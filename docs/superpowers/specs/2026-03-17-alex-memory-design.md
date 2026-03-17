# Alex Memory — Design Specification

**Date:** 2026-03-17
**Status:** Approved

## Overview

A GPU-accelerated semantic memory system for Claude Code, built on the BEAM (Gleam/OTP). Combines an Obsidian vault as the human-readable source of truth with a Qdrant vector database as the semantic search layer. Includes a forked superpowers skill suite with memory-aware workflows.

## Goals

- Give Claude Code persistent, searchable memory across conversations
- Leverage a local RTX 5090 for fast embedding via Ollama
- Store memories as browsable .md files in an Obsidian vault
- Integrate memory recall/store into existing brainstorming, debugging, and planning workflows
- Provide explicit skills (`/remember`, `/recall`, `/bugs`, `/status`) and automatic behaviors (session start/end)

## Architecture

### Approach: Monolith OTP App with Supervision Tree Isolation

Single Gleam application with isolated supervision scopes. If the indexer crashes, MCP stays up. If infra goes down, everything restarts cleanly.

```
alex_memory (Application)
└── RootSupervisor (one_for_one)
    ├── InfraScope (rest_for_one)
    │   ├── OllamaClient (GenServer)
    │   │   - HTTP connection to Ollama
    │   │   - embed(text) -> vector
    │   │   - Health checks on startup
    │   └── QdrantClient (GenServer)
    │       - HTTP connection to Qdrant
    │       - upsert/search/filter operations
    │       - Creates collections on startup if missing
    │
    ├── IndexerScope (rest_for_one)
    │   ├── VaultWatcher (GenServer)
    │   │   - BEAM :fs to watch ~/alex-vault/
    │   │   - Debounces rapid file changes (500ms)
    │   │   - Sends changed file paths to Embedder
    │   └── Embedder (GenServer)
    │       - Parses frontmatter + content
    │       - Chunks by heading boundaries (h2/h3)
    │       - Calls OllamaClient.embed() per chunk
    │       - Upserts vectors + payload to Qdrant
    │
    └── MCPScope (one_for_one)
        └── MCPServer (Mist)
            - stdio or SSE transport via mcp_toolkit
            - Tools: memory_store, memory_find, memory_list, memory_update
            - On store: writes .md to vault, then sends to Embedder
```

### Infrastructure

- **Qdrant** — Docker container, local vector database
- **Ollama** — Local LLM/embedding runtime, GPU-accelerated (RTX 5090)
- **Embedding model** — Ollama-served, default `nomic-embed-text` (768 dimensions). Changing models requires a full re-index.

### Language Choice: Gleam

Gleam on the BEAM is chosen for:
- OTP supervision trees (ideal for long-running services with isolated failure domains)
- Concurrent file watching + embedding + serving
- Type safety
- Future investment in the BEAM ecosystem

Both Qdrant and Ollama are accessed via REST/HTTP APIs — no native client libraries needed.

### Key dependency: `mcp_toolkit`

Gleam MCP library providing typed server builder, stdio + SSE transports, JSON schema helpers. OTP 27+/Gleam 1.12+.

## Data Model

### Memory Document Structure

Every memory exists in two places:

**1. Vault file** (source of truth):

```markdown
---
type: bug
status: open
severity: p1
tags: [cook, scheduler]
created: 2026-03-17
updated: 2026-03-17
source: conversation
---

# Scheduler Race Condition

The scheduler can deadlock when two recipes share an ingredient...
```

**2. Qdrant point** (search layer):

```json
{
  "type": "bug",
  "status": "open",
  "severity": "p1",
  "tags": ["cook", "scheduler"],
  "created": "2026-03-17",
  "updated": "2026-03-17",
  "source": "conversation",
  "vault_path": "Claude/bugs/scheduler-race-condition.md",
  "title": "Scheduler Race Condition",
  "content": "The scheduler can deadlock when...",
  "chunk_index": 0,
  "chunk_total": 1
}
```

### Memory Types

| Type | Purpose | Auto-created when... |
|------|---------|---------------------|
| `bug` | Bug reports with status tracking | Claude identifies or discusses a bug |
| `decision` | Design decisions + reasoning | Brainstorm concludes, architecture choice made |
| `project` | Progress, milestones, goals | Project work is discussed |
| `memory` | User preferences, corrections, learned behavior | Claude learns something about how you work |
| `pattern` | Code patterns and conventions | Claude notices or user describes a convention |
| `session` | Session summaries | Conversation ends (via hook) |
| `reference` | External links, docs, dashboards | User mentions external resources |
| `brainstorm` | Brainstorm outputs, design specs | Brainstorm skill completes |

### Metadata Fields

| Field | Required | Values |
|-------|----------|--------|
| `type` | Yes | One of the types above |
| `status` | No | `open`, `resolved`, `active`, `archived`, `wontfix` |
| `severity` | No | `p0`, `p1`, `p2`, `p3` (bugs only) |
| `tags` | No | List of strings |
| `created` | Yes | ISO date |
| `updated` | Yes | ISO date |
| `source` | Yes | `conversation`, `vault`, `manual` |
| `vault_path` | Yes | Path relative to vault root |
| `schema_version` | Yes | Integer, current: `1`. Used for future migration — re-index from vault when bumped. |

### Point ID Strategy

Qdrant point IDs are deterministic UUIDs generated from `sha256(vault_path + ":" + chunk_index)` truncated to UUID v5 format. This ensures:
- Idempotent upserts — re-embedding the same chunk overwrites the same point
- Clean re-indexing — no duplicates

### Chunking Strategy

Long notes split into chunks at h2/h3 heading boundaries for semantic coherence. Each chunk gets its own vector but shares metadata. `chunk_index` and `chunk_total` fields allow full document reconstruction.

**On re-embed (file edited):** Delete all existing points for that `vault_path` first, then upsert new chunks. This handles the case where chunk count changes (e.g., a heading was removed).

## Vault Structure

### Claude's memory folder

```
~/alex-vault/Claude/
├── bugs/
├── decisions/
├── projects/
├── memory/
├── patterns/
├── sessions/
├── references/
└── brainstorms/
```

Separated from user's PARA structure. Clear boundary between human notes and Claude-generated content.

### Two directions of data flow

**Vault → Qdrant (indexing):**
- VaultWatcher detects file changes via BEAM `:fs`
- Debounce 500ms to batch rapid edits
- Embedder parses frontmatter + content, chunks, embeds, upserts
- Covers entire vault, not just `Claude/` folder

**Claude → Vault → Qdrant (memory creation):**
- Claude calls `memory_store` via MCP
- MCPServer writes .md to `~/alex-vault/Claude/{type}/{slug}.md`
- MCPServer sends path to Embedder for indexing

**Deletions:** When a .md file is removed, VaultWatcher deletes all Qdrant points matching that `vault_path`.

**Edits in Obsidian:** If frontmatter is edited in Obsidian (e.g., `status: open` → `status: resolved`), VaultWatcher re-embeds and Qdrant metadata updates automatically. Obsidian is always authoritative.

**Ignores:** `.obsidian/`, `.git/`, binary attachments, non-markdown files. Configurable via `config.toml`.

## MCP Tools

| Tool | Parameters | Returns |
|------|-----------|---------|
| `memory_store` | `content`, `title`, `type`, `status?`, `severity?`, `tags?` | `vault_path`, `point_id` |
| `memory_find` | `query`, `type?`, `status?`, `tags?`, `limit?` | List of matches with score + metadata |
| `memory_list` | `type?`, `status?`, `tags?`, `sort_by?` | List of memories (filter only, no semantic search) |
| `memory_update` | `vault_path`, `status?`, `tags?`, `content?` | Updated memory |
| `memory_reindex` | `full?` (default: false) | Count of re-indexed documents |

`memory_find` embeds the query via Ollama, searches nearest neighbors in Qdrant, applies optional metadata filters. `memory_list` is pure metadata filtering for structured queries like "all open bugs."

`memory_update` always operates on the vault file (identified by `vault_path`). It rewrites the .md file with updated frontmatter/content, then the normal VaultWatcher → Embedder pipeline handles re-indexing.

`memory_reindex` forces a re-index. Without `full`, re-indexes only files modified since last index. With `full=true`, drops and rebuilds the entire collection from vault.

## Claude Code Integration

### Repo Structure

```
~/dev/alex-memory/
│
├── .claude-plugin/
│   └── plugin.json
│
├── gleam.toml
├── src/
│   ├── alex_memory.gleam
│   ├── infra/
│   │   ├── ollama_client.gleam
│   │   └── qdrant_client.gleam
│   ├── indexer/
│   │   ├── vault_watcher.gleam
│   │   ├── embedder.gleam
│   │   └── frontmatter.gleam
│   ├── mcp/
│   │   └── server.gleam
│   └── types.gleam
│
├── docker-compose.yml
├── config/
│   └── config.toml
│
├── skills/                        # Forked from obra/superpowers
│   ├── brainstorming/             # MODIFIED — memory-aware
│   ├── systematic-debugging/      # MODIFIED — memory-aware
│   ├── writing-plans/             # MODIFIED — memory-aware
│   ├── executing-plans/           # MODIFIED — memory-aware
│   ├── using-superpowers/         # MODIFIED — registers memory skills
│   ├── dispatching-parallel-agents/
│   ├── finishing-a-development-branch/
│   ├── receiving-code-review/
│   ├── repo-standards/
│   ├── requesting-code-review/
│   ├── subagent-driven-development/
│   ├── test-driven-development/
│   ├── using-git-worktrees/
│   ├── verification-before-completion/
│   ├── writing-skills/
│   ├── remember/                  # NEW
│   ├── recall/                    # NEW
│   ├── bugs/                      # NEW
│   └── status/                    # NEW
│
├── hooks/
│   ├── hooks.json
│   ├── run-hook.cmd
│   └── session-start              # MODIFIED — injects memory context
│
├── agents/
│   └── code-reviewer.md
│
├── commands/
│   ├── brainstorm.md
│   ├── execute-plan.md
│   ├── write-plan.md
│   ├── remember.md                # NEW
│   ├── recall.md                  # NEW
│   ├── bugs.md                    # NEW
│   └── status.md                  # NEW
│
├── docs/
├── tests/
├── package.json
├── LICENSE
└── README.md
```

### New Skills

**`/remember`** — Explicit memory store. Accepts natural language, Claude determines type and metadata, writes to vault + Qdrant.

**`/recall`** — Explicit semantic search. Accepts a query, optional filters. Returns matches with scores and vault paths.

**`/bugs`** — Bug management. List open bugs, filter by tag, resolve bugs by description.

**`/status`** — Project progress. List active projects, show progress for a specific project.

### Modified Skills

**brainstorming/SKILL.md:**
- Step 1 "Explore project context" extended to call `memory_find` for related decisions, brainstorms, and open bugs, plus `memory_list(type=pattern)` for conventions.
- New step 6.5 "Store to memory" after writing design doc — stores brainstorm as `type=brainstorm`, extracts key decisions as individual `type=decision` entries.

**systematic-debugging/SKILL.md:**
- New step 0 "Check memory" — `memory_find` for prior bugs with similar symptoms, `memory_list(type=bug, status=resolved)` to check if this was fixed before.
- Post-resolution step stores the bug with `type=bug, status=resolved` and root cause + fix.

**writing-plans/SKILL.md:**
- New step 0 "Recall context" — `memory_find` for related decisions and patterns, surfaces constraints from prior brainstorms.

**executing-plans/SKILL.md:**
- On completion, stores notable outcomes and any new patterns discovered.

**using-superpowers/SKILL.md:**
- Updated skill registry to include `remember`, `recall`, `bugs`, `status`.

### Automatic Behaviors

**On conversation start (SessionStart hook):**
1. `memory_find` with query derived from working directory + user message context
2. Surface relevant memories as internal context
3. Mention open bugs or active project items for this repo

**On conversation end (CLAUDE.md instruction, not a hook):**

There is no reliable session-end hook in Claude Code (the user can close the terminal). Instead, CLAUDE.md instructs Claude to summarize and store before signing off. A `/session-end` skill is also available for explicit invocation.

1. Summarize what was accomplished
2. Store as `type=session` with relevant tags
3. Extract any confirmed bugs identified → `type=bug` entries
4. Extract any decisions made → `type=decision` entries

**During normal work (CLAUDE.md instructions):**

Auto-store triggers require judgment, not reflexive storage:

- Bug **confirmed** (not speculative) → auto-store `type=bug, status=open`
- User **explicitly corrects** Claude → auto-store `type=memory`
- Code pattern **agreed upon** or demonstrated repeatedly → auto-store `type=pattern`
- External link **with clear ongoing relevance** → auto-store `type=reference`

Before auto-storing, Claude should `memory_find` with a high similarity threshold (>0.85) to avoid near-duplicate entries. If a similar memory exists, update it instead of creating a new one.

### Installation

Single plugin install replacing the current superpowers plugin. The `.claude-plugin/plugin.json` makes the entire repo a Claude Code plugin. The Gleam MCP server runs as a separate process (`gleam run`) alongside Docker services.

## Configuration

### `config/config.toml`

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
vector_dimension = 768  # Must match embedding model (nomic-embed-text = 768)

[indexer]
debounce_ms = 500
chunk_max_tokens = 512

[mcp]
transport = "stdio"  # "sse" available for multi-client setups
# port = 22370       # Only used when transport = "sse"
```

### `docker-compose.yml`

```yaml
services:
  qdrant:
    image: qdrant/qdrant
    ports:
      - "6333:6333"
    volumes:
      - qdrant_data:/qdrant/storage

  ollama:
    image: ollama/ollama
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

volumes:
  qdrant_data:
  ollama_data:
```

## Startup & Resilience

### OllamaClient startup

On init, OllamaClient:
1. Health-checks Ollama at the configured URL
2. Checks if the configured embedding model is available (`GET /api/tags`)
3. If model is missing, pulls it automatically (`POST /api/pull`)
4. Verifies embedding dimensions match `vector_dimension` config

### Qdrant as a derived cache

Qdrant is a search index, not the source of truth. The vault is authoritative. If the Qdrant volume is lost, `memory_reindex(full=true)` rebuilds everything from vault .md files. This is documented as the recovery procedure.

### Error handling: vault write vs embed

If a `memory_store` writes the .md file to vault but the embed call fails, the VaultWatcher will detect the new file and retry embedding on its next cycle. No data is lost — the vault file exists, Qdrant will catch up.

### Session-start timeout

The SessionStart hook has a 3-second timeout for memory recall. If Ollama or Qdrant are unavailable (containers not running), Claude proceeds without memory context and logs a warning. Memory tools remain available for explicit use once services come up.

## Open Questions

- **Ollama containerized vs host-installed?** Docker GPU passthrough works but adds a layer. Host-installed Ollama may be simpler since Alex plans to use it for other things too. Leaning toward host-installed.
- **MCP transport:** Start with stdio, add SSE later if needed.
