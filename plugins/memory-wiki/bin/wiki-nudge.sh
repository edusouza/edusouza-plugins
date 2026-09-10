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
# IT DOES NOT DEFINE WHAT IS PENDING. wiki_pending in _wiki-pending.sh does, and it is the only
# implementation of that rule anywhere (a rollup counts as ingested when wiki/log.md carries a
# `- Sources:` line naming it; wiki-log.sh is the only writer of those lines). wiki-ingest-plan.sh
# reports from the same function. A second implementation here would drift in the worst
# possible direction: the skill reporting the work done while the nudge keeps demanding it, or
# the nudge going quiet on a week nobody ingested.
#
# Registered as its own SessionStart entry alongside wiki-inject.sh rather than folded into it.
# The two have unrelated outputs and unrelated failure modes, and a bug in the pending
# calculation must not be able to suppress the index injection. claude-memory registers its two
# SessionStart hooks the same way.
#
# PERFORMANCE. This blocks *every* session start, and on this machine a process spawn costs
# ~430 ms measured. Budgets, measured, pinned by test/run-tests.sh with a PATH shim that logs
# every call:
#   1  when Claude Code exported CLAUDE_PROJECT_DIR — one `git rev-parse` inside
#      wiki_project_dir, and nothing else.
#   2  without it (non-Claude hosts): that git, plus the python that parses the payload JSON.
#   0  when either opt-out is set — the two guards are the first statements in the file.
# The pending calculation is sourced rather than run as a child script, so it costs no process,
# and the list is joined by parameter expansion rather than a `paste`.
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

# Locate our own bin/. Claude Code sets CLAUDE_PLUGIN_ROOT; the fallback is pure parameter
# expansion rather than the usual `$(cd "$(dirname ...)" && pwd)` because that idiom costs a
# `dirname` process and a subshell for a value only used to find two sibling files.
DIR="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin}"
if [[ -z "$DIR" || ! -f "$DIR/_wiki-hook.sh" ]]; then
  SELF="${BASH_SOURCE[0]}"
  DIR="${SELF%/*}"
  [[ "$DIR" == "$SELF" ]] && DIR="."
fi
# shellcheck source=_wiki-hook.sh
. "$DIR/_wiki-hook.sh" 2>/dev/null
# shellcheck source=_wiki-pending.sh
. "$DIR/_wiki-pending.sh" 2>/dev/null
# The single guard, deliberately: `.` returns the status of the *last statement* in the file it
# sourced, so `|| exit 0` on a source line would be at the mercy of whatever that happens to
# be. Whether the helpers are actually usable is the question, and this is the question.
declare -f wiki_hook_memdir wiki_project_dir wiki_pending >/dev/null 2>&1 || exit 0

wiki_hook_memdir || exit 0

# A project that never scaffolded a wiki has nothing pending by definition, and this is the
# common case across a machine's projects. Note what this is NOT: a pending calculation.
# Testing for episodic/weekly here instead would be — that directory's location is
# wiki_pending's business, and a nudge that disagreed with it about where rollups live would go
# quiet on a real backlog.
[[ -d "$MEMDIR/wiki" ]] || exit 0

wiki_pending "$MEMDIR"
(( ${#PENDING[@]} )) || exit 0

# The count and the list are derived from the same array, so they cannot disagree. A nudge
# whose number contradicted its own names is one the user stops believing, and after that it is
# just noise at the top of every session.
LIST=""
for n in "${PENDING[@]}"; do LIST="${LIST:+$LIST, }$n"; done
NOUN="weekly rollups"
(( ${#PENDING[@]} == 1 )) && NOUN="weekly rollup"

# Three lines, no more: a header the model can see, what is outstanding and which weeks, and
# the single command that clears it. Deliberately no leading blank line — wiki-inject.sh
# terminates its own output with a newline, so this starts on a fresh line either way, and a
# fourth line here would be session-start context nobody agreed to spend. The list is bounded
# in practice by one name per un-ingested week.
printf '## Memory wiki - ingest pending\n%s %s not yet ingested: %s\nRun:  /memory-wiki:ingest\n' \
  "${#PENDING[@]}" "$NOUN" "$LIST"

exit 0
