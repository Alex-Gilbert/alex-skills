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

# Document ID tracking — maps file paths to EdgeQuake document IDs for deletion
# Managed automatically by `canopy index`
[documents]
"src/rendering/blob.rs" = ["dc5dcdba-55b2-4e5a-9ed9-49534699459b", "63ad371a-e501-417e-8ed1-7a2d110144fb"]
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

### Phase 0 Findings (Resolved)

All three open questions resolved. Full findings in `~/dev/canopy/docs/phase0-findings.md`.

1. **Ingestion format**: `POST /api/v1/documents` accepts JSON with `content` (raw text), `title`, and `metadata` fields. Raw `reqwest` HTTP calls work well (SDK not needed for Phase 1). No special packaging required — send code as plain text.

2. **Double-chunking**: Not an issue. EdgeQuake's default chunk size is 1200 tokens. Tree-sitter chunks (function/struct level) are naturally well under this threshold. All test files (34-38 lines) produced `chunk_count = 1`. **Constraint for Phase 1: keep tree-sitter chunks under ~1200 tokens (~300 lines of code).**

3. **Deletion**: `DELETE /api/v1/documents/{id}` works perfectly — removes chunks, entities, and relationships. **Cannot use title-based search** to find documents (list API has tenant-context issues). **Must track document IDs locally** — store `{file_path → [document_ids]}` mapping in `.canopy.toml` or a local SQLite file after each ingestion.

### Ingestion

- `POST /api/v1/documents` with JSON body: `content` (raw code), `title` (e.g., `chunk::src/foo.rs::FunctionName`), `metadata` (file_path, language, node_kinds, etc.)
- EdgeQuake embeds (nomic-embed-text), runs LLM entity extraction (qwen2.5-coder:7b), builds graph edges
- Processing time: ~2-3 seconds per chunk with local Ollama

### Deletion

- On file change: look up document IDs for that file from local storage, delete each via `DELETE /api/v1/documents/{id}`, then re-ingest new chunks and store new IDs
- On file delete: same deletion, no re-ingestion
- Local ID storage: section in `.canopy.toml` or SQLite file in `.canopy/` directory

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

- Docker Compose on archbtw using EdgeQuake's official compose file (from `~/dev/edgequake/edgequake/docker/`)
- PostgreSQL with AGE + pgvector extensions (custom Dockerfile, pre-configured)
- EdgeQuake container runs with `--network host` (required for reliable Ollama connectivity — bridge networking has iptables issues)
- Ollama systemd service must bind to `0.0.0.0` (not `127.0.0.1`) via `Environment="OLLAMA_HOST=0.0.0.0"`
- Model config via env vars: `OLLAMA_MODEL=qwen2.5-coder:7b`, `EDGEQUAKE_DEFAULT_LLM_MODEL=qwen2.5-coder:7b`, `OLLAMA_EMBEDDING_MODEL=nomic-embed-text`

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

### Phase 0: Prototype EdgeQuake Boundary (COMPLETE)

All validations passed. See `~/dev/canopy/docs/phase0-findings.md` for details.
- No double-chunking (chunk_count=1 for all test files)
- Deletion by document ID works; local ID tracking required
- Entity extraction excellent (24 entities, 17 relationships from 3 small files)
- Graph RAG decisive (hybrid mode: detailed answers; naive mode: nothing)

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
