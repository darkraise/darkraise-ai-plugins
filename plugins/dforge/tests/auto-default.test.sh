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
names "one spec" "$P/skills/brainstorming/references/auto-by-default.md" 'One spec covers the whole request: no'
names "acceptance waits for the review" "$P/skills/brainstorming/references/drafting-acceptance.md" 'Under `autoRun=on` skip this step and the offer below: the statements are'
names "no design presented" "$P/skills/brainstorming/references/design-phase.md" '; under `autoRun=on` present no design (see Auto by default)'
names "self-review accepts an open statement" "$P/skills/brainstorming/references/spec-self-review.md" 'Under `autoRun=on`, a statement rated `medium` or `low` passes when it carries its `Q:`'
names "the critic gets the decisions" "$P/skills/brainstorming/references/architecture-critic.md" 'spec path, the approved design sections verbatim (under `autoRun=on`, the'
names "the gate is the spec review" "$P/skills/brainstorming/references/user-review-gate.md" 'Under `autoRun=on`, this gate is the spec review message in Auto by default.'
names "no plan budget check in a run" "$B" 'an auto run skip this check: the plan is always written in this session.'
names "the review rulings section" "$P/skills/brainstorming/references/auto-by-default.md" '`## Review rulings`'
names "the three approvals" "$P/skills/brainstorming/references/auto-by-default.md" '- **Approve and run unattended**, **Approve, keep the normal stops**, or'
names "the finish line" "$P/skills/brainstorming/references/auto-by-default.md" '`Finish: <merge|pr|keep>` line in `## Decisions`;'
names "specReview never skips it" "$P/skills/brainstorming/references/auto-by-default.md" '`specReview=false` does not skip this stop.'
names "the finish line is a bare paragraph" "$P/skills/brainstorming/references/auto-by-default.md" 'recorded as its own paragraph (no list'
names "a review deferral carries its command" "$P/skills/brainstorming/references/auto-by-default.md" '`scripts/register add <register> "A<n>: <statement>" --state deferred --note "Q: <question>"`;'
names "a review deferral opens a register" "$P/skills/brainstorming/references/auto-by-default.md" 'with no register open, first open `<docs>/registers/<date>-<spec-slug>.md`'
names "start takes the deferrals' register" "$P/skills/brainstorming/references/auto-by-default.md" '`--register <path>` when a register is open, and always the register'
W="$P/skills/writing-plans/SKILL.md"
names "writing-plans: a listed launch at the switch" "$P/skills/writing-plans/references/auto-run-plan.md" '(on exit 5, wait for or stop what `scripts/in-flight` lists and run it'
FIN="$P/skills/finishing-a-development-branch/SKILL.md"
names "finishing: get reads the spec line" "$FIN" '`Finish:` line itself and records it with `"source": "spec"`, so the spec'
names "finishing: a final residual keeps a merge" "$FIN" 'the run added. `merge` also keeps when the run added a deferred row whose'
names "finishing: the final message lists residuals" "$FIN" 'it; the `final review residual` rows among them),'
names "finishing: a deferred task keeps its rows deferred" "$FIN" '`(deferred by the auto run)` is set with'
check "finishing: no read-the-spec-and-set clause" "$(cat "$FIN" "$P/skills/finishing-a-development-branch/references/"*.md | grep -c 'first run `scripts/finish-choice set <action> --plan PLAN_FILE`:')" "0"
names "rulings are imported" "$P/skills/brainstorming/references/auto-by-default.md" '`scripts/auto-run ruling add "Fable, spec: <line>"`'
names "the old pin survives" "$B" '`autoRun=off`: never offer an auto run'
names "a Codex host runs attended" "$P/skills/brainstorming/references/auto-by-default.md" 'and on a Codex host `on` behaves as `off`. Steps 1-5'
names "Fable's open items are asked at the review" "$P/skills/brainstorming/references/auto-by-default.md" '- every item Fable left undecided, and every critic Blocker it did not'
names "critic prompt: the decisions" "$P/skills/brainstorming/references/architecture-critic-prompt.md" 'or under `autoRun=on` the spec'"'"'s'
names "using-dforge: the approval is the spec review" "$P/skills/using-dforge/SKILL.md" 'still get approval (under `autoRun=on`, the spec review).'

# Review depth: the spec phase by depth. Matched with line breaks folded.
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
says() { # says <label> <file> <text>
  check "$1" "$(flat "$2" | grep -qF -- "$3" && echo yes || echo no)" "yes"
}
lacks() { # lacks <label> <file> <text>
  check "$1" "$(flat "$2" | grep -qF -- "$3" && echo yes || echo no)" "no"
}
AR="$P/reference/auto-run.md"
PROC='`Process: architectural, <inline|subagent>, depth <d> — <triggers>`'
says "using-dforge: the Process line names the depth" "$P/skills/using-dforge/SKILL.md" "$PROC"
says "using-dforge: the depth comes from depth-route" "$P/skills/using-dforge/SKILL.md" '`<d>` from `scripts/depth-route --spec-triggers`'
says "brainstorming: the Process line names the depth" "$B" "$PROC"
says "brainstorming: the depth comes from depth-route" "$B" 'take `<d>` from `scripts/depth-route --spec-triggers <ids>`'
says "brainstorming: a later trigger reruns depth-route and the depth only rises" "$B" 'reruns `scripts/depth-route --spec-triggers` with the whole list, and the depth can only rise'
says "brainstorming: an owner line survives the ratchet" "$B" 'a `**Depth:** <d> — owner` line is left as it is'
says "brainstorming: the depth decides the fold, not the triggers" "$P/skills/brainstorming/references/architecture-critic.md" 'The depth decides, not the trigger list'
says "brainstorming: an owner full line gets the separate critic" "$P/skills/brainstorming/references/architecture-critic.md" 'a spec whose line reads `**Depth:** full — owner` and holds no risk trigger gets the separate critic'
says "brainstorming: light runs the self-review round only" "$P/skills/brainstorming/references/auto-by-default.md" 'At `light`, run the spec self-review round and nothing else: no critic, no Fable review'
says "brainstorming: standard folds the critic and runs no second round" "$P/skills/brainstorming/references/auto-by-default.md" 'with the critic folded into it (Architecture critic), and no second round'
says "brainstorming: a Codex host runs the spec phase as full" "$P/skills/brainstorming/references/architecture-critic.md" 'On a Codex host the spec phase runs as `full` at every depth'
says "brainstorming: light reports the critic as skipped" "$P/skills/brainstorming/references/architecture-critic.md" '`Critic: skipped (depth light)`'
says "brainstorming: the spec review names the depth" "$P/skills/brainstorming/references/auto-by-default.md" '`Depth: <d> — <reasons>`'
says "brainstorming: the light approve option says the plan is not a stop" "$P/skills/brainstorming/references/auto-by-default.md" '(depth light: the plan is not a stop; execution follows in this session)'
says "brainstorming: the owner sets the depth under Changes needed" "$P/skills/brainstorming/references/auto-by-default.md" 'sets the depth by hand under **Changes needed**: write `**Depth:** <d> — owner` in the spec'
says "brainstorming: no rulings to import at light" "$P/skills/brainstorming/references/auto-by-default.md" '(none at depth light)'
says "brainstorming: self-review checks the Depth line" "$P/skills/brainstorming/references/spec-self-review.md" 'its first word is `light`, `standard` or `full`'
says "brainstorming: every architectural spec carries the Depth line" "$P/skills/brainstorming/references/spec-document.md" 'carries a `**Depth:**` line directly below its `**Execution strategy:**` line'
lacks "brainstorming: the fold no longer keys on the Process line's triggers" <(cat "$P/skills/brainstorming/SKILL.md" "$P/skills/brainstorming/references/"*.md) 'your Process line names neither irreducible risk nor a new'
says "auto-run.md: the spec depth sizes the phase" "$AR" 'The spec'"'"'s `**Depth:**` line sizes this phase'
says "auto-run.md: light dispatches no critic and no Fable review" "$AR" 'dispatch no critic and no Fable review, record no spec ruling'
says "auto-run.md: light under ask reaches execution with no reader" "$AR" 'reaches execution with no reader of the written spec'
says "auto-run.md: the critic folds at depth standard" "$AR" 'folds the critic into Fable'"'"'s first round at depth standard'
says "auto-run.md: no second Fable round at standard" "$AR" 'at depth `standard` no second round runs'
says "auto-run.md: finishing lists every lens-skipped line" "$AR" '`final review lens-skipped <id> reason=<reason>` line in the ledger, whatever its reason'
says "auto-run.md: light finishing lists the unverified test statements" "$AR" 'every `test` statement of the spec under `not verified (depth light)`'
says "brainstorming: the open line decides a second round only at full" "$P/skills/brainstorming/references/architecture-critic.md" 'decides whether a second round runs at depth `full`; at `standard` none runs.'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
