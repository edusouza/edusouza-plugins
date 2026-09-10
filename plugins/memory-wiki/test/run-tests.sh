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

# --- shipped surface: every declared file exists and has content ---
# `-s`, not `-f`. A zero-byte SKILL.md, command or script is present in exactly the sense
# `-f` tests for and useless in every other: Claude Code loads it, finds no frontmatter, and
# the surface silently is not there. That is the harness's own recurring failure shape — a
# check that holds on an empty file — so the emptiness is caught here rather than left to
# whichever later check happens to read the file's contents.
missing=""
for p in README.md skills/lint/SKILL.md commands/lint.md commands/init.md \
         bin/wiki-lint.sh bin/wiki-lint.ps1 bin/wiki-init.sh bin/wiki-lint-project.sh \
         bin/wiki-index.py bin/wiki-index.sh \
         bin/wiki-log.sh bin/wiki-ingest-plan.sh \
         bin/wiki-inject.sh hooks/hooks.json \
         bin/_wiki-paths.sh assets/wiki-README.md \
         skills/ingest/references/page-authoring.md \
         skills/ingest/SKILL.md commands/ingest.md; do
  [[ -s "$PLUGIN/$p" ]] || missing="$missing $p"
done
if [[ -z "$missing" ]]; then
  pass "surface: all declared files present"
else
  fail "surface: all declared files present" "missing:$missing"
fi

# --- ingest surface: the frontmatter Claude Code actually reads ---
# Presence is not the contract. Everything that decides whether these two files work at all
# lives in their frontmatter, and every field below fails silently when it is wrong: a skill
# whose `name:` is not `ingest` is invocable under a different name than the command and the
# nudge point at; a command missing `disable-model-invocation: true` becomes a second
# model-invocable surface competing with the skill (its Phase 1 siblings all carry it); and a
# command whose `allowed-tools` omits a tool cannot use it — an ingest that cannot Write is a
# run that reads the whole work order and produces nothing.
#
# Matching happens against the frontmatter block ALONE — the lines between the `---` on line 1
# and the next `---` — so nothing here can be satisfied by prose, by a bullet describing the
# field, or by a fenced code block further down the file quoting a frontmatter template. Body
# prose is deliberately not pinned: it is judgment, and pinning a word of it would turn every
# improvement into a failure. What is pinned is the machine-read part.
#
# CR is stripped first, for the reason the authoring check gives: .gitattributes marks *.md as
# `text`, so with core.autocrlf=true every checked-out .md in the working tree is CRLF and a
# `$`-anchored pattern would never match past the trailing CR.
fm_block() {
  tr -d '\r' < "$1" 2>/dev/null \
    | awk 'NR==1 { if ($0 != "---") exit; next } $0 == "---" { exit } { print }'
}
ing_bad=""
INGSKILL="skills/ingest/SKILL.md"
INGCMD="commands/ingest.md"
if [[ ! -s "$PLUGIN/$INGSKILL" ]]; then
  ing_bad="$ing_bad
      $INGSKILL is absent or empty"
else
  ing_fm="$(fm_block "$PLUGIN/$INGSKILL")"
  grep -qE '^name: ingest$' <<< "$ing_fm" || ing_bad="$ing_bad
      $INGSKILL: no 'name: ingest' in frontmatter"
  # A skill with no description is never triggered by anything the user says.
  grep -qE '^description: .' <<< "$ing_fm" || ing_bad="$ing_bad
      $INGSKILL: no non-empty 'description:' in frontmatter"
fi
if [[ ! -s "$PLUGIN/$INGCMD" ]]; then
  ing_bad="$ing_bad
      $INGCMD is absent or empty"
else
  ing_fm="$(fm_block "$PLUGIN/$INGCMD")"
  grep -qE '^disable-model-invocation: true$' <<< "$ing_fm" || ing_bad="$ing_bad
      $INGCMD: no 'disable-model-invocation: true' in frontmatter"
  ing_at="$(grep -E '^allowed-tools:' <<< "$ing_fm")"
  if [[ -z "$ing_at" ]]; then
    ing_bad="$ing_bad
      $INGCMD: no 'allowed-tools:' line in frontmatter"
  else
    # Word-bounded, so `Read` is not satisfied by `ReadFile` and `Grep` is not satisfied by a
    # substring of something else.
    for t in Bash Read Write Edit Glob Grep; do
      grep -qE "(^|[^A-Za-z])$t([^A-Za-z]|\$)" <<< "$ing_at" || ing_bad="$ing_bad
      $INGCMD: allowed-tools does not list $t"
    done
  fi
fi
if [[ -z "$ing_bad" ]]; then
  pass "ingest: skill and command carry the frontmatter that makes them work"
else
  fail "ingest: skill and command carry the frontmatter that makes them work" "$ing_bad"
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

# --- inject: the read half, driven the way Claude Code drives it ---
# End to end: a throwaway git project, its own memory dir under $HOME/.claude/projects/<hash>,
# wiki-init.sh plus the real generator, and the payload JSON Claude Code puts on stdin.
# scratch_project_dir is what keeps this off the user's live memory dir (see its comment);
# everything created below is deleted at the end of the block.
#
# Payloads are written to files and *redirected* in, never piped. A hook that exits before
# reading stdin makes a piped writer die of EPIPE, and that writer's own stderr would then
# land in the very output these checks assert is empty.
#
# Most of the checks below assert *silence*, which is the easiest thing in the world to assert
# wrongly: a script that dies on its first line is silent too, and so is one that is not there.
# Every silence check therefore asserts rc 0 *and* empty output *and* carries
# `$inj_emit_proof -eq 1` — proof that the one emitting check rendered the fixture's symptom
# string. A hook that is unconditionally silent fails the whole block instead of passing most
# of it. The two spawn-budget numbers are gated the same way, on `inj_shim_ok`.
INJHOOK="$PLUGIN/bin/wiki-inject.sh"
INJPROJ="$(mktemp -d)"
( cd "$INJPROJ" && git init -q . ) >/dev/null 2>&1
INJPDIR="$(scratch_project_dir "$INJPROJ")"
INJTMP="$(mktemp -d)"
printf '{"session_id":"0000","transcript_path":"","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' \
  "$INJPROJ" > "$INJTMP/payload.json"
printf 'not json\n' > "$INJTMP/bad.json"
: > "$INJTMP/empty.json"
printf '{"hook_event_name":"SessionStart"}' > "$INJTMP/nocwd.json"

# inj_run <payload-file> [VAR=val ...]  -> sets INJ_OUT (stdout+stderr) and INJ_RC.
# stderr is captured deliberately: a hook must be silent on *both* streams at session start.
# Deliberately NOT called via $(...) — that would run it in a subshell and discard INJ_OUT.
INJ_OUT=""; INJ_RC=0
inj_run() {
  local pf="$1"; shift
  INJ_OUT="$(env "$@" bash "$INJHOOK" < "$pf" 2>&1)"; INJ_RC=$?
}

if [[ -z "$INJPDIR" ]]; then
  fail "inject: silent and exits 0 with no wiki" \
    "$INJPROJ resolves to $(wiki_project_dir "$INJPROJ"), which is this repo's own memory
dir or already exists; refusing to scaffold into it or delete it. Check \$TMPDIR."
else
  INJWIKI="$INJPDIR/memory/wiki"

  # Two shapes of "no wiki": no project memory dir at all, and a memory-enabled project
  # that never ran /memory-wiki:init.
  inj_run "$INJTMP/payload.json"; inj_a_out="$INJ_OUT"; inj_a_rc=$INJ_RC
  mkdir -p "$INJPDIR/memory"
  inj_run "$INJTMP/payload.json"; inj_b_out="$INJ_OUT"; inj_b_rc=$INJ_RC
  if [[ $inj_a_rc -eq 0 && $inj_b_rc -eq 0 && -z "$inj_a_out" && -z "$inj_b_out" ]]; then
    pass "inject: silent and exits 0 with no wiki"
  else
    fail "inject: silent and exits 0 with no wiki" "no memory dir: rc=$inj_a_rc out=[$inj_a_out]
no wiki dir:   rc=$inj_b_rc out=[$inj_b_out]"
  fi

  # A freshly scaffolded wiki holds nothing but the empty-wiki placeholder, and a section
  # header over "there is nothing here" is worse than no section. This is also the only
  # "both regions empty" case reachable without a fake atlas, since $HOME/.claude/memory-wiki
  # exists on no machine until Phase 4. The -f guard distinguishes "suppressed the placeholder"
  # from "wiki-init.sh silently wrote no index.md at all".
  bash "$PLUGIN/bin/wiki-init.sh" "$INJPROJ" >/dev/null 2>&1
  inj_run "$INJTMP/payload.json"
  if [[ $INJ_RC -eq 0 && -z "$INJ_OUT" && -f "$INJWIKI/index.md" ]]; then
    pass "inject: a wiki rendering only the empty-wiki placeholder is suppressed"
  else
    fail "inject: a wiki rendering only the empty-wiki placeholder is suppressed" \
      "rc=$INJ_RC  index.md present: $([[ -f "$INJWIKI/index.md" ]] && echo yes || echo NO)
out=[$INJ_OUT]"
  fi

  # The non-silent path, and the only check in the block that proves the hook can speak.
  # Real pages, the real generator, the real hook.
  cp "$HERE/fixtures/typed/wiki"/*.md "$INJWIKI/" 2>/dev/null
  "$PYBIN" "$PLUGIN/bin/wiki-index.py" --wiki "$INJWIKI" >/dev/null 2>&1; inj_gen_rc=$?
  inj_run "$INJTMP/payload.json"; inj_emit_out="$INJ_OUT"; inj_emit_rc=$INJ_RC
  inj_bad=""
  [[ $inj_gen_rc -eq 0 ]] || inj_bad="$inj_bad generator rc=$inj_gen_rc;"
  [[ $inj_emit_rc -eq 0 ]] || inj_bad="$inj_bad hook rc=$inj_emit_rc;"
  # The section header, the affordance sentence, the symptom string rendered verbatim, and a
  # page wikilink. ASCII needles only: the header carries an em dash and this file is read on
  # hosts whose console encoding is not UTF-8.
  for needle in \
    '## Memory wiki' \
    'ONLY when a line below matches' \
    'demo: fatal: cannot open state file' \
    '[[failure_demo-crash]]'; do
    [[ "$inj_emit_out" == *"$needle"* ]] || inj_bad="$inj_bad missing: $needle;"
  done
  # The header must name the wiki this output came from, or the model cannot open the pages.
  [[ "$inj_emit_out" == *"/memory/wiki"* ]] || inj_bad="$inj_bad header does not name the wiki path;"
  if [[ -z "$inj_bad" ]]; then
    pass "inject: emits the project index region"
  else
    fail "inject: emits the project index region" "$inj_bad
$inj_emit_out"
  fi
  # The proof every silence check below leans on. Emphatically not `-n "$inj_emit_out"`: while
  # the hook did not exist at all, that variable held bash's "No such file or directory" and a
  # bare emptiness guard was satisfied by the error message for the very failure it exists to
  # detect. Only the rendered symptom string proves the emitting path actually ran.
  inj_emit_proof=0
  [[ "$inj_emit_out" == *'demo: fatal: cannot open state file'* ]] && inj_emit_proof=1

  # Both switches, checked against the wiki that just produced output — so this pins the
  # suppression itself, not an index that had nothing in it either way.
  inj_run "$INJTMP/payload.json" MEMORY_WIKI_NO_INJECT=1;       inj_n_out="$INJ_OUT"; inj_n_rc=$INJ_RC
  inj_run "$INJTMP/payload.json" CLAUDE_MEMORY_CONSOLIDATING=1; inj_c_out="$INJ_OUT"; inj_c_rc=$INJ_RC
  if [[ $inj_n_rc -eq 0 && $inj_c_rc -eq 0 && -z "$inj_n_out" && -z "$inj_c_out" \
        && $inj_emit_proof -eq 1 ]]; then
    pass "inject: honours MEMORY_WIKI_NO_INJECT and CLAUDE_MEMORY_CONSOLIDATING"
  else
    fail "inject: honours MEMORY_WIKI_NO_INJECT and CLAUDE_MEMORY_CONSOLIDATING" \
      "NO_INJECT:     rc=$inj_n_rc out=[$inj_n_out]
CONSOLIDATING: rc=$inj_c_rc out=[$inj_c_out]
emitting run rendered the symptom: $inj_emit_proof (must be 1, or 'silent' proves nothing)"
  fi

  # Three shapes of unusable payload: not JSON at all, nothing on stdin, and valid JSON with
  # no cwd. All silent, all rc 0 — the hook has no business reporting a malformed payload to
  # the user at session start.
  inj_run "$INJTMP/bad.json";   inj_p1="$INJ_OUT"; inj_r1=$INJ_RC
  inj_run "$INJTMP/empty.json"; inj_p2="$INJ_OUT"; inj_r2=$INJ_RC
  inj_run "$INJTMP/nocwd.json"; inj_p3="$INJ_OUT"; inj_r3=$INJ_RC
  if [[ $inj_r1 -eq 0 && $inj_r2 -eq 0 && $inj_r3 -eq 0 \
        && -z "$inj_p1" && -z "$inj_p2" && -z "$inj_p3" && $inj_emit_proof -eq 1 ]]; then
    pass "inject: unparseable payload is a silent no-op"
  else
    fail "inject: unparseable payload is a silent no-op" "not json:  rc=$inj_r1 out=[$inj_p1]
empty:     rc=$inj_r2 out=[$inj_p2]
no cwd:    rc=$inj_r3 out=[$inj_p3]
emitting run rendered the symptom: $inj_emit_proof (must be 1, or 'silent' proves nothing)"
  fi

  # No python at all. Everything the hook touches before the interpreter probe is either a
  # bash builtin or a `.` of a sibling file, so emptying PATH is enough to hide python without
  # disturbing anything else — bash is invoked by absolute path for exactly that reason. This
  # is the last of the brief's silent-exit conditions and the only one with no other coverage.
  INJ_OUT="$(env PATH="$INJTMP/no-such-bin" "${BASH:-bash}" "$INJHOOK" \
    < "$INJTMP/payload.json" 2>&1)"; INJ_RC=$?
  if [[ $INJ_RC -eq 0 && -z "$INJ_OUT" && $inj_emit_proof -eq 1 ]]; then
    pass "inject: no python runtime is a silent no-op"
  else
    fail "inject: no python runtime is a silent no-op" "rc=$INJ_RC out=[$INJ_OUT]
emitting run rendered the symptom: $inj_emit_proof (must be 1, or 'silent' proves nothing)"
  fi

  # The payload shape Claude Code actually sends on this platform: cwd as a Windows path,
  # whose separators arrive JSON-escaped as \\. It has to land on the same memory dir as the
  # POSIX spelling — the hook is the only caller that takes a path straight out of JSON, so
  # a lost unescaping step would show up here and nowhere else in the suite.
  if command -v cygpath >/dev/null 2>&1; then
    inj_win="$(cygpath -w "$INJPROJ" 2>/dev/null)"
    printf '{"cwd":"%s","hook_event_name":"SessionStart"}' "${inj_win//\\/\\\\}" \
      > "$INJTMP/winpath.json"
    inj_run "$INJTMP/winpath.json"
    if [[ $INJ_RC -eq 0 && "$INJ_OUT" == "$inj_emit_out" && $inj_emit_proof -eq 1 ]]; then
      pass "inject: a Windows-style escaped cwd resolves to the same wiki"
    else
      fail "inject: a Windows-style escaped cwd resolves to the same wiki" \
        "cwd sent: ${inj_win//\\/\\\\}
rc=$INJ_RC
$(diff <(echo "$inj_emit_out") <(echo "$INJ_OUT") || true)"
    fi
  else
    pass "inject: Windows-style cwd check skipped (no cygpath)"
  fi

  # --- the atlas half ---
  # Phase 4 populates $HOME/.claude/memory-wiki; until then that dir exists on no machine, so
  # the atlas emission branch would ship completely unexercised. MEMORY_WIKI_ATLAS_DIR is the
  # seam that lets it be driven here and is the only reason it exists — the default is still
  # $HOME/.claude/memory-wiki, the same path wiki-lint-project.sh hardcodes.
  INJATL="$INJTMP/atlas"; mkdir -p "$INJATL"
  printf '%s\n' '# Wiki index' '' \
    '<!-- BEGIN memory-wiki (managed; do not edit by hand) -->' \
    '(no pages yet — run /memory-wiki:ingest)' \
    '<!-- END memory-wiki -->' > "$INJATL/index.md"
  inj_run "$INJTMP/payload.json" MEMORY_WIKI_ATLAS_DIR="$INJATL"
  inj_at_empty="$INJ_OUT"; inj_at_erc=$INJ_RC
  printf '%s\n' '# Wiki index' '' \
    '<!-- BEGIN memory-wiki (managed; do not edit by hand) -->' \
    '## Map' \
    '- [[atlas/global-thing]] — a cross-project page' \
    '<!-- END memory-wiki -->' > "$INJATL/index.md"
  inj_run "$INJTMP/payload.json" MEMORY_WIKI_ATLAS_DIR="$INJATL"
  inj_at_full="$INJ_OUT"; inj_at_frc=$INJ_RC
  inj_bad=""
  [[ $inj_at_erc -eq 0 && $inj_at_frc -eq 0 ]] \
    || inj_bad="$inj_bad rc placeholder=$inj_at_erc populated=$inj_at_frc;"
  # Both runs must still print the project section: that is what distinguishes "the atlas was
  # suppressed" from "the hook fell over before it got there".
  [[ "$inj_at_empty" == *'## Memory wiki'* ]] \
    || inj_bad="$inj_bad placeholder-atlas run printed no project section;"
  [[ "$inj_at_full" == *'## Memory wiki'* ]] \
    || inj_bad="$inj_bad populated-atlas run printed no project section;"
  [[ "$inj_at_empty" != *'cross-project atlas'* ]] \
    || inj_bad="$inj_bad a placeholder-only atlas got a section header;"
  [[ "$inj_at_full" == *'cross-project atlas'* ]] \
    || inj_bad="$inj_bad a non-empty atlas got no section header;"
  [[ "$inj_at_full" == *'[[atlas/global-thing]]'* ]] \
    || inj_bad="$inj_bad the atlas section carried no body;"
  if [[ -z "$inj_bad" ]]; then
    pass "inject: the atlas section appears only when its region is non-empty"
  else
    fail "inject: the atlas section appears only when its region is non-empty" "$inj_bad
--- placeholder atlas ---
$inj_at_empty
--- populated atlas ---
$inj_at_full"
  fi

  # --- spawn budget ---
  # Same shim technique as claude-memory/test/run-tests.sh: put a logging wrapper for every
  # external binary this path can reach on the front of PATH, run the hook, count the log.
  # This asserts the property the hook actually cares about (how many processes start) rather
  # than a wall-clock number that would be flaky. On this machine a spawn costs ~430 ms — 50
  # of them measured 21.5 s — and this hook blocks *every* session start.
  #
  # CLAUDE_PLUGIN_ROOT is exported because Claude Code sets it, and the hook's fallback for
  # locating its own bin/ is pure parameter expansion precisely so that it costs nothing
  # either way; leaving it unset here would measure a path production never takes.
  INJSHIM="$(mktemp -d)"
  INJLOG="$INJSHIM/calls.log"; : > "$INJLOG"
  for bin in git cygpath sed awk grep tr wc cat head tail cut python python3 \
             basename dirname realpath readlink; do
    real="$(command -v "$bin" 2>/dev/null)" || continue
    [[ -z "$real" ]] && continue
    cat > "$INJSHIM/$bin" <<EOF
#!/usr/bin/env bash
echo "$bin" >> "$INJLOG"
exec "$real" "\$@"
EOF
    chmod +x "$INJSHIM/$bin"
  done

  # Sets the globals INJ_SPAWN_OUT and INJ_SPAWNS. Deliberately NOT called via $(...) — that
  # would run it in a subshell and discard both. The PATH assignment is scoped to the inner
  # subshell so the wc/tr that read the log are never themselves counted.
  INJ_SPAWN_OUT=""; INJ_SPAWNS=0
  inj_count_spawns() {
    local pf="$1"; shift
    : > "$INJLOG"
    INJ_SPAWN_OUT="$( PATH="$INJSHIM:$PATH"; env CLAUDE_PLUGIN_ROOT="$PLUGIN" "$@" \
      bash "$INJHOOK" < "$pf" 2>/dev/null )"
    INJ_SPAWNS="$(wc -l < "$INJLOG" | tr -d ' ')"
  }

  # Budget, enumerated from the shim's own log rather than guessed:
  #   1  python    parse the payload JSON — the hook's whole job is to resolve the memory dir
  #                from the payload's cwd, so there is no environment shortcut past it
  #   7  inside wiki_project_dir: cygpath -u, three git rev-parse, dirname, cygpath -w, sed
  #   1  cygpath -m  to name the wiki in the section header
  # Region extraction is a bash `while read` loop and costs nothing at all; the awk
  # wiki-lint.sh uses to measure the same region would be one spawn per file, two more here.
  #
  # The `dirname` is worth naming because it is not obvious: on Windows, `git rev-parse
  # --absolute-git-dir` answers in mixed form (C:/…) while --git-common-dir resolves to POSIX
  # form (/c/…), so wiki_resolve_main_root's string comparison reads *every* git repo as a
  # linked worktree and takes the dirname branch. It still returns the right root — for a main
  # worktree dirname(<root>/.git) is <root> — but it costs a process every time.
  #
  # None of wiki_project_dir's seven are this task's to cut: it is the shared vendored
  # resolver every other memory-wiki entry point uses, and forking it here so the hook is
  # faster is precisely how a project's memory and its wiki end up in different directories.
  INJ_BUDGET=9
  inj_count_spawns "$INJTMP/payload.json"
  inj_got="$INJ_SPAWNS"; inj_budget_out="$INJ_SPAWN_OUT"
  # The shimmed run must still produce the RIGHT output, or a shim that perturbs the code
  # under test could report a flattering number for a run that did nothing at all. Both
  # numeric checks below are gated on this: while the hook did not yet exist, they reported
  # 0 spawns and PASSed — the best budget in the suite, for a script that was not there.
  inj_shim_ok=0
  [[ "$inj_budget_out" == *'demo: fatal: cannot open state file'* \
     && "$inj_budget_out" == *'## Memory wiki'* ]] && inj_shim_ok=1
  if (( inj_shim_ok )); then
    pass "spawn budget: shimmed run still injects the region"
  else
    fail "spawn budget: shimmed run still injects the region" "$inj_budget_out"
  fi
  if (( inj_shim_ok )) && [[ "$inj_got" -le "$INJ_BUDGET" ]]; then
    pass "spawn budget: wiki-inject.sh uses $inj_got process(es) (budget $INJ_BUDGET)"
  else
    fail "spawn budget: wiki-inject.sh" "spawned $inj_got processes, budget is $INJ_BUDGET
shimmed run injected the region: $inj_shim_ok (0 makes the count above meaningless)
called: $(sort "$INJLOG" | uniq -c | tr '\n' ' ')
On Windows each spawn costs 0.15-1.1s in a SessionStart hook."
  fi
  # ...and the two opt-outs must cost nothing at all. They are the first two lines of the
  # script for that reason: a guard that fires only after the memory dir has been resolved
  # would already have spent the whole budget.
  inj_count_spawns "$INJTMP/payload.json" MEMORY_WIKI_NO_INJECT=1
  inj_off="$INJ_SPAWNS"; inj_off_out="$INJ_SPAWN_OUT"
  if (( inj_shim_ok )) && [[ "$inj_off" -eq 0 && -z "$inj_off_out" ]]; then
    pass "spawn budget: MEMORY_WIKI_NO_INJECT short-circuits before any process starts"
  else
    fail "spawn budget: MEMORY_WIKI_NO_INJECT short-circuits before any process starts" \
      "spawned $inj_off processes, output=[$inj_off_out]
called: $(sort "$INJLOG" | uniq -c | tr '\n' ' ')"
  fi
  rm -rf "$INJSHIM"

  # --- region pairing: the reader must agree with the writer ---
  # write_region in bin/wiki-index.py pairs the LAST BEGIN before the first END that follows
  # it, not the first BEGIN. It ships that rule because the naive pairing destroyed content on
  # a file carrying a leftover dangling BEGIN — the run swallowed every foreign line between
  # the stale marker and the new END. A reader that disagrees with the writer about which span
  # is *the* region injects exactly those foreign lines, so pin the reader to the same rule.
  # Second case: a BEGIN with no END at all is not a region running to end of file.
  printf '%s\n' '# Wiki index' '' \
    '<!-- BEGIN memory-wiki (managed; do not edit by hand) -->' \
    'INJ-STALE-LEFTOVER' '' \
    '<!-- BEGIN memory-wiki (managed; do not edit by hand) -->' \
    '## Map' \
    '- [[project_demo]] — the live region' \
    '<!-- END memory-wiki -->' > "$INJWIKI/index.md"
  inj_run "$INJTMP/payload.json"; inj_pair_out="$INJ_OUT"; inj_pair_rc=$INJ_RC
  printf '%s\n' '# Wiki index' '' \
    '<!-- BEGIN memory-wiki (managed; do not edit by hand) -->' \
    'INJ-ORPHAN-TAIL' > "$INJWIKI/index.md"
  inj_run "$INJTMP/payload.json"; inj_orph_out="$INJ_OUT"; inj_orph_rc=$INJ_RC
  inj_bad=""
  [[ $inj_pair_rc -eq 0 && $inj_orph_rc -eq 0 ]] \
    || inj_bad="$inj_bad rc dangling=$inj_pair_rc orphan=$inj_orph_rc;"
  [[ "$inj_pair_out" == *'[[project_demo]]'* ]] || inj_bad="$inj_bad the well-formed pair's body was not injected;"
  [[ "$inj_pair_out" != *'INJ-STALE-LEFTOVER'* ]] || inj_bad="$inj_bad injected the line above the stale BEGIN;"
  [[ -z "$inj_orph_out" ]] || inj_bad="$inj_bad an unterminated BEGIN injected to end of file;"
  if [[ -z "$inj_bad" ]]; then
    pass "inject: region pairing matches write_region (last BEGIN, first END after it)"
  else
    fail "inject: region pairing matches write_region (last BEGIN, first END after it)" "$inj_bad
--- dangling BEGIN ---
$inj_pair_out
--- unterminated BEGIN ---
$inj_orph_out"
  fi

  rm -rf "$INJPDIR"
fi
rm -rf "$INJPROJ" "$INJTMP"

# --- hooks: the manifest Claude Code actually reads ---
# Parsed, not grepped. Two independent failures live here and both are silent: a command that
# does not begin with the literal ${CLAUDE_PLUGIN_ROOT}/ is never expanded and the hook dies at
# load time with "Shell substitution failed ... (detail withheld)"; and a SessionStart matcher
# that does not name wiki-inject.sh means the whole read half of memory-wiki never runs.
#
# The count assertion is load-bearing, not decoration. "*Every* command starts with
# ${CLAUDE_PLUGIN_ROOT}/" is vacuously true of a manifest that parses to {} — which is exactly
# the false-pass shape this harness keeps producing — so the number of commands found is
# asserted before anything is asserted about them.
HOOKSJSON="$PLUGIN/hooks/hooks.json"
hooks_dump="$("$PYBIN" -c "
import json,sys
d = json.load(open(sys.argv[1]))
for event, matchers in sorted(d.get('hooks', {}).items()):
    for m in matchers:
        for h in m.get('hooks', []):
            print('%s\t%s\t%s' % (event, h.get('command',''), h.get('statusMessage','')))
" "$HOOKSJSON" 2>&1)"; hooks_rc=$?
hooks_bad=""; hooks_n=0; hooks_inject=0
if [[ $hooks_rc -ne 0 || -z "$hooks_dump" ]]; then
  hooks_bad="hooks.json did not parse into any hook command (rc=$hooks_rc):
$hooks_dump"
else
  while IFS=$'\t' read -r hk_event hk_cmd hk_status; do
    [[ -z "$hk_event$hk_cmd" ]] && continue
    hooks_n=$((hooks_n + 1))
    # The literal string, not a shell expansion of it — hence the single quotes.
    [[ "$hk_cmd" == '${CLAUDE_PLUGIN_ROOT}/'* ]] \
      || hooks_bad="$hooks_bad
      $hk_event: command does not start with \${CLAUDE_PLUGIN_ROOT}/ : $hk_cmd"
    if [[ "$hk_event" == "SessionStart" && "$hk_cmd" == *'/bin/wiki-inject.sh' ]]; then
      hooks_inject=1
      [[ -n "$hk_status" ]] || hooks_bad="$hooks_bad
      SessionStart wiki-inject.sh has no statusMessage"
    fi
  done <<< "$hooks_dump"
  (( hooks_n > 0 )) || hooks_bad="$hooks_bad
      no hook commands declared at all"
  (( hooks_inject )) || hooks_bad="$hooks_bad
      no SessionStart command ending in /bin/wiki-inject.sh"
fi
if [[ -z "$hooks_bad" ]]; then
  pass "hooks: SessionStart declares wiki-inject with \${CLAUDE_PLUGIN_ROOT} ($hooks_n command(s))"
else
  fail "hooks: SessionStart declares wiki-inject with \${CLAUDE_PLUGIN_ROOT}" "$hooks_bad"
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
