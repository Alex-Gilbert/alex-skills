---
name: session-end
description: "Summarize and store session before ending. Use when user invokes /session-end or when wrapping up a conversation."
requires_skills: [obsidian-markdown, cliban-workflow]
---

# Session End — Summarize and Store

Summarize the current conversation, capture cliban activity, and store knowledge to memory before ending.

## Process

### Step 1: Capture Session Window

Approximate the session start time — if unsure, use `-2h` as a default rolling window.

```bash
SESSION_START="${SESSION_START:-2h}"
```

### Step 2: Cliban Activity Summary

Query everything that moved during the session:

```bash
cliban issue ls --updated-since "$SESSION_START" --json
```

For each issue, capture:
- Key + title
- Status (and whether it transitioned during the session — compare with prior log lines via `cliban issue show KEY --section activity` if needed)
- Any new sub-issues created (parent_id set during the window)
- Activity log entries added during the window

Render as a markdown section:

```markdown
## Cliban activity this session

- SHH-12 (in-progress → in-review): plan complete, PR opened — see SHH-12 → <url>
- SHH-13 (new sub-issue): CSRF middleware promoted from SHH-12 Task 1 Step 3
- COOK-42 (backlog → done): hotfix landed
- ...
```

### Step 3: Summarize Accomplishments (free-form)

What was done in this session, beyond cliban tracking:
- Decisions made
- Patterns established or refined
- Bugs found (cross-reference cliban keys)
- Code shipped (key files, modules touched)
- Open items / what's next

### Step 4: Store Knowledge to Memory (per obsidian-markdown conventions)

For each non-trivial item:

- **Decisions** → vault entry with `type: decision`, frontmatter tags matching the project. Cross-link cliban keys.
- **Bugs** → only if they have non-trivial diagnostic context (root cause, repro). Cross-link `Cliban: <KEY>`.
- **Patterns** → vault entry with `type: pattern`, project tags.
- **Session summary** → vault entry with `type: session` capturing the full picture: accomplishments, decisions, cliban activity section, what's next.

Use the obsidian-markdown skill for vault conventions (wikilinks, frontmatter shape, callouts).

### Step 5: Avoid Duplicates

Before storing each item, check the vault for >0.85 similarity. Don't store near-duplicates.

## Notes

- The previous `$MEMORY_API_URL` HTTP backend is no longer in use. All vault writes go through the obsidian-markdown skill's conventions directly to the vault filesystem.
- Cliban activity summarization is the new core of session-end — everything that mutated in cliban this session shows up in the summary, giving you a complete picture of what changed without re-reading the chat.
