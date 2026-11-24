#!/usr/bin/env bash
# Print a greeting for the name given, or for the world.
set -eu
printf 'Hello, %s!\n' "${1:-world}"
