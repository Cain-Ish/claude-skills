#!/bin/bash
# ============================================================================
# Self-Debugger Plugin - Web Pattern Discovery
# ============================================================================
# Discovers Claude Code plugin best practices from the web and creates
# external validation rules based on findings.
#
# Usage:
#   ./web-discover.sh
#
# Searches for:
#   - Claude Code plugin best practices (current year)
#   - Official documentation updates
#   - Community patterns and examples
#
# Outputs:
#   - New rules in rules/external/
#   - Confidence scores based on source authority
#   - References to original sources
# ============================================================================

set -euo pipefail

# Source libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/web-search.sh"

# ============================================================================
# Pattern Discovery
# ============================================================================

discover_hook_patterns() {
    log_info "Discovering hook best practices..."

    # Search for hook patterns
    local results
    results=$(search_pattern_examples "hook frontmatter yaml")

    if [[ -z "$results" ]] || [[ "$results" == "[]" ]]; then
        log_warn "No hook patterns discovered"
        return 0
    fi

    # AIDEV-NOTE: Pattern extraction and rule generation pending WebSearch integration
    log_info "Would analyze hook patterns from search results"
}

discover_plugin_schema_patterns() {
    log_info "Discovering plugin.json schema patterns..."

    # Search for plugin manifest patterns
    local results
    results=$(search_pattern_examples "plugin.json manifest schema")

    if [[ -z "$results" ]] || [[ "$results" == "[]" ]]; then
        log_warn "No plugin schema patterns discovered"
        return 0
    fi

    log_info "Would analyze plugin schema patterns from search results"
}

discover_agent_patterns() {
    log_info "Discovering agent best practices..."

    # Search for agent patterns
    local results
    results=$(search_pattern_examples "agent markdown frontmatter")

    if [[ -z "$results" ]] || [[ "$results" == "[]" ]]; then
        log_warn "No agent patterns discovered"
        return 0
    fi

    log_info "Would analyze agent patterns from search results"
}

# ============================================================================
# Rule Generation
# ============================================================================

generate_external_rule() {
    local rule_id="$1"
    local pattern="$2"
    local confidence="$3"
    local source_url="$4"
    local description="$5"

    local rule_file="$RULES_EXTERNAL_DIR/${rule_id}.json"

    # Check if rule already exists
    if [[ -f "$rule_file" ]]; then
        log_warn "External rule already exists: $rule_id"
        return 0
    fi

    # Create rule JSON
    local rule_json
    rule_json=$(cat <<EOF
{
  "rule_id": "$rule_id",
  "version": "1.0.0",
  "category": "web-discovered",
  "severity": "warning",
  "confidence": $confidence,
  "applies_to": {
    "component": "hooks",
    "pattern": ".*\\.md$"
  },
  "validation": {
    "type": "static",
    "checks": [
      {
        "check_id": "has-pattern",
        "type": "regex",
        "pattern": "$pattern",
        "error_message": "$description"
      }
    ]
  },
  "fix_template": {
    "type": "manual",
    "content": "See documentation: $source_url"
  },
  "references": [
    "$source_url"
  ],
  "learned_from": "web_search",
  "last_updated": "$(get_timestamp)"
}
EOF
)

    # Validate JSON
    if ! echo "$rule_json" | jq empty 2>/dev/null; then
        log_error "Invalid JSON generated for rule: $rule_id"
        return 1
    fi

    # Write rule file
    write_json "$rule_json" "$rule_file"
    log_success "Created external rule: $rule_id (confidence: $confidence)"
}

# ============================================================================
# Main Discovery Loop
# ============================================================================

main() {
    init_debugger

    log_info "Starting web pattern discovery..."

    # Ensure external rules directory exists
    mkdir -p "$RULES_EXTERNAL_DIR"

    # Search for best practices
    log_info "Searching for Claude Code plugin best practices..."

    local results
    results=$(search_plugin_best_practices 2026)

    if [[ -z "$results" ]] || [[ "$results" == "[]" ]]; then
        log_warn "No search results available (WebSearch tool integration pending)"
        log_info "Skipping web discovery for now"
        exit 0
    fi

    # Process search results
    if has_jq; then
        local url_count
        url_count=$(echo "$results" | jq 'length' 2>/dev/null || echo "0")

        log_info "Found $url_count potential sources"

        # Discover patterns by category
        discover_hook_patterns
        discover_plugin_schema_patterns
        discover_agent_patterns
    fi

    # Example external rule generation (manual for now)
    # This demonstrates the structure - actual rules would be discovered from web

    # Example: Hook description best practice
    generate_external_rule \
        "hook-has-description-external" \
        "^---.*description:.*---" \
        "0.7" \
        "https://docs.anthropic.com/claude-code/plugins/hooks" \
        "Hooks should include description in frontmatter (web-discovered pattern)"

    log_success "Web discovery complete"
    log_info "External rules: $(find "$RULES_EXTERNAL_DIR" -name "*.json" | wc -l | tr -d ' ')"

    # Record discovery event
    local discovery_record
    discovery_record=$(cat <<EOF
{
  "timestamp": "$(get_timestamp)",
  "session_id": "$CURRENT_SESSION_ID",
  "event": "web_discovery",
  "sources_checked": $(echo "$results" | jq 'length' 2>/dev/null || echo "0"),
  "rules_created": $(find "$RULES_EXTERNAL_DIR" -name "*.json" | wc -l | tr -d ' ')
}
EOF
)
    append_jsonl "$discovery_record" "$METRICS_FILE"
}

# ============================================================================
# Entry Point
# ============================================================================

main "$@"
