#!/usr/bin/env bash
set -euo pipefail

# Write validation hook for PreToolUse
# Validates file writes to prevent common mistakes:
# - Writing .env files with secrets
# - Creating unnecessary .md documentation files
# - Writing to sensitive system locations

# Get hook input from stdin
HOOK_INPUT=$(cat)

# Extract file path from tool input
FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // empty')
CONTENT=$(echo "$HOOK_INPUT" | jq -r '.tool_input.content // empty')

# If no file path, exit
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Initialize output with default "allow"
OUTPUT_JSON='{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "",
    "additionalContext": ""
  }
}'

# Function to block write
block_write() {
  local reason="$1"
  OUTPUT_JSON=$(echo "$OUTPUT_JSON" | jq --arg reason "$reason" '
    .hookSpecificOutput.permissionDecision = "deny" |
    .hookSpecificOutput.permissionDecisionReason = $reason
  ')
  echo "$OUTPUT_JSON"
  exit 0
}

# Function to warn about write
warn_write() {
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

# Get filename
FILENAME=$(basename "$FILE_PATH")

# Block: Writing .env files
if [[ "$FILENAME" == ".env" ]] || [[ "$FILENAME" == .env.* ]]; then
  # Check if content contains potential secrets
  if echo "$CONTENT" | grep -qE "(API_KEY|SECRET|PASSWORD|TOKEN|PRIVATE_KEY)="; then
    block_write "Writing .env file with potential secrets detected. Use environment variables or secure vaults instead. Never commit secrets to version control."
  fi
fi

# Warn: Creating new README or documentation files (often unnecessary)
if [[ "$FILENAME" =~ ^README.*\.md$ ]] || [[ "$FILENAME" =~ ^CONTRIBUTING\.md$ ]] || [[ "$FILENAME" =~ ^CHANGELOG\.md$ ]]; then
  # Check if file already exists
  if [[ ! -f "$FILE_PATH" ]]; then
    warn_write "Creating new documentation file '$FILENAME'. The global CLAUDE.md instructions say: NEVER proactively create documentation files (*.md) or README files. Only create documentation files if explicitly requested by the User."
  fi
fi

# Warn: Creating generic .md files in project root
if [[ "$FILENAME" =~ \.md$ ]] && [[ "$FILE_PATH" =~ ^[^/]+\.md$ ]]; then
  # Check if it's a new file in project root
  if [[ ! -f "$FILE_PATH" ]]; then
    warn_write "Creating new .md file '$FILENAME' in project root. The global CLAUDE.md instructions say: NEVER proactively create documentation files. Only create if explicitly requested."
  fi
fi

# Block: Writing to system files
if [[ "$FILE_PATH" =~ ^/etc/ ]] || [[ "$FILE_PATH" =~ ^/usr/ ]] || [[ "$FILE_PATH" =~ ^/var/ ]]; then
  block_write "Attempting to write to system directory: $FILE_PATH. This requires elevated privileges and could damage the system."
fi

# Block: Writing to .ssh directory
if [[ "$FILE_PATH" =~ \.ssh/ ]]; then
  block_write "Attempting to write to .ssh directory: $FILE_PATH. SSH keys and configuration are sensitive and should be managed manually."
fi

# Warn: Writing credentials or configuration files
if [[ "$FILENAME" =~ (credentials|secrets|config)\.(json|yaml|yml|toml)$ ]]; then
  warn_write "Writing to configuration/credentials file: $FILENAME. Verify this doesn't contain sensitive data that should be in environment variables."
fi

# Warn: Writing to node_modules or vendor directories
if [[ "$FILE_PATH" =~ node_modules/ ]] || [[ "$FILE_PATH" =~ vendor/ ]]; then
  warn_write "Writing to dependency directory ($FILE_PATH). Dependencies should be managed via package manager, not manual file writes."
fi

# Block: Writing files with potential SQL injection patterns
if [[ "$CONTENT" =~ (DROP[[:space:]]+TABLE|DELETE[[:space:]]+FROM.*WHERE[[:space:]]+1=1|TRUNCATE[[:space:]]+TABLE) ]]; then
  block_write "Content contains destructive SQL patterns. Never write files with DROP, unfiltered DELETE, or TRUNCATE statements."
fi

# Add helpful context for test files
if [[ "$FILENAME" =~ \.(test|spec)\.(ts|js|py|go)$ ]]; then
  add_context "📝 Writing test file. Remember to follow TDD principles: write tests before implementation."
fi

# Add context for configuration files
if [[ "$FILENAME" =~ \.(json|yaml|yml|toml)$ ]]; then
  add_context "⚙️ Writing configuration file. Validate syntax and avoid hardcoding secrets."
fi

# Output result
echo "$OUTPUT_JSON"
exit 0
