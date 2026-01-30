#!/usr/bin/env bash
set -euo pipefail

# PreCompact hook - Preserve state before context compaction
# Research: https://github.com/affaan-m/everything-claude-code/blob/main/hooks/memory-persistence/pre-compact.sh

CLAUDE_SKILLS_DIR="${HOME}/.claude/claude-skills"
MEMORY_DIR="${CLAUDE_SKILLS_DIR}/memory"
OBSERVATIONS_DIR="${CLAUDE_SKILLS_DIR}/observations"
INSTINCTS_DIR="${CLAUDE_SKILLS_DIR}/instincts"

mkdir -p "$MEMORY_DIR" "$OBSERVATIONS_DIR"

HOOK_INPUT=$(cat)
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // "unknown"')
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // ""')
TRIGGER=$(echo "$HOOK_INPUT" | jq -r '.trigger // "auto"')

OUTPUT_JSON='{
  "hookSpecificOutput": {
    "hookEventName": "PreCompact",
    "additionalContext": ""
  }
}'

update_context() {
  OUTPUT_JSON=$(echo "$OUTPUT_JSON" | jq --arg msg "$1" \
    '.hookSpecificOutput.additionalContext += $msg + "\n"')
}

# 1. Backup transcript
if [[ -f "$TRANSCRIPT_PATH" ]]; then
  BACKUP_FILE="${MEMORY_DIR}/${SESSION_ID}-$(date +%s).transcript"
  cp "$TRANSCRIPT_PATH" "$BACKUP_FILE"
  update_context "💾 Transcript backed up ($TRIGGER compaction)"
fi

# 2. Preserve key decisions/patterns
if [[ -f "$TRANSCRIPT_PATH" ]]; then
  DECISIONS_FILE="${MEMORY_DIR}/${SESSION_ID}-decisions.jsonl"

  # Extract key patterns: decisions, conclusions, important code snippets
  grep -E "(decided|conclusion|key finding|root cause|important)" "$TRANSCRIPT_PATH" 2>/dev/null | \
    head -50 > "${DECISIONS_FILE}.tmp" || true

  if [[ -s "${DECISIONS_FILE}.tmp" ]]; then
    jq -n \
      --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
      --arg session_id "$SESSION_ID" \
      --arg trigger "$TRIGGER" \
      --arg content "$(cat "${DECISIONS_FILE}.tmp")" \
      '{
        timestamp: $timestamp,
        session_id: $session_id,
        trigger: $trigger,
        preserved_content: $content
      }' >> "$DECISIONS_FILE"

    rm "${DECISIONS_FILE}.tmp"
  fi
fi

# 3. Snapshot current instincts state
if [[ -d "$INSTINCTS_DIR" ]]; then
  SNAPSHOT_FILE="${MEMORY_DIR}/${SESSION_ID}-instincts-snapshot.json"

  INSTINCT_COUNT=$(find "$INSTINCTS_DIR" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
  HIGH_CONFIDENCE=$(find "$INSTINCTS_DIR" -name "*.md" -type f -exec grep -l "^confidence: 0\.[789]" {} \; 2>/dev/null | wc -l | tr -d ' ')

  jq -n \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    --arg session_id "$SESSION_ID" \
    --argjson total "$INSTINCT_COUNT" \
    --argjson high_conf "$HIGH_CONFIDENCE" \
    '{
      timestamp: $timestamp,
      session_id: $session_id,
      total_instincts: $total,
      high_confidence_instincts: $high_conf
    }' > "$SNAPSHOT_FILE"

  update_context "📊 Instinct snapshot: $INSTINCT_COUNT total, $HIGH_CONFIDENCE high-confidence"
fi

# 4. Preserve session observations
SESSION_OBS="${OBSERVATIONS_DIR}/sessions/${SESSION_ID}.jsonl"
if [[ -f "$SESSION_OBS" ]]; then
  PRESERVED_OBS="${MEMORY_DIR}/${SESSION_ID}-observations.jsonl"
  cp "$SESSION_OBS" "$PRESERVED_OBS"
fi

# 5. Cleanup old backups (keep last 7 days)
find "$MEMORY_DIR" -name "*.transcript" -mtime +7 -delete 2>/dev/null || true
find "$MEMORY_DIR" -name "*-decisions.jsonl" -mtime +30 -delete 2>/dev/null || true

update_context "✨ Context preserved before compaction"

echo "$OUTPUT_JSON"
exit 0
