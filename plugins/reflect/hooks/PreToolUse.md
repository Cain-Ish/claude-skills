---
description: Pre-commit reflection hook - suggests skill improvement before commits
events:
  - PreToolUse
---

# Pre-Commit Reflection Hook

Before executing `git commit` commands, this hook checks if the user wants to capture session learnings via `/reflect`.

## When This Hook Triggers

This hook activates when:
1. The tool being used is `Bash`
2. The command contains `git commit` (but NOT `git commit --amend`)
3. Environment variable `SKIP_REFLECT_HOOK` is not set to `1`

## Hook Instructions for Claude

When the above conditions are met:

1. **Check if reflection is appropriate**: If the session involved:
   - Using a slash command or skill (like `/frontend-design`, `/code-reviewer`, etc.)
   - Multiple iterations and corrections
   - Learning new patterns or discovering edge cases

   Then reflection would be valuable.

2. **Proactively suggest reflection** by saying something like:

   "Before committing, would you like to reflect on this session to capture learnings? This helps improve skills for future sessions. You can run `/reflect` or `/reflect [skill-name]` now, or skip with 'n'."

3. **Wait for user response**:
   - If user says "yes" or runs `/reflect`: Execute the reflect workflow first, then proceed with commit
   - If user says "no" or "skip": Proceed with commit immediately
   - If user is silent: After 5 seconds of your message, proceed with commit (don't block their work)

4. **Don't interfere** if:
   - This is a `--amend` commit (corrections don't need reflection)
   - The session was trivial (simple file reads, one-line changes)
   - The user explicitly said "no" to reflection in the last hour

## Example Flow

```
User: Create a git commit with the changes

Claude: I'll commit your changes. Before I do, this session involved using the frontend-design skill with several iterations - would you like to reflect on what we learned? You can run /reflect frontend-design now, or just say 'n' to skip and commit immediately.

User: yes

Claude: [Runs /reflect frontend-design workflow...]
[After reflection completes]
Claude: Great, now committing your changes...
[Executes git commit]
```

## Configuration

Users control this hook via `/reflect` subcommands:
- `/reflect on` - Enable reflection suggestions (default)
- `/reflect off` - Disable reflection suggestions
- `/reflect status` - Check current status

Or set environment variable:
```bash
export SKIP_REFLECT_HOOK=1  # Completely disable this hook
```

## Notes

- This hook is **non-blocking** - it suggests but doesn't force reflection
- It's **context-aware** - only suggests when the session warrants it
- It **respects user time** - doesn't nag if they decline
- The state is tracked in `~/.claude/reflect-skill-state.json`
