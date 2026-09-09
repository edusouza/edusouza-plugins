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

# --- python runtime ---
# As of 0.4.0, python backs wiki-index.py — a real runtime dependency, not just a
# test-harness convenience for parsing JSON below. Resolve it once, in the order the
# real interpreter wins on this machine: a WindowsApps `python3` shim can resolve
# ahead of the real `python`, so `python` is tried first. Fail loudly rather than
# let every check that needs it fail with a confusing "command not found" one by one.
PYBIN=""
if command -v python >/dev/null 2>&1; then
  PYBIN="python"
elif command -v python3 >/dev/null 2>&1; then
  PYBIN="python3"
else
  echo "FAIL: python runtime not found (tried: python, python3)"
  echo "      memory-wiki 0.4.0+ requires python; install it and re-run."
  exit 1
fi

# --- version parity: plugin.json vs marketplace.json ---
# This repo carries two independent version fields per plugin and nothing validates
# them, which is its single most recurring failure mode. Guard it from day one.
PJ="$PLUGIN/.claude-plugin/plugin.json"
MJ="$REPO/.claude-plugin/marketplace.json"
PV="$("$PYBIN" -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" "$PJ" 2>&1)"
MV="$("$PYBIN" -c "
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
run_fixture readme
run_fixture casing
run_fixture schema --sources "$HERE/fixtures/schema/sources"
run_fixture typed --sources "$HERE/fixtures/typed/sources" --concepts "$HERE/fixtures/typed/concepts"

# --- wiki-index.py: render half, golden-tested against the same typed fixture ---
# CR is stripped from both sides for the same reason the PowerShell parity check
# strips it: the content under test is the render, not which host produced the
# newline.
idx_out="$("$PYBIN" "$PLUGIN/bin/wiki-index.py" --wiki "$HERE/fixtures/typed/wiki" --render-only 2>&1 | tr -d '\r')"
idx_exp="$(cat "$HERE/expected/typed-index.txt" 2>/dev/null | tr -d '\r')"
if [[ "$idx_out" == "$idx_exp" ]]; then
  pass "index: render"
else
  fail "index: render" "$(diff <(echo "$idx_exp") <(echo "$idx_out") || true)"
fi

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

# Where a throwaway project's memory would live — echoed only when that dir is safe to
# scaffold into and, far more importantly, safe to `rm -rf` afterwards.
#
# Neither half is theoretical. `mktemp -d` honours $TMPDIR, and wiki_resolve_main_root
# redirects anything inside a *linked worktree* to the MAIN repo root. So a $TMPDIR
# pointing anywhere inside this repo or a worktree of it resolves a throwaway project
# onto the user's real project dir, and the cleanup at the end of the block then deletes
# their entire memory. A `*/projects/*` shape check does not help: the live path matches
# it exactly as well as a temp hash does. The two conditions that do discriminate are
# that the dir is not this repo's own, and that it did not already exist.
scratch_project_dir() {
  local d
  d="$(wiki_project_dir "$1" 2>/dev/null)"
  [[ -z "$d" || "$d" == "$(wiki_project_dir "$REPO" 2>/dev/null)" || -e "$d" ]] && return 1
  printf '%s' "$d"
}

# --- init: creates the scaffold, and is idempotent ---
TMPPROJ="$(mktemp -d)"
( cd "$TMPPROJ" && git init -q . ) >/dev/null 2>&1
TMPPDIR="$(scratch_project_dir "$TMPPROJ")"
if [[ -z "$TMPPDIR" ]]; then
  fail "init: scaffolds and is idempotent" \
    "$TMPPROJ resolves to $(wiki_project_dir "$TMPPROJ"), which is this repo's own memory
dir or already exists; refusing to scaffold into it or delete it. Check \$TMPDIR."
else
  MEMD="$TMPPDIR/memory"
  mkdir -p "$MEMD"
  out1="$(bash "$PLUGIN/bin/wiki-init.sh" "$TMPPROJ" 2>&1)"
  out2="$(bash "$PLUGIN/bin/wiki-init.sh" "$TMPPROJ" 2>&1)"
  if [[ -f "$MEMD/wiki/log.md" && -f "$MEMD/wiki/README.md" && -f "$MEMD/wiki/index.md" \
        && -d "$MEMD/wiki/inbox" ]] \
     && grep -q 'already initialized' <<< "$out2"; then
    pass "init: scaffolds and is idempotent"
  else
    fail "init: scaffolds and is idempotent" "run1: $out1
run2: $out2"
  fi
  rm -rf "$TMPPDIR"
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
rm -rf "$TMPPROJ" "$NOMEM"

# --- index: the write half ---
# Every check below runs on a `cp -r` copy of fixtures/typed, never on the fixture itself:
# the write path creates index.md, and expected/typed.txt pins that fixture at
# "index region : 0 B". Writing in place would break the render golden.
IDXBEGIN='<!-- BEGIN memory-wiki (managed; do not edit by hand) -->'
IDXTMP="$(mktemp -d)"
cp -r "$HERE/fixtures/typed" "$IDXTMP/typed"
IDXWIKI="$IDXTMP/typed/wiki"
IDXMEM="$IDXTMP/MEMORY.md"

# A realistic shared MEMORY.md: a line the user wrote by hand, then claude-memory's own
# managed region. Written with CRLF because the real file on Windows is CRLF and has to
# stay that way — silently rewriting a shared file's endings is a whole-file diff that
# belongs to nobody.
printf '%s\r\n' \
  '# Memory Index' \
  '' \
  '- [User note](note.md) — a line memory-wiki must never touch' \
  '' \
  '<!-- BEGIN claude-memory tier-3 (managed; do not edit by hand) -->' \
  '- [Some concept](concept_some.md) — belongs to claude-memory' \
  '<!-- END claude-memory tier-3 -->' > "$IDXMEM"

idx_w="$("$PYBIN" "$PLUGIN/bin/wiki-index.py" --wiki "$IDXWIKI" --memory-md "$IDXMEM" 2>&1)"; idx_rc=$?

# Extracted exactly the way wiki-lint.sh measures the injection budget, so the writer and
# the linter agree on what "the region" is. CR is stripped on both sides for the same
# reason the render check strips it: the content under test is the render, not the newline.
extract_region() {
  awk '/<!-- BEGIN memory-wiki/{f=1;next} /<!-- END memory-wiki/{f=0} f' "$1" 2>/dev/null | tr -d '\r'
}
# Reads on stdin so the filename never lands in the checksum. Silent on a missing file:
# the checks below test for the file separately and report that themselves.
sum_of() { [[ -f "$1" ]] && cksum < "$1"; }
got_region="$(extract_region "$IDXWIKI/index.md")"
want_region="$(cat "$HERE/expected/typed-index.txt" 2>/dev/null | tr -d '\r')"
if [[ $idx_rc -eq 0 && -n "$got_region" && "$got_region" == "$want_region" ]]; then
  pass "index: writes the region into index.md"
else
  fail "index: writes the region into index.md" "rc=$idx_rc  $idx_w
$(diff <(echo "$want_region") <(echo "$got_region") || true)"
fi

idx_mem="$(cat "$IDXMEM" 2>/dev/null)"
mem_ok=1
for needle in \
  '- [User note](note.md) — a line memory-wiki must never touch' \
  '<!-- BEGIN claude-memory tier-3 (managed; do not edit by hand) -->' \
  '- [Some concept](concept_some.md) — belongs to claude-memory' \
  '<!-- END claude-memory tier-3 -->' \
  "$IDXBEGIN"; do
  [[ "$idx_mem" == *"$needle"* ]] || mem_ok=0
done
# ...and what we added is a pointer, not a second copy of the index (D-a): rendering the
# region into both files would spend the injection budget twice.
idx_stub="$(extract_region "$IDXMEM")"
[[ -n "$idx_stub" && "$idx_stub" == *"wiki/index.md"* && "$idx_stub" != *"## Symptoms"* ]] || mem_ok=0
if [[ $mem_ok -eq 1 ]]; then
  pass "index: MEMORY.md keeps every foreign line and gains our stub"
else
  fail "index: MEMORY.md keeps every foreign line and gains our stub" "$idx_mem"
fi

# Not merely "a CR survived somewhere": the block we wrote must have adopted the file's own
# convention too, or the next reader gets a file with mixed endings.
if [[ "$idx_mem" == *$'\r'* && "$idx_mem" == *"$IDXBEGIN"$'\r'* ]]; then
  pass "index: MEMORY.md keeps its CRLF line endings"
else
  fail "index: MEMORY.md keeps its CRLF line endings" "no CR-terminated memory-wiki marker in $IDXMEM"
fi

# Idempotence: the append path's separator logic is where a second run grows a stray blank
# line or a whole second block. Checksum both files across a repeat run.
#
# The exit code is part of the assertion, not decoration. If the generator throws, nothing
# is written, both files stay exactly as run 1 left them and the checksums match trivially
# — a crashed generator would report PASS. This run is also the only exercise of the
# replace path anywhere in the suite: the checks above it only ever hit create and append.
sum1="$(sum_of "$IDXWIKI/index.md")|$(sum_of "$IDXMEM")"
"$PYBIN" "$PLUGIN/bin/wiki-index.py" --wiki "$IDXWIKI" --memory-md "$IDXMEM" >/dev/null 2>&1; idx_rc2=$?
sum2="$(sum_of "$IDXWIKI/index.md")|$(sum_of "$IDXMEM")"
if [[ $idx_rc2 -eq 0 && -f "$IDXWIKI/index.md" && -f "$IDXMEM" && "$sum1" == "$sum2" ]]; then
  pass "index: re-running is byte-identical"
else
  fail "index: re-running is byte-identical" "rc=$idx_rc2
run1: $sum1
run2: $sum2"
fi
rm -rf "$IDXTMP"

# --- init: the seed and the generator must agree on an empty wiki ---
# wiki-init.sh seeds index.md with the empty-wiki placeholder and wiki-index.py renders
# that same placeholder when there are no pages. If the two ever drift, every newly
# initialized wiki shows a phantom diff on its very first ingest, on a file nobody edited.
#
# Three shapes have to be one shape, because two of them are permanent once written: the
# seeded file, the same file rewritten through the replace path, and an index.md the
# generator creates from nothing in a wiki that never had one. The replace path never adds
# a heading afterwards, so a wiki whose index.md was created headingless keeps it forever
# while newly scaffolded wikis get one. Pinning only the first two lets that drift back in.
IXPROJ="$(mktemp -d)"
( cd "$IXPROJ" && git init -q . ) >/dev/null 2>&1
IXPDIR="$(scratch_project_dir "$IXPROJ")"
IXBARE="$(mktemp -d)"
if [[ -z "$IXPDIR" ]]; then
  fail "init: seeded index.md is what the generator would write" \
    "$IXPROJ resolves to $(wiki_project_dir "$IXPROJ"), which is this repo's own memory
dir or already exists; refusing to scaffold into it or delete it. Check \$TMPDIR."
else
  mkdir -p "$IXPDIR/memory"
  bash "$PLUGIN/bin/wiki-init.sh" "$IXPROJ" >/dev/null 2>&1
  seed1="$(sum_of "$IXPDIR/memory/wiki/index.md")"
  "$PYBIN" "$PLUGIN/bin/wiki-index.py" --wiki "$IXPDIR/memory/wiki" >/dev/null 2>&1; seed_rc=$?
  seed2="$(sum_of "$IXPDIR/memory/wiki/index.md")"
  "$PYBIN" "$PLUGIN/bin/wiki-index.py" --wiki "$IXBARE" >/dev/null 2>&1; bare_rc=$?
  seed3="$(sum_of "$IXBARE/index.md")"
  if [[ $seed_rc -eq 0 && $bare_rc -eq 0 && -n "$seed1" \
        && "$seed1" == "$seed2" && "$seed1" == "$seed3" ]]; then
    pass "init: seeded index.md is what the generator would write"
  else
    fail "init: seeded index.md is what the generator would write" "rc: seed=$seed_rc bare=$bare_rc
seeded:    ${seed1:-<no index.md>}
rewritten: ${seed2:-<no index.md>}
created:   ${seed3:-<no index.md>}"
  fi
  rm -rf "$IXPDIR"
fi
rm -rf "$IXPROJ" "$IXBARE"

# --- the ingest ledger: wiki-log.sh writes it, wiki-ingest-plan.sh reads it back ---
# One block for both scripts because they are one contract. wiki-log.sh is the only writer of
# the `- Sources:` lines and wiki-ingest-plan.sh is the only reader of them, so a writer whose
# format the reader cannot parse would sail through two separately-green blocks. The fixture's
# log.md is written in exactly the shape wiki-log.sh appends, and the round-trip check below
# closes the loop from the other end.
#
# fixtures/ingest-plan/memory carries an index.md, a README.md and an inbox/consumed/ that the
# page list does not mention on purpose: without them the exclusion half of the contract would
# be asserted against a wiki that has nothing to exclude.
PLAN="$PLUGIN/bin/wiki-ingest-plan.sh"
LOGSH="$PLUGIN/bin/wiki-log.sh"
PLANFIX="$HERE/fixtures/ingest-plan/memory"

plan_out="$(bash "$PLAN" "$PLANFIX" 2>&1)"
plan_exp="$(cat "$HERE/expected/ingest-plan.txt" 2>/dev/null)"
if [[ "$plan_out" == "$plan_exp" ]]; then
  pass "plan: work order"
else
  fail "plan: work order" "$(diff <(echo "$plan_exp") <(echo "$plan_out") || true)"
fi

# The round trip, asserted from both ends on one temp copy — two pending before, none after —
# so it cannot pass by the fixture having had nothing pending all along.
#
# "after" is measured in BYTES rather than captured with $(...). Command substitution strips
# trailing newlines, so a script that emitted one stray newline would compare equal to "" and
# this check would certify the exact bug it exists to catch: wiki-nudge.sh counts these lines,
# and one blank line reads as a pending rollup named "".
PLANTMP="$(mktemp -d)"
cp -r "$PLANFIX" "$PLANTMP/memory"
rt_want=$'2026-W35\n2026-W36'
rt_before="$(bash "$PLAN" "$PLANTMP/memory" --pending-only 2>&1)"
# A space after the comma, because the ingest skill is the caller and writes lists the way a
# person would.
rt_log="$(bash "$LOGSH" --wiki "$PLANTMP/memory/wiki" --op ingest --title 'Round trip' \
  --date 2026-09-09 --sources '2026-W35, 2026-W36' 2>&1)"; rt_rc=$?
rt_after="$(bash "$PLAN" "$PLANTMP/memory" --pending-only 2>&1 | wc -c | tr -d '[:space:]')"
# The same emptied state read through the full report, where a section that has run dry is
# rendered as (none) rather than dropped — the only place the suite reaches that branch.
rt_none_want=$'## Pending sources (0)\n(none)'
rt_none="$(bash "$PLAN" "$PLANTMP/memory" 2>&1)"
if [[ $rt_rc -eq 0 && "$rt_before" == "$rt_want" && "$rt_after" == "0" \
      && "$rt_none" == *"$rt_none_want"* ]]; then
  pass "plan: logging a source clears it from pending"
else
  fail "plan: logging a source clears it from pending" "log rc=$rt_rc  $rt_log
before: $rt_before
after: $rt_after byte(s), want 0
work order:
$rt_none"
fi
rm -rf "$PLANTMP"

# The writer's format line for line, the survival of the entry that was already there, and the
# glob trap, in one run.
#
# Wiki page names are model-generated, so one of them here carries a literal `*`. It is passed
# as a single quoted argument; a splitter that let the shell word-split the list unquoted would
# then pathname-expand that word against the process's cwd — which is why this run happens from
# a directory holding a file the pattern matches. `[[component_decoy]]` in log.md means the glob
# fired. The `--updated` value is padded with spaces to pin the trimming at the same time.
LOGTMP="$(mktemp -d)"
cp -r "$PLANFIX" "$LOGTMP/memory"
: > "$LOGTMP/component_decoy"
log_run="$( cd "$LOGTMP" && bash "$LOGSH" --wiki "$LOGTMP/memory/wiki" --op ingest \
  --title 'Star names and all' --date 2026-09-10 --sources '2026-W35' \
  --created 'component_new,component_*' --updated '  failure_demo-crash  ' \
  --inbox '2026-09-02-note.md' 2>&1 )"; log_rc=$?
log_body="$(cat "$LOGTMP/memory/wiki/log.md" 2>/dev/null)"
log_missing=""
for needle in \
  '## [2026-09-10] ingest | Star names and all' \
  '- Sources: [[2026-W35]]' \
  '- Pages created: [[component_new]], [[component_*]]' \
  '- Pages updated: [[failure_demo-crash]]' \
  '- Inbox consumed: 2026-09-02-note.md' \
  '## [2026-09-01] ingest | Week 2026-W34' \
  '- Sources: [[2026-W34]]'; do
  [[ "$log_body" == *"$needle"* ]] || log_missing="$log_missing
      $needle"
done
if [[ $log_rc -eq 0 && -z "$log_missing" ]]; then
  pass "log: appends the ledger format, preserving earlier entries"
else
  fail "log: appends the ledger format, preserving earlier entries" "rc=$log_rc  $log_run
not found in log.md:$log_missing"
fi
rm -rf "$LOGTMP"

# Both of the writer's redirections, because they fail independently: a directory where log.md
# belongs never satisfies -f, so the run fails on the create; a read-only regular file does
# satisfy it, so the run gets as far as the append and fails there. wiki-log.sh has no `set -e`,
# and an unchecked redirection prints its error and falls straight through to "logged:" —
# telling Task 6's ingest skill the entry landed immediately before it moves the inbox capture
# into consumed/, which loses the capture with nothing left to show it existed.
UNWR="$(mktemp -d)"
mkdir -p "$UNWR/asdir/log.md" "$UNWR/asro"
unwr_bad=""
unwr1="$(bash "$LOGSH" --wiki "$UNWR/asdir" --op ingest --title unwritable --date 2026-09-14 \
  --sources '2026-W35' 2>&1)"; unwr1_rc=$?
[[ $unwr1_rc -eq 1 && "$unwr1" != *"logged:"* ]] || unwr_bad="$unwr_bad
      create: rc=$unwr1_rc (want 1) $unwr1"
printf '# Wiki Log\n' > "$UNWR/asro/log.md"
chmod 444 "$UNWR/asro/log.md"
# Assert the append half only where the platform honours the bit. Running as root, or on a
# filesystem that ignores it, would make this a test of nothing rather than a failing one.
if ! ( printf 'x\n' >> "$UNWR/asro/log.md" ) 2>/dev/null; then
  unwr2="$(bash "$LOGSH" --wiki "$UNWR/asro" --op ingest --title unwritable --date 2026-09-14 \
    --sources '2026-W35' 2>&1)"; unwr2_rc=$?
  [[ $unwr2_rc -eq 1 && "$unwr2" != *"logged:"* ]] || unwr_bad="$unwr_bad
      append: rc=$unwr2_rc (want 1) $unwr2"
fi
chmod 644 "$UNWR/asro/log.md" 2>/dev/null
if [[ -z "$unwr_bad" ]]; then
  pass "log: a failed write is reported as a failure"
else
  fail "log: a failed write is reported as a failure" "want rc=1 and no 'logged:' line:$unwr_bad"
fi
rm -rf "$UNWR"

# A project that never scaffolded a wiki is an expected answer, not a script failure. Under
# --pending-only it is not even an answer: wiki-nudge.sh would read the report's lines as
# pending rollups. Bytes again, for the reason given above.
NOWIKI="$(mktemp -d)"
mkdir -p "$NOWIKI/memory"
nw_out="$(bash "$PLAN" "$NOWIKI/memory" 2>&1)"; nw_rc=$?
nw_bytes="$(bash "$PLAN" "$NOWIKI/memory" --pending-only 2>&1 | wc -c | tr -d '[:space:]')"
# ...and the report itself goes to stderr, behind that guard rather than instead of it, so
# stdout stays reserved for the work order and no future caller can miscount a diagnostic.
nw_stdout="$(bash "$PLAN" "$NOWIKI/memory" 2>/dev/null | wc -c | tr -d '[:space:]')"
if [[ $nw_rc -eq 0 && "$nw_out" == *"ERROR: no wiki for: $NOWIKI/memory"* \
      && "$nw_out" == *"/memory-wiki:init"* && "$nw_bytes" == "0" && "$nw_stdout" == "0" ]]; then
  pass "plan: missing wiki reports, exits 0, and stays silent under --pending-only"
else
  fail "plan: missing wiki reports, exits 0, and stays silent under --pending-only" "rc=$nw_rc
$nw_out
--pending-only: $nw_bytes byte(s), want 0
report on stdout: $nw_stdout byte(s), want 0"
fi
rm -rf "$NOWIKI"

# Every refused call must leave stdout empty too. wiki-nudge.sh counts the lines this script
# puts on stdout, so anything there that is not a rollup name becomes a nag the user cannot
# clear. One typo used to be enough: `--pending--only` was taken as MEMORY_DIR, the real path
# discarded, and the resulting "no wiki" report read as two pending rollups named after the
# error text. A second positional is refused for the same reason rather than silently winning.
ref_bad=""
for bogus in '--pending--only' '--nope'; do
  b_out="$(bash "$PLAN" "$PLANFIX" "$bogus" 2>/dev/null | wc -c | tr -d '[:space:]')"
  b_err="$(bash "$PLAN" "$PLANFIX" "$bogus" 2>&1 >/dev/null)"; b_rc=$?
  [[ "$b_out" == "0" && $b_rc -eq 0 && "$b_err" == *"unrecognized argument"* ]] \
    || ref_bad="$ref_bad
      $bogus: stdout=$b_out byte(s) rc=$b_rc stderr=$b_err"
done
two_out="$(bash "$PLAN" "$PLANFIX" "$PLANFIX" 2>/dev/null | wc -c | tr -d '[:space:]')"
[[ "$two_out" == "0" ]] || ref_bad="$ref_bad
      second positional: stdout=$two_out byte(s), want 0"
if [[ -z "$ref_bad" ]]; then
  pass "plan: a refused argument leaves stdout empty"
else
  fail "plan: a refused argument leaves stdout empty" "want stdout=0 rc=0 and a stderr complaint:$ref_bad"
fi

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
  # readme is the parity assertion that matters most here: the divergence it pins was between
  # the twins, not against a golden — bash listed its structural link targets explicitly while
  # the twin derived them from $structural.
  parity readme
  # casing likewise: the structural exemption is four exact filenames, and PowerShell's -notin
  # ignored case where bash's == does not, so Readme.md was a page on one twin and structural
  # on the other.
  parity casing
  parity schema "$HERE/fixtures/schema/sources"
  # parity has no --concepts slot, so both sides run without one and both report the same two
  # broken links to [[concept_root-heuristic]]. That is still a valid parity assertion — the
  # contract under test is that the two scripts agree, not that they agree only when fully
  # argumented. Do not widen the helper for this.
  parity typed "$HERE/fixtures/typed/sources"
else
  pass "parity: skipped (pwsh not on PATH)"
fi

# --- shipped surface: every declared file exists ---
missing=""
for p in README.md skills/lint/SKILL.md commands/lint.md commands/init.md \
         bin/wiki-lint.sh bin/wiki-lint.ps1 bin/wiki-init.sh bin/wiki-lint-project.sh \
         bin/wiki-index.py bin/wiki-index.sh \
         bin/wiki-log.sh bin/wiki-ingest-plan.sh \
         bin/_wiki-paths.sh assets/wiki-README.md \
         skills/ingest/references/page-authoring.md; do
  [[ -f "$PLUGIN/$p" ]] || missing="$missing $p"
done
if [[ -z "$missing" ]]; then
  pass "surface: all declared files present"
else
  fail "surface: all declared files present" "missing:$missing"
fi

# --- authoring reference: both worked exemplars survive an edit ---
# Deliberately shallow. Page prose is judgment, and pinning a word of it here would
# turn every improvement to the reference into a test failure. What is pinned is that
# a *complete* worked example of each specially-treated type is still in the file:
# failure_ (the only type with `symptom:`, the line the session-start index renders
# verbatim) and component_ (the only type with `part_of:`).
#
# Every pattern is anchored to the start of a line, which is what makes this more than
# a word search. Prose mentions and bullets ("- `type: failure` also needs `symptom:`")
# are indented or prefixed and cannot match; the frontmatter *template* in the same
# reference spells `type:` as the union `project | component | tech | failure | concept`
# and lists the per-type extras in a markdown table, so it cannot satisfy these either.
# Only a real frontmatter block inside a worked exemplar can.
#
# The file-absent branch is explicit rather than left to grep's non-zero exit: an empty
# or deleted file must report *why* it failed, not just list four unmatched patterns.
#
# CR is stripped before matching, for the same reason the render and parity checks strip
# it, and here it is load-bearing rather than cosmetic: .gitattributes marks *.md as
# `text` with no eol, so with core.autocrlf=true — the default on the Windows clone this
# is developed on — every checked-out .md in the working tree is CRLF. A `$`-anchored
# pattern would then never match the trailing CR, and this check would report a missing
# exemplar on every fresh clone while passing on the machine that wrote the file.
AUTHREF="skills/ingest/references/page-authoring.md"
missing=""
if [[ ! -s "$PLUGIN/$AUTHREF" ]]; then
  missing=" $AUTHREF is absent or empty"
else
  authref_body="$(tr -d '\r' < "$PLUGIN/$AUTHREF")"
  for pat in '^type: failure$' '^symptom:' '^type: component$' '^part_of:'; do
    grep -qE "$pat" <<< "$authref_body" || missing="$missing no line matches: $pat;"
  done
fi
if [[ -z "$missing" ]]; then
  pass "authoring: reference carries a worked failure_ and component_ exemplar"
else
  fail "authoring: reference carries a worked failure_ and component_ exemplar" "$missing"
fi

# --- commands: no shell resolver in a !`...` substitution ---
# Claude Code expands only the exact literal ${CLAUDE_PLUGIN_ROOT} in a command body, and
# it does so before any shell runs. A hand-rolled resolver using ${CLAUDE_PLUGIN_ROOT:-},
# CLAUDE_SKILL_DIR or a `find` over the plugin cache is therefore never expanded, and the
# command dies at load time with "Shell substitution failed ... (detail withheld)". This
# regression has now shipped twice in this repo; pin it.
bad=""
for c in "$PLUGIN"/commands/*.md; do
  sub="$(grep -o '!`[^`]*`' "$c")"
  [[ -z "$sub" ]] && continue
  grep -q '\${CLAUDE_PLUGIN_ROOT}' <<< "$sub" || bad="$bad $(basename "$c"):no-plugin-root"
  grep -qE 'CLAUDE_SKILL_DIR|CLAUDE_PLUGIN_ROOT:-|\bexec\b|plugins/cache' <<< "$sub" \
    && bad="$bad $(basename "$c"):resolver"
done
if [[ -z "$bad" ]]; then
  pass "commands: substitutions use \${CLAUDE_PLUGIN_ROOT}, not a resolver"
else
  fail "commands: substitutions use \${CLAUDE_PLUGIN_ROOT}, not a resolver" "offenders:$bad"
fi

# --- lint-project: resolves a memory dir, and reports rather than fails without one ---
NOMEM2="$(mktemp -d)"
out4="$(bash "$PLUGIN/bin/wiki-lint-project.sh" "$NOMEM2/nope" 2>&1)"; rc4=$?
if [[ $rc4 -eq 0 ]] && grep -q 'ERROR: no memory dir' <<< "$out4"; then
  pass "lint-project: missing memory dir reports and exits 0"
else
  fail "lint-project: missing memory dir reports and exits 0" "rc=$rc4
$out4"
fi
# A pre-wiki memory dir has no wiki/ subdir; the flat pages there are the thing to audit.
out5="$(bash "$PLUGIN/bin/wiki-lint-project.sh" "$HERE/fixtures/clean/wiki" 2>&1)"
if grep -q '^## Structural' <<< "$out5"; then
  pass "lint-project: audits a memory dir with no wiki/ subdir"
else
  fail "lint-project: audits a memory dir with no wiki/ subdir" "$out5"
fi
rm -rf "$NOMEM2"

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
