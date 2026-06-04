---
description: Enable three-tier cross-session memory for the current project (opt-in). Creates the user-local memory dir and seeds MEMORY.md + state, after which the SessionEnd capture and SessionStart recall hooks become active for this project.
argument-hint: "[project-dir]  (defaults to the current project)"
allowed-tools: Bash, Write, Read
---

# Enable memory for this project

Memory is **opt-in**: the SessionEnd capture and SessionStart recall hooks only do anything for
projects that have an initialized memory dir. This command creates that dir for the project, so run
it once per project you want remembered.

## 1. Resolve the project and its memory dir

The target project is `$ARGUMENTS` if provided, otherwise the **current working directory** (the
path Claude Code was launched in).

Derive the user-local memory dir the same way Claude Code names project dirs: take the project's
**absolute** path and replace every `:`, `\`, and `/` with `-`. That string is `<hash>`; the memory
dir is `~/.claude/projects/<hash>/memory`.

- Example (Windows): `C:\Users\me\proj` → `C--Users-me-proj`
- Example (POSIX): `/home/me/proj` → `-home-me-proj`

Sanity-check the hash: a directory `~/.claude/projects/<hash>/` should already exist for the current
project (it holds this session's transcript). List `~/.claude/projects/` and confirm the match
before writing. If the project passed as an argument has no such dir yet, that's fine — derive the
hash from its absolute path anyway.

## 2. If it already exists, stop

If `~/.claude/projects/<hash>/memory` already exists, report `memory already enabled for: <project>`
with the resolved path and do nothing else. Re-seeding would clobber existing memory.

## 3. Create the dir tree

Create these directories (use Bash `mkdir -p`, or PowerShell `New-Item -ItemType Directory -Force`):

```
<memory>/episodic/sessions/raw
<memory>/episodic/sessions/archive
<memory>/episodic/weekly
```

## 4. Seed the two state files

Write `<memory>/MEMORY.md` with **exactly** this content (the leading HTML comment is load-bearing —
it tells future sessions what may and may not be indexed here):

```
<!-- Tier-3 semantic index (auto-loaded every session). ONE line per durable memory.
     Index ONLY Tier-3 files (concept_*/project_*/feedback_*). Never list episodic logs here —
     those are injected at session start by the claude-memory plugin. -->
```

Write `<memory>/.memory-state.json` with exactly this content:

```json
{
  "schemaVersion": 1,
  "lastWeeklyConsolidation": null,
  "lastTier3Distill": null,
  "notes": "Bookkeeping for the claude-memory plugin. Updated by /claude-memory:consolidate. Dates are ISO 8601 (UTC)."
}
```

## 5. Confirm

Print:

```
memory enabled for: <project>
  -> <memory>
Capture (SessionEnd) and recall (SessionStart) are now active for this project.
```
