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

- **Tier 1 — recent sessions.** A `SessionEnd` hook (`memory-capture.sh`) records git metadata + a
  raw transcript snapshot into a per-project, user-local memory dir. No LLM, no recursion, instant.
- **Tier 2 — last week.** The `/claude-memory:consolidate` command folds the week's captures into one
  redacted narrative rollup, then archives the captures and deletes the raw snapshots.
- **Tier 3 — abstractions.** The same consolidation distills durable *decision heuristics* into
  `concept_*.md`, indexed in `MEMORY.md`, which Claude Code auto-loads every session. Stale concepts
  decay to `dormant`.
- **Recall.** A `SessionStart` hook (`memory-inject.sh`) injects the last 1–2 sessions + the latest
  weekly rollup, and reminds you when consolidation is overdue. The `/claude-memory:memory` skill
  does on-demand search and ad-hoc concept promotion.

The two things *you* trigger — enabling a project and running the weekly consolidation — are
**slash commands** (`/claude-memory:init`, `/claude-memory:consolidate`), so there are no scripts to
put on `PATH`. The two lifecycle hooks remain shell scripts because the harness fires them
automatically on session start/end.

Memory is **per-project**, **opt-in**, and **local-only** (lives under `~/.claude/projects/<hash>/memory/`,
never committed to a repo).

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

Memory captures only for projects you opt in. From the project, run the slash command:

```
/claude-memory:init
```

(Pass a path to enable a different project: `/claude-memory:init /path/to/proj`.)

## Weekly consolidation

There is no background daemon. When you start a session and consolidation is overdue (>7 days with
pending captures), the SessionStart hook prints a one-line reminder. Run:

```
/claude-memory:consolidate            # the current project (default)
/claude-memory:consolidate all        # every memory-enabled project
/claude-memory:consolidate <memdir>   # one specific memory dir
```

The command runs the bundled `memory-consolidate.sh` in a **background subagent** (keeping the heavy
output out of your main session). The script is deterministic — it buckets captures by ISO week and
calls `claude -p` headlessly per week to produce the rollups and distillation — so it spends tokens.
Run it when prompted.

## Requirements

- `python` (3.x) and `claude` on `PATH`. `python` is used by the lifecycle hooks and the
  consolidation script's bucketing; `claude` is invoked headlessly by the consolidation script.
- A POSIX shell (git-bash on Windows) — the lifecycle hooks and the `init`/`consolidate` scripts run
  in bash. They handle Windows path quirks (`cygpath`, CRLF). The slash commands invoke these scripts
  by absolute path via the plugin root, so nothing needs to be on `PATH`.

## Safety notes

- Raw transcript snapshots are **transient**: consolidation redacts them into the durable rollup and
  then deletes them. Durable memory (rollups, concepts) is produced with explicit redaction of
  secrets/PII/confidential data.
- Memory injected at session start is sent to the model API — but that is ≤ the exposure that already
  occurred when the original transcript was created.
- The consolidation's headless `claude -p` is guarded by `CLAUDE_MEMORY_CONSOLIDATING=1`, which makes
  this plugin's own SessionStart/SessionEnd hooks no-op during consolidation (no recursion).

## License

MIT
