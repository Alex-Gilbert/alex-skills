# MCP to REST Migration Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the MCP protocol layer with a plain REST API using TOON-formatted responses.

**Architecture:** Strip mcp_toolkit, rewrite http_server.gleam as a REST router, refactor server.gleam handlers to pure functions returning strings, add TOON formatting helpers. Skills updated to teach agents curl commands.

**Tech Stack:** Gleam, Mist (HTTP server), gleam_json (body parsing), TOON (response format, hand-built strings)

**Spec:** `docs/superpowers/specs/2026-03-18-mcp-to-rest-migration-design.md`

---

## Chunk 1: Config and Dependency Cleanup

### Task 1: Rename [mcp] config section to [http]

**Files:**
- Modify: `config/config.toml`
- Modify: `src/alex_memory/config.gleam`
- Modify: `test/alex_memory/config_test.gleam`

- [ ] **Step 1: Update config_test.gleam — change [mcp] to [http] and field references**

In `test/alex_memory/config_test.gleam`, change the TOML string and assertions:

```gleam
// In parse_config_test(), replace the [mcp] block in the TOML string:
// OLD:
// [mcp]
// http_port = 7890
// default_author = \"alex\"
// NEW:
// [http]
// port = 7890
// default_author = \"alex\"

// And update assertions at the end:
// OLD:
//   c.mcp.http_port |> should.equal(7890)
//   c.mcp.default_author |> should.equal("alex")
// NEW:
//   c.http.port |> should.equal(7890)
//   c.http.default_author |> should.equal("alex")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test -- --module alex_memory/config_test`
Expected: Compilation error — `McpConfig` type and `c.mcp` field don't match new names.

- [ ] **Step 3: Update config.gleam**

In `src/alex_memory/config.gleam`:

Rename `McpConfig` to `HttpConfig`:
```gleam
pub type HttpConfig {
  HttpConfig(
    port: Int,
    default_author: String,
  )
}
```

Update `Config` type:
```gleam
pub type Config {
  Config(
    vault: VaultConfig,
    ollama: OllamaConfig,
    qdrant: QdrantConfig,
    indexer: IndexerConfig,
    http: HttpConfig,
  )
}
```

Update the `parse` function — change TOML keys from `["mcp", "http_port"]` to `["http", "port"]` and `["mcp", "default_author"]` to `["http", "default_author"]`:
```gleam
      let http_port =
        tom.get_int(doc, ["http", "port"])
        |> result.unwrap(7890)

      let http_default_author =
        tom.get_string(doc, ["http", "default_author"])
        |> result.unwrap("")

      // In the Config constructor:
      //   http: HttpConfig(
      //     port: http_port,
      //     default_author: http_default_author,
      //   ),
```

- [ ] **Step 4: Update config.toml**

In `config/config.toml`, rename the section:
```toml
[http]
port = 7890
default_author = "alex"
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `gleam test -- --module alex_memory/config_test`
Expected: PASS (both `parse_config_test` and `load_from_file_test`)

- [ ] **Step 6: Commit**

```bash
git add config/config.toml src/alex_memory/config.gleam test/alex_memory/config_test.gleam
git commit -m "refactor: rename [mcp] config section to [http]"
```

### Task 2: Remove mcp_toolkit dependency

**Files:**
- Modify: `gleam.toml`

- [ ] **Step 1: Remove mcp_toolkit from gleam.toml**

Delete this line from the `[dependencies]` section:
```
mcp_toolkit = ">= 0.3.1 and < 1.0.0"
```

- [ ] **Step 2: Run gleam deps download**

Run: `gleam deps download`
Expected: Success, mcp_toolkit no longer fetched.

Note: `gleam build` will FAIL at this point because `server.gleam` and `http_server.gleam` still import mcp_toolkit. That's expected — we'll fix those files in subsequent tasks.

- [ ] **Step 3: Commit**

```bash
git add gleam.toml manifest.toml
git commit -m "chore: remove mcp_toolkit dependency"
```

---

## Chunk 2: TOON Formatter

### Task 3: TOON formatting helpers

**Files:**
- Create: `src/alex_memory/toon.gleam`
- Create: `test/alex_memory/toon_test.gleam`

- [ ] **Step 1: Write failing tests for `quote` function**

Create `test/alex_memory/toon_test.gleam`:

```gleam
import alex_memory/toon
import gleeunit/should

// -- quote tests --

pub fn quote_plain_string_test() {
  toon.quote("hello")
  |> should.equal("hello")
}

pub fn quote_empty_string_test() {
  toon.quote("")
  |> should.equal("\"\"")
}

pub fn quote_string_with_comma_test() {
  toon.quote("hello, world")
  |> should.equal("\"hello, world\"")
}

pub fn quote_string_that_looks_like_number_test() {
  toon.quote("42")
  |> should.equal("\"42\"")
}

pub fn quote_string_that_looks_like_float_test() {
  toon.quote("3.14")
  |> should.equal("\"3.14\"")
}

pub fn quote_true_test() {
  toon.quote("true")
  |> should.equal("\"true\"")
}

pub fn quote_false_test() {
  toon.quote("false")
  |> should.equal("\"false\"")
}

pub fn quote_null_test() {
  toon.quote("null")
  |> should.equal("\"null\"")
}

pub fn quote_string_with_colon_test() {
  toon.quote("key: value")
  |> should.equal("\"key: value\"")
}

pub fn quote_string_with_quotes_test() {
  toon.quote("he said \"hi\"")
  |> should.equal("\"he said \\\"hi\\\"\"")
}

pub fn quote_string_with_leading_whitespace_test() {
  toon.quote(" hello")
  |> should.equal("\" hello\"")
}

pub fn quote_string_with_brackets_test() {
  toon.quote("[test]")
  |> should.equal("\"[test]\"")
}

pub fn quote_string_with_braces_test() {
  toon.quote("{test}")
  |> should.equal("\"{test}\"")
}

pub fn quote_string_with_backslash_test() {
  toon.quote("path\\to")
  |> should.equal("\"path\\\\to\"")
}

pub fn quote_string_with_newline_test() {
  toon.quote("line1\nline2")
  |> should.equal("\"line1\\nline2\"")
}

pub fn quote_dash_test() {
  toon.quote("-")
  |> should.equal("\"-\"")
}

pub fn quote_dash_prefix_test() {
  toon.quote("-x")
  |> should.equal("\"-x\"")
}

pub fn quote_unicode_passthrough_test() {
  toon.quote("hello 世界 👋")
  |> should.equal("hello 世界 👋")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `gleam test -- --module alex_memory/toon_test`
Expected: Compilation error — module `alex_memory/toon` doesn't exist.

- [ ] **Step 3: Implement toon.gleam**

Create `src/alex_memory/toon.gleam`:

```gleam
import gleam/int
import gleam/float
import gleam/list
import gleam/string

/// Quote a TOON value if it needs quoting per TOON spec.
/// Strings must be quoted if they: are empty, have leading/trailing whitespace,
/// equal true/false/null, look like numbers, contain special chars, or start with "-".
pub fn quote(value: String) -> String {
  case needs_quoting(value) {
    True -> "\"" <> escape(value) <> "\""
    False -> value
  }
}

fn needs_quoting(value: String) -> Bool {
  case value {
    "" -> True
    "true" | "false" | "null" -> True
    "-" -> True
    _ -> {
      looks_like_number(value)
      || starts_with_dash(value)
      || has_leading_or_trailing_whitespace(value)
      || contains_special_chars(value)
    }
  }
}

fn looks_like_number(value: String) -> Bool {
  case int.parse(value) {
    Ok(_) -> True
    Error(_) ->
      case float.parse(value) {
        Ok(_) -> True
        Error(_) -> False
      }
  }
}

fn starts_with_dash(value: String) -> Bool {
  string.starts_with(value, "-")
}

fn has_leading_or_trailing_whitespace(value: String) -> Bool {
  let trimmed = string.trim(value)
  trimmed != value
}

fn contains_special_chars(value: String) -> Bool {
  string.to_graphemes(value)
  |> list.any(fn(c) {
    case c {
      "," | ":" | "\"" | "\\" | "[" | "]" | "{" | "}" | "\n" | "\t" | "\r" ->
        True
      _ -> False
    }
  })
}

fn escape(value: String) -> String {
  string.to_graphemes(value)
  |> list.map(fn(c) {
    case c {
      "\\" -> "\\\\"
      "\"" -> "\\\""
      "\n" -> "\\n"
      "\r" -> "\\r"
      "\t" -> "\\t"
      _ -> c
    }
  })
  |> string.join("")
}

/// Format a tabular TOON response.
/// name: the array name (e.g. "results" or "memories")
/// fields: column names
/// rows: list of rows, each row is a list of string values (same length as fields)
/// Returns the TOON string.
pub fn table(
  name: String,
  fields: List(String),
  rows: List(List(String)),
) -> String {
  let count = list.length(rows)
  let field_header = string.join(fields, ",")
  let header =
    name
    <> "["
    <> int.to_string(count)
    <> "]{"
    <> field_header
    <> "}:"

  case rows {
    [] -> header <> "\n"
    _ -> {
      let row_strings =
        list.map(rows, fn(row) {
          "  "
          <> list.map(row, quote)
          |> string.join(",")
        })
      header <> "\n" <> string.join(row_strings, "\n") <> "\n"
    }
  }
}
```

- [ ] **Step 4: Write failing tests for `table` function**

Add to `test/alex_memory/toon_test.gleam`:

```gleam
// -- table tests --

pub fn table_empty_test() {
  toon.table("results", ["title", "score"], [])
  |> should.equal("results[0]{title,score}:\n")
}

pub fn table_single_row_test() {
  toon.table("results", ["title", "score"], [["Bug fix", "0.78"]])
  |> should.equal("results[1]{title,score}:\n  Bug fix,\"0.78\"\n")
}

pub fn table_multiple_rows_test() {
  toon.table(
    "memories",
    ["title", "type"],
    [["Auth bug", "bug"], ["HTTP design", "brainstorm"]],
  )
  |> should.equal(
    "memories[2]{title,type}:\n  Auth bug,bug\n  HTTP design,brainstorm\n",
  )
}

pub fn table_with_special_values_test() {
  toon.table(
    "results",
    ["title", "preview"],
    [["Hello", "has, comma"]],
  )
  |> should.equal("results[1]{title,preview}:\n  Hello,\"has, comma\"\n")
}
```

- [ ] **Step 5: Run all toon tests**

Run: `gleam test -- --module alex_memory/toon_test`
Expected: All PASS.

- [ ] **Step 6: Commit**

```bash
git add src/alex_memory/toon.gleam test/alex_memory/toon_test.gleam
git commit -m "feat: add TOON formatting helpers for REST API responses"
```

---

## Chunk 3: Handler Rewrite

### Task 4: Rewrite server.gleam — strip MCP, add read handler

**Files:**
- Modify: `src/alex_memory/mcp/server.gleam`

This is the largest change. The handlers keep their arg types and decoders but shed all MCP wrappers. Each handler becomes a plain function returning `Result(String, String)` where Ok is the response body and Error is the error message.

- [ ] **Step 1: Replace the entire server.gleam file**

The new `src/alex_memory/mcp/server.gleam`:

```gleam
import alex_memory/config.{type Config}
import alex_memory/indexer/embedder
import alex_memory/infra/ollama_client
import alex_memory/infra/qdrant_client
import alex_memory/mcp/author
import alex_memory/mcp/dashboard_writer
import alex_memory/mcp/vault_writer
import alex_memory/toon
import alex_memory/types
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

// ---------- Argument types ----------

pub type StoreArgs {
  StoreArgs(
    title: String,
    content: String,
    memory_type: String,
    status: Option(String),
    severity: Option(String),
    tags: Option(List(String)),
  )
}

pub type FindArgs {
  FindArgs(
    query: String,
    type_: Option(String),
    status: Option(String),
    tags: Option(List(String)),
    author: Option(String),
    limit: Int,
  )
}

pub type ListArgs {
  ListArgs(
    type_: Option(String),
    status: Option(String),
    tags: Option(List(String)),
    author: Option(String),
    sort_by: Option(String),
  )
}

pub type UpdateArgs {
  UpdateArgs(
    vault_path: String,
    status: Option(String),
    tags: Option(List(String)),
    content: Option(String),
  )
}

// ---------- Decoders (reused from JSON request bodies) ----------

pub fn decode_store_args() -> decode.Decoder(StoreArgs) {
  use title <- decode.field("title", decode.string)
  use content <- decode.field("content", decode.string)
  use memory_type <- decode.field("memory_type", decode.string)
  use status <- decode.optional_field(
    "status",
    None,
    decode.optional(decode.string),
  )
  use severity <- decode.optional_field(
    "severity",
    None,
    decode.optional(decode.string),
  )
  use tags <- decode.optional_field(
    "tags",
    None,
    decode.optional(decode.list(decode.string)),
  )
  decode.success(StoreArgs(
    title: title,
    content: content,
    memory_type: memory_type,
    status: status,
    severity: severity,
    tags: tags,
  ))
}

pub fn decode_find_args() -> decode.Decoder(FindArgs) {
  use query <- decode.field("query", decode.string)
  use type_ <- decode.optional_field(
    "type",
    None,
    decode.optional(decode.string),
  )
  use status <- decode.optional_field(
    "status",
    None,
    decode.optional(decode.string),
  )
  use tags <- decode.optional_field(
    "tags",
    None,
    decode.optional(decode.list(decode.string)),
  )
  use author <- decode.optional_field(
    "author",
    None,
    decode.optional(decode.string),
  )
  use limit <- decode.optional_field("limit", 10, decode.int)
  decode.success(FindArgs(
    query: query,
    type_: type_,
    status: status,
    tags: tags,
    author: author,
    limit: limit,
  ))
}

pub fn decode_update_args() -> decode.Decoder(UpdateArgs) {
  use vault_path <- decode.field("vault_path", decode.string)
  use status <- decode.optional_field(
    "status",
    None,
    decode.optional(decode.string),
  )
  use tags <- decode.optional_field(
    "tags",
    None,
    decode.optional(decode.list(decode.string)),
  )
  use content <- decode.optional_field(
    "content",
    None,
    decode.optional(decode.string),
  )
  decode.success(UpdateArgs(
    vault_path: vault_path,
    status: status,
    tags: tags,
    content: content,
  ))
}

// ---------- Filter builder (unchanged) ----------

fn build_filter(
  type_filter: Option(String),
  status_filter: Option(String),
  tags_filter: Option(List(String)),
  author_filter: Option(String),
) -> Option(json.Json) {
  let conditions = []
  let conditions = case type_filter {
    Some(t) -> [
      json.object([
        #("key", json.string("type")),
        #("match", json.object([#("value", json.string(t))])),
      ]),
      ..conditions
    ]
    None -> conditions
  }
  let conditions = case status_filter {
    Some(s) -> [
      json.object([
        #("key", json.string("status")),
        #("match", json.object([#("value", json.string(s))])),
      ]),
      ..conditions
    ]
    None -> conditions
  }
  let conditions = case tags_filter {
    Some(tag_list) ->
      list.fold(tag_list, conditions, fn(acc, tag) {
        [
          json.object([
            #("key", json.string("tags")),
            #("match", json.object([#("value", json.string(tag))])),
          ]),
          ..acc
        ]
      })
    None -> conditions
  }
  let conditions = case author_filter {
    Some(a) -> [
      json.object([
        #("key", json.string("author")),
        #("match", json.object([#("value", json.string(a))])),
      ]),
      ..conditions
    ]
    None -> conditions
  }
  case conditions {
    [] -> None
    _ -> Some(json.object([#("must", json.array(conditions, fn(x) { x }))]))
  }
}

// ---------- Payload extraction (unchanged) ----------

fn get_payload_string(payload: decode.Dynamic, field: String) -> String {
  case decode.run(payload, decode.at([field], decode.string)) {
    Ok(value) -> value
    Error(_) -> ""
  }
}

// ---------- Handlers ----------

/// Store a new memory. Returns Ok("stored: <vault_path>") or Error(message).
pub fn handle_store(
  config: Config,
  embedder_subject: Subject(embedder.Message),
  args: StoreArgs,
) -> Result(String, String) {
  case types.memory_type_from_string(args.memory_type) {
    Error(e) -> Error(e)
    Ok(memory_type) -> {
      let status = case args.status {
        Some(s) ->
          case types.status_from_string(s) {
            Ok(st) -> Some(st)
            Error(_) -> None
          }
        None -> None
      }

      let severity = case args.severity {
        Some("p0") -> Some(types.P0)
        Some("p1") -> Some(types.P1)
        Some("p2") -> Some(types.P2)
        Some("p3") -> Some(types.P3)
        _ -> None
      }

      let tags = case args.tags {
        Some(t) -> t
        None -> []
      }

      let request_author =
        author.get()
        |> result.unwrap(config.http.default_author)

      case
        vault_writer.write_memory(
          config.vault.path,
          config.vault.claude_dir,
          memory_type,
          args.title,
          args.content,
          status,
          severity,
          tags,
          request_author,
        )
      {
        Ok(vault_path) -> {
          let full_path = config.vault.path <> "/" <> vault_path
          process.send(
            embedder_subject,
            embedder.IndexFile(path: full_path, vault_relative: vault_path),
          )
          let _ =
            process.spawn_unlinked(fn() {
              let _ =
                dashboard_writer.regenerate(
                  config.vault.path,
                  config.vault.claude_dir,
                )
              Nil
            })
          Ok("stored: " <> vault_path)
        }
        Error(e) -> Error("Failed to write memory: " <> e)
      }
    }
  }
}

/// Semantic search. Returns Ok(toon_string) or Error(message).
pub fn handle_find(config: Config, args: FindArgs) -> Result(String, String) {
  case ollama_client.embed(config.ollama.url, config.ollama.model, args.query) {
    Error(_) -> Error("Failed to generate query embedding")
    Ok(vector) -> {
      let filter =
        build_filter(args.type_, args.status, args.tags, args.author)

      case
        qdrant_client.search(
          config.qdrant.url,
          config.qdrant.collection,
          vector,
          args.limit,
          filter,
        )
      {
        Error(_) -> Error("Search failed")
        Ok(hits) -> {
          let rows =
            list.map(hits, fn(hit) {
              let title = get_payload_string(hit.payload, "title")
              let score = float.to_string(hit.score)
              let type_str = get_payload_string(hit.payload, "type")
              let vault_path = get_payload_string(hit.payload, "vault_path")
              let status_str = get_payload_string(hit.payload, "status")
              let author_str = get_payload_string(hit.payload, "author")
              let content = get_payload_string(hit.payload, "content")
              let preview = case string.length(content) > 200 {
                True -> string.slice(content, 0, 200) <> "..."
                False -> content
              }
              [title, score, type_str, vault_path, status_str, author_str, preview]
            })

          case rows {
            [] -> Ok("No memories found matching your query.")
            _ ->
              Ok(
                toon.table(
                  "results",
                  ["title", "score", "type", "path", "status", "author", "preview"],
                  rows,
                ),
              )
          }
        }
      }
    }
  }
}

/// List memories with filters. Returns Ok(toon_string) or Error(message).
pub fn handle_list(config: Config, args: ListArgs) -> Result(String, String) {
  let filter = build_filter(args.type_, args.status, args.tags, args.author)

  case
    qdrant_client.scroll(
      config.qdrant.url,
      config.qdrant.collection,
      filter,
      100,
    )
  {
    Error(_) -> Error("Failed to list memories")
    Ok(points) -> {
      let unique_points = deduplicate_by_vault_path(points)

      let rows =
        list.map(unique_points, fn(point) {
          let title = get_payload_string(point.payload, "title")
          let type_str = get_payload_string(point.payload, "type")
          let status_str = get_payload_string(point.payload, "status")
          let author_str = get_payload_string(point.payload, "author")
          let vault_path = get_payload_string(point.payload, "vault_path")
          let updated = get_payload_string(point.payload, "updated")
          [title, type_str, status_str, author_str, vault_path, updated]
        })

      case rows {
        [] -> Ok("No memories found matching the filters.")
        _ ->
          Ok(
            toon.table(
              "memories",
              ["title", "type", "status", "author", "path", "updated"],
              rows,
            ),
          )
      }
    }
  }
}

/// Read a memory file by vault-relative path.
/// Returns Ok(raw_markdown) or Error(message).
pub fn handle_read(config: Config, vault_path: String) -> Result(String, String) {
  let abs_path = config.vault.path <> "/" <> vault_path
  case simplifile.read(abs_path) {
    Ok(content) -> Ok(content)
    Error(_) -> Error("not found: " <> vault_path)
  }
}

/// Update an existing memory. Returns Ok(confirmation) or Error(message).
pub fn handle_update(config: Config, args: UpdateArgs) -> Result(String, String) {
  let status = case args.status {
    Some(s) ->
      case types.status_from_string(s) {
        Ok(st) -> Some(st)
        Error(_) -> None
      }
    None -> None
  }

  case
    vault_writer.update_memory(
      config.vault.path,
      args.vault_path,
      status,
      args.tags,
      args.content,
    )
  {
    Ok(Nil) -> {
      let _ =
        process.spawn_unlinked(fn() {
          let _ =
            dashboard_writer.regenerate(
              config.vault.path,
              config.vault.claude_dir,
            )
          Nil
        })
      Ok("updated: " <> args.vault_path)
    }
    Error(e) -> Error("Failed to update memory: " <> e)
  }
}

/// Trigger reindex. Returns Ok(confirmation).
pub fn handle_reindex(
  embedder_subject: Subject(embedder.Message),
) -> Result(String, String) {
  process.send(embedder_subject, embedder.ReindexAll)
  Ok("Reindex triggered. All vault markdown files will be re-embedded and indexed.")
}

// ---------- Deduplication (unchanged) ----------

fn deduplicate_by_vault_path(
  points: List(qdrant_client.ScrollPoint),
) -> List(qdrant_client.ScrollPoint) {
  do_dedup_by_path(points, [], [])
}

fn do_dedup_by_path(
  points: List(qdrant_client.ScrollPoint),
  seen_paths: List(String),
  acc: List(qdrant_client.ScrollPoint),
) -> List(qdrant_client.ScrollPoint) {
  case points {
    [] -> list.reverse(acc)
    [point, ..rest] -> {
      let path = get_payload_string(point.payload, "vault_path")
      case list.contains(seen_paths, path) {
        True -> do_dedup_by_path(rest, seen_paths, acc)
        False -> do_dedup_by_path(rest, [path, ..seen_paths], [point, ..acc])
      }
    }
  }
}
```

Key changes from the old file:
- Removed all `mcp_toolkit` and `mcp_toolkit/core/protocol` imports
- Removed `ReindexArgs` type (no args needed)
- Removed `decode_list_args` and `decode_reindex_args` (list uses query params, reindex has no body)
- Made decoders `pub` (http_server needs them for JSON body parsing)
- Removed `text_result`, `error_result`, `build` function, all `*_schema` functions
- Handlers are now plain `pub fn` taking typed args, returning `Result(String, String)`
- Added `handle_read` for the new read endpoint
- TOON formatting via `toon.table` for find/list results
- Config references changed from `config.mcp.*` to `config.http.*`

- [ ] **Step 2: Verify the file compiles in isolation**

Run: `gleam build 2>&1 | head -20`
Expected: Errors only from `http_server.gleam` and `alex_memory.gleam` (which still reference old MCP types). `server.gleam` itself should compile.

- [ ] **Step 3: Commit**

```bash
git add src/alex_memory/mcp/server.gleam
git commit -m "refactor: strip MCP wrappers from handlers, add TOON responses and read endpoint"
```

---

## Chunk 4: HTTP Server and Main Entry Point

### Task 5: Rewrite http_server.gleam as REST router

**Files:**
- Modify: `src/alex_memory/mcp/http_server.gleam`

- [ ] **Step 1: Replace the entire http_server.gleam file**

The new `src/alex_memory/mcp/http_server.gleam`:

```gleam
import alex_memory/config.{type Config}
import alex_memory/indexer/embedder
import alex_memory/mcp/author
import alex_memory/mcp/server
import gleam/bit_array
import gleam/bytes_tree
import gleam/erlang/process.{type Subject}
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import mist

/// Start the REST API server on the configured port.
pub fn start(
  config: Config,
  embedder_subject: Subject(embedder.Message),
) -> Result(Nil, String) {
  let handler = fn(req: request.Request(mist.Connection)) {
    // Extract author from X-Author header, fall back to config default
    let req_author =
      request.get_header(req, "x-author")
      |> result.unwrap(config.http.default_author)
    author.set(req_author)

    route(req, config, embedder_subject)
  }

  let port = config.http.port
  io.println_error(
    "REST API server starting on port " <> string.inspect(port) <> "...",
  )

  case
    mist.new(handler)
    |> mist.bind("0.0.0.0")
    |> mist.port(port)
    |> mist.start
  {
    Ok(_) -> {
      io.println_error(
        "REST API server listening on port " <> string.inspect(port),
      )
      Ok(Nil)
    }
    Error(e) -> {
      io.println_error("Failed to start HTTP server: " <> string.inspect(e))
      Error("Failed to start HTTP server")
    }
  }
}

// ---------- Router ----------

fn route(
  req: request.Request(mist.Connection),
  config: Config,
  embedder_subject: Subject(embedder.Message),
) -> response.Response(mist.ResponseData) {
  case request.path_segments(req), req.method {
    // GET /health
    ["health"], http.Get -> json_response(200, "{\"status\":\"ok\"}")

    // POST /memories — store
    ["memories"], http.Post -> handle_store(req, config, embedder_subject)

    // POST /memories/search — semantic search
    ["memories", "search"], http.Post -> handle_find(req, config)

    // GET /memories — list with filters
    ["memories"], http.Get -> handle_list(req, config)

    // PATCH /memories — update
    ["memories"], http.Patch -> handle_update(req, config)

    // POST /memories/reindex — trigger reindex
    ["memories", "reindex"], http.Post -> handle_reindex(embedder_subject)

    // GET /memories/* — read raw file (wildcard path)
    ["memories", ..path_rest], http.Get ->
      handle_read(config, string.join(path_rest, "/"))

    // 404
    _, _ -> text_response(404, "not found")
  }
}

// ---------- Route handlers ----------

fn handle_store(
  req: request.Request(mist.Connection),
  config: Config,
  embedder_subject: Subject(embedder.Message),
) -> response.Response(mist.ResponseData) {
  case read_json_body(req, server.decode_store_args()) {
    Error(e) -> text_response(400, e)
    Ok(args) ->
      case server.handle_store(config, embedder_subject, args) {
        Ok(msg) -> text_response(200, msg)
        Error(e) -> text_response(400, e)
      }
  }
}

fn handle_find(
  req: request.Request(mist.Connection),
  config: Config,
) -> response.Response(mist.ResponseData) {
  case read_json_body(req, server.decode_find_args()) {
    Error(e) -> text_response(400, e)
    Ok(args) ->
      case server.handle_find(config, args) {
        Ok(body) -> toon_response(200, body)
        Error(e) -> text_response(500, e)
      }
  }
}

fn handle_list(
  req: request.Request(mist.Connection),
  config: Config,
) -> response.Response(mist.ResponseData) {
  // Parse query params into ListArgs
  let params =
    request.get_query(req)
    |> result.unwrap([])

  let get_param = fn(key: String) -> option.Option(String) {
    list.find(params, fn(pair) { pair.0 == key })
    |> result.map(fn(pair) { pair.1 })
    |> option.from_result
  }

  let tags = case get_param("tags") {
    Some(t) -> Some(string.split(t, ","))
    None -> None
  }

  let args =
    server.ListArgs(
      type_: get_param("type"),
      status: get_param("status"),
      tags: tags,
      author: get_param("author"),
      sort_by: get_param("sort_by"),
    )

  case server.handle_list(config, args) {
    Ok(body) -> toon_response(200, body)
    Error(e) -> text_response(500, e)
  }
}

fn handle_read(
  config: Config,
  vault_path: String,
) -> response.Response(mist.ResponseData) {
  case server.handle_read(config, vault_path) {
    Ok(content) -> markdown_response(200, content)
    Error(_) -> text_response(404, "not found: " <> vault_path)
  }
}

fn handle_update(
  req: request.Request(mist.Connection),
  config: Config,
) -> response.Response(mist.ResponseData) {
  case read_json_body(req, server.decode_update_args()) {
    Error(e) -> text_response(400, e)
    Ok(args) ->
      case server.handle_update(config, args) {
        Ok(msg) -> text_response(200, msg)
        Error(e) -> text_response(400, e)
      }
  }
}

fn handle_reindex(
  embedder_subject: Subject(embedder.Message),
) -> response.Response(mist.ResponseData) {
  case server.handle_reindex(embedder_subject) {
    Ok(msg) -> text_response(200, msg)
    Error(e) -> text_response(500, e)
  }
}

// ---------- Body parsing ----------

fn read_json_body(
  req: request.Request(mist.Connection),
  decoder: decode.Decoder(a),
) -> Result(a, String) {
  case mist.read_body(req, 1_000_000) {
    Error(_) -> Error("Failed to read request body")
    Ok(req_with_body) ->
      case bit_array.to_string(req_with_body.body) {
        Error(_) -> Error("Invalid UTF-8 body")
        Ok(body_string) ->
          json.parse(body_string, decoder)
          |> result.map_error(fn(_) { "Invalid JSON body" })
      }
  }
}

// ---------- Response helpers ----------

fn text_response(
  status: Int,
  body: String,
) -> response.Response(mist.ResponseData) {
  response.new(status)
  |> response.set_header("content-type", "text/plain; charset=utf-8")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

fn json_response(
  status: Int,
  body: String,
) -> response.Response(mist.ResponseData) {
  response.new(status)
  |> response.set_header("content-type", "application/json")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

fn toon_response(
  status: Int,
  body: String,
) -> response.Response(mist.ResponseData) {
  response.new(status)
  |> response.set_header("content-type", "text/toon; charset=utf-8")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

fn markdown_response(
  status: Int,
  body: String,
) -> response.Response(mist.ResponseData) {
  response.new(status)
  |> response.set_header("content-type", "text/markdown; charset=utf-8")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}
```

Key changes:
- No `mcp_toolkit`, `sse`, or `rpc` imports
- `start()` takes `Config` + `Subject(embedder.Message)` instead of `Config` + `mcp_toolkit.Server`
- Author extracted from `X-Author` header via `request.get_header`
- Routes pattern-match on `(path_segments, method)` tuples
- JSON body parsing via `mist.read_body` + `json.parse` + existing decoders
- Wildcard path for `GET /memories/*` via `["memories", ..path_rest]`
- Response helpers for text, json, toon, and markdown content types

**Important:** The `read_json_body` function needs the `decode` import. Add to imports:
```gleam
import gleam/dynamic/decode
```

- [ ] **Step 2: Commit**

```bash
git add src/alex_memory/mcp/http_server.gleam
git commit -m "refactor: rewrite http_server as REST router"
```

### Task 6: Update main entry point

**Files:**
- Modify: `src/alex_memory.gleam`

- [ ] **Step 1: Update alex_memory.gleam**

```gleam
import alex_memory/config
import alex_memory/indexer/embedder
import alex_memory/indexer/vault_watcher
import alex_memory/infra/ollama_client
import alex_memory/infra/qdrant_client
import alex_memory/mcp/dashboard_writer
import alex_memory/mcp/http_server
import gleam/erlang/process
import gleam/io

pub fn main() {
  io.println_error("Starting alex_memory...")

  // Load config (fast, local file read)
  let assert Ok(cfg) = config.load("config/config.toml")
  io.println_error("Config loaded")

  // Start embedder immediately (it can queue messages before infra is ready)
  let assert Ok(embedder_subject) = embedder.start(cfg)

  // Start infrastructure setup in a background process
  let _ = process.spawn(fn() { setup_infrastructure(cfg, embedder_subject) })

  // Start REST API server (fatal on failure — e.g. port conflict)
  let assert Ok(_) = http_server.start(cfg, embedder_subject)
  io.println_error("REST API server ready")

  // Keep BEAM alive for HTTP clients
  process.sleep_forever()
}

fn setup_infrastructure(
  cfg: config.Config,
  embedder_subject: process.Subject(embedder.Message),
) -> Nil {
  // Ensure Qdrant collection exists
  case
    qdrant_client.ensure_collection(
      cfg.qdrant.url,
      cfg.qdrant.collection,
      cfg.qdrant.vector_dimension,
    )
  {
    Ok(_) ->
      io.println_error("Qdrant collection ready: " <> cfg.qdrant.collection)
    Error(_) -> io.println_error("WARNING: Qdrant not available")
  }

  // Ensure Ollama model is available
  case ollama_client.model_exists(cfg.ollama.url, cfg.ollama.model) {
    Ok(True) ->
      io.println_error("Ollama model ready: " <> cfg.ollama.model)
    Ok(False) -> {
      io.println_error("Pulling Ollama model: " <> cfg.ollama.model)
      case ollama_client.pull_model(cfg.ollama.url, cfg.ollama.model) {
        Ok(_) -> io.println_error("Model pulled successfully")
        Error(_) -> io.println_error("WARNING: Failed to pull model")
      }
    }
    Error(_) -> io.println_error("WARNING: Ollama not available")
  }

  // Start vault watcher
  case vault_watcher.start(cfg, embedder_subject) {
    Ok(_) ->
      io.println_error("Vault watcher started for: " <> cfg.vault.path)
    Error(_) -> io.println_error("WARNING: Vault watcher failed to start")
  }

  // Initial index
  io.println_error("Starting initial vault index...")
  process.send(embedder_subject, embedder.ReindexAll)

  // Generate Obsidian Bases dashboards
  case dashboard_writer.regenerate(cfg.vault.path, cfg.vault.claude_dir) {
    Ok(_) -> io.println_error("Dashboards generated")
    Error(e) -> io.println_error("WARNING: Dashboard generation failed: " <> e)
  }

  io.println_error("Infrastructure setup complete")
  Nil
}
```

Changes:
- Removed `import alex_memory/mcp/server as mcp_server`
- Removed `let server = mcp_server.build(cfg, embedder_subject)`
- `http_server.start(cfg, embedder_subject)` instead of `http_server.start(cfg, server)`
- Changed log message to "REST API server ready"

- [ ] **Step 2: Build the project**

Run: `gleam build`
Expected: Success — no compilation errors.

- [ ] **Step 3: Run existing tests**

Run: `gleam test`
Expected: All existing tests pass. The config test passes with the [http] rename. The vault_writer, dashboard_writer, frontmatter, chunker, point_id, and types tests are untouched.

- [ ] **Step 4: Commit**

```bash
git add src/alex_memory.gleam
git commit -m "refactor: update main entry point, remove MCP server build"
```

---

## Chunk 5: Smoke Test and Verification

### Task 7: Verify the REST API works

- [ ] **Step 1: Start the server**

Run: `gleam run &`
Expected: Logs show "REST API server listening on port 7890" and "REST API server ready".

- [ ] **Step 2: Test health endpoint**

Run: `curl -s http://localhost:7890/health`
Expected: `{"status":"ok"}`

- [ ] **Step 3: Test store endpoint**

Run:
```bash
curl -s -X POST \
  -H "X-Author: test-agent" \
  -d '{"title":"REST API smoke test","content":"Testing the new REST API.","memory_type":"memory"}' \
  http://localhost:7890/memories
```
Expected: `stored: Claude/memory/rest-api-smoke-test.md`

- [ ] **Step 4: Test search endpoint**

Run:
```bash
curl -s -X POST \
  -d '{"query":"REST API smoke test","limit":3}' \
  http://localhost:7890/memories/search
```
Expected: TOON-formatted results containing the memory just stored. Format starts with `results[N]{title,score,type,path,status,author,preview}:`

- [ ] **Step 5: Test list endpoint**

Run: `curl -s 'http://localhost:7890/memories?type=memory'`
Expected: TOON-formatted list starting with `memories[N]{title,type,status,author,path,updated}:`

- [ ] **Step 6: Test read endpoint**

Run: `curl -s http://localhost:7890/memories/Claude/memory/rest-api-smoke-test.md`
Expected: Raw markdown file content with YAML frontmatter.

- [ ] **Step 7: Test update endpoint**

Run:
```bash
curl -s -X PATCH \
  -d '{"vault_path":"Claude/memory/rest-api-smoke-test.md","status":"archived"}' \
  http://localhost:7890/memories
```
Expected: `updated: Claude/memory/rest-api-smoke-test.md`

- [ ] **Step 8: Test reindex endpoint**

Run: `curl -s -X POST http://localhost:7890/memories/reindex`
Expected: `Reindex triggered. All vault markdown files will be re-embedded and indexed.`

- [ ] **Step 9: Test 404**

Run: `curl -s -w '\n%{http_code}' http://localhost:7890/nonexistent`
Expected: Body is `not found`, status code is `404`.

- [ ] **Step 10: Stop the server and clean up test file**

Stop the server. Delete the smoke test file from the vault if desired.

---

## Chunk 6: Skills and Settings

### Task 8: Update Claude Code settings

**Files:**
- Create: `.claude/settings.json`
- Modify: `.claude/settings.local.json`

- [ ] **Step 1: Create .claude/settings.json with env var defaults**

```json
{
  "env": {
    "MEMORY_API_URL": "http://localhost:7890",
    "MEMORY_API_AUTHOR": "alex"
  }
}
```

- [ ] **Step 2: Remove MCP server config from settings.local.json if present**

Check `.claude/settings.local.json` for any `mcpServers` block referencing alex-memory and remove it. Keep other settings (like permissions) intact.

- [ ] **Step 3: Commit**

```bash
git add .claude/settings.json .claude/settings.local.json
git commit -m "chore: add MEMORY_API_URL and MEMORY_API_AUTHOR env vars to settings"
```

### Task 9: Update skills to use curl contract

**Files to modify** (every skill that references `memory_store`, `memory_find`, `memory_list`, `memory_update`, or `memory_reindex`):

- `skills/remember/SKILL.md`
- `skills/recall/SKILL.md`
- `skills/bugs/SKILL.md`
- `skills/status/SKILL.md`
- `skills/session-end/SKILL.md`
- `skills/idea/SKILL.md`
- `skills/shape/SKILL.md`
- `skills/brainstorming/SKILL.md`
- `skills/brainstorming/visual-companion.md`
- `skills/writing-plans/SKILL.md`
- `skills/executing-plans/SKILL.md`
- `skills/systematic-debugging/SKILL.md`

For each skill, replace MCP tool calls with curl commands. The pattern:

**memory_find → curl POST /memories/search:**
```
curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
  -d '{"query": "SEARCH_TERMS", "type": "TYPE", "limit": 10}' \
  $MEMORY_API_URL/memories/search
```

**memory_store → curl POST /memories:**
```
curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
  -d '{"title": "TITLE", "content": "CONTENT", "memory_type": "TYPE", "status": "STATUS", "tags": ["TAG"]}' \
  $MEMORY_API_URL/memories
```

**memory_list → curl GET /memories:**
```
curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
  "$MEMORY_API_URL/memories?type=TYPE&status=STATUS"
```

**memory_update → curl PATCH /memories:**
```
curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
  -X PATCH \
  -d '{"vault_path": "PATH", "status": "STATUS"}' \
  $MEMORY_API_URL/memories
```

**memory_reindex → curl POST /memories/reindex:**
```
curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
  -X POST $MEMORY_API_URL/memories/reindex
```

- [ ] **Step 1: Update each skill file**

Go through each file listed above. For each occurrence of an MCP tool call instruction (e.g., "Call `memory_find` with..."), replace with the equivalent curl command using `$MEMORY_API_URL` and `$MEMORY_API_AUTHOR`.

Read each skill file carefully before editing — the context around each tool call matters for how the curl replacement should be phrased.

- [ ] **Step 2: Verify no MCP tool references remain**

Run: `grep -r "memory_find\|memory_store\|memory_list\|memory_update\|memory_reindex\|mcp__alex-memory" skills/`
Expected: No matches (or only references in documentation/changelogs, not instructions).

- [ ] **Step 3: Commit**

```bash
git add skills/
git commit -m "refactor: update all skills from MCP tool calls to REST curl commands"
```

---

## Summary

| Task | Description | Key Files |
|------|-------------|-----------|
| 1 | Config rename [mcp]→[http] | config.toml, config.gleam, config_test.gleam |
| 2 | Remove mcp_toolkit dep | gleam.toml |
| 3 | TOON formatter (TDD) | toon.gleam, toon_test.gleam |
| 4 | Rewrite handlers | server.gleam |
| 5 | Rewrite HTTP server | http_server.gleam |
| 6 | Update main entry | alex_memory.gleam |
| 7 | Smoke test all endpoints | curl commands |
| 8 | Claude Code settings | .claude/settings.json |
| 9 | Update skills | 12 skill files |
