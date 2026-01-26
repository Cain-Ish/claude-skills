#!/usr/bin/env bash
# Decision Tracer - Explainability and decision history for AI agent transparency
# Based on 2026 research: EU AI Act compliance, mechanistic interpretability, chain of thought
# Provides full audit trail of automation decisions for regulatory and debugging needs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Configuration ===

TRACER_DIR="${HOME}/.claude/automation-hub/decision-tracer"
DECISION_LOG="${TRACER_DIR}/decisions.jsonl"
CHAIN_OF_THOUGHT_LOG="${TRACER_DIR}/chain-of-thought.jsonl"
DECISION_INDEX="${TRACER_DIR}/decision-index.json"
EXPORT_DIR="${TRACER_DIR}/exports"

# Decision types
DECISION_AUTO_ROUTING="auto_routing"
DECISION_AUTO_APPROVAL="auto_approval"
DECISION_AUTO_CLEANUP="auto_cleanup"
DECISION_AUTO_REFLECT="auto_reflect"
DECISION_AUTO_FIX="auto_fix"
DECISION_LEARNING="learning_optimization"

# === Initialize ===

mkdir -p "${TRACER_DIR}" "${EXPORT_DIR}"

# === Decision Logging ===

log_decision() {
    local decision_type="$1"
    local decision_outcome="$2"
    local decision_rationale="$3"
    local decision_confidence="$4"
    local decision_context="$5"

    local timestamp
    timestamp=$(date -u +%s)

    local decision_id
    decision_id=$(date +%s%N)

    # Create decision entry
    local decision_entry
    decision_entry=$(jq -n \
        --arg id "${decision_id}" \
        --arg timestamp "${timestamp}" \
        --arg type "${decision_type}" \
        --arg outcome "${decision_outcome}" \
        --arg rationale "${decision_rationale}" \
        --arg confidence "${decision_confidence}" \
        --arg context "${decision_context}" \
        '{
            id: $id,
            timestamp: ($timestamp | tonumber),
            decision_type: $type,
            outcome: $outcome,
            rationale: $rationale,
            confidence: ($confidence | tonumber),
            context: $context,
            recorded_at: (now | tostring)
        }')

    # Write to decision log
    echo "${decision_entry}" >> "${DECISION_LOG}"

    # Update index
    update_decision_index "${decision_id}" "${decision_type}" "${decision_outcome}"

    debug "Decision logged: ${decision_id} (${decision_type}: ${decision_outcome})"

    # Emit streaming event if SSE enabled
    if [[ -f "${SCRIPT_DIR}/streaming-events.sh" ]]; then
        bash "${SCRIPT_DIR}/streaming-events.sh" decision \
            "${decision_type}" \
            "${decision_outcome}" \
            "${decision_confidence}" \
            "${decision_rationale}" 2>/dev/null || true
    fi
}

# === Chain of Thought Logging ===

log_chain_of_thought() {
    local decision_id="$1"
    local step_number="$2"
    local step_description="$3"
    local step_reasoning="$4"
    local step_data="${5:-{}}"

    local timestamp
    timestamp=$(date -u +%s)

    local cot_entry
    cot_entry=$(jq -n \
        --arg id "${decision_id}" \
        --arg timestamp "${timestamp}" \
        --arg step "${step_number}" \
        --arg description "${step_description}" \
        --arg reasoning "${step_reasoning}" \
        --argjson data "${step_data}" \
        '{
            decision_id: $id,
            timestamp: ($timestamp | tonumber),
            step: ($step | tonumber),
            description: $description,
            reasoning: $reasoning,
            data: $data
        }')

    echo "${cot_entry}" >> "${CHAIN_OF_THOUGHT_LOG}"

    debug "Chain of thought step ${step_number}: ${step_description}"
}

# === Decision Index Management ===

update_decision_index() {
    local decision_id="$1"
    local decision_type="$2"
    local outcome="$3"

    if [[ ! -f "${DECISION_INDEX}" ]]; then
        echo '{"by_type":{},"by_outcome":{},"total":0}' > "${DECISION_INDEX}"
    fi

    local index_data
    index_data=$(jq \
        --arg id "${decision_id}" \
        --arg type "${decision_type}" \
        --arg outcome "${outcome}" \
        '
        .total += 1 |
        .by_type[$type] = (.by_type[$type] // 0) + 1 |
        .by_outcome[$outcome] = (.by_outcome[$outcome] // 0) + 1
        ' "${DECISION_INDEX}")

    echo "${index_data}" > "${DECISION_INDEX}"
}

# === Auto-Routing Decision Tracing ===

trace_routing_decision() {
    local prompt="$1"
    local stage1_score="$2"
    local stage2_complexity="${3:-}"
    local final_decision="$4"
    local confidence="$5"

    local decision_id
    decision_id=$(date +%s%N)

    # Log main decision
    local rationale
    if [[ "${final_decision}" == "approved" ]]; then
        rationale="Stage 1 score: ${stage1_score}/10, Stage 2 complexity: ${stage2_complexity}, Auto-approved based on learned thresholds"
    elif [[ "${final_decision}" == "skipped" ]]; then
        rationale="Stage 1 score: ${stage1_score}/10 (< 4), Pre-filter determined prompt not complex enough for multi-agent"
    else
        rationale="Stage 1 score: ${stage1_score}/10, Stage 2 complexity: ${stage2_complexity}, Presenting to user for approval"
    fi

    local context
    context=$(jq -n \
        --arg prompt "${prompt:0:100}..." \
        --arg stage1 "${stage1_score}" \
        --arg stage2 "${stage2_complexity}" \
        '{
            prompt_preview: $prompt,
            stage1_score: $stage1,
            stage2_complexity: $stage2
        }')

    log_decision \
        "${DECISION_AUTO_ROUTING}" \
        "${final_decision}" \
        "${rationale}" \
        "${confidence}" \
        "$(echo "${context}" | jq -c '.')"

    # Log chain of thought
    log_chain_of_thought "${decision_id}" 1 \
        "Stage 1 Pre-Filter Analysis" \
        "Analyzed prompt signals: token budget, keyword density, multi-domain detection, complexity keywords, user preference" \
        "$(jq -n --arg score "${stage1_score}" '{stage1_score: $score}')"

    if [[ -n "${stage2_complexity}" ]]; then
        log_chain_of_thought "${decision_id}" 2 \
            "Stage 2 Complexity Analysis" \
            "Invoked task-analyzer agent to determine complexity score and recommended pattern" \
            "$(jq -n --arg complexity "${stage2_complexity}" '{complexity: $complexity}')"

        log_chain_of_thought "${decision_id}" 3 \
            "Auto-Approval Check" \
            "Compared complexity against learned user approval thresholds for this band" \
            "$(jq -n --arg decision "${final_decision}" '{final_decision: $decision}')"
    fi
}

# === Auto-Cleanup Decision Tracing ===

trace_cleanup_decision() {
    local trigger="$1"
    local safety_checks="$2"
    local final_decision="$3"
    local confidence="$4"

    local rationale
    if [[ "${final_decision}" == "approved" ]]; then
        rationale="Trigger: ${trigger}, All safety checks passed: ${safety_checks}"
    else
        rationale="Trigger: ${trigger}, Safety blocker detected: ${safety_checks}"
    fi

    local context
    context=$(jq -n \
        --arg trigger "${trigger}" \
        --arg checks "${safety_checks}" \
        '{
            trigger: $trigger,
            safety_checks: $checks
        }')

    log_decision \
        "${DECISION_AUTO_CLEANUP}" \
        "${final_decision}" \
        "${rationale}" \
        "${confidence}" \
        "$(echo "${context}" | jq -c '.')"
}

# === Decision History Query ===

query_decisions() {
    local query_type="${1:-all}"
    local limit="${2:-10}"

    if [[ ! -f "${DECISION_LOG}" ]]; then
        echo "No decisions logged yet"
        return 0
    fi

    echo "📊 Decision History (${query_type})"
    echo ""

    case "${query_type}" in
        all)
            tail -${limit} "${DECISION_LOG}" | jq -r \
                '"[\(.id)] \(.decision_type): \(.outcome) (confidence: \(.confidence))"'
            ;;

        type)
            local decision_type="${3:-auto_routing}"
            jq -s --arg type "${decision_type}" \
                'map(select(.decision_type == $type)) | .[-'"${limit}"':] | .[] |
                "[\(.id)] \(.outcome) (confidence: \(.confidence)) - \(.rationale)"' \
                "${DECISION_LOG}"
            ;;

        outcome)
            local outcome="${3:-approved}"
            jq -s --arg outcome "${outcome}" \
                'map(select(.outcome == $outcome)) | .[-'"${limit}"':] | .[] |
                "[\(.id)] \(.decision_type): \(.outcome) - \(.rationale)"' \
                "${DECISION_LOG}"
            ;;

        recent)
            local hours="${3:-24}"
            local cutoff_time
            cutoff_time=$(($(date +%s) - (hours * 3600)))

            jq -s --arg cutoff "${cutoff_time}" \
                'map(select(.timestamp >= ($cutoff | tonumber))) | .[] |
                "[\(.id)] \(.decision_type): \(.outcome) (confidence: \(.confidence))"' \
                "${DECISION_LOG}"
            ;;

        *)
            echo "Unknown query type: ${query_type}"
            return 1
            ;;
    esac
}

# === Chain of Thought Replay ===

replay_chain_of_thought() {
    local decision_id="$1"

    echo "🔍 Chain of Thought Replay: ${decision_id}"
    echo ""

    if [[ ! -f "${CHAIN_OF_THOUGHT_LOG}" ]]; then
        echo "No chain of thought data available"
        return 0
    fi

    # Get decision details
    local decision
    decision=$(jq -s --arg id "${decision_id}" \
        'map(select(.id == $id)) | .[0]' \
        "${DECISION_LOG}")

    if [[ "${decision}" == "null" ]]; then
        echo "Decision ${decision_id} not found"
        return 1
    fi

    local decision_type
    decision_type=$(echo "${decision}" | jq -r '.decision_type')

    local outcome
    outcome=$(echo "${decision}" | jq -r '.outcome')

    echo "Decision: ${decision_type} → ${outcome}"
    echo ""

    # Get chain of thought steps
    jq -s --arg id "${decision_id}" \
        'map(select(.decision_id == $id)) | sort_by(.step) | .[] |
        "Step \(.step): \(.description)\n  Reasoning: \(.reasoning)\n  Data: \(.data | @json)\n"' \
        "${CHAIN_OF_THOUGHT_LOG}"
}

# === Decision Export (EU AI Act Compliance) ===

export_decision_history() {
    local export_format="${1:-json}"
    local start_date="${2:-}"
    local end_date="${3:-}"

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    local export_file
    export_file="${EXPORT_DIR}/decisions_${timestamp}.${export_format}"

    echo "📤 Exporting decision history to: ${export_file}"
    echo ""

    if [[ ! -f "${DECISION_LOG}" ]]; then
        echo "No decisions to export"
        return 0
    fi

    case "${export_format}" in
        json)
            # Filter by date range if provided
            if [[ -n "${start_date}" ]] && [[ -n "${end_date}" ]]; then
                local start_timestamp
                start_timestamp=$(date -j -f "%Y-%m-%d" "${start_date}" +%s 2>/dev/null || date -d "${start_date}" +%s)

                local end_timestamp
                end_timestamp=$(date -j -f "%Y-%m-%d" "${end_date}" +%s 2>/dev/null || date -d "${end_date}" +%s)

                jq -s --arg start "${start_timestamp}" --arg end "${end_timestamp}" \
                    'map(select(.timestamp >= ($start | tonumber) and .timestamp <= ($end | tonumber)))' \
                    "${DECISION_LOG}" > "${export_file}"
            else
                jq -s '.' "${DECISION_LOG}" > "${export_file}"
            fi
            ;;

        csv)
            # CSV export for spreadsheet analysis
            {
                echo "id,timestamp,decision_type,outcome,confidence,rationale"
                jq -r '.id + "," + (.timestamp | tostring) + "," + .decision_type + "," + .outcome + "," + (.confidence | tostring) + "," + .rationale' \
                    "${DECISION_LOG}"
            } > "${export_file}"
            ;;

        audit)
            # Comprehensive audit format (JSON with chain of thought)
            {
                echo '{"decisions":['
                jq -s '.' "${DECISION_LOG}"
                echo '],"chain_of_thought":['
                jq -s '.' "${CHAIN_OF_THOUGHT_LOG}" 2>/dev/null || echo '[]'
                echo '],"exported_at":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
            } | jq '.' > "${export_file}"
            ;;

        *)
            echo "Unknown export format: ${export_format}"
            return 1
            ;;
    esac

    local total_decisions
    total_decisions=$(wc -l < "${DECISION_LOG}" | tr -d ' ')

    echo "✓ Exported ${total_decisions} decisions"
    echo "  Format: ${export_format}"
    echo "  File: ${export_file}"
}

# === Decision Statistics ===

decision_stats() {
    echo "📊 Decision Tracer Statistics"
    echo ""

    if [[ ! -f "${DECISION_LOG}" ]]; then
        echo "No decisions logged yet"
        return 0
    fi

    local total_decisions
    total_decisions=$(wc -l < "${DECISION_LOG}" | tr -d ' ')

    echo "┌─ Overall ───────────────────────────────┐"
    echo "│ Total Decisions: ${total_decisions}"
    echo "└─────────────────────────────────────────┘"
    echo ""

    # By decision type
    echo "┌─ By Decision Type ──────────────────────┐"
    jq -s 'group_by(.decision_type) |
        map({
            type: .[0].decision_type,
            count: length,
            avg_confidence: (map(.confidence) | add / length)
        }) |
        .[] |
        "│ " + .type + ": " + (.count | tostring) + " decisions (avg confidence: " + (.avg_confidence | tostring) + ")"' \
        "${DECISION_LOG}"
    echo "└─────────────────────────────────────────┘"
    echo ""

    # By outcome
    echo "┌─ By Outcome ────────────────────────────┐"
    jq -s 'group_by(.outcome) |
        map({
            outcome: .[0].outcome,
            count: length
        }) |
        .[] |
        "│ " + .outcome + ": " + (.count | tostring)' \
        "${DECISION_LOG}"
    echo "└─────────────────────────────────────────┘"
    echo ""

    # Confidence distribution
    echo "┌─ Confidence Distribution ───────────────┐"
    jq -s 'map(
            if .confidence >= 0.90 then "high"
            elif .confidence >= 0.70 then "medium"
            else "low"
            end
        ) |
        group_by(.) |
        map({
            level: .[0],
            count: length
        }) |
        .[] |
        "│ " + .level + ": " + (.count | tostring)' \
        "${DECISION_LOG}"
    echo "└─────────────────────────────────────────┘"
}

# === Main ===

main() {
    local command="${1:-stats}"
    shift || true

    case "${command}" in
        log)
            if [[ $# -lt 5 ]]; then
                echo "Usage: decision-tracer.sh log <type> <outcome> <rationale> <confidence> <context>"
                exit 1
            fi

            log_decision "$@"
            ;;

        trace-routing)
            if [[ $# -lt 5 ]]; then
                echo "Usage: decision-tracer.sh trace-routing <prompt> <stage1_score> <stage2_complexity> <decision> <confidence>"
                exit 1
            fi

            trace_routing_decision "$@"
            ;;

        trace-cleanup)
            if [[ $# -lt 4 ]]; then
                echo "Usage: decision-tracer.sh trace-cleanup <trigger> <safety_checks> <decision> <confidence>"
                exit 1
            fi

            trace_cleanup_decision "$@"
            ;;

        cot)
            if [[ $# -lt 4 ]]; then
                echo "Usage: decision-tracer.sh cot <decision_id> <step> <description> <reasoning> [data_json]"
                exit 1
            fi

            log_chain_of_thought "$@"
            ;;

        query)
            query_decisions "$@"
            ;;

        replay)
            if [[ $# -eq 0 ]]; then
                echo "Usage: decision-tracer.sh replay <decision_id>"
                exit 1
            fi

            replay_chain_of_thought "$1"
            ;;

        export)
            export_decision_history "$@"
            ;;

        stats)
            decision_stats
            ;;

        *)
            cat <<'EOF'
Decision Tracer - Explainability and audit trail for AI automation decisions

USAGE:
  decision-tracer.sh log <type> <outcome> <rationale> <confidence> <context>
  decision-tracer.sh trace-routing <prompt> <stage1_score> <stage2_complexity> <decision> <confidence>
  decision-tracer.sh trace-cleanup <trigger> <safety_checks> <decision> <confidence>
  decision-tracer.sh cot <decision_id> <step> <description> <reasoning> [data_json]
  decision-tracer.sh query [all|type|outcome|recent] [limit]
  decision-tracer.sh replay <decision_id>
  decision-tracer.sh export [json|csv|audit] [start_date] [end_date]
  decision-tracer.sh stats

DECISION TYPES:
  auto_routing          Multi-agent routing decisions
  auto_approval         Auto-approval of complexity analysis
  auto_cleanup          Cleanup trigger decisions
  auto_reflect          Reflection worthiness decisions
  auto_fix              Auto-fix application decisions
  learning_optimization Learning system optimization proposals

EXAMPLES:
  # Log a routing decision
  decision-tracer.sh trace-routing "build complex API" 8 65 "approved" 0.85

  # Query recent decisions
  decision-tracer.sh query recent 24  # Last 24 hours

  # Replay chain of thought
  decision-tracer.sh replay 1737840123456789000

  # Export for EU AI Act compliance
  decision-tracer.sh export audit 2026-01-01 2026-12-31

RESEARCH:
  - EU AI Act transparency requirements (deadline: August 2026)
  - Mechanistic interpretability for AI decision understanding
  - Chain of thought logging for debugging and compliance
  - Audit trail generation for regulatory reporting

EOF
            ;;
    esac
}

# Execute
main "$@"

exit 0
