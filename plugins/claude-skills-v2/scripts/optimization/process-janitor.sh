#!/usr/bin/env bash
set -euo pipefail

# Process Janitor - Cleans up orphaned Claude Code processes and stale resources
# Prevents resource leaks from failed agents, background tasks, and zombie processes

# Configuration
CLAUDE_SKILLS_DIR="${HOME}/.claude/claude-skills"
LEARNING_DIR="${CLAUDE_SKILLS_DIR}/learning"
SESSION_DIR="${CLAUDE_SKILLS_DIR}/observations/sessions"
MAX_SESSION_AGE_DAYS=30
MAX_LOG_SIZE_MB=100

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
  echo -e "${BLUE}[janitor]${NC} $1"
}

cleanup_count=0

# ============================================================
# 1. Clean up orphaned background observer processes
# ============================================================
log "Checking for orphaned background observer processes..."

OBSERVER_PID_FILE="${LEARNING_DIR}/observer.pid"
if [[ -f "$OBSERVER_PID_FILE" ]]; then
  PID=$(cat "$OBSERVER_PID_FILE")

  if ps -p "$PID" > /dev/null 2>&1; then
    # Process exists, check if it's actually the observer
    if ps -p "$PID" -o command= | grep -q "background-observer"; then
      log "Background observer running (PID: $PID) - OK"
    else
      log "PID file points to wrong process, cleaning up"
      rm -f "$OBSERVER_PID_FILE"
      ((cleanup_count++))
    fi
  else
    # Process doesn't exist, remove stale PID file
    log "Removing stale observer PID file"
    rm -f "$OBSERVER_PID_FILE"
    ((cleanup_count++))
  fi
else
  log "No observer PID file found"
fi

# ============================================================
# 2. Clean up stale session files
# ============================================================
log "Cleaning up old session files (>${MAX_SESSION_AGE_DAYS} days)..."

if [[ -d "$SESSION_DIR" ]]; then
  OLD_SESSIONS=$(find "$SESSION_DIR" -name "*.jsonl" -mtime +${MAX_SESSION_AGE_DAYS} 2>/dev/null || echo "")

  if [[ -n "$OLD_SESSIONS" ]]; then
    OLD_COUNT=$(echo "$OLD_SESSIONS" | wc -l | tr -d ' ')
    echo "$OLD_SESSIONS" | xargs rm -f
    log "Removed $OLD_COUNT old session files"
    ((cleanup_count += OLD_COUNT))
  else
    log "No old session files to clean"
  fi
fi

# ============================================================
# 3. Clean up large log files
# ============================================================
log "Checking for large log files (>${MAX_LOG_SIZE_MB}MB)..."

if [[ -d "$LEARNING_DIR" ]]; then
  LARGE_LOGS=$(find "$LEARNING_DIR" -name "*.log" -size +${MAX_LOG_SIZE_MB}M 2>/dev/null || echo "")

  if [[ -n "$LARGE_LOGS" ]]; then
    while IFS= read -r log_file; do
      if [[ -z "$log_file" ]]; then continue; fi

      SIZE=$(du -m "$log_file" | cut -f1)
      log "Truncating large log: $(basename "$log_file") (${SIZE}MB)"

      # Keep last 1000 lines
      tail -1000 "$log_file" > "${log_file}.tmp"
      mv "${log_file}.tmp" "$log_file"
      ((cleanup_count++))
    done <<< "$LARGE_LOGS"
  else
    log "No large log files found"
  fi
fi

# ============================================================
# 4. Clean up temporary validation backups
# ============================================================
log "Cleaning up old validation backups (>7 days)..."

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BACKUP_DIR="${PLUGIN_DIR}/.validation-backups"

if [[ -d "$BACKUP_DIR" ]]; then
  OLD_BACKUPS=$(find "$BACKUP_DIR" -name "*.bak" -mtime +7 2>/dev/null || echo "")

  if [[ -n "$OLD_BACKUPS" ]]; then
    BACKUP_COUNT=$(echo "$OLD_BACKUPS" | wc -l | tr -d ' ')
    echo "$OLD_BACKUPS" | xargs rm -f
    log "Removed $BACKUP_COUNT old validation backups"
    ((cleanup_count += BACKUP_COUNT))
  else
    log "No old validation backups to clean"
  fi
fi

# ============================================================
# 5. Clean up orphaned task output files
# ============================================================
log "Cleaning up orphaned task output files..."

TASK_OUTPUT_DIR="${HOME}/.claude/task-outputs"
if [[ -d "$TASK_OUTPUT_DIR" ]]; then
  # Find outputs older than 1 day
  OLD_OUTPUTS=$(find "$TASK_OUTPUT_DIR" -name "*.txt" -mtime +1 2>/dev/null || echo "")

  if [[ -n "$OLD_OUTPUTS" ]]; then
    OUTPUT_COUNT=$(echo "$OLD_OUTPUTS" | wc -l | tr -d ' ')
    echo "$OLD_OUTPUTS" | xargs rm -f
    log "Removed $OUTPUT_COUNT old task output files"
    ((cleanup_count += OUTPUT_COUNT))
  fi
fi

# ============================================================
# 6. Check for zombie Claude processes
# ============================================================
log "Checking for zombie Claude processes..."

ZOMBIE_COUNT=0
while IFS= read -r zombie; do
  if [[ -n "$zombie" ]]; then
    PID=$(echo "$zombie" | awk '{print $2}')
    log "Found zombie process: $PID"
    ((ZOMBIE_COUNT++))
  fi
done < <(ps aux | grep -i claude | grep -i defunct || echo "")

if [[ $ZOMBIE_COUNT -eq 0 ]]; then
  log "No zombie processes found"
else
  log "Found $ZOMBIE_COUNT zombie processes (cannot kill defunct, they'll clean up automatically)"
fi

# ============================================================
# 7. Report disk usage
# ============================================================
log "Checking Claude Skills disk usage..."

if [[ -d "$CLAUDE_SKILLS_DIR" ]]; then
  TOTAL_SIZE=$(du -sh "$CLAUDE_SKILLS_DIR" 2>/dev/null | cut -f1 || echo "unknown")
  log "Total disk usage: $TOTAL_SIZE"

  # Breakdown by directory
  if [[ -d "${CLAUDE_SKILLS_DIR}/observations" ]]; then
    OBS_SIZE=$(du -sh "${CLAUDE_SKILLS_DIR}/observations" 2>/dev/null | cut -f1 || echo "0")
    log "  Observations: $OBS_SIZE"
  fi

  if [[ -d "${CLAUDE_SKILLS_DIR}/learning" ]]; then
    LEARN_SIZE=$(du -sh "${CLAUDE_SKILLS_DIR}/learning" 2>/dev/null | cut -f1 || echo "0")
    log "  Learning: $LEARN_SIZE"
  fi

  if [[ -d "${CLAUDE_SKILLS_DIR}/instincts" ]]; then
    INST_SIZE=$(du -sh "${CLAUDE_SKILLS_DIR}/instincts" 2>/dev/null | cut -f1 || echo "0")
    log "  Instincts: $INST_SIZE"
  fi
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Cleanup complete${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Items cleaned: $cleanup_count"
echo "Zombie processes: $ZOMBIE_COUNT (if any, will clean up automatically)"
echo "Disk usage: $TOTAL_SIZE"
echo ""

if [[ $cleanup_count -gt 0 ]]; then
  echo -e "${YELLOW}💡 Tip: Run this janitor regularly to keep system clean${NC}"
  echo -e "${YELLOW}   Auto-run: Add to SessionEnd hook or cron${NC}"
fi

exit 0
