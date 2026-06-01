#!/usr/bin/env bash
# tdd-stop-guard.sh
# Blocks Claude from stopping when there are uncommitted .ts files and the test
# suite does not pass coverage thresholds.
#
# Suspend for the TDD red phase (write failing tests before implementation):
#   touch <workspace-root>/.claude/.tdd-mode
# Re-enable after implementation makes tests green:
#   rm <workspace-root>/.claude/.tdd-mode

set -euo pipefail

# Must be inside a git repo.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Sentinel lives one level above the repo root (workspace root).
WORKSPACE_ROOT=$(dirname "$REPO_ROOT")
SENTINEL="$WORKSPACE_ROOT/.claude/.tdd-mode"

# Red phase — tests are expected to fail, skip the gate.
[ -f "$SENTINEL" ] && exit 0

# No uncommitted .ts files — nothing to enforce.
DIRTY_TS=$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | grep '\.ts' || true)
[ -z "$DIRTY_TS" ] && exit 0

# Detect package manager.
if [ -f "$REPO_ROOT/pnpm-lock.yaml" ]; then
  PM="pnpm"
elif [ -f "$REPO_ROOT/yarn.lock" ]; then
  PM="yarn"
else
  PM="npm"
fi

# Only enforce if a test:cov script exists.
if ! "$PM" run --if-present test:cov --help >/dev/null 2>&1; then
  HAS_COV=$(node -e "
    const p = require('$REPO_ROOT/package.json');
    process.exit(p.scripts && p.scripts['test:cov'] ? 0 : 1);
  " 2>/dev/null && echo yes || echo no)
  [ "$HAS_COV" = "no" ] && exit 0
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  TDD Stop Guard: uncommitted .ts files detected          ║"
echo "║  Running coverage check before allowing Claude to stop…  ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

cd "$REPO_ROOT"
if "$PM" run test:cov 2>&1; then
  echo ""
  echo "✓ Coverage check passed."
  exit 0
else
  echo ""
  echo "✗ Coverage check FAILED."
  echo ""
  echo "  Fix the failing tests, or suspend the gate for the TDD red phase:"
  echo "    touch $SENTINEL"
  exit 1
fi
