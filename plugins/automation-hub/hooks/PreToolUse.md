# PreToolUse Hook: Auto-Routing & Signal Tracking

You are processing a PreToolUse hook for the automation-hub plugin. This hook implements intelligent multi-agent routing and session signal tracking.

## Auto-Routing Logic (Two-Stage Decision Process)

### Stage 1: Fast Pre-Filter

**ONLY run Stage 1 if:**
- The user's prompt contains a request (not just a question)
- The tool about to be invoked is a code modification tool (Write, Edit, Bash with code changes)
- Auto-routing is enabled in config

**Execute:**
```bash
bash /path/to/plugins/automation-hub/scripts/stage1-prefilter.sh "${USER_PROMPT}" "${TOKEN_BUDGET}" "${TOOL_NAME}"
```

**Stage 1 Checks 5 Signals:**
1. Token budget >30K (suggests complex task)
2. Keyword density ≥3 domain words (architecture, security, testing, etc.)
3. Multi-domain detection ≥2 domains (frontend+backend, security+deployment, etc.)
4. Complexity words ≥2 (implement, migrate, comprehensive, system, etc.)
5. Prompt length >200 words (detailed requirements)

**Scoring:** Each signal adds to score (max 10). Threshold ≥4 proceeds to Stage 2.

**If Stage 1 returns "skip":** Do nothing, let the original tool call proceed.

**If Stage 1 returns "proceed":** Continue to Stage 2.

### Stage 2: Full Complexity Analysis

**Safety Checks Before Stage 2:**

1. **Rate Limiting:**
   ```bash
   bash /path/to/plugins/automation-hub/scripts/lib/common.sh check_rate_limit "auto_routing" 10 5
   ```
   - Max 10 per hour
   - Min 5 minutes between invocations
   - If rate limit exceeded: log decision and skip

2. **Circuit Breaker:**
   ```bash
   bash /path/to/plugins/automation-hub/scripts/lib/common.sh check_circuit_breaker "auto_routing" 3
   ```
   - If 3 consecutive failures: auto-disable feature and notify user
   - If circuit open: skip routing

**Invoke Multi-Agent Task Analyzer:**

Use the Task tool to invoke the `multi-agent:task-analyzer` agent:

```
Task tool parameters:
- subagent_type: "multi-agent:task-analyzer"
- description: "Analyze task complexity"
- prompt: "${USER_PROMPT}"
- model: "haiku" (fast and cost-effective for analysis)
```

**Parse Analysis Response:**

The agent returns:
- `complexity_score`: 0-100
- `recommended_pattern`: "single", "sequential", "parallel", "hierarchical"
- `estimated_tokens`: Token cost estimate
- `rationale`: Explanation of decision

**Store in session state:**
```bash
jq -n \
  --argjson score "${complexity_score}" \
  --arg pattern "${recommended_pattern}" \
  --argjson tokens "${estimated_tokens}" \
  '{
    task_analysis: {
      complexity_score: $score,
      recommended_pattern: $pattern,
      estimated_tokens: $tokens
    }
  }' > ~/.claude/automation-hub/session-state.json
```

**Apply Auto-Approval Logic:**

```bash
decision=$(bash /path/to/plugins/automation-hub/scripts/invoke-task-analyzer.sh "${USER_PROMPT}" "${TOKEN_BUDGET}")
```

Returns one of:
- `skip`: Complexity too low, let original tool proceed
- `suggest`: Present recommendation to user with AskUserQuestion
- `auto_approve`: Automatically invoke multi-agent coordination

**Handle Decision:**

1. **If "skip":** Do nothing, let original tool call proceed

2. **If "suggest":** Use AskUserQuestion tool to ask:
   ```
   Question: "This task appears complex (score: ${complexity_score}/100).
             Recommended approach: ${recommended_pattern} multi-agent coordination.
             Estimated cost: ${estimated_tokens} tokens.

             Would you like to use multi-agent orchestration?"

   Options:
   - "Yes, use multi-agent (Recommended)" → Invoke multi-agent:orchestrate
   - "No, proceed normally" → Let original tool proceed

   Log user's choice for learning system
   ```

3. **If "auto_approve":**
   - Invoke `multi-agent:orchestrate` agent directly
   - Log auto-approval for metrics
   - Notify user: "Auto-routing to multi-agent coordination (complexity: ${complexity_score})"

**Error Handling:**

- If task-analyzer fails: log failure, increment circuit breaker counter, let original tool proceed
- If rate limit exceeded: log decision, skip routing
- If circuit breaker open: show user message, skip routing

## Session Signal Tracking

Track signals for auto-reflection worthiness scoring:

**Signals to Track:**

1. **Corrections** (+10 each): User explicitly corrects Claude
   - Detect phrases: "actually", "no that's wrong", "fix that", "incorrect"
   - Increment: `.signals.corrections`

2. **Iterations** (+5 each): Multiple attempts at same task
   - Detect tool retry patterns (same tool, similar params within 5 minutes)
   - Increment: `.signals.iterations`

3. **Skill Usage** (+8 each): User invoked a skill
   - Detect Skill tool calls
   - Increment: `.signals.skill_usage`

4. **External Failures** (+12 each): Test/lint failures
   - Detect Bash tool failures with test/lint keywords
   - Increment: `.signals.external_failures`

5. **Edge Cases** (+6 each): Unanticipated questions or workarounds
   - Detect phrases: "edge case", "corner case", "didn't expect", "workaround"
   - Increment: `.signals.edge_cases`

6. **Token Count** (+1 per 1K tokens): Session length
   - Update: `.signals.token_count` with current total

**Update Session State:**

```bash
bash /path/to/plugins/automation-hub/scripts/track-session-signals.sh "${SIGNAL_TYPE}"
```

## Implementation Notes

- **Non-blocking:** This hook should complete quickly (<500ms for Stage 1, <5s for Stage 2)
- **Opt-out:** Respect `SKIP_AUTOMATION=1` environment variable
- **Debug mode:** If `AUTOMATION_DEBUG=1`, output detailed decision traces
- **Metrics:** Log all decisions to `~/.claude/automation-hub/metrics.jsonl`

## Configuration Check

Before running any automation, verify feature is enabled:

```bash
enabled=$(bash /path/to/plugins/automation-hub/scripts/lib/common.sh get_config_value ".auto_routing.enabled" "false")

if [[ "${enabled}" != "true" ]]; then
  exit 0  # Skip hook
fi
```

## Example Flow

```
User: "Build a comprehensive authentication system with JWT, OAuth, and 2FA"

Stage 1 Pre-Filter:
  ✓ Token budget: 45K tokens → YES
  ✓ Keywords: authentication, OAuth, JWT, system, comprehensive → 5 matches → YES
  ✓ Multi-domain: security + backend → 2 domains → YES
  ✓ Complexity words: build, comprehensive, system → 3 matches → YES
  ✓ Prompt length: 12 words → NO
  Score: 8/10 → PROCEED TO STAGE 2

Stage 2 Analysis:
  Invoke task-analyzer...
  Result: complexity=72, pattern=hierarchical, tokens=250K
  Band: very_complex
  Decision: suggest (always require approval for very complex)

Present to User:
  "This task appears very complex (score: 72/100).
   Recommended: hierarchical multi-agent coordination.
   Estimated: 250K tokens.
   Use multi-agent orchestration?"

User approves → Invoke multi-agent:orchestrate
Log approval for learning system
```
