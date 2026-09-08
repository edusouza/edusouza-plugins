#!/usr/bin/env bash
# Sandboxed behavioural check for the SessionEnd capture core.
# Runs <bin-dir>/memory-capture.sh against a fake $HOME whose memory dir is pre-created,
# using the real repo as cwd so the git metadata block is exercised, then prints the
# resulting note with the volatile timestamp normalized so two runs can be diffed.
# Usage: sandbox-capture.sh <bin-dir> <sandbox-root> <repo> <branch-override-payload-cwd>
set -uo pipefail
BIN="$1"; SB="$2"; REPO="$3"
rm -rf "$SB"; mkdir -p "$SB"

MEMROOT="$( HOME="$SB"; . "$BIN/_memory-paths.sh"; mem_project_dir "$REPO" )"
mkdir -p "$MEMROOT/memory/episodic/sessions/raw"

# A small fake transcript so the raw-snapshot branch runs without copying megabytes.
TXT="$SB/fake-transcript.jsonl"
printf '{"type":"user"}\n{"type":"assistant"}\n' > "$TXT"
touch -t 202602030405 "$TXT"

PAY="$SB/pay.json"
printf '{"cwd":"%s","session_id":"abcd1234-0000-0000-0000-000000000000","transcript_path":"%s"}' \
  "$REPO" "$TXT" > "$PAY"

HOME="$SB" CLAUDE_PLUGIN_ROOT="" bash "$BIN/memory-capture.sh" < "$PAY" >/dev/null 2>&1

N="$MEMROOT/memory/episodic/sessions/2026-02-03-abcd1234.md"
if [[ -f "$N" ]]; then
  sed -e 's/^- captured_at: .*/- captured_at: <NORMALIZED>/' "$N"
else
  echo "NO NOTE WRITTEN at $N"
  ls -R "$MEMROOT/memory" 2>/dev/null
fi
echo "--- raw snapshot ---"
ls -1 "$MEMROOT/memory/episodic/sessions/raw" 2>/dev/null
