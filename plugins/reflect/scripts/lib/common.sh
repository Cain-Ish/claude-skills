#!/bin/bash
# ============================================================================
# Reflect Plugin - Shared Library
# ============================================================================
# Common functions, configuration, and utilities used across all reflect scripts.
# Source this file at the beginning of each script:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# ============================================================================

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

# Base directories
REFLECT_HOME="${REFLECT_HOME:-$HOME/.claude}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# File paths
METRICS_FILE="${REFLECT_METRICS_FILE:-$REFLECT_HOME/reflect-metrics.jsonl}"
STATE_FILE="${REFLECT_STATE_FILE:-$REFLECT_HOME/reflect-skill-state.json}"
CONFIG_FILE="${REFLECT_CONFIG_FILE:-$REFLECT_HOME/reflect-config.json}"
MEMORIES_DIR="${REFLECT_MEMORIES_DIR:-$REFLECT_HOME/memories}"
PAUSED_DIR="${REFLECT_PAUSED_DIR:-$REFLECT_HOME/reflect-paused-skills}"
FEEDBACK_DIR="${REFLECT_FEEDBACK_DIR:-$REFLECT_HOME/reflect-external-feedback}"
ARCHIVE_DIR="${REFLECT_ARCHIVE_DIR:-$REFLECT_HOME/memories-archive}"

# Default thresholds (can be overridden by config file)
CONSECUTIVE_REJECTION_THRESHOLD="${REFLECT_REJECTION_THRESHOLD:-3}"
OUTCOME_TRACKING_DAYS="${REFLECT_OUTCOME_DAYS:-7}"
MEMORY_RETENTION_DAYS="${REFLECT_MEMORY_RETENTION:-90}"
METRICS_RETENTION_DAYS="${REFLECT_METRICS_RETENTION:-180}"
FEEDBACK_RETENTION_DAYS="${REFLECT_FEEDBACK_RETENTION:-30}"

# Display settings
COLOR_ENABLED="${REFLECT_COLOR:-true}"
VERBOSE="${REFLECT_VERBOSE:-false}"

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

# Get date for N days ago (YYYY-MM-DD format)
get_days_ago_date() {
    local days="${1:-0}"
    if date --version >/dev/null 2>&1; then
        date -d "$days days ago" +"%Y-%m-%d"
    else
        date -v-${days}d +"%Y-%m-%d"
    fi
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
    # Support nested fields like 'thresholds.consecutiveRejections'
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

# Extract a boolean field from JSON
# Usage: extract_json_bool "file.json" "enabled"
extract_json_bool() {
    local file="$1"
    local field="$2"
    local value

    if has_jq; then
        value=$(jq -r ".$field // false" "$file" 2>/dev/null)
    else
        value=$(grep -o "\"$field\"[[:space:]]*:[[:space:]]*[a-z]*" "$file" 2>/dev/null | \
                grep -o "true\|false" | head -1)
    fi

    [[ "$value" == "true" ]] && echo "true" || echo "false"
}

# Extract a number field from JSON
# Usage: extract_json_number "file.json" "count"
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

    # Resolve to real path and check if within REFLECT_HOME
    local real_path
    if [[ -e "$path" ]]; then
        real_path=$(cd "$(dirname "$path")" && pwd)/$(basename "$path")
    else
        real_path="$path"
    fi

    # Check if symlink (security risk)
    if [[ -L "$path" ]]; then
        log_debug "Warning: path is a symlink: $path"
        # Allow symlinks but log them
    fi

    return 0
}

# Validate skill name (prevent path traversal and special characters)
# Usage: validate_skill_name "skill-name" || exit 1
validate_skill_name() {
    local skill="$1"

    # Check for empty
    if [[ -z "$skill" ]]; then
        log_error "Skill name cannot be empty"
        return 1
    fi

    # Check length (prevent buffer issues and DoS)
    if [[ ${#skill} -gt 100 ]]; then
        log_error "Skill name too long (max 100 characters)"
        return 1
    fi

    # Check for path traversal
    if [[ "$skill" == *".."* ]]; then
        log_error "Invalid skill name: contains '..'"
        return 1
    fi

    # Check for slashes
    if [[ "$skill" == *"/"* ]] || [[ "$skill" == *"\\"* ]]; then
        log_error "Invalid skill name: contains path separator"
        return 1
    fi

    # Check for Windows special characters (colon, asterisk, etc.)
    if [[ "$skill" == *":"* ]] || [[ "$skill" == *"*"* ]] || [[ "$skill" == *"?"* ]] || \
       [[ "$skill" == *"<"* ]] || [[ "$skill" == *">"* ]] || [[ "$skill" == *"|"* ]] || \
       [[ "$skill" == *'"'* ]]; then
        log_error "Invalid skill name: contains special characters"
        return 1
    fi

    # Check for null bytes
    if [[ "$skill" == *$'\0'* ]]; then
        log_error "Invalid skill name: contains null byte"
        return 1
    fi

    # Allow only alphanumeric, dash, underscore
    if ! [[ "$skill" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Skill name must contain only letters, numbers, dashes, and underscores"
        return 1
    fi

    # Prevent Windows reserved names
    local upper_skill="${skill^^}"
    case "$upper_skill" in
        CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])
            log_error "Invalid skill name: reserved system name"
            return 1
            ;;
    esac

    return 0
}

# Validate session ID format
# Usage: validate_session_id "abc123" || exit 1
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

# Validate text input length
# Usage: validate_text_length "$text" "field name" 1000 || exit 1
validate_text_length() {
    local text="$1"
    local name="${2:-text}"
    local max_length="${3:-1000}"

    if [[ ${#text} -gt $max_length ]]; then
        log_error "$name too long (max $max_length characters)"
        return 1
    fi

    return 0
}

# Validate user action
# Usage: validate_action "approved" || exit 1
validate_action() {
    local action="$1"

    case "$action" in
        approved|rejected|modified|deferred)
            return 0
            ;;
        *)
            log_error "Invalid action: $action (must be approved|rejected|modified|deferred)"
            return 1
            ;;
    esac
}

# Validate boolean value
# Usage: validate_bool "true" || exit 1
validate_bool() {
    local value="$1"

    case "$value" in
        true|false)
            return 0
            ;;
        *)
            log_error "Invalid boolean: $value (must be true|false)"
            return 1
            ;;
    esac
}

# ============================================================================
# Configuration Loading
# ============================================================================

# Load configuration from config file
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        if has_jq; then
            # Load thresholds
            local val
            val=$(jq -r '.thresholds.consecutiveRejections // empty' "$CONFIG_FILE" 2>/dev/null)
            [[ -n "$val" ]] && CONSECUTIVE_REJECTION_THRESHOLD="$val"

            val=$(jq -r '.thresholds.outcomeTrackingDays // empty' "$CONFIG_FILE" 2>/dev/null)
            [[ -n "$val" ]] && OUTCOME_TRACKING_DAYS="$val"

            val=$(jq -r '.thresholds.memoryRetentionDays // empty' "$CONFIG_FILE" 2>/dev/null)
            [[ -n "$val" ]] && MEMORY_RETENTION_DAYS="$val"

            val=$(jq -r '.thresholds.metricsRetentionDays // empty' "$CONFIG_FILE" 2>/dev/null)
            [[ -n "$val" ]] && METRICS_RETENTION_DAYS="$val"

            # Load display settings
            val=$(jq -r '.display.colorEnabled // empty' "$CONFIG_FILE" 2>/dev/null)
            [[ -n "$val" ]] && COLOR_ENABLED="$val"

            val=$(jq -r '.display.verboseMode // empty' "$CONFIG_FILE" 2>/dev/null)
            [[ -n "$val" ]] && VERBOSE="$val"

            log_debug "Loaded configuration from $CONFIG_FILE"
        else
            log_debug "jq not available, using default configuration"
        fi
    fi
}

# ============================================================================
# Directory Initialization
# ============================================================================

# Ensure all required directories exist
init_directories() {
    mkdir -p "$REFLECT_HOME"
    mkdir -p "$MEMORIES_DIR"
    mkdir -p "$PAUSED_DIR"
    mkdir -p "$FEEDBACK_DIR"
}

# ============================================================================
# Metrics Helpers
# ============================================================================

# Count lines matching pattern in JSONL file
# Usage: count_jsonl_matches "reflect-metrics.jsonl" '"skill":"frontend"'
count_jsonl_matches() {
    local file="$1"
    local pattern="$2"

    if [[ ! -f "$file" ]]; then
        echo "0"
        return
    fi

    grep -c "$pattern" "$file" 2>/dev/null || echo "0"
}

# Get last N lines from JSONL file matching pattern
# Usage: get_recent_events "reflect-metrics.jsonl" '"type":"proposal"' 10
get_recent_events() {
    local file="$1"
    local pattern="$2"
    local count="${3:-10}"

    if [[ ! -f "$file" ]]; then
        return
    fi

    # Use tac if available, otherwise tail -r (macOS), otherwise use awk
    if command -v tac &>/dev/null; then
        tac "$file" | grep "$pattern" | head -n "$count"
    elif tail -r /dev/null 2>/dev/null; then
        tail -r "$file" | grep "$pattern" | head -n "$count"
    else
        # Fallback: use awk to reverse
        awk '{a[NR]=$0} END {for(i=NR;i>=1;i--) print a[i]}' "$file" | grep "$pattern" | head -n "$count"
    fi
}

# Generate unique session ID with improved entropy
generate_session_id() {
    if command -v uuidgen &>/dev/null; then
        uuidgen | cut -d'-' -f1 | tr '[:upper:]' '[:lower:]'
    elif [[ -r /dev/urandom ]]; then
        # Use more entropy from urandom (16 hex chars = 64 bits)
        head -c 8 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n'
    else
        # Fallback: combine multiple sources for entropy
        local timestamp pid random_val hostname_hash
        timestamp=$(date +%s%N 2>/dev/null || date +%s)
        pid=$$
        random_val=$RANDOM
        hostname_hash=$(hostname 2>/dev/null | head -c 8 || echo "local")
        printf '%s%s%s%s' "$timestamp" "$pid" "$random_val" "$hostname_hash" | \
            sha256sum 2>/dev/null | head -c 16 || \
            printf '%s%s' "$timestamp" "$pid" | head -c 16
    fi
}

# Escape a string for safe JSON inclusion
# Usage: json_escape "string with \"quotes\" and newlines"
json_escape() {
    local str="$1"

    # If jq is available, use it for proper escaping
    if has_jq; then
        printf '%s' "$str" | jq -Rs '.' | sed 's/^"//;s/"$//'
        return
    fi

    # Manual escaping (order matters!)
    # 1. Escape backslashes first
    str="${str//\\/\\\\}"
    # 2. Escape double quotes
    str="${str//\"/\\\"}"
    # 3. Escape control characters
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    # 4. Escape other problematic characters
    str="${str//$'\b'/\\b}"
    str="${str//$'\f'/\\f}"

    printf '%s' "$str"
}

# Create a JSON string value (with quotes)
# Usage: json_string "my value" -> "my value"
json_string() {
    local str="$1"

    if [[ -z "$str" ]]; then
        echo "null"
        return
    fi

    # If jq is available, use it
    if has_jq; then
        printf '%s' "$str" | jq -Rs '.'
        return
    fi

    # Manual: escape and wrap in quotes
    printf '"%s"' "$(json_escape "$str")"
}

# ============================================================================
# Arithmetic Helpers (avoid bc dependency)
# ============================================================================

# Calculate percentage using bash arithmetic
# Usage: calc_percentage numerator denominator
calc_percentage() {
    local num="$1"
    local denom="$2"

    if [[ "$denom" -eq 0 ]]; then
        echo "0"
        return
    fi

    # Use bc if available for precision, otherwise bash arithmetic
    if command -v bc &>/dev/null; then
        echo "scale=1; $num * 100 / $denom" | bc
    else
        echo $(( (num * 100) / denom ))
    fi
}

# ============================================================================
# Initialization
# ============================================================================

# Load config on source
load_config

# Initialize directories
init_directories
