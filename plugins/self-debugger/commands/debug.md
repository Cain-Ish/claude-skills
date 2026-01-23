---
name: debug
description: View detected plugin issues and apply fixes
usage: |
  /debug                Show status and recent issues
  /debug scan          Force immediate scan
  /debug fix [id]      Generate and apply fix for issue
args:
  - name: subcommand
    description: Action to perform (scan, fix, or empty for status)
    required: false
  - name: issue_id
    description: Issue ID to fix (required for 'fix' subcommand)
    required: false
---

# Self-Debugger: Debug Command

View detected plugin issues and apply fixes.

When you execute this command, analyze the subcommand and perform the appropriate action:

## Subcommand: Status (no arguments)

If no arguments provided, show status:

1. Check background monitor status (PID file in `~/.claude/self-debugger/sessions/$CLAUDE_SESSION_ID/monitor.pid`)
2. Count total issues and pending issues from `~/.claude/self-debugger/findings/issues.jsonl`
3. Display last 10 issues with:
   - Short issue ID (first 8 chars)
   - Severity level
   - Plugin/component path
   - Error message

**Example output**:
```
## Self-Debugger Status

✅ Background monitor: Running (PID: 12345)

## Issues Found: 3 total, 3 pending

### Recent Issues:
- [0035139a] ERROR: test-plugin/.claude-plugin/plugin.json - plugin.json must have 'version' field
- [6ec71b51] ERROR: test-plugin/.claude-plugin/plugin.json - plugin.json must have 'author.name' field
- [33a0b78f] ERROR: test-plugin/.claude-plugin/plugin.json - plugin.json must have 'license' field

---
Use `/debug fix [issue-id]` to generate and apply a fix
Use `/debug scan` to force immediate scan
```

## Subcommand: Scan

If first argument is "scan", force immediate scan:

1. Execute `${CLAUDE_PLUGIN_ROOT}/scripts/scan-plugins.sh`
2. Report scan results
3. Direct user to `/debug` to view issues

## Subcommand: Fix [issue-id]

If first argument is "fix" and issue-id provided:

**Phase 3 Workflow** (agents available):

1. **Load issue** from findings file
2. **Invoke debugger-fixer agent** via Task tool:
   ```
   Use Task tool with:
   - subagent_type: "debugger-fixer"
   - prompt: "Generate fix for issue ID: [issue-id]"
   - description: "Generate fix proposal"
   ```

3. **Invoke debugger-critic agent** via Task tool:
   ```
   Use Task tool with:
   - subagent_type: "debugger-critic"
   - prompt: "Validate fix proposal: [fix-json]"
   - description: "Validate fix quality"
   ```

4. **Check critic score**:
   - Score < 70: Reject, show feedback, ask if user wants to retry
   - Score >= 70: Proceed to apply

5. **Show fix proposal** to user:
   - Display diff
   - Show description
   - Show critic score and feedback
   - Ask: "Apply this fix? (yes/no/dry-run)"

6. **Apply fix** if approved:
   - If "dry-run": Execute apply-fix.sh with DRY_RUN=true
   - If "yes": Execute apply-fix.sh to create branch, commit, push
   - If "no": Abort

7. **Report results**:
   - Branch created
   - Commit hash
   - MR link (if available)
   - Next steps for human review

**Current Placeholder** (agents not yet integrated):

```bash
echo "Fix generation requires debugger-fixer and debugger-critic agents"
echo
echo "Workflow:"
echo "  1. Load issue: [issue-id]"
echo "  2. Invoke debugger-fixer agent (generates fix from rule template)"
echo "  3. Invoke debugger-critic agent (scores 0-100, min 70 to apply)"
echo "  4. Show fix diff and ask for approval"
echo "  5. Create feature branch: debug/[plugin]/[issue-short]"
echo "  6. Apply fix and commit with session tracking"
echo "  7. Push to origin for MR review"
echo
echo "To test the workflow manually:"
echo "  1. ${CLAUDE_PLUGIN_ROOT}/scripts/generate-fix.sh [issue-id]"
echo "  2. Review fix proposal JSON"
echo "  3. ${CLAUDE_PLUGIN_ROOT}/scripts/apply-fix.sh [issue-id] [fix.json]"
```

## Implementation Notes

**When agents are available**, integrate Task tool invocations:

```typescript
// Example pseudo-code for fix workflow
async function generateAndApplyFix(issueId: string) {
  // Step 1: Generate fix
  const fixProposal = await invokAgent({
    type: "debugger-fixer",
    prompt: `Generate fix for issue: ${issueId}`,
  });

  // Step 2: Validate fix
  const validation = await invokeAgent({
    type: "debugger-critic",
    prompt: `Validate fix: ${JSON.stringify(fixProposal)}`,
  });

  // Step 3: Check score
  if (validation.score < 70) {
    return { error: "Fix quality too low", feedback: validation.feedback };
  }

  // Step 4: Ask user approval
  const approved = await askUser(`Apply fix? Score: ${validation.score}`);

  // Step 5: Apply if approved
  if (approved) {
    await applyFix(issueId, fixProposal);
  }
}
```

## Error Handling

- **Issue not found**: Show error, list available issues
- **Critic rejects**: Show feedback, ask if user wants manual intervention
- **Git conflicts**: Show conflict, recommend manual resolution
- **No source repo**: Error - must be in claude-skills repository

## Examples

```bash
# Check status
/debug

# Force scan
/debug scan

# Generate and apply fix
/debug fix 0035139a

# Dry-run mode (show diff without applying)
/debug fix 0035139a
# Then select "dry-run" when prompted
```
