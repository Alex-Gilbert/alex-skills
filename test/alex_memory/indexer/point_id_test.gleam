import alex_memory/indexer/point_id
import gleam/list
import gleam/string
import gleeunit/should

pub fn deterministic_id_test() {
  let id1 = point_id.generate("Claude/bugs/test.md", 0)
  let id2 = point_id.generate("Claude/bugs/test.md", 0)
  id1 |> should.equal(id2)
}

pub fn different_chunks_different_ids_test() {
  let id0 = point_id.generate("Claude/bugs/test.md", 0)
  let id1 = point_id.generate("Claude/bugs/test.md", 1)
  should.not_equal(id0, id1)
}

pub fn different_paths_different_ids_test() {
  let id_a = point_id.generate("Claude/bugs/a.md", 0)
  let id_b = point_id.generate("Claude/bugs/b.md", 0)
  should.not_equal(id_a, id_b)
}

pub fn id_is_uuid_format_test() {
  let id = point_id.generate("test.md", 0)
  // UUID format: 8-4-4-4-12 hex chars
  let parts = string.split(id, "-")
  list.length(parts) |> should.equal(5)
}
