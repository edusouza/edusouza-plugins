#!/usr/bin/env bash
# Shared SessionStart preamble for wiki-inject.sh and wiki-nudge.sh. SOURCE this file; do not
# execute it.
#
# The two hooks must resolve a session to the same memory dir, or the index and the ingest
# nudge would land in different projects. Keeping that rule in one place is what keeps them
# agreed. Everything here is a builtin or a `.`, so sourcing it costs neither hook a process.
#
#   wiki_hook_memdir   drain the hook payload, resolve the session's cwd, set MEMDIR.
#                      Returns 1, with MEMDIR empty, when there is no usable cwd.

# shellcheck source=_wiki-paths.sh
. "${BASH_SOURCE[0]%/*}/_wiki-paths.sh" 2>/dev/null

wiki_hook_memdir() {
  MEMDIR=""
  local payload="" cwd="${CLAUDE_PROJECT_DIR:-}" py=""

  # `read -d ''` drains stdin with a builtin; `$(cat)` would cost a process. It is drained even
  # when CLAUDE_PROJECT_DIR makes the payload unnecessary, so Claude Code's writer never takes an
  # EPIPE, and skipped on a terminal so a hand-run does not wait for input that never comes.
  [[ -t 0 ]] || IFS= read -r -d '' payload || true

  # Prefer the cwd Claude Code exported, exactly as claude-memory's memory-inject.sh does, and
  # pay for python only when it is absent (non-Claude hosts): it is the most expensive spawn
  # either hook can make. `python` is tried first because a WindowsApps `python3` shim can
  # resolve ahead of the real interpreter.
  if [[ -z "$cwd" && -n "$payload" ]]; then
    if command -v python >/dev/null 2>&1; then
      py="python"
    elif command -v python3 >/dev/null 2>&1; then
      py="python3"
    else
      return 1
    fi
    # Every malformed shape lands on the empty string: not JSON, JSON that is not an object, an
    # object with no `cwd`, a null `cwd`. A here-string rather than a pipe, so this costs one
    # process and not one process plus a forked writer.
    cwd="$("$py" -c '
import sys, json
try:
    d = json.loads(sys.stdin.read())
    v = d.get("cwd") if isinstance(d, dict) else None
    if isinstance(v, str) and v:
        sys.stdout.write(v)
except Exception:
    pass' <<< "$payload" 2>/dev/null)"
    cwd="${cwd%$'\r'}"
  fi
  [[ -n "$cwd" ]] || return 1

  # Worktree-aware, and resolved exactly once per hook: a linked worktree shares the MAIN repo's
  # memory dir. The shared vendored resolver, never a faster private copy — that is precisely how
  # a project's memory and its wiki end up in different directories.
  MEMDIR="$(wiki_project_dir "$cwd")/memory"
}
