---
name: memory
description: Search, recall, and curate the three-tier cross-session developer memory (Tier 1 = recent sessions, Tier 2 = weekly rollups, Tier 3 = durable concepts/heuristics). Use when the user asks "what did we do before / last time", wants to recall a past decision or solution, when a durable insight from the current session should be promoted to permanent memory, or to enable memory for a project. Also defines the end-of-session narrative-write ritual.
---

# Three-tier developer memory

A brain-like memory that persists across Claude Code sessions. Episodic detail (sessions → weekly)
decays into semantic abstractions (concepts) over time.

## Where the files live (user-local, per project)

```
~/.claude/projects/<project-hash>/memory/
  MEMORY.md                       # Tier-3 index (auto-loaded each session)
  concept_<slug>.md               # Tier 3: durable heuristics / solution patterns
  project_<slug>.md               # Tier 3: durable project facts
  feedback_<slug>.md              # user corrections (never contradict these)
  episodic/sessions/<date>-<sid>.md      # Tier 1: per-session captures (mechanical)
  episodic/sessions/<date>-narrative.md  # Tier 1: in-session narrative (this ritual)
  episodic/weekly/<YYYY>-Www.md          # Tier 2: weekly rollups
```

`<project-hash>` is the project path with `:` `\` `/` replaced by `-`. The session-start memory
context reports the absolute memory dir to use (a `## Memory - dir for this project` line) — prefer
that path for all reads/writes. If you must derive it yourself, hash the current working directory;
**but inside a git worktree the hash resolves to the main repo root**, so worktree sessions share the
main repo's memory rather than creating a separate per-worktree dir. Use the reported path to avoid
getting this wrong.

## Enabling a project (opt-in)

Memory is captured ONLY for projects that have been initialized. To enable the current project, run
the slash command `/claude-memory:init`. It creates the memory dir and seeds it; from then on the
SessionEnd capture and SessionStart recall hooks are active for that project.

## Mode 1 — Recall / search

Search with Grep + Read (no external search dependency required):

1. `Grep` the query terms (case-insensitive, `-i`) across the memory dir, prioritizing
   `concept_*.md` and `project_*.md` (durable), then `episodic/weekly/*.md`, then
   `episodic/sessions/` and `episodic/sessions/archive/`.
2. `Read` the top matches and synthesize a short answer. Cite which memory file each point came from.
3. If a `concept_*` file answered the query, bump its `last_accessed:` to today (Edit) — this
   "reheats" it so the weekly decay pass keeps it active.
4. If nothing matches, say so plainly. Do not fabricate recall.

## Mode 2 — Promote a durable insight to Tier 3 (ad-hoc, mid-session)

When the current session produces a genuine, reusable **decision heuristic / solution pattern /
gotcha** that future sessions should know, don't wait for the weekly consolidation — write it now:

1. Create `<memory>/concept_<snake_slug>.md` using the FLAT schema:
   ```
   ---
   name: <Human Title>
   description: <one-line recall summary>
   type: concept
   status: active
   last_accessed: <today YYYY-MM-DD>
   ---
   <the abstraction — decision guidance, NOT a code location>

   **Why:** <what pain it prevents>
   **How to apply:** <when/how a future session should act on it>
   ```
2. Add a one-line entry to `<memory>/MEMORY.md`:
   `- [<name>](concept_<slug>.md) — <description>`
3. **Bar for promotion:** it must be judgment that helps *decide*, transferable beyond one task,
   and not trivially grep-able from the codebase. If it's just "file X does Y", it's NOT a concept.

## Mode 3 — End-of-session narrative ritual

The capture hooks record git metadata + a raw transcript snapshot automatically, but the *reasoning*
(decisions, dead-ends, lessons) is most cheaply captured by you, now, with full context. A `Stop`
hook (`memory-narrative-nudge.sh`) prompts you to do this once per substantial session — when nudged,
just follow it. You can also do it proactively: for any session with notable substance, before
wrapping up write/append to `<memory>/episodic/sessions/<today>-narrative.md`:

```
# Narrative - <today>

## What I worked on
## Decisions & why
## Dead-ends / gotchas
## Lessons (candidate abstractions)
## Open threads / next step
```

Keep it tight (a screenful). This file is injected at the next session start and folded into the
weekly rollup. Multiple sessions in one day: append under a new `---` separator.

## Redaction (applies to everything you write here)

Durable memory gets re-read and re-sent to the model API. **Redact** secrets (API keys, tokens,
passwords), personal data (real names, emails, account IDs), and any confidential customer/business
data. Keep the engineering substance; replace identifiers with neutral placeholders. When unsure,
redact.

## Weekly consolidation (not this skill)

Tier-2 + Tier-3 batch consolidation is run by the `/claude-memory:consolidate` command, which
executes the bundled `memory-consolidate.sh` (deterministic bash; headless `claude -p` per week) in a
background subagent. With no argument it consolidates the current project; pass a memory dir to target
one, or `all` for every memory-enabled project. This skill is for *interactive* recall and ad-hoc
curation only.
