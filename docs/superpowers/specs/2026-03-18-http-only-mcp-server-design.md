# HTTP-Only MCP Server — Design Spec

**Date:** 2026-03-18
**Status:** Approved
**Supersedes:** Dual-transport portions of `2026-03-18-network-mcp-server-design.md`

## Problem

The alex-memory MCP server runs as a Claude Code plugin subprocess over stdio, and also starts an HTTP listener on port 7890. When the server is already running (e.g. started manually or by systemd), the plugin spawns a second instance that crashes on `Eaddrinuse`. Running multiple BEAM instances of the same server is wasteful and error-prone.

## Decision

Remove stdio transport entirely. The server becomes an HTTP-only systemd service. Claude Code clients connect via URL (`http://host:7890/sse`) instead of spawning a subprocess. One BEAM, one transport, one process.

## Architecture

```
systemd → alex-memory server → HTTP on :7890
Claude Code → connects to http://localhost:7890/sse (local)
            → connects to http://<tailscale-host>:7890/sse (remote)
```

The Claude Code plugin stays in the repo to distribute skills and hooks. It no longer spawns a subprocess.

## What Gets Removed

| Item | Reason |
|------|--------|
| `run-mcp.sh` | No subprocess to launch |
| `mcp_server.run_stdio(server)` in `alex_memory.gleam` | No stdio transport |
| `transport` config key | HTTP is the only transport |
| `http_enabled` config key | HTTP is always on |
| Conditional `sleep_forever()` | Server always stays alive |

## What Gets Added

| Item | Purpose |
|------|---------|
| `deploy/alex-memory.service` | Systemd unit file |

## What Gets Modified

### `alex_memory.gleam` — Simplified Main

```
main():
  config.load()
  embedder.start()
  server = build(config, embedder)
  spawn(setup_infrastructure())
  assert Ok(_) = http_server.start(server)  # fatal on failure (e.g. port conflict)
  sleep_forever()                            # keep BEAM alive
```

No stdio, no conditional branching. HTTP startup failure (including `Eaddrinuse`) is fatal — the server crashes with a clear error message. Systemd's `Restart=on-failure` handles transient issues.

### `config.toml` / `config.gleam`

Remove `transport` and `http_enabled` keys. Keep `http_port` and `default_author`. No backwards compatibility shim — this is a breaking config change, users update their `config.toml`.

```toml
[mcp]
http_port = 7890
default_author = "alex"
```

### `http_server.gleam`

No route changes. Improve error handling: log clearly and exit on port conflict instead of silently failing.

### `.claude-plugin/plugin.json`

No changes — provides skills/hooks, no MCP subprocess.

## Systemd Unit

```ini
# deploy/alex-memory.service
[Unit]
Description=alex-memory MCP server
After=network.target ollama.service
Wants=ollama.service

[Service]
Type=simple
User=alex
WorkingDirectory=/home/alex/dev/alex-memory
ExecStart=/usr/bin/gleam run
Restart=on-failure
RestartSec=5
Environment=HOME=/home/alex

[Install]
WantedBy=multi-user.target
```

- `After=ollama.service` — starts after Ollama (used for embeddings)
- `Wants=` not `Requires=` — server handles Ollama unavailability gracefully
- Qdrant is Docker-managed with its own restart policy

### Installation

```bash
sudo cp deploy/alex-memory.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now alex-memory
```

## Client Setup

Users add to `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "alex-memory": {
      "url": "http://localhost:7890/sse"
    }
  }
}
```

Remote users on Tailnet use the Tailscale hostname instead of localhost.

## What Doesn't Change

- Skills, hooks, plugin manifest (distribution only)
- HTTP routes (`/sse`, `/mcp`, `/health`)
- Author identity (still from Tailscale headers for remote, `default_author` for local)
- Embedder, chunker, vault watcher, Qdrant/Ollama clients
- Tailscale ACL setup
