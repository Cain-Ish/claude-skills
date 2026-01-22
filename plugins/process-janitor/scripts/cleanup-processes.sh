#!/bin/bash
# ============================================================================
# Process Janitor - Clean Up Orphaned Processes
# ============================================================================
# Safely terminates orphaned Claude Code processes and cleans up their files.
# Implements multiple safety layers:
# - Confirmation prompts (unless auto mode)
# - Dry-run mode
# - Multi-factor orphan verification
# - Signal escalation (SIGTERM → SIGKILL)
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

DRY_RUN=true  # Default to dry-run for safety
AUTO_MODE=false
QUIET_MODE=false

# ============================================================================
# Functions
# ============================================================================

# Parse command line options
parse_options() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --execute)
                DRY_RUN=false
                shift
                ;;
            --auto)
                AUTO_MODE=true
                DRY_RUN=false
                shift
                ;;
            --quiet|-q)
                QUIET_MODE=true
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
Usage: cleanup-processes.sh [OPTIONS]

Safely clean up orphaned Claude Code processes and session files.

OPTIONS:
    --dry-run       Show what would be cleaned up without making changes (default)
    --execute       Execute cleanup (will prompt for confirmation)
    --auto          Execute cleanup automatically without prompts
    --quiet, -q     Suppress informational output
    --help, -h      Show this help message

EXAMPLES:
    cleanup-processes.sh                    # Dry-run mode (safe preview)
    cleanup-processes.sh --execute          # Interactive cleanup
    cleanup-processes.sh --auto --quiet     # Automated cleanup (for cron)

SAFETY:
    - Current session is never cleaned up
    - Sessions must pass 5 safety checks before cleanup
    - Confirmation required unless --auto is used
    - Defaults to dry-run mode
EOF
}

# Get list of orphaned sessions
get_orphaned_sessions() {
    "$SCRIPT_DIR/cleanup-scan.sh" --json 2>/dev/null | \
        grep -o '"orphaned_sessions":[^]]*]' | \
        grep -o '[a-zA-Z0-9-]*' | \
        grep -v "orphaned_sessions" || echo ""
}

# Verify session is safe to cleanup (5-layer safety check)
verify_safe_to_cleanup() {
    local session_id="$1"

    # Layer 1: Current session whitelist
    if [[ "$session_id" == "$CURRENT_SESSION_ID" ]]; then
        log_error "SAFETY: Refusing to cleanup current session"
        return 1
    fi

    # Layer 2: Session must exist
    if ! session_exists "$session_id"; then
        log_debug "Session $session_id does not exist"
        return 1
    fi

    # Layer 3: Must be on same hostname
    if ! is_session_local "$session_id"; then
        log_error "SAFETY: Refusing to cleanup remote session"
        return 1
    fi

    # Layer 4: Must pass grace period
    if ! is_session_old_enough "$session_id"; then
        log_error "SAFETY: Session too recent (grace period not elapsed)"
        return 1
    fi

    # Layer 5: Must be actually orphaned
    if ! is_session_orphaned "$session_id"; then
        log_error "SAFETY: Session is not orphaned"
        return 1
    fi

    return 0
}

# Clean up a single session
cleanup_single_session() {
    local session_id="$1"
    local dry_run="${2:-true}"

    # Get metadata
    local metadata_file
    metadata_file=$(get_session_metadata_file "$session_id")

    if [[ ! -f "$metadata_file" ]]; then
        log_warn "Metadata file not found for session: $session_id"
        return 1
    fi

    local pid
    pid=$(extract_json_number "$metadata_file" "pid")

    if ! validate_pid "$pid" 2>/dev/null; then
        log_warn "Invalid PID for session $session_id"
        # Still cleanup files
        if [[ "$dry_run" == "false" ]]; then
            cleanup_session_files "$session_id"
        fi
        return 0
    fi

    # Verify safe to cleanup
    if ! verify_safe_to_cleanup "$session_id"; then
        log_error "Failed safety checks for session: $session_id"
        return 1
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY-RUN] Would terminate process $pid (session: $session_id)"
        log_info "[DRY-RUN] Would cleanup session files: $(get_session_dir "$session_id")"
        return 0
    fi

    # Terminate process if still running
    if is_process_running "$pid"; then
        log_info "Terminating process $pid (session: $session_id)..."
        if terminate_process_gracefully "$pid"; then
            log_success "Process $pid terminated"
        else
            log_error "Failed to terminate process $pid"
            return 1
        fi
    else
        log_debug "Process $pid not running, cleaning up files only"
    fi

    # Clean up session files
    log_info "Cleaning up session files: $session_id"
    cleanup_session_files "$session_id"

    log_success "Cleaned up session: $session_id"
    return 0
}

# Main cleanup workflow
run_cleanup() {
    local orphaned_sessions
    orphaned_sessions=($(get_orphaned_sessions))

    if [[ ${#orphaned_sessions[@]} -eq 0 ]]; then
        if [[ "$QUIET_MODE" == "false" ]]; then
            log_success "No orphaned sessions found"
        fi
        return 0
    fi

    # Display summary
    if [[ "$QUIET_MODE" == "false" ]]; then
        echo ""
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║           PROCESS CLEANUP - ORPHANED SESSIONS                ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        echo ""
        echo "Found ${#orphaned_sessions[@]} orphaned session(s):"
        echo ""

        for session_id in "${orphaned_sessions[@]}"; do
            local metadata_file
            metadata_file=$(get_session_metadata_file "$session_id")

            if [[ -f "$metadata_file" ]]; then
                local pid
                pid=$(extract_json_number "$metadata_file" "pid")
                local start_time
                start_time=$(extract_json_field "$metadata_file" "start_time")
                local working_dir
                working_dir=$(extract_json_field "$metadata_file" "working_dir")

                echo "  • Session: $session_id"
                echo "    PID: $pid"
                echo "    Started: $start_time"
                echo "    Working Dir: $working_dir"
                echo ""
            fi
        done

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "═══════════════════════════════════════════════════════════"
            echo "DRY-RUN MODE: No changes will be made"
            echo "Use --execute to perform cleanup"
            echo "═══════════════════════════════════════════════════════════"
            echo ""
        fi
    fi

    # Request confirmation (unless auto mode)
    if [[ "$DRY_RUN" == "false" ]] && [[ "$AUTO_MODE" == "false" ]]; then
        echo ""
        echo -n "Proceed with cleanup? [y/N] "
        read -r response

        case "$response" in
            [yY][eE][sS]|[yY])
                log_info "Proceeding with cleanup..."
                ;;
            *)
                log_info "Cleanup cancelled"
                return 0
                ;;
        esac
    fi

    # Execute cleanup
    local success_count=0
    local failure_count=0

    for session_id in "${orphaned_sessions[@]}"; do
        if [[ -z "$session_id" ]]; then
            continue
        fi

        if cleanup_single_session "$session_id" "$DRY_RUN"; then
            ((success_count++)) || true
        else
            ((failure_count++)) || true
        fi
    done

    # Summary
    if [[ "$QUIET_MODE" == "false" ]]; then
        echo ""
        echo "═══════════════════════════════════════════════════════════"
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "DRY-RUN COMPLETE"
            echo "  Would cleanup: $success_count session(s)"
        else
            echo "CLEANUP COMPLETE"
            echo "  Cleaned up: $success_count session(s)"
            if [[ $failure_count -gt 0 ]]; then
                echo "  Failed: $failure_count session(s)"
            fi
        fi
        echo "═══════════════════════════════════════════════════════════"
        echo ""
    fi

    [[ $failure_count -eq 0 ]]
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Parse options
    parse_options "$@"

    # Initialize
    init_janitor

    # Run cleanup
    run_cleanup
}

main "$@"
