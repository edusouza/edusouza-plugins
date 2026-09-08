# memory-wiki Phase 2 (ingest + index region + injection) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **This plan specifies behaviour, not source.** Implementations are deliberately not written out — each task states the contract, the failure modes to handle, and the assertions that must pass. Match the surrounding code's style: read the Phase 1 scripts in `plugins/memory-wiki/bin/` and `claude-memory`'s hooks before writing anything.

**Goal:** Turn `claude-memory`'s weekly rollups, Tier-3 concepts, and the wiki inbox into typed, cross-linked wiki pages, and put the resulting index in front of the model at every session start.

**Architecture:** The judgment (what deserves a page, what it says) is the model's, done in-session by an `ingest` skill. Everything else is deterministic and lives in `bin/`: a work-order script decides what is un-ingested, a Python index generator rewrites the two managed regions, a log script appends the ledger entry the work order reads back, and two SessionStart hooks inject the index and nudge when rollups pile up. The model never hand-writes the index and never hand-writes the log, so the two artifacts the whole loop depends on cannot drift with prompt quality.

**Tech Stack:** Bash (POSIX-leaning, no bash-4 associative arrays), PowerShell 7 (linter twin only), Python 3 (index generator — a runtime dependency, new in this phase), plain-text golden-file tests. No build system, no test framework.

**Spec:** `docs/superpowers/specs/2026-08-21-memory-wiki-design.md` (Phase 2 is §11's second bullet: `ingest` + the `MEMORY.md` region + `wiki-inject`)

**Predecessor plan:** `docs/superpowers/plans/2026-08-21-memory-wiki-phase1.md` (shipped as `memory-wiki` 0.3.1)

---

## Global Constraints

Every task's requirements implicitly include this section.

- **Plugin version for this phase is `0.4.0`.** It must be identical in **both** `plugins/memory-wiki/.claude-plugin/plugin.json` **and** the root `.claude-plugin/marketplace.json`. Task 9 additionally bumps `claude-memory` to `0.3.5` in both of its catalogs. These are independent catalogs and nothing but `test/run-tests.sh` validates them.
- **Shell scripts live in `bin/`, never inline in a SKILL.md.** Slash commands may contain only an invocation of a bundled script.
- **Slash-command substitutions must use the literal `${CLAUDE_PLUGIN_ROOT}`.** Claude Code expands exactly that string textually before any shell runs. `${CLAUDE_PLUGIN_ROOT:-}`, unbraced `$CLAUDE_PLUGIN_ROOT`, `CLAUDE_SKILL_DIR`, and any `find`-over-`plugins/cache` resolver are **not** expanded and die at load time with `Shell substitution failed ... (detail withheld)`. Never use `exit` or `exec` inside a command substitution block. `test/run-tests.sh` pins this.
- **`memory-wiki` writes only `<memdir>/wiki/**` and its own delimited region in `MEMORY.md`.** It never writes `episodic/**`, never writes root `concept_*.md` / `project_*.md` / `feedback_*.md`, never writes `.memory-state.json`.
- **`memory-wiki` never deletes.** Consumed inbox captures move to `wiki/inbox/consumed/`; they are never removed. Sources are immutable. `wiki/log.md` is append-only.
- **`lint` reports; it never fixes.** No task may add auto-remediation.
- **Script output must be deterministic** — sorted with `LC_ALL=C` byte ordering (bash), `[StringComparer]::Ordinal` (PowerShell), or Python's default code-point sort; no timestamps, no absolute paths in any golden-tested body.
- **Every hook script exits 0 unconditionally** and is silent when it has nothing to say. A hook that errors visibly at session start is worse than one that no-ops.
- **Every hook script honours `CLAUDE_MEMORY_CONSOLIDATING=1`** by exiting immediately, matching `claude-memory`'s existing recursion guard.
- **Author** in every manifest: `{ "name": "Eduardo Souza" }`. **License:** MIT.
- **Commit messages** use conventional-commit prefixes (`feat(memory-wiki):`, `test(memory-wiki):`, `fix(claude-memory):`, `docs:`) and end with:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01T2AWToFDaVbLYxzYhkDwpF
  ```

---

## Decisions this plan settles

The spec leaves four things underdetermined. Implementers must not re-litigate these; the reasoning is recorded here so a reviewer can check the plan against the spec without concluding it drifted.

### D-a: The index lives in `wiki/index.md`. `MEMORY.md` gets a pointer stub.

Spec §4.1 says memory-wiki writes "one new delimited region in `MEMORY.md`". Spec §6.1 says `wiki-inject.sh` injects the "project index region" at SessionStart. Doing both puts the same ~1.7 KB into the context twice on any machine where the harness auto-loads `MEMORY.md` — and the hook cannot detect whether auto-load happened.

So: **`wiki/index.md` holds the full managed region and `wiki-inject.sh` is its only injector.** The `memory-wiki` region in `MEMORY.md` holds a two-line stub saying the wiki exists, how many pages it has, and where the full index is. The §6.6 budget is unchanged (the region is emitted once either way); only the delivery vehicle differs. The stub still earns its place: it is how a human, Obsidian, or a grep finds the wiki from the index every other reader already uses, and it is the documented handshake between the two writers (§4.1).

Phase 1's `wiki-lint` already measures the injection budget from `<WIKI>/index.md` between the `memory-wiki` markers, so this is also the reading Phase 1 shipped.

### D-b: `ingest` is a skill driving deterministic scripts, not a headless `claude -p` pass.

Spec §7 lists `ingest` as a skill; §9 speaks of "**any** headless `claude -p` used by `ingest`" conditionally. `llm-wiki`'s `ingest` — the pattern §2 maps this onto — is a skill.

Phase 2 ships **no headless call.** The in-session model writes pages; `bin/` scripts do the work order, the index, and the log. This directly de-risks §10's headline risk ("ingest prompt quality is the real unknown"): the index and the ledger are no longer prompt-dependent, so the only thing quality can affect is page prose, which a human can judge. `skills/ingest/references/page-authoring.md` must be written as a self-contained instruction block with no reference to "the skill" or "this session", so a later phase can feed it to `claude -p` verbatim, at which point §9's `CLAUDE_MEMORY_CONSOLIDATING=1` plus clean-temp-cwd requirement applies. Until then it is satisfied vacuously.

### D-c: The index generator is Python, with no PowerShell twin.

Spec §8 says scripts ship as `.sh` / `.ps1` pairs because bash is unreliable for filesystem work on this machine (`concept_windows_filesystem_tooling`). But `wiki-index` is the one script that **writes to a file another plugin also writes** (`MEMORY.md`), and two independent implementations of a marker-delimited rewrite are two chances to corrupt it.

Python resolves both concerns at once: one implementation, invoked identically from bash and from PowerShell, with no bash filesystem semantics involved. `bin/wiki-index.sh` is a short wrapper so the invocation shape matches its siblings. **This makes Python a runtime dependency of `memory-wiki` for the first time** (`claude-memory`'s hooks already require it), and Task 10 updates the README accordingly. The linter keeps its `.ps1` twin — it is the script an agent invokes ad hoc, and it only reads.

### D-d: D5 (trim the rollup dump) is implemented in `claude-memory`, keyed on the wiki's existence.

Spec D5 wants the full weekly-rollup dump at session start replaced by its `## Open threads` section — that is the larger half of the 2,854 bytes §6.6 claims to save. The dump belongs to `claude-memory`'s `memory-inject.sh`, and D2 says memory-wiki does not modify claude-memory.

D2 protects claude-memory's **capture machinery and independence**, not its source file from ever changing. The change made in Task 9 keeps both properties: `memory-inject.sh` trims *only* when `<memdir>/wiki/index.md` already carries a populated `## Symptoms` or `## Map` heading — that is, only when something else is demonstrably providing a topical index. With no wiki, byte-for-byte nothing changes, and `claude-memory` still installs and runs entirely alone. `CLAUDE_MEMORY_ROLLUP_FULL=1` forces the old behaviour back. This is detection by artifact, not by env var or by plugin dependency, so there is no user setup step and no install-order coupling.

---

## File Structure

```
.claude-plugin/marketplace.json                MODIFY  memory-wiki 0.3.1 -> 0.4.0, claude-memory 0.3.4 -> 0.3.5
README.md                                      MODIFY  refresh the memory-wiki row

plugins/claude-memory/
├─ .claude-plugin/plugin.json                  MODIFY  0.3.4 -> 0.3.5
├─ README.md                                   MODIFY  document CLAUDE_MEMORY_ROLLUP_FULL
└─ bin/memory-inject.sh                        MODIFY  trim the rollup dump when a wiki index exists (D-d)

plugins/memory-wiki/
├─ .claude-plugin/plugin.json                  MODIFY  0.3.1 -> 0.4.0
├─ README.md                                   MODIFY  Phase 2 surface, python runtime dep, env vars
├─ assets/wiki-README.md                       MODIFY  schema now includes symptom / sources / part_of
├─ bin/
│  ├─ wiki-lint.sh                             MODIFY  type-value checks, type-specific fields, --concepts
│  ├─ wiki-lint.ps1                            MODIFY  the same, byte-identically
│  ├─ wiki-lint-project.sh                     MODIFY  pass --concepts <memdir>
│  ├─ wiki-init.sh                             MODIFY  seed wiki/index.md with an empty managed region
│  ├─ wiki-index.py                            NEW     render + write both managed regions (the only writer)
│  ├─ wiki-index.sh                            NEW     wrapper around wiki-index.py
│  ├─ wiki-log.sh                              NEW     append one well-formed ledger entry
│  ├─ wiki-ingest-plan.sh                      NEW     the deterministic work order (also --pending-only)
│  ├─ wiki-inject.sh                           NEW     SessionStart: emit project + atlas index regions
│  └─ wiki-nudge.sh                            NEW     SessionStart: one line when rollups are un-ingested
├─ commands/ingest.md                          NEW     work order, then hand off to the skill
├─ hooks/hooks.json                            NEW     registers the two SessionStart hooks
├─ skills/ingest/
│  ├─ SKILL.md                                 NEW     driver: plan -> read -> write -> index -> log -> lint
│  └─ references/page-authoring.md             NEW     types, frontmatter, link rules, two worked exemplars
└─ test/
   ├─ run-tests.sh                             MODIFY  new fixtures, index/log/plan/hook checks, interop
   ├─ fixtures/schema/                         NEW     frontmatter violations, one per new check
   ├─ fixtures/typed/                          NEW     a well-formed typed wiki; the index-render input
   ├─ fixtures/ingest-plan/                    NEW     a memdir with a partially-ingested log
   ├─ expected/schema.txt                      NEW
   ├─ expected/typed.txt                       NEW
   ├─ expected/typed-index.txt                 NEW
   ├─ expected/ingest-plan.txt                 NEW
   └─ expected/{clean,broken,orphans,no-frontmatter,atlas}.txt   MODIFY  one new counter line each
```

**Responsibility boundaries.** `wiki-lint.sh` stays a pure function of a directory. `wiki-index.py` is the **only** thing that writes `index.md` or touches `MEMORY.md` — the model must never hand-write either. `wiki-log.sh` is the only thing that writes `wiki/log.md`, because `wiki-ingest-plan.sh` parses those exact lines back to decide what is pending; the two are one contract, which is why they are one task. `wiki-inject.sh` and `wiki-nudge.sh` read and print, never write. The skill layer holds only the judgment none of these can express.

**Style reference.** Every new bash script follows the Phase 1 shape: `#!/usr/bin/env bash`, a header comment explaining *why* the script exists (not what each line does), `set -uo pipefail`, and the three-line `CLAUDE_PLUGIN_ROOT`-then-`BASH_SOURCE` resolver used by `wiki-init.sh` and `wiki-lint-project.sh` for locating `bin/` siblings.

---

## Task 1: Schema validation in the linter

The wiki schema is what makes recall work: `symptom:` is what §6.1's zero-tool-call matching keys on, and `sources:` is what makes every generated claim traceable. Nothing checks either today. This task also teaches the linter that root `concept_*.md` files are legitimate link targets — without that, every ingest-generated page that cites a concept would report as a broken link and the phase would sink on its first run.

**Files:**
- Modify: `plugins/memory-wiki/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (versions)
- Modify: `plugins/memory-wiki/bin/{wiki-lint.sh,wiki-lint.ps1,wiki-lint-project.sh}`
- Modify: `plugins/memory-wiki/assets/wiki-README.md`
- Modify: `plugins/memory-wiki/test/run-tests.sh`
- Modify: `plugins/memory-wiki/test/expected/{clean,broken,orphans,no-frontmatter,atlas}.txt`
- Create: `plugins/memory-wiki/test/fixtures/schema/` and `plugins/memory-wiki/test/fixtures/typed/`
- Create: `plugins/memory-wiki/test/expected/{schema,typed}.txt`

**Interfaces:**
- Consumes: Phase 1's `wiki-lint.sh <WIKI_DIR> [--sources DIR] [--atlas DIR]`.
- Produces:
  - `wiki-lint.sh <WIKI_DIR> [--sources DIR] [--atlas DIR] [--concepts DIR]`, and `wiki-lint.ps1` with `-Concepts`. `--concepts` adds every `*.md` basename in `DIR` to the resolvable-name set **without** adding them to the page set, so they never count as pages or orphans.
  - One new counter line, `schema errors`, printed after `missing frontmatter`; one new findings block, `SCHEMA:`, printed after `NO FRONTMATTER:`. Both use the existing `printf '  %-20s : %s\n'` / four-space-indent formatting.
  - Required fields by `type:` value — reported alphabetically on the existing `(missing: ...)` line:

    | `type:` | required fields |
    | --- | --- |
    | *(any)* | `description`, `last_accessed`, `name`, `status`, `type` |
    | `failure` | + `symptom`, `sources` |
    | `component` | + `part_of`, `sources` |
    | `project`, `tech` | + `sources` |
    | `concept` | nothing extra |

  - Value rules: `type` ∈ {`project`, `component`, `tech`, `failure`, `concept`}; `status` ∈ {`active`, `dormant`, `superseded`}. Violations render as `<page> (invalid: type=<v>)`, `(invalid: status=<v>)`, or `(invalid: type=<v>, status=<v>)`.
  - **A page with no parseable top-level `type:` triggers no type-specific and no value findings.** Files using the global auto-memory's nested `metadata:` block indent their keys, so the existing `^type:` match already misses them — that is the desired behaviour. The absent `type` is reported once as a missing field and must not cascade into three findings.
  - `test/fixtures/typed/` becomes the canonical well-formed wiki, reused by Tasks 2, 3, 7 and 9. **Nothing may add an `index.md` to it** — `expected/typed.txt` pins it at `index region : 0 B`.

- [ ] **Step 1: Write the failing fixtures and goldens**

Create `fixtures/schema/` — four pages, each isolating one new check, linked in a cycle so orphan and broken-link counts stay at zero and the golden shows only the schema findings. Add a `fixtures/schema/sources/2026-W35.md` so the one `sources:` citation resolves.

| page | `type:` | defect |
| --- | --- | --- |
| `failure_no-symptom` | `failure` | no `symptom:`, no `sources:` |
| `component_no-parent` | `component` | no `part_of:`, no `sources:` |
| `tech_bad-status` | `tech` | `status: stale`; has `sources: ["[[2026-W35]]"]` |
| `concept_bad-type` | `heuristic` | invalid type value; nothing else required of it |

`expected/schema.txt`:

```
## Structural
  pages                : 4
  wikilinks            : 5
  broken links         : 0
  orphans              : 0
  missing frontmatter  : 2
  schema errors        : 2

  NO FRONTMATTER:
    component_no-parent (missing: part_of, sources)
    failure_no-symptom (missing: sources, symptom)

  SCHEMA:
    concept_bad-type (invalid: type=heuristic)
    tech_bad-status (invalid: status=stale)

## Injection budget
  index region         : 0 B (~0 tokens)
```

Create `fixtures/typed/` — a well-formed wiki exercising every new rule *passing*, plus `fixtures/typed/sources/2026-W35.md` and `fixtures/typed/concepts/concept_root-heuristic.md`:

| page | `type:` | notes |
| --- | --- | --- |
| `project_demo` | `project` | links to the component, the tech page, and the dormant concept |
| `component_demo-plugin` | `component` | `part_of: "[[project_demo]]"`; links to the failure page |
| `tech_demo-cli` | `tech` | links to the component |
| `failure_demo-crash` | `failure` | `symptom: "demo: fatal: cannot open state file"`; links to the component and to `[[concept_root-heuristic]]` |
| `concept_demo-heuristic` | `concept` | `status: dormant` — proves the index excludes it while lint still counts it |

Every page except the dormant concept carries `sources: ["[[2026-W35]]"]`. Frontmatter wikilinks count toward the link total, so the counts are: 5 pages, 13 links, everything else zero. No `index.md`.

`expected/typed.txt`:

```
## Structural
  pages                : 5
  wikilinks            : 13
  broken links         : 0
  orphans              : 0
  missing frontmatter  : 0
  schema errors        : 0

## Injection budget
  index region         : 0 B (~0 tokens)
```

Insert `  schema errors        : 0` immediately after the `missing frontmatter` line in each of the five existing goldens. Nothing else in them changes.

Register both fixtures in `run-tests.sh` after `run_fixture no-frontmatter`: `schema` with `--sources`, `typed` with `--sources` and `--concepts`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: FAIL on all seven fixtures. The five existing ones fail on the absent `schema errors` line; `schema` and `typed` fail for that plus the unimplemented rules, and `typed` additionally reports two broken links because `--concepts` is swallowed as a positional and clobbers `$WIKI`.

- [ ] **Step 3: Implement in `wiki-lint.sh`**

Extend the argument parser with `--concepts`. In the frontmatter block, read `type:` and `status:` once via a small helper that strips the key, surrounding quotes and trailing whitespace; build the required-field list as base-plus-type-specific and iterate it **sorted** so the reported line stays alphabetical without a second sort. Emit value violations to a new temp file, counted and printed like `nofm`. Add the `--concepts` basenames to `$TMP/known` only — never to `$TMP/pages`.

Comment the two non-obvious decisions: why indented keys are skipped (the nested-`metadata:` schema, and the no-cascade rule), and why concepts go into `known` but not `pages`.

- [ ] **Step 4: Mirror in `wiki-lint.ps1`, byte-identically**

Add `[string]$Concepts`. Split the current `$required` constant into a base list plus `$validTypes` / `$validStatus`. Use a helper mirroring the bash one to read `type`/`status` from the frontmatter lines, build the per-type required list, sort it with the existing `Sort-Ordinal`, and collect value violations into a `$schema` array that is de-duplicated and ordinally sorted like `$nofm`. Add `$Concepts` basenames to `$known`. Emit the counter and the block in the same positions.

- [ ] **Step 5: Pass `--concepts` from the project entry point**

`wiki-lint-project.sh` passes `--concepts "$MEM"` alongside its existing `--sources` and `--atlas`, with a comment noting these are claude-memory's files and are link targets, not pages.

- [ ] **Step 6: Bump the version in both catalogs**

`plugins/memory-wiki/.claude-plugin/plugin.json` and the `memory-wiki` entry in `.claude-plugin/marketplace.json` both go to `0.4.0`.

- [ ] **Step 7: Update the schema asset**

Rewrite the `## Required frontmatter` section of `assets/wiki-README.md` to carry the base template plus the per-type table above, with one clause each on *why* `symptom` and `sources` are required, and a closing note that `lint` reports an out-of-range `type:`/`status:` separately from an absent one.

- [ ] **Step 8: Run the tests to verify they pass**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: PASS for all seven fixtures and version parity at `0.4.0`.

Then add `parity schema` and `parity typed` to the PowerShell parity block. Note that the `parity` helper takes `(name, sources, atlas)` positionally and has no `--concepts` slot, so the `typed` parity run reports two broken links on *both* sides — still a valid parity assertion. **Do not widen `parity` for this**; the contract under test is that the two scripts agree, not that they agree on the fully-argumented invocation.

- [ ] **Step 9: Commit**

`feat(memory-wiki): validate the page schema and resolve root concepts`

---

## Task 2: `wiki-index.py` — render the index region

Half of the generator: turn a directory of typed pages into the region body. Pure function, no writes, golden-tested. The write half is Task 3, and splitting them lets a reviewer reject the *shape* of the index without also reasoning about a marker-delimited rewrite of a shared file.

**Files:**
- Create: `plugins/memory-wiki/bin/wiki-index.py`
- Create: `plugins/memory-wiki/test/expected/typed-index.txt`
- Modify: `plugins/memory-wiki/test/run-tests.sh`

**Interfaces:**
- Consumes: `test/fixtures/typed/wiki/` from Task 1.
- Produces: `python bin/wiki-index.py --wiki <WIKI_DIR> --render-only` prints the region body to stdout and writes nothing. Exit 0; exit 1 with a message on stderr when `--wiki` is not a directory.
- Produces, for Task 3: module-level `BEGIN` / `END` marker constants, `parse_frontmatter(text) -> dict`, `parse_list(value) -> list[str]`, `read_pages(wiki_dir) -> list[dict]` (flat frontmatter plus a `_base` key holding the filename without `.md`), `active(pages) -> list[dict]`, and `render(pages, link) -> str` where `link` maps a base name to its link form.

**Behaviour:**
- Markers are exactly `<!-- BEGIN memory-wiki (managed; do not edit by hand) -->` and `<!-- END memory-wiki -->` — the pair Phase 1's linter already measures between.
- `index`, `log` and `README` are machinery, not pages, and are skipped.
- Frontmatter parsing is flat `key: value` fenced by `---` on line 1, surrounding quotes stripped. **Indented keys are skipped**, so the global auto-memory's nested `metadata:` block never contributes a `type:`.
- `parse_list` accepts a YAML flow list, a bare `[[name]]`, or a bare scalar, and returns plain names with wikilink brackets stripped.
- A page with no `status:` is treated as `active`, matching how lint reads it. Dormant and superseded pages are excluded from every section.
- Three sections, each omitted entirely when empty:
  - **Symptoms** — one line per active page carrying `symptom:`, sorted by symptom text then filename, rendered as `` - `<symptom>` → <link> ``.
  - **Map** — one line per active page whose `type:` is `project`, `component` or `tech`, in filename order, rendered as `- <link> — <description>`. `failure` is deliberately absent: failure pages are reached by symptom, and listing them twice doubles the region for no extra coverage.
  - **Sources ingested** — the sorted union of every active page's `sources:`, comma-joined on one line.
- When all three are empty the body is the single line `(no pages yet — run /memory-wiki:ingest)`. This exact string is reused by Task 3's `wiki-init.sh` seed and Task 7's suppression check.
- The body always ends with exactly one trailing newline.
- Directory listing and every sort use Python's default code-point ordering, which matches the bash side's `LC_ALL=C`.
- **Write bytes to stdout, not `print()`.** The region contains `→` and `—`, and a Windows console's default cp1252 encoding raises on both.

- [ ] **Step 1: Write the failing test**

Create `expected/typed-index.txt` — the render of `fixtures/typed/wiki/`:

```
## Symptoms — match the literal text, then read the page
- `demo: fatal: cannot open state file` → [[failure_demo-crash]]

## Map
- [[component_demo-plugin]] — the plugin that does the demo thing
- [[project_demo]] — the demo repo, its conventions and standing threads
- [[tech_demo-cli]] — how the demo CLI actually behaves

## Sources ingested
[[2026-W35]]
```

(Descriptions must match whatever Task 1's fixture frontmatter actually says.)

In `run-tests.sh`, resolve a `PYBIN` (`python` then `python3`) once and **fail loudly if absent** — python is a runtime dependency as of 0.4.0, not an optional test aid. Add an `index: render` check diffing `--render-only` output against the golden, with CR stripped from both sides.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: `FAIL: index: render` — python reports the file does not exist.

- [ ] **Step 3: Write the renderer**

Implement the module docstring (state D-c's reasoning in it — future readers will ask why this one script has no twin), the constants, the four helpers, `render`, and a `main()` that handles `--render-only` and exits 1 with `ERROR: writing is not implemented yet` otherwise.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: `PASS: index: render`, every Task 1 check still passing.

- [ ] **Step 5: Commit**

`feat(memory-wiki): render the index region from the pages on disk`

---

## Task 3: `wiki-index.py` — write both managed regions

The other half: put the rendered region into `wiki/index.md` and a pointer stub into `MEMORY.md` without disturbing a byte outside the markers. `MEMORY.md` is shared with `claude-memory` and with the user's own entries, so this is the one place in the plugin where a bug destroys someone else's data.

**Files:**
- Modify: `plugins/memory-wiki/bin/wiki-index.py`
- Create: `plugins/memory-wiki/bin/wiki-index.sh`
- Modify: `plugins/memory-wiki/bin/wiki-init.sh`
- Modify: `plugins/memory-wiki/test/run-tests.sh`

**Interfaces:**
- Consumes: `render`, `read_pages`, `active`, `BEGIN`, `END` from Task 2.
- Produces:
  - `python bin/wiki-index.py --wiki <WIKI_DIR> [--memory-md <PATH>]` — rewrites the managed region in `<WIKI_DIR>/index.md`, and in `<PATH>` when given. Creates either file if absent. Prints one status line per file written. Exit 0.
  - `bash bin/wiki-index.sh --wiki <WIKI_DIR> [--memory-md <PATH>] [--render-only]` — same arguments, locating the generator via `CLAUDE_PLUGIN_ROOT` when set and falling back to its own directory. Exits 1 with a clear message when python is missing.
  - `write_region(path, body) -> str`.
  - `render_stub(pages) -> str` — a two-line pointer giving the active page count and directing the reader to `wiki/index.md`, **never a copy of the index**. Its docstring should record why (D-a).
  - `wiki-init.sh` additionally creates `<memdir>/wiki/index.md` containing an `# Wiki index` heading and a managed region whose body is exactly the empty-wiki placeholder string from Task 2.

**`write_region` contract:**
- Replaces the text between the markers when both are present, in order; appends the whole block otherwise, separated from existing content by one blank line.
- Preserves everything outside the markers byte for byte, including `claude-memory`'s region and the user's own lines.
- Preserves the file's existing line-ending convention. Silently rewriting a shared file's CRLF to LF is a whole-file diff belonging to nobody.
- Atomic: temp file in the same directory, then `os.replace`. Creates the parent directory when absent.
- **Idempotent.** Running it twice with the same body must leave the file byte-identical — no second block, no drifting blank line. The append path's separator logic is where this is easy to get wrong; test the empty-file, ends-with-`\n`, ends-with-`\n\n` and no-trailing-newline cases by reasoning before you run.

- [ ] **Step 1: Write the failing tests**

Add four checks to `run-tests.sh`, placed after the existing `. "$PLUGIN/bin/_wiki-paths.sh"` line (they need `wiki_project_dir`) and before the PowerShell parity section. **Every write test operates on a `cp -r` copy of `fixtures/typed`** — the write path creates `index.md`, and `expected/typed.txt` pins the fixture at `0 B`.

Seed a realistic `MEMORY.md` in the temp dir: a user-written line, then a `claude-memory` region, **written with CRLF** because the real file is CRLF on Windows and must stay that way.

| check | asserts |
| --- | --- |
| `index: writes the region into index.md` | the region extracted from the written `index.md` equals `expected/typed-index.txt` |
| `index: MEMORY.md keeps every foreign line and gains our stub` | the user line, the `claude-memory` BEGIN marker and its body all survive, and a `memory-wiki` BEGIN marker now exists |
| `index: MEMORY.md keeps its CRLF line endings` | the file still contains CR |
| `index: re-running is byte-identical` | checksums of both files are unchanged after a second run |

Add a fifth check, `init: seeded index.md is what the generator would write`: scaffold a throwaway project with `wiki-init.sh`, checksum `wiki/index.md`, run the generator against the empty wiki, and assert the checksum is unchanged. This is what pins the seed string and `EMPTY` together — if they diverge, every new wiki shows a phantom diff on its first ingest.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: four new FAILs — the first because `main()` still refuses to write, the rest on files that were never created.

- [ ] **Step 3: Implement `write_region`, `render_stub`, and the rest of `main`**

`main` renders the body, writes `index.md`, and writes the stub to `--memory-md` when given, then prints a status line per file. Status lines carry absolute paths and are therefore never golden-tested — the write path is asserted by file content.

- [ ] **Step 4: Write the wrapper**

`bin/wiki-index.sh`, per the interface above. `exec` is fine here — the ban on `exec` applies only inside slash-command substitutions.

- [ ] **Step 5: Seed `index.md` in `wiki-init.sh`**

Add the `index.md` heredoc after the existing `log.md` one, with a comment stating that the seeded body must stay identical to the generator's empty-wiki render and why.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: PASS on all five new checks.

Then extend the existing `init: scaffolds and is idempotent` assertion to require `wiki/index.md`, and add `bin/wiki-index.py` and `bin/wiki-index.sh` to the `surface:` file list. Run again — all PASS.

- [ ] **Step 7: Commit**

`feat(memory-wiki): write the index region and the MEMORY.md pointer stub`

---

## Task 4: The ingest ledger — `wiki-log.sh` and `wiki-ingest-plan.sh`

One task because they are one contract: `wiki-log.sh` writes the `- Sources:` lines and `wiki-ingest-plan.sh` greps them back to decide what is still pending. Split across two tasks, a reviewer could approve a writer whose format the reader cannot parse. The round-trip is the test.

**Files:**
- Create: `plugins/memory-wiki/bin/{wiki-log.sh,wiki-ingest-plan.sh}`
- Create: `plugins/memory-wiki/test/fixtures/ingest-plan/`
- Create: `plugins/memory-wiki/test/expected/ingest-plan.txt`
- Modify: `plugins/memory-wiki/test/run-tests.sh`

**Interfaces:**
- Consumes: `_wiki-paths.sh`'s `wiki_project_dir`.
- Produces: `bash bin/wiki-log.sh --wiki <WIKI_DIR> --op <OP> --title <TITLE> [--date YYYY-MM-DD] [--sources a,b] [--created a,b] [--updated a,b] [--inbox a,b]` — appends one entry. Exit 1 on a missing or non-directory `--wiki`, or a missing `--op` / `--title`. Creates `log.md` with the Phase 1 header if absent.
- Produces: `bash bin/wiki-ingest-plan.sh [MEMORY_DIR] [--pending-only]` — with no argument, resolves the current project's memory dir worktree-aware. **Exit 0 always**, including when there is no wiki.

**The ledger entry format — a contract, not a preference:**

```
## [YYYY-MM-DD] <op> | <title>

- Sources: [[a]], [[b]]
- Pages created: [[c]]
- Pages updated: [[d]]
- Inbox consumed: e.md
```

The `- Sources:` line is always present, even when empty. The `- Inbox consumed:` line is omitted when there is nothing to report. Comma-separated arguments are split, trimmed and wrapped in `[[ ]]`; split by reading lines rather than by unquoted word-splitting, or a name containing `*` or `?` will glob-expand.

`--date` exists only so tests are deterministic; day to day it is never passed.

**Pending detection:** a rollup `<name>.md` in `episodic/weekly/` counts as ingested exactly when `wiki/log.md` has a line starting `- Sources:` containing `[[<name>]]`. `wiki-log.sh` is the only writer of those lines, so the two cannot drift.

**Work-order output** — three sections, each with a parenthesised count and `(none)` when empty:

```
## Pending sources (2)
2026-W35
2026-W36

## Existing pages (2)
component_demo-plugin | component | the plugin that does the demo thing
failure_demo-crash | failure | the demo binary exits 1 with no output at all

## Inbox (1)
2026-09-02-note.md
```

Page rows are `name | type | description` with no column padding — padding to the longest name would make the golden brittle to unrelated fixture edits. `index`, `log` and `README` are excluded. Everything is explicitly sorted, with `LC_ALL=C` exported.

**Two failure modes that matter:**
- No wiki: print `ERROR: no wiki for: <memdir>` plus a pointer to `/memory-wiki:init`, and **exit 0** — a project that never scaffolded one is an expected answer, not a script failure.
- `--pending-only` prints one bare name per line and **nothing at all** when there are none. `wiki-nudge.sh` counts those lines, and `printf '%s\n'` with no arguments still emits one newline, which would read as a pending rollup named `""`. Guard it.

- [ ] **Step 1: Write the failing test**

Create `fixtures/ingest-plan/memory/` containing: three weekly rollups (`2026-W34`, `2026-W35`, `2026-W36`); a `wiki/log.md` whose one entry cites `[[2026-W34]]` in the format above; two well-formed wiki pages (`component_demo-plugin`, `failure_demo-crash`, both sourced from W34); and one `wiki/inbox/2026-09-02-note.md`. Write `expected/ingest-plan.txt` to match the shape above.

Add four checks to `run-tests.sh`, before the PowerShell parity section:

| check | asserts |
| --- | --- |
| `plan: work order` | full output matches the golden |
| `plan: logging a source clears it from pending` | on a temp copy, logging W35+W36 leaves `--pending-only` empty |
| `log: appends the ledger format, preserving earlier entries` | the new entry's `##` header, `- Sources:` and `- Inbox consumed:` lines are exact, **and the pre-existing W34 entry is still there** |
| `plan: missing wiki reports, exits 0, and stays silent under --pending-only` | all three at once |

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: four new FAILs — neither script exists.

- [ ] **Step 3: Write `wiki-log.sh`**

Header comment should say *why* nothing hand-writes this file: it is the ingest ledger, and the pending calculation greps exactly these lines.

- [ ] **Step 4: Write `wiki-ingest-plan.sh`**

Header comment should say *why* it exists: so the ingest skill spends its judgment on page content and none on globbing or bookkeeping, and so the skill and the session-start nudge cannot disagree about what "pending" means, because there is one implementation of it.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: PASS on all four. Then add both scripts to the `surface:` file list and run again — all PASS.

- [ ] **Step 6: Commit**

`feat(memory-wiki): the ingest ledger — wiki-log.sh and wiki-ingest-plan.sh`

---

## Task 5: The page-authoring reference

Spec §10 names ingest prose as the phase's highest risk and says the PoC "ships in the repo as the target". The PoC was built in a session scratchpad and is gone. This task rebuilds the target from material still on disk: this repo's real `2026-W31` rollup and its real Tier-3 concepts. Two full worked exemplars are worth more than any amount of instruction about tone.

**Files:**
- Create: `plugins/memory-wiki/skills/ingest/references/page-authoring.md`
- Modify: `plugins/memory-wiki/test/run-tests.sh`

**Interfaces:**
- Consumes: the schema rules from Task 1 and the link rules in `assets/wiki-README.md`.
- Produces: the reference Task 6's SKILL.md reads. Written with no reference to "the skill" or "this session", so a later phase can hand it to `claude -p` verbatim (D-b).

**Required content:**

1. **What earns a page** — three tests, all of which must pass: it recurs; it has a name a future session would search for; it is not already covered. State plainly that **preferring an update over a new page** is the single most commonly skipped rule, and that a corpus of near-duplicates is worse than one of stale pages. Cap: **8 new pages per run** (§10's "ingest caps pages created per run"). Zero new pages in a quiet week is a correct outcome.
2. **The five types** — a table with, for each, when to reach for it. Two rules stated explicitly: **never create a `concept_*` page here** (they belong to `claude-memory`; link them), and if material has both a *what you saw* and a *what to do* half, write the `failure_` page and link the concept. Note the rejected types: a decision goes in a `## Decisions` section on the relevant `component_` page; open threads are transient and `lint` reports them.
3. **Frontmatter** — the flat template with the type-specific fields. `symptom:` gets its own paragraph: it goes into the session-start index verbatim, so write what you would actually *see*, quoted from the source. `"Hook cancelled"` is right; `"the hook was cancelled"` is useless.
4. **Links** — one convention, `[[exact-filename-without-extension]]`, with the 39%-broken statistic as the reason. Rollup citations by filename. Root `concept_*.md` links resolve via `lint --concepts`. `[[atlas/<page>]]` exists but there is no atlas until Phase 4 — do not invent one. **Before finishing a page, add the link *to* it** from its `project_` or `component_`, or it is an orphan.
5. **Body shape** — 2–3 KB, because a page is re-read whole every time it matches. `failure_` takes four sections in order: Symptom (the literal output, fenced), Cause (mechanism, one paragraph), Fix (concrete), Generalisation (one transferable sentence, linking the concept if one exists). `component_`: what it is, then dated `## Decisions` each citing its source, then `## Failure modes` linking its `failure_` pages. `tech_`: what the tool actually does as distinct from what its docs say. `project_`: conventions, environment, and `## Standing threads`.
6. **Redaction** — inherited unchanged from `claude-memory`. Pages are re-read and re-sent every session, so they are held to the same bar as Tier 3. Refer to people by role.
7. **Exemplar: a `failure_` page** — reconstruct the `Shell substitution failed for pattern` defect from `2026-W31` and `concept_slash_command_bash_needs_allowed_tools`. It must carry `symptom: "Shell substitution failed for pattern"`, quote the error verbatim under `## Symptom`, explain under `## Cause` that only the literal `${CLAUDE_PLUGIN_ROOT}` is expanded textually before any shell runs (and that this is *not* the permissions error, which has its own wording), and generalise under `## Generalisation` to "expect this defect to be copied forward when a plugin is scaffolded from a sibling — grep every `plugins/*/commands/*.md`".
8. **Exemplar: a `component_` page** — for the `claude-memory` plugin, with `part_of: "[[project_claude-plugins]]"`, sources citing W27 and W31, a dated `## Decisions` section (rollup-validated-before-archiving; raw transcripts budgeted rather than dumped; `MEMORY.md` regions delimited per writer), and a `## Failure modes` section linking failure pages.
9. **Anti-example** — a page with four named defects: no `part_of`, no `sources`, a description matching no search anyone would run, and a body whose only content points at a commit git already holds. Close with: if the page adds nothing to `git log`, do not write it.

- [ ] **Step 1: Write the failing test**

Add `skills/ingest/references/page-authoring.md` to the `surface:` file list, and add a shallow content check asserting the file contains `^type: failure$`, `^symptom:`, `^type: component$` and `^part_of:` — pinning that a worked example of each specially-treated type is still present, without pinning its wording.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: `FAIL: surface: all declared files present` and `FAIL: authoring: reference carries a worked failure_ and component_ exemplar`.

- [ ] **Step 3: Write the reference**

Cover items 1–9 above. Nested fenced blocks need increasing backtick counts — the `failure_` exemplar contains a fenced error block inside it.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: both checks PASS.

- [ ] **Step 5: Commit**

`docs(memory-wiki): the page-authoring reference and its two exemplars`

---

## Task 6: The `ingest` skill and the `/memory-wiki:ingest` command

The driver. Everything it needs is now deterministic except the prose, so the skill body is short by design.

**Files:**
- Create: `plugins/memory-wiki/skills/ingest/SKILL.md`
- Create: `plugins/memory-wiki/commands/ingest.md`
- Modify: `plugins/memory-wiki/test/run-tests.sh`

**Interfaces:**
- Consumes: `wiki-ingest-plan.sh`, `wiki-index.sh` / `wiki-index.py`, `wiki-log.sh`, `wiki-lint.sh`, and `references/page-authoring.md`.
- Produces: a model-invocable `ingest` skill, and `/memory-wiki:ingest [memory-dir]`. The command carries `disable-model-invocation: true` matching its Phase 1 siblings — the *skill* is the model-invocable surface, the command is the human one.

**SKILL.md frontmatter:** `name: ingest`, and a description whose triggers include "ingest", "update the memory wiki", "run memory-wiki ingest", "add last week to the wiki", and the session-start nudge reporting un-ingested rollups.

**The eight steps the body must specify:**

1. **Get the work order** — run `wiki-ingest-plan.sh`. Prefer the `## Memory - dir for this project` path injected at session start over deriving it from the cwd; inside a worktree the derivation resolves to the main repo. **If pending sources is `(none)` and the inbox is empty, stop** and say so — re-ingesting a logged week is how duplicate pages get made. On `ERROR: no wiki`, point at `/memory-wiki:init`.
2. **Read the rules** — `references/page-authoring.md`, not from memory of some other wiki.
3. **Read the sources** — only the *pending* rollups, plus any root `concept_*.md` they touch, plus every inbox file. `episodic/**` and root `concept_*.md` are immutable inputs.
4. **Write the pages** — restate the rules most often skipped: prefer updating over creating; 8 new pages max; every page carries `sources:`; every page is linked *from* somewhere; never create a `concept_*`. For the inbox, fold or promote each capture, then **move** it to `inbox/consumed/` — never delete.
5. **Regenerate the index** — via `wiki-index.sh`, with the direct `python wiki-index.py` invocation given as the Windows fallback. Never by hand.
6. **Append the ledger entry** — one `wiki-log.sh` call per run, with `--sources`, `--created`, `--updated`, `--inbox`. This is what clears those weeks from pending, so it is neither optional nor hand-written.
7. **Verify** — `wiki-lint.sh` with `--sources` and `--concepts`. Every page written this run must lint clean. Draw the line explicitly: **fix your own pages; report and leave alone anything pre-existing.** That is not a violation of "lint never fixes", which is about findings you did not create.
8. **Report** — ingested weeks, created and updated pages, inbox disposition, the lint counters verbatim, and a separate line naming pre-existing findings left alone.

**Rules block:** write only inside `<memdir>/wiki/` plus the `MEMORY.md` region, and that region only via the script; never modify `episodic/**` or root Tier-3 files; never delete; redaction inherited. On a contradiction with an existing page: write the new page, set the old one `status: superseded` with `superseded_by:`, and say so in the report — do not silently pick a winner.

**commands/ingest.md** runs the work order through a `${CLAUDE_PLUGIN_ROOT}` substitution passing `"$ARGUMENTS"`, then hands off to the skill with three instructions: use the work order rather than re-deriving it by globbing; on `ERROR: no wiki` point at `/memory-wiki:init` (and `/claude-memory:init` before it) without creating anything; stop when there is nothing pending. `allowed-tools` needs `Bash, Read, Write, Edit, Glob, Grep`.

- [ ] **Step 1: Write the failing test**

Add `skills/ingest/SKILL.md` and `commands/ingest.md` to the `surface:` list. The existing `commands: substitutions use ${CLAUDE_PLUGIN_ROOT}` check iterates `commands/*.md` and will start covering `ingest.md` automatically.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: `FAIL: surface: all declared files present`.

- [ ] **Step 3: Write the skill**
- [ ] **Step 4: Write the command**

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: all PASS, including the substitution check now covering `ingest.md`.

- [ ] **Step 6: Run a real ingest and record the after-baseline**

This is §10's quality benchmark made concrete, and the only step in this plan that exercises the prose path.

Reinstall the plugin so the cache is current (`stale-plugin-cache-reinstall`), then run `/memory-wiki:ingest` against this repo's own memory dir. Afterwards run `/memory-wiki:lint` and append the report to `test/expected/README.md` under a new `## Recorded after-baseline (not a test)` heading, beside the Phase 1 "Recorded baseline". Mark it explicitly as not asserted anywhere — these counts change every week — and add a short "Reading the after-baseline" section covering: how the page count moved from 18 flat concepts; that **any orphan above zero is an ingest that wrote a page and forgot to link it**, the exact defect the authoring reference calls out; and that the three nested-`metadata:` findings persist and should, being the global auto-memory's schema rather than this one's.

Judge the generated pages against the exemplars. If they are visibly worse — vague descriptions, symptoms paraphrased instead of quoted, pages that restate `git log` — that is a prompt defect, not an acceptable outcome: tighten `page-authoring.md` and re-run. This is the iteration §10 asks for.

- [ ] **Step 7: Commit**

`feat(memory-wiki): the ingest skill and /memory-wiki:ingest`

---

## Task 7: `wiki-inject.sh` and the hook registration

The read half of §6.1: the index in front of the model at every session start, with no decision required from anyone. This is the first hook `memory-wiki` has ever registered.

**Files:**
- Create: `plugins/memory-wiki/bin/wiki-inject.sh`
- Create: `plugins/memory-wiki/hooks/hooks.json`
- Modify: `plugins/memory-wiki/test/run-tests.sh`

**Interfaces:**
- Consumes: `_wiki-paths.sh`; the region `wiki-index.py` writes into `<memdir>/wiki/index.md`.
- Produces: a `SessionStart` hook that reads the hook payload JSON on stdin, takes `cwd`, resolves the memory dir worktree-aware, and prints the project index region followed by the atlas region from `$HOME/.claude/memory-wiki/index.md`.
- Produces: `hooks/hooks.json` with one `SessionStart` matcher, commands referenced as `${CLAUDE_PLUGIN_ROOT}/bin/...` with a `statusMessage`, mirroring `claude-memory/hooks/hooks.json`.

**Behaviour:**
- Region extraction uses the same marker-delimited `awk` Phase 1's linter uses to measure the budget, with CR stripped.
- Output is two optional sections. The project section carries a one-line header naming the wiki path (via `cygpath -m` where available) and telling the model to read a page **only when a line below matches** — the index line is the affordance (§6.2). The atlas section is emitted only when that region is non-empty, which it will not be until Phase 4.
- A wiki rendering only the empty-wiki placeholder is treated as empty and suppressed — it is not worth a section header.
- Silent, exit 0, on every one of: `CLAUDE_MEMORY_CONSOLIDATING` set, `MEMORY_WIKI_NO_INJECT` set, python missing, unparseable or empty `cwd`, no wiki, both regions empty.

- [ ] **Step 1: Write the failing test**

Scaffold a throwaway git project with its own memory dir and drive the hook the way Claude Code does — payload JSON on stdin, output on stdout. Place the block before the `--- smoke ---` section.

| check | asserts |
| --- | --- |
| `inject: silent and exits 0 with no wiki` | empty output, rc 0 |
| `inject: emits the project index region` | after `wiki-init.sh`, copying `fixtures/typed/wiki/*.md` in and running the generator: the section header, the symptom string and a page wikilink all appear |
| `inject: honours MEMORY_WIKI_NO_INJECT and CLAUDE_MEMORY_CONSOLIDATING` | both produce empty output |
| `inject: unparseable payload is a silent no-op` | `not json` on stdin gives empty output and rc 0 |
| `hooks: SessionStart declares wiki-inject with ${CLAUDE_PLUGIN_ROOT}` | parse `hooks.json` and assert the command list contains `/bin/wiki-inject.sh` and that **every** command starts with the literal `${CLAUDE_PLUGIN_ROOT}/` |

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: five new FAILs — neither file exists.

- [ ] **Step 3: Write the hook**

Header comment must record D-a: this is the only injector, and the `MEMORY.md` region holds a stub rather than a copy because a copy would spend the budget twice on a machine where the harness auto-loads it, and the hook cannot detect that it did.

- [ ] **Step 4: Write the hook manifest**
- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: PASS on all five. Then add `bin/wiki-inject.sh` and `hooks/hooks.json` to the `surface:` list and run again — all PASS.

- [ ] **Step 6: Commit**

`feat(memory-wiki): inject the wiki index at session start`

---

## Task 8: `wiki-nudge.sh` — the ingest-pending reminder

An ingest that nothing reminds you to run is an ingest that happens once. This mirrors `claude-memory`'s consolidation-overdue reminder exactly: no background process, no token spend, silent whenever there is nothing to do.

**Files:**
- Create: `plugins/memory-wiki/bin/wiki-nudge.sh`
- Modify: `plugins/memory-wiki/hooks/hooks.json`
- Modify: `plugins/memory-wiki/test/run-tests.sh`

**Interfaces:**
- Consumes: `wiki-ingest-plan.sh --pending-only` — the single implementation of "pending", so this can never disagree with the skill about what is left to do.
- Produces: a second `SessionStart` hook printing three lines — a `## Memory wiki - ingest pending` header, a count with the pending week names comma-joined, and `Run:  /memory-wiki:ingest` — when at least one rollup is un-ingested. Silent otherwise. Honours `MEMORY_WIKI_NO_NUDGE=1` and `CLAUDE_MEMORY_CONSOLIDATING`. Exits 0 always.

**Two hook entries rather than one script doing both jobs:** they have unrelated outputs and unrelated failure modes, and a bug in the pending calculation must not be able to suppress the index injection. `claude-memory` registers its two SessionStart hooks the same way.

- [ ] **Step 1: Write the failing test**

Reuse Task 7's scratch project, adding the block after the injection checks and before its cleanup.

| check | asserts |
| --- | --- |
| `nudge: silent when nothing is pending` | no rollups at all gives empty output, rc 0 — this is the steady state and must cost nothing |
| `nudge: names the pending rollups` | after adding two weekly rollups: the count, both week names, and the command all appear |
| `nudge: goes quiet once logged, and honours MEMORY_WIKI_NO_NUDGE` | after a `wiki-log.sh` call citing both, output is empty; and the kill switch also empties it |

Extend the `hooks:` assertion to require `/bin/wiki-nudge.sh` as well, and rename the check accordingly.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: three new FAILs plus the renamed hooks check failing.

- [ ] **Step 3: Write the nudge**
- [ ] **Step 4: Register the second hook**

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: PASS on all three plus the hooks check. Then add `bin/wiki-nudge.sh` to the `surface:` list and run again — all PASS.

- [ ] **Step 6: Commit**

`feat(memory-wiki): nudge at session start when rollups are un-ingested`

---

## Task 9: D5 — trim `claude-memory`'s rollup dump when a wiki index exists

The last piece of §6.6's budget. `memory-inject.sh` currently dumps 200 lines of last week's rollup at every session start; once the wiki covers that week topically, page by page, all of it is duplicated except `## Open threads`, which is transient continuity no durable page reproduces. See D-d for why this is a `claude-memory` change and why it does not couple the two plugins.

**Files:**
- Modify: `plugins/claude-memory/bin/memory-inject.sh`
- Modify: `plugins/claude-memory/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (versions)
- Modify: `plugins/claude-memory/README.md`
- Modify: `plugins/memory-wiki/test/run-tests.sh`

**Interfaces:**
- Consumes: the `## Symptoms` / `## Map` headings `wiki-index.py` writes into `<memdir>/wiki/index.md`.
- Produces: `memory-inject.sh` emits only the `## Open threads` section of the newest weekly rollup, capped at 60 lines, when **all** of: `CLAUDE_MEMORY_ROLLUP_FULL` is unset, `<memdir>/wiki/index.md` matches `^## (Symptoms|Map)`, and the rollup actually has an `## Open threads` heading. Otherwise the existing `head -200` dump, byte for byte. `claude-memory` version `0.3.5`.

**Why the guard keys on a populated heading, not on the wiki directory existing:** a user who runs `/memory-wiki:init` but never ingests would otherwise lose the rollup and gain nothing. Those two headings appear only when the renderer had real pages to work with.

Extraction runs from the `## Open threads` line to the next `## ` heading.

- [ ] **Step 1: Write the failing test**

Add an interop block before the `--- smoke ---` section — that is, after the SessionStart blocks from Tasks 7 and 8. Note in a comment why it lives in memory-wiki's harness: memory-wiki is the consumer that motivates the behaviour, and this repo has exactly one test harness.

Build a scratch project whose single weekly rollup contains a `BULK_BODY_MARKER` line in its body and a real `## Open threads` section, and drive `memory-inject.sh` with payload JSON on stdin.

| check | asserts |
| --- | --- |
| `interop: no wiki -> claude-memory dumps the full rollup, unchanged` | `BULK_BODY_MARKER` present |
| `interop: populated wiki -> only Open threads, and ROLLUP_FULL restores the dump` | after scaffolding and generating a populated index: marker absent, `## Open threads` and its content present; and with `CLAUDE_MEMORY_ROLLUP_FULL=1` the marker is back |
| `interop: an empty wiki does not trim the rollup` | a second project with `wiki-init.sh` run but no pages still shows the marker |
| `interop: claude-memory version parity` | `plugin.json` and `marketplace.json` agree, guarded like memory-wiki's own parity check |

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: the first interop check PASSes (current behaviour already dumps everything) and `interop: populated wiki -> only Open threads...` FAILs.

- [ ] **Step 3: Implement the trim**

Modify only the `## Memory - last week (Tier 2)` block in `memory-inject.sh`. The comment there must state: what triggers the trim, why `## Open threads` is the exception, why the guard keys on a populated heading rather than the directory, that with no wiki nothing changes, and the escape hatch.

- [ ] **Step 4: Bump `claude-memory` in both catalogs to `0.3.5`**

- [ ] **Step 5: Document the escape hatch**

Add `CLAUDE_MEMORY_ROLLUP_FULL=1` to `plugins/claude-memory/README.md`'s environment-variable section, creating the section if there is none. State the default behaviour and that with no wiki it changes nothing.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: all four interop checks PASS, every earlier check still passing.

- [ ] **Step 7: Commit**

`feat(claude-memory): inject only Open threads when a wiki index covers the week`

---

## Task 10: Documentation

The plugin's surface tripled and it gained a runtime dependency, two hooks, and three environment variables. None of that is discoverable from the code. The tests must already be green before this task starts.

**Files:**
- Modify: `plugins/memory-wiki/README.md`
- Modify: `README.md` (root, the memory-wiki row)

**Required content in the plugin README:**

- The skill/command table gains `/memory-wiki:ingest` and the `ingest` skill alongside the Phase 1 entries.
- A **How it runs** section: two hooks at session start (`wiki-inject` puts the symptom index and component map in front of the model so an error string matches with zero tool calls; `wiki-nudge` prints one line when rollups pile up, nothing otherwise); `/memory-wiki:ingest` weekly after consolidate, with the deterministic half scripted and the model only writing pages; `/memory-wiki:lint` monthly, reporting and never fixing.
- An **Environment variables** table: `MEMORY_WIKI_NO_INJECT`, `MEMORY_WIKI_NO_NUDGE`, `CLAUDE_MEMORY_CONSOLIDATING` (set by the other plugin; every hook here no-ops, which is the recursion guard), and `CLAUDE_MEMORY_ROLLUP_FULL` (belongs to `claude-memory`; restores the dump this plugin's index replaces).
- A **What it writes, and what it will not touch** section restating the boundary and the never-deletes rule, including that a bad ingest is corrected by re-running rather than recovered from a backup.
- **Dependencies:** python moves from test-only to **runtime**, called out as new in 0.4.0, with the note that `claude-memory`'s hooks already require it. Keep the `pwsh`-optional line but extend it to say the index generator has no twin on purpose (D-c).
- **Tests:** refresh the list to name the new coverage — index-render goldens, the ledger round-trip, hook checks driven with real payload JSON, the claude-memory interop check, version parity for both plugins.
- Keep the existing "byte counts are not platform artifacts" note verbatim.

The root README's `memory-wiki` row should mention `ingest`, session-start injection, and `lint`, replacing the Phase-1-only wording.

- [ ] **Step 1: Rewrite the plugin README**
- [ ] **Step 2: Refresh the root README row**

- [ ] **Step 3: Verify the whole suite one more time**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: every check PASS, `version parity (0.4.0)`, `interop: claude-memory version parity (0.3.5)`.

- [ ] **Step 4: Commit**

`docs: document memory-wiki's Phase 2 surface`

---

## Self-Review

**1. Spec coverage.**

| Spec | Where |
| --- | --- |
| §4.1 boundary — reads/writes/never-writes | Global Constraints; enforced by the `ingest` skill's Rules block |
| §4.1 `MEMORY.md` delimited region | Task 3 (`write_region`, `render_stub`); D-a explains the stub |
| §4.2 layout — `wiki/index.md`, `wiki/log.md`, `wiki/inbox/` | Task 3 (index seed), Task 4 (log), Task 6 (`inbox/consumed/`) |
| §4.3 data flow — rollups + concepts + inbox → pages + region + log | Tasks 4, 5, 6 |
| §5.1 five types, `failure_`/`concept_` split | Task 1 (validation), Task 5 (authoring rules) |
| §5.2 frontmatter incl. `symptom:`, `sources:`, `part_of:` | Task 1 |
| §5.3 one link convention; `atlas/` prefix; asymmetry | Task 1 (`--concepts`), Task 5; the `atlas/` prefix and asymmetry shipped in Phase 1 |
| §6.1 SessionStart injection; index shaped for triggering | Tasks 2, 7 |
| §6.1 `UserPromptSubmit` recall | **Phase 3.** Explicitly out of scope per §11 |
| §6.2 index line as the affordance | Task 7's injected header tells the model to read a page only on a match |
| §6.3 write-through: append live, inbox for uncertain | Task 6 (skill), Task 5 (reference) |
| §6.4 subagents get paths, never write | **Phase 3**, with the rest of the runtime read loop |
| §6.5 Stop nudge extension | **Deferred.** §6.5 asks to extend `claude-memory`'s existing Stop *reason text* to flush the inbox. Task 8 covers the SessionStart half of the reminder loop; the Stop half belongs with Phase 3's `wiki-recall`, where the per-turn hooks are tuned together. Flagged here rather than silently dropped. |
| §6.6 injection budget | Task 9 (D5, the rollup trim) + D-a (single injection); `wiki-lint` already reports the region size |
| §7 `ingest` rules — index first, never modify sources, `sources:` provenance, no-op on an already-ingested week | Tasks 4, 5, 6 |
| §7 `query`, `promote` | **Phases 3 and 4** |
| §8 `wiki-inject`, `wiki-nudge` | Tasks 7, 8 |
| §8 `.sh`/`.ps1` pairs | Honoured for the linter; D-c records why the index generator is Python instead |
| §9 never deletes; redaction inherited; headless guard | Global Constraints, Task 5, Task 6; D-b on the headless guard |
| §10 ingest prompt quality benchmark | Task 5 (exemplars) + Task 6 Step 6 (real run, recorded after-baseline, iterate if worse) |
| §10 cap pages created per run | Tasks 5 and 6: 8 per run |

Two spec items are deliberately unclaimed and named as such: §6.1's `UserPromptSubmit` recall and §6.4's subagent contract are Phase 3 by §11; §6.5's Stop-nudge extension is deferred to Phase 3 with the reasoning above.

**2. Placeholder scan.** No `TBD`, no "add error handling", no "similar to Task N". Behaviour is specified per task — inputs, outputs, exact report shapes, every failure path, and the assertions that must pass — with implementations left to the executor by request. The one intentionally unfilled artifact is the after-baseline report in Task 6 Step 6, which measures a real run and cannot be written before it; its surrounding headings and reading notes are specified in full and it is explicitly marked "not a test".

**3. Type consistency.** Checked across tasks:

- `wiki-lint` flags: `--sources`, `--atlas`, `--concepts` (Task 1) — matched by `wiki-lint.ps1`'s `-Sources` / `-Atlas` / `-Concepts`, by `wiki-lint-project.sh` (Task 1), and by the `ingest` skill's verify step (Task 6).
- `wiki-index.py` flags: `--wiki`, `--memory-md`, `--render-only` (Tasks 2, 3) — matched by `wiki-index.sh` (Task 3), the skill (Task 6), and every test invocation.
- `wiki-log.sh` flags: `--wiki`, `--op`, `--title`, `--date`, `--sources`, `--created`, `--updated`, `--inbox` (Task 4) — matched by the skill (Task 6) and Task 8's test.
- `wiki-ingest-plan.sh`: positional `MEMORY_DIR` plus `--pending-only` (Task 4) — matched by `commands/ingest.md` passing `"$ARGUMENTS"` (Task 6) and by `wiki-nudge.sh` (Task 8).
- Python names shared across Tasks 2 and 3: `BEGIN`, `END`, `parse_frontmatter`, `parse_list`, `read_pages`, `active`, `render`, `render_stub`, `write_region`.
- Region markers are the single pair `<!-- BEGIN memory-wiki (managed; do not edit by hand) -->` / `<!-- END memory-wiki -->` in `wiki-index.py` (Task 3), `wiki-init.sh`'s seed (Task 3), `wiki-inject.sh`'s extractor (Task 7), and Phase 1's `wiki-lint` budget measurement.
- The empty-index placeholder `(no pages yet — run /memory-wiki:ingest)` appears in `wiki-index.py`'s empty-render path (Task 2), `wiki-init.sh`'s seed (Task 3), and `wiki-inject.sh`'s suppression check (Task 7). Task 3's `init: seeded index.md is what the generator would write` check is what pins the first two together.
- The heading strings `## Symptoms` and `## Map` are produced by `render` (Task 2) and matched by `memory-inject.sh`'s trim guard (Task 9).
- `test/fixtures/typed/` is created once (Task 1) and reused by Tasks 2, 3, 7 and 9. Only Tasks 3, 7 and 9 write, and all three must copy it first — `expected/typed.txt` pins the fixture at `index region : 0 B`, which an in-place `index.md` would break.
