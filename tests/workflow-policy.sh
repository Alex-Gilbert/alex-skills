#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local file=$1 pattern=$2 message=$3
  rg -qi "$pattern" "$file" || fail "$message"
}

assert_not_contains() {
  local file=$1 pattern=$2 message=$3
  if rg -qi "$pattern" "$file"; then
    fail "$message"
  fi
}

assert_git_blob() {
  local file=$1 expected=$2 message=$3 actual
  actual=$(git hash-object "$file")
  test "$actual" = "$expected" || fail "$message"
}

# Skill discovery is available but never forced into every session.
if jq -e '.hooks.SessionStart' hooks/hooks.json >/dev/null; then
  fail 'SessionStart must not inject the skill-selection policy'
fi
test ! -e hooks/session-start || fail 'the coercive session-start injector must be removed'
assert_not_contains skills/using-superpowers/SKILL.md \
  '1% chance|ABSOLUTELY MUST|DO NOT HAVE A CHOICE|Follow skill exactly|Red Flags' \
  'skill selection must not use coercive legacy language'
assert_contains skills/using-superpowers/SKILL.md \
  'explicit(ly)? request|explicit request' \
  'explicit skill requests must remain binding'
assert_contains skills/using-superpowers/SKILL.md \
  'judg(e|ment)|judgment' \
  'skill selection must be judgment-based'
assert_contains skills/using-superpowers/SKILL.md \
  'declares `requires_skills`' \
  'selected skill dependencies must still load'

# Brainstorm only where design judgment is actually needed.
assert_contains skills/brainstorming/SKILL.md \
  'trivial|well-specified' \
  'brainstorming must define a bypass for trivial or well-specified work'
assert_not_contains skills/brainstorming/SKILL.md \
  'This applies to EVERY project|Every project goes through this process' \
  'brainstorming must not gate every change'

# Plans specify behavior and verification instead of transcribing code.
assert_contains skills/writing-plans/SKILL.md \
  'behavior|behaviour' \
  'plans must focus on behavior'
assert_contains skills/writing-plans/SKILL.md \
  'test intent' \
  'plans must state test intent'
assert_not_contains skills/writing-plans/SKILL.md \
  'questionable taste|2-5 minutes|2–5 minutes|code blocks required for code steps' \
  'plans must not be implementation transcripts'
assert_contains skills/writing-plans/SKILL.md \
  'fresh-context' \
  'plan review must use a fresh-context verifier'
assert_contains skills/writing-plans/plan-document-reviewer-prompt.md \
  'Issue key|cliban issue show' \
  'the reviewer prompt must read the cliban-backed spec and plan'

# Project Markdown is the progressive, lifecycle-free durable memory store.
assert_contains skills/cliban-workflow/SKILL.md \
  'cliban --help' \
  'cliban availability must use a supported command'
assert_not_contains skills/cliban-workflow/SKILL.md \
  'Probe `cliban version`' \
  'cliban availability must not use the unsupported version command'
assert_contains skills/cliban-workflow/SKILL.md \
  'cliban project search <KEY>.*--section notes --json' \
  'durable lessons must be retrieved progressively from project Markdown'
assert_contains skills/cliban-workflow/SKILL.md \
  'cliban project search --help' \
  'project memory must capability-check stale cliban installations'
assert_contains skills/cliban-workflow/SKILL.md \
  'continu(e|ing).*project.*milestone.*issue|project.*milestone.*issue.*normally' \
  'missing memory search must not disable ordinary cliban workflows'
assert_contains skills/cliban-workflow/SKILL.md \
  'one.*`###`|`###`.*one' \
  'durable lessons must have independently retrievable H3 sections'
assert_contains skills/cliban-workflow/SKILL.md \
  'durable|reusable' \
  'notes must be reserved for durable lessons'
assert_contains skills/cliban-workflow/SKILL.md \
  'only relevant|only matching|whole.*section|full.*section' \
  'memory retrieval must not load the full notes section by default'
assert_contains skills/brainstorming/SKILL.md \
  'project.*`## Notes`|`## Notes`.*project' \
  'brainstorming must use project Markdown for durable memory'
assert_contains skills/brainstorming/SKILL.md \
  'project edit <KEY> --description "\$\(cat /tmp/project\.md\)"' \
  'project brainstorming must retain a whole-description fallback for older cliban'
assert_contains skills/cliban-workflow/SKILL.md \
  'project show <KEY> --json.*description.*project\.md' \
  'memory updates must begin by round-tripping the full project description'
assert_contains skills/cliban-workflow/SKILL.md \
  'project edit <KEY> --description-file /tmp/project\.md' \
  'memory updates must preserve the full project description'
assert_not_contains skills/cliban-workflow/SKILL.md \
  'cliban note' \
  'the superseded first-class note API must be removed'

# Keep the proven engineering and milestone safety rails.
assert_contains skills/test-driven-development/SKILL.md \
  'NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST' \
  'TDD must remain test-first'
assert_contains skills/complete-milestone/SKILL.md \
  'Build .*test on every merge result|Build \*then\* test on every merge result' \
  'milestone merge verification must remain intact'
assert_contains skills/complete-milestone/SKILL.md \
  'done.*claim|Treat "done" as a claim' \
  'milestone completion claims must still be verified'
assert_git_blob skills/test-driven-development/SKILL.md \
  7a751fa946b7fd801feb504cb1af6b5b62adcf43 \
  'TDD must remain byte-for-byte unchanged'
# Model routing is centralized behind capability roles and defaults to no-Fable.
test -f skills/model-routing/SKILL.md || fail 'model-routing skill must exist'
assert_contains skills/OWNERSHIP.md \
  '\bmodel-routing\b' \
  'model-routing ownership must be documented'
assert_contains skills/model-routing/SKILL.md \
  'ALEX_SKILLS_MODEL_PROFILE' \
  'model profile must be selectable with one environment variable'
assert_contains skills/model-routing/SKILL.md \
  'no-fable.*default|default.*no-fable' \
  'the default profile must avoid Fable'
for profile in performance economy inherit; do
  assert_contains skills/model-routing/SKILL.md \
    "\\b$profile\\b" \
    "$profile model profile must be available"
done
assert_contains skills/model-routing/SKILL.md \
  '\| `no-fable` \(default\) \| `opus` \| `opus` \| `sonnet` \| `haiku` \|' \
  'the no-fable profile must contain no Fable model route'
assert_contains skills/model-routing/SKILL.md \
  '\| `performance` \| `fable` \| `fable` \| `sonnet` \| `haiku` \|' \
  'the performance profile mapping must stay explicit'
assert_contains skills/model-routing/SKILL.md \
  '\| `economy` \| `sonnet` \| `sonnet` \| `sonnet` \| `haiku` \|' \
  'the economy profile must keep every non-mechanical role off premium models'
assert_contains skills/model-routing/SKILL.md \
  '\| `inherit` \| inherit \| inherit \| inherit \| inherit \|' \
  'the provider-neutral profile must inherit every role'
for role in COORDINATOR REVIEWER IMPLEMENTER MECHANICAL; do
  assert_contains skills/model-routing/SKILL.md \
    "ALEX_SKILLS_MODEL_$role" \
    "$role capability role must support a host-specific override"
done
assert_contains skills/model-routing/SKILL.md \
  'empty|unset' \
  'empty profile selection must have defined behavior'
assert_contains skills/model-routing/SKILL.md \
  'unknown|unrecognized|invalid' \
  'unknown profile selection must have defined behavior'
assert_contains skills/model-routing/SKILL.md \
  'unsupported|unavailable.*override|override.*unavailable' \
  'unsupported explicit model overrides must be surfaced'
assert_contains skills/subagent-driven-development/SKILL.md \
  'same concrete model|same model' \
  'workflows must allow economy profiles to map distinct roles identically'
assert_contains README.md \
  'ALEX_SKILLS_MODEL_PROFILE=no-fable' \
  'README must document the cheap no-Fable switch'
for profile in performance economy inherit; do
  assert_contains README.md \
    "\\b$profile\\b" \
    "README must document the $profile model profile"
done

for skill in \
  complete-milestone improve requesting-code-review requesting-strict-review \
  subagent-driven-development; do
  assert_contains "skills/$skill/SKILL.md" \
    'model-routing' \
    "$skill must load centralized model routing"
done

if rg -ni '\b(fable|opus|sonnet|haiku)\b' \
  skills/complete-milestone/SKILL.md \
  skills/improve/SKILL.md \
  skills/improve/references/closing-the-loop.md \
  skills/requesting-code-review/SKILL.md \
  skills/requesting-strict-review/SKILL.md \
  skills/subagent-driven-development/SKILL.md \
  skills/subagent-driven-development/task-reviewer-prompt.md \
  agents/code-reviewer.md; then
  fail 'workflow skills and agent definitions must use roles, not concrete model names'
fi
assert_not_contains agents/code-reviewer.md \
  '^model:' \
  'the reviewer agent must not hard-pin a provider model'

printf 'workflow policy checks passed\n'
