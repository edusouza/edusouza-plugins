#!/usr/bin/env bash
# Thin wrapper around wiki-index.py: find the generator, find an interpreter, hand off.
#
# Exists so callers (a slash command, a hook, the ingest skill) never have to know which
# spelling of python this machine has, or where the plugin was unpacked. All the logic
# stays in the .py — this file must never grow a second implementation of it.
#
# Usage: wiki-index.sh --wiki <WIKI_DIR> [--memory-md <PATH>] [--render-only]
set -uo pipefail

DIR="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin}"
[[ -z "$DIR" || ! -f "$DIR/wiki-index.py" ]] && DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Probe order matters and matches test/run-tests.sh: on Windows a WindowsApps `python3`
# shim can resolve ahead of the real interpreter and does nothing but open the Store, so
# plain `python` is tried first.
PYBIN=""
if command -v python >/dev/null 2>&1; then
  PYBIN="python"
elif command -v python3 >/dev/null 2>&1; then
  PYBIN="python3"
else
  echo "ERROR: no python runtime found (tried: python, python3)" >&2
  echo "  memory-wiki 0.4.0+ needs python to generate the index. Install it and re-run." >&2
  exit 1
fi

exec "$PYBIN" "$DIR/wiki-index.py" "$@"
