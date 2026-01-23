#!/bin/bash
# ============================================================================
# Plugin Detector Library
# ============================================================================
# Detects available plugins that can be optimized by self-debugger
# Uses loose coupling - checks for observable data, not hard dependencies
# ============================================================================

# Check if multi-agent plugin is available
has_multi_agent_data() {
    local metrics_file="$HOME/.claude/multi-agent-metrics.jsonl"
    local plugin_dir="$HOME/.claude/plugins/multi-agent"

    [[ -f "$metrics_file" ]] || [[ -d "$plugin_dir" ]]
}

# Check if reflect plugin is available
has_reflect_data() {
    local proposals_file="$HOME/.claude/reflect/proposals.jsonl"
    local metrics_file="$HOME/.claude/reflect/metrics.jsonl"
    local plugin_dir="$HOME/.claude/plugins/reflect"

    [[ -f "$proposals_file" ]] || [[ -f "$metrics_file" ]] || [[ -d "$plugin_dir" ]]
}

# Check if process-janitor plugin is available
has_process_janitor_data() {
    local cleanup_file="$HOME/.claude/process-janitor/cleanup.jsonl"
    local heartbeat_dir="$HOME/.claude/process-janitor/heartbeat"
    local plugin_dir="$HOME/.claude/plugins/process-janitor"

    [[ -f "$cleanup_file" ]] || [[ -d "$heartbeat_dir" ]] || [[ -d "$plugin_dir" ]]
}

# Detect all available plugins
detect_available_plugins() {
    local available=()

    if has_multi_agent_data; then
        available+=("multi-agent")
    fi

    if has_reflect_data; then
        available+=("reflect")
    fi

    if has_process_janitor_data; then
        available+=("process-janitor")
    fi

    echo "${available[@]}"
}

# Get plugin data locations
get_plugin_metrics_path() {
    local plugin_name="$1"

    case "$plugin_name" in
        multi-agent)
            echo "$HOME/.claude/multi-agent-metrics.jsonl"
            ;;
        reflect)
            echo "$HOME/.claude/reflect/proposals.jsonl"
            ;;
        process-janitor)
            echo "$HOME/.claude/process-janitor/cleanup.jsonl"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Check if plugin has minimum samples for analysis
check_minimum_samples() {
    local plugin_name="$1"
    local min_samples="${2:-10}"
    local metrics_path

    metrics_path=$(get_plugin_metrics_path "$plugin_name")

    if [[ -z "$metrics_path" ]] || [[ ! -f "$metrics_path" ]]; then
        return 1
    fi

    local sample_count
    sample_count=$(wc -l < "$metrics_path" | tr -d ' ')

    [[ "$sample_count" -ge "$min_samples" ]]
}

# Display plugin enhancement status
show_plugin_status() {
    echo "Plugin Enhancement Status:"
    echo ""

    if has_multi_agent_data; then
        local count=$(wc -l < "$HOME/.claude/multi-agent-metrics.jsonl" 2>/dev/null | tr -d ' ')
        echo "  ✓ Multi-Agent: Active ($count executions logged)"
        if check_minimum_samples "multi-agent" 20; then
            echo "    → Ready for threshold optimization"
        else
            echo "    → Needs $((20 - count)) more executions for optimization"
        fi
    else
        echo "  ○ Multi-Agent: Not detected"
    fi

    echo ""

    if has_reflect_data; then
        local count=$(wc -l < "$HOME/.claude/reflect/proposals.jsonl" 2>/dev/null | tr -d ' ')
        echo "  ✓ Reflect: Active ($count proposals logged)"
        if check_minimum_samples "reflect" 10; then
            echo "    → Ready for proposal optimization"
        else
            echo "    → Needs $((10 - count)) more proposals for optimization"
        fi
    else
        echo "  ○ Reflect: Not detected"
    fi

    echo ""

    if has_process_janitor_data; then
        echo "  ✓ Process-Janitor: Active"
        echo "    → Monitoring available"
    else
        echo "  ○ Process-Janitor: Not detected"
    fi

    echo ""
    echo "Install and use plugins to enable self-optimization features."
}

# Run optimization for available plugins
optimize_available_plugins() {
    local script_dir="${1:-./scripts}"
    local optimizations_run=0
    local optimizations_available=0

    echo "Checking for optimization opportunities..."
    echo ""

    # Multi-Agent optimization
    if has_multi_agent_data && check_minimum_samples "multi-agent" 20; then
        optimizations_available=$((optimizations_available + 1))
        echo "Running multi-agent threshold analysis..."
        if "$script_dir/detect-multi-agent-thresholds.sh"; then
            optimizations_run=$((optimizations_run + 1))
        fi
        echo ""
    fi

    # Reflect optimization
    if has_reflect_data && check_minimum_samples "reflect" 10; then
        optimizations_available=$((optimizations_available + 1))
        echo "Running reflect proposal analysis..."
        if "$script_dir/detect-reflect-proposals.sh" 2>/dev/null; then
            optimizations_run=$((optimizations_run + 1))
        fi
        echo ""
    fi

    # Summary
    if [[ $optimizations_available -eq 0 ]]; then
        echo "No plugin data available for optimization yet."
        echo ""
        show_plugin_status
    else
        echo "Completed $optimizations_run of $optimizations_available optimization analyses."
    fi
}

# Export functions for use in other scripts
export -f has_multi_agent_data
export -f has_reflect_data
export -f has_process_janitor_data
export -f detect_available_plugins
export -f get_plugin_metrics_path
export -f check_minimum_samples
export -f show_plugin_status
export -f optimize_available_plugins
