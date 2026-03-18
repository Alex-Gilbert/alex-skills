---
name: status
description: "Project progress tracking via semantic memory. Use when user invokes /status to see active projects or project details."
---

# Status — Project Progress

Track project progress stored in the semantic memory system.

## Subcommands

### `/status` (no args)
List all active projects: call `memory_list` with `type=project, status=active`.

### `/status <project>`
Show details for a specific project: call `memory_find` with the project name/description and `type=project`.

## Output Format

For each project, show:
- **Title** and **status**
- **Tags**
- **Last updated**
- **Content** (full for single project, preview for list)
