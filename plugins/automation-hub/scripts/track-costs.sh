#!/usr/bin/env bash
# Track token usage and calculate ROI for automation decisions
# Helps justify automation overhead with measurable value

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Configuration ===

# Claude API Pricing (as of 2026)
# Sonnet 4: $3/MTok input, $15/MTok output
# Opus 4: $15/MTok input, $75/MTok output
# Haiku 4: $0.25/MTok input, $1.25/MTok output

PRICING_SONNET_INPUT=3.00
PRICING_SONNET_OUTPUT=15.00
PRICING_OPUS_INPUT=15.00
PRICING_OPUS_OUTPUT=75.00
PRICING_HAIKU_INPUT=0.25
PRICING_HAIKU_OUTPUT=1.25

# === Helper Functions ===

calculate_cost() {
    local model="$1"
    local input_tokens="$2"
    local output_tokens="$3"

    local input_price output_price

    case "${model}" in
        *sonnet*)
            input_price="${PRICING_SONNET_INPUT}"
            output_price="${PRICING_SONNET_OUTPUT}"
            ;;
        *opus*)
            input_price="${PRICING_OPUS_INPUT}"
            output_price="${PRICING_OPUS_OUTPUT}"
            ;;
        *haiku*)
            input_price="${PRICING_HAIKU_INPUT}"
            output_price="${PRICING_HAIKU_OUTPUT}"
            ;;
        *)
            # Default to Sonnet pricing
            input_price="${PRICING_SONNET_INPUT}"
            output_price="${PRICING_SONNET_OUTPUT}"
            ;;
    esac

    # Calculate cost in dollars
    # Cost = (input_tokens / 1,000,000) * input_price + (output_tokens / 1,000,000) * output_price
    local input_cost
    input_cost=$(echo "scale=6; (${input_tokens} / 1000000) * ${input_price}" | bc)

    local output_cost
    output_cost=$(echo "scale=6; (${output_tokens} / 1000000) * ${output_price}" | bc)

    local total_cost
    total_cost=$(echo "scale=6; ${input_cost} + ${output_cost}" | bc)

    echo "${total_cost}"
}

# === Track Decision Cost ===

track_decision_cost() {
    local event_type="$1"
    local feature="$2"
    local input_tokens="${3:-0}"
    local output_tokens="${4:-0}"
    local model="${5:-sonnet}"

    local cost
    cost=$(calculate_cost "${model}" "${input_tokens}" "${output_tokens}")

    # Log cost metric
    log_metric "cost" "$(jq -n \
        --arg feature "${feature}" \
        --arg input "${input_tokens}" \
        --arg output "${output_tokens}" \
        --arg cost "${cost}" \
        --arg model "${model}" \
        '{
            feature: $feature,
            input_tokens: ($input | tonumber),
            output_tokens: ($output | tonumber),
            total_cost_usd: ($cost | tonumber),
            model: $model
        }')"

    echo "${cost}"
}

# === Analyze Cost Trends ===

analyze_costs() {
    local lookback_days="${1:-30}"

    local metrics_file
    metrics_file=$(get_metrics_path)

    if [[ ! -f "${metrics_file}" ]]; then
        echo "No metrics data available"
        return 0
    fi

    local cutoff_time
    cutoff_time=$(date -u -v-"${lookback_days}"d +%s 2>/dev/null || date -u -d "${lookback_days} days ago" +%s)

    echo "💰 Cost Analysis (Last ${lookback_days} Days)"
    echo ""

    # Load cost metrics
    local cost_data
    cost_data=$(jq -s --arg cutoff "${cutoff_time}" \
        'map(select(.event_type == "cost" and .timestamp >= ($cutoff | tonumber)))' \
        "${metrics_file}")

    local total_count
    total_count=$(echo "${cost_data}" | jq 'length')

    if [[ ${total_count} -eq 0 ]]; then
        echo "No cost data found in last ${lookback_days} days"
        return 0
    fi

    # Calculate total costs
    local total_cost
    total_cost=$(echo "${cost_data}" | jq -r 'map(.data.total_cost_usd) | add')

    local total_input_tokens
    total_input_tokens=$(echo "${cost_data}" | jq -r 'map(.data.input_tokens) | add')

    local total_output_tokens
    total_output_tokens=$(echo "${cost_data}" | jq -r 'map(.data.output_tokens) | add')

    echo "┌─ Overall Statistics ─────────────────────┐"
    echo "│ Total API Calls: ${total_count}"
    printf "│ Total Cost: \$%.4f\n" "${total_cost}"
    echo "│ Input Tokens: $(printf "%'d" ${total_input_tokens})"
    echo "│ Output Tokens: $(printf "%'d" ${total_output_tokens})"
    printf "│ Avg Cost/Call: \$%.6f\n" "$(echo "scale=6; ${total_cost} / ${total_count}" | bc)"
    echo "└──────────────────────────────────────────┘"
    echo ""

    # Cost by feature
    echo "┌─ Cost by Feature ────────────────────────┐"
    echo "${cost_data}" | jq -r '
        group_by(.data.feature) |
        map({
            feature: .[0].data.feature,
            count: length,
            total_cost: (map(.data.total_cost_usd) | add),
            avg_cost: ((map(.data.total_cost_usd) | add) / length)
        }) |
        sort_by(.total_cost) | reverse |
        .[] |
        "│ " + .feature + ": $" + (.total_cost | tostring | .[0:8]) + " (" + (.count | tostring) + " calls)"' | head -10
    echo "└──────────────────────────────────────────┘"
    echo ""

    # Cost by model
    echo "┌─ Cost by Model ──────────────────────────┐"
    echo "${cost_data}" | jq -r '
        group_by(.data.model) |
        map({
            model: .[0].data.model,
            count: length,
            total_cost: (map(.data.total_cost_usd) | add)
        }) |
        sort_by(.total_cost) | reverse |
        .[] |
        "│ " + .model + ": $" + (.total_cost | tostring | .[0:8]) + " (" + (.count | tostring) + " calls)"'
    echo "└──────────────────────────────────────────┘"
    echo ""
}

# === Calculate ROI ===

calculate_roi() {
    local lookback_days="${1:-30}"

    local metrics_file
    metrics_file=$(get_metrics_path)

    if [[ ! -f "${metrics_file}" ]]; then
        echo "No metrics data available"
        return 0
    fi

    local cutoff_time
    cutoff_time=$(date -u -v-"${lookback_days}"d +%s 2>/dev/null || date -u -d "${lookback_days} days ago" +%s)

    echo "📊 ROI Analysis (Last ${lookback_days} Days)"
    echo ""

    # Load metrics
    local all_metrics
    all_metrics=$(jq -s --arg cutoff "${cutoff_time}" \
        'map(select(.timestamp >= ($cutoff | tonumber)))' \
        "${metrics_file}")

    # Calculate costs
    local total_cost
    total_cost=$(echo "${all_metrics}" | jq -r '
        map(select(.event_type == "cost")) |
        map(.data.total_cost_usd) | add // 0')

    # Calculate value delivered
    # Value metrics:
    # 1. Auto-approved decisions = interruptions saved
    # 2. Auto-cleanups = manual cleanup time saved
    # 3. Applied proposals = optimization improvements

    local auto_approved_count
    auto_approved_count=$(echo "${all_metrics}" | jq -r '
        map(select(.event_type == "decision" and .data.decision == "auto_approved")) | length')

    local auto_cleanup_count
    auto_cleanup_count=$(echo "${all_metrics}" | jq -r '
        map(select(.event_type == "cleanup" and .data.auto_triggered == true)) | length')

    local proposals_applied
    proposals_applied=$(echo "${all_metrics}" | jq -r '
        map(select(.event_type == "proposal_applied")) | length')

    # Estimate value in time saved
    # Assumptions (conservative):
    # - Each auto-approved decision saves 30 seconds of user decision time
    # - Each auto-cleanup saves 2 minutes of manual cleanup
    # - Each applied proposal saves 5 minutes of manual optimization

    local decision_time_saved=$((auto_approved_count * 30))  # seconds
    local cleanup_time_saved=$((auto_cleanup_count * 120))  # seconds
    local optimization_time_saved=$((proposals_applied * 300))  # seconds

    local total_time_saved=$((decision_time_saved + cleanup_time_saved + optimization_time_saved))
    local hours_saved=$(echo "scale=2; ${total_time_saved} / 3600" | bc)

    # Convert time to dollar value (assuming $100/hour developer time)
    local developer_rate=100
    local value_delivered=$(echo "scale=2; ${hours_saved} * ${developer_rate}" | bc)

    # Calculate ROI
    local roi
    if [[ $(echo "${total_cost} > 0" | bc) -eq 1 ]]; then
        roi=$(echo "scale=1; ((${value_delivered} - ${total_cost}) / ${total_cost}) * 100" | bc)
    else
        roi="N/A"
    fi

    echo "┌─ Cost ───────────────────────────────────┐"
    printf "│ API Costs: \$%.4f\n" "${total_cost}"
    echo "└──────────────────────────────────────────┘"
    echo ""

    echo "┌─ Value Delivered ────────────────────────┐"
    echo "│ Auto-Approved Decisions: ${auto_approved_count}"
    echo "│   Time Saved: $(echo "scale=1; ${decision_time_saved} / 60" | bc) minutes"
    echo "│"
    echo "│ Auto-Cleanups: ${auto_cleanup_count}"
    echo "│   Time Saved: $(echo "scale=1; ${cleanup_time_saved} / 60" | bc) minutes"
    echo "│"
    echo "│ Optimizations Applied: ${proposals_applied}"
    echo "│   Time Saved: $(echo "scale=1; ${optimization_time_saved} / 60" | bc) minutes"
    echo "│"
    echo "│ Total Time Saved: ${hours_saved} hours"
    printf "│ Estimated Value: \$%.2f\n" "${value_delivered}"
    echo "└──────────────────────────────────────────┘"
    echo ""

    echo "┌─ ROI ────────────────────────────────────┐"
    if [[ "${roi}" != "N/A" ]]; then
        printf "│ Return on Investment: %.1f%%\n" "${roi}"
        echo "│"
        if [[ $(echo "${roi} > 0" | bc) -eq 1 ]]; then
            printf "│ Net Benefit: \$%.2f\n" "$(echo "${value_delivered} - ${total_cost}" | bc)"
            echo "│ Status: ✅ Positive ROI"
        else
            echo "│ Status: ⚠️  Negative ROI (early stages)"
        fi
    else
        echo "│ Not enough data for ROI calculation"
    fi
    echo "└──────────────────────────────────────────┘"
    echo ""

    echo "Assumptions:"
    echo "  - Developer time: \$${developer_rate}/hour"
    echo "  - Decision interruption: 30 seconds saved"
    echo "  - Cleanup task: 2 minutes saved"
    echo "  - Optimization: 5 minutes saved"
    echo ""
    echo "Note: ROI improves as automation learns and auto-approval increases"
}

# === Set Budget Alert ===

set_budget_alert() {
    local monthly_budget="$1"

    local config
    config=$(load_config)

    config=$(echo "${config}" | jq \
        --arg budget "${monthly_budget}" \
        '.budget = {
            monthly_limit_usd: ($budget | tonumber),
            alert_threshold: 0.80
        }')

    save_config "${config}"

    echo "✓ Budget alert set: \$${monthly_budget}/month"
    echo "  Alert at 80% (\$$(echo "scale=2; ${monthly_budget} * 0.80" | bc))"
}

check_budget() {
    local config
    config=$(load_config)

    local monthly_budget
    monthly_budget=$(echo "${config}" | jq -r '.budget.monthly_limit_usd // 0')

    if [[ $(echo "${monthly_budget} == 0" | bc) -eq 1 ]]; then
        echo "No budget limit set"
        echo "Set with: track-costs.sh set-budget <amount>"
        return 0
    fi

    # Calculate current month costs
    local month_start
    month_start=$(date -u +%Y-%m-01)
    local month_start_ts
    month_start_ts=$(date -u -j -f "%Y-%m-%d" "${month_start}" +%s 2>/dev/null || date -u -d "${month_start}" +%s)

    local metrics_file
    metrics_file=$(get_metrics_path)

    local month_cost
    month_cost=$(jq -s --arg cutoff "${month_start_ts}" \
        'map(select(.event_type == "cost" and .timestamp >= ($cutoff | tonumber))) |
        map(.data.total_cost_usd) | add // 0' \
        "${metrics_file}")

    local usage_percent
    usage_percent=$(echo "scale=1; (${month_cost} / ${monthly_budget}) * 100" | bc)

    echo "📊 Budget Status ($(date +%B %Y))"
    echo ""
    printf "Budget: \$%.2f / \$%.2f (%.1f%%)\n" "${month_cost}" "${monthly_budget}" "${usage_percent}"

    local remaining
    remaining=$(echo "scale=2; ${monthly_budget} - ${month_cost}" | bc)
    printf "Remaining: \$%.2f\n" "${remaining}"

    local alert_threshold
    alert_threshold=$(echo "${config}" | jq -r '.budget.alert_threshold // 0.80')

    if [[ $(echo "${usage_percent} > (${alert_threshold} * 100)" | bc) -eq 1 ]]; then
        echo ""
        echo "⚠️  WARNING: Budget usage above ${alert_threshold}% threshold!"
    fi
}

# === Main ===

main() {
    local command="${1:-analyze}"

    case "${command}" in
        analyze)
            local days="${2:-30}"
            analyze_costs "${days}"
            ;;

        roi)
            local days="${2:-30}"
            calculate_roi "${days}"
            ;;

        set-budget)
            if [[ $# -lt 2 ]]; then
                echo "Usage: track-costs.sh set-budget <monthly_usd>"
                exit 1
            fi
            set_budget_alert "$2"
            ;;

        check-budget)
            check_budget
            ;;

        track)
            # Used internally by other scripts
            if [[ $# -lt 6 ]]; then
                echo "Usage: track-costs.sh track <event> <feature> <input_tokens> <output_tokens> <model>"
                exit 1
            fi
            track_decision_cost "$2" "$3" "$4" "$5" "$6"
            ;;

        *)
            cat <<'EOF'
Cost Tracking - Token usage and ROI analysis

USAGE:
  track-costs.sh analyze [days]         Analyze costs (default: 30 days)
  track-costs.sh roi [days]             Calculate ROI (default: 30 days)
  track-costs.sh set-budget <usd>       Set monthly budget alert
  track-costs.sh check-budget           Check current budget status

EXAMPLES:
  track-costs.sh analyze               Analyze last 30 days
  track-costs.sh analyze 7             Analyze last week
  track-costs.sh roi                   Calculate ROI for last 30 days
  track-costs.sh set-budget 50         Set $50/month budget
  track-costs.sh check-budget          Check current month usage

PRICING (2026):
  Sonnet 4: $3/MTok input, $15/MTok output
  Opus 4: $15/MTok input, $75/MTok output
  Haiku 4: $0.25/MTok input, $1.25/MTok output

ROI CALCULATION:
  Value = Time saved × Developer rate
  Time saved from: auto-approvals, cleanups, optimizations
  Developer rate: $100/hour (configurable)

EOF
            ;;
    esac
}

# Execute
main "$@"

exit 0
