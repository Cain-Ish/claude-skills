#!/usr/bin/env bash
# Orchestrate: Unified interface for entire automation ecosystem
# Routes commands to appropriate plugins while maintaining modularity

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Parse Input ===

COMMAND="${1:-status}"
shift || true
ARGS=("$@")

# Join args for natural language processing (handle empty array)
if [[ ${#ARGS[@]} -gt 0 ]]; then
    FULL_INPUT="${COMMAND} ${ARGS[*]}"
else
    FULL_INPUT="${COMMAND}"
fi

# === Plugin Detection ===

detect_available_plugins() {
    local plugins_base="${HOME}/.claude/plugins"
    local project_plugins="$(pwd)/plugins"

    local available=()

    # Check for known plugins
    for plugin in "multi-agent" "process-janitor" "reflect" "self-debugger"; do
        if [[ -d "${plugins_base}/${plugin}" ]] || [[ -d "${project_plugins}/${plugin}" ]]; then
            available+=("${plugin}")
        fi
    done

    printf '%s\n' "${available[@]}"
}

# === Intent Detection ===

detect_intent() {
    local input="$1"
    local input_lower
    input_lower=$(echo "${input}" | tr '[:upper:]' '[:lower:]')

    # Multi-agent keywords
    if echo "${input_lower}" | grep -qE '\b(multiple|parallel|coordinate|agents|complex|hierarchical|sequential)\b'; then
        echo "multi-agent"
        return
    fi

    # Process cleanup keywords
    if echo "${input_lower}" | grep -qE '\b(clean|cleanup|process|orphan|kill|stop|janitor)\b'; then
        echo "process-janitor"
        return
    fi

    # Reflection keywords
    if echo "${input_lower}" | grep -qE '\b(reflect|learn|improve|session|proposal|skill)\b'; then
        echo "reflect"
        return
    fi

    # Debug keywords
    if echo "${input_lower}" | grep -qE '\b(debug|fix|error|bug|issue|scan|analyze)\b'; then
        echo "self-debugger"
        return
    fi

    # Optimization/learning keywords
    if echo "${input_lower}" | grep -qE '\b(optimize|proposal|metrics|analyze|learning|tune)\b'; then
        echo "learning"
        return
    fi

    # Discovery keywords
    if echo "${input_lower}" | grep -qE '\b(discover|find|search|available|ecosystem|registry)\b'; then
        echo "discovery"
        return
    fi

    # Default to status if unclear
    echo "status"
}

# === Command Handlers ===

cmd_status() {
    cat <<'EOF'
🤖 Automation Ecosystem Status

EOF

    # Automation Hub Status
    echo "┌─ Auto-Routing ──────────────────────────┐"

    local routing_enabled
    routing_enabled=$(get_config_value ".auto_routing.enabled" "false")

    if [[ "${routing_enabled}" == "true" ]]; then
        echo "│ Status: ✓ Enabled                       │"

        # Get approval rates if metrics exist
        local metrics_file
        metrics_file=$(get_metrics_path)

        if [[ -f "${metrics_file}" ]]; then
            local recent_routings
            recent_routings=$(jq -r 'select(.event_type == "decision" and .data.feature == "auto_routing")' "${metrics_file}" 2>/dev/null | wc -l | tr -d ' ')

            echo "│ Recent Invocations: ${recent_routings} (last 7 days)    │"
        fi
    else
        echo "│ Status: ✗ Disabled                      │"
    fi

    echo "└─────────────────────────────────────────┘"
    echo ""

    # Check for multi-agent plugin
    local available_plugins
    available_plugins=$(detect_available_plugins)

    if echo "${available_plugins}" | grep -q "multi-agent"; then
        echo "┌─ Multi-Agent (plugin: multi-agent) ─────┐"
        echo "│ Available Patterns: 4                    │"
        echo "│ (single/sequential/parallel/hierarchical)│"
        echo "│ Invoke: /orchestrate multi-agent <task>  │"
        echo "└─────────────────────────────────────────┘"
        echo ""
    fi

    # Check for process-janitor plugin
    if echo "${available_plugins}" | grep -q "process-janitor"; then
        echo "┌─ Process Cleanup (plugin: process-janitor)"

        local cleanup_enabled
        cleanup_enabled=$(get_config_value ".auto_cleanup.enabled" "false")

        if [[ "${cleanup_enabled}" == "true" ]]; then
            echo "│ Auto-Cleanup: ✓ Enabled                 │"
        else
            echo "│ Auto-Cleanup: ✗ Disabled                │"
        fi

        echo "│ Invoke: /orchestrate cleanup             │"
        echo "└─────────────────────────────────────────┘"
        echo ""
    fi

    # Check for reflect plugin
    if echo "${available_plugins}" | grep -q "reflect"; then
        echo "┌─ Reflection (plugin: reflect) ──────────┐"

        local reflect_enabled
        reflect_enabled=$(get_config_value ".auto_reflect.enabled" "false")

        if [[ "${reflect_enabled}" == "true" ]]; then
            echo "│ Auto-Suggest: ✓ Enabled                 │"

            # Show session worthiness if available
            local session_state
            session_state=$(get_session_state_path)

            if [[ -f "${session_state}" ]]; then
                local score
                score=$(bash "${SCRIPT_DIR}/calculate-reflection-score.sh" 2>/dev/null || echo "0")

                local threshold
                threshold=$(get_config_value ".auto_reflect.worthiness_threshold" "20")

                echo "│ Session Worthiness: ${score}/${threshold} points        │"
            fi
        else
            echo "│ Auto-Suggest: ✗ Disabled                │"
        fi

        echo "│ Invoke: /orchestrate reflect             │"
        echo "└─────────────────────────────────────────┘"
        echo ""
    fi

    # Check for self-debugger plugin
    if echo "${available_plugins}" | grep -q "self-debugger"; then
        echo "┌─ Self-Debugger (plugin: self-debugger) ─┐"

        local auto_apply
        auto_apply=$(get_config_value ".auto_apply.enabled" "false")

        if [[ "${auto_apply}" == "true" ]]; then
            echo "│ Auto-Fix: ✓ Enabled                     │"
        else
            echo "│ Auto-Fix: ✗ Disabled (recommended)      │"
        fi

        echo "│ Invoke: /orchestrate debug               │"
        echo "└─────────────────────────────────────────┘"
        echo ""
    fi

    # Learning System
    echo "┌─ Learning System ───────────────────────┐"

    local learning_enabled
    learning_enabled=$(get_config_value ".learning.enabled" "false")

    if [[ "${learning_enabled}" == "true" ]]; then
        echo "│ Status: ✓ Enabled                       │"

        # Check for pending proposals
        local proposals_dir="${HOME}/.claude/automation-hub/proposals"
        local pending_count=0

        if [[ -d "${proposals_dir}" ]]; then
            pending_count=$(ls -1 "${proposals_dir}"/*.json 2>/dev/null | wc -l | tr -d ' ')
        fi

        echo "│ Pending Proposals: ${pending_count}                    │"
        echo "│ Invoke: /orchestrate optimize            │"
    else
        echo "│ Status: ✗ Disabled                      │"
    fi

    echo "└─────────────────────────────────────────┘"
    echo ""

    # Quick Actions
    echo "Quick Actions:"
    echo "  /orchestrate discover    - Refresh ecosystem registry"
    echo "  /orchestrate optimize    - Generate optimization proposals"
    echo "  /orchestrate enable all  - Enable all automation features"
    echo "  /orchestrate help        - Show all available commands"
}

cmd_help() {
    cat <<'EOF'
🤖 Orchestrate - Unified Automation Interface

USAGE:
  /orchestrate [command] [args...]

COMMANDS:
  status              Show complete ecosystem status (default)
  discover            Refresh ecosystem registry (plugins, agents, MCP)
  optimize            Run learning analysis and generate proposals

  multi-agent <task>  Invoke multi-agent coordination
  cleanup             Trigger process cleanup
  reflect             Start reflection session
  debug               Run self-debugger scan

  enable <feature>    Enable automation feature
  disable <feature>   Disable automation feature
  proposals           View optimization proposals

  help                Show this help message

NATURAL LANGUAGE:
  You can also describe what you want:

  /orchestrate "I need multiple agents for this complex task"
  /orchestrate "clean up orphaned processes"
  /orchestrate "reflect on my session"
  /orchestrate "find security-related agents"

PLUGIN ROUTING:
  Commands are automatically routed to the appropriate plugin:
  - multi-agent       → multi-agent plugin
  - cleanup           → process-janitor plugin
  - reflect           → reflect plugin
  - debug             → self-debugger plugin
  - optimize/proposals → automation-hub learning system

EXAMPLES:
  /orchestrate status
  /orchestrate discover
  /orchestrate multi-agent "Build a GraphQL API with auth"
  /orchestrate "optimize my thresholds"
  /orchestrate enable auto-routing

EOF
}

cmd_discover() {
    echo "🔍 Discovering Ecosystem..."
    echo ""

    # Run ecosystem discovery
    bash "${SCRIPT_DIR}/discover-ecosystem.sh"

    echo ""
    echo "✓ Registry updated: ~/.claude/automation-hub/ecosystem-registry.json"
    echo ""
    echo "Use /orchestrate status to see available capabilities"
}

cmd_optimize() {
    echo "📊 Running Learning Analysis..."
    echo ""

    # Run metrics analysis
    bash "${SCRIPT_DIR}/analyze-metrics.sh"
}

cmd_proposals() {
    local proposals_dir="${HOME}/.claude/automation-hub/proposals"

    if [[ ! -d "${proposals_dir}" ]]; then
        echo "No proposals available yet"
        echo "Run: /orchestrate optimize"
        return
    fi

    local proposals
    proposals=$(ls -1 "${proposals_dir}"/*.json 2>/dev/null || echo "")

    if [[ -z "${proposals}" ]]; then
        echo "No pending proposals"
        echo "Run: /orchestrate optimize to generate proposals"
        return
    fi

    echo "📋 Optimization Proposals"
    echo ""

    for proposal_file in ${proposals}; do
        local proposal
        proposal=$(cat "${proposal_file}")

        local id type confidence
        id=$(echo "${proposal}" | jq -r '.id')
        type=$(echo "${proposal}" | jq -r '.type')
        confidence=$(echo "${proposal}" | jq -r '.confidence')
        rationale=$(echo "${proposal}" | jq -r '.rationale')

        echo "┌─ ${id} ─────"
        echo "│ Type: ${type}"
        echo "│ Confidence: ${confidence}"
        echo "│"
        echo "│ ${rationale}"
        echo "│"
        echo "│ Apply: /automation apply-proposal ${id}"
        echo "└─────────────────────────────────────────"
        echo ""
    done
}

cmd_enable() {
    local feature="${ARGS[0]:-}"

    if [[ -z "${feature}" ]]; then
        echo "Usage: /orchestrate enable <feature|all>"
        echo ""
        echo "Features:"
        echo "  auto-routing    - Intelligent multi-agent routing"
        echo "  auto-cleanup    - Automatic process cleanup"
        echo "  auto-reflect    - Session reflection suggestions"
        echo "  auto-apply      - Auto-fix application (use with caution)"
        echo "  learning        - Optimization learning system"
        echo "  all             - All features (except auto-apply)"
        return
    fi

    bash "${SCRIPT_DIR}/automation-command.sh" enable "${feature}"
}

cmd_disable() {
    local feature="${ARGS[0]:-}"

    if [[ -z "${feature}" ]]; then
        echo "Usage: /orchestrate disable <feature|all>"
        return
    fi

    bash "${SCRIPT_DIR}/automation-command.sh" disable "${feature}"
}

# === Natural Language Routing ===

route_natural_language() {
    local input="$1"

    local intent
    intent=$(detect_intent "${input}")

    debug "Detected intent: ${intent}"

    case "${intent}" in
        multi-agent)
            echo "🤖 Routing to multi-agent plugin..."
            echo ""
            echo "Task: ${input}"
            echo ""
            echo "Note: Multi-agent plugin should be invoked directly by Claude"
            echo "Recommendation: Use multi-agent:orchestrate or /multi-agent skill"
            ;;

        process-janitor)
            echo "🧹 Routing to process cleanup..."
            echo ""
            echo "Note: Process-janitor plugin should be invoked directly"
            echo "Recommendation: Use /cleanup skill or process-janitor commands"
            ;;

        reflect)
            echo "💡 Routing to reflection system..."
            echo ""
            echo "Note: Reflect plugin should be invoked directly by Claude"
            echo "Recommendation: Use /reflect skill"
            ;;

        self-debugger)
            echo "🔧 Routing to self-debugger..."
            echo ""
            echo "Note: Self-debugger plugin should be invoked directly"
            echo "Recommendation: Use /debug skill or self-debugger commands"
            ;;

        learning)
            cmd_optimize
            ;;

        discovery)
            cmd_discover
            ;;

        status)
            cmd_status
            ;;
    esac
}

# === Main Dispatch ===

main() {
    case "${COMMAND}" in
        status|"")
            cmd_status
            ;;

        help|--help|-h)
            cmd_help
            ;;

        discover|discovery)
            cmd_discover
            ;;

        optimize|learn|analyze)
            cmd_optimize
            ;;

        proposals|proposal)
            cmd_proposals
            ;;

        enable)
            cmd_enable
            ;;

        disable)
            cmd_disable
            ;;

        multi-agent)
            echo "🤖 Multi-Agent Coordination"
            echo ""
            echo "Task: ${ARGS[*]}"
            echo ""
            echo "Note: This command should invoke the multi-agent plugin"
            echo "Claude should use the Task tool with subagent_type='multi-agent:orchestrate'"
            ;;

        cleanup|clean)
            echo "🧹 Process Cleanup"
            echo ""
            echo "Note: This command should invoke the process-janitor plugin"
            echo "Claude should use the /cleanup skill or process-janitor commands"
            ;;

        reflect|reflection)
            echo "💡 Session Reflection"
            echo ""
            echo "Note: This command should invoke the reflect plugin"
            echo "Claude should use the /reflect skill"
            ;;

        debug|debugger)
            echo "🔧 Self-Debugger"
            echo ""
            echo "Note: This command should invoke the self-debugger plugin"
            echo "Claude should use the /debug skill"
            ;;

        *)
            # Natural language routing
            route_natural_language "${FULL_INPUT}"
            ;;
    esac
}

# Execute
main

exit 0
