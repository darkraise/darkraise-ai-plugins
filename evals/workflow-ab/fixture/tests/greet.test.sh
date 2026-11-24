#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   - $1"; else echo "FAIL - $1: want [$3] got [$2]"; fail=1; fi; }
check "default name" "$(bash "$HERE/../greet.sh")" "Hello, world!"
check "given name" "$(bash "$HERE/../greet.sh" Ada)" "Hello, Ada!"
exit $fail
