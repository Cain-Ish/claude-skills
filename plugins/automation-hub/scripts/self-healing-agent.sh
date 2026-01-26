#!/usr/bin/env bash
# Self-Healing Agent - Autonomous error detection and recovery
# Based on 2026 research: agentic remediation, autonomous recovery patterns
# Failures become triggers for repair agents, not system crashes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Configuration ===

HEALING_DIR="${HOME}/.claude/automation-hub/self-healing"
ERROR_LOG="${HEALING_DIR}/errors.jsonl"
RECOVERY_HISTORY="${HEALING_DIR}/recovery-history.jsonl"
HEALTH_CHECKS="${HEALING_DIR}/health-checks.json"

# Recovery strategies
MAX_RETRY_ATTEMPTS=3
RETRY_BACKOFF_BASE=2  # Exponential backoff: 2, 4, 8 seconds
CIRCUIT_BREAKER_THRESHOLD=5  # Failures before circuit opens
CIRCUIT_BREAKER_TIMEOUT=300  # 5 minutes before retry

# === Initialize ===

mkdir -p "${HEALING_DIR}"

# === Error Detection ===

detect_error() {
    local error_type="$1"
    local error_message="$2"
    local error_context="$3"

    local timestamp
    timestamp=$(date -u +%s)

    # Log error
    local error_entry
    error_entry=$(jq -n \
        --arg timestamp "${timestamp}" \
        --arg type "${error_type}" \
        --arg message "${error_message}" \
        --arg context "${error_context}" \
        '{
            timestamp: ($timestamp | tonumber),
            error_type: $type,
            message: $message,
            context: $context,
            detected_at: (now | tostring)
        }')

    echo "${error_entry}" >> "${ERROR_LOG}"

    debug "Error detected: ${error_type} - ${error_message}"

    # Trigger recovery agent
    trigger_recovery_agent "${error_type}" "${error_message}" "${error_context}"
}

# === Recovery Agent (Autonomous) ===

trigger_recovery_agent() {
    local error_type="$1"
    local error_message="$2"
    local error_context="$3"

    echo "🔧 Self-Healing Agent Activated"
    echo "  Error: ${error_type}"
    echo "  Message: ${error_message}"
    echo ""

    # Determine recovery strategy based on error type
    local recovery_strategy
    recovery_strategy=$(classify_recovery_strategy "${error_type}" "${error_message}")

    echo "  Strategy: ${recovery_strategy}"
    echo ""

    case "${recovery_strategy}" in
        auto_retry)
            execute_auto_retry "${error_type}" "${error_context}"
            ;;

        alternative_path)
            execute_alternative_path "${error_type}" "${error_context}"
            ;;

        graceful_degradation)
            execute_graceful_degradation "${error_type}" "${error_context}"
            ;;

        circuit_breaker)
            execute_circuit_breaker "${error_type}" "${error_context}"
            ;;

        rollback)
            execute_rollback "${error_type}" "${error_context}"
            ;;

        escalate)
            execute_escalation "${error_type}" "${error_message}" "${error_context}"
            ;;

        *)
            echo "⚠️  Unknown recovery strategy: ${recovery_strategy}"
            execute_escalation "${error_type}" "${error_message}" "${error_context}"
            ;;
    esac
}

# === Recovery Strategy Classification ===

classify_recovery_strategy() {
    local error_type="$1"
    local error_message="$2"

    # Classify error and determine best recovery approach
    case "${error_type}" in
        network_timeout|api_timeout)
            echo "auto_retry"
            ;;

        plugin_not_found|agent_not_available)
            echo "alternative_path"
            ;;

        rate_limit_exceeded)
            echo "graceful_degradation"
            ;;

        repeated_failure)
            echo "circuit_breaker"
            ;;

        corrupt_state|invalid_config)
            echo "rollback"
            ;;

        unknown_error|critical_failure)
            echo "escalate"
            ;;

        *)
            # Check message for patterns
            if echo "${error_message}" | grep -qi "timeout\|timed out"; then
                echo "auto_retry"
            elif echo "${error_message}" | grep -qi "not found\|missing\|unavailable"; then
                echo "alternative_path"
            elif echo "${error_message}" | grep -qi "rate limit\|quota exceeded"; then
                echo "graceful_degradation"
            else
                echo "escalate"
            fi
            ;;
    esac
}

# === Auto Retry with Exponential Backoff ===

execute_auto_retry() {
    local error_type="$1"
    local context="$2"

    echo "🔄 Auto-Retry Strategy (Exponential Backoff)"

    for attempt in $(seq 1 ${MAX_RETRY_ATTEMPTS}); do
        echo "  Attempt ${attempt}/${MAX_RETRY_ATTEMPTS}..."

        # Calculate backoff delay
        local delay
        delay=$((RETRY_BACKOFF_BASE ** (attempt - 1)))

        if [[ ${attempt} -gt 1 ]]; then
            echo "  Waiting ${delay}s before retry..."
            sleep ${delay}
        fi

        # Attempt recovery (simulated)
        if attempt_operation "${context}"; then
            echo "  ✓ Recovery successful on attempt ${attempt}"
            log_recovery_success "${error_type}" "auto_retry" "${attempt}"
            return 0
        else
            echo "  ✗ Attempt ${attempt} failed"
        fi
    done

    echo "  ⚠️  All ${MAX_RETRY_ATTEMPTS} retry attempts exhausted"
    log_recovery_failure "${error_type}" "auto_retry" "max_attempts_exceeded"

    # Escalate after max retries
    execute_escalation "${error_type}" "Max retries exceeded" "${context}"
}

# === Alternative Execution Path ===

execute_alternative_path() {
    local error_type="$1"
    local context="$2"

    echo "🔀 Alternative Path Strategy"

    # Try alternative approaches
    local -a alternatives=(
        "fallback_plugin"
        "degraded_mode"
        "cached_response"
    )

    for alternative in "${alternatives[@]}"; do
        echo "  Trying: ${alternative}..."

        if attempt_alternative "${alternative}" "${context}"; then
            echo "  ✓ Alternative path successful: ${alternative}"
            log_recovery_success "${error_type}" "alternative_path" "${alternative}"
            return 0
        else
            echo "  ✗ ${alternative} failed"
        fi
    done

    echo "  ⚠️  No alternative paths succeeded"
    log_recovery_failure "${error_type}" "alternative_path" "no_alternatives_available"

    # Fallback to graceful degradation
    execute_graceful_degradation "${error_type}" "${context}"
}

# === Graceful Degradation ===

execute_graceful_degradation() {
    local error_type="$1"
    local context="$2"

    echo "📉 Graceful Degradation Strategy"
    echo "  Reducing functionality to maintain service..."

    # Degradation steps (ordered by severity)
    local -a degradation_levels=(
        "disable_non_essential_features"
        "use_cached_data_only"
        "read_only_mode"
        "minimal_functionality"
    )

    for level in "${degradation_levels[@]}"; do
        echo "  Applying: ${level}..."

        if apply_degradation "${level}" "${context}"; then
            echo "  ✓ Degraded mode active: ${level}"
            log_recovery_success "${error_type}" "graceful_degradation" "${level}"

            # Schedule health check to restore full functionality
            schedule_health_check "restore_functionality" 300  # 5 minutes

            return 0
        fi
    done

    echo "  ⚠️  Could not establish degraded mode"
    log_recovery_failure "${error_type}" "graceful_degradation" "degradation_failed"
}

# === Circuit Breaker Pattern ===

execute_circuit_breaker() {
    local error_type="$1"
    local context="$2"

    echo "🔌 Circuit Breaker Strategy"

    # Check if circuit should open
    local recent_failures
    recent_failures=$(count_recent_failures "${error_type}" 300)  # Last 5 minutes

    if [[ ${recent_failures} -ge ${CIRCUIT_BREAKER_THRESHOLD} ]]; then
        echo "  ⚠️  Circuit breaker OPEN (${recent_failures} failures)"
        echo "  Suspending operations for ${CIRCUIT_BREAKER_TIMEOUT}s..."

        # Open circuit
        open_circuit "${error_type}" "${CIRCUIT_BREAKER_TIMEOUT}"

        log_recovery_success "${error_type}" "circuit_breaker" "circuit_opened"

        # Schedule circuit half-open check
        schedule_health_check "circuit_half_open:${error_type}" "${CIRCUIT_BREAKER_TIMEOUT}"

        return 0
    else
        echo "  Circuit breaker threshold not reached (${recent_failures}/${CIRCUIT_BREAKER_THRESHOLD})"
        # Try alternative recovery
        execute_auto_retry "${error_type}" "${context}"
    fi
}

# === Rollback to Last Known Good State ===

execute_rollback() {
    local error_type="$1"
    local context="$2"

    echo "⏪ Rollback Strategy"
    echo "  Restoring to last known good state..."

    # Check for git checkpoint
    if [[ -f "${HOME}/.claude/automation-hub/checkpoints/latest" ]]; then
        local checkpoint
        checkpoint=$(cat "${HOME}/.claude/automation-hub/checkpoints/latest")

        echo "  Found checkpoint: ${checkpoint}"
        echo "  Rolling back..."

        if bash "${SCRIPT_DIR}/rollback-fixes.sh" 2>/dev/null; then
            echo "  ✓ Rollback successful"
            log_recovery_success "${error_type}" "rollback" "git_checkpoint"
            return 0
        else
            echo "  ✗ Rollback failed"
        fi
    else
        echo "  ⚠️  No checkpoint available for rollback"
    fi

    # Try config rollback
    if rollback_config; then
        echo "  ✓ Configuration rolled back"
        log_recovery_success "${error_type}" "rollback" "config_restore"
        return 0
    fi

    log_recovery_failure "${error_type}" "rollback" "no_rollback_available"
}

# === Escalation (Human Intervention Required) ===

execute_escalation() {
    local error_type="$1"
    local error_message="$2"
    local context="$3"

    echo "🚨 Escalation Required"
    echo ""
    echo "  Error Type: ${error_type}"
    echo "  Message: ${error_message}"
    echo "  Context: ${context}"
    echo ""
    echo "  Autonomous recovery exhausted. Human intervention required."
    echo ""
    echo "  Actions taken:"
    echo "  - Error logged: ${ERROR_LOG}"
    echo "  - Recovery history: ${RECOVERY_HISTORY}"
    echo ""
    echo "  Suggested next steps:"
    echo "  1. Review error log: cat ${ERROR_LOG} | tail -10"
    echo "  2. Check recovery history: cat ${RECOVERY_HISTORY} | tail -10"
    echo "  3. Run diagnostics: /automation debug"
    echo "  4. Manual intervention required"

    log_recovery_failure "${error_type}" "escalate" "human_intervention_required"
}

# === Helper Functions ===

attempt_operation() {
    local context="$1"

    # Simulated operation attempt
    # In production, this would retry the actual failed operation

    # For demonstration, random success/failure
    local random
    random=$((RANDOM % 100))

    if [[ ${random} -gt 30 ]]; then
        return 0  # Success
    else
        return 1  # Failure
    fi
}

attempt_alternative() {
    local alternative="$1"
    local context="$2"

    # Simulated alternative attempt
    case "${alternative}" in
        fallback_plugin)
            # Check if fallback plugin exists
            return 1  # Not available in demo
            ;;
        degraded_mode)
            return 0  # Always available
            ;;
        cached_response)
            # Check cache
            if bash "${SCRIPT_DIR}/performance-cache.sh" lookup response "emergency" 2>/dev/null; then
                return 0
            else
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

apply_degradation() {
    local level="$1"
    local context="$2"

    # Apply degradation level
    debug "Applying degradation level: ${level}"

    # In production, this would actually modify system behavior
    # For now, just return success for demonstration
    return 0
}

count_recent_failures() {
    local error_type="$1"
    local time_window="$2"

    if [[ ! -f "${ERROR_LOG}" ]]; then
        echo "0"
        return
    fi

    local cutoff_time
    cutoff_time=$(($(date +%s) - time_window))

    local count
    count=$(jq -s --arg type "${error_type}" --arg cutoff "${cutoff_time}" \
        'map(select(.error_type == $type and .timestamp >= ($cutoff | tonumber))) | length' \
        "${ERROR_LOG}" 2>/dev/null || echo "0")

    echo "${count}"
}

open_circuit() {
    local error_type="$1"
    local timeout="$2"

    # Mark circuit as open in health checks
    if [[ ! -f "${HEALTH_CHECKS}" ]]; then
        echo '{"circuits":{}}' > "${HEALTH_CHECKS}"
    fi

    local expire_at
    expire_at=$(($(date +%s) + timeout))

    local health_data
    health_data=$(jq --arg type "${error_type}" --arg expire "${expire_at}" \
        '.circuits[$type] = {
            status: "open",
            opened_at: (now | tostring),
            expires_at: ($expire | tonumber)
        }' "${HEALTH_CHECKS}")

    echo "${health_data}" > "${HEALTH_CHECKS}"
}

rollback_config() {
    # Rollback configuration to default
    local default_config="${SCRIPT_DIR}/../config/default-config.json"

    if [[ -f "${default_config}" ]]; then
        cp "${default_config}" "${HOME}/.claude/automation-hub/config.json"
        return 0
    else
        return 1
    fi
}

schedule_health_check() {
    local check_type="$1"
    local delay_seconds="$2"

    debug "Scheduled health check: ${check_type} in ${delay_seconds}s"

    # In production, this would use cron or systemd timer
    # For now, just log the scheduled check
    log_metric "health_check_scheduled" "$(jq -n \
        --arg type "${check_type}" \
        --arg delay "${delay_seconds}" \
        '{check_type: $type, delay_seconds: ($delay | tonumber)}')"
}

log_recovery_success() {
    local error_type="$1"
    local strategy="$2"
    local details="$3"

    local timestamp
    timestamp=$(date -u +%s)

    local recovery_entry
    recovery_entry=$(jq -n \
        --arg timestamp "${timestamp}" \
        --arg type "${error_type}" \
        --arg strategy "${strategy}" \
        --arg details "${details}" \
        '{
            timestamp: ($timestamp | tonumber),
            error_type: $type,
            recovery_strategy: $strategy,
            result: "success",
            details: $details
        }')

    echo "${recovery_entry}" >> "${RECOVERY_HISTORY}"

    # Log metric
    log_metric "self_healing_success" "$(jq -n \
        --arg type "${error_type}" \
        --arg strategy "${strategy}" \
        '{error_type: $type, strategy: $strategy}')"
}

log_recovery_failure() {
    local error_type="$1"
    local strategy="$2"
    local reason="$3"

    local timestamp
    timestamp=$(date -u +%s)

    local recovery_entry
    recovery_entry=$(jq -n \
        --arg timestamp "${timestamp}" \
        --arg type "${error_type}" \
        --arg strategy "${strategy}" \
        --arg reason "${reason}" \
        '{
            timestamp: ($timestamp | tonumber),
            error_type: $type,
            recovery_strategy: $strategy,
            result: "failure",
            reason: $reason
        }')

    echo "${recovery_entry}" >> "${RECOVERY_HISTORY}"

    # Log metric
    log_metric "self_healing_failure" "$(jq -n \
        --arg type "${error_type}" \
        --arg strategy "${strategy}" \
        --arg reason "${reason}" \
        '{error_type: $type, strategy: $strategy, reason: $reason}')"
}

# === Recovery Statistics ===

recovery_stats() {
    echo "📊 Self-Healing Statistics"
    echo ""

    if [[ ! -f "${RECOVERY_HISTORY}" ]]; then
        echo "No recovery history available yet"
        return 0
    fi

    local total_recoveries
    total_recoveries=$(wc -l < "${RECOVERY_HISTORY}" | tr -d ' ')

    local successful
    successful=$(jq -s 'map(select(.result == "success")) | length' "${RECOVERY_HISTORY}")

    local failed
    failed=$(jq -s 'map(select(.result == "failure")) | length' "${RECOVERY_HISTORY}")

    local success_rate
    if [[ ${total_recoveries} -gt 0 ]]; then
        success_rate=$(echo "scale=1; (${successful} / ${total_recoveries}) * 100" | bc)
    else
        success_rate="0"
    fi

    echo "┌─ Overall ───────────────────────────────┐"
    echo "│ Total Recovery Attempts: ${total_recoveries}"
    echo "│ Successful: ${successful}"
    echo "│ Failed: ${failed}"
    printf "│ Success Rate: %.1f%%\n" "${success_rate}"
    echo "└─────────────────────────────────────────┘"
    echo ""

    # By strategy
    echo "┌─ By Strategy ───────────────────────────┐"
    jq -s 'group_by(.recovery_strategy) |
        map({
            strategy: .[0].recovery_strategy,
            total: length,
            successful: (map(select(.result == "success")) | length)
        }) |
        .[] |
        "│ " + .strategy + ": " + (.successful | tostring) + "/" + (.total | tostring)' \
        "${RECOVERY_HISTORY}"
    echo "└─────────────────────────────────────────┘"
}

# === Main ===

main() {
    local command="${1:-stats}"
    shift || true

    case "${command}" in
        detect)
            if [[ $# -lt 2 ]]; then
                echo "Usage: self-healing-agent.sh detect <error_type> <error_message> [context]"
                exit 1
            fi

            local error_type="$1"
            local error_message="$2"
            local context="${3:-unknown}"

            detect_error "${error_type}" "${error_message}" "${context}"
            ;;

        stats)
            recovery_stats
            ;;

        test)
            echo "🧪 Testing Self-Healing Agent"
            echo ""

            # Simulate various error scenarios
            local -a test_cases=(
                "network_timeout:Connection timed out:api_call"
                "plugin_not_found:Multi-agent plugin unavailable:routing"
                "rate_limit_exceeded:API quota exceeded:decision"
                "repeated_failure:5th consecutive failure:auto_routing"
            )

            for test_case in "${test_cases[@]}"; do
                IFS=':' read -r error_type error_msg context <<< "${test_case}"

                echo "Test Case: ${error_type}"
                detect_error "${error_type}" "${error_msg}" "${context}"
                echo ""
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo ""
            done

            recovery_stats
            ;;

        *)
            cat <<'EOF'
Self-Healing Agent - Autonomous error detection and recovery

USAGE:
  self-healing-agent.sh detect <type> <message> [context]
  self-healing-agent.sh stats
  self-healing-agent.sh test

RECOVERY STRATEGIES:
  auto_retry           Exponential backoff retry (network timeouts)
  alternative_path     Try fallback plugins or degraded mode
  graceful_degradation Reduce functionality to maintain service
  circuit_breaker      Suspend operations after repeated failures
  rollback             Restore to last known good state
  escalate             Require human intervention

EXAMPLES:
  self-healing-agent.sh detect network_timeout "Connection timed out" "api_call"
  self-healing-agent.sh stats
  self-healing-agent.sh test

RESEARCH:
  - Algomox: Self-healing infrastructure with agentic AI
  - 2026 paradigm: Failures trigger repair agents, not alerts
  - Error handling separates experimental from production systems
  - Autonomous remediation before human involvement

EOF
            ;;
    esac
}

# Execute
main "$@"

exit 0
