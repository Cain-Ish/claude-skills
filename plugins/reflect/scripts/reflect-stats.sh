#!/bin/bash
# ============================================================================
# Reflect Stats: Show Effectiveness Metrics
# ============================================================================
# Displays acceptance rates, effectiveness scores, and insights.
# Uses shared library for cross-platform compatibility.
# ============================================================================

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/platform.sh"

# Alias for consistency with existing code
RESET="$NC"

# Usage
usage() {
    cat <<EOF
Usage: $0 [SKILL_NAME] [OPTIONS]

Display reflect effectiveness metrics.

Arguments:
  SKILL_NAME    Optional: Show stats for specific skill only

Options:
  --all         Show all metrics (default: summary only)
  --json        Output in JSON format

Examples:
  $0                      # Overall summary
  $0 frontend-design      # Stats for one skill
  $0 --all               # Detailed breakdown
  $0 --json              # Machine-readable output

EOF
    exit 1
}

# Check if metrics file exists
if [ ! -f "$METRICS_FILE" ]; then
    log_warn "No metrics data found"
    echo "Run /reflect on a skill first to collect metrics"
    exit 1
fi

# Parse arguments
SKILL_FILTER=""
SHOW_ALL=false
OUTPUT_JSON=false

while [ $# -gt 0 ]; do
    case "$1" in
        --all)
            SHOW_ALL=true
            shift
            ;;
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            SKILL_FILTER="$1"
            shift
            ;;
    esac
done

# Extract proposals and outcomes
extract_proposals() {
    grep -v '^#' "$METRICS_FILE" | grep "\"type\":\"proposal\"" || true
}

extract_outcomes() {
    grep -v '^#' "$METRICS_FILE" | grep "\"type\":\"outcome\"" || true
}

# Count by field
count_by_field() {
    local field="$1"
    local value="$2"
    (grep "\"$field\":\"$value\"" || true) | wc -l | tr -d ' '
}

# Calculate acceptance rate (uses calc_percentage from common.sh)
calc_acceptance_rate() {
    local total=$1
    local approved=$2
    calc_percentage "$approved" "$total"
}

# Get proposals
PROPOSALS=$(extract_proposals)

if [ -z "$PROPOSALS" ]; then
    echo "No proposals found in metrics database"
    echo "Run /reflect on a skill to start tracking effectiveness"
    exit 0
fi

# Filter by skill if requested
if [ -n "$SKILL_FILTER" ]; then
    # Validate skill name for security
    validate_skill_name "$SKILL_FILTER" || exit 1

    PROPOSALS=$(echo "$PROPOSALS" | grep "\"skill\":\"$SKILL_FILTER\"" || true)
    if [ -z "$PROPOSALS" ]; then
        log_info "No proposals found for skill: $SKILL_FILTER"
        exit 0
    fi
fi

# Count totals (use grep -c for reliable counting)
TOTAL_PROPOSALS=$(printf '%s\n' "$PROPOSALS" | grep -c . || echo "0")
APPROVED=$(echo "$PROPOSALS" | count_by_field "user_action" "approved")
REJECTED=$(echo "$PROPOSALS" | count_by_field "user_action" "rejected")
MODIFIED=$(echo "$PROPOSALS" | count_by_field "user_action" "modified")
DEFERRED=$(echo "$PROPOSALS" | count_by_field "user_action" "deferred")

# Calculate acceptance rate (approved + modified = accepted)
ACCEPTED=$((APPROVED + MODIFIED))
ACCEPTANCE_RATE=$(calc_acceptance_rate "$TOTAL_PROPOSALS" "$ACCEPTED")

# Get outcomes
OUTCOMES=$(extract_outcomes)
if [ -n "$SKILL_FILTER" ]; then
    OUTCOMES=$(echo "$OUTCOMES" | grep "\"skill\":\"$SKILL_FILTER\"" || true)
fi

# Check if OUTCOMES is empty first
# Use grep -c to count non-empty lines reliably
if [ -z "$OUTCOMES" ]; then
    TOTAL_OUTCOMES=0
else
    TOTAL_OUTCOMES=$(printf '%s\n' "$OUTCOMES" | grep -c . || echo "0")
fi

if [ "$TOTAL_OUTCOMES" -gt 0 ]; then
    # Note: JSON booleans are unquoted (true/false), not strings ("true"/"false")
    HELPFUL=$(echo "$OUTCOMES" | grep -c "\"improvement_helpful\":true" || echo "0")
    NOT_HELPFUL=$(echo "$OUTCOMES" | grep -c "\"improvement_helpful\":false" || echo "0")
    EFFECTIVENESS_RATE=$(calc_acceptance_rate "$TOTAL_OUTCOMES" "$HELPFUL")
else
    HELPFUL=0
    NOT_HELPFUL=0
    EFFECTIVENESS_RATE="N/A"
fi

# JSON output
if [ "$OUTPUT_JSON" = true ]; then
    cat <<EOF
{
  "skill": "${SKILL_FILTER:-all}",
  "proposals": {
    "total": $TOTAL_PROPOSALS,
    "approved": $APPROVED,
    "rejected": $REJECTED,
    "modified": $MODIFIED,
    "deferred": $DEFERRED,
    "acceptance_rate": $ACCEPTANCE_RATE
  },
  "outcomes": {
    "total": $TOTAL_OUTCOMES,
    "helpful": $HELPFUL,
    "not_helpful": $NOT_HELPFUL,
    "effectiveness_rate": "$EFFECTIVENESS_RATE"
  }
}
EOF
    exit 0
fi

# Human-readable output
echo ""
echo -e "${BOLD}Reflect Effectiveness Metrics${RESET}"
if [ -n "$SKILL_FILTER" ]; then
    echo -e "Skill: ${CYAN}$SKILL_FILTER${RESET}"
fi
echo ""

echo -e "${BOLD}Proposals${RESET}"
echo "  Total: $TOTAL_PROPOSALS"
echo "  Approved: $APPROVED"
echo "  Rejected: $REJECTED"
echo "  Modified: $MODIFIED"
echo "  Deferred: $DEFERRED"
echo ""

# Color-code acceptance rate (using bash arithmetic - handles integer percentages)
if [ "$ACCEPTANCE_RATE" -ge 70 ] 2>/dev/null; then
    RATE_COLOR="$GREEN"
elif [ "$ACCEPTANCE_RATE" -ge 50 ] 2>/dev/null; then
    RATE_COLOR="$YELLOW"
else
    RATE_COLOR="$RED"
fi

echo -e "${BOLD}Acceptance Rate${RESET}: ${RATE_COLOR}${ACCEPTANCE_RATE}%${RESET}"
echo ""

if [ "$TOTAL_OUTCOMES" -gt 0 ]; then
    echo -e "${BOLD}Outcomes${RESET}"
    echo "  Total: $TOTAL_OUTCOMES"
    echo "  Helpful: $HELPFUL"
    echo "  Not Helpful: $NOT_HELPFUL"
    echo ""

    # Color-code effectiveness (using bash arithmetic)
    if [ "$EFFECTIVENESS_RATE" != "N/A" ]; then
        if [ "$EFFECTIVENESS_RATE" -ge 75 ] 2>/dev/null; then
            EFF_COLOR="$GREEN"
        elif [ "$EFFECTIVENESS_RATE" -ge 50 ] 2>/dev/null; then
            EFF_COLOR="$YELLOW"
        else
            EFF_COLOR="$RED"
        fi
        echo -e "${BOLD}Effectiveness Rate${RESET}: ${EFF_COLOR}${EFFECTIVENESS_RATE}%${RESET}"
    fi
else
    echo -e "${YELLOW}No outcome data yet${RESET}"
    echo "Use reflect-track-outcome.sh after using improved skills"
fi

echo ""

# Insights
echo -e "${BOLD}Insights${RESET}"
if [ "$ACCEPTANCE_RATE" -lt 50 ] 2>/dev/null; then
    echo -e "  ${RED}⚠${RESET}  Low acceptance rate - proposals may be too aggressive"
fi
if [ "$TOTAL_OUTCOMES" -eq 0 ]; then
    echo -e "  ${YELLOW}ℹ${RESET}  No outcome tracking yet - can't measure effectiveness"
fi
if [ "$ACCEPTANCE_RATE" -ge 70 ] 2>/dev/null && [ "$EFFECTIVENESS_RATE" != "N/A" ] && [ "$EFFECTIVENESS_RATE" -ge 75 ] 2>/dev/null; then
    echo -e "  ${GREEN}✓${RESET}  Excellent performance! Proposals are accepted and helpful"
fi

echo ""
echo "Run '/reflect reflect' to analyze effectiveness and propose meta-improvements"
echo ""
