---
name: requesting-strict-review
description: Use when finishing a large feature branch, auditing a PR, or evaluating a refactor — to dispatch an opinionated maintainability reviewer focused on structural simplification, abstraction quality, and spaghetti detection. Stricter than requesting-code-review and complementary to it.
requires_skills: [model-routing]
---

# Requesting Strict Review

Dispatch a deliberately demanding code reviewer that pushes for structural simplification, deletion-over-rearrangement, and abstraction cleanliness. Use when `requesting-code-review`'s broad checklist won't push back hard enough on shape — typically after a multi-task feature branch or before opening a PR.

**Core principle:** Behavior-preserving restructurings that delete complexity. Reviewer looks for "code judo" moves, not local nits.

**Not a replacement for `requesting-code-review`.** That one covers requirements, tests, security, devenv coverage. This one is single-axis: maintainability and structural quality. Run both for big merges if you want full coverage.

## When to Use

**Good fit:**
- Finishing a multi-task feature branch (before merge or PR)
- Auditing a long-lived branch that's grown sprawling
- After a deliberate refactor — was the simplification actually delivered?
- Before merging a diff that crosses ~200+ changed lines or touches a critical module

**Skip for:**
- One-line fixes, dep bumps, doc-only changes
- Mid-flight work between subagent tasks (use `requesting-code-review` instead — strict review needs whole-branch context)
- Diffs you already know are mechanical

## How to Request

**1. Compute the diff range against the branch base:**

```bash
BASE=$(git merge-base HEAD main 2>/dev/null || git merge-base HEAD master)
HEAD_SHA=$(git rev-parse HEAD)
WORKTREE=$(git rev-parse --show-toplevel)
```

**2. Dispatch the code-reviewer subagent**, filling the template at `code-reviewer.md`:

- `{WORKTREE_PATH}` — `$WORKTREE`
- `{BASE_SHA}` — `$BASE`
- `{HEAD_SHA}` — `$HEAD_SHA`
- `{SUMMARY}` — one-sentence description of what the branch is for

Resolve the `reviewer` role through model-routing and pass it when supported. Strict review depends on capable judgment, but the selected provider model and cost profile belong to the central routing policy.

**3. Act on findings.** Strict review is more demanding than normal:

- Treat Critical / Important findings as `must address or justify`, not optional
- "Code-judo opportunities" findings often mean restructuring the branch before merge
- If you push back, push back with technical reasoning — not "ship it"

## Integration

**With `finishing-a-development-branch`:** That skill offers strict review as Step 4.5 before merge/PR. Decline for trivial branches.

**Standalone:** Invoke directly when you want an aggressive structural audit at any branch state — you don't need to be at the finish line.

**PR review:** Run after pushing the PR. Findings can be posted as inline PR comments via `/code-review --comment` if you want them on the PR rather than only in-session.

## Red Flags

**Never:**
- Run on a partial implementation between subagent tasks (no structural context yet)
- Use this in place of normal review for requirements/test/security coverage
- Auto-approve just because strict review didn't flag blockers — it intentionally ignores correctness

**Always:**
- Give the subagent the actual diff range, not just "current branch"
- Read whole-file context for new or substantially-changed files when responding to findings
- Surface "code-judo opportunities" to the user before merging, even if you disagree

## Template

See `code-reviewer.md` in this directory.
