# claude-memory

A **three-tier, brain-like cross-session memory** for Claude Code. Stop re-explaining context every
session: Claude remembers what it did last session, what happened last week (summarized), and the
durable heuristics it has learned.

```
   DETAIL ▲                         weekly consolidation ("sleep")
          │                         ─────────────────────────▶
 TIER 1   │  SESSION CAPTURE   week rollover    WEEKLY ROLLUP     TIER 2
"last     │  (SessionEnd hook, ───────────────▶ (LLM summary,
 session" │   mechanical)                        redacted)
          │      EPISODIC (decays → summarized → pruned)
          │ ───────────────────────────────────────────────────────────
          │      SEMANTIC (timeless, distilled)        distill durable
 TIER 3   │                          MEMORY.md + concept_*.md  (auto-loads)
"brain"   ▼                          (decision heuristics, gotchas)
```

## How it works

- **Tier 1 — recent sessions.** Each session is captured (git metadata + a raw transcript snapshot)
  into a per-project, user-local memory dir. No LLM, no recursion, instant. Capture happens on two
  hooks for reliability (see below): a best-effort `SessionEnd` (`memory-capture.sh`) and a
  guaranteed `SessionStart` catch-up sweep (`memory-catchup.sh`).
- **Tier 2 — last week.** `memory-consolidate.sh` folds the week's captures into one redacted
  narrative rollup, then archives the captures and deletes the raw snapshots.
- **Tier 3 — abstractions.** The same consolidation distills durable *decision heuristics* into
  `concept_*.md`, indexed in `MEMORY.md`, which Claude Code auto-loads every session. Stale concepts
  decay to `dormant`.
- **Recall.** A `SessionStart` hook (`memory-inject.sh`) injects the last 1–2 sessions + the latest
  weekly rollup, and reminds you when consolidation is overdue. The `/claude-memory:memory` skill
  does on-demand search and ad-hoc concept promotion.
- **Narrative nudge.** A `Stop` hook (`memory-narrative-nudge.sh`) fires once per substantial session
  to have Claude write the end-of-session narrative (the *reasoning*: decisions, dead-ends, lessons).
  This can't happen at exit — `SessionEnd` can't invoke the model — so it rides the `Stop` event.

Memory is **per-project**, **opt-in**, and **local-only** (lives under `~/.claude/projects/<hash>/memory/`,
never committed to a repo).

## Why capture runs on *two* hooks

`SessionEnd` is unreliable on exit in current Claude Code: `/exit` doesn't fire it at all, Ctrl+C
cancels it mid-run, and async/detached work in it is killed before completing (anthropics/claude-code
issues [#35892](https://github.com/anthropics/claude-code/issues/35892),
[#32712](https://github.com/anthropics/claude-code/issues/32712),
[#41577](https://github.com/anthropics/claude-code/issues/41577); detaching via `nohup`/`disown`
does **not** survive on Windows/cygwin either — the child is reaped with the hook).

The fix doesn't depend on `SessionEnd` firing. The transcript `.jsonl` persists on disk no matter how
a session ends, and `SessionStart` *does* fire reliably — so on each start the **catch-up sweep**
re-captures any prior session that has no note yet. `SessionEnd` is kept only as a synchronous
best-effort fast-path (atomic temp-then-rename writes mean a mid-run kill leaves no partial file).
Net: every session is captured at the latest by the next session's start. The LLM narrative ritual
likewise moved off exit onto the `Stop` nudge.

## Tuning (environment variables)

| Variable | Default | Effect |
| --- | --- | --- |
| `CLAUDE_MEMORY_NO_NUDGE` | unset | Set to disable the end-of-session narrative nudge entirely. |
| `CLAUDE_MEMORY_NUDGE_MIN_TURNS` | `6` | Assistant-turn threshold below which a session is too trivial to nudge. |
| `CLAUDE_MEMORY_CATCHUP_MAX` | `25` | Max sessions the catch-up sweep captures per start (the rest drain on later starts). |
| `CLAUDE_MEMORY_CATCHUP_MIN_AGE` | `120` | Seconds; transcripts modified more recently are skipped as the in-flight session. |

## Install (local development)

```bash
claude --plugin-dir /path/to/claude-memory
```

Or via a marketplace (add `.claude-plugin/marketplace.json` to a git repo, then):

```bash
/plugin marketplace add <owner/repo>
/plugin install claude-memory@<marketplace>
```

## Enable for a project

Memory captures only for projects you opt in. From the project root:

```bash
memory-init.sh
```

(That script is on `PATH` once the plugin is enabled.)

## Weekly consolidation

There is no background daemon. When you start a session and consolidation is overdue (>7 days with
pending captures), the SessionStart hook prints a one-line reminder. Run:

```bash
memory-consolidate.sh            # all enabled projects
memory-consolidate.sh <memdir>   # one project
```

This calls `claude -p` headlessly, so it spends tokens — run it when prompted, or wire it to your OS
scheduler if you prefer true cron.

## Requirements

- `python` (3.x) and `claude` on `PATH`.
- A POSIX shell (git-bash on Windows). The scripts handle Windows path quirks (`cygpath`, CRLF).

## Safety notes

- Raw transcript snapshots are **transient**: consolidation redacts them into the durable rollup and
  then deletes them. Durable memory (rollups, concepts) is produced with explicit redaction of
  secrets/PII/confidential data.
- Memory injected at session start is sent to the model API — but that is ≤ the exposure that already
  occurred when the original transcript was created.
- The consolidation's headless `claude -p` is guarded by `CLAUDE_MEMORY_CONSOLIDATING=1`, which makes
  this plugin's own hooks no-op during consolidation (no recursion).

## License

MIT
