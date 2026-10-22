#!/bin/bash
# Fails if the release notes link to a download that isn't attached to the release.
#
# Usage: check-release-links.sh <tag>
# Needs GH_TOKEN and GITHUB_REPOSITORY.
set -euo pipefail

tag=$1
release=$(gh api "repos/$GITHUB_REPOSITORY/releases/tags/$tag")
assets=$(jq -r '.assets[].name' <<< "$release")
links=$(jq -r '.body // ""' <<< "$release" | grep -oE "releases/download/$tag/[^) \"]+" | sed 's#.*/##' | sort -u || true)

missing=0
for name in $links; do
  if ! grep -qxF "$name" <<< "$assets"; then
    echo "::error::The $tag notes link to $name, but no asset with that name is attached"
    missing=1
  fi
done
[ "$missing" = 0 ] && echo "All $(wc -w <<< "$links") download links in the $tag notes resolve."
exit $missing
