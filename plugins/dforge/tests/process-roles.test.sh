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
names "analyst: auto-run offer follows it" "$P/skills/brainstorming/references/auto-run-offer.md" 'right after the Draft acceptance step and before you'
names "analyst: the line format" "$P/skills/brainstorming/references/drafting-acceptance.md" '`A<n>. [<test|demo>[, neg], <high|confirmed>] <statement>`'
names "analyst: the verdict options" "$P/skills/brainstorming/references/drafting-acceptance.md" '**Right**, **Wrong, or not wanted** and **Not sure**'
names "analyst: not sure defers" "$P/skills/brainstorming/references/auto-by-default.md" '--state deferred --note "Q: <question>"'
names "analyst: confirmed is the human's" "$P/skills/brainstorming/references/drafting-acceptance.md" '`confirmed` is reserved for a verdict from your human partner'
names "analyst: self-review item" "$P/skills/brainstorming/references/spec-self-review.md" 'every statement matches `A<n>. [<test|demo>[, neg], <high|confirmed>]'
after=$(grep -n '^## After the Design (architectural path)$' "$BS" | cut -d: -f1)
draft=$(grep -n '^\*\*Drafting acceptance:\*\*$' "$BS" | cut -d: -f1)
offer=$(grep -n '^\*\*Offering an auto run:\*\*$' "$BS" | cut -d: -f1)
check "analyst: drafting sits between After the Design and the auto-run offer" \
  "$([ -n "$after" ] && [ -n "$draft" ] && [ -n "$offer" ] && [ "$after" -lt "$draft" ] && [ "$draft" -lt "$offer" ] && echo yes || echo no)" "yes"
names "analyst: the process graph" "$P/skills/brainstorming/references/process-flow.md" '"Draft acceptance\n(rate; ask below high)" -> "Offer an auto run\n(once, unless autoRun=off)";'
names "analyst: live spec self-review checks the format" "$P/skills/brainstorming/references/spec-self-review.md" \
  'no rating other than `high` or `confirmed` appears'
names "analyst: plans never build on a deferred statement" "$P/skills/writing-plans/references/register-rows.md" \
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
names "critic: findings section" "$P/skills/brainstorming/references/architecture-critic.md" 'answered in a `## Critic findings` section'
names "critic: counts in the review request" "$P/skills/brainstorming/references/architecture-critic.md" 'Critic: <b> Blocker, <h> High (<f> fixed, <a> answered), <m> Medium'
names "critic: live Fable review checks answers" "$P/reference/auto-run.md" \
  'each answer to a Blocker or High finding'
names "critic: the process graph" "$P/skills/brainstorming/references/process-flow.md" '"Architecture critic\n(one judge-opus round)" -> "User reviews spec?";'
names "critic: folded into Fable at depth standard" "$P/skills/brainstorming/references/architecture-critic.md" 'and the spec'"'"'s depth is `standard`, dispatch no critic.'
names "critic: depth full keeps the separate round" "$P/skills/brainstorming/references/architecture-critic.md" 'new-subsystem trigger gives it, keeps the separate critic round.'
names "critic: the folded counts say so" "$P/skills/brainstorming/references/architecture-critic.md" 'followed by ` (in Fable'"'"'s review)` when the critic was folded into it.'
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
names "final review: lens replies as files" "$FR" 'each lens seat writes its report to `<workspace>/lens-<id>.md`'
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
for f in "$SDD_LEDGER" "$P/skills/executing-plans/SKILL.md"; do
  s=$(basename "$(dirname "$f")")/$(basename "$f")
  names "$s: dispatched line" "$f" 'Acceptance QA: dispatched (base <sha7>)'
  names "$s: complete line" "$f" 'Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo'
  names "$s: recovery points at step 0.5" "$f" '`Acceptance QA:` lines are written by'
  names "$s: recovery reads an existing report" "$f" 'line and `<workspace>/acceptance-report.md` present means read the report'
  names "$s: recovery re-dispatches once without a report" "$f" 'with no report, re-dispatch QA once with `[MODE]`'
done

names "task review: lens-route per task" "$P/reference/delegated-task.md" '`scripts/lens-route PLAN_FILE --task <N>`, and writes'
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

WP="$P/skills/writing-plans/SKILL.md"
DPR="$P/skills/writing-plans/references/drafter-prompt.md"
names "drafting: small plans stay in the session" "$WP" 'A plan of 1-3 tasks is drafted in the session.'
names "drafting: slices of 2-3, all at once" "$WP" 'split the index into slices of 2-3 consecutive tasks'
wp_flat=$(tr '\n' ' ' < "$WP" | tr -s ' ')
check "drafting: one drafter per slice, every slice in one message" "$(grep -cF 'dispatch one `dforge:drafter-sonnet` per slice, every slice in one message' <<<"$wp_flat")" "1"
check "drafting: the dispatch names the plugin root" "$(grep -cF 'the slice path (`<state>/drafts/<plan basename without .md>/tasks-A-B.md`) and the plugin root, as the template' <<<"$wp_flat")" "1"
names "drafting: joined without reading" "$WP" 'scripts/draft-pack --join PLAN_FILE'
names "drafting: a changed Contract re-dispatches every slice" "$WP" 're-dispatches every slice: a slice drafted against the old Contract'
names "drafting: Codex drafts in the session" "$WP" 'On a Codex host, draft every task in the session'
names "drafter prompt: the slice path" "$DPR" '**Write to:** [SLICE_PATH]'
names "drafter prompt: the scratch worktree" "$DPR" 'Write nothing in this checkout except [SLICE_PATH].'

# The contract-and-test plan shape (docs/dforge/specs/2026-10-26-faster-plans-design.md §1, §5).
# Matched with line breaks and runs of spaces folded, so a phrase may wrap.
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
says() { # says <label> <file> <text>
  check "$1" "$(flat "$2" | grep -qF -- "$3" && echo yes || echo no)" "yes"
}
lacks() { # lacks <label> <file> <text>
  check "$1" "$(flat "$2" | grep -qF -- "$3" && echo yes || echo no)" "no"
}
PRP="$P/skills/writing-plans/references/plan-reviewer-prompt.md"
AI="$P/skills/writing-plans/references/assigning-implementers.md"
PR="$P/criteria/plan-review.md"
ALLOWED='a configuration value, a generated-file or migration command, or a fixed constant the spec names'
says "shape: a task is a feature slice" "$WP" 'A task is a feature slice'
lacks "shape: bite-sized granularity is gone" <(cat "$P/skills/writing-plans/SKILL.md" "$P/skills/writing-plans/references/"*.md) '## Bite-Sized Task Granularity'
lacks "shape: no bite-sized wording" <(cat "$P/skills/writing-plans/SKILL.md" "$P/skills/writing-plans/references/"*.md) 'bite-sized'
says "shape: the task carries its interfaces, tests and verify commands" "$WP" 'its interfaces, the complete code of its tests, the decisions it embodies'
says "shape: implementation code only where no test pins it" "$WP" "$ALLOWED"
says "shape: Step 3 describes the implementation" "$WP" 'Step 3 describes the implementation; it carries no implementation code'
lacks "shape: Step 3 no longer carries the implementation" <(cat "$P/skills/writing-plans/SKILL.md" "$P/skills/writing-plans/references/"*.md) 'Step 3 carries the whole implementation.'
says "shape: a Codex host keeps code-given tasks" "$WP" 'On a Codex host, tasks keep the code-given shape'
says "shape: tests that assert nothing are placeholders" "$WP" 'Tests that describe behaviour without asserting it'
lacks "shape: the old how-not-shown ban is reworded" <(cat "$P/skills/writing-plans/SKILL.md" "$P/skills/writing-plans/references/"*.md) 'Steps that describe what to do without showing how'
says "shape: a Claude code task scores spec 2" "$P/skills/writing-plans/references/assignment-procedure.md" 'so it scores spec 2'
says "shape: Rule S at 6 on a Claude plan" "$P/skills/writing-plans/references/assignment-procedure.md" 'On a Claude plan, if `files + spec + coupling >= 6`'
says "shape: Rule S at 4 on a Codex plan" "$P/skills/writing-plans/references/assignment-procedure.md" 'on a `Host: codex` plan, if it is `>= 4`'
lacks "shape: no host-blind Rule S at 4" <(cat "$P/skills/writing-plans/SKILL.md" "$P/skills/writing-plans/references/"*.md) 'If `files + spec + coupling >= 4`, split'
says "drafter prompt: tests and interfaces, not code" "$DPR" 'gives the complete code of its tests'
says "drafter prompt: implementation code only where no test pins it" "$DPR" "$ALLOWED"
says "drafter prompt: tests fail on the current tree" "$DPR" 'confirm each fails for the reason the task fixes'
lacks "drafter prompt: no complete code of every step" "$DPR" 'gives the complete code of every step'
lacks "drafter prompt: no prototyping" "$DPR" 'You may prototype'
says "plan reviewer: a missing implementation body is not a finding" "$PRP" 'a missing implementation body is not a finding'
says "plan reviewer: a stub or missing test is" "$PRP" 'a missing or stub test is'
says "plan review criteria: a precise description is not a gap" "$PR" 'a task that describes its implementation precisely without its code is not a gap'
says "plan review criteria: implementation code only where no test pins it" "$PR" "$ALLOWED"
lacks "plan review criteria: no host-blind complete-code rule" "$PR" 'exact file paths, every code step carries the complete code'
says "assigning: a Claude code task scores spec 2" "$AI" 'gives its tests and interfaces but not its implementation, so it scores 2'
says "assigning: the Claude cap is 8" "$AI" 'Rule S caps a compliant Claude total at 8'
lacks "assigning: no cap at 6" "$AI" 'Rule S also caps a compliant total at 6'
says "spec review: Fable's second round needs an open Blocker or High" "$P/skills/brainstorming/references/auto-by-default.md" 'a second only when round 1 leaves a Blocker or High finding open'
says "spec review: the folded critic gets no second Fable round" "$P/skills/brainstorming/references/architecture-critic.md" 'No second Fable round runs at standard'
lacks "spec review: no unconditional answer check" <(cat "$P/skills/brainstorming/SKILL.md" "$P/skills/brainstorming/references/"*.md) 'which checks each Blocker and High answer'
says "auto-run.md: Fable's second round needs an open Blocker or High" "$P/reference/auto-run.md" 'A second runs only when round 1 leaves a Blocker or High finding open'
lacks "auto-run.md: no unconditional second round" "$P/reference/auto-run.md" 'At most two Fable rounds run (review, revise, re-review)'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
