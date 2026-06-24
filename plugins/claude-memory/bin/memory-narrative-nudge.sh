#!/usr/bin/env bash
# Narrative nudge. Runs on Stop (when Claude finishes a turn naturally — Stop hooks do
# NOT fire on user interrupt, so this only ever lands at a real pause).
#
# The LLM narrative ritual (skill Mode 3) cannot run at exit — SessionEnd can't invoke
# the model. Stop is the only lifecycle point where we can ask the model to do one more
# bounded turn. So: once per session, if the session has real substance and no narrative
# exists yet, emit `{"decision":"block","reason":...}` to have Claude write it, then stop.
#
# Loop-safe by three independent guards: stop_hook_active (set true on the continuation
# turn we triggered), a per-session marker file, and the narrative file's existence.
# Cheap heuristic for "substance": assistant-turn count in the transcript.
#
# Escape hatches:
#   CLAUDE_MEMORY_NO_NUDGE=1            disable entirely
#   CLAUDE_MEMORY_NUDGE_MIN_TURNS=<n>  substance threshold (default 6)
set -uo pipefail

[[ -n "${CLAUDE_MEMORY_CONSOLIDATING:-}" ]] && exit 0   # not during headless consolidation
[[ -n "${CLAUDE_MEMORY_NO_NUDGE:-}" ]] && exit 0        # user opted out

PY="$(command -v python 2>/dev/null || command -v python3 2>/dev/null || true)"
[[ -z "$PY" ]] && exit 0

# Shared path helpers (worktree-aware memory dir resolution).
DIR="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin}"
[[ -z "$DIR" || ! -f "$DIR/_memory-paths.sh" ]] && DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_memory-paths.sh
. "$DIR/_memory-paths.sh"

PAYLOAD="$(cat 2>/dev/null || true)"

# Parse scalar fields + count assistant turns in one python pass.
PARSED="$(printf '%s' "$PAYLOAD" | "$PY" -c "import sys,json
try:
    d=json.loads(sys.stdin.read() or '{}')
except Exception:
    d={}
def g(k): return str(d.get(k) or '').replace(chr(10),' ').strip()
print(g('cwd'))
print(g('session_id'))
print(g('transcript_path'))
print('1' if d.get('stop_hook_active') else '0')
turns=0
tp=d.get('transcript_path') or ''
try:
    with open(tp,'r',encoding='utf-8',errors='ignore') as fh:
        for line in fh:
            line=line.strip()
            if not line: continue
            try: e=json.loads(line)
            except Exception: continue
            if e.get('type')=='assistant' or e.get('role')=='assistant' or (isinstance(e.get('message'),dict) and e['message'].get('role')=='assistant'):
                turns+=1
except Exception:
    turns=0
print(turns)" 2>/dev/null | tr -d '\r' || true)"

CWD_RAW=""; SID=""; TRANSCRIPT_RAW=""; STOP_ACTIVE="0"; TURNS="0"
{ IFS= read -r CWD_RAW; IFS= read -r SID; IFS= read -r TRANSCRIPT_RAW; IFS= read -r STOP_ACTIVE; IFS= read -r TURNS; } <<< "$PARSED" || true

# We triggered this continuation — let Claude stop now (primary loop guard).
[[ "$STOP_ACTIVE" == "1" ]] && exit 0
[[ -z "$CWD_RAW" ]] && exit 0

# Worktree-aware: a linked worktree resolves to the main repo's memory dir.
MEM="$(mem_project_dir "$CWD_RAW")/memory"
[[ -d "$MEM" ]] || exit 0   # project not memory-enabled

SID8="${SID:0:8}"; [[ -z "$SID8" ]] && SID8="nosid"
SESS_DIR="$MEM/episodic/sessions"
mkdir -p "$SESS_DIR" 2>/dev/null || true
MARKER="$SESS_DIR/.nudged-$SID8"
[[ -e "$MARKER" ]] && exit 0   # already nudged this session

TODAY="$(date +%Y-%m-%d)"
NARR="$SESS_DIR/$TODAY-narrative.md"
if [[ -f "$NARR" ]]; then
  : > "$MARKER" 2>/dev/null || true   # narrative already written; don't nudge
  exit 0
fi

# Substance gate: skip short/trivial sessions (and don't burn the once-per-session
# nudge on them — leave the marker unset so a later, larger turn can still trigger).
MIN_TURNS="${CLAUDE_MEMORY_NUDGE_MIN_TURNS:-6}"
case "$TURNS" in (*[!0-9]*|'') TURNS=0;; esac
[[ "$TURNS" -lt "$MIN_TURNS" ]] && exit 0

# Burn the nudge now (before emitting) so a crash/interrupt can't re-trigger it.
: > "$MARKER" 2>/dev/null || true

# Present the narrative path in a form Claude's tools accept on this OS.
NARR_DISPLAY="$NARR"
if command -v cygpath >/dev/null 2>&1; then
  NARR_DISPLAY="$(cygpath -m "$NARR" 2>/dev/null || echo "$NARR")"
fi

# Emit the block decision as pure JSON (python json.dumps escapes the path safely).
REASON="Before this session ends: it had substantial work but no end-of-session narrative yet. Per the /claude-memory:memory skill (Mode 3), write a concise narrative to ${NARR_DISPLAY} now — sections: What I worked on / Decisions & why / Dead-ends & gotchas / Lessons (candidate abstractions) / Open threads & next step. Redact secrets and personal data. Keep it to a screenful. If the file exists, append under a new '---' separator. Then stop — do not start new work."

"$PY" -c "import json,sys
print(json.dumps({'decision':'block','reason':sys.argv[1]}))" "$REASON" 2>/dev/null || exit 0

exit 0
