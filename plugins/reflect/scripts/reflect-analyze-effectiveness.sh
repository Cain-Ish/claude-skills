#!/bin/bash
# Reflect Analyze Effectiveness: Meta-Analysis for Self-Improvement
# Analyzes metrics to identify patterns and propose improvements to reflect itself

set -euo pipefail

# Paths
GLOBAL_CLAUDE_DIR="${HOME}/.claude"
METRICS_FILE="$GLOBAL_CLAUDE_DIR/reflect-metrics.jsonl"
QUEUE_FILE="$GLOBAL_CLAUDE_DIR/reflect-improvements-queue.md"

# Usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Analyze reflect effectiveness metrics and propose meta-improvements.

Options:
  --output FILE    Save analysis to file (default: stdout)
  --append-queue   Append findings to improvement queue

Examples:
  $0                          # Display analysis
  $0 --append-queue           # Add to improvement queue
  $0 --output analysis.md     # Save to file

EOF
    exit 1
}

# Check if metrics file exists
if [ ! -f "$METRICS_FILE" ]; then
    echo "Error: No metrics data found at $METRICS_FILE"
    exit 1
fi

# Parse arguments
OUTPUT_FILE=""
APPEND_QUEUE=false

while [ $# -gt 0 ]; do
    case "$1" in
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --append-queue)
            APPEND_QUEUE=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Get timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DATE_READABLE=$(date +"%Y-%m-%d %H:%M")

# Extract data
PROPOSALS=$(grep -v '^#' "$METRICS_FILE" | grep "\"type\":\"proposal\"" || true)
OUTCOMES=$(grep -v '^#' "$METRICS_FILE" | grep "\"type\":\"outcome\"" || true)

if [ -z "$PROPOSALS" ]; then
    echo "Error: No proposal data in metrics database"
    exit 1
fi

# Calculate key metrics
TOTAL_PROPOSALS=$(echo "$PROPOSALS" | wc -l | tr -d ' ')
APPROVED=$(echo "$PROPOSALS" | (grep "\"user_action\":\"approved\"" || true) | wc -l | tr -d ' ')
REJECTED=$(echo "$PROPOSALS" | (grep "\"user_action\":\"rejected\"" || true) | wc -l | tr -d ' ')

ACCEPTANCE_RATE=0
if [ "$TOTAL_PROPOSALS" -gt 0 ]; then
    ACCEPTANCE_RATE=$(echo "scale=1; $APPROVED * 100 / $TOTAL_PROPOSALS" | bc)
fi

TOTAL_OUTCOMES=$(echo "$OUTCOMES" | wc -l | tr -d ' ' || echo "0")
HELPFUL=0
EFFECTIVENESS_RATE="N/A"

if [ "$TOTAL_OUTCOMES" -gt 0 ]; then
    HELPFUL=$(echo "$OUTCOMES" | (grep "\"improvement_helpful\":true" || true) | wc -l | tr -d ' ')
    if [ "$TOTAL_OUTCOMES" -gt 0 ]; then
        EFFECTIVENESS_RATE=$(echo "scale=1; $HELPFUL * 100 / $TOTAL_OUTCOMES" | bc)
    fi
fi

# Analyze by skill
SKILLS=$(echo "$PROPOSALS" | grep -o '"skill":"[^"]*"' | cut -d'"' -f4 | sort | uniq)

# Generate analysis report
generate_report() {
    cat <<EOF
# Reflect Effectiveness Analysis

**Generated**: $DATE_READABLE
**Analysis Period**: All time
**Data Source**: ~/.claude/reflect-metrics.jsonl

---

## Summary Metrics

| Metric | Value | Status |
|--------|-------|--------|
| Total Proposals | $TOTAL_PROPOSALS | - |
| Accepted | $APPROVED | - |
| Rejected | $REJECTED | - |
| Acceptance Rate | ${ACCEPTANCE_RATE}% | $(rate_status "$ACCEPTANCE_RATE") |
| Outcomes Tracked | $TOTAL_OUTCOMES | - |
| Helpful Improvements | $HELPFUL | - |
| Effectiveness Rate | ${EFFECTIVENESS_RATE}% | $(rate_status "$EFFECTIVENESS_RATE") |

---

## Insights & Patterns

### Acceptance Rate Analysis

$(acceptance_analysis "$ACCEPTANCE_RATE" "$TOTAL_PROPOSALS")

### Effectiveness Analysis

$(effectiveness_analysis "$EFFECTIVENESS_RATE" "$TOTAL_OUTCOMES")

### Per-Skill Breakdown

$(per_skill_analysis)

---

## Proposed Meta-Improvements

$(propose_improvements "$ACCEPTANCE_RATE" "$EFFECTIVENESS_RATE" "$TOTAL_OUTCOMES")

---

## Action Items

1. Review proposed improvements above
2. Run \`/reflect reflect\` to apply meta-improvements to reflect skill
3. Continue tracking outcomes to validate effectiveness
4. Re-run this analysis monthly to monitor trends

---

**Next Steps**: Use this analysis to inform \`/reflect reflect\` proposals for improving the reflect skill itself.
EOF
}

# Helper: Rate status emoji
rate_status() {
    local rate="$1"
    if [ "$rate" = "N/A" ]; then
        echo "⚠️ No data"
    elif (( $(echo "$rate >= 75" | bc -l) )); then
        echo "✅ Excellent"
    elif (( $(echo "$rate >= 50" | bc -l) )); then
        echo "⚠️ Needs improvement"
    else
        echo "❌ Poor"
    fi
}

# Helper: Acceptance analysis
acceptance_analysis() {
    local rate="$1"
    local total="$2"

    if (( $(echo "$rate >= 70" | bc -l) )); then
        cat <<EOF
**Status**: ✅ Good acceptance rate (${rate}%)

Proposals are generally well-received. Reflect is accurately detecting signals and proposing relevant improvements.

**Recommendation**: Maintain current signal detection strategy.
EOF
    elif (( $(echo "$rate >= 50" | bc -l) )); then
        cat <<EOF
**Status**: ⚠️ Moderate acceptance rate (${rate}%)

About half of proposals are rejected. This suggests:
- Some proposals may be too aggressive or speculative
- Signal detection may include false positives
- Confidence levels may need recalibration

**Recommendation**: Review rejected proposals to identify patterns. Consider raising thresholds for MED and LOW confidence proposals.
EOF
    else
        cat <<EOF
**Status**: ❌ Low acceptance rate (${rate}%)

Most proposals are rejected. Critical issues:
- Signal detection is likely misinterpreting user feedback
- Proposals may be based on insufficient evidence
- Confidence calibration is off

**Recommendation**: Immediate review required. Consider:
1. Only propose HIGH confidence changes
2. Require more evidence before proposing
3. Review signal-examples.md for accuracy
EOF
    fi
}

# Helper: Effectiveness analysis
effectiveness_analysis() {
    local rate="$1"
    local total="$2"

    if [ "$total" -eq 0 ]; then
        cat <<EOF
**Status**: ⚠️ No outcome data

No effectiveness tracking yet. Cannot determine if accepted improvements actually help.

**Recommendation**:
- Start tracking outcomes with \`reflect-track-outcome.sh\`
- After using an improved skill, log whether it helped
- Track for at least 10 proposals before drawing conclusions
EOF
    elif (( $(echo "$rate >= 75" | bc -l) )); then
        cat <<EOF
**Status**: ✅ High effectiveness (${rate}%)

Accepted improvements are helping in practice. Reflect is successfully identifying valuable changes.

**Recommendation**: Continue current approach. Focus on scaling to more skills.
EOF
    elif (( $(echo "$rate >= 50" | bc -l) )); then
        cat <<EOF
**Status**: ⚠️ Moderate effectiveness (${rate}%)

Some improvements help, but many don't deliver expected value. Possible causes:
- Changes are too generic or vague
- Skills need more specific, actionable guidance
- User expectations not met

**Recommendation**: Focus on more specific, actionable proposals. Review helpful vs. not-helpful outcomes to identify what works.
EOF
    else
        cat <<EOF
**Status**: ❌ Low effectiveness (${rate}%)

Most accepted improvements don't actually help. Serious issue:
- Proposals may sound good but lack practical value
- Changes may be addressing wrong problems
- Skills may need different types of improvements

**Recommendation**: Deep analysis required:
1. Compare helpful vs. not-helpful changes
2. Interview users about what would actually help
3. Consider focusing on different aspects (constraints vs. preferences)
EOF
    fi
}

# Helper: Per-skill analysis
per_skill_analysis() {
    if [ -z "$SKILLS" ]; then
        echo "No skills found in metrics data."
        return
    fi

    echo "| Skill | Proposals | Accepted | Rejection Rate |"
    echo "|-------|-----------|----------|----------------|"

    for skill in $SKILLS; do
        local skill_proposals=$(echo "$PROPOSALS" | (grep "\"skill\":\"$skill\"" || true) | wc -l | tr -d ' ')
        local skill_rejected=$(echo "$PROPOSALS" | (grep "\"skill\":\"$skill\"" || true) | (grep "\"user_action\":\"rejected\"" || true) | wc -l | tr -d ' ')
        local skill_approved=$(echo "$PROPOSALS" | (grep "\"skill\":\"$skill\"" || true) | (grep "\"user_action\":\"approved\"" || true) | wc -l | tr -d ' ')

        local reject_rate=0
        if [ "$skill_proposals" -gt 0 ]; then
            reject_rate=$(echo "scale=1; $skill_rejected * 100 / $skill_proposals" | bc)
        fi

        echo "| $skill | $skill_proposals | $skill_approved | ${reject_rate}% |"
    done
}

# Helper: Propose improvements
propose_improvements() {
    local accept_rate="$1"
    local effect_rate="$2"
    local outcomes="$3"

    cat <<EOF
Based on the metrics analysis, here are recommended improvements to the reflect skill:

### Priority 1: High-Impact Changes

EOF

    if (( $(echo "$accept_rate < 50" | bc -l) )); then
        cat <<EOF
1. **Raise confidence thresholds**
   - Current: Proposing changes with weak signals
   - Recommended: Only propose HIGH confidence (explicit corrections)
   - Expected impact: Higher acceptance rate

EOF
    fi

    if [ "$outcomes" -eq 0 ]; then
        cat <<EOF
2. **Implement outcome tracking workflow**
   - Current: No validation of improvement effectiveness
   - Recommended: Add automated outcome tracking at skill invocation
   - Expected impact: Evidence-based improvement validation

EOF
    fi

    if [ "$effect_rate" != "N/A" ] && (( $(echo "$effect_rate < 50" | bc -l) )); then
        cat <<EOF
3. **Make proposals more actionable**
   - Current: Generic or vague suggestions
   - Recommended: Specific, measurable changes with examples
   - Expected impact: Higher effectiveness rate

EOF
    fi

    cat <<EOF
### Priority 2: Process Improvements

4. **Add proposal templates**
   - Standardize format for consistency
   - Include "before/after" examples in proposals

5. **Implement A/B testing**
   - Test proposal strategies on subset of skills
   - Measure which approaches work best

6. **Create feedback loop**
   - Ask users why they rejected proposals
   - Use feedback to refine detection strategy

### Priority 3: Long-term Enhancements

7. **ML-based signal detection**
   - Train model on accepted vs. rejected proposals
   - Auto-adjust confidence levels

8. **Cross-skill pattern detection**
   - Identify improvements that work across multiple skills
   - Create reusable improvement templates

9. **Automated effectiveness tracking**
   - Auto-track outcomes on next skill usage
   - Generate effectiveness reports automatically
EOF
}

# Generate report
REPORT=$(generate_report)

# Output
if [ -n "$OUTPUT_FILE" ]; then
    echo "$REPORT" > "$OUTPUT_FILE"
    echo "Analysis saved to: $OUTPUT_FILE"
elif [ "$APPEND_QUEUE" = true ]; then
    # Ensure queue file exists
    touch "$QUEUE_FILE"

    # Append to queue
    {
        echo ""
        echo "---"
        echo ""
        echo "## Analysis from $DATE_READABLE"
        echo ""
        echo "$REPORT"
    } >> "$QUEUE_FILE"

    echo "Analysis appended to: $QUEUE_FILE"
else
    echo "$REPORT"
fi
