---
name: executing-plans
description: "Use when you have a written plan in a cliban issue to execute in a separate session with review checkpoints."
requires_skills: [cliban-workflow]
---

# Executing Plans

## Overview

Load the plan from cliban, review critically, execute all tasks step-by-step, report when complete.

**Announce at start:** "I'm using the executing-plans skill to implement this plan."

**Note:** Tell your human partner that this skill works much better with subagent support. If subagents are available, prefer `superpowers:subagent-driven-development`.

## The Process

### Step 1: Resolve Issue + Load Plan

1. Resolve the issue key (argument, `cliban issue current --json`, or ask user).
2. Read the plan section:

```bash
cliban issue show <KEY> --section plan
```

3. If `--section plan` returns exit 1, ask the user to run writing-plans first.
4. Critically review the plan — list any concerns about gaps, ordering, or dependencies. Surface them with the user before starting.

### Step 2: Move Issue to In-Progress + Log Start

```bash
cliban issue mv <KEY> in-progress
cliban issue log <KEY> "starting execution"
```

### Step 3: Execute Tasks

For each `### Task N` in the plan:

1. Mark task started in your TodoWrite (one todo per task).
2. For each `- [ ]` step under the task, in order:
   a. Execute the step (write code, run commands)
   b. Run verification (the next step in the plan typically says "Expected: PASS" or similar)
   c. Atomically tick the step:

      ```bash
      cliban issue tick <KEY> --task N --step M --json
      ```

      Exit code 2 means the description structure changed since you read it (e.g., a concurrent edit). Re-read the plan and recover.

3. Mark TodoWrite task complete after the last step of the cliban Task is ticked.

### Step 4: Handle Discoveries

While executing:

**A step turns out to be a body of work** (would take 30+ minutes):

```bash
cliban issue promote <KEY> --task N --step M --title "<descriptive title>" --as sub-issue --json
cliban issue log <KEY> "promoted Step M of Task N → NEWKEY"
```

Then either pause and execute the new sub-issue first, or note it as a follow-up. Decide with the user if unclear.

**A bug surfaces in unrelated code:**

```bash
NEW=$(cliban issue add --project <PROJ> --label bug --priority medium \
  --blocks <KEY> --title "<bug title>" \
  --description-file - --json <<'EOF' | jq -r '.key'
## Spec

<bug description, repro steps, expected vs actual>
EOF
)
cliban issue log <KEY> "bug surfaced during Task N Step M: $NEW"
```

Move the original issue to `blocked` if the bug actually blocks progress, then handle the bug. Otherwise continue and resolve the bug later.

**Plan has a gap or error:** Stop. Surface with user. Don't guess.

### Step 5: Complete Development

After all tasks complete and verified:

- Announce: "I'm using the finishing-a-development-branch skill to complete this work."
- **REQUIRED SUB-SKILL:** Use `superpowers:finishing-a-development-branch`
- That skill will handle: test verification, status transition to `in-review` or `done`, branch cleanup.

## When to Stop and Ask for Help

**STOP executing immediately when:**
- Hit a blocker (missing dependency, test fails, instruction unclear)
- Plan has critical gaps preventing starting
- You don't understand an instruction
- Verification fails repeatedly
- `cliban issue tick` returns exit 2 — the description structure changed underneath you

**Ask for clarification rather than guessing.**

## Remember

- Review plan critically first
- Follow plan steps exactly
- Don't skip verifications
- Use `cliban issue tick` for every step — that's the source of truth for progress
- Use `cliban issue log` for non-trivial decisions (promotions, bugs found, blockers hit)
- Stop when blocked, don't guess
- Never start implementation on `main`/`master` without explicit user consent

## Integration

**Required workflow skills:**
- `superpowers:using-git-worktrees` — ensure isolated workspace
- `superpowers:writing-plans` — creates the plan this skill executes
- `superpowers:finishing-a-development-branch` — completes development after all tasks
