#!/usr/bin/env bash
# Efficiency measurement and auto-run polish: the skill and instruction text
# the spec pins (A9, A10).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$(cd "$HERE/../../plugins/dagents" && pwd)"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
# flat — stdin as one line: newlines to spaces, runs of spaces squeezed, case folded.
flat() { tr -d '\r' | tr '\n' ' ' | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
has() { case $1 in *"$2"*) echo yes ;; *) echo no ;; esac; }

# --- lookups_block_early ---
SKILL="$P/skills/executing-plans/SKILL.md"
check "lookups_block_early: ## Lookups within the first 15,000 characters" \
  "$(head -c 15000 "$SKILL" | tr -d '\r' | grep -c '^## Lookups$')" "1"
check "lookups_block_early: no claim that the session has read the code" \
  "$(has "$(flat < "$SKILL")" 'session has read the code')" "no"

# --- compact_instructions_bounded ---
COCKPIT=$(tr -d '\r' < "$P/hooks/cockpit/register.tsx" | awk '/^const AUTO_COMPACT_INSTRUCTIONS =/ { f = 1; next } f { print; exit }' | flat)
BUDGET=$(tr -d '\r' < "$P/reference/session-budget.md" | awk '/^# Compact instructions$/ { f = 1; next } f && /^```/ { exit } f' | flat)
for phrase in 'at most 1,500 words' 'rulings only for the task in flight and plan-wide rulings' 'one line per finished task'; do
  check "compact_instructions_bounded: the cockpit says '$phrase'" "$(has "$COCKPIT" "$phrase")" "yes"
  check "compact_instructions_bounded: session-budget.md says '$phrase'" "$(has "$BUDGET" "$phrase")" "yes"
done

# --- mirror_audit ---
# Each polish item and the markers and report: the dagents cases that mirror
# it (every one must exist), or a row of fixtures/mirror-na.tsv with a reason.
ROOT="$(cd "$HERE/../.." && pwd)"
NA="$HERE/fixtures/mirror-na.tsv"
MIRROR='1	tests/dagents/efficiency-measurement.acceptance.test.sh::compact_instructions_bounded
2	tests/dagents/auto-run.test.sh::resume_reactivates
2	tests/dagents/auto-run.test.sh::resume_refusals
3	tests/dagents/auto-run.test.sh::version_mismatch_warns_once
3	plugins/dagents/tests/cockpit.test.ts::run row shows mismatch
4	tests/dagents/budget-line.test.sh::task_complete_prints_auto_line
5	tests/dagents/codex-review.test.sh::quota_skip_in_run
5	tests/dagents/codex-review.test.sh::prompt_says_headless
7	tests/dagents/task-step.test.sh::verdict_line_ref_parenthetical
8	tests/dagents/impl-stop-gate.test.sh::ui_proof_exempt
9	tests/dagents/auto-run.test.sh::api_error_counts_apart
9	plugins/dagents/tests/cockpit.test.ts::api-error ending re-prompts
10	tests/dagents/auto-run.test.sh::counters_after_events
10	plugins/dagents/tests/cockpit.test.ts::compaction books seconds
markers	tests/dagents/usage-marker.test.sh::task_step_start_opens_each
markers	tests/dagents/usage-marker.test.sh::marker_failure_silent
report	tests/dagents/usage-report.test.sh::wrapper_reads_own_stores'
check "mirror_audit: fixtures/mirror-na.tsv exists" "$([ -f "$NA" ] && echo yes || echo no)" "yes"
bad=$(tr -d '\r' 2>/dev/null < "$NA" | awk -F'\t' 'NF && ($1 == "" || $2 == "")' | wc -l | tr -d ' ')
check "mirror_audit: every n/a row names an item and a reason" "$bad" "0"
for item in 1 2 3 4 5 7 8 9 10 markers report; do
  cases=$(printf '%s\n' "$MIRROR" | awk -F'\t' -v i="$item" '$1 == i { print $2 }')
  missing=""
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    grep -qF -- "${c#*::}" "$ROOT/${c%%::*}" 2>/dev/null || missing="$missing ${c}"
  done <<<"$cases"
  if [ -n "$cases" ] && [ -z "$missing" ]; then got=mirrored
  elif tr -d '\r' 2>/dev/null < "$NA" | awk -F'\t' -v i="$item" '$1 == i && $2 != "" { f = 1 } END { exit !f }'; then got="n/a"
  else got="neither:${missing:- no case}"; fi
  check "mirror_audit: polish $item is mirrored or n/a" "$( [ "${got#neither}" = "$got" ] && echo ok || echo "$got")" "ok"
done
# Polish 5 is mirrored for the Codex family only: the rest must be recorded n/a.
check "mirror_audit: polish 5's panel and agy runner are recorded n/a" \
  "$(tr -d '\r' 2>/dev/null < "$NA" | awk -F'\t' '$1 == "5" && $2 != "" { n++ } END { print n + 0 }')" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
