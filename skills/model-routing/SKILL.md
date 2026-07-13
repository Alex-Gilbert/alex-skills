---
name: model-routing
description: "Use when a workflow dispatches subagents and must choose models by capability, cost, or host availability."
---

# Model Routing

Workflows request capability roles; this skill is the only place that maps them to provider model names. Resolve the profile once before the first dispatch. If the host cannot select models, omit the model parameter and inherit.

## Select a Profile

Read `ALEX_SKILLS_MODEL_PROFILE`. Unset or empty means `no-fable`. An unrecognized value is a configuration error: stop before dispatch and report the valid profiles instead of guessing.

| Profile | coordinator | reviewer | implementer | mechanical |
|---|---|---|---|---|
| `no-fable` (default) | `opus` | `opus` | `sonnet` | `haiku` |
| `performance` | `fable` | `fable` | `sonnet` | `haiku` |
| `economy` | `sonnet` | `sonnet` | `sonnet` | `haiku` |
| `inherit` | inherit | inherit | inherit | inherit |

Switch the whole workflow before starting a session:

```bash
export ALEX_SKILLS_MODEL_PROFILE=no-fable
```

Role-specific overrides take precedence and may contain any model identifier supported by the host:

```bash
export ALEX_SKILLS_MODEL_COORDINATOR=<model>
export ALEX_SKILLS_MODEL_REVIEWER=<model>
export ALEX_SKILLS_MODEL_IMPLEMENTER=<model>
export ALEX_SKILLS_MODEL_MECHANICAL=<model>
```

Resolution order is: non-empty role override, selected profile, then its role mapping. If an explicit override or mapped concrete model is unsupported or unavailable, stop before dispatch and surface the identifier; ask the user to choose a supported override or the `inherit` profile. Never silently replace it with the host default. If the host has no model-selection capability at all, say once that routing cannot be enforced and inherit for every role.

## Roles

- `coordinator`: long-horizon planning, architecture, conflict resolution, and orchestration.
- `reviewer`: independent correctness, security, and maintainability judgment.
- `implementer`: ordinary multi-file implementation and debugging.
- `mechanical`: tightly specified, isolated, low-risk edits.

Use the resolved model identifier in the host's subagent model parameter. For `inherit`, omit that parameter and use the host default. Roles remain semantically distinct even when a profile maps several roles to the same concrete model. Never silently move from `no-fable` or `economy` to `performance`; expensive models are opt-in.
