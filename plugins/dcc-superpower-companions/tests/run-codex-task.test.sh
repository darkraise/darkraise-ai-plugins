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
  "$(grep -qE 'timeout +900' <<<"$cmd" && echo yes || echo no)" "yes"
check "explicit timeout wins" \
  "$(dry --model gpt-5.5 --effort medium --timeout 42 | grep -qE 'timeout +42' && echo yes || echo no)" "yes"

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
check "rejects a multi-word effort" "$(rc_of --model gpt-5.5 --effort 'medium high')" "2"

check "rejected input prints nothing on stdout" \
  "$(bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/report.md" \
      --cwd "$TMP/work" --model luna --effort medium --dry-run 2>/dev/null \
      | wc -c | tr -d ' \r\n')" "0"

# The dry run's contract is that it shows what would actually run, so re-parse
# what it printed and confirm a space-containing path survives as ONE argument.
mkdir -p "$TMP/dir with space"
printed=$(bash "$SCRIPT" --brief "$TMP/brief.md" --report "$TMP/report.md" \
  --cwd "$TMP/dir with space" --model gpt-5.5 --effort medium --dry-run 2>/dev/null)
eval "set -- $printed"
roundtrip=no
while [ $# -gt 0 ]; do
  if [ "$1" = "-C" ] && [ "${2:-}" = "$TMP/dir with space" ]; then roundtrip=yes; fi
  shift
done
check "dry run round-trips a space-containing path as one argument" "$roundtrip" "yes"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
