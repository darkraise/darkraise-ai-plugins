#!/usr/bin/env bash
# The Codex CLI validates neither the model nor the reasoning effort: it echoes
# any string into its banner and fails at the API, which bills for the round
# trip. Local validation is therefore the wrapper's job, and these tests are the
# only thing that proves it happens before a process is spawned.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/run-codex-task.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

mkdir -p "$TMP/work"
printf 'do the thing\n' > "$TMP/brief.md"

dry() { bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/report.md" \
          --cwd "$TMP/work" --dry-run "$@" 2>"$TMP/err"; }
rc_of() { dry "$@" >/dev/null; echo $?; }

check "script exists" "$([ -f "$SCRIPT" ] && echo yes || echo no)" "yes"
check "schema exists" "$([ -f "$HERE/../scripts/codex-report-schema.json" ] && echo yes || echo no)" "yes"
check "schema is valid JSON" \
  "$(jq -e . >/dev/null 2>&1 < "$HERE/../scripts/codex-report-schema.json" && echo yes || echo no)" "yes"
check "schema status enum matches the contract" \
  "$(jq -r '.properties.status.enum | sort | join(",")' < "$HERE/../scripts/codex-report-schema.json")" \
  "BLOCKED,DONE,NEEDS_CONTEXT"
# OpenAI strict structured output requires `required` to name every key in
# `properties`. A mismatch is rejected at request validation, so every real run
# would 400 while a stubbed suite stayed green.
check "schema required covers every property" \
  "$(jq -r '((.properties|keys)-(.required))|join(",")' \
      < "$HERE/../scripts/codex-report-schema.json")" ""
# The subtraction check above passes vacuously if `required` is missing
# outright: jq errors on "array and null cannot be subtracted", the command
# substitution captures nothing from stderr, and "" matches the expected "".
# This check closes that hole by asserting a required array exists at all.
check "schema declares a required array" \
  "$(jq -r 'if (.required|type) == "array" and (.required|length) > 0 then "ok" else "missing" end' \
      < "$HERE/../scripts/codex-report-schema.json")" "ok"

# --- validation happens before anything is spawned --------------------------
check "rejects a model absent from codex-assignment" "$(rc_of --model gpt-4o --effort medium)" "2"
check "rejects luna, which 400s on a ChatGPT account" "$(rc_of --model luna --effort medium)" "2"
check "rejects an invalid effort" "$(rc_of --model gpt-5.5 --effort minimal)" "2"
check "rejects a missing brief" \
  "$(bash "$SCRIPT" --brief "$TMP/nope.md" --report "$TMP/r.md" --cwd "$TMP/work" \
      --model gpt-5.5 --effort medium --dry-run >/dev/null 2>&1; echo $?)" "2"
check "accepts a valid rung" "$(rc_of --model gpt-5.5 --effort medium)" "0"

# --- the composed command line ----------------------------------------------
cmd=$(dry --model gpt-5.5 --effort medium)
for frag in "exec" "-C" "-s workspace-write" "-m gpt-5.5" \
            "model_reasoning_effort=medium" "--json" "--output-schema" "-o"; do
  check "dry run includes [$frag]" "$(grep -qF -- "$frag" <<<"$cmd" && echo yes || echo no)" "yes"
done
check "dry run never bypasses the sandbox" \
  "$(grep -qF -- "--dangerously-bypass" <<<"$cmd" && echo yes || echo no)" "no"

# --- timeouts come from the table unless overridden -------------------------
check "timeout defaults from codex-timeout" \
  "$(grep -qE '^timeout=900$' <<<"$cmd" && echo yes || echo no)" "yes"
# Captured into a variable first, not `dry ... | grep -q`: `grep -q` exits as
# soon as it matches the first ("timeout=...") line and closes its end of the
# pipe, and the wrapper's still-pending second `printf` (the "codex ..." line)
# can then hit SIGPIPE, making `dry` exit 141 under `pipefail` even though the
# match itself succeeded - reproduced directly at roughly a 50% rate.
check "explicit timeout wins" \
  "$(out=$(dry --model gpt-5.5 --effort medium --timeout 42); grep -qE '^timeout=42$' <<<"$out" && echo yes || echo no)" "yes"

# --- resume must re-send every per-invocation flag ---------------------------
# A bare `codex exec resume <id>` falls back to the user's config defaults, so a
# round-2 fix would silently run at a tier the ledger does not record.
res=$(dry --model gpt-5.5 --effort high --resume 01a0-thread)
check "resume names the subcommand" "$(grep -qF -- "resume" <<<"$res" && echo yes || echo no)" "yes"
check "resume carries the thread id" "$(grep -qF -- "01a0-thread" <<<"$res" && echo yes || echo no)" "yes"
check "resume re-sends the model" "$(grep -qF -- "-m gpt-5.5" <<<"$res" && echo yes || echo no)" "yes"
check "resume re-sends the effort" \
  "$(grep -qF -- "model_reasoning_effort=high" <<<"$res" && echo yes || echo no)" "yes"

# --- malformed input fails fast, and the dry run tells the truth ------------
check "a trailing flag with no value exits 2 rather than hanging" \
  "$(timeout 10 bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/report.md" \
      --cwd "$TMP/work" --model gpt-5.5 --effort medium --resume \
      >/dev/null 2>&1; echo $?)" "2"

check "rejects an unknown flag" "$(rc_of --model gpt-5.5 --effort medium --bogus x)" "2"
# Assert the message, not just the exit code: a multi-word effort already exited
# 2 before the fix, via an unrelated timeout-lookup miss. Only the message proves
# the effort check itself rejected it.
#
# Captured to a variable rather than piped straight into grep: the wrapper's own
# validation failure exits 2, and with `set -o pipefail` active in this suite, a
# direct `cmd 2>&1 >/dev/null | grep ...` pipeline reports cmd's exit code (2)
# instead of grep's match result, so the check would fail regardless of the
# message. Command substitution sidesteps that: only the text is captured.
msg=$(bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/report.md" \
      --cwd "$TMP/work" --model gpt-5.5 --effort 'medium high' --dry-run 2>&1 >/dev/null)
check "rejects a multi-word effort at the effort check, not downstream" \
  "$(grep -qF 'invalid reasoning effort' <<<"$msg" && echo yes || echo no)" "yes"

check "rejected input prints nothing on stdout" \
  "$(bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/report.md" \
      --cwd "$TMP/work" --model luna --effort medium --dry-run 2>/dev/null \
      | wc -c | tr -d ' \r\n')" "0"

# The dry run's contract is that it shows what would actually run, so re-parse
# what it printed and confirm a space-containing path survives as ONE argument.
mkdir -p "$TMP/dir with space"
printed=$(bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/report.md" \
  --cwd "$TMP/dir with space" --model gpt-5.5 --effort medium --dry-run 2>/dev/null | grep '^codex ')
eval "set -- $printed"
roundtrip=no
while [ $# -gt 0 ]; do
  if [ "$1" = "-C" ] && [ "${2:-}" = "$TMP/dir with space" ]; then roundtrip=yes; fi
  shift
done
check "dry run round-trips a space-containing path as one argument" "$roundtrip" "yes"

# --- execution against a stub codex -----------------------------------------
# No model is ever called. The stub writes the JSONL and last-message files a
# real run would produce, so commit behaviour and report shape are provable.
mkdir -p "$TMP/stub" "$TMP/repo"
git -C "$TMP/repo" init -q .
git -C "$TMP/repo" config user.email t@t.t
git -C "$TMP/repo" config user.name t
printf 'seed\n' > "$TMP/repo/seed.txt"
git -C "$TMP/repo" add -A
git -C "$TMP/repo" commit -qm seed

cat > "$TMP/stub/codex" <<'STUB'
#!/usr/bin/env bash
# Mimics `codex exec --json -o FILE`: JSONL on stdout, final message to -o.
out=""; cwd=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -C) cwd="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [ -n "${STUB_SLEEP:-}" ]; then
  sleep "$STUB_SLEEP" &
  sleeppid=$!
  # Exposes the real grandchild's own Windows pid so a test can prove it was
  # actually killed, not just that the wrapper returned before it finished.
  [ -n "${STUB_SLEEP_WINPID_FILE:-}" ] && cat "/proc/$sleeppid/winpid" 2>/dev/null > "$STUB_SLEEP_WINPID_FILE"
  wait "$sleeppid"
fi
printf '{"type":"thread.started","thread_id":"%s"}\n' "${STUB_THREAD:-th-001}"
printf '{"type":"item.completed"}\n'
# Content varies with the thread id so a later run actually diffs against an
# earlier run's commit; identical bytes on every call would make a "the tree
# is dirty" assertion unsatisfiable regardless of whether the wrapper is right.
[ -n "$cwd" ] && [ -z "${STUB_NO_WRITE:-}" ] && printf 'produced %s\n' "${STUB_THREAD:-th-001}" > "$cwd/produced.txt"
if [ -z "${STUB_NO_LAST:-}" ]; then
cat > "$out" <<JSON
{"status":"${STUB_STATUS:-DONE}","summary":"stub summary","commit_subject":"feat(x): stub change","questions":[]}
JSON
fi
exit "${STUB_RC:-0}"
STUB
chmod +x "$TMP/stub/codex"

check "the stub shadows the real codex" \
  "$(PATH="$TMP/stub:$PATH" command -v codex)" "$TMP/stub/codex"

run_exec() { # run_exec  -> prints the wrapper's stdout status line
  PATH="$TMP/stub:$PATH" bash "$SCRIPT" \
    --brief "$TMP/brief.md" --report "$TMP/report.md" \
    --cwd "$TMP/repo" --model gpt-5.5 --effort medium "$@" 2>"$TMP/err"
}

# A cwd below the repository root would make `git add -A` stage the whole repo.
mkdir -p "$TMP/repo/sub"
check "refuses a cwd that is not the repository root" \
  "$(PATH="$TMP/stub:$PATH" bash "$SCRIPT" --brief "$TMP/brief.md" \
      --report "$TMP/report.md" --cwd "$TMP/repo/sub" --model gpt-5.5 \
      --effort medium >/dev/null 2>&1; echo $?)" "2"

before=$(git -C "$TMP/repo" rev-parse HEAD)
line=$(STUB_STATUS=DONE run_exec)
after=$(git -C "$TMP/repo" rev-parse HEAD)

check "DONE commits exactly one commit" \
  "$(git -C "$TMP/repo" rev-list --count "$before".."$after")" "1"
check "DONE uses the schema commit subject" \
  "$(git -C "$TMP/repo" log -1 --pretty=%s)" "feat(x): stub change"
check "status line reports DONE" "$(grep -qF 'status=DONE' <<<"$line" && echo yes || echo no)" "yes"
check "status line carries the thread id" "$(grep -qF 'thread=th-001' <<<"$line" && echo yes || echo no)" "yes"
check "report file was written" "$([ -f "$TMP/report.md" ] && echo yes || echo no)" "yes"
check "report records the executor tier" \
  "$(grep -qE '^- executor: codex gpt-5\.5 / medium' "$TMP/report.md" && echo yes || echo no)" "yes"
check "report records the thread id" \
  "$(grep -qE '^- thread: th-001' "$TMP/report.md" && echo yes || echo no)" "yes"
check "report records a commit range" \
  "$(grep -qE '^- commits: [0-9a-f]{7}\.\.[0-9a-f]{7}' "$TMP/report.md" && echo yes || echo no)" "yes"

# A non-DONE status must leave the tree dirty rather than commit broken work,
# which is how a Claude implementer behaves when it reports BLOCKED mid-task.
before=$(git -C "$TMP/repo" rev-parse HEAD)
line=$(STUB_STATUS=BLOCKED STUB_THREAD=th-002 run_exec)
after=$(git -C "$TMP/repo" rev-parse HEAD)
check "BLOCKED creates no commit" "$(git -C "$TMP/repo" rev-list --count "$before".."$after")" "0"
check "BLOCKED is reported on the status line" \
  "$(grep -qF 'status=BLOCKED' <<<"$line" && echo yes || echo no)" "yes"
check "BLOCKED leaves the tree dirty" \
  "$(git -C "$TMP/repo" status --porcelain | grep -q . && echo yes || echo no)" "yes"
git -C "$TMP/repo" reset -q --hard HEAD
git -C "$TMP/repo" clean -qfd

# Codex can exit 0 without writing its final message. The wrapper must not
# read a previous run's verdict as this one's, which resume rounds guarantee
# will be present since they reuse the same --report path.
line=$(STUB_STATUS=DONE STUB_THREAD=th-010 run_exec) || true
mid=$(git -C "$TMP/repo" rev-parse HEAD)
line=$(STUB_NO_LAST=1 STUB_THREAD=th-011 run_exec) || true
after=$(git -C "$TMP/repo" rev-parse HEAD)
check "a run that writes no verdict does not inherit the previous one" \
  "$(git -C "$TMP/repo" rev-list --count "$mid".."$after")" "0"
check "a run that writes no verdict reports BLOCKED" \
  "$(grep -qF 'status=BLOCKED' <<<"$line" && echo yes || echo no)" "yes"
git -C "$TMP/repo" reset -q --hard HEAD; git -C "$TMP/repo" clean -qfd

# A non-zero exit is a run failure regardless of what the last message claimed.
before=$(git -C "$TMP/repo" rev-parse HEAD)
line=$(STUB_RC=1 STUB_STATUS=DONE STUB_THREAD=th-003 run_exec) || true
after=$(git -C "$TMP/repo" rev-parse HEAD)
check "non-zero exit creates no commit" "$(git -C "$TMP/repo" rev-list --count "$before".."$after")" "0"
git -C "$TMP/repo" reset -q --hard HEAD
git -C "$TMP/repo" clean -qfd

# A DONE verdict with an empty diff must still report, not die with nothing.
rm -f "$TMP/report.md"
before=$(git -C "$TMP/repo" rev-parse HEAD)
line=$(STUB_NO_WRITE=1 STUB_STATUS=DONE STUB_THREAD=th-020 run_exec) || true
after=$(git -C "$TMP/repo" rev-parse HEAD)
check "DONE with an empty diff creates no commit" \
  "$(git -C "$TMP/repo" rev-list --count "$before".."$after")" "0"
check "DONE with an empty diff still writes a report" \
  "$([ -f "$TMP/report.md" ] && echo yes || echo no)" "yes"
check "DONE with an empty diff still prints a status line" \
  "$(grep -qF 'status=DONE' <<<"$line" && echo yes || echo no)" "yes"
check "DONE with an empty diff records why nothing was committed" \
  "$(grep -qF 'nothing was committed' "$TMP/report.md" && echo yes || echo no)" "yes"
git -C "$TMP/repo" reset -q --hard HEAD
git -C "$TMP/repo" clean -qfd

check "the prompt inlines repo conventions when present" \
  "$(printf 'be terse\n' > "$TMP/repo/CLAUDE.md"; STUB_STATUS=DONE run_exec >/dev/null; \
     grep -qF 'be terse' "$TMP/report.md.prompt.md" && echo yes || echo no)" "yes"
git -C "$TMP/repo" reset -q --hard HEAD; git -C "$TMP/repo" clean -qfd

# $report itself is only written after the commit, so a single round never
# exercises this. A resume round does: round 1's report is still sitting in
# $cwd, untracked, when round 2's `git add -A` runs, so only a second round
# with the same --report path under $cwd can prove it stays out of the commit.
inline_report="$TMP/repo/inline-report.md"
PATH="$TMP/stub:$PATH" STUB_STATUS=DONE STUB_THREAD=th-040 bash "$SCRIPT" \
  --brief "$TMP/brief.md" --report "$inline_report" \
  --cwd "$TMP/repo" --model gpt-5.5 --effort medium >/dev/null 2>"$TMP/err"
before=$(git -C "$TMP/repo" rev-parse HEAD)
PATH="$TMP/stub:$PATH" STUB_STATUS=DONE STUB_THREAD=th-041 bash "$SCRIPT" \
  --brief "$TMP/brief.md" --report "$inline_report" \
  --cwd "$TMP/repo" --model gpt-5.5 --effort medium >/dev/null 2>"$TMP/err"
after=$(git -C "$TMP/repo" rev-parse HEAD)
# Without this, an argument error in the second invocation (or any other
# early exit) leaves HEAD unchanged, and the exclusion check below would then
# report "excluded" for the wrong reason - nothing to sweep, not correct
# exclusion of something present. The reviewer confirmed this with --bogus x.
check "the resumed round actually produced a commit" \
  "$(git -C "$TMP/repo" rev-list --count "$before".."$after")" "1"
check "a resumed --report path inside cwd is not swept into the commit" \
  "$(git -C "$TMP/repo" log -1 --name-only --pretty=format: | grep -qxF 'inline-report.md' && echo swept || echo excluded)" \
  "excluded"
git -C "$TMP/repo" reset -q --hard HEAD; git -C "$TMP/repo" clean -qfd

# A model that never responds must not hang the wrapper forever, and killing it
# must happen before the process exits, since `timeout` reaping its own child
# is what made the previous kill attempt inert (see run-codex-task.sh).
rm -f "$TMP/report.md" "$TMP/sleep.winpid"
before=$(git -C "$TMP/repo" rev-parse HEAD)
start=$(date +%s)
line=$(STUB_SLEEP=30 STUB_THREAD=th-030 STUB_SLEEP_WINPID_FILE="$TMP/sleep.winpid" \
  PATH="$TMP/stub:$PATH" bash "$SCRIPT" \
  --brief "$TMP/brief.md" --report "$TMP/report.md" --cwd "$TMP/repo" \
  --model gpt-5.5 --effort medium --timeout 3 2>/dev/null) || true
elapsed=$(( $(date +%s) - start ))
after=$(git -C "$TMP/repo" rev-parse HEAD)
check "a timed-out run returns long before the child would finish" \
  "$([ "$elapsed" -lt 20 ] && echo yes || echo no)" "yes"
check "a timed-out run reports BLOCKED" \
  "$(grep -qF 'status=BLOCKED' <<<"$line" && echo yes || echo no)" "yes"
check "a timed-out run creates no commit" \
  "$(git -C "$TMP/repo" rev-list --count "$before".."$after")" "0"
# Proves the real grandchild died, not just that the wrapper stopped waiting
# for it: taskkill //F //T on a winpid was shown live to leave this exact
# process running, so this closes the gap that check alone would leave open.
sleep_winpid=$(cat "$TMP/sleep.winpid" 2>/dev/null || true)
# Without this, an empty capture (a future host where /proc/N/winpid does not
# resolve) makes the death check pass vacuously via its `|| echo gone` branch,
# proving nothing while looking green.
check "a timed-out run's grandchild winpid was captured" \
  "$([ -n "$sleep_winpid" ] && echo yes || echo no)" "yes"
# Captured separately from the match, and stderr is not discarded: `tasklist`
# itself failing (not just finding nothing) must not be indistinguishable from
# a clean "gone" via an `&&`-chain's `|| echo gone` fallback.
tl_out=$(tasklist //FI "PID eq $sleep_winpid" 2>&1)
tl_rc=$?
check "tasklist itself ran successfully" "$([ "$tl_rc" -eq 0 ] && echo yes || echo no)" "yes"
check "a timed-out run's grandchild process is actually dead" \
  "$(grep -q "$sleep_winpid" <<<"$tl_out" && echo alive || echo gone)" \
  "gone"
git -C "$TMP/repo" reset -q --hard HEAD; git -C "$TMP/repo" clean -qfd

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
