# Multi-Agent Plugin Testing Guide

## Quick Validation Tests

### Test 1: Simple Task (Score < 30)

```bash
node scripts/lib/complexity-analyzer.js "Fix typo in README.md" 200000
```

**Expected Output**:
- `complexity_score`: 0-29
- `pattern`: "single"
- `recommended_agents`: ["general-purpose"]
- `cost.multiplier`: "1x" or "2x"

### Test 2: Moderate Task (Score 30-49)

```bash
node scripts/lib/complexity-analyzer.js "Implement user registration endpoint and add unit tests" 200000
```

**Expected Output**:
- `complexity_score`: 30-49
- `pattern`: "sequential"
- `recommended_agents`: 2 agents
- `domains`: 1-2 domains

### Test 3: Complex Task (Score 50-69)

```bash
node scripts/lib/complexity-analyzer.js "Comprehensive code review including security audit, performance analysis, and test coverage validation" 200000
```

**Expected Output**:
- `complexity_score`: 50-69
- `pattern`: "parallel"
- `recommended_agents`: 2-3 agents
- `domains`: 2-3 domains (security, performance, testing)

### Test 4: Very Complex Task (Score 70+)

```bash
node scripts/lib/complexity-analyzer.js "Design and implement OAuth2 authentication system with JWT tokens, comprehensive security audit covering OWASP top 10, performance optimization for high-concurrency scenarios, and full test coverage with integration and edge case tests" 200000
```

**Expected Output**:
- `complexity_score`: 70-100
- `pattern`: "hierarchical"
- `recommended_agents`: 3+ agents
- `domains`: 3+ domains

## Component Tests

### Agent Registry

Verify agent registry loads correctly:

```bash
node -e "console.log(JSON.stringify(require('./scripts/lib/agent-registry.json'), null, 2))"
```

**Expected**: JSON with 8 agents and domain keyword mappings

### Configuration

Check default configuration:

```bash
cat config/default-config.json | jq '.'
```

**Expected**: Valid JSON with token_budget, thresholds, auto_approve settings

### Domain Detection

Test domain keyword matching:

```bash
# Security domain
node scripts/lib/complexity-analyzer.js "Fix SQL injection vulnerability" 200000 | jq '.domains'
# Expected: ["security"]

# Performance domain
node scripts/lib/complexity-analyzer.js "Optimize slow database queries" 200000 | jq '.domains'
# Expected: ["performance"]

# Multiple domains
node scripts/lib/complexity-analyzer.js "Security audit and performance review" 200000 | jq '.domains'
# Expected: ["security", "performance"]
```

## Integration Tests

### Full Workflow Simulation

1. **Load Configuration** (manual check)
   - Verify `~/.claude/multi-agent.local.md` is read if exists
   - Defaults are used if not

2. **Analyze Complexity**
   ```bash
   node scripts/lib/complexity-analyzer.js "Your request here" 200000
   ```
   - Verify JSON output is valid
   - Score is 0-100
   - Pattern matches score range

3. **Agent Selection**
   - Verify `recommended_agents` match detected `domains`
   - Count matches pattern limits (single=1, sequential=2, parallel=3, hierarchical=5)

4. **Cost Estimation**
   - `cost.single` is always lower than `cost.multi`
   - `cost.multiplier` is reasonable (1-20x)
   - `within_budget` is correct based on token_budget

## Edge Cases

### Test: No Domains Detected

```bash
node scripts/lib/complexity-analyzer.js "Hello world" 200000
```

**Expected**:
- `domains`: []
- `pattern`: "single"
- `recommended_agents`: ["general-purpose"]

### Test: Budget Exceeded

```bash
node scripts/lib/complexity-analyzer.js "Comprehensive review with security, performance, testing, architecture analysis" 50000
```

**Expected**:
- `within_budget`: false (if cost.multi > 50000)

### Test: Very Long Request

```bash
node scripts/lib/complexity-analyzer.js "$(cat README.md)" 200000
```

**Expected**:
- High `token_estimate` (README is large)
- Higher `complexity_score` due to token count
- Valid pattern recommendation

## Scoring Verification

### Token Points (Max 40)

Test requests with different lengths:

```bash
# Small (< 5K tokens)
echo "Fix typo" | wc -c
# Expected token_points: 0

# Medium (10-30K tokens)
# Create ~10K character request
# Expected token_points: 20

# Large (> 50K tokens)
# Create very large request
# Expected token_points: 40
```

### Domain Points (Max 30)

```bash
# 1 domain
node scripts/lib/complexity-analyzer.js "Security audit" 200000 | jq '.analysis.domain_points'
# Expected: 10

# 2 domains
node scripts/lib/complexity-analyzer.js "Security and performance review" 200000 | jq '.analysis.domain_points'
# Expected: 20

# 3+ domains
node scripts/lib/complexity-analyzer.js "Security, performance, and testing review" 200000 | jq '.analysis.domain_points'
# Expected: 30
```

### Structural Points (Max 30)

```bash
# Multi-step
node scripts/lib/complexity-analyzer.js "First implement, then test, and finally review" 200000 | jq '.analysis.structural_points'
# Expected: >= 10

# Validation required
node scripts/lib/complexity-analyzer.js "Review and validate the implementation" 200000 | jq '.analysis.structural_points'
# Expected: >= 10

# Parallel work
node scripts/lib/complexity-analyzer.js "Comprehensive review of security and performance" 200000 | jq '.analysis.structural_points'
# Expected: >= 10
```

## Pattern Selection Verification

### Score Ranges

Verify pattern selection matches documented ranges:

| Score Range | Expected Pattern |
|-------------|------------------|
| 0-29        | single           |
| 30-49       | sequential       |
| 50-69       | parallel         |
| 70-100      | hierarchical     |

Test boundary cases:
- Score 29 → single
- Score 30 → sequential
- Score 49 → sequential
- Score 50 → parallel
- Score 69 → parallel
- Score 70 → hierarchical

## Quality Assurance Checklist

Before release:

- [ ] All test cases pass
- [ ] Complexity analyzer produces valid JSON
- [ ] Agent registry is valid and complete
- [ ] Configuration files are valid JSON/YAML
- [ ] Documentation is comprehensive
- [ ] Examples in README work as shown
- [ ] Token estimates are reasonable (within ±50% of actual)
- [ ] Pattern recommendations make sense for each score range
- [ ] Error handling works (invalid input, missing config)
- [ ] Agent selection matches detected domains

## Performance Tests

### Speed

```bash
time node scripts/lib/complexity-analyzer.js "Test request" 200000
```

**Expected**: < 100ms for analysis

### Memory

```bash
/usr/bin/time -l node scripts/lib/complexity-analyzer.js "Test request" 200000
```

**Expected**: < 50MB memory usage

## Common Issues

### Issue: `domains` array is empty for obvious domain

**Cause**: Keywords not in `domain_keywords` mapping

**Solution**: Add missing keywords to `agent-registry.json`

### Issue: Recommended agents don't match domains

**Cause**: Agent selection algorithm mismatch

**Solution**: Verify agent `capabilities` match `domain_keywords`

### Issue: Pattern is "single" for obviously complex task

**Cause**: Low token estimate or missed structural complexity

**Solution**: Check token estimation and structural analysis logic

## Validation Success Criteria

✅ **Complexity Scoring**: >85% accuracy vs manual assessment
✅ **Token Estimates**: Within ±20% of actual usage
✅ **Domain Detection**: >90% accuracy
✅ **Pattern Selection**: Matches expected pattern for score range
✅ **Agent Selection**: Matches primary agent for each domain
✅ **Cost Estimation**: Reasonable multipliers (1-20×)

---

Run these tests before deploying to production or releasing a new version.
