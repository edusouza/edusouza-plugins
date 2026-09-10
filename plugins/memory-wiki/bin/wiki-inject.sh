#!/usr/bin/env bash
# SessionStart injection of the memory wiki index — the read half of memory-wiki.
#
# Takes the session's cwd — the CLAUDE_PROJECT_DIR Claude Code exports, falling back to the
# `cwd` in the hook payload JSON on stdin — resolves that project's memory dir worktree-aware,
# and prints the managed region of <memdir>/wiki/index.md followed by the cross-project atlas
# region. Nothing decides whether to do this: the index is in front of the model at every
# session start, and the model reads a page only when a line in that index matches what it is
# doing. The index line IS the affordance.
#
# THIS IS THE ONLY INJECTOR OF THE INDEX REGION (plan decision D-a). wiki-index.py writes a
# two-line *pointer* into MEMORY.md — the wiki's path and a one-line "read the index there" —
# never a copy of the rendered index. That is deliberate: on a machine where the harness
# auto-loads MEMORY.md, rendering the region into both places spends the injection budget
# twice for one set of facts, and this hook cannot detect that MEMORY.md was already loaded,
# so it could not compensate. One renderer, one injector, one copy in context.
#
# PERFORMANCE. This blocks *every* session start, and on this machine a process spawn costs
# ~430 ms measured (50 grep spawns took 21.5 s). So: bash builtins over subprocesses,
# parameter expansion over sed, one `while read` pass over a file rather than an awk or a grep
# per candidate, and the memory dir resolved exactly once and reused. Budgets, measured, both
# pinned by test/run-tests.sh with a PATH shim that logs every call:
#   1  when Claude Code exported CLAUDE_PROJECT_DIR — one `git rev-parse` inside
#      wiki_project_dir, and nothing else. The python that would parse the payload is skipped
#      entirely, and it is the most expensive spawn in the set (memory-inject.sh measures
#      python at 1.1 s on Windows).
#   2  without it (non-Claude hosts): that git, plus that python.
#   0  when either opt-out is set — the two guards are the first statements in the file.
# Region extraction and the mixed-form path conversion are bash builtins and cost nothing.
#
# This was 9 before _wiki-paths.sh was re-vendored from claude-memory 0.3.5; see that file's
# header for the resolver bug that cost the other seven.
#
# Silent, exit 0, always. A hook that errors visibly at session start is worse than one that
# no-ops, and every one of these is a normal state rather than a fault: the recursion guard,
# the opt-out, no python, an unparseable or absent cwd, a project with no wiki, and a wiki
# whose regions are empty or hold nothing but the empty-wiki placeholder.
set -uo pipefail

# --- guards: before any work, so an opted-out session start spawns nothing ---
# CLAUDE_MEMORY_CONSOLIDATING matches claude-memory's recursion guard: a headless
# consolidation invocation must not be handed the wiki it is about to write into.
[[ -n "${CLAUDE_MEMORY_CONSOLIDATING:-}" ]] && exit 0
[[ -n "${MEMORY_WIKI_NO_INJECT:-}" ]] && exit 0

# Locate our own bin/. Claude Code sets CLAUDE_PLUGIN_ROOT; the fallback is pure parameter
# expansion rather than the usual `$(cd "$(dirname ...)" && pwd)` because that idiom costs a
# `dirname` process and a subshell for a value only ever used to source a sibling file.
DIR="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin}"
if [[ -z "$DIR" || ! -f "$DIR/_wiki-paths.sh" ]]; then
  SELF="${BASH_SOURCE[0]}"
  DIR="${SELF%/*}"
  [[ "$DIR" == "$SELF" ]] && DIR="."
fi
# shellcheck source=_wiki-paths.sh
. "$DIR/_wiki-paths.sh" 2>/dev/null
# The single guard, deliberately: `.` returns the status of the *last statement* in the file it
# sourced, so `|| exit 0` on the source line would be at the mercy of whatever that happens to
# be. Whether the resolver is actually usable is the question, and this is the question.
declare -f wiki_project_dir >/dev/null 2>&1 || exit 0

# --- the payload ---
# `read -d ''` consumes the whole stream with a builtin; `$(cat)` would cost a process. The
# tty guard keeps a hand-run of this script from hanging on a terminal that will never send
# anything — a no-op is the right answer there too.
#
# stdin is drained here even on the path that turns out not to need it: leaving the payload
# unread would make Claude Code's writer take an EPIPE, and draining it costs nothing.
PAYLOAD=""
if [[ ! -t 0 ]]; then
  IFS= read -r -d '' PAYLOAD || true
fi

# Prefer the cwd Claude Code already exported, exactly as claude-memory's memory-inject.sh
# does, and only pay for python to parse the payload when it is absent (non-Claude hosts).
# Both land on the same memory dir: wiki_project_dir maps a repo root, any subdirectory of
# it, and any linked worktree of it to one and the same main-worktree root. This is not a
# corner: python is the most expensive spawn this hook can make, and on a normal Claude Code
# session start it is now never made at all.
CWD="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$CWD" ]]; then
  [[ -z "$PAYLOAD" ]] && exit 0

  PYBIN=""
  if command -v python >/dev/null 2>&1; then
    PYBIN="python"
  elif command -v python3 >/dev/null 2>&1; then
    PYBIN="python3"
  else
    exit 0
  fi

  # Every malformed shape lands on the empty string and therefore on a silent exit: not JSON,
  # JSON that is not an object, an object with no `cwd`, a null `cwd`. A here-string rather
  # than a pipe, so this costs one process and not one process plus a forked writer.
  CWD="$("$PYBIN" -c '
import sys, json
try:
    d = json.loads(sys.stdin.read())
    v = d.get("cwd") if isinstance(d, dict) else None
    if isinstance(v, str) and v:
        sys.stdout.write(v)
except Exception:
    pass' <<< "$PAYLOAD" 2>/dev/null || true)"
  CWD="${CWD%$'\r'}"
fi
[[ -z "$CWD" ]] && exit 0

# Worktree-aware, and resolved exactly once: a linked worktree shares the MAIN repo's memory
# dir. This is the shared vendored resolver every other memory-wiki entry point uses — a
# faster private copy here is precisely how a project's memory and its wiki end up in
# different directories.
MEMDIR="$(wiki_project_dir "$CWD")/memory"
WIKI="$MEMDIR/wiki"
[[ -d "$WIKI" ]] || exit 0   # project has no wiki -> nothing to inject

# --- region extraction ---
# The pair used is the LAST BEGIN before the first END that follows it. That is not the naive
# "first BEGIN, first END": it is write_region's rule in bin/wiki-index.py, and the reader has
# to agree with the writer about which span is *the* region. write_region ships that rule
# because the naive pairing destroyed content on a file carrying a leftover dangling BEGIN —
# it spanned the stale marker and deleted every foreign line beneath it. A reader using the
# naive rule injects exactly those foreign lines into the model's context instead. On a
# well-formed file the two coincide; the difference only shows up on the malformed file, which
# is the only case where it matters.
#
# With no well-formed pair at all the region is empty. It is never read as "BEGIN to end of
# file" — same reason: an unterminated marker is not a licence to swallow the rest of a file.
#
# Pure bash. `while read` over a file is a builtin, so this costs no process; the awk the
# linter uses to measure the budget would be one spawn per file, ~430 ms each, here. Markers
# are compared on the whitespace-stripped line exactly as write_region does, and a trailing CR
# is stripped so a CRLF index.md reads identically to an LF one.
WIKI_BEGIN='<!-- BEGIN memory-wiki (managed; do not edit by hand) -->'
WIKI_END='<!-- END memory-wiki -->'
# wiki-index.py's EMPTY constant. A wiki rendering only this is treated as empty: a section
# header over "there is nothing here" is worse than no section at all.
WIKI_EMPTY='(no pages yet — run /memory-wiki:ingest)'

REGION=""
extract_region() {           # extract_region <file>  -> sets REGION ("" when there is none)
  REGION=""
  local file="${1:-}" line="" t="" buf="" inside=0 closed=0
  # -f, not -r. `-r` is true of a *directory* at this path, and the redirect below then
  # fails, leaving `line` unassigned for the `[[ -n "$line" ]]` that follows — which trips
  # `set -u` and exits 1 with two bash errors visible at session start, the exact thing this
  # hook must never do. A FIFO passes `-r` too and would block the read forever. `line` is
  # initialised as well so no future path can reach that test unassigned either.
  [[ -n "$file" && -f "$file" && -r "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    t="${line#"${line%%[![:space:]]*}"}"    # strip leading whitespace
    t="${t%"${t##*[![:space:]]}"}"          # strip trailing whitespace
    if [[ "$t" == "$WIKI_BEGIN" ]]; then
      # A second BEGIN before any END means the first was left dangling by something else.
      # Start over at the later, well-formed pair rather than spanning the leftover.
      buf=""; inside=1; continue
    fi
    if (( inside )) && [[ "$t" == "$WIKI_END" ]]; then
      closed=1; break
    fi
    (( inside )) && buf+="$line"$'\n'
  done < "$file"
  (( closed )) || return 0
  while [[ "$buf" == $'\n'* ]]; do buf="${buf#$'\n'}"; done
  while [[ "$buf" == *$'\n' ]]; do buf="${buf%$'\n'}"; done
  [[ -z "$buf" || "$buf" == "$WIKI_EMPTY" ]] && return 0
  REGION="$buf"
}

extract_region "$WIKI/index.md"; PROJ_REGION="$REGION"
# The cross-project atlas. Phase 4 populates this; until then the directory exists nowhere and
# the section is simply never emitted. The path matches what wiki-lint-project.sh hardcodes.
# MEMORY_WIKI_ATLAS_DIR exists so test/run-tests.sh can drive the emission branch before
# Phase 4 makes it reachable; it is not a user-facing setting.
ATLAS_DIR="${MEMORY_WIKI_ATLAS_DIR:-$HOME/.claude/memory-wiki}"
extract_region "$ATLAS_DIR/index.md"; ATLAS_REGION="$REGION"

[[ -z "$PROJ_REGION" && -z "$ATLAS_REGION" ]] && exit 0

# Mixed form (C:/foo/bar) is what the model needs to open the file on Windows, and it is
# harmless everywhere else. wiki_to_mixed is the vendored pure-bash conversion — the sibling
# documents it as "the shape `cygpath -m` produced" — so this costs no process. `cygpath -m`
# remains the fallback for one specific reason rather than as decoration: a stale plugin cache
# can leave an older _wiki-paths.sh on disk that predates wiki_to_mixed, and that is a
# documented failure mode in this repo, not a hypothetical.
mixed_path() {
  if declare -f wiki_to_mixed >/dev/null 2>&1; then
    wiki_to_mixed "$1"
  elif command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1" 2>/dev/null || printf '%s' "$1"
  else
    printf '%s' "$1"
  fi
}

# One header line per section: where the wiki is, and the rule for using it. The rule is the
# whole point (§6.2) — an index the model reads pages out of unconditionally is a context
# budget with no ceiling, while an index it consults and mostly ignores is a lookup table.
if [[ -n "$PROJ_REGION" ]]; then
  printf '\n## Memory wiki (%s) — read a linked page ONLY when a line below matches what you are doing; the line is the affordance.\n\n%s\n' \
    "$(mixed_path "$WIKI")" "$PROJ_REGION"
fi
if [[ -n "$ATLAS_REGION" ]]; then
  printf '\n## Memory wiki — cross-project atlas (%s) — same rule: read a linked page ONLY when a line below matches.\n\n%s\n' \
    "$(mixed_path "$ATLAS_DIR")" "$ATLAS_REGION"
fi

exit 0
