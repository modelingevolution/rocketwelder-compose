#!/bin/bash
# Cut a patch compose release (tag vX.Y.Z+1 on HEAD) when every file changed since the latest
# release tag is under skills/. Anything else changed (an image bump, a compose edit, a script)
# means a normal release is pending: do nothing and say why — the skills ship with that release.
#
# Usage: .github/scripts/skills-release.sh [--dry-run]
#   Run from the repo root with HEAD on the commit to release. --dry-run decides and prints, never tags.
#
# Version rule = release.sh --patch: latest tag matching ^vX.Y.Z$ (version sort), patch + 1.
# Other sessions tag this repo too (Deployments/app/release-rocket-welder.sh), so the tags are
# re-read from origin right before deciding, and a tag that already exists on origin fails the run.
set -euo pipefail

DRY_RUN=false
case "${1:-}" in
    --dry-run) DRY_RUN=true ;;
    "") ;;
    *) echo "Usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

say() {
    echo "$*"
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then echo "$*" >> "$GITHUB_STEP_SUMMARY"; fi
}

git fetch --quiet --force --tags origin

LATEST=$(git tag --sort=-version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)
HEAD_SHA=$(git rev-parse HEAD)

if [[ -z "$LATEST" ]]; then
    say "No release tag (vX.Y.Z) found. Nothing to do."
    exit 0
fi
if [[ "$(git rev-parse "$LATEST^{commit}")" == "$HEAD_SHA" ]]; then
    say "HEAD ${HEAD_SHA:0:7} is already released as $LATEST. Nothing to do."
    exit 0
fi
if ! git merge-base --is-ancestor "$LATEST" HEAD; then
    say "HEAD ${HEAD_SHA:0:7} does not contain the latest release $LATEST. Nothing to do."
    exit 0
fi

CHANGED=$(git diff --name-only "$LATEST" HEAD)
OTHER=$(grep -v '^skills/' <<< "$CHANGED" || true)

if [[ -n "$OTHER" ]]; then
    say "Not released: files outside skills/ changed since $LATEST, so a normal release is pending."
    say "The skills ship with that release (release.sh). Files outside skills/:"
    say ""
    while IFS= read -r f; do say "- \`$f\`"; done <<< "$OTHER"
    exit 0
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "${LATEST#v}"
TAG="v$MAJOR.$MINOR.$((PATCH + 1))"

if git rev-parse -q --verify "refs/tags/$TAG" > /dev/null \
   || [[ -n "$(git ls-remote --tags origin "refs/tags/$TAG")" ]]; then
    say "::error::Tag $TAG already exists on origin (another release was cut meanwhile). Not tagging."
    exit 1
fi

say "Skills-only change since $LATEST:"
say ""
while IFS= read -r f; do say "- \`$f\`"; done <<< "$CHANGED"
say ""

if [[ "$DRY_RUN" == true ]]; then
    say "[DRY RUN] Would tag $TAG on ${HEAD_SHA:0:7} and push it to origin."
    exit 0
fi

git tag "$TAG" "$HEAD_SHA"
if ! git push origin "refs/tags/$TAG"; then
    say "::error::Pushing $TAG failed (it may have been created meanwhile). Not released."
    exit 1
fi
say "Released $TAG on ${HEAD_SHA:0:7}. Stations get it through the AutoUpdater."
