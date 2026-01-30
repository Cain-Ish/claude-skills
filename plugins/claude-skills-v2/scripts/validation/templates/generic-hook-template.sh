#!/usr/bin/env bash
set -euo pipefail

# Generic Hook Template
# Works for SessionStart, SessionEnd, Stop, PreCompact events
# TODO: Replace with your hook logic

# Get hook input from stdin
HOOK_INPUT=$(cat)

# Extract relevant data
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // "unknown"')

# TODO: Implement your hook logic here
# Examples:
#
# SessionStart: Initialize session state, load configuration
# SessionEnd: Save session state, cleanup resources
# Stop: Extract patterns, suggest reflection
# PreCompact: Save state before context compaction

# For SessionStart and other lifecycle hooks, return empty JSON
# (no permissionDecision needed - these are informational)
OUTPUT_JSON='{}'

# Optional: Add additional context if needed
# OUTPUT_JSON=$(echo "$OUTPUT_JSON" | jq --arg ctx "Your context message" '
#   .hookSpecificOutput.additionalContext = $ctx
# ')

# Output result
echo "$OUTPUT_JSON"
exit 0
