#!/usr/bin/env bash
# Tier-1 episodic capture (mechanical, no LLM). Runs on SessionEnd.
# Records git metadata + a raw transcript snapshot into the project's user-local
# memory dir. Deliberately cheap and side-effect-free: makes ZERO `claude -p`
# calls, so it can never recurse or trigger other lifecycle hooks (e.g. a Stop
# test-coverage guard). Always exits 0 so it can't block session end.
#
# Opt-in: only captures for projects whose memory dir already exists (run
# `/claude-memory:init` once in a project to enable it).
set -uo pipefail

# --- recursion guard: never run inside a headless consolidation invocation ---
[[ -n "${CLAUDE_MEMORY_CONSOLIDATING:-}" ]] && exit 0

PY="$(command -v python 2>/dev/null || command -v python3 2>/dev/null || true)"
[[ -z "$PY" ]] && exit 0   # no python -> skip silently (don't break session end)

PAYLOAD="$(cat 2>/dev/null || true)"

# Parse the SessionEnd hook JSON (cwd / session_id / transcript_path) via python.
PARSED="$(printf '%s' "$PAYLOAD" | "$PY" -c "import sys,json
try:
    d=json.loads(sys.stdin.read() or '{}')
except Exception:
    d={}
for k in ('cwd','session_id','transcript_path'):
    print((str(d.get(k) or '')).replace(chr(10),' ').strip())" 2>/dev/null | tr -d '\r' || true)"

CWD_RAW=""; SESSION_ID=""; TRANSCRIPT_RAW=""
{ IFS= read -r CWD_RAW; IFS= read -r SESSION_ID; IFS= read -r TRANSCRIPT_RAW; } <<< "$PARSED" || true

# Normalize Windows paths (C:\... or C:/...) to POSIX (/c/...) for git-bash use.
to_posix() {
  [[ -z "$1" ]] && return 0
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$1" 2>/dev/null || printf '%s' "$1"
  else
    printf '%s' "$1" | sed -E 's#^([A-Za-z]):#/\L\1#; s#\\#/#g'
  fi
}
CWD="$(to_posix "$CWD_RAW")"
TRANSCRIPT="$(to_posix "$TRANSCRIPT_RAW")"

# --- derive the user-local memory dir ---
# Prefer transcript_path (authoritative: ~/.claude/projects/<hash>/<sid>.jsonl),
# fall back to encoding cwd the same way Claude Code names project dirs.
if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
  PROJ_DIR="$(dirname "$TRANSCRIPT")"
elif [[ -n "$CWD_RAW" ]]; then
  # Claude Code names project dirs by replacing : \ / in the original path with '-'.
  HASH="$(printf '%s' "$CWD_RAW" | sed 's#[:\\/]#-#g')"
  PROJ_DIR="$HOME/.claude/projects/$HASH"
else
  exit 0
fi

MEM="$PROJ_DIR/memory"
# Only capture for projects that have opted in (memory dir already initialized).
[[ -d "$MEM" ]] || exit 0

SESS_DIR="$MEM/episodic/sessions"
mkdir -p "$SESS_DIR/raw" 2>/dev/null || true

DATE="$(date +%Y-%m-%d)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SID8="${SESSION_ID:0:8}"; [[ -z "$SID8" ]] && SID8="nosid"
NOTE="$SESS_DIR/$DATE-$SID8.md"

# --- git metadata, run inside the session cwd (the repo) ---
BRANCH="unknown"; ISSUE=""; COMMITS=""; DIFFSTAT=""; STATUS=""
if [[ -n "$CWD" ]] && ( cd "$CWD" 2>/dev/null && git rev-parse --git-dir >/dev/null 2>&1 ); then
  pushd "$CWD" >/dev/null 2>&1 || true
  BRANCH="$(git branch --show-current 2>/dev/null || echo unknown)"
  ISSUE="$(printf '%s' "$BRANCH" | grep -oE '[0-9]+' | head -1 || true)"
  COMMITS="$(git log --oneline -10 2>/dev/null || true)"
  DIFFSTAT="$(git diff --stat 2>/dev/null | tail -50 || true)"
  STATUS="$(git status --short 2>/dev/null | head -50 || true)"
  popd >/dev/null 2>&1 || true
fi

# --- snapshot the raw transcript (transient; consolidation redacts then deletes) ---
RAW_REF="(no transcript found)"
if [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
  if cp "$TRANSCRIPT" "$SESS_DIR/raw/$DATE-$SID8.jsonl" 2>/dev/null; then
    RAW_REF="episodic/sessions/raw/$DATE-$SID8.jsonl"
  fi
fi

# --- write the mechanical capture (overwrites this session's own file only) ---
{
  echo "# Session capture - $DATE ($SID8)"
  echo
  echo "- captured_at: $TS"
  echo "- session_id: ${SESSION_ID:-unknown}"
  echo "- cwd: ${CWD:-unknown}"
  echo "- branch: $BRANCH${ISSUE:+  (issue #$ISSUE)}"
  echo "- transcript_path: ${TRANSCRIPT:-unknown}"
  echo "- raw_snapshot: $RAW_REF"
  echo
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
  echo "> Mechanical capture only. Narrative (decisions/dead-ends/lessons), if written this"
  echo "> session, lives in \`$DATE-narrative.md\`. Both are folded into the weekly rollup and"
  echo "> redacted by the consolidation pass; the raw snapshot is deleted afterward."
} > "$NOTE" 2>/dev/null || true

exit 0
