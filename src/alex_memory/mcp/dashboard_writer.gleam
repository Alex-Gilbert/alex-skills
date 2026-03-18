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
    Error(e) ->
      Error("Failed to write " <> filename <> ": " <> string.inspect(e))
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
