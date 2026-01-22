#!/bin/bash
# ============================================================================
# Process Janitor Plugin - Shared Library
# ============================================================================
# Common functions, configuration, and utilities used across all process-janitor scripts.
# Source this file at the beginning of each script:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# ============================================================================

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

# Base directories
JANITOR_HOME="${JANITOR_HOME:-$HOME/.claude}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Session tracking directories
SESSIONS_DIR="${JANITOR_SESSIONS_DIR:-$JANITOR_HOME/sessions}"
REGISTRY_FILE="${JANITOR_REGISTRY_FILE:-$SESSIONS_DIR/registry.jsonl}"

# Configuration files
CONFIG_FILE="${JANITOR_CONFIG_FILE:-$JANITOR_HOME/process-janitor-config.json}"
DEFAULT_CONFIG="${PLUGIN_ROOT}/config/default-config.json"

# Current session info (set by Claude Code)
CURRENT_SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
CURRENT_PID="$$"

# Default thresholds (can be overridden by config file)
MIN_SESSION_AGE_MINUTES="${JANITOR_MIN_AGE:-10}"
HEARTBEAT_INTERVAL_SECONDS="${JANITOR_HEARTBEAT_INTERVAL:-60}"
STALE_HEARTBEAT_THRESHOLD_MINUTES="${JANITOR_STALE_THRESHOLD:-5}"

# Display settings
COLOR_ENABLED="${JANITOR_COLOR:-true}"
VERBOSE="${JANITOR_VERBOSE:-false}"

# ============================================================================
# Color Definitions
# ============================================================================

if [[ "$COLOR_ENABLED" == "true" ]] && [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    PURPLE=''
    CYAN=''
    BOLD=''
    DIM=''
    NC=''
fi

# ============================================================================
# Logging Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${DIM}[DEBUG]${NC} $*" >&2
    fi
}

# ============================================================================
# Date/Time Utilities
# ============================================================================

# Get current timestamp in ISO 8601 format
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Get timestamp for N days ago
# Usage: get_days_ago_timestamp 7
get_days_ago_timestamp() {
    local days="${1:-0}"
    if date --version >/dev/null 2>&1; then
        # GNU date (Linux, Git Bash on Windows)
        date -d "$days days ago" -u +"%Y-%m-%dT%H:%M:%SZ"
    else
        # BSD date (macOS)
        date -v-${days}d -u +"%Y-%m-%dT%H:%M:%SZ"
    fi
}

# Get timestamp for N minutes ago
# Usage: get_minutes_ago_timestamp 5
get_minutes_ago_timestamp() {
    local minutes="${1:-0}"
    if date --version >/dev/null 2>&1; then
        # GNU date (Linux, Git Bash on Windows)
        date -d "$minutes minutes ago" -u +"%Y-%m-%dT%H:%M:%SZ"
    else
        # BSD date (macOS)
        date -v-${minutes}M -u +"%Y-%m-%dT%H:%M:%SZ"
    fi
}

# Parse ISO 8601 timestamp to Unix epoch
# Usage: parse_timestamp "2026-01-22T11:29:00Z"
parse_timestamp() {
    local timestamp="$1"

    if date --version >/dev/null 2>&1; then
        # GNU date
        date -d "$timestamp" +%s 2>/dev/null || echo "0"
    else
        # BSD date (macOS)
        date -j -f "%Y-%m-%dT%H:%M:%SZ" "$timestamp" +%s 2>/dev/null || echo "0"
    fi
}

# Get age in seconds between timestamp and now
# Usage: get_age_seconds "2026-01-22T11:29:00Z"
get_age_seconds() {
    local timestamp="$1"
    local epoch
    epoch=$(parse_timestamp "$timestamp")
    local now
    now=$(date +%s)

    echo $((now - epoch))
}

# ============================================================================
# JSON Utilities
# ============================================================================

# Check if jq is available
has_jq() {
    command -v jq &>/dev/null
}

# Extract a field from a JSON file
# Usage: extract_json_field "file.json" "fieldName"
extract_json_field() {
    local file="$1"
    local field="$2"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 1
    fi

    # Security: Validate file is within allowed directories
    if ! validate_file_path "$file" 2>/dev/null; then
        log_debug "File path validation failed for: $file"
        echo ""
        return 1
    fi

    if has_jq; then
        jq -r ".$field // empty" "$file" 2>/dev/null || echo ""
    elif command -v python3 &>/dev/null; then
        # Security: Pass file and field as arguments to prevent injection
        python3 -c "
import json
import sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    # Support nested fields like 'metadata.pid'
    result = data
    for key in sys.argv[2].split('.'):
        if isinstance(result, dict):
            result = result.get(key, '')
        else:
            result = ''
            break
    print(result if result is not None else '')
except Exception:
    print('')
" "$file" "$field" 2>/dev/null
    else
        # Fallback: simple grep (less reliable)
        grep -o "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null | \
            sed 's/.*:[[:space:]]*"//' | sed 's/"$//' | head -1
    fi
}

# Extract a number field from JSON
# Usage: extract_json_number "file.json" "pid"
extract_json_number() {
    local file="$1"
    local field="$2"

    if has_jq; then
        jq -r ".$field // 0" "$file" 2>/dev/null || echo "0"
    else
        grep -o "\"$field\"[[:space:]]*:[[:space:]]*[0-9.]*" "$file" 2>/dev/null | \
            grep -o "[0-9.]*$" | head -1 || echo "0"
    fi
}

# Write JSON to file safely
# Usage: write_json '{"key":"value"}' "output.json"
write_json() {
    local json="$1"
    local file="$2"
    local dir
    dir=$(dirname "$file")

    mkdir -p "$dir"

    # Write to temp file first, then atomic move
    local temp_file
    temp_file=$(mktemp)

    # Security: Set restrictive permissions immediately
    chmod 600 "$temp_file"

    if has_jq; then
        printf '%s\n' "$json" | jq '.' > "$temp_file" 2>/dev/null || printf '%s\n' "$json" > "$temp_file"
    else
        printf '%s\n' "$json" > "$temp_file"
    fi

    mv "$temp_file" "$file"
    # Ensure final file has proper permissions
    chmod 600 "$file"
}

# ============================================================================
# File Locking
# ============================================================================

# Execute a command with exclusive file lock
# Usage: with_lock "/path/to/lockfile" command arg1 arg2
with_lock() {
    local lockfile="$1"
    shift

    # Create lock directory if needed
    mkdir -p "$(dirname "$lockfile")"

    if command -v flock &>/dev/null; then
        # Linux/Git Bash: use flock with timeout
        (
            flock -x -w 10 200 || {
                log_error "Failed to acquire lock on $lockfile"
                return 1
            }
            "$@"
        ) 200>"$lockfile"
    else
        # macOS/fallback: use mkdir-based locking with stale lock detection
        local lock_dir="${lockfile}.dir"
        local pid_file="${lock_dir}/pid"
        local max_attempts=10
        local attempt=0
        local stale_threshold=60  # seconds

        while ! mkdir "$lock_dir" 2>/dev/null; do
            attempt=$((attempt + 1))

            # Check for stale lock
            if [[ -d "$lock_dir" ]]; then
                local lock_age=0
                if [[ -f "$pid_file" ]]; then
                    # Check if lock is old
                    if stat -f %m "$lock_dir" &>/dev/null; then
                        # macOS stat
                        lock_age=$(( $(date +%s) - $(stat -f %m "$lock_dir") ))
                    elif stat -c %Y "$lock_dir" &>/dev/null; then
                        # GNU stat
                        lock_age=$(( $(date +%s) - $(stat -c %Y "$lock_dir") ))
                    fi

                    if [[ $lock_age -gt $stale_threshold ]]; then
                        local lock_pid
                        lock_pid=$(cat "$pid_file" 2>/dev/null || echo "")
                        # Check if process still exists
                        if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                            log_warn "Removing stale lock (PID $lock_pid no longer exists)"
                            rm -rf "$lock_dir"
                            continue
                        elif [[ -z "$lock_pid" ]]; then
                            log_warn "Removing stale lock (no PID, age ${lock_age}s)"
                            rm -rf "$lock_dir"
                            continue
                        fi
                    fi
                fi
            fi

            if [[ $attempt -ge $max_attempts ]]; then
                log_error "Failed to acquire lock on $lockfile after $max_attempts attempts"
                return 1
            fi
            sleep 1
        done

        # Record PID for stale lock detection
        echo $$ > "$pid_file"

        # Use subshell to contain trap
        (
            trap 'rm -rf "$lock_dir" 2>/dev/null || true' EXIT INT TERM
            "$@"
        )
        local result=$?

        rm -rf "$lock_dir" 2>/dev/null || true

        return $result
    fi
}

# Internal helper for append_jsonl - DO NOT CALL DIRECTLY
_append_json_to_file() {
    printf '%s\n' "$1" >> "$2"
}

# Append to JSONL file with locking
# Usage: append_jsonl '{"event":"data"}' "/path/to/file.jsonl"
append_jsonl() {
    local json="$1"
    local file="$2"
    local dir
    dir=$(dirname "$file")

    mkdir -p "$dir"

    # Security: Use function call instead of bash -c to prevent injection
    with_lock "${file}.lock" _append_json_to_file "$json" "$file"
}

# ============================================================================
# Validation Functions
# ============================================================================

# Validate file path is within allowed directories
# Usage: validate_file_path "/path/to/file" || exit 1
validate_file_path() {
    local path="$1"

    # Must not be empty
    if [[ -z "$path" ]]; then
        log_error "File path cannot be empty"
        return 1
    fi

    # Check for command injection characters
    if [[ "$path" =~ [\;\|\&\$\`\<\>] ]]; then
        log_error "Invalid file path: contains dangerous characters"
        return 1
    fi

    # Check for null bytes
    if [[ "$path" == *$'\0'* ]]; then
        log_error "Invalid file path: contains null byte"
        return 1
    fi

    # Check if symlink (security risk)
    if [[ -L "$path" ]]; then
        log_debug "Warning: path is a symlink: $path"
        # Allow symlinks but log them
    fi

    return 0
}

# Validate session ID format
# Usage: validate_session_id "abc123-def456" || exit 1
validate_session_id() {
    local session_id="$1"

    # Check for empty
    if [[ -z "$session_id" ]]; then
        log_error "Session ID cannot be empty"
        return 1
    fi

    # Check length
    if [[ ${#session_id} -gt 64 ]]; then
        log_error "Session ID too long (max 64 characters)"
        return 1
    fi

    # Session IDs should be alphanumeric with dashes (UUID-like)
    if ! [[ "$session_id" =~ ^[a-zA-Z0-9-]+$ ]]; then
        log_error "Invalid session ID format"
        return 1
    fi

    return 0
}

# Validate PID
# Usage: validate_pid "12345" || exit 1
validate_pid() {
    local pid="$1"

    # Check for empty
    if [[ -z "$pid" ]]; then
        log_error "PID cannot be empty"
        return 1
    fi

    # PID must be a positive integer
    if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
        log_error "Invalid PID format (must be a positive integer)"
        return 1
    fi

    # PID must be > 0
    if [[ "$pid" -eq 0 ]]; then
        log_error "Invalid PID (cannot be 0)"
        return 1
    fi

    return 0
}

# ============================================================================
# Directory Management
# ============================================================================

# Ensure required directories exist
ensure_directories() {
    mkdir -p "$SESSIONS_DIR"
    mkdir -p "$(dirname "$REGISTRY_FILE")"
    mkdir -p "$(dirname "$CONFIG_FILE")"
}

# ============================================================================
# Configuration Loading
# ============================================================================

# Load configuration from file or use defaults
load_config() {
    ensure_directories

    # If user config doesn't exist, use defaults
    if [[ ! -f "$CONFIG_FILE" ]] && [[ -f "$DEFAULT_CONFIG" ]]; then
        cp "$DEFAULT_CONFIG" "$CONFIG_FILE"
    fi

    # Load settings from config file if it exists
    if [[ -f "$CONFIG_FILE" ]]; then
        local auto_cleanup
        auto_cleanup=$(extract_json_field "$CONFIG_FILE" "auto_cleanup_on_start" 2>/dev/null || echo "false")
        export JANITOR_AUTO_CLEANUP="${auto_cleanup:-false}"

        local min_age
        min_age=$(extract_json_number "$CONFIG_FILE" "min_session_age_minutes" 2>/dev/null || echo "$MIN_SESSION_AGE_MINUTES")
        export MIN_SESSION_AGE_MINUTES="${min_age:-$MIN_SESSION_AGE_MINUTES}"

        local heartbeat
        heartbeat=$(extract_json_number "$CONFIG_FILE" "heartbeat_interval_seconds" 2>/dev/null || echo "$HEARTBEAT_INTERVAL_SECONDS")
        export HEARTBEAT_INTERVAL_SECONDS="${heartbeat:-$HEARTBEAT_INTERVAL_SECONDS}"

        local stale
        stale=$(extract_json_number "$CONFIG_FILE" "stale_heartbeat_threshold_minutes" 2>/dev/null || echo "$STALE_HEARTBEAT_THRESHOLD_MINUTES")
        export STALE_HEARTBEAT_THRESHOLD_MINUTES="${stale:-$STALE_HEARTBEAT_THRESHOLD_MINUTES}"
    fi
}

# ============================================================================
# Initialization
# ============================================================================

# Initialize plugin (call this at the start of scripts)
init_janitor() {
    ensure_directories
    load_config
}
