# Linear Integration Design

## Overview

Integrate Linear ticket management into the alex-memory skill system so Claude can create, search, update, and complete Linear issues as part of the brainstorming → planning → execution workflow. Linear becomes a first-class citizen alongside the memory system — tracking work visibility for the team while memory tracks knowledge for Claude.

## Architecture: Convention Layer Skill

A new `linear-integration` skill acts as a **convention layer** loaded via `requires_skills` by any skill that participates in the work lifecycle. No server-side changes — this is entirely skills + Linear MCP + CLAUDE.md configuration.

### Integration Approach

- **Linear's official MCP server** provides the tools (create/update/search issues, manage projects, add comments)
- **The linear-integration skill** teaches Claude when and how to use those tools
- **Existing skills** declare `requires_skills: [linear-integration]` and get small additions at key workflow moments
- **CLAUDE.md env vars** configure which team/project to target, per-repo

## Configuration

### One-Time Setup (Per Developer)

```bash
claude mcp add --transport http linear-server https://mcp.linear.app/mcp
```

Then run `/mcp` in a Claude Code session to complete the OAuth flow.

### Per-Repo Setup (CLAUDE.md)

```
LINEAR_TEAM=Engineering
LINEAR_PROJECT=alex-memory
LINEAR_PREFIX=ENG
```

- `LINEAR_TEAM` — Linear team name for issue creation
- `LINEAR_PROJECT` — default project to associate issues with
- `LINEAR_PREFIX` — team prefix for ticket references (e.g., ENG-42)

### Graceful Degradation

If the Linear MCP server is not connected or CLAUDE.md lacks Linear vars, all Linear actions are **silently skipped**. Skills work exactly as they do today. No errors, no warnings. This enables:

- Teammates who haven't set up the MCP yet aren't blocked
- Personal repos without Linear config work normally
- Incremental adoption — add Linear to one repo at a time

**Detection mechanism:** The linear-integration skill teaches Claude to check for Linear availability in two steps:

1. **Check for env vars first.** If `LINEAR_TEAM` is not set in CLAUDE.md, skip all Linear actions immediately. This is the fast path for personal repos.
2. **If env vars exist, attempt the first Linear MCP tool call.** If it fails (MCP server not connected, auth expired), log the failure once and skip all remaining Linear actions for the session. Do not retry or prompt the user.

## Status Mapping

| Workflow Event | Linear Status |
|----------------|---------------|
| Plan task created | `Todo` |
| Task picked up by Claude | `In Progress` |
| Task completed | `Done` |
| Bug discovered | New issue, `Backlog` |
| Work abandoned | `Canceled` |

## Issue Conventions

- **Title:** imperative, concise (matches commit message style)
- **Description:** context from the design/plan, cross-reference to memory vault path if relevant
- **Labels:** derived from work type (bug, feature, refactor); if a label doesn't exist in Linear, skip it rather than attempting to create it
- **Priority:** default `Medium` (3) unless the plan indicates urgency; do not auto-map from task ordering
- **Assignee:** assign to the authenticated Linear user (the developer running Claude)

## Project Conventions

When brainstorming produces a new body of work:

1. Create a Linear project with the design title
2. Link the spec doc in the project description
3. Suggest updating `LINEAR_PROJECT` in CLAUDE.md if this becomes the primary project

## Dual-System Coordination (Memory + Linear)

Linear tracks the **ticket**. Memory tracks the **knowledge**. They are not mirrors.

| Event | Memory | Linear |
|-------|--------|--------|
| Bug discovered | Full bug with symptoms, reproduction, context | Issue with summary + link to memory |
| Design approved | Brainstorm + extracted decisions | Project created + link to spec |
| Plan task created | Plan doc in `docs/superpowers/plans/` | Issue created as `Todo` |
| Task completed | — (commit is the record) | Issue moved to `Done` |
| Teammate comments on ticket | — | Claude reads comment when picking up task |
| Session ends | Session summary with ticket IDs | — |
| Pattern discovered | Pattern stored to memory | — |

### Cross-Referencing

When both systems have a record for the same thing (e.g., a bug):

- Linear issue description includes the memory vault path
- Memory content includes the Linear issue ID (e.g., `ENG-47`)

Lightweight cross-references, not content duplication.

## Touchpoints — Where Linear Actions Happen

### session-start hook

The session-start hook is a bash script that injects context into the system prompt — it cannot call MCP tools directly. Instead, add **instructions** to the injected context telling Claude to search Linear at conversation start (same pattern used for memory search):

- If `LINEAR_TEAM` is configured, search Linear for user's in-progress and todo issues
- Surface alongside memory context
- Highlight tickets matching current repo's `LINEAR_PROJECT`

### brainstorming skill

- `requires_skills: [linear-integration]`
- **Explore context step:** search Linear for related issues before asking questions
- **After design approval:** create a Linear project (or use existing one), link spec doc in project description

### writing-plans skill

- `requires_skills: [linear-integration]`
- As each plan task is written, create a corresponding Linear issue under the project
- Issues created as `Todo`, ordered by plan sequence
- Plan doc annotated with Linear issue IDs (e.g., `ENG-42: Set up dashboard route`)

### executing-plans skill

- `requires_skills: [linear-integration]`
- Pick up a task → move its Linear issue to `In Progress`
- Complete a task → move its Linear issue to `Done`
- Discover a bug mid-task → create new Linear bug issue + store in memory

### bugs skill

- `requires_skills: [linear-integration]`
- Bug stored to memory → also create Linear issue with label `bug`
- Bug resolved in memory → also move Linear issue to `Done`
- Link memory vault path in Linear issue description

### session-end skill

- `requires_skills: [linear-integration]`
- Summarize which Linear tickets were moved/created during the session
- Include ticket IDs in session summary stored to memory

### finishing-a-development-branch skill

- `requires_skills: [linear-integration]`
- Reference Linear project/issues in PR description
- Linear auto-links PRs when issue IDs appear in branch name or PR body

## File Structure

### New Files

```
skills/linear-integration/SKILL.md
```

### Modified Files

| File | Change |
|------|--------|
| `skills/brainstorming/SKILL.md` | Add `requires_skills`, Linear search at explore step, project creation after approval |
| `skills/writing-plans/SKILL.md` | Add `requires_skills`, ticket creation as plan tasks are written |
| `skills/executing-plans/SKILL.md` | Add `requires_skills`, status transitions on task pickup/completion |
| `skills/bugs/SKILL.md` | Add `requires_skills`, Linear issue alongside memory storage |
| `skills/session-end/SKILL.md` | Add `requires_skills`, ticket summary in session output |
| `hooks/session-start` | Linear issue search alongside memory search |
| `skills/finishing-a-development-branch/SKILL.md` | Add `requires_skills`, ticket references in PR descriptions |

## Linear MCP Tools Available

The official Linear MCP server (`https://mcp.linear.app/mcp`) provides:

- Create/edit issues (title, team, description, priority, status, labels)
- Update issues (status, priority, description)
- Search issues (by query, team, status, assignee, labels, priority)
- Get user's issues (assigned, with filters)
- Add comments to issues (markdown)
- Create/edit projects
- Create/edit project milestones
- Create/edit project updates
- Manage project labels
- Create/edit initiatives
