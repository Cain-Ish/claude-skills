# Version Management for Claude Code Plugins

This document describes version management best practices for plugins in the claude-skills repository.

## Semantic Versioning

All plugins follow [Semantic Versioning 2.0.0](https://semver.org/):

```
MAJOR.MINOR.PATCH

Example: 1.2.3
         │ │ │
         │ │ └─ PATCH: Bug fixes, docs, corrections
         │ └─── MINOR: New features (backward-compatible)
         └───── MAJOR: Breaking changes
```

## When to Bump Versions

### PATCH Version (X.X.PATCH)

Increment for bug fixes and non-functional changes:
- **Bug fixes** - Correcting errors in existing functionality
- **Documentation** - README updates, comment improvements
- **Schema compliance** - Fixing plugin.json validation issues
- **Hook corrections** - Adding missing frontmatter, fixing syntax
- **Refactoring** - Internal improvements without behavior changes

**Examples**:
- 1.0.0 → 1.0.1: Fix missing YAML frontmatter in hook
- 1.0.1 → 1.0.2: Add missing README.md file
- 1.0.2 → 1.0.3: Correct plugin.json license field

### MINOR Version (X.MINOR.0)

Increment for new features that are backward-compatible:
- **New hooks** - Adding SessionEnd, Stop, PreToolUse hooks
- **New agents** - Adding specialized agent definitions
- **New commands** - Adding slash commands
- **New skills** - Adding user-invocable skills
- **Enhanced functionality** - New options, configuration, capabilities

**Examples**:
- 1.0.3 → 1.1.0: Add new /debug scan command
- 1.1.0 → 1.2.0: Add debugger-critic agent
- 1.2.0 → 1.3.0: Add web discovery functionality

### MAJOR Version (MAJOR.0.0)

Increment for breaking changes:
- **API changes** - Incompatible tool interfaces
- **Removed features** - Deleted commands, agents, or functionality
- **Renamed components** - Changed hook names, command names
- **Configuration changes** - Incompatible config file formats

**Examples**:
- 1.3.0 → 2.0.0: Rename /debug command to /validate
- 2.0.0 → 3.0.0: Remove deprecated fix-all command
- 3.0.0 → 4.0.0: Change rule schema format (breaking)

## Self-Debugger Automated Fixes

When self-debugger applies automated fixes:

### Default Bump: PATCH

Self-debugger fixes are usually bug fixes (PATCH bumps):
- Schema violations → PATCH
- Missing documentation → PATCH
- Incorrect frontmatter → PATCH
- Code quality issues → PATCH

### Manual Review Required

Some fixes may warrant MINOR or MAJOR bumps:
- **Agent reviews** should identify if fix changes behavior (MINOR)
- **Human reviewers** can override version bump in MR review

## Version Bumping Process

### 1. Manual Changes (Human Developers)

When making changes:
```bash
# 1. Edit files
vim plugins/my-plugin/hooks/NewHook.md

# 2. Update version in plugin.json
vim plugins/my-plugin/.claude-plugin/plugin.json
# Change: "version": "1.0.0" → "1.1.0" (new hook = MINOR)

# 3. Commit with version in message
git commit -m "Add NewHook.md (v1.1.0)

- Adds PreToolUse hook for validation
- Bump version: 1.0.0 → 1.1.0 (MINOR: new feature)
"
```

### 2. Self-Debugger Automated Fixes

Self-debugger **automatically** bumps versions:
```bash
# debugger-fixer agent:
# 1. Loads current version from plugin.json
# 2. Determines bump type (usually PATCH for fixes)
# 3. Includes version update in fix diff
# 4. Commits with version tracking

# Example commit:
Fix missing frontmatter in SessionStart hook (v1.0.1)

Issue: abc123-...
Rule: hook-session-start-valid

Applied fix:
- Prepended YAML frontmatter
- Bump version: 1.0.0 → 1.0.1 (PATCH: bug fix)
```

### 3. Version Verification

Check version consistency:
```bash
# All plugins should have valid semver versions
grep -r '"version"' plugins/*/. claude-plugin/plugin.json

# Verify no duplicate versions across plugins (each plugin independent)
jq -r '.version' plugins/*/.claude-plugin/plugin.json | sort
```

## Best Practices

### DO ✅

- **Bump on every change** - No commits without version updates
- **Document bump type** - Explain why MAJOR/MINOR/PATCH in commit
- **Follow semver strictly** - Breaking change = MAJOR, feature = MINOR
- **Start at 1.0.0** - Mature plugins should be 1.x.x
- **Use 0.x.x for experimental** - Pre-release plugins only

### DON'T ❌

- **Don't skip versions** - 1.0.0 → 1.0.2 (missing 1.0.1)
- **Don't downgrade** - 1.2.0 → 1.1.0 (never go backwards)
- **Don't reuse versions** - Delete tags if you need to redo a release
- **Don't forget to bump** - Every fix needs a version bump
- **Don't mix bump types** - PATCH fix shouldn't include MINOR features

## Tools and Automation

### Self-Debugger Rules

The self-debugger can validate version management:
- Checks semver format in plugin.json (already implemented)
- Future: Detect version bumps in commits
- Future: Validate changelog entries match versions

### Git Hooks

Consider adding pre-commit hooks:
```bash
# Check if plugin.json changed but version didn't bump
# Warn if commit message doesn't mention version
```

## FAQs

**Q: Do I need to bump version for typo fixes in README?**
A: Yes. PATCH bump (documentation change).

**Q: What if I'm just refactoring without changing behavior?**
A: PATCH bump (internal improvement).

**Q: Can I make multiple PATCH fixes before releasing?**
A: Yes, but bump version on each commit. Example: 1.0.0 → 1.0.1 → 1.0.2 → 1.0.3

**Q: Should test-only changes bump version?**
A: Yes. Tests are part of the plugin. PATCH bump.

**Q: What about experimental branches?**
A: Use pre-release tags: 1.1.0-alpha, 1.1.0-beta, 1.1.0-rc.1

## References

- [Semantic Versioning 2.0.0](https://semver.org/)
- [Keep a Changelog](https://keepachangelog.com/)
- [Claude Code Plugin Marketplace](https://docs.anthropic.com/claude-code/plugins)

---

**Version**: This document is version-controlled. Last updated: 2026-01-23
