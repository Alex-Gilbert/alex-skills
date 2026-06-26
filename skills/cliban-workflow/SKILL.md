---
name: cliban-workflow
description: "Convention layer for cliban-based workflow management. Loaded by workflow skills via requires_skills to provide cliban command vocabulary, status mapping, and the parseable-description contract."
---

# Cliban Workflow — Convention Layer

This skill is loaded automatically by workflow skills that declare `requires_skills: [cliban-workflow]`. It teaches when and how to use the cliban CLI for the brainstorm → plan → execute → finish workflow.

## Detection and Graceful Degradation

Before performing ANY cliban action, check availability:

1. **Probe `cliban version`.** If the command is not on `$PATH` (non-zero exit / "command not found"), skip all cliban actions silently for this session. Do not warn, do not suggest install, do not block the workflow.
2. **If the probe succeeds, attempt the first real cliban call.** If it fails (DB missing, schema mismatch, exit 3), surface the error once with `"cliban error: <message> — try 'cliban init' or check $CLIBAN_DB"` and then skip remaining cliban actions this session. Do not retry.

<IMPORTANT>
Cliban integration is REQUIRED for the new workflow but the SKILLS must still function for users who haven't installed cliban yet. Workflow skills fall back to local-file behavior only if explicitly directed; otherwise they error clearly with the cliban setup instruction above.
</IMPORTANT>

## Vocabulary

Cliban's primitives are:

- **Project** — top-level scope. Identified by uppercase key (e.g. `SHH`, `COOK`).
- **Milestone** — bundle of issues. Named per project, optional target date.
- **Issue** — body of work. Key shape: `{PROJECT}-{N}` (e.g. `SHH-12`).
- **Sub-issue** — depth-limited to 2. Use `--parent KEY` on `issue add`.
- **Labels** — free-form per project (auto-created on first use).
- **Relations** — `blocks`, `blocked_by`, `related_to` (symmetric).

## Status Mapping

| Workflow event | Cliban status |
|---|---|
| Plan written | `backlog` |
| First step picked up | `in-progress` |
| Stuck on dependency | `blocked` |
| PR opened | `in-review` |
| PR merged / local merge | `done` |
| Discarded / abandoned | keep current status, append log entry |

## Active-Project Resolution

When a workflow skill needs a project context:

1. Try `basename $(git rev-parse --show-toplevel)` and match (case-insensitive) against `cliban project ls --json` results (both `key` and `name`).
2. If no match, list projects and ask the user which one — or whether to create a new project.

```bash
REPO=$(basename "$(git rev-parse --show-toplevel)" 2>/dev/null | tr '[:lower:]' '[:upper:]')
cliban project ls --json | jq --arg r "$REPO" 'select(.key==$r or (.name|ascii_upcase)==$r)'
```

## Active-Issue Resolution

When a workflow skill needs the current issue:

1. Try `cliban issue current --json` (reads current git branch, parses the cliban-style prefix).
2. If exit code 1, ask the user for the issue KEY.

## Parseable-Description Contract

Issue (and milestone/project) descriptions follow a strict markdown contract that several cliban commands parse:

```markdown
## Spec

[brainstorming output — free-form markdown]

## Plan

### Task 1: short name
**Files:** ...

- [ ] **Step 1: ...**
- [ ] **Step 2: ...**

### Task 2: short name
...

### Review Checkpoint: scope of the group above

### Task 3: short name
...

## Activity Log

- 2026-05-20T13:42Z — chronological entry
- 2026-05-21T09:15Z — another entry

## Notes

[long-lived notes, mostly on project descriptions]
```

Binding conventions:

1. Top-level anchors: `## Spec`, `## Plan`, `## Activity Log`, `## Notes`. Exact-match.
2. Plan tasks: H3 `### Task <N>: <name>`. Numbered uniquely.
3. Plan steps: GFM checkbox lines at column zero (`- [ ] ...` or `- [x] ...`). Indented child bullets are NOT steps.
4. Review checkpoints: H3 `### Review Checkpoint: <scope>`. No steps, no number — a marker between task groups telling the executor where to batch its review. `tick`/`promote` ignore them.
4. Promotion suffix: a step pointing to a separate issue is rewritten as `- [ ] Step 3: CSRF middleware → SHH-18`.
5. Strict failure: structural violations exit with code 2 — fix the description and retry, no best-effort recovery.

## Mutation Commands (atomic via SQLite)

```bash
# Read one section without round-tripping the whole description:
cliban issue show KEY --section spec|plan|activity|notes

# Atomically flip a plan step's checkbox:
cliban issue tick KEY --task N --step M --json

# Atomically append a timestamped Activity Log entry:
cliban issue log KEY "<message>" --json
cliban issue log KEY --message-file - --json  # stdin

# Promote a step into its own issue and rewrite the step line:
cliban issue promote KEY --task N --step M --title "..." --as sub-issue|related --json
```

Each of these runs in a single SQL transaction. Concurrent calls are serialized.

## Cross-Project Conventions

- **Canonical labels** for `--label`: `bug`, `feature`, `refactor`, `chore`. Cliban auto-creates labels on `issue add --label`; do not pre-create. Orphan labels are not garbage-collected, so prefer the canonical set.
- **Default priority** on issue creation: `medium`. Use `high` / `urgent` only when explicitly indicated.
- **Relations:** use `--blocks` / `--blocked-by` for hard dependencies, `--related-to` for soft references.
- **Promotion-mirror responsibility:** when a promoted child issue moves to `done`, the workflow skill that did the move is responsible for also calling `cliban issue tick` on the referencing step in the parent. Cliban core does NOT auto-mirror — this is the skill's job, deliberately kept out of cliban to avoid coupling the core to the description-parsing contract.

## Workflow Actions by Skill

### Brainstorming
- Detect active project (above)
- Ask scope: project / milestone / issue
- Create the appropriate node with the `## Spec` section in its description

### Writing-plans
- Take or infer an Issue key
- Read spec: `cliban issue show KEY --section spec`
- Write plan via `cliban issue edit KEY --description-file -` (round-trips full description preserving Spec + Activity Log)

### Executing-plans / Subagent-driven-development
- `cliban issue mv KEY in-progress`
- For each step: execute → `cliban issue tick KEY --task N --step M`
- For bugs: `cliban issue add --label bug --blocks KEY` + `cliban issue log KEY "bug surfaced: NEWKEY"`
- For oversized steps: `cliban issue promote KEY --task N --step M --title "..." --as sub-issue`

### Ticket
- `cliban issue add --project KEY --title "..." --priority ...`

### Bugs
- Add: `cliban issue add --label bug --priority ...`
- List: `cliban issue ls --label bug --json`
- Resolve: `cliban issue mv KEY done`

### Status
- `cliban project ls --json`
- `cliban issue ls --status in-progress --json`
- `cliban issue blocked --json`

### Finishing-a-development-branch
- PR opened: `cliban issue mv KEY in-review` + `cliban issue log KEY "PR opened: <url>"`
- Local merge: `cliban issue mv KEY done`
- Discard: `cliban issue log KEY "work discarded"` (keep current status)

### Session-end
- `cliban issue ls --updated-since <session-start> --json` → summarize as a "Cliban activity" section

## What NOT to Do

- Don't parse the human table output of `ls`/`show`. Always use `--json`.
- Don't nest sub-issues three levels deep — cliban exits 2 (use `related_to` instead).
- Don't mutate the structured sections (`## Plan`, `## Activity Log`) outside of `tick`/`promote`/`log`. Hand-editing breaks the contract and the next mutation command exits 2.
- Don't pre-create labels — `issue add --label X` auto-creates.
- Don't pass `--editor` in an agent context — exits 2 without a TTY.
- Don't write spec or plan content to `docs/superpowers/specs/` or `docs/superpowers/plans/` in project repos. Those locations are deprecated under the new workflow.
- **Never write a cliban issue key into source code, comments, commit messages, or any committed artifact.** A cliban key (e.g. `PROJ-42`) is private local tracking metadata — meaningless to anyone reading the repo. Track the work *in cliban* (`tick`/`log`); the key stays out of the code. (A global pre-commit hook enforces this and will block such commits.)
