# HTTP-Only MCP Server Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove stdio transport and make the alex-memory MCP server an HTTP-only systemd service.

**Architecture:** Single-transport HTTP server on port 7890 managed by systemd. Claude Code clients connect via URL. Plugin stays for skills/hooks distribution only.

**Tech Stack:** Gleam/OTP, mcp_toolkit, Mist HTTP server, systemd

**Spec:** `docs/superpowers/specs/2026-03-18-http-only-mcp-server-design.md`

---

## Chunk 1: Strip stdio, simplify config

### Task 1: Remove `transport` and `http_enabled` from config

**Files:**
- Modify: `src/alex_memory/config.gleam:22-29` (McpConfig type)
- Modify: `src/alex_memory/config.gleam:93-104` (parsing)
- Modify: `src/alex_memory/config.gleam:126-131` (McpConfig construction)
- Modify: `config/config.toml:19-23` (mcp section)
- Modify: `test/alex_memory/config_test.gleam:24-28,44-46` (test TOML and assertions)

- [ ] **Step 1: Update McpConfig type**

In `src/alex_memory/config.gleam`, replace the `McpConfig` type:

```gleam
pub type McpConfig {
  McpConfig(
    http_port: Int,
    default_author: String,
  )
}
```

- [ ] **Step 2: Update config parsing**

In `src/alex_memory/config.gleam`, remove the `mcp_transport` and `mcp_http_enabled` parsing blocks (lines 93-104). Remove those fields from the `McpConfig` constructor (lines 126-131). The mcp section becomes:

```gleam
      let mcp_http_port =
        tom.get_int(doc, ["mcp", "http_port"])
        |> result.unwrap(7890)

      let mcp_default_author =
        tom.get_string(doc, ["mcp", "default_author"])
        |> result.unwrap("")

      // ... inside Ok(Config(...)):
        mcp: McpConfig(
          http_port: mcp_http_port,
          default_author: mcp_default_author,
        ),
```

- [ ] **Step 3: Update config.toml**

Replace the `[mcp]` section in `config/config.toml`:

```toml
[mcp]
http_port = 7890
default_author = "alex"
```

- [ ] **Step 4: Update the config test**

Remove `transport` and `http_enabled` from the test TOML string and assertions. The test TOML becomes:

```gleam
// In test/alex_memory/config_test.gleam, replace the [mcp] section in the toml string:
[mcp]
http_port = 7890
default_author = \"alex\"
```

Remove these assertion lines:
```gleam
c.mcp.transport |> should.equal("stdio")
c.mcp.http_enabled |> should.equal(True)
```

- [ ] **Step 5: Fix compilation errors in alex_memory.gleam**

`src/alex_memory.gleam` references `cfg.mcp.http_enabled`. Comment out or stub the `http_enabled` conditionals temporarily — Task 2 will replace the entire main function. Minimum fix: remove the two `case cfg.mcp.http_enabled` blocks and unconditionally call `http_server.start` and `process.sleep_forever()`.

- [ ] **Step 6: Run tests**

Run: `gleam test -- --exact -- config_test`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add src/alex_memory/config.gleam config/config.toml test/alex_memory/config_test.gleam
git commit -m "refactor: remove transport and http_enabled config keys"
```

### Task 2: Remove stdio transport and simplify main

**Files:**
- Modify: `src/alex_memory.gleam` (entire file — remove stdio, remove conditionals)
- Modify: `src/alex_memory/mcp/server.gleam:17,671-692` (remove stdio import, `run_stdio`, `do_run_stdio`)

- [ ] **Step 1: Remove stdio functions from server.gleam**

In `src/alex_memory/mcp/server.gleam`:
- Remove the import: `import mcp_toolkit/transport/stdio`
- Delete the `run_stdio` function (lines 672-675)
- Delete the `do_run_stdio` function (lines 677-692)

- [ ] **Step 2: Simplify alex_memory.gleam main**

Replace the entire `main()` function in `src/alex_memory.gleam`:

```gleam
pub fn main() {
  io.println_error("Starting alex_memory...")

  // Load config (fast, local file read)
  let assert Ok(cfg) = config.load("config/config.toml")
  io.println_error("Config loaded")

  // Start embedder immediately (it can queue messages before infra is ready)
  let assert Ok(embedder_subject) = embedder.start(cfg)

  // Build the MCP server
  let server = mcp_server.build(cfg, embedder_subject)

  // Start infrastructure setup in a background process
  let _ = process.spawn(fn() { setup_infrastructure(cfg, embedder_subject) })

  // Start HTTP server (fatal on failure — e.g. port conflict)
  let assert Ok(_) = http_server.start(cfg, server)
  io.println_error("MCP server ready on port " <> string.inspect(cfg.mcp.http_port))

  // Keep BEAM alive for HTTP clients
  process.sleep_forever()
}
```

Also update imports — add `import gleam/string` if not present, remove any stdio-specific imports.

- [ ] **Step 3: Verify compilation**

Run: `gleam build`
Expected: Compiles with no errors.

- [ ] **Step 4: Commit**

```bash
git add src/alex_memory.gleam src/alex_memory/mcp/server.gleam
git commit -m "refactor: remove stdio transport, HTTP-only server"
```

### Task 3: Delete run-mcp.sh

**Files:**
- Delete: `run-mcp.sh`

- [ ] **Step 1: Delete the file**

```bash
rm run-mcp.sh
```

- [ ] **Step 2: Search for references**

Search the codebase for any references to `run-mcp.sh` (docs, config, plugin files):

```bash
grep -r "run-mcp" .
```

Remove or update any references found.

- [ ] **Step 3: Commit**

```bash
git add -u run-mcp.sh
git commit -m "chore: delete run-mcp.sh — server managed by systemd"
```

## Chunk 2: Systemd unit and deployment

### Task 4: Create systemd unit file

**Files:**
- Create: `deploy/alex-memory.service`

- [ ] **Step 1: Create the deploy directory and unit file**

```bash
mkdir -p deploy
```

Write `deploy/alex-memory.service`:

```ini
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

- [ ] **Step 2: Commit**

```bash
git add deploy/alex-memory.service
git commit -m "feat: add systemd unit file for alex-memory server"
```

### Task 5: Install and start the service

This task is manual — not code changes.

- [ ] **Step 1: Kill the existing process**

```bash
kill 111673
```

(Or whatever PID is currently running on port 7890.)

- [ ] **Step 2: Install the systemd service**

```bash
sudo cp deploy/alex-memory.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now alex-memory
```

- [ ] **Step 3: Verify it started**

```bash
systemctl status alex-memory
curl http://localhost:7890/health
```

Expected: Service active, health endpoint returns `{"status":"ok"}`.

### Task 6: Configure Claude Code to use URL

- [ ] **Step 1: Add mcpServers entry**

Add to `~/.claude/settings.json` under `mcpServers`:

```json
{
  "mcpServers": {
    "alex-memory": {
      "url": "http://localhost:7890/sse"
    }
  }
}
```

- [ ] **Step 2: Verify MCP tools work**

Restart Claude Code and confirm that `memory_find`, `memory_store`, `memory_list`, `memory_update`, and `memory_reindex` tools are available and functional.
