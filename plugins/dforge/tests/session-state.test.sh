#!/usr/bin/env bash
# lib/session-state.sh: the cockpit's per-session state file, read with its
# validity rules, each rejection logged once per turn.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
export HOME="$TMP/home" MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR
git init -q "$TMP/repo" && cd "$TMP/repo" || exit 1
. "$HERE/../scripts/lib/in-flight.sh"
. "$HERE/../scripts/lib/session-state.sh"
SD="$HOME/.claude/dforge/sessions/state" TD="$HOME/.claude/dforge/sessions/turns"
mkdir -p "$SD" "$TD"
LOG="$TMP/repo/.dforge/session-state.log"
ms() { echo $(( ($(date +%s) - ${1:-0}) * 1000 )); } # ms [SECONDS_AGO]
state() { # state SID UPDATED_MS [PARTIAL] [SESSION]
  jq -nc --arg s "${4:-$1}" --argjson u "$2" --argjson p "${3:-false}" --argjson at "$(ms)" \
    '{session:$s, updated:$u, window:200000, model:"claude-x", partial:$p,
      launches:[{id:"b1", kind:"shell", what:"Dev server", command:"npm run dev", startedAt:$at, outputFile:"", service:true, timer:false}]}' > "$SD/$1.json"
}
touch -d '-60 seconds' "$TD/s-1"

check "the file name is the sanitised id" "$(ss_file 'a:b')" "$SD/a-b.json"
state s-1 "$(ms)"
check "window" "$(ss_window s-1)" "200000"
check "model" "$(ss_model s-1)" "claude-x"
check "launches: six fields with the service role" "$(ss_launches s-1 | cut -f1,2,4,5,6)" $'shell\tb1\tidle -\tDev server\tservice'

state s-1 "$(ms 120)"
ss_launches s-1 >/dev/null; rc=$?
check "launches older than the turn stamp are stale" "$rc" "1"
check "the window stays valid for the same session" "$(ss_window s-1)" "200000"
ss_launches s-1 >/dev/null
check "a rejection is logged once per turn" "$(grep -c $'\ts-1\tlaunches\tstale$' "$LOG")" "1"

state s-1 "$(ms)" true
ss_launches s-1 >/dev/null; rc=$?
check "partial launches are rejected" "$rc:$(grep -c $'\tlaunches\tpartial$' "$LOG")" "1:1"

state s-1 "$(ms)" false s-other
ss_window s-1 >/dev/null; rc=$?
check "another session's file is rejected" "$rc:$(grep -c $'\twindow\tsession mismatch$' "$LOG")" "1:1"

printf 'not json\n' > "$SD/s-1.json"
ss_window s-1 >/dev/null; rc=$?
check "an unparseable file is rejected" "$rc:$(grep -c $'\twindow\tunparseable$' "$LOG")" "1:1"

ss_window s-9 >/dev/null; rc=$?
check "a missing file is rejected" "$rc:$(grep -c $'\ts-9\twindow\tmissing$' "$LOG")" "1:1"

state s-2 "$(ms)"
ss_launches s-2 >/dev/null; rc=$?
check "no turn stamp: launches are stale" "$rc" "1"

state s-old "$(ms)"; touch -d '-31 days' "$SD/s-old.json"
ss_prune
check "prune: a file older than 30 days goes, a newer one stays" \
  "$([ -e "$SD/s-old.json" ] && echo kept || echo gone) $([ -e "$SD/s-2.json" ] && echo kept || echo gone)" "gone kept"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
