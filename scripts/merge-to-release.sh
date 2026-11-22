#!/usr/bin/env bash
# Merges current main onto the release branch and pushes it.
#
# Usage: ./scripts/merge-to-release.sh [--dry-run]
#
# - Requires a clean working tree (stashes are not touched).
# - Refuses to merge if local main or release is behind origin (ff-only pull first).
# - On merge conflict: aborts the merge, leaves release checked out, exits 1.
# - Returns to the original branch when done.

set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

MAIN=main
RELEASE=release

current_branch=$(git rev-parse --abbrev-ref HEAD)
main_branch_at_start="$current_branch"

cleanup() {
  if [[ "$current_branch" != "$RELEASE" && "$(git rev-parse --abbrev-ref HEAD)" == "$RELEASE" ]]; then
    git checkout "$current_branch" >/dev/null 2>&1 || echo "WARN: could not return to $current_branch" >&2
  fi
}
trap cleanup EXIT

fail() { echo "ERROR: $*" >&2; exit 1; }

git diff-index --quiet HEAD -- || fail "working tree not clean; commit or stash first"

git fetch origin

for branch in "$MAIN" "$RELEASE"; do
  if [[ "$(git rev-parse --abbrev-ref HEAD)" == "$branch" ]]; then
    git pull --ff-only origin "$branch" || fail "$branch is behind origin and cannot fast-forward; reconcile manually"
  fi
done

git checkout "$RELEASE" || fail "no local branch $RELEASE"
git pull --ff-only origin "$RELEASE" || fail "$RELEASE is behind origin and cannot fast-forward; reconcile manually"

if git merge-base --is-ancestor "$MAIN" "$RELEASE"; then
  echo "Nothing to do: $MAIN is already an ancestor of $RELEASE ($(git rev-parse --short "$RELEASE"))."
  exit 0
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run: would merge $(git rev-parse --short "$MAIN") into $RELEASE and push origin/$RELEASE"
  git log --oneline "$RELEASE..$MAIN" | sed 's/^/  would merge: /'
  exit 0
fi

if ! git merge --no-edit "$MAIN"; then
  git merge --abort || true
  fail "merge conflict between $MAIN and $RELEASE; merge aborted, $RELEASE left checked out"
fi

git push origin "$RELEASE"

echo "Done: $RELEASE now at $(git rev-parse --short "$RELEASE"), pushed."
git checkout "$main_branch_at_start" >/dev/null 2>&1 || true
