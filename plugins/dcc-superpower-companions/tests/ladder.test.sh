#!/usr/bin/env bash
# The ladder tables are data the skills read at runtime, so their integrity is
# checkable without a model. The escalation graph must terminate: every agent
# ranks strictly below its successor, so walking successors can never cycle and
# must end at the SPLIT action, which is not an agent.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LADDER="$HERE/../reference/ladder.md"
AGENTS="$HERE/../agents"

IMPLEMENTERS="impl-haiku impl-opus-high impl-opus-low impl-opus-medium impl-sonnet-high impl-sonnet-low impl-sonnet-medium"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

# block <tag> - print the body of the fenced block opened by ```<tag>
block() {
  awk -v tag="$1" '
    $0 == "```" tag { f = 1; next }
    f && $0 == "```" { exit }
    f && NF { print }
  ' "$LADDER"
}

agent_exists() { [ -f "$AGENTS/$1.md" ]; }

check "ladder.md exists" "$([ -f "$LADDER" ] && echo yes || echo no)" "yes"

# --- assignment table -------------------------------------------------------
assignment=$(block assignment)
check "assignment table has 7 rows" "$(printf '%s\n' "$assignment" | grep -c .)" "7"

seen_scores=""
bad_score=NONE
bad_agent=NONE
while read -r score agent; do
  [ -n "$score" ] || continue
  case " $seen_scores " in *" $score "*) bad_score="duplicate:$score" ;; esac
  seen_scores="$seen_scores $score"
  agent_exists "$agent" || bad_agent="$agent"
done <<< "$assignment"

check "assignment scores are unique" "$bad_score" "NONE"
check "every assigned agent has a definition file" "$bad_agent" "NONE"

missing=NONE
for s in 0 1 2 3 4 5 6; do
  case " $seen_scores " in *" $s "*) ;; *) missing="$s" ;; esac
done
check "assignment covers every score 0 through 6" "$missing" "NONE"

# Rule S caps a compliant total at 6. A row above it would mean the split gate
# is bypassable by scoring, which is the defect the gate exists to remove.
above=$(printf '%s\n' "$assignment" | awk 'NF && $1 > 6 {print $1}' | tr '\n' ' ' | sed 's/ $//')
check "assignment has no row above score 6" "${above:-NONE}" "NONE"

# --- escalation table -------------------------------------------------------
escalation=$(block escalation)
check "escalation table has 7 rows" "$(printf '%s\n' "$escalation" | grep -c .)" "7"

bad_from=NONE
bad_to=NONE
terminals=""
while read -r from to; do
  [ -n "$from" ] || continue
  agent_exists "$from" || bad_from="$from"
  if [ "$to" = "SPLIT" ]; then
    terminals="$terminals $from"
  else
    agent_exists "$to" || bad_to="$to"
  fi
done <<< "$escalation"

check "every escalation source has a definition file" "$bad_from" "NONE"
check "every escalation target has a definition file" "$bad_to" "NONE"
check "exactly one terminal rung, and it is impl-opus-high" \
  "$(echo $terminals)" "impl-opus-high"

sources=$(printf '%s\n' "$escalation" | awk 'NF {print $1}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
check "every implementer appears exactly once as an escalation source" "$sources" "$IMPLEMENTERS"

# Judges and scouts are not on the ladder; they are never escalation targets.
offladder=$(printf '%s\n' "$escalation" | awk 'NF {print $1; print $2}' | grep -E '^(judge|scout)-' | tr '\n' ' ' | sed 's/ $//')
check "no judge or scout appears in the escalation table" "${offladder:-NONE}" "NONE"

# --- rank monotonicity ------------------------------------------------------
rank() { # rank <agent> - model_rank * 10 + effort_rank
  case "$1" in
    impl-haiku) echo 0; return ;;
    impl-sonnet-*) m=10 ;;
    impl-opus-*) m=20 ;;
    impl-fable-*) m=30 ;;
    *) echo -1; return ;;
  esac
  case "${1##*-}" in
    low) e=0 ;; medium) e=1 ;; high) e=2 ;; xhigh) e=3 ;; max) e=4 ;; *) echo -1; return ;;
  esac
  echo $((m + e))
}

bad_rank=NONE
while read -r from to; do
  [ -n "$from" ] || continue
  [ "$to" = "SPLIT" ] && continue
  rf=$(rank "$from"); rt=$(rank "$to")
  if [ "$rf" -lt 0 ] || [ "$rt" -lt 0 ]; then bad_rank="unrankable:$from->$to"; break; fi
  if [ "$rt" -le "$rf" ]; then bad_rank="not-increasing:$from($rf)->$to($rt)"; break; fi
done <<< "$escalation"
check "every escalation strictly increases rank" "$bad_rank" "NONE"

# --- termination ------------------------------------------------------------
successor() { printf '%s\n' "$escalation" | awk -v a="$1" 'NF && $1 == a {print $2; exit}'; }

bad_walk=NONE
for start in $IMPLEMENTERS; do
  cur="$start"; steps=0; visited=""
  while [ "$cur" != "SPLIT" ]; do
    case " $visited " in *" $cur "*) bad_walk="cycle-at:$cur"; break ;; esac
    visited="$visited $cur"
    steps=$((steps + 1))
    if [ "$steps" -gt 20 ]; then bad_walk="runaway-from:$start"; break; fi
    cur=$(successor "$cur")
    [ -n "$cur" ] || { bad_walk="dead-end-from:$start"; break; }
  done
  [ "$bad_walk" = NONE ] || break
done
check "escalation from every implementer reaches SPLIT without cycling" "$bad_walk" "NONE"

# --- retirement is over -----------------------------------------------------
# All nine names resolve natively again, so the map is gone. Asserting its
# absence stops a stale table rotting back in behind a passing suite.
retired=$(block retired)
check "the retired-agent map is gone" "$(printf '%s' "$retired" | grep -c .)" "0"

# --- reserve table ----------------------------------------------------------
reserve=$(block reserve)
check "reserve table has 10 rows" "$(printf '%s\n' "$reserve" | grep -c .)" "10"

RESERVE_AGENTS="impl-fable-high impl-fable-low impl-fable-max impl-fable-medium impl-fable-xhigh impl-opus-max impl-opus-xhigh impl-sonnet-max impl-sonnet-xhigh"
RESERVE_SOURCES="impl-fable-high impl-fable-low impl-fable-max impl-fable-medium impl-fable-xhigh impl-opus-high impl-opus-max impl-opus-xhigh impl-sonnet-max impl-sonnet-xhigh"

bad_rfrom=NONE
bad_rto=NONE
rterminals=""
while read -r from to; do
  [ -n "$from" ] || continue
  agent_exists "$from" || bad_rfrom="$from"
  if [ "$to" = "BLOCKED" ]; then
    rterminals="$rterminals $from"
  else
    agent_exists "$to" || bad_rto="$to"
  fi
done <<< "$reserve"

check "every reserve source has a definition file" "$bad_rfrom" "NONE"
check "every reserve target has a definition file" "$bad_rto" "NONE"
check "exactly one reserve terminal, and it is impl-fable-max" \
  "$(echo $rterminals)" "impl-fable-max"

rsources=$(printf '%s\n' "$reserve" | awk 'NF {print $1}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
check "reserve sources are the nine reserve agents plus the entry rung" \
  "$rsources" "$RESERVE_SOURCES"

# The gate is structural: if an ordinary escalation row could reach a reserve
# agent, a task would arrive there without a split standing in front of it.
leak=NONE
for a in $RESERVE_AGENTS; do
  if printf '%s\n' "$escalation" | awk -v a="$a" 'NF && ($1 == a || $2 == a) { found = 1 } END { exit !found }'; then
    leak="$a"
  fi
done
check "no escalation row mentions a reserve agent" "$leak" "NONE"

# impl-opus-high is a source in both tables, and the difference between them is
# whether the split has been spent. No other agent may be in both.
esources=$(printf '%s\n' "$escalation" | awk 'NF {print $1}' | LC_ALL=C sort)
overlap=$(printf '%s\n' "$rsources" | tr ' ' '\n' | grep -Fx -f <(printf '%s\n' "$esources") | tr '\n' ' ' | sed 's/ $//')
check "impl-opus-high is the only source in both tables" "$overlap" "impl-opus-high"

bad_rrank=NONE
while read -r from to; do
  [ -n "$from" ] || continue
  [ "$to" = "BLOCKED" ] && continue
  rf=$(rank "$from"); rt=$(rank "$to")
  if [ "$rf" -lt 0 ] || [ "$rt" -lt 0 ]; then bad_rrank="unrankable:$from->$to"; break; fi
  if [ "$rt" -le "$rf" ]; then bad_rrank="not-increasing:$from($rf)->$to($rt)"; break; fi
done <<< "$reserve"
check "every reserve step strictly increases rank" "$bad_rrank" "NONE"

reserve_successor() { printf '%s\n' "$reserve" | awk -v a="$1" 'NF && $1 == a {print $2; exit}'; }

bad_rwalk=NONE
for start in $RESERVE_AGENTS; do
  cur="$start"; steps=0; visited=""
  while [ "$cur" != "BLOCKED" ]; do
    case " $visited " in *" $cur "*) bad_rwalk="cycle-at:$cur"; break ;; esac
    visited="$visited $cur"
    steps=$((steps + 1))
    if [ "$steps" -gt 20 ]; then bad_rwalk="runaway-from:$start"; break; fi
    cur=$(reserve_successor "$cur")
    [ -n "$cur" ] || { bad_rwalk="dead-end-from:$start"; break; }
  done
  [ "$bad_rwalk" = NONE ] || break
done
check "reserve from every reserve agent reaches BLOCKED without cycling" "$bad_rwalk" "NONE"

offreserve=$(printf '%s\n' "$reserve" | awk 'NF {print $1; print $2}' | grep -E '^(judge|scout)-' | tr '\n' ' ' | sed 's/ $//')
check "no judge or scout appears in the reserve table" "${offreserve:-NONE}" "NONE"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
