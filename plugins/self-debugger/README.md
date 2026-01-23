# Self-Debugger Plugin

A meta-plugin that monitors, debugs, and improves all plugins in the claude-skills repository by detecting issues, generating fixes, and committing them to feature branches.

## Overview

The self-debugger plugin provides:

- **Automatic monitoring**: Background scans every 5 minutes detect plugin issues
- **Rule-based validation**: Declarative rules check hooks, agents, skills, and plugin manifests
- **Source repo detection**: Only activates in the claude-skills source repository
- **Fix generation**: (Coming in Phase 3) AI-powered fix proposals with critic validation
- **Git integration**: (Coming in Phase 3) Feature branch commits for human review
- **Self-improvement**: (Coming in Phase 4) Learns from feedback and adjusts rules

## Architecture

```
SessionStart Hook
    ↓
Detect Source Repo (.git + plugins/ marker)
    ↓
Launch Background Monitor (non-blocking)
    ↓
Scan Every 5 Minutes → Load Rules → Detect Issues
    ↓
Store Findings (~/.claude/self-debugger/findings/issues.jsonl)
    ↓
Use /debug command to view and fix issues
```

## Installation

1. Clone or symlink this plugin to your Claude Code plugins directory:
   ```bash
   ln -s /path/to/claude-skills/plugins/self-debugger ~/.claude/plugins/self-debugger
   ```

2. Restart Claude Code or run `/plugins reload`

## Usage

### Automatic Monitoring

When you start Claude Code in the claude-skills repository:

1. SessionStart hook detects source repo
2. Background monitor launches (non-blocking)
3. First scan starts after 5 seconds
4. Subsequent scans every 5 minutes
5. Issues stored in `~/.claude/self-debugger/findings/issues.jsonl`

### Manual Commands

- `/debug` - Show detected issues and monitor status
- `/debug scan` - Force immediate scan (coming soon)
- `/debug fix [issue-id]` - Generate and apply fix (coming soon)

## Configuration

Default configuration at `~/.claude/self-debugger/config.json`:

```json
{
  "scan_interval_seconds": 300,
  "min_critic_score": 70,
  "max_fixes_per_session": 10,
  "stale_lock_threshold_minutes": 30,
  "auto_web_discovery": false
}
```

## Rules

Rules are stored in `rules/` directory:

- **`rules/core/`**: Hand-written rules, never auto-modified
- **`rules/learned/`**: Auto-discovered from codebase analysis
- **`rules/external/`**: Web-discovered patterns

### Current Rules

1. **`hook-session-start.json`**: Validates SessionStart hooks have proper YAML frontmatter
2. **`plugin-schema.json`**: Validates plugin.json follows marketplace schema

### Rule Schema

```json
{
  "rule_id": "unique-rule-id",
  "version": "1.0.0",
  "category": "hook-correctness",
  "severity": "error|warning|info",
  "confidence": 0.95,
  "applies_to": {
    "component": "hooks",
    "pattern": "SessionStart\\.md$"
  },
  "validation": {
    "type": "static",
    "checks": [
      {
        "check_id": "check-name",
        "type": "regex|json-field|structure",
        "pattern": "...",
        "error_message": "..."
      }
    ]
  },
  "fix_template": {
    "type": "prepend|append|replace|merge",
    "content": "..."
  },
  "references": ["https://docs.anthropic.com/..."],
  "learned_from": "manual|codebase|web_search",
  "last_updated": "2026-01-23"
}
```

## State Directory

State stored in `~/.claude/self-debugger/`:

```
~/.claude/self-debugger/
├── findings/
│   ├── issues.jsonl              # Detected issues
│   └── fixes.jsonl               # Applied fixes (Phase 3)
├── sessions/
│   └── [session-id]/
│       ├── monitor.pid           # Monitor process PID
│       ├── status.json           # Session status
│       ├── heartbeat.ts          # Liveness tracking
│       └── scan-*.log            # Scan logs
├── locks/                        # Branch locks (Phase 3)
└── metrics.jsonl                 # Self-improvement metrics
```

## Safety Mechanisms

1. **Source repo detection**: Only runs in claude-skills repo, not installed plugins
2. **Non-blocking monitor**: Session starts immediately, scans run in background
3. **Graceful shutdown**: SIGTERM with timeout, cleanup on session end
4. **Locked file access**: Prevents concurrent write conflicts
5. **Stale lock detection**: 30-minute timeout prevents deadlocks

## Development Status

### ✅ Phase 1: Foundation (Complete)
- [x] Plugin manifest
- [x] Common library (reused from process-janitor)
- [x] Rule engine with full validation execution
  - [x] Regex checks (with pcregrep support)
  - [x] JSON field validation (nested paths, patterns)
  - [x] Structure checks (file existence, min_dashes)
- [x] Core rules (hook-session-start, plugin-schema)
- [x] Scan plugins script
- [x] SessionStart hook

### ✅ Phase 2: Background Monitor (Complete)
- [x] start-monitor.sh
- [x] stop-monitor.sh
- [x] Stop hook
- [x] Heartbeat tracking
- [x] Session management

### ✅ Phase 3: Fix Generation (Complete - Framework Ready)
- [x] debugger-fixer agent (specification)
- [x] debugger-critic agent (specification)
- [x] git-utils.sh library (5-layer locking, branch management)
- [x] generate-fix.sh script (placeholder for agent integration)
- [x] apply-fix.sh script (full implementation)
- [x] /debug command (full workflow documented)

**Note**: Agent invocations await Task tool integration. Manual workflow available via scripts.

### ⏳ Phase 4: Self-Improvement (Pending)
- [ ] self-improve.sh script
- [ ] Metrics analysis
- [ ] Rule confidence adjustment

### ⏳ Phase 5: Web Discovery (Pending)
- [ ] web-search.sh library
- [ ] web-discover.sh script
- [ ] External rules

## Contributing

To add a new rule:

1. Create JSON file in `rules/core/`
2. Define validation checks and fix template
3. Test against plugins: `./scripts/scan-plugins.sh`
4. Verify issues recorded in `~/.claude/self-debugger/findings/issues.jsonl`

## Troubleshooting

### Monitor not starting

Check logs:
```bash
tail -f ~/.claude/self-debugger/sessions/[session-id]/monitor.log
```

### No issues detected

Verify rules loaded:
```bash
ls -la plugins/self-debugger/rules/core/
```

Enable verbose mode:
```bash
export DEBUGGER_VERBOSE=true
```

## License

MIT

## References

- [Self-Improving Coding Agents](https://arxiv.org/html/2504.15228v2)
- [Autonomous Software Maintenance](https://www.tembo.io/blog/ai-coding-agents-revolutionizing-development)
- [Claude Code Plugin Architecture](https://thamizhelango.medium.com/beyond-function-calling-how-claude-codes-plugin-architecture-is-redefining-ai-development-tools-67ccec9b5954)
