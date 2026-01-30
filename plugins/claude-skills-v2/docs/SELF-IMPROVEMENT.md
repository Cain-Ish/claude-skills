# Self-Improvement Architecture

The claude-skills-v2 plugin now has comprehensive self-improvement capabilities to detect, diagnose, and fix its own structural issues.

## Overview

This system enables the plugin to:
1. ✅ **Validate** its own structure before commits (pre-commit hook)
2. ✅ **Diagnose** problems when they occur (diagnostic agent)
3. 🚧 **Auto-fix** common problems (with safety gates) [Planned]
4. 🚧 **Learn** from development mistakes (meta-learning) [Planned]

## Implemented Components (Phase 1 & 2)

### Tier 1: Prevention (Pre-commit Validation)

**Pre-Commit Validator** - `scripts/validation/pre-commit-validator.sh`
- Validates plugin.json schema and structure
- Checks hooks.json for valid hook types and existing scripts
- Verifies agent files have proper frontmatter
- Validates config JSON syntax
- Returns actionable error messages with file:line references

**Script Checker** - `scripts/validation/script-checker.sh`
- Parses hooks.json to find all referenced scripts
- Checks if each script exists and is executable
- Can generate missing scripts from templates (`--generate` flag)
- Shows hook type and purpose for context

**Hook Script Templates** - `scripts/validation/templates/`
- `pretooluse-template.sh` - Template for PreToolUse hooks
- `posttooluse-template.sh` - Template for PostToolUse hooks
- `generic-hook-template.sh` - Template for lifecycle hooks

### Missing Hook Scripts (Now Created)

**1. Context Tracker** - `scripts/hooks/pre-tool-use/context-tracker.sh`
- Tracks all tool usage for the learning engine
- Logs to `~/.claude/claude-skills/context/tool-usage.jsonl`
- Always returns `permissionDecision: allow` (passive tracking)

**2. Write Validation** - `scripts/hooks/pre-tool-use/write-validation.sh`
- Prevents writing .env files with secrets
- Warns against unnecessary .md documentation files
- Blocks writes to sensitive system locations
- Validates against security anti-patterns

**3. Edit Validation** - `scripts/hooks/pre-tool-use/edit-validation.sh`
- Prevents editing files with secrets
- Blocks modifications to sensitive system files
- Warns about editing critical dependency files
- Detects removal of security-related code

**4. Bash Feedback** - `scripts/hooks/post-tool-use/bash-feedback.sh`
- Provides contextual feedback on bash command execution
- Logs commands for learning engine pattern detection
- Generates helpful messages based on exit codes
- Tracks common workflows (git, npm, docker, testing)

### Tier 2: Detection (Runtime Diagnostics)

**Plugin Diagnostician Agent** - `agents/diagnostics/plugin-diagnostician.md`
- Auto-invokes on plugin load errors and validation failures
- Reads error logs and validation output
- Identifies root causes of issues
- Classifies issues by impact (Critical/High/Medium/Low)
- Generates fix proposals with confidence scores (0.0-1.0)
- Outputs structured diagnostic reports

**Validate Plugin Command** - `commands/validate-plugin.md`
- User-invocable command: `/validate-plugin`
- Options: `--manifest`, `--hooks`, `--agents`, `--config`, `--verbose`
- Runs comprehensive validation checks
- Shows formatted output with errors and warnings
- Integration point for auto-fix (with `--fix` flag, planned)

## Validation Checks

### Plugin Manifest (plugin.json)
- ✅ Valid JSON syntax
- ✅ Required fields: name, version, description, author
- ✅ Author is object (not string)
- ✅ No unsupported keys
- ✅ Referenced hook/agent/skill files exist
- ✅ Agent/skill paths are valid

### Hooks Configuration (hooks.json)
- ✅ Valid JSON syntax
- ✅ Valid hook types (PreToolUse, PostToolUse, SessionStart, etc.)
- ✅ Each hook has required fields (matcher, hooks array)
- ✅ All referenced scripts exist
- ✅ Scripts are executable

### Agent Files
- ✅ Have frontmatter (---...---)
- ✅ Required frontmatter fields (name, description)

### Config Files
- ✅ Valid JSON syntax

## Error Classification

### 🔴 Errors (Block Commits)
- Invalid JSON syntax
- Missing required fields
- Referenced files don't exist
- Invalid hook types
- Unsupported manifest keys

### ⚠️ Warnings (Allow with Notice)
- Agent missing frontmatter
- Empty directories referenced
- Scripts not executable

## Usage

### Manual Validation

```bash
# Run full validation
./scripts/validation/pre-commit-validator.sh

# Check for missing scripts
./scripts/validation/script-checker.sh

# Generate missing scripts from templates
./scripts/validation/script-checker.sh --generate
```

### Via Command

```bash
# User runs validation command
/validate-plugin

# Validate specific component
/validate-plugin --manifest
/validate-plugin --hooks --verbose

# Auto-fix issues (planned)
/validate-plugin --fix
```

### Automatic Validation

Pre-commit git hook (to be installed via `install.sh`):
- Runs before every git commit
- Blocks commits if validation fails
- Shows actionable error messages

## File Structure

```
claude-skills/plugins/claude-skills-v2/
├── .claude-plugin/
│   └── plugin.json                     # Plugin manifest
├── hooks/
│   └── hooks.json                      # Hook configuration
├── agents/
│   ├── diagnostics/
│   │   └── plugin-diagnostician.md     # Diagnostic agent
│   └── ...
├── commands/
│   ├── validate-plugin.md              # Validation command
│   └── ...
├── scripts/
│   ├── hooks/
│   │   ├── pre-tool-use/
│   │   │   ├── context-tracker.sh      # ✅ NEW
│   │   │   ├── write-validation.sh     # ✅ NEW
│   │   │   ├── edit-validation.sh      # ✅ NEW
│   │   │   └── bash-validation.sh
│   │   └── post-tool-use/
│   │       ├── bash-feedback.sh        # ✅ NEW
│   │       ├── observation-logger.sh
│   │       └── auto-format.sh
│   └── validation/                     # ✅ NEW
│       ├── pre-commit-validator.sh     # ✅ Main validator
│       ├── script-checker.sh           # ✅ Script existence checker
│       └── templates/                  # ✅ Hook templates
│           ├── pretooluse-template.sh
│           ├── posttooluse-template.sh
│           └── generic-hook-template.sh
└── docs/
    └── SELF-IMPROVEMENT.md             # This file
```

## Next Steps (Phase 3 - Planned)

### Auto-Fix System
- **plugin-fixer agent** - Applies fixes with confidence-based approval
- **auto-fixer.sh script** - Implements common fixes
- **fix-plugin command** - Interactive fixing wizard
- **Git commit integration** - All fixes create rollback points

**Fix Confidence Levels:**
- **0.9+ (High)**: Auto-apply
  - Transform author string → object
  - Remove unsupported keys
  - Generate missing scripts
  - Fix file permissions
- **0.7-0.9 (Medium)**: Ask user
  - Generate complex hook scripts
  - Update deprecated config
- **<0.7 (Low)**: Suggest only
  - Refactor complex logic

### Meta-Learning (Phase 4 - Planned)
- **meta-learner agent** - Learns from plugin development patterns
- **Enhanced observation-logger** - Tracks plugin development events
- **Instinct creation** - Prevents recurring mistakes

## Current Status

✅ **Phase 1 Complete**: Validation infrastructure and missing scripts
✅ **Phase 2 Complete**: Diagnostic capabilities
🚧 **Phase 3 Planned**: Auto-fix system
🚧 **Phase 4 Planned**: Meta-learning

## Validation Results

Current plugin status:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 Claude Skills v2 - Pre-Commit Validation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 Validating plugin.json... ✓
🪝 Validating hooks.json... ✓
🤖 Validating agent files... ✓
⚙️  Validating config files... ✓

Summary:
  ✓ Checks passed: 30
  ⚠ Warnings: 1 (instinct-critic.md missing frontmatter)

✅ Pre-commit validation passed
```

All referenced hook scripts exist and are executable.

## Benefits

1. **Catch issues early** - Pre-commit hook prevents broken commits
2. **Self-diagnosis** - Plugin can identify its own problems
3. **Clear error messages** - File:line references for easy fixing
4. **Template generation** - Missing scripts can be auto-generated
5. **Validation command** - Users can validate on-demand
6. **Confidence-based fixes** - Future auto-fix will be safe and transparent

## Design Principles

1. **Safety first** - Validation never modifies files (only checks)
2. **Clear output** - Errors show file:line and actionable fixes
3. **Fail fast** - Pre-commit catches issues before they propagate
4. **Self-documenting** - Templates have TODO comments for guidance
5. **Modular design** - Each validator is independent and testable
6. **Confidence scores** - Future fixes rated by confidence (0.0-1.0)
