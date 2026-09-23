#!/bin/bash

JSON_FILE="platforms.json"
COMPILE_CMD='docker run --privileged --rm -v ./compiled_modules:/compiled_modules:rw -e PLATFORM=${PLATFORM} compile_modules'

jq -r 'keys[]' "$JSON_FILE" | while read platform; do
  echo "Compiling for platform: $platform"
  PLATFORM=$platform
  eval "$COMPILE_CMD"
done
