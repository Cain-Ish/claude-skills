# Orchestrate Skill - Unified Automation Interface

**Invocation:** `/orchestrate` or `/orchestrate <command>` or natural language

## Purpose

Provide a **single entry point** for the entire automation ecosystem, intelligently routing commands to appropriate plugins while maintaining modularity.

**Research Foundation:**
- [Hub-and-Spoke Orchestration (45% faster)](https://www.onabout.ai/p/mastering-multi-agent-orchestration-architectures-patterns-roi-benchmarks-for-2025-2026)
- [Dynamic Tool Discovery in MCP](https://www.speakeasy.com/mcp/tool-design/dynamic-tool-discovery)
- [Self-Improving AI Agents](https://yoheinakajima.com/better-ways-to-build-self-improving-ai-agents/)

## How It Works

### 1. Command Dispatch

When user invokes `/orchestrate <command>`, execute:

```bash
bash /path/to/automation-hub/scripts/orchestrate-dispatch.sh <command> [args...]
```

The script handles routing to appropriate plugins.

### 2. Natural Language Intent Detection

When user provides natural language (not a known command), the dispatch script:

1. **Extracts keywords** from input
2. **Detects intent** based on keyword patterns:
   - Multi-agent: "multiple", "parallel", "coordinate", "agents", "complex"
   - Cleanup: "clean", "cleanup", "process", "orphan", "kill"
   - Reflection: "reflect", "learn", "improve", "session", "proposal"
   - Debug: "debug", "fix", "error", "bug", "issue", "scan"
   - Learning: "optimize", "proposal", "metrics", "analyze", "tune"
   - Discovery: "discover", "find", "search", "available", "ecosystem"

3. **Routes to appropriate plugin** or suggests the correct skill to invoke

### 3. Plugin Detection

Automatically detects which plugins are installed:
- `multi-agent` - For complex multi-agent coordination
- `process-janitor` - For process cleanup
- `reflect` - For session reflection
- `self-debugger` - For debugging and auto-fixes

Only shows available plugins in status dashboard.

## Commands Reference

### Core Commands

```bash
# Status and discovery
/orchestrate                    # Show unified status dashboard
/orchestrate status             # Same as above
/orchestrate discover           # Refresh ecosystem registry
/orchestrate help               # Show all commands

# Learning and optimization
/orchestrate optimize           # Run learning analysis
/orchestrate proposals          # View optimization proposals

# Feature control
/orchestrate enable <feature>   # Enable automation feature
/orchestrate disable <feature>  # Disable automation feature
```

### Plugin Routing Commands

```bash
# Multi-agent coordination
/orchestrate multi-agent <task>
# → Claude should invoke: multi-agent:orchestrate skill

# Process cleanup
/orchestrate cleanup
# → Claude should invoke: /cleanup skill or process-janitor commands

# Session reflection
/orchestrate reflect
# → Claude should invoke: /reflect skill

# Self-debugging
/orchestrate debug
# → Claude should invoke: /debug skill or self-debugger commands
```

### Natural Language Examples

```bash
# Multi-agent coordination
/orchestrate "I need multiple agents to build a secure API"
# → Detects: multi-agent intent
# → Claude invokes: multi-agent:orchestrate

# Process cleanup
/orchestrate "clean up orphaned processes"
# → Detects: cleanup intent
# → Claude invokes: process-janitor cleanup

# Session reflection
/orchestrate "reflect on this session and improve"
# → Detects: reflect intent
# → Claude invokes: reflect:reflect

# Ecosystem discovery
/orchestrate "what agents are available for security?"
# → Detects: discovery intent
# → Runs: ecosystem discovery and filters for security agents
```

## Implementation Instructions for Claude

When user invokes `/orchestrate`, you should:

### Step 1: Run Dispatch Script

```bash
bash /path/to/automation-hub/scripts/orchestrate-dispatch.sh <user_input>
```

This returns:
- Unified status dashboard (for `status` command)
- Help text (for `help` command)
- Intent detection result (for natural language)
- Routing suggestion (for plugin commands)

### Step 2: Handle Routing

Based on the dispatch script output:

**If intent is `multi-agent`:**
```
User input: "coordinate multiple agents for complex task"
Dispatch output: "🤖 Routing to multi-agent plugin..."

→ You should invoke: Task tool with subagent_type="multi-agent:orchestrate"
   with the user's task description
```

**If intent is `cleanup`:**
```
User input: "clean up processes"
Dispatch output: "🧹 Routing to process cleanup..."

→ You should invoke: /cleanup skill or process-janitor directly
```

**If intent is `reflect`:**
```
User input: "reflect on session"
Dispatch output: "💡 Routing to reflection system..."

→ You should invoke: /reflect skill
```

**If intent is `debug`:**
```
User input: "debug and fix issues"
Dispatch output: "🔧 Routing to self-debugger..."

→ You should invoke: /debug skill or self-debugger scan
```

**If intent is `learning`:**
```
User input: "optimize my settings"
Dispatch output: Runs analyze-metrics.sh and shows proposals

→ No additional action needed (already handled by script)
```

**If intent is `discovery`:**
```
User input: "find available security agents"
Dispatch output: Runs ecosystem discovery

→ Parse registry and filter for security-related agents
```

### Step 3: Provide Unified Response

Combine the dispatch script output with your plugin invocation results to give the user a seamless experience.

**Example:**
```
User: /orchestrate "build a secure GraphQL API"

You:
[Run dispatch script]
→ Detects: multi-agent intent

[Invoke multi-agent:orchestrate with task]
→ Gets: Recommended agents (graphql-architect, security-auditor)

[Unified Response]
🤖 Orchestrating Multi-Agent Coordination

Detected Complexity: High (GraphQL + Security)
Selected Agents:
  - graphql-architect (schema design)
  - security-auditor (authentication)

Pattern: Parallel Execution

[Execute multi-agent coordination...]
```

## Status Dashboard Format

When showing status, the dispatch script provides:

```
🤖 Automation Ecosystem Status

┌─ Auto-Routing ──────────────────────────┐
│ Status: ✓ Enabled                       │
│ Recent Invocations: 12 (last 7 days)    │
└─────────────────────────────────────────┘

┌─ Multi-Agent (plugin: multi-agent) ─────┐
│ Available Patterns: 4                    │
│ (single/sequential/parallel/hierarchical)│
│ Invoke: /orchestrate multi-agent <task>  │
└─────────────────────────────────────────┘

[... other plugins ...]

Quick Actions:
  /orchestrate discover    - Refresh ecosystem registry
  /orchestrate optimize    - Generate optimization proposals
  /orchestrate enable all  - Enable all automation features
```

## Benefits

1. **Single Entry Point**: Users only need to learn `/orchestrate`
2. **Intelligent Routing**: Automatically detects and routes to appropriate plugins
3. **Backwards Compatible**: Original plugin commands still work
4. **Modular Architecture**: Plugins remain independent and maintainable
5. **Ecosystem Aware**: Dynamically discovers available capabilities
6. **Natural Language**: Users can describe what they want naturally

## Integration with Other Plugins

### Multi-Agent Plugin
- Detected by: "multi-agent", "parallel", "coordinate", "agents", "complex"
- Routed to: `multi-agent:orchestrate` agent or `/multi-agent` skill
- Returns: Execution plan and results

### Process-Janitor Plugin
- Detected by: "clean", "cleanup", "process", "orphan", "kill"
- Routed to: `/cleanup` skill or direct process-janitor commands
- Returns: Cleanup report

### Reflect Plugin
- Detected by: "reflect", "learn", "improve", "session", "proposal"
- Routed to: `/reflect` skill
- Returns: Skill improvement proposals

### Self-Debugger Plugin
- Detected by: "debug", "fix", "error", "bug", "issue"
- Routed to: `/debug` skill or self-debugger scan
- Returns: Issue analysis and fix suggestions

## Error Handling

**If plugin not installed:**
```
User: /orchestrate multi-agent "task"
→ Dispatch detects multi-agent not installed
→ Response: "Multi-agent plugin not found. Install from: <link>"
```

**If ambiguous intent:**
```
User: /orchestrate "do something"
→ Cannot detect clear intent
→ Response: Shows available commands and asks for clarification
```

**If command fails:**
```
User: /orchestrate optimize
→ analyze-metrics.sh fails
→ Response: Shows error and suggests debug steps
```

## Examples

### Example 1: Status Check
```
User: /orchestrate

Output:
🤖 Automation Ecosystem Status

[Unified dashboard showing all plugin statuses]

Quick Actions:
  /orchestrate discover
  /orchestrate optimize
  /orchestrate enable all
```

### Example 2: Multi-Agent Coordination
```
User: /orchestrate "I need multiple agents to build an authentication system"

Process:
1. Run dispatch → Detects multi-agent intent
2. Invoke multi-agent:orchestrate with task
3. Return unified result

Output:
🤖 Multi-Agent Coordination

Task: Build authentication system
Selected Agents: backend-architect, security-auditor
Pattern: Sequential

[Execution results...]
```

### Example 3: Learning Optimization
```
User: /orchestrate optimize

Process:
1. Run dispatch → Executes analyze-metrics.sh
2. Generates proposals based on session data
3. Shows proposals with confidence scores

Output:
📊 Learning Analysis

Generated 2 proposals:

[P2026-01-25-001] Enable auto-approval (Confidence: 0.87)
Rationale: 90% approval rate over 43 samples

[P2026-01-25-002] Adjust threshold (Confidence: 0.75)
Rationale: Reduce false positives by 35%
```

## Testing

```bash
# Test status
/orchestrate status

# Test discovery
/orchestrate discover

# Test help
/orchestrate help

# Test natural language
/orchestrate "find security agents"
/orchestrate "clean up processes"
/orchestrate "optimize thresholds"

# Test plugin routing
/orchestrate multi-agent "complex task"
/orchestrate cleanup
/orchestrate reflect
```

---

**Status:** Production Ready
**Version:** 1.0 (Unified Interface)
**Integration:** All automation ecosystem plugins
**Research:** Hub-and-spoke + MCP dynamic discovery patterns
