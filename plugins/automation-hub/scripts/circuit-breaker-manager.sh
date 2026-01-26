#!/usr/bin/env bash
# Circuit Breaker Manager
# Prevents cascading failures by opening circuit after failure threshold

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Configuration ===

FAILURE_THRESHOLD=$(get_config_value ".auto_cleanup.circuit_breaker.failure_threshold" "3")
HALF_OPEN_AFTER_SECONDS=$(get_config_value ".auto_cleanup.circuit_breaker.half_open_after_seconds" "60")
SUCCESS_THRESHOLD=$(get_config_value ".auto_cleanup.circuit_breaker.success_threshold" "2")

CIRCUIT_BREAKER_DIR="${HOME}/.claude/automation-hub/circuit-breakers"
mkdir -p "${CIRCUIT_BREAKER_DIR}"

# Circuit states: CLOSED, OPEN, HALF_OPEN
# CLOSED: Normal operation, requests pass through
# OPEN: Circuit tripped, requests fail immediately
# HALF_OPEN: Testing if service recovered, limited requests

# === Circuit Breaker State ===

get_circuit_state() {
    local circuit_id="$1"
    local state_file="${CIRCUIT_BREAKER_DIR}/${circuit_id}.json"

    if [[ ! -f "${state_file}" ]]; then
        # Initialize new circuit as CLOSED
        jq -n \
            --arg id "${circuit_id}" \
            --arg ts "$(date -u +%s)" \
            '{
                circuit_id: $id,
                state: "CLOSED",
                failure_count: 0,
                success_count: 0,
                last_failure_time: null,
                opened_at: null,
                last_state_change: ($ts | tonumber)
            }' > "${state_file}"
    fi

    cat "${state_file}"
}

update_circuit_state() {
    local circuit_id="$1"
    local new_state="$2"
    local state_file="${CIRCUIT_BREAKER_DIR}/${circuit_id}.json"

    local current_state
    current_state=$(get_circuit_state "${circuit_id}")

    local timestamp
    timestamp=$(date -u +%s)

    local updated_state
    updated_state=$(echo "${current_state}" | jq \
        --arg state "${new_state}" \
        --arg ts "${timestamp}" \
        '.state = $state | .last_state_change = ($ts | tonumber)')

    if [[ "${new_state}" == "OPEN" ]]; then
        updated_state=$(echo "${updated_state}" | jq \
            --arg ts "${timestamp}" \
            '.opened_at = ($ts | tonumber)')
    fi

    echo "${updated_state}" > "${state_file}"
}

# === Record Events ===

record_failure() {
    local circuit_id="$1"
    local state_file="${CIRCUIT_BREAKER_DIR}/${circuit_id}.json"

    local current_state
    current_state=$(get_circuit_state "${circuit_id}")

    local state
    state=$(echo "${current_state}" | jq -r '.state')

    local timestamp
    timestamp=$(date -u +%s)

    # Update failure count
    local updated_state
    updated_state=$(echo "${current_state}" | jq \
        --arg ts "${timestamp}" \
        '.failure_count += 1 | .success_count = 0 | .last_failure_time = ($ts | tonumber)')

    local failure_count
    failure_count=$(echo "${updated_state}" | jq -r '.failure_count')

    # Check if threshold exceeded
    if [[ "${state}" == "CLOSED" ]] && [[ ${failure_count} -ge ${FAILURE_THRESHOLD} ]]; then
        log_warning "Circuit breaker ${circuit_id}: OPEN (${failure_count} consecutive failures)"
        updated_state=$(echo "${updated_state}" | jq \
            --arg ts "${timestamp}" \
            '.state = "OPEN" | .opened_at = ($ts | tonumber)')

        # Log metric
        log_metric "circuit_breaker_open" "$(jq -n --arg id "${circuit_id}" '{circuit_id: $id}')"
    fi

    echo "${updated_state}" > "${state_file}"
}

record_success() {
    local circuit_id="$1"
    local state_file="${CIRCUIT_BREAKER_DIR}/${circuit_id}.json"

    local current_state
    current_state=$(get_circuit_state "${circuit_id}")

    local state
    state=$(echo "${current_state}" | jq -r '.state')

    # Update success count, reset failure count
    local updated_state
    updated_state=$(echo "${current_state}" | jq \
        '.success_count += 1 | .failure_count = 0')

    local success_count
    success_count=$(echo "${updated_state}" | jq -r '.success_count')

    # Transition HALF_OPEN → CLOSED after success threshold
    if [[ "${state}" == "HALF_OPEN" ]] && [[ ${success_count} -ge ${SUCCESS_THRESHOLD} ]]; then
        log_success "Circuit breaker ${circuit_id}: CLOSED (${success_count} consecutive successes)"
        local timestamp
        timestamp=$(date -u +%s)
        updated_state=$(echo "${updated_state}" | jq \
            --arg ts "${timestamp}" \
            '.state = "CLOSED" | .opened_at = null | .last_state_change = ($ts | tonumber)')

        # Log metric
        log_metric "circuit_breaker_closed" "$(jq -n --arg id "${circuit_id}" '{circuit_id: $id}')"
    elif [[ "${state}" == "CLOSED" ]]; then
        # Already closed, just reset counters
        updated_state=$(echo "${updated_state}" | jq '.success_count = 0')
    fi

    echo "${updated_state}" > "${state_file}"
}

# === Check Circuit ===

check_circuit() {
    local circuit_id="$1"

    local current_state
    current_state=$(get_circuit_state "${circuit_id}")

    local state
    state=$(echo "${current_state}" | jq -r '.state')

    if [[ "${state}" == "CLOSED" ]]; then
        # Circuit is closed, allow requests
        return 0
    elif [[ "${state}" == "OPEN" ]]; then
        # Check if enough time has passed to move to HALF_OPEN
        local opened_at
        opened_at=$(echo "${current_state}" | jq -r '.opened_at')
        local current_time
        current_time=$(date -u +%s)
        local elapsed=$((current_time - opened_at))

        if [[ ${elapsed} -ge ${HALF_OPEN_AFTER_SECONDS} ]]; then
            # Transition to HALF_OPEN
            log_info "Circuit breaker ${circuit_id}: HALF_OPEN (testing recovery)"
            update_circuit_state "${circuit_id}" "HALF_OPEN"
            return 0  # Allow limited requests
        else
            # Still open
            debug "Circuit breaker ${circuit_id} is OPEN (${elapsed}s/${HALF_OPEN_AFTER_SECONDS}s elapsed)"
            return 1  # Fail fast
        fi
    elif [[ "${state}" == "HALF_OPEN" ]]; then
        # Allow limited requests to test recovery
        return 0
    fi
}

# === Reset Circuit ===

reset_circuit() {
    local circuit_id="$1"
    local state_file="${CIRCUIT_BREAKER_DIR}/${circuit_id}.json"

    log_info "Manually resetting circuit breaker: ${circuit_id}"

    local timestamp
    timestamp=$(date -u +%s)

    jq -n \
        --arg id "${circuit_id}" \
        --arg ts "${timestamp}" \
        '{
            circuit_id: $id,
            state: "CLOSED",
            failure_count: 0,
            success_count: 0,
            last_failure_time: null,
            opened_at: null,
            last_state_change: ($ts | tonumber)
        }' > "${state_file}"

    log_success "Circuit breaker ${circuit_id} reset to CLOSED"
}

# === Statistics ===

circuit_stats() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  CIRCUIT BREAKER STATISTICS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    local circuits=()
    for file in "${CIRCUIT_BREAKER_DIR}"/*.json; do
        if [[ -f "${file}" ]]; then
            circuits+=("${file}")
        fi
    done

    if [[ ${#circuits[@]} -eq 0 ]]; then
        echo "No circuit breakers registered yet."
        echo ""
        echo "Configuration:"
        echo "  Failure threshold: ${FAILURE_THRESHOLD}"
        echo "  Half-open after: ${HALF_OPEN_AFTER_SECONDS}s"
        echo "  Success threshold: ${SUCCESS_THRESHOLD}"
        echo ""
        echo "2026 Research Foundation:"
        echo "  ✅ Prevents cascading failures"
        echo "  ✅ Fail fast when service is down"
        echo "  ✅ Automatic recovery testing (HALF_OPEN state)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        return
    fi

    local closed_count=0
    local open_count=0
    local half_open_count=0

    for circuit_file in "${circuits[@]}"; do
        local circuit_data
        circuit_data=$(cat "${circuit_file}")

        local circuit_id
        circuit_id=$(echo "${circuit_data}" | jq -r '.circuit_id')
        local state
        state=$(echo "${circuit_data}" | jq -r '.state')
        local failure_count
        failure_count=$(echo "${circuit_data}" | jq -r '.failure_count')

        case "${state}" in
            CLOSED) closed_count=$((closed_count + 1)) ;;
            OPEN) open_count=$((open_count + 1)) ;;
            HALF_OPEN) half_open_count=$((half_open_count + 1)) ;;
        esac

        local status_icon="✓"
        if [[ "${state}" == "OPEN" ]]; then
            status_icon="✗"
        elif [[ "${state}" == "HALF_OPEN" ]]; then
            status_icon="⚠️"
        fi

        echo "${status_icon} ${circuit_id}: ${state} (failures: ${failure_count})"
    done

    echo ""
    echo "Summary:"
    echo "  CLOSED (healthy): ${closed_count}"
    echo "  HALF_OPEN (testing): ${half_open_count}"
    echo "  OPEN (circuit tripped): ${open_count}"
    echo ""
    echo "Configuration:"
    echo "  Failure threshold: ${FAILURE_THRESHOLD}"
    echo "  Half-open after: ${HALF_OPEN_AFTER_SECONDS}s"
    echo "  Success threshold: ${SUCCESS_THRESHOLD}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# === MAIN ===

main() {
    local command="${1:-stats}"
    shift || true

    case "${command}" in
        check)
            # Usage: circuit-breaker-manager.sh check <circuit_id>
            local circuit_id="$1"
            check_circuit "${circuit_id}"
            ;;
        record-failure)
            # Usage: circuit-breaker-manager.sh record-failure <circuit_id>
            local circuit_id="$1"
            record_failure "${circuit_id}"
            ;;
        record-success)
            # Usage: circuit-breaker-manager.sh record-success <circuit_id>
            local circuit_id="$1"
            record_success "${circuit_id}"
            ;;
        reset)
            # Usage: circuit-breaker-manager.sh reset <circuit_id>
            local circuit_id="$1"
            reset_circuit "${circuit_id}"
            ;;
        stats)
            circuit_stats
            ;;
        *)
            cat <<EOF
Circuit Breaker Manager

CHECK CIRCUIT:
  check <circuit_id>
    Returns 0 if circuit is CLOSED/HALF_OPEN, 1 if OPEN

RECORD EVENTS:
  record-failure <circuit_id>
    Increments failure count, opens circuit if threshold exceeded

  record-success <circuit_id>
    Increments success count, closes circuit from HALF_OPEN if threshold met

RESET:
  reset <circuit_id>
    Manually reset circuit to CLOSED state

STATISTICS:
  stats
    Show all circuit breaker states

Circuit States:
  CLOSED     - Normal operation, requests pass through
  OPEN       - Circuit tripped, fail fast (no requests)
  HALF_OPEN  - Testing recovery, limited requests allowed

2026 Research:
  - Prevents cascading failures in distributed systems
  - Fail fast pattern (AWS SDK, Temporal, Polly)
  - Automatic recovery testing
EOF
            ;;
    esac
}

main "$@"
