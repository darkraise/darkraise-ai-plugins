#!/usr/bin/env bash
# The selection rule and the outcome policy are the two things a review seat
# gets wrong silently: a wrong model still produces a review, and a failed run
# still produces a file. Both are asserted here against a stub Codex plugin, so
# no model call is made and every branch is reachable.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/run-codex-review.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The runner marks this session's Codex gate file off on a quota error. A fixed
# session id and a temporary directory keep the machine's real file out of it.
export DR_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=codex-review-test

# The runner resolves its plugin root through scripts/codex-plugin, which reads
# the profile settings and the policy file. Both are fixtures here, and
# CLAUDE_PROJECT_DIR is cleared because the locator also reads a project's own
# .claude/settings*.json - without this a run under Claude Code reads this
# repository's settings.
STUB_PLUGIN="$HERE/fixtures/stub-codex-plugin"
export STUB_MODE=ok
export CLAUDE_PROJECT_DIR=
export CLAUDE_CONFIG_DIR="$TMP/config"
mkdir -p "$CLAUDE_CONFIG_DIR/plugins"
printf '{"enabledPlugins":{"codex@openai-codex":true}}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
jq -nc --arg p "$STUB_PLUGIN" \
  '{version:2, plugins:{"codex@openai-codex":[{scope:"user", installPath:$p, version:"1.0.3"}]}}' \
  > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
export DR_CODEX_POLICY="$TMP/policy.json"
jq -nc '{plugin:"codex@openai-codex", versions:["1.0.3"],
         trust:{calibration:"pending", smoke:"pending"}}' > "$DR_CODEX_POLICY"

# A fixture ladder, because the shipped codex-judge rows bound a run at 1800
# seconds and the timeout case would wait out half an hour against them. The
# rows and their order are the shipped ones; only the seconds differ.
export CODEX_REVIEW_LADDER="$TMP/ladder.md"
fence='```'
{ printf '%scodex-judge\n' "$fence"
  printf 'gpt-6-astra high 2\n'
  printf 'gpt-5.6-sol high 2\n'
  printf '%s\n' "$fence"; } > "$CODEX_REVIEW_LADDER"

# --kind final composes its own prompt from `git diff <base>...HEAD`, so the
# work tree has to be a real repository with the base branch present. One empty
# commit is enough: the diff may be empty, and the runner only needs the compose
# to succeed.
mkdir -p "$TMP/work"
git -C "$TMP/work" init -q -b main
git -C "$TMP/work" -c user.email=t@example.invalid -c user.name=t \
  commit -q --allow-empty -m base

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <haystack> <needle>
  case "$2" in
    *"$3"*) printf 'ok   - %s\n' "$1"; pass=$((pass + 1)) ;;
    *) printf 'FAIL - %s\n       missing: [%s]\n' "$1" "$3"; fail=$((fail + 1)) ;;
  esac
}

mkdir -p "$TMP/bin" "$TMP/codexhome" "$TMP/work"
BASH_BIN=$(command -v bash)
for dep in jq timeout head tr sed awk grep cat mktemp rm; do
  printf '#!%s\nexec "%s" "$@"\n' "$BASH_BIN" "$(command -v "$dep")" > "$TMP/bin/$dep"
  chmod +x "$TMP/bin/$dep"
done

# A stub roster, so selection is tested without probing the real machine.
write_roster() { # write_roster
  cat > "$TMP/bin/detect-stub" <<STUB
#!$BASH_BIN
cat <<'JSON'
[{"id":"codex","present":true,"path":"/stub/codex","version":"codex-cli 0.153.4",
  "authed":true,"auth_status":"authenticated","batch_capable":true,"usable":true,
  "reason":null}]
JSON
STUB
  chmod +x "$TMP/bin/detect-stub"
}

# A stub session gate. Every case sees a usable Codex unless it sets
# GATE_STUB_LINE or GATE_STUB_EXIT.
cat > "$TMP/gate-stub" <<STUB
#!$BASH_BIN
printf '%s\n' "\${GATE_STUB_LINE:-codex-gate usable=true reason=ok review=true lane=true resets_at=- source=cache}"
exit "\${GATE_STUB_EXIT:-0}"
STUB

run() { # run <args...>; STUB_* variables in the environment script the stub
  printf '0' > "$TMP/calls"
  : > "$TMP/events.log"
  PATH="$TMP/bin:$PATH" CODEX_REVIEW_ROSTER="$TMP/bin/detect-stub" \
    CODEX_REVIEW_GATE="$TMP/gate-stub" CODEX_REVIEW_LADDER="$CODEX_REVIEW_LADDER" \
    CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" CLAUDE_PROJECT_DIR= \
    DR_CODEX_POLICY="$DR_CODEX_POLICY" \
    STUB_CALL_FILE="$TMP/calls" STUB_EVENT_LOG="$TMP/events.log" \
    "$BASH_BIN" "$SCRIPT" "$@" 2>"$TMP/err"
}

check "script exists" "$([ -f "$SCRIPT" ] && echo yes || echo no)" "yes"

# --- selection ---------------------------------------------------------------
write_roster
out=$(run --kind final --cwd "$TMP/work" --out "$TMP/o.md" --base main --dry-run)
req_of() { sed -n '2p' <<<"$1"; } # req_of <dry-run output>; echoes the request JSON
present "the heavy tier selects astra" "$out" "codex-judge gpt-6-astra/high"
present "dry run reports OK" "$out" "status=OK"
present "dry run reports no catalog evidence" "$out" "evidence=none"
r=$(req_of "$out")
check "final: prints a turn request" "$(jq -r '.op' <<<"$r")" "turn"
check "final: carries the selected model" "$(jq -r '.model' <<<"$r")" "gpt-6-astra"
check "final: carries the selected effort" "$(jq -r '.effort' <<<"$r")" "high"
check "final: sends no base field" "$(jq -r 'has("base")' <<<"$r")" "false"
check "final: read-only sandbox" "$(jq -r '.sandbox' <<<"$r")" "read-only"
check "final: deadline in milliseconds" "$(jq -r '.deadlineMs > 0' <<<"$r")" "true"

# --- the two kinds differ ----------------------------------------------------
write_roster
printf 'prompt text\n' > "$TMP/p.txt"
out=$(run --kind risk3 --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run)
r=$(req_of "$out")
check "risk3: carries a schema path" \
  "$(jq -r '.schemaPath' <<<"$r" | grep -c 'codex-review-schema.json')" "1"
check "risk3: read-only sandbox" "$(jq -r '.sandbox' <<<"$r")" "read-only"
# risk3 is the sub-project 7 name for the task seat, normalised to task before
# the request is built, so that is the kind the client sees.
check "risk3: the kind reaches the request" "$(jq -r '.kind' <<<"$r")" "task"

# The unusable branch has its own status line and must still be parseable.
cat > "$TMP/bin/detect-stub" <<STUB
#!$BASH_BIN
cat <<'JSON'
[{"id":"codex","present":true,"path":null,"version":null,"authed":false,
  "auth_status":"logged_out","batch_capable":true,"usable":false,
  "reason":"present but not authenticated; run codex login"}]
JSON
STUB
chmod +x "$TMP/bin/detect-stub"
out=$(run --kind final --cwd "$TMP/work" --out "$TMP/o.md" --base main --dry-run); rc=$?
present "an unusable codex is FAILED" "$out" "status=FAILED"
present "the unusable status line keeps the model/effort shape" "$out" "codex-judge none/none"
check "an unusable codex exits 1" "$rc" "1"

# --- usage errors are exit 2, before any call --------------------------------
run --kind risk3 --cwd "$TMP/work" --out "$TMP/o.json" --dry-run >/dev/null; rc=$?
check "risk3 without --prompt is a usage error" "$rc" "2"
run --kind final --cwd "$TMP/work" --out "$TMP/o.md" --dry-run >/dev/null; rc=$?
check "final without --base is a usage error" "$rc" "2"
run --kind bogus --cwd "$TMP/work" --out "$TMP/o.md" --base main --dry-run >/dev/null; rc=$?
check "an unknown kind is a usage error" "$rc" "2"

# --- the outcome policy ------------------------------------------------------
seat() { # seat <kind> <extra-args...>; STUB_* in the environment scripts the stub
  rm -f "$TMP"/o.md* "$TMP"/o.json*
  local k="$1"; shift
  run --kind "$k" --cwd "$TMP/work" "$@"
}

write_roster

out=$(seat final --out "$TMP/o.md" --base main); rc=$?
present "a complete run with output is OK" "$out" "status=OK"
check "OK exits 0" "$rc" "0"

out=$(STUB_EMPTY=1 seat final --out "$TMP/o.md" --base main); rc=$?
present "an empty report is FAILED" "$out" "status=FAILED"
check "FAILED exits 1" "$rc" "1"

out=$(STUB_EMPTY=1 seat final --out "$TMP/o.md" --base main)
present "no report at all is FAILED" "$out" "status=FAILED"

out=$(STUB_FINAL_MESSAGE='{"spec_verdict":"met","task_quality":18,"cannot_verify":[]}'   seat risk3 --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "a schema-shaped risk3 report is OK" "$out" "status=OK"

out=$(seat risk3 --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "risk3 output that is not schema-shaped is FAILED" "$out" "status=FAILED"

out=$(STUB_MODE=hang seat final --out "$TMP/o.md" --base main); rc=$?
present "a run past its deadline is TIMEOUT, never a model change" "$out" "status=TIMEOUT"
check "TIMEOUT exits 1" "$rc" "1"
check "TIMEOUT does not run a second seat" "$(cat "$TMP/calls")" "1"

out=$(STUB_REFUSE_ONCE=1 seat final --out "$TMP/o.md" --base main); rc=$?
present "a refused model falls back once" "$out" "status=FALLBACK"
present "the fallback line names the model that ran" "$out" "codex-judge gpt-5.6-sol/high"
check "FALLBACK exits 0" "$rc" "0"
check "the fallback runs exactly one extra seat" "$(cat "$TMP/calls")" "2"

out=$(STUB_MODE=refusal seat final --out "$TMP/o.md" --base main)
present "a fallback that also fails is FAILED" "$out" "status=FAILED"
check "the fallback is attempted at most once" "$(cat "$TMP/calls")" "2"

# A failed turn whose prose merely mentions a refusal is classified from the
# result's own error field, so it is not a refusal and never falls back.
out=$(STUB_TURN_STATUS=1 STUB_FINAL_MESSAGE='the diff mentions an unsupported model'   seat final --out "$TMP/o.md" --base main)
present "prose that mentions a refusal is not a refusal" "$out" "status=FAILED"
check "a prose mention runs no second seat" "$(cat "$TMP/calls")" "1"

out=$(STUB_MODE=logged-out seat final --out "$TMP/o.md" --base main)
present "an auth failure is FAILED, not a model change" "$out" "status=FAILED"
check "an auth failure runs no second seat" "$(cat "$TMP/calls")" "1"

# A client-side throw is not a capability signal.
out=$(STUB_MODE=throw seat final --out "$TMP/o.md" --base main)
present "a thrown turn is FAILED, not a model change" "$out" "status=FAILED"
check "a thrown turn runs no second seat" "$(cat "$TMP/calls")" "1"

# The refusal has to survive into the fallback run, because the ledger quotes it.
# It travels in the result's own stderr field now and reaches the runner's
# message rather than a log file.
STUB_REFUSE_ONCE=1 seat final --out "$TMP/o.md" --base main >/dev/null
check "the refusal is quoted before the fallback runs"   "$(grep -c 'refused (.*); falling back to gpt-5.6-sol/high' "$TMP/err")" "1"
check "both seats ran, preferred rung first"   "$(awk '/^runAppServerTurn/{print $2}' "$TMP/events.log" | tr '
' ',')"   "gpt-6-astra/high,gpt-5.6-sol/high,"
check "no seat ever reaches a review entry point"   "$(grep -c 'runAppServerReview' "$TMP/events.log")" "0"

# --- task and plan kinds, and the light tier ---------------------------------
write_roster
out=$(run --kind task --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run)
r=$(req_of "$out")
check "task: passes the task-review schema"   "$(jq -r '.schemaPath' <<<"$r" | grep -c 'codex-review-schema.json')" "1"
present "task defaults to the heavy tier" "$out" "codex-judge gpt-6-astra/high"

out=$(run --kind task --tier light --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run)
present "the light tier selects the last judge row" "$out" "codex-judge gpt-5.6-sol/high"
present "the light tier reports no catalog evidence" "$out" "evidence=none"

out=$(run --kind risk3 --tier light --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run)
present "risk3 accepts the light tier" "$out" "codex-judge gpt-5.6-sol/high"

out=$(run --kind plan --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run)
r=$(req_of "$out")
check "plan: passes the plan-review schema"   "$(jq -r '.schemaPath' <<<"$r" | grep -c 'codex-plan-review-schema.json')" "1"
check "plan: read-only sandbox" "$(jq -r '.sandbox' <<<"$r")" "read-only"
present "plan takes the heavy selection" "$out" "codex-judge gpt-6-astra/high"

run --kind task --cwd "$TMP/work" --out "$TMP/o.json" --dry-run >/dev/null; rc=$?
check "task without --prompt is a usage error" "$rc" "2"
run --kind plan --cwd "$TMP/work" --out "$TMP/o.json" --dry-run >/dev/null; rc=$?
check "plan without --prompt is a usage error" "$rc" "2"
run --kind plan --tier light --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run >/dev/null; rc=$?
check "--tier with plan is a usage error" "$rc" "2"
run --kind final --tier light --cwd "$TMP/work" --out "$TMP/o.md" --base main --dry-run >/dev/null; rc=$?
check "--tier with final is a usage error" "$rc" "2"
run --kind task --tier medium --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run >/dev/null; rc=$?
check "an unknown tier is a usage error" "$rc" "2"

out=$(STUB_FINAL_MESSAGE='{"executability":17,"coherence":16,"coverage":17,"assumptions":16,"findings":[]}'   seat plan --out "$TMP/o.json" --prompt "$TMP/p.txt"); rc=$?
present "a schema-shaped plan report is OK" "$out" "status=OK"
check "a plan OK exits 0" "$rc" "0"
out=$(STUB_FINAL_MESSAGE='{"spec_verdict":"met","task_quality":18,"cannot_verify":[]}'   seat plan --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "a task-shaped report is not a plan review" "$out" "status=FAILED"
out=$(STUB_FINAL_MESSAGE='{"spec_verdict":"met","task_quality":18,"cannot_verify":[]}'   seat task --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "a schema-shaped task report is OK" "$out" "status=OK"
out=$(STUB_MODE=refusal seat task --tier light --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "a refused light run is FAILED" "$out" "status=FAILED"
check "the light tier never falls back" "$(cat "$TMP/calls")" "1"

# --- the session gate and the quota ------------------------------------------
write_roster
OFF='codex-gate usable=false reason=quota review=false lane=false resets_at=2026-09-20T10:03:27Z source=cache'
calls() { cat "$TMP/calls" 2>/dev/null || echo 0; }

out=$(GATE_STUB_LINE="$OFF" seat task --out "$TMP/o.json" --prompt "$TMP/p.txt"); rc=$?
check "an unusable gate prints the unusable line" "$out" "codex-judge none/none status=FAILED exit=0 out=$TMP/o.json evidence=none"
check "an unusable gate exits 1" "$rc" "1"
check "an unusable gate runs no codex" "$(calls)" "0"
present "the runner names the gate's reason" "$(cat "$TMP/err")" "run-codex-review: codex is off for this session (quota)"

out=$(GATE_STUB_LINE="$OFF" seat final --out "$TMP/o.md" --base main --dry-run); rc=$?
present "a dry run is gated too" "$out" "codex-judge none/none status=FAILED"
check "a gated dry run exits 1" "$rc" "1"
case "$out" in
  *would-run*) printf 'FAIL - a gated dry run prints no command\n'; fail=$((fail + 1)) ;;
  *) printf 'ok   - a gated dry run prints no command\n'; pass=$((pass + 1)) ;;
esac
out=$(GATE_STUB_LINE="$OFF" seat risk3 --out "$TMP/o.json" --prompt "$TMP/p.txt"); rc=$?
present "risk3 is gated too" "$out" "codex-judge none/none status=FAILED"
check "a gated risk3 runs no codex" "$(calls)" "0"

out=$(GATE_STUB_EXIT=2 seat final --out "$TMP/o.md" --base main); rc=$?
present "a gate that exits non-zero is refused, whatever it printed" "$out" "codex-judge none/none status=FAILED"
check "a refused gate exits 1" "$rc" "1"
check "a refused gate runs no codex" "$(calls)" "0"

out=$(GATE_STUB_LINE='codex-gate usable=true reason=ok review=false lane=false resets_at=- source=probe' \
  run --kind plan --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run)
present "an untrusted review surface still runs: the runner reads usable only" "$out" "codex-judge gpt-6-astra/high status=OK"

SFILE="$DR_CODEX_SESSION_DIR/codex-review-test.json"
open_session() {
  mkdir -p "$DR_CODEX_SESSION_DIR"
  printf '{"session_id":"codex-review-test","usable":true,"review":true,"lane":true,"reason":"ok","plugin_version":"1.0.3"}\n' > "$SFILE"
}
open_session
out=$(STUB_MODE=quota seat task --out "$TMP/o.json" --prompt "$TMP/p.txt"); rc=$?
present "a quota error is FAILED on the model that ran" "$out" "codex-judge gpt-6-astra/high status=FAILED exit=1"
check "a quota error exits 1" "$rc" "1"
check "a quota error is never a refusal: no second seat" "$(calls)" "1"
check "a quota error turns Codex off for the session" \
  "$(jq -r '[.usable, .review, .lane, .reason] | map(tostring) | join("/")' "$SFILE" | tr -d '\r')" "false/false/false/quota"
check "the marked-off file keeps the plugin version" "$(jq -r '.plugin_version' "$SFILE" | tr -d '\r')" "1.0.3"

open_session
out=$(STUB_REFUSE_ONCE=1 STUB_SECOND_MODE=quota seat final --out "$TMP/o.md" --base main); rc=$?
present "a quota error on the fallback run is FAILED" "$out" "codex-judge gpt-5.6-sol/high status=FAILED exit=1"
check "the quota fallback ran exactly one extra seat" "$(calls)" "2"
check "a quota error on the fallback run turns Codex off" "$(jq -r '.usable | tostring' "$SFILE" | tr -d '\r')" "false"

open_session
STUB_TURN_STATUS=1 STUB_FINAL_MESSAGE='the diff mentions an unsupported model'   seat final --out "$TMP/o.md" --base main >/dev/null
check "an ordinary failure leaves the session on" "$(jq -r '.usable | tostring' "$SFILE" | tr -d '\r')" "true"

# The caller must defer to the runner's outcome rather than running its own
# retry rule: a FAILED seat that redispatches turns one refused run into two.
SDD="$HERE/../reference/delegated-task.md"
sdd=$(cat "$SDD")
present "the risk-3 caller names the runner" "$sdd" "run-codex-review.sh"
present "the risk-3 caller defers on FAILED" "$sdd" "TIMEOUT or FAILED"
# Needle must be unique to the new text: SKILL.md's recovery table already
# carries a bare "never re-dispatch", so a shorter needle would pass untouched.
present "the risk-3 caller does not redispatch a decided seat" "$sdd" "never re-dispatch the Codex seat"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
