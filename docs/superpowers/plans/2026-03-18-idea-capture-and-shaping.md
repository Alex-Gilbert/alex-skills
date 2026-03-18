# Idea Capture and Shaping Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add idea capture and shaping pipeline — new `idea` memory type, `/idea` quick-capture skill, `/shape` refinement skill, and brainstorming skill modifications.

**Architecture:** Extends the existing memory type system with `Idea`, adds two new skills as markdown files, and modifies the brainstorming skill to enforce vault storage and accept ideas as input. No new infrastructure — uses existing MCP tools, vault writer, and embedder.

**Tech Stack:** Gleam (types + MCP server), Markdown (skills), existing Qdrant + Ollama pipeline

**Spec:** `docs/superpowers/specs/2026-03-18-idea-capture-and-shaping-design.md`

---

## Chunk 1: Gleam Code Changes

### Task 1: Add `Idea` to MemoryType enum and conversion functions

**Files:**
- Modify: `src/alex_memory/types.gleam:5-14` (enum), `:83-94` (to_string), `:96-108` (from_string), `:157-168` (to_dir)
- Test: `test/alex_memory/types_test.gleam`

- [ ] **Step 1: Write the failing test**

Add to `test/alex_memory/types_test.gleam`:

```gleam
pub fn idea_type_roundtrip_test() {
  types.memory_type_to_string(types.Idea) |> should.equal("idea")
  types.memory_type_from_string("idea") |> should.equal(Ok(types.Idea))
  types.memory_type_to_dir(types.Idea) |> should.equal("ideas")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `gleam test -- --filter idea_type_roundtrip`
Expected: FAIL — compile error, `Idea` variant does not exist

- [ ] **Step 3: Add Idea variant to MemoryType enum**

In `src/alex_memory/types.gleam`, add `Idea` after `Brainstorm` in the `MemoryType` type:

```gleam
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
```

- [ ] **Step 4: Add Idea to memory_type_to_string**

In `memory_type_to_string()`, add case:

```gleam
    Idea -> "idea"
```

- [ ] **Step 5: Add Idea to memory_type_from_string**

In `memory_type_from_string()`, add case before the catch-all:

```gleam
    "idea" -> Ok(Idea)
```

- [ ] **Step 6: Add Idea to memory_type_to_dir**

In `memory_type_to_dir()`, add case:

```gleam
    Idea -> "ideas"
```

- [ ] **Step 7: Run test to verify it passes**

Run: `gleam test -- --filter idea_type_roundtrip`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add src/alex_memory/types.gleam test/alex_memory/types_test.gleam
git commit -m "feat: add Idea variant to MemoryType enum"
```

---

### Task 2: Add `"idea"` to MCP server schema enums

**Files:**
- Modify: `src/alex_memory/mcp/server.gleam:561-583` (three schema functions)

- [ ] **Step 1: Update store_schema()**

In `src/alex_memory/mcp/server.gleam` line 564, in the JSON string for `store_schema()`, change the `memory_type` enum from:

```
"enum":["bug","decision","project","memory","pattern","session","reference","brainstorm"]
```

to:

```
"enum":["bug","decision","project","memory","pattern","session","reference","brainstorm","idea"]
```

Also update the description string to include `idea`:

```
"description":"Type of memory: bug, decision, project, memory, pattern, session, reference, brainstorm, idea"
```

- [ ] **Step 2: Update find_schema()**

In line 572, update the `type` enum in the JSON string from:

```
"enum":["bug","decision","project","memory","pattern","session","reference","brainstorm"]
```

to:

```
"enum":["bug","decision","project","memory","pattern","session","reference","brainstorm","idea"]
```

- [ ] **Step 3: Update list_schema()**

In line 580, same change — add `"idea"` to the `type` enum array.

- [ ] **Step 4: Run full test suite**

Run: `gleam test`
Expected: All tests pass (no behavior change, just schema metadata)

- [ ] **Step 5: Commit**

```bash
git add src/alex_memory/mcp/server.gleam
git commit -m "feat: add idea to MCP tool schema enums"
```

---

## Chunk 2: New Skills

### Task 3: Create `/idea` skill

**Files:**
- Create: `skills/idea/SKILL.md`

- [ ] **Step 1: Create skill directory**

```bash
mkdir -p skills/idea
```

- [ ] **Step 2: Write SKILL.md**

Create `skills/idea/SKILL.md`:

```markdown
---
name: idea
description: "Quick idea capture to semantic memory. Use when user invokes /idea or expresses a raw idea worth capturing."
---

# Idea — Quick Capture

Capture an idea to semantic memory with minimal friction. Speed is the priority.

## Flow

1. **Get the idea** — If the user typed it inline (e.g., `/idea what if we added X`), use that. Otherwise ask: "What's the idea?"
2. **Gather context silently** (no extra prompts to the user):
   - Note the current working directory and project name
   - Call `memory_find` with the idea text as query, filtered to `type=idea`. Discard results with score below 0.85 (threshold enforced client-side, not by the API).
   - If near-duplicates found (score >= 0.85), surface them: "This looks similar to [existing idea title] — still want to capture it?" If the user says yes or there are no duplicates, continue.
3. **Store** — Call `memory_store`:
   - `title`: concise title extracted from the idea text
   - `content`: the raw idea text, followed by a `**Project context:**` line with the project name and working directory
   - `memory_type`: `idea`
   - `status`: `open`
   - `tags`: current project name at minimum
4. **Confirm** — "Stored. Use `/shape` when you want to develop it further."

## Design Constraints

- No clarifying questions beyond the initial "What's the idea?" if not provided inline
- No analysis, evaluation, or brainstorming
- No follow-up questions about tags, priority, or metadata — infer what you can silently
- The entire interaction should take under 30 seconds
```

- [ ] **Step 3: Commit**

```bash
git add skills/idea/SKILL.md
git commit -m "feat: add /idea skill for quick idea capture"
```

---

### Task 4: Create `/shape` skill

**Files:**
- Create: `skills/shape/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

Create `skills/shape/SKILL.md`:

```markdown
---
name: shape
description: "Lightweight idea refinement through focused questioning. Use when user invokes /shape to challenge and refine a captured idea."
---

# Shape — Lightweight Idea Refinement

Challenge and refine an idea into something actionable through focused questioning. Lighter than brainstorming — no spec output, no approaches analysis. The goal is to stress-test the idea and sharpen it.

## Entry Points

- `/shape` with no args — call `memory_list(type=idea, status=open)` to list open ideas. Present the list and let the user pick one.
- `/shape <query>` — call `memory_find` with the query filtered to `type=idea`. If a match is found, use it. If no match, start shaping the query as a fresh concept.

## Flow

1. **Load the idea** — from vault or fresh input. Display it back to the user so you're both starting from the same place.
2. **Offer visual companion** (this is its own message, no other content):
   > "Some of what we're working on might be easier to explain if I can show it to you in a web browser. I can put together mockups, diagrams, comparisons, and other visuals as we go. This feature is still new and can be token-intensive. Want to try it? (Requires opening a local URL)"
   If accepted, read the guide at `skills/brainstorming/visual-companion.md` before proceeding. If declined, text-only shaping. Per-question, decide visual vs. terminal: "would the user understand this better by seeing it than reading it?"
3. **Challenge the idea** — ask questions one at a time (guideline: 3-5, adapt to complexity). Examples:
   - "What problem does this actually solve?"
   - "Who benefits and how would they use it?"
   - "What's the simplest version that delivers value?"
   - "What could go wrong or make this harder than it looks?"
   After each answer, push back where warranted. Surface tensions ("you said X but that conflicts with Y"), challenge assumptions, ask for clarification.
4. **Synthesize** — produce a shaped version of the idea with:
   - **Problem statement** — what this solves and for whom
   - **Proposed approach** — high-level direction, not a spec
   - **Open questions** — things still unresolved
   - **Risks** — what could go wrong
   Present this to the user for approval.
5. **Update vault** — call `memory_update` on the idea's vault path:
   - `content`: the shaped version, with the original raw idea preserved in a `## Original Idea` section at the bottom
   - `status`: `active`
6. **Confirm** — "Idea shaped. Use the brainstorming skill when you're ready to turn this into a spec."

## Edge Cases

- If called on an already-shaped idea (`active` status): re-shape it. Update content, keep status as `active`. Refining further is valid.
- If called on an archived idea (`archived` status): warn that this idea already has a spec, ask if the user wants to re-open it.

## Design Constraints

- No approaches/trade-offs analysis (that's brainstorming)
- No spec output
- No implementation planning
- One question at a time — do not overwhelm
```

- [ ] **Step 2: Commit**

```bash
git add skills/shape/SKILL.md
git commit -m "feat: add /shape skill for lightweight idea refinement"
```

---

### Task 5: Create command files for `/idea` and `/shape`

**Files:**
- Create: `commands/idea.md`
- Create: `commands/shape.md`

- [ ] **Step 1: Write idea command file**

Create `commands/idea.md`:

```markdown
---
description: "Quick idea capture to semantic memory"
---

Invoke the superpowers:idea skill to capture this idea.
```

- [ ] **Step 2: Write shape command file**

Create `commands/shape.md`:

```markdown
---
description: "Lightweight idea refinement through focused questioning"
---

Invoke the superpowers:shape skill to shape this idea.
```

- [ ] **Step 3: Commit**

```bash
git add commands/idea.md commands/shape.md
git commit -m "feat: add /idea and /shape command files"
```

---

## Chunk 3: Skill Modifications

### Task 6: Modify brainstorming skill — enforce spec storage and accept ideas

**Files:**
- Modify: `skills/brainstorming/SKILL.md:32-34` (step 6.5), `:68-76` (Understanding the idea)

- [ ] **Step 1: Wrap step 6.5 in HARD-GATE**

In `skills/brainstorming/SKILL.md`, replace lines 32-34:

```markdown
6.5. **Store to memory** — After writing and committing the design doc:
   - Call memory_store with type=brainstorm for the full design
   - Extract each key decision and call memory_store with type=decision for each
```

with:

```markdown
6.5. **Store to memory** — After writing and committing the design doc:
<HARD-GATE>
Do NOT invoke writing-plans until BOTH of these are confirmed complete:
- Call memory_store with type=brainstorm for the full design
- Extract each key decision and call memory_store with type=decision for each
If the user started from a stored idea (type=idea), also call memory_update to set the idea's status to `archived`.
</HARD-GATE>
```

- [ ] **Step 2: Add idea-loading to "Understanding the idea" section**

In the "Understanding the idea" section (after line 70), add a new bullet after "Check out the current project state first":

```markdown
- If the user references a stored idea or came from `/shape`, pull it from the vault via `memory_find(type=idea)` and use it as starting context. Display the idea (and its shaped version if status is `active`) so both parties start aligned.
```

- [ ] **Step 3: Commit**

```bash
git add skills/brainstorming/SKILL.md
git commit -m "feat: brainstorming enforces spec-to-vault storage, accepts stored ideas"
```

---

### Task 7: Update using-superpowers skill registry

**Files:**
- Modify: `skills/using-superpowers/SKILL.md:119-125` (Memory Skills table)

- [ ] **Step 1: Add idea and shape to the Memory Skills table**

In `skills/using-superpowers/SKILL.md`, update the Memory Skills table (after line 125) to add two rows:

```markdown
| Skill | Purpose |
|-------|---------|
| `remember` | Store information to semantic memory |
| `recall` | Search semantic memory for relevant context |
| `bugs` | Bug tracking and management |
| `status` | Project progress tracking |
| `session-end` | Summarize and store session before ending |
| `idea` | Quick idea capture to semantic memory |
| `shape` | Lightweight idea refinement through questioning |
```

- [ ] **Step 2: Commit**

```bash
git add skills/using-superpowers/SKILL.md
git commit -m "feat: register /idea and /shape in using-superpowers skill"
```

---

### Task 8: Final verification

- [ ] **Step 1: Run full Gleam test suite**

Run: `gleam test`
Expected: All tests pass

- [ ] **Step 2: Verify skill files are well-formed**

Run: `head -5 skills/idea/SKILL.md skills/shape/SKILL.md commands/idea.md commands/shape.md`
Expected: Each file has correct header/frontmatter

- [ ] **Step 3: Verify the pipeline narrative reads correctly**

Read through in order:
1. `skills/idea/SKILL.md` — captures ideas as `type=idea, status=open`
2. `skills/shape/SKILL.md` — refines to `status=active`
3. `skills/brainstorming/SKILL.md` — step 6.5 archives idea to `status=archived`

Confirm status lifecycle is consistent across all three skills.

- [ ] **Step 4: Final commit if any fixups needed**

```bash
git add -A
git commit -m "fix: address verification findings"
```

(Skip if no changes needed.)
