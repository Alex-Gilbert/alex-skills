import alex_memory/config.{type Config}
import alex_memory/indexer/chunker
import alex_memory/indexer/frontmatter
import alex_memory/indexer/point_id
import alex_memory/infra/ollama_client
import alex_memory/infra/qdrant_client
import alex_memory/types
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/string
import simplifile

// ---------- Types ----------

pub type Message {
  IndexFile(path: String, vault_relative: String)
  DeleteFile(vault_relative: String)
  ReindexAll
  Shutdown
}

pub type State {
  State(config: Config)
}

// ---------- Public API ----------

pub fn start(config: Config) -> Result(Subject(Message), actor.StartError) {
  let result =
    actor.new(State(config: config))
    |> actor.on_message(handle_message)
    |> actor.start
  case result {
    Ok(started) -> Ok(started.data)
    Error(e) -> Error(e)
  }
}

// ---------- Message handler ----------

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    IndexFile(path: full_path, vault_relative: vault_relative) -> {
      index_file(state.config, full_path, vault_relative)
      actor.continue(state)
    }

    DeleteFile(vault_relative: vault_relative) -> {
      delete_file(state.config, vault_relative)
      actor.continue(state)
    }

    ReindexAll -> {
      reindex_all(state.config)
      actor.continue(state)
    }

    Shutdown -> actor.stop()
  }
}

// ---------- Core pipeline ----------

/// Read -> parse -> delete old -> chunk -> embed -> upsert
fn index_file(
  config: Config,
  full_path: String,
  vault_relative: String,
) -> Nil {
  case simplifile.read(full_path) {
    Error(_) -> {
      io.println_error("Embedder: failed to read file: " <> full_path)
      Nil
    }
    Ok(content) -> {
      case frontmatter.parse(content) {
        Error(e) -> {
          io.println_error(
            "Embedder: failed to parse frontmatter in " <> vault_relative <> ": " <> e,
          )
          Nil
        }
        Ok(doc) -> {
          // Delete stale points for this file
          delete_file(config, vault_relative)

          // Chunk the body content
          let chunks = chunker.chunk(doc.content, config.indexer.chunk_max_tokens)

          // Embed and upsert each chunk
          list.each(chunks, fn(chunk) {
            let text = doc.title <> "\n" <> chunk.content
            case
              ollama_client.embed(config.ollama.url, config.ollama.model, text)
            {
              Error(_) -> {
                io.println_error(
                  "Embedder: failed to embed chunk "
                  <> int.to_string(chunk.index)
                  <> " of "
                  <> vault_relative,
                )
                Nil
              }
              Ok(vector) -> {
                let id = point_id.generate(vault_relative, chunk.index)
                let payload = build_payload(doc, vault_relative, chunk)
                case
                  qdrant_client.upsert(
                    config.qdrant.url,
                    config.qdrant.collection,
                    id,
                    vector,
                    payload,
                  )
                {
                  Ok(_) -> Nil
                  Error(_) -> {
                    io.println_error(
                      "Embedder: failed to upsert chunk "
                      <> int.to_string(chunk.index)
                      <> " of "
                      <> vault_relative,
                    )
                    Nil
                  }
                }
              }
            }
          })
        }
      }
    }
  }
}

/// Delete all Qdrant points matching vault_path
fn delete_file(config: Config, vault_relative: String) -> Nil {
  let _ =
    qdrant_client.delete_by_field(
      config.qdrant.url,
      config.qdrant.collection,
      "vault_path",
      vault_relative,
    )
  Nil
}

/// Walk vault directory and index every .md file
fn reindex_all(config: Config) -> Nil {
  let files = walk_vault_markdown(config.vault.path, config.vault.ignore)
  list.each(files, fn(full_path) {
    let vault_relative = make_relative(full_path, config.vault.path)
    index_file(config, full_path, vault_relative)
  })
}

// ---------- Helpers ----------

/// List all .md files in vault_path, filtering out ignored directories.
pub fn walk_vault_markdown(
  vault_path: String,
  ignore: List(String),
) -> List(String) {
  case simplifile.get_files(vault_path) {
    Error(_) -> []
    Ok(files) ->
      list.filter(files, fn(path) {
        string.ends_with(path, ".md") && !is_ignored(path, vault_path, ignore)
      })
  }
}

/// Return True if the path falls inside any ignored directory name.
fn is_ignored(
  path: String,
  vault_path: String,
  ignore: List(String),
) -> Bool {
  let relative = make_relative(path, vault_path)
  list.any(ignore, fn(dir) {
    string.starts_with(relative, dir <> "/")
    || string.contains(relative, "/" <> dir <> "/")
  })
}

/// Strip the vault_path prefix to produce a vault-relative path.
fn make_relative(full_path: String, vault_path: String) -> String {
  let prefix = vault_path <> "/"
  case string.starts_with(full_path, prefix) {
    True -> string.drop_start(full_path, string.length(prefix))
    False -> full_path
  }
}

/// Build a Qdrant JSON payload from a MemoryDocument and chunk info.
pub fn build_payload(
  doc: types.MemoryDocument,
  vault_relative: String,
  chunk: chunker.ContentChunk,
) -> json.Json {
  let base_fields = [
    #("vault_path", json.string(vault_relative)),
    #("type", json.string(types.memory_type_to_string(doc.metadata.memory_type))),
    #("title", json.string(doc.title)),
    #("content", json.string(chunk.content)),
    #("chunk_index", json.int(chunk.index)),
    #("chunk_total", json.int(chunk.total)),
    #("created", json.string(doc.metadata.created)),
    #("updated", json.string(doc.metadata.updated)),
    #("source", json.string(types.source_to_string(doc.metadata.source))),
    #("schema_version", json.int(doc.metadata.schema_version)),
    #("tags", json.array(doc.metadata.tags, json.string)),
  ]

  let fields_with_status = case doc.metadata.status {
    None -> base_fields
    Some(s) ->
      list.append(base_fields, [
        #("status", json.string(types.status_to_string(s))),
      ])
  }

  let all_fields = case doc.metadata.severity {
    None -> fields_with_status
    Some(sev) ->
      list.append(fields_with_status, [
        #("severity", json.string(types.severity_to_string(sev))),
      ])
  }

  json.object(all_fields)
}
