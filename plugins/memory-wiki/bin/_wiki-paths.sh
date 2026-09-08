#!/usr/bin/env bash
# Shared path helpers for memory-wiki. SOURCE this file; do not execute it.
#
# Vendored from claude-memory's _memory-paths.sh so the two plugins install
# independently — memory-wiki cannot depend on another plugin's files existing on disk.
# Behavior must stay identical: both must resolve a given cwd to the same memory dir, or
# a project's memory and its wiki would end up in different places. test/run-tests.sh
# cross-checks the two resolvers whenever claude-memory is installed.
#
#   wiki_to_posix <path>          Windows/POSIX path -> POSIX (git-bash friendly)
#   wiki_resolve_main_root <cwd>  linked worktree -> main worktree root; else unchanged
#   wiki_hash_dir <path>          path -> $HOME/.claude/projects/<hash>
#   wiki_project_dir <cwd>        worktree-aware project dir (resolve + hash)

# Normalize Windows paths (C:\... or C:/...) to POSIX (/c/...) for git-bash use.
wiki_to_posix() {
  [[ -z "${1:-}" ]] && return 0
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$1" 2>/dev/null || printf '%s' "$1"
  else
    printf '%s' "$1" | sed -E 's#^([A-Za-z]):#/\L\1#; s#\\#/#g'
  fi
}

# Echo the MAIN worktree root for a cwd. Only *linked* worktrees are redirected: the main
# worktree (incl. any subdirectory) and non-git cwds echo unchanged. Detection: a linked
# worktree's git-dir (<main>/.git/worktrees/<name>) differs from its common-dir (<main>/.git).
wiki_resolve_main_root() {
  local cwd="${1:-}" gitdir common main pcwd
  [[ -z "$cwd" ]] && return 0
  pcwd="$(wiki_to_posix "$cwd")"
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
wiki_hash_dir() {
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
wiki_project_dir() {
  wiki_hash_dir "$(wiki_resolve_main_root "${1:-}")"
}
