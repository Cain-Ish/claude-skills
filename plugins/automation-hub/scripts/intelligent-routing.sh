#!/usr/bin/env bash
# Intelligent routing using ecosystem-aware agent selection
# Based on 2025-2026 multi-agent orchestration best practices
#
# Enhanced with adaptive learning (2026 research):
# - Multi-factor agent selection (AWS, Microsoft 2026)
# - Adaptive weight optimization (arXiv 2026)
# - Statistical learning from routing outcomes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Adaptive routing learner
ADAPTIVE_LEARNER="${SCRIPT_DIR}/adaptive-routing-learner.sh"
ADAPTIVE_ENABLED=$(get_config_value ".adaptive_routing.enabled" "true")

# === Input ===
PROMPT="${1:-}"
COMPLEXITY_SCORE="${2:-0}"
RECOMMENDED_PATTERN="${3:-single}"

if [[ -z "${PROMPT}" ]]; then
    echo "Usage: $0 <prompt> <complexity_score> <pattern>" >&2
    exit 1
fi

# === Ensure Ecosystem Registry is Fresh ===

REGISTRY="${HOME}/.claude/automation-hub/ecosystem-registry.json"

# Refresh registry if older than 1 hour or missing
refresh_registry() {
    local max_age=3600  # 1 hour

    if [[ -f "${REGISTRY}" ]]; then
        local file_age
        file_age=$(( $(date +%s) - $(stat -f %m "${REGISTRY}" 2>/dev/null || stat -c %Y "${REGISTRY}" 2>/dev/null || echo 0) ))

        if [[ ${file_age} -lt ${max_age} ]]; then
            debug "Using cached registry (age: ${file_age}s)"
            return 0
        fi
    fi

    debug "Refreshing ecosystem registry..."
    bash "${SCRIPT_DIR}/discover-ecosystem.sh" "${REGISTRY}"
}

refresh_registry

# === Extract Task Intent ===

extract_task_intent() {
    local prompt="$1"

    # Extract key action verbs and domain keywords
    local intent_keywords
    intent_keywords=$(echo "${prompt}" | tr '[:upper:]' '[:lower:]' | grep -oE '\b(build|create|implement|design|test|debug|fix|optimize|refactor|migrate|analyze|review|audit|secure|deploy|monitor|document)\b' | sort -u | xargs)

    local domain_keywords
    domain_keywords=$(echo "${prompt}" | tr '[:upper:]' '[:lower:]' | grep -oE '\b(api|backend|frontend|database|security|testing|deployment|ci/cd|performance|authentication|authorization|microservices|graphql|rest|websocket)\b' | sort -u | xargs)

    echo "${intent_keywords} ${domain_keywords}"
}

# === Semantic Agent Matching ===

match_agents_to_task() {
    local keywords="$1"
    local complexity="$2"

    if [[ ! -f "${REGISTRY}" ]]; then
        debug "No registry found, returning default multi-agent"
        echo "multi-agent:orchestrate"
        return
    fi

    # Query semantic index for matching agents
    local matches
    matches=$(jq -c --arg kw "${keywords}" --argjson complexity "${complexity}" '
        .semantic_index[]
        | select(.type == "agent")
        | . + {
            match_score: (
                (.keywords | map(select(. as $k | ($kw | contains($k)))) | length) /
                ((.keywords | length) + 1)
            )
        }
        | select(.match_score > 0)
    ' "${REGISTRY}" | jq -s 'sort_by(-.match_score) | .[0:5]')

    debug "Agent matches: $(echo "${matches}" | jq -r '.[].name' | xargs)"

    # Select agents based on complexity and pattern
    if [[ ${complexity} -lt 30 ]]; then
        # Simple task - single agent
        echo "${matches}" | jq -r '.[0].name // "general-purpose"'
    elif [[ ${complexity} -lt 50 ]]; then
        # Moderate - sequential 2-3 agents
        echo "${matches}" | jq -r '[.[0:2] | .[].name] | join(",")'
    elif [[ ${complexity} -lt 70 ]]; then
        # Complex - parallel 3-5 agents
        echo "${matches}" | jq -r '[.[0:4] | .[].name] | join(",")'
    else
        # Very complex - hierarchical orchestration
        echo "multi-agent:orchestrate"
    fi
}

# === Build Agent Execution Plan ===

build_execution_plan() {
    local agents="$1"
    local pattern="$2"
    local prompt="$3"

    # Split agents by comma
    IFS=',' read -ra AGENT_LIST <<< "${agents}"

    local plan=()

    case "${pattern}" in
        single)
            # Single agent execution
            plan+=("$(jq -n \
                --arg agent "${AGENT_LIST[0]}" \
                --arg prompt "${prompt}" \
                '{
                    type: "single",
                    agent: $agent,
                    prompt: $prompt,
                    description: "Execute with single agent"
                }')")
            ;;

        sequential)
            # Sequential execution
            for i in "${!AGENT_LIST[@]}"; do
                local agent="${AGENT_LIST[$i]}"
                plan+=("$(jq -n \
                    --arg agent "${agent}" \
                    --arg step "$((i + 1))" \
                    --arg total "${#AGENT_LIST[@]}" \
                    --arg prompt "${prompt}" \
                    '{
                        type: "sequential",
                        step: ($step | tonumber),
                        total_steps: ($total | tonumber),
                        agent: $agent,
                        prompt: $prompt,
                        depends_on: (if ($step | tonumber) > 1 then [($step | tonumber) - 1] else [] end),
                        description: ("Step " + $step + "/" + $total + ": " + $agent)
                    }')")
            done
            ;;

        parallel)
            # Parallel execution
            for agent in "${AGENT_LIST[@]}"; do
                plan+=("$(jq -n \
                    --arg agent "${agent}" \
                    --arg prompt "${prompt}" \
                    '{
                        type: "parallel",
                        agent: $agent,
                        prompt: $prompt,
                        description: ("Execute in parallel: " + $agent)
                    }')")
            done
            ;;

        hierarchical)
            # Hierarchical with coordinator
            plan+=("$(jq -n \
                --arg coordinator "multi-agent:coordinator" \
                --argjson workers "$(printf '%s\n' "${AGENT_LIST[@]}" | jq -R . | jq -s .)" \
                --arg prompt "${prompt}" \
                '{
                    type: "hierarchical",
                    coordinator: $coordinator,
                    workers: $workers,
                    prompt: $prompt,
                    description: "Hierarchical orchestration with coordinator"
                }')")
            ;;
    esac

    printf '%s\n' "${plan[@]}" | jq -s '.'
}

# === Generate Recommendation ===

generate_recommendation() {
    local task_keywords
    task_keywords=$(extract_task_intent "${PROMPT}")

    debug "Task keywords: ${task_keywords}"

    local selected_agents
    selected_agents=$(match_agents_to_task "${task_keywords}" "${COMPLEXITY_SCORE}")

    debug "Selected agents: ${selected_agents}"

    # Determine pattern based on complexity and agent count
    local pattern="${RECOMMENDED_PATTERN}"

    local agent_count
    agent_count=$(echo "${selected_agents}" | tr ',' '\n' | wc -l | tr -d ' ')

    if [[ ${agent_count} -eq 1 ]]; then
        pattern="single"
    elif [[ ${agent_count} -le 3 ]] && [[ ${COMPLEXITY_SCORE} -lt 70 ]]; then
        pattern="sequential"
    elif [[ ${COMPLEXITY_SCORE} -ge 70 ]]; then
        pattern="hierarchical"
    else
        pattern="parallel"
    fi

    # Build execution plan
    local plan
    plan=$(build_execution_plan "${selected_agents}" "${pattern}" "${PROMPT}")

    # Generate recommendation JSON
    jq -n \
        --argjson complexity "${COMPLEXITY_SCORE}" \
        --arg pattern "${pattern}" \
        --arg agents "${selected_agents}" \
        --argjson plan "${plan}" \
        --arg keywords "${task_keywords}" \
        '{
            complexity_score: $complexity,
            recommended_pattern: $pattern,
            selected_agents: ($agents | split(",")),
            execution_plan: $plan,
            task_keywords: $keywords,
            rationale: (
                if $complexity < 30 then "Simple task - single agent execution"
                elif $complexity < 50 then "Moderate complexity - sequential workflow"
                elif $complexity < 70 then "Complex task - parallel execution with " + ($plan | length | tostring) + " agents"
                else "Very complex - hierarchical orchestration required"
                end
            )
        }'
}

# === Main Execution ===

recommendation=$(generate_recommendation)

# Log decision
metadata=$(echo "${recommendation}" | jq -c '{
    complexity: .complexity_score,
    pattern: .recommended_pattern,
    agents: .selected_agents,
    plan_steps: (.execution_plan | length)
}')

log_decision "intelligent_routing" "recommended" "Ecosystem-aware agent selection" "${metadata}"

# Output recommendation
echo "${recommendation}"

exit 0
