---
description: Enable three-tier cross-session memory for the current project (opt-in). Runs the bundled memory-init.sh, which creates the user-local memory dir and seeds MEMORY.md + state; afterward the SessionEnd capture and SessionStart recall hooks are active for this project.
argument-hint: "[project-dir]  (defaults to the current project)"
allowed-tools: Bash(*)
disable-model-invocation: true
---

# Enable memory for this project

The deterministic work is done by the bundled script — this command just runs it. The resolver tries
the plugin-root env var first, then the skill-dir fallback, so it works regardless of which one
Claude Code sets in the injection context:

!`for R in "${CLAUDE_PLUGIN_ROOT:-}" "${CLAUDE_SKILL_DIR:-}/.."; do [ -n "$R" ] && [ -x "$R/bin/memory-init.sh" ] && exec "$R/bin/memory-init.sh" "$ARGUMENTS"; done; echo "ERROR: could not locate memory-init.sh — CLAUDE_PLUGIN_ROOT='${CLAUDE_PLUGIN_ROOT:-}' CLAUDE_SKILL_DIR='${CLAUDE_SKILL_DIR:-}'"`

Relay the script output above to the user. On success it reports whether memory was newly enabled or
was already active, and the resolved memory dir path (an empty argument means "the current project").
If the line starts with `ERROR:`, neither path variable resolved — tell the user the two values shown
so the command's resolver can be fixed.
