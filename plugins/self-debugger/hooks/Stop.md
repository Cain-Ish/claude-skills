---
event: Stop
---

# Self-Debugger: Session Stop Hook

Gracefully shut down the background monitor when the session ends and clean up orphaned processes.

## Cleanup Steps

Run the following cleanup steps (use defensive `|| true` to prevent hook failures):

```bash
# Step 1: Clean up orphaned Claude Code processes via process-janitor
echo "Self-debugger: Cleaning up orphaned processes..."
if command -v claude >/dev/null 2>&1; then
  claude /cleanup 2>/dev/null || true
fi

# Step 2: Clean up self-debugger monitor
DEBUGGER_HOME="$HOME/.claude/self-debugger"
GLOBAL_MONITOR_PID="$DEBUGGER_HOME/monitor.pid"
GLOBAL_MONITOR_SESSION="$DEBUGGER_HOME/monitor-session.id"
SESSION_DIR="$DEBUGGER_HOME/sessions/${CLAUDE_SESSION_ID}"

# Check if this session owns the global monitor
if [[ -f "$GLOBAL_MONITOR_SESSION" ]]; then
  OWNER_SESSION=$(cat "$GLOBAL_MONITOR_SESSION" 2>/dev/null || echo "")

  if [[ "$OWNER_SESSION" == "${CLAUDE_SESSION_ID}" ]]; then
    # This session owns the monitor - stop it
    echo "Self-debugger: Stopping global monitor (owned by this session)"

    PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
    if [[ -x "$PLUGIN_ROOT/scripts/stop-monitor.sh" ]]; then
      "$PLUGIN_ROOT/scripts/stop-monitor.sh" || true
    fi

    # Clean up global monitor files
    rm -f "$GLOBAL_MONITOR_PID" "$GLOBAL_MONITOR_SESSION" 2>/dev/null || true
    rm -rf "$DEBUGGER_HOME/global-monitor.lock" 2>/dev/null || true
  else
    echo "Self-debugger: Monitor owned by another session ($OWNER_SESSION), not stopping"
  fi
else
  echo "Self-debugger: No global monitor to clean up"
fi

# Clean up session directory (defensive)
if [[ -d "$SESSION_DIR" ]]; then
  # Mark session as stopped
  echo '{"status":"stopped","stopped_at":"'"$(date -u +"%Y-%m-%dT%H:%M:%SZ")"'"}' > "$SESSION_DIR/status.json" 2>/dev/null || true

  echo "Self-debugger: Session cleanup complete"
fi
```

## Safety

- All operations use `|| true` to prevent hook failures
- Graceful SIGTERM with 5-second timeout, then SIGKILL if needed
- Cleans up PID files and stale locks
- Session status preserved for metrics analysis
