#!/bin/bash
# ============================================================================
# Reflect Metrics: Track Proposal Event
# ============================================================================
# Logs a reflect proposal (approved/rejected/modified) to metrics database
# with file locking for concurrent access safety.
# ============================================================================

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/platform.sh"

# Ensure metrics file exists (or create if empty)
if [ ! -f "$METRICS_FILE" ]; then
    if [ -d "$(dirname "$METRICS_FILE")" ]; then
        touch "$METRICS_FILE"
    else
        log_error "Metrics file directory not found: $(dirname "$METRICS_FILE")"
        exit 1
    fi
fi

# Usage information
usage() {
    cat <<EOF
Usage: $0 SKILL_NAME USER_ACTION [OPTIONS]

Track a reflect proposal event to metrics database.

Arguments:
  SKILL_NAME        Name of the skill being reflected on
  USER_ACTION       User's response: approved|rejected|modified|deferred

Options:
  --session-id ID   Session identifier (auto-generated if not provided)
  --session ID      Alias for --session-id
  --corrections N   Number of corrections detected (default: 0)
  --successes N     Number of successes detected (default: 0)
  --edge-cases N    Number of edge cases detected (default: 0)
  --preferences N   Number of preferences detected (default: 0)
  --changes JSON    JSON array of proposed changes
  --modifications TEXT  User's modifications to proposal (if modified)
  --critic-score N  Critic agent score 0-100 (optional, Phase 4)
  --critic-recommendation TEXT  Critic recommendation (APPROVE/REVISE/REJECT, Phase 4)
  --critic-concerns JSON  JSON array of critic concerns (optional, Phase 4)

Examples:
  $0 frontend-design approved --corrections 2 --successes 3
  $0 code-reviewer rejected --corrections 1
  $0 humanlayer modified --corrections 1 --modifications "Changed confidence levels"

EOF
    exit 1
}

# Parse arguments
if [ $# -lt 2 ]; then
    usage
fi

SKILL_NAME="$1"
USER_ACTION="$2"
shift 2

# Defaults
SESSION_ID=$(generate_session_id)
CORRECTIONS=0
SUCCESSES=0
EDGE_CASES=0
PREFERENCES=0
CHANGES_JSON="[]"
MODIFICATIONS=""
CRITIC_SCORE=""
CRITIC_RECOMMENDATION=""
CRITIC_CONCERNS="[]"

# Parse optional arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --session-id|--session)
            SESSION_ID="$2"
            shift 2
            ;;
        --corrections)
            CORRECTIONS="$2"
            shift 2
            ;;
        --successes)
            SUCCESSES="$2"
            shift 2
            ;;
        --edge-cases)
            EDGE_CASES="$2"
            shift 2
            ;;
        --preferences)
            PREFERENCES="$2"
            shift 2
            ;;
        --changes)
            CHANGES_JSON="$2"
            shift 2
            ;;
        --modifications)
            MODIFICATIONS="$2"
            shift 2
            ;;
        --critic-score)
            CRITIC_SCORE="$2"
            shift 2
            ;;
        --critic-recommendation)
            CRITIC_RECOMMENDATION="$2"
            shift 2
            ;;
        --critic-concerns)
            CRITIC_CONCERNS="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

# Validate inputs
validate_skill_name "$SKILL_NAME" || exit 1
validate_action "$USER_ACTION" || exit 1
validate_session_id "$SESSION_ID" || exit 1

# Validate JSON arrays if provided
if [ "$CHANGES_JSON" != "[]" ]; then
    if command -v jq >/dev/null 2>&1; then
        if ! echo "$CHANGES_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
            log_error "Invalid JSON array for --changes parameter"
            exit 1
        fi
    else
        # Basic validation without jq
        if ! [[ "$CHANGES_JSON" =~ ^\[.*\]$ ]]; then
            log_error "Invalid JSON array format for --changes (must start with [ and end with ])"
            exit 1
        fi
    fi
fi

if [ "$CRITIC_CONCERNS" != "[]" ]; then
    if command -v jq >/dev/null 2>&1; then
        if ! echo "$CRITIC_CONCERNS" | jq -e 'type == "array"' >/dev/null 2>&1; then
            log_error "Invalid JSON array for --critic-concerns parameter"
            exit 1
        fi
    else
        # Basic validation without jq
        if ! [[ "$CRITIC_CONCERNS" =~ ^\[.*\]$ ]]; then
            log_error "Invalid JSON array format for --critic-concerns (must start with [ and end with ])"
            exit 1
        fi
    fi
fi

# Build JSON event
TIMESTAMP=$(get_timestamp)

# Validate text inputs for length
validate_text_length "$MODIFICATIONS" "modifications" 5000 || exit 1

# Escape modifications text for JSON using proper escape function
if [ -n "$MODIFICATIONS" ]; then
    MODIFICATIONS_JSON=$(json_string "$MODIFICATIONS")
else
    MODIFICATIONS_JSON="null"
fi

# Prepare critic fields (optional, Phase 4)
CRITIC_FIELDS=""
if [ -n "$CRITIC_SCORE" ]; then
    CRITIC_FIELDS="$CRITIC_FIELDS,\"critic_score\":$CRITIC_SCORE"
fi

if [ -n "$CRITIC_RECOMMENDATION" ]; then
    validate_text_length "$CRITIC_RECOMMENDATION" "critic_recommendation" 2000 || exit 1
    CRITIC_REC_JSON=$(json_string "$CRITIC_RECOMMENDATION")
    CRITIC_FIELDS="$CRITIC_FIELDS,\"critic_recommendation\":$CRITIC_REC_JSON"
fi

if [ "$CRITIC_CONCERNS" != "[]" ]; then
    CRITIC_FIELDS="$CRITIC_FIELDS,\"critic_concerns\":$CRITIC_CONCERNS"
fi

# Create JSON line
JSON_EVENT=$(cat <<EOF
{"type":"proposal","timestamp":"$TIMESTAMP","session_id":"$SESSION_ID","skill":"$SKILL_NAME","signals":{"corrections":$CORRECTIONS,"successes":$SUCCESSES,"edge_cases":$EDGE_CASES,"preferences":$PREFERENCES},"proposal":{"changes":$CHANGES_JSON},"user_action":"$USER_ACTION","modifications":$MODIFICATIONS_JSON$CRITIC_FIELDS}
EOF
)

# Append to metrics file with file locking (prevents race conditions)
append_jsonl "$JSON_EVENT" "$METRICS_FILE"

# Check for consecutive rejections (Factor 9: Compact Errors into Context Window)
if [ "$USER_ACTION" = "rejected" ]; then
    # Get last 5 proposals for this skill using cross-platform reverse
    RECENT_PROPOSALS=$(get_recent_events "$METRICS_FILE" "\"skill\":\"$SKILL_NAME\"" 5 | \
                       grep "\"type\":\"proposal\"")

    # Count consecutive rejections from the end
    CONSECUTIVE_REJECTIONS=0
    while IFS= read -r line; do
        if echo "$line" | grep -q "\"user_action\":\"rejected\""; then
            CONSECUTIVE_REJECTIONS=$((CONSECUTIVE_REJECTIONS + 1))
        else
            # Non-rejection breaks the streak
            break
        fi
    done <<< "$RECENT_PROPOSALS"

    # Auto-pause if threshold reached (configurable via CONSECUTIVE_REJECTION_THRESHOLD)
    if [ "$CONSECUTIVE_REJECTIONS" -ge "$CONSECUTIVE_REJECTION_THRESHOLD" ]; then
        # Create paused skills directory
        mkdir -p "$PAUSED_DIR"

        # Mark skill as paused with timestamp and reason
        PAUSE_FILE="$PAUSED_DIR/$SKILL_NAME.paused"
        PAUSE_JSON="{\"skill\":\"$SKILL_NAME\",\"paused_at\":\"$(get_timestamp)\",\"reason\":\"consecutive_rejections\",\"consecutive_rejections\":$CONSECUTIVE_REJECTIONS,\"session_id\":\"$SESSION_ID\"}"
        write_json "$PAUSE_JSON" "$PAUSE_FILE"

        echo ""  >&2
        log_warn "AUTO-PAUSED: $CONSECUTIVE_REJECTIONS consecutive rejections for skill '$SKILL_NAME'"
        echo "" >&2
        echo "   Why this happened:" >&2
        echo "   • Signal detection may be misinterpreting feedback" >&2
        echo "   • Proposals may be too aggressive or speculative" >&2
        echo "   • The skill may not need changes right now" >&2
        echo "" >&2
        echo "   Reflect has been paused for this skill to prevent wasted effort." >&2
        echo "" >&2
        echo "   Next steps:" >&2
        echo "   1. Run '/reflect stats $SKILL_NAME' to analyze patterns" >&2
        echo "   2. When ready, run '/reflect resume $SKILL_NAME' to re-enable" >&2
        echo "" >&2
    fi
fi

# Output session ID for chaining to outcome tracking
echo "SESSION_ID=$SESSION_ID"
log_info "Proposal logged: skill=$SKILL_NAME action=$USER_ACTION"
