import alex_memory/indexer/frontmatter
import alex_memory/types
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

pub fn parse_basic_frontmatter_test() {
  let input =
    "---
type: bug
status: open
severity: p1
tags: [cook, scheduler]
created: 2026-03-17
updated: 2026-03-17
source: conversation
---

# Scheduler Race Condition

The scheduler can deadlock."

  let assert Ok(doc) = frontmatter.parse(input)
  doc.title |> should.equal("Scheduler Race Condition")
  doc.metadata.memory_type |> should.equal(types.Bug)
  doc.metadata.status |> should.equal(Some(types.Open))
  doc.metadata.severity |> should.equal(Some(types.P1))
  doc.metadata.tags |> should.equal(["cook", "scheduler"])
  doc.metadata.source |> should.equal(types.Conversation)
}

pub fn parse_minimal_frontmatter_test() {
  let input =
    "---
type: memory
created: 2026-03-17
updated: 2026-03-17
source: conversation
---

# A Memory

Some content."

  let assert Ok(doc) = frontmatter.parse(input)
  doc.metadata.memory_type |> should.equal(types.Memory)
  doc.metadata.status |> should.equal(None)
  doc.metadata.severity |> should.equal(None)
  doc.metadata.tags |> should.equal([])
}

pub fn parse_no_frontmatter_test() {
  let input = "# Just a Note\n\nNo frontmatter here."
  let result = frontmatter.parse(input)
  result |> should.be_ok
}

pub fn parse_author_frontmatter_test() {
  let input =
    "---\ntype: bug\nstatus: open\nauthor: alex@example.com\ncreated: 2026-03-18\nupdated: 2026-03-18\nsource: conversation\n---\n\n# Test Bug\n\nSome content"
  let assert Ok(doc) = frontmatter.parse(input)
  doc.metadata.author
  |> should.equal("alex@example.com")
}

pub fn serialize_frontmatter_test() {
  let meta =
    types.Metadata(
      memory_type: types.Bug,
      status: Some(types.Open),
      severity: Some(types.P1),
      tags: ["cook", "scheduler"],
      created: "2026-03-17",
      updated: "2026-03-17",
      source: types.Conversation,
      vault_path: "Claude/bugs/test.md",
      schema_version: 1,
      author: "",
    )
  let output = frontmatter.serialize(meta, "Test Bug", "Some content")
  string.contains(output, "type: bug") |> should.be_true
  string.contains(output, "status: open") |> should.be_true
  string.contains(output, "# Test Bug") |> should.be_true
}

pub fn serialize_author_frontmatter_test() {
  let meta =
    types.Metadata(
      memory_type: types.Bug,
      status: option.Some(types.Open),
      severity: option.None,
      tags: [],
      created: "2026-03-18",
      updated: "2026-03-18",
      source: types.Conversation,
      vault_path: "",
      schema_version: 1,
      author: "alex@example.com",
    )
  let result = frontmatter.serialize(meta, "Test Bug", "Content")
  result |> string.contains("author: alex@example.com") |> should.be_true
}
