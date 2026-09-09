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
  case "$1" in
    --sources)  SOURCES="${2:-}";  shift 2 ;;
    --atlas)    ATLAS="${2:-}";    shift 2 ;;
    --concepts) CONCEPTS="${2:-}"; shift 2 ;;
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

# Reads one top-level frontmatter key ($1) out of a frontmatter body ($2), stripping the key,
# any surrounding quotes and any trailing whitespace, so `type: "failure"` and `type: failure `
# both compare equal to `failure`.
fm_value() {
  sed -n "s/^$1:[[:space:]]*//p" <<< "$2" | head -n 1 |
    sed -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"
}

# --- collect page names and per-page link lists ---
: > "$TMP/pages"; : > "$TMP/links"; : > "$TMP/inbound"; : > "$TMP/nofm"; : > "$TMP/schema"
LINK_COUNT=0

for f in "$WIKI"/*.md; do
  [[ -e "$f" ]] || continue
  base="$(basename "$f" .md)"
  is_structural "$base" || echo "$base" >> "$TMP/pages"

  # Frontmatter must be a --- fenced block starting on line 1 AND carry every
  # required field. Which fields those are depends on the page's own type:, so the
  # list is built per page and sorted once, keeping the reported line alphabetical
  # without a separate sort step.
  if ! is_structural "$base"; then
    if [[ "$(head -n 1 "$f" | tr -d '\r')" != "---" ]]; then
      echo "$base (no frontmatter)" >> "$TMP/nofm"
    else
      fm="$(awk 'NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$f" | tr -d '\r')"

      # Only top-level keys are read — `^type:`, never ` type:`. Pages written by the global
      # auto-memory nest their keys under a `metadata:` block, which indents them out of every
      # match here, and that is the wanted behaviour: such a page has no parseable type, so it
      # reports its absent `type` once as a missing field and is exempt from both the
      # type-specific requirements and the value checks below. One schema collision must not
      # cascade into three findings.
      type_v="$(fm_value type "$fm")"
      status_v="$(fm_value status "$fm")"

      req=(description last_accessed name status type)
      case "$type_v" in
        failure)      req+=(sources symptom) ;;
        component)    req+=(part_of sources) ;;
        project|tech) req+=(sources) ;;
      esac
      missing=""
      while IFS= read -r field; do
        grep -qE "^${field}:" <<< "$fm" || missing="${missing:+$missing, }$field"
      done < <(printf '%s\n' "${req[@]}" | sort)
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
if [[ -n "$SOURCES" && -d "$SOURCES" ]]; then
  for f in "$SOURCES"/*.md; do [[ -e "$f" ]] && basename "$f" .md >> "$TMP/known"; done
fi
# claude-memory's flat root concept_*.md files are legitimate link targets but are not pages of
# this wiki: they live outside it and memory-wiki never writes them. Counting them as pages
# would report every unlinked one as an orphan of a wiki it is not part of, and would inflate
# the page count with files this plugin does not own. So they go into `known` — resolvable —
# and never into `pages`, which is what gets counted and orphan-checked.
if [[ -n "$CONCEPTS" && -d "$CONCEPTS" ]]; then
  for f in "$CONCEPTS"/*.md; do [[ -e "$f" ]] && basename "$f" .md >> "$TMP/known"; done
fi
: > "$TMP/known_atlas"
if [[ -n "$ATLAS" && -d "$ATLAS" ]]; then
  for f in "$ATLAS"/*.md; do [[ -e "$f" ]] && basename "$f" .md >> "$TMP/known_atlas"; done
fi
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
  # README.md is the only structural file whose links are not edges. It is prose *about* the
  # link syntax, and its [[...]] are illustrations that cannot resolve by construction — so
  # every freshly scaffolded wiki would report them as broken links its owner cannot fix.
  # index.md and log.md are the opposite: they are real indexes of the graph, and one pointing
  # at a page that no longer exists is a genuine finding. Only README is exempt.
  [[ "$from" == "README" ]] && continue
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
