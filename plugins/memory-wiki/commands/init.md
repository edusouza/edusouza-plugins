---
description: Scaffold the memory-wiki layer inside this project's existing claude-memory dir. Creates wiki/, wiki/inbox/, wiki/log.md, and the page-schema README. Idempotent — safe to re-run.
argument-hint: "[project-dir]  (defaults to the current project)"
allowed-tools: Bash(*)
disable-model-invocation: true
---

# Initialize the memory wiki for this project

The deterministic work is done by the bundled script — this command just runs it. The resolver tries
the plugin-root env var first, then the skill-dir fallback, then the plugin cache, so it works
regardless of which one Claude Code sets in the injection context:

!`for R in "${CLAUDE_PLUGIN_ROOT:-}" "${CLAUDE_SKILL_DIR:-}/.." "$(find "$HOME/.claude/plugins/cache/edusouza-plugins/memory-wiki" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | tail -1)"; do [ -n "$R" ] && [ -x "$R/bin/wiki-init.sh" ] && exec "$R/bin/wiki-init.sh" "$ARGUMENTS"; done; echo "ERROR: could not locate wiki-init.sh — CLAUDE_PLUGIN_ROOT='${CLAUDE_PLUGIN_ROOT:-}' CLAUDE_SKILL_DIR='${CLAUDE_SKILL_DIR:-}'"`

Relay the script output above to the user. On success it reports whether the wiki was newly created
or already existed, and the resolved wiki path.

- If the output starts with `ERROR: no memory dir`, this project has not opted into claude-memory —
  tell the user to run `/claude-memory:init` first. Do not create the directory yourself.
- If it starts with `ERROR: could not locate`, neither path variable resolved — report the two
  values shown so the resolver can be fixed.
