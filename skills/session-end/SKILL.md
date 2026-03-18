---
name: session-end
description: "Summarize and store session before ending. Use when user invokes /session-end or when wrapping up a conversation."
requires_skills: [obsidian-markdown]
---

# Session End — Summarize and Store

Summarize the current conversation and store key information to memory before ending.

## Process

1. **Summarize accomplishments** — what was done in this session
2. **Extract decisions** — any design or architecture decisions made → store each as `type=decision`
3. **Extract bugs** — any confirmed bugs identified → store each as `type=bug, status=open`
4. **Extract patterns** — any code patterns or conventions agreed upon → store each as `type=pattern`
5. **Store session summary** — call `memory_store` with `type=session`, including:
   - What was accomplished
   - Key decisions made
   - Bugs found
   - What's next / open items
   - Tags for the relevant projects/areas

## Before Storing Each Item

Check for duplicates with `memory_find` (>0.85 similarity threshold) to avoid near-duplicate entries.
