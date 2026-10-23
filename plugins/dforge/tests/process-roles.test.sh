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
names "qa: the seat" "$QA" 'dispatches `dforge:impl-sonnet-high`'
names "qa: never reads the plan" "$QA" 'You may not read the plan, the'
names "qa: expectations first" "$QA" 'the spec text alone, as literal values in the test'
names "qa: test names" "$QA" 'Each test name starts with `A<n>:`'
names "qa: never fixes the code" "$QA" 'An assertion failure is a finding, which you never fix'
names "qa: detached mutation worktree" "$QA" 'git worktree add --detach [WORKSPACE]/qa-mutation HEAD'
names "qa: the committed tests reach the mutation worktree" "$QA" 'committed the acceptance file, so `HEAD` has it'
names "qa: tests are committed as they run" "$QA" 'Commit as you go: once a statement'"'"'s test has run'
names "qa: the mutation baseline passes first" "$QA" 'run that statement'"'"'s test there before changing anything'
names "qa: a setup error is not red" "$QA" 'A missing file, an import or a'
names "qa: report path" "$QA" '`[WORKSPACE]/acceptance-report.md`'
names "qa: ambiguous result" "$QA" '`cannot-test: ambiguous`'
names "qa: rerun mode" "$QA" '`rerun`: the acceptance file may already exist'
check "qa: the report lists only the statements given" "$(grep -qF -- 'demo — not executed' "$QA" && echo yes || echo no)" "no"

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
names "analyst: live spec self-review checks the format" "$BS" \
  'no rating other than `high` or `confirmed` appears'
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
names "critic: checklist step" "$BS" '11. **Architecture critic** — one `dforge:judge-opus` round'
names "critic: findings section" "$BS" 'answered in a `## Critic findings` section'
names "critic: counts in the review request" "$BS" 'Critic: <b> Blocker, <h> High (<f> fixed, <a> answered), <m> Medium'
names "critic: live Fable review checks answers" "$P/reference/auto-run.md" \
  'each answer to a Blocker or High finding'
names "critic: the process graph" "$BS" '"Architecture critic\n(one judge-opus round)" -> "User reviews spec?";'
names "critic: folded into Fable without a risk trigger" "$BS" 'and your Process line names neither irreducible risk nor a new'
names "critic: a risk trigger keeps the separate round" "$BS" 'a risk or new-subsystem trigger keeps the separate'
names "critic: the folded counts say so" "$BS" 'followed by ` (in Fable'"'"'s review)` when the critic was folded into it.'
names "auto-run.md: the critic may fold into Fable" "$P/reference/auto-run.md" 'which folds the critic into'

FR="$P/reference/final-review.md"
at() { grep -nF -- "$2" "$1" | head -n 1 | cut -d: -f1; }
g=$(at "$FR" '0. **Gates.**'); q=$(at "$FR" '0.5 **Acceptance QA.**')
k=$(at "$FR" 'Run `scripts/review-package PLAN_FILE MERGE_BASE HEAD`'); l=$(at "$FR" 'scripts/lens-route PLAN_FILE --final MERGE_BASE HEAD')
check "final review: gates, QA, package, lenses in order" \
  "$([ -n "$g" ] && [ -n "$q" ] && [ -n "$k" ] && [ -n "$l" ] && [ "$g" -lt "$q" ] && [ "$q" -lt "$k" ] && [ "$k" -lt "$l" ] && echo yes || echo no)" "yes"
names "final review: QA skipped when complete" "$FR" 'the ledger already holds `Acceptance QA: complete`'
names "final review: recovery from the report" "$FR" '`<workspace>/acceptance-report.md` exists, read it'
names "final review: recovery re-dispatch" "$FR" 'otherwise re-dispatch once with `[MODE]` `rerun`'
names "final review: leftover worktree" "$FR" 'git worktree remove --force <workspace>/qa-mutation'
names "final review: ambiguous goes to the ruling seat" "$FR" '`scripts/review-route PLAN_FILE --ruling acceptance-ambiguous`'
names "final review: lens replies as files" "$FR" 'save each reply to `<workspace>/lens-<id>.md`'
names "final review: residual acceptance failure" "$FR" 'is the one edit allowed on an acceptance test'
names "final review: a spent re-dispatch writes the report" "$FR" 'is spent: write `<workspace>/acceptance-report.md` yourself, with'
names "final review: the QA timer outlives the background default" "$FR" 'call'"'"'s `timeout` set to (`<s>` + 120) × 1000 ms'
names "final review: the QA timer scales with the statements" "$FR" '`<s>` = 600 + 180 × the number of'
names "final review: QA runs alongside the review" "$FR" 'Then go on to step 1 without waiting'
names "final review: the fix wave waits for QA" "$FR" '3. **Wait for QA.**'
names "final review: the review reads the QA dispatch SHA" "$FR" 'passed as that SHA, never as the word `HEAD`'
names "final review: the re-review covers QA's commits" "$FR" 'so the range holds QA'"'"'s'
names "final review: a small plan's lenses skip Minor" "$FR" '[Report Critical and Important findings only; leave Minor ones'
names "final review: the ledger goes by path" "$FR" 'never paste the lines into the prompt'
names "re-review: added acceptance tests are checked" "$P/skills/subagent-driven-development/references/re-review-prompt.md" 'When the fix diff adds or touches a test'
names "final review: V2 waits for QA to stop before cleanup" "$FR" 'Clean up only once it has stopped'
names "final review: the wait for a stopped QA agent is bounded" "$FR" 'finished, for 10 minutes at most in all.'
names "final review: a QA agent that cannot be stopped keeps its files" "$FR" 'If it cannot be stopped, leave its files in place'
names "final review: a skipped Codex round has no status line to wait for" "$FR" 'nothing to wait for: go straight to the one-list case'
names "final review: both acceptance test name forms are protected" "$FR" 'or with `a<n>_` where the framework forbids a colon'
names "final review: a test the QA report names is protected" "$FR" 'or which the QA report identifies as an'
names "re-review: a test the QA report names is protected" "$P/skills/subagent-driven-development/references/re-review-prompt.md" 'or which the QA report identifies as an acceptance test'
names "re-review: both acceptance test name forms" "$P/skills/subagent-driven-development/references/re-review-prompt.md" 'starts with `A<n>:` or'
names "final review: demos are counted from the spec" "$FR" 'counted from the final report, except `<d>`: the number of the spec'"'"'s'
names "final review: qa findings join the Claude list" "$FR" '`[qa]` finding from step 0.5 and every lens finding'
names "final review: qa findings skip the verifier" "$FR" 'A `[qa]` finding is not given to the verifier: it enters the fix wave as'
for f in "$P/skills/subagent-driven-development/SKILL.md" "$P/skills/executing-plans/SKILL.md"; do
  s=$(basename "$(dirname "$f")")
  names "$s: dispatched line" "$f" 'Acceptance QA: dispatched (base <sha7>)'
  names "$s: complete line" "$f" 'Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo'
  names "$s: recovery points at step 0.5" "$f" '`Acceptance QA:` lines are written by'
  names "$s: recovery reads an existing report" "$f" 'line and `<workspace>/acceptance-report.md` present means read the report'
  names "$s: recovery re-dispatches once without a report" "$f" 'with no report, re-dispatch QA once with `[MODE]`'
done

names "task review: lens-route per task" "$P/reference/delegated-task.md" 'run `scripts/lens-route PLAN_FILE --task <N>`'
TRP="$P/skills/subagent-driven-development/references/task-reviewer-prompt.md"
names "task reviewer: lens section" "$TRP" '## Lens Criteria'
names "task reviewer: lenses are not scored" "$TRP" 'do not score them, and do not add them to Verification Scores'
names "task reviewer: the placeholder" "$TRP" '`[LENS_FILES]` — OPTIONAL'
names "task reviewer: Minor issues are capped" "$TRP" 'List at most three Minor issues, the ones most worth fixing'
names "re-review: the A<n> question" "$P/skills/subagent-driven-development/references/re-review-prompt.md" \
  'still fail if the code violated statement A<n> of the spec?'
names "code reviewer: the A<n> question" "$P/skills/requesting-code-review/references/code-reviewer.md" \
  'would it fail if the code violated spec statement A<n>?'
names "requesting review: security lens" "$P/skills/requesting-code-review/SKILL.md" 'criteria/lenses/security.md'

names "milestone judge: A<n> tests are evidence" "$P/skills/closing-a-milestone/references/milestone-judge.md" \
  'is evidenced by the committed test whose name starts with `A<n>:`'
names "gates template: claude-security example" "$P/skills/running-gates/references/gates-template.md" \
  'claude --agent claude-security:claude-security'
NC="$P/reference/native-codex.md"
names "codex: critic and lens seats" "$NC" 'The architecture critic and every review lens are native judges at rank 8'
names "codex: QA seat" "$NC" 'Acceptance QA is a native implementer at `gpt-6.1-sol / high`'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
