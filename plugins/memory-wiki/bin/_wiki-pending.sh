#!/usr/bin/env bash
# The pending-rollup rule for memory-wiki. SOURCE this file; do not execute it.
#
# A weekly rollup is pending until wiki/log.md carries a `- Sources:` line naming it, and
# wiki-log.sh is the only writer of those lines. This function is the only implementation of
# that rule: wiki-ingest-plan.sh reports from it and wiki-nudge.sh nags from it, so the skill and
# the session-start reminder cannot disagree about which weeks are left.
#
# Sourced rather than run as a child script, and pure bash, because wiki-nudge.sh calls it at
# every session start: one pass over log.md and a substring test per rollup, never a grep per
# candidate, and no process at all.
#
#   wiki_pending <memdir>   fill PENDING with the un-ingested rollup names, in byte order

wiki_pending() {
  local mem="${1:-}" f base line cited=""
  # Byte order for the glob below, the same order `sort` and wiki-index.py's code-point sort give.
  local LC_ALL=C
  PENDING=()

  local rollups=( "$mem/episodic/weekly"/*.md )
  # No rollups leaves the pattern itself as the only element, and then there is nothing for
  # log.md to be matched against, so it is not read.
  [[ ${#rollups[@]} -eq 1 && ! -e "${rollups[0]}" ]] && return 0

  if [[ -f "$mem/wiki/log.md" ]]; then
    # `|| [[ -n "$line" ]]` so an unterminated final line is still read.
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      # Joined with a space so no `[[name]]` can ever be formed across the seam between two
      # lines, however malformed one of them is.
      [[ "$line" == "- Sources:"* ]] && cited+=" ${line#- Sources:}"
    done < "$mem/wiki/log.md"
  fi

  for f in "${rollups[@]}"; do
    [[ -e "$f" ]] || continue
    base="${f##*/}"; base="${base%.md}"
    [[ "$cited" == *"[[$base]]"* ]] || PENDING+=("$base")
  done
}
