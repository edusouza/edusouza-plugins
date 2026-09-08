# Golden files

Each `<name>.txt` is the exact expected stdout of `bin/wiki-lint.sh` run against
`../fixtures/<name>/wiki`.

Byte counts in the "Injection budget" block are **not** platform artifacts — `wiki-lint` strips CR
before measuring, so the same fixture reports the same number on CRLF and LF input. If a count
differs, the `tr -d '\r'` in the region extraction is missing or misplaced: **fix the script, not
the golden file.** (This repo sets `core.autocrlf=true` and marks `*.md` as `text`, so fixtures are
CRLF in the working tree on Windows. That is exactly why the strip is load-bearing.)

## Recorded baseline (not a test)

`wiki-lint.sh` against this repo's own claude-memory dir on 2026-08-21, before any wiki existed.
Kept as a before/after reference for Phase 2. Deliberately **not** asserted anywhere — these counts
change every week.

```
## Structural
  pages                : 18
  wikilinks            : 11
  broken links         : 1
  orphans              : 8
  missing frontmatter  : 3

  BROKEN:
    prefer-scripts-over-inline-shell-in-skills -> [[dev-workflow-branch-before-coding]]

  ORPHANS:
    concept_check_existing_conventions_first
    concept_git_ordering_ancestor_check
    concept_plugin_command_path_resolution
    concept_plugin_marketplace_naming
    concept_robust_remediation_skill_design
    concept_shared_file_delimited_regions
    concept_source_of_truth_over_catalog_entry
    concept_verify_before_destroy

  NO FRONTMATTER:
    bump-plugin-version-on-change (missing: last_accessed, status, type)
    prefer-scripts-over-inline-shell-in-skills (missing: last_accessed, status, type)
    stale-plugin-cache-reinstall (missing: last_accessed, status, type)

## Injection budget
  index region         : 0 B (~0 tokens)
```

### Reading the baseline

- **8 of 18 pages are orphans (44%)** — nothing links to them. Every one is a `concept_*` that
  Tier-3 distillation wrote in isolation.
- **The 1 broken link targets a page that was never written.** `[[dev-workflow-branch-before-coding]]`
  has no file anywhere in the dir.
- **The 3 frontmatter findings are a schema collision, not sloppiness.** Those files carry nested
  `metadata: { node_type, type }` frontmatter — the global auto-memory's schema — while
  `concept_*` files carry the flat `type:` / `status:` / `last_accessed:` schema that
  `tier3-distill.md` mandates. Two systems write this directory with two incompatible schemas, which
  is the collision that prompt explicitly warns against. `lint` reports it; deciding what to do is
  the user's call.
- **Index region is 0 B** because a pre-wiki memory dir has no `index.md` with a managed
  `memory-wiki` region. Phase 2 is what makes that number non-zero.
