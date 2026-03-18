import alex_memory/types
import gleeunit/should

pub fn memory_type_to_string_test() {
  types.memory_type_to_string(types.Bug) |> should.equal("bug")
  types.memory_type_to_string(types.Decision) |> should.equal("decision")
  types.memory_type_to_string(types.Session) |> should.equal("session")
  types.memory_type_to_string(types.Brainstorm) |> should.equal("brainstorm")
}

pub fn memory_type_from_string_test() {
  types.memory_type_from_string("bug") |> should.equal(Ok(types.Bug))
  types.memory_type_from_string("decision") |> should.equal(Ok(types.Decision))
  types.memory_type_from_string("invalid") |> should.be_error
}

pub fn status_to_string_test() {
  types.status_to_string(types.Open) |> should.equal("open")
  types.status_to_string(types.Resolved) |> should.equal("resolved")
}
