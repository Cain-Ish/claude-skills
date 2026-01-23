#!/bin/bash
# ============================================================================
# Self-Debugger Plugin - Apply Fix
# ============================================================================
# Applies a validated fix proposal to a feature branch with git commit.
#
# Usage:
#   ./apply-fix.sh <issue-id> <fix-proposal-json>
#
# Environment Variables:
#   DRY_RUN - Set to "true" to show diff without applying
# ============================================================================

set -euo pipefail

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/git-utils.sh"

# ============================================================================
# Main Logic
# ============================================================================

main() {
    init_debugger

    if [[ $# -lt 2 ]]; then
        log_error "Usage: $0 <issue-id> <fix-proposal-json>"
        exit 1
    fi

    local issue_id="$1"
    local fix_proposal_file="$2"

    local dry_run="${DRY_RUN:-false}"

    log_info "Applying fix for issue: $issue_id"

    # Detect source repository
    if ! detect_source_repo; then
        log_error "Not in source repository (no .git or plugins/ found)"
        exit 1
    fi

    log_info "Source repository: $SOURCE_REPO_ROOT"

    # Load fix proposal
    if [[ ! -f "$fix_proposal_file" ]]; then
        log_error "Fix proposal file not found: $fix_proposal_file"
        exit 1
    fi

    if ! has_jq; then
        log_error "jq is required to apply fixes"
        exit 1
    fi

    # Extract fix details
    local plugin
    plugin=$(jq -r '.plugin' "$fix_proposal_file" 2>/dev/null || echo "")
    local component
    component=$(jq -r '.component' "$fix_proposal_file" 2>/dev/null || echo "")
    local fix_type
    fix_type=$(jq -r '.fix_type' "$fix_proposal_file" 2>/dev/null || echo "")
    local description
    description=$(jq -r '.description' "$fix_proposal_file" 2>/dev/null || echo "")

    if [[ -z "$plugin" ]] || [[ -z "$component" ]]; then
        log_error "Invalid fix proposal: missing plugin or component"
        exit 1
    fi

    log_info "Plugin: $plugin"
    log_info "Component: $component"
    log_info "Fix type: $fix_type"
    log_info "Description: $description"

    # Create short issue ID for branch name
    local issue_short="${issue_id:0:8}"
    local branch_name="debug/${plugin}/${issue_short}"

    # Acquire branch lock
    log_info "Acquiring branch lock: $branch_name"
    if ! acquire_branch_lock "$branch_name"; then
        log_error "Failed to acquire branch lock (another instance may be working on this)"
        exit 1
    fi

    # Ensure lock is released on exit
    trap 'release_branch_lock "$branch_name"' EXIT INT TERM

    # Dry run mode - show diff only
    if [[ "$dry_run" == "true" ]]; then
        log_warn "DRY RUN MODE - No changes will be applied"
        local diff
        diff=$(jq -r '.diff' "$fix_proposal_file" 2>/dev/null || echo "")
        echo "$diff"
        log_success "Dry run complete (use DRY_RUN=false to apply)"
        exit 0
    fi

    # Create feature branch
    log_info "Creating feature branch: $branch_name"
    if ! create_feature_branch "$plugin" "$issue_short"; then
        log_error "Failed to create feature branch"
        exit 1
    fi

    # Apply fix to file
    local file_path
    file_path="$SOURCE_REPO_ROOT/plugins/$plugin/$component"

    log_info "Applying fix to: $file_path"

    # TODO: Apply fix based on fix_type (prepend, append, replace, merge)
    # For now, use git apply with diff
    local diff
    diff=$(jq -r '.diff' "$fix_proposal_file" 2>/dev/null || echo "")

    if [[ -n "$diff" ]]; then
        # Try to apply diff
        if echo "$diff" | git apply --check 2>/dev/null; then
            echo "$diff" | git apply
            log_success "Applied diff successfully"
        else
            log_error "Failed to apply diff (conflicts or format issues)"
            exit 1
        fi
    else
        log_warn "No diff in fix proposal, applying manually based on fix_type"

        # Apply based on fix_type
        case "$fix_type" in
            "prepend")
                local content
                content=$(jq -r '.fixed_content' "$fix_proposal_file" 2>/dev/null || echo "")
                if [[ -n "$content" ]]; then
                    echo "$content" > "${file_path}.tmp"
                    cat "$file_path" >> "${file_path}.tmp"
                    mv "${file_path}.tmp" "$file_path"
                    log_success "Prepended content to file"
                fi
                ;;
            *)
                log_error "Unsupported fix_type: $fix_type (manual application required)"
                exit 1
                ;;
        esac
    fi

    # Stage the file
    cd "$SOURCE_REPO_ROOT" || exit 1
    git add "plugins/$plugin/$component"

    # Commit fix
    log_info "Committing fix..."
    if ! commit_fix "$issue_id" "$plugin" "$component" "$description"; then
        log_error "Failed to commit fix"
        exit 1
    fi

    # Push to origin
    log_info "Pushing branch to origin..."
    if ! push_branch "$branch_name"; then
        log_warn "Failed to push branch (you may need to push manually)"
    fi

    # Update issue status
    log_info "Updating issue status to 'applied'..."
    # TODO: Update issue status in issues.jsonl

    # Record fix in fixes.jsonl
    local fix_record
    fix_record=$(cat <<EOF
{
  "issue_id": "$issue_id",
  "applied_at": "$(get_timestamp)",
  "session_id": "$CURRENT_SESSION_ID",
  "branch": "$branch_name",
  "plugin": "$plugin",
  "component": "$component",
  "description": "$description"
}
EOF
)
    append_jsonl "$fix_record" "$FIXES_FILE"

    # Record metrics
    local metric_record
    metric_record=$(cat <<EOF
{
  "timestamp": "$(get_timestamp)",
  "session_id": "$CURRENT_SESSION_ID",
  "event": "fix_applied",
  "issue_id": "$issue_id",
  "plugin": "$plugin",
  "branch": "$branch_name"
}
EOF
)
    append_jsonl "$metric_record" "$METRICS_FILE"

    log_success "Fix applied successfully!"
    log_info "Branch: $branch_name"
    log_info "Next step: Review MR and merge to main"
}

# ============================================================================
# Entry Point
# ============================================================================

main "$@"
