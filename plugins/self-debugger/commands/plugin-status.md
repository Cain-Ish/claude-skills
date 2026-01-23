---
name: plugin-status
description: Show which plugins can be enhanced by self-debugger and their status
usage: |
  /debug plugin-status       - Show all plugin enhancement status
  /debug optimize           - Run optimizations for available plugins
---

# Plugin Enhancement Status Command

Shows which plugins self-debugger can enhance and whether they have enough data for optimization.

## Usage

### Show Status

```bash
/debug plugin-status
```

**Output**:
```
Plugin Enhancement Status:

  ✓ Multi-Agent: Active (25 executions logged)
    → Ready for threshold optimization

  ✓ Reflect: Active (15 proposals logged)
    → Ready for proposal optimization

  ○ Process-Janitor: Not detected

Install and use plugins to enable self-optimization features.
```

### Run Optimizations

```bash
/debug optimize
```

**Output**:
```
Checking for optimization opportunities...

Running multi-agent threshold analysis...
=== Multi-Agent Threshold Analysis ===
[Full analysis output...]

Running reflect proposal analysis...
=== Reflect Proposal Analysis ===
[Full analysis output...]

Completed 2 of 2 optimization analyses.
```

## Implementation

```bash
#!/bin/bash

SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT}/scripts"

# Source plugin detection library
source "$SCRIPT_DIR/lib/plugin-detector.sh"

# Parse command
COMMAND="${1:-status}"

case "$COMMAND" in
  status|plugin-status)
    # Show which plugins can be enhanced
    show_plugin_status
    ;;

  optimize)
    # Run all available optimizations
    optimize_available_plugins "$SCRIPT_DIR"
    ;;

  *)
    echo "Usage: /debug plugin-status|optimize"
    echo ""
    echo "Commands:"
    echo "  plugin-status  - Show plugin enhancement availability"
    echo "  optimize       - Run optimizations for available plugins"
    exit 1
    ;;
esac
```

## What Plugins Can Be Enhanced

Self-debugger can optimize:

### Multi-Agent
- **Data**: Complexity scores and user approval decisions
- **Optimization**: Threshold calibration based on approval patterns
- **Minimum**: 20 executions
- **Impact**: Fewer false-positive multi-agent suggestions

### Reflect
- **Data**: Proposal types and critic approval rates
- **Optimization**: Signal detection improvements
- **Minimum**: 10 proposals
- **Impact**: Higher quality skill proposals

### Process-Janitor (Future)
- **Data**: Cleanup decisions and false positives
- **Optimization**: Heartbeat timeout adjustments
- **Minimum**: 20 cleanups
- **Impact**: Fewer incorrect process terminations

## Example Session

```bash
# Check status
$ /debug plugin-status

Plugin Enhancement Status:

  ✓ Multi-Agent: Active (8 executions logged)
    → Needs 12 more executions for optimization

  ○ Reflect: Not detected

# Use plugins to collect data
$ /multi-agent Review code
$ /multi-agent Implement feature
# ... (use multi-agent 12 more times)

# Check again
$ /debug plugin-status

Plugin Enhancement Status:

  ✓ Multi-Agent: Active (20 executions logged)
    → Ready for threshold optimization

# Run optimization
$ /debug optimize

Checking for optimization opportunities...

Running multi-agent threshold analysis...
=== Multi-Agent Threshold Analysis ===
Analyzing 20 executions...

Optimization Opportunities:
  ⚠️  PARALLEL pattern has low approval rate (30%)
      Recommendation: Increase threshold to 60

Completed 1 of 1 optimization analyses.
```

## Privacy Note

Self-debugger only analyzes:
- Aggregate metrics (counts, rates, scores)
- User decisions (approved/rejected)
- Timestamps

It does NOT access:
- Actual code content
- User prompts or requests
- File paths or names
- Any sensitive data

All data is stored locally in `~/.claude/` and never uploaded.
