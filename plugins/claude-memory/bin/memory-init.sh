#!/usr/bin/env bash
# Enable the three-tier memory system for a project (explicit opt-in).
# Creates the user-local memory dir for the project and seeds MEMORY.md + state.
# After this, the SessionEnd capture + SessionStart injection hooks become active
# for that project. Run once per project from its root:  memory-init.sh
#
# Usage: memory-init.sh [PROJECT_DIR]   (defaults to current directory)
set -uo pipefail

TARGET="${1:-$PWD}"

# Shared path helpers (worktree-aware memory dir resolution).
DIR="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin}"
[[ -z "$DIR" || ! -f "$DIR/_memory-paths.sh" ]] && DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_memory-paths.sh
. "$DIR/_memory-paths.sh"

# Claude Code names project dirs from the launch path, replacing : \ / with '-'. When
# TARGET is a linked git worktree, memory resolves to the MAIN repo so it stays shared.
MEM="$(mem_project_dir "$TARGET")/memory"

if [[ -d "$MEM" ]]; then
  echo "memory already enabled for: $TARGET"
  echo "  -> $MEM"
  exit 0
fi

mkdir -p "$MEM/episodic/sessions/raw" "$MEM/episodic/sessions/archive" "$MEM/episodic/weekly"

cat > "$MEM/MEMORY.md" <<'EOF'
<!-- Tier-3 semantic index (auto-loaded every session). ONE line per durable memory.
     Index ONLY Tier-3 files (concept_*/project_*/feedback_*). Never list episodic logs here —
     those are injected at session start by the claude-memory plugin. -->
EOF

cat > "$MEM/.memory-state.json" <<'EOF'
{
  "schemaVersion": 1,
  "lastWeeklyConsolidation": null,
  "lastTier3Distill": null,
  "notes": "Bookkeeping for the claude-memory plugin. Updated by memory-consolidate.sh. Dates are ISO 8601 (UTC)."
}
EOF

echo "memory enabled for: $TARGET"
echo "  -> $MEM"
echo "Capture (SessionEnd) and recall (SessionStart) are now active for this project."
