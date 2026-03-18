import gleam/list
import gleam/string

pub type ContentChunk {
  ContentChunk(content: String, index: Int, total: Int)
}

/// Split markdown content into chunks at h2/h3 heading boundaries.
/// The max_tokens parameter is accepted for future use but currently unused.
pub fn chunk(content: String, _max_tokens: Int) -> List(ContentChunk) {
  let lines = string.split(content, "\n")
  let sections = split_into_sections(lines, [], [])
  let non_empty =
    list.filter(sections, fn(s) { string.trim(s) != "" })
  let total = list.length(non_empty)
  list.index_map(non_empty, fn(section, i) {
    ContentChunk(content: section, index: i, total: total)
  })
}

/// Walk lines, splitting at ## or ### headings.
/// Returns a list of section strings (joined lines).
fn split_into_sections(
  lines: List(String),
  current: List(String),
  acc: List(String),
) -> List(String) {
  case lines {
    [] -> {
      // Flush remaining current section
      let section = current |> list.reverse |> string.join("\n")
      list.reverse([section, ..acc])
    }
    [line, ..rest] -> {
      case is_split_heading(line) {
        True -> {
          // Flush current section and start a new one with this heading
          let section = current |> list.reverse |> string.join("\n")
          split_into_sections(rest, [line], [section, ..acc])
        }
        False -> {
          split_into_sections(rest, [line, ..current], acc)
        }
      }
    }
  }
}

fn is_split_heading(line: String) -> Bool {
  string.starts_with(line, "## ") || string.starts_with(line, "### ")
}
