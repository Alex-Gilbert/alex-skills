# Network MCP Server — Design Spec

**Date:** 2026-03-18
**Status:** Approved

## Problem

The alex-memory MCP server runs as a local Claude Code plugin subprocess over stdio. Other Claude Code instances on the Tailnet cannot access the shared memory pool. The goal is to make this server the central brain for all agents on the network.

## Constraints

- Start with personal use (Alex's machines), scale to ~10 engineers
- Tailscale ACLs for auth (no API keys for prototype)
- Author identity from Tailscale peer headers
- Vault stays on the server machine — remote agents access through MCP API only
- Skills and hooks must continue working unchanged

## Design

### Dual-Transport Server

Add an HTTP listener alongside the existing stdio loop. Same `mcp_toolkit.Server` instance, two transports running concurrently.

- **Stdio** stays for the local plugin (zero-latency, no network)
- **SSE + Streamable HTTP** bind to a configurable port for remote agents
- Both transports share the same stateless server value

### Config Additions

```toml
[mcp]
transport = "stdio"        # existing
http_port = 7890           # new — port for remote access
http_enabled = true        # new — toggle network listener
default_author = "alex"    # new — author for local stdio requests
```

### HTTP Routes

| Method | Path | Handler | Purpose |
|--------|------|---------|---------|
| GET | `/sse` | `sse.handle_get` | Open SSE stream, get connection ID |
| POST | `/sse?id=<conn_id>` | `sse.handle_post` | Send MCP request, response via SSE |
| POST | `/mcp` | `rpc.handle_http_rpc` | Streamable HTTP (stateless request/response) |
| GET | `/health` | Simple 200 OK | Infrastructure health check |

SSE exists because Claude Code's remote MCP support uses it. Streamable HTTP is the newer MCP spec direction for future-proofing.

### Author Identity

Every memory write gets an `author` field:

- **Remote requests:** Extracted from `Tailscale-User-Login` HTTP header (injected automatically by Tailscale for authenticated peers)
- **Local stdio:** Defaults to `config.mcp.default_author`
- **Storage:** Written to YAML frontmatter and Qdrant payload as a filterable field
- **Not user-supplied:** `memory_store` does not accept an author param — always derived from transport context

Frontmatter example:

```yaml
---
type: bug
status: open
author: alex@example.com
created: 2026-03-18
---
```

`memory_find` and `memory_list` gain an optional `author` filter parameter.

### Startup Sequence Change

```
main():
  config.load()
  embedder.start()
  spawn(setup_infrastructure())
  spawn(run_stdio(server))      # was blocking, now spawned
  run_http(server, config)      # blocks on Mist accept loop (if http_enabled)
```

Both loops run concurrently as separate OTP processes. If `http_enabled = false`, skip `run_http` and block on stdio as before (backwards compatible).

### Remote Client Setup

Engineers on the Tailnet:

1. Clone the repo (gets skills + hooks)
2. Do NOT run `run-mcp.sh` locally
3. Add remote MCP server to `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "alex-memory": {
      "url": "http://<tailscale-hostname>:7890/sse"
    }
  }
}
```

Skills call tool names (`memory_store`, `memory_find`, etc.) — they don't care about the transport. Hooks inject the same context. Everything works.

### Tailscale ACLs

```json
{
  "acls": [
    { "action": "accept", "src": ["group:engineers"], "dst": ["memory-server:7890"] }
  ]
}
```

## What Changes

| File | Change |
|------|--------|
| `config.gleam` | Parse `http_port`, `http_enabled`, `default_author` |
| `config.toml` | Add those three fields |
| `server.gleam` | Add `run_http()` with Mist + SSE/RPC transports, author middleware |
| `alex_memory.gleam` | Spawn stdio in separate process, conditionally start HTTP listener |
| `vault_writer.gleam` | Accept and write `author` to frontmatter |
| `frontmatter.gleam` | Parse/serialize `author` field |
| `types.gleam` | Add `author` to `Metadata` type |
| `server.gleam` (handlers) | Thread author through `handle_store`, add `author` filter to `handle_find`/`handle_list` |

## What Doesn't Change

- Skills, hooks, plugin manifest
- Embedder, chunker, point ID generation
- Qdrant client, Ollama client
- Vault watcher
