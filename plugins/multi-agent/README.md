# Multi-Agent Orchestration Plugin

Intelligent routing and coordination of single or multiple agents based on task complexity, with transparent cost-benefit analysis.

## Overview

**Problem**: Using multiple agents for simple tasks wastes tokens. Using a single agent for complex tasks produces inferior results.

**Solution**: Automatically analyze task complexity (0-100 score) → Recommend optimal pattern (single/sequential/parallel/hierarchical) → Show cost comparison (1× vs 15×) → Execute with user approval.

**Research Foundation**:
- Multi-agent achieves **90% better results** on complex tasks
- Token consumption is **15× higher** on average
- Optimal at **30K+ token contexts**
- Token usage explains **80% of performance variance**

**Key Insight**: Multi-agent is justified when task value warrants 90% quality improvement at 15× token cost.

## Quick Start

### Installation

The plugin is automatically available in the `plugins/multi-agent` directory.

### Basic Usage

```bash
# Analyze and execute with optimal routing
/multi-agent Review this authentication module for security and performance issues

# Analyze complexity without execution
/multi-agent analyze Implement OAuth2 with comprehensive testing

# Check configuration and metrics
/multi-agent status

# View configuration details
/multi-agent config
```

### Example Session

```bash
$ /multi-agent Comprehensive review of authentication module

Analyzing and executing: Comprehensive review of authentication module

## Complexity Analysis
Score: 68/100 (Complex)
Detected Domains: security, review, performance
Recommended Pattern: Parallel

Cost Comparison:
- Single agent:  ~20,000 tokens
- Multi-agent:   ~180,000 tokens (9×)

Expected Improvement: 90% better results with multi-specialist coverage

Recommended Agents:
- security-auditor: Security audits and vulnerability assessment
- performance-engineer: Performance optimization and scalability
- test-automator: Test automation and quality assurance

Reasoning: Three independent analysis domains (security, performance, testing).
Parallel execution provides comprehensive coverage with each specialist focusing
on their domain.

Proceed with parallel execution? (y/N): y

Launching parallel analysis with 3 agents...

[Agents execute simultaneously]

Aggregating results from 3 specialists...

## Multi-Agent Analysis Summary

**Agents Executed**: 3 (security-auditor, performance-engineer, test-automator)
**Domains Analyzed**: security, performance, testing
**Total Findings**: 12 (2 critical, 4 high, 4 medium, 2 low)

[Comprehensive unified report follows...]
```

## Architecture

### Components

```
plugins/multi-agent/
├── agents/
│   ├── task-analyzer.md        # Complexity scoring and pattern recommendation
│   ├── coordinator.md          # Hierarchical orchestration
│   └── aggregator.md           # Parallel result synthesis
├── skills/
│   └── orchestrate/
│       ├── SKILL.md            # Main orchestration workflow
│       └── references/         # Detailed documentation
│           ├── complexity-scoring.md
│           ├── agent-registry.md
│           └── coordination-patterns.md
├── commands/
│   └── multi-agent.md          # User-facing command
├── scripts/
│   └── lib/
│       ├── complexity-analyzer.js  # Core decision engine
│       └── agent-registry.json     # Agent capabilities database
└── config/
    ├── default-config.json         # Default settings
    └── multi-agent.local.example.md # Configuration template
```

### Workflow

```
User Request
    ↓
[1] Load Configuration
    ↓
[2] Analyze Complexity (task-analyzer agent)
    ↓
[3] Present Analysis + Get Approval
    ↓
[4] Execute Pattern
    │
    ├─→ Single: One agent handles everything
    ├─→ Sequential: A → B pipeline
    ├─→ Parallel: A + B + C → Aggregator
    └─→ Hierarchical: Coordinator orchestrates
    ↓
[5] Return Results
    ↓
[6] Track Metrics
```

## Coordination Patterns

### Pattern 1: Single Agent (Complexity 0-29)

**Use Case**: Simple, focused tasks

**Example**: "Fix typo in README.md"

**Cost**: 1× (baseline)

**Execution**:
```
general-purpose
    ↓
Result
```

### Pattern 2: Sequential (Complexity 30-49)

**Use Case**: Dependent two-phase workflows

**Example**: "Implement API endpoint and review for security"

**Cost**: 2-6× (depends on agents)

**Execution**:
```
general-purpose (implement)
    ↓
security-auditor (review)
    ↓
Result
```

### Pattern 3: Parallel (Complexity 50-69)

**Use Case**: Independent multi-domain analysis

**Example**: "Review PR for security, performance, and test coverage"

**Cost**: 8-15×

**Execution**:
```
        Request
           |
    ┌──────┼──────┐
    ↓      ↓      ↓
Security  Perf  Test
    └──────┼──────┘
           ↓
    Aggregator
           ↓
    Unified Report
```

### Pattern 4: Hierarchical (Complexity 70-100)

**Use Case**: Complex multi-phase workflows with coordination

**Example**: "Design and implement OAuth2 with comprehensive validation"

**Cost**: 10-20×

**Execution**:
```
    Coordinator
        ↓
    Design (architect)
        ↓
    Implement (general)
        ↓
    Validate (parallel)
    ├─ Security
    ├─ Performance
    └─ Testing
        ↓
    Synthesize (coordinator)
        ↓
    Unified Report
```

## Complexity Scoring

### Scoring Components (Total: 100 points)

**1. Token Estimate (Max 40 points)**
- \> 50K tokens: 40 points
- 30-50K: 30 points
- 10-30K: 20 points
- 5-10K: 10 points
- < 5K: 0-5 points

**2. Domain Diversity (Max 30 points)**
- 3+ domains: 30 points
- 2 domains: 20 points
- 1 domain: 10 points

**3. Structural Complexity (Max 30 points)**
- Multi-step workflow: 10 points
- Validation required: 10 points
- Parallel work viable: 10 points

### Domain Detection

Detects keywords to identify expertise needed:

- **Security**: security, vulnerability, auth*, compliance, owasp
- **Performance**: optimize, slow, bottleneck, latency, cache
- **Testing**: test, coverage, jest, pytest, tdd, unit
- **Review**: review, quality, refactor, maintainability
- **Architecture**: architecture, design, pattern, microservices
- **Debugging**: bug, error, fix, debug, crash, exception

## Agent Registry

Available specialists:

| Agent | Domains | Avg Tokens | Use Case |
|-------|---------|-----------|----------|
| **general-purpose** | Multi-domain | 8,000 | Research, exploration, implementation |
| **code-reviewer** | Review, Quality | 5,000 | Code quality, patterns, best practices |
| **security-auditor** | Security | 6,000 | Vulnerabilities, compliance, OWASP |
| **test-automator** | Testing | 4,000 | Test coverage, TDD, quality assurance |
| **performance-engineer** | Performance | 5,500 | Optimization, profiling, scalability |
| **architect-review** | Architecture | 7,000 | System design, patterns, scalability |
| **debugger** | Debugging | 4,500 | Error resolution, troubleshooting |
| **tdd-orchestrator** | Testing, TDD | 6,000 | Test-driven development coordination |

## Configuration

### Default Configuration

Location: `plugins/multi-agent/config/default-config.json`

```json
{
  "token_budget": 200000,
  "complexity_thresholds": {
    "simple": 30,
    "moderate": 50,
    "complex": 70
  },
  "auto_approve": {
    "single_agent": true,
    "sequential": false,
    "parallel": false,
    "hierarchical": false
  },
  "cost_awareness": {
    "show_estimates": true,
    "warn_on_high_multiplier": true,
    "warn_threshold": 10
  }
}
```

### User Configuration

Location: `~/.claude/multi-agent.local.md`

Create this file to override defaults:

```markdown
---
token_budget: 150000
auto_approve_single: true
auto_approve_parallel: false
preferred_agents:
  security: "security-auditor"
  testing: "test-automator"
---

# My Preferences

Conservative token usage. Always ask before multi-agent execution.
Always involve security-auditor for authentication code.
```

See `config/multi-agent.local.example.md` for a complete template.

## Commands

### /multi-agent [request]

Analyze complexity and execute with optimal routing.

```bash
/multi-agent Review authentication module for security issues
```

### /multi-agent analyze [request]

Analyze complexity without execution (planning/budgeting).

```bash
/multi-agent analyze Implement OAuth2 authentication
```

### /multi-agent status

Show configuration and recent execution metrics.

```bash
/multi-agent status
```

### /multi-agent config

Show detailed configuration from default and user overrides.

```bash
/multi-agent config
```

## Decision Matrix

| Complexity | Pattern | Agents | Cost | Use Case |
|-----------|---------|--------|------|----------|
| 0-29 | Single | 1 | 1× | Simple, focused tasks |
| 30-49 | Sequential | 2 | 2-6× | Dependent workflows (generate → validate) |
| 50-69 | Parallel | 2-3 | 8-15× | Independent analyses (security + perf + test) |
| 70-100 | Hierarchical | 3-5 | 10-20× | Complex coordinated workflows |

## Cost-Benefit Guidelines

### When Multi-Agent is Worth It

✅ **High complexity (50+)**: Quality improvement justifies cost
✅ **Multiple domains**: Need specialist expertise
✅ **High stakes**: Critical features, security, production
✅ **Large context (30K+ tokens)**: Already high token usage
✅ **Comprehensive review requested**: User explicitly wants thoroughness

### When Single Agent is Better

✅ **Low complexity (<30)**: Simple tasks don't benefit
✅ **Budget constrained**: Token efficiency critical
✅ **Time sensitive**: Speed over thoroughness
✅ **Single domain**: Specialist not needed
✅ **Low stakes**: Non-critical code, internal tools

## Examples

### Example 1: Auto-Routed Simple Task

**Input**: "Fix typo in README.md"

**Analysis**:
- Score: 12/100 (Simple)
- Pattern: Single
- Agent: general-purpose
- Cost: ~7K tokens (1×)

**Output**: Auto-executes (no approval needed if configured)

### Example 2: Sequential with Approval

**Input**: "Implement user registration endpoint and add comprehensive tests"

**Analysis**:
- Score: 45/100 (Moderate)
- Pattern: Sequential
- Agents: general-purpose → test-automator
- Cost: ~50K tokens (4×)

**Output**: Shows cost comparison, asks approval, executes pipeline

### Example 3: Parallel Multi-Specialist

**Input**: "Comprehensive code review including security audit, performance analysis, and test coverage validation"

**Analysis**:
- Score: 75/100 (Complex)
- Pattern: Parallel
- Agents: security-auditor + performance-engineer + test-automator → aggregator
- Cost: ~180K tokens (9×)

**Output**: Explains workflow, shows cost, requires approval, executes in parallel

### Example 4: Hierarchical Coordination

**Input**: "Design and implement OAuth2 authentication with JWT tokens, comprehensive security audit, performance optimization, and full test coverage"

**Analysis**:
- Score: 90/100 (Very Complex)
- Pattern: Hierarchical
- Coordinator orchestrates: architect-review → general-purpose → parallel(security, perf, test) → synthesis
- Cost: ~200K tokens (10×)

**Output**: Presents multi-phase plan, shows expected workflow, requires approval

## Metrics and Learning

### Tracked Metrics

Location: `~/.claude/multi-agent-metrics.jsonl`

For each execution:
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

### Continuous Improvement

Metrics enable:
- **Score calibration**: Adjust thresholds based on actual complexity
- **Cost accuracy**: Improve token estimates
- **Pattern optimization**: Learn which patterns work best
- **User preferences**: Auto-approve patterns user consistently approves

## Troubleshooting

### Issue: Cost estimates inaccurate

**Cause**: Agent token usage varies by task

**Solution**: Metrics tracking will improve estimates over time. View actual usage with `/multi-agent status`.

### Issue: Wrong pattern recommended

**Cause**: Keyword detection or score calibration

**Solution**:
1. Check `/multi-agent analyze` to see reasoning
2. Manual override by adjusting complexity thresholds in config
3. Report pattern to improve future recommendations

### Issue: Budget exceeded

**Cause**: Estimated cost > token budget

**Solution**:
1. System warns and offers alternatives (sequential vs parallel, reduce scope)
2. Adjust `token_budget` in `~/.claude/multi-agent.local.md`
3. Choose simpler pattern

### Issue: Agent failure

**Cause**: Agent unavailable or error during execution

**Solution**: System automatically falls back to general-purpose agent. Check logs for details.

## Advanced Usage

### Programmatic API

Other plugins can invoke multi-agent orchestration:

```bash
# From another skill
source ${CLAUDE_PLUGIN_ROOT}/../multi-agent/scripts/lib/common.sh

complexity=$(analyze_request_complexity "$task")

if [ $complexity -gt 70 ]; then
  # Use Task tool to invoke orchestration
  Task(
    subagent_type: "multi-agent:orchestrate",
    prompt: "$task",
    config_override: {"auto_approve": true}
  )
fi
```

### Custom Agent Selection

Override automatic selection in user config:

```markdown
---
preferred_agents:
  security: "security-auditor"    # Always use for security domain
  testing: "test-automator"       # Always use for testing domain
---
```

### Cost Control

Set strict budget limits:

```markdown
---
token_budget: 100000
warn_on_high_cost: true
cost_threshold: 50000  # Warn if request > 50K tokens
---
```

## Performance Characteristics

### Token Usage

- **Single**: 1× baseline (5-15K tokens)
- **Sequential**: 2-6× (10-60K tokens)
- **Parallel**: 8-15× (80-200K tokens)
- **Hierarchical**: 10-20× (100-300K tokens)

### Quality Improvement

Based on empirical research:
- **Simple tasks (0-29)**: Negligible improvement with multi-agent
- **Moderate tasks (30-49)**: 30-50% improvement
- **Complex tasks (50-69)**: 70-90% improvement
- **Very complex (70-100)**: 90%+ improvement

### Speed

- **Single**: Fastest (1 agent execution)
- **Sequential**: Moderate (serial pipeline)
- **Parallel**: Fast (simultaneous execution + aggregation)
- **Hierarchical**: Slowest (multiple sequential phases)

## Best Practices

### DO:
✅ Start with `/multi-agent analyze` to understand cost before execution
✅ Configure `~/.claude/multi-agent.local.md` for your preferences
✅ Use simpler patterns when appropriate (avoid over-engineering)
✅ Review metrics periodically with `/multi-agent status`
✅ Trust the complexity scoring for borderline cases

### DON'T:
❌ Force multi-agent for simple tasks (token waste)
❌ Skip approval gates for expensive operations
❌ Ignore budget warnings
❌ Override pattern recommendations without understanding trade-offs

## Contributing

To add new agents to the registry:

1. Add agent definition to `scripts/lib/agent-registry.json`
2. Document capabilities and average token usage
3. Update domain keyword mappings if needed
4. Test with sample requests to validate selection

## Self-Optimization (Auto-Calibration)

The multi-agent plugin can **automatically optimize its thresholds** based on your usage patterns via integration with the [self-debugger](../self-debugger) plugin.

### How It Works

1. **Collect Data**: Each `/multi-agent` execution logs metrics (score, pattern, approved/rejected)
2. **Analyze Patterns**: Self-debugger detects when thresholds need adjustment
3. **Suggest Improvements**: Recommends threshold changes based on approval rates
4. **You Decide**: Review and apply optimizations

### Example

```bash
# After 25 executions, self-debugger detects:
⚠️  PARALLEL pattern has low approval rate (33%)
    Average score: 58
    Recommendation: Increase threshold from 50 to 60
    Impact: Fewer rejected multi-agent proposals

# You adjust your config:
~/.claude/multi-agent.local.md:
---
complexity_thresholds:
  complex: 60  # Increased based on usage patterns
---

# Future requests are more accurate!
```

### Benefits

- **Personalized thresholds** adapt to your preferences
- **Fewer false positives** reduce wasted tokens
- **Continuous improvement** as you use the system more

**Learn More**: See [SELF_OPTIMIZATION.md](SELF_OPTIMIZATION.md) for complete guide

## References

- [Complexity Scoring Details](skills/orchestrate/references/complexity-scoring.md)
- [Agent Registry Documentation](skills/orchestrate/references/agent-registry.md)
- [Coordination Patterns Guide](skills/orchestrate/references/coordination-patterns.md)
- [Self-Optimization Guide](SELF_OPTIMIZATION.md)

## License

MIT

## Version

1.0.0

---

**Summary**: This plugin bridges research insights (multi-agent achieves 90% better results at 30K+ token contexts with 15× cost) with practical implementation (complexity analysis, cost transparency, user control, graceful degradation) using proven coordination patterns.
