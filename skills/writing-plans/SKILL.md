---
name: writing-plans
description: "Use when a specced multi-step issue needs an implementation handoff before coding begins"
requires_skills: [cliban-workflow]
---

# Writing Plans

## Overview

Write a concise behavioral implementation plan that gives a capable engineer the destination, boundaries, and verification strategy while leaving local implementation judgment to them. A plan is a map, not a transcript of code they should copy.

Store the plan in the cliban issue's `## Plan` section, never in `docs/superpowers/plans/`.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

## Inputs

Resolve one issue key from, in order:

1. The invoking skill's argument
2. `cliban issue current --json`
3. The user

Read the spec with `cliban issue show <KEY> --section spec`. If no `## Spec` exists, get a concise spec from the user or use brainstorming when material design choices remain.

## Scope and Context

Inspect the relevant code, tests, project commands, and related durable notes before planning. If the spec contains independent subsystems, decompose it into sibling issues rather than writing one enormous plan.

Apply the ponytail lens to implementation choices: prefer stdlib, native platform features, existing dependencies, existing project patterns, and the fewest files. Do not reopen approved product scope.

## Plan Content

Each task should deliver one coherent, independently understandable behavior. Include only what helps an implementer make the right change:

- **Files:** exact files to create, modify, or test; line anchors only when stable and useful
- **Interfaces:** signatures, schemas, commands, or wire formats when they are constraints
- **Behaviors:** observable outcomes, edge cases, errors, and compatibility requirements
- **Test intent:** what the tests prove and the important cases; preserve test-first ordering
- **Commands:** focused verification and commit commands

Use exact code only when it is truly load-bearing: a public signature, protocol shape, migration invariant, tricky algorithm, or detail where multiple plausible implementations would not be equivalent. Otherwise describe behavior and let the implementer work with the repository.

Tasks should be sized as coherent changes, not decomposed into minutes or one checkbox per keystroke. For every behavior change, preserve this test-first sequence:

- [ ] Add a failing test for the specified behavior and run it to confirm the expected failure.
- [ ] Implement the behavior using the listed files and constraints.
- [ ] Run focused verification, then the relevant broader suite.
- [ ] Commit the coherent change.

Name concrete test cases and expected outcomes, but do not pre-write routine test or implementation bodies.

## Review Checkpoints

The executor (`subagent-driven-development`) reviews at checkpoints, not after every task. Insert this H3 marker between task groups:

```markdown
### Review Checkpoint: <scope of completed group>
```

Place a checkpoint at the first of:

- a coherent feature, layer, or phase is complete;
- the unreviewed group spans several files or a few hundred lines; or
- later tasks will stack on a foundational schema, interface, or security decision.

Do not checkpoint every task or wait until the entire plan is complete. A typical plan has one every 3–5 tasks or at phase boundaries. The end of the plan is an implicit checkpoint.

## Cliban Format

```markdown
## Spec

<existing approved spec>

## Plan

### Task 1: <behavioral outcome>

**Files:**
- Modify: `src/existing.rs`
- Test: `tests/behavior.rs`

**Interfaces:** `parse(input: &str) -> Result<Value, ParseError>`

**Behaviors:**
- Valid input returns the parsed value.
- Invalid input reports the byte offset without panicking.

**Test intent:** Prove valid parsing, boundary offsets, and malformed-input errors.

**Commands:** `cargo test --test behavior`; `cargo test`; `git commit -m "feat: parse values"`

- [ ] Add the failing behavior tests and verify the expected failure.
- [ ] Implement the parser behavior and error contract.
- [ ] Run focused and full verification.
- [ ] Commit the coherent change.

### Review Checkpoint: parsing contract

### Task 2: <next outcome>
...
```

Tasks use unique numbered H3 headings. Steps are GFM checkboxes at column zero. Checkpoint headings have no task number or steps. This is a binding parser contract shared with `cliban-workflow`.

## No Placeholders

Never leave `TBD`, `TODO`, “implement later,” vague “add error handling,” undefined interfaces, or “similar to Task N.” Be specific about required behavior without prescribing routine code.

## Write and Verify

Round-trip the full description so `## Spec`, `## Activity Log`, and other sections survive:

```bash
cliban issue show <KEY> --json | jq -r '.description' > /tmp/desc.md
# Insert or replace ## Plan in /tmp/desc.md.
cliban issue edit <KEY> --description-file /tmp/desc.md
cliban issue show <KEY> --section plan
```

## Fresh-Context Plan Review

After the plan parses, dispatch a fresh-context verifier using `plan-document-reviewer-prompt.md`. Give it the issue key and repository path, but not the planning conversation. It independently reads the spec and plan from cliban and checks:

1. every spec requirement maps to a task;
2. interfaces and behavior remain consistent across tasks;
3. test intent is sufficient to catch wrong behavior;
4. dependencies and review checkpoints are ordered safely;
5. no placeholder, scope creep, or needless abstraction remains.

Fix blocking findings in the plan and ask the verifier to re-check. Advisory style preferences do not block execution. Fresh context is the point: do not replace this step with same-context self-review.

## Execution Handoff

After review, proceed directly:

> **"Plan written to cliban issue `<KEY>`. View with `cliban issue show <KEY> --section plan --pager`. Proceeding with subagent-driven execution."**

**REQUIRED SUB-SKILL:** Use `alex-skills:subagent-driven-development`. If the user explicitly wants inline execution, use `alex-skills:executing-plans` instead.

## Anti-Patterns

- Do not commit plans or specs to the project repo.
- Do not turn a plan into pre-written routine implementation.
- Do not plan an issue with neither a spec nor enough user-provided behavior to remove material ambiguity.
