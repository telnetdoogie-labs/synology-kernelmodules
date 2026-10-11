#!/bin/bash
# Prints a GitHub Actions output line "include=<json>" describing the build matrix.
#
# Usage: select-platforms.sh <platforms.json> <requested> <include_legacy>
#   requested       "all", or platform names separated by commas/spaces
#   include_legacy  "true" to keep 3.x-kernel platforms (built with Dockerfile_legacy)
set -euo pipefail

json_file=$1
requested=${2:-all}
include_legacy=${3:-false}

known=$(jq -r 'keys[]' "$json_file")
wanted=$(echo "$requested" | tr ', ' '[\n*]' | sed '/^$/d' | sort -u)

if [ -z "$wanted" ] || echo "$wanted" | grep -qx all; then
  wanted=$known
  explicit=false
else
  explicit=true
  unknown=$(comm -23 <(echo "$wanted") <(echo "$known" | sort))
  if [ -n "$unknown" ]; then
    echo "::error::Unknown platform(s): $(echo "$unknown" | tr '\n' ' ')" >&2
    echo "Known platforms: $(echo "$known" | tr '\n' ' ')" >&2
    exit 1
  fi
fi

include=$(jq -c \
  --argjson wanted "$(echo "$wanted" | jq -R . | jq -sc .)" \
  --argjson legacy "$include_legacy" \
  --argjson explicit "$explicit" '
  to_entries
  | map(select(.key as $k | $wanted | index($k)))
  | map(select(.value.VERSION != "3" or $legacy or $explicit))
  | map({
      platform: .key,
      kver: "\(.value.VERSION).\(.value.PATCHLEVEL).\(.value.SUBLEVEL)\(.value.EXTRAVERSION)",
      dockerfile: (if .value.VERSION == "3" then "Dockerfile_legacy" else "Dockerfile" end)
    })
  | sort_by(.platform)' "$json_file")

if [ "$include" = "[]" ]; then
  echo "::error::No platforms selected" >&2
  exit 1
fi

echo "Selected: $(echo "$include" | jq -r 'map(.platform) | join(", ")')" >&2
echo "include=$include"
