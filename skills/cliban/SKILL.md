---
name: cliban
description: Use when the user mentions cliban, kanban, tickets, issues, projects, or milestones, or asks you to capture, list, or move work items — drives the local cliban CLI for self-hosted task tracking.
---

# Using cliban

`cliban` is a self-hosted, terminal-first kanban board with a flat CLI.
**Always use `--json` for reads** — never parse the human table format. The
default no longer opens an editor; mutations are safe to run unattended.

## Vocabulary

- **Statuses**: `backlog` | `in-progress` | `blocked` | `in-review` | `done`
- **Priorities**: `none` | `low` | `medium` | `high` | `urgent`
- **Issue keys**: `{PROJECT}-{N}` like `CLI-42` (project key is uppercase letters/digits, 2-10 chars starting with a letter).
- **Sub-issues**: depth limited to 2 — a sub-issue cannot have its own children. The CLI returns exit code 2 if you try to nest a third level.
- **Relations**: `blocks`, `blocked_by` (reverse of `blocks`), `related_to` (symmetric).
- **Labels**: free-form tags per project.

## JSON shapes (stable)

Optional refs are emitted as JSON `null` rather than omitted, so destructuring is safe:

```json
{
  "key":             "CLI-42",
  "title":           "...",
  "description":     "...",
  "status":          "backlog",
  "priority":        "high",
  "position":        12000.5,
  "archived":        false,
  "milestone":       "v0.1" | null,
  "parent":          "CLI-3" | null,
  "due_date":        "2026-06-01" | null,
  "labels":          ["bug", "ui"],
  "relations":       [{"type": "blocks", "target": "CLI-9"}],
  "git_branch_name": "cli-42-fix-column-ordering",
  "created_at":      "2026-...Z",
  "updated_at":      "2026-...Z"
}
```

- `cliban issue show KEY --json` → one pretty-printed object.
- `cliban issue ls --json` → one **compact** JSON object **per line** (NDJSON). Parse with `for line in stdout.splitlines(): json.loads(line)` or `jq -c`.
- `cliban milestone ls --json`, `cliban project ls --json`, `cliban label ls --json` are also NDJSON.

## DB location

`$XDG_DATA_HOME/cliban/cliban.db` by default (falls back to `~/.local/share/cliban/cliban.db`). Override with `--db <path>` or `$CLIBAN_DB`.

## Common recipes

### Create a project
```bash
cliban project add CLI --name "Cliban" --description "kanban board"
```

### List projects (NDJSON)
```bash
cliban project ls --json
```

### Capture a new issue
```bash
cliban issue add --project CLI \
  --title "Fix the kanban column ordering" \
  --description "When more than 5 cards exist in IN-REVIEW, positions go negative." \
  --priority high --due 2026-06-01 \
  --label bug --label ui \
  --blocked-by CLI-3 --related-to CLI-7 \
  --json
```

### Bulk-import from NDJSON
```bash
cliban issue import /path/to/issues.ndjson --json
# or stream:
cliban issue import - < /path/to/issues.ndjson --json
```
Per-line schema: `{"project":"CLI","title":"...","description":"...","status":"...","priority":"...","milestone":"...","parent":"CLI-1","labels":["a","b"]}`.
Pass `--project KEY` to set a default project for records that omit it.

### Add a sub-issue
```bash
cliban issue add --project CLI --parent CLI-12 \
  --title "Repro test" --priority medium --json
```

### Multi-line description
```bash
cliban issue add --project CLI --title "Plan" --description-file ./plan.md
# stdin still works:
cliban issue edit CLI-12 --description - < /tmp/desc.md
```

### Move work along
```bash
cliban issue mv CLI-12 in-progress
cliban issue mv CLI-12 done
```

### Set or clear a milestone
```bash
cliban milestone add --project CLI --name "v0.1" --target 2026-06-01
cliban milestone show v0.1 --project CLI --with-issues --json    # positional NAME
cliban issue edit CLI-12 --milestone "v0.1"
cliban issue edit CLI-12 --clear-milestone
```

### Labels
```bash
cliban label add bug --project CLI
cliban issue edit CLI-12 --label bug --label cook-cc
cliban issue ls --project CLI --label bug --json    # filter (all-of)
cliban issue edit CLI-12 --remove-label cook-cc
```

### Issue relations
```bash
cliban issue edit CLI-12 --blocks CLI-9
cliban issue edit CLI-12 --blocked-by CLI-3
cliban issue edit CLI-12 --related-to CLI-7

cliban issue blocked --project CLI --json   # issues that have an open blocker
cliban issue edit CLI-12 --remove-relation CLI-9
```

### Sorting on `ls`
```bash
cliban issue ls --project CLI --sort priority --json          # urgent first (default desc)
cliban issue ls --project CLI --sort created:asc --json
cliban issue ls --project CLI --sort updated:desc --json
cliban issue ls --project CLI --sort position --json
```

### Inspect a single issue
```bash
cliban issue show CLI-42 --json
```

### Delete (cascades sub-issues)
```bash
cliban issue rm CLI-12
```

### Archive
```bash
cliban issue archive CLI-12
cliban issue unarchive CLI-12
cliban issue archive-done --project CLI --json
# Per-project auto-archive policy:
cliban project edit CLI --auto-archive-done-after 7d
cliban issue archive-done --auto --json    # sweeps every project per its policy
```

### Query archived issues
```bash
cliban issue ls --project CLI --archived --json
```

## Editor behavior (agent-safe by default)

`cliban issue add` and `cliban issue edit` **never open an editor by default**.
You must pass `--editor` (or `-e` for `edit`) to opt in. Without `--editor`,
`add` requires `--title`; `edit` requires at least one mutation flag — both
fail with exit code 2 otherwise. The legacy `--no-editor` flag is still
accepted (hidden, no-op) for backwards compatibility.

## Exit codes

- `0` success
- `1` not found
- `2` validation error (invalid status, depth-2 violation, missing required flag, etc.)
- `3` internal/db error

## What NOT to do

- Don't try to parse the table output of `ls`/`show`. Use `--json`.
- Don't nest sub-issues three levels deep; the CLI returns exit code 2.
- Don't filter on archived state by hand — pass `--archived` to `ls` to include them; otherwise they are excluded.
- Don't assume timestamps are in the local timezone — they are UTC ISO-8601.
- Don't pass `--editor` in an agent context unless you actually have a TTY; it will fail with exit code 2 if stdin isn't a TTY.

## Discovery checklist

When the user gives a vague kanban-related task, run these reads first to ground yourself in the current state:

```bash
cliban project ls --json
cliban issue ls --status in-progress --json
cliban issue ls --status blocked --json
cliban issue blocked --json    # what's stuck on something
```
