#!/usr/bin/env bash
# Once the last task is complete nothing hands off: the final review and
# finishing run in the same session, and an auto run finishes on the recorded
# choice first.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
SKILL_VIEW_DIR=$(mktemp -d)
trap 'rm -rf "$SKILL_VIEW_DIR"' EXIT
. "$HERE/skill-view.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" && echo yes || echo no)" "yes"
}

SDD="$P/skills/subagent-driven-development/SKILL.md"
. "$HERE/fixtures/sdd-text.sh"
EP="$(skill_view executing-plans)"
FIN="$P/skills/finishing-a-development-branch/SKILL.md"
H="$P/skills/handoff/SKILL.md"
FR="$P/reference/final-review.md"

names "subagent mode: --final is for the record" "$SDD_BUDGET" '`scripts/context-size --final` for the record, then'
names "subagent mode: the final phase never hands off" "$SDD_BUDGET" 'prints: the final phase never hands off, and a `review-package` budget line'
names "subagent mode: Final Review stays here" "$SDD" 'This runs in the session that completed the last task. Only a stop the'
names "inline mode: never a stop" "$EP" 'The last task completing is never a stop: the final review, its fix wave and'
names "inline mode: --final never hands off" "$EP" 'task'"'"'s `Task <N>: complete` line for the record: it never says `handoff`.'
names "inline mode: the final review stays here" "$EP" 'pass. In this mode it runs in this session: the final phase never hands off.'
names "handoff: plan saved outside an auto run" "$H" 'plan saved outside an auto run'
names "handoff: never a stop" "$H" 'The last task completing is never a stop in either execution'
names "final review: the same session" "$FR" 'the session that completed the last task: the'
names "finishing: the recorded choice first" "$FIN" 'Read `scripts/finish-choice get --plan PLAN_FILE`'
names "finishing: a spec-review deferral keeps a merge" "$FIN" 'A row deferred at the spec review, before the run started, counts as one'
names "subagent mode: recovery resumes the final phase" "$SDD" '3. When every task has its `complete` line, run `scripts/context-size --final`'
names "inline mode: recovery resumes the final phase" "$EP" '3. When every task has its `complete` line, run `scripts/context-size --final`'
names "handoff: a saved plan switches in place" "$H" 'a compaction that left too much. A saved plan switches in place instead'
names "subagent mode: phase final right after the last task" "$SDD" '`scripts/auto-run phase final` next, before any budget check and before the'
names "inline mode: phase final right after the last task" "$EP" 'merge), run `scripts/auto-run phase final` next, before any budget check and'
names "finishing: get reads the spec's line" "$FIN" 'with nothing recorded in this checkout'"'"'s plan workspace it reads the spec'"'"'s'
names "README: the last task completing is never a stop" "$P/README.md" 'The last task completing is never a stop'
names "subagent mode: the spec's Finish line replaces the question" "$SDD_SETUP" '`scripts/finish-choice set <action> --plan PLAN_FILE` instead of asking.'
names "inline mode: the spec's Finish line replaces the question" "$EP" '`scripts/finish-choice set <action> --plan PLAN_FILE` instead of asking.'
check "handoff: no spec-to-plan trigger is left" "$(grep -c 'spec-to-plan' "$H")" "0"
for f in "$SDD" "$SDD_BATCHING" "$SDD_BUDGET" "$SDD_EXAMPLE" "$SDD_FINISH_RULINGS" "$SDD_GRAPH" "$SDD_LEDGER" "$SDD_RATIONALE" "$SDD_RATIONALIZATIONS" "$SDD_RULING_SEAT" "$SDD_SETUP" "$EP" "$H" "$FR"; do
  check "${f#"$P"/} no longer hands off after --final" "$(tr '\n' ' ' < "$f" | tr -s ' ' | grep -cE -- '--final` (said|says) `handoff`')" "0"
done

# Review depth: the final review by depth. Matched with line breaks folded.
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
says() { # says <label> <file> <text>
  check "$1" "$(flat "$2" | grep -qF -- "$3" && echo yes || echo no)" "yes"
}
says "final review: depth-route runs before step 0" "$FR" 'Before step 0 run `scripts/depth-route PLAN_FILE`'
says "final review: the depth is ledgered" "$FR" 'append `Review depth: <depth> (<reason>)` to the ledger'
says "final review: a recovered review reads the ledgered depth" "$FR" 'read that line and run no new route'
names "final review: gates run at every depth" "$FR" '| 0 Gates | runs | runs | runs |'
names "final review: UI proof runs at every depth" "$FR" '| 0.2 UI proof | runs | runs | runs |'
names "final review: QA is skipped at light only" "$FR" '| 0.5 Acceptance QA | skipped | runs | runs |'
names "final review: the Claude review runs at every depth" "$FR" '| 1 Claude review | runs | runs | runs |'
names "final review: the lens column by depth" "$FR" '| 1 Lenses | `security` only, when it applies | at most 2 | up to `lensCap` |'
names "final review: the Codex round is skipped below full" "$FR" '| 2 Codex round | skipped | skipped | as today |'
names "final review: the dedupe judge needs two lists" "$FR" '| 3 Dedupe judge | never (one list) | never (one list) | with two lists |'
says "final review: the fix wave runs at every depth" "$FR" 'The fix wave and its scoped re-review run at every depth.'
says "final review: light writes the skipped QA line" "$FR" 'append `Acceptance QA: skipped (depth light)` to the ledger, once'
says "final review: recovery reads skipped as complete" "$FR" 'Recovery reads that line as `Acceptance QA: complete`'
says "final review: the Codex round skip is said" "$FR" '`codex round skipped (depth <d>)`'
says "final review: the skipped round leaves nothing to wait for" "$FR" 'or depth light or standard), there is nothing to wait for'
says "final review: lens-route reads the depth itself" "$FR" '`lens-route` reads the depth itself'
says "final review: every lens-skipped line reaches the ledger" "$FR" 'as `final review lens-skipped <id> reason=<reason>`, whatever its reason'
says "final review: the integration check starts beside the reviewers" "$FR" '**Integration check.** In the same message as the Claude review'
says "final review: it runs through suite-run" "$FR" $'through `bash <plugin-root>/scripts/suite-run -- bash -c \'<integration check>\'`'
says "final review: in the background at the review head" "$FR" 'as a background command at the same HEAD the Claude review reads'
says "final review: the check never shares the checkout QA writes in" "$FR" 'QA commits in the checkout while it runs, so the run must not share it'
says "final review: a failure the merge base shares is no finding" "$FR" 'A failing line that does not also fail at MERGE_BASE is a finding'
says "final review: the suite finding enters the fix wave as confirmed" "$FR" 'A `[suite]` finding enters the fix wave as confirmed, as a `[qa]` finding does'
says "final review: the fix wave waits for the integration check" "$FR" 'The fix wave also waits for the integration check started in step 1'
says "final review: the fix subagent runs the integration check in the same form" "$FR" $'Tell the fix subagent to run the plan\'s `**Integration check:**` command the same way, `bash <plugin-root>/scripts/suite-run -- bash -c \'<integration check>\'`'
says "finishing: Step 1 runs the integration check in the form the final review recorded" "$FIN" $'`bash <plugin-root>/scripts/suite-run -- bash -c \'<integration check>\'`, the form the final review recorded, so its pass is reused'

# Waiting for CI (docs/dforge/specs/2026-10-31-test-tiers-and-ci-parity-design.md, part 5).
ER="$P/skills/finishing-a-development-branch/references/execute-choice.md"
names "execute-choice: the wait section" "$ER" '### Wait for CI'
says "execute-choice: wait only when finishing pushed" "$ER" 'Finishing waits for CI only when it pushed: Option 2, or an Early CI push whose head is the final head.'
says "execute-choice: the run is found by commit" "$ER" 'Run `gh run list --commit <sha>`, then `gh run watch <id>` as a background Bash command.'
says "execute-choice: the Bash timeout" "$ER" 'Set the call'"'"'s `timeout` to (90 × 60 + 120) × 1000 ms, because a background call otherwise stops at 30 minutes.'
says "execute-choice: an auto run ends the turn" "$ER" 'In an auto run, end the turn and resume on the notification.'
says "execute-choice: no run appears" "$ER" 'When no run for the commit appears within 60 seconds, print one line saying so and skip the wait; never call the branch CI-green.'
says "execute-choice: the CI ledger line" "$ER" 'Record `CI: <sha7> run <id> <green|red|still running at 90 min>` on the ledger.'
says "execute-choice: green completes the branch" "$ER" 'Green completes the branch.'
says "execute-choice: red reopens through debugging" "$ER" 'Red reopens the branch through dforge:systematic-debugging, naming each failed job and step; push the fix and wait again.'
says "execute-choice: a run still going is not done" "$ER" 'A run still going after 90 minutes is reported as not done, never as done.'
says "execute-choice: an auto run stops on a run still going" "$ER" 'In an auto run, a run still going after 90 minutes runs `scripts/auto-run stop --reason "CI run <id> still running at 90 min"` before the final message.'
says "execute-choice: the skips print one line" "$ER" 'With keep, no `gh` (`command -v gh` fails), `gh` not logged in (`gh auth status` exits non-zero), or a CI line of `none`, print why in one line and skip the wait; never call the branch CI-green.'
says "execute-choice: a local merge waits for nothing" "$ER" 'After a local merge, nothing was pushed, so do not wait: print `gh run list --commit <merge sha>` and `gh run watch <id>` for your human partner to run after pushing, and never call the branch CI-green.'
says "execute-choice: a merge deletes the early remote branch" "$ER" 'On a plan with an `**Early CI:**` line, run `git push origin --delete <feature-branch>` after the local merge.'
says "execute-choice: the delete keeps a branch holding unmerged commits" "$ER" 'the sha it prints is an ancestor of the merge (`git merge-base --is-ancestor <sha> HEAD`)'
says "execute-choice: keep names the remote branch" "$ER" 'With keep on such a plan, say that the remote branch `origin/<feature-branch>` exists.'
says "finishing: the final message quotes the CI line" "$FIN" 'When the ledger holds a `CI:` line, the final message quotes it.'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
