#!/usr/bin/env bash
# The registry is the one place an executor is described. A malformed entry
# must not remove every other executor from the roster: that is the silent
# downgrade detect-executors.sh was already written to avoid, and it is why
# list skips bad entries rather than failing.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
EXEC="$P/scripts/executors"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
run() { DR_EXECUTORS_DIR="$1" bash "$EXEC" "${@:2}"; }

mkdir -p "$TMP/reg"
entry() { # entry <id> [extra jq assignment]
  jq -n --arg id "$1" '{id:$id, locator:"scripts/x-plugin",
    probe:{command:"scripts/lib/x-client.mjs", op:"auth"},
    wrapper:"scripts/run-x-task.sh", session_dir:($id + "-sessions"),
    surfaces:["lane"], blocks:{gate:"gate"}}' > "$TMP/reg/$1.json"
}
entry alpha
entry beta

check "script exists" "$([ -f "$EXEC" ] && echo yes || echo no)" "yes"

# --- list ------------------------------------------------------------------
check "list names every valid entry, sorted" "$(run "$TMP/reg" list | tr '\n' ' ')" "alpha beta "
check "list exits 0" "$(run "$TMP/reg" list >/dev/null; echo $?)" "0"
check "an empty directory lists nothing and still exits 0" \
  "$(mkdir -p "$TMP/empty"; run "$TMP/empty" list; echo "rc=$?")" "rc=0"

# --- get and path ----------------------------------------------------------
check "get reads a top-level field" "$(run "$TMP/reg" get alpha id)" "alpha"
check "get reads a dotted key" "$(run "$TMP/reg" get alpha probe.op)" "auth"
check "get prints an array one element per line" \
  "$(run "$TMP/reg" get alpha surfaces | tr '\n' ',')" "lane,"
check "get on an unknown id exits 1" "$(run "$TMP/reg" get nope id >/dev/null 2>&1; echo $?)" "1"
check "get on an unknown key exits 1" "$(run "$TMP/reg" get alpha nope >/dev/null 2>&1; echo $?)" "1"
check "path resolves against the plugin root" \
  "$(run "$TMP/reg" path alpha locator)" "$(cd "$P" && pwd)/scripts/x-plugin"
check "path takes a dotted key too" \
  "$(run "$TMP/reg" path alpha probe.command)" "$(cd "$P" && pwd)/scripts/lib/x-client.mjs"

# --- invalid entries are skipped, never fatal ------------------------------
# Each case keeps alpha and beta valid, so the assertion proves the bad entry
# was dropped rather than that the whole listing collapsed.
printf 'not json\n' > "$TMP/reg/broken.json"
check "malformed JSON is skipped" "$(run "$TMP/reg" list 2>/dev/null | tr '\n' ' ')" "alpha beta "
check "malformed JSON still exits 0" "$(run "$TMP/reg" list >/dev/null 2>&1; echo $?)" "0"
check "malformed JSON is reported on stderr" \
  "$(run "$TMP/reg" list 2>&1 >/dev/null | grep -c 'broken')" "1"
rm -f "$TMP/reg/broken.json"

jq -n '{id:"missing", locator:"scripts/x"}' > "$TMP/reg/missing.json"
check "a missing required field is skipped" "$(run "$TMP/reg" list 2>/dev/null | tr '\n' ' ')" "alpha beta "
rm -f "$TMP/reg/missing.json"

entry gamma; jq '.id = "delta"' "$TMP/reg/gamma.json" > "$TMP/x" && mv "$TMP/x" "$TMP/reg/gamma.json"
check "an id that disagrees with its filename is skipped" \
  "$(run "$TMP/reg" list 2>/dev/null | tr '\n' ' ')" "alpha beta "
rm -f "$TMP/reg/gamma.json"

# A separate directory: NTFS is case-insensitive, so writing Alpha.json beside
# alpha.json overwrites it, and the assertion would then pass for the wrong
# reason.
mkdir -p "$TMP/case"
jq -n '{id:"Alpha", locator:"a", probe:{command:"b", op:"auth"}, wrapper:"c",
        session_dir:"d", surfaces:["lane"], blocks:{gate:"gate"}}' > "$TMP/case/Alpha.json"
jq -n '{id:"zeta", locator:"a", probe:{command:"b", op:"auth"}, wrapper:"c",
        session_dir:"d", surfaces:["lane"], blocks:{gate:"gate"}}' > "$TMP/case/zeta.json"
check "an id outside the pattern is skipped" \
  "$(run "$TMP/case" list 2>/dev/null | tr '\n' ' ')" "zeta "

# --- the shipped entry -----------------------------------------------------
check "the shipped registry lists codex" \
  "$(bash "$EXEC" list | grep -cx codex)" "1"
check "the shipped codex entry names the real locator" \
  "$(bash "$EXEC" get codex locator)" "scripts/codex-plugin"
check "the shipped codex entry keeps the ladder block named gate" \
  "$(bash "$EXEC" get codex blocks.gate)" "gate"
check "the shipped codex entry keeps the session directory" \
  "$(bash "$EXEC" get codex session_dir)" "codex-sessions"
check "the shipped codex entry keeps the session directory override" \
  "$(bash "$EXEC" get codex session_dir_env)" "DR_CODEX_SESSION_DIR"
check "the shipped codex entry opens both surfaces" \
  "$(bash "$EXEC" get codex surfaces | tr '\n' ',')" "review,lane,"
check "the shipped codex entry names its wrapper" \
  "$(bash "$EXEC" get codex wrapper)" "scripts/run-codex-task.sh"
check "the shipped codex locator resolves to a real file" \
  "$([ -f "$(bash "$EXEC" path codex locator)" ] && echo yes || echo no)" "yes"
check "the shipped codex probe resolves to a real file" \
  "$([ -f "$(bash "$EXEC" path codex probe.command)" ] && echo yes || echo no)" "yes"

# --- usage -----------------------------------------------------------------
check "no arguments is a usage error" "$(bash "$EXEC" >/dev/null 2>&1; echo $?)" "2"
check "an unknown subcommand is a usage error" "$(bash "$EXEC" frobnicate >/dev/null 2>&1; echo $?)" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
