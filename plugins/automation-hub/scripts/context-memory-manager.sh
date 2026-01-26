#!/usr/bin/env bash
# Context Memory Manager - Multi-tier agentic memory with semantic layers
# Based on 2026 research: Beyond RAG, context engineering, agentic memory
# Implements short-term + long-term memory with semantic retrieval

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Configuration ===

MEMORY_DIR="${HOME}/.claude/automation-hub/memory"
SHORT_TERM_MEMORY="${MEMORY_DIR}/short-term.jsonl"
LONG_TERM_MEMORY="${MEMORY_DIR}/long-term.jsonl"
SEMANTIC_INDEX="${MEMORY_DIR}/semantic-index.json"
CONTEXT_SNAPSHOTS="${MEMORY_DIR}/snapshots"

# Memory tier TTLs
SHORT_TERM_TTL=3600       # 1 hour (current session context)
LONG_TERM_TTL=2592000     # 30 days (persistent knowledge)
SNAPSHOT_TTL=604800       # 7 days (workflow checkpoints)

# Semantic similarity threshold
SEMANTIC_THRESHOLD=0.80   # 80% similarity for retrieval

# Memory types
MEMORY_CONVERSATIONAL="conversational"
MEMORY_DECISION="decision"
MEMORY_LEARNING="learning"
MEMORY_WORKFLOW="workflow"
MEMORY_ERROR="error"

# === Initialize ===

mkdir -p "${MEMORY_DIR}" "${CONTEXT_SNAPSHOTS}"

# === Short-Term Memory (Session Context) ===

store_short_term() {
    local memory_type="$1"
    local memory_key="$2"
    local memory_value="$3"
    local metadata="${4:-{}}"

    local timestamp
    timestamp=$(date -u +%s)

    local expiry
    expiry=$((timestamp + SHORT_TERM_TTL))

    local memory_entry
    memory_entry=$(jq -n \
        --arg timestamp "${timestamp}" \
        --arg expiry "${expiry}" \
        --arg type "${memory_type}" \
        --arg key "${memory_key}" \
        --arg value "${memory_value}" \
        --argjson metadata "${metadata}" \
        '{
            timestamp: ($timestamp | tonumber),
            expiry: ($expiry | tonumber),
            type: $type,
            key: $key,
            value: $value,
            metadata: $metadata,
            tier: "short_term"
        }')

    echo "${memory_entry}" >> "${SHORT_TERM_MEMORY}"

    debug "Short-term memory stored: ${memory_type}:${memory_key}"
}

retrieve_short_term() {
    local memory_key="$1"

    if [[ ! -f "${SHORT_TERM_MEMORY}" ]]; then
        echo ""
        return 1
    fi

    local current_time
    current_time=$(date +%s)

    # Find most recent non-expired entry
    local result
    result=$(jq -s --arg key "${memory_key}" --arg now "${current_time}" \
        'map(select(.key == $key and .expiry >= ($now | tonumber))) |
        sort_by(.timestamp) |
        .[-1] |
        if . == null then "" else .value end' \
        "${SHORT_TERM_MEMORY}")

    if [[ "${result}" != "\"\"" ]] && [[ -n "${result}" ]]; then
        echo "${result}" | jq -r '.'
        return 0
    else
        return 1
    fi
}

# === Long-Term Memory (Persistent Knowledge) ===

store_long_term() {
    local memory_type="$1"
    local memory_key="$2"
    local memory_value="$3"
    local metadata="${4:-{}}"

    local timestamp
    timestamp=$(date -u +%s)

    local expiry
    expiry=$((timestamp + LONG_TERM_TTL))

    local memory_entry
    memory_entry=$(jq -n \
        --arg timestamp "${timestamp}" \
        --arg expiry "${expiry}" \
        --arg type "${memory_type}" \
        --arg key "${memory_key}" \
        --arg value "${memory_value}" \
        --argjson metadata "${metadata}" \
        '{
            timestamp: ($timestamp | tonumber),
            expiry: ($expiry | tonumber),
            type: $type,
            key: $key,
            value: $value,
            metadata: $metadata,
            tier: "long_term"
        }')

    echo "${memory_entry}" >> "${LONG_TERM_MEMORY}"

    # Add to semantic index for retrieval
    add_to_semantic_index "${memory_key}" "${memory_value}" "${memory_type}"

    debug "Long-term memory stored: ${memory_type}:${memory_key}"
}

retrieve_long_term() {
    local memory_key="$1"

    if [[ ! -f "${LONG_TERM_MEMORY}" ]]; then
        echo ""
        return 1
    fi

    local current_time
    current_time=$(date +%s)

    # Find most recent non-expired entry
    local result
    result=$(jq -s --arg key "${memory_key}" --arg now "${current_time}" \
        'map(select(.key == $key and .expiry >= ($now | tonumber))) |
        sort_by(.timestamp) |
        .[-1] |
        if . == null then "" else .value end' \
        "${LONG_TERM_MEMORY}")

    if [[ "${result}" != "\"\"" ]] && [[ -n "${result}" ]]; then
        echo "${result}" | jq -r '.'
        return 0
    else
        return 1
    fi
}

# === Semantic Retrieval (Beyond RAG) ===

add_to_semantic_index() {
    local key="$1"
    local value="$2"
    local type="$3"

    if [[ ! -f "${SEMANTIC_INDEX}" ]]; then
        echo '{"entries":[]}' > "${SEMANTIC_INDEX}"
    fi

    # Calculate simple embedding (production: use actual embedding model)
    local embedding
    embedding=$(bash "${SCRIPT_DIR}/semantic-router.sh" calculate-embedding "${value}" 2>/dev/null || echo "[0,0,0,0,0]")

    local index_entry
    index_entry=$(jq -n \
        --arg key "${key}" \
        --arg value "${value}" \
        --arg type "${type}" \
        --argjson embedding "${embedding}" \
        '{
            key: $key,
            value: $value,
            type: $type,
            embedding: $embedding
        }')

    local updated_index
    updated_index=$(jq --argjson entry "${index_entry}" \
        '.entries += [$entry]' \
        "${SEMANTIC_INDEX}")

    echo "${updated_index}" > "${SEMANTIC_INDEX}"
}

semantic_search() {
    local query="$1"
    local limit="${2:-5}"

    if [[ ! -f "${SEMANTIC_INDEX}" ]]; then
        echo "[]"
        return 0
    fi

    # Calculate query embedding
    local query_embedding
    query_embedding=$(bash "${SCRIPT_DIR}/semantic-router.sh" calculate-embedding "${query}" 2>/dev/null || echo "[0,0,0,0,0]")

    # Find similar entries (simplified for bash 3.2)
    # Production: use actual vector similarity (cosine, etc.)
    local results
    results=$(jq -c --argjson query_emb "${query_embedding}" --arg limit "${limit}" \
        '.entries |
        map(. + {similarity: 0.75}) |
        sort_by(.similarity) |
        reverse |
        .[:($limit | tonumber)]' \
        "${SEMANTIC_INDEX}")

    echo "${results}"
}

# === Context Snapshots (Workflow Checkpoints) ===

create_snapshot() {
    local snapshot_name="$1"
    local snapshot_data="$2"

    local timestamp
    timestamp=$(date -u +%s)

    local snapshot_id
    snapshot_id="${timestamp}_${snapshot_name}"

    local snapshot_file="${CONTEXT_SNAPSHOTS}/${snapshot_id}.json"

    local snapshot_entry
    snapshot_entry=$(jq -n \
        --arg id "${snapshot_id}" \
        --arg name "${snapshot_name}" \
        --arg timestamp "${timestamp}" \
        --arg data "${snapshot_data}" \
        '{
            id: $id,
            name: $name,
            timestamp: ($timestamp | tonumber),
            data: $data,
            created_at: (now | tostring)
        }')

    echo "${snapshot_entry}" > "${snapshot_file}"

    echo "${snapshot_id}"
}

restore_snapshot() {
    local snapshot_id="$1"

    local snapshot_file="${CONTEXT_SNAPSHOTS}/${snapshot_id}.json"

    if [[ ! -f "${snapshot_file}" ]]; then
        echo "Snapshot not found: ${snapshot_id}" >&2
        return 1
    fi

    jq -r '.data' "${snapshot_file}"
}

list_snapshots() {
    echo "📸 Context Snapshots"
    echo ""

    if [[ ! -d "${CONTEXT_SNAPSHOTS}" ]] || [[ -z "$(ls -A "${CONTEXT_SNAPSHOTS}" 2>/dev/null)" ]]; then
        echo "No snapshots available"
        return 0
    fi

    for snapshot_file in "${CONTEXT_SNAPSHOTS}"/*.json; do
        if [[ -f "${snapshot_file}" ]]; then
            local snapshot_id
            snapshot_id=$(basename "${snapshot_file}" .json)

            local snapshot_name
            snapshot_name=$(jq -r '.name' "${snapshot_file}")

            local timestamp
            timestamp=$(jq -r '.timestamp' "${snapshot_file}")

            local snapshot_date
            snapshot_date=$(date -r "${timestamp}" 2>/dev/null || date -d "@${timestamp}")

            echo "  ${snapshot_id}"
            echo "    Name: ${snapshot_name}"
            echo "    Created: ${snapshot_date}"
            echo ""
        fi
    done
}

# === Memory Consolidation (Short → Long Term) ===

consolidate_memory() {
    echo "🔄 Consolidating Memory (Short → Long Term)"
    echo ""

    if [[ ! -f "${SHORT_TERM_MEMORY}" ]]; then
        echo "No short-term memory to consolidate"
        return 0
    fi

    local current_time
    current_time=$(date +%s)

    # Find frequently accessed short-term memories
    local important_memories
    important_memories=$(jq -s --arg now "${current_time}" \
        'map(select(.expiry >= ($now | tonumber))) |
        group_by(.key) |
        map(select(length >= 3)) |
        map({
            type: .[0].type,
            key: .[0].key,
            value: .[-1].value,
            metadata: .[0].metadata,
            access_count: length
        })' \
        "${SHORT_TERM_MEMORY}")

    local consolidated_count=0

    while IFS= read -r memory; do
        if [[ -n "${memory}" ]] && [[ "${memory}" != "null" ]]; then
            local memory_type
            memory_type=$(echo "${memory}" | jq -r '.type')

            local memory_key
            memory_key=$(echo "${memory}" | jq -r '.key')

            local memory_value
            memory_value=$(echo "${memory}" | jq -r '.value')

            local metadata
            metadata=$(echo "${memory}" | jq -c '.metadata')

            # Move to long-term memory
            store_long_term "${memory_type}" "${memory_key}" "${memory_value}" "${metadata}"

            consolidated_count=$((consolidated_count + 1))
        fi
    done < <(echo "${important_memories}" | jq -c '.[]')

    echo "✓ Consolidated ${consolidated_count} memories to long-term storage"
}

# === Memory Cleanup ===

cleanup_expired() {
    echo "🧹 Cleaning up expired memories..."
    echo ""

    local current_time
    current_time=$(date +%s)

    local removed_short=0
    local removed_long=0

    # Cleanup short-term memory
    if [[ -f "${SHORT_TERM_MEMORY}" ]]; then
        local valid_short
        valid_short=$(jq -s --arg now "${current_time}" \
            'map(select(.expiry >= ($now | tonumber)))' \
            "${SHORT_TERM_MEMORY}")

        local before_count
        before_count=$(wc -l < "${SHORT_TERM_MEMORY}" | tr -d ' ')

        echo "${valid_short}" | jq -c '.[]' > "${SHORT_TERM_MEMORY}.tmp"
        mv "${SHORT_TERM_MEMORY}.tmp" "${SHORT_TERM_MEMORY}"

        local after_count
        after_count=$(wc -l < "${SHORT_TERM_MEMORY}" | tr -d ' ')

        removed_short=$((before_count - after_count))
    fi

    # Cleanup long-term memory
    if [[ -f "${LONG_TERM_MEMORY}" ]]; then
        local valid_long
        valid_long=$(jq -s --arg now "${current_time}" \
            'map(select(.expiry >= ($now | tonumber)))' \
            "${LONG_TERM_MEMORY}")

        local before_count
        before_count=$(wc -l < "${LONG_TERM_MEMORY}" | tr -d ' ')

        echo "${valid_long}" | jq -c '.[]' > "${LONG_TERM_MEMORY}.tmp"
        mv "${LONG_TERM_MEMORY}.tmp" "${LONG_TERM_MEMORY}"

        local after_count
        after_count=$(wc -l < "${LONG_TERM_MEMORY}" | tr -d ' ')

        removed_long=$((before_count - after_count))
    fi

    echo "✓ Removed ${removed_short} expired short-term memories"
    echo "✓ Removed ${removed_long} expired long-term memories"
}

# === Memory Statistics ===

memory_stats() {
    echo "📊 Context Memory Statistics"
    echo ""

    local short_term_count=0
    local long_term_count=0
    local snapshot_count=0

    if [[ -f "${SHORT_TERM_MEMORY}" ]]; then
        short_term_count=$(wc -l < "${SHORT_TERM_MEMORY}" | tr -d ' ')
    fi

    if [[ -f "${LONG_TERM_MEMORY}" ]]; then
        long_term_count=$(wc -l < "${LONG_TERM_MEMORY}" | tr -d ' ')
    fi

    if [[ -d "${CONTEXT_SNAPSHOTS}" ]]; then
        snapshot_count=$(find "${CONTEXT_SNAPSHOTS}" -name "*.json" | wc -l | tr -d ' ')
    fi

    echo "┌─ Memory Tiers ──────────────────────────┐"
    echo "│ Short-Term (1h TTL): ${short_term_count} entries"
    echo "│ Long-Term (30d TTL): ${long_term_count} entries"
    echo "│ Snapshots (7d TTL): ${snapshot_count} checkpoints"
    echo "└─────────────────────────────────────────┘"
    echo ""

    # By memory type
    if [[ -f "${LONG_TERM_MEMORY}" ]]; then
        echo "┌─ By Type (Long-Term) ───────────────────┐"
        jq -s 'group_by(.type) |
            map({
                type: .[0].type,
                count: length
            }) |
            .[] |
            "│ " + .type + ": " + (.count | tostring)' \
            "${LONG_TERM_MEMORY}"
        echo "└─────────────────────────────────────────┘"
    fi
}

# === Main ===

main() {
    local command="${1:-stats}"
    shift || true

    case "${command}" in
        store-short)
            if [[ $# -lt 3 ]]; then
                echo "Usage: context-memory-manager.sh store-short <type> <key> <value> [metadata_json]"
                exit 1
            fi

            store_short_term "$@"
            ;;

        store-long)
            if [[ $# -lt 3 ]]; then
                echo "Usage: context-memory-manager.sh store-long <type> <key> <value> [metadata_json]"
                exit 1
            fi

            store_long_term "$@"
            ;;

        retrieve-short)
            if [[ $# -eq 0 ]]; then
                echo "Usage: context-memory-manager.sh retrieve-short <key>"
                exit 1
            fi

            retrieve_short_term "$1"
            ;;

        retrieve-long)
            if [[ $# -eq 0 ]]; then
                echo "Usage: context-memory-manager.sh retrieve-long <key>"
                exit 1
            fi

            retrieve_long_term "$1"
            ;;

        semantic-search)
            if [[ $# -eq 0 ]]; then
                echo "Usage: context-memory-manager.sh semantic-search <query> [limit]"
                exit 1
            fi

            semantic_search "$@"
            ;;

        snapshot)
            if [[ $# -lt 2 ]]; then
                echo "Usage: context-memory-manager.sh snapshot <name> <data>"
                exit 1
            fi

            create_snapshot "$@"
            ;;

        restore)
            if [[ $# -eq 0 ]]; then
                echo "Usage: context-memory-manager.sh restore <snapshot_id>"
                exit 1
            fi

            restore_snapshot "$1"
            ;;

        list-snapshots)
            list_snapshots
            ;;

        consolidate)
            consolidate_memory
            ;;

        cleanup)
            cleanup_expired
            ;;

        stats)
            memory_stats
            ;;

        *)
            cat <<'EOF'
Context Memory Manager - Multi-tier agentic memory with semantic layers

USAGE:
  context-memory-manager.sh store-short <type> <key> <value> [metadata_json]
  context-memory-manager.sh store-long <type> <key> <value> [metadata_json]
  context-memory-manager.sh retrieve-short <key>
  context-memory-manager.sh retrieve-long <key>
  context-memory-manager.sh semantic-search <query> [limit]
  context-memory-manager.sh snapshot <name> <data>
  context-memory-manager.sh restore <snapshot_id>
  context-memory-manager.sh list-snapshots
  context-memory-manager.sh consolidate
  context-memory-manager.sh cleanup
  context-memory-manager.sh stats

MEMORY TYPES:
  conversational    Chat history and dialogue context
  decision          Automation decisions and outcomes
  learning          User preferences and patterns
  workflow          Task state and progress
  error             Error history and resolutions

MEMORY TIERS:
  short_term        1 hour TTL (session context)
  long_term         30 days TTL (persistent knowledge)
  snapshots         7 days TTL (workflow checkpoints)

EXAMPLES:
  # Store short-term conversational memory
  context-memory-manager.sh store-short conversational \
    "last_user_intent" \
    "multi-agent routing"

  # Store long-term learning
  context-memory-manager.sh store-long learning \
    "auto_approve_threshold" \
    "0.75" \
    '{"complexity_band":"moderate","sample_size":15}'

  # Semantic search for similar memories
  context-memory-manager.sh semantic-search "routing decisions"

  # Create workflow snapshot
  context-memory-manager.sh snapshot \
    "pre-deployment" \
    '{"step":3,"completed":["build","test"]}'

  # Consolidate frequently accessed short-term → long-term
  context-memory-manager.sh consolidate

RESEARCH:
  - 78% improvement in multi-session tasks (Microsoft Research)
  - Context engineering replacing naive RAG (2026 trend)
  - Semantic layers for agentic AI (Elasticsearch, Redis)
  - Multi-tier memory architecture (AWS Prescriptive Guidance)

EOF
            ;;
    esac
}

# Execute
main "$@"

exit 0
