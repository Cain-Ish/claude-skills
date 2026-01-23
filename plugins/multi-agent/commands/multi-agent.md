---
name: multi-agent
description: Intelligently orchestrate single or multi-agent execution with complexity analysis and cost transparency
usage: |
  /multi-agent [request]       - Auto-analyze and execute
  /multi-agent analyze [req]   - Analyze complexity only (no execution)
  /multi-agent status          - Show metrics and configuration
  /multi-agent config          - Show current configuration
examples:
  - /multi-agent Review this PR for security and performance issues
  - /multi-agent analyze Implement OAuth2 authentication
  - /multi-agent status
---

# Multi-Agent Orchestration Command

Intelligent routing and coordination of single or multiple agents based on task complexity.

## Command Modes

### Mode 1: Execute (Default)

**Syntax**: `/multi-agent [request]`

**Example**: `/multi-agent Review authentication module for security vulnerabilities and performance issues`

**Behavior**:
1. Analyze request complexity using task-analyzer agent
2. Present complexity score, pattern recommendation, and cost estimate
3. Request user approval (unless auto-approve is configured)
4. Execute using recommended pattern (single/sequential/parallel/hierarchical)
5. Return results

**Use this when**: You want to execute a task with optimal agent coordination

---

### Mode 2: Analyze Only

**Syntax**: `/multi-agent analyze [request]`

**Example**: `/multi-agent analyze Implement OAuth2 with comprehensive testing`

**Behavior**:
1. Analyze request complexity
2. Show recommendations and cost estimates
3. **Do not execute** - just show analysis
4. Useful for planning and budgeting

**Use this when**: You want to understand complexity and cost before committing to execution

---

### Mode 3: Status

**Syntax**: `/multi-agent status`

**Behavior**:
1. Show current configuration (token budget, auto-approve settings)
2. Display recent execution metrics (if available)
3. Show agent registry status
4. Report plugin version

**Use this when**: Checking configuration or reviewing recent multi-agent executions

---

### Mode 4: Config

**Syntax**: `/multi-agent config`

**Behavior**:
1. Display current configuration from default and user overrides
2. Show path to user config file
3. Explain how to customize settings

**Use this when**: Understanding or troubleshooting configuration

---

## Implementation

### Parse Command Arguments

```bash
#!/bin/bash

# Get command arguments
COMMAND="$1"
shift
REQUEST="$*"

# Determine mode
case "$COMMAND" in
  "analyze")
    MODE="analyze"
    ;;
  "status")
    MODE="status"
    ;;
  "config")
    MODE="config"
    ;;
  *)
    # Default mode: execute
    MODE="execute"
    REQUEST="$COMMAND $REQUEST"
    ;;
esac
```

### Mode: Execute

```bash
if [ "$MODE" = "execute" ]; then
  if [ -z "$REQUEST" ]; then
    echo "Usage: /multi-agent [request]"
    echo "Example: /multi-agent Review code for security and performance"
    exit 1
  fi

  # Invoke orchestrate skill
  echo "Analyzing and executing: $REQUEST"
  # The skill will handle: analyze → approve → execute → return results
fi
```

**Implementation**: Invoke the `orchestrate` skill with the user's request. The skill handles the full workflow.

### Mode: Analyze

```bash
if [ "$MODE" = "analyze" ]; then
  if [ -z "$REQUEST" ]; then
    echo "Usage: /multi-agent analyze [request]"
    exit 1
  fi

  echo "Analyzing complexity (no execution)..."

  # Invoke task-analyzer agent directly
  # This returns JSON with complexity analysis
  # Format and display the analysis without executing
fi
```

**Implementation**: Invoke task-analyzer agent and display results in user-friendly format without proceeding to execution.

### Mode: Status

```bash
if [ "$MODE" = "status" ]; then
  echo "# Multi-Agent Orchestration Status"
  echo

  # Show configuration
  echo "## Configuration"
  CONFIG_FILE="$HOME/.claude/multi-agent.local.md"
  DEFAULT_CONFIG="${CLAUDE_PLUGIN_ROOT}/config/default-config.json"

  if [ -f "$CONFIG_FILE" ]; then
    echo "User config: $CONFIG_FILE"
    TOKEN_BUDGET=$(grep "^token_budget:" "$CONFIG_FILE" | awk '{print $2}')
    AUTO_APPROVE_SINGLE=$(grep "^auto_approve_single:" "$CONFIG_FILE" | awk '{print $2}')
  else
    echo "Using default config (no user overrides)"
    TOKEN_BUDGET=$(jq -r '.token_budget' "$DEFAULT_CONFIG")
    AUTO_APPROVE_SINGLE=$(jq -r '.auto_approve.single_agent' "$DEFAULT_CONFIG")
  fi

  echo "- Token Budget: ${TOKEN_BUDGET:-200000}"
  echo "- Auto-approve Single: ${AUTO_APPROVE_SINGLE:-true}"
  echo

  # Show metrics if available
  METRICS_FILE="$HOME/.claude/multi-agent-metrics.jsonl"
  if [ -f "$METRICS_FILE" ]; then
    echo "## Recent Executions"
    echo
    tail -5 "$METRICS_FILE" | jq -r '
      "[\(.timestamp)] Score: \(.complexity_score) | Pattern: \(.pattern) | Cost: ~\(.cost_estimate) tokens"
    '
  else
    echo "No execution metrics yet"
  fi

  echo
  echo "## Agent Registry"
  REGISTRY="${CLAUDE_PLUGIN_ROOT}/scripts/lib/agent-registry.json"
  AGENT_COUNT=$(jq '.agents | length' "$REGISTRY")
  echo "Available agents: $AGENT_COUNT"
  jq -r '.agents[] | "- \(.id): \(.description)"' "$REGISTRY"

  echo
  echo "Plugin version: $(jq -r '.version' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json")"
fi
```

**Output Example**:
```
# Multi-Agent Orchestration Status

## Configuration
User config: /Users/user/.claude/multi-agent.local.md
- Token Budget: 150000
- Auto-approve Single: true

## Recent Executions

[2026-01-23T14:32:15Z] Score: 45 | Pattern: sequential | Cost: ~50000 tokens
[2026-01-23T15:10:42Z] Score: 78 | Pattern: hierarchical | Cost: ~180000 tokens

## Agent Registry
Available agents: 8
- general-purpose: Research, multi-step tasks, and code exploration
- code-reviewer: Code quality, security, and performance analysis
- security-auditor: Security audits, compliance, and vulnerability assessment
- test-automator: Test automation and quality assurance
- performance-engineer: Performance optimization and scalability
- architect-review: Architecture review and design patterns
- debugger: Error resolution and troubleshooting
- tdd-orchestrator: Test-driven development coordination

Plugin version: 1.0.0
```

### Mode: Config

```bash
if [ "$MODE" = "config" ]; then
  echo "# Multi-Agent Configuration"
  echo

  DEFAULT_CONFIG="${CLAUDE_PLUGIN_ROOT}/config/default-config.json"
  USER_CONFIG="$HOME/.claude/multi-agent.local.md"

  echo "## Default Configuration"
  echo "Location: $DEFAULT_CONFIG"
  echo
  cat "$DEFAULT_CONFIG" | jq '.'
  echo

  if [ -f "$USER_CONFIG" ]; then
    echo "## User Overrides"
    echo "Location: $USER_CONFIG"
    echo
    cat "$USER_CONFIG"
  else
    echo "## User Overrides"
    echo "No user configuration found."
    echo
    echo "To customize, create: $USER_CONFIG"
    echo
    echo "Example:"
    echo "---"
    echo "token_budget: 150000"
    echo "auto_approve_single: true"
    echo "auto_approve_parallel: false"
    echo "---"
    echo
    echo "# My Preferences"
    echo "Conservative token usage, always ask before multi-agent."
  fi

  echo
  echo "Configuration is loaded in this priority:"
  echo "1. User config (~/.claude/multi-agent.local.md) - highest priority"
  echo "2. Default config (plugin/config/default-config.json) - fallback"
fi
```

## Usage Examples

### Example 1: Simple Request

```bash
$ /multi-agent Fix typo in README.md

Analyzing and executing: Fix typo in README.md

## Complexity Analysis
Score: 12/100 (Simple task)
Pattern: Single agent
Cost: ~7,000 tokens

Proceeding with single agent execution...

[general-purpose agent executes and fixes typo]

Done! Typo fixed in README.md.
```

### Example 2: Moderate Complexity with Approval

```bash
$ /multi-agent Review authentication code for security vulnerabilities

Analyzing and executing: Review authentication code for security vulnerabilities

## Complexity Analysis
Score: 52/100 (Moderate complexity)
Detected Domains: security, review
Recommended Pattern: Sequential

Cost Comparison:
- Single agent:  ~15,000 tokens
- Multi-agent:   ~60,000 tokens (4×)

Expected Improvement: 90% better results with multi-agent coordination

Recommended Agents:
- security-auditor: Security audits and vulnerability assessment
- code-reviewer: Code quality and security analysis

Reasoning: Two-phase analysis ensures comprehensive security review followed by
code quality validation. Sequential pattern allows reviewer to validate and
expand on security findings.

Proceed with sequential execution? (y/N): y

Executing Phase 1: security-auditor...
[security audit results]

Executing Phase 2: code-reviewer...
[code review results]

[Combined results presented]
```

### Example 3: Analyze Without Execution

```bash
$ /multi-agent analyze Implement OAuth2 authentication with comprehensive testing

Analyzing complexity (no execution)...

## Complexity Analysis
Score: 85/100 (High complexity)
Detected Domains: architecture, security, testing
Recommended Pattern: Hierarchical coordination

Cost Comparison:
- Single agent:  ~20,000 tokens
- Multi-agent:   ~200,000 tokens (10×)

Recommended Workflow:
1. Architecture design (architect-review)
2. Implementation (general-purpose)
3. Parallel quality assurance:
   - Security audit (security-auditor)
   - Test suite (test-automator)
4. Synthesis (coordinator)

Reasoning: Complex feature requiring design, implementation, and multi-domain
validation. Hierarchical coordination ensures proper sequencing and comprehensive
specialist review.

Note: Analysis only - not executing. Use '/multi-agent [request]' to execute.
```

### Example 4: Check Status

```bash
$ /multi-agent status

# Multi-Agent Orchestration Status

## Configuration
User config: /Users/user/.claude/multi-agent.local.md
- Token Budget: 150000
- Auto-approve Single: true

## Recent Executions
[2026-01-23T14:32:15Z] Score: 45 | Pattern: sequential | Cost: ~50000 tokens
[2026-01-23T15:10:42Z] Score: 78 | Pattern: hierarchical | Cost: ~180000 tokens

## Agent Registry
Available agents: 8
[agent list...]

Plugin version: 1.0.0
```

## Error Handling

### Invalid Request

```bash
$ /multi-agent

Usage: /multi-agent [request]
Example: /multi-agent Review code for security and performance

Available modes:
  /multi-agent [request]       - Analyze and execute
  /multi-agent analyze [req]   - Analyze only (no execution)
  /multi-agent status          - Show configuration and metrics
  /multi-agent config          - Show detailed configuration
```

### Budget Exceeded

```bash
$ /multi-agent [complex request]

## Complexity Analysis
Score: 92/100 (Very high complexity)
...
Cost: ~250,000 tokens (12×)

⚠️  Warning: Estimated cost (250,000) exceeds your budget (150,000)

Options:
1. Sequential pattern (reduce to 2 agents): ~90,000 tokens
2. Focus on security only: ~60,000 tokens
3. Proceed anyway (may hit token limits)

Choose option (1-3):
```

---

This command provides a user-friendly interface to the multi-agent orchestration system with clear modes for different use cases.
