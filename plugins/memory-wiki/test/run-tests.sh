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
MJ="$REPO/.claude-plugin/marketplace.json"
# plugin_version <plugin-dir>  -> the version in that plugin's .claude-plugin/plugin.json
plugin_version() {
  "$PYBIN" -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" \
    "$1/.claude-plugin/plugin.json" 2>&1
}
# marketplace_version <name>   -> that plugin's version in the root marketplace.json
marketplace_version() {
  "$PYBIN" -c "
import json,sys
e=[p for p in json.load(open(sys.argv[1]))['plugins'] if p['name']==sys.argv[2]]
print(e[0]['version'] if e else 'MISSING')" "$MJ" "$1" 2>&1
}
PV="$(plugin_version "$PLUGIN")"
MV="$(marketplace_version memory-wiki)"

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

# --- lint: a flag that came last with no value must terminate ---
# `shift 2` shifts nothing and returns non-zero when there is no $2, so a bare `shift 2` spins
# the option loop forever rather than reporting anything. The caller that makes this reachable
# is a model — skills/ingest/SKILL.md passes two of these flags in its verify step — and a Bash
# call that never returns is the worst failure shape this plugin has.
#
# `timeout` IS the assertion here, not a safety net: rc 124 is "still running", which is exactly
# the regression. Without the bound a reintroduced hang would wedge this suite instead of failing.
if command -v timeout >/dev/null 2>&1; then
  argv_bad=""
  for argv_flag in --sources --atlas --concepts; do
    timeout 5 bash "$PLUGIN/bin/wiki-lint.sh" "$HERE/fixtures/clean/wiki" "$argv_flag" \
      >/dev/null 2>&1
    argv_rc=$?
    [[ $argv_rc -eq 0 ]] || argv_bad="$argv_bad $argv_flag(rc=$argv_rc)"
  done
  if [[ -z "$argv_bad" ]]; then
    pass "lint: a valueless trailing flag terminates"
  else
    fail "lint: a valueless trailing flag terminates" \
      "non-zero rc (124 = still running when the bound expired):$argv_bad"
  fi
else
  echo "SKIP: lint: valueless trailing flag (no timeout on this machine)"
fi

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

# --- index: machinery files are never read as pages ---
# _SKIP is what keeps index.md, log.md and README.md out of the page set, and none of the
# fixtures contains one, so the constant shipped unexercised: emptying it left every golden
# green. It is not cosmetic — index.md is a file this script itself writes, so a regression
# feeds the generator's own output back in as a page on the very next run.
#
# The three machinery files here carry *valid page frontmatter*, symptom and all. That is the
# whole point: `-s`-style presence would prove nothing, and only a page-shaped one can show up
# in the render if the skip stops working.
SKPWIKI="$(mktemp -d)"
for skp in index log README; do
  printf '%s\n' '---' "name: Machinery $skp" \
    "description: MACHINERY_$skp must never be rendered as a page" \
    'type: project' 'status: active' 'last_accessed: 2026-09-08' \
    "symptom: \"MACHINERY_$skp\"" 'sources: ["[[2026-W99]]"]' '---' > "$SKPWIKI/$skp.md"
done
printf '%s\n' '---' 'name: Real Page' 'description: the only page here' \
  'type: project' 'status: active' 'last_accessed: 2026-09-08' \
  'sources: ["[[2026-W35]]"]' '---' > "$SKPWIKI/project_real.md"
skp_out="$("$PYBIN" "$PLUGIN/bin/wiki-index.py" --wiki "$SKPWIKI" --render-only 2>&1 | tr -d '\r')"
skp_want='## Map
- [[project_real]] — the only page here

## Sources ingested
[[2026-W35]]'
rm -rf "$SKPWIKI"
if [[ "$skp_out" == "$skp_want" ]]; then
  pass "index: index/log/README are never rendered as pages"
else
  fail "index: index/log/README are never rendered as pages" \
    "$(diff <(echo "$skp_want") <(echo "$skp_out") || true)"
fi

# --- index: sources: parses the same way wiki-lint.sh scans it ---
# Two parsers read this one field. wiki-lint.sh scans the raw line with `\[\[[^]|#]*`, so a
# bracketless comma list is two resolvable links to it; parse_list read the whole value as one
# name ("2026-W35]], [[2026-W36") and rendered that into the injected region as a broken link,
# while lint went on reporting clean. The bracketless form is what a model writes — it is
# reading a format full of [[...]] — so it is the realistic input, not a contrived one.
#
# The assertion is the deduplicated Sources line across BOTH spellings: with the two parsers
# disagreeing the set holds three names instead of two and each source is listed twice.
SRCWIKI="$(mktemp -d)"; SRCSRC="$(mktemp -d)"
: > "$SRCSRC/2026-W35.md"; : > "$SRCSRC/2026-W36.md"
printf '%s\n' '---' 'name: Flow Form' 'description: sources as a YAML flow list' \
  'type: project' 'status: active' 'last_accessed: 2026-09-08' \
  'sources: ["[[2026-W35]]", "[[2026-W36]]"]' '---' \
  'Links [[project_bare-form]].' > "$SRCWIKI/project_flow-form.md"
printf '%s\n' '---' 'name: Bare Form' 'description: the same two sources, no flow brackets' \
  'type: project' 'status: active' 'last_accessed: 2026-09-08' \
  'sources: [[2026-W35]], [[2026-W36]]' '---' \
  'Links [[project_flow-form]].' > "$SRCWIKI/project_bare-form.md"
src_out="$("$PYBIN" "$PLUGIN/bin/wiki-index.py" --wiki "$SRCWIKI" --render-only 2>&1 | tr -d '\r' \
  | sed -n '/^## Sources ingested$/{n;p;}')"
src_lint="$(bash "$PLUGIN/bin/wiki-lint.sh" "$SRCWIKI" --sources "$SRCSRC" 2>&1)"
rm -rf "$SRCWIKI" "$SRCSRC"
src_bad=""
[[ "$src_out" == '[[2026-W35]], [[2026-W36]]' ]] \
  || src_bad="$src_bad rendered Sources line: [$src_out];"
grep -qE '^  broken links +: 0$' <<< "$src_lint" \
  || src_bad="$src_bad lint did not report 0 broken links;"
if [[ -z "$src_bad" ]]; then
  pass "index: a bracketless comma list in sources: parses as wiki-lint.sh reads it"
else
  fail "index: a bracketless comma list in sources: parses as wiki-lint.sh reads it" "$src_bad
$src_lint"
fi

# --- index: a repeated frontmatter key keeps its FIRST value, as the linter reads it ---
# wiki-lint.sh and wiki-lint.ps1 both validate the first occurrence of a key. An index that read
# the last one instead would let a page lint clean on one value and be injected on another.
DUPWIKI="$(mktemp -d)"
printf '%s\n' '---' 'name: Dup' 'description: FIRST_VALUE' 'type: project' 'status: active' \
  'last_accessed: 2026-09-08' 'sources: ["[[2026-W35]]"]' 'description: SECOND_VALUE' '---' \
  > "$DUPWIKI/project_dup.md"
dup_out="$("$PYBIN" "$PLUGIN/bin/wiki-index.py" --wiki "$DUPWIKI" --render-only 2>&1 | tr -d '\r')"
dup_list="$("$PYBIN" "$PLUGIN/bin/wiki-index.py" --wiki "$DUPWIKI" --list-pages 2>&1 | tr -d '\r')"
rm -rf "$DUPWIKI"
if [[ "$dup_out" == *'[[project_dup]] — FIRST_VALUE'* && "$dup_out" != *SECOND_VALUE* \
      && "$dup_list" == 'project_dup | project | FIRST_VALUE' ]]; then
  pass "index: a repeated frontmatter key keeps its first value"
else
  fail "index: a repeated frontmatter key keeps its first value" "render:
$dup_out
list-pages:
$dup_list"
fi

# --- index: a page that is not UTF-8 is named, not a traceback ---
# Such a page crashed every render, index write and page listing with an uncaught
# UnicodeDecodeError. The run must still fail — an index silently missing a page is worse — but
# with the file named, so the ingest skill can report what to fix.
NUTFWIKI="$(mktemp -d)"
printf '%s\n' '---' 'name: Fine' 'description: a fine page' 'type: project' 'status: active' \
  'last_accessed: 2026-09-08' 'sources: ["[[2026-W35]]"]' '---' > "$NUTFWIKI/project_fine.md"
printf -- '---\nname: Bad \xff\xfe\n---\n' > "$NUTFWIKI/project_latin1.md"
nutf_err="$("$PYBIN" "$PLUGIN/bin/wiki-index.py" --wiki "$NUTFWIKI" --render-only 2>&1 >/dev/null)"; nutf_rc=$?
rm -rf "$NUTFWIKI"
if [[ $nutf_rc -eq 1 && "$nutf_err" == *project_latin1.md*'not valid UTF-8'* \
      && "$nutf_err" != *Traceback* ]]; then
  pass "index: a non-UTF-8 page fails with its name, not a traceback"
else
  fail "index: a non-UTF-8 page fails with its name, not a traceback" "rc=$nutf_rc (want 1)
$nutf_err"
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
    # Not `pass`. A skip is absent coverage, and reporting it as a pass both inflates the
    # total and hides the absence. See the SKIP below the Windows-cwd check for the full note.
    echo "SKIP: paths: agrees with claude-memory's resolver (claude-memory not installed)"
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
REPO_PDIR="$(wiki_project_dir "$REPO" 2>/dev/null)"
scratch_project_dir() {
  local d
  d="$(wiki_project_dir "$1" 2>/dev/null)"
  [[ -z "$d" || "$d" == "$REPO_PDIR" || -e "$d" ]] && return 1
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

# The stub's literal bytes, and its count. These two lines are the ONLY thing this plugin
# writes into the file claude-memory and the user share, and every probe above them is a
# shape check that `Memory wiki: 999 active pages.` would satisfy just as well — so the text
# a reader actually sees, and the number that tells them whether the wiki is worth opening,
# were pinned nowhere.
#
# The count is load-bearing in both directions. fixtures/typed holds six pages, two of them
# non-active (one dormant, one superseded), so 4 is simultaneously the assertion that the
# status filter ran and that nothing outside wiki/*.md was counted. Bump this literal when the
# fixture gains a page — that edit is the point, not an annoyance.
idx_stub_want='Memory wiki: 4 active pages.
Full index (symptoms, map, sources ingested): `wiki/index.md` in this memory dir.'
if [[ "$idx_stub" == "$idx_stub_want" ]]; then
  pass "index: the MEMORY.md stub is exactly two lines and counts only active pages"
else
  fail "index: the MEMORY.md stub is exactly two lines and counts only active pages" \
    "$(diff <(echo "$idx_stub_want") <(echo "$idx_stub") || true)"
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
# this check would certify the exact bug it exists to catch: a pending list whose one blank
# line reads as a rollup named "".
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
# telling the ingest skill the entry landed immediately before it moves the inbox capture
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
# --pending-only it is not even an answer, since that stdout is a list of rollup names. Bytes
# again, for the reason given above.
NOWIKI="$(mktemp -d)"
mkdir -p "$NOWIKI/memory"
# One run with the streams kept apart: the report must be on stderr, behind that guard rather
# than instead of it, so stdout stays reserved for the work order.
bash "$PLAN" "$NOWIKI/memory" > "$NOWIKI/out" 2> "$NOWIKI/err"; nw_rc=$?
nw_out="$(cat "$NOWIKI/err")"
nw_stdout="$(wc -c < "$NOWIKI/out" | tr -d '[:space:]')"
nw_bytes="$(bash "$PLAN" "$NOWIKI/memory" --pending-only 2>&1 | wc -c | tr -d '[:space:]')"
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

# Every refused call must leave stdout empty too, because stdout is read as a work order or a
# pending list. One typo used to be enough: `--pending--only` was taken as MEMORY_DIR, the real
# path discarded, and the resulting "no wiki" report printed as though it were the answer. A
# second positional is refused for the same reason rather than silently winning.
ref_bad=""
REFTMP="$(mktemp -d)"
for bogus in '--pending--only' '--nope'; do
  bash "$PLAN" "$PLANFIX" "$bogus" > "$REFTMP/out" 2> "$REFTMP/err"; b_rc=$?
  b_out="$(wc -c < "$REFTMP/out" | tr -d '[:space:]')"
  b_err="$(cat "$REFTMP/err")"
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
rm -rf "$REFTMP"

# A page list that cannot be read must neither blank the work order nor read as "(none)". The
# trigger is a page that is not valid UTF-8, which wiki-index.py refuses by name. The pending and
# inbox sections do not depend on the page list and must survive it; the pages section must say
# it is unavailable, because "(none)" would have the skill re-author every page that exists.
UNAV="$(mktemp -d)"
cp -r "$PLANFIX" "$UNAV/memory"
printf -- '---\nname: Bad \xff\xfe\n---\n' > "$UNAV/memory/wiki/project_latin1.md"
bash "$PLAN" "$UNAV/memory" > "$UNAV/out" 2> "$UNAV/err"; unav_rc=$?
unav_out="$(cat "$UNAV/out")"; unav_err="$(cat "$UNAV/err")"
rm -rf "$UNAV"
unav_bad=""
[[ $unav_rc -eq 0 ]] || unav_bad="$unav_bad rc=$unav_rc;"
for needle in $'## Pending sources (2)\n2026-W35\n2026-W36' \
              $'## Existing pages (unavailable)\n' \
              $'## Inbox (1)\n2026-09-02-note.md'; do
  [[ "$unav_out" == *"$needle"* ]] || unav_bad="$unav_bad missing: ${needle%%$'\n'*};"
done
[[ "$unav_out" != *'## Existing pages ('[0-9]* ]] || unav_bad="$unav_bad pages section printed a count;"
[[ "$unav_err" == *project_latin1.md* ]] || unav_bad="$unav_bad stderr does not name the bad page;"
if [[ -z "$unav_bad" ]]; then
  pass "plan: an unreadable page list is reported as unavailable, not as a blank work order"
else
  fail "plan: an unreadable page list is reported as unavailable, not as a blank work order" "$unav_bad
--- stdout ---
$unav_out
--- stderr ---
$unav_err"
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

  # -Concepts, which parity above cannot reach: the helper has no slot for it and widening it
  # is ruled out just there. So the twin's half of that interface — the flag that makes
  # claude-memory's flat root concept_*.md files resolvable without counting them as pages —
  # otherwise ships with the bash side goldened and the PowerShell side never once invoked.
  #
  # Not a parity assertion and deliberately not goldened: it asserts the one thing the flag is
  # for. fixtures/typed links [[concept_root-heuristic]] twice, and that file lives in
  # concepts/, not wiki/ — so 0 broken links can only mean -Concepts was read and honoured.
  # Without it the same run reports 2. The page count is asserted alongside, because "resolvable
  # without becoming a page" is one contract and half of it would pass on its own.
  ps_conc="$(pwsh -NoProfile -File "$PLUGIN/bin/wiki-lint.ps1" \
    -WikiDir "$HERE/fixtures/typed/wiki" \
    -Sources "$HERE/fixtures/typed/sources" \
    -Concepts "$HERE/fixtures/typed/concepts" 2>&1 | tr -d '\r')"
  conc_bad=""
  grep -qE '^  broken links +: 0$' <<< "$ps_conc" || conc_bad="$conc_bad broken links is not 0;"
  grep -qE '^  pages +: 6$' <<< "$ps_conc" || conc_bad="$conc_bad pages is not 6;"
  if [[ -z "$conc_bad" ]]; then
    pass "lint.ps1: -Concepts resolves the flat root concepts without counting them"
  else
    fail "lint.ps1: -Concepts resolves the flat root concepts without counting them" "$conc_bad
$ps_conc"
  fi
else
  # Not `pass`. Nine parity assertions plus the -Concepts check collapse into this one line the
  # moment pwsh leaves PATH, and calling that a pass inflates the total by ten while hiding
  # that the entire PowerShell twin went unrun. See the SKIP below the Windows-cwd check.
  echo "SKIP: parity: the whole PowerShell twin suite (pwsh not on PATH)"
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
         bin/wiki-inject.sh bin/wiki-nudge.sh hooks/hooks.json \
         bin/_wiki-paths.sh bin/_wiki-hook.sh bin/_wiki-pending.sh assets/wiki-README.md \
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

# hook_run <plugin-root> <hook> <payload-file> [VAR=val ...]
#   -> sets HOOK_OUT (stdout+stderr), HOOK_RC and HOOK_BYTES, all from ONE invocation.
# The one runner every hook check in this suite goes through. Not called via $(...), which would
# run it in a subshell and discard all three.
#
# stderr is captured deliberately: a hook must be silent on *both* streams at session start.
# Output is captured to a file and measured in BYTES, because command substitution strips
# trailing newlines and a hook that printed one blank line would otherwise compare equal to "".
# Reading it back is builtins only, so the runner adds no process to any check.
#
# Three variables are pinned rather than inherited, because the suite is itself run from inside
# a Claude Code session that exports the first two:
#   CLAUDE_PLUGIN_ROOT — inherited, the hook would locate its bin/ through the *installed*
#     plugin and every check would silently exercise the cache instead of this checkout.
#   CLAUDE_PROJECT_DIR — the hooks prefer it over the payload's cwd, so inheriting it would
#     resolve every check onto the real repo instead of the throwaway project, and would make
#     the unparseable-payload checks test nothing. Checks of that shortcut pass it as a VAR=val,
#     which `env` applies after the unset.
#   CLAUDE_MEMORY_ROLLUP_FULL — a developer who exported it would turn every claude-memory trim
#     assertion into an assertion of nothing at all.
HOOK_OUT=""; HOOK_RC=0; HOOK_BYTES=0
HOOKCAP="$(mktemp -d)"
hook_run() {
  local root="$1" hook="$2" pf="$3" raw=""; shift 3
  env -u CLAUDE_PROJECT_DIR -u CLAUDE_MEMORY_ROLLUP_FULL CLAUDE_PLUGIN_ROOT="$root" "$@" \
    bash "$hook" < "$pf" > "$HOOKCAP/out" 2>&1
  HOOK_RC=$?
  # Byte semantics for the length below, set only after the hook ran so it never inherits them.
  local LC_ALL=C
  IFS= read -r -d '' raw < "$HOOKCAP/out"
  HOOK_BYTES=${#raw}
  while [[ "$raw" == *$'\n' ]]; do raw="${raw%$'\n'}"; done
  HOOK_OUT="$raw"
}

# inj_run <payload-file> [VAR=val ...]  -> sets INJ_OUT and INJ_RC for wiki-inject.sh.
INJ_OUT=""; INJ_RC=0
inj_run() { hook_run "$PLUGIN" "$INJHOOK" "$@"; INJ_OUT="$HOOK_OUT"; INJ_RC=$HOOK_RC; }

if [[ -z "$INJPDIR" ]]; then
  fail "inject: silent and exits 0 with no wiki" \
    "$INJPROJ resolves to $(wiki_project_dir "$INJPROJ"), which is this repo's own memory
dir or already exists; refusing to scaffold into it or delete it. Check \$TMPDIR."
else
  INJWIKI="$INJPDIR/memory/wiki"

  # These two run first because they need the wiki *absent*, but they are only reported far
  # below, after inj_emit_proof exists. Asserting them here would leave the suite's two
  # earliest silence checks with nothing but "rc 0 and no output" behind them — which
  # separates a crash from silence but not silence-by-accident: a DIR mis-resolution that
  # trips the `declare -f wiki_project_dir` bail in the hook satisfies both, and so does a
  # hook replaced wholesale by `exit 0`.
  #
  # Two shapes of "no wiki": no project memory dir at all, and a memory-enabled project
  # that never ran /memory-wiki:init.
  inj_run "$INJTMP/payload.json"; inj_a_out="$INJ_OUT"; inj_a_rc=$INJ_RC
  mkdir -p "$INJPDIR/memory"
  inj_run "$INJTMP/payload.json"; inj_b_out="$INJ_OUT"; inj_b_rc=$INJ_RC

  # A freshly scaffolded wiki holds nothing but the empty-wiki placeholder, and a section
  # header over "there is nothing here" is worse than no section. This is also the only
  # "both regions empty" case reachable without a fake atlas, since $HOME/.claude/memory-wiki
  # exists on no machine until Phase 4. The -f capture distinguishes "suppressed the
  # placeholder" from "wiki-init.sh silently wrote no index.md at all".
  bash "$PLUGIN/bin/wiki-init.sh" "$INJPROJ" >/dev/null 2>&1
  inj_run "$INJTMP/payload.json"; inj_ph_out="$INJ_OUT"; inj_ph_rc=$INJ_RC
  inj_ph_idx=0; [[ -f "$INJWIKI/index.md" ]] && inj_ph_idx=1

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

  # The two runs held back from above, now that there is something to gate them on.
  if [[ $inj_a_rc -eq 0 && $inj_b_rc -eq 0 && -z "$inj_a_out" && -z "$inj_b_out" \
        && $inj_emit_proof -eq 1 ]]; then
    pass "inject: silent and exits 0 with no wiki"
  else
    fail "inject: silent and exits 0 with no wiki" "no memory dir: rc=$inj_a_rc out=[$inj_a_out]
no wiki dir:   rc=$inj_b_rc out=[$inj_b_out]
emitting run rendered the symptom: $inj_emit_proof (must be 1, or 'silent' proves nothing)"
  fi
  if [[ $inj_ph_rc -eq 0 && -z "$inj_ph_out" && $inj_ph_idx -eq 1 \
        && $inj_emit_proof -eq 1 ]]; then
    pass "inject: a wiki rendering only the empty-wiki placeholder is suppressed"
  else
    fail "inject: a wiki rendering only the empty-wiki placeholder is suppressed" \
      "rc=$inj_ph_rc  index.md present: $inj_ph_idx  out=[$inj_ph_out]
emitting run rendered the symptom: $inj_emit_proof (must be 1, or 'silent' proves nothing)"
  fi

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
  # disturbing anything else — bash is invoked by absolute path for exactly that reason.
  # CLAUDE_PROJECT_DIR must be unset here or the hook never reaches the interpreter probe at
  # all, and this would quietly stop testing anything.
  INJ_OUT="$(env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT="$PLUGIN" \
    PATH="$INJTMP/no-such-bin" "${BASH:-bash}" "$INJHOOK" \
    < "$INJTMP/payload.json" 2>&1)"; INJ_RC=$?
  if [[ $INJ_RC -eq 0 && -z "$INJ_OUT" && $inj_emit_proof -eq 1 ]]; then
    pass "inject: no python runtime is a silent no-op"
  else
    fail "inject: no python runtime is a silent no-op" "rc=$INJ_RC out=[$INJ_OUT]
emitting run rendered the symptom: $inj_emit_proof (must be 1, or 'silent' proves nothing)"
  fi

  # The CLAUDE_PROJECT_DIR shortcut, which is what makes the python spawn avoidable on a real
  # Claude Code session start. Driven with a payload whose cwd is deliberately unusable, so a
  # pass can only mean the exported variable was preferred — and the output must be identical
  # to the payload-driven run, since both resolve through the same wiki_project_dir.
  printf '{"cwd":"","hook_event_name":"SessionStart"}' > "$INJTMP/blankcwd.json"
  inj_run "$INJTMP/blankcwd.json" CLAUDE_PROJECT_DIR="$INJPROJ"
  if [[ $INJ_RC -eq 0 && "$INJ_OUT" == "$inj_emit_out" && $inj_emit_proof -eq 1 ]]; then
    pass "inject: CLAUDE_PROJECT_DIR is preferred over the payload cwd"
  else
    fail "inject: CLAUDE_PROJECT_DIR is preferred over the payload cwd" "rc=$INJ_RC
$(diff <(echo "$inj_emit_out") <(echo "$INJ_OUT") || true)"
  fi

  # A directory — or a FIFO — sitting where index.md belongs. Both satisfy `-r`, and reading
  # one through the region extractor's redirect leaves its loop variable unassigned, which
  # under `set -u` exits 1 with two bash errors printed at session start. That is a direct
  # violation of the global constraint that a hook exits 0 unconditionally and stays silent,
  # so it is pinned rather than left to inspection.
  #
  # The FIFO run is wrapped in `timeout`, and not as a formality: the failure it guards
  # against is an unbounded block, so without a bound a regression would hang this suite
  # forever instead of reporting. rc 124 is timeout's "still running", and it fails the check
  # like any other non-zero. Both halves are skipped only if their setup cannot be performed.
  mv "$INJWIKI/index.md" "$INJTMP/index.md.bak"
  mkdir -p "$INJWIKI/index.md"
  inj_run "$INJTMP/payload.json"; inj_d_out="$INJ_OUT"; inj_d_rc=$INJ_RC
  rmdir "$INJWIKI/index.md"
  # inj_f_ran, not pre-set inj_f_rc=0/inj_f_out="": with the FIFO setup unavailable those two
  # defaults satisfy the assertion below on their own, so the check reported a pass for a half
  # that never ran. The dir half is unconditional, so the two halves are now reported apart.
  inj_f_out=""; inj_f_rc=0; inj_f_ran=0
  if command -v timeout >/dev/null 2>&1 && command -v mkfifo >/dev/null 2>&1 \
     && mkfifo "$INJWIKI/index.md" 2>/dev/null; then
    inj_f_ran=1
    inj_f_out="$(env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT="$PLUGIN" \
      timeout 10 bash "$INJHOOK" < "$INJTMP/payload.json" 2>&1)"; inj_f_rc=$?
    rm -f "$INJWIKI/index.md"
  fi
  mv "$INJTMP/index.md.bak" "$INJWIKI/index.md"
  if [[ $inj_d_rc -eq 0 && -z "$inj_d_out" && $inj_emit_proof -eq 1 ]]; then
    pass "inject: a directory at index.md is a silent no-op"
  else
    fail "inject: a directory at index.md is a silent no-op" "dir:  rc=$inj_d_rc out=[$inj_d_out]
emitting run rendered the symptom: $inj_emit_proof (must be 1, or 'silent' proves nothing)"
  fi
  if [[ $inj_f_ran -eq 0 ]]; then
    echo "SKIP: inject: a FIFO at index.md is a silent no-op (no timeout/mkfifo, or mkfifo refused)"
  elif [[ $inj_f_rc -eq 0 && -z "$inj_f_out" && $inj_emit_proof -eq 1 ]]; then
    pass "inject: a FIFO at index.md is a silent no-op"
  else
    fail "inject: a FIFO at index.md is a silent no-op" "fifo: rc=$inj_f_rc out=[$inj_f_out]
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
    # Not `pass`. A skip is absent coverage, and reporting it as a pass both inflates the
    # total and hides the absence — the same shape as this harness's false-pass history.
    # claude-memory's suite spells an unrunnable check this way for the same reason.
    echo "SKIP: inject: Windows-style cwd check (no cygpath on this machine)"
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
  # external binary a hook can reach on the front of PATH, run the hook, count the log. This
  # asserts the property the hooks actually care about (how many processes start) rather than a
  # wall-clock number that would be flaky. On this machine a spawn costs ~430 ms — 50 of them
  # measured 21.5 s — and both hooks block *every* session start. One shim serves both budgets.
  #
  # `bash` is shimmed too, so a hook that started a child script would be counted for it. Two
  # consequences, both deliberate:
  #   * every shim's shebang names the real bash by ABSOLUTE PATH instead of `/usr/bin/env bash`.
  #     With a `bash` shim on PATH, `env bash` would resolve to the shim, logging a spurious
  #     "bash" for every other shimmed call and running each shim under itself.
  #   * hooks under test are launched through $REALBASH rather than through PATH, so the
  #     harness's own invocation is not counted as one of the hook's spawns.
  #
  # CLAUDE_PLUGIN_ROOT is exported because Claude Code sets it, and because it pins the hook to
  # *this checkout*. CLAUDE_PROJECT_DIR is unset unless a check passes it, so each number belongs
  # to a named entry path instead of to whatever the surrounding session exported.
  SHIM="$(mktemp -d)"
  SHIMLOG="$SHIM/calls.log"; : > "$SHIMLOG"
  REALBASH="$(command -v bash 2>/dev/null)"
  [[ -n "$REALBASH" ]] || REALBASH="${BASH:-/bin/bash}"
  for bin in bash git cygpath sed awk grep tr wc cat head tail cut python python3 \
             basename dirname realpath readlink; do
    real="$(command -v "$bin" 2>/dev/null)" || continue
    [[ -z "$real" ]] && continue
    printf '#!%s\necho "%s" >> "%s"\nexec "%s" "$@"\n' \
      "$REALBASH" "$bin" "$SHIMLOG" "$real" > "$SHIM/$bin"
  done
  chmod +x "$SHIM"/*

  # count_spawns <hook> <payload-file> [VAR=val ...] -> sets SPAWN_OUT, SPAWNS and SPAWNS_PY.
  # Not called via $(...), which would discard all three. The PATH assignment is scoped to the
  # inner subshell so the wc/grep that read the log are never themselves counted.
  SPAWN_OUT=""; SPAWNS=0; SPAWNS_PY=0
  count_spawns() {
    local hook="$1" pf="$2"; shift 2
    : > "$SHIMLOG"
    SPAWN_OUT="$( PATH="$SHIM:$PATH"; env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT="$PLUGIN" \
      "$@" "$REALBASH" "$hook" < "$pf" 2>/dev/null )"
    SPAWNS="$(wc -l < "$SHIMLOG" | tr -d ' ')"
    # No `|| echo 0`: grep -c already prints 0 when it matches nothing, and the fallback would
    # append a second line, turning a numeric test into a syntax error on the happy path.
    SPAWNS_PY="$(grep -c '^python' "$SHIMLOG" 2>/dev/null)"; SPAWNS_PY="${SPAWNS_PY:-0}"
  }
  spawn_calls() { sort "$SHIMLOG" | uniq -c | tr '\n' ' '; }

  # wiki-inject.sh has two entry paths, and production takes the cheaper one:
  #
  #   payload path (CLAUDE_PROJECT_DIR unset, non-Claude hosts) — 2 processes
  #     1  git      one `rev-parse` inside wiki_project_dir answers every question it has
  #     1  python   parse the payload JSON for its cwd
  #
  #   fast path (CLAUDE_PROJECT_DIR exported, every real Claude Code session) — 1 process
  #     the git above; python is skipped entirely, and it is the most expensive spawn in the
  #     set (memory-inject.sh measures python at 1.1 s on Windows)
  #
  # Everything else is a bash builtin: region extraction is a `while read` loop, and the
  # mixed-form path conversion is wiki_to_mixed rather than a `cygpath -m`. The awk
  # wiki-lint.sh uses to measure the same region would be one spawn per file, two more here.
  INJ_BUDGET=2
  INJ_BUDGET_FAST=1
  count_spawns "$INJHOOK" "$INJTMP/payload.json"
  inj_got="$SPAWNS"; inj_budget_out="$SPAWN_OUT"
  # The shimmed run must still produce the RIGHT output, or a shim that perturbs the code
  # under test could report a flattering number for a run that did nothing at all. Every
  # numeric check below is gated on this: while the hook did not yet exist, they reported
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
called: $(spawn_calls)
On Windows each spawn costs 0.15-1.1s in a SessionStart hook."
  fi

  # The fast path, which is the one every real session start takes. Measured separately
  # rather than assumed from the payload-path number: what is being asserted is that the
  # exported cwd actually removes the python spawn, not merely that it is preferred.
  count_spawns "$INJHOOK" "$INJTMP/blankcwd.json" CLAUDE_PROJECT_DIR="$INJPROJ"
  inj_fast="$SPAWNS"; inj_fast_py="$SPAWNS_PY"
  inj_fast_ok=0
  [[ "$SPAWN_OUT" == *'demo: fatal: cannot open state file'* ]] && inj_fast_ok=1
  if (( inj_fast_ok )) && [[ "$inj_fast" -le "$INJ_BUDGET_FAST" && "$inj_fast_py" -eq 0 ]]; then
    pass "spawn budget: with CLAUDE_PROJECT_DIR set, $inj_fast process(es) and no python (budget $INJ_BUDGET_FAST)"
  else
    fail "spawn budget: with CLAUDE_PROJECT_DIR set" \
      "spawned $inj_fast processes (budget $INJ_BUDGET_FAST), python calls=$inj_fast_py
shimmed run injected the region: $inj_fast_ok (0 makes the count above meaningless)
called: $(spawn_calls)"
  fi

  # ...and the two opt-outs must cost nothing at all. They are the first two lines of the
  # script for that reason: a guard that fires only after the memory dir has been resolved
  # would already have spent the whole budget.
  count_spawns "$INJHOOK" "$INJTMP/payload.json" MEMORY_WIKI_NO_INJECT=1
  if (( inj_shim_ok )) && [[ "$SPAWNS" -eq 0 && -z "$SPAWN_OUT" ]]; then
    pass "spawn budget: MEMORY_WIKI_NO_INJECT short-circuits before any process starts"
  else
    fail "spawn budget: MEMORY_WIKI_NO_INJECT short-circuits before any process starts" \
      "spawned $SPAWNS processes, output=[$SPAWN_OUT]
called: $(spawn_calls)"
  fi

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

  # --- nudge: the ingest-pending reminder, on the same scratch project ---
  # Same discipline as the injection checks above, and for a sharper reason: two of these three
  # assertions are assertions of SILENCE, and a script that dies on its first line is silent,
  # and so is one that is not there at all. Every silent assertion below therefore carries
  # `$nudge_proof -eq 1` — set only by the one run that rendered the header AND a week name.
  # Replace bin/wiki-nudge.sh with `exit 0` and the emitting check fails, which drags every
  # silence check down with it. That coupling is the point of the variable.
  #
  # Silence is measured in BYTES, never with `-z` on a $(...) capture. Command substitution
  # strips trailing newlines, so a nudge that printed nothing but a blank line would compare
  # equal to "" and these checks would certify the exact defect they exist to catch:
  # session-start context spent on nothing, at every session start.
  NUDGEHOOK="$PLUGIN/bin/wiki-nudge.sh"
  NUDGEWEEK="$INJPDIR/memory/episodic/weekly"

  # nudge_run <payload-file> [VAR=val ...] -> NUDGE_OUT / NUDGE_RC / NUDGE_BYTES, via hook_run.
  NUDGE_OUT=""; NUDGE_RC=0; NUDGE_BYTES=0
  nudge_run() {
    hook_run "$PLUGIN" "$NUDGEHOOK" "$@"
    NUDGE_OUT="$HOOK_OUT"; NUDGE_RC=$HOOK_RC; NUDGE_BYTES="$HOOK_BYTES"
  }

  # The steady state, in its two shapes: a memory dir with no episodic/weekly at all, and one
  # with an empty weekly/ (what a memory-enabled project looks like before its first rollup).
  # Both must run before any rollup exists, so they are captured here and reported further
  # down, once there is a proof to gate them on. Reporting them here would leave the block's
  # two earliest checks backed by nothing but "rc 0 and no bytes" — which separates a crash
  # from silence, but not silence-by-accident: a hook replaced wholesale by `exit 0` passes
  # both, and so does one whose resolver failed to load.
  nudge_run "$INJTMP/payload.json"
  nudge_a_b="$NUDGE_BYTES"; nudge_a_rc=$NUDGE_RC; nudge_a_out="$NUDGE_OUT"
  mkdir -p "$NUDGEWEEK"
  nudge_run "$INJTMP/payload.json"
  nudge_b_b="$NUDGE_BYTES"; nudge_b_rc=$NUDGE_RC; nudge_b_out="$NUDGE_OUT"

  # The one emitting run, and the only check in the block that proves the hook can speak. Two
  # rollups, neither of them cited by a `- Sources:` line in the wiki's log.md.
  printf 'week 35\n' > "$NUDGEWEEK/2026-W35.md"
  printf 'week 36\n' > "$NUDGEWEEK/2026-W36.md"
  nudge_run "$INJTMP/payload.json"
  nudge_emit_out="$NUDGE_OUT"; nudge_emit_rc=$NUDGE_RC
  nudge_bad=""
  [[ $nudge_emit_rc -eq 0 ]] || nudge_bad="$nudge_bad rc=$nudge_emit_rc;"
  # The header, the count, both week names, and the command to run. The count is asserted as
  # the literal '2 weekly rollups' rather than as a bare digit: a nudge whose count disagreed
  # with the list it printed would still contain both names, and that is precisely the shape
  # that teaches the user to stop believing the number.
  for needle in \
    '## Memory wiki - ingest pending' \
    '2 weekly rollups' \
    '2026-W35' \
    '2026-W36' \
    'Run:  /memory-wiki:ingest'; do
    [[ "$nudge_emit_out" == *"$needle"* ]] || nudge_bad="$nudge_bad missing: $needle;"
  done
  # Exactly three lines. The count and the names share one line by design, so a fourth line is
  # session-start context nobody agreed to spend.
  nudge_n="$(printf '%s\n' "$nudge_emit_out" | wc -l | tr -d '[:space:]')"
  [[ "$nudge_n" == "3" ]] || nudge_bad="$nudge_bad printed $nudge_n line(s), want 3;"
  if [[ -z "$nudge_bad" ]]; then
    pass "nudge: names the pending rollups"
  else
    fail "nudge: names the pending rollups" "$nudge_bad
$nudge_emit_out"
  fi
  # The proof every silence check leans on. Emphatically not `-n "$nudge_emit_out"`: while the
  # script did not exist that variable held bash's "No such file or directory", which satisfies
  # a bare emptiness guard perfectly. Only the header plus a rendered week name proves the
  # emitting path ran.
  nudge_proof=0
  [[ "$nudge_emit_out" == *'## Memory wiki - ingest pending'* \
     && "$nudge_emit_out" == *'2026-W36'* ]] && nudge_proof=1

  if [[ $nudge_a_rc -eq 0 && $nudge_b_rc -eq 0 && "$nudge_a_b" == "0" && "$nudge_b_b" == "0" \
        && $nudge_proof -eq 1 ]]; then
    pass "nudge: silent when nothing is pending"
  else
    fail "nudge: silent when nothing is pending" "no weekly dir: rc=$nudge_a_rc bytes=$nudge_a_b out=[$nudge_a_out]
empty weekly/: rc=$nudge_b_rc bytes=$nudge_b_b out=[$nudge_b_out]
emitting run rendered the header and a week name: $nudge_proof (must be 1, or 'silent' proves nothing)"
  fi

  # Every remaining suppression is measured against the state that just produced three lines,
  # so a pass means the suppression fired — not that the project had nothing to say anyway.
  nudge_run "$INJTMP/payload.json" MEMORY_WIKI_NO_NUDGE=1
  nudge_off_b="$NUDGE_BYTES"; nudge_off_rc=$NUDGE_RC; nudge_off_out="$NUDGE_OUT"
  nudge_run "$INJTMP/payload.json" CLAUDE_MEMORY_CONSOLIDATING=1
  nudge_con_b="$NUDGE_BYTES"; nudge_con_rc=$NUDGE_RC; nudge_con_out="$NUDGE_OUT"

  # Four unusable payloads: not JSON, nothing on stdin, valid JSON with no cwd, and — not a
  # malformed payload at all — a cwd naming a directory that does not exist, which parses and
  # resolves and simply has no memory dir under it. None of them is the user's problem at
  # session start, so all four are silent and rc 0.
  printf '{"cwd":"%s","hook_event_name":"SessionStart"}' "$INJTMP/no-such-project" \
    > "$INJTMP/ghostcwd.json"
  nudge_run "$INJTMP/bad.json";       nudge_p1="$NUDGE_BYTES"; nudge_r1=$NUDGE_RC; nudge_o1="$NUDGE_OUT"
  nudge_run "$INJTMP/empty.json";     nudge_p2="$NUDGE_BYTES"; nudge_r2=$NUDGE_RC; nudge_o2="$NUDGE_OUT"
  nudge_run "$INJTMP/nocwd.json";     nudge_p3="$NUDGE_BYTES"; nudge_r3=$NUDGE_RC; nudge_o3="$NUDGE_OUT"
  nudge_run "$INJTMP/ghostcwd.json";  nudge_p4="$NUDGE_BYTES"; nudge_r4=$NUDGE_RC; nudge_o4="$NUDGE_OUT"
  if [[ $nudge_con_rc -eq 0 && $nudge_r1 -eq 0 && $nudge_r2 -eq 0 && $nudge_r3 -eq 0 \
        && $nudge_r4 -eq 0 && "$nudge_con_b" == "0" && "$nudge_p1" == "0" \
        && "$nudge_p2" == "0" && "$nudge_p3" == "0" && "$nudge_p4" == "0" \
        && $nudge_proof -eq 1 ]]; then
    pass "nudge: CLAUDE_MEMORY_CONSOLIDATING and an unusable payload are silent no-ops"
  else
    fail "nudge: CLAUDE_MEMORY_CONSOLIDATING and an unusable payload are silent no-ops" \
      "CONSOLIDATING: rc=$nudge_con_rc bytes=$nudge_con_b out=[$nudge_con_out]
not json:      rc=$nudge_r1 bytes=$nudge_p1 out=[$nudge_o1]
empty:         rc=$nudge_r2 bytes=$nudge_p2 out=[$nudge_o2]
no cwd:        rc=$nudge_r3 bytes=$nudge_p3 out=[$nudge_o3]
absent cwd:    rc=$nudge_r4 bytes=$nudge_p4 out=[$nudge_o4]
emitting run rendered the header and a week name: $nudge_proof (must be 1, or 'silent' proves nothing)"
  fi

  # --- spawn budget ---
  # The shim built for the injection budget above. `bash` is among the shimmed binaries because
  # the pending calculation once ran as a child `bash wiki-ingest-plan.sh`; a budget blind to
  # bash would not see one come back.
  #
  #   payload path (CLAUDE_PROJECT_DIR unset, non-Claude hosts) — 2 processes
  #     1  python   parse the payload JSON for its cwd
  #     1  git      one `rev-parse` inside wiki_project_dir answers every question it has
  #
  #   fast path (CLAUDE_PROJECT_DIR exported, every real Claude Code session) — 1 process
  #     the git above; python is skipped entirely
  #
  # Everything else is a bash builtin: wiki_pending is sourced from _wiki-pending.sh rather than
  # run as a child, and the list is joined by parameter expansion, not `paste`.
  NUDGE_BUDGET=2
  NUDGE_BUDGET_FAST=1
  count_spawns "$NUDGEHOOK" "$INJTMP/payload.json"
  nudge_got="$SPAWNS"; nudge_budget_out="$SPAWN_OUT"
  # The shimmed run must still produce the RIGHT output, or a shim that perturbed the code
  # under test could report a flattering number for a run that did nothing at all.
  nudge_shim_ok=0
  [[ "$nudge_budget_out" == *'## Memory wiki - ingest pending'* \
     && "$nudge_budget_out" == *'2026-W36'* ]] && nudge_shim_ok=1
  if (( nudge_shim_ok )); then
    pass "spawn budget: shimmed run still prints the nudge"
  else
    fail "spawn budget: shimmed run still prints the nudge" "$nudge_budget_out"
  fi
  if (( nudge_shim_ok )) && [[ "$nudge_got" -le "$NUDGE_BUDGET" ]]; then
    pass "spawn budget: wiki-nudge.sh uses $nudge_got process(es) (budget $NUDGE_BUDGET)"
  else
    fail "spawn budget: wiki-nudge.sh" "spawned $nudge_got processes, budget is $NUDGE_BUDGET
shimmed run printed the nudge: $nudge_shim_ok (0 makes the count above meaningless)
called: $(spawn_calls)
On Windows each spawn costs 0.15-1.1s in a SessionStart hook."
  fi

  # The fast path, measured rather than inferred: what is asserted is that the exported cwd
  # actually removes the python spawn. blankcwd.json carries an empty cwd, so output here can
  # only mean CLAUDE_PROJECT_DIR won.
  count_spawns "$NUDGEHOOK" "$INJTMP/blankcwd.json" CLAUDE_PROJECT_DIR="$INJPROJ"
  nudge_fast="$SPAWNS"; nudge_fast_py="$SPAWNS_PY"
  nudge_fast_ok=0
  [[ "$SPAWN_OUT" == *'2026-W36'* ]] && nudge_fast_ok=1
  if (( nudge_fast_ok )) && [[ "$nudge_fast" -le "$NUDGE_BUDGET_FAST" && "$nudge_fast_py" -eq 0 ]]; then
    pass "spawn budget: with CLAUDE_PROJECT_DIR set, $nudge_fast process(es) and no python (budget $NUDGE_BUDGET_FAST)"
  else
    fail "spawn budget: with CLAUDE_PROJECT_DIR set" \
      "spawned $nudge_fast processes (budget $NUDGE_BUDGET_FAST), python calls=$nudge_fast_py
shimmed run printed the nudge: $nudge_fast_ok (0 makes the count above meaningless)
called: $(spawn_calls)"
  fi

  # ...and the kill switch must cost nothing at all. It is the second line of the script for
  # that reason: a guard that fired only after the memory dir had been resolved would already
  # have spent the whole budget on a user who asked for none of it.
  count_spawns "$NUDGEHOOK" "$INJTMP/payload.json" MEMORY_WIKI_NO_NUDGE=1
  if (( nudge_shim_ok )) && [[ "$SPAWNS" -eq 0 && -z "$SPAWN_OUT" ]]; then
    pass "spawn budget: MEMORY_WIKI_NO_NUDGE short-circuits before any process starts"
  else
    fail "spawn budget: MEMORY_WIKI_NO_NUDGE short-circuits before any process starts" \
      "spawned $SPAWNS processes, output=[$SPAWN_OUT]
shimmed run printed the nudge: $nudge_shim_ok (0 makes the count above meaningless)
called: $(spawn_calls)"
  fi
  rm -rf "$SHIM"

  # The ledger closes it, and this is the round trip that matters at session start: wiki-log.sh
  # is the only writer of the `- Sources:` lines and wiki-ingest-plan.sh the only reader, so
  # citing both weeks must leave the nudge with nothing to say. A nudge that kept talking after
  # a completed ingest is one the user learns to ignore, which is the same as not having one.
  nudge_log="$(bash "$PLUGIN/bin/wiki-log.sh" --wiki "$INJWIKI" --op ingest \
    --title 'Nudge round trip' --date 2026-09-09 --sources '2026-W35, 2026-W36' 2>&1)"
  nudge_log_rc=$?
  nudge_run "$INJTMP/payload.json"
  nudge_q_b="$NUDGE_BYTES"; nudge_q_rc=$NUDGE_RC; nudge_q_out="$NUDGE_OUT"
  if [[ $nudge_log_rc -eq 0 && $nudge_q_rc -eq 0 && "$nudge_q_b" == "0" \
        && $nudge_off_rc -eq 0 && "$nudge_off_b" == "0" && $nudge_proof -eq 1 ]]; then
    pass "nudge: goes quiet once logged, and honours MEMORY_WIKI_NO_NUDGE"
  else
    fail "nudge: goes quiet once logged, and honours MEMORY_WIKI_NO_NUDGE" \
      "wiki-log.sh: rc=$nudge_log_rc  $nudge_log
after logging both:   rc=$nudge_q_rc bytes=$nudge_q_b out=[$nudge_q_out]
MEMORY_WIKI_NO_NUDGE: rc=$nudge_off_rc bytes=$nudge_off_b out=[$nudge_off_out]
emitting run rendered the header and a week name: $nudge_proof (must be 1, or 'silent' proves nothing)"
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
# BOTH SessionStart entries are required by name. They are two entries rather than one script
# doing both jobs because their outputs and their failure modes are unrelated, and a bug in the
# pending calculation must not be able to suppress the index injection — claude-memory
# registers its own two the same way. A manifest that quietly lost one of them would still
# satisfy every other assertion here, and the loss shows up at session start as nothing
# happening, which is also what a project with no wiki looks like.
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
hooks_bad=""; hooks_n=0; hooks_inject=0; hooks_nudge=0
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
    if [[ "$hk_event" == "SessionStart" && "$hk_cmd" == *'/bin/wiki-nudge.sh' ]]; then
      hooks_nudge=1
      [[ -n "$hk_status" ]] || hooks_bad="$hooks_bad
      SessionStart wiki-nudge.sh has no statusMessage"
    fi
  done <<< "$hooks_dump"
  (( hooks_n > 0 )) || hooks_bad="$hooks_bad
      no hook commands declared at all"
  (( hooks_inject )) || hooks_bad="$hooks_bad
      no SessionStart command ending in /bin/wiki-inject.sh"
  (( hooks_nudge )) || hooks_bad="$hooks_bad
      no SessionStart command ending in /bin/wiki-nudge.sh"
fi
if [[ -z "$hooks_bad" ]]; then
  pass "hooks: SessionStart declares wiki-inject and wiki-nudge with \${CLAUDE_PLUGIN_ROOT} ($hooks_n command(s))"
else
  fail "hooks: SessionStart declares wiki-inject and wiki-nudge with \${CLAUDE_PLUGIN_ROOT}" "$hooks_bad"
fi

# --- interop: claude-memory trims its rollup dump once this wiki covers the week ---
# The one block in this suite that drives a script belonging to the OTHER plugin,
# plugins/claude-memory/bin/memory-inject.sh. It lives here because memory-wiki is the
# consumer that motivates the behaviour — the trim exists so the wiki index does not have to
# share the session-start budget with 200 lines of the same week in prose — and because this
# repo has exactly one test harness. Nothing in claude-memory knows memory-wiki exists: the
# whole coupling is one file path, the region markers, and the `[[YYYY-Www]]` form the index
# cites rollups in, so it is asserted from the side that depends on it.
#
# What each check is worth, stated up front because check 1 asserts the *unchanged* behaviour
# and would pass just as happily against a memory-inject.sh in which the trim was never
# written at all:
#   * checks 1 and 3, and the uncovered-week check, fail if the trim ever fires when it must
#     not (no wiki / scaffolded but never ingested / populated, but not yet with this week)
#   * check 2 fails if the trim never fires, and its CLAUDE_MEMORY_ROLLUP_FULL half fails if
#     it always fires
# The pair is therefore bidirectional: neither "trim removed" nor "trim unconditional" is a
# green suite. Every assertion below is the PRESENCE of something the hook rendered, or an
# absence paired with a presence from the same capture — there is no bare "output was empty"
# anywhere here, so a memory-inject.sh replaced wholesale by `exit 0` fails all three rather
# than passing them.
CMROOT="$REPO/plugins/claude-memory"
CMHOOK="$CMROOT/bin/memory-inject.sh"
CMTMP="$(mktemp -d)"

# The rollup all three behavioural checks are driven against. Every section carries a marker
# whose presence or absence names exactly one property:
#   BULK_BODY_MARKER     the 200-line dump      — present iff the trim did NOT fire
#   OPEN_THREADS_MARKER  the section kept       — the transient continuity no wiki page holds
#   NEXT_SECTION_MARKER  the section after it   — absent proves extraction stopped at `## `
cm_write_rollup() {
  printf '%s\n' \
    '# 2026-W36' \
    '' \
    '## Narrative' \
    'The week in prose, all of which the wiki now covers page by page.' \
    'BULK_BODY_MARKER' \
    '' \
    '## Decisions' \
    '- decided a thing' \
    '' \
    '## Open threads' \
    '- OPEN_THREADS_MARKER: still unresolved' \
    '- a second thread' \
    '' \
    '## Next week' \
    'NEXT_SECTION_MARKER' > "$1"
}

# cm_run <project-dir> [VAR=val ...] -> sets CM_OUT (stdout+stderr) and CM_RC, through hook_run
# with CLAUDE_PLUGIN_ROOT pinned to claude-memory in THIS checkout.
CM_OUT=""; CM_RC=0
cm_run() {
  local proj="$1"; shift
  printf '{"session_id":"0000","transcript_path":"","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' \
    "$proj" > "$CMTMP/payload.json"
  hook_run "$CMROOT" "$CMHOOK" "$CMTMP/payload.json" "$@"
  CM_OUT="$HOOK_OUT"; CM_RC=$HOOK_RC
}

# Two throwaway projects, because "no wiki" and "an empty wiki" are different states of the
# same directory and one of them has to survive the other's scaffolding. scratch_project_dir
# is what keeps both off the user's live memory dir (see its comment).
CMPROJ="$(mktemp -d)"
( cd "$CMPROJ" && git init -q . ) >/dev/null 2>&1
CMPDIR="$(scratch_project_dir "$CMPROJ")"
CMPROJ2="$(mktemp -d)"
( cd "$CMPROJ2" && git init -q . ) >/dev/null 2>&1
CMPDIR2="$(scratch_project_dir "$CMPROJ2")"

if [[ -z "$CMPDIR" || -z "$CMPDIR2" ]]; then
  # Three separate fails, not one: a $TMPDIR problem must not quietly shrink the number of
  # checks this suite reports.
  cm_why="$CMPROJ resolves to $(wiki_project_dir "$CMPROJ") and $CMPROJ2 to
$(wiki_project_dir "$CMPROJ2"); one of them is this repo's own memory dir or already exists.
Refusing to scaffold into it or delete it. Check \$TMPDIR."
  fail "interop: no wiki -> claude-memory dumps the full rollup, unchanged" "$cm_why"
  fail "interop: populated wiki -> only Open threads, and ROLLUP_FULL restores the dump" "$cm_why"
  fail "interop: an empty wiki does not trim the rollup" "$cm_why"
else
  # --- state 1: memory-enabled, no wiki directory at all (the majority of projects) ---
  mkdir -p "$CMPDIR/memory/episodic/weekly"
  cm_write_rollup "$CMPDIR/memory/episodic/weekly/2026-W36.md"
  cm_run "$CMPROJ"; cm_nowiki_out="$CM_OUT"; cm_nowiki_rc=$CM_RC

  # --- state 2: the same project, scaffolded and really ingested, this week included ---
  # The typed fixture's pages cite only 2026-W35, so one page citing 2026-W36 is added: the trim
  # keys on the newest rollup's name appearing in the rendered index.
  bash "$PLUGIN/bin/wiki-init.sh" "$CMPROJ" >/dev/null 2>&1
  cp "$HERE/fixtures/typed/wiki"/*.md "$CMPDIR/memory/wiki/" 2>/dev/null
  printf '%s\n' '---' 'name: This Week' 'description: a page written from the week under test' \
    'type: concept' 'status: active' 'last_accessed: 2026-09-08' 'sources: ["[[2026-W36]]"]' \
    '---' > "$CMPDIR/memory/wiki/concept_this-week.md"
  "$PYBIN" "$PLUGIN/bin/wiki-index.py" --wiki "$CMPDIR/memory/wiki" >/dev/null 2>&1; cm_gen_rc=$?
  # The premise of check 2, asserted rather than assumed: the guard keys on the week's citation,
  # so an index that never carried one makes "the trim did not fire" mean nothing.
  cm_idx_ok=0
  grep -qF '[[2026-W36]]' "$CMPDIR/memory/wiki/index.md" 2>/dev/null && cm_idx_ok=1
  cm_run "$CMPROJ"; cm_trim_out="$CM_OUT"; cm_trim_rc=$CM_RC
  cm_run "$CMPROJ" CLAUDE_MEMORY_ROLLUP_FULL=1; cm_full_out="$CM_OUT"; cm_full_rc=$CM_RC

  # ...and the cap, on the same project because it is a property of the same extraction. An
  # `## Open threads` section of 80 lines: uncapped it injects all 80, which is a worse
  # session-start bill than the 200-line dump this whole task exists to retire.
  {
    printf '%s\n' '# 2026-W36' '' '## Narrative' 'BULK_BODY_MARKER' '' '## Open threads'
    printf -- '- thread %s\n' {01..80}
    printf '%s\n' '' '## Next week' 'NEXT_SECTION_MARKER'
  } > "$CMPDIR/memory/episodic/weekly/2026-W36.md"
  cm_run "$CMPROJ"; cm_cap_out="$CM_OUT"; cm_cap_rc=$CM_RC
  cm_cap_n="$(grep -c '^- thread ' <<< "$cm_cap_out")"; cm_cap_n="${cm_cap_n:-0}"

  # ...and the third guard condition: a rollup with no `## Open threads` heading at all. Having
  # nothing to keep means the full dump, not an empty Tier-2 block — the same wiki that trimmed
  # twice above is still
  # in place, so a pass here can only mean the rollup's own shape decided it.
  printf '%s\n' '# 2026-W36' '' '## Narrative' 'BULK_BODY_MARKER' '' \
    '## Next week' 'NEXT_SECTION_MARKER' > "$CMPDIR/memory/episodic/weekly/2026-W36.md"
  cm_run "$CMPROJ"; cm_noopen_out="$CM_OUT"; cm_noopen_rc=$CM_RC

  # ...and the shape half of a real corpus actually has. A week consolidated twice
  # appends a SECOND `# Week ...` document into the same file, so the rollup carries two
  # `## Open threads` sections with a foreign body between them. Four of the eight rollups in
  # this project's own memory dir look like this, so extracting only the first would drop half
  # the open threads on half the weeks — silently, and in the direction the user cannot see.
  #
  # The separator here is an h1, deliberately, because that is what it is in every doubled file
  # on disk: `SPLIT_H1_MARKER` absent is the assertion that an h1 closes a section. It is not
  # cosmetic. At least one real rollup has NO `## ` heading after its first open-threads
  # section, so a `## `-only terminator would run to end of file and present a whole second
  # rollup body as open threads.
  printf '%s\n' \
    '# Week 2026-W36' '' \
    '## Narrative' 'BULK_BODY_MARKER' '' \
    '## Open threads' '- FIRST_THREAD_MARKER' \
    '# Week 2026-W36 SPLIT_H1_MARKER' '' \
    '## Summary' 'SECOND_BODY_MARKER' '' \
    '## Open threads' '- SECOND_THREAD_MARKER' '' \
    '## Next week' 'NEXT_SECTION_MARKER' \
    > "$CMPDIR/memory/episodic/weekly/2026-W36.md"
  cm_run "$CMPROJ"; cm_dbl_out="$CM_OUT"; cm_dbl_rc=$CM_RC
  cm_dbl_n="$(grep -c '^## Open threads' <<< "$cm_dbl_out")"; cm_dbl_n="${cm_dbl_n:-0}"

  # ...and the state every project with a wiki is in each week between consolidation and
  # /memory-wiki:ingest: an index covering earlier weeks, and a newer rollup no page cites yet.
  # Trimmed, that week would be injected nowhere, so it must be dumped whole. The rollup is dated
  # into the future so `ls -t` picks it as the latest however quickly this block ran.
  cm_write_rollup "$CMPDIR/memory/episodic/weekly/2026-W37.md"
  touch -d '2099-01-01 00:00:00' "$CMPDIR/memory/episodic/weekly/2026-W37.md"
  cm_run "$CMPROJ"; cm_unc_out="$CM_OUT"; cm_unc_rc=$CM_RC
  rm -f "$CMPDIR/memory/episodic/weekly/2026-W37.md"
  cm_bad=""
  [[ $cm_unc_rc -eq 0 ]] || cm_bad="$cm_bad rc=$cm_unc_rc;"
  # Premise: the trim demonstrably fires on this same project for a week the index does cite.
  [[ $cm_idx_ok -eq 1 && "$cm_trim_out" != *'BULK_BODY_MARKER'* ]] \
    || cm_bad="$cm_bad the trim never fired on this project, so its not firing here proves nothing;"
  grep -qF '[[2026-W37]]' "$CMPDIR/memory/wiki/index.md" 2>/dev/null \
    && cm_bad="$cm_bad the index cites 2026-W37, so this is not the case under test;"
  for needle in '### 2026-W37.md' 'BULK_BODY_MARKER' 'NEXT_SECTION_MARKER'; do
    [[ "$cm_unc_out" == *"$needle"* ]] || cm_bad="$cm_bad missing: $needle;"
  done
  if [[ -z "$cm_bad" ]]; then
    pass "interop: a populated wiki that has not ingested the newest week keeps its full rollup"
  else
    fail "interop: a populated wiki that has not ingested the newest week keeps its full rollup" "$cm_bad
$cm_unc_out"
  fi

  # --- state 3: a second project, /memory-wiki:init run and nothing ingested ---
  mkdir -p "$CMPDIR2/memory/episodic/weekly"
  cm_write_rollup "$CMPDIR2/memory/episodic/weekly/2026-W36.md"
  bash "$PLUGIN/bin/wiki-init.sh" "$CMPROJ2" >/dev/null 2>&1
  cm_empty_idx=0; [[ -f "$CMPDIR2/memory/wiki/index.md" ]] && cm_empty_idx=1
  cm_run "$CMPROJ2"; cm_empty_out="$CM_OUT"; cm_empty_rc=$CM_RC

  # Check 1. The whole rollup, headings and all — asserting the sections *after* Open threads
  # too, because "the full dump" and "the trimmed section" differ precisely there.
  cm_bad=""
  [[ $cm_nowiki_rc -eq 0 ]] || cm_bad="$cm_bad rc=$cm_nowiki_rc;"
  for needle in \
    '## Memory - last week (Tier 2)' \
    '### 2026-W36.md' \
    'BULK_BODY_MARKER' \
    '## Open threads' \
    'OPEN_THREADS_MARKER' \
    'NEXT_SECTION_MARKER'; do
    [[ "$cm_nowiki_out" == *"$needle"* ]] || cm_bad="$cm_bad missing: $needle;"
  done
  if [[ -z "$cm_bad" ]]; then
    pass "interop: no wiki -> claude-memory dumps the full rollup, unchanged"
  else
    fail "interop: no wiki -> claude-memory dumps the full rollup, unchanged" "$cm_bad
$cm_nowiki_out"
  fi

  # Check 2. The trim itself, its boundary, its cap, and its escape hatch.
  cm_bad=""
  [[ $cm_gen_rc -eq 0 ]] || cm_bad="$cm_bad generator rc=$cm_gen_rc;"
  [[ $cm_idx_ok -eq 1 ]] \
    || cm_bad="$cm_bad index.md does not cite [[2026-W36]], so nothing here could have triggered the trim;"
  [[ $cm_trim_rc -eq 0 && $cm_full_rc -eq 0 && $cm_cap_rc -eq 0 && $cm_noopen_rc -eq 0 \
     && $cm_dbl_rc -eq 0 ]] \
    || cm_bad="$cm_bad rc trim=$cm_trim_rc full=$cm_full_rc cap=$cm_cap_rc no-open=$cm_noopen_rc doubled=$cm_dbl_rc;"
  # The section survives, and so does the framing that says which week it came from — a bare
  # `## Open threads` with no provenance is continuity the model cannot place.
  for needle in \
    '## Memory - last week (Tier 2)' \
    '### 2026-W36.md' \
    '## Open threads' \
    'OPEN_THREADS_MARKER'; do
    [[ "$cm_trim_out" == *"$needle"* ]] || cm_bad="$cm_bad trimmed run missing: $needle;"
  done
  [[ "$cm_trim_out" != *'BULK_BODY_MARKER'* ]] \
    || cm_bad="$cm_bad the trimmed run still carries the bulk body;"
  [[ "$cm_trim_out" != *'NEXT_SECTION_MARKER'* ]] \
    || cm_bad="$cm_bad extraction ran past the next ## heading;"
  # The escape hatch, asserted as byte equality with the no-wiki run rather than as "the
  # marker came back": the contract is the OLD output exactly, and nothing else about this
  # project changed between the two captures.
  [[ "$cm_full_out" == *'BULK_BODY_MARKER'* ]] \
    || cm_bad="$cm_bad CLAUDE_MEMORY_ROLLUP_FULL=1 did not restore the dump;"
  [[ "$cm_full_out" == "$cm_nowiki_out" ]] \
    || cm_bad="$cm_bad CLAUDE_MEMORY_ROLLUP_FULL=1 output differs from the no-wiki dump;"
  [[ "$cm_cap_out" == *'- thread 01'* ]] \
    || cm_bad="$cm_bad the 80-line run injected no thread lines at all;"
  [[ "$cm_cap_out" != *'BULK_BODY_MARKER'* ]] \
    || cm_bad="$cm_bad the 80-line run was not trimmed at all;"
  (( cm_cap_n >= 1 && cm_cap_n <= 60 )) \
    || cm_bad="$cm_bad injected $cm_cap_n of 80 thread lines, cap is 60;"
  for needle in 'BULK_BODY_MARKER' 'NEXT_SECTION_MARKER'; do
    [[ "$cm_noopen_out" == *"$needle"* ]] \
      || cm_bad="$cm_bad a rollup with no ## Open threads heading lost: $needle;"
  done
  # Both sections, and both headings: the count is asserted as well as the content, because a
  # run that concatenated the two bodies under one heading would still carry both markers.
  for needle in '- FIRST_THREAD_MARKER' '- SECOND_THREAD_MARKER'; do
    [[ "$cm_dbl_out" == *"$needle"* ]] \
      || cm_bad="$cm_bad doubled rollup: only some sections injected, missing $needle;"
  done
  (( cm_dbl_n == 2 )) \
    || cm_bad="$cm_bad doubled rollup injected $cm_dbl_n ## Open threads heading(s), want 2;"
  # ...and nothing that lies BETWEEN or AFTER them. SPLIT_H1_MARKER is the h1-terminator
  # assertion; SECOND_BODY_MARKER would appear too if the h1 failed to close section one.
  for needle in 'BULK_BODY_MARKER' 'SPLIT_H1_MARKER' 'SECOND_BODY_MARKER' 'NEXT_SECTION_MARKER'; do
    [[ "$cm_dbl_out" != *"$needle"* ]] \
      || cm_bad="$cm_bad doubled rollup injected foreign content: $needle;"
  done
  if [[ -z "$cm_bad" ]]; then
    pass "interop: populated wiki -> only Open threads, and ROLLUP_FULL restores the dump"
  else
    fail "interop: populated wiki -> only Open threads, and ROLLUP_FULL restores the dump" "$cm_bad
--- trimmed ---
$cm_trim_out
--- ROLLUP_FULL=1 ---
$cm_full_out
--- 80-line Open threads ($cm_cap_n thread lines injected) ---
$cm_cap_out
--- rollup with no ## Open threads heading ---
$cm_noopen_out
--- doubled rollup ($cm_dbl_n ## Open threads heading(s) injected) ---
$cm_dbl_out"
  fi

  # Check 3. /memory-wiki:init and no ingest: the user would otherwise lose the rollup and
  # gain nothing, which is one reason the guard keys on the week being cited in the index
  # rather than on the wiki directory existing.
  cm_bad=""
  [[ $cm_empty_rc -eq 0 ]] || cm_bad="$cm_bad rc=$cm_empty_rc;"
  [[ $cm_empty_idx -eq 1 ]] \
    || cm_bad="$cm_bad wiki-init.sh wrote no index.md, so this project is not the case under test;"
  for needle in \
    '## Memory - last week (Tier 2)' \
    'BULK_BODY_MARKER' \
    '## Open threads' \
    'NEXT_SECTION_MARKER'; do
    [[ "$cm_empty_out" == *"$needle"* ]] || cm_bad="$cm_bad missing: $needle;"
  done
  if [[ -z "$cm_bad" ]]; then
    pass "interop: an empty wiki does not trim the rollup"
  else
    fail "interop: an empty wiki does not trim the rollup" "$cm_bad
$cm_empty_out"
  fi

  rm -rf "$CMPDIR" "$CMPDIR2"
fi
rm -rf "$CMPROJ" "$CMPROJ2" "$CMTMP"

# Check 4. claude-memory's own two version fields, guarded exactly like memory-wiki's at the
# top of this file — same two independent catalogs, same recurring failure mode, and this is
# the one task that touches the other plugin. Outside the $TMPDIR guard above, since it reads
# nothing but the two manifests.
#
# The literal is pinned, not merely the agreement: 0.3.5 already shipped WITHOUT this trim, so
# a checkout that carries the behaviour while still claiming 0.3.5 is describing a plugin that
# behaves differently from the one the user installed. Bump this line with the version.
cm_pv="$(plugin_version "$CMROOT")"
cm_mv="$(marketplace_version claude-memory)"
if [[ "$cm_pv" == "$cm_mv" && "$cm_pv" == "0.3.6" ]]; then
  pass "interop: claude-memory version parity ($cm_pv)"
else
  fail "interop: claude-memory version parity" "plugin.json=$cm_pv  marketplace.json=$cm_mv  want=0.3.6"
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
  # Not `pass`. This is the only check in the suite that runs against a real corpus rather than
  # a fixture, so reporting its absence as a pass hides exactly the coverage a fresh machine
  # lacks. See the SKIP below the Windows-cwd check.
  echo "SKIP: smoke: real memory dir (none on this machine)"
fi

rm -rf "$HOOKCAP"
exit "$FAILED"
