#!/usr/bin/env bash
# Test harness for claude-memory. Run from anywhere:
#   bash plugins/claude-memory/test/run-tests.sh
#
# Two kinds of check live here:
#   1. CORRECTNESS - path helpers must map a cwd to exactly one memory dir. Getting
#      this wrong silently writes a project's memory somewhere nobody reads, so the
#      golden tables below are characterization tests: they pin the behavior that
#      shipped, and any refactor must reproduce them byte for byte.
#   2. SPAWN BUDGET - these helpers run in a SessionStart hook, on Windows, where a
#      process spawn costs 0.15-1.1s (python 1.1s, git 0.9s, cygpath 0.5s cold).
#      The cost of this path is dominated by HOW MANY processes it starts, not by
#      what any of them do, so the budget is asserted directly via PATH shims.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO="$(cd "$PLUGIN/../.." && pwd)"
FAILED=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; echo "$2" | sed 's/^/      /'; FAILED=1; }

# --- version parity: plugin.json vs marketplace.json ---
# This repo carries two independent version fields per plugin and nothing else
# validates them; it is the repo's most recurring failure mode.
PJ="$PLUGIN/.claude-plugin/plugin.json"
MJ="$REPO/.claude-plugin/marketplace.json"
PV="$(python -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" "$PJ" 2>&1)"
MV="$(python -c "
import json,sys
m=json.load(open(sys.argv[1]))
e=[p for p in m['plugins'] if p['name']=='claude-memory']
print(e[0]['version'] if e else 'MISSING')" "$MJ" 2>&1)"
if [[ "$PV" == "$MV" ]]; then
  pass "version parity ($PV)"
else
  fail "version parity" "plugin.json=$PV  marketplace.json=$MV"
fi

# shellcheck source=../bin/_memory-paths.sh
. "$PLUGIN/bin/_memory-paths.sh"

check() {
  local name="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then pass "$name"; else fail "$name" "got:  [$got]
want: [$want]"; fi
}

# --- mem_to_posix: Windows/POSIX -> POSIX, drive letter lowercased ---
check "to_posix: backslash windows" "$(mem_to_posix 'C:\Users\eduardo\desenvolvimento\claude-plugins')" "/c/Users/eduardo/desenvolvimento/claude-plugins"
check "to_posix: forward-slash windows" "$(mem_to_posix 'C:/Users/eduardo/x')" "/c/Users/eduardo/x"
check "to_posix: already posix"      "$(mem_to_posix '/c/Users/eduardo/x')" "/c/Users/eduardo/x"
check "to_posix: spaces + drive D"   "$(mem_to_posix 'D:\a b\c')"           "/d/a b/c"
check "to_posix: non-ascii"          "$(mem_to_posix '/c/já/ü')"            "/c/já/ü"
check "to_posix: relative untouched" "$(mem_to_posix 'relative/path')"      "relative/path"
check "to_posix: empty"              "$(mem_to_posix '')"                   ""

# --- mem_hash_dir: path -> $HOME/.claude/projects/<hash>, matching Claude Code ---
P="$HOME/.claude/projects"
check "hash_dir: posix"        "$(mem_hash_dir '/c/Users/eduardo/desenvolvimento/claude-plugins')" "$P/C--Users-eduardo-desenvolvimento-claude-plugins"
check "hash_dir: windows"      "$(mem_hash_dir 'C:\Users\eduardo\x')" "$P/C--Users-eduardo-x"
check "hash_dir: spaces"       "$(mem_hash_dir '/c/a b/c')"           "$P/C--a b-c"
check "hash_dir: drive upper"  "$(mem_hash_dir '/d/Foo')"             "$P/D--Foo"
check "hash_dir: empty"        "$(mem_hash_dir '')"                   ""

# --- the invariant that actually matters: this repo resolves to its real memory dir ---
# A refactor that breaks this sends every capture to a directory nothing reads.
REAL="$P/C--Users-eduardo-desenvolvimento-claude-plugins"
if [[ -d "$REAL" ]]; then
  check "project_dir: resolves to the live memory dir" "$(mem_project_dir 'C:\Users\eduardo\desenvolvimento\claude-plugins')" "$REAL"
else
  echo "SKIP: project_dir live-dir check (no memory dir on this machine)"
fi

# --- worktree redirection: a linked worktree shares the MAIN repo's memory ---
# Losing this silently fragments memory into a per-worktree dir that nothing reads.
WT="$(git -C "$REPO" worktree list 2>/dev/null | awk 'NR>1{print $1; exit}')"
if [[ -n "$WT" && -d "$WT" ]]; then
  check "worktree: linked worktree redirects to main root" "$(mem_resolve_main_root "$WT")" "$(mem_to_posix "$REPO")"
  check "worktree: linked worktree shares main memory dir"  "$(mem_project_dir "$WT")"      "$(mem_project_dir "$REPO")"
else
  echo "SKIP: worktree checks (no linked worktree on this machine)"
fi
check "worktree: subdir of main resolves to main" "$(mem_project_dir "$REPO/plugins")" "$(mem_project_dir "$REPO")"
check "worktree: repo root resolves to itself" "$(mem_resolve_main_root "$REPO")" "$(mem_to_posix "$REPO")"
check "worktree: non-git path echoes unchanged" "$(mem_resolve_main_root '/c/Windows/Temp')" "/c/Windows/Temp"

# --- spawn budget ---
# Shim git/cygpath/sed onto the front of PATH, each logging one line per call before
# delegating to the real binary, then resolve a path and count the log. This asserts
# the property the hook actually cares about (how many processes start) rather than a
# wall-clock number that would be flaky on a fast machine.
SHIM="$(mktemp -d)"; trap 'rm -rf "$SHIM"' EXIT
LOG="$SHIM/calls.log"; : > "$LOG"
for bin in git cygpath sed; do
  real="$(command -v "$bin" 2>/dev/null)" || continue
  [[ -z "$real" ]] && continue
  cat > "$SHIM/$bin" <<EOF
#!/usr/bin/env bash
echo "$bin" >> "$LOG"
exec "$real" "\$@"
EOF
  chmod +x "$SHIM/$bin"
done

# The shimmed run must still return the RIGHT path, not just a small count — a shim
# that perturbs the code under test could otherwise report a low number for a run that
# did nothing. Asserted below alongside the count.
# Sets the globals SHIMMED_OUT and SPAWN_COUNT. Deliberately NOT called via $(...) —
# that would run it in a subshell and discard SHIMMED_OUT.
SHIMMED_OUT=""; SPAWN_COUNT=0
count_spawns() {
  : > "$LOG"
  SHIMMED_OUT="$( PATH="$SHIM:$PATH"; . "$PLUGIN/bin/_memory-paths.sh"; mem_project_dir "$REPO" 2>/dev/null )"
  SPAWN_COUNT="$(wc -l < "$LOG" | tr -d ' ')"
}

# mem_project_dir needs git only to answer "is this a linked worktree?", which
# `git rev-parse` reports for all three questions in a single invocation. Path
# string munging is pure bash. Budget: 1 process, total.
BUDGET=1
count_spawns
GOT="$SPAWN_COUNT"
check "spawn budget: shimmed run still resolves correctly" "$SHIMMED_OUT" "$(mem_project_dir "$REPO")"
if [[ "$GOT" -le "$BUDGET" ]]; then
  pass "spawn budget: mem_project_dir uses $GOT process(es) (budget $BUDGET)"
else
  fail "spawn budget: mem_project_dir" "spawned $GOT processes, budget is $BUDGET
called: $(sort "$LOG" | uniq -c | tr '\n' ' ')
On Windows each spawn costs 0.15-1.1s in a SessionStart hook."
fi

# --- behavioural: the catch-up sweep captures exactly the right sessions ---
# Runs the real hook against a synthetic project (see sandbox-catchup.sh for the
# fixture) and pins the capture set, covering every skip branch: too-recent, self,
# already-captured, already-consolidated.
SB1="$(mktemp -d)"; trap 'rm -rf "$SHIM" "$SB1" "$SB2"' EXIT
CATCHUP_GOT="$(bash "$HERE/sandbox-catchup.sh" "$PLUGIN/bin" "$SB1" 2>/dev/null)"
read -r -d '' CATCHUP_WANT <<'EOF'
--- captures ---
aaaaaaaa.md
bbbbbbbb.md
eeeeeeee.md
--- raw snapshots ---
aaaaaaaa.jsonl
bbbbbbbb.jsonl
--- stray files (marker leaks) ---
EOF
check "catchup: captures only uncaptured, idle, non-self sessions" "$CATCHUP_GOT" "$CATCHUP_WANT"

# --- behavioural: the SessionEnd capture note keeps its shape (git metadata included) ---
SB2="$(mktemp -d)"
CAPTURE_GOT="$(bash "$HERE/sandbox-capture.sh" "$PLUGIN/bin" "$SB2" "$REPO" 2>/dev/null)"
if [[ "$CAPTURE_GOT" == *"# Session capture - 2026-02-03 (abcd1234)"* \
   && "$CAPTURE_GOT" == *"- captured_at: <NORMALIZED>"* \
   && "$CAPTURE_GOT" == *"## Recent commits (git log --oneline -10)"* \
   && "$CAPTURE_GOT" == *"raw_snapshot: episodic/sessions/raw/2026-02-03-abcd1234.jsonl"* ]]; then
  pass "capture: SessionEnd note carries date, git metadata and raw snapshot"
else
  fail "capture: SessionEnd note" "$CAPTURE_GOT"
fi

echo
if [[ "$FAILED" -eq 0 ]]; then echo "All tests passed."; else echo "Some tests FAILED."; fi
exit "$FAILED"
