#!/usr/bin/env bash
# reflect-analyze-all.sh - Batch analysis across all skills
#
# Usage:
#   reflect-analyze-all.sh [OPTIONS]
#
# Options:
#   --min-skills N         Minimum skills affected for pattern (default: 2)
#   --output FILE          Write report to file (default: stdout)
#   --format FORMAT        Output format: markdown|json (default: markdown)
#   --days N               Analyze metrics from last N days (default: 90)
#   --verbose              Show detailed analysis
#   --help                 Show this help message
#
# Examples:
#   reflect-analyze-all.sh
#   reflect-analyze-all.sh --min-skills 3 --days 30
#   reflect-analyze-all.sh --output batch-analysis.md --verbose
#
# This script:
# 1. Analyzes metrics across all skills
# 2. Identifies patterns affecting multiple skills
# 3. Finds systemic improvements needed
# 4. Generates cross-skill recommendations

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GLOBAL_CLAUDE_DIR="${HOME}/.claude"
METRICS_FILE="$GLOBAL_CLAUDE_DIR/reflect-metrics.jsonl"
MEMORIES_DIR="$GLOBAL_CLAUDE_DIR/memories"

# Defaults
MIN_SKILLS=2
OUTPUT_FILE=""
FORMAT="markdown"
DAYS=90
VERBOSE=false

# Parse arguments
show_help() {
    head -n 25 "$0" | grep '^#' | sed 's/^# \?//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --min-skills)
            MIN_SKILLS="$2"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --format)
            FORMAT="$2"
            shift 2
            ;;
        --days)
            DAYS="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Utility functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}✓${NC} $*" >&2
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*" >&2
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

# Check dependencies
check_dependencies() {
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed"
        exit 1
    fi
}

# Calculate cutoff date
get_cutoff_date() {
    if date --version >/dev/null 2>&1; then
        # GNU date
        date -d "$DAYS days ago" -u +"%Y-%m-%dT%H:%M:%SZ"
    else
        # BSD date (macOS)
        date -v-"${DAYS}"d -u +"%Y-%m-%dT%H:%M:%SZ"
    fi
}

# Analyze metrics for patterns
analyze_patterns() {
    local cutoff_date
    cutoff_date=$(get_cutoff_date)

    if [ ! -f "$METRICS_FILE" ]; then
        log_warning "No metrics file found at $METRICS_FILE"
        return
    fi

    if [ "$VERBOSE" = true ]; then
        log_info "Analyzing metrics since $cutoff_date"
    fi

    # Extract recent proposal events
    local recent_proposals
    recent_proposals=$(jq -r "select(.type == \"proposal\") | select(.timestamp >= \"$cutoff_date\")" "$METRICS_FILE" 2>/dev/null || echo "")

    if [ -z "$recent_proposals" ]; then
        log_warning "No recent proposals found in the last $DAYS days"
        return
    fi

    # Analyze patterns
    analyze_rejection_patterns "$recent_proposals"
    analyze_external_feedback_patterns "$recent_proposals"
    analyze_critic_score_patterns "$recent_proposals"
    analyze_common_changes "$recent_proposals"
}

# Find skills with high rejection rates
analyze_rejection_patterns() {
    local proposals="$1"

    if [ "$VERBOSE" = true ]; then
        log_info "Analyzing rejection patterns..."
    fi

    # Group by skill and count rejections
    local rejection_stats
    rejection_stats=$(echo "$proposals" | \
        jq -r 'select(.user_action == "rejected") | .skill' | \
        sort | uniq -c | sort -rn)

    if [ -n "$rejection_stats" ]; then
        echo "## High Rejection Rates"
        echo
        echo "Skills with multiple rejections (may indicate misaligned signal detection):"
        echo
        echo "| Skill | Rejections |"
        echo "|-------|------------|"
        echo "$rejection_stats" | while read -r count skill; do
            if [ "$count" -ge 2 ]; then
                echo "| $skill | $count |"
            fi
        done
        echo
    fi
}

# Find patterns in external feedback across skills
analyze_external_feedback_patterns() {
    local proposals="$1"

    if [ "$VERBOSE" = true ]; then
        log_info "Analyzing external feedback patterns..."
    fi

    # Find skills with external feedback
    local feedback_stats
    feedback_stats=$(echo "$proposals" | \
        jq -r 'select(.external_feedback_count > 0) | "\(.skill):\(.external_feedback_count)"' | \
        sort | uniq)

    if [ -n "$feedback_stats" ]; then
        echo "## External Feedback Patterns"
        echo
        echo "Skills with objective signals (tests, lint, build errors):"
        echo
        echo "| Skill | Feedback Events |"
        echo "|-------|-----------------|"
        echo "$feedback_stats" | while IFS=: read -r skill count; do
            echo "| $skill | $count |"
        done
        echo
        echo "**Recommendation**: High external feedback indicates skills that benefit most from objective signals."
        echo
    fi
}

# Analyze critic scores across skills
analyze_critic_score_patterns() {
    local proposals="$1"

    if [ "$VERBOSE" = true ]; then
        log_info "Analyzing critic score patterns..."
    fi

    # Find proposals with critic scores
    local critic_stats
    critic_stats=$(echo "$proposals" | \
        jq -r 'select(.critic_score != null) | "\(.skill):\(.critic_score):\(.user_action)"')

    if [ -z "$critic_stats" ]; then
        return
    fi

    echo "## Critic Score Analysis"
    echo
    echo "### Average Scores by Skill"
    echo
    echo "| Skill | Avg Score | Approved | Rejected |"
    echo "|-------|-----------|----------|----------|"

    # Calculate averages per skill
    local skills
    skills=$(echo "$critic_stats" | cut -d: -f1 | sort | uniq)

    for skill in $skills; do
        local skill_scores
        skill_scores=$(echo "$critic_stats" | grep "^$skill:" || true)

        if [ -n "$skill_scores" ]; then
            local avg_score
            avg_score=$(echo "$skill_scores" | cut -d: -f2 | awk '{sum+=$1; count++} END {printf "%.0f", sum/count}')

            local approved
            approved=$(echo "$skill_scores" | grep ":approved$" | wc -l | tr -d ' ')

            local rejected
            rejected=$(echo "$skill_scores" | grep ":rejected$" | wc -l | tr -d ' ')

            echo "| $skill | $avg_score | $approved | $rejected |"
        fi
    done
    echo
    echo "**Insights**:"
    echo "- Scores 90-100: Excellent proposals (approve immediately)"
    echo "- Scores 70-89: Good proposals (minor improvements)"
    echo "- Scores <70: Need significant revision"
    echo
}

# Find common changes across skills
analyze_common_changes() {
    local proposals="$1"

    if [ "$VERBOSE" = true ]; then
        log_info "Analyzing common changes..."
    fi

    # Extract change descriptions from all proposals
    local all_changes
    all_changes=$(echo "$proposals" | \
        jq -r '.proposal.changes[]?.description // empty' 2>/dev/null || echo "")

    if [ -z "$all_changes" ]; then
        return
    fi

    # Look for common keywords indicating cross-skill patterns
    echo "## Common Change Themes"
    echo
    echo "Recurring themes across multiple skills:"
    echo

    # Count keyword occurrences
    local accessibility_count
    accessibility_count=$(echo "$all_changes" | grep -ic "accessibility\|aria\|a11y" || echo "0")

    local type_count
    type_count=$(echo "$all_changes" | grep -ic "type\|typing\|typescript" || echo "0")

    local test_count
    test_count=$(echo "$all_changes" | grep -ic "test\|testing\|coverage" || echo "0")

    local error_count
    error_count=$(echo "$all_changes" | grep -ic "error\|exception\|handling" || echo "0")

    local doc_count
    doc_count=$(echo "$all_changes" | grep -ic "document\|comment\|docstring" || echo "0")

    # Report themes affecting MIN_SKILLS+ skills
    local themes_found=false

    if [ "$accessibility_count" -ge "$MIN_SKILLS" ]; then
        echo "- **Accessibility** ($accessibility_count mentions) - aria-labels, semantic HTML, a11y compliance"
        themes_found=true
    fi

    if [ "$type_count" -ge "$MIN_SKILLS" ]; then
        echo "- **Type Safety** ($type_count mentions) - TypeScript, type hints, type checking"
        themes_found=true
    fi

    if [ "$test_count" -ge "$MIN_SKILLS" ]; then
        echo "- **Testing** ($test_count mentions) - test coverage, missing tests, test quality"
        themes_found=true
    fi

    if [ "$error_count" -ge "$MIN_SKILLS" ]; then
        echo "- **Error Handling** ($error_count mentions) - exception handling, error messages, edge cases"
        themes_found=true
    fi

    if [ "$doc_count" -ge "$MIN_SKILLS" ]; then
        echo "- **Documentation** ($doc_count mentions) - comments, docstrings, documentation quality"
        themes_found=true
    fi

    if [ "$themes_found" = false ]; then
        echo "*No recurring themes found affecting $MIN_SKILLS+ skills*"
    fi

    echo
}

# Generate recommendations
generate_recommendations() {
    if [ "$VERBOSE" = true ]; then
        log_info "Generating recommendations..."
    fi

    echo "## Recommended Actions"
    echo
    echo "### Cross-Skill Improvements"
    echo
    echo "Based on the analysis, consider these systemic improvements:"
    echo
    echo "1. **Review ~/.claude/memories/skill-patterns.md**"
    echo "   - Add recurring themes as cross-skill patterns"
    echo "   - Document patterns that affect multiple skills"
    echo "   - Example: If accessibility appears in 3+ skills, create a shared pattern"
    echo
    echo "2. **Update High-Rejection Skills**"
    echo "   - Skills with 3+ rejections may have misaligned signal detection"
    echo "   - Review meta-learnings in ~/.claude/memories/reflect-meta.md"
    echo "   - Consider adjusting confidence thresholds"
    echo
    echo "3. **Leverage External Feedback**"
    echo "   - Skills with high external feedback benefit most from objective signals"
    echo "   - Capture test/lint errors as signals during reflection"
    echo "   - Prioritize external feedback over conversation signals"
    echo
    echo "4. **Improve Low-Scoring Proposals**"
    echo "   - Review critic feedback for skills with avg scores <70"
    echo "   - Common issues: vague evidence, scope creep, breaking changes"
    echo "   - See skills/reflect/references/proposal-validation-guide.md"
    echo
}

# Main analysis
main() {
    check_dependencies

    if [ "$VERBOSE" = true ]; then
        log_info "Batch Skill Analysis - Last $DAYS days"
        echo
    fi

    # Start report
    {
        echo "# Batch Skill Analysis Report"
        echo
        echo "**Generated**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
        echo "**Analysis Period**: Last $DAYS days"
        echo "**Minimum Skills for Pattern**: $MIN_SKILLS"
        echo
        echo "---"
        echo

        # Run analyses
        analyze_patterns

        # Generate recommendations
        generate_recommendations

        echo "---"
        echo
        echo "*Generated by reflect-analyze-all.sh*"
        echo "*See ~/.claude/reflect-metrics.jsonl for raw data*"
    } | if [ -n "$OUTPUT_FILE" ]; then
        tee "$OUTPUT_FILE"
        log_success "Report written to $OUTPUT_FILE"
    else
        cat
    fi
}

main
