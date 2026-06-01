# GitHub Projects & Issues — gh Commands Reference

## Table of Contents
1. [Detect Current Repo](#detect-current-repo)
2. [List Projects](#list-projects)
3. [Get Project Fields and Status Option IDs](#get-project-fields-and-status-option-ids)
4. [Find Issue Item in Project](#find-issue-item-in-project)
5. [Move Issue Status in Project](#move-issue-status-in-project)
6. [Fetch Sub-issues](#fetch-sub-issues)
7. [Add Issue Comment](#add-issue-comment)
8. [Dedup Check Commands](#dedup-check-commands)
9. [AC Validation Comment Template](#ac-validation-comment-template)
10. [Decision Log Comment Template](#decision-log-comment-template)
11. [Conflict Escalation Issue Template](#conflict-escalation-issue-template)
12. [Full Status Update Workflow](#full-status-update-workflow)

---

## Detect Current Repo

```bash
gh repo view --json nameWithOwner --jq '.nameWithOwner'
# Output: owner/repo
```

---

## List Projects

For a user owner:
```bash
gh project list --owner <owner> --format json --jq '.projects[] | {number: .number, title: .title}'
```

For an org owner:
```bash
gh project list --owner <org> --format json --jq '.projects[] | {number: .number, title: .title}'
```

---

## Get Project Fields and Status Option IDs

Run once per session and cache the output.

```bash
gh api graphql -f query='
query($owner: String!, $number: Int!) {
  user(login: $owner) {
    projectV2(number: $number) {
      id
      fields(first: 20) {
        nodes {
          ... on ProjectV2SingleSelectField {
            id
            name
            options { id name }
          }
          ... on ProjectV2Field {
            id
            name
          }
        }
      }
    }
  }
}' -f owner="<owner>" -F number=<project_number>
```

If the owner is an org, replace `user` with `organization`:
```bash
gh api graphql -f query='
query($org: String!, $number: Int!) {
  organization(login: $org) {
    projectV2(number: $number) {
      id
      fields(first: 20) {
        nodes {
          ... on ProjectV2SingleSelectField {
            id
            name
            options { id name }
          }
        }
      }
    }
  }
}' -f org="<org>" -F number=<project_number>
```

From the output, extract and store:
- `projectId` — the `id` of the project
- `statusFieldId` — the `id` of the field named "Status"
- Option IDs for: `Backlog`, `Ready`, `In Progress`, `Review`, `Done`

---

## Find Issue Item in Project

```bash
# List all items in the project with their linked issue numbers
gh api graphql -f query='
query($projectId: ID!) {
  node(id: $projectId) {
    ... on ProjectV2 {
      items(first: 100) {
        nodes {
          id
          content {
            ... on Issue {
              number
              title
            }
          }
        }
      }
    }
  }
}' -f projectId="<project_id>"
```

Filter by issue number:
```bash
# Pipe through jq to find the item ID for issue #N
... | jq '.data.node.items.nodes[] | select(.content.number == <issue_number>) | .id'
```

If the issue is not yet in the project, add it:
```bash
gh project item-add <project_number> --owner <owner> --url "https://github.com/<owner>/<repo>/issues/<issue_number>"
# Returns the new item ID
```

---

## Move Issue Status in Project

```bash
gh project item-edit \
  --id <item_id> \
  --project-id <project_id> \
  --field-id <status_field_id> \
  --single-select-option-id <option_id>
```

Replace `<option_id>` with the ID for the desired status:
- `Backlog` option ID
- `Ready` option ID
- `In Progress` option ID
- `Review` option ID
- `Done` option ID

---

## Fetch Sub-issues

```bash
# Sub-issues of an issue (Features under Epic, or Tasks under Feature)
gh api repos/<owner>/<repo>/issues/<issue_number>/sub_issues
```

Returns an array of issue objects. Key fields: `number`, `title`, `body`, `state`.

---

## Add Issue Comment

```bash
gh issue comment <issue_number> --repo <owner>/<repo> --body "$(cat <<'EOF'
<comment body here>
EOF
)"
```

---

## Dedup Check Commands

Run these BEFORE starting implementation on any task to avoid duplicating work from a prior session.

### Check for existing branches

```bash
# Branches matching the issue number
git fetch origin
git branch -a | grep -i "<issue_number>"

# If a branch exists, inspect its history
git log origin/<branch_name> --oneline -10

# See what files were changed
git diff origin/master...origin/<branch_name> --stat
```

### Check for prior session comments on the issue

```bash
# Read existing comments (look for "Decision Log" or "Resuming" comments)
gh issue view <issue_number> --repo <owner>/<repo> --json comments --jq '.comments[] | {body: .body, createdAt: .createdAt}'
```

### If existing work found

1. Checkout the existing branch: `git checkout <branch_name>`
2. Read the last decision log comment to understand where work stopped
3. Continue from that point — do NOT recreate the branch or start fresh
4. Post a resume comment:
```bash
gh issue comment <issue_number> --repo <owner>/<repo> --body "$(cat <<'EOF'
Resuming from branch `<branch_name>`. Last commit: <commit_message>. Continuing from where the previous session left off.
EOF
)"
```

---

## AC Validation Comment Template

Post this comment after all acceptance criteria have been verified:

```bash
gh issue comment <issue_number> --repo <owner>/<repo> --body "$(cat <<'EOF'
## AC Validation — PASSED

All acceptance criteria verified against PR #<pr_number>:

- [x] <AC 1> — satisfied by <file/path> <and/or> test <test_name>
- [x] <AC 2> — satisfied by <file/path>
- [x] <AC 3> — satisfied by <file/path>

Moving to Review.
EOF
)"
```

### If an AC fails validation

```bash
gh issue comment <issue_number> --repo <owner>/<repo> --body "$(cat <<'EOF'
## AC Validation — FAILED

The following acceptance criteria are NOT satisfied:

- [ ] <AC that failed>: <reason> (<file/path> or missing coverage)
- [ ] <AC that failed>: <reason>

Returning to In Progress. Will implement missing pieces and re-validate.
EOF
)"
```

---

## Decision Log Comment Template

Post this at the end of every task before moving to Review. Keep it concise — focus on decisions and surprises, not implementation details.

```bash
gh issue comment <issue_number> --repo <owner>/<repo> --body "$(cat <<'EOF'
## Decision Log

**Implemented:** <1-2 line summary of what was done>

**Key decisions:**
- <Decision A>: <why> (considered: <alternative>)
- <Decision B>: <why>

**Errors found:**
- <Error>: <how resolved>

**Unexpected:**
- <Anything noteworthy — conflicts, missing deps, weird edge cases>
EOF
)"
```

**Rules for decision logs:**
- Each bullet: 1-2 lines max
- Focus on WHY, not HOW (the code shows how)
- Always mention alternatives considered and rejected
- Always mention errors encountered
- Never dump code or lengthy explanations

---

## Conflict Escalation Issue Template

When a conflict is found that cannot be resolved autonomously, open a blocker issue:

```bash
gh issue create --repo <owner>/<repo> \
  --title "[Blocker] <conflict summary>" \
  --body "$(cat <<'EOF'
## Conflict

While working on #<original_issue>, a conflict was found that requires user decision.

### The conflict
<Describe the contradiction or impossibility>

### Competing requirements
- **Requirement A** (from #<issue_a>): <description>
- **Requirement B** (from #<issue_b>): <description>

### Suggested resolutions
1. <Option 1>
2. <Option 2>

### Impact
- <What is blocked and why>

---

Blocking: #<affected_issues>
EOF
)" \
  --assignee <user> \
  --label "blocker"
```

---

## Full Status Update Workflow

Convenience pattern — do this every time you need to move an issue status:

```bash
# 1. Get item ID for the issue
ITEM_ID=$(gh api graphql -f query='...' | jq -r '.data.node.items.nodes[] | select(.content.number == <N>) | .id')

# 2. Update status
gh project item-edit \
  --id "$ITEM_ID" \
  --project-id "<PROJECT_ID>" \
  --field-id "<STATUS_FIELD_ID>" \
  --single-select-option-id "<OPTION_ID>"
```

Cache `PROJECT_ID`, `STATUS_FIELD_ID`, and option IDs at the start of the session — they don't change between tasks.
