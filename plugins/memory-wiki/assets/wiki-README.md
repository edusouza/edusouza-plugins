# This project's memory wiki

Generated and maintained by the `memory-wiki` plugin. Pages here are LLM-owned; the sources they
cite live in `../episodic/weekly/` and are immutable.

## Page types

| Prefix | Holds |
| --- | --- |
| `project_` | a repo: conventions, environment, standing threads |
| `component_` | a plugin, script, or subsystem within a project |
| `tech_` | external tool or platform mechanics |
| `failure_` | symptom → cause → fix → generalization |
| `concept_` | a durable heuristic (owned by claude-memory; read here, never rewritten) |

`failure_` and `concept_` are deliberately separate. A concept says *what to do*; a failure page
says *what you saw*. You search a failure page by the error text in front of you.

## Rules

- **All internal links are `[[exact-filename-without-extension]]`** — never the human title, never a
  kebab-slug that does not match a file. This one rule is what keeps the graph connected. Before it
  existed, 39% of the wikilinks across this machine's memory dirs resolved to nothing, because three
  naming conventions were in use at once with no schema to arbitrate.
- Source citations use the rollup filename: `[[2026-W28]]`.
- Links to the cross-project atlas use `[[atlas/<page>]]`.
- Atlas pages link *back* via their `evidence:` frontmatter, not via wikilinks — separate vaults
  cannot resolve them. This asymmetry is deliberate; `lint` does not flag it.

## Required frontmatter

Every page carries a `---` fenced block on line 1 containing, at minimum:

```yaml
---
name: <Human Title, sentence case>
description: <one-line recall summary>
type: project | component | tech | failure | concept
status: active | dormant | superseded
last_accessed: YYYY-MM-DD
---
```

Flat, not nested under a `metadata:` key — `lint` reads only top-level keys, so an indented one is
invisible to it and the page reports as though the field were absent.

Some types require more than the base:

| `type:` | also required |
| --- | --- |
| `project`, `tech` | `sources` |
| `component` | `part_of`, `sources` |
| `failure` | `symptom`, `sources` |
| `concept` | nothing extra |

- **`symptom:` is what a failure page is found by.** Recall matches the error text in front of you
  against that line, so a failure page without one is unreachable by the only search anyone runs.
- **`sources:` is what makes a claim checkable.** Every page but a `concept_` is distilled from a
  weekly rollup, and the citation is what lets a later reader trace the claim back to what actually
  happened. `concept_` pages are exempt because `claude-memory` owns them and cites elsewhere.

`lint` reports an absent field and an out-of-range value as **separate** findings: a missing
`type:`/`status:` appears under `NO FRONTMATTER`, while a value outside the lists above appears
under `SCHEMA` as `<page> (invalid: type=<v>)`. A page with no readable top-level `type:` is
reported once, for the missing field, and is not additionally judged against any type's extra
requirements.

## Directories

- `inbox/` — fleeting in-session captures, triaged by the next ingest. Write here when you are
  unsure whether something deserves a page.
- `log.md` — append-only record of every operation.

## Maintenance

Run `/memory-wiki:lint` to audit this wiki for broken links, orphans, missing frontmatter, and
schema errors. It reports; it never fixes.
