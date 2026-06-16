#!/usr/bin/env bash
# branch-from-issue.sh — create & check out a GitHub issue-linked branch BEFORE coding.
#
# Usage:
#   branch-from-issue.sh <issue-number> [--base <branch>] [--name <branch>]
#
# Runs the explicit-flag form, branching from the repo's default branch:
#   gh issue develop <issue-number> --base <main-branch> --name <branch-name> --checkout
#
#   --base <branch>   Override the base branch (default: the repo's default branch).
#   --name <branch>   Override the new branch name (default: <issue>-<kebab-slug-of-title>).
#
# Prints the created branch name; exits non-zero with a clear message on any failure.
# Requires: gh (authenticated) and git, run inside the target repository.

set -euo pipefail

die() { echo "branch-from-issue: $*" >&2; exit 1; }

ISSUE=""
BASE=""
NAME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --base) BASE="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,/^$/{/^#/{s/^# \{0,1\}//;p}}' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$ISSUE" ] || die "unexpected argument: $1"; ISSUE="$1"; shift ;;
  esac
done

[ -n "$ISSUE" ] || die "usage: branch-from-issue.sh <issue-number> [--base <branch>] [--name <branch>]"
case "$ISSUE" in *[!0-9]*) die "issue number must be numeric, got: '$ISSUE'" ;; esac

# Preconditions.
command -v gh  >/dev/null 2>&1 || die "gh CLI not installed (https://cli.github.com)"
command -v git >/dev/null 2>&1 || die "git not installed"
gh auth status >/dev/null 2>&1 || die "gh not authenticated — run: gh auth login"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"

# Warn (don't fail) on a dirty tree — gh ... --checkout may refuse to switch branches.
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo "branch-from-issue: warning — uncommitted changes present; --checkout may fail" >&2
fi

# Resolve <main-branch> (unless --base given): GitHub API, then local origin/HEAD fallback.
MAIN="$BASE"
if [ -z "$MAIN" ]; then
  MAIN="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null \
    || git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')"
  if [ -z "$MAIN" ]; then
    git remote set-head origin --auto >/dev/null 2>&1 || true
    MAIN="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')"
  fi
fi
[ -n "$MAIN" ] || die "could not resolve the default branch (pass --base <branch>)"

# Guard: base must be a real remote branch (gh may silently fall back otherwise).
git show-ref --verify --quiet "refs/remotes/origin/$MAIN" \
  || git ls-remote --exit-code --heads origin "$MAIN" >/dev/null 2>&1 \
  || die "base branch '$MAIN' not found on origin"

# Derive <branch-name> (unless --name given) as "<issue>-<kebab-slug-of-title>".
BRANCH="$NAME"
if [ -z "$BRANCH" ]; then
  TITLE="$(gh issue view "$ISSUE" --json title -q .title 2>/dev/null)" \
    || die "issue #$ISSUE not found (check the number, or run from the right repo)"
  SLUG="$(printf '%s' "$TITLE" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-50 | sed -E 's/-+$//')"
  BRANCH="${ISSUE}-${SLUG:-issue}"
fi

echo "branch-from-issue: issue #$ISSUE → '$BRANCH' (base '$MAIN')" >&2

# Create the issue-linked branch, based on the default branch, and check it out locally.
gh issue develop "$ISSUE" --base "$MAIN" --name "$BRANCH" --checkout \
  || die "gh issue develop failed (branch may already exist or be linked; see: gh issue develop $ISSUE --list)"

# Confirm the local checkout actually happened.
CURRENT="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo)"
[ "$CURRENT" = "$BRANCH" ] || die "branch created but HEAD is '$CURRENT' (expected '$BRANCH')"

echo "✓ created and checked out '$BRANCH' (base '$MAIN', issue #$ISSUE)"
