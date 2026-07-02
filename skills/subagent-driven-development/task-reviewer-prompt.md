# Checkpoint Reviewer Prompt Template

Use this when dispatching a reviewer at a `### Review Checkpoint`. One reviewer pass over the **cumulative diff since the last checkpoint** (which covers all tasks in this checkpoint's group) returns **two verdicts**: spec compliance, then code quality.

**Purpose:** Verify the group of tasks built what was requested (nothing more, nothing less) AND is well-built — in a single dispatch, replacing per-task review.

```
Task tool (general-purpose):
  description: "Checkpoint review: <checkpoint scope>"
  model: fable   # review/bug-finding is fable's strongest documented gain; fall back to opus
  prompt: |
    You are reviewing a batch of completed work at a review checkpoint.

    ## What Was Requested

    [FULL TEXT of every Task in this checkpoint group]

    ## What The Implementers Claim They Built

    [Concatenated implementer reports for the group]

    ## The Diff To Review

    BASE_SHA: [HEAD at the previous checkpoint, or branch base if first]
    HEAD_SHA: [current HEAD]
    Review `git diff BASE_SHA..HEAD_SHA` plus the tests.

    ## CRITICAL: Do Not Trust The Reports

    The reports may be incomplete, optimistic, or wrong. Verify everything by
    reading the actual code and tests — never by trusting a claim.

    ## Verdict 1 — Spec Compliance (per task in the group)

    For each task, reading the code (not the report):
    - **Missing:** anything requested but not implemented (or claimed but absent)?
    - **Extra:** anything built that wasn't requested — over-engineering, unrequested "nice to haves"?
    - **Misunderstood:** right feature, wrong approach, or wrong problem solved?

    Report per task: ✅ compliant, or ❌ with specific `file:line` issues.

    ## Verdict 2 — Code Quality (across the group's diff)

    - Idiomatic style, naming, subtle bugs, edge cases
    - Test coverage gaps
    - File organization: does each file have one clear responsibility and a well-defined interface? Are units independently testable? Does the diff follow the plan's file structure?
    - New/grown files: did THIS change create already-large files or significantly grow existing ones? (Don't flag pre-existing sizes.)

    Report every issue you find, including ones you are uncertain about or
    consider low-severity — the severity labels do the filtering, not omission.

    Report: Strengths, Issues grouped Critical / Important / Minor (each with `file:line`), Assessment.

    ## Output

    SPEC: per-task ✅/❌ list.
    QUALITY: Strengths + Critical/Important/Minor + Assessment.
```

**Acting on the result:**
- Spec ❌ on any task, or any Critical/Important quality issue → re-dispatch the relevant implementer with the specifics, then re-review this checkpoint.
- Only Minor issues → accept; `cliban issue log` if they accumulate across checkpoints.
