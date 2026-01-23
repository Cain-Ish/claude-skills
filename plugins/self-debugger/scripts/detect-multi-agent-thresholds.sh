#!/bin/bash
#
# Multi-Agent Threshold Detection Script
# Analyzes multi-agent metrics to detect threshold calibration opportunities
#

set -euo pipefail

METRICS_FILE="$HOME/.claude/multi-agent-metrics.jsonl"
MIN_SAMPLES=20

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if metrics file exists
if [ ! -f "$METRICS_FILE" ]; then
  echo "No multi-agent metrics found yet."
  echo "Metrics will be collected as you use /multi-agent command."
  echo "Location: $METRICS_FILE"
  exit 0
fi

# Count total executions
TOTAL=$(wc -l < "$METRICS_FILE" | tr -d ' ')

if [ "$TOTAL" -lt "$MIN_SAMPLES" ]; then
  echo "Insufficient data for threshold analysis"
  echo "Current: $TOTAL executions"
  echo "Required: $MIN_SAMPLES executions"
  echo "Use /multi-agent more to collect data for optimization."
  exit 0
fi

echo -e "${BLUE}=== Multi-Agent Threshold Analysis ===${NC}"
echo "Analyzing $TOTAL executions..."
echo ""

# Analyze approval rates by pattern
ANALYSIS=$(cat "$METRICS_FILE" | jq -s '
  group_by(.pattern) |
  map({
    pattern: .[0].pattern,
    total: length,
    approved: (map(select(.user_approved == true)) | length),
    rejected: (map(select(.user_approved == false)) | length),
    approval_rate: ((map(select(.user_approved == true)) | length) / length),
    avg_score: ((map(.complexity_score) | add) / length),
    min_score: (map(.complexity_score) | min),
    max_score: (map(.complexity_score) | max)
  })
')

echo -e "${GREEN}Pattern Performance:${NC}"
echo "$ANALYSIS" | jq -r '
  .[] |
  "  \(.pattern | ascii_upcase):
    Total: \(.total) | Approved: \(.approved) | Rejected: \(.rejected)
    Approval Rate: \(.approval_rate * 100 | floor)%
    Score Range: \(.min_score)-\(.max_score) (avg: \(.avg_score | floor))"
'
echo ""

# Detect issues and opportunities
ISSUES_FOUND=0

echo -e "${YELLOW}Optimization Opportunities:${NC}"

# Issue 1: Low approval rate for a pattern
LOW_APPROVAL=$(echo "$ANALYSIS" | jq -r '
  .[] |
  select(.approval_rate < 0.5 and .total >= 5) |
  @json
')

if [ -n "$LOW_APPROVAL" ]; then
  echo "$LOW_APPROVAL" | jq -r '
    "  ⚠️  \(.pattern | ascii_upcase) pattern has low approval rate (\(.approval_rate * 100 | floor)%)
    Average score: \(.avg_score | floor)
    Recommendation: Increase threshold to reduce false-positive suggestions
    Impact: Fewer rejected multi-agent proposals"
  '
  ISSUES_FOUND=$((ISSUES_FOUND + 1))
  echo ""
fi

# Issue 2: Very high approval rate (could be more aggressive)
HIGH_APPROVAL=$(echo "$ANALYSIS" | jq -r '
  .[] |
  select(.approval_rate > 0.9 and .total >= 5) |
  @json
')

if [ -n "$HIGH_APPROVAL" ]; then
  echo "$HIGH_APPROVAL" | jq -r '
    "  ✨ \(.pattern | ascii_upcase) pattern has very high approval rate (\(.approval_rate * 100 | floor)%)
    Average score: \(.avg_score | floor)
    Opportunity: Could decrease threshold for faster routing
    Impact: More tasks benefit from multi-agent coordination"
  '
  echo ""
fi

# Issue 3: Score boundary analysis
# Look for rejection clusters at specific score ranges
BOUNDARY_ISSUES=$(cat "$METRICS_FILE" | jq -s '
  map(select(.user_approved == false)) |
  group_by((.complexity_score / 5 | floor) * 5) |
  map({
    score_bucket: .[0].complexity_score,
    count: length,
    pattern: .[0].pattern
  }) |
  map(select(.count >= 3))
')

if [ "$(echo "$BOUNDARY_ISSUES" | jq 'length')" -gt 0 ]; then
  echo -e "  ${RED}⚠️  Score Boundary Issues Detected:${NC}"
  echo "$BOUNDARY_ISSUES" | jq -r '
    .[] |
    "    Pattern: \(.pattern) | Score ~\(.score_bucket) | Rejections: \(.count)
    → Consider adjusting threshold near this boundary"
  '
  ISSUES_FOUND=$((ISSUES_FOUND + 1))
  echo ""
fi

# Summary and recommendations
echo -e "${BLUE}=== Summary ===${NC}"
if [ "$ISSUES_FOUND" -eq 0 ]; then
  echo -e "${GREEN}✅ Thresholds appear well-calibrated for your usage patterns${NC}"
  echo "Current configuration is working well. Continue monitoring."
else
  echo -e "${YELLOW}$ISSUES_FOUND optimization opportunities detected${NC}"
  echo ""
  echo "Recommended Actions:"
  echo "1. Review approval patterns above"
  echo "2. Adjust thresholds in: ~/.claude/multi-agent.local.md"
  echo "3. Or modify: plugins/multi-agent/config/default-config.json"
  echo ""
  echo "Example adjustment:"
  echo "---"
  echo "complexity_thresholds:"
  echo "  simple: 30"
  echo "  moderate: 55    # Increased from 50 based on data"
  echo "  complex: 70"
  echo "---"
fi

echo ""
echo "Next analysis after: $((MIN_SAMPLES - TOTAL + 20)) more executions"

# Exit with status indicating issues found
if [ "$ISSUES_FOUND" -gt 0 ]; then
  exit 1  # Issues detected
else
  exit 0  # No issues
fi
