---
description: Audit this project's memory wiki for broken wikilinks, orphan pages, and missing frontmatter. Runs the bundled wiki-lint script and reports; never fixes anything.
argument-hint: "[memory-dir]  (defaults to the current project)"
allowed-tools: Bash(*)
disable-model-invocation: true
---

# Lint the memory wiki

!`for R in "${CLAUDE_PLUGIN_ROOT:-}" "${CLAUDE_SKILL_DIR:-}/.." "$(find "$HOME/.claude/plugins/cache/edusouza-plugins/memory-wiki" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | tail -1)"; do [ -n "$R" ] && [ -x "$R/bin/wiki-lint.sh" ] && { . "$R/bin/_wiki-paths.sh"; M="${ARGUMENTS:-$(wiki_project_dir "$PWD")/memory}"; [ -d "$M" ] || { echo "ERROR: no memory dir: $M"; exit 0; }; W="$M/wiki"; [ -d "$W" ] || W="$M"; exec "$R/bin/wiki-lint.sh" "$W" --sources "$M/episodic/weekly" --atlas "$HOME/.claude/memory-wiki"; }; done; echo "ERROR: could not locate wiki-lint.sh — CLAUDE_PLUGIN_ROOT='${CLAUDE_PLUGIN_ROOT:-}' CLAUDE_SKILL_DIR='${CLAUDE_SKILL_DIR:-}'"`

Relay the report above verbatim — it is exhaustive about structure by construction, so do not
re-derive or summarize the counters.

Then add the two readings the numbers do not carry on their own:

- **If any links are broken**, check whether their targets look like human titles or kebab-slugs
  rather than filenames. That is the most common cause and the fix is a rename, not a new page.
- **If any pages lack frontmatter**, check whether they use a nested `metadata:` block. Those come
  from the global auto-memory's schema, not from a malformed page — report it as a schema collision.

If the output starts with `ERROR: no memory dir`, the project has not opted into claude-memory; tell
the user to run `/claude-memory:init`. For the judgment-based content checks — contradictions, stale
claims, missing pages — use the `lint` skill, which does the reading this command does not.

**This command reports. It does not fix anything, and neither should you without being asked.**
