---
name: bugs
description: "Bug tracking via cliban (issues with label=bug) + optional memory entry for knowledge. Use when user invokes /bugs to list, filter, add, or resolve bugs."
requires_skills: [obsidian-markdown, cliban-workflow]
---

# Bugs — Bug Management

Bugs are tracked as cliban issues with the `bug` label. Non-trivial bugs may also have a memory vault entry capturing the knowledge (root cause analysis, repro context). The cliban issue is the ticket; the memory file is the knowledge.

## Subcommands

### `/bugs` (no args)

List all open bugs across all projects:

```bash
cliban issue ls --label bug --status backlog --json
cliban issue ls --label bug --status in-progress --json
cliban issue ls --label bug --status blocked --json
```

Present per-status grouped output.

### `/bugs <project>`

List open bugs in one project:

```bash
# Resolve project key (case-insensitive)
TARGET="<PROJECT_INPUT>"
KEY=$(cliban project ls --json | jq -r --arg t "$TARGET" \
  'select((.key|ascii_upcase) == ($t|ascii_upcase) or (.name|ascii_upcase) == ($t|ascii_upcase)) | .key' | head -1)
[ -z "$KEY" ] && echo "no project matches" && exit 1

for status in backlog in-progress blocked; do
  cliban issue ls --project "$KEY" --label bug --status "$status" --json
done
```

### `/bugs add <description>`

Resolve the active project (via `cliban-workflow` convention layer). Then:

1. Determine title, severity, and priority from the description.
2. Create the cliban issue:

```bash
NEW=$(cliban issue add --project <KEY> --label bug \
  --priority <p0=urgent|p1=high|p2=medium|p3=low> \
  --title "<title>" \
  --description-file - --json <<'EOF' | jq -r '.key'
## Spec

<description, severity, repro steps if known, expected vs actual>
EOF
)
echo "Created $NEW"
```

3. **Optional — for non-trivial bugs only:** create a memory vault entry capturing the diagnostic knowledge. Use the obsidian-markdown skill for vault content conventions:
   - Frontmatter: `type: bug`, `status: open`, `tags: [<project>, ...]`
   - Content: full repro, root cause, hypothesis, files implicated
   - Cross-link: include `Cliban: <NEW>` in the memory body. Include the vault path in the cliban issue description (edit the `## Spec` section to add `Memory: Claude/bugs/<path>.md` at the end).

Skip the memory step for simple/obvious bugs.

### `/bugs resolve <query>`

1. Search cliban for matching bugs:

```bash
cliban issue ls --label bug --json | jq -r --arg q "<QUERY>" \
  'select(.status != "done" and (.title|ascii_downcase|contains($q|ascii_downcase)))'
```

2. Present the top match(es). Confirm with the user which issue to resolve.

3. Move the cliban issue to `done`:

```bash
cliban issue mv <BUG-KEY> done
cliban issue log <BUG-KEY> "resolved: <one-line reason>"
```

4. If the bug's description references a memory vault path (`Memory: ...`), also update the memory entry's frontmatter to `status: resolved` (per obsidian-markdown conventions). This is the only knowledge-vault write — the cliban side is the source of truth for the ticket.

## Output Format

For each bug, show:
- **Key** (e.g., `SHH-42`) and **title**
- **Priority** and **status**
- **Project**
- **Updated** timestamp
- **Memory path** (if cross-referenced in description)

## Notes

- Cliban auto-creates the `bug` label on first use; no setup needed.
- Use cliban's relation flags for dependencies: `--blocks KEY` if this bug blocks another body of work; `--blocked-by KEY` if it's gated on something else.
- The previous memory-API backend (`$MEMORY_API_URL`) is no longer used. If old bugs exist there, they're historical — new bugs flow through cliban.
