---
name: vikunja-integration
description: "Convention layer for Vikunja kanban board management. Loaded by workflow skills via requires_skills to add self-hosted task tracking alongside semantic memory."
---

# Vikunja Integration — Convention Layer

This skill is loaded automatically by workflow skills that declare `requires_skills: [vikunja-integration]`. It teaches Claude when and how to use the Vikunja kanban board for task tracking.

## Detection and Graceful Degradation

Before performing ANY Vikunja action, check availability:

1. **Attempt `GET /projects` on the memory API.** If it returns 503, Vikunja is not configured. Skip all Vikunja actions silently. Do not mention Vikunja, do not warn, do not suggest setup.
2. **If the first call fails with a connection error,** note the failure internally and skip all remaining Vikunja actions for this session. Do not retry or prompt the user.

<IMPORTANT>
Vikunja integration is OPTIONAL. When unavailable, all workflow skills must work exactly as they did before this skill existed. Never block a workflow because Vikunja is unavailable.
</IMPORTANT>

## Tasks vs Memories

Vikunja and the memory vault serve different purposes:

| | Vikunja Tasks | Memory Vault |
|---|---|---|
| **Purpose** | Actionable work with a lifecycle | Knowledge capture and retrieval |
| **Has "done" state?** | Yes | No (has status: open/resolved/archived) |
| **Organized by** | Projects, kanban columns, priority | Type, tags, semantic search |
| **Examples** | "Add caching layer", "Fix login bug" | Decision records, patterns, session notes |

**Rule of thumb:** If it has a "done" state, it's a task. If it's knowledge worth remembering, it's a memory. Some things are both — create a task AND store a memory, cross-referencing each other.

## API Usage

All Vikunja operations go through the memory API (same base URL as `/memories`):

```bash
# List projects
curl -s http://localhost:7890/projects

# Create a project
curl -s -X POST http://localhost:7890/projects \
  -H 'Content-Type: application/json' \
  -d '{"title": "Sprint 12", "description": "Q2 work items"}'

# List tasks in a project
curl -s 'http://localhost:7890/tasks?project_id=1'

# Create a task
curl -s -X POST http://localhost:7890/tasks \
  -H 'Content-Type: application/json' \
  -d '{"project_id": 1, "title": "Implement caching layer", "description": "Add Redis caching for hot paths", "priority": 3}'

# Update a task (mark done)
curl -s -X PATCH http://localhost:7890/tasks/42 \
  -H 'Content-Type: application/json' \
  -d '{"project_id": 1, "done": true}'

# Update a task (change priority)
curl -s -X PATCH http://localhost:7890/tasks/42 \
  -H 'Content-Type: application/json' \
  -d '{"project_id": 1, "priority": 4}'
```

## Priority Mapping

| Value | Meaning |
|-------|---------|
| 0 | Unset |
| 1 | Low |
| 2 | Medium |
| 3 | High |
| 4 | Urgent |
| 5 | Do now |

Default to 0 (unset) unless the user or context indicates urgency.

## Cross-Referencing (Tasks + Memories)

Vikunja tracks the **work item**. Memory tracks the **knowledge**. They are not mirrors.

When both systems have a record for the same thing:
- **Task description** includes the memory vault path (e.g., `Memory: Claude/decisions/caching-strategy.md`)
- **Memory content** includes the Vikunja task ID (e.g., `Task: #42`)

Do not duplicate full content between systems.

## Vikunja Web UI

The kanban board is available at `http://localhost:3456` for visual management. The API and UI share the same backend — changes made via API appear in the UI and vice versa.

## Workflow Actions by Skill

### During brainstorming (after design approval)
- Create a Vikunja task for the body of work in the appropriate project
- Link any spec/design memory in the task description

### During executing-plans (plan lifecycle)
- Mark the task as in-progress (update description with progress notes)
- On completion, mark the task done

### During session-end
- Summarize which tasks were created/updated during the session
- Include task IDs in the session summary stored to memory
