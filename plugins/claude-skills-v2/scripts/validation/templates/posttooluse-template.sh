#!/usr/bin/env bash
set -euo pipefail

# PostToolUse Hook Template
# TODO: Replace with your hook logic

# Configuration
CLAUDE_SKILLS_DIR="${HOME}/.claude/claude-skills"
LOG_DIR="${CLAUDE_SKILLS_DIR}/logs"
LOG_FILE="${LOG_DIR}/hook-events.jsonl"

# Create directories if they don't exist
mkdir -p "$LOG_DIR"

# Get hook input from stdin
HOOK_INPUT=$(cat)

# Extract relevant data
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // "unknown"')
TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // "unknown"')
TOOL_INPUT=$(echo "$HOOK_INPUT" | jq -r '.tool_input // {}')
TOOL_RESPONSE=$(echo "$HOOK_INPUT" | jq -r '.tool_response // {}')

# TODO: Extract specific fields based on your needs
# For Bash: COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // empty')
# For Write/Edit: FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty')

# TODO: Implement your post-execution logic here
# Examples:
# - Log tool execution for learning
# - Track patterns for optimization
# - Collect metrics for analysis
# - Generate feedback for user

# Create log entry (example)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
LOG_ENTRY=$(jq -n \
  --arg timestamp "$TIMESTAMP" \
  --arg session_id "$SESSION_ID" \
  --arg tool_name "$TOOL_NAME" \
  --argjson tool_input "$TOOL_INPUT" \
  '{
    timestamp: $timestamp,
    session_id: $session_id,
    tool_name: $tool_name,
    tool_input: $tool_input
  }')

# Append to log (optional)
# echo "$LOG_ENTRY" >> "$LOG_FILE"

# Keep log manageable (optional)
# if [[ -f "$LOG_FILE" ]]; then
#   LINE_COUNT=$(wc -l < "$LOG_FILE")
#   if (( LINE_COUNT > 1000 )); then
#     tail -1000 "$LOG_FILE" > "${LOG_FILE}.tmp"
#     mv "${LOG_FILE}.tmp" "$LOG_FILE"
#   fi
# fi

# Generate feedback (optional)
FEEDBACK=""
# TODO: Add your feedback logic
# if [[ "$TOOL_NAME" == "Bash" ]] && echo "$TOOL_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
#   FEEDBACK="Command failed. Review error output."
# fi

# Return PostToolUse output
OUTPUT_JSON=$(jq -n \
  --arg feedback "$FEEDBACK" \
  '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $feedback
    }
  }')

echo "$OUTPUT_JSON"
exit 0
