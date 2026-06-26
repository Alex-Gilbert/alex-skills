# alex-memory justfile
# Manages upstream superpowers sync and skill merging

# Pull latest changes from obra/superpowers into vendor/superpowers/
pull-superpowers:
    git fetch superpowers
    git subtree pull --prefix=vendor/superpowers superpowers main --squash -m "chore: pull latest obra/superpowers"

# Show which shared skills have diverged from upstream
diff-skills:
    #!/usr/bin/env bash
    set -euo pipefail
    changed=0
    for skill in $(comm -12 \
        <(ls skills/ | sort) \
        <(ls vendor/superpowers/skills/ | sort)); do
        if ! diff -rq "vendor/superpowers/skills/$skill" "skills/$skill" > /dev/null 2>&1; then
            echo "  $skill"
            changed=1
        fi
    done
    if [ "$changed" -eq 0 ]; then
        echo "All shared skills are in sync."
    fi

# Show detailed diff for a specific skill: just diff-skill brainstorming
diff-skill name:
    diff -ru "vendor/superpowers/skills/{{name}}" "skills/{{name}}" || true

# Merge upstream skill changes into local skills using Claude
merge-skills:
    #!/usr/bin/env bash
    set -euo pipefail

    diverged=()
    for skill in $(comm -12 \
        <(ls skills/ | sort) \
        <(ls vendor/superpowers/skills/ | sort)); do
        if ! diff -rq "vendor/superpowers/skills/$skill" "skills/$skill" > /dev/null 2>&1; then
            diverged+=("$skill")
        fi
    done

    if [ ${#diverged[@]} -eq 0 ]; then
        echo "All shared skills are in sync. Nothing to merge."
        exit 0
    fi

    echo "Diverged skills: ${diverged[*]}"
    echo ""

    # Build a diff summary for Claude
    diff_context=""
    for skill in "${diverged[@]}"; do
        diff_context+="
    === Skill: $skill ===
    $(diff -ru "vendor/superpowers/skills/$skill" "skills/$skill" || true)
    "
    done

    echo "Invoking Claude to reconcile ${#diverged[@]} diverged skill(s)..."
    echo ""

    claude --print --verbose --allowedTools "Read Edit Glob Grep Bash(diff:*)" --permission-mode bypassPermissions --output-format stream-json "You are merging upstream skill changes from obra/superpowers into the local alex-memory skills.

    RULES:
    - The upstream version is in vendor/superpowers/skills/<name>/
    - The local version is in skills/<name>/
    - Local customizations (cliban integration, ponytail integration, custom skills references) MUST be preserved
    - Upstream improvements (bug fixes, new features, better prompts, new files) should be incorporated
    - If a change conflicts with a local customization, keep the local customization but incorporate the spirit of the upstream change where possible
    - Do NOT touch skills that only exist locally (cliban, bugs, status, ticket, ponytail*, improve, etc.)

    Here are the diffs (--- is upstream, +++ is local):

    $diff_context

    For each diverged skill, read both the upstream and local versions, then edit the local version to incorporate upstream improvements while preserving local customizations. After merging, explain what you changed and why." \
    | jq -r 'select(.type == "assistant") | .message.content[] | select(.type == "text") | .text' 2>/dev/null

# Pull and merge in one step
sync-superpowers: pull-superpowers merge-skills

# List skills that only exist locally (not upstream)
local-skills:
    #!/usr/bin/env bash
    comm -23 \
        <(ls skills/ | sort) \
        <(ls vendor/superpowers/skills/ | sort)

# List skills that only exist upstream (not yet pulled into local)
upstream-only-skills:
    #!/usr/bin/env bash
    comm -13 \
        <(ls skills/ | sort) \
        <(ls vendor/superpowers/skills/ | sort)
