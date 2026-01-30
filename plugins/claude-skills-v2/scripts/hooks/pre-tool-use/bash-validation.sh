#!/usr/bin/env bash
set -euo pipefail

# Bash validation hook for PreToolUse
# Validates bash commands before execution to prevent common mistakes

# Get hook input from stdin
HOOK_INPUT=$(cat)

# Extract bash command from tool input
BASH_COMMAND=$(echo "$HOOK_INPUT" | jq -r '.tool_input.command // empty')

# If no command, exit
if [[ -z "$BASH_COMMAND" ]]; then
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

# Function to block command
block_command() {
  local reason="$1"
  OUTPUT_JSON=$(echo "$OUTPUT_JSON" | jq --arg reason "$reason" '
    .hookSpecificOutput.permissionDecision = "deny" |
    .hookSpecificOutput.permissionDecisionReason = $reason
  ')
  echo "$OUTPUT_JSON"
  exit 0
}

# Function to warn about command
warn_command() {
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

# Check for dev servers outside tmux
if echo "$BASH_COMMAND" | grep -qE "(npm|pnpm|yarn|bun) (run )?dev"; then
  if [[ -z "${TMUX:-}" ]]; then
    warn_command "Dev servers should run in tmux for log access and session persistence. Run 'tmux new -s dev' first, or use 'tmux attach' to attach to existing session."
  fi
fi

# Check for git push
if echo "$BASH_COMMAND" | grep -qE "^git push"; then
  # Check if there are uncommitted changes
  if git diff --quiet && git diff --cached --quiet 2>/dev/null; then
    add_context "💡 Reminder: Review 'git log' to verify commits before pushing"
  else
    warn_command "You have uncommitted changes. Review changes with 'git status' and 'git diff' before pushing."
  fi
fi

# Check for force push to main/master
if echo "$BASH_COMMAND" | grep -qE "git push.*(--force|-f)"; then
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" ]]; then
    block_command "Force push to main/master is extremely dangerous. Create a new branch or use --force-with-lease if you're absolutely certain."
  else
    warn_command "Force push detected. This rewrites history. Confirm you've coordinated with your team."
  fi
fi

# Check for destructive rm commands
if echo "$BASH_COMMAND" | grep -qE "rm\s+(-rf|-fr|-r\s+-f|-f\s+-r)"; then
  # Check if it's removing common safe patterns
  if ! echo "$BASH_COMMAND" | grep -qE "(node_modules|dist|build|\.next|target|__pycache__|\.pytest_cache)"; then
    warn_command "Destructive 'rm -rf' command detected. Verify the target path is correct: $BASH_COMMAND"
  fi
fi

# Check for commands that modify package.json
if echo "$BASH_COMMAND" | grep -qE "(npm|pnpm|yarn|bun) (install|add|remove)"; then
  add_context "📦 Package manager operation detected. This will modify package.json and lockfile."
fi

# Check for sudo commands
if echo "$BASH_COMMAND" | grep -qE "^sudo "; then
  warn_command "Command requires sudo privileges. Verify this is necessary and safe."
fi

# Check for pipe to shell from curl/wget
if echo "$BASH_COMMAND" | grep -qE "(curl|wget).*\|\s*(bash|sh)"; then
  warn_command "Piping untrusted remote scripts directly to shell is dangerous. Download first, inspect, then execute."
fi

# Check for > redirection to important files
if echo "$BASH_COMMAND" | grep -qE ">\s*(/etc/|~/.ssh/|~/.bashrc|~/.zshrc|package\.json)"; then
  warn_command "Command redirects output to important system/config file. This could overwrite critical configuration."
fi

# Check for database commands
if echo "$BASH_COMMAND" | grep -qE "(DROP DATABASE|DROP TABLE|TRUNCATE|DELETE FROM.*WHERE 1=1)"; then
  block_command "Destructive database command detected. Never run DROP, TRUNCATE, or unfiltered DELETE in production."
fi

# Output result
echo "$OUTPUT_JSON"
exit 0
