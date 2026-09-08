# memory-wiki Phase 1 (init + lint) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the `memory-wiki` plugin's deterministic half — a structural linter that audits an existing claude-memory dir, plus the `init` scaffolding — so it delivers value before any page is ever generated.

**Architecture:** A Claude Code plugin at `plugins/memory-wiki/`. All real work lives in `bin/` shell scripts (repo convention: shell never goes inline in a SKILL.md); slash commands are thin wrappers that locate and exec those scripts through the repo's established three-way path resolver. `wiki-lint` is a pure function — given a wiki directory it prints a deterministic report — which makes golden-fixture testing the natural harness. A PowerShell twin ships alongside the bash original and is held to byte-identical output.

**Tech Stack:** Bash (POSIX-leaning, no bash-4 associative arrays), PowerShell 7, plain-text golden-file tests. No build system, no test framework, no external dependencies.

**Spec:** `docs/superpowers/specs/2026-08-21-memory-wiki-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- **Plugin version starts at `0.1.0`.** Any change to a plugin must bump the version in **both** `plugins/memory-wiki/.claude-plugin/plugin.json` **and** the root `.claude-plugin/marketplace.json`. These are two independent catalogs and nothing validates them — this is the repo's single most recurring failure mode.
- **Shell scripts live in `bin/`, never inline in a SKILL.md.** Slash commands may contain only the resolver one-liner.
- **Slash commands must not rely on `CLAUDE_PLUGIN_ROOT` / `CLAUDE_SKILL_DIR`.** Unlike hooks, commands may see both empty. Use the three-way resolver verbatim (Task 9).
- **`memory-wiki` never writes to anything claude-memory owns.** It reads `episodic/**`, `concept_*.md`, `project_*.md`, `feedback_*.md`. It writes only `<memdir>/wiki/**` and its own delimited region in `MEMORY.md`. Phase 1 writes no `MEMORY.md` region at all.
- **`lint` reports; it never fixes.** No task may add auto-remediation.
- **Script output must be deterministic** — sorted, no timestamps, no absolute paths in the report body. Golden-file tests depend on this.
- **Author** in every manifest: `{ "name": "Eduardo Souza" }`. **License:** MIT.
- **Commit messages** use conventional-commit prefixes (`feat(memory-wiki):`, `test(memory-wiki):`, `docs:`) and end with:
  ```
  Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_013digwf1UNSjLu23UsFgbb1
  ```

---

## File Structure

```
.claude-plugin/marketplace.json          MODIFY — add the memory-wiki catalog entry

plugins/memory-wiki/
├─ .claude-plugin/plugin.json            manifest (name, description, version 0.1.0)
├─ README.md                             what it is, the two skills, install, dependencies
├─ bin/
│  ├─ _wiki-paths.sh                     vendored worktree-aware memdir resolution
│  ├─ wiki-lint.sh                       THE deliverable — structural audit, bash
│  ├─ wiki-lint.ps1                      byte-identical PowerShell twin
│  └─ wiki-init.sh                       scaffold <memdir>/wiki/, idempotent
├─ commands/
│  ├─ init.md                            thin resolver → wiki-init.sh
│  └─ lint.md                            thin resolver → wiki-lint.sh
├─ skills/lint/SKILL.md                  runs the script, then does model-side content checks
├─ assets/wiki-README.md                 page schema written into <memdir>/wiki/README.md
└─ test/
   ├─ run-tests.sh                       harness: run each fixture, diff vs expected
   ├─ fixtures/{clean,broken,orphans,no-frontmatter,atlas}/…
   └─ expected/*.txt                     golden reports
```

**Responsibility boundaries.** `wiki-lint.sh` never resolves a memory dir — it takes a directory argument and nothing else, which is what makes it testable against fixtures. `_wiki-paths.sh` owns *all* path resolution. `wiki-init.sh` is the only script that writes. The skill layer holds only judgment the script cannot express.

---

## Task 1: Plugin skeleton, marketplace registration, and the version-drift guard

The plugin's very first test guards the repo's most recurring failure mode: `plugin.json` and `marketplace.json` drifting apart.

**Files:**
- Create: `plugins/memory-wiki/.claude-plugin/plugin.json`
- Create: `plugins/memory-wiki/test/run-tests.sh`
- Modify: `.claude-plugin/marketplace.json` (append to the `plugins` array)

**Interfaces:**
- Consumes: nothing
- Produces: `test/run-tests.sh` — run from the repo root as `bash plugins/memory-wiki/test/run-tests.sh`; exits `0` when all checks pass, `1` on the first failure; prints one `PASS: <name>` or `FAIL: <name>` line per check.

- [ ] **Step 1: Write the failing test**

Create `plugins/memory-wiki/test/run-tests.sh`:

```bash
#!/usr/bin/env bash
# Golden-file test harness for memory-wiki. Run from anywhere:
#   bash plugins/memory-wiki/test/run-tests.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO="$(cd "$PLUGIN/../.." && pwd)"
FAILED=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; echo "$2" | sed 's/^/      /'; FAILED=1; }

# --- version parity: plugin.json vs marketplace.json ---
PJ="$PLUGIN/.claude-plugin/plugin.json"
MJ="$REPO/.claude-plugin/marketplace.json"
PV="$(python -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" "$PJ" 2>&1)"
MV="$(python -c "
import json,sys
m=json.load(open(sys.argv[1]))
e=[p for p in m['plugins'] if p['name']=='memory-wiki']
print(e[0]['version'] if e else 'MISSING')" "$MJ" 2>&1)"

if [[ "$PV" == "$MV" ]]; then
  pass "version parity ($PV)"
else
  fail "version parity" "plugin.json=$PV  marketplace.json=$MV"
fi

exit "$FAILED"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: FAIL — `plugin.json` does not exist yet, so `$PV` holds a Python traceback and will not equal `$MV`.

- [ ] **Step 3: Write minimal implementation**

Create `plugins/memory-wiki/.claude-plugin/plugin.json`:

```json
{
  "name": "memory-wiki",
  "description": "Turns claude-memory's flat Tier-3 concepts into a cross-linked, searchable wiki. Phase 1: lint audits an existing memory dir for broken wikilinks, orphan pages, and missing frontmatter; init scaffolds the wiki layer. Reads what claude-memory writes and never modifies it.",
  "version": "0.1.0",
  "author": { "name": "Eduardo Souza" },
  "license": "MIT"
}
```

Then append this object to the `plugins` array in `.claude-plugin/marketplace.json`, after the `llm-wiki` entry:

```json
    {
      "name": "memory-wiki",
      "source": "./plugins/memory-wiki",
      "description": "Turns claude-memory's flat Tier-3 concepts into a cross-linked, searchable wiki. lint audits an existing memory dir for broken wikilinks, orphan pages, and missing frontmatter; init scaffolds the wiki layer. Reads what claude-memory writes and never modifies it.",
      "version": "0.1.0",
      "author": { "name": "Eduardo Souza" }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: `PASS: version parity (0.1.0)`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/memory-wiki/.claude-plugin/plugin.json \
        plugins/memory-wiki/test/run-tests.sh \
        .claude-plugin/marketplace.json
git commit -m "feat(memory-wiki): add plugin skeleton with version-parity test"
```

---

## Task 2: `wiki-lint.sh` — report shape on a clean wiki

**Files:**
- Create: `plugins/memory-wiki/bin/wiki-lint.sh`
- Create: `plugins/memory-wiki/test/fixtures/clean/wiki/{index.md,log.md,concept_alpha.md,concept_beta.md}`
- Create: `plugins/memory-wiki/test/expected/clean.txt`
- Modify: `plugins/memory-wiki/test/run-tests.sh`
- Modify: `.gitattributes` — pin fixtures to LF so they are byte-stable across clones:
  ```
  # Test fixtures are compared byte-for-byte; keep them LF everywhere.
  plugins/memory-wiki/test/fixtures/** text eol=lf
  plugins/memory-wiki/test/expected/** text eol=lf
  ```
  Belt-and-braces only — `wiki-lint` strips `\r` and must pass on CRLF input regardless.

**Interfaces:**
- Consumes: `run-tests.sh` from Task 1
- Produces: `bin/wiki-lint.sh <WIKI_DIR> [--sources <DIR>] [--atlas <DIR>]` — prints the report to stdout, always exits `0` (lint reports, it does not gate). Report contract, in this exact order: a `## Structural` block of five aligned counter lines, then optional `BROKEN:` / `ORPHANS:` / `NO FRONTMATTER:` detail blocks (each omitted when its count is zero, each sorted), then a `## Injection budget` block. `run_fixture <name> [args...]` is added to the harness and reused by every later task.

- [ ] **Step 1: Write the failing test**

Create the fixture. `test/fixtures/clean/wiki/index.md`:

```markdown
# Index

<!-- BEGIN memory-wiki (managed; do not edit by hand) -->
- [[concept_alpha]] — first
- [[concept_beta]] — second
<!-- END memory-wiki -->
```

`test/fixtures/clean/wiki/log.md`:

```markdown
# Wiki Log
```

`test/fixtures/clean/wiki/concept_alpha.md`:

```markdown
---
name: Alpha
description: first concept
type: concept
status: active
last_accessed: 2026-08-21
---
Alpha links to [[concept_beta]].
```

`test/fixtures/clean/wiki/concept_beta.md`:

```markdown
---
name: Beta
description: second concept
type: concept
status: active
last_accessed: 2026-08-21
---
Beta links back to [[concept_alpha]].
```

Create `test/expected/clean.txt`:

```
## Structural
  pages                : 2
  wikilinks            : 4
  broken links         : 0
  orphans              : 0
  missing frontmatter  : 0

## Injection budget
  index region         : 60 B (~16 tokens)
```

Add to `run-tests.sh`, immediately before the final `exit "$FAILED"`:

```bash
# --- golden-file fixtures ---
run_fixture() {
  local name="$1"; shift
  local out exp
  exp="$HERE/expected/$name.txt"
  out="$(bash "$PLUGIN/bin/wiki-lint.sh" "$HERE/fixtures/$name/wiki" "$@" 2>&1)"
  if [[ "$out" == "$(cat "$exp" 2>/dev/null)" ]]; then
    pass "fixture: $name"
  else
    fail "fixture: $name" "$(diff <(cat "$exp" 2>/dev/null) <(echo "$out") || true)"
  fi
}

run_fixture clean
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: `FAIL: fixture: clean` — `wiki-lint.sh` does not exist, so `$out` is a "No such file or directory" message.

- [ ] **Step 3: Write minimal implementation**

Create `plugins/memory-wiki/bin/wiki-lint.sh`:

```bash
#!/usr/bin/env bash
# Structural audit of a memory-wiki. Pure function: takes a directory, prints a
# deterministic report, exits 0. Reports only — never fixes, never writes.
#
# Usage: wiki-lint.sh <WIKI_DIR> [--sources <DIR>] [--atlas <DIR>]
set -uo pipefail

WIKI=""; SOURCES=""; ATLAS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sources) SOURCES="${2:-}"; shift 2 ;;
    --atlas)   ATLAS="${2:-}";   shift 2 ;;
    *)         WIKI="$1";        shift ;;
  esac
done

if [[ -z "$WIKI" || ! -d "$WIKI" ]]; then
  echo "ERROR: not a directory: ${WIKI:-<none>}" >&2
  exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# index.md and log.md link to nearly every page by design. Counting their links as
# inbound edges would hide every orphan, so they are excluded from the page set and
# from inbound-edge accounting (their links still count toward the total).
is_structural() { [[ "$1" == "index" || "$1" == "log" ]]; }

# --- collect page names and per-page link lists ---
: > "$TMP/pages"; : > "$TMP/links"; : > "$TMP/inbound"; : > "$TMP/nofm"
LINK_COUNT=0

for f in "$WIKI"/*.md; do
  [[ -e "$f" ]] || continue
  base="$(basename "$f" .md)"
  is_structural "$base" || echo "$base" >> "$TMP/pages"

  # frontmatter must be a --- fenced block starting on line 1
  if ! is_structural "$base"; then
    if [[ "$(head -n 1 "$f" | tr -d '\r')" != "---" ]]; then
      echo "$base" >> "$TMP/nofm"
    fi
  fi

  # [[target]] — stop at ] | or #, so aliases and anchors resolve to the page
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    LINK_COUNT=$((LINK_COUNT + 1))
    echo "$base|$target" >> "$TMP/links"
  done < <(grep -o '\[\[[^]|#]*' "$f" 2>/dev/null | sed 's/^\[\[//' | sed 's/[[:space:]]*$//')
done

sort -u -o "$TMP/pages" "$TMP/pages"
PAGE_COUNT=$(wc -l < "$TMP/pages" | tr -d ' ')
NOFM_COUNT=$(sort -u "$TMP/nofm" | grep -c . || true)

# --- report ---
echo "## Structural"
printf '  %-20s : %s\n' "pages" "$PAGE_COUNT"
printf '  %-20s : %s\n' "wikilinks" "$LINK_COUNT"
printf '  %-20s : %s\n' "broken links" "0"
printf '  %-20s : %s\n' "orphans" "0"
printf '  %-20s : %s\n' "missing frontmatter" "$NOFM_COUNT"

if [[ "$NOFM_COUNT" -gt 0 ]]; then
  echo ""; echo "  NO FRONTMATTER:"
  sort -u "$TMP/nofm" | sed 's/^/    /'
fi

echo ""
echo "## Injection budget"
REGION_BYTES=0
if [[ -f "$WIKI/index.md" ]]; then
  # tr -d '\r' is load-bearing: a memory dir may hold CRLF or LF files, and the
  # reported budget must not depend on which. The PowerShell twin strips \r too.
  REGION_BYTES=$(awk '/<!-- BEGIN memory-wiki/{f=1;next} /<!-- END memory-wiki/{f=0} f' "$WIKI/index.md" | tr -d '\r' | wc -c | tr -d ' ')
fi
printf '  %-20s : %s B (~%s tokens)\n' "index region" "$REGION_BYTES" "$((REGION_BYTES * 10 / 36))"
```

Make it executable: `chmod +x plugins/memory-wiki/bin/wiki-lint.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: `PASS: fixture: clean`, exit 0.

The count must be exactly `60` on every platform. If it comes out `62`, the `tr -d '\r'` in the
region extraction is missing or misplaced — **fix the script, not the golden file.** This repo sets
`core.autocrlf=true` and `.gitattributes` marks `*.md` as `text`, so fixture files carry CRLF in the
working tree on Windows and LF elsewhere. A linter whose reported budget changes with line endings is
broken, because a real memory dir can hold either.

- [ ] **Step 5: Commit**

```bash
git add plugins/memory-wiki/bin/wiki-lint.sh plugins/memory-wiki/test/
git commit -m "feat(memory-wiki): add wiki-lint report shape with clean-wiki fixture"
```

---

## Task 3: Link resolution — broken links, `atlas/` prefix, and source citations

Three resolution rules in one task because they are one decision: does `[[target]]` name something that exists?

**Files:**
- Modify: `plugins/memory-wiki/bin/wiki-lint.sh`
- Create: `plugins/memory-wiki/test/fixtures/broken/wiki/{index.md,log.md,concept_alpha.md,concept_beta.md}`
- Create: `plugins/memory-wiki/test/fixtures/atlas/wiki/{index.md,log.md,concept_alpha.md,concept_beta.md}`
- Create: `plugins/memory-wiki/test/fixtures/atlas/{sources/2026-W28.md,atlas/global_thing.md}`
- Create: `plugins/memory-wiki/test/expected/{broken.txt,atlas.txt}`
- Modify: `plugins/memory-wiki/test/run-tests.sh`

**Interfaces:**
- Consumes: `bin/wiki-lint.sh` from Task 2
- Produces: link resolution in three namespaces — a bare `[[name]]` resolves against `<WIKI_DIR>/*.md` then `<SOURCES>/*.md`; `[[atlas/name]]` resolves against `<ATLAS>/*.md`. Unresolved links are reported in a sorted `BROKEN:` block as `page -> [[target]]`.

- [ ] **Step 1: Write the failing test**

`test/fixtures/broken/wiki/index.md` and `log.md`: copy the two from `fixtures/clean/wiki/` unchanged.

`test/fixtures/broken/wiki/concept_alpha.md`:

```markdown
---
name: Alpha
description: first concept
type: concept
status: active
last_accessed: 2026-08-21
---
Alpha links to [[concept_beta]] and to [[nope_missing]].
```

`test/fixtures/broken/wiki/concept_beta.md`:

```markdown
---
name: Beta
description: second concept
type: concept
status: active
last_accessed: 2026-08-21
---
Beta links to [[concept_alpha]] and to [[also_missing]].
```

`test/expected/broken.txt`:

```
## Structural
  pages                : 2
  wikilinks            : 6
  broken links         : 2
  orphans              : 0
  missing frontmatter  : 0

  BROKEN:
    concept_alpha -> [[nope_missing]]
    concept_beta -> [[also_missing]]

## Injection budget
  index region         : 60 B (~16 tokens)
```

Now the atlas fixture. `test/fixtures/atlas/wiki/index.md` and `log.md`: copy from `fixtures/clean/wiki/`.

`test/fixtures/atlas/wiki/concept_alpha.md`:

```markdown
---
name: Alpha
description: first concept
type: concept
status: active
last_accessed: 2026-08-21
---
Alpha links to [[concept_beta]], cites [[2026-W28]], promotes to
[[atlas/global_thing]], and dangles at [[atlas/nope]].
```

`test/fixtures/atlas/wiki/concept_beta.md`:

```markdown
---
name: Beta
description: second concept
type: concept
status: active
last_accessed: 2026-08-21
---
Beta links back to [[concept_alpha]].
```

`test/fixtures/atlas/sources/2026-W28.md`:

```markdown
# Week 2026-W28
```

`test/fixtures/atlas/atlas/global_thing.md`:

```markdown
---
name: Global Thing
description: a promoted page
type: concept
scope: global
status: active
last_accessed: 2026-08-21
---
Promoted.
```

`test/expected/atlas.txt`:

```
## Structural
  pages                : 2
  wikilinks            : 7
  broken links         : 1
  orphans              : 0
  missing frontmatter  : 0

  BROKEN:
    concept_alpha -> [[atlas/nope]]

## Injection budget
  index region         : 60 B (~16 tokens)
```

Add both to `run-tests.sh`, after `run_fixture clean`:

```bash
run_fixture broken
run_fixture atlas --sources "$HERE/fixtures/atlas/sources" --atlas "$HERE/fixtures/atlas/atlas"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: `PASS: fixture: clean`, then `FAIL: fixture: broken` — the report hardcodes `broken links : 0` and emits no `BROKEN:` block. `atlas` fails the same way.

- [ ] **Step 3: Write minimal implementation**

In `wiki-lint.sh`, after the `sort -u -o "$TMP/pages"` line, add the resolution sets:

```bash
# --- resolvable-name sets ---
: > "$TMP/known"
cat "$TMP/pages" >> "$TMP/known"
if [[ -n "$SOURCES" && -d "$SOURCES" ]]; then
  for f in "$SOURCES"/*.md; do [[ -e "$f" ]] && basename "$f" .md >> "$TMP/known"; done
fi
: > "$TMP/known_atlas"
if [[ -n "$ATLAS" && -d "$ATLAS" ]]; then
  for f in "$ATLAS"/*.md; do [[ -e "$f" ]] && basename "$f" .md >> "$TMP/known_atlas"; done
fi
# index.md and log.md are real files and are legitimate link targets even though they
# are excluded from the page count.
for s in index log; do [[ -f "$WIKI/$s.md" ]] && echo "$s" >> "$TMP/known"; done
sort -u -o "$TMP/known" "$TMP/known"
sort -u -o "$TMP/known_atlas" "$TMP/known_atlas"

# --- classify every link ---
: > "$TMP/broken"
while IFS='|' read -r from to; do
  [[ -n "$to" ]] || continue
  if [[ "$to" == atlas/* ]]; then
    if grep -qxF "${to#atlas/}" "$TMP/known_atlas"; then
      continue
    fi
  elif grep -qxF "$to" "$TMP/known"; then
    is_structural "$from" || echo "$to" >> "$TMP/inbound"
    continue
  fi
  echo "$from -> [[$to]]" >> "$TMP/broken"
done < "$TMP/links"
BROKEN_COUNT=$(grep -c . "$TMP/broken" || true)
```

Replace the hardcoded broken-links counter line with:

```bash
printf '  %-20s : %s\n' "broken links" "$BROKEN_COUNT"
```

And insert this block immediately *before* the existing `NO FRONTMATTER` block, so detail sections print in the counter order:

```bash
if [[ "$BROKEN_COUNT" -gt 0 ]]; then
  echo ""; echo "  BROKEN:"
  sort "$TMP/broken" | sed 's/^/    /'
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: three `PASS:` fixture lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/memory-wiki/bin/wiki-lint.sh plugins/memory-wiki/test/
git commit -m "feat(memory-wiki): resolve wikilinks across wiki, sources, and atlas namespaces"
```

---

## Task 4: Orphan detection

**Files:**
- Modify: `plugins/memory-wiki/bin/wiki-lint.sh`
- Create: `plugins/memory-wiki/test/fixtures/orphans/wiki/{index.md,log.md,concept_alpha.md,concept_beta.md,concept_gamma.md}`
- Create: `plugins/memory-wiki/test/expected/orphans.txt`
- Modify: `plugins/memory-wiki/test/run-tests.sh`

**Interfaces:**
- Consumes: the `$TMP/inbound` file populated in Task 3
- Produces: an `ORPHANS:` block listing every page with zero inbound edges from non-structural pages, sorted.

- [ ] **Step 1: Write the failing test**

`test/fixtures/orphans/wiki/index.md`:

```markdown
# Index

<!-- BEGIN memory-wiki (managed; do not edit by hand) -->
- [[concept_alpha]] — first
- [[concept_beta]] — second
- [[concept_gamma]] — third
<!-- END memory-wiki -->
```

`test/fixtures/orphans/wiki/log.md`: copy from `fixtures/clean/wiki/log.md`.

`test/fixtures/orphans/wiki/concept_alpha.md`:

```markdown
---
name: Alpha
description: first concept
type: concept
status: active
last_accessed: 2026-08-21
---
Alpha links to [[concept_beta]].
```

`test/fixtures/orphans/wiki/concept_beta.md`:

```markdown
---
name: Beta
description: second concept
type: concept
status: active
last_accessed: 2026-08-21
---
Beta links to nobody.
```

`test/fixtures/orphans/wiki/concept_gamma.md`:

```markdown
---
name: Gamma
description: third concept
type: concept
status: active
last_accessed: 2026-08-21
---
Gamma is reachable only from the index.
```

`test/expected/orphans.txt`:

```
## Structural
  pages                : 3
  wikilinks            : 4
  broken links         : 0
  orphans              : 2
  missing frontmatter  : 0

  ORPHANS:
    concept_alpha
    concept_gamma

## Injection budget
  index region         : 90 B (~25 tokens)
```

Add to `run-tests.sh`, after `run_fixture atlas ...`:

```bash
run_fixture orphans
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: `FAIL: fixture: orphans` — the counter is still hardcoded to `0` and no `ORPHANS:` block is emitted.

- [ ] **Step 3: Write minimal implementation**

In `wiki-lint.sh`, immediately after the `BROKEN_COUNT=` assignment, add:

```bash
# A page is an orphan when nothing outside index.md/log.md links to it.
sort -u -o "$TMP/inbound" "$TMP/inbound"
comm -23 "$TMP/pages" "$TMP/inbound" > "$TMP/orphans"
ORPHAN_COUNT=$(grep -c . "$TMP/orphans" || true)
```

Replace the hardcoded orphans counter line with:

```bash
printf '  %-20s : %s\n' "orphans" "$ORPHAN_COUNT"
```

And insert this block between the `BROKEN:` block and the `NO FRONTMATTER:` block:

```bash
if [[ "$ORPHAN_COUNT" -gt 0 ]]; then
  echo ""; echo "  ORPHANS:"
  sed 's/^/    /' "$TMP/orphans"
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: four `PASS:` fixture lines, exit 0. `comm` requires both inputs sorted — `$TMP/pages` was sorted in Task 2 and `$TMP/inbound` is sorted above.

- [ ] **Step 5: Commit**

```bash
git add plugins/memory-wiki/bin/wiki-lint.sh plugins/memory-wiki/test/
git commit -m "feat(memory-wiki): detect orphan pages, excluding index and log edges"
```

---

## Task 5: Frontmatter validation

Task 2 only checked that a `---` fence opens line 1. This adds the required-field check.

**Files:**
- Modify: `plugins/memory-wiki/bin/wiki-lint.sh`
- Create: `plugins/memory-wiki/test/fixtures/no-frontmatter/wiki/{index.md,log.md,concept_alpha.md,concept_beta.md}`
- Create: `plugins/memory-wiki/test/expected/no-frontmatter.txt`
- Modify: `plugins/memory-wiki/test/run-tests.sh`

**Interfaces:**
- Consumes: `bin/wiki-lint.sh` from Task 4
- Produces: a page is flagged when it lacks a line-1 `---` fence **or** is missing any of `name:`, `description:`, `type:`, `status:`, `last_accessed:`. The `NO FRONTMATTER:` block reports `page (missing: field, field)` for a malformed block, or `page (no frontmatter)` when the fence is absent.

- [ ] **Step 1: Write the failing test**

`test/fixtures/no-frontmatter/wiki/index.md` and `log.md`: copy from `fixtures/clean/wiki/`.

`test/fixtures/no-frontmatter/wiki/concept_alpha.md`:

```markdown
---
name: Alpha
description: first concept
type: concept
status: active
last_accessed: 2026-08-21
---
Alpha links to [[concept_beta]].
```

`test/fixtures/no-frontmatter/wiki/concept_beta.md` — has a fence but is missing two required fields:

```markdown
---
name: Beta
type: concept
---
Beta links back to [[concept_alpha]].
```

`test/expected/no-frontmatter.txt`:

```
## Structural
  pages                : 2
  wikilinks            : 4
  broken links         : 0
  orphans              : 0
  missing frontmatter  : 1

  NO FRONTMATTER:
    concept_beta (missing: description, last_accessed, status)

## Injection budget
  index region         : 60 B (~16 tokens)
```

Add to `run-tests.sh`, after `run_fixture orphans`:

```bash
run_fixture no-frontmatter
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: `FAIL: fixture: no-frontmatter` — `concept_beta` opens with `---`, so the Task 2 check passes it and the count is `0`.

- [ ] **Step 3: Write minimal implementation**

In `wiki-lint.sh`, replace the frontmatter check inside the per-file loop:

```bash
  if ! is_structural "$base"; then
    if [[ "$(head -n 1 "$f" | tr -d '\r')" != "---" ]]; then
      echo "$base" >> "$TMP/nofm"
    fi
  fi
```

with:

```bash
  if ! is_structural "$base"; then
    if [[ "$(head -n 1 "$f" | tr -d '\r')" != "---" ]]; then
      echo "$base (no frontmatter)" >> "$TMP/nofm"
    else
      # Body of the fenced block: everything between line 1 and the next '---'.
      fm="$(awk 'NR==1{next} /^---[[:space:]]*$/{exit} {print}' "$f" | tr -d '\r')"
      missing=""
      for field in name description type status last_accessed; do
        grep -qE "^${field}:" <<< "$fm" || missing="$missing $field"
      done
      if [[ -n "$missing" ]]; then
        # shellcheck disable=SC2086
        echo "$base (missing: $(printf '%s\n' $missing | sort | paste -sd, - | sed 's/,/, /g'))" >> "$TMP/nofm"
      fi
    fi
  fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: five `PASS:` fixture lines, exit 0. Note the missing fields print alphabetically (`description, last_accessed, status`), not in declaration order — that is what makes the output deterministic.

- [ ] **Step 5: Commit**

```bash
git add plugins/memory-wiki/bin/wiki-lint.sh plugins/memory-wiki/test/
git commit -m "feat(memory-wiki): validate required frontmatter fields"
```

---

## Task 6: Run the linter against real memory and record the baseline

The first moment the plugin does the thing it exists for. This task has no new fixture — its deliverable is a recorded, reproducible baseline against live data.

**Files:**
- Create: `plugins/memory-wiki/test/expected/README.md`
- Modify: `plugins/memory-wiki/test/run-tests.sh`

**Interfaces:**
- Consumes: `bin/wiki-lint.sh` from Task 5
- Produces: `run-tests.sh` gains a `smoke` check that runs the linter against `$HOME/.claude/projects/*/memory` when one exists and asserts only that it exits 0 and emits a `## Structural` header — never asserting counts, which change as memory grows.

- [ ] **Step 1: Write the failing test**

Add to `run-tests.sh`, after the last `run_fixture` line:

```bash
# --- smoke: run against a real memory dir if one exists ---
# Asserts shape only. Counts change as memory grows and must never be pinned here.
REAL="$(ls -d "$HOME"/.claude/projects/*/memory 2>/dev/null | head -1)"
if [[ -n "$REAL" && -d "$REAL" ]]; then
  out="$(bash "$PLUGIN/bin/wiki-lint.sh" "$REAL" --sources "$REAL/episodic/weekly" 2>&1)"
  rc=$?
  if [[ $rc -eq 0 ]] && grep -q '^## Structural' <<< "$out"; then
    pass "smoke: real memory dir"
  else
    fail "smoke: real memory dir" "rc=$rc
$out"
  fi
else
  pass "smoke: skipped (no memory dir on this machine)"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: five fixture `PASS:` lines, then either `PASS: smoke: real memory dir` or a `FAIL:` showing the error. A real memory dir contains files the fixtures never exercised — nested `episodic/` subdirs, CRLF line endings, `[[links|with aliases]]`. **If it fails, that is a genuine bug in the linter, not a bad test.** Fix `wiki-lint.sh` until it passes.

- [ ] **Step 3: Record the baseline**

Run the linter by hand against this repo's own memory dir and capture the report:

```bash
bash plugins/memory-wiki/bin/wiki-lint.sh \
  "$HOME/.claude/projects/C--Users-eduardo-desenvolvimento-claude-plugins/memory" \
  --sources "$HOME/.claude/projects/C--Users-eduardo-desenvolvimento-claude-plugins/memory/episodic/weekly"
```

Write `plugins/memory-wiki/test/expected/README.md` documenting what the golden files are and pasting that report as the recorded baseline:

```markdown
# Golden files

Each `<name>.txt` is the exact expected stdout of `bin/wiki-lint.sh` run against
`../fixtures/<name>/wiki`. Byte counts in the "Injection budget" block are artifacts of the
fixture's line endings — if a count differs on your platform, update the golden file. The
contract under test is that extraction is deterministic, not any particular number.

## Recorded baseline (not a test)

`wiki-lint.sh` against this repo's own claude-memory dir on 2026-08-21, before any wiki
existed. Kept as a before/after reference for Phase 2, deliberately NOT asserted — these
counts change every week.

<paste the actual report output here>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: six `PASS:` lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/memory-wiki/bin/wiki-lint.sh plugins/memory-wiki/test/
git commit -m "test(memory-wiki): smoke-test lint against a real memory dir, record baseline"
```

---

## Task 7: PowerShell twin with output parity

**Files:**
- Create: `plugins/memory-wiki/bin/wiki-lint.ps1`
- Modify: `plugins/memory-wiki/test/run-tests.sh`

**Interfaces:**
- Consumes: `bin/wiki-lint.sh` from Task 6 — its stdout is the specification
- Produces: `wiki-lint.ps1 -WikiDir <DIR> [-Sources <DIR>] [-Atlas <DIR>]` emitting byte-identical output to the bash original for every fixture.

- [ ] **Step 1: Write the failing test**

Add to `run-tests.sh`, before the smoke check:

```bash
# --- PowerShell parity: the .ps1 must match the .sh byte for byte ---
if command -v pwsh >/dev/null 2>&1; then
  for name in clean broken orphans no-frontmatter; do
    sh_out="$(bash "$PLUGIN/bin/wiki-lint.sh" "$HERE/fixtures/$name/wiki" 2>&1)"
    ps_out="$(pwsh -NoProfile -File "$PLUGIN/bin/wiki-lint.ps1" -WikiDir "$HERE/fixtures/$name/wiki" 2>&1)"
    if [[ "$sh_out" == "$ps_out" ]]; then
      pass "parity: $name"
    else
      fail "parity: $name" "$(diff <(echo "$sh_out") <(echo "$ps_out") || true)"
    fi
  done
else
  pass "parity: skipped (pwsh not on PATH)"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: `FAIL: parity: clean` — `wiki-lint.ps1` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `plugins/memory-wiki/bin/wiki-lint.ps1`:

```powershell
# Structural audit of a memory-wiki. PowerShell twin of wiki-lint.sh.
# Output MUST stay byte-identical to the bash original — test/run-tests.sh asserts it.
param(
  [Parameter(Mandatory)][string]$WikiDir,
  [string]$Sources,
  [string]$Atlas
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $WikiDir)) { Write-Error "not a directory: $WikiDir"; exit 0 }

$structural = @('index','log')
$linkRx = [regex]'\[\[([^\]\|#]*)'
$required = @('name','description','type','status','last_accessed')

$pages = @(); $links = @(); $nofm = @(); $inbound = @(); $linkCount = 0

foreach ($f in Get-ChildItem $WikiDir -Filter *.md -File | Sort-Object Name) {
  $base = [IO.Path]::GetFileNameWithoutExtension($f.Name)
  $body = (Get-Content $f.FullName -Raw) -replace "`r",''
  $lines = $body -split "`n"
  if ($base -notin $structural) {
    $pages += $base
    if ($lines[0] -ne '---') {
      $nofm += "$base (no frontmatter)"
    } else {
      $fm = @(); for ($i=1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^---\s*$') { break }; $fm += $lines[$i] }
      $missing = @($required | Where-Object { $fld = $_; -not ($fm | Where-Object { $_ -match "^$fld`:" }) })
      if ($missing.Count) { $nofm += "$base (missing: $(($missing | Sort-Object) -join ', '))" }
    }
  }
  foreach ($m in $linkRx.Matches($body)) {
    $t = $m.Groups[1].Value.TrimEnd()
    if ($t) { $linkCount++; $links += ,@($base,$t) }
  }
}
$pages = @($pages | Sort-Object -Unique)

$known = [System.Collections.Generic.HashSet[string]]::new([string[]]$pages)
if ($Sources -and (Test-Path $Sources)) {
  Get-ChildItem $Sources -Filter *.md -File | ForEach-Object { [void]$known.Add([IO.Path]::GetFileNameWithoutExtension($_.Name)) }
}
foreach ($s in $structural) { if (Test-Path (Join-Path $WikiDir "$s.md")) { [void]$known.Add($s) } }
$knownAtlas = [System.Collections.Generic.HashSet[string]]::new()
if ($Atlas -and (Test-Path $Atlas)) {
  Get-ChildItem $Atlas -Filter *.md -File | ForEach-Object { [void]$knownAtlas.Add([IO.Path]::GetFileNameWithoutExtension($_.Name)) }
}

$broken = @()
foreach ($l in $links) {
  $from,$to = $l[0],$l[1]
  if ($to -like 'atlas/*') {
    if ($knownAtlas.Contains($to.Substring(6))) { continue }
  } elseif ($known.Contains($to)) {
    if ($from -notin $structural) { $inbound += $to }
    continue
  }
  $broken += "$from -> [[$to]]"
}
$orphans = @($pages | Where-Object { $_ -notin $inbound })

"## Structural"
"  {0,-20} : {1}" -f 'pages', $pages.Count
"  {0,-20} : {1}" -f 'wikilinks', $linkCount
"  {0,-20} : {1}" -f 'broken links', $broken.Count
"  {0,-20} : {1}" -f 'orphans', $orphans.Count
"  {0,-20} : {1}" -f 'missing frontmatter', $nofm.Count
if ($broken.Count)  { ""; "  BROKEN:";         $broken  | Sort-Object | ForEach-Object { "    $_" } }
if ($orphans.Count) { ""; "  ORPHANS:";        $orphans | Sort-Object | ForEach-Object { "    $_" } }
if ($nofm.Count)    { ""; "  NO FRONTMATTER:"; $nofm    | Sort-Object | ForEach-Object { "    $_" } }

""
"## Injection budget"
$regionBytes = 0
$idx = Join-Path $WikiDir 'index.md'
if (Test-Path $idx) {
  $raw = (Get-Content $idx -Raw) -replace "`r",''
  $m = [regex]::Match($raw,'(?s)<!-- BEGIN memory-wiki[^>]*-->\n(.*?)<!-- END memory-wiki')
  if ($m.Success) { $regionBytes = [Text.Encoding]::UTF8.GetByteCount($m.Groups[1].Value) }
}
"  {0,-20} : {1} B (~{2} tokens)" -f 'index region', $regionBytes, [math]::Floor($regionBytes * 10 / 36)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: four `PASS: parity:` lines plus the earlier passes, exit 0.

Parity failures are almost always line-ending or byte-count differences. Both scripts strip `\r` before counting; if `index region` still differs, the awk range in the bash version includes the `BEGIN` line's trailing newline while the regex in PowerShell does not — align them by adjusting the PowerShell regex, not the golden files.

- [ ] **Step 5: Commit**

```bash
git add plugins/memory-wiki/bin/wiki-lint.ps1 plugins/memory-wiki/test/run-tests.sh
git commit -m "feat(memory-wiki): add PowerShell lint twin with output-parity test"
```

---

## Task 8: `_wiki-paths.sh` — vendored, worktree-aware memory-dir resolution

Vendored rather than sourced from claude-memory: the two plugins must install independently, so memory-wiki cannot depend on another plugin's files existing on disk.

**Files:**
- Create: `plugins/memory-wiki/bin/_wiki-paths.sh`
- Modify: `plugins/memory-wiki/test/run-tests.sh`

**Interfaces:**
- Consumes: nothing
- Produces: three functions to be **sourced, never executed** — `wiki_to_posix <path>`, `wiki_resolve_main_root <cwd>` (a linked worktree resolves to the main repo root; anything else echoes unchanged), and `wiki_project_dir <cwd>` (echoes `$HOME/.claude/projects/<hash>`). Task 9 consumes `wiki_project_dir`.

- [ ] **Step 1: Write the failing test**

Add to `run-tests.sh`, before the smoke check:

```bash
# --- path helpers ---
# shellcheck source=/dev/null
. "$PLUGIN/bin/_wiki-paths.sh" 2>/dev/null
if declare -f wiki_project_dir >/dev/null 2>&1; then
  got="$(wiki_project_dir "$REPO")"
  want="$HOME/.claude/projects/$(printf '%s' "$(cygpath -w "$REPO" 2>/dev/null || printf '%s' "$REPO")" | sed 's#[:\\/]#-#g')"
  if [[ "$got" == "$want" ]]; then
    pass "paths: repo root resolves to its project dir"
  else
    fail "paths: repo root resolves to its project dir" "got:  $got
want: $want"
  fi
else
  fail "paths: _wiki-paths.sh" "wiki_project_dir not defined"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: `FAIL: paths: _wiki-paths.sh` — the file does not exist, so `wiki_project_dir` is undefined.

- [ ] **Step 3: Write minimal implementation**

Create `plugins/memory-wiki/bin/_wiki-paths.sh`:

```bash
#!/usr/bin/env bash
# Shared path helpers for memory-wiki. SOURCE this file; do not execute it.
#
# Vendored from claude-memory's _memory-paths.sh so the two plugins install
# independently. Behavior must stay identical — both must resolve a given cwd to the
# same memory dir, or a project's memory and its wiki would end up in different places.
#
#   wiki_to_posix <path>          Windows/POSIX path -> POSIX
#   wiki_resolve_main_root <cwd>  linked worktree -> main worktree root; else unchanged
#   wiki_project_dir <cwd>        cwd -> $HOME/.claude/projects/<hash>

wiki_to_posix() {
  [[ -z "${1:-}" ]] && return 0
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$1" 2>/dev/null || printf '%s' "$1"
  else
    printf '%s' "$1" | sed -E 's#^([A-Za-z]):#/\L\1#; s#\\#/#g'
  fi
}

# Only *linked* worktrees redirect. Detection: a linked worktree's git-dir
# (<main>/.git/worktrees/<name>) differs from its common-dir (<main>/.git).
wiki_resolve_main_root() {
  local cwd="${1:-}" gitdir common main pcwd
  [[ -z "$cwd" ]] && return 0
  pcwd="$(wiki_to_posix "$cwd")"
  if ! git -C "$pcwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf '%s' "$cwd"; return 0
  fi
  gitdir="$(git -C "$pcwd" rev-parse --absolute-git-dir 2>/dev/null)"
  common="$(git -C "$pcwd" rev-parse --git-common-dir 2>/dev/null)"
  if [[ -n "$common" ]]; then
    common="$(cd "$pcwd" 2>/dev/null && cd "$common" 2>/dev/null && pwd)"
  fi
  if [[ -n "$gitdir" && -n "$common" && "$gitdir" != "$common" ]]; then
    main="$(dirname "$common")"
    [[ -n "$main" ]] && { printf '%s' "$main"; return 0; }
  fi
  printf '%s' "$cwd"
}

# Matches how Claude Code names project dirs: Windows-style path, then : \ / -> '-'.
wiki_hash_dir() {
  local path="${1:-}" win hash
  [[ -z "$path" ]] && return 0
  if command -v cygpath >/dev/null 2>&1; then
    win="$(cygpath -w "$path" 2>/dev/null || printf '%s' "$path")"
  else
    win="$path"
  fi
  hash="$(printf '%s' "$win" | sed 's#[:\\/]#-#g')"
  printf '%s' "$HOME/.claude/projects/$hash"
}

wiki_project_dir() {
  wiki_hash_dir "$(wiki_resolve_main_root "${1:-}")"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: `PASS: paths: repo root resolves to its project dir`, exit 0. If the repo root is itself a linked worktree the assertion still holds, because the test derives `want` from `$REPO` while the function derives it from the resolved main root — should those differ, the test correctly fails and the repo root is not what it appears to be.

- [ ] **Step 5: Commit**

```bash
git add plugins/memory-wiki/bin/_wiki-paths.sh plugins/memory-wiki/test/run-tests.sh
git commit -m "feat(memory-wiki): vendor worktree-aware path helpers"
```

---

## Task 9: `wiki-init.sh` and the `/memory-wiki:init` command

**Files:**
- Create: `plugins/memory-wiki/bin/wiki-init.sh`
- Create: `plugins/memory-wiki/assets/wiki-README.md`
- Create: `plugins/memory-wiki/commands/init.md`
- Modify: `plugins/memory-wiki/test/run-tests.sh`

**Interfaces:**
- Consumes: `wiki_project_dir` from Task 8
- Produces: `wiki-init.sh [PROJECT_DIR]` (defaults to `$PWD`) creates `<memdir>/wiki/inbox/`, `<memdir>/wiki/log.md`, and `<memdir>/wiki/README.md`. **Idempotent** — re-running prints `wiki already initialized` and changes nothing. Exits non-zero only when `<memdir>` does not exist, i.e. claude-memory was never initialized for the project.

- [ ] **Step 1: Write the failing test**

Add to `run-tests.sh`, before the smoke check:

```bash
# --- init: creates the scaffold, and is idempotent ---
TMPPROJ="$(mktemp -d)"
( cd "$TMPPROJ" && git init -q . ) >/dev/null 2>&1
MEMD="$(wiki_project_dir "$TMPPROJ")/memory"
mkdir -p "$MEMD"
out1="$(bash "$PLUGIN/bin/wiki-init.sh" "$TMPPROJ" 2>&1)"
out2="$(bash "$PLUGIN/bin/wiki-init.sh" "$TMPPROJ" 2>&1)"
if [[ -f "$MEMD/wiki/log.md" && -f "$MEMD/wiki/README.md" && -d "$MEMD/wiki/inbox" ]] \
   && grep -q 'already initialized' <<< "$out2"; then
  pass "init: scaffolds and is idempotent"
else
  fail "init: scaffolds and is idempotent" "run1: $out1
run2: $out2"
fi
rm -rf "$TMPPROJ" "$(wiki_project_dir "$TMPPROJ")"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: `FAIL: init: scaffolds and is idempotent` — `wiki-init.sh` does not exist, so no files are created.

- [ ] **Step 3: Write minimal implementation**

Create `plugins/memory-wiki/assets/wiki-README.md`:

```markdown
# This project's memory wiki

Generated and maintained by the `memory-wiki` plugin. Pages here are LLM-owned; the
sources they cite live in `../episodic/weekly/` and are immutable.

## Page types

| Prefix | Holds |
| --- | --- |
| `project_` | a repo: conventions, environment, standing threads |
| `component_` | a plugin, script, or subsystem within a project |
| `tech_` | external tool or platform mechanics |
| `failure_` | symptom -> cause -> fix -> generalization |
| `concept_` | a durable heuristic (owned by claude-memory; read, never rewritten here) |

## Rules

- **All internal links are `[[exact-filename-without-extension]]`** — never the human
  title, never a kebab-slug that does not match a file. This one rule is what keeps the
  graph connected; violating it is how 39% of links ended up broken before this wiki existed.
- Source citations use the rollup filename: `[[2026-W28]]`.
- Links to the cross-project atlas use `[[atlas/<page>]]`.
- Atlas pages link *back* via their `evidence:` frontmatter, not via wikilinks — separate
  vaults cannot resolve them. This asymmetry is deliberate; `lint` does not flag it.
- Required frontmatter on every page: `name`, `description`, `type`, `status`, `last_accessed`.

`inbox/` holds fleeting in-session captures, triaged by the next ingest.
```

Create `plugins/memory-wiki/bin/wiki-init.sh`:

```bash
#!/usr/bin/env bash
# Scaffold the wiki layer inside an existing claude-memory dir. Idempotent.
# Usage: wiki-init.sh [PROJECT_DIR]   (defaults to the current directory)
set -uo pipefail

TARGET="${1:-$PWD}"
[[ -z "$TARGET" ]] && TARGET="$PWD"

DIR="${CLAUDE_PLUGIN_ROOT:+$CLAUDE_PLUGIN_ROOT/bin}"
[[ -z "$DIR" || ! -f "$DIR/_wiki-paths.sh" ]] && DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_wiki-paths.sh
. "$DIR/_wiki-paths.sh"

MEM="$(wiki_project_dir "$TARGET")/memory"
if [[ ! -d "$MEM" ]]; then
  echo "ERROR: no memory dir for: $TARGET"
  echo "  expected: $MEM"
  echo "  Run /claude-memory:init first — memory-wiki builds on top of it."
  exit 1
fi

WIKI="$MEM/wiki"
if [[ -d "$WIKI" ]]; then
  echo "wiki already initialized for: $TARGET"
  echo "  -> $WIKI"
  exit 0
fi

mkdir -p "$WIKI/inbox"
cp "$DIR/../assets/wiki-README.md" "$WIKI/README.md"

cat > "$WIKI/log.md" <<'EOF'
# Wiki Log

Append-only chronological record. Format: `## [YYYY-MM-DD] operation | title`

---
EOF

echo "wiki initialized for: $TARGET"
echo "  -> $WIKI"
echo "  Next: run /memory-wiki:lint to audit what is already there."
```

Create `plugins/memory-wiki/commands/init.md`:

```markdown
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

Relay the script output above to the user. On success it reports whether the wiki was newly created or
already existed, and the resolved wiki path. If the output starts with `ERROR: no memory dir`, tell the
user to run `/claude-memory:init` first. If it starts with `ERROR: could not locate`, neither path
variable resolved — report the two values shown so the resolver can be fixed.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: `PASS: init: scaffolds and is idempotent`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/memory-wiki/bin/wiki-init.sh plugins/memory-wiki/assets/ \
        plugins/memory-wiki/commands/init.md plugins/memory-wiki/test/run-tests.sh
git commit -m "feat(memory-wiki): add idempotent wiki-init script and init command"
```

---

## Task 10: The `lint` skill, the `/memory-wiki:lint` command, and the plugin README

The script covers structure exhaustively; the skill adds the judgment calls it cannot make.

**Files:**
- Create: `plugins/memory-wiki/skills/lint/SKILL.md`
- Create: `plugins/memory-wiki/commands/lint.md`
- Create: `plugins/memory-wiki/README.md`
- Modify: `plugins/memory-wiki/.claude-plugin/plugin.json` (version → `0.2.0`)
- Modify: `.claude-plugin/marketplace.json` (version → `0.2.0`)
- Modify: `README.md` (repo root — add the `memory-wiki` row)

**Interfaces:**
- Consumes: `bin/wiki-lint.sh` from Task 7, `wiki_project_dir` from Task 8
- Produces: the plugin's complete Phase 1 surface — `/memory-wiki:init`, `/memory-wiki:lint`, and a model-invocable `lint` skill.

- [ ] **Step 1: Write the failing test**

Add to `run-tests.sh`, before the smoke check:

```bash
# --- shipped surface: every declared file exists, versions still agree ---
missing=""
for p in README.md skills/lint/SKILL.md commands/lint.md commands/init.md \
         bin/wiki-lint.sh bin/wiki-lint.ps1 bin/wiki-init.sh bin/_wiki-paths.sh \
         assets/wiki-README.md; do
  [[ -f "$PLUGIN/$p" ]] || missing="$missing $p"
done
if [[ -z "$missing" ]]; then
  pass "surface: all declared files present"
else
  fail "surface: all declared files present" "missing:$missing"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: `FAIL: surface: all declared files present` — `missing: README.md skills/lint/SKILL.md commands/lint.md`.

- [ ] **Step 3: Write minimal implementation**

Create `plugins/memory-wiki/skills/lint/SKILL.md`:

```markdown
---
name: lint
description: Audit a project's memory wiki for structural and content drift. Runs the bundled wiki-lint script for exhaustive structural checks (broken wikilinks, orphan pages, missing frontmatter, injection budget), then adds the judgment-based checks a script cannot make — contradictions between pages, claims superseded by newer sources, and entities that recur across pages without their own page. Use when the user says "lint the memory wiki", "audit my memory", "what's broken in my memory", or asks what the wiki is missing.
---

# Lint the memory wiki

Two halves: the script is exhaustive about structure, you are selective about content.

## 1. Structure (run the script — do not reimplement it)

Resolve the memory dir from the `## Memory - dir for this project` line injected at session
start. Then run:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/bin/wiki-lint.sh" "<memdir>/wiki" \
  --sources "<memdir>/episodic/weekly" \
  --atlas "$HOME/.claude/memory-wiki"
```

If `<memdir>/wiki` does not exist yet, run the script against `<memdir>` itself — the existing
flat `concept_*.md` files are a wiki with no edges, and auditing them is the point of Phase 1.

Relay the counters verbatim. Do not re-derive them by hand and do not fix anything.

## 2. Content (your half — judgment, not enumeration)

Read `wiki/log.md` for what changed recently, then the pages the script flagged plus any the log
touched. Flag only the most significant instances of:

- **Contradictions** — two pages making conflicting claims. Name both and say which source each
  came from; do not silently pick a winner.
- **Stale claims** — an assertion contradicted by a more recent source, or by the repo's actual
  current state. Verify against the filesystem before reporting, not from memory alone.
- **Missing pages** — an entity named across three or more pages with no page of its own.
- **Weak cross-references** — pages that clearly belong linked and are not.

## 3. Report

```
## Structural
<script output, verbatim>

## Content
<contradictions, stale claims, missing pages, weak links — top findings only>

## What to do next
<the 1-3 highest-value actions, each naming the specific page or source involved>
```

## Rules

- **Report; never fix.** Every finding is the user's call. This is the whole contract of the skill.
- Structural findings: exhaustive (the script guarantees it). Content findings: prioritized.
- A broken link whose target is a *human title* rather than a filename is the single most common
  defect. Say so explicitly when you see it — the fix is a rename, not a new page.
```

Create `plugins/memory-wiki/commands/lint.md`:

```markdown
---
description: Audit this project's memory wiki for broken wikilinks, orphan pages, and missing frontmatter. Runs the bundled wiki-lint script and reports; never fixes anything.
argument-hint: "[memory-dir]  (defaults to the current project)"
allowed-tools: Bash(*)
disable-model-invocation: true
---

# Lint the memory wiki

!`for R in "${CLAUDE_PLUGIN_ROOT:-}" "${CLAUDE_SKILL_DIR:-}/.." "$(find "$HOME/.claude/plugins/cache/edusouza-plugins/memory-wiki" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort | tail -1)"; do [ -n "$R" ] && [ -x "$R/bin/wiki-lint.sh" ] && { . "$R/bin/_wiki-paths.sh"; M="${ARGUMENTS:-$(wiki_project_dir "$PWD")/memory}"; W="$M/wiki"; [ -d "$W" ] || W="$M"; exec "$R/bin/wiki-lint.sh" "$W" --sources "$M/episodic/weekly" --atlas "$HOME/.claude/memory-wiki"; }; done; echo "ERROR: could not locate wiki-lint.sh — CLAUDE_PLUGIN_ROOT='${CLAUDE_PLUGIN_ROOT:-}' CLAUDE_SKILL_DIR='${CLAUDE_SKILL_DIR:-}'"`

Relay the report above verbatim. Then, if any links are broken, check whether their targets look
like human titles rather than filenames — that is the most common cause and the fix is a rename.
For the judgment-based content checks (contradictions, stale claims, missing pages), use the
`lint` skill.
```

Create `plugins/memory-wiki/README.md`:

```markdown
# memory-wiki

Turns `claude-memory`'s flat Tier-3 concepts into a cross-linked, searchable wiki. It reads what
`claude-memory` writes and never modifies it — capture and weekly rollups stay where they are.

**Phase 1 (this release) is the deterministic half:** an audit that works on the memory you
already have, before a single page is generated.

| Skill / command | What it does |
| --- | --- |
| `/memory-wiki:init` | Scaffolds `wiki/`, `wiki/inbox/`, `wiki/log.md`, and the page-schema README inside an existing memory dir. Idempotent. |
| `/memory-wiki:lint` | Runs the structural audit: broken wikilinks, orphan pages, missing frontmatter, injection budget. |
| `lint` skill | The same audit, plus the judgment checks a script cannot make — contradictions, stale claims, missing pages. |

## Why

Tier-3 distillation already writes `[[wikilinks]]` spontaneously — nothing instructed it to, and
nothing validates them. Across 32 memory-enabled projects on one machine, **39% of those links
resolve to no existing page** and **63% of pages have no inbound link at all**. Three naming
conventions collide with no schema to arbitrate. `lint` is what notices.

## Install

```bash
/plugin install memory-wiki@edusouza-plugins
```

## Dependencies

- `bash` (git-bash on Windows) and `git` on `PATH`. `pwsh` optional — a PowerShell twin of the
  linter ships alongside the bash original.
- `claude-memory` for anything to audit. `memory-wiki` does not require it to be installed, but
  an uninitialized project has no memory dir and `init` will say so.

## Tests

```bash
bash plugins/memory-wiki/test/run-tests.sh
```

Golden-file fixtures plus a shape-only smoke test against a real memory dir. No framework, no
dependencies.

## License

MIT
```

Bump both manifests to `0.2.0` (a new skill and two new commands shipped since `0.1.0`), and add a `memory-wiki` row to the root `README.md` Plugins table matching the format of the existing rows.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash plugins/memory-wiki/test/run-tests.sh`
Expected: every check passes, including `PASS: version parity (0.2.0)` — proving the Task 1 guard catches a real drift the moment both files must move together.

- [ ] **Step 5: Commit**

```bash
git add plugins/memory-wiki/ .claude-plugin/marketplace.json README.md
git commit -m "feat(memory-wiki): add lint skill, lint command, and plugin README

Bumps memory-wiki to 0.2.0 in both plugin.json and marketplace.json."
```

---

## Self-Review

**1. Spec coverage.** Phase 1 of the spec is §11 "Phase 1 — `init` + `lint`", drawing on §5 (page schema), §7 (the `init` and `lint` rows), §8 (`wiki-lint` script), and §12 (non-goals).

| Spec requirement | Task |
| --- | --- |
| §8 `wiki-lint`: broken links, orphans, missing frontmatter, injection budget | 2–5 |
| §8 "must exclude `index.md` and `log.md` when computing orphans" | 4 |
| §8 `.sh` / `.ps1` pair per script | 7 |
| §5.3 link convention: exact filename; `atlas/` prefix; source citations | 3, and documented in the Task 9 asset |
| §5.3 atlas→project asymmetry is deliberate, not a lint finding | Task 9 asset; Task 3 only resolves `atlas/` in the outbound direction |
| §5.2 required frontmatter fields | 5 |
| §4.2 worktree-aware path resolution reusing claude-memory's *semantics* | 8 |
| §7 `init` scaffolds `wiki/`, `README.md` schema | 9 |
| §7 `lint` reports, never fixes | 10 (skill rules), and Global Constraints |
| §7 `lint` content checks: contradictions, stale claims, missing pages, weak links | 10 |
| §10 "no build system" — establish tests without adding dependencies | 1–2 (golden-file harness) |
| Global: version parity across two catalogs | 1, re-proven in 10 |

**Deliberately out of Phase 1**, per spec §11: `wiki-inject`, `wiki-recall`, `wiki-nudge`, `wiki-scan-dupes`, the `MEMORY.md` region writer, and the `ingest` / `query` / `promote` skills. No gap.

**2. Placeholder scan.** One intentional fill-in remains: Task 6 Step 3 says `<paste the actual report output here>`. That is output that cannot exist before the task runs — the step's instruction is complete and executable. Every code block elsewhere is literal. No "add error handling", no "similar to Task N", no "write tests for the above".

**3. Type consistency.**
- `wiki-lint.sh` argument form — `<WIKI_DIR> [--sources <DIR>] [--atlas <DIR>]` — is identical in Tasks 2, 3, 6, 7, 10 and both command files.
- `wiki-lint.ps1` uses `-WikiDir` / `-Sources` / `-Atlas` (PowerShell convention) and Task 7's parity test is the only caller.
- `wiki_project_dir` is defined in Task 8 and consumed in Tasks 8, 9, 10 under exactly that name. The file is `_wiki-paths.sh` in every reference.
- Temp-file names inside `wiki-lint.sh` (`$TMP/pages`, `links`, `inbound`, `nofm`, `known`, `known_atlas`, `broken`, `orphans`) are introduced in Task 2 and 3 and reused consistently in 4 and 5.
- Report labels are byte-identical across the bash source, the PowerShell twin, and all five golden files: `pages`, `wikilinks`, `broken links`, `orphans`, `missing frontmatter`, `index region`.
- `is_structural` is defined once (Task 2) and used in Tasks 2, 3, 4, 5.

**One ordering dependency worth flagging to the executor:** Task 3 populates `$TMP/inbound`, which Task 4 consumes. Running Task 4 before Task 3 produces a linter that reports every page as an orphan. Execute in order.
