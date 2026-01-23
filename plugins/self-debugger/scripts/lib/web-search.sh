#!/bin/bash
# ============================================================================
# Self-Debugger Plugin - Web Search Utilities
# ============================================================================
# Wrapper functions for WebSearch and WebFetch tools to discover plugin
# best practices, patterns, and documentation from the web.
#
# Source this file after common.sh:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/web-search.sh"
# ============================================================================

set -euo pipefail

# ============================================================================
# Web Search Results Storage
# ============================================================================

WEB_SEARCH_CACHE="$DEBUGGER_HOME/web-search-cache"

# Store web search results
# Usage: store_search_results "$query" "$results_json"
store_search_results() {
    local query="$1"
    local results_json="$2"

    mkdir -p "$WEB_SEARCH_CACHE"

    # Create filename from query (sanitize)
    local filename
    filename=$(echo "$query" | tr ' ' '-' | tr -cd '[:alnum:]-' | tr '[:upper:]' '[:lower:]')
    local cache_file="$WEB_SEARCH_CACHE/${filename}.json"

    # Store with timestamp
    local cache_entry
    cache_entry=$(cat <<EOF
{
  "query": "$query",
  "timestamp": "$(get_timestamp)",
  "results": $results_json
}
EOF
)

    write_json "$cache_entry" "$cache_file"
    log_debug "Cached search results: $cache_file"
}

# Check if search results are cached and fresh
# Usage: get_cached_results "$query" "$max_age_days"
get_cached_results() {
    local query="$1"
    local max_age_days="${2:-7}"  # Default 7 days

    local filename
    filename=$(echo "$query" | tr ' ' '-' | tr -cd '[:alnum:]-' | tr '[:upper:]' '[:lower:]')
    local cache_file="$WEB_SEARCH_CACHE/${filename}.json"

    if [[ ! -f "$cache_file" ]]; then
        echo ""
        return 1
    fi

    # Check cache age
    local cache_timestamp
    cache_timestamp=$(extract_json_field "$cache_file" "timestamp" 2>/dev/null || echo "")

    if [[ -z "$cache_timestamp" ]]; then
        echo ""
        return 1
    fi

    local cache_age_seconds
    cache_age_seconds=$(get_age_seconds "$cache_timestamp")
    local cache_age_days=$((cache_age_seconds / 86400))

    if [[ $cache_age_days -gt $max_age_days ]]; then
        log_debug "Cache expired (age: ${cache_age_days} days)"
        echo ""
        return 1
    fi

    # Return cached results
    if has_jq; then
        jq -c '.results' "$cache_file" 2>/dev/null || echo ""
    else
        cat "$cache_file"
    fi
}

# ============================================================================
# Web Search Patterns
# ============================================================================

# Search for Claude Code plugin best practices
# Returns: JSON array of URLs and snippets
search_plugin_best_practices() {
    local year="${1:-2026}"

    local query="Claude Code plugin best practices $year"

    # Check cache first
    local cached_results
    cached_results=$(get_cached_results "$query" 7)

    if [[ -n "$cached_results" ]]; then
        log_info "Using cached search results for: $query"
        echo "$cached_results"
        return 0
    fi

    # AIDEV-NOTE: WebSearch tool integration pending
    # This will use Claude Code's WebSearch tool when available
    log_warn "WebSearch tool not yet integrated"
    log_info "Would search for: $query"

    # Placeholder results
    local placeholder_results
    placeholder_results=$(cat <<'EOF'
[
  {
    "url": "https://docs.anthropic.com/claude-code/plugins",
    "title": "Claude Code Plugin Development Guide",
    "snippet": "Official documentation for creating Claude Code plugins"
  },
  {
    "url": "https://github.com/anthropics/claude-code/wiki/Plugin-Best-Practices",
    "title": "Plugin Best Practices - GitHub Wiki",
    "snippet": "Community-maintained best practices for plugin development"
  }
]
EOF
)

    # Cache placeholder results
    store_search_results "$query" "$placeholder_results"

    echo "$placeholder_results"
}

# Search for specific pattern examples
# Usage: search_pattern_examples "hook frontmatter yaml"
search_pattern_examples() {
    local pattern="$1"

    local query="Claude Code plugin $pattern example 2026"

    # Check cache
    local cached_results
    cached_results=$(get_cached_results "$query" 7)

    if [[ -n "$cached_results" ]]; then
        echo "$cached_results"
        return 0
    fi

    log_warn "WebSearch tool not yet integrated"
    log_info "Would search for: $query"

    # Return empty results
    echo "[]"
}

# ============================================================================
# Web Fetch Utilities
# ============================================================================

# Fetch content from URL and extract relevant information
# Usage: fetch_and_extract "$url" "$pattern_to_find"
fetch_and_extract() {
    local url="$1"
    local pattern="${2:-}"

    # AIDEV-NOTE: WebFetch tool integration pending
    log_warn "WebFetch tool not yet integrated"
    log_info "Would fetch: $url"

    if [[ -n "$pattern" ]]; then
        log_info "Would extract pattern: $pattern"
    fi

    # Return empty for now
    echo ""
}

# ============================================================================
# Pattern Extraction
# ============================================================================

# Extract code patterns from web content
# Usage: extract_code_patterns "$web_content"
extract_code_patterns() {
    local content="$1"

    # Look for markdown code blocks
    local patterns
    patterns=$(echo "$content" | grep -A 10 '```' | grep -B 10 '```' || echo "")

    if [[ -n "$patterns" ]]; then
        log_debug "Found code patterns in content"
        echo "$patterns"
    else
        echo ""
    fi
}

# ============================================================================
# URL Validation
# ============================================================================

# Check if URL is from official sources
# Usage: is_official_source "$url"
is_official_source() {
    local url="$1"

    # Official sources for Claude Code
    local official_domains=(
        "docs.anthropic.com"
        "github.com/anthropics"
        "claude.ai"
    )

    for domain in "${official_domains[@]}"; do
        if [[ "$url" =~ $domain ]]; then
            return 0  # Is official
        fi
    done

    return 1  # Not official
}

# Calculate confidence score for web-discovered patterns
# Usage: calculate_web_confidence "$url" "$has_code_examples"
calculate_web_confidence() {
    local url="$1"
    local has_code_examples="${2:-false}"

    local confidence="0.5"  # Default medium confidence

    # Increase confidence for official sources
    if is_official_source "$url"; then
        confidence="0.8"
    fi

    # Increase confidence if includes code examples
    if [[ "$has_code_examples" == "true" ]]; then
        confidence=$(echo "$confidence + 0.1" | bc 2>/dev/null || echo "$confidence")
    fi

    # Clamp to max 0.95 (never full confidence for web sources)
    if (( $(echo "$confidence > 0.95" | bc -l 2>/dev/null || echo "0") )); then
        confidence="0.95"
    fi

    echo "$confidence"
}
