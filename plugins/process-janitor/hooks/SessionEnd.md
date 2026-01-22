---
event: SessionEnd
description: Clean up current session on normal exit
---

# Session End Hook

This hook runs when a Claude Code session ends normally. It performs cleanup of the current session's child processes and updates session status.

## What This Hook Does

1. **Stops Heartbeat**: Terminates the background heartbeat process
2. **Updates Status**: Marks session as completed in metadata
3. **Cleans Child Processes**: Terminates any background jobs spawned during session
4. **Releases Locks**: Removes any locks held by this session

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

# Unregister current session
if [[ "$CURRENT_SESSION_ID" != "unknown" ]]; then
    unregister_session

    # Kill any background jobs from this session
    jobs -p | while read -r job_pid; do
        kill "$job_pid" 2>/dev/null || true
    done
fi
```

## Session Metadata Update

The hook updates the session metadata to include:
- End time timestamp
- Status: "completed"
- Exit code (if available)

## Cleanup Actions

- Stops heartbeat background process
- Updates session metadata with end time
- Does NOT remove session directory (kept for history)
- Removes temporary lock files

## Notes

- This hook does NOT delete session files (for audit trail)
- Orphaned session detection relies on heartbeat, not SessionEnd
- Failed or crashed sessions won't trigger this hook
