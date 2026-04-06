# Canopy Phase 2: Query + MCP

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `canopy mcp` command that exposes an `ask_codebase` tool over MCP stdio, allowing LLM coding agents to ask natural language questions about an indexed codebase.

**Architecture:** The MCP server loads `.canopy.toml` from the current directory to get the EdgeQuake URL and document-to-file reverse map. It exposes a single `ask_codebase` tool that forwards questions to EdgeQuake's `/api/v1/query` endpoint, then enriches the response with file paths resolved from the local document ID tracking. The server uses `rmcp` (the official Rust MCP SDK) with stdio transport.

**Tech Stack:** Rust, rmcp (MCP SDK, includes schemars for JSON Schema), reqwest, tokio

**Spec:** `docs/superpowers/specs/2026-04-02-canopy-design.md` (in alex-memory repo)
**Phase 0 findings:** `~/dev/canopy/docs/phase0-findings.md`
**Phase 1 code:** `~/dev/canopy/` (working indexing pipeline)

**Prerequisites:** EdgeQuake running on localhost:8080, Phase 1 complete (canopy project with indexed documents)

---

## File Structure

```
~/dev/canopy/
├── Cargo.toml              # Add rmcp dep
├── src/
│   ├── main.rs             # Add Mcp subcommand
│   ├── lib.rs              # Add pub mod mcp
│   ├── edgequake.rs        # Add query() method + response types
│   ├── mcp.rs              # MCP server: CanopyServer + ask_codebase tool
│   ├── config.rs           # (unchanged)
│   ├── chunker.rs          # (unchanged)
│   └── git.rs              # (unchanged)
└── tests/
    ├── edgequake_query_test.rs  # Integration test for query API
    ├── chunker_test.rs          # (unchanged)
    └── config_test.rs           # (unchanged)
```

New modules:
- `edgequake.rs` gets `query()` method and response types (extending existing file)
- `mcp.rs` is the MCP server — holds `EdgeQuakeClient`, builds a reverse map from config to resolve file paths from source chunk IDs, exposes `ask_codebase` tool

---

## Chunk 1: EdgeQuake Query Client

### Task 1: Add Query Types and Method to EdgeQuakeClient

**Files:**
- Modify: `~/dev/canopy/src/edgequake.rs`
- Create: `~/dev/canopy/tests/edgequake_query_test.rs`

The EdgeQuake query API: `POST /api/v1/query` with JSON body `{"query": "...", "mode": "..."}`.

Response shape (confirmed in Phase 0 and live testing):
```json
{
    "answer": "synthesized text",
    "mode": "hybrid",
    "sources": [
        {
            "source_type": "entity",
            "id": "function_name",
            "score": 0.0,
            "snippet": "entity description",
            "reference_id": 1,
            "entity_type": "FUNCTION",
            "degree": 22,
            "source_chunk_ids": ["uuid-chunk-0"]
        }
    ],
    "stats": {
        "embedding_time_ms": 351,
        "retrieval_time_ms": 3,
        "generation_time_ms": 1691,
        "total_time_ms": 2051,
        "sources_retrieved": 117,
        "rerank_time_ms": 5,
        "tokens_used": 273,
        "tokens_per_second": 161.44,
        "llm_provider": "ollama",
        "llm_model": "gemma3:12b"
    },
    "reranked": true
}
```

- [ ] **Step 1: Write the failing integration test**

Create `~/dev/canopy/tests/edgequake_query_test.rs`:

```rust
use canopy::edgequake::EdgeQuakeClient;

/// Integration test — requires EdgeQuake running on localhost:8080
/// with canopy's own codebase indexed (run `canopy reindex` first if needed).
#[tokio::test]
async fn test_query_returns_answer() {
    let client = EdgeQuakeClient::new("http://localhost:8080");

    // Skip if EdgeQuake is not running
    if !client.health().await.unwrap_or(false) {
        eprintln!("Skipping: EdgeQuake not running");
        return;
    }

    let response = client.query("what structs exist in this codebase", "hybrid").await.unwrap();

    assert!(!response.answer.is_empty(), "answer should not be empty");
    assert_eq!(response.mode, "hybrid");
    assert!(!response.sources.is_empty(), "should have sources");
    assert!(response.stats.total_time_ms > 0, "stats should have timing");
}

#[tokio::test]
async fn test_query_modes() {
    let client = EdgeQuakeClient::new("http://localhost:8080");

    if !client.health().await.unwrap_or(false) {
        eprintln!("Skipping: EdgeQuake not running");
        return;
    }

    for mode in &["hybrid", "local", "global", "naive"] {
        let response = client.query("what functions exist", mode).await.unwrap();
        assert_eq!(response.mode, *mode, "response mode should match request");
        assert!(!response.answer.is_empty(), "answer should not be empty for mode {mode}");
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/dev/canopy && cargo test --test edgequake_query_test -- --nocapture 2>&1 | head -30`

Expected: Compilation error — `EdgeQuakeClient` has no `query` method and no `QueryResponse` type.

- [ ] **Step 3: Add query response types and method to edgequake.rs**

Add the following to the bottom of `~/dev/canopy/src/edgequake.rs`, after the existing `delete` method's closing brace but still inside `impl EdgeQuakeClient`:

```rust
    pub async fn query(&self, question: &str, mode: &str) -> Result<QueryResponse> {
        let body = serde_json::json!({
            "query": question,
            "mode": mode,
        });
        let resp = self
            .client
            .post(format!("{}/api/v1/query", self.base_url))
            .json(&body)
            .send()
            .await
            .context("Failed to query EdgeQuake")?;

        let status = resp.status();
        if status.is_success() {
            Ok(resp.json().await?)
        } else {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("EdgeQuake query failed ({}): {}", status, body)
        }
    }
```

Add these structs after the existing `DeleteResponse` struct (outside the `impl` block):

```rust
#[derive(Debug, Deserialize)]
pub struct QueryResponse {
    pub answer: String,
    pub mode: String,
    #[serde(default)]
    pub sources: Vec<QuerySource>,
    #[serde(default)]
    pub stats: QueryStats,
    #[serde(default)]
    pub reranked: bool,
}

#[derive(Debug, Deserialize)]
pub struct QuerySource {
    pub source_type: String,
    pub id: String,
    #[serde(default)]
    pub score: f64,
    #[serde(default)]
    pub snippet: String,
    #[serde(default)]
    pub reference_id: u64,
    #[serde(default)]
    pub entity_type: String,
    #[serde(default)]
    pub degree: u64,
    #[serde(default)]
    pub source_chunk_ids: Vec<String>,
}

#[derive(Debug, Default, Deserialize)]
pub struct QueryStats {
    #[serde(default)]
    pub embedding_time_ms: u64,
    #[serde(default)]
    pub retrieval_time_ms: u64,
    #[serde(default)]
    pub generation_time_ms: u64,
    #[serde(default)]
    pub total_time_ms: u64,
    #[serde(default)]
    pub sources_retrieved: u64,
    #[serde(default)]
    pub rerank_time_ms: u64,
    #[serde(default)]
    pub tokens_used: u64,
    #[serde(default)]
    pub tokens_per_second: f64,
    #[serde(default)]
    pub llm_provider: String,
    #[serde(default)]
    pub llm_model: String,
}
```

Also add `use serde::Serialize;` to the top of the file (alongside existing `Deserialize` import), and add `Serialize` derive to `QueryResponse`, `QuerySource`, and `QueryStats` — the MCP server will need to serialize these for the tool response.

Updated import line: `use serde::{Deserialize, Serialize};`

Updated derives:
- `#[derive(Debug, Serialize, Deserialize)]` for `QueryResponse`
- `#[derive(Debug, Serialize, Deserialize)]` for `QuerySource`
- `#[derive(Debug, Default, Serialize, Deserialize)]` for `QueryStats`

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ~/dev/canopy && cargo test --test edgequake_query_test -- --nocapture 2>&1 | tail -20`

Expected: Both tests pass (assuming EdgeQuake is running with indexed data).

- [ ] **Step 5: Commit**

```bash
cd ~/dev/canopy
git add src/edgequake.rs tests/edgequake_query_test.rs
git commit -m "feat: add query method to EdgeQuakeClient

POST /api/v1/query with mode support (hybrid, local, global, naive).
Response types: QueryResponse, QuerySource, QueryStats."
```

---

## Chunk 2: MCP Server

### Task 2: Update Cargo.toml with MCP Dependencies

**Files:**
- Modify: `~/dev/canopy/Cargo.toml`

- [ ] **Step 1: Add rmcp and schemars to dependencies**

Add these lines to the `[dependencies]` section in `~/dev/canopy/Cargo.toml`:

```toml
rmcp = { version = "1", features = ["server", "macros", "transport-io"] }
```

Note: `schemars` is not needed as a direct dependency — rmcp re-exports it as `rmcp::schemars`.

- [ ] **Step 2: Verify it compiles**

Run: `cd ~/dev/canopy && cargo check 2>&1 | tail -10`

Expected: No errors. rmcp and schemars downloaded and linked.

- [ ] **Step 3: Commit**

```bash
cd ~/dev/canopy
git add Cargo.toml Cargo.lock
git commit -m "deps: add rmcp for MCP server"
```

### Task 3: Create MCP Server Module

**Files:**
- Create: `~/dev/canopy/src/mcp.rs`
- Modify: `~/dev/canopy/src/lib.rs`

The MCP server exposes one tool: `ask_codebase(question, mode?)`. It loads `.canopy.toml` to get the EdgeQuake URL and builds a reverse map from document IDs to file paths so it can enrich query results with source file locations.

The `source_chunk_ids` from EdgeQuake look like `"7e5cfd98-...-chunk-0"`. The document UUID is the prefix before `-chunk-`. The config's `documents` map stores `file_path -> [document_ids]`. We reverse this to `document_id -> file_path` at startup.

- [ ] **Step 1: Add module declaration to lib.rs**

Add `pub mod mcp;` to `~/dev/canopy/src/lib.rs` (after the existing module declarations).

- [ ] **Step 2: Create the MCP server module**

Create `~/dev/canopy/src/mcp.rs`:

```rust
use crate::config::Config;
use crate::edgequake::{EdgeQuakeClient, QueryResponse};
use rmcp::handler::server::tool::ToolRouter;
use rmcp::handler::server::wrapper::Parameters;
use rmcp::model::{Implementation, ProtocolVersion, ServerCapabilities, ServerInfo};
use rmcp::{schemars, tool, tool_router};
use serde::Deserialize;
use std::collections::HashMap;

pub struct CanopyServer {
    tool_router: ToolRouter<Self>,
    eq_client: EdgeQuakeClient,
    /// Reverse map: document_id -> file_path (built from config.documents)
    doc_to_file: HashMap<String, String>,
}

#[derive(Deserialize, schemars::JsonSchema)]
pub struct AskCodebaseParams {
    /// The natural language question to ask about the codebase
    pub question: String,
    /// Query mode: "hybrid" (default, recommended), "local", "global", or "naive"
    pub mode: Option<String>,
}

#[tool_router]
impl CanopyServer {
    #[tool(
        name = "ask_codebase",
        description = "Ask a natural language question about the indexed codebase. Returns a synthesized answer with source references. Use 'hybrid' mode (default) for best results."
    )]
    async fn ask_codebase(
        &self,
        Parameters(params): Parameters<AskCodebaseParams>,
    ) -> Result<String, String> {
        let mode = params.mode.as_deref().unwrap_or("hybrid");
        let response = self
            .eq_client
            .query(&params.question, mode)
            .await
            .map_err(|e| format!("Query failed: {e}"))?;
        Ok(self.format_response(&response))
    }
}

impl CanopyServer {
    pub fn new(config: &Config) -> Self {
        let eq_client = EdgeQuakeClient::new(&config.project.edgequake_url);
        let doc_to_file = build_reverse_map(&config.documents);
        Self {
            tool_router: Self::tool_router(),
            eq_client,
            doc_to_file,
        }
    }

    fn format_response(&self, response: &QueryResponse) -> String {
        let mut out = String::new();

        // Answer
        out.push_str(&response.answer);

        // Source files (deduplicated, resolved from chunk IDs)
        let file_paths = self.resolve_source_files(response);
        if !file_paths.is_empty() {
            out.push_str("\n\n---\n**Source files:**\n");
            for path in &file_paths {
                out.push_str(&format!("- {path}\n"));
            }
        }

        // Stats footer
        out.push_str(&format!(
            "\n_Query: {}ms | {} sources | mode: {}_",
            response.stats.total_time_ms,
            response.sources.len(),
            response.mode,
        ));

        out
    }

    /// Resolve source chunk IDs to file paths using the reverse document map.
    /// source_chunk_ids look like "uuid-chunk-0" — extract the UUID prefix,
    /// then look up in doc_to_file.
    fn resolve_source_files(&self, response: &QueryResponse) -> Vec<String> {
        let mut seen = std::collections::HashSet::new();
        let mut paths = Vec::new();

        for source in &response.sources {
            for chunk_id in &source.source_chunk_ids {
                // Extract document UUID: everything before "-chunk-"
                let doc_id = chunk_id
                    .rfind("-chunk-")
                    .map(|i| &chunk_id[..i])
                    .unwrap_or(chunk_id);

                if let Some(file_path) = self.doc_to_file.get(doc_id) {
                    if seen.insert(file_path.clone()) {
                        paths.push(file_path.clone());
                    }
                }
            }
        }

        paths
    }
}

#[rmcp::tool_handler]
impl rmcp::ServerHandler for CanopyServer {
    fn get_info(&self) -> ServerInfo {
        ServerInfo {
            protocol_version: ProtocolVersion::V_2025_03_26,
            capabilities: ServerCapabilities::builder()
                .enable_tools()
                .build(),
            server_info: Implementation::from_build_env(),
            instructions: Some(
                "Canopy provides semantic code search. Use ask_codebase to ask questions about the indexed codebase.".into(),
            ),
        }
    }
}

/// Build a reverse map from document_id -> file_path.
/// Config stores file_path -> [document_ids].
fn build_reverse_map(documents: &HashMap<String, Vec<String>>) -> HashMap<String, String> {
    let mut reverse = HashMap::new();
    for (file_path, doc_ids) in documents {
        for doc_id in doc_ids {
            reverse.insert(doc_id.clone(), file_path.clone());
        }
    }
    reverse
}
```

- [ ] **Step 3: Verify it compiles**

Run: `cd ~/dev/canopy && cargo check 2>&1 | tail -20`

Expected: Clean compilation. If there are import path issues with rmcp types, adjust the use statements to match the actual rmcp API. Common fixes:
- `rmcp::model::ServerInfo` might be at a different path — check `cargo doc --open` if needed
- `ServerCapabilities::builder()` pattern may differ — the key is enabling tool capabilities
- `Implementation::from_build_env()` auto-generates name/version from Cargo.toml

- [ ] **Step 4: Run all existing tests to ensure nothing broke**

Run: `cd ~/dev/canopy && cargo test 2>&1 | tail -20`

Expected: All existing tests still pass.

- [ ] **Step 5: Commit**

```bash
cd ~/dev/canopy
git add src/lib.rs src/mcp.rs
git commit -m "feat: add MCP server module with ask_codebase tool

CanopyServer loads config, builds doc-to-file reverse map,
exposes ask_codebase(question, mode?) via rmcp tool_router.
Resolves source chunk IDs to file paths in responses."
```

### Task 4: Add `canopy mcp` CLI Subcommand

**Files:**
- Modify: `~/dev/canopy/src/main.rs`

- [ ] **Step 1: Add the Mcp variant to the Commands enum**

In `~/dev/canopy/src/main.rs`, add to the `Commands` enum (after the `Status` variant):

```rust
    /// Start MCP server (stdio transport) for agent integration
    Mcp,
```

- [ ] **Step 2: Add the match arm in main**

In the `match cli.command` block in `main()`, add:

```rust
        Commands::Mcp => cmd_mcp().await,
```

- [ ] **Step 3: Add the cmd_mcp function**

Add this function to `~/dev/canopy/src/main.rs` (after the `cmd_status` function). Add `use canopy::mcp::CanopyServer;` to the imports at the top.

```rust
async fn cmd_mcp() -> Result<()> {
    let cwd = std::env::current_dir()?;
    let repo_root = git::find_root(&cwd)?;
    let config_path = repo_root.join(".canopy.toml");

    if !config_path.exists() {
        anyhow::bail!("Not a canopy project. Run `canopy init` first.");
    }

    let config = Config::load(&config_path)?;
    let server = CanopyServer::new(&config);

    let transport = rmcp::transport::io::stdio();
    let service = rmcp::serve_server(server, transport).await?;
    service.waiting().await?;

    Ok(())
}
```

- [ ] **Step 4: Verify it compiles**

Run: `cd ~/dev/canopy && cargo check 2>&1 | tail -10`

Expected: Clean compilation.

- [ ] **Step 5: Verify the MCP subcommand is registered**

Run: `cd ~/dev/canopy && cargo run -- --help 2>&1`

Expected output includes:
```
Commands:
  init     Initialize canopy for a git repository
  index    Index changes since last indexed commit
  reindex  Full re-index of the entire repository
  status   Show project status
  mcp      Start MCP server (stdio transport) for agent integration
```

- [ ] **Step 6: Commit**

```bash
cd ~/dev/canopy
git add src/main.rs
git commit -m "feat: add canopy mcp subcommand

Starts MCP stdio server exposing ask_codebase tool.
Loads .canopy.toml for EdgeQuake URL and file path resolution."
```

### Task 5: Smoke Test MCP Server

Verify the MCP server starts and responds to the MCP protocol handshake.

- [ ] **Step 1: Build the binary**

Run: `cd ~/dev/canopy && cargo build 2>&1 | tail -5`

Expected: Successful build.

- [ ] **Step 2: Test MCP handshake via stdio**

Run this command which sends an MCP initialize request via stdin and checks stdout for a response. Uses the compiled binary (not `cargo run`) to avoid timeout counting compilation time.

```bash
cd ~/dev/canopy && echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"0.1.0"}}}' | timeout 10 ./target/debug/canopy mcp 2>/dev/null | head -1
```

Expected: A JSON response containing `"result"` with server info and capabilities including tools.

> **Note:** This pipes input then closes stdin (EOF). The server may exit before flushing output. If you get empty output, that's a buffering/timing issue, not a bug — Task 6 Step 3 (testing with Claude Code as a real MCP client) is the definitive test.

- [ ] **Step 3: Test tools/list via stdio**

```bash
cd ~/dev/canopy && printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"0.1.0"}}}\n{"jsonrpc":"2.0","method":"notifications/initialized"}\n{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}\n' | timeout 10 ./target/debug/canopy mcp 2>/dev/null
```

Expected: Response includes `ask_codebase` in the tools list with its JSON Schema (question: required string, mode: optional string). Same EOF caveat as Step 2 applies.

- [ ] **Step 4: Commit (tag Phase 2 complete)**

```bash
cd ~/dev/canopy
git commit --allow-empty -m "milestone: Phase 2 complete — MCP server with ask_codebase tool

canopy mcp starts stdio MCP server exposing ask_codebase(question, mode?).
Queries EdgeQuake graph RAG, resolves source chunk IDs to file paths."
```

### Task 6: Configure for Claude Code Integration

This task sets up canopy as an MCP server in Claude Code so agents can use `ask_codebase` on indexed projects.

- [ ] **Step 1: Build release binary**

Run: `cd ~/dev/canopy && cargo build --release 2>&1 | tail -5`

The binary will be at `~/dev/canopy/target/release/canopy`.

- [ ] **Step 2: Add to Claude Code MCP settings**

Add a canopy MCP server configuration. The MCP server needs to run from within the project directory so it can find `.canopy.toml`. For a project like Atlas at `~/dev/atlas/`:

In `~/.claude/settings.json` (or project-level `.claude/settings.json`), add to the `mcpServers` section:

```json
{
  "mcpServers": {
    "canopy": {
      "command": "/home/alex/dev/canopy/target/release/canopy",
      "args": ["mcp"],
      "cwd": "/home/alex/dev/atlas"
    }
  }
}
```

Adjust `cwd` to point to whichever project has been indexed with `canopy init`.

- [ ] **Step 3: Test with Claude Code**

Start a Claude Code session in the Atlas project and ask a question that exercises the tool:

```
Use the ask_codebase tool to find out how CSS properties flow from parsing to rendering
```

Verify:
- The tool call succeeds
- The answer is synthesized and relevant
- Source files are listed
- Stats footer shows timing

- [ ] **Step 4: Commit configuration (if project-level)**

If you added a project-level `.claude/settings.json` in the target project:

```bash
cd ~/dev/atlas  # or whichever project
git add .claude/settings.json
git commit -m "config: add canopy MCP server for semantic code search"
```
