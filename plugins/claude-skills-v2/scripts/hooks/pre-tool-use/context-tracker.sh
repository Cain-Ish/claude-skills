#!/usr/bin/env bash
set -euo pipefail

# Context tracker for PreToolUse
# Tracks all tool usage for the learning engine to detect patterns

# Configuration
CLAUDE_SKILLS_DIR="${HOME}/.claude/claude-skills"
CONTEXT_DIR="${CLAUDE_SKILLS_DIR}/context"
CONTEXT_LOG="${CONTEXT_DIR}/tool-usage.jsonl"

# Create directories if they don't exist
mkdir -p "$CONTEXT_DIR"

# Get hook input from stdin
HOOK_INPUT=$(cat)

# Extract relevant data
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // "unknown"')
TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // "unknown"')
TOOL_INPUT=$(echo "$HOOK_INPUT" | jq -r '.tool_input // {}')

# Create context tracking entry
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CONTEXT_ENTRY=$(jq -n \
  --arg timestamp "$TIMESTAMP" \
  --arg session_id "$SESSION_ID" \
  --arg tool_name "$TOOL_NAME" \
  --argjson tool_input "$TOOL_INPUT" \
  '{
    timestamp: $timestamp,
    session_id: $session_id,
    tool_name: $tool_name,
    tool_input: $tool_input,
    tracking_type: "pre_execution"
  }')

# Append to context log
echo "$CONTEXT_ENTRY" >> "$CONTEXT_LOG"

# Keep context log manageable (last 5,000 entries)
if [[ -f "$CONTEXT_LOG" ]]; then
  LINE_COUNT=$(wc -l < "$CONTEXT_LOG")
  if (( LINE_COUNT > 5000 )); then
    tail -5000 "$CONTEXT_LOG" > "${CONTEXT_LOG}.tmp"
    mv "${CONTEXT_LOG}.tmp" "$CONTEXT_LOG"
  fi
fi

# Return standard PreToolUse output (always allow - this is just tracking)
OUTPUT_JSON='{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "",
    "additionalContext": ""
  }
}'

echo "$OUTPUT_JSON"
exit 0
