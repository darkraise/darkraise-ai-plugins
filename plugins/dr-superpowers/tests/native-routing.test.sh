#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
selector="$HERE/../scripts/select-native-tier.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then printf 'ok - %s\n' "$1"; pass=$((pass+1)); else printf 'FAIL - %s: got [%s], want [%s]\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
check 'native selector exists' "$([ -f "$selector" ] && echo yes || echo no)" yes
[ "$fail" -eq 0 ] || exit 1
cat > "$fixture/request.json" <<'JSON'
{"policy":"codex-v1","operation":"assign","role":"implementer","score":0,"assignment_source":"rubric",
 "available_pairs":[{"model":"gpt-5.6-luna","effort":"low"},{"model":"gpt-5.6-luna","effort":"medium"},
 {"model":"gpt-5.6-sol","effort":"low"},{"model":"gpt-5.6-sol","effort":"medium"},{"model":"gpt-5.6-sol","effort":"high"},
 {"model":"gpt-6-astra","effort":"high"},{"model":"gpt-6-astra","effort":"xhigh"},
 {"model":"gpt-6-astra","effort":"max"},{"model":"gpt-6-astra","effort":"ultra"}],
 "attempted_ranks":[],"attempted_reserves":[],"split_consumed":false,"review_rounds":0}
JSON
select_with() { jq "$1" "$fixture/request.json" > "$fixture/input.json"; bash "$selector" --request "$fixture/input.json"; }
expected=('gpt-5.6-luna/low' 'gpt-5.6-luna/medium' 'gpt-5.6-sol/low' 'gpt-5.6-sol/medium' 'gpt-5.6-sol/high' 'gpt-6-astra/high' 'gpt-6-astra/xhigh')
for score in {0..6}; do
  out="$(select_with ".score = $score")"
  check "score $score selects explicit pair" "$(jq -r '.model + "/" + .effort' <<< "$out")" "${expected[$score]}"
done
out="$(select_with '.score=2 | .available_pairs=[{model:"gpt-5.6-sol",effort:"medium"}]')"
check 'missing effort promotes without demotion' "$(jq .rank <<< "$out")" 3
out="$(select_with '.score=6 | .available_pairs=[{model:"gpt-5.6-sol",effort:"high"}]')"
check 'initial unavailable pair does not enter reserve' "$(jq -r .action <<< "$out")" blocked
out="$(select_with '.assignment_source="human" | .pinned_pair={model:"absent",effort:"high"}')"
check 'unavailable human pin requires approval' "$(jq -r .action <<< "$out")" approval
out="$(select_with '.operation="escalate" | .attempted_ranks=[0,1,2,3,4,5,6]')"
check 'execution exhaustion splits once' "$(jq -r .action <<< "$out")" split
out="$(select_with '.operation="escalate" | .attempted_ranks=[0,1,2,3,4,5,6] | .split_consumed=true')"
check 'split child exhaustion enters max reserve' "$(jq -r .effort <<< "$out")" max
out="$(select_with '.operation="escalate" | .attempted_ranks=[6] | .split_consumed=true | .attempted_reserves=["max"]')"
check 'reserve advances to ultra' "$(jq -r .effort <<< "$out")" ultra
out="$(select_with '.operation="escalate" | .attempted_ranks=[6] | .split_consumed=true | .attempted_reserves=["max","ultra"]')"
check 'reserve exhaustion blocks' "$(jq -r .action <<< "$out")" blocked
out="$(select_with '.review_rounds=5')"
check 'five-round cap stops another dispatch' "$(jq -r .action <<< "$out")" blocked
out="$(select_with '.role="scout"')"
check 'scout uses rank-three floor' "$(jq .rank <<< "$out")" 3
out="$(select_with '.role="judge"')"
check 'judge uses rank-five floor' "$(jq .rank <<< "$out")" 5
select_with 'del(.available_pairs)' >/dev/null 2>&1
check 'missing capability metadata fails preflight' "$?" 2
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
