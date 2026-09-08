#!/usr/bin/env bash
# Tier-1 catch-up sweep. Runs on SessionStart (alongside memory-inject.sh).
#
# This is the RELIABLE capture path. SessionEnd can't be trusted on exit (`/exit`
# skips it, Ctrl+C cancels it, async/detached work in it is killed — issues #35892/
# #32712/#41577, and nohup/disown doesn't survive on Windows/cygwin), but the
# transcript .jsonl files persist on disk regardless of how a session ended, and
# SessionStart fires reliably and waits for its hook. So on each start we sweep the
# project's transcript dir and capture any past session that has no capture note yet —
# folding in whatever the best-effort SessionEnd hook missed.
#
# Runs SYNCHRONOUSLY (a detached child would be reaped when this hook returns) but is
# cheap: file copies + small note writes, no git, no `claude -p`. Bounded per start so a
# huge backlog can't stall startup; the remainder drains on subsequent starts. Prints
# NOTHING to stdout (SessionStart stdout becomes injected context). Always exits 0.
#
# PERFORMANCE: the per-transcript work is all bash builtins. It used to spawn
# `basename` + `stat` for EVERY transcript in the project (2N processes at 0.15-1.1s
# each on Windows); the age test is now one `touch`ed marker compared with `-nt`, and
# the id comes from parameter expansion. See test/run-tests.sh for the spawn budget.
#
# Tuning: CLAUDE_MEMORY_CATCHUP_MAX (default 25) = max sessions captured per start.
#         CLAUDE_MEMORY_CATCHUP_MIN_AGE (default 120s) = don't capture a transcript
#         modified more recently than this — it's almost certainly the in-flight current
#         session (belt-and-suspenders for the session_id skip below). A session that
#         just ended is caught on the next start instead; no loss.
set -uo pipefail

# Never run inside a headless consolidation invocation.
[[ -n "${CLAUDE_MEMORY_CONSOLIDATING:-}" ]] && exit 0

DIR="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin}"
[[ -z "$DIR" || ! -f "$DIR/_memory-capture-one.sh" ]] && DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="$DIR/_memory-capture-one.sh"
[[ -f "$CORE" ]] || exit 0
# shellcheck source=_memory-paths.sh
. "$DIR/_memory-paths.sh"

PY="$(command -v python 2>/dev/null || command -v python3 2>/dev/null || true)"
[[ -z "$PY" ]] && exit 0

PAYLOAD="$(cat 2>/dev/null || true)"
# Both fields are needed and neither is in the environment: the sweep is keyed on the
# session's OWN cwd (transcripts live in that cwd's project dir, not the main repo's),
# and the current session id is what keeps this hook from capturing itself.
PARSED="$(printf '%s' "$PAYLOAD" | "$PY" -c "import sys,json
try:
    d=json.loads(sys.stdin.read() or '{}')
except Exception:
    d={}
for k in ('cwd','session_id'):
    print((str(d.get(k) or '')).replace(chr(10),' ').strip())" 2>/dev/null | tr -d '\r' || true)"

CWD_RAW=""; CUR_SID=""
{ IFS= read -r CWD_RAW; IFS= read -r CUR_SID; } <<< "$PARSED" || true
[[ -z "$CWD_RAW" ]] && exit 0

# Transcripts are written by Claude Code into the cwd's own project dir (raw hash), but the
# memory dir is worktree-aware (the main repo for a linked worktree). Keep the two separate:
# sweep transcripts from TXDIR, but check/write captures under the (possibly main) MEM.
TXDIR="$(mem_hash_dir "$CWD_RAW")"
PROJ_DIR="$(mem_project_dir "$CWD_RAW")"
MEM="$PROJ_DIR/memory"
[[ -d "$MEM" ]] || exit 0   # project not memory-enabled -> nothing to sweep

SESS_DIR="$MEM/episodic/sessions"
CAP_MAX="${CLAUDE_MEMORY_CATCHUP_MAX:-25}"
case "$CAP_MAX" in (*[!0-9]*|'') CAP_MAX=25;; esac
MIN_AGE="${CLAUDE_MEMORY_CATCHUP_MIN_AGE:-120}"
case "$MIN_AGE" in (*[!0-9]*|'') MIN_AGE=120;; esac

# One marker stamped at (now - MIN_AGE) replaces a `stat` per transcript: `-nt` then
# answers "modified more recently than the cutoff?" as a builtin. If the marker can't
# be created we drop the age test rather than skip everything, matching the old
# behavior when `stat` failed (don't skip -> the session_id check still guards us).
MARKER=""
if [[ -n "${EPOCHSECONDS:-}" ]]; then
  _m="$SESS_DIR/.catchup-cutoff.$$"
  if touch -d "@$(( EPOCHSECONDS - MIN_AGE ))" "$_m" 2>/dev/null; then MARKER="$_m"; fi
fi

# Synchronous sweep, all output suppressed (must not leak into injected context).
# Newest-first so a backlog still gets the most relevant recent sessions before the cap.
{
  count=0
  mapfile -t TRANSCRIPTS < <(ls -t "$TXDIR"/*.jsonl 2>/dev/null)
  for t in "${TRANSCRIPTS[@]}"; do
    [[ -z "$t" ]] && continue
    [[ "$count" -ge "$CAP_MAX" ]] && break
    sid="${t##*/}"; sid="${sid%.jsonl}"
    [[ -z "$sid" || "$sid" == "$CUR_SID" ]] && continue
    # Skip the in-flight session even if its id wasn't supplied: a transcript still
    # being written has a very recent mtime. Caught on a later start once it's idle.
    [[ -n "$MARKER" && "$t" -nt "$MARKER" ]] && continue
    sid8="${sid:0:8}"
    captured=0
    for n in "$SESS_DIR"/*-"$sid8".md "$SESS_DIR"/archive/*-"$sid8".md; do
      [[ -e "$n" ]] && { captured=1; break; }
    done
    [[ "$captured" -eq 1 ]] && continue
    CAP_CWD="$CWD_RAW" CAP_SID="$sid" CAP_TRANSCRIPT="$t" CAP_NO_GIT=1 bash "$CORE"
    count=$((count + 1))
  done
} >/dev/null 2>&1

[[ -n "$MARKER" ]] && rm -f "$MARKER" 2>/dev/null

exit 0
