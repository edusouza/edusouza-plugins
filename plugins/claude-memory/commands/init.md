---
description: Enable three-tier cross-session memory for the current project (opt-in). Runs the bundled memory-init.sh, which creates the user-local memory dir and seeds MEMORY.md + state; afterward the SessionEnd capture and SessionStart recall hooks are active for this project.
argument-hint: "[project-dir]  (defaults to the current project)"
allowed-tools: Bash
disable-model-invocation: true
---

# Enable memory for this project

The deterministic work is done by the bundled script — this command just runs it. The plugin root is
substituted into the command text before the shell runs, so no path lookup is needed:

!`"${CLAUDE_PLUGIN_ROOT}/bin/memory-init.sh" "$ARGUMENTS"`

Relay the script output above to the user. On success it reports whether memory was newly enabled or
was already active, and the resolved memory dir path (an empty argument means "the current project").
