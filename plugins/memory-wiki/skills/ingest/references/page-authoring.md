# Writing pages for a project's memory wiki

A memory wiki distils immutable weekly rollups (`episodic/weekly/*.md`) into a small set of pages
that are cheap to search and safe to re-read. The rollups are the record; the wiki is the index
into it. Everything below is about the one thing no script can do for you: deciding what deserves
a page, and what that page says.

Read this whole file before writing the first page of a run.

---

## 1. What earns a page

Three tests. **All three must pass.**

1. **It recurs.** Two or more sources mention it, or one source says in so many words that it will
   happen again ("expect this to be copied forward", "this is the third time"). A fact that
   happened once and is unlikely to happen again is already recorded in the rollup that holds it.
2. **It has a name a future session would search for.** An error string, a plugin name, a tool
   name, a repo name. If you cannot write the `description:` as the sentence somebody would type
   when they hit this again, there is no page here — only a paragraph that belongs to a rollup.
3. **It is not already covered.** Read every existing page's `name:` and `description:` first, and
   the root `concept_*.md` files alongside them. "Covered" includes covered badly: a thin page on
   the subject means you update that page, not that you write a better one next to it.

### Prefer updating an existing page over creating a new one

This is the single most commonly skipped rule in this whole file. When new material touches
something a page already covers, the work is: revise the body in place, add the new rollup to
`sources:`, and set `last_accessed:` to the date of the run. Not a second page.

**A corpus of near-duplicates is worse than a corpus of stale pages.** A stale page is found,
read, and corrected. Two near-duplicate pages are both found, they disagree, and nothing on either
page tells the reader which one is current — so both get distrusted, and so does everything next
to them. Splitting a subject across two pages also halves the inbound links to each, which is how
pages start showing up as orphans.

### The cap

**At most 8 new pages per run** — one run being one pass over the rollups that are still pending.
Updates to existing pages are not capped and never were; the cap exists to stop a large backlog of
un-ingested rollups turning into a wall of thin pages in a single pass.

If more than 8 candidates pass all three tests, take the 8 with the strongest recurrence evidence
and leave the rest. Nothing is lost: the rollups are immutable, and the next run reads the same
material with the same tests.

**Zero new pages is a correct outcome.** A quiet week produces no pages, and a run that creates
none has still done its job if it updated `last_accessed:` and `sources:` where the week touched
existing pages. Never invent a page to avoid reporting zero.

---

## 2. The five types

| Prefix | Holds | Reach for it when |
| --- | --- | --- |
| `project_` | one repo: its conventions, environment, standing threads | the material is about the repo as a whole rather than any one part of it. One per repo — if it exists, update it |
| `component_` | a plugin, script, or subsystem inside a project | the material is about a *named* part that has its own decisions and its own failure modes |
| `tech_` | an external tool or platform | the material is about something you did not write and cannot change: a CLI, a harness, a runtime, an API |
| `failure_` | one concrete defect: symptom → cause → fix → generalisation | the material contains a literal error, wrong output, or a hang you could recognise on sight |
| `concept_` | one durable heuristic | never — see below |

### Filenames

Pages live in `wiki/`, and the filename is `<prefix>_<kebab-case-subject>.md`, lower case:
`wiki/failure_slash-command-shell-substitution.md`, `wiki/component_claude-memory.md`. Nothing
derives the filename from `name:`, so the two are free to differ — but the filename **is** the link
target every other page uses, so choose it once and do not rename it. A rename breaks every inbound
link silently and turns the page into an orphan on the next audit.

### Two rules, both absolute

- **Never create a `concept_*` page here.** Concepts are Tier 3: `claude-memory` owns them, they
  live as `concept_*.md` at the root of the memory dir, and they are indexed from `MEMORY.md`.
  Read them, link them, and leave them alone. Writing one into `wiki/` forks the heuristic corpus
  into two piles that drift apart, and the pile in `wiki/` is the one nothing else maintains.
- **If material has both a *what you saw* half and a *what to do* half, write the `failure_` page
  and link the concept.** The halves are deliberately kept in different places: a concept says
  what to do, a failure page says what you saw, and you find a failure page by the error text in
  front of you. If no concept exists for the *what to do* half, still write the failure page and
  put the transferable sentence in its `## Generalisation` — do not create the concept to hold it.

### Types that were considered and rejected — do not invent them

- **A decision is not a page.** It goes in a dated entry under `## Decisions` on the relevant
  `component_` page, or on the `project_` page when it is repo-wide.
- **An open thread is not a page.** Open threads are transient by definition; a page for one is
  stale within a week and nothing prunes it. Reporting them is `lint`'s job, not a page's. Do not
  create `thread_`, `todo_`, `question_`, or `decision_` pages.
- **Episodic material is not a page.** Anything whose natural title is a date or a session belongs
  to the rollups, which already hold it and are already citable.

---

## 3. Frontmatter

Every page opens with a `---` fenced block on line 1. **Flat — top-level keys only.** An indented
key is invisible to `lint` and to the index renderer, which both read with `^key:` anchoring, so a
field nested under anything reports exactly as though it were absent.

```yaml
---
name: <Human Title, sentence case>
description: <one-line recall summary>
type: project | component | tech | failure | concept
status: active | dormant | superseded
last_accessed: YYYY-MM-DD
---
```

Those five are required on every page, whatever its type. Some types require more:

| `type:` | also required |
| --- | --- |
| `project` | `sources` |
| `tech` | `sources` |
| `component` | `part_of`, `sources` |
| `failure` | `symptom`, `sources` |
| `concept` | nothing extra |

Field by field:

- **`name:`** — a human title in sentence case. Not the filename.
- **`description:`** — one line, and the line rendered beside the page in the generated index Map.
  Write the sentence somebody would search, not a category label. "notes about memory" is a label;
  "how the consolidation pipeline is gated and where it writes" is a description.
- **`type:`** — exactly one of the five values, lower case. Getting it wrong and leaving it out are
  reported as different findings: an out-of-range value is a schema error, while an absent `type:`
  (or an indented one, which reads as absent) is reported as missing frontmatter and the page is
  then never judged against any type's extra requirements at all — so a typo'd `type:` silently
  buys the page an exemption from needing `symptom:` or `part_of:`.
- **`status:`** — `active` unless the page describes something no longer in use (`dormant`) or has
  been replaced by another page (`superseded`, and link the replacement in the body). Dormant and
  superseded pages are dropped from the generated index but are never deleted.
- **`last_accessed:`** — the date of the run that last wrote the page. Update it on every edit.
- **`sources:`** — a flow list of rollup wikilinks: `sources: ["[[2026-W27]]", "[[2026-W31]]"]`.
  This is what makes a claim checkable: it is the trail back to what actually happened. When
  updating a page, **add** the new rollup, never replace the list. Cite the rollup the material
  genuinely came from even when part of what it concluded has since been reversed, and say in the
  body which part no longer holds — a citation picked for tidiness rather than provenance turns the
  field into decoration, and decoration is the one thing `sources:` must never be.
- **`part_of:`** — one wikilink to the owning project page: `part_of: "[[project_claude-plugins]]"`.
  It has to name a page that already exists or one the same run creates. A component pointing at a
  project page nobody wrote is a broken link and an unattached component in a single line.

### `symptom:` — quote what you would see

`symptom:` is the only field that reaches the session-start index **verbatim**. It renders there as
a line of `` `<symptom>` → [[page]] ``, and matching the error text currently on screen against
that line is the only search anyone actually runs. A failure page without a usable `symptom:` is
unreachable by the one query that would have found it.

So quote it from the source, in the words the machine used, not in the words you would use to
describe it afterwards:

- `symptom: "Hook cancelled"` — right. It is what is on screen, so it matches.
- `symptom: "the hook was cancelled"` — useless. Nobody types that, and it appears nowhere in any
  output.

Keep it to one line. Trim only the parts that could never match twice — absolute home paths,
process ids, timestamps, hashes — and keep the shape where you trim: `Cannot open /home/<user>/…`
still matches on the half that is stable.

---

## 4. Links

**One convention: `[[exact-filename-without-extension]]`.** Never the human title, never a
kebab-slug that does not correspond to a file, never a relative path. Before this rule existed,
39% of the wikilinks across this machine's memory dirs resolved to nothing — three naming
conventions were in use at once and there was no schema to arbitrate between them.

- **Source citations use the rollup filename**: `[[2026-W31]]` for `episodic/weekly/2026-W31.md`.
- **Root `concept_*.md` links resolve.** `lint` is passed `--concepts` pointing at the memory-dir
  root, so `[[concept_windows_filesystem_tooling]]` is a live link even though the file lives outside
  `wiki/`. Link concepts freely — and link them rather than restating them, because the concept
  file is maintained elsewhere and a copy here will go stale silently.
- **`[[atlas/<page>]]` is a valid form with nothing behind it yet.** The cross-project atlas
  arrives in a later phase. Until it exists, every such link is a broken link: do not write one,
  and do not invent atlas pages to point at.
- **A wiki's own `README.md` is not part of the link graph at all** — it is neither counted as a
  page nor checked for inbound links. Do not link to it, and never "fix an orphan" by linking it
  from there.

### Add the inbound link before you call a page finished

A page nothing links to is an orphan, and an orphan is found by nothing but a directory listing.
The generated index does not rescue it: links from `index.md` and `log.md` are excluded from
inbound-edge accounting on purpose, precisely so that a page listed there but linked from nowhere
still shows up as the orphan it is. The inbound edge is part of writing the page, not a tidy-up
for later:

- every `failure_` page gets a line under `## Failure modes` on the `component_` page it belongs to;
- every `component_` page gets a mention in the body of its `project_` page;
- every `tech_` page gets a mention from the `project_` or `component_` page that is driven
  through it.

This is the second most commonly skipped rule, after preferring an update.

---

## 5. Body shape

**Budget 2–3 KB of body.** A page is re-read whole every time it matches, so its length is a
recurring cost paid on every hit, not a one-off cost paid when it is written. A page that wants to
be longer is holding more than one thing: split it, or push the detail back to the rollup, which
is immutable and already citable.

**`failure_` — four sections, in this order, always:**

1. `## Symptom` — the literal output, in a fenced block. Verbatim. Not paraphrased, not tidied.
2. `## Cause` — the mechanism, one paragraph. What the machine actually did, at the level of "this
   string is expanded before the shell starts", never "there was a bug in the resolver".
3. `## Fix` — concrete. The change that resolved it, specific enough to apply again without
   rediscovering anything.
4. `## Generalisation` — one transferable sentence: where else to expect this, and what to check.
   Link the concept page if one exists. If none does, the sentence still belongs here.

**`component_`:**

- One or two sentences on what it is and what it does.
- `## Decisions` — dated entries, newest first, each ending in its source citation. A decision
  without a date is unrankable against a later one; a decision without a citation is unverifiable.
- `## Failure modes` — one line per `failure_` page, linking it.

**`tech_`:**

- What the tool *actually does*, as distinct from what its documentation says. The documentation is
  online and is not worth re-hosting; the value of the page is the delta — behaviour observed here
  that the docs omit, understate, or get wrong. If every line could have been copied from the docs,
  the page has no reason to exist.

**`project_`:**

- Conventions: what this repo does its own way, including the ones that look arbitrary.
- Environment: OS, shells, runtimes, and the local quirks that bite.
- `## Standing threads` — the questions that keep coming back, not this week's TODO list.

---

## 6. Redaction

Inherited unchanged from `claude-memory`. Wiki pages are re-read and re-sent every session, so they
are held to exactly the same bar as Tier 3:

- **Refer to people by role**, never by name, email address, handle, or account id. "The user",
  "the reviewer", "the maintainer", "the reporter".
- **No secrets, ever.** Keys, tokens, passwords, connection strings, cookies, signed URLs, or
  anything shaped like one. When an error message embeds a credential, quote the error and mask the
  credential.
- **Strip volatile identifiers from quoted output** where they carry no signal: absolute home
  paths, session ids, process ids, temp directories.
- **Where redaction would break a match, mask the value and keep the shape.** `/home/<user>/.claude/…`
  still matches the stable half of the string; deleting the path entirely does not.

---

## 7. Before a page is done

- [ ] Frontmatter is flat, on line 1, and carries the five base fields plus its type's extras.
- [ ] `description:` is a sentence somebody would search for.
- [ ] `sources:` cites every rollup the page draws on, including the ones added by this run.
- [ ] Every `[[link]]` names a real file: a page in the wiki, a rollup in `episodic/weekly/`, or a
      root `concept_*.md`. No atlas links.
- [ ] Something links *to* this page.
- [ ] No names, no secrets.
- [ ] Body is 2–3 KB and holds one subject.

---

## 8. Worked exemplar — a `failure_` page

`wiki/failure_slash-command-shell-substitution.md`

````markdown
---
name: Shell substitution failed in a plugin slash command
description: a plugin slash command dies at load time when its shell substitution resolves the plugin's own path instead of using the literal plugin-root variable
type: failure
status: active
last_accessed: 2026-09-08
symptom: "Shell substitution failed for pattern"
sources: ["[[2026-W24]]"]
---
## Symptom

A plugin's slash command fails the moment it is invoked, before its body reaches the model:

```
Shell substitution failed for pattern "..." (detail withheld on this connection)
```

Two neighbouring errors are *not* this one, and their wording is how you tell them apart:
`Shell command permission check failed for pattern "..."` is an `allowed-tools` problem, and
`Shell command failed for pattern "...": <output>` means the command ran and exited non-zero.
Read which one you got before editing anything — widening `allowed-tools` for this one is a
no-op.

## Cause

Claude Code expands exactly one thing in a command body, textually, before any shell is
spawned: the literal `${CLAUDE_PLUGIN_ROOT}`. The substitution is a plain global regex over
that exact string, and it also normalises `\` to `/`. Anything that merely resembles it —
`${CLAUDE_PLUGIN_ROOT:-}` with a default, unbraced `$CLAUDE_PLUGIN_ROOT`, `CLAUDE_SKILL_DIR`,
or a `find` over `plugins/cache` written to locate the plugin's own directory — is left
untouched and reaches the shell as a reference to a name that was never in its environment.
The spawn then produces no normal result, which is what this message reports — logged
internally as a spawn failure, not a script error, which is why the snippet it quotes back
reads like a broken script.

## Fix

Delete the resolver and address the file through the literal form:

```markdown
!`bash "${CLAUDE_PLUGIN_ROOT}/bin/wiki-lint-project.sh"`
```

Never `exit` or `exec` inside a substitution block — they terminate or replace the shell
rather than returning output. If the command only needs to *show* a path, drop the
substitution entirely: no shell, no failure mode, no `allowed-tools` entry.

**This reverses the fix recorded in [[2026-W24]].** That week saw the same failure and read it
correctly — inside a command, `$CLAUDE_PLUGIN_ROOT` and `$CLAUDE_SKILL_DIR` really are empty,
since only hooks get those names in their environment — but drew the wrong conclusion: that a
command must therefore carry a filesystem fallback locating itself under
`$HOME/.claude/plugins/cache/`. The observation holds; the conclusion does not, because the
literal `${CLAUDE_PLUGIN_ROOT}` is never a name the shell resolves — it is gone before the
shell starts. The fallback resolver W24 added *is* the defect this page describes.

## Generalisation

Expect this defect to be copied forward when a plugin is scaffolded from a sibling — grep
every `plugins/*/commands/*.md` for `CLAUDE_SKILL_DIR`, `:-}` and `plugins/cache` after
fixing one. It shipped in [[component_claude-memory]] and was then inherited verbatim by the
plugin scaffolded from it. And when a page corrects an earlier fix, name the reasoning it
supersedes instead of quietly replacing it: the rollup that recorded that reasoning is
immutable and still on disk, so a reader who finds it and not this page will derive the
resolver again. See [[concept_slash_command_bash_needs_allowed_tools]].
````

Note what makes it findable: `symptom:` is the string that appears on screen, so the index line it
renders matches a paste of the error. The body quotes the error again, in full, under `## Symptom` —
the frontmatter line is the hook, the fenced block is the confirmation.

Note also what it does with a source whose conclusion turned out to be wrong. It cites `[[2026-W24]]`
anyway, because that is the week the material actually comes from, and then says plainly which part
of it no longer holds. Dropping the citation to avoid the awkwardness would have been worse than
useless: `sources:` is the only thing that makes a claim checkable, and a citation chosen for
tidiness rather than provenance quietly turns the field into decoration.

The page itself stays `status: active`. What was superseded is a conclusion inside an earlier
source, which this page corrects in place and names; `status: superseded` is for a page that another
page has replaced wholesale. Correcting a source without saying what you are correcting is how a
corrected mistake gets re-derived from the rollup that still records it.

---

## 9. Worked exemplar — a `component_` page

`wiki/component_claude-memory.md`

````markdown
---
name: Claude-memory plugin
description: the three-tier cross-session memory plugin — how its consolidation pipeline is gated and where it is allowed to write
type: component
status: active
last_accessed: 2026-09-08
part_of: "[[project_claude-plugins]]"
sources: ["[[2026-W27]]", "[[2026-W31]]"]
---
Owns this project's memory: Tier 1 session notes, Tier 2 weekly rollups under
`episodic/weekly/`, and Tier 3 durable concepts as root `concept_*.md` files indexed from
`MEMORY.md`. Consolidation runs headless out of `bin/memory-consolidate.sh`.

## Decisions

- **2026-W31 — inconsistencies in its own README are reported, not resolved unilaterally.**
  Its install instructions use generic `<marketplace>` placeholders where the other plugins
  name the marketplace concretely. Inconsistent, but not wrong, and normalising it is the
  owner's call rather than a documentation sweep's. [[2026-W31]]
- **2026-W27 — a rollup is structurally validated before any source is archived.** The gate
  requires exit 0, the absence of known error sentinels, and a `# Week` header. It replaced a
  non-emptiness check, under which a run that printed a context-overflow error to stdout and
  still exited 0 was accepted as a valid rollup — and its raw transcripts deleted. A failed
  week now leaves its sources intact and retries. [[2026-W27]]
- **2026-W27 — raw transcripts are budgeted into the prompt, never dumped into it.** 20 KB of
  head plus 10 KB of tail per file, 120 KB per week. Chosen over dropping raw transcripts
  entirely, because the curated notes are the primary signal and are always passed in full
  while the raw material is only corroboration. [[2026-W27]]
- **2026-W27 — `MEMORY.md` is written per-writer, inside delimited regions.** Tier 3 rewrites
  only what lies between its own `BEGIN`/`END` markers, because a separate global auto-memory
  index owns other content in the same file and a wholesale overwrite erased it.
  [[2026-W27]]

## Failure modes

- `Shell substitution failed for pattern` when a command body resolves its own path instead of
  using the literal plugin-root variable — [[failure_slash-command-shell-substitution]].
````

**`part_of:` must name a page that already exists, or one the same run creates.** The exemplar
points at `[[project_claude-plugins]]` to show the shape of the field, and there is no such page
here to point at — copy that line into a real wiki and you get a broken link plus a component
attached to nothing. Write the `project_` page first, or point `part_of:` at the project page that
is already there. The same caution applies to every other `[[link]]` in both exemplars: they
illustrate the form, and each one has to name a real file in the wiki you are actually writing.

Three things to copy from it. Decisions are **dated and newest first**, so a later decision that
contradicts an earlier one is visibly the later one. Each carries its **own** citation rather than
leaning on `sources:`, so a reader checking one claim does not have to read every rollup the page
draws on. And `## Failure modes` is where the inbound link to the failure exemplar lives — writing
that one line is what keeps the failure page from being an orphan.

---

## 10. Anti-example — and the rule it exists for

````markdown
---
name: Memory notes
description: notes about memory
type: component
status: active
last_accessed: 2026-09-08
---
Fixed the consolidation bug in `claude-memory`. See commit `a1b2c3d`.
````

Four defects, each fatal on its own:

1. **No `part_of:`.** `type: component` requires it. `lint` reports the schema error, but the real
   damage is that nothing on the page says which repo it belongs to, and no project page can list
   it — so it is an orphan from the moment it is written.
2. **No `sources:`.** Also required for a component. Nothing here is checkable: there is no rollup
   to trace the claim to, so a later reader cannot establish whether it was ever true, let alone
   whether it still is.
3. **A `description:` matching no search anyone would run.** "notes about memory" is a category
   label. That line is what renders in the index Map, and the Map is how a page gets opened at all;
   nobody hitting a consolidation failure types "notes about memory". `name: Memory notes` is the
   same defect in the same page.
4. **A body whose only content points at a commit git already holds.** `git show a1b2c3d` is
   faster, complete, and cannot go stale. The page contributes no symptom to match on, no mechanism
   to reason from, and nothing transferable to another repo — the three things a page is for.

**If the page adds nothing to `git log`, do not write it.**
