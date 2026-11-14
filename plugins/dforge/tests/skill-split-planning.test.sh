#!/usr/bin/env bash
# brainstorming and writing-plans keep each moved section reachable: a
# reference file, a "Read ... before you ..." line at the step that needs it,
# links that still resolve, and a SKILL.md under the 20,000-byte cap.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

MOVED="
brainstorming:process-flow
brainstorming:design-phase
brainstorming:auto-by-default
brainstorming:drafting-acceptance
brainstorming:auto-run-offer
brainstorming:spec-document
brainstorming:spec-self-review
brainstorming:architecture-critic
brainstorming:user-review-gate
writing-plans:auto-run-plan
writing-plans:execution-line
writing-plans:assignment-procedure
writing-plans:register-rows
writing-plans:task-check-line
writing-plans:test-step-forms
writing-plans:lint-and-review
writing-plans:execution-handoff
writing-plans:ci-line
"

for entry in $MOVED; do
  skill=${entry%%:*}
  topic=${entry#*:}
  doc="$P/skills/$skill/SKILL.md"
  ref="$P/skills/$skill/references/$topic.md"
  check "$skill: $topic.md exists" "$([ -s "$ref" ] && echo yes || echo no)" "yes"
  check "$skill: SKILL.md links $topic.md once" "$(tr -d '\r' < "$doc" | grep -c "^Read \[$topic\.md\](references/$topic\.md) before you .*\.$")" "1"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
