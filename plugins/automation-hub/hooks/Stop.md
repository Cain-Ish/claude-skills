# Stop Hook: Auto-Cleanup & Auto-Reflection

You are processing a Stop hook for the automation-hub plugin. This hook runs when a Claude Code session ends, and implements:

1. **Auto-Cleanup Orchestration**: Safely cleanup orphaned processes
2. **Auto-Reflection Suggestion**: Suggest reflection based on session worthiness

## Auto-Cleanup Orchestration

### Check if Cleanup Should Run

**Only proceed if auto-cleanup is enabled:**

```bash
enabled=$(bash /path/to/plugins/automation-hub/scripts/lib/common.sh get_config_value ".auto_cleanup.enabled" "false")

if [[ "${enabled}" != "true" ]]; then
  # Skip cleanup, proceed to reflection check
fi
```

### Safety Checks

**Run safety checker script:**

```bash
safe=$(bash /path/to/plugins/automation-hub/scripts/check-cleanup-safe.sh)
```

**The safety checker verifies:**

1. **No uncommitted changes** (if required by config):
   ```bash
   git status --porcelain
   # If output non-empty and .auto_cleanup.safety_blockers.uncommitted_changes=true → UNSAFE
   ```

2. **No running dev processes**:
   - Check for: vite, webpack, jest --watch, npm run dev, MCP servers
   - If any found → UNSAFE

3. **No recent activity** (within last 2 minutes):
   - Check last tool call timestamp
   - If < 2 minutes ago → UNSAFE

4. **Session limit not exceeded**:
   - Check if cleanup already ran this session
   - If max_cleanups_per_session exceeded → UNSAFE

**If safety check returns "unsafe":**

- Log decision: "Cleanup skipped due to safety blocker: ${reason}"
- Do NOT invoke process-janitor
- Proceed to reflection check

**If safety check returns "safe":**

- Proceed with cleanup

### Invoke Process-Janitor Cleanup

**Run cleanup script:**

```bash
bash /path/to/plugins/process-janitor/scripts/cleanup.sh
```

**Log cleanup action:**

```bash
bash /path/to/plugins/automation-hub/scripts/lib/common.sh log_decision \
  "auto_cleanup" \
  "executed" \
  "Session end cleanup triggered" \
  '{}'
```

**Increment session counter:**

```bash
bash /path/to/plugins/automation-hub/scripts/lib/common.sh increment_session_counter \
  ".actions.auto_cleanup_count"
```

**Output to user (non-blocking):**

```
🧹 Auto-cleanup completed: [X] processes stopped
```

## Auto-Reflection Suggestion

### Check if Reflection Should Run

**Only proceed if auto-reflect is enabled:**

```bash
enabled=$(bash /path/to/plugins/automation-hub/scripts/lib/common.sh get_config_value ".auto_reflect.enabled" "false")

if [[ "${enabled}" != "true" ]]; then
  exit 0
fi
```

### Calculate Reflection Worthiness Score

**Run scoring script:**

```bash
score=$(bash /path/to/plugins/automation-hub/scripts/calculate-reflection-score.sh)
```

**The scoring script:**

1. Loads session signals from `~/.claude/automation-hub/session-state.json`
2. Calculates weighted score:
   - corrections × 10
   - iterations × 5
   - skill_usage × 8
   - external_failures × 12
   - edge_cases × 6
   - token_count ÷ 1000 × 1

3. Returns total score

**Get threshold:**

```bash
threshold=$(bash /path/to/plugins/automation-hub/scripts/lib/common.sh get_config_value ".auto_reflect.worthiness_threshold" "20")
```

**If score < threshold:**

- Log decision: "Reflection skipped: score ${score} < threshold ${threshold}"
- Exit (no suggestion)

**If score ≥ threshold:**

- Proceed with suggestion

### Check Session Limit

**Verify max 1 suggestion per session:**

```bash
count=$(bash /path/to/plugins/automation-hub/scripts/lib/common.sh get_session_state_value ".actions.auto_reflect_count" "0")

max=$(bash /path/to/plugins/automation-hub/scripts/lib/common.sh get_config_value ".auto_reflect.max_suggestions_per_session" "1")

if [[ ${count} -ge ${max} ]]; then
  # Already suggested this session, skip
  exit 0
fi
```

### Suggest Reflection

**Check mode:**

```bash
suggest_only=$(bash /path/to/plugins/automation-hub/scripts/lib/common.sh get_config_value ".auto_reflect.suggest_only" "true")
auto_execute=$(bash /path/to/plugins/automation-hub/scripts/lib/common.sh get_config_value ".auto_reflect.auto_execute" "false")
```

**Mode: suggest_only (default)**

Present non-blocking suggestion with 10-second timeout:

```
💡 Reflection Suggested (worthiness: ${score}/20)

This session showed patterns worth capturing:
- ${corrections} corrections made
- ${skill_usage} skills used
- ${external_failures} test/lint failures
- ${iterations} iterations attempted

Run /reflect to capture learnings and improve skills?

[Continue without reflecting in 10 seconds...]
```

**If user doesn't respond within 10 seconds:**

- Session ends normally
- Log decision: "Reflection suggested but timed out"

**If user responds "yes" or invokes /reflect:**

- Invoke reflect:reflect skill
- Log decision: "Reflection accepted by user"

**Mode: auto_execute**

Automatically invoke reflect skill:

```bash
# Invoke reflect skill directly
/reflect
```

Output to user:

```
💡 Auto-reflection triggered (worthiness: ${score}/20)
Analyzing session to propose skill improvements...
```

### Log Metrics

```bash
bash /path/to/plugins/automation-hub/scripts/lib/common.sh log_decision \
  "auto_reflect" \
  "suggested" \
  "Worthiness score ${score} ≥ threshold ${threshold}" \
  "{\"score\": ${score}, \"signals\": {...}}"
```

**Increment counter:**

```bash
bash /path/to/plugins/automation-hub/scripts/lib/common.sh increment_session_counter \
  ".actions.auto_reflect_count"
```

## Cleanup Session State

**After all Stop hook logic completes:**

```bash
bash /path/to/plugins/automation-hub/scripts/lib/common.sh clear_session_state
```

This resets signal counters for the next session.

## Error Handling

- **Cleanup failures**: Log error, continue to reflection check (don't block session end)
- **Reflection script failures**: Log error, exit gracefully (don't block session end)
- **Timeout on user response**: Session ends normally after timeout

## Implementation Notes

- **Non-blocking**: Session should end within 15 seconds regardless of hook execution
- **Graceful degradation**: If any script fails, log and continue (never block session end)
- **Timeout**: Reflection suggestion times out after 10 seconds
- **One-time**: Stop hook runs exactly once per session

## Example Flows

### Flow 1: Safe Cleanup + High Worthiness

```
Session ending...

Stop Hook:
  ✓ Auto-cleanup enabled
  ✓ Safety check: SAFE (no uncommitted changes, no dev processes)
  → Invoking process-janitor cleanup...
  → Cleanup: 3 processes stopped

  ✓ Auto-reflect enabled
  → Calculate worthiness: 28 points
  → Threshold: 20 points → SUGGEST

User sees:
  🧹 Auto-cleanup completed: 3 processes stopped

  💡 Reflection Suggested (worthiness: 28/20)
  This session showed patterns worth capturing:
  - 2 corrections made
  - 1 skill used
  - 1 test failure
  - 3 iterations attempted

  Run /reflect to capture learnings?
  [Continue without reflecting in 10 seconds...]

User: (no response, timeout)
→ Session ends normally
```

### Flow 2: Unsafe Cleanup + Low Worthiness

```
Session ending...

Stop Hook:
  ✓ Auto-cleanup enabled
  ✗ Safety check: UNSAFE (uncommitted changes detected)
  → Skip cleanup

  ✓ Auto-reflect enabled
  → Calculate worthiness: 12 points
  → Threshold: 20 points → SKIP

→ Session ends immediately
```

### Flow 3: Auto-Execute Mode

```
Session ending...

Stop Hook:
  (cleanup logic...)

  ✓ Auto-reflect enabled (auto-execute mode)
  → Calculate worthiness: 35 points
  → Threshold: 20 points → AUTO-EXECUTE

User sees:
  💡 Auto-reflection triggered (worthiness: 35/20)
  Analyzing session to propose skill improvements...

  (Reflect skill runs automatically)

→ Session ends after reflection completes
```
