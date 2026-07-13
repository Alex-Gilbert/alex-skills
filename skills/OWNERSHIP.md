# Skill Ownership

Whether a skill tracks upstream [`obra/superpowers`](https://github.com/obra/superpowers) or is owned by this fork. This determines how we maintain it.

- **upstream-tracked** — keep close to upstream. Pull improvements by sync/cherry-pick. **Do NOT** weave in fork customizations (ponytail, cliban) or de-bloat them — that trades line-count for permanent merge pain. Invoke fork disciplines (e.g. ponytail) *against* these skills as standalone steps instead of editing them.
- **fork-owned** — already diverged (cliban rewrite and/or heavy customization). Edit freely; integrate ponytail; de-bloat at will. Port upstream improvements by *manual cherry-pick*, never a clean merge.
- **fork-original** — does not exist upstream. Wholly ours.

Verify with: `grep -c "cliban\|MEMORY_API_URL\|ponytail" skills/<name>/SKILL.md` — fork markers ⇒ fork-owned.

## upstream-tracked (keep pristine)

dispatching-parallel-agents · receiving-code-review · test-driven-development · using-git-worktrees · using-superpowers · verification-before-completion · writing-skills

## fork-owned (diverged from upstream — own them)

brainstorming · executing-plans · finishing-a-development-branch · requesting-code-review · subagent-driven-development · writing-plans · systematic-debugging *(upstream base with fork workflow changes)*

## fork-original (no upstream counterpart)

bugs · cliban · cliban-workflow · complete-milestone · improve · model-routing · ponytail · ponytail-audit · ponytail-debt · ponytail-review · repo-standards · requesting-strict-review · status · ticket
