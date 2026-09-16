#!/usr/bin/env bash
# codex-client.mjs is the only new file that imports the Codex plugin. Every
# case here drives it against the Task 1 stub: no real Codex, no real broker,
# no read of this machine's Claude config.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
STUB="$HERE/fixtures/stub-codex-plugin"
CLIENT="$P/scripts/lib/codex-client.mjs"

export DR_CODEX_SESSION_DIR="$(mktemp -d)"
export CLAUDE_CODE_SESSION_ID=codex-client-test-session

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" "$DR_CODEX_SESSION_DIR"' EXIT

run() { # run <request-json>; echoes the result JSON
  printf '%s' "$1" | node "$CLIENT" "$STUB" 2>"$TMP/stderr"
}

req() { # req <extra-json>
  jq -nc --arg cwd "$TMP" --argjson extra "$1" \
    '{op:"turn", kind:"task", cwd:$cwd, model:"gpt-5.6-sol", effort:"high",
      prompt:"review this", schemaPath:null, sandbox:"read-only",
      resumeThreadId:null, persistThread:false, threadName:null,
      deadlineMs:5000} + $extra'
}

# --- a plain turn succeeds ---
export STUB_MODE=ok STUB_FINAL_MESSAGE='{"spec_verdict":"met"}'
out=$(run "$(req '{}')")
check "turn: ok is true" "$(jq -r '.ok' <<<"$out")" "true"
check "turn: turnStatus is 0" "$(jq -r '.turnStatus' <<<"$out")" "0"
check "turn: finalMessage passes through" "$(jq -r '.finalMessage' <<<"$out")" '{"spec_verdict":"met"}'
check "turn: threadId captured" "$(jq -r '.threadId' <<<"$out")" "stub-thread"
check "turn: turnId captured" "$(jq -r '.turnId' <<<"$out")" "stub-turn"
check "turn: reason is null" "$(jq -r '.reason' <<<"$out")" "null"

# --- every kind runs one plain turn; nothing reaches a review entry point ---
export STUB_EVENT_LOG="$TMP/events.log"
: > "$STUB_EVENT_LOG"
run "$(req '{"kind":"final"}')" >/dev/null
check "final: routes to runAppServerTurn" \
  "$(grep -c '^runAppServerTurn' "$STUB_EVENT_LOG")" "1"
: > "$STUB_EVENT_LOG"
run "$(req '{}')" >/dev/null
check "task: routes to runAppServerTurn" \
  "$(grep -c '^runAppServerTurn' "$STUB_EVENT_LOG")" "1"
unset STUB_EVENT_LOG

# --- a plugin that will not import fails closed ---
out=$(printf '%s' "$(req '{}')" | node "$CLIENT" "$TMP/not-a-plugin" 2>/dev/null)
check "missing plugin: ok is false" "$(jq -r '.ok' <<<"$out")" "false"
check "missing plugin: reason" "$(jq -r '.reason' <<<"$out")" "plugin-api"

# --- an unavailable codex fails closed ---
export STUB_MODE=unavailable
out=$(run "$(req '{}')")
check "unavailable: ok is false" "$(jq -r '.ok' <<<"$out")" "false"
check "unavailable: reason" "$(jq -r '.reason' <<<"$out")" "unavailable"
export STUB_MODE=ok

# --- a malformed request is rejected, not guessed at ---
out=$(printf 'not json' | node "$CLIENT" "$STUB" 2>/dev/null)
check "bad request: ok is false" "$(jq -r '.ok' <<<"$out")" "false"
check "bad request: reason" "$(jq -r '.reason' <<<"$out")" "bad-request"
out=$(run "$(jq -nc '{op:"turn", kind:"task"}')")
check "missing cwd: reason" "$(jq -r '.reason' <<<"$out")" "bad-request"

# --- the process always exits 0 so bash reads the JSON, not an exit code ---
printf '%s' "$(req '{}')" | node "$CLIENT" "$STUB" >/dev/null 2>&1
check "exit code is always 0" "$?" "0"

# --- the deadline interrupts rather than merely abandoning ---
export STUB_MODE=hang STUB_EVENT_LOG="$TMP/deadline.log"
: > "$STUB_EVENT_LOG"
out=$(run "$(req '{"deadlineMs":300}')")
check "deadline: ok is false" "$(jq -r '.ok' <<<"$out")" "false"
check "deadline: timedOut is true" "$(jq -r '.timedOut' <<<"$out")" "true"
check "deadline: reason" "$(jq -r '.reason' <<<"$out")" "timeout"
check "deadline: interrupted is true" "$(jq -r '.interrupted' <<<"$out")" "true"
check "deadline: interrupt carried both ids" \
  "$(grep -c '^interruptAppServerTurn stub-thread stub-turn' "$STUB_EVENT_LOG")" "1"
unset STUB_EVENT_LOG
export STUB_MODE=ok

# --- a turn that finishes in time is never interrupted ---
export STUB_EVENT_LOG="$TMP/no-interrupt.log"
: > "$STUB_EVENT_LOG"
run "$(req '{}')" >/dev/null
check "fast turn: no interrupt" "$(grep -c '^interruptAppServerTurn' "$STUB_EVENT_LOG")" "0"
unset STUB_EVENT_LOG

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
