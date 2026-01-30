#!/usr/bin/env bash
set -euo pipefail

# Background Observer - Continuous learning pattern detection
# Runs in background, analyzes observations every 5 minutes

# Configuration
CLAUDE_SKILLS_DIR="${HOME}/.claude/claude-skills"
OBSERVATIONS_LOG="${CLAUDE_SKILLS_DIR}/observations/observations.jsonl"
INSTINCTS_DIR="${CLAUDE_SKILLS_DIR}/instincts/learned"
LEARNING_DIR="${CLAUDE_SKILLS_DIR}/learning"
LOG_FILE="${LEARNING_DIR}/observer.log"

# Create directories
mkdir -p "$INSTINCTS_DIR" "$LEARNING_DIR"

# Logging function
log() {
  echo "[$(date -u +"%Y-%m-%d %H:%M:%S")] $*" >> "$LOG_FILE"
}

log "Background observer started (PID: $$)"

# Detection interval (seconds)
INTERVAL=${CLAUDE_SKILLS_DETECTION_INTERVAL:-300}  # Default: 5 minutes
log "Detection interval: ${INTERVAL}s"

# Minimum observations required for pattern detection
MIN_OBSERVATIONS=3

# Function to detect patterns
detect_patterns() {
  log "Running pattern detection..."

  # Check if observations exist
  if [[ ! -f "$OBSERVATIONS_LOG" ]]; then
    log "No observations log found"
    return 0
  fi

  # Get observation count
  OBSERVATION_COUNT=$(wc -l < "$OBSERVATIONS_LOG" | tr -d ' ')
  if [[ "$OBSERVATION_COUNT" -lt "$MIN_OBSERVATIONS" ]]; then
    log "Insufficient observations ($OBSERVATION_COUNT < $MIN_OBSERVATIONS)"
    return 0
  fi

  log "Analyzing $OBSERVATION_COUNT observations..."

  # Pattern 1: Repeated tool usage patterns
  # Example: User consistently uses Edit tool with specific file patterns

  # Count tool usage by type
  TOOL_STATS=$(jq -r '.trigger' "$OBSERVATIONS_LOG" 2>/dev/null | sort | uniq -c | sort -rn)

  # Pattern 2: Domain-specific patterns
  # Example: User always runs tests before git commit in testing domain

  # Analyze domain sequences
  DOMAIN_SEQUENCES=$(jq -r '.domain' "$OBSERVATIONS_LOG" 2>/dev/null | \
    awk 'NR>1{print prev,$0} {prev=$0}' | sort | uniq -c | sort -rn | head -5)

  # Pattern 3: User corrections
  # High-value signal: user fixing Claude's output

  CORRECTIONS=$(grep '"event_type":"potential_correction"' "$OBSERVATIONS_LOG" 2>/dev/null || true)
  CORRECTION_COUNT=$(echo "$CORRECTIONS" | grep -c . || echo 0)

  if [[ "$CORRECTION_COUNT" -gt 0 ]]; then
    log "Detected $CORRECTION_COUNT user correction(s)"

    # Analyze corrections for patterns
    while IFS= read -r correction; do
      # Extract domain and context
      DOMAIN=$(echo "$correction" | jq -r '.domain // "general"')
      ACTION=$(echo "$correction" | jq -r '.action // ""')

      # Simple pattern: if we see the same domain corrected multiple times
      DOMAIN_CORRECTIONS=$(echo "$CORRECTIONS" | grep -c "\"domain\":\"$DOMAIN\"" || echo 0)

      if [[ "$DOMAIN_CORRECTIONS" -ge 2 ]]; then
        # Potential instinct: user has preferences in this domain
        INSTINCT_ID="domain-preference-$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-')"
        INSTINCT_FILE="${INSTINCTS_DIR}/${INSTINCT_ID}.md"

        # Check if instinct already exists
        if [[ -f "$INSTINCT_FILE" ]]; then
          # Update confidence (increment by 0.1, max 0.9)
          CURRENT_CONFIDENCE=$(grep "^confidence:" "$INSTINCT_FILE" | awk '{print $2}' || echo 0.3)
          NEW_CONFIDENCE=$(echo "$CURRENT_CONFIDENCE + 0.1" | bc)
          if (( $(echo "$NEW_CONFIDENCE > 0.9" | bc -l) )); then
            NEW_CONFIDENCE=0.9
          fi

          # Update instinct file
          sed -i.bak "s/^confidence: .*/confidence: $NEW_CONFIDENCE/" "$INSTINCT_FILE"
          rm -f "${INSTINCT_FILE}.bak"

          log "Updated instinct: $INSTINCT_ID (confidence: $NEW_CONFIDENCE)"
        else
          # Create new instinct
          create_instinct "$INSTINCT_ID" "$DOMAIN" "$DOMAIN_CORRECTIONS" "0.5"
        fi
      fi
    done <<< "$CORRECTIONS"
  fi

  # Pattern 4: Frequent domain + tool combinations
  # Example: User always uses Edit + TypeScript in code-modification domain

  DOMAIN_TOOL_COMBOS=$(jq -r '"\(.domain):\(.trigger)"' "$OBSERVATIONS_LOG" 2>/dev/null | \
    sort | uniq -c | sort -rn | head -10)

  log "Top domain+tool combinations:"
  echo "$DOMAIN_TOOL_COMBOS" >> "$LOG_FILE"

  # Pattern 5: Temporal patterns (time-based)
  # Example: User always runs tests before commits

  # Get recent observations (last 24 hours)
  CUTOFF_TIME=$(date -u -v-24H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "24 hours ago" +"%Y-%m-%dT%H:%M:%SZ")
  RECENT_OBS=$(jq -r "select(.timestamp >= \"$CUTOFF_TIME\")" "$OBSERVATIONS_LOG" 2>/dev/null | wc -l | tr -d ' ')

  log "Recent observations (24h): $RECENT_OBS"

  log "Pattern detection complete"
}

# Function to create new instinct
create_instinct() {
  local instinct_id="$1"
  local domain="$2"
  local observation_count="$3"
  local confidence="$4"

  local instinct_file="${INSTINCTS_DIR}/${instinct_id}.md"

  log "Creating new instinct: $instinct_id (domain: $domain, confidence: $confidence)"

  cat > "$instinct_file" <<EOF
---
id: $instinct_id
trigger: "when working in $domain domain"
confidence: $confidence
domain: $domain
source: observation
created: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
last_observed: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
observations: $observation_count
---

# ${domain^} Domain Pattern

## Pattern
User has demonstrated consistent preferences in the $domain domain

## Action
Apply learned patterns when working in $domain

## Evidence
- Observed $observation_count instance(s)
- Detected via background pattern analysis

## Confidence Scoring
- Base: 0.3 (initial detection)
- User corrections: +0.2 (explicit signals)
- **Total: $confidence**
EOF

  log "Instinct created: $instinct_file"
}

# Function to decay old instincts
decay_instincts() {
  log "Running instinct confidence decay..."

  # Decay rate per week
  DECAY_RATE=0.05
  ARCHIVE_THRESHOLD=0.25
  CURRENT_TIME=$(date +%s)

  # Find all instinct files
  find "$INSTINCTS_DIR" -name "*.md" -type f 2>/dev/null | while read -r instinct_file; do
    # Get last observed timestamp
    LAST_OBSERVED=$(grep "^last_observed:" "$instinct_file" | awk '{print $2}' || echo "")

    if [[ -z "$LAST_OBSERVED" ]]; then
      continue
    fi

    # Convert to epoch
    LAST_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_OBSERVED" +%s 2>/dev/null || \
                 date -d "$LAST_OBSERVED" +%s 2>/dev/null || echo 0)

    if [[ "$LAST_EPOCH" -eq 0 ]]; then
      continue
    fi

    # Calculate weeks since last observed
    SECONDS_SINCE=$((CURRENT_TIME - LAST_EPOCH))
    WEEKS_SINCE=$(echo "scale=2; $SECONDS_SINCE / 604800" | bc)

    # Calculate decay
    CURRENT_CONFIDENCE=$(grep "^confidence:" "$instinct_file" | awk '{print $2}' || echo 0.3)
    DECAY_AMOUNT=$(echo "scale=2; $WEEKS_SINCE * $DECAY_RATE" | bc)
    NEW_CONFIDENCE=$(echo "$CURRENT_CONFIDENCE - $DECAY_AMOUNT" | bc)

    # Check if below archive threshold
    if (( $(echo "$NEW_CONFIDENCE < $ARCHIVE_THRESHOLD" | bc -l) )); then
      # Archive the instinct
      ARCHIVE_DIR="${CLAUDE_SKILLS_DIR}/instincts/archived"
      mkdir -p "$ARCHIVE_DIR"
      mv "$instinct_file" "$ARCHIVE_DIR/"
      log "Archived instinct: $(basename "$instinct_file") (confidence: $NEW_CONFIDENCE < $ARCHIVE_THRESHOLD)"
    elif (( $(echo "$NEW_CONFIDENCE < $CURRENT_CONFIDENCE" | bc -l) )); then
      # Update confidence
      sed -i.bak "s/^confidence: .*/confidence: $NEW_CONFIDENCE/" "$instinct_file"
      rm -f "${instinct_file}.bak"
      log "Decayed instinct: $(basename "$instinct_file") ($CURRENT_CONFIDENCE -> $NEW_CONFIDENCE)"
    fi
  done

  log "Instinct decay complete"
}

# Main observation loop
ITERATION=0
while true; do
  ITERATION=$((ITERATION + 1))
  log "--- Iteration $ITERATION ---"

  # Run pattern detection
  detect_patterns

  # Run instinct decay (every 10 iterations, ~50 minutes)
  if [[ $((ITERATION % 10)) -eq 0 ]]; then
    decay_instincts
  fi

  # Sleep until next iteration
  log "Sleeping for ${INTERVAL}s..."
  sleep "$INTERVAL"
done
