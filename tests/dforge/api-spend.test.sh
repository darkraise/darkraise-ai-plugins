#!/usr/bin/env bash
# api-spend and lib/api-budget.sh: which API budgets are open, and what dforge spent on them.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/../../plugins/dforge"
unset CLAUDE_CONFIG_DIR DFORGE_NO_SETTINGS DFORGE_API_SPEND_FILE DFORGE_API_PRICES DFORGE_FLOCK DR_LOCK_TENTHS
unset DFORGE_OPENAI_API_KEY DFORGE_ANTHROPIC_API_KEY DFORGE_AGENTROUTER_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { case "$2" in *"$3"*) check "$1" yes yes ;; *) check "$1" "[$2]" "contains [$3]" ;; esac; }
lacks() { case "$2" in *"$3"*) check "$1" "[$2]" "lacks [$3]" ;; *) check "$1" yes yes ;; esac; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
export HOME="$TMP/home"; mkdir -p "$HOME/.dforge"
SPEND="$P/scripts/api-spend"
FILE="$HOME/.dforge/api-spend.json"
caps() { printf '{"apiBudgetAnthropic":%s,"apiBudgetOpenai":%s,"apiBudgetAgentRouter":%s}\n' "$1" "$2" "$3" > "$HOME/.dforge/config.json"; }
keys() { export DFORGE_ANTHROPIC_API_KEY=sk-test-anthropic-SENTINEL DFORGE_OPENAI_API_KEY=sk-test-openai-SENTINEL DFORGE_AGENTROUTER_API_KEY=sk-test-agentrouter-SENTINEL; }
nokeys() { unset DFORGE_ANTHROPIC_API_KEY DFORGE_OPENAI_API_KEY DFORGE_AGENTROUTER_API_KEY; }
status() { bash "$SPEND" status 2>>"$TMP/err" | tr -d '\r'; }
line() { status | grep "^api-budget $1 "; }
j() { jq -r "$1" | tr -d '\r'; }

# --- closed by default ---
check "no cap, no key: every budget is off, in the order tried" "$(status)" \
"api-budget anthropic open=false spent=0.0000 cap=0.0000 reason=off
api-budget openai open=false spent=0.0000 cap=0.0000 reason=off
api-budget agentrouter open=false spent=0.0000 cap=0.0000 reason=off"
keys
check "a key with no cap is still off" "$(line openai)" "api-budget openai open=false spent=0.0000 cap=0.0000 reason=off"

# --- A10: only the DFORGE_ variables count ---
nokeys; caps 10 10 10
export OPENAI_API_KEY=vendor-openai ANTHROPIC_API_KEY=vendor-anthropic
check "A10: the vendors' own variables open no budget" "$(status | grep -c 'open=false .* reason=no-key$')" "3"
unset OPENAI_API_KEY ANTHROPIC_API_KEY
export DFORGE_OPENAI_API_KEY=""
check "an empty key variable is no key" "$(line openai)" "api-budget openai open=false spent=0.0000 cap=10.0000 reason=no-key"

# --- open, add, spent ---
keys
check "a cap and a key: open" "$(line anthropic)" "api-budget anthropic open=true spent=0.0000 cap=10.0000 reason=ok"
bash "$SPEND" add openai 1.25; check "add: exit 0" "$?" "0"
check "add prints nothing" "$(bash "$SPEND" add openai 0.0005 2>&1)" ""
check "add: the amount accumulates, to four decimals" "$(line openai)" "api-budget openai open=true spent=1.2505 cap=10.0000 reason=ok"
check "add: calls are counted" "$(j '.openai.calls' < "$FILE")" "2"
check "add: the other budgets are untouched" "$(line agentrouter)" "api-budget agentrouter open=true spent=0.0000 cap=10.0000 reason=ok"
bash "$SPEND" add anthropic 9.4
check "below 95% of the cap: open" "$(line anthropic)" "api-budget anthropic open=true spent=9.4000 cap=10.0000 reason=ok"
bash "$SPEND" add anthropic 0.2
check "at or above 95% of the cap: spent" "$(line anthropic)" "api-budget anthropic open=false spent=9.6000 cap=10.0000 reason=spent"
nokeys
check "no key is reported before spent" "$(line anthropic)" "api-budget anthropic open=false spent=9.6000 cap=10.0000 reason=no-key"
caps 0 10 10
check "off is reported before no key" "$(line anthropic)" "api-budget anthropic open=false spent=9.6000 cap=0.0000 reason=off"

# --- the spend file ---
keys; caps 10 10 10
export DFORGE_API_SPEND_FILE="$TMP/elsewhere.json"
bash "$SPEND" add agentrouter 2
check "DFORGE_API_SPEND_FILE moves the file" "$(j '.agentrouter.spent_usd == 2' < "$TMP/elsewhere.json")" "true"
check "the default file is untouched" "$(j '.agentrouter.spent_usd // 0' < "$FILE")" "0"
unset DFORGE_API_SPEND_FILE
printf '{"openai": {"spent_usd": 5' > "$FILE"
check "a spend file that cannot be read closes every budget" "$(status | grep -c 'open=false .* reason=unreadable$')" "3"
rm -f "$FILE"
for _ in 1 2 3 4 5 6 7 8 9 10; do bash "$SPEND" add openai 0.1 & done; wait
check "ten adds at once all land" "$(j '.openai.calls' < "$FILE") $(line openai | sed 's/.* spent=\([0-9.]*\) .*/\1/')" "10 1.0000"

# --- the lock: one left by a killed process, and one that is held ---
LOCKBASE=$( . "$P/scripts/lib/lock.sh"; dr_lock_base "$FILE" )
: > "$LOCKBASE.lock"
bash "$SPEND" add openai 0.1; rc=$?
check "a lock file left behind does not block an add" "$rc $(j '.openai.calls' < "$FILE")" "0 11"
sleep 0 & dead=$!; wait "$dead"
mkdir "$LOCKBASE.lockd"; uname -n > "$LOCKBASE.lockd/host"; printf '%s\n' "$dead" > "$LOCKBASE.lockd/pid"
DFORGE_FLOCK=no-such-flock bash "$SPEND" add openai 0.1 2>>"$TMP/err"; rc=$?
check "no flock: a lock whose owner is dead is reclaimed" "$rc $(j '.openai.calls' < "$FILE")" "0 12"
for _ in 1 2 3 4 5; do DFORGE_FLOCK=no-such-flock bash "$SPEND" add openai 0.1 & done; wait
check "no flock: five adds at once all land" "$(j '.openai.calls' < "$FILE")" "17"
check "no flock: the lock directory is gone" "$([ -e "$LOCKBASE.lockd" ] && echo left || echo gone)" "gone"
mkdir "$LOCKBASE.lockd"; uname -n > "$LOCKBASE.lockd/host"; printf '%s\n' "$$" > "$LOCKBASE.lockd/pid"
DFORGE_FLOCK=no-such-flock DR_LOCK_TENTHS=3 bash "$SPEND" add openai 0.1 2>"$TMP/busy.err"; rc=$?
check "a lock a live process holds: the add exits 1 and adds nothing" "$rc $(j '.openai.calls' < "$FILE")" "1 17"
has "a lock a live process holds: stderr says so" "$(cat "$TMP/busy.err")" "is locked by another process"
(. "$P/scripts/lib/api-budget.sh"; DFORGE_FLOCK=no-such-flock DR_LOCK_TENTHS=3 api_budget_charge openai 0.1 2>/dev/null)
check "charge returns the add's status" "$?" "1"
rm -rf "$LOCKBASE.lockd"

# --- usage ---
bash "$SPEND" add nope 1 2>/dev/null; check "an unknown budget: exit 2" "$?" "2"
bash "$SPEND" add openai abc 2>/dev/null; check "an amount that is not a number: exit 2" "$?" "2"
bash "$SPEND" add openai -1 2>/dev/null; check "a negative amount: exit 2" "$?" "2"
bash "$SPEND" add openai 2>/dev/null; check "a missing amount: exit 2" "$?" "2"
bash "$SPEND" frob 2>/dev/null; check "an unknown command: exit 2" "$?" "2"
check "a refused add changes nothing" "$(j '.openai.calls' < "$FILE")" "17"

# --- the library ---
lib() { (. "$P/scripts/lib/api-budget.sh"; "$@"); }
check "key variable: anthropic" "$(lib api_budget_key_var anthropic)" "DFORGE_ANTHROPIC_API_KEY"
check "key variable: openai" "$(lib api_budget_key_var openai)" "DFORGE_OPENAI_API_KEY"
check "key variable: agentrouter" "$(lib api_budget_key_var agentrouter)" "DFORGE_AGENTROUTER_API_KEY"
lib api_budget_key_var nope >/dev/null 2>&1; check "key variable: an unknown budget fails" "$?" "1"
check "state prints the budget's status line" "$(lib api_budget_state agentrouter | tr -d '\r')" "$(line agentrouter)"
lib api_budget_state agentrouter >/dev/null; check "state: 0 when open" "$?" "0"
caps 10 10 0
lib api_budget_state agentrouter >/dev/null; check "state: 1 when closed" "$?" "1"
caps 10 10 10
lib api_budget_charge agentrouter 0.5
check "charge adds to the budget" "$(line agentrouter)" "api-budget agentrouter open=true spent=0.5000 cap=10.0000 reason=ok"

# --- the price table ---
printf '%s\n' '{"checked":"2026-11-14","models":{"m1":{"source":"https://example.invalid/pricing","input":2.5,"cached_input":0.25,"output":10}}}' > "$TMP/prices.json"
export DFORGE_API_PRICES="$TMP/prices.json"
check "price: input" "$(lib api_budget_price m1 input)" "2.5"
check "price: cached input" "$(lib api_budget_price m1 cached_input)" "0.25"
check "price: output" "$(lib api_budget_price m1 output)" "10"
lib api_budget_price m2 input >/dev/null 2>&1; check "price: an unknown model fails" "$?" "1"
lib api_budget_price m1 batch >/dev/null 2>&1; check "price: an unknown field fails" "$?" "1"
unset DFORGE_API_PRICES
check "the shipped table prices the Decisions model" "$(lib api_budget_price gpt-6-luna input)" "0.1"
check "every shipped row names its source and an input price" \
  "$(j '[.models[] | select((.source | startswith("https://") | not) or (.input | type != "number"))] | length' < "$P/reference/api-prices.json")" "0"
check "the shipped table is dated" "$(j '.checked | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}$")' < "$P/reference/api-prices.json")" "true"

# --- A8: no key value is printed or stored ---
lacks "A8: no key value in the output or the spend file" "$(status) $(cat "$TMP/err" 2>/dev/null) $(cat "$FILE")" "SENTINEL"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
