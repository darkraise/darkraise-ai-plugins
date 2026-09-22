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

# A fixed session id and a temporary directory keep the machine's real session
# file out of every case, whatever the wrapper touches.
export DR_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=run-task-test

mkdir -p "$TMP/work"
printf 'do the thing\n' > "$TMP/brief.md"

dry() { bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/report.md" \
          --cwd "$TMP/work" --dry-run "$@" 2>"$TMP/err"; }
rc_of() { dry "$@" >/dev/null; echo $?; }

# The wrapper builds the request with `jq --arg cwd "$cwd"`. Where jq is a native
# Windows build under an MSYS shell, the runtime rewrites a POSIX path argument
# into its Windows form on the way into the process, so the literal the suite
# passed in is not the literal that lands in the JSON. Running the expected value
# through the same one-argument jq call applies the identical rewrite - an
# identity everywhere else - so the assertion compares paths, not path spellings.
as_arg() { jq -rn --arg p "$1" '$p'; }

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

# The ledger's per-task checkpoint reads these two arrays, so an executor-lane
# task reports discovered issues and assumptions exactly as a Claude one does.
check "schema carries the two checkpoint arrays" \
  "$(jq -r '[.properties.discovered_issues.type, .properties.assumptions.type] | join(",")' \
      < "$HERE/../scripts/codex-report-schema.json" | tr -d '\r')" "array,array"
check "contract names both checkpoint fields" \
  "$(grep -c -e '`discovered_issues`' -e '`assumptions`' "$HERE/../scripts/codex-task-contract.md")" "2"

# --- validation happens before anything is spawned --------------------------
check "rejects a model absent from codex-assignment" "$(rc_of --model gpt-4o --effort medium)" "2"
check "rejects luna, which 400s on a ChatGPT account" "$(rc_of --model luna --effort medium)" "2"
check "rejects an invalid effort" "$(rc_of --model gpt-6-sol --effort minimal)" "2"
check "rejects a missing brief" \
  "$(bash "$SCRIPT" --brief "$TMP/nope.md" --report "$TMP/r.md" --cwd "$TMP/work" \
      --model gpt-6-sol --effort medium --dry-run >/dev/null 2>&1; echo $?)" "2"
check "accepts a valid rung" "$(rc_of --model gpt-6-sol --effort medium)" "0"

# --- the composed turn request ----------------------------------------------
req=$(dry --model gpt-6-sol --effort medium | sed -n '2p')
check "dry run: prints a turn request" "$(jq -r '.op' <<<"$req")" "turn"
check "dry run: carries the model" "$(jq -r '.model' <<<"$req")" "gpt-6-sol"
check "dry run: carries the effort" "$(jq -r '.effort' <<<"$req")" "medium"
check "dry run: workspace-write sandbox" "$(jq -r '.sandbox' <<<"$req")" "workspace-write"
check "dry run: persists the thread" "$(jq -r '.persistThread' <<<"$req")" "true"
check "dry run: carries the report schema" \
  "$(jq -r '.schemaPath' <<<"$req" | grep -c 'codex-report-schema.json')" "1"
check "dry run: names the worktree" "$(jq -r '.cwd' <<<"$req")" "$(as_arg "$TMP/work")"
check "dry run: never bypasses the sandbox" \
  "$(jq -r '.sandbox' <<<"$req" | grep -c 'bypass')" "0"

# --- timeouts come from the table unless overridden -------------------------
check "deadline defaults from codex-timeout" "$(jq -r '.deadlineMs' <<<"$req")" "1200000"
check "explicit timeout wins" \
  "$(dry --model gpt-6-sol --effort medium --timeout 42 | sed -n '2p' | jq -r '.deadlineMs')" "42000"

# A resumed run must still re-send the model and the effort: the client starts a
# fresh thread unless resumeThreadId is set, and a resumed thread has to carry
# the tier the ledger recorded.
res=$(dry --model gpt-6-sol --effort high --resume 01a0-thread | sed -n '2p')
check "resume carries the thread id" "$(jq -r '.resumeThreadId' <<<"$res")" "01a0-thread"
check "resume re-sends the model" "$(jq -r '.model' <<<"$res")" "gpt-6-sol"
check "resume re-sends the effort" "$(jq -r '.effort' <<<"$res")" "high"
check "resume still asks for a persisted thread" "$(jq -r '.persistThread' <<<"$res")" "true"

plain=$(dry --model gpt-6-sol --effort medium | sed -n '2p')
check "a non-resume run sends no thread id" "$(jq -r '.resumeThreadId' <<<"$plain")" "null"
check "a non-resume run still names the worktree" "$(jq -r '.cwd' <<<"$plain")" "$(as_arg "$TMP/work")"
check "a non-resume run still asks for workspace-write" "$(jq -r '.sandbox' <<<"$plain")" "workspace-write"

# --- malformed input fails fast, and the dry run tells the truth ------------
check "a trailing flag with no value exits 2 rather than hanging" \
  "$(timeout 10 bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/report.md" \
      --cwd "$TMP/work" --model gpt-6-sol --effort medium --resume \
      >/dev/null 2>&1; echo $?)" "2"

check "rejects an unknown flag" "$(rc_of --model gpt-6-sol --effort medium --bogus x)" "2"
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
      --cwd "$TMP/work" --model gpt-6-sol --effort 'medium high' --dry-run 2>&1 >/dev/null)
check "rejects a multi-word effort at the effort check, not downstream" \
  "$(grep -qF 'invalid reasoning effort' <<<"$msg" && echo yes || echo no)" "yes"

# A non-numeric timeout is worse than useless: `[ "$waited" -lt "$timeout_s" ]`
# errors and evaluates false on the first iteration, so the poll loop never runs
# and the tree is killed about a second after launch - reported as BLOCKED. A
# controller following the Timeout row ("retry with --timeout raised") is
# exactly who writes 30m.
check "rejects a non-numeric timeout" "$(rc_of --model gpt-6-sol --effort medium --timeout 30m)" "2"
check "rejects a seconds-suffixed timeout" "$(rc_of --model gpt-6-sol --effort medium --timeout 1800s)" "2"
tmsg=$(bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/report.md" --cwd "$TMP/work" \
      --model gpt-6-sol --effort medium --timeout 30m --dry-run 2>&1 >/dev/null)
check "a non-numeric timeout is rejected at the timeout check" \
  "$(grep -qF 'whole seconds' <<<"$tmsg" && echo yes || echo no)" "yes"

# A report directory that does not exist would otherwise surface as shell
# redirect errors and exit 1 - the code the skill defines as "Codex ran and did
# not reach DONE", costing the controller a rung for a typo.
check "rejects a report directory that does not exist" \
  "$(bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/no-such-dir/report.md" \
      --cwd "$TMP/work" --model gpt-6-sol --effort medium --dry-run >/dev/null 2>&1; echo $?)" "2"

# jq parses every verdict. Absent, the parse falls back to BLOCKED, which the
# controller cannot tell from a real block - it spends a rung and a second paid
# run to learn nothing. PATH is stripped to a lone dirname shim, the only
# external command the wrapper runs before this guard.
BASH_BIN=$(command -v bash)
mkdir -p "$TMP/nojq"
printf '#!%s\nexec "%s" "$@"\n' "$BASH_BIN" "$(command -v dirname)" > "$TMP/nojq/dirname"
chmod +x "$TMP/nojq/dirname"
jq_rc=$(PATH="$TMP/nojq" "$BASH_BIN" "$SCRIPT" --brief "$TMP/brief.md" \
      --report "$TMP/report.md" --cwd "$TMP/work" --model gpt-6-sol --effort medium \
      --dry-run >/dev/null 2>"$TMP/jq.err"; echo $?)
check "a missing jq exits 2 before anything is spawned" "$jq_rc" "2"
check "a missing jq names the dependency rather than failing downstream" \
  "$(grep -qF 'jq is required' "$TMP/jq.err" && echo yes || echo no)" "yes"

check "rejected input prints nothing on stdout" \
  "$(bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/report.md" \
      --cwd "$TMP/work" --model luna --effort medium --dry-run 2>/dev/null \
      | wc -c | tr -d ' \r\n')" "0"

# The dry run's contract is that it shows what would actually run, so re-parse
# what it printed and confirm a space-containing path arrives whole.
mkdir -p "$TMP/dir with space"
spaced=$(bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/report.md" \
  --cwd "$TMP/dir with space" --model gpt-6-sol --effort medium --dry-run 2>/dev/null \
  | sed -n '2p')
check "dry run carries a space-containing path whole" \
  "$(jq -r '.cwd' <<<"$spaced")" "$(as_arg "$TMP/dir with space")"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
