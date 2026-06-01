# claude-plugins

A personal [Claude Code](https://code.claude.com) plugin marketplace.

## Install

```bash
/plugin marketplace add edusouza/claude-plugins
/plugin install claude-memory@claude-plugins
```

Update later with `/plugin marketplace update claude-plugins`.

## Plugins

| Plugin | Description |
|--------|-------------|
| [**claude-memory**](plugins/claude-memory) | Three-tier, brain-like cross-session memory: SessionEnd captures each session, a weekly consolidation distills durable decision-heuristics, and relevant memory is auto-injected at session start. Per-project, opt-in, local-only. |
| [**delivery-workflow**](plugins/delivery-workflow) | Feature delivery suite for GitHub: TDD `dev-workflow` (with a coverage Stop-gate hook), `epic-workflow` orchestration, `pr-review-fix`, and `pr-autoheal`. Drives code from issue to green PR. |
| [**issue-ops**](plugins/issue-ops) | Turn inputs into structured GitHub issues: `bug-rca` (code + observability root-cause analysis, diagnosis only) and `spec-to-issues` (spec/PRD folder → Epic→Spec→Task hierarchy). |
| [**context-docs**](plugins/context-docs) | Generate modular context-engineering docs under `docs/context/` that AI agents lazy-load on demand — architecture, standards, patterns, decisions — for any project. |
| [**design-to-ui**](plugins/design-to-ui) | Turn a design into UI components via atomic design. Source-agnostic (Stitch, Claude Design handoff/HTML, image) and framework-agnostic (React, Vue, Svelte, Angular, Solid). |

Install any of them with `/plugin install <name>@claude-plugins` (e.g. `/plugin install delivery-workflow@claude-plugins`).

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
