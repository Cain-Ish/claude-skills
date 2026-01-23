#!/bin/bash
# ============================================================================
# Self-Debugger Plugin - Shared Library
# ============================================================================
# Common functions, configuration, and utilities used across all self-debugger scripts.
# Source this file at the beginning of each script:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#
# REF:common-lib-base: Adapted from process-janitor with self-debugger extensions
# ============================================================================

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

# Base directories
DEBUGGER_HOME="${DEBUGGER_HOME:-$HOME/.claude/self-debugger}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# State directories
FINDINGS_DIR="${DEBUGGER_FINDINGS_DIR:-$DEBUGGER_HOME/findings}"
SESSIONS_DIR="${DEBUGGER_SESSIONS_DIR:-$DEBUGGER_HOME/sessions}"
LOCKS_DIR="${DEBUGGER_LOCKS_DIR:-$DEBUGGER_HOME/locks}"
METRICS_FILE="${DEBUGGER_METRICS_FILE:-$DEBUGGER_HOME/metrics.jsonl}"

# Findings files
ISSUES_FILE="${FINDINGS_DIR}/issues.jsonl"
FIXES_FILE="${FINDINGS_DIR}/fixes.jsonl}"

# Configuration files
CONFIG_FILE="${DEBUGGER_CONFIG_FILE:-$DEBUGGER_HOME/config.json}"
DEFAULT_CONFIG="${PLUGIN_ROOT}/config/default-config.json"

# Rules directories
RULES_CORE_DIR="${PLUGIN_ROOT}/rules/core"
RULES_LEARNED_DIR="${PLUGIN_ROOT}/rules/learned"
RULES_EXTERNAL_DIR="${PLUGIN_ROOT}/rules/external"

# Current session info (set by Claude Code)
CURRENT_SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
CURRENT_PID="$$"

# Default thresholds (can be overridden by config file)
SCAN_INTERVAL_SECONDS="${DEBUGGER_SCAN_INTERVAL:-300}"  # 5 minutes
MIN_CRITIC_SCORE="${DEBUGGER_MIN_CRITIC_SCORE:-70}"
MAX_FIXES_PER_SESSION="${DEBUGGER_MAX_FIXES:-10}"
STALE_LOCK_THRESHOLD_MINUTES="${DEBUGGER_STALE_LOCK_THRESHOLD:-30}"

# Display settings
COLOR_ENABLED="${DEBUGGER_COLOR:-true}"
VERBOSE="${DEBUGGER_VERBOSE:-false}"

# ============================================================================
# Color Definitions (REF:common-lib-base: Reused from process-janitor)
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
# Logging Functions (REF:common-lib-base: Reused from process-janitor)
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
# Date/Time Utilities (REF:common-lib-base: Reused from process-janitor)
# ============================================================================

# Get current timestamp in ISO 8601 format
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Get timestamp for N minutes ago
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
get_age_seconds() {
    local timestamp="$1"
    local epoch
    epoch=$(parse_timestamp "$timestamp")
    local now
    now=$(date +%s)

    echo $((now - epoch))
}

# ============================================================================
# JSON Utilities (REF:common-lib-base: Reused from process-janitor)
# ============================================================================

# Check if jq is available
has_jq() {
    command -v jq &>/dev/null
}

# Extract a field from a JSON file
extract_json_field() {
    local file="$1"
    local field="$2"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 1
    fi

    if has_jq; then
        jq -r ".$field // empty" "$file" 2>/dev/null || echo ""
    elif command -v python3 &>/dev/null; then
        python3 -c "
import json
import sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
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
write_json() {
    local json="$1"
    local file="$2"
    local dir
    dir=$(dirname "$file")

    mkdir -p "$dir"

    local temp_file
    temp_file=$(mktemp)
    chmod 600 "$temp_file"

    if has_jq; then
        printf '%s\n' "$json" | jq '.' > "$temp_file" 2>/dev/null || printf '%s\n' "$json" > "$temp_file"
    else
        printf '%s\n' "$json" > "$temp_file"
    fi

    mv "$temp_file" "$file"
    chmod 600 "$file"
}

# ============================================================================
# File Locking (REF:common-lib-base: Reused from process-janitor)
# ============================================================================

# Execute a command with exclusive file lock
with_lock() {
    local lockfile="$1"
    shift

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
        local stale_threshold=60

        while ! mkdir "$lock_dir" 2>/dev/null; do
            attempt=$((attempt + 1))

            # Check for stale lock
            if [[ -d "$lock_dir" ]]; then
                local lock_age=0
                if [[ -f "$pid_file" ]]; then
                    if stat -f %m "$lock_dir" &>/dev/null; then
                        lock_age=$(( $(date +%s) - $(stat -f %m "$lock_dir") ))
                    elif stat -c %Y "$lock_dir" &>/dev/null; then
                        lock_age=$(( $(date +%s) - $(stat -c %Y "$lock_dir") ))
                    fi

                    if [[ $lock_age -gt $stale_threshold ]]; then
                        local lock_pid
                        lock_pid=$(cat "$pid_file" 2>/dev/null || echo "")
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

        echo $$ > "$pid_file"

        (
            trap 'rm -rf "$lock_dir" 2>/dev/null || true' EXIT INT TERM
            "$@"
        )
        local result=$?

        rm -rf "$lock_dir" 2>/dev/null || true

        return $result
    fi
}

# Internal helper for append_jsonl
_append_json_to_file() {
    printf '%s\n' "$1" >> "$2"
}

# Append to JSONL file with locking
append_jsonl() {
    local json="$1"
    local file="$2"
    local dir
    dir=$(dirname "$file")

    mkdir -p "$dir"

    with_lock "${file}.lock" _append_json_to_file "$json" "$file"
}

# ============================================================================
# Validation Functions (REF:common-lib-base: Reused from process-janitor)
# ============================================================================

# Validate session ID format
validate_session_id() {
    local session_id="$1"

    if [[ -z "$session_id" ]]; then
        log_error "Session ID cannot be empty"
        return 1
    fi

    if [[ ${#session_id} -gt 64 ]]; then
        log_error "Session ID too long (max 64 characters)"
        return 1
    fi

    if ! [[ "$session_id" =~ ^[a-zA-Z0-9-]+$ ]]; then
        log_error "Invalid session ID format"
        return 1
    fi

    return 0
}

# Validate PID
validate_pid() {
    local pid="$1"

    if [[ -z "$pid" ]]; then
        log_error "PID cannot be empty"
        return 1
    fi

    if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
        log_error "Invalid PID format (must be a positive integer)"
        return 1
    fi

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
    mkdir -p "$DEBUGGER_HOME"
    mkdir -p "$FINDINGS_DIR"
    mkdir -p "$SESSIONS_DIR"
    mkdir -p "$LOCKS_DIR"
    mkdir -p "$(dirname "$METRICS_FILE")"
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
        local scan_interval
        scan_interval=$(extract_json_number "$CONFIG_FILE" "scan_interval_seconds" 2>/dev/null || echo "$SCAN_INTERVAL_SECONDS")
        export SCAN_INTERVAL_SECONDS="${scan_interval:-$SCAN_INTERVAL_SECONDS}"

        local min_score
        min_score=$(extract_json_number "$CONFIG_FILE" "min_critic_score" 2>/dev/null || echo "$MIN_CRITIC_SCORE")
        export MIN_CRITIC_SCORE="${min_score:-$MIN_CRITIC_SCORE}"

        local max_fixes
        max_fixes=$(extract_json_number "$CONFIG_FILE" "max_fixes_per_session" 2>/dev/null || echo "$MAX_FIXES_PER_SESSION")
        export MAX_FIXES_PER_SESSION="${max_fixes:-$MAX_FIXES_PER_SESSION}"

        local stale_lock
        stale_lock=$(extract_json_number "$CONFIG_FILE" "stale_lock_threshold_minutes" 2>/dev/null || echo "$STALE_LOCK_THRESHOLD_MINUTES")
        export STALE_LOCK_THRESHOLD_MINUTES="${stale_lock:-$STALE_LOCK_THRESHOLD_MINUTES}"
    fi
}

# ============================================================================
# UUID Generation
# ============================================================================

# Generate a UUID for issue IDs
generate_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif command -v python3 &>/dev/null; then
        python3 -c "import uuid; print(str(uuid.uuid4()))"
    else
        # Fallback: use random hex
        openssl rand -hex 16 | sed 's/\(........\)\(....\)\(....\)\(....\)\(............\)/\1-\2-\3-\4-\5/'
    fi
}

# ============================================================================
# Initialization
# ============================================================================

# Initialize plugin (call this at the start of scripts)
init_debugger() {
    ensure_directories
    load_config
}
