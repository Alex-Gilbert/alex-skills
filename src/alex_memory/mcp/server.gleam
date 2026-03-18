import alex_memory/config.{type Config}
import alex_memory/indexer/embedder
import alex_memory/infra/ollama_client
import alex_memory/infra/qdrant_client
import alex_memory/mcp/author
import alex_memory/mcp/dashboard_writer
import alex_memory/mcp/vault_writer
import alex_memory/types
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/json
import gleam/list
import gleam/result
import gleam/option.{type Option, None, Some}
import gleam/string
import mcp_toolkit
import mcp_toolkit/core/protocol as mcp

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

pub type ReindexArgs {
  ReindexArgs(full: Bool)
}

// ---------- Decoders ----------

fn decode_store_args() -> decode.Decoder(StoreArgs) {
  use title <- decode.field("title", decode.string)
  use content <- decode.field("content", decode.string)
  use memory_type <- decode.field("memory_type", decode.string)
  use status <- decode.optional_field("status", None, decode.optional(decode.string))
  use severity <- decode.optional_field("severity", None, decode.optional(decode.string))
  use tags <- decode.optional_field("tags", None, decode.optional(decode.list(decode.string)))
  decode.success(StoreArgs(
    title: title,
    content: content,
    memory_type: memory_type,
    status: status,
    severity: severity,
    tags: tags,
  ))
}

fn decode_find_args() -> decode.Decoder(FindArgs) {
  use query <- decode.field("query", decode.string)
  use type_ <- decode.optional_field("type", None, decode.optional(decode.string))
  use status <- decode.optional_field("status", None, decode.optional(decode.string))
  use tags <- decode.optional_field("tags", None, decode.optional(decode.list(decode.string)))
  use author <- decode.optional_field("author", None, decode.optional(decode.string))
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

fn decode_list_args() -> decode.Decoder(ListArgs) {
  use type_ <- decode.optional_field("type", None, decode.optional(decode.string))
  use status <- decode.optional_field("status", None, decode.optional(decode.string))
  use tags <- decode.optional_field("tags", None, decode.optional(decode.list(decode.string)))
  use author <- decode.optional_field("author", None, decode.optional(decode.string))
  use sort_by <- decode.optional_field("sort_by", None, decode.optional(decode.string))
  decode.success(ListArgs(
    type_: type_,
    status: status,
    tags: tags,
    author: author,
    sort_by: sort_by,
  ))
}

fn decode_update_args() -> decode.Decoder(UpdateArgs) {
  use vault_path <- decode.field("vault_path", decode.string)
  use status <- decode.optional_field("status", None, decode.optional(decode.string))
  use tags <- decode.optional_field("tags", None, decode.optional(decode.list(decode.string)))
  use content <- decode.optional_field("content", None, decode.optional(decode.string))
  decode.success(UpdateArgs(
    vault_path: vault_path,
    status: status,
    tags: tags,
    content: content,
  ))
}

fn decode_reindex_args() -> decode.Decoder(ReindexArgs) {
  use full <- decode.optional_field("full", False, decode.bool)
  decode.success(ReindexArgs(full: full))
}

// ---------- Tool result helpers ----------

fn text_result(text: String) -> Result(mcp.CallToolResult, String) {
  Ok(mcp.CallToolResult(
    content: [
      mcp.TextToolContent(mcp.TextContent(
        annotations: None,
        text: text,
        type_: "text",
      )),
    ],
    is_error: Some(False),
    meta: None,
  ))
}

fn error_result(message: String) -> Result(mcp.CallToolResult, String) {
  Ok(mcp.CallToolResult(
    content: [
      mcp.TextToolContent(mcp.TextContent(
        annotations: None,
        text: "Error: " <> message,
        type_: "text",
      )),
    ],
    is_error: Some(True),
    meta: None,
  ))
}

// ---------- Filter builder ----------

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

// ---------- Payload extraction helpers ----------

fn get_payload_string(
  payload: decode.Dynamic,
  field: String,
) -> String {
  case decode.run(payload, decode.at([field], decode.string)) {
    Ok(value) -> value
    Error(_) -> ""
  }
}

// ---------- Tool handlers ----------

fn handle_store(
  config: Config,
  embedder_subject: Subject(embedder.Message),
) -> fn(mcp.CallToolRequest(StoreArgs)) -> Result(mcp.CallToolResult, String) {
  fn(request: mcp.CallToolRequest(StoreArgs)) -> Result(
    mcp.CallToolResult,
    String,
  ) {
    case request.arguments {
      None -> error_result("Arguments required")
      Some(args) -> {
        // Parse memory type
        case types.memory_type_from_string(args.memory_type) {
          Error(e) -> error_result(e)
          Ok(memory_type) -> {
            // Parse optional status
            let status = case args.status {
              Some(s) ->
                case types.status_from_string(s) {
                  Ok(st) -> Some(st)
                  Error(_) -> None
                }
              None -> None
            }

            // Parse optional severity
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

            // Get author from request context, fall back to config default
            let request_author =
              author.get()
              |> result.unwrap(config.mcp.default_author)

            // Write to vault
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
                // Send to embedder for indexing
                let full_path = config.vault.path <> "/" <> vault_path
                process.send(
                  embedder_subject,
                  embedder.IndexFile(
                    path: full_path,
                    vault_relative: vault_path,
                  ),
                )
                // Regenerate dashboards in background
                let _ =
                  process.spawn_unlinked(fn() {
                    let _ =
                      dashboard_writer.regenerate(
                        config.vault.path,
                        config.vault.claude_dir,
                      )
                    Nil
                  })
                text_result(
                  "Memory stored at: "
                  <> vault_path,
                )
              }
              Error(e) -> error_result("Failed to write memory: " <> e)
            }
          }
        }
      }
    }
  }
}

fn handle_find(
  config: Config,
) -> fn(mcp.CallToolRequest(FindArgs)) -> Result(mcp.CallToolResult, String) {
  fn(request: mcp.CallToolRequest(FindArgs)) -> Result(
    mcp.CallToolResult,
    String,
  ) {
    case request.arguments {
      None -> error_result("Arguments required")
      Some(args) -> {
        // Embed the query
        case
          ollama_client.embed(config.ollama.url, config.ollama.model, args.query)
        {
          Error(_) -> error_result("Failed to generate query embedding")
          Ok(vector) -> {
            let filter = build_filter(args.type_, args.status, args.tags, args.author)

            // Search Qdrant
            case
              qdrant_client.search(
                config.qdrant.url,
                config.qdrant.collection,
                vector,
                args.limit,
                filter,
              )
            {
              Error(_) -> error_result("Search failed")
              Ok(hits) -> {
                let results =
                  list.map(hits, fn(hit) {
                    let title = get_payload_string(hit.payload, "title")
                    let content = get_payload_string(hit.payload, "content")
                    let vault_path =
                      get_payload_string(hit.payload, "vault_path")
                    let type_str = get_payload_string(hit.payload, "type")
                    let status_str =
                      get_payload_string(hit.payload, "status")
                    let author_str =
                      get_payload_string(hit.payload, "author")
                    let score_str = float.to_string(hit.score)

                    let preview = case string.length(content) > 200 {
                      True -> string.slice(content, 0, 200) <> "..."
                      False -> content
                    }

                    "## "
                    <> title
                    <> " (score: "
                    <> score_str
                    <> ")\n"
                    <> "- **Type:** "
                    <> type_str
                    <> "\n"
                    <> "- **Path:** "
                    <> vault_path
                    <> "\n"
                    <> case status_str {
                      "" -> ""
                      s -> "- **Status:** " <> s <> "\n"
                    }
                    <> case author_str {
                      "" -> ""
                      a -> "- **Author:** " <> a <> "\n"
                    }
                    <> "- **Preview:** "
                    <> preview
                    <> "\n"
                  })

                let result_text = case results {
                  [] -> "No memories found matching your query."
                  _ ->
                    "Found "
                    <> string.inspect(list.length(results))
                    <> " results:\n\n"
                    <> string.join(results, "\n---\n")
                }
                text_result(result_text)
              }
            }
          }
        }
      }
    }
  }
}

fn handle_list(
  config: Config,
) -> fn(mcp.CallToolRequest(ListArgs)) -> Result(mcp.CallToolResult, String) {
  fn(request: mcp.CallToolRequest(ListArgs)) -> Result(
    mcp.CallToolResult,
    String,
  ) {
    let args = case request.arguments {
      None -> ListArgs(type_: None, status: None, tags: None, author: None, sort_by: None)
      Some(a) -> a
    }

    let filter = build_filter(args.type_, args.status, args.tags, args.author)

    case
      qdrant_client.scroll(
        config.qdrant.url,
        config.qdrant.collection,
        filter,
        100,
      )
    {
      Error(_) -> error_result("Failed to list memories")
      Ok(points) -> {
        // Deduplicate by vault_path (chunks produce multiple entries)
        let unique_points = deduplicate_by_vault_path(points)

        let results =
          list.map(unique_points, fn(point) {
            let title = get_payload_string(point.payload, "title")
            let vault_path = get_payload_string(point.payload, "vault_path")
            let type_str = get_payload_string(point.payload, "type")
            let status_str =
              get_payload_string(point.payload, "status")
            let updated = get_payload_string(point.payload, "updated")
            let author_str = get_payload_string(point.payload, "author")

            "- **"
            <> title
            <> "** ["
            <> type_str
            <> "]"
            <> case status_str {
              "" -> ""
              s -> " (" <> s <> ")"
            }
            <> case author_str {
              "" -> ""
              a -> " by " <> a
            }
            <> " — "
            <> vault_path
            <> case updated {
              "" -> ""
              u -> " (updated: " <> u <> ")"
            }
          })

        let result_text = case results {
          [] -> "No memories found matching the filters."
          _ ->
            "Found "
            <> string.inspect(list.length(results))
            <> " memories:\n\n"
            <> string.join(results, "\n")
        }
        text_result(result_text)
      }
    }
  }
}

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

fn handle_update(
  config: Config,
) -> fn(mcp.CallToolRequest(UpdateArgs)) -> Result(mcp.CallToolResult, String) {
  fn(request: mcp.CallToolRequest(UpdateArgs)) -> Result(
    mcp.CallToolResult,
    String,
  ) {
    case request.arguments {
      None -> error_result("Arguments required")
      Some(args) -> {
        // Parse optional status
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
            // Regenerate dashboards in background
            let _ =
              process.spawn_unlinked(fn() {
                let _ =
                  dashboard_writer.regenerate(
                    config.vault.path,
                    config.vault.claude_dir,
                  )
                Nil
              })
            text_result(
              "Memory updated: " <> args.vault_path
              <> "\nThe vault watcher will automatically re-index the updated file.",
            )
          }
          Error(e) -> error_result("Failed to update memory: " <> e)
        }
      }
    }
  }
}

fn handle_reindex(
  embedder_subject: Subject(embedder.Message),
) -> fn(mcp.CallToolRequest(ReindexArgs)) -> Result(mcp.CallToolResult, String) {
  fn(_request: mcp.CallToolRequest(ReindexArgs)) -> Result(
    mcp.CallToolResult,
    String,
  ) {
    process.send(embedder_subject, embedder.ReindexAll)
    text_result(
      "Reindex triggered. All vault markdown files will be re-embedded and indexed.",
    )
  }
}

// ---------- Tool schemas ----------

fn store_schema() -> mcp.ToolInputSchema {
  let assert Ok(schema) =
    mcp.tool_input_schema(
      "{\"type\":\"object\",\"properties\":{\"title\":{\"type\":\"string\",\"description\":\"Title of the memory\"},\"content\":{\"type\":\"string\",\"description\":\"Markdown content of the memory\"},\"memory_type\":{\"type\":\"string\",\"description\":\"Type of memory: bug, decision, project, memory, pattern, session, reference, brainstorm, idea\",\"enum\":[\"bug\",\"decision\",\"project\",\"memory\",\"pattern\",\"session\",\"reference\",\"brainstorm\",\"idea\"]},\"status\":{\"type\":\"string\",\"description\":\"Optional status: open, resolved, active, archived, wontfix\",\"enum\":[\"open\",\"resolved\",\"active\",\"archived\",\"wontfix\"]},\"severity\":{\"type\":\"string\",\"description\":\"Optional severity for bugs: p0, p1, p2, p3\",\"enum\":[\"p0\",\"p1\",\"p2\",\"p3\"]},\"tags\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"description\":\"Optional tags for categorization\"}},\"required\":[\"title\",\"content\",\"memory_type\"]}",
    )
  schema
}

fn find_schema() -> mcp.ToolInputSchema {
  let assert Ok(schema) =
    mcp.tool_input_schema(
      "{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"Semantic search query\"},\"type\":{\"type\":\"string\",\"description\":\"Filter by memory type\",\"enum\":[\"bug\",\"decision\",\"project\",\"memory\",\"pattern\",\"session\",\"reference\",\"brainstorm\",\"idea\"]},\"status\":{\"type\":\"string\",\"description\":\"Filter by status\",\"enum\":[\"open\",\"resolved\",\"active\",\"archived\",\"wontfix\"]},\"tags\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"description\":\"Filter by tags (all must match)\"},\"author\":{\"type\":\"string\",\"description\":\"Filter by author\"},\"limit\":{\"type\":\"integer\",\"description\":\"Maximum number of results (default: 10)\"}},\"required\":[\"query\"]}",
    )
  schema
}

fn list_schema() -> mcp.ToolInputSchema {
  let assert Ok(schema) =
    mcp.tool_input_schema(
      "{\"type\":\"object\",\"properties\":{\"type\":{\"type\":\"string\",\"description\":\"Filter by memory type\",\"enum\":[\"bug\",\"decision\",\"project\",\"memory\",\"pattern\",\"session\",\"reference\",\"brainstorm\",\"idea\"]},\"status\":{\"type\":\"string\",\"description\":\"Filter by status\",\"enum\":[\"open\",\"resolved\",\"active\",\"archived\",\"wontfix\"]},\"tags\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"description\":\"Filter by tags\"},\"author\":{\"type\":\"string\",\"description\":\"Filter by author\"},\"sort_by\":{\"type\":\"string\",\"description\":\"Sort field (e.g. updated, created)\"}}}",
    )
  schema
}

fn update_schema() -> mcp.ToolInputSchema {
  let assert Ok(schema) =
    mcp.tool_input_schema(
      "{\"type\":\"object\",\"properties\":{\"vault_path\":{\"type\":\"string\",\"description\":\"Vault-relative path of the memory to update\"},\"status\":{\"type\":\"string\",\"description\":\"New status\",\"enum\":[\"open\",\"resolved\",\"active\",\"archived\",\"wontfix\"]},\"tags\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"description\":\"New tags (replaces existing)\"},\"content\":{\"type\":\"string\",\"description\":\"New markdown content (replaces existing)\"}},\"required\":[\"vault_path\"]}",
    )
  schema
}

fn reindex_schema() -> mcp.ToolInputSchema {
  let assert Ok(schema) =
    mcp.tool_input_schema(
      "{\"type\":\"object\",\"properties\":{\"full\":{\"type\":\"boolean\",\"description\":\"Whether to do a full reindex (default: false)\"}}}",
    )
  schema
}

// ---------- Public API ----------

/// Build the MCP server with all tools registered.
/// Returns a server value that can be used by any transport.
pub fn build(
  config: Config,
  embedder_subject: Subject(embedder.Message),
) -> mcp_toolkit.Server {
  mcp_toolkit.new("alex-memory", "1.0.0")
  |> mcp_toolkit.description(
    "Persistent memory system for Claude Code with semantic search",
  )
  |> mcp_toolkit.add_tool(
    mcp.Tool(
      name: "memory_store",
      description: Some(
        "Store a new memory in the vault. Creates a markdown file and indexes it for semantic search.",
      ),
      input_schema: store_schema(),
      annotations: None,
    ),
    decode_store_args(),
    handle_store(config, embedder_subject),
  )
  |> mcp_toolkit.add_tool(
    mcp.Tool(
      name: "memory_find",
      description: Some(
        "Search memories using semantic similarity. Returns ranked results with content previews.",
      ),
      input_schema: find_schema(),
      annotations: None,
    ),
    decode_find_args(),
    handle_find(config),
  )
  |> mcp_toolkit.add_tool(
    mcp.Tool(
      name: "memory_list",
      description: Some(
        "List memories with optional filters. Uses metadata filtering without semantic search.",
      ),
      input_schema: list_schema(),
      annotations: None,
    ),
    decode_list_args(),
    handle_list(config),
  )
  |> mcp_toolkit.add_tool(
    mcp.Tool(
      name: "memory_update",
      description: Some(
        "Update an existing memory's status, tags, or content. The vault watcher will re-index automatically.",
      ),
      input_schema: update_schema(),
      annotations: None,
    ),
    decode_update_args(),
    handle_update(config),
  )
  |> mcp_toolkit.add_tool(
    mcp.Tool(
      name: "memory_reindex",
      description: Some(
        "Trigger a full re-index of all vault markdown files.",
      ),
      input_schema: reindex_schema(),
      annotations: None,
    ),
    decode_reindex_args(),
    handle_reindex(embedder_subject),
  )
  |> mcp_toolkit.build()
}

