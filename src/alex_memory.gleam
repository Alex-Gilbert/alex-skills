import alex_memory/config
import alex_memory/indexer/embedder
import alex_memory/indexer/vault_watcher
import alex_memory/infra/ollama_client
import alex_memory/infra/qdrant_client
import alex_memory/mcp/http_server
import alex_memory/mcp/server as mcp_server
import gleam/erlang/process
import gleam/io

pub fn main() {
  io.println_error("Starting alex_memory...")

  // Load config (fast, local file read)
  let assert Ok(cfg) = config.load("config/config.toml")
  io.println_error("Config loaded")

  // Start embedder immediately (it can queue messages before infra is ready)
  let assert Ok(embedder_subject) = embedder.start(cfg)

  // Build the MCP server (shared by both transports)
  let server = mcp_server.build(cfg, embedder_subject)

  // Start infrastructure setup in a background process
  let _ = process.spawn(fn() { setup_infrastructure(cfg, embedder_subject) })

  // Start HTTP server (fatal on failure — e.g. port conflict)
  let assert Ok(_) = http_server.start(cfg, server)
  io.println_error("MCP server ready")

  // Keep BEAM alive for HTTP clients
  process.sleep_forever()
}

fn setup_infrastructure(
  cfg: config.Config,
  embedder_subject: process.Subject(embedder.Message),
) -> Nil {
  // Ensure Qdrant collection exists
  case
    qdrant_client.ensure_collection(
      cfg.qdrant.url,
      cfg.qdrant.collection,
      cfg.qdrant.vector_dimension,
    )
  {
    Ok(_) ->
      io.println_error("Qdrant collection ready: " <> cfg.qdrant.collection)
    Error(_) -> io.println_error("WARNING: Qdrant not available")
  }

  // Ensure Ollama model is available
  case ollama_client.model_exists(cfg.ollama.url, cfg.ollama.model) {
    Ok(True) ->
      io.println_error("Ollama model ready: " <> cfg.ollama.model)
    Ok(False) -> {
      io.println_error("Pulling Ollama model: " <> cfg.ollama.model)
      case ollama_client.pull_model(cfg.ollama.url, cfg.ollama.model) {
        Ok(_) -> io.println_error("Model pulled successfully")
        Error(_) -> io.println_error("WARNING: Failed to pull model")
      }
    }
    Error(_) -> io.println_error("WARNING: Ollama not available")
  }

  // Start vault watcher
  case vault_watcher.start(cfg, embedder_subject) {
    Ok(_) ->
      io.println_error("Vault watcher started for: " <> cfg.vault.path)
    Error(_) -> io.println_error("WARNING: Vault watcher failed to start")
  }

  // Initial index
  io.println_error("Starting initial vault index...")
  process.send(embedder_subject, embedder.ReindexAll)

  io.println_error("Infrastructure setup complete")
  Nil
}
