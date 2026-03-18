import alex_memory/config.{type Config}
import alex_memory/indexer/embedder
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/string
import simplifile

// ---------- Types ----------

pub type Message {
  FileChanged(path: String)
  FileDeleted(path: String)
  Tick
  Shutdown
}

pub type State {
  State(
    config: Config,
    self: Subject(Message),
    embedder: Subject(embedder.Message),
    pending: List(String),
    file_times: Dict(String, Int),
  )
}

// ---------- Public API ----------

pub fn start(
  config: Config,
  embedder_subject: Subject(embedder.Message),
) -> Result(Subject(Message), actor.StartError) {
  let result =
    actor.new_with_initialiser(1000, fn(self_subject) {
      let state =
        State(
          config: config,
          self: self_subject,
          embedder: embedder_subject,
          pending: [],
          file_times: dict.new(),
        )
      actor.initialised(state)
      |> actor.returning(self_subject)
      |> Ok
    })
    |> actor.on_message(handle_message)
    |> actor.start
  case result {
    Ok(started) -> Ok(started.data)
    Error(e) -> Error(e)
  }
}

/// Notify the watcher of a changed file (external API).
pub fn notify_change(watcher: Subject(Message), path: String) -> Nil {
  process.send(watcher, FileChanged(path))
}

/// Notify the watcher of a deleted file (external API).
pub fn notify_delete(watcher: Subject(Message), path: String) -> Nil {
  process.send(watcher, FileDeleted(path))
}

// ---------- Message handler ----------

fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    FileChanged(path: path) -> {
      // Add to pending list (deduplicated) and schedule a debounce tick
      let already_pending = list.contains(state.pending, path)
      let new_pending = case already_pending {
        True -> state.pending
        False -> [path, ..state.pending]
      }
      // Schedule a tick after debounce_ms; if one is already scheduled it will
      // fire first and process this file; the next tick is a no-op on empty pending.
      let _ =
        process.send_after(state.self, state.config.indexer.debounce_ms, Tick)
      actor.continue(State(..state, pending: new_pending))
    }

    FileDeleted(path: path) -> {
      // Immediately send delete to embedder (no debounce needed)
      let vault_relative = make_relative(path, state.config.vault.path)
      process.send(state.embedder, embedder.DeleteFile(vault_relative))
      // Remove from pending if present
      let new_pending = list.filter(state.pending, fn(p) { p != path })
      actor.continue(State(..state, pending: new_pending))
    }

    Tick -> {
      // Process all pending paths, filter to indexable files
      list.each(state.pending, fn(full_path) {
        case should_index(full_path, state.config) {
          True -> {
            let vault_relative = make_relative(full_path, state.config.vault.path)
            process.send(
              state.embedder,
              embedder.IndexFile(
                path: full_path,
                vault_relative: vault_relative,
              ),
            )
          }
          False -> Nil
        }
      })
      actor.continue(State(..state, pending: []))
    }

    Shutdown -> actor.stop()
  }
}

// ---------- Helpers ----------

/// Return True if the path should be indexed: .md extension and not in an
/// ignored directory.
pub fn should_index(path: String, config: Config) -> Bool {
  string.ends_with(path, ".md")
  && !is_ignored(path, config.vault.path, config.vault.ignore)
}

/// Return True if the path falls inside any ignored directory.
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
pub fn make_relative(full_path: String, vault_path: String) -> String {
  let prefix = vault_path <> "/"
  case string.starts_with(full_path, prefix) {
    True -> string.drop_start(full_path, string.length(prefix))
    False -> full_path
  }
}

/// Scan the vault for .md files and return those modified after `since_ms`.
/// `since_ms` is a Unix timestamp in milliseconds; pass 0 to get all files.
pub fn scan_for_changes(
  config: Config,
  since_ms: Int,
) -> List(String) {
  case simplifile.get_files(config.vault.path) {
    Error(_) -> []
    Ok(files) ->
      list.filter(files, fn(path) {
        should_index(path, config) && file_modified_after(path, since_ms)
      })
  }
}

/// Return True if the file's mtime is newer than `since_ms` milliseconds.
/// Returns True when `since_ms` is 0 (include everything).
fn file_modified_after(path: String, since_ms: Int) -> Bool {
  case since_ms {
    0 -> True
    _ -> {
      case simplifile.file_info(path) {
        Error(_) -> False
        Ok(info) -> {
          // simplifile returns mtime_seconds (Unix epoch seconds)
          let mtime_ms = info.mtime_seconds * 1000
          mtime_ms > since_ms
        }
      }
    }
  }
}
