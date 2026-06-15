---
name: pr-review-fix
description: >
  Reads all open review comments and conversation comments on a pull request, plans a fix for
  each one, presents the plan for user confirmation, then applies fixes one commit per issue,
  runs tests as a gate before each commit, pushes, replies inline to each resolved thread, and
  posts a summary table on the PR. Use when the user says "fix PR comments", "address review
  feedback", "fix the review", "resolve PR comments", "address feedback on PR #N", "fix review
  on this PR", "go through the review comments", or wants to act on code review feedback.
---

# PR Review Fix

Reads PR review feedback, plans fixes, confirms with the user, applies one commit per issue,
runs tests as a gate, pushes, and updates the PR with inline replies and a summary.

## Step 1: Identify the PR

If the user mentioned a PR number (e.g. "fix PR #42"), use that number directly.

Otherwise, detect the current branch's PR:

```bash
gh pr view --json number,title,url,headRefName,state
```

If no PR exists for the current branch, tell the user and stop.

Confirm you're on the correct local branch (`git branch --show-current`) — if not, check it out before proceeding.

## Step 2: Fetch all comments

Use three separate calls — the `gh pr view` JSON fields don't expose review thread state.

**Basic PR info:**
```bash
gh pr view <number> --json number,title,url,headRefName,baseRefName
```

**Inline review comments (REST):**
```bash
gh api repos/{owner}/{repo}/pulls/{number}/comments
```
Each object has: `id` (numeric, used for replies), `path`, `line`, `side`, `in_reply_to_id`, `user.login`, `body`.

Filter: keep only root comments (`in_reply_to_id == null`) — replies are noise for planning purposes.

**Resolved thread status (GraphQL):**
```bash
gh api graphql -f query='
{
  repository(owner: "{owner}", name: "{repo}") {
    pullRequest(number: {number}) {
      reviewThreads(first: 100) {
        nodes {
          isResolved
          comments(first: 1) { nodes { databaseId } }
        }
      }
    }
  }
}'
```
This maps each thread's root comment `databaseId` → `isResolved`. Skip threads where `isResolved: true`.

**Conversation comments (non-inline):**
```bash
gh api repos/{owner}/{repo}/issues/{number}/comments
```
Each object has: `id`, `user.login`, `body`, `created_at`.

Filter out from all sources:
- Bot comments (`user.login` ends with `[bot]`)
- Empty bodies
- Resolved review threads

## Step 3: Analyze and plan

For each unresolved item:
1. Read the referenced file at the indicated lines (for review threads — read a generous window, ±20 lines around the comment location)
2. Understand the reviewer's concern
3. Decide: is this a concrete code fix, or does it require discussion?

**Concrete fix**: you can determine exactly what code change to make.
**Needs discussion**: subjective style, architectural decisions, "what do you think about X?", or anything where multiple valid approaches exist and the reviewer hasn't specified one.

Detect the test command for this repo:

```bash
# Check for package.json test script
cat package.json | jq -r '.scripts.test // empty' 2>/dev/null
# Or look for Makefile, pytest.ini, go.mod, etc.
```

If you can't reliably detect it, include it in the plan and ask the user.

Present the full plan before touching any code:

```
PR #42 — "Add input validation to invoice upload"
Branch: feat/invoice-validation

Detected test command: pnpm test

Found N items to address:

FIXES (will be applied automatically):
  1. [review] src/invoices/invoice.dto.ts:23
     Reviewer: @alice — "Missing @IsNotEmpty() on fileName"
     Fix: Add @IsNotEmpty() decorator to the fileName property

  2. [review] src/invoices/invoice.service.ts:112
     Reviewer: @alice — "Should throw NotFoundException, not return null"
     Fix: Replace `return null` with `throw new NotFoundException(...)`

  3. [conversation] @bob — "Can you add a test for the NotFoundException case?"
     Fix: Add a test in invoice.service.spec.ts covering the error path

NEEDS DISCUSSION (will be skipped, noted in PR summary):
  4. [review] src/invoices/invoice.service.ts:88
     Reviewer: @charlie — "Not sure this abstraction is right — thoughts?"

Proceed? You can exclude items by number (e.g. "yes, skip 3") or just say "yes" to run all fixes.
```

Wait for explicit user confirmation before touching any code.

## Step 4: Apply fixes

For each confirmed fix, in order:

### 4a. Apply the code change

Use the Edit or Write tool to make the change. Keep changes minimal — only what the reviewer asked for.

### 4b. Run tests

Run the detected test command. Tests are a hard gate — do not commit if they fail.

If tests **pass** → proceed to commit.

If tests **fail**:
- Do NOT commit
- Report to the user: which fix caused the failure, what the test output says
- Ask whether to skip this item or attempt a revised fix
- Wait for user input before continuing

Note: lint and format run automatically via your Claude Code hooks — do not call them explicitly.

### 4c. Commit

```bash
git add <only the files modified for this fix>
git commit -m "fix: <concise description of what was fixed>"
```

Commit message rules:
- Use `fix:` prefix (conventional commits)
- Describe what changed from the reviewer's perspective, not the symptom
  - Good: `fix: throw NotFoundException when invoice is not found`
  - Bad: `fix: address PR comment #3`
- Never use `--no-verify`

Capture the commit SHA immediately after committing:

```bash
git rev-parse HEAD
```

Store it — you'll need it for the PR update.

Repeat 4a–4c for each confirmed fix.

## Step 5: Push

After all commits:

```bash
git push
```

Never force-push. If the push is rejected (branch is behind), warn the user and stop — do not auto-rebase.

## Step 6: Update the PR

Get the repo's owner and name:

```bash
gh repo view --json owner,name
```

### 6a. Inline replies

For each fixed review comment, reply using its numeric `id` (from the REST response — this is the integer, not the GraphQL node ID):

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments/{comment_id}/replies \
  -f body="Fixed in {sha}: {one-line description of what was done}"
```

Skip this step for conversation comments — they live on the issue thread, not the diff.

### 6b. Summary comment

Post one summary comment on the PR:

```bash
gh pr comment <number> --body "..."
```

Format the body as:

```markdown
## Review feedback addressed

| # | Type | Location | Comment | Status | Commit |
|---|------|----------|---------|--------|--------|
| 1 | review | `src/invoices/invoice.dto.ts:23` | Missing @IsNotEmpty() on fileName | ✅ Fixed | `abc1234` |
| 2 | review | `src/invoices/invoice.service.ts:112` | Should throw NotFoundException | ✅ Fixed | `def5678` |
| 3 | conversation | — | Add test for NotFoundException | ✅ Fixed | `ghi9012` |
| 4 | review | `src/invoices/invoice.service.ts:88` | Abstraction question | 💬 Needs discussion | — |
| 5 | review | `src/invoices/invoice.dto.ts:10` | Rename field | ⚠️ Skipped — tests failed | — |

All changes pushed to `feat/invoice-validation`.
```

Status values:
- ✅ Fixed — committed and pushed
- 💬 Needs discussion — skipped, requires human judgment
- ⚠️ Skipped — [reason] — e.g. tests failed, user excluded it, couldn't determine fix

## Constraints

| Rule | Detail |
|------|--------|
| Tests are a hard gate | Never commit if tests fail — report back to user |
| One commit per issue | Don't batch multiple fixes into one commit |
| No `--no-verify` | Hooks must run |
| No force push | Reject-on-push means ask the user, not rebase silently |
| No auto-rebase | Never run `git rebase` without explicit user instruction |
| Conventional commits | `fix: <description>` |
| Resolved threads | Skip in analysis, note in summary as "already resolved" |
| Hooks handle lint/format | Do not call lint or format commands explicitly |
