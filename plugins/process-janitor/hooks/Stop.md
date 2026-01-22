---
event: Stop
description: Final cleanup before Claude Code process exits
---

# Stop Hook

This hook runs immediately before the Claude Code process terminates. It ensures graceful cleanup of session tracking resources.

## What This Hook Does

1. **Terminates Heartbeat**: Forcefully stops the heartbeat background process
2. **Releases Locks**: Ensures all file locks are released
3. **Marks Session Stopped**: Updates session status to "stopped"
4. **Emergency Cleanup**: Final attempt to clean up resources

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

# Stop heartbeat if running
if [[ "$CURRENT_SESSION_ID" != "unknown" ]]; then
    stop_heartbeat "$CURRENT_SESSION_ID" 2>/dev/null || true

    # Update metadata with stop time
    metadata_file=$(get_session_metadata_file "$CURRENT_SESSION_ID")

    if [[ -f "$metadata_file" ]]; then
        updated_metadata=$(cat "$metadata_file" | jq --arg ts "$(get_timestamp)" '.stop_time = $ts | .status = "stopped"')
        if has_jq && [[ -n "$updated_metadata" ]]; then
            write_json "$updated_metadata" "$metadata_file" 2>/dev/null || true
        fi
    fi
fi

# Remove any stale locks owned by this process
find ~/.claude/sessions/ -name "*.lock.dir" -type d 2>/dev/null | while read -r lock_dir; do
    if [[ -f "$lock_dir/pid" ]]; then
        lock_pid=$(cat "$lock_dir/pid" 2>/dev/null || echo "")
        if [[ "$lock_pid" == "$$" ]]; then
            rm -rf "$lock_dir" 2>/dev/null || true
        fi
    fi
done || true
```

## Difference from SessionEnd

| Hook | SessionEnd | Stop |
|------|-----------|------|
| **Trigger** | Normal session completion | Process termination (any reason) |
| **Timing** | End of session | Immediately before exit |
| **Reliability** | May not run on crash | More likely to run |
| **Purpose** | Graceful cleanup | Emergency cleanup |

## Error Handling

This hook uses defensive error handling:
- All commands use `|| true` to prevent failures from blocking exit
- File operations wrapped in existence checks
- No critical operations that could hang

## Notes

- Runs even on abnormal termination (SIGINT, SIGTERM)
- Heartbeat will stop, causing session to appear orphaned soon
- Does NOT block process exit
- Silent failures are acceptable (logged only)
