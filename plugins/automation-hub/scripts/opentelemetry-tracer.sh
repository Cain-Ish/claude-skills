#!/usr/bin/env bash
# OpenTelemetry Tracer - Distributed tracing for AI agents with semantic conventions
# Based on 2026 research: OpenTelemetry AI agent standards, distributed tracing, observability
# Implements span hierarchy, trace context propagation, and semantic conventions

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Configuration ===

OTEL_DIR="${HOME}/.claude/automation-hub/opentelemetry"
TRACES_LOG="${OTEL_DIR}/traces.jsonl"
SPANS_LOG="${OTEL_DIR}/spans.jsonl"
METRICS_LOG="${OTEL_DIR}/metrics.jsonl"
ACTIVE_TRACES="${OTEL_DIR}/active-traces.json"

# Span types (semantic conventions)
SPAN_AGENT="agent"
SPAN_TOOL="tool"
SPAN_LLM="llm"
SPAN_RETRIEVAL="retrieval"
SPAN_CHAIN="chain"
SPAN_WORKFLOW="workflow"

# Span status
STATUS_OK="ok"
STATUS_ERROR="error"
STATUS_UNSET="unset"

# === Initialize ===

mkdir -p "${OTEL_DIR}"

initialize_otel() {
    if [[ ! -f "${ACTIVE_TRACES}" ]]; then
        echo '{"traces":{}}' > "${ACTIVE_TRACES}"
        echo "✓ Initialized OpenTelemetry tracer"
    fi
}

# === Trace Management ===

start_trace() {
    local trace_name="$1"
    local context="${2:-{}}"

    local trace_id
    trace_id=$(date +%s%N | sha256sum | cut -c1-32)

    local timestamp
    timestamp=$(date -u +%s%N)

    local trace_entry
    trace_entry=$(jq -n \
        --arg id "${trace_id}" \
        --arg name "${trace_name}" \
        --arg timestamp "${timestamp}" \
        --argjson context "${context}" \
        '{
            trace_id: $id,
            name: $name,
            start_time: ($timestamp | tonumber),
            context: $context,
            spans: [],
            status: "active"
        }')

    # Add to active traces
    local updated_traces
    updated_traces=$(jq --arg id "${trace_id}" --argjson trace "${trace_entry}" \
        '.traces[$id] = $trace' \
        "${ACTIVE_TRACES}")

    echo "${updated_traces}" > "${ACTIVE_TRACES}"

    debug "Started trace: ${trace_id} (${trace_name})"

    echo "${trace_id}"
}

end_trace() {
    local trace_id="$1"
    local status="${2:-${STATUS_OK}}"

    if [[ ! -f "${ACTIVE_TRACES}" ]]; then
        echo "No active traces"
        return 1
    fi

    local trace
    trace=$(jq -c --arg id "${trace_id}" \
        '.traces[$id]' \
        "${ACTIVE_TRACES}")

    if [[ -z "${trace}" ]] || [[ "${trace}" == "null" ]]; then
        echo "Trace not found: ${trace_id}"
        return 1
    fi

    local end_time
    end_time=$(date -u +%s%N)

    local updated_trace
    updated_trace=$(echo "${trace}" | jq --arg end "${end_time}" --arg status "${status}" \
        '. + {
            end_time: ($end | tonumber),
            status: $status
        }')

    # Calculate duration
    local start_time
    start_time=$(echo "${updated_trace}" | jq -r '.start_time')

    local duration
    duration=$(echo "scale=6; (${end_time} - ${start_time}) / 1000000000" | bc -l)

    updated_trace=$(echo "${updated_trace}" | jq --arg duration "${duration}" \
        '. + {duration_seconds: ($duration | tonumber)}')

    # Log completed trace
    echo "${updated_trace}" >> "${TRACES_LOG}"

    # Remove from active traces
    local updated_active
    updated_active=$(jq --arg id "${trace_id}" \
        'del(.traces[$id])' \
        "${ACTIVE_TRACES}")

    echo "${updated_active}" > "${ACTIVE_TRACES}"

    debug "Ended trace: ${trace_id} (${status}, ${duration}s)"
}

# === Span Management ===

start_span() {
    local trace_id="$1"
    local span_type="$2"
    local span_name="$3"
    local parent_span_id="${4:-}"
    local attributes="${5:-{}}"

    local span_id
    span_id=$(date +%s%N | sha256sum | cut -c1-16)

    local timestamp
    timestamp=$(date -u +%s%N)

    local span_entry
    span_entry=$(jq -n \
        --arg trace_id "${trace_id}" \
        --arg span_id "${span_id}" \
        --arg type "${span_type}" \
        --arg name "${span_name}" \
        --arg parent "${parent_span_id}" \
        --arg timestamp "${timestamp}" \
        --argjson attrs "${attributes}" \
        '{
            trace_id: $trace_id,
            span_id: $span_id,
            parent_span_id: (if $parent == "" then null else $parent end),
            span_type: $type,
            name: $name,
            start_time: ($timestamp | tonumber),
            attributes: $attrs,
            events: [],
            status: "active"
        }')

    # Add span to trace
    if [[ -f "${ACTIVE_TRACES}" ]]; then
        local updated_traces
        updated_traces=$(jq --arg trace_id "${trace_id}" --argjson span "${span_entry}" \
            '(.traces[$trace_id].spans) += [$span]' \
            "${ACTIVE_TRACES}")

        echo "${updated_traces}" > "${ACTIVE_TRACES}"
    fi

    debug "Started span: ${span_id} (${span_type}:${span_name})"

    echo "${span_id}"
}

end_span() {
    local trace_id="$1"
    local span_id="$2"
    local status="${3:-${STATUS_OK}}"
    local result="${4:-}"

    local end_time
    end_time=$(date -u +%s%N)

    if [[ ! -f "${ACTIVE_TRACES}" ]]; then
        return 0
    fi

    # Find and update span
    local trace
    trace=$(jq -c --arg id "${trace_id}" \
        '.traces[$id]' \
        "${ACTIVE_TRACES}" 2>/dev/null || echo "null")

    if [[ "${trace}" == "null" ]]; then
        return 0
    fi

    # Get span index
    local span_index
    span_index=$(echo "${trace}" | jq --arg sid "${span_id}" \
        '.spans | map(.span_id == $sid) | index(true)')

    if [[ "${span_index}" == "null" ]]; then
        return 0
    fi

    # Update span with end time and status
    local updated_trace
    updated_trace=$(echo "${trace}" | jq \
        --arg idx "${span_index}" \
        --arg end "${end_time}" \
        --arg status "${status}" \
        --arg result "${result}" \
        '
        .spans[($idx | tonumber)] += {
            end_time: ($end | tonumber),
            status: $status,
            result: (if $result == "" then null else $result end)
        } |
        .spans[($idx | tonumber)] += {
            duration_seconds: (
                (.spans[($idx | tonumber)].end_time - .spans[($idx | tonumber)].start_time) / 1000000000
            )
        }
        ')

    # Get completed span
    local completed_span
    completed_span=$(echo "${updated_trace}" | jq -c --arg idx "${span_index}" \
        '.spans[($idx | tonumber)]')

    # Log span
    echo "${completed_span}" >> "${SPANS_LOG}"

    # Update active traces
    local updated_active
    updated_active=$(jq --arg trace_id "${trace_id}" --argjson trace "${updated_trace}" \
        '.traces[$trace_id] = $trace' \
        "${ACTIVE_TRACES}")

    echo "${updated_active}" > "${ACTIVE_TRACES}"

    debug "Ended span: ${span_id} (${status})"
}

add_span_event() {
    local trace_id="$1"
    local span_id="$2"
    local event_name="$3"
    local event_attributes="${4:-{}}"

    local timestamp
    timestamp=$(date -u +%s%N)

    local event
    event=$(jq -n \
        --arg name "${event_name}" \
        --arg timestamp "${timestamp}" \
        --argjson attrs "${event_attributes}" \
        '{
            name: $name,
            timestamp: ($timestamp | tonumber),
            attributes: $attrs
        }')

    if [[ ! -f "${ACTIVE_TRACES}" ]]; then
        return 0
    fi

    # Add event to span
    local updated_active
    updated_active=$(jq \
        --arg trace_id "${trace_id}" \
        --arg span_id "${span_id}" \
        --argjson event "${event}" \
        '
        .traces[$trace_id].spans |= map(
            if .span_id == $span_id then
                .events += [$event]
            else
                .
            end
        )
        ' \
        "${ACTIVE_TRACES}")

    echo "${updated_active}" > "${ACTIVE_TRACES}"

    debug "Added event to span ${span_id}: ${event_name}"
}

# === Semantic Conventions ===

trace_agent_execution() {
    local agent_name="$1"
    local task="$2"

    echo "🤖 Tracing Agent Execution: ${agent_name}"
    echo "  Task: ${task}"
    echo ""

    # Start trace
    local trace_id
    trace_id=$(start_trace "agent_execution" \
        "$(jq -n --arg agent "${agent_name}" --arg task "${task}" \
            '{agent: $agent, task: $task}')")

    # Start agent span
    local agent_span
    agent_span=$(start_span \
        "${trace_id}" \
        "${SPAN_AGENT}" \
        "${agent_name}" \
        "" \
        "$(jq -n --arg task "${task}" '{task: $task}')")

    # Simulate agent work with multiple spans
    echo "  Planning..."
    local plan_span
    plan_span=$(start_span \
        "${trace_id}" \
        "${SPAN_CHAIN}" \
        "planning" \
        "${agent_span}" \
        '{"phase":"planning"}')

    sleep 0.1
    end_span "${trace_id}" "${plan_span}" "${STATUS_OK}" "plan_created"

    echo "  Executing..."
    local exec_span
    exec_span=$(start_span \
        "${trace_id}" \
        "${SPAN_CHAIN}" \
        "execution" \
        "${agent_span}" \
        '{"phase":"execution"}')

    # Simulate tool calls
    local tool_span
    tool_span=$(start_span \
        "${trace_id}" \
        "${SPAN_TOOL}" \
        "complexity-analysis" \
        "${exec_span}" \
        '{"tool":"complexity-analysis"}')

    add_span_event "${trace_id}" "${tool_span}" "tool_invoked" \
        '{"parameters":{"prompt":"test task"}}'

    sleep 0.1
    end_span "${trace_id}" "${tool_span}" "${STATUS_OK}" "complexity_score:65"

    end_span "${trace_id}" "${exec_span}" "${STATUS_OK}" "execution_complete"

    echo "  Finalizing..."
    end_span "${trace_id}" "${agent_span}" "${STATUS_OK}" "task_completed"

    # End trace
    end_trace "${trace_id}" "${STATUS_OK}"

    echo ""
    echo "✓ Trace completed: ${trace_id}"
}

trace_llm_call() {
    local trace_id="$1"
    local parent_span="$2"
    local model="$3"
    local prompt="$4"

    local llm_span
    llm_span=$(start_span \
        "${trace_id}" \
        "${SPAN_LLM}" \
        "llm_call" \
        "${parent_span}" \
        "$(jq -n --arg model "${model}" --arg prompt "${prompt}" \
            '{model: $model, prompt: $prompt}')")

    # Simulate LLM call
    sleep 0.2

    # Add usage event
    add_span_event "${trace_id}" "${llm_span}" "token_usage" \
        '{"prompt_tokens":150,"completion_tokens":75,"total_tokens":225}'

    end_span "${trace_id}" "${llm_span}" "${STATUS_OK}" "response_generated"

    echo "${llm_span}"
}

trace_retrieval() {
    local trace_id="$1"
    local parent_span="$2"
    local query="$3"
    local limit="$4"

    local retrieval_span
    retrieval_span=$(start_span \
        "${trace_id}" \
        "${SPAN_RETRIEVAL}" \
        "semantic_search" \
        "${parent_span}" \
        "$(jq -n --arg query "${query}" --arg limit "${limit}" \
            '{query: $query, limit: ($limit | tonumber)}')")

    # Simulate retrieval
    sleep 0.1

    # Add retrieved documents event
    add_span_event "${trace_id}" "${retrieval_span}" "documents_retrieved" \
        "$(jq -n --arg count "${limit}" '{count: ($count | tonumber), relevance_avg: 0.87}')"

    end_span "${trace_id}" "${retrieval_span}" "${STATUS_OK}" "retrieved_${limit}_docs"

    echo "${retrieval_span}"
}

# === Trace Visualization ===

visualize_trace() {
    local trace_id="$1"

    echo "📊 Trace Visualization: ${trace_id}"
    echo ""

    # Get trace from logs
    local trace
    trace=$(grep "\"trace_id\":\"${trace_id}\"" "${TRACES_LOG}" 2>/dev/null | tail -1 || echo "")

    if [[ -z "${trace}" ]]; then
        # Try active traces
        trace=$(jq -c --arg id "${trace_id}" \
            '.traces[$id]' \
            "${ACTIVE_TRACES}" 2>/dev/null || echo "null")
    fi

    if [[ -z "${trace}" ]] || [[ "${trace}" == "null" ]]; then
        echo "Trace not found: ${trace_id}"
        return 1
    fi

    local trace_name
    trace_name=$(echo "${trace}" | jq -r '.name')

    local duration
    duration=$(echo "${trace}" | jq -r '.duration_seconds // "active"')

    echo "Trace: ${trace_name} (${duration}s)"
    echo ""

    # Visualize spans hierarchy
    local spans
    spans=$(echo "${trace}" | jq -c '.spans[]')

    echo "Span Hierarchy:"
    echo ""

    while IFS= read -r span; do
        if [[ -n "${span}" ]]; then
            local span_name
            span_name=$(echo "${span}" | jq -r '.name')

            local span_type
            span_type=$(echo "${span}" | jq -r '.span_type')

            local span_duration
            span_duration=$(echo "${span}" | jq -r '.duration_seconds // "active"')

            local parent_id
            parent_id=$(echo "${span}" | jq -r '.parent_span_id // "null"')

            local indent=""
            if [[ "${parent_id}" != "null" ]]; then
                indent="  "
            fi

            echo "${indent}└─ ${span_type}: ${span_name} (${span_duration}s)"

            # Show events
            local events
            events=$(echo "${span}" | jq -r '.events[]? | "     • " + .name')
            if [[ -n "${events}" ]]; then
                echo "${events}"
            fi
        fi
    done <<< "${spans}"
}

# === Metrics Collection ===

collect_span_metrics() {
    echo "📈 Collecting Span Metrics"
    echo ""

    if [[ ! -f "${SPANS_LOG}" ]]; then
        echo "No span data available"
        return 0
    fi

    # Count by span type
    echo "┌─ By Span Type ──────────────────────────┐"
    jq -r '.span_type' "${SPANS_LOG}" 2>/dev/null | sort | uniq -c | \
        awk '{printf "│ %-15s %d\n", $2":", $1}'
    echo "└─────────────────────────────────────────┘"
    echo ""

    # Average duration by type
    echo "┌─ Average Duration (seconds) ────────────┐"
    for span_type in agent tool llm retrieval chain workflow; do
        local avg_duration
        avg_duration=$(jq -s --arg type "${span_type}" \
            'map(select(.span_type == $type) | .duration_seconds) |
            if length > 0 then (add / length) else 0 end' \
            "${SPANS_LOG}" 2>/dev/null || echo "0")

        if (( $(echo "${avg_duration} > 0" | bc -l) )); then
            printf "│ %-15s %.4f\n" "${span_type}:" "${avg_duration}"
        fi
    done
    echo "└─────────────────────────────────────────┘"
}

# === Export ===

export_traces() {
    local format="${1:-json}"
    local output_file="${2:-}"

    echo "📤 Exporting Traces (${format})"
    echo ""

    if [[ ! -f "${TRACES_LOG}" ]]; then
        echo "No trace data available"
        return 0
    fi

    local output=""

    case "${format}" in
        json)
            output=$(jq -s '.' "${TRACES_LOG}")
            ;;

        jaeger)
            # Jaeger-compatible format (simplified)
            output=$(jq -s 'map({
                traceID: .trace_id,
                spans: .spans | map({
                    traceID: .trace_id,
                    spanID: .span_id,
                    operationName: .name,
                    startTime: .start_time,
                    duration: (.duration_seconds * 1000000 | floor),
                    tags: .attributes
                }),
                processes: {},
                warnings: null
            })' "${TRACES_LOG}")
            ;;

        otlp)
            # OpenTelemetry Protocol format (simplified)
            output=$(jq -s 'map({
                resourceSpans: [{
                    scopeSpans: [{
                        spans: .spans | map({
                            traceId: .trace_id,
                            spanId: .span_id,
                            parentSpanId: .parent_span_id,
                            name: .name,
                            kind: (if .span_type == "agent" then 1 else 0 end),
                            startTimeUnixNano: .start_time,
                            endTimeUnixNano: .end_time,
                            attributes: (.attributes | to_entries | map({
                                key: .key,
                                value: {stringValue: (.value | tostring)}
                            })),
                            status: {code: (if .status == "ok" then 0 else 2 end)}
                        })
                    }]
                }]
            })' "${TRACES_LOG}")
            ;;

        *)
            echo "Unknown format: ${format}"
            return 1
            ;;
    esac

    if [[ -n "${output_file}" ]]; then
        echo "${output}" > "${output_file}"
        echo "✓ Exported to: ${output_file}"
    else
        echo "${output}"
    fi
}

# === Statistics ===

otel_stats() {
    echo "📊 OpenTelemetry Statistics"
    echo ""

    local total_traces=0
    local total_spans=0
    local active_traces=0

    if [[ -f "${TRACES_LOG}" ]]; then
        total_traces=$(wc -l < "${TRACES_LOG}" | tr -d ' ')
    fi

    if [[ -f "${SPANS_LOG}" ]]; then
        total_spans=$(wc -l < "${SPANS_LOG}" | tr -d ' ')
    fi

    if [[ -f "${ACTIVE_TRACES}" ]]; then
        active_traces=$(jq '.traces | length' "${ACTIVE_TRACES}" 2>/dev/null || echo "0")
    fi

    echo "┌─ Overview ──────────────────────────────┐"
    echo "│ Total Traces: ${total_traces}"
    echo "│ Total Spans: ${total_spans}"
    echo "│ Active Traces: ${active_traces}"
    echo "└─────────────────────────────────────────┘"
    echo ""

    if [[ ${total_spans} -gt 0 ]]; then
        collect_span_metrics
    fi
}

# === Main ===

main() {
    local command="${1:-stats}"
    shift || true

    # Initialize on first run
    initialize_otel

    case "${command}" in
        start-trace)
            if [[ $# -eq 0 ]]; then
                echo "Usage: opentelemetry-tracer.sh start-trace <name> [context_json]"
                exit 1
            fi

            start_trace "$@"
            ;;

        end-trace)
            if [[ $# -eq 0 ]]; then
                echo "Usage: opentelemetry-tracer.sh end-trace <trace_id> [status]"
                exit 1
            fi

            end_trace "$@"
            ;;

        start-span)
            if [[ $# -lt 3 ]]; then
                echo "Usage: opentelemetry-tracer.sh start-span <trace_id> <type> <name> [parent_span_id] [attributes_json]"
                exit 1
            fi

            start_span "$@"
            ;;

        end-span)
            if [[ $# -lt 2 ]]; then
                echo "Usage: opentelemetry-tracer.sh end-span <trace_id> <span_id> [status] [result]"
                exit 1
            fi

            end_span "$@"
            ;;

        add-event)
            if [[ $# -lt 3 ]]; then
                echo "Usage: opentelemetry-tracer.sh add-event <trace_id> <span_id> <event_name> [attributes_json]"
                exit 1
            fi

            add_span_event "$@"
            ;;

        trace-agent)
            if [[ $# -lt 2 ]]; then
                echo "Usage: opentelemetry-tracer.sh trace-agent <agent_name> <task>"
                exit 1
            fi

            trace_agent_execution "$@"
            ;;

        visualize)
            if [[ $# -eq 0 ]]; then
                echo "Usage: opentelemetry-tracer.sh visualize <trace_id>"
                exit 1
            fi

            visualize_trace "$1"
            ;;

        export)
            export_traces "$@"
            ;;

        stats)
            otel_stats
            ;;

        *)
            cat <<'EOF'
OpenTelemetry Tracer - Distributed tracing for AI agents

USAGE:
  opentelemetry-tracer.sh start-trace <name> [context_json]
  opentelemetry-tracer.sh end-trace <trace_id> [status]
  opentelemetry-tracer.sh start-span <trace_id> <type> <name> [parent_span_id] [attributes_json]
  opentelemetry-tracer.sh end-span <trace_id> <span_id> [status] [result]
  opentelemetry-tracer.sh add-event <trace_id> <span_id> <event_name> [attributes_json]
  opentelemetry-tracer.sh trace-agent <agent_name> <task>
  opentelemetry-tracer.sh visualize <trace_id>
  opentelemetry-tracer.sh export [format] [output_file]
  opentelemetry-tracer.sh stats

SPAN TYPES:
  agent          Agent execution span
  tool           Tool invocation span
  llm            LLM API call span
  retrieval      Semantic search/retrieval span
  chain          Chain of operations span
  workflow       Workflow orchestration span

EXPORT FORMATS:
  json           Standard JSON format
  jaeger         Jaeger-compatible format
  otlp           OpenTelemetry Protocol format

EXAMPLES:
  # Start trace for agent execution
  trace_id=$(opentelemetry-tracer.sh start-trace "agent_workflow")

  # Start agent span
  agent_span=$(opentelemetry-tracer.sh start-span \
    "${trace_id}" agent "automation-hub" "" '{"task":"routing"}')

  # Start tool span (child of agent)
  tool_span=$(opentelemetry-tracer.sh start-span \
    "${trace_id}" tool "complexity-analysis" "${agent_span}")

  # Add event to span
  opentelemetry-tracer.sh add-event \
    "${trace_id}" "${tool_span}" "tool_completed" '{"result":"65"}'

  # End spans
  opentelemetry-tracer.sh end-span "${trace_id}" "${tool_span}" ok "score:65"
  opentelemetry-tracer.sh end-span "${trace_id}" "${agent_span}" ok "completed"

  # End trace
  opentelemetry-tracer.sh end-trace "${trace_id}" ok

  # Visualize trace
  opentelemetry-tracer.sh visualize "${trace_id}"

  # Export traces (Jaeger format)
  opentelemetry-tracer.sh export jaeger traces.json

  # Quick agent trace
  opentelemetry-tracer.sh trace-agent "automation-hub" "routing decision"

RESEARCH:
  - OpenTelemetry AI semantic conventions (2026)
  - Mission-critical observability infrastructure
  - Distributed tracing across agent frameworks
  - Integration with Jaeger, Zipkin, Tempo

EOF
            ;;
    esac
}

# Execute
main "$@"

exit 0
