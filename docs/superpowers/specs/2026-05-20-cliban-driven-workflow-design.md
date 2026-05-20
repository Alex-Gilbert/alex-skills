---
type: spec
status: approved
tags: [skills, cliban, workflow, refactor]
created: 2026-05-20
updated: 2026-05-20
source: brainstorm
---

# Cliban-Driven Workflow Design

> [!abstract]
> Move all spec and plan content out of project repos into cliban. Cliban becomes the system of record for the brainstorm → plan → execute → finish lifecycle. The skill suite is rewritten to read and mutate cliban issues instead of writing markdown files to `docs/superpowers/specs/` and `docs/superpowers/plans/`. Linear integration is retired. Cliban grows seven small CLI additions and a new convention-layer skill ties it all together.

## Background and Motivation

Today the brainstorm/writing-plans skills produce two markdown files per body of work and commit them to the project repo. That clutters every project with `docs/superpowers/specs/*.md` and `docs/superpowers/plans/*.md`. The user already does informal work tracking in cliban (CLI, COOK, SHH projects); cliban issue descriptions already hold rich markdown content (e.g., COOK-1 carries a full status section, COOK-2 carries a bug analysis). Two things drove the refactor:

1. **Spec/plan files do not belong in the code repo.** They drift, get stale, and the diff between "spec" and "code" is rarely interesting after a body of work ships.
2. **The user owns cliban.** We can change the tool, not just the workflow.

The result: cliban becomes the system of record. Project repos contain only code.

## Primitive Model

Four nodes, no more:

| Node | Purpose | Cliban support today |
|---|---|---|
| **Project** | Product / repo / long-lived scope | Exists |
| **Milestone** | Bundle of work — release, theme, or epic. Optional target date. | Exists (needs `description` field — see Cliban CLI Extensions) |
| **Issue** | A body of work. Carries a spec. May carry a plan. | Exists |
| **Sub-issue** | Part of an issue. Cliban caps at depth 2. | Exists |

> [!note]
> Specs and plans are **content sections inside the description** of one of these nodes — not separate primitives. The brainstorm skill picks the right node based on scope.

"Epic" is not a separate node type. An epic is either a Milestone (bundle of issues) or a parent Issue (one body of work with sub-pieces). The skills never need to distinguish.

## Workflow Lifecycle

A piece of work moves through cliban nodes via this skill chain. Nothing writes to project repos.

| Step | Skill | What touches cliban |
|---|---|---|
| Capture | `/idea` (unchanged) | nothing — stays in vault |
| Promote idea to work | `/ticket` (rewritten) | Creates Issue in active project, status `backlog` |
| Design | `brainstorming` (rewritten) | Edits chosen node's description: adds `## Spec`. Scope determines node: Project / Milestone / Issue. Creates the node if absent. |
| Plan | `writing-plans` (rewritten) | Edits Issue description: adds `## Plan`. Promotes oversized steps to sub-issues. |
| Execute | `executing-plans` / `subagent-driven-development` (rewritten) | Walks `## Plan` checkboxes. Moves Issue `backlog → in-progress`. Ticks each step. New Issues for bugs (with `blocks` / `related-to`). |
| Finish | `finishing-a-development-branch` (rewritten) | Moves Issue `in-review` on PR open, `done` on merge. Archive via per-project policy. |

Cross-cutting skills updated: `/bugs`, `/status`, `session-end`. `linear-integration` deleted. See **Per-Skill Changes** below.

## Data Layout Conventions

The skills depend on a parseable description structure. These conventions are binding.

### Issue description template

```markdown
## Spec

[brainstorming output — free-form markdown, may contain H3+ subsections]

## Plan

### Task 1: [name]
**Files:**
- Create: `exact/path.py`
- Test: `tests/path.py`

- [ ] **Step 1: Write failing test**
  ```python
  def test_thing(): ...
  ```
- [ ] **Step 2: Run it; expect FAIL**
- [ ] **Step 3: Implement**

### Task 2: [name]
…

## Activity Log

- 2026-05-20T13:42Z — Step 3 of Task 1 promoted to SHH-18 (substantial work)
- 2026-05-21T09:15Z — bug discovered while executing Task 2 → SHH-19
```

### Milestone description template

```markdown
## Spec

[what this milestone delivers, why, scope, non-goals]
```

### Project description template

```markdown
## Spec

[architecture overview, vision, long-lived constraints]

## Notes

[ongoing notes that outlive any single milestone]
```

### Binding conventions

1. Top-level H2 anchors: `## Spec`, `## Plan`, `## Activity Log`, `## Notes`. Skills locate sections by exact match.
2. Plan tasks are H3 `### Task N: <name>`. Numbered. Skills walk tasks in order.
3. Steps are GFM checkboxes — `- [ ]` and `- [x]`. No alternate syntax.
4. **Promotion suffix**: a step pointing to a separate issue uses `→ KEY`: `- [ ] Step 3: CSRF middleware → SHH-18`. When the linked issue is moved to `done`, the workflow skill that moves it (`executing-plans` / `finishing-a-development-branch`) is responsible for also calling `cliban issue tick` on the referencing step in the parent. Cliban core does not auto-mirror this state — the mirroring is the skill's job, kept out of cliban to avoid coupling the core to the description-parsing contract.
5. No markdown frontmatter inside descriptions. Cliban metadata (status, priority, labels, milestone) is the frontmatter.

> [!warning] Strict failure on broken structure
> If a description's `## Plan` anchor is missing or `### Task N` is renamed, the new mutation commands (`tick`, `promote`, `log`) exit 2 with a clear error. They never attempt best-effort recovery. The user must fix the description before retrying.

## Per-Skill Changes

### `brainstorming` — major rewrite

Adds two early steps before the existing process:

1. **Detect active project.** Try, in order: (a) match the current git repo's `basename $(git rev-parse --show-toplevel)` against project keys/names from `cliban project ls --json`; (b) if no match, list all projects and ask the user which one (or whether to create a new project). The match is best-effort — case-insensitive against both `key` and `name`.
2. **Scope question.** *"Project-level, milestone-level, or issue-level?"* Branches the rest of the conversation:
   - Project-scoped → `cliban project add` (if new) + writes `## Spec` to project description on approval.
   - Milestone-scoped → `cliban milestone add --description-file -` + offers to create kickoff Issues.
   - Issue-scoped → `cliban issue add --description-file -` with `## Spec` content.

Removes all `docs/superpowers/specs/` writes. Removes "commit the design doc" step. Keeps clarifying questions, 2-3 approaches, design sections, self-review gate. Hand-off becomes: *"Issue SHH-12 created with spec. Ready to write the plan?"*

### `writing-plans` — major rewrite

Operates on a cliban Issue key (passed in, or inferred via `cliban issue current`).

1. Reads the Issue's `## Spec` via `cliban issue show KEY --section spec --json`.
2. Writes the `## Plan` section into the description via `cliban issue edit KEY --description-file -` (round-trips full description, preserving Spec + Activity Log).
3. Removes all `docs/superpowers/plans/` writes.
4. Self-review and hand-off unchanged.

### `executing-plans` — major rewrite

Operates on a cliban Issue key.

1. `cliban issue mv KEY in-progress` on start.
2. For each Task → each Step: execute → `cliban issue tick KEY --task N --step M` → run verification.
3. When a step is too big: `cliban issue promote KEY --task N --step M --title "…" --as sub-issue` and recurse on the new sub-issue.
4. When a bug surfaces: `cliban issue add --project X --title "…" --blocks KEY --label bug` + `cliban issue log KEY "bug surfaced: SHH-19"`.
5. Hands off to `finishing-a-development-branch` when all tasks done.

### `subagent-driven-development` — major rewrite

Same as `executing-plans` but dispatches each Task to a fresh subagent. The subagent receives the Issue key + Task number, uses `cliban issue tick` to mark its steps, returns. Two-stage review unchanged.

### `finishing-a-development-branch` — updated

- On PR creation: `cliban issue mv KEY in-review` + `cliban issue log KEY "PR opened: <url>"`.
- On local merge: `cliban issue mv KEY done`.
- On discard: `cliban issue log KEY "work discarded"`. Status preserved.
- Archive sweep unchanged (`cliban issue archive-done --auto` per project policy).

### `ticket` — rewritten

Was Linear-only. Now creates a cliban Issue through the existing 3-phase conversation. Drops `$LINEAR_TEAM` check. Output: `Created SHH-12: <title>` instead of a Linear URL.

### `bugs` — rewritten

- `/bugs add` creates a cliban Issue with `label=bug`.
- `/bugs list` is `cliban issue ls --label bug --json` (cross-project, or per-project with `--project KEY`).
- `/bugs resolve KEY` is `cliban issue mv KEY done`.
- The memory/vault side stays for non-trivial bugs that deserve a knowledge entry. Cross-link: `Cliban: SHH-19` in the memory file, vault path in the issue description.

### `status` — rewritten

Replaces the vault-walking implementation with cliban queries:

- `cliban project ls --json`
- `cliban issue ls --status in-progress --json`
- `cliban issue blocked --json`

Active-projects view becomes the cliban project list, progress summarized from issue counts per status.

### `session-end` — small update

Appends a "Cliban activity" section to the session summary: `cliban issue ls --updated-since <session-start> --json`. Lists issues created/moved/ticked during the session.

### `linear-integration` — deleted

Skill folder removed. `requires_skills: [linear-integration]` declarations stripped from all skills. `LINEAR_TEAM` / `LINEAR_PROJECT` env vars removed from `.claude/settings.json` if present.

### Unchanged

`idea`, `shape`, `remember`, `recall`, `obsidian-markdown`, `using-git-worktrees`, `systematic-debugging`, `test-driven-development`, `writing-skills`, `requesting-code-review`, `receiving-code-review`, `repo-standards`, `verification-before-completion`, `dispatching-parallel-agents`, `using-superpowers`.

## Cliban CLI Extensions

Eight additions. All small. None break existing commands.

| # | Change | Surface |
|---|---|---|
| 1 | Milestone descriptions | New `description` field on milestone records. `cliban milestone add/edit --description` and `--description-file`. `cliban milestone show --json` includes it. |
| 2 | `cliban issue tick KEY --task N --step M --json` | Atomic checkbox toggle inside the `## Plan` section. Exit 2 if no Plan / no Task N / no Step M / already ticked. |
| 3 | `cliban issue promote KEY --task N --step M --title "…" --as sub-issue\|related` | Creates new issue, rewrites the step line to `→ NEWKEY`. Returns the new issue. |
| 4 | `cliban issue log KEY <message> [--message-file -] --json` | Atomic chronological append to `## Activity Log` (creates section if absent). UTC-stamped. |
| 5 | `cliban issue ls --updated-since <duration\|timestamp>` | E.g. `--updated-since 4h` or `--updated-since 2026-05-20T00:00Z`. Filters by `updated_at`. Powers `session-end`. |
| 6 | `cliban issue show --section spec\|plan\|activity` | Returns just one H2 section's content. Skills use this for targeted reads. No `--section` → unchanged behavior. |
| 7 | `cliban issue show --pager` / `cliban view KEY` | Pipes rendered output through `$PAGER` (or `glow` if `$CLIBAN_RENDERER=glow`). Quality-of-life only. |
| 8 | `cliban issue current --json` | Infers active issue from current git branch name (cliban auto-generates these like `shh-12-add-device-linking`; this is the reverse). Exit 1 on no match. |

> [!warning] Parseable-description contract
> Cliban now has *opinions* about the markdown structure of descriptions. `tick`, `promote`, `log` parse the description, mutate it, write it back. The contract must be documented prominently in the cliban README alongside the skill suite. Strict exit-2 failure on structural violations — no best-effort recovery.

### Concurrency

All three new mutations (`tick`, `promote`, `log`) are atomic via SQLite write-serialization. Concurrent ticks on the same step: the second exits 2 ("step already checked"); the skill treats that as success and proceeds.

## The `cliban-workflow` Convention Layer

A new skill at `skills/cliban-workflow/SKILL.md`. Loaded via `requires_skills: [cliban-workflow]` from the eight rewritten skills. Mirrors the old `linear-integration` shape.

What it provides:

1. **Detection and graceful degradation.** Checks `cliban --version` on `$PATH`. If absent, host skill silently skips cliban actions (workflow continues, just without tracking). Same gate as the old Linear layer.
2. **The parseable-description contract.** H2 anchor names, task/step structure, `→ KEY` promotion convention. One canonical doc.
3. **The mutation command vocabulary.** `tick`, `promote`, `log`, plus standard reads (`show`, `ls --json`).
4. **Status mapping.** Workflow event → cliban status:
   - Plan written → `backlog`
   - First step picked up → `in-progress`
   - PR opened → `in-review`
   - PR merged / local merge → `done`
   - Discarded → keep current status, log entry
5. **Active-issue resolution.** Try `cliban issue current --json`; fall back to asking user for KEY.
6. **Cross-project conventions.** Labels (`bug`, `feature`, `refactor`, `chore`), priority defaults (`medium`), parent/relation rules (one `blocks` per blocking issue, `related-to` for soft links). Cliban auto-creates missing labels on `issue add` / `issue edit --label`, so skills don't need to pre-create them — but they also don't get garbage-collected when the last issue referencing them is deleted, so prefer the canonical set above and only invent new ones when they have ongoing meaning.
7. **What NOT to do.** Negative space: don't parse table output, don't nest sub-issues 3 deep, don't mutate descriptions outside `tick`/`promote`/`log` for structured sections.

The dependent skills shrink because they no longer carry cliban vocabulary themselves — they reference the convention layer.

## Migration

> [!tip] No migration script
> Volume is small (~5-10 spec/plan files across all projects). Existing artifacts already referenced from cliban issues (e.g., COOK-1 → `cook/docs/superpowers/plans/2026-05-19-doom3-plan-5-dhewm3-bringup.md`). Moving them would orphan those references. New work flows through cliban; existing artifacts stay where they are.

Actions taken during rollout:

- Delete `docs/superpowers/specs/` and `docs/superpowers/plans/` from `alex-memory` once any specs the user wants in cliban are migrated by hand.
- Add a single-line note to project READMEs that mention specs/plans: *"Specs and plans live in cliban (`cliban issue show <KEY>`)."*

## Error Handling

| Failure | Behavior |
|---|---|
| `cliban` not on `$PATH` | Convention layer detects. All skills silently skip cliban actions. Workflow continues without tracking. |
| Cliban DB missing or corrupt | Cliban returns exit 3. Convention layer surfaces "cliban DB error — see `cliban init`" once per session, then degrades to no-cliban mode. |
| Description hand-edited, `## Plan` anchor missing | `tick`/`promote` exit 2 with clear message ("no ## Plan section in SHH-12 — fix description before retrying"). Skill stops and reports. **Strict; no recovery.** |
| Two agents tick concurrently | SQLite serializes writes. Second `tick` to same step exits 2 ("step already checked"). Skill treats as success and moves on. |
| `cliban issue current` finds no match | Exit 1. Convention layer prompts user for KEY. |
| Promotion target title collides with existing issue | Cliban creates a new issue regardless (titles aren't unique). No special handling. |

## Testing Strategy

Three layers, scaled to risk.

1. **Cliban CLI additions.** Unit + integration tests in the `cliban` repo (Go). The atomic mutations (`tick`, `promote`, `log`) need concurrency tests: N goroutines hitting the same issue, assert SQLite serialization holds and final state is consistent.
2. **Convention layer and rewritten skills.** No automated skill harness today. Verification is a manual golden-path smoke test: a script that walks `/brainstorm → /writing-plans → /executing-plans → /bugs add → finishing-a-development-branch` on a throwaway cliban project, asserting cliban state at each transition.
3. **Graceful degradation.** Manual: temporarily move `cliban` off `$PATH`, run `/brainstorm`, confirm completion without errors.

## Rollout Order

Sequential because skills depend on cliban additions and on the convention layer.

1. Ship the eight cliban CLI additions. Tests in the cliban repo.
2. Write the `cliban-workflow` convention-layer skill.
3. Rewrite skills in dependency order, one commit per skill:
   - `brainstorming` (most-used; do first)
   - `writing-plans`
   - `executing-plans` + `subagent-driven-development` (siblings; do together)
   - `ticket`
   - `bugs`
   - `status`
   - `finishing-a-development-branch`
   - `session-end` (small update last)
4. Delete `linear-integration` skill.
5. Remove `LINEAR_TEAM` / `LINEAR_PROJECT` env vars from `.claude/settings.json` if present.
6. Run the golden-path smoke test on a throwaway cliban project.

Each step is independently shippable. If the rewrite stalls partway, the unchanged skills keep working: cliban additions are non-breaking, and the convention layer is opt-in via `requires_skills:`.

## Stress Tests

Concerns surfaced and resolved during brainstorm. Recorded so future-me can audit the resolution.

| ID | Concern | Resolution |
|---|---|---|
| ST-1 | "Brainstorm produces a list of milestones." | Brainstorm detects project scope. Creates/selects Project, creates each Milestone with a description, optionally creates anchor Issues. Required milestone `description` field (Cliban Extension #1). |
| ST-2 | "What about epics specifically?" | No separate Epic node. An epic is either a Milestone (bundle of issues) or a parent Issue (one body of work with sub-pieces). Skills create the right cliban node for the scope. |
| ST-3 | "Spec for the whole project — where?" | Project's `description`. Cliban already supports project descriptions and accepts markdown. Pager / renderer addition (Cliban Extension #7) makes reading long specs ergonomic. |
| ST-4 | "Plan has 30 bite-sized steps." | Steps live as `- [ ]` checkboxes inside the Issue description. Board stays uncluttered. Per-step state lost, but writing-plans intentionally makes steps 2-5 min, so per-step kanban tracking is overkill. The Issue itself moves through statuses. |
| ST-5 | "A plan step turns out to be huge." | Promote to sub-issue (or top-level Issue with `related-to` if independent). Promotion command (Cliban Extension #3) rewrites the step line to `→ KEY`. |
| ST-6 | "Cliban depth-2 cap." | Sub-issues can't have sub-issues. If a sub-issue needs sub-pieces, promote to top-level Issue with `related-to` link back. We don't fight the cap. |
| ST-7 | "Diagrams, attachments." | No attachment support in cliban. For now: embed images via path reference in markdown. Acceptable for solo workflow. Future cliban extension; not blocking. |
| ST-8 | "Spec evolves mid-execution." | Edit the Issue description in place. No versioning. For revision tracking, append a `## Revision Log` section or rely on cliban's `updated_at` timestamp. Versioned description history is out of scope. |
| ST-9 | "Cliban DB lost / switching machines." | Single SQLite file. Should be in a synced location or backed up. Orthogonal concern; out of scope for this design but flag in the cliban README. |
| ST-10 | "Reviewing an old spec months later." | `cliban issue show KEY --pager` or `cliban view KEY` (Cliban Extension #7). Terminal-friendly reading of long descriptions. |

## Out of Scope

Recorded so we don't scope-creep this design.

- **Cliban attachments** (images, diagrams, binary files). Future cliban work; embed via path references for now.
- **Description versioning / history.** Cliban tracks `updated_at` but not per-edit diffs. Out of scope.
- **Cross-machine cliban sync.** Single SQLite file; user manages sync.
- **Team-collab features.** Cliban is single-user. Linear handed off this responsibility; not replaced.
- **Migration script for existing specs/plans.** Volume too low. Hand-migrate any worth keeping.
- **Skill harness for automated testing.** Manual golden-path smoke test for now.
- **Automated bidirectional sync between cliban and any other tracker.** Cliban is the single source of truth.
