import gleam/float
import gleam/int
import gleam/list
import gleam/string

/// Returns True if the string must be quoted per TOON spec.
fn needs_quoting(value: String) -> Bool {
  case value {
    "" -> True
    "true" -> True
    "false" -> True
    "null" -> True
    _ ->
      string.starts_with(value, "-")
      || has_leading_or_trailing_whitespace(value)
      || looks_like_number(value)
      || contains_special_char(value)
  }
}

fn has_leading_or_trailing_whitespace(value: String) -> Bool {
  case string.first(value), string.last(value) {
    Ok(first), Ok(last) ->
      first == " " || first == "\t" || last == " " || last == "\t"
    _, _ -> False
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

fn contains_special_char(value: String) -> Bool {
  string.contains(value, ",")
  || string.contains(value, ":")
  || string.contains(value, "\"")
  || string.contains(value, "\\")
  || string.contains(value, "[")
  || string.contains(value, "]")
  || string.contains(value, "{")
  || string.contains(value, "}")
  || string.contains(value, "\n")
  || string.contains(value, "\t")
  || string.contains(value, "\r")
}

/// Escape special characters inside a quoted TOON string.
fn escape(value: String) -> String {
  value
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\r", "\\r")
  |> string.replace("\t", "\\t")
}

/// Quote a TOON value if needed per spec.
pub fn quote(value: String) -> String {
  case needs_quoting(value) {
    True -> "\"" <> escape(value) <> "\""
    False -> value
  }
}

/// Format a tabular TOON block.
///
/// Output format:
///   name[count]{field1,field2,...}:
///     value1,value2,...
///     ...
pub fn table(
  name: String,
  fields: List(String),
  rows: List(List(String)),
) -> String {
  let count = list.length(rows)
  let fields_str = string.join(fields, ",")
  let header =
    name
    <> "["
    <> int.to_string(count)
    <> "]{"
    <> fields_str
    <> "}:\n"
  let body =
    list.map(rows, fn(row) {
      "  " <> string.join(list.map(row, quote), ",") <> "\n"
    })
    |> string.join("")
  header <> body
}
