#!/usr/bin/env bash
# The agy gate decides whether a session may hand tasks to Antigravity, so every
# way it can say no is asserted here against the stub agy under
# fixtures/stub-agy. No case starts the real agy.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$(cd "$HERE/.." && pwd)"
STUBDIR="$(cd "$HERE/fixtures/stub-agy" && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# The gate reads ~/.dforge/config.json; a temporary home keeps the real one out.
export HOME="$TMP/home"
mkdir -p "$HOME" "$TMP/work"
unset CLAUDE_CONFIG_DIR

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
skip() { printf 'skip - %s\n' "$1"; }

# A PATH holding every tool the scripts use and no agy, so "not installed" does
# not depend on the host having none. Only the directories of the tools the
# scripts run are linked: on Windows the rest of PATH is System32.
SEAL="$TMP/seal"
mkdir -p "$SEAL"
while IFS= read -r dir; do
  for tool in "$dir"/*; do
    name=${tool##*/}
    case "$name" in agy|agy.exe) continue ;; esac
    [ -e "$SEAL/$name" ] || ln -s "$tool" "$SEAL/$name" 2>/dev/null
  done
done < <(for tool in bash node jq git cat date; do dirname "$(type -P "$tool")"; done | sort -u)
# A Chocolatey shim such as jq.exe finds its program from its own directory, so
# these run from where they are. The link goes first: writing to it would
# overwrite the program it names.
for tool in jq node git; do
  rm -f "$SEAL/$tool"
  printf '#!%s\nexec "%s" "$@"\n' "$BASH" "$(type -P "$tool")" > "$SEAL/$tool"
  chmod +x "$SEAL/$tool"
done

# Node cannot run a bash-script stub on Windows; the probe cases need it to.
SPAWNABLE=$(node -e 'const r = require("child_process").spawnSync(process.argv[1], ["--version"], { encoding: "utf8" }); console.log(r.status === 0 ? "yes" : "no")' "$STUBDIR/agy" 2>/dev/null | tr -d '\r')

POLICY="$TMP/policy.json"
jq '.trust.smoke = "pass"' "$P/reference/agy-policy.json" > "$POLICY" 2>/dev/null
HIGHFLOOR="$TMP/highfloor.json"
jq '.min_version = "1.5.0"' "$POLICY" > "$HIGHFLOOR" 2>/dev/null

# --- the stub itself ---------------------------------------------------------
# Tasks 4 to 7 drive the wrapper through this stub, so its own shapes are pinned.
check "the stub is executable" "$([ -x "$STUBDIR/agy" ] && echo yes || echo no)" "yes"
check "the stub prints its version" "$("$STUBDIR/agy" --version | tr -d '\r')" "1.4.12"
check "the stub lists two model ids after its banner" \
  "$("$STUBDIR/agy" models | tr -d '\r' | grep -c "$(printf '^[a-z0-9.-]*\t')")" "2"
check "the stub can be logged out" "$(STUB_AGY_AUTH=logged-out "$STUBDIR/agy" models >/dev/null 2>&1; echo $?)" "1"
check "the stub can be broken" "$(STUB_AGY_AUTH=broken "$STUBDIR/agy" models >/dev/null 2>&1; echo $?)" "3"
mkdir -p "$TMP/stubwork"
stub_out=$(cd "$TMP/stubwork" && STUB_AGY_ARGS_LOG="$TMP/stub-args.log" "$STUBDIR/agy" --model m -p hi)
check "a print call logs one line per argument then a separator" \
  "$(tr '\n' ' ' < "$TMP/stub-args.log")" "--model m -p hi -- "
check "a print call reports DONE with a conversation id" \
  "$(jq -r '[.structured_output.status, .conversation_id, (.usage.total_tokens | tostring)] | join(",")' <<<"$stub_out")" "DONE,conv-1,10"
check "a print call writes the file the done mode names" "$(tr -d '\r' < "$TMP/stubwork/out.txt")" "stub"
stub_out=$(cd "$TMP/stubwork" && STUB_AGY_MODE=error STUB_AGY_ERROR='quota exhausted' "$STUBDIR/agy" -p hi; echo "rc=$?")
check "the error mode prints status ERROR, the text and exit 1" \
  "$(jq -sR -r 'split("\n") | [(.[0] | fromjson | [.status, .error, .finished_reason] | join(",")), .[1]] | join(" ")' <<<"$stub_out")" \
  "ERROR,quota exhausted,error rc=1"
stub_out=$(cd "$TMP/stubwork" && STUB_AGY_MODE=print-timeout "$STUBDIR/agy" -p hi 2>"$TMP/stub-err"; echo "rc=$?")
check "the print-timeout mode succeeds with finished_reason print_timeout" \
  "$(head -1 <<<"$stub_out" | jq -r '[.status, .finished_reason] | join(",")') $(tail -1 <<<"$stub_out")" "SUCCESS,print_timeout rc=0"
check "the print-timeout mode writes the timeout line to stderr" \
  "$(grep -c 'print timeout after 5s with turn in progress' "$TMP/stub-err")" "1"

# --- the policy file ---------------------------------------------------------
check "the policy states the cli, the version floor, the major ceiling and the calibrated version" \
  "$(jq -r '[.cli, .min_version, (.max_major | tostring), .calibrated] | join(",")' "$P/reference/agy-policy.json" 2>/dev/null | tr -d '\r')" \
  "agy,1.4.12,1,1.4.12"
# Task 7 flips fail to pass in its own commit; either value is valid here.
check "the policy records the smoke gate as fail or pass" \
  "$(jq -r '.trust.smoke | if . == "fail" or . == "pass" then "valid" else . end' "$P/reference/agy-policy.json" 2>/dev/null | tr -d '\r')" "valid"

# --- the locator -------------------------------------------------------------
loc() { # loc [args...]; sets out and rc. LOC_PATH and LOC_POLICY override the defaults.
  out=$(cd "$TMP/work" && PATH="${LOC_PATH:-$STUBDIR:$SEAL}" DR_AGY_POLICY="${LOC_POLICY:-$POLICY}" \
    "$BASH" "$P/scripts/agy-locate" "$@" 2>"$TMP/err"); rc=$?
  out=${out//$'\r'/}
}
check "agy-locate exists" "$([ -f "$P/scripts/agy-locate" ] && echo yes || echo no)" "yes"
loc
check "an agy inside the range is ok, with its directory as root" "$out" "agy-locate ok version=1.4.12 root=$STUBDIR"
check "ok exits 0" "$rc" "0"
STUB_AGY_VERSION=1.9.3 loc
check "a minor above the floor is ok" "$out" "agy-locate ok version=1.9.3 root=$STUBDIR"
STUB_AGY_VERSION=1.4.11 loc
check "a version below the floor is off" "$out" "agy-locate off reason=plugin-version:1.4.11"
check "off exits 1" "$rc" "1"
STUB_AGY_VERSION=2.0.0 loc
check "a major above the ceiling is off" "$out" "agy-locate off reason=plugin-version:2.0.0"
STUB_AGY_VERSION=$'1.4.12\r' loc
check "a carriage return after the version is stripped" "$out" "agy-locate ok version=1.4.12 root=$STUBDIR"
STUB_AGY_VERSION=$'1.4.12\nsecond line' loc
check "only the first line of the version output counts" "$out" "agy-locate ok version=1.4.12 root=$STUBDIR"
LOC_POLICY="$HIGHFLOOR" loc
check "DR_AGY_POLICY replaces the policy path" "$out" "agy-locate off reason=plugin-version:1.4.12"
LOC_PATH="$SEAL" loc
check "no agy on PATH is not installed" "$out" "agy-locate off reason=plugin-not-installed"
check "not installed exits 1" "$rc" "1"
mkdir -p "$TMP/mute"
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/mute/agy"; chmod +x "$TMP/mute/agy"
LOC_PATH="$TMP/mute:$SEAL" loc
check "an agy that prints no version counts as not installed" "$out" "agy-locate off reason=plugin-not-installed"
loc extra
check "an argument is a usage error" "$rc" "2"

# --- the probe ----------------------------------------------------------------
probe() { # probe <root> [stdin json]; prints the authed value
  local in=${2-}; [ -n "$in" ] || in='{"op":"auth","cwd":"."}'
  printf '%s' "$in" | (cd "$TMP/work" && PATH="$STUBDIR:$SEAL" node "$P/scripts/lib/agy-probe.mjs" "$1" 2>/dev/null) \
    | tail -1 | tr -d '\r' | jq -r '.authed | tostring'
}
check "agy-probe.mjs exists" "$([ -f "$P/scripts/lib/agy-probe.mjs" ] && echo yes || echo no)" "yes"
if [ "$SPAWNABLE" = yes ]; then
  check "a clean exit listing a model id is authed" "$(probe "$STUBDIR")" "true"
  check "output asking for a sign-in is not authed" "$(STUB_AGY_AUTH=logged-out probe "$STUBDIR")" "false"
  check "a failure that asks for nothing is unknown" "$(STUB_AGY_AUTH=broken probe "$STUBDIR")" "null"
  mkdir -p "$TMP/empty-root"
  check "a root without agy falls back to agy on PATH" "$(probe "$TMP/empty-root")" "true"
  # Windows looks for a bare name in the working directory before PATH; a "."
  # entry on PATH does the same here, so an agy a project plants in its own
  # directory would run if the fallback ran there.
  mkdir -p "$TMP/planted" "$TMP/probe-tmp"
  printf '#!/usr/bin/env bash\n: > "%s"\nprintf "m\\tM\\n"\n' "$TMP/planted-ran" > "$TMP/planted/agy"
  chmod +x "$TMP/planted/agy"
  check "the PATH fallback does not run an agy in the request's cwd" \
    "$(jq -cn --arg cwd "$TMP/planted" '{op:"auth",cwd:$cwd}' \
      | PATH="$SEAL:." TMPDIR="$TMP/probe-tmp" node "$P/scripts/lib/agy-probe.mjs" "$TMP/empty-root" 2>/dev/null \
      | tail -1 | tr -d '\r' | jq -r '.authed | tostring') $([ -e "$TMP/planted-ran" ] && echo ran || echo not-run)" \
    "null not-run"
  check "an op other than auth answers null" "$(probe "$STUBDIR" '{"op":"quota","cwd":"."}')" "null"
  check "an op other than auth exits 2" \
    "$(printf '{"op":"quota","cwd":"."}' | PATH="$STUBDIR:$SEAL" node "$P/scripts/lib/agy-probe.mjs" "$STUBDIR" >/dev/null 2>&1; echo $?)" "2"
else
  skip "the probe cases: Node cannot run the bash-script stub on this platform"
fi

UNTRUSTED="$TMP/untrusted.json"
jq '.trust.smoke = "fail"' "$P/reference/agy-policy.json" > "$UNTRUSTED" 2>/dev/null

# --- the gate ------------------------------------------------------------------
REG="$TMP/reg"
mkdir -p "$REG"
jq -n '{id:"agy", locator:"scripts/agy-locate",
  probe:{command:"scripts/lib/agy-probe.mjs", op:"auth"},
  gate:"scripts/agy-gate", wrapper:"scripts/run-agy-task.sh",
  reference:"reference/executor-lane.md", session_dir:"agy-sessions",
  session_dir_env:"DR_AGY_SESSION_DIR", surfaces:["lane"], blocks:{gate:"agy-lane-gate"}}' > "$REG/agy.json"
SESS="$TMP/sessions"
ARGS="$TMP/args.log"
gate() { # gate [args...]; sets out and rc. GATE_PATH, GATE_POLICY and SID override the defaults.
  out=$(cd "$TMP/work" && PATH="${GATE_PATH:-$STUBDIR:$SEAL}" DR_AGY_POLICY="${GATE_POLICY:-$POLICY}" \
    DR_EXECUTORS_DIR="$REG" DR_AGY_SESSION_DIR="$SESS" CLAUDE_CODE_SESSION_ID="${SID-s1}" \
    STUB_AGY_ARGS_LOG="$ARGS" "$BASH" "$P/scripts/agy-gate" "$@" 2>"$TMP/err"); rc=$?
}
field() { jq -r ".$1 | tostring" "$SESS/s1.json" 2>/dev/null | tr -d '\r'; }
fresh() { rm -rf "$SESS" "$ARGS"; }
setting() { mkdir -p "$HOME/.dforge"; printf '%s\n' "$1" > "$HOME/.dforge/config.json"; }
mark_off() { (export DR_EXECUTORS_DIR="$REG" DR_AGY_SESSION_DIR="$SESS" CLAUDE_CODE_SESSION_ID=s1
  . "$P/scripts/lib/executor-session.sh"; executor_session_mark_off agy "$1"); }

check "agy-gate exists" "$([ -f "$P/scripts/agy-gate" ] && echo yes || echo no)" "yes"

fresh; GATE_PATH="$SEAL" gate
check "no agy on PATH turns the gate off" "$out" \
  "agy-gate usable=false reason=plugin-not-installed review=false lane=false resets_at=- source=probe"
check "the gate exits 0 when it answers" "$rc" "0"
fresh; STUB_AGY_VERSION=1.4.11 gate
check "a version out of range turns the gate off" "$out" \
  "agy-gate usable=false reason=plugin-version:1.4.11 review=false lane=false resets_at=- source=probe"
check "a version out of range never runs the auth probe" "$(grep -c '^models$' "$ARGS" 2>/dev/null)" "0"

# A quota mark needs no probe: the gate keeps it for the session, --refresh included.
fresh; mark_off quota
gate
check "a quota mark is reported from the session file" "$out" \
  "agy-gate usable=false reason=quota review=false lane=false resets_at=- source=cache"
gate --refresh
check "--refresh keeps a cached quota instead of probing it away" "$out" \
  "agy-gate usable=false reason=quota review=false lane=false resets_at=- source=cache"
check "keeping a quota starts no agy" "$([ -f "$ARGS" ] && echo yes || echo no)" "no"
check "the kept quota stays in the session file" "$(field usable)/$(field reason)" "false/quota"
SID=s2 gate
check "another session does not inherit the quota" \
  "$(case "$out" in *reason=quota*) echo inherited ;; *) echo own ;; esac)" "own"

fresh; GATE_POLICY="$TMP/none.json" gate
check "a missing policy file is a usage-level failure" "$rc" "2"
gate --bogus
check "an unknown flag is a usage error" "$rc" "2"
gate --refresh extra
check "an extra argument is a usage error" "$rc" "2"

setting '{"agyLane":false}'
fresh; gate
check "agyLane off answers without a probe" "$out" \
  "agy-gate usable=false reason=setting review=false lane=false resets_at=- source=setting"
check "agyLane off starts no agy" "$([ -f "$ARGS" ] && echo yes || echo no)" "no"
check "agyLane off is written for the readers" "$(field usable)/$(field reason)/$(field lane)" "false/setting/false"
setting '{}'

if [ "$SPAWNABLE" = yes ]; then
  fresh; gate
  check "a usable, trusted agy opens the lane" "$out" \
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- source=probe"
  check "the session file records the answer" \
    "$(field session_id)/$(field usable)/$(field review)/$(field lane)/$(field reason)/$(field agy_version)" "s1/true/false/true/ok/1.4.12"
  check "the session file carries no reset time" "$(field resets_at)/$(field resets_at_epoch)" "null/null"
  check "the probe ran once" "$(grep -c '^models$' "$ARGS")" "1"
  gate
  check "a second call answers from the cache" "$out" \
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- source=cache"
  check "a cached answer runs no agy" "$(grep -c '^models$' "$ARGS")" "1"
  GATE_POLICY="$UNTRUSTED" gate
  check "trust is read on every call, cache hit included" "$out" \
    "agy-gate usable=true reason=ok review=false lane=false resets_at=- source=cache"
  gate --refresh
  check "--refresh re-probes an ordinary cached answer" "$out" \
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- source=probe"
  check "the re-probe ran agy models again" "$(grep -c '^models$' "$ARGS")" "2"

  fresh; GATE_POLICY="$UNTRUSTED" gate
  check "a usable but untrusted agy opens no lane" "$out" \
    "agy-gate usable=true reason=ok review=false lane=false resets_at=- source=probe"

  fresh; STUB_AGY_AUTH=logged-out gate
  check "a logged-out agy is off" "$out" \
    "agy-gate usable=false reason=logged-out review=false lane=false resets_at=- source=probe"
  gate
  check "a cached logged-out answer is reused without --refresh" "$out" \
    "agy-gate usable=false reason=logged-out review=false lane=false resets_at=- source=cache"
  gate --refresh
  check "--refresh re-probes a logged-out answer and finds the login" "$out" \
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- source=probe"

  fresh; STUB_AGY_AUTH=broken gate
  check "an auth probe that answers nothing is probe-failed" "$out" \
    "agy-gate usable=false reason=probe-failed review=false lane=false resets_at=- source=probe"

  fresh; gate
  mark_off quota
  gate --refresh
  check "a quota mark made after a good probe also survives --refresh" "$out" \
    "agy-gate usable=false reason=quota review=false lane=false resets_at=- source=cache"
  check "the quota survives with the probe never re-run" "$(grep -c '^models$' "$ARGS")" "1"
  check "a quota mark keeps the recorded agy version" "$(field agy_version)" "1.4.12"

  fresh; STUB_AGY_VERSION='1.4.12 (build 7)' gate
  check "a version holding a space still opens the lane" "$out" \
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- source=probe"
  check "a version holding a space is recorded whole" "$(field agy_version)" "1.4.12 (build 7)"

  fresh; SID= gate
  check "no session id still answers, with the lane closed" "$out" \
    "agy-gate usable=true reason=ok review=false lane=false resets_at=- source=probe"
  check "no session id writes no file" "$(ls "$SESS" 2>/dev/null | wc -l | tr -d ' ')" "0"

  fresh; setting '{"agyLane":false}'; gate
  setting '{}'; gate
  check "switching agyLane back on probes again" "$out" \
    "agy-gate usable=true reason=ok review=false lane=true resets_at=- source=probe"
else
  skip "the gate cases that need a usable probe: Node cannot run the bash-script stub on this platform"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
