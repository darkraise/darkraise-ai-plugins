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

# Flag ORDER is a correctness property here, not a style one: `codex exec`
# accepts -C and -s while `codex exec resume` rejects both, so a substring test
# that ignores position passes on an argv the real CLI refuses to parse.
before() { # before <argv-line> <first> <second> -> yes when both are present, in order
  awk -v a="$2" -v b="$3" '
    { ai = 0; bi = 0
      for (i = 1; i <= NF; i++) {
        if (ai == 0 && $i == a) ai = i
        if (bi == 0 && $i == b) bi = i
      }
      print (ai > 0 && bi > 0 && ai < bi) ? "yes" : "no" }
  ' <<<"$1"
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

# --- resume must place -C and -s before the subcommand -----------------------
# Verified against codex-cli 0.153.4: `codex exec resume <id> -C <dir>` answers
# `error: unexpected argument '-C' found` and exits before any model call, and
# -s is refused the same way. The wrapper would then report status=BLOCKED,
# which is indistinguishable from a real block, so every fix round on the
# external lane would die at argument parsing. The parent `codex exec` takes
# both flags and honours them for the resumed thread.
res_cmd=$(tail -1 <<<"$res")
check "resume places -C before the subcommand" "$(before "$res_cmd" -C resume)" "yes"
check "resume places -s before the subcommand" "$(before "$res_cmd" -s resume)" "yes"
check "resume keeps -m after the subcommand, where resume accepts it" \
  "$(before "$res_cmd" resume -m)" "yes"
check "resume keeps the thread id adjacent to the subcommand" \
  "$(grep -qE -- 'resume 01a0-thread' <<<"$res_cmd" && echo yes || echo no)" "yes"

plain_cmd=$(tail -1 <<<"$(dry --model gpt-5.5 --effort medium)")
check "a non-resume run names no subcommand" \
  "$(grep -qE -- '(^| )resume( |$)' <<<"$plain_cmd" && echo named || echo bare)" "bare"
check "a non-resume run still passes -C" \
  "$(grep -qF -- "-C $TMP/work" <<<"$plain_cmd" && echo yes || echo no)" "yes"
check "a non-resume run still passes the sandbox" \
  "$(grep -qF -- "-s workspace-write" <<<"$plain_cmd" && echo yes || echo no)" "yes"

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

# A non-numeric timeout is worse than useless: `[ "$waited" -lt "$timeout_s" ]`
# errors and evaluates false on the first iteration, so the poll loop never runs
# and the tree is killed about a second after launch - reported as BLOCKED. A
# controller following the Timeout row ("retry with --timeout raised") is
# exactly who writes 30m.
check "rejects a non-numeric timeout" "$(rc_of --model gpt-5.5 --effort medium --timeout 30m)" "2"
check "rejects a seconds-suffixed timeout" "$(rc_of --model gpt-5.5 --effort medium --timeout 1800s)" "2"
tmsg=$(bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/report.md" --cwd "$TMP/work" \
      --model gpt-5.5 --effort medium --timeout 30m --dry-run 2>&1 >/dev/null)
check "a non-numeric timeout is rejected at the timeout check" \
  "$(grep -qF 'whole seconds' <<<"$tmsg" && echo yes || echo no)" "yes"

# A report directory that does not exist would otherwise surface as shell
# redirect errors and exit 1 - the code the skill defines as "Codex ran and did
# not reach DONE", costing the controller a rung for a typo.
check "rejects a report directory that does not exist" \
  "$(bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/no-such-dir/report.md" \
      --cwd "$TMP/work" --model gpt-5.5 --effort medium --dry-run >/dev/null 2>&1; echo $?)" "2"

# jq parses every verdict. Absent, the parse falls back to BLOCKED, which the
# controller cannot tell from a real block - it spends a rung and a second paid
# run to learn nothing. PATH is stripped to a lone dirname shim, the only
# external command the wrapper runs before this guard.
BASH_BIN=$(command -v bash)
mkdir -p "$TMP/nojq"
printf '#!%s\nexec "%s" "$@"\n' "$BASH_BIN" "$(command -v dirname)" > "$TMP/nojq/dirname"
chmod +x "$TMP/nojq/dirname"
jq_rc=$(PATH="$TMP/nojq" "$BASH_BIN" "$SCRIPT" --brief "$TMP/brief.md" \
      --report "$TMP/report.md" --cwd "$TMP/work" --model gpt-5.5 --effort medium \
      --dry-run >/dev/null 2>"$TMP/jq.err"; echo $?)
check "a missing jq exits 2 before anything is spawned" "$jq_rc" "2"
check "a missing jq names the dependency rather than failing downstream" \
  "$(grep -qF 'jq is required' "$TMP/jq.err" && echo yes || echo no)" "yes"

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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
