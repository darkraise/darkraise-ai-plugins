#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
selector="$HERE/../scripts/select-native-tier.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then printf 'ok - %s\n' "$1"; pass=$((pass+1)); else printf 'FAIL - %s: got [%s], want [%s]\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
cat > "$fixture/request.json" <<'JSON'
{"policy":"codex-v2","operation":"assign","role":"implementer","assignment_source":"rubric",
 "axes":{"files":0,"spec":0,"coupling":0,"risk":0},
 "available_pairs":[{"model":"gpt-5.6-luna","effort":"low"},{"model":"gpt-5.6-luna","effort":"medium"},
 {"model":"gpt-5.6-terra","effort":"low"},{"model":"gpt-5.6-terra","effort":"medium"},{"model":"gpt-5.6-terra","effort":"high"},
 {"model":"gpt-5.6-sol","effort":"low"},{"model":"gpt-5.6-sol","effort":"medium"},{"model":"gpt-5.6-sol","effort":"high"},
 {"model":"gpt-6-astra","effort":"high"},{"model":"gpt-6-astra","effort":"xhigh"},
 {"model":"gpt-6-astra","effort":"max"},{"model":"gpt-6-astra","effort":"ultra"}],
 "attempted_ranks":[],"attempted_reserves":[],"split_consumed":false,"review_rounds":0}
JSON
select_with() { jq "$1" "$fixture/request.json" > "$fixture/input.json"; bash "$selector" --request "$fixture/input.json"; }
expect_error() {
  local output status
  output="$(select_with "$2" 2>&1)"; status=$?
  check "$1 exits with preflight failure" "$status" 2
  check "$1 explains the failure" "$(case "$output" in *"$3"*) echo yes ;; *) echo no ;; esac)" yes
}
decision() {
  local output
  output="$(select_with "$2")"
  check "$1" "$(jq -c "$3" <<< "$output")" "$4"
}
while read -r score files spec coupling risk model effort; do
  decision "score $score selects the calculated rank and pair" ".axes={files:$files,spec:$spec,coupling:$coupling,risk:$risk} | .score=$score" '[.action,.score,.rank,.model,.effort]' "[\"dispatch\",$score,$score,\"$model\",\"$effort\"]"
done <<'CASES'
0 0 0 0 0 gpt-5.6-luna low
1 1 0 0 0 gpt-5.6-luna medium
2 1 1 0 0 gpt-5.6-terra low
3 1 1 1 0 gpt-5.6-terra medium
4 1 1 0 1 gpt-5.6-terra high
5 1 1 1 1 gpt-5.6-sol low
6 1 1 0 2 gpt-5.6-sol medium
7 1 1 1 2 gpt-5.6-sol high
8 1 1 0 3 gpt-6-astra high
9 1 1 1 3 gpt-6-astra xhigh
CASES

decision 'calculate weighted score without a supplied total' '.axes={files:1,spec:1,coupling:1,risk:2}' '.score' 7
expect_error 'unweighted total' '.axes={files:1,spec:1,coupling:1,risk:2} | .score=5' 'score does not match'
expect_error 'missing raw axes' 'del(.axes)' 'axes'
expect_error 'missing risk axis' 'del(.axes.risk)' 'axes'
expect_error 'fractional axis' '.axes.files=0.5' 'axes'
expect_error 'negative axis' '.axes.risk=-1' 'axes'
expect_error 'axis above three' '.axes.risk=4' 'axes'
expect_error 'non-numeric axis' '.axes.spec="1"' 'axes'
expect_error 'oversized reducible subtotal' '.axes={files:2,spec:1,coupling:1,risk:0}' 'Rule S'
expect_error 'undecided approach' '.axes.spec=3' 'Rule S'
expect_error 'fractional supplied total' '.score=0.5' 'score'
expect_error 'out-of-range supplied total' '.score=10' 'score'
expect_error 'null supplied total' '.score=null' 'score'
expect_error 'old policy' '.policy="codex-v1"' 'conversion required'
expect_error 'unknown policy' '.policy="codex-v99"' 'conversion required'
expect_error 'missing capability metadata' 'del(.available_pairs)' 'metadata'

decision 'missing Terra effort promotes within Terra' '.axes={files:1,spec:1,coupling:0,risk:0} | .available_pairs=[{model:"gpt-5.6-terra",effort:"medium"}]' '[.score,.rank,.model,.effort]' '[2,3,"gpt-5.6-terra","medium"]'
decision 'missing Terra promotes to Sol low' '.axes={files:1,spec:1,coupling:1,risk:0} | .available_pairs |= map(select(.model != "gpt-5.6-terra"))' '[.score,.rank,.model,.effort]' '[3,5,"gpt-5.6-sol","low"]'
decision 'initial assignment neither demotes nor enters reserve' '.axes={files:1,spec:1,coupling:1,risk:3} | .available_pairs=[{model:"gpt-5.6-sol",effort:"high"},{model:"gpt-6-astra",effort:"max"}]' '.action' '"blocked"'
decision 'empty capabilities block initial assignment' '.available_pairs=[]' '.action' '"blocked"'
decision 'scout retains Sol medium floor' '.role="scout"' '[.rank,.model,.effort]' '[6,"gpt-5.6-sol","medium"]'
decision 'judge retains Astra high floor' '.role="judge"' '[.rank,.model,.effort]' '[8,"gpt-6-astra","high"]'
decision 'judge never drops below its floor' '.role="judge" | .available_pairs=[{model:"gpt-5.6-sol",effort:"high"}]' '.action' '"blocked"'
decision 'judge exhaustion never enters implementer reserve' '.role="judge" | .operation="escalate" | .attempted_ranks=[8,9] | .split_consumed=true' '.action' '"blocked"'

decision 'human reserve pin needs neither axes nor split' 'del(.axes) | .assignment_source="human" | .pinned_pair={model:"gpt-6-astra",effort:"ultra"}' '[.action,.model,.effort]' '["dispatch","gpt-6-astra","ultra"]'
decision 'human override may retain an undecided approach' '.axes.spec=3 | .assignment_source="human" | .pinned_pair={model:"gpt-6-astra",effort:"high"}' '.action' '"dispatch"'
decision 'unavailable human pin requires approval' '.assignment_source="human" | .pinned_pair={model:"absent",effort:"high"}' '.action' '"approval"'
decision 'human escalation requires approval' '.assignment_source="human" | .pinned_pair={model:"gpt-6-astra",effort:"high"} | .operation="escalate"' '.action' '"approval"'

expect_error 'reassignment with execution history' '.attempted_ranks=[0]' 'initial assignment'
expect_error 'reassignment with reserve history' '.attempted_ranks=[9] | .attempted_reserves=["max"] | .split_consumed=true' 'initial assignment'
expect_error 'human reassignment with history' '.assignment_source="human" | .pinned_pair={model:"gpt-6-astra",effort:"high"} | .attempted_ranks=[8]' 'initial assignment'
expect_error 'escalation without an attempt' '.operation="escalate"' 'execution history'
expect_error 'rank above nine' '.operation="escalate" | .attempted_ranks=[10]' 'history'
expect_error 'repeated execution rank' '.operation="escalate" | .attempted_ranks=[1,1]' 'history'
expect_error 'backward execution ranks' '.operation="escalate" | .attempted_ranks=[3,1]' 'history'
expect_error 'backward reserve efforts' '.operation="escalate" | .attempted_ranks=[9] | .split_consumed=true | .attempted_reserves=["ultra","max"]' 'history'
expect_error 'reserve without consumed split' '.operation="escalate" | .attempted_ranks=[9] | .attempted_reserves=["max"]' 'split'

decision 'execution advances to the next higher rank' '.operation="escalate" | .attempted_ranks=[2,3]' '.rank' 4
decision 'execution exhaustion splits once' '.operation="escalate" | .attempted_ranks=[9]' '.action' '"split"'
decision 'new split child starts with empty local history' '.split_consumed=true' '[.action,.rank]' '["dispatch",0]'
decision 'split child exhaustion enters max reserve' '.operation="escalate" | .attempted_ranks=[9] | .split_consumed=true' '[.action,.effort]' '["dispatch","max"]'
decision 'unavailable max is skipped for ultra' '.operation="escalate" | .attempted_ranks=[9] | .split_consumed=true | .available_pairs |= map(select(.effort != "max"))' '.effort' '"ultra"'
decision 'reserve advances to ultra' '.operation="escalate" | .attempted_ranks=[9] | .split_consumed=true | .attempted_reserves=["max"]' '.effort' '"ultra"'
decision 'new xhigh cannot precede remaining ultra reserve' '.operation="escalate" | .attempted_ranks=[8] | .split_consumed=true | .attempted_reserves=["max"]' '.effort' '"ultra"'
decision 'new xhigh cannot revive exhausted reserve' '.operation="escalate" | .attempted_ranks=[8] | .split_consumed=true | .attempted_reserves=["max","ultra"]' '.action' '"blocked"'
decision 'exhausted ultra cannot return to newly available max' '.operation="escalate" | .attempted_ranks=[8] | .split_consumed=true | .attempted_reserves=["ultra"]' '.action' '"blocked"'
decision 'exhausted capabilities cannot split twice' '.operation="escalate" | .attempted_ranks=[9] | .split_consumed=true | .available_pairs=[]' '.action' '"blocked"'
decision 'five-round cap stops another dispatch' '.review_rounds=5' '.action' '"blocked"'
decision 'human pin cannot bypass review cap' '.review_rounds=5 | .assignment_source="human" | .pinned_pair={model:"gpt-6-astra",effort:"ultra"}' '.action' '"blocked"'
cat "$fixture/request.json" "$fixture/request.json" > "$fixture/input.json"
bash "$selector" --request "$fixture/input.json" > "$fixture/output.json" 2>/dev/null
check 'multiple JSON requests are rejected' "$?" 2
check 'invalid request emits no decision' "$(wc -c < "$fixture/output.json" | tr -d ' ')" 0
awk '/^```json$/ { inside=1; next } inside && /^```$/ { exit } inside { print }' "$HERE/../reference/native-codex.md" > "$fixture/documented.json"
out="$(bash "$selector" --request "$fixture/documented.json" 2>/dev/null)"
check 'documented request executes with the stated assignment' "$(jq -c '[.action,.score,.rank,.model,.effort]' <<< "$out")" '["dispatch",7,7,"gpt-5.6-sol","high"]'
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
