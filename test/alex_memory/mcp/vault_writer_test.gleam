import alex_memory/mcp/vault_writer
import alex_memory/types
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import simplifile

pub fn write_memory_test() {
  let tmp_dir = "/tmp/alex_memory_test_vault"
  let _ = simplifile.create_directory_all(tmp_dir <> "/Claude/bugs")

  let result =
    vault_writer.write_memory(
      tmp_dir,
      "Claude",
      types.Bug,
      "Test Bug",
      "This is a test bug.",
      Some(types.Open),
      Some(types.P1),
      ["cook"],
      "",
    )
  result |> should.be_ok

  let assert Ok(path) = result
  string.contains(path, "Claude/bugs/") |> should.be_true
  string.ends_with(path, ".md") |> should.be_true

  // Verify file was written
  let assert Ok(content) = simplifile.read(tmp_dir <> "/" <> path)
  string.contains(content, "type: bug") |> should.be_true
  string.contains(content, "# Test Bug") |> should.be_true

  // Cleanup
  let _ = simplifile.delete_all([tmp_dir])
  Nil
}

pub fn write_memory_with_author_test() {
  let tmp_dir = "/tmp/alex_memory_test_vault_author"
  let _ = simplifile.create_directory_all(tmp_dir)

  let assert Ok(vault_path) =
    vault_writer.write_memory(
      tmp_dir,
      "Claude",
      types.Bug,
      "Author Test",
      "content",
      None,
      None,
      [],
      "alex@example.com",
    )

  let assert Ok(content) = simplifile.read(tmp_dir <> "/" <> vault_path)
  content |> string.contains("author: alex@example.com") |> should.be_true

  let _ = simplifile.delete_all([tmp_dir])
}

pub fn slugify_test() {
  vault_writer.slugify("Scheduler Race Condition")
  |> should.equal("scheduler-race-condition")

  vault_writer.slugify("Fix: the (weird) bug!")
  |> should.equal("fix-the-weird-bug")
}
