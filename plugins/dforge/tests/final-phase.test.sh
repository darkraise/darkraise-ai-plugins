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
EP="$P/skills/executing-plans/SKILL.md"
FIN="$P/skills/finishing-a-development-branch/SKILL.md"
H="$P/skills/handoff/SKILL.md"
FR="$P/reference/final-review.md"

names "subagent mode: --final is for the record" "$SDD" '`scripts/context-size --final` for the record, then'
names "subagent mode: the final phase never hands off" "$SDD" 'prints: the final phase never hands off, and a `review-package` budget line'
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
names "subagent mode: the spec's Finish line replaces the question" "$SDD" '`scripts/finish-choice set <action> --plan PLAN_FILE` instead of asking.'
names "inline mode: the spec's Finish line replaces the question" "$EP" '`scripts/finish-choice set <action> --plan PLAN_FILE` instead of asking.'
check "handoff: no spec-to-plan trigger is left" "$(grep -c 'spec-to-plan' "$H")" "0"
for f in "$SDD" "$EP" "$H" "$FR"; do
  check "${f#"$P"/} no longer hands off after --final" "$(tr '\n' ' ' < "$f" | tr -s ' ' | grep -cE -- '--final` (said|says) `handoff`')" "0"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
