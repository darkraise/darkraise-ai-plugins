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

# --- the shipped agy entry -----------------------------------------------------
check "the shipped registry lists agy before codex" \
  "$(bash "$EXEC" list | tr '\n' ' ')" "agy codex "
check "the shipped registry ranks agy before codex" \
  "$(bash "$EXEC" ranked | tr '\n' ' ')" "agy codex "
check "the shipped agy entry has priority 10" "$(bash "$EXEC" get agy priority)" "10"
check "the shipped agy entry names the real locator" \
  "$(bash "$EXEC" get agy locator)" "scripts/agy-locate"
check "the shipped agy entry names its gate" "$(bash "$EXEC" get agy gate)" "scripts/agy-gate"
check "the shipped agy entry names its wrapper" \
  "$(bash "$EXEC" get agy wrapper)" "scripts/run-agy-task.sh"
check "the shipped agy entry names its session directory" \
  "$(bash "$EXEC" get agy session_dir)" "agy-sessions"
check "the shipped agy entry names its session directory override" \
  "$(bash "$EXEC" get agy session_dir_env)" "DR_AGY_SESSION_DIR"
check "the shipped agy entry opens only the lane" \
  "$(bash "$EXEC" get agy surfaces | tr '\n' ',')" "lane,"
check "the shipped agy entry declares no missing reason" \
  "$(bash "$EXEC" get agy reasons.missing >/dev/null 2>&1; echo $?)" "1"
for key in locator probe.command gate wrapper; do
  check "the shipped agy $key resolves to a real file" \
    "$([ -f "$(bash "$EXEC" path agy "$key")" ] && echo yes || echo no)" "yes"
done
for key in gate assignment successor timeout; do
  block=$(bash "$EXEC" get agy "blocks.$key")
  check "the shipped agy $key block exists in the ladder" \
    "$(grep -cx "\`\`\`$block" "$P/reference/ladder.md")" "1"
done

# --- ranked ------------------------------------------------------------------
# Priority decides which executor planning tries first. A malformed value must
# neither drop the entry nor abort the listing: it ranks as if absent, with one
# line on stderr.
mkdir -p "$TMP/rank"
rentry() { # rentry <id> [priority as a JSON literal]; no second argument leaves priority out
  jq -n --arg id "$1" --arg p "${2-}" '{id:$id, locator:"scripts/x-plugin",
    probe:{command:"scripts/lib/x-client.mjs", op:"auth"},
    wrapper:"scripts/run-x-task.sh", session_dir:($id + "-sessions"),
    surfaces:["lane"], blocks:{gate:"gate"}}
    + (if $p == "" then {} else {priority: ($p | fromjson)} end)' > "$TMP/rank/$1.json"
}
rentry alpha 20; rentry beta 10; rentry aardvark 10; rentry eta 0
rentry lambda 9; rentry theta 100
rentry gamma; rentry delta '"x"'; rentry epsilon -1; rentry zeta 1.5

check "ranked orders by ascending priority, numerically, ties by id, then the unranked by id" \
  "$(run "$TMP/rank" ranked 2>/dev/null | tr '\n' ' ')" \
  "eta lambda aardvark beta alpha theta delta epsilon gamma zeta "
check "ranked exits 0" "$(run "$TMP/rank" ranked >/dev/null 2>&1; echo $?)" "0"
check "ranked reports each invalid priority once on stderr and nothing else" \
  "$(run "$TMP/rank" ranked 2>&1 >/dev/null | sort | tr '\n' '|')" \
  "executors: delta: priority is not a non-negative integer|executors: epsilon: priority is not a non-negative integer|executors: zeta: priority is not a non-negative integer|"
# The edge literals are written verbatim, not through jq, which may reformat 1.0.
mkdir -p "$TMP/rank-edge"
edge() { # edge <id> <priority literal>
  printf '{"id":"%s","locator":"scripts/x-plugin","probe":{"command":"scripts/lib/x-client.mjs","op":"auth"},"wrapper":"scripts/run-x-task.sh","session_dir":"%s-sessions","surfaces":["lane"],"blocks":{"gate":"gate"},"priority":%s}\n' \
    "$1" "$1" "$2" > "$TMP/rank-edge/$1.json"
}
edge one 1.0; edge two 2; edge nul null
check "priority 1.0 is an integer and ranks; null ranks as absent" \
  "$(run "$TMP/rank-edge" ranked 2>/dev/null | tr '\n' ' ')" "one two nul "
check "only the null priority is reported" \
  "$(run "$TMP/rank-edge" ranked 2>&1 >/dev/null | tr '\n' '|')" "executors: nul: priority is not a non-negative integer|"
check "ranked takes no argument" "$(run "$TMP/rank" ranked extra >/dev/null 2>&1; echo $?)" "2"
check "list ignores priority and stays silent about it" \
  "$(run "$TMP/rank" list 2>&1 | tr '\n' ' ')" \
  "aardvark alpha beta delta epsilon eta gamma lambda theta zeta "
check "a registry without priorities ranks by id" "$(run "$TMP/reg" ranked | tr '\n' ' ')" "alpha beta "
check "an empty registry ranks nothing and still exits 0" "$(run "$TMP/empty" ranked; echo "rc=$?")" "rc=0"
check "ranked skips a malformed entry like list does" \
  "$(printf 'not json\n' > "$TMP/reg/broken.json"; run "$TMP/reg" ranked 2>/dev/null | tr '\n' ' '; rm -f "$TMP/reg/broken.json")" "alpha beta "
check "the shipped codex entry carries priority 20" "$(bash "$EXEC" get codex priority)" "20"
check "the shipped registry ranks codex" "$(bash "$EXEC" ranked | grep -cx codex)" "1"

# --- usage -----------------------------------------------------------------
check "no arguments is a usage error" "$(bash "$EXEC" >/dev/null 2>&1; echo $?)" "2"
check "an unknown subcommand is a usage error" "$(bash "$EXEC" frobnicate >/dev/null 2>&1; echo $?)" "2"

# --- the shipped test fixture registry --------------------------------------
FIX="$HERE/fixtures/executors"
check "the fixture registry lists three ids" \
  "$(run "$FIX" list | tr '\n' ' ')" "codex opencode stub "
check "the fixture codex entry matches the shipped one" \
  "$(diff -q "$FIX/codex.json" "$P/reference/executors/codex.json" >/dev/null && echo same || echo differs)" "same"
check "the stub locator is executable" \
  "$([ -x "$FIX/bin/stub-plugin" ] && echo yes || echo no)" "yes"
check "the stub locator emits the ok grammar" \
  "$(bash "$FIX/bin/stub-plugin" | sed 's/root=.*/root=X/')" "stub-plugin ok version=0.0.0-stub root=X"
check "the stub locator exits 0 when ok" "$(bash "$FIX/bin/stub-plugin" >/dev/null; echo $?)" "0"
check "the stub locator can report off" \
  "$(STUB_LOCATOR=off bash "$FIX/bin/stub-plugin")" "stub-plugin off reason=plugin-not-enabled"
check "the stub locator exits 1 when off" \
  "$(STUB_LOCATOR=off bash "$FIX/bin/stub-plugin" >/dev/null; echo $?)" "1"
check "the stub probe answers authed" \
  "$(printf '{"op":"auth","cwd":"."}' | node "$FIX/bin/stub-probe.mjs" x | jq -r '.authed')" "true"
check "the stub probe can answer logged out" \
  "$(printf '{"op":"auth","cwd":"."}' | STUB_PROBE=logged-out node "$FIX/bin/stub-probe.mjs" x | jq -r '.authed')" "false"
check "the stub probe can fail without an authed field" \
  "$(printf '{"op":"auth","cwd":"."}' | STUB_PROBE=throw node "$FIX/bin/stub-probe.mjs" x | jq -r '.authed // "absent"')" "absent"
check "the fixture registry ranks the prioritised codex entry before the unranked ones" \
  "$(run "$FIX" ranked | tr '\n' ' ')" "codex opencode stub "

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
