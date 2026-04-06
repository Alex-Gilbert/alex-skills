import alex_memory/config.{type Config}
import alex_memory/indexer/embedder
import alex_memory/infra/ollama_client
import alex_memory/infra/qdrant_client
import alex_memory/infra/vikunja_client
import alex_memory/mcp/author
import alex_memory/mcp/dashboard_writer
import alex_memory/mcp/vault_writer
import alex_memory/toon
import alex_memory/types
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
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

// ---------- Decoders (pub — used by http_server) ----------

pub fn decode_store_args() -> decode.Decoder(StoreArgs) {
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

pub fn decode_find_args() -> decode.Decoder(FindArgs) {
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

pub fn decode_update_args() -> decode.Decoder(UpdateArgs) {
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

// ---------- Filter builder ----------

pub fn build_filter(
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

pub fn get_payload_string(
  payload: decode.Dynamic,
  field: String,
) -> String {
  case decode.run(payload, decode.at([field], decode.string)) {
    Ok(value) -> value
    Error(_) -> ""
  }
}

// ---------- Deduplication helper ----------

pub fn deduplicate_by_vault_path(
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

// ---------- Handlers ----------

pub fn handle_store(
  config: Config,
  embedder_subject: Subject(embedder.Message),
  args: StoreArgs,
) -> Result(String, String) {
  case types.memory_type_from_string(args.memory_type) {
    Error(e) -> Error(e)
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
        |> result.unwrap(config.http.default_author)

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
          Ok("stored: " <> vault_path)
        }
        Error(e) -> Error("Failed to write memory: " <> e)
      }
    }
  }
}

pub fn handle_find(
  config: Config,
  args: FindArgs,
) -> Result(String, String) {
  case
    ollama_client.embed(config.ollama.url, config.ollama.model, args.query)
  {
    Error(_) -> Error("Failed to generate query embedding")
    Ok(vector) -> {
      let filter = build_filter(args.type_, args.status, args.tags, args.author)

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
          {
              let rows =
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

                  [title, score_str, type_str, vault_path, status_str, author_str, preview]
                })
              Ok(toon.table("results", ["title", "score", "type", "path", "status", "author", "preview"], rows))
          }
        }
      }
    }
  }
}

pub fn handle_list(
  config: Config,
  args: ListArgs,
) -> Result(String, String) {
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
      // Deduplicate by vault_path (chunks produce multiple entries)
      let unique_points = deduplicate_by_vault_path(points)

      {
          let rows =
            list.map(unique_points, fn(point) {
              let title = get_payload_string(point.payload, "title")
              let vault_path = get_payload_string(point.payload, "vault_path")
              let type_str = get_payload_string(point.payload, "type")
              let status_str =
                get_payload_string(point.payload, "status")
              let updated = get_payload_string(point.payload, "updated")
              let author_str = get_payload_string(point.payload, "author")

              [title, type_str, status_str, author_str, vault_path, updated]
            })
          Ok(toon.table("memories", ["title", "type", "status", "author", "path", "updated"], rows))
      }
    }
  }
}

pub fn handle_read(
  config: Config,
  vault_path: String,
) -> Result(String, String) {
  let path = config.vault.path <> "/" <> vault_path
  case simplifile.read(path) {
    Ok(content) -> Ok(content)
    Error(_) -> Error("not found: " <> path)
  }
}

pub fn handle_update(
  config: Config,
  args: UpdateArgs,
) -> Result(String, String) {
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
      Ok("updated: " <> args.vault_path)
    }
    Error(e) -> Error("Failed to update memory: " <> e)
  }
}

pub fn handle_reindex(
  embedder_subject: Subject(embedder.Message),
) -> Result(String, String) {
  process.send(embedder_subject, embedder.ReindexAll)
  Ok("Reindex triggered. All vault markdown files will be re-embedded and indexed.")
}

// ---------- Vikunja argument types ----------

pub type CreateProjectArgs {
  CreateProjectArgs(title: String, description: String)
}

pub type CreateTaskArgs {
  CreateTaskArgs(
    project_id: Int,
    title: String,
    description: String,
    priority: Option(Int),
  )
}

pub type UpdateTaskArgs {
  UpdateTaskArgs(
    project_id: Int,
    title: Option(String),
    description: Option(String),
    done: Option(Bool),
    priority: Option(Int),
  )
}

// ---------- Vikunja decoders ----------

pub fn decode_create_project_args() -> decode.Decoder(CreateProjectArgs) {
  use title <- decode.field("title", decode.string)
  use description <- decode.optional_field("description", "", decode.string)
  decode.success(CreateProjectArgs(title: title, description: description))
}

pub fn decode_create_task_args() -> decode.Decoder(CreateTaskArgs) {
  use project_id <- decode.field("project_id", decode.int)
  use title <- decode.field("title", decode.string)
  use description <- decode.optional_field("description", "", decode.string)
  use priority <- decode.optional_field(
    "priority",
    None,
    decode.optional(decode.int),
  )
  decode.success(CreateTaskArgs(
    project_id: project_id,
    title: title,
    description: description,
    priority: priority,
  ))
}

pub fn decode_update_task_args() -> decode.Decoder(UpdateTaskArgs) {
  use project_id <- decode.field("project_id", decode.int)
  use title <- decode.optional_field(
    "title",
    None,
    decode.optional(decode.string),
  )
  use description <- decode.optional_field(
    "description",
    None,
    decode.optional(decode.string),
  )
  use done <- decode.optional_field(
    "done",
    None,
    decode.optional(decode.bool),
  )
  use priority <- decode.optional_field(
    "priority",
    None,
    decode.optional(decode.int),
  )
  decode.success(UpdateTaskArgs(
    project_id: project_id,
    title: title,
    description: description,
    done: done,
    priority: priority,
  ))
}

// ---------- Vikunja handlers ----------

pub fn handle_list_projects(
  url: String,
  token: String,
) -> Result(String, String) {
  case vikunja_client.list_projects(url, token) {
    Ok(projects) -> {
      let rows =
        list.map(projects, fn(p) {
          [int.to_string(p.id), p.title, p.description]
        })
      Ok(toon.table("projects", ["id", "title", "description"], rows))
    }
    Error(e) -> Error("Failed to list projects: " <> string.inspect(e))
  }
}

pub fn handle_create_project(
  url: String,
  token: String,
  args: CreateProjectArgs,
) -> Result(String, String) {
  case vikunja_client.create_project(url, token, args.title, args.description) {
    Ok(p) ->
      Ok(
        "created: " <> p.title <> " (id: " <> int.to_string(p.id) <> ")",
      )
    Error(e) -> Error("Failed to create project: " <> string.inspect(e))
  }
}

pub fn handle_list_tasks(
  url: String,
  token: String,
  project_id: Int,
) -> Result(String, String) {
  case vikunja_client.list_tasks(url, token, project_id) {
    Ok(tasks) -> {
      let rows =
        list.map(tasks, fn(t) {
          [
            int.to_string(t.id),
            t.title,
            case t.done {
              True -> "done"
              False -> "open"
            },
            int.to_string(t.priority),
            int.to_string(t.project_id),
          ]
        })
      Ok(toon.table(
        "tasks",
        ["id", "title", "status", "priority", "project_id"],
        rows,
      ))
    }
    Error(e) -> Error("Failed to list tasks: " <> string.inspect(e))
  }
}

pub fn handle_create_task(
  url: String,
  token: String,
  args: CreateTaskArgs,
) -> Result(String, String) {
  case
    vikunja_client.create_task(
      url,
      token,
      args.project_id,
      args.title,
      args.description,
      args.priority,
    )
  {
    Ok(t) ->
      Ok(
        "created: " <> t.title <> " (id: " <> int.to_string(t.id) <> ")",
      )
    Error(e) -> Error("Failed to create task: " <> string.inspect(e))
  }
}

pub fn handle_update_task(
  url: String,
  token: String,
  task_id: Int,
  args: UpdateTaskArgs,
) -> Result(String, String) {
  case
    vikunja_client.update_task(
      url,
      token,
      args.project_id,
      task_id,
      args.title,
      args.description,
      args.done,
      args.priority,
    )
  {
    Ok(_) -> Ok("updated: task " <> int.to_string(task_id))
    Error(e) -> Error("Failed to update task: " <> string.inspect(e))
  }
}
