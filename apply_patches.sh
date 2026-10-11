#!/bin/sh


# Remove DCACHE_OP_HASH return from overlayfs module
SUPER_C=./fs/overlayfs/super.c
echo "Looking for DCACHE_OP_HASH in $SUPER_C..."
# Show and remove lines
MATCHING_LINES=$(grep "DCACHE_OP_HASH[[:space:]]*|" "$SUPER_C")
if [ -n "$MATCHING_LINES" ]; then
    echo "Removing the following line(s):"
    echo "$MATCHING_LINES"
    sed -i '/DCACHE_OP_HASH[[:space:]]*|/d' "$SUPER_C"
    echo "Patch applied."
else
    echo "No DCACHE_OP_HASH lines found - nothing to remove."
fi
