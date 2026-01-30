#!/usr/bin/env bash
set -euo pipefail

# Bash feedback hook for PostToolUse
# Provides feedback on bash command execution
# Logs commands for learning engine to detect patterns

# Configuration
CLAUDE_SKILLS_DIR="${HOME}/.claude/claude-skills"
BASH_LOG_DIR="${CLAUDE_SKILLS_DIR}/bash-history"
BASH_LOG="${BASH_LOG_DIR}/bash-commands.jsonl"

# Create directories if they don't exist
mkdir -p "$BASH_LOG_DIR"

# Get hook input from stdin
HOOK_INPUT=$(cat)

# Extract relevant data
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // "unknown"')
TOOL_INPUT=$(echo "$HOOK_INPUT" | jq -r '.tool_input // {}')
TOOL_RESPONSE=$(echo "$HOOK_INPUT" | jq -r '.tool_response // {}')

# Extract bash command
BASH_COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // empty')

# If no command, exit
if [[ -z "$BASH_COMMAND" ]]; then
  exit 0
fi

# Extract exit code and output
EXIT_CODE=0
if echo "$TOOL_RESPONSE" | jq -e '.error' > /dev/null 2>&1; then
  EXIT_CODE=1
fi

# Create bash execution log entry
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BASH_ENTRY=$(jq -n \
  --arg timestamp "$TIMESTAMP" \
  --arg session_id "$SESSION_ID" \
  --arg command "$BASH_COMMAND" \
  --arg exit_code "$EXIT_CODE" \
  --argjson tool_response "$TOOL_RESPONSE" \
  '{
    timestamp: $timestamp,
    session_id: $session_id,
    command: $command,
    exit_code: ($exit_code | tonumber),
    tool_response: $tool_response,
    execution_type: "bash_command"
  }')

# Append to bash log
echo "$BASH_ENTRY" >> "$BASH_LOG"

# Keep bash log manageable (last 1,000 entries)
if [[ -f "$BASH_LOG" ]]; then
  LINE_COUNT=$(wc -l < "$BASH_LOG")
  if (( LINE_COUNT > 1000 )); then
    tail -1000 "$BASH_LOG" > "${BASH_LOG}.tmp"
    mv "${BASH_LOG}.tmp" "$BASH_LOG"
  fi
fi

# Generate feedback based on command patterns
FEEDBACK=""

# Detect common command patterns for learning
if echo "$BASH_COMMAND" | grep -qE "^git "; then
  # Git commands
  if [[ $EXIT_CODE -eq 0 ]]; then
    if echo "$BASH_COMMAND" | grep -qE "git commit"; then
      FEEDBACK="✅ Git commit successful. Remember to push when ready."
    elif echo "$BASH_COMMAND" | grep -qE "git push"; then
      FEEDBACK="🚀 Code pushed to remote repository."
    elif echo "$BASH_COMMAND" | grep -qE "git pull"; then
      FEEDBACK="⬇️ Remote changes pulled successfully."
    fi
  else
    if echo "$BASH_COMMAND" | grep -qE "git commit"; then
      FEEDBACK="⚠️ Git commit failed. Check pre-commit hooks or ensure files are staged."
    elif echo "$BASH_COMMAND" | grep -qE "git push"; then
      FEEDBACK="⚠️ Git push failed. You may need to pull remote changes first."
    fi
  fi
fi

if echo "$BASH_COMMAND" | grep -qE "(npm|pnpm|yarn|bun) "; then
  # Package manager commands
  if [[ $EXIT_CODE -eq 0 ]]; then
    if echo "$BASH_COMMAND" | grep -qE "(install|add)"; then
      FEEDBACK="📦 Package(s) installed successfully. Lockfile updated."
    elif echo "$BASH_COMMAND" | grep -qE "(run |)test"; then
      FEEDBACK="✅ Tests completed successfully."
    elif echo "$BASH_COMMAND" | grep -qE "(run |)build"; then
      FEEDBACK="🏗️ Build completed successfully."
    fi
  else
    if echo "$BASH_COMMAND" | grep -qE "(install|add)"; then
      FEEDBACK="⚠️ Package installation failed. Check package name and version compatibility."
    elif echo "$BASH_COMMAND" | grep -qE "(run |)test"; then
      FEEDBACK="❌ Tests failed. Review test output for details."
    elif echo "$BASH_COMMAND" | grep -qE "(run |)build"; then
      FEEDBACK="❌ Build failed. Review error messages and fix syntax/type errors."
    fi
  fi
fi

if echo "$BASH_COMMAND" | grep -qE "docker "; then
  # Docker commands
  if [[ $EXIT_CODE -eq 0 ]]; then
    if echo "$BASH_COMMAND" | grep -qE "docker build"; then
      FEEDBACK="🐳 Docker image built successfully."
    elif echo "$BASH_COMMAND" | grep -qE "docker run"; then
      FEEDBACK="🐳 Docker container started."
    fi
  else
    FEEDBACK="⚠️ Docker command failed. Check Docker daemon is running and command syntax."
  fi
fi

if echo "$BASH_COMMAND" | grep -qE "(pytest|python -m pytest)"; then
  # Python testing
  if [[ $EXIT_CODE -eq 0 ]]; then
    FEEDBACK="✅ Python tests passed."
  else
    FEEDBACK="❌ Python tests failed. Review pytest output for failure details."
  fi
fi

if echo "$BASH_COMMAND" | grep -qE "go test"; then
  # Go testing
  if [[ $EXIT_CODE -eq 0 ]]; then
    FEEDBACK="✅ Go tests passed."
  else
    FEEDBACK="❌ Go tests failed. Review test output for failure details."
  fi
fi

if echo "$BASH_COMMAND" | grep -qE "cargo "; then
  # Rust cargo commands
  if [[ $EXIT_CODE -eq 0 ]]; then
    if echo "$BASH_COMMAND" | grep -qE "cargo build"; then
      FEEDBACK="🦀 Rust build completed successfully."
    elif echo "$BASH_COMMAND" | grep -qE "cargo test"; then
      FEEDBACK="✅ Rust tests passed."
    fi
  else
    if echo "$BASH_COMMAND" | grep -qE "cargo build"; then
      FEEDBACK="❌ Rust build failed. Review compiler errors."
    elif echo "$BASH_COMMAND" | grep -qE "cargo test"; then
      FEEDBACK="❌ Rust tests failed."
    fi
  fi
fi

# Return PostToolUse output with feedback
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
