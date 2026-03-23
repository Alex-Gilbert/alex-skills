# Linear Integration Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Linear ticket management as a convention layer skill, woven into the brainstorming → planning → execution workflow via `requires_skills`.

**Architecture:** A single new skill (`skills/linear-integration/SKILL.md`) teaches Claude when and how to use Linear MCP tools. Seven existing skills get small additions declaring the dependency and adding Linear actions at key workflow moments. The session-start hook gets instructions for Linear context at conversation start.

**Tech Stack:** Linear MCP server (official, remote), Claude Code skills system (markdown), bash (hook)

**Spec:** `docs/superpowers/specs/2026-03-23-linear-integration-design.md`

---

## Chunk 1: Foundation

### Task 1: Create the linear-integration convention layer skill

**Files:**
- Create: `skills/linear-integration/SKILL.md`

- [ ] **Step 1: Write the skill file**

```markdown
---
name: linear-integration
description: "Convention layer for Linear ticket management. Loaded by workflow skills via requires_skills to add ticket creation, status tracking, and project management at key workflow moments."
---

# Linear Integration — Convention Layer

This skill is loaded automatically by workflow skills that declare `requires_skills: [linear-integration]`. It teaches Claude when and how to use the Linear MCP tools for ticket management.

## Detection and Graceful Degradation

Before performing ANY Linear action, check availability:

1. **Check for `LINEAR_TEAM` in CLAUDE.md.** If not set, skip all Linear actions silently. Do not mention Linear, do not warn, do not suggest setup.
2. **If env vars exist, attempt the first Linear MCP tool call.** If it fails (MCP server not connected, auth expired), note the failure internally and skip all remaining Linear actions for this session. Do not retry or prompt the user.

<IMPORTANT>
Linear integration is OPTIONAL. When unavailable, all workflow skills must work exactly as they did before this skill existed. Never block a workflow because Linear is unavailable.
</IMPORTANT>

## Configuration

Read these from CLAUDE.md:

| Variable | Purpose | Example |
|----------|---------|---------|
| `LINEAR_TEAM` | Team name for issue creation | `Engineering` |
| `LINEAR_PROJECT` | Default project for issues | `alex-memory` |
| `LINEAR_PREFIX` | Team prefix for ticket references | `ENG` |

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

## Project Conventions

When brainstorming produces a new body of work:

1. Search Linear for an existing project matching the design title or `LINEAR_PROJECT`
2. If no match, create a new Linear project with the design title
3. Link the spec doc path in the project description
4. Suggest updating `LINEAR_PROJECT` in CLAUDE.md if this becomes the primary project for the repo

## Cross-Referencing (Memory + Linear)

Linear tracks the **ticket**. Memory tracks the **knowledge**. They are not mirrors.

When both systems have a record for the same thing:
- **Linear issue description** includes the memory vault path (e.g., `Memory: Claude/bugs/rendering-bug.md`)
- **Memory content** includes the Linear issue ID (e.g., `Linear: ENG-47`)

Do not duplicate full content between systems.

## Workflow Actions by Skill

### During brainstorming (explore context step)
- Search Linear for issues related to the topic being brainstormed
- Surface any existing tickets to inform the design discussion

### During brainstorming (after design approval)
- Create or find a Linear project for this body of work
- Link the spec doc in the project description

### During writing-plans (as tasks are defined)
- Create a Linear issue for each plan task, status `Todo`
- Annotate the plan doc with issue IDs (e.g., `ENG-42: Set up dashboard route`)

### During executing-plans (task lifecycle)
- **Pick up task:** read any comments on the Linear issue for teammate feedback, then move to `In Progress`
- **Complete task:** move Linear issue to `Done`
- **Discover bug:** create new Linear issue with label `bug` + store in memory

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
```

- [ ] **Step 2: Verify the file was created correctly**

Run: `head -5 skills/linear-integration/SKILL.md`
Expected: frontmatter with name: linear-integration

- [ ] **Step 3: Commit**

```bash
git add skills/linear-integration/SKILL.md
git commit -m "feat: add linear-integration convention layer skill"
```

---

### Task 2: Update session-start hook with Linear context

**Files:**
- Modify: `hooks/session-start` (lines 36-40)

The session-start hook is a bash script that injects context into the system prompt. It cannot call MCP tools directly. Add instructions telling Claude to search Linear at conversation start, matching the pattern used for memory context.

- [ ] **Step 1: Add Linear context block after the memory context**

After line 38 (`memory_escaped=$(escape_for_json "$memory_context")`), add a new `linear_context` variable and its escaped version.

Then modify line 40 to include the linear context in `session_context`.

The new `linear_context` block:

```bash
# Linear integration context
linear_context="When Linear MCP is available and LINEAR_TEAM is set in CLAUDE.md, you MUST:\n- Search Linear for your in-progress and todo issues at conversation start\n- Highlight tickets matching the current repo's LINEAR_PROJECT\n- Surface Linear context alongside memory context\n\nLinear is accessed via MCP tools (not curl). The Linear MCP server provides tools for:\n- Searching issues (by query, team, status, assignee, labels, priority)\n- Getting user's assigned issues\n- Creating and editing issues, projects, milestones, and comments\n- Updating issue status, priority, and other fields\n\nLinear configuration is in CLAUDE.md:\n- LINEAR_TEAM: team name for issue creation\n- LINEAR_PROJECT: default project for issues\n- LINEAR_PREFIX: team prefix for ticket references (e.g., ENG-42)\n\nIf LINEAR_TEAM is not set, skip all Linear actions silently."
linear_escaped=$(escape_for_json "$linear_context")
```

Update the `session_context` line to include `${linear_escaped}`:

```bash
session_context="<EXTREMELY_IMPORTANT>\nYou have superpowers.\n\n**Below is the full content of your 'superpowers:using-superpowers' skill - your introduction to using skills. For all other skills, use the 'Skill' tool:**\n\n${using_superpowers_escaped}\n\n${memory_escaped}\n\n${linear_escaped}\n\n${warning_escaped}\n</EXTREMELY_IMPORTANT>"
```

- [ ] **Step 2: Verify the hook still produces valid JSON**

Run: `bash hooks/session-start 2>&1 | python3 -m json.tool > /dev/null && echo "Valid JSON"`
Expected: "Valid JSON"

- [ ] **Step 3: Commit**

```bash
git add hooks/session-start
git commit -m "feat: add Linear context injection to session-start hook"
```

---

## Chunk 2: Workflow Skill Modifications

### Task 3: Update brainstorming skill

**Files:**
- Modify: `skills/brainstorming/SKILL.md`

Three changes: (1) add `linear-integration` to `requires_skills`, (2) add Linear search at explore context step, (3) add project creation after design approval.

- [ ] **Step 1: Update frontmatter**

Change line 4 from:
```yaml
requires_skills: [obsidian-markdown]
```
to:
```yaml
requires_skills: [obsidian-markdown, linear-integration]
```

- [ ] **Step 2: Add Linear search to the explore context step**

After line 36 (the `$MEMORY_API_URL/memories?type=pattern"` closing), add:

```markdown
   If Linear is available (per linear-integration skill), also search Linear for related issues:
   - Search for issues related to the topic being brainstormed
   - Surface any existing tickets that might inform the design
```

- [ ] **Step 3: Add Linear project creation to the store-to-memory section**

After line 63 (the PATCH command for archiving ideas, before `</HARD-GATE>`), add:

```markdown
- If Linear is available, create or find a Linear project for this body of work:
  - Search for existing project matching the design title or `LINEAR_PROJECT`
  - If none exists, create a new project with the design title
  - Link the spec doc path in the project description
```

- [ ] **Step 4: Verify frontmatter is valid**

Run: `head -5 skills/brainstorming/SKILL.md`
Expected: `requires_skills: [obsidian-markdown, linear-integration]`

- [ ] **Step 5: Commit**

```bash
git add skills/brainstorming/SKILL.md
git commit -m "feat: add Linear integration to brainstorming skill"
```

---

### Task 4: Update writing-plans skill

**Files:**
- Modify: `skills/writing-plans/SKILL.md`

Two changes: (1) add `requires_skills`, (2) add ticket creation instructions.

- [ ] **Step 1: Update frontmatter**

Change lines 1-4 from:
```yaml
---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
---
```
to:
```yaml
---
name: writing-plans
description: Use when you have a spec or requirements for a multi-step task, before touching code
requires_skills: [linear-integration]
---
```

- [ ] **Step 2: Add Linear ticket creation to the Execution Handoff section**

Before the line `**"Plan complete and saved to...` (in the Execution Handoff section), add:

```markdown
**Linear ticket creation:** If Linear is available (per linear-integration skill), after saving the plan:
- Create a Linear issue for each task, status `Todo`, under the `LINEAR_PROJECT`
- Annotate each task heading in the plan doc with the Linear issue ID (e.g., `### Task 1: Set up dashboard route [ENG-42]`)
- Issues should have titles matching the task names, descriptions referencing the plan doc path
```

- [ ] **Step 3: Commit**

```bash
git add skills/writing-plans/SKILL.md
git commit -m "feat: add Linear integration to writing-plans skill"
```

---

### Task 5: Update executing-plans skill

**Files:**
- Modify: `skills/executing-plans/SKILL.md`

Two changes: (1) add `requires_skills`, (2) add status transitions during task execution.

- [ ] **Step 1: Update frontmatter**

Change lines 1-4 from:
```yaml
---
name: executing-plans
description: Use when you have a written implementation plan to execute in a separate session with review checkpoints
---
```
to:
```yaml
---
name: executing-plans
description: Use when you have a written implementation plan to execute in a separate session with review checkpoints
requires_skills: [linear-integration]
---
```

- [ ] **Step 2: Add Linear status transitions to Step 2 (Execute Tasks)**

After line 30 (`4. Mark as completed`), add:

```markdown
5. If Linear is available and the task has a Linear issue ID (annotated in the plan heading as `[ENG-XX]`):
   - When picking up a task: read any comments on the Linear issue to check for teammate feedback before starting
   - When marking as in_progress: move the Linear issue to `In Progress`
   - When marking as completed: move the Linear issue to `Done`
   - If a bug is discovered during the task: create a new Linear issue with label `bug` alongside storing in memory
```

- [ ] **Step 3: Commit**

```bash
git add skills/executing-plans/SKILL.md
git commit -m "feat: add Linear integration to executing-plans skill"
```

---

### Task 6: Update bugs skill

**Files:**
- Modify: `skills/bugs/SKILL.md`

Three changes: (1) add `linear-integration` to `requires_skills`, (2) add Linear issue creation in `/bugs add`, (3) add Linear status update in `/bugs resolve`.

- [ ] **Step 1: Update frontmatter**

Change line 4 from:
```yaml
requires_skills: [obsidian-markdown]
```
to:
```yaml
requires_skills: [obsidian-markdown, linear-integration]
```

- [ ] **Step 2: Add Linear issue creation to /bugs add**

After line 53 (the closing of the `/bugs add` curl command), add:

```markdown
If Linear is available (per linear-integration skill), also create a corresponding Linear issue:
- Use the same title and a summary of the description
- Set label to `bug` (if the label exists in Linear)
- Add the memory vault path to the Linear issue description: `Memory: <vault_path>`
- Add the Linear issue ID to the memory content: `Linear: <PREFIX>-<ID>`
```

- [ ] **Step 3: Add Linear status update to /bugs resolve**

After line 45 (the closing of the `/bugs resolve` PATCH command), add:

```markdown
5. If Linear is available and the bug's memory content contains a Linear issue ID (`Linear: ENG-XX`):
   - Move the corresponding Linear issue to `Done`
```

- [ ] **Step 4: Add Linear issue ID to output format**

After line 62 (`- **Content preview** (first 200 chars)`), add:

```markdown
- **Linear issue** (if cross-referenced in content)
```

- [ ] **Step 5: Commit**

```bash
git add skills/bugs/SKILL.md
git commit -m "feat: add Linear integration to bugs skill"
```

---

### Task 7: Update session-end skill

**Files:**
- Modify: `skills/session-end/SKILL.md`

Two changes: (1) add `linear-integration` to `requires_skills`, (2) add Linear ticket summary to session output.

- [ ] **Step 1: Update frontmatter**

Change line 4 from:
```yaml
requires_skills: [obsidian-markdown]
```
to:
```yaml
requires_skills: [obsidian-markdown, linear-integration]
```

- [ ] **Step 2: Add Linear summary to session content**

After line 28 (`- Tags for the relevant projects/areas`), add:

```markdown
   - Linear tickets created or updated during this session (include issue IDs like `ENG-42`)
```

- [ ] **Step 3: Commit**

```bash
git add skills/session-end/SKILL.md
git commit -m "feat: add Linear integration to session-end skill"
```

---

### Task 8: Update finishing-a-development-branch skill

**Files:**
- Modify: `skills/finishing-a-development-branch/SKILL.md`

Two changes: (1) add `requires_skills`, (2) add Linear ticket references in PR descriptions.

- [ ] **Step 1: Update frontmatter**

Change lines 1-4 from:
```yaml
---
name: finishing-a-development-branch
description: Use when implementation is complete, all tests pass, and you need to decide how to integrate the work - guides completion of development work by presenting structured options for merge, PR, or cleanup
---
```
to:
```yaml
---
name: finishing-a-development-branch
description: Use when implementation is complete, all tests pass, and you need to decide how to integrate the work - guides completion of development work by presenting structured options for merge, PR, or cleanup
requires_skills: [linear-integration]
---
```

- [ ] **Step 2: Add Linear references to PR creation (Option 2)**

After line 103 (the closing `)"` of the `gh pr create` command), add:

```markdown
If Linear is available and there are associated Linear issues:
- Add a `## Linear` section to the PR body listing the issue IDs (e.g., `Closes ENG-42, ENG-43, ENG-44`)
- Linear auto-links PRs when issue IDs appear in the PR body
```

- [ ] **Step 3: Add Linear status update for merge (Option 1)**

After line 85 (closing of the merge code block, after `git branch -d <feature-branch>`), add:

```markdown
If Linear is available, move all associated Linear issues to `Done`.
```

- [ ] **Step 4: Commit**

```bash
git add skills/finishing-a-development-branch/SKILL.md
git commit -m "feat: add Linear integration to finishing-a-development-branch skill"
```
