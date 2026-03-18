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
