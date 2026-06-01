# Design Sources

`design-to-ui` accepts three kinds of design input. Identify which one you have, extract its structure,
then continue with the framework-agnostic atomic decomposition. Whatever the source, you need: the
**component hierarchy/layout**, **styling** (colors, spacing, typography), **text content**, and
**icons/image assets**.

---

## A. Google Stitch (MCP)

The input is a URL containing `stitch.withgoogle.com`.

### URL format & parsing
```
https://stitch.withgoogle.com/project/<project_id>/screen/<screen_id>
```
```ts
function parseStitchUrl(url: string) {
  const m = url.match(/stitch\.withgoogle\.com\/project\/(\d+)\/screen\/([a-zA-Z0-9]+)/);
  return m ? { projectId: m[1], screenId: m[2] } : null;
}
```

### MCP tools
| Tool | Purpose | Key params |
|------|---------|-----------|
| `mcp__stitch__list_projects` | List projects | `filter?` (`view=owned` / `view=shared`) |
| `mcp__stitch__get_project` | Project details | `name` = `projects/{id}` |
| `mcp__stitch__list_screens` | Screens in a project | `projectId` = `projects/{id}` |
| `mcp__stitch__get_screen` | **Primary** — full screen design data | `projectId` (number), `screenId` |
| `mcp__stitch__generate_screen_from_text` | Generate a new screen | `projectId`, `prompt`, `deviceType?`, `modelId?` |

Primary path:
```
mcp__stitch__get_screen({ projectId: "123456", screenId: "abc123" })
```
Returns the component hierarchy, layout (flex/grid/positioning), styling, text, image references, and
interactive states.

**Errors:** if `get_screen` fails with a connection error the generation may still be processing — wait and
retry `get_screen`; do **not** retry `generate_screen_from_text`. For invalid IDs, re-check URL parsing and
access. For large designs, work top-level structure first, then section by section.

---

## B. Claude Design (handoff bundle / HTML export)

Claude Design (Anthropic's visual tool at **claude.ai/design**) is conversational and web-based. It has
**no public API or MCP** — so you never "call" it. Instead it produces artifacts you consume as files:

- **Handoff bundle for Claude Code** — "When a design is ready to build, Claude packages everything into a
  handoff bundle that you can pass to Claude Code with a single instruction." Treat the bundle as the
  spec: read its files for layout, design tokens, copy, and assets.
- **Standalone HTML export** — Claude Design can export to a standalone HTML file (also PDF/PPTX/Canva).
  Parse the HTML/CSS to recover structure, colors, spacing, typography, and assets. The DOM tree maps
  directly onto the atomic hierarchy; inline styles / CSS variables give you the design tokens.

How to use it:
1. Ask the user to point you at the handoff bundle directory or the exported HTML file (or paste it).
2. Read the files. From HTML, derive the component tree from the DOM; from a bundle, read its manifest/
   token files plus any assets.
3. Extract design tokens (CSS custom properties, a tokens file) and prefer mapping them onto the target
   project's existing theme tokens rather than hardcoding hex values.

---

## C. Image / screenshot

A pasted image or an image file of a mockup. Read it visually and infer:
- the layout regions and component hierarchy,
- approximate spacing and alignment,
- colors (sample dominant/accent colors) and typography (relative sizes/weights),
- icons and imagery.

This is the lowest-fidelity source — confirm ambiguous spacing/colors with the user or the project's
existing design tokens rather than guessing exact pixel values.

---

## Design-data interpretation (all sources)

Once you have raw layout/style data (Stitch JSON, exported CSS, or visual estimates), map it to the
project's styling system. Examples below use Tailwind; translate to CSS Modules / styled-components / etc.
as detected.

### Layout
| Design property | Tailwind |
|-----------------|----------|
| `flexDirection: column` | `flex flex-col` |
| `flexDirection: row` | `flex flex-row` |
| `justifyContent: center` | `justify-center` |
| `alignItems: center` | `items-center` |
| `gap: 16` | `gap-4` |
| `padding.top: 16` | `pt-4` |

### Color
Prefer the project's theme tokens. Map raw values onto the nearest token; only fall back to literal classes
(`bg-white`, `bg-black`, `bg-[#1f8cf9]`) when no token matches. Encode opacity as `/90`, `/80`, etc.

### Typography
| Property | Tailwind |
|----------|----------|
| `fontSize: 14` | `text-sm` |
| `fontSize: 16` | `text-base` |
| `fontSize: 18` | `text-lg` |
| `fontWeight: 500` | `font-medium` |
| `fontWeight: 600` | `font-semibold` |
| `fontWeight: 700` | `font-bold` |

### Spacing scale (px → Tailwind)
| px | scale | px | scale |
|----|-------|----|-------|
| 4 | `1` | 24 | `6` |
| 8 | `2` | 32 | `8` |
| 12 | `3` | 40 | `10` |
| 16 | `4` | 48 | `12` |
| 20 | `5` | | |
