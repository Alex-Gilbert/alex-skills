---
name: ticket
description: "Create a Linear ticket through conversation. Use when user invokes /ticket to brainstorm and create a well-formed Linear issue."
requires_skills: [linear-integration]
---

# Ticket — Create a Linear Issue

Create a well-formed Linear ticket through natural conversation. Starts quick, goes deeper if the topic warrants it.

## Prerequisites

Check `$LINEAR_TEAM` is set. If not, tell the user: "Linear integration requires `LINEAR_TEAM` in `.claude/settings.json`. See the linear-integration skill for setup."

## The Process

### Phase 1: Quick Understanding (2-3 questions)

1. **What are you building/fixing?** — get the core idea in one sentence
2. **What type of work is this?** — feature, bug, refactor, chore (suggest based on description)
3. **How urgent is this?** — map to Linear priority (default Medium)

After these questions, draft a ticket:

```
Title: <imperative, concise>
Type: <feature/bug/refactor/chore>
Priority: <Urgent/High/Medium/Low>
Description: <2-3 sentences from what you've learned>
```

Ask: **"Does this capture it, or should we dig deeper?"**

### Phase 2: Go Deeper (if needed)

If the user wants more detail, ask follow-up questions **one at a time**:

- What does success look like? (acceptance criteria)
- What context would help someone picking this up? (background, constraints)
- Are there dependencies or blockers?
- Which project should this live under? (default: `$LINEAR_PROJECT`)

Update the draft with richer description and acceptance criteria.

### Phase 3: Create the Ticket

Once the user approves the draft:

1. Create the Linear issue using the MCP tools:
   - `team`: `$LINEAR_TEAM`
   - `project`: `$LINEAR_PROJECT` (or as specified)
   - `assignee`: `"me"`
   - `state`: `Backlog` (or `Todo` if the user is starting work now)
   - `labels`: based on work type (if the label exists in Linear)
2. If the user specified a parent ticket (e.g., "this is under UI-10"), set `parentId`
3. Report the created ticket ID and URL

### Creating Sub-Tickets

If the user says "under UI-XX" or "child of UI-XX", set the `parentId` on the new issue. This creates a sub-ticket hierarchy in Linear:

```
UI-10: Build user dashboard        ← parent
  └── UI-11: Design activity feed  ← sub-ticket (parentId: UI-10)
```

## Output

After creation, show:
```
Created <ISSUE-ID>: <title>
Priority: <priority> | Project: <project>
URL: <linear-url>
```

If it's a sub-ticket, also show: `Parent: <PARENT-ID>`
