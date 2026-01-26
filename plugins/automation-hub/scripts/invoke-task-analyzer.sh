#!/usr/bin/env bash
# Stage 2: Invoke multi-agent task-analyzer and apply auto-approval logic

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Input ===
# $1: prompt text
# $2: token budget

PROMPT="${1:-}"
TOKEN_BUDGET="${2:-0}"

debug "Stage 2: Invoking multi-agent task-analyzer"

# === Invoke Task Analyzer Agent ===

# Note: This is a placeholder for the actual Task tool invocation
# In practice, this would be done by Claude in the PreToolUse hook
# This script prepares the decision logic

# For now, we'll simulate by checking if analysis exists in session state
# In real implementation, Claude will invoke the agent and store results

analysis_file="${HOME}/.claude/automation-hub/session-state.json"

if [[ ! -f "${analysis_file}" ]]; then
    debug "  No task analysis available (agent not yet invoked)"
    echo "pending_analysis"
    exit 0
fi

# === Parse Analysis Results ===

complexity_score=$(jq -r '.task_analysis.complexity_score // 0' "${analysis_file}")
recommended_pattern=$(jq -r '.task_analysis.recommended_pattern // "single"' "${analysis_file}")
estimated_tokens=$(jq -r '.task_analysis.estimated_tokens // 0' "${analysis_file}")

debug "  Complexity: ${complexity_score}, Pattern: ${recommended_pattern}, Cost: ${estimated_tokens} tokens"

# === Auto-Approval Decision Tree ===

decision="suggest"
reason=""

# Get complexity band
if [[ ${complexity_score} -lt 30 ]]; then
    band="simple"
elif [[ ${complexity_score} -lt 50 ]]; then
    band="moderate"
elif [[ ${complexity_score} -lt 70 ]]; then
    band="complex"
else
    band="very_complex"
fi

debug "  Complexity band: ${band}"

# Band-specific logic
case "${band}" in
    simple)
        decision="skip"
        reason="Complexity too low (${complexity_score}), multi-agent not needed"
        ;;

    moderate)
        # Check if user has approved this band before
        auto_approve=$(get_config_value ".auto_routing.stage2_auto_approve.moderate" "false")

        if [[ "${auto_approve}" == "true" ]]; then
            # Check approval rate
            approval_rate=$(calculate_approval_rate "${band}")

            threshold=$(get_config_value ".auto_routing.approval_rate_threshold" "0.70")

            if (( $(echo "${approval_rate} >= ${threshold}" | bc -l) )); then
                decision="auto_approve"
                reason="Auto-approved based on learning (approval_rate=${approval_rate})"
            else
                decision="suggest"
                reason="Approval rate (${approval_rate}) below threshold (${threshold})"
            fi
        else
            decision="suggest"
            reason="Auto-approval disabled for moderate complexity"
        fi
        ;;

    complex)
        # Check token budget
        if [[ ${TOKEN_BUDGET} -lt ${estimated_tokens} ]]; then
            decision="suggest"
            reason="Insufficient token budget (${TOKEN_BUDGET} < ${estimated_tokens})"
        else
            auto_approve=$(get_config_value ".auto_routing.stage2_auto_approve.complex" "false")

            if [[ "${auto_approve}" == "true" ]]; then
                approval_rate=$(calculate_approval_rate "${band}")
                threshold=$(get_config_value ".auto_routing.approval_rate_threshold" "0.70")

                if (( $(echo "${approval_rate} >= ${threshold}" | bc -l) )); then
                    decision="auto_approve"
                    reason="Auto-approved based on learning (approval_rate=${approval_rate})"
                else
                    decision="suggest"
                    reason="Approval rate (${approval_rate}) below threshold (${threshold})"
                fi
            else
                decision="suggest"
                reason="Auto-approval disabled for complex tasks"
            fi
        fi
        ;;

    very_complex)
        decision="suggest"
        reason="Very complex tasks always require user approval"
        ;;
esac

debug "  → Decision: ${decision} (${reason})"

# === Log Metrics ===

metadata=$(jq -n \
    --arg band "${band}" \
    --argjson score "${complexity_score}" \
    --arg pattern "${recommended_pattern}" \
    --argjson tokens "${estimated_tokens}" \
    '{
        complexity_band: $band,
        complexity_score: $score,
        recommended_pattern: $pattern,
        estimated_tokens: $tokens
    }')

log_decision "auto_routing" "${decision}" "${reason}" "${metadata}"

# === Output ===

echo "${decision}"
exit 0

# === Helper Functions ===

calculate_approval_rate() {
    local band="$1"

    local metrics_path
    metrics_path=$(get_metrics_path)

    if [[ ! -f "${metrics_path}" ]]; then
        echo "0.00"
        return
    fi

    # Count approvals and rejections for this band
    local approvals
    approvals=$(jq -r --arg band "${band}" \
        'select(.event_type == "decision" and .data.feature == "auto_routing" and .data.metadata.complexity_band == $band and (.data.decision == "auto_approve" or .data.decision == "user_approve")) | .timestamp' \
        "${metrics_path}" 2>/dev/null | wc -l | tr -d ' ')

    local rejections
    rejections=$(jq -r --arg band "${band}" \
        'select(.event_type == "decision" and .data.feature == "auto_routing" and .data.metadata.complexity_band == $band and .data.decision == "user_reject") | .timestamp' \
        "${metrics_path}" 2>/dev/null | wc -l | tr -d ' ')

    local total=$((approvals + rejections))

    if [[ ${total} -eq 0 ]]; then
        echo "0.00"
        return
    fi

    # Calculate rate
    local rate
    rate=$(echo "scale=2; ${approvals} / ${total}" | bc)

    echo "${rate}"
}
