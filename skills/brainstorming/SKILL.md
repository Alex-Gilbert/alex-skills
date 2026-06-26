---
name: brainstorming
description: "You MUST use this before any creative work - creating features, building components, adding functionality, or modifying behavior. Explores user intent, requirements and design before implementation, with the resulting spec stored in cliban."
requires_skills: [cliban-workflow]
---

# Brainstorming Ideas Into Designs

Help turn ideas into fully formed designs and specs through natural collaborative dialogue. The resulting spec is stored in a cliban node (project / milestone / issue) — NOT in a file under `docs/superpowers/specs/`.

<HARD-GATE>
Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until you have presented a design and the user has approved it. This applies to EVERY project regardless of perceived simplicity.
</HARD-GATE>

## Anti-Pattern: "This Is Too Simple To Need A Design"

Every project goes through this process. A todo list, a single-function utility, a config change — all of them. The design can be short (a few sentences for truly simple projects), but you MUST present it and get approval.

## Checklist

You MUST create a task for each of these items and complete them in order:

1. **Explore project context** — `cliban project ls --json`, recent commits, existing related issues
2. **Decide brainstorm scope** — project-level / milestone-level / issue-level
3. **Offer visual companion** (if topic will involve visual questions) — own message, no other content
4. **Ask clarifying questions** — one at a time
5. **Propose 2-3 approaches** — with trade-offs and a recommendation
6. **Present design** — in sections scaled to complexity, get approval after each
7. **Spec self-review** — placeholders / contradictions / ambiguity / scope
8. **Write the spec to the cliban node** (Project description / Milestone description / Issue description)
9. **User reviews stored spec** before transitioning to implementation
10. **Transition** — invoke writing-plans skill (for issue-scoped) or hand back to user (for project/milestone scoped — they'll create issues under it later)

## Deciding Scope

Ask early in the conversation:

> "This sounds like:
> - **Project-level** — a new product, a major architectural direction
> - **Milestone-level** — a release, an epic, a themed bundle of issues
> - **Issue-level** — a single feature or body of work
>
> Which fits?"

Branch the rest of the conversation on the answer. If unclear, the user picks — don't auto-decide.

## Scope: Project-Level

1. Confirm project name/key with user (e.g., `SHH` for shh secret manager).
2. If new, create: `cliban project add <KEY> --name "<Name>" --description "<one-line summary>"`.
3. Run the rest of the brainstorm (questions → approaches → design sections) to draft an architecture-level spec.
4. After approval, write the `## Spec` (and optionally `## Notes`) to the project description:

```bash
cliban project edit <KEY> --description-file - <<'EOF'
## Spec

<design content with H3 subsections — architecture, vision, constraints>

## Notes

<longer-lived notes that outlive any single milestone>
EOF
```

5. Offer to create initial milestones under the new project:

> "Should I create milestones for the phases we discussed?"

If yes, repeat the milestone flow below for each.

6. Hand-off: this brainstorm is complete. Next step is per-milestone or per-issue brainstorming as the user picks them up. Do NOT invoke writing-plans (no single issue to plan yet).

## Scope: Milestone-Level

1. Resolve the active project (convention layer).
2. Ask milestone name and optional target date.
3. Run questions → approaches → design.
4. After approval, write the spec to the milestone description:

```bash
cliban milestone add --project <KEY> --name "<NAME>" [--target YYYY-MM-DD] \
  --description-file - <<'EOF'
## Spec

<what this milestone delivers, why, scope, non-goals>
EOF
```

5. Offer to create kickoff issues:

> "Should I create initial issues under milestone <NAME>?"

If yes, repeat the issue flow below for each. (Or hand off to /ticket.)

6. Hand-off: brainstorm complete. No writing-plans call at milestone scope.

## Scope: Issue-Level

1. Resolve the active project.
2. Run questions → approaches → design sections.
3. After approval, create the issue:

```bash
cliban issue add --project <KEY> --title "<title>" \
  --priority medium --label <type> \
  [--milestone "<name>"] [--parent <KEY-N>] \
  --description-file - --json <<'EOF'
## Spec

<spec body with whatever subsections are useful>
EOF
```

4. Spec self-review (inline checks).
5. Tell the user: `"Spec written to <NEWKEY>. Please review it with `cliban issue show <NEWKEY> --section spec --pager` and let me know if anything needs changes before we write the implementation plan."`
6. Wait for approval. If changes are requested, edit the spec:

```bash
cliban issue edit <NEWKEY> --description-file - <<'EOF'
<full new description, preserving ## Plan and ## Activity Log if they exist>
EOF
```

7. **Transition:** invoke the `writing-plans` skill with the issue key.

## Clarifying Questions

- Check existing project state (recent issues, milestones, prior brainstorms via `cliban issue ls --project KEY`)
- Search for related work: `cliban issue ls --project KEY --label <type> --json | jq 'select(.title | contains("<keyword>"))'`
- Surface any existing tickets that touch the same area before brainstorming new work
- **Challenge necessity as you go (ponytail attitude).** For each feature or requirement the user proposes, ask whether it needs to exist *at all* before exploring how to build it — ponytail ladder rung 1, YAGNI. Push back on speculative needs ("do you need this now, or is it for later?"). This is the cheapest place to delete scope. Embody the challenge in the dialogue; don't load the full `ponytail` persona (its terse code-first output mode clashes with brainstorming).

## Exploring Approaches

- Propose 2-3 different approaches with trade-offs
- Present options conversationally with your recommendation and reasoning
- Lead with your recommended option and explain why

## Presenting the Design

- Scale each section to its complexity: a few sentences if straightforward, up to 200-300 words if nuanced
- Ask after each section whether it looks right so far
- Cover: architecture, components, data flow, error handling, testing
- Be ready to go back and clarify

## Spec Self-Review

After drafting the design content (but before writing to cliban):

1. **Placeholder scan:** Any "TBD", "TODO", incomplete sections, or vague requirements?
2. **Internal consistency:** Do sections contradict? Does the architecture match the feature descriptions?
3. **Scope check:** Focused enough for one body of work, or does it need decomposition? If issue-scoped and the spec covers multiple independent subsystems, decompose into multiple sibling issues.
4. **Ambiguity check:** Could anything be interpreted two ways?
5. **Reinvention check (final ponytail sweep):** Run the ponytail lens you've been applying throughout once more across the *whole* drafted spec — does each requirement still need to exist, or does stdlib / a native platform feature / an already-installed dependency already cover it? Cut or shrink anything that reinvents the wheel before the spec is written. This is the cheapest place to delete scope, and the last one before it's locked in. (Same attitude as the dialogue — no separate persona load.)

Fix inline. No need to re-review — just fix and move on.

## Visual Companion

A browser-based companion for showing mockups, diagrams, and visual options. Available as a tool — not a mode.

**Offering the companion:** When you anticipate visual content, offer once for consent:
> "Some of what we're working on might be easier to explain if I can show it to you in a web browser. I can put together mockups, diagrams, comparisons, and other visuals as we go. This feature is still new and can be token-intensive. Want to try it? (Requires opening a local URL)"

**This offer MUST be its own message.** Do not combine with clarifying questions. Wait for response.

**Per-question decision:** Decide for each question whether the browser or terminal is better. Use the browser ONLY for content that IS visual (mockups, layouts, diagrams). Use the terminal for text content (requirements, tradeoffs, A/B/C/D text options).

If they accept, read the detailed guide: `skills/brainstorming/visual-companion.md`.

## Key Principles

- **One question at a time** — don't overwhelm
- **Multiple choice preferred** — easier to answer
- **YAGNI ruthlessly** — challenge whether each feature needs to exist (ponytail rung 1) before discussing how to build it; remove unnecessary features
- **Explore alternatives** — always 2-3 approaches
- **Incremental validation** — present design, get approval section by section
- **Be flexible** — go back and clarify when something doesn't make sense

## Anti-Patterns

- **DO NOT** write `docs/superpowers/specs/*.md`. The spec lives in cliban.
- **DO NOT** commit a spec file to the project repo as part of brainstorming. The project repo stays code-only.
- **DO NOT** invoke writing-plans for project- or milestone-scoped brainstorms — those don't have a single issue to plan.
