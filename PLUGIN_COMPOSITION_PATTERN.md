# Plugin Composition Pattern

**A design pattern for creating cross-plugin enhancements while maintaining independence and user control.**

## Overview

Plugins can enhance each other through **observable interfaces** without creating hard dependencies. This enables:

- **Loose coupling**: Plugins work independently even when enhancers disabled
- **Optional enhancements**: Features are additive, not required
- **Graceful degradation**: Missing plugins don't cause errors
- **User control**: Any plugin can be enabled/disabled independently

## Core Principles

### 1. Observable Interfaces

Plugins expose data through **standard file locations** that other plugins can optionally consume.

```
Producer Plugin              Consumer Plugin (Enhancer)
    │                                    │
    ├─ Logs to ~/.claude/<name>/data.jsonl
    │  • No knowledge of consumers       │
    │  • Works completely standalone     │
    │                                    │
    │                              ├─ if [ -f data.jsonl ]; then
    │                              │    enhance()
    │                              │  fi
    │                              │  • Optional enhancement only
    │                              │  • Graceful if producer disabled
```

### 2. No Hard Dependencies

**✅ GOOD**: Producer doesn't know consumer exists

```bash
# multi-agent plugin
log_metrics() {
  # Always log, works without self-debugger
  echo "$METRICS" >> ~/.claude/multi-agent-metrics.jsonl
}
```

**❌ BAD**: Producer checks for consumer

```bash
# DON'T DO THIS
if command -v self-debugger &> /dev/null; then
  log_metrics()  # Only works if self-debugger installed
fi
```

### 3. Graceful Degradation

**✅ GOOD**: Consumer checks if data exists

```bash
# self-debugger plugin
if [ -f "$METRICS_FILE" ]; then
  analyze_metrics  # Enhance if available
else
  echo "No metrics found. Install multi-agent for this feature."
  exit 0  # Not an error
fi
```

**❌ BAD**: Consumer requires producer

```bash
# DON'T DO THIS
if [ ! -f "$METRICS_FILE" ]; then
  echo "ERROR: multi-agent required!"
  exit 1  # This breaks if multi-agent disabled
fi
```

## Standard Directory Structure

All plugins follow this convention for observable data:

```
~/.claude/
├── <plugin-name>/
│   ├── config.json              # User configuration
│   ├── metrics.jsonl            # Observable metrics
│   ├── <plugin-specific>.jsonl  # Other observable data
│   └── ...
```

### Example: Multi-Agent

```
~/.claude/
└── multi-agent/
    ├── config.json              # User preferences
    └── metrics.jsonl            # Logged: score, pattern, approval
```

### Example: Reflect

```
~/.claude/
└── reflect/
    ├── config.json              # Signal detection rules
    ├── proposals.jsonl          # Logged: type, approved, implemented
    └── metrics.jsonl            # General metrics
```

### Example: Process-Janitor

```
~/.claude/
└── process-janitor/
    ├── config.json              # Heartbeat timeout, etc.
    ├── cleanup.jsonl            # Logged: decisions, false positives
    └── heartbeat/               # Active process heartbeats
```

## Observable Data Schema

### Standard Metrics Format

Every plugin that wants to be optimizable should use:

```jsonl
{
  "timestamp": "2026-01-23T14:32:15Z",  // ISO 8601 UTC
  "event_type": "string",                // Domain-specific event
  "outcome": "success|failure|approved|rejected",
  "metadata": {
    // Plugin-specific data
  }
}
```

### Example: Multi-Agent Metrics

```jsonl
{
  "timestamp": "2026-01-23T14:32:15Z",
  "event_type": "complexity_analysis",
  "outcome": "approved",
  "complexity_score": 68,
  "pattern": "parallel",
  "agents": ["security-auditor", "performance-engineer"],
  "cost_estimate": 180000,
  "user_approved": true
}
```

### Example: Reflect Proposals

```jsonl
{
  "timestamp": "2026-01-23T15:10:42Z",
  "event_type": "skill_proposal",
  "outcome": "approved",
  "proposal_type": "session_analysis",
  "signal_type": "repeated_pattern",
  "approved_by_critic": true,
  "critic_score": 85,
  "implemented": true
}
```

## Plugin Detection Library

Use the standardized detection library in self-debugger:

```bash
# Source the library
source "${CLAUDE_PLUGIN_ROOT}/../self-debugger/scripts/lib/plugin-detector.sh"

# Check for specific plugins
if has_multi_agent_data; then
  echo "Multi-agent available"
fi

if has_reflect_data; then
  echo "Reflect available"
fi

# Detect all available plugins
AVAILABLE=$(detect_available_plugins)
echo "Available: $AVAILABLE"

# Check minimum samples
if check_minimum_samples "multi-agent" 20; then
  echo "Ready for analysis"
fi

# Show status to user
show_plugin_status
```

## Creating a New Plugin Enhancement

### Step 1: Producer Plugin Logs Data

**Example**: Add metrics logging to your plugin

```bash
# In your plugin's skill or command
log_metrics() {
  local metrics_dir="$HOME/.claude/my-plugin"
  local metrics_file="$metrics_dir/metrics.jsonl"

  mkdir -p "$metrics_dir"

  cat >> "$metrics_file" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "event_type": "my_event",
  "outcome": "success",
  "metadata": {
    "custom_field": "value"
  }
}
EOF
}

# Call it after key operations
execute_feature && log_metrics
```

### Step 2: Consumer Plugin Detects Data

**Example**: Add detection to self-debugger

```bash
# In plugins/self-debugger/scripts/lib/plugin-detector.sh

has_my_plugin_data() {
    local metrics_file="$HOME/.claude/my-plugin/metrics.jsonl"
    local plugin_dir="$HOME/.claude/plugins/my-plugin"

    [[ -f "$metrics_file" ]] || [[ -d "$plugin_dir" ]]
}

# Add to detect_available_plugins()
if has_my_plugin_data; then
    available+=("my-plugin")
fi

# Add to get_plugin_metrics_path()
my-plugin)
    echo "$HOME/.claude/my-plugin/metrics.jsonl"
    ;;
```

### Step 3: Create Detection Rule

**File**: `plugins/self-debugger/rules/external/my-plugin-optimization.json`

```json
{
  "id": "my-plugin-optimization",
  "name": "My Plugin Optimization",
  "description": "Analyzes my-plugin metrics to optimize behavior",
  "severity": "medium",
  "category": "optimization",
  "detection": {
    "type": "metrics-analysis",
    "metrics_file": "~/.claude/my-plugin/metrics.jsonl",
    "min_samples": 10
  },
  "script": "./scripts/detect-my-plugin.sh",
  "metadata": {
    "plugin_target": "my-plugin",
    "requires_user_data": true
  }
}
```

### Step 4: Create Detection Script

**File**: `plugins/self-debugger/scripts/detect-my-plugin.sh`

```bash
#!/bin/bash
set -euo pipefail

METRICS_FILE="$HOME/.claude/my-plugin/metrics.jsonl"
MIN_SAMPLES=10

# Check if data exists (graceful degradation)
if [ ! -f "$METRICS_FILE" ]; then
  echo "No my-plugin metrics found yet."
  exit 0
fi

# Check minimum samples
TOTAL=$(wc -l < "$METRICS_FILE" | tr -d ' ')
if [ "$TOTAL" -lt "$MIN_SAMPLES" ]; then
  echo "Need $((MIN_SAMPLES - TOTAL)) more samples"
  exit 0
fi

# Analyze metrics
echo "Analyzing $TOTAL events..."

# Your analysis logic here
jq -s 'group_by(.outcome) | map({outcome: .[0].outcome, count: length})' \
  "$METRICS_FILE"

# Detect issues and suggest improvements
# ...

exit 0  # Or exit 1 if issues found
```

### Step 5: Make Script Executable

```bash
chmod +x plugins/self-debugger/scripts/detect-my-plugin.sh
```

### Step 6: Document the Relationship

**In your plugin's README.md**:

```markdown
## Self-Optimization

This plugin can be optimized by [self-debugger](../self-debugger) based on usage patterns.

### How It Works

1. Plugin logs metrics to `~/.claude/my-plugin/metrics.jsonl`
2. Self-debugger analyzes patterns (after 10+ samples)
3. Suggests improvements based on data
4. You review and apply optimizations

### What Gets Optimized

- [Describe what self-debugger optimizes]
- [Example optimizations based on patterns]

See [self-debugger integration docs] for details.
```

## Real-World Examples

### Example 1: Multi-Agent ← Self-Debugger ✅

**Producer**: Multi-Agent
- Logs: Complexity scores, pattern recommendations, user approvals
- Location: `~/.claude/multi-agent-metrics.jsonl`
- Works standalone: Yes

**Consumer**: Self-Debugger
- Analyzes: Approval rates by pattern and score
- Suggests: Threshold adjustments
- Required: No (optional enhancement)

**Benefit**: Thresholds personalize to user preferences

### Example 2: Reflect ← Self-Debugger ✅

**Producer**: Reflect
- Logs: Proposal types, critic approvals, implementations
- Location: `~/.claude/reflect/proposals.jsonl`
- Works standalone: Yes

**Consumer**: Self-Debugger
- Analyzes: Success rates by proposal type
- Suggests: Signal detection improvements
- Required: No (optional enhancement)

**Benefit**: Better proposal quality over time

### Example 3: Process-Janitor ← Self-Debugger (Future)

**Producer**: Process-Janitor
- Logs: Cleanup decisions, false positives
- Location: `~/.claude/process-janitor/cleanup.jsonl`
- Works standalone: Yes

**Consumer**: Self-Debugger
- Analyzes: False positive rates
- Suggests: Heartbeat timeout adjustments
- Required: No (optional enhancement)

**Benefit**: Fewer incorrect process cleanups

## Plugin Metadata Declaration

### Enhanced plugin.json (Optional)

Declare relationships for documentation purposes:

```json
{
  "name": "multi-agent",
  "version": "1.0.0",
  "provides": {
    "metrics": {
      "location": "~/.claude/multi-agent-metrics.jsonl",
      "schema": {
        "timestamp": "ISO 8601",
        "complexity_score": "0-100",
        "pattern": "single|sequential|parallel|hierarchical",
        "user_approved": "boolean"
      },
      "description": "Complexity analysis decisions and user approvals"
    }
  },
  "enhanced_by": [
    {
      "plugin": "self-debugger",
      "feature": "threshold-calibration",
      "required": false
    }
  ]
}
```

```json
{
  "name": "self-debugger",
  "version": "1.0.0",
  "enhances": [
    {
      "plugin": "multi-agent",
      "feature": "threshold-calibration",
      "data_source": "metrics"
    },
    {
      "plugin": "reflect",
      "feature": "proposal-optimization",
      "data_source": "proposals"
    }
  ]
}
```

## Error Handling Best Practices

### Producer Plugin

```bash
# ✅ GOOD: Always log, never fail
log_metrics() {
  local metrics_file="$HOME/.claude/my-plugin/metrics.jsonl"

  # Create directory if needed
  mkdir -p "$(dirname "$metrics_file")"

  # Log metrics (no error checking needed)
  echo "$METRICS_JSON" >> "$metrics_file" || true

  # Continue execution regardless
}
```

### Consumer Plugin

```bash
# ✅ GOOD: Check, enhance, or skip gracefully
enhance_plugin() {
  local metrics_file="$HOME/.claude/my-plugin/metrics.jsonl"

  # Check existence
  if [ ! -f "$metrics_file" ]; then
    echo "Plugin not available for enhancement."
    return 0  # Not an error
  fi

  # Check minimum data
  if [ "$(wc -l < "$metrics_file")" -lt 10 ]; then
    echo "Insufficient data. Need more samples."
    return 0  # Not an error
  fi

  # Analyze and enhance
  analyze_metrics "$metrics_file"
}
```

## User Experience

### Discovery

Users should easily discover available enhancements:

```bash
$ /debug status

Plugin Enhancement Status:

  ✓ Multi-Agent: Active (25 executions logged)
    → Ready for threshold optimization

  ✓ Reflect: Active (15 proposals logged)
    → Ready for proposal optimization

  ○ Process-Janitor: Not detected

Install and use plugins to enable self-optimization features.
```

### Transparency

Always explain what data is being analyzed:

```bash
$ ./scripts/detect-multi-agent-thresholds.sh

=== Multi-Agent Threshold Analysis ===
Analyzing 25 executions from ~/.claude/multi-agent-metrics.jsonl

Pattern Performance:
  PARALLEL:
    Total: 9 | Approved: 3 | Rejected: 6
    Approval Rate: 33%

Optimization Opportunities:
  ⚠️  PARALLEL pattern has low approval rate (33%)
      Recommendation: Increase threshold from 50 to 60
```

## Testing Your Plugin Composition

### Test 1: Producer Works Standalone

```bash
# Disable consumer plugin
rm -rf ~/.claude/plugins/self-debugger

# Verify producer still works
/multi-agent Review code
# Should work perfectly, logging to metrics.jsonl
```

### Test 2: Consumer Handles Missing Data

```bash
# Remove producer data
rm ~/.claude/multi-agent-metrics.jsonl

# Verify consumer degrades gracefully
./scripts/detect-multi-agent-thresholds.sh
# Should show "No metrics found" (not error)
```

### Test 3: Enhancement Works When Both Present

```bash
# Both plugins installed and used
/multi-agent [multiple executions]

# Consumer detects and analyzes
./scripts/detect-multi-agent-thresholds.sh
# Should show analysis and recommendations
```

## Design Checklist

When creating cross-plugin enhancements:

### Producer Plugin
- [ ] Logs observable metrics to standard location
- [ ] Uses consistent JSON/JSONL format
- [ ] Documents metric schema
- [ ] Works standalone (no optimizer dependency)
- [ ] Continues if metrics logging fails
- [ ] Privacy: Only logs aggregated/non-sensitive data

### Consumer Plugin
- [ ] Checks if data source exists before reading
- [ ] Gracefully handles missing data (exit 0, not error)
- [ ] Provides clear user messaging about availability
- [ ] Doesn't break if producer disabled
- [ ] Documents what plugins it can enhance
- [ ] Shows minimum sample requirements

### Integration
- [ ] No hard dependencies (optional enhancement only)
- [ ] Clear documentation of relationship
- [ ] User can disable either plugin independently
- [ ] Metrics schema versioning for compatibility
- [ ] Privacy considerations documented
- [ ] Example usage in README

## Future Enhancements

### Plugin Registry (Planned)

Automatic discovery via marketplace:

```json
{
  "plugins": [
    {
      "name": "multi-agent",
      "provides_data": ["metrics"],
      "enhanced_by": ["self-debugger"]
    },
    {
      "name": "self-debugger",
      "consumes_data": ["metrics", "proposals", "cleanup"],
      "enhances": ["multi-agent", "reflect", "process-janitor"]
    }
  ]
}
```

### Standard CLI

```bash
# Discover available enhancements
claude plugins enhancements

# Enable/disable specific enhancements
claude plugins enhance multi-agent --with self-debugger
claude plugins enhance multi-agent --disable
```

### Metrics Viewer

```bash
# View metrics from all plugins
claude metrics list
claude metrics view multi-agent
claude metrics analyze --plugin multi-agent --last 30d
```

---

**Summary**: The Plugin Composition Pattern enables plugins to enhance each other while maintaining independence. Use observable interfaces (standard file locations), graceful degradation (check before enhance), and no hard dependencies (optional enhancement only). This creates a rich ecosystem where plugins collaborate without coupling.
