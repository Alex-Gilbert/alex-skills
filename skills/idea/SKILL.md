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
