# Multi-Agent Orchestration - Quick Start

## 5-Minute Setup

### 1. Verify Installation

```bash
# Check the plugin is installed
ls -la plugins/multi-agent/

# Test the complexity analyzer
node plugins/multi-agent/scripts/lib/complexity-analyzer.js "Test request" 200000
```

If you see JSON output, you're ready!

### 2. First Command

```bash
# Simplest usage
/multi-agent Review this code for security issues

# The system will:
# 1. Analyze complexity → Show score and pattern
# 2. Estimate cost → Show 1× vs multi-agent cost
# 3. Ask approval → You decide whether to proceed
# 4. Execute → Run with recommended agents
```

### 3. Understand the Output

```
## Complexity Analysis
Score: 48/100 (Moderate)
Detected Domains: security, review
Recommended Pattern: Sequential

Cost Comparison:
- Single agent:  ~15,000 tokens
- Multi-agent:   ~60,000 tokens (4×)

Expected Improvement: 90% better results

Recommended Agents:
- security-auditor: Security audits and vulnerability assessment
- code-reviewer: Code quality and security analysis

Proceed? (y/N):
```

**What this means**:
- **Score 48**: Moderate complexity (30-49 range)
- **Sequential**: Two agents in pipeline (security → review)
- **4× cost**: Multi-agent uses 4× more tokens but gives 90% better results
- **Your choice**: Type `y` to proceed or `N` to cancel

## Common Use Cases

### Use Case 1: Quick Code Fix (Auto-Routed)

```bash
/multi-agent Fix the typo in line 42 of README.md
```

**What happens**: Score < 30 → Single agent → Auto-executes (if configured)

### Use Case 2: Security Review

```bash
/multi-agent Review authentication module for security vulnerabilities
```

**What happens**: Score 30-50 → Sequential → Ask approval → security-auditor → code-reviewer

### Use Case 3: Comprehensive Analysis

```bash
/multi-agent Comprehensive review of payment system: security, performance, and testing
```

**What happens**: Score 50-70 → Parallel → Ask approval → 3 agents run simultaneously → Aggregated report

### Use Case 4: Just Check Complexity

```bash
/multi-agent analyze Implement OAuth2 with comprehensive testing
```

**What happens**: Shows analysis without executing → Use for planning/budgeting

## Key Commands

```bash
# Execute with auto-routing
/multi-agent [your request]

# Analyze only (no execution)
/multi-agent analyze [your request]

# Check status and metrics
/multi-agent status

# View configuration
/multi-agent config
```

## Decision Guide

**When does it use multiple agents?**

| Your Request | Score | Pattern | Agents | Cost |
|-------------|-------|---------|--------|------|
| "Fix typo" | <30 | Single | 1 | 1× |
| "Implement feature + test" | 30-49 | Sequential | 2 | 2-6× |
| "Security + perf + test review" | 50-69 | Parallel | 2-3 | 8-15× |
| "Design OAuth2 + implement + full audit" | 70+ | Hierarchical | 3-5 | 10-20× |

**Simple rule**: The more domains (security, performance, testing, architecture) your request covers, the higher the score and more agents it will use.

## Configuration (Optional)

Create `~/.claude/multi-agent.local.md` to customize:

```markdown
---
token_budget: 150000              # Your token limit
auto_approve_single: true         # Skip approval for simple tasks
auto_approve_parallel: false      # Ask before expensive multi-agent
---

# My Preferences

I prefer conservative token usage. Always ask before multi-agent.
```

See `plugins/multi-agent/config/multi-agent.local.example.md` for full template.

## Understanding Costs

**Token Multipliers** (research-based):
- Single agent: **1×** baseline
- Sequential (2 agents): **2-6×**
- Parallel (3 agents): **8-15×**
- Hierarchical (4+ agents): **10-20×**

**Quality Improvement** (research-based):
- Multi-agent achieves **90% better results** on complex tasks
- Optimal at **30K+ token contexts**

**When it's worth it**:
✅ High complexity (score > 50)
✅ Multiple domains (security + performance + testing)
✅ Critical features (authentication, payments, security)
✅ Large existing context (30K+ tokens)

**When single agent is better**:
✅ Simple tasks (score < 30)
✅ Budget constraints
✅ Time-sensitive
✅ Non-critical code

## Troubleshooting

### "Budget exceeded" warning

**What**: Estimated cost > your token budget

**Fix**:
1. System offers alternatives (sequential instead of parallel, focus on priority domain)
2. Or increase budget in config: `token_budget: 300000`
3. Or proceed anyway (may hit token limits)

### "Wrong pattern recommended"

**What**: System recommends pattern you disagree with

**Why**: Score near threshold (e.g., 31 vs 29)

**Fix**: Use `/multi-agent analyze` to see reasoning, then manually choose simpler/complex pattern if needed

### "Agent not working"

**What**: Agent fails during execution

**Fix**: System automatically falls back to general-purpose agent

## Examples

### Example 1: Simple Task

```bash
$ /multi-agent Add logging to the user registration function

Analyzing...
Score: 18/100 (Simple)
Pattern: Single agent
Cost: ~7,000 tokens

Proceeding with general-purpose agent...

[Agent executes and adds logging]
Done!
```

**Why single?**: Low complexity, single domain (code change), no multi-step workflow.

### Example 2: Moderate Complexity

```bash
$ /multi-agent Implement password reset endpoint with security validation

Analyzing...
Score: 42/100 (Moderate)
Detected Domains: architecture, security
Pattern: Sequential

Cost Comparison:
- Single agent:  ~12,000 tokens
- Multi-agent:   ~48,000 tokens (4×)

Proceed? (y/N): y

Executing Phase 1: general-purpose (implementation)...
Executing Phase 2: security-auditor (validation)...

[Results from both phases presented]
```

**Why sequential?**: Two domains (architecture + security), clear dependency (implement → validate).

### Example 3: Complex Task

```bash
$ /multi-agent Full audit of authentication system: security, performance, test coverage

Analyzing...
Score: 68/100 (Complex)
Detected Domains: security, performance, testing
Pattern: Parallel

Cost: ~180,000 tokens (9×)

Proceed? (y/N): y

Launching 3 agents in parallel...
- security-auditor
- performance-engineer
- test-automator

[All agents execute simultaneously]

Aggregating results...

## Comprehensive Report
[Unified findings from all 3 specialists]
```

**Why parallel?**: Three independent domains, comprehensive analysis requested, no dependencies.

## Next Steps

1. **Try it**: Run `/multi-agent` with your actual work
2. **Review**: Check `/multi-agent status` to see metrics
3. **Tune**: Create config if you want different defaults
4. **Learn**: Read full docs in `README.md`

## Quick Reference

```bash
# Most common usage
/multi-agent [your request]           # Auto-route and execute

# Planning
/multi-agent analyze [request]        # See complexity without executing

# Monitoring
/multi-agent status                   # Check config and recent executions
/multi-agent config                   # View detailed configuration

# Testing
node scripts/lib/complexity-analyzer.js "Your request" 200000
```

---

**TL;DR**: Use `/multi-agent [request]` and the system will automatically decide whether to use one agent (simple tasks) or multiple agents (complex tasks), showing you the cost before proceeding. It's transparent, user-controlled, and optimized for quality vs token efficiency.
