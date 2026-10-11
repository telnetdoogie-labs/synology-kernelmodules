#!/bin/bash
# Builds every platform Synology currently publishes sources for (3.x/legacy platforms excluded).
# Set DSM_VERSION (e.g. DSM_VERSION=7.2 ./compile_for_all.sh) to build from that DSM release's sources.

set -euo pipefail

PLATFORMS_FILE="discovered_platforms.json"

echo "Discovering platforms from archive.synology.com${DSM_VERSION:+ for DSM $DSM_VERSION}..."
python3 discover_platforms.py ${DSM_VERSION:+--dsm "$DSM_VERSION"} > "$PLATFORMS_FILE"

jq -r 'to_entries[] | select(.value.VERSION != "3") | .key' "$PLATFORMS_FILE" | while read -r platform; do
  echo "Compiling for platform: $platform"
  # Mount the list so every build uses the same sources, even if Synology publishes mid-run.
  docker run --privileged --rm \
    -v ./compiled_modules:/compiled_modules:rw \
    -v "./$PLATFORMS_FILE:/synology-toolkit/platforms.json:ro" \
    -e PLATFORM="$platform" \
    compile_modules </dev/null || echo "Build failed for $platform"
done
