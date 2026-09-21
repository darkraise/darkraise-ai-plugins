#!/usr/bin/env bash
# The lane tables are data the skills and the wrapper script read at runtime, so
# their integrity is checkable without a model. Two invariants matter most: no
# rung may name a model outside the external CLI policy, and the
# successor column must terminate at HANDBACK rather than cycling.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LADDER="$HERE/../reference/ladder.md"

# Probed on 2026-08-31 against Codex 0.151.0 with ChatGPT-subscription auth.
# Luna and Terra were rejected with HTTP 400; minimal was rejected as an effort.
VALID_MODELS="gpt-5.5 gpt-5.6-sol"
VALID_EFFORTS="low medium high xhigh ultra"

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
  case "$m" in gpt-5.5) mr=0 ;; gpt-5.6-sol) mr=1 ;; *) echo -1; return ;; esac
  case "$e" in low) er=0 ;; medium) er=1 ;; high) er=2 ;; xhigh) er=3 ;; ultra) er=4 ;; *) echo -1; return ;; esac
  echo $((mr * 10 + er))
}

check "ladder.md exists" "$([ -f "$LADDER" ] && echo yes || echo no)" "yes"

# --- gate -------------------------------------------------------------------
gate=$(block gate)
check "gate min_score is 2" "$(printf '%s\n' "$gate" | awk '$1=="min_score"{print $2}')" "2"
check "gate max_risk is 1" "$(printf '%s\n' "$gate" | awk '$1=="max_risk"{print $2}')" "1"
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

# Rule S caps reducible at 3, so under max_risk 1 no eligible total exceeds 4.
outside=$(printf '%s\n' "$assignment" | awk 'NF && ($1 < 2 || $1 > 4) {print $1}' | tr '\n' ' ' | sed 's/ $//')
check "codex-assignment has no row outside 2..4" "${outside:-NONE}" "NONE"

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

# --- codex-judge -------------------------------------------------------------
# The judge rung is policy for the two review seats, not a rung on the
# execution ladder: run-codex-task.sh:93 validates --model against
# codex-assignment, so a judge model there would widen execution admission.
# Its allowlist is therefore separate from VALID_MODELS on purpose.
JUDGE_MODELS="gpt-6-astra gpt-5.6-sol"

judge=$(block codex-judge)
check "codex-judge block is present" "$([ -n "$judge" ] && echo yes || echo no)" "yes"

rows=$(printf '%s\n' "$judge" | grep -c .)
check "codex-judge has exactly two rows" "$rows" "2"

# Exact pairs, not merely "two distinct rows". A test that only asserts
# distinctness admits a fallback the owner never approved, and admits a row
# that does not run at high.
check "codex-judge preferred row" "$(printf '%s\n' "$judge" | sed -n 1p)" "gpt-6-astra xhigh 5400"
check "codex-judge fallback row" "$(printf '%s\n' "$judge" | sed -n 2p)" "gpt-5.6-sol xhigh 2400"

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

# The judge block must not leak into execution admission.
leak=NONE
printf '%s\n' "$assignment" | awk '{print $2}' | grep -qxF gpt-6-astra && leak=assignment
printf '%s\n' "$successor" | tr ' ' '\n' | grep -qF gpt-6-astra && leak=successor
check "no judge model appears in the execution blocks" "$leak" "NONE"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
