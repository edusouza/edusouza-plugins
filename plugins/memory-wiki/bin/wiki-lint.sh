#!/usr/bin/env bash
# Structural audit of a memory-wiki. Pure function: takes a directory, prints a
# deterministic report, exits 0. Reports only — never fixes, never writes.
#
# Usage: wiki-lint.sh <WIKI_DIR> [--sources <DIR>] [--atlas <DIR>]
set -uo pipefail

# Deterministic collation. Without this, `sort` ignores punctuation under some locales
# and orders "a-b" vs "a_b" differently per machine, which the PowerShell twin (ordinal)
# would never reproduce. Byte order everywhere.
export LC_ALL=C

WIKI=""; SOURCES=""; ATLAS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sources) SOURCES="${2:-}"; shift 2 ;;
    --atlas)   ATLAS="${2:-}";   shift 2 ;;
    *)         WIKI="$1";        shift ;;
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
is_structural() { [[ "$1" == "index" || "$1" == "log" || "$1" == "MEMORY" ]]; }

# --- collect page names and per-page link lists ---
: > "$TMP/pages"; : > "$TMP/links"; : > "$TMP/inbound"; : > "$TMP/nofm"
LINK_COUNT=0

for f in "$WIKI"/*.md; do
  [[ -e "$f" ]] || continue
  base="$(basename "$f" .md)"
  is_structural "$base" || echo "$base" >> "$TMP/pages"

  # Frontmatter must be a --- fenced block starting on line 1 AND carry every
  # required field. Fields are checked in alphabetical order so the reported list
  # is sorted without a separate sort step.
  if ! is_structural "$base"; then
    if [[ "$(head -n 1 "$f" | tr -d '\r')" != "---" ]]; then
      echo "$base (no frontmatter)" >> "$TMP/nofm"
    else
      fm="$(awk 'NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$f" | tr -d '\r')"
      missing=""
      for field in description last_accessed name status type; do
        grep -qE "^${field}:" <<< "$fm" || missing="${missing:+$missing, }$field"
      done
      [[ -n "$missing" ]] && echo "$base (missing: $missing)" >> "$TMP/nofm"
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

# --- resolvable-name sets ---
: > "$TMP/known"
cat "$TMP/pages" >> "$TMP/known"
if [[ -n "$SOURCES" && -d "$SOURCES" ]]; then
  for f in "$SOURCES"/*.md; do [[ -e "$f" ]] && basename "$f" .md >> "$TMP/known"; done
fi
: > "$TMP/known_atlas"
if [[ -n "$ATLAS" && -d "$ATLAS" ]]; then
  for f in "$ATLAS"/*.md; do [[ -e "$f" ]] && basename "$f" .md >> "$TMP/known_atlas"; done
fi
# index.md and log.md are real files and are legitimate link targets even though they
# are excluded from the page count.
for s in index log; do [[ -f "$WIKI/$s.md" ]] && echo "$s" >> "$TMP/known"; done
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

echo ""
echo "## Injection budget"
REGION_BYTES=0
if [[ -f "$WIKI/index.md" ]]; then
  # tr -d '\r' is load-bearing: a memory dir may hold CRLF or LF files, and the
  # reported budget must not depend on which. The PowerShell twin strips \r too.
  REGION_BYTES=$(awk '/<!-- BEGIN memory-wiki/{f=1;next} /<!-- END memory-wiki/{f=0} f' "$WIKI/index.md" | tr -d '\r' | wc -c | tr -d ' ')
fi
printf '  %-20s : %s B (~%s tokens)\n' "index region" "$REGION_BYTES" "$((REGION_BYTES * 10 / 36))"
