#!/usr/bin/env bash
# Run every test file; fail when any fails.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
status=0
for t in "$HERE"/*.test.sh; do bash "$t" || status=1; done
exit $status
