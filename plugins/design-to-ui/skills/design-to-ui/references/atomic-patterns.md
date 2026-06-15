# Atomic Design Patterns (framework-neutral)

Atomic design organizes a UI into five layers. `design-to-ui` keeps this decomposition regardless of the
source design or the target framework. Generate components bottom-up: **atoms → molecules → organisms →
templates → pages** (dependencies first).

## The five layers

| Layer | What it is | Examples | Depends on |
|-------|------------|----------|-----------|
| **Atoms** | Single-purpose building blocks, no dependence on other custom components | button, input, label, icon, badge, checkbox, progress-bar, select, slider | nothing |
| **Molecules** | Small groups of atoms with minimal local state | search input, form field, stat card, nav link, pagination, tab group | atoms |
| **Organisms** | Larger sections, may hold business logic | app/header bar, sidebar, data table, card, page header, form section | atoms + molecules |
| **Templates** | Page-level layout/skeleton with placeholders | dashboard layout, two-column layout | organisms |
| **Pages** | A template filled with real content/data | the concrete screen | templates + organisms |

## Sample inventory (illustrative)

A typical component library looks like the following. **This is an example, not a fixed contract** — detect
the actual inventory in the target project and reuse what exists.

- **Atoms:** badge, button, checkbox, icon, indicator-dot, input-field, progress-bar, select, slider
- **Molecules:** action-button-group, filter-bar, form-field, nav-link, pagination, search-input,
  stat-card, tab-group
- **Organisms:** app-bar, card, form-section, page-header, sidebar

## Component design principles (any framework)

- **One responsibility per atom.** Variants/sizes are props, not new components.
- **Props in, events out.** Atoms/molecules are presentational; push state up. Use the framework's
  idiomatic prop and event mechanism (see `frameworks/<framework>.md`).
- **Compose, don't duplicate.** Build molecules from atoms, organisms from molecules.
- **Style with the project's system.** Use existing theme tokens/palette before literal colors. Support
  dark mode if the project does.
- **Accessibility.** Semantic elements, labels, focus states, keyboard support.
- **Reuse first.** Always check the existing component directory before creating a new component.

## Creating a new component — checklist

1. Pick the correct layer (atom/molecule/organism/template/page) and place it in the matching directory.
2. Define a minimal, typed prop API; emit events for interactions.
3. Use the framework's idioms for local state and rendering (conditionals/lists) — see the framework ref.
4. Style with the detected styling system; pull colors from theme tokens; add dark-mode variants if used.
5. Use the project's icon library.
6. Export it the way the project does (barrel file / index), and wire it into its parent.

See `frameworks/{react,vue,svelte,angular}.md` for concrete per-framework idioms, and `design-sources.md`
for mapping raw design data (colors/spacing/typography) onto the styling system.
