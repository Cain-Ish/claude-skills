#!/usr/bin/env bash
set -euo pipefail

# Pre-commit Validator for claude-skills-v2 plugin
# Validates plugin structure before commits to catch issues early
#
# ARCHITECTURE: Self-Improvement System
# =====================================
# This plugin implements a comprehensive self-improvement architecture across 3 phases:
#
# Phase 1: Prevention (Validation)
#   - pre-commit-validator.sh (this script): Validates plugin structure before commits
#   - script-checker.sh: Detects missing hook scripts
#   - Hook templates: Templates for generating missing scripts
#   - 4 new hooks: context-tracker, write-validation, edit-validation, bash-feedback
#
# Phase 2: Detection (Diagnostics)
#   - plugin-diagnostician agent: Auto-diagnoses errors with root cause analysis
#   - /validate-plugin command: User-triggered validation with filtering
#   - /save-plugin command: Manual auto-commit trigger
#
# Phase 3: Remediation (Auto-Fix)
#   - auto-fixer.sh: Applies fixes with confidence-based approval (0.0-1.0)
#   - /fix-plugin command: Interactive fixing wizard
#   - Auto-commit system: Prevents data loss during development
#
# Documentation Philosophy:
#   - All docs are IN the code (this comment, command files, agent frontmatter)
#   - NO separate docs/ folder (violates "no unnecessary .md files" principle)
#   - Commands (commands/*.md) serve as user documentation
#   - Code comments serve as architecture/technical documentation
#
# For more details, see:
#   - commands/validate-plugin.md - Validation usage
#   - commands/fix-plugin.md - Auto-fix usage
#   - commands/save-plugin.md - Auto-commit usage
#   - agents/diagnostics/plugin-diagnostician.md - Diagnostic agent spec

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN_JSON="${PLUGIN_DIR}/.claude-plugin/plugin.json"
HOOKS_JSON="${PLUGIN_DIR}/hooks/hooks.json"
CONFIG_JSON="${PLUGIN_DIR}/config/default-config.json"
AGENTS_DIR="${PLUGIN_DIR}/agents"
COMMANDS_DIR="${PLUGIN_DIR}/commands"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Validation state
ERRORS=()
WARNINGS=()
CHECKS_PASSED=0
CHECKS_FAILED=0

# Helper functions
error() {
  local msg="$1"
  local file="${2:-}"
  local line="${3:-}"

  if [[ -n "$file" ]] && [[ -n "$line" ]]; then
    ERRORS+=("🔴 $file:$line - $msg")
  elif [[ -n "$file" ]]; then
    ERRORS+=("🔴 $file - $msg")
  else
    ERRORS+=("🔴 $msg")
  fi
  ((CHECKS_FAILED++)) || true
}

warning() {
  local msg="$1"
  local file="${2:-}"

  if [[ -n "$file" ]]; then
    WARNINGS+=("⚠️  $file - $msg")
  else
    WARNINGS+=("⚠️  $msg")
  fi
}

pass() {
  ((CHECKS_PASSED++)) || true
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Claude Skills v2 - Pre-Commit Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  error "jq is required but not installed. Install with: brew install jq"
  echo ""
  echo "${RED}❌ Validation failed${NC}"
  exit 1
fi

# ============================================================
# 1. Validate plugin.json
# ============================================================
echo "📋 Validating plugin.json..."

if [[ ! -f "$PLUGIN_JSON" ]]; then
  error "plugin.json not found" ".claude-plugin/plugin.json"
else
  # Check if valid JSON
  if ! jq empty "$PLUGIN_JSON" 2>/dev/null; then
    error "plugin.json is not valid JSON" ".claude-plugin/plugin.json"
  else
    # Check required fields
    for field in name version description author; do
      if ! jq -e ".$field" "$PLUGIN_JSON" > /dev/null 2>&1; then
        error "Missing required field: $field" ".claude-plugin/plugin.json"
      fi
    done

    # Check author is object (not string)
    if jq -e '.author | type == "string"' "$PLUGIN_JSON" > /dev/null 2>&1; then
      error "author must be an object with 'name' field, not a string" ".claude-plugin/plugin.json"
    elif jq -e '.author | type == "object"' "$PLUGIN_JSON" > /dev/null 2>&1; then
      if ! jq -e '.author.name' "$PLUGIN_JSON" > /dev/null 2>&1; then
        error "author object must have 'name' field" ".claude-plugin/plugin.json"
      else
        pass
      fi
    fi

    # Check for unsupported keys
    UNSUPPORTED_KEYS=$(jq -r 'keys[] | select(. | IN("name", "version", "description", "author", "license", "skills", "hooks", "agents", "settings") | not)' "$PLUGIN_JSON" 2>/dev/null || true)
    if [[ -n "$UNSUPPORTED_KEYS" ]]; then
      while IFS= read -r key; do
        error "Unsupported key in plugin.json: $key" ".claude-plugin/plugin.json"
      done <<< "$UNSUPPORTED_KEYS"
    fi

    # Check hooks path exists
    if jq -e '.hooks' "$PLUGIN_JSON" > /dev/null 2>&1; then
      HOOKS_PATH=$(jq -r '.hooks' "$PLUGIN_JSON")
      FULL_HOOKS_PATH="${PLUGIN_DIR}/${HOOKS_PATH#./}"
      if [[ ! -f "$FULL_HOOKS_PATH" ]]; then
        error "hooks path does not exist: $HOOKS_PATH" ".claude-plugin/plugin.json"
      else
        pass
      fi
    fi

    # Check agent files exist
    if jq -e '.agents' "$PLUGIN_JSON" > /dev/null 2>&1; then
      AGENT_COUNT=$(jq '.agents | length' "$PLUGIN_JSON")
      for ((i=0; i<AGENT_COUNT; i++)); do
        AGENT_PATH=$(jq -r ".agents[$i]" "$PLUGIN_JSON")
        FULL_AGENT_PATH="${PLUGIN_DIR}/${AGENT_PATH#./}"

        if [[ "$AGENT_PATH" == */ ]]; then
          # Directory reference
          if [[ ! -d "$FULL_AGENT_PATH" ]]; then
            error "Agent directory does not exist: $AGENT_PATH" ".claude-plugin/plugin.json"
          else
            # Check if directory has any .md files
            if ! find "$FULL_AGENT_PATH" -maxdepth 1 -name "*.md" | grep -q .; then
              warning "Agent directory is empty: $AGENT_PATH" ".claude-plugin/plugin.json"
            else
              pass
            fi
          fi
        else
          # File reference
          if [[ ! -f "$FULL_AGENT_PATH" ]]; then
            error "Agent file does not exist: $AGENT_PATH" ".claude-plugin/plugin.json"
          else
            pass
          fi
        fi
      done
    fi

    # Check skills paths exist
    if jq -e '.skills' "$PLUGIN_JSON" > /dev/null 2>&1; then
      SKILL_COUNT=$(jq '.skills | length' "$PLUGIN_JSON")
      for ((i=0; i<SKILL_COUNT; i++)); do
        SKILL_PATH=$(jq -r ".skills[$i]" "$PLUGIN_JSON")
        FULL_SKILL_PATH="${PLUGIN_DIR}/${SKILL_PATH#./}"

        if [[ "$SKILL_PATH" == */ ]]; then
          # Directory reference
          if [[ ! -d "$FULL_SKILL_PATH" ]]; then
            error "Skills directory does not exist: $SKILL_PATH" ".claude-plugin/plugin.json"
          else
            pass
          fi
        else
          # File reference
          if [[ ! -f "$FULL_SKILL_PATH" ]]; then
            error "Skills file does not exist: $SKILL_PATH" ".claude-plugin/plugin.json"
          else
            pass
          fi
        fi
      done
    fi
  fi
fi

# ============================================================
# 2. Validate hooks.json
# ============================================================
echo "🪝 Validating hooks.json..."

if [[ ! -f "$HOOKS_JSON" ]]; then
  warning "hooks.json not found (optional)" "hooks/hooks.json"
else
  # Check if valid JSON
  if ! jq empty "$HOOKS_JSON" 2>/dev/null; then
    error "hooks.json is not valid JSON" "hooks/hooks.json"
  else
    # Valid hook types
    VALID_HOOK_TYPES=("PreToolUse" "PostToolUse" "SessionStart" "SessionEnd" "Stop" "PreCompact" "UserPromptSubmit")

    # Check for invalid hook types
    HOOK_TYPES_IN_FILE=$(jq -r 'keys[]' "$HOOKS_JSON")
    while IFS= read -r hook_type; do
      if [[ ! " ${VALID_HOOK_TYPES[*]} " =~ " ${hook_type} " ]]; then
        error "Invalid hook type: $hook_type (valid types: ${VALID_HOOK_TYPES[*]})" "hooks/hooks.json"
      fi
    done <<< "$HOOK_TYPES_IN_FILE"

    # Check each hook has required fields
    for hook_type in "${VALID_HOOK_TYPES[@]}"; do
      if ! jq -e ".${hook_type}" "$HOOKS_JSON" > /dev/null 2>&1; then
        continue
      fi

      hook_count=$(jq ".${hook_type} | length" "$HOOKS_JSON")
      for ((i=0; i<hook_count; i++)); do
        # Check matcher exists
        if ! jq -e ".${hook_type}[$i].matcher" "$HOOKS_JSON" > /dev/null 2>&1; then
          error "Hook missing 'matcher' field" "hooks/hooks.json"
        fi

        # Check hooks array exists
        if ! jq -e ".${hook_type}[$i].hooks" "$HOOKS_JSON" > /dev/null 2>&1; then
          error "Hook missing 'hooks' array" "hooks/hooks.json"
        else
          hooks_in_group=$(jq ".${hook_type}[$i].hooks | length" "$HOOKS_JSON")

          for ((j=0; j<hooks_in_group; j++)); do
            # Check type exists
            if ! jq -e ".${hook_type}[$i].hooks[$j].type" "$HOOKS_JSON" > /dev/null 2>&1; then
              error "Hook missing 'type' field" "hooks/hooks.json"
            fi

            # Check command exists for command type
            hook_hook_type=$(jq -r ".${hook_type}[$i].hooks[$j].type" "$HOOKS_JSON")
            if [[ "$hook_hook_type" == "command" ]]; then
              if ! jq -e ".${hook_type}[$i].hooks[$j].command" "$HOOKS_JSON" > /dev/null 2>&1; then
                error "Command hook missing 'command' field" "hooks/hooks.json"
              else
                pass
              fi
            fi
          done
        fi
      done
    done

    # Run script-checker to verify all scripts exist
    SCRIPT_CHECKER="${PLUGIN_DIR}/scripts/validation/script-checker.sh"
    if [[ -x "$SCRIPT_CHECKER" ]]; then
      if ! "$SCRIPT_CHECKER" > /dev/null 2>&1; then
        error "Some hook scripts referenced in hooks.json do not exist" "hooks/hooks.json"
        echo "  Run: $SCRIPT_CHECKER --verbose for details"
      else
        pass
      fi
    fi
  fi
fi

# ============================================================
# 3. Validate agent files
# ============================================================
echo "🤖 Validating agent files..."

if [[ -d "$AGENTS_DIR" ]]; then
  AGENT_COUNT=0
  while IFS= read -r -d '' agent_file; do
    ((AGENT_COUNT++))
    # Get relative path
    RELATIVE_PATH="${agent_file#$PLUGIN_DIR/}"

    # Check if file has frontmatter
    if ! grep -q "^---$" "$agent_file" 2>/dev/null; then
      warning "Agent file missing frontmatter" "$RELATIVE_PATH"
    else
      # Extract frontmatter
      FRONTMATTER=$(sed -n '/^---$/,/^---$/p' "$agent_file" | sed '1d;$d')

      # Check required frontmatter fields
      for field in name description; do
        if ! echo "$FRONTMATTER" | grep -q "^$field:"; then
          error "Agent missing required frontmatter field: $field" "$RELATIVE_PATH"
        fi
      done

      pass
    fi
  done < <(find "$AGENTS_DIR" -type f -name "*.md" -print0)

  if [[ $AGENT_COUNT -eq 0 ]]; then
    warning "No agent files found in agents/" "agents/"
  fi
fi

# ============================================================
# 4. Validate config JSON
# ============================================================
echo "⚙️  Validating config files..."

if [[ -f "$CONFIG_JSON" ]]; then
  if ! jq empty "$CONFIG_JSON" 2>/dev/null; then
    error "config/default-config.json is not valid JSON" "config/default-config.json"
  else
    pass
  fi
fi

# ============================================================
# 5. Check for unnecessary documentation
# ============================================================
echo "📝 Checking for unnecessary documentation..."

# Check for docs/ directory (violates plugin philosophy)
if [[ -d "${PLUGIN_DIR}/docs" ]]; then
  error "docs/ directory exists - violates plugin philosophy. Documentation should be IN the code (commands, agents, comments), not separate .md files" "docs/"
else
  pass
fi

# Check for unnecessary root-level .md files
UNNECESSARY_MD_FILES=$(find "$PLUGIN_DIR" -maxdepth 1 -name "*.md" -not -name "CLAUDE.md" 2>/dev/null || echo "")
if [[ -n "$UNNECESSARY_MD_FILES" ]]; then
  while IFS= read -r md_file; do
    if [[ -z "$md_file" ]]; then continue; fi
    FILENAME=$(basename "$md_file")
    warning "Unnecessary .md file in root: $FILENAME (documentation should be in commands/ or code comments)" "$FILENAME"
  done <<< "$UNNECESSARY_MD_FILES"
fi

# ============================================================
# 5. Summary
# ============================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Print errors
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "${RED}❌ Validation Errors:${NC}"
  for err in "${ERRORS[@]}"; do
    echo "  $err"
  done
  echo ""
fi

# Print warnings
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo "${YELLOW}⚠️  Warnings:${NC}"
  for warn in "${WARNINGS[@]}"; do
    echo "  $warn"
  done
  echo ""
fi

# Print summary
echo "Summary:"
echo "  ${GREEN}✓${NC} Checks passed: $CHECKS_PASSED"
if [[ $CHECKS_FAILED -gt 0 ]]; then
  echo "  ${RED}✗${NC} Checks failed: $CHECKS_FAILED"
fi
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo "  ${YELLOW}⚠${NC} Warnings: ${#WARNINGS[@]}"
fi

echo ""

# Exit code
if [[ $CHECKS_FAILED -gt 0 ]]; then
  echo "${RED}❌ Pre-commit validation failed${NC}"
  echo ""
  echo "Fix the errors above before committing."
  exit 1
else
  echo "${GREEN}✅ Pre-commit validation passed${NC}"
  exit 0
fi
