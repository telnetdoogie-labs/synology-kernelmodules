#!/bin/bash
# Packages compiled modules and writes release notes, ready for a GitHub Release.
#
# Usage: prepare-release.sh <modules dir> <tag|auto> <target commit> <out dir>
#   modules dir  <kernel version>/<platform>/*.ko plus sources.json
#   tag          the release tag, or "auto" to pick the next version after the
#                newest vX.Y.Z tag: a minor bump when the release adds a platform,
#                otherwise a patch bump
#   out dir      receives dist/ (assets), notes.md and tag
#
# Needs GH_TOKEN, GITHUB_REPOSITORY, and a checkout with full history and tags.
set -euo pipefail

modules=$(realpath "$1")
tag=$2
target=$3
out=$(realpath -m "$4")
here=$(dirname "$(realpath "$0")")
mkdir -p "$out/dist"

prev=$(git tag -l 'v*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | grep -vxF "$tag" | head -n1 || true)

# What the previous release was built from, if it recorded it.
previous=()
if [ -n "$prev" ] && git show "$prev:compiled_modules/sources.json" > "$out/previous.json" 2>/dev/null; then
  previous=(--previous "$out/previous.json")
fi

if [ "$tag" = auto ]; then
  IFS=. read -r major minor patch <<< "${prev:-v0.0.0}"
  major=${major#v}
  if [ ${#previous[@]} -eq 0 ]; then
    added=1
  else
    added=$(jq -n --slurpfile old "$out/previous.json" --slurpfile new "$modules/sources.json" \
      '($new[0] | keys) - ($old[0] | keys) | length')
  fi
  if [ "$added" -gt 0 ]; then
    tag="v$major.$((minor + 1)).0"
  else
    tag="v$major.$minor.$((patch + 1))"
  fi
fi
echo "$tag" > "$out/tag"
echo "Release $tag (previous: ${prev:-none})" >&2

# One zip per platform. Named <platform>.zip because GitHub renames assets containing "+".
for dir in "$modules"/*/*/; do
  platform=$(basename "$dir")
  (cd "$dir" && zip -qj "$out/dist/$platform.zip" ./*.ko)
done
(cd "$modules" && zip -qr "$out/dist/all-platforms.zip" .)
cp "$modules/sources.json" "$out/dist/sources.json"

# GitHub's changelog since the previous release (filtered by .github/release.yml).
notes_args=(-f tag_name="$tag" -f target_commitish="$target")
[ -n "$prev" ] && notes_args+=(-f previous_tag_name="$prev")
gh api "repos/$GITHUB_REPOSITORY/releases/generate-notes" "${notes_args[@]}" --jq .body > "$out/changelog.md"

python3 "$here/release_notes.py" \
  --modules "$modules" --sources "$modules/sources.json" \
  --repo "$GITHUB_REPOSITORY" --tag "$tag" \
  --changelog "$out/changelog.md" "${previous[@]}" > "$out/notes.md"

ls -l "$out/dist" >&2
