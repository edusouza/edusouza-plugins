# memory-wiki

Turns [`claude-memory`](../claude-memory)'s flat Tier-3 concepts into a cross-linked, searchable
wiki. It reads what `claude-memory` writes and never modifies it — capture and weekly rollups stay
exactly where they are.

**Phase 1 (this release) is the deterministic half:** an audit that works on the memory you already
have, before a single page is generated.

| Skill / command | What it does |
| --- | --- |
| `/memory-wiki:init` | Scaffolds `wiki/`, `wiki/inbox/`, `wiki/log.md`, and the page-schema README inside an existing memory dir. Idempotent. |
| `/memory-wiki:lint` | Runs the structural audit: broken wikilinks, orphan pages, missing frontmatter, injection budget. |
| `lint` skill | The same audit, plus the judgment checks a script cannot make — contradictions, stale claims, missing pages, weak cross-references. |

## Why

Tier-3 distillation already writes `[[wikilinks]]` spontaneously — nothing instructs it to, and
nothing validates them. Across 32 memory-enabled projects on one machine, **39% of those links
resolve to no existing page** and **63% of pages have no inbound link at all**. Three naming
conventions are in use at once (human titles, kebab-slugs, `snake_case` filenames) with no schema to
arbitrate between them.

`lint` is what notices. It reports; it never fixes.

## Install

```bash
/plugin install memory-wiki@edusouza-plugins
```

## Usage

```
/claude-memory:init      # once, if this project has no memory yet
/memory-wiki:lint        # audit — works on a bare memory dir, no wiki needed
/memory-wiki:init        # scaffold wiki/ when you are ready for Phase 2
```

`lint` deliberately works *before* `init`. A memory dir full of flat `concept_*.md` files is a wiki
with no edges, and auditing it is the point.

## Dependencies

- `bash` (git-bash on Windows) and `git` on `PATH`.
- `python` (3.x) — used only by the test harness to parse JSON, not at runtime.
- `pwsh` optional. A PowerShell twin of the linter ships alongside the bash original and is held to
  byte-identical output; reach for it where shelling out through bash is unreliable.
- `claude-memory` for anything to audit. Not a hard requirement — the plugins install independently
  and `memory-wiki` vendors its own copy of the path resolution — but a project with no memory dir
  has nothing to lint, and `init` will say so rather than creating one.

## Tests

```bash
bash plugins/memory-wiki/test/run-tests.sh
```

Golden-file fixtures, a bash/PowerShell output-parity check, a cross-check that the vendored path
resolver agrees with `claude-memory`'s own, and a shape-only smoke test against a real memory dir.
No framework, no dependencies beyond the above.

Byte counts in the golden files are **not** platform artifacts: `wiki-lint` strips CR before
measuring, so the same fixture reports the same number on CRLF and LF input. If a count differs, fix
the script, not the golden file.

## License

MIT
