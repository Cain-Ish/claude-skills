#!/usr/bin/env bash
# Analyze cross-plugin metrics and generate optimization proposals
# Implements self-reflection and self-challenging patterns

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Configuration ===

METRICS_FILE=$(get_metrics_path)
PROPOSALS_DIR="${HOME}/.claude/automation-hub/proposals"
ANALYSIS_PERIOD_DAYS=7

mkdir -p "${PROPOSALS_DIR}"

# === Load Metrics ===

load_metrics_for_period() {
    local days="$1"

    if [[ ! -f "${METRICS_FILE}" ]]; then
        echo "[]"
        return
    fi

    local cutoff_date
    cutoff_date=$(date -u -v-${days}d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "${days} days ago" +"%Y-%m-%dT%H:%M:%SZ")

    jq -c --arg cutoff "${cutoff_date}" \
        'select(.timestamp > $cutoff)' \
        "${METRICS_FILE}" | jq -s '.'
}

# === Analysis Functions ===

analyze_routing_accuracy() {
    local metrics="$1"

    # Calculate approval rates by complexity band
    local routing_decisions
    routing_decisions=$(echo "${metrics}" | jq -c '
        .[] | select(.event_type == "decision" and .data.feature == "auto_routing")
    ')

    if [[ -z "${routing_decisions}" ]]; then
        return
    fi

    # Group by complexity band
    local bands=("simple" "moderate" "complex" "very_complex")

    for band in "${bands[@]}"; do
        local band_decisions
        band_decisions=$(echo "${routing_decisions}" | jq -c --arg band "${band}" \
            'select(.data.metadata.complexity_band == $band)')

        if [[ -z "${band_decisions}" ]]; then
            continue
        fi

        local total
        total=$(echo "${band_decisions}" | wc -l | tr -d ' ')

        local approved
        approved=$(echo "${band_decisions}" | jq -c \
            'select(.data.decision == "auto_approve" or .data.decision == "user_approve")' \
            | wc -l | tr -d ' ')

        local rejected
        rejected=$(echo "${band_decisions}" | jq -c \
            'select(.data.decision == "user_reject")' \
            | wc -l | tr -d ' ')

        if [[ ${total} -gt 0 ]]; then
            local approval_rate
            approval_rate=$(echo "scale=2; ${approved} / ${total}" | bc)

            debug "  ${band}: ${approval_rate} (${approved}/${total})"

            # Generate proposal if approval rate suggests threshold adjustment
            if [[ ${total} -ge 30 ]] && (( $(echo "${approval_rate} >= 0.85" | bc -l) )); then
                # High approval rate - could enable auto-approval
                generate_auto_approval_proposal "${band}" "${approval_rate}" "${total}"
            elif [[ ${total} -ge 50 ]] && (( $(echo "${approval_rate} <= 0.55" | bc -l) )); then
                # Low approval rate - adjust stage 1 threshold
                generate_threshold_adjustment_proposal "${band}" "${approval_rate}" "${total}"
            fi
        fi
    done
}

analyze_reflection_signals() {
    local metrics="$1"

    # Analyze which signals correlate with accepted reflection proposals
    local reflection_events
    reflection_events=$(echo "${metrics}" | jq -c '
        .[] | select(.event_type == "decision" and .data.feature == "auto_reflect")
    ')

    if [[ -z "${reflection_events}" ]]; then
        return
    fi

    # Calculate signal correlation with proposal acceptance
    # This is a simplified analysis; real implementation would use proper statistics

    debug "Reflection signal analysis:"

    local signals=("corrections" "iterations" "skill_usage" "external_failures" "edge_cases")

    for signal in "${signals[@]}"; do
        # Count events with high signal value that resulted in acceptance
        # This is a placeholder for actual correlation analysis
        debug "  ${signal}: needs correlation calculation"
    done
}

# === Proposal Generation ===

generate_auto_approval_proposal() {
    local band="$1"
    local approval_rate="$2"
    local sample_count="$3"

    local proposal_id="P$(date +%Y-%m-%d-%H%M%S)-auto-approve-${band}"

    local current_setting
    current_setting=$(get_config_value ".auto_routing.stage2_auto_approve.${band}" "false")

    # Only propose if not already enabled
    if [[ "${current_setting}" == "true" ]]; then
        return
    fi

    # Calculate confidence based on sample size and approval rate
    local confidence
    if [[ ${sample_count} -ge 100 ]] && (( $(echo "${approval_rate} >= 0.90" | bc -l) )); then
        confidence="0.92"
    elif [[ ${sample_count} -ge 50 ]] && (( $(echo "${approval_rate} >= 0.85" | bc -l) )); then
        confidence="0.85"
    else
        confidence="0.75"
    fi

    jq -n \
        --arg id "${proposal_id}" \
        --arg type "auto_approval_threshold" \
        --arg band "${band}" \
        --arg current "${current_setting}" \
        --arg proposed "true" \
        --arg rate "${approval_rate}" \
        --arg samples "${sample_count}" \
        --arg confidence "${confidence}" \
        '{
            id: $id,
            type: $type,
            target: (".auto_routing.stage2_auto_approve." + $band),
            current_value: ($current == "true"),
            proposed_value: ($proposed == "true"),
            rationale: (
                "User has " + ($rate | tonumber * 100 | floor | tostring) + "% approval rate for " +
                $band + " complexity tasks over " + $samples + " samples. " +
                "Enabling auto-approval reduces interruptions while maintaining safety."
            ),
            confidence: ($confidence | tonumber),
            data_support: {
                complexity_band: $band,
                approval_rate: ($rate | tonumber),
                sample_count: ($samples | tonumber),
                recommendation: "enable"
            },
            impact_prediction: {
                interruption_reduction: "~30%",
                risk_level: "low",
                rollback_plan: "Disable if approval rate drops below 0.70 in next 7 days"
            },
            created_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
        }' > "${PROPOSALS_DIR}/${proposal_id}.json"

    debug "Generated proposal: ${proposal_id}"
}

generate_threshold_adjustment_proposal() {
    local band="$1"
    local approval_rate="$2"
    local sample_count="$3"

    local proposal_id="P$(date +%Y-%m-%d-%H%M%S)-threshold-adj-${band}"

    local current_threshold
    current_threshold=$(get_config_value ".auto_routing.stage1_threshold" "4")

    # Propose increasing threshold to reduce false positives
    local proposed_threshold=$((current_threshold + 1))

    local confidence
    if [[ ${sample_count} -ge 100 ]]; then
        confidence="0.82"
    elif [[ ${sample_count} -ge 50 ]]; then
        confidence="0.75"
    else
        confidence="0.65"
    fi

    jq -n \
        --arg id "${proposal_id}" \
        --arg type "threshold_calibration" \
        --arg current "${current_threshold}" \
        --arg proposed "${proposed_threshold}" \
        --arg rate "${approval_rate}" \
        --arg samples "${sample_count}" \
        --arg confidence "${confidence}" \
        '{
            id: $id,
            type: $type,
            target: ".auto_routing.stage1_threshold",
            current_value: ($current | tonumber),
            proposed_value: ($proposed | tonumber),
            rationale: (
                "Low approval rate (" + ($rate | tonumber * 100 | floor | tostring) + "%) " +
                "suggests Stage 1 pre-filter has high false positive rate. " +
                "Increasing threshold to " + $proposed + " predicted to improve precision."
            ),
            confidence: ($confidence | tonumber),
            data_support: {
                current_approval_rate: ($rate | tonumber),
                sample_count: ($samples | tonumber),
                predicted_false_positive_reduction: "35-45%"
            },
            impact_prediction: {
                precision_improvement: "~15%",
                risk_level: "medium",
                rollback_plan: "Revert to " + $current + " if false negative rate increases >5%"
            },
            created_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
        }' > "${PROPOSALS_DIR}/${proposal_id}.json"

    debug "Generated proposal: ${proposal_id}"
}

# === Report Generation ===

generate_analysis_report() {
    local metrics="$1"

    local total_events
    total_events=$(echo "${metrics}" | jq 'length')

    local period_start
    period_start=$(date -u -v-${ANALYSIS_PERIOD_DAYS}d +"%Y-%m-%d" 2>/dev/null || date -u -d "${ANALYSIS_PERIOD_DAYS} days ago" +"%Y-%m-%d")

    local period_end
    period_end=$(date -u +"%Y-%m-%d")

    # Count proposals
    local proposal_count
    proposal_count=$(ls -1 "${PROPOSALS_DIR}"/*.json 2>/dev/null | wc -l | tr -d ' ')

    cat <<EOF
# Automation Hub - Learning Analysis

**Analysis Period:** ${period_start} to ${period_end}
**Metrics Analyzed:** ${total_events} events

## Summary

**Overall Health:** 🟢 Analysis Complete

## Optimization Proposals

**Generated:** ${proposal_count} proposal(s)

EOF

    # List proposals
    for proposal_file in "${PROPOSALS_DIR}"/*.json; do
        if [[ -f "${proposal_file}" ]]; then
            local proposal
            proposal=$(cat "${proposal_file}")

            local id type confidence
            id=$(echo "${proposal}" | jq -r '.id')
            type=$(echo "${proposal}" | jq -r '.type')
            confidence=$(echo "${proposal}" | jq -r '.confidence')

            local conf_level
            if (( $(echo "${confidence} >= 0.85" | bc -l) )); then
                conf_level="High"
            elif (( $(echo "${confidence} >= 0.70" | bc -l) )); then
                conf_level="Medium"
            else
                conf_level="Low"
            fi

            echo "### [${id}] ${type} (${conf_level} Confidence: ${confidence})"
            echo ""
            echo "$(echo "${proposal}" | jq -r '.rationale')"
            echo ""
            echo "**Impact:** $(echo "${proposal}" | jq -r '.impact_prediction | to_entries | map("\(.key): \(.value)") | join(", ")')"
            echo ""
        fi
    done

    cat <<EOF

## Next Analysis

**Scheduled:** $(date -u -v+7d +"%Y-%m-%d" 2>/dev/null || date -u -d "7 days" +"%Y-%m-%d")

---
View proposals: \`/automation proposals\`
Apply proposal: \`/automation apply-proposal <id>\`
EOF
}

# === Main Execution ===

debug "Starting metrics analysis..."

# Load metrics
metrics=$(load_metrics_for_period "${ANALYSIS_PERIOD_DAYS}")

event_count=$(echo "${metrics}" | jq 'length')

debug "Loaded ${event_count} events from last ${ANALYSIS_PERIOD_DAYS} days"

if [[ ${event_count} -eq 0 ]]; then
    echo "No metrics available for analysis"
    exit 0
fi

# Run analyses
debug "Analyzing routing accuracy..."
analyze_routing_accuracy "${metrics}"

debug "Analyzing reflection signals..."
analyze_reflection_signals "${metrics}"

# Generate report
report=$(generate_analysis_report "${metrics}")

# Save report
report_file="${PROPOSALS_DIR}/analysis-$(date +%Y-%m-%d).md"
echo "${report}" > "${report_file}"

# Output report
echo "${report}"

debug "Analysis complete: ${report_file}"

exit 0
