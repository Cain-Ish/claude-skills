#!/usr/bin/env bash
set -euo pipefail

# Auto-format hook for PostToolUse
# Runs after Edit/Write tools to automatically format code files
# Executes async to avoid blocking user flow

# Get hook input from stdin
HOOK_INPUT=$(cat)

# Extract file path from tool input
FILE_PATH=$(echo "$HOOK_INPUT" | jq -r '.tool_input.file_path // empty')

# If no file path, exit silently
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Check if file exists
if [[ ! -f "$FILE_PATH" ]]; then
  exit 0
fi

# Get file extension
EXT="${FILE_PATH##*.}"

# Initialize output
OUTPUT_JSON='{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": ""
  }
}'

# Function to update output context
update_context() {
  local message="$1"
  OUTPUT_JSON=$(echo "$OUTPUT_JSON" | jq --arg msg "$message" \
    '.hookSpecificOutput.additionalContext += $msg + "\n"')
}

# Function to run formatter
run_formatter() {
  local cmd="$1"
  local formatter_name="$2"

  if eval "$cmd" 2>&1; then
    update_context "✓ Auto-formatted with $formatter_name"
    return 0
  else
    update_context "⚠️ $formatter_name formatting failed (file may have syntax errors)"
    return 1
  fi
}

# Format based on file type
case "$EXT" in
  ts|tsx|js|jsx)
    # TypeScript/JavaScript formatting
    if command -v prettier &> /dev/null; then
      run_formatter "prettier --write '$FILE_PATH'" "Prettier"
    fi

    # TypeScript type checking (non-blocking)
    if [[ "$EXT" == "ts" || "$EXT" == "tsx" ]]; then
      if command -v tsc &> /dev/null; then
        if tsc --noEmit "$FILE_PATH" 2>&1; then
          update_context "✓ TypeScript type check passed"
        else
          update_context "⚠️ TypeScript type errors detected (run 'tsc --noEmit' for details)"
        fi
      fi
    fi

    # Check for console.log
    if grep -q "console\.log" "$FILE_PATH"; then
      update_context "ℹ️ File contains console.log statements - consider removing before production"
    fi
    ;;

  py)
    # Python formatting
    if command -v black &> /dev/null; then
      run_formatter "black '$FILE_PATH'" "Black"
    fi

    # Python linting (non-blocking)
    if command -v ruff &> /dev/null; then
      if ruff check "$FILE_PATH" 2>&1; then
        update_context "✓ Ruff linting passed"
      else
        update_context "⚠️ Ruff found linting issues"
      fi
    fi

    # Type checking with mypy (non-blocking)
    if command -v mypy &> /dev/null; then
      if mypy "$FILE_PATH" 2>&1; then
        update_context "✓ MyPy type check passed"
      else
        update_context "⚠️ MyPy found type errors"
      fi
    fi
    ;;

  go)
    # Go formatting
    if command -v gofmt &> /dev/null; then
      run_formatter "gofmt -w '$FILE_PATH'" "gofmt"
    fi

    # Go vet (non-blocking)
    if command -v go &> /dev/null; then
      if go vet "$FILE_PATH" 2>&1; then
        update_context "✓ Go vet passed"
      else
        update_context "⚠️ Go vet found issues"
      fi
    fi
    ;;

  rs)
    # Rust formatting
    if command -v rustfmt &> /dev/null; then
      run_formatter "rustfmt '$FILE_PATH'" "rustfmt"
    fi
    ;;

  java)
    # Java formatting (if google-java-format is installed)
    if command -v google-java-format &> /dev/null; then
      run_formatter "google-java-format --replace '$FILE_PATH'" "google-java-format"
    fi
    ;;

  rb)
    # Ruby formatting
    if command -v rubocop &> /dev/null; then
      run_formatter "rubocop --auto-correct '$FILE_PATH'" "RuboCop"
    fi
    ;;

  *)
    # Unknown file type, exit silently
    exit 0
    ;;
esac

# Output JSON result
echo "$OUTPUT_JSON"
exit 0
