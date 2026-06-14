#!/usr/bin/env bash
# Tier-1 episodic capture. Runs on SessionEnd.
#
# SessionEnd is unreliable on exit in current Claude Code: `/exit` doesn't fire it at
# all, Ctrl+C cancels it mid-run, and async/detached work in it is killed before
# completing (see anthropics/claude-code issues #35892, #32712, #41577). Detaching
# (nohup/disown) does NOT survive on Windows/cygwin — the child is reaped with the hook.
# So this hook just runs the capture SYNCHRONOUSLY as a best-effort fast-path for the
# clean-exit case. Writes are atomic (temp + mv in the core), so even a mid-run kill
# leaves no partial file. The actual GUARANTEE is the SessionStart catch-up sweep
# (memory-catchup.sh), which re-captures anything this hook missed from on-disk data.
#
# Makes ZERO `claude -p` calls. Always exits 0 so it can't block session end.
set -uo pipefail

# Never run inside a headless consolidation invocation.
[[ -n "${CLAUDE_MEMORY_CONSOLIDATING:-}" ]] && exit 0

DIR="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin}"
[[ -z "$DIR" || ! -f "$DIR/_memory-capture-one.sh" ]] && DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="$DIR/_memory-capture-one.sh"
[[ -f "$CORE" ]] || exit 0

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

CAP_CWD=""; CAP_SID=""; CAP_TRANSCRIPT=""
{ IFS= read -r CAP_CWD; IFS= read -r CAP_SID; IFS= read -r CAP_TRANSCRIPT; } <<< "$PARSED" || true
export CAP_CWD CAP_SID CAP_TRANSCRIPT

# Synchronous, fast (no git-LLM, no detach). Suppress output; never fail the hook.
bash "$CORE" >/dev/null 2>&1 || true

exit 0
