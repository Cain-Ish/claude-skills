#!/bin/bash
# ============================================================================
# Self-Debugger Plugin - Background Monitor
# ============================================================================
# Runs continuous scanning in the background with periodic intervals.
# Launched by SessionStart hook, stopped by Stop hook.
#
# Usage:
#   ./start-monitor.sh
#
# Environment Variables:
#   CLAUDE_SESSION_ID - Current session ID (required)
#   SCAN_INTERVAL_SECONDS - Time between scans (default: 300 = 5 minutes)
# ============================================================================

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ============================================================================
# Signal Handlers
# ============================================================================

cleanup() {
    log_info "Monitor: Shutting down gracefully (session: $CURRENT_SESSION_ID)"

    # Update session status
    local session_dir="$SESSIONS_DIR/$CURRENT_SESSION_ID"
    if [[ -d "$session_dir" ]]; then
        local status_file="$session_dir/status.json"
        write_json '{"status":"stopped","stopped_at":"'"$(get_timestamp)"'"}' "$status_file"
    fi

    exit 0
}

trap cleanup SIGTERM SIGINT EXIT

# ============================================================================
# Heartbeat Update
# ============================================================================

update_heartbeat() {
    local session_dir="$SESSIONS_DIR/$CURRENT_SESSION_ID"
    local heartbeat_file="$session_dir/heartbeat.ts"

    mkdir -p "$session_dir"
    echo "$(get_timestamp)" > "$heartbeat_file"
}

# ============================================================================
# Main Monitor Loop
# ============================================================================

main() {
    init_debugger

    log_info "Monitor: Starting background monitor (session: $CURRENT_SESSION_ID)"

    # Validate session ID
    if ! validate_session_id "$CURRENT_SESSION_ID"; then
        log_error "Monitor: Invalid session ID: $CURRENT_SESSION_ID"
        exit 1
    fi

    # Create session directory
    local session_dir="$SESSIONS_DIR/$CURRENT_SESSION_ID"
    mkdir -p "$session_dir"

    # Initial status
    local status_file="$session_dir/status.json"
    write_json '{"status":"running","started_at":"'"$(get_timestamp)"'","pid":'"$$"'}' "$status_file"

    # Wait for session to initialize
    log_debug "Monitor: Waiting 5 seconds for session initialization..."
    sleep 5

    # Main scan loop
    local scan_count=0

    while true; do
        scan_count=$((scan_count + 1))

        log_info "Monitor: Starting scan #$scan_count (interval: ${SCAN_INTERVAL_SECONDS}s)"

        # Update heartbeat
        update_heartbeat

        # Run scan
        local scan_log="$session_dir/scan-${scan_count}.log"

        if "$SCRIPT_DIR/scan-plugins.sh" > "$scan_log" 2>&1; then
            log_debug "Monitor: Scan #$scan_count completed successfully"
        else
            log_warn "Monitor: Scan #$scan_count failed (see $scan_log)"
        fi

        # Wait for next interval
        log_debug "Monitor: Waiting ${SCAN_INTERVAL_SECONDS}s until next scan..."
        sleep "$SCAN_INTERVAL_SECONDS"
    done
}

# ============================================================================
# Entry Point
# ============================================================================

main "$@"
