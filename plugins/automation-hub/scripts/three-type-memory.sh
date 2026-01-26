#!/usr/bin/env bash
# Three-Type Memory Manager: Episodic, Semantic, Procedural
# Implements cognitive science-based memory architecture for AI agents

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

MEMORY_BASE="${HOME}/.claude/automation-hub/memory"
EPISODIC_DIR="${MEMORY_BASE}/episodic"
SEMANTIC_DIR="${MEMORY_BASE}/semantic"
PROCEDURAL_DIR="${MEMORY_BASE}/procedural"
INDEX_DIR="${MEMORY_BASE}/index"

# Initialize directories
mkdir -p "${EPISODIC_DIR}" "${SEMANTIC_DIR}" "${PROCEDURAL_DIR}" "${INDEX_DIR}"

# === EPISODIC MEMORY ===
# Stores specific experiences with full context

store_episode() {
    local episode_type="$1"  # session, reflection, interaction
    local goal="$2"
    local reasoning="$3"
    local actions="$4"       # JSON array
    local outcome="$5"       # success, partial, failure
    local reflection="${6:-}"

    local timestamp
    timestamp=$(date -u +%s)
    local session_id="${CLAUDE_SESSION_ID:-unknown}"

    local episode
    episode=$(jq -n \
        --arg ts "${timestamp}" \
        --arg sid "${session_id}" \
        --arg type "${episode_type}" \
        --arg goal "${goal}" \
        --arg reasoning "${reasoning}" \
        --argjson actions "${actions}" \
        --arg outcome "${outcome}" \
        --arg reflection "${reflection}" \
        '{
            timestamp: ($ts | tonumber),
            session_id: $sid,
            episode_type: $type,
            goal: $goal,
            reasoning: $reasoning,
            actions: $actions,
            outcome: $outcome,
            reflection: $reflection,
            memory_type: "episodic"
        }')

    echo "${episode}" >> "${EPISODIC_DIR}/${episode_type}s.jsonl"
    debug "Stored episodic memory: ${episode_type}"
}

retrieve_similar_episodes() {
    local query="$1"
    local limit="${2:-5}"
    local episode_type="${3:-}"  # Optional filter

    # Simple keyword matching (production: use embeddings)
    local results="[]"

    for file in "${EPISODIC_DIR}"/*.jsonl; do
        if [[ -f "${file}" ]]; then
            local file_results
            if [[ -n "${episode_type}" ]]; then
                file_results=$(jq -s --arg q "${query}" --arg type "${episode_type}" \
                    'map(select(.episode_type == $type and (.goal | ascii_downcase | contains($q | ascii_downcase))))' \
                    "${file}")
            else
                file_results=$(jq -s --arg q "${query}" \
                    'map(select(.goal | ascii_downcase | contains($q | ascii_downcase)))' \
                    "${file}")
            fi
            results=$(echo "${results}" "${file_results}" | jq -s 'add')
        fi
    done

    echo "${results}" | jq "sort_by(.timestamp) | reverse | .[:${limit}]"
}

# === SEMANTIC MEMORY ===
# Stores factual knowledge, rules, and patterns

store_fact() {
    local fact="$1"
    local source="$2"        # session, reflection, external
    local confidence="$3"    # 0.0-1.0
    local domain="${4:-general}"

    local timestamp
    timestamp=$(date -u +%s)

    local entry
    entry=$(jq -n \
        --arg ts "${timestamp}" \
        --arg fact "${fact}" \
        --arg source "${source}" \
        --arg conf "${confidence}" \
        --arg domain "${domain}" \
        '{
            timestamp: ($ts | tonumber),
            fact: $fact,
            source: $source,
            confidence: ($conf | tonumber),
            domain: $domain,
            memory_type: "semantic",
            reinforcement_count: 1
        }')

    # Check for existing similar fact and reinforce or add new
    if [[ -f "${SEMANTIC_DIR}/facts.jsonl" ]]; then
        local existing
        existing=$(grep -F "\"${fact}\"" "${SEMANTIC_DIR}/facts.jsonl" | tail -1 || echo "")
        if [[ -n "${existing}" ]]; then
            # Reinforce existing fact
            local new_count
            new_count=$(echo "${existing}" | jq '.reinforcement_count + 1')
            local new_conf
            new_conf=$(echo "${existing}" | jq --arg c "${confidence}" \
                '(.confidence + ($c | tonumber)) / 2')

            local reinforced
            reinforced=$(echo "${existing}" | jq \
                --arg count "${new_count}" \
                --arg conf "${new_conf}" \
                '.reinforcement_count = ($count | tonumber) | .confidence = ($conf | tonumber)')

            # Replace in file (simplified - production would use proper update)
            echo "${reinforced}" >> "${SEMANTIC_DIR}/facts.jsonl"
            debug "Reinforced semantic fact (count: ${new_count})"
            return
        fi
    fi

    echo "${entry}" >> "${SEMANTIC_DIR}/facts.jsonl"
    debug "Stored semantic fact: ${fact}"
}

store_rule() {
    local rule="$1"
    local condition="$2"     # When this is true...
    local action="$3"        # ...do this
    local evidence="$4"      # JSON array of supporting episodes
    local confidence="$5"

    local timestamp
    timestamp=$(date -u +%s)

    local entry
    entry=$(jq -n \
        --arg ts "${timestamp}" \
        --arg rule "${rule}" \
        --arg cond "${condition}" \
        --arg act "${action}" \
        --argjson evidence "${evidence}" \
        --arg conf "${confidence}" \
        '{
            timestamp: ($ts | tonumber),
            rule: $rule,
            condition: $cond,
            action: $act,
            evidence: $evidence,
            confidence: ($conf | tonumber),
            memory_type: "semantic",
            active: true
        }')

    echo "${entry}" >> "${SEMANTIC_DIR}/rules.jsonl"
    debug "Stored semantic rule: ${rule}"
}

store_pattern() {
    local pattern_name="$1"
    local description="$2"
    local occurrences="$3"   # JSON array of episode references
    local frequency="$4"     # How often observed

    local timestamp
    timestamp=$(date -u +%s)

    local entry
    entry=$(jq -n \
        --arg ts "${timestamp}" \
        --arg name "${pattern_name}" \
        --arg desc "${description}" \
        --argjson occurrences "${occurrences}" \
        --arg freq "${frequency}" \
        '{
            timestamp: ($ts | tonumber),
            pattern_name: $name,
            description: $desc,
            occurrences: $occurrences,
            frequency: ($freq | tonumber),
            memory_type: "semantic"
        }')

    echo "${entry}" >> "${SEMANTIC_DIR}/patterns.jsonl"
    debug "Stored semantic pattern: ${pattern_name}"
}

# === PROCEDURAL MEMORY ===
# Stores learned skills and behavioral patterns

store_skill_outcome() {
    local skill_name="$1"
    local outcome="$2"       # success, partial, failure
    local context="$3"       # JSON: { complexity, domain, etc. }
    local duration="$4"      # seconds

    local timestamp
    timestamp=$(date -u +%s)
    local session_id="${CLAUDE_SESSION_ID:-unknown}"

    local entry
    entry=$(jq -n \
        --arg ts "${timestamp}" \
        --arg sid "${session_id}" \
        --arg skill "${skill_name}" \
        --arg outcome "${outcome}" \
        --argjson context "${context}" \
        --arg dur "${duration}" \
        '{
            timestamp: ($ts | tonumber),
            session_id: $sid,
            skill: $skill,
            outcome: $outcome,
            context: $context,
            duration: ($dur | tonumber),
            memory_type: "procedural"
        }')

    echo "${entry}" >> "${PROCEDURAL_DIR}/skills.jsonl"
    debug "Stored procedural skill outcome: ${skill_name} → ${outcome}"
}

store_routing_pattern() {
    local prompt_type="$1"   # Keywords or classification
    local routed_to="$2"     # Agent/skill selected
    local was_correct="$3"   # true/false (user approved?)
    local complexity="$4"

    local timestamp
    timestamp=$(date -u +%s)

    local entry
    entry=$(jq -n \
        --arg ts "${timestamp}" \
        --arg prompt "${prompt_type}" \
        --arg routed "${routed_to}" \
        --arg correct "${was_correct}" \
        --arg comp "${complexity}" \
        '{
            timestamp: ($ts | tonumber),
            prompt_type: $prompt,
            routed_to: $routed,
            was_correct: ($correct == "true"),
            complexity: ($comp | tonumber),
            memory_type: "procedural"
        }')

    echo "${entry}" >> "${PROCEDURAL_DIR}/routing.jsonl"
    debug "Stored procedural routing pattern"
}

store_preference() {
    local preference_key="$1"
    local preference_value="$2"
    local evidence_type="$3"  # correction, approval, explicit
    local strength="$4"       # 0.0-1.0

    local timestamp
    timestamp=$(date -u +%s)

    local entry
    entry=$(jq -n \
        --arg ts "${timestamp}" \
        --arg key "${preference_key}" \
        --arg val "${preference_value}" \
        --arg evidence "${evidence_type}" \
        --arg str "${strength}" \
        '{
            timestamp: ($ts | tonumber),
            preference_key: $key,
            preference_value: $val,
            evidence_type: $evidence,
            strength: ($str | tonumber),
            memory_type: "procedural"
        }')

    echo "${entry}" >> "${PROCEDURAL_DIR}/preferences.jsonl"
    debug "Stored procedural preference: ${preference_key}"
}

# === MEMORY CONSOLIDATION ===
# Converts episodic → semantic/procedural over time

consolidate_memories() {
    log_info "Consolidating memories (episodic → semantic/procedural)..."

    local current_time
    current_time=$(date +%s)
    local consolidation_window=$((7 * 24 * 3600))  # 7 days
    local cutoff=$((current_time - consolidation_window))

    # Find patterns in episodic memory
    if [[ -f "${EPISODIC_DIR}/sessions.jsonl" ]]; then
        # Extract repeated patterns
        local patterns
        patterns=$(jq -s --arg cutoff "${cutoff}" '
            map(select(.timestamp >= ($cutoff | tonumber))) |
            group_by(.outcome) |
            map({
                outcome: .[0].outcome,
                count: length,
                common_goals: (map(.goal) | group_by(.) | map({goal: .[0], count: length}) | sort_by(.count) | reverse | .[:3])
            })
        ' "${EPISODIC_DIR}/sessions.jsonl")

        # Convert high-frequency patterns to semantic memory
        echo "${patterns}" | jq -c '.[] | select(.count >= 3)' | while read -r pattern; do
            local outcome
            outcome=$(echo "${pattern}" | jq -r '.outcome')
            local count
            count=$(echo "${pattern}" | jq -r '.count')
            store_pattern \
                "outcome_${outcome}" \
                "Sessions with ${outcome} outcome pattern" \
                "[]" \
                "${count}"
        done
    fi

    # Log consolidation
    jq -n --arg ts "${current_time}" '{
        timestamp: ($ts | tonumber),
        action: "consolidation",
        status: "complete"
    }' >> "${INDEX_DIR}/consolidation-log.jsonl"

    log_success "Consolidation complete"
}

# === MEMORY RETRIEVAL ===

retrieve_relevant() {
    local query="$1"
    local memory_types="${2:-all}"  # episodic,semantic,procedural or all
    local limit="${3:-10}"

    local results="[]"

    if [[ "${memory_types}" == "all" ]] || [[ "${memory_types}" == *"episodic"* ]]; then
        # Search episodic
        for file in "${EPISODIC_DIR}"/*.jsonl; do
            if [[ -f "${file}" ]]; then
                local matches
                matches=$(jq -s --arg q "${query}" \
                    'map(select(.goal | ascii_downcase | contains($q | ascii_downcase)))' \
                    "${file}")
                results=$(echo "${results}" "${matches}" | jq -s 'add')
            fi
        done
    fi

    if [[ "${memory_types}" == "all" ]] || [[ "${memory_types}" == *"semantic"* ]]; then
        # Search semantic
        for file in "${SEMANTIC_DIR}"/*.jsonl; do
            if [[ -f "${file}" ]]; then
                local matches
                matches=$(jq -s --arg q "${query}" \
                    'map(select(.fact // .rule // .pattern_name | ascii_downcase | contains($q | ascii_downcase)))' \
                    "${file}")
                results=$(echo "${results}" "${matches}" | jq -s 'add')
            fi
        done
    fi

    if [[ "${memory_types}" == "all" ]] || [[ "${memory_types}" == *"procedural"* ]]; then
        # Search procedural
        for file in "${PROCEDURAL_DIR}"/*.jsonl; do
            if [[ -f "${file}" ]]; then
                local matches
                matches=$(jq -s --arg q "${query}" \
                    'map(select(.skill // .preference_key // .prompt_type | ascii_downcase | contains($q | ascii_downcase)))' \
                    "${file}")
                results=$(echo "${results}" "${matches}" | jq -s 'add')
            fi
        done
    fi

    # Sort by recency, limit
    echo "${results}" | jq "sort_by(.timestamp) | reverse | .[:${limit}]"
}

# === MEMORY CLEANUP (Avoid Bloat) ===

cleanup_memories() {
    local retention_days="${1:-30}"
    local retention_seconds=$((retention_days * 24 * 3600))
    local cutoff=$(($(date +%s) - retention_seconds))

    log_info "Cleaning memories older than ${retention_days} days..."

    local removed_count=0

    for dir in "${EPISODIC_DIR}" "${SEMANTIC_DIR}" "${PROCEDURAL_DIR}"; do
        for file in "${dir}"/*.jsonl; do
            if [[ -f "${file}" ]]; then
                local before
                before=$(wc -l < "${file}" | tr -d ' ')

                jq -s --arg cutoff "${cutoff}" \
                    'map(select(.timestamp >= ($cutoff | tonumber)))' \
                    "${file}" | jq -c '.[]' > "${file}.tmp"
                mv "${file}.tmp" "${file}"

                local after
                after=$(wc -l < "${file}" | tr -d ' ')
                removed_count=$((removed_count + before - after))
            fi
        done
    done

    log_success "Removed ${removed_count} expired memory entries"
}

# === STATISTICS ===

memory_stats() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  THREE-TYPE MEMORY STATISTICS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    echo "EPISODIC MEMORY (Specific Experiences):"
    for file in "${EPISODIC_DIR}"/*.jsonl; do
        if [[ -f "${file}" ]]; then
            local name
            name=$(basename "${file}" .jsonl)
            local count
            count=$(wc -l < "${file}" | tr -d ' ')
            echo "  ${name}: ${count} entries"
        fi
    done

    echo ""
    echo "SEMANTIC MEMORY (Factual Knowledge):"
    for file in "${SEMANTIC_DIR}"/*.jsonl; do
        if [[ -f "${file}" ]]; then
            local name
            name=$(basename "${file}" .jsonl)
            local count
            count=$(wc -l < "${file}" | tr -d ' ')
            echo "  ${name}: ${count} entries"
        fi
    done

    echo ""
    echo "PROCEDURAL MEMORY (Behavioral Patterns):"
    for file in "${PROCEDURAL_DIR}"/*.jsonl; do
        if [[ -f "${file}" ]]; then
            local name
            name=$(basename "${file}" .jsonl)
            local count
            count=$(wc -l < "${file}" | tr -d ' ')
            echo "  ${name}: ${count} entries"
        fi
    done

    echo ""
    echo "2026 Research Foundation:"
    echo "  ✅ Episodic memory for specific experiences"
    echo "  ✅ Semantic memory for factual knowledge"
    echo "  ✅ Procedural memory for learned behaviors"
    echo "  ✅ Automatic consolidation (episodic → semantic/procedural)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# === MAIN ===

main() {
    local command="${1:-stats}"
    shift || true

    case "${command}" in
        # Episodic
        store-episode) store_episode "$@" ;;
        retrieve-episodes) retrieve_similar_episodes "$@" ;;

        # Semantic
        store-fact) store_fact "$@" ;;
        store-rule) store_rule "$@" ;;
        store-pattern) store_pattern "$@" ;;

        # Procedural
        store-skill) store_skill_outcome "$@" ;;
        store-routing) store_routing_pattern "$@" ;;
        store-preference) store_preference "$@" ;;

        # Retrieval
        retrieve) retrieve_relevant "$@" ;;

        # Maintenance
        consolidate) consolidate_memories ;;
        cleanup) cleanup_memories "$@" ;;
        stats) memory_stats ;;

        *)
            cat <<EOF
Three-Type Memory Manager

EPISODIC (Specific Experiences):
  store-episode <type> <goal> <reasoning> <actions_json> <outcome> [reflection]
  retrieve-episodes <query> [limit] [episode_type]

SEMANTIC (Factual Knowledge):
  store-fact <fact> <source> <confidence> [domain]
  store-rule <rule> <condition> <action> <evidence_json> <confidence>
  store-pattern <name> <description> <occurrences_json> <frequency>

PROCEDURAL (Behavioral Patterns):
  store-skill <skill_name> <outcome> <context_json> <duration>
  store-routing <prompt_type> <routed_to> <was_correct> <complexity>
  store-preference <key> <value> <evidence_type> <strength>

RETRIEVAL:
  retrieve <query> [memory_types] [limit]

MAINTENANCE:
  consolidate     - Convert episodic patterns to semantic/procedural
  cleanup [days]  - Remove memories older than N days (default: 30)
  stats           - Show memory statistics
EOF
            ;;
    esac
}

main "$@"
