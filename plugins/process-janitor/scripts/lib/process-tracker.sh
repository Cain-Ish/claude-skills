#!/bin/bash
# ============================================================================
# Process Janitor Plugin - Process Tracking Utilities
# ============================================================================
# Process-specific functions for detecting, managing, and cleaning up
# orphaned Claude Code sessions.
#
# Source this file after common.sh and platform.sh:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/platform.sh"
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/process-tracker.sh"
# ============================================================================

# ============================================================================
# Process Information
# ============================================================================

# Get process info (cross-platform)
# Usage: get_process_info 12345
get_process_info() {
    local pid="$1"

    if ! validate_pid "$pid" 2>/dev/null; then
        return 1
    fi

    case "$PLATFORM" in
        windows)
            tasklist //FI "PID eq $pid" //FO CSV //NH 2>/dev/null
            ;;
        macos)
            ps -o pid=,ppid=,command= -p "$pid" 2>/dev/null
            ;;
        linux)
            ps -o pid=,ppid=,cmd= -p "$pid" 2>/dev/null
            ;;
        *)
            ps -p "$pid" 2>/dev/null
            ;;
    esac
}

# Get hostname
# Usage: hostname=$(get_hostname)
get_hostname() {
    hostname 2>/dev/null || echo "unknown"
}

# ============================================================================
# Session Management
# ============================================================================

# Get session directory for a given session ID
# Usage: session_dir=$(get_session_dir "abc123")
get_session_dir() {
    local session_id="$1"

    if ! validate_session_id "$session_id"; then
        return 1
    fi

    echo "$SESSIONS_DIR/$session_id"
}

# Get session metadata file path
# Usage: metadata_file=$(get_session_metadata_file "abc123")
get_session_metadata_file() {
    local session_id="$1"
    local session_dir

    session_dir=$(get_session_dir "$session_id") || return 1
    echo "$session_dir/metadata.json"
}

# Check if session directory exists
# Usage: session_exists "abc123"
session_exists() {
    local session_id="$1"
    local session_dir

    session_dir=$(get_session_dir "$session_id") || return 1
    [[ -d "$session_dir" ]]
}

# Get list of all tracked session IDs
# Usage: sessions=($(get_all_session_ids))
get_all_session_ids() {
    if [[ ! -d "$SESSIONS_DIR" ]]; then
        return 0
    fi

    for session_dir in "$SESSIONS_DIR"/*; do
        if [[ -d "$session_dir" ]]; then
            basename "$session_dir"
        fi
    done
}

# ============================================================================
# Heartbeat Management
# ============================================================================

# Update heartbeat timestamp for a session
# Usage: update_heartbeat "abc123"
update_heartbeat() {
    local session_id="$1"
    local metadata_file

    metadata_file=$(get_session_metadata_file "$session_id") || return 1

    if [[ ! -f "$metadata_file" ]]; then
        log_debug "Metadata file not found for session $session_id"
        return 1
    fi

    # Read current metadata
    local current_metadata
    current_metadata=$(cat "$metadata_file" 2>/dev/null)

    # Update last_heartbeat field
    local updated_metadata
    if has_jq; then
        updated_metadata=$(echo "$current_metadata" | jq --arg ts "$(get_timestamp)" '.last_heartbeat = $ts')
    else
        # Fallback: sed replacement
        local timestamp
        timestamp=$(get_timestamp)
        updated_metadata=$(echo "$current_metadata" | sed "s/\"last_heartbeat\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"last_heartbeat\": \"$timestamp\"/")
    fi

    # Write back atomically
    write_json "$updated_metadata" "$metadata_file"
}

# Start heartbeat background process
# Usage: start_heartbeat "abc123"
start_heartbeat() {
    local session_id="$1"
    local session_dir

    session_dir=$(get_session_dir "$session_id") || return 1

    # Start heartbeat in background
    (
        trap 'exit 0' TERM INT

        while true; do
            update_heartbeat "$session_id" 2>/dev/null || exit 1
            sleep "$HEARTBEAT_INTERVAL_SECONDS"
        done
    ) &

    local heartbeat_pid=$!
    echo "$heartbeat_pid" > "$session_dir/heartbeat.pid"
    log_debug "Started heartbeat process: $heartbeat_pid"
}

# Stop heartbeat background process
# Usage: stop_heartbeat "abc123"
stop_heartbeat() {
    local session_id="$1"
    local session_dir

    session_dir=$(get_session_dir "$session_id") || return 1
    local heartbeat_pid_file="$session_dir/heartbeat.pid"

    if [[ -f "$heartbeat_pid_file" ]]; then
        local heartbeat_pid
        heartbeat_pid=$(cat "$heartbeat_pid_file" 2>/dev/null)

        if [[ -n "$heartbeat_pid" ]] && validate_pid "$heartbeat_pid" 2>/dev/null; then
            if is_process_running "$heartbeat_pid"; then
                kill "$heartbeat_pid" 2>/dev/null || true
                log_debug "Stopped heartbeat process: $heartbeat_pid"
            fi
        fi

        rm -f "$heartbeat_pid_file"
    fi
}

# ============================================================================
# Orphan Detection
# ============================================================================

# Check if a session is old enough to be considered for cleanup
# Usage: is_session_old_enough "abc123"
is_session_old_enough() {
    local session_id="$1"
    local metadata_file

    metadata_file=$(get_session_metadata_file "$session_id") || return 1

    if [[ ! -f "$metadata_file" ]]; then
        return 1
    fi

    local start_time
    start_time=$(extract_json_field "$metadata_file" "start_time")

    if [[ -z "$start_time" ]]; then
        log_debug "No start_time in metadata for session $session_id"
        return 1
    fi

    local age_seconds
    age_seconds=$(get_age_seconds "$start_time")

    local min_age_seconds=$((MIN_SESSION_AGE_MINUTES * 60))

    [[ $age_seconds -gt $min_age_seconds ]]
}

# Check if a session is orphaned
# Usage: is_session_orphaned "abc123"
is_session_orphaned() {
    local session_id="$1"
    local metadata_file

    metadata_file=$(get_session_metadata_file "$session_id") || return 1

    if [[ ! -f "$metadata_file" ]]; then
        log_debug "Metadata file not found for session $session_id"
        return 0  # Consider orphaned if no metadata
    fi

    # Extract PID and last heartbeat
    local pid
    pid=$(extract_json_number "$metadata_file" "pid")
    local last_heartbeat
    last_heartbeat=$(extract_json_field "$metadata_file" "last_heartbeat")

    # Validate PID
    if ! validate_pid "$pid" 2>/dev/null; then
        log_debug "Invalid PID in metadata for session $session_id"
        return 0  # Orphaned
    fi

    # Check if process is still running
    if ! is_process_running "$pid"; then
        log_debug "Process $pid (session $session_id) is not running"
        return 0  # Orphaned
    fi

    # Check heartbeat staleness (in minutes)
    if [[ -n "$last_heartbeat" ]]; then
        local age_seconds
        age_seconds=$(get_age_seconds "$last_heartbeat")
        local stale_threshold_seconds=$((STALE_HEARTBEAT_THRESHOLD_MINUTES * 60))

        if [[ $age_seconds -gt $stale_threshold_seconds ]]; then
            log_debug "Session $session_id has stale heartbeat (${age_seconds}s old)"
            return 0  # Orphaned
        fi
    else
        log_debug "No heartbeat found for session $session_id"
        return 0  # Orphaned
    fi

    # Session is active
    return 1
}

# Check if session is on same hostname (safety check)
# Usage: is_session_local "abc123"
is_session_local() {
    local session_id="$1"
    local metadata_file

    metadata_file=$(get_session_metadata_file "$session_id") || return 1

    if [[ ! -f "$metadata_file" ]]; then
        return 1
    fi

    local session_hostname
    session_hostname=$(extract_json_field "$metadata_file" "hostname")
    local current_hostname
    current_hostname=$(get_hostname)

    [[ "$session_hostname" == "$current_hostname" ]]
}

# ============================================================================
# Process Termination
# ============================================================================

# Terminate a process gracefully (SIGTERM then SIGKILL)
# Usage: terminate_process_gracefully 12345
terminate_process_gracefully() {
    local pid="$1"

    if ! validate_pid "$pid" 2>/dev/null; then
        log_error "Invalid PID: $pid"
        return 1
    fi

    # Skip if already dead
    if ! is_process_running "$pid"; then
        log_debug "Process $pid is not running"
        return 0
    fi

    log_info "Terminating process $pid..."

    # Send SIGTERM
    case "$PLATFORM" in
        windows)
            taskkill //PID "$pid" 2>/dev/null || return 0
            ;;
        *)
            kill -TERM "$pid" 2>/dev/null || return 0
            ;;
    esac

    # Wait up to 5 seconds
    for i in {1..5}; do
        sleep 1
        if ! is_process_running "$pid"; then
            log_success "Process $pid terminated gracefully"
            return 0
        fi
    done

    # Force kill if necessary
    log_warn "Process $pid did not terminate, forcing..."
    case "$PLATFORM" in
        windows)
            taskkill //F //PID "$pid" 2>/dev/null || return 0
            ;;
        *)
            kill -KILL "$pid" 2>/dev/null || return 0
            ;;
    esac

    sleep 1
    if is_process_running "$pid"; then
        log_error "Failed to terminate process $pid"
        return 1
    fi

    log_success "Process $pid terminated forcefully"
    return 0
}

# ============================================================================
# Session Cleanup
# ============================================================================

# Clean up session files
# Usage: cleanup_session_files "abc123"
cleanup_session_files() {
    local session_id="$1"
    local session_dir

    session_dir=$(get_session_dir "$session_id") || return 1

    if [[ ! -d "$session_dir" ]]; then
        log_debug "Session directory not found: $session_dir"
        return 0
    fi

    # Stop heartbeat if running
    stop_heartbeat "$session_id" 2>/dev/null || true

    # Remove session directory
    rm -rf "$session_dir"
    log_debug "Removed session directory: $session_dir"

    # Remove lock files
    local lock_dir="$session_dir.lock.dir"
    if [[ -d "$lock_dir" ]]; then
        rm -rf "$lock_dir"
        log_debug "Removed lock directory: $lock_dir"
    fi
}

# ============================================================================
# Session Registration
# ============================================================================

# Register current session
# Usage: register_session
register_session() {
    local session_id="$CURRENT_SESSION_ID"

    if ! validate_session_id "$session_id"; then
        log_error "Invalid current session ID: $session_id"
        return 1
    fi

    local session_dir
    session_dir=$(get_session_dir "$session_id") || return 1

    # Create session directory
    mkdir -p "$session_dir"

    # Get parent PID
    local ppid
    if [[ "$PLATFORM" == "windows" ]]; then
        # Windows: parse from WMIC
        ppid=$(wmic process where "ProcessId=$CURRENT_PID" get ParentProcessId 2>/dev/null | grep -o "[0-9]*" | head -1 || echo "0")
    else
        # Unix: use ps
        ppid=$(ps -o ppid= -p "$CURRENT_PID" 2>/dev/null | tr -d ' ' || echo "0")
    fi

    # Create metadata
    local metadata
    metadata=$(cat <<EOF
{
  "session_id": "$session_id",
  "pid": $CURRENT_PID,
  "ppid": $ppid,
  "start_time": "$(get_timestamp)",
  "hostname": "$(get_hostname)",
  "working_dir": "$(pwd)",
  "last_heartbeat": "$(get_timestamp)",
  "platform": "$PLATFORM"
}
EOF
    )

    # Write metadata
    local metadata_file
    metadata_file=$(get_session_metadata_file "$session_id")
    write_json "$metadata" "$metadata_file"

    # Append to registry
    append_jsonl "$metadata" "$REGISTRY_FILE"

    log_success "Registered session: $session_id (PID: $CURRENT_PID)"

    # Start heartbeat
    start_heartbeat "$session_id"
}

# Unregister current session
# Usage: unregister_session
unregister_session() {
    local session_id="$CURRENT_SESSION_ID"

    if ! validate_session_id "$session_id"; then
        return 1
    fi

    # Stop heartbeat
    stop_heartbeat "$session_id" 2>/dev/null || true

    # Update metadata with end time
    local metadata_file
    metadata_file=$(get_session_metadata_file "$session_id")

    if [[ -f "$metadata_file" ]]; then
        local updated_metadata
        if has_jq; then
            updated_metadata=$(cat "$metadata_file" | jq --arg ts "$(get_timestamp)" '.end_time = $ts | .status = "completed"')
        else
            updated_metadata=$(cat "$metadata_file")
        fi
        write_json "$updated_metadata" "$metadata_file"
    fi

    log_success "Unregistered session: $session_id"
}
