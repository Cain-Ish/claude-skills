#!/usr/bin/env bash
set -euo pipefail

# Script Checker - Detect missing hook scripts referenced in hooks.json
# Usage: ./script-checker.sh [--generate] [--verbose]

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS_JSON="${PLUGIN_DIR}/hooks/hooks.json"
SCRIPTS_DIR="${PLUGIN_DIR}/scripts"
TEMPLATES_DIR="${SCRIPTS_DIR}/validation/templates"

# Parse arguments
GENERATE_MISSING=false
VERBOSE=false
for arg in "$@"; do
  case $arg in
    --generate)
      GENERATE_MISSING=true
      ;;
    --verbose)
      VERBOSE=true
      ;;
    --help)
      echo "Usage: $0 [--generate] [--verbose]"
      echo ""
      echo "Options:"
      echo "  --generate    Generate missing scripts from templates"
      echo "  --verbose     Show detailed output"
      echo "  --help        Show this help message"
      exit 0
      ;;
  esac
done

# Check if hooks.json exists
if [[ ! -f "$HOOKS_JSON" ]]; then
  echo "❌ Error: hooks.json not found at $HOOKS_JSON"
  exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo "❌ Error: jq is required but not installed"
  exit 1
fi

# Validate hooks.json is valid JSON
if ! jq empty "$HOOKS_JSON" 2>/dev/null; then
  echo "❌ Error: hooks.json is not valid JSON"
  exit 1
fi

echo "🔍 Checking hook scripts referenced in hooks.json..."
echo ""

# Extract all script paths from hooks.json
MISSING_SCRIPTS=()
ALL_SCRIPTS=()

# Function to check script
check_script() {
  local script_path="$1"
  local hook_type="$2"
  local matcher="$3"

  ALL_SCRIPTS+=("$script_path")

  # Convert relative path to absolute
  local full_path="${PLUGIN_DIR}/${script_path#./}"

  if [[ ! -f "$full_path" ]]; then
    MISSING_SCRIPTS+=("$script_path|$hook_type|$matcher")
    echo "  🔴 Missing: $script_path"
    [[ "$VERBOSE" == true ]] && echo "      Type: $hook_type, Matcher: $matcher"
    return 1
  else
    [[ "$VERBOSE" == true ]] && echo "  ✅ Found: $script_path"

    # Check if executable
    if [[ ! -x "$full_path" ]]; then
      echo "  ⚠️  Warning: $script_path is not executable"
      [[ "$VERBOSE" == true ]] && echo "      Run: chmod +x $full_path"
    fi
    return 0
  fi
}

# Parse hooks.json and check each script
HOOK_TYPES=("PreToolUse" "PostToolUse" "SessionStart" "SessionEnd" "Stop" "PreCompact")

for hook_type in "${HOOK_TYPES[@]}"; do
  # Check if hook type exists in hooks.json
  if ! jq -e ".${hook_type}" "$HOOKS_JSON" > /dev/null 2>&1; then
    continue
  fi

  [[ "$VERBOSE" == true ]] && echo "Checking $hook_type hooks..."

  # Get number of hook groups
  hook_count=$(jq ".${hook_type} | length" "$HOOKS_JSON")

  for ((i=0; i<hook_count; i++)); do
    matcher=$(jq -r ".${hook_type}[$i].matcher" "$HOOKS_JSON")

    # Get number of hooks in this group
    hooks_in_group=$(jq ".${hook_type}[$i].hooks | length" "$HOOKS_JSON")

    for ((j=0; j<hooks_in_group; j++)); do
      script_path=$(jq -r ".${hook_type}[$i].hooks[$j].command" "$HOOKS_JSON")

      # Skip non-script hooks (like "agent" type)
      hook_hook_type=$(jq -r ".${hook_type}[$i].hooks[$j].type" "$HOOKS_JSON")
      if [[ "$hook_hook_type" != "command" ]]; then
        continue
      fi

      check_script "$script_path" "$hook_type" "$matcher"
    done
  done
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Summary
TOTAL_SCRIPTS=${#ALL_SCRIPTS[@]}
MISSING_COUNT=${#MISSING_SCRIPTS[@]}
FOUND_COUNT=$((TOTAL_SCRIPTS - MISSING_COUNT))

echo "Summary:"
echo "  Total scripts referenced: $TOTAL_SCRIPTS"
echo "  Found: $FOUND_COUNT"
echo "  Missing: $MISSING_COUNT"

if [[ $MISSING_COUNT -eq 0 ]]; then
  echo ""
  echo "✅ All referenced hook scripts exist!"
  exit 0
fi

# Show missing scripts with context
echo ""
echo "Missing Scripts:"
for entry in "${MISSING_SCRIPTS[@]}"; do
  IFS='|' read -r script_path hook_type matcher <<< "$entry"
  echo "  • $script_path"
  echo "    Hook Type: $hook_type"
  echo "    Matcher: $matcher"

  # Suggest template
  TEMPLATE=""
  case $hook_type in
    PreToolUse)
      TEMPLATE="${TEMPLATES_DIR}/pretooluse-template.sh"
      ;;
    PostToolUse)
      TEMPLATE="${TEMPLATES_DIR}/posttooluse-template.sh"
      ;;
    *)
      TEMPLATE="${TEMPLATES_DIR}/generic-hook-template.sh"
      ;;
  esac
  echo "    Template: $TEMPLATE"
  echo ""
done

# Offer to generate missing scripts
if [[ "$GENERATE_MISSING" == true ]]; then
  echo "📝 Generating missing scripts from templates..."
  echo ""

  for entry in "${MISSING_SCRIPTS[@]}"; do
    IFS='|' read -r script_path hook_type matcher <<< "$entry"

    # Determine template
    TEMPLATE=""
    case $hook_type in
      PreToolUse)
        TEMPLATE="${TEMPLATES_DIR}/pretooluse-template.sh"
        ;;
      PostToolUse)
        TEMPLATE="${TEMPLATES_DIR}/posttooluse-template.sh"
        ;;
      *)
        TEMPLATE="${TEMPLATES_DIR}/generic-hook-template.sh"
        ;;
    esac

    # Convert relative path to absolute
    full_path="${PLUGIN_DIR}/${script_path#./}"

    # Create directory if needed
    mkdir -p "$(dirname "$full_path")"

    # Copy template
    if [[ -f "$TEMPLATE" ]]; then
      cp "$TEMPLATE" "$full_path"
      chmod +x "$full_path"
      echo "  ✅ Generated: $script_path (from template)"
    else
      echo "  ❌ Template not found: $TEMPLATE"
    fi
  done

  echo ""
  echo "✅ Script generation complete!"
  echo "   Remember to implement the TODO sections in each generated script."
else
  echo ""
  echo "💡 Run with --generate to automatically create missing scripts from templates"
fi

exit 0
