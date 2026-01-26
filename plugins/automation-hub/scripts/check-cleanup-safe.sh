#!/usr/bin/env bash
# Check if cleanup is safe to run based on safety blockers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Safety Checks ===

debug "Checking cleanup safety..."

# Check 1: Uncommitted changes
check_uncommitted=$(get_config_value ".auto_cleanup.safety_blockers.uncommitted_changes" "true")

if [[ "${check_uncommitted}" == "true" ]]; then
    if [[ -d .git ]]; then
        if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
            debug "  ✗ UNSAFE: Uncommitted changes detected"
            echo "unsafe:uncommitted_changes"
            exit 0
        fi

        if [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
            debug "  ✗ UNSAFE: Untracked files detected"
            echo "unsafe:untracked_files"
            exit 0
        fi
    fi
fi

debug "  ✓ Git status clean"

# Check 2: Running dev processes
check_dev_processes=$(get_config_value ".auto_cleanup.safety_blockers.running_dev_processes" "true")

if [[ "${check_dev_processes}" == "true" ]]; then
    dev_process_patterns=(
        "vite"
        "webpack"
        "jest.*--watch"
        "npm.*run.*dev"
        "npm.*run.*start"
        "yarn.*dev"
        "yarn.*start"
        "pnpm.*dev"
        "pnpm.*start"
        "node.*--watch"
        "nodemon"
        "tsx.*watch"
        "mcp"
    )

    for pattern in "${dev_process_patterns[@]}"; do
        if pgrep -f "${pattern}" >/dev/null 2>&1; then
            debug "  ✗ UNSAFE: Running dev process detected (${pattern})"
            echo "unsafe:dev_process:${pattern}"
            exit 0
        fi
    done
fi

debug "  ✓ No dev processes running"

# Check 3: Recent activity
check_recent_activity=$(get_config_value ".auto_cleanup.safety_blockers.recent_activity_minutes" "2")

if [[ ${check_recent_activity} -gt 0 ]]; then
    session_state_path=$(get_session_state_path)

    if [[ -f "${session_state_path}" ]]; then
        last_activity=$(jq -r '.last_tool_call // empty' "${session_state_path}")

        if [[ -n "${last_activity}" ]]; then
            now=$(date +%s)
            last_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${last_activity}" +%s 2>/dev/null || echo 0)
            elapsed_minutes=$(( (now - last_epoch) / 60 ))

            if [[ ${elapsed_minutes} -lt ${check_recent_activity} ]]; then
                debug "  ✗ UNSAFE: Recent activity detected (${elapsed_minutes} minutes ago)"
                echo "unsafe:recent_activity:${elapsed_minutes}m"
                exit 0
            fi
        fi
    fi
fi

debug "  ✓ No recent activity"

# Check 4: Session cleanup limit
max_cleanups=$(get_config_value ".auto_cleanup.max_cleanups_per_session" "1")
current_count=$(get_session_state_value ".actions.auto_cleanup_count" "0")

if [[ ${current_count} -ge ${max_cleanups} ]]; then
    debug "  ✗ UNSAFE: Max cleanups per session exceeded (${current_count}/${max_cleanups})"
    echo "unsafe:session_limit:${current_count}/${max_cleanups}"
    exit 0
fi

debug "  ✓ Session limit not exceeded"

# All checks passed
debug "  → SAFE to cleanup"
echo "safe"
exit 0
