---
name: status
description: "Project progress tracking via semantic memory. Use when user invokes /status to see active projects or project details."
---

# Status — Project Progress

Track project progress stored in the semantic memory system.

## Subcommands

### `/status` (no args)
List all active projects:
```bash
curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
  "$MEMORY_API_URL/memories?type=project&status=active"
```

### `/status <project>`
Show details for a specific project:
```bash
curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
  -d '{"query": "PROJECT_NAME", "type": "project"}' \
  $MEMORY_API_URL/memories/search
```

## Output Format

For each project, show:
- **Title** and **status**
- **Tags**
- **Last updated**
- **Content** (full for single project, preview for list)
