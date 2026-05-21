---
name: writing-plans
description: "Use when you have a spec for a multi-step task, before touching code. Writes the implementation plan into the corresponding cliban issue's ## Plan section."
requires_skills: [cliban-workflow]
---

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch, code, testing, docs they might need to check, how to test it. Give them the whole plan as bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well.

**The plan is written into the cliban Issue's `## Plan` section** — NOT to a markdown file in `docs/superpowers/plans/`.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

## Inputs

This skill operates on a single cliban Issue. Resolve the key in this order:

1. Argument passed by the invoking skill (typically the brainstorming hand-off)
2. `cliban issue current --json` (current git branch)
3. Ask the user

Then read the spec:

```bash
cliban issue show <KEY> --section spec
```

If there is no `## Spec` section, ask the user to run brainstorming first, or ask them to paste the spec content so you can populate it.

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken into sibling issues during brainstorming. If it wasn't, suggest stopping and decomposing — each plan should produce working, testable software on its own.

For substantial multi-phase work, suggest creating sibling issues (via /ticket or by editing the milestone). Don't write a 50-task plan on one issue.

## File Structure (in the codebase)

Before defining tasks, map out which files in the target project repo will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces. Each file should have one clear responsibility.
- Files that change together should live together. Split by responsibility, not by technical layer.
- In existing codebases, follow established patterns. If a file you're modifying has grown unwieldy, including a split in the plan is reasonable — but don't propose unrelated refactoring.

This structure informs the task decomposition. Each task should produce self-contained changes that make sense independently.

## Bite-Sized Task Granularity

**Each step is one action (2-5 minutes):**
- "Write the failing test" — step
- "Run it to make sure it fails" — step
- "Implement the minimal code to make the test pass" — step
- "Run the tests and make sure they pass" — step
- "Commit" — step

## Plan Structure Inside the Issue Description

The full description after writing-plans should look like:

```markdown
## Spec

<existing spec content from brainstorming>

## Plan

### Task 1: <component name>

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

- [ ] **Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

- [ ] **Step 3: Write minimal implementation**

```python
def function(input):
    return expected
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```

### Task 2: <next component>

...
```

Tasks are H3 with numbered titles. Steps are GFM checkboxes at column zero (no nested indentation as a step). The contract is binding — see the `cliban-workflow` skill.

## No Placeholders

Every step must contain the actual content an engineer needs. These are **plan failures** — never write them:
- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases"
- "Write tests for the above" (without actual test code)
- "Similar to Task N" (repeat the code — the engineer may be reading tasks out of order)
- Steps that describe what to do without showing how (code blocks required for code steps)
- References to types, functions, or methods not defined in any task

## Writing the Plan to Cliban

1. Round-trip the full description (preserving `## Spec` and any `## Activity Log`):

```bash
# Read current description
cliban issue show <KEY> --json | jq -r '.description' > /tmp/desc.md

# Author the new description, inserting/replacing `## Plan` between `## Spec`
# and `## Activity Log` (or at end of doc if neither anchor exists).
# Then write it back:
cliban issue edit <KEY> --description-file /tmp/desc.md
```

2. After writing, verify the plan section parses cleanly:

```bash
cliban issue show <KEY> --section plan | head -20
```

If `cliban issue show --section plan` returns exit code 1 ("no ## Plan section"), the plan didn't land — review the description for structural issues and retry.

## Self-Review

After writing the complete plan, look at the spec with fresh eyes and check the plan against it. Run yourself — not a subagent.

**1. Spec coverage:** Skim each section/requirement in the spec. Can you point to a task that implements it? List any gaps.

**2. Placeholder scan:** Search your plan for red flags — any of the patterns above. Fix them.

**3. Type consistency:** Do types, signatures, and property names you used in later tasks match what you defined in earlier tasks? `clearLayers()` in Task 3 but `clearFullLayers()` in Task 7 is a bug.

If you find issues, fix them inline. Re-write the description if needed.

## Execution Handoff

After saving the plan, offer execution choice:

> **"Plan written to cliban issue `<KEY>`. View with `cliban issue show <KEY> --section plan --pager`. Two execution options:**
>
> **1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration
>
> **2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints
>
> **Which approach?"**

**If Subagent-Driven chosen:**
- **REQUIRED SUB-SKILL:** Use `superpowers:subagent-driven-development`
- Fresh subagent per task + two-stage review

**If Inline Execution chosen:**
- **REQUIRED SUB-SKILL:** Use `superpowers:executing-plans`
- Batch execution with checkpoints for review

## Anti-Patterns

- **DO NOT** write `docs/superpowers/plans/*.md`. The plan lives in the cliban issue description.
- **DO NOT** commit the plan as a file in the project repo. The repo stays code-only.
- **DO NOT** invoke writing-plans on an issue that has no `## Spec` — go back to brainstorming first.
