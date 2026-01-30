#!/usr/bin/env bash
set -euo pipefail

# SessionEnd hook - Final state save and cleanup

CLAUDE_SKILLS_DIR="${HOME}/.claude/claude-skills"
SESSION_STATE_DIR="${CLAUDE_SKILLS_DIR}/session-state"
LEARNING_DIR="${CLAUDE_SKILLS_DIR}/learning"
METRICS_DIR="${CLAUDE_SKILLS_DIR}/metrics"

mkdir -p "$SESSION_STATE_DIR" "$METRICS_DIR"

HOOK_INPUT=$(cat)
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // "unknown"')

OUTPUT_JSON='{
  "hookSpecificOutput": {
    "hookEventName": "SessionEnd",
    "additionalContext": ""
  }
}'

update_context() {
  OUTPUT_JSON=$(echo "$OUTPUT_JSON" | jq --arg msg "$1" \
    '.hookSpecificOutput.additionalContext += $msg + "\n"')
}

# 1. Finalize session state
SESSION_STATE_FILE="${SESSION_STATE_DIR}/${SESSION_ID}.json"
if [[ -f "$SESSION_STATE_FILE" ]]; then
  jq --arg end_time "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
     '. + { end_time: $end_time, finalized: true }' \
     "$SESSION_STATE_FILE" > "${SESSION_STATE_FILE}.tmp"
  mv "${SESSION_STATE_FILE}.tmp" "$SESSION_STATE_FILE"
fi

# 2. Stop background observer if running
OBSERVER_PID_FILE="${LEARNING_DIR}/observer.pid"
if [[ -f "$OBSERVER_PID_FILE" ]]; then
  PID=$(cat "$OBSERVER_PID_FILE")
  if ps -p "$PID" > /dev/null 2>&1; then
    kill "$PID" 2>/dev/null || true
    update_context "🛑 Stopped background observer"
  fi
  rm -f "$OBSERVER_PID_FILE"
fi

# 3. Archive old session states (keep last 30 days)
find "$SESSION_STATE_DIR" -name "*.json" -mtime +30 -delete 2>/dev/null || true

# 4. Log final metrics
FINAL_METRICS="${METRICS_DIR}/session-end.jsonl"
jq -n \
  --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg session_id "$SESSION_ID" \
  '{
    timestamp: $timestamp,
    session_id: $session_id,
    event_type: "session_finalized"
  }' >> "$FINAL_METRICS"

update_context "✨ Session finalized"

echo "$OUTPUT_JSON"
exit 0
