---
name: bugs
description: "Bug tracking and management via semantic memory. Use when user invokes /bugs to list, filter, add, or resolve bugs."
requires_skills: [obsidian-markdown]
---

# Bugs — Bug Management

Manage bugs stored in the semantic memory system.

## Subcommands

### `/bugs` (no args)
List all open bugs:
```bash
curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
  "$MEMORY_API_URL/memories?type=bug&status=open"
```

### `/bugs <tag>`
List open bugs filtered by tag:
```bash
curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
  "$MEMORY_API_URL/memories?type=bug&status=open&tags=TAG"
```

### `/bugs resolve <query>`
1. Search for the bug:
   ```bash
   curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
     -d '{"query": "QUERY", "type": "bug", "status": "open"}' \
     $MEMORY_API_URL/memories/search
   ```
2. Present the top match and confirm with the user
3. Update status to resolved:
   ```bash
   curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
     -X PATCH \
     -d '{"vault_path": "PATH", "status": "resolved"}' \
     $MEMORY_API_URL/memories
   ```

### `/bugs add <description>`
Create a new bug, determining title, severity, and tags from the description:
```bash
curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
  -d '{"title": "TITLE", "content": "DESCRIPTION", "memory_type": "bug", "status": "open", "severity": "SEVERITY", "tags": ["TAG"]}' \
  $MEMORY_API_URL/memories
```

## Output Format

For each bug, show:
- **Title** and **severity** (p0-p3)
- **Tags**
- **Created date**
- **Vault path**
- **Content preview** (first 200 chars)
