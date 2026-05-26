---
name: repo-standards
description: Use when setting up a new repo or auditing an existing repo against org standards for devenv, secrets, testing, observability, CI/CD, code quality, security, and API documentation
---

# Repo Standards

## Overview

Analyze a repository against org standards and produce a gap analysis. This skill discovers what exists, identifies what's missing, and hands findings to the brainstorming workflow for design before any implementation.

**Core principle:** Discover and report, never auto-scaffold. All implementation goes through brainstorm → ADR → plan → execute.

**Announce at start:** "I'm using the repo-standards skill to audit this repository."

## The Process

### Step 1: Discover Project Type

Detect the project by checking for:

| File | Indicates |
|------|-----------|
| `package.json` | Node.js/JS/TS project |
| `go.mod` | Go project |
| `pyproject.toml` / `requirements.txt` | Python project |
| `Cargo.toml` | Rust project |
| `*.csproj` / `*.sln` | .NET project |
| `pom.xml` / `build.gradle` | Java/Kotlin project |

Also detect:
- Framework (Next.js, Express, FastAPI, Gin, etc.)
- Package manager (pnpm, npm, yarn, cargo, pip, etc.)
- Monorepo structure (workspaces, nx, turborepo)

Report: "Detected: [language] project using [framework] with [package manager]"

### Step 2: Run Standards Checklist

Check each area and report status as PASS, PARTIAL, or MISSING.

#### 2.1 Devenv & Reproducibility

| Check | How to verify |
|-------|--------------|
| `devenv.nix` exists | File exists in repo root |
| Language version pinned | `devenv.nix` specifies exact version (e.g., `pkgs.nodejs_22`) |
| Package manager managed by Nix | Package manager enabled in `devenv.nix` (e.g., `pnpm.enable = true`) |
| Auto-install on shell entry | `install.enable = true` or equivalent |
| `devenv.yaml` exists | File exists with nixpkgs input |
| `devenv.lock` committed | Lock file exists and is tracked |
| `.envrc` exists | Direnv integration configured |
| Developer commands as devenv scripts | Key commands (dev, build, test, lint) defined in `scripts` block |
| `enterShell` lists available commands | Shell entry message shows what's available |

#### 2.2 Secrets Management

| Check | How to verify |
|-------|--------------|
| `shared.env` exists | File exists with `op://` references only |
| No plaintext secrets committed | Scan for API keys, tokens, JWTs, passwords in tracked files |
| `local.env.template` exists | Template for per-developer overrides |
| `local.env` gitignored | In `.gitignore` |
| `hack/bin/load-secrets` exists | Secret resolution script present |
| `.secrets.cache.env` gitignored | In `.gitignore` |
| Secret-sensitive scripts use load-secrets | devenv scripts for dev/build/start wrap through load-secrets |
| `pull-secrets` devenv script exists | Explicit command to refresh secrets |

#### 2.3 Test Strategy

| Check | How to verify |
|-------|--------------|
| Test runner configured | Config file exists (vitest.config, jest.config, pytest.ini, etc.) |
| `test` devenv script exists | Defined in `devenv.nix` scripts |
| `test-watch` devenv script exists | For TDD workflow |
| Test files discoverable | Clear pattern (co-located or `tests/` directory) |
| Test setup/helpers exist | Setup file, factories, shared utilities |
| Mock/offline dev mode | `dev-mock` or equivalent for no-backend development |
| `.env.mock` or equivalent | Committed dummy values for mock mode |

#### 2.4 Observability

| Check | How to verify |
|-------|--------------|
| OpenTelemetry instrumented | OTel SDK in dependencies, initialization code present |
| Structured logging | No bare `console.log`/`print` in production code; uses a logging library |
| Error reporting configured | Error tracking service integrated (Sentry, etc.) or OTel error spans |
| Traces for external calls | HTTP clients / DB queries instrumented with trace spans |

#### 2.5 CI/CD

| Check | How to verify |
|-------|--------------|
| Pipeline exists | `.github/workflows/`, `.gitlab-ci.yml`, etc. |
| Lint step | Pipeline runs linter |
| Type check step | Pipeline runs type checker (where applicable) |
| Test step | Pipeline runs tests |
| Build step | Pipeline builds artifact |
| Secrets injected at runtime | No secrets baked into build artifacts |
| Deploy strategy defined | Per-environment deployment (dev, staging, prod) |

#### 2.6 Code Quality Gates

| Check | How to verify |
|-------|--------------|
| Linter configured | Config file exists (eslint, golangci-lint, ruff, clippy, etc.) |
| `lint` devenv script exists | Defined in `devenv.nix` scripts |
| Formatter configured | Prettier, gofmt, black, rustfmt, etc. |
| Type checking enabled | TypeScript strict, mypy, etc. (where language supports it) |
| `typecheck` devenv script exists | Defined in `devenv.nix` scripts |

#### 2.7 Security Baseline

| Check | How to verify |
|-------|--------------|
| No secrets in committed files | Scan tracked files for patterns (API keys, tokens, passwords) |
| Lock file committed | `pnpm-lock.yaml`, `go.sum`, `Cargo.lock`, etc. tracked |
| Dependency audit in CI | Pipeline step that checks for known vulnerabilities |
| `.env` files with real values not committed | Only `.env.mock` and `shared.env` (op:// refs) committed |

#### 2.8 API Documentation

| Check | How to verify |
|-------|--------------|
| API routes documented | OpenAPI/Swagger spec, or equivalent docs |
| Docs co-located or generated | Spec lives near code or is auto-generated |
| Usage examples provided | Examples in docs for public-facing APIs |
| `docs` devenv script exists | Devenv script to generate/serve API docs locally |

*Note: Skip this section if the repo has no API endpoints.*

#### 2.9 Planning Surface

Cliban is the org's planning surface. The repo itself should not host planning artefacts; those live as cliban issues (`cliban issue show KEY`) and travel with the project, not the source tree.

| Check | How to verify |
|-------|--------------|
| No in-repo `plans/` directory | `find . -type d -name plans -not -path '*/.git/*' -not -path '*/target/*' -not -path '*/node_modules/*'` returns nothing |
| No in-repo `specs/` directory | Same search for `specs` |
| No `docs/superpowers/` directory | Legacy from the pre-cliban workflow; should not exist |
| No top-level `TODO.md` / `PLAN.md` / `ROADMAP.md` / `SPEC.md` | Audit/planning docs at the repo root indicate the planning surface has leaked into the tree |
| Source comments don't link planning docs | `grep -rn 'docs/superpowers\|standard/plans\|standard/specs' <source-dirs>` returns nothing — historical pointers must be swept, not left as 404s |
| Authoritative spec files (if any) are self-contained | A repo MAY host an authoritative reference spec (e.g. a language standard); when present, its text MUST NOT reference cliban keys, source-code paths, or external design docs. Cross-references go to other Standard sections or to formally-numbered change records. |

**Rationale:** plan/design docs decay fast and rot in-tree (commits move on, the docs don't). Keeping them in cliban means each iteration of a plan replaces the prior one and the source tree only carries the resulting code + tests + spec text — what readers actually need.

*Note: For repos that pre-date cliban migration, the historical artefacts may need a sweep PR (search the project's cliban backlog for "sweep dead doc-pointers" or file one).*

### Step 3: Produce Gap Report

Present findings organized by area:

```
## Repo Standards Audit: [repo-name]

**Project type:** [language] / [framework] / [package manager]

### Summary
- PASS: N areas
- PARTIAL: N areas
- MISSING: N areas

### Detailed Findings

#### [Area Name] — [PASS|PARTIAL|MISSING]

| Check | Status | Notes |
|-------|--------|-------|
| ... | PASS/MISSING | ... |

[Repeat for each area]

### Recommended Priority
1. [Most critical gap]
2. [Second most critical]
3. ...
```

### Step 4: Hand Off to Brainstorming

After presenting the gap report:

"These are the gaps I found. Ready to brainstorm the design for addressing them?"

Then invoke **superpowers:brainstorming** to design the solution. The brainstorming session will:
1. Use the gap report as input
2. Design the devenv setup, testing strategy, etc.
3. Produce an ADR documenting decisions
4. Flow into planning and execution

## Key Principles

- **Discover, don't prescribe** — Report what's there and what's missing. Don't assume solutions.
- **Language-agnostic** — Detect project type and adapt checks. The principles are universal; the tooling varies.
- **No auto-scaffolding** — Every gap goes through the brainstorm → ADR → plan → execute pipeline.
- **Heuristic-based** — Some checks may have false positives/negatives. Report confidence level when uncertain.
- **Reference implementation** — The marketplace-frontend repo at `~/dev/remote/github.com/RilianTech/marketplace-frontend` is the gold standard for JS/TS projects.

## Integration

**Delegates to:**
- **brainstorming** — After gap report, to design solutions

**Referenced by:**
- **requesting-code-review** — Devenv review guard uses a subset of these checks on diffs

## Your Job

1. Create the directory if needed: `mkdir -p skills/repo-standards`
2. Write the skill file with the EXACT content above
3. Verify the frontmatter is correct with `head -4 skills/repo-standards/SKILL.md`
4. Do NOT commit
