import alex_memory/mcp/dashboard_writer
import gleam/string
import gleeunit/should
import simplifile

pub fn regenerate_creates_all_dashboard_files_test() {
  let tmp = "/tmp/alex-memory-dashboard-test"
  let claude_dir = "Claude"
  let dashboard_dir = tmp <> "/" <> claude_dir <> "/_dashboards"
  let _ = simplifile.delete_all([tmp])

  dashboard_writer.regenerate(tmp, claude_dir)
  |> should.be_ok

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

  string.contains(content, "type: cards")
  |> should.be_true

  string.contains(content, "type: table")
  |> should.be_true

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

  string.contains(content, "Claude/decisions")
  |> should.be_true

  // Table view should appear before cards view
  let assert Ok(table_pos) = string_index_of(content, "type: table")
  let assert Ok(cards_pos) = string_index_of(content, "type: cards")
  should.be_true(table_pos < cards_pos)

  let _ = simplifile.delete_all([tmp])
  Nil
}

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

  dashboard_writer.regenerate(tmp, claude_dir)
  |> should.be_ok

  let assert Ok(first) =
    simplifile.read(dashboard_dir <> "/command-center.base")

  dashboard_writer.regenerate(tmp, claude_dir)
  |> should.be_ok

  let assert Ok(second) =
    simplifile.read(dashboard_dir <> "/command-center.base")

  first |> should.equal(second)

  let _ = simplifile.delete_all([tmp])
  Nil
}
