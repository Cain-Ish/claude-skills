#!/usr/bin/env bash
# reflect-cleanup-memories.sh - Archive old memories and clean up stale data
#
# Usage:
#   reflect-cleanup-memories.sh [OPTIONS]
#
# Options:
#   --dry-run              Show what would be archived without making changes
#   --age-days DAYS        Age threshold in days (default: 90)
#   --force                Skip confirmation prompt
#   --clean-metrics        Also clean old metrics (>180 days)
#   --clean-feedback       Also clean old external feedback (>30 days)
#   --help                 Show this help message
#
# Examples:
#   reflect-cleanup-memories.sh --dry-run
#   reflect-cleanup-memories.sh --age-days 60
#   reflect-cleanup-memories.sh --clean-metrics --clean-feedback
#
# This script:
# 1. Archives memory files not modified in N days (default: 90)
# 2. Optionally cleans old metrics and external feedback
# 3. Creates timestamped archive directories
# 4. Preserves file structure in archives

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MEMORIES_DIR="${HOME}/.claude/memories"
ARCHIVE_BASE="${HOME}/.claude/memories-archive"
METRICS_FILE="${HOME}/.claude/reflect-metrics.jsonl"
FEEDBACK_DIR="${HOME}/.claude/reflect-external-feedback"

# Defaults
DRY_RUN=false
AGE_DAYS=90
FORCE=false
CLEAN_METRICS=false
CLEAN_FEEDBACK=false

# Parse arguments
show_help() {
    head -n 20 "$0" | grep '^#' | sed 's/^# \?//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --age-days)
            AGE_DAYS="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --clean-metrics)
            CLEAN_METRICS=true
            shift
            ;;
        --clean-feedback)
            CLEAN_FEEDBACK=true
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Utility functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*" >&2
}

# Create archive directory with timestamp
create_archive_dir() {
    local archive_date
    archive_date=$(date +%Y-%m)
    local archive_dir="${ARCHIVE_BASE}/${archive_date}"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would create archive directory: $archive_dir"
    else
        mkdir -p "$archive_dir"
        log_success "Created archive directory: $archive_dir"
    fi

    echo "$archive_dir"
}

# Find and archive old memory files
archive_old_memories() {
    log_info "Searching for memory files older than $AGE_DAYS days..."

    if [ ! -d "$MEMORIES_DIR" ]; then
        log_warning "Memories directory not found: $MEMORIES_DIR"
        return
    fi

    # Find files older than AGE_DAYS days, excluding README.md
    local old_files
    old_files=$(find "$MEMORIES_DIR" -type f -name "*.md" ! -name "README.md" -mtime "+${AGE_DAYS}" 2>/dev/null || true)

    if [ -z "$old_files" ]; then
        log_info "No memory files older than $AGE_DAYS days found"
        return
    fi

    local count
    count=$(echo "$old_files" | wc -l | tr -d ' ')
    log_info "Found $count memory file(s) to archive:"

    # List files with modification dates
    echo "$old_files" | while read -r file; do
        local mod_date
        mod_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$file" 2>/dev/null || stat -c "%y" "$file" 2>/dev/null | cut -d' ' -f1)
        local rel_path
        rel_path=$(basename "$file")
        echo "  - $rel_path (last modified: $mod_date)"
    done

    # Confirm if not forced
    if [ "$DRY_RUN" = false ] && [ "$FORCE" = false ]; then
        echo
        read -rp "Archive these files? [y/N] " -n 1
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Archival cancelled"
            return
        fi
    fi

    # Create archive directory
    local archive_dir
    archive_dir=$(create_archive_dir)

    # Archive each file
    echo "$old_files" | while read -r file; do
        local basename
        basename=$(basename "$file")

        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY-RUN] Would archive: $basename"
        else
            mv "$file" "$archive_dir/$basename"
            log_success "Archived: $basename → $archive_dir/"
        fi
    done

    if [ "$DRY_RUN" = false ]; then
        log_success "Archived $count memory file(s)"
    fi
}

# Clean old metrics
clean_old_metrics() {
    if [ "$CLEAN_METRICS" = false ]; then
        return
    fi

    log_info "Cleaning metrics older than 180 days..."

    if [ ! -f "$METRICS_FILE" ]; then
        log_warning "Metrics file not found: $METRICS_FILE"
        return
    fi

    # Calculate cutoff timestamp (180 days ago)
    local cutoff_timestamp
    if date --version >/dev/null 2>&1; then
        # GNU date
        cutoff_timestamp=$(date -d "180 days ago" -u +"%Y-%m-%dT%H:%M:%SZ")
    else
        # BSD date (macOS)
        cutoff_timestamp=$(date -v-180d -u +"%Y-%m-%dT%H:%M:%SZ")
    fi

    # Count old entries
    local old_count
    old_count=$(jq -r "select(.timestamp < \"$cutoff_timestamp\")" "$METRICS_FILE" 2>/dev/null | wc -l | tr -d ' ')

    if [ "$old_count" -eq 0 ]; then
        log_info "No old metrics to clean"
        return
    fi

    log_info "Found $old_count metric entries older than 180 days"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would remove $old_count old metric entries"
        return
    fi

    # Confirm if not forced
    if [ "$FORCE" = false ]; then
        echo
        read -rp "Remove these old metrics? [y/N] " -n 1
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Metrics cleanup cancelled"
            return
        fi
    fi

    # Filter out old entries
    local temp_file
    temp_file=$(mktemp)
    jq -r "select(.timestamp >= \"$cutoff_timestamp\")" "$METRICS_FILE" > "$temp_file"
    mv "$temp_file" "$METRICS_FILE"

    log_success "Removed $old_count old metric entries"
}

# Clean old external feedback
clean_old_feedback() {
    if [ "$CLEAN_FEEDBACK" = false ]; then
        return
    fi

    log_info "Cleaning external feedback older than 30 days..."

    if [ ! -d "$FEEDBACK_DIR" ]; then
        log_warning "External feedback directory not found: $FEEDBACK_DIR"
        return
    fi

    # Find files older than 30 days
    local old_files
    old_files=$(find "$FEEDBACK_DIR" -type f -name "*.jsonl" -mtime +30 2>/dev/null || true)

    if [ -z "$old_files" ]; then
        log_info "No old external feedback files found"
        return
    fi

    local count
    count=$(echo "$old_files" | wc -l | tr -d ' ')
    log_info "Found $count external feedback file(s) to remove"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would remove $count external feedback files"
        return
    fi

    # Confirm if not forced
    if [ "$FORCE" = false ]; then
        echo
        read -rp "Remove these old feedback files? [y/N] " -n 1
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Feedback cleanup cancelled"
            return
        fi
    fi

    # Remove files
    echo "$old_files" | while read -r file; do
        rm "$file"
    done

    log_success "Removed $count old external feedback file(s)"
}

# Print summary
print_summary() {
    echo
    log_info "Cleanup Summary"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}Mode:${NC} Dry-run (no changes made)"
    else
        echo -e "${GREEN}Mode:${NC} Live (changes applied)"
    fi

    echo "Memory age threshold: $AGE_DAYS days"
    echo "Archive location: $ARCHIVE_BASE"

    if [ "$CLEAN_METRICS" = true ]; then
        echo "Metrics cleanup: Enabled (180 days)"
    fi

    if [ "$CLEAN_FEEDBACK" = true ]; then
        echo "Feedback cleanup: Enabled (30 days)"
    fi

    echo
}

# Main execution
main() {
    log_info "Reflect Memory Cleanup"
    echo

    # Archive old memories
    archive_old_memories

    # Clean metrics if requested
    clean_old_metrics

    # Clean feedback if requested
    clean_old_feedback

    # Print summary
    print_summary

    if [ "$DRY_RUN" = true ]; then
        log_info "This was a dry-run. Run without --dry-run to apply changes."
    else
        log_success "Cleanup completed successfully"
    fi
}

main
