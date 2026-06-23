---
name: subagent-driven-development
description: "Use when executing a cliban-stored implementation plan with independent tasks in the current session, dispatching a fresh subagent per task."
requires_skills: [cliban-workflow]
---

# Subagent-Driven Development

Execute a plan by dispatching a fresh subagent per task, with two-stage review after each: spec compliance review first, then code quality review. The plan lives in a cliban Issue's `## Plan` section.

**Why subagents:** You delegate tasks to specialized agents with isolated context. By precisely crafting their instructions and context, you ensure they stay focused and succeed. They should never inherit your session's context or history — you construct exactly what they need. This also preserves your own context for coordination work.

**Core principle:** Fresh subagent per task + two-stage review (spec then quality) = high quality, fast iteration.

**Continuous execution:** Do not pause to check in between tasks. Execute all tasks from the plan without stopping. The only reasons to stop are: BLOCKED status you cannot resolve, ambiguity that prevents progress, or all tasks complete.

**Commit discipline (continuous ≠ uncommitted):** Land every task's work as a commit *as you go*. Commits are the only durable, reviewable record — staged-but-uncommitted work is invisible to reviewers and to whoever integrates the branch, and a subagent can end its turn with work merely staged. So: never advance past a task, come to rest, or send your final report while any task's work is staged-but-uncommitted; verify each task's commit actually landed (`git log --oneline <base>..HEAD`) before moving on; and **never commit anything after your final report** — land every commit first, *then* report. A commit that arrives after your report gets silently missed by the integrator.

## When to Use

```dot
digraph when_to_use {
    "Plan in cliban issue?" [shape=diamond];
    "Tasks mostly independent?" [shape=diamond];
    "Stay in this session?" [shape=diamond];
    "subagent-driven-development" [shape=box];
    "executing-plans" [shape=box];
    "Brainstorm or plan first" [shape=box];

    "Plan in cliban issue?" -> "Tasks mostly independent?" [label="yes"];
    "Plan in cliban issue?" -> "Brainstorm or plan first" [label="no"];
    "Tasks mostly independent?" -> "Stay in this session?" [label="yes"];
    "Tasks mostly independent?" -> "Brainstorm or plan first" [label="no - tightly coupled"];
    "Stay in this session?" -> "subagent-driven-development" [label="yes"];
    "Stay in this session?" -> "executing-plans" [label="no"];
}
```

## The Process

### Step 0: Enforce Worktree Isolation

Plan execution requires an isolated worktree — there is **no fallback to in-place work**. Before reading the plan or touching any task:

1. Invoke `alex-memory:using-git-worktrees`.
2. After it returns, verify isolation actually succeeded:

   ```bash
   GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
   GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
   if [ "$GIT_DIR" = "$GIT_COMMON" ] && [ -z "$(git rev-parse --show-superproject-working-tree 2>/dev/null)" ]; then
     echo "ABORT: not in a worktree" >&2; exit 1
   fi
   ```

3. **If the check fails** (e.g., sandbox blocked `git worktree add` and the worktree skill fell back to in-place), STOP. Report the failure and ask the user to resolve permissions or use a less-restrictive sandbox before retrying. Do not proceed with the plan in the main checkout. The in-place fallback in `using-git-worktrees` is for ad-hoc work, not for executing a written plan.

### Step 1: Load Plan from Cliban

1. Resolve the issue key (argument, `cliban issue current --json`, or ask user).
2. Read the plan section:

```bash
cliban issue show <KEY> --section plan
```

3. Extract every task with full text. The plan format is binding per the `cliban-workflow` description contract:
   - H3 `### Task N: <name>` headers separate tasks
   - GFM `- [ ]` / `- [x]` lines are the steps
4. Critically review for gaps or contradictions. Surface concerns to the user before dispatching.
5. Create a TodoWrite with one todo per Task (NOT per Step — steps are bite-sized, internal to the subagent).

### Step 2: Move Issue to In-Progress

```bash
cliban issue mv <KEY> in-progress
cliban issue log <KEY> "starting subagent-driven execution"
```

### Step 3: Per-Task Loop

For each Task N in the plan:

#### 3a. Dispatch Implementer Subagent

Use the template `./implementer-prompt.md` with these fields filled in:
- `WHAT_TO_BUILD`: the full task text (read from your extraction in Step 1)
- `CLIBAN_KEY`: `<KEY>` so the subagent can call `cliban issue tick`/`log` itself
- `TASK_NUMBER`: N
- `CONTEXT`: scene-setting — what already shipped (previous tasks done), what depends on this task

The subagent must:
1. Implement the task
2. Run tests
3. Commit (one or more commits per task, depending on scope)
4. Tick each step via `cliban issue tick <KEY> --task N --step M` as it goes
5. Self-review
6. Report back with status

**Blocking dispatch — consume the return value, don't fire-and-forget.** Dispatch the implementer and wait for it; read the result it *returns* to you. Do NOT background-dispatch task subagents, and do NOT design a flow where a task subagent must message you back after you've moved on — a child that reports to a parent who has already advanced or finished is orphaned (the "peer no longer addressable" failure, and the source of dropped commits). One task child is live at a time; you do not advance to the next task, and you do not emit your own final report, while any dispatched child is still running or its commit is unlanded. If a child returns with work staged-but-uncommitted, YOU commit it (you have the worktree) before proceeding.

#### 3b. Handle Implementer Status

**DONE:** proceed to spec compliance review.
**DONE_WITH_CONCERNS:** read concerns. If about correctness/scope, address before review. Otherwise note and proceed.
**NEEDS_CONTEXT:** provide missing context and re-dispatch.
**BLOCKED:** assess the blocker. Context problem → provide context and retry. Reasoning problem → re-dispatch with a more capable model. Task too big → break it down. Plan wrong → escalate to user.

#### 3c. Dispatch Spec Compliance Reviewer

Use `./spec-reviewer-prompt.md`. The reviewer:
- Reads actual code and tests
- Compares against the task's spec
- Reports ✅ (compliant) or ❌ (with specific issues)

If ❌: re-dispatch the implementer with the issues, then re-review.

#### 3d. Dispatch Code Quality Reviewer

Use `./code-quality-reviewer-prompt.md`. The reviewer evaluates:
- Idiomatic style, naming
- Subtle bugs, edge cases
- Test coverage gaps
- File organization

Reports Strengths + Issues (Critical/Important/Minor) + Assessment.

If Critical or Important issues → re-dispatch implementer to fix, re-review.

If only Minor issues → accept and move on (note in cliban via `cliban issue log` if multiple Minors accumulate).

#### 3e. Mark Task Complete + Log

```bash
cliban issue log <KEY> "Task N complete: <one-line summary>"
```

Update TodoWrite — Task N done.

### Step 4: Final Cumulative Review

After all tasks are done:

1. Dispatch a final code reviewer for the entire body of work (cumulative diff).
2. The reviewer evaluates cross-task consistency, architectural drift, dead code, anything that slipped through per-task reviews.
3. **Ponytail drift check:** the same reviewer also confirms the implementation didn't over-build *beyond* the lazy plan — no abstractions, dependencies, or flexibility the plan didn't call for. The plan was already trimmed by ponytail at write time; this verifies the executor stayed within it rather than re-trimming the plan. Have the reviewer apply the `alex-memory:ponytail-review` lens to the cumulative diff for this. One pass, cumulative — not per task.
4. Report findings to user.
5. If Critical/Important issues found, dispatch fix subagent(s).

### Step 5: Finishing

After cumulative review approves:

- Announce: "I'm using the finishing-a-development-branch skill to complete this work."
- **REQUIRED SUB-SKILL:** Use `alex-memory:finishing-a-development-branch`.

## Model Selection

**Role tiering — keep judgment capable, make only the grind cheap.** You (the executor) coordinate, resolve conflicts, run reviews, and land commits — stay on a capable model. The per-task **implementer** subagents are where cheap models belong; the two **reviewers** (spec + quality) stay capable, since their whole job is catching what a cheap implementer got wrong. Never run the executor or the reviewers on the cheap tier to save tokens — that removes the quality recovery that makes cheap implementers safe.

Per-task **implementer** model, by task shape:
- **Mechanical tasks** (isolated functions, clear specs, 1-2 files): cheap model
- **Integration tasks** (multi-file coordination, debugging): standard model
- **Architecture/review tasks**: most capable available

## Prompt Templates

- `./implementer-prompt.md` — implementer subagent
- `./spec-reviewer-prompt.md` — spec compliance reviewer subagent
- `./code-quality-reviewer-prompt.md` — code quality reviewer subagent

Adjust these to include the `cliban issue tick` / `cliban issue log` calls the subagent should make. The subagent works on a single Task at a time; it does NOT mutate the plan structure (no edits to the `## Plan` section directly — only `tick` and `log` and `promote`).

## Red Flags

**Never:**
- Start implementation without a verified worktree (Step 0 — the in-place fallback in `using-git-worktrees` is for ad-hoc work, not plan execution)
- Start implementation on `main`/`master` without explicit user consent
- Skip reviews (spec compliance OR code quality)
- Proceed with unfixed Critical/Important issues
- Dispatch multiple implementer subagents in parallel (conflicts)
- Make a subagent read the plan from cliban directly — extract the task text once and pass it as part of the prompt (reduces subagent context cost, prevents re-reads from drifting)
- Let a subagent edit the `## Plan` or `## Spec` structure — they can `tick`, `log`, `promote`, but NOT `edit --description`
- Report a task or the whole plan "done" while any work is staged-but-uncommitted
- Commit anything after your final report — land every commit first, THEN report
- Come to rest while a dispatched subagent's task work is uncommitted or unverified — a subagent can end its turn with work merely staged, or become unaddressable mid-task; YOU land/verify the commit before advancing
- Background-dispatch task subagents or rely on a child messaging you back — dispatch blocking and consume the returned result; a child reporting to a parent who has moved on is orphaned

**Always:**
- Pass the FULL task text in the subagent prompt (not the issue key + "read the plan")
- Set `CLIBAN_KEY` so the subagent can call tick/log
- Review the subagent's commits (not just its report) — commits are the ground truth
- Verify each task's commit actually landed on the branch (`git log --oneline <base>..HEAD`) before advancing to the next task

## Integration

**Required workflow skills:**
- `alex-memory:using-git-worktrees` — ensure isolated workspace
- `alex-memory:writing-plans` — creates the plan
- `alex-memory:requesting-code-review` — review templates
- `alex-memory:finishing-a-development-branch` — complete development

**Subagents should use:**
- `alex-memory:test-driven-development` — TDD per task
