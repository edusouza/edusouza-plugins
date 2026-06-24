---
name: ci-autoheal
description: >
  Autonomously drives a failing GitHub Actions workflow back to green without needing a PR.
  Discovers the failing run (from a run URL, workflow name, branch, or recent history),
  downloads logs, dispatches a diagnostic subagent to identify root cause (build errors /
  config errors / missing secrets / Cloudflare deployment failures / test failures /
  lint violations / transient flakiness), applies fixes, verifies locally, then commits
  and either pushes directly (feature branches) or opens a hotfix PR (main/master).
  Loops up to 5 times before escalating. Trigger when user says "CI is failing on main",
  "fix the failing workflow", "deploy to CF failed", "GH Actions is broken",
  "the workflow is red", "/ci:autoheal", or pastes a GitHub Actions run URL.
---

# CI Autoheal

Autonomously fixes a failing GitHub Actions workflow by diagnosing logs, applying fixes,
verifying locally, and re-triggering — up to 5 iterations. Works without a PR (push to
main, scheduled runs, manual dispatches, deployment pipelines).

## Setup

### 1. Identify the failing run

If the user provided a run URL, extract the run ID from it:
`https://github.com/<owner>/<repo>/actions/runs/<RUN_ID>`

If the user provided a workflow name or described the failure, search recent runs:

```bash
gh run list --limit 20 \
  --json databaseId,name,status,conclusion,headBranch,event,createdAt,url \
  | jq '[.[] | select(.conclusion == "failure" or .conclusion == "timed_out" or .conclusion == "cancelled")]'
```

If multiple failures exist, present a short numbered list and ask the user to confirm which
workflow to target. Default to the most recent failure if the user says "fix it" without
specifying.

```bash
RUN_ID=<confirmed run ID>
RUN_INFO=$(gh run view $RUN_ID --json headBranch,workflowName,event,workflowDatabaseId,url)
BRANCH=$(echo $RUN_INFO | jq -r .headBranch)
WORKFLOW=$(echo $RUN_INFO | jq -r .workflowName)
EVENT=$(echo $RUN_INFO | jq -r .event)
```

### 2. Determine fix strategy

```
if BRANCH is "main" or "master":
  FIX_STRATEGY=hotfix-pr    # create hotfix/<slug> branch, push, open PR
else:
  FIX_STRATEGY=direct-push  # push fixes directly to BRANCH
```

Tell the user the chosen strategy before proceeding. If they want to override
(e.g. allow direct push to main), ask explicitly and only proceed with their confirmation.

### 3. Checkout the branch

```bash
git fetch origin
git checkout $BRANCH
git pull origin $BRANCH
```

### 4. Detect repo scope

Inspect the workflow YAML and recent changed files to determine which verify commands apply:

```bash
# Files changed in the last commit on this branch
git diff --name-only HEAD~1 HEAD
```

Scope rules:
- Paths under `invaice-backend/` → `pnpm lint && pnpm test` (run inside `invaice-backend/`)
- Paths under `invaice-frontend/` → `pnpm lint && pnpm test:run` (run inside `invaice-frontend/`)
- Cloudflare Worker (paths include `wrangler.toml` or `src/` near a `wrangler.toml`) → `pnpm run build` in that directory
- Both backend and frontend changed → run both, sequentially
- Unknown scope → inspect the failing job steps in the log to infer the command

## Iteration Loop (max 5)

Repeat until all jobs pass or the iteration cap is reached.

### 1. Poll run status

```bash
gh run view $RUN_ID --json jobs \
  --jq '.jobs[] | {name, conclusion, steps: [.steps[] | select(.conclusion == "failure") | {name, conclusion}]}'
```

If all jobs have `conclusion == "success"` or `"skipped"` — report success and stop.

### 2. Collect failing logs

```bash
gh run view $RUN_ID --log-failed
```

Capture the full log text. For Cloudflare deployments, pay special attention to lines
containing `Error:`, `error:`, `✘`, `wrangler`, `deploy`, `build`, `script`.

### 3. Diagnose with a subagent

Dispatch an `Agent` (subagent_type: general-purpose) with the full log, the list of changed
files, and the workflow name. Ask it to:

1. Identify the root cause category:
   - `build-failure` — TypeScript/compile errors, missing imports, bundling failures
   - `config-error` — wrangler.toml, package.json, or workflow YAML misconfiguration
   - `missing-secret` — env var or secret absent from GitHub Actions secrets or wrangler.toml
   - `cf-deployment-error` — Cloudflare API error, invalid binding, `compatibility_date` mismatch,
     script size limit exceeded, worker name conflict, authentication failure against CF API
   - `test-failure` — unit or integration tests failing
   - `lint-violation` — ESLint/Prettier violations
   - `infra-outage` — Cloudflare or GitHub Actions transient outage (error messages reference
     upstream services, HTTP 5xx from CF, or the same job passed hours earlier unchanged)
   - `flaky-transient` — likely a network hiccup or race condition; a re-run may suffice
2. Return exact file(s) and line number(s) for the fix (when applicable)
3. Describe the fix to apply
4. State whether a database migration is required (yes/no)
5. State whether a simple re-run (no code change) would likely resolve it (yes/no)
6. Recommend action: `fix-code` | `re-run` | `escalate`

Wait for the subagent response before continuing.

### 4. Check for escalation or re-run

**Escalate immediately** (do not attempt a code fix) when the subagent reports:

| Category | Action |
|----------|--------|
| `missing-secret` | Stop — secrets must be added via GitHub Settings → Secrets or CF dashboard |
| `cf-deployment-error` and root cause is API auth | Stop — credential/token issue outside codebase |
| `infra-outage` | Stop — wait for outage to resolve; provide status page links |
| `migration required: yes` | Stop — migrations must be authored by the developer |
| Root cause in files outside this branch's changes | Stop — upstream breakage, flag to developer |

**Re-run** when the subagent recommends `re-run`:

```bash
gh run rerun $RUN_ID --failed
```

Wait ~60 seconds, then refresh `RUN_ID` to the new run and poll again. This counts as one
iteration. If the re-run also fails, proceed to `fix-code` on the next iteration.

### 5. Apply the fix

Use Edit or Write tools to apply exactly the changes the subagent proposed. Do not modify
files outside the diagnosed scope.

Common fix patterns for each category:

- `build-failure`: fix the TypeScript error, add the missing import, update the dep
- `config-error`: correct wrangler.toml binding name, fix package.json script, update
  `compatibility_date` to a recent date
- `cf-deployment-error` (non-auth): fix binding config, reduce bundle size, resolve
  route conflict, update wrangler version in the workflow YAML
- `test-failure`: fix the test or the production code causing the regression
- `lint-violation`: apply the lint fix

### 6. Verify locally

Run in the relevant sub-directory based on the scope detected in Setup:

```bash
pnpm lint && pnpm test            # invaice-backend/
pnpm lint && pnpm test:run        # invaice-frontend/
pnpm run build                    # Cloudflare Worker directory
```

If verification **fails**: do NOT push. Re-dispatch the diagnostic subagent with the
local error output appended to the log. Apply a revised fix and re-verify. This extra
cycle within an iteration does NOT count against the 5-iteration cap.

### 7. Commit and push (or open hotfix PR)

```bash
git fetch origin $BRANCH
git add <only the files modified>
git commit -m "fix: <concise description of what was fixed>"
```

**If `FIX_STRATEGY=direct-push`:**
```bash
git push origin $BRANCH
```

**If `FIX_STRATEGY=hotfix-pr`:**
```bash
HOTFIX_BRANCH="hotfix/<3-5-word-slug-from-fix>"
git checkout -b $HOTFIX_BRANCH
git push origin $HOTFIX_BRANCH
gh pr create \
  --title "fix: <description>" \
  --base main \
  --head $HOTFIX_BRANCH \
  --body "Hotfix for failing **$WORKFLOW** workflow on \`main\`.

**Root cause**: <diagnosis from subagent>
**Fix**: <what was changed>
**Local verify**: passed"
```

Print the PR URL for the user.

Rules:
- Never use `--no-verify`
- Never force push
- Commit message must use `fix:` prefix (conventional commits)
- Hotfix branch slug must be human-readable, not a timestamp or run ID

### 8. Re-trigger and loop

After pushing, determine how to trigger a new run based on `EVENT`:

**Push-triggered** (`push`, `pull_request`): the workflow auto-triggers on push.
Wait ~30 seconds, then get the new run ID:

```bash
sleep 30
RUN_ID=$(gh run list --branch $BRANCH --workflow "$WORKFLOW" --limit 1 \
  --json databaseId --jq '.[0].databaseId')
```

**Schedule or dispatch-triggered** (`schedule`, `workflow_dispatch`): trigger manually:

```bash
# Find the workflow file name
WORKFLOW_FILE=$(gh api repos/{owner}/{repo}/actions/workflows \
  --jq ".workflows[] | select(.name == \"$WORKFLOW\") | .path" \
  | xargs basename)

gh workflow run "$WORKFLOW_FILE" --ref $BRANCH
sleep 30
RUN_ID=$(gh run list --branch $BRANCH --workflow "$WORKFLOW" --limit 1 \
  --json databaseId --jq '.[0].databaseId')
```

Return to step 1.

## Escalation Report (after 5 iterations or unresolvable condition)

```
## CI Autoheal Report — ESCALATED

**Workflow**: <name>
**Branch**: <branch>
**Trigger event**: <push | schedule | workflow_dispatch>
**Run URL**: <url>
**Fix strategy used**: <direct-push | hotfix-pr>
**Iterations attempted**: <N>
**Jobs still failing**: <list>

### Iteration history
| # | Root cause | Fix applied | Local verify | Push/PR | Outcome |
|---|------------|-------------|--------------|---------|---------|
| 1 | ...        | ...         | pass/fail    | ...     | ...     |

### Current error (last log excerpt)
<most relevant lines — wrangler output, compiler error, test failure>

### Recommended next steps
<specific action for the developer>
```

Common escalation playbooks:

| Condition | Recommended action |
|-----------|-------------------|
| `missing-secret` | Add `<SECRET_NAME>` in GitHub → Settings → Secrets and variables → Actions, or `wrangler secret put <NAME>` |
| CF auth failure | Rotate `CLOUDFLARE_API_TOKEN` in GitHub secrets; verify token has `Workers Scripts:Edit` permission |
| CF binding mismatch | Run `wrangler kv namespace list` / `wrangler d1 list` and reconcile `wrangler.toml` names |
| CF compatibility error | Update `compatibility_date` in `wrangler.toml` to today's date |
| Script size limit | Audit bundle with `wrangler publish --dry-run`; tree-shake or split into multiple Workers |
| Infra outage | Monitor cloudflarestatus.com / githubstatus.com; use `gh run rerun $RUN_ID` once resolved |
| Migration required | Run `pnpm migration:generate src/database/migrations/<Name>` and review before merging |
| Upstream breakage | Identify the dependency that regressed; pin to last-known-good version or open an issue upstream |

## Constraints

| Rule | Detail |
|------|--------|
| `git fetch origin` | Always before any push or rebase |
| No `--no-verify` | Hooks must run |
| No force push | Unless branch history already contains a force-push |
| Conventional commits | `fix: <description>` |
| No auto-migrations | Escalate instead |
| No secret hardcoding | Never write secrets into source files; escalate all secret issues |
| Hotfix PR for main | Never push directly to main/master without explicit user confirmation |
| Re-run counted | One `gh run rerun` attempt counts as one iteration |
| Iteration cap | 5 loops, then escalate |
| Timeout | ~15 min total; skip `gh run view --log-failed` if it hangs beyond 10 min |
