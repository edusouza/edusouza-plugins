---
name: spec-to-issues
description: Create a GitHub issue hierarchy from a spec or PRD folder. Detects the spec layout (OpenSpec, a single PRD/markdown doc, or a generic docs/spec folder), then generates an Epic issue, Spec/Feature issues as children of the Epic, and Task issues as children of their Spec. Each issue gets a detailed description, acceptance criteria, size (XS/S/M/L/XL), and blocked-by/blocking relationships via sub-issues. Creates a feature label for filtering. Supports dry-run preview. Use when the user wants to create GH issues from a spec/PRD folder, push specs to GitHub, convert specs to issues, or sync a spec to a GitHub project board.
---

# Spec to GitHub Issues

Convert a spec or PRD into a structured GitHub issue hierarchy: **Epic > Specs/Features > Tasks**.

## Workflow

### 1. Identify and Read the Spec Source

Ask the user which folder (or file) to process, or accept it as an argument. The goal is to extract three
things regardless of format: a **top-level feature** (→ Epic), **requirement groups** (→ Specs/Features),
and **granular tasks** (→ Tasks). Detect the layout:

**OpenSpec change folder:**
```
openspec/changes/<change-name>/
  .openspec.yaml        # Metadata
  proposal.md           # Why, What Changes, Capabilities, Impact      → Epic
  design.md             # Context, Goals, Decisions, Risks, Migration  → Epic
  specs/<spec-name>/
    spec.md             # Requirements with WHEN/THEN scenarios        → Specs
  tasks.md              # Numbered task groups with checkboxes          → Tasks
```

**Single PRD / design doc** (`PRD.md`, `design.md`, `rfc-*.md`, etc.):
- Epic ← the doc's title + overview/goals
- Specs ← top-level sections / requirement groups (`##` headings, "Requirements", capabilities)
- Tasks ← checklist items, "Tasks"/"Implementation" subsections, or numbered steps

**Generic `docs/`/spec folder** (multiple markdown files, no fixed schema):
- Epic ← a README/index or the folder's purpose
- Specs ← one per major doc/feature area
- Tasks ← checklists or numbered steps within each doc

If the structure is ambiguous, infer the best mapping and **confirm it with the user** before creating
anything (the dry-run in step 6 is the safety gate). The key invariant: extract a top-level feature
description, requirement groups, and granular tasks — the GitHub machinery below is identical regardless
of source format.

### 2. Detect Repository and Project

Auto-detect from git remote:
```bash
gh repo view --json nameWithOwner -q .nameWithOwner
```

If detection fails, ask the user for `owner/repo`.

Then fetch repo metadata (repository ID, issue types, project, fields). See `references/gh-graphql-mutations.md` for the query.

Required IDs to collect:
- **Repository ID**
- **Issue Type IDs**: Epic, Feature, Task
- **Project ID** (first project, or ask user if multiple)
- **Size field ID** and option IDs (XS, S, M, L, XL)
- **Status field ID** and "Backlog" option ID
- **Existing labels** (to avoid duplicates)

### 3. Parse the Change Artifacts

Read all artifacts and build a structured plan:

**Epic** (from `proposal.md` + `design.md`):
- Title: Human-readable name derived from the change folder name
- Description: Combine the "Why" section from proposal and "Goals/Non-Goals" from design
- Acceptance Criteria: Derive from the "Impact" section of proposal and the overall migration/implementation plan
- Size: XL (epics are always XL)

**Specs** (from each `specs/*/spec.md`):
- Title: Derived from the spec folder name, human-readable
- Description: Combine all requirements from the spec
- Acceptance Criteria: Extract directly from WHEN/THEN scenarios
- Size: Estimate based on number of requirements and scenarios (1-2 requirements = S, 3-4 = M, 5+ = L)
- Blocking/Blocked-by: Infer from the order and dependencies in `tasks.md` -- if tasks for spec A must complete before spec B starts, A blocks B

**Tasks** (from `tasks.md`):
- Title: The task checkbox text
- Description: Include the task text plus context from the parent spec and the section it belongs to
- Acceptance Criteria: Derive from the task description and related spec scenarios
- Size: Estimate based on task complexity (single config change = XS, multi-file implementation = M, full page build = L)
- Parent Spec: Map each task group to its corresponding spec based on naming/numbering

### 4. Map Tasks to Specs

The `tasks.md` file has numbered sections (e.g., "1. Project Scaffold", "2. OpenAPI Codegen Pipeline"). Map each section to a spec:

- Match by name similarity (e.g., "Project Scaffold" -> `vue-app-scaffold` spec)
- Match by content overlap (task mentions same files/concepts as spec requirements)
- If a section has no matching spec, it becomes a direct child of the Epic
- Present the mapping to the user for confirmation

### 5. Determine Relationships

Analyze dependencies between specs:
- **Explicit ordering**: If `tasks.md` phases indicate sequence (Phase 0 before Phase 1), specs in earlier phases block later ones
- **Content dependencies**: If spec B references outputs of spec A (e.g., "uses the typed client from openapi-codegen"), A blocks B
- **Present relationships** for user confirmation

### 6. Dry-Run Preview

Before creating anything, display a complete preview:

```
LABEL: <label-name> (color: <hex>)

EPIC: <title> [XL]
  Description: <first 100 chars>...
  Acceptance Criteria: <count> items

  SPEC: <title> [Size]
    Blocked by: <spec-names>
    Blocking: <spec-names>
    Acceptance Criteria: <count> items
    TASKS:
      - <task-title> [Size]
      - <task-title> [Size]
      ...

  SPEC: <title> [Size]
    ...
```

Also show totals: issue count, label name, project assignment.

**Wait for user approval before proceeding.**

### 7. Create Issues

Execute in this order (dependencies require sequential creation):

#### 7a. Create Label
Create a label named after the change (e.g., `epic:migrate-angular-to-vue`). Use a random pleasant color. Check if it already exists first.

#### 7b. Create Epic
- Issue Type: Epic
- Label: the created label
- Body format:

```markdown
## Overview
<from proposal "Why" section>

## Goals
<from design "Goals" section>

## Non-Goals
<from design "Non-Goals" section>

## Acceptance Criteria
- [ ] <criterion 1>
- [ ] <criterion 2>
...

## Specs
_Sub-issues track individual specs_

## Size
XL
```

- Add to project, set Size = XL, Status = Backlog

#### 7c. Create Spec Issues
For each spec, in dependency order:
- Issue Type: Feature
- Label: same label
- Body format:

```markdown
## Overview
<summarize the spec's requirements>

## Requirements
<list all requirements from spec.md>

## Acceptance Criteria
- [ ] <from WHEN/THEN scenarios>
...

## Size
<XS|S|M|L|XL>

## Dependencies
- Blocked by: #<number>, #<number>
- Blocking: #<number>, #<number>
```

- Add as sub-issue of Epic via `addSubIssue`
- Add to project, set Size and Status = Backlog

#### 7d. Create Task Issues
For each task:
- Issue Type: Task
- Label: same label
- Body format:

```markdown
## Description
<task description with context from parent spec>

## Acceptance Criteria
- [ ] <derived from task and spec>
...

## Size
<XS|S|M|L|XL>
```

- Add as sub-issue of parent Spec via `addSubIssue`
- Add to project, set Size and Status = Backlog

### 8. Summary

After creation, display:
- Total issues created (Epic + Specs + Tasks)
- Link to the Epic issue
- Link to filter by label: `https://github.com/<owner>/<repo>/issues?q=label:<label-name>`
- Any errors encountered

## GraphQL Reference

See `references/gh-graphql-mutations.md` for all mutation templates.

## Key Rules

- **Never create duplicate labels** -- check existing labels first
- **Sequential creation** -- Epic first, then Specs (need Epic ID for sub-issue), then Tasks (need Spec IDs)
- **Rate limiting** -- GitHub GraphQL has rate limits. If hitting limits, pause briefly between batches
- **Error recovery** -- If a task creation fails, log it and continue with remaining tasks. Report failures at the end
- **Label format** -- `epic:<change-name>` (lowercase, hyphenated)
- **Max 3 parallel API calls** -- avoid overwhelming GitHub API
