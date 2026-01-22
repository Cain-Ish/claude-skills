#!/bin/bash
# ============================================================================
# Process Janitor Plugin - Cross-Platform Compatibility Layer
# ============================================================================
# Provides platform-specific implementations for commands that differ
# between macOS, Linux, and Windows (Git Bash).
#
# Source this file after common.sh:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/platform.sh"
# ============================================================================

# Detect platform
detect_platform() {
    case "$OSTYPE" in
        darwin*)
            echo "macos"
            ;;
        linux*)
            echo "linux"
            ;;
        msys*|cygwin*|mingw*)
            echo "windows"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

PLATFORM=$(detect_platform)

# ============================================================================
# File Age Detection
# ============================================================================

# Get file modification time as Unix timestamp
# Usage: get_file_mtime "/path/to/file"
get_file_mtime() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "0"
        return 1
    fi

    case "$PLATFORM" in
        macos)
            stat -f %m "$file" 2>/dev/null || echo "0"
            ;;
        linux|windows)
            stat -c %Y "$file" 2>/dev/null || echo "0"
            ;;
        *)
            # Fallback: use date -r if available
            if date -r "$file" +%s 2>/dev/null; then
                :
            else
                echo "0"
            fi
            ;;
    esac
}

# Get file age in days
# Usage: get_file_age_days "/path/to/file"
get_file_age_days() {
    local file="$1"
    local mtime
    local now

    mtime=$(get_file_mtime "$file")
    now=$(date +%s)

    if [[ "$mtime" == "0" ]]; then
        echo "0"
        return 1
    fi

    echo $(( (now - mtime) / 86400 ))
}

# Get file modification date in YYYY-MM-DD format
# Usage: get_file_mod_date "/path/to/file"
get_file_mod_date() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 1
    fi

    case "$PLATFORM" in
        macos)
            stat -f "%Sm" -t "%Y-%m-%d" "$file" 2>/dev/null
            ;;
        linux|windows)
            stat -c %y "$file" 2>/dev/null | cut -d' ' -f1
            ;;
        *)
            date -r "$file" +"%Y-%m-%d" 2>/dev/null || echo ""
            ;;
    esac
}

# ============================================================================
# File Operations
# ============================================================================

# Reverse file lines (cross-platform tac)
# Usage: reverse_file "/path/to/file"
reverse_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    if command -v tac &>/dev/null; then
        # GNU tac (Linux, Git Bash)
        tac "$file"
    elif tail -r /dev/null 2>/dev/null; then
        # BSD tail -r (macOS)
        tail -r "$file"
    else
        # Fallback: awk
        awk '{a[NR]=$0} END {for(i=NR;i>=1;i--) print a[i]}' "$file"
    fi
}

# In-place sed edit (cross-platform)
# Usage: sed_inplace "s/old/new/g" "/path/to/file"
sed_inplace() {
    local expression="$1"
    local file="$2"

    case "$PLATFORM" in
        macos)
            # BSD sed requires '' after -i
            sed -i '' "$expression" "$file"
            ;;
        linux|windows|*)
            # GNU sed
            sed -i "$expression" "$file"
            ;;
    esac
}

# Create temporary file
# Usage: temp_file=$(create_temp_file)
create_temp_file() {
    local prefix="${1:-janitor}"

    if command -v mktemp &>/dev/null; then
        mktemp -t "${prefix}.XXXXXX"
    else
        # Fallback
        local temp_dir="${TMPDIR:-/tmp}"
        local temp_file="$temp_dir/${prefix}.$$.$RANDOM"
        touch "$temp_file"
        echo "$temp_file"
    fi
}

# Create temporary directory
# Usage: temp_dir=$(create_temp_dir)
create_temp_dir() {
    local prefix="${1:-janitor}"

    if command -v mktemp &>/dev/null; then
        mktemp -d -t "${prefix}.XXXXXX"
    else
        local temp_dir="${TMPDIR:-/tmp}/${prefix}.$$.$RANDOM"
        mkdir -p "$temp_dir"
        echo "$temp_dir"
    fi
}

# ============================================================================
# Path Handling
# ============================================================================

# Normalize path separators (convert backslashes to forward slashes)
# Usage: normalize_path "C:\Users\name\file"
normalize_path() {
    local path="$1"
    echo "${path//\\//}"
}

# Get absolute path
# Usage: abs_path=$(get_absolute_path "relative/path")
get_absolute_path() {
    local path="$1"

    if [[ -d "$path" ]]; then
        (cd "$path" && pwd)
    elif [[ -f "$path" ]]; then
        local dir
        dir=$(dirname "$path")
        local base
        base=$(basename "$path")
        echo "$(cd "$dir" && pwd)/$base"
    else
        # Path doesn't exist, try to resolve anyway
        echo "$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")"
    fi
}

# ============================================================================
# Process Management
# ============================================================================

# Check if a process is running by PID
# Usage: is_process_running 12345
is_process_running() {
    local pid="$1"

    case "$PLATFORM" in
        windows)
            # Windows: use tasklist
            tasklist //FI "PID eq $pid" 2>/dev/null | grep -q "$pid"
            ;;
        *)
            # Unix: use kill -0
            kill -0 "$pid" 2>/dev/null
            ;;
    esac
}

# ============================================================================
# Command Availability Checks
# ============================================================================

# Check if required commands are available
check_dependencies() {
    local missing=()

    # Required commands
    for cmd in git bash; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    # Optional but recommended
    local recommended=()
    for cmd in jq bc; do
        if ! command -v "$cmd" &>/dev/null; then
            recommended+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        log_error "Please install them and try again"
        return 1
    fi

    if [[ ${#recommended[@]} -gt 0 ]]; then
        log_warn "Recommended commands not found: ${recommended[*]}"
        log_warn "Some features may have reduced functionality"
    fi

    return 0
}

# ============================================================================
# Sound/Notification (optional)
# ============================================================================

# Play notification sound (cross-platform)
# Usage: play_notification_sound
play_notification_sound() {
    case "$PLATFORM" in
        macos)
            afplay /System/Library/Sounds/Glass.aiff 2>/dev/null &
            ;;
        linux)
            if command -v paplay &>/dev/null; then
                paplay /usr/share/sounds/freedesktop/stereo/complete.oga 2>/dev/null &
            elif command -v aplay &>/dev/null; then
                aplay /usr/share/sounds/sound-icons/glass.wav 2>/dev/null &
            fi
            ;;
        windows)
            powershell -c "[console]::beep(800,200)" 2>/dev/null &
            ;;
    esac
}

# Show desktop notification (cross-platform)
# Usage: show_notification "Title" "Message"
show_notification() {
    local title="$1"
    local message="$2"

    # Escape special characters to prevent command injection
    local escaped_title escaped_message

    case "$PLATFORM" in
        macos)
            # Escape for AppleScript (escape quotes and backslashes)
            escaped_title="${title//\\/\\\\}"
            escaped_title="${escaped_title//\"/\\\"}"
            escaped_message="${message//\\/\\\\}"
            escaped_message="${escaped_message//\"/\\\"}"
            osascript -e "display notification \"$escaped_message\" with title \"$escaped_title\"" 2>/dev/null
            ;;
        linux)
            # notify-send handles arguments safely, no escaping needed
            if command -v notify-send &>/dev/null; then
                notify-send "$title" "$message" 2>/dev/null
            fi
            ;;
        windows)
            # Escape for PowerShell (use single quotes to prevent expansion)
            # Replace single quotes with two single quotes for PowerShell escaping
            escaped_title="${title//\'/\'\'}"
            escaped_message="${message//\'/\'\'}"
            powershell -c "
                [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
                \$template = [Windows.UI.Notifications.ToastTemplateType]::ToastText02
                \$xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(\$template)
                \$xml.GetElementsByTagName('text')[0].AppendChild(\$xml.CreateTextNode('$escaped_title')) | Out-Null
                \$xml.GetElementsByTagName('text')[1].AppendChild(\$xml.CreateTextNode('$escaped_message')) | Out-Null
                \$toast = [Windows.UI.Notifications.ToastNotification]::new(\$xml)
                [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Reflect').Show(\$toast)
            " 2>/dev/null
            ;;
    esac
}

# ============================================================================
# Clipboard Operations
# ============================================================================

# Copy text to clipboard
# Usage: copy_to_clipboard "text to copy"
copy_to_clipboard() {
    local text="$1"

    case "$PLATFORM" in
        macos)
            echo -n "$text" | pbcopy
            ;;
        linux)
            if command -v xclip &>/dev/null; then
                echo -n "$text" | xclip -selection clipboard
            elif command -v xsel &>/dev/null; then
                echo -n "$text" | xsel --clipboard --input
            fi
            ;;
        windows)
            echo -n "$text" | clip
            ;;
    esac
}

# ============================================================================
# Export platform info
# ============================================================================

export PLATFORM
