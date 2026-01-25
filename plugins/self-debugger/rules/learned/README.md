# Learned Rules

This directory contains rules learned from actual debugging sessions and real-world issues discovered during Claude Code plugin development.

## Overview

Learned rules are patterns discovered through:
- **Session analysis**: Real bugs and issues encountered during development
- **Code review findings**: Problems identified in PR reviews
- **User feedback**: Issues reported by plugin developers
- **Self-improvement analysis**: Metrics-driven rule refinement

Unlike core rules (which are manually crafted) and external rules (discovered from web sources), learned rules come directly from production experience.

## Current Learned Rules

### 1. react-query-key-mismatch.json
**Category**: react-query-correctness
**Severity**: error
**Confidence**: 0.85

Detects when React Query cache operations use different query keys than the actual queryKey in useQuery definitions.

**Learned from**: Frontend template API alignment session
**Discovery**: TemplateDetails.tsx used `['templates', serviceId]` for cache operations but useFetch used `[url, params]`, causing optimistic updates to write to wrong cache location.

**Impact**: HIGH - Causes stale data and UI inconsistencies

**Example**:
```typescript
// ❌ WRONG - Key mismatch
queryClient.setQueryData(['templates', serviceId], ...)  // Wrong key!
const data = useFetch(url, params)  // Uses [url, params]

// ✅ CORRECT - Keys match
queryClient.setQueryData([url, params], ...)
const data = useFetch(url, params)
```

---

### 2. placeholder-test-assertion.json
**Category**: test-quality
**Severity**: warning
**Confidence**: 0.90

Detects placeholder test assertions that don't validate actual behavior.

**Learned from**: Frontend template API alignment session
**Discovery**: templates.test.tsx had three tests with `expect(true).toBe(true)` placeholders that provided false coverage without validating URLSearchParams construction.

**Impact**: MEDIUM - False sense of test coverage

**Patterns detected**:
- `expect(true).toBe(true)`
- `expect(false).toBe(false)`
- `expect(1).toBe(1)`
- Tests with TODO/FIXME comments

**Example**:
```typescript
// ❌ WRONG - Placeholder
it('converts job_inputs to JSON string', () => {
  // TODO: implement
  expect(true).toBe(true);  // Always passes!
});

// ✅ CORRECT - Real assertion
it('converts job_inputs to JSON string', async () => {
  const formData = mockMutateAsync.mock.calls[0][0];
  expect(formData.get('job_inputs')).toBe(
    JSON.stringify({ key: 'value' })
  );
});
```

---

### 3. tsx-extension-required.json
**Category**: typescript-correctness
**Severity**: error
**Confidence**: 0.95

Detects .ts files containing JSX syntax that require .tsx extension.

**Learned from**: Frontend template API alignment session
**Discovery**: templates.test.ts file had JSX syntax causing 18 TypeScript compilation errors (TS1005, TS1128, TS1161).

**Impact**: CRITICAL - Breaks TypeScript compilation

**Auto-fix**: Yes - Renames file from .ts to .tsx

**Example**:
```typescript
// ❌ WRONG - JSX in .ts file
// File: templates.test.ts
const wrapper = ({ children }) => (
  <QueryClientProvider>{children}</QueryClientProvider>
);
// Error: TS1005: '>' expected

// ✅ CORRECT - JSX in .tsx file
// File: templates.test.tsx (renamed)
const wrapper = ({ children }) => (
  <QueryClientProvider>{children}</QueryClientProvider>
);
```

## Rule Lifecycle

1. **Discovery**: Issue encountered in real session
2. **Documentation**: Context and fix recorded
3. **Rule creation**: Pattern formalized as JSON rule
4. **Validation**: Tested against codebase
5. **Refinement**: Confidence adjusted based on metrics
6. **Promotion**: High-confidence rules may move to core/

## Metrics

Learned rules track:
- **Detection count**: How many times the pattern was found
- **Fix application rate**: How many times fixes were applied
- **Approval rate**: Percentage of fixes that were accepted
- **False positive rate**: Detections that weren't real issues

These metrics feed into the self-improvement loop, adjusting rule confidence over time.

## Adding New Learned Rules

When you discover a new pattern worth encoding:

1. **Document the context**:
   - Session ID where discovered
   - Exact issue and fix
   - Impact assessment

2. **Create rule JSON**:
   ```json
   {
     "rule_id": "descriptive-name",
     "version": "1.0.0",
     "category": "category-name",
     "severity": "error|warning",
     "confidence": 0.70,
     "learned_from": "session:session-name",
     "discovery_context": "Detailed explanation...",
     "last_updated": "2026-01-25"
   }
   ```

3. **Test the rule**:
   - Run against codebase
   - Verify detection accuracy
   - Check for false positives

4. **Commit with context**:
   - Include session reference
   - Link to issue/PR if applicable
   - Document impact metrics

## Future Enhancements

- **Automatic rule learning**: LLM-powered pattern extraction from fix sessions
- **Confidence adjustment**: Automatic tuning based on approval rates
- **Pattern clustering**: Identify similar issues for rule generalization
- **Cross-project learning**: Share learned rules across codebases

---

**Last Updated**: 2026-01-25
**Total Learned Rules**: 3
**Average Confidence**: 0.90
