---
name: project-context-docs
description: >
  Generate comprehensive context engineering documentation for any software project.
  Analyzes the entire codebase — config files, source code, tests, CI/CD, docs, and git history —
  to produce a modular set of reference files that AI agents lazy-load on demand.
  Use when: (1) user asks to "document this project", "create context docs", "generate project documentation",
  "create onboarding docs for agents", (2) user wants to capture architectural decisions and coding standards,
  (3) user needs project reference files for AI-assisted development,
  (4) user says "analyze this codebase and document it".
---

# Project Context Documentation Generator

Generate a modular documentation set under `docs/context/` that AI agents load on-demand. Each file is small and self-contained — agents only load the file relevant to their current task.

## Output Structure

```
docs/context/
  INDEX.md              # Always loaded — project identity, tech stack, quick commands, file map
  architecture.md       # Module organization, data flow, routing, auth
  adrs.md               # Architectural Decision Records — decisions that MUST be followed
  standards.md          # Code style, naming, imports, git conventions
  patterns.md           # Component, service, state, API integration patterns with code examples
  testing.md            # Test strategy, patterns, techniques, anti-patterns with code examples
  examples.md           # How-to guides: add feature, integrate API, common modifications
  troubleshooting.md    # Build issues, test issues, dev env, known gotchas
  tooling.md            # Required/optional tools, versions, env vars
```

**Loading rules for agents:**
- `INDEX.md` is always in context (kept under 80 lines)
- Other files are loaded ONLY when the agent's task matches the file's domain
- Each file is self-contained — no cross-references needed to understand it

## Process

1. **Discover** — Scan the project to identify its tech stack, structure, and conventions
2. **Extract** — Read key files to collect information for each documentation section
3. **Synthesize** — Write each file using templates from `references/`

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
- `ls` on top-level `src/` (or equivalent) for module organization
- Component hierarchy pattern (flat, feature-based, domain-driven, atomic design)
- Monorepo indicators: `packages/`, `apps/`, `nx.json`, `turbo.json`, `pnpm-workspace.yaml`

### 1d. Existing Documentation
- `docs/` directory, ADR files, API specs (`openapi.*`, `swagger.*`, `*.proto`, `schema.graphql`)

### 1e. Git Context
```
git log --oneline -20
git branch -a
git remote -v
```

## Step 2: Extract

Read discovered files. Prioritize:
1. Config files (tooling decisions)
2. Entry points (bootstrap/routing architecture)
3. A representative component/module (coding patterns)
4. A representative test file (testing patterns)
5. CI/CD files (deploy pipeline, quality gates)

## Step 3: Synthesize

Write each file under `docs/context/` using the templates in `references/`. Start with `INDEX.md`, then write the remaining files in order.

**Guidelines:**
- State facts from code observation — never invent or assume
- Note ambiguities explicitly
- Prefer code snippets over prose for patterns
- Each file must be self-contained — readable without loading other context files
- Use the project's actual file paths and names in examples
- For ADRs, capture "why" not just "what"
- Note inconsistencies between existing docs and actual code
- Omit files that don't apply (e.g., skip `adrs.md` if no decisions are discoverable)

**File size targets:**
- `INDEX.md`: 40-80 lines (always in context — keep minimal)
- Other files: 60-150 lines each (enough detail to be useful, small enough for lazy loading)

After writing, show the user the list of generated files and offer to refine any section.
