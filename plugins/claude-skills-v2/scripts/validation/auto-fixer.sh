#!/usr/bin/env bash
set -euo pipefail

# Auto-fixer for plugin structure issues
# Applies fixes with confidence-based approval gates

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN_JSON="${PLUGIN_DIR}/.claude-plugin/plugin.json"
HOOKS_JSON="${PLUGIN_DIR}/hooks/hooks.json"
BACKUP_DIR="${PLUGIN_DIR}/.validation-backups"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DRY_RUN="${DRY_RUN:-false}"
AUTO_FIX_THRESHOLD="${AUTO_FIX_THRESHOLD:-0.9}"
CREATE_BACKUPS="${CREATE_BACKUPS:-true}"
CREATE_GIT_COMMITS="${CREATE_GIT_COMMITS:-true}"

# Stats
FIXES_APPLIED=0
FIXES_SKIPPED=0
ISSUES_FOUND=0

log() {
  echo -e "${BLUE}[auto-fixer]${NC} $1"
}

success() {
  echo -e "${GREEN}✅ $1${NC}"
}

warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
  echo -e "${RED}❌ $1${NC}"
}

# Create backup
backup_file() {
  local file="$1"
  if [[ "$CREATE_BACKUPS" == "true" ]] && [[ -f "$file" ]]; then
    mkdir -p "$BACKUP_DIR"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="${BACKUP_DIR}/$(basename "$file").${timestamp}.bak"
    cp "$file" "$backup_path"
    log "Backup created: $backup_path"
  fi
}

# Create git commit for fix
commit_fix() {
  local fix_description="$1"

  if [[ "$CREATE_GIT_COMMITS" != "true" ]]; then
    return 0
  fi

  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    log "Not in git repository, skipping commit"
    return 0
  fi

  # Check if there are changes to commit
  if git diff --quiet && git diff --cached --quiet; then
    log "No changes to commit"
    return 0
  fi

  # Stage and commit
  git add -A
  git commit -m "fix(plugin): ${fix_description}

Auto-fixed by: scripts/validation/auto-fixer.sh
Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

This is an automatic fix with rollback capability (git revert).
" > /dev/null 2>&1

  local commit_hash=$(git rev-parse --short HEAD)
  success "Git commit created: ${commit_hash}"
  log "Rollback: git revert ${commit_hash}"
}

# ============================================================
# FIX 1: Transform author string to object
# Confidence: 0.95 (Very High)
# ============================================================
fix_author_string_to_object() {
  log "Checking author field format..."

  if ! jq -e '.author | type == "string"' "$PLUGIN_JSON" > /dev/null 2>&1; then
    return 0  # Already an object
  fi

  ((ISSUES_FOUND++))
  log "Issue detected: author is string (should be object)"

  if [[ "$DRY_RUN" == "true" ]]; then
    warning "DRY RUN: Would transform author string to object"
    return 0
  fi

  # Get current author string
  local author_name=$(jq -r '.author' "$PLUGIN_JSON")

  # Backup original
  backup_file "$PLUGIN_JSON"

  # Transform to object
  jq --arg name "$author_name" '.author = {name: $name}' "$PLUGIN_JSON" > "${PLUGIN_JSON}.tmp"
  mv "${PLUGIN_JSON}.tmp" "$PLUGIN_JSON"

  success "Fixed: Author transformed to object format"
  ((FIXES_APPLIED++))

  # Commit fix
  commit_fix "Transform author string to object in plugin.json"
}

# ============================================================
# FIX 2: Remove unsupported keys from plugin.json
# Confidence: 0.95 (Very High)
# ============================================================
fix_unsupported_keys() {
  log "Checking for unsupported keys in plugin.json..."

  local unsupported=$(jq -r 'keys[] | select(. | IN("name", "version", "description", "author", "license", "skills", "hooks", "agents", "settings") | not)' "$PLUGIN_JSON" 2>/dev/null || echo "")

  if [[ -z "$unsupported" ]]; then
    return 0  # No unsupported keys
  fi

  ((ISSUES_FOUND++))
  log "Issue detected: Unsupported keys found"

  while IFS= read -r key; do
    if [[ -z "$key" ]]; then continue; fi

    warning "Found unsupported key: $key"

    if [[ "$DRY_RUN" == "true" ]]; then
      warning "DRY RUN: Would remove key: $key"
      continue
    fi

    # Backup original
    backup_file "$PLUGIN_JSON"

    # Remove the key
    jq "del(.$key)" "$PLUGIN_JSON" > "${PLUGIN_JSON}.tmp"
    mv "${PLUGIN_JSON}.tmp" "$PLUGIN_JSON"

    success "Removed unsupported key: $key"
    ((FIXES_APPLIED++))
  done <<< "$unsupported"

  if [[ "$DRY_RUN" != "true" ]] && [[ $FIXES_APPLIED -gt 0 ]]; then
    commit_fix "Remove unsupported keys from plugin.json"
  fi
}

# ============================================================
# FIX 3: Generate missing hook scripts from templates
# Confidence: 0.85 (High)
# ============================================================
fix_missing_hook_scripts() {
  log "Checking for missing hook scripts..."

  local script_checker="${PLUGIN_DIR}/scripts/validation/script-checker.sh"
  if [[ ! -x "$script_checker" ]]; then
    log "Script checker not found, skipping"
    return 0
  fi

  # Run script checker to find missing scripts
  local missing_output=$("$script_checker" 2>&1 || true)

  if echo "$missing_output" | grep -q "All referenced hook scripts exist"; then
    return 0  # No missing scripts
  fi

  if ! echo "$missing_output" | grep -q "Missing:"; then
    return 0  # No missing scripts detected
  fi

  ((ISSUES_FOUND++))
  log "Issue detected: Missing hook scripts"

  # Extract missing script paths
  local missing_scripts=$(echo "$missing_output" | grep "Missing:" | sed 's/.*Missing: //' || echo "")

  while IFS= read -r script_path; do
    if [[ -z "$script_path" ]]; then continue; fi

    warning "Missing script: $script_path"

    if [[ "$DRY_RUN" == "true" ]]; then
      warning "DRY RUN: Would generate: $script_path"
      continue
    fi

    # Confidence check: Only auto-generate if confidence >= threshold
    local confidence=0.85
    if (( $(echo "$confidence < $AUTO_FIX_THRESHOLD" | bc -l) )); then
      warning "Confidence ($confidence) below threshold ($AUTO_FIX_THRESHOLD), skipping"
      ((FIXES_SKIPPED++))
      continue
    fi

    # Generate using script-checker --generate
    log "Generating missing script from template..."
    if AUTO_FIX_THRESHOLD=0 "$script_checker" --generate > /dev/null 2>&1; then
      success "Generated: $script_path"
      ((FIXES_APPLIED++))
    else
      error "Failed to generate: $script_path"
    fi
  done <<< "$missing_scripts"

  if [[ "$DRY_RUN" != "true" ]] && [[ $FIXES_APPLIED -gt 0 ]]; then
    commit_fix "Generate missing hook scripts from templates"
  fi
}

# ============================================================
# FIX 4: Fix file permissions (make scripts executable)
# Confidence: 0.95 (Very High)
# ============================================================
fix_script_permissions() {
  log "Checking script file permissions..."

  local scripts_dir="${PLUGIN_DIR}/scripts"
  if [[ ! -d "$scripts_dir" ]]; then
    return 0
  fi

  local fixed_count=0

  # Find all .sh files that aren't executable
  while IFS= read -r -d '' script_file; do
    if [[ ! -x "$script_file" ]]; then
      ((ISSUES_FOUND++))
      warning "Script not executable: ${script_file#$PLUGIN_DIR/}"

      if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN: Would make executable: ${script_file#$PLUGIN_DIR/}"
        continue
      fi

      chmod +x "$script_file"
      success "Made executable: ${script_file#$PLUGIN_DIR/}"
      ((fixed_count++))
      ((FIXES_APPLIED++))
    fi
  done < <(find "$scripts_dir" -type f -name "*.sh" -print0)

  if [[ "$DRY_RUN" != "true" ]] && [[ $fixed_count -gt 0 ]]; then
    commit_fix "Fix script file permissions (chmod +x)"
  fi
}

# ============================================================
# FIX 5: Fix JSON formatting
# Confidence: 0.90 (High)
# ============================================================
fix_json_formatting() {
  log "Checking JSON file formatting..."

  local fixed_count=0

  for json_file in "$PLUGIN_JSON" "$HOOKS_JSON" "${PLUGIN_DIR}/config"/*.json; do
    if [[ ! -f "$json_file" ]]; then
      continue
    fi

    # Check if file is already properly formatted
    local formatted=$(jq . "$json_file" 2>/dev/null || echo "")
    local current=$(cat "$json_file")

    if [[ "$formatted" == "$current" ]]; then
      continue  # Already formatted
    fi

    ((ISSUES_FOUND++))
    warning "JSON not formatted: ${json_file#$PLUGIN_DIR/}"

    if [[ "$DRY_RUN" == "true" ]]; then
      warning "DRY RUN: Would format: ${json_file#$PLUGIN_DIR/}"
      continue
    fi

    # Backup original
    backup_file "$json_file"

    # Format with jq
    jq . "$json_file" > "${json_file}.tmp"
    mv "${json_file}.tmp" "$json_file"

    success "Formatted: ${json_file#$PLUGIN_DIR/}"
    ((fixed_count++))
    ((FIXES_APPLIED++))
  done

  if [[ "$DRY_RUN" != "true" ]] && [[ $fixed_count -gt 0 ]]; then
    commit_fix "Format JSON files with proper indentation"
  fi
}

# ============================================================
# Main execution
# ============================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Plugin Auto-Fixer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
  warning "DRY RUN MODE - No changes will be applied"
  echo ""
fi

log "Auto-fix threshold: $AUTO_FIX_THRESHOLD (confidence required)"
log "Create backups: $CREATE_BACKUPS"
log "Create git commits: $CREATE_GIT_COMMITS"
echo ""

# Run all fixes
fix_author_string_to_object
fix_unsupported_keys
fix_script_permissions
fix_json_formatting
fix_missing_hook_scripts

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Summary:"
echo "  Issues found: $ISSUES_FOUND"
echo "  Fixes applied: $FIXES_APPLIED"
echo "  Fixes skipped: $FIXES_SKIPPED"
echo ""

if [[ $FIXES_APPLIED -gt 0 ]]; then
  success "Auto-fix completed successfully"
  echo ""
  log "Next steps:"
  echo "  1. Review changes: git diff"
  echo "  2. Validate: ./scripts/validation/pre-commit-validator.sh"
  echo "  3. Test the plugin"

  if [[ "$CREATE_GIT_COMMITS" == "true" ]]; then
    echo "  4. If issues, rollback: git log --oneline | head -5"
  fi
elif [[ $ISSUES_FOUND -gt 0 ]]; then
  warning "Issues found but not fixed (confidence < $AUTO_FIX_THRESHOLD)"
  log "Run with lower threshold: AUTO_FIX_THRESHOLD=0.7 $0"
else
  success "No issues found - plugin structure is healthy"
fi

exit 0
