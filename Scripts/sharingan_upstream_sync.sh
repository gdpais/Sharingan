#!/usr/bin/env bash
# Weekly upstream sync for Sharingan: merge steipete/CodexBar into a fresh branch off origin/main.
#
# Usage: ./Scripts/sharingan_upstream_sync.sh [--dry-run]
#   --dry-run  merge in a temporary worktree, report conflicts and the rebrand to-do list, then discard it.
#
# Without --dry-run it creates `upstream-sync/<YYYY-MM-DD>` from origin/main in a sibling worktree
# (../<repo>-upstream-sync-<date>), merges upstream with a merge commit (never rebase), auto-resolves the routine
# "both sides appended keys" conflicts in Localizable.strings (re-branding only the new upstream values),
# and stops with the remaining conflicts listed. It never pushes; open the PR yourself once the merge
# builds and the tests pass. See docs/sharingan-upstream.md.
set -euo pipefail

UPSTREAM_URL="https://github.com/steipete/CodexBar.git"
UPSTREAM_REF="refs/remotes/upstream/main"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"

git fetch --quiet origin main
git fetch --quiet "$UPSTREAM_URL" "main:${UPSTREAM_REF}"

BASE=$(git merge-base origin/main "$UPSTREAM_REF")
AHEAD=$(git rev-list --count "${BASE}..${UPSTREAM_REF}")
if [[ "$AHEAD" == "0" ]]; then
    echo "Up to date: origin/main already contains upstream $(git rev-parse --short "$UPSTREAM_REF")."
    exit 0
fi
echo "Upstream is ${AHEAD} commits ahead of the last sync point $(git rev-parse --short "$BASE")."

BRANCH="upstream-sync/$(date -u +%Y-%m-%d)"
if (( DRY_RUN )); then
    WORKTREE=$(mktemp -d "${TMPDIR:-/tmp}/sharingan-sync.XXXXXX")
    git worktree add --quiet --detach "$WORKTREE" origin/main
    trap 'git -C "$WORKTREE" merge --abort >/dev/null 2>&1 || true; git worktree remove --force "$WORKTREE"' EXIT
else
    WORKTREE="$(dirname "$ROOT")/$(basename "$ROOT")-${BRANCH//\//-}"
    git worktree add --quiet -b "$BRANCH" "$WORKTREE" origin/main
fi

cd "$WORKTREE"
MESSAGE="Merge upstream CodexBar $(git rev-parse --short "$UPSTREAM_REF")"
if git -c merge.conflictStyle=diff3 merge --no-ff --no-edit -m "$MESSAGE" "$UPSTREAM_REF" >/dev/null 2>&1; then
    echo "Merged without conflicts."
else
    # Catalog paths never contain spaces, so plain word splitting is safe (and works on macOS bash 3.2).
    STRINGS=$(git diff --name-only --diff-filter=U -- 'Sources/*/Resources/*.lproj/Localizable.strings')
    if [[ -n "$STRINGS" ]]; then
        # shellcheck disable=SC2086
        if python3 "$ROOT/Scripts/sharingan_resolve_strings_appends.py" --rebrand $STRINGS; then
            # shellcheck disable=SC2086
            git add -- $STRINGS
        fi
        echo "Resolved appended-key conflicts in $(echo "$STRINGS" | wc -l | tr -d ' ') catalog(s) where possible."
    fi
fi

echo
echo "New upstream English strings that mention CodexBar. Values in auto-resolved catalog blocks are already"
echo "rebranded; check any that landed elsewhere, and hardcoded Swift strings, by hand:"
git diff "$BASE" "$UPSTREAM_REF" -- 'Sources/*/Resources/en.lproj/Localizable.strings' \
    | grep -E '^\+"' | grep -E '= ".*CodexBar' | sed 's/^+/  /' || echo "  (none)"

echo
REMAINING=$(git diff --name-only --diff-filter=U)
if [[ -n "$REMAINING" ]]; then
    echo "Conflicts left for a human ($(echo "$REMAINING" | wc -l | tr -d ' ')):"
    echo "$REMAINING" | sed 's/^/  /'
else
    echo "No conflicts left."
fi

if (( DRY_RUN )); then
    echo
    echo "Dry run: nothing was kept."
    exit 0
fi

if [[ -z "$REMAINING" ]] && ! git diff --cached --quiet; then
    git commit --no-edit --quiet
fi
echo
echo "Worktree: $WORKTREE (branch $BRANCH)"
echo "Next: resolve what's listed, run 'make check' and the tests, then push the branch and open a PR."
