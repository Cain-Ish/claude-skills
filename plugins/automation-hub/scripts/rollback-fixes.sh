#!/usr/bin/env bash
# Rollback auto-applied fixes to last git checkpoint

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Load Latest Checkpoint ===

CHECKPOINT_DIR="${HOME}/.claude/automation-hub/checkpoints"
LATEST_CHECKPOINT="${CHECKPOINT_DIR}/latest"

if [[ ! -f "${LATEST_CHECKPOINT}" ]]; then
    echo "No checkpoint found to rollback to" >&2
    exit 1
fi

CHECKPOINT=$(cat "${LATEST_CHECKPOINT}")

debug "Rolling back to checkpoint: ${CHECKPOINT}"

# === Verify Git Repository ===

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "Not a git repository" >&2
    exit 1
fi

# === Check if Checkpoint Exists ===

if ! git stash list | grep -q "${CHECKPOINT}"; then
    echo "Checkpoint ${CHECKPOINT} not found in git stash" >&2
    exit 1
fi

# === Rollback ===

echo "Rolling back auto-applied fixes..."
echo "Checkpoint: ${CHECKPOINT}"
echo ""

# Pop the stash
if git stash pop "${CHECKPOINT}"; then
    echo "✓ Rollback successful"

    # Remove checkpoint file
    rm -f "${LATEST_CHECKPOINT}"

    # Log rollback
    log_decision "auto_apply" "rollback" "User requested rollback" "{\"checkpoint\": \"${CHECKPOINT}\"}"

    exit 0
else
    echo "✗ Rollback failed" >&2
    echo "You may need to manually resolve conflicts" >&2
    exit 1
fi
