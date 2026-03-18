import alex_memory/infra/qdrant_client
import gleam/json
import gleam/list
import gleam/option
import gleeunit/should

const base_url = "http://localhost:6333"

const test_collection = "test_alex_memory"

pub fn full_lifecycle_test() {
  // 1. Create collection
  let assert Ok(_) =
    qdrant_client.ensure_collection(base_url, test_collection, 1024)

  // 2. Upsert a point with fake 1024-dim vector (all 0.1)
  let vector = list.repeat(0.1, 1024)
  let payload =
    json.object([
      #("vault_path", json.string("test/doc.md")),
      #("type", json.string("bug")),
      #("title", json.string("Test Bug")),
      #("content", json.string("This is a test bug")),
    ])
  let assert Ok(_) =
    qdrant_client.upsert(
      base_url,
      test_collection,
      "00000000-0000-0000-0000-000000000001",
      vector,
      payload,
    )

  // 3. Search for it
  let assert Ok(results) =
    qdrant_client.search(base_url, test_collection, vector, 10, option.None)
  list.length(results) |> should.not_equal(0)

  // 4. Delete by vault_path
  let assert Ok(_) =
    qdrant_client.delete_by_field(
      base_url,
      test_collection,
      "vault_path",
      "test/doc.md",
    )

  // 5. Search again with filter - should be empty
  let filter = qdrant_client.match_filter("vault_path", "test/doc.md")
  let assert Ok(results2) =
    qdrant_client.search(
      base_url,
      test_collection,
      vector,
      10,
      option.Some(filter),
    )
  list.length(results2) |> should.equal(0)

  // 6. Cleanup
  let assert Ok(_) = qdrant_client.delete_collection(base_url, test_collection)
}
