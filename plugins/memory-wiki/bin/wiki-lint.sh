#!/usr/bin/env bash
# Structural audit of a memory-wiki. Pure function: takes a directory, prints a
# deterministic report, exits 0. Reports only — never fixes, never writes.
#
# Usage: wiki-lint.sh <WIKI_DIR> [--sources <DIR>] [--atlas <DIR>] [--concepts <DIR>]
set -uo pipefail

# Deterministic collation. Without this, `sort` ignores punctuation under some locales
# and orders "a-b" vs "a_b" differently per machine, which the PowerShell twin (ordinal)
# would never reproduce. Byte order everywhere.
export LC_ALL=C

WIKI=""; SOURCES=""; ATLAS=""; CONCEPTS=""
while [[ $# -gt 0 ]]; do
  # `shift 2` shifts nothing and returns non-zero when the flag came last with no value, which
  # would spin this loop forever; fall back to shifting the flag on its own. Same idiom, and
  # the same reason, as wiki-log.sh. It is not theoretical here: this script is invoked by a
  # model — skills/ingest/SKILL.md passes two of these flags — and a hung Bash call in the
  # middle of a verify step is worse than any wrong report.
  case "$1" in
    --sources)  SOURCES="${2:-}";  shift 2 || shift ;;
    --atlas)    ATLAS="${2:-}";    shift 2 || shift ;;
    --concepts) CONCEPTS="${2:-}"; shift 2 || shift ;;
    *)          WIKI="$1";         shift ;;
  esac
done

if [[ -z "$WIKI" || ! -d "$WIKI" ]]; then
  echo "ERROR: not a directory: ${WIKI:-<none>}" >&2
  exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Index and log files link to nearly every page by design. Counting their links as
# inbound edges would hide every orphan, so they are excluded from the page set and
# from inbound-edge accounting (their links still count toward the total).
#
# MEMORY.md is included because a pre-wiki memory dir has no index.md — MEMORY.md IS
# the index there, and linting <memdir> directly is the Phase 1 entry point. Omitting
# it reports the index as an orphan with no frontmatter, which is noise, not a finding.
# README.md is the page schema wiki-init.sh copies into every new wiki — it is the document
# that defines the schema, not a page written against it. Audited as content it reports its
# own placeholders ([[atlas/<page>]], [[exact-filename-without-extension]]) as broken links and
# itself as a frontmatter-less orphan, so every freshly scaffolded wiki would be born with two
# false positives.
is_structural() { [[ "$1" == "index" || "$1" == "log" || "$1" == "MEMORY" || "$1" == "README" ]]; }

# Appends the name of every *.md directly inside $1 to the file $2. Parameter expansion rather
# than `basename`, which would be a process per file.
collect_names() {
  local f b
  for f in "$1"/*.md; do
    [[ -e "$f" ]] || continue
    b="${f##*/}"; printf '%s\n' "${b%.md}"
  done >> "$2"
}

# --- collect page names and per-page link lists ---
: > "$TMP/pages"; : > "$TMP/links"; : > "$TMP/inbound"; : > "$TMP/nofm"; : > "$TMP/schema"
LINK_COUNT=0
declare -A FMV FMHAS

for f in "$WIKI"/*.md; do
  [[ -e "$f" ]] || continue
  base="$(basename "$f" .md)"
  is_structural "$base" || echo "$base" >> "$TMP/pages"

  # Frontmatter must be a --- fenced block starting on line 1 AND carry every
  # required field. Which fields those are depends on the page's own type:.
  if ! is_structural "$base"; then
    if [[ "$(head -n 1 "$f" | tr -d '\r')" != "---" ]]; then
      echo "$base (no frontmatter)" >> "$TMP/nofm"
    else
      fm="$(awk 'NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$f" | tr -d '\r')"

      # One pass over the frontmatter, all builtins — this runs per page, and a sed or a grep per
      # field would be a process each. Two things are recorded for every schema key:
      #   FMV    its FIRST value, stripped of surrounding whitespace and then of one pair of
      #          double and one pair of single quotes, so `type: "failure"` and `type: failure `
      #          both compare equal to `failure`;
      #   FMHAS  whether ANY line gives it a non-blank value.
      #
      # A key with nothing after it is absent, not present. A bare `symptom:` would otherwise
      # count as present while every downstream consumer treats the field as missing anyway —
      # its FMV is "" so the value checks below skip it, and wiki-index.py's render drops it
      # from Symptoms, Map and Sources ingested — certifying a page that is unreachable by the
      # one query this plugin exists to serve. `[[:blank:]]` is space-and-tab in the C locale,
      # exactly what the PowerShell twin's `[ \t]` matches — the two must agree byte-for-byte.
      #
      # Only top-level keys are read: the key is everything before the first colon and must be a
      # schema name exactly, so ` type:` never matches. Pages written by the global auto-memory
      # nest their keys under a `metadata:` block, which indents them out of every match here,
      # and that is the wanted behaviour: such a page has no parseable type, so it reports its
      # absent `type` once as a missing field and is exempt from both the type-specific
      # requirements and the value checks below. One schema collision must not cascade into
      # three findings.
      FMV=(); FMHAS=()
      while IFS= read -r line; do
        key="${line%%:*}"
        [[ "$key" == "$line" ]] && continue      # no colon on this line
        case "$key" in
          description|last_accessed|name|part_of|sources|status|symptom|type) ;;
          *) continue ;;
        esac
        val="${line#*:}"
        [[ "$val" == *[![:blank:]]* ]] && FMHAS[$key]=1
        [[ -n "${FMV[$key]+set}" ]] && continue
        val="${val#"${val%%[![:space:]]*}"}"
        val="${val%"${val##*[![:space:]]}"}"
        [[ "$val" == \"*\" ]] && val="${val:1:${#val}-2}"
        [[ "$val" == \'*\' ]] && val="${val:1:${#val}-2}"
        FMV[$key]="$val"
      done <<< "$fm"
      type_v="${FMV[type]:-}"
      status_v="${FMV[status]:-}"

      # Each list is written in byte order, so the reported fields come out alphabetical.
      case "$type_v" in
        failure)      req=(description last_accessed name sources status symptom type) ;;
        component)    req=(description last_accessed name part_of sources status type) ;;
        project|tech) req=(description last_accessed name sources status type) ;;
        *)            req=(description last_accessed name status type) ;;
      esac
      missing=""
      for field in "${req[@]}"; do
        [[ -n "${FMHAS[$field]:-}" ]] || missing="${missing:+$missing, }$field"
      done
      [[ -n "$missing" ]] && echo "$base (missing: $missing)" >> "$TMP/nofm"

      # A field that is out of range is a different finding from one that is absent, and
      # absent fields are already reported above — so each value is judged only where it is
      # actually present.
      if [[ -n "$type_v" ]]; then
        invalid=""
        case "$type_v" in
          project|component|tech|failure|concept) ;;
          *) invalid="type=$type_v" ;;
        esac
        if [[ -n "$status_v" ]]; then
          case "$status_v" in
            active|dormant|superseded) ;;
            *) invalid="${invalid:+$invalid, }status=$status_v" ;;
          esac
        fi
        [[ -n "$invalid" ]] && echo "$base (invalid: $invalid)" >> "$TMP/schema"
      fi
    fi
  fi

  # README.md is not a participant in the link graph at all — neither counted nor classified.
  # It is prose *about* the link syntax, and its [[...]] are illustrations that cannot resolve
  # by construction, so every freshly scaffolded wiki would otherwise report them as broken
  # links its owner cannot fix. index.md and log.md are the opposite: real indexes whose links
  # are real edges to real pages, so one pointing at a page that no longer exists is a genuine
  # finding. They are exempt from inbound-edge accounting only; README is exempt from both.
  [[ "$base" == "README" ]] && continue

  # [[target]] — stop at ] | or #, so aliases and anchors resolve to the page
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    LINK_COUNT=$((LINK_COUNT + 1))
    echo "$base|$target" >> "$TMP/links"
  done < <(grep -o '\[\[[^]|#]*' "$f" 2>/dev/null | sed 's/^\[\[//' | sed 's/[[:space:]]*$//')
done

sort -u -o "$TMP/pages" "$TMP/pages"
PAGE_COUNT=$(wc -l < "$TMP/pages" | tr -d ' ')
NOFM_COUNT=$(sort -u "$TMP/nofm" | grep -c . || true)
SCHEMA_COUNT=$(sort -u "$TMP/schema" | grep -c . || true)

# --- resolvable-name sets ---
: > "$TMP/known"
cat "$TMP/pages" >> "$TMP/known"
[[ -n "$SOURCES" && -d "$SOURCES" ]] && collect_names "$SOURCES" "$TMP/known"
# claude-memory's flat root concept_*.md files are legitimate link targets but are not pages of
# this wiki: they live outside it and memory-wiki never writes them. Counting them as pages
# would report every unlinked one as an orphan of a wiki it is not part of, and would inflate
# the page count with files this plugin does not own. So they go into `known` — resolvable —
# and never into `pages`, which is what gets counted and orphan-checked.
[[ -n "$CONCEPTS" && -d "$CONCEPTS" ]] && collect_names "$CONCEPTS" "$TMP/known"
: > "$TMP/known_atlas"
[[ -n "$ATLAS" && -d "$ATLAS" ]] && collect_names "$ATLAS" "$TMP/known_atlas"
# Every structural file that exists is a real file and a legitimate link target, even though
# it is excluded from the page count. This must stay the same set the PowerShell twin adds —
# it derives the list from $structural, so any name missing here reports broken on the bash
# side alone. MEMORY was such a name, and in a pre-wiki memory dir — Phase 1's entry point,
# where MEMORY.md always exists — it is the likeliest of the four to be linked.
for s in index log MEMORY README; do [[ -f "$WIKI/$s.md" ]] && echo "$s" >> "$TMP/known"; done
sort -u -o "$TMP/known" "$TMP/known"
sort -u -o "$TMP/known_atlas" "$TMP/known_atlas"

# --- classify every link ---
: > "$TMP/broken"
while IFS='|' read -r from to; do
  [[ -n "$to" ]] || continue
  if [[ "$to" == atlas/* ]]; then
    if grep -qxF "${to#atlas/}" "$TMP/known_atlas"; then
      continue
    fi
  elif grep -qxF "$to" "$TMP/known"; then
    is_structural "$from" || echo "$to" >> "$TMP/inbound"
    continue
  fi
  echo "$from -> [[$to]]" >> "$TMP/broken"
done < "$TMP/links"
BROKEN_COUNT=$(grep -c . "$TMP/broken" || true)

# A page is an orphan when nothing outside index.md/log.md links to it.
sort -u -o "$TMP/inbound" "$TMP/inbound"
comm -23 "$TMP/pages" "$TMP/inbound" > "$TMP/orphans"
ORPHAN_COUNT=$(grep -c . "$TMP/orphans" || true)

# --- report ---
echo "## Structural"
printf '  %-20s : %s\n' "pages" "$PAGE_COUNT"
printf '  %-20s : %s\n' "wikilinks" "$LINK_COUNT"
printf '  %-20s : %s\n' "broken links" "$BROKEN_COUNT"
printf '  %-20s : %s\n' "orphans" "$ORPHAN_COUNT"
printf '  %-20s : %s\n' "missing frontmatter" "$NOFM_COUNT"
printf '  %-20s : %s\n' "schema errors" "$SCHEMA_COUNT"

if [[ "$BROKEN_COUNT" -gt 0 ]]; then
  echo ""; echo "  BROKEN:"
  sort "$TMP/broken" | sed 's/^/    /'
fi

if [[ "$ORPHAN_COUNT" -gt 0 ]]; then
  echo ""; echo "  ORPHANS:"
  sed 's/^/    /' "$TMP/orphans"
fi

if [[ "$NOFM_COUNT" -gt 0 ]]; then
  echo ""; echo "  NO FRONTMATTER:"
  sort -u "$TMP/nofm" | sed 's/^/    /'
fi

if [[ "$SCHEMA_COUNT" -gt 0 ]]; then
  echo ""; echo "  SCHEMA:"
  sort -u "$TMP/schema" | sed 's/^/    /'
fi

echo ""
echo "## Injection budget"
REGION_BYTES=0
if [[ -f "$WIKI/index.md" ]]; then
  # tr -d '\r' is load-bearing: a memory dir may hold CRLF or LF files, and the
  # reported budget must not depend on which. The PowerShell twin strips \r too.
  REGION_BYTES=$(awk '/<!-- BEGIN memory-wiki/{f=1;next} /<!-- END memory-wiki/{f=0} f' "$WIKI/index.md" | tr -d '\r' | wc -c | tr -d ' ')
fi
printf '  %-20s : %s B (~%s tokens)\n' "index region" "$REGION_BYTES" "$((REGION_BYTES * 10 / 36))"
