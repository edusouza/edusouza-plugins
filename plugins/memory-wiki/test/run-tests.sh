#!/usr/bin/env bash
# Golden-file test harness for memory-wiki. Run from anywhere:
#   bash plugins/memory-wiki/test/run-tests.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO="$(cd "$PLUGIN/../.." && pwd)"
FAILED=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; echo "$2" | sed 's/^/      /'; FAILED=1; }

# --- version parity: plugin.json vs marketplace.json ---
# This repo carries two independent version fields per plugin and nothing validates
# them, which is its single most recurring failure mode. Guard it from day one.
PJ="$PLUGIN/.claude-plugin/plugin.json"
MJ="$REPO/.claude-plugin/marketplace.json"
PV="$(python -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" "$PJ" 2>&1)"
MV="$(python -c "
import json,sys
m=json.load(open(sys.argv[1]))
e=[p for p in m['plugins'] if p['name']=='memory-wiki']
print(e[0]['version'] if e else 'MISSING')" "$MJ" 2>&1)"

if [[ "$PV" == "$MV" ]]; then
  pass "version parity ($PV)"
else
  fail "version parity" "plugin.json=$PV  marketplace.json=$MV"
fi

# --- golden-file fixtures ---
run_fixture() {
  local name="$1"; shift
  local out exp
  exp="$HERE/expected/$name.txt"
  out="$(bash "$PLUGIN/bin/wiki-lint.sh" "$HERE/fixtures/$name/wiki" "$@" 2>&1)"
  if [[ "$out" == "$(cat "$exp" 2>/dev/null)" ]]; then
    pass "fixture: $name"
  else
    fail "fixture: $name" "$(diff <(cat "$exp" 2>/dev/null) <(echo "$out") || true)"
  fi
}

run_fixture clean
run_fixture broken
run_fixture atlas --sources "$HERE/fixtures/atlas/sources" --atlas "$HERE/fixtures/atlas/atlas"
run_fixture orphans
run_fixture no-frontmatter

# --- path helpers ---
# shellcheck source=/dev/null
. "$PLUGIN/bin/_wiki-paths.sh" 2>/dev/null
if declare -f wiki_project_dir >/dev/null 2>&1; then
  got="$(wiki_project_dir "$REPO")"
  want="$HOME/.claude/projects/$(printf '%s' "$(cygpath -w "$REPO" 2>/dev/null || printf '%s' "$REPO")" | sed 's#[:\\/]#-#g')"
  if [[ "$got" == "$want" ]]; then
    pass "paths: repo root resolves to its project dir"
  else
    fail "paths: repo root resolves to its project dir" "got:  $got
want: $want"
  fi
  # The vendored copy must agree with claude-memory's original wherever both exist, or
  # a project's memory and its wiki would resolve to different directories.
  CM="$(ls -d "$HOME"/.claude/plugins/cache/*/claude-memory/*/bin/_memory-paths.sh 2>/dev/null | tail -1)"
  if [[ -n "$CM" && -f "$CM" ]]; then
    cm_got="$(bash -c '. "$1"; mem_project_dir "$2"' _ "$CM" "$REPO" 2>/dev/null)"
    if [[ "$got" == "$cm_got" ]]; then
      pass "paths: agrees with claude-memory's resolver"
    else
      fail "paths: agrees with claude-memory's resolver" "memory-wiki: $got
claude-memory: $cm_got"
    fi
  else
    pass "paths: claude-memory not installed, cross-check skipped"
  fi
else
  fail "paths: _wiki-paths.sh" "wiki_project_dir not defined"
fi

# --- init: creates the scaffold, and is idempotent ---
TMPPROJ="$(mktemp -d)"
( cd "$TMPPROJ" && git init -q . ) >/dev/null 2>&1
MEMD="$(wiki_project_dir "$TMPPROJ")/memory"
mkdir -p "$MEMD"
out1="$(bash "$PLUGIN/bin/wiki-init.sh" "$TMPPROJ" 2>&1)"
out2="$(bash "$PLUGIN/bin/wiki-init.sh" "$TMPPROJ" 2>&1)"
if [[ -f "$MEMD/wiki/log.md" && -f "$MEMD/wiki/README.md" && -d "$MEMD/wiki/inbox" ]] \
   && grep -q 'already initialized' <<< "$out2"; then
  pass "init: scaffolds and is idempotent"
else
  fail "init: scaffolds and is idempotent" "run1: $out1
run2: $out2"
fi
# Refuses to scaffold where claude-memory was never initialized, rather than creating
# a stray memory dir of its own.
NOMEM="$(mktemp -d)"
out3="$(bash "$PLUGIN/bin/wiki-init.sh" "$NOMEM" 2>&1)"; rc3=$?
if [[ $rc3 -ne 0 ]] && grep -q 'no memory dir' <<< "$out3"; then
  pass "init: refuses a project with no memory dir"
else
  fail "init: refuses a project with no memory dir" "rc=$rc3
$out3"
fi
rm -rf "$TMPPROJ" "$NOMEM" "$(wiki_project_dir "$TMPPROJ")"

# --- PowerShell parity: the .ps1 must match the .sh byte for byte ---
# The bash script's stdout is the specification; the twin exists so the agent side can
# invoke the linter without going through an unreliable Bash layer on Windows.
# The two scripts take the same options under different spellings (--sources vs
# -Sources), so each invocation is built separately. Passing one form to both would
# make bash swallow "-Sources" as a positional and clobber the wiki dir.
parity() {
  local name="$1" src="${2:-}" atl="${3:-}"
  local sh_args=() ps_args=() sh_out ps_out
  [[ -n "$src" ]] && { sh_args+=(--sources "$src"); ps_args+=(-Sources "$src"); }
  [[ -n "$atl" ]] && { sh_args+=(--atlas "$atl");   ps_args+=(-Atlas "$atl");   }
  # CR is stripped from both sides: pwsh on Windows always terminates lines with CRLF
  # while bash emits LF. That is a host convention, not a difference in the report, and
  # the contract under test is the content.
  sh_out="$(bash "$PLUGIN/bin/wiki-lint.sh" "$HERE/fixtures/$name/wiki" ${sh_args[@]+"${sh_args[@]}"} 2>&1 | tr -d '\r')"
  ps_out="$(pwsh -NoProfile -File "$PLUGIN/bin/wiki-lint.ps1" -WikiDir "$HERE/fixtures/$name/wiki" ${ps_args[@]+"${ps_args[@]}"} 2>&1 | tr -d '\r')"
  if [[ "$sh_out" == "$ps_out" ]]; then
    pass "parity: $name"
  else
    fail "parity: $name" "$(diff <(echo "$sh_out") <(echo "$ps_out") || true)"
  fi
}

if command -v pwsh >/dev/null 2>&1; then
  parity clean
  parity broken
  parity orphans
  parity no-frontmatter
  parity atlas "$HERE/fixtures/atlas/sources" "$HERE/fixtures/atlas/atlas"
else
  pass "parity: skipped (pwsh not on PATH)"
fi

# --- shipped surface: every declared file exists ---
missing=""
for p in README.md skills/lint/SKILL.md commands/lint.md commands/init.md \
         bin/wiki-lint.sh bin/wiki-lint.ps1 bin/wiki-init.sh bin/_wiki-paths.sh \
         assets/wiki-README.md; do
  [[ -f "$PLUGIN/$p" ]] || missing="$missing $p"
done
if [[ -z "$missing" ]]; then
  pass "surface: all declared files present"
else
  fail "surface: all declared files present" "missing:$missing"
fi

# --- smoke: run against a real memory dir if one exists ---
# Asserts shape only. Counts change as memory grows and must never be pinned here.
REAL="$(ls -d "$HOME"/.claude/projects/*/memory 2>/dev/null | head -1)"
if [[ -n "$REAL" && -d "$REAL" ]]; then
  out="$(bash "$PLUGIN/bin/wiki-lint.sh" "$REAL" --sources "$REAL/episodic/weekly" 2>&1)"
  rc=$?
  if [[ $rc -eq 0 ]] && grep -q '^## Structural' <<< "$out"; then
    pass "smoke: real memory dir"
  else
    fail "smoke: real memory dir" "rc=$rc
$out"
  fi
else
  pass "smoke: skipped (no memory dir on this machine)"
fi

exit "$FAILED"
