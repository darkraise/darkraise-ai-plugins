#!/usr/bin/env bash
# The judge blocks are data the review runners read at runtime, so their
# integrity is checkable without a model.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
LADDER="$P/reference/ladder.md"

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

check "ladder.md exists" "$([ -f "$LADDER" ] && echo yes || echo no)" "yes"

# --- codex-judge -------------------------------------------------------------
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

# Controllers run the review runners as background Bash calls
# with timeout = (bound + 120) * 1000 ms, and a background call caps at
# 7200000 ms. A bound past 7080 seconds would be killed by the host before the
# runner could print its status line.
too_long=NONE
while read -r model effort secs _; do
  [ -n "$model" ] || continue
  [ $(( (secs + 120) * 1000 )) -le 7200000 ] || too_long="judge:$model/$effort:$secs"
done <<< "$judge"
check "every bound plus 120 s fits a background call's 7200000 ms cap" "$too_long" "NONE"

# --- agy-judge -----------------------------------------------------------------
agy=$(block agy-judge)
check "agy-judge preferred row" "$(printf '%s\n' "$agy" | sed -n 1p)" "claude-opus-5-5 high 5400"
check "agy-judge fallback row" "$(printf '%s\n' "$agy" | sed -n 2p)" "gemini-4-argon high 2400"
too_long=NONE
while read -r model effort secs _; do
  [ -n "$model" ] || continue
  [ $(( (secs + 120) * 1000 )) -le 7200000 ] || too_long="judge:$model/$effort:$secs"
done <<< "$agy"
check "every agy-judge bound plus 120 s fits a background call's cap" "$too_long" "NONE"

# --- judge blocks --------------------------------------------------------------
rows=$(awk '$0 == "```agy-judge" { f = 1; next } f && $0 == "```" { exit } f && NF' "$P/reference/ladder.md")
check "agy-judge has two rows" "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')" "2"
check "agy-judge rows are model effort seconds" "$(printf '%s\n' "$rows" | awk 'NF != 3 || $3 !~ /^[0-9]+$/' | wc -l | tr -d ' ')" "0"
check "no lane runner remains" "$(ls "$P/scripts" | grep -c -e '^run-codex-task' -e '^run-agy-task' -e '^lane-breaker')" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
