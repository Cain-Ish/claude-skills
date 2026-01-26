#!/usr/bin/env bash
# Dynamic ecosystem discovery - finds all available plugins, agents, MCP servers, and tools
# Inspired by MCP Gateway dynamic tool discovery patterns

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Output Format ===
# JSON structure containing all discovered capabilities

OUTPUT_FILE="${1:-${HOME}/.claude/automation-hub/ecosystem-registry.json}"

debug "Discovering ecosystem capabilities..."

# === 1. Discover Claude Code Plugins ===

discover_plugins() {
    local plugins_dir="${HOME}/.claude/plugins"
    local project_plugins="$(pwd)/plugins"

    local plugins=()

    # Scan global plugins
    if [[ -d "${plugins_dir}" ]]; then
        for plugin_manifest in "${plugins_dir}"/*/.claude-plugin/plugin.json; do
            if [[ -f "${plugin_manifest}" ]]; then
                local plugin_info
                plugin_info=$(jq -c '{
                    name: .name,
                    version: .version,
                    description: .description,
                    agents: (.agents // {} | keys),
                    commands: (.commands // {} | keys),
                    hooks: (.hooks // {} | keys),
                    skills: (.skills // {} | keys),
                    type: "plugin",
                    scope: "global",
                    path: "'"$(dirname "$(dirname "${plugin_manifest}")")"'"
                }' "${plugin_manifest}")

                plugins+=("${plugin_info}")
            fi
        done
    fi

    # Scan project plugins
    if [[ -d "${project_plugins}" ]]; then
        for plugin_manifest in "${project_plugins}"/*/.claude-plugin/plugin.json; do
            if [[ -f "${plugin_manifest}" ]]; then
                local plugin_info
                plugin_info=$(jq -c '{
                    name: .name,
                    version: .version,
                    description: .description,
                    agents: (.agents // {} | keys),
                    commands: (.commands // {} | keys),
                    hooks: (.hooks // {} | keys),
                    skills: (.skills // {} | keys),
                    type: "plugin",
                    scope: "project",
                    path: "'"$(dirname "$(dirname "${plugin_manifest}")")"'"
                }' "${plugin_manifest}")

                plugins+=("${plugin_info}")
            fi
        done
    fi

    # Output as JSON array
    printf '%s\n' "${plugins[@]}" | jq -s '.'
}

# === 2. Discover MCP Servers ===

discover_mcp_servers() {
    local mcp_config="${HOME}/.claude/mcp.json"
    local mcp_servers=()

    if [[ -f "${mcp_config}" ]]; then
        # Extract MCP server configurations
        mcp_servers=$(jq -c '.mcpServers // {} | to_entries[] | {
            name: .key,
            description: (.value.description // ""),
            command: .value.command,
            args: (.value.args // []),
            env: (.value.env // {}),
            type: "mcp_server",
            scope: "global"
        }' "${mcp_config}")
    fi

    # Check project-level .mcp.json
    if [[ -f "$(pwd)/.mcp.json" ]]; then
        local project_mcp
        project_mcp=$(jq -c '.mcpServers // {} | to_entries[] | {
            name: .key,
            description: (.value.description // ""),
            command: .value.command,
            args: (.value.args // []),
            env: (.value.env // {}),
            type: "mcp_server",
            scope: "project"
        }' "$(pwd)/.mcp.json")

        mcp_servers=$(echo -e "${mcp_servers}\n${project_mcp}")
    fi

    if [[ -n "${mcp_servers}" ]]; then
        echo "${mcp_servers}" | jq -s '.'
    else
        echo '[]'
    fi
}

# === 3. Discover Available Agents ===

discover_agents() {
    local agents=()

    # Extract agents from discovered plugins
    local plugin_agents
    plugin_agents=$(discover_plugins | jq -c '.[] | select(.agents | length > 0) | .agents[] as $agent | {
        name: ($agent | if type == "string" then . else .name end),
        plugin: .name,
        description: (if ($agent | type) == "object" then $agent.description else "" end),
        type: "agent",
        capabilities: (if ($agent | type) == "object" then ($agent.capabilities // []) else [] end),
        tags: (if ($agent | type) == "object" then ($agent.tags // []) else [] end)
    }')

    if [[ -n "${plugin_agents}" ]]; then
        echo "${plugin_agents}" | jq -s '.'
    else
        echo '[]'
    fi
}

# === 4. Discover Available Skills ===

discover_skills() {
    local skills=()

    # Extract skills from plugins
    local plugin_skills
    plugin_skills=$(discover_plugins | jq -c '.[] | select(.skills | length > 0) | .skills[] as $skill | {
        name: $skill,
        plugin: .name,
        type: "skill",
        invocation: ("/" + $skill)
    }')

    if [[ -n "${plugin_skills}" ]]; then
        echo "${plugin_skills}" | jq -s '.'
    else
        echo '[]'
    fi
}

# === 5. Create Semantic Index ===

create_semantic_index() {
    local capabilities="$1"

    # Extract keywords from descriptions and tags for semantic matching
    # This is a simple keyword-based approach; could be enhanced with embeddings

    echo "${capabilities}" | jq -c '.[] | {
        id: (.name + ":" + .type),
        name: .name,
        type: .type,
        keywords: (
            [.description, .name, (.tags // []) | join(" "), (.capabilities // []) | join(" ")]
            | join(" ")
            | ascii_downcase
            | split(" ")
            | unique
            | map(select(length > 3))
        ),
        metadata: .
    }' | jq -s '.'
}

# === 6. Build Complete Registry ===

build_registry() {
    local plugins
    plugins=$(discover_plugins)

    local mcp_servers
    mcp_servers=$(discover_mcp_servers)

    local agents
    agents=$(discover_agents)

    local skills
    skills=$(discover_skills)

    # Combine all capabilities
    local all_capabilities
    all_capabilities=$(jq -n \
        --argjson plugins "${plugins}" \
        --argjson mcp "${mcp_servers}" \
        --argjson agents "${agents}" \
        --argjson skills "${skills}" \
        '{
            plugins: $plugins,
            mcp_servers: $mcp,
            agents: $agents,
            skills: $skills,
            metadata: {
                discovered_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
                total_plugins: ($plugins | length),
                total_mcp_servers: ($mcp | length),
                total_agents: ($agents | length),
                total_skills: ($skills | length)
            }
        }')

    # Create semantic index
    local all_items
    all_items=$(echo "${all_capabilities}" | jq -c '[.plugins[], .mcp_servers[], .agents[], .skills[]]')

    local semantic_index
    semantic_index=$(create_semantic_index "${all_items}")

    # Add semantic index to registry
    echo "${all_capabilities}" | jq --argjson index "${semantic_index}" '. + {semantic_index: $index}'
}

# === 7. Query Functions for Hook Usage ===

query_agents_for_task() {
    local task_description="$1"
    local registry="${OUTPUT_FILE}"

    if [[ ! -f "${registry}" ]]; then
        echo "[]"
        return
    fi

    # Simple keyword matching (could be enhanced with semantic similarity)
    local query_keywords
    query_keywords=$(echo "${task_description}" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' ' ' | xargs -n1 | sort -u)

    # Find agents with matching keywords
    local matches
    matches=$(jq -c --arg keywords "${query_keywords}" '
        .semantic_index[]
        | select(.type == "agent")
        | select(
            (.keywords | map(select(. as $k | $keywords | contains($k))) | length) > 0
        )
        | {
            name: .name,
            match_score: ((.keywords | map(select(. as $k | $keywords | contains($k))) | length) / (.keywords | length)),
            metadata: .metadata
        }
    ' "${registry}" | jq -s 'sort_by(-.match_score)')

    echo "${matches}"
}

# === Main Execution ===

debug "Building ecosystem registry..."

registry=$(build_registry)

# Write to output file
ensure_config_dirs
echo "${registry}" > "${OUTPUT_FILE}"

debug "Registry created: ${OUTPUT_FILE}"

# Print summary
summary=$(echo "${registry}" | jq -r '
    "Discovered Ecosystem:\n" +
    "  Plugins: \(.metadata.total_plugins)\n" +
    "  MCP Servers: \(.metadata.total_mcp_servers)\n" +
    "  Agents: \(.metadata.total_agents)\n" +
    "  Skills: \(.metadata.total_skills)\n" +
    "  Semantic Index: \(.semantic_index | length) entries"
')

echo "${summary}"

exit 0
