#!/usr/bin/env bash
set -euo pipefail

# PreToolUse Hook Template
# TODO: Replace with your hook logic

# Get hook input from stdin
HOOK_INPUT=$(cat)

# Extract relevant data
# SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // "unknown"')
# TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // "unknown"')
# TOOL_INPUT=$(echo "$HOOK_INPUT" | jq -r '.tool_input // {}')

# TODO: Extract specific fields from tool_input based on tool type
# For Bash: COMMAND=$(echo "$HOOK_INPUT" | jq -r '.tool_input.command // empty')
# For Write: FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // empty')
# For Edit: FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // empty')
# For Read: FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // empty')

# Initialize output with default "allow"
OUTPUT_JSON='{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "",
    "additionalContext": ""
  }
}'

# Function to block operation
block_operation() {
  local reason="$1"
  OUTPUT_JSON=$(echo "$OUTPUT_JSON" | jq --arg reason "$reason" '
    .hookSpecificOutput.permissionDecision = "deny" |
    .hookSpecificOutput.permissionDecisionReason = $reason
  ')
  echo "$OUTPUT_JSON"
  exit 0
}

# Function to warn about operation
warn_operation() {
  local warning="$1"
  OUTPUT_JSON=$(echo "$OUTPUT_JSON" | jq --arg warning "$warning" '
    .hookSpecificOutput.permissionDecision = "ask" |
    .hookSpecificOutput.permissionDecisionReason = $warning
  ')
  echo "$OUTPUT_JSON"
  exit 0
}

# Function to add context (allow with message)
add_context() {
  local context="$1"
  OUTPUT_JSON=$(echo "$OUTPUT_JSON" | jq --arg ctx "$context" '
    .hookSpecificOutput.additionalContext = $ctx
  ')
}

# TODO: Implement your validation logic here
# Example patterns:
#
# Check for dangerous patterns:
# if [[ "$COMMAND" =~ dangerous_pattern ]]; then
#   block_operation "Reason for blocking"
# fi
#
# Warn about risky operations:
# if [[ "$FILE_PATH" =~ \.env$ ]]; then
#   warn_operation "Editing .env file - ensure no secrets are committed"
# fi
#
# Add helpful context:
# if [[ "$FILE_PATH" =~ \.test\. ]]; then
#   add_context "Remember to run tests after editing"
# fi

# Output result
echo "$OUTPUT_JSON"
exit 0
