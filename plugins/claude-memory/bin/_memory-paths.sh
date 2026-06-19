#!/usr/bin/env bash
# Shared path helpers for the claude-memory plugin. SOURCE this file; do not execute it.
#
# Centralizes how a working directory maps to its user-local memory dir, so all hook
# scripts agree on one location. Key behavior: when the cwd is a *linked git worktree*,
# memory resolves to the MAIN worktree root — so worktree sessions share the main repo's
# memory instead of fragmenting into a per-worktree dir.
#
# Functions:
#   mem_to_posix <path>        Windows/POSIX path -> POSIX (git-bash friendly)
#   mem_resolve_main_root <cwd>  cwd -> main worktree root (or cwd unchanged)
#   mem_hash_dir <path>        path -> $HOME/.claude/projects/<hash>  (Claude Code naming)
#   mem_project_dir <cwd>      worktree-aware project dir (resolve + hash)

# Normalize Windows paths (C:\... or C:/...) to POSIX (/c/...) for git-bash use.
mem_to_posix() {
  [[ -z "${1:-}" ]] && return 0
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$1" 2>/dev/null || printf '%s' "$1"
  else
    printf '%s' "$1" | sed -E 's#^([A-Za-z]):#/\L\1#; s#\\#/#g'
  fi
}

# Echo the MAIN worktree root for a cwd. Only *linked* worktrees are redirected: the main
# worktree (incl. any subdirectory) and non-git / git-less cwds echo unchanged, preserving
# the original behavior for existing users. Detection: a linked worktree's git-dir
# (<main>/.git/worktrees/<name>) differs from its common-dir (<main>/.git).
mem_resolve_main_root() {
  local cwd="${1:-}" gitdir common main
  [[ -z "$cwd" ]] && return 0
  local pcwd; pcwd="$(mem_to_posix "$cwd")"
  if ! git -C "$pcwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s' "$cwd"; return 0
  fi
  gitdir="$(git -C "$pcwd" rev-parse --absolute-git-dir 2>/dev/null)"
  # --git-common-dir may be relative to cwd; resolve to absolute via the dir itself.
  common="$(git -C "$pcwd" rev-parse --git-common-dir 2>/dev/null)"
  if [[ -n "$common" ]]; then
    common="$(cd "$pcwd" 2>/dev/null && cd "$common" 2>/dev/null && pwd)"
  fi
  if [[ -n "$gitdir" && -n "$common" && "$gitdir" != "$common" ]]; then
    main="$(dirname "$common")"          # <main>/.git -> <main>
    [[ -n "$main" ]] && { printf '%s' "$main"; return 0; }
  fi
  printf '%s' "$cwd"
}

# Echo $HOME/.claude/projects/<hash> for a path, matching how Claude Code names project
# dirs: convert to a Windows-style path first on Windows, then replace : \ / with '-'.
mem_hash_dir() {
  local path="${1:-}" win hash
  [[ -z "$path" ]] && return 0
  if command -v cygpath >/dev/null 2>&1; then
    win="$(cygpath -w "$path" 2>/dev/null || printf '%s' "$path")"
  else
    win="$path"
  fi
  hash="$(printf '%s' "$win" | sed 's#[:\\/]#-#g')"
  printf '%s' "$HOME/.claude/projects/$hash"
}

# Worktree-aware project dir: where this cwd's memory lives (main repo for worktrees).
mem_project_dir() {
  mem_hash_dir "$(mem_resolve_main_root "${1:-}")"
}
