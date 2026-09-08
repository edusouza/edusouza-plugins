#!/usr/bin/env bash
# Scaffold the wiki layer inside an existing claude-memory dir. Idempotent.
#
# Deliberately refuses to create the memory dir itself: memory-wiki reads what
# claude-memory writes, and silently creating a stray memory dir here would produce a
# wiki with no sources to ingest.
#
# Usage: wiki-init.sh [PROJECT_DIR]   (defaults to the current directory)
set -uo pipefail

TARGET="${1:-$PWD}"
[[ -z "$TARGET" ]] && TARGET="$PWD"

DIR="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin}"
[[ -z "$DIR" || ! -f "$DIR/_wiki-paths.sh" ]] && DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_wiki-paths.sh
. "$DIR/_wiki-paths.sh"

MEM="$(wiki_project_dir "$TARGET")/memory"
if [[ ! -d "$MEM" ]]; then
  echo "ERROR: no memory dir for: $TARGET"
  echo "  expected: $MEM"
  echo "  Run /claude-memory:init first — memory-wiki builds on top of it."
  exit 1
fi

WIKI="$MEM/wiki"
if [[ -d "$WIKI" ]]; then
  echo "wiki already initialized for: $TARGET"
  echo "  -> $WIKI"
  exit 0
fi

mkdir -p "$WIKI/inbox"

SCHEMA="$DIR/../assets/wiki-README.md"
if [[ -f "$SCHEMA" ]]; then
  cp "$SCHEMA" "$WIKI/README.md"
else
  echo "ERROR: page-schema asset not found: $SCHEMA" >&2
  echo "  The wiki needs its schema — refusing to scaffold a wiki without one." >&2
  rmdir "$WIKI/inbox" "$WIKI" 2>/dev/null
  exit 1
fi

cat > "$WIKI/log.md" <<'EOF'
# Wiki Log

Append-only chronological record. Format: `## [YYYY-MM-DD] operation | title`

---
EOF

echo "wiki initialized for: $TARGET"
echo "  -> $WIKI"
echo "  Next: run /memory-wiki:lint to audit what is already there."
