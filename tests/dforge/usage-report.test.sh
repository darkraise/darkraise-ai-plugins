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
check "per_task_fields: outside the tasks" "$(q "$J" '.plans[0].outside | [.turns, .cost]')" "[2,0.000372]"
check "per_task_fields: cost per task" "$(q "$J" '.plans[0] | [.completed, .costPerTask]')" "[2,0.003002]"
check "per_task_fields: by model" "$(q "$J" '.plans[0].byModel | keys')" '["claude-opus-5-5","claude-sonnet-5-5"]'
check "per_task_fields: md has a row per task" \
  "$(node "$REPORT" --markers "$FX/basic/markers.tsv" --transcripts "$FX/basic/proj" | grep -c '^| [12] |')" "2"

# --- deferred_excluded, unpriced_model, open_after_close_ignored ---
J=$(rep misc)
check "deferred_excluded: not completed" "$(q "$J" '.plans[0] | [.completed, (.tasks | map(.tasks[]))]')" "[1,[7]]"
check "deferred_excluded: listed as excluded" "$(q "$J" '.plans[0].excluded')" '["Task 6: deferred by the auto run"]'
check "deferred_excluded: not in the cost per task" "$(q "$J" '.plans[0] | .costPerTask == .tasks[0].cost')" "true"
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

# --- usage errors ---
node "$REPORT" --format csv >/dev/null 2>&1
check "usage: a bad format exits 2" "$?" "2"
node "$REPORT" --no-such >/dev/null 2>&1
check "usage: an unknown argument exits 2" "$?" "2"
check "usage: no input is an empty report" "$(node "$REPORT" --format json | jq -c .)" '{"plans":[]}'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
