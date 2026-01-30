---
name: evolve
description: Cluster related instincts into new skills for enhanced automation
usage: /evolve [--auto] [--min-confidence 0.6]
examples:
  - /evolve
  - /evolve --auto
  - /evolve --min-confidence 0.7
---

# /evolve - Skill Evolution

Automatically cluster related instincts into cohesive skills that enhance Claude's capabilities.

## What This Does

1. **Analyzes instincts** to find related patterns
2. **Clusters by domain** and trigger similarity
3. **Generates skill proposals** for user review
4. **Creates new skills** that combine multiple learnings

## Usage

```bash
# Interactive mode (review each proposal)
/evolve

# Auto-approve high-confidence clusters
/evolve --auto

# Only cluster instincts with confidence >= 0.7
/evolve --min-confidence 0.7
```

## How It Works

### Step 1: Gather Instincts

Collects all learned instincts from:
```
~/.claude/claude-skills/instincts/
├── learned/        # Auto-discovered patterns
└── personal/       # User-defined patterns
```

### Step 2: Cluster by Similarity

**Clustering Algorithm:**
```
1. Group by domain (code-style, testing, git-workflow, etc.)
2. Calculate trigger similarity (using fuzzy matching)
3. Find temporal correlation (observed together)
4. Identify logical sequences (A before B before C)
```

**Example Clustering:**
```
Instincts:
  1. prefer-functional-components (confidence: 0.8, domain: code-style)
  2. use-hooks-over-hoc (confidence: 0.7, domain: code-style)
  3. component-composition (confidence: 0.6, domain: code-style)

Cluster Analysis:
  ✓ Same domain: code-style
  ✓ Related triggers: All mention "React components"
  ✓ Compatible: Can be combined

Proposed Skill: react-patterns
```

### Step 3: Generate Skill Proposals

For each cluster with 3+ instincts:

```markdown
# Skill Proposal: react-patterns

## Summary
Combines 3 React coding patterns learned from your work

## Included Instincts
1. prefer-functional-components (0.8)
   - Use functional components with hooks

2. use-hooks-over-hoc (0.7)
   - Prefer hooks over higher-order components

3. component-composition (0.6)
   - Compose components rather than prop drilling

## Proposed Skill Actions
When working with React:
- Create components as functional (not class-based)
- Use hooks (useState, useEffect) for state/side effects
- Compose components to share logic
- Avoid HOCs and prop drilling patterns

## Confidence Score: 0.73
Average of included instincts, weighted by observation count

## Impact
This skill will:
- Auto-suggest React patterns matching your preferences
- Reduce corrections needed for React code
- Speed up React component development
```

### Step 4: Critic Validation

Uses `instinct-critic` agent to score each proposal (0-100):

**Scoring Criteria:**
- **Coherence** (30 points) - Do instincts fit together logically?
- **Usefulness** (30 points) - Will this skill provide value?
- **Completeness** (20 points) - Are there missing pieces?
- **Confidence** (20 points) - Are underlying instincts reliable?

**Approval Thresholds:**
- **>= 80**: Auto-approve (with --auto flag)
- **70-79**: Recommend approval
- **60-69**: Suggest refinement
- **< 60**: Reject (needs more instincts)

### Step 5: Skill Creation

Approved skills are created as:
```
~/.claude/skills/evolved/react-patterns/SKILL.md
```

## Command Options

### `--auto`
Auto-approve clusters with critic score >= 80:
```bash
/evolve --auto

# Output:
# 🤖 Auto-approval mode enabled
#
# Cluster 1: react-patterns (score: 85/100)
# ✅ Auto-approved and created
#
# Cluster 2: git-workflow (score: 72/100)
# ⏸️ Requires manual approval (score < 80)
```

### `--min-confidence`
Only cluster instincts meeting minimum confidence:
```bash
/evolve --min-confidence 0.7

# Only uses instincts with confidence >= 0.7
# More reliable but fewer clusters
```

## Output Example

```
/evolve

🌱 Analyzing learned instincts...

📊 Instinct Inventory
├─ Total instincts: 12
├─ High confidence (>= 0.7): 6
├─ Moderate confidence (0.5-0.7): 4
└─ Low confidence (< 0.5): 2

🔍 Clustering Analysis

Cluster 1: react-patterns
├─ Instincts: 3
├─ Avg confidence: 0.73
├─ Domain: code-style
└─ Critic score: 85/100

  Included instincts:
  1. prefer-functional-components (0.8) - 12 observations
  2. use-hooks-over-hoc (0.7) - 8 observations
  3. component-composition (0.6) - 6 observations

  Proposed actions:
  - Use functional components for all React code
  - Prefer hooks over HOCs and render props
  - Compose components to share logic

  💡 Recommendation: APPROVE
     This cluster is coherent and will improve React development

Cluster 2: test-workflow
├─ Instincts: 4
├─ Avg confidence: 0.65
├─ Domain: testing
└─ Critic score: 78/100

  Included instincts:
  1. test-before-commit (0.7) - 10 observations
  2. prefer-jest (0.6) - 7 observations
  3. test-coverage-80 (0.7) - 5 observations
  4. run-tests-on-save (0.6) - 4 observations

  Proposed actions:
  - Always run tests before git commit
  - Use Jest as test framework
  - Aim for 80%+ test coverage
  - Auto-run tests on file save

  💡 Recommendation: APPROVE
     Solid testing workflow automation

Cluster 3: git-style
├─ Instincts: 2
├─ Avg confidence: 0.55
├─ Domain: git-workflow
└─ Critic score: 62/100

  Included instincts:
  1. conventional-commits (0.6) - 4 observations
  2. branch-naming (0.5) - 3 observations

  ⚠️ Recommendation: WAIT
     Only 2 instincts - collect more patterns first
     Suggested instincts to add:
     - Pull before push behavior
     - Commit frequency preferences
     - Merge vs rebase preferences

📋 Summary
├─ Clusters found: 3
├─ Recommended for approval: 2
├─ Need more data: 1
└─ Would create: 2 new skills

❓ Approve proposals?
   [1] Approve all recommended (2 skills)
   [2] Review individually
   [3] Cancel

> 1

✅ Creating skills...

Created: ~/.claude/skills/evolved/react-patterns/SKILL.md
Created: ~/.claude/skills/evolved/test-workflow/SKILL.md

🎉 Evolution complete!
   - 2 new skills created
   - 7 instincts clustered
   - 5 instincts remaining for future clustering

💡 Next steps:
   - New skills are automatically loaded in next session
   - Remaining instincts will be re-evaluated as more data accumulates
   - Run /learn after sessions to discover more patterns
```

## Skill Creation Process

**Generated Skill Structure:**
```yaml
---
name: react-patterns
description: Learned React coding patterns from your work
disable-model-invocation: false
activation-triggers:
  - "working with React components"
  - "creating new component"
  - "refactoring React code"
---

# React Patterns

Auto-generated skill combining your learned React preferences.

## Patterns

### 1. Functional Components
**Confidence: 0.8**
Use functional components with hooks instead of class components.

**Examples:**
```jsx
// ✅ Preferred
const Button = ({ label, onClick }) => {
  return <button onClick={onClick}>{label}</button>;
};

// ❌ Avoid
class Button extends React.Component {
  render() {
    return <button onClick={this.props.onClick}>{this.props.label}</button>;
  }
}
```

### 2. Hooks Over HOCs
**Confidence: 0.7**
Prefer hooks for code reuse over higher-order components.

### 3. Component Composition
**Confidence: 0.6**
Compose components to share logic instead of prop drilling.

## When to Apply

Apply these patterns when:
- Creating new React components
- Refactoring existing components
- Reviewing React code

## Evidence

Based on:
- 26 total observations
- 3 user corrections
- Consistent across 15 days of work
```

## When to Use /evolve

**Good Times:**
- ✅ After accumulating 5+ instincts in related domains
- ✅ When patterns become clear (multiple observations)
- ✅ End of project to capture project-specific learnings
- ✅ When `/learn` suggests you have enough instincts

**Not Useful:**
- ❌ Too few instincts (< 3 in any domain)
- ❌ Unrelated instincts (no logical clustering)
- ❌ Low-confidence instincts only (< 0.5)

## Integration with /learn

**Workflow:**
```
Work on features
     ↓
/learn (extract patterns)
     ↓
Accumulate instincts
     ↓
/evolve (cluster into skills)
     ↓
Skills auto-apply in future
```

## Advanced Usage

### Custom Clustering
```bash
# Only cluster code-style instincts
/evolve --domain code-style

# Require at least 4 instincts per cluster
/evolve --min-cluster-size 4

# Include low-confidence instincts
/evolve --min-confidence 0.4
```

### Review Mode
```bash
# See what would be created without creating
/evolve --dry-run

# Output shows proposals but doesn't create skills
```

## Privacy & Data

**What Gets Stored:**
- Skill definitions (patterns and actions)
- Cluster metadata (which instincts combined)
- Creation timestamps

**What's NOT Stored:**
- Specific code snippets
- File contents
- Sensitive information

## Troubleshooting

**"No clusters found"**
- Need at least 3 related instincts
- Instincts may be too diverse (different domains)
- Try with lower --min-confidence

**"Critic scores too low"**
- Instincts not coherent enough
- Need more observations to increase confidence
- Wait for more patterns to emerge

**"Skills not loading"**
- Ensure ~/.claude/skills/evolved/ exists
- Check skill file format (must have YAML frontmatter)
- Restart Claude Code to reload skills

---

**Related Commands:**
- `/learn` - Extract patterns from sessions
- `/optimize` - View and adjust evolution settings
