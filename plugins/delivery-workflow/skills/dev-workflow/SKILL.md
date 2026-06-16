---
name: dev-workflow
description: >
  Structured TDD-based development workflow for implementing features, fixing bugs, and improving
  code. Triggers when the user says they want to code something, fix a bug, improve or refactor
  code, or add a feature. Enforces the full cycle: branch from issue (if provided), analysis,
  tests, implementation, verification, code review, security review. Supports parallel subagent
  execution in isolated git worktrees for independent tasks, with automatic merge back to the
  original branch. Never skips or reorders steps.
---

# Developer Workflow

Follow these steps in order for every coding, bug fix, or improvement task. Never skip steps.
Always ask if requirements are ambiguous before starting.

## Completion Checklist

**MUST complete all steps in order. Check off each step's VERIFICATION CHECKPOINT before proceeding.**

- [ ] **Step 0: Branch from Issue** (if applicable) — Branch created and checked out from the GitHub issue (before any coding)
- [ ] **Step 1: Analyze** — Requirements understood, alternatives considered, parallelization assessed
- [ ] **Step 2: Write Tests First (TDD)** — Tests written, tests fail (red phase)
- [ ] **Step 3: Implement** — Implementation complete, tests pass (or worktrees merged)
- [ ] **Step 4: Run Tests and Build** — Tests pass, build succeeds
- [ ] **Step 5: Code Review** — Code reviewed, no violations OR proceed to Step 6
- [ ] **Step 6: Fix Code Review Issues** — (ONLY if Step 5 found violations) Issues fixed, return to Step 4
- [ ] **Step 7: Security Review** — Security reviewed, no issues OR return to Step 3

---

## Step 0: Branch from Issue (if applicable)

**ACTION REQUIRED:** If the user provides a GitHub issue number, create and check out the linked branch **BEFORE** any analysis or coding. Do NOT start Step 1 until you are on the new branch.

First, resolve the default branch (`<main-branch>`) and derive a deterministic branch name (`<branch-name>`) from the issue title:

```bash
# Preconditions: gh installed + authenticated
command -v gh >/dev/null 2>&1 || { echo 'gh CLI not installed'; exit 1; }
gh auth status >/dev/null 2>&1 || { echo 'Run: gh auth login'; exit 1; }

ISSUE_NUMBER=<issue-number>

# Resolve <main-branch>: query GitHub, then fall back to local origin/HEAD
MAIN="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null \
  || git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')"
[ -z "$MAIN" ] && { git remote set-head origin --auto >/dev/null 2>&1; \
  MAIN="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')"; }
[ -n "$MAIN" ] || { echo 'Could not resolve default branch'; exit 1; }

# Guard: <main-branch> must be a real remote branch (gh may silently fall back otherwise)
git show-ref --verify --quiet "refs/remotes/origin/$MAIN" \
  || git ls-remote --exit-code --heads origin "$MAIN" >/dev/null 2>&1 \
  || { echo "Default branch '$MAIN' not found on origin"; exit 1; }

# Derive <branch-name> as "<issue-number>-<kebab-slug-of-title>"
TITLE="$(gh issue view "$ISSUE_NUMBER" --json title -q .title)"
SLUG="$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-50 | sed -E 's/-+$//')"
BRANCH="${ISSUE_NUMBER}-${SLUG:-issue}"
```

Then create the issue-linked branch, based on the default branch, and check it out locally with the explicit flags:

```bash
gh issue develop "$ISSUE_NUMBER" --base "$MAIN" --name "$BRANCH" --checkout
```

This is equivalent to: `gh issue develop <issue-number> --base <main-branch> --name <branch-name> --checkout`.

**VERIFICATION CHECKPOINT:** After executing, confirm:
- [ ] Branch created with the chosen name (`$BRANCH`), linked to the GitHub issue
- [ ] Branch is based on the default branch (`$MAIN`)
- [ ] Branch is checked out locally — `git rev-parse --abbrev-ref HEAD` equals `$BRANCH`
- [ ] Current branch is NOT main/master
- [ ] This happened BEFORE any analysis or code was written

**If no issue number provided:** Skip to Step 1 (ensure you're on a feature branch, not main/master).

---

## Step 1: Analyze

**ACTION REQUIRED:** Complete ALL of the following before proceeding:

- For **features/improvements**: State the expected behavior. List affected files.
- For **bug fixes**: List 2-3 root cause hypotheses. Identify the most likely cause.
- For **all tasks**: List 2-3 alternative approaches with trade-offs. Select one and explain why.
- **Parallelization assessment**: Identify which parts are independent and can be worked on concurrently in isolated worktrees. Record the dependency graph.

**VERIFICATION CHECKPOINT:** Before proceeding to Step 2, confirm:
- [ ] Expected behavior (for features) OR root cause (for bugs) is clearly stated
- [ ] Affected files are listed
- [ ] Alternative approaches were considered
- [ ] Selected approach is justified
- [ ] Parallelization assessment completed (independent units identified or none)

**If requirements are unclear:** STOP and ask the user. DO NOT proceed.

---

## Step 2: Write Tests First (TDD)

**ACTION REQUIRED:** Execute ALL of the following in order:

1. Write test cases that MUST fail (red phase) — testing behavior that does not exist yet
2. Write test cases that MUST pass (existing behavior that should not regress)
3. Run the test suite: use the EXACT command from `package.json` under `scripts.test`
4. Confirm the new tests fail as expected
5. If parallel implementation is planned, organize tests by independent work units

**VERIFICATION CHECKPOINT:** Before proceeding to Step 3, confirm:
- [ ] Test file created with failing test cases
- [ ] Test suite was run (using exact command from package.json)
- [ ] New tests failed (red phase confirmed)
- [ ] Tests organized by independent work units (if parallel planned)

**DO NOT:**
- Write any implementation code in this step
- Proceed if tests did not fail (investigate why first)

> **TDD sentinel:** a Stop hook enforces coverage ≥ threshold whenever uncommitted `.ts` files exist. Activate the red-phase bypass **before** writing failing tests: `touch <workspace-root>/.claude/.tdd-mode`. Remove it once implementation makes them green.

---

## Step 3: Implement

### Sequential (default)

**ACTION REQUIRED:** Write implementation code to make failing tests pass:

1. Modify source code only (NOT test files)
2. Run the test suite: use the EXACT command from `package.json` under `scripts.test`
3. Verify tests pass
4. If tests fail, fix implementation and repeat

**VERIFICATION CHECKPOINT:** Before proceeding to Step 4, confirm:
- [ ] Only source files were modified (not test files)
- [ ] All tests pass (including new tests)
- [ ] No hardcoded/fake implementation just to force pass

**DO NOT:**
- Modify test files in this step
- Fake implementation with hardcoded returns

**IF STUCK:** STOP and ask the user for help. Do not hack workarounds.

### Parallel (worktree-based subagents)

**ACTION REQUIRED:** Use when Step 1 identified **two or more independent work units** with no shared state.

1. Record the current branch name — this is the **original branch** for merge
2. For EACH independent unit, dispatch a subagent using Agent tool with `isolation: "worktree"`:
   - Clear description of work unit and owned files
   - Specific failing tests it must make pass
   - Instruction to NOT touch files outside its scope
   - Instruction to commit its work before finishing
3. Launch ALL subagents in a **single message** for maximum concurrency

**VERIFICATION CHECKPOINT:** After all subagents complete, confirm:
- [ ] All subagents finished their work units
- [ ] Each subagent committed its changes
- [ ] Worktree branch names recorded for merging

**DO NOT:**
- Let parallel agents write to the same working tree
- Proceed until all subagents report completion

### Step 3a: Merge Worktrees (ONLY if parallel was used)

**ACTION REQUIRED:** Execute the following for each worktree branch:

```bash
git checkout <original-branch>
git merge <worktree-branch-1> --no-edit
git merge <worktree-branch-2> --no-edit
# ... repeat for each worktree branch
```

If merge conflicts occur: resolve manually, favoring correctness.

**VERIFICATION CHECKPOINT:** Before proceeding to Step 4, confirm:
- [ ] All worktree branches merged into original branch
- [ ] Merge conflicts resolved (if any occurred)
- [ ] Combined code compiles
- [ ] Full test suite passes (integration check)

**DO NOT proceed to Step 4 until all merges are complete and codebase is stable.**

---

## Step 4: Run Tests and Build

**ACTION REQUIRED:** Execute ALL of the following:

1. Run tests: use the EXACT command from `package.json` under `scripts.test`
2. Run build: use the EXACT command from `package.json` under `scripts.build`
3. If either fails, fix and repeat

**VERIFICATION CHECKPOINT:** Before proceeding to Step 5, confirm:
- [ ] Test command was executed (exact command from package.json)
- [ ] All tests pass (new and existing)
- [ ] Build command was executed (exact command from package.json)
- [ ] Build succeeded with no errors

**DO NOT proceed to Step 5 if tests fail or build is broken.**

---

## Step 5: Code Review

**ACTION REQUIRED:** Review code WITHOUT making changes:

Check the following:
- [ ] Architecture compliance
- [ ] Naming conventions followed
- [ ] Single Responsibility Principle (SRP) respected
- [ ] Component structure follows atomic design
- [ ] Style guidelines met
- [ ] Code is clear and maintainable
- [ ] No unnecessary complexity
- [ ] If parallel used: consistency across merged work units

**VERIFICATION CHECKPOINT:** After review, output:
- If violations found: List each with file:line reference → PROCEED TO STEP 6
- If no violations: → PROCEED TO STEP 7

**DO NOT modify code in this step.**

---

## Step 6: Fix Code Review Issues

**ACTION REQUIRED:** For EACH violation found in Step 5:

1. Fix only what was flagged (do not over-engineer)
2. Run tests: use the EXACT command from `package.json` under `scripts.test`
3. Verify tests pass
4. Run build: use the EXACT command from `package.json` under `scripts.build`
5. Verify build succeeds

**VERIFICATION CHECKPOINT:** After fixes, confirm:
- [ ] All violations addressed
- [ ] Tests pass
- [ ] Build succeeds

→ RETURN TO STEP 5 for re-review

---

## Step 7: Security Review

**ACTION REQUIRED:** Review code WITHOUT making changes:

Check the following:
- [ ] Input validation present
- [ ] No injection risks (SQL, XSS, command injection)
- [ ] Authentication/authorization properly used
- [ ] No secrets exposed
- [ ] No insecure defaults
- [ ] OWASP Top 10 relevant items covered

**VERIFICATION CHECKPOINT:** After review, output:
- If issues found: List each with file:line reference → RETURN TO STEP 3
- If no issues: → TASK COMPLETE

**DO NOT modify code in this step.**

---

## Command Source Rule

**CRITICAL:** When the skill references test or build commands, it MUST:
1. Read `package.json` to find the EXACT command under `scripts.test` and `scripts.build`
2. Use that EXACT command — never use `# or equivalent` or guess
3. If the command doesn't exist, ask the user for the correct command

Example flow:
```
1. Read package.json
2. Find scripts.test = "vitest" or "vitest run" or similar
3. Use "pnpm vitest" or whatever the EXACT script is
```

---

## Non-Negotiable Rules

1. **Ask when unclear** — Never assume requirements
2. **Branch from the issue first** — When a GitHub issue number is provided, create and check out the branch via `gh issue develop` BEFORE writing any code or tests
3. **Tests first, always** — Write tests before implementation
4. **Never modify tests to pass** — Unless business requirements changed AND user confirms
5. **Never fake implementation** — No hardcoded returns, no skipped assertions
6. **Code review is read-only** — No changes during Step 5 or Step 7
7. **Security review is read-only** — No changes during Step 7
8. **Use exact commands** — Read from package.json, never guess
9. **Complete checkpoints** — Every step must pass its verification before proceeding
10. **Subagents use worktrees** — Never let parallel agents write to the same working tree
11. **Merge all worktrees** — All worktree branches must merge before Step 4
