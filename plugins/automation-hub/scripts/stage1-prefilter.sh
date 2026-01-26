#!/usr/bin/env bash
# Stage 1 Pre-Filter: Fast complexity detection (<100ms, <100 tokens)
# Checks 5 signals, scores 0-10, threshold ≥4 proceeds to Stage 2

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Input ===
# $1: prompt text
# $2: token budget (from context)
# $3: tool name being invoked

PROMPT="${1:-}"
TOKEN_BUDGET="${2:-0}"
TOOL_NAME="${3:-}"

# === Signal Detection ===

score=0
signals=()

debug "Stage 1 Pre-Filter: Analyzing prompt for multi-agent routing"

# Signal 1: Token Budget (>30K suggests complex task)
if [[ ${TOKEN_BUDGET} -gt 30000 ]]; then
    ((score++))
    signals+=("token_budget")
    debug "  ✓ Token budget signal: YES (${TOKEN_BUDGET} tokens)"
else
    debug "  ✗ Token budget signal: NO (${TOKEN_BUDGET} tokens)"
fi

# Signal 2: Keyword Density (3+ domain-specific words)
domain_keywords=(
    "architecture" "microservices" "distributed" "scalability" "performance"
    "security" "authentication" "authorization" "encryption" "vulnerability"
    "database" "migration" "schema" "optimization" "indexing"
    "testing" "integration" "end-to-end" "coverage" "mocking"
    "deployment" "ci/cd" "pipeline" "kubernetes" "docker"
    "refactor" "design pattern" "framework" "api" "backend" "frontend"
    "async" "concurrency" "parallel" "thread" "queue"
    "monitoring" "logging" "observability" "tracing" "metrics"
)

keyword_count=0
for keyword in "${domain_keywords[@]}"; do
    if echo "${PROMPT}" | grep -qi "\b${keyword}\b"; then
        ((keyword_count++))
    fi
done

if [[ ${keyword_count} -ge 3 ]]; then
    ((score += 2))
    signals+=("keyword_density:${keyword_count}")
    debug "  ✓ Keyword density: ${keyword_count} matches → YES"
else
    debug "  ✗ Keyword density: ${keyword_count} matches → NO"
fi

# Signal 3: Multi-Domain Detection (crosses technical boundaries)
domains_mentioned=0

if echo "${PROMPT}" | grep -Eqi "\b(frontend|ui|react|vue|angular|css|html)\b"; then
    ((domains_mentioned++))
fi
if echo "${PROMPT}" | grep -Eqi "\b(backend|api|server|database|sql|nosql)\b"; then
    ((domains_mentioned++))
fi
if echo "${PROMPT}" | grep -Eqi "\b(devops|deploy|ci/cd|docker|kubernetes|aws|gcp)\b"; then
    ((domains_mentioned++))
fi
if echo "${PROMPT}" | grep -Eqi "\b(security|auth|encrypt|vulnerability|penetration)\b"; then
    ((domains_mentioned++))
fi
if echo "${PROMPT}" | grep -Eqi "\b(testing|test|qa|e2e|integration|unit)\b"; then
    ((domains_mentioned++))
fi

if [[ ${domains_mentioned} -ge 2 ]]; then
    ((score += 2))
    signals+=("multi_domain:${domains_mentioned}")
    debug "  ✓ Multi-domain: ${domains_mentioned} domains → YES"
else
    debug "  ✗ Multi-domain: ${domains_mentioned} domains → NO"
fi

# Signal 4: Explicit Complexity Words
complexity_words=(
    "complex" "comprehensive" "complete" "full" "entire" "whole"
    "implement" "build" "create" "design" "architect"
    "migrate" "refactor" "redesign" "overhaul" "modernize"
    "system" "platform" "infrastructure" "ecosystem"
    "multiple" "several" "various" "different" "across"
)

complexity_count=0
for word in "${complexity_words[@]}"; do
    if echo "${PROMPT}" | grep -qi "\b${word}\b"; then
        ((complexity_count++))
    fi
done

if [[ ${complexity_count} -ge 2 ]]; then
    ((score += 2))
    signals+=("complexity_words:${complexity_count}")
    debug "  ✓ Complexity words: ${complexity_count} matches → YES"
else
    debug "  ✗ Complexity words: ${complexity_count} matches → NO"
fi

# Signal 5: Prompt Length (>200 words suggests detailed requirements)
word_count=$(echo "${PROMPT}" | wc -w | tr -d ' ')

if [[ ${word_count} -gt 200 ]]; then
    ((score++))
    signals+=("prompt_length:${word_count}")
    debug "  ✓ Prompt length: ${word_count} words → YES"
else
    debug "  ✗ Prompt length: ${word_count} words → NO"
fi

# === Decision ===

threshold=$(get_config_value ".auto_routing.stage1_threshold" "4")

debug "  Stage 1 score: ${score}/${threshold} (signals: ${signals[*]:-none})"

if [[ ${score} -ge ${threshold} ]]; then
    debug "  → PROCEED TO STAGE 2"
    echo "proceed"
    exit 0
else
    debug "  → SKIP (below threshold)"
    echo "skip"
    exit 0
fi
