#!/usr/bin/env bash
# The README documents the two Claude Code settings an unattended parallel run
# needs, each with the reason it is needed.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
README="$HERE/../README.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

section=$(tr -d '\r' < "$README" | awk '/^## / { in_section = ($0 == "## Unattended runs"); next } in_section')
flat=$(tr -s ' \n' '  ' <<<"$section")
has() { if grep -qF -- "$1" <<<"$flat"; then echo yes; else echo no; fi; }

check "one Unattended runs heading" "$(tr -d '\r' < "$README" | grep -c '^## Unattended runs$')" "1"
check "the section has text" "$([ -n "$section" ] && echo yes || echo no)" "yes"
check "auto mode is named with its flag" "$(has '--permission-mode auto')" "yes"
check "auto mode gives its reason: a permission prompt stalls a wave implementer" "$(has 'permission prompt')" "yes"
check "worktree.baseRef is set to head in a settings snippet" "$(has '{ "worktree": { "baseRef": "head" } }')" "yes"
check "baseRef gives its reason: the default branches from origin" "$(has 'origin/<default-branch>')" "yes"
check "baseRef gives its reason: unpushed local commits are missing from the worktree" "$(has 'unpushed')" "yes"
check "dforge's own auto run is told apart from auto mode" "$(has 'reference/auto-run.md')" "yes"
check "the section sits before Session budget" \
  "$(tr -d '\r' < "$README" | awk '/^## Unattended runs$/ { a = NR } /^## Session budget$/ { b = NR } END { print (a > 0 && a < b) ? "yes" : "no" }')" "yes"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
