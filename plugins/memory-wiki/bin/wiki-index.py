#!/usr/bin/env python3
"""Render and write the memory-wiki index region.

This is the one memory-wiki script with no PowerShell twin, and that is
deliberate (call it D-c). Every other script in this plugin is read-only or
writes exclusively inside wiki/**, so a bash/PowerShell divergence between the
twins is at worst a report that looks different on two platforms. This script
is different: its write half rewrites a marker-delimited region inside
MEMORY.md — a file claude-memory also writes, outside those markers.
A marker-delimited rewrite of a file another plugin owns is already a single
sharp edge; maintaining two independently-written implementations of that
rewrite (bash+awk on one side, PowerShell on the other) would be two chances
to drift out of sync and corrupt the other plugin's content instead of one.
Python is the one language every memory-wiki install can already depend on
as of 0.4.0, so it gets the only implementation.

The render half is a pure function from a directory of pages to the region
body; `--render-only` prints it and writes nothing. The write half splices that
body into wiki/index.md, and a two-line pointer into MEMORY.md, without
disturbing a byte outside the markers. `--list-pages` prints one
`name | type | description` line per page for wiki-ingest-plan.sh, so the work
order reads pages with this same parser rather than a second one.

Usage:
    python wiki-index.py --wiki <WIKI_DIR> [--memory-md <PATH>]
    python wiki-index.py --wiki <WIKI_DIR> --render-only
    python wiki-index.py --wiki <WIKI_DIR> --list-pages
"""

import os
import stat
import sys
import tempfile

# The pair Phase 1's linter (wiki-lint.sh) already measures the injection
# budget between. write_region locates these same two lines in wiki/index.md
# and MEMORY.md to know what to replace.
BEGIN = "<!-- BEGIN memory-wiki (managed; do not edit by hand) -->"
END = "<!-- END memory-wiki -->"

# The region body for a wiki with no pages. wiki-init.sh seeds a brand-new
# wiki/index.md with this exact string between the markers, and run-tests.sh
# pins the two together: if they ever drift, the first ingest in every new
# project shows a phantom diff on a file nobody edited.
EMPTY = "(no pages yet — run /memory-wiki:ingest)\n"

# What wiki-init.sh puts above the managed region, and what write_region puts there
# when it has to create index.md itself — in a wiki scaffolded before index.md was
# seeded, or one that never ran init. The two shapes have to match, because this is
# a one-shot decision: the replace path never adds a heading afterwards, so an
# index.md created without one keeps a bare marker block forever while every newly
# scaffolded wiki gets a heading.
INDEX_HEADING = "# Wiki index"

# Machinery, not pages: never rendered, never counted.
_SKIP = ("index", "log", "README")


def _unquote(value):
    """Strip one pair of matching surrounding quotes, if there is one."""
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("\"", "'"):
        return value[1:-1]
    return value


def parse_frontmatter(text):
    """Parse a flat `key: value` frontmatter block fenced by `---` on line 1.

    Only top-level (non-indented) keys are read. An indented key — such as the
    global auto-memory's nested `metadata:` block — is skipped rather than
    matched, so a nested key can never masquerade as a top-level `type:` or
    `status:`. This mirrors wiki-lint.sh's frontmatter pass, which reads with the
    same top-level anchoring.
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    fm = {}
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if line[:1] in (" ", "\t"):
            continue
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        fm[key.strip()] = _unquote(value.strip())
    return fm


def _strip_link(item):
    """Strip one pair of surrounding quotes, then one pair of wikilink brackets."""
    item = _unquote(item.strip())
    if item.startswith("[[") and item.endswith("]]"):
        item = item[2:-2]
    return item


def parse_list(value):
    """Parse a frontmatter value that names one or more wiki/source pages.

    Accepts a YAML flow list (`["[[2026-W35]]", "[[other]]"]`), a bare comma
    list of wikilinks (`[[2026-W35]], [[other]]`), a single wikilink
    (`[[name]]`), or a bare scalar, and returns plain names with quotes and
    wikilink brackets stripped. A flow list is distinguished from a bare
    wikilink by its second character: `["..."` opens a list of quoted items,
    while `[[...` is a bracket pair with nothing between them and the next `[`.

    The bracketless comma form is here because the field is written by a model
    reading a format full of `[[...]]`, and it will sometimes hand them back
    without the flow brackets — wiki-log.sh's render_list already extends the
    same courtesy for the same reason. Splitting on the comma matters beyond
    tidiness: wiki-lint.sh scans the identical line with `\\[\\[[^]|#]*` and sees
    two perfectly resolvable links, so without this the linter would report
    clean while the index carried one garbage name ("a]], [[b") rendered as a
    broken link. Two parsers of one field must not disagree.

    Splitting on every comma, like render_list, is the deliberate limit: a page
    name containing a comma is not a filename this plugin ever writes, and
    matching the writer is worth more than covering a name that cannot occur.
    """
    value = value.strip()
    if not value:
        return []
    if value.startswith("[") and not value.startswith("[["):
        value = value[1:-1] if value.endswith("]") else value[1:]
    return [_strip_link(item) for item in value.split(",") if item.strip()]


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


def render(pages):
    """Render the index region body from an already-active page list."""
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
        lines += [f"- `{symptom}` → [[{base}]]" for symptom, base in symptoms]
        sections.append("\n".join(lines))

    if mapped:
        lines = ["## Map"]
        lines += [f"- [[{base}]] — {desc}" for base, desc in mapped]
        sections.append("\n".join(lines))

    if sources:
        lines = ["## Sources ingested", ", ".join(f"[[{s}]]" for s in sorted(sources))]
        sections.append("\n".join(lines))

    if not sections:
        return EMPTY

    return "\n\n".join(sections) + "\n"


def render_stub(pages):
    """Render MEMORY.md's two-line pointer at the wiki. `pages` is the active list.

    A pointer, never a copy of the index (D-a). MEMORY.md is auto-loaded into
    context by the harness while wiki/index.md is read on demand, so emitting
    the same region into both files would spend the injection budget twice on
    one set of facts — and nothing here can detect that it happened, because the
    hook cannot tell whether the harness already loaded MEMORY.md. MEMORY.md
    therefore gets only the count and the path; the index itself lives in one
    place.
    """
    n = len(pages)
    return (
        f"Memory wiki: {n} active page{'' if n == 1 else 's'}.\n"
        "Full index (symptoms, map, sources ingested): `wiki/index.md`"
        " in this memory dir.\n"
    )


def _line_ending(text):
    """The newline convention this file's managed block must be written with.

    A file holding even one CRLF is treated as a CRLF file: MEMORY.md is CRLF on
    Windows, and splicing an LF block into it leaves mixed endings that the next
    tool to touch the file normalizes into a whole-file diff belonging to nobody.
    A new or empty file gets LF, like everything else this plugin generates.
    """
    return "\r\n" if "\r\n" in text else "\n"


def _atomic_write(path, text):
    """Write `text` over `path` via a temp file in the same directory + os.replace.

    Same directory so the replace is a rename within one filesystem, which is
    what makes it atomic: a concurrent reader of MEMORY.md sees either the whole
    old file or the whole new one, never a truncated one. Binary mode is
    required rather than stylistic — text mode on Windows would translate every
    "\\n" this module carefully placed into "\\r\\n".
    """
    fd, tmp = tempfile.mkstemp(
        dir=os.path.dirname(path), prefix=".wiki-index-", suffix=".tmp"
    )
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(text.encode("utf-8"))
        # mkstemp creates 0600. Carry the original's mode across so replacing a
        # file shared with another tool does not quietly tighten its permissions.
        try:
            os.chmod(tmp, stat.S_IMODE(os.stat(path).st_mode))
        except OSError:
            pass
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def write_region(path, body):
    """Replace this plugin's managed region in `path`, appending it if absent.

    Returns what happened: "created", "replaced", "appended" or "unchanged".

    Everything outside the two marker lines is carried across as the exact bytes
    that were read — the region is spliced out and back in by line index, never
    reformatted or re-terminated — because MEMORY.md also holds claude-memory's
    region and the user's own entries, and a whole-file rewrite of a shared file
    is a diff belonging to nobody.

    Markers are matched on the stripped line, and the pair used is the last
    BEGIN before the first END that follows it. That matters for a file someone
    left a dangling BEGIN in: the naive "first BEGIN, first END" would span the
    leftover and delete everything under it on the next run. If there is no such
    pair at all the block is appended — the region is never read as "BEGIN to end
    of file", which would delete everything below a stray marker.

    One filename-specific rule: an `index.md` written from nothing also gets
    INDEX_HEADING, so a generated index and a wiki-init.sh-scaffolded one are the
    same file. See that constant for why it cannot be left to the caller.
    """
    path = os.path.abspath(path)
    os.makedirs(os.path.dirname(path), exist_ok=True)

    try:
        with open(path, "rb") as f:
            original = f.read().decode("utf-8")
    except FileNotFoundError:
        original = None
    text = "" if original is None else original

    # The block, in the file's own newline convention.
    nl = _line_ending(text)
    inner = body.replace("\r\n", "\n").strip("\n")
    block = "".join(
        line + nl for line in [BEGIN] + (inner.split("\n") if inner else []) + [END]
    )

    file_lines = text.splitlines(keepends=True)
    begin_i = end_i = -1
    for i, line in enumerate(file_lines):
        stripped = line.strip()
        if stripped == BEGIN:
            # A second BEGIN before any END means the earlier one was left
            # dangling by something else. Move to the later, well-formed pair
            # instead of spanning the leftover — that text is not ours to delete.
            begin_i = i
        elif begin_i >= 0 and stripped == END:
            end_i = i
            break

    if end_i >= 0:
        updated = (
            "".join(file_lines[:begin_i]) + block + "".join(file_lines[end_i + 1:])
        )
        action = "replaced"
    else:
        # Append path: separate the block from the existing content by exactly one
        # blank line, adding only the newlines that are missing. Trailing blank
        # lines already there are content outside the markers and are never
        # trimmed. Four cases, and the CRLF/LF question is settled first so only
        # the count of trailing newlines matters here:
        #   ""        nothing to separate from      -> add nothing
        #   "...\n"   terminated, no blank line yet -> add one newline
        #   "...\n\n" already a blank line          -> add nothing
        #   "..."     unterminated last line        -> terminate it, then blank
        # Every one of them converges on the next run: the markers now exist, the
        # replace path fires, and the whole prefix is carried across verbatim.
        tail = text.replace("\r\n", "\n")
        if not tail or tail.endswith("\n\n"):
            sep = ""
        elif tail.endswith("\n"):
            sep = nl
        else:
            sep = nl + nl
        # An index.md written from nothing gets the heading wiki-init.sh seeds, so a
        # generated one and a scaffolded one are byte-identical. Only when there is no
        # existing content: a file that already has something above the markers keeps
        # whatever its owner put there, and MEMORY.md never gets a heading from us.
        head = ""
        if not text and os.path.basename(path) == "index.md":
            head = INDEX_HEADING + nl + nl
        updated = text + sep + head + block
        action = "created" if original is None else "appended"

    # Not rewriting a shared file we are not changing is the cheapest possible
    # guarantee of idempotence, and it leaves the file's mtime alone for whatever
    # else watches it.
    if updated == original:
        return "unchanged"

    _atomic_write(path, updated)
    return action


def _emit(text):
    """Write to stdout as UTF-8 bytes.

    Not print(): this module's output carries → and — and absolute paths, and a
    Windows console's default cp1252 encoding raises on the first two.
    """
    sys.stdout.buffer.write(text.encode("utf-8"))


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    wiki_dir = None
    memory_md = None
    render_only = False
    list_pages = False
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--wiki" and i + 1 < len(argv):
            i += 1
            wiki_dir = argv[i]
        elif arg == "--memory-md":
            # Loud, not silent: this is the flag that writes into the shared file, so a
            # caller who passes it without a path has to learn that the pointer was
            # never written rather than get a clean exit 0 and no stub.
            if i + 1 >= len(argv):
                print("ERROR: --memory-md needs a path", file=sys.stderr)
                return 1
            i += 1
            memory_md = argv[i]
        elif arg == "--render-only":
            render_only = True
        elif arg == "--list-pages":
            list_pages = True
        i += 1

    if not wiki_dir or not os.path.isdir(wiki_dir):
        print(f"ERROR: not a directory: {wiki_dir or '<none>'}", file=sys.stderr)
        return 1

    if list_pages:
        # Every page, dormant and superseded included: this is the ingest work order's
        # view of what already exists, and a page the index does not render must still
        # not be written a second time.
        _emit("".join(
            f"{p['_base']} | {p.get('type', '')} | {p.get('description', '')}\n"
            for p in read_pages(wiki_dir)
        ))
        return 0

    pages = active(read_pages(wiki_dir))
    body = render(pages)

    if render_only:
        _emit(body)
        return 0

    targets = [(os.path.join(wiki_dir, "index.md"), body)]
    if memory_md:
        targets.append((memory_md, render_stub(pages)))

    for target, region in targets:
        try:
            action = write_region(target, region)
        except (OSError, UnicodeDecodeError) as exc:
            # A shared file we cannot read or replace is reported and left alone,
            # rather than half-written or buried under a traceback.
            print(f"ERROR: cannot write {target}: {exc}", file=sys.stderr)
            return 1
        # Absolute paths, so these lines are never golden-tested; the write path
        # is asserted by file content instead.
        _emit(f"{action}: {os.path.abspath(target)}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
