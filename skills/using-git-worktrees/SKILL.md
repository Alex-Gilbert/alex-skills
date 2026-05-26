---
name: using-git-worktrees
description: Use when starting feature work that needs isolation from current workspace or before executing implementation plans - ensures an isolated workspace exists in .worktrees/ at the repo root
---

# Using Git Worktrees

## Overview

All non-trivial work happens in an isolated worktree at `<repo-root>/.worktrees/<branch>`. This is non-negotiable — do not ask the user for consent, do not work in place unless the sandbox blocks worktree creation.

**Core principle:** Detect existing isolation first. If not isolated, create a worktree under `.worktrees/`. Never fight the harness.

**Announce at start:** "I'm using the using-git-worktrees skill to set up an isolated workspace."

## Step 0: Detect Existing Isolation

**Before creating anything, check if you are already in an isolated workspace.**

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
BRANCH=$(git branch --show-current)
```

**Submodule guard:** `GIT_DIR != GIT_COMMON` is also true inside git submodules. Before concluding "already in a worktree," verify you are not in a submodule:

```bash
# If this returns a path, you're in a submodule, not a worktree — treat as normal repo
git rev-parse --show-superproject-working-tree 2>/dev/null
```

**If `GIT_DIR != GIT_COMMON` (and not a submodule):** You are already in a linked worktree. Skip to Step 2 (Project Setup). Do NOT create another worktree.

Report with branch state:
- On a branch: "Already in isolated workspace at `<path>` on branch `<name>`."
- Detached HEAD: "Already in isolated workspace at `<path>` (detached HEAD, externally managed). Branch creation needed at finish time."

**If `GIT_DIR == GIT_COMMON` (or in a submodule):** You are in a normal repo checkout. Proceed to Step 1.

## Step 1: Create Worktree in `.worktrees/`

Worktrees always live at `<repo-root>/.worktrees/<branch>`. No other locations. Do not prompt for consent — the user has already declared this preference.

### 1a. Ensure `.worktrees/` is ignored

```bash
cd "$(git rev-parse --show-toplevel)"
if ! git check-ignore -q .worktrees; then
  printf '\n.worktrees/\n' >> .gitignore
  git add .gitignore
  git commit -m "chore: ignore .worktrees/"
fi
```

**Why critical:** Prevents accidentally committing worktree contents to the repository.

### 1b. Create the worktree

```bash
ROOT=$(git rev-parse --show-toplevel)
BRANCH_NAME=<the-branch-for-this-work>
git worktree add "$ROOT/.worktrees/$BRANCH_NAME" -b "$BRANCH_NAME"
cd "$ROOT/.worktrees/$BRANCH_NAME"
```

If the branch already exists, drop the `-b` flag and check it out:

```bash
git worktree add "$ROOT/.worktrees/$BRANCH_NAME" "$BRANCH_NAME"
```

**Sandbox fallback (ad-hoc work only):** If `git worktree add` fails with a permission error (sandbox denial) AND this skill was invoked for ad-hoc work, tell the user the sandbox blocked worktree creation and you're working in the current directory instead. Then run setup and baseline tests in place.

**Plan execution flows do NOT fall back.** When invoked from `subagent-driven-development` or `executing-plans`, the calling skill verifies isolation after this one returns and will abort if creation failed. Do not silently work in place when called from a plan execution flow — report the failure clearly so the caller can stop.

**Do NOT use native worktree tools** (`EnterWorktree`, `/worktree`, etc.) — they place worktrees in harness-managed locations outside the repo. The user has chosen `.worktrees/` at the repo root.

## Step 2: Project Setup

Auto-detect and run appropriate setup:

```bash
# Node.js
if [ -f package.json ]; then npm install; fi

# Rust
if [ -f Cargo.toml ]; then cargo build; fi

# Python
if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
if [ -f pyproject.toml ]; then poetry install; fi

# Go
if [ -f go.mod ]; then go mod download; fi
```

## Step 3: Verify Clean Baseline

Run tests to ensure workspace starts clean:

```bash
# Use project-appropriate command
npm test / cargo test / pytest / go test ./...
```

**If tests fail:** Report failures, ask whether to proceed or investigate.

**If tests pass:** Report ready.

### Report

```
Worktree ready at <repo-root>/.worktrees/<branch>
Tests passing (<N> tests, 0 failures)
Ready to implement <feature-name>
```

## Quick Reference

| Situation | Action |
|-----------|--------|
| Already in linked worktree | Skip creation (Step 0) |
| In a submodule | Treat as normal repo (Step 0 guard) |
| Not in a worktree | Create at `<repo-root>/.worktrees/<branch>` (Step 1) |
| `.worktrees/` not in .gitignore | Add and commit before creating worktree |
| Branch already exists | `git worktree add <path> <branch>` (no `-b`) |
| Permission error on create | Sandbox fallback, work in place |
| Tests fail during baseline | Report failures + ask |
| No package.json/Cargo.toml | Skip dependency install |

## Common Mistakes

### Asking for consent

- **Problem:** Prompting "would you like a worktree?" wastes a turn — the user already said yes, always.
- **Fix:** Skip the question. Create the worktree.

### Using native worktree tools

- **Problem:** `EnterWorktree` and similar tools put worktrees in harness-managed locations, not `.worktrees/`.
- **Fix:** Always use `git worktree add` into `<repo-root>/.worktrees/<branch>`.

### Skipping detection

- **Problem:** Creating a nested worktree inside an existing one
- **Fix:** Always run Step 0 before creating anything

### Skipping ignore verification

- **Problem:** Worktree contents get tracked, pollute git status
- **Fix:** Always check + add `.worktrees/` to `.gitignore` before creating

### Proceeding with failing tests

- **Problem:** Can't distinguish new bugs from pre-existing issues
- **Fix:** Report failures, get explicit permission to proceed

## Red Flags

**Never:**
- Ask the user whether to create a worktree
- Create a worktree anywhere other than `<repo-root>/.worktrees/<branch>`
- Use native worktree tools (`EnterWorktree`, etc.)
- Create a worktree when Step 0 detects existing isolation
- Create a worktree without verifying `.worktrees/` is ignored
- Skip baseline test verification
- Proceed with failing tests without asking

**Always:**
- Run Step 0 detection first
- Use `git worktree add` into `<repo-root>/.worktrees/<branch>`
- Add `.worktrees/` to `.gitignore` if missing, and commit
- Auto-detect and run project setup
- Verify clean test baseline
