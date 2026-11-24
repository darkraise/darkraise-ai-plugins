#!/usr/bin/env bash
# usage-report.mjs slices transcripts at the task markers' byte offsets and
# prices each slice. Fixtures: tests/dforge/fixtures/usage/<case>/ (markers.tsv
# and a Claude project directory, proj/). Costs below are worked by hand from
# reference/api-prices.json: per Mtok, Opus 5.5 input 4, cache read 0.2,
# write 5m 5, write 1h 8, output 20; Sonnet 5.5 input 2, cache read 0.1,
# output 10.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT="$HERE/../../plugins/dforge/scripts/lib/usage-report.mjs"
FX="$HERE/fixtures/usage"
export MSYS_NO_PATHCONV=1
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_NOSYSTEM=1

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
rep() { # rep CASE — the JSON report of one fixture
  node "$REPORT" --markers "$FX/$1/markers.tsv" --transcripts "$FX/$1/proj" --format json 2>/dev/null
}
q() { jq -c "$2" <<<"$1" 2>/dev/null | tr -d '\r'; }

# --- per_task_fields ---
J=$(rep basic)
T1='.plans[0].tasks[] | select(.tasks == [1])'
check "per_task_fields: task 1 usage" \
  "$(q "$J" "$T1 | [.turns, .input, .cacheRead, .cacheWrite5m, .cacheWrite1h, .output]")" "[2,15,5000,100,300,60]"
check "per_task_fields: task 1 models" "$(q "$J" "$T1 | .models")" '["claude-opus-5-5"]'
check "per_task_fields: task 1 context" "$(q "$J" "$T1 | [.contextOpen, .contextClose]")" "[1000,3305]"
check "per_task_fields: task 1 subagent" "$(q "$J" "$T1 | .subagents")" \
  '{"dforge:judge-opus":{"turns":1,"input":100,"cacheRead":0,"cacheWrite5m":0,"cacheWrite1h":0,"output":50,"cost":0.0007}}'
# 15*4 + 5000*0.2 + 100*5 + 300*8 + 60*20 = 5160, plus the subagent's 700.
check "per_task_fields: task 1 cost" "$(q "$J" "$T1 | .cost")" "0.00586"
check "per_task_fields: task 1 label, group and range" "$(q "$J" "$T1 | [.label, .group, .range]")" '["marked",false,"aaa..bbb"]'
check "per_task_fields: task 2 usage and cost" \
  "$(q "$J" '.plans[0].tasks[] | select(.tasks == [2]) | [.turns, .input, .cacheRead, .output, .cost]')" "[1,7,500,8,0.000144]"
# m0 comes before the first open (excluded); m4 after task 2 is outside: 2*4 + 3*20.
check "per_task_fields: outside the tasks" "$(q "$J" '.plans[0].outside | [.turns, .cost]')" "[1,0.000068]"
check "per_task_fields: cost per task, with and without outside" "$(q "$J" '.plans[0] | [.completed, .costPerTask, .costPerTaskSegments]')" "[2,0.003036,0.003002]"
check "per_task_fields: by model" "$(q "$J" '.plans[0].byModel | keys')" '["claude-opus-5-5","claude-sonnet-5-5"]'
check "per_task_fields: md has a row per task" \
  "$(node "$REPORT" --markers "$FX/basic/markers.tsv" --transcripts "$FX/basic/proj" | grep -c '^| [12] |')" "2"

# --- deferred_excluded, unpriced_model, open_after_close_ignored ---
J=$(rep misc)
check "deferred_excluded: not completed" "$(q "$J" '.plans[0] | [.completed, (.tasks | map(.tasks[]))]')" "[1,[7]]"
check "deferred_excluded: listed as excluded" "$(q "$J" '.plans[0].excluded')" '["Task 6: deferred by the auto run","before first open"]'
check "deferred_excluded: not in the cost per task" "$(q "$J" '.plans[0] | .costPerTaskSegments == .tasks[0].cost')" "true"
# k4 and k5 after task 7 are outside (577*4); task 6's slice is neither.
check "deferred_excluded: its slice is not outside" "$(q "$J" '.plans[0].outside | [.turns, .cost]')" "[2,0.002308]"
check "unpriced_model: listed and priced at 0" "$(q "$J" '.plans[0].tasks[0] | [.unpriced, .cost, .turns]')" '[["claude-unknown-9"],0.00004,2]'
check "open_after_close_ignored: the task keeps its slice" "$(q "$J" '.plans[0].tasks[0] | [.input, .contextOpen]')" "[1010,3]"
check "open_after_close_ignored: an open with no close is unclosed" "$(q "$J" '.plans[0].unclosed')" "1"

# --- task_across_sessions ---
J=$(rep sessions)
check "task_across_sessions: the tail of A plus B's segment" \
  "$(q "$J" '.plans[0].tasks[0] | [.tasks, .turns, .input]')" "[[3],3,7]"

# --- overlapping_group ---
J=$(rep group)
check "overlapping_group: one row for both tasks" "$(q "$J" '.plans[0].tasks | length')" "1"
check "overlapping_group: tasks, group and the union once" \
  "$(q "$J" '.plans[0].tasks[0] | [.tasks, .group, .turns, .input]')" "[[4,5],true,3,7]"
check "overlapping_group: both tasks completed" "$(q "$J" '.plans[0].completed')" "2"

# --- lookups_and_files_share ---
J=$(node "$REPORT" --markers "$FX/lookups/markers.tsv" --transcripts "$FX/lookups/proj" --plan "$FX/lookups/p.md" --format json 2>/dev/null)
# Two whole reads of a.sh, rg on b.sh, sed -n on c.sh; git status is no lookup.
# Read results of 400 and 200 characters are 100 + 50 tokens at 4 per token.
check "lookups_and_files_share: lookups, repeats, share and read tokens" \
  "$(q "$J" '.plans[0].tasks[0] | [.lookups, .repeatReads, .filesLookupShare, .readTokens]')" "[4,1,0.75,150]"

# --- compaction_fields ---
J=$(rep compaction)
check "compaction_fields: task 2's compaction" "$(q "$J" '.plans[0].tasks[] | select(.tasks == [2]) | .compactions')" \
  '[{"durationMs":117000,"postTokens":32000,"nextContext":40000}]'
check "compaction_fields: the first task after it counts its lookups" \
  "$(q "$J" '.plans[0].tasks | map(.lookupsAfterCompaction)')" "[null,2]"

# --- growth_and_outside ---
J=$(rep growth)
check "growth_and_outside: growth sums the rises" "$(q "$J" '.plans[0].tasks[] | select(.tasks == [1]) | .growth')" "40000"
# Task 1: 420000 cache read * 0.2; task 2: 10 * 4; outside (between tasks): 1000 * 4.
check "growth_and_outside: the usage between tasks is outside" "$(q "$J" '.plans[0].outside | [.turns, .input]')" "[1,1000]"
check "growth_and_outside: both cost figures" "$(q "$J" '.plans[0] | [.costPerTask, .costPerTaskSegments]')" "[0.04402,0.04202]"
check "growth_and_outside: the usage before the first open is excluded" "$(q "$J" '.plans[0].excluded')" '["before first open"]'

# --- splits_and_all_plans ---
J=$(node "$REPORT" --markers "$FX/splits/repo/state/sdd/usage-markers.tsv" --transcripts "$FX/splits/proj" --format json 2>/dev/null)
check "splits_and_all_plans: both plans" "$(q "$J" '[.plans[].plan]')" '["docs/plans/p.md","docs/plans/q.md"]'
check "splits_and_all_plans: by model" "$(q "$J" '.plans[0].byModel | map_values([.input, .cost])')" \
  '{"claude-opus-5-5":[10,0.00004],"claude-sonnet-5-5":[20,0.00004]}'
check "splits_and_all_plans: by repository" "$(q "$J" '.plans[0].byRepo | to_entries | map([(.key | sub(".*/fixtures/"; "")), .value.input, .value.cost])')" \
  '[["usage/splits/repo",30,0.00008]]'

# --- wait_seconds ---
J=$(rep wait)
check "wait_seconds: from the background call to its notification" "$(q "$J" '.plans[0].tasks[0].waitSeconds')" "90"

# --- dispatches_from_transcript ---
J=$(rep dispatch)
check "dispatches_from_transcript: families and agent types" "$(q "$J" '.plans[0].tasks[0].dispatches')" \
  '{"codex-task":1,"review-panel":1,"api-judge":1,"dforge:judge-sonnet-high":2}'
check "dispatches_from_transcript: fix rounds from rereview calls" "$(q "$J" '.plans[0].tasks[0].fixRounds')" "2"

# --- ledger_gone: the close rows alone carry each task's range ---
J=$(rep misc)
check "ledger_gone: closed tasks with their ranges, the deferred one excluded" \
  "$(q "$J" '[[.plans[0].tasks[] | [.tasks[0], .range]], (.plans[0].excluded | map(select(test("deferred"))))]')" \
  '[[[7,"h..i"]],["Task 6: deferred by the auto run"]]'

# --- unmarked_ledger_line ---
J=$(node "$REPORT" --markers "$FX/unmarked/markers.tsv" --transcripts "$FX/unmarked/proj" --ledger "$FX/unmarked/progress.md" --format json 2>/dev/null)
check "unmarked_ledger_line: a row from the inferred bounds" \
  "$(q "$J" '.plans[0].tasks[] | select(.tasks == [6]) | [.label, .range, .input]')" '["unmarked","c..d",30]'
check "unmarked_ledger_line: counted" "$(q "$J" '.plans[0].unmarked')" "1"
B=$(cd "$HERE/../../plugins/dforge/scripts/lib" && node --input-type=module -e '
  import { inferBounds } from "./usage-report.mjs";
  const e = { type: "assistant", message: { content: [{ type: "tool_use", id: "t", name: "Bash",
    input: { command: "P=docs/p.md; bash task-step start \"$P\" 2 3" } }] } };
  console.log(JSON.stringify(inferBounds([{ offset: 0, entry: e }]).map((b) => [b.plan, b.task])));' 2>&1)
check "unmarked_ledger_line: a batch start with a variable" "$B" '[["docs/p.md",2],["docs/p.md",3]]'

# --- quality_pairing ---
QR="$TMP/qrepo"
git init -q "$QR"
qc() { # qc DATE SUBJECT FILE
  printf '%s\n' "$2" >> "$QR/$3"
  git -C "$QR" add -A
  GIT_AUTHOR_DATE=$1 GIT_COMMITTER_DATE=$1 git -C "$QR" -c user.name=t -c user.email=t@example.invalid commit -q -m "$2"
}
qc 2025-12-31T00:00:00Z "feat: base" a.sh
QA=$(git -C "$QR" rev-parse --short HEAD)
qc 2026-01-02T00:00:00Z "fix(x): inside the task range" a.sh
QB=$(git -C "$QR" rev-parse --short HEAD)
qc 2026-01-02T12:00:00Z "feat: not a fix" a.sh
qc 2026-01-03T00:00:00Z "fix(y): after the finish" a.sh
qc 2026-01-03T01:00:00Z "fix: another file" z.sh
qc 2026-01-20T00:00:00Z "fix: too late" a.sh
printf '2026-01-01T00:00:00Z\topen\tdforge\t5.1.1\t/plugin\tdocs/plans/p.md\t1\tq1\t\t0\t1\ttask-brief:1\t\t\n2026-01-01T00:10:00Z\tclose\tdforge\t5.1.1\t/plugin\tdocs/plans/p.md\t1\tq1\t\t\t2\ttask-close:1\t%s..%s\t\n' "$QA" "$QB" > "$TMP/q-markers.tsv"
J=$(node "$REPORT" --markers "$TMP/q-markers.tsv" --transcripts "$FX/quality/proj" --plan "$FX/quality/plans/p.md" \
  --review-record "$FX/quality/record.md" --register "$FX/quality/reg.md" --repo "$QR" --format json 2>/dev/null)
check "quality_pairing: the plan's quality" "$(q "$J" '.plans[0].quality')" \
  '{"findings":{"Critical":1,"Important":2},"fixRounds":0,"breakerItems":0,"deferredRows":2,"followUpTasks":3,"fixCommits":1}'

# --- usage errors ---
node "$REPORT" --format csv >/dev/null 2>&1
check "usage: a bad format exits 2" "$?" "2"
node "$REPORT" --no-such >/dev/null 2>&1
check "usage: an unknown argument exits 2" "$?" "2"
check "usage: no input is an empty report" "$(node "$REPORT" --format json | jq -c .)" '{"plans":[]}'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
