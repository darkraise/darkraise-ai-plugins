#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
die() { printf 'select-native-tier: %s\n' "$1" >&2; exit 2; }
[ "$#" -eq 2 ] && [ "$1" = --request ] && [ -f "$2" ] || die 'usage: select-native-tier.sh --request FILE'
command -v jq >/dev/null 2>&1 || die 'jq is required'
jq -e -s --slurpfile policy "$HERE/../reference/codex-routing.json" '
  def integer($maximum): type == "number" and . >= 0 and . <= $maximum and floor == .;
  def pair: type == "object" and
    (.model | type == "string" and length > 0) and
    (.effort | type == "string" and length > 0);
  def ordered_history($maximum):
    type == "array" and all(.[]; integer($maximum)) and . == (sort | unique);
  def require($condition; $message): if $condition then . else error($message) end;

  require(length == 1; "exactly one JSON request is required") | .[0] |
  require(type == "object"; "request must be an object") |
  $policy[0] as $p | ($p.execution | map(.rank) | max) as $maximum |
  require(.policy == $p.version; "unsupported routing policy; conversion required before using codex-v2") |
  require(
    (.operation == "assign" or .operation == "escalate") and
    (.role == "implementer" or .role == "scout" or .role == "judge") and
    (.assignment_source == "rubric" or .assignment_source == "human") and
    (.available_pairs | type == "array" and all(.[]; pair)) and
    (.split_consumed | type == "boolean") and
    (.review_rounds | type == "number" and . >= 0 and floor == .);
    "invalid request or missing advertised model/effort metadata") |
  require(.attempted_ranks | ordered_history($maximum); "invalid execution history: ranks must be unique and increasing") |
  require(.attempted_reserves | type == "array"; "invalid reserve history") |
  (.attempted_reserves | map(. as $effort | $p.reserve | map(.effort) | index($effort))) as $reserve_indices |
  require($reserve_indices | ordered_history(($p.reserve | length) - 1); "invalid reserve history: efforts must be known, unique and increasing") |
  require(.operation != "assign" or ((.attempted_ranks | length) == 0 and (.attempted_reserves | length) == 0);
    "initial assignment cannot carry previous attempts") |
  if .assignment_source == "human" then
    require(.pinned_pair | pair; "human assignment requires an explicit model/effort pair")
  else
    require(.axes | type == "object" and ([.files,.spec,.coupling,.risk] | all(.[]; integer(3)));
      "rubric axes files/spec/coupling/risk must each be integers from 0 through 3") |
    require(.axes.spec < 3 and (.axes.files + .axes.spec + .axes.coupling) < 4;
      "Rule S requires splitting or settling the approach before assignment") |
    (.axes.files + .axes.spec + .axes.coupling + 2 * .axes.risk) as $score |
    require((has("score") | not) or (.score | integer($maximum)); "score must be an integer from 0 through 9") |
    require((has("score") | not) or .score == $score; "score does not match the weighted raw axes") |
    .score = $score |
    require(.operation != "escalate" or (.attempted_ranks | length) > 0; "escalation requires execution history") |
    require((.attempted_reserves | length) == 0 or (.split_consumed and .role == "implementer");
      "reserve history requires an implementer with a consumed split")
  end |
  . as $r |
  def available($pair): any($r.available_pairs[]; .model == $pair.model and .effort == $pair.effort);
  def decision($action; $reason): {action:$action,reason:$reason};
  def reserve:
    [$p.reserve | to_entries[] | select(.key > ($reserve_indices | max // -1)) | .value | select(available(.))] as $choices |
    if ($choices | length) > 0 then $choices[0] + decision("dispatch";"split child exhausted execution ranks; use next reserve")
    else decision("blocked";"execution and reserve capabilities exhausted") end;
  (
    if $r.review_rounds >= $p.review_cap then decision("blocked";"five-round review cap reached")
    elif $r.assignment_source == "human" then
      if $r.operation == "assign" and available($r.pinned_pair) then
        {model:$r.pinned_pair.model,effort:$r.pinned_pair.effort} + decision("dispatch";"approved human assignment")
      else decision("approval";"human-pinned assignment requires approval before substitution") end
    elif ($reserve_indices | length) > 0 then reserve
    else
      ([$r.score,$p.role_floors[$r.role],
        (if $r.operation == "escalate" then (($r.attempted_ranks | max) + 1) else 0 end)] | max) as $floor |
      [$p.execution[] | select(.rank >= $floor) | select(available(.))] as $choices |
      if ($choices | length) > 0 then
        $choices[0] + decision("dispatch";
          if $r.operation == "escalate" then "next available higher execution rank"
          elif $choices[0].rank > $r.score then "promoted from score \($r.score) to available rank \($choices[0].rank)"
          else "rubric assignment" end)
      elif $r.operation == "assign" or $r.role != "implementer" then decision("blocked";"no advertised execution pair satisfies this assignment")
      elif $r.split_consumed == false then decision("split";"execution ranks exhausted; split remaining work once")
      else reserve end
    end
  ) | if $r.assignment_source == "rubric" then . + {score:$r.score} else . end
' "$2" || die 'cannot evaluate routing request'
