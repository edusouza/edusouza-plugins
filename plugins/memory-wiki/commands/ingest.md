---
description: Distil this project's un-ingested weekly rollups and inbox captures into memory-wiki pages, regenerate the index, and append the ingest ledger. Prints the work order first, then runs the ingest skill against it.
argument-hint: "[memory-dir]  (defaults to the current project)"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep
disable-model-invocation: true
---

# Ingest into the memory wiki

The work order — what is still pending, what pages already exist, what is waiting in the inbox.
Claude Code substitutes the plugin root before any shell runs, so no path lookup is needed.
Stderr is folded in because the no-wiki report is printed there, not on stdout:

!`"${CLAUDE_PLUGIN_ROOT}/bin/wiki-ingest-plan.sh" "$ARGUMENTS" 2>&1`

Now run the `ingest` skill, following its eight steps in order, with three things settled here:

1. **The work order above is the input.** Skip the skill's step 1 — it has already run, and its
   output is what you see. Do not re-derive which rollups are pending by globbing
   `episodic/weekly/`; that directory holds every week ever written, and the ones already cited in
   `wiki/log.md` have been ingested. The memory dir the report was built from is the one to work
   in for every remaining step.
2. **If the output is `ERROR: no wiki for: <memdir>`**, stop. Tell the user to run
   `/memory-wiki:init` to scaffold the wiki — and `/claude-memory:init` first if that reports no
   memory dir either. Create nothing yourself: not the wiki, not the memory dir, not a page.
3. **If `## Pending sources` is `(none)` and `## Inbox` is `(none)`, stop and say so.** There is
   nothing to ingest. Re-ingesting a week already recorded in the ledger is how duplicate pages
   get made, and nothing on the resulting pages reveals afterwards that it happened.

Everything else — the authoring rules, the index regeneration, the ledger entry, the lint pass and
the report shape — is the skill's, and it is the authority on all of it.
