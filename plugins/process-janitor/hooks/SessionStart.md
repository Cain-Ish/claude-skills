---
event: SessionStart
description: Register current Claude Code session for process tracking
---

# Session Start Hook

This hook runs automatically when a Claude Code session starts. It registers the current session for tracking and optionally performs cleanup of orphaned sessions.

## What This Hook Does

1. **Registers Current Session**: Creates session metadata and starts heartbeat tracking
2. **Auto-Cleanup (Optional)**: If configured, scans for and cleans up orphaned sessions from previous crashes

## Configuration

Auto-cleanup can be enabled in `~/.claude/process-janitor-config.json`:

```json
{
  "auto_cleanup_on_start": true
}
```

## Hook Execution

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-register-session.sh
```
