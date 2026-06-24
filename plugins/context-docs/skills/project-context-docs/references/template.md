# Per-File Templates

Use these templates when generating each file under `docs/context/`. Adapt sections to fit the project — omit sections that don't apply.

---

## INDEX.md (40-80 lines — always in context)

```markdown
# {Project Name}

> Generated {date}. Source of truth is always the code.

## What It Does
{1-3 sentences: what the product does, who uses it, why.}

## Tech Stack
| Layer | Technology |
|-------|-----------|
| Language | {e.g., TypeScript 5.x} |
| Framework | {e.g., Angular 21, Next.js 15} |
| Styling | {e.g., Tailwind CSS 4} |
| Testing | {e.g., Vitest + Playwright} |
| Build | {e.g., esbuild via Angular CLI} |
| CI/CD | {e.g., GitHub Actions} |
| Infra | {e.g., Docker + nginx} |
| Package Manager | {e.g., pnpm 10.x} |

## Quick Commands
\```bash
{install}   # Install dependencies
{dev}       # Start dev server
{build}     # Production build
{test}      # Run tests
{lint}      # Lint
\```

## Key Files
| File | Purpose |
|------|---------|
| {entry point} | App bootstrap |
| {routes file} | Route definitions |
| {env config} | Environment config |
| {CI config} | CI/CD pipeline |

## Context Files
Load these ONLY when relevant to your task:
- `architecture.md` — module org, data flow, routing, auth
- `adrs.md` — architectural decisions that MUST be followed
- `standards.md` — code style, naming, imports, git conventions
- `patterns.md` — component, service, state, API patterns with code
- `testing.md` — test strategy, patterns, anti-patterns with code
- `examples.md` — how-to guides for common modifications
- `troubleshooting.md` — build/test issues, known gotchas
- `tooling.md` — required tools, versions, env vars
- `data-models.md` — schema, entities, relations (if applicable)
- `api.md` — endpoint catalog, contracts (if applicable)
- `dependencies.md` — key libs, what NOT to use
```

---

## architecture.md (60-150 lines)

```markdown
# Architecture

## Directory Structure
\```
{Annotated tree — top-level + key nested dirs. Skip node_modules, dist, etc.}
\```

## Module Organization
{Pattern: flat, feature-based, domain-driven, atomic design, etc.
Where new code should go.}

## Data Flow
\```
{How data moves: API layer → state → components.}
User Action -> Component -> Service -> API -> Backend
                  ^                        |
                  |--- Signal/State <------+
\```

## Routing & Entry Points
{Bootstrap process. Key entry files. Routing strategy. Layout hierarchy.}

## Authentication & Authorization
{Auth strategy, token handling, guards/middleware. Note active migrations.}
```

---

## adrs.md (60-150 lines)

```markdown
# Architectural Decision Records

Decisions that MUST be followed. Each entry explains what was decided and why.

## ADR-{N}: {Title}
- **Status**: {Accepted / Superseded by ADR-X / Deprecated}
- **Context**: {Why was this decision needed?}
- **Decision**: {What was decided}
- **Consequences**: {Trade-offs, constraints this creates}

{Look for decisions about:
- Package manager choice
- Framework/version choice
- Styling approach
- State management strategy
- Auth provider
- Testing strategy
- Component architecture
- Routing strategy
- API layer design
- Deployment target
- Monorepo vs polyrepo}
```

---

## standards.md (60-150 lines)

```markdown
# Standards

## Code Style
{Linter + formatter config. Key enforced rules. Pre-commit hooks.}
\```
{linter} -> {formatter} -> {pre-commit hook tool}
\```

## Naming Conventions
| Entity | Convention | Example |
|--------|-----------|---------|
| Files | {e.g., kebab-case} | {e.g., `user-profile.component.ts`} |
| Components | {e.g., PascalCase} | {e.g., `UserProfileComponent`} |
| Services | {e.g., PascalCase + Service} | {e.g., `AuthService`} |
| Types | {e.g., PascalCase} | {e.g., `UserProfile`} |
| Tests | {e.g., co-located .spec.ts} | {e.g., `auth.service.spec.ts`} |
| CSS | {e.g., Tailwind utility} | {e.g., `bg-primary text-white`} |

## Import Conventions
{Path aliases, import ordering, barrel files vs direct imports.}

## Error Handling
{Standard patterns: interceptors, error boundaries, try-catch conventions.}

## Git Conventions
{Commit message format, branch naming, PR conventions.}
```

---

## patterns.md (60-150 lines)

```markdown
# Patterns

## Component Pattern
\```{language}
// Example: typical component structure
{annotated code skeleton from actual project}
\```

## Service / Data Access Pattern
\```{language}
// Example: typical service structure
{annotated code skeleton}
\```

## State Management
{How state is managed. Local vs global. Reactivity model.}

## API Integration
{How API calls are made. Request/response typing. Multipart uploads. Pagination.}
```

---

## testing.md (60-150 lines)

```markdown
# Testing

## Strategy
| Type | Tool | Location | Coverage Target |
|------|------|----------|----------------|
| Unit | {e.g., Vitest} | {e.g., co-located *.spec.ts} | {e.g., >80%} |
| Integration | {e.g., Vitest + TestBed} | {same} | {key flows} |
| E2E | {e.g., Playwright} | {e.g., e2e/} | {critical paths} |

## Unit Test Pattern
\```{language}
// Example: representative test showing setup, mocking, assertions
{annotated test code from actual project}
\```

## Key Techniques
{Framework-specific patterns: TestBed setup, signal input testing, mock patterns,
async handling, HTTP testing, etc.}

## Anti-Patterns
{What NOT to do in tests. Project-specific pitfalls.
E.g., "No fakeAsync with Vitest", "Don't mock the database in integration tests".}
```

---

## examples.md (60-150 lines)

```markdown
# Examples

## Adding a New Feature
{Step-by-step with actual file paths:
1. Create types
2. Create service
3. Create component(s)
4. Add route
5. Write tests}

## Adding a New API Integration
{How to integrate a new backend endpoint:
1. Add types
2. Add method to service
3. Use in component}

## Common Modifications
| Task | Files to Modify |
|------|----------------|
| Add a new page | {routes file, new page dir, layout} |
| Add a reusable component | {components dir, atomic level} |
| Add a new API service | {types, service extending base} |
| Add environment config | {environment files, types} |
| Add a test | {co-located .spec.ts} |

## Common Mistakes
{What agents typically get wrong in this specific project:
- Patterns that look right but break project conventions
- Imports that seem obvious but conflict with aliases
- Auth/state assumptions that are wrong for this stack}
```

---

## troubleshooting.md (60-150 lines)

```markdown
# Troubleshooting

## Build Issues
{Common build errors and fixes. Framework-specific gotchas.}

## Test Issues
{Common test failures, environment setup, flaky test patterns.}

## Dev Environment
{Prerequisites, required env vars, common setup issues.}

## Known Gotchas
{Project-specific pitfalls:
- Framework version quirks
- Incompatible library combinations
- Platform-specific issues
- Environment-specific behavior}
```

---

## tooling.md (60-150 lines)

```markdown
# Tooling

## Required Tools
| Tool | Version | Purpose | Install |
|------|---------|---------|---------|
| {e.g., Node.js} | {e.g., 22.x} | Runtime | {e.g., nvm install 22} |
| {e.g., pnpm} | {e.g., 10.x} | Package manager | {e.g., corepack enable} |

## Optional Tools
| Tool | Purpose | When Needed |
|------|---------|-------------|
| {e.g., Docker} | Container builds | Production builds, CI |

## Environment Variables
| Variable | Required | Description | Where Set |
|----------|----------|-------------|-----------|
| {e.g., API_BASE_URL} | {dev/prod/both} | Backend API URL | {.env, CI secrets} |
```

---

## data-models.md (60-150 lines)

```markdown
# Data Models

## Overview
{Database engine, ORM, migration tool. Total number of main entities.}

## Entities

### {EntityName}
| Field | Type | Nullable | Notes |
|-------|------|----------|-------|
| id | {uuid/int} | no | Primary key |
| {field} | {type} | {yes/no} | {constraints, default, FK target} |
| created_at | timestamp | no | Auto-set on insert |

{Repeat for each main entity. Skip junction tables unless they have extra fields.}

## Relations
\```
{Diagram or list of key relations:}
User -> Post (one-to-many, User.id = Post.author_id)
Post <-> Tag (many-to-many via post_tags)
Order -> OrderItem (one-to-many, cascade delete)
\```

## Naming Conventions
{snake_case vs camelCase in DB. Table naming (plural/singular). FK naming pattern.
How ORM maps names (e.g., Prisma camelCase fields → snake_case columns).}

## Migrations
{Where migrations live. How to create and run them. Current state/version.}
\```bash
{migration run command}
{migration create command}
\```
```

---

## api.md (60-150 lines)

```markdown
# API

## Overview
{REST/GraphQL/gRPC. Base URL pattern (e.g., `/api/v1`). Versioning strategy. Auth mechanism.}

## Authentication
{How to authenticate requests — bearer token, session cookie, API key, OAuth flow.
Which routes are public vs protected.}

## Endpoints

### {Resource} (`/api/{resource}`)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/{resource}` | {required/public} | List all {resource} |
| GET | `/api/{resource}/:id` | {required/public} | Get single {resource} |
| POST | `/api/{resource}` | required | Create {resource} |
| PUT | `/api/{resource}/:id` | required | Update {resource} |
| DELETE | `/api/{resource}/:id` | required | Delete {resource} |

**Request body (POST/PUT):**
\```json
{example request body with real field names}
\```

**Response shape:**
\```json
{example response body}
\```

{Repeat per resource group.}

## Error Format
\```json
{standard error response — status, code, message fields}
\```

## Pagination
{Cursor-based / offset-limit / page. Request params and response envelope fields.}
```

---

## dependencies.md (60-150 lines)

```markdown
# Dependencies

## Key Libraries
| Library | Version | Purpose | Why chosen |
|---------|---------|---------|------------|
| {lib} | {x.y.z} | {what it does} | {why this one — vs alternatives not chosen} |

{Focus on non-obvious choices. Skip ubiquitous tools already in tooling.md (Node, pnpm, etc.).}

## Usage Patterns

### {Library Name}
\```{language}
// How this library is actually used in the project
{short annotated example from real code — import path + typical call}
\```

{Include patterns for: HTTP client, state management, auth, ORM, UI component lib.}

## What NOT to Use
| Instead of | Use | Reason |
|-----------|-----|--------|
| {lib to avoid} | {preferred lib already in project} | {why — duplicate, deprecated, policy} |

## Version Constraints
{Libraries pinned to specific versions and why — known breaking changes, peer dep conflicts.
Any libraries that MUST NOT be upgraded without a migration plan.}
```
