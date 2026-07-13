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

# Cliban is the progressive, lifecycle-free durable memory store.
assert_contains skills/cliban-workflow/SKILL.md \
  'cliban --help' \
  'cliban availability must use a supported command'
assert_not_contains skills/cliban-workflow/SKILL.md \
  'Probe `cliban version`' \
  'cliban availability must not use the unsupported version command'
assert_contains skills/cliban-workflow/SKILL.md \
  'cliban note search' \
  'durable lessons must be retrieved progressively from cliban notes'
assert_contains skills/cliban-workflow/SKILL.md \
  'cliban note --help' \
  'note memory must capability-check stale cliban installations'
assert_contains skills/cliban-workflow/SKILL.md \
  'continuing all project, milestone, and issue workflows normally' \
  'missing note support must not disable ordinary cliban workflows'
assert_contains skills/cliban-workflow/SKILL.md \
  'durable|reusable' \
  'notes must be reserved for durable lessons'
assert_contains skills/cliban-workflow/SKILL.md \
  'search before|before adding' \
  'notes must be searched before adding to avoid duplicates'
assert_not_contains skills/brainstorming/SKILL.md \
  'longer-lived notes|optionally `## Notes`' \
  'brainstorming must not create a second durable-memory store'
assert_not_contains skills/cliban-workflow/SKILL.md \
  '\[long-lived notes' \
  'description-level notes must not compete with cliban notes'

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
assert_git_blob skills/complete-milestone/SKILL.md \
  a54fbc48ec56e0463505479358805874d19b688c \
  'complete-milestone must remain byte-for-byte unchanged'

printf 'fable-native workflow checks passed\n'
