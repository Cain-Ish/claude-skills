#!/bin/bash
# ============================================================================
# Self-Debugger Plugin - Scan All Plugins
# ============================================================================
# Scans all plugins in the repository for issues using rule-based validation.
# Stores violations in ~/.claude/self-debugger/findings/issues.jsonl
#
# Usage:
#   ./scan-plugins.sh [plugins-dir]
#
# Environment Variables:
#   PLUGINS_DIR - Directory containing plugins (default: detect from repo root)
#   VERBOSE - Enable debug logging (default: false)
# ============================================================================

set -euo pipefail

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/rule-engine.sh"

# ============================================================================
# Main Logic
# ============================================================================

main() {
    init_debugger

    log_info "Starting plugin scan (session: $CURRENT_SESSION_ID)"

    # Determine plugins directory
    local plugins_dir="${1:-}"
    if [[ -z "$plugins_dir" ]]; then
        # Auto-detect: look for plugins/ directory in repo root
        local repo_root
        repo_root=$(git -C "$PLUGIN_ROOT" rev-parse --show-toplevel 2>/dev/null || echo "")
        if [[ -n "$repo_root" ]] && [[ -d "$repo_root/plugins" ]]; then
            plugins_dir="$repo_root/plugins"
        else
            log_error "Could not find plugins directory. Please specify path."
            exit 1
        fi
    fi

    if [[ ! -d "$plugins_dir" ]]; then
        log_error "Plugins directory not found: $plugins_dir"
        exit 1
    fi

    log_debug "Scanning plugins in: $plugins_dir"

    # Load all rules
    log_info "Loading validation rules..."
    local all_rules
    all_rules=$(load_all_rules)

    if ! has_jq; then
        log_error "jq is required for scanning. Please install jq."
        exit 1
    fi

    local rule_count
    rule_count=$(echo "$all_rules" | jq 'length' 2>/dev/null || echo "0")
    log_info "Loaded $rule_count rules"

    if [[ "$rule_count" -eq 0 ]]; then
        log_warn "No rules loaded. Nothing to validate."
        exit 0
    fi

    # Scan each plugin
    local total_issues=0
    local total_plugins=0

    for plugin_dir in "$plugins_dir"/*; do
        if [[ ! -d "$plugin_dir" ]]; then
            continue
        fi

        local plugin_name
        plugin_name=$(basename "$plugin_dir")

        # Skip self-debugger (avoid recursion)
        if [[ "$plugin_name" == "self-debugger" ]]; then
            log_debug "Skipping self-debugger plugin"
            continue
        fi

        total_plugins=$((total_plugins + 1))
        log_info "Scanning plugin: $plugin_name"

        # Scan plugin components
        local plugin_issues
        plugin_issues=$(scan_plugin "$plugin_dir" "$plugin_name" "$all_rules")

        total_issues=$((total_issues + plugin_issues))
    done

    log_success "Scan complete: $total_issues issues found in $total_plugins plugins"

    # Record scan metrics
    local scan_record
    scan_record=$(cat <<EOF
{
  "timestamp": "$(get_timestamp)",
  "session_id": "$CURRENT_SESSION_ID",
  "event": "scan_complete",
  "plugins_scanned": $total_plugins,
  "issues_found": $total_issues,
  "rule_count": $rule_count
}
EOF
)
    append_jsonl "$scan_record" "$METRICS_FILE"
}

# Scan a single plugin
# Usage: scan_plugin "/path/to/plugin" "plugin-name" "$all_rules_json"
# Returns: Number of issues found
scan_plugin() {
    local plugin_dir="$1"
    local plugin_name="$2"
    local all_rules="$3"
    local issues_count=0

    # Scan plugin.json
    if [[ -f "$plugin_dir/.claude-plugin/plugin.json" ]]; then
        local component=".claude-plugin/plugin.json"
        scan_component "$plugin_dir" "$plugin_name" "$component" "$all_rules"
        issues_count=$((issues_count + $?))
    fi

    # Scan hooks
    if [[ -d "$plugin_dir/hooks" ]]; then
        for hook_file in "$plugin_dir/hooks"/*.md; do
            if [[ -f "$hook_file" ]]; then
                local component
                component="hooks/$(basename "$hook_file")"
                scan_component "$plugin_dir" "$plugin_name" "$component" "$all_rules"
                issues_count=$((issues_count + $?))
            fi
        done
    fi

    # Scan agents
    if [[ -d "$plugin_dir/agents" ]]; then
        for agent_file in "$plugin_dir/agents"/*.md; do
            if [[ -f "$agent_file" ]]; then
                local component
                component="agents/$(basename "$agent_file")"
                scan_component "$plugin_dir" "$plugin_name" "$component" "$all_rules"
                issues_count=$((issues_count + $?))
            fi
        done
    fi

    # Scan skills
    if [[ -d "$plugin_dir/skills" ]]; then
        while IFS= read -r -d '' skill_file; do
            local component
            component="${skill_file#$plugin_dir/}"
            scan_component "$plugin_dir" "$plugin_name" "$component" "$all_rules"
            issues_count=$((issues_count + $?))
        done < <(find "$plugin_dir/skills" -name "*.md" -print0 2>/dev/null)
    fi

    log_debug "  → Found $issues_count issues in $plugin_name"
    return $issues_count
}

# Scan a single component (file)
# Usage: scan_component "/path/to/plugin" "plugin-name" "hooks/SessionStart.md" "$all_rules_json"
# Returns: Number of violations found
scan_component() {
    local plugin_dir="$1"
    local plugin_name="$2"
    local component="$3"
    local all_rules="$4"
    local violations_count=0

    local file_path="$plugin_dir/$component"

    if [[ ! -f "$file_path" ]]; then
        return 0
    fi

    # Find applicable rules
    local applicable_rules
    applicable_rules=$(find_applicable_rules "$all_rules" "$component")

    local applicable_count
    applicable_count=$(echo "$applicable_rules" | jq 'length' 2>/dev/null || echo "0")

    if [[ "$applicable_count" -eq 0 ]]; then
        return 0
    fi

    log_debug "  Checking $component (${applicable_count} applicable rules)"

    # Validate against each applicable rule
    for ((i=0; i<applicable_count; i++)); do
        local rule
        rule=$(echo "$applicable_rules" | jq -c ".[$i]" 2>/dev/null)

        # Run validation
        local violations
        violations=$(validate_file_against_rule "$rule" "$file_path" "$plugin_name")

        local violation_count
        violation_count=$(echo "$violations" | jq 'length' 2>/dev/null || echo "0")

        # Record each violation
        for ((j=0; j<violation_count; j++)); do
            local violation
            violation=$(echo "$violations" | jq -c ".[$j]" 2>/dev/null)

            record_issue "$plugin_name" "$component" "$violation"
            violations_count=$((violations_count + 1))
        done
    done

    return $violations_count
}

# ============================================================================
# Entry Point
# ============================================================================

main "$@"
