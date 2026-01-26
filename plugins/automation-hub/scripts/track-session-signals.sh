#!/usr/bin/env bash
# Track session signals for auto-reflection worthiness scoring

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Input ===
# $1: signal type (corrections, iterations, skill_usage, external_failures, edge_cases, token_count)
# $2: increment value (optional, default 1)

SIGNAL_TYPE="${1:-}"
INCREMENT="${2:-1}"

if [[ -z "${SIGNAL_TYPE}" ]]; then
    echo "Usage: $0 <signal_type> [increment]" >&2
    exit 1
fi

# === Initialize Session State ===

init_session_state

# === Update Signal Counter ===

case "${SIGNAL_TYPE}" in
    corrections|iterations|skill_usage|external_failures|edge_cases)
        increment_session_counter ".signals.${SIGNAL_TYPE}" "${INCREMENT}"
        debug "Incremented signal: ${SIGNAL_TYPE} +${INCREMENT}"
        ;;

    token_count)
        # For token count, set absolute value rather than increment
        session_state_path=$(get_session_state_path)
        updated_state=$(jq ".signals.token_count = ${INCREMENT}" "${session_state_path}")
        echo "${updated_state}" > "${session_state_path}"
        debug "Updated token count: ${INCREMENT}"
        ;;

    *)
        echo "Unknown signal type: ${SIGNAL_TYPE}" >&2
        exit 1
        ;;
esac

# === Log Metric ===

data=$(jq -n \
    --arg signal "${SIGNAL_TYPE}" \
    --argjson increment "${INCREMENT}" \
    '{
        signal_type: $signal,
        increment: $increment
    }')

log_metric "signal_tracked" "${data}"

exit 0
