---
description: Run the weekly memory consolidation (Tier 2 rollups + Tier 3 distill). Spawns a background subagent that executes the bundled memory-consolidate.sh (deterministic bash; calls claude -p headlessly per week). Run when the SessionStart reminder says consolidation is overdue.
argument-hint: "[memory-dir | \"all\"]  (defaults to the current project)"
allowed-tools: Task
disable-model-invocation: true
---

# Weekly memory consolidation

The consolidation script, with its absolute path resolved at load time (tries the plugin-root env
var first, then the skill-dir fallback):

!`for R in "${CLAUDE_PLUGIN_ROOT:-}" "${CLAUDE_SKILL_DIR:-}/.."; do [ -n "$R" ] && [ -x "$R/bin/memory-consolidate.sh" ] && { echo "$R/bin/memory-consolidate.sh"; exit 0; }; done; echo "ERROR: could not locate memory-consolidate.sh — CLAUDE_PLUGIN_ROOT='${CLAUDE_PLUGIN_ROOT:-}' CLAUDE_SKILL_DIR='${CLAUDE_SKILL_DIR:-}'"`

If the line above starts with `ERROR:`, neither path variable resolved — report the two values shown
to the user and stop (do not spawn the subagent).

Otherwise, all the deterministic work lives in that bash script — your only job is to launch it
without flooding this session. Spawn a **background subagent** (Task tool, `run_in_background: true`)
with a clean context and give it this task, substituting the concrete script path printed above for
`<SCRIPT>` and the user's argument string for `<ARGS>` (the raw `$ARGUMENTS` for this command — may
be empty):

> Run the memory consolidation script and report the result. From the current project directory,
> execute exactly this via the Bash tool with a 600000 ms (10-minute) timeout:
>
>     <SCRIPT> <ARGS>
>
> The script is fully deterministic: it buckets session captures by ISO week, calls `claude -p`
> headlessly to produce each weekly rollup and the Tier-3 distillation, archives the consumed notes,
> deletes the raw transcripts, and updates `.memory-state.json`. With no argument it targets the
> current project; `all` targets every memory-enabled project; a path targets one memory dir.
>
> Your final message must be a terse summary only: which weeks were rolled up (and from how many
> captures) and the Tier-3 changes the script reported. Do NOT paste the script's full stdout or any
> transcript content.

Tell the user consolidation is running in the background and that you'll report the summary when the
subagent finishes. If the subagent reports the project isn't memory-enabled, point them at
`/claude-memory:init`.
