#!/bin/bash
# ============================================================================
# Process Janitor - Scan for Orphaned Sessions
# ============================================================================
# Scans for orphaned Claude Code sessions using multiple safety checks:
# - Process existence check
# - Heartbeat staleness detection
# - Grace period enforcement
# - Hostname verification
# ============================================================================

set -euo pipefail

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/platform.sh"
source "$SCRIPT_DIR/lib/process-tracker.sh"

# ============================================================================
# Options
# ============================================================================

QUIET_MODE=false
OUTPUT_FORMAT="text"  # text or json

# ============================================================================
# Functions
# ============================================================================

# Parse command line options
parse_options() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --quiet|-q)
                QUIET_MODE=true
                shift
                ;;
            --json)
                OUTPUT_FORMAT="json"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help
show_help() {
    cat <<EOF
Usage: cleanup-scan.sh [OPTIONS]

Scan for orphaned Claude Code sessions.

OPTIONS:
    --quiet, -q     Suppress informational output
    --json          Output results in JSON format
    --help, -h      Show this help message

EXAMPLES:
    cleanup-scan.sh                # Scan and display results
    cleanup-scan.sh --quiet        # Scan silently (for automation)
    cleanup-scan.sh --json         # Output JSON for programmatic use
EOF
}

# Detect orphaned sessions
detect_orphaned_sessions() {
    local orphaned=()
    local active=()
    local skipped=()

    # Get all session IDs
    local session_ids
    session_ids=($(get_all_session_ids))

    if [[ ${#session_ids[@]} -eq 0 ]]; then
        log_debug "No sessions found"
        echo ""
        return 0
    fi

    for session_id in "${session_ids[@]}"; do
        # Skip current session
        if [[ "$session_id" == "$CURRENT_SESSION_ID" ]]; then
            active+=("$session_id")
            continue
        fi

        # Skip if session doesn't exist
        if ! session_exists "$session_id"; then
            continue
        fi

        # Safety check: Only cleanup sessions on same machine
        if ! is_session_local "$session_id"; then
            log_debug "Skipping remote session: $session_id"
            skipped+=("$session_id:remote")
            continue
        fi

        # Safety check: Session must be old enough (grace period)
        if ! is_session_old_enough "$session_id"; then
            log_debug "Skipping too recent session: $session_id"
            skipped+=("$session_id:too_recent")
            active+=("$session_id")
            continue
        fi

        # Check if orphaned
        if is_session_orphaned "$session_id"; then
            local metadata_file
            metadata_file=$(get_session_metadata_file "$session_id")
            local pid
            pid=$(extract_json_number "$metadata_file" "pid")

            orphaned+=("$session_id:$pid")
            log_debug "Detected orphaned session: $session_id (PID: $pid)"
        else
            active+=("$session_id")
        fi
    done

    # Output results
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        output_json_results "${orphaned[@]}" "${active[@]}" "${skipped[@]}"
    else
        output_text_results "${orphaned[@]}" "${active[@]}" "${skipped[@]}"
    fi
}

# Output results in text format
output_text_results() {
    local orphaned_count=0
    local active_count=0
    local skipped_count=0

    # Count orphaned
    for item in "$@"; do
        if [[ "$item" == *:* ]]; then
            local session_id="${item%%:*}"
            local info="${item#*:}"

            if [[ "$info" == "remote" ]] || [[ "$info" == "too_recent" ]]; then
                ((skipped_count++)) || true
            else
                ((orphaned_count++)) || true
            fi
        fi
    done

    # Calculate active (total - orphaned - skipped)
    local total_sessions
    total_sessions=$(get_all_session_ids | wc -l)
    active_count=$((total_sessions - orphaned_count - skipped_count))

    if [[ "$QUIET_MODE" == "false" ]]; then
        echo ""
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║              PROCESS CLEANUP SCAN RESULTS                    ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Active Sessions:   $active_count"
        echo "Orphaned Sessions: $orphaned_count"
        echo "Skipped Sessions:  $skipped_count"
        echo "Total Tracked:     $total_sessions"
        echo ""

        if [[ $orphaned_count -gt 0 ]]; then
            echo "┌─ ORPHANED SESSIONS ───────────────────────────────────────┐"

            local index=1
            for item in "$@"; do
                if [[ "$item" == *:* ]]; then
                    local session_id="${item%%:*}"
                    local pid="${item#*:}"

                    # Skip non-orphaned items
                    if [[ "$pid" == "remote" ]] || [[ "$pid" == "too_recent" ]]; then
                        continue
                    fi

                    local metadata_file
                    metadata_file=$(get_session_metadata_file "$session_id")

                    if [[ -f "$metadata_file" ]]; then
                        local start_time
                        start_time=$(extract_json_field "$metadata_file" "start_time")
                        local last_heartbeat
                        last_heartbeat=$(extract_json_field "$metadata_file" "last_heartbeat")
                        local working_dir
                        working_dir=$(extract_json_field "$metadata_file" "working_dir")

                        echo "│ [$index] Session: $session_id"
                        echo "│     PID: $pid (NOT RUNNING)"
                        echo "│     Started: $start_time"
                        echo "│     Last Heartbeat: $last_heartbeat (STALE)"
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
        else
            echo "✓ No orphaned sessions detected"
        fi
        echo ""
    fi

    # Return exit code based on orphaned count
    [[ $orphaned_count -eq 0 ]]
}

# Output results in JSON format
output_json_results() {
    local orphaned_sessions=()
    local active_sessions=()

    for item in "$@"; do
        if [[ "$item" == *:* ]]; then
            local session_id="${item%%:*}"
            local info="${item#*:}"

            if [[ "$info" != "remote" ]] && [[ "$info" != "too_recent" ]]; then
                orphaned_sessions+=("\"$session_id\"")
            fi
        fi
    done

    local orphaned_list=$(IFS=,; echo "${orphaned_sessions[*]}")
    local orphaned_count=${#orphaned_sessions[@]}

    echo "{"
    echo "  \"orphaned_count\": $orphaned_count,"
    echo "  \"orphaned_sessions\": [$orphaned_list]"
    echo "}"
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Parse options
    parse_options "$@"

    # Initialize
    init_janitor

    # Detect orphaned sessions
    detect_orphaned_sessions
}

main "$@"
