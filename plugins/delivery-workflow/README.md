# delivery-workflow

A feature-delivery suite that drives code from a GitHub issue to a green PR. Four skills:

| Skill | What it does | Trigger |
|-------|--------------|---------|
| `dev-workflow` | Rigorous 8-step TDD cycle: branch from issue → analyze → tests-first → implement → test+build → code review → fix → security review. | "fix a bug", "add a feature", "implement #N" |
| `epic-workflow` | Orchestrates a GitHub Epic (Epic→Features→Tasks): builds the hierarchy, dependency graph, runs ready tasks (≤3 parallel), validates acceptance criteria, manages the project board. | "work on epic #N", "implement epic" |
| `pr-review-fix` | Reads all open PR review comments, plans fixes, applies one commit per issue (tests as a gate), replies inline, posts a summary table. | "fix PR comments", "address review feedback" |
| `pr-autoheal` | Drives a PR's CI to green: polls checks, pulls failing logs, diagnoses via a subagent, applies fixes, verifies, pushes — up to 5 iterations. | "autoheal PR #N", "fix CI on PR N" |
| `ci-autoheal` | Fixes failing GitHub Actions workflows with no PR (push to main, scheduled runs, CF deployments): discovers the run, diagnoses logs, applies fixes, verifies, commits, then either pushes directly (feature branches) or opens a hotfix PR (main/master) — up to 5 iterations. | "CI is failing on main", "fix the failing workflow", "deploy to CF failed", "/ci:autoheal" |

## Install
```bash
/plugin install delivery-workflow@claude-plugins
```

## ⚠️ This plugin installs a Stop hook
`dev-workflow` ships a **`Stop` coverage-gate hook** (`skills/dev-workflow/hooks/tdd-stop-guard.sh`).
Once this plugin is installed it runs on **every** stop: when there are uncommitted `.ts` files and the
repo has a `test:cov` script, it runs coverage and blocks stopping until it passes.

- It **no-ops** when there is no `test:cov` script or no uncommitted `.ts` files.
- Suspend it for the TDD red phase (write failing tests first):
  ```bash
  touch <workspace-root>/.claude/.tdd-mode   # re-enable: rm that file
  ```

## Dependencies
- **Required:** `git`, the GitHub CLI (`gh`, authenticated).
- **Optional (graceful):** `epic-workflow` calls `/delivery-workflow:dev-workflow` (bundled) and references
  the external `commit-commands` and `code-review` plugins. If those aren't installed, Claude performs the
  commit/PR and review steps inline.
- Test/build commands are read from the project's `package.json`.
