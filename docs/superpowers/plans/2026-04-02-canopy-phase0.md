# Canopy Phase 0: Prototype EdgeQuake Boundary

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate three assumptions about EdgeQuake before building the full Canopy CLI: (1) pre-chunked code ingests without double-chunking, (2) documents can be deleted by file path, (3) entity extraction on Rust source code produces useful graph structure.

**Architecture:** A throwaway Rust binary (`canopy-proto`) that exercises EdgeQuake's REST API against synthetic Rust sample code. EdgeQuake runs via Docker Compose on archbtw alongside the existing Ollama service. Results are documented in a findings report that gates Phase 1.

**Tech Stack:** Rust (reqwest, tokio, clap, serde), Docker Compose, EdgeQuake, PostgreSQL (AGE + pgvector), Ollama (nomic-embed-text, qwen2.5-coder:7b)

**Spec:** `docs/superpowers/specs/2026-04-02-canopy-design.md`

---

## Chunk 1: Infrastructure, Prototype, and Validation

### Task 1: Pull Ollama Models

Ensure the required models are available on the host Ollama instance before starting EdgeQuake.

**Files:** None (host commands only)

- [ ] **Step 1: Pull the embedding model**

Run:
```bash
ollama pull nomic-embed-text
```

Expected: Model downloads (or reports "already exists").

- [ ] **Step 2: Pull the code LLM**

Run:
```bash
ollama pull qwen2.5-coder:7b
```

Expected: Model downloads (or reports "already exists").

- [ ] **Step 3: Verify models are available**

Run:
```bash
ollama list | grep -E "nomic-embed-text|qwen2.5-coder"
```

Expected: Both models listed with sizes.

---

### Task 2: Deploy EdgeQuake via Docker Compose

Clone EdgeQuake's repository and start services using their official Docker Compose configuration.

**Files:**
- Create: `~/dev/edgequake/.env` (local override)

- [ ] **Step 1: Clone the EdgeQuake repository**

Run:
```bash
git clone https://github.com/raphaelmansuy/edgequake.git ~/dev/edgequake
```

Expected: Repository clones successfully.

- [ ] **Step 2: Create environment file**

The official `docker-compose.yml` in `~/dev/edgequake/docker/` already has the service definitions with `host.docker.internal` for Ollama on Linux. Create a `.env` file to set the LLM provider and model:

Create `~/dev/edgequake/docker/.env`:
```env
EDGEQUAKE_LLM_PROVIDER=ollama
OLLAMA_HOST=http://host.docker.internal:11434
POSTGRES_PASSWORD=edgequake_secret
```

- [ ] **Step 3: Start services**

Run:
```bash
cd ~/dev/edgequake/docker && docker compose up -d
```

Expected: Three containers start: `postgres`, `edgequake`, `frontend`. The postgres container may take a moment to build (it compiles Apache AGE from source).

- [ ] **Step 4: Wait for health**

Run:
```bash
sleep 15 && curl -s http://localhost:8080/health | python3 -m json.tool
```

Expected: JSON response with healthy status. If it fails, check `docker compose logs edgequake` for connection issues (especially Ollama connectivity and PostgreSQL readiness).

- [ ] **Step 5: Verify the web UI loads**

Open `http://localhost:3000` in a browser. You should see the EdgeQuake dashboard.

- [ ] **Step 6: Check Ollama connectivity from EdgeQuake**

Run:
```bash
docker compose logs edgequake 2>&1 | grep -i ollama | tail -5
```

Expected: No connection errors. If you see "connection refused" for Ollama, verify `extra_hosts` is set in the compose file and Ollama is listening on `0.0.0.0:11434` (not just `127.0.0.1`). Check Ollama's systemd config:

```bash
# If needed, edit Ollama to bind to all interfaces:
# sudo systemctl edit ollama
# Add: Environment="OLLAMA_HOST=0.0.0.0"
# Then: sudo systemctl restart ollama
```

---

### Task 3: Create Canopy Prototype Project

**Files:**
- Create: `~/dev/canopy/Cargo.toml`
- Create: `~/dev/canopy/src/main.rs`

- [ ] **Step 1: Initialize the Rust project**

Run:
```bash
cargo init ~/dev/canopy --name canopy-proto
```

- [ ] **Step 2: Add dependencies**

Replace `~/dev/canopy/Cargo.toml` with:

```toml
[package]
name = "canopy-proto"
version = "0.1.0"
edition = "2021"

[dependencies]
anyhow = "1"
clap = { version = "4", features = ["derive"] }
reqwest = { version = "0.12", features = ["json"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tokio = { version = "1", features = ["full"] }
```

- [ ] **Step 3: Write initial main.rs with health check**

Replace `~/dev/canopy/src/main.rs` with:

```rust
use anyhow::{Context, Result};
use clap::{Parser, Subcommand};

const BASE_URL: &str = "http://localhost:8080";

#[derive(Parser)]
#[command(name = "canopy-proto", about = "Canopy Phase 0 — EdgeQuake boundary prototype")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Check EdgeQuake server health
    Health,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    let client = reqwest::Client::new();

    match cli.command {
        Commands::Health => health(&client).await?,
    }

    Ok(())
}

async fn health(client: &reqwest::Client) -> Result<()> {
    let resp = client
        .get(format!("{BASE_URL}/health"))
        .send()
        .await
        .context("Failed to connect to EdgeQuake")?;
    println!("Status: {}", resp.status());
    let body: serde_json::Value = resp.json().await?;
    println!("{}", serde_json::to_string_pretty(&body)?);
    Ok(())
}
```

- [ ] **Step 4: Build and run health check**

Run:
```bash
cd ~/dev/canopy && cargo run -- health
```

Expected: `Status: 200` followed by JSON with EdgeQuake health info.

- [ ] **Step 5: Initialize git and commit**

Run:
```bash
cd ~/dev/canopy && git init && git add -A && git commit -m "init: canopy phase 0 prototype"
```

---

### Task 3b: Explore EdgeQuake API Surface

Before writing any integration code, inspect the actual API to confirm our assumptions about endpoints, request formats, and response schemas.

**Files:** None

- [ ] **Step 1: Open the Swagger UI**

Open `http://localhost:8080/swagger-ui` in a browser. This shows every available endpoint with request/response schemas.

- [ ] **Step 2: Confirm these endpoints exist and note any differences**

Check for:
- `POST /api/v1/documents` — does it accept `content`, `title`, `metadata` as JSON fields?
- `GET /api/v1/documents` — does it support `document_pattern` query parameter?
- `DELETE /api/v1/documents/{id}` — exists?
- `GET /api/v1/graph` — exists? What does it return?
- `POST /api/v1/query` — does it accept `query` and `mode` fields?
- `POST /api/v1/tenants/default/workspaces` — exists? Does it accept `chunking_config`?

If any endpoint is different from what's in this plan, adapt the code in subsequent tasks accordingly. The Swagger UI is the source of truth — all API calls below are based on research and may need adjustment.

**Note on SDK:** The spec mentions using `edgequake-sdk` (v0.3.0). This plan uses raw `reqwest` for transparency during prototyping — we want to see the actual HTTP requests and responses. Phase 1 can evaluate whether the SDK simplifies things.

---

### Task 4: Create Workspace with Large Chunk Size

EdgeQuake chunks ingested documents by default (1200 tokens, 100 overlap). We prevent double-chunking by creating a workspace with a very large chunk size so our pre-chunked code passes through as a single chunk.

**Files:**
- Modify: `~/dev/canopy/src/main.rs`

- [ ] **Step 1: Add CreateWorkspace subcommand**

Add to the `Commands` enum in `src/main.rs`:

```rust
/// Create a workspace with large chunk size to prevent double-chunking
CreateWorkspace {
    /// Workspace name
    name: String,
},
```

Add to the match block:

```rust
Commands::CreateWorkspace { name } => create_workspace(&client, &name).await?,
```

Add the handler function:

```rust
async fn create_workspace(client: &reqwest::Client, name: &str) -> Result<()> {
    let body = serde_json::json!({
        "name": name,
        "chunking_config": {
            "chunk_size": 100000,
            "chunk_overlap": 0,
            "min_chunk_size": 1,
            "preserve_sentences": false
        }
    });
    let resp = client
        .post(format!("{BASE_URL}/api/v1/tenants/default/workspaces"))
        .json(&body)
        .send()
        .await
        .context("Failed to create workspace")?;
    println!("Status: {}", resp.status());
    let result: serde_json::Value = resp.json().await?;
    println!("{}", serde_json::to_string_pretty(&result)?);
    println!("\n==> Save the workspace ID from the response for subsequent commands.");
    Ok(())
}
```

- [ ] **Step 2: Run it**

Run:
```bash
cd ~/dev/canopy && cargo run -- create-workspace canopy-test
```

Expected: 200/201 with JSON containing the workspace ID and the chunking config we specified. Save the workspace ID — you'll need it.

**If this endpoint doesn't exist or returns 404:** The workspace/tenant API may differ from what we expect. Check EdgeQuake's Swagger UI at `http://localhost:8080/swagger-ui` to find the correct endpoint. Adapt the code accordingly and document the finding.

- [ ] **Step 3: Commit**

Run:
```bash
cd ~/dev/canopy && git add -A && git commit -m "feat: add create-workspace command"
```

---

### Task 5: Create Sample Rust Code

Create synthetic Rust files with known relationships so we can verify entity extraction finds them.

**Files:**
- Create: `~/dev/canopy/samples/types.rs`
- Create: `~/dev/canopy/samples/renderer.rs`
- Create: `~/dev/canopy/samples/gpu.rs`

- [ ] **Step 1: Create samples directory**

Run:
```bash
mkdir -p ~/dev/canopy/samples
```

- [ ] **Step 2: Create types.rs**

Create `~/dev/canopy/samples/types.rs`:

```rust
/// Color represented as RGBA float values.
pub struct Color {
    pub r: f32,
    pub g: f32,
    pub b: f32,
    pub a: f32,
}

impl Color {
    pub fn white() -> Self {
        Self { r: 1.0, g: 1.0, b: 1.0, a: 1.0 }
    }

    pub fn transparent() -> Self {
        Self { r: 0.0, g: 0.0, b: 0.0, a: 0.0 }
    }
}

/// Style configuration for blob rendering.
/// Used by BlobRenderer to control appearance of each blob.
pub struct BlobStyle {
    pub color: Color,
    pub opacity: f32,
    pub border_radius: f32,
}

impl Default for BlobStyle {
    fn default() -> Self {
        Self {
            color: Color::white(),
            opacity: 1.0,
            border_radius: 0.0,
        }
    }
}
```

- [ ] **Step 3: Create renderer.rs**

Create `~/dev/canopy/samples/renderer.rs`:

```rust
use crate::types::BlobStyle;
use crate::gpu::GpuContext;

/// Manages a collection of blob styles and renders them to the GPU.
/// The main entry point for the blob rendering pipeline.
pub struct BlobRenderer {
    styles: Vec<BlobStyle>,
    frame_count: u64,
}

impl BlobRenderer {
    pub fn new() -> Self {
        Self {
            styles: Vec::new(),
            frame_count: 0,
        }
    }

    /// Add a style to be rendered in the next frame.
    pub fn add_style(&mut self, style: BlobStyle) {
        self.styles.push(style);
    }

    /// Render all blobs to the GPU context.
    /// Increments the frame counter and issues draw calls for each style.
    pub fn render(&mut self, gpu: &mut GpuContext) {
        self.frame_count += 1;
        for style in &self.styles {
            gpu.draw_blob(style);
        }
        gpu.flush();
    }

    /// Clear all styles for the next frame.
    pub fn clear(&mut self) {
        self.styles.clear();
    }
}
```

- [ ] **Step 4: Create gpu.rs**

Create `~/dev/canopy/samples/gpu.rs`:

```rust
use crate::types::BlobStyle;

/// Low-level GPU context for issuing draw calls.
/// Abstracts the graphics pipeline for blob rendering.
pub struct GpuContext {
    draw_calls: u32,
    shader_bound: bool,
}

impl GpuContext {
    pub fn new() -> Self {
        Self {
            draw_calls: 0,
            shader_bound: false,
        }
    }

    /// Bind the blob shader program. Must be called before draw_blob.
    pub fn bind_shader(&mut self) {
        self.shader_bound = true;
    }

    /// Issue a draw call for a single blob with the given style.
    /// Applies color and opacity from the BlobStyle to the GPU pipeline.
    pub fn draw_blob(&mut self, style: &BlobStyle) {
        if !self.shader_bound {
            self.bind_shader();
        }
        self.draw_calls += 1;
        // Apply style.color (RGBA) and style.opacity to uniform buffer
        // Issue instanced draw call for blob geometry
    }

    /// Flush all pending draw calls to the GPU.
    pub fn flush(&mut self) {
        self.draw_calls = 0;
    }
}
```

- [ ] **Step 5: Commit**

Run:
```bash
cd ~/dev/canopy && git add -A && git commit -m "feat: add sample Rust files for validation"
```

**Known relationships to verify later:**
- `BlobRenderer` uses `BlobStyle` (from types.rs)
- `BlobRenderer` uses `GpuContext` (from gpu.rs)
- `GpuContext.draw_blob()` takes `&BlobStyle` parameter
- `BlobStyle` contains `Color`
- `BlobRenderer.render()` calls `GpuContext.draw_blob()` and `GpuContext.flush()`
- `Color` has constructors `white()` and `transparent()`

---

### Task 6: Validate Ingestion (Single Chunk, No Double-Chunking)

Send a single sample file to EdgeQuake and verify it's stored as exactly one chunk.

**Files:**
- Modify: `~/dev/canopy/src/main.rs`

- [ ] **Step 1: Add Ingest subcommand**

Add to the `Commands` enum:

```rust
/// Ingest a source file as a single document
Ingest {
    /// Path to the source file
    file: String,
    /// Workspace ID (from create-workspace output)
    #[arg(long)]
    workspace: Option<String>,
},
```

Add to the match block:

```rust
Commands::Ingest { file, workspace } => ingest(&client, &file, workspace.as_deref()).await?,
```

Add the handler function:

```rust
async fn ingest(client: &reqwest::Client, file: &str, workspace: Option<&str>) -> Result<()> {
    let content = std::fs::read_to_string(file)
        .with_context(|| format!("Failed to read {file}"))?;

    // Use the file path as a title prefix so we can find/delete documents by file later
    let title = format!("chunk::{file}");

    let body = serde_json::json!({
        "content": content,
        "title": title,
        "metadata": {
            "file_path": file,
            "language": "rust",
            "chunk_type": "full_file"
        }
    });

    let mut req = client.post(format!("{BASE_URL}/api/v1/documents"));
    if let Some(ws) = workspace {
        req = req.header("X-Workspace-Id", ws);
    }

    let resp = req
        .json(&body)
        .send()
        .await
        .context("Failed to ingest document")?;

    println!("Status: {}", resp.status());
    let result: serde_json::Value = resp.json().await?;
    println!("{}", serde_json::to_string_pretty(&result)?);

    if let Some(chunk_count) = result.get("chunk_count") {
        println!("\n==> VALIDATION: chunk_count = {chunk_count}");
        println!("    Expected: 1 (no double-chunking)");
        if chunk_count.as_u64() == Some(1) {
            println!("    PASS");
        } else {
            println!("    FAIL — EdgeQuake re-chunked our content");
        }
    }

    if let Some(entity_count) = result.get("entity_count") {
        println!("    entity_count = {entity_count}");
    }
    if let Some(rel_count) = result.get("relationship_count") {
        println!("    relationship_count = {rel_count}");
    }

    Ok(())
}
```

- [ ] **Step 2: Build and ingest types.rs**

Run:
```bash
cd ~/dev/canopy && cargo run -- ingest samples/types.rs
```

Expected: `chunk_count = 1` (PASS). If this fails and shows `chunk_count > 1`, retry with the workspace flag:

```bash
cargo run -- ingest samples/types.rs --workspace YOUR_WORKSPACE_ID
```

If it still double-chunks even with the large chunk_size workspace, document the finding — we need a different approach (possibly a lower-level API or custom chunking strategy).

- [ ] **Step 3: Check entity extraction results**

The response should show `entity_count > 0` and `relationship_count >= 0`. Even a single file should produce entities like `Color`, `BlobStyle`, `Default`. If `entity_count = 0`, check EdgeQuake logs:

```bash
cd ~/dev/edgequake/docker && docker compose logs edgequake 2>&1 | tail -20
```

Common issue: Ollama model not found. Make sure EdgeQuake is configured to use `qwen2.5-coder:7b` (check the environment variables or EdgeQuake's settings UI).

- [ ] **Step 4: Commit**

Run:
```bash
cd ~/dev/canopy && git add -A && git commit -m "feat: add ingest command, validate single-chunk ingestion"
```

---

### Task 7: Validate Multi-Chunk Ingestion and Entity Extraction Quality

Ingest all three sample files and evaluate whether EdgeQuake discovers the relationships between them.

**Files:**
- Modify: `~/dev/canopy/src/main.rs`

- [ ] **Step 1: Ingest the remaining two sample files**

`samples/types.rs` was already ingested in Task 6. Ingest the other two:

Run:
```bash
cd ~/dev/canopy
cargo run -- ingest samples/renderer.rs
cargo run -- ingest samples/gpu.rs
```

(Add `--workspace YOUR_WORKSPACE_ID` to each if needed based on Task 6 results.)

Expected: Each returns `chunk_count = 1`, `entity_count > 0`.

- [ ] **Step 2: Add Explore subcommand**

Add to the `Commands` enum:

```rust
/// Explore the knowledge graph (entities and relationships)
Explore,
```

Add to the match block:

```rust
Commands::Explore => explore(&client).await?,
```

Add the handler function:

```rust
async fn explore(client: &reqwest::Client) -> Result<()> {
    // List entities
    let resp = client
        .get(format!("{BASE_URL}/api/v1/graph"))
        .send()
        .await
        .context("Failed to fetch graph")?;
    let result: serde_json::Value = resp.json().await?;

    println!("=== GRAPH EXPLORATION ===\n");

    if let Some(entities) = result.get("entities").and_then(|e| e.as_array()) {
        println!("Entities ({}):", entities.len());
        for entity in entities {
            let name = entity.get("name").and_then(|n| n.as_str()).unwrap_or("?");
            let etype = entity.get("type").and_then(|t| t.as_str()).unwrap_or("?");
            let desc = entity.get("description").and_then(|d| d.as_str()).unwrap_or("");
            println!("  [{etype}] {name}");
            if !desc.is_empty() {
                println!("          {desc}");
            }
        }
    } else {
        println!("No 'entities' field in response. Raw response:");
        println!("{}", serde_json::to_string_pretty(&result)?);
        println!("\nCheck the Swagger UI at http://localhost:8080/swagger-ui for the correct graph endpoint.");
    }

    if let Some(rels) = result.get("relationships").and_then(|r| r.as_array()) {
        println!("\nRelationships ({}):", rels.len());
        for rel in rels {
            let src = rel.get("source").and_then(|s| s.as_str()).unwrap_or("?");
            let tgt = rel.get("target").and_then(|t| t.as_str()).unwrap_or("?");
            let rtype = rel.get("type").and_then(|t| t.as_str()).unwrap_or("?");
            println!("  {src} --[{rtype}]--> {tgt}");
        }
    }

    println!("\n==> Also check the EdgeQuake web UI at http://localhost:3000 for visual graph inspection.");

    Ok(())
}
```

- [ ] **Step 3: Run explore and evaluate**

Run:
```bash
cd ~/dev/canopy && cargo run -- explore
```

**Evaluate against known relationships:**

| Expected relationship | Found? |
|----------------------|--------|
| BlobRenderer uses BlobStyle | |
| BlobRenderer uses GpuContext | |
| GpuContext.draw_blob takes BlobStyle | |
| BlobStyle contains Color | |
| BlobRenderer.render calls GpuContext methods | |
| BlobStyle implements Default | |

**Scoring:**
- **4+ found:** Excellent — entity extraction works well on code
- **2-3 found:** Acceptable — graph RAG adds value over pure vector search
- **0-1 found:** Poor — entity extraction on code is not working; consider whether pure vector search (naive mode) is sufficient, or investigate prompt tuning for the entity extraction LLM

Also open the EdgeQuake web UI at `http://localhost:3000` and visually inspect the graph. Screenshot it for the findings document.

- [ ] **Step 4: Commit**

Run:
```bash
cd ~/dev/canopy && git add -A && git commit -m "feat: add explore command, validate entity extraction quality"
```

---

### Task 8: Validate Deletion by File Path

Test the delete-and-replace workflow: find documents by their title (which contains the file path), delete them, verify they're gone.

**Files:**
- Modify: `~/dev/canopy/src/main.rs`

- [ ] **Step 1: Add ListDocs and Delete subcommands**

Add to the `Commands` enum:

```rust
/// List all documents (optionally filtered by title pattern)
ListDocs {
    /// Filter by title pattern (optional)
    #[arg(long)]
    pattern: Option<String>,
},
/// Delete all documents matching a file path
Delete {
    /// File path to match (searches document titles for "chunk::<path>")
    file_path: String,
},
```

Add to the match block:

```rust
Commands::ListDocs { pattern } => list_docs(&client, pattern.as_deref()).await?,
Commands::Delete { file_path } => delete_by_path(&client, &file_path).await?,
```

Add the handler functions:

```rust
async fn list_docs(client: &reqwest::Client, pattern: Option<&str>) -> Result<()> {
    let mut url = format!("{BASE_URL}/api/v1/documents");
    if let Some(p) = pattern {
        url = format!("{url}?document_pattern={p}");
    }
    let resp = client.get(&url).send().await.context("Failed to list documents")?;
    let result: serde_json::Value = resp.json().await?;
    println!("{}", serde_json::to_string_pretty(&result)?);
    Ok(())
}

async fn delete_by_path(client: &reqwest::Client, file_path: &str) -> Result<()> {
    // Step 1: List documents matching this file path via title pattern
    let search = format!("chunk::{file_path}");
    let url = format!("{BASE_URL}/api/v1/documents?document_pattern={search}");
    let resp = client.get(&url).send().await.context("Failed to list documents")?;
    let result: serde_json::Value = resp.json().await?;

    // The list response structure may vary — try common field names
    let docs = result.get("documents")
        .or_else(|| result.get("data"))
        .or_else(|| result.get("items"))
        .and_then(|d| d.as_array());

    match docs {
        Some(docs) if !docs.is_empty() => {
            println!("Found {} document(s) matching '{file_path}':", docs.len());
            let mut deleted = 0;
            for doc in docs {
                if let Some(id) = doc.get("id").and_then(|i| i.as_str()) {
                    let title = doc.get("title").and_then(|t| t.as_str()).unwrap_or("?");
                    println!("  Deleting [{id}] {title}...");
                    let del = client
                        .delete(format!("{BASE_URL}/api/v1/documents/{id}"))
                        .send()
                        .await?;
                    println!("    -> {}", del.status());
                    deleted += 1;
                }
            }
            println!("\n==> Deleted {deleted} document(s).");
        }
        _ => {
            println!("No documents found matching '{file_path}'.");
            println!("Raw list response:");
            println!("{}", serde_json::to_string_pretty(&result)?);
            println!("\n==> The document_pattern filter may not work as expected.");
            println!("    Fallback: track document IDs locally after ingestion.");
        }
    }

    Ok(())
}
```

- [ ] **Step 2: List all documents**

Run:
```bash
cd ~/dev/canopy && cargo run -- list-docs
```

Expected: Shows all three ingested documents with their IDs and titles (`chunk::samples/types.rs`, etc.).

- [ ] **Step 3: Delete documents for types.rs**

Run:
```bash
cd ~/dev/canopy && cargo run -- delete samples/types.rs
```

Expected: Finds and deletes the document for `samples/types.rs`.

- [ ] **Step 4: Verify deletion**

Run:
```bash
cd ~/dev/canopy && cargo run -- list-docs --pattern "chunk::samples/types.rs"
```

Expected: No documents found. If the `document_pattern` filter doesn't work for exact matching, try listing all docs and verifying manually.

- [ ] **Step 5: Re-ingest types.rs to verify clean re-indexing**

Run:
```bash
cd ~/dev/canopy && cargo run -- ingest samples/types.rs
```

Expected: New document created, `chunk_count = 1`. The delete-and-replace cycle works.

- [ ] **Step 6: Commit**

Run:
```bash
cd ~/dev/canopy && git add -A && git commit -m "feat: add list-docs and delete commands, validate deletion workflow"
```

---

### Task 9: Validate Querying

Ask natural language questions about the ingested code and evaluate answer quality.

**Files:**
- Modify: `~/dev/canopy/src/main.rs`

- [ ] **Step 1: Add Query subcommand**

Add to the `Commands` enum:

```rust
/// Ask a question about the ingested code
Query {
    /// The question to ask
    question: String,
    /// Query mode: hybrid, local, global, naive
    #[arg(long, default_value = "hybrid")]
    mode: String,
},
```

Add to the match block:

```rust
Commands::Query { question, mode } => query(&client, &question, &mode).await?,
```

Add the handler function:

```rust
async fn query(client: &reqwest::Client, question: &str, mode: &str) -> Result<()> {
    let body = serde_json::json!({
        "query": question,
        "mode": mode,
    });
    let resp = client
        .post(format!("{BASE_URL}/api/v1/query"))
        .json(&body)
        .send()
        .await
        .context("Failed to query EdgeQuake")?;

    println!("Status: {}", resp.status());
    let result: serde_json::Value = resp.json().await?;
    println!("{}", serde_json::to_string_pretty(&result)?);
    Ok(())
}
```

- [ ] **Step 2: Test with a relationship question**

Run:
```bash
cd ~/dev/canopy && cargo run -- query "How does BlobRenderer render blobs to the GPU?"
```

Expected: An answer that mentions BlobRenderer calling GpuContext.draw_blob() with BlobStyle, and GpuContext.flush(). The answer should reference the relationship between the three types.

- [ ] **Step 3: Test with a "what depends on X" question**

Run:
```bash
cd ~/dev/canopy && cargo run -- query "What types use BlobStyle?"
```

Expected: Mentions BlobRenderer and GpuContext (draw_blob parameter).

- [ ] **Step 4: Test with naive mode (pure vector, no graph)**

Run:
```bash
cd ~/dev/canopy && cargo run -- query "How does BlobRenderer render blobs to the GPU?" --mode naive
```

Compare the naive (vector-only) answer to the hybrid (graph + vector) answer from Step 2. Does the graph add meaningful relationship context?

- [ ] **Step 5: Test with local mode (graph neighborhood)**

Run:
```bash
cd ~/dev/canopy && cargo run -- query "What depends on Color?" --mode local
```

Expected: Finds that BlobStyle contains Color, and potentially that BlobStyle.default() calls Color::white().

- [ ] **Step 6: Commit**

Run:
```bash
cd ~/dev/canopy && git add -A && git commit -m "feat: add query command, validate query quality"
```

---

### Task 10: Document Findings and Gate Decision

Summarize all validation results and make the go/no-go decision for Phase 1.

**Files:**
- Create: `~/dev/canopy/docs/phase0-findings.md`

- [ ] **Step 1: Create findings document**

Create `~/dev/canopy/docs/phase0-findings.md` with this template, filled in with actual results:

```markdown
# Canopy Phase 0 Findings

**Date:** YYYY-MM-DD
**EdgeQuake version:** (from health endpoint)
**Ollama models:** nomic-embed-text, qwen2.5-coder:7b

## Validation 1: No Double-Chunking

**Result:** PASS / FAIL / WORKAROUND

- chunk_count for types.rs (XX lines): ___
- chunk_count for renderer.rs (XX lines): ___
- chunk_count for gpu.rs (XX lines): ___
- Workspace chunk_size setting: 100000
- Did workspace-level config prevent double-chunking? YES / NO
- Workaround needed: ___

## Validation 2: Deletion by File Path

**Result:** PASS / FAIL / WORKAROUND

- Did document_pattern filter find docs by title? YES / NO
- Could documents be deleted by ID after finding? YES / NO
- Was re-ingestion after deletion clean? YES / NO
- Fallback needed (local ID tracking)? YES / NO

## Validation 3: Entity Extraction Quality

**Result:** EXCELLENT / ACCEPTABLE / POOR

Entities discovered:
- (list actual entities from explore output)

Relationships discovered:
- (list actual relationships)

Expected relationships found: ___ / 6

## Validation 4: Query Quality

**Result:** USEFUL / MARGINAL / USELESS

### "How does BlobRenderer render blobs?" (hybrid mode)
(paste answer)

### "What types use BlobStyle?" (hybrid mode)
(paste answer)

### Hybrid vs Naive comparison
- Hybrid answer quality: ___
- Naive answer quality: ___
- Does graph RAG add value? YES / NO

## Gate Decision

**PROCEED to Phase 1 / ADJUST architecture / STOP**

Blockers for Phase 1:
- (list any)

Adjustments needed:
- (list any changes to the spec)

Notes:
- (anything surprising or worth remembering)
```

- [ ] **Step 2: Fill in the findings with actual results from Tasks 4-9**

Review the output from each validation task and fill in the template. Be honest — if entity extraction is poor, say so. The gate decision should be:

- **PROCEED:** All three validations pass (with or without workarounds) and query quality is at least acceptable.
- **ADJUST:** Validations pass but the approach needs changes (e.g., need local ID tracking, or need a different LLM model).
- **STOP:** Fundamental assumption is broken (e.g., EdgeQuake can't handle code at all, or the API is too immature).

- [ ] **Step 3: Commit**

Run:
```bash
cd ~/dev/canopy && git add -A && git commit -m "docs: phase 0 findings and gate decision"
```
