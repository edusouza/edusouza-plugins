---
name: bug-rca
description: "Automated bug triage, root cause analysis, and GitHub issue enrichment. Fetches a GitHub bug issue, analyzes the codebase for related code paths, optionally queries whatever observability backend is connected (logs, error groups, traces, metrics, alerts via MCP — GCP, Datadog, Sentry, CloudWatch, etc.), synthesizes a root cause analysis, determines priority (P0-P3) and size (XS-XL), and updates the GitHub issue with all findings. Does NOT modify any source code — diagnosis only. Use when the user mentions a bug issue on GitHub, references a GH bug issue, says 'issue bug gh', 'issue bug github', 'analyze bug #N', 'triage issue #N', or asks to investigate a GitHub bug."
---

# Bug RCA Skill

Analyze a GitHub bug issue, investigate root cause using code and observability, and update the issue with findings.

> **Scope boundary**: This skill is read-only with respect to the codebase. Do not edit, create, or delete any source files. The deliverable is a diagnosis written into the GitHub issue, not a code change.

## Workflow

### Phase 1: Fetch & Parse Issue

1. Run `gh issue view <number> --json title,body,labels,comments,assignees,createdAt,author`
2. Extract from issue body and comments:
   - Error messages, stack traces
   - Affected endpoints or operations
   - Timestamps, tenant/account IDs, user context
   - Steps to reproduce (if provided)
3. Present issue summary to user before proceeding

### Phase 2: Code Analysis

Run these investigations in parallel where possible:

1. **Search for related code** - Grep for error messages, endpoint paths, entity/service names mentioned in the issue
2. **Trace the code path** - Read controllers, services, repositories involved in the affected operation
3. **Check recent changes** - `git log --oneline -20 -- <affected_files>` and `git blame` on suspicious areas
4. **Check test coverage** - Look for existing tests that should catch this bug

### Phase 3: Observability Investigation (optional — depends on available tooling)

Read `references/observability-guide.md` for backend-specific tool names and filter patterns.

**First, detect what observability is available this session.** Check which monitoring MCP tools or CLIs are connected — common ones: GCP Cloud Operations (`mcp__observability__*`, `mcp__cloud-run__*`), Datadog, Sentry, AWS CloudWatch, Grafana/Loki, Honeycomb. **If none are available, skip this phase** and rely on the stack traces / log excerpts in the issue plus the Phase 2 code analysis.

When a backend is available, follow this investigation order (skip steps that clearly don't apply), mapping each to the connected backend's equivalent:

1. **Error groups / issues** - aggregated error patterns (e.g. Sentry issues, GCP error groups)
2. **Logs** - filtered by severity, timestamp, and error message around the report window
3. **Traces** - request/span traces for latency and failure paths
4. **Metrics** - CPU, memory, request latency, instance/replica count, error rate
5. **Alerts** - correlated alert firings around the time of the bug
6. **Service / deploy state** - current revision/version, scaling config, and recent deploys that might correlate

### Phase 4: Synthesize RCA

Read `references/priority-matrix.md` for priority and size criteria.

1. Correlate code analysis with observability findings
2. Identify the root cause (not just symptoms)
3. Determine priority (P0-P3) using the priority signal checklist
4. Determine size (XS-XL) using the size signal checklist
5. Identify the exact file(s), line(s), and function(s) where the fix should be applied, with a brief description of what the fix should do — but **do not edit or create any files**. The RCA skill is diagnosis-only; implementation is out of scope.

### Phase 5: Update GitHub Issue

Read `references/rca-template.md` for the issue title and body template.

1. Compose a new title: `bug(<module>): <concise root cause description>`
2. Format findings using the RCA template as the new issue body (preserving the original description in a "Original Report" section at the top)
3. Update the issue title, body, and module label:
   ```bash
   gh issue edit <number> \
     --title "bug(<module>): <concise description>" \
     --body "<rca_body>" \
     --add-label "module:<name>"
   ```
4. Record **Priority** and **Size**. Prefer Project fields when the repo uses a GitHub Project that has Priority/Size fields; otherwise fall back to labels.

   **First, check whether a usable Project exists:**
   ```bash
   OWNER=$(gh repo view --json owner -q '.owner.login')
   # Pick the first project the issue belongs to, or set PROJECT_NUM manually
   PROJECT_NUM=$(gh project list --owner "$OWNER" --format json \
     | jq -r '.projects[0].number // empty')
   ```

   **If a Project with Priority/Size fields exists**, set them (discover field/option IDs via
   `gh project field-list "$PROJECT_NUM" --owner "$OWNER" --format json` and match option `name` to the
   determined value):
   ```bash
   ITEM_ID=$(gh project item-list "$PROJECT_NUM" --owner "$OWNER" --format json \
     | jq -r ".items[] | select(.content.number == <number>) | .id")
   gh project item-edit --project-id "$PROJECT_NUM" --id "$ITEM_ID" \
     --field-id "<priority_field_id>" --single-select-option-id "<priority_option_id>"
   gh project item-edit --project-id "$PROJECT_NUM" --id "$ITEM_ID" \
     --field-id "<size_field_id>" --single-select-option-id "<size_option_id>"
   ```
   Optionally move the item to a "Ready"/triaged status if the board has one and the item is currently in "Backlog".

   **Otherwise (no Project, or no such fields)**, encode priority and size as labels:
   ```bash
   gh issue edit <number> \
     --add-label "priority:P1" \
     --add-label "size:M"
   ```
   Create the labels first if they do not exist (`gh label create "priority:P1" --color FBCA04`).

## Important Notes

- **No code changes**: Never edit, create, or delete source files. Read files freely for analysis, but the only write action permitted is updating the GitHub issue.
- **Redact sensitive data**: Never paste secrets or PII into the issue body. Scrub credentials, tokens, API keys, user emails, and customer/tenant identifiers from log snippets before including them. (If your project has stricter compliance rules — e.g. HIPAA/PHI, GDPR — follow those.)
- **Verify before claiming**: Always confirm findings with actual evidence (logs, code, traces) before stating root cause.
- **Ask when uncertain**: If evidence is inconclusive, say so. Propose investigation steps rather than guessing.
- **One issue at a time**: Process a single issue per invocation.
