#!/usr/bin/env bash
# Agent Registry Manager - Centralized agent discovery and capability management
# Based on 2026 research: Google Cloud AI Agent Marketplace, GoDaddy ANS Registry, automated discovery
# Implements agent registration, capability query, version management, and trust verification

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Configuration ===

REGISTRY_DIR="${HOME}/.claude/automation-hub/registry"
AGENTS_REGISTRY="${REGISTRY_DIR}/agents.json"
CAPABILITIES_INDEX="${REGISTRY_DIR}/capabilities-index.json"
VERSION_HISTORY="${REGISTRY_DIR}/version-history.jsonl"
TRUST_VERIFICATION="${REGISTRY_DIR}/trust-verification.json"
DISCOVERY_LOG="${REGISTRY_DIR}/discovery.jsonl"

# Trust levels
TRUST_VERIFIED="verified"
TRUST_TRUSTED="trusted"
TRUST_UNVERIFIED="unverified"
TRUST_SUSPICIOUS="suspicious"

# Agent status
STATUS_ACTIVE="active"
STATUS_INACTIVE="inactive"
STATUS_DEPRECATED="deprecated"
STATUS_BETA="beta"

# === Initialize ===

mkdir -p "${REGISTRY_DIR}"

initialize_registry() {
    if [[ ! -f "${AGENTS_REGISTRY}" ]]; then
        cat > "${AGENTS_REGISTRY}" <<'EOF'
{
  "agents": [],
  "last_updated": "",
  "registry_version": "1.0.0"
}
EOF
        echo "✓ Initialized agent registry"
    fi

    if [[ ! -f "${CAPABILITIES_INDEX}" ]]; then
        echo '{"capabilities":{},"last_indexed":""}' > "${CAPABILITIES_INDEX}"
        echo "✓ Initialized capabilities index"
    fi

    if [[ ! -f "${TRUST_VERIFICATION}" ]]; then
        cat > "${TRUST_VERIFICATION}" <<'EOF'
{
  "trust_policies": {
    "require_signature": false,
    "allow_unverified": true,
    "auto_trust_known_publishers": true
  },
  "trusted_publishers": [
    "automation-hub",
    "multi-agent",
    "claude-official"
  ],
  "verifications": []
}
EOF
        echo "✓ Initialized trust verification"
    fi
}

# === Agent Registration ===

register_agent() {
    local agent_id="$1"
    local agent_name="$2"
    local version="$3"
    local capabilities="$4"
    local publisher="${5:-unknown}"

    echo "📝 Registering Agent: ${agent_id}"
    echo "  Name: ${agent_name}"
    echo "  Version: ${version}"
    echo "  Publisher: ${publisher}"
    echo ""

    # Check if agent already exists
    local existing
    existing=$(jq -c --arg id "${agent_id}" \
        '.agents[] | select(.id == $id)' \
        "${AGENTS_REGISTRY}" 2>/dev/null || echo "")

    if [[ -n "${existing}" ]]; then
        echo "Agent already registered. Use update-agent to modify."
        return 1
    fi

    # Determine trust level
    local trust_level
    trust_level=$(determine_trust_level "${publisher}")

    # Parse capabilities
    local caps_array
    caps_array=$(echo "${capabilities}" | jq -c 'split(",")')

    # Create agent entry
    local agent_entry
    agent_entry=$(jq -n \
        --arg id "${agent_id}" \
        --arg name "${agent_name}" \
        --arg version "${version}" \
        --argjson capabilities "${caps_array}" \
        --arg publisher "${publisher}" \
        --arg trust "${trust_level}" \
        '{
            id: $id,
            name: $name,
            version: $version,
            capabilities: $capabilities,
            publisher: $publisher,
            trust_level: $trust,
            status: "active",
            registered_at: (now | tostring),
            last_updated: (now | tostring)
        }')

    # Add to registry
    local updated_registry
    updated_registry=$(jq --argjson agent "${agent_entry}" \
        '.agents += [$agent] | .last_updated = (now | tostring)' \
        "${AGENTS_REGISTRY}")

    echo "${updated_registry}" > "${AGENTS_REGISTRY}"

    # Index capabilities
    index_agent_capabilities "${agent_id}" "${caps_array}"

    # Log version
    log_version_change "${agent_id}" "" "${version}" "initial_registration"

    echo "✓ Agent registered successfully"
    echo "  ID: ${agent_id}"
    echo "  Trust Level: ${trust_level}"
}

update_agent() {
    local agent_id="$1"
    local field="$2"
    local value="$3"

    echo "🔄 Updating Agent: ${agent_id}"
    echo "  Field: ${field}"
    echo "  Value: ${value}"
    echo ""

    # Get current agent
    local current_agent
    current_agent=$(jq -c --arg id "${agent_id}" \
        '.agents[] | select(.id == $id)' \
        "${AGENTS_REGISTRY}" 2>/dev/null || echo "")

    if [[ -z "${current_agent}" ]]; then
        echo "Agent not found: ${agent_id}"
        return 1
    fi

    # Update field
    local updated_registry
    case "${field}" in
        version)
            local old_version
            old_version=$(echo "${current_agent}" | jq -r '.version')

            updated_registry=$(jq \
                --arg id "${agent_id}" \
                --arg val "${value}" \
                '(.agents[] | select(.id == $id) | .version) = $val |
                 (.agents[] | select(.id == $id) | .last_updated) = (now | tostring)' \
                "${AGENTS_REGISTRY}")

            log_version_change "${agent_id}" "${old_version}" "${value}" "version_update"
            ;;

        status)
            updated_registry=$(jq \
                --arg id "${agent_id}" \
                --arg val "${value}" \
                '(.agents[] | select(.id == $id) | .status) = $val |
                 (.agents[] | select(.id == $id) | .last_updated) = (now | tostring)' \
                "${AGENTS_REGISTRY}")
            ;;

        trust_level)
            updated_registry=$(jq \
                --arg id "${agent_id}" \
                --arg val "${value}" \
                '(.agents[] | select(.id == $id) | .trust_level) = $val |
                 (.agents[] | select(.id == $id) | .last_updated) = (now | tostring)' \
                "${AGENTS_REGISTRY}")
            ;;

        *)
            echo "Unknown field: ${field}"
            return 1
            ;;
    esac

    echo "${updated_registry}" > "${AGENTS_REGISTRY}"

    echo "✓ Agent updated successfully"
}

# === Capability Discovery ===

query_by_capability() {
    local capability="$1"

    echo "🔍 Querying Agents by Capability: ${capability}"
    echo ""

    if [[ ! -f "${AGENTS_REGISTRY}" ]]; then
        echo "No agents registered"
        return 0
    fi

    # Find agents with capability
    local matching_agents
    matching_agents=$(jq -c --arg cap "${capability}" \
        '.agents[] | select(.capabilities[] == $cap and .status == "active")' \
        "${AGENTS_REGISTRY}")

    local count=0

    while IFS= read -r agent; do
        if [[ -n "${agent}" ]]; then
            count=$((count + 1))

            local agent_id
            agent_id=$(echo "${agent}" | jq -r '.id')

            local agent_name
            agent_name=$(echo "${agent}" | jq -r '.name')

            local version
            version=$(echo "${agent}" | jq -r '.version')

            local trust
            trust=$(echo "${agent}" | jq -r '.trust_level')

            echo "  ${count}. ${agent_name} (${agent_id})"
            echo "     Version: ${version}, Trust: ${trust}"
        fi
    done <<< "${matching_agents}"

    echo ""
    echo "Found ${count} agent(s) with capability: ${capability}"

    # Log discovery
    log_discovery "${capability}" "${count}" "capability_query"
}

list_all_capabilities() {
    echo "📋 All Available Capabilities"
    echo ""

    if [[ ! -f "${CAPABILITIES_INDEX}" ]]; then
        echo "No capabilities indexed"
        return 0
    fi

    local capabilities
    capabilities=$(jq -r '.capabilities | keys[]' "${CAPABILITIES_INDEX}" 2>/dev/null || echo "")

    if [[ -z "${capabilities}" ]]; then
        echo "No capabilities found"
        return 0
    fi

    while IFS= read -r capability; do
        if [[ -n "${capability}" ]]; then
            local agent_count
            agent_count=$(jq -r --arg cap "${capability}" \
                '.capabilities[$cap] | length' \
                "${CAPABILITIES_INDEX}")

            echo "  • ${capability} (${agent_count} agent(s))"
        fi
    done <<< "${capabilities}"
}

index_agent_capabilities() {
    local agent_id="$1"
    local capabilities="$2"

    # Get current index
    local current_index
    current_index=$(cat "${CAPABILITIES_INDEX}")

    # Add agent to each capability
    local caps
    caps=$(echo "${capabilities}" | jq -r '.[]')

    while IFS= read -r cap; do
        if [[ -n "${cap}" ]]; then
            current_index=$(echo "${current_index}" | jq \
                --arg cap "${cap}" \
                --arg agent "${agent_id}" \
                '
                if .capabilities[$cap] then
                    .capabilities[$cap] += [$agent]
                else
                    .capabilities[$cap] = [$agent]
                end
                ')
        fi
    done <<< "${caps}"

    # Update timestamp
    current_index=$(echo "${current_index}" | jq \
        '.last_indexed = (now | tostring)')

    echo "${current_index}" > "${CAPABILITIES_INDEX}"
}

# === Trust Verification ===

determine_trust_level() {
    local publisher="$1"

    # Check if publisher is in trusted list
    local is_trusted
    is_trusted=$(jq -r --arg pub "${publisher}" \
        '.trusted_publishers | contains([$pub])' \
        "${TRUST_VERIFICATION}")

    if [[ "${is_trusted}" == "true" ]]; then
        echo "${TRUST_VERIFIED}"
    else
        echo "${TRUST_UNVERIFIED}"
    fi
}

verify_agent() {
    local agent_id="$1"
    local verification_method="${2:-manual}"

    echo "✅ Verifying Agent: ${agent_id}"
    echo "  Method: ${verification_method}"
    echo ""

    # Get agent
    local agent
    agent=$(jq -c --arg id "${agent_id}" \
        '.agents[] | select(.id == $id)' \
        "${AGENTS_REGISTRY}" 2>/dev/null || echo "")

    if [[ -z "${agent}" ]]; then
        echo "Agent not found: ${agent_id}"
        return 1
    fi

    # Create verification record
    local verification
    verification=$(jq -n \
        --arg agent "${agent_id}" \
        --arg method "${verification_method}" \
        '{
            agent_id: $agent,
            verification_method: $method,
            verified_at: (now | tostring),
            status: "verified"
        }')

    # Add to verifications
    local updated_trust
    updated_trust=$(jq --argjson verification "${verification}" \
        '.verifications += [$verification]' \
        "${TRUST_VERIFICATION}")

    echo "${updated_trust}" > "${TRUST_VERIFICATION}"

    # Update agent trust level
    update_agent "${agent_id}" trust_level "${TRUST_VERIFIED}"

    echo "✓ Agent verified successfully"
}

# === Version Management ===

log_version_change() {
    local agent_id="$1"
    local old_version="$2"
    local new_version="$3"
    local change_type="$4"

    local version_entry
    version_entry=$(jq -n \
        --arg agent "${agent_id}" \
        --arg old "${old_version}" \
        --arg new "${new_version}" \
        --arg type "${change_type}" \
        '{
            agent_id: $agent,
            old_version: (if $old == "" then null else $old end),
            new_version: $new,
            change_type: $type,
            timestamp: (now | tostring)
        }')

    echo "${version_entry}" >> "${VERSION_HISTORY}"
}

get_version_history() {
    local agent_id="$1"
    local limit="${2:-10}"

    echo "📜 Version History: ${agent_id}"
    echo ""

    if [[ ! -f "${VERSION_HISTORY}" ]]; then
        echo "No version history"
        return 0
    fi

    grep "\"agent_id\":\"${agent_id}\"" "${VERSION_HISTORY}" 2>/dev/null | \
        tail -"${limit}" | \
        jq -r '"  " + .old_version + " → " + .new_version + " (" + .change_type + ")"'
}

# === Discovery Logging ===

log_discovery() {
    local query="$1"
    local results_count="$2"
    local query_type="$3"

    local discovery_entry
    discovery_entry=$(jq -n \
        --arg query "${query}" \
        --arg count "${results_count}" \
        --arg type "${query_type}" \
        '{
            query: $query,
            results_count: ($count | tonumber),
            query_type: $type,
            timestamp: (now | tostring)
        }')

    echo "${discovery_entry}" >> "${DISCOVERY_LOG}"
}

# === Registry Statistics ===

registry_stats() {
    echo "📊 Agent Registry Statistics"
    echo ""

    local total_agents=0
    local active_agents=0
    local verified_agents=0
    local total_capabilities=0

    if [[ -f "${AGENTS_REGISTRY}" ]]; then
        total_agents=$(jq '.agents | length' "${AGENTS_REGISTRY}")
        active_agents=$(jq '.agents | map(select(.status == "active")) | length' "${AGENTS_REGISTRY}")
        verified_agents=$(jq '.agents | map(select(.trust_level == "verified")) | length' "${AGENTS_REGISTRY}")
    fi

    if [[ -f "${CAPABILITIES_INDEX}" ]]; then
        total_capabilities=$(jq '.capabilities | keys | length' "${CAPABILITIES_INDEX}")
    fi

    echo "┌─ Overview ──────────────────────────────┐"
    echo "│ Total Agents: ${total_agents}"
    echo "│ Active Agents: ${active_agents}"
    echo "│ Verified Agents: ${verified_agents}"
    echo "│ Total Capabilities: ${total_capabilities}"
    echo "└─────────────────────────────────────────┘"
    echo ""

    # Show top capabilities
    if [[ ${total_capabilities} -gt 0 ]]; then
        echo "┌─ Top Capabilities ──────────────────────┐"
        jq -r '.capabilities | to_entries | sort_by(.value | length) | reverse | limit(5;.[]) |
            "│ " + .key + ": " + (.value | length | tostring) + " agent(s)"' \
            "${CAPABILITIES_INDEX}"
        echo "└─────────────────────────────────────────┘"
    fi
}

# === Main ===

main() {
    local command="${1:-stats}"
    shift || true

    # Initialize on first run
    initialize_registry

    case "${command}" in
        register)
            if [[ $# -lt 4 ]]; then
                echo "Usage: agent-registry-manager.sh register <agent_id> <name> <version> <capabilities> [publisher]"
                exit 1
            fi

            register_agent "$@"
            ;;

        update)
            if [[ $# -lt 3 ]]; then
                echo "Usage: agent-registry-manager.sh update <agent_id> <field> <value>"
                exit 1
            fi

            update_agent "$@"
            ;;

        query-capability)
            if [[ $# -eq 0 ]]; then
                echo "Usage: agent-registry-manager.sh query-capability <capability_name>"
                exit 1
            fi

            query_by_capability "$1"
            ;;

        list-capabilities)
            list_all_capabilities
            ;;

        verify)
            if [[ $# -eq 0 ]]; then
                echo "Usage: agent-registry-manager.sh verify <agent_id> [verification_method]"
                exit 1
            fi

            verify_agent "$@"
            ;;

        version-history)
            if [[ $# -eq 0 ]]; then
                echo "Usage: agent-registry-manager.sh version-history <agent_id> [limit]"
                exit 1
            fi

            get_version_history "$@"
            ;;

        stats)
            registry_stats
            ;;

        *)
            cat <<'EOF'
Agent Registry Manager - Centralized agent discovery and capability management

USAGE:
  agent-registry-manager.sh register <agent_id> <name> <version> <capabilities> [publisher]
  agent-registry-manager.sh update <agent_id> <field> <value>
  agent-registry-manager.sh query-capability <capability_name>
  agent-registry-manager.sh list-capabilities
  agent-registry-manager.sh verify <agent_id> [verification_method]
  agent-registry-manager.sh version-history <agent_id> [limit]
  agent-registry-manager.sh stats

TRUST LEVELS:
  verified        Verified by registry authority
  trusted         From known trusted publisher
  unverified      Not yet verified
  suspicious      Flagged for review

AGENT STATUS:
  active          Agent available for use
  inactive        Agent temporarily unavailable
  deprecated      Agent superseded by newer version
  beta            Agent in testing phase

EXAMPLES:
  # Register new agent
  agent-registry-manager.sh register \
    "automation-hub:v1" \
    "Automation Hub Coordinator" \
    "1.6.0" \
    "routing,orchestration,memory" \
    "automation-hub"

  # Query agents by capability
  agent-registry-manager.sh query-capability "routing"

  # List all capabilities
  agent-registry-manager.sh list-capabilities

  # Update agent version
  agent-registry-manager.sh update \
    "automation-hub:v1" \
    version \
    "1.7.0"

  # Verify agent
  agent-registry-manager.sh verify "automation-hub:v1" manual

  # View version history
  agent-registry-manager.sh version-history "automation-hub:v1" 10

  # View statistics
  agent-registry-manager.sh stats

RESEARCH:
  - Google Cloud AI Agent Marketplace (2026)
  - GoDaddy ANS Registry for agent identity
  - TrueFoundry AI Agent Registry
  - Automated capability discovery

EOF
            ;;
    esac
}

# Execute
main "$@"

exit 0
