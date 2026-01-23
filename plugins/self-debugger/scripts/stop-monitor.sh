#!/bin/bash
# ============================================================================
# Self-Debugger Plugin - Stop Monitor
# ============================================================================
# Gracefully stops the background monitor for the current session.
# Called by Stop hook on session end.
#
# Usage:
#   ./stop-monitor.sh
#
# Environment Variables:
#   CLAUDE_SESSION_ID - Current session ID (required)
# ============================================================================

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ============================================================================
# Main Logic
# ============================================================================

main() {
    init_debugger

    log_info "Stopping monitor (session: $CURRENT_SESSION_ID)"

    # Validate session ID
    if ! validate_session_id "$CURRENT_SESSION_ID"; then
        log_error "Invalid session ID: $CURRENT_SESSION_ID"
        exit 1
    fi

    # Find PID file
    local session_dir="$SESSIONS_DIR/$CURRENT_SESSION_ID"
    local pid_file="$session_dir/monitor.pid"

    if [[ ! -f "$pid_file" ]]; then
        log_warn "No monitor PID file found at: $pid_file"
        exit 0
    fi

    # Read PID
    local monitor_pid
    monitor_pid=$(cat "$pid_file" 2>/dev/null || echo "")

    if [[ -z "$monitor_pid" ]]; then
        log_warn "Empty PID file, cleaning up"
        rm -f "$pid_file"
        exit 0
    fi

    # Validate PID format
    if ! validate_pid "$monitor_pid"; then
        log_error "Invalid PID in file: $monitor_pid"
        rm -f "$pid_file"
        exit 1
    fi

    # Check if process exists
    if ! kill -0 "$monitor_pid" 2>/dev/null; then
        log_warn "Monitor process (PID: $monitor_pid) not running, cleaning up"
        rm -f "$pid_file"
        exit 0
    fi

    # Send SIGTERM for graceful shutdown
    log_info "Sending SIGTERM to monitor (PID: $monitor_pid)"
    kill -TERM "$monitor_pid" 2>/dev/null || true

    # Wait for graceful shutdown (max 5 seconds)
    local wait_count=0
    while kill -0 "$monitor_pid" 2>/dev/null; do
        wait_count=$((wait_count + 1))

        if [[ $wait_count -ge 5 ]]; then
            log_warn "Monitor did not stop gracefully, sending SIGKILL"
            kill -KILL "$monitor_pid" 2>/dev/null || true
            break
        fi

        sleep 1
    done

    # Clean up PID file
    rm -f "$pid_file"

    log_success "Monitor stopped successfully"
}

# ============================================================================
# Entry Point
# ============================================================================

main "$@"
