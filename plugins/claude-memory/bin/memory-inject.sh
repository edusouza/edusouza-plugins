#!/usr/bin/env bash
# Tier-1 + Tier-2 recall injection. Runs on SessionStart; prints memory context to
# stdout (which Claude Code adds to the session). Tier-3 (MEMORY.md + concept_*/
# project_* files) auto-loads natively and is NOT repeated here. Episodic layers are
# injected here ONLY (never indexed in MEMORY.md) to avoid context bloat.
#
# No-ops for projects without an initialized memory dir (opt-in). Always exits 0.
#
# PERFORMANCE: this blocks session start, and on Windows a spawn costs 0.15-1.1s
# (python 1.1s, git 0.9s, cygpath 0.5s cold). Everything that can be a bash builtin is
# one: the date arithmetic uses EPOCHSECONDS + printf '%(…)T', the path munging is
# parameter expansion, and the JSON payload is only parsed by python when Claude Code
# has not already handed us the project dir in the environment. See test/run-tests.sh.
set -uo pipefail

# --- recursion guard: do not inject into a headless consolidation invocation ---
[[ -n "${CLAUDE_MEMORY_CONSOLIDATING:-}" ]] && exit 0

# Shared path helpers (worktree-aware memory dir resolution).
DIR="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin}"
[[ -z "$DIR" || ! -f "$DIR/_memory-paths.sh" ]] && DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_memory-paths.sh
. "$DIR/_memory-paths.sh"

PAYLOAD="$(cat 2>/dev/null || true)"

# Prefer the cwd Claude Code already exported; only shell out to python to parse the
# JSON payload when it is absent (non-Claude hosts). Both land on the same memory dir:
# mem_project_dir maps a repo root, any subdirectory of it, and any linked worktree of
# it to one and the same main-worktree root.
CWD_RAW="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$CWD_RAW" ]]; then
  PYBIN="$(command -v python 2>/dev/null || command -v python3 2>/dev/null || true)"
  [[ -z "$PYBIN" ]] && exit 0
  CWD_RAW="$(printf '%s' "$PAYLOAD" | "$PYBIN" -c "import sys,json
try: print((json.loads(sys.stdin.read() or '{}').get('cwd') or ''))
except Exception: print('')" 2>/dev/null | tr -d '\r' || true)"
fi
[[ -z "$CWD_RAW" ]] && exit 0

# Worktree-aware: a linked worktree resolves to the main repo's memory dir.
MEMDIR="$(mem_project_dir "$CWD_RAW")/memory"
[[ -d "$MEMDIR" ]] || exit 0   # project not memory-enabled -> nothing to inject

{
  # Tell the model the absolute memory dir to read/write (Modes 1-3) — esp. important in a
  # worktree, where deriving it from cwd would point at the wrong (worktree) location.
  echo ""
  echo "## Memory - dir for this project"
  mem_to_mixed "$MEMDIR"; echo

  SDIR="$MEMDIR/episodic/sessions"
  if compgen -G "$SDIR/*.md" >/dev/null 2>&1; then
    echo ""
    echo "## Memory - recent sessions (Tier 1)"
    # One `ls -t` for the mtime ordering bash can't do on its own; the two-file limit
    # and the basenames are array slicing and parameter expansion.
    mapfile -t RECENT < <(ls -t "$SDIR"/*.md 2>/dev/null)
    for f in "${RECENT[@]:0:2}"; do
      echo ""; echo "### ${f##*/}"; cat "$f"
    done
  fi
  if compgen -G "$MEMDIR/episodic/weekly/*.md" >/dev/null 2>&1; then
    mapfile -t WEEKLIES < <(ls -t "$MEMDIR/episodic/weekly"/*.md 2>/dev/null)
    LASTWK="${WEEKLIES[0]:-}"
    if [[ -n "$LASTWK" ]]; then
      # TRIM: when a memory-wiki index already covers this same week topically, page by page,
      # everything below is a second telling of it — except `## Open threads`, which is
      # transient continuity ("still unresolved when the week ended") that no durable wiki page
      # reproduces. So in that one case we inject that section — every occurrence of it, capped
      # at 60 lines in total — instead of 200 lines of prose the model reads again in the index.
      #
      # The trigger is THIS WEEK CITED BY THE INDEX — not the existence of <memdir>/wiki/, and
      # not merely a populated index. The region memory-wiki renders between its markers lists
      # every rollup its pages were written from as `[[YYYY-Www]]`, so the newest rollup's name
      # appearing there means a page covers that week. A wiki holding only earlier weeks — every
      # project's state between consolidation and /memory-wiki:ingest — keeps the whole rollup,
      # because trimming it then would inject that week nowhere: not here, and not in a wiki that
      # has not ingested it yet. The same holds for a wiki that was scaffolded and never
      # ingested. The index is asked rather than wiki/log.md because a logged run may create no
      # pages at all, and a week no page holds is not covered.
      #
      # With no wiki at all — the majority of projects — nothing here changes, byte for byte, and
      # the `-f` test that decides so is a bash builtin, so that path pays no extra process.
      # Escape hatch: CLAUDE_MEMORY_ROLLUP_FULL=1 restores the full dump unconditionally.
      #
      # Both scans are `while read` loops rather than a grep/sed/awk per candidate: this runs in
      # a SessionStart hook and on Windows every spawn costs 0.15-1.1s (see the header note).
      ROLLUP_OPEN=()
      if [[ -z "${CLAUDE_MEMORY_ROLLUP_FULL:-}" \
            && -f "$MEMDIR/wiki/index.md" && -r "$MEMDIR/wiki/index.md" ]]; then
        # `-f` rather than `-r` alone on purpose: a directory or a FIFO at index.md satisfies
        # `-r`, and reading one here would print an error or block forever at session start.
        WEEK="${LASTWK##*/}"; WEEK="${WEEK%.md}"
        WIKI_COVERS=0 IN_REGION=0 RLINE=""
        while IFS= read -r RLINE || [[ -n "$RLINE" ]]; do
          # Only inside the managed markers: anything outside them is not the rendered index.
          # A trailing CR is absorbed by every pattern ending in `*`.
          case "$RLINE" in
            '<!-- BEGIN memory-wiki'*) IN_REGION=1 ;;
            '<!-- END memory-wiki'*)   IN_REGION=0 ;;
            *"[[$WEEK]]"*)             (( IN_REGION )) && { WIKI_COVERS=1; break; } ;;
          esac
        done 2>/dev/null < "$MEMDIR/wiki/index.md"
        if (( WIKI_COVERS )); then
          # EVERY `## Open threads` section, each running to the next heading that closes it,
          # with ONE 60-line cap across all of them. Not the first section only: a week
          # consolidated twice appends a second `# Week ...` document into the same file, and
          # on this project's own corpus four of eight rollups are doubled — so first-only
          # would silently drop half the open threads on half the weeks, which is exactly the
          # continuity this exception exists to preserve.
          #
          # A section is closed by the next `## ` heading OR by a `# ` h1, and an h1 is not
          # optional: in a doubled file the separator between the two bodies IS the h1, and at
          # least one real rollup here has no `## ` heading after its first open-threads
          # section at all — terminating on `## ` alone would swallow the whole second document
          # and present it as open threads. `### ` and deeper are left alone, since a
          # subheading below a section belongs to it.
          #
          # A trailing CR is left on each line, so a CRLF rollup is re-emitted with its own
          # endings; every pattern here ends in `*`, which absorbs it.
          IN_OPEN=0 RLINE=""
          while IFS= read -r RLINE || [[ -n "$RLINE" ]]; do
            case "$RLINE" in
              '## Open threads'*) IN_OPEN=1 ;;  # a section opens, or the next one re-opens
              '## '*|'# '*)       IN_OPEN=0 ;;  # ...and any other heading closes it
            esac
            (( IN_OPEN )) || continue
            ROLLUP_OPEN+=( "$RLINE" )
            (( ${#ROLLUP_OPEN[@]} >= 60 )) && break
          done 2>/dev/null < "$LASTWK"
        fi
      fi
      echo ""; echo "## Memory - last week (Tier 2)"
      echo "### ${LASTWK##*/}"
      # Empty array = the trim did not apply (no wiki, an un-ingested one, the escape hatch, or
      # a rollup with no `## Open threads` heading at all). Every one of those gets the dump
      # this block has always printed.
      if (( ${#ROLLUP_OPEN[@]} )); then
        printf '%s\n' "${ROLLUP_OPEN[@]}"
      else
        head -200 "$LASTWK"
      fi
    fi
  fi

  # Consolidation-overdue reminder: nags only when captures await rollup AND the last
  # weekly consolidation was >=7 days ago (or never). No background process / token spend.
  # Pure bash — this used to cost a second python interpreter start (~1.1s on Windows).
  PENDING=( "$SDIR"/*.md ); [[ -e "${PENDING[0]:-}" ]] || PENDING=()
  PENDING_CNT="${#PENDING[@]}"
  if (( PENDING_CNT > 0 )); then
    LAST=""
    if [[ -r "$MEMDIR/.memory-state.json" ]]; then
      STATE="$(<"$MEMDIR/.memory-state.json")"
      [[ "$STATE" =~ \"lastWeeklyConsolidation\"[[:space:]]*:[[:space:]]*\"([0-9]{4}-[0-9]{2}-[0-9]{2})\" ]] \
        && LAST="${BASH_REMATCH[1]}"
    fi
    # Missing/never/unparseable date all count as overdue, matching the previous behavior.
    OVERDUE=1
    if [[ -n "$LAST" ]]; then
      printf -v CUTOFF '%(%Y-%m-%d)T' $(( ${EPOCHSECONDS:-0} - 7*86400 ))
      [[ "$LAST" > "$CUTOFF" ]] && OVERDUE=0
    fi
    if (( OVERDUE )); then
      echo ""
      echo "## Memory - consolidation overdue"
      echo "$PENDING_CNT session capture(s) await rollup; last weekly consolidation was >=7 days ago (or never)."
      echo "Run:  /claude-memory:consolidate   (or use the /claude-memory:memory skill)."
    fi
  fi
} || true

exit 0
