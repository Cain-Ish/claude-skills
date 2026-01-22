#!/bin/bash
# ============================================================================
# Process Janitor - Register Session
# ============================================================================
# Registers the current Claude Code session for tracking.
# Called automatically by the SessionStart hook.
# ============================================================================

set -euo pipefail

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/platform.sh"
source "$SCRIPT_DIR/lib/process-tracker.sh"

# ============================================================================
# Main
# ============================================================================

main() {
    # Initialize
    init_janitor

    # Check if we have a valid session ID
    if [[ "$CURRENT_SESSION_ID" == "unknown" ]]; then
        log_error "CLAUDE_SESSION_ID not set"
        exit 1
    fi

    # Register the session
    if register_session; then
        log_info "Session tracking initialized"

        # Check if auto-cleanup is enabled
        if [[ "${JANITOR_AUTO_CLEANUP:-false}" == "true" ]]; then
            log_info "Auto-cleanup enabled - scanning for orphaned sessions..."

            # Run cleanup scan (non-interactive, auto mode)
            if [[ -x "$SCRIPT_DIR/cleanup-scan.sh" ]]; then
                "$SCRIPT_DIR/cleanup-scan.sh" --quiet 2>/dev/null || true
            fi
        fi
    else
        log_error "Failed to register session"
        exit 1
    fi
}

main "$@"
