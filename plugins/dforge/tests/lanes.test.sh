#!/usr/bin/env bash
# The lane tables are data the skills and the wrapper script read at runtime, so
# their integrity is checkable without a model. Two invariants matter most: no
# rung may name a model outside the external CLI policy, and the
# successor column must terminate at HANDBACK rather than cycling.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LADDER="$HERE/../reference/ladder.md"

# Probed on 2026-08-31 against Codex 0.151.0 with ChatGPT-subscription auth:
# GPT-5.6 Luna and Terra were rejected with HTTP 400, and minimal was rejected
# as an effort. gpt-5.5 retires from Codex with ChatGPT sign-in on 2026-10-14.
VALID_MODELS="gpt-6.1-sol"
VALID_EFFORTS="low medium high xhigh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

block() {
  awk -v tag="$1" '
    $0 == "```" tag { f = 1; next }
    f && $0 == "```" { exit }
    f && NF { print }
  ' "$LADDER"
}

in_list() { case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# rank orders a rung for the termination proof: model major, effort minor.
rank() {
  local m="${1%%/*}" e="${1##*/}" mr er
  case "$m" in gpt-6.1-sol) mr=0 ;; *) echo -1; return ;; esac
  case "$e" in low) er=0 ;; medium) er=1 ;; high) er=2 ;; xhigh) er=3 ;; *) echo -1; return ;; esac
  echo $((mr * 10 + er))
}

check "ladder.md exists" "$([ -f "$LADDER" ] && echo yes || echo no)" "yes"

# --- gate -------------------------------------------------------------------
gate=$(block gate)
check "gate min_score is 2" "$(printf '%s\n' "$gate" | awk '$1=="min_score"{print $2}')" "2"
check "gate max_risk is 1" "$(printf '%s\n' "$gate" | awk '$1=="max_risk"{print $2}')" "1"
check "gate max_score is 4" "$(printf '%s\n' "$gate" | awk '$1=="max_score"{print $2}')" "4"
check "gate requires a clean Rule S pass" \
  "$(printf '%s\n' "$gate" | awk '$1=="require_rule_s_clean"{print $2}')" "true"
check "gate requires an enabled executor" \
  "$(printf '%s\n' "$gate" | awk '$1=="require_external_enabled"{print $2}')" "true"

# --- codex-assignment -------------------------------------------------------
assignment=$(block codex-assignment)
check "codex-assignment has 3 rows" "$(printf '%s\n' "$assignment" | grep -c .)" "3"

bad_model=NONE bad_effort=NONE seen=""
while read -r score model effort; do
  [ -n "$score" ] || continue
  in_list "$model" "$VALID_MODELS" || bad_model="$model"
  in_list "$effort" "$VALID_EFFORTS" || bad_effort="$effort"
  seen="$seen $score"
done <<< "$assignment"
check "every assigned model matches the external CLI policy" "$bad_model" "NONE"
check "every assigned effort is valid" "$bad_effort" "NONE"

missing=NONE
for s in 2 3 4; do in_list "$s" "$seen" || missing="$s"; done
check "codex-assignment covers scores 2, 3 and 4" "$missing" "NONE"

# max_score 4 bounds the eligible totals, so no row may sit outside 2..4, and
# the highest row is the gate's ceiling.
outside=$(printf '%s\n' "$assignment" | awk 'NF && ($1 < 2 || $1 > 4) {print $1}' | tr '\n' ' ' | sed 's/ $//')
check "codex-assignment has no row outside 2..4" "${outside:-NONE}" "NONE"
check "the highest codex-assignment row is the gate's max_score" \
  "$(printf '%s\n' "$assignment" | awk 'NF && $1 > m { m = $1 } END { print m }')" \
  "$(printf '%s\n' "$gate" | awk '$1=="max_score"{print $2}')"

retired=$(printf '%s\n' "$assignment" "$(block codex-successor)" "$(block codex-timeout)" "$(block codex-judge)" | grep -c 'gpt-5\.5')
check "no lane block names gpt-5.5, which leaves Codex on 2026-10-14" "$retired" "0"

# --- codex-successor --------------------------------------------------------
successor=$(block codex-successor)
succ_of() { printf '%s\n' "$successor" | awk -v k="$1" '$1 == k {print $2}'; }

bad_rank=NONE
while read -r from to; do
  [ -n "$from" ] || continue
  [ "$to" = HANDBACK ] && continue
  fr=$(rank "$from"); tr=$(rank "$to")
  { [ "$fr" -lt 0 ] || [ "$tr" -lt 0 ]; } && { bad_rank="unrankable:$from->$to"; continue; }
  [ "$tr" -gt "$fr" ] || bad_rank="not-increasing:$from->$to"
done <<< "$successor"
check "every successor ranks strictly above its source" "$bad_rank" "NONE"

bad_walk=NONE
while read -r start _; do
  [ -n "$start" ] || continue
  cur="$start"
  for _ in 1 2 3 4 5 6; do
    [ "$cur" = HANDBACK ] && break
    cur=$(succ_of "$cur")
    [ -n "$cur" ] || { bad_walk="dead-end-from:$start"; break; }
  done
  [ "$cur" = HANDBACK ] || bad_walk="${bad_walk#NONE}no-terminal-from:$start"
  [ "$bad_walk" = NONE ] || break
done <<< "$successor"
check "every rung reaches HANDBACK without cycling" "$bad_walk" "NONE"

# Every assignment rung must have somewhere to go on a capability failure.
bad_entry=NONE
while read -r _ model effort; do
  [ -n "$model" ] || continue
  [ -n "$(succ_of "$model/$effort")" ] || bad_entry="$model/$effort"
done <<< "$assignment"
check "every assignment rung has a successor" "$bad_entry" "NONE"

# --- codex-timeout ----------------------------------------------------------
timeouts=$(block codex-timeout)
bad_timeout=NONE
while read -r from to; do
  [ -n "$from" ] || continue
  secs=$(printf '%s\n' "$timeouts" | awk -v k="$from" '$1 == k {print $2}')
  [ -n "$secs" ] || { bad_timeout="missing:$from"; continue; }
  printf '%s' "$secs" | grep -qE '^[0-9]+$' || bad_timeout="non-numeric:$from"
  [ "$to" = HANDBACK ] && continue
  secs_to=$(printf '%s\n' "$timeouts" | awk -v k="$to" '$1 == k {print $2}')
  [ -n "$secs_to" ] || bad_timeout="missing:$to"
done <<< "$successor"
check "every rung named anywhere has a numeric timeout" "$bad_timeout" "NONE"

# The wrapper admits an effort before it looks up the bound, so an admitted
# effort without a row passes validation only to die at the lookup.
wrapper_efforts=$(sed -n 's/^VALID_EFFORTS="\(.*\)"$/\1/p' "$HERE/../scripts/run-codex-task.sh")
no_row=NONE
for m in $(printf '%s\n' "$assignment" | awk '{print $2}' | sort -u); do
  for e in $wrapper_efforts; do
    [ -n "$(printf '%s\n' "$timeouts" | awk -v k="$m/$e" '$1 == k')" ] || no_row="$m/$e"
  done
done
check "every effort the wrapper admits has a codex-timeout row" "$no_row" "NONE"

# --- codex-judge -------------------------------------------------------------
# The judge rung is policy for the two review seats, not a rung on the
# execution ladder: run-codex-task.sh:93 validates --model against
# codex-assignment, so a judge model there would widen execution admission.
# Its allowlist is therefore separate from VALID_MODELS on purpose.
JUDGE_MODELS="gpt-6-astra gpt-6.1-sol"

judge=$(block codex-judge)
check "codex-judge block is present" "$([ -n "$judge" ] && echo yes || echo no)" "yes"

rows=$(printf '%s\n' "$judge" | grep -c .)
check "codex-judge has exactly two rows" "$rows" "2"

# Exact pairs, not merely "two distinct rows". A test that only asserts
# distinctness admits a fallback the owner never approved, and admits a row
# that does not run at high.
check "codex-judge preferred row" "$(printf '%s\n' "$judge" | sed -n 1p)" "gpt-6-astra xhigh 5400"
check "codex-judge fallback row" "$(printf '%s\n' "$judge" | sed -n 2p)" "gpt-6.1-sol xhigh 2400"

bad_judge=NONE
while read -r model effort secs extra; do
  [ -n "$model" ] || continue
  [ -z "$extra" ] || bad_judge="extra-field:$model"
  in_list "$model" "$JUDGE_MODELS" || bad_judge="model:$model"
  in_list "$effort" "$VALID_EFFORTS" || bad_judge="effort:$effort"
  printf '%s' "$secs" | grep -qE '^[1-9][0-9]*$' || bad_judge="timeout:$model"
done <<< "$judge"
check "codex-judge rows are well formed" "$bad_judge" "NONE"

# The third column duplicates a constant that also lives in codex-timeout.
# Nothing else would notice the two drifting apart.
drift=NONE
while read -r model effort secs _; do
  [ -n "$model" ] || continue
  t=$(printf '%s\n' "$timeouts" | awk -v k="$model/$effort" '$1 == k {print $2}')
  [ -z "$t" ] && continue
  [ "$t" = "$secs" ] || drift="$model/$effort:$secs!=$t"
done <<< "$judge"
check "codex-judge agrees with codex-timeout" "$drift" "NONE"

# Controllers run the wrapper and the review runner as background Bash calls
# with timeout = (bound + 120) * 1000 ms, and a background call caps at
# 7200000 ms. A bound past 7080 seconds would be killed by the host before the
# wrapper could print its status line.
too_long=NONE
while read -r pair secs; do
  [ -n "$pair" ] || continue
  [ $(( (secs + 120) * 1000 )) -le 7200000 ] || too_long="timeout:$pair:$secs"
done <<< "$timeouts"
while read -r model effort secs _; do
  [ -n "$model" ] || continue
  [ $(( (secs + 120) * 1000 )) -le 7200000 ] || too_long="judge:$model/$effort:$secs"
done <<< "$judge"
check "every bound plus 120 s fits a background call's 7200000 ms cap" "$too_long" "NONE"

# The judge block must not leak into execution admission.
leak=NONE
printf '%s\n' "$assignment" | awk '{print $2}' | grep -qxF gpt-6-astra && leak=assignment
printf '%s\n' "$successor" | tr ' ' '\n' | grep -qF gpt-6-astra && leak=successor
check "no judge model appears in the execution blocks" "$leak" "NONE"

# --- the agy lane --------------------------------------------------------------
# agy admits wider bands than Codex, so its blocks are checked on their own.
AGY_MODELS="gemini-3.8-flash gemini-4-argon claude-sonnet-5-5 claude-opus-5-5"
AGY_EFFORTS="low medium high"

agy_gate=$(block agy-lane-gate)
agy_gate_field() { printf '%s\n' "$agy_gate" | awk -v k="$1" '$1 == k {print $2}'; }
check "agy-lane-gate has five lines" "$(printf '%s\n' "$agy_gate" | grep -c .)" "5"
check "agy-lane-gate min_score is 0" "$(agy_gate_field min_score)" "0"
check "agy-lane-gate max_score is 8" "$(agy_gate_field max_score)" "8"
check "agy-lane-gate max_risk is 2" "$(agy_gate_field max_risk)" "2"
check "agy-lane-gate requires a clean Rule S pass" "$(agy_gate_field require_rule_s_clean)" "true"
check "agy-lane-gate requires an enabled executor" "$(agy_gate_field require_external_enabled)" "true"

agy_assignment=$(block agy-assignment)
check "agy-assignment has 9 rows" "$(printf '%s\n' "$agy_assignment" | grep -c .)" "9"
bad_agy=NONE agy_scores=""
while read -r score model effort extra; do
  [ -n "$score" ] || continue
  in_list "$model" "$AGY_MODELS" || bad_agy="model:$score:$model"
  in_list "$effort" "$AGY_EFFORTS" || bad_agy="effort:$score:$effort"
  [ -z "$extra" ] || bad_agy="extra-field:$score"
  agy_scores="$agy_scores $score"
done <<< "$agy_assignment"
check "every agy-assignment rung names a known model and effort" "$bad_agy" "NONE"
check "agy-assignment has one row for each total 0 through 8" \
  "$(printf '%s\n' $agy_scores | sort -n | tr '\n' ' ')" "0 1 2 3 4 5 6 7 8 "
check "agy-assignment runs Flash medium on 0-2, Argon low on 3-4 and Argon high on 5-8" \
  "$(printf '%s\n' "$agy_assignment" | tr '\n' ',')" \
  "0 gemini-3.8-flash medium,1 gemini-3.8-flash medium,2 gemini-3.8-flash medium,3 gemini-4-argon low,4 gemini-4-argon low,5 gemini-4-argon high,6 gemini-4-argon high,7 gemini-4-argon high,8 gemini-4-argon high,"
check "no agy-assignment row starts on a Claude model" \
  "$(printf '%s\n' "$agy_assignment" | awk '$2 ~ /^claude-/' | grep -c .)" "0"
check "the lowest agy-assignment row is the gate's min_score" \
  "$(printf '%s\n' "$agy_assignment" | awk 'NR == 1 || $1 < m { m = $1 } END { print m }')" "$(agy_gate_field min_score)"
check "the highest agy-assignment row is the gate's max_score" \
  "$(printf '%s\n' "$agy_assignment" | awk '$1 > m { m = $1 } END { print m }')" "$(agy_gate_field max_score)"

agy_rank() { # agy_rank <model>/<effort>: model_rank * 10 + effort_rank, or -1
  local m="${1%%/*}" e="${1##*/}" mr er
  case "$m" in gemini-*) mr=0 ;; claude-sonnet-5-5) mr=1 ;; claude-opus-5-5) mr=2 ;; *) echo -1; return ;; esac
  case "$e" in low) er=0 ;; medium) er=1 ;; high) er=2 ;; *) echo -1; return ;; esac
  echo $((mr * 10 + er))
}

agy_successor=$(block agy-successor)
# The checks below loop over the rows, so an empty block would pass them all.
check "agy-successor block is present" "$([ -n "$agy_successor" ] && echo yes || echo no)" "yes"
check "agy-successor sends each Gemini rung to Sonnet and each Sonnet rung back" \
  "$(printf '%s\n' "$agy_successor" | tr '\n' ',')" \
  "gemini-3.8-flash/medium claude-sonnet-5-5/medium,gemini-4-argon/low claude-sonnet-5-5/medium,gemini-4-argon/high claude-sonnet-5-5/high,claude-sonnet-5-5/medium HANDBACK,claude-sonnet-5-5/high HANDBACK,"
bad_agy_claude=NONE
while read -r from to; do
  case "$from" in claude-*) [ "$to" = HANDBACK ] || bad_agy_claude="$from->$to" ;; esac
done <<< "$agy_successor"
check "every Claude agy-successor source hands back" "$bad_agy_claude" "NONE"
agy_succ_of() { printf '%s\n' "$agy_successor" | awk -v k="$1" '$1 == k {print $2}'; }

bad_agy_rank=NONE
while read -r from to; do
  [ -n "$from" ] || continue
  [ "$to" = HANDBACK ] && continue
  from_rank=$(agy_rank "$from"); to_rank=$(agy_rank "$to")
  { [ "$from_rank" -lt 0 ] || [ "$to_rank" -lt 0 ]; } && { bad_agy_rank="unrankable:$from->$to"; continue; }
  [ "$to_rank" -gt "$from_rank" ] || bad_agy_rank="not-increasing:$from->$to"
done <<< "$agy_successor"
check "every agy-successor ranks strictly above its source" "$bad_agy_rank" "NONE"

bad_agy_family=NONE
while read -r from to; do
  case "$from" in gemini-*) case "$to" in claude-*) ;; *) bad_agy_family="$from->$to" ;; esac ;; esac
done <<< "$agy_successor"
check "a failed Gemini rung moves to a Claude rung, never to another Gemini effort" "$bad_agy_family" "NONE"

bad_agy_walk=NONE
while read -r start _; do
  [ -n "$start" ] || continue
  cur="$start"
  for _ in 1 2 3 4 5 6; do
    [ "$cur" = HANDBACK ] && break
    cur=$(agy_succ_of "$cur")
    [ -n "$cur" ] || { bad_agy_walk="dead-end-from:$start"; break; }
  done
  [ "$cur" = HANDBACK ] || bad_agy_walk="${bad_agy_walk#NONE}no-terminal-from:$start"
  [ "$bad_agy_walk" = NONE ] || break
done <<< "$agy_successor"
check "every agy-successor rung reaches HANDBACK without cycling" "$bad_agy_walk" "NONE"

bad_agy_entry=NONE
while read -r _ model effort; do
  [ -n "$model" ] || continue
  [ -n "$(agy_succ_of "$model/$effort")" ] || bad_agy_entry="$model/$effort"
done <<< "$agy_assignment"
check "every agy-assignment rung has a successor" "$bad_agy_entry" "NONE"

agy_timeouts=$(block agy-timeout)
check "agy-timeout block is present" "$([ -n "$agy_timeouts" ] && echo yes || echo no)" "yes"
check "agy-timeout gives Argon 900 s at low and 1500 s at high, one row per reachable rung" \
  "$(printf '%s\n' "$agy_timeouts" | tr '\n' ',')" \
  "gemini-3.8-flash/medium 900,gemini-4-argon/low 900,gemini-4-argon/high 1500,claude-sonnet-5-5/medium 1200,claude-sonnet-5-5/high 1800,"
check "no agy block names claude-opus-5-5" \
  "$(printf '%s\n' "$agy_assignment" "$agy_successor" "$agy_timeouts" | grep -c 'claude-opus-5-5')" "0"
bad_agy_timeout=NONE
while read -r from to; do
  [ -n "$from" ] || continue
  for rung in "$from" "$to"; do
    [ "$rung" = HANDBACK ] && continue
    secs=$(printf '%s\n' "$agy_timeouts" | awk -v k="$rung" '$1 == k {print $2}')
    [ -n "$secs" ] || { bad_agy_timeout="missing:$rung"; continue; }
    printf '%s' "$secs" | grep -qE '^[1-9][0-9]*$' || bad_agy_timeout="non-numeric:$rung"
  done
done <<< "$agy_successor"
while read -r _ model effort; do
  [ -n "$model" ] || continue
  [ -n "$(printf '%s\n' "$agy_timeouts" | awk -v k="$model/$effort" '$1 == k {print $2}')" ] || bad_agy_timeout="missing:$model/$effort"
done <<< "$agy_assignment"
check "every agy rung named in an assignment or a successor row has a numeric timeout" "$bad_agy_timeout" "NONE"

agy_too_long=NONE
while read -r pair secs; do
  [ -n "$pair" ] || continue
  [ $(( (secs + 120) * 1000 )) -le 7200000 ] || agy_too_long="$pair:$secs"
done <<< "$agy_timeouts"
check "every agy-timeout bound plus 120 s fits a background call's 7200000 ms cap" "$agy_too_long" "NONE"

check "no agy block names a Codex model" \
  "$(printf '%s\n' "$agy_gate" "$agy_assignment" "$agy_successor" "$agy_timeouts" | grep -c 'gpt-')" "0"

# --- the agy calibration decision ---
# Rows 0-2 of agy-assignment, that rung's successor and timeout rows come from
# replayed runs, so they are checked against what the record decided.
NOTES="$HERE/../../../docs/dforge/notes/2026-11-02-agy-calibration.md"

decision=$(sed -n 's|^\*\*Decision:\*\* totals 0-2 run \([a-z0-9.-]*/[a-z]*\).*$|\1|p' "$NOTES" 2>/dev/null | head -n 1)
band=$(block agy-assignment | awk '$1 + 0 <= 2 { print $2 "/" $3 }' | sort -u | tr '\n' ' ' | sed 's/ $//')
check "agy-assignment rows 0, 1 and 2 all name the decision" "$band" "${decision:-none}"
check "agy-assignment has exactly three rows at or below total 2" \
  "$(block agy-assignment | awk '$1 + 0 <= 2' | grep -c .)" "3"
check "the 0-2 rung's successor is claude-sonnet-5-5/medium" \
  "$(block agy-successor | awk -v k="$decision" '$1 == k { print $2 }')" "claude-sonnet-5-5/medium"
secs=$(block agy-timeout | awk -v k="$decision" '$1 == k { print $2 }')
check "the 0-2 rung has a timeout between 900 and 6900 seconds" \
  "$([ "${secs:-0}" -ge 900 ] && [ "${secs:-0}" -le 6900 ] && echo yes || echo no)" "yes"

reach=$( { block agy-assignment | awk '{ print $2 "/" $3 }'; block agy-successor | awk '$2 != "HANDBACK" { print $2 }'; } | sort -u)
stale=$( { block agy-successor | awk '{ print $1 }'; block agy-timeout | awk '{ print $1 }'; } \
  | sort -u | grep -vxF -f <(printf '%s\n' "$reach") | tr '\n' ' ' | sed 's/ $//')
check "no successor or timeout row names a rung that nothing reaches" "${stale:-NONE}" "NONE"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
