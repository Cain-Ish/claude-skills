---
name: cleanup
description: Manage and clean up orphaned Claude Code processes
usage: |
  /cleanup [scan|report|run|auto|status]
arguments:
  - name: action
    description: Action to perform
    required: false
    default: scan
    choices:
      - scan
      - report
      - run
      - auto
      - status
examples:
  - command: /cleanup
    description: Scan for orphaned processes (safe, read-only)
  - command: /cleanup scan
    description: Scan for orphaned processes
  - command: /cleanup report
    description: Generate detailed report
  - command: /cleanup run
    description: Execute cleanup with confirmation
  - command: /cleanup auto
    description: Execute cleanup automatically
  - command: /cleanup status
    description: Show current session tracking status
---

# Process Cleanup Command

Safely detect and clean up orphaned Claude Code processes from crashed or force-killed sessions.

## Actions

### scan (default)
Scan for orphaned processes without making any changes. This is a safe, read-only operation.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-scan.sh
```

### report
Generate a detailed report about all tracked sessions.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-report.sh
```

### run
Execute cleanup with interactive confirmation prompt. Uses dry-run mode by default.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-processes.sh --execute
```

### auto
Execute cleanup automatically without prompts (for automation).

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-processes.sh --auto
```

### status
Show current session tracking status and configuration.

```bash
echo "Current Session: ${CLAUDE_SESSION_ID}"
echo "Tracking Directory: ~/.claude/sessions/"
echo ""
ls -la ~/.claude/sessions/ 2>/dev/null || echo "No sessions tracked"
```

## Safety Features

- **Multi-layer safety checks**: 5 independent checks before cleanup
- **Current session protection**: Never cleans up the active session
- **Grace period**: Sessions < 10 minutes old are protected
- **Dry-run default**: Preview changes before execution
- **Confirmation prompts**: Interactive approval required

## Configuration

Edit `~/.claude/process-janitor-config.json` to customize:

```json
{
  "auto_cleanup_on_start": false,
  "min_session_age_minutes": 10,
  "heartbeat_interval_seconds": 60,
  "stale_heartbeat_threshold_minutes": 5
}
```
