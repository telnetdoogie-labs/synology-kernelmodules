#!/bin/bash
# Writes <modules dir>/SHA256SUMS covering every .ko under it, with paths relative
# to that directory (e.g. "4.4.302+/apollolake/iptable_raw.ko"), so it can be
# checked from inside the directory with `sha256sum -c SHA256SUMS`.
#
# Usage: write-checksums.sh <modules dir>
set -euo pipefail

modules=$1
cd "$modules"

mapfile -t files < <(find . -name '*.ko' -type f -printf '%P\n' | LC_ALL=C sort)
if [ "${#files[@]}" -eq 0 ]; then
  echo "::error::No .ko files found in $modules" >&2
  exit 1
fi

sha256sum -- "${files[@]}" > SHA256SUMS.tmp
mv SHA256SUMS.tmp SHA256SUMS
sha256sum --quiet -c SHA256SUMS
echo "Wrote checksums for ${#files[@]} modules to $modules/SHA256SUMS" >&2
