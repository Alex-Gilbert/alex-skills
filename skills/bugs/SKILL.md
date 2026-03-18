---
name: bugs
description: "Bug tracking and management via semantic memory. Use when user invokes /bugs to list, filter, add, or resolve bugs."
---

# Bugs — Bug Management

Manage bugs stored in the semantic memory system.

## Subcommands

### `/bugs` (no args)
List all open bugs: call `memory_list` with `type=bug, status=open`.

### `/bugs <tag>`
List open bugs filtered by tag: call `memory_list` with `type=bug, status=open, tags=[tag]`.

### `/bugs resolve <query>`
1. Search for the bug: call `memory_find` with the query and `type=bug, status=open`
2. Present the top match and confirm with the user
3. Update status to resolved: call `memory_update` with `vault_path` and `status=resolved`

### `/bugs add <description>`
Create a new bug: call `memory_store` with `memory_type=bug, status=open`, determining title, severity, and tags from the description.

## Output Format

For each bug, show:
- **Title** and **severity** (p0-p3)
- **Tags**
- **Created date**
- **Vault path**
- **Content preview** (first 200 chars)
