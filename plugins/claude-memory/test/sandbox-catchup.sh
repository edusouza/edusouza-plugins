#!/usr/bin/env bash
# Sandboxed behavioural check for the catch-up sweep.
#
# Runs a given memory-catchup.sh against a synthetic project (fake $HOME, fake
# transcript dir) and prints the resulting capture set, so two implementations can be
# diffed. Takes: <bin-dir-containing-memory-catchup.sh> <sandbox-root>
#
# Fixture covers every branch of the sweep's skip logic:
#   aaaaaaaa / bbbbbbbb  old transcripts, no note      -> MUST be captured
#   cccccccc             mtime = now                   -> skipped (MIN_AGE)
#   dddddddd             == current session id         -> skipped (self)
#   eeeeeeee             note already in sessions/     -> skipped (idempotent)
#   ffffffff             note already in archive/      -> skipped (consolidated)
set -uo pipefail
BIN="$1"; SB="$2"
rm -rf "$SB"; mkdir -p "$SB"

CWD="$SB/proj"; mkdir -p "$CWD"          # deliberately NOT a git repo
HASH="${CWD//\//-}"; HASH="${HASH//:/-}" # mirrors mem_hash_dir for a posix path
PROJ="$SB/.claude/projects"
# resolve the hash the way the lib does, so this fixture can't drift from it
TX="$( HOME="$SB"; . "$BIN/_memory-paths.sh"; mem_hash_dir "$CWD" )"
mkdir -p "$TX/memory/episodic/sessions/archive" "$TX/memory/episodic/sessions/raw"

OLD_TS="202601010000"
for sid in aaaaaaaa-1111-1111-1111-111111111111 bbbbbbbb-2222-2222-2222-222222222222 \
           dddddddd-4444-4444-4444-444444444444 eeeeeeee-5555-5555-5555-555555555555 \
           ffffffff-6666-6666-6666-666666666666; do
  printf '{"type":"user"}\n' > "$TX/$sid.jsonl"
  touch -t "$OLD_TS" "$TX/$sid.jsonl"
done
printf '{"type":"user"}\n' > "$TX/cccccccc-3333-3333-3333-333333333333.jsonl"   # fresh mtime

echo "pre-existing" > "$TX/memory/episodic/sessions/2026-01-01-eeeeeeee.md"
echo "consolidated" > "$TX/memory/episodic/sessions/archive/2026-01-01-ffffffff.md"

PAY="$SB/pay.json"
{ printf '{"cwd":"%s","session_id":"dddddddd-4444-4444-4444-444444444444"}' "$CWD"; } > "$PAY"

HOME="$SB" CLAUDE_PLUGIN_ROOT="" bash "$BIN/memory-catchup.sh" < "$PAY" >/dev/null 2>&1

echo "--- captures ---"
( cd "$TX/memory/episodic/sessions" && ls -1 *.md 2>/dev/null | sed 's/^[0-9-]*-//' | sort )
echo "--- raw snapshots ---"
( cd "$TX/memory/episodic/sessions/raw" && ls -1 *.jsonl 2>/dev/null | sed 's/^[0-9-]*-//' | sort )
echo "--- stray files (marker leaks) ---"
( cd "$TX/memory/episodic/sessions" && ls -1a 2>/dev/null | grep -E '^\.' | grep -v '^\.\.$' | grep -v '^\.$' | sort )
