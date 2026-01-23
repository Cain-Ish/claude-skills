#!/bin/bash
# ============================================================================
# Self-Debugger Plugin - Self-Improvement
# ============================================================================
# Analyzes metrics, adjusts rule confidence, and improves the self-debugger
# based on feedback from fix applications and user interactions.
#
# Usage:
#   ./self-improve.sh
#
# Analyzes:
#   - Fix approval rates per rule
#   - False positive detection
#   - Rule effectiveness scores
#   - User feedback patterns
#
# Outputs:
#   - Updated rule confidence scores
#   - Recommendations for rule improvements
#   - Self-improvement commit to feature branch
# ============================================================================

set -euo pipefail

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/git-utils.sh"

# ============================================================================
# Metrics Analysis
# ============================================================================

analyze_rule_effectiveness() {
    local rule_id="$1"

    if [[ ! -f "$METRICS_FILE" ]]; then
        echo "0"
        return 0
    fi

    # Count total detections for this rule
    local total_detections
    total_detections=$(grep "\"rule_id\": \"$rule_id\"" "$ISSUES_FILE" 2>/dev/null | wc -l | tr -d ' ')

    # Count applied fixes for this rule
    local applied_fixes
    applied_fixes=$(grep "\"rule_id\": \"$rule_id\"" "$FIXES_FILE" 2>/dev/null | wc -l | tr -d ' ')

    # Calculate approval rate
    if [[ "$total_detections" -eq 0 ]]; then
        echo "0"
        return 0
    fi

    local approval_rate
    approval_rate=$(( (applied_fixes * 100) / total_detections ))

    echo "$approval_rate"
}

# Calculate overall plugin health score
calculate_health_score() {
    log_info "Calculating self-debugger health score..."

    if [[ ! -f "$ISSUES_FILE" ]]; then
        echo "100"  # No issues = perfect health
        return 0
    fi

    # Metrics to consider:
    # 1. Total issues detected
    local total_issues
    total_issues=$(wc -l < "$ISSUES_FILE" 2>/dev/null | tr -d ' ')

    # 2. Issues resolved
    local resolved_issues
    resolved_issues=$(grep -c "\"status\": \"applied\"" "$ISSUES_FILE" 2>/dev/null || echo "0")

    # 3. False positives (issues rejected or never fixed)
    local pending_old
    pending_old=$(grep "\"status\": \"pending\"" "$ISSUES_FILE" 2>/dev/null | \
        while read -r line; do
            detected_at=$(echo "$line" | grep -o '"detected_at": "[^"]*"' | cut -d'"' -f4)
            age_seconds=$(get_age_seconds "$detected_at" 2>/dev/null || echo "0")
            age_days=$((age_seconds / 86400))
            if [[ $age_days -gt 7 ]]; then
                echo "1"
            fi
        done | wc -l | tr -d ' ')

    # Calculate score
    if [[ "$total_issues" -eq 0 ]]; then
        echo "100"
        return 0
    fi

    local resolution_rate=$((resolved_issues * 100 / total_issues))
    local false_positive_rate=$((pending_old * 100 / total_issues))
    local health_score=$((resolution_rate - false_positive_rate))

    # Clamp to 0-100
    if [[ $health_score -lt 0 ]]; then
        health_score=0
    elif [[ $health_score -gt 100 ]]; then
        health_score=100
    fi

    echo "$health_score"
}

# ============================================================================
# Rule Confidence Adjustment
# ============================================================================

adjust_rule_confidence() {
    local rule_file="$1"
    local approval_rate="$2"

    if ! has_jq; then
        log_error "jq required for rule adjustment"
        return 1
    fi

    # Read current confidence
    local current_confidence
    current_confidence=$(jq -r '.confidence' "$rule_file" 2>/dev/null || echo "0.5")

    # Adjust confidence based on approval rate
    local new_confidence
    if [[ "$approval_rate" -ge 90 ]]; then
        # High approval rate - increase confidence
        new_confidence=$(echo "$current_confidence + 0.05" | bc 2>/dev/null || echo "$current_confidence")
    elif [[ "$approval_rate" -le 30 ]]; then
        # Low approval rate - decrease confidence
        new_confidence=$(echo "$current_confidence - 0.10" | bc 2>/dev/null || echo "$current_confidence")
    else
        # Medium approval rate - slight decrease
        new_confidence=$(echo "$current_confidence - 0.02" | bc 2>/dev/null || echo "$current_confidence")
    fi

    # Clamp to 0.1-1.0
    if (( $(echo "$new_confidence > 1.0" | bc -l 2>/dev/null || echo "0") )); then
        new_confidence="1.0"
    elif (( $(echo "$new_confidence < 0.1" | bc -l 2>/dev/null || echo "0") )); then
        new_confidence="0.1"
    fi

    # Update rule file
    local temp_file
    temp_file=$(mktemp)
    jq ".confidence = $new_confidence | .last_updated = \"$(get_timestamp)\"" "$rule_file" > "$temp_file"
    mv "$temp_file" "$rule_file"

    log_info "Adjusted rule confidence: $(basename "$rule_file") $current_confidence → $new_confidence (approval: ${approval_rate}%)"
}

# ============================================================================
# Main Logic
# ============================================================================

main() {
    init_debugger

    log_info "Starting self-improvement analysis..."

    # Detect source repository
    if ! detect_source_repo; then
        log_error "Not in source repository"
        exit 1
    fi

    log_info "Source repository: $SOURCE_REPO_ROOT"

    # Calculate health score
    local health_score
    health_score=$(calculate_health_score)
    log_info "Self-debugger health score: $health_score/100"

    # Analyze each rule in core directory
    local rules_updated=0

    for rule_file in "$RULES_CORE_DIR"/*.json; do
        if [[ ! -f "$rule_file" ]]; then
            continue
        fi

        local rule_id
        rule_id=$(jq -r '.rule_id' "$rule_file" 2>/dev/null || echo "")

        if [[ -z "$rule_id" ]]; then
            log_warn "Skipping invalid rule file: $rule_file"
            continue
        fi

        # Analyze effectiveness
        local approval_rate
        approval_rate=$(analyze_rule_effectiveness "$rule_id")

        log_info "Rule: $rule_id - Approval rate: ${approval_rate}%"

        # Adjust confidence if significant data
        local total_detections
        total_detections=$(grep -c "\"rule_id\": \"$rule_id\"" "$ISSUES_FILE" 2>/dev/null || echo "0")

        if [[ "$total_detections" -ge 5 ]]; then
            # Enough data to adjust confidence
            adjust_rule_confidence "$rule_file" "$approval_rate"
            rules_updated=$((rules_updated + 1))
        else
            log_debug "Not enough data for rule: $rule_id (only $total_detections detections)"
        fi
    done

    # Generate improvement report
    log_success "Self-improvement analysis complete"
    log_info "Rules updated: $rules_updated"
    log_info "Health score: $health_score/100"

    # Commit improvements if any rules were updated
    if [[ "$rules_updated" -gt 0 ]]; then
        log_info "Committing rule confidence adjustments..."

        # Create feature branch
        local branch_name="debug/self-debugger/confidence-adjustment"

        if ! acquire_branch_lock "$branch_name"; then
            log_error "Failed to acquire branch lock"
            exit 1
        fi

        trap 'release_branch_lock "$branch_name"' EXIT INT TERM

        # Create branch
        cd "$SOURCE_REPO_ROOT" || exit 1
        if ! git rev-parse --verify "$branch_name" >/dev/null 2>&1; then
            git checkout -b "$branch_name"
        else
            git checkout "$branch_name"
        fi

        # Stage rule changes
        git add plugins/self-debugger/rules/core/*.json

        # Commit
        local commit_msg
        commit_msg=$(cat <<EOF
self-improve: Adjust rule confidence based on approval rates

Updated $rules_updated rules based on fix approval metrics.

Health score: $health_score/100

Rule adjustments:
$(for rule_file in "$RULES_CORE_DIR"/*.json; do
    if git diff --cached --name-only | grep -q "$(basename "$rule_file")"; then
        rule_id=$(jq -r '.rule_id' "$rule_file" 2>/dev/null)
        confidence=$(jq -r '.confidence' "$rule_file" 2>/dev/null)
        echo "  - $rule_id: confidence = $confidence"
    fi
done)

Session-ID: $CURRENT_SESSION_ID
Auto-generated: self-debugger self-improvement

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)

        if git commit -m "$commit_msg"; then
            log_success "Committed rule confidence adjustments"

            # Push branch
            if push_branch "$branch_name"; then
                log_success "Pushed branch: $branch_name"
                log_info "Create MR for human review"
            fi
        else
            log_warn "No changes to commit"
        fi

        release_branch_lock "$branch_name"
    else
        log_info "No rule updates needed (insufficient data)"
    fi

    # Record self-improvement event
    local improvement_record
    improvement_record=$(cat <<EOF
{
  "timestamp": "$(get_timestamp)",
  "session_id": "$CURRENT_SESSION_ID",
  "event": "self_improvement",
  "health_score": $health_score,
  "rules_updated": $rules_updated
}
EOF
)
    append_jsonl "$improvement_record" "$METRICS_FILE"
}

# ============================================================================
# Entry Point
# ============================================================================

main "$@"
