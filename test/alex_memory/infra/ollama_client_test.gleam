import alex_memory/infra/ollama_client
import gleam/list
import gleeunit/should

pub fn health_check_test() {
  let result = ollama_client.health_check("http://localhost:11434")
  result |> should.be_ok
}

pub fn embed_text_test() {
  let result =
    ollama_client.embed(
      "http://localhost:11434",
      "snowflake-arctic-embed:l",
      "The scheduler can deadlock when two recipes share an ingredient",
    )
  result |> should.be_ok

  let assert Ok(embedding) = result
  // snowflake-arctic-embed:l produces 1024-dimensional vectors
  list.length(embedding) |> should.equal(1024)
}

pub fn model_exists_test() {
  let result =
    ollama_client.model_exists("http://localhost:11434", "snowflake-arctic-embed:l")
  result |> should.equal(Ok(True))
}
