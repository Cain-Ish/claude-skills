#!/bin/bash
# ============================================================================
# Process Janitor - Generate Detailed Report
# ============================================================================
# Generates a comprehensive report of all tracked sessions including:
# - Current session status
# - Active sessions
# - Orphaned sessions
# - Session metadata and history
# ============================================================================

set -euo pipefail

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/platform.sh"
source "$SCRIPT_DIR/lib/process-tracker.sh"

# ============================================================================
# Functions
# ============================================================================

# Format time ago from timestamp
time_ago() {
    local timestamp="$1"
    local age_seconds
    age_seconds=$(get_age_seconds "$timestamp")

    if [[ $age_seconds -lt 60 ]]; then
        echo "${age_seconds} seconds ago"
    elif [[ $age_seconds -lt 3600 ]]; then
        echo "$((age_seconds / 60)) minutes ago"
    elif [[ $age_seconds -lt 86400 ]]; then
        echo "$((age_seconds / 3600)) hours ago"
    else
        echo "$((age_seconds / 86400)) days ago"
    fi
}

# Generate detailed report
generate_report() {
    # Initialize array explicitly to avoid unbound variable error with set -u
    local session_ids=()
    session_ids=($(get_all_session_ids))

    local active_count=0
    local orphaned_count=0
    local total_count=${#session_ids[@]}

    # Count active vs orphaned (skip if no sessions)
    if [[ ${#session_ids[@]} -gt 0 ]]; then
        for session_id in "${session_ids[@]}"; do
            if [[ "$session_id" == "$CURRENT_SESSION_ID" ]] || ! is_session_orphaned "$session_id"; then
                ((active_count++)) || true
            else
                ((orphaned_count++)) || true
            fi
        done
    fi

    # Header
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                  PROCESS CLEANUP REPORT                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Active Sessions:   $active_count"
    echo "Orphaned Sessions: $orphaned_count"
    echo "Total Tracked:     $total_count"
    echo ""

    # Current session
    if [[ "$CURRENT_SESSION_ID" != "unknown" ]]; then
        echo "┌─ CURRENT SESSION ─────────────────────────────────────────┐"

        local current_metadata_file
        current_metadata_file=$(get_session_metadata_file "$CURRENT_SESSION_ID")

        if [[ -f "$current_metadata_file" ]]; then
            local pid
            pid=$(extract_json_number "$current_metadata_file" "pid")
            local start_time
            start_time=$(extract_json_field "$current_metadata_file" "start_time")
            local last_heartbeat
            last_heartbeat=$(extract_json_field "$current_metadata_file" "last_heartbeat")
            local working_dir
            working_dir=$(extract_json_field "$current_metadata_file" "working_dir")

            echo "│ Session ID: $CURRENT_SESSION_ID"
            echo "│ PID: $pid"
            echo "│ Started: $start_time ($(time_ago "$start_time"))"
            echo "│ Last Heartbeat: $(time_ago "$last_heartbeat")"
            echo "│ Working Dir: $working_dir"
            echo "│ Status: ACTIVE ✓"
        else
            echo "│ Session ID: $CURRENT_SESSION_ID"
            echo "│ Status: Not yet registered"
        fi

        echo "└───────────────────────────────────────────────────────────┘"
        echo ""
    fi

    # Orphaned sessions
    if [[ $orphaned_count -gt 0 ]]; then
        echo "┌─ ORPHANED SESSIONS ───────────────────────────────────────┐"

        local index=1
        for session_id in "${session_ids[@]}"; do
            # Skip current session
            if [[ "$session_id" == "$CURRENT_SESSION_ID" ]]; then
                continue
            fi

            # Check if orphaned
            if is_session_orphaned "$session_id"; then
                local metadata_file
                metadata_file=$(get_session_metadata_file "$session_id")

                if [[ -f "$metadata_file" ]]; then
                    local pid
                    pid=$(extract_json_number "$metadata_file" "pid")
                    local start_time
                    start_time=$(extract_json_field "$metadata_file" "start_time")
                    local last_heartbeat
                    last_heartbeat=$(extract_json_field "$metadata_file" "last_heartbeat")
                    local working_dir
                    working_dir=$(extract_json_field "$metadata_file" "working_dir")

                    echo "│ [$index] Session: $session_id"
                    if is_process_running "$pid"; then
                        echo "│     PID: $pid (RUNNING but stale heartbeat)"
                    else
                        echo "│     PID: $pid (NOT RUNNING)"
                    fi
                    echo "│     Started: $start_time ($(time_ago "$start_time"))"
                    echo "│     Last Heartbeat: $last_heartbeat ($(time_ago "$last_heartbeat"))"
                    echo "│     Working Dir: $working_dir"

                    if is_process_running "$pid"; then
                        echo "│     Reason: Heartbeat timeout"
                    else
                        echo "│     Reason: Process no longer exists"
                    fi

                    echo "│"
                    ((index++)) || true
                fi
            fi
        done

        echo "└───────────────────────────────────────────────────────────┘"
        echo ""
        echo "Run '/cleanup run' to clean up orphaned sessions"
    fi

    # Active sessions (other than current)
    local other_active_count=$((active_count - 1))
    if [[ $other_active_count -gt 0 ]]; then
        echo "┌─ OTHER ACTIVE SESSIONS ───────────────────────────────────┐"

        local index=1
        for session_id in "${session_ids[@]}"; do
            # Skip current session
            if [[ "$session_id" == "$CURRENT_SESSION_ID" ]]; then
                continue
            fi

            # Check if active
            if ! is_session_orphaned "$session_id"; then
                local metadata_file
                metadata_file=$(get_session_metadata_file "$session_id")

                if [[ -f "$metadata_file" ]]; then
                    local pid
                    pid=$(extract_json_number "$metadata_file" "pid")
                    local start_time
                    start_time=$(extract_json_field "$metadata_file" "start_time")
                    local working_dir
                    working_dir=$(extract_json_field "$metadata_file" "working_dir")

                    echo "│ [$index] Session: $session_id"
                    echo "│     PID: $pid"
                    echo "│     Started: $start_time ($(time_ago "$start_time"))"
                    echo "│     Working Dir: $working_dir"
                    echo "│     Status: ACTIVE ✓"
                    echo "│"
                    ((index++)) || true
                fi
            fi
        done

        echo "└───────────────────────────────────────────────────────────┘"
    fi

    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Initialize
    init_janitor

    # Generate report
    generate_report
}

main "$@"
