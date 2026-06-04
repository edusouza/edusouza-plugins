---
description: Enable three-tier cross-session memory for the current project (opt-in). Runs the bundled memory-init.sh, which creates the user-local memory dir and seeds MEMORY.md + state; afterward the SessionEnd capture and SessionStart recall hooks are active for this project.
argument-hint: "[project-dir]  (defaults to the current project)"
allowed-tools: Bash(*)
disable-model-invocation: true
---

# Enable memory for this project

The deterministic work is done by the bundled script — this command just runs it:

!`"${CLAUDE_PLUGIN_ROOT}/bin/memory-init.sh" "$ARGUMENTS"`

Relay the script output above to the user. It reports whether memory was newly enabled or was
already active, and the resolved memory dir path. An empty argument means "the current project".
