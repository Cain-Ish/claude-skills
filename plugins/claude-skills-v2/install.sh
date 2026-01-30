#!/usr/bin/env bash
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Claude Skills 2.0 - Autonomous Plugin"
echo ""

# Validate
jq empty "$PLUGIN_DIR/.claude-plugin/plugin.json" && echo "✅ plugin.json valid" || exit 1
jq empty "$PLUGIN_DIR/hooks/hooks.json" && echo "✅ hooks.json valid" || exit 1
jq empty "$PLUGIN_DIR/config/default-config.json" && echo "✅ config valid" || exit 1

# Make scripts executable
find "$PLUGIN_DIR/scripts" -type f -name "*.sh" -exec chmod +x {} \;
echo "✅ Scripts executable"

# Create data directories
mkdir -p ~/.claude/claude-skills/{observations/sessions,instincts/{learned,personal},logs,metrics,memory,learning,findings}
echo "✅ Data directories created"

echo ""
echo "📦 Install:"
echo "   /plugin install $PLUGIN_DIR"
echo ""
echo "✨ Auto-features:"
echo "   • PreToolUse: Validates commands (blocks dangerous operations)"
echo "   • PostToolUse: Auto-formats code, logs observations"
echo "   • SessionStart: Initializes learning engine"
echo "   • Stop: Extracts patterns, suggests next actions"
echo "   • PreCompact: Preserves state before context reset"
echo "   • Continuous learning: Background pattern detection every 5 min"
echo ""
echo "🤖 Available:"
echo "   /learn - Extract patterns from session"
echo "   /evolve - Cluster instincts into skills"
echo ""
echo "🎯 Agents auto-invoke based on context (security, code review, orchestration)"
