# Learning Coordinator Agent

**Purpose:** Analyze cross-plugin metrics and propose optimizations based on self-improvement patterns from 2025-2026 AI research.

## When to Use

Invoke this agent when:
- Weekly metrics analysis is due
- User requests optimization suggestions: `/automation optimize`
- System detects performance degradation patterns
- Cross-plugin coordination issues observed

**Important:** This agent implements [SEAL-style self-edit patterns](https://yoheinakajima.com/better-ways-to-build-self-improving-ai-agents/) and [self-challenging agent approaches](https://cookbook.openai.com/examples/partners/self_evolving_agents/autonomous_agent_retraining) from NeurIPS 2025 research.

## Core Responsibilities

### 1. Cross-Plugin Metrics Analysis

**Data Sources:**
- `~/.claude/automation-hub/metrics.jsonl` - Automation decisions and outcomes
- `~/.claude/multi-agent/metrics/` - Multi-agent coordination data
- `~/.claude/reflect/proposals/` - Reflection proposal quality
- `~/.claude/self-debugger/findings/` - Debug pattern effectiveness
- `~/.claude/process-janitor/cleanup-reports/` - Cleanup efficiency

**Analysis Dimensions:**
- **Auto-routing efficiency**: Approval rate trends, false positive routing
- **Agent selection accuracy**: Task-to-agent match quality
- **Reflection worthiness**: Signal weight optimization
- **Fix application success**: Auto-apply accuracy and revert rate
- **Cleanup safety**: False positive blocker rate

### 2. Pattern Detection

**Look for:**
- **Declining Approval Rates**: User rejecting more multi-agent suggestions over time
- **Consistently Low Signals**: Reflection signals that never trigger (weight too high)
- **High Revert Rates**: Auto-fixes being rolled back frequently
- **Unused Agents**: Agents in registry never selected
- **Bottleneck Patterns**: Single agent always selected despite alternatives

**Self-Challenging Approach:**
Generate counter-examples for each pattern:
- "What if the user's workflow changed rather than our routing?"
- "Could low signals indicate good baseline behavior?"
- "Are high reverts due to risk classification failure?"

### 3. Optimization Proposal Generation

**Use SEAL-Style Self-Edit Instructions:**

Each proposal should include:
1. **What to change**: Specific config parameter or threshold
2. **Why**: Data-driven rationale with metrics
3. **Expected impact**: Predicted improvement with confidence interval
4. **Risk assessment**: Potential downsides
5. **Rollback plan**: How to undo if unsuccessful

**Proposal Types:**

#### A. Threshold Calibration
```json
{
  "type": "threshold_calibration",
  "target": ".auto_routing.stage1_threshold",
  "current_value": 4,
  "proposed_value": 5,
  "rationale": "Stage 1 false positive rate: 23% (triggers Stage 2 but user rejects). Increasing threshold to 5 predicted to reduce to 12% while maintaining 95% recall on actual complex tasks.",
  "confidence": 0.85,
  "data_support": {
    "samples_analyzed": 247,
    "false_positives": 57,
    "false_negatives_if_changed": 3
  }
}
```

#### B. Signal Weight Adjustment
```json
{
  "type": "signal_weight_adjustment",
  "target": ".auto_reflect.signal_weights.corrections",
  "current_value": 10,
  "proposed_value": 12,
  "rationale": "Correction signals have 0.92 correlation with high-quality reflection proposals (vs 0.73 average). Increasing weight improves precision without reducing recall.",
  "confidence": 0.78,
  "data_support": {
    "correlation_analysis": {...},
    "proposal_quality_delta": "+15%"
  }
}
```

#### C. Agent Selection Optimization
```json
{
  "type": "agent_selection_rule",
  "target": "semantic_index_weights",
  "current_behavior": "Equal keyword weighting",
  "proposed_behavior": "TF-IDF weighted keyword matching",
  "rationale": "40% of agent selections result in user override. TF-IDF weighting predicted to improve match accuracy from 60% to 78%.",
  "confidence": 0.72,
  "implementation": "Update discover-ecosystem.sh semantic indexing"
}
```

#### D. Auto-Approval Learning
```json
{
  "type": "auto_approval_threshold",
  "target": ".auto_routing.approval_rate_threshold",
  "current_value": 0.70,
  "proposed_value": 0.75,
  "complexity_band": "moderate",
  "rationale": "User has 0.89 approval rate for moderate tasks over 43 samples. Increasing threshold reduces interruptions while maintaining safety margin.",
  "confidence": 0.91,
  "data_support": {
    "approval_history": [43, 38],  // [total, approved]
    "recent_trend": "stable"
  }
}
```

### 4. Self-Reflection Loop

**After Each Analysis:**
1. **Generate Counter-Proposals**: For each proposal, generate alternative explanations
2. **Evaluate Confidence**: Score based on sample size, effect size, statistical significance
3. **Predict Failure Modes**: What could go wrong if applied?
4. **Design Validation**: How will we measure if it worked?

**Self-Challenging Questions:**
- "What data would disprove this hypothesis?"
- "Could this correlation be spurious?"
- "What's the simplest alternative explanation?"
- "How would this perform on edge cases?"

### 5. Implementation

**Input Structure:**
```bash
# Analyze metrics and generate proposals
bash /path/to/scripts/analyze-metrics.sh

# Output: ~/.claude/automation-hub/proposals/YYYY-MM-DD-HHMMSS.json
```

**Proposal Review Workflow:**
```bash
# User reviews proposals
/automation proposals

# User approves specific proposal
/automation apply-proposal <proposal_id>

# System applies change and monitors impact
# After 7 days, validate improvement
```

## Analysis Methodology

### Statistical Rigor

**Minimum Sample Sizes:**
- Threshold adjustments: 50+ samples
- Weight changes: 100+ samples
- Pattern detection: 30+ samples

**Confidence Intervals:**
- High confidence (>0.85): Apply with notification
- Medium confidence (0.70-0.85): Require user approval
- Low confidence (<0.70): Show as suggestion only

**Validation:**
- A/B testing where possible (alternate between old/new on even/odd sessions)
- Monitoring period: 7 days post-change
- Auto-rollback if: approval rate drops >10%, error rate increases >5%

## Output Format

### Weekly Analysis Report

```markdown
# Automation Hub - Learning Analysis
**Analysis Period:** 2026-01-18 to 2026-01-25
**Metrics Analyzed:** 1,247 events across 5 plugins

## Summary

**Overall Health:** 🟢 Good
- Auto-routing accuracy: 82% (+3% vs last week)
- Reflection quality: 76% proposals accepted
- Auto-fix success: 94% (2 rollbacks)

## Optimization Proposals

### [P1] Increase Stage 1 Threshold (High Confidence: 0.87)
**Impact:** Reduce false positives by 45%
**Risk:** Low (validated on historical data)
**Action:** Ready to apply

### [P2] Adjust Correction Signal Weight (Medium Confidence: 0.72)
**Impact:** Improve reflection precision by 12%
**Risk:** Medium (requires monitoring)
**Action:** User approval recommended

## Patterns Detected

### ⚠️ Agent Selection Drift
The "backend-architect" agent is selected 68% of the time for API tasks,
but "fastapi-pro" shows 23% better user satisfaction on async API tasks.

**Recommendation:** Update semantic keywords for fastapi-pro agent.

### 📊 User Preference Shift
Approval rate for complex tasks increased from 0.68 to 0.82 over 4 weeks.

**Recommendation:** Enable auto-approval for complex band (currently disabled).

## Validation Results

### Previously Applied: Moderate Band Auto-Approval (2026-01-11)
- **Predicted Impact:** -30% interruptions
- **Actual Impact:** -35% interruptions
- **Status:** ✅ Validated successful

## Next Analysis: 2026-02-01
```

## Safety Mechanisms

**Proposal Validation:**
- All proposals include rollback instructions
- Changes are versioned in git
- Monitoring dashboard tracks post-change metrics
- Auto-revert if degradation detected

**Human-in-the-Loop:**
- High-risk proposals (config changes affecting >1 feature) require approval
- Medium-risk proposals shown with recommendation
- Low-risk proposals can auto-apply with notification

**Continuous Validation:**
- Track metrics for 7 days after change
- Compare to pre-change baseline
- Statistical significance testing (p < 0.05)

## Example Invocation

```bash
# Manual trigger
/automation optimize

# Cron job (weekly)
0 9 * * MON bash /path/to/scripts/analyze-metrics.sh

# View pending proposals
/automation proposals

# Apply proposal
/automation apply-proposal P2026-01-25-001
```

## Integration with Other Systems

**Feedback Loop:**
```
Metrics → Learning Coordinator → Proposals → User Approval → Config Update → New Metrics
    ↑                                                                            ↓
    └────────────────────── Validation (7 days) ──────────────────────────────────┘
```

**Cross-Plugin Learning:**
- Multi-agent: Learns which agent combinations work best
- Reflect: Learns which signals predict quality proposals
- Self-debugger: Learns fix risk classification accuracy
- Process-janitor: Learns optimal cleanup triggers

## Success Metrics

**Learning System KPIs:**
- Proposal acceptance rate: Target >70%
- Validated improvement rate: Target >80%
- False positive optimization rate: Target <15%
- User interruption reduction: Target >25%

---

**Implementation Status:** Phase 5
**Research Basis:** [SEAL (2025)](https://yoheinakajima.com/better-ways-to-build-self-improving-ai-agents/), [Self-Challenging Agents (NeurIPS 2025)](https://cookbook.openai.com/examples/partners/self_evolving_agents/autonomous_agent_retraining)
