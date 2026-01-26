#!/usr/bin/env bash
# Apply learning coordinator optimization proposal with validation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Input ===

PROPOSAL_ID="${1:-}"

if [[ -z "${PROPOSAL_ID}" ]]; then
    echo "Usage: $0 <proposal_id>" >&2
    exit 1
fi

# === Load Proposal ===

PROPOSALS_DIR="${HOME}/.claude/automation-hub/proposals"
PROPOSAL_FILE="${PROPOSALS_DIR}/${PROPOSAL_ID}.json"

if [[ ! -f "${PROPOSAL_FILE}" ]]; then
    echo "Proposal not found: ${PROPOSAL_ID}" >&2
    exit 1
fi

proposal=$(cat "${PROPOSAL_FILE}")

# === Extract Proposal Details ===

proposal_type=$(echo "${proposal}" | jq -r '.type')
target=$(echo "${proposal}" | jq -r '.target')
current_value=$(echo "${proposal}" | jq -r '.current_value')
proposed_value=$(echo "${proposal}" | jq -r '.proposed_value')
confidence=$(echo "${proposal}" | jq -r '.confidence')
rationale=$(echo "${proposal}" | jq -r '.rationale')

# === Show Proposal ===

cat <<EOF
📊 Optimization Proposal: ${PROPOSAL_ID}

Type: ${proposal_type}
Target: ${target}
Current Value: ${current_value}
Proposed Value: ${proposed_value}
Confidence: ${confidence}

Rationale:
${rationale}

Impact Prediction:
$(echo "${proposal}" | jq -r '.impact_prediction | to_entries | map("  \(.key): \(.value)") | join("\n")')

EOF

# === Confirmation ===

# Check if high confidence (can auto-apply with notification)
if (( $(echo "${confidence} >= 0.85" | bc -l) )); then
    echo "⚡ High confidence proposal - applying automatically"
    apply=true
else
    echo -n "Apply this proposal? (yes/no): "
    read -r response

    if [[ "${response}" != "yes" ]]; then
        echo "Cancelled"
        exit 0
    fi
    apply=true
fi

# === Backup Current Config ===

config_path=$(get_config_path)
backup_path="${config_path}.backup.$(date +%s)"

cp "${config_path}" "${backup_path}"

debug "Config backup: ${backup_path}"

# === Apply Proposal ===

echo "Applying proposal..."

# Update config
updated_config=$(jq "${target} = ${proposed_value}" "${config_path}")
echo "${updated_config}" > "${config_path}"

# === Create Validation Tracker ===

validation_file="${PROPOSALS_DIR}/${PROPOSAL_ID}.validation.json"

jq -n \
    --arg id "${PROPOSAL_ID}" \
    --arg applied_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg backup "${backup_path}" \
    --arg target "${target}" \
    --argjson old "${current_value}" \
    --argjson new "${proposed_value}" \
    '{
        proposal_id: $id,
        applied_at: $applied_at,
        backup_path: $backup,
        target: $target,
        old_value: $old,
        new_value: $new,
        validation_period_days: 7,
        validation_due: (now + (7 * 86400) | strftime("%Y-%m-%dT%H:%M:%SZ")),
        status: "monitoring",
        baseline_metrics: {},
        post_change_metrics: {}
    }' > "${validation_file}"

# === Log Decision ===

log_decision "learning" "proposal_applied" "Applied optimization proposal" "$(jq -c '{
    proposal_id: .id,
    type: .type,
    target: .target,
    confidence: .confidence
}' "${PROPOSAL_FILE}")"

# === Output ===

cat <<EOF

✅ Proposal Applied Successfully

Target: ${target}
New Value: ${proposed_value}
Backup: ${backup_path}

📊 Monitoring Period: 7 days
The system will track metrics to validate this change.

Rollback: /automation rollback-proposal ${PROPOSAL_ID}
Status: /automation validation-status ${PROPOSAL_ID}

EOF

# Archive proposal
mv "${PROPOSAL_FILE}" "${PROPOSALS_DIR}/applied/${PROPOSAL_ID}.json" 2>/dev/null || true

exit 0
