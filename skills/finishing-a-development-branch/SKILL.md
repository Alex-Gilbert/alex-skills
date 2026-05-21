---
name: finishing-a-development-branch
description: "Use when implementation is complete, all tests pass, and you need to integrate the work. Presents structured options for merge/PR/cleanup and transitions the cliban issue state."
requires_skills: [cliban-workflow]
---

# Finishing a Development Branch

## Overview

Guide completion of development work by presenting clear options, executing the chosen workflow, and transitioning the cliban issue state.

**Core principle:** Verify tests → Detect environment → Present options → Execute choice → Move cliban issue → Clean up.

**Announce at start:** "I'm using the finishing-a-development-branch skill to complete this work."

## The Process

### Step 1: Verify Tests

Run the project's test suite before offering options:

```bash
# e.g. for Go projects:
go test ./...
# e.g. for Node:
npm test
# e.g. for Python:
pytest
```

**If tests fail:**

```
Tests failing (<N> failures). Must fix before completing.

[Show failures]

Cannot proceed with merge/PR until tests pass.
```

Stop. Do not proceed.

### Step 2: Resolve Cliban Issue (if any)

```bash
cliban issue current --json
```

If exit 0, capture `KEY` from the output. If exit 1, no cliban issue is associated with this branch — the rest of the skill works without cliban updates (gracefully degrades).

### Step 3: Detect Environment

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
BRANCH=$(git branch --show-current)
WORKTREE=$(git rev-parse --show-toplevel)
```

| State | Menu | Cleanup |
|---|---|---|
| `GIT_DIR == GIT_COMMON` (normal repo) | Standard 4 options | No worktree cleanup |
| `GIT_DIR != GIT_COMMON`, named branch | Standard 4 options | Provenance-based |
| `GIT_DIR != GIT_COMMON`, detached HEAD | Reduced 3 options (no merge) | No cleanup (host-managed) |

### Step 4: Determine Base Branch

```bash
git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null
```

Or ask: "This branch split from `main` — is that correct?"

### Step 5: Present Options

**Normal repo or named-branch worktree:**

```
Implementation complete. What would you like to do?

1. Merge back to <base-branch> locally
2. Push and create a Pull Request
3. Keep the branch as-is (I'll handle it later)
4. Discard this work

Which option?
```

**Detached HEAD (3 options, no local merge):**

```
Implementation complete. You're on a detached HEAD (externally managed workspace).

1. Push as new branch and create a Pull Request
2. Keep as-is
3. Discard this work

Which option?
```

Keep the options concise — no additional explanation.

### Step 6: Execute Choice + Cliban Transition

#### Option 1: Merge Locally

```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"

git checkout <base-branch>
git pull 2>/dev/null || true   # local-only branches may not have a remote
git merge --squash <feature-branch>
git commit -m "<squash subject>"

# Verify tests on merged result
<test command>

# Move cliban issue to done (if KEY captured in Step 2):
if [ -n "$KEY" ]; then
  cliban issue mv $KEY done
  cliban issue log $KEY "merged to <base-branch> as $(git rev-parse --short HEAD)"
fi

# Cleanup worktree (Step 7), then delete branch:
git branch -d <feature-branch>
```

If this issue was promoted from a parent issue (description's `## Plan` step rewritten with `→ KEY`), the parent's step checkbox does NOT auto-tick. The cliban-workflow convention says it's our job to mirror — tick the parent's referencing step:

```bash
# Find the parent (if this issue's promotion left a trail in any parent's plan)
# This is best-effort — look at related-to / parent_id:
PARENT=$(cliban issue show $KEY --json | jq -r '.parent // empty')
if [ -n "$PARENT" ]; then
  # Walk the parent's plan and find the step line that contains "→ $KEY"
  cliban issue show $PARENT --section plan | grep -nE "→ +$KEY( |$)" || true
  # If found, ask the user "should I tick that step?" — manual confirmation required;
  # cliban does not expose a "tick by content match" command.
fi
```

#### Option 2: Push and Create PR

```bash
git push -u origin <feature-branch>

# Compose PR body referencing the cliban issue
gh pr create --title "<title>" --body "$(cat <<EOF
## Summary
<2-3 bullets of what changed>

## Cliban
$KEY — see \`cliban issue show $KEY --pager\`

## Test Plan
- [ ] <verification steps>
EOF
)"

# Move cliban issue to in-review:
if [ -n "$KEY" ]; then
  PR_URL=$(gh pr view --json url -q .url)
  cliban issue mv $KEY in-review
  cliban issue log $KEY "PR opened: $PR_URL"
fi
```

**Do NOT clean up the worktree** — user needs it for PR iteration.

#### Option 3: Keep As-Is

```bash
echo "Keeping branch <name>. Worktree preserved at <path>."
# Do not move the cliban issue — its current status is correct for "keep working later".
# Optionally log:
if [ -n "$KEY" ]; then
  cliban issue log $KEY "paused; branch preserved at <path>"
fi
```

#### Option 4: Discard

Confirm:

```
This will permanently delete:
- Branch <name>
- All commits: <commit-list>
- Worktree at <path>

Type 'discard' to confirm.
```

Wait for the exact string `discard`. If confirmed:

```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"

# Log to cliban before destroying the branch (issue stays open — work wasn't done)
if [ -n "$KEY" ]; then
  cliban issue log $KEY "work discarded; branch and commits deleted"
fi
```

Then cleanup worktree (Step 7), then force-delete branch:

```bash
git branch -D <feature-branch>
```

### Step 7: Cleanup Workspace

**Only runs for Options 1 and 4.** Options 2 and 3 always preserve the worktree.

```bash
WORKTREE_PATH=$(git -C <WORKTREE> rev-parse --show-toplevel)

# If GIT_DIR == GIT_COMMON, no worktree to clean up.
if [ "$GIT_DIR" = "$GIT_COMMON" ]; then
  exit 0
fi

# Provenance check: only auto-remove worktrees we own.
case "$WORKTREE_PATH" in
  */.worktrees/*|*/worktrees/*|*/.config/superpowers/worktrees/*)
    MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
    cd "$MAIN_ROOT"
    git worktree remove "$WORKTREE_PATH"
    git worktree prune
    ;;
  *)
    # Host-managed worktree — leave it in place.
    echo "Worktree at $WORKTREE_PATH appears host-managed; not auto-removing."
    ;;
esac
```

## Quick Reference

| Option | Merge | Push | Keep Worktree | Cleanup Branch | Cliban Mv |
|--------|-------|------|---------------|----------------|-----------|
| 1. Merge locally | yes | - | - | yes | done |
| 2. Create PR | - | yes | yes | - | in-review |
| 3. Keep as-is | - | - | yes | - | (no change) |
| 4. Discard | - | - | - | yes (force) | (no change, log only) |

## Common Mistakes

**Skipping test verification** → Always run tests first.

**Open-ended menu** → Present exactly 4 (or 3) structured options.

**Cleaning up worktree on Option 2** → Only Options 1 & 4 clean up the worktree.

**Deleting branch before removing worktree** → Worktree references the branch; remove worktree first.

**Running `git worktree remove` from inside the worktree** → CD to main repo root first.

**Cleaning up harness-owned worktrees** → Only remove worktrees under known superpowers/.worktrees/ directories.

**No confirmation for Discard** → Require typed `discard`.

**Forgetting to move the cliban issue** → Every option (except 3) updates the issue. Option 3 logs but doesn't move.

## Red Flags

**Never:**
- Proceed with failing tests
- Merge without verifying tests on the result
- Delete work without typed confirmation
- Force-push without explicit user request
- Remove a worktree before confirming merge success
- Move the cliban issue to `done` if the work was discarded

**Always:**
- Verify tests before offering options
- Detect environment before presenting menu
- Present exactly 4 options (or 3 for detached HEAD)
- Get typed `discard` confirmation for Option 4
- Cleanup worktree for Options 1 & 4 only
- Log to cliban for all four options (status change for 1/2, log-only for 3/4)
