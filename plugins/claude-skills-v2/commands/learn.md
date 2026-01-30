---
name: learn
description: Extract patterns from current session and create learned instincts
usage: /learn [--session SESSION_ID] [--dry-run]
examples:
  - /learn
  - /learn --session abc123
  - /learn --dry-run
---

# /learn - Extract Session Patterns

Extract learnable patterns from the current session (or specified session) and create confidence-scored instincts for future use.

## What This Does

1. **Analyzes observations** from your session
2. **Detects patterns** in your workflow
3. **Creates instincts** with confidence scores (0.3-0.9)
4. **Stores learnings** for future sessions

## Usage

```bash
# Extract patterns from current session
/learn

# Analyze specific session
/learn --session abc123

# Preview without creating instincts (dry run)
/learn --dry-run
```

## How It Works

### Step 1: Observation Collection

During your session, the plugin automatically logs:
- All tool executions (Edit, Write, Bash, etc.)
- User corrections (when you fix Claude's output)
- Error resolutions
- Domain contexts

### Step 2: Pattern Detection

The `observer` agent analyzes observations to find:

**High-Value Patterns:**
- 🔴 **User corrections** - You explicitly fixed something (confidence +0.2)
- 🟡 **Error resolutions** - You solved a problem (confidence +0.15)
- 🟢 **Repeated workflows** - You do X consistently (confidence +0.1)

**Pattern Examples:**
```
You corrected class component → functional component (3 times)
  → Instinct: "prefer-functional-components" (confidence: 0.9)

You always run tests before git commit (5 times)
  → Instinct: "test-before-commit" (confidence: 0.6)

You use pnpm instead of npm (12 vs 2 occurrences)
  → Instinct: "prefer-pnpm" (confidence: 0.8)
```

### Step 3: Confidence Scoring

**Confidence Levels:**
- **0.3-0.5** - Tentative (monitor, don't apply yet)
- **0.5-0.7** - Moderate (suggest to you)
- **0.7-0.9** - High (auto-apply with notification)
- **0.9+** - Very high (silent auto-apply)

**Scoring Factors:**
```
Base (frequency):
  3-5 occurrences:  0.3
  6-10 occurrences: 0.5
  11-20 occurrences: 0.7
  20+ occurrences:  0.9

Boosters:
  User correction:  +0.2
  Error resolution: +0.15
  Consistency:      +0.1
  Recency:          +0.05
```

### Step 4: Instinct Creation

Instincts are stored as markdown files:

```yaml
---
id: prefer-functional-components
trigger: "when creating React components"
confidence: 0.75
domain: code-modification
source: observation
created: 2026-01-30T10:15:30Z
last_observed: 2026-01-30T12:45:00Z
observations: 8
---

# Prefer Functional Components

## Pattern
User consistently prefers functional React components over class components

## Action
When creating new React components, use functional syntax with hooks

## Evidence
- Observed 8 instances (2026-01-28 to 2026-01-30)
- User corrected class component to functional on 2026-01-28
- 100% consistency across all React component work

## Confidence Scoring
- Base: 0.5 (repeated pattern)
- User corrections: +0.2 (2 explicit corrections)
- Consistency: +0.1 (100% consistency)
- **Total: 0.8**
```

### Step 5: Application

**How Instincts Are Used:**

1. **Moderate Confidence (0.5-0.7)**
   - Claude suggests the pattern
   - You can accept or reject
   - Acceptance increases confidence

2. **High Confidence (0.7+)**
   - Claude auto-applies pattern
   - Notifies you it did so
   - You can override if needed

3. **Very High Confidence (0.9+)**
   - Silent auto-application
   - Pattern is fully learned

## Command Options

### `--session SESSION_ID`
Analyze a specific session instead of current session:
```bash
/learn --session abc123
```

### `--dry-run`
Preview patterns without creating instincts:
```bash
/learn --dry-run

# Output:
# 📊 Pattern Analysis (Dry Run)
#
# Patterns Detected:
# 1. prefer-functional-components (confidence: 0.8)
#    - 8 observations
#    - 2 user corrections
#    - Would create instinct
#
# 2. test-before-commit (confidence: 0.6)
#    - 5 observations
#    - Consistent pattern
#    - Would create instinct
```

## Output Example

```
/learn

🧠 Analyzing session patterns...

📊 Session Analysis
├─ Observations: 45
├─ Domains: code-modification, git-workflow, testing
├─ Time range: 2026-01-28 to 2026-01-30
└─ Worthiness score: 75/100

🔍 Patterns Detected

1. ✨ prefer-functional-components (confidence: 0.8)
   Domain: code-modification
   Evidence: 8 observations, 2 user corrections
   Action: Use functional React components instead of classes

2. 🔧 test-before-commit (confidence: 0.6)
   Domain: git-workflow
   Evidence: 5 sequences detected
   Action: Run tests before git commit

3. 📦 prefer-pnpm (confidence: 0.8)
   Domain: package-management
   Evidence: 12 uses vs 2 npm uses
   Action: Use pnpm for package operations

💾 Instincts Created: 3
├─ High confidence (>= 0.7): 2
├─ Moderate confidence (0.5-0.7): 1
└─ Saved to: ~/.claude/claude-skills/instincts/learned/

💡 Next Steps:
   - High-confidence instincts will auto-apply in future sessions
   - Moderate-confidence instincts will be suggested
   - Run /evolve when you have 5+ instincts to cluster into skills
```

## When to Use /learn

**Good Times to Run /learn:**
- ✅ After completing a significant feature
- ✅ After a productive session with clear patterns
- ✅ When you notice you're correcting Claude repeatedly
- ✅ After resolving several similar errors
- ✅ End of day to capture daily learnings

**Not Useful:**
- ❌ Very short sessions (<10 observations)
- ❌ Exploratory/research sessions without patterns
- ❌ First-time trying something new
- ❌ Random, unrelated tasks

## Privacy & Data

**What Gets Analyzed:**
- Tool names (Edit, Write, Bash, etc.)
- File patterns (*.ts, test files, etc.)
- Command patterns (git commands, npm commands)
- Domain classifications

**What's NEVER Stored:**
- Sensitive file contents (.env, secrets)
- Personal identifiable information
- API keys or credentials
- Private code snippets

**Data Location:**
```
~/.claude/claude-skills/
├── observations/           # Raw observations (30-day retention)
├── instincts/learned/      # Learned instincts
└── learning/               # Learning engine logs
```

## Integration with /evolve

Once you have multiple related instincts, use `/evolve` to cluster them:

```bash
# After /learn creates several instincts
/learn
# → Creates: prefer-functional-components, use-hooks-over-hoc, component-composition

# Cluster related instincts into a skill
/evolve
# → Creates: react-patterns skill combining all React instincts
```

## Troubleshooting

**"Not enough observations"**
- Need at least 3 observations for pattern detection
- Continue working and try again later

**"No patterns detected"**
- Session may not have clear repeated patterns
- Try after a more focused work session

**"Confidence too low"**
- Patterns exist but not consistent enough
- Will be re-evaluated as more observations accumulate

## Technical Details

**Implementation:**
- Uses `observer` agent (Haiku model for efficiency)
- Analyzes `observations.jsonl` file
- Creates instinct markdown files with frontmatter
- Logs metrics to `learning/patterns.jsonl`

**Performance:**
- Analysis typically takes 5-15 seconds
- Does not block other Claude Code operations
- Background observer also runs every 5 minutes

---

**Related Commands:**
- `/evolve` - Cluster instincts into skills
- `/optimize` - View and adjust confidence thresholds
