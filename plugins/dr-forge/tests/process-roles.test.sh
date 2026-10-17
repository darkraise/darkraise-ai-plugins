#!/usr/bin/env bash
# The process roles (analyst, architecture critic, QA and review lenses) live
# in skill and reference text; each check pins one whole instruction.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" 2>/dev/null && echo yes || echo no)" "yes"
}

QA="$P/reference/acceptance-qa.md"
names "qa: the seat" "$QA" 'dispatches `dr-forge:impl-sonnet-high`'
names "qa: never reads the plan" "$QA" 'You may not read the plan, the'
names "qa: expectations first" "$QA" 'the spec text alone, as literal values in the test'
names "qa: test names" "$QA" 'Each test name starts with `A<n>:`'
names "qa: never fixes the code" "$QA" 'An assertion failure is a finding, which you never fix'
names "qa: detached mutation worktree" "$QA" 'git worktree add --detach [WORKSPACE]/qa-mutation HEAD'
names "qa: report path" "$QA" '`[WORKSPACE]/acceptance-report.md`'
names "qa: ambiguous result" "$QA" '`cannot-test: ambiguous`'
names "qa: rerun mode" "$QA" '`rerun`: the acceptance file may already exist'

BS="$P/skills/brainstorming/SKILL.md"
names "analyst: the checklist step" "$BS" '7. **Draft acceptance** — numbered, tagged, rated statements'
names "analyst: auto-run offer follows it" "$BS" 'right after the Draft acceptance step and before you'
names "analyst: the line format" "$BS" '`A<n>. [<test|demo>[, neg], <high|confirmed>] <statement>`'
names "analyst: the verdict options" "$BS" '**Right**, **Wrong, or not wanted** and **Not sure**'
names "analyst: not sure defers" "$BS" '--state deferred --note "Q: <question>"'
names "analyst: confirmed is the human's" "$BS" '`confirmed` is reserved for a verdict from your human partner'
names "analyst: self-review item" "$BS" 'every statement matches `A<n>. [<test|demo>[, neg], <high|confirmed>]'
after=$(grep -n '^## After the Design (architectural path)$' "$BS" | cut -d: -f1)
draft=$(grep -n '^\*\*Drafting acceptance:\*\*$' "$BS" | cut -d: -f1)
offer=$(grep -n '^\*\*Offering an auto run:\*\*$' "$BS" | cut -d: -f1)
check "analyst: drafting sits between After the Design and the auto-run offer" \
  "$([ -n "$after" ] && [ -n "$draft" ] && [ -n "$offer" ] && [ "$after" -lt "$draft" ] && [ "$draft" -lt "$offer" ] && echo yes || echo no)" "yes"
names "analyst: the process graph" "$BS" '"Draft acceptance\n(rate; ask below high)" -> "Offer an auto run\n(once, unless autoRun=off)";'
names "analyst: spec reviewer checks the format" "$P/skills/brainstorming/references/spec-document-reviewer-prompt.md" \
  'a rating other than `high` or `confirmed`'
names "analyst: plans never build on a deferred statement" "$P/skills/writing-plans/SKILL.md" \
  'A row whose Item begins `A<n>:` is a deferred acceptance statement'

AC="$P/criteria/architecture-critique.md"
check "critic: criteria ids" \
  "$(grep -o '{#[a-z0-9_]\{1,\}}' "$AC" 2>/dev/null | tr -d '{#}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')" \
  "failure operability simplest unstated"
CP="$P/skills/brainstorming/references/architecture-critic-prompt.md"
names "critic: the prompt does not score" "$CP" 'do not score them 1-20'
names "critic: ranked findings" "$CP" 'Blocker / High / Medium / Nit'
names "critic: one change" "$CP" 'If I could change one thing, it would be'
names "critic: checklist step" "$BS" '11. **Architecture critic** — one `dr-forge:judge-opus` round'
names "critic: findings section" "$BS" 'answered in a `## Critic findings` section'
names "critic: counts in the review request" "$BS" 'Critic: <b> Blocker, <h> High (<f> fixed, <a> answered), <m> Medium'
names "critic: spec reviewer checks answers" "$P/skills/brainstorming/references/spec-document-reviewer-prompt.md" \
  'a Blocker or High critic finding with neither a fix nor an answer'
names "critic: the process graph" "$BS" '"Architecture critic\n(one judge-opus round)" -> "User reviews spec?";'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
