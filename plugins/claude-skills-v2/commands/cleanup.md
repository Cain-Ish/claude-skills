---
name: cleanup
description: Clean up orphaned processes, old files, and optimize system resources
usage: /cleanup [--dry-run] [--verbose] [--aggressive]
examples:
  - /cleanup
  - /cleanup --dry-run
  - /cleanup --verbose
  - /cleanup --aggressive
---

# /cleanup - System Resource Cleanup

Clean up orphaned processes, stale files, and optimize Claude Skills system resources.

## What This Does

1. **Orphaned Processes** - Removes stale background observer PIDs
2. **Old Sessions** - Deletes session files >30 days old
3. **Large Logs** - Truncates logs >100MB to last 1000 lines
4. **Validation Backups** - Removes backups >7 days old
5. **Task Outputs** - Cleans up old task output files
6. **Zombie Processes** - Reports (cannot kill, but auto-cleanup)
7. **Disk Usage** - Reports total usage by component

## Usage

```bash
# Standard cleanup
/cleanup

# Preview without changes
/cleanup --dry-run

# Show detailed output
/cleanup --verbose

# More aggressive (shorter retention)
/cleanup --aggressive
```

## Configuration

**Standard Cleanup:**
- Session files: >30 days
- Log files: >100MB
- Backups: >7 days
- Task outputs: >1 day

**Aggressive Cleanup (`--aggressive`):**
- Session files: >7 days
- Log files: >50MB
- Backups: >3 days
- Task outputs: >12 hours

## What Gets Cleaned

### 1. Orphaned Observer Processes

**Problem:** Background observer PID file points to dead process

**Cleanup:**
```bash
# Removes stale PID file
rm ~/.claude/claude-skills/learning/observer.pid
```

### 2. Old Session Files

**Problem:** Session logs accumulate over time

**Location:** `~/.claude/claude-skills/observations/sessions/*.jsonl`

**Cleanup:**
```bash
# Remove sessions older than 30 days
find sessions/ -name "*.jsonl" -mtime +30 -delete
```

### 3. Large Log Files

**Problem:** Log files grow without rotation

**Location:** `~/.claude/claude-skills/learning/*.log`

**Cleanup:**
```bash
# Truncate to last 1000 lines if >100MB
tail -1000 large.log > large.log.tmp && mv large.log.tmp large.log
```

### 4. Validation Backups

**Problem:** Pre-fix backups accumulate

**Location:** `.validation-backups/*.bak`

**Cleanup:**
```bash
# Remove backups older than 7 days
find .validation-backups/ -name "*.bak" -mtime +7 -delete
```

### 5. Task Output Files

**Problem:** Old task outputs left behind

**Location:** `~/.claude/task-outputs/*.txt`

**Cleanup:**
```bash
# Remove outputs older than 1 day
find task-outputs/ -name "*.txt" -mtime +1 -delete
```

## Example Output

### Standard Cleanup

```bash
/cleanup
```

Output:
```
[janitor] Checking for orphaned background observer processes...
[janitor] No observer PID file found
[janitor] Cleaning up old session files (>30 days)...
[janitor] Removed 15 old session files
[janitor] Checking for large log files (>100MB)...
[janitor] Truncating large log: observer.log (145MB)
[janitor] Cleaning up old validation backups (>7 days)...
[janitor] Removed 8 old validation backups
[janitor] Cleaning up orphaned task output files...
[janitor] Removed 3 old task output files
[janitor] Checking for zombie Claude processes...
[janitor] No zombie processes found
[janitor] Checking Claude Skills disk usage...
[janitor] Total disk usage: 245M
[janitor]   Observations: 120M
[janitor]   Learning: 85M
[janitor]   Instincts: 40M

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Cleanup complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Items cleaned: 26
Zombie processes: 0
Disk usage: 245M

💡 Tip: Run this janitor regularly to keep system clean
   Auto-run: Add to SessionEnd hook or cron
```

### Dry Run

```bash
/cleanup --dry-run
```

Output:
```
[dry-run] Would remove 15 old session files
[dry-run] Would truncate observer.log (145MB → 1000 lines)
[dry-run] Would remove 8 validation backups
[dry-run] Would remove 3 task outputs

Summary: 26 items would be cleaned (no changes made)
```

## Automatic Cleanup

### SessionEnd Hook Integration

The janitor automatically runs on SessionEnd (can be disabled):

```json
// config/auto-commit-config.json
{
  "cleanup": {
    "run_on_session_end": true,
    "aggressive": false
  }
}
```

### Cron Schedule (Optional)

For long-running systems:

```bash
# Run daily at 2am
0 2 * * * /path/to/scripts/optimization/process-janitor.sh
```

## Safety Features

1. **Dry run mode** - Preview without changes
2. **Age thresholds** - Only removes old files
3. **Preserves recent** - Keeps files within retention period
4. **Logs actions** - All cleanup logged for audit
5. **No data loss** - Only removes temporary/stale files

## What Doesn't Get Cleaned

**Preserved items:**
- Active session files
- Recent observations (<30 days)
- Learned instincts (permanent)
- Small log files (<100MB)
- Recent backups (<7 days)
- Running processes

## Troubleshooting

**"Too many files to clean"**
- Use `--aggressive` for shorter retention
- Check disk space: `df -h`
- Review large directories: `du -sh ~/.claude/claude-skills/*`

**"Cannot remove file: Permission denied"**
- Check file permissions
- Some files may be in use
- Run cleanup when Claude Code is idle

**"Disk usage still high"**
- Check for large instinct files
- Review observation log sizes
- Consider archiving old sessions

## Integration

Works with:
- `/validate-plugin` - Clean before validation
- Auto-commit - Clean after commits
- SessionEnd hook - Automatic cleanup
- Background observer - Keeps logs manageable

## Implementation

Executes `scripts/optimization/process-janitor.sh` with options.

## See Also

- `scripts/optimization/process-janitor.sh` - Cleanup implementation
- `scripts/optimization/resource-monitor.sh` - Resource monitoring
- `/optimize` - Resource optimization (future)
