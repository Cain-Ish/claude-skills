#!/usr/bin/env bash
set -euo pipefail

# Stop hook - Extract patterns, trigger cleanup, suggest reflection
# Runs at session end to capture learnings and perform maintenance

# Configuration
CLAUDE_SKILLS_DIR="${HOME}/.claude/claude-skills"
SESSION_STATE_DIR="${CLAUDE_SKILLS_DIR}/session-state"
OBSERVATIONS_DIR="${CLAUDE_SKILLS_DIR}/observations"
METRICS_DIR="${CLAUDE_SKILLS_DIR}/metrics"

# Create directories
mkdir -p "$SESSION_STATE_DIR" "$OBSERVATIONS_DIR" "$METRICS_DIR"

# Get hook input from stdin
HOOK_INPUT=$(cat)

# Extract session info
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // "unknown"')
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // ""')

# Initialize output
OUTPUT_JSON='{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "additionalContext": ""
  }
}'

# Function to update context
update_context() {
  local message="$1"
  OUTPUT_JSON=$(echo "$OUTPUT_JSON" | jq --arg msg "$message" \
    '.hookSpecificOutput.additionalContext += $msg + "\n"')
}

# 1. Analyze session observations
SESSION_OBSERVATIONS="${OBSERVATIONS_DIR}/sessions/${SESSION_ID}.jsonl"
SESSION_WORTHINESS=0

if [[ -f "$SESSION_OBSERVATIONS" ]]; then
  OBSERVATION_COUNT=$(wc -l < "$SESSION_OBSERVATIONS" | tr -d ' ')

  # Calculate session worthiness score (0-100)
  # Factors: observation count, corrections, errors resolved, domains

  # Base score from observation count
  if [[ "$OBSERVATION_COUNT" -gt 50 ]]; then
    SESSION_WORTHINESS=$((SESSION_WORTHINESS + 40))
  elif [[ "$OBSERVATION_COUNT" -gt 20 ]]; then
    SESSION_WORTHINESS=$((SESSION_WORTHINESS + 25))
  elif [[ "$OBSERVATION_COUNT" -gt 10 ]]; then
    SESSION_WORTHINESS=$((SESSION_WORTHINESS + 15))
  fi

  # Check for user corrections (high value)
  CORRECTION_COUNT=$(grep -c '"event_type":"potential_correction"' "$SESSION_OBSERVATIONS" 2>/dev/null || echo 0)
  SESSION_WORTHINESS=$((SESSION_WORTHINESS + CORRECTION_COUNT * 15))

  # Check for errors resolved (medium value)
  ERROR_COUNT=$(grep -c '"event_type":"error_encountered"' "$SESSION_OBSERVATIONS" 2>/dev/null || echo 0)
  SESSION_WORTHINESS=$((SESSION_WORTHINESS + ERROR_COUNT * 10))

  # Check for domain diversity (bonus)
  DOMAIN_COUNT=$(jq -r '.domain' "$SESSION_OBSERVATIONS" 2>/dev/null | sort -u | wc -l | tr -d ' ')
  if [[ "$DOMAIN_COUNT" -gt 3 ]]; then
    SESSION_WORTHINESS=$((SESSION_WORTHINESS + 10))
  fi

  # Cap at 100
  if [[ "$SESSION_WORTHINESS" -gt 100 ]]; then
    SESSION_WORTHINESS=100
  fi

  update_context "📊 Session analysis: $OBSERVATION_COUNT observation(s), worthiness: ${SESSION_WORTHINESS}/100"
fi

# 2. Update session state with final metrics
SESSION_STATE_FILE="${SESSION_STATE_DIR}/${SESSION_ID}.json"
if [[ -f "$SESSION_STATE_FILE" ]]; then
  # Update with final data
  jq --arg end_time "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
     --argjson worthiness "$SESSION_WORTHINESS" \
     --argjson observations "${OBSERVATION_COUNT:-0}" \
     '. + {
       end_time: $end_time,
       worthiness_score: $worthiness,
       observation_count: $observations
     }' "$SESSION_STATE_FILE" > "${SESSION_STATE_FILE}.tmp"
  mv "${SESSION_STATE_FILE}.tmp" "$SESSION_STATE_FILE"
fi

# 3. Suggest pattern extraction if session is valuable
LEARNING_THRESHOLD=60  # Threshold for suggesting /learn

if [[ "$SESSION_WORTHINESS" -ge "$LEARNING_THRESHOLD" ]]; then
  update_context ""
  update_context "💡 This session has valuable patterns (score: ${SESSION_WORTHINESS}/100)"
  update_context "   Consider running: /learn"
  update_context "   This will extract reusable patterns for future sessions"
fi

# 4. Check if cleanup should be triggered
CLEANUP_THRESHOLD=70
SHOULD_CLEANUP=false

# Cleanup triggers
TRIGGERS=()

# Trigger 1: Session completed successfully (worthiness > threshold)
if [[ "$SESSION_WORTHINESS" -ge "$CLEANUP_THRESHOLD" ]]; then
  TRIGGERS+=("session_complete")
fi

# Trigger 2: Check for git commit (indicates work is done)
if [[ -f "$SESSION_OBSERVATIONS" ]]; then
  if grep -q "git commit" "$SESSION_OBSERVATIONS" 2>/dev/null; then
    TRIGGERS+=("git_commit")
  fi
fi

# Trigger 3: Check transcript for completion keywords
if [[ -f "$TRANSCRIPT_PATH" ]]; then
  if grep -qiE "(done|finished|complete|ready)" "$TRANSCRIPT_PATH" 2>/dev/null | tail -20; then
    TRIGGERS+=("completion_keyword")
  fi
fi

# If at least 2 triggers, suggest cleanup
if [[ "${#TRIGGERS[@]}" -ge 2 ]]; then
  SHOULD_CLEANUP=true
fi

# 5. Safety checks before cleanup
BLOCKERS=()

# Blocker 1: Uncommitted changes
if git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null; then
  : # No changes, OK
else
  BLOCKERS+=("uncommitted_changes")
fi

# Blocker 2: Running processes (dev servers, etc.)
if pgrep -f "(npm run dev|pnpm dev|yarn dev)" > /dev/null 2>&1; then
  BLOCKERS+=("dev_server_running")
fi

# Blocker 3: Recent activity (within 5 minutes)
HEARTBEAT_FILE="${CLAUDE_SKILLS_DIR}/heartbeats/${SESSION_ID}"
if [[ -f "$HEARTBEAT_FILE" ]]; then
  LAST_HEARTBEAT=$(cat "$HEARTBEAT_FILE")
  CURRENT_TIME=$(date +%s)
  TIME_SINCE=$((CURRENT_TIME - LAST_HEARTBEAT))

  if [[ "$TIME_SINCE" -lt 300 ]]; then  # 5 minutes
    BLOCKERS+=("recent_activity")
  fi
fi

# 6. Cleanup decision
if [[ "$SHOULD_CLEANUP" == "true" ]] && [[ "${#BLOCKERS[@]}" -eq 0 ]]; then
  update_context ""
  update_context "🧹 Cleanup recommended"
  update_context "   Triggers: ${TRIGGERS[*]}"
  update_context "   Run: /cleanup"
elif [[ "$SHOULD_CLEANUP" == "true" ]] && [[ "${#BLOCKERS[@]}" -gt 0 ]]; then
  update_context ""
  update_context "⚠️ Cleanup suggested but blocked"
  update_context "   Blockers: ${BLOCKERS[*]}"
fi

# 7. Check for instincts ready to evolve
INSTINCTS_DIR="${CLAUDE_SKILLS_DIR}/instincts"
EVOLVE_THRESHOLD=5  # Minimum instincts for evolution

if [[ -d "$INSTINCTS_DIR" ]]; then
  INSTINCT_COUNT=$(find "$INSTINCTS_DIR" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$INSTINCT_COUNT" -ge "$EVOLVE_THRESHOLD" ]]; then
    # Check if we haven't suggested evolution recently
    LAST_EVOLVE_FILE="${METRICS_DIR}/last-evolve-suggestion"
    SUGGEST_EVOLVE=false

    if [[ ! -f "$LAST_EVOLVE_FILE" ]]; then
      SUGGEST_EVOLVE=true
    else
      LAST_EVOLVE=$(cat "$LAST_EVOLVE_FILE")
      CURRENT_TIME=$(date +%s)
      TIME_SINCE=$((CURRENT_TIME - LAST_EVOLVE))

      # Suggest every 7 days (604800 seconds)
      if [[ "$TIME_SINCE" -gt 604800 ]]; then
        SUGGEST_EVOLVE=true
      fi
    fi

    if [[ "$SUGGEST_EVOLVE" == "true" ]]; then
      update_context ""
      update_context "🌱 You have $INSTINCT_COUNT learned instinct(s)"
      update_context "   Consider running: /evolve"
      update_context "   This will cluster related patterns into new skills"

      # Update timestamp
      date +%s > "$LAST_EVOLVE_FILE"
    fi
  fi
fi

# 8. Remove session heartbeat
rm -f "${CLAUDE_SKILLS_DIR}/heartbeats/${SESSION_ID}" 2>/dev/null || true

# 9. Log session metrics
METRICS_LOG="${METRICS_DIR}/sessions.jsonl"
jq -n \
  --arg session_id "$SESSION_ID" \
  --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --argjson worthiness "$SESSION_WORTHINESS" \
  --argjson observations "${OBSERVATION_COUNT:-0}" \
  --arg triggers "$(IFS=,; echo "${TRIGGERS[*]}")" \
  --arg blockers "$(IFS=,; echo "${BLOCKERS[*]}")" \
  '{
    timestamp: $timestamp,
    session_id: $session_id,
    event_type: "session_end",
    worthiness_score: $worthiness,
    observation_count: $observations,
    cleanup_triggers: $triggers,
    cleanup_blockers: $blockers
  }' >> "$METRICS_LOG"

# 10. Final summary
update_context ""
update_context "✨ Session ended"
update_context "   Observations logged for learning"
update_context "   Patterns available for extraction"

# Output result
echo "$OUTPUT_JSON"
exit 0
