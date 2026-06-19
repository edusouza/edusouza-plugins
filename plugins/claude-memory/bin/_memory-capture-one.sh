#!/usr/bin/env bash
# Shared Tier-1 episodic capture for ONE session (mechanical, no LLM).
# Reused by both memory-capture.sh (SessionEnd, live) and memory-catchup.sh
# (SessionStart, sweeping prior sessions that exited without a capture).
#
# Inputs come from the environment (so a detached child inherits them cleanly):
#   CAP_CWD          raw cwd string (Windows or POSIX); used for git metadata
#   CAP_SID          session id
#   CAP_TRANSCRIPT   raw transcript_path (may be empty)
#   CAP_NO_GIT=1     skip git metadata (set by catch-up: the repo state is "now",
#                    not the state of that past session, so recording it misleads)
#
# Deliberately cheap and side-effect-free: makes ZERO `claude -p` calls, so it can
# never recurse or trigger other lifecycle hooks. Writes atomically (temp + mv) so a
# killed/detached child can never leave a half-written note or partial raw snapshot.
# Always exits 0.
set -uo pipefail

# Never run inside a headless consolidation invocation.
[[ -n "${CLAUDE_MEMORY_CONSOLIDATING:-}" ]] && exit 0

CAP_CWD="${CAP_CWD:-}"
CAP_SID="${CAP_SID:-}"
CAP_TRANSCRIPT="${CAP_TRANSCRIPT:-}"
CAP_NO_GIT="${CAP_NO_GIT:-}"

# Shared path helpers (worktree-aware memory dir resolution + mem_to_posix).
DIR="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin}"
[[ -z "$DIR" || ! -f "$DIR/_memory-paths.sh" ]] && DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_memory-paths.sh
. "$DIR/_memory-paths.sh"

CWD="$(mem_to_posix "$CAP_CWD")"
TRANSCRIPT="$(mem_to_posix "$CAP_TRANSCRIPT")"

# --- derive the user-local memory dir ---
# Derive from cwd (worktree-aware: a linked worktree maps to the main repo's memory dir).
# Fall back to the transcript's own project dir only when no cwd is available — the
# transcript lives at ~/.claude/projects/<hash>/<sid>.jsonl, so its dirname is that dir.
if [[ -n "$CAP_CWD" ]]; then
  PROJ_DIR="$(mem_project_dir "$CAP_CWD")"
elif [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
  PROJ_DIR="$(dirname "$TRANSCRIPT")"
else
  exit 0
fi

MEM="$PROJ_DIR/memory"
# Only capture for projects that have opted in (memory dir already initialized).
[[ -d "$MEM" ]] || exit 0

SESS_DIR="$MEM/episodic/sessions"
mkdir -p "$SESS_DIR/raw" 2>/dev/null || true

# Date the capture by the transcript's own mtime when available, so a catch-up of an
# old session lands in the right ISO week (consolidation buckets by the filename date).
# Fall back to today only when there's no transcript to read a date from.
if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
  DATE="$(date -r "$TRANSCRIPT" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)"
else
  DATE="$(date +%Y-%m-%d)"
fi
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SID8="${CAP_SID:0:8}"; [[ -z "$SID8" ]] && SID8="nosid"
NOTE="$SESS_DIR/$DATE-$SID8.md"

# Already captured (or already consolidated into archive)? Stay idempotent.
if compgen -G "$SESS_DIR/archive/*-$SID8.md" >/dev/null 2>&1; then
  exit 0   # already folded into a weekly rollup; do not resurrect it
fi

# --- git metadata, run inside the session cwd (the repo) ---
BRANCH="unknown"; ISSUE=""; COMMITS=""; DIFFSTAT=""; STATUS=""
if [[ -z "$CAP_NO_GIT" && -n "$CWD" ]] && ( cd "$CWD" 2>/dev/null && git rev-parse --git-dir >/dev/null 2>&1 ); then
  pushd "$CWD" >/dev/null 2>&1 || true
  BRANCH="$(git branch --show-current 2>/dev/null || echo unknown)"
  ISSUE="$(printf '%s' "$BRANCH" | grep -oE '[0-9]+' | head -1 || true)"
  COMMITS="$(git log --oneline -10 2>/dev/null || true)"
  DIFFSTAT="$(git diff --stat 2>/dev/null | tail -50 || true)"
  STATUS="$(git status --short 2>/dev/null | head -50 || true)"
  popd >/dev/null 2>&1 || true
fi

# --- snapshot the raw transcript (transient; consolidation redacts then deletes) ---
# Copy to a temp name first, then atomically rename, so a killed child never leaves a
# partial .jsonl that consolidation would treat as a complete record.
RAW_REF="(no transcript found)"
if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
  RAW_TMP="$SESS_DIR/raw/.$DATE-$SID8.jsonl.tmp.$$"
  if cp "$TRANSCRIPT" "$RAW_TMP" 2>/dev/null && mv -f "$RAW_TMP" "$SESS_DIR/raw/$DATE-$SID8.jsonl" 2>/dev/null; then
    RAW_REF="episodic/sessions/raw/$DATE-$SID8.jsonl"
  else
    rm -f "$RAW_TMP" 2>/dev/null || true
  fi
fi

# --- write the mechanical capture atomically (overwrites this session's own file) ---
NOTE_TMP="$SESS_DIR/.$DATE-$SID8.md.tmp.$$"
{
  echo "# Session capture - $DATE ($SID8)"
  echo
  echo "- captured_at: $TS"
  echo "- session_id: ${CAP_SID:-unknown}"
  echo "- cwd: ${CWD:-unknown}"
  if [[ -n "$CAP_NO_GIT" ]]; then
    echo "- branch: (catch-up capture; git state not recorded - it would reflect 'now', not this session)"
  else
    echo "- branch: $BRANCH${ISSUE:+  (issue #$ISSUE)}"
  fi
  echo "- transcript_path: ${TRANSCRIPT:-unknown}"
  echo "- raw_snapshot: $RAW_REF"
  echo
  if [[ -z "$CAP_NO_GIT" ]]; then
    echo "## Recent commits (git log --oneline -10)"
    echo '```'
    printf '%s\n' "${COMMITS:-(none)}"
    echo '```'
    echo
    echo "## Uncommitted changes (git status --short)"
    echo '```'
    printf '%s\n' "${STATUS:-(clean)}"
    echo '```'
    echo
    echo "## Diff stat (git diff --stat)"
    echo '```'
    printf '%s\n' "${DIFFSTAT:-(none)}"
    echo '```'
    echo
  fi
  echo "> Mechanical capture only. Narrative (decisions/dead-ends/lessons), if written this"
  echo "> session, lives in \`$DATE-narrative.md\`. Both are folded into the weekly rollup and"
  echo "> redacted by the consolidation pass; the raw snapshot is deleted afterward."
} > "$NOTE_TMP" 2>/dev/null && mv -f "$NOTE_TMP" "$NOTE" 2>/dev/null || rm -f "$NOTE_TMP" 2>/dev/null || true

exit 0
