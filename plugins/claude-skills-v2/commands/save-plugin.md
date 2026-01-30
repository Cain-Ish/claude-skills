---
name: save-plugin
description: Manually trigger auto-commit to save plugin development progress
usage: /save-plugin [--push] [--message "custom message"]
examples:
  - /save-plugin
  - /save-plugin --push
  - /save-plugin --message "Implemented validation system"
---

# /save-plugin - Save Plugin Development Progress

Manually trigger an auto-commit to save your plugin development work and prevent data loss.

## What This Does

1. **Validates** plugin structure (if validation enabled)
2. **Stages all changes** (modified and new files)
3. **Creates commit** with descriptive message
4. **Optionally pushes** to remote repository
5. **Updates** last-commit timestamp

## Usage

```bash
# Quick save (local commit only)
/save-plugin

# Save and push to remote
/save-plugin --push

# Save with custom commit message
/save-plugin --message "Added new diagnostic agent"

# Save and push with custom message
/save-plugin --push --message "Completed Phase 2"
```

## Auto-Commit vs Manual Save

### Auto-Commit (Automatic)
- Triggers on SessionEnd hook
- Minimum 5-minute interval
- Generic commit message
- Never pushes to remote (safety)

### Manual Save (This Command)
- Triggers on demand
- No interval restriction
- Custom commit message supported
- Can push to remote with `--push`

## Commit Message Format

**Default format:**
```
🤖 Auto-commit: Plugin development checkpoint

Auto-committed at: 2026-01-30 15:30:00 UTC
Changed files: 12
Trigger: manual

Changes:
M       .claude-plugin/plugin.json
A       agents/diagnostics/plugin-diagnostician.md
A       commands/validate-plugin.md
...

---
This is an automatic commit to prevent data loss during plugin development.
Created by: scripts/hooks/auto-commit.sh
```

**Custom message format:**
```
Implemented validation system

Custom commit message provided by user.

Auto-committed at: 2026-01-30 15:30:00 UTC
Changed files: 12

---
Created via: /save-plugin command
```

## Configuration

Auto-commit settings in `config/auto-commit-config.json`:

```json
{
  "auto_commit": {
    "enabled": true,
    "min_interval_seconds": 300,
    "auto_push": false,
    "validation": {
      "run_before_commit": true,
      "block_on_critical_errors": false
    }
  }
}
```

## Safety Features

1. **Validation before commit** - Runs pre-commit-validator.sh
2. **Interval limiting** - Auto-commits limited to 1 per 5 minutes
3. **Never force-push** - Always uses standard push
4. **Preserves history** - Creates proper git commits (easy rollback)
5. **Warnings on errors** - Commits anyway but shows validation warnings

## Examples

### Example 1: Quick Save During Development

```bash
/save-plugin
```

Output:
```
🔍 Running pre-commit validation...
✅ Validation passed
✅ Auto-commit created: a1b2c3d
   Files committed: 8
💡 Run 'git push' to sync with remote (or set AUTO_PUSH=true)
```

### Example 2: Save and Push

```bash
/save-plugin --push
```

Output:
```
🔍 Running pre-commit validation...
✅ Validation passed
✅ Auto-commit created: d4e5f6g
   Files committed: 12
🔄 Auto-pushing to origin/master...
✅ Changes pushed to remote
```

### Example 3: Custom Message

```bash
/save-plugin --message "Completed self-improvement Phase 1 & 2"
```

Output:
```
✅ Auto-commit created: h7i8j9k
   Message: "Completed self-improvement Phase 1 & 2"
   Files committed: 15
```

## When to Use

**Use /save-plugin when:**
- ✅ After completing a feature or fix
- ✅ Before taking a break from development
- ✅ Before making major changes (create checkpoint)
- ✅ After successful validation
- ✅ When you want to push to remote immediately

**Auto-commit handles:**
- ⏰ End of session (automatic)
- ⏰ Periodic saves during long sessions
- ⏰ Background safety net

## Technical Details

**Implementation:**
- Executes `scripts/hooks/auto-commit.sh` with manual trigger flag
- Parses `--push` and `--message` options
- Sets environment variables for script configuration
- Returns user-friendly output

**Files Used:**
- `scripts/hooks/auto-commit.sh` - Auto-commit implementation
- `config/auto-commit-config.json` - Configuration
- `.last-auto-commit` - Timestamp tracking

## Implementation Instructions

When user runs `/save-plugin`:

```bash
# Parse options
PUSH_FLAG=false
CUSTOM_MESSAGE=""

if [[ "$@" =~ --push ]]; then
  PUSH_FLAG=true
fi

if [[ "$@" =~ --message ]]; then
  # Extract message after --message
  CUSTOM_MESSAGE="..." # parse from args
fi

# Execute auto-commit script
PLUGIN_DIR="$(pwd)/claude-skills/plugins/claude-skills-v2"
cd "$PLUGIN_DIR"

# Set environment variables
export AUTO_COMMIT_ENABLED=true
export AUTO_PUSH=$PUSH_FLAG
if [[ -n "$CUSTOM_MESSAGE" ]]; then
  export CUSTOM_COMMIT_MESSAGE="$CUSTOM_MESSAGE"
fi

# Run the auto-commit script
./scripts/hooks/auto-commit.sh
```

## Troubleshooting

**"No changes to commit"**
- All changes are already committed
- Check `git status`

**"Validation failed"**
- Script still commits (data safety priority)
- Run `/validate-plugin` to see errors
- Fix issues and commit again

**"Failed to push to remote"**
- Check network connection
- Verify GitHub authentication
- May need to pull remote changes first

## See Also

- `/validate-plugin` - Validate before saving
- `scripts/hooks/auto-commit.sh` - Auto-commit implementation
- `config/auto-commit-config.json` - Configuration options
