#!/usr/bin/env bash
set -euo pipefail

# Resource Monitor - Checks system resources before spawning agents
# Prevents overloading system with too many parallel agents

# Thresholds (configurable via environment)
MAX_CPU_PERCENT="${MAX_CPU_PERCENT:-80}"
MAX_MEMORY_PERCENT="${MAX_MEMORY_PERCENT:-85}"
MAX_CONCURRENT_AGENTS="${MAX_CONCURRENT_AGENTS:-5}"

# Get current resource usage
get_cpu_usage() {
  # macOS and Linux compatible
  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS
    top -l 1 | grep "CPU usage" | awk '{print $3}' | sed 's/%//'
  else
    # Linux
    top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//'
  fi
}

get_memory_usage() {
  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS - calculate used/total percentage
    vm_stat | awk '
      BEGIN { free=0; active=0; inactive=0; wired=0 }
      /Pages free/ { free=$3 }
      /Pages active/ { active=$3 }
      /Pages inactive/ { inactive=$3 }
      /Pages wired/ { wired=$3 }
      END {
        total = free + active + inactive + wired
        used = active + wired
        if (total > 0) printf "%.0f", (used/total)*100
        else print "0"
      }
    '
  else
    # Linux
    free | grep Mem | awk '{printf "%.0f", ($3/$2)*100}'
  fi
}

count_running_agents() {
  # Count Claude Code subagent processes
  ps aux | grep -c "claude.*agent" | grep -v grep || echo "0"
}

# Get current stats
CPU_USAGE=$(get_cpu_usage || echo "0")
MEMORY_USAGE=$(get_memory_usage || echo "0")
RUNNING_AGENTS=$(count_running_agents)

# Remove any decimal points for comparison
CPU_USAGE_INT=${CPU_USAGE%.*}
MEMORY_USAGE_INT=${MEMORY_USAGE%.*}

# Determine if resources are available
RESOURCES_AVAILABLE=true
WARNINGS=()

if (( CPU_USAGE_INT > MAX_CPU_PERCENT )); then
  RESOURCES_AVAILABLE=false
  WARNINGS+=("CPU usage high: ${CPU_USAGE}% (threshold: ${MAX_CPU_PERCENT}%)")
fi

if (( MEMORY_USAGE_INT > MAX_MEMORY_PERCENT )); then
  RESOURCES_AVAILABLE=false
  WARNINGS+=("Memory usage high: ${MEMORY_USAGE}% (threshold: ${MAX_MEMORY_PERCENT}%)")
fi

if (( RUNNING_AGENTS >= MAX_CONCURRENT_AGENTS )); then
  RESOURCES_AVAILABLE=false
  WARNINGS+=("Too many concurrent agents: $RUNNING_AGENTS (max: $MAX_CONCURRENT_AGENTS)")
fi

# Generate recommendation
if [[ "$RESOURCES_AVAILABLE" == "true" ]]; then
  RECOMMENDATION="Resources available for agent execution"
  MAX_AGENTS_TO_SPAWN=$((MAX_CONCURRENT_AGENTS - RUNNING_AGENTS))
else
  RECOMMENDATION="System resources constrained - defer or limit agent execution"
  MAX_AGENTS_TO_SPAWN=0
fi

# Output as JSON
OUTPUT_JSON=$(jq -n \
  --argjson cpu "$CPU_USAGE_INT" \
  --argjson memory "$MEMORY_USAGE_INT" \
  --argjson running "$RUNNING_AGENTS" \
  --argjson max "$MAX_CONCURRENT_AGENTS" \
  --argjson available "$([[ "$RESOURCES_AVAILABLE" == "true" ]] && echo "true" || echo "false")" \
  --arg recommendation "$RECOMMENDATION" \
  --argjson max_spawn "$MAX_AGENTS_TO_SPAWN" \
  --argjson warnings "$(if [[ ${#WARNINGS[@]} -gt 0 ]]; then printf '%s\n' "${WARNINGS[@]}" | jq -R . | jq -s .; else echo '[]'; fi)" \
  '{
    cpu_usage_percent: $cpu,
    memory_usage_percent: $memory,
    running_agents: $running,
    max_concurrent_agents: $max,
    resources_available: $available,
    recommendation: $recommendation,
    max_agents_to_spawn: $max_spawn,
    warnings: $warnings,
    timestamp: now | strftime("%Y-%m-%dT%H:%M:%SZ")
  }')

echo "$OUTPUT_JSON"

# Exit code: 0 if resources available, 1 if constrained
if [[ "$RESOURCES_AVAILABLE" == "true" ]]; then
  exit 0
else
  exit 1
fi
