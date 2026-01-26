#!/usr/bin/env bash
# Common library functions for automation-hub plugin
# Adapted from process-janitor patterns

set -euo pipefail

# === Configuration Management ===

get_config_path() {
    echo "${HOME}/.claude/automation-hub/config.json"
}

get_metrics_path() {
    echo "${HOME}/.claude/automation-hub/metrics.jsonl"
}

get_session_state_path() {
    echo "${HOME}/.claude/automation-hub/session-state.json"
}

ensure_config_dirs() {
    local config_dir="${HOME}/.claude/automation-hub"
    mkdir -p "${config_dir}"
    mkdir -p "${config_dir}/proposals"
    mkdir -p "${config_dir}/checkpoints"
}

load_config() {
    ensure_config_dirs

    local config_path
    config_path=$(get_config_path)

    # Copy default config if not exists
    if [[ ! -f "${config_path}" ]]; then
        local plugin_dir
        plugin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
        cp "${plugin_dir}/config/default-config.json" "${config_path}"
    fi

    cat "${config_path}"
}

get_config_value() {
    local key="$1"
    local default="${2:-}"

    local config
    config=$(load_config)

    local value
    value=$(echo "${config}" | jq -r "${key} // empty")

    if [[ -z "${value}" ]]; then
        echo "${default}"
    else
        echo "${value}"
    fi
}

is_feature_enabled() {
    local feature="$1"

    # Check environment variable override
    if [[ "${SKIP_AUTOMATION:-0}" == "1" ]]; then
        return 1
    fi

    local enabled
    enabled=$(get_config_value ".${feature}.enabled" "false")

    [[ "${enabled}" == "true" ]]
}

# === Metrics Logging ===

log_metric() {
    local event_type="$1"
    local data="$2"

    local enabled
    enabled=$(get_config_value ".observability.log_metrics" "true")

    if [[ "${enabled}" != "true" ]]; then
        return 0
    fi

    local metrics_path
    metrics_path=$(get_metrics_path)

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local session_id="${CLAUDE_SESSION_ID:-unknown}"

    local metric_entry
    metric_entry=$(jq -n \
        --arg ts "${timestamp}" \
        --arg sid "${session_id}" \
        --arg type "${event_type}" \
        --argjson data "${data}" \
        '{
            timestamp: $ts,
            session_id: $sid,
            event_type: $type,
            data: $data
        }')

    echo "${metric_entry}" >> "${metrics_path}"
}

log_decision() {
    local feature="$1"
    local decision="$2"
    local reason="$3"
    local metadata="${4:-{}}"

    local enabled
    enabled=$(get_config_value ".observability.log_decisions" "true")

    if [[ "${enabled}" != "true" ]]; then
        return 0
    fi

    local data
    data=$(jq -n \
        --arg feat "${feature}" \
        --arg dec "${decision}" \
        --arg rsn "${reason}" \
        --argjson meta "${metadata}" \
        '{
            feature: $feat,
            decision: $dec,
            reason: $rsn,
            metadata: $meta
        }')

    log_metric "decision" "${data}"
}

# === Debug & Logging Output ===

debug() {
    local message="$1"

    local debug_mode
    debug_mode=$(get_config_value ".observability.debug_mode" "false")

    if [[ "${debug_mode}" == "true" ]] || [[ "${AUTOMATION_DEBUG:-0}" == "1" ]]; then
        echo "[AUTO-DEBUG] ${message}" >&2
    fi
}

log_info() {
    local message="$1"
    echo "[INFO] ${message}" >&2
}

log_success() {
    local message="$1"
    echo "[✓] ${message}" >&2
}

log_warning() {
    local message="$1"
    echo "[⚠️] ${message}" >&2
}

log_error() {
    local message="$1"
    echo "[✗] ${message}" >&2
}

# === Rate Limiting ===

check_rate_limit() {
    local feature="$1"
    local max_per_hour="$2"
    local min_interval_minutes="${3:-5}"

    local metrics_path
    metrics_path=$(get_metrics_path)

    if [[ ! -f "${metrics_path}" ]]; then
        return 0  # No metrics, allow
    fi

    local now
    now=$(date +%s)

    local one_hour_ago
    one_hour_ago=$((now - 3600))

    # Count events in last hour
    local count
    count=$(jq -r --arg feature "${feature}" --arg cutoff "$(date -u -r ${one_hour_ago} +"%Y-%m-%dT%H:%M:%SZ")" \
        'select(.event_type == "decision" and .data.feature == $feature and .timestamp > $cutoff) | .timestamp' \
        "${metrics_path}" 2>/dev/null | wc -l | tr -d ' ')

    if [[ ${count} -ge ${max_per_hour} ]]; then
        debug "Rate limit exceeded: ${count}/${max_per_hour} per hour for ${feature}"
        return 1
    fi

    # Check minimum interval
    local last_event_ts
    last_event_ts=$(jq -r --arg feature "${feature}" \
        'select(.event_type == "decision" and .data.feature == $feature) | .timestamp' \
        "${metrics_path}" 2>/dev/null | tail -1)

    if [[ -n "${last_event_ts}" ]]; then
        local last_event_epoch
        last_event_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${last_event_ts}" +%s 2>/dev/null || echo 0)

        local min_interval_seconds=$((min_interval_minutes * 60))
        local elapsed=$((now - last_event_epoch))

        if [[ ${elapsed} -lt ${min_interval_seconds} ]]; then
            debug "Min interval not met: ${elapsed}s < ${min_interval_seconds}s for ${feature}"
            return 1
        fi
    fi

    return 0
}

# === Circuit Breaker ===

check_circuit_breaker() {
    local feature="$1"
    local failure_threshold="${2:-3}"

    local enabled
    enabled=$(get_config_value ".${feature}.circuit_breaker.enabled" "false")

    if [[ "${enabled}" != "true" ]]; then
        return 0  # Circuit breaker disabled, allow
    fi

    local metrics_path
    metrics_path=$(get_metrics_path)

    if [[ ! -f "${metrics_path}" ]]; then
        return 0  # No metrics, allow
    fi

    # Get last N decisions
    local recent_failures
    recent_failures=$(jq -r --arg feature "${feature}" \
        'select(.event_type == "decision" and .data.feature == $feature and .data.decision == "failure") | .timestamp' \
        "${metrics_path}" 2>/dev/null | tail -${failure_threshold})

    local failure_count
    failure_count=$(echo "${recent_failures}" | grep -c . || echo 0)

    if [[ ${failure_count} -ge ${failure_threshold} ]]; then
        debug "Circuit breaker OPEN: ${failure_count} consecutive failures for ${feature}"
        return 1
    fi

    return 0
}

record_circuit_breaker_trip() {
    local feature="$1"

    local config_path
    config_path=$(get_config_path)

    # Disable feature in config
    local updated_config
    updated_config=$(jq ".${feature}.enabled = false" "${config_path}")
    echo "${updated_config}" > "${config_path}"

    log_decision "${feature}" "circuit_breaker_trip" "Auto-disabled after failure threshold" "{}"
}

# === Session State Management ===

init_session_state() {
    local session_state_path
    session_state_path=$(get_session_state_path)

    if [[ ! -f "${session_state_path}" ]]; then
        echo '{
            "session_id": "'"${CLAUDE_SESSION_ID:-unknown}"'",
            "started_at": "'"$(date -u +"%Y-%m-%dT%H:%M:%SZ")"'",
            "signals": {
                "corrections": 0,
                "iterations": 0,
                "skill_usage": 0,
                "external_failures": 0,
                "edge_cases": 0,
                "token_count": 0
            },
            "actions": {
                "auto_routing_count": 0,
                "auto_cleanup_count": 0,
                "auto_reflect_count": 0,
                "auto_fix_count": 0
            }
        }' > "${session_state_path}"
    fi
}

get_session_state_value() {
    local key="$1"
    local default="${2:-0}"

    local session_state_path
    session_state_path=$(get_session_state_path)

    init_session_state

    local value
    value=$(jq -r "${key} // ${default}" "${session_state_path}")

    echo "${value}"
}

increment_session_counter() {
    local key="$1"
    local increment="${2:-1}"

    local session_state_path
    session_state_path=$(get_session_state_path)

    init_session_state

    local updated_state
    updated_state=$(jq "${key} += ${increment}" "${session_state_path}")
    echo "${updated_state}" > "${session_state_path}"
}

clear_session_state() {
    local session_state_path
    session_state_path=$(get_session_state_path)

    rm -f "${session_state_path}"
}

# === Utility Functions ===

is_command_available() {
    command -v "$1" >/dev/null 2>&1
}

safe_exit() {
    local code="${1:-0}"
    local message="${2:-}"

    if [[ -n "${message}" ]]; then
        echo "${message}" >&2
    fi

    exit "${code}"
}
