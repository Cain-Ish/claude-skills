#!/usr/bin/env bash
# Security Sandbox - Capability-based security and permission management
# Based on 2026 research: OWASP AI Agent Security Top 10, micro-VM isolation, scoped permissions
# Implements defense-in-depth with execution sandboxing + permission scoping

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Configuration ===

SECURITY_DIR="${HOME}/.claude/automation-hub/security"
PERMISSIONS_DB="${SECURITY_DIR}/permissions.json"
CAPABILITY_TOKENS="${SECURITY_DIR}/capability-tokens.json"
SECURITY_AUDIT_LOG="${SECURITY_DIR}/audit.jsonl"
COMMAND_ALLOWLIST="${SECURITY_DIR}/command-allowlist.json"

# Security levels
SECURITY_LEVEL_UNRESTRICTED="unrestricted"
SECURITY_LEVEL_SCOPED="scoped"
SECURITY_LEVEL_SANDBOXED="sandboxed"
SECURITY_LEVEL_ISOLATED="isolated"

# Permission types
PERM_FILESYSTEM="filesystem"
PERM_NETWORK="network"
PERM_PROCESS="process"
PERM_SHELL="shell"
PERM_SYSTEM="system"

# === Initialize ===

mkdir -p "${SECURITY_DIR}"

initialize_security_config() {
    if [[ ! -f "${PERMISSIONS_DB}" ]]; then
        cat > "${PERMISSIONS_DB}" <<'EOF'
{
  "default_level": "scoped",
  "permissions": {
    "automation-hub": {
      "filesystem": {
        "allowed_paths": [
          "${HOME}/.claude/automation-hub",
          "${HOME}/.claude/plugins",
          "/tmp"
        ],
        "denied_paths": [
          "/etc",
          "/bin",
          "/sbin",
          "/usr/bin",
          "/usr/sbin"
        ],
        "read_only": false
      },
      "network": {
        "allowed": false,
        "allowed_hosts": [],
        "denied_hosts": []
      },
      "process": {
        "allowed_commands": [
          "jq",
          "grep",
          "sed",
          "awk",
          "date",
          "bc"
        ],
        "denied_commands": [
          "rm -rf",
          "dd",
          "mkfs"
        ],
        "max_processes": 10
      },
      "shell": {
        "allowed": true,
        "restricted_mode": true
      }
    }
  }
}
EOF
        echo "✓ Initialized security configuration"
    fi

    if [[ ! -f "${COMMAND_ALLOWLIST}" ]]; then
        cat > "${COMMAND_ALLOWLIST}" <<'EOF'
{
  "allowlist": [
    {
      "command": "git",
      "args_pattern": "^(status|diff|log|add|commit|push).*",
      "description": "Git version control operations"
    },
    {
      "command": "jq",
      "args_pattern": ".*",
      "description": "JSON processing"
    },
    {
      "command": "grep",
      "args_pattern": "^(-[a-zA-Z]+ )?.*",
      "description": "Text search"
    },
    {
      "command": "bash",
      "args_pattern": "^scripts/.*\\.sh.*",
      "description": "Automation scripts only"
    }
  ],
  "denylist": [
    {
      "command": "rm",
      "args_pattern": ".*-rf.*",
      "reason": "Recursive force delete prohibited"
    },
    {
      "command": "dd",
      "args_pattern": ".*",
      "reason": "Direct disk access prohibited"
    },
    {
      "command": "chmod",
      "args_pattern": ".*777.*",
      "reason": "Overly permissive chmod prohibited"
    }
  ]
}
EOF
        echo "✓ Initialized command allowlist"
    fi
}

# === Permission Checking ===

check_permission() {
    local permission_type="$1"
    local resource="$2"
    local action="${3:-read}"

    local agent_id="${4:-automation-hub}"

    local allowed="false"

    case "${permission_type}" in
        filesystem)
            allowed=$(check_filesystem_permission "${resource}" "${action}" "${agent_id}")
            ;;

        network)
            allowed=$(check_network_permission "${resource}" "${action}" "${agent_id}")
            ;;

        process)
            allowed=$(check_process_permission "${resource}" "${action}" "${agent_id}")
            ;;

        shell)
            allowed=$(check_shell_permission "${resource}" "${action}" "${agent_id}")
            ;;

        *)
            echo "false"
            return 1
            ;;
    esac

    echo "${allowed}"
}

check_filesystem_permission() {
    local path="$1"
    local action="$2"
    local agent_id="$3"

    # Expand path
    local expanded_path
    expanded_path=$(eval echo "${path}")

    # Check denied paths first
    local denied_paths
    denied_paths=$(jq -r --arg agent "${agent_id}" \
        '.permissions[$agent].filesystem.denied_paths[]' \
        "${PERMISSIONS_DB}" 2>/dev/null || echo "")

    while IFS= read -r denied_path; do
        if [[ -n "${denied_path}" ]]; then
            local expanded_denied
            expanded_denied=$(eval echo "${denied_path}")

            if [[ "${expanded_path}" == ${expanded_denied}* ]]; then
                echo "false"
                return 1
            fi
        fi
    done <<< "${denied_paths}"

    # Check allowed paths
    local allowed_paths
    allowed_paths=$(jq -r --arg agent "${agent_id}" \
        '.permissions[$agent].filesystem.allowed_paths[]' \
        "${PERMISSIONS_DB}" 2>/dev/null || echo "")

    local path_allowed="false"

    while IFS= read -r allowed_path; do
        if [[ -n "${allowed_path}" ]]; then
            local expanded_allowed
            expanded_allowed=$(eval echo "${allowed_path}")

            if [[ "${expanded_path}" == ${expanded_allowed}* ]]; then
                path_allowed="true"
                break
            fi
        fi
    done <<< "${allowed_paths}"

    if [[ "${path_allowed}" == "false" ]]; then
        echo "false"
        return 1
    fi

    # Check if write action is allowed
    if [[ "${action}" == "write" ]] || [[ "${action}" == "delete" ]]; then
        local read_only
        read_only=$(jq -r --arg agent "${agent_id}" \
            '.permissions[$agent].filesystem.read_only' \
            "${PERMISSIONS_DB}" 2>/dev/null || echo "false")

        if [[ "${read_only}" == "true" ]]; then
            echo "false"
            return 1
        fi
    fi

    echo "true"
}

check_network_permission() {
    local host="$1"
    local action="$2"
    local agent_id="$3"

    local network_allowed
    network_allowed=$(jq -r --arg agent "${agent_id}" \
        '.permissions[$agent].network.allowed' \
        "${PERMISSIONS_DB}" 2>/dev/null || echo "false")

    if [[ "${network_allowed}" == "false" ]]; then
        echo "false"
        return 1
    fi

    # Check allowed hosts (if specified)
    local allowed_hosts
    allowed_hosts=$(jq -r --arg agent "${agent_id}" \
        '.permissions[$agent].network.allowed_hosts | length' \
        "${PERMISSIONS_DB}" 2>/dev/null || echo "0")

    if [[ ${allowed_hosts} -gt 0 ]]; then
        local host_allowed
        host_allowed=$(jq -r --arg agent "${agent_id}" --arg host "${host}" \
            '.permissions[$agent].network.allowed_hosts | contains([$host])' \
            "${PERMISSIONS_DB}" 2>/dev/null || echo "false")

        echo "${host_allowed}"
    else
        echo "true"
    fi
}

check_process_permission() {
    local command="$1"
    local action="$2"
    local agent_id="$3"

    # Check if command is in allowed list
    local command_allowed
    command_allowed=$(jq -r --arg agent "${agent_id}" --arg cmd "${command}" \
        '.permissions[$agent].process.allowed_commands | contains([$cmd])' \
        "${PERMISSIONS_DB}" 2>/dev/null || echo "false")

    echo "${command_allowed}"
}

check_shell_permission() {
    local script="$1"
    local action="$2"
    local agent_id="$3"

    local shell_allowed
    shell_allowed=$(jq -r --arg agent "${agent_id}" \
        '.permissions[$agent].shell.allowed' \
        "${PERMISSIONS_DB}" 2>/dev/null || echo "false")

    if [[ "${shell_allowed}" == "false" ]]; then
        echo "false"
        return 1
    fi

    # Check if restricted mode
    local restricted
    restricted=$(jq -r --arg agent "${agent_id}" \
        '.permissions[$agent].shell.restricted_mode' \
        "${PERMISSIONS_DB}" 2>/dev/null || echo "true")

    if [[ "${restricted}" == "true" ]]; then
        # In restricted mode, only allow scripts in automation-hub directory
        if [[ "${script}" != *"automation-hub"* ]]; then
            echo "false"
            return 1
        fi
    fi

    echo "true"
}

# === Command Validation ===

validate_command() {
    local command="$1"
    local args="$2"

    # Check allowlist
    local allowlist_entries
    allowlist_entries=$(jq -c '.allowlist[]' "${COMMAND_ALLOWLIST}" 2>/dev/null || echo "")

    local allowed="false"

    while IFS= read -r entry; do
        if [[ -n "${entry}" ]]; then
            local cmd
            cmd=$(echo "${entry}" | jq -r '.command')

            local pattern
            pattern=$(echo "${entry}" | jq -r '.args_pattern')

            if [[ "${command}" == "${cmd}" ]]; then
                if echo "${args}" | grep -qE "${pattern}"; then
                    allowed="true"
                    break
                fi
            fi
        fi
    done <<< "${allowlist_entries}"

    # Check denylist
    local denylist_entries
    denylist_entries=$(jq -c '.denylist[]' "${COMMAND_ALLOWLIST}" 2>/dev/null || echo "")

    while IFS= read -r entry; do
        if [[ -n "${entry}" ]]; then
            local cmd
            cmd=$(echo "${entry}" | jq -r '.command')

            local pattern
            pattern=$(echo "${entry}" | jq -r '.args_pattern')

            local reason
            reason=$(echo "${entry}" | jq -r '.reason')

            if [[ "${command}" == "${cmd}" ]]; then
                if echo "${args}" | grep -qE "${pattern}"; then
                    echo "false"
                    audit_security_violation "command_denied" "${command} ${args}" "${reason}"
                    return 1
                fi
            fi
        fi
    done <<< "${denylist_entries}"

    echo "${allowed}"
}

# === Capability Tokens (WebAssembly-inspired) ===

issue_capability_token() {
    local capability_type="$1"
    local resource="$2"
    local action="$3"
    local expiry_seconds="${4:-3600}"

    local timestamp
    timestamp=$(date -u +%s)

    local expiry
    expiry=$((timestamp + expiry_seconds))

    local token_id
    token_id=$(date +%s%N)

    local token_entry
    token_entry=$(jq -n \
        --arg id "${token_id}" \
        --arg timestamp "${timestamp}" \
        --arg expiry "${expiry}" \
        --arg type "${capability_type}" \
        --arg resource "${resource}" \
        --arg action "${action}" \
        '{
            id: $id,
            timestamp: ($timestamp | tonumber),
            expiry: ($expiry | tonumber),
            type: $type,
            resource: $resource,
            action: $action,
            used: false
        }')

    if [[ ! -f "${CAPABILITY_TOKENS}" ]]; then
        echo '{"tokens":[]}' > "${CAPABILITY_TOKENS}"
    fi

    local updated_tokens
    updated_tokens=$(jq --argjson token "${token_entry}" \
        '.tokens += [$token]' \
        "${CAPABILITY_TOKENS}")

    echo "${updated_tokens}" > "${CAPABILITY_TOKENS}"

    echo "${token_id}"
}

verify_capability_token() {
    local token_id="$1"
    local expected_resource="$2"
    local expected_action="$3"

    if [[ ! -f "${CAPABILITY_TOKENS}" ]]; then
        echo "false"
        return 1
    fi

    local current_time
    current_time=$(date +%s)

    local token
    token=$(jq -r --arg id "${token_id}" --arg now "${current_time}" \
        '.tokens[] |
        select(.id == $id and .expiry >= ($now | tonumber) and .used == false)' \
        "${CAPABILITY_TOKENS}" 2>/dev/null)

    if [[ -z "${token}" ]]; then
        echo "false"
        return 1
    fi

    local token_resource
    token_resource=$(echo "${token}" | jq -r '.resource')

    local token_action
    token_action=$(echo "${token}" | jq -r '.action')

    if [[ "${token_resource}" == "${expected_resource}" ]] && [[ "${token_action}" == "${expected_action}" ]]; then
        # Mark token as used (one-time use)
        local updated_tokens
        updated_tokens=$(jq --arg id "${token_id}" \
            '(.tokens[] | select(.id == $id) | .used) = true' \
            "${CAPABILITY_TOKENS}")

        echo "${updated_tokens}" > "${CAPABILITY_TOKENS}"

        echo "true"
    else
        echo "false"
        return 1
    fi
}

# === Security Audit Logging ===

audit_security_event() {
    local event_type="$1"
    local resource="$2"
    local action="$3"
    local outcome="$4"
    local details="${5:-}"

    local timestamp
    timestamp=$(date -u +%s)

    local audit_entry
    audit_entry=$(jq -n \
        --arg timestamp "${timestamp}" \
        --arg type "${event_type}" \
        --arg resource "${resource}" \
        --arg action "${action}" \
        --arg outcome "${outcome}" \
        --arg details "${details}" \
        '{
            timestamp: ($timestamp | tonumber),
            event_type: $type,
            resource: $resource,
            action: $action,
            outcome: $outcome,
            details: $details,
            recorded_at: (now | tostring)
        }')

    echo "${audit_entry}" >> "${SECURITY_AUDIT_LOG}"

    debug "Security audit: ${event_type} on ${resource} (${outcome})"
}

audit_security_violation() {
    local violation_type="$1"
    local resource="$2"
    local reason="$3"

    audit_security_event \
        "security_violation" \
        "${resource}" \
        "${violation_type}" \
        "denied" \
        "${reason}"

    # Emit security event if streaming enabled
    if [[ -f "${SCRIPT_DIR}/streaming-events.sh" ]]; then
        bash "${SCRIPT_DIR}/streaming-events.sh" error \
            "security_violation" \
            "${violation_type}: ${resource} - ${reason}" \
            "false" 2>/dev/null || true
    fi
}

# === Security Statistics ===

security_stats() {
    echo "🔒 Security Sandbox Statistics"
    echo ""

    if [[ ! -f "${SECURITY_AUDIT_LOG}" ]]; then
        echo "No security events logged yet"
        return 0
    fi

    local total_events
    total_events=$(wc -l < "${SECURITY_AUDIT_LOG}" | tr -d ' ')

    local violations
    violations=$(jq -s 'map(select(.event_type == "security_violation")) | length' \
        "${SECURITY_AUDIT_LOG}")

    local allowed
    allowed=$(jq -s 'map(select(.outcome == "allowed")) | length' \
        "${SECURITY_AUDIT_LOG}")

    local denied
    denied=$(jq -s 'map(select(.outcome == "denied")) | length' \
        "${SECURITY_AUDIT_LOG}")

    echo "┌─ Overall ───────────────────────────────┐"
    echo "│ Total Security Events: ${total_events}"
    echo "│ Allowed: ${allowed}"
    echo "│ Denied: ${denied}"
    echo "│ Violations: ${violations}"
    echo "└─────────────────────────────────────────┘"
    echo ""

    # Recent violations
    if [[ ${violations} -gt 0 ]]; then
        echo "┌─ Recent Violations ─────────────────────┐"
        jq -s 'map(select(.event_type == "security_violation")) |
            .[-5:] |
            .[] |
            "│ " + .action + ": " + .resource' \
            "${SECURITY_AUDIT_LOG}"
        echo "└─────────────────────────────────────────┘"
    fi
}

# === Main ===

main() {
    local command="${1:-stats}"
    shift || true

    # Initialize on first run
    initialize_security_config

    case "${command}" in
        check)
            if [[ $# -lt 2 ]]; then
                echo "Usage: security-sandbox.sh check <type> <resource> [action] [agent_id]"
                exit 1
            fi

            check_permission "$@"
            ;;

        validate)
            if [[ $# -lt 2 ]]; then
                echo "Usage: security-sandbox.sh validate <command> <args>"
                exit 1
            fi

            validate_command "$@"
            ;;

        issue-token)
            if [[ $# -lt 3 ]]; then
                echo "Usage: security-sandbox.sh issue-token <type> <resource> <action> [expiry_seconds]"
                exit 1
            fi

            issue_capability_token "$@"
            ;;

        verify-token)
            if [[ $# -lt 3 ]]; then
                echo "Usage: security-sandbox.sh verify-token <token_id> <resource> <action>"
                exit 1
            fi

            verify_capability_token "$@"
            ;;

        audit)
            if [[ $# -lt 4 ]]; then
                echo "Usage: security-sandbox.sh audit <type> <resource> <action> <outcome> [details]"
                exit 1
            fi

            audit_security_event "$@"
            ;;

        stats)
            security_stats
            ;;

        *)
            cat <<'EOF'
Security Sandbox - Capability-based security and permission management

USAGE:
  security-sandbox.sh check <type> <resource> [action] [agent_id]
  security-sandbox.sh validate <command> <args>
  security-sandbox.sh issue-token <type> <resource> <action> [expiry_seconds]
  security-sandbox.sh verify-token <token_id> <resource> <action>
  security-sandbox.sh audit <type> <resource> <action> <outcome> [details]
  security-sandbox.sh stats

PERMISSION TYPES:
  filesystem      File and directory access
  network         Network connectivity
  process         Process execution
  shell           Shell script execution
  system          System-level operations

SECURITY LEVELS:
  unrestricted    No restrictions (development only)
  scoped          Permission-based access control
  sandboxed       Execution isolation + permissions
  isolated        Micro-VM isolation (future)

EXAMPLES:
  # Check filesystem permission
  security-sandbox.sh check filesystem "/tmp/data.json" write

  # Validate command before execution
  security-sandbox.sh validate "git" "status"

  # Issue capability token (one-time use)
  security-sandbox.sh issue-token filesystem "/tmp/output.txt" write 3600

  # Verify capability token
  security-sandbox.sh verify-token "1737840123456789000" "/tmp/output.txt" write

  # Audit security event
  security-sandbox.sh audit "filesystem_access" "/tmp/data.json" "write" "allowed"

RESEARCH:
  - OWASP AI Agent Security Top 10 (2026)
  - Micro-VM isolation with Kata Containers/gVisor
  - Capability-based security (WebAssembly model)
  - Scoped permissions (least privilege principle)

EOF
            ;;
    esac
}

# Execute
main "$@"

exit 0
