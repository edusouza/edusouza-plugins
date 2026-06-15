---
name: pr-autoheal
description: Autonomously drives a GitHub PR to green CI. Fetches check statuses, downloads failing job logs, dispatches a diagnostic subagent to identify root cause (stale rebase / missed call sites / type errors / test mocks / lint violations), applies fixes, verifies locally, and pushes — looping up to 5 times before escalating. Trigger when user types /pr:autoheal followed by a PR number, says "autoheal PR #N", "drive PR N to green", or "fix CI on PR N".
---

# PR Autoheal

Autonomously fixes a failing PR's CI checks by diagnosing logs, applying fixes, verifying locally, and pushing — up to 5 iterations.

## Setup

```bash
PR=<number>
PR_INFO=$(gh pr view $PR --json headRefName,baseRefName,url)
BRANCH=$(echo $PR_INFO | jq -r .headRefName)
BASE=$(echo $PR_INFO | jq -r .baseRefName)

git fetch origin
git checkout $BRANCH
```

Detect repo scope from changed files to select verify commands:

```bash
CHANGED=$(gh pr view $PR --json files --jq '[.files[].path] | join(" ")')
# If paths include "invaice-backend/" patterns: VERIFY="pnpm lint && pnpm test" (run in invaice-backend/)
# If paths include "invaice-frontend/" patterns: VERIFY="pnpm lint && pnpm test:run" (run in invaice-frontend/)
# If both repos changed, run both verify commands in their respective directories.
```

## Iteration Loop (max 5)

Repeat until all checks pass or iteration cap is reached.

### 1. Poll check statuses

```bash
gh pr checks $PR --json name,status,conclusion,detailsUrl
```

If all conclusions are `SUCCESS` or `SKIPPED` — report success and stop.

### 2. Collect failing logs

For each check with `conclusion == FAILURE`:

```bash
RUN_ID=$(gh run list --branch $BRANCH --limit 1 --json databaseId --jq '.[0].databaseId')
gh run view $RUN_ID --log-failed
```

Capture the full log text.

### 3. Diagnose with a subagent

Dispatch an `Agent` (subagent_type: general-purpose) with a prompt containing the full log and the list of changed files, asking it to:

1. Identify root cause from: `stale-rebase` | `missed-call-sites` | `type-errors` | `test-mock-failures` | `lint-violations`
2. Return exact file(s) and line number(s) for the fix
3. Describe the fix to apply
4. State whether a database migration is required (yes/no)

Wait for the subagent response before continuing.

### 4. Check for escalation conditions

If subagent reports `migration required: yes` — **stop and escalate immediately**. Do not attempt a fix; migrations must be authored by the developer.

### 5. Apply the fix

Use Edit or Write tools to apply exactly the changes the subagent proposed. Do not modify files outside the diagnosed scope.

### 6. Verify locally

Run in the relevant sub-directory:

```bash
pnpm lint && pnpm test           # backend (invaice-backend/)
pnpm lint && pnpm test:run       # frontend (invaice-frontend/)
```

If verification **fails**: do NOT push. Re-run the diagnostic subagent with the local error output appended. Apply another fix and re-verify. This counts as the same iteration — not a new one.

### 7. Commit and push

```bash
# Non-negotiable: always fetch before any rebase or push
git fetch origin master

git add <only the files modified>
git commit -m "fix: <concise description>"

git push origin $BRANCH
```

Rules:
- Never use `--no-verify` or `-n`
- Never force push unless the branch's existing history already contains a force-push
- Commit message must use the `fix:` prefix (conventional commits)

### 8. Wait and loop

Wait ~30 seconds for CI to pick up the push, then return to step 1.

## Escalation Report (after 5 iterations or unresolvable condition)

```
## PR #<N> Autoheal Report — ESCALATED

**Iterations attempted**: <N>
**Checks still failing**: <list>

### Iteration history
| # | Root cause diagnosed | Fix applied | Local verify | Outcome |
|---|----------------------|-------------|--------------|---------|
| 1 | ...                  | ...         | pass/fail    | ...     |

### Current error (last log excerpt)
<relevant lines>

### Recommended next steps
<specific action for the developer>
```

Common escalation reasons:
- Migration required — run `pnpm migration:generate src/database/migrations/Name` and review
- Root cause is upstream (outside this PR's changed files)
- Flaky test — note test name, suggest re-run or skip investigation
- Secrets/env var missing in CI environment

## Constraints

| Rule | Detail |
|------|--------|
| `git fetch origin master` | Always before rebase or push |
| No `--no-verify` | Hooks must run |
| No force push | Unless branch history already has one |
| Conventional commits | `fix: <description>` |
| No auto-migrations | Escalate instead |
| Iteration cap | 5 loops, then escalate |
| Timeout | ~15 min total; skip `gh run view` if it hangs beyond 10 min |
