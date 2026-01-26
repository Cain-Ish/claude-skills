#!/usr/bin/env bash
# MAR (Multi-Agent Reflexion) Debate Orchestrator
# Coordinates debate among persona critics for high-quality reflection proposals

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Input: proposal text or question for debate
PROPOSAL_TEXT="${1:-}"
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"

MAR_DIR="${HOME}/.claude/automation-hub/mar-debates"
mkdir -p "${MAR_DIR}"

# Check if MAR is enabled
MAR_ENABLED=$(get_config_value ".mar_debate.enabled" "true")
if [[ "${MAR_ENABLED}" != "true" ]]; then
    debug "MAR debate disabled, falling back to single-critic"
    exit 0
fi

# Get configuration
MIN_WORTHINESS=$(get_config_value ".mar_debate.min_worthiness_for_debate" "25")
CONSERVATIVE_WEIGHT=$(get_config_value ".mar_debate.personas.conservative.weight" "0.30")
AGGRESSIVE_WEIGHT=$(get_config_value ".mar_debate.personas.aggressive.weight" "0.30")
BALANCED_WEIGHT=$(get_config_value ".mar_debate.personas.balanced.weight" "0.40")
CONSENSUS_THRESHOLD=$(get_config_value ".mar_debate.consensus_threshold" "0.70")

# === Validate Input ===

if [[ -z "${PROPOSAL_TEXT}" ]]; then
    log_error "Usage: mar-debate-orchestrator.sh <proposal_text>"
    exit 1
fi

# === Store Debate Context ===

DEBATE_ID="$(date +%s)-${SESSION_ID}"
DEBATE_FILE="${MAR_DIR}/debate-${DEBATE_ID}.json"

log_info "Initiating MAR debate: ${DEBATE_ID}"

# Create initial debate record
jq -n \
    --arg id "${DEBATE_ID}" \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg sid "${SESSION_ID}" \
    --arg proposal "${PROPOSAL_TEXT}" \
    '{
        debate_id: $id,
        timestamp: $ts,
        session_id: $sid,
        proposal: $proposal,
        personas: {
            conservative: { weight: '"${CONSERVATIVE_WEIGHT}"', critique: null },
            aggressive: { weight: '"${AGGRESSIVE_WEIGHT}"', critique: null },
            balanced: { weight: '"${BALANCED_WEIGHT}"', critique: null }
        },
        consensus: null,
        status: "in_progress"
    }' > "${DEBATE_FILE}"

# === Prepare Agent Invocation Instructions ===

# In a real implementation, this would invoke Task tool with each agent
# For bash script, we output instructions that the calling hook/skill should execute

cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  MAR DEBATE: Multi-Agent Reflection
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Debate ID: ${DEBATE_ID}
Proposal: ${PROPOSAL_TEXT}

INSTRUCTIONS FOR CLAUDE CODE:

To run the MAR debate, invoke these agents in sequence:

1. Conservative Critic (Weight: ${CONSERVATIVE_WEIGHT})
   Task tool with mar-conservative-critic:
   "Critique this reflection proposal from a risk-minimization perspective:

   ${PROPOSAL_TEXT}

   Output your critique in the required JSON format."

2. Aggressive Critic (Weight: ${AGGRESSIVE_WEIGHT})
   Task tool with mar-aggressive-critic:
   "Critique this reflection proposal from an improvement-maximization perspective:

   ${PROPOSAL_TEXT}

   Output your critique in the required JSON format."

3. Balanced Critic (Weight: ${BALANCED_WEIGHT})
   Task tool with mar-balanced-critic:
   "Critique this reflection proposal from a pragmatic perspective, synthesizing
   the conservative and aggressive viewpoints:

   ${PROPOSAL_TEXT}

   Output your critique in the required JSON format."

4. Judge Synthesis
   Task tool with mar-judge:
   "Synthesize the three critiques into a consensus recommendation:

   Conservative: <paste conservative critique JSON>
   Aggressive: <paste aggressive critique JSON>
   Balanced: <paste balanced critique JSON>

   Apply weights: Conservative ${CONSERVATIVE_WEIGHT}, Aggressive ${AGGRESSIVE_WEIGHT}, Balanced ${BALANCED_WEIGHT}
   Consensus threshold: ${CONSENSUS_THRESHOLD}

   Output your consensus in the required JSON format."

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

After running all agents, the final consensus will guide the reflection proposal.

Research Foundation:
- MAR Framework (arXiv 2512.20845): Multi-agent debate prevents degeneration of thought
- Performance: 47% HotPot QA, 82.7% HumanEval (surpassing single-critic)
- Addresses failure mode: LLM repeating same errors in self-reflection

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

# Update debate status
jq '.status = "pending_critiques"' "${DEBATE_FILE}" > "${DEBATE_FILE}.tmp"
mv "${DEBATE_FILE}.tmp" "${DEBATE_FILE}"

# Log metric
log_metric "mar_debate_initiated" "$(jq -n --arg id "${DEBATE_ID}" '{debate_id: $id}')"

debug "MAR debate instructions output. Awaiting agent invocations."
