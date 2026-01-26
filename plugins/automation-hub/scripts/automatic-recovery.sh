#!/usr/bin/env bash
# Automatic Recovery Orchestrator
# Implements retry logic, circuit breakers, and durable execution for automation workflows

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Configuration ===

RECOVERY_ENABLED=$(get_config_value ".auto_cleanup.automatic_recovery.enabled" "true")
MAX_RETRIES=$(get_config_value ".auto_cleanup.automatic_recovery.max_retries" "3")
INITIAL_BACKOFF=$(get_config_value ".auto_cleanup.automatic_recovery.initial_backoff_ms" "1000")
MAX_BACKOFF=$(get_config_value ".auto_cleanup.automatic_recovery.max_backoff_ms" "30000")
BACKOFF_MULTIPLIER=$(get_config_value ".auto_cleanup.automatic_recovery.backoff_multiplier" "2")
ENABLE_JITTER=$(get_config_value ".auto_cleanup.automatic_recovery.enable_jitter" "true")

RECOVERY_DIR="${HOME}/.claude/automation-hub/recovery"
FAILED_TASKS_FILE="${RECOVERY_DIR}/failed-tasks.jsonl"
RECOVERY_LOG="${RECOVERY_DIR}/recovery-log.jsonl"

mkdir -p "${RECOVERY_DIR}"

# === Error Classification ===

classify_error() {
    local error_message="$1"
    local exit_code="${2:-1}"

    # Transient errors (retry automatically)
    if echo "${error_message}" | grep -qi "timeout\|connection refused\|network\|temporary"; then
        echo "transient"
        return
    fi

    # Intermittent errors (retry with backoff)
    if echo "${error_message}" | grep -qi "rate limit\|too many requests\|service unavailable"; then
        echo "intermittent"
        return
    fi

    # Permanent errors (do not retry)
    if echo "${error_message}" | grep -qi "not found\|forbidden\|unauthorized\|invalid"; then
        echo "permanent"
        return
    fi

    # Default: intermittent (retry with caution)
    echo "intermittent"
}

# === Exponential Backoff with Jitter ===

calculate_backoff() {
    local attempt="$1"
    local base_backoff="${2:-${INITIAL_BACKOFF}}"
    local max_backoff="${3:-${MAX_BACKOFF}}"
    local multiplier="${4:-${BACKOFF_MULTIPLIER}}"

    # Calculate exponential backoff: base * multiplier^attempt
    local backoff
    backoff=$(echo "${base_backoff} * (${multiplier} ^ ${attempt})" | bc -l | cut -d. -f1)

    # Cap at max_backoff
    if [[ ${backoff} -gt ${max_backoff} ]]; then
        backoff=${max_backoff}
    fi

    # Add jitter (random 0-25% of backoff) if enabled
    if [[ "${ENABLE_JITTER}" == "true" ]]; then
        local jitter
        jitter=$(( RANDOM % (backoff / 4) ))
        backoff=$((backoff + jitter))
    fi

    echo "${backoff}"
}

# === Retry with Backoff ===

retry_with_backoff() {
    local task_id="$1"
    local command="$2"
    local max_retries="${3:-${MAX_RETRIES}}"

    local attempt=0
    local success=false

    while [[ ${attempt} -lt ${max_retries} ]]; do
        log_info "Attempt $((attempt + 1))/${max_retries} for task ${task_id}"

        # Execute command
        local output
        local exit_code=0
        output=$(eval "${command}" 2>&1) || exit_code=$?

        if [[ ${exit_code} -eq 0 ]]; then
            log_success "Task ${task_id} succeeded on attempt $((attempt + 1))"
            success=true

            # Log success
            log_recovery_event "${task_id}" "success" "$((attempt + 1))" "${output}"
            break
        else
            # Classify error
            local error_type
            error_type=$(classify_error "${output}" "${exit_code}")

            log_warning "Task ${task_id} failed (attempt $((attempt + 1))): ${error_type} error"

            # Permanent errors - don't retry
            if [[ "${error_type}" == "permanent" ]]; then
                log_error "Permanent error detected, aborting retries"
                log_recovery_event "${task_id}" "permanent_failure" "$((attempt + 1))" "${output}"
                return 1
            fi

            # Check circuit breaker
            if ! "${SCRIPT_DIR}/circuit-breaker-manager.sh" check "${task_id}"; then
                log_error "Circuit breaker open for ${task_id}, aborting retries"
                log_recovery_event "${task_id}" "circuit_breaker_open" "$((attempt + 1))" "${output}"
                return 1
            fi

            # Calculate backoff for next attempt
            if [[ $((attempt + 1)) -lt ${max_retries} ]]; then
                local backoff_ms
                backoff_ms=$(calculate_backoff "${attempt}")
                local backoff_seconds
                backoff_seconds=$(echo "scale=2; ${backoff_ms} / 1000" | bc -l)

                log_info "Waiting ${backoff_seconds}s before retry (exponential backoff with jitter)"
                sleep "${backoff_seconds}"
            fi

            # Record failure
            "${SCRIPT_DIR}/circuit-breaker-manager.sh" record-failure "${task_id}"
        fi

        attempt=$((attempt + 1))
    done

    if [[ "${success}" == "true" ]]; then
        # Reset circuit breaker on success
        "${SCRIPT_DIR}/circuit-breaker-manager.sh" record-success "${task_id}"
        return 0
    else
        log_error "Task ${task_id} failed after ${max_retries} attempts"
        log_recovery_event "${task_id}" "max_retries_exceeded" "${attempt}" "Failed after ${max_retries} attempts"

        # Store for manual redrive
        store_failed_task "${task_id}" "${command}" "${attempt}"
        return 1
    fi
}

# === Failed Task Storage (for manual redrive) ===

store_failed_task() {
    local task_id="$1"
    local command="$2"
    local attempts="$3"

    local timestamp
    timestamp=$(date -u +%s)

    local entry
    entry=$(jq -n \
        --arg ts "${timestamp}" \
        --arg tid "${task_id}" \
        --arg cmd "${command}" \
        --arg att "${attempts}" \
        '{
            timestamp: ($ts | tonumber),
            task_id: $tid,
            command: $cmd,
            attempts: ($att | tonumber),
            status: "failed",
            recoverable: true
        }')

    echo "${entry}" >> "${FAILED_TASKS_FILE}"
    log_info "Stored failed task ${task_id} for manual redrive"
}

# === Log Recovery Event ===

log_recovery_event() {
    local task_id="$1"
    local event_type="$2"  # success, permanent_failure, circuit_breaker_open, max_retries_exceeded
    local attempts="$3"
    local details="$4"

    local timestamp
    timestamp=$(date -u +%s)

    local entry
    entry=$(jq -n \
        --arg ts "${timestamp}" \
        --arg tid "${task_id}" \
        --arg type "${event_type}" \
        --arg att "${attempts}" \
        --arg details "${details}" \
        '{
            timestamp: ($ts | tonumber),
            task_id: $tid,
            event_type: $type,
            attempts: ($att | tonumber),
            details: $details
        }')

    echo "${entry}" >> "${RECOVERY_LOG}"
}

# === Manual Redrive ===

redrive_failed_tasks() {
    if [[ ! -f "${FAILED_TASKS_FILE}" ]]; then
        log_info "No failed tasks to redrive"
        return 0
    fi

    log_info "Redriving failed tasks..."

    local count=0
    local success_count=0

    while IFS= read -r task_entry; do
        local task_id
        task_id=$(echo "${task_entry}" | jq -r '.task_id')
        local command
        command=$(echo "${task_entry}" | jq -r '.command')

        log_info "Redriving task: ${task_id}"

        if retry_with_backoff "${task_id}" "${command}" 1; then
            success_count=$((success_count + 1))
            # Remove from failed tasks file
            grep -v "\"task_id\": \"${task_id}\"" "${FAILED_TASKS_FILE}" > "${FAILED_TASKS_FILE}.tmp" || true
            mv "${FAILED_TASKS_FILE}.tmp" "${FAILED_TASKS_FILE}"
        fi

        count=$((count + 1))
    done < "${FAILED_TASKS_FILE}"

    log_success "Redrive complete: ${success_count}/${count} tasks recovered"
}

# === Recovery Statistics ===

recovery_stats() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  AUTOMATIC RECOVERY STATISTICS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ ! -f "${RECOVERY_LOG}" ]]; then
        echo "No recovery events logged yet."
        echo ""
        echo "2026 Research Foundation:"
        echo "  ✅ Exponential backoff with jitter"
        echo "  ✅ Circuit breakers for cascading failure prevention"
        echo "  ✅ Error classification (transient, intermittent, permanent)"
        echo "  ✅ Hybrid retry + manual redrive strategy"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        return
    fi

    local total_events
    total_events=$(wc -l < "${RECOVERY_LOG}" | tr -d ' ')

    local success_count
    success_count=$(grep -c '"event_type": "success"' "${RECOVERY_LOG}" || echo 0)

    local circuit_breaker_count
    circuit_breaker_count=$(grep -c '"event_type": "circuit_breaker_open"' "${RECOVERY_LOG}" || echo 0)

    local permanent_failure_count
    permanent_failure_count=$(grep -c '"event_type": "permanent_failure"' "${RECOVERY_LOG}" || echo 0)

    local max_retries_count
    max_retries_count=$(grep -c '"event_type": "max_retries_exceeded"' "${RECOVERY_LOG}" || echo 0)

    echo "Total Recovery Events: ${total_events}"
    echo ""
    echo "Event Breakdown:"
    echo "  ✓ Successful recoveries: ${success_count}"
    echo "  ⚡ Circuit breaker activations: ${circuit_breaker_count}"
    echo "  ✗ Permanent failures: ${permanent_failure_count}"
    echo "  ⏸ Max retries exceeded: ${max_retries_count}"
    echo ""

    if [[ -f "${FAILED_TASKS_FILE}" ]]; then
        local failed_count
        failed_count=$(wc -l < "${FAILED_TASKS_FILE}" | tr -d ' ')
        echo "Failed Tasks Pending Redrive: ${failed_count}"
    else
        echo "Failed Tasks Pending Redrive: 0"
    fi

    echo ""
    echo "2026 Research Foundation:"
    echo "  ✅ Exponential backoff with jitter"
    echo "  ✅ Circuit breakers for cascading failure prevention"
    echo "  ✅ Error classification (transient, intermittent, permanent)"
    echo "  ✅ Hybrid retry + manual redrive strategy"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# === MAIN ===

main() {
    local command="${1:-stats}"
    shift || true

    if [[ "${RECOVERY_ENABLED}" != "true" ]]; then
        log_warning "Automatic recovery is disabled in config"
        return 0
    fi

    case "${command}" in
        retry)
            # Usage: automatic-recovery.sh retry <task_id> <command> [max_retries]
            local task_id="$1"
            local task_command="$2"
            local max_retries="${3:-${MAX_RETRIES}}"
            retry_with_backoff "${task_id}" "${task_command}" "${max_retries}"
            ;;
        redrive)
            redrive_failed_tasks
            ;;
        stats)
            recovery_stats
            ;;
        *)
            cat <<EOF
Automatic Recovery Orchestrator

RETRY WITH BACKOFF:
  retry <task_id> <command> [max_retries]
    Executes command with exponential backoff retry logic
    Example: automatic-recovery.sh retry "cleanup-task-1" "./check-cleanup-safe.sh" 3

MANUAL REDRIVE:
  redrive
    Reattempts all failed tasks stored for manual intervention

STATISTICS:
  stats
    Shows recovery event statistics and pending failed tasks

Features:
  • Exponential backoff with jitter (prevents thundering herd)
  • Error classification (transient, intermittent, permanent)
  • Circuit breaker integration (prevents cascading failures)
  • Hybrid strategy (auto-retry + manual redrive)
  • Durable task storage (failed tasks persist for recovery)

2026 Research:
  - Idempotent workflows that self-heal
  - Temporal-inspired durable execution
  - AWS Step Functions redrive pattern
  - Circuit breakers with exponential backoff
EOF
            ;;
    esac
}

main "$@"
