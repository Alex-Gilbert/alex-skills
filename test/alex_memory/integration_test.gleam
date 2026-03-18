import alex_memory/infra/ollama_client
import alex_memory/infra/qdrant_client
import alex_memory/mcp/vault_writer
import alex_memory/types
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import simplifile

const test_vault = "/tmp/alex_memory_integration_test"

const test_collection = "integration_test"

pub fn full_pipeline_test() {
  // Setup
  let _ = simplifile.create_directory_all(test_vault <> "/Claude/bugs")
  let assert Ok(_) =
    qdrant_client.ensure_collection(
      "http://localhost:6333",
      test_collection,
      768,
    )

  // 1. Write a memory to vault
  let assert Ok(path) =
    vault_writer.write_memory(
      test_vault,
      "Claude",
      types.Bug,
      "Cache Invalidation Bug",
      "The cache does not invalidate when a Cookfile dependency changes.",
      Some(types.Open),
      Some(types.P1),
      ["cook", "cache"],
    )

  // 2. Read and embed it
  let full_path = test_vault <> "/" <> path
  let assert Ok(content) = simplifile.read(full_path)
  let assert Ok(embedding) =
    ollama_client.embed("http://localhost:11434", "nomic-embed-text", content)

  // Verify embedding dimension
  list.length(embedding) |> should.equal(768)

  // 3. Upsert to Qdrant
  let payload =
    json.object([
      #("vault_path", json.string(path)),
      #("type", json.string("bug")),
      #("title", json.string("Cache Invalidation Bug")),
      #(
        "content",
        json.string(
          "The cache does not invalidate when a Cookfile dependency changes.",
        ),
      ),
    ])
  let assert Ok(_) =
    qdrant_client.upsert(
      "http://localhost:6333",
      test_collection,
      "00000000-0000-0000-0000-000000000002",
      embedding,
      payload,
    )

  // 4. Search for it with a related query
  let assert Ok(query_vec) =
    ollama_client.embed(
      "http://localhost:11434",
      "nomic-embed-text",
      "cache invalidation problem",
    )
  let assert Ok(results) =
    qdrant_client.search(
      "http://localhost:6333",
      test_collection,
      query_vec,
      5,
      None,
    )
  list.length(results) |> should.not_equal(0)

  // 5. Verify the top result is our inserted point
  let assert Ok(top) = list.first(results)
  string.contains(top.id, "00000000-0000-0000-0000-000000000002")
  |> should.be_true

  // Cleanup
  let _ =
    qdrant_client.delete_collection("http://localhost:6333", test_collection)
  let _ = simplifile.delete_all([test_vault])
  Nil
}
