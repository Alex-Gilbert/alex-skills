# alex-skills

A personal [Claude Code](https://claude.com/claude-code) skills system — agent
workflows for brainstorming, planning, test-driven development, debugging, code
review, and release, wired to integrate with [cliban](https://github.com/Alex-Gilbert)
(a self-hosted kanban/issue CLI) for issue, plan, and milestone tracking.

Skills are selected by judgment rather than injected as a mandatory session-start
policy. Explicit skill requests remain binding; otherwise the agent uses only the
workflows that materially help the task. Substantial ambiguous work still follows
brainstorm → behavioral plan → test-driven execution, while trivial or already
well-specified changes can proceed directly.

Cliban notes provide progressive durable memory. Agents search project-scoped notes
for relevant lessons during non-trivial work and record only reusable knowledge;
notes are never loaded wholesale into every session.

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
