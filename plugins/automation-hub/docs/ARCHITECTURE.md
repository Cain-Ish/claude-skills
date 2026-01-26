# Automation Hub - Architecture Design

## System Overview

The Automation Hub is a **meta-orchestration layer** that sits above existing plugins and makes intelligent decisions about when to invoke them automatically, based on context signals and learned user preferences.

## Core Principle: Event-Driven Automation

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  User Prompt │────▶│ PreToolUse   │────▶│   Tool       │
│              │     │    Hook      │     │  Execution   │
└──────────────┘     └──────┬───────┘     └──────────────┘
                            │
                            ▼
                     ┌──────────────┐
                     │  Auto-Route  │
                     │  Decision    │
                     └──────────────┘
```

Hooks intercept execution at strategic points:
- **PreToolUse**: Before any tool executes → routing decisions
- **Stop**: When session ends → cleanup & reflection

## Auto-Routing Architecture

### Two-Stage Decision Pipeline

```
User Prompt
    │
    ▼
┌─────────────────────────────────────┐
│     Stage 1: Fast Pre-Filter        │
│  (<100ms, <100 tokens overhead)     │
│                                     │
│  5 Signals:                         │
│  • Token budget >30K                │
│  • Keyword density ≥3               │
│  • Multi-domain ≥2                  │
│  • Complexity words ≥2              │
│  • Prompt length >200 words         │
│                                     │
│  Score: 0-10                        │
└──────────┬──────────────────────────┘
           │
    ┌──────┴──────┐
    │ Score < 4?  │
    └──────┬──────┘
           │
    Yes    │    No
    │      │      │
    ▼      │      ▼
  Skip     │   ┌─────────────────────────────────────┐
  (90%     │   │  Stage 2: Full Complexity Analysis  │
  of       │   │   (Invoke task-analyzer agent)      │
  prompts) │   │                                     │
           │   │  Returns:                           │
           │   │  • Complexity: 0-100                │
           │   │  • Pattern: single/parallel/etc     │
           │   │  • Estimated tokens                 │
           │   └──────────┬──────────────────────────┘
           │              │
           │              ▼
           │        ┌────────────────┐
           │        │  Auto-Approval │
           │        │  Decision Tree │
           │        └────────┬───────┘
           │                 │
           │        ┌────────┴─────────────────┐
           │        │                          │
           ▼        ▼                          ▼
      ┌────────┐ ┌──────┐                 ┌─────────┐
      │  Skip  │ │ Suggest│               │ Auto-   │
      │ (Low)  │ │ (Med) │               │ Approve │
      └────────┘ └───┬───┘               └────┬────┘
                     │                          │
                     ▼                          ▼
              Ask User Question         Invoke Multi-Agent
                     │                   Automatically
                     │
                     ├─► User Approves ──► Log for Learning
                     │
                     └─► User Rejects ──► Log for Learning
```

### Auto-Approval Logic

```
Complexity Score → Complexity Band → Decision

0-29     → Simple        → Skip (not worth multi-agent)
30-49    → Moderate      → Auto-approve if approval_rate ≥70% AND samples ≥10
50-69    → Complex       → Auto-approve if token_budget OK AND approval_rate ≥70%
70-100   → Very Complex  → Always suggest (never auto-approve)
```

### Learning Feedback Loop

```
User Decision (Approve/Reject)
         │
         ▼
   Log to Metrics
         │
         ▼
Calculate Approval Rate by Band
         │
         ▼
Update Auto-Approval Thresholds
         │
         ▼
Future Prompts Use New Thresholds
```

## Auto-Cleanup Architecture

### Safety-First Design

```
Session End (Stop Hook)
    │
    ▼
┌───────────────────────┐
│  Check Feature       │
│  Enabled?            │
└──────┬────────────────┘
       │
       ▼
┌───────────────────────┐
│  Safety Checks:       │
│                       │
│  1. Git Status        │──► Uncommitted? ──► UNSAFE
│  2. Dev Processes     │──► Running?     ──► UNSAFE
│  3. Recent Activity   │──► <2 min?      ──► UNSAFE
│  4. Session Limit     │──► Already ran? ──► UNSAFE
└──────┬────────────────┘
       │
       │ All SAFE
       ▼
┌───────────────────────┐
│  Invoke Process       │
│  Janitor Cleanup      │
└───────────────────────┘
       │
       ▼
┌───────────────────────┐
│  Log Metrics          │
│  Increment Counter    │
└───────────────────────┘
```

### Safety Blockers (Any One Blocks Cleanup)

1. **Git Safety**: Uncommitted changes or untracked files
2. **Process Safety**: Running dev servers (vite, webpack, jest --watch, MCP servers)
3. **Timing Safety**: Tool call within last 2 minutes
4. **Rate Safety**: Cleanup already ran this session (max 1 per session)

## Auto-Reflection Architecture

### Signal Accumulation System

```
During Session:
    │
    User Correction ──────────► Track: corrections++
    │
    Multiple Attempts ────────► Track: iterations++
    │
    Skill Invoked ────────────► Track: skill_usage++
    │
    Test/Lint Failure ────────► Track: external_failures++
    │
    Edge Case Encountered ────► Track: edge_cases++
    │
    Token Usage ──────────────► Track: token_count
    │
    ▼
Session End (Stop Hook)
    │
    ▼
┌────────────────────────────────────┐
│  Calculate Worthiness Score:       │
│                                    │
│  score = corrections × 10          │
│        + iterations × 5            │
│        + skill_usage × 8           │
│        + external_failures × 12    │
│        + edge_cases × 6            │
│        + (token_count / 1000) × 1  │
└───────────┬────────────────────────┘
            │
            ▼
     ┌──────────────┐
     │ Score ≥ 20?  │
     └──────┬───────┘
            │
       No   │   Yes
       │    │    │
       ▼    │    ▼
     Skip   │  ┌────────────────────────┐
            │  │  Suggest Reflection     │
            │  │  (10 sec timeout)       │
            │  └──────┬─────────────────┘
            │         │
            │    ┌────┴────┐
            │    │         │
            ▼    ▼         ▼
          User   User     Timeout
          Accepts Ignores
            │      │        │
            ▼      ▼        ▼
      Run /reflect  Skip   Skip
```

### Signal Weight Rationale

- **External Failures (12)**: Highest weight - objective evidence of issues
- **Corrections (10)**: High weight - user explicitly corrected Claude
- **Skill Usage (8)**: Medium-high - user invoked specialized behavior
- **Edge Cases (6)**: Medium - unanticipated scenarios worth capturing
- **Iterations (5)**: Medium - multiple attempts suggest complexity
- **Token Count (1 per 1K)**: Low - session length is weak signal alone

## Configuration & Observability

### Configuration Layer

```
┌────────────────────────────────────┐
│  default-config.json (Plugin)      │
│  - Shipped defaults                │
└────────────────┬───────────────────┘
                 │ Copy on first run
                 ▼
┌────────────────────────────────────┐
│  ~/.claude/automation-hub/         │
│  config.json (User)                │
│  - User customizations             │
│  - Learning adjustments            │
└────────────────┬───────────────────┘
                 │ Read on every hook
                 ▼
         ┌───────────────┐
         │  Hook Logic   │
         └───────────────┘
```

### Metrics Pipeline

```
Hook Execution
    │
    ▼
┌────────────────────────────────────┐
│  Log Decision:                     │
│  {                                 │
│    timestamp: "2026-01-25T...",   │
│    session_id: "...",             │
│    event_type: "decision",        │
│    data: {                        │
│      feature: "auto_routing",    │
│      decision: "auto_approve",   │
│      reason: "...",              │
│      metadata: {...}             │
│    }                              │
│  }                                │
└────────────────┬───────────────────┘
                 │ Append JSONL
                 ▼
┌────────────────────────────────────┐
│  ~/.claude/automation-hub/         │
│  metrics.jsonl                     │
│  - One JSON object per line        │
│  - 90 day retention                │
└────────────────┬───────────────────┘
                 │ Consumed by
                 ▼
         ┌───────────────┐
         │  /automation  │
         │  status/debug │
         └───────────────┘
                 │ Consumed by (Phase 5)
                 ▼
         ┌───────────────┐
         │  Learning     │
         │  Coordinator  │
         └───────────────┘
```

### Debug Mode Flow

```
export AUTOMATION_DEBUG=1
    │
    ▼
Hook Execution
    │
    ▼
┌────────────────────────────────────┐
│  Debug Output to stderr:           │
│                                    │
│  [AUTO-DEBUG] PreToolUse: ...      │
│  [AUTO-DEBUG]   - Signal: YES      │
│  [AUTO-DEBUG]   - Score: 6/10      │
│  [AUTO-DEBUG]   - Decision: ...    │
└────────────────────────────────────┘
    │
    ▼
User Sees Real-Time Trace
```

## Safety Mechanisms

### Rate Limiting

```
Hook Invocation
    │
    ▼
┌────────────────────────────────────┐
│  Check Metrics:                    │
│  - Count events in last hour       │
│  - Check time since last event     │
└────────────────┬───────────────────┘
                 │
        ┌────────┴─────────┐
        │                  │
        ▼                  ▼
    Within Limits      Exceeded
        │                  │
        │                  ▼
        │          ┌───────────────┐
        │          │  Log Decision │
        │          │  Skip Action  │
        │          └───────────────┘
        │
        ▼
   Proceed
```

**Limits:**
- Auto-routing: 10/hour, min 5 min between
- Auto-cleanup: 1/session
- Auto-reflect: 1/session
- Auto-fix: 5/session

### Circuit Breaker

```
Consecutive Failures
    │
    ▼
┌────────────────────────────────────┐
│  Track Last N Decisions:           │
│  [failure, failure, failure]       │
└────────────────┬───────────────────┘
                 │
        ┌────────┴─────────┐
        │                  │
        ▼                  ▼
    Count < 3          Count ≥ 3
        │                  │
        │                  ▼
        │          ┌───────────────────┐
        │          │  TRIP BREAKER     │
        │          │  - Disable feature│
        │          │  - Update config  │
        │          │  - Notify user    │
        │          └───────────────────┘
        │
        ▼
   Normal Operation
```

**Auto-Reset:** After 60 minutes of no attempts

## Data Flow

### Session Lifecycle

```
Session Start
    │
    ▼
Initialize State
~/.claude/automation-hub/session-state.json
{
  "session_id": "...",
  "started_at": "...",
  "signals": {
    "corrections": 0,
    "iterations": 0,
    ...
  },
  "actions": {
    "auto_routing_count": 0,
    "auto_cleanup_count": 0,
    ...
  }
}
    │
    ▼
┌────────────────────────┐
│  User Interactions     │
│  (Tool Calls)          │
└────────┬───────────────┘
         │ Each tool call
         ▼
   PreToolUse Hook
         │
         ├─► Check Auto-Routing
         │   │
         │   ├─► Stage 1 Pre-Filter
         │   │
         │   └─► Stage 2 Analysis (if needed)
         │
         ├─► Track Signals
         │   │
         │   └─► Update session-state.json
         │
         └─► Log Metrics
             │
             └─► Append to metrics.jsonl
    │
    ▼
Session End
    │
    ▼
Stop Hook
    │
    ├─► Check Auto-Cleanup
    │   │
    │   ├─► Safety Checks
    │   │
    │   └─► Invoke process-janitor (if safe)
    │
    ├─► Check Auto-Reflection
    │   │
    │   ├─► Calculate Worthiness
    │   │
    │   └─► Suggest /reflect (if worthy)
    │
    └─► Clear Session State
```

## Extensibility Points

### Adding New Automation Features

1. **Add Config Section**
   ```json
   "new_feature": {
     "enabled": false,
     "description": "...",
     "settings": {...}
   }
   ```

2. **Add Hook Logic**
   - Update `PreToolUse.md` or `Stop.md`
   - Add decision criteria
   - Add metrics logging

3. **Add Scripts**
   - Create `scripts/new-feature-*.sh`
   - Use common library functions
   - Follow safety patterns

4. **Add Command Integration**
   - Update `automation-command.sh`
   - Add enable/disable support
   - Add status reporting

5. **Add Tests**
   - Update `test-installation.sh`
   - Verify script execution
   - Validate configuration

### Plugin Integration Pattern

```
automation-hub
    │
    ├─► Multi-Agent Plugin
    │   └─► Invoke: multi-agent:task-analyzer
    │       Consumes: User prompt
    │       Returns: Complexity analysis
    │
    ├─► Process-Janitor Plugin
    │   └─► Invoke: cleanup script
    │       Consumes: None
    │       Returns: Cleanup report
    │
    ├─► Reflect Plugin
    │   └─► Invoke: reflect:reflect skill
    │       Consumes: Session signals
    │       Returns: Skill proposals
    │
    └─► Self-Debugger Plugin
        └─► Consume: issues.jsonl
            Produce: Auto-fix commands
            Returns: Fix results
```

## Performance Characteristics

### Overhead Analysis

**Stage 1 Pre-Filter:**
- Execution: <100ms (bash regex matching)
- Tokens: <100 (no LLM calls)
- Triggers: Every prompt (but 90% skip immediately)

**Stage 2 Analysis:**
- Execution: 2-5 seconds (LLM call with Haiku)
- Tokens: ~500-1000 (task-analyzer agent)
- Triggers: Only if Stage 1 score ≥4 (~10% of prompts)

**Auto-Cleanup:**
- Execution: <500ms (safety checks)
- Tokens: 0 (bash only)
- Triggers: Once per session at end

**Auto-Reflection:**
- Execution: <200ms (score calculation)
- Tokens: 0 (bash only)
- Triggers: Once per session at end (if worthy)

**Total Session Overhead:**
- Simple prompts: <100ms, <100 tokens (~2%)
- Complex prompts: 2-5sec, ~1000 tokens (acceptable for value gained)

## Security Considerations

### User Data Privacy

- **No External Calls**: All processing local
- **No Credential Storage**: Config is plain JSON, no secrets
- **Metrics Anonymization**: Session IDs are ephemeral

### Code Safety

- **Auto-Fix Disabled by Default**: Requires explicit opt-in
- **Git Checkpoints**: All auto-fixes create rollback points
- **Safety Blockers**: Multiple layers prevent destructive actions
- **Circuit Breakers**: Auto-disable on repeated failures

### Privilege Escalation

- **No Sudo Required**: All operations in user space
- **No Process Injection**: Only SIGTERM to owned processes
- **No File System Tampering**: Only modifies ~/.claude/automation-hub/

---

**Architecture Version:** 1.0
**Last Updated:** January 25, 2026
**Status:** Phase 1-3 Implemented
