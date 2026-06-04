#!/usr/bin/env bash
# Enable the three-tier memory system for a project (explicit opt-in).
# Creates the user-local memory dir for the project and seeds MEMORY.md + state.
# After this, the SessionEnd capture + SessionStart injection hooks become active
# for that project. Run once per project from its root:  memory-init.sh
#
# Usage: memory-init.sh [PROJECT_DIR]   (defaults to current directory)
set -uo pipefail

TARGET="${1:-$PWD}"
# Claude Code names project dirs from the path it was launched with, replacing
# : \ / with '-'. Convert to a Windows-style path first on Windows so the hash
# matches (e.g. C:\Users\me\proj -> C--Users-me-proj).
if command -v cygpath >/dev/null 2>&1; then
  WIN="$(cygpath -w "$TARGET" 2>/dev/null || echo "$TARGET")"
else
  WIN="$TARGET"
fi
HASH="$(printf '%s' "$WIN" | sed 's#[:\\/]#-#g')"
MEM="$HOME/.claude/projects/$HASH/memory"

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
