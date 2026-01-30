---
name: validate-plugin
description: Validate plugin structure, manifest, hooks, agents, and configuration
usage: /validate-plugin [--manifest] [--hooks] [--agents] [--config] [--fix] [--verbose]
examples:
  - /validate-plugin
  - /validate-plugin --manifest
  - /validate-plugin --hooks --verbose
  - /validate-plugin --fix
---

# /validate-plugin - Plugin Structure Validation

Comprehensive validation of the claude-skills-v2 plugin structure to catch issues before they cause problems.

## What This Does

1. **Validates plugin.json** - Schema, required fields, file references
2. **Validates hooks.json** - Structure, script existence, hook types
3. **Validates agent files** - Frontmatter, required fields
4. **Validates config files** - JSON syntax
5. **Checks for common issues** - Missing scripts, invalid paths, unsupported keys

## Usage

```bash
# Full validation (all checks)
/validate-plugin

# Validate only manifest
/validate-plugin --manifest

# Validate only hooks
/validate-plugin --hooks

# Validate only agents
/validate-plugin --agents

# Validate only config
/validate-plugin --config

# Show detailed output
/validate-plugin --verbose

# Auto-fix issues (high-confidence fixes only)
/validate-plugin --fix
```

## Validation Checks

### Plugin Manifest (plugin.json)

- ✅ Valid JSON syntax
- ✅ Required fields: name, version, description, author
- ✅ Author is object (not string)
- ✅ No unsupported keys
- ✅ Referenced files exist (hooks, agents, skills)
- ✅ Agent paths are valid
- ✅ Skills paths are valid

### Hooks Configuration (hooks.json)

- ✅ Valid JSON syntax
- ✅ Valid hook types (PreToolUse, PostToolUse, SessionStart, etc.)
- ✅ Each hook has required fields (matcher, hooks array, type, command)
- ✅ All referenced scripts exist
- ✅ Scripts are executable

### Agent Files

- ✅ Have frontmatter (---...---)
- ✅ Required frontmatter fields (name, description)
- ✅ Valid markdown syntax

### Config Files

- ✅ Valid JSON syntax
- ✅ Required sections present

## Error Types

### 🔴 Errors (Must Fix)
- Invalid JSON syntax
- Missing required fields
- Referenced files don't exist
- Invalid hook types
- Unsupported manifest keys

### ⚠️ Warnings (Should Fix)
- Agent missing frontmatter
- Empty directories referenced
- Scripts not executable

## Auto-Fix Capability

When using `--fix`:

**High-Confidence Fixes (Auto-Applied):**
- Transform author string → object
- Remove unsupported keys from manifest
- Fix file permissions (chmod +x)
- Generate missing scripts from templates

**Medium-Confidence (Asks Permission):**
- Generate missing hook scripts
- Update deprecated configuration

**Low-Confidence (Suggest Only):**
- Complex structural issues
- Refactoring recommendations

## Examples

### Example 1: Quick Health Check

```bash
/validate-plugin
```

Output:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 Claude Skills v2 - Plugin Validation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 Validating plugin.json... ✓
🪝 Validating hooks.json... ✓
🤖 Validating agent files... ✓
⚙️  Validating config files... ✓

Summary:
  ✓ Checks passed: 29
  ✗ Checks failed: 0
  ⚠ Warnings: 1

✅ Plugin validation passed
```

### Example 2: Fix Issues Automatically

```bash
/validate-plugin --fix
```

Output:
```
🔍 Detecting issues...

Found fixable issues:
  🔴 Author field is string (should be object)
  🔴 Missing script: ./scripts/hooks/pre-tool-use/context-tracker.sh
  ⚠️  Script not executable: ./scripts/hooks/session-start.sh

Applying fixes:
  ✅ Transformed author to object format
  ✅ Generated missing script from template
  ✅ Made scripts executable (chmod +x)

Re-validating...
✅ All issues fixed! Plugin is now valid.
```

### Example 3: Verbose Output

```bash
/validate-plugin --verbose
```

Shows detailed information about each check, file paths, and validation logic.

## Integration

This command uses:
- `scripts/validation/pre-commit-validator.sh` - Core validation logic
- `scripts/validation/script-checker.sh` - Script existence checks
- `scripts/validation/auto-fixer.sh` - Auto-fix implementation (when --fix used)

## When to Use

- **Before commits** - Catch issues early
- **After editing manifest** - Verify changes are valid
- **After adding hooks** - Ensure scripts exist
- **After adding agents** - Verify frontmatter
- **Plugin development** - Continuous validation
- **CI/CD** - Automated quality checks

## Technical Details

**Implementation:**
- Executes `scripts/validation/pre-commit-validator.sh`
- Parses options to filter validation checks
- With `--fix`: runs `scripts/validation/auto-fixer.sh` for repairs
- Returns structured output (errors, warnings, summary)

**Files Used:**
- `scripts/validation/pre-commit-validator.sh` - Main validator
- `scripts/validation/script-checker.sh` - Script existence checks
- `scripts/validation/auto-fixer.sh` - Auto-fix logic (when --fix used)
- `scripts/validation/templates/*.sh` - Templates for missing scripts

## Implementation Instructions

When user runs `/validate-plugin`:

1. Parse arguments to determine which validation to run
2. Execute the pre-commit-validator.sh script with appropriate flags
3. Display formatted output to user
4. If --fix flag present, run auto-fixer after showing issues
5. Re-validate after fixes and show results

```bash
# Basic implementation
PLUGIN_DIR="$(pwd)/claude-skills/plugins/claude-skills-v2"
cd "$PLUGIN_DIR"
./scripts/validation/pre-commit-validator.sh
```

## See Also

- `/fix-plugin` - Interactive fixing wizard (to be implemented)
- Pre-commit hook - Automatic validation before git commits
