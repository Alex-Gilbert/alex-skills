---
name: remember
description: "Store information to semantic memory. Use when user invokes /remember or when Claude identifies something worth storing (bug confirmed, correction received, pattern discovered)."
requires_skills: [obsidian-markdown]
---

# Remember — Store to Memory

Store information as a searchable memory in the Obsidian vault.

## Before Storing

1. **Determine memory type** from context:
   - `bug` — confirmed bug with symptoms and context
   - `decision` — design or architecture decision with reasoning
   - `project` — project progress, milestones, goals
   - `memory` — user preferences, corrections, learned behavior
   - `pattern` — code patterns and conventions
   - `session` — session summary (usually auto-generated)
   - `reference` — external links, docs, dashboards
   - `brainstorm` — brainstorm outputs, design specs
   - `idea` — raw ideas for later development

2. **Check for duplicates** — search for the content summary with a high similarity threshold:
   ```bash
   curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
     -d '{"query": "CONTENT_SUMMARY", "limit": 5}' \
     $MEMORY_API_URL/memories/search
   ```
   If a match scores >0.85, offer to update the existing memory instead of creating a new one.

3. **Determine metadata:**
   - `status`: open/active/resolved as appropriate
   - `severity`: p0-p3 for bugs only
   - `tags`: relevant project/topic tags

## Storing

Store the memory:
```bash
curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
  -d '{"title": "TITLE", "content": "CONTENT", "memory_type": "TYPE", "status": "STATUS", "severity": "SEVERITY", "tags": ["TAG"]}' \
  $MEMORY_API_URL/memories
```
- `title`: concise, descriptive title
- `content`: full content in markdown
- `memory_type`: determined type
- `status`, `severity`, `tags` as appropriate

Report the vault path where the memory was saved.
