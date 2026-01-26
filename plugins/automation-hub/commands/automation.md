# /automation Command

Control and monitor the automation-hub orchestration system.

## Usage

```bash
/automation <subcommand> [options]
```

## Subcommands

### `status`

Show current automation system status, including:
- Feature enablement state (auto-routing, auto-cleanup, auto-reflect, auto-apply)
- Recent activity (last 24 hours)
- User approval rates by complexity band
- Pending optimizations from learning system
- Circuit breaker status
- Rate limit usage

**Example:**
```bash
/automation status
```

### `enable <feature|all>`

Enable a specific automation feature or all features.

**Features:**
- `auto-routing`: Multi-agent routing
- `auto-cleanup`: Process cleanup
- `auto-reflect`: Reflection suggestions
- `auto-apply`: Auto-fix application (requires explicit opt-in)
- `learning`: Cross-plugin optimization learning
- `all`: All features (except auto-apply)

**Example:**
```bash
/automation enable auto-routing
/automation enable all
```

### `disable <feature|all>`

Disable a specific automation feature or all features.

**Example:**
```bash
/automation disable auto-routing
/automation disable all
```

### `debug`

Show detailed debug information for troubleshooting:
- Recent decision traces
- Failed automation attempts
- Configuration validation
- Metrics file health

**Example:**
```bash
/automation debug
```

### `rollback-fixes`

Rollback auto-applied fixes to the last git checkpoint.

**Example:**
```bash
/automation rollback-fixes
```

### `reset-learning`

Reset learning system metrics and approval rate tracking.

**Example:**
```bash
/automation reset-learning
```

### `config`

Open the automation configuration file for manual editing.

**Example:**
```bash
/automation config
```

## Implementation

When the user invokes `/automation <subcommand>`, execute the corresponding script:

```bash
bash /path/to/plugins/automation-hub/scripts/automation-command.sh "${SUBCOMMAND}" "${ARGS}"
```

## Output Format

### Status Output

```
🤖 Automation Hub Status

Features:
  ✓ Auto-Routing: ENABLED
    - Stage 1 threshold: 4/10
    - Auto-approve moderate: NO
    - Auto-approve complex: NO
    - Approval rate (moderate): 75% (12 samples)
    - Approval rate (complex): 82% (8 samples)

  ✓ Auto-Cleanup: ENABLED
    - Idle timeout: 10 minutes
    - Require clean git: YES
    - Cleanups today: 3

  ✓ Auto-Reflect: ENABLED (suggest-only)
    - Worthiness threshold: 20 points
    - Suggestions today: 1

  ✗ Auto-Apply: DISABLED
    - Min confidence: 90%
    - Allowed severities: low

  ✓ Learning: ENABLED
    - Pending proposals: 2
    - Last analysis: 2 days ago

Activity (Last 24h):
  - Auto-routing invoked: 8 times
  - User approvals: 6 (75%)
  - User rejections: 2 (25%)
  - Auto-cleanups: 3
  - Reflection suggestions: 1

Circuit Breakers:
  ✓ All circuits CLOSED (healthy)

Rate Limits:
  - Auto-routing: 8/10 per hour (80%)
```

### Debug Output

```
🔍 Automation Hub Debug Info

Recent Decisions (last 10):
  [2026-01-25 14:23:15] auto_routing → auto_approve
    Reason: Auto-approved based on learning (approval_rate=0.82)
    Complexity: 58, Pattern: parallel, Tokens: 120K

  [2026-01-25 13:45:32] auto_routing → suggest
    Reason: Approval rate (0.65) below threshold (0.70)
    Complexity: 42, Pattern: sequential, Tokens: 80K

Failed Attempts:
  None

Configuration Validation:
  ✓ Config file exists
  ✓ Config valid JSON
  ✓ All required fields present
  ✓ Metrics file writable

Metrics Health:
  - Total entries: 1,247
  - Oldest entry: 45 days ago
  - File size: 512 KB
  - Last entry: 2 minutes ago
```

## Error Handling

- If feature doesn't exist: Show error and list valid features
- If config file corrupted: Offer to restore from default
- If permission denied: Show instructions to fix permissions
- If metrics file missing: Create new empty file

## Safety Notes

- Disabling a feature immediately stops all automation for that feature
- Enabling auto-apply requires explicit confirmation (dangerous operation)
- Reset-learning requires confirmation (destructive operation)
- Rollback-fixes only works if checkpoints exist
