#!/usr/bin/env bash
# Streaming Events - Real-time progress updates via Server-Sent Events (SSE)
# Based on 2026 research: SSE for AI agent transparency, real-time UX
# Enables live decision tracking, tool call visibility, progress monitoring

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Configuration ===

EVENTS_DIR="${HOME}/.claude/automation-hub/events"
EVENT_STREAM="${EVENTS_DIR}/stream.jsonl"
SSE_PORT="${AUTOMATION_SSE_PORT:-8765}"

# Event types
EVENT_DECISION="decision"
EVENT_TOOL_CALL="tool_call"
EVENT_PROGRESS="progress"
EVENT_STATUS="status"
EVENT_ERROR="error"
EVENT_COMPLETION="completion"

# === Initialize ===

mkdir -p "${EVENTS_DIR}"

# === Event Emission ===

emit_event() {
    local event_type="$1"
    local event_data="$2"
    local event_id="${3:-}"

    local timestamp
    timestamp=$(date -u +%s)

    # Generate event ID if not provided
    if [[ -z "${event_id}" ]]; then
        event_id=$(date +%s%N)
    fi

    # Create SSE-formatted event
    local event
    event=$(jq -n \
        --arg id "${event_id}" \
        --arg type "${event_type}" \
        --argjson data "${event_data}" \
        --arg timestamp "${timestamp}" \
        '{
            id: $id,
            event: $type,
            data: $data,
            timestamp: ($timestamp | tonumber)
        }')

    # Write to event stream
    echo "${event}" >> "${EVENT_STREAM}"

    # If SSE server is running, push event
    if [[ -f "${EVENTS_DIR}/sse-server.pid" ]]; then
        push_to_sse_server "${event}"
    fi

    debug "Event emitted: ${event_type} (${event_id})"
}

# === Event Types ===

emit_decision_event() {
    local feature="$1"
    local decision="$2"
    local confidence="$3"
    local reasoning="$4"

    local data
    data=$(jq -n \
        --arg feature "${feature}" \
        --arg decision "${decision}" \
        --arg confidence "${confidence}" \
        --arg reasoning "${reasoning}" \
        '{
            feature: $feature,
            decision: $decision,
            confidence: ($confidence | tonumber),
            reasoning: $reasoning
        }')

    emit_event "${EVENT_DECISION}" "${data}"
}

emit_tool_call_event() {
    local tool_name="$1"
    local tool_action="$2"
    local tool_status="$3"
    local tool_result="${4:-}"

    local data
    data=$(jq -n \
        --arg tool "${tool_name}" \
        --arg action "${tool_action}" \
        --arg status "${tool_status}" \
        --arg result "${tool_result}" \
        '{
            tool: $tool,
            action: $action,
            status: $status,
            result: $result
        }')

    emit_event "${EVENT_TOOL_CALL}" "${data}"
}

emit_progress_event() {
    local task_name="$1"
    local current_step="$2"
    local total_steps="$3"
    local status_message="$4"

    local progress_percent
    if [[ ${total_steps} -gt 0 ]]; then
        progress_percent=$(echo "scale=1; (${current_step} / ${total_steps}) * 100" | bc)
    else
        progress_percent="0"
    fi

    local data
    data=$(jq -n \
        --arg task "${task_name}" \
        --arg current "${current_step}" \
        --arg total "${total_steps}" \
        --arg percent "${progress_percent}" \
        --arg message "${status_message}" \
        '{
            task: $task,
            current_step: ($current | tonumber),
            total_steps: ($total | tonumber),
            progress_percent: ($percent | tonumber),
            status: $message
        }')

    emit_event "${EVENT_PROGRESS}" "${data}"
}

emit_status_event() {
    local status="$1"
    local message="$2"

    local data
    data=$(jq -n \
        --arg status "${status}" \
        --arg message "${message}" \
        '{
            status: $status,
            message: $message
        }')

    emit_event "${EVENT_STATUS}" "${data}"
}

emit_error_event() {
    local error_type="$1"
    local error_message="$2"
    local recoverable="${3:-false}"

    local data
    data=$(jq -n \
        --arg type "${error_type}" \
        --arg message "${error_message}" \
        --arg recoverable "${recoverable}" \
        '{
            error_type: $type,
            message: $message,
            recoverable: ($recoverable | test("true"))
        }')

    emit_event "${EVENT_ERROR}" "${data}"
}

emit_completion_event() {
    local task_name="$1"
    local result="$2"
    local duration_ms="${3:-0}"

    local data
    data=$(jq -n \
        --arg task "${task_name}" \
        --arg result "${result}" \
        --arg duration "${duration_ms}" \
        '{
            task: $task,
            result: $result,
            duration_ms: ($duration | tonumber)
        }')

    emit_event "${EVENT_COMPLETION}" "${data}"
}

# === SSE Server (Simple HTTP Server) ===

start_sse_server() {
    local port="${1:-${SSE_PORT}}"

    echo "🌐 Starting SSE Server on port ${port}..."

    # Check if already running
    if [[ -f "${EVENTS_DIR}/sse-server.pid" ]]; then
        local pid
        pid=$(cat "${EVENTS_DIR}/sse-server.pid")

        if ps -p "${pid}" > /dev/null 2>&1; then
            echo "  ⚠️  SSE server already running (PID: ${pid})"
            return 0
        fi
    fi

    # Start simple SSE server using Python (more widely available than netcat for SSE)
    python3 <<EOF &
import http.server
import socketserver
import json
import time
import os

PORT = ${port}
EVENTS_DIR = "${EVENTS_DIR}"

class SSEHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/events':
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream')
            self.send_header('Cache-Control', 'no-cache')
            self.send_header('Connection', 'keep-alive')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()

            # Send keep-alive comments
            event_stream = os.path.join(EVENTS_DIR, 'stream.jsonl')

            # Tail the event stream
            last_pos = 0
            while True:
                try:
                    if os.path.exists(event_stream):
                        with open(event_stream, 'r') as f:
                            f.seek(last_pos)
                            lines = f.readlines()
                            last_pos = f.tell()

                            for line in lines:
                                if line.strip():
                                    event = json.loads(line)
                                    self.wfile.write(f"id: {event['id']}\\n".encode())
                                    self.wfile.write(f"event: {event['event']}\\n".encode())
                                    self.wfile.write(f"data: {json.dumps(event['data'])}\\n\\n".encode())
                                    self.wfile.flush()

                    # Send keep-alive every 15 seconds
                    time.sleep(0.5)
                    self.wfile.write(b': keep-alive\\n\\n')
                    self.wfile.flush()

                except BrokenPipeError:
                    break
                except Exception as e:
                    print(f"Error: {e}")
                    break

        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # Suppress logs

with socketserver.TCPServer(("0.0.0.0", PORT), SSEHandler) as httpd:
    print(f"SSE Server running on port {PORT}")
    httpd.serve_forever()
EOF

    local server_pid=$!
    echo "${server_pid}" > "${EVENTS_DIR}/sse-server.pid"

    echo "  ✓ SSE Server started (PID: ${server_pid})"
    echo ""
    echo "  Connect to: http://localhost:${port}/events"
    echo ""
    echo "  Example JavaScript client:"
    echo "    const eventSource = new EventSource('http://localhost:${port}/events');"
    echo "    eventSource.addEventListener('decision', (e) => console.log(JSON.parse(e.data)));"
}

stop_sse_server() {
    if [[ ! -f "${EVENTS_DIR}/sse-server.pid" ]]; then
        echo "No SSE server running"
        return 0
    fi

    local pid
    pid=$(cat "${EVENTS_DIR}/sse-server.pid")

    if ps -p "${pid}" > /dev/null 2>&1; then
        echo "Stopping SSE server (PID: ${pid})..."
        kill "${pid}"
        rm "${EVENTS_DIR}/sse-server.pid"
        echo "✓ SSE server stopped"
    else
        echo "SSE server not running (stale PID file)"
        rm "${EVENTS_DIR}/sse-server.pid"
    fi
}

push_to_sse_server() {
    local event="$1"

    # Event is already in stream, SSE server will pick it up via tail
    debug "Event queued for SSE broadcast"
}

# === Event Stream Viewer (CLI) ===

watch_events() {
    local event_type="${1:-all}"

    echo "👁️  Watching Event Stream (type: ${event_type})"
    echo "  Press Ctrl+C to stop"
    echo ""

    # Initialize stream if doesn't exist
    touch "${EVENT_STREAM}"

    # Tail event stream with filtering
    if [[ "${event_type}" == "all" ]]; then
        tail -f "${EVENT_STREAM}" | while IFS= read -r line; do
            local event
            event=$(echo "${line}" | jq -c '.')

            local event_id
            event_id=$(echo "${event}" | jq -r '.id')

            local event_name
            event_name=$(echo "${event}" | jq -r '.event')

            local event_data
            event_data=$(echo "${event}" | jq -c '.data')

            echo "[${event_id}] ${event_name}: ${event_data}"
        done
    else
        tail -f "${EVENT_STREAM}" | while IFS= read -r line; do
            local event
            event=$(echo "${line}" | jq -c '.')

            local event_name
            event_name=$(echo "${event}" | jq -r '.event')

            if [[ "${event_name}" == "${event_type}" ]]; then
                local event_id
                event_id=$(echo "${event}" | jq -r '.id')

                local event_data
                event_data=$(echo "${event}" | jq -c '.data')

                echo "[${event_id}] ${event_name}: ${event_data}"
            fi
        done
    fi
}

# === Event Statistics ===

event_stats() {
    if [[ ! -f "${EVENT_STREAM}" ]]; then
        echo "No events recorded yet"
        return 0
    fi

    echo "📊 Event Stream Statistics"
    echo ""

    local total_events
    total_events=$(wc -l < "${EVENT_STREAM}" | tr -d ' ')

    echo "Total Events: ${total_events}"
    echo ""

    # By event type
    echo "┌─ By Event Type ─────────────────────────┐"
    jq -s 'group_by(.event) |
        map({
            type: .[0].event,
            count: length
        }) |
        .[] |
        "│ " + .type + ": " + (.count | tostring)' \
        "${EVENT_STREAM}"
    echo "└─────────────────────────────────────────┘"
    echo ""

    # Recent events
    echo "Recent Events (last 10):"
    tail -10 "${EVENT_STREAM}" | jq -r '"  [\(.id)] \(.event): \(.data | @json)"'
}

# === Demo Mode ===

demo_events() {
    echo "🎬 Event Streaming Demo"
    echo ""

    # Simulate a workflow with events
    emit_status_event "started" "Beginning automation workflow"
    sleep 1

    emit_progress_event "multi-agent-routing" 1 5 "Analyzing prompt complexity"
    sleep 1

    emit_decision_event "auto_routing" "proceed_to_stage2" "0.85" "High token budget and keyword density"
    sleep 1

    emit_progress_event "multi-agent-routing" 2 5 "Invoking task analyzer"
    sleep 1

    emit_tool_call_event "multi-agent:task-analyzer" "analyze" "started" ""
    sleep 2

    emit_tool_call_event "multi-agent:task-analyzer" "analyze" "completed" '{"complexity":65,"pattern":"parallel"}'
    sleep 1

    emit_progress_event "multi-agent-routing" 3 5 "Checking auto-approval thresholds"
    sleep 1

    emit_decision_event "auto_routing" "auto_approved" "0.90" "Complexity within learned threshold"
    sleep 1

    emit_progress_event "multi-agent-routing" 4 5 "Coordinating agents"
    sleep 1

    emit_tool_call_event "multi-agent:coordinator" "coordinate" "started" ""
    sleep 2

    emit_progress_event "multi-agent-routing" 5 5 "Workflow complete"
    sleep 1

    emit_completion_event "multi-agent-routing" "success" "8500"

    echo "✓ Demo complete"
    echo ""
    echo "View events:"
    echo "  bash scripts/streaming-events.sh stats"
    echo "  bash scripts/streaming-events.sh watch"
}

# === Main ===

main() {
    local command="${1:-stats}"
    shift || true

    case "${command}" in
        emit)
            if [[ $# -lt 2 ]]; then
                echo "Usage: streaming-events.sh emit <type> <data_json>"
                exit 1
            fi

            emit_event "$1" "$2"
            ;;

        decision)
            if [[ $# -lt 4 ]]; then
                echo "Usage: streaming-events.sh decision <feature> <decision> <confidence> <reasoning>"
                exit 1
            fi

            emit_decision_event "$@"
            ;;

        tool-call)
            if [[ $# -lt 3 ]]; then
                echo "Usage: streaming-events.sh tool-call <tool> <action> <status> [result]"
                exit 1
            fi

            emit_tool_call_event "$@"
            ;;

        progress)
            if [[ $# -lt 4 ]]; then
                echo "Usage: streaming-events.sh progress <task> <current> <total> <message>"
                exit 1
            fi

            emit_progress_event "$@"
            ;;

        status)
            if [[ $# -lt 2 ]]; then
                echo "Usage: streaming-events.sh status <status> <message>"
                exit 1
            fi

            emit_status_event "$@"
            ;;

        error)
            if [[ $# -lt 2 ]]; then
                echo "Usage: streaming-events.sh error <type> <message> [recoverable]"
                exit 1
            fi

            emit_error_event "$@"
            ;;

        completion)
            if [[ $# -lt 2 ]]; then
                echo "Usage: streaming-events.sh completion <task> <result> [duration_ms]"
                exit 1
            fi

            emit_completion_event "$@"
            ;;

        start-server)
            start_sse_server "$@"
            ;;

        stop-server)
            stop_sse_server
            ;;

        watch)
            watch_events "$@"
            ;;

        stats)
            event_stats
            ;;

        demo)
            demo_events
            ;;

        *)
            cat <<'EOF'
Streaming Events - Real-time progress updates via Server-Sent Events (SSE)

USAGE:
  streaming-events.sh emit <type> <data_json>
  streaming-events.sh decision <feature> <decision> <confidence> <reasoning>
  streaming-events.sh tool-call <tool> <action> <status> [result]
  streaming-events.sh progress <task> <current> <total> <message>
  streaming-events.sh status <status> <message>
  streaming-events.sh error <type> <message> [recoverable]
  streaming-events.sh completion <task> <result> [duration_ms]

  streaming-events.sh start-server [port]
  streaming-events.sh stop-server
  streaming-events.sh watch [event_type]
  streaming-events.sh stats
  streaming-events.sh demo

EVENT TYPES:
  decision     Automation decisions (auto-routing, auto-approval)
  tool_call    Tool/agent invocations with status
  progress     Step-by-step progress tracking
  status       Workflow status updates
  error        Error events with recoverability info
  completion   Task completion with results

SSE SERVER:
  Port: ${SSE_PORT} (configurable via AUTOMATION_SSE_PORT)
  Endpoint: http://localhost:${SSE_PORT}/events

EXAMPLES:
  # Start SSE server for real-time updates
  streaming-events.sh start-server

  # Emit events
  streaming-events.sh decision "auto_routing" "approved" "0.92" "High confidence"
  streaming-events.sh progress "task-1" 3 10 "Processing step 3"

  # Watch events (CLI)
  streaming-events.sh watch
  streaming-events.sh watch decision

  # Run demo
  streaming-events.sh demo

CLIENT EXAMPLE (JavaScript):
  const eventSource = new EventSource('http://localhost:${SSE_PORT}/events');

  eventSource.addEventListener('decision', (e) => {
    const data = JSON.parse(e.data);
    console.log('Decision:', data.decision, 'Confidence:', data.confidence);
  });

  eventSource.addEventListener('progress', (e) => {
    const data = JSON.parse(e.data);
    updateProgressBar(data.progress_percent);
  });

RESEARCH:
  - SSE for AI agent transparency and real-time UX
  - FastAPI streaming patterns for agent progress
  - Tool call visibility and decision tracing
  - Real-time updates reduce latency perception

EOF
            ;;
    esac
}

# Execute
main "$@"

exit 0
