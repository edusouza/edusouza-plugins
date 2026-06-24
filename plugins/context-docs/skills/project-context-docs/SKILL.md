---
name: project-context-docs
description: >
  Generate comprehensive context engineering documentation for any software project.
  Analyzes the entire codebase — config files, source code, tests, CI/CD, docs, and git history —
  to produce a modular set of reference files that AI agents lazy-load on demand.
  Use when: (1) user asks to "document this project", "create context docs", "generate project documentation",
  "create onboarding docs for agents", (2) user wants to capture architectural decisions and coding standards,
  (3) user needs project reference files for AI-assisted development, (4) user says "analyze this codebase
  and document it", (5) user asks to "update context docs", "update architecture docs", "refresh project docs",
  or "sync context to CLAUDE.md".
---

# Project Context Documentation Generator

Generate a modular documentation set under `docs/context/` that AI agents load on-demand. Each file is small and self-contained — agents only load the file relevant to their current task.

## Commands

| Invocation | Behavior |
|-----------|----------|
| `/project-context-docs` | Full init: scan codebase, generate all docs, write manifest, update `CLAUDE.md` |
| `/project-context-docs update` | Re-generate all docs using the existing manifest to skip discovery |
| `/project-context-docs update <section>` | Re-generate a single file (e.g., `update standards`, `update api`) |
| `/project-context-docs sync-claude-md` | Inject or refresh the `## Context Docs` block in the project's `CLAUDE.md` |

## Output Structure

```
docs/context/
  .meta.json           # Manifest: stack, key files, generated files, last commit
  INDEX.md             # Always loaded — project identity, tech stack, quick commands, file map
  architecture.md      # Module organization, data flow, routing, auth
  adrs.md              # Architectural Decision Records — decisions that MUST be followed
  standards.md         # Code style, naming, imports, git conventions
  patterns.md          # Component, service, state, API integration patterns with code examples
  testing.md           # Test strategy, patterns, techniques, anti-patterns with code examples
  examples.md          # How-to guides: add feature, integrate API, common modifications
  troubleshooting.md   # Build issues, test issues, dev env, known gotchas
  tooling.md           # Required/optional tools, versions, env vars
  data-models.md       # Database schema, entities, relations, field conventions (if applicable)
  api.md               # Endpoint catalog, request/response contracts, auth per route (if applicable)
  dependencies.md      # Key libs, why chosen, usage patterns, what NOT to use
```

**Loading rules for agents:**
- `INDEX.md` is always in context (kept under 80 lines)
- Other files are loaded ONLY when the agent's task matches the file's domain
- Each file is self-contained — no cross-references needed to understand it

## Process

Route based on the command:

- **Default (init)**: run Steps 1–5
- **`update`**: skip Step 1 (read manifest instead), run Steps 2–5 with full regeneration
- **`update <section>`**: skip Steps 1 and 3, regenerate only the named file, then run Step 4 to update the manifest
- **`sync-claude-md`**: run Step 5 only

---

## Step 1: Discover

Scan these categories using Glob and Grep (not shell commands):

### 1a. Project Identity
- `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `Gemfile`, `pom.xml`, `build.gradle`
- `README.md`, `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `CONTRIBUTING.md`, `.cursorrules`

### 1b. Configuration & Tooling
- Build: `angular.json`, `vite.config.*`, `webpack.config.*`, `next.config.*`, `tsconfig*.json`, `Makefile`
- Lint/Format: `eslint.config.*`, `.eslintrc*`, `.prettierrc*`, `biome.json`, `.editorconfig`
- Test: `vitest.config.*`, `jest.config.*`, `pytest.ini`, `playwright.config.*`, `cypress.config.*`
- CI/CD: `.github/workflows/*.yml`, `.gitlab-ci.yml`, `Jenkinsfile`, `.circleci/config.yml`
- Infra: `Dockerfile*`, `docker-compose*.yml`, `terraform/*.tf`, `*.tofu`, `serverless.yml`, `wrangler.toml`, `fly.toml`, `nginx.conf*`
- Hooks: `.husky/`, `.pre-commit-config.yaml`
- Lockfiles: `pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`, `poetry.lock`, `Cargo.lock`, `go.sum`

### 1c. Source Structure
- Top-level `src/` (or equivalent) for module organization
- Component hierarchy pattern (flat, feature-based, domain-driven, atomic design)
- Monorepo indicators: `packages/`, `apps/`, `nx.json`, `turbo.json`, `pnpm-workspace.yaml`

### 1d. Existing Documentation
- `docs/` directory, ADR files, API specs (`openapi.*`, `swagger.*`, `*.proto`, `schema.graphql`)

### 1e. Data Layer
- ORM/schema files: `prisma/schema.prisma`, `drizzle/`, `db/schema.*`, `models/`
- Migration files: `migrations/`, `db/migrations/`
- Entity patterns: `*.entity.ts`, `*.model.ts`, `*.schema.ts`
- Database config: `database.yml`, `knexfile.*`, `ormconfig.*`, `drizzle.config.*`

### 1f. API Surface
- Route files: `routes/`, `*router.*`, `*controller.*`, `pages/api/`, `app/api/`, `*.routes.ts`
- API specs: `openapi.yml`, `openapi.yaml`, `swagger.json`, `schema.graphql`, `*.graphql`, `*.proto`

### 1g. Dependencies
- Read `package.json` (or equivalent) `dependencies` + `devDependencies`
- Identify: UI library, state management, HTTP client, auth, ORM, test framework, bundler, linter/formatter

### 1h. Git Context
```bash
git log --oneline -20
git rev-parse HEAD
```

---

## Step 2: Extract

Read discovered files. Prioritize:
1. Config files (tooling decisions)
2. Entry points (bootstrap/routing architecture)
3. Schema/model/migration files (data layer)
4. Route/controller files (API surface)
5. `package.json` or equivalent (dependencies)
6. A representative component/module (coding patterns)
7. A representative test file (testing patterns)
8. CI/CD files (deploy pipeline, quality gates)

If running `update` (not init): read `.meta.json` to get `stack` and `key_files` — use those as the starting point and only re-read files that are relevant to what changed.

---

## Step 3: Synthesize

Write each applicable file under `docs/context/` using the templates in `references/`. Start with `INDEX.md`, then write the remaining files in order.

**Which files to generate:**
- Always: `INDEX.md`, `architecture.md`, `standards.md`, `patterns.md`, `testing.md`, `examples.md`, `tooling.md`, `dependencies.md`
- If ADRs are discoverable: `adrs.md`
- If data layer found: `data-models.md`
- If routes/controllers/OpenAPI found: `api.md`
- Skip `troubleshooting.md` unless gotchas are discoverable from README, comments, or issue history

**Guidelines:**
- State facts from code observation — never invent or assume
- Note ambiguities explicitly rather than guessing
- Prefer code snippets over prose for patterns
- Each file must be self-contained — readable without loading other context files
- Use the project's actual file paths and names in examples
- For ADRs, capture "why" not just "what"
- Note inconsistencies between existing docs and actual code
- Include a **"Common Mistakes"** block in `examples.md` — what agents typically get wrong in this project

**File size targets:**
- `INDEX.md`: 40-80 lines (always in context — keep minimal)
- Other files: 60-150 lines each (enough detail to be useful, small enough for lazy loading)

---

## Step 4: Write Manifest

Write `docs/context/.meta.json` after every generation (init, update, or partial update):

```json
{
  "generated_at": "<ISO date>",
  "commit": "<git rev-parse HEAD output>",
  "stack": {
    "language": "<detected>",
    "framework": "<detected>",
    "test_tool": "<detected>",
    "build_tool": "<detected>",
    "package_manager": "<detected>",
    "ci": "<detected>"
  },
  "key_files": {
    "entry": "<path or null>",
    "routes": "<path or null>",
    "schema": "<path or null>",
    "env": "<path or null>",
    "ci": "<path or null>"
  },
  "generated_files": ["<list of files actually written, e.g. INDEX.md, architecture.md, ...>"]
}
```

---

## Step 5: Sync CLAUDE.md

Find the project's `CLAUDE.md` at the repository root. If it doesn't exist, create it.

Inject or replace a `## Context Docs` block. If a `## Context Docs` block already exists, replace it entirely. Only include rows for files that were actually generated.

```markdown
## Context Docs

AI context docs live under `docs/context/`. Always load `INDEX.md` first; then only load the file relevant to your current task.

| File | Load when... |
|------|-------------|
| `docs/context/INDEX.md` | Always — stack, commands, key files |
| `docs/context/architecture.md` | Touching module structure, routing, or auth |
| `docs/context/standards.md` | Writing new code |
| `docs/context/patterns.md` | Implementing a component, service, or API call |
| `docs/context/testing.md` | Writing or fixing tests |
| `docs/context/examples.md` | Adding a new feature or common modification |
| `docs/context/troubleshooting.md` | Debugging build, test, or env issues |
| `docs/context/tooling.md` | Setting up the dev environment |
| `docs/context/data-models.md` | Working with database entities or schema |
| `docs/context/api.md` | Calling or implementing API endpoints |
| `docs/context/dependencies.md` | Choosing or adding a library |
| `docs/context/adrs.md` | Making architectural decisions — check here first |
```

---

After completing all steps, show the user:
1. List of generated/updated files
2. Confirmation that `CLAUDE.md` was updated (or already up-to-date)
3. Offer to refine any specific section
