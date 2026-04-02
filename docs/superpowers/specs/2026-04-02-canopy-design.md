# Canopy — Semantic Code Search System

**Date:** 2026-04-02
**Status:** Approved

## What It Is

Canopy is a standalone Rust project that indexes codebases using tree-sitter, stores the results in a graph RAG engine (EdgeQuake), and provides an MCP tool (`ask_codebase`) that lets LLM coding agents ask natural language questions about the codebase. Reduces token usage and exploration time when working in large codebases.

**Motivation:** Real exploration costs in the Atlas codebase (~150k LOC, 30 Rust/Bevy crates). A single exploration of the blob rendering system consumed 82k tokens, 32 tool calls, and 13 minutes via a sub-agent. Canopy collapses that to a single `ask_codebase()` call returning a focused answer in seconds.

## Architecture

### Components

| Component | What | Runs as |
|-----------|------|---------|
| **EdgeQuake** | Graph RAG engine (entity extraction, embeddings, graph storage, query synthesis) | Docker Compose on archbtw (PostgreSQL with AGE + pgvector) |
| **Ollama** | LLM backend for EdgeQuake (embeddings + entity extraction + synthesis) | systemd service on archbtw (already running) |
| **Canopy CLI** | Tree-sitter chunker, git-triggered indexer, MCP server for agents | Per-project Rust binary |

### Data Flow

```
File change → git commit → post-commit/post-merge hook → canopy index →
  git diff (changed files) → tree-sitter parse → chunk merge/split →
  delete old chunks from EdgeQuake → ingest new chunks →
  EdgeQuake: embed (Ollama) + extract entities (Ollama) → PostgreSQL (graph + vectors)

Agent question → MCP ask_codebase → Canopy CLI → EdgeQuake query API →
  vector search + graph traversal → Ollama synthesis →
  answer + source chunks (with file paths + line ranges) → agent
```

### Key Decision: All Rust

The original design split Canopy into a Gleam server and Rust client. The revised design goes all-Rust:

- **EdgeQuake** replaces the custom Gleam server + Qdrant — it handles embedding, entity extraction, graph storage, and query synthesis
- **Canopy CLI** (Rust) handles tree-sitter parsing, git integration, and MCP
- Gleam server is eliminated entirely

### Key Decision: Graph RAG over Vector RAG

EdgeQuake implements LightRAG, which captures relationships between entities as explicit graph edges, not just vector similarity. This addresses the key weakness of pure vector search: understanding that `blob_common.wgsl` is included by all four shader variants, or that `BlobCssStyle` flows through `BlobDrawSource` to the GPU.

### Key Decision: Git-triggered Indexing (not file watching)

File watching creates staleness problems (orphaned chunks from renames, excessive re-indexing during active development, complex chunk diffing state). Git-triggered indexing is cleaner:

- **post-commit hook**: fires on all local commits; the hook script checks the current branch and skips non-main commits
- **post-merge hook**: fires on pulls/merges from remote (including fast-forwards); same branch check
- Both call `canopy index` which diffs against the last indexed SHA

Uncommitted work is not indexed — the agent reads those files directly. Canopy's value is navigating the large existing codebase, not the few files being actively edited.

### Key Decision: Index Main Only

No per-branch parallel indexes. Main is the canonical codebase state. Feature branches are short-lived and touch a small subset of files — the main index is 95-99% accurate for any branch. `canopy reindex` is available for the rare long-lived branch that restructures significant code.

### Key Decision: File-level Delete-and-Replace

When a file changes, all its chunks are deleted from EdgeQuake and the file is re-parsed and re-ingested. No chunk-level diffing. Git tells us which files changed — we work at that granularity.

### Key Decision: All-Local LLMs (to start)

- **Embeddings:** Ollama (e.g., `nomic-embed-text`) — always local
- **Entity extraction:** Ollama (e.g., `qwen2.5-coder`)
- **Synthesis:** Ollama (e.g., `qwen2.5-coder`), swappable to cloud later if quality is insufficient

EdgeQuake supports configuring different providers per operation, so upgrading synthesis to a cloud LLM is a config change.

## Canopy CLI

### Commands

| Command | What it does |
|---------|-------------|
| `canopy init` | Detect git root, register project with EdgeQuake, write `.canopy.toml`, install git hooks, full initial index |
| `canopy index` | Diff against last indexed SHA, re-parse changed files, send chunks to EdgeQuake, delete chunks for removed files, record new SHA |
| `canopy reindex` | Full re-index from scratch |
| `canopy status` | Show project info, last indexed SHA, chunk count, EdgeQuake connection status |
| `canopy mcp` | Start MCP stdio server for agents |

### `.canopy.toml` (per-project config)

```toml
[project]
name = "atlas"
edgequake_url = "http://localhost:8080"

[indexing]
last_sha = "abc123"
languages = ["rust", "toml"]  # optional filter, default: all tree-sitter-supported
ignore = ["target/", "vendor/"]  # in addition to .gitignore
merge_threshold = 20  # lines — chunks smaller than this get merged with siblings
split_threshold = 200  # lines — chunks larger than this get split at child boundaries
```

### Git Hooks

Installed by `canopy init`:

- `.git/hooks/post-commit` → check branch is main, then `canopy index`
- `.git/hooks/post-merge` → check branch is main, then `canopy index`

If hooks already exist, Canopy appends to them rather than overwriting. The hook invocation is non-blocking — if EdgeQuake is unreachable or indexing fails, the hook logs a warning and exits cleanly. The git workflow is never blocked by Canopy.

### MCP Interface

Single tool exposed to agents:

```
ask_codebase(question: string, mode?: "hybrid" | "local" | "global" | "naive")
```

Returns: synthesized answer + source chunks with file paths and line ranges.

## Tree-sitter Chunking

### Strategy

Parse → classify → merge small → split large → tag.

**Primary chunks** (each becomes an EdgeQuake document):
- Functions / methods
- Structs / enums / traits / interfaces / classes
- Impl blocks
- Module-level constants / statics

**Merge rule:** Adjacent chunks in the same file under `merge_threshold` lines (default 20) get bundled into a single document.

**Split rule:** Chunks over 200 lines get split at child boundaries (e.g., individual methods within a large impl block become their own documents).

**Doc comments:** Attached to the following declaration — part of the chunk, not separate documents.

**Split threshold** is configurable alongside merge threshold in `.canopy.toml`.

**Language support:** Bundle grammars for common languages (Rust, TypeScript, Python, Go, etc.) in Phase 1. Dynamic grammar loading via `tree-sitter-loader` deferred to Phase 3.

### Metadata Per Document

- `file_path`: relative to repo root
- `language`: rust, toml, etc.
- `node_kinds`: tree-sitter node types in this chunk
- `line_range`: start-end lines for source navigation
- `parent_scope`: enclosing module/impl context

## EdgeQuake Integration

### Open Questions (Phase 0 must resolve)

Three aspects of the EdgeQuake integration are unverified and must be prototyped before building the full CLI:

1. **Ingestion format**: EdgeQuake's `POST /api/v1/documents` expects file/document uploads. We need to confirm how to package tree-sitter chunks — likely as synthetic Markdown files with metadata in the body. The `edgequake-sdk` Rust crate (v0.3.0) should be used rather than raw HTTP.

2. **Double-chunking**: EdgeQuake runs its own chunking (1200 tokens, 100 overlap) on ingested documents. Our tree-sitter chunks are typically well under this threshold (most are 20-200 lines), so they likely pass through un-split. Must verify this — if EdgeQuake re-chunks our chunks, we need to either configure its chunk size or use a lower-level API.

3. **Deletion by metadata**: The file-level delete-and-replace strategy requires deleting all documents from a given file path. Must verify whether EdgeQuake supports this via its API or workspace filtering. Fallback: track EdgeQuake document IDs per file in `.canopy.toml` or a local SQLite file.

### Ingestion

- Each chunk sent as a document to EdgeQuake via the `edgequake-sdk` Rust crate
- Chunk metadata (file_path, language, node_kinds, line_range, parent_scope) included in the document body
- EdgeQuake embeds, runs LLM entity extraction, builds graph edges
- Exact packaging format to be determined during Phase 0 prototyping

### Deletion

- On file change: delete all documents belonging to that file path, then re-ingest new chunks
- On file delete: delete all documents for that path
- Deletion mechanism to be validated during Phase 0

### Querying

- `ask_codebase` MCP call → `POST /api/v1/query` to EdgeQuake
- Default mode: `hybrid` (local graph + global community detection)
- Canopy CLI enriches response with file paths and line ranges from chunk metadata

### LLM Configuration

Configured on EdgeQuake side:
- Embeddings: Ollama (`nomic-embed-text`)
- Entity extraction: Ollama (`qwen2.5-coder`)
- Synthesis: Ollama (`qwen2.5-coder`), swappable to cloud later

## Deployment

### EdgeQuake + PostgreSQL

- Docker Compose on archbtw using EdgeQuake's official compose file
- PostgreSQL with AGE + pgvector extensions (pre-configured)
- Runs alongside existing Ollama systemd service

### Canopy CLI

- Single Rust binary, installed to `~/.cargo/bin/canopy`
- No runtime dependencies beyond network access to EdgeQuake

### Per-project Setup

```
cd ~/dev/atlas
canopy init
```

### Agent MCP Configuration

Agent config points to `canopy mcp` as an MCP stdio server.

## Risks

**Entity extraction quality on code:** EdgeQuake's LightRAG entity extraction is designed for natural language documents. Whether it produces useful entities and relationships from raw source code with a local model (qwen2.5-coder) is the core architectural bet. Mitigation: even if entity extraction is mediocre, vector search over semantically-chunked code still provides value. Phase 0 validates this before committing to the full build.

## Phased Build Plan

### Phase 0: Prototype EdgeQuake Boundary

- Deploy EdgeQuake + PostgreSQL via Docker Compose on archbtw
- Feed a sample of Rust source files (from Atlas) through the ingestion API
- Verify: chunks pass through without double-chunking, or find configuration to prevent it
- Verify: documents can be deleted by file path metadata, or determine fallback
- Verify: entity extraction on code produces useful graph structure with qwen2.5-coder
- **Gate:** Do not proceed to Phase 1 until all three verifications pass or have confirmed workarounds

### Phase 1: Indexing Pipeline

- Canopy CLI with `init`, `index`, `reindex`, `status`
- Tree-sitter chunking with merge/split logic
- EdgeQuake integration (ingest + delete)
- Git hooks (with branch check, append-safe, non-blocking)
- Verify results via EdgeQuake's built-in web UI

### Phase 2: Query + MCP

- `canopy mcp` with `ask_codebase` tool
- Wire up EdgeQuake's query API
- Enrich responses with file paths + line ranges
- Test with a real agent against Atlas

### Phase 3: Tune and Harden

- Experiment with chunk sizes, merge thresholds, embedding models
- Evaluate synthesis quality, swap to cloud LLM if needed
- Handle edge cases (binary files, generated code, very large files)
