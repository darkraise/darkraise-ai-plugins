#!/usr/bin/env bash
# The delegated task loop, the waves, the final review and finishing call the
# step and suite scripts instead of describing their mechanics. Each call is a
# whole instruction a session follows, so each is pinned by the text that
# carries it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
DT="$P/reference/delegated-task.md"
PW="$P/reference/parallel-waves.md"
FR="$P/reference/final-review.md"
FIN="$P/skills/finishing-a-development-branch/SKILL.md"
IP="$P/skills/subagent-driven-development/references/implementer-prompt.md"
SDD="$P/skills/subagent-driven-development/SKILL.md"
INLINE="$P/skills/executing-plans/SKILL.md"
. "$HERE/fixtures/sdd-text.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" 2>/dev/null && echo yes || echo no)" "yes"
}
lacks() { # lacks <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" 2>/dev/null && echo yes || echo no)" "no"
}

# loop_steps - the delegated loop's text before its by-hand section
loop_steps() { sed '/^## The steps by hand/,$d' "$DT"; }

check "delegated-task.md has the by-hand section" "$(grep -c '^## The steps by hand' "$DT")" "1"

for call in 'task-step start PLAN_FILE N' 'task-step review PLAN_FILE N' 'task-step rereview PLAN_FILE N'; do
  check "the loop steps name $call" "$([ "$(loop_steps | grep -cF -- "$call")" -ge 1 ] && echo yes || echo no)" "yes"
done
for gone in 'scripts/review-package' 'scripts/task-brief PLAN_FILE N' 'Record BASE' 'run `scripts/lens-route'; do
  check "the loop steps no longer carry: $gone" "$(loop_steps | grep -cF -- "$gone")" "0"
done
check "only the cache rule runs date +%s in the loop steps" "$(loop_steps | grep -cF 'date +%s')" "1"
names "the fix message is a file of finding bullets" "$DT" '`<workspace>/task-<N>-fix-<R>.md`'
names "the fix message bullet format" "$DT" 'per open finding, `- <file>: <finding one-liner>`, then a blank line, then'
names "the skip rule needs --covered" "$DT" '`bash <plugin-root>/scripts/task-step rereview PLAN_FILE N` (with `--covered`'
names "a skipped re-review is recorded on the fix-round line" "$DT" 're-review skipped (<n> lines)'
names "the review step names the checks" "$DT" 'lines, each `clean` or the short SHA and what it found'
names "a repeated start keeps the recorded base" "$DT" 'keeps the recorded BASE'
names "the Codex seat line carries the fallback judge" "$DT" 'the judge after `fallback:` as the seat when it'
names "a failed route is read off the seat line" "$DT" '`(review-route exited <N>: …)`'
names "the gate line position is stated" "$DT" 'A `gate:` line right'

names "waves open a task with --wave" "$PW" '`bash <plugin-root>/scripts/task-step start PLAN_FILE N --wave <k>`'
names "waves review against the task ref" "$PW" '`--head <TASK_REF>` to'
names "waves pass the worktree to a Codex review" "$PW" '`--cwd <worktree>`, so that a Codex seat'
names "an overlap rebase passes --base" "$PW" '`task-step rereview PLAN_FILE N --head <TASK_REF> --base <that HEAD>`'
names "waves batch the in-hand cannot-verify items" "$PW" 'of every task whose review is in hand when one task reaches its cannot-verify'
names "the wave base check runs through suite-run" "$PW" '`bash <plugin-root>/scripts/suite-run -- bash -c '"'"'<the check>'"'"'`, in the'
check "the wave integration check runs through suite-run" "$(grep -cF 'scripts/suite-run -- bash -c' "$PW")" "2"
lacks "the wave check output file is gone" "$PW" 'wave-<k>-check.txt'

names "the final review runs suites through suite-run" "$FR" '`bash <plugin-root>/scripts/suite-run -- <command>`'
names "finishing runs the suite through suite-run" "$FIN" '`bash <plugin-root>/scripts/suite-run -- <test command>`, in the background'
names "finishing verifies the merged result through suite-run" "$FIN" 'bash <plugin-root>/scripts/suite-run -- <test command>'
names "implementers run the full suite through suite-run" "$IP" '`bash [PLUGIN_ROOT]/scripts/suite-run -- <the suite command>` and report'
lacks "implementers no longer run the full suite before committing" "$IP" 'full suite once before committing, not after every edit.'

names "the example workflow starts a task with task-step" "$SDD_EXAMPLE" '[task-step start PLAN_FILE 1:'
names "the example workflow reviews with task-step" "$SDD_EXAMPLE" '[task-step review PLAN_FILE 1:'
names "the example workflow re-reviews with task-step" "$SDD_EXAMPLE" '[task-step rereview PLAN_FILE 2:'
lacks "the example workflow no longer hand-runs review-package" "$SDD_EXAMPLE" 'review-package PLAN_FILE a1b2c3d HEAD'
names "the budget line is on every task-step digest" "$SDD" 'every `scripts/task-step`'
names "the rationalization row names the skip rule" "$SDD_RATIONALIZATIONS" 'Only `task-step rereview --covered` skips one'
lacks "the rationalization row no longer says every round is re-reviewed" "$SDD_RATIONALIZATIONS" 'Every round ends with a scoped re-review.'
names "inline mode hands delegated tasks to delegated-task.md" "$INLINE" '[delegated-task.md](../../reference/delegated-task.md) for this task instead'
check "inline mode restates no hand-run review mechanic" "$(grep -cE 'date \+%s|codex-gate|lens-route' "$INLINE")" "0"

# --- the group reviewer template ---
GRP="$P/skills/subagent-driven-development/references/group-reviewer-prompt.md"
check "the group reviewer template exists" "$([ -f "$GRP" ] && echo yes || echo no)" "yes"
for ph in '[GROUP_LIST]' '[PACKAGE_FILE]' '[REPORT_FILE]' '[PLUGIN_ROOT]'; do
  names "the group template carries $ph" "$GRP" "$ph"
done
names "the group template is a fenced prompt task-step can fill" "$GRP" '  prompt: |'
names "the group package holds one section per task" "$GRP" 'one section per task, headed `## Task <N>`'
names "the group reviewer scores each task on its own" "$GRP" 'Score each task on its own'
names "the group report holds one block per task" "$GRP" 'one block per task, headed `### Task <N>`'
names "a group finding names its task" "$GRP" 'prefix its file with `(Task <N>) `'
names "a finding in one task never fails another" "$GRP" 'A finding in one task never fails another task'
names "the group reviewer reads a section's lens files" "$GRP" 'a `**Lenses:**` line'
lacks "the group template takes no single diff placeholder" "$GRP" '[DIFF_FILE]'
check "the group prompt holds no placeholder task-step does not fill" \
  "$(awk '/^  prompt: \|/ { on = 1; next } on && /^```/ { exit } on' "$GRP" 2>/dev/null | grep -oE '\[[A-Z][A-Z_]*\]' | sort -u | grep -cvxE '\[(GROUP_LIST|PACKAGE_FILE|REPORT_FILE|PLUGIN_ROOT)\]')" "0"

# --- group reviews in the loop, the ledger and the waves ---
names "DONE holds a grouped task" "$DT" '`bash <plugin-root>/scripts/task-step hold PLAN_FILE N`'
names "exit 4 from hold means reviewed alone" "$DT" 'exit 4 means the task is reviewed alone'
names "the group review call" "$DT" '`bash <plugin-root>/scripts/task-step review --group PLAN_FILE N M …`'
names "the group trigger" "$DT" 'when 4 tasks are held, before you dispatch a task `review-route` reviews alone, and after the plan'"'"'s last task'
names "nothing is dispatched while a group is open" "$DT" 'no new task is dispatched until the group is clean'
names "group fixes run one task at a time" "$DT" 'fixes inside a group run one task at a time'
names "a concerned or blocked member leaves the group" "$DT" 'leaves the group and is reviewed alone'
names "a member re-reviews on the moving group head" "$DT" "each member's re-review moves that head on"
names "a group runs two fix rounds" "$DT" 'A group runs at most two fix rounds'
names "each member gets its own complete line" "$DT" 'each member gets its own `complete` line once the group is clean'
names "the loop's recovery reads a held task" "$DT" '| `awaiting group review (commits …)` |'
names "the ledger grammar holds the awaiting line" "$SDD_LEDGER" 'Task <N>: awaiting group review (commits <a7>..<b7>)'
names "the ledger grammar holds the group review line" "$SDD_LEDGER" 'Group <list>: review round R/2 (Task <N>: <k> open — <one-liners> | clean; …; commits <a7>..<b7> (Task <N>)[, <a7>..<b7> (Task <M>)])'
names "a group list is a comma list or a range" "$SDD_LEDGER" 'joined by commas (`Group 4,6,7`), or a contiguous range (`Group <a>-<b>`)'
names "a comma list covers the tasks it names" "$SDD_LEDGER" 'a comma list covers the tasks it names'
names "the recovery table reads a held task" "$SDD_LEDGER" '| `awaiting group review` | Reviewed by the next group dispatch'
names "the recovery table resumes a group review's round 2 per open member" "$SDD_LEDGER" 'On a group review'"'"'s line (its clause starts `Task <N>:`), run round 2 for each member whose clause is open, one member at a time; on a batch'"'"'s line, run it once for the batch |'
names "the recovery table sends a group review's open findings to the breaker" "$SDD_LEDGER" 'Go to the breaker: a group review'"'"'s line (its clause starts `Task <N>:`) sends each member'"'"'s open findings, a batch'"'"'s line the batch'"'"'s |'
check "the recovery table has one row per Group round" "$(grep -c '^| `review round [12]/2` on a' "$SDD_LEDGER")" "2"
names "after compaction a held task waits for its group" "$SDD" '`awaiting group review` is reviewed by the next group dispatch'
names "the process graph names the group template" "$SDD_GRAPH" './references/group-reviewer-prompt.md'
lacks "the overview no longer reviews every task alone" "$SDD" 'a judge-scored task review after each task;'
names "waves hold a grouped task at its ref, in its worktree" "$PW" '`task-step hold PLAN_FILE N --head <TASK_REF> --cwd <worktree>`'
names "a wave task's hold carries its worktree" "$DT" '`--head <task ref> --cwd <worktree>`'
check "a Codex plan holds no task, in DONE and in the group section" "$(grep -cF 'On a `Host: codex` plan no task is held: every task is reviewed alone (§3).' "$DT")" "2"
names "a concerned task with only observations is still held" "$DT" 'in subagent mode hold the task first, as DONE says'
names "recovery never reruns a group review that ran" "$DT" 'the group review ran: never run `review --group` again'
names "a missing baseline is never a subset" "$PW" 'A missing baseline file, an empty `<current>`, or a grep exit'
names "the subset test needs grep to exit 1" "$PW" '`grep -vxFf <baseline> <current>` exits 1'
names "waves review grouped tasks before any merges" "$PW" 'once every grouped task in the wave is held, before any of them merges'
names "a wave member's fix round stays in its worktree" "$PW" "a member's fix round goes to that task's implementer in its worktree"
names "a grouped wave task merges once its group is clean" "$PW" 'or, for a grouped task, its group is clean'

# --- the fix loop holds two rounds (faster-plans §3) ---
ESC="$P/skills/subagent-driven-development/references/escalation.md"
RRP="$P/skills/subagent-driven-development/references/re-review-prompt.md"
RUL="$P/skills/subagent-driven-development/references/ruling-prompt.md"
EL="$P/reference/executor-lane.md"
LAD="$P/reference/ladder.md"
# only_older <label> <file> — every line naming an R/5 round is about an older run's ledger
only_older() { check "$1" "$(grep -E 'round (<R>|[0-9R])/5([^0-9]|$)' "$2" | grep -vcE 'older|Codex')" "0"; }

names "the loop holds two rounds" "$DT" 'Two rounds at most per task:'
names "round 1 resumes or re-dispatches by cache state" "$DT" '**Round 1 — resume or re-dispatch by cache state.**'
names "round 2 is a fresh dispatch on the successor rung" "$DT" '**Round 2 — a fresh dispatch on the successor rung.**'
names "a SPLIT successor keeps the rung for round 2" "$DT" 'When the successor is `SPLIT`, round 2 is a fresh dispatch of the same rung'
names "a reserve-tier task takes its reserve successor" "$DT" 'A reserve-tier task takes its reserve successor'
names "the breaker trips after round 2" "$DT" "When round 2's re-review still leaves findings open"
names "the fix-round line counts to 2" "$DT" 'Task <N>: fix round <R>/2 ('
names "recovery: round 1 resumes at round 2" "$DT" '| `fix round 1/2`, or `fix round 1/5` from an older run | Resume the loop at round 2'
names "recovery: round 2 goes to the breaker" "$DT" '| `fix round 2/2`, or `fix round R/5` with R >= 2 from an older run | Go to the breaker (§4) |'
names "a Codex host keeps five rounds" "$DT" 'A Codex host keeps its five-round cap (`review_cap: 5`)'
names "a Codex host's five-round schedule" "$DT" 'On a `Host: codex` plan the loop keeps five rounds:'
names "a Codex host's recovery row" "$DT" '| `fix round R/5` on a `Host: codex` plan | Codex: R < 5 resumes the loop at round R+1 by the five-round schedule (§4); `fix round 5/5` goes to the breaker (§4) |'
for gone in '**Progress.**' 'progress <p> -> <q>' 'Rounds 4-5' 'Five rounds maximum' 'rounds 1-3 may resume it' \
            'The five-round cap is the same.' 'skip never triggers escalation' 'returns the progress reading'; do
  lacks "the delegated loop drops: $gone" "$DT" "$gone"
done
only_older "the delegated loop names R/5 only for older runs" "$DT"

names "escalation: round 2 climbs the ladder" "$ESC" '- **Fix round 2.** Dispatch a fresh implementer on the successor rung'
names "escalation: the recorded round is 2/2" "$ESC" 'Task <N>: fix round 2/2 (1 addressed, 1 open - <one-liner>; commits <a7>..<b7>; escalated <old-agent> -> <new-agent>)'
names "escalation: a split comes from the breaker" "$ESC" "a split is reached only through the breaker's AMEND"
names "escalation: the split ruling counts two rounds" "$ESC" 'impl-opus-high exhausted after 2 rounds'
for gone in 'Fix rounds 4 and 5' 'progress has stalled' 'after 5 rounds' 'fix round 4/5'; do
  lacks "escalation drops: $gone" "$ESC" "$gone"
done

for gone in '### Progress' '**Progress:**' 'a progress reading'; do
  lacks "the re-review prompt drops: $gone" "$RRP" "$gone"
done
names "the breaker item follows the second round" "$RUL" 'breaker: findings still open after the second fix round.'
lacks "the breaker item no longer waits five rounds" "$RUL" 'fifth fix round'

names "executor: round 1 resumes the session" "$EL" "Fix round 1 resumes that executor's own session"
names "executor: round 2 hands back" "$EL" '**Round 2 is `HANDBACK`.**'
names "executor: the failed-resume example is round 1 of 2" "$EL" 'Task <N>: fix round 1/2 (0 addressed, 2 open - codex quota exhausted'
for gone in 'Round 4 is' 'Fix rounds 1 to 3' 'five-round cap' 'stalled at round 3' 'rounds 4 and 5' 'two in a row' '§Rounds 1-3'; do
  lacks "executor-lane drops: $gone" "$EL" "$gone"
done
names "ladder: the lane resumes once, then hands back" "$LAD" 'resumes the same session on round 1 and hands back on round 2'
lacks "ladder: no fourth round on the lane" "$LAD" 'heading for at round 4'

names "subagent mode: the fix-round grammar" "$SDD_LEDGER" 'Task <N>: fix round R/2 (X addressed, Y open — <one-liners>; commits a..b[; re-review skipped (<n> lines)]; resumed | fresh (<why>) | escalated <old> -> <new> | HANDBACK to <agent>)'
names "subagent mode: the group round grammar" "$SDD_LEDGER" ': review round R/2 ('
names "subagent mode: a group's round 1 resumes at round 2" "$SDD_LEDGER" "| \`review round 1/2\` on a \`Group\` line, or \`review round 1/5\` from an older run | Resume the group's loop at round 2"
names "subagent mode: a group's round 2 goes to the breaker" "$SDD_LEDGER" '| `review round 2/2` on a `Group` line, or `review round R/5` with R >= 2 from an older run | Go to the breaker'
names "subagent mode: the wave round grammar" "$SDD_LEDGER" 'Wave <k>: fix round R/2 (<same fields as a fix round>)'
names "subagent mode: older ledgers map R/5" "$SDD_LEDGER" 'A `Task`, `Group` or `Wave` round line written before the two-round cap reads `R/5`: R = 1 resumes at round 2, and R >= 2 goes to the breaker.'
names "subagent mode: a Codex R/5 line is live" "$SDD_LEDGER" 'On a `Host: codex` plan a `Task` or `Wave` round line reading `R/5` is live, not older: apply the Codex row of [delegated-task.md](../../../reference/delegated-task.md) §Recovery.'
names "subagent mode: compaction resumes round 1 at round 2" "$SDD" '`fix round 1/2` resumes at round 2 with a fresh dispatch'
names "subagent mode: the breaker row" "$SDD_RULING_SEAT" '| `breaker` | Every finding still open after round 2/2 |'
names "subagent mode: the flowchart caps at 2" "$SDD_GRAPH" '"R = 2?"'
names "subagent mode: the example round has no progress field" "$SDD_EXAMPLE" '[Ledger: Task 2: fix round 1/2 (2 addressed, 0 open; commits d4e5f6a..b7c8d9e; resumed)]'
for gone in 'progress p -> q' 'stalled progress' 'round 1 of 5' 'Fix round R of 5' 'Progress: 18' '"R = 5?"'; do
  check "subagent mode drops: $gone" "$(sdd_text | grep -cF -- "$gone")" "0"
done
only_older "subagent mode names R/5 only for older runs" "$SDD"
only_older "the ledger names R/5 only for older runs" "$SDD_LEDGER"
names "inline mode: delegated fix rounds stop at 2" "$INLINE" 'fix rounds up to 2 and'
names "inline mode: the breaker row" "$INLINE" "| \`breaker\` | A delegated task's findings still open after round 2/2 |"
only_older "inline mode names R/5 only for older runs" "$INLINE"

# --- the wave check cadence (faster-plans §4) ---
WP="$P/skills/writing-plans/SKILL.md"
names "waves ask check-due which check closes a wave" "$PW" '`bash <plugin-root>/scripts/wave check-due PLAN_FILE <k>`'
names "every wave closes" "$PW" 'Every wave closes with an `integrated` or a `merged` line, one-task and serialized waves included.'
names "the merged line" "$PW" 'Wave <k>: merged (head <sha7>; check at wave <m>)'
names "the integrated line may be baseline-only" "$PW" 'Wave <k>: integrated (head <sha7>; <command> → pass[; baseline failures only])'
names "a wave opens once every earlier wave is closed" "$PW" 'every earlier wave closed by its `integrated` or `merged` line'
names "an ancestor with no task commits between proves the base" "$PW" 'or an ancestor of `HEAD` with no task commits between'
names "a task commit outside any wave forces the fallback proof" "$PW" 'Only a task commit outside any wave forces the fallback proof'
names "the base proof records its failures" "$PW" '`<workspace>/base-proof-failures.txt`'
names "a new failure hands over every diff since the last pass" "$PW" 'every task diff since the last passing check'
names "no in-flight run is exempt" "$PW" 'None is exempt.'
names "an earlier cadence ruling is superseded" "$PW" 'is superseded by this cadence and the red-baseline rule'
names "an overlap round counts toward two rounds" "$PW" 'It counts toward the two rounds.'
names "recovery: a wave in flight has no closing line" "$PW" 'A `Wave <k>: started` line with no later `Wave <k>: integrated` or `Wave <k>: merged` line'
lacks "a one-task wave is no longer line-free" "$PW" 'with no Wave lines, no worktree and no merge'
lacks "waves no longer count five rounds" "$PW" 'It counts toward the five'
only_older "waves name R/5 only for older runs" "$PW"
names "writing-plans: the optional Wave check header line" "$WP" '**Wave check:** [waves only, optional:'
names "writing-plans: the waves rule names the Wave check" "$WP" '`**Wave check:**`, optional, names a faster command'
names "subagent mode: the merged grammar" "$SDD_LEDGER" 'Wave <k>: merged (head <sha7>; check at wave <m>)'
names "subagent mode: the integrated grammar" "$SDD_LEDGER" 'Wave <k>: integrated (head <sha7>; <command> → pass[; baseline failures only])'
names "subagent mode: compaction reads a merged line as closed" "$SDD" 'A `Wave <k>: started` line with no later `integrated` or `merged` line'
names "subagent mode: recovery reads merged as closed" "$SDD_LEDGER" '`Wave <k>: merged` closes the wave as `integrated` does'
names "subagent mode: a one-task wave proves its base and closes by §5" "$SDD" 'A wave of one task runs in the checkout, proves its base first and closes by §5'
lacks "subagent mode: the old integrated grammar is gone" "$SDD_LEDGER" 'Wave <k>: integrated (head <sha7>; <command> → pass)'


# The controller reads a review through task-step verdict and an AMEND through
# plan-amend --report; it never reads or copies a report's text.
check "the loop steps run task-step verdict" "$([ "$(loop_steps | grep -cF -- 'task-step verdict PLAN_FILE N')" -ge 1 ] && echo yes || echo no)" "yes"
names "the re-review is read through verdict --rereview" "$DT" '`bash <plugin-root>/scripts/task-step verdict PLAN_FILE N --rereview <R>`'
names "verdict writes the fix file's bullets" "$DT" '`task-step verdict` writes its bullets from the report'
names "the seat's report is never read" "$DT" 'Never Read the report file yourself'
names "a failed verdict restores the tracked files" "$DT" '`git -C <dir> checkout -- <files>`'
names "a failed verdict is a Ruling line" "$DT" 'restored the committed state and re-dispatched once'
names "a second failure takes the fallback judge" "$DT" 'A second failure dispatches the route'"'"'s fallback judge'
names "the risk-3 check reads the report's last section" "$DT" 'A report whose `## Codex findings` section is not its last'
lacks "the risk-3 check no longer reads the reply" "$DT" 'A reply whose `### Codex findings`'
for f in "$SDD_RULING_SEAT" "$INLINE"; do
  s=$(basename "$(dirname "$f")")/$(basename "$f")
  names "$s: an AMEND applies from the report" "$f" 'scripts/plan-amend PLAN_FILE --report <workspace>/rulings-<point>-<task>-report.md --id A<k>'
  lacks "$s: an AMEND is no longer copied by hand" "$f" 'copy the entry, from its `## A?` line'
  names "$s: the ruling report is read by its Verdict section" "$f" 'read only its `## Verdict` section'
done
names "the example workflow reads the verdict with task-step" "$SDD_EXAMPLE" '[task-step verdict PLAN_FILE 1:'
names "a header amendment's confirmation reads the first report" "$SDD_RULING_SEAT" 'then the path of the first seat'"'"'s report'
names "by hand: the review prompt's two report placeholders" "$DT" '`[IMPLEMENTER_REPORT_FILE]` set to the implementer'"'"'s report and `[REPORT_FILE]` to `<workspace>/task-<N>-review-report.md`'
names "the lane's review prompt no longer names a Verification Scores section" "$P/reference/executor-lane.md" 'rather than a markdown report file'
names "a group review is read through verdict --group" "$DT" '`bash <plugin-root>/scripts/task-step verdict PLAN_FILE N M … --group`'
names "Codex seats apply the cannot-verify route" "$DT" 'the bands, the cannot-verify route and the fix loop'
names "a group applies the cannot-verify route" "$DT" 'cannot-verify route and plan-conflict route'
lacks "no ⚠️ route is left in delegated-task.md" "$DT" '⚠️ route'
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
