#!/usr/bin/env bash
# Auto-apply self-debugger fixes with safety mechanisms
# Implements SEAL-style self-edit patterns from 2025 research

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Configuration ===

MIN_CONFIDENCE=$(get_config_value ".auto_apply.min_confidence" "0.90")
ALLOWED_SEVERITIES=$(get_config_value ".auto_apply.allowed_severities" '["low"]')
CREATE_CHECKPOINTS=$(get_config_value ".auto_apply.create_checkpoints" "true")
MAX_FIXES=$(get_config_value ".auto_apply.max_fixes_per_session" "5")

# === Check if Auto-Apply is Enabled ===

if ! is_feature_enabled "auto_apply"; then
    debug "Auto-apply disabled, skipping"
    exit 0
fi

# === Load Self-Debugger Findings ===

FINDINGS_FILE="${HOME}/.claude/self-debugger/findings/issues.jsonl"

if [[ ! -f "${FINDINGS_FILE}" ]]; then
    debug "No self-debugger findings available"
    exit 0
fi

# === Filter Auto-Fixable Issues ===

filter_autofix_eligible() {
    local min_conf="$1"
    local allowed_sev="$2"

    if [[ ! -f "${FINDINGS_FILE}" ]]; then
        echo "[]"
        return
    fi

    # Parse allowed severities
    local severity_filter
    severity_filter=$(echo "${allowed_sev}" | jq -r '.[]' | paste -sd '|' -)

    debug "Filtering fixes: confidence >= ${min_conf}, severity in [${severity_filter}]"

    # Filter issues that meet criteria
    jq -c --argjson min_conf "${min_conf}" --arg sev_filter "${severity_filter}" '
        select(
            (.severity | test($sev_filter; "i")) and
            (.auto_fixable == true) and
            (.confidence >= $min_conf) and
            (.fix_applied != true)
        )
    ' "${FINDINGS_FILE}" | jq -s '.'
}

# === Risk Classification ===

classify_fix_risk() {
    local issue="$1"

    local severity
    severity=$(echo "${issue}" | jq -r '.severity')

    local category
    category=$(echo "${issue}" | jq -r '.category // "unknown"')

    local file_count
    file_count=$(echo "${issue}" | jq -r '.affected_files | length')

    # Risk factors
    local risk_score=0

    # Severity
    case "${severity}" in
        low) risk_score=$((risk_score + 1)) ;;
        medium) risk_score=$((risk_score + 3)) ;;
        high) risk_score=$((risk_score + 5)) ;;
    esac

    # Category
    case "${category}" in
        formatting|style|documentation|typo) risk_score=$((risk_score + 0)) ;;
        deprecation|syntax|missing_import) risk_score=$((risk_score + 1)) ;;
        logic|error_handling|performance) risk_score=$((risk_score + 3)) ;;
        security|api_breaking|data_loss) risk_score=$((risk_score + 10)) ;;
    esac

    # File count
    if [[ ${file_count} -gt 5 ]]; then
        risk_score=$((risk_score + 3))
    elif [[ ${file_count} -gt 1 ]]; then
        risk_score=$((risk_score + 1))
    fi

    # Classification
    if [[ ${risk_score} -le 2 ]]; then
        echo "AUTO_APPLY"
    elif [[ ${risk_score} -le 5 ]]; then
        echo "SUGGEST_APPLY"
    else
        echo "MANUAL_REVIEW"
    fi
}

# === Create Git Checkpoint ===

create_checkpoint() {
    if [[ "${CREATE_CHECKPOINTS}" != "true" ]]; then
        debug "Checkpoints disabled"
        return 0
    fi

    local checkpoint_name="automation-hub-autofix-$(date +%s)"

    debug "Creating git checkpoint: ${checkpoint_name}"

    # Check if git repo
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        debug "Not a git repository, skipping checkpoint"
        return 0
    fi

    # Create stash with untracked files
    if git stash push --include-untracked -m "${checkpoint_name}" >/dev/null 2>&1; then
        # Get stash reference
        local stash_ref
        stash_ref=$(git stash list | grep "${checkpoint_name}" | head -1 | cut -d: -f1)

        # Save checkpoint metadata
        local checkpoint_dir="${HOME}/.claude/automation-hub/checkpoints"
        mkdir -p "${checkpoint_dir}"

        echo "${stash_ref}" > "${checkpoint_dir}/latest"

        debug "Checkpoint created: ${stash_ref}"
        echo "${stash_ref}"
    else
        debug "Nothing to checkpoint (working directory clean)"
        return 0
    fi
}

# === Apply Fix ===

apply_fix() {
    local issue="$1"

    local issue_id
    issue_id=$(echo "${issue}" | jq -r '.id')

    local file_path
    file_path=$(echo "${issue}" | jq -r '.file')

    local fix_command
    fix_command=$(echo "${issue}" | jq -r '.suggested_fix.command // empty')

    local fix_patch
    fix_patch=$(echo "${issue}" | jq -r '.suggested_fix.patch // empty')

    debug "Applying fix for issue ${issue_id} in ${file_path}"

    # Apply fix based on type
    if [[ -n "${fix_command}" ]]; then
        # Execute fix command
        debug "Running fix command: ${fix_command}"
        if eval "${fix_command}" >/dev/null 2>&1; then
            debug "Fix applied successfully"
            return 0
        else
            debug "Fix command failed"
            return 1
        fi
    elif [[ -n "${fix_patch}" ]]; then
        # Apply patch
        debug "Applying patch to ${file_path}"
        if echo "${fix_patch}" | patch -p1 >/dev/null 2>&1; then
            debug "Patch applied successfully"
            return 0
        else
            debug "Patch application failed"
            return 1
        fi
    else
        debug "No fix command or patch available"
        return 1
    fi
}

# === Mark Fix as Applied ===

mark_fix_applied() {
    local issue_id="$1"
    local success="$2"

    # Update findings file with fix status
    local temp_file="${FINDINGS_FILE}.tmp"

    jq -c --arg id "${issue_id}" --arg status "${success}" '
        if .id == $id then
            . + {
                fix_applied: ($status == "true"),
                fix_applied_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ")),
                fix_applied_by: "automation-hub"
            }
        else
            .
        end
    ' "${FINDINGS_FILE}" > "${temp_file}"

    mv "${temp_file}" "${FINDINGS_FILE}"
}

# === Main Execution ===

main() {
    debug "Auto-apply: Checking for fixable issues..."

    # Check session limit
    local fixes_applied
    fixes_applied=$(get_session_state_value ".actions.auto_fix_count" "0")

    if [[ ${fixes_applied} -ge ${MAX_FIXES} ]]; then
        debug "Session fix limit reached (${fixes_applied}/${MAX_FIXES})"
        log_decision "auto_apply" "rate_limited" "Max fixes per session exceeded" "{\"count\": ${fixes_applied}}"
        exit 0
    fi

    # Filter eligible issues
    local eligible_issues
    eligible_issues=$(filter_autofix_eligible "${MIN_CONFIDENCE}" "${ALLOWED_SEVERITIES}")

    local issue_count
    issue_count=$(echo "${eligible_issues}" | jq 'length')

    debug "Found ${issue_count} auto-fixable issues"

    if [[ ${issue_count} -eq 0 ]]; then
        debug "No eligible fixes"
        exit 0
    fi

    # Create checkpoint before any fixes
    local checkpoint
    checkpoint=$(create_checkpoint)

    # Process each issue
    local applied=0
    local failed=0

    while IFS= read -r issue; do
        local issue_id
        issue_id=$(echo "${issue}" | jq -r '.id')

        # Classify risk
        local risk
        risk=$(classify_fix_risk "${issue}")

        debug "Issue ${issue_id}: risk=${risk}"

        # Only auto-apply low-risk fixes
        if [[ "${risk}" != "AUTO_APPLY" ]]; then
            debug "Skipping: risk too high (${risk})"
            continue
        fi

        # Check if we've hit session limit
        if [[ ${applied} -ge $((MAX_FIXES - fixes_applied)) ]]; then
            debug "Reached max fixes for this run"
            break
        fi

        # Apply fix
        if apply_fix "${issue}"; then
            mark_fix_applied "${issue_id}" "true"
            applied=$((applied + 1))

            # Log success
            local metadata
            metadata=$(echo "${issue}" | jq -c '{
                issue_id: .id,
                severity: .severity,
                category: .category,
                file: .file,
                checkpoint: "'"${checkpoint}"'"
            }')

            log_decision "auto_apply" "applied" "Auto-applied low-risk fix" "${metadata}"

            echo "✓ Auto-applied fix: ${issue_id}"
        else
            mark_fix_applied "${issue_id}" "false"
            failed=$((failed + 1))

            log_decision "auto_apply" "failed" "Fix application failed" "{\"issue_id\": \"${issue_id}\"}"

            echo "✗ Failed to apply fix: ${issue_id}"
        fi
    done < <(echo "${eligible_issues}" | jq -c '.[]')

    # Update session counter
    increment_session_counter ".actions.auto_fix_count" "${applied}"

    # Summary
    if [[ ${applied} -gt 0 ]]; then
        echo ""
        echo "🔧 Auto-applied ${applied} fix(es)"
        if [[ -n "${checkpoint}" ]]; then
            echo "   Checkpoint: ${checkpoint}"
            echo "   Rollback: /automation rollback-fixes"
        fi
    fi

    if [[ ${failed} -gt 0 ]]; then
        echo "⚠️  ${failed} fix(es) failed to apply"
    fi
}

# Run main
main

exit 0
