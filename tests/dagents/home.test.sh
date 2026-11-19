#!/usr/bin/env bash
# The home directory's suites are JavaScript (node:test); this wrapper is how
# scripts/test-all.mjs, which collects *.test.sh here, finds them.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v node >/dev/null 2>&1 || { echo "home tests: node is required but not on PATH" >&2; exit 2; }
exec node --test --test-reporter=spec --test-timeout=300000 "$HERE"/home/*.test.mjs
