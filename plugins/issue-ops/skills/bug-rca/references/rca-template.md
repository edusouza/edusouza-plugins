# RCA Issue Update Template

Use this template when updating the GitHub issue title and body. Adapt sections based on findings — omit sections with no relevant data.

## Title Format

```
bug(<module>): <concise root cause description>
```

Examples:
- `bug(auth): pagination offset mismatch skips first page of invitations`
- `bug(jobs): upstream API timeout on large payloads causes silent job failure`
- `bug(search): missing tenant_id filter in duplicate-detection query`

## Body Template

```markdown
> **Original report:** <original issue title>
>
> <original issue body, quoted>

---

## Root Cause Analysis

### Summary
<!-- One-paragraph plain-language explanation of what's happening and why -->

### Evidence

#### From Logs/Observability
<!-- Error messages, stack traces, log snippets, metrics. Include timestamps. -->

```
<relevant log entries or error messages>
```

#### From Code Analysis
<!-- File paths, line numbers, the problematic code pattern, git blame for recent changes -->

- **File**: `src/module/file.ts:123`
- **Issue**: <description of the code problem>
- **Recent change**: <commit hash> by <author> on <date> (if relevant)

#### Reproduction Path
<!-- How the bug manifests: endpoint, input, conditions -->

1. <step>
2. <step>
3. <expected vs actual>

### Root Cause
<!-- Technical explanation of the underlying cause -->

### Impact
- **Affected scope**: <all users / a specific tenant / a specific action>
- **Data integrity**: <any data corruption or loss?>
- **Frequency**: <constant / intermittent / triggered by specific condition>

---

## Triage

| Attribute | Value |
|-----------|-------|
| **Priority** | `P{0-3}` — <brief justification> |
| **Size** | `{XS/S/M/L/XL}` — <brief justification> |
| **Module** | <affected module(s)/package(s)> |

---

## Proposed Fixes

### Option 1: <short name>
<!-- Preferred fix -->
- **Files to change**: `src/...`, `src/...`
- **Approach**: <what to do>
- **Risk**: <low/medium/high> — <why>
- **Migration needed**: yes/no

### Option 2: <short name> (if applicable)
<!-- Alternative approach -->
- **Files to change**: `src/...`
- **Approach**: <what to do>
- **Trade-offs**: <vs option 1>
```
