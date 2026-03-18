import gleam/option.{type Option}

// ---------- Domain types ----------

pub type MemoryType {
  Bug
  Decision
  Project
  Memory
  Pattern
  Session
  Reference
  Brainstorm
  Idea
}

pub type Status {
  Open
  Resolved
  Active
  Archived
  Wontfix
}

pub type Severity {
  P0
  P1
  P2
  P3
}

pub type Source {
  Conversation
  Vault
  Manual
}

// ---------- Record types ----------

pub type Metadata {
  Metadata(
    memory_type: MemoryType,
    status: Option(Status),
    severity: Option(Severity),
    tags: List(String),
    created: String,
    updated: String,
    source: Source,
    vault_path: String,
    schema_version: Int,
    author: String,
  )
}

pub type Chunk {
  Chunk(
    title: String,
    content: String,
    metadata: Metadata,
    chunk_index: Int,
    chunk_total: Int,
  )
}

pub type MemoryDocument {
  MemoryDocument(
    title: String,
    content: String,
    metadata: Metadata,
  )
}

pub type SearchResult {
  SearchResult(
    score: Float,
    title: String,
    content: String,
    metadata: Metadata,
  )
}

// ---------- Conversion functions ----------

pub fn memory_type_to_string(t: MemoryType) -> String {
  case t {
    Bug -> "bug"
    Decision -> "decision"
    Project -> "project"
    Memory -> "memory"
    Pattern -> "pattern"
    Session -> "session"
    Reference -> "reference"
    Brainstorm -> "brainstorm"
    Idea -> "idea"
  }
}

pub fn memory_type_from_string(s: String) -> Result(MemoryType, String) {
  case s {
    "bug" -> Ok(Bug)
    "decision" -> Ok(Decision)
    "project" -> Ok(Project)
    "memory" -> Ok(Memory)
    "pattern" -> Ok(Pattern)
    "session" -> Ok(Session)
    "reference" -> Ok(Reference)
    "brainstorm" -> Ok(Brainstorm)
    "idea" -> Ok(Idea)
    _ -> Error("Unknown memory type: " <> s)
  }
}

pub fn status_to_string(s: Status) -> String {
  case s {
    Open -> "open"
    Resolved -> "resolved"
    Active -> "active"
    Archived -> "archived"
    Wontfix -> "wontfix"
  }
}

pub fn status_from_string(s: String) -> Result(Status, String) {
  case s {
    "open" -> Ok(Open)
    "resolved" -> Ok(Resolved)
    "active" -> Ok(Active)
    "archived" -> Ok(Archived)
    "wontfix" -> Ok(Wontfix)
    _ -> Error("Unknown status: " <> s)
  }
}

pub fn severity_to_string(s: Severity) -> String {
  case s {
    P0 -> "p0"
    P1 -> "p1"
    P2 -> "p2"
    P3 -> "p3"
  }
}

pub fn source_to_string(s: Source) -> String {
  case s {
    Conversation -> "conversation"
    Vault -> "vault"
    Manual -> "manual"
  }
}

pub fn source_from_string(s: String) -> Result(Source, String) {
  case s {
    "conversation" -> Ok(Conversation)
    "vault" -> Ok(Vault)
    "manual" -> Ok(Manual)
    _ -> Error("Unknown source: " <> s)
  }
}

pub fn memory_type_to_dir(t: MemoryType) -> String {
  case t {
    Bug -> "bugs"
    Decision -> "decisions"
    Project -> "projects"
    Memory -> "memory"
    Pattern -> "patterns"
    Session -> "sessions"
    Reference -> "references"
    Brainstorm -> "brainstorms"
    Idea -> "ideas"
  }
}
