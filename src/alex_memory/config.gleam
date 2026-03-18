import gleam/list
import gleam/result
import simplifile
import tom

pub type VaultConfig {
  VaultConfig(path: String, claude_dir: String, ignore: List(String))
}

pub type OllamaConfig {
  OllamaConfig(url: String, model: String)
}

pub type QdrantConfig {
  QdrantConfig(url: String, collection: String, vector_dimension: Int)
}

pub type IndexerConfig {
  IndexerConfig(debounce_ms: Int, chunk_max_tokens: Int)
}

pub type McpConfig {
  McpConfig(transport: String)
}

pub type Config {
  Config(
    vault: VaultConfig,
    ollama: OllamaConfig,
    qdrant: QdrantConfig,
    indexer: IndexerConfig,
    mcp: McpConfig,
  )
}

fn get_string_array(doc, path: List(String)) -> List(String) {
  case tom.get_array(doc, path) {
    Ok(items) -> list.filter_map(items, tom.as_string)
    Error(_) -> []
  }
}

pub fn parse(toml_string: String) -> Result(Config, String) {
  case tom.parse(toml_string) {
    Error(_) -> Error("Failed to parse TOML")
    Ok(doc) -> {
      use vault_path <- result.try(
        tom.get_string(doc, ["vault", "path"])
        |> result.map_error(fn(_) { "Missing vault.path" }),
      )
      use vault_claude_dir <- result.try(
        tom.get_string(doc, ["vault", "claude_dir"])
        |> result.map_error(fn(_) { "Missing vault.claude_dir" }),
      )
      let vault_ignore = get_string_array(doc, ["vault", "ignore"])

      use ollama_url <- result.try(
        tom.get_string(doc, ["ollama", "url"])
        |> result.map_error(fn(_) { "Missing ollama.url" }),
      )
      use ollama_model <- result.try(
        tom.get_string(doc, ["ollama", "model"])
        |> result.map_error(fn(_) { "Missing ollama.model" }),
      )

      use qdrant_url <- result.try(
        tom.get_string(doc, ["qdrant", "url"])
        |> result.map_error(fn(_) { "Missing qdrant.url" }),
      )
      use qdrant_collection <- result.try(
        tom.get_string(doc, ["qdrant", "collection"])
        |> result.map_error(fn(_) { "Missing qdrant.collection" }),
      )
      use qdrant_vector_dimension <- result.try(
        tom.get_int(doc, ["qdrant", "vector_dimension"])
        |> result.map_error(fn(_) { "Missing qdrant.vector_dimension" }),
      )

      use indexer_debounce_ms <- result.try(
        tom.get_int(doc, ["indexer", "debounce_ms"])
        |> result.map_error(fn(_) { "Missing indexer.debounce_ms" }),
      )
      use indexer_chunk_max_tokens <- result.try(
        tom.get_int(doc, ["indexer", "chunk_max_tokens"])
        |> result.map_error(fn(_) { "Missing indexer.chunk_max_tokens" }),
      )

      use mcp_transport <- result.try(
        tom.get_string(doc, ["mcp", "transport"])
        |> result.map_error(fn(_) { "Missing mcp.transport" }),
      )

      Ok(Config(
        vault: VaultConfig(
          path: vault_path,
          claude_dir: vault_claude_dir,
          ignore: vault_ignore,
        ),
        ollama: OllamaConfig(url: ollama_url, model: ollama_model),
        qdrant: QdrantConfig(
          url: qdrant_url,
          collection: qdrant_collection,
          vector_dimension: qdrant_vector_dimension,
        ),
        indexer: IndexerConfig(
          debounce_ms: indexer_debounce_ms,
          chunk_max_tokens: indexer_chunk_max_tokens,
        ),
        mcp: McpConfig(transport: mcp_transport),
      ))
    }
  }
}

pub fn load(path: String) -> Result(Config, String) {
  simplifile.read(path)
  |> result.map_error(fn(_) { "Failed to read config file: " <> path })
  |> result.try(parse)
}
