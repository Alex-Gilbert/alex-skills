---
name: session-end
description: "Summarize and store session before ending. Use when user invokes /session-end or when wrapping up a conversation."
requires_skills: [obsidian-markdown, linear-integration]
---

# Session End — Summarize and Store

Summarize the current conversation and store key information to memory before ending.

## Process

1. **Summarize accomplishments** — what was done in this session
2. **Extract decisions** — any design or architecture decisions made → store each as `type=decision`
3. **Extract bugs** — any confirmed bugs identified → store each as `type=bug, status=open`
4. **Extract patterns** — any code patterns or conventions agreed upon → store each as `type=pattern`
5. **Store session summary** — store with `type=session`:
   ```bash
   curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
     -d '{"title": "TITLE", "content": "CONTENT", "memory_type": "session", "tags": ["TAG"]}' \
     $MEMORY_API_URL/memories
   ```
   Include in content:
   - What was accomplished
   - Key decisions made
   - Bugs found
   - What's next / open items
   - Tags for the relevant projects/areas
   - Linear tickets created or updated during this session (include issue IDs like `ENG-42`)

## Before Storing Each Item

Check for duplicates (>0.85 similarity threshold) to avoid near-duplicate entries:
```bash
curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
  -d '{"query": "CONTENT_SUMMARY", "limit": 5}' \
  $MEMORY_API_URL/memories/search
```
