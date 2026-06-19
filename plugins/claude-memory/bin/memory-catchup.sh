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
NOW="$(date +%s 2>/dev/null || echo 0)"

# Synchronous sweep, all output suppressed (must not leak into injected context).
# Newest-first so a backlog still gets the most relevant recent sessions before the cap.
{
  count=0
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    [[ "$count" -ge "$CAP_MAX" ]] && break
    sid="$(basename "$t" .jsonl)"
    [[ -z "$sid" || "$sid" == "$CUR_SID" ]] && continue
    # Skip the in-flight session even if its id wasn't supplied: a transcript still
    # being written has a very recent mtime. Caught on a later start once it's idle.
    mtime="$(stat -c %Y "$t" 2>/dev/null || echo 0)"
    [[ "$NOW" -gt 0 && "$mtime" -gt 0 && $((NOW - mtime)) -lt "$MIN_AGE" ]] && continue
    sid8="${sid:0:8}"
    captured=0
    for n in "$SESS_DIR"/*-"$sid8".md "$SESS_DIR"/archive/*-"$sid8".md; do
      [[ -e "$n" ]] && { captured=1; break; }
    done
    [[ "$captured" -eq 1 ]] && continue
    CAP_CWD="$CWD_RAW" CAP_SID="$sid" CAP_TRANSCRIPT="$t" CAP_NO_GIT=1 bash "$CORE"
    count=$((count + 1))
  done < <(ls -t "$TXDIR"/*.jsonl 2>/dev/null)
} >/dev/null 2>&1

exit 0
