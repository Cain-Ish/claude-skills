#!/usr/bin/env bash
# Test automation-hub plugin installation and configuration

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "🧪 Testing automation-hub plugin installation"
echo ""

errors=0
warnings=0

# === Helper Functions ===

pass() {
    echo "  ✓ $1"
}

fail() {
    echo "  ✗ $1" >&2
    errors=$((errors + 1))
}

warn() {
    echo "  ⚠️  $1"
    warnings=$((warnings + 1))
}

# === Test 1: Plugin Structure ===

echo "1. Checking plugin structure..."

if [[ -f "${PLUGIN_DIR}/.claude-plugin/plugin.json" ]]; then
    pass "Plugin manifest exists"
else
    fail "Plugin manifest missing"
fi

if [[ -f "${PLUGIN_DIR}/config/default-config.json" ]]; then
    pass "Default config exists"
else
    fail "Default config missing"
fi

if [[ -f "${PLUGIN_DIR}/hooks/PreToolUse.md" ]]; then
    pass "PreToolUse hook exists"
else
    fail "PreToolUse hook missing"
fi

if [[ -f "${PLUGIN_DIR}/hooks/Stop.md" ]]; then
    pass "Stop hook exists"
else
    fail "Stop hook missing"
fi

echo ""

# === Test 2: Script Executability ===

echo "2. Checking script permissions..."

scripts=(
    # === CORE AUTOMATION (Phases 1-5) ===
    "scripts/lib/common.sh"

    # Phase 1: Auto-Routing
    "scripts/stage1-prefilter.sh"
    "scripts/invoke-task-analyzer.sh"
    "scripts/discover-ecosystem.sh"
    "scripts/intelligent-routing.sh"
    "scripts/adaptive-routing-learner.sh"
    "scripts/semantic-router.sh"
    "scripts/team-coordinator.sh"
    "scripts/agent-registry-manager.sh"
    "scripts/swarm-orchestrator.sh"
    "scripts/workflow-planner.sh"

    # Phase 2: Auto-Cleanup
    "scripts/check-cleanup-safe.sh"
    "scripts/automatic-recovery.sh"
    "scripts/circuit-breaker-manager.sh"

    # Phase 3: Auto-Reflection
    "scripts/track-session-signals.sh"
    "scripts/calculate-reflection-score.sh"
    "scripts/mar-debate-orchestrator.sh"
    "scripts/three-type-memory.sh"

    # Phase 4: Auto-Debugging
    "scripts/auto-apply-fixes.sh"
    "scripts/rollback-fixes.sh"
    "scripts/self-healing-agent.sh"

    # Phase 5: Closed-Loop Learning
    "scripts/analyze-metrics.sh"
    "scripts/apply-proposal.sh"
    "scripts/predictive-analytics.sh"
    "scripts/autonomous-orchestration-refiner.sh"
    "scripts/cross-plugin-optimizer.sh"

    # === SUPPORTING INFRASTRUCTURE ===
    "scripts/automation-command.sh"
    "scripts/orchestrate-dispatch.sh"
    "scripts/telemetry-exporter.sh"
    "scripts/generate-dashboard.sh"
    "scripts/track-costs.sh"
    "scripts/performance-cache.sh"
    "scripts/streaming-events.sh"
    "scripts/decision-tracer.sh"
    "scripts/context-memory-manager.sh"
    "scripts/security-sandbox.sh"
    "scripts/protocol-bridge.sh"
    "scripts/cross-platform-orchestrator.sh"
    "scripts/opentelemetry-tracer.sh"
    "scripts/agentic-qa-validator.sh"
    "scripts/deployment-automator.sh"
)

for script in "${scripts[@]}"; do
    if [[ -x "${PLUGIN_DIR}/${script}" ]]; then
        pass "${script} is executable"
    else
        fail "${script} is not executable (run: chmod +x ${PLUGIN_DIR}/${script})"
    fi
done

echo ""

# === Test 3: Dependencies ===

echo "3. Checking dependencies..."

if command -v jq >/dev/null 2>&1; then
    pass "jq is installed"
else
    fail "jq is NOT installed (required for JSON processing)"
fi

if command -v git >/dev/null 2>&1; then
    pass "git is installed"
else
    fail "git is NOT installed (required for version control)"
fi

if command -v bc >/dev/null 2>&1; then
    pass "bc is installed"
else
    fail "bc is NOT installed (required for arithmetic)"
fi

echo ""

# === Test 4: Configuration Validity ===

echo "4. Validating configuration..."

if jq empty "${PLUGIN_DIR}/config/default-config.json" 2>/dev/null; then
    pass "Default config is valid JSON"
else
    fail "Default config is invalid JSON"
fi

# Check required config fields
required_fields=(
    ".auto_routing.enabled"
    ".auto_cleanup.enabled"
    ".auto_reflect.enabled"
    ".auto_apply.enabled"
    ".learning.enabled"
)

for field in "${required_fields[@]}"; do
    # Check if field exists (not null), regardless of value
    exists=$(jq -r "${field} | if . == null then \"missing\" else \"present\" end" "${PLUGIN_DIR}/config/default-config.json" 2>/dev/null)
    if [[ "${exists}" == "present" ]]; then
        pass "Config has ${field}"
    else
        fail "Config missing ${field}"
    fi
done

echo ""

# === Test 5: Hook Format ===

echo "5. Validating hook format..."

# Check PreToolUse has required sections
if grep -q "## Auto-Routing Logic" "${PLUGIN_DIR}/hooks/PreToolUse.md"; then
    pass "PreToolUse hook has auto-routing section"
else
    warn "PreToolUse hook missing auto-routing section"
fi

if grep -q "## Session Signal Tracking" "${PLUGIN_DIR}/hooks/PreToolUse.md"; then
    pass "PreToolUse hook has signal tracking section"
else
    warn "PreToolUse hook missing signal tracking section"
fi

# Check Stop has required sections
if grep -q "## Auto-Cleanup Orchestration" "${PLUGIN_DIR}/hooks/Stop.md"; then
    pass "Stop hook has auto-cleanup section"
else
    warn "Stop hook missing auto-cleanup section"
fi

if grep -q "## Auto-Reflection Suggestion" "${PLUGIN_DIR}/hooks/Stop.md"; then
    pass "Stop hook has auto-reflection section"
else
    warn "Stop hook missing auto-reflection section"
fi

echo ""

# === Test 6: Runtime Directories ===

echo "6. Checking runtime directories..."

config_dir="${HOME}/.claude/automation-hub"

if [[ -d "${config_dir}" ]]; then
    pass "Runtime config directory exists"
else
    warn "Runtime config directory will be created on first run"
fi

echo ""

# === Test 7: Script Functionality (Basic) ===

echo "7. Testing script functionality..."

# Test common.sh can be sourced
if source "${PLUGIN_DIR}/scripts/lib/common.sh" 2>/dev/null; then
    pass "common.sh can be sourced"
else
    fail "common.sh has syntax errors"
fi

# Test stage1-prefilter.sh runs
if bash "${PLUGIN_DIR}/scripts/stage1-prefilter.sh" "test prompt" "50000" "Write" >/dev/null 2>&1; then
    pass "stage1-prefilter.sh runs without errors"
else
    fail "stage1-prefilter.sh has runtime errors"
fi

# Test calculate-reflection-score.sh runs
if bash "${PLUGIN_DIR}/scripts/calculate-reflection-score.sh" >/dev/null 2>&1; then
    pass "calculate-reflection-score.sh runs without errors"
else
    fail "calculate-reflection-score.sh has runtime errors"
fi

echo ""

# === Summary ===

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ ${errors} -eq 0 ]] && [[ ${warnings} -eq 0 ]]; then
    echo "✅ All tests passed! Plugin is ready to use."
    exit 0
elif [[ ${errors} -eq 0 ]]; then
    echo "⚠️  Tests passed with ${warnings} warning(s)."
    echo "Plugin should work but review warnings above."
    exit 0
else
    echo "❌ Tests failed with ${errors} error(s) and ${warnings} warning(s)."
    echo "Fix errors before using plugin."
    exit 1
fi
