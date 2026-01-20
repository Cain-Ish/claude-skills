#!/bin/bash
# ============================================================================
# Reflect Config: Configuration Management
# ============================================================================
# Manages reflect plugin configuration.
# ============================================================================

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# Plugin directory (parent of scripts)
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
DEFAULT_CONFIG="$PLUGIN_DIR/config/default-config.json"

# Usage
usage() {
    cat <<EOF
Usage: $0 <command> [options]

Manage reflect plugin configuration.

Commands:
  init          Initialize config with defaults (creates ~/.claude/reflect-config.json)
  show          Display current configuration
  get <key>     Get a specific config value (e.g., thresholds.consecutiveRejections)
  set <key> <value>  Set a config value
  reset         Reset to default configuration

Examples:
  $0 init
  $0 show
  $0 get thresholds.consecutiveRejections
  $0 set thresholds.consecutiveRejections 5
  $0 reset

EOF
    exit 1
}

# Initialize config
cmd_init() {
    if [ -f "$CONFIG_FILE" ]; then
        log_warn "Configuration file already exists: $CONFIG_FILE"
        read -p "Overwrite with defaults? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Keeping existing configuration"
            return 0
        fi
    fi

    if [ -f "$DEFAULT_CONFIG" ]; then
        cp "$DEFAULT_CONFIG" "$CONFIG_FILE"
        log_success "Configuration initialized: $CONFIG_FILE"
    else
        # Create minimal config if default doesn't exist
        write_json '{
  "thresholds": {
    "consecutiveRejections": 3,
    "outcomeTrackingDays": 7,
    "memoryRetentionDays": 90,
    "metricsRetentionDays": 180
  },
  "display": {
    "colorEnabled": true,
    "verboseMode": false
  }
}' "$CONFIG_FILE"
        log_success "Configuration created: $CONFIG_FILE"
    fi
}

# Show current config
cmd_show() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_warn "No configuration file found"
        echo "Run '$0 init' to create one"
        return 1
    fi

    echo -e "${BOLD}Reflect Configuration${NC}"
    echo "File: $CONFIG_FILE"
    echo ""

    if has_jq; then
        jq '.' "$CONFIG_FILE"
    else
        cat "$CONFIG_FILE"
    fi
}

# Get config value
cmd_get() {
    local key="$1"

    if [ -z "$key" ]; then
        log_error "Key required"
        echo "Usage: $0 get <key>"
        return 1
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        log_warn "No configuration file - using defaults"
        return 1
    fi

    local value=$(extract_json_field "$CONFIG_FILE" "$key")

    if [ -z "$value" ]; then
        log_warn "Key not found: $key"
        return 1
    fi

    echo "$value"
}

# Set config value
cmd_set() {
    local key="$1"
    local value="$2"

    if [ -z "$key" ] || [ -z "$value" ]; then
        log_error "Key and value required"
        echo "Usage: $0 set <key> <value>"
        return 1
    fi

    # Initialize config if it doesn't exist
    if [ ! -f "$CONFIG_FILE" ]; then
        cmd_init
    fi

    # Use Node.js json-utils if jq not available
    if has_jq; then
        # Try to parse value as JSON, otherwise quote as string
        local tmp_file=$(mktemp)
        if echo "$value" | jq '.' >/dev/null 2>&1; then
            # Valid JSON
            jq ".$key = $value" "$CONFIG_FILE" > "$tmp_file" && mv "$tmp_file" "$CONFIG_FILE"
        else
            # String value
            jq ".$key = \"$value\"" "$CONFIG_FILE" > "$tmp_file" && mv "$tmp_file" "$CONFIG_FILE"
        fi
    elif command -v node &>/dev/null; then
        node "$SCRIPT_DIR/lib/json-utils.js" set "$CONFIG_FILE" "$key" "$value"
    else
        log_error "Need jq or node to modify configuration"
        return 1
    fi

    log_success "Set $key = $value"
}

# Reset to defaults
cmd_reset() {
    if [ -f "$CONFIG_FILE" ]; then
        rm "$CONFIG_FILE"
    fi
    cmd_init
    log_success "Configuration reset to defaults"
}

# Main
case "${1:-}" in
    init)
        cmd_init
        ;;
    show)
        cmd_show
        ;;
    get)
        cmd_get "$2"
        ;;
    set)
        cmd_set "$2" "$3"
        ;;
    reset)
        cmd_reset
        ;;
    *)
        usage
        ;;
esac
