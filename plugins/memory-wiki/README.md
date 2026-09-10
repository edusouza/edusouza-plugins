# memory-wiki

Turns [`claude-memory`](../claude-memory)'s weekly rollups and flat Tier-3 concepts into a
cross-linked, searchable wiki. It reads what `claude-memory` writes and never modifies it — captures,
rollups and the root `concept_*.md` files stay exactly where they are.

The point is recall that costs no tool calls. At session start the wiki's **symptom index** and
**component map** are put straight in front of the model, so the error text in front of *you* matches
a page before anything goes looking for one. The model opens a page only when a line in that index
matches what it is doing; the line is the affordance.

| Skill / command | What it does | Trigger |
| --- | --- | --- |
| `/memory-wiki:init` | Scaffolds `wiki/`, `wiki/inbox/`, `wiki/log.md`, a seeded `wiki/index.md` and the page-schema `README.md` inside an existing memory dir. Idempotent. Refuses to create the memory dir itself — that is `claude-memory`'s. | You run it once per project, after `/claude-memory:init`. |
| `/memory-wiki:ingest` | Prints the work order — which weekly rollups no ledger entry cites yet, which pages already exist, what is waiting in the inbox — then hands it to the `ingest` skill. | You run it weekly, after `/claude-memory:consolidate`, or when session start reports rollups pending. |
| `ingest` skill | Distils the pending rollups and inbox captures into pages, regenerates the index, appends the ledger entry, and lints its own work. Everything mechanical is scripted; the only judgment left is which pages to write and what they say. | "ingest", "update the memory wiki", "add last week to the wiki" — or the session-start nudge. |
| `/memory-wiki:lint` | Structural audit: broken wikilinks, orphan pages, missing frontmatter, schema errors, injection budget. Reports; never fixes. | You run it monthly, or after anything hand-edits the wiki. |
| `lint` skill | The same audit, plus the judgment checks a script cannot make — contradictions between pages, claims a newer source superseded, entities that recur without a page of their own. | "lint the memory wiki", "audit my memory", "what's broken in my memory" |

The three slash commands are `disable-model-invocation: true`: they run when you type them, never on
the model's initiative. The two skills are the model-invocable half.

## How it runs

**Two hooks at session start** — two separate `SessionStart` commands in `hooks/hooks.json`, not one
script doing both jobs, so a bug in the pending calculation cannot suppress the index injection. Both
are silent and exit 0 on every path, including every failure.

- **`bin/wiki-inject.sh` — the read half.** Resolves this project's memory dir (worktree-aware: a
  linked worktree shares the main repo's memory) and prints the managed region of
  `<memdir>/wiki/index.md`, followed by the cross-project atlas region if one exists. That region is
  up to three sections: `## Symptoms` (one line per page carrying a `symptom:`, matched against the
  literal error text), `## Map` (the `project_`/`component_`/`tech_` pages with their one-line
  descriptions), and `## Sources ingested`. Nothing decides whether to do this — it happens at every
  session start, and a project with no wiki, an empty wiki, or an unparseable payload simply gets
  silence. This is the **only** injector of the index region.
- **`bin/wiki-nudge.sh` — the write half's alarm clock.** Three lines when weekly rollups are sitting
  un-ingested (a header, the count with the week names, and the one command that clears it) and
  nothing whatsoever otherwise, which is its state on almost every session start. The pending rule
  lives in one sourced function, `wiki_pending` in `bin/_wiki-pending.sh`, which both the nudge and
  the `ingest` skill's work order (`bin/wiki-ingest-plan.sh`) call, so the two cannot disagree. A
  rollup counts as ingested when `wiki/log.md` carries a `- Sources:` line naming it.

Both block every session start, so both are budgeted in processes. On this machine a process spawn
costs ~430 ms measured, and `test/run-tests.sh` pins the counts with a `PATH` shim that logs every
call. The two hooks share their payload and memory-dir resolution through `bin/_wiki-hook.sh`, so
they always agree on which project a session belongs to:

| Hook | Under Claude Code | Other hosts | Opted out |
| --- | --- | --- | --- |
| `wiki-inject.sh` | 1 process | 2 | 0 |
| `wiki-nudge.sh` | 1 process | 2 | 0 |

Claude Code exports `CLAUDE_PROJECT_DIR`, which is the fast path; without it each hook pays one more
process to parse the hook payload JSON with python. The opt-out guards run before either script does
any work, so an opted-out session start spawns nothing at all.

**`/memory-wiki:ingest` — weekly, after consolidation.** The deterministic half is scripted end to
end: `wiki-ingest-plan.sh` produces the work order, `wiki-index.sh` regenerates the index,
`wiki-log.sh` appends the one ledger entry, `wiki-lint.sh` verifies the result. The model only writes
pages. It caps itself at **8 new pages per run** (updates are uncapped) and prefers revising an
existing page over creating a near-duplicate beside it. Zero new pages is a correct outcome.

`wiki-index.sh` writes the managed region of `wiki/index.md`, and — when handed `--memory-md`, as
`ingest` always does — a **two-line pointer** into `MEMORY.md`: the count of active pages, and one
line saying the full index is in `wiki/index.md`. It is a pointer and never a copy of the index. The
harness auto-loads `MEMORY.md` while the session-start hook injects
the region, so rendering it into both places would spend the injection budget twice for one set of
facts. One renderer, one injector, one copy in context.

**`/memory-wiki:lint` — monthly.** It reports and never fixes; no part of this plugin has an
auto-remediation path. It works *before* `init` too: handed a memory dir with no `wiki/` subdirectory
it audits the memory dir itself, because a directory of flat `concept_*.md` files is a wiki with no
edges and auditing that is the point. Both the command and the skill pass `--concepts <memdir>`,
which is what makes links to the root `concept_*.md` files resolve without counting them as pages of
this wiki. Omit it and every ingest-generated page citing a concept reports as a broken link — which
is most of them. `README.md` inside a wiki is not part of the link graph at all: it is the page
schema `init` copies in, its `[[...]]` are illustrations that cannot resolve, and counting them would
make every freshly scaffolded wiki report broken links its owner cannot fix.

## What it writes, and what it will not touch

Writes, and only these:

- `<memdir>/wiki/**` — pages, `index.md`, the append-only `log.md`, and `inbox/`.
- The `memory-wiki`-delimited region of `<memdir>/MEMORY.md`, spliced between its own markers
  without disturbing a byte outside them — including the region `claude-memory` owns in the same
  file. Only `bin/wiki-index.py` ever writes it; the write is atomic (temp file + `os.replace`) and
  preserves the file's existing CRLF or LF convention.

Never touches: `<memdir>/episodic/**`, the root `concept_*.md` / `project_*.md` / `feedback_*.md`
files, or `.memory-state.json`. Those are `claude-memory`'s, they are the record this wiki indexes,
and the wiki is worth nothing if the record can move under it.

**It never deletes anything.** Consumed inbox captures are *moved* to `wiki/inbox/consumed/`, never
removed. A page that turned out wrong keeps its file and gets `status: superseded` plus a
`superseded_by: "[[<new-page>]]"` pointing at the page that replaced it. `wiki/log.md` is
append-only.

So there is no backup and no undo, and there is nothing to restore: **a bad ingest is corrected by
running forward, not recovered from a snapshot.** Fix or supersede the offending pages and re-run
`wiki-index.sh` — the index is regenerated from the pages every time and re-running it is
byte-identical when nothing changed. If the ledger write is what failed, re-run that one
`wiki-log.sh` call; do not redo the ingest, because the pages are already on disk and the consumed
captures are still in `inbox/consumed/`.

## Environment variables

| Variable | Set by | Effect |
| --- | --- | --- |
| `MEMORY_WIKI_NO_INJECT` | you | Any non-empty value: `wiki-inject.sh` exits before doing anything. No index at session start, zero processes spawned. |
| `MEMORY_WIKI_NO_NUDGE` | you | Any non-empty value: same, for `wiki-nudge.sh`. No pending-rollup reminder. |
| `CLAUDE_MEMORY_CONSOLIDATING` | `claude-memory` | Set to `1` around its headless consolidation run. **Every hook here exits immediately** — the recursion guard, matching `claude-memory`'s own. Not yours to set. |
| `CLAUDE_MEMORY_ROLLUP_FULL` | you, for `claude-memory` | Belongs to the other plugin. Once this wiki's index cites the latest weekly rollup — that is, once at least one page was written from that week — `claude-memory` stops dumping up to 200 lines of it at session start and injects only its `## Open threads` sections (capped at 60 lines), because the wiki now covers that week topically. `=1` restores the full dump. |

`MEMORY_WIKI_ATLAS_DIR` also appears in `wiki-inject.sh`, but **it is not a user-facing setting** and
is documented here only so nobody mistakes it for one: it exists so the test suite can drive the
cross-project atlas branch before Phase 4 makes it reachable. `bin/wiki-lint-project.sh` hardcodes
the same default (`$HOME/.claude/memory-wiki`) and does *not* honour the override, so setting it
today gives you a hook and a linter reading two different atlases.

## Why

Tier-3 distillation already writes `[[wikilinks]]` spontaneously — nothing instructs it to, and
nothing validates them. Across 32 memory-enabled projects on one machine, **39% of those links
resolve to no existing page** and **63% of pages have no inbound link at all**. Three naming
conventions are in use at once (human titles, kebab-slugs, `snake_case` filenames) with no schema to
arbitrate between them.

`lint` is what notices. `ingest` is what builds the graph that has edges. Neither fixes anything you
did not ask it to.

## Install

```bash
/plugin install memory-wiki@edusouza-plugins
```

## Usage

```
/claude-memory:init      # once, if this project has no memory yet
/memory-wiki:lint        # audit — works on a bare memory dir, no wiki needed
/memory-wiki:init        # scaffold wiki/ when there are rollups worth ingesting
/memory-wiki:ingest      # weekly, after /claude-memory:consolidate
```

`lint` deliberately works *before* `init`. A memory dir full of flat `concept_*.md` files is a wiki
with no edges, and auditing it is the point.

## Dependencies

- `bash` (git-bash on Windows) and `git` on `PATH`.
- **`python` (3.x) — a runtime dependency as of 0.4.0**, not just a test one. It generates the index
  and writes the `MEMORY.md` pointer, so `ingest` cannot complete without it; `wiki-index.sh` exits 1
  and says so rather than half-writing anything. The session-start hooks need it only on hosts that
  do not export `CLAUDE_PROJECT_DIR`, and no-op silently when it is absent. `claude-memory`'s own
  lifecycle hooks already require python, so a machine running both plugins has it.
- `pwsh` optional. A PowerShell twin of the linter (`bin/wiki-lint.ps1`) ships alongside the bash
  original and is held to byte-identical output; reach for it where shelling out through bash is
  unreliable. The index generator has **no** twin, on purpose: it is the one script that rewrites a
  delimited region inside a file another plugin also writes, and two independently-written
  implementations of that rewrite would be two chances to corrupt `MEMORY.md` instead of one.
- `claude-memory` for anything to audit or ingest. Not a hard requirement — the plugins install
  independently and `memory-wiki` vendors its own copy of the path resolution
  (`bin/_wiki-paths.sh`, byte-identical to `claude-memory`'s `_memory-paths.sh` in every executable
  line, and re-vendored rather than patched when that file changes) — but a project with no memory
  dir has nothing to lint, and `init` will say so rather than creating one.

## Tests

```bash
bash plugins/memory-wiki/test/run-tests.sh
```

No framework, no dependencies beyond the above. What it covers:

- **Linter goldens** — nine fixtures diffed against the exact expected stdout, plus a bash/PowerShell
  output-parity check over the same fixtures when `pwsh` is on `PATH`.
- **Index-render goldens** — `wiki-index.py --render-only` against the typed fixture, plus the write
  half: the region lands in `index.md`, `MEMORY.md` keeps every foreign line and its CRLF endings and
  gains only the stub, re-running is byte-identical, and the `index.md` `init` seeds is exactly what
  the generator would have written.
- **The ledger round-trip** — `wiki-log.sh` appends the entry format while preserving earlier ones,
  a failed write is reported as a failure rather than a false success, and logging a source clears it
  from `wiki-ingest-plan.sh`'s pending list.
- **Hook checks driven with real payload JSON** — both hooks fed an actual `SessionStart` payload on
  stdin: what they emit, that they are silent on every failure path, that the opt-outs and the
  recursion guard hold, and their measured spawn budgets under a `PATH` shim that logs every call.
- **`claude-memory` interop** — that an index citing the latest week trims the other plugin's rollup
  injection to its open threads, that no wiki, an empty wiki, and a populated wiki that has not yet
  ingested the latest week leave it unchanged, and that `CLAUDE_MEMORY_ROLLUP_FULL` restores the dump.
- **Version parity for both plugins** — `plugin.json` against the root `marketplace.json`, for
  `memory-wiki` and for `claude-memory`.
- A shape-only smoke test against a real memory dir, skipped when this machine has none.

Byte counts in the golden files are **not** platform artifacts: `wiki-lint` strips CR before
measuring, so the same fixture reports the same number on CRLF and LF input. If a count differs, fix
the script, not the golden file.

`test/expected/README.md` carries two recorded baselines — a pre-wiki lint of this repo's own memory
dir, and an after-baseline from one full `ingest` run over its rollups — each with an explicit
account of what the numbers do and do not license. Both are deliberately not asserted anywhere.

## License

MIT
