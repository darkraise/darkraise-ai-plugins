#!/usr/bin/env bash
# darkmem-sync's suites are JavaScript (node:test); this wrapper is how
# scripts/test-all.mjs, which collects *.test.sh here, finds them.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v node >/dev/null 2>&1 || { echo "darkmem-sync tests: node is required but not on PATH" >&2; exit 2; }
exec node --test --test-reporter=spec --test-timeout=60000 "$HERE"/darkmem-sync/*.test.mjs
