# claude-plugins

A personal [Claude Code](https://code.claude.com) plugin marketplace.

## Install

```bash
/plugin marketplace add edusouza/edusouza-plugins
/plugin install claude-memory@edusouza-plugins
```

Update later with `/plugin marketplace update edusouza-plugins`.

## Plugins

| Plugin | Description |
|--------|-------------|
| [**claude-memory**](plugins/claude-memory) | Three-tier cross-session memory for Claude Code: per-session captures consolidate weekly into durable abstractions, auto-injected at session start. Per-project, opt-in, local-only. |
| [**delivery-workflow**](plugins/delivery-workflow) | Feature delivery suite for GitHub: a TDD dev-workflow (with a coverage Stop-gate hook), epic orchestration across an issue hierarchy, PR review-comment resolution, PR-bound CI autoheal, and branch/main CI autoheal for deployment pipelines. Drives code from issue to green. |
| [**issue-ops**](plugins/issue-ops) | Turn inputs into structured GitHub issues: `bug-rca` (code + observability root-cause analysis, diagnosis only) and `spec-to-issues` (spec/PRD folder → Epic→Spec→Task hierarchy). |
| [**context-docs**](plugins/context-docs) | Generate modular context-engineering docs under `docs/context/` that AI agents lazy-load on demand — architecture, standards, patterns, decisions — for any project. |
| [**design-to-ui**](plugins/design-to-ui) | Turn a design into UI components via atomic design. Source-agnostic (Stitch, Claude Design handoff/HTML, image) and framework-agnostic (React, Vue, Svelte, Angular, Solid). |

Install any of them with `/plugin install <name>@edusouza-plugins` (e.g. `/plugin install delivery-workflow@edusouza-plugins`).

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
