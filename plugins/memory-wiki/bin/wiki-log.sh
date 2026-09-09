#!/usr/bin/env bash
# Append one entry to a wiki's ingest ledger, wiki/log.md.
#
# Nothing hand-writes that file, and this script is the reason why. log.md is not a diary: its
# `- Sources:` lines ARE the record of which weekly rollups have been ingested, and
# wiki-ingest-plan.sh works out what is still pending by reading exactly those lines back. One
# writer is what keeps the two from drifting — an entry typed by hand in a slightly different
# shape silently un-ingests a week, and the next session is told to redo work already done. The
# shape below is therefore a contract with that reader, not a formatting preference.
#
# Append-only, per the plugin's standing rule: this never rewrites or removes an existing entry.
#
# There is no _wiki-paths.sh here on purpose: nothing in this script resolves a project. The
# wiki directory arrives as --wiki, from a caller that has already resolved it.
#
# Usage: wiki-log.sh --wiki <WIKI_DIR> --op <OP> --title <TITLE> [--date YYYY-MM-DD]
#                    [--sources a,b] [--created a,b] [--updated a,b] [--inbox a,b]
set -uo pipefail

# Byte semantics, as everywhere else in this plugin. Nothing here sorts, but the [[:space:]]
# class the trimming below leans on is locale-defined, and this pins what it matches.
export LC_ALL=C

WIKI=""; OP=""; TITLE=""; DATE=""
SOURCES=""; CREATED=""; UPDATED=""; INBOX=""
while [[ $# -gt 0 ]]; do
  # `shift 2` shifts nothing and returns non-zero when the flag came last with no value, which
  # would spin this loop forever; fall back to shifting the flag on its own.
  case "$1" in
    --wiki)    WIKI="${2:-}";    shift 2 || shift ;;
    --op)      OP="${2:-}";      shift 2 || shift ;;
    --title)   TITLE="${2:-}";   shift 2 || shift ;;
    --date)    DATE="${2:-}";    shift 2 || shift ;;
    --sources) SOURCES="${2:-}"; shift 2 || shift ;;
    --created) CREATED="${2:-}"; shift 2 || shift ;;
    --updated) UPDATED="${2:-}"; shift 2 || shift ;;
    --inbox)   INBOX="${2:-}";   shift 2 || shift ;;
    # Rejected rather than ignored. This file is append-only, so a misspelled `--craeted`
    # quietly dropped here is a page that never appears in the ledger and can never be added
    # to the entry afterwards.
    *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$WIKI" || ! -d "$WIKI" ]]; then
  echo "ERROR: not a wiki directory: ${WIKI:-<none>}" >&2
  exit 1
fi
if [[ -z "$OP" ]]; then
  echo "ERROR: --op is required (what this entry records: ingest, prune, merge, ...)" >&2
  exit 1
fi
if [[ -z "$TITLE" ]]; then
  echo "ERROR: --title is required" >&2
  exit 1
fi

# Today, unless --date pins it. printf's %(...)T is a bash builtin, so the everyday path costs
# no process; --date exists only so the tests have a deterministic value to assert.
[[ -z "$DATE" ]] && printf -v DATE '%(%Y-%m-%d)T' -1

# Render one comma-separated argument into the entry's list form.
#
# Split by reading lines off a here-string, never by letting the shell word-split the value.
# Wiki page names are model-generated: an unquoted split runs pathname expansion over every
# word it produces, so a page called `component_*` would silently become whatever files happen
# to sit in the caller's working directory.
#
# $1 is the raw value; $2 is `link` for the fields that hold wiki/source page names and
# anything else for --inbox, whose items are plain capture filenames rather than pages.
render_list() {
  local raw="${1:-}" mode="${2:-}" item out=""
  while IFS= read -r item; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [[ -z "$item" ]] && continue
    if [[ "$mode" == link ]]; then
      # A caller that already bracketed the name gets one pair of brackets, not two: the
      # ingest skill is a model reading a format full of [[...]], and it will sometimes hand
      # them straight back.
      if [[ "$item" == "[["*"]]" ]]; then
        item="${item#'[['}"
        item="${item%']]'}"
      fi
      item="[[$item]]"
    fi
    out="${out:+$out, }$item"
  done <<< "${raw//,/$'\n'}"
  printf '%s' "$out"
}

SRC="$(render_list "$SOURCES" link)"
CRE="$(render_list "$CREATED" link)"
UPD="$(render_list "$UPDATED" link)"
INB="$(render_list "$INBOX" plain)"

LOG="$WIKI/log.md"

# The same header wiki-init.sh seeds a new wiki's log.md with. Repeated rather than shared,
# because this has to work on a wiki scaffolded before this script existed, or one whose log.md
# was removed by hand. Keep the two byte-identical.
if [[ ! -f "$LOG" ]]; then
  cat > "$LOG" <<'EOF'
# Wiki Log

Append-only chronological record. Format: `## [YYYY-MM-DD] operation | title`

---
EOF
fi

# One leading blank line separates this entry from whatever precedes it. That is safe without
# checking for a trailing newline first, because the only two writers of log.md are this block
# and wiki-init.sh above, and both terminate every line they emit.
{
  printf '\n## [%s] %s | %s\n\n' "$DATE" "$OP" "$TITLE"
  # Always emitted, even with nothing after the colon. This is the line the pending
  # calculation reads, and an entry carrying no `- Sources:` line at all is indistinguishable
  # from one whose sources were dropped on the way in.
  printf '%s\n' "- Sources:${SRC:+ $SRC}"
  # The other three are omitted when empty: unlike Sources they are a description of what the
  # run did, and "created no pages" is better said by silence than by an empty bullet.
  [[ -n "$CRE" ]] && printf '%s\n' "- Pages created: $CRE"
  [[ -n "$UPD" ]] && printf '%s\n' "- Pages updated: $UPD"
  [[ -n "$INB" ]] && printf '%s\n' "- Inbox consumed: $INB"
} >> "$LOG"

echo "logged: [$DATE] $OP | $TITLE"
echo "  -> $LOG"
