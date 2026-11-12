#!/usr/bin/env bash
# The process roles (analyst, architecture critic, QA and review lenses) live
# in skill and reference text; each check pins one whole instruction.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
. "$HERE/fixtures/sdd-text.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" 2>/dev/null && echo yes || echo no)" "yes"
}

AC="$P/criteria/architecture-critique.md"
check "critic: criteria ids" \
  "$(grep -o '{#[a-z0-9_]\{1,\}}' "$AC" 2>/dev/null | tr -d '{#}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')" \
  "failure operability simplest unstated"

for f in "$SDD_LEDGER" "$P/skills/executing-plans/SKILL.md"; do
  s=$(basename "$(dirname "$f")")/$(basename "$f")
  names "$s: complete line" "$f" 'Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo'
done

TRP="$P/skills/subagent-driven-development/references/task-reviewer-prompt.md"
names "task reviewer: lens section" "$TRP" '## Lens Criteria'
names "task reviewer: the placeholder" "$TRP" '`[LENS_FILES]` — OPTIONAL'

# Matched with line breaks and runs of spaces folded, so a phrase may wrap.
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
says() { # says <label> <file> <text>
  check "$1" "$(flat "$2" | grep -qF -- "$3" && echo yes || echo no)" "yes"
}
WPF="$P/skills/writing-plans/references/test-step-forms.md"
says "writing-plans forms: the Extend form heading" "$WPF" '- [ ] **Step 1: Extend the test `<file>::<name>`**'
says "writing-plans forms: the Covered by form heading" "$WPF" $'- [ ] **Step 1: Covered by Task <N>\'s test `<name>`**'
LENS="$P/criteria/lenses/test-quality.md"
names "lens: the redundant criterion" "$LENS" '### Redundant Tests {#redundant}'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
