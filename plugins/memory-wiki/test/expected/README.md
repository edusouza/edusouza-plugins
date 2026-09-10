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

## Recorded after-baseline (not a test)

`wiki-lint.sh` against the wiki produced by one full `ingest` run over this repo's own eight
rollups (2026-W23 … 2026-W31), on 2026-09-09, at `memory-wiki` 0.4.0. Run against a disposable
copy of the memory dir, not the live one. Like the baseline above, deliberately **not** asserted
anywhere.

```
## Structural
  pages                : 8
  wikilinks            : 104
  broken links         : 0
  orphans              : 0
  missing frontmatter  : 0
  schema errors        : 0

## Injection budget
  index region         : 1644 B (~456 tokens)
```

Eight pages: 1 `project_`, 1 `component_`, 6 `failure_`. The index region renders 6 symptom lines
and 2 Map entries. Clean on the first attempt; no repair pass was needed.

### What this number does and does not license

- **The one clean before/after is the injection budget: 0 B → 1644 B.** That is what Phase 2 was
  for, and it is the only line in the two blocks that measures the same thing on both sides.
- **The two blocks count different populations. `orphans 8 → 0` is not a repair.** The baseline
  above lints the memory dir *root*, where the flat Tier-3 notes are the pages. This block lints
  `memory/wiki`, where those notes are `--concepts` link targets and the 8 wiki pages are the
  pages. Lint the same dir at root scope after this run and it still reports orphans, a broken
  link and missing frontmatter — the root corpus has grown since 2026-08-21 and is no tidier.
  Never place the two blocks side by side as a delta.
- **The meaningful analogue is inbound edges into Tier 3, and it went the wrong way.** This run
  gives most root notes an inbound edge from a wiki page. An earlier trial run over the same
  corpus reached more, by spending its cap on `component_`/`tech_` pages instead of failures.
  §1's cap order optimises symptom reachability and de-optimises concept reachability, and nothing
  measures the second.
- **Structural lint saturates and does not grade an ingest.** Three separate trial runs over this
  corpus, against three different revisions of the authoring reference, all reported 0 broken /
  0 orphans / 0 missing frontmatter / 0 schema errors. The quality differences between them were
  entirely in `symptom:` lines and prose. These counts are a floor, not a score.
- **The `component_` page is contaminated by construction and cannot be cited as evidence.** §9 of
  `skills/ingest/references/page-authoring.md` is a worked `component_claude-memory` exemplar
  built from this same corpus. All three trial runs reproduce parts of its wording. The same
  hazard applies more weakly to §8 and to any `failure_` page about plugin command path
  resolution. Exclude both subjects from any judgement about derivation quality.
- **n = 1 per reference revision, one agent per run.** Of the five changes made to the authoring
  reference before this run, two have a documented counterfactual against the previous run (the
  `(no error)` last-resort bound in §3; the de-corpused §3 example strings). Three do not, and are
  recorded here as unvalidated: the §1 cap-shortage rule, the corrected pending-source claim in
  §1, and the §6 artifact-identifier clause.
- **The 6-failure page count is not attributable to the reference.** The run homed three repo-wide
  failures on the `project_` page, which §1 step 3 does not license — it names `component_` and
  `tech_` only. That extension freed the three slots. A future run that reads §1 literally will
  fit three failures, not six.
