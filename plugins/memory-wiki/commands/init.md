---
description: Scaffold the memory-wiki layer inside this project's existing claude-memory dir. Creates wiki/, wiki/inbox/, wiki/log.md, and the page-schema README. Idempotent — safe to re-run.
argument-hint: "[project-dir]  (defaults to the current project)"
allowed-tools: Bash
disable-model-invocation: true
---

# Initialize the memory wiki for this project

The deterministic work is done by the bundled script — this command just runs it. Claude Code
substitutes the plugin root into the command text before any shell runs, so no path lookup is needed:

!`"${CLAUDE_PLUGIN_ROOT}/bin/wiki-init.sh" "$ARGUMENTS"`

Relay the script output above to the user. On success it reports whether the wiki was newly created
or already existed, and the resolved wiki path.

If the output contains `ERROR: no memory dir`, this project has not opted into claude-memory — tell
the user to run `/claude-memory:init` first. Do not create the directory yourself.
