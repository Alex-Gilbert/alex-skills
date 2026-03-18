# MCP to REST Migration Design

**Status:** APPROVED
**Date:** 2026-03-18
**Supersedes:** 2026-03-18-http-only-mcp-server-design.md

## Summary

Remove the MCP protocol layer (mcp_toolkit, SSE, JSON-RPC) from alex-memory and replace it with a plain REST API. Agents interact via curl commands taught by skills. Configuration via `MEMORY_API_URL` and `MEMORY_API_AUTHOR` env vars in Claude Code settings.

## Motivation

MCP adds a brittle, unpredictable protocol layer between agents and what is fundamentally a CRUD + search API. The 5 operations change rarely, the only consumers are Claude Code agents, and skills already provide the "when and why" context that MCP's tool discovery is supposed to deliver. A plain REST API is simpler to debug, deploy, and consume.

## Routes

```
POST   /memories          → store a new memory
POST   /memories/search   → semantic search
GET    /memories           → list with filters
GET    /memories/*path     → read raw markdown file
PATCH  /memories           → update existing memory
POST   /memories/reindex   → trigger full re-index
GET    /health             → health check
```

## Request Formats

### POST /memories (store)

```json
{
  "title": "Bug title",
  "content": "Markdown body",
  "memory_type": "bug",
  "status": "open",
  "severity": "p1",
  "tags": ["auth", "login"]
}
```

Required: `title`, `content`, `memory_type`

### POST /memories/search (find)

```json
{
  "query": "search terms",
  "type": "bug",
  "status": "open",
  "tags": ["auth"],
  "author": "alex",
  "limit": 10
}
```

Required: `query`

### GET /memories (list)

Query params: `type`, `status`, `tags` (comma-separated), `author`, `sort_by`

Example: `GET /memories?type=bug&status=open&tags=auth,login`

### GET /memories/*path (read)

Path is vault-relative. Example: `GET /memories/Claude/bugs/auth-bug.md`

Returns raw markdown file content (frontmatter + body), verbatim.

### PATCH /memories (update)

```json
{
  "vault_path": "Claude/bugs/auth-bug.md",
  "status": "resolved",
  "tags": ["auth"],
  "content": "Updated markdown body"
}
```

Required: `vault_path`

### POST /memories/reindex

Empty body. Triggers full vault re-index.

## Response Formats

### Search results — TOON (text/toon)

```
results[3]{title,score,type,path,status,author,preview}:
  Memory system first working,0.78,memory,Claude/memory/mem.md,active,alex,The memory system is now operational...
  HTTP-only MCP design,0.71,brainstorm,Claude/brainstorms/http.md,active,alex,Removes stdio transport entirely...
  MCP server decision,0.64,decision,Claude/decisions/mcp-http.md,active,alex-gilbert,On 2026-03-18...
```

### List results — TOON (text/toon)

```
memories[2]{title,type,status,author,path,updated}:
  Auth bug in login,bug,open,alex,Claude/bugs/auth-bug.md,2026-03-18
  HTTP design,brainstorm,active,alex,Claude/brainstorms/http.md,2026-03-17
```

### Read — raw markdown (text/markdown)

Verbatim file content from disk.

### Store/update/reindex — plain text (text/plain)

Confirmation message, e.g. `stored: Claude/bugs/auth-bug.md`

### Errors

HTTP status codes with plain text body:

- 400: missing required fields, invalid type/status enum values
- 404: memory file not found (read endpoint)
- 500: internal error (qdrant/ollama unavailable)

## Author Identity

Passed via `X-Author` HTTP header. Falls back to config `default_author` if not present.

Stored in Claude Code settings as `MEMORY_API_AUTHOR` env var. Skills template it into curl commands:

```bash
curl -s -H "X-Author: $MEMORY_API_AUTHOR" ...
```

## TOON Encoding

TOON (Token-Oriented Object Notation) is used for search and list responses. It provides ~40% fewer tokens than JSON with higher LLM comprehension accuracy.

No library dependency — TOON encoding is implemented as string formatting helpers in Gleam. The response shapes are uniform arrays of objects, which is TOON's sweet spot.

Quoting rules applied: strings containing commas, colons, quotes, brackets, braces, or that look like numbers/booleans are quoted.

## Configuration

### config/config.toml

Rename `[mcp]` section to `[http]`:

```toml
[http]
port = 7890
default_author = "alex"
```

### Claude Code settings

```json
{
  "env": {
    "MEMORY_API_URL": "http://localhost:7890",
    "MEMORY_API_AUTHOR": "alex"
  }
}
```

Project-level `.claude/settings.json` provides defaults. User-level `.claude/settings.local.json` provides overrides for remote/different setups.

## What Changes

### Deleted

- `mcp_toolkit` dependency from gleam.toml
- All `mcp_toolkit` imports
- SSE registry setup
- MCP tool schemas (JSON strings in server.gleam)
- `CallToolRequest`/`CallToolResult` wrappers
- `text_result()` and `error_result()` helpers
- `/sse` and `/mcp` routes

### Rewritten

- `http_server.gleam` — REST routes, JSON body parsing, X-Author header, TOON/text responses
- `server.gleam` — handlers take arg types directly, return `Result(String, String)`

### Added

- `memory_read` handler + `GET /memories/*path` route
- TOON string formatting helpers
- Env var documentation

### Untouched

- `types.gleam`
- `vault_writer.gleam`
- `author.gleam` (FFI)
- `dashboard_writer.gleam`
- `embedder.gleam`, `vault_watcher.gleam`, `chunker.gleam`, `frontmatter.gleam`, `point_id.gleam`
- `qdrant_client.gleam`, `ollama_client.gleam`
- `deploy/alex-memory.service`

### Updated outside Gleam

- Skills that call `mcp__alex-memory__*` tools — rewritten to teach curl contracts
- Claude Code settings — `MEMORY_API_URL` and `MEMORY_API_AUTHOR` env vars
- `config/config.toml` — rename `[mcp]` to `[http]`

## Skill Contract

Skills become the API documentation. Each skill that needs memory includes curl commands referencing `$MEMORY_API_URL` and `$MEMORY_API_AUTHOR`. Example:

```
To search memory, run:
curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
  -d '{"query": "search terms", "type": "bug", "limit": 10}' \
  $MEMORY_API_URL/memories/search
```

No MCP client configuration needed. No tool discovery. Skills provide the when/why/how.
