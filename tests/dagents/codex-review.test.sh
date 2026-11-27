#!/usr/bin/env bash
# The selection rule and the outcome policy are the two things a review seat
# gets wrong silently: a wrong model still produces a review, and a failed run
# still produces a file. Both are asserted here against a stub Codex plugin, so
# no model call is made and every branch is reachable.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../plugins/dagents/scripts/run-codex-review.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The runner marks this session's Codex gate file off on a quota error. A fixed
# session id and a temporary directory keep the machine's real file out of it.
export DAGENTS_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=codex-review-test

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
export DAGENTS_CODEX_POLICY="$TMP/policy.json"
jq -nc '{plugin:"codex@openai-codex", min_version:"1.0.3", max_major:1,
         trust:{calibration:"pending", smoke:"pending"}}' > "$DAGENTS_CODEX_POLICY"

# A fixture ladder, because the shipped codex-judge rows bound a run at 1800
# seconds and the timeout case would wait out half an hour against them. The
# rows and their order are the shipped ones; only the seconds differ.
export CODEX_REVIEW_LADDER="$TMP/ladder.md"
fence='```'
{ printf '%scodex-judge\n' "$fence"
  printf 'gpt-6-astra high 2\n'
  printf 'gpt-6.1-sol high 2\n'
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

# A stub session gate. Every case sees a usable Codex unless it sets
# GATE_STUB_LINE or GATE_STUB_EXIT.
# A --refresh call is the probe after a quota error: GATE_STUB_REFRESH_EPOCH has
# it record that reset, GATE_STUB_REFRESH_LINE prints that line, and with
# neither it prints nothing and fails. Each call's arguments go to gate.args.
cat > "$TMP/gate-stub" <<STUB
#!$BASH_BIN
printf '%s\n' "\$*" >> "$TMP/gate.args"
if [ "\${1:-}" = --refresh ]; then
  if [ -n "\${GATE_STUB_REFRESH_EPOCH:-}" ]; then
    printf '{"session_id":"codex-review-test","usable":false,"review":false,"lane":false,"reason":"quota","resets_at":"2100-01-01T00:00:00Z","resets_at_epoch":%s}\n' "\$GATE_STUB_REFRESH_EPOCH" > "$DAGENTS_CODEX_SESSION_DIR/\$CLAUDE_CODE_SESSION_ID.json"
    printf 'codex-gate usable=false reason=quota review=false lane=false resets_at=2100-01-01T00:00:00Z source=probe\n'
    exit 0
  fi
  [ -n "\${GATE_STUB_REFRESH_LINE:-}" ] || exit 1
  printf '%s\n' "\$GATE_STUB_REFRESH_LINE"
  exit 0
fi
printf '%s\n' "\${GATE_STUB_LINE:-codex-gate usable=true reason=ok review=true lane=true resets_at=- source=cache}"
exit "\${GATE_STUB_EXIT:-0}"
STUB

run() { # run <args...>; STUB_* variables in the environment script the stub
  printf '0' > "$TMP/calls"
  : > "$TMP/events.log"
  : > "$TMP/gate.args"
  PATH="$TMP/bin:$PATH" CODEX_REVIEW_GATE="$TMP/gate-stub" CODEX_REVIEW_LADDER="$CODEX_REVIEW_LADDER" \
    CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" CLAUDE_PROJECT_DIR= \
    DAGENTS_CODEX_POLICY="$DAGENTS_CODEX_POLICY" \
    STUB_CALL_FILE="$TMP/calls" STUB_EVENT_LOG="$TMP/events.log" \
    "$BASH_BIN" "$SCRIPT" "$@" 2>"$TMP/err"
}

check "script exists" "$([ -f "$SCRIPT" ] && echo yes || echo no)" "yes"

# --- term_reaps_group: a TERM to the runner's group reaps the client too ---
if command -v setsid >/dev/null 2>&1; then
  { printf '%scodex-judge\n' "$fence"; printf 'gpt-6-astra high 120\ngpt-6.1-sol high 120\n'; printf '%s\n' "$fence"; } > "$TMP/ladder-long.md"
  : > "$TMP/stub.pid"; printf '0' > "$TMP/calls"; printf 'review this\n' > "$TMP/tp.txt"
  PATH="$TMP/bin:$PATH" CODEX_REVIEW_GATE="$TMP/gate-stub" CODEX_REVIEW_LADDER="$TMP/ladder-long.md" \
    CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" CLAUDE_PROJECT_DIR= DAGENTS_CODEX_POLICY="$DAGENTS_CODEX_POLICY" \
    STUB_MODE=hang STUB_PID_FILE="$TMP/stub.pid" STUB_CALL_FILE="$TMP/calls" STUB_EVENT_LOG="$TMP/term.log" \
    setsid "$BASH_BIN" "$SCRIPT" --kind task --cwd "$TMP/work" --out "$TMP/term.json" --prompt "$TMP/tp.txt" >/dev/null 2>&1 &
  rpid=$!
  for _ in $(seq 1 100); do [ -s "$TMP/stub.pid" ] && break; sleep 0.1; done
  npid=$(cat "$TMP/stub.pid"); tpid=$(ps -o ppid= -p "$npid" 2>/dev/null | tr -d ' ')
  kill -TERM -- "-$rpid" 2>/dev/null
  for _ in $(seq 1 100); do { kill -0 "$npid" || kill -0 "$tpid"; } 2>/dev/null || break; sleep 0.1; done
  check "term_reaps_group" "$(kill -0 "$npid" 2>/dev/null && echo alive || echo gone):$(kill -0 "$tpid" 2>/dev/null && echo alive || echo gone)" "gone:gone"
  kill -KILL "$npid" "$tpid" 2>/dev/null; wait "$rpid" 2>/dev/null
else
  printf 'skip - term_reaps_group\n'
fi

# --- native_request_paths: cwd and schemaPath in the form cygpath -m gives ---
mkdir -p "$TMP/cyg"
printf '#!/usr/bin/env bash\n[ "$1" = -m ] && shift\nprintf "C:/stub%%s\\n" "$1"\n' > "$TMP/cyg/cygpath"
chmod +x "$TMP/cyg/cygpath"
printf 'review this\n' > "$TMP/np.txt"
r=$(PATH="$TMP/cyg:$PATH"; run --kind task --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/np.txt" --dry-run | sed -n 2p)
check "native_request_paths" "$(jq -r '.cwd' <<<"$r" | tr -d '\r')|$(jq -r '.schemaPath | startswith("C:/stub")' <<<"$r" | tr -d '\r')" \
  "C:/stub$(cd "$TMP/work" && pwd)|true"

# --- selection ---------------------------------------------------------------
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
printf 'prompt text\n' > "$TMP/p.txt"
out=$(run --kind task --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run)
r=$(req_of "$out")
check "task: carries a schema path" \
  "$(jq -r '.schemaPath' <<<"$r" | grep -c 'codex-review-schema.json')" "1"
check "task: read-only sandbox" "$(jq -r '.sandbox' <<<"$r")" "read-only"
check "task: the kind reaches the request" "$(jq -r '.kind' <<<"$r")" "task"

# --- usage errors are exit 2, before any call --------------------------------
run --kind risk3 --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run >/dev/null; rc=$?
check "the retired risk3 kind is a usage error" "$rc" "2"
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

out=$(seat final --out "$TMP/o.md" --base main); rc=$?
present "a complete run with output is OK" "$out" "status=OK"
check "OK exits 0" "$rc" "0"

out=$(STUB_EMPTY=1 seat final --out "$TMP/o.md" --base main); rc=$?
present "an empty report is FAILED" "$out" "status=FAILED"
check "FAILED exits 1" "$rc" "1"

out=$(STUB_EMPTY=1 seat final --out "$TMP/o.md" --base main)
present "no report at all is FAILED" "$out" "status=FAILED"

out=$(STUB_FINAL_MESSAGE='{"spec":18,"scope":18,"verification":18,"quality":18,"spec_verdict":"compliant","task_quality":"approved","findings":[],"cannot_verify":[]}'   seat task --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "a schema-shaped task report is OK" "$out" "status=OK"

out=$(seat task --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "task output that is not schema-shaped is FAILED" "$out" "status=FAILED"

# A reviewer that read nothing still answers in the schema: every score 1 and
# no finding to justify any of them.
UNREAD_TASK='{"spec":1,"scope":1,"verification":1,"quality":1,"spec_verdict":"issues","task_quality":"needs_fixes","findings":[],"cannot_verify":["the diff was not read"]}'
out=$(STUB_FINAL_MESSAGE="$UNREAD_TASK" seat task --out "$TMP/o.json" --prompt "$TMP/p.txt"); rc=$?
present "an unread task review is FAILED" "$out" "status=FAILED"
check "an unread task review exits 1" "$rc" "1"
present "an unread task review says it read nothing" "$(cat "$TMP/err")" "read nothing"
out=$(STUB_FINAL_MESSAGE='{"executability":1,"coherence":1,"coverage":1,"assumptions":1,"findings":[]}' seat plan --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "an unread plan review is FAILED" "$out" "status=FAILED"
out=$(STUB_FINAL_MESSAGE='{"spec":1,"scope":1,"verification":1,"quality":1,"spec_verdict":"issues","task_quality":"needs_fixes","findings":[{"severity":"Critical","file":"a.sh","line":3,"summary":"x"}],"cannot_verify":[]}' seat task --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "all scores 1 with a finding is a review" "$out" "status=OK"
out=$(STUB_FINAL_MESSAGE='{"spec":2,"scope":1,"verification":1,"quality":1,"spec_verdict":"issues","task_quality":"needs_fixes","findings":[],"cannot_verify":[]}' seat task --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "one score above 1 without findings is a review" "$out" "status=OK"

out=$(STUB_MODE=hang seat final --out "$TMP/o.md" --base main); rc=$?
present "a run past its deadline is TIMEOUT, never a model change" "$out" "status=TIMEOUT"
check "TIMEOUT exits 1" "$rc" "1"
check "TIMEOUT does not run a second seat" "$(cat "$TMP/calls")" "1"

# A client that never answers, its event loop blocked, is stopped by the outer
# timeout: that is a TIMEOUT too, not an error.
out=$(CODEX_REVIEW_GRACE=1 STUB_MODE=wedge seat final --out "$TMP/o.md" --base main)
check "outer_kill_is_timeout" "$out" "codex-judge gpt-6-astra/high status=TIMEOUT exit=124 out=$TMP/o.md evidence=none"

out=$(STUB_REFUSE_ONCE=1 seat final --out "$TMP/o.md" --base main); rc=$?
present "a refused model falls back once" "$out" "status=FALLBACK"
present "the fallback line names the model that ran" "$out" "codex-judge gpt-6.1-sol/high"
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

out=$(STUB_FINAL_MESSAGE=$' \n\t ' seat final --out "$TMP/o.md" --base main)
present "blank_final_is_schema" "$out" "status=FAILED exit=0 out=$TMP/o.md evidence=none"

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
check "the refusal is quoted before the fallback runs"   "$(grep -c 'refused (.*); falling back to gpt-6.1-sol/high' "$TMP/err")" "1"
check "both seats ran, preferred rung first"   "$(awk '/^runAppServerTurn/{print $2}' "$TMP/events.log" | tr '
' ',')"   "gpt-6-astra/high,gpt-6.1-sol/high,"
check "no seat ever reaches a review entry point"   "$(grep -c 'runAppServerReview' "$TMP/events.log")" "0"

# Malformed structured output must fail on both the preferred and fallback seats.
valid_task='{"spec":18,"scope":18,"verification":18,"quality":18,"spec_verdict":"compliant","task_quality":"approved","findings":[],"cannot_verify":[]}'
valid_plan='{"executability":18,"coherence":18,"coverage":18,"assumptions":18,"findings":[]}'
for kind in task plan; do
  if [ "$kind" = task ]; then valid=$valid_task; score=spec; else valid=$valid_plan; score=coverage; fi
  for mutation in 'del(.findings)' ".${score}=0" ".${score}=21" ".${score}=1.5" ".${score}=\"18\"" '.findings={}' '.findings=[{}]' '.extra=true' 'null'; do
    report=$(jq -c "$mutation" <<<"$valid")
    out=$(STUB_FINAL_MESSAGE="$report" seat "$kind" --out "$TMP/o.json" --prompt "$TMP/p.txt"); rc=$?
    present "$kind rejects $mutation" "$out" 'status=FAILED'
    check "$kind invalid report exits 1" "$rc" 1
  done
  out=$(STUB_FINAL_MESSAGE="$valid $valid" seat "$kind" --out "$TMP/o.json" --prompt "$TMP/p.txt")
  present "$kind rejects multiple reports" "$out" 'status=FAILED'
done
for mutation in '.spec_verdict="met"' '.task_quality=18' '.cannot_verify=[42]' '.findings=[{"severity":"bad","file":"x","line":1,"summary":"x"}]' '.findings=[{"severity":"Minor","file":"x","line":"1","summary":"x"}]'; do
  report=$(jq -c "$mutation" <<<"$valid_task")
  out=$(STUB_FINAL_MESSAGE="$report" seat task --out "$TMP/o.json" --prompt "$TMP/p.txt")
  present "task rejects $mutation" "$out" 'status=FAILED'
done
out=$(STUB_REFUSE_ONCE=1 STUB_FINAL_MESSAGE='{}' seat task --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "malformed fallback is FAILED" "$out" 'status=FAILED'
present "the malformed report came from the fallback seat" "$out" "codex-judge gpt-6.1-sol/high status=FAILED"
out=$(STUB_REFUSE_ONCE=1 STUB_FINAL_MESSAGE="$UNREAD_TASK" seat task --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "an unread fallback review is FAILED" "$out" "codex-judge gpt-6.1-sol/high status=FAILED"

# --- task and plan kinds, and the light tier ---------------------------------
out=$(run --kind task --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run)
r=$(req_of "$out")
check "task: passes the task-review schema"   "$(jq -r '.schemaPath' <<<"$r" | grep -c 'codex-review-schema.json')" "1"
present "task defaults to the heavy tier" "$out" "codex-judge gpt-6-astra/high"

out=$(run --kind task --tier light --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run)
present "the light tier selects the last judge row" "$out" "codex-judge gpt-6.1-sol/high"
present "the light tier reports no catalog evidence" "$out" "evidence=none"

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
out=$(STUB_FINAL_MESSAGE='{"spec":18,"scope":18,"verification":18,"quality":18,"spec_verdict":"compliant","task_quality":"approved","findings":[],"cannot_verify":[]}'   seat plan --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "a task-shaped report is not a plan review" "$out" "status=FAILED"
out=$(STUB_FINAL_MESSAGE='{"spec":18,"scope":18,"verification":18,"quality":18,"spec_verdict":"compliant","task_quality":"approved","findings":[],"cannot_verify":[]}'   seat task --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "a schema-shaped task report is OK" "$out" "status=OK"
out=$(STUB_MODE=refusal seat task --tier light --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "a refused light run is FAILED" "$out" "status=FAILED"
check "the light tier never falls back" "$(cat "$TMP/calls")" "1"

# --- the session gate and the quota ------------------------------------------
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

out=$(GATE_STUB_EXIT=2 seat final --out "$TMP/o.md" --base main); rc=$?
present "a gate that exits non-zero is refused, whatever it printed" "$out" "codex-judge none/none status=FAILED"
check "a refused gate exits 1" "$rc" "1"
check "a refused gate runs no codex" "$(calls)" "0"

out=$(GATE_STUB_LINE='codex-gate usable=true reason=ok review=false lane=false resets_at=- source=probe' \
  run --kind plan --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run)
present "an untrusted review surface still runs: the runner reads usable only" "$out" "codex-judge gpt-6-astra/high status=OK"

SFILE="$DAGENTS_CODEX_SESSION_DIR/codex-review-test.json"
open_session() {
  mkdir -p "$DAGENTS_CODEX_SESSION_DIR"
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
present "a quota error on the fallback run is FAILED" "$out" "codex-judge gpt-6.1-sol/high status=FAILED exit=1"
check "the quota fallback ran exactly one extra seat" "$(calls)" "2"
check "a quota error on the fallback run turns Codex off" "$(jq -r '.usable | tostring' "$SFILE" | tr -d '\r')" "false"

# --- quota_records_reset: the gate's probe records the reset ---
open_session
GATE_STUB_REFRESH_EPOCH=4102444800 STUB_MODE=quota seat task --out "$TMP/o.json" --prompt "$TMP/p.txt" >/dev/null
check "quota_records_reset" "$(jq -r '.resets_at_epoch' "$SFILE" | tr -d '\r')" "4102444800"
check "quota_records_reset: the gate is probed once" "$(grep -c '^--refresh$' "$TMP/gate.args")" "1"

# --- quota_probe_says_usable: a probe that finds Codex usable leaves it on ---
open_session
GATE_STUB_REFRESH_LINE='codex-gate usable=true reason=ok review=true lane=true resets_at=- source=probe' \
  STUB_MODE=quota seat task --out "$TMP/o.json" --prompt "$TMP/p.txt" >/dev/null
check "quota_probe_says_usable" "$(jq -r '.usable | tostring' "$SFILE" | tr -d '\r')" "true"

open_session
STUB_TURN_STATUS=1 STUB_FINAL_MESSAGE='the diff mentions an unsupported model'   seat final --out "$TMP/o.md" --base main >/dev/null
check "an ordinary failure leaves the session on" "$(jq -r '.usable | tostring' "$SFILE" | tr -d '\r')" "true"

# --- quota_skip_in_run: an auto run of session s1 in the work tree ---
RUNSTATE="$TMP/work/.dagents/sdd/auto-run.json"
mkdir -p "$(dirname "$RUNSTATE")"
jq -n '{active: true, session: "s1", phase: "execute", decisions: [], rulings: []}' > "$RUNSTATE"
open_session
CLAUDE_CODE_SESSION_ID=s1 STUB_MODE=quota seat task --out "$TMP/o.json" --prompt "$TMP/p.txt" >/dev/null
check "quota_skip_in_run: a quota failure records a five-hour codex skip" \
  "$(jq -c '[.reviewSkips[] | [.family, .kind, (.until - .failedAt)]]' "$RUNSTATE")" '[["codex","quota",18000]]'
open_session
out=$(CLAUDE_CODE_SESSION_ID=s1 seat task --out "$TMP/o.json" --prompt "$TMP/p.txt"); rc=$?
check "quota_skip_in_run: called again within the window it is SKIPPED" "$out" \
  "codex-judge none/none status=SKIPPED exit=0 out=- evidence=none reason=quota-skip"
check "quota_skip_in_run: and exits 1 without launching" "$rc:$(calls)" "1:0"
jq '.reviewSkips[0].until = 1' "$RUNSTATE" > "$RUNSTATE.tmp" && mv "$RUNSTATE.tmp" "$RUNSTATE"
out=$(CLAUDE_CODE_SESSION_ID=s1 seat task --out "$TMP/o.json" --prompt "$TMP/p.txt")
check "quota_skip_in_run: after the window it launches again" "$(grep -c SKIPPED <<<"$out"):$(calls)" "0:1"
jq -n '{active: true, session: "s1", phase: "execute", decisions: [], rulings: []}' > "$RUNSTATE"
open_session
CLAUDE_CODE_SESSION_ID=s1 GATE_STUB_REFRESH_EPOCH=4102444800 STUB_MODE=quota seat task --out "$TMP/o.json" --prompt "$TMP/p.txt" >/dev/null
check "quota_records_reset: the run's skip lasts until the reset" "$(jq -c '[.reviewSkips[] | [.family, .until]]' "$RUNSTATE")" '[["codex",4102444800]]'
rm -rf "$TMP/work/.dagents"
open_session
CLAUDE_CODE_SESSION_ID=s1 STUB_MODE=quota seat task --out "$TMP/o.json" --prompt "$TMP/p.txt" >/dev/null
check "quota_skip_in_run: outside an auto run a quota failure writes no state" "$(ls -A "$TMP/work/.dagents/sdd" 2>/dev/null | grep -c auto-run)" "0"

# --- prompt_says_headless: the prompt the CLI gets opens with the opening line ---
printf 'review this\n' > "$TMP/hp.txt"
hp_sum=$(cksum < "$TMP/hp.txt")
STUB_PROMPT_LOG="$TMP/sent-prompt" seat task --out "$TMP/o.json" --prompt "$TMP/hp.txt" >/dev/null
check "prompt_says_headless: the prompt sent opens with the opening line" "$(head -n 1 "$TMP/sent-prompt" 2>/dev/null)" \
  "this sandbox is read-only: read each file this prompt names with a shell command such as cat; nothing can be written"
check "prompt_says_headless: and carries the --prompt text after it" "$(tail -n 1 "$TMP/sent-prompt" 2>/dev/null)" "review this"
check "prompt_says_headless: the --prompt file is unchanged" "$(cksum < "$TMP/hp.txt")" "$hp_sum"
STUB_PROMPT_LOG="$TMP/sent-final" seat final --out "$TMP/o.md" --base main >/dev/null
check "prompt_says_headless: a composed final prompt opens with it too" "$(head -n 1 "$TMP/sent-final" 2>/dev/null)" \
  "this sandbox is read-only: read each file this prompt names with a shell command such as cat; nothing can be written"

# --- failures_book_total: a seat that ran and failed books the run's total ---
mkdir -p "$(dirname "$RUNSTATE")"
jq -n '{active: true, session: "s1", phase: "execute", decisions: [], rulings: []}' > "$RUNSTATE"
pf() { jq -r '.totals.panelFailures // 0' "$RUNSTATE"; }
open_session
CLAUDE_CODE_SESSION_ID=s1 STUB_EMPTY=1 seat final --out "$TMP/o.md" --base main >/dev/null
check "failures_book_total: a FAILED seat adds one" "$(pf)" "1"
CLAUDE_CODE_SESSION_ID=s1 STUB_MODE=hang seat final --out "$TMP/o.md" --base main >/dev/null
check "failures_book_total: a TIMEOUT seat adds one" "$(pf)" "2"
CLAUDE_CODE_SESSION_ID=s1 seat final --out "$TMP/o.md" --base main >/dev/null
check "failures_book_total: an OK seat adds nothing" "$(pf)" "2"
CLAUDE_CODE_SESSION_ID=s1 GATE_STUB_LINE="$OFF" seat final --out "$TMP/o.md" --base main >/dev/null
check "failures_book_total: a gate-off seat ran nothing and adds nothing" "$(pf)" "2"
CLAUDE_CODE_SESSION_ID=s2 STUB_EMPTY=1 seat final --out "$TMP/o.md" --base main >/dev/null
check "failures_book_total: another session's failure adds nothing" "$(pf)" "2"
rm -rf "$TMP/work/.dagents"

# --- unwritable_out_fails: a report that cannot be written is no review ---
rm -rf "$TMP"/odir.md*; mkdir -p "$TMP/odir.md"
out=$(run --kind final --cwd "$TMP/work" --out "$TMP/odir.md" --base main)
present "unwritable_out_fails" "$out" "status=FAILED exit=0 out=$TMP/odir.md evidence=none"
present "unwritable_out_fails: the failed write is named" "$(cat "$TMP/err")" "cannot write the report: $TMP/odir.md"
rm -rf "$TMP"/odir.md*

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
