# Reflect Plugin for Claude Code

A self-improvement system that helps Claude learn from sessions and continuously improve skills.

## Features

- **Session Analysis**: Detects improvement signals from conversations (corrections, successes, edge cases)
- **Smart Proposals**: Generates skill improvement proposals with confidence levels (HIGH/MED/LOW)
- **Quality Validation**: Validates proposals via reflect-critic agent against 12-factor agent principles
- **Metrics Tracking**: Tracks acceptance rates and effectiveness to measure actual improvement
- **External Feedback**: Captures test failures, lint errors, and build issues as objective signals
- **Memory System**: Accumulates learnings in memory files for cross-session persistence

## Installation

1. Add the marketplace:
   ```
   /plugin marketplace add https://github.com/Cain-Ish/claude-skills
   ```

2. Install the plugin:
   ```
   /plugin install reflect
   ```

## Usage

### Basic Commands

```bash
/reflect                    # Analyze session, auto-detect skill
/reflect [skill-name]       # Analyze session for specific skill
/reflect on                 # Enable automatic end-of-session reflection
/reflect off                # Disable automatic reflection
/reflect status             # Check auto-reflect status
```

### Metrics Commands

```bash
/reflect stats              # Show overall effectiveness metrics
/reflect stats [skill]      # Show metrics for specific skill
/reflect validate [skill]   # Check if recent improvements helped
/reflect analyze-effectiveness  # Analyze metrics and propose meta-improvements
```

### Advanced Commands

```bash
/reflect improve            # Systematic self-improvement workflow
/reflect reflect            # Meta-improvement: improve reflect itself
/reflect resume [skill]     # Resume a paused skill
/reflect cleanup            # Clean up old memories and metrics
```

## How It Works

1. **Signal Detection**: After using a skill, `/reflect` analyzes the session for:
   - **Corrections** (HIGH confidence): User explicitly said "no" or corrected output
   - **Successes** (MEDIUM confidence): User approved with "perfect", "great", etc.
   - **Edge Cases** (MEDIUM confidence): Unanticipated questions or workarounds needed
   - **External Feedback** (HIGH confidence): Test failures, lint errors, build issues

2. **Proposal Generation**: Creates improvement proposals with:
   - Confidence levels based on signal strength
   - Specific actions (Add constraint, Update guideline, etc.)
   - Commit message for version control

3. **Quality Validation**: The reflect-critic agent scores proposals (0-100) against:
   - 12-factor agent principles
   - Signal-to-proposal alignment
   - Implementation feasibility

4. **Metrics Tracking**: All proposals are logged to track:
   - Acceptance rate (how often proposals are approved)
   - Effectiveness rate (how often improvements actually helped)

## Hooks

### PreToolUse Hook
Suggests reflection before git commits if the session involved meaningful skill usage.

### Stop Hook
When auto-reflect is enabled, suggests capturing learnings before ending the session.

## File Locations

| Path | Purpose |
|------|---------|
| `~/.claude/reflect-metrics.jsonl` | Metrics database (JSONL format) |
| `~/.claude/reflect-skill-state.json` | Auto-reflect on/off state |
| `~/.claude/memories/skill-patterns.md` | Cross-skill patterns |
| `~/.claude/memories/{skill}-prefs.md` | Skill-specific preferences |
| `~/.claude/memories/reflect-meta.md` | Meta-learnings about reflect |

## Requirements

- **macOS/Linux**: Works out of the box
- **Windows**: Requires WSL or Git Bash for script execution

## License

MIT
