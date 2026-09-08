# memory-wiki — design

**Date:** 2026-08-21
**Status:** design approved in brainstorming; awaiting spec review before implementation planning
**Repo:** `edusouza/edusouza-plugins`
**Relationship to existing plugins:** consumes `claude-memory`; adapts the `llm-wiki` pattern. Neither is modified.

---

## 1. Problem

`claude-memory` compresses sessions along one axis: **time**. Sessions roll up into weeks, weeks
distil into a flat list of `concept_*.md` files indexed by `MEMORY.md`. Nothing connects a concept to
another concept, to the component it concerns, or to the same lesson learned in a different project.

The consequences are measurable. An audit of all 32 memory-enabled projects on this machine
(`scripts: audit-memory-graph.ps1`, read-only, 2026-08-21):

| Measurement | Result |
| --- | --- |
| Tier-3 pages across all projects | 318 |
| `[[wikilink]]` occurrences already written | 305 |
| **Links that resolve to no existing page** | **118 (39%)** |
| **Pages with zero inbound links (orphans)** | **200 (63%)** |
| Pages marked `dormant` (dropped from `MEMORY.md`, grep-only) | 47 |
| Cross-project near-duplicate pairs (lexical match only — a floor) | 18 |

Three distinct problems sit underneath those numbers.

### 1.1 The graph already exists and nothing maintains it

Tier-3 distillation writes `[[wikilinks]]` spontaneously — `tier3-distill.md` never mentions them.
It also writes cross-references it *cannot* express as links, in prose:

> **Why:** Hit three times independently — path-resolution fallback silently failing on `/c/` mounts
> **(W24)**, Bash find/ls mangling paths during the consolidate-bug investigation **(W27)**, and the
> `rtk` hook rejecting a compound `find` predicate **(W28)**.
> — `concept_windows_filesystem_tooling.md`

39% of those links dangle because three naming conventions collide with no schema to arbitrate:
`ai-job-search` links by human title (`[[Verify the parsed layer, not the rendered one]]`), `catalogo`
links by kebab-slug, and files on disk are `concept_snake_case`. No linter has ever looked.

### 1.2 Retrieval is time-shaped; questions are topic-shaped

To answer "what do I know about plugin versioning?" you must read whole weeks. There is no page for
the `claude-memory` plugin, none for the `rtk` hook, none for "plugin updates stop propagating" —
recurring entities with no home. Session-start injection compounds this by spending its entire budget
on **recency**: last week's rollup is injected whether or not it relates to the task at hand, and the
other seven weeks are invisible.

### 1.3 Per-project memory cannot see its own most valuable pattern

The same lesson is being relearned across projects, and no layer exists that could notice:

| Lesson | Independently rediscovered in |
| --- | --- |
| Prefer harness tools over shelling out | **5 projects** — `claude-plugins`, `seguro-ai`, `interview`, `reviewer`, `~` |
| An empty result is a claim, not evidence of absence | **4 projects** — `mockstage-website`, `seguro-ai`, `obsidian-LLM-Wiki`, `reviewer` |
| Validate an artifact before destroying its source | **3 projects** — `claude-plugins`, `interview`, `AppData-Local-Temp` |
| "No direct commits to master" | 2 projects, as *byte-identical rules* under two slug conventions |

Five separate weeks spent rediscovering one fact about this laptop.

### 1.4 Defects that persisted because nothing audits

Found incidentally while building the PoC, all pre-existing:

- **5 of 8 weekly rollups** in `claude-plugins` carry two `# Week` headers. Re-consolidation appends
  rather than replaces; `rollup_is_valid()` requires a `# Week` header to be *present*, not unique.
- **`2026-W26` and `2026-W28` contradict each other** on whether commit `c97df67` bumped
  `delivery-workflow`. Both rollups are on disk; nothing reconciles them.
- The untracked `blog-draft.md` / `blog-bug-rca.md` is **one standing item reported fresh in W27, W29,
  W30 and W31** — four consecutive weeks, never tracked as a single thread.
- The global auto-memory contains a dangling `[[dev-workflow-branch-before-coding]]` that was never written.
- **`CLAUDE.md` does not exist anywhere in the repo**, yet `2026-W26` records writing it via `/init`
  "merged as part of the branch," and `concept_check_existing_conventions_first` cites it as evidence.
  A stale claim propagated into a durable concept.

---

## 2. The insight

**Tier 3 is already a degenerate wiki — pages with the edges stripped out.** `MEMORY.md` is already an
index, and it already carries the `<!-- BEGIN … -->` delimited-region protocol so two writers can share
it. The link primitive and the maintenance loop are the only missing parts.

So this is not "bolt a wiki onto memory." The mapping to `llm-wiki` is near 1:1, and most of it already
exists:

| llm-wiki | claude-memory today | memory-wiki |
| --- | --- | --- |
| `sources/` — immutable, curated | `episodic/weekly/` — immutable, auto-generated | unchanged; pages cite `[[2026-W28]]` |
| `inbox/` — fleeting captures | *(none)* | `wiki/inbox/` — in-session captures |
| `wiki/` — LLM-owned pages | flat `concept_*.md`, no edges | `wiki/` — typed, linked pages |
| `wiki/index.md` | `MEMORY.md` | second delimited region in `MEMORY.md` |
| `wiki/log.md` | *(none — only `.memory-state.json`)* | `wiki/log.md`, append-only |
| `ingest` | `tier3-distill` | `ingest` — reads rollups **and** concepts |
| `query` | grep (Mode 1) | `query` — graph traversal with citations |
| `lint` | **nothing** | `lint` — script + model |
| `bootstrap` | `/claude-memory:init` | `init` — thin, additive |

---

## 3. Scope decisions (settled)

| # | Decision | Rejected alternative | Why |
| --- | --- | --- | --- |
| D1 | **Two layers** — per-project `wiki/` plus a thin global atlas | one global wiki; per-project only | one global store mixes work/client/personal contexts and a bad ingest pollutes everything; per-project only leaves §1.3 unclaimed |
| D2 | **New plugin consuming `claude-memory`** | extend `claude-memory`; supersede both | keeps the hard-won capture machinery untouched and independently versioned; both plugins work alone |
| D3 | **Rollups stay as permanent immutable sources** | consume-then-archive; skip Tier 2 | every claim stays traceable and `ingest` stays re-runnable; costs ~5 KB/week/project |
| D4 | **`UserPromptSubmit` auto-recall ships, default on** | model-invoked recall only | the model almost never *decides* to grep; see §6.1 |
| D5 | **Index replaces the rollup dump, except `## Open threads`** | keep the full rollup; drop it entirely | the rest of the rollup is superseded topically and still on disk; open threads carry continuity value the index does not reproduce (351 B in the current rollup) |

---

## 4. Architecture

### 4.1 Boundary with claude-memory

`memory-wiki` **reads** what `claude-memory` writes and never modifies it:

- **Reads:** `episodic/weekly/*.md`, `episodic/sessions/*.md`, `concept_*.md`, `project_*.md`, `feedback_*.md`
- **Writes:** `<memdir>/wiki/**` and one new delimited region in `MEMORY.md`
- **Never writes:** `concept_*.md` at the memory-dir root, `episodic/**`, `.memory-state.json`

The `MEMORY.md` coupling is solved by the repo's own established pattern
(`concept_shared_file_delimited_regions`): a second region alongside the existing one.

```
<!-- BEGIN claude-memory tier-3 (managed; do not edit by hand) -->   ← claude-memory owns
<!-- END claude-memory tier-3 -->
<!-- BEGIN memory-wiki (managed; do not edit by hand) -->            ← memory-wiki owns
<!-- END memory-wiki -->
```

Each writer rewrites only between its own markers and preserves everything else, including the
user's global auto-memory entries that also live in this file.

**Consequence, accepted:** `ingest` runs *alongside* `tier3-distill` rather than replacing it — one
extra LLM pass per week per project. Removing it would require an env guard inside `claude-memory`,
which D2 puts out of scope for v1. To avoid duplicated content, the `memory-wiki` region **omits the
heuristics list** that `claude-memory`'s region already carries (§6.6).

### 4.2 On-disk layout

```
~/.claude/projects/<project-hash>/memory/        ← claude-memory owns everything above wiki/
├─ MEMORY.md                     two managed regions + the user's own entries
├─ concept_*.md                  Tier 3, read as input, never rewritten
├─ episodic/
│  ├─ sessions/                  Tier 1
│  └─ weekly/                    Tier 2 — the wiki's immutable sources/
└─ wiki/                         ← memory-wiki owns this subtree
   ├─ README.md                  page schema, human- and Obsidian-visible
   ├─ log.md                     append-only operations record
   ├─ inbox/                     in-session captures, triaged by the next ingest
   ├─ project_*.md
   ├─ component_*.md
   ├─ tech_*.md
   └─ failure_*.md

~/.claude/memory-wiki/                            ← the atlas (cross-project)
├─ index.md                      managed region, injected every session
└─ <promoted pages>
```

Path resolution reuses `claude-memory`'s `_memory-paths.sh` semantics verbatim, including the
worktree rule: a linked worktree resolves to the **main** repo's memory dir, so a project's wiki stays
unified across worktrees.

### 4.3 Data flow

```
episodic/sessions/ ─┐
narratives ─────────┼──▶ episodic/weekly/ ──┐
                    │    (immutable, cited)  │
concept_*.md ───────┘                        ├──▶ [ingest] ──▶ wiki/*.md
                                             │                 + MEMORY.md region
wiki/inbox/ ─────────────────────────────────┘                 + wiki/log.md
                                                                     │
                                    [promote] ◀────────────────────────┤
                                        │                              │
                                        ▼                       [lint] ┘
                              ~/.claude/memory-wiki/            (report only,
                                                                 never auto-fixes)

                    [query] ◀── reads wiki/ + atlas, cites both
```

---

## 5. Page schema

### 5.1 Types

Five types, of which two already exist. Each must earn its place; a type that could be a tag is a tag.

| Prefix | Holds | Why not a `concept_` |
| --- | --- | --- |
| `project_` | a repo: conventions, environment, standing threads | *(already exists; now linked)* |
| `component_` | a plugin, script, or subsystem within a project | **no home today** — nothing describes "the claude-memory plugin" as a thing |
| `tech_` | external tool/platform mechanics | **no home today** — `gh`, headless `claude -p`, plugin loading |
| `failure_` | **symptom → cause → fix → generalization** | different retrieval path: you search by the error text in front of you, not by the lesson you would draw from it |
| `concept_` | durable heuristic — *what to do* | *(already exists; absorbed verbatim)* |

`feedback_*` is left entirely to `claude-memory`.

**Explicitly rejected types:** `decision_` (folded into a `## Decisions` section on the relevant
`component_` page — a standalone decision page duplicates the rollup that already dates it) and
`thread_` (open threads are transient; `lint` generates them as a report rather than pages).

The `failure_` / `concept_` split is the highest-value part of this schema. A concept says *what to
do*; a failure page says *what you saw*. `concept_best_effort_shutdown_hooks` is useless when you are
staring at `Hook cancelled` and do not yet know that is what you are looking at.

### 5.2 Frontmatter

Flat, matching the existing on-disk convention exactly — no nesting under `metadata:`, `name:` is a
human title, not a slug.

```yaml
---
name: <Human Title, sentence case>
description: <one-line recall summary>
type: project | component | tech | failure | concept
status: active | dormant | superseded
last_accessed: YYYY-MM-DD
# type-specific:
part_of: "[[component_or_project]]"      # component_
symptom: "<literal string you would see>" # failure_ — REQUIRED, feeds §6.1 matching
sources: ["[[2026-W28]]", ...]            # provenance, required on generated pages
promoted_to: "[[atlas/<page>]]"           # set by promote
---
```

Atlas pages additionally carry `scope: global`, `promoted_on:`, and an `evidence:` list of
`{project, page, finding}` triples.

### 5.3 Link conventions

One convention, enforced by the linter — this is what §1.1 lacked.

- **All internal links are `[[<exact-filename-without-extension>]]`.** Never the human title, never a
  kebab-slug that does not match a file. This is the single rule whose absence produced 118 broken links.
- **Source citations** use the rollup filename: `[[2026-W28]]`.
- **Project → atlas** links use `[[atlas/<page>]]`. The linter resolves the `atlas/` prefix against the
  atlas dir.
- **Atlas → project** links are *not* wikilinks. Separate vaults cannot resolve them, and pretending
  otherwise would manufacture broken links. The `evidence:` frontmatter carries the trail, rendered in
  the body as a plain table. **This is a deliberate asymmetry**, documented so `lint` does not flag it.

---

## 6. Runtime — how agents interact during a session

The weekly write path is only half the system. Memory that requires an agent to *decide* to look it up
mostly does not get looked up.

### 6.1 Automatic read — no decision required

| When | Mechanism | Payload |
| --- | --- | --- |
| SessionStart | `bin/wiki-inject.sh` | project index region + atlas index region |
| Every prompt | `bin/wiki-recall.sh` on `UserPromptSubmit` | 0–3 **one-line pointers**, never bodies |

**The index is shaped for triggering, not browsing.** Failure-mode entries lead with the literal
string you would see in a terminal:

```
`SessionEnd hook [...] failed: Hook cancelled` → [[failure_sessionend-hook-cancelled]]
```

When that text scrolls past, the match happens with **zero tool calls** — the key is already resident.

**`UserPromptSubmit` auto-recall (D4).** Deterministic, no LLM: case-insensitive substring match of the
prompt against `symptom:` frontmatter values, page names, and `description:` lines from both index
regions. Constraints, chosen so this cannot become noise:

- **Cap 3 hits**, ranked by match length (longest literal wins — a `symptom:` match beats a name match)
- **Minimum match length 8 characters**, to suppress incidental hits on short words
- **Emit pointers only** — `name — description → path`, roughly 40 tokens per hit
- **Silent on a miss**, which is the common case, so steady-state cost is zero
- **Kill switch** `MEMORY_WIKI_NO_RECALL=1`, mirroring `CLAUDE_MEMORY_NO_NUDGE`
- Skipped entirely when `CLAUDE_MEMORY_CONSOLIDATING=1`, matching the existing recursion guard

### 6.2 On-demand read — agent decides

The index line **is** the affordance: a matched line leads to one `Read` of a 2–3 KB page. No skill
invocation needed for the common case.

The `query` skill is reserved for genuine synthesis: index → 3–10 pages → follow `[[wikilinks]]` →
cited answer → filed back as a `query-synthesis` page when the answer took real work. Filing back is
the norm for substantial queries, not the exception, so explorations compound.

### 6.3 In-session write — *write-through for evidence, inbox for structure*

| Operation | Timing | Rationale |
| --- | --- | --- |
| Append a dated instance to an existing page | **live** | cheap, safe, and full context exists only now — the same reason the narrative nudge exists |
| Create a page | **live only if** the index shows no match | otherwise duplicates |
| Drop a capture in `wiki/inbox/` | **live**, for anything uncertain | the next `ingest` triages it |
| Merge, restructure, promote to atlas, mark dormant | **never mid-session** | all require the whole-corpus view a session does not have |

`wiki/inbox/` is not a new mechanism — it is `llm-wiki`'s `inbox/` reused for exactly the reason it
exists there: fleeting captures should not become pages until something can see them all together.

### 6.4 Subagents

Subagents run with their own context, so SessionStart injection does not reach them. The contract:

- **The dispatching agent passes page *paths*, not bodies.** Pick matching `failure_*` / `concept_*`
  entries from the resident index and name them in the dispatch prompt; the subagent reads only what it
  needs.
- **Subagents do not write to the wiki.** They return findings; the parent appends or files to inbox.
  Parallel agents writing one wiki is a race with no whole-corpus view.

`failure_*` pages are what subagents benefit from most — a reviewer that knows the project's recorded
failure modes reviews differently from one that does not.

### 6.5 End of turn

Extend the *reason text* of `claude-memory`'s existing `Stop` nudge to also flush `wiki/inbox/`.
**Do not add a second `Stop` hook** — nudge fatigue would degrade both. If `claude-memory` is absent,
`memory-wiki` registers its own `Stop` nudge using the same three guards (`stop_hook_active`, a
per-session `.nudged-<sid8>` marker, and target-file existence) plus the same substance gate.

### 6.6 Injection budget

Measured against the live `claude-plugins` memory and the PoC wiki (30 pages):

| | today | with memory-wiki |
| --- | --- | --- |
| last session capture | 5,651 B | 5,651 B |
| weekly rollup | 4,876 B (full) | **351 B** (`## Open threads` only, D5) |
| `MEMORY.md` | 3,435 B | 3,435 B *(unchanged)* |
| memory-wiki region | — | **+1,671 B** (symptom index + map + sources) |
| **total** | **13,962 B ≈ 3,878 tok** | **11,108 B ≈ 3,086 tok** |
| per prompt | 0 | 0 on a miss; ~40 tok per hit, capped at 3 |
| **covers** | **13** heuristics + last week | same 13 + 30 pages + atlas + symptom index + component map |

Note the "13": the project holds 18 Tier-3 files, but 5 are `dormant` and therefore dropped from
`MEMORY.md` — reachable only by grep, which nothing triggers. The wiki index surfaces them again as
map and symptom entries without re-listing them as heuristics.

The region is 1,671 B rather than 3,121 B because it omits the heuristics list that `claude-memory`'s
own region already carries (§4.1). Net: **~790 fewer tokens at session start, for strictly more coverage.**

Injection does not scale with the global corpus — the project index covers one project, and the atlas
is bounded by its promotion bar.

---

## 7. Skills

| Skill | Does | Cadence | Trigger |
| --- | --- | --- | --- |
| `init` | scaffold `wiki/`, write `wiki/README.md` schema, register the atlas, install hooks | once per project | `/memory-wiki:init` |
| `ingest` | rollups + concepts + inbox → typed pages, links, index region, log entry | weekly, after consolidate | `/memory-wiki:ingest`, or the SessionStart nudge |
| `query` | graph recall with citations; files substantial answers back | on demand | model-invoked |
| `lint` | script does structure exhaustively; model does contradictions, stale claims, gaps | monthly | `/memory-wiki:lint` |
| `promote` | scan all memory dirs for ≥2-project findings; promote to atlas with evidence | monthly | `/memory-wiki:promote` |

**`ingest` rules** (inherited from `llm-wiki`, adapted):

- Read the index **first**; prefer updating an existing page over creating one.
- Never modify `episodic/**` or root `concept_*.md` — those are sources.
- Every generated page carries `sources:` provenance.
- Re-running over an already-ingested week is a no-op unless the week's content changed
  (detected via `wiki/log.md`, the same way `llm-wiki`'s ingest detects unprocessed sources).

**`lint` rule:** report, never auto-fix. Structural findings exhaustive; content findings prioritised.
This mirrors `llm-wiki`'s lint and respects `concept_diagnose_then_offer_options`.

**`promote` rule:** the bar is the *same finding recorded independently in ≥2 project wikis*. The count
is evidence, not a vote. Promotion never deletes the local pages; it sets `promoted_to:` on each and
links the atlas page back through `evidence:`.

---

## 8. Bundled scripts

Per this repo's convention, non-trivial shell lives in `bin/`, not inline in a SKILL.md
(`prefer-scripts-over-inline-shell-in-skills`). Each ships as a `.sh` / `.ps1` pair, since the
environment's Bash layer is unreliable for filesystem work (`concept_windows_filesystem_tooling`).

| Script | Purpose | Status |
| --- | --- | --- |
| `wiki-lint` | structural audit: broken links, orphans, missing frontmatter, injection budget | **prototype works** (`wiki-lint.ps1`) |
| `wiki-scan-dupes` | cross-project duplicate candidates for `promote` | **prototype works** (`audit-memory-graph.ps1`) |
| `wiki-inject` | SessionStart — emit both index regions | to build |
| `wiki-recall` | `UserPromptSubmit` — match prompt against index, emit ≤3 pointers | to build |
| `wiki-nudge` | SessionStart — count un-ingested rollups, print a one-line reminder | to build |

`wiki-lint` must exclude `index.md` and `log.md` when computing orphans: both link to nearly every
page by design, and counting them hides every orphan.

---

## 9. Safety, privacy, redaction

- **`memory-wiki` never deletes anything.** Sources are immutable, `log.md` is append-only, `ingest` is
  re-runnable. A bad ingest is corrected by re-running, not recovered from backup. This follows
  directly from `concept_verify_before_destroy`, the most expensive lesson in this corpus.
- **Redaction rules are inherited unchanged** from `claude-memory`: secrets, PII, and confidential
  customer/business data are stripped at write time. Wiki pages are re-read and re-sent every session,
  so they are held to the same bar as Tier 3.
- **The atlas raises a privacy surface the per-project design did not have**, since it aggregates
  across work, client, and personal projects. Mitigations: the ≥2-project bar, atlas pages carrying
  only the abstraction (never project specifics beyond the `evidence:` table), and a
  `MEMORY_WIKI_ATLAS_EXCLUDE` list of project hashes never scanned.
- **Any headless `claude -p`** used by `ingest` inherits the `CLAUDE_MEMORY_CONSOLIDATING=1` guard
  convention plus a clean temp cwd, so plugin hooks no-op and cannot recurse (`tech_headless-claude`).

---

## 10. Risks

| Risk | Severity | Mitigation |
| --- | --- | --- |
| **Ingest prompt quality is the real unknown** — the PoC pages were hand-authored | **high** | Phase 2 iterates the prompt against the PoC output as an explicit quality benchmark; the PoC ships in the repo as the target |
| `UserPromptSubmit` recall becomes noise | medium | cap 3, min match 8 chars, pointers only, silent on miss, kill switch; ship default-on and tune from real misfires |
| Page explosion across 32 projects | medium | injection is per-project so it never scales with the global total; `lint` polices the rest; `ingest` caps pages created per run |
| Duplicate LLM pass with `tier3-distill` | low | accepted for v1 (§4.1); a one-line `claude-memory` env guard removes it later |
| Two writers race on `MEMORY.md` | low | delimited regions + atomic temp-then-rename, the pattern already proven in `claude-memory` |
| Atlas links unresolvable in Obsidian | low | deliberate asymmetry, documented in §5.3 so `lint` does not flag it |

---

## 11. Phases

**Phase 1 — `init` + `lint`.** Ships value before anything writes: point it at the *existing* memory
and it reports the 118 broken links and 200 orphans. Zero LLM cost, zero risk, and it validates the
schema before a single page is generated.

**Phase 2 — `ingest` + the `MEMORY.md` region + `wiki-inject`.** The core. Prompt iterated against the
PoC output.

**Phase 3 — `wiki-recall` + `query`.** The runtime read loop (§6.1, §6.2). Split from Phase 2 so the
per-prompt hook can be tuned against a wiki that already exists.

**Phase 4 — `promote` + the atlas.** Needs several project wikis to exist before the ≥2 bar means anything.

---

## 12. Non-goals

- Replacing `claude-memory`. Capture, Tier 1 and Tier 2 stay where they are.
- Fixing the defects in §1.4. They are **findings, not scope** — `lint` surfaces them; acting on them
  is a separate decision. The duplicate-rollup bug in particular belongs to `claude-memory`.
- Embeddings, vector search, or any index beyond a Markdown file. The corpus is ~50 KB per project;
  grep plus an index is sufficient and keeps the store portable and human-readable.
- Syncing to the user's existing Obsidian LLM-Wiki vault. Separate corpus, separate purpose.

---

## Appendix A — PoC evidence

Built 2026-08-21 from the real `claude-plugins` memory: 8 weekly rollups, 10 narratives, 18 existing
Tier-3 pages. Artifacts in the session scratchpad under `poc-memory-wiki/`.

| | live memory | PoC wiki |
| --- | --- | --- |
| pages | 19 *(18 Tier-3 files + `MEMORY.md`)* | 30 |
| `[[wikilinks]]` | 11 | **171** |
| broken links | 1 | 1 *(the same pre-existing one)* |
| orphans | **9 (47%)** — 8 concept pages, plus `MEMORY.md` itself | **0** |
| missing frontmatter | 1 *(`MEMORY.md`, which is the index — not a defect)* | 0 |

**Recall, measured.** *"`SessionEnd hook failed: Hook cancelled` — does it matter?"* — today: grep hits
3 files across 9.1 KB, which must then be synthesised. Wiki: **one 2.3 KB page**, reached from the
resident index with no grep.

*"What do I know about shell tooling across all my projects?"* — today: unanswerable without sweeping
32 dirs by hand. Wiki: one atlas page.

**What the PoC did not prove:** pages were authored by hand, not by headless `claude -p`. *The material
supports this quality* is demonstrated; *the automated prompt reaches it* is not. Atlas promotion across
32 projects was measured lexically, not generated. Both are Phase 2/4 risks, tracked in §10.

---

## Appendix B — open questions

Deferred deliberately; none blocks implementation.

1. **Ingest cadence when consolidation is skipped.** If weeks go un-consolidated, rollups do not exist
   and `ingest` has no sources. Options: fall back to ingesting session narratives directly, or simply
   nudge for consolidation first. Decide once Phase 2 has real usage data.
2. **Atlas page count ceiling.** The ≥2 bar is untested at scale; 32 projects may promote more than
   expected. Revisit after Phase 4 with a measured count.
3. **Whether `query` should read the atlas by default** or only on explicit cross-project questions.
   Cheap either way; decide from observed query shapes.
