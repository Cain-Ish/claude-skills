#!/usr/bin/env bash
set -euo pipefail

# Edit validation hook for PreToolUse
# Validates file edits to prevent common mistakes:
# - Editing files with secrets
# - Modifying sensitive system files
# - Breaking critical configuration

# Get hook input from stdin
HOOK_INPUT=$(cat)

# Extract file path from tool input
FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // empty')
OLD_STRING=$(echo "$HOOK_INPUT" | jq -r '.tool_input.old_string // empty')
NEW_STRING=$(echo "$HOOK_INPUT" | jq -r '.tool_input.new_string // empty')

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

# Function to block edit
block_edit() {
  local reason="$1"
  OUTPUT_JSON=$(echo "$OUTPUT_JSON" | jq --arg reason "$reason" '
    .hookSpecificOutput.permissionDecision = "deny" |
    .hookSpecificOutput.permissionDecisionReason = $reason
  ')
  echo "$OUTPUT_JSON"
  exit 0
}

# Function to warn about edit
warn_edit() {
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

# Block: Editing .env files with secrets
if [[ "$FILENAME" == ".env" ]] || [[ "$FILENAME" == .env.* ]]; then
  # Check if the edit involves secret-like patterns
  if echo "$OLD_STRING$NEW_STRING" | grep -qE "(API_KEY|SECRET|PASSWORD|TOKEN|PRIVATE_KEY)="; then
    block_edit "Editing .env file with secrets. Use environment variables or secure vaults. Never commit secrets to version control."
  fi
fi

# Block: Editing system files
if [[ "$FILE_PATH" =~ ^/etc/ ]] || [[ "$FILE_PATH" =~ ^/usr/ ]] || [[ "$FILE_PATH" =~ ^/var/ ]]; then
  block_edit "Attempting to edit system file: $FILE_PATH. This requires elevated privileges and could damage the system."
fi

# Block: Editing .ssh files
if [[ "$FILE_PATH" =~ \.ssh/ ]]; then
  block_edit "Attempting to edit SSH configuration or keys: $FILE_PATH. SSH security settings should be managed manually with extreme care."
fi

# Warn: Editing critical configuration files
if [[ "$FILENAME" =~ ^(package\.json|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Cargo\.lock|go\.mod|go\.sum|requirements\.txt|Pipfile\.lock)$ ]]; then
  warn_edit "Editing critical dependency file: $FILENAME. Manual edits can cause dependency conflicts. Use package manager commands instead."
fi

# Warn: Editing git configuration
if [[ "$FILENAME" =~ ^\.git(config|ignore|attributes)$ ]]; then
  warn_edit "Editing git configuration file: $FILENAME. Ensure changes don't break version control or team workflows."
fi

# Warn: Editing credentials or secrets files
if [[ "$FILENAME" =~ (credentials|secrets)\.(json|yaml|yml|toml)$ ]]; then
  warn_edit "Editing credentials/secrets file: $FILENAME. Verify this doesn't expose sensitive data or break authentication."
fi

# Block: Removing critical security checks
if [[ -n "$OLD_STRING" ]] && echo "$OLD_STRING" | grep -qE "(authenticate|authorize|validate|sanitize|escape|csrf)"; then
  if [[ -z "$NEW_STRING" ]] || ! echo "$NEW_STRING" | grep -qE "(authenticate|authorize|validate|sanitize|escape|csrf)"; then
    warn_edit "Edit appears to remove or weaken security-related code (authentication, authorization, validation). Verify this doesn't introduce vulnerabilities."
  fi
fi

# Block: Introducing potential SQL injection
if [[ -n "$NEW_STRING" ]] && echo "$NEW_STRING" | grep -qE "(DROP[[:space:]]+TABLE|DELETE[[:space:]]+FROM.*WHERE[[:space:]]+1=1|TRUNCATE[[:space:]]+TABLE)"; then
  block_edit "Edit introduces destructive SQL patterns. Never use DROP, unfiltered DELETE, or TRUNCATE statements."
fi

# Warn: Editing production configuration
if [[ "$FILE_PATH" =~ (prod|production)\.(json|yaml|yml|toml|env)$ ]]; then
  warn_edit "Editing production configuration: $FILE_PATH. Changes could impact live systems. Test thoroughly before deployment."
fi

# Warn: Editing database migration files
if [[ "$FILE_PATH" =~ migrations/ ]] && [[ "$FILE_PATH" =~ \.(sql|js|ts|py)$ ]]; then
  # Check if file already exists (editing existing migration)
  if [[ -f "$FILE_PATH" ]]; then
    warn_edit "Editing existing database migration: $FILE_PATH. Modifying applied migrations can corrupt database state. Create a new migration instead."
  fi
fi

# Add helpful context for test files
if [[ "$FILENAME" =~ \.(test|spec)\.(ts|js|py|go)$ ]]; then
  add_context "🧪 Editing test file. Ensure tests still pass after changes."
fi

# Add context for TypeScript/JavaScript files
if [[ "$FILENAME" =~ \.(ts|tsx|js|jsx)$ ]]; then
  add_context "💡 Remember to run type checker and linter after editing."
fi

# Add context for Python files
if [[ "$FILENAME" =~ \.py$ ]]; then
  add_context "🐍 Remember to run type checker (mypy) and linter after editing."
fi

# Output result
echo "$OUTPUT_JSON"
exit 0
