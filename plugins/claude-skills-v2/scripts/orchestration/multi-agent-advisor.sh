#!/usr/bin/env bash
set -euo pipefail

# Multi-Agent Orchestration Advisor
# Analyzes tasks and recommends parallel vs sequential agent execution

# Input: Task description via stdin or argument
TASK_DESCRIPTION="${1:-$(cat)}"

# Output format
OUTPUT_JSON='{
  "recommendation": "",
  "reasoning": "",
  "agents": [],
  "execution_mode": ""
}'

# Function to analyze task for parallelization potential
analyze_task() {
  local task="$TASK_DESCRIPTION"

  # Indicators of parallel-suitable tasks
  local parallel_indicators=(
    "review.*and.*test"
    "check.*and.*validate"
    "analyze.*and.*audit"
    "multiple.*independent"
    "both.*and"
    "all.*of"
  )

  # Indicators of sequential tasks
  local sequential_indicators=(
    "then"
    "after"
    "first.*then"
    "before"
    "depends on"
    "requires"
  )

  # Count indicators
  local parallel_count=0
  local sequential_count=0

  for indicator in "${parallel_indicators[@]}"; do
    if echo "$task" | grep -qiE "$indicator"; then
      ((parallel_count++)) || true
    fi
  done

  for indicator in "${sequential_indicators[@]}"; do
    if echo "$task" | grep -qiE "$indicator"; then
      ((sequential_count++)) || true
    fi
  done

  # Make recommendation
  if [[ $parallel_count -gt $sequential_count ]]; then
    echo "parallel"
  elif [[ $sequential_count -gt $parallel_count ]]; then
    echo "sequential"
  else
    echo "unknown"
  fi
}

# Recommend agents based on task
recommend_agents() {
  local task="$TASK_DESCRIPTION"
  local agents=()

  # Code review indicators
  if echo "$task" | grep -qiE "(review|check|audit).*code"; then
    agents+=("code-reviewer")
  fi

  # Security indicators
  if echo "$task" | grep -qiE "(security|vulnerability|auth|credential)"; then
    agents+=("security-auditor")
  fi

  # Testing indicators
  if echo "$task" | grep -qiE "(test|coverage|spec)"; then
    agents+=("test-automator")
  fi

  # Performance indicators
  if echo "$task" | grep -qiE "(performance|optimize|slow|memory)"; then
    agents+=("performance-engineer")
  fi

  # Diagnostics indicators
  if echo "$task" | grep -qiE "(error|bug|issue|problem|fail)"; then
    agents+=("debugger")
  fi

  # Plugin development indicators
  if echo "$task" | grep -qiE "(plugin|manifest|hook|agent)"; then
    agents+=("plugin-diagnostician")
  fi

  # Output as JSON array
  printf '%s\n' "${agents[@]}" | jq -R . | jq -s .
}

# Main analysis
MODE=$(analyze_task)
AGENTS=$(recommend_agents)
AGENT_COUNT=$(echo "$AGENTS" | jq 'length')

# Generate reasoning
REASONING=""
case $MODE in
  parallel)
    REASONING="Task contains multiple independent checks that can run simultaneously. Use parallel execution with multiple Task tool calls in a single message."
    EXECUTION_MODE="parallel"
    ;;
  sequential)
    REASONING="Task has dependencies between steps. Execute agents sequentially, waiting for each to complete before starting the next."
    EXECUTION_MODE="sequential"
    ;;
  *)
    if [[ $AGENT_COUNT -gt 1 ]]; then
      REASONING="Multiple agents recommended but execution order unclear. Default to parallel for efficiency unless dependencies exist."
      EXECUTION_MODE="parallel_suggested"
    else
      REASONING="Single agent sufficient for this task."
      EXECUTION_MODE="single"
    fi
    ;;
esac

# Generate recommendation
if [[ $AGENT_COUNT -eq 0 ]]; then
  RECOMMENDATION="No specialized agents needed. Handle with general-purpose agent or direct tool usage."
elif [[ $AGENT_COUNT -eq 1 ]]; then
  AGENT_NAME=$(echo "$AGENTS" | jq -r '.[0]')
  RECOMMENDATION="Use single agent: $AGENT_NAME"
elif [[ "$EXECUTION_MODE" == "parallel" ]] || [[ "$EXECUTION_MODE" == "parallel_suggested" ]]; then
  RECOMMENDATION="Use $AGENT_COUNT agents in parallel: $(echo "$AGENTS" | jq -r 'join(", ")')"
else
  RECOMMENDATION="Use $AGENT_COUNT agents sequentially: $(echo "$AGENTS" | jq -r 'join(" → ")')"
fi

# Build output JSON
OUTPUT_JSON=$(jq -n \
  --arg rec "$RECOMMENDATION" \
  --arg reason "$REASONING" \
  --argjson agents "$AGENTS" \
  --arg mode "$EXECUTION_MODE" \
  '{
    recommendation: $rec,
    reasoning: $reason,
    agents: $agents,
    execution_mode: $mode,
    agent_count: ($agents | length),
    task_analyzed: true
  }')

echo "$OUTPUT_JSON"
exit 0
