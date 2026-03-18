import alex_memory/config
import alex_memory/indexer/embedder
import alex_memory/indexer/vault_watcher
import alex_memory/infra/ollama_client
import alex_memory/infra/qdrant_client
import alex_memory/mcp/server as mcp_server
import gleam/erlang/process
import gleam/io

pub fn main() {
  io.println_error("Starting alex_memory...")

  // Load config
  let assert Ok(cfg) = config.load("config/config.toml")
  io.println_error("Config loaded from config/config.toml")

  // Ensure Qdrant collection exists
  let assert Ok(_) =
    qdrant_client.ensure_collection(
      cfg.qdrant.url,
      cfg.qdrant.collection,
      cfg.qdrant.vector_dimension,
    )
  io.println_error("Qdrant collection ready: " <> cfg.qdrant.collection)

  // Ensure Ollama model is available
  let assert Ok(exists) =
    ollama_client.model_exists(cfg.ollama.url, cfg.ollama.model)
  case exists {
    True -> io.println_error("Ollama model ready: " <> cfg.ollama.model)
    False -> {
      io.println_error("Pulling Ollama model: " <> cfg.ollama.model)
      let assert Ok(_) =
        ollama_client.pull_model(cfg.ollama.url, cfg.ollama.model)
      io.println_error("Model pulled successfully")
    }
  }

  // Start embedder
  let assert Ok(embedder_subject) = embedder.start(cfg)
  io.println_error("Embedder started")

  // Start vault watcher
  let assert Ok(_watcher_subject) = vault_watcher.start(cfg, embedder_subject)
  io.println_error("Vault watcher started for: " <> cfg.vault.path)

  // Initial index
  io.println_error("Starting initial vault index...")
  process.send(embedder_subject, embedder.ReindexAll)

  io.println_error("alex_memory is running.")

  // Start MCP server on stdio (blocks until stdin closes)
  mcp_server.start(cfg, embedder_subject)
}
