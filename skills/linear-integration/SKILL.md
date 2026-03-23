---
name: linear-integration
description: "Convention layer for Linear ticket management. Loaded by workflow skills via requires_skills to add ticket creation, status tracking, and project management at key workflow moments."
---

# Linear Integration — Convention Layer

This skill is loaded automatically by workflow skills that declare `requires_skills: [linear-integration]`. It teaches Claude when and how to use the Linear MCP tools for ticket management.

## Detection and Graceful Degradation

Before performing ANY Linear action, check availability:

1. **Check for `$LINEAR_TEAM` environment variable.** If not set, skip all Linear actions silently. Do not mention Linear, do not warn, do not suggest setup.
2. **If the configuration is present, attempt the first Linear MCP tool call.** If it fails (MCP server not connected, auth expired), note the failure internally and skip all remaining Linear actions for this session. Do not retry or prompt the user.

<IMPORTANT>
Linear integration is OPTIONAL. When unavailable, all workflow skills must work exactly as they did before this skill existed. Never block a workflow because Linear is unavailable.
</IMPORTANT>

## Configuration

These environment variables are set in `.claude/settings.json` under `env` and are available automatically:

| Variable | Purpose | Example |
|----------|---------|---------|
| `LINEAR_TEAM` | Team name for issue creation | `UI/UX` |
| `LINEAR_PROJECT` | Default project for issues | `Atlas` |

The issue prefix (e.g., `UI-123`) comes from the team automatically — no separate config needed.

## Status Mapping

| Workflow Event | Linear Status |
|----------------|---------------|
| Plan task created | `Todo` |
| Task picked up | `In Progress` |
| Task completed | `Done` |
| Bug discovered | New issue, `Backlog` |
| Work abandoned | `Canceled` |

## Issue Conventions

When creating Linear issues:

- **Title:** imperative, concise — matches commit message style (e.g., "Add pagination to activity feed")
- **Description:** include context from the design/plan. If a memory vault path exists for this item, add it as a cross-reference at the bottom: `Memory: Claude/bugs/rendering-bug.md`
- **Labels:** use work type labels (`bug`, `feature`, `refactor`) if they exist in Linear. If a label doesn't exist, skip it — don't attempt to create labels.
- **Priority:** default to `Medium` (3). Only use `Urgent` (1) or `High` (2) if the plan or user explicitly indicates urgency.
- **Assignee:** assign to the authenticated Linear user (the developer running Claude).

## Ticket Model

**One ticket per body of work, not per task.** Do not create micro-tickets for individual plan steps.

- `/ticket` creates a parent ticket through conversation
- Brainstorming creates one ticket (or sub-ticket under a parent if specified)
- Writing-plans and executing-plans work under the existing ticket — no new tickets
- Sub-tickets use Linear's `parentId` to create hierarchy:

```
UI-10: Build user dashboard        ← parent (created via /ticket)
  └── UI-11: Design activity feed  ← sub-ticket (created during brainstorm)
  └── UI-12: Add filtering         ← sub-ticket (created during another brainstorm)
```

The user explicitly specifies parent relationships (e.g., "this is under UI-10"). Do not auto-detect parents.

## Cross-Referencing (Memory + Linear)

Linear tracks the **ticket**. Memory tracks the **knowledge**. They are not mirrors.

When both systems have a record for the same thing:
- **Linear issue description** includes the memory vault path (e.g., `Memory: Claude/bugs/rendering-bug.md`)
- **Memory content** includes the Linear issue ID (e.g., `Linear: UI-47`)

Do not duplicate full content between systems.

## Workflow Actions by Skill

### During brainstorming (explore context step)
- Search Linear for issues related to the topic being brainstormed
- Surface any existing tickets to inform the design discussion

### During brainstorming (after design approval)
- Create one Linear ticket for this body of work
- If user specified a parent (e.g., "under UI-10"), create as sub-ticket with `parentId`
- Link the spec doc in the ticket description

### During executing-plans (plan lifecycle)
- **First task pickup:** read any comments on the ticket for teammate feedback, move to `In Progress`
- **All tasks complete:** move the ticket to `Done`
- **Discover bug:** create a new Linear issue with label `bug` + store in memory

### During /bugs add
- Create a Linear issue alongside the memory bug entry
- Link the memory vault path in the Linear issue description

### During /bugs resolve
- Move the corresponding Linear issue to `Done`

### During session-end
- Summarize which Linear tickets were created/moved during the session
- Include ticket IDs in the session summary stored to memory

### During finishing-a-development-branch (PR creation)
- Include Linear issue IDs in the PR description body
- Linear auto-links PRs when issue IDs appear in the body
