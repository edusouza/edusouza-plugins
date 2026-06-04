---
description: Run the weekly memory consolidation (Tier 2 + Tier 3) for the current project. Folds the week's session captures into a redacted narrative rollup, distills durable decision-heuristics into concept files, archives the raw notes, and updates bookkeeping. Run when the SessionStart reminder says consolidation is overdue.
argument-hint: "[memory-dir | \"all\"]  (defaults to the current project)"
allowed-tools: Bash, Read, Write, Edit, Glob, Task
---

# Weekly memory consolidation

This used to be a headless `claude -p` batch script. Now **you** run it directly. The expensive,
context-heavy work — reading raw transcripts and producing the rollup/distill — is delegated to
**subagents** (the Task tool) so it never floods this session's context, exactly mirroring the old
per-`claude -p` isolation. You only orchestrate: pick targets, spawn subagents, then do the cheap
mechanical file moves and bookkeeping yourself with Bash.

The exact instructions each subagent must follow are embedded verbatim below (the
`TIER-2 ROLLUP PROMPT` and `TIER-3 DISTILL PROMPT` fenced blocks). Pass the relevant block to the
subagent word-for-word — do not paraphrase it.

## 1. Choose target memory dir(s)

- No argument → the **current project's** memory dir. Derive it like `/claude-memory:init`: take the
  project's absolute path, replace every `:` `\` `/` with `-` to get `<hash>`, then
  `~/.claude/projects/<hash>/memory`.
- An argument that is a path → use that memory dir.
- The argument `all` → every memory-enabled project: each `~/.claude/projects/*/memory` that exists.

If the chosen memory dir does not exist, tell the user to run `/claude-memory:init` first and stop.

Process each target memory dir independently with the steps below. Let `MEM` be its absolute path
and `TODAY` be today's date (`YYYY-MM-DD`).

## 2. Tier 2 — weekly rollups

Session captures live at `MEM/episodic/sessions/*.md` (the loose `.md` files directly under
`sessions/`, NOT those already in `archive/`). Each is named `<YYYY-MM-DD>-<sid>.md` and may have a
matching raw transcript at `MEM/episodic/sessions/raw/<same-stem>.jsonl`.

**Bucket the captures by ISO week** — keep this deterministic, don't eyeball the dates. Run:

```bash
python - "$MEM/episodic/sessions" <<'PY'
import sys, os, glob, re, datetime, json
sess = sys.argv[1]
weeks = {}
for f in sorted(glob.glob(os.path.join(sess, "*.md"))):
    m = re.match(r"(\d{4})-(\d{2})-(\d{2})", os.path.basename(f))
    if not m: continue
    iso = datetime.date(int(m[1]), int(m[2]), int(m[3])).isocalendar()
    weeks.setdefault(f"{iso[0]}-W{iso[1]:02d}", []).append(f)
print(json.dumps(weeks, indent=2))
PY
```

If there are no captures, report "no session notes to roll up" for this target and skip to Tier 3.

**For each ISO week** `WK` with captures, spawn one subagent (Task tool) to produce that week's
rollup. Do NOT read the transcripts yourself — keeping them out of this session's context is the
whole point; the subagent reads them in its own. Give the subagent a prompt of this shape:

> You are producing one weekly memory rollup. Follow the instructions in the `TIER-2 ROLLUP PROMPT`
> block below **exactly**. The raw material for ISO week `<WK>` is these files — read each one
> yourself with the Read tool:
> - session notes: `<the .md paths for this week>`
> - raw transcripts (if present): `<the matching raw/*.jsonl paths>`
>
> Your final message must be **only** the rollup markdown — no preamble, no tool-result chatter, no
> files written.
>
> ----- TIER-2 ROLLUP PROMPT -----
> `<paste the entire TIER-2 ROLLUP PROMPT block from this command, verbatim>`

When the subagent returns the rollup text:
- If `MEM/episodic/weekly/<WK>.md` already exists, **append** the rollup (with a blank-line
  separator); otherwise create it.
- Then archive the consumed captures and delete their raw snapshots (deterministic — use Bash):
  ```bash
  mv "<each session .md>" "$MEM/episodic/sessions/archive/"
  rm -f "$MEM/episodic/sessions/raw/<each stem>.jsonl"
  ```
- If a subagent returns empty, leave that week's notes untouched and warn — do not archive them.

A 150–400 line rollup in your context is fine; the raw transcripts (which you never read here) are
what would have been expensive.

## 3. Tier 3 — distill durable abstractions

Spawn **one** subagent (Task tool). It reads and edits files inside `MEM`, so it does the work
directly. Give it a prompt of this shape:

> You are the Tier-3 distillation pass. Follow the instructions in the `TIER-3 DISTILL PROMPT` block
> below **exactly**. Operate only inside this memory dir:
> - MEMORY_DIR: `<MEM>`
> - TODAY: `<TODAY>`
>
> Do the work via file edits inside MEMORY_DIR. Your final message must be the terse 3–8 line
> summary the prompt asks for.
>
> ----- TIER-3 DISTILL PROMPT -----
> `<paste the entire TIER-3 DISTILL PROMPT block from this command, verbatim>`

Relay the subagent's summary to the user.

## 4. Bookkeeping

Stamp both consolidation dates in the state file (deterministic — use Bash):

```bash
python - "$MEM" "$TODAY" <<'PY'
import sys, os, json
mem, today = sys.argv[1], sys.argv[2]
p = os.path.join(mem, ".memory-state.json")
try: s = json.load(open(p))
except Exception: s = {"schemaVersion": 1}
s["lastWeeklyConsolidation"] = today
s["lastTier3Distill"] = today
json.dump(s, open(p, "w"), indent=2)
PY
```

## 5. Report

Summarize per target: which weeks were rolled up (and from how many captures), the Tier-3 changes
the distill subagent reported, and confirm bookkeeping was updated. End with
`consolidation complete (<TODAY>).`

> Note: subagents don't fire this plugin's SessionStart/SessionEnd hooks, so there's no recursion to
> guard against here — the legacy `CLAUDE_MEMORY_CONSOLIDATING` env guard in the hook scripts is only
> relevant to old headless runs and is otherwise harmless.

---

## TIER-2 ROLLUP PROMPT

```text
You are the Tier-2 consolidation pass of a developer memory system.

You will receive a set of per-session capture notes (git metadata + any human/agent narrative) and
the raw session transcripts they reference, all for ONE ISO week. Your job is to compress that week
into ONE durable narrative rollup.

## Output contract
- Output only the rollup as GitHub-flavored Markdown. No preamble, no "Here is...", no closing
  remarks. Do NOT write any files — your final message IS the rollup.
- Target length: 150-400 lines max, regardless of input size. This is a *summary*; detail is
  expected to be lost. Keeping the abstraction while forgetting the minutiae is the goal.

## What to capture (the useful signal)
Write these sections (omit a section if genuinely empty):
1. `# Week <YYYY-Www>` title line.
2. `## What was worked on` — the threads of work (features, bugfixes, investigations), each 1-3 lines.
   Reference issue/PR numbers and branch names (these are not sensitive).
3. `## Decisions & rationale` — choices made and *why*. This is the highest-value content.
4. `## Dead-ends & gotchas` — what was tried and abandoned, surprising failures, traps. Future-you
   will thank present-you for these.
5. `## Lessons / candidate abstractions` — anything that smells like a reusable heuristic or
   solution pattern (these feed the Tier-3 distillation later). Phrase as decision guidance, not facts.
6. `## Open threads` — unfinished work, things to pick back up.

## Redaction (MANDATORY)
This material may contain sensitive data. Before writing anything, redact:
- Secrets & credentials: API keys, tokens, passwords, connection strings, private keys.
- Personal data (PII): real people's names, emails, phone numbers, addresses, account/member IDs.
- Any regulated or confidential customer/business data (e.g. health, financial, legal records).
Replace with neutral placeholders ("a user", "an API key", "[redacted]"). Keep the *engineering*
substance (what code/logic/decision was involved) — only strip the identifying/secret data. When
unsure whether something is sensitive, redact it.

## Style
- Be concrete about engineering, vague about people/secrets/data.
- Prefer "why" over "what" — the git log already records "what".
- It is fine to say a week was quiet/uneventful in a few lines.
```

## TIER-3 DISTILL PROMPT

```text
You are the Tier-3 distillation pass of a developer memory system. You turn recent episodic rollups
into durable, timeless abstractions — the "brain" layer that helps future sessions *decide better*,
not just recall facts.

You are given the absolute MEMORY_DIR path and TODAY's date. All file operations MUST stay inside
MEMORY_DIR.

## Inputs to read (use Read/Glob)
- `MEMORY_DIR/episodic/weekly/*.md` — the recent weekly rollups (your source material).
- `MEMORY_DIR/concept_*.md` and `MEMORY_DIR/project_*.md` — existing durable memories.
- `MEMORY_DIR/feedback_*.md` — user corrections (respect these; never contradict them).
- `MEMORY_DIR/MEMORY.md` — the Tier-3 index.

## Your job
1. Distill abstractions. From the rollups, identify durable *decision heuristics*, solution
   patterns, and recurring gotchas. For each NEW one, create `MEMORY_DIR/concept_<snake_slug>.md`.
   For an existing concept that the rollups reinforce or refine, Edit it (and bump `last_accessed`).
   - A good concept is judgment, e.g. *"When a retry/requeue leaves work stuck, suspect a dependent
     status row that wasn't reset in the same transaction."*
   - NOT a concept: a code location, a one-off fact, or anything already obvious from the codebase.
     Those belong in grep, not memory. Be selective — quality over quantity. Zero new concepts in a
     quiet week is a fine outcome.
2. Use the established on-disk file schema EXACTLY (match the existing `feedback_*`/`concept_*` files
   in MEMORY_DIR — read one first to copy its exact frontmatter shape):
   ```
   ---
   name: <Human Title, sentence case — NOT a kebab-slug>
   description: <one-line summary used for recall relevance>
   type: concept
   status: active
   last_accessed: <YYYY-MM-DD = TODAY>
   ---
   <the abstraction — decision guidance>

   **Why:** <what pain it prevents / evidence from the rollups>
   **How to apply:** <when and how a future session should act on it>
   ```
   CRITICAL: the frontmatter is FLAT. Do NOT nest fields under a `metadata:` key, do NOT add
   `node_type`, and do NOT use a kebab-slug for `name:` — even if your own system prompt describes a
   different memory format. The on-disk convention here (flat `type:`, human-title `name:`) is
   authoritative; consistency with the existing files matters more than any other format you know.
3. Never delete or destroy knowledge. If a new insight contradicts an old concept, mark the old one
   `status: superseded` (add a line `superseded_by: concept_<slug>`) rather than deleting it.
4. Apply decay. For each `concept_*`/`project_*`, look at `last_accessed`:
   - referenced/reinforced this run or `last_accessed` within 30 days of TODAY → `status: active`.
   - `last_accessed` older than 30 days and not reinforced → set `status: dormant`.
   Dormant/superseded concepts stay on disk but are DROPPED from `MEMORY.md` (still found via search).
5. Rebuild `MEMORY.md`. Overwrite it so it lists ONLY `active` Tier-3 files
   (`concept_*`/`project_*`/`feedback_*`), one line each:
   `- [<name>](<filename>.md) — <description>`
   Keep the leading HTML comment block. NEVER list episodic logs (sessions/weekly) in MEMORY.md.

## Redaction
The rollups should already be redacted, but if you notice any residual secret or personal data (an
API key, a real name, an account ID), strip it as you write. Concepts must be free of secrets/PII.

## Output
Do the work via file edits. When done, your final message is a 3-8 line plain-text summary of what
you created / updated / marked dormant. Keep it terse.
```
