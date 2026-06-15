---
name: epic-workflow
description: Orchestrate Epic-driven feature development from GitHub Issues. Navigates an Epic issue hierarchy (Epic to Features to Tasks), manages GitHub Project board status (Backlog, Ready, In Progress, Review, Done), and orchestrates implementation using dev-workflow, commit-push-pr, and code-review skills with acceptance criteria validation. Use when the user wants to implement an Epic issue or says "work on epic #N", "implement epic", "start epic workflow", or similar.
---

# Epic Workflow

## Setup

Resolve repo and project metadata once, then reuse throughout:

```bash
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
gh project list --owner <owner> --format json   # find project number
```

Then fetch field/option IDs — see `references/gh-commands.md` section "Get Project Fields".

Cache these for the entire session: `projectId`, `statusFieldId`, option IDs for Backlog/Ready/In Progress/Review/Done.

---

## Phase 1: Discover Issue Hierarchy

Build a complete task list before starting any work.

```bash
gh issue view <epic_number> --repo <REPO> --json title,body,state
gh api repos/<OWNER>/<REPO>/issues/<epic_number>/sub_issues          # Features
gh api repos/<OWNER>/<REPO>/issues/<feature_number>/sub_issues       # Tasks
```

For each task, record:
- Issue number and title
- Parent feature
- Acceptance criteria (look for "Acceptance Criteria", "AC:", checklist items)
- Dependencies (look for "Depends on #N", "Blocked by #N", "Requires #N")
- Status in the project board

### Dedup Check (MANDATORY before Phase 3)

For every task, check for existing work before implementing:

```bash
# Check for branches matching the issue number
git branch -a | grep -i "<issue_number>"

# Check for recent comments on the issue (may indicate prior work)
gh issue view <issue_number> --repo <REPO> --json comments --jq '.comments[].body'
```

If a branch exists:
1. Read its latest commits: `git log origin/<branch> --oneline -10`
2. Read issue comments for prior decision logs
3. **Resume from existing work** — do NOT start fresh. Checkout the existing branch and continue.
4. Post a decision-log comment noting the resume: `"Resuming from branch <branch>. Last commit: <msg>"`

---

## Phase 2: Dependency Analysis

Parse each task body for blocking dependencies. Build a directed graph:
- Nodes = tasks
- Edges = "must complete before"

Tasks with zero incoming edges (no blockers) are **ready to start**.

### Conflict Detection

While analyzing dependencies, check for:
- **Contradictory ACs** between tasks that share files or state
- **Circular dependencies** (A blocks B blocks A)
- **Conflicting requirements** (Task A says "use X pattern", Task B says "use Y pattern")

If conflicts found: **STOP and escalate** — see Conflict Escalation Protocol below.

---

## Phase 3: Execution Loop

Repeat until all tasks are Done:

1. Identify all tasks that are ready (no pending dependencies)
2. Check for existing work (Dedup Check above)
3. **HARD LIMIT: count currently running subagents. If >= 3, WAIT for one to finish before spawning another.**
4. Only parallelize tasks with no shared file dependencies
5. Bundle tasks into a single PR when they cannot be independently deployed or tested
6. When a task completes, post Decision Log comment, mark dependents as unblocked

### Per-Task Workflow

#### Step 1 — Move to In Progress
```bash
# See references/gh-commands.md "Full Status Update Workflow"
```

#### Step 2 — Create or Resume Branch
```bash
git fetch origin

# If dedup check found an existing branch:
git checkout <existing-branch>

# Otherwise, new branch from master (or dependency branch):
git checkout -b <issue-number>-<short-slug> origin/master
```

Branch naming: `<issue-number>-<kebab-title>` (e.g. `312-add-login-page`)

#### Step 3 — Implement
Use `/delivery-workflow:dev-workflow` skill.

#### Step 4 — Commit, Push, PR
Use `/commit-commands:commit-push-pr` skill.

PR description must:
- Reference the issue: `Closes #<issue-number>`
- List the acceptance criteria being satisfied with checkmarks

#### Step 5 — AC Validation Gate (MANDATORY)

**This step is a hard gate. It cannot be skipped or relaxed.**

1. Re-read the task's acceptance criteria from the issue body
2. For EACH criterion, verify it is satisfied by the code in the PR
3. Check ALL of the following:
   - Every AC has a corresponding implementation in the diff
   - Every AC is covered by at least one test (if tests apply)
   - No AC is marked "TODO" or "will do later"

**If ALL criteria pass:**
- Post AC validation comment on the issue (see references/gh-commands.md)
- Proceed to Step 6

**If ANY criterion fails:**
- Do NOT move to Review
- Move issue back to **In Progress**
- Add a comment listing unmet criteria
- Return to Step 3 and implement the missing pieces
- Repeat from Step 4

**If an AC is contradictory or cannot be satisfied as written:**
- Do NOT skip it
- Follow the Conflict Escalation Protocol below

#### Step 6 — Post Decision Log (MANDATORY)

Before moving to Review, post a decision-log comment on the issue. See Decision Log Protocol below.

#### Step 7 — Move to Review
Only after AC validation passes AND decision log is posted:
```bash
# Update project board status to Review
# See references/gh-commands.md
```

---

## Decision Log Protocol

At the end of every task (before moving to Review), post a concise comment on the issue:

```markdown
## Decision Log

**Implemented:** <1-2 lines summarizing what was done>

**Key decisions:**
- <Decision>: <why> (considered: <alternative>)
- <Decision>: <why>

**Errors found:**
- <Error>: <how resolved>

**Unexpected:**
- <Anything noteworthy>
```

**Rules:**
- Keep each bullet to 1-2 lines max
- Focus on WHY, not HOW (the code shows how)
- Always mention alternatives that were considered and rejected
- Always mention errors encountered during implementation
- Do NOT dump code or lengthy explanations

---

## Conflict Escalation Protocol

When encountering any of these situations:
- Contradictory acceptance criteria
- An AC that conflicts with existing code or architecture
- A dependency that cannot be resolved
- Two tasks that require incompatible changes to the same files
- An AC that is technically impossible or unclear

**Take ONE of these actions (in order of preference):**

1. **Ask the user directly** if they are available — present the conflict and ask for resolution
2. **Open a blocking issue** titled `"[Blocker] <conflict summary>"`, assigned to the user, with:
   - Description of the conflict
   - The two+ competing requirements
   - Suggested resolutions
   - Link to the original task(s)
3. **Comment on the affected issue(s)** noting the blocker and linking to the blocker issue

**Never silently resolve a conflict.** Never pick a side without informing the user. Never skip an AC because it seems wrong.

---

## Project Board Status Values

| Status | Used When |
|--------|-----------|
| `Backlog` | Not yet started |
| `Ready` | Triaged, ready to pick up |
| `In Progress` | Actively being implemented |
| `Review` | PR open, AC validated, pending review |
| `Done` | Merged |

---

## Parallelism Rules (HARD LIMITS)

- **MAXIMUM 3 parallel subagents** — count before spawning, wait if at limit
- Only parallelize tasks with no shared file dependencies
- Bundle tasks into a single PR when they cannot be independently deployed or tested
- When in doubt, serialize — safety over speed

---

## References

- See `references/gh-commands.md` for GitHub Projects GraphQL commands, status updates, and comment templates
