# Alex Memory Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a GPU-accelerated semantic memory system for Claude Code — Gleam/OTP app with Qdrant vector search, Ollama embeddings, Obsidian vault sync, and a forked superpowers skill suite with memory-aware workflows.

**Architecture:** Single Gleam OTP application with three isolated supervision scopes (InfraScope, IndexerScope, MCPScope). Qdrant + Ollama run as Docker services. Memories are stored as .md files in an Obsidian vault (source of truth) and indexed in Qdrant for semantic search. A forked superpowers plugin provides skills and hooks for Claude Code integration.

**Tech Stack:** Gleam 1.12+ on OTP 27+, mcp_toolkit (MCP server), mist (HTTP), gleam_otp (actors/supervision), tom (TOML config), simplifile (filesystem), Docker (Qdrant + Ollama), Obsidian vault

**Spec:** `docs/superpowers/specs/2026-03-17-alex-memory-design.md`

---

## File Structure

### Gleam Application

| File | Responsibility |
|------|---------------|
| `src/alex_memory.gleam` | Application entry, root supervisor |
| `src/alex_memory/config.gleam` | TOML config parsing + types |
| `src/alex_memory/types.gleam` | Shared types: Memory, Chunk, MemoryType, Metadata, PointId |
| `src/alex_memory/infra/ollama_client.gleam` | OTP actor wrapping Ollama HTTP API (health, pull, embed) |
| `src/alex_memory/infra/qdrant_client.gleam` | OTP actor wrapping Qdrant HTTP API (collections, upsert, search, delete) |
| `src/alex_memory/indexer/frontmatter.gleam` | Parse YAML frontmatter from markdown files |
| `src/alex_memory/indexer/chunker.gleam` | Split markdown by h2/h3 headings into chunks |
| `src/alex_memory/indexer/embedder.gleam` | OTP actor: receives file paths, parses, chunks, embeds, upserts |
| `src/alex_memory/indexer/vault_watcher.gleam` | OTP actor: watches vault via Erlang :fs, debounces, sends to embedder |
| `src/alex_memory/indexer/point_id.gleam` | Deterministic UUID generation from vault_path + chunk_index |
| `src/alex_memory/mcp/server.gleam` | MCP server: tool definitions and handlers |
| `src/alex_memory/mcp/vault_writer.gleam` | Write .md files to vault with frontmatter |
| `src/alex_memory/ffi/fs.gleam` | Gleam FFI bindings for Erlang :fs module |
| `src/alex_memory/ffi/crypto.gleam` | Gleam FFI bindings for Erlang :crypto (sha256) |

### Tests

| File | Tests |
|------|-------|
| `test/alex_memory/config_test.gleam` | Config parsing from TOML |
| `test/alex_memory/types_test.gleam` | Type constructors, serialization |
| `test/alex_memory/indexer/frontmatter_test.gleam` | Frontmatter parsing edge cases |
| `test/alex_memory/indexer/chunker_test.gleam` | Markdown chunking logic |
| `test/alex_memory/indexer/point_id_test.gleam` | Deterministic ID generation |
| `test/alex_memory/infra/ollama_client_test.gleam` | Integration tests (requires running Ollama) |
| `test/alex_memory/infra/qdrant_client_test.gleam` | Integration tests (requires running Qdrant) |
| `test/alex_memory/mcp/vault_writer_test.gleam` | File writing + frontmatter serialization |
| `test/alex_memory/mcp/server_test.gleam` | MCP tool handler unit tests |

### Infrastructure & Config

| File | Responsibility |
|------|---------------|
| `docker-compose.yml` | Qdrant + Ollama services |
| `config/config.toml` | Runtime config (vault path, model, URLs) |
| `gleam.toml` | Gleam project dependencies |

### Superpowers Fork (Claude Code Plugin)

| File | Responsibility |
|------|---------------|
| `.claude-plugin/plugin.json` | Plugin metadata |
| `package.json` | Node package metadata (for plugin system) |
| `hooks/hooks.json` | Hook definitions (SessionStart) |
| `hooks/run-hook.cmd` | Cross-platform hook runner |
| `hooks/session-start` | SessionStart script — injects memory context |
| `skills/using-superpowers/SKILL.md` | Modified — adds memory skills to registry |
| `skills/brainstorming/SKILL.md` | Modified — memory-aware brainstorming |
| `skills/systematic-debugging/SKILL.md` | Modified — memory-aware debugging |
| `skills/writing-plans/SKILL.md` | Modified — memory-aware planning |
| `skills/executing-plans/SKILL.md` | Modified — stores outcomes to memory |
| `skills/remember/SKILL.md` | NEW — explicit memory store |
| `skills/recall/SKILL.md` | NEW — explicit semantic search |
| `skills/bugs/SKILL.md` | NEW — bug management |
| `skills/status/SKILL.md` | NEW — project progress |
| `skills/session-end/SKILL.md` | NEW — manual session summary |
| `commands/remember.md` | NEW — command file for /remember |
| `commands/recall.md` | NEW — command file for /recall |
| `commands/bugs.md` | NEW — command file for /bugs |
| `commands/status.md` | NEW — command file for /status |
| `commands/session-end.md` | NEW — command file for /session-end |

---

## Chunk 1: Project Scaffolding & Infrastructure

### Task 1: Initialize Gleam project

**Files:**
- Create: `gleam.toml`
- Create: `src/alex_memory.gleam`
- Create: `test/alex_memory_test.gleam`

- [ ] **Step 1: Initialize Gleam project in alex-memory repo**

Run:
```bash
cd ~/dev/alex-memory
gleam new alex_memory --skip-git .
```

If `gleam new` doesn't support `.` as target, init in a temp dir and move files:
```bash
cd /tmp && gleam new alex_memory && cp -r alex_memory/gleam.toml alex_memory/src alex_memory/test ~/dev/alex-memory/ && rm -rf /tmp/alex_memory
```

Expected: `gleam.toml`, `src/alex_memory.gleam`, `test/alex_memory_test.gleam` created

- [ ] **Step 2: Verify project compiles**

Run: `cd ~/dev/alex-memory && gleam build`
Expected: Build succeeds with no errors

- [ ] **Step 3: Verify tests pass**

Run: `cd ~/dev/alex-memory && gleam test`
Expected: 1 test passes (default hello world test)

- [ ] **Step 4: Commit**

```bash
cd ~/dev/alex-memory
git add gleam.toml src/ test/
git commit -m "feat: initialize Gleam project"
```

### Task 2: Add dependencies

**Files:**
- Modify: `gleam.toml`

- [ ] **Step 1: Add all required dependencies**

Run:
```bash
cd ~/dev/alex-memory
gleam add gleam_otp gleam_erlang gleam_http gleam_httpc gleam_json mcp_toolkit mist simplifile tom gleeunit gleam_crypto gleam_bit_array
```

- [ ] **Step 2: Verify build still works**

Run: `cd ~/dev/alex-memory && gleam build`
Expected: All dependencies resolve and build succeeds

- [ ] **Step 3: Commit**

```bash
cd ~/dev/alex-memory
git add gleam.toml manifest.toml
git commit -m "feat: add project dependencies"
```

### Task 3: Docker Compose for Qdrant + Ollama

**Files:**
- Create: `docker-compose.yml`

- [ ] **Step 1: Write docker-compose.yml**

```yaml
services:
  qdrant:
    image: qdrant/qdrant:latest
    ports:
      - "6333:6333"
      - "6334:6334"
    volumes:
      - qdrant_data:/qdrant/storage
    restart: unless-stopped

  ollama:
    image: ollama/ollama:latest
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    restart: unless-stopped

volumes:
  qdrant_data:
  ollama_data:
```

- [ ] **Step 2: Start services and verify**

Run:
```bash
cd ~/dev/alex-memory
docker compose up -d
```

Verify Qdrant:
```bash
curl -s http://localhost:6333/collections | python3 -m json.tool
```
Expected: `{"result":{"collections":[]},"status":"ok","time":...}`

Verify Ollama:
```bash
curl -s http://localhost:11434/api/tags | python3 -m json.tool
```
Expected: `{"models":[]}` (empty, no models pulled yet)

- [ ] **Step 3: Pull embedding model**

Run:
```bash
docker compose exec ollama ollama pull nomic-embed-text
```
Expected: Model downloads successfully

- [ ] **Step 4: Verify embedding works**

Run:
```bash
curl -s http://localhost:11434/api/embed -d '{"model":"nomic-embed-text","input":"test embedding"}' | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'dimensions: {len(d[\"embeddings\"][0])}')"
```
Expected: `dimensions: 768`

- [ ] **Step 5: Commit**

```bash
cd ~/dev/alex-memory
git add docker-compose.yml
git commit -m "infra: add Docker Compose for Qdrant and Ollama"
```

### Task 4: Config module

**Files:**
- Create: `config/config.toml`
- Create: `src/alex_memory/config.gleam`
- Create: `test/alex_memory/config_test.gleam`

- [ ] **Step 1: Write the config.toml**

```toml
[vault]
path = "/home/alex/alex-vault"
claude_dir = "Claude"
ignore = [".obsidian", ".git", ".trash"]

[ollama]
url = "http://localhost:11434"
model = "nomic-embed-text"

[qdrant]
url = "http://localhost:6333"
collection = "alex_memory"
vector_dimension = 768

[indexer]
debounce_ms = 500
chunk_max_tokens = 512

[mcp]
transport = "stdio"
```

- [ ] **Step 2: Write failing test for config parsing**

```gleam
// test/alex_memory/config_test.gleam
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
}

pub fn load_from_file_test() {
  let cfg = config.load("config/config.toml")
  cfg |> should.be_ok
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd ~/dev/alex-memory && gleam test`
Expected: Compilation error — `config` module doesn't exist

- [ ] **Step 4: Implement config module**

```gleam
// src/alex_memory/config.gleam
import gleam/result
import gleam/dynamic
import simplifile
import tom

pub type Config {
  Config(
    vault: VaultConfig,
    ollama: OllamaConfig,
    qdrant: QdrantConfig,
    indexer: IndexerConfig,
    mcp: McpConfig,
  )
}

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

pub fn parse(toml_string: String) -> Result(Config, String) {
  use doc <- result.try(
    tom.parse(toml_string)
    |> result.map_error(fn(_) { "Failed to parse TOML" }),
  )

  use vault_path <- result.try(
    tom.get_string(doc, ["vault", "path"])
    |> result.map_error(fn(_) { "Missing vault.path" }),
  )
  use claude_dir <- result.try(
    tom.get_string(doc, ["vault", "claude_dir"])
    |> result.map_error(fn(_) { "Missing vault.claude_dir" }),
  )
  use ignore <- result.try(
    get_string_array(doc, ["vault", "ignore"]),
  )

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
  use qdrant_dimension <- result.try(
    tom.get_int(doc, ["qdrant", "vector_dimension"])
    |> result.map_error(fn(_) { "Missing qdrant.vector_dimension" }),
  )

  use debounce_ms <- result.try(
    tom.get_int(doc, ["indexer", "debounce_ms"])
    |> result.map_error(fn(_) { "Missing indexer.debounce_ms" }),
  )
  use chunk_max_tokens <- result.try(
    tom.get_int(doc, ["indexer", "chunk_max_tokens"])
    |> result.map_error(fn(_) { "Missing indexer.chunk_max_tokens" }),
  )

  use transport <- result.try(
    tom.get_string(doc, ["mcp", "transport"])
    |> result.map_error(fn(_) { "Missing mcp.transport" }),
  )

  Ok(Config(
    vault: VaultConfig(
      path: vault_path,
      claude_dir: claude_dir,
      ignore: ignore,
    ),
    ollama: OllamaConfig(url: ollama_url, model: ollama_model),
    qdrant: QdrantConfig(
      url: qdrant_url,
      collection: qdrant_collection,
      vector_dimension: qdrant_dimension,
    ),
    indexer: IndexerConfig(
      debounce_ms: debounce_ms,
      chunk_max_tokens: chunk_max_tokens,
    ),
    mcp: McpConfig(transport: transport),
  ))
}

pub fn load(path: String) -> Result(Config, String) {
  use content <- result.try(
    simplifile.read(path)
    |> result.map_error(fn(_) { "Failed to read config file: " <> path }),
  )
  parse(content)
}

fn get_string_array(
  doc: tom.Toml,
  path: List(String),
) -> Result(List(String), String) {
  tom.get_array(doc, path)
  |> result.map_error(fn(_) { "Missing array at " <> string.join(path, ".") })
  |> result.try(fn(arr) {
    list.try_map(arr, fn(val) {
      case val {
        tom.String(s) -> Ok(s)
        _ -> Error("Expected string in array")
      }
    })
  })
}
```

Note: The `get_string_array` helper may need adjustment based on the exact `tom` API. Check `tom.get_array` return type and adapt accordingly. The `tom` library may return `List(Tom)` or similar — consult `hexdocs.pm/tom` during implementation.

- [ ] **Step 5: Run tests**

Run: `cd ~/dev/alex-memory && gleam test`
Expected: Both config tests pass

- [ ] **Step 6: Commit**

```bash
cd ~/dev/alex-memory
git add config/ src/alex_memory/config.gleam test/alex_memory/config_test.gleam
git commit -m "feat: config module with TOML parsing"
```

### Task 5: Shared types module

**Files:**
- Create: `src/alex_memory/types.gleam`
- Create: `test/alex_memory/types_test.gleam`

- [ ] **Step 1: Write failing test for types**

```gleam
// test/alex_memory/types_test.gleam
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/dev/alex-memory && gleam test`
Expected: Compilation error — `types` module doesn't exist

- [ ] **Step 3: Implement types module**

```gleam
// src/alex_memory/types.gleam
import gleam/option.{type Option}

pub type MemoryType {
  Bug
  Decision
  Project
  Memory
  Pattern
  Session
  Reference
  Brainstorm
}

pub type Status {
  Open
  Resolved
  Active
  Archived
  Wontfix
}

pub type Severity {
  P0
  P1
  P2
  P3
}

pub type Source {
  Conversation
  Vault
  Manual
}

pub type Metadata {
  Metadata(
    memory_type: MemoryType,
    status: Option(Status),
    severity: Option(Severity),
    tags: List(String),
    created: String,
    updated: String,
    source: Source,
    vault_path: String,
    schema_version: Int,
  )
}

pub type Chunk {
  Chunk(
    title: String,
    content: String,
    metadata: Metadata,
    chunk_index: Int,
    chunk_total: Int,
  )
}

pub type MemoryDocument {
  MemoryDocument(
    title: String,
    content: String,
    metadata: Metadata,
  )
}

pub type SearchResult {
  SearchResult(
    score: Float,
    title: String,
    content: String,
    metadata: Metadata,
  )
}

pub fn memory_type_to_string(t: MemoryType) -> String {
  case t {
    Bug -> "bug"
    Decision -> "decision"
    Project -> "project"
    Memory -> "memory"
    Pattern -> "pattern"
    Session -> "session"
    Reference -> "reference"
    Brainstorm -> "brainstorm"
  }
}

pub fn memory_type_from_string(s: String) -> Result(MemoryType, String) {
  case s {
    "bug" -> Ok(Bug)
    "decision" -> Ok(Decision)
    "project" -> Ok(Project)
    "memory" -> Ok(Memory)
    "pattern" -> Ok(Pattern)
    "session" -> Ok(Session)
    "reference" -> Ok(Reference)
    "brainstorm" -> Ok(Brainstorm)
    _ -> Error("Unknown memory type: " <> s)
  }
}

pub fn status_to_string(s: Status) -> String {
  case s {
    Open -> "open"
    Resolved -> "resolved"
    Active -> "active"
    Archived -> "archived"
    Wontfix -> "wontfix"
  }
}

pub fn status_from_string(s: String) -> Result(Status, String) {
  case s {
    "open" -> Ok(Open)
    "resolved" -> Ok(Resolved)
    "active" -> Ok(Active)
    "archived" -> Ok(Archived)
    "wontfix" -> Ok(Wontfix)
    _ -> Error("Unknown status: " <> s)
  }
}

pub fn severity_to_string(s: Severity) -> String {
  case s {
    P0 -> "p0"
    P1 -> "p1"
    P2 -> "p2"
    P3 -> "p3"
  }
}

pub fn source_to_string(s: Source) -> String {
  case s {
    Conversation -> "conversation"
    Vault -> "vault"
    Manual -> "manual"
  }
}

pub fn source_from_string(s: String) -> Result(Source, String) {
  case s {
    "conversation" -> Ok(Conversation)
    "vault" -> Ok(Vault)
    "manual" -> Ok(Manual)
    _ -> Error("Unknown source: " <> s)
  }
}

pub fn memory_type_to_dir(t: MemoryType) -> String {
  case t {
    Bug -> "bugs"
    Decision -> "decisions"
    Project -> "projects"
    Memory -> "memory"
    Pattern -> "patterns"
    Session -> "sessions"
    Reference -> "references"
    Brainstorm -> "brainstorms"
  }
}
```

- [ ] **Step 4: Run tests**

Run: `cd ~/dev/alex-memory && gleam test`
Expected: All type tests pass

- [ ] **Step 5: Commit**

```bash
cd ~/dev/alex-memory
git add src/alex_memory/types.gleam test/alex_memory/types_test.gleam
git commit -m "feat: shared types module with memory types and metadata"
```

---

## Chunk 2: Infrastructure Clients

### Task 6: Point ID generation

**Files:**
- Create: `src/alex_memory/indexer/point_id.gleam`
- Create: `src/alex_memory/ffi/crypto.gleam`
- Create: `src/alex_memory_ffi.erl` (Erlang FFI for :crypto)
- Create: `test/alex_memory/indexer/point_id_test.gleam`

- [ ] **Step 1: Write failing test for deterministic point IDs**

```gleam
// test/alex_memory/indexer/point_id_test.gleam
import alex_memory/indexer/point_id
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/dev/alex-memory && gleam test`
Expected: Compilation error

- [ ] **Step 3: Implement point_id module**

The module uses Erlang's `:crypto.hash(:sha256, data)` via FFI to generate deterministic UUIDs from `vault_path:chunk_index`.

```gleam
// src/alex_memory/indexer/point_id.gleam
import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/string

/// Generate a deterministic UUID from vault_path and chunk_index.
/// Uses SHA-256 hash truncated to UUID v5 format.
pub fn generate(vault_path: String, chunk_index: Int) -> String {
  let input = vault_path <> ":" <> int.to_string(chunk_index)
  let hash = crypto.hash(crypto.Sha256, bit_array.from_string(input))
  hash_to_uuid(hash)
}

fn hash_to_uuid(hash: BitArray) -> String {
  // Take first 16 bytes of SHA-256, format as UUID
  let assert <<a:bytes-size(4), b:bytes-size(2), c:bytes-size(2), d:bytes-size(2), e:bytes-size(6), _:bytes>> = hash
  let hex_a = bit_array.base16_encode(a) |> string.lowercase
  let hex_b = bit_array.base16_encode(b) |> string.lowercase
  let hex_c = bit_array.base16_encode(c) |> string.lowercase
  let hex_d = bit_array.base16_encode(d) |> string.lowercase
  let hex_e = bit_array.base16_encode(e) |> string.lowercase
  hex_a <> "-" <> hex_b <> "-" <> hex_c <> "-" <> hex_d <> "-" <> hex_e
}
```

Note: The exact `bit_array` and `crypto` APIs may need adjustment. Gleam's `gleam_crypto` package provides `crypto.hash`. Check `hexdocs.pm/gleam_crypto` for the exact function signatures. The bit pattern matching syntax may vary — adapt during implementation.

- [ ] **Step 4: Run tests**

Run: `cd ~/dev/alex-memory && gleam test`
Expected: All point_id tests pass

- [ ] **Step 5: Commit**

```bash
cd ~/dev/alex-memory
git add src/alex_memory/indexer/point_id.gleam test/alex_memory/indexer/point_id_test.gleam
git commit -m "feat: deterministic point ID generation for Qdrant"
```

### Task 7: Ollama HTTP client

**Files:**
- Create: `src/alex_memory/infra/ollama_client.gleam`
- Create: `test/alex_memory/infra/ollama_client_test.gleam`

- [ ] **Step 1: Write failing integration test**

These tests require Ollama running (`docker compose up -d`).

```gleam
// test/alex_memory/infra/ollama_client_test.gleam
import alex_memory/infra/ollama_client
import gleeunit/should

pub fn health_check_test() {
  let result = ollama_client.health_check("http://localhost:11434")
  result |> should.be_ok
}

pub fn embed_text_test() {
  let result = ollama_client.embed(
    "http://localhost:11434",
    "nomic-embed-text",
    "The scheduler can deadlock when two recipes share an ingredient",
  )
  result |> should.be_ok

  let assert Ok(embedding) = result
  // nomic-embed-text produces 768-dimensional vectors
  list.length(embedding) |> should.equal(768)
}

pub fn model_exists_test() {
  let result = ollama_client.model_exists(
    "http://localhost:11434",
    "nomic-embed-text",
  )
  result |> should.equal(Ok(True))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/dev/alex-memory && gleam test`
Expected: Compilation error

- [ ] **Step 3: Implement Ollama HTTP client (stateless functions first)**

```gleam
// src/alex_memory/infra/ollama_client.gleam
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/json
import gleam/dynamic
import gleam/result
import gleam/list
import gleam/option.{type Option, None, Some}

pub type OllamaError {
  ConnectionError(String)
  ApiError(String)
  ModelNotFound(String)
}

/// Check if Ollama is reachable
pub fn health_check(base_url: String) -> Result(Nil, OllamaError) {
  let url = base_url <> "/api/tags"
  use req <- result.try(
    request.to(url)
    |> result.map_error(fn(_) { ConnectionError("Invalid URL: " <> url) }),
  )
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(_) { ConnectionError("Cannot reach Ollama at " <> base_url) }),
  )
  case resp.status {
    200 -> Ok(Nil)
    status -> Error(ApiError("Unexpected status: " <> int.to_string(status)))
  }
}

/// Check if a model is available locally
pub fn model_exists(base_url: String, model: String) -> Result(Bool, OllamaError) {
  let url = base_url <> "/api/tags"
  use req <- result.try(
    request.to(url)
    |> result.map_error(fn(_) { ConnectionError("Invalid URL") }),
  )
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(_) { ConnectionError("Cannot reach Ollama") }),
  )
  use models <- result.try(
    parse_model_list(resp.body)
    |> result.map_error(fn(_) { ApiError("Failed to parse model list") }),
  )
  Ok(list.any(models, fn(m) { string.contains(m, model) }))
}

/// Pull a model (blocking — may take minutes on first run)
pub fn pull_model(base_url: String, model: String) -> Result(Nil, OllamaError) {
  let url = base_url <> "/api/pull"
  let body = json.object([#("name", json.string(model))]) |> json.to_string
  use req <- result.try(
    request.to(url)
    |> result.map(request.set_body(_, body))
    |> result.map(request.set_method(_, http.Post))
    |> result.map(request.set_header(_, "content-type", "application/json"))
    |> result.map_error(fn(_) { ConnectionError("Invalid URL") }),
  )
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(_) { ConnectionError("Cannot reach Ollama") }),
  )
  case resp.status {
    200 -> Ok(Nil)
    _ -> Error(ApiError("Failed to pull model: " <> model))
  }
}

/// Generate embeddings for text
pub fn embed(
  base_url: String,
  model: String,
  text: String,
) -> Result(List(Float), OllamaError) {
  let url = base_url <> "/api/embed"
  let body =
    json.object([
      #("model", json.string(model)),
      #("input", json.string(text)),
    ])
    |> json.to_string
  use req <- result.try(
    request.to(url)
    |> result.map(request.set_body(_, body))
    |> result.map(request.set_method(_, http.Post))
    |> result.map(request.set_header(_, "content-type", "application/json"))
    |> result.map_error(fn(_) { ConnectionError("Invalid URL") }),
  )
  use resp <- result.try(
    httpc.send(req)
    |> result.map_error(fn(_) { ConnectionError("Cannot reach Ollama") }),
  )
  use embedding <- result.try(
    parse_embedding(resp.body)
    |> result.map_error(fn(_) { ApiError("Failed to parse embedding response") }),
  )
  Ok(embedding)
}

fn parse_embedding(body: String) -> Result(List(Float), json.DecodeError) {
  // Ollama returns {"embeddings": [[0.1, 0.2, ...]]}
  let decoder =
    dynamic.field("embeddings", dynamic.list(dynamic.list(dynamic.float)))
  use parsed <- result.try(json.decode(body, decoder))
  case parsed {
    [first, ..] -> Ok(first)
    [] -> Error(json.UnexpectedFormat([]))
  }
}

fn parse_model_list(body: String) -> Result(List(String), Nil) {
  let decoder =
    dynamic.field(
      "models",
      dynamic.list(dynamic.field("name", dynamic.string)),
    )
  json.decode(body, decoder)
  |> result.map_error(fn(_) { Nil })
}
```

Note: The exact `gleam_httpc` API (how to set method, body, headers on a request) should be verified against `hexdocs.pm/gleam_httpc`. The `request` module from `gleam_http` provides `set_body`, `set_method`, `set_header`. Adapt as needed.

- [ ] **Step 4: Run integration tests**

Run: `cd ~/dev/alex-memory && gleam test`
Expected: All ollama_client tests pass (Docker services must be running)

- [ ] **Step 5: Commit**

```bash
cd ~/dev/alex-memory
git add src/alex_memory/infra/ollama_client.gleam test/alex_memory/infra/ollama_client_test.gleam
git commit -m "feat: Ollama HTTP client with embed, health check, model pull"
```

### Task 8: Qdrant HTTP client

**Files:**
- Create: `src/alex_memory/infra/qdrant_client.gleam`
- Create: `test/alex_memory/infra/qdrant_client_test.gleam`

- [ ] **Step 1: Write failing integration tests**

```gleam
// test/alex_memory/infra/qdrant_client_test.gleam
import alex_memory/infra/qdrant_client
import gleeunit/should

const test_collection = "test_alex_memory"

pub fn create_collection_test() {
  let result = qdrant_client.ensure_collection(
    "http://localhost:6333",
    test_collection,
    768,
  )
  result |> should.be_ok
}

pub fn upsert_and_search_test() {
  // Setup: ensure collection exists
  let assert Ok(_) = qdrant_client.ensure_collection(
    "http://localhost:6333",
    test_collection,
    768,
  )

  // Create a fake 768-dim vector (all 0.1)
  let vector = list.repeat(0.1, 768)
  let payload =
    json.object([
      #("vault_path", json.string("test/doc.md")),
      #("type", json.string("bug")),
      #("title", json.string("Test Bug")),
      #("content", json.string("This is a test bug")),
    ])

  let assert Ok(_) = qdrant_client.upsert(
    "http://localhost:6333",
    test_collection,
    "test-uuid-1234",
    vector,
    payload,
  )

  // Search for it
  let assert Ok(results) = qdrant_client.search(
    "http://localhost:6333",
    test_collection,
    vector,
    10,
    option.None,
  )

  list.length(results) |> should.not_equal(0)
}

pub fn delete_by_vault_path_test() {
  let assert Ok(_) = qdrant_client.delete_by_field(
    "http://localhost:6333",
    test_collection,
    "vault_path",
    "test/doc.md",
  )

  // Verify deletion — search should return empty
  let vector = list.repeat(0.1, 768)
  let assert Ok(results) = qdrant_client.search(
    "http://localhost:6333",
    test_collection,
    vector,
    10,
    option.Some(json.object([
      #("must", json.array([
        json.object([
          #("key", json.string("vault_path")),
          #("match", json.object([
            #("value", json.string("test/doc.md")),
          ])),
        ]),
      ], fn(x) { x })),
    ])),
  )
  list.length(results) |> should.equal(0)
}

pub fn cleanup_test() {
  // Delete the test collection
  let _ = qdrant_client.delete_collection(
    "http://localhost:6333",
    test_collection,
  )
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/dev/alex-memory && gleam test`
Expected: Compilation error

- [ ] **Step 3: Implement Qdrant HTTP client**

```gleam
// src/alex_memory/infra/qdrant_client.gleam
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/json.{type Json}
import gleam/dynamic
import gleam/result
import gleam/list
import gleam/int
import gleam/float
import gleam/option.{type Option, None, Some}

pub type QdrantError {
  ConnectionError(String)
  ApiError(Int, String)
}

pub type SearchHit {
  SearchHit(
    id: String,
    score: Float,
    payload: dynamic.Dynamic,
  )
}

/// Create collection if it doesn't exist
pub fn ensure_collection(
  base_url: String,
  collection: String,
  vector_size: Int,
) -> Result(Nil, QdrantError) {
  // Check if exists
  let url = base_url <> "/collections/" <> collection
  use req <- result.try(make_request(url, http.Get, ""))
  use resp <- result.try(send(req))
  case resp.status {
    200 -> Ok(Nil)
    404 -> {
      // Create it
      let body =
        json.object([
          #("vectors", json.object([
            #("size", json.int(vector_size)),
            #("distance", json.string("Cosine")),
          ])),
        ])
        |> json.to_string
      let url = base_url <> "/collections/" <> collection
      use req <- result.try(make_request(url, http.Put, body))
      use resp <- result.try(send(req))
      case resp.status {
        200 -> Ok(Nil)
        s -> Error(ApiError(s, "Failed to create collection"))
      }
    }
    s -> Error(ApiError(s, "Failed to check collection"))
  }
}

/// Delete a collection
pub fn delete_collection(
  base_url: String,
  collection: String,
) -> Result(Nil, QdrantError) {
  let url = base_url <> "/collections/" <> collection
  use req <- result.try(make_request(url, http.Delete, ""))
  use resp <- result.try(send(req))
  case resp.status {
    200 -> Ok(Nil)
    s -> Error(ApiError(s, "Failed to delete collection"))
  }
}

/// Upsert a single point
pub fn upsert(
  base_url: String,
  collection: String,
  id: String,
  vector: List(Float),
  payload: Json,
) -> Result(Nil, QdrantError) {
  let url = base_url <> "/collections/" <> collection <> "/points"
  let body =
    json.object([
      #("points", json.array([
        json.object([
          #("id", json.string(id)),
          #("vector", json.array(vector, json.float)),
          #("payload", payload),
        ]),
      ], fn(x) { x })),
    ])
    |> json.to_string
  use req <- result.try(make_request(url, http.Put, body))
  use resp <- result.try(send(req))
  case resp.status {
    200 -> Ok(Nil)
    s -> Error(ApiError(s, "Failed to upsert point"))
  }
}

/// Search for nearest neighbors
pub fn search(
  base_url: String,
  collection: String,
  vector: List(Float),
  limit: Int,
  filter: Option(Json),
) -> Result(List(SearchHit), QdrantError) {
  let url = base_url <> "/collections/" <> collection <> "/points/search"
  let base_fields = [
    #("vector", json.array(vector, json.float)),
    #("limit", json.int(limit)),
    #("with_payload", json.bool(True)),
  ]
  let fields = case filter {
    Some(f) -> list.append(base_fields, [#("filter", f)])
    None -> base_fields
  }
  let body = json.object(fields) |> json.to_string
  use req <- result.try(make_request(url, http.Post, body))
  use resp <- result.try(send(req))
  case resp.status {
    200 -> parse_search_results(resp.body)
    s -> Error(ApiError(s, "Search failed"))
  }
}

/// Delete all points matching a field value
pub fn delete_by_field(
  base_url: String,
  collection: String,
  field: String,
  value: String,
) -> Result(Nil, QdrantError) {
  let url = base_url <> "/collections/" <> collection <> "/points/delete"
  let body =
    json.object([
      #("filter", json.object([
        #("must", json.preprocessed_array([
          json.object([
            #("key", json.string(field)),
            #("match", json.object([
              #("value", json.string(value)),
            ])),
          ]),
        ])),
      ])),
    ])
    |> json.to_string
  use req <- result.try(make_request(url, http.Post, body))
  use resp <- result.try(send(req))
  case resp.status {
    200 -> Ok(Nil)
    s -> Error(ApiError(s, "Failed to delete by field"))
  }
}

/// List all points matching a filter (scroll API)
pub fn scroll(
  base_url: String,
  collection: String,
  filter: Option(Json),
  limit: Int,
) -> Result(List(SearchHit), QdrantError) {
  let url = base_url <> "/collections/" <> collection <> "/points/scroll"
  let base_fields = [
    #("limit", json.int(limit)),
    #("with_payload", json.bool(True)),
  ]
  let fields = case filter {
    Some(f) -> list.append(base_fields, [#("filter", f)])
    None -> base_fields
  }
  let body = json.object(fields) |> json.to_string
  use req <- result.try(make_request(url, http.Post, body))
  use resp <- result.try(send(req))
  case resp.status {
    200 -> parse_scroll_results(resp.body)
    s -> Error(ApiError(s, "Scroll failed"))
  }
}

// --- Internal helpers ---

fn make_request(
  url: String,
  method: http.Method,
  body: String,
) -> Result(request.Request(String), QdrantError) {
  request.to(url)
  |> result.map(request.set_method(_, method))
  |> result.map(request.set_body(_, body))
  |> result.map(request.set_header(_, "content-type", "application/json"))
  |> result.map_error(fn(_) { ConnectionError("Invalid URL: " <> url) })
}

fn send(
  req: request.Request(String),
) -> Result(response.Response(String), QdrantError) {
  httpc.send(req)
  |> result.map_error(fn(_) { ConnectionError("Failed to connect to Qdrant") })
}

fn parse_search_results(body: String) -> Result(List(SearchHit), QdrantError) {
  // Qdrant returns {"result": [{"id": ..., "score": ..., "payload": ...}]}
  let decoder =
    dynamic.field(
      "result",
      dynamic.list(dynamic.decode3(
        SearchHit,
        dynamic.field("id", dynamic.string),
        dynamic.field("score", dynamic.float),
        dynamic.field("payload", dynamic.dynamic),
      )),
    )
  json.decode(body, decoder)
  |> result.map_error(fn(_) { ApiError(0, "Failed to parse search results") })
}

fn parse_scroll_results(body: String) -> Result(List(SearchHit), QdrantError) {
  let decoder =
    dynamic.field(
      "result",
      dynamic.field(
        "points",
        dynamic.list(dynamic.decode3(
          SearchHit,
          dynamic.field("id", dynamic.string),
          dynamic.field("score", fn(_) { Ok(0.0) }),
          dynamic.field("payload", dynamic.dynamic),
        )),
      ),
    )
  json.decode(body, decoder)
  |> result.map_error(fn(_) { ApiError(0, "Failed to parse scroll results") })
}
```

Note: The `json.array` and `json.preprocessed_array` APIs may differ. Consult `hexdocs.pm/gleam_json` for exact signatures. The `dynamic.decode3` constructor pattern should work but verify the import path. Qdrant point IDs may be returned as strings or ints depending on what was upserted — we use string IDs (UUIDs).

- [ ] **Step 4: Run integration tests**

Run: `cd ~/dev/alex-memory && gleam test`
Expected: All qdrant_client tests pass (Docker services must be running)

- [ ] **Step 5: Commit**

```bash
cd ~/dev/alex-memory
git add src/alex_memory/infra/qdrant_client.gleam test/alex_memory/infra/qdrant_client_test.gleam
git commit -m "feat: Qdrant HTTP client with upsert, search, delete, scroll"
```

---

## Chunk 3: Indexer Pipeline

### Task 9: Frontmatter parser

**Files:**
- Create: `src/alex_memory/indexer/frontmatter.gleam`
- Create: `test/alex_memory/indexer/frontmatter_test.gleam`

- [ ] **Step 1: Write failing tests**

```gleam
// test/alex_memory/indexer/frontmatter_test.gleam
import alex_memory/indexer/frontmatter
import alex_memory/types
import gleam/option.{None, Some}
import gleeunit/should

pub fn parse_basic_frontmatter_test() {
  let input =
    "---
type: bug
status: open
severity: p1
tags: [cook, scheduler]
created: 2026-03-17
updated: 2026-03-17
source: conversation
---

# Scheduler Race Condition

The scheduler can deadlock."

  let assert Ok(doc) = frontmatter.parse(input)
  doc.title |> should.equal("Scheduler Race Condition")
  doc.metadata.memory_type |> should.equal(types.Bug)
  doc.metadata.status |> should.equal(Some(types.Open))
  doc.metadata.severity |> should.equal(Some(types.P1))
  doc.metadata.tags |> should.equal(["cook", "scheduler"])
  doc.metadata.source |> should.equal(types.Conversation)
}

pub fn parse_minimal_frontmatter_test() {
  let input =
    "---
type: memory
created: 2026-03-17
updated: 2026-03-17
source: conversation
---

# A Memory

Some content."

  let assert Ok(doc) = frontmatter.parse(input)
  doc.metadata.memory_type |> should.equal(types.Memory)
  doc.metadata.status |> should.equal(None)
  doc.metadata.severity |> should.equal(None)
  doc.metadata.tags |> should.equal([])
}

pub fn parse_no_frontmatter_test() {
  let input = "# Just a Note\n\nNo frontmatter here."
  let result = frontmatter.parse(input)
  // Should return a document with default metadata sourced from vault
  result |> should.be_ok
}

pub fn serialize_frontmatter_test() {
  let meta = types.Metadata(
    memory_type: types.Bug,
    status: Some(types.Open),
    severity: Some(types.P1),
    tags: ["cook", "scheduler"],
    created: "2026-03-17",
    updated: "2026-03-17",
    source: types.Conversation,
    vault_path: "Claude/bugs/test.md",
    schema_version: 1,
  )
  let output = frontmatter.serialize(meta, "Test Bug", "Some content")
  string.contains(output, "type: bug") |> should.be_true
  string.contains(output, "status: open") |> should.be_true
  string.contains(output, "# Test Bug") |> should.be_true
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/dev/alex-memory && gleam test`
Expected: Compilation error

- [ ] **Step 3: Implement frontmatter parser**

This is a simple line-based YAML-subset parser (not a full YAML parser). Frontmatter is delimited by `---` lines. We parse the key-value pairs we know about.

```gleam
// src/alex_memory/indexer/frontmatter.gleam
import alex_memory/types.{
  type MemoryDocument, type Metadata, type MemoryType,
  type Status, type Severity, type Source,
  MemoryDocument, Metadata,
}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Parse a markdown file with optional YAML frontmatter into a MemoryDocument.
pub fn parse(content: String) -> Result(MemoryDocument, String) {
  let lines = string.split(content, "\n")
  case lines {
    ["---", ..rest] -> parse_with_frontmatter(rest)
    _ -> parse_without_frontmatter(content)
  }
}

/// Serialize metadata + title + content into a markdown file with frontmatter.
pub fn serialize(
  metadata: Metadata,
  title: String,
  content: String,
) -> String {
  let fm_lines = [
    "---",
    "type: " <> types.memory_type_to_string(metadata.memory_type),
  ]
  let fm_lines = case metadata.status {
    Some(s) -> list.append(fm_lines, ["status: " <> types.status_to_string(s)])
    None -> fm_lines
  }
  let fm_lines = case metadata.severity {
    Some(s) -> list.append(fm_lines, ["severity: " <> types.severity_to_string(s)])
    None -> fm_lines
  }
  let fm_lines = case metadata.tags {
    [] -> fm_lines
    tags -> list.append(fm_lines, [
      "tags: [" <> string.join(tags, ", ") <> "]",
    ])
  }
  let fm_lines = list.append(fm_lines, [
    "created: " <> metadata.created,
    "updated: " <> metadata.updated,
    "source: " <> types.source_to_string(metadata.source),
    "---",
    "",
    "# " <> title,
    "",
    content,
  ])
  string.join(fm_lines, "\n")
}

fn parse_with_frontmatter(
  lines: List(String),
) -> Result(MemoryDocument, String) {
  let #(fm_lines, body_lines) = split_at_delimiter(lines, "---")
  let fm = parse_frontmatter_lines(fm_lines)
  let body = string.join(body_lines, "\n") |> string.trim
  let title = extract_title(body)

  use memory_type <- result.try(
    get_fm_value(fm, "type")
    |> result.try(types.memory_type_from_string),
  )

  let status =
    get_fm_value(fm, "status")
    |> result.try(types.status_from_string)
    |> option.from_result

  let severity =
    get_fm_value(fm, "severity")
    |> result.try(fn(s) {
      case s {
        "p0" -> Ok(types.P0)
        "p1" -> Ok(types.P1)
        "p2" -> Ok(types.P2)
        "p3" -> Ok(types.P3)
        _ -> Error("Unknown severity")
      }
    })
    |> option.from_result

  let tags = case get_fm_value(fm, "tags") {
    Ok(t) -> parse_tags(t)
    Error(_) -> []
  }

  let created = get_fm_value(fm, "created") |> result.unwrap("")
  let updated = get_fm_value(fm, "updated") |> result.unwrap("")
  let source =
    get_fm_value(fm, "source")
    |> result.try(types.source_from_string)
    |> result.unwrap(types.Vault)

  Ok(MemoryDocument(
    title: title,
    content: body,
    metadata: Metadata(
      memory_type: memory_type,
      status: status,
      severity: severity,
      tags: tags,
      created: created,
      updated: updated,
      source: source,
      vault_path: "",
      schema_version: 1,
    ),
  ))
}

fn parse_without_frontmatter(content: String) -> Result(MemoryDocument, String) {
  let title = extract_title(content)
  Ok(MemoryDocument(
    title: title,
    content: content,
    metadata: Metadata(
      memory_type: types.Reference,
      status: None,
      severity: None,
      tags: [],
      created: "",
      updated: "",
      source: types.Vault,
      vault_path: "",
      schema_version: 1,
    ),
  ))
}

fn split_at_delimiter(
  lines: List(String),
  delimiter: String,
) -> #(List(String), List(String)) {
  case lines {
    [] -> #([], [])
    [line, ..rest] if line == delimiter -> #([], rest)
    [line, ..rest] -> {
      let #(before, after) = split_at_delimiter(rest, delimiter)
      #([line, ..before], after)
    }
  }
}

fn parse_frontmatter_lines(lines: List(String)) -> List(#(String, String)) {
  list.filter_map(lines, fn(line) {
    case string.split_once(line, ": ") {
      Ok(#(key, value)) -> Ok(#(string.trim(key), string.trim(value)))
      Error(_) -> Error(Nil)
    }
  })
}

fn get_fm_value(
  fm: List(#(String, String)),
  key: String,
) -> Result(String, String) {
  list.find(fm, fn(pair) { pair.0 == key })
  |> result.map(fn(pair) { pair.1 })
  |> result.map_error(fn(_) { "Missing key: " <> key })
}

fn extract_title(body: String) -> String {
  string.split(body, "\n")
  |> list.find(fn(line) { string.starts_with(line, "# ") })
  |> result.map(fn(line) { string.drop_start(line, 2) |> string.trim })
  |> result.unwrap("Untitled")
}

fn parse_tags(raw: String) -> List(String) {
  raw
  |> string.replace("[", "")
  |> string.replace("]", "")
  |> string.split(",")
  |> list.map(string.trim)
  |> list.filter(fn(s) { s != "" })
}
```

- [ ] **Step 4: Run tests**

Run: `cd ~/dev/alex-memory && gleam test`
Expected: All frontmatter tests pass

- [ ] **Step 5: Commit**

```bash
cd ~/dev/alex-memory
git add src/alex_memory/indexer/frontmatter.gleam test/alex_memory/indexer/frontmatter_test.gleam
git commit -m "feat: frontmatter parser and serializer for vault markdown"
```

### Task 10: Markdown chunker

**Files:**
- Create: `src/alex_memory/indexer/chunker.gleam`
- Create: `test/alex_memory/indexer/chunker_test.gleam`

- [ ] **Step 1: Write failing tests**

```gleam
// test/alex_memory/indexer/chunker_test.gleam
import alex_memory/indexer/chunker
import gleeunit/should

pub fn single_section_no_split_test() {
  let content = "# Title\n\nSome short content here."
  let chunks = chunker.chunk(content, 512)
  list.length(chunks) |> should.equal(1)
  let assert [chunk] = chunks
  chunk.index |> should.equal(0)
  chunk.total |> should.equal(1)
}

pub fn split_on_h2_test() {
  let content =
    "# Title\n\nIntro paragraph.\n\n## Section A\n\nContent A.\n\n## Section B\n\nContent B."
  let chunks = chunker.chunk(content, 512)
  list.length(chunks) |> should.equal(3)
  // Chunk 0: intro, Chunk 1: Section A, Chunk 2: Section B
}

pub fn split_on_h3_test() {
  let content =
    "# Title\n\n## Section\n\n### Sub A\n\nContent A.\n\n### Sub B\n\nContent B."
  let chunks = chunker.chunk(content, 512)
  // Should split at ### boundaries
  list.length(chunks) |> should.not_equal(1)
}

pub fn chunk_indices_correct_test() {
  let content =
    "# Title\n\n## A\n\nContent A.\n\n## B\n\nContent B.\n\n## C\n\nContent C."
  let chunks = chunker.chunk(content, 512)
  let indices = list.map(chunks, fn(c) { c.index })
  let totals = list.map(chunks, fn(c) { c.total })
  // Indices should be 0, 1, 2, 3
  indices |> should.equal([0, 1, 2, 3])
  // All totals should be 4
  list.all(totals, fn(t) { t == 4 }) |> should.be_true
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/dev/alex-memory && gleam test`
Expected: Compilation error

- [ ] **Step 3: Implement chunker**

```gleam
// src/alex_memory/indexer/chunker.gleam
import gleam/list
import gleam/string

pub type ContentChunk {
  ContentChunk(content: String, index: Int, total: Int)
}

/// Split markdown content into chunks at h2/h3 heading boundaries.
/// Each chunk gets an index and the total count.
pub fn chunk(content: String, _max_tokens: Int) -> List(ContentChunk) {
  let lines = string.split(content, "\n")
  let sections = split_by_headings(lines, [])

  let total = list.length(sections)
  list.index_map(sections, fn(section, idx) {
    ContentChunk(
      content: string.join(section, "\n") |> string.trim,
      index: idx,
      total: total,
    )
  })
  |> list.filter(fn(c) { c.content != "" })
  |> reindex
}

fn split_by_headings(
  lines: List(String),
  current: List(String),
) -> List(List(String)) {
  case lines {
    [] ->
      case current {
        [] -> []
        _ -> [list.reverse(current)]
      }
    [line, ..rest] ->
      case is_heading(line) {
        True ->
          case current {
            [] -> split_by_headings(rest, [line])
            _ -> [
              list.reverse(current),
              ..split_by_headings(rest, [line])
            ]
          }
        False -> split_by_headings(rest, [line, ..current])
      }
  }
}

fn is_heading(line: String) -> Bool {
  string.starts_with(line, "## ") || string.starts_with(line, "### ")
}

fn reindex(chunks: List(ContentChunk)) -> List(ContentChunk) {
  let total = list.length(chunks)
  list.index_map(chunks, fn(chunk, idx) {
    ContentChunk(..chunk, index: idx, total: total)
  })
}
```

- [ ] **Step 4: Run tests**

Run: `cd ~/dev/alex-memory && gleam test`
Expected: All chunker tests pass

- [ ] **Step 5: Commit**

```bash
cd ~/dev/alex-memory
git add src/alex_memory/indexer/chunker.gleam test/alex_memory/indexer/chunker_test.gleam
git commit -m "feat: markdown chunker splitting on h2/h3 headings"
```

### Task 11: Vault writer

**Files:**
- Create: `src/alex_memory/mcp/vault_writer.gleam`
- Create: `test/alex_memory/mcp/vault_writer_test.gleam`

- [ ] **Step 1: Write failing tests**

```gleam
// test/alex_memory/mcp/vault_writer_test.gleam
import alex_memory/mcp/vault_writer
import alex_memory/types
import gleam/option.{None, Some}
import simplifile
import gleeunit/should

pub fn write_memory_test() {
  let tmp_dir = "/tmp/alex_memory_test_vault"
  let _ = simplifile.create_directory_all(tmp_dir <> "/Claude/bugs")

  let result = vault_writer.write_memory(
    tmp_dir,
    "Claude",
    types.Bug,
    "Test Bug",
    "This is a test bug.",
    Some(types.Open),
    Some(types.P1),
    ["cook"],
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
  let _ = simplifile.delete(tmp_dir)
}

pub fn slugify_test() {
  vault_writer.slugify("Scheduler Race Condition")
  |> should.equal("scheduler-race-condition")

  vault_writer.slugify("Fix: the (weird) bug!")
  |> should.equal("fix-the-weird-bug")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/dev/alex-memory && gleam test`
Expected: Compilation error

- [ ] **Step 3: Implement vault_writer**

```gleam
// src/alex_memory/mcp/vault_writer.gleam
import alex_memory/indexer/frontmatter
import alex_memory/types
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/regex
import simplifile

/// Write a memory to the vault as a markdown file.
/// Returns the vault-relative path.
pub fn write_memory(
  vault_path: String,
  claude_dir: String,
  memory_type: types.MemoryType,
  title: String,
  content: String,
  status: Option(types.Status),
  severity: Option(types.Severity),
  tags: List(String),
) -> Result(String, String) {
  let type_dir = types.memory_type_to_dir(memory_type)
  let slug = slugify(title)
  let relative_path = claude_dir <> "/" <> type_dir <> "/" <> slug <> ".md"
  let full_path = vault_path <> "/" <> relative_path

  // Ensure directory exists
  let dir = vault_path <> "/" <> claude_dir <> "/" <> type_dir
  let _ = simplifile.create_directory_all(dir)

  // Get current date
  let today = get_today()

  let metadata = types.Metadata(
    memory_type: memory_type,
    status: status,
    severity: severity,
    tags: tags,
    created: today,
    updated: today,
    source: types.Conversation,
    vault_path: relative_path,
    schema_version: 1,
  )

  let file_content = frontmatter.serialize(metadata, title, content)

  simplifile.write(full_path, file_content)
  |> result.map(fn(_) { relative_path })
  |> result.map_error(fn(_) { "Failed to write file: " <> full_path })
}

/// Update an existing memory file's frontmatter/content.
pub fn update_memory(
  vault_path: String,
  relative_path: String,
  status: Option(types.Status),
  tags: Option(List(String)),
  content: Option(String),
) -> Result(Nil, String) {
  let full_path = vault_path <> "/" <> relative_path
  use existing <- result.try(
    simplifile.read(full_path)
    |> result.map_error(fn(_) { "File not found: " <> full_path }),
  )
  use doc <- result.try(frontmatter.parse(existing))

  let updated_meta = types.Metadata(
    ..doc.metadata,
    status: option.or(status, doc.metadata.status),
    tags: option.unwrap(tags, doc.metadata.tags),
    updated: get_today(),
    vault_path: relative_path,
  )
  let updated_content = option.unwrap(content, doc.content)
  let file_content = frontmatter.serialize(updated_meta, doc.title, updated_content)

  simplifile.write(full_path, file_content)
  |> result.map_error(fn(_) { "Failed to write file: " <> full_path })
}

pub fn slugify(title: String) -> String {
  title
  |> string.lowercase
  |> string.replace(" ", "-")
  |> string.to_graphemes
  |> list.filter(fn(c) {
    c == "-" || {
      let assert [cp] = string.to_utf_codepoints(c)
      let n = string.utf_codepoint_to_int(cp)
      // a-z or 0-9 or hyphen
      { n >= 97 && n <= 122 } || { n >= 48 && n <= 57 } || n == 45
    }
  })
  |> string.join("")
  |> collapse_hyphens
}

fn collapse_hyphens(s: String) -> String {
  case string.contains(s, "--") {
    True -> collapse_hyphens(string.replace(s, "--", "-"))
    False -> string.trim(s) |> string.trim_start("-") |> string.trim_end("-")
  }
}

fn get_today() -> String {
  // Use Erlang's :calendar module for current date
  // This will need FFI — placeholder for now
  "2026-03-17"
}
```

Note: The `get_today()` function needs Erlang FFI for `:calendar.local_time()`. During implementation, add an FFI call or use a Gleam date library. The `option.or` function may need to be verified — if it doesn't exist, use a case expression.

- [ ] **Step 4: Run tests**

Run: `cd ~/dev/alex-memory && gleam test`
Expected: All vault_writer tests pass

- [ ] **Step 5: Commit**

```bash
cd ~/dev/alex-memory
git add src/alex_memory/mcp/vault_writer.gleam test/alex_memory/mcp/vault_writer_test.gleam
git commit -m "feat: vault writer for creating and updating memory markdown files"
```

### Task 12: Embedder actor

**Files:**
- Create: `src/alex_memory/indexer/embedder.gleam`

This is an OTP actor that receives file paths, parses them, chunks them, embeds via Ollama, and upserts to Qdrant.

- [ ] **Step 1: Implement embedder actor**

```gleam
// src/alex_memory/indexer/embedder.gleam
import alex_memory/config.{type Config}
import alex_memory/indexer/chunker
import alex_memory/indexer/frontmatter
import alex_memory/indexer/point_id
import alex_memory/infra/ollama_client
import alex_memory/infra/qdrant_client
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import simplifile

pub type Message {
  IndexFile(path: String, vault_relative: String)
  DeleteFile(vault_relative: String)
  ReindexAll
  Shutdown
}

pub type State {
  State(config: Config)
}

pub fn start(config: Config) -> Result(Subject(Message), actor.StartError) {
  actor.new(State(config: config))
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(message: Message, state: State) -> actor.Next(Message, State) {
  case message {
    IndexFile(path, vault_relative) -> {
      case index_file(state.config, path, vault_relative) {
        Ok(_) -> io.println("Indexed: " <> vault_relative)
        Error(e) -> io.println("Failed to index " <> vault_relative <> ": " <> e)
      }
      actor.continue(state)
    }
    DeleteFile(vault_relative) -> {
      case delete_file(state.config, vault_relative) {
        Ok(_) -> io.println("Deleted: " <> vault_relative)
        Error(_) -> io.println("Failed to delete " <> vault_relative)
      }
      actor.continue(state)
    }
    ReindexAll -> {
      case reindex_all(state.config) {
        Ok(count) -> io.println("Reindexed " <> int.to_string(count) <> " files")
        Error(e) -> io.println("Reindex failed: " <> e)
      }
      actor.continue(state)
    }
    Shutdown -> actor.stop(process.Normal)
  }
}

fn index_file(
  config: Config,
  full_path: String,
  vault_relative: String,
) -> Result(Nil, String) {
  // Read and parse the file
  use content <- result.try(
    simplifile.read(full_path)
    |> result.map_error(fn(_) { "Cannot read file" }),
  )
  use doc <- result.try(frontmatter.parse(content))

  // Delete existing points for this file (handles chunk count changes)
  let _ = qdrant_client.delete_by_field(
    config.qdrant.url,
    config.qdrant.collection,
    "vault_path",
    vault_relative,
  )

  // Chunk the content
  let chunks = chunker.chunk(doc.content, config.indexer.chunk_max_tokens)

  // Embed and upsert each chunk
  list.try_each(chunks, fn(chunk) {
    use embedding <- result.try(
      ollama_client.embed(config.ollama.url, config.ollama.model, chunk.content)
      |> result.map_error(fn(_) { "Embedding failed" }),
    )

    let pid = point_id.generate(vault_relative, chunk.index)
    let payload = build_payload(doc, vault_relative, chunk)

    qdrant_client.upsert(
      config.qdrant.url,
      config.qdrant.collection,
      pid,
      embedding,
      payload,
    )
    |> result.map_error(fn(_) { "Upsert failed" })
  })
}

fn delete_file(config: Config, vault_relative: String) -> Result(Nil, String) {
  qdrant_client.delete_by_field(
    config.qdrant.url,
    config.qdrant.collection,
    "vault_path",
    vault_relative,
  )
  |> result.map_error(fn(_) { "Delete failed" })
}

fn reindex_all(config: Config) -> Result(Int, String) {
  use files <- result.try(
    walk_vault_markdown(config.vault.path, config.vault.ignore)
    |> result.map_error(fn(_) { "Failed to walk vault" }),
  )
  list.try_each(files, fn(path) {
    let relative = string.replace(path, config.vault.path <> "/", "")
    index_file(config, path, relative)
  })
  |> result.map(fn(_) { list.length(files) })
}

fn walk_vault_markdown(
  vault_path: String,
  ignore: List(String),
) -> Result(List(String), Nil) {
  simplifile.get_files(vault_path)
  |> result.map_error(fn(_) { Nil })
  |> result.map(fn(files) {
    list.filter(files, fn(f) {
      string.ends_with(f, ".md")
      && list.all(ignore, fn(ig) { !string.contains(f, "/" <> ig <> "/") })
    })
  })
}

fn build_payload(
  doc: types.MemoryDocument,
  vault_relative: String,
  chunk: chunker.ContentChunk,
) -> json.Json {
  let base = [
    #("vault_path", json.string(vault_relative)),
    #("type", json.string(types.memory_type_to_string(doc.metadata.memory_type))),
    #("title", json.string(doc.title)),
    #("content", json.string(chunk.content)),
    #("chunk_index", json.int(chunk.index)),
    #("chunk_total", json.int(chunk.total)),
    #("created", json.string(doc.metadata.created)),
    #("updated", json.string(doc.metadata.updated)),
    #("source", json.string(types.source_to_string(doc.metadata.source))),
    #("schema_version", json.int(doc.metadata.schema_version)),
    #("tags", json.array(doc.metadata.tags, json.string)),
  ]
  let base = case doc.metadata.status {
    Some(s) -> list.append(base, [#("status", json.string(types.status_to_string(s)))])
    None -> base
  }
  let base = case doc.metadata.severity {
    Some(s) -> list.append(base, [#("severity", json.string(types.severity_to_string(s)))])
    None -> base
  }
  json.object(base)
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd ~/dev/alex-memory && gleam build`
Expected: Compiles without errors

- [ ] **Step 3: Commit**

```bash
cd ~/dev/alex-memory
git add src/alex_memory/indexer/embedder.gleam
git commit -m "feat: embedder actor — parses, chunks, embeds, upserts vault files"
```

### Task 13: Vault watcher actor

**Files:**
- Create: `src/alex_memory/indexer/vault_watcher.gleam`
- Create: `src/alex_memory/ffi/fs.gleam` (if needed for :fs bindings)

The vault watcher uses Erlang's `:fs` library to watch the filesystem and sends messages to the embedder.

- [ ] **Step 1: Implement vault watcher**

```gleam
// src/alex_memory/indexer/vault_watcher.gleam
import alex_memory/config.{type Config}
import alex_memory/indexer/embedder
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/string

pub type Message {
  FileChanged(path: String)
  FileDeleted(path: String)
  Tick
  Shutdown
}

pub type State {
  State(
    config: Config,
    embedder: Subject(embedder.Message),
    pending: List(String),
  )
}

pub fn start(
  config: Config,
  embedder: Subject(embedder.Message),
) -> Result(Subject(Message), actor.StartError) {
  actor.new(State(config: config, embedder: embedder, pending: []))
  |> actor.on_message(handle_message)
  |> actor.start
}

fn handle_message(message: Message, state: State) -> actor.Next(Message, State) {
  case message {
    FileChanged(path) -> {
      // Add to pending for debounce
      let pending = case list.contains(state.pending, path) {
        True -> state.pending
        False -> [path, ..state.pending]
      }
      // Schedule a tick for debounce
      schedule_tick(state.config.indexer.debounce_ms)
      actor.continue(State(..state, pending: pending))
    }
    FileDeleted(path) -> {
      let relative = make_relative(path, state.config.vault.path)
      process.send(state.embedder, embedder.DeleteFile(relative))
      actor.continue(state)
    }
    Tick -> {
      // Process all pending files
      list.each(state.pending, fn(path) {
        case should_index(path, state.config) {
          True -> {
            let relative = make_relative(path, state.config.vault.path)
            process.send(
              state.embedder,
              embedder.IndexFile(path, relative),
            )
          }
          False -> Nil
        }
      })
      actor.continue(State(..state, pending: []))
    }
    Shutdown -> actor.stop(process.Normal)
  }
}

fn should_index(path: String, config: Config) -> Bool {
  string.ends_with(path, ".md")
  && list.all(config.vault.ignore, fn(ig) {
    !string.contains(path, "/" <> ig <> "/")
  })
}

fn make_relative(path: String, vault_path: String) -> String {
  string.replace(path, vault_path <> "/", "")
}

fn schedule_tick(delay_ms: Int) -> Nil {
  // Use erlang:send_after/3 via FFI
  // This needs an Erlang FFI binding — implement during build
  Nil
}
```

Note: The `:fs` file system watcher and `erlang:send_after` need Erlang FFI bindings. During implementation:
1. Add `fs` as an Erlang dependency in `gleam.toml` under `[dependencies]` or use `gleam add` if available
2. Create FFI bindings in `src/alex_memory_ffi.erl` for `:fs.subscribe/0`, `:fs.start_link/2`, and `erlang:send_after/3`
3. The watcher will receive `{:fs, :file_event, {path, events}}` messages — use a Gleam selector to handle these

- [ ] **Step 2: Verify it compiles**

Run: `cd ~/dev/alex-memory && gleam build`
Expected: Compiles (with warnings about unimplemented FFI)

- [ ] **Step 3: Commit**

```bash
cd ~/dev/alex-memory
git add src/alex_memory/indexer/vault_watcher.gleam
git commit -m "feat: vault watcher actor with debounce and file change detection"
```

### Task 14: Application entry and supervision tree

**Files:**
- Modify: `src/alex_memory.gleam`

- [ ] **Step 1: Implement the root supervision tree**

```gleam
// src/alex_memory.gleam
import alex_memory/config
import alex_memory/indexer/embedder
import alex_memory/indexer/vault_watcher
import alex_memory/infra/ollama_client
import alex_memory/infra/qdrant_client
import gleam/io
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import gleam/result

pub fn main() {
  io.println("Starting alex_memory...")

  // Load config
  let assert Ok(cfg) = config.load("config/config.toml")
  io.println("Config loaded from config/config.toml")

  // Ensure Qdrant collection exists
  let assert Ok(_) = qdrant_client.ensure_collection(
    cfg.qdrant.url,
    cfg.qdrant.collection,
    cfg.qdrant.vector_dimension,
  )
  io.println("Qdrant collection ready: " <> cfg.qdrant.collection)

  // Ensure Ollama model is available
  let assert Ok(exists) = ollama_client.model_exists(cfg.ollama.url, cfg.ollama.model)
  case exists {
    True -> io.println("Ollama model ready: " <> cfg.ollama.model)
    False -> {
      io.println("Pulling Ollama model: " <> cfg.ollama.model)
      let assert Ok(_) = ollama_client.pull_model(cfg.ollama.url, cfg.ollama.model)
      io.println("Model pulled successfully")
    }
  }

  // Start embedder
  let assert Ok(embedder_subject) = embedder.start(cfg)
  io.println("Embedder started")

  // Start vault watcher
  let assert Ok(watcher_subject) = vault_watcher.start(cfg, embedder_subject)
  io.println("Vault watcher started for: " <> cfg.vault.path)

  // Initial index
  io.println("Starting initial vault index...")
  process.send(embedder_subject, embedder.ReindexAll)

  // Start MCP server (Task 15)
  // mcp_server.start(cfg, embedder_subject)

  io.println("alex_memory is running.")

  // Keep the process alive
  process.sleep_forever()
}
```

Note: This is a simplified entry point. The full supervision tree using `static_supervisor` will be implemented once all actors are working. The initial version starts actors directly to get end-to-end working first, then wraps them in supervision.

- [ ] **Step 2: Test that the application starts**

Run:
```bash
cd ~/dev/alex-memory
docker compose up -d  # ensure services are running
gleam run
```
Expected: Prints startup messages, indexes the vault, stays running. Ctrl+C to stop.

- [ ] **Step 3: Commit**

```bash
cd ~/dev/alex-memory
git add src/alex_memory.gleam
git commit -m "feat: application entry point with startup sequence"
```

---

## Chunk 4: MCP Server

### Task 15: MCP server with memory tools

**Files:**
- Create: `src/alex_memory/mcp/server.gleam`

- [ ] **Step 1: Implement MCP server with all 5 tools**

```gleam
// src/alex_memory/mcp/server.gleam
import alex_memory/config.{type Config}
import alex_memory/indexer/embedder
import alex_memory/infra/ollama_client
import alex_memory/infra/qdrant_client
import alex_memory/mcp/vault_writer
import alex_memory/types
import gleam/dynamic
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import mcp_toolkit

pub fn start(
  config: Config,
  embedder: Subject(embedder.Message),
) -> Result(Nil, String) {
  let server =
    mcp_toolkit.new("alex-memory", "0.1.0")
    |> mcp_toolkit.description("Semantic memory system for Claude Code")
    |> mcp_toolkit.instructions(
      "Use memory_find to search for relevant context. "
      <> "Use memory_store to save important information. "
      <> "Use memory_list to filter by type/status/tags. "
      <> "Use memory_update to change status or content. "
      <> "Use memory_reindex to rebuild the search index.",
    )
    |> add_memory_store(config, embedder)
    |> add_memory_find(config)
    |> add_memory_list(config)
    |> add_memory_update(config)
    |> add_memory_reindex(config, embedder)
    |> mcp_toolkit.build()

  // Start stdio transport
  let assert Ok(transport) = mcp_toolkit.create_transport(
    mcp_toolkit.Stdio,
  )

  io.println("MCP server listening on stdio")
  // Run the server loop reading from stdin
  run_stdio_loop(server, transport)
}

fn add_memory_store(
  builder: mcp_toolkit.Builder,
  config: Config,
  embedder: Subject(embedder.Message),
) -> mcp_toolkit.Builder {
  // Tool definition with JSON schema for parameters
  let tool = mcp_toolkit.Tool(
    name: "memory_store",
    description: Some(
      "Store a memory. Creates a markdown file in the vault and indexes it for semantic search. "
      <> "Use for: bugs, decisions, project updates, user preferences, patterns, references, brainstorm outputs.",
    ),
    input_schema: json.object([
      #("type", json.string("object")),
      #("properties", json.object([
        #("title", json.object([
          #("type", json.string("string")),
          #("description", json.string("Title of the memory")),
        ])),
        #("content", json.object([
          #("type", json.string("string")),
          #("description", json.string("The memory content in markdown")),
        ])),
        #("memory_type", json.object([
          #("type", json.string("string")),
          #("enum", json.array(
            ["bug", "decision", "project", "memory", "pattern", "session", "reference", "brainstorm"],
            json.string,
          )),
        ])),
        #("status", json.object([
          #("type", json.string("string")),
          #("enum", json.array(["open", "resolved", "active", "archived", "wontfix"], json.string)),
        ])),
        #("severity", json.object([
          #("type", json.string("string")),
          #("enum", json.array(["p0", "p1", "p2", "p3"], json.string)),
        ])),
        #("tags", json.object([
          #("type", json.string("array")),
          #("items", json.object([#("type", json.string("string"))])),
        ])),
      ])),
      #("required", json.array(["title", "content", "memory_type"], json.string)),
    ]),
  )

  // Handler function — decodes args and calls vault_writer
  let handler = fn(request: mcp_toolkit.CallToolRequest) -> mcp_toolkit.CallToolResult {
    // Decode arguments from the request
    // Implementation details depend on mcp_toolkit's CallToolRequest structure
    // Write to vault, send to embedder, return result
    todo
  }

  let decoder = fn(d: dynamic.Dynamic) -> Result(dynamic.Dynamic, List(dynamic.DecodeError)) {
    Ok(d)
  }

  mcp_toolkit.add_tool(builder, tool, decoder, handler)
}

fn add_memory_find(
  builder: mcp_toolkit.Builder,
  config: Config,
) -> mcp_toolkit.Builder {
  let tool = mcp_toolkit.Tool(
    name: "memory_find",
    description: Some(
      "Semantic search across all memories. Embeds the query and finds nearest neighbors. "
      <> "Optional filters narrow results by type, status, or tags.",
    ),
    input_schema: json.object([
      #("type", json.string("object")),
      #("properties", json.object([
        #("query", json.object([
          #("type", json.string("string")),
          #("description", json.string("Natural language search query")),
        ])),
        #("type", json.object([
          #("type", json.string("string")),
          #("description", json.string("Filter by memory type")),
        ])),
        #("status", json.object([
          #("type", json.string("string")),
          #("description", json.string("Filter by status")),
        ])),
        #("tags", json.object([
          #("type", json.string("array")),
          #("items", json.object([#("type", json.string("string"))])),
          #("description", json.string("Filter by tags (any match)")),
        ])),
        #("limit", json.object([
          #("type", json.string("integer")),
          #("description", json.string("Max results (default 10)")),
        ])),
      ])),
      #("required", json.array(["query"], json.string)),
    ]),
  )

  let handler = fn(request: mcp_toolkit.CallToolRequest) -> mcp_toolkit.CallToolResult {
    // 1. Embed the query via Ollama
    // 2. Build Qdrant filter from optional type/status/tags
    // 3. Search Qdrant
    // 4. Return formatted results
    todo
  }

  let decoder = fn(d: dynamic.Dynamic) -> Result(dynamic.Dynamic, List(dynamic.DecodeError)) {
    Ok(d)
  }

  mcp_toolkit.add_tool(builder, tool, decoder, handler)
}

fn add_memory_list(
  builder: mcp_toolkit.Builder,
  config: Config,
) -> mcp_toolkit.Builder {
  let tool = mcp_toolkit.Tool(
    name: "memory_list",
    description: Some(
      "List memories by filter (no semantic search). "
      <> "Use for structured queries like 'all open bugs' or 'active projects tagged cook'.",
    ),
    input_schema: json.object([
      #("type", json.string("object")),
      #("properties", json.object([
        #("type", json.object([#("type", json.string("string"))])),
        #("status", json.object([#("type", json.string("string"))])),
        #("tags", json.object([
          #("type", json.string("array")),
          #("items", json.object([#("type", json.string("string"))])),
        ])),
        #("sort_by", json.object([#("type", json.string("string"))])),
      ])),
    ]),
  )

  let handler = fn(request: mcp_toolkit.CallToolRequest) -> mcp_toolkit.CallToolResult {
    // Use Qdrant scroll API with filters, no vector search
    todo
  }

  let decoder = fn(d: dynamic.Dynamic) -> Result(dynamic.Dynamic, List(dynamic.DecodeError)) {
    Ok(d)
  }

  mcp_toolkit.add_tool(builder, tool, decoder, handler)
}

fn add_memory_update(
  builder: mcp_toolkit.Builder,
  config: Config,
) -> mcp_toolkit.Builder {
  let tool = mcp_toolkit.Tool(
    name: "memory_update",
    description: Some(
      "Update a memory's status, tags, or content. "
      <> "Modifies the vault file; re-indexing happens automatically.",
    ),
    input_schema: json.object([
      #("type", json.string("object")),
      #("properties", json.object([
        #("vault_path", json.object([
          #("type", json.string("string")),
          #("description", json.string("Vault-relative path to the memory file")),
        ])),
        #("status", json.object([#("type", json.string("string"))])),
        #("tags", json.object([
          #("type", json.string("array")),
          #("items", json.object([#("type", json.string("string"))])),
        ])),
        #("content", json.object([#("type", json.string("string"))])),
      ])),
      #("required", json.array(["vault_path"], json.string)),
    ]),
  )

  let handler = fn(request: mcp_toolkit.CallToolRequest) -> mcp_toolkit.CallToolResult {
    // Call vault_writer.update_memory, watcher handles re-index
    todo
  }

  let decoder = fn(d: dynamic.Dynamic) -> Result(dynamic.Dynamic, List(dynamic.DecodeError)) {
    Ok(d)
  }

  mcp_toolkit.add_tool(builder, tool, decoder, handler)
}

fn add_memory_reindex(
  builder: mcp_toolkit.Builder,
  config: Config,
  embedder: Subject(embedder.Message),
) -> mcp_toolkit.Builder {
  let tool = mcp_toolkit.Tool(
    name: "memory_reindex",
    description: Some(
      "Force re-indexing of the vault. "
      <> "Use with full=true to drop and rebuild the entire Qdrant collection.",
    ),
    input_schema: json.object([
      #("type", json.string("object")),
      #("properties", json.object([
        #("full", json.object([
          #("type", json.string("boolean")),
          #("description", json.string("Drop and rebuild entire collection (default false)")),
        ])),
      ])),
    ]),
  )

  let handler = fn(request: mcp_toolkit.CallToolRequest) -> mcp_toolkit.CallToolResult {
    process.send(embedder, embedder.ReindexAll)
    todo
  }

  let decoder = fn(d: dynamic.Dynamic) -> Result(dynamic.Dynamic, List(dynamic.DecodeError)) {
    Ok(d)
  }

  mcp_toolkit.add_tool(builder, tool, decoder, handler)
}

fn run_stdio_loop(server, transport) -> Result(Nil, String) {
  // Read from stdin, pass to handle_message, write to stdout
  // The exact implementation depends on mcp_toolkit's transport API
  // See mcp_toolkit docs for stdio loop examples
  todo
}
```

Note: The `todo` placeholders in handler functions need to be filled in during implementation. The exact `mcp_toolkit` handler API (how `CallToolRequest` provides arguments, how `CallToolResult` is constructed) must be checked against `hexdocs.pm/mcp_toolkit`. The tool handler closures need to capture `config` and `embedder` — Gleam closures support this.

- [ ] **Step 2: Fill in handler implementations**

Each handler follows the same pattern:
1. Decode arguments from the request
2. Call the appropriate infra/writer function
3. Return a `CallToolResult` with the response

Implement each handler function, replacing `todo` with real logic. Test each tool manually with the MCP inspector or by piping JSON-RPC messages to stdin.

- [ ] **Step 3: Verify MCP server starts**

Run: `cd ~/dev/alex-memory && gleam run`
Expected: "MCP server listening on stdio" printed, process stays alive

- [ ] **Step 4: Test with Claude Code**

Add to `~/.claude/settings.json` temporarily:
```json
{
  "mcpServers": {
    "alex-memory": {
      "command": "gleam",
      "args": ["run"],
      "cwd": "/home/alex/dev/alex-memory"
    }
  }
}
```

Start Claude Code and verify the memory tools appear.

- [ ] **Step 5: Commit**

```bash
cd ~/dev/alex-memory
git add src/alex_memory/mcp/server.gleam
git commit -m "feat: MCP server with memory_store, memory_find, memory_list, memory_update, memory_reindex"
```

### Task 16: End-to-end integration test

- [ ] **Step 1: Write an integration test that exercises the full pipeline**

```gleam
// test/alex_memory/integration_test.gleam
import alex_memory/config
import alex_memory/indexer/embedder
import alex_memory/infra/ollama_client
import alex_memory/infra/qdrant_client
import alex_memory/mcp/vault_writer
import alex_memory/types
import gleam/option.{None, Some}
import gleam/process
import gleeunit/should
import simplifile

const test_vault = "/tmp/alex_memory_integration_test"
const test_collection = "integration_test"

pub fn full_pipeline_test() {
  // Setup
  let _ = simplifile.create_directory_all(test_vault <> "/Claude/bugs")
  let assert Ok(_) = qdrant_client.ensure_collection(
    "http://localhost:6333", test_collection, 768,
  )

  // 1. Write a memory to vault
  let assert Ok(path) = vault_writer.write_memory(
    test_vault, "Claude", types.Bug,
    "Cache Invalidation Bug",
    "The cache does not invalidate when a Cookfile dependency changes.",
    Some(types.Open), Some(types.P1), ["cook", "cache"],
  )

  // 2. Read and embed it
  let full_path = test_vault <> "/" <> path
  let assert Ok(content) = simplifile.read(full_path)
  let assert Ok(embedding) = ollama_client.embed(
    "http://localhost:11434", "nomic-embed-text", content,
  )

  // 3. Upsert to Qdrant
  let payload = json.object([
    #("vault_path", json.string(path)),
    #("type", json.string("bug")),
    #("title", json.string("Cache Invalidation Bug")),
  ])
  let assert Ok(_) = qdrant_client.upsert(
    "http://localhost:6333", test_collection,
    "test-integration-id", embedding, payload,
  )

  // 4. Search for it
  let assert Ok(query_vec) = ollama_client.embed(
    "http://localhost:11434", "nomic-embed-text",
    "cache invalidation problem",
  )
  let assert Ok(results) = qdrant_client.search(
    "http://localhost:6333", test_collection, query_vec, 5, None,
  )
  list.length(results) |> should.not_equal(0)

  // Cleanup
  let _ = qdrant_client.delete_collection("http://localhost:6333", test_collection)
  let _ = simplifile.delete(test_vault)
}
```

- [ ] **Step 2: Run integration test**

Run: `cd ~/dev/alex-memory && gleam test`
Expected: Full pipeline test passes

- [ ] **Step 3: Commit**

```bash
cd ~/dev/alex-memory
git add test/alex_memory/integration_test.gleam
git commit -m "test: end-to-end integration test for the full memory pipeline"
```

---

## Chunk 5: Superpowers Fork & Skills Integration

### Task 17: Fork obra/superpowers into the repo

- [ ] **Step 1: Add obra/superpowers as a git subtree or copy**

```bash
cd ~/dev/alex-memory

# Clone upstream to a temp location
git clone https://github.com/obra/superpowers.git /tmp/superpowers-upstream

# Copy skill-related directories into our repo
cp -r /tmp/superpowers-upstream/skills/ ./skills/
cp -r /tmp/superpowers-upstream/hooks/ ./hooks/
cp -r /tmp/superpowers-upstream/agents/ ./agents/
cp -r /tmp/superpowers-upstream/commands/ ./commands/
cp -r /tmp/superpowers-upstream/.claude-plugin/ ./.claude-plugin/
cp /tmp/superpowers-upstream/package.json ./package.json
cp /tmp/superpowers-upstream/LICENSE ./LICENSE

# Clean up
rm -rf /tmp/superpowers-upstream
```

- [ ] **Step 2: Update plugin.json**

Modify `.claude-plugin/plugin.json`:
```json
{
  "name": "alex-memory",
  "description": "Semantic memory system + enhanced skills for Claude Code",
  "version": "0.1.0",
  "author": {
    "name": "Alex Gilbert"
  },
  "repository": "https://github.com/Alex-Gilbert/alex-memory",
  "license": "MIT",
  "keywords": ["memory", "skills", "vector-search", "obsidian", "qdrant"]
}
```

- [ ] **Step 3: Verify the existing skills are intact**

Read through a few skill files to confirm they copied correctly:
```bash
head -5 skills/brainstorming/SKILL.md
head -5 skills/systematic-debugging/SKILL.md
head -5 skills/using-superpowers/SKILL.md
```

- [ ] **Step 4: Commit**

```bash
cd ~/dev/alex-memory
git add skills/ hooks/ agents/ commands/ .claude-plugin/ package.json LICENSE
git commit -m "feat: fork obra/superpowers v5.0.5 as plugin base"
```

### Task 18: Create new skills using writing-skills

**IMPORTANT:** Each new skill MUST be created using the `superpowers:writing-skills` skill. Do NOT hand-write SKILL.md files.

- [ ] **Step 1: Create `/remember` skill**

Invoke `superpowers:writing-skills` with these requirements:
- **Name:** remember
- **Trigger:** When user invokes `/remember` or when Claude identifies something worth storing
- **Behavior:** Accepts natural language input. Claude determines the appropriate `memory_type`, `status`, `severity`, and `tags`. Calls the `memory_store` MCP tool. Reports back the vault path where the memory was saved.
- **Guard rails:** Before storing, call `memory_find` with >0.85 similarity threshold to check for duplicates. If a near-duplicate exists, offer to update it instead.
- **Location:** `skills/remember/SKILL.md`
- **Command file:** `commands/remember.md`

- [ ] **Step 2: Create `/recall` skill**

Invoke `superpowers:writing-skills` with these requirements:
- **Name:** recall
- **Trigger:** When user invokes `/recall` or Claude needs context
- **Behavior:** Accepts a natural language query and optional filters (type, status, tags). Calls `memory_find` MCP tool. Formats results with scores, titles, vault paths, and content previews. Offers to open the full note if the user wants more detail.
- **Location:** `skills/recall/SKILL.md`
- **Command file:** `commands/recall.md`

- [ ] **Step 3: Create `/bugs` skill**

Invoke `superpowers:writing-skills` with these requirements:
- **Name:** bugs
- **Trigger:** When user invokes `/bugs`
- **Behavior:** Subcommands:
  - `/bugs` — list all open bugs (`memory_list(type=bug, status=open)`)
  - `/bugs <tag>` — open bugs filtered by tag
  - `/bugs resolve <query>` — find the bug by semantic search, update status to resolved
  - `/bugs add <description>` — create a new bug
- **Location:** `skills/bugs/SKILL.md`
- **Command file:** `commands/bugs.md`

- [ ] **Step 4: Create `/status` skill**

Invoke `superpowers:writing-skills` with these requirements:
- **Name:** status
- **Trigger:** When user invokes `/status`
- **Behavior:** Subcommands:
  - `/status` — list all active projects (`memory_list(type=project, status=active)`)
  - `/status <project>` — show details for a specific project by semantic search
- **Location:** `skills/status/SKILL.md`
- **Command file:** `commands/status.md`

- [ ] **Step 5: Create `/session-end` skill**

Invoke `superpowers:writing-skills` with these requirements:
- **Name:** session-end
- **Trigger:** When user invokes `/session-end` or Claude is wrapping up
- **Behavior:** Summarizes the current conversation's accomplishments, decisions, bugs found, and patterns discovered. Stores each as the appropriate memory type. Creates a session summary with `type=session`.
- **Location:** `skills/session-end/SKILL.md`
- **Command file:** `commands/session-end.md`

- [ ] **Step 6: Commit all new skills**

```bash
cd ~/dev/alex-memory
git add skills/remember/ skills/recall/ skills/bugs/ skills/status/ skills/session-end/
git add commands/remember.md commands/recall.md commands/bugs.md commands/status.md commands/session-end.md
git commit -m "feat: new memory skills — remember, recall, bugs, status, session-end"
```

### Task 19: Modify existing skills for memory awareness

**IMPORTANT:** Use `superpowers:writing-skills` for modifications too.

- [ ] **Step 1: Modify brainstorming skill**

Using `writing-skills`, add to `skills/brainstorming/SKILL.md`:

In the Checklist section, modify step 1:
```
1. **Explore project context** — check files, docs, recent commits.
   THEN call memory_find for related decisions, brainstorms, and open bugs.
   Call memory_list(type=pattern) for established conventions in this area.
```

Add step 6.5 after "Write design doc":
```
6.5 **Store to memory** — After writing and committing the design doc:
   - Call memory_store with type=brainstorm for the full design
   - Extract each key decision and call memory_store with type=decision for each
```

- [ ] **Step 2: Modify systematic-debugging skill**

Add to `skills/systematic-debugging/SKILL.md`:

Before investigation begins:
```
0. **Check memory** — Before investigating:
   - memory_find for prior bugs with similar symptoms
   - memory_list(type=bug, status=resolved) to check if this was fixed before
   If a prior resolution exists, try that fix first.
```

After resolution:
```
N. **Store resolution** — After the bug is fixed:
   - memory_store with type=bug, status=resolved
   - Include: symptoms, root cause, fix applied, files changed
```

- [ ] **Step 3: Modify writing-plans skill**

Add to `skills/writing-plans/SKILL.md`:

Before planning:
```
0. **Recall context** — Before writing the plan:
   - memory_find for related decisions and patterns
   - Surface constraints from prior brainstorms
   - Check for open bugs that might affect the implementation
```

- [ ] **Step 4: Modify executing-plans skill**

Add to `skills/executing-plans/SKILL.md`:

On completion:
```
After completing the plan:
- memory_store any notable outcomes or lessons learned (type=pattern or type=decision)
- If bugs were discovered during execution, ensure they're stored (type=bug)
```

- [ ] **Step 5: Modify using-superpowers skill**

Add the new skills to the registry in `skills/using-superpowers/SKILL.md`. In the skill list / table, add entries for:
- `remember` — Store information to semantic memory
- `recall` — Search semantic memory
- `bugs` — Bug tracking and management
- `status` — Project progress tracking
- `session-end` — Summarize and store session before ending

- [ ] **Step 6: Commit modified skills**

```bash
cd ~/dev/alex-memory
git add skills/brainstorming/ skills/systematic-debugging/ skills/writing-plans/
git add skills/executing-plans/ skills/using-superpowers/
git commit -m "feat: add memory awareness to brainstorming, debugging, planning, and execution skills"
```

### Task 20: Update hooks for memory integration

**Files:**
- Modify: `hooks/hooks.json`
- Modify: `hooks/session-start`

- [ ] **Step 1: Update hooks.json** (no changes needed — SessionStart already defined)

Verify the existing `hooks.json` works. No `Stop` hook needed per spec (session-end is CLAUDE.md-driven).

- [ ] **Step 2: Modify session-start hook**

Update `hooks/session-start` to inject memory system context. After the existing `using_superpowers_escaped` injection, add:

```bash
# Memory system context
memory_context="When memory MCP tools are available (memory_store, memory_find, memory_list, memory_update, memory_reindex), you MUST:\\n- Search memory at conversation start for relevant context about the current working directory\\n- Auto-store confirmed bugs, explicit corrections, agreed-upon patterns, and relevant external links\\n- Before auto-storing, check for duplicates with memory_find (>0.85 similarity)\\n- Before ending a conversation, summarize accomplishments and store as type=session\\n- During brainstorming, recall prior decisions and patterns before starting"
memory_escaped=$(escape_for_json "$memory_context")
```

And include `${memory_escaped}` in the `session_context` string.

- [ ] **Step 3: Commit**

```bash
cd ~/dev/alex-memory
git add hooks/
git commit -m "feat: inject memory system context in session-start hook"
```

### Task 21: Create vault folder structure

- [ ] **Step 1: Create the Claude memory directories in the vault**

```bash
mkdir -p ~/alex-vault/Claude/{bugs,decisions,projects,memory,patterns,sessions,references,brainstorms}
```

- [ ] **Step 2: Add a .gitkeep to each (if vault is git-tracked)**

```bash
for dir in bugs decisions projects memory patterns sessions references brainstorms; do
  touch ~/alex-vault/Claude/$dir/.gitkeep
done
```

- [ ] **Step 3: Commit in the vault repo**

```bash
cd ~/alex-vault
git add Claude/
git commit -m "feat: add Claude memory directory structure"
```

### Task 22: Plugin installation and final verification

- [ ] **Step 1: Install the plugin in Claude Code**

```bash
claude plugin install ~/dev/alex-memory
```

Or if manual registration is needed, update `~/.claude/settings.json` to point to the alex-memory plugin directory.

- [ ] **Step 2: Configure the MCP server in Claude Code settings**

Add to the appropriate settings file:
```json
{
  "mcpServers": {
    "alex-memory": {
      "command": "gleam",
      "args": ["run"],
      "cwd": "/home/alex/dev/alex-memory"
    }
  }
}
```

- [ ] **Step 3: Verify end-to-end**

Start a new Claude Code session and verify:
1. Memory tools appear in the tool list
2. `/remember test memory` creates a file in `~/alex-vault/Claude/memory/`
3. `/recall test` finds the memory just created
4. `/bugs` shows no open bugs (empty list)
5. Skills are registered (check `/help` or skill list)

- [ ] **Step 4: Final commit**

```bash
cd ~/dev/alex-memory
git add -A
git commit -m "feat: complete alex-memory v0.1.0 — semantic memory system for Claude Code"
```

- [ ] **Step 5: Push to remote**

```bash
cd ~/dev/alex-memory
git push origin main
```

---

## Implementer Notes & Errata

These notes address issues found during plan review. Read before starting implementation.

### General: Missing Imports

The code samples throughout this plan are **intentionally minimal on imports** to focus on logic. Every Gleam file will need its own complete import block. The compiler will tell you exactly what's missing. Common imports you'll need to add:

- `gleam/string`, `gleam/list`, `gleam/int`, `gleam/float` — used pervasively
- `gleam/result` — for `use` expressions and `result.try`
- `gleam/option.{type Option, Some, None}` — for optional fields
- `gleam/http` — for `http.Post`, `http.Put`, `http.Get`, `http.Delete`
- `gleam/http/response` — for response type in httpc calls
- `gleam/erlang/process` — for `Subject`, `send`, selectors

**Do not treat missing imports as plan errors — let the Gleam compiler guide you.**

### General: API Verification

The `mcp_toolkit`, `tom`, `gleam_httpc`, and `gleam_json` APIs used in this plan are based on documentation available at plan-writing time. **Before implementing each task, read the hexdocs for the relevant package** to verify function names, type signatures, and module paths. Key docs:

- `hexdocs.pm/mcp_toolkit` — Server builder, tool registration, transport
- `hexdocs.pm/tom` — `parse` returns `Dict(String, Toml)`, not `Toml`
- `hexdocs.pm/gleam_json` — `json.array` signature, no `json.preprocessed_array`
- `hexdocs.pm/gleam_httpc` — Request builder patterns
- `hexdocs.pm/gleam_otp` — Actor and supervisor APIs

### Task 1: Add .gitignore

Create `.gitignore` as the first step in Task 1, BEFORE `gleam new`:

```gitignore
/build/
/_build/
/deps/
erl_crash.dump
*.beam
*.ez
.gleam/
```

### Task 4: Config — `tom` API corrections

- `tom.parse` returns `Result(Dict(String, Toml), ParseError)` — the doc type is `Dict(String, tom.Toml)`, not `tom.Toml`
- `tom.get_array` returns `Result(List(Toml), GetError)` — elements are `tom.String(s)`, `tom.Int(i)`, etc.
- Remove the unused `gleam/dynamic` import

### Task 6: Point ID — Not UUID v5

The generated IDs are SHA-256-derived hex strings formatted as UUID-shaped strings (8-4-4-4-12). They are NOT compliant UUID v5 (no version/variant bits set). This is fine — Qdrant accepts any string ID. Don't call them "UUID v5" in code comments.

### Task 8: Qdrant client fixes

- Replace `json.preprocessed_array([...])` with `json.array([...], fn(x) { x })` (the former doesn't exist)
- In `parse_scroll_results`: Qdrant scroll results don't have a `score` field. Replace `dynamic.field("score", fn(_) { Ok(0.0) })` with a direct `fn(_) { Ok(0.0) }` as the second argument to `decode3`
- Combine the Qdrant tests into a single `full_lifecycle_test` function to avoid test ordering fragility

### Task 10: Chunker — `max_tokens` not implemented

The `_max_tokens` parameter is currently ignored. During implementation, add a fallback: if a section exceeds `max_tokens` (estimated at ~4 chars/token), split it further at paragraph boundaries (`\n\n`). This prevents single enormous chunks when a document has no h2/h3 sub-headings.

### Task 11: Vault writer — `get_today()` implementation

Replace the hardcoded date with Erlang FFI. Create `src/alex_memory/ffi/calendar.gleam`:

```gleam
// src/alex_memory/ffi/calendar.gleam
@external(erlang, "alex_memory_ffi", "get_today")
pub fn get_today() -> String
```

And `src/alex_memory_ffi.erl`:

```erlang
-module(alex_memory_ffi).
-export([get_today/0]).

get_today() ->
    {{Y, M, D}, _} = calendar:local_time(),
    list_to_binary(io_lib:format("~4..0B-~2..0B-~2..0B", [Y, M, D])).
```

Also: replace `option.or(status, doc.metadata.status)` with an explicit case expression:
```gleam
case status {
  Some(_) -> status
  None -> doc.metadata.status
}
```

And use `simplifile.delete_all(tmp_dir)` (not `simplifile.delete`) for directory cleanup in tests.

### Tasks 12-13: Embedder and Vault Watcher — Missing pieces

**Tests:** Add unit tests for the pure functions in the embedder:
- `build_payload` — make it `pub` and test it
- `walk_vault_markdown` — make it `pub` and test it with a temp directory

**Vault watcher `:fs` FFI:** The `:fs` Erlang library needs FFI bindings. Add to `src/alex_memory_ffi.erl`:

```erlang
start_fs_watcher(Path) ->
    {ok, Pid} = fs:start_link(fs_watcher, Path),
    fs:subscribe(fs_watcher),
    {ok, Pid}.
```

And create a Gleam wrapper. The watcher receives `{fs, file_event, {Path, Events}}` messages — use `process.selecting` in the actor's init to handle these.

**`schedule_tick` implementation:** Use `process.send_after` from `gleam_erlang`:
```gleam
fn schedule_tick(self: Subject(Message), delay_ms: Int) -> Nil {
  process.send_after(self, delay_ms, Tick)
  Nil
}
```
The watcher actor needs access to its own `Subject` — pass it during init using `actor.new_with_initialiser`.

### Task 14: Supervision tree — DEFERRED

The plan starts actors directly without OTP supervision. This is intentional for getting end-to-end working first. **After Chunk 4 is complete and verified, refactor `alex_memory.gleam` to use `static_supervisor`:**

```gleam
// Target supervision tree (implement after e2e works)
let infra_sup =
  static_supervisor.new(static_supervisor.RestForOne)
  |> static_supervisor.add(ollama_actor.supervised())
  |> static_supervisor.add(qdrant_actor.supervised())

let indexer_sup =
  static_supervisor.new(static_supervisor.RestForOne)
  |> static_supervisor.add(vault_watcher.supervised())
  |> static_supervisor.add(embedder.supervised())

let root =
  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.add(infra_sup |> static_supervisor.supervised())
  |> static_supervisor.add(indexer_sup |> static_supervisor.supervised())
  |> static_supervisor.add(mcp_server.supervised())
  |> static_supervisor.start()
```

This requires converting the infra clients from pure modules to actors — also deferred. The current design (pure functions calling HTTP directly) works fine; actors add connection pooling and state management later.

### Task 15: MCP Server — Handler reference implementation

The `todo` placeholders must be filled. Here is the reference pattern for `memory_store` — all other handlers follow the same shape:

```gleam
// Reference handler pattern for memory_store
let handler = fn(request) {
  // 1. Decode arguments (mcp_toolkit provides the arguments as dynamic)
  let args = request.arguments
  let assert Ok(title) = dynamic.field("title", dynamic.string)(args)
  let assert Ok(content) = dynamic.field("content", dynamic.string)(args)
  let assert Ok(type_str) = dynamic.field("memory_type", dynamic.string)(args)
  let assert Ok(memory_type) = types.memory_type_from_string(type_str)

  let status = dynamic.field("status", dynamic.string)(args)
    |> result.try(types.status_from_string)
    |> option.from_result
  let tags = dynamic.field("tags", dynamic.list(dynamic.string))(args)
    |> result.unwrap([])

  // 2. Write to vault
  let assert Ok(vault_path) = vault_writer.write_memory(
    config.vault.path, config.vault.claude_dir,
    memory_type, title, content, status, None, tags,
  )

  // 3. Send to embedder for indexing
  let full_path = config.vault.path <> "/" <> vault_path
  process.send(embedder, embedder.IndexFile(full_path, vault_path))

  // 4. Return result (check mcp_toolkit docs for exact CallToolResult construction)
  mcp_toolkit.text_result("Stored to " <> vault_path)
}
```

For `memory_find`:
```gleam
// 1. Embed the query
let assert Ok(query_vec) = ollama_client.embed(config.ollama.url, config.ollama.model, query)
// 2. Build optional filter
let filter = build_qdrant_filter(type_filter, status_filter, tags_filter)
// 3. Search
let assert Ok(results) = qdrant_client.search(config.qdrant.url, config.qdrant.collection, query_vec, limit, filter)
// 4. Format and return
```

**The `run_stdio_loop` function** should use `mcp_toolkit`'s transport API. Check `hexdocs.pm/mcp_toolkit/mcp_toolkit/transport/stdio.html` for the exact function that reads stdin and dispatches to `handle_message`. It likely looks like:
```gleam
mcp_toolkit.transport.stdio.serve(server)
```

### Task 17: Superpowers fork — upstream tracking note

The flat `cp -r` approach is intentional. This fork is expected to diverge significantly from upstream (memory integration touches 5+ skills). Cherry-picking upstream fixes is still possible by cloning upstream and manually diffing. If you want to preserve merge capability, use `git subtree add --prefix=skills-upstream https://github.com/obra/superpowers.git main --squash` instead.

### Task 18: Skills — writing-skills process

The `writing-skills` skill uses a TDD-like process (RED/GREEN/REFACTOR). For memory skills that wrap MCP tools:
- **RED phase:** Describe the scenario where a user/agent tries to use memory without the skill (e.g., guesses at tool parameters, forgets to check for duplicates). This establishes what the skill prevents.
- **GREEN phase:** Write the minimal SKILL.md that addresses those failure modes.
- **REFACTOR phase:** Tighten the skill based on testing.

If the writing-skills process feels excessive for these utility skills, the implementer may write the SKILL.md directly following the skill format conventions — but document the rationale.

### Task 19: Skill modifications — direct edit, not writing-skills

The plan provides exact text to insert. Apply these as direct edits to the SKILL.md files. Do not invoke writing-skills for modifications where the exact change is specified — it would create process overhead for no benefit.

### Task 20: Session-start hook — exact modification

Replace the `session_context` assignment line in `hooks/session-start` with:

```bash
memory_context="When memory MCP tools are available (memory_store, memory_find, memory_list, memory_update, memory_reindex), you MUST:\\n- Search memory at conversation start for relevant context\\n- Auto-store confirmed bugs, corrections, patterns, and references\\n- Check for duplicates with memory_find (>0.85 similarity) before storing\\n- Summarize and store as type=session before ending conversations"
memory_escaped=$(escape_for_json "$memory_context")

session_context="<EXTREMELY_IMPORTANT>\nYou have superpowers.\n\n**Below is the full content of your 'superpowers:using-superpowers' skill - your introduction to using skills. For all other skills, use the 'Skill' tool:**\n\n${using_superpowers_escaped}\n\n${memory_escaped}\n\n${warning_escaped}\n</EXTREMELY_IMPORTANT>"
```

### Task 22: Plugin installation — uninstall existing first

**Before** installing alex-memory as a plugin, uninstall the existing superpowers plugin to avoid skill conflicts:

```bash
claude plugin uninstall superpowers@claude-plugins-official
claude plugin install ~/dev/alex-memory
```

### Task 22: Final commit — use specific files

Replace `git add -A` with specific files to avoid committing build artifacts:
```bash
git add .claude-plugin/ skills/ hooks/ agents/ commands/ package.json
git commit -m "feat: complete alex-memory v0.1.0"
```

### Spec deviation: `/session-end` skill

The spec describes session-end behavior as a CLAUDE.md instruction, not a skill. The plan adds a `/session-end` skill for explicit invocation as a complement to the CLAUDE.md auto-behavior. This is an intentional enhancement beyond the spec.
