#!/bin/bash
# ============================================================================
# Self-Debugger Plugin - Rule Engine
# ============================================================================
# Rule loading, validation execution, and fix template application.
# Source this file after common.sh:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/rule-engine.sh"
# ============================================================================

set -euo pipefail

# ============================================================================
# Rule Loading
# ============================================================================

# Load all rules from a directory
# Usage: load_rules_from_dir "/path/to/rules/core"
# Returns: JSON array of rules
load_rules_from_dir() {
    local rules_dir="$1"
    local rules_json="[]"

    if [[ ! -d "$rules_dir" ]]; then
        echo "$rules_json"
        return 0
    fi

    # Find all .json files in the directory
    while IFS= read -r -d '' rule_file; do
        if [[ -f "$rule_file" ]]; then
            local rule_content
            if has_jq; then
                rule_content=$(jq -c '.' "$rule_file" 2>/dev/null || echo "null")
            else
                rule_content=$(cat "$rule_file" 2>/dev/null || echo "null")
            fi

            if [[ "$rule_content" != "null" ]]; then
                # Add rule to array
                if has_jq; then
                    rules_json=$(echo "$rules_json" | jq -c ". + [$rule_content]" 2>/dev/null || echo "$rules_json")
                fi
            fi
        fi
    done < <(find "$rules_dir" -name "*.json" -print0 2>/dev/null)

    echo "$rules_json"
}

# Load all rules (core + learned + external)
# Returns: JSON array of all rules, sorted by confidence (descending)
load_all_rules() {
    local all_rules="[]"

    # Load core rules
    local core_rules
    core_rules=$(load_rules_from_dir "$RULES_CORE_DIR")
    if has_jq; then
        all_rules=$(echo "$all_rules" | jq -c ". + $core_rules" 2>/dev/null || echo "[]")
    fi

    # Load learned rules
    local learned_rules
    learned_rules=$(load_rules_from_dir "$RULES_LEARNED_DIR")
    if has_jq; then
        all_rules=$(echo "$all_rules" | jq -c ". + $learned_rules" 2>/dev/null || echo "$all_rules")
    fi

    # Load external rules
    local external_rules
    external_rules=$(load_rules_from_dir "$RULES_EXTERNAL_DIR")
    if has_jq; then
        all_rules=$(echo "$all_rules" | jq -c ". + $external_rules" 2>/dev/null || echo "$all_rules")
    fi

    # Sort by confidence (descending)
    if has_jq; then
        all_rules=$(echo "$all_rules" | jq -c 'sort_by(-.confidence)' 2>/dev/null || echo "$all_rules")
    fi

    echo "$all_rules"
}

# ============================================================================
# Rule Matching
# ============================================================================

# Check if a rule applies to a component
# Usage: rule_applies_to '{"applies_to": {...}}' "hooks/SessionStart.md"
# Returns: 0 if applies, 1 if not
rule_applies_to() {
    local rule_json="$1"
    local component_path="$2"

    if ! has_jq; then
        log_warn "jq not available, cannot check rule applicability"
        return 1
    fi

    # Extract applies_to criteria
    local component_type
    component_type=$(echo "$rule_json" | jq -r '.applies_to.component // ""' 2>/dev/null)
    local pattern
    pattern=$(echo "$rule_json" | jq -r '.applies_to.pattern // ""' 2>/dev/null)

    # Check component type (hooks, agents, skills, scripts)
    if [[ -n "$component_type" ]]; then
        if ! [[ "$component_path" =~ ^$component_type/ ]]; then
            return 1
        fi
    fi

    # Check pattern match
    if [[ -n "$pattern" ]]; then
        if ! [[ "$component_path" =~ $pattern ]]; then
            return 1
        fi
    fi

    return 0
}

# Find rules applicable to a component
# Usage: find_applicable_rules "$all_rules" "hooks/SessionStart.md"
# Returns: JSON array of applicable rules
find_applicable_rules() {
    local all_rules_json="$1"
    local component_path="$2"
    local applicable_rules="[]"

    if ! has_jq; then
        echo "$applicable_rules"
        return 0
    fi

    # Iterate through rules
    local rule_count
    rule_count=$(echo "$all_rules_json" | jq 'length' 2>/dev/null || echo "0")

    for ((i=0; i<rule_count; i++)); do
        local rule
        rule=$(echo "$all_rules_json" | jq -c ".[$i]" 2>/dev/null)

        if rule_applies_to "$rule" "$component_path"; then
            applicable_rules=$(echo "$applicable_rules" | jq -c ". + [$rule]" 2>/dev/null || echo "$applicable_rules")
        fi
    done

    echo "$applicable_rules"
}

# ============================================================================
# Validation Execution
# ============================================================================

# Execute a single validation check against a file
# Returns: 0 if valid, 1 if violation found
execute_validation_check() {
    local check_json="$1"
    local file_path="$2"
    local plugin_name="$3"

    if ! has_jq; then
        log_debug "jq not available, skipping check"
        return 0  # Skip check if jq unavailable (avoid false positives)
    fi

    # Extract check parameters
    local check_type
    check_type=$(echo "$check_json" | jq -r '.type // "unknown"' 2>/dev/null)
    local check_id
    check_id=$(echo "$check_json" | jq -r '.check_id // "unknown"' 2>/dev/null)

    log_debug "Executing check: $check_id (type: $check_type) on $file_path"

    # Validate path exists (structure checks can work on directories, others need files)
    if [[ "$check_type" == "structure" ]]; then
        if [[ ! -e "$file_path" ]]; then
            log_debug "Path not found: $file_path"
            return 1
        fi
    else
        if [[ ! -f "$file_path" ]]; then
            log_debug "File not found: $file_path"
            return 1
        fi
    fi

    case "$check_type" in
        "regex")
            # Regex pattern matching against file content
            local pattern
            pattern=$(echo "$check_json" | jq -r '.pattern // ""' 2>/dev/null)

            if [[ -z "$pattern" ]]; then
                log_warn "Regex check missing pattern: $check_id"
                return 0  # Avoid false positive if rule is malformed
            fi

            # Test pattern directly on file for better multiline support
            # Use grep -Pzo if available (GNU grep), otherwise fall back to basic grep
            if command -v pcregrep &>/dev/null; then
                # Use pcregrep for advanced multiline regex
                if pcregrep -qM "$pattern" "$file_path" 2>/dev/null; then
                    log_debug "  ✓ Regex check passed: $check_id"
                    return 0  # Valid
                fi
            elif grep -qE "$pattern" "$file_path" 2>/dev/null; then
                # Basic grep (works for single-line patterns)
                log_debug "  ✓ Regex check passed: $check_id"
                return 0  # Valid
            fi

            log_debug "  ✗ Regex check failed: $check_id (pattern: $pattern)"
            return 1  # Violation
            ;;

        "json-field")
            # JSON field validation
            local field
            field=$(echo "$check_json" | jq -r '.field // ""' 2>/dev/null)
            local required
            required=$(echo "$check_json" | jq -r '.required // false' 2>/dev/null)
            local pattern
            pattern=$(echo "$check_json" | jq -r '.pattern // ""' 2>/dev/null)

            if [[ -z "$field" ]]; then
                log_warn "JSON field check missing field: $check_id"
                return 0  # Avoid false positive
            fi

            # Extract field value
            local value
            value=$(extract_json_field "$file_path" "$field")

            # Check required
            if [[ "$required" == "true" ]] && [[ -z "$value" ]]; then
                log_debug "  ✗ Required field missing: $field"
                return 1  # Required field missing
            fi

            # Check pattern if provided and value exists
            if [[ -n "$pattern" ]] && [[ -n "$value" ]]; then
                if echo "$value" | grep -qE "$pattern"; then
                    log_debug "  ✓ JSON field check passed: $field"
                    return 0  # Valid
                else
                    log_debug "  ✗ JSON field pattern mismatch: $field (expected: $pattern, got: $value)"
                    return 1  # Pattern mismatch
                fi
            fi

            log_debug "  ✓ JSON field check passed: $field"
            return 0  # Valid
            ;;

        "structure")
            # File/directory structure validation
            local exists_check
            exists_check=$(echo "$check_json" | jq -r '.exists // ""' 2>/dev/null)

            if [[ -n "$exists_check" ]]; then
                # Check if path exists relative to plugin root
                local plugin_dir
                if [[ -d "$file_path" ]]; then
                    # file_path is the plugin directory itself (component=".")
                    # Remove trailing "/." if present
                    plugin_dir="${file_path%/.}"
                else
                    # file_path is a file, go up to plugin root
                    plugin_dir=$(dirname "$(dirname "$file_path")")
                fi
                local check_path="$plugin_dir/$exists_check"

                log_debug "  Checking existence: $check_path"
                if [[ -e "$check_path" ]]; then
                    log_debug "  ✓ Structure check passed: $exists_check exists"
                    return 0  # Valid
                else
                    log_debug "  ✗ Structure check failed: $exists_check not found"
                    return 1  # Violation
                fi
            fi

            # Check for minimum number of YAML frontmatter dashes (---)
            local min_dashes
            min_dashes=$(echo "$check_json" | jq -r '.min_dashes // 0' 2>/dev/null)

            if [[ "$min_dashes" -gt 0 ]]; then
                local dash_count=0
                if [[ -f "$file_path" ]]; then
                    # Count lines matching the pattern
                    dash_count=$(grep -E '^---\s*$' "$file_path" 2>/dev/null | wc -l | tr -d ' ')
                fi

                if [[ "$dash_count" -ge "$min_dashes" ]]; then
                    log_debug "  ✓ Structure check passed: found $dash_count '---' lines (min: $min_dashes)"
                    return 0  # Valid
                else
                    log_debug "  ✗ Structure check failed: found $dash_count '---' lines (min: $min_dashes)"
                    return 1  # Violation
                fi
            fi

            # If no specific structure check defined, pass
            return 0
            ;;

        *)
            log_warn "Unknown check type: $check_type for check $check_id"
            return 0  # Unknown check type - avoid false positive
            ;;
    esac
}

# Run all checks for a rule against a file
# Usage: validate_file_against_rule "$rule_json" "/path/to/file" "plugin-name"
# Returns: JSON array of violations (empty if valid)
validate_file_against_rule() {
    local rule_json="$1"
    local file_path="$2"
    local plugin_name="$3"
    local violations="[]"

    if ! has_jq; then
        echo "$violations"
        return 0
    fi

    # Extract rule metadata
    local rule_id
    rule_id=$(echo "$rule_json" | jq -r '.rule_id' 2>/dev/null)
    local severity
    severity=$(echo "$rule_json" | jq -r '.severity' 2>/dev/null)
    local confidence
    confidence=$(echo "$rule_json" | jq -r '.confidence' 2>/dev/null)

    # Get validation checks
    local checks
    checks=$(echo "$rule_json" | jq -c '.validation.checks // []' 2>/dev/null)
    local check_count
    check_count=$(echo "$checks" | jq 'length' 2>/dev/null || echo "0")

    # Run each check
    for ((i=0; i<check_count; i++)); do
        local check
        check=$(echo "$checks" | jq -c ".[$i]" 2>/dev/null)

        # Execute check
        if ! execute_validation_check "$check" "$file_path" "$plugin_name"; then
            # Violation found - create issue record
            local check_id
            check_id=$(echo "$check" | jq -r '.check_id' 2>/dev/null)
            local error_message
            error_message=$(echo "$check" | jq -r '.error_message' 2>/dev/null)

            local violation
            violation=$(cat <<EOF
{
  "rule_id": "$rule_id",
  "check_id": "$check_id",
  "severity": "$severity",
  "confidence": $confidence,
  "error_message": "$error_message",
  "file": "$file_path"
}
EOF
)
            violations=$(echo "$violations" | jq -c ". + [$violation]" 2>/dev/null || echo "$violations")
        fi
    done

    echo "$violations"
}

# ============================================================================
# Issue Recording
# ============================================================================

# Record an issue to findings file
# Usage: record_issue "$plugin" "$component" "$violation_json"
record_issue() {
    local plugin="$1"
    local component="$2"
    local violation_json="$3"

    if ! has_jq; then
        log_error "jq required to record issues"
        return 1
    fi

    # Extract violation details for deduplication check
    local rule_id
    rule_id=$(echo "$violation_json" | jq -r '.rule_id' 2>/dev/null)
    local severity
    severity=$(echo "$violation_json" | jq -r '.severity' 2>/dev/null)
    local confidence
    confidence=$(echo "$violation_json" | jq -r '.confidence' 2>/dev/null)
    local error_message
    error_message=$(echo "$violation_json" | jq -r '.error_message' 2>/dev/null)
    local file
    file=$(echo "$violation_json" | jq -r '.file' 2>/dev/null)

    # Deduplication: Check if same issue already exists (pending status)
    # Match criteria: plugin + component + rule_id
    if [[ -f "$ISSUES_FILE" ]]; then
        local existing_count=0
        if grep -q "\"plugin\": \"$plugin\".*\"component\": \"$component\".*\"rule_id\": \"$rule_id\".*\"status\": \"pending\"" "$ISSUES_FILE" 2>/dev/null; then
            existing_count=1
        fi

        if [[ "$existing_count" -gt 0 ]]; then
            log_debug "Issue already recorded (plugin: $plugin, component: $component, rule: $rule_id), skipping duplicate"
            return 0
        fi
    fi

    # Generate unique issue ID
    local issue_id
    issue_id=$(generate_uuid)

    # Create issue record
    local issue
    issue=$(cat <<EOF
{
  "issue_id": "$issue_id",
  "detected_at": "$(get_timestamp)",
  "session_id": "$CURRENT_SESSION_ID",
  "status": "pending",
  "plugin": "$plugin",
  "component": "$component",
  "rule_id": "$rule_id",
  "severity": "$severity",
  "confidence": $confidence,
  "location": {
    "file": "$file",
    "line": 0,
    "column": 0
  },
  "evidence": {
    "expected": "",
    "actual": "",
    "diff": "",
    "error_message": "$error_message"
  }
}
EOF
)

    # Append to issues file
    append_jsonl "$issue" "$ISSUES_FILE"

    log_info "Recorded issue: $issue_id ($severity) in $plugin/$component"
}

# ============================================================================
# Fix Template Application (placeholder for future implementation)
# ============================================================================

# Apply a fix template to a file
# Usage: apply_fix_template "$rule_json" "$file_path"
apply_fix_template() {
    local rule_json="$1"
    local file_path="$2"

    # AIDEV-NOTE: Fix template application will be implemented in Phase 3
    log_debug "Fix template application not yet implemented"
    return 0
}
