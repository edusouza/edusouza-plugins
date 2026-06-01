---
name: design-to-ui
description: >
  Turn a design into UI components using atomic design. The design SOURCE is pluggable — a Google Stitch
  URL, a Claude Design handoff bundle / exported HTML, or an image/screenshot mockup — and the TARGET
  FRAMEWORK is detected from the project (React, Vue, Svelte, Angular, Solid, …), never assumed. Decomposes
  the design into atoms → molecules → organisms → templates → pages, reuses existing components, generates
  the missing ones in the project's framework and styling system, then verifies against the source.
  Use when the user provides a Stitch URL (`stitch.withgoogle.com`), a Claude Design export/handoff, or a
  screenshot; or asks to "implement a design", "convert design to code", "build this screen", or mentions
  "design", "mockup", or "pixel-perfect".
---

# design-to-ui

Convert a design into framework-native UI components following **atomic design**. Two things are
pluggable: **where the design comes from** (step 1) and **what framework you generate** (step 2). The
atomic decomposition and verification in between are the same regardless.

## Workflow

### 1. Identify the design source

Determine which source you have and extract its structure (layout, styling — colors/spacing/typography,
text content, icons, image assets). See `references/design-sources.md` for the details of each.

- **Stitch** — the input is a URL containing `stitch.withgoogle.com`. Fetch via the Stitch MCP
  (`mcp__stitch__get_screen`).
- **Claude Design** — Anthropic's visual tool (claude.ai/design) has **no API/MCP**. It integrates by
  exporting a **handoff bundle you pass to Claude Code** or a **standalone HTML** export. Read the bundle
  or HTML file directly to recover layout, design tokens, and assets.
- **Image / screenshot** — a pasted mockup or image file. Read it visually and infer structure, spacing,
  and color from the pixels.

If the source is ambiguous, ask the user which one they're providing.

### 2. Detect the target framework and styling system

**Do not assume a framework.** Inspect the project before writing anything:

- **Framework** — read `package.json` dependencies (`react`/`next`, `vue`/`nuxt`, `svelte`/`@sveltejs`,
  `@angular/core`, `solid-js`, `preact`), or framework config files (`angular.json`, `svelte.config.*`,
  `nuxt.config.*`). Fall back to plain web components if none is found.
- **Styling system** — Tailwind (`tailwind.config.*`), CSS Modules (`*.module.css`), styled-components /
  Emotion, UnoCSS, or vanilla CSS. Match what the project already uses.
- **Icon library** — e.g. `lucide`, `@heroicons`, Material Symbols, `react-icons`. Reuse the project's.
- **Component directory** — detect the existing structure (e.g. `src/components/`, `app/components/`,
  `src/lib/components/`); **do not hardcode a path**. Note whether atomic folders already exist.

Then load the matching idiom reference: `references/frameworks/{react,vue,svelte,angular}.md` (use the
closest one for frameworks not listed).

### 3. Decompose into atomic layers

Break the design down (see `references/atomic-patterns.md` for the methodology and a sample inventory):

- **Atoms** — buttons, inputs, labels, icons, badges, checkboxes, progress bars. Single-purpose, no deps.
- **Molecules** — search bars, form fields, stat cards, tab groups, nav links. Small atom combinations.
- **Organisms** — headers, sidebars, data tables, complex cards. May hold business logic.
- **Templates / Pages** — layouts that compose organisms into the full screen.

### 4. Reuse existing components

Scan the detected component directory and **reuse whatever already exists** before creating anything new.
Match by purpose, not just name.

### 5. Create the missing components (dependencies first)

Create in dependency order — **atoms → molecules → organisms → templates → pages** — using the detected
framework's idioms and the project's styling system and icon library (per the loaded framework reference).
Keep components small, typed, and accessible.

### 6. Verify against the source

Check the implementation against the original design:

- [ ] **Colors** — match the source (use the project's theme tokens/palette)
- [ ] **Spacing** — padding/margins consistent with the design
- [ ] **Typography** — size, weight, line-height
- [ ] **Layout** — flex/grid structure correct
- [ ] **Responsive** — breakpoints handled
- [ ] **Dark mode** — included if the project/design supports it
- [ ] **Icons** — match the design, drawn from the project's icon library

For an objective comparison, render the result and screenshot-compare against the source (the
`webapp-testing` skill / Playwright can drive this).

## Notes

- **Framework-agnostic** — always detect; never default to a specific framework.
- **Atomic design is the through-line** — keep the atoms→pages decomposition regardless of source or
  framework.
- **Claude Design has no programmatic API** — consume its handoff bundle or HTML export as files.

## References

- `references/design-sources.md` — Stitch MCP, Claude Design handoff/HTML, and image inputs; design-data
  interpretation (layout/color/typography/spacing mapping).
- `references/atomic-patterns.md` — atomic-design methodology and a sample component inventory.
- `references/frameworks/{react,vue,svelte,angular}.md` — per-framework component idioms.
