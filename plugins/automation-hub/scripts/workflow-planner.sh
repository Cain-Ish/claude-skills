#!/usr/bin/env bash
# Workflow Planner - Dynamic task decomposition and orchestration planning
# Based on 2026 research: agentic workflows, task decomposition, human-in-the-loop
# Implements adaptive planning with milestone tracking and resilience

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Configuration ===

WORKFLOW_DIR="${HOME}/.claude/automation-hub/workflows"
ACTIVE_WORKFLOWS="${WORKFLOW_DIR}/active.json"
WORKFLOW_HISTORY="${WORKFLOW_DIR}/history.jsonl"
TASK_DECOMPOSITIONS="${WORKFLOW_DIR}/decompositions.json"

# Workflow patterns
PATTERN_SEQUENTIAL="sequential"
PATTERN_PARALLEL="parallel"
PATTERN_HIERARCHICAL="hierarchical"
PATTERN_COLLABORATIVE="collaborative"

# Task states
STATE_PENDING="pending"
STATE_IN_PROGRESS="in_progress"
STATE_COMPLETED="completed"
STATE_FAILED="failed"
STATE_BLOCKED="blocked"

# Planning strategies
STRATEGY_TOP_DOWN="top_down"
STRATEGY_BOTTOM_UP="bottom_up"
STRATEGY_ADAPTIVE="adaptive"

# === Initialize ===

mkdir -p "${WORKFLOW_DIR}"

# === Task Decomposition ===

decompose_task() {
    local goal="$1"
    local strategy="${2:-${STRATEGY_TOP_DOWN}}"
    local max_depth="${3:-3}"

    echo "🧩 Decomposing Task: ${goal}"
    echo "  Strategy: ${strategy}"
    echo ""

    case "${strategy}" in
        "${STRATEGY_TOP_DOWN}")
            decompose_top_down "${goal}" 0 "${max_depth}"
            ;;

        "${STRATEGY_BOTTOM_UP}")
            decompose_bottom_up "${goal}"
            ;;

        "${STRATEGY_ADAPTIVE}")
            decompose_adaptive "${goal}" "${max_depth}"
            ;;

        *)
            echo "Unknown strategy: ${strategy}" >&2
            return 1
            ;;
    esac
}

decompose_top_down() {
    local goal="$1"
    local current_depth="$2"
    local max_depth="$3"

    if [[ ${current_depth} -ge ${max_depth} ]]; then
        # Reached max depth, return atomic task
        create_atomic_task "${goal}" "${current_depth}"
        return 0
    fi

    # Analyze goal and break into sub-tasks
    local sub_tasks
    sub_tasks=$(analyze_goal_breakdown "${goal}")

    if [[ "${sub_tasks}" == "atomic" ]]; then
        # Task cannot be further decomposed
        create_atomic_task "${goal}" "${current_depth}"
        return 0
    fi

    # Create parent task
    local task_id
    task_id=$(create_task "${goal}" "${STATE_PENDING}" "${current_depth}")

    # Decompose sub-tasks recursively
    local indent
    indent=$(printf '%*s' $((current_depth * 2)) '')

    echo "${indent}└─ ${goal}"

    local next_depth=$((current_depth + 1))

    while IFS= read -r sub_task; do
        if [[ -n "${sub_task}" ]] && [[ "${sub_task}" != "null" ]]; then
            decompose_top_down "${sub_task}" "${next_depth}" "${max_depth}"
        fi
    done <<< "${sub_tasks}"
}

decompose_bottom_up() {
    local goal="$1"

    # Start with known atomic tasks and build upward
    # Simplified for demonstration
    echo "Bottom-up decomposition (simplified):"
    echo "  1. Identify required capabilities"
    echo "  2. Map capabilities to atomic tasks"
    echo "  3. Compose tasks into sub-goals"
    echo "  4. Combine sub-goals into main goal"
}

decompose_adaptive() {
    local goal="$1"
    local max_depth="$2"

    # Adaptive: start top-down, but adjust based on complexity
    local complexity
    complexity=$(estimate_task_complexity "${goal}")

    echo "Adaptive decomposition (complexity: ${complexity}):"

    if [[ ${complexity} -lt 30 ]]; then
        # Simple task, minimal decomposition
        decompose_top_down "${goal}" 0 2
    elif [[ ${complexity} -lt 70 ]]; then
        # Moderate task, standard decomposition
        decompose_top_down "${goal}" 0 "${max_depth}"
    else
        # Complex task, deep decomposition
        decompose_top_down "${goal}" 0 $((max_depth + 1))
    fi
}

analyze_goal_breakdown() {
    local goal="$1"

    # Simplified goal analysis (production: use LLM)
    # Returns sub-tasks or "atomic" if cannot decompose

    # Check for keywords indicating decomposable task
    if echo "${goal}" | grep -qiE "build|create|implement|develop|design"; then
        # Decomposable into design + implement + test
        echo "Design ${goal}"
        echo "Implement ${goal}"
        echo "Test ${goal}"
    elif echo "${goal}" | grep -qiE "and|then|after|before"; then
        # Multiple steps indicated
        echo "Step 1 of ${goal}"
        echo "Step 2 of ${goal}"
    else
        # Atomic task
        echo "atomic"
    fi
}

estimate_task_complexity() {
    local task="$1"

    # Simplified complexity estimation (production: use LLM scoring)
    local complexity=0

    # Word count indicator
    local word_count
    word_count=$(echo "${task}" | wc -w | tr -d ' ')
    complexity=$((complexity + word_count * 2))

    # Complexity keywords
    if echo "${task}" | grep -qiE "complex|multiple|integrate|coordinate"; then
        complexity=$((complexity + 20))
    fi

    if echo "${task}" | grep -qiE "build|implement|develop|create"; then
        complexity=$((complexity + 15))
    fi

    if echo "${task}" | grep -qiE "test|validate|verify"; then
        complexity=$((complexity + 10))
    fi

    echo "${complexity}"
}

# === Workflow Creation ===

create_workflow() {
    local goal="$1"
    local pattern="${2:-${PATTERN_SEQUENTIAL}}"
    local human_in_loop="${3:-false}"

    local timestamp
    timestamp=$(date -u +%s)

    local workflow_id
    workflow_id="${timestamp}_$(echo "${goal}" | sed 's/[^a-zA-Z0-9]/_/g' | cut -c1-20)"

    local workflow
    workflow=$(jq -n \
        --arg id "${workflow_id}" \
        --arg goal "${goal}" \
        --arg pattern "${pattern}" \
        --arg hitl "${human_in_loop}" \
        --arg timestamp "${timestamp}" \
        '{
            id: $id,
            goal: $goal,
            pattern: $pattern,
            human_in_loop: ($hitl | test("true")),
            state: "pending",
            tasks: [],
            milestones: [],
            created_at: ($timestamp | tonumber),
            updated_at: ($timestamp | tonumber)
        }')

    if [[ ! -f "${ACTIVE_WORKFLOWS}" ]]; then
        echo '{"workflows":[]}' > "${ACTIVE_WORKFLOWS}"
    fi

    local updated_workflows
    updated_workflows=$(jq --argjson workflow "${workflow}" \
        '.workflows += [$workflow]' \
        "${ACTIVE_WORKFLOWS}")

    echo "${updated_workflows}" > "${ACTIVE_WORKFLOWS}"

    echo "${workflow_id}"
}

# === Task Management ===

create_task() {
    local description="$1"
    local state="${2:-${STATE_PENDING}}"
    local depth="${3:-0}"

    local timestamp
    timestamp=$(date -u +%s)

    local task_id
    task_id=$(date +%s%N)

    echo "${task_id}"
}

create_atomic_task() {
    local description="$1"
    local depth="$2"

    local indent
    indent=$(printf '%*s' $((depth * 2)) '')

    echo "${indent}  ⚫ ${description} (atomic)"
}

add_task_to_workflow() {
    local workflow_id="$1"
    local task_description="$2"
    local dependencies="${3:-[]}"

    local task_id
    task_id=$(date +%s%N)

    local task
    task=$(jq -n \
        --arg id "${task_id}" \
        --arg description "${task_description}" \
        --argjson deps "${dependencies}" \
        '{
            id: $id,
            description: $description,
            state: "pending",
            dependencies: $deps,
            result: null
        }')

    local updated_workflows
    updated_workflows=$(jq --arg wid "${workflow_id}" --argjson task "${task}" \
        '(.workflows[] | select(.id == $wid) | .tasks) += [$task]' \
        "${ACTIVE_WORKFLOWS}")

    echo "${updated_workflows}" > "${ACTIVE_WORKFLOWS}"

    echo "${task_id}"
}

update_task_state() {
    local workflow_id="$1"
    local task_id="$2"
    local new_state="$3"
    local result="${4:-}"

    local updated_workflows
    updated_workflows=$(jq --arg wid "${workflow_id}" --arg tid "${task_id}" --arg state "${new_state}" --arg result "${result}" \
        '(.workflows[] | select(.id == $wid) | .tasks[] | select(.id == $tid)) |= (
            .state = $state |
            if $result != "" then .result = $result else . end
        )' \
        "${ACTIVE_WORKFLOWS}")

    echo "${updated_workflows}" > "${ACTIVE_WORKFLOWS}"

    # Check if workflow is complete
    check_workflow_completion "${workflow_id}"
}

# === Milestone Tracking ===

add_milestone() {
    local workflow_id="$1"
    local milestone_description="$2"
    local required_tasks="$3"

    local timestamp
    timestamp=$(date -u +%s)

    local milestone
    milestone=$(jq -n \
        --arg description "${milestone_description}" \
        --argjson tasks "${required_tasks}" \
        --arg timestamp "${timestamp}" \
        '{
            description: $description,
            required_tasks: $tasks,
            achieved: false,
            achieved_at: null
        }')

    local updated_workflows
    updated_workflows=$(jq --arg wid "${workflow_id}" --argjson milestone "${milestone}" \
        '(.workflows[] | select(.id == $wid) | .milestones) += [$milestone]' \
        "${ACTIVE_WORKFLOWS}")

    echo "${updated_workflows}" > "${ACTIVE_WORKFLOWS}"
}

check_milestone_achievement() {
    local workflow_id="$1"

    # Check each milestone
    jq -c --arg wid "${workflow_id}" \
        '.workflows[] | select(.id == $wid) | .milestones[]' \
        "${ACTIVE_WORKFLOWS}" | while IFS= read -r milestone; do

        local description
        description=$(echo "${milestone}" | jq -r '.description')

        local required_tasks
        required_tasks=$(echo "${milestone}" | jq -c '.required_tasks[]')

        local all_complete=true

        while IFS= read -r task_id; do
            local task_state
            task_state=$(jq -r --arg wid "${workflow_id}" --arg tid "${task_id}" \
                '.workflows[] | select(.id == $wid) | .tasks[] | select(.id == $tid) | .state' \
                "${ACTIVE_WORKFLOWS}")

            if [[ "${task_state}" != "${STATE_COMPLETED}" ]]; then
                all_complete=false
                break
            fi
        done <<< "${required_tasks}"

        if [[ "${all_complete}" == "true" ]]; then
            echo "✓ Milestone achieved: ${description}"

            # Mark milestone as achieved
            local timestamp
            timestamp=$(date -u +%s)

            local updated_workflows
            updated_workflows=$(jq --arg wid "${workflow_id}" --arg desc "${description}" --arg ts "${timestamp}" \
                '(.workflows[] | select(.id == $wid) | .milestones[] | select(.description == $desc)) |= (
                    .achieved = true |
                    .achieved_at = ($ts | tonumber)
                )' \
                "${ACTIVE_WORKFLOWS}")

            echo "${updated_workflows}" > "${ACTIVE_WORKFLOWS}"
        fi
    done
}

# === Workflow Execution ===

check_workflow_completion() {
    local workflow_id="$1"

    local total_tasks
    total_tasks=$(jq -r --arg wid "${workflow_id}" \
        '.workflows[] | select(.id == $wid) | .tasks | length' \
        "${ACTIVE_WORKFLOWS}")

    local completed_tasks
    completed_tasks=$(jq -r --arg wid "${workflow_id}" \
        '.workflows[] | select(.id == $wid) | .tasks | map(select(.state == "completed")) | length' \
        "${ACTIVE_WORKFLOWS}")

    if [[ ${completed_tasks} -eq ${total_tasks} ]]; then
        echo "✓ Workflow ${workflow_id} completed"

        # Move to history
        local workflow
        workflow=$(jq -c --arg wid "${workflow_id}" \
            '.workflows[] | select(.id == $wid)' \
            "${ACTIVE_WORKFLOWS}")

        echo "${workflow}" >> "${WORKFLOW_HISTORY}"

        # Remove from active
        local updated_workflows
        updated_workflows=$(jq --arg wid "${workflow_id}" \
            '.workflows |= map(select(.id != $wid))' \
            "${ACTIVE_WORKFLOWS}")

        echo "${updated_workflows}" > "${ACTIVE_WORKFLOWS}"
    fi
}

# === Workflow Statistics ===

workflow_stats() {
    echo "📊 Workflow Statistics"
    echo ""

    if [[ ! -f "${ACTIVE_WORKFLOWS}" ]]; then
        echo "No active workflows"
        return 0
    fi

    local active_count
    active_count=$(jq '.workflows | length' "${ACTIVE_WORKFLOWS}")

    echo "┌─ Active Workflows ──────────────────────┐"
    echo "│ Count: ${active_count}"
    echo "└─────────────────────────────────────────┘"
    echo ""

    if [[ ${active_count} -gt 0 ]]; then
        jq -r '.workflows[] |
            "Workflow: " + .id + "\n" +
            "  Goal: " + .goal + "\n" +
            "  Pattern: " + .pattern + "\n" +
            "  Tasks: " + (.tasks | length | tostring) + " total, " +
            (.tasks | map(select(.state == "completed")) | length | tostring) + " completed\n"' \
            "${ACTIVE_WORKFLOWS}"
    fi
}

# === Main ===

main() {
    local command="${1:-stats}"
    shift || true

    case "${command}" in
        decompose)
            if [[ $# -eq 0 ]]; then
                echo "Usage: workflow-planner.sh decompose <goal> [strategy] [max_depth]"
                exit 1
            fi

            decompose_task "$@"
            ;;

        create)
            if [[ $# -eq 0 ]]; then
                echo "Usage: workflow-planner.sh create <goal> [pattern] [human_in_loop]"
                exit 1
            fi

            create_workflow "$@"
            ;;

        add-task)
            if [[ $# -lt 2 ]]; then
                echo "Usage: workflow-planner.sh add-task <workflow_id> <description> [dependencies_json]"
                exit 1
            fi

            add_task_to_workflow "$@"
            ;;

        update-task)
            if [[ $# -lt 3 ]]; then
                echo "Usage: workflow-planner.sh update-task <workflow_id> <task_id> <state> [result]"
                exit 1
            fi

            update_task_state "$@"
            ;;

        add-milestone)
            if [[ $# -lt 3 ]]; then
                echo "Usage: workflow-planner.sh add-milestone <workflow_id> <description> <required_tasks_json>"
                exit 1
            fi

            add_milestone "$@"
            ;;

        check-milestones)
            if [[ $# -eq 0 ]]; then
                echo "Usage: workflow-planner.sh check-milestones <workflow_id>"
                exit 1
            fi

            check_milestone_achievement "$1"
            ;;

        stats)
            workflow_stats
            ;;

        *)
            cat <<'EOF'
Workflow Planner - Dynamic task decomposition and orchestration planning

USAGE:
  workflow-planner.sh decompose <goal> [strategy] [max_depth]
  workflow-planner.sh create <goal> [pattern] [human_in_loop]
  workflow-planner.sh add-task <workflow_id> <description> [dependencies_json]
  workflow-planner.sh update-task <workflow_id> <task_id> <state> [result]
  workflow-planner.sh add-milestone <workflow_id> <description> <required_tasks_json>
  workflow-planner.sh check-milestones <workflow_id>
  workflow-planner.sh stats

DECOMPOSITION STRATEGIES:
  top_down        Break goal into sub-goals recursively
  bottom_up       Identify atomic tasks, compose upward
  adaptive        Adjust depth based on complexity

WORKFLOW PATTERNS:
  sequential      Tasks execute in order
  parallel        Tasks execute concurrently
  hierarchical    Nested task dependencies
  collaborative   Multiple agents coordinate

TASK STATES:
  pending         Awaiting execution
  in_progress     Currently executing
  completed       Successfully finished
  failed          Execution failed
  blocked         Waiting on dependencies

EXAMPLES:
  # Decompose complex goal
  workflow-planner.sh decompose \
    "build REST API with authentication" \
    adaptive \
    3

  # Create workflow with human-in-the-loop
  workflow-planner.sh create \
    "implement user authentication" \
    sequential \
    true

  # Add task with dependencies
  workflow-planner.sh add-task \
    "1737840123_implement_user_auth" \
    "Design database schema" \
    '["1737840123456789000"]'

  # Update task state
  workflow-planner.sh update-task \
    "1737840123_implement_user_auth" \
    "1737840123456789000" \
    completed \
    "Schema designed and reviewed"

  # Add milestone
  workflow-planner.sh add-milestone \
    "1737840123_implement_user_auth" \
    "Backend implementation complete" \
    '["task1","task2","task3"]'

RESEARCH:
  - 30-50% process time reduction (Deloitte 2026)
  - Specialized multi-agent systems (Vellum)
  - Human-in-the-loop integration (OneReach)
  - Adaptive task decomposition (Analytics Vidhya)

EOF
            ;;
    esac
}

# Execute
main "$@"

exit 0
