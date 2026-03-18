import alex_memory/config
import gleeunit/should

pub fn parse_config_test() {
  let toml = "
[vault]
path = \"/home/alex/alex-vault\"
claude_dir = \"Claude\"
ignore = [\".obsidian\", \".git\", \".trash\"]

[ollama]
url = \"http://localhost:11434\"
model = \"nomic-embed-text\"

[qdrant]
url = \"http://localhost:6333\"
collection = \"alex_memory\"
vector_dimension = 768

[indexer]
debounce_ms = 500
chunk_max_tokens = 512

[mcp]
transport = \"stdio\"
http_port = 7890
http_enabled = true
default_author = \"alex\"
"

  let cfg = config.parse(toml)
  cfg |> should.be_ok

  let assert Ok(c) = cfg
  c.vault.path |> should.equal("/home/alex/alex-vault")
  c.vault.claude_dir |> should.equal("Claude")
  c.ollama.url |> should.equal("http://localhost:11434")
  c.ollama.model |> should.equal("nomic-embed-text")
  c.qdrant.url |> should.equal("http://localhost:6333")
  c.qdrant.collection |> should.equal("alex_memory")
  c.qdrant.vector_dimension |> should.equal(768)
  c.indexer.debounce_ms |> should.equal(500)
  c.indexer.chunk_max_tokens |> should.equal(512)
  c.mcp.transport |> should.equal("stdio")
  c.mcp.http_port |> should.equal(7890)
  c.mcp.http_enabled |> should.equal(True)
  c.mcp.default_author |> should.equal("alex")
}

pub fn load_from_file_test() {
  let cfg = config.load("config/config.toml")
  cfg |> should.be_ok
}
