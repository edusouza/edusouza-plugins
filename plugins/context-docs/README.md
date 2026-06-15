# context-docs

Generate a modular set of **context-engineering docs** under `docs/context/` that AI agents lazy-load on
demand — so an agent loads only the file relevant to its current task.

| Skill | What it does | Trigger |
|-------|--------------|---------|
| `project-context-docs` | Scans config, source, tests, CI/CD, docs, and git history, then writes `INDEX.md` (always loaded) plus `architecture.md`, `adrs.md`, `standards.md`, `patterns.md`, `testing.md`, `examples.md`, `troubleshooting.md`, and `tooling.md`. | "document this project", "create context docs", "onboarding docs for agents" |

Works on any stack — it detects npm/Cargo/Go/Python/Ruby/Java build files, multiple agent-doc conventions,
and the project's component structure.

## Install
```bash
/plugin install context-docs@claude-plugins
```

## Dependencies
- `git` and read-only file tools only. No external services, no API keys.
- States facts observed from the code; flags ambiguities rather than inventing them.
