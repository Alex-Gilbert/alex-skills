# Obsidian Bases Dashboard Generation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Auto-generate 5 Obsidian Bases `.base` dashboard files that provide live kanban-like views over the memory vault.

**Architecture:** New `dashboard_writer.gleam` module generates static YAML `.base` files via string concatenation. Triggered on server startup and after every `memory_store`/`memory_update` via spawned background processes. No new MCP tool.

**Tech Stack:** Gleam, simplifile, Obsidian Bases YAML format

**Spec:** `docs/superpowers/specs/2026-03-18-obsidian-dashboards-design.md`

---

## Chunk 1: Dashboard Writer Module

### Task 1: Create `dashboard_writer.gleam` with test

**Files:**
- Create: `src/alex_memory/mcp/dashboard_writer.gleam`
- Create: `test/alex_memory/mcp/dashboard_writer_test.gleam`

- [ ] **Step 1: Write the failing test**

Create `test/alex_memory/mcp/dashboard_writer_test.gleam`:

```gleam
import alex_memory/mcp/dashboard_writer
import gleam/string
import gleeunit/should
import simplifile

pub fn regenerate_creates_all_dashboard_files_test() {
  // Use a temp directory
  let tmp = "/tmp/alex-memory-dashboard-test"
  let claude_dir = "Claude"
  let dashboard_dir = tmp <> "/" <> claude_dir <> "/_dashboards"

  // Clean up any previous test run
  let _ = simplifile.delete_all([tmp])

  // Run regenerate
  dashboard_writer.regenerate(tmp, claude_dir)
  |> should.be_ok

  // Verify all 5 files exist
  simplifile.is_file(dashboard_dir <> "/command-center.base")
  |> should.be_ok
  |> should.be_true

  simplifile.is_file(dashboard_dir <> "/idea-pipeline.base")
  |> should.be_ok
  |> should.be_true

  simplifile.is_file(dashboard_dir <> "/bug-board.base")
  |> should.be_ok
  |> should.be_true

  simplifile.is_file(dashboard_dir <> "/decision-log.base")
  |> should.be_ok
  |> should.be_true

  simplifile.is_file(dashboard_dir <> "/active-projects.base")
  |> should.be_ok
  |> should.be_true

  // Clean up
  let _ = simplifile.delete_all([tmp])
  Nil
}

pub fn regenerate_command_center_contains_expected_content_test() {
  let tmp = "/tmp/alex-memory-dashboard-content-test"
  let claude_dir = "Claude"
  let dashboard_dir = tmp <> "/" <> claude_dir <> "/_dashboards"

  let _ = simplifile.delete_all([tmp])

  dashboard_writer.regenerate(tmp, claude_dir)
  |> should.be_ok

  let assert Ok(content) =
    simplifile.read(dashboard_dir <> "/command-center.base")

  // Verify it contains expected view types
  string.contains(content, "type: cards")
  |> should.be_true

  string.contains(content, "type: table")
  |> should.be_true

  // Verify it references correct folders
  string.contains(content, "Claude/bugs")
  |> should.be_true

  string.contains(content, "Claude/ideas")
  |> should.be_true

  let _ = simplifile.delete_all([tmp])
  Nil
}

pub fn regenerate_idea_pipeline_groups_by_status_test() {
  let tmp = "/tmp/alex-memory-dashboard-idea-test"
  let claude_dir = "Claude"
  let dashboard_dir = tmp <> "/" <> claude_dir <> "/_dashboards"

  let _ = simplifile.delete_all([tmp])

  dashboard_writer.regenerate(tmp, claude_dir)
  |> should.be_ok

  let assert Ok(content) =
    simplifile.read(dashboard_dir <> "/idea-pipeline.base")

  // Cards view grouped by status
  string.contains(content, "type: cards")
  |> should.be_true

  string.contains(content, "property: status")
  |> should.be_true

  string.contains(content, "Claude/ideas")
  |> should.be_true

  let _ = simplifile.delete_all([tmp])
  Nil
}

pub fn regenerate_decision_log_table_first_test() {
  let tmp = "/tmp/alex-memory-dashboard-decision-test"
  let claude_dir = "Claude"
  let dashboard_dir = tmp <> "/" <> claude_dir <> "/_dashboards"

  let _ = simplifile.delete_all([tmp])

  dashboard_writer.regenerate(tmp, claude_dir)
  |> should.be_ok

  let assert Ok(content) =
    simplifile.read(dashboard_dir <> "/decision-log.base")

  // Decision log primary view is table (only dashboard with table-first)
  string.contains(content, "Claude/decisions")
  |> should.be_true

  // Table view should appear before cards view
  let assert Ok(table_pos) = string_index_of(content, "type: table")
  let assert Ok(cards_pos) = string_index_of(content, "type: cards")
  should.be_true(table_pos < cards_pos)

  let _ = simplifile.delete_all([tmp])
  Nil
}

/// Helper: find index of substring in string
fn string_index_of(haystack: String, needle: String) -> Result(Int, Nil) {
  case string.split_once(haystack, needle) {
    Ok(#(before, _)) -> Ok(string.length(before))
    Error(_) -> Error(Nil)
  }
}

pub fn regenerate_is_idempotent_test() {
  let tmp = "/tmp/alex-memory-dashboard-idempotent-test"
  let claude_dir = "Claude"
  let dashboard_dir = tmp <> "/" <> claude_dir <> "/_dashboards"

  let _ = simplifile.delete_all([tmp])

  // Run twice
  dashboard_writer.regenerate(tmp, claude_dir)
  |> should.be_ok

  let assert Ok(first) =
    simplifile.read(dashboard_dir <> "/command-center.base")

  dashboard_writer.regenerate(tmp, claude_dir)
  |> should.be_ok

  let assert Ok(second) =
    simplifile.read(dashboard_dir <> "/command-center.base")

  // Content should be identical
  first |> should.equal(second)

  let _ = simplifile.delete_all([tmp])
  Nil
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: FAIL — compile error, `dashboard_writer` module does not exist

- [ ] **Step 3: Write the dashboard_writer module**

Create `src/alex_memory/mcp/dashboard_writer.gleam`:

```gleam
import gleam/string
import simplifile

// ---------- Public API ----------

/// Regenerate all Obsidian Bases dashboard files.
/// Best-effort: writes as many files as possible.
/// Returns Error with the first error message if any write fails.
pub fn regenerate(
  vault_root: String,
  claude_dir: String,
) -> Result(Nil, String) {
  let dashboard_dir = vault_root <> "/" <> claude_dir <> "/_dashboards"

  // Ensure directory exists
  case simplifile.create_directory_all(dashboard_dir) {
    Ok(_) -> Nil
    Error(_) -> Nil
  }

  let results = [
    write_base(dashboard_dir, "command-center.base", command_center(claude_dir)),
    write_base(dashboard_dir, "idea-pipeline.base", idea_pipeline(claude_dir)),
    write_base(dashboard_dir, "bug-board.base", bug_board(claude_dir)),
    write_base(dashboard_dir, "decision-log.base", decision_log(claude_dir)),
    write_base(
      dashboard_dir,
      "active-projects.base",
      active_projects(claude_dir),
    ),
  ]

  // Return first error if any, otherwise Ok
  case find_first_error(results) {
    Ok(err) -> Error(err)
    Error(_) -> Ok(Nil)
  }
}

// ---------- Private helpers ----------

fn write_base(
  dir: String,
  filename: String,
  content: String,
) -> Result(Nil, String) {
  let path = dir <> "/" <> filename
  case simplifile.write(path, content) {
    Ok(_) -> Ok(Nil)
    Error(e) -> Error("Failed to write " <> filename <> ": " <> string.inspect(e))
  }
}

fn find_first_error(
  results: List(Result(Nil, String)),
) -> Result(String, Nil) {
  case results {
    [] -> Error(Nil)
    [Ok(_), ..rest] -> find_first_error(rest)
    [Error(e), ..] -> Ok(e)
  }
}

// ---------- Dashboard content generators ----------

fn command_center(claude_dir: String) -> String {
  "filters:
  and:
    - or:
        - expression: 'file.folder = \""
  <> claude_dir
  <> "/bugs\"'
        - expression: 'file.folder = \""
  <> claude_dir
  <> "/decisions\"'
        - expression: 'file.folder = \""
  <> claude_dir
  <> "/projects\"'
        - expression: 'file.folder = \""
  <> claude_dir
  <> "/ideas\"'
        - expression: 'file.folder = \""
  <> claude_dir
  <> "/brainstorms\"'
        - expression: 'file.folder = \""
  <> claude_dir
  <> "/patterns\"'
        - expression: 'file.folder = \""
  <> claude_dir
  <> "/memory\"'
        - expression: 'file.folder = \""
  <> claude_dir
  <> "/references\"'
        - expression: 'file.folder = \""
  <> claude_dir
  <> "/sessions\"'
    - expression: 'status != \"archived\"'
    - expression: 'status != \"wontfix\"'
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
    name: \"By Type\"
    groupBy:
      property: type
    order:
      - property: updated
        direction: desc
  - type: table
    name: \"All Active\"
    order:
      - property: updated
        direction: desc
"
}

fn idea_pipeline(claude_dir: String) -> String {
  "filters:
  expression: 'file.folder = \""
  <> claude_dir
  <> "/ideas\"'
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
    name: \"Pipeline\"
    groupBy:
      property: status
    order:
      - property: updated
        direction: desc
  - type: table
    name: \"All Ideas\"
    order:
      - property: updated
        direction: desc
"
}

fn bug_board(claude_dir: String) -> String {
  "filters:
  expression: 'file.folder = \""
  <> claude_dir
  <> "/bugs\"'
properties:
  severity:
    width: 80
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
    name: \"By Severity\"
    groupBy:
      property: severity
    filters:
      expression: 'status != \"resolved\"'
    order:
      - property: updated
        direction: desc
  - type: table
    name: \"All Bugs\"
    order:
      - property: severity
        direction: asc
"
}

fn decision_log(claude_dir: String) -> String {
  "filters:
  expression: 'file.folder = \""
  <> claude_dir
  <> "/decisions\"'
properties:
  status:
    width: 100
  tags:
    width: 200
  created:
    width: 120
  author:
    width: 100
views:
  - type: table
    name: \"Recent Decisions\"
    order:
      - property: created
        direction: desc
  - type: cards
    name: \"By Status\"
    groupBy:
      property: status
    order:
      - property: created
        direction: desc
"
}

fn active_projects(claude_dir: String) -> String {
  "filters:
  expression: 'file.folder = \""
  <> claude_dir
  <> "/projects\"'
properties:
  status:
    width: 100
  tags:
    width: 200
  created:
    width: 120
  updated:
    width: 120
  author:
    width: 100
views:
  - type: cards
    name: \"By Status\"
    groupBy:
      property: status
    order:
      - property: updated
        direction: desc
  - type: table
    name: \"All Projects\"
    order:
      - property: updated
        direction: desc
"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `gleam test`
Expected: All tests pass (including the 4 new dashboard tests)

- [ ] **Step 5: Commit**

```bash
git add src/alex_memory/mcp/dashboard_writer.gleam test/alex_memory/mcp/dashboard_writer_test.gleam
git commit -m "feat: add dashboard_writer module for Obsidian Bases generation"
```

---

## Chunk 2: Integration and Config

### Task 2: Add `_dashboards` to config ignore list

**Files:**
- Modify: `config/config.toml:4`

- [ ] **Step 1: Update ignore list**

In `config/config.toml`, change line 4 from:

```toml
ignore = [".obsidian", ".git", ".trash"]
```

to:

```toml
ignore = [".obsidian", ".git", ".trash", "_dashboards"]
```

- [ ] **Step 2: Run tests to verify nothing breaks**

Run: `gleam test`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add config/config.toml
git commit -m "chore: add _dashboards to vault ignore list"
```

---

### Task 3: Hook regenerate into server startup

**Files:**
- Modify: `src/alex_memory.gleam:1-5` (imports), `:75-78` (setup_infrastructure)

- [ ] **Step 1: Add import**

In `src/alex_memory.gleam`, add to the imports at the top:

```gleam
import alex_memory/mcp/dashboard_writer
```

- [ ] **Step 2: Add regenerate call in setup_infrastructure**

In `setup_infrastructure`, after line 75 (`process.send(embedder_subject, embedder.ReindexAll)`) and before line 77 (`io.println_error("Infrastructure setup complete")`), add:

```gleam
  // Generate Obsidian Bases dashboards
  case dashboard_writer.regenerate(cfg.vault.path, cfg.vault.claude_dir) {
    Ok(_) -> io.println_error("Dashboards generated")
    Error(e) -> io.println_error("WARNING: Dashboard generation failed: " <> e)
  }
```

- [ ] **Step 3: Run tests**

Run: `gleam test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add src/alex_memory.gleam
git commit -m "feat: generate dashboards on server startup"
```

---

### Task 4: Hook regenerate into handle_store and handle_update

**Files:**
- Modify: `src/alex_memory/mcp/server.gleam:1-17` (imports), `:295-309` (handle_store), `:533-537` (handle_update)

- [ ] **Step 1: Add import**

In `src/alex_memory/mcp/server.gleam`, add to the imports at the top:

```gleam
import alex_memory/mcp/dashboard_writer
```

- [ ] **Step 2: Add regenerate in handle_store**

In `handle_store`, after the embedder message send (line 304) and before the `text_result` (line 305), add a spawned regeneration. Replace lines 304-308:

```gleam
                )
                text_result(
                  "Memory stored at: "
                  <> vault_path,
                )
```

with:

```gleam
                )
                // Regenerate dashboards in background
                let _ =
                  process.spawn_unlinked(fn() {
                    let _ =
                      dashboard_writer.regenerate(
                        config.vault.path,
                        config.vault.claude_dir,
                      )
                    Nil
                  })
                text_result(
                  "Memory stored at: "
                  <> vault_path,
                )
```

- [ ] **Step 3: Add regenerate in handle_update**

In `handle_update`, replace lines 533-537:

```gleam
          Ok(Nil) ->
            text_result(
              "Memory updated: " <> args.vault_path
              <> "\nThe vault watcher will automatically re-index the updated file.",
            )
```

with:

```gleam
          Ok(Nil) -> {
            // Regenerate dashboards in background
            let _ =
              process.spawn_unlinked(fn() {
                let _ =
                  dashboard_writer.regenerate(
                    config.vault.path,
                    config.vault.claude_dir,
                  )
                Nil
              })
            text_result(
              "Memory updated: " <> args.vault_path
              <> "\nThe vault watcher will automatically re-index the updated file.",
            )
          }
```

- [ ] **Step 4: Run tests**

Run: `gleam test`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add src/alex_memory/mcp/server.gleam
git commit -m "feat: regenerate dashboards after memory store and update"
```

---

### Task 5: Final verification

- [ ] **Step 1: Run full test suite**

Run: `gleam test`
Expected: All tests pass

- [ ] **Step 2: Verify dashboard files can be generated**

Run: `gleam run &` (start server in background), then check:
```bash
ls ~/alex-vault/Claude/_dashboards/
```
Expected: 5 `.base` files listed

- [ ] **Step 3: Inspect a generated file**

```bash
cat ~/alex-vault/Claude/_dashboards/idea-pipeline.base
```
Expected: Valid YAML with `type: cards`, `groupBy: property: status`, and `Claude/ideas` folder filter

- [ ] **Step 4: Final commit if any fixups needed**

```bash
git add -A
git commit -m "fix: address verification findings"
```

(Skip if no changes needed.)
