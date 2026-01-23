# Multi-Agent Self-Optimization via Self-Debugger

The multi-agent plugin integrates with the **self-debugger** plugin to automatically detect and suggest threshold optimizations based on your actual usage patterns.

## How It Works

```
You use /multi-agent
    ↓
Metrics logged to ~/.claude/multi-agent-metrics.jsonl
    ↓
Self-debugger monitors metrics (every 5 min in source repo)
    ↓
Detects threshold calibration opportunities
    ↓
Suggests adjustments based on approval patterns
    ↓
You review and apply (or ignore)
```

## What Gets Optimized

### Complexity Thresholds

The system analyzes your approval/rejection patterns to optimize:

```json
{
  "complexity_thresholds": {
    "simple": 30,     // When to use single agent
    "moderate": 50,   // When to use sequential (2 agents)
    "complex": 70     // When to use parallel/hierarchical
  }
}
```

### Optimization Signals

**Low Approval Rate** (⚠️ Issue)
- Pattern: You frequently reject a coordination pattern
- Example: Parallel pattern rejected 80% of the time at scores 50-55
- Recommendation: Increase threshold (e.g., 50 → 55)
- Impact: Fewer false-positive multi-agent suggestions

**High Approval Rate** (✨ Opportunity)
- Pattern: You almost always approve a coordination pattern
- Example: Parallel pattern approved 95% of the time at scores 65+
- Recommendation: Could decrease threshold (e.g., 70 → 65)
- Impact: More tasks benefit from multi-agent coordination earlier

**Score Boundary Issues** (🎯 Precision)
- Pattern: Rejection cluster at specific score range
- Example: 5 rejections at scores 52-54, but approvals at 60+
- Recommendation: Adjust boundary to be more precise
- Impact: Better accuracy in pattern recommendations

## Requirements

### 1. Install Self-Debugger Plugin

```bash
# Clone or symlink self-debugger
ln -s /path/to/claude-skills/plugins/self-debugger ~/.claude/plugins/self-debugger
```

### 2. Work in Source Repository

Self-debugger only activates in the claude-skills source repository (has `.git` + `plugins/` marker).

### 3. Collect Metrics

Use `/multi-agent` at least **20 times** to collect enough data for analysis.

```bash
# As you work, use multi-agent:
/multi-agent Review this code for security issues
/multi-agent Implement feature with tests
/multi-agent Comprehensive audit of auth module

# Each execution logs metrics
```

## Checking for Optimizations

### Manual Check

```bash
# Run detection script directly
./plugins/self-debugger/scripts/detect-multi-agent-thresholds.sh
```

**Output Example**:
```
=== Multi-Agent Threshold Analysis ===
Analyzing 25 executions...

Pattern Performance:
  PARALLEL:
    Total: 12 | Approved: 4 | Rejected: 8
    Approval Rate: 33%
    Score Range: 50-72 (avg: 58)

Optimization Opportunities:
  ⚠️  PARALLEL pattern has low approval rate (33%)
    Average score: 58
    Recommendation: Increase threshold to reduce false-positive suggestions
    Impact: Fewer rejected multi-agent proposals

Recommended Actions:
1. Review approval patterns above
2. Adjust thresholds in: ~/.claude/multi-agent.local.md
3. Or modify: plugins/multi-agent/config/default-config.json
```

### Automatic Monitoring

If self-debugger is running in background (in source repo):

```bash
# Check for detected issues
/debug

# Self-debugger will show multi-agent threshold issues if detected
Issues Detected:
  1. multi-agent-threshold-optimization
     Severity: medium
     Description: Multi-Agent Threshold Calibration
     Detected: Parallel pattern has low approval rate
```

## Applying Optimizations

### Option 1: Manual Adjustment (Recommended)

Create or update `~/.claude/multi-agent.local.md`:

```markdown
---
complexity_thresholds:
  simple: 30
  moderate: 50
  complex: 60    # Adjusted from 70 based on usage patterns
---

# My Adjustments

Based on 25 executions, I found parallel pattern at scores 70+ works well,
but scores 50-60 often get rejected. Lowered threshold to 60.
```

### Option 2: Auto-Fix (Future)

```bash
# Generate and apply fix automatically
./plugins/self-debugger/scripts/fix-multi-agent-thresholds.sh

# This will:
# 1. Analyze metrics
# 2. Calculate optimal thresholds
# 3. Update config file
# 4. Create backup
```

**Currently**: Manual review recommended
**Future**: Will integrate with self-debugger's fix generation workflow

## Metrics Collection

### What's Logged

Every `/multi-agent` execution logs:

```json
{
  "timestamp": "2026-01-23T14:32:15Z",
  "complexity_score": 68,
  "pattern": "parallel",
  "agents": ["security-auditor", "performance-engineer", "test-automator"],
  "cost_estimate": 180000,
  "user_approved": true
}
```

### Metrics Location

```bash
~/.claude/multi-agent-metrics.jsonl
```

### View Your Metrics

```bash
# See all executions
cat ~/.claude/multi-agent-metrics.jsonl | jq '.'

# Approval rate by pattern
cat ~/.claude/multi-agent-metrics.jsonl | jq -s '
  group_by(.pattern) |
  map({
    pattern: .[0].pattern,
    approval_rate: ((map(select(.user_approved == true)) | length) / length * 100)
  })
'

# Recent rejections
cat ~/.claude/multi-agent-metrics.jsonl | jq -s '
  map(select(.user_approved == false)) | .[-5:]
'
```

## Privacy & Data

### What's Stored

- Complexity scores
- Pattern recommendations
- User approval decisions (yes/no)
- Timestamp

### What's NOT Stored

- Actual request content
- Code being analyzed
- File paths
- Any user data

### Data Location

All metrics stored locally:
- `~/.claude/multi-agent-metrics.jsonl` (your metrics)
- Never uploaded or shared
- Analyzable only by self-debugger on your machine

## Example Workflow

### Week 1: Collect Data

```bash
# Use multi-agent naturally
/multi-agent Review auth module for security

Complexity: 58
Pattern: parallel
Proceed? (y/N): n  # You reject it

# Metrics logged: {score: 58, pattern: "parallel", approved: false}
```

### Week 2: Check for Patterns

```bash
# After 20+ executions
./plugins/self-debugger/scripts/detect-multi-agent-thresholds.sh

# See that you reject parallel at scores 50-60
⚠️  PARALLEL pattern has low approval rate (40%)
    Score boundary: ~55 has 6 rejections
    Recommendation: Increase threshold to 60
```

### Week 3: Apply Optimization

```bash
# Update your config
~/.claude/multi-agent.local.md:
---
complexity_thresholds:
  complex: 60  # Increased from 50
---
```

### Week 4: Validate Improvement

```bash
# Continue using multi-agent
/multi-agent Review auth module for security

Complexity: 58
Pattern: sequential  # Now uses simpler pattern at this score
Proceed? (y/N): y   # Higher approval rate!

# Metrics show improvement
```

## Benefits

### Personalized Thresholds

Your thresholds adapt to **your** preferences:
- Conservative users → higher thresholds (fewer multi-agent suggestions)
- Aggressive users → lower thresholds (more multi-agent usage)

### Token Optimization

- Fewer rejected multi-agent proposals = less wasted tokens
- Better pattern matching = higher approval rate
- Personalized cost/quality trade-off

### Continuous Improvement

As you use multi-agent more:
- Data gets richer
- Patterns become clearer
- Thresholds get more accurate

## Troubleshooting

### "No metrics found"

**Cause**: Haven't used `/multi-agent` yet

**Solution**: Use the command to generate metrics:
```bash
/multi-agent [your request]
```

### "Insufficient data for analysis"

**Cause**: Fewer than 20 executions

**Solution**: Continue using `/multi-agent`. Check count:
```bash
wc -l ~/.claude/multi-agent-metrics.jsonl
```

### "Self-debugger not detecting issues"

**Cause**: Not in source repository or self-debugger not installed

**Solution**:
1. Ensure you're in claude-skills source repo
2. Verify self-debugger is installed: `ls ~/.claude/plugins/self-debugger`
3. Check detection manually: `./plugins/self-debugger/scripts/detect-multi-agent-thresholds.sh`

### "Recommendations don't match my experience"

**Cause**: Small sample size or recent behavior change

**Solution**:
- Collect more data (50+ executions better than 20)
- Clear old metrics if preferences changed: `rm ~/.claude/multi-agent-metrics.jsonl`
- Start fresh collection

## Advanced: Custom Analysis

### Analyze Specific Pattern

```bash
cat ~/.claude/multi-agent-metrics.jsonl | jq -s '
  map(select(.pattern == "parallel")) |
  group_by((.complexity_score / 10 | floor) * 10) |
  map({
    score_bucket: .[0].complexity_score,
    total: length,
    approved: (map(select(.user_approved == true)) | length)
  })
'
```

### Find Rejection Clusters

```bash
cat ~/.claude/multi-agent-metrics.jsonl | jq -s '
  map(select(.user_approved == false)) |
  group_by(.pattern) |
  map({
    pattern: .[0].pattern,
    avg_rejected_score: ((map(.complexity_score) | add) / length)
  })
'
```

### Export Metrics for Analysis

```bash
# Convert to CSV for spreadsheet analysis
cat ~/.claude/multi-agent-metrics.jsonl | jq -r '
  [.timestamp, .complexity_score, .pattern, .user_approved] |
  @csv
' > multi-agent-metrics.csv
```

## Future Enhancements

### Planned (Phase 2)

- [ ] Automatic fix application (with user approval)
- [ ] Integration with /debug command
- [ ] Visual approval rate charts
- [ ] Per-domain threshold tuning (security vs performance)

### Ideas (Phase 3)

- [ ] Machine learning for pattern prediction
- [ ] Time-of-day patterns (user more conservative when tired?)
- [ ] Project-specific threshold profiles
- [ ] Collaborative learning (anonymized patterns from community)

---

**Summary**: Multi-agent thresholds automatically optimize based on your usage patterns via self-debugger integration. Collect 20+ metrics, check for optimizations, apply adjustments, validate improvements. Your personalized thresholds improve over time!
