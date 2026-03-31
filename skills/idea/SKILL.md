---
name: idea
description: "Quick idea capture to semantic memory. Use when user invokes /idea."
requires_skills: [obsidian-markdown]
---

# Idea — Quick Capture

Capture an idea to semantic memory with minimal friction. Speed is the priority.

## Flow

1. **Get the idea** — If the user typed it inline (e.g., `/idea what if we added X`), use that. Otherwise ask: "What's the idea?"
2. **Gather context silently** (no extra prompts to the user):
   - Note the current working directory and project name
   - Search for near-duplicates (threshold enforced client-side, not by the API):
     ```bash
     curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
       -d '{"query": "IDEA_TEXT", "type": "idea", "limit": 5}' \
       $MEMORY_API_URL/memories/search
     ```
     Discard results with score below 0.85.
   - If near-duplicates found (score >= 0.85), surface them: "This looks similar to [existing idea title] — still want to capture it?" If the user says yes or there are no duplicates, continue.
3. **Store** — Create the idea:
   ```bash
   curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
     -d '{"title": "TITLE", "content": "IDEA_TEXT\n\n**Project context:** PROJECT_NAME (WORKING_DIR)", "memory_type": "idea", "status": "open", "tags": ["PROJECT_NAME"]}' \
     $MEMORY_API_URL/memories
   ```
4. **Confirm** — "Stored. Use `/shape` when you want to develop it further."

## Design Constraints

- No clarifying questions beyond the initial "What's the idea?" if not provided inline
- No analysis, evaluation, or brainstorming
- No follow-up questions about tags, priority, or metadata — infer what you can silently
- The entire interaction should take under 30 seconds
