---
name: complete-milestone
description: "Use when asked to orchestrate, drive, or complete an entire cliban milestone end-to-end — multiple dependency-linked issues each needing their own plan, implementation, and integration."
requires_skills: [cliban-workflow]
---

# Complete Milestone

## Overview

Orchestrate every issue in a cliban milestone to completion: one agent per ticket, run in dependency order, each isolated in its own worktree, each driven through `writing-plans` then `subagent-driven-development`. The orchestrator owns branch integration and merges; agents never merge.

**Core principle:** The orchestrator is a conductor, not a coder. It computes the dependency order, dispatches one agent per ticket, gates each ticket on its dependencies, and integrates finished work onto a milestone branch — never `main` — until the user finalizes.

**Announce at start:** "I'm using the complete-milestone skill to orchestrate `<milestone>`."

## When to Use

- "Orchestrate this milestone" / "complete the whole milestone" / "build out milestone X"
- A milestone has multiple issues with `blocked_by` relations forming an execution order
- You want each ticket planned and implemented independently, then integrated safely

**When NOT to use:** a single issue (use `writing-plans` + `subagent-driven-development` directly); issues with no shared integration target; exploratory work without a plan.

## The Integration Branch Rule (read first)

**Ticket branches merge into a milestone integration branch, NOT `main`.**

Merging half-finished phases straight to `main` breaks whatever currently builds from `main` — often the very tool you are using to track the work. `main` stays shippable; the milestone branch absorbs the in-progress phases; the user lands it as one atomic switch at the end via `finishing-a-development-branch`.

```
main ──────────────────────────────────────●  (untouched until final cutover)
        │                                   ↑
        └─ milestone/<slug> ──●──●──●──●─────┘  (each ● = one ticket merged in)
                              │  │  │  │
                       .worktrees/<ticket-branch> per ticket
```

## Process

```dot
digraph complete_milestone {
    "Load milestone issues + blocked_by graph" [shape=box];
    "Compute waves (topological order)" [shape=box];
    "Create milestone/<slug> off main" [shape=box];
    "Wave has ready tickets?" [shape=diamond];
    "Per ready ticket: worktree off milestone branch + dispatch agent" [shape=box];
    "Agent: writing-plans -> subagent-driven-development -> commit on ticket branch" [shape=box];
    "Agent reports done?" [shape=diamond];
    "Orchestrator: review + test + merge ticket->milestone branch" [shape=box];
    "Move issue to done, remove worktree, unblock dependents" [shape=box];
    "All issues done?" [shape=diamond];
    "Hand milestone branch to user (finishing-a-development-branch)" [shape=doublecircle];

    "Load milestone issues + blocked_by graph" -> "Compute waves (topological order)";
    "Compute waves (topological order)" -> "Create milestone/<slug> off main";
    "Create milestone/<slug> off main" -> "Wave has ready tickets?";
    "Wave has ready tickets?" -> "Per ready ticket: worktree off milestone branch + dispatch agent" [label="yes"];
    "Per ready ticket: worktree off milestone branch + dispatch agent" -> "Agent: writing-plans -> subagent-driven-development -> commit on ticket branch";
    "Agent: writing-plans -> subagent-driven-development -> commit on ticket branch" -> "Agent reports done?";
    "Agent reports done?" -> "Orchestrator: review + test + merge ticket->milestone branch" [label="yes"];
    "Orchestrator: review + test + merge ticket->milestone branch" -> "Move issue to done, remove worktree, unblock dependents";
    "Move issue to done, remove worktree, unblock dependents" -> "All issues done?";
    "All issues done?" -> "Wave has ready tickets?" [label="no - next ready tickets"];
    "All issues done?" -> "Hand milestone branch to user (finishing-a-development-branch)" [label="yes"];
}
```

### Step 1: Load the milestone and its dependency graph

```bash
cliban issue ls --project <KEY> --milestone "<NAME>" --json
```

For each issue capture `key`, `status`, and `relations` (`blocked_by` targets). Build the DAG: an issue is **ready** when every issue it is `blocked_by` is `done`.

### Step 2: Compute waves

Topologically sort. A **wave** is the set of currently-ready, not-yet-done issues — they run in parallel. After a wave's issues land, recompute readiness; newly unblocked issues form the next wave. Announce the plan:

```
Waves: [CLI-5] -> [CLI-6, CLI-8] -> [CLI-7] -> [CLI-9]
```

### Step 3: Create the milestone integration branch

```bash
ROOT=$(git rev-parse --show-toplevel)
SLUG=<milestone-slug>                       # e.g. rust-rewrite-loom-tui
git -C "$ROOT" branch "milestone/$SLUG" main 2>/dev/null || true
```

All ticket worktrees branch **off `milestone/$SLUG`**, not `main`.

### Step 4: Per ready ticket — worktree + one agent

For each ticket in the current wave, follow `using-git-worktrees` but branch off the milestone branch:

```bash
git worktree add "$ROOT/.worktrees/<ticket-branch>" -b "<ticket-branch>" "milestone/$SLUG"
```

Use the issue's `git_branch_name` as `<ticket-branch>`. Then dispatch **one agent per ticket** (parallel within a wave; use `dispatching-parallel-agents` discipline). The agent's brief MUST:

1. `cd` into its worktree and confirm isolation.
2. Invoke `writing-plans` for the issue key → fills the issue's `## Plan`.
3. Invoke `subagent-driven-development` for the same key → executes the plan task-by-task with the two-stage review it mandates.
4. Commit all work on `<ticket-branch>`. **Do NOT merge, do NOT touch `main` or the milestone branch.**
5. Report back: branch name, test status, and a one-line summary.

The agent runs writing-plans AND subagent-driven-development itself — the orchestrator does not pre-plan for it.

### Step 5: Integrate as each agent finishes

When an agent reports done, the **orchestrator** (not the agent) integrates, following `finishing-a-development-branch` Option 1 but targeting the milestone branch. **A "done" notification is a claim to verify, not a fact.**

```bash
cd "$ROOT"
# 0. VERIFY THE AGENT ACTUALLY FINISHED (before trusting the report):
git -C ".worktrees/<ticket-branch>" log --oneline "milestone/$SLUG..<ticket-branch>"  # must have commits
git -C ".worktrees/<ticket-branch>" status -s                                          # staged-but-uncommitted = NOT done
#   Also confirm the cliban plan's task checkboxes are ticked. If work is staged/
#   uncommitted or tasks are open, the agent came to rest early — resume it
#   (SendMessage) to finish + commit; do NOT integrate a half-done branch.

git checkout "milestone/$SLUG"
git merge --no-ff "<ticket-branch>"         # resolve conflicts here, in the orchestrator
<build the project>                          # BUILD FIRST — see hazard 1 below
<run the project's test command>            # then the full test gate; milestone must stay green

# VERIFY THE MERGE CAPTURED THE BRANCH'S CURRENT TIP before cleanup (see hazard 2):
test "$(git rev-parse <ticket-branch>)" = "$(git rev-parse HEAD^2)" || echo "LATE COMMIT — agent committed after the merge snapshot; cherry-pick it in"

cliban issue mv <KEY> done
cliban issue log <KEY> "merged to milestone/$SLUG as $(git rev-parse --short HEAD)"
git worktree remove "$ROOT/.worktrees/<ticket-branch>"
git branch -d "<ticket-branch>" || git branch -D "<ticket-branch>"   # -d fails after conflict-resolved --no-ff; -D once verified merged
```

If the build or tests fail on the merge result, the ticket is not done — fix it in the orchestrator (the break is usually cross-ticket; see hazard 1) or reopen it before proceeding.

**Refresh dependents:** before dispatching a ticket whose dependency just landed, its worktree must branch off the *updated* milestone branch (Step 4 already does this because the worktree is created at wave time, after upstream merges). Never create all worktrees up front.

### Step 6: Finalize

When every issue is `done` and `milestone/$SLUG` is green, STOP and hand off to the user via `finishing-a-development-branch` (base = `main`). Landing the milestone branch on `main` is the user's call — especially when a phase is a cutover that deletes or replaces existing code.

## Parallel-integration hazards

Wave tickets are written against the *same* base in parallel, so they collide on whatever is shared. The orchestrator is the **serialization point for every shared resource** — and the conflicts that matter most are the ones git does NOT mark. Watch for these:

**1. Clean auto-merge ≠ coherent code.** Two tickets that took divergent designs on the same files (e.g. both reworking one subsystem) auto-merge with *zero conflict markers* yet produce a tree that doesn't compile — git merged non-overlapping hunks of incompatible designs. **Build after every merge, even marker-free ones.** The compiler is the authority; git silence is not. When it breaks, the fix is usually porting an *already-merged* ticket's code onto the newer ticket's API (delegate that to a focused agent if it's deep), not reverting.

**2. Agents commit after they report.** An agent (or a sub-agent it spawned) can push a commit *after* its "done" notification / after your merge snapshot. Verify `git rev-parse <branch>` equals the merge's ticket-side parent (`HEAD^2`) before deleting the branch; cherry-pick any straggler. Put "commit everything FIRST, then send your final report — no dangling commits" in every agent brief.

**3. Serialized shared sequences (changelog IDs, version files, shared enums, registries).** Every agent mints the next ID / bumps the version against the *stale* base, so they collide on merge. Pre-assigning reserved IDs in briefs helps but merge-order still wins — **the orchestrator owns the sequence and renumbers at integration time**, in merge order, keeping it gapless. Tell agents not to bump a shared version file at all (the milestone is one unreleased version until finalize).

**4. Path-based pre-commit hooks don't enforce *completeness*.** A spec-first (or lint, or codegen) hook that fires on "any file under X changed" passes when an agent does *half* the paired change — adds the section but not the changelog entry, the keyword but not the grammar. The orchestrator must check the both-halves invariant at integration and fill the gap.

**5. Shared mutable state contention.** Sub-agents racing on a shared DB/scratchpad (e.g. the cliban issue store) can overwrite each other's ticket descriptions or files. Verify each ticket's description still matches its key before relying on it; keep per-ticket state in the worktree, not shared paths.

**6. Finished agents re-create branches/worktrees.** An agent doing a late rebase can resurrect a branch/worktree you already cleaned up. Re-scan `git worktree list` for stragglers before finalizing; remove stale ones (`--force` if needed) — but never the *live* worktree of a still-running agent.

## Quick Reference

| Concern | Rule |
|---|---|
| Integration target | `milestone/<slug>`, never `main` until finalize |
| Parallelism | One agent per ticket; whole wave in parallel |
| Readiness | Issue ready when all `blocked_by` are `done` |
| Who plans | The ticket's agent (writing-plans), not the orchestrator |
| Who implements | The ticket's agent (subagent-driven-development) |
| Who merges | The orchestrator, only — agents never merge |
| Worktree timing | Created at wave dispatch, off current milestone branch |
| Tests | **Build then test** on every merge result, even marker-free auto-merges; failure reopens the ticket |
| "Done" report | A claim to verify — confirm real commits + ticked plan before integrating |
| Shared IDs/versions | Orchestrator owns the sequence; renumber at merge, in order, gapless |
| Branch cleanup | Verify `<branch>` == merge `HEAD^2` before delete; cherry-pick stragglers |
| Final landing | User decides, via finishing-a-development-branch |

## Common Mistakes

**Merging tickets to `main`** → breaks the working build mid-milestone. Always merge to the milestone branch; `main` lands once, at the end, by the user.

**Creating all worktrees up front** → dependent tickets branch off stale code that lacks their dependency's work. Create each worktree at wave time, after upstream merges.

**Orchestrator pre-planning the ticket** → the agent is told to run writing-plans itself. Don't hand it a finished plan; let the per-ticket plan + review checkpoints happen inside the agent.

**Agent merges its own branch** → loses the orchestrator's conflict-resolution and green-tests gate. Agents commit only; the orchestrator integrates.

**Ignoring the DAG and firing all agents at once** → dependents race their dependencies. Gate strictly on `blocked_by` → `done`.

**Skipping tests on the merge result** → a green ticket branch can still break the milestone branch on merge. Test after every integration.

**Trusting "no conflict markers" as "coherent"** → a clean auto-merge of two divergent designs compiles to nothing. Build, don't just check for markers. See Parallel-integration hazards.

**Deleting a branch on the "done" report** → agents commit after reporting. Verify branch tip == merge `HEAD^2` first; cherry-pick stragglers.

**Letting each agent own a shared sequence (CS-ids, version files)** → guaranteed collisions. The orchestrator assigns at merge time.

## Red Flags

**Never:**
- Merge a ticket branch into `main` (only the milestone branch, until final handoff)
- Dispatch a ticket before all its `blocked_by` issues are `done`
- Let an agent merge, rebase onto, or push the milestone branch
- Create a dependent's worktree before its dependency has merged
- Mark an issue `done` when the milestone branch fails tests after its merge
- Integrate a branch on its "done" report alone — verify real commits, a ticked plan, and tip == merge `HEAD^2`
- Treat a marker-free auto-merge as safe without building it
- Let agents own a shared ID/version sequence — they will collide

**Always:**
- Build the dependency DAG before dispatching anything
- Branch ticket worktrees off the milestone branch
- Make each agent run writing-plans then subagent-driven-development itself
- Integrate (verify-done + merge + **build** + test + cliban move + tip-check + cleanup) as the orchestrator, per ticket
- Own every shared sequence (changelog IDs, version files, shared enums); renumber at merge, gapless
- Check the both-halves invariant when a path-based hook could pass on a half-done paired change
- Brief every agent: commit everything first, THEN report — no dangling commits
- Hand the final milestone-branch → `main` decision to the user
