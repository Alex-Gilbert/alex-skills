---
name: obsidian-markdown
description: "Obsidian Flavored Markdown conventions. Use when writing or editing .md files in the Obsidian vault — memories, ideas, specs, or any vault content."
---

# Obsidian Flavored Markdown

Conventions for writing valid Obsidian-compatible markdown. Follow these when creating or editing any content destined for the vault.

Based on [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills).

## Internal Links (Wikilinks)

Use wikilinks for all vault-internal references. Obsidian tracks renames automatically.

```markdown
[[Note Name]]                          Link to note
[[Note Name|Display Text]]             Custom display text
[[Note Name#Heading]]                  Link to heading
```

Use standard markdown links `[text](url)` for external URLs only.

## Frontmatter

```yaml
---
type: decision
status: active
tags: [project-name, topic]
created: 2026-03-18
updated: 2026-03-18
source: conversation
author: alex@example.com
---
```

Rules:
- Every note MUST have frontmatter with at least `type`
- When editing, keep existing keys — only add new keys when requested
- Don't alter value types (e.g., don't convert strings to numbers)
- Use ISO dates (`YYYY-MM-DD`)
- Tags go in frontmatter, not inline `#tag` syntax

## Callouts

Use callouts for structured, highlighted information:

```markdown
> [!note]
> Basic callout.

> [!warning] Custom Title
> Callout with a custom title.

> [!faq]- Collapsed by default
> Foldable callout (- collapsed, + expanded).
```

Useful types for memories:
- `note` — general context
- `warning` — risks, caveats
- `tip` — recommendations
- `example` — concrete examples
- `bug` — bug details
- `quote` — attributed quotes or user statements
- `abstract` — summary or TL;DR

## Formatting

```markdown
==Highlighted text==                   Highlight important terms
%%Hidden comment%%                     Comments hidden in reading view
```

## Content Structure

- Use `# Title` as the first heading (matches frontmatter title)
- Use `## Sections` for logical divisions
- Prefer bullet lists over prose for scannable content
- Use tables for comparative data
