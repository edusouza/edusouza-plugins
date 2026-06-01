# claude-code-plugins

A personal [Claude Code](https://code.claude.com) plugin marketplace.

## Install

```bash
/plugin marketplace add edusouza/claude-code-plugins
/plugin install claude-memory@claude-code-plugins
```

Update later with `/plugin marketplace update claude-code-plugins`.

## Plugins

| Plugin | Description |
|--------|-------------|
| [**claude-memory**](plugins/claude-memory) | Three-tier, brain-like cross-session memory: SessionEnd captures each session, a weekly consolidation distills durable decision-heuristics, and relevant memory is auto-injected at session start. Per-project, opt-in, local-only. |

## Local development

Test a plugin without installing from the marketplace:

```bash
claude --plugin-dir ./plugins/claude-memory
```

## Layout

```
.claude-plugin/marketplace.json   # marketplace catalog
plugins/<name>/                   # one directory per plugin
  .claude-plugin/plugin.json
  hooks/ bin/ prompts/ skills/ ...
```

Add a new plugin by dropping it under `plugins/` and adding an entry to
`.claude-plugin/marketplace.json`.
