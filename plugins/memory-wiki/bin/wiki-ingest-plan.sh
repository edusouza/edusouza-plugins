#!/usr/bin/env bash
# Print the work order for one ingest run: which weekly rollups are still un-ingested, which
# pages already exist, and what is waiting in the inbox.
#
# Exists so the ingest skill spends its judgment on page content and none of it on globbing and
# bookkeeping. Asked to work out "which rollups are new" by listing directories itself, a model
# gets it subtly wrong in a way nobody notices until a week is missing from the wiki.
#
# It owns neither rule it reports. What is pending comes from wiki_pending (_wiki-pending.sh),
# the same function the session-start nudge calls; the page list comes from wiki-index.py, the
# same reader that renders the index. So the work order cannot disagree with the nudge about
# which weeks are left, or with the index about what a page's type and description are.
#
# Reports only; writes nothing, anywhere. Exit 0 always.
#
# Usage: wiki-ingest-plan.sh [MEMORY_DIR] [--pending-only]
set -uo pipefail

# Byte ordering. Every list below comes straight out of pathname expansion, which sorts using
# the current collation — under LC_ALL=C that is byte order, the same order `sort` would give
# and the same order wiki-index.py's code-point sort gives, at no process cost.
export LC_ALL=C

# Keyed on _wiki-pending.sh rather than _wiki-paths.sh: a CLAUDE_PLUGIN_ROOT naming an older
# install still carries the latter, and would hand this script a bin/ without its helpers.
DIR="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin}"
[[ -z "$DIR" || ! -f "$DIR/_wiki-pending.sh" ]] && DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_wiki-paths.sh
. "$DIR/_wiki-paths.sh"
# shellcheck source=_wiki-pending.sh
. "$DIR/_wiki-pending.sh"

MEM=""; PENDING_ONLY=0; BAD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pending-only) PENDING_ONLY=1; shift ;;
    # Anything else flag-shaped, and any second positional, is a caller bug — never a memory
    # dir. Accepting it as one turned a one-character typo (`--pending--only`) into a report on
    # a directory that does not exist, printed on stdout as though it were the answer. Same
    # reasoning as wiki-log.sh's unknown-argument rejection.
    --*) BAD="${BAD:+$BAD }$1"; shift ;;
    *)
      if [[ -n "$MEM" ]]; then BAD="${BAD:+$BAD }$1"; else MEM="$1"; fi
      shift ;;
  esac
done
if [[ -n "$BAD" ]]; then
  # Still exit 0 — this is a report command, and that contract holds on every path — but with
  # nothing whatsoever on stdout that could be read as a work order or a pending list.
  echo "ERROR: unrecognized argument(s): $BAD" >&2
  echo "  usage: wiki-ingest-plan.sh [MEMORY_DIR] [--pending-only]" >&2
  exit 0
fi
# Worktree-aware, so a session running inside a linked worktree reads the main repo's memory
# rather than scaffolding a second one of its own.
[[ -z "$MEM" ]] && MEM="$(wiki_project_dir "$PWD")/memory"

WIKI="$MEM/wiki"
if [[ ! -d "$WIKI" ]]; then
  # Exit 0: a project that never scaffolded a wiki is an expected answer, not a script failure.
  # Silent under --pending-only, whose stdout is a list of rollup names and nothing else. On
  # stderr otherwise, so stdout carries the work order and nothing else either.
  if (( PENDING_ONLY == 0 )); then
    echo "ERROR: no wiki for: $MEM" >&2
    echo "  Run /memory-wiki:init to scaffold one." >&2
  fi
  exit 0
fi

wiki_pending "$MEM"

if (( PENDING_ONLY )); then
  # `printf '%s\n'` with no arguments still emits one newline, which a reader of this list would
  # take for a pending rollup named "". Guard the call; do not try to trim the output afterwards.
  (( ${#PENDING[@]} )) && printf '%s\n' "${PENDING[@]}"
  exit 0
fi

# --- existing pages ----------------------------------------------------------------------
# wiki-index.py's own page reader, so the type and description listed here are exactly what the
# index renders, and index/log/README are skipped by the same list. If it cannot run — no python
# — wiki-index.sh has already said why on stderr, and nothing is printed: a work order showing
# "(none)" for pages that were never read would have the skill write a duplicate of every one.
PAGE_LIST="$(bash "$DIR/wiki-index.sh" --wiki "$WIKI" --list-pages)" || exit 0
PAGES=()
[[ -n "$PAGE_LIST" ]] && mapfile -t PAGES <<< "$PAGE_LIST"

# --- inbox -------------------------------------------------------------------------------
# A plain glob, so it never descends into inbox/consumed/. Captures moved there are ingested
# history that must never be offered for triage again — and they are only ever moved, never
# deleted, so that directory grows forever.
INBOX=()
for f in "$WIKI/inbox"/*.md; do
  [[ -e "$f" ]] || continue
  INBOX+=("${f##*/}")
done

# --- the work order ----------------------------------------------------------------------
# Every section is printed with its count and an explicit (none) when empty. A section that
# simply vanished would leave the reader unable to tell "nothing pending" from "the script
# stopped before it got there".
emit_section() {
  local title="$1"; shift
  printf '%s (%s)\n' "$title" "$#"
  if (( $# )); then printf '%s\n' "$@"; else printf '(none)\n'; fi
}

emit_section '## Pending sources' ${PENDING[@]+"${PENDING[@]}"}
printf '\n'
emit_section '## Existing pages' ${PAGES[@]+"${PAGES[@]}"}
printf '\n'
emit_section '## Inbox' ${INBOX[@]+"${INBOX[@]}"}
exit 0
