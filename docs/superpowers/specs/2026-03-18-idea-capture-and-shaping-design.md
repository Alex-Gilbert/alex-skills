# Idea Capture and Shaping — Design Specification

**Date:** 2026-03-18
**Status:** Approved

## Overview

Adds an idea capture and refinement pipeline to the alex-memory system. Three changes: a new `idea` memory type, a `/idea` skill for quick capture, and a `/shape` skill for lightweight refinement. Also modifies the existing brainstorming skill to enforce spec-to-vault storage and accept stored ideas as input.

The pipeline creates a progression: raw idea → shaped idea → full spec → implementation plan.

## Goals

- Capture ideas with minimal friction (under 30 seconds)
- Provide a lightweight refinement step between raw capture and full brainstorming
- Track idea lifecycle through status: `open` (raw) → `active` (shaped) → `archived` (specced)
- Ensure specs produced by brainstorming are always vectorized in the vault
- Connect the full pipeline so ideas flow naturally through to implementation

## New Memory Type: `idea`

Add `Idea` variant to `MemoryType` in `types.gleam` with directory mapping `ideas/`.

**Code changes:**
- `types.gleam`: Add `Idea` to `MemoryType`, update `memory_type_to_string`, `memory_type_from_string`, `memory_type_to_dir`
- `server.gleam`: Add `"idea"` to the `memory_type` enum in `store_schema()`, `find_schema()`, and `list_schema()`
- `vault_writer.gleam`: No changes needed (already uses `memory_type_to_dir`)

**Status convention for ideas (no new enum values):**
- `open` = raw, just captured via `/idea`
- `active` = shaped, been through `/shape`
- `archived` = specced, full brainstorm produced a spec

**Vault path:** `~/alex-vault/Claude/ideas/<slug>.md`

**Example vault file:**
```markdown
---
type: idea
status: open
tags: [alex-memory]
author: alex@greystone
created: 2026-03-18
updated: 2026-03-18
source: conversation
---

# CLI Dashboard for Memory Stats

What if we had a terminal dashboard showing memory counts by type,
recent activity, and search hit rates? Would help see if the system
is actually being used.

**Project context:** alex-memory (~/dev/alex-memory)
```

## `/idea` Skill — Quick Capture

**Trigger:** User types `/idea` or Claude detects idea capture intent.

**Skill file:** `skills/idea/SKILL.md`

**Flow:**
1. If the user typed their idea inline (e.g., `/idea what if we added a CLI dashboard`), skip to step 3
2. Otherwise, ask: "What's the idea?" — single prompt, no follow-ups
3. Context gathering (automatic, no extra prompts):
   - Detect current working directory / project
   - Call `memory_find` with the idea text as query, filtered to `type=idea`. Client-side, discard results with score below 0.85 (the threshold is enforced by the skill, not the API).
   - If near-duplicates found, surface them: "This looks similar to [existing idea] — still want to capture it?"
4. Store to vault via `memory_store`:
   - `title`: extracted from the idea text
   - `content`: raw idea + auto-detected project context
   - `memory_type`: `idea`
   - `status`: `open`
   - `tags`: current project name at minimum
5. Confirm: "Stored. Use `/shape` when you want to develop it further."

**Design constraints:**
- No clarifying questions beyond the initial prompt
- No analysis or evaluation
- No brainstorming
- Speed is the priority — friction kills idea capture

## `/shape` Skill — Lightweight Idea Refinement

**Trigger:** User types `/shape` or `/shape <topic>`.

**Skill file:** `skills/shape/SKILL.md`

**Entry points:**
- `/shape` with no args → list open ideas via `memory_list(type=idea, status=open)`, present the list, user picks one
- `/shape <query>` → search vault for matching idea, or if no match, start shaping a fresh concept

**Flow:**
1. Load the idea (from vault or fresh input)
2. Offer visual companion (own message, no other content) — same pattern as brainstorming skill. If accepted, read the guide at `skills/brainstorming/visual-companion.md` before proceeding. If declined, text-only shaping.
3. Challenge the idea with questions, one at a time (guideline: 3-5, but adapt to the idea's complexity). Examples:
   - "What problem does this actually solve?"
   - "Who benefits and how would they use it?"
   - "What's the simplest version that delivers value?"
   - "What could go wrong or make this harder than it looks?"
   - Per-question decision on visual vs. terminal — same rule as brainstorming: "would the user understand this better by seeing it than reading it?"
4. After each answer, push back, surface tensions, ask for clarification where warranted
5. Synthesize into a shaped idea: problem statement, proposed approach, open questions, risks identified
6. Update vault entry via `memory_update`: new content with shaped version, status → `active`, preserve original raw idea in a "## Original Idea" section
7. Confirm: "Idea shaped. Use the brainstorming skill when you're ready to turn this into a spec."

**Edge cases:**
- If `/shape` is called on an already-shaped idea (`active` status), re-shape it — update the content and keep status as `active`. No warning needed; refining a shaped idea further is valid.

**Design constraints:**
- No approaches/trade-offs analysis (that's brainstorming)
- No spec output
- No implementation planning

## Brainstorming Skill Modifications

Two additive changes to the existing brainstorming skill:

### Enforced spec-to-vault storage

Wrap existing step 6.5 in a `<HARD-GATE>` tag (matching the pattern at the top of the brainstorming skill). The content stays the same — store full design as `type=brainstorm`, extract key decisions as `type=decision` — but the gate prevents invoking writing-plans until storage is confirmed.

Dual-write remains: spec file to `docs/superpowers/specs/`, vault copy as `type=brainstorm`.

### Accept stored ideas as starting input

Add to the "Understanding the idea" phase: if the user references a stored idea (by name or via `/shape` output), pull it from the vault via `memory_find(type=idea)` and use it as starting context. When the brainstorm completes and a spec is produced, update the idea's status to `archived`.

## Full Pipeline

```
/idea (capture, status=open)
  → /shape (refine, status=active)
    → brainstorming (full spec, status=archived)
      → writing-plans → implementation
```

Each stage is optional — you can jump straight from `/idea` to brainstorming, or start brainstorming without a stored idea. The pipeline is a natural progression, not a forced sequence.

## Skill Registry Updates

Update the `using-superpowers` skill's Memory Skills table to include `/idea` and `/shape` so Claude discovers and invokes them.

## Not In Scope

- No new status enum values (reusing existing `open`, `active`, `archived`)
- No file watching changes
- No changes to the vectorization pipeline (handles new types automatically once added to the enum)
- No changes to other skills beyond brainstorming
