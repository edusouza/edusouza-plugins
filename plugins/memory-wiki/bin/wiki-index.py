#!/usr/bin/env python3
"""Render (and, once Task 3 lands, write) the memory-wiki index region.

This is the one memory-wiki script with no PowerShell twin, and that is
deliberate (call it D-c). Every other script in this plugin is read-only or
writes exclusively inside wiki/**, so a bash/PowerShell divergence between the
twins is at worst a report that looks different on two platforms. This script
is different: its write half (Task 3) rewrites a marker-delimited region
inside MEMORY.md — a file claude-memory also writes, outside those markers.
A marker-delimited rewrite of a file another plugin owns is already a single
sharp edge; maintaining two independently-written implementations of that
rewrite (bash+awk on one side, PowerShell on the other) would be two chances
to drift out of sync and corrupt the other plugin's content instead of one.
Python is the one language every memory-wiki install can already depend on
as of 0.4.0, so it gets the only implementation.

Task 2 (this task) implements only the render half: a pure function from a
directory of pages to the region body, printed to stdout. It writes nothing.
Task 3 adds the write half. Until then, main() refuses anything other than
--render-only.

Usage:
    python wiki-index.py --wiki <WIKI_DIR> --render-only
"""

import os
import sys

# The pair Phase 1's linter (wiki-lint.sh) already measures the injection
# budget between. Task 3 locates these same two lines in wiki/index.md and
# MEMORY.md to know what to replace.
BEGIN = "<!-- BEGIN memory-wiki (managed; do not edit by hand) -->"
END = "<!-- END memory-wiki -->"

# Machinery, not pages: never rendered, never counted.
_SKIP = ("index", "log", "README")


def parse_frontmatter(text):
    """Parse a flat `key: value` frontmatter block fenced by `---` on line 1.

    Only top-level (non-indented) keys are read. An indented key — such as the
    global auto-memory's nested `metadata:` block — is skipped rather than
    matched, so a nested key can never masquerade as a top-level `type:` or
    `status:`. This mirrors wiki-lint.sh's fm_value, which reads with the same
    `^key:` anchoring.
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    fm = {}
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if not line.strip():
            continue
        if line[:1] in (" ", "\t"):
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ("\"", "'"):
            value = value[1:-1]
        fm[key] = value
    return fm


def _strip_link(item):
    """Strip one pair of surrounding quotes, then one pair of wikilink brackets."""
    item = item.strip()
    if len(item) >= 2 and item[0] == item[-1] and item[0] in ("\"", "'"):
        item = item[1:-1]
    if item.startswith("[[") and item.endswith("]]"):
        item = item[2:-2]
    return item


def parse_list(value):
    """Parse a frontmatter value that names one or more wiki/source pages.

    Accepts a YAML flow list (`["[[2026-W35]]", "[[other]]"]`), a bare
    wikilink (`[[name]]`), or a bare scalar, and returns plain names with
    quotes and wikilink brackets stripped. A flow list is distinguished from a
    bare wikilink by its second character: `["..."` opens a list of quoted
    items, while `[[...` is a bracket pair with nothing between them and the
    next `[`.
    """
    value = value.strip()
    if not value:
        return []
    if value.startswith("[") and not value.startswith("[["):
        inner = value[1:-1] if value.endswith("]") else value[1:]
        return [_strip_link(item) for item in inner.split(",") if item.strip()]
    return [_strip_link(value)]


def read_pages(wiki_dir):
    """Read every page in wiki_dir into a flat frontmatter dict plus `_base`.

    Directory listing is sorted with Python's default code-point ordering —
    the same byte ordering `LC_ALL=C` gives the bash side — so callers that
    rely on filename order (the Map section) get it for free.
    """
    pages = []
    for name in sorted(os.listdir(wiki_dir)):
        if not name.endswith(".md"):
            continue
        base = name[:-3]
        if base in _SKIP:
            continue
        with open(os.path.join(wiki_dir, name), "rb") as f:
            text = f.read().decode("utf-8")
        fm = parse_frontmatter(text)
        fm["_base"] = base
        pages.append(fm)
    return pages


def active(pages):
    """Pages with no status are active, matching how wiki-lint.sh reads them.

    Dormant and superseded pages are excluded from every section; any other
    (including invalid) status is a lint concern, not a filter concern here.
    """
    return [p for p in pages if p.get("status") not in ("dormant", "superseded")]


def render(pages, link):
    """Render the index region body from an already-active page list.

    `link` maps a base filename to its rendered link form, e.g.
    ``lambda base: f"[[{base}]]"`` — used for both wiki pages and the
    Sources-ingested episodic references, since both render the same way.
    """
    symptoms = sorted(
        (p["symptom"], p["_base"]) for p in pages if p.get("symptom")
    )

    # Filename order, not sorted again here: `pages` already carries the
    # code-point order read_pages produced, and re-sorting would be a second
    # place this could silently diverge from it.
    mapped = [
        (p["_base"], p.get("description", ""))
        for p in pages
        if p.get("type") in ("project", "component", "tech")
    ]

    sources = set()
    for p in pages:
        sources.update(parse_list(p.get("sources", "")))

    sections = []

    if symptoms:
        lines = ["## Symptoms — match the literal text, then read the page"]
        lines += [f"- `{symptom}` → {link(base)}" for symptom, base in symptoms]
        sections.append("\n".join(lines))

    if mapped:
        lines = ["## Map"]
        lines += [f"- {link(base)} — {desc}" for base, desc in mapped]
        sections.append("\n".join(lines))

    if sources:
        lines = ["## Sources ingested", ", ".join(link(s) for s in sorted(sources))]
        sections.append("\n".join(lines))

    if not sections:
        return "(no pages yet — run /memory-wiki:ingest)\n"

    return "\n\n".join(sections) + "\n"


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    wiki_dir = None
    render_only = False
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--wiki" and i + 1 < len(argv):
            i += 1
            wiki_dir = argv[i]
        elif arg == "--render-only":
            render_only = True
        i += 1

    # The write half (rewriting wiki/index.md and MEMORY.md in place) is
    # Task 3. Anything that isn't a render request is refused rather than
    # silently doing nothing, so a caller who forgets the flag finds out now.
    if not render_only:
        print("ERROR: writing is not implemented yet", file=sys.stderr)
        return 1

    if not wiki_dir or not os.path.isdir(wiki_dir):
        print(f"ERROR: not a directory: {wiki_dir or '<none>'}", file=sys.stderr)
        return 1

    body = render(active(read_pages(wiki_dir)), lambda base: f"[[{base}]]")

    # Bytes, not print(): the region contains → and —, and a Windows
    # console's default cp1252 encoding raises on both under print().
    sys.stdout.buffer.write(body.encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
