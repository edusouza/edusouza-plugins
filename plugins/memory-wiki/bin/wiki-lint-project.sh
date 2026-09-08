#!/usr/bin/env bash
# Project-aware entry point for the linter: resolves this project's memory dir, picks
# the directory to audit, and hands it to wiki-lint.sh with the standard source/atlas
# roots. Exists so /memory-wiki:lint stays a one-line command instead of carrying this
# logic inline in its markdown body.
#
# wiki-lint.sh itself stays a pure function of a directory — all project resolution
# lives here, and the PowerShell twin only has to mirror the pure half.
#
# Usage: wiki-lint-project.sh [MEMORY_DIR]   (defaults to the current project's memory dir)
set -uo pipefail

DIR="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin}"
[[ -z "$DIR" || ! -f "$DIR/_wiki-paths.sh" ]] && DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_wiki-paths.sh
. "$DIR/_wiki-paths.sh"

MEM="${1:-}"
[[ -z "$MEM" ]] && MEM="$(wiki_project_dir "$PWD")/memory"

# Exit 0 on a missing memory dir: this is a report command, and a project that never
# opted into claude-memory is an expected answer, not a script failure.
if [[ ! -d "$MEM" ]]; then
  echo "ERROR: no memory dir: $MEM"
  exit 0
fi

# A pre-wiki memory dir has no wiki/ subdir. Its flat concept_*.md files are a wiki with
# no edges, and auditing those is the Phase 1 entry point — so fall back to the memory
# dir itself rather than reporting nothing.
WIKI="$MEM/wiki"
[[ -d "$WIKI" ]] || WIKI="$MEM"

bash "$DIR/wiki-lint.sh" "$WIKI" --sources "$MEM/episodic/weekly" --atlas "$HOME/.claude/memory-wiki"
