#!/usr/bin/env bash
# Shared path helpers for memory-wiki. SOURCE this file; do not execute it.
#
# Vendored from claude-memory's _memory-paths.sh so the two plugins install
# independently — memory-wiki cannot depend on another plugin's files existing on disk.
# Behavior must stay identical: both must resolve a given cwd to the same memory dir, or
# a project's memory and its wiki would end up in different places. test/run-tests.sh
# cross-checks the two resolvers whenever claude-memory is installed.
#
# That identity is the whole point of the file, and it is the thing that decays: this was
# a pre-fda1203 copy, drifted behind the original in every function. Re-vendored from
# claude-memory 0.3.5. When _memory-paths.sh changes, re-vendor rather than patch.
#
# PERFORMANCE CONTRACT: every one of these runs inside a SessionStart hook, and on
# Windows a process spawn costs 0.15-1.1s (measured: git 0.9s, cygpath 0.5s cold). The
# cost here is dominated by HOW MANY processes start, not by what any of them do, so
# the path munging below is deliberately pure bash — no cygpath, no sed — and the
# worktree probe asks git all of its questions in ONE `rev-parse`. Budget: one process
# per wiki_project_dir call. Keep it that way.
#
#   wiki_to_posix <path>          Windows/POSIX path -> POSIX (git-bash friendly)
#   wiki_resolve_main_root <cwd>  cwd -> main worktree root (or cwd unchanged)
#   wiki_to_mixed <path>          POSIX -> mixed Windows form (/c/x -> C:/x)
#   wiki_hash_dir <path>          path -> $HOME/.claude/projects/<hash>
#   wiki_project_dir <cwd>        worktree-aware project dir (resolve + hash)

# Normalize Windows paths (C:\... or C:/...) to POSIX (/c/...) for git-bash use.
# Pure bash: this used to shell out to `cygpath -u` (0.5s/call on Windows).
wiki_to_posix() {
  local p="${1:-}"
  [[ -z "$p" ]] && return 0
  p="${p//\\//}"                 # backslashes -> forward slashes
  if [[ "$p" == [A-Za-z]:* ]]; then
    local d="${p:0:1}"
    p="/${d,}${p:2}"             # C:/x -> /c/x  (${d,} lowercases the drive letter)
  fi
  printf '%s' "$p"
}

# Echo the MAIN worktree root for a cwd; a cwd outside any repo echoes unchanged.
# Every in-repo cwd maps to the main root — a linked worktree, a subdirectory, and the
# repo root all resolve to the same place — so one repo keeps exactly one memory dir
# instead of fragmenting per worktree or per subdirectory.
#
# The git-common-dir is <main>/.git for a linked worktree just as it is for the main
# worktree (only the git-DIR differs, at <main>/.git/worktrees/<name>), so its parent
# is the main root in every case and no separate worktree test is needed.
#
# NOTE: the previous implementation reached this same result by accident — it compared
# --absolute-git-dir against --git-common-dir to detect a linked worktree, but the two
# came back in different notations on Windows (C:/… vs /c/…), so the comparison was
# always unequal and every in-repo cwd took the redirect branch. The behavior below is
# identical for every input; it just says so on purpose, in one git call instead of three.
wiki_resolve_main_root() {
  local cwd="${1:-}" pcwd out inside common main
  [[ -z "$cwd" ]] && return 0
  pcwd="$(wiki_to_posix "$cwd")"

  # One `rev-parse` answers both questions and returns the common-dir already absolute,
  # so no second git call and no `cd`-subshell are needed to resolve it. --path-format
  # needs git >= 2.31; on anything older this fails and the legacy two-call form below
  # runs instead, rather than silently dropping the redirect.
  if out="$(git -C "$pcwd" rev-parse --is-inside-work-tree --path-format=absolute --git-common-dir 2>/dev/null)" \
     && [[ "$out" == *$'\n'* ]]; then
    inside="${out%%$'\n'*}"
    common="${out#*$'\n'}"
    common="${common%%$'\n'*}"
  else
    inside="$(git -C "$pcwd" rev-parse --is-inside-work-tree 2>/dev/null)"
    common="$(git -C "$pcwd" rev-parse --git-common-dir 2>/dev/null)"
    [[ -n "$common" ]] && common="$(cd "$pcwd" 2>/dev/null && cd "$common" 2>/dev/null && pwd)"
  fi

  if [[ "$inside" == "true" && -n "$common" ]]; then
    main="${common%/*}"                 # <main>/.git -> <main>
    [[ -n "$main" ]] && { wiki_to_posix "$main"; return 0; }
  fi
  printf '%s' "$cwd"
}

# POSIX -> mixed Windows form (/c/x -> C:/x), the shape `cygpath -m` produced.
# A non-drive absolute POSIX path (/tmp/x) is left as-is. `cygpath` used to remap those
# onto the MSYS root (C:\Program Files\Git\tmp\x), but no such path reaches here: on
# Windows every cwd Claude Code reports is drive-rooted, and off Windows the old code
# had no cygpath and took this same branch.
wiki_to_mixed() {
  local path="${1:-}" d
  [[ -z "$path" ]] && return 0
  if [[ "$path" == /[A-Za-z]/* ]]; then
    d="${path:1:1}"
    printf '%s' "${d^}:${path:2}"   # /c/x -> C:/x  (${d^} uppercases the drive letter)
  elif [[ "$path" == /[A-Za-z] ]]; then
    d="${path:1:1}"
    printf '%s' "${d^}:/"           # bare drive: cygpath -w '/c' is 'C:\', hashing to 'C--'
  else
    printf '%s' "$path"
  fi
}

# Echo $HOME/.claude/projects/<hash> for a path, matching how Claude Code names project
# dirs: convert to a Windows-style path first on Windows, then replace : \ / with '-'.
# Pure bash: `cygpath -w` + `sed` used to cost two spawns here. Either separator form
# yields the same hash, since ':', '\' and '/' all map to '-'.
wiki_hash_dir() {
  local path="${1:-}" win hash
  [[ -z "$path" ]] && return 0
  win="$(wiki_to_mixed "$path")"
  hash="${win//\\/-}"; hash="${hash//\//-}"; hash="${hash//:/-}"
  printf '%s' "$HOME/.claude/projects/$hash"
}

# Worktree-aware project dir: where this cwd's memory lives (main repo for worktrees).
wiki_project_dir() {
  wiki_hash_dir "$(wiki_resolve_main_root "${1:-}")"
}
