#!/usr/bin/env bash
# Every implementer tier carries the scope-limit clause, then the three clauses
# that keep tests honest: a general solution, report a wrong test, never touch
# an existing test. Prose wraps, so each clause is matched with its line breaks
# folded to spaces.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS="$HERE/../agents"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
says() { # says <label> <file> <text>
  check "$1" "$(flat "$2" | grep -oF -- "$3" | wc -l | tr -d ' ')" "1"
}

n=0
for f in "$AGENTS"/impl-*.md; do
  n=$((n + 1))
  b=$(basename "$f" .md)
  says "$b: the scope-limit clause" "$f" \
    'Change only what the brief asks for. Do not add features, tests, files, docs or refactors the brief does not call for; if you think one would help, say so in your report instead.'
  says "$b: write a general solution" "$f" \
    'Write a general solution that is correct for every valid input, never one that only passes the specific inputs a test uses: no hardcoded expected values and no special-casing of test inputs.'
  says "$b: report a test that looks wrong" "$f" \
    'When a test looks wrong, report it as incorrect in your report instead of working around it or changing the code to satisfy it.'
  says "$b: existing tests are immutable" "$f" \
    'Never edit or delete an existing test unless the brief names it.'
  check "$b: the three clauses follow the scope clause, in order" \
    "$(awk '
      /^Change only what the brief asks for\./ { s = NR }
      /^Write a general solution/ { g = NR }
      /^When a test looks wrong/ { w = NR }
      /^Never edit or delete an existing test/ { e = NR }
      END { print (s && s < g && g < w && w < e) ? "yes" : "no" }
    ' "$f")" "yes"
done
check "the fleet has sixteen implementers" "$n" "16"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
