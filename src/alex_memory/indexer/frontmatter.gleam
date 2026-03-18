import alex_memory/types.{
  type MemoryDocument, type Metadata, Metadata, MemoryDocument, Reference, Vault,
}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// ---------- Public API ----------

/// Parse a markdown string that may contain YAML frontmatter.
/// Returns a MemoryDocument with metadata extracted from frontmatter
/// and title extracted from the first `# ` heading in the body.
/// If no frontmatter is present, defaults to Reference type and Vault source.
pub fn parse(content: String) -> Result(MemoryDocument, String) {
  let lines = string.split(content, "\n")
  case lines {
    ["---", ..rest] -> {
      let #(fm_lines, body_lines) = split_at_delimiter(rest, "---")
      let kv = parse_frontmatter_lines(fm_lines)
      use meta <- result_then(build_metadata(kv))
      let body = string.join(body_lines, "\n")
      let title = extract_title(body)
      Ok(MemoryDocument(title: title, content: body, metadata: meta))
    }
    _ -> {
      let body = content
      let title = extract_title(body)
      let meta =
        Metadata(
          memory_type: Reference,
          status: None,
          severity: None,
          tags: [],
          created: "",
          updated: "",
          source: Vault,
          vault_path: "",
          schema_version: 1,
        )
      Ok(MemoryDocument(title: title, content: body, metadata: meta))
    }
  }
}

/// Serialize metadata, title, and content into a markdown string with frontmatter.
pub fn serialize(meta: Metadata, title: String, content: String) -> String {
  let lines = [
    "---",
    "type: " <> types.memory_type_to_string(meta.memory_type),
    ..optional_field("status", option.map(meta.status, types.status_to_string))
  ]
  let lines =
    list.append(
      lines,
      optional_field(
        "severity",
        option.map(meta.severity, types.severity_to_string),
      ),
    )
  let lines = case meta.tags {
    [] -> lines
    tags ->
      list.append(lines, [
        "tags: [" <> string.join(tags, ", ") <> "]",
      ])
  }
  let lines =
    list.append(lines, [
      "created: " <> meta.created,
      "updated: " <> meta.updated,
      "source: " <> types.source_to_string(meta.source),
      "---",
      "",
      "# " <> title,
      "",
      content,
    ])
  string.join(lines, "\n")
}

// ---------- Private helpers ----------

/// Split a list of lines at the first occurrence of `delimiter`.
/// Returns #(before, after) where after does not include the delimiter line.
fn split_at_delimiter(
  lines: List(String),
  delimiter: String,
) -> #(List(String), List(String)) {
  do_split(lines, delimiter, [])
}

fn do_split(
  lines: List(String),
  delimiter: String,
  acc: List(String),
) -> #(List(String), List(String)) {
  case lines {
    [] -> #(list.reverse(acc), [])
    [head, ..tail] ->
      case head == delimiter {
        True -> #(list.reverse(acc), tail)
        False -> do_split(tail, delimiter, [head, ..acc])
      }
  }
}

/// Parse frontmatter lines into key-value pairs by splitting on `: `.
fn parse_frontmatter_lines(lines: List(String)) -> List(#(String, String)) {
  list.filter_map(lines, fn(line) {
    case string.split_once(line, ": ") {
      Ok(#(k, v)) -> Ok(#(string.trim(k), string.trim(v)))
      Error(_) -> Error(Nil)
    }
  })
}

/// Look up a key in a key-value list.
fn find_key(kv: List(#(String, String)), key: String) -> Option(String) {
  case list.find_map(kv, fn(pair) {
    case pair.0 == key {
      True -> Ok(pair.1)
      False -> Error(Nil)
    }
  }) {
    Ok(v) -> Some(v)
    Error(_) -> None
  }
}

/// Build a Metadata record from parsed key-value pairs.
fn build_metadata(
  kv: List(#(String, String)),
) -> Result(Metadata, String) {
  // type is required
  use memory_type <- result_then(case find_key(kv, "type") {
    Some(v) -> types.memory_type_from_string(v)
    None -> Error("Missing required frontmatter field: type")
  })

  let status = case find_key(kv, "status") {
    Some(v) ->
      case types.status_from_string(v) {
        Ok(s) -> Some(s)
        Error(_) -> None
      }
    None -> None
  }

  let severity = case find_key(kv, "severity") {
    Some(v) ->
      case severity_from_string(v) {
        Ok(s) -> Some(s)
        Error(_) -> None
      }
    None -> None
  }

  let tags = case find_key(kv, "tags") {
    Some(v) -> parse_tags(v)
    None -> []
  }

  let created = find_key(kv, "created") |> option.unwrap("")
  let updated = find_key(kv, "updated") |> option.unwrap("")

  use source <- result_then(case find_key(kv, "source") {
    Some(v) -> types.source_from_string(v)
    None -> Ok(types.Vault)
  })

  Ok(Metadata(
    memory_type: memory_type,
    status: status,
    severity: severity,
    tags: tags,
    created: created,
    updated: updated,
    source: source,
    vault_path: "",
    schema_version: 1,
  ))
}

/// Parse a tags string like `[cook, scheduler]` into a list of strings.
fn parse_tags(raw: String) -> List(String) {
  let stripped =
    raw
    |> string.trim
    |> strip_brackets
  case stripped {
    "" -> []
    s ->
      string.split(s, ",")
      |> list.map(string.trim)
      |> list.filter(fn(t) { t != "" })
  }
}

fn strip_brackets(s: String) -> String {
  let s = case string.starts_with(s, "[") {
    True -> string.drop_start(s, 1)
    False -> s
  }
  case string.ends_with(s, "]") {
    True -> string.drop_end(s, 1)
    False -> s
  }
}

/// Extract the title from the first `# ` heading in the body.
fn extract_title(body: String) -> String {
  let lines = string.split(body, "\n")
  case list.find(lines, fn(line) { string.starts_with(line, "# ") }) {
    Ok(line) -> string.drop_start(line, 2)
    Error(_) -> ""
  }
}

/// Parse severity from string (not in types module).
fn severity_from_string(s: String) -> Result(types.Severity, String) {
  case s {
    "p0" -> Ok(types.P0)
    "p1" -> Ok(types.P1)
    "p2" -> Ok(types.P2)
    "p3" -> Ok(types.P3)
    _ -> Error("Unknown severity: " <> s)
  }
}

/// Helper to build an optional field line.
fn optional_field(key: String, value: Option(String)) -> List(String) {
  case value {
    Some(v) -> [key <> ": " <> v]
    None -> []
  }
}

/// Monadic bind for Result — avoids deep nesting.
fn result_then(
  result: Result(a, e),
  f: fn(a) -> Result(b, e),
) -> Result(b, e) {
  case result {
    Ok(v) -> f(v)
    Error(e) -> Error(e)
  }
}
