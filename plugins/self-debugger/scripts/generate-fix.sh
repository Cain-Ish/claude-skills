#!/bin/bash
# ============================================================================
# Self-Debugger Plugin - Generate Fix
# ============================================================================
# Generates a fix proposal for a detected issue using the debugger-fixer
# and debugger-critic agents.
#
# Usage:
#   ./generate-fix.sh <issue-id>
#
# Output:
#   JSON fix proposal with critic validation
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

    if [[ $# -lt 1 ]]; then
        log_error "Usage: $0 <issue-id>"
        exit 1
    fi

    local issue_id="$1"

    log_info "Generating fix for issue: $issue_id"

    # Validate issue ID format
    if ! [[ "$issue_id" =~ ^[a-f0-9-]{36}$ ]] && ! [[ "$issue_id" =~ ^[a-f0-9-]{8}$ ]]; then
        log_error "Invalid issue ID format: $issue_id"
        exit 1
    fi

    # Load issue from findings
    if [[ ! -f "$ISSUES_FILE" ]]; then
        log_error "No issues file found at: $ISSUES_FILE"
        exit 1
    fi

    local issue
    if [[ ${#issue_id} -eq 8 ]]; then
        # Short ID - match prefix
        issue=$(grep "\"issue_id\": \"$issue_id" "$ISSUES_FILE" | head -1 || echo "")
    else
        # Full ID
        issue=$(grep "\"issue_id\": \"$issue_id\"" "$ISSUES_FILE" | head -1 || echo "")
    fi

    if [[ -z "$issue" ]]; then
        log_error "Issue not found: $issue_id"
        exit 1
    fi

    log_debug "Found issue in findings file"

    # TODO: Invoke debugger-fixer agent
    # This will be implemented when agent invocation is available
    # For now, return placeholder

    log_warn "Fix generation requires debugger-fixer agent (Phase 3)"
    log_warn "Returning placeholder fix proposal"

    # Placeholder fix proposal
    local fix_proposal
    fix_proposal=$(cat <<'EOF'
{
  "issue_id": "placeholder",
  "status": "pending",
  "message": "Fix generation will be available in Phase 3",
  "next_steps": [
    "Implement agent invocation via Task tool",
    "debugger-fixer agent generates fix from rule template",
    "debugger-critic agent validates fix (score 0-100)",
    "Return fix proposal with diff for user approval"
  ]
}
EOF
)

    echo "$fix_proposal"
}

# ============================================================================
# Entry Point
# ============================================================================

main "$@"
