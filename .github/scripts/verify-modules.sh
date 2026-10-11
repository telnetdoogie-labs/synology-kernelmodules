#!/bin/bash
# Checks that every expected module was built and that its vermagic matches the
# target kernel exactly (the NAS refuses to load a module whose vermagic differs).
#
# Usage: verify-modules.sh <module dir> <kernel version, e.g. 4.4.302+>
set -euo pipefail

dir=$1
kver=$2
modules="iptable_raw.ko ip6table_raw.ko"
# overlayfs only exists from Linux 3.18 on, so 3.10 platforms can't have overlay.ko.
if [ "$(printf '%s\n' 3.18 "${kver%%[!0-9.]*}" | sort -V | head -n1)" = 3.18 ]; then
  modules="$modules overlay.ko"
else
  echo "Not expecting overlay.ko: kernel $kver predates overlayfs (3.18)"
fi
failed=0

for mod in $modules; do
  path="$dir/$mod"
  if [ ! -f "$path" ]; then
    echo "::error::$mod was not built (missing $path)"
    failed=1
    continue
  fi
  if command -v modinfo >/dev/null 2>&1; then
    vermagic=$(modinfo -F vermagic "$path")
  else
    vermagic=$(strings "$path" | sed -n 's/^vermagic=//p' | head -n1)
  fi
  case "$vermagic" in
    "$kver "*) echo "OK  $mod  vermagic: $vermagic" ;;
    *)
      echo "::error::$mod has vermagic '$vermagic', expected it to start with '$kver '"
      failed=1
      ;;
  esac
done

exit $failed
