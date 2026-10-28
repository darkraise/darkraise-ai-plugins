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

broken_links() { # broken_links <markdown file>: relative link targets that do not exist
  local file=$1 dir target out=""
  dir=$(dirname "$file")
  for target in $(tr -d '\r' < "$file" | grep -o '](\([^)#]*\)' | sed 's/^](//'); do
    case "$target" in ''|http*|*'<'*|*'['*) continue ;; esac
    [ -e "$dir/$target" ] || out="$out $target"
  done
  printf '%s' "$out"
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
writing-plans:lint-and-review
writing-plans:execution-handoff
"

for entry in $MOVED; do
  skill=${entry%%:*}
  topic=${entry#*:}
  doc="$P/skills/$skill/SKILL.md"
  ref="$P/skills/$skill/references/$topic.md"
  check "$skill: $topic.md exists" "$([ -s "$ref" ] && echo yes || echo no)" "yes"
  check "$skill: SKILL.md links $topic.md once" "$(tr -d '\r' < "$doc" | grep -c "^Read \[$topic\.md\](references/$topic\.md) before you .*\.$")" "1"
  check "$skill: $topic.md has no broken link" "$(broken_links "$ref")" ""
done

for skill in brainstorming writing-plans; do
  doc="$P/skills/$skill/SKILL.md"
  check "$skill: SKILL.md has no broken link" "$(broken_links "$doc")" ""
  bytes=$(wc -c < "$doc" | tr -d ' ')
  check "$skill: SKILL.md is at most 20000 bytes" "$([ "$bytes" -le 20000 ] && echo yes || echo "no ($bytes)")" "yes"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
