---
name: shape
description: "Lightweight idea refinement through focused questioning. Use when user invokes /shape to challenge and refine a captured idea."
requires_skills: [obsidian-markdown]
---

# Shape — Lightweight Idea Refinement

Challenge and refine an idea into something actionable through focused questioning. Lighter than brainstorming — no spec output, no approaches analysis. The goal is to stress-test the idea and sharpen it.

## Entry Points

- `/shape` with no args — list open ideas and let the user pick one:
  ```bash
  curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
    "$MEMORY_API_URL/memories?type=idea&status=open"
  ```
- `/shape <query>` — search for a matching idea. If found, use it. If no match, start shaping the query as a fresh concept:
  ```bash
  curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
    -d '{"query": "QUERY", "type": "idea"}' \
    $MEMORY_API_URL/memories/search
  ```

## Flow

1. **Load the idea** — from vault or fresh input. Display it back to the user so you're both starting from the same place.
2. **Offer visual companion** (this is its own message, no other content):
   > "Some of what we're working on might be easier to explain if I can show it to you in a web browser. I can put together mockups, diagrams, comparisons, and other visuals as we go. This feature is still new and can be token-intensive. Want to try it? (Requires opening a local URL)"
   If accepted, read the guide at `skills/brainstorming/visual-companion.md` before proceeding. If declined, text-only shaping. Per-question, decide visual vs. terminal: "would the user understand this better by seeing it than reading it?"
3. **Challenge the idea** — ask questions one at a time (guideline: 3-5, adapt to complexity). Examples:
   - "What problem does this actually solve?"
   - "Who benefits and how would they use it?"
   - "What's the simplest version that delivers value?"
   - "What could go wrong or make this harder than it looks?"
   After each answer, push back where warranted. Surface tensions ("you said X but that conflicts with Y"), challenge assumptions, ask for clarification.
4. **Synthesize** — produce a shaped version of the idea with:
   - **Problem statement** — what this solves and for whom
   - **Proposed approach** — high-level direction, not a spec
   - **Open questions** — things still unresolved
   - **Risks** — what could go wrong
   Present this to the user for approval.
5. **Update vault** — update the idea with the shaped version:
   ```bash
   curl -s -H "X-Author: $MEMORY_API_AUTHOR" \
     -X PATCH \
     -d '{"vault_path": "PATH", "status": "active", "content": "SHAPED_VERSION\n\n## Original Idea\nORIGINAL_TEXT"}' \
     $MEMORY_API_URL/memories
   ```
6. **Confirm** — "Idea shaped. Use the brainstorming skill when you're ready to turn this into a spec."

## Edge Cases

- If called on an already-shaped idea (`active` status): re-shape it. Update content, keep status as `active`. Refining further is valid.
- If called on an archived idea (`archived` status): warn that this idea already has a spec, ask if the user wants to re-open it.

## Design Constraints

- No approaches/trade-offs analysis (that's brainstorming)
- No spec output
- No implementation planning
- One question at a time — do not overwhelm

## Visual Companion

A browser-based companion for showing mockups, diagrams, and visual options during shaping. Available as a tool — not a mode. Accepting the companion means it's available for questions that benefit from visual treatment; it does NOT mean every question goes through the browser.

**Offering the companion:** When you anticipate that upcoming questions will involve visual content (mockups, layouts, diagrams), offer it once for consent:
> "Some of what we're working on might be easier to explain if I can show it to you in a web browser. I can put together mockups, diagrams, comparisons, and other visuals as we go. This feature is still new and can be token-intensive. Want to try it? (Requires opening a local URL)"

**This offer MUST be its own message.** Do not combine it with clarifying questions, context summaries, or any other content. The message should contain ONLY the offer above and nothing else. Wait for the user's response before continuing. If they decline, proceed with text-only shaping.

**Per-question decision:** Even after the user accepts, decide FOR EACH QUESTION whether to use the browser or the terminal. The test: **would the user understand this better by seeing it than reading it?**

- **Use the browser** for content that IS visual — mockups, wireframes, layout comparisons, architecture diagrams, side-by-side visual designs
- **Use the terminal** for content that is text — requirements questions, conceptual choices, tradeoff lists, A/B/C/D text options, scope decisions

A question about a UI topic is not automatically a visual question. "What does personality mean in this context?" is a conceptual question — use the terminal. "Which wizard layout works better?" is a visual question — use the browser.

If they agree to the companion, read the detailed guide before proceeding:
`skills/brainstorming/visual-companion.md`
