#!/usr/bin/env bash
# Each check pins a line form a script parses from what the document tells a session to write, or a file the skills link to.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" && echo yes || echo no)" "yes"
}

names "the finish line" "$P/skills/brainstorming/references/auto-by-default.md" '`Finish: <merge|pr|keep>` line in `## Decisions`;'
W="$P/skills/writing-plans/SKILL.md"

# Matched with line breaks folded.
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
says() { # says <label> <file> <text>
  check "$1" "$(flat "$2" | grep -qF -- "$3" && echo yes || echo no)" "yes"
}

# CI parity (test tiers plan, part 5): the reference, the plan header's CI line
# and its early-CI forms.
CIP="$P/reference/ci-parity.md"
CIL="$P/skills/writing-plans/references/ci-line.md"
check "ci-parity.md exists" "$([ -s "$CIP" ] && echo yes || echo no)" "yes"

names "writing-plans: the header template has a CI line" "$W" '**CI:** '
says "writing-plans: the CI line grammar" "$CIL" '`<workflow files>` — platforms: <list> — local: `<cmd>`; `<cmd>` — uncovered: <platforms or none>'
says "writing-plans: the early-CI wave form" "$CIL" '**Early CI:** after wave <k> — consented <YYYY-MM-DD>'
says "writing-plans: the early-CI task form" "$CIL" '**Early CI:** after task <n> — consented <YYYY-MM-DD>'

# Docs pointers: pointers name the file that holds their target.
SDD_REFS="$P/skills/subagent-driven-development/references"
check "the Recovery pointers resolve" "$([ -s "$SDD_REFS/ledger.md" ] && [ -s "$P/skills/executing-plans/references/recovery.md" ] && echo yes || echo no)" "yes"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
