#!/bin/bash
#
# Reflect Proposal Optimization Detection Script
# Analyzes reflect proposal metrics to detect optimization opportunities
#

set -euo pipefail

METRICS_FILE="$HOME/.claude/reflect/proposals.jsonl"
MIN_SAMPLES=10

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if metrics file exists
if [ ! -f "$METRICS_FILE" ]; then
  echo "No reflect proposal metrics found yet."
  echo "Metrics will be collected as reflect plugin analyzes sessions."
  echo "Location: $METRICS_FILE"
  exit 0
fi

# Count total proposals
TOTAL=$(wc -l < "$METRICS_FILE" | tr -d ' ')

if [ "$TOTAL" -lt "$MIN_SAMPLES" ]; then
  echo "Insufficient data for proposal analysis"
  echo "Current: $TOTAL proposals"
  echo "Required: $MIN_SAMPLES proposals"
  echo "Use reflect plugin more to collect data for optimization."
  exit 0
fi

echo -e "${BLUE}=== Reflect Proposal Analysis ===${NC}"
echo "Analyzing $TOTAL proposals..."
echo ""

# Analyze approval rates by proposal type
ANALYSIS=$(cat "$METRICS_FILE" | jq -s '
  group_by(.proposal_type // "unknown") |
  map({
    type: .[0].proposal_type // "unknown",
    total: length,
    approved: (map(select(.approved_by_critic == true)) | length),
    rejected: (map(select(.approved_by_critic == false)) | length),
    implemented: (map(select(.implemented == true)) | length),
    approval_rate: ((map(select(.approved_by_critic == true)) | length) / length),
    implementation_rate: (
      if (map(select(.approved_by_critic == true)) | length) > 0 then
        ((map(select(.implemented == true)) | length) /
         (map(select(.approved_by_critic == true)) | length))
      else 0 end
    )
  })
')

echo -e "${GREEN}Proposal Performance by Type:${NC}"
echo "$ANALYSIS" | jq -r '
  .[] |
  "  \(.type | ascii_upcase):
    Total: \(.total) | Approved: \(.approved) | Rejected: \(.rejected) | Implemented: \(.implemented)
    Approval Rate: \(.approval_rate * 100 | floor)%
    Implementation Rate: \(.implementation_rate * 100 | floor)%"
'
echo ""

# Detect issues and opportunities
ISSUES_FOUND=0

echo -e "${YELLOW}Optimization Opportunities:${NC}"

# Issue 1: Low approval rate for a proposal type
LOW_APPROVAL=$(echo "$ANALYSIS" | jq -r '
  .[] |
  select(.approval_rate < 0.4 and .total >= 3) |
  @json
')

if [ -n "$LOW_APPROVAL" ]; then
  echo "$LOW_APPROVAL" | jq -r '
    "  ⚠️  \(.type | ascii_upcase) proposals have low approval rate (\(.approval_rate * 100 | floor)%)
    Total proposals: \(.total)
    Recommendation: Review signal detection for this type
    Impact: Reduce low-quality proposals that waste critic analysis time"
  '
  ISSUES_FOUND=$((ISSUES_FOUND + 1))
  echo ""
fi

# Issue 2: Low implementation rate (approved but not implemented)
LOW_IMPLEMENTATION=$(echo "$ANALYSIS" | jq -r '
  .[] |
  select(.approved > 0 and .implementation_rate < 0.5) |
  @json
')

if [ -n "$LOW_IMPLEMENTATION" ]; then
  echo "$LOW_IMPLEMENTATION" | jq -r '
    "  ⚠️  \(.type | ascii_upcase) proposals are approved but rarely implemented (\(.implementation_rate * 100 | floor)%)
    Approved: \(.approved) | Implemented: \(.implemented)
    Recommendation: Make proposals more actionable
    Impact: Increase value of approved proposals"
  '
  ISSUES_FOUND=$((ISSUES_FOUND + 1))
  echo ""
fi

# Issue 3: High variance in success rates (some types much better)
VARIANCE=$(echo "$ANALYSIS" | jq -r '
  if length > 1 then
    (map(.approval_rate) | max) - (map(.approval_rate) | min)
  else
    0
  end
')

if [ "$(echo "$VARIANCE > 0.3" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
  BEST_TYPE=$(echo "$ANALYSIS" | jq -r 'max_by(.approval_rate) | .type')
  WORST_TYPE=$(echo "$ANALYSIS" | jq -r 'min_by(.approval_rate) | .type')

  echo -e "  ${BLUE}ℹ️  Large variance in proposal success rates${NC}"
  echo "    Best: $BEST_TYPE ($(echo "$ANALYSIS" | jq -r --arg type "$BEST_TYPE" '.[] | select(.type == $type) | (.approval_rate * 100 | floor)')%)"
  echo "    Worst: $WORST_TYPE ($(echo "$ANALYSIS" | jq -r --arg type "$WORST_TYPE" '.[] | select(.type == $type) | (.approval_rate * 100 | floor)')%)"
  echo "    Opportunity: Focus on signal types similar to $BEST_TYPE"
  echo "    Impact: Increase overall proposal quality"
  echo ""
fi

# Analyze signal sources (if available)
if cat "$METRICS_FILE" | jq -e 'has("signal_type")' > /dev/null 2>&1; then
  SIGNAL_ANALYSIS=$(cat "$METRICS_FILE" | jq -s '
    group_by(.signal_type // "unknown") |
    map({
      signal: .[0].signal_type // "unknown",
      total: length,
      approved: (map(select(.approved_by_critic == true)) | length),
      approval_rate: ((map(select(.approved_by_critic == true)) | length) / length)
    }) |
    sort_by(-.approval_rate)
  ')

  echo -e "${GREEN}Best Performing Signals:${NC}"
  echo "$SIGNAL_ANALYSIS" | jq -r '
    .[:3] |
    .[] |
    "  ✨ \(.signal): \(.approval_rate * 100 | floor)% approval (\(.approved)/\(.total))"
  '
  echo ""
fi

# Summary and recommendations
echo -e "${BLUE}=== Summary ===${NC}"
if [ "$ISSUES_FOUND" -eq 0 ]; then
  echo -e "${GREEN}✅ Proposal quality appears good${NC}"
  echo "Reflect is generating proposals that pass critic validation."
else
  echo -e "${YELLOW}$ISSUES_FOUND optimization opportunities detected${NC}"
  echo ""
  echo "Recommended Actions:"
  echo "1. Review proposal types with low approval rates"
  echo "2. Adjust signal detection rules in reflect config"
  echo "3. Focus on successful signal patterns"
  echo ""
  echo "Note: Reflect plugin will self-improve based on these patterns"
fi

echo ""
echo "Next analysis after: $((MIN_SAMPLES - TOTAL + 10)) more proposals"

# Exit with status indicating issues found
if [ "$ISSUES_FOUND" -gt 0 ]; then
  exit 1  # Issues detected
else
  exit 0  # No issues
fi
