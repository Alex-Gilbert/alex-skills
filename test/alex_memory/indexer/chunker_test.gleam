import alex_memory/indexer/chunker
import gleam/list
import gleeunit/should

pub fn single_section_no_split_test() {
  let content = "# Title\n\nSome short content here."
  let chunks = chunker.chunk(content, 512)
  list.length(chunks) |> should.equal(1)
  let assert [chunk] = chunks
  chunk.index |> should.equal(0)
  chunk.total |> should.equal(1)
}

pub fn split_on_h2_test() {
  let content =
    "# Title\n\nIntro paragraph.\n\n## Section A\n\nContent A.\n\n## Section B\n\nContent B."
  let chunks = chunker.chunk(content, 512)
  list.length(chunks) |> should.equal(3)
  // Chunk 0: intro, Chunk 1: Section A, Chunk 2: Section B
}

pub fn split_on_h3_test() {
  let content =
    "# Title\n\n## Section\n\n### Sub A\n\nContent A.\n\n### Sub B\n\nContent B."
  let chunks = chunker.chunk(content, 512)
  // Should split at ### boundaries
  list.length(chunks) |> should.not_equal(1)
}

pub fn chunk_indices_correct_test() {
  let content =
    "# Title\n\n## A\n\nContent A.\n\n## B\n\nContent B.\n\n## C\n\nContent C."
  let chunks = chunker.chunk(content, 512)
  let indices = list.map(chunks, fn(c) { c.index })
  let totals = list.map(chunks, fn(c) { c.total })
  // Indices should be 0, 1, 2, 3
  indices |> should.equal([0, 1, 2, 3])
  // All totals should be 4
  list.all(totals, fn(t) { t == 4 }) |> should.be_true
}
