import alex_memory/indexer/frontmatter
import alex_memory/types
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import simplifile

// ---------- FFI ----------

@external(erlang, "alex_memory_ffi", "get_today")
fn get_today() -> String

// ---------- Public API ----------

/// Write a new memory markdown file to the vault.
/// Returns a vault-relative path on success.
pub fn write_memory(
  vault_path: String,
  claude_dir: String,
  memory_type: types.MemoryType,
  title: String,
  content: String,
  status: Option(types.Status),
  severity: Option(types.Severity),
  tags: List(String),
  author: String,
) -> Result(String, String) {
  let today = get_today()
  let type_dir = types.memory_type_to_dir(memory_type)
  let slug = slugify(title)
  let relative_path = claude_dir <> "/" <> type_dir <> "/" <> slug <> ".md"
  let abs_dir = vault_path <> "/" <> claude_dir <> "/" <> type_dir
  let abs_path = vault_path <> "/" <> relative_path

  // Ensure directory exists
  case simplifile.create_directory_all(abs_dir) {
    Ok(_) -> Nil
    Error(_) -> Nil
  }

  let meta =
    types.Metadata(
      memory_type: memory_type,
      status: status,
      severity: severity,
      tags: tags,
      created: today,
      updated: today,
      source: types.Conversation,
      vault_path: relative_path,
      schema_version: 1,
      author: author,
    )

  let file_content = frontmatter.serialize(meta, title, content)

  case simplifile.write(abs_path, file_content) {
    Ok(_) -> Ok(relative_path)
    Error(e) -> Error("Failed to write file: " <> string.inspect(e))
  }
}

/// Update an existing memory file's status, tags, and/or content.
pub fn update_memory(
  vault_path: String,
  relative_path: String,
  status: Option(types.Status),
  tags: Option(List(String)),
  content: Option(String),
) -> Result(Nil, String) {
  let today = get_today()
  let abs_path = vault_path <> "/" <> relative_path

  case simplifile.read(abs_path) {
    Error(e) -> Error("Failed to read file: " <> string.inspect(e))
    Ok(raw) -> {
      case frontmatter.parse(raw) {
        Error(e) -> Error("Failed to parse file: " <> e)
        Ok(doc) -> {
          let new_status = case status {
            Some(_) -> status
            None -> doc.metadata.status
          }
          let new_tags = case tags {
            Some(t) -> t
            None -> doc.metadata.tags
          }
          let new_content = case content {
            Some(c) -> c
            None -> doc.content
          }
          let updated_meta =
            types.Metadata(
              memory_type: doc.metadata.memory_type,
              status: new_status,
              severity: doc.metadata.severity,
              tags: new_tags,
              created: doc.metadata.created,
              updated: today,
              source: doc.metadata.source,
              vault_path: doc.metadata.vault_path,
              schema_version: doc.metadata.schema_version,
              author: doc.metadata.author,
            )
          let file_content =
            frontmatter.serialize(updated_meta, doc.title, new_content)
          case simplifile.write(abs_path, file_content) {
            Ok(_) -> Ok(Nil)
            Error(e) -> Error("Failed to write file: " <> string.inspect(e))
          }
        }
      }
    }
  }
}

/// Convert a title string into a URL-safe slug.
/// Lowercases, replaces spaces with hyphens, removes non-alphanumeric/hyphen chars,
/// collapses consecutive hyphens, and trims leading/trailing hyphens.
pub fn slugify(title: String) -> String {
  title
  |> string.lowercase
  |> string.to_graphemes
  |> list.map(fn(c) {
    case c {
      " " -> "-"
      _ -> c
    }
  })
  |> list.filter(fn(c) {
    is_lowercase_alpha(c) || is_digit(c) || c == "-"
  })
  |> string.join("")
  |> collapse_hyphens
  |> trim_hyphens
}

// ---------- Private helpers ----------

fn is_lowercase_alpha(c: String) -> Bool {
  case c {
    "a" | "b" | "c" | "d" | "e" | "f" | "g" | "h" | "i" | "j" | "k" | "l"
    | "m" | "n" | "o" | "p" | "q" | "r" | "s" | "t" | "u" | "v" | "w" | "x"
    | "y" | "z" -> True
    _ -> False
  }
}

fn is_digit(c: String) -> Bool {
  case c {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

fn trim_hyphens(s: String) -> String {
  s
  |> trim_leading_hyphens
  |> trim_trailing_hyphens
}

fn trim_leading_hyphens(s: String) -> String {
  case string.starts_with(s, "-") {
    True -> trim_leading_hyphens(string.drop_start(s, 1))
    False -> s
  }
}

fn trim_trailing_hyphens(s: String) -> String {
  case string.ends_with(s, "-") {
    True -> trim_trailing_hyphens(string.drop_end(s, 1))
    False -> s
  }
}

fn collapse_hyphens(s: String) -> String {
  do_collapse(string.to_graphemes(s), False, [])
  |> list.reverse
  |> string.join("")
}

fn do_collapse(
  chars: List(String),
  last_was_hyphen: Bool,
  acc: List(String),
) -> List(String) {
  case chars {
    [] -> acc
    ["-", ..rest] ->
      case last_was_hyphen {
        True -> do_collapse(rest, True, acc)
        False -> do_collapse(rest, True, ["-", ..acc])
      }
    [c, ..rest] -> do_collapse(rest, False, [c, ..acc])
  }
}
