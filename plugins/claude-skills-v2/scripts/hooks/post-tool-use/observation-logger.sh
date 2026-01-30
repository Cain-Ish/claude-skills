#!/usr/bin/env bash
set -euo pipefail

# Observation logger for continuous learning
# Logs all tool executions to enable pattern detection

# Configuration
CLAUDE_SKILLS_DIR="${HOME}/.claude/claude-skills"
OBSERVATIONS_DIR="${CLAUDE_SKILLS_DIR}/observations"
OBSERVATIONS_LOG="${OBSERVATIONS_DIR}/observations.jsonl"
SESSION_DIR="${OBSERVATIONS_DIR}/sessions"

# Create directories if they don't exist
mkdir -p "$OBSERVATIONS_DIR" "$SESSION_DIR"

# Get hook input from stdin
HOOK_INPUT=$(cat)

# Extract relevant data
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // "unknown"')
TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // "unknown"')
TOOL_INPUT=$(echo "$HOOK_INPUT" | jq -r '.tool_input // {}')
TOOL_RESPONSE=$(echo "$HOOK_INPUT" | jq -r '.tool_response // {}')

# Determine event type based on tool usage patterns
EVENT_TYPE="tool_execution"

# Check for potential user corrections (comparing similar tool calls)
# This is a simplification - real correction detection needs more context
if [[ "$TOOL_NAME" == "Edit" ]] && echo "$TOOL_INPUT" | jq -e '.old_string' > /dev/null 2>&1; then
  # Edit tool often indicates a correction
  EVENT_TYPE="potential_correction"
fi

# Check for error patterns
if echo "$TOOL_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
  EVENT_TYPE="error_encountered"
fi

# Detect domain based on file paths and tool usage
DOMAIN="general"
if echo "$TOOL_INPUT" | jq -r '.file_path // ""' | grep -qE "\.(test|spec)\.(ts|js|py)"; then
  DOMAIN="testing"
elif echo "$TOOL_INPUT" | jq -r '.file_path // ""' | grep -qE "\.(ts|tsx|js|jsx|py|go|rs)$"; then
  DOMAIN="code-modification"
elif echo "$TOOL_INPUT" | jq -r '.command // ""' | grep -qE "^git "; then
  DOMAIN="git-workflow"
elif echo "$TOOL_INPUT" | jq -r '.command // ""' | grep -qE "(npm|pnpm|yarn|bun)"; then
  DOMAIN="package-management"
fi

# Create observation entry
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
OBSERVATION=$(jq -n \
  --arg timestamp "$TIMESTAMP" \
  --arg session_id "$SESSION_ID" \
  --arg event_type "$EVENT_TYPE" \
  --arg tool_name "$TOOL_NAME" \
  --argjson tool_input "$TOOL_INPUT" \
  --arg domain "$DOMAIN" \
  '{
    timestamp: $timestamp,
    session_id: $session_id,
    event_type: $event_type,
    trigger: $tool_name,
    action: ($tool_input | tostring),
    domain: $domain,
    metadata: {
      tool_name: $tool_name,
      tool_input: $tool_input
    }
  }')

# Append to observations log
echo "$OBSERVATION" >> "$OBSERVATIONS_LOG"

# Also append to session-specific log
SESSION_LOG="${SESSION_DIR}/${SESSION_ID}.jsonl"
echo "$OBSERVATION" >> "$SESSION_LOG"

# Keep observations log manageable (last 10,000 entries)
if [[ -f "$OBSERVATIONS_LOG" ]]; then
  LINE_COUNT=$(wc -l < "$OBSERVATIONS_LOG")
  if (( LINE_COUNT > 10000 )); then
    tail -10000 "$OBSERVATIONS_LOG" > "${OBSERVATIONS_LOG}.tmp"
    mv "${OBSERVATIONS_LOG}.tmp" "$OBSERVATIONS_LOG"
  fi
fi

# Exit successfully (this is async, don't block)
exit 0
