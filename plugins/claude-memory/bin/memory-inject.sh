#!/usr/bin/env bash
# Tier-1 + Tier-2 recall injection. Runs on SessionStart; prints memory context to
# stdout (which Claude Code adds to the session). Tier-3 (MEMORY.md + concept_*/
# project_* files) auto-loads natively and is NOT repeated here. Episodic layers are
# injected here ONLY (never indexed in MEMORY.md) to avoid context bloat.
#
# No-ops for projects without an initialized memory dir (opt-in). Always exits 0.
set -uo pipefail

# --- recursion guard: do not inject into a headless consolidation invocation ---
[[ -n "${CLAUDE_MEMORY_CONSOLIDATING:-}" ]] && exit 0

PYBIN="$(command -v python 2>/dev/null || command -v python3 2>/dev/null || true)"
[[ -z "$PYBIN" ]] && exit 0

PAYLOAD="$(cat 2>/dev/null || true)"

CWD_RAW="$(printf '%s' "$PAYLOAD" | "$PYBIN" -c "import sys,json
try: print((json.loads(sys.stdin.read() or '{}').get('cwd') or ''))
except Exception: print('')" 2>/dev/null | tr -d '\r' || true)"
[[ -z "$CWD_RAW" ]] && exit 0

HASH="$(printf '%s' "$CWD_RAW" | sed 's#[:\\/]#-#g')"
MEMDIR="$HOME/.claude/projects/$HASH/memory"
[[ -d "$MEMDIR" ]] || exit 0   # project not memory-enabled -> nothing to inject

{
  SDIR="$MEMDIR/episodic/sessions"
  if compgen -G "$SDIR/*.md" >/dev/null 2>&1; then
    echo ""
    echo "## Memory - recent sessions (Tier 1)"
    for f in $(ls -t "$SDIR"/*.md 2>/dev/null | head -2); do
      echo ""; echo "### $(basename "$f")"; cat "$f"
    done
  fi
  if compgen -G "$MEMDIR/episodic/weekly/*.md" >/dev/null 2>&1; then
    LASTWK="$(ls -t "$MEMDIR/episodic/weekly"/*.md 2>/dev/null | head -1)"
    if [[ -n "$LASTWK" ]]; then
      echo ""; echo "## Memory - last week (Tier 2)"
      echo "### $(basename "$LASTWK")"
      head -200 "$LASTWK"
    fi
  fi

  # Consolidation-overdue reminder: nags only when captures await rollup AND the last
  # weekly consolidation was >=7 days ago (or never). No background process / token spend.
  OVERDUE=""; PENDING_CNT=0
  read -r OVERDUE PENDING_CNT < <("$PYBIN" - "$MEMDIR" <<'PY' | tr -d '\r'
import sys,os,json,glob,datetime
mem=sys.argv[1]
pending=len(glob.glob(os.path.join(mem,"episodic","sessions","*.md")))
try: last=json.load(open(os.path.join(mem,".memory-state.json"))).get("lastWeeklyConsolidation")
except Exception: last=None
overdue="no"
if pending>0:
    if not last: overdue="yes"
    else:
        try:
            if (datetime.date.today()-datetime.date.fromisoformat(last)).days>=7: overdue="yes"
        except Exception: overdue="yes"
print(overdue, pending)
PY
) || true
  if [[ "$OVERDUE" == "yes" ]]; then
    echo ""
    echo "## Memory - consolidation overdue"
    echo "$PENDING_CNT session capture(s) await rollup; last weekly consolidation was >=7 days ago (or never)."
    echo "Run:  memory-consolidate.sh   (or use the /claude-memory:memory skill)."
  fi
} || true

exit 0
