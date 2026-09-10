---
name: ingest
description: Distil this project's un-ingested weekly rollups and inbox captures into memory-wiki pages, then regenerate the index and append the ingest ledger. Use when the user says "ingest", "update the memory wiki", "run memory-wiki ingest", "add last week to the wiki", "write up the last few weeks", or when session start reports that this project has un-ingested weekly rollups pending.
---

# Ingest into the memory wiki

One run is one pass over the rollups that are still pending. Everything mechanical here is
scripted — what is pending, what the index says, what the ledger records, what lints. The only
judgment left is which pages to write and what they say, and the rules for that live in
`references/page-authoring.md`, beside this file.

Work through the eight steps in order. Step 1 can end the run on its own.

## 1. Get the work order

```bash
bash "${CLAUDE_PLUGIN_ROOT}/bin/wiki-ingest-plan.sh" "<memdir>"
```

Take `<memdir>` from the `## Memory - dir for this project` line injected at session start, and
**pass it explicitly**. Deriving it from the cwd is wrong inside a git worktree — it resolves to
the main repo — and it is also the slow path: resolution costs several process spawns, which on
Windows is most of a second for an answer you were already handed.

The script prints three sections, each with its count and an explicit `(none)` when empty:
`## Pending sources` (the rollups no ledger entry cites yet), `## Existing pages`
(`name | type | description`, one per line), and `## Inbox`.

**If `## Pending sources` is `(none)` and `## Inbox` is `(none)`, stop here.** Say there is
nothing to ingest and end the run. Do not read the rollups, do not write a page, do not append a
ledger entry. Re-ingesting a week that is already logged is how duplicate pages get made, and the
duplicates are not detectable afterwards from anything on the page.

If you see `ERROR: no wiki for: <memdir>`, this project has a memory dir but no wiki. Stop and
tell the user to run `/memory-wiki:init`. Do not scaffold anything yourself. That report is
printed on **stderr**, not stdout — with stderr discarded you see an empty work order and no
explanation, so keep it (`2>&1`).

Do not re-derive any of this by globbing. `wiki-ingest-plan.sh` reports the single implementation of
"pending" — the same one the session-start nudge calls — and a second opinion about it is a week
silently missing from the wiki.

## 2. Read the rules

Read `references/page-authoring.md` in full before writing the first page. Read it this run, from
this file, not from memory of some other wiki — what earns a page, the five types, the frontmatter
each type requires, the one link convention, and the body shapes are all in there, and this skill
deliberately does not restate them.

## 3. Read the sources

- **Only the rollups listed under `## Pending sources`**, at `<memdir>/episodic/weekly/<week>.md`.
  Not the whole directory: the ones already cited in the ledger have been ingested.
- Any root `concept_*.md` in `<memdir>` that those rollups touch — to link rather than restate,
  and to avoid writing a page for something Tier 3 already covers.
- Every file listed under `## Inbox`, at `<memdir>/wiki/inbox/*.md`. Not `inbox/consumed/`.
- The pages under `## Existing pages` whose `description` overlaps what you are about to write.
  You need them to decide update-vs-create, which is step 4's first rule.

`<memdir>/episodic/**` and the root `concept_*.md` files are **immutable inputs**. Read them;
never edit them.

## 4. Write the pages

The full rules are in the reference. These are the ones runs actually skip:

- **Prefer updating an existing page over creating a new one.** Revise the body in place, add the
  new rollup to `sources:`, bump `last_accessed:`. Not a second page next to the first.
- **At most 8 new pages per run.** Updates are not capped. Zero new pages is a correct outcome —
  never invent a page to avoid reporting zero.
- **Every page carries `sources:`**, citing the rollup the material genuinely came from.
- **Every page is linked *from* somewhere before you call it finished** — a `failure_` from its
  `component_`'s `## Failure modes`, a `component_` from its `project_` page. Links from
  `index.md` and `log.md` do not count and are excluded from inbound-edge accounting on purpose.
- **Never create a `concept_*` page.** Those are Tier 3, owned by `claude-memory`, and live at the
  root of the memory dir. Link them; leave them alone.

Every inbox capture gets a disposition this run: fold it into an existing page, or promote it to a
page of its own. Leaving one in the inbox is the exception, not a third default — do it only when
the capture genuinely is not yet enough to become or join a page, and say why in the report. Then
**move** the ones you used, and never delete them:

```bash
mkdir -p "<memdir>/wiki/inbox/consumed"
mv "<memdir>/wiki/inbox/<capture>.md" "<memdir>/wiki/inbox/consumed/"
```

`mkdir -p` first: `wiki-init.sh` scaffolds `inbox/` but not `inbox/consumed/`, so on a wiki that
has never ingested, that directory does not exist yet.

## 5. Regenerate the index

```bash
bash "${CLAUDE_PLUGIN_ROOT}/bin/wiki-index.sh" --wiki "<memdir>/wiki" --memory-md "<memdir>/MEMORY.md"
```

**Never write `wiki/index.md` or the `memory-wiki` region of `MEMORY.md` by hand.** This script is
the only writer of both. It splices its region into `MEMORY.md` between its own markers without
touching a byte outside them — including the region `claude-memory` owns in the same file — and
hand-editing is how that guarantee gets lost.

Windows fallback, if shelling through the wrapper proves unreliable — the wrapper does nothing but
locate the interpreter and hand off:

```bash
python "${CLAUDE_PLUGIN_ROOT}/bin/wiki-index.py" --wiki "<memdir>/wiki" --memory-md "<memdir>/MEMORY.md"
```

`wiki-index.sh` exits 1 with a clear message when no python is on PATH, so read the exit code: a
failed index leaves the pages correct but unreachable from `MEMORY.md`.

## 6. Append the ledger entry

One call, once, after the pages are written and the index is regenerated:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/bin/wiki-log.sh" --wiki "<memdir>/wiki" \
  --op ingest --title "<what this run covered>" \
  --sources "2026-W30, 2026-W31" \
  --created "component_foo, failure_bar" \
  --updated "project_baz" \
  --inbox "2026-09-02-note.md"
```

- **`--sources` must name every week you read this run.** Those are the `- Sources:` lines
  `wiki-ingest-plan.sh` reads back to work out what is still pending, so this call — and only this
  call — is what clears them. A week left out is offered again next run, and ingested twice.
- Omit `--created`, `--updated` or `--inbox` when there is nothing to report. `--sources` is
  always written, even empty.
- One entry per run, not one per page. Never hand-write `log.md`; it is append-only and this
  script is its only writer, so an entry typed in a slightly different shape un-ingests a week.
- **Check the exit code.** It exits 1 and says so when the write fails, rather than reporting a
  false success. If it fails, the entry was *not* recorded: say so in the report and fix it by
  re-running this one call. Do not redo the ingest — the pages are on disk and the consumed
  captures are still in `inbox/consumed/`, because nothing here deletes anything.

## 7. Verify

```bash
bash "${CLAUDE_PLUGIN_ROOT}/bin/wiki-lint.sh" "<memdir>/wiki" \
  --sources "<memdir>/episodic/weekly" \
  --concepts "<memdir>"
```

`--concepts` is not optional in practice: it is what makes the root `concept_*.md` files resolve
as link targets. Without it, every page you wrote that cites a concept reports as a broken link.

**Every page written or updated this run must lint clean.** Draw the line explicitly:

- **Findings on your own pages: fix them.** An orphan among them means you wrote a page and forgot
  the inbound link — add the link, do not delete the page. A broken link is nearly always a target
  written as a human title or a kebab-slug instead of the exact filename.
- **Findings on pages this run did not touch are pre-existing: report them, name them, leave them
  alone.** That is not a violation of "lint reports, never fixes" — that rule is about findings
  you did not create. Fixing them silently mixes someone else's damage into this run's diff.

Re-run the linter after any fix, and re-run step 5 if a fix changed frontmatter.

## 8. Report

```
## Ingested
<weeks, comma-joined — or "none">

## Pages
created: <names, or none>
updated: <names, or none>

## Inbox
<capture> -> folded into <page> | promoted to <page> | left in inbox because <reason>

## Lint
<the counters from step 7, verbatim — do not re-derive or summarize them>

Pre-existing findings left alone: <named, or "none">
```

Report the lint counters verbatim; they are exhaustive about structure by construction. The
pre-existing line is separate and always present, even when it says none — it is what tells the
user which findings this run is not responsible for.

## Rules

- **Write only inside `<memdir>/wiki/`**, plus the `memory-wiki` region of `<memdir>/MEMORY.md` —
  and that region only through `wiki-index.sh` (step 5), never by editing `MEMORY.md` yourself.
- **Never modify anything under `<memdir>/episodic/`, and never the root Tier-3 files** —
  `concept_*.md`, `project_*.md`, `feedback_*.md`, `.memory-state.json`. They belong to
  `claude-memory`. They are the record this wiki indexes, and the wiki is worth nothing if the
  record can move under it.
- **Never delete anything.** Consumed captures move to `inbox/consumed/`. Superseded pages keep
  their file. `wiki/log.md` is append-only. If something looks like it should go, say so in the
  report and leave it.
- **Redaction is inherited from `claude-memory` unchanged** — people by role and never by name or
  address, no secrets ever, volatile identifiers stripped from quoted output. §6 of the authoring
  reference has the detail. Pages are re-read and re-sent every session, so they are held to
  exactly the Tier-3 bar.
- **On a contradiction with an existing page: write the new page, set the old page's
  `status: superseded` and add `superseded_by: "[[<new-page>]]"`, and say so in the report.** Do
  not silently pick a winner, and do not delete or overwrite the old page. A superseded page is
  dropped from the generated index but is still orphan-checked, so keep an inbound link to it or
  the next audit reports it as an orphan.
- **When it is the *newer* material that turned out to be wrong** — the rollup it came from was
  later reversed — the existing page stands. Leave it `active`, record the reversal in its body
  citing both rollups, and say so. Correcting a source without naming what you are correcting is
  how the mistake gets re-derived from the rollup that still records it.
