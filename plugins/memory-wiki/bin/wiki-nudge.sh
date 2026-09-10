#!/usr/bin/env bash
# SessionStart reminder that weekly rollups are sitting un-ingested — the write half's alarm
# clock, and the whole of it.
#
# An ingest that nothing reminds you to run is an ingest that happens once. This mirrors
# claude-memory's consolidation-overdue reminder exactly: no background process, no token
# spend, no state of its own. Three lines when there is something to do, and complete silence
# otherwise — which is the state it is in on almost every session start, and the reason it can
# afford to run on all of them.
#
# IT DOES NOT WORK OUT WHAT IS PENDING. `wiki-ingest-plan.sh --pending-only` does, and it is
# the only implementation of that rule anywhere (a rollup counts as ingested when wiki/log.md
# carries a `- Sources:` line naming it; wiki-log.sh is the only writer of those lines). A
# second implementation here would be a second answer to the only question this hook knows how
# to ask, and the two would drift in the worst possible direction: the skill reporting the work
# done while the nudge keeps demanding it, or the nudge going quiet on a week nobody ingested.
#
# Registered as its own SessionStart entry alongside wiki-inject.sh rather than folded into it.
# The two have unrelated outputs and unrelated failure modes, and a bug in the pending
# calculation must not be able to suppress the index injection. claude-memory registers its two
# SessionStart hooks the same way.
#
# PERFORMANCE. This blocks *every* session start, and on this machine a process spawn costs
# ~430 ms measured. Budgets, measured, pinned by test/run-tests.sh with a PATH shim that logs
# every call:
#   2  when Claude Code exported CLAUDE_PROJECT_DIR — one `git rev-parse` inside
#      wiki_project_dir, and one `bash` for the child that owns the pending calculation.
#   3  without it (non-Claude hosts): those two, plus the python that parses the payload JSON.
#   0  when either opt-out is set — the two guards are the first statements in the file.
# Everything else is a bash builtin: the pending list is split with a here-string rather than a
# `tr`, and joined by parameter expansion rather than a `paste`.
#
# The child is handed the memory dir EXPLICITLY, and must never be called argument-less. That
# was measured: with an explicit MEMORY_DIR the pending path costs ~0.155 s, argument-less
# ~0.746 s, because wiki_project_dir resolves the project a second time inside the child. This
# hook already has to resolve the memory dir for its own purposes, so paying for it twice is
# pure waste on the one path where waste is least affordable.
#
# Silent, exit 0, always. Every one of these is a normal state rather than a fault: the
# recursion guard, the opt-out, no python, an unparseable or absent cwd, a cwd naming a
# directory that does not exist, a project with no memory dir, a project with no wiki, and a
# wiki with nothing pending. A hook that errors visibly at session start is worse than one that
# no-ops.
#
# Reports only; writes nothing, anywhere.
set -uo pipefail

# --- guards: before any work, so an opted-out session start spawns nothing ---
# CLAUDE_MEMORY_CONSOLIDATING matches claude-memory's recursion guard: a headless consolidation
# invocation is the thing that CREATES the rollups this hook counts, and must not be nagged
# about them mid-write.
[[ -n "${CLAUDE_MEMORY_CONSOLIDATING:-}" ]] && exit 0
[[ -n "${MEMORY_WIKI_NO_NUDGE:-}" ]] && exit 0

# Byte semantics for the [[:space:]] class used when sifting the child's output. Nothing here
# sorts — the child already emits its list in LC_ALL=C order — but that class is locale-defined
# and this pins what it matches.
export LC_ALL=C

# Locate our own bin/. Claude Code sets CLAUDE_PLUGIN_ROOT; the fallback is pure parameter
# expansion rather than the usual `$(cd "$(dirname ...)" && pwd)` because that idiom costs a
# `dirname` process and a subshell for a value only used to find two sibling files.
DIR="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin}"
if [[ -z "$DIR" || ! -f "$DIR/_wiki-paths.sh" ]]; then
  SELF="${BASH_SOURCE[0]}"
  DIR="${SELF%/*}"
  [[ "$DIR" == "$SELF" ]] && DIR="."
fi
# shellcheck source=_wiki-paths.sh
. "$DIR/_wiki-paths.sh" 2>/dev/null
# The single guard, deliberately: `.` returns the status of the *last statement* in the file it
# sourced, so `|| exit 0` on the source line would be at the mercy of whatever that happens to
# be. Whether the resolver is actually usable is the question, and this is the question.
declare -f wiki_project_dir >/dev/null 2>&1 || exit 0

# The one thing this script cannot do without and cannot substitute for. A stale plugin cache
# holding a bin/ from before Task 4 is a documented failure mode in this repo, not a
# hypothetical, and `bash` on a missing file prints its own complaint to stderr.
PLAN="$DIR/wiki-ingest-plan.sh"
[[ -f "$PLAN" ]] || exit 0

# --- the payload ---
# `read -d ''` consumes the whole stream with a builtin; `$(cat)` would cost a process. The tty
# guard keeps a hand-run of this script from hanging on a terminal that will never send
# anything — a no-op is the right answer there too.
#
# stdin is drained here even on the path that turns out not to need it: leaving the payload
# unread would make Claude Code's writer take an EPIPE, and draining it costs nothing.
PAYLOAD=""
if [[ ! -t 0 ]]; then
  IFS= read -r -d '' PAYLOAD || true
fi

# Prefer the cwd Claude Code already exported, and only pay for python to parse the payload
# when it is absent (non-Claude hosts). This ordering is not a preference: it is parity with
# wiki-inject.sh, which took it from claude-memory's memory-inject.sh. If the two SessionStart
# hooks disagreed about which signal wins, a nested session would land the wiki index and the
# ingest nudge in different projects — and the nudge would name weeks from one project while
# the index described another.
CWD="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$CWD" ]]; then
  [[ -z "$PAYLOAD" ]] && exit 0

  PYBIN=""
  if command -v python >/dev/null 2>&1; then
    PYBIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYBIN="python3"
  else
    exit 0
  fi

  # Every malformed shape lands on the empty string and therefore on a silent exit: not JSON,
  # JSON that is not an object, an object with no `cwd`, a null `cwd`. A here-string rather
  # than a pipe, so this costs one process and not one process plus a forked writer.
  CWD="$("$PYBIN" -c '
import sys, json
try:
    d = json.loads(sys.stdin.read())
    v = d.get("cwd") if isinstance(d, dict) else None
    if isinstance(v, str) and v:
        sys.stdout.write(v)
except Exception:
    pass' <<< "$PAYLOAD" 2>/dev/null || true)"
  CWD="${CWD%$'\r'}"
fi
[[ -z "$CWD" ]] && exit 0

# Worktree-aware, and resolved exactly once: a linked worktree shares the MAIN repo's memory
# dir. Same shared resolver every other memory-wiki entry point uses — a faster private copy
# here is precisely how a project's memory and its wiki end up in different directories.
MEMDIR="$(wiki_project_dir "$CWD")/memory"

# A project that never scaffolded a wiki has nothing pending by definition, and this is the
# common case across a machine's projects. The child would answer the same way, silently, but
# it would cost a process to say so; a directory test costs nothing. Note what this is NOT: it
# is not a pending calculation, and nothing below it re-implements one. Testing for
# episodic/weekly here instead would be — that directory's location is the child's business,
# and a nudge that disagreed with it about where rollups live would go quiet on a real backlog.
[[ -d "$MEMDIR/wiki" ]] || exit 0

# --- what is pending ---
# The whole of the calculation, in one child, handed the memory dir explicitly (see the header).
# stderr is discarded rather than shown: `--pending-only` puts nothing but diagnostics there,
# and a diagnostic at session start is the visible error this hook must never produce. stdout
# carries one bare rollup name per line and NOTHING AT ALL when there is nothing pending.
PENDING_RAW="$(bash "$PLAN" "$MEMDIR" --pending-only 2>/dev/null)"; PLAN_RC=$?
# A non-zero child cannot be trusted to have finished its list, and a truncated list is a nudge
# that names three weeks out of five. It exits 0 on every path it defines, so this is only ever
# reached when something outside those paths went wrong — no bash on PATH, a killed process —
# and none of those is worth reporting at session start either.
(( PLAN_RC == 0 )) || exit 0
[[ -z "$PENDING_RAW" ]] && exit 0

# Split the list without ever letting the shell word-split or glob it: rollup names come off a
# filesystem, and an unquoted split would run pathname expansion over each one.
#
# The blank-line skip is not decoration. `printf '%s\n'` with no arguments still emits one
# newline, so a producer that forgot to guard that call would hand back a single empty line —
# which reads as a pending rollup named "" and nags the user forever about a week that does not
# exist and no ingest can clear. Task 4 closed that on the producing side and pinned it with a
# byte-count check; this closes it on the consuming side, because the blast radius is here.
NAMES=()
# `line` is initialised before the loop, not left to the first `read`: the `|| [[ -n "$line" ]]`
# clause that catches an unterminated final line would trip `set -u` if it were ever reached
# with the variable unassigned, and a `set -u` abort here means two bash errors printed at
# session start. wiki-inject.sh's region reader carries the same initialisation for the same
# reason. It is unreachable today — the here-string below is never empty — and that is exactly
# the kind of guarantee that a later edit quietly removes.
line=""
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  # Whitespace-only is empty for this purpose; a name is a filename stem or it is nothing.
  [[ -z "${line//[[:space:]]/}" ]] && continue
  NAMES+=("$line")
done <<< "$PENDING_RAW"
(( ${#NAMES[@]} )) || exit 0

# The count and the list are derived from the same array, so they cannot disagree. A nudge
# whose number contradicted its own names is one the user stops believing, and after that it is
# just noise at the top of every session.
LIST=""
for n in "${NAMES[@]}"; do LIST="${LIST:+$LIST, }$n"; done
NOUN="weekly rollups"
(( ${#NAMES[@]} == 1 )) && NOUN="weekly rollup"

# Three lines, no more: a header the model can see, what is outstanding and which weeks, and
# the single command that clears it. Deliberately no leading blank line — wiki-inject.sh
# terminates its own output with a newline, so this starts on a fresh line either way, and a
# fourth line here would be session-start context nobody agreed to spend. The list is bounded
# in practice by one name per un-ingested week.
printf '## Memory wiki - ingest pending\n%s %s not yet ingested: %s\nRun:  /memory-wiki:ingest\n' \
  "${#NAMES[@]}" "$NOUN" "$LIST"

exit 0
