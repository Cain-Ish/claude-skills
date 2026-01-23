# Self-Debugger Development Guide

## Current Status

✅ **Phase 1: Foundation (Complete)**
- Plugin structure created
- Common library adapted from process-janitor
- Rule engine framework implemented
- Two core rules defined (hook-session-start, plugin-schema)
- Scan plugins script created
- SessionStart hook implemented

✅ **Phase 2: Background Monitor (Complete)**
- Background monitor with 5-minute scan intervals
- Graceful shutdown on session end
- Heartbeat tracking for liveness
- Session state management

## Next Steps

### 1. Implement Validation Check Execution

**File**: `plugins/self-debugger/scripts/lib/rule-engine.sh`
**Function**: `execute_validation_check()`
**Line**: ~102

This is the core validation logic that executes individual checks against files. You need to implement:

```bash
execute_validation_check() {
    local check_json="$1"
    local file_path="$2"
    local plugin_name="$3"

    # Extract check parameters using jq
    local check_type=$(echo "$check_json" | jq -r '.type')

    case "$check_type" in
        "regex")
            # Read file content
            # Test pattern match
            # Return 0 if matches, 1 if not
            ;;
        "json-field")
            # Extract field from JSON
            # Validate required/pattern
            # Return 0 if valid, 1 if not
            ;;
        "structure")
            # Check file/directory structure
            # Return 0 if valid, 1 if not
            ;;
        *)
            log_warn "Unknown check type: $check_type"
            return 0
            ;;
    esac
}
```

**Example Implementation for Regex Check**:

```bash
"regex")
    local pattern
    pattern=$(echo "$check_json" | jq -r '.pattern')

    if [[ ! -f "$file_path" ]]; then
        return 1  # File doesn't exist = violation
    fi

    # Read file content
    local content
    content=$(cat "$file_path")

    # Test pattern (use grep for better multiline support)
    if echo "$content" | grep -qE "$pattern"; then
        return 0  # Valid
    else
        return 1  # Violation
    fi
    ;;
```

**Example Implementation for JSON Field Check**:

```bash
"json-field")
    local field
    field=$(echo "$check_json" | jq -r '.field')
    local required
    required=$(echo "$check_json" | jq -r '.required // false')
    local pattern
    pattern=$(echo "$check_json" | jq -r '.pattern // ""')

    # Extract field value
    local value
    value=$(extract_json_field "$file_path" "$field")

    # Check required
    if [[ "$required" == "true" ]] && [[ -z "$value" ]]; then
        return 1  # Required field missing
    fi

    # Check pattern if provided
    if [[ -n "$pattern" ]] && [[ -n "$value" ]]; then
        if ! echo "$value" | grep -qE "$pattern"; then
            return 1  # Pattern mismatch
        fi
    fi

    return 0  # Valid
    ;;
```

### 2. Test the Implementation

After implementing `execute_validation_check()`:

```bash
# 1. Start Claude Code in the claude-skills repo
cd /path/to/claude-skills

# 2. SessionStart hook should auto-launch monitor
# Check monitor is running:
ps aux | grep start-monitor.sh

# 3. Wait 5 seconds for first scan
sleep 5

# 4. Check for detected issues
cat ~/.claude/self-debugger/findings/issues.jsonl

# 5. Use /debug command to view issues
# In Claude Code:
/debug
```

### 3. Create Test Cases

Create intentional violations to test detection:

**Test Case 1**: Hook without frontmatter

```bash
# Create test hook without frontmatter
cat > plugins/reflect/hooks/TestHook.md <<'EOF'
# Test Hook

This hook is missing frontmatter (intentional violation).
EOF

# Run scan
./plugins/self-debugger/scripts/scan-plugins.sh

# Verify issue detected
cat ~/.claude/self-debugger/findings/issues.jsonl | grep TestHook
```

**Test Case 2**: Plugin with missing version

```bash
# Create test plugin with incomplete manifest
mkdir -p plugins/test-plugin/.claude-plugin
cat > plugins/test-plugin/.claude-plugin/plugin.json <<'EOF'
{
  "name": "test-plugin",
  "description": "Test plugin"
}
EOF

# Run scan
./plugins/self-debugger/scripts/scan-plugins.sh

# Verify violation detected
cat ~/.claude/self-debugger/findings/issues.jsonl | grep "has-required-version"
```

### 4. Phase 3: Fix Generation (Next Major Phase)

After validation works correctly, implement:

1. **Git utilities** (`scripts/lib/git-utils.sh`):
   - Source repo detection
   - Branch locking (5-layer safety)
   - Feature branch creation
   - Commit with session tracking

2. **Debugger agents**:
   - `debugger-fixer` agent (generates fixes)
   - `debugger-critic` agent (validates fixes, scores 0-100)

3. **Fix scripts**:
   - `generate-fix.sh` (invokes agents, returns proposal)
   - `apply-fix.sh` (creates branch, commits, pushes)

4. **Enhanced /debug command**:
   - `/debug fix [issue-id]` fully functional
   - Dry-run mode for testing

## Implementation Tips

### For `execute_validation_check()`

1. **Start simple**: Implement regex checks first (most rules use this)
2. **Use existing utilities**: `extract_json_field()` and `extract_json_number()` from common.sh
3. **Handle errors gracefully**: Return 0 (valid) on errors to avoid false positives
4. **Support multiline patterns**: Use `grep -Pzo` or read entire file content
5. **Log debug info**: Use `log_debug` to trace validation decisions

### For Testing

1. **Create intentional violations**: Easier to verify detection works
2. **Check JSONL format**: Use `jq` to pretty-print issues file
3. **Monitor logs**: Background monitor logs to `~/.claude/self-debugger/sessions/*/scan-*.log`
4. **Verify rule loading**: Enable VERBOSE mode to see which rules are loaded

### For Rules

1. **Keep rules simple**: Start with obvious violations (missing frontmatter, missing fields)
2. **High confidence for strict rules**: Use 0.9+ confidence for error-level rules
3. **Document patterns**: Add comments explaining regex patterns
4. **Test against real plugins**: Run scan against reflect and process-janitor

## Common Issues

### Monitor doesn't start

- Check SessionStart hook runs: Add debug echo statements
- Verify source repo detection: Check `.git` exists and `plugins/` directory present
- Check script permissions: All scripts should be executable (`chmod +x`)

### No issues detected

- Verify rules loaded: Check `rules/core/` contains JSON files
- Enable verbose logging: `export DEBUGGER_VERBOSE=true`
- Check `execute_validation_check()` implementation: Add log statements

### Issues file empty

- Check write permissions on `~/.claude/self-debugger/`
- Verify `append_jsonl()` works: Test with echo command
- Check `record_issue()` called: Add debug logs in scan-plugins.sh

## Architecture Decisions

### Why JSONL for issues?

- Append-only: No concurrent write conflicts
- Queryable: Use `grep`, `jq`, or `tail` for analysis
- Preserves history: Full audit trail for effectiveness tracking

### Why separate rule types?

- **Core rules**: Trusted, never auto-modified
- **Learned rules**: Start with lower confidence, validated over time
- **External rules**: Web-discovered, require validation

### Why background monitor?

- Non-blocking: Session starts immediately
- Continuous detection: Finds issues as code changes
- Resource-efficient: 5-minute intervals balance responsiveness vs. CPU usage

## Resources

- **process-janitor plugin**: Reference for locking, logging, and JSONL patterns
- **reflect plugin**: Reference for agent design and metrics tracking
- **Plan document**: Full architecture and phase breakdown
- **Claude Code docs**: Plugin API and hook specifications

## Phase 4 & 5: Self-Improvement and Web Discovery

These phases are now complete! Here's how to use them:

### Self-Improvement Workflow

```bash
# 1. Apply several fixes (minimum 5 per rule for meaningful data)
/debug fix [issue-id]
/debug fix [issue-id]
# ... repeat

# 2. Run self-improvement analysis
/self-improve

# 3. Review confidence adjustments
git diff plugins/self-debugger/rules/core/

# 4. Check health score
cat ~/.claude/self-debugger/metrics.jsonl | tail -1 | jq .

# 5. Merge self-improvement branch after review
git checkout debug/self-debugger/confidence-adjustment
git log -1  # Review changes
# Create MR for review
```

### Web Discovery Workflow

```bash
# 1. Run web discovery (requires WebSearch tool)
/self-improve web

# 2. Check external rules created
ls -la plugins/self-debugger/rules/external/

# 3. Review discovered patterns
cat plugins/self-debugger/rules/external/*.json | jq .

# 4. Validate external rules with scans
./plugins/self-debugger/scripts/scan-plugins.sh

# 5. Promote high-confidence rules to core
# (manually review and move from external/ to core/)
```

### Confidence Adjustment Algorithm

Rules are adjusted based on approval rates:

```bash
# High approval (≥90%)
confidence += 0.05

# Low approval (≤30%)
confidence -= 0.10

# Medium approval
confidence -= 0.02
```

Constraints:
- Minimum 5 detections required
- Confidence clamped to 0.1-1.0
- Changes go to feature branches

### Health Score Formula

```
health_score = resolution_rate - false_positive_rate

Where:
  resolution_rate = (resolved_issues / total_issues) * 100
  false_positive_rate = (issues_pending_>7_days / total_issues) * 100
```

Healthy plugin: Score ≥ 70

### Web Discovery Confidence

```
base_confidence = 0.5

if official_source:
    confidence = 0.8

if has_code_examples:
    confidence += 0.1

max_confidence = 0.95  # Never full confidence for web sources
```

## Questions?

If you get stuck, check:

1. Logs in `~/.claude/self-debugger/sessions/[session-id]/`
2. Issue records in `~/.claude/self-debugger/findings/issues.jsonl`
3. Rule files in `plugins/self-debugger/rules/core/`
4. Metrics in `~/.claude/self-debugger/metrics.jsonl`
5. Web cache in `~/.claude/self-debugger/web-search-cache/`
6. This development guide (DEVELOPMENT.md)
