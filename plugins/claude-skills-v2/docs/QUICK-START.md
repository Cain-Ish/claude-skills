# Quick Start: Self-Improvement Features

The claude-skills-v2 plugin now includes powerful self-improvement and auto-commit features.

## 🚀 Immediate Benefits

1. **Auto-commit** prevents data loss during plugin development
2. **Validation** catches issues before they cause problems
3. **Diagnostics** identifies root causes when errors occur
4. **Hook scripts** provide intelligent safety checks

## ⚡ Quick Commands

### Validate Your Plugin

```bash
# Full validation
/validate-plugin

# Quick health check
cd claude-skills/plugins/claude-skills-v2
./scripts/validation/pre-commit-validator.sh
```

### Save Your Work

```bash
# Manual save (local commit)
/save-plugin

# Save and push to GitHub
/save-plugin --push

# Save with custom message
/save-plugin --message "Implemented new feature"
```

### Check for Missing Scripts

```bash
cd claude-skills/plugins/claude-skills-v2
./scripts/validation/script-checker.sh

# Generate missing scripts from templates
./scripts/validation/script-checker.sh --generate
```

## 🛡️ Safety Features Active

### PreToolUse Hooks (Prevent Mistakes)

1. **Context Tracker** - Logs all tool usage for learning
2. **Write Validation** - Blocks writing secrets to .env files
3. **Edit Validation** - Prevents editing sensitive system files
4. **Bash Validation** - Warns about dangerous commands

### PostToolUse Hooks (Learn & Improve)

1. **Observation Logger** - Tracks patterns for learning
2. **Auto-Format** - Formats code after edits
3. **Bash Feedback** - Provides helpful command feedback

### Lifecycle Hooks

1. **SessionEnd** - Auto-commits changes when session ends
2. **SessionStart** - Initializes and validates plugin
3. **Stop** - Extracts patterns and suggests reflection

## 📊 Current Status

```
✅ Plugin Structure: Valid
✅ All Hook Scripts: Present and executable (12/12)
✅ Validation Checks: 31 passed
⚠️  Warnings: 1 (non-critical)
✅ Auto-Commit: Enabled
✅ GitHub Sync: Ready
```

## 🔧 Configuration

### Enable/Disable Auto-Commit

Edit `config/auto-commit-config.json`:

```json
{
  "auto_commit": {
    "enabled": true,           // Set to false to disable
    "min_interval_seconds": 300,  // 5 minutes minimum
    "auto_push": false         // Set to true for auto-push
  }
}
```

### Environment Variables

```bash
# Disable auto-commit temporarily
export AUTO_COMMIT_ENABLED=false

# Enable auto-push
export AUTO_PUSH=true

# Change minimum interval (seconds)
export AUTO_COMMIT_MIN_INTERVAL=600  # 10 minutes
```

## 🎯 Common Workflows

### Workflow 1: Active Development

```bash
# Work on plugin features...
# Changes are validated and saved automatically on SessionEnd

# Manual checkpoint
/save-plugin

# Push to GitHub when ready
/save-plugin --push
```

### Workflow 2: Before Committing

```bash
# Validate before creating manual commit
/validate-plugin

# If validation passes, commit normally
git add .
git commit -m "Your message"
git push
```

### Workflow 3: After Editing Manifest

```bash
# Edit plugin.json or hooks.json
# Validate immediately
/validate-plugin --manifest --hooks

# If errors found, run diagnostics
# The plugin-diagnostician agent will auto-invoke
```

## 🔍 Troubleshooting

### "Validation failed but auto-committed anyway"

This is normal! Auto-commit prioritizes data safety over perfection.
- Run `/validate-plugin` to see specific errors
- Fix the issues
- The next commit will be clean

### "No changes to commit"

All changes are already saved. Check:
```bash
git status
git log -1
```

### "Failed to push to remote"

Common causes:
1. No network connection
2. Need to authenticate with GitHub
3. Remote has newer changes (need to pull first)

Solution:
```bash
git pull origin master --rebase
git push origin master
```

## 📚 Documentation

- **SELF-IMPROVEMENT.md** - Full architecture documentation
- **/validate-plugin** - Validation command docs
- **/save-plugin** - Auto-commit command docs
- **scripts/validation/** - Validator implementations

## 🆘 Getting Help

If you encounter issues:

1. Run validation: `/validate-plugin --verbose`
2. Check diagnostics (auto-invokes on errors)
3. Review error logs
4. Consult SELF-IMPROVEMENT.md for details

## ✨ New Features Summary

| Feature | Status | Usage |
|---------|--------|-------|
| Pre-commit Validation | ✅ Active | Automatic on commit |
| Auto-commit System | ✅ Active | SessionEnd + Manual |
| Plugin Diagnostician | ✅ Active | Auto on errors |
| Missing Script Detection | ✅ Ready | /validate-plugin |
| Hook Templates | ✅ Ready | script-checker --generate |
| /validate-plugin Command | ✅ Ready | On-demand validation |
| /save-plugin Command | ✅ Ready | Manual save/push |

## 🎉 What's Next

**Coming in Phase 3:**
- Auto-fix system (fixes applied with confidence scores)
- Interactive fix wizard (/fix-plugin command)
- Git commit integration (automatic rollback points)

**Coming in Phase 4:**
- Meta-learning from plugin development
- Pattern-based instinct creation
- Prevents recurring mistakes

---

**Your plugin is now self-aware and actively preventing issues!** 🚀
