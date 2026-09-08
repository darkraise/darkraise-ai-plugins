#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die() { printf 'select-native-tier: %s\n' "$1" >&2; exit 2; }
[ "$#" -eq 2 ] && [ "$1" = --request ] && [ -f "$2" ] || die 'usage: select-native-tier.sh --request FILE'
command -v jq >/dev/null 2>&1 || die 'jq is required'
request="$2"
jq -e '
  .policy == "codex-v1" and (.operation == "assign" or .operation == "escalate") and
  (.role == "implementer" or .role == "scout" or .role == "judge") and
  (.assignment_source == "rubric" or .assignment_source == "human") and
  (.score | type == "number" and . >= 0 and . <= 6 and floor == .) and
  (.available_pairs | type == "array" and all(.[]; (.model | type == "string" and length > 0) and (.effort | type == "string" and length > 0))) and
  (.attempted_ranks | type == "array" and all(.[]; type == "number" and . >= 0 and . <= 6 and floor == .)) and
  (.attempted_reserves | type == "array" and all(.[]; . == "max" or . == "ultra")) and
  (.split_consumed | type == "boolean") and (.review_rounds | type == "number" and . >= 0 and floor == .) and
  (if .assignment_source == "human" then (.pinned_pair.model | type == "string" and length > 0) and (.pinned_pair.effort | type == "string" and length > 0) else true end)
' "$request" >/dev/null 2>&1 || die 'invalid request or missing advertised model/effort metadata'
jq --slurpfile policy "$HERE/../reference/codex-routing.json" '
  . as $r | $policy[0] as $p |
  def available($pair): any($r.available_pairs[]; .model == $pair.model and .effort == $pair.effort);
  def decision($action;$reason): {action:$action,reason:$reason};
  if $r.review_rounds >= $p.review_cap then decision("blocked";"five-round review cap reached")
  elif $r.assignment_source == "human" then
    if $r.operation == "assign" and available($r.pinned_pair) then
      $r.pinned_pair + decision("dispatch";"approved human assignment")
    else decision("approval";"human-pinned assignment requires approval before substitution") end
  else
    ([$r.score,$p.role_floors[$r.role],
      (if $r.operation == "escalate" then (($r.attempted_ranks | max // -1) + 1) else 0 end)] | max) as $floor |
    [$p.execution[] | select(.rank >= $floor) | select(available(.))] as $choices |
    if ($choices | length) > 0 then
      $choices[0] + decision("dispatch";(if $r.operation == "escalate" then "next available higher execution rank" elif $choices[0].rank > $r.score then "promoted from score \($r.score) to available rank \($choices[0].rank)" else "rubric assignment" end))
    elif $r.operation == "assign" or $r.role != "implementer" then decision("blocked";"no advertised execution pair satisfies this assignment")
    elif $r.split_consumed == false then decision("split";"execution ranks exhausted; split remaining work once")
    else
      (if ($r.attempted_reserves | index("ultra")) != null then []
       else [$p.reserve[] | select(available(.)) | . as $pair | select(($r.attempted_reserves | index($pair.effort)) == null)] end) as $reserve |
      if ($reserve | length) > 0 then $reserve[0] + decision("dispatch";"split child exhausted execution ranks; use next reserve")
      else decision("blocked";"execution and reserve capabilities exhausted") end
    end
  end
' "$request" || die 'cannot evaluate routing policy'
