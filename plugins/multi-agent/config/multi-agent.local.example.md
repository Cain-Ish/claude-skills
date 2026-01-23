---
# Multi-Agent User Configuration Example
# Copy this file to: ~/.claude/multi-agent.local.md
# Then customize values below

# Token budget for multi-agent executions
token_budget: 150000

# Auto-approve settings (skip user confirmation)
auto_approve_single: true      # Auto-approve simple single-agent tasks
auto_approve_sequential: false # Ask before sequential pattern
auto_approve_parallel: false   # Ask before parallel pattern
auto_approve_hierarchical: false # Ask before hierarchical pattern

# Preferred agents for specific domains (optional)
# Overrides automatic agent selection
preferred_agents:
  security: "security-auditor"
  performance: "performance-engineer"
  testing: "test-automator"
  architecture: "architect-review"

# Cost awareness settings
warn_on_high_cost: true
cost_threshold: 100000  # Warn if estimated cost exceeds this

# Metrics tracking
enable_metrics: true
---

# My Multi-Agent Preferences

## Usage Philosophy

I prefer **conservative token usage** and want to approve multi-agent execution
unless the task is clearly simple (single-agent).

## Domain Priorities

- **Security**: Always use security-auditor for authentication/authorization code
- **Performance**: Use performance-engineer only for known bottlenecks
- **Testing**: Prefer comprehensive test coverage on critical features

## Budget Management

I work with a 150K token budget per session. Alert me when:
- A single request will use >50% of budget
- Cumulative usage approaches 80% of budget

## Notes

- Auto-approve simple tasks to save time on obvious cases
- Always ask before complex hierarchical coordination
- Prefer sequential over parallel when domains have dependencies
