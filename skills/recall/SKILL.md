---
name: recall
description: "Search semantic memory for relevant context. Use when user invokes /recall, or when Claude needs prior context about decisions, bugs, patterns, or project history."
---

# Recall — Search Memory

Search the semantic memory system for relevant context.

## How to Search

1. Search with a natural language query describing what you're looking for:
   ```bash
   curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
     -d '{"query": "SEARCH_TERMS", "limit": 10}' \
     $MEMORY_API_URL/memories/search
   ```

2. **Optional fields** in the request body to narrow results:
   - `type`: filter by memory type (bug, decision, pattern, etc.)
   - `status`: filter by status (open, resolved, active, etc.)
   - `tags`: filter by tags (array)
   - `limit`: max results (default 10)

## Presenting Results

Format each result as:
- **Score**: similarity score (0-1)
- **Title**: memory title
- **Type**: memory type
- **Path**: vault path (for opening in Obsidian)
- **Preview**: first 200 chars of content

If the user wants more detail on a specific result, fetch the full content using the path from the search result:
```bash
curl -s $MEMORY_API_URL/memories/<path>
```
For example: `curl -s $MEMORY_API_URL/memories/Claude/decisions/some-decision.md`
