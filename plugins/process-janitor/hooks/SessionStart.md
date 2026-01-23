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
#!/bin/bash
set -euo pipefail

# Source libraries
SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT}/scripts"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/platform.sh"
source "$SCRIPT_DIR/lib/process-tracker.sh"

# Initialize
init_janitor

# Check if we have a valid session ID
if [[ "$CURRENT_SESSION_ID" == "unknown" ]]; then
    log_error "CLAUDE_SESSION_ID not set"
    exit 1
fi

# Register the session
if register_session; then
    log_info "Session tracking initialized"

    # Check if auto-cleanup is enabled
    if [[ "${JANITOR_AUTO_CLEANUP:-false}" == "true" ]]; then
        log_info "Auto-cleanup enabled - scanning for orphaned sessions..."

        # Run cleanup scan (non-interactive, auto mode)
        if [[ -x "$SCRIPT_DIR/cleanup-scan.sh" ]]; then
            "$SCRIPT_DIR/cleanup-scan.sh" --quiet 2>/dev/null || true
        fi
    fi
else
    log_error "Failed to register session"
    exit 1
fi
```
