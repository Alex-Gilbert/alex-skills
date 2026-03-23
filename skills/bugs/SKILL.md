---
name: bugs
description: "Bug tracking and management via semantic memory. Use when user invokes /bugs to list, filter, add, or resolve bugs."
requires_skills: [obsidian-markdown, linear-integration]
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
2. To see full details of a bug, read it using the path from search results:
   ```bash
   curl -s $MEMORY_API_URL/memories/<path>
   ```
3. Present the top match and confirm with the user
4. Update status to resolved:
   ```bash
   curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
     -X PATCH \
     -d '{"vault_path": "PATH", "status": "resolved"}' \
     $MEMORY_API_URL/memories
   ```
5. If Linear is available (per linear-integration skill) and the bug's memory content contains a Linear issue ID (`Linear: UI-XX`):
   - Move the corresponding Linear issue to `Done`

### `/bugs add <description>`
Create a new bug, determining title, severity, and tags from the description:
```bash
curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
  -d '{"title": "TITLE", "content": "DESCRIPTION", "memory_type": "bug", "status": "open", "severity": "SEVERITY", "tags": ["TAG"]}' \
  $MEMORY_API_URL/memories
```
If Linear is available (per linear-integration skill), also create a corresponding Linear issue:
- Use the same title and a summary of the description
- Set label to `bug` (if the label exists in Linear)
- Add the memory vault path to the Linear issue description: `Memory: <vault_path>`
- Add the Linear issue ID to the memory content: `Linear: <ISSUE-ID>` (e.g., `Linear: UI-47`)

## Output Format

For each bug, show:
- **Title** and **severity** (p0-p3)
- **Tags**
- **Created date**
- **Vault path**
- **Content preview** (first 200 chars)
- **Linear issue** (if cross-referenced in content)
