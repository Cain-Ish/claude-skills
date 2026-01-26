#!/usr/bin/env bash
# Protocol Bridge - MCP + A2A integration for multi-agent collaboration
# Based on 2026 research: Google A2A, Anthropic MCP, agent interoperability
# Implements both vertical (agent-tool) and horizontal (agent-agent) communication

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Configuration ===

BRIDGE_DIR="${HOME}/.claude/automation-hub/protocol-bridge"
MCP_REGISTRY="${BRIDGE_DIR}/mcp-servers.json"
A2A_REGISTRY="${BRIDGE_DIR}/a2a-agents.json"
PROTOCOL_LOG="${BRIDGE_DIR}/protocol-activity.jsonl"
MESSAGE_QUEUE="${BRIDGE_DIR}/message-queue.json"

# Protocol types
PROTOCOL_MCP="mcp"
PROTOCOL_A2A="a2a"
PROTOCOL_ACP="acp"
PROTOCOL_ANP="anp"

# Message types (A2A)
MSG_REQUEST="request"
MSG_RESPONSE="response"
MSG_DELEGATE="delegate"
MSG_NOTIFY="notify"
MSG_QUERY="query"

# === Initialize ===

mkdir -p "${BRIDGE_DIR}"

initialize_protocol_bridge() {
    if [[ ! -f "${MCP_REGISTRY}" ]]; then
        cat > "${MCP_REGISTRY}" <<'EOF'
{
  "servers": [
    {
      "name": "automation-hub",
      "protocol": "mcp",
      "version": "1.0",
      "capabilities": [
        "auto-routing",
        "auto-cleanup",
        "auto-reflection",
        "decision-tracing",
        "memory-management"
      ],
      "endpoints": {
        "tools": "tools/list",
        "execute": "tools/execute",
        "resources": "resources/list"
      }
    }
  ]
}
EOF
        echo "✓ Initialized MCP registry"
    fi

    if [[ ! -f "${A2A_REGISTRY}" ]]; then
        cat > "${A2A_REGISTRY}" <<'EOF'
{
  "agents": [
    {
      "id": "automation-hub-coordinator",
      "name": "Automation Hub Coordinator",
      "protocol": "a2a",
      "version": "1.0",
      "capabilities": [
        "workflow-orchestration",
        "multi-agent-coordination",
        "decision-making",
        "resource-allocation"
      ],
      "communication": {
        "accepts": ["request", "delegate", "query"],
        "sends": ["response", "notify", "delegate"]
      },
      "trust_level": "verified"
    }
  ]
}
EOF
        echo "✓ Initialized A2A registry"
    fi

    if [[ ! -f "${MESSAGE_QUEUE}" ]]; then
        echo '{"queue":[]}' > "${MESSAGE_QUEUE}"
    fi
}

# === MCP Protocol (Vertical: Agent-Tool) ===

mcp_list_tools() {
    local server_name="${1:-automation-hub}"

    echo "🔧 MCP Tools Available (${server_name})"
    echo ""

    # List available automation-hub tools
    cat <<'EOF'
┌─ Available Tools ───────────────────────┐
│ auto-routing           Multi-agent routing
│ complexity-analysis    Task complexity scoring
│ decision-tracing       Audit trail logging
│ memory-store          Context persistence
│ semantic-search       Memory retrieval
│ workflow-planning     Task decomposition
│ security-check        Permission validation
│ self-healing          Error recovery
│ streaming-events      Real-time updates
└─────────────────────────────────────────┘
EOF
}

mcp_execute_tool() {
    local tool_name="$1"
    local parameters="$2"

    local timestamp
    timestamp=$(date -u +%s)

    echo "🔧 MCP Tool Execution: ${tool_name}"
    echo "  Parameters: ${parameters}"
    echo ""

    # Route to appropriate automation script
    case "${tool_name}" in
        auto-routing)
            local prompt
            prompt=$(echo "${parameters}" | jq -r '.prompt')
            bash "${SCRIPT_DIR}/stage1-prefilter.sh" "${prompt}" 50000 "Write"
            ;;

        complexity-analysis)
            local prompt
            prompt=$(echo "${parameters}" | jq -r '.prompt')
            bash "${SCRIPT_DIR}/invoke-task-analyzer.sh" "${prompt}"
            ;;

        decision-tracing)
            local decision_type
            decision_type=$(echo "${parameters}" | jq -r '.type')
            local outcome
            outcome=$(echo "${parameters}" | jq -r '.outcome')
            local rationale
            rationale=$(echo "${parameters}" | jq -r '.rationale')
            local confidence
            confidence=$(echo "${parameters}" | jq -r '.confidence // "0.85"')
            local context
            context=$(echo "${parameters}" | jq -r '.context // "{}"')

            bash "${SCRIPT_DIR}/decision-tracer.sh" log \
                "${decision_type}" \
                "${outcome}" \
                "${rationale}" \
                "${confidence}" \
                "${context}"
            ;;

        memory-store)
            local tier
            tier=$(echo "${parameters}" | jq -r '.tier // "short"')
            local type
            type=$(echo "${parameters}" | jq -r '.type')
            local key
            key=$(echo "${parameters}" | jq -r '.key')
            local value
            value=$(echo "${parameters}" | jq -r '.value')

            if [[ "${tier}" == "short" ]]; then
                bash "${SCRIPT_DIR}/context-memory-manager.sh" store-short \
                    "${type}" "${key}" "${value}"
            else
                bash "${SCRIPT_DIR}/context-memory-manager.sh" store-long \
                    "${type}" "${key}" "${value}"
            fi
            ;;

        semantic-search)
            local query
            query=$(echo "${parameters}" | jq -r '.query')
            local limit
            limit=$(echo "${parameters}" | jq -r '.limit // "5"')

            bash "${SCRIPT_DIR}/context-memory-manager.sh" semantic-search \
                "${query}" "${limit}"
            ;;

        workflow-planning)
            local goal
            goal=$(echo "${parameters}" | jq -r '.goal')
            local strategy
            strategy=$(echo "${parameters}" | jq -r '.strategy // "adaptive"')

            bash "${SCRIPT_DIR}/workflow-planner.sh" decompose \
                "${goal}" "${strategy}" 3
            ;;

        security-check)
            local perm_type
            perm_type=$(echo "${parameters}" | jq -r '.type')
            local resource
            resource=$(echo "${parameters}" | jq -r '.resource')
            local action
            action=$(echo "${parameters}" | jq -r '.action // "read"')

            bash "${SCRIPT_DIR}/security-sandbox.sh" check \
                "${perm_type}" "${resource}" "${action}"
            ;;

        self-healing)
            local error_type
            error_type=$(echo "${parameters}" | jq -r '.error_type')
            local error_message
            error_message=$(echo "${parameters}" | jq -r '.error_message')
            local context
            context=$(echo "${parameters}" | jq -r '.context // "unknown"')

            bash "${SCRIPT_DIR}/self-healing-agent.sh" detect \
                "${error_type}" "${error_message}" "${context}"
            ;;

        streaming-events)
            local event_type
            event_type=$(echo "${parameters}" | jq -r '.event_type')
            local data
            data=$(echo "${parameters}" | jq -c '.data')

            bash "${SCRIPT_DIR}/streaming-events.sh" emit \
                "${event_type}" "${data}"
            ;;

        *)
            echo "Unknown tool: ${tool_name}"
            return 1
            ;;
    esac

    # Log MCP execution
    log_protocol_activity "${PROTOCOL_MCP}" "tool_execution" "${tool_name}" "$(jq -n \
        --arg params "${parameters}" \
        '{parameters: $params}')"
}

mcp_list_resources() {
    local server_name="${1:-automation-hub}"

    echo "📦 MCP Resources Available (${server_name})"
    echo ""

    cat <<'EOF'
┌─ Available Resources ───────────────────┐
│ decision-history       All logged decisions
│ memory-short-term      Current session context
│ memory-long-term       Persistent knowledge
│ workflow-active        Active workflows
│ security-audit         Security event log
│ metrics-dashboard      Performance metrics
└─────────────────────────────────────────┘
EOF
}

# === A2A Protocol (Horizontal: Agent-Agent) ===

a2a_send_message() {
    local target_agent="$1"
    local message_type="$2"
    local content="$3"
    local correlation_id="${4:-}"

    local timestamp
    timestamp=$(date -u +%s)

    local message_id
    message_id=$(date +%s%N)

    if [[ -z "${correlation_id}" ]]; then
        correlation_id="${message_id}"
    fi

    local message
    message=$(jq -n \
        --arg id "${message_id}" \
        --arg correlation "${correlation_id}" \
        --arg timestamp "${timestamp}" \
        --arg from "automation-hub-coordinator" \
        --arg to "${target_agent}" \
        --arg type "${message_type}" \
        --arg content "${content}" \
        '{
            id: $id,
            correlation_id: $correlation,
            timestamp: ($timestamp | tonumber),
            from: $from,
            to: $to,
            type: $type,
            content: $content,
            protocol: "a2a",
            status: "sent"
        }')

    # Add to message queue
    local updated_queue
    updated_queue=$(jq --argjson msg "${message}" \
        '.queue += [$msg]' \
        "${MESSAGE_QUEUE}")

    echo "${updated_queue}" > "${MESSAGE_QUEUE}"

    # Log A2A activity
    log_protocol_activity "${PROTOCOL_A2A}" "message_sent" "${target_agent}" "$(jq -n \
        --arg type "${message_type}" \
        --arg id "${message_id}" \
        '{message_type: $type, message_id: $id}')"

    echo "${message_id}"
}

a2a_receive_message() {
    local agent_id="${1:-automation-hub-coordinator}"

    if [[ ! -f "${MESSAGE_QUEUE}" ]]; then
        echo "[]"
        return 0
    fi

    # Get pending messages for this agent
    local messages
    messages=$(jq -c --arg agent "${agent_id}" \
        '.queue | map(select(.to == $agent and .status == "sent"))' \
        "${MESSAGE_QUEUE}")

    echo "${messages}"
}

a2a_process_message() {
    local message_id="$1"

    # Get message from queue
    local message
    message=$(jq -c --arg id "${message_id}" \
        '.queue[] | select(.id == $id)' \
        "${MESSAGE_QUEUE}")

    if [[ -z "${message}" ]] || [[ "${message}" == "null" ]]; then
        echo "Message not found: ${message_id}"
        return 1
    fi

    local message_type
    message_type=$(echo "${message}" | jq -r '.type')

    local content
    content=$(echo "${message}" | jq -r '.content')

    local from_agent
    from_agent=$(echo "${message}" | jq -r '.from')

    local correlation_id
    correlation_id=$(echo "${message}" | jq -r '.correlation_id')

    echo "📨 Processing A2A Message: ${message_type}"
    echo "  From: ${from_agent}"
    echo "  Content: ${content}"
    echo ""

    # Process based on message type
    case "${message_type}" in
        "${MSG_REQUEST}")
            # Process request and send response
            local result
            result=$(process_agent_request "${content}")

            a2a_send_message \
                "${from_agent}" \
                "${MSG_RESPONSE}" \
                "${result}" \
                "${correlation_id}"
            ;;

        "${MSG_DELEGATE}")
            # Accept delegation and execute
            echo "Accepted delegation: ${content}"
            # Execute delegated task...
            ;;

        "${MSG_QUERY}")
            # Answer query
            local answer
            answer=$(answer_agent_query "${content}")

            a2a_send_message \
                "${from_agent}" \
                "${MSG_RESPONSE}" \
                "${answer}" \
                "${correlation_id}"
            ;;

        "${MSG_NOTIFY}")
            # Acknowledge notification
            echo "Notification received: ${content}"
            ;;

        "${MSG_RESPONSE}")
            # Process response
            echo "Response received: ${content}"
            ;;

        *)
            echo "Unknown message type: ${message_type}"
            ;;
    esac

    # Mark message as processed
    local updated_queue
    updated_queue=$(jq --arg id "${message_id}" \
        '(.queue[] | select(.id == $id) | .status) = "processed"' \
        "${MESSAGE_QUEUE}")

    echo "${updated_queue}" > "${MESSAGE_QUEUE}"
}

process_agent_request() {
    local request="$1"

    # Parse request and route to appropriate handler
    local request_type
    request_type=$(echo "${request}" | jq -r '.type // "unknown"')

    case "${request_type}" in
        "complexity_analysis")
            local prompt
            prompt=$(echo "${request}" | jq -r '.prompt')
            bash "${SCRIPT_DIR}/invoke-task-analyzer.sh" "${prompt}"
            ;;

        "workflow_decomposition")
            local goal
            goal=$(echo "${request}" | jq -r '.goal')
            bash "${SCRIPT_DIR}/workflow-planner.sh" decompose "${goal}" adaptive 3
            ;;

        *)
            echo "Unsupported request type: ${request_type}"
            ;;
    esac
}

answer_agent_query() {
    local query="$1"

    # Use semantic search to find relevant information
    bash "${SCRIPT_DIR}/context-memory-manager.sh" semantic-search "${query}" 3
}

# === Protocol Activity Logging ===

log_protocol_activity() {
    local protocol="$1"
    local activity_type="$2"
    local target="$3"
    local details="$4"

    local timestamp
    timestamp=$(date -u +%s)

    local activity_entry
    activity_entry=$(jq -n \
        --arg timestamp "${timestamp}" \
        --arg protocol "${protocol}" \
        --arg type "${activity_type}" \
        --arg target "${target}" \
        --argjson details "${details}" \
        '{
            timestamp: ($timestamp | tonumber),
            protocol: $protocol,
            activity_type: $type,
            target: $target,
            details: $details,
            recorded_at: (now | tostring)
        }')

    echo "${activity_entry}" >> "${PROTOCOL_LOG}"

    debug "Protocol activity: ${protocol} ${activity_type} -> ${target}"
}

# === Protocol Statistics ===

protocol_stats() {
    echo "📊 Protocol Bridge Statistics"
    echo ""

    if [[ ! -f "${PROTOCOL_LOG}" ]]; then
        echo "No protocol activity logged yet"
        return 0
    fi

    local total_activities
    total_activities=$(wc -l < "${PROTOCOL_LOG}" | tr -d ' ')

    local mcp_count
    mcp_count=$(jq -s 'map(select(.protocol == "mcp")) | length' "${PROTOCOL_LOG}")

    local a2a_count
    a2a_count=$(jq -s 'map(select(.protocol == "a2a")) | length' "${PROTOCOL_LOG}")

    echo "┌─ Overall ───────────────────────────────┐"
    echo "│ Total Protocol Activities: ${total_activities}"
    echo "│ MCP (Agent-Tool): ${mcp_count}"
    echo "│ A2A (Agent-Agent): ${a2a_count}"
    echo "└─────────────────────────────────────────┘"
    echo ""

    # By activity type
    if [[ ${total_activities} -gt 0 ]]; then
        echo "┌─ By Activity Type ──────────────────────┐"
        jq -s 'group_by(.activity_type) |
            map({
                type: .[0].activity_type,
                count: length
            }) |
            .[] |
            "│ " + .type + ": " + (.count | tostring)' \
            "${PROTOCOL_LOG}"
        echo "└─────────────────────────────────────────┘"
    fi
}

# === Main ===

main() {
    local command="${1:-stats}"
    shift || true

    # Initialize on first run
    initialize_protocol_bridge

    case "${command}" in
        mcp-list-tools)
            mcp_list_tools "$@"
            ;;

        mcp-execute)
            if [[ $# -lt 2 ]]; then
                echo "Usage: protocol-bridge.sh mcp-execute <tool_name> <parameters_json>"
                exit 1
            fi

            mcp_execute_tool "$@"
            ;;

        mcp-list-resources)
            mcp_list_resources "$@"
            ;;

        a2a-send)
            if [[ $# -lt 3 ]]; then
                echo "Usage: protocol-bridge.sh a2a-send <target_agent> <message_type> <content> [correlation_id]"
                exit 1
            fi

            a2a_send_message "$@"
            ;;

        a2a-receive)
            a2a_receive_message "$@"
            ;;

        a2a-process)
            if [[ $# -eq 0 ]]; then
                echo "Usage: protocol-bridge.sh a2a-process <message_id>"
                exit 1
            fi

            a2a_process_message "$1"
            ;;

        stats)
            protocol_stats
            ;;

        *)
            cat <<'EOF'
Protocol Bridge - MCP + A2A integration for multi-agent collaboration

USAGE:
  protocol-bridge.sh mcp-list-tools [server_name]
  protocol-bridge.sh mcp-execute <tool_name> <parameters_json>
  protocol-bridge.sh mcp-list-resources [server_name]
  protocol-bridge.sh a2a-send <target_agent> <message_type> <content> [correlation_id]
  protocol-bridge.sh a2a-receive [agent_id]
  protocol-bridge.sh a2a-process <message_id>
  protocol-bridge.sh stats

PROTOCOLS:
  MCP        Model Context Protocol (agent-to-tool, vertical)
  A2A        Agent-to-Agent Protocol (agent-to-agent, horizontal)
  ACP        Agent Communication Protocol
  ANP        Agent Negotiation Protocol

MESSAGE TYPES (A2A):
  request    Request action from another agent
  response   Response to a request
  delegate   Delegate task to another agent
  notify     Send notification
  query      Query for information

EXAMPLES:
  # MCP: List available tools
  protocol-bridge.sh mcp-list-tools

  # MCP: Execute complexity analysis tool
  protocol-bridge.sh mcp-execute \
    complexity-analysis \
    '{"prompt":"build REST API"}'

  # A2A: Send request to another agent
  protocol-bridge.sh a2a-send \
    "task-analyzer-agent" \
    request \
    '{"type":"complexity_analysis","prompt":"complex task"}'

  # A2A: Receive pending messages
  protocol-bridge.sh a2a-receive automation-hub-coordinator

  # A2A: Process received message
  protocol-bridge.sh a2a-process "1737840123456789000"

RESEARCH:
  - Google A2A: 50+ technology partners (2026)
  - MCP: Anthropic's vertical integration standard
  - 40% of enterprise apps will use AI agents by 2026
  - Agent orchestration market: $8.5B by 2026

EOF
            ;;
    esac
}

# Execute
main "$@"

exit 0
