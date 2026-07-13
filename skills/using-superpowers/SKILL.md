---
name: using-superpowers
description: Use when deciding which available skills meaningfully improve a task, especially when several workflows could apply
---

# Using Skills

Skills are focused tools, not a mandatory preflight checklist. Use judgment: load a skill when its specialized workflow, constraints, or reference material will materially improve the result. Explicit requests remain binding.

## Selection

1. Honor the user's explicit skill request. A named skill is binding unless it is unavailable or conflicts with a higher-priority instruction.
2. For an unrequested skill, compare its trigger to the actual task. Load it when the match is substantive.
3. Prefer the smallest set that covers the work. Load process skills before implementation skills when both are useful.
4. Follow hard safety or correctness invariants in a selected skill. Adapt recommendations and optional workflow to the task and user direction.
5. If a skill proves irrelevant after inspection, set it aside and continue.

When a selected skill declares `requires_skills`, load those dependencies before following it. Dependency loading is binding because those skills supply contracts the selected workflow assumes. This does not make a dependency a reason to select its parent skill.

Skip a skill when the work is trivial, already well-specified, or the skill would add ceremony without reducing meaningful risk. Do not load skills speculatively just because they exist.

## Priority

1. User and repository instructions
2. Hard invariants in deliberately selected skills
3. Skill recommendations
4. Default behavior

In Claude Code, use the Skill tool. On other platforms, use the platform's skill-loading mechanism. See `references/codex-tools.md` for Codex equivalents.
