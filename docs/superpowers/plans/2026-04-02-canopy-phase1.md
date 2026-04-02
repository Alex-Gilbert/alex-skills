# Canopy Phase 1: Indexing Pipeline

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Canopy CLI with `init`, `index`, `reindex`, and `status` commands that parse codebases with tree-sitter, ingest chunks into EdgeQuake, and maintain incremental indexes triggered by git hooks.

**Architecture:** Single Rust binary. Tree-sitter parses source files into semantic chunks (functions, structs, impls). Chunks are sent to a running EdgeQuake server via REST API. Document IDs are tracked locally in `.canopy.toml` for file-level delete-and-replace on incremental updates. Git hooks trigger indexing on commits to main.

**Tech Stack:** Rust, tree-sitter (0.26) + tree-sitter-rust (0.24), reqwest, clap, serde, toml

**Spec:** `docs/superpowers/specs/2026-04-02-canopy-design.md`
**Phase 0 findings:** `~/dev/canopy/docs/phase0-findings.md`
**Existing prototype:** `~/dev/canopy/` (Phase 0 throwaway code — will be replaced)

**Prerequisites:** EdgeQuake running on localhost:8080 (deployed in Phase 0)

---

## File Structure

```
~/dev/canopy/
├── Cargo.toml              # Updated with tree-sitter deps
├── src/
│   ├── main.rs             # CLI entry (clap subcommands, wires modules together)
│   ├── config.rs           # .canopy.toml read/write with document ID tracking
│   ├── chunker.rs          # Tree-sitter parsing → semantic chunks
│   ├── edgequake.rs        # EdgeQuake HTTP client (ingest, delete, health)
│   └── git.rs              # Git operations (root, diff, branch, hooks)
├── tests/
│   ├── chunker_test.rs     # Unit tests for tree-sitter chunking
│   └── config_test.rs      # Unit tests for config serialization
├── samples/                # From Phase 0 (kept for manual testing)
└── docs/
    └── phase0-findings.md  # Phase 0 results
```

Each module has one clear responsibility. `main.rs` wires them together via CLI subcommands.

---

## Chunk 1: Foundation

### Task 1: Restructure Project and Update Dependencies

Replace the Phase 0 prototype with a proper project structure.

**Files:**
- Modify: `~/dev/canopy/Cargo.toml`
- Replace: `~/dev/canopy/src/main.rs`
- Create: `~/dev/canopy/src/config.rs`
- Create: `~/dev/canopy/src/edgequake.rs`
- Create: `~/dev/canopy/src/chunker.rs`
- Create: `~/dev/canopy/src/git.rs`

- [ ] **Step 1: Update Cargo.toml**

Replace `~/dev/canopy/Cargo.toml` with:

```toml
[package]
name = "canopy"
version = "0.1.0"
edition = "2021"

[[bin]]
name = "canopy"
path = "src/main.rs"

[dependencies]
anyhow = "1"
clap = { version = "4", features = ["derive"] }
reqwest = { version = "0.12", features = ["json", "blocking"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tokio = { version = "1", features = ["full"] }
toml = "0.8"
tree-sitter = "0.26"
tree-sitter-rust = "0.24"

[dev-dependencies]
tempfile = "3"
```

- [ ] **Step 2: Create stub modules**

Create `~/dev/canopy/src/config.rs`:
```rust
use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::{Path, PathBuf};

#[derive(Debug, Serialize, Deserialize)]
pub struct Config {
    pub project: ProjectConfig,
    pub indexing: IndexingConfig,
    /// Maps file paths (relative to repo root) to EdgeQuake document IDs
    #[serde(default)]
    pub documents: HashMap<String, Vec<String>>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ProjectConfig {
    pub name: String,
    pub edgequake_url: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct IndexingConfig {
    #[serde(default)]
    pub last_sha: String,
    #[serde(default)]
    pub languages: Vec<String>,
    #[serde(default)]
    pub ignore: Vec<String>,
    #[serde(default = "default_merge_threshold")]
    pub merge_threshold: usize,
    #[serde(default = "default_split_threshold")]
    pub split_threshold: usize,
}

fn default_merge_threshold() -> usize { 20 }
fn default_split_threshold() -> usize { 200 }

impl Config {
    pub fn load(path: &Path) -> Result<Self> {
        let content = std::fs::read_to_string(path)?;
        Ok(toml::from_str(&content)?)
    }

    pub fn save(&self, path: &Path) -> Result<()> {
        let content = toml::to_string_pretty(self)?;
        std::fs::write(path, content)?;
        Ok(())
    }

    pub fn default_for(name: &str, edgequake_url: &str) -> Self {
        Self {
            project: ProjectConfig {
                name: name.to_string(),
                edgequake_url: edgequake_url.to_string(),
            },
            indexing: IndexingConfig {
                last_sha: String::new(),
                languages: vec![],
                ignore: vec!["target/".into(), "vendor/".into(), "node_modules/".into()],
                merge_threshold: default_merge_threshold(),
                split_threshold: default_split_threshold(),
            },
            documents: HashMap::new(),
        }
    }

    /// Get document IDs for a file path, if any
    pub fn doc_ids_for(&self, file_path: &str) -> Option<&Vec<String>> {
        self.documents.get(file_path)
    }

    /// Store document IDs for a file path
    pub fn set_doc_ids(&mut self, file_path: String, ids: Vec<String>) {
        self.documents.insert(file_path, ids);
    }

    /// Remove document ID tracking for a file path
    pub fn remove_doc_ids(&mut self, file_path: &str) {
        self.documents.remove(file_path);
    }
}
```

Create `~/dev/canopy/src/edgequake.rs`:
```rust
use anyhow::{Context, Result};
use serde::Deserialize;

pub struct EdgeQuakeClient {
    client: reqwest::Client,
    base_url: String,
}

#[derive(Debug, Deserialize)]
pub struct IngestResponse {
    pub document_id: String,
    pub chunk_count: Option<u64>,
    pub entity_count: Option<u64>,
    pub relationship_count: Option<u64>,
    pub status: String,
}

#[derive(Debug, Deserialize)]
pub struct DeleteResponse {
    pub document_id: String,
    pub deleted: bool,
    pub chunks_deleted: Option<u64>,
}

impl EdgeQuakeClient {
    pub fn new(base_url: &str) -> Self {
        Self {
            client: reqwest::Client::new(),
            base_url: base_url.to_string(),
        }
    }

    pub async fn health(&self) -> Result<bool> {
        let resp = self.client
            .get(format!("{}/health", self.base_url))
            .send()
            .await
            .context("Failed to connect to EdgeQuake")?;
        Ok(resp.status().is_success())
    }

    pub async fn ingest(&self, content: &str, title: &str, metadata: serde_json::Value) -> Result<IngestResponse> {
        let body = serde_json::json!({
            "content": content,
            "title": title,
            "metadata": metadata,
        });
        let resp = self.client
            .post(format!("{}/api/v1/documents", self.base_url))
            .json(&body)
            .send()
            .await
            .context("Failed to ingest document")?;

        let status = resp.status();
        if status == reqwest::StatusCode::CREATED || status.is_success() {
            Ok(resp.json().await?)
        } else {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("EdgeQuake ingest failed ({}): {}", status, body)
        }
    }

    pub async fn delete(&self, document_id: &str) -> Result<DeleteResponse> {
        let resp = self.client
            .delete(format!("{}/api/v1/documents/{}", self.base_url, document_id))
            .send()
            .await
            .context("Failed to delete document")?;

        let status = resp.status();
        if status.is_success() {
            Ok(resp.json().await?)
        } else if status == reqwest::StatusCode::NOT_FOUND {
            Ok(DeleteResponse {
                document_id: document_id.to_string(),
                deleted: false,
                chunks_deleted: Some(0),
            })
        } else {
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("EdgeQuake delete failed ({}): {}", status, body)
        }
    }
}
```

Create `~/dev/canopy/src/chunker.rs`:
```rust
use tree_sitter::{Language, Parser};

/// A semantic code chunk extracted by tree-sitter
#[derive(Debug, Clone)]
pub struct Chunk {
    pub content: String,
    pub file_path: String,
    pub language: String,
    pub node_kinds: Vec<String>,
    pub line_start: usize, // 1-based
    pub line_end: usize,   // 1-based
    pub parent_scope: String,
}

/// Parse a source file and extract semantic chunks
pub fn chunk_file(
    source: &str,
    file_path: &str,
    language: &str,
    merge_threshold: usize,
    split_threshold: usize,
) -> Vec<Chunk> {
    let ts_lang = match language {
        "rust" => Language::new(tree_sitter_rust::LANGUAGE),
        _ => return vec![fallback_chunk(source, file_path, language)],
    };

    let mut parser = Parser::new();
    if parser.set_language(&ts_lang).is_err() {
        return vec![fallback_chunk(source, file_path, language)];
    }

    let tree = match parser.parse(source, None) {
        Some(t) => t,
        None => return vec![fallback_chunk(source, file_path, language)],
    };

    let source_bytes = source.as_bytes();
    let root = tree.root_node();
    let mut raw_chunks: Vec<Chunk> = Vec::new();

    // Walk top-level children and extract primary chunks
    let mut cursor = root.walk();
    if cursor.goto_first_child() {
        loop {
            let node = cursor.node();
            if is_primary_node(node.kind()) {
                let start = node.start_position().row + 1;
                let end = node.end_position().row + 1;
                let text = node.utf8_text(source_bytes).unwrap_or("").to_string();
                let line_count = end - start + 1;

                if line_count > split_threshold {
                    // Split large nodes at child boundaries
                    let children = split_large_node(&node, source_bytes, file_path, language, split_threshold);
                    raw_chunks.extend(children);
                } else {
                    raw_chunks.push(Chunk {
                        content: text,
                        file_path: file_path.to_string(),
                        language: language.to_string(),
                        node_kinds: vec![node.kind().to_string()],
                        line_start: start,
                        line_end: end,
                        parent_scope: String::new(),
                    });
                }
            }
            if !cursor.goto_next_sibling() {
                break;
            }
        }
    }

    // Merge small adjacent chunks
    merge_small_chunks(raw_chunks, file_path, language, merge_threshold)
}

fn is_primary_node(kind: &str) -> bool {
    matches!(kind,
        "function_item" | "struct_item" | "enum_item" | "impl_item" |
        "trait_item" | "type_item" | "const_item" | "static_item" |
        "mod_item" | "macro_definition"
    )
}

fn split_large_node(
    node: &tree_sitter::Node,
    source: &[u8],
    file_path: &str,
    language: &str,
    split_threshold: usize,
) -> Vec<Chunk> {
    let mut chunks = Vec::new();
    let parent_kind = node.kind().to_string();

    let mut cursor = node.walk();
    if cursor.goto_first_child() {
        loop {
            let child = cursor.node();
            if is_primary_node(child.kind()) || child.kind().ends_with("_item") {
                let start = child.start_position().row + 1;
                let end = child.end_position().row + 1;
                let text = child.utf8_text(source).unwrap_or("").to_string();
                chunks.push(Chunk {
                    content: text,
                    file_path: file_path.to_string(),
                    language: language.to_string(),
                    node_kinds: vec![child.kind().to_string()],
                    line_start: start,
                    line_end: end,
                    parent_scope: parent_kind.clone(),
                });
            }
            if !cursor.goto_next_sibling() {
                break;
            }
        }
    }

    // If we couldn't split meaningfully, return the whole node as one chunk
    if chunks.is_empty() {
        let start = node.start_position().row + 1;
        let end = node.end_position().row + 1;
        let text = node.utf8_text(source).unwrap_or("").to_string();
        chunks.push(Chunk {
            content: text,
            file_path: file_path.to_string(),
            language: language.to_string(),
            node_kinds: vec![parent_kind],
            line_start: start,
            line_end: end,
            parent_scope: String::new(),
        });
    }

    chunks
}

fn merge_small_chunks(
    chunks: Vec<Chunk>,
    file_path: &str,
    language: &str,
    merge_threshold: usize,
) -> Vec<Chunk> {
    if chunks.is_empty() {
        return chunks;
    }

    let mut merged: Vec<Chunk> = Vec::new();
    let mut pending: Option<Chunk> = None;

    for chunk in chunks {
        let line_count = chunk.line_end - chunk.line_start + 1;

        match pending.take() {
            None => {
                if line_count < merge_threshold {
                    pending = Some(chunk);
                } else {
                    merged.push(chunk);
                }
            }
            Some(mut p) => {
                let p_lines = p.line_end - p.line_start + 1;
                if p_lines < merge_threshold && line_count < merge_threshold {
                    // Merge: combine content and metadata
                    p.content.push_str("\n\n");
                    p.content.push_str(&chunk.content);
                    p.line_end = chunk.line_end;
                    p.node_kinds.extend(chunk.node_kinds);
                    pending = Some(p);
                } else {
                    merged.push(p);
                    if line_count < merge_threshold {
                        pending = Some(chunk);
                    } else {
                        merged.push(chunk);
                    }
                }
            }
        }
    }

    if let Some(p) = pending {
        merged.push(p);
    }

    merged
}

fn fallback_chunk(source: &str, file_path: &str, language: &str) -> Chunk {
    let line_count = source.lines().count();
    Chunk {
        content: source.to_string(),
        file_path: file_path.to_string(),
        language: language.to_string(),
        node_kinds: vec!["file".to_string()],
        line_start: 1,
        line_end: line_count,
        parent_scope: String::new(),
    }
}

/// Detect language from file extension
pub fn detect_language(path: &str) -> Option<&'static str> {
    let ext = path.rsplit('.').next()?;
    match ext {
        "rs" => Some("rust"),
        _ => None,
    }
}
```

Create `~/dev/canopy/src/git.rs`:
```rust
use anyhow::{Context, Result};
use std::path::{Path, PathBuf};
use std::process::Command;

/// Find the git root directory from the current or given path
pub fn find_root(from: &Path) -> Result<PathBuf> {
    let output = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .current_dir(from)
        .output()
        .context("Failed to run git")?;
    if !output.status.success() {
        anyhow::bail!("Not a git repository: {}", from.display());
    }
    let root = String::from_utf8(output.stdout)?.trim().to_string();
    Ok(PathBuf::from(root))
}

/// Get the current HEAD SHA
pub fn head_sha(repo: &Path) -> Result<String> {
    let output = Command::new("git")
        .args(["rev-parse", "HEAD"])
        .current_dir(repo)
        .output()
        .context("Failed to get HEAD SHA")?;
    if !output.status.success() {
        anyhow::bail!("Failed to get HEAD SHA");
    }
    Ok(String::from_utf8(output.stdout)?.trim().to_string())
}

/// Get the current branch name
pub fn current_branch(repo: &Path) -> Result<String> {
    let output = Command::new("git")
        .args(["rev-parse", "--abbrev-ref", "HEAD"])
        .current_dir(repo)
        .output()
        .context("Failed to get current branch")?;
    Ok(String::from_utf8(output.stdout)?.trim().to_string())
}

#[derive(Debug)]
pub enum FileChange {
    Added(String),
    Modified(String),
    Deleted(String),
}

/// Get list of changed files between two SHAs
pub fn diff_files(repo: &Path, from_sha: &str, to_sha: &str) -> Result<Vec<FileChange>> {
    let output = Command::new("git")
        .args(["diff", "--name-status", from_sha, to_sha])
        .current_dir(repo)
        .output()
        .context("Failed to run git diff")?;
    if !output.status.success() {
        anyhow::bail!("git diff failed");
    }
    let text = String::from_utf8(output.stdout)?;
    let mut changes = Vec::new();
    for line in text.lines() {
        let parts: Vec<&str> = line.splitn(2, '\t').collect();
        if parts.len() != 2 {
            continue;
        }
        let change = match parts[0] {
            "A" => FileChange::Added(parts[1].to_string()),
            "M" => FileChange::Modified(parts[1].to_string()),
            "D" => FileChange::Deleted(parts[1].to_string()),
            s if s.starts_with('R') => {
                // Rename: treat as delete old + add new
                let names: Vec<&str> = parts[1].splitn(2, '\t').collect();
                if names.len() == 2 {
                    changes.push(FileChange::Deleted(names[0].to_string()));
                    FileChange::Added(names[1].to_string())
                } else {
                    FileChange::Modified(parts[1].to_string())
                }
            }
            _ => FileChange::Modified(parts[1].to_string()),
        };
        changes.push(change);
    }
    Ok(changes)
}

/// List all tracked files in the repo (for full reindex)
pub fn all_tracked_files(repo: &Path) -> Result<Vec<String>> {
    let output = Command::new("git")
        .args(["ls-files"])
        .current_dir(repo)
        .output()
        .context("Failed to list tracked files")?;
    let text = String::from_utf8(output.stdout)?;
    Ok(text.lines().map(|l| l.to_string()).collect())
}

const HOOK_MARKER: &str = "# canopy-hook";

/// Install post-commit and post-merge hooks
pub fn install_hooks(repo: &Path) -> Result<()> {
    let hooks_dir = repo.join(".git/hooks");
    std::fs::create_dir_all(&hooks_dir)?;

    let canopy_block = format!(
        r#"
{HOOK_MARKER}
if [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || [ "$(git rev-parse --abbrev-ref HEAD)" = "master" ]; then
    canopy index >/dev/null 2>&1 &
fi
"#
    );

    for hook_name in ["post-commit", "post-merge"] {
        let hook_path = hooks_dir.join(hook_name);
        let existing = std::fs::read_to_string(&hook_path).unwrap_or_default();

        if existing.contains(HOOK_MARKER) {
            continue; // Already installed
        }

        let content = if existing.is_empty() {
            format!("#!/bin/sh\n{canopy_block}")
        } else {
            format!("{existing}\n{canopy_block}")
        };

        std::fs::write(&hook_path, content)?;

        // Make executable
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&hook_path, std::fs::Permissions::from_mode(0o755))?;
        }
    }

    Ok(())
}
```

Replace `~/dev/canopy/src/main.rs` with a minimal stub:
```rust
mod chunker;
mod config;
mod edgequake;
mod git;

use anyhow::Result;
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "canopy", about = "Semantic code search powered by tree-sitter + EdgeQuake")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Initialize canopy for a git repository
    Init {
        /// EdgeQuake server URL
        #[arg(long, default_value = "http://localhost:8080")]
        edgequake_url: String,
    },
    /// Index changes since last indexed commit
    Index,
    /// Full re-index of the entire repository
    Reindex,
    /// Show project status
    Status,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Init { edgequake_url } => cmd_init(&edgequake_url).await,
        Commands::Index => cmd_index().await,
        Commands::Reindex => cmd_reindex().await,
        Commands::Status => cmd_status().await,
    }
}

async fn cmd_init(_edgequake_url: &str) -> Result<()> {
    println!("TODO: init");
    Ok(())
}

async fn cmd_index() -> Result<()> {
    println!("TODO: index");
    Ok(())
}

async fn cmd_reindex() -> Result<()> {
    println!("TODO: reindex");
    Ok(())
}

async fn cmd_status() -> Result<()> {
    println!("TODO: status");
    Ok(())
}
```

- [ ] **Step 3: Verify it compiles**

Run:
```bash
cd ~/dev/canopy && cargo build 2>&1
```

Expected: Compiles with no errors (warnings about unused code are fine).

- [ ] **Step 4: Commit**

```bash
cd ~/dev/canopy && git add -A && git commit -m "refactor: restructure for Phase 1 — config, chunker, edgequake, git modules"
```

---

### Task 2: Config Module Tests

**Files:**
- Create: `~/dev/canopy/tests/config_test.rs`

- [ ] **Step 1: Write config round-trip test**

Create `~/dev/canopy/tests/config_test.rs`:

```rust
use canopy::config::Config;
use tempfile::NamedTempFile;

#[test]
fn test_config_roundtrip() {
    let config = Config::default_for("test-project", "http://localhost:8080");
    let file = NamedTempFile::new().unwrap();
    let path = file.path();

    config.save(path).unwrap();
    let loaded = Config::load(path).unwrap();

    assert_eq!(loaded.project.name, "test-project");
    assert_eq!(loaded.project.edgequake_url, "http://localhost:8080");
    assert_eq!(loaded.indexing.merge_threshold, 20);
    assert_eq!(loaded.indexing.split_threshold, 200);
    assert!(loaded.indexing.last_sha.is_empty());
    assert!(loaded.documents.is_empty());
}

#[test]
fn test_document_id_tracking() {
    let mut config = Config::default_for("test", "http://localhost:8080");

    config.set_doc_ids("src/main.rs".into(), vec!["id-1".into(), "id-2".into()]);
    assert_eq!(config.doc_ids_for("src/main.rs").unwrap().len(), 2);

    config.remove_doc_ids("src/main.rs");
    assert!(config.doc_ids_for("src/main.rs").is_none());
}

#[test]
fn test_document_ids_persist_through_save_load() {
    let mut config = Config::default_for("test", "http://localhost:8080");
    config.set_doc_ids("src/lib.rs".into(), vec!["abc-123".into()]);
    config.indexing.last_sha = "deadbeef".into();

    let file = NamedTempFile::new().unwrap();
    config.save(file.path()).unwrap();
    let loaded = Config::load(file.path()).unwrap();

    assert_eq!(loaded.indexing.last_sha, "deadbeef");
    assert_eq!(loaded.doc_ids_for("src/lib.rs").unwrap(), &vec!["abc-123".to_string()]);
}
```

- [ ] **Step 2: Add lib.rs and update main.rs for test access**

Integration tests need `pub` access to modules. Create a `lib.rs` that re-exports them, and have `main.rs` import from the library.

Create `~/dev/canopy/src/lib.rs`:
```rust
pub mod chunker;
pub mod config;
pub mod edgequake;
pub mod git;
```

Update `~/dev/canopy/src/main.rs` — replace the `mod` declarations at the top with library imports:
```rust
use canopy::chunker;
use canopy::config::Config;
use canopy::edgequake::EdgeQuakeClient;
use canopy::git;
```

(Remove the existing `mod chunker;`, `mod config;`, `mod edgequake;`, `mod git;` lines from main.rs — those are now in lib.rs.)

Add the lib target to `~/dev/canopy/Cargo.toml` (before the `[[bin]]` section):
```toml
[lib]
name = "canopy"
path = "src/lib.rs"
```

- [ ] **Step 3: Run tests**

```bash
cd ~/dev/canopy && cargo test --test config_test 2>&1
```

Expected: All 3 tests pass.

- [ ] **Step 4: Commit**

```bash
cd ~/dev/canopy && git add -A && git commit -m "test: add config module tests, add lib.rs for test access"
```

---

### Task 3: Chunker Tests and Refinement

**Files:**
- Create: `~/dev/canopy/tests/chunker_test.rs`

- [ ] **Step 1: Write chunker tests**

Create `~/dev/canopy/tests/chunker_test.rs`:

```rust
use canopy::chunker::{chunk_file, detect_language};

#[test]
fn test_detect_language() {
    assert_eq!(detect_language("src/main.rs"), Some("rust"));
    assert_eq!(detect_language("foo.py"), None);
    assert_eq!(detect_language("no_ext"), None);
}

#[test]
fn test_chunk_simple_function() {
    let source = r#"
fn hello() {
    println!("hello");
}
"#;
    let chunks = chunk_file(source, "test.rs", "rust", 20, 200);
    assert_eq!(chunks.len(), 1);
    assert!(chunks[0].content.contains("fn hello()"));
    assert_eq!(chunks[0].node_kinds, vec!["function_item"]);
}

#[test]
fn test_chunk_struct_and_impl() {
    let source = r#"
pub struct Foo {
    x: i32,
}

impl Foo {
    pub fn new(x: i32) -> Self {
        Self { x }
    }

    pub fn value(&self) -> i32 {
        self.x
    }
}
"#;
    let chunks = chunk_file(source, "test.rs", "rust", 20, 200);
    // struct (3 lines) + impl (10 lines) — struct is under merge_threshold (20)
    // but impl is not, so struct gets its own chunk (or merged with impl)
    assert!(chunks.len() >= 1);
    // Verify both struct and impl are present somewhere in the chunks
    let all_content: String = chunks.iter().map(|c| c.content.as_str()).collect::<Vec<_>>().join("\n");
    assert!(all_content.contains("pub struct Foo"));
    assert!(all_content.contains("impl Foo"));
}

#[test]
fn test_merge_small_chunks() {
    let source = r#"
const A: i32 = 1;

const B: i32 = 2;

const C: i32 = 3;
"#;
    let chunks = chunk_file(source, "test.rs", "rust", 20, 200);
    // Three 1-line constants — all under merge_threshold, should merge into 1 chunk
    assert_eq!(chunks.len(), 1);
    assert!(chunks[0].content.contains("const A"));
    assert!(chunks[0].content.contains("const C"));
    assert!(chunks[0].node_kinds.len() == 3);
}

#[test]
fn test_line_numbers() {
    let source = r#"fn first() {}

fn second() {
    let x = 1;
    let y = 2;
}
"#;
    let chunks = chunk_file(source, "test.rs", "rust", 5, 200);
    // Two small functions — may or may not merge depending on threshold
    // At merge_threshold=5, both are under 5 lines so they merge
    assert!(chunks.len() >= 1);
    assert_eq!(chunks[0].line_start, 1);
}

#[test]
fn test_unsupported_language_returns_whole_file() {
    let source = "print('hello')";
    let chunks = chunk_file(source, "test.py", "python", 20, 200);
    assert_eq!(chunks.len(), 1);
    assert_eq!(chunks[0].node_kinds, vec!["file"]);
    assert_eq!(chunks[0].content, source);
}

#[test]
fn test_empty_file() {
    let chunks = chunk_file("", "empty.rs", "rust", 20, 200);
    // Empty file may produce 0 chunks (no primary nodes)
    assert!(chunks.is_empty() || chunks.len() == 1);
}

#[test]
fn test_file_with_doc_comments() {
    let source = r#"
/// This is a documented function.
/// It does important things.
pub fn documented() -> bool {
    true
}
"#;
    let chunks = chunk_file(source, "test.rs", "rust", 20, 200);
    assert_eq!(chunks.len(), 1);
    // Doc comments should be included in the chunk
    assert!(chunks[0].content.contains("/// This is a documented function"));
    assert!(chunks[0].content.contains("pub fn documented"));
}
```

- [ ] **Step 2: Run tests**

```bash
cd ~/dev/canopy && cargo test --test chunker_test 2>&1
```

Expected: All tests pass. If any fail, adjust the chunker logic in `src/chunker.rs` to match the expected behavior, then re-run.

- [ ] **Step 3: Commit**

```bash
cd ~/dev/canopy && git add -A && git commit -m "test: add chunker tests for parsing, merging, splitting"
```

---

## Chunk 2: CLI Commands

### Task 4: Implement `canopy init`

**Files:**
- Modify: `~/dev/canopy/src/main.rs`

- [ ] **Step 1: Implement cmd_init**

Add `use anyhow::Context;` to the imports in main.rs if not already present. Then replace the `cmd_init` function:

```rust
async fn cmd_init(edgequake_url: &str) -> Result<()> {
    // 1. Find git root
    let cwd = std::env::current_dir()?;
    let repo_root = git::find_root(&cwd)?;
    println!("Git root: {}", repo_root.display());

    // 2. Check EdgeQuake health
    let eq = EdgeQuakeClient::new(edgequake_url);
    if !eq.health().await? {
        anyhow::bail!("EdgeQuake is not healthy at {edgequake_url}");
    }
    println!("EdgeQuake: connected at {edgequake_url}");

    // 3. Derive project name from directory
    let project_name = repo_root
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("unknown")
        .to_string();

    // 4. Check if .canopy.toml already exists
    let config_path = repo_root.join(".canopy.toml");
    if config_path.exists() {
        anyhow::bail!(".canopy.toml already exists. Use `canopy reindex` to re-index.");
    }

    // 5. Create config
    let config = Config::default_for(&project_name, edgequake_url);
    config.save(&config_path)?;
    println!("Created .canopy.toml");

    // 6. Install git hooks
    git::install_hooks(&repo_root)?;
    println!("Installed git hooks (post-commit, post-merge)");

    // 7. Run initial index
    println!("\nStarting initial index...");
    do_full_index(&repo_root, &config_path, &eq).await?;

    println!("\nCanopy initialized for '{project_name}'.");
    Ok(())
}
```

- [ ] **Step 2: Implement the shared indexing logic**

Add these helper functions to `~/dev/canopy/src/main.rs`:

```rust
use std::path::Path;

/// Index a single file: parse with tree-sitter, ingest chunks into EdgeQuake
async fn index_file(
    repo_root: &Path,
    file_path: &str,
    config: &Config,
    eq: &EdgeQuakeClient,
) -> Result<Vec<String>> {
    let full_path = repo_root.join(file_path);
    let source = std::fs::read_to_string(&full_path)
        .with_context(|| format!("Failed to read {file_path}"))?;

    let language = chunker::detect_language(file_path).unwrap_or("unknown");
    let chunks = chunker::chunk_file(
        &source,
        file_path,
        language,
        config.indexing.merge_threshold,
        config.indexing.split_threshold,
    );

    let mut doc_ids = Vec::new();
    for (i, chunk) in chunks.iter().enumerate() {
        let title = format!("chunk::{}::{}",
            file_path,
            chunk.node_kinds.first().map(|s| s.as_str()).unwrap_or("unknown")
        );
        let metadata = serde_json::json!({
            "file_path": file_path,
            "language": chunk.language,
            "node_kinds": chunk.node_kinds,
            "line_range": format!("{}-{}", chunk.line_start, chunk.line_end),
            "parent_scope": chunk.parent_scope,
            "chunk_index": i,
        });

        match eq.ingest(&chunk.content, &title, metadata).await {
            Ok(resp) => {
                doc_ids.push(resp.document_id);
            }
            Err(e) => {
                eprintln!("  Warning: failed to ingest chunk {} of {}: {}", i, file_path, e);
            }
        }
    }

    Ok(doc_ids)
}

/// Delete all tracked documents for a file
async fn delete_file_docs(
    file_path: &str,
    config: &Config,
    eq: &EdgeQuakeClient,
) -> Result<()> {
    if let Some(ids) = config.doc_ids_for(file_path) {
        for id in ids {
            if let Err(e) = eq.delete(id).await {
                eprintln!("  Warning: failed to delete doc {}: {}", id, e);
            }
        }
    }
    Ok(())
}

/// Check if a file should be indexed based on language and ignore patterns
fn should_index(file_path: &str, config: &Config) -> bool {
    // Check ignore patterns
    for pattern in &config.indexing.ignore {
        if file_path.starts_with(pattern.trim_end_matches('/')) {
            return false;
        }
    }
    // Check if we support the language
    chunker::detect_language(file_path).is_some()
}

/// Full index: index all supported files in the repo
async fn do_full_index(
    repo_root: &Path,
    config_path: &Path,
    eq: &EdgeQuakeClient,
) -> Result<()> {
    let mut config = Config::load(config_path)?;

    // Get all tracked files
    let files = git::all_tracked_files(repo_root)?;
    let indexable: Vec<_> = files.iter().filter(|f| should_index(f, &config)).collect();

    println!("Found {} files to index", indexable.len());

    let mut total_chunks = 0usize;
    for (i, file_path) in indexable.iter().enumerate() {
        print!("  [{}/{}] {} ... ", i + 1, indexable.len(), file_path);
        match index_file(repo_root, file_path, &config, eq).await {
            Ok(ids) => {
                let count = ids.len();
                total_chunks += count;
                config.set_doc_ids(file_path.to_string(), ids);
                println!("{count} chunk(s)");
            }
            Err(e) => {
                eprintln!("ERROR: {e}");
            }
        }
    }

    // Update SHA and save
    config.indexing.last_sha = git::head_sha(repo_root)?;
    config.save(config_path)?;

    println!("Indexed {total_chunks} chunks from {} files", indexable.len());
    Ok(())
}
```

- [ ] **Step 3: Verify it compiles**

```bash
cd ~/dev/canopy && cargo build 2>&1
```

- [ ] **Step 4: Commit**

```bash
cd ~/dev/canopy && git add -A && git commit -m "feat: implement canopy init with full indexing"
```

---

### Task 5: Implement `canopy index` (incremental)

**Files:**
- Modify: `~/dev/canopy/src/main.rs`

- [ ] **Step 1: Implement cmd_index**

Replace the `cmd_index` function:

```rust
async fn cmd_index() -> Result<()> {
    let cwd = std::env::current_dir()?;
    let repo_root = git::find_root(&cwd)?;
    let config_path = repo_root.join(".canopy.toml");

    if !config_path.exists() {
        anyhow::bail!("Not a canopy project. Run `canopy init` first.");
    }

    let mut config = Config::load(&config_path)?;
    let eq = EdgeQuakeClient::new(&config.project.edgequake_url);

    let current_sha = git::head_sha(&repo_root)?;

    if config.indexing.last_sha == current_sha {
        println!("Already up to date ({})", &current_sha[..8]);
        return Ok(());
    }

    if config.indexing.last_sha.is_empty() {
        println!("No previous index. Running full index...");
        return do_full_index(&repo_root, &config_path, &eq).await;
    }

    // Incremental: diff files
    let changes = git::diff_files(&repo_root, &config.indexing.last_sha, &current_sha)?;
    if changes.is_empty() {
        println!("No file changes detected.");
        config.indexing.last_sha = current_sha;
        config.save(&config_path)?;
        return Ok(());
    }

    println!("Indexing changes from {}..{}", &config.indexing.last_sha[..8], &current_sha[..8]);

    let mut indexed = 0usize;
    let mut deleted = 0usize;

    for change in &changes {
        match change {
            git::FileChange::Deleted(path) => {
                if should_index(path, &config) {
                    delete_file_docs(path, &config, &eq).await?;
                    config.remove_doc_ids(path);
                    deleted += 1;
                    println!("  D {path}");
                }
            }
            git::FileChange::Added(path) | git::FileChange::Modified(path) => {
                if should_index(path, &config) {
                    // Delete old docs first (for modified files)
                    delete_file_docs(path, &config, &eq).await?;

                    match index_file(&repo_root, path, &config, &eq).await {
                        Ok(ids) => {
                            let count = ids.len();
                            config.set_doc_ids(path.to_string(), ids);
                            indexed += count;
                            let prefix = match change {
                                git::FileChange::Added(_) => "A",
                                _ => "M",
                            };
                            println!("  {prefix} {path} ({count} chunks)");
                        }
                        Err(e) => {
                            eprintln!("  E {path}: {e}");
                        }
                    }
                }
            }
        }
    }

    config.indexing.last_sha = current_sha;
    config.save(&config_path)?;

    println!("Done: {indexed} chunks indexed, {deleted} files deleted");
    Ok(())
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd ~/dev/canopy && cargo build 2>&1
```

- [ ] **Step 3: Commit**

```bash
cd ~/dev/canopy && git add -A && git commit -m "feat: implement canopy index (incremental)"
```

---

### Task 6: Implement `canopy reindex` and `canopy status`

**Files:**
- Modify: `~/dev/canopy/src/main.rs`

- [ ] **Step 1: Implement cmd_reindex**

Replace the `cmd_reindex` function:

```rust
async fn cmd_reindex() -> Result<()> {
    let cwd = std::env::current_dir()?;
    let repo_root = git::find_root(&cwd)?;
    let config_path = repo_root.join(".canopy.toml");

    if !config_path.exists() {
        anyhow::bail!("Not a canopy project. Run `canopy init` first.");
    }

    let config = Config::load(&config_path)?;
    let eq = EdgeQuakeClient::new(&config.project.edgequake_url);

    // Delete all existing tracked documents
    let total_docs: usize = config.documents.values().map(|v| v.len()).sum();
    if total_docs > 0 {
        println!("Deleting {total_docs} existing documents...");
        for (file_path, ids) in &config.documents {
            for id in ids {
                if let Err(e) = eq.delete(id).await {
                    eprintln!("  Warning: failed to delete {id} for {file_path}: {e}");
                }
            }
        }
    }

    // Clear stale document IDs and save before re-indexing
    config.documents.clear();
    config.indexing.last_sha.clear();
    config.save(&config_path)?;

    // Full re-index
    println!("Starting full re-index...");
    do_full_index(&repo_root, &config_path, &eq).await
}
```

- [ ] **Step 2: Implement cmd_status**

Replace the `cmd_status` function:

```rust
async fn cmd_status() -> Result<()> {
    let cwd = std::env::current_dir()?;
    let repo_root = git::find_root(&cwd)?;
    let config_path = repo_root.join(".canopy.toml");

    if !config_path.exists() {
        anyhow::bail!("Not a canopy project. Run `canopy init` first.");
    }

    let config = Config::load(&config_path)?;

    println!("Canopy project: {}", config.project.name);
    println!("EdgeQuake URL: {}", config.project.edgequake_url);

    // Check EdgeQuake health
    let eq = EdgeQuakeClient::new(&config.project.edgequake_url);
    match eq.health().await {
        Ok(true) => println!("EdgeQuake: connected"),
        Ok(false) => println!("EdgeQuake: unhealthy"),
        Err(_) => println!("EdgeQuake: unreachable"),
    }

    // Index info
    if config.indexing.last_sha.is_empty() {
        println!("Last indexed: never");
    } else {
        println!("Last indexed: {}", &config.indexing.last_sha[..8]);
    }

    let current_sha = git::head_sha(&repo_root).unwrap_or_default();
    if !current_sha.is_empty() {
        if current_sha == config.indexing.last_sha {
            println!("HEAD: {} (up to date)", &current_sha[..8]);
        } else {
            println!("HEAD: {} (needs indexing)", &current_sha[..8]);
        }
    }

    let file_count = config.documents.len();
    let doc_count: usize = config.documents.values().map(|v| v.len()).sum();
    println!("Indexed files: {file_count}");
    println!("Total documents: {doc_count}");

    Ok(())
}
```

- [ ] **Step 3: Verify it compiles**

```bash
cd ~/dev/canopy && cargo build 2>&1
```

- [ ] **Step 4: Commit**

```bash
cd ~/dev/canopy && git add -A && git commit -m "feat: implement canopy reindex and status"
```

---

## Chunk 3: Integration Testing

### Task 7: Manual End-to-End Test Against a Real Repo

This task is manual verification using the Atlas repo (or any Rust repo) with EdgeQuake running.

**Files:** None (manual testing)

- [ ] **Step 1: Build release binary**

```bash
cd ~/dev/canopy && cargo build --release 2>&1
```

- [ ] **Step 2: Test init on a Rust repo**

Pick a Rust repo to test against (e.g., Atlas at `~/dev/atlas`, or the canopy repo itself):

```bash
cd ~/dev/canopy && ./target/release/canopy init
```

Expected: Creates `.canopy.toml`, installs git hooks, indexes all `.rs` files, prints summary.

- [ ] **Step 3: Verify .canopy.toml was created**

```bash
cat ~/dev/canopy/.canopy.toml | head -20
```

Expected: Shows project config, last_sha, and document ID mappings.

- [ ] **Step 4: Test status**

```bash
cd ~/dev/canopy && ./target/release/canopy status
```

Expected: Shows project name, EdgeQuake connection, last indexed SHA (matching HEAD), file count, document count.

- [ ] **Step 5: Make a change and test incremental index**

```bash
cd ~/dev/canopy
echo "// test comment" >> src/main.rs
git add -A && git commit -m "test: trigger incremental index"
```

The post-commit hook should run `canopy index` automatically. If not, run manually:

```bash
./target/release/canopy index
```

Expected: Shows the modified file being re-indexed. Only `src/main.rs` should be re-processed.

- [ ] **Step 6: Test reindex**

```bash
cd ~/dev/canopy && ./target/release/canopy reindex
```

Expected: Deletes all existing documents, re-indexes everything from scratch.

- [ ] **Step 7: Query the indexed code via EdgeQuake**

Use the Phase 0 prototype or curl to query:

```bash
curl -s -X POST -H "Content-Type: application/json" \
  http://localhost:8080/api/v1/query \
  -d '{"query": "How does the chunker work?", "mode": "hybrid"}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('answer','')[:500])"
```

Expected: An answer that references the chunker module, tree-sitter parsing, and chunk merging/splitting.

- [ ] **Step 8: Install binary to PATH**

```bash
cargo install --path ~/dev/canopy
```

Verify:
```bash
which canopy && canopy status
```

- [ ] **Step 9: Clean up test commit if needed**

```bash
cd ~/dev/canopy && git reset --soft HEAD~1 && git checkout src/main.rs
```

- [ ] **Step 10: Final commit**

```bash
cd ~/dev/canopy && git add -A && git commit -m "feat: Phase 1 complete — indexing pipeline"
```
