---
description: End-of-session reflection hook - captures learnings when Claude stops
events:
  - Stop
---

# End-of-Session Reflection Hook

When the session ends (user runs `/stop` or session times out), this hook checks if learnings should be captured.

## When This Hook Triggers

This hook activates when:
1. The session is ending (Stop event)
2. Auto-reflect is enabled (via `/reflect on`)
3. The session lasted more than 5 minutes
4. The session involved meaningful work (not just simple queries)

## Hook Instructions for Claude

When the above conditions are met:

1. **Check if auto-reflect is enabled**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/reflect.sh status
   ```

   If output contains "Auto-reflect is enabled", proceed to step 2.
   If disabled, skip the rest of this hook.

2. **Evaluate session significance**:
   - Did the session involve using skills or complex commands?
   - Were there multiple iterations, corrections, or learnings?
   - Did patterns emerge that could improve future sessions?

   If yes to any of these, reflection would be valuable.

3. **Proactively suggest reflection**:

   "This session involved [brief summary]. Before ending, would you like to capture learnings to improve skills? Run `/reflect` or `/reflect [skill-name]` now."

4. **If user declines or doesn't respond**:
   - Save session summary to `~/.claude/reflect-queue.md` for later review
   - Don't block session end

## Example Flow

```
User: /stop

Claude: Before ending this session, I noticed we:
- Used /frontend-design to create new components
- Discovered a pattern with dark mode styling
- Iterated on the color scheme

Would you like to reflect on this to improve the frontend-design skill? [y/n]

User: y

Claude: [Runs /reflect frontend-design...]
[Completes reflection workflow]
Claude: Session learnings captured. Goodbye!
```

## Queued Reflections

If user doesn't respond or says "later", append to queue:

```markdown
# Reflection Queue

## Session 2026-01-12 14:30
- **Skills used**: frontend-design, code-reviewer
- **Learnings**: Dark mode styling patterns, component structure
- **Suggested improvements**: Add dark mode constraints to skill

---
```

User can process queue later with:
```bash
/reflect review-queue
```

## Configuration

Enable/disable via:
- `/reflect on` - Enable end-of-session reflection (this hook activates)
- `/reflect off` - Disable end-of-session reflection (this hook skips)

## Notes

- This hook is **optional and non-blocking**
- It only triggers for substantive sessions, not trivial ones
- Queued reflections prevent losing insights if user is busy
- The hook respects the auto-reflect setting in `~/.claude/reflect-skill-state.json`
