---
description: Audit this project's memory wiki for broken wikilinks, orphan pages, and missing frontmatter. Runs the bundled wiki-lint script and reports; never fixes anything.
argument-hint: "[memory-dir]  (defaults to the current project)"
allowed-tools: Bash
disable-model-invocation: true
---

# Lint the memory wiki

Memory-dir resolution and the source/atlas roots live in the bundled script, so this command is just
its invocation — Claude Code substitutes the plugin root before any shell runs:

!`"${CLAUDE_PLUGIN_ROOT}/bin/wiki-lint-project.sh" "$ARGUMENTS"`

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
