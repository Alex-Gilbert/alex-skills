# alex-skills

A model-agnostic agent skills system, packaged for Claude Code and documented
for Codex-compatible hosts. It provides workflows for brainstorming, planning,
test-driven development, debugging, code review, and release, wired to integrate
with [cliban](https://github.com/Alex-Gilbert) (a self-hosted kanban/issue CLI)
for issue, plan, and milestone tracking.

Skills are selected by judgment rather than injected as a mandatory session-start
policy. Explicit skill requests remain binding; otherwise the agent uses only the
workflows that materially help the task. Substantial ambiguous work still follows
brainstorm → behavioral plan → test-driven execution, while trivial or already
well-specified changes can proceed directly.

Project Markdown provides progressive durable memory. Agents fuzzy-search `###`
subsections under each project's `## Notes`, retrieving only relevant lessons
rather than loading project memory wholesale into every session.

## Model profiles

Workflow skills request capability roles rather than concrete models. The
central `model-routing` skill maps those roles for `performance`, `no-fable`,
`economy`, and provider-neutral `inherit` profiles. The default is `no-fable`:

```bash
export ALEX_SKILLS_MODEL_PROFILE=no-fable
```

Use `performance` to opt into the expensive top tier, `economy` for a
Sonnet/Haiku-only workflow, or `inherit` to let Codex or another host select
every model. Per-role environment overrides accept any model identifier the
host supports.

## Provenance

This project is built on top of **[obra/superpowers](https://github.com/obra/superpowers)**
by Jesse Vincent (MIT-licensed). Many of the core workflow skills are taken from
or derived from superpowers; others are original to this repo.

See [`skills/OWNERSHIP.md`](skills/OWNERSHIP.md) for the per-skill breakdown:

- **upstream-tracked** — kept close to superpowers, pull improvements by sync.
- **fork-owned** — superpowers skills heavily diverged for the cliban workflow.
- **fork-original** — no upstream counterpart (the `ponytail` over-engineering
  family, `cliban`/`cliban-workflow`, `bugs`, `status`, `ticket`, `improve`,
  `repo-standards`, `requesting-strict-review`, `complete-milestone`).

The unmodified upstream snapshot is vendored under [`vendor/superpowers/`](vendor/superpowers/),
which carries its own copy of the upstream license.

## License

MIT — see [`LICENSE`](LICENSE). Copyright © 2025 Jesse Vincent (superpowers) and
© 2026 Alex Gilbert (modifications and original skills).
