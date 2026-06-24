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

- [ ] **Step 0: Branch from Issue** (if applicable) — Branch created from GitHub issue
- [ ] **Step 1: Analyze** — Requirements understood, alternatives considered, parallelization assessed
- [ ] **Step 2: Write Tests First (TDD)** — Tests written, tests fail (red phase)
- [ ] **Step 3: Implement** — Implementation complete, tests pass (or worktrees merged)
- [ ] **Step 4: Run Tests and Build** — Tests pass, build succeeds
- [ ] **Step 5: Code Review** — Code reviewed, no violations OR proceed to Step 6
- [ ] **Step 6: Fix Code Review Issues** — (ONLY if Step 5 found violations) Issues fixed, return to Step 4
- [ ] **Step 7: Security Review** — Security reviewed, no issues OR return to Step 3

---

## Step 0: Branch from Issue (if applicable)

**ACTION REQUIRED:** If the user provides a GitHub issue number, execute:

```bash
gh issue develop <issue-number>
```

**VERIFICATION CHECKPOINT:** After executing, confirm:
- [ ] Branch created from GitHub issue
- [ ] Current branch is the new feature branch (not main/master)
- [ ] Branch is linked to the GitHub issue

**If no issue number provided:** Skip to Step 1 (ensure you're on a feature branch, not main/master).

---

## Step 1: Analyze

**ACTION REQUIRED:** Dispatch an **Explore subagent** first, then synthesize findings.

### 1a — Launch Explore agent

Dispatch an `Explore` subagent (subagent_type) with a prompt that includes the task description and asks it to:
- Find all files likely affected (source, tests, types, config)
- Trace the call graph / dependency chain from the entry point
- For bug fixes: locate where the symptom surfaces and list candidate root-cause sites
- Report the dependency graph and flag any shared state between potential work units

### 1b — Synthesize (after Explore returns)

Using the Explore findings, complete ALL of the following:

- For **features/improvements**: State the expected behavior. Confirm affected files from Explore output.
- For **bug fixes**: State the most likely root cause (from the candidate sites Explore identified). List 2-3 hypotheses ranked by likelihood.
- For **all tasks**: List 2-3 alternative approaches with trade-offs. Select one and explain why.
- **Parallelization assessment**: Using the dependency graph from Explore, identify which work units are independent (no shared file writes). Record the dependency graph.

**VERIFICATION CHECKPOINT:** Before proceeding to Step 2, confirm:
- [ ] Explore agent returned affected files and dependency graph
- [ ] Expected behavior (for features) OR root cause (for bugs) is clearly stated
- [ ] Alternative approaches were considered and one selected
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

**ACTION REQUIRED:** Launch all three review agents in a **single message** for maximum concurrency. Get the git diff first, then pass it to each agent.

1. **Agent 1** — `pr-review-toolkit:code-reviewer` (subagent_type)
   - Prompt includes: the git diff of changed files + "Review for architecture compliance, naming conventions, SRP, atomic component structure, style guidelines, clarity, and maintainability. If parallel worktrees were merged, also check consistency across work units. Return findings with file:line references."

2. **Agent 2** — `pr-review-toolkit:silent-failure-hunter` (subagent_type)
   - Prompt includes: the git diff of changed files + "Find silent failures, swallowed errors, inadequate error handling, and inappropriate fallback behavior. Return findings with file:line references."

3. **Agent 3** — `pr-review-toolkit:type-design-analyzer` (subagent_type)
   - Prompt includes: the git diff of changed files + "Review new or modified types for encapsulation quality, invariant expression, and usefulness. Return findings with file:line references."

**VERIFICATION CHECKPOINT:** After all three agents complete, confirm:
- [ ] All three agents finished
- [ ] Findings collected and merged from all agents

**After collecting findings:**
- If any violations found: List each with file:line reference → PROCEED TO STEP 6
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

**ACTION REQUIRED:** Launch a dedicated security review agent. Get the git diff first, then dispatch:

- **Agent** — `pr-review-toolkit:code-reviewer` (subagent_type)
  - Prompt includes: the git diff of changed files + "Perform a security-only review. Check: input validation, injection risks (SQL, XSS, command injection), authentication/authorization usage, exposed secrets or credentials, insecure defaults, and OWASP Top 10 items relevant to this diff. Do NOT flag style or architecture issues — security only. Return findings with file:line references and severity (critical/high/medium/low)."

**VERIFICATION CHECKPOINT:** After the agent completes, output:
- If issues found: List each with file:line reference and severity → RETURN TO STEP 3
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
2. **Tests first, always** — Write tests before implementation
3. **Never modify tests to pass** — Unless business requirements changed AND user confirms
4. **Never fake implementation** — No hardcoded returns, no skipped assertions
5. **Code review is read-only** — No changes during Step 5 or Step 7
6. **Security review is read-only** — No changes during Step 7
7. **Use exact commands** — Read from package.json, never guess
8. **Complete checkpoints** — Every step must pass its verification before proceeding
9. **Subagents use worktrees** — Never let parallel agents write to the same working tree
10. **Merge all worktrees** — All worktree branches must merge before Step 4
