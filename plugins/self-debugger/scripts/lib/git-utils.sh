#!/bin/bash
# ============================================================================
# Self-Debugger Plugin - Git Utilities
# ============================================================================
# Git operations for fix generation, branch management, and commits.
# Source this file after common.sh:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/git-utils.sh"
# ============================================================================

set -euo pipefail

# ============================================================================
# Repository Detection
# ============================================================================

# Detect source repository by searching for .git and plugins/ marker
# Usage: detect_source_repo [start_dir]
# Returns: 0 if in source repo, 1 if not
# Sets: SOURCE_REPO_ROOT environment variable
detect_source_repo() {
    local start_dir="${1:-$(pwd)}"
    local current_dir="$start_dir"

    # Search upward for .git directory
    while [[ "$current_dir" != "/" ]]; do
        if [[ -d "$current_dir/.git" ]]; then
            # Found .git - now check for plugins/ marker
            if [[ -d "$current_dir/plugins" ]]; then
                export SOURCE_REPO_ROOT="$current_dir"
                log_debug "Source repo detected: $SOURCE_REPO_ROOT"
                return 0
            else
                log_debug "Found .git but no plugins/ directory at: $current_dir"
                return 1
            fi
        fi

        # Go up one level
        current_dir=$(dirname "$current_dir")
    done

    log_debug "No source repository found (no .git directory)"
    return 1
}

# ============================================================================
# Branch Locking (5-layer safety pattern from process-janitor)
# ============================================================================

# Acquire exclusive lock on a branch
# Usage: acquire_branch_lock "debug/reflect/hook-frontmatter"
# Returns: 0 if lock acquired, 1 if failed
acquire_branch_lock() {
    local branch_name="$1"
    local lock_dir="$LOCKS_DIR/${branch_name//\//_}"  # Replace slashes with underscores
    local lock_pid_file="$lock_dir/pid"
    local lock_session_file="$lock_dir/session"
    local lock_timestamp_file="$lock_dir/timestamp"

    mkdir -p "$LOCKS_DIR"

    # Layer 1: Try to create lock directory (atomic operation)
    if mkdir "$lock_dir" 2>/dev/null; then
        # Lock acquired - write metadata
        echo "$CURRENT_PID" > "$lock_pid_file"
        echo "$CURRENT_SESSION_ID" > "$lock_session_file"
        echo "$(get_timestamp)" > "$lock_timestamp_file"

        log_info "Acquired branch lock: $branch_name"
        return 0
    fi

    # Lock exists - check if stale
    if [[ ! -d "$lock_dir" ]]; then
        log_warn "Lock directory disappeared, retrying..."
        return 1
    fi

    # Layer 2: Check lock age
    local lock_age_minutes=0
    if [[ -f "$lock_timestamp_file" ]]; then
        local lock_timestamp
        lock_timestamp=$(cat "$lock_timestamp_file" 2>/dev/null || echo "")
        if [[ -n "$lock_timestamp" ]]; then
            local lock_age_seconds
            lock_age_seconds=$(get_age_seconds "$lock_timestamp")
            lock_age_minutes=$((lock_age_seconds / 60))
        fi
    fi

    # Layer 3: Check if lock is stale (> threshold minutes)
    if [[ $lock_age_minutes -gt $STALE_LOCK_THRESHOLD_MINUTES ]]; then
        # Layer 4: Check if process still exists
        if [[ -f "$lock_pid_file" ]]; then
            local lock_pid
            lock_pid=$(cat "$lock_pid_file" 2>/dev/null || echo "")

            if [[ -n "$lock_pid" ]] && validate_pid "$lock_pid" 2>/dev/null; then
                # Layer 5: Verify process is actually running
                if ! kill -0 "$lock_pid" 2>/dev/null; then
                    log_warn "Removing stale lock (PID $lock_pid not running, age ${lock_age_minutes}m)"
                    rm -rf "$lock_dir"
                    return 1  # Retry acquisition
                else
                    log_error "Lock held by running process (PID $lock_pid, age ${lock_age_minutes}m)"
                    return 1
                fi
            else
                log_warn "Removing stale lock (invalid PID, age ${lock_age_minutes}m)"
                rm -rf "$lock_dir"
                return 1  # Retry acquisition
            fi
        else
            log_warn "Removing stale lock (no PID file, age ${lock_age_minutes}m)"
            rm -rf "$lock_dir"
            return 1  # Retry acquisition
        fi
    fi

    # Lock is held by another active process
    log_error "Branch locked by another process (age ${lock_age_minutes}m)"
    return 1
}

# Release branch lock
# Usage: release_branch_lock "debug/reflect/hook-frontmatter"
release_branch_lock() {
    local branch_name="$1"
    local lock_dir="$LOCKS_DIR/${branch_name//\//_}"

    if [[ -d "$lock_dir" ]]; then
        rm -rf "$lock_dir"
        log_debug "Released branch lock: $branch_name"
    fi
}

# ============================================================================
# Branch Operations
# ============================================================================

# Create feature branch for fix
# Usage: create_feature_branch "reflect" "hook-frontmatter"
# Returns: Branch name
create_feature_branch() {
    local plugin="$1"
    local issue_short="$2"
    local branch_name="debug/${plugin}/${issue_short}"

    # Ensure we're in source repo
    if [[ -z "${SOURCE_REPO_ROOT:-}" ]]; then
        if ! detect_source_repo; then
            log_error "Not in source repository"
            return 1
        fi
    fi

    cd "$SOURCE_REPO_ROOT" || return 1

    # Check if branch already exists
    if git rev-parse --verify "$branch_name" >/dev/null 2>&1; then
        log_warn "Branch already exists: $branch_name"
        git checkout "$branch_name"
    else
        # Create new branch from current HEAD
        git checkout -b "$branch_name"
        log_info "Created feature branch: $branch_name"
    fi

    echo "$branch_name"
}

# ============================================================================
# Commit Operations
# ============================================================================

# Commit fix with session tracking
# Usage: commit_fix "$issue_id" "$plugin" "$component" "$fix_description"
commit_fix() {
    local issue_id="$1"
    local plugin="$2"
    local component="$3"
    local fix_description="$4"

    # Ensure we're in source repo
    if [[ -z "${SOURCE_REPO_ROOT:-}" ]]; then
        log_error "SOURCE_REPO_ROOT not set"
        return 1
    fi

    cd "$SOURCE_REPO_ROOT" || return 1

    # Create commit message
    local commit_msg
    commit_msg=$(cat <<EOF
fix(${plugin}): ${fix_description}

Fixes detected issue in ${component}

Issue-ID: ${issue_id}
Session-ID: ${CURRENT_SESSION_ID}
Auto-generated: self-debugger plugin

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)

    # Commit with message
    if git commit -F - <<< "$commit_msg"; then
        log_success "Committed fix for issue: $issue_id"
        return 0
    else
        log_error "Failed to commit fix"
        return 1
    fi
}

# ============================================================================
# Push Operations
# ============================================================================

# Push branch to origin
# Usage: push_branch "debug/reflect/hook-frontmatter"
push_branch() {
    local branch_name="$1"

    # Ensure we're in source repo
    if [[ -z "${SOURCE_REPO_ROOT:-}" ]]; then
        log_error "SOURCE_REPO_ROOT not set"
        return 1
    fi

    cd "$SOURCE_REPO_ROOT" || return 1

    # Push with -u to set upstream
    if git push -u origin "$branch_name"; then
        log_success "Pushed branch to origin: $branch_name"
        return 0
    else
        log_error "Failed to push branch"
        return 1
    fi
}

# ============================================================================
# Helper Functions
# ============================================================================

# Get current git branch
get_current_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown"
}

# Check if working directory is clean
is_working_tree_clean() {
    git diff-index --quiet HEAD -- 2>/dev/null
}

# Get short commit hash
get_short_hash() {
    git rev-parse --short HEAD 2>/dev/null || echo "unknown"
}
