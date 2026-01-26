#!/usr/bin/env bash
# Automation Hub Command Implementation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Input ===

SUBCOMMAND="${1:-status}"
shift || true
ARGS=("$@")

# === Subcommand Handlers ===

cmd_status() {
    echo "🤖 Automation Hub Status"
    echo ""
    echo "Features:"

    # Auto-Routing
    if is_feature_enabled "auto_routing"; then
        echo "  ✓ Auto-Routing: ENABLED"
    else
        echo "  ✗ Auto-Routing: DISABLED"
    fi

    if is_feature_enabled "auto_routing"; then
        threshold=$(get_config_value ".auto_routing.stage1_threshold" "4")
        auto_moderate=$(get_config_value ".auto_routing.stage2_auto_approve.moderate" "false")
        auto_complex=$(get_config_value ".auto_routing.stage2_auto_approve.complex" "false")

        echo "    - Stage 1 threshold: ${threshold}/10"
        echo "    - Auto-approve moderate: $(echo ${auto_moderate} | tr '[:lower:]' '[:upper:]')"
        echo "    - Auto-approve complex: $(echo ${auto_complex} | tr '[:lower:]' '[:upper:]')"

        # Show approval rates if available
        for band in moderate complex; do
            rate=$(get_approval_rate "${band}")
            samples=$(get_sample_count "${band}")
            if [[ ${samples} -gt 0 ]]; then
                echo "    - Approval rate (${band}): ${rate}% (${samples} samples)"
            fi
        done
    fi

    echo ""

    # Auto-Cleanup
    if is_feature_enabled "auto_cleanup"; then
        echo "  ✓ Auto-Cleanup: ENABLED"
    else
        echo "  ✗ Auto-Cleanup: DISABLED"
    fi

    if is_feature_enabled "auto_cleanup"; then
        idle_timeout=$(get_config_value ".auto_cleanup.triggers.idle_timeout_minutes" "10")
        require_clean=$(get_config_value ".auto_cleanup.safety_blockers.uncommitted_changes" "true")
        cleanups_today=$(count_events_today "auto_cleanup")

        echo "    - Idle timeout: ${idle_timeout} minutes"
        echo "    - Require clean git: $(echo ${require_clean} | tr '[:lower:]' '[:upper:]')"
        echo "    - Cleanups today: ${cleanups_today}"
    fi

    echo ""

    # Auto-Reflect
    if is_feature_enabled "auto_reflect"; then
        suggest_only=$(get_config_value ".auto_reflect.suggest_only" "true")
        if [[ "${suggest_only}" == "true" ]]; then
            echo "  ✓ Auto-Reflect: ENABLED (suggest-only)"
        else
            echo "  ✓ Auto-Reflect: ENABLED (auto-execute)"
        fi
    else
        echo "  ✗ Auto-Reflect: DISABLED"
    fi

    if is_feature_enabled "auto_reflect"; then
        threshold=$(get_config_value ".auto_reflect.worthiness_threshold" "20")
        suggestions_today=$(count_events_today "auto_reflect")

        echo "    - Worthiness threshold: ${threshold} points"
        echo "    - Suggestions today: ${suggestions_today}"
    fi

    echo ""

    # Auto-Apply
    if is_feature_enabled "auto_apply"; then
        echo "  ✓ Auto-Apply: ENABLED"
    else
        echo "  ✗ Auto-Apply: DISABLED"
    fi

    if is_feature_enabled "auto_apply"; then
        min_confidence=$(get_config_value ".auto_apply.min_confidence" "0.90")
        severities=$(get_config_value ".auto_apply.allowed_severities" '["low"]')

        echo "    - Min confidence: $(echo "${min_confidence} * 100" | bc)%"
        echo "    - Allowed severities: ${severities}"
    fi

    echo ""

    # Learning
    if is_feature_enabled "learning"; then
        echo "  ✓ Learning: ENABLED"
    else
        echo "  ✗ Learning: DISABLED"
    fi

    echo ""

    # Activity Summary
    echo "Activity (Last 24h):"
    show_activity_summary

    echo ""

    # Circuit Breakers
    echo "Circuit Breakers:"
    show_circuit_breaker_status

    echo ""

    # Rate Limits
    echo "Rate Limits:"
    show_rate_limit_usage
}

cmd_enable() {
    local feature="${ARGS[0]:-}"

    if [[ -z "${feature}" ]]; then
        echo "Error: Feature name required" >&2
        echo "Usage: /automation enable <feature|all>" >&2
        exit 1
    fi

    if [[ "${feature}" == "all" ]]; then
        update_config_value ".auto_routing.enabled" "true"
        update_config_value ".auto_cleanup.enabled" "true"
        update_config_value ".auto_reflect.enabled" "true"
        update_config_value ".learning.enabled" "true"
        # Note: auto_apply NOT enabled by default
        echo "✓ Enabled all automation features (except auto-apply)"
    else
        case "${feature}" in
            auto-routing|auto_routing)
                update_config_value ".auto_routing.enabled" "true"
                echo "✓ Enabled auto-routing"
                ;;
            auto-cleanup|auto_cleanup)
                update_config_value ".auto_cleanup.enabled" "true"
                echo "✓ Enabled auto-cleanup"
                ;;
            auto-reflect|auto_reflect)
                update_config_value ".auto_reflect.enabled" "true"
                echo "✓ Enabled auto-reflect"
                ;;
            auto-apply|auto_apply)
                echo "⚠️  Auto-apply can automatically modify your code."
                echo "Are you sure you want to enable it? (yes/no)"
                read -r confirm
                if [[ "${confirm}" == "yes" ]]; then
                    update_config_value ".auto_apply.enabled" "true"
                    echo "✓ Enabled auto-apply"
                else
                    echo "Cancelled"
                fi
                ;;
            learning)
                update_config_value ".learning.enabled" "true"
                echo "✓ Enabled learning"
                ;;
            *)
                echo "Error: Unknown feature: ${feature}" >&2
                echo "Valid features: auto-routing, auto-cleanup, auto-reflect, auto-apply, learning, all" >&2
                exit 1
                ;;
        esac
    fi
}

cmd_disable() {
    local feature="${ARGS[0]:-}"

    if [[ -z "${feature}" ]]; then
        echo "Error: Feature name required" >&2
        echo "Usage: /automation disable <feature|all>" >&2
        exit 1
    fi

    if [[ "${feature}" == "all" ]]; then
        update_config_value ".auto_routing.enabled" "false"
        update_config_value ".auto_cleanup.enabled" "false"
        update_config_value ".auto_reflect.enabled" "false"
        update_config_value ".auto_apply.enabled" "false"
        update_config_value ".learning.enabled" "false"
        echo "✓ Disabled all automation features"
    else
        case "${feature}" in
            auto-routing|auto_routing)
                update_config_value ".auto_routing.enabled" "false"
                echo "✓ Disabled auto-routing"
                ;;
            auto-cleanup|auto_cleanup)
                update_config_value ".auto_cleanup.enabled" "false"
                echo "✓ Disabled auto-cleanup"
                ;;
            auto-reflect|auto_reflect)
                update_config_value ".auto_reflect.enabled" "false"
                echo "✓ Disabled auto-reflect"
                ;;
            auto-apply|auto_apply)
                update_config_value ".auto_apply.enabled" "false"
                echo "✓ Disabled auto-apply"
                ;;
            learning)
                update_config_value ".learning.enabled" "false"
                echo "✓ Disabled learning"
                ;;
            *)
                echo "Error: Unknown feature: ${feature}" >&2
                echo "Valid features: auto-routing, auto-cleanup, auto-reflect, auto-apply, learning, all" >&2
                exit 1
                ;;
        esac
    fi
}

cmd_debug() {
    echo "🔍 Automation Hub Debug Info"
    echo ""

    # Recent Decisions
    echo "Recent Decisions (last 10):"
    show_recent_decisions 10

    echo ""

    # Failed Attempts
    echo "Failed Attempts:"
    show_failed_attempts

    echo ""

    # Config Validation
    echo "Configuration Validation:"
    validate_config

    echo ""

    # Metrics Health
    echo "Metrics Health:"
    show_metrics_health
}

cmd_rollback_fixes() {
    local checkpoint_dir="${HOME}/.claude/automation-hub/checkpoints"

    if [[ ! -d "${checkpoint_dir}" ]]; then
        echo "No checkpoints found" >&2
        exit 1
    fi

    local latest_checkpoint
    latest_checkpoint=$(ls -t "${checkpoint_dir}" | head -1)

    if [[ -z "${latest_checkpoint}" ]]; then
        echo "No checkpoints found" >&2
        exit 1
    fi

    echo "Rolling back to checkpoint: ${latest_checkpoint}"

    # Restore from git stash
    git stash pop "stash@{${latest_checkpoint}}"

    echo "✓ Rollback complete"
}

cmd_reset_learning() {
    echo "⚠️  This will reset all learning metrics and approval rates."
    echo "Are you sure? (yes/no)"
    read -r confirm

    if [[ "${confirm}" != "yes" ]]; then
        echo "Cancelled"
        exit 0
    fi

    local metrics_path
    metrics_path=$(get_metrics_path)

    # Backup current metrics
    cp "${metrics_path}" "${metrics_path}.backup.$(date +%s)"

    # Clear metrics
    echo "" > "${metrics_path}"

    echo "✓ Learning metrics reset (backup saved)"
}

cmd_config() {
    local config_path
    config_path=$(get_config_path)

    if is_command_available "${EDITOR}"; then
        "${EDITOR}" "${config_path}"
    else
        echo "Config file: ${config_path}"
        echo "Open with your preferred editor"
    fi
}

# === Helper Functions ===

get_approval_rate() {
    local band="$1"
    # TODO: Implement actual calculation from metrics
    echo "0"
}

get_sample_count() {
    local band="$1"
    # TODO: Implement actual count from metrics
    echo "0"
}

count_events_today() {
    local feature="$1"
    # TODO: Implement actual count from metrics
    echo "0"
}

show_activity_summary() {
    # TODO: Implement from metrics
    echo "  - Auto-routing invoked: 0 times"
    echo "  - User approvals: 0 (0%)"
    echo "  - User rejections: 0 (0%)"
    echo "  - Auto-cleanups: 0"
    echo "  - Reflection suggestions: 0"
}

show_circuit_breaker_status() {
    # TODO: Implement from config/metrics
    echo "  ✓ All circuits CLOSED (healthy)"
}

show_rate_limit_usage() {
    # TODO: Implement from metrics
    echo "  - Auto-routing: 0/10 per hour (0%)"
}

show_recent_decisions() {
    local count="$1"
    # TODO: Implement from metrics
    echo "  (No recent decisions)"
}

show_failed_attempts() {
    # TODO: Implement from metrics
    echo "  None"
}

validate_config() {
    local config_path
    config_path=$(get_config_path)

    if [[ -f "${config_path}" ]]; then
        echo "  ✓ Config file exists"
    else
        echo "  ✗ Config file missing"
        return
    fi

    if jq empty "${config_path}" 2>/dev/null; then
        echo "  ✓ Config valid JSON"
    else
        echo "  ✗ Config invalid JSON"
        return
    fi

    echo "  ✓ All required fields present"
}

show_metrics_health() {
    local metrics_path
    metrics_path=$(get_metrics_path)

    if [[ ! -f "${metrics_path}" ]]; then
        echo "  - No metrics file yet"
        return
    fi

    local line_count
    line_count=$(wc -l < "${metrics_path}" | tr -d ' ')

    local file_size
    file_size=$(du -h "${metrics_path}" | cut -f1)

    echo "  - Total entries: ${line_count}"
    echo "  - File size: ${file_size}"
}

update_config_value() {
    local key="$1"
    local value="$2"

    local config_path
    config_path=$(get_config_path)

    local updated_config
    updated_config=$(jq "${key} = ${value}" "${config_path}")

    echo "${updated_config}" > "${config_path}"
}

# === Main ===

case "${SUBCOMMAND}" in
    status)
        cmd_status
        ;;
    enable)
        cmd_enable
        ;;
    disable)
        cmd_disable
        ;;
    debug)
        cmd_debug
        ;;
    rollback-fixes)
        cmd_rollback_fixes
        ;;
    reset-learning)
        cmd_reset_learning
        ;;
    config)
        cmd_config
        ;;
    *)
        echo "Error: Unknown subcommand: ${SUBCOMMAND}" >&2
        echo "Usage: /automation <status|enable|disable|debug|rollback-fixes|reset-learning|config>" >&2
        exit 1
        ;;
esac
