---
name: self-improve
description: Analyze metrics and improve self-debugger based on feedback
usage: |
  /self-improve           Run self-improvement analysis
  /self-improve web       Discover patterns from web
args:
  - name: mode
    description: Mode (empty for standard, 'web' for web discovery)
    required: false
---

# Self-Debugger: Self-Improvement Command

Analyzes fix approval metrics, adjusts rule confidence, and discovers new patterns from the web.

## Subcommands

### `/self-improve` (Standard Analysis)

Analyzes self-debugger effectiveness and adjusts rule confidence:

1. **Load metrics** from `~/.claude/self-debugger/metrics.jsonl`
2. **Calculate health score** (0-100) based on:
   - Issue resolution rate
   - False positive rate (issues pending > 7 days)
   - Fix approval rate
3. **Analyze each rule**:
   - Count total detections
   - Count applied fixes
   - Calculate approval rate
4. **Adjust confidence**:
   - High approval (≥90%): +0.05 confidence
   - Low approval (≤30%): -0.10 confidence
   - Medium approval: -0.02 confidence
5. **Create feature branch** with rule updates
6. **Commit and push** for review

Execute:
```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
"$PLUGIN_ROOT/scripts/self-improve.sh"
```

**Example output**:
```
Self-debugger health score: 85/100
Rule: hook-session-start-valid - Approval rate: 95%
Rule: plugin-schema-valid - Approval rate: 80%
Adjusted rule confidence: hook-session-start.json 0.95 → 1.0 (approval: 95%)
Rules updated: 1

Branch: debug/self-debugger/confidence-adjustment
Next step: Review MR and merge to main
```

### `/self-improve web` (Web Discovery)

Discovers new patterns and best practices from the web:

1. **Search for Claude Code best practices** (current year)
2. **Fetch official documentation** updates
3. **Extract code patterns** from examples
4. **Generate external rules** with confidence scores:
   - Official sources (docs.anthropic.com): 0.8 confidence
   - Community sources (GitHub): 0.6 confidence
   - With code examples: +0.1 confidence
5. **Store in `rules/external/`** for validation

Execute:
```bash
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT}"
"$PLUGIN_ROOT/scripts/web-discover.sh"
```

**Example output**:
```
Searching for Claude Code plugin best practices...
Found 5 potential sources

Discovering hook best practices...
Created external rule: hook-has-description-external (confidence: 0.7)

Web discovery complete
External rules: 1
```

## When to Use

**Run standard self-improvement**:
- After applying 10+ fixes
- Weekly maintenance
- Before releasing new rules
- When health score drops below 70

**Run web discovery**:
- Monthly (discover new patterns)
- After major Claude Code releases
- When creating new plugin types
- To validate existing rules against official docs

## Requirements

**Standard analysis**:
- Minimum 5 detections per rule for confidence adjustment
- Issues and fixes recorded in JSONL files
- Source repository access

**Web discovery**:
- WebSearch tool integration (pending)
- WebFetch tool integration (pending)
- Internet connectivity

## Safety

- All rule changes go to feature branches
- Human review required before merge
- Confidence clamped to 0.1-1.0 range
- Web-discovered rules start at ≤0.8 confidence
- Never auto-merge self-improvements

## Metrics Tracked

Stored in `~/.claude/self-debugger/metrics.jsonl`:
- `event: self_improvement` - Rule confidence adjustments
- `event: web_discovery` - Pattern discovery runs
- `health_score` - Overall effectiveness (0-100)
- `rules_updated` - Count of modified rules

## Examples

```bash
# Standard self-improvement
/self-improve

# Web pattern discovery
/self-improve web

# Check results
cat ~/.claude/self-debugger/metrics.jsonl | tail -5 | jq .

# View adjusted rules
git diff plugins/self-debugger/rules/core/
```

## Notes

- Self-improvement runs safely in source repository only
- Web discovery requires internet and WebSearch tool
- All changes require MR review before merge
- Health score formula: resolution_rate - false_positive_rate
