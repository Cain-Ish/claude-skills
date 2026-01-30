---
name: fix-plugin
description: Automatically fix common plugin structure issues with confidence-based approval
usage: /fix-plugin [--dry-run] [--threshold 0.9] [--auto]
examples:
  - /fix-plugin
  - /fix-plugin --dry-run
  - /fix-plugin --threshold 0.7
  - /fix-plugin --auto
---

# /fix-plugin - Auto-Fix Plugin Issues

Automatically detect and fix common plugin structure issues using confidence-based approval gates.

## What This Does

1. **Detects issues** by running validation checks
2. **Classifies fixes** by confidence level (0.0-1.0)
3. **Applies high-confidence fixes** automatically
4. **Asks permission** for medium-confidence fixes
5. **Creates git commits** for each fix (easy rollback)
6. **Re-validates** after applying fixes

## Usage

```bash
# Interactive mode (asks permission for medium-confidence fixes)
/fix-plugin

# Dry run (preview without making changes)
/fix-plugin --dry-run

# Auto mode (apply all fixes above threshold)
/fix-plugin --auto

# Lower threshold (fix more issues)
/fix-plugin --threshold 0.7

# Dry run with lower threshold
/fix-plugin --dry-run --threshold 0.7
```

## Confidence Levels

Fixes are classified by confidence score:

### 0.9-1.0 (Very High) - Auto-Applied
- ✅ Transform author string → object
- ✅ Remove unsupported keys from plugin.json
- ✅ Fix file permissions (chmod +x on scripts)
- ✅ Format JSON files properly

### 0.7-0.9 (High) - Asks Permission
- ⚠️  Generate missing hook scripts from templates
- ⚠️  Update deprecated configuration structure
- ⚠️  Fix minor structural issues

### 0.5-0.7 (Medium) - Suggests Only
- 💡 Refactor complex hook logic
- 💡 Improve agent frontmatter
- 💡 Optimize configuration

### <0.5 (Low) - Manual Fix Required
- 🔧 Architectural changes
- 🔧 Complex migrations
- 🔧 Ambiguous requirements

## Common Fixes

### Fix 1: Author String → Object

**Issue:**
```json
{
  "author": "Claude Skills Team"
}
```

**Fix (Confidence: 0.95):**
```json
{
  "author": {
    "name": "Claude Skills Team"
  }
}
```

### Fix 2: Remove Unsupported Keys

**Issue:**
```json
{
  "name": "claude-skills",
  "minClaudeCodeVersion": "1.0.0",  // Unsupported
  "rules": {...}                     // Unsupported
}
```

**Fix (Confidence: 0.95):**
```json
{
  "name": "claude-skills"
  // Unsupported keys removed
}
```

### Fix 3: Generate Missing Hook Scripts

**Issue:**
```
🔴 Missing: ./scripts/hooks/pre-tool-use/context-tracker.sh
```

**Fix (Confidence: 0.85):**
- Generates script from template
- Makes executable (chmod +x)
- Includes TODO comments for implementation

### Fix 4: Fix Script Permissions

**Issue:**
```
⚠️  Script not executable: ./scripts/hooks/session-start.sh
```

**Fix (Confidence: 0.95):**
```bash
chmod +x ./scripts/hooks/session-start.sh
```

### Fix 5: Format JSON Files

**Issue:**
```json
{"name":"plugin","version":"1.0.0"}
```

**Fix (Confidence: 0.90):**
```json
{
  "name": "plugin",
  "version": "1.0.0"
}
```

## Safety Features

### 1. Backups
Every fix creates a backup:
```
.validation-backups/
├── plugin.json.20260130_153000.bak
├── hooks.json.20260130_153030.bak
└── ...
```

### 2. Git Commits
Each fix creates a separate commit:
```
fix(plugin): Transform author string to object
fix(plugin): Remove unsupported keys from plugin.json
fix(plugin): Generate missing hook scripts
```

Easy rollback:
```bash
git log --oneline | head -5
git revert <commit-hash>
```

### 3. Re-validation
After fixes, re-runs validation to confirm success.

### 4. Dry Run Mode
Preview changes without applying:
```bash
/fix-plugin --dry-run
```

## Example Sessions

### Example 1: Quick Fix

```bash
/fix-plugin
```

Output:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔧 Plugin Auto-Fixer
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[auto-fixer] Auto-fix threshold: 0.9
[auto-fixer] Checking author field format...
[auto-fixer] Issue detected: author is string
✅ Fixed: Author transformed to object format
✅ Git commit created: a1b2c3d

[auto-fixer] Checking for unsupported keys...
✅ All checks passed

[auto-fixer] Checking script permissions...
⚠️  Script not executable: scripts/hooks/session-start.sh
✅ Made executable: scripts/hooks/session-start.sh
✅ Git commit created: e4f5g6h

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Summary:
  Issues found: 2
  Fixes applied: 2
  Fixes skipped: 0

✅ Auto-fix completed successfully

Next steps:
  1. Review changes: git diff
  2. Validate: ./scripts/validation/pre-commit-validator.sh
  3. Test the plugin
```

### Example 2: Dry Run

```bash
/fix-plugin --dry-run
```

Output:
```
⚠️  DRY RUN MODE - No changes will be applied

[auto-fixer] Issue detected: author is string
⚠️  DRY RUN: Would transform author string to object

[auto-fixer] Issue detected: Missing hook scripts
⚠️  DRY RUN: Would generate: ./scripts/hooks/pre-tool-use/context-tracker.sh

Summary:
  Issues found: 2
  Fixes applied: 0 (dry run)
```

### Example 3: Lower Threshold

```bash
/fix-plugin --threshold 0.7
```

Output:
```
[auto-fixer] Auto-fix threshold: 0.7

... (applies more fixes with confidence >= 0.7)

[auto-fixer] Missing hook script detected
⚠️  Fix requires approval (confidence: 0.85)
   Generate: ./scripts/hooks/pre-tool-use/context-tracker.sh

   Apply this fix? [y/N]: y

✅ Generated: ./scripts/hooks/pre-tool-use/context-tracker.sh
```

## Configuration

Fix behavior in `config/auto-commit-config.json`:

```json
{
  "auto_fix": {
    "enabled": true,
    "high_confidence_threshold": 0.9,
    "approval_required_threshold": 0.7,
    "create_git_commits": true,
    "backup_before_fix": true
  }
}
```

## Environment Variables

```bash
# Dry run mode
DRY_RUN=true /fix-plugin

# Change auto-fix threshold
AUTO_FIX_THRESHOLD=0.7 /fix-plugin

# Disable backups
CREATE_BACKUPS=false /fix-plugin

# Disable git commits
CREATE_GIT_COMMITS=false /fix-plugin
```

## When to Use

**Use /fix-plugin when:**
- ✅ After validation shows errors
- ✅ Plugin fails to load with manifest errors
- ✅ You want quick fixes for common issues
- ✅ Setting up plugin from scratch
- ✅ After major refactoring

**Don't use when:**
- ❌ You have uncommitted work you want to keep separate
- ❌ Issues require manual judgment
- ❌ You need to understand root cause first

## Technical Details

**Implementation:**
- Executes `scripts/validation/auto-fixer.sh`
- Parses options to configure behavior
- Runs fixes in priority order
- Creates individual git commits for each fix
- Returns detailed fix report

**Files Modified:**
- `.claude-plugin/plugin.json` - Manifest fixes
- `hooks/hooks.json` - Hook configuration fixes
- `scripts/**/*.sh` - Script generation and permissions
- Config files - JSON formatting

**Fix Priority Order:**
1. Author string → object (critical)
2. Remove unsupported keys (critical)
3. Fix script permissions (high)
4. Format JSON files (medium)
5. Generate missing scripts (medium)

## Rollback

Each fix creates a git commit for easy rollback:

```bash
# List recent fix commits
git log --oneline | grep "fix(plugin)" | head -5

# Rollback specific fix
git revert <commit-hash>

# Rollback all fixes
git log --oneline | grep "fix(plugin)" | \
  awk '{print $1}' | xargs git revert
```

Or use backups:
```bash
# Restore from backup
cp .validation-backups/plugin.json.20260130_153000.bak .claude-plugin/plugin.json
```

## Integration

Works seamlessly with:
- `/validate-plugin` - Detects issues
- `plugin-diagnostician` - Analyzes root causes
- `/save-plugin` - Commits fixes
- Pre-commit hook - Prevents unfixed issues

## See Also

- `/validate-plugin` - Detect issues
- `scripts/validation/auto-fixer.sh` - Fix implementation
- `SELF-IMPROVEMENT.md` - Architecture docs
