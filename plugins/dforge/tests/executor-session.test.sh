#!/usr/bin/env bash
# Session state is per executor. The failure this guards is cross-talk: one
# executor hitting a rate limit must not mark another's surfaces off, because
# review-route and plan-lint both read those files.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

export DR_EXECUTORS_DIR="$HERE/fixtures/executors"
export CLAUDE_CODE_SESSION_ID=session-test
export DR_CODEX_SESSION_DIR="$TMP/codex" DR_STUB_SESSION_DIR="$TMP/stub"
. "$P/scripts/lib/executor-session.sh"

check "the session id comes from the environment" "$(executor_session_id)" "session-test"
check "a directory honours its override" "$(executor_session_dir codex)" "$TMP/codex"
check "another executor has its own directory" "$(executor_session_dir stub)" "$TMP/stub"
check "the two directories differ" \
  "$([ "$(executor_session_dir codex)" != "$(executor_session_dir stub)" ] && echo yes || echo no)" "yes"
check "the file is the session id under that directory" \
  "$(executor_session_file codex)" "$TMP/codex/session-test.json"

# --- surfaces --------------------------------------------------------------
executor_session_write codex '{"session_id":"session-test","usable":true,"review":true,"lane":false}'
check "an open surface reads on" "$(executor_session_on codex review && echo on || echo off)" "on"
check "a closed surface reads off" "$(executor_session_on codex lane && echo on || echo off)" "off"
check "an absent executor reads off" "$(executor_session_on stub lane && echo on || echo off)" "off"

# --- mark_off writes the record the gate reads back ------------------------
executor_session_write codex '{"session_id":"session-test","usable":true,"review":true,"lane":true,"plugin_version":"1.0.3"}'
executor_session_mark_off codex quota
rec="$TMP/codex/session-test.json"
check "mark_off clears usable" "$(jq -r '.usable' "$rec")" "false"
check "mark_off clears every surface in the registry" \
  "$(jq -r '[.review, .lane] | join(",")' "$rec")" "false,false"
check "mark_off records the reason" "$(jq -r '.reason' "$rec")" "quota"
check "mark_off records the session id" "$(jq -r '.session_id' "$rec")" "session-test"
check "mark_off stamps checked_at" "$(jq -r '.checked_at | test("^[0-9]{4}-")' "$rec")" "true"
check "mark_off writes both reset fields present and null" \
  "$(jq -r '[has("resets_at"), has("resets_at_epoch"), .resets_at, .resets_at_epoch] | map(tostring) | join(",")' "$rec")" "true,true,null,null"
check "mark_off preserves plugin_version" "$(jq -r '.plugin_version' "$rec")" "1.0.3"

# --- no cross-talk ---------------------------------------------------------
executor_session_write stub '{"session_id":"session-test","usable":true,"lane":true}'
executor_session_mark_off codex quota
check "marking one executor off leaves another untouched" \
  "$(executor_session_on stub lane && echo on || echo off)" "on"
executor_session_write stub '{"session_id":"session-test","usable":true,"lane":true,"stub_version":"0.0.0-stub"}'
executor_session_mark_off stub quota
check "mark_off keeps an executor's own version field" \
  "$(jq -r '[.stub_version, (.plugin_version | tostring), .reason] | join(",")' "$TMP/stub/session-test.json")" "0.0.0-stub,null,quota"

# --- no session id ---------------------------------------------------------
check "without a session id the file call fails" \
  "$(CLAUDE_CODE_SESSION_ID= ; executor_session_file codex >/dev/null 2>&1; echo $?)" "1"
check "without a session id a surface reads off" \
  "$(CLAUDE_CODE_SESSION_ID= ; executor_session_on codex review && echo on || echo off)" "off"

# --- reset times and the fallback mark -------------------------------------
FAR=4070908800 FAR_ISO=2099-01-01T00:00:00Z
srec="$TMP/stub/session-test.json"
executor_session_write stub '{"session_id":"session-test","usable":true,"lane":true,"reason":"ok"}'
executor_session_mark_off stub quota "$FAR"
check "mark_off with a reset epoch records it as a number" \
  "$(jq -r '.resets_at_epoch | type' "$srec")/$(jq -r '.resets_at_epoch' "$srec")" "number/$FAR"
check "mark_off with a reset epoch records it in ISO 8601 UTC" "$(jq -r '.resets_at' "$srec")" "$FAR_ISO"
executor_session_mark_off stub quota ""
check "mark_off with an empty reset writes both reset fields null" \
  "$(jq -r '[.resets_at, .resets_at_epoch] | map(tostring) | join(",")' "$srec")" "null,null"
executor_session_mark_off stub quota 99999999999999999999
check "mark_off with a reset past 18 digits writes both reset fields null" \
  "$(jq -r '[.resets_at, .resets_at_epoch] | map(tostring) | join(",")' "$srec")" "null,null"

executor_session_write stub '{"session_id":"session-test","usable":true,"lane":true,"reason":"ok","stub_version":"0.0.0-stub"}'
executor_session_mark_fallback_off stub "$FAR"
check "mark_fallback_off leaves usable, lane, reason and versions alone" \
  "$(jq -r '[.usable, .lane, .reason, .stub_version] | map(tostring) | join(",")' "$srec")" "true,true,ok,0.0.0-stub"
check "mark_fallback_off writes the fallback object" \
  "$(jq -c '.fallback' "$srec")" "{\"usable\":false,\"reason\":\"quota\",\"resets_at\":\"$FAR_ISO\",\"resets_at_epoch\":$FAR}"
executor_session_mark_off stub quota
check "a lane mark_off keeps the fallback object" "$(jq -r '.fallback.resets_at_epoch' "$srec")" "$FAR"
executor_session_write stub '{"session_id":"session-test","usable":true,"lane":true,"reason":"ok"}'
check "a write without a fallback key keeps the prior fallback object" "$(jq -r '.fallback.reason' "$srec")" "quota"
executor_session_write stub '{"session_id":"session-test","usable":true,"lane":true,"reason":"ok","fallback":null}'
check "a write with fallback null drops the object" "$(jq -r 'has("fallback")' "$srec")" "false"
executor_session_mark_fallback_off stub ""
check "mark_fallback_off with no reset writes both reset fields null" \
  "$(jq -c '.fallback' "$srec")" '{"usable":false,"reason":"quota","resets_at":null,"resets_at_epoch":null}'
rm -f "$srec"
executor_session_mark_fallback_off stub "$FAR"
check "mark_fallback_off with no prior file writes the session id and the mark" \
  "$(jq -r '[.session_id, .fallback.reason, (.usable | tostring)] | join(",")' "$srec")" "session-test,quota,null"
rm -f "$srec"
check "mark_fallback_off without a session id succeeds" \
  "$(CLAUDE_CODE_SESSION_ID= executor_session_mark_fallback_off stub "$FAR"; echo $?)" "0"
check "mark_fallback_off without a session id writes no file" "$([ -e "$srec" ] && echo yes || echo no)" "no"

# --- pruning ---------------------------------------------------------------
touch -d '8 days ago' "$TMP/codex/ancient.json" 2>/dev/null || touch -t 200001010000 "$TMP/codex/ancient.json"
executor_session_write codex '{"session_id":"session-test","usable":true}'
check "a week-old session file is pruned on write" \
  "$([ -f "$TMP/codex/ancient.json" ] && echo kept || echo pruned)" "pruned"

# A malformed entry is an installation fault, so the helper's diagnostic must
# reach the caller rather than being swallowed into a mute lane shutdown.
mkdir -p "$TMP/bad"
printf 'not json\n' > "$TMP/bad/codex.json"
check "a malformed entry still fails closed" \
  "$(DR_EXECUTORS_DIR="$TMP/bad" executor_session_file codex >/dev/null 2>&1; echo $?)" "1"
check "a malformed entry says why on stderr" \
  "$(DR_EXECUTORS_DIR="$TMP/bad" executor_session_file codex 2>&1 >/dev/null | head -1 | tr -d '\r')" \
  "executors: codex: missing or malformed required fields"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
