#!/usr/bin/env bash
# The executor lane is gone: no shipped file names its scripts, settings or
# reference, and the README tells an upgrading user what moved.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names='run-codex-task\.sh|run-agy-task\.sh|lane-breaker|plan-revise|codexLane|agyLane|executor-lane\.md'
hits=$(cd "$P" && grep -rlE "$names" scripts reference skills hooks config .claude-plugin .codex-plugin 2>/dev/null | sort | tr '\n' ' ')
check "no shipped file names a lane script, setting or reference" "$hits" ""
section=$(awk '/^## Migrating to 5\.0/ { f = 1; next } f && /^## / { exit } f' "$P/README.md")
for name in codexLane agyLane agyReview revising-plans plan-revise; do
  check "the 5.0 migration names $name" "$(grep -c -- "$name" <<<"$section" | awk '{ print ($1 > 0) ? "yes" : "no" }')" "yes"
done
check "the 5.0 migration says an Executor line draws a plan-lint WARN" "$(grep -c 'prints a WARN that the line is obsolete' <<<"$section")" "1"
check "the 5.0 migration gives the mid-lane rule" "$(grep -c 'A task caught mid-lane' <<<"$section")" "1"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
