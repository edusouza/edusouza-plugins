---
name: lint
description: Audit a project's memory wiki for structural and content drift. Runs the bundled wiki-lint script for exhaustive structural checks (broken wikilinks, orphan pages, missing frontmatter, injection budget), then adds the judgment-based checks a script cannot make — contradictions between pages, claims superseded by newer sources, and entities that recur across pages without their own page. Use when the user says "lint the memory wiki", "audit my memory", "what's broken in my memory", or asks what the memory is missing.
---

# Lint the memory wiki

Two halves: the script is exhaustive about structure, you are selective about content.

## 1. Structure — run the script, do not reimplement it

Resolve the memory dir from the `## Memory - dir for this project` line injected at session start.
Prefer that path over deriving it from the cwd — inside a git worktree the derivation resolves to the
main repo, and getting it wrong points the audit at the wrong project.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/bin/wiki-lint.sh" "<memdir>/wiki" \
  --sources "<memdir>/episodic/weekly" \
  --atlas "$HOME/.claude/memory-wiki"
```

If `<memdir>/wiki` does not exist yet, run the script against `<memdir>` itself. The flat
`concept_*.md` files there are a wiki with no edges, and auditing them is the whole point of this
phase — a pre-wiki memory dir is the normal case, not an error.

On Windows, or wherever shelling out proves unreliable, `bin/wiki-lint.ps1` produces byte-identical
output (`-WikiDir` / `-Sources` / `-Atlas`).

Relay the counters verbatim. Do not re-derive them by hand and do not fix anything.

## 2. Content — your half: judgment, not enumeration

Read `wiki/log.md` for what changed recently, then read the pages the script flagged plus any the log
touched. Flag only the most significant instances of:

- **Contradictions** — two pages making conflicting claims. Name both, say which source each came
  from, and do not silently pick a winner.
- **Stale claims** — an assertion contradicted by a more recent source, or by the repo's actual
  current state. **Verify against the filesystem before reporting it**, not from memory alone; a
  claim that a file exists is checkable in one command.
- **Missing pages** — an entity named across three or more pages with no page of its own.
- **Weak cross-references** — pages that clearly belong linked and are not.

## 3. Report

```
## Structural
<script output, verbatim>

## Content
<contradictions, stale claims, missing pages, weak links — top findings only>

## What to do next
<the 1-3 highest-value actions, each naming the specific page or source involved>
```

## Rules

- **Report; never fix.** Every finding is the user's call. This is the whole contract of the skill —
  an audit does not imply permission to change anything.
- Structural findings: exhaustive (the script guarantees it). Content findings: prioritized.
- **A broken link whose target is a human title rather than a filename is the single most common
  defect.** Say so explicitly when you see it — the fix is a rename, not a new page. Likewise a link
  written as a kebab-slug against a `snake_case` file.
- **A page flagged for missing frontmatter may belong to a different system.** Files written by the
  global auto-memory use nested `metadata:` frontmatter rather than the flat schema; that is a schema
  collision worth reporting as such, not a page to "fix".
