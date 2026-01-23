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
# Check if monitor is already running
SESSION_DIR="$HOME/.claude/self-debugger/sessions/${CLAUDE_SESSION_ID}"
MONITOR_PID_FILE="$SESSION_DIR/monitor.pid"

if [[ -f "$MONITOR_PID_FILE" ]]; then
  EXISTING_PID=$(cat "$MONITOR_PID_FILE")
  if kill -0 "$EXISTING_PID" 2>/dev/null; then
    echo "Self-debugger: Monitor already running (PID: $EXISTING_PID)"
    exit 0
  else
    # Stale PID file, clean up
    rm -f "$MONITOR_PID_FILE"
  fi
fi

# Create session directory
mkdir -p "$SESSION_DIR"

# Initialize heartbeat
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$SESSION_DIR/heartbeat.ts"

# Launch monitor in background (non-blocking)
# Use start-monitor.sh script from plugin
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
if [[ -x "$PLUGIN_ROOT/scripts/start-monitor.sh" ]]; then
  # Launch in background, redirect output to log file
  nohup "$PLUGIN_ROOT/scripts/start-monitor.sh" >> "$SESSION_DIR/monitor.log" 2>&1 &
  MONITOR_PID=$!

  # Store PID for later cleanup
  echo "$MONITOR_PID" > "$MONITOR_PID_FILE"

  echo "Self-debugger: Background monitor started (PID: $MONITOR_PID)"
  echo "  - Scan interval: 5 minutes"
  - Findings: ~/.claude/self-debugger/findings/issues.jsonl"
  echo "  - Use /debug command to view issues and apply fixes"
else
  echo "Self-debugger: Warning: start-monitor.sh not found or not executable"
  exit 1
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
