# Network MCP Server Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an HTTP/SSE listener alongside the existing stdio transport so remote Claude Code agents on the Tailnet can access the shared memory pool.

**Architecture:** Dual-transport — same `mcp_toolkit.Server` instance serves both stdio (local plugin) and HTTP/SSE (remote agents). Author identity derived from Tailscale headers (remote) or config default (local). New `author` field threaded through metadata, frontmatter, vault writer, Qdrant payload, and tool schemas.

**Tech Stack:** Gleam/OTP, mcp_toolkit (SSE + RPC transports), Mist HTTP server, Tailscale

**Spec:** `docs/superpowers/specs/2026-03-18-network-mcp-server-design.md`

---

## Chunk 1: Author Field in Types, Frontmatter, and Vault Writer

This chunk adds the `author` field to the data model, plumbing it through the type system, frontmatter parsing/serialization, vault writer, and embedder payload — with tests at each step.

### Task 1: Add `author` to Metadata type

**Files:**
- Modify: `src/alex_memory/types.gleam:39-51`
- Test: `test/alex_memory/types_test.gleam`

- [ ] **Step 1: Write the failing test**

Add to `test/alex_memory/types_test.gleam`:

```gleam
pub fn metadata_has_author_field_test() {
  let meta = types.Metadata(
    memory_type: types.Bug,
    status: option.None,
    severity: option.None,
    tags: [],
    created: "2026-03-18",
    updated: "2026-03-18",
    source: types.Conversation,
    vault_path: "",
    schema_version: 1,
    author: "alex",
  )
  meta.author
  |> should.equal("alex")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: Compile error — `Metadata` does not have an `author` field.

- [ ] **Step 3: Add `author` field to Metadata**

In `src/alex_memory/types.gleam`, update the `Metadata` type (line 39-51) to add `author: String` after `schema_version`:

```gleam
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
    author: String,
  )
}
```

- [ ] **Step 4: Fix all existing Metadata constructors**

Every place that constructs a `Metadata` record now needs the `author` field. Search for `Metadata(` across the codebase and add `author: ""` to each — **except** `update_memory` which must preserve the existing author:

- `src/alex_memory/indexer/frontmatter.gleam:29-38` (default metadata for no-frontmatter case) — add `author: ""`
- `src/alex_memory/indexer/frontmatter.gleam:171-181` (build_metadata) — add `author: ""` (will be updated in Task 2 to parse from frontmatter)
- `src/alex_memory/mcp/vault_writer.gleam:41-51` (write_memory) — add `author: ""` (will be updated in Task 3 to accept param)
- `src/alex_memory/mcp/vault_writer.gleam:91-101` (update_memory) — add `author: doc.metadata.author` to preserve existing author
- `test/alex_memory/indexer/frontmatter_test.gleam` (the `serialize_frontmatter_test` Metadata constructor at ~line 60) — add `author: ""`
- `test/alex_memory/integration_test.gleam` (any `write_memory` calls) — add `""` as the author argument

- [ ] **Step 5: Run tests to verify everything compiles and passes**

Run: `gleam test`
Expected: All tests PASS including the new `metadata_has_author_field_test`.

- [ ] **Step 6: Commit**

```bash
git add src/alex_memory/types.gleam test/alex_memory/types_test.gleam src/alex_memory/indexer/frontmatter.gleam src/alex_memory/mcp/vault_writer.gleam test/alex_memory/indexer/frontmatter_test.gleam test/alex_memory/integration_test.gleam
git commit -m "feat: add author field to Metadata type"
```

---

### Task 2: Parse and serialize `author` in frontmatter

**Files:**
- Modify: `src/alex_memory/indexer/frontmatter.gleam:46-79` (serialize), `131-181` (build_metadata)
- Test: `test/alex_memory/indexer/frontmatter_test.gleam`

- [ ] **Step 1: Write the failing test for parsing**

Add to `test/alex_memory/indexer/frontmatter_test.gleam`:

```gleam
pub fn parse_author_frontmatter_test() {
  let input =
    "---\ntype: bug\nstatus: open\nauthor: alex@example.com\ncreated: 2026-03-18\nupdated: 2026-03-18\nsource: conversation\n---\n\n# Test Bug\n\nSome content"
  let assert Ok(doc) = frontmatter.parse(input)
  doc.metadata.author
  |> should.equal("alex@example.com")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: FAIL — `author` defaults to `""` because `build_metadata` doesn't read it yet.

- [ ] **Step 3: Add author parsing to build_metadata**

In `src/alex_memory/indexer/frontmatter.gleam`, in `build_metadata` (around line 164), add after the `source` binding:

```gleam
let author = find_key(kv, "author") |> option.unwrap("")
```

And include it in the `Ok(Metadata(...))` return (around line 171-181):

```gleam
Ok(Metadata(
  memory_type: memory_type,
  status: status,
  severity: severity,
  tags: tags,
  created: created,
  updated: updated,
  source: source,
  vault_path: "",
  schema_version: 1,
  author: author,
))
```

- [ ] **Step 4: Run test to verify parsing passes**

Run: `gleam test`
Expected: `parse_author_frontmatter_test` PASSES.

- [ ] **Step 5: Write the failing test for serialization**

Add to `test/alex_memory/indexer/frontmatter_test.gleam`:

```gleam
pub fn serialize_author_frontmatter_test() {
  let meta =
    types.Metadata(
      memory_type: types.Bug,
      status: option.Some(types.Open),
      severity: option.None,
      tags: [],
      created: "2026-03-18",
      updated: "2026-03-18",
      source: types.Conversation,
      vault_path: "",
      schema_version: 1,
      author: "alex@example.com",
    )
  let result = frontmatter.serialize(meta, "Test Bug", "Content")
  result |> string.contains("author: alex@example.com") |> should.be_true
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `gleam test`
Expected: FAIL — `serialize` doesn't emit `author` yet.

- [ ] **Step 7: Add author serialization**

In `src/alex_memory/indexer/frontmatter.gleam`, in the `serialize` function, add the author block **between the tags block (line 66) and the final `list.append` (line 67)** — it must be inside the frontmatter delimiters, not after `---`:

```gleam
let lines = case meta.author {
  "" -> lines
  a -> list.append(lines, ["author: " <> a])
}
```

- [ ] **Step 8: Run tests to verify both pass**

Run: `gleam test`
Expected: All tests PASS.

- [ ] **Step 9: Commit**

```bash
git add src/alex_memory/indexer/frontmatter.gleam test/alex_memory/indexer/frontmatter_test.gleam
git commit -m "feat: parse and serialize author in frontmatter"
```

---

### Task 3: Thread `author` through vault writer

**Files:**
- Modify: `src/alex_memory/mcp/vault_writer.gleam:17-59`
- Test: `test/alex_memory/mcp/vault_writer_test.gleam`

- [ ] **Step 1: Write the failing test**

Add to `test/alex_memory/mcp/vault_writer_test.gleam`:

```gleam
pub fn write_memory_with_author_test() {
  let tmp_dir = "/tmp/alex_memory_test_vault_author"
  let _ = simplifile.create_directory_all(tmp_dir)

  let assert Ok(vault_path) =
    vault_writer.write_memory(
      tmp_dir,
      "Claude",
      types.Bug,
      "Author Test",
      "content",
      option.None,
      option.None,
      [],
      "alex@example.com",
    )

  let assert Ok(content) = simplifile.read(tmp_dir <> "/" <> vault_path)
  content |> string.contains("author: alex@example.com") |> should.be_true

  let _ = simplifile.delete_all([tmp_dir])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: Compile error — `write_memory` doesn't accept `author` parameter.

- [ ] **Step 3: Add `author` parameter to write_memory**

In `src/alex_memory/mcp/vault_writer.gleam`, update `write_memory` signature (lines 17-26) to add `author: String` after `tags`:

```gleam
pub fn write_memory(
  vault_path: String,
  claude_dir: String,
  memory_type: types.MemoryType,
  title: String,
  content: String,
  status: Option(types.Status),
  severity: Option(types.Severity),
  tags: List(String),
  author: String,
) -> Result(String, String) {
```

And set `author: author` in the `Metadata` constructor (line 41-51):

```gleam
let meta =
  types.Metadata(
    memory_type: memory_type,
    status: status,
    severity: severity,
    tags: tags,
    created: today,
    updated: today,
    source: types.Conversation,
    vault_path: relative_path,
    schema_version: 1,
    author: author,
  )
```

- [ ] **Step 4: Fix existing call sites**

The existing `write_memory` call in `src/alex_memory/mcp/server.gleam:261-269` now needs an `author` argument. For now, pass `""` — this will be updated in Chunk 2 when we add the author context.

Update `server.gleam` around line 261:

```gleam
vault_writer.write_memory(
  config.vault.path,
  config.vault.claude_dir,
  memory_type,
  args.title,
  args.content,
  status,
  severity,
  tags,
  "",
)
```

Also fix these existing call sites to pass `""` as the author argument:
- `test/alex_memory/mcp/vault_writer_test.gleam` — existing `write_memory_test`
- `test/alex_memory/integration_test.gleam` — any `write_memory` calls

- [ ] **Step 5: Run tests to verify all pass**

Run: `gleam test`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add src/alex_memory/mcp/vault_writer.gleam src/alex_memory/mcp/server.gleam test/alex_memory/mcp/vault_writer_test.gleam test/alex_memory/integration_test.gleam
git commit -m "feat: thread author through vault writer"
```

---

### Task 4: Add `author` to embedder Qdrant payload

**Files:**
- Modify: `src/alex_memory/indexer/embedder.gleam:202-237`

- [ ] **Step 1: Add `author` to build_payload**

In `src/alex_memory/indexer/embedder.gleam`, in `build_payload` (line 207-218), add to `base_fields`:

```gleam
#("author", json.string(doc.metadata.author)),
```

Add it after the `"tags"` field (line 218).

- [ ] **Step 2: Run tests to verify nothing breaks**

Run: `gleam test`
Expected: All tests PASS.

- [ ] **Step 3: Commit**

```bash
git add src/alex_memory/indexer/embedder.gleam
git commit -m "feat: include author in Qdrant payload"
```

---

## Chunk 2: Config Changes and HTTP Transport

This chunk extends the config to support HTTP settings, adds the HTTP server with SSE/RPC routing, and changes the startup sequence to run both transports concurrently.

### Task 5: Extend McpConfig with HTTP fields

**Files:**
- Modify: `src/alex_memory/config.gleam:22-24, 88-91`
- Modify: `config/config.toml`
- Test: `test/alex_memory/config_test.gleam`

- [ ] **Step 1: Write the failing test**

Update `test/alex_memory/config_test.gleam` `parse_config_test` to include the new fields in the inline TOML and assert them:

Add to the TOML string inside the test:
```toml
http_port = 7890
http_enabled = true
default_author = "alex"
```

Add assertions:
```gleam
cfg.mcp.http_port |> should.equal(7890)
cfg.mcp.http_enabled |> should.equal(True)
cfg.mcp.default_author |> should.equal("alex")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test`
Expected: Compile error — `McpConfig` doesn't have these fields.

- [ ] **Step 3: Update McpConfig type**

In `src/alex_memory/config.gleam`, change `McpConfig` (lines 22-24):

```gleam
pub type McpConfig {
  McpConfig(
    transport: String,
    http_port: Int,
    http_enabled: Bool,
    default_author: String,
  )
}
```

- [ ] **Step 4: Update the parser**

In `src/alex_memory/config.gleam`, after the `mcp_transport` binding (line 88-91), add:

```gleam
let mcp_http_port =
  tom.get_int(doc, ["mcp", "http_port"])
  |> result.unwrap(7890)

let mcp_http_enabled =
  tom.get_bool(doc, ["mcp", "http_enabled"])
  |> result.unwrap(False)

let mcp_default_author =
  tom.get_string(doc, ["mcp", "default_author"])
  |> result.unwrap("")
```

And update the `McpConfig` constructor (line 109):

```gleam
mcp: McpConfig(
  transport: mcp_transport,
  http_port: mcp_http_port,
  http_enabled: mcp_http_enabled,
  default_author: mcp_default_author,
),
```

- [ ] **Step 5: Update config/config.toml**

Add to the `[mcp]` section:

```toml
http_port = 7890
http_enabled = true
default_author = "alex"
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `gleam test`
Expected: All tests PASS. (The `load_from_file_test` also passes because the fields have defaults.)

- [ ] **Step 7: Commit**

```bash
git add src/alex_memory/config.gleam config/config.toml test/alex_memory/config_test.gleam
git commit -m "feat: add http_port, http_enabled, default_author to McpConfig"
```

---

### Task 6: Create HTTP server module

**Files:**
- Create: `src/alex_memory/mcp/http_server.gleam`

This module sets up a Mist HTTP listener that routes requests to mcp_toolkit's SSE and RPC transports.

Note: `mcp_toolkit.Server` is a type alias for `mcp_toolkit/core/server.Server` — the SSE and RPC transport functions accept either interchangeably.

Note: Per-request author identity from Tailscale headers is deferred to a follow-up. The `mcp_toolkit` handler signature `fn(CallToolRequest(Args)) -> Result(CallToolResult, String)` has no per-request context. A future task will use Erlang process dictionary to stash author per-request before `handle_message` is called. For now, all requests (stdio and HTTP) use `config.mcp.default_author`.

- [ ] **Step 1: Create the HTTP server module**

Create `src/alex_memory/mcp/http_server.gleam`:

```gleam
import alex_memory/config.{type Config}
import gleam/bytes_tree
import gleam/http/request
import gleam/http/response
import gleam/io
import gleam/string
import mcp_toolkit
import mcp_toolkit/transport/rpc
import mcp_toolkit/transport/sse
import mist

/// Start the HTTP MCP server on the configured port.
/// Mist runs its accept loop in a background OTP supervisor — this returns immediately.
pub fn start(
  config: Config,
  server: mcp_toolkit.Server,
) -> Result(Nil, String) {
  let registry = sse.start_registry()

  let handler = fn(req: request.Request(mist.Connection)) {
    case request.path_segments(req) {
      ["sse"] -> sse.handle_sse(req, registry, server)
      ["mcp"] -> rpc.handle_http_rpc(req, server, 1_000_000)
      ["health"] -> health_response()
      _ -> not_found_response()
    }
  }

  let port = config.mcp.http_port
  io.println_error(
    "HTTP MCP server starting on port " <> string.inspect(port) <> "...",
  )

  case
    mist.new(handler)
    |> mist.port(port)
    |> mist.start
  {
    Ok(_) -> {
      io.println_error("HTTP MCP server listening on port " <> string.inspect(port))
      Ok(Nil)
    }
    Error(e) -> {
      io.println_error("Failed to start HTTP server: " <> string.inspect(e))
      Error("Failed to start HTTP server")
    }
  }
}

fn health_response() -> response.Response(mist.ResponseData) {
  response.new(200)
  |> response.set_header("Content-Type", "application/json")
  |> response.set_body(
    mist.Bytes(bytes_tree.from_string("{\"status\":\"ok\"}")),
  )
}

fn not_found_response() -> response.Response(mist.ResponseData) {
  response.new(404)
  |> response.set_body(
    mist.Bytes(bytes_tree.from_string("Not found")),
  )
}
```

- [ ] **Step 2: Verify it compiles**

Run: `gleam build`
Expected: Compiles with no errors.

- [ ] **Step 3: Commit**

```bash
git add src/alex_memory/mcp/http_server.gleam
git commit -m "feat: add HTTP server module with SSE, RPC, and health routes"
```

---

### Task 7: Refactor server.gleam and main entry point for dual transport

**Files:**
- Modify: `src/alex_memory/mcp/server.gleam:571-663`
- Modify: `src/alex_memory.gleam`

Currently `start()` builds the server AND runs the stdio loop. We split these so both transports share the same server, and update `main()` in the same commit to keep the build green.

- [ ] **Step 1: Extract `build` and `run_stdio` from `start` in server.gleam**

In `src/alex_memory/mcp/server.gleam`, replace `start` and `run_stdio` (lines 571-663) with:

```gleam
/// Build the MCP server with all tools registered.
/// Returns a server value that can be used by any transport.
pub fn build(
  config: Config,
  embedder_subject: Subject(embedder.Message),
) -> mcp_toolkit.Server {
  mcp_toolkit.new("alex-memory", "1.0.0")
  |> mcp_toolkit.description(
    "Persistent memory system for Claude Code with semantic search",
  )
  |> mcp_toolkit.add_tool(
    mcp.Tool(
      name: "memory_store",
      description: Some(
        "Store a new memory in the vault. Creates a markdown file and indexes it for semantic search.",
      ),
      input_schema: store_schema(),
      annotations: None,
    ),
    decode_store_args(),
    handle_store(config, embedder_subject),
  )
  |> mcp_toolkit.add_tool(
    mcp.Tool(
      name: "memory_find",
      description: Some(
        "Search memories using semantic similarity. Returns ranked results with content previews.",
      ),
      input_schema: find_schema(),
      annotations: None,
    ),
    decode_find_args(),
    handle_find(config),
  )
  |> mcp_toolkit.add_tool(
    mcp.Tool(
      name: "memory_list",
      description: Some(
        "List memories with optional filters. Uses metadata filtering without semantic search.",
      ),
      input_schema: list_schema(),
      annotations: None,
    ),
    decode_list_args(),
    handle_list(config),
  )
  |> mcp_toolkit.add_tool(
    mcp.Tool(
      name: "memory_update",
      description: Some(
        "Update an existing memory's status, tags, or content. The vault watcher will re-index automatically.",
      ),
      input_schema: update_schema(),
      annotations: None,
    ),
    decode_update_args(),
    handle_update(config),
  )
  |> mcp_toolkit.add_tool(
    mcp.Tool(
      name: "memory_reindex",
      description: Some(
        "Trigger a full re-index of all vault markdown files.",
      ),
      input_schema: reindex_schema(),
      annotations: None,
    ),
    decode_reindex_args(),
    handle_reindex(embedder_subject),
  )
  |> mcp_toolkit.build()
}

/// Start the stdio transport. Blocks until stdin closes.
pub fn run_stdio(server: mcp_toolkit.Server) -> Nil {
  io.println_error("MCP server ready, listening on stdio...")
  do_run_stdio(server)
}

fn do_run_stdio(server: mcp_toolkit.Server) -> Nil {
  case stdio.read_message() {
    Ok(message) -> {
      case mcp_toolkit.handle_message(server, message) {
        Ok(Some(response)) -> io.println(json.to_string(response))
        Ok(None) -> Nil
        Error(err) -> io.println(json.to_string(err))
      }
      do_run_stdio(server)
    }
    Error(_) -> {
      io.println_error("MCP server: stdin closed, shutting down")
      Nil
    }
  }
}
```

Delete the old `start` and `run_stdio` functions.

- [ ] **Step 2: Update main() to use dual transport**

Replace the contents of `src/alex_memory.gleam`:

```gleam
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

  // Start HTTP server if enabled (non-blocking — Mist runs in background)
  case cfg.mcp.http_enabled {
    True -> {
      let _ = http_server.start(cfg, server)
      Nil
    }
    False -> Nil
  }

  // Start stdio transport (blocks until stdin closes)
  io.println_error("MCP server ready")
  mcp_server.run_stdio(server)

  // If HTTP is enabled, keep the BEAM alive after stdio closes
  // so remote clients aren't dropped when the local plugin disconnects.
  case cfg.mcp.http_enabled {
    True -> {
      io.println_error("Stdio closed, HTTP server still running. Ctrl+C to stop.")
      process.sleep_forever()
    }
    False -> Nil
  }
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
```

- [ ] **Step 3: Verify it compiles**

Run: `gleam build`
Expected: Compiles with no errors.

- [ ] **Step 4: Run tests**

Run: `gleam test`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/alex_memory/mcp/server.gleam src/alex_memory.gleam
git commit -m "feat: dual transport — split server build/stdio, add HTTP startup with process lifecycle"
```

---

## Chunk 3: Author Context in Tool Handlers

This chunk threads author identity through the MCP tool handlers. The challenge: mcp_toolkit's tool handler signature is `fn(CallToolRequest(Args)) -> Result(CallToolResult, String)` — there's no per-request context for HTTP headers. We solve this by passing `default_author` from config into the handler closures for stdio. The HTTP transport will need a different approach — we store author in a process dictionary or pass it through the server's context mechanism.

### Task 9: Pass default_author into handle_store

**Files:**
- Modify: `src/alex_memory/mcp/server.gleam:220-294`

For the stdio transport, all requests use `config.mcp.default_author`. The HTTP transport author injection is a future enhancement once we understand mcp_toolkit's context mechanism better.

- [ ] **Step 1: Update handle_store to use default_author**

In `src/alex_memory/mcp/server.gleam`, update `handle_store` (line 220) to pass `config.mcp.default_author` to `vault_writer.write_memory`:

Replace the `""` we added in Task 3, Step 4 with `config.mcp.default_author`:

```gleam
vault_writer.write_memory(
  config.vault.path,
  config.vault.claude_dir,
  memory_type,
  args.title,
  args.content,
  status,
  severity,
  tags,
  config.mcp.default_author,
)
```

- [ ] **Step 2: Verify it compiles and tests pass**

Run: `gleam test`
Expected: All tests PASS.

- [ ] **Step 3: Commit**

```bash
git add src/alex_memory/mcp/server.gleam
git commit -m "feat: pass default_author from config into memory_store handler"
```

---

### Task 10: Add `author` filter to find and list schemas

**Files:**
- Modify: `src/alex_memory/mcp/server.gleam` (FindArgs, ListArgs, decoders, build_filter, schemas, result formatting)

- [ ] **Step 1: Add `author` to FindArgs and ListArgs**

In `src/alex_memory/mcp/server.gleam`, update `FindArgs` (lines 32-40):

```gleam
pub type FindArgs {
  FindArgs(
    query: String,
    type_: Option(String),
    status: Option(String),
    tags: Option(List(String)),
    author: Option(String),
    limit: Int,
  )
}
```

Update `ListArgs` (lines 42-49):

```gleam
pub type ListArgs {
  ListArgs(
    type_: Option(String),
    status: Option(String),
    tags: Option(List(String)),
    author: Option(String),
    sort_by: Option(String),
  )
}
```

- [ ] **Step 2: Update decoders**

In `decode_find_args` (line 83-96), add after the tags line:

```gleam
use author <- decode.optional_field("author", None, decode.optional(decode.string))
```

And include `author: author` in the `FindArgs` constructor.

In `decode_list_args` (line 98-109), add after the tags line:

```gleam
use author <- decode.optional_field("author", None, decode.optional(decode.string))
```

And include `author: author` in the `ListArgs` constructor.

- [ ] **Step 3: Update build_filter to support author**

Update the `build_filter` function signature (line 161-164) to accept `author_filter: Option(String)`:

```gleam
fn build_filter(
  type_filter: Option(String),
  status_filter: Option(String),
  tags_filter: Option(List(String)),
  author_filter: Option(String),
) -> Option(json.Json) {
```

Add after the tags block (around line 199):

```gleam
let conditions = case author_filter {
  Some(a) -> [
    json.object([
      #("key", json.string("author")),
      #("match", json.object([#("value", json.string(a))])),
    ]),
    ..conditions
  ]
  None -> conditions
}
```

- [ ] **Step 4: Update call sites of build_filter**

In `handle_find` (around line 312):
```gleam
let filter = build_filter(args.type_, args.status, args.tags, args.author)
```

In `handle_list` (around line 392):
```gleam
let filter = build_filter(args.type_, args.status, args.tags, args.author)
```

Also update the `handle_list` fallback for `None` arguments (around line 387-389) to include `author`:
```gleam
let args = case request.arguments {
  None -> ListArgs(type_: None, status: None, tags: None, author: None, sort_by: None)
  Some(a) -> a
}
```

- [ ] **Step 5: Add author to result formatting**

In `handle_find` result formatting (around lines 327-360), add after the status line:

```gleam
let author_str = get_payload_string(hit.payload, "author")
```

And include in the output string:
```gleam
<> case author_str {
  "" -> ""
  a -> "- **Author:** " <> a <> "\n"
}
```

In `handle_list` result formatting (around lines 408-431), add:

```gleam
let author_str = get_payload_string(point.payload, "author")
```

And include in the output:
```gleam
<> case author_str {
  "" -> ""
  a -> " by " <> a
}
```

- [ ] **Step 6: Update tool schemas**

In `find_schema` (line 535-541), add `author` property to the JSON schema string:

```json
"author":{"type":"string","description":"Filter by author"}
```

In `list_schema` (line 543-549), add the same `author` property.

- [ ] **Step 7: Verify everything compiles and tests pass**

Run: `gleam test`
Expected: All tests PASS.

- [ ] **Step 8: Commit**

```bash
git add src/alex_memory/mcp/server.gleam
git commit -m "feat: add author filter to memory_find and memory_list"
```

---

### Task 11: End-to-end verification

**Files:** None (manual testing)

- [ ] **Step 1: Start infrastructure**

```bash
systemctl status ollama
docker compose -f /home/alex/dev/alex-memory/docker-compose.yml up -d
```

- [ ] **Step 2: Run the server locally to verify stdio still works**

```bash
cd /home/alex/dev/alex-memory
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"0.1"}}}' | gleam run 2>/dev/null
```

Expected: JSON response with server capabilities.

- [ ] **Step 3: Test HTTP health endpoint**

In a separate terminal while the server is running:

```bash
curl -s http://localhost:7890/health
```

Expected: `{"status":"ok"}`

- [ ] **Step 4: Run full test suite**

```bash
gleam test
```

Expected: All tests PASS.

- [ ] **Step 5: Commit any fixes, then tag**

```bash
git add -A
git commit -m "test: end-to-end verification of dual transport"
```
