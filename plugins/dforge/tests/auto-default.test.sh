#!/usr/bin/env bash
# Under autoRun=on, brainstorming's one stop is the spec review: each check is
# a whole instruction, not a keyword.
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

B="$P/skills/brainstorming/SKILL.md"
names "the section" "$B" '## Auto by default (`autoRun=on`)'
names "the setting" "$B" '- `autoRun=on`, the default: the architectural path runs as Auto by default'
names "designApproval has no effect" "$B" '`autoRun=on`, which presents no design.'
names "specReview has no effect" "$B" 'Gate and go on to Implementation. It has no effect under `autoRun=on`:'
names "the checklist points at the section" "$B" '**Architectural:** (under `autoRun=on`, the default on Claude Code, steps 6-8'
names "no sub-project split" "$B" 'Under `autoRun=ask` or `autoRun=off` only (under `on`, one spec covers the whole request)'
names "one spec" "$B" 'One spec covers the whole request: no'
names "acceptance waits for the review" "$B" 'Under `autoRun=on` skip this step and the offer below: the statements are'
names "no design presented" "$B" '; under `autoRun=on` present no design (see Auto by default)'
names "self-review accepts an open statement" "$B" 'Under `autoRun=on`, a statement rated `medium` or `low` passes when it carries its `Q:`'
names "the critic gets the decisions" "$B" 'spec path, the approved design sections verbatim (under `autoRun=on`, the'
names "the gate is the spec review" "$B" 'Under `autoRun=on`, this gate is the spec review message in Auto by default.'
names "no plan budget check in a run" "$B" 'an auto run skip this check: the plan is always written in this session.'
names "the review rulings section" "$B" '`## Review rulings`'
names "the three approvals" "$B" '- **Approve and run unattended**, **Approve, keep the normal stops**, or'
names "the finish line" "$B" '`Finish: <merge|pr|keep>` line in `## Decisions`;'
names "specReview never skips it" "$B" '`specReview=false` does not skip this stop.'
names "the finish line is a bare paragraph" "$B" 'recorded as its own paragraph (no list'
names "a review deferral carries its command" "$B" '`scripts/register add <register> "A<n>: <statement>" --state deferred --note "Q: <question>"`;'
names "a review deferral opens a register" "$B" 'with no register open, first open `<docs>/registers/<date>-<spec-slug>.md`'
names "start takes the deferrals' register" "$B" '`--register <path>` when a register is open, and always the register'
W="$P/skills/writing-plans/SKILL.md"
names "writing-plans: a listed launch at the switch" "$W" '(on exit 5, wait for or stop what `scripts/in-flight` lists and run it'
FIN="$P/skills/finishing-a-development-branch/SKILL.md"
names "finishing: get reads the spec line" "$FIN" '`Finish:` line itself and records it with `"source": "spec"`, so the spec'
names "finishing: a final residual keeps a merge" "$FIN" 'the run added. `merge` also keeps when the run added a deferred row whose'
names "finishing: the final message lists residuals" "$FIN" 'it; the `final review residual` rows among them),'
names "finishing: a deferred task keeps its rows deferred" "$FIN" '`(deferred by the auto run)` is set with'
check "finishing: no read-the-spec-and-set clause" "$(grep -c 'first run `scripts/finish-choice set <action> --plan PLAN_FILE`:' "$FIN")" "0"
names "rulings are imported" "$B" '`scripts/auto-run ruling add "Fable, spec: <line>"`'
names "the old pin survives" "$B" '`autoRun=off`: never offer an auto run'
names "a Codex host runs attended" "$B" 'and on a Codex host `on` behaves as `off`. Steps 1-5'
names "Fable's open items are asked at the review" "$B" '- every item Fable left undecided, and every critic Blocker it did not'
names "critic prompt: the decisions" "$P/skills/brainstorming/references/architecture-critic-prompt.md" 'or under `autoRun=on` the spec'"'"'s'
names "using-dforge: the approval is the spec review" "$P/skills/using-dforge/SKILL.md" 'still get approval (under `autoRun=on`, the spec review).'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
