#!/usr/bin/env bash
# Print the work order for one ingest run: which weekly rollups are still un-ingested, which
# pages already exist, and what is waiting in the inbox.
#
# Exists so the ingest skill spends its judgment on page content and none of it on globbing and
# bookkeeping. Asked to work out "which rollups are new" by listing directories itself, a model
# gets it subtly wrong in a way nobody notices until a week is missing from the wiki.
#
# And so the skill and the session-start nudge cannot disagree about what "pending" means,
# because there is exactly one implementation of it: a rollup counts as ingested when
# wiki/log.md carries a `- Sources:` line naming it, and wiki-log.sh is the only writer of those
# lines. Two implementations of that rule would be two answers to the only question the nudge
# knows how to ask.
#
# --pending-only is what wiki-nudge.sh calls at session start, which makes this a hook-path
# script: the pending calculation runs entirely in builtins — one pass over log.md rather than a
# grep per rollup — because a process costs ~0.4s on Windows and fifty of them would add twenty
# seconds to every session start.
#
# Reports only; writes nothing, anywhere. Exit 0 always.
#
# Usage: wiki-ingest-plan.sh [MEMORY_DIR] [--pending-only]
set -uo pipefail

# Byte ordering. Every list below comes straight out of pathname expansion, which sorts using
# the current collation — under LC_ALL=C that is byte order, the same order `sort` would give
# and the same order wiki-index.py's code-point sort gives, at no process cost.
export LC_ALL=C

DIR="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin}"
[[ -z "$DIR" || ! -f "$DIR/_wiki-paths.sh" ]] && DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_wiki-paths.sh
. "$DIR/_wiki-paths.sh"

MEM=""; PENDING_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pending-only) PENDING_ONLY=1; shift ;;
    *)              MEM="$1";       shift ;;
  esac
done
# Worktree-aware, so a session running inside a linked worktree reads the main repo's memory
# rather than scaffolding a second one of its own.
[[ -z "$MEM" ]] && MEM="$(wiki_project_dir "$PWD")/memory"

WIKI="$MEM/wiki"
if [[ ! -d "$WIKI" ]]; then
  # Exit 0: a project that never scaffolded a wiki is an expected answer, not a script failure.
  # Silent under --pending-only, because wiki-nudge.sh counts the lines printed there and would
  # read this report as a list of pending rollups.
  if (( PENDING_ONLY == 0 )); then
    echo "ERROR: no wiki for: $MEM"
    echo "  Run /memory-wiki:init to scaffold one."
  fi
  exit 0
fi

# --- pending sources ---------------------------------------------------------------------
# Every `- Sources:` line in log.md, concatenated once. One pass over one file, then a
# substring test per rollup — as opposed to a grep per rollup, which is a process per candidate
# on the path that runs at every session start.
CITED=""
if [[ -f "$WIKI/log.md" ]]; then
  # `|| [[ -n "$line" ]]` so an unterminated final line is still read.
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    # Joined with a space so no `[[name]]` can ever be formed across the seam between two
    # lines, however malformed one of them is.
    [[ "$line" == "- Sources:"* ]] && CITED="$CITED ${line#- Sources:}"
  done < "$WIKI/log.md"
fi

PENDING=()
for f in "$MEM/episodic/weekly"/*.md; do
  # A directory with no rollups leaves the pattern itself in $f.
  [[ -e "$f" ]] || continue
  base="${f##*/}"; base="${base%.md}"
  [[ "$CITED" == *"[[$base]]"* ]] && continue
  PENDING+=("$base")
done

if (( PENDING_ONLY )); then
  # `printf '%s\n'` with no arguments still emits one newline. wiki-nudge.sh counts these
  # lines, so that stray newline reads as a pending rollup named "" and nags the user forever
  # about a week that does not exist. Guard the call; do not try to trim the output afterwards.
  (( ${#PENDING[@]} )) && printf '%s\n' "${PENDING[@]}"
  exit 0
fi

# --- existing pages ----------------------------------------------------------------------
TRIMMED=""
# Strip leading and trailing whitespace from $1 into TRIMMED. Assigns to a global instead of
# echoing because $( ) is a fork, and this runs once per frontmatter line of every page.
trim() {
  TRIMMED="${1:-}"
  TRIMMED="${TRIMMED#"${TRIMMED%%[![:space:]]*}"}"
  TRIMMED="${TRIMMED%"${TRIMMED##*[![:space:]]}"}"
}

FM_TYPE=""; FM_DESC=""
# Read one page's top-level `type:` and `description:` into FM_TYPE / FM_DESC.
#
# In-process, one read pass per page, for the same reason as above: a sed or awk per page is a
# process per page. Only non-indented keys are read — the same anchoring wiki-lint.sh's fm_value
# and wiki-index.py's parse_frontmatter use — so a page whose keys are nested under a
# `metadata:` block reports no type here rather than a wrong one.
read_fm() {
  local line key val first=1
  FM_TYPE=""; FM_DESC=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    trim "$line"
    if (( first )); then
      first=0
      # No `---` fence on line 1 means no frontmatter at all. That is a lint finding, not one
      # of ours: report the page with empty columns and move on.
      [[ "$TRIMMED" == "---" ]] || return 0
      continue
    fi
    # Closing fence: everything below it is prose, where a line starting `type:` is not a field.
    [[ "$TRIMMED" == "---" ]] && return 0
    # Top-level keys only, tested on the raw line before trimming flattened the indent away.
    [[ "$line" == [[:space:]]* ]] && continue
    case "$TRIMMED" in
      "type:"*)        key=type;        val="${TRIMMED#type:}" ;;
      "description:"*) key=description; val="${TRIMMED#description:}" ;;
      *) continue ;;
    esac
    trim "$val"; val="$TRIMMED"
    # `type: "failure"` and `type: failure` are the same value.
    if [[ "$val" == \"*\" || "$val" == \'*\' ]]; then
      val="${val:1:${#val}-2}"
    fi
    if [[ "$key" == type ]]; then FM_TYPE="$val"; else FM_DESC="$val"; fi
  done < "$1"
}

PAGES=()
for f in "$WIKI"/*.md; do
  [[ -e "$f" ]] || continue
  base="${f##*/}"; base="${base%.md}"
  # Machinery, not pages: the same three names wiki-index.py skips.
  [[ "$base" == index || "$base" == log || "$base" == README ]] && continue
  read_fm "$f"
  # No column padding. Padding to the longest name would make the golden brittle to fixture
  # edits that have nothing to do with this script.
  PAGES+=("$base | $FM_TYPE | $FM_DESC")
done

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
