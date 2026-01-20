#!/bin/bash
# ============================================================================
# Reflect Command Script
# ============================================================================
# Handles: on, off, status, stats, validate, resume, analyze-all, cleanup,
#          analyze-effectiveness, improve, reflect subcommands
# ============================================================================

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/platform.sh"

# Plugin directory (parent of scripts)
CLAUDE_DIR="$(dirname "$SCRIPT_DIR")"
SKILLS_DIR="$CLAUDE_DIR/skills"

# Optional: Log invocations for debugging (with log rotation)
if [ "${DEBUG_REFLECT:-0}" = "1" ]; then
    LOG_FILE="$REFLECT_HOME/reflect.log"
    echo "$(date) - Args: $*" >> "$LOG_FILE"
    # Keep only last 1000 lines to prevent unbounded growth
    tail -n 1000 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
fi

# Enable auto-reflect
reflect_on() {
    local timestamp=$(get_timestamp)
    local json="{\"enabled\":true,\"updatedAt\":\"$timestamp\"}"
    write_json "$json" "$STATE_FILE"
    log_success "Auto-reflect enabled"
    echo "Sessions will be analyzed automatically when you stop."
    log_debug "State saved to: $STATE_FILE"
}

# Disable auto-reflect
reflect_off() {
    local timestamp=$(get_timestamp)
    local json="{\"enabled\":false,\"updatedAt\":\"$timestamp\"}"
    write_json "$json" "$STATE_FILE"
    log_success "Auto-reflect disabled"
    echo "Use \`/reflect\` manually to analyze sessions."
}

# Check auto-reflect status
reflect_status() {
    if [ -f "$STATE_FILE" ]; then
        local enabled=$(extract_json_bool "$STATE_FILE" "enabled")
        local updated=$(extract_json_field "$STATE_FILE" "updatedAt")

        if [ "$enabled" = "true" ]; then
            echo -e "${GREEN}●${NC} Auto-reflect is ${BOLD}enabled${NC}"
            echo "  Last updated: $updated"
        else
            echo -e "${YELLOW}○${NC} Auto-reflect is ${BOLD}disabled${NC}"
            echo "  Last updated: $updated"
        fi

        # Show paused skills if any
        if [ -d "$PAUSED_DIR" ] && [ -n "$(ls -A "$PAUSED_DIR" 2>/dev/null)" ]; then
            echo ""
            echo -e "${YELLOW}Paused skills:${NC}"
            for pause_file in "$PAUSED_DIR"/*.paused; do
                if [ -f "$pause_file" ]; then
                    local skill_name=$(basename "$pause_file" .paused)
                    echo "  - $skill_name"
                fi
            done
        fi
    else
        echo -e "${DIM}○${NC} Auto-reflect is not configured"
        echo "  Run \`/reflect on\` to enable."
    fi
}

# Main command handler
case "$1" in
    on)
        reflect_on
        ;;
    off)
        reflect_off
        ;;
    status)
        reflect_status
        ;;
    stats)
        # Show effectiveness metrics
        shift  # Remove 'stats' from args
        "$CLAUDE_DIR/scripts/reflect-stats.sh" "$@"
        ;;
    validate)
        # Validate if recent improvements helped
        shift  # Remove 'validate' from args
        SKILL="${1:-}"
        if [ -z "$SKILL" ]; then
            echo "Usage: /reflect validate [skill-name]"
            echo "Example: /reflect validate frontend-design"
            exit 1
        fi
        # Run outcome tracking script interactively
        "$CLAUDE_DIR/scripts/reflect-track-outcome.sh" "$SKILL"
        ;;
    resume)
        # Resume a paused skill
        shift  # Remove 'resume' from args
        SKILL="${1:-}"
        if [ -z "$SKILL" ]; then
            echo "Usage: /reflect resume [skill-name]"
            echo "Example: /reflect resume frontend-design"
            echo ""
            echo "Paused skills:"
            if [ -d "$PAUSED_DIR" ] && [ -n "$(ls -A "$PAUSED_DIR" 2>/dev/null)" ]; then
                for pause_file in "$PAUSED_DIR"/*.paused; do
                    if [ -f "$pause_file" ]; then
                        skill_name=$(basename "$pause_file" .paused)
                        paused_at=$(extract_json_field "$pause_file" "paused_at")
                        reason=$(extract_json_field "$pause_file" "reason")
                        echo "  - $skill_name (paused: $paused_at, reason: $reason)"
                    fi
                done
            else
                echo "  No paused skills found."
            fi
            exit 1
        fi

        # Validate skill name
        validate_skill_name "$SKILL" || exit 1

        PAUSE_FILE="$PAUSED_DIR/$SKILL.paused"

        if [ ! -f "$PAUSE_FILE" ]; then
            log_error "Skill '$SKILL' is not paused"
            echo "Run '/reflect resume' with no args to see paused skills."
            exit 1
        fi

        # Read pause info
        paused_at=$(extract_json_field "$PAUSE_FILE" "paused_at")
        reason=$(extract_json_field "$PAUSE_FILE" "reason")

        # Remove pause file
        rm "$PAUSE_FILE"

        log_success "Resumed skill: $SKILL"
        echo "  Was paused at: $paused_at"
        echo "  Reason: $reason"
        echo ""
        echo "Reflect is now active again for this skill."
        ;;
    analyze-all)
        # Batch analysis across all skills
        shift  # Remove 'analyze-all' from args
        "$CLAUDE_DIR/scripts/reflect-analyze-all.sh" "$@"
        ;;
    cleanup)
        # Run memory and metrics cleanup
        shift  # Remove 'cleanup' from args
        "$CLAUDE_DIR/scripts/reflect-cleanup-memories.sh" "$@"
        ;;
    config)
        # Configuration management
        shift  # Remove 'config' from args
        "$CLAUDE_DIR/scripts/reflect-config.sh" "$@"
        ;;
    analyze-effectiveness)
        # Analyze effectiveness and generate report
        shift  # Remove 'analyze-effectiveness' from args
        "$CLAUDE_DIR/scripts/reflect-analyze-effectiveness.sh" "$@"
        ;;
    improve)
        # Systematic self-improvement workflow
        echo "=== Reflect Self-Improvement Workflow ===" >&2
        echo "" >&2
        echo "Step 1: Analyzing effectiveness metrics..." >&2
        echo "" >&2

        # Run effectiveness analysis
        "$CLAUDE_DIR/scripts/reflect-analyze-effectiveness.sh"

        echo "" >&2
        echo "Step 2: Triggering reflect skill on itself..." >&2
        echo "The analysis above will inform proposed improvements." >&2
        echo "" >&2

        # Trigger reflect skill targeting itself
        echo "REFLECT_SKILL:reflect"
        ;;
    reflect)
        # Meta-improvement: reflect on reflect
        # Trigger reflect skill workflow targeting itself
        echo "REFLECT_SKILL:reflect"
        ;;
    *)
        # For empty args or skill name
        if [ -n "$1" ]; then
            # Skill name explicitly provided - validate and trigger
            if validate_skill_name "$1" 2>/dev/null; then
                echo "REFLECT_SKILL:$1"
            else
                log_error "Invalid skill name: $1"
                exit 1
            fi
        elif [ -f "$STATE_FILE" ]; then
            # No skill name, check if auto-reflect is enabled
            enabled=$(extract_json_bool "$STATE_FILE" "enabled")
            if [ "$enabled" = "true" ]; then
                # Auto-reflect is enabled - trigger reflect skill without specific skill name
                log_debug "Auto-reflect enabled, triggering analysis"
                echo "REFLECT_SKILL:"
            else
                # Auto-reflect disabled and no skill specified - just trigger with no args
                log_debug "Auto-reflect disabled, triggering manual analysis"
                echo "REFLECT_SKILL:"
            fi
        else
            # No state file exists - trigger reflect skill anyway
            log_debug "No state file, triggering analysis"
            echo "REFLECT_SKILL:"
        fi
        ;;
esac