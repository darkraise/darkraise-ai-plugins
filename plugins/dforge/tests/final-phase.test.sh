#!/usr/bin/env bash
# Once the last task is complete nothing hands off: the final review and
# finishing run in the same session, and an auto run finishes on the recorded
# choice first.
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

SDD="$P/skills/subagent-driven-development/SKILL.md"
. "$HERE/fixtures/sdd-text.sh"
EP="$P/skills/executing-plans/SKILL.md"
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
for f in "$SDD" "$SDD_BUDGET" "$SDD_LEDGER" "$EP" "$H" "$FR"; do
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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
