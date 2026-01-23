---
event: SessionStart
---

# Self-Debugger: Session Start Hook

You are running the self-debugger plugin. This plugin monitors, debugs, and improves all plugins in the claude-skills repository.

## Activation Check

**IMPORTANT:** This plugin only activates when running inside the claude-skills source repository.

Perform these checks:

1. **Detect source repository:**
   - Search upward from current working directory for `.git` directory
   - Once found, check if `plugins/` directory exists at repo root
   - If both conditions are true, this is the source repo

2. **Verify not in installed plugin directory:**
   - Plugin should NOT activate in `~/.claude/plugins/` or similar
   - Only activate in the actual source repository

3. **If NOT in source repo:**
   - Stop here - do NOT launch background monitor
   - Log: "Self-debugger: Not in source repo, skipping activation"
   - Exit gracefully

## Background Monitor Launch

If in source repository, launch the background monitor:

```bash
# Global monitor coordination - only one monitor across all Claude instances
DEBUGGER_HOME="$HOME/.claude/self-debugger"
GLOBAL_MONITOR_LOCK="$DEBUGGER_HOME/global-monitor.lock"
GLOBAL_MONITOR_PID="$DEBUGGER_HOME/monitor.pid"
GLOBAL_MONITOR_SESSION="$DEBUGGER_HOME/monitor-session.id"
SESSION_DIR="$DEBUGGER_HOME/sessions/${CLAUDE_SESSION_ID}"

mkdir -p "$DEBUGGER_HOME"
mkdir -p "$SESSION_DIR"

# Initialize session heartbeat
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$SESSION_DIR/heartbeat.ts"

# Check if a global monitor is already running
if [[ -f "$GLOBAL_MONITOR_PID" ]]; then
  EXISTING_PID=$(cat "$GLOBAL_MONITOR_PID" 2>/dev/null || echo "")
  OWNER_SESSION=$(cat "$GLOBAL_MONITOR_SESSION" 2>/dev/null || echo "unknown")

  if [[ -n "$EXISTING_PID" ]] && kill -0 "$EXISTING_PID" 2>/dev/null; then
    if [[ "$OWNER_SESSION" == "${CLAUDE_SESSION_ID}" ]]; then
      echo "Self-debugger: Monitor already running in this session (PID: $EXISTING_PID)"
    else
      echo "Self-debugger: Monitor running in another session (PID: $EXISTING_PID, session: $OWNER_SESSION)"
    fi
    exit 0
  else
    # Stale PID file, clean up
    echo "Self-debugger: Cleaning up stale monitor (PID: $EXISTING_PID)"
    rm -f "$GLOBAL_MONITOR_PID" "$GLOBAL_MONITOR_SESSION"
  fi
fi

# Try to acquire global monitor lock
# Use flock for atomic locking (available on Linux/macOS)
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"

if command -v flock &>/dev/null; then
  # Linux/Git Bash: Use flock
  exec 200>"$GLOBAL_MONITOR_LOCK"
  if ! flock -n 200; then
    echo "Self-debugger: Another instance is starting monitor, skipping"
    exit 0
  fi

  # Lock acquired - launch monitor
  if [[ -x "$PLUGIN_ROOT/scripts/start-monitor.sh" ]]; then
    nohup "$PLUGIN_ROOT/scripts/start-monitor.sh" >> "$DEBUGGER_HOME/monitor.log" 2>&1 &
    MONITOR_PID=$!

    # Store global monitor info
    echo "$MONITOR_PID" > "$GLOBAL_MONITOR_PID"
    echo "${CLAUDE_SESSION_ID}" > "$GLOBAL_MONITOR_SESSION"

    echo "Self-debugger: Global monitor started (PID: $MONITOR_PID)"
    echo "  - Scan interval: 5 minutes"
    echo "  - Findings: ~/.claude/self-debugger/findings/issues.jsonl"
    echo "  - Use /debug command to view issues and apply fixes"
  else
    echo "Self-debugger: Error: start-monitor.sh not found"
    exit 1
  fi
else
  # macOS fallback: Use mkdir-based locking
  if mkdir "$GLOBAL_MONITOR_LOCK" 2>/dev/null; then
    trap 'rm -rf "$GLOBAL_MONITOR_LOCK"' EXIT

    # Lock acquired - launch monitor
    if [[ -x "$PLUGIN_ROOT/scripts/start-monitor.sh" ]]; then
      nohup "$PLUGIN_ROOT/scripts/start-monitor.sh" >> "$DEBUGGER_HOME/monitor.log" 2>&1 &
      MONITOR_PID=$!

      # Store global monitor info
      echo "$MONITOR_PID" > "$GLOBAL_MONITOR_LOCK/pid"
      echo "$MONITOR_PID" > "$GLOBAL_MONITOR_PID"
      echo "${CLAUDE_SESSION_ID}" > "$GLOBAL_MONITOR_SESSION"

      echo "Self-debugger: Global monitor started (PID: $MONITOR_PID)"
      echo "  - Scan interval: 5 minutes"
      echo "  - Findings: ~/.claude/self-debugger/findings/issues.jsonl"
      echo "  - Use /debug command to view issues and apply fixes"
    else
      echo "Self-debugger: Error: start-monitor.sh not found"
      exit 1
    fi
  else
    echo "Self-debugger: Another instance is starting monitor, skipping"
    exit 0
  fi
fi
```

## Notes

- Background monitor runs non-blocking (session starts immediately)
- First scan starts after 5 seconds (allows session to initialize)
- Subsequent scans every 5 minutes
- Monitor will be stopped automatically on session end (Stop hook)
- Use `/debug` command to interact with findings

## Safety

- Only runs in source repository (never in installed plugins)
- Non-blocking: does not delay session start
- Graceful handling of stale PID files
- Locked file access prevents concurrent write conflicts
