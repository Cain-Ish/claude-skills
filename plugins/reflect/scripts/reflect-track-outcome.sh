#!/bin/bash
# ============================================================================
# Reflect Metrics: Track Outcome Event
# ============================================================================
# Logs the outcome of a previous reflect proposal (did it help?)
# Uses shared library for cross-platform compatibility and validation.
# ============================================================================

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/platform.sh"

# Ensure metrics file exists
if [ ! -f "$METRICS_FILE" ]; then
    log_error "Metrics file not found at $METRICS_FILE"
    echo "Run /reflect on a skill first to collect metrics"
    exit 1
fi

# Find most recent proposal for a skill
find_recent_proposal() {
    local skill="$1"
    # Read JSONL file backwards, find first proposal for this skill
    # Skip comment lines (starting with #)
    # Use reverse_file from platform.sh for cross-platform compatibility
    reverse_file "$METRICS_FILE" | grep -v '^#' | grep "\"type\":\"proposal\"" | grep "\"skill\":\"$skill\"" | head -n 1
}

# Extract number from JSON line (simple grep-based extraction)
extract_json_number() {
    local json="$1"
    local field="$2"
    echo "$json" | grep -o "\"$field\":[0-9]*" | cut -d':' -f2
}

# Usage information
usage() {
    cat <<EOF
Usage: $0 SKILL_NAME [OPTIONS]

Track the outcome of a previous reflect proposal.

Arguments:
  SKILL_NAME        Name of the skill (finds most recent proposal)

Options:
  --interactive         Interactive mode (prompts for all inputs)
  --session-id ID       Session ID from proposal (auto-detected if not provided)
  --corrections-now N   Number of corrections in current session (default: 0)
  --satisfaction LEVEL  User satisfaction: positive|neutral|negative (default: neutral)
  --similar-issues BOOL Similar issues recurred: true|false (default: false)
  --helpful BOOL        Were improvements helpful: true|false (required in non-interactive mode)
  --confidence FLOAT    Confidence in assessment 0.0-1.0 (default: 0.5)

Examples:
  $0 frontend-design --helpful true --corrections-now 1 --satisfaction positive
  $0 code-reviewer --helpful false --corrections-now 5 --similar-issues true

EOF
    exit 1
}

# Parse arguments
if [ $# -lt 1 ]; then
    usage
fi

SKILL_NAME="$1"
shift

# Validate skill name
validate_skill_name "$SKILL_NAME" || exit 1

# Defaults
INTERACTIVE=false
SESSION_ID=""
CORRECTIONS_NOW=0
SATISFACTION="neutral"
SIMILAR_ISSUES="false"
HELPFUL=""
CONFIDENCE="0.5"

# Parse optional arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --interactive)
            INTERACTIVE=true
            shift
            ;;
        --session-id)
            SESSION_ID="$2"
            # Validate session ID format
            validate_session_id "$SESSION_ID" || exit 1
            shift 2
            ;;
        --corrections-now)
            CORRECTIONS_NOW="$2"
            # Validate numeric input
            if ! [[ "$CORRECTIONS_NOW" =~ ^[0-9]+$ ]]; then
                log_error "corrections-now must be a non-negative integer"
                exit 1
            fi
            shift 2
            ;;
        --satisfaction)
            SATISFACTION="$2"
            shift 2
            ;;
        --similar-issues)
            SIMILAR_ISSUES="$2"
            shift 2
            ;;
        --helpful)
            HELPFUL="$2"
            shift 2
            ;;
        --confidence)
            CONFIDENCE="$2"
            # Validate confidence is a valid float 0.0-1.0
            if ! [[ "$CONFIDENCE" =~ ^[0-1](\.[0-9]+)?$ ]] && [ "$CONFIDENCE" != "1" ]; then
                log_error "confidence must be a number between 0.0 and 1.0"
                exit 1
            fi
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Interactive prompt helper with cancel support
# Usage: prompt_with_cancel "prompt text" "variable_name" ["default_value"]
# Returns 0 on success, 1 on cancel
prompt_with_cancel() {
    local prompt="$1"
    local default="${2:-}"
    local result

    if [ -n "$default" ]; then
        echo "$prompt (default: $default, or 'q' to cancel)" >&2
    else
        echo "$prompt (or 'q' to cancel)" >&2
    fi
    read -r result

    # Check for cancel
    if [ "${result,,}" = "q" ] || [ "${result,,}" = "quit" ] || [ "${result,,}" = "cancel" ]; then
        echo "Cancelled by user" >&2
        return 1
    fi

    # Use default if empty
    if [ -z "$result" ] && [ -n "$default" ]; then
        result="$default"
    fi

    echo "$result"
    return 0
}

# Interactive mode: prompt for inputs
if [ "$INTERACTIVE" = true ]; then
    echo "═══════════════════════════════════════" >&2
    echo "  Reflect Outcome Tracker (Interactive)" >&2
    echo "═══════════════════════════════════════" >&2
    echo "" >&2
    echo "Tracking outcome for skill: $SKILL_NAME" >&2
    echo "Enter 'q' at any prompt to cancel." >&2
    echo "" >&2

    # Prompt for helpful (required)
    while true; do
        echo "Were the improvements helpful? (yes/no, or 'q' to cancel)" >&2
        read -r helpful_input

        # Check for cancel
        if [ "${helpful_input,,}" = "q" ] || [ "${helpful_input,,}" = "quit" ] || [ "${helpful_input,,}" = "cancel" ]; then
            log_info "Cancelled by user"
            exit 0
        fi

        case "${helpful_input,,}" in
            yes|y)
                HELPFUL="true"
                break
                ;;
            no|n)
                HELPFUL="false"
                break
                ;;
            *)
                echo "Please answer 'yes', 'no', or 'q' to cancel" >&2
                ;;
        esac
    done

    # Prompt for corrections now
    echo "" >&2
    corrections_input=$(prompt_with_cancel "How many corrections occurred in this session?" "0") || exit 0
    if [ -n "$corrections_input" ]; then
        if [[ "$corrections_input" =~ ^[0-9]+$ ]]; then
            CORRECTIONS_NOW="$corrections_input"
        else
            log_warn "Invalid number, using default: 0"
            CORRECTIONS_NOW=0
        fi
    fi

    # Prompt for satisfaction
    echo "" >&2
    satisfaction_input=$(prompt_with_cancel "What was your satisfaction level? (positive/neutral/negative)" "neutral") || exit 0
    if [ -n "$satisfaction_input" ]; then
        case "${satisfaction_input,,}" in
            positive|neutral|negative)
                SATISFACTION="${satisfaction_input,,}"
                ;;
            *)
                log_warn "Invalid value, using default: neutral"
                SATISFACTION="neutral"
                ;;
        esac
    fi

    # Prompt for similar issues
    echo "" >&2
    similar_input=$(prompt_with_cancel "Did similar issues recur? (yes/no)" "no") || exit 0
    case "${similar_input,,}" in
        yes|y)
            SIMILAR_ISSUES="true"
            ;;
        no|n|"")
            SIMILAR_ISSUES="false"
            ;;
        *)
            log_warn "Invalid input, using default: no"
            SIMILAR_ISSUES="false"
            ;;
    esac

    # Prompt for confidence
    echo "" >&2
    confidence_input=$(prompt_with_cancel "Confidence in this assessment? (0.0-1.0)" "0.5") || exit 0
    if [ -n "$confidence_input" ]; then
        if [[ "$confidence_input" =~ ^[0-1](\.[0-9]+)?$ ]] || [ "$confidence_input" = "1" ]; then
            CONFIDENCE="$confidence_input"
        else
            log_warn "Invalid value, using default: 0.5"
            CONFIDENCE="0.5"
        fi
    fi

    echo "" >&2
    echo "────────────────────────────────────────" >&2
fi

# Validate required arguments (skip in interactive mode since we prompted)
if [ "$INTERACTIVE" = false ] && [ -z "$HELPFUL" ]; then
    log_error "--helpful is required in non-interactive mode"
    usage
fi

# Find recent proposal if session ID not provided
if [ -z "$SESSION_ID" ]; then
    RECENT_PROPOSAL=$(find_recent_proposal "$SKILL_NAME")

    if [ -z "$RECENT_PROPOSAL" ]; then
        log_error "No recent proposal found for skill '$SKILL_NAME'"
        echo "Cannot track outcome without a prior proposal." >&2
        exit 1
    fi

    # Extract session ID and corrections count from proposal
    SESSION_ID=$(echo "$RECENT_PROPOSAL" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4)
    CORRECTIONS_BEFORE=$(extract_json_number "$RECENT_PROPOSAL" "corrections")

    log_info "Found proposal: session_id=$SESSION_ID corrections=$CORRECTIONS_BEFORE"
else
    # Manual session ID provided, try to find corrections count
    PROPOSAL=$(grep "\"session_id\":\"$SESSION_ID\"" "$METRICS_FILE" | grep "\"type\":\"proposal\"" | head -n 1)
    if [ -n "$PROPOSAL" ]; then
        CORRECTIONS_BEFORE=$(extract_json_number "$PROPOSAL" "corrections")
    else
        CORRECTIONS_BEFORE=0
        log_warn "Could not find proposal for session $SESSION_ID, using 0 for corrections_before"
    fi
fi

# Validate satisfaction
case "$SATISFACTION" in
    positive|neutral|negative)
        # Valid
        ;;
    *)
        log_error "Invalid satisfaction '$SATISFACTION'"
        echo "Must be one of: positive, neutral, negative" >&2
        exit 1
        ;;
esac

# Validate helpful boolean
case "$HELPFUL" in
    true|false)
        # Valid
        ;;
    *)
        log_error "Invalid helpful value '$HELPFUL'"
        echo "Must be: true or false" >&2
        exit 1
        ;;
esac

# Validate similar_issues boolean
case "$SIMILAR_ISSUES" in
    true|false)
        # Valid
        ;;
    *)
        log_error "Invalid similar_issues value '$SIMILAR_ISSUES'"
        echo "Must be: true or false" >&2
        exit 1
        ;;
esac

# Ensure CORRECTIONS_BEFORE has a valid default
if [ -z "$CORRECTIONS_BEFORE" ]; then
    CORRECTIONS_BEFORE=0
fi

# Build JSON event
TIMESTAMP=$(get_timestamp)

JSON_EVENT=$(cat <<EOF
{"type":"outcome","timestamp":"$TIMESTAMP","session_id":"$SESSION_ID","skill":"$SKILL_NAME","next_session_metrics":{"corrections_before":${CORRECTIONS_BEFORE},"corrections_after":${CORRECTIONS_NOW},"user_satisfaction":"$SATISFACTION","similar_issues":$SIMILAR_ISSUES},"improvement_helpful":$HELPFUL,"confidence":$CONFIDENCE}
EOF
)

# Append to metrics file with file locking (prevents race conditions)
append_jsonl "$JSON_EVENT" "$METRICS_FILE"

log_success "Outcome logged: skill=$SKILL_NAME helpful=$HELPFUL"
