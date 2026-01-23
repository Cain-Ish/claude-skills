---
event: Stop
---

# Self-Debugger: Session Stop Hook

Gracefully shut down the background monitor when the session ends.

## Cleanup Steps

Run the following cleanup steps (use defensive `|| true` to prevent hook failures):

```bash
# Stop background monitor
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"

if [[ -x "$PLUGIN_ROOT/scripts/stop-monitor.sh" ]]; then
  "$PLUGIN_ROOT/scripts/stop-monitor.sh" || true
fi

# Clean up session directory (defensive)
SESSION_DIR="$HOME/.claude/self-debugger/sessions/${CLAUDE_SESSION_ID}"
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
