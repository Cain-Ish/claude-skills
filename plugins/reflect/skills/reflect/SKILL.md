---
name: reflect
description: Analyze the current session and propose improvements to skills. Run after using a skill to capture learnings. Use when user says "reflect", "improve skill", "learn from this", or at end of skill-heavy sessions.
---

# Reflect Skill

Analyze the current session and propose improvements to skills based on what worked, what didn't, and edge cases discovered.

## Trigger

Run `/reflect` or `/reflect [skill-name]` after a session where you used a skill.

Additional commands:
- `/reflect on` - Enable automatic end-of-session reflection
- `/reflect off` - Disable automatic reflection
- `/reflect status` - Check if auto-reflect is enabled

## Workflow

### Step 0: Check if Skill is Paused

**IMPORTANT**: Before proceeding, check if the skill has been auto-paused due to consecutive rejections.

Check for pause file:
```bash
PAUSED_FILE="${HOME}/.claude/reflect-paused-skills/[skill-name].paused"
```

If the file exists:
1. Read the pause reason and timestamp
2. Inform the user:
   ```
   ⚠️  Skill '[skill-name]' is currently paused

   Paused at: [timestamp]
   Reason: [reason]

   This skill was auto-paused after 3+ consecutive rejections.

   To resume: /reflect resume [skill-name]
   To see stats: /reflect stats [skill-name]
   ```
3. **Stop the reflection workflow** - do not proceed to Step 1

If the file does not exist, continue to Step 1.

---

### Step 1: Identify the Skill & Load Memories

**A. Identify skill:**

If skill name not provided, ask:

```
Which skill should I analyze this session for?
- frontend-design
- code-reviewer
- [other]
```

**B. Load relevant memories:**

Before analyzing the conversation, load accumulated learnings from the memories directory.

**Read cross-skill patterns:**
```bash
PATTERNS_FILE="${HOME}/.claude/memories/skill-patterns.md"
if [ -f "$PATTERNS_FILE" ]; then
    cat "$PATTERNS_FILE"
fi
```

**Read skill-specific preferences:**
```bash
PREFS_FILE="${HOME}/.claude/memories/${SKILL_NAME}-prefs.md"
if [ -f "$PREFS_FILE" ]; then
    cat "$PREFS_FILE"
fi
```

**For reflect skill itself, read meta-learnings:**
```bash
if [ "$SKILL_NAME" = "reflect" ]; then
    META_FILE="${HOME}/.claude/memories/reflect-meta.md"
    if [ -f "$META_FILE" ]; then
        cat "$META_FILE"
    fi
fi
```

These memories inform:
- What patterns to look for in the conversation
- Known user preferences to validate against
- Historical issues that were previously addressed
- Cross-skill patterns that apply to this skill

### Step 2: Analyze the Conversation & External Feedback

**IMPORTANT: Check for external feedback FIRST** - this provides objective evidence:

```bash
# Check for captured external feedback
FEEDBACK_FILE="${HOME}/.claude/reflect-external-feedback/latest-feedback.jsonl"

if [ -f "$FEEDBACK_FILE" ] && grep -q "\"skill\":\"$SKILL_NAME\"" "$FEEDBACK_FILE"; then
    # External feedback exists for this skill
    echo "Found external feedback (test/lint errors)"

    # Extract and display feedback
    grep "\"skill\":\"$SKILL_NAME\"" "$FEEDBACK_FILE"
fi
```

**External Feedback** (HIGH confidence):
- Test failures (pytest, jest, etc.)
- Lint errors (ruff, eslint, mypy)
- Build failures
- Type errors

These are **objective signals** - prioritize them over conversation signals.

---

**Then analyze conversation signals:**

**For large conversations (>10k tokens)**, first compress context:

Use the Task tool to invoke `context-manager` agent:
```
Task: Extract reflect-relevant signals from conversation
Agent: context-manager
Prompt: "Extract only these types of interactions from the conversation:
- User corrections (explicit rejections, requests to change)
- User successes (approvals, positive feedback)
- Edge cases (unexpected questions, workarounds)
- Repeated user preferences
Focus on the skill: [skill-name]. Remove all other content."
```

📖 **Compression strategy & templates**: See `references/context-compression.md`

Then analyze the compressed output (or full conversation if small) for signals. **Count them**:

**Corrections** (HIGH): User said "no", explicitly corrected, asked for immediate changes
**Successes** (MED): User said "perfect"/"great", accepted output, built on it
**Edge Cases** (MED): Unanticipated questions, workarounds needed, features not covered
**Preferences** (LOW): Repeated patterns across sessions

📖 **Detailed examples**: See `references/signal-examples.md` (includes external feedback)

Count each signal type - numbers will be logged to metrics for self-improvement tracking.

### Step 3: Generate and Validate Proposal

#### Step 3A: Draft Initial Proposal

Use simplified format:

```
Skill Reflection: [skill-name]

Signals: X corrections, Y successes, Z edge cases

Proposed changes:
🔴 HIGH: [action] - "[description]"
🟡 MED:  [action] - "[description]"
🔵 LOW:  [action] - "[description]"

Commit: "[skill]: [summary]"
```

**Confidence levels**: HIGH=explicit corrections, MED=strong patterns, LOW=weak signals
**Actions**: Add constraint, Add preference, Update guideline, Clarify ambiguity

📖 **Templates & guidelines**: See `references/proposal-templates.md`

---

#### Step 3B: Validate with Critic Agent

**IMPORTANT**: Before presenting to user, validate the proposal using the reflect-critic agent.

Use the Task tool to invoke the critic:

```
Task tool:
  subagent_type: "reflect-critic"
  description: "Validate reflect proposal"
  prompt: "
    Please validate this reflect proposal:

    Skill: [skill-name]
    Signals: X corrections, Y successes, Z edge cases

    Proposed Changes:
    [paste your drafted proposal here]

    Validate against:
    1. 12-factor agent principles
    2. Signal-to-proposal alignment
    3. Implementation feasibility

    Provide score (0-100) and recommendation (APPROVE/REVISE/REJECT).
  "
```

The critic will return:
- **Score**: 0-100 (quality assessment)
- **Recommendation**: APPROVE | APPROVE with suggestions | REVISE | REJECT
- **Detailed feedback**: Strengths, concerns, specific improvements

**Decision tree based on critic score:**

- **90-100 (Excellent)**: Proceed to Step 3C with proposal as-is
- **70-89 (Good)**: Incorporate critic's suggestions, then proceed to Step 3C
- **50-69 (Needs work)**: Revise proposal based on critic feedback, re-validate
- **0-49 (Poor)**: Reject proposal, consider alternative approach or gather more signals

📖 **Critic validation details**: See `agents/reflect-critic.md`

---

#### Step 3C: Present Final Proposal

After validation (and any revisions), present to user:

```
Skill Reflection: [skill-name]

Signals: X corrections, Y successes, Z edge cases

Proposed changes:
🔴 HIGH: [action] - "[description]"
🟡 MED:  [action] - "[description]"
🔵 LOW:  [action] - "[description]"

Commit: "[skill]: [summary]"

Critic Score: X/100 ([Excellent|Good|Needs work])
Critic Recommendation: [key points from critic]

Apply? [Y/n] or describe tweaks
```

**Include critic score and key insights** to help user make informed decision.

### Step 4: If Approved

1. **Log metrics**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/reflect-track-proposal.sh \
     [skill] approved --corrections X --successes Y --edge-cases Z
   ```

2. **Write to memories** (not SKILL.md):

   **For cross-skill patterns:**
   If the learning applies to multiple skills (e.g., accessibility, type safety, testing):
   ```bash
   # Append to ~/.claude/memories/skill-patterns.md
   PATTERNS_FILE="${HOME}/.claude/memories/skill-patterns.md"

   cat >> "$PATTERNS_FILE" <<EOF

   ---

   ## Pattern Name (Added: $(date +%Y-%m-%d))

   **Pattern**: Brief description

   **Applies to**: skill1, skill2, skill3

   **Evidence**:
   - Specific examples or data
   - Session IDs if relevant

   **Implementation**:
   - Concrete guidance
   - Code examples if applicable
   EOF
   ```

   **For skill-specific preferences:**
   If the learning applies to a single skill:
   ```bash
   # Append to ~/.claude/memories/{skill-name}-prefs.md
   PREFS_FILE="${HOME}/.claude/memories/${SKILL_NAME}-prefs.md"

   # Create file if it doesn't exist
   if [ ! -f "$PREFS_FILE" ]; then
       cat > "$PREFS_FILE" <<EOF
   # ${SKILL_NAME^} Preferences

   User preferences and learnings specific to the ${SKILL_NAME} skill.

   Last updated: $(date +%Y-%m-%d)

   ---
   EOF
   fi

   cat >> "$PREFS_FILE" <<EOF

   ## Preference Topic (Added: $(date +%Y-%m-%d))

   **Preference**: Description

   **Source**: [User correction/External feedback/Edge case/Success]

   **Evidence**: What happened

   **Implementation**:
   - How to apply this preference
   EOF
   ```

   **For reflect meta-learnings:**
   If improving reflect itself:
   ```bash
   # Append to ~/.claude/memories/reflect-meta.md
   META_FILE="${HOME}/.claude/memories/reflect-meta.md"

   cat >> "$META_FILE" <<EOF

   ## Learning Topic (Added: $(date +%Y-%m-%d))

   **Learning**: What was learned

   **Evidence**:
   - Data or research supporting this
   - Metrics or user feedback

   **Application**:
   - How this changes reflect's behavior
   EOF
   ```

   **Update last modified timestamp:**
   ```bash
   # Update "Last updated" line in the file
   sed -i.bak "s/Last updated: .*/Last updated: $(date +%Y-%m-%d)/" "$MEMORY_FILE"
   rm -f "$MEMORY_FILE.bak"
   ```

3. **Only modify SKILL.md for structural changes:**

   Only edit the actual SKILL.md file if:
   - Adding a new workflow step
   - Changing core instructions
   - Fixing bugs in the skill itself

   For accumulated learnings and preferences, use memories instead.

4. **Commit & push** using helper script:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/reflect-commit-changes.sh \
     [skill] "[summary]"
   ```

   Or manually: See `references/git-workflow.md`

5. Confirm: "Memory updated and pushed to remote"

### Step 5: If Declined

1. **Log metrics**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/reflect-track-proposal.sh \
     [skill] rejected --corrections X --successes Y --edge-cases Z
   ```

2. Optionally save observations to `${CLAUDE_PLUGIN_ROOT}/skills/[skill]/OBSERVATIONS.md`

## Toggle Commands

### `/reflect on`

Enable automatic end-of-session reflection:
1. Create/update `~/.claude/reflect-skill-state.json` with `{"enabled": true, "updatedAt": "[timestamp]"}`
2. Confirm: "Auto-reflect enabled. Sessions will be analyzed automatically when you stop."

### `/reflect off`

Disable automatic reflection:
1. Update `~/.claude/reflect-skill-state.json` with `{"enabled": false, "updatedAt": "[timestamp]"}`
2. Confirm: "Auto-reflect disabled. Use /reflect manually to analyze sessions."

### `/reflect status`

Check current status:
1. Read `~/.claude/reflect-skill-state.json`
2. Report: "Auto-reflect is [enabled/disabled]" with last updated timestamp

**Note:** The state file is saved in the global Claude user directory (`~/.claude/`) so it persists across plugin upgrades.

## Example

```
Skill Reflection: frontend-design
Signals: 2 corrections, 3 successes

Proposed changes:
🔴 HIGH: Add constraint - "Never use gradients unless requested"
🔴 HIGH: Update guideline - "Dark backgrounds: use #000 not #1a1a1a"
🟡 MED: Add preference - "Prefer CSS Grid for card layouts"

Commit: "frontend-design: no gradients, #000 dark, prefer Grid"
Apply? [Y/n]
```

## Metrics & Self-Improvement

Reflect tracks effectiveness via `~/.claude/reflect-metrics.jsonl`:
- **Proposal events**: Logged when user approves/rejects changes
- **Outcome events**: Track if improvements actually helped (future sessions)
- **Meta-improvement**: `/reflect reflect` will analyze metrics and improve itself

Scripts: `reflect-track-proposal.sh`, `reflect-track-outcome.sh`

## Git Workflow

Use the helper script to commit changes:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/reflect-commit-changes.sh [skill] "[summary]"
```

📖 **Manual workflow**: See `references/git-workflow.md`

## Important Notes

- Always show the exact changes before applying
- Never modify skills without explicit user approval
- Commit messages should be concise and descriptive
- Push only after successful commit