#!/usr/bin/env bash
# Weekly consolidation (Tier 2 + Tier 3) for the claude-memory plugin.
# Runs `claude -p` from a CLEAN temp cwd with CLAUDE_MEMORY_CONSOLIDATING=1 exported.
# The env guard is the PRIMARY recursion defense: this plugin's own SessionStart/
# SessionEnd hooks fire for the headless `claude -p` too (plugin hooks are global,
# unaffected by cwd or --settings), and both check that guard and no-op. The clean
# temp cwd additionally keeps any *project* hooks (e.g. a Stop test guard) out of scope.
#
# Usage:
#   memory-consolidate.sh                 # consolidate ALL memory-enabled projects
#   memory-consolidate.sh <MEMORY_DIR>    # consolidate one project's memory dir
set -uo pipefail
export CLAUDE_MEMORY_CONSOLIDATING=1

PY="$(command -v python 2>/dev/null || command -v python3 2>/dev/null || true)"
CLAUDE_BIN="$(command -v claude 2>/dev/null || true)"
if [[ -z "$PY" || -z "$CLAUDE_BIN" ]]; then
  echo "memory-consolidate: need python and claude on PATH (py='$PY' claude='$CLAUDE_BIN')" >&2
  exit 1
fi

# Prompts ship with the plugin. Prefer the plugin root env var (set in hook context);
# fall back to the script's sibling ../prompts when run manually from bin/.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROMPTS="$PLUGIN_ROOT/prompts"
if [[ ! -f "$PROMPTS/tier2-rollup.md" || ! -f "$PROMPTS/tier3-distill.md" ]]; then
  echo "memory-consolidate: prompt files not found under $PROMPTS" >&2; exit 1
fi

TMPCWD="$(mktemp -d)"
trap 'rm -rf "$TMPCWD"' EXIT
run_claude() { ( cd "$TMPCWD" && "$CLAUDE_BIN" -p --settings '{}' "$@" ) 2>/dev/null; }

consolidate_one() {
  local MEM_IN="$1" MEM SESS WEEKLY ARCHIVE TODAY
  if command -v cygpath >/dev/null 2>&1; then MEM="$(cygpath -m "$MEM_IN" 2>/dev/null || echo "$MEM_IN")"; else MEM="$MEM_IN"; fi
  if [[ ! -d "$MEM" ]]; then echo "skip (not found): $MEM" >&2; return 0; fi
  SESS="$MEM/episodic/sessions"; WEEKLY="$MEM/episodic/weekly"; ARCHIVE="$SESS/archive"
  mkdir -p "$WEEKLY" "$ARCHIVE" "$SESS/raw"
  TODAY="$(date +%Y-%m-%d)"
  echo "### project memory: $MEM"

  # -------- Tier 2: weekly rollups --------
  echo "  == Tier 2: weekly rollups =="
  local WEEKS WK FILES INFILE ROLLUP_OUT f raw
  mapfile -t WEEKS < <("$PY" - "$SESS" <<'PY' | tr -d '\r'
import sys,os,glob,datetime,re
sess=sys.argv[1]; weeks=set()
for f in glob.glob(os.path.join(sess,"*.md")):
    m=re.match(r"(\d{4})-(\d{2})-(\d{2})",os.path.basename(f))
    if not m: continue
    iso=datetime.date(int(m[1]),int(m[2]),int(m[3])).isocalendar()
    weeks.add(f"{iso[0]}-W{iso[1]:02d}")
print("\n".join(sorted(weeks)))
PY
)
  if [[ ${#WEEKS[@]} -eq 0 || ( ${#WEEKS[@]} -eq 1 && -z "${WEEKS[0]}" ) ]]; then
    echo "    (no session notes to roll up)"
  else
    for WK in "${WEEKS[@]}"; do
      [[ -z "$WK" ]] && continue
      mapfile -t FILES < <("$PY" - "$SESS" "$WK" <<'PY' | tr -d '\r'
import sys,os,glob,datetime,re
sess,wk=sys.argv[1],sys.argv[2]
for f in sorted(glob.glob(os.path.join(sess,"*.md"))):
    m=re.match(r"(\d{4})-(\d{2})-(\d{2})",os.path.basename(f))
    if not m: continue
    iso=datetime.date(int(m[1]),int(m[2]),int(m[3])).isocalendar()
    if f"{iso[0]}-W{iso[1]:02d}"==wk: print(f)
PY
)
      [[ ${#FILES[@]} -eq 0 ]] && continue
      INFILE="$(mktemp)"
      {
        cat "$PROMPTS/tier2-rollup.md"; echo; echo "================ INPUT MATERIAL FOR $WK ================"
        for f in "${FILES[@]}"; do echo; echo "===== SESSION NOTE: $(basename "$f") ====="; cat "$f"; done
        for f in "${FILES[@]}"; do
          raw="$SESS/raw/$(basename "$f" .md).jsonl"
          [[ -f "$raw" ]] && { echo; echo "===== RAW TRANSCRIPT: $(basename "$raw") ====="; cat "$raw"; }
        done
      } > "$INFILE"
      ROLLUP_OUT="$(run_claude --permission-mode bypassPermissions < "$INFILE")"
      if [[ -n "${ROLLUP_OUT// }" ]]; then
        [[ -f "$WEEKLY/$WK.md" ]] && printf '%s\n' "$ROLLUP_OUT" >> "$WEEKLY/$WK.md" || printf '%s\n' "$ROLLUP_OUT" > "$WEEKLY/$WK.md"
        for f in "${FILES[@]}"; do
          mv "$f" "$ARCHIVE/" 2>/dev/null || true
          rm -f "$SESS/raw/$(basename "$f" .md).jsonl" 2>/dev/null || true
        done
        echo "    wrote $WK.md from ${#FILES[@]} session note(s); archived + raw deleted"
      else
        echo "    WARN: claude produced no rollup for $WK; left session notes untouched" >&2
      fi
      rm -f "$INFILE"
    done
  fi

  # -------- Tier 3: distill abstractions --------
  echo "  == Tier 3: distill abstractions =="
  local T3; T3="$(mktemp)"
  { cat "$PROMPTS/tier3-distill.md"; echo; echo "---"; echo "MEMORY_DIR: $MEM"; echo "TODAY: $TODAY"; } > "$T3"
  run_claude --permission-mode bypassPermissions --add-dir "$MEM" < "$T3" || true
  rm -f "$T3"

  # -------- bookkeeping --------
  "$PY" - "$MEM" "$TODAY" <<'PY'
import sys,os,json
mem,today=sys.argv[1],sys.argv[2]; p=os.path.join(mem,".memory-state.json")
try: s=json.load(open(p))
except Exception: s={"schemaVersion":1}
s["lastWeeklyConsolidation"]=today; s["lastTier3Distill"]=today
json.dump(s,open(p,"w"),indent=2)
PY
}

# -------- target selection --------
declare -a TARGETS=()
if [[ $# -ge 1 ]]; then
  TARGETS=("$@")
else
  for d in "$HOME"/.claude/projects/*/memory; do [[ -d "$d" ]] && TARGETS+=("$d"); done
fi
if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "memory-consolidate: no memory-enabled projects found (run memory-init.sh in a project first)."
  exit 0
fi
for t in "${TARGETS[@]}"; do consolidate_one "$t"; done
echo "consolidation complete ($(date +%Y-%m-%d))."
