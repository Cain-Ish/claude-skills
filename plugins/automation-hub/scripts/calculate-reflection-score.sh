#!/usr/bin/env bash
# Calculate reflection worthiness score from session signals

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# === Load Signal Weights ===

weight_corrections=$(get_config_value ".auto_reflect.signal_weights.corrections" "10")
weight_iterations=$(get_config_value ".auto_reflect.signal_weights.iterations" "5")
weight_skill_usage=$(get_config_value ".auto_reflect.signal_weights.skill_usage" "8")
weight_external_failures=$(get_config_value ".auto_reflect.signal_weights.external_failures" "12")
weight_edge_cases=$(get_config_value ".auto_reflect.signal_weights.edge_cases" "6")
weight_tokens_per_1k=$(get_config_value ".auto_reflect.signal_weights.tokens_per_1k" "1")

debug "Calculating reflection worthiness score..."
debug "  Weights: corrections=${weight_corrections}, iterations=${weight_iterations}, skill_usage=${weight_skill_usage}"

# === Load Session Signals ===

corrections=$(get_session_state_value ".signals.corrections" "0")
iterations=$(get_session_state_value ".signals.iterations" "0")
skill_usage=$(get_session_state_value ".signals.skill_usage" "0")
external_failures=$(get_session_state_value ".signals.external_failures" "0")
edge_cases=$(get_session_state_value ".signals.edge_cases" "0")
token_count=$(get_session_state_value ".signals.token_count" "0")

debug "  Signals: corrections=${corrections}, iterations=${iterations}, skill_usage=${skill_usage}"
debug "           failures=${external_failures}, edge_cases=${edge_cases}, tokens=${token_count}"

# === Calculate Score ===

score=0

# Corrections
score=$((score + corrections * weight_corrections))

# Iterations
score=$((score + iterations * weight_iterations))

# Skill usage
score=$((score + skill_usage * weight_skill_usage))

# External failures
score=$((score + external_failures * weight_external_failures))

# Edge cases
score=$((score + edge_cases * weight_edge_cases))

# Token count (per 1K tokens)
token_score=$(( (token_count / 1000) * weight_tokens_per_1k ))
score=$((score + token_score))

debug "  → Total score: ${score}"

# === Output ===

echo "${score}"
exit 0
