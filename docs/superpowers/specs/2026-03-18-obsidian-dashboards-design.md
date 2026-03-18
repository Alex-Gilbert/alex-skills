# Obsidian Bases Dashboard Generation — Design Specification

**Date:** 2026-03-18
**Status:** Approved

## Overview

Auto-generate Obsidian Bases `.base` files that provide live dashboard views over the memory vault. A Command Center for the big picture, plus drill-down dashboards for ideas, bugs, decisions, and projects. Cards grouped by status or severity give a kanban-like experience. Dashboards regenerate automatically on server startup and after every memory write.

## Goals

- Open Obsidian, see what needs attention without running any commands
- Idea pipeline as a kanban board (open → active → archived)
- Bug triage view grouped by severity
- Decision log for recent architectural choices
- Project status at a glance
- Zero maintenance — dashboards self-heal on every memory write

## Dashboard Files

**Location:** `~/alex-vault/Claude/_dashboards/`

Underscore prefix sorts first in Obsidian's file explorer and signals "generated/meta." Directory added to `vault.ignore` in config for hygiene.

### 1. `command-center.base` — Everything at a glance

- **Primary view:** Cards grouped by `type` — see all active work across memory types
- **Secondary view:** Table sorted by `updated` desc — chronological detail view
- **Filters:** All Claude/ subdirectories, exclude `archived` and `wontfix` status

### 2. `idea-pipeline.base` — Idea lifecycle

- **Primary view:** Cards grouped by `status` — columns: open | active | archived
- **Secondary view:** Table sorted by `updated` desc
- **Filters:** `Claude/ideas` folder only
- **Shows full lifecycle** including archived (graduated to spec) for progression visibility

### 3. `bug-board.base` — Bug triage

- **Primary view:** Cards grouped by `severity` — columns: p0 | p1 | p2 | p3
- **Secondary view:** Table sorted by `severity` asc (most urgent first)
- **Filters:** `Claude/bugs` folder, exclude `resolved` status in cards view

### 4. `decision-log.base` — Recent decisions

- **Primary view:** Table sorted by `created` desc — most recent first
- **Secondary view:** Cards grouped by `status`
- **Filters:** `Claude/decisions` folder

### 5. `active-projects.base` — Project status

- **Primary view:** Cards grouped by `status`
- **Secondary view:** Table sorted by `updated` desc
- **Filters:** `Claude/projects` folder

**Note:** Dedicated dashboards cover 4 of 9 memory types (bugs, ideas, decisions, projects). The remaining 5 (memory, pattern, session, reference, brainstorm) are visible through the Command Center only. This is intentional — those types don't benefit from dedicated views.

**View ordering:** "Primary view" = first entry in the `views` array (default tab when opened). "Secondary view" = second entry (available as a tab).

## `.base` File Format

Obsidian Bases files are YAML. Filters use expression strings with `=` for equality, `!=` for inequality, combined with `and`/`or`/`not` wrappers. `file.folder` filters on vault directory, frontmatter properties are referenced by name.

### Reference Template: `idea-pipeline.base`

```yaml
filters:
  expression: 'file.folder = "Claude/ideas"'
properties:
  status:
    width: 100
  tags:
    width: 150
  created:
    width: 120
  updated:
    width: 120
  author:
    width: 100
views:
  - type: cards
    name: "Pipeline"
    groupBy:
      property: status
    order:
      - property: updated
        direction: desc
  - type: table
    name: "All Ideas"
    order:
      - property: updated
        direction: desc
```

### Reference Template: `command-center.base`

```yaml
filters:
  and:
    - or:
        - expression: 'file.folder = "Claude/bugs"'
        - expression: 'file.folder = "Claude/decisions"'
        - expression: 'file.folder = "Claude/projects"'
        - expression: 'file.folder = "Claude/ideas"'
        - expression: 'file.folder = "Claude/brainstorms"'
        - expression: 'file.folder = "Claude/patterns"'
        - expression: 'file.folder = "Claude/memory"'
        - expression: 'file.folder = "Claude/references"'
        - expression: 'file.folder = "Claude/sessions"'
    - expression: 'status != "archived"'
    - expression: 'status != "wontfix"'
properties:
  type:
    width: 100
  status:
    width: 100
  severity:
    width: 80
  updated:
    width: 120
  tags:
    width: 150
  author:
    width: 100
views:
  - type: cards
    name: "By Type"
    groupBy:
      property: type
    order:
      - property: updated
        direction: desc
  - type: table
    name: "All Active"
    order:
      - property: updated
        direction: desc
```

### Remaining Dashboards

Follow the same pattern. Key variations:

- **`bug-board.base`**: `file.folder = "Claude/bugs"`, cards `groupBy: severity`, cards view adds filter `status != "resolved"`, table view sorts by `severity` asc. Properties include `severity` at width 80.
- **`decision-log.base`**: `file.folder = "Claude/decisions"`, primary view is table (sorted `created` desc), secondary is cards `groupBy: status`. Properties include `created` at width 120.
- **`active-projects.base`**: `file.folder = "Claude/projects"`, cards `groupBy: status`, table sorted `updated` desc.

## New Module: `dashboard_writer.gleam`

**Location:** `src/alex_memory/mcp/dashboard_writer.gleam`

**Public API:**
```
regenerate(vault_root: String, claude_dir: String) -> Result(Nil, String)
```

Writes all 5 `.base` files to `{vault_root}/{claude_dir}/_dashboards/`. Ensures the directory exists before writing. Uses `simplifile` (existing dependency) for file I/O.

**YAML generation:** String concatenation, same pattern as `frontmatter.serialize`. No YAML library needed — content is static templates with only `claude_dir` substituted into folder path expressions.

**Idempotent:** Safe to call repeatedly. Overwrites existing files with fresh content.

**Error handling:** Best-effort — writes as many files as possible. Returns `Error` with the first error message encountered. Callers log and continue; a failed dashboard generation never blocks memory operations. The next successful call writes all 5 files fresh, so partial failures self-heal.

**Concurrency:** Rapid memory writes may spawn multiple concurrent `regenerate` calls. This is harmless — each call writes the same static content, so concurrent overwrites produce identical results. No debouncing needed.

## Integration Points

### 1. Server startup

In `setup_infrastructure` in `alex_memory.gleam`, at the end of the function (after triggering the async reindex via `embedder.ReindexAll`). Dashboards don't depend on the reindex completing — they query frontmatter, not Qdrant.

```
dashboard_writer.regenerate(config.vault.path, config.vault.claude_dir)
```

Non-fatal if it fails — log warning and continue.

### 2. After `memory_store`

In `handle_store` in `server.gleam`, after successful vault write + embedder send. Spawned in a background process to not block the MCP response:

```
process.spawn(fn() { dashboard_writer.regenerate(...) })
```

### 3. After `memory_update`

Same pattern as store — spawned background regeneration.

## Testing

**File:** `test/alex_memory/mcp/dashboard_writer_test.gleam`

Test `regenerate` against a temp directory:
- Verify all 5 `.base` files are created
- Verify each file contains expected view type strings (e.g., `"type: cards"`, `"type: table"`)
- Verify filter expressions reference correct folders (e.g., `Claude/ideas`, `Claude/bugs`)
- Verify idempotency: calling `regenerate` twice produces identical files

## Config Change

Add `_dashboards` to the vault ignore list in `config/config.toml`:

```toml
ignore = [".obsidian", ".git", ".trash", "_dashboards"]
```

Technically optional (vault watcher filters to `.md` only), but explicit is better.

## Not In Scope

- No new MCP tool — dashboards are an Obsidian display concern
- No `/status` skill changes — CLI summaries stay separate
- No auto-linking between memories (deferred)
- No Kanban plugin integration — Bases cards-grouped-by-status is sufficient
- No custom dashboard creation — fixed set of 5 dashboards
- No Dataview dependency — Bases is built-in, no plugins needed
