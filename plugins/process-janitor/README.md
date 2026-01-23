# Process Janitor Plugin

Safely detect and clean up orphaned Claude Code sessions and their child processes. Includes multi-layer safety checks to prevent false positives when running multiple Claude instances simultaneously.

## Features

- **Session Tracking**: Registers each Claude session with heartbeat monitoring
- **Multi-Instance Safe**: Never kills active Claude sessions
- **Grace Period**: 10-minute minimum age before considering sessions orphaned
- **Heartbeat Verification**: Checks process liveness AND heartbeat staleness
- **Hostname Filtering**: Only cleans up sessions on the local machine
- **Optional Auto-Cleanup**: Automatically scan and cleanup on session start
- **Manual Cleanup**: `/cleanup` command for on-demand scanning

## Installation

The plugin is automatically discovered when copied to `~/.claude/plugins/process-janitor/`.

### Automatic Setup

1. Copy plugin to Claude plugins directory:
   ```bash
   cp -r plugins/process-janitor ~/.claude/plugins/
   ```

2. Enable plugin in `~/.claude/settings.json`:
   ```json
   {
     "enabledPlugins": {
       "process-janitor@claude-skills": true
     }
   }
   ```

3. (Optional) Create configuration file `~/.claude/process-janitor-config.json`:
   ```json
   {
     "auto_cleanup_on_start": true,
     "min_session_age_minutes": 10,
     "heartbeat_interval_seconds": 60,
     "stale_heartbeat_threshold_minutes": 5,
     "cleanup_mode": "auto",
     "dry_run_default": false
   }
   ```

If no configuration file exists, the plugin will use defaults from `config/default-config.json`.

## Configuration

### Configuration File: `~/.claude/process-janitor-config.json`

| Setting | Default | Description |
|---------|---------|-------------|
| `auto_cleanup_on_start` | `false` | Automatically scan and cleanup orphaned sessions when Claude starts |
| `min_session_age_minutes` | `10` | Minimum age (in minutes) before a session is considered orphaned |
| `heartbeat_interval_seconds` | `60` | How often session heartbeat is updated |
| `stale_heartbeat_threshold_minutes` | `5` | Minutes since last heartbeat before considered stale |
| `cleanup_mode` | `interactive` | `auto` for automatic cleanup, `interactive` for confirmation prompts |
| `notification_enabled` | `true` | Show notifications when orphaned sessions are detected |
| `dry_run_default` | `true` | Default to dry-run mode (show what would be cleaned without actually cleaning) |

### Configuration Profiles

#### Conservative (Default)
```json
{
  "auto_cleanup_on_start": false,
  "cleanup_mode": "interactive",
  "dry_run_default": true
}
```
- Manual cleanup only
- Always ask before cleaning
- Dry-run by default

#### Aggressive
```json
{
  "auto_cleanup_on_start": true,
  "cleanup_mode": "auto",
  "dry_run_default": false
}
```
- Auto-cleanup on start
- No confirmation prompts
- Actually performs cleanup

## Usage

### Automatic Cleanup (If Enabled)

When `auto_cleanup_on_start: true`, the plugin automatically:
1. Runs on every Claude session start
2. Scans for orphaned sessions
3. Cleans up sessions meeting safety criteria:
   - Process is dead
   - Heartbeat is stale (>5 minutes old)
   - Session is old enough (>10 minutes)
   - Hostname matches current machine

### Manual Cleanup

Use the `/cleanup` command:

```bash
# Scan for orphaned sessions (dry-run)
/cleanup scan

# Execute cleanup with confirmation
/cleanup run

# Force cleanup without prompts (dangerous)
/cleanup run --force
```

### Viewing Status

```bash
# List all tracked sessions
ls ~/.claude/process-janitor/sessions/

# View session metadata
cat ~/.claude/process-janitor/sessions/<session-id>/metadata.json

# Check cleanup logs
tail -f ~/.claude/process-janitor/cleanup.log
```

## How It Works

### Session Registration (SessionStart Hook)

When Claude starts:
1. Creates session directory: `~/.claude/process-janitor/sessions/<session-id>/`
2. Writes metadata:
   ```json
   {
     "session_id": "abc123-def456",
     "pid": 12345,
     "start_time": "2026-01-23T12:00:00Z",
     "last_heartbeat": "2026-01-23T12:05:00Z",
     "hostname": "macbook.local",
     "working_dir": "/path/to/workspace",
     "status": "active"
   }
   ```
3. Starts background heartbeat (updates every 60 seconds)
4. Optionally runs auto-cleanup scan

### Heartbeat Monitoring

A background process updates `last_heartbeat` every 60 seconds while Claude is running.

### Orphan Detection (5 Safety Layers)

A session is considered orphaned only if ALL conditions are met:

1. **Process Dead**: PID does not exist (`kill -0` fails)
2. **Stale Heartbeat**: Last heartbeat >5 minutes ago
3. **Minimum Age**: Session created >10 minutes ago
4. **Hostname Match**: Session created on current machine
5. **Parent Validation**: If parent Claude process exists, child is NOT orphaned

### Session Cleanup (SessionEnd/Stop Hooks)

On normal exit:
- SessionEnd hook updates status to "completed"
- Stops heartbeat
- Keeps session directory (for audit trail)

On crash/force-quit:
- Stop hook attempts emergency cleanup
- Heartbeat stops, session becomes stale
- Next Claude start detects orphan (if auto-cleanup enabled)

## Safety Guarantees

### Multi-Instance Protection

The plugin is designed to work safely with multiple simultaneous Claude instances:

- **Never kills active processes**: Checks process liveness before cleanup
- **Heartbeat validation**: Active sessions have recent heartbeats
- **Grace period**: Minimum 10-minute age prevents false positives during quick restarts
- **Hostname filtering**: Won't touch sessions from remote machines
- **Parent process checking**: Won't cleanup child sessions of active parents

### What Can Go Wrong (And How It's Prevented)

| Scenario | Protection | Result |
|----------|------------|--------|
| User runs 3 Claude instances simultaneously | Each has unique session ID + active heartbeat | All run safely, none killed |
| User force-quits and immediately restarts | Grace period (10 min) + heartbeat check | Old session NOT cleaned (too recent) |
| User switches workspaces rapidly | Each workspace has separate session | No interference |
| Session created on remote machine | Hostname verification | Remote sessions ignored |
| Race condition during cleanup | File locking with stale lock detection | Atomic operations, no corruption |

## Troubleshooting

### Issue: Sessions Not Being Cleaned Up

**Check:**
1. Is auto-cleanup enabled? `cat ~/.claude/process-janitor-config.json | jq .auto_cleanup_on_start`
2. Is session old enough? Sessions <10 minutes won't be cleaned
3. Is heartbeat truly stale? Check `last_heartbeat` in metadata
4. Check logs: `tail ~/.claude/process-janitor/cleanup.log`

### Issue: Active Session Wrongly Identified as Orphaned

This should NEVER happen. If it does:
1. Check heartbeat process is running: `pgrep -f "heartbeat.*<session-id>"`
2. Verify metadata file is writable: `ls -la ~/.claude/process-janitor/sessions/<session-id>/metadata.json`
3. Check for file lock issues
4. Report as bug with logs from `cleanup.log`

### Issue: Cleanup Logs Show Errors

Common errors:
- `CLAUDE_SESSION_ID not set`: Hook not running in Claude context (expected when testing manually)
- `Failed to acquire lock`: Another cleanup is running, will retry
- `File path validation failed`: Security check preventing access outside allowed directories

## Commands

### Available Commands

| Command | Description |
|---------|-------------|
| `/cleanup scan` | Scan for orphaned sessions (dry-run) |
| `/cleanup run` | Execute cleanup with confirmation |
| `/cleanup status` | Show current session info |
| `/cleanup config` | Display current configuration |

## Hooks

The plugin registers three hooks:

### SessionStart
- **Trigger**: When Claude session starts
- **Actions**:
  - Register session
  - Start heartbeat
  - Optionally run auto-cleanup scan

### SessionEnd
- **Trigger**: Normal Claude exit
- **Actions**:
  - Stop heartbeat
  - Update status to "completed"
  - Clean up background jobs

### Stop
- **Trigger**: Claude process termination (any reason)
- **Actions**:
  - Emergency heartbeat stop
  - Mark session as "stopped"
  - Release file locks

## File Structure

```
~/.claude/
├── process-janitor-config.json          # User configuration
└── process-janitor/
    ├── cleanup.log                      # Cleanup operation logs
    └── sessions/
        ├── <session-id-1>/
        │   └── metadata.json            # Session tracking data
        ├── <session-id-2>/
        │   └── metadata.json
        └── registry.jsonl               # Append-only session registry
```

## Future Extensions (Planned)

The current implementation provides session management and cleanup. Future extensions will add:

### Child Process Tracking

- **Track spawned processes**: vite, jest --watch, MCP servers
- **Orphan detection**: Find children of dead sessions by PPID and CWD
- **Graceful termination**: Kill child processes when parent session is cleaned
- **Process patterns**: Configure which processes to track

This will be developed separately in `scripts/lib/child-process-tracker.sh` and integrated later.

## Contributing

Contributions welcome! Areas for improvement:

1. **Child process cleanup**: Detect and cleanup orphaned dev servers, MCP processes
2. **Better notifications**: Desktop notifications for detected orphans
3. **Statistics**: Track cleanup history, patterns
4. **Recovery**: Restore sessions after crash (save workspace state)

## License

MIT - See LICENSE file in repository root

## Credits

Part of the [claude-skills](https://github.com/Cain-Ish/claude-skills) collection.
