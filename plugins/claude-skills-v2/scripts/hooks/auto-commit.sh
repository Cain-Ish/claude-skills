#!/usr/bin/env bash
set -euo pipefail

# Auto-commit system for plugin development
# Automatically commits changes to prevent data loss during development

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PLUGIN_DIR"

# Configuration
AUTO_COMMIT_ENABLED="${AUTO_COMMIT_ENABLED:-true}"
MIN_INTERVAL_SECONDS="${AUTO_COMMIT_MIN_INTERVAL:-300}" # 5 minutes default
LAST_COMMIT_FILE="${PLUGIN_DIR}/.last-auto-commit"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
  echo -e "${BLUE}[auto-commit]${NC} $1"
}

# Check if auto-commit is enabled
if [[ "$AUTO_COMMIT_ENABLED" != "true" ]]; then
  log "Auto-commit disabled (set AUTO_COMMIT_ENABLED=true to enable)"
  exit 0
fi

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  log "Not in a git repository, skipping"
  exit 0
fi

# Check minimum interval since last auto-commit
if [[ -f "$LAST_COMMIT_FILE" ]]; then
  LAST_COMMIT_TIME=$(cat "$LAST_COMMIT_FILE")
  CURRENT_TIME=$(date +%s)
  TIME_DIFF=$((CURRENT_TIME - LAST_COMMIT_TIME))

  if [[ $TIME_DIFF -lt $MIN_INTERVAL_SECONDS ]]; then
    log "Last auto-commit was ${TIME_DIFF}s ago (min interval: ${MIN_INTERVAL_SECONDS}s), skipping"
    exit 0
  fi
fi

# Check if there are changes to commit
if git diff --quiet && git diff --cached --quiet; then
  # Check for untracked files
  if [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
    log "No changes to commit"
    exit 0
  fi
fi

log "Changes detected, creating auto-commit..."

# Run validation before committing
VALIDATION_SCRIPT="${PLUGIN_DIR}/scripts/validation/pre-commit-validator.sh"
if [[ -x "$VALIDATION_SCRIPT" ]]; then
  log "Running pre-commit validation..."
  if ! "$VALIDATION_SCRIPT" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Validation failed, but auto-committing anyway to prevent data loss${NC}"
    echo -e "${YELLOW}   Run ./scripts/validation/pre-commit-validator.sh to see errors${NC}"
  else
    log "✅ Validation passed"
  fi
fi

# Stage all changes (including untracked files)
git add -A

# Create commit message
TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
CHANGED_FILES=$(git diff --cached --name-only | wc -l | tr -d ' ')

COMMIT_MSG="🤖 Auto-commit: Plugin development checkpoint

Auto-committed at: ${TIMESTAMP}
Changed files: ${CHANGED_FILES}

Changes:
$(git diff --cached --name-status | head -20)
$(if [[ $(git diff --cached --name-status | wc -l) -gt 20 ]]; then echo "... and more"; fi)

---
This is an automatic commit to prevent data loss during plugin development.
Created by: scripts/hooks/auto-commit.sh"

# Create the commit
if git commit -m "$COMMIT_MSG" > /dev/null 2>&1; then
  COMMIT_HASH=$(git rev-parse --short HEAD)
  echo -e "${GREEN}✅ Auto-commit created: ${COMMIT_HASH}${NC}"
  echo -e "${GREEN}   Files committed: ${CHANGED_FILES}${NC}"

  # Update last commit timestamp
  date +%s > "$LAST_COMMIT_FILE"

  # Optionally push to remote
  if [[ "${AUTO_PUSH:-false}" == "true" ]]; then
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    log "Auto-pushing to origin/${CURRENT_BRANCH}..."

    if git push origin "$CURRENT_BRANCH" 2>&1; then
      echo -e "${GREEN}✅ Changes pushed to remote${NC}"
    else
      echo -e "${YELLOW}⚠️  Failed to push to remote (may need authentication)${NC}"
    fi
  else
    log "💡 Run 'git push' to sync with remote (or set AUTO_PUSH=true)"
  fi
else
  echo -e "${YELLOW}⚠️  Failed to create auto-commit${NC}"
  exit 1
fi

exit 0
