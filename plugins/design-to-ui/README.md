# design-to-ui

Turn a design into framework-native UI components following **atomic design**. The design *source* and the
target *framework* are both pluggable.

| Skill | What it does | Trigger |
|-------|--------------|---------|
| `design-to-ui` | Reads a design, decomposes it into atoms→molecules→organisms→templates→pages, reuses existing components, generates the missing ones in the project's framework + styling system, then verifies against the source. | a Stitch URL, a Claude Design export/handoff, a screenshot, or "implement this design / screen / mockup", "pixel-perfect" |

**Design sources (any one):**
- **Google Stitch** — a `stitch.withgoogle.com` URL, fetched via the Stitch MCP.
- **Claude Design** (claude.ai/design) — it has *no API/MCP*; consume the **handoff bundle it packages for
  Claude Code** or its **standalone HTML export**.
- **Image / screenshot** — read visually.

**Target framework is detected**, never assumed — React, Vue, Svelte, Angular, Solid, Preact, or plain web
components — along with the styling system (Tailwind / CSS Modules / styled-components / …) and icon library.

## Install
```bash
/plugin install design-to-ui@claude-plugins
```

## Dependencies
- **Optional:** the Stitch MCP server (only for Stitch URLs); Claude Design artifacts as files; Playwright /
  the `webapp-testing` skill for screenshot-based verification.
- Otherwise just the target project's own framework toolchain. No API keys required by the skill itself.
