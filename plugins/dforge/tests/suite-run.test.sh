#!/usr/bin/env bash
# suite-run records a command's run per HEAD, reuses a clean pass at the same
# HEAD, and prints a digest that never reports a failure as silence. Every case
# works in a throwaway git repository; HOME points into the temporary directory.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$HERE/../scripts/suite-run"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <text> <needle>
  case $2 in
    *"$3"*) printf 'ok   - %s\n' "$1"; pass=$((pass + 1)) ;;
    *) printf 'FAIL - %s\n       missing: [%s]\n       in:      [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)) ;;
  esac
}
lacks() { # lacks <name> <text> <needle>
  case $2 in
    *"$3"*) printf 'FAIL - %s\n       unexpected: [%s]\n' "$1" "$3"; fail=$((fail + 1)) ;;
    *) printf 'ok   - %s\n' "$1"; pass=$((pass + 1)) ;;
  esac
}

TMP=$(mktemp -d)
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export MSYS_NO_PATHCONV=1

REPO="$TMP/repo"
git init -q -b main "$REPO"
git -C "$REPO" config user.name Tester
git -C "$REPO" config user.email tester@example.com
printf 'one\n' > "$REPO/a.txt"
git -C "$REPO" add a.txt
git -C "$REPO" commit -q -m one
commit() { printf '%s\n' "$1" >> "$REPO/a.txt"; git -C "$REPO" commit -q -am "$1"; }

# probe.sh stands in for a test suite: it counts its runs in $PROBE_RUNS, prints
# the file it is given and exits with the code it is given.
export PROBE_RUNS="$TMP/runs"
cat > "$TMP/probe.sh" <<'PROBE'
echo x >> "$PROBE_RUNS"
[ -z "${2:-}" ] || cat "$2"
exit "${1:-0}"
PROBE
runs() { if [ -f "$PROBE_RUNS" ]; then wc -l < "$PROBE_RUNS" | tr -d ' '; else echo 0; fi; }
probe() { run -- bash "$TMP/probe.sh" "$@"; }
run() { out=$(cd "$REPO" && bash "$SUITE" "$@" 2>&1); rc=$?; }
rows() { wc -l < "$REPO/.dforge/suites.tsv" | tr -d ' '; }
last_row() { tail -n 1 "$REPO/.dforge/suites.tsv" | tr -d '\r'; }
field() { last_row | cut -f"$1"; }

printf '# tests 3\n# pass 3\n# fail 0\n' > "$TMP/out-tap-pass"
printf 'ok 1 - a\nnot ok 2 - b broke\nnot ok 3 - c broke\n# pass 1\n# fail 2\n' > "$TMP/out-tap-fail"
printf 'boom: something broke\nsecond line\n' > "$TMP/out-opaque"
seq 1 40 | sed 's/^/line /' > "$TMP/out-long"
printf 'bun test\n(pass) a\n(fail) b > breaks [1.2ms]\n\n 1 pass\n 1 fail\n' > "$TMP/out-bun"
printf 'ok   - one\nFAIL - two\n       want: [a]\n\n3 passed, 1 failed\n' > "$TMP/out-fail-word"
i=0; : > "$TMP/out-many"
while [ "$i" -lt 25 ]; do i=$((i + 1)); printf 'not ok %s - case %s\n' "$i" "$i" >> "$TMP/out-many"; done

# --- a first run, a reuse, and what ends one -------------------------------
HEAD1=$(git -C "$REPO" rev-parse HEAD)
probe 0 "$TMP/out-tap-pass"
check "a passing run exits 0" "$rc" "0"
has "a pass prints its verdict" "$out" "suite: pass (exit 0)"
has "a pass prints the counts it read" "$out" "counts: 3 pass, 0 fail"
check "the digest ends with the log path" "$(printf '%s\n' "$out" | tail -n 1 | cut -c1-5)" "log: "
check "the command ran once" "$(runs)" "1"
check "the row has six fields" "$(last_row | awk -F'\t' '{print NF}')" "6"
check "the row records HEAD" "$(field 1)" "$HEAD1"
check "the row records a clean tree" "$(field 2)" "clean"
check "the row records the command" "$(field 3)" "bash $TMP/probe.sh 0 $TMP/out-tap-pass"
check "the row records the exit" "$(field 4)" "0"
check "the logged output is kept" "$(cat "$(field 5)")" "$(cat "$TMP/out-tap-pass")"
check "the run leaves the tree clean" "$(git -C "$REPO" status --porcelain --untracked-files=all)" ""

probe 0 "$TMP/out-tap-pass"
check "a repeat at the same HEAD exits 0" "$rc" "0"
has "a repeat reuses the pass" "$out" "suite: reused pass at ${HEAD1:0:7} ("
check "a reuse does not run the command" "$(runs)" "1"
check "a reuse records no row" "$(rows)" "1"

probe 0 "$TMP/out-opaque"
check "another command runs" "$(runs)" "2"

commit two
probe 0 "$TMP/out-tap-pass"
check "a new HEAD runs again" "$(runs)" "3"
HEAD2=$(git -C "$REPO" rev-parse HEAD)
check "the new row records the new HEAD" "$(field 1)" "$HEAD2"

# --- a dirty tree never reuses and never records a reusable row --------------
printf 'x\n' > "$REPO/scratch.txt"
probe 0 "$TMP/out-tap-pass"
check "a dirty tree runs despite a clean pass at this HEAD" "$(runs)" "4"
check "the dirty run is recorded as dirty" "$(field 2)" "dirty"
probe 0 "$TMP/out-tap-pass"
check "a dirty tree never reuses its own row" "$(runs)" "5"
rm "$REPO/scratch.txt"
probe 0 "$TMP/out-tap-pass"
has "a clean tree reuses the earlier clean pass" "$out" "suite: reused pass at ${HEAD2:0:7} ("
check "the dirty rows did not run it again" "$(runs)" "5"

commit three
printf 'x\n' > "$REPO/scratch.txt"
probe 0 "$TMP/out-tap-pass"
rm "$REPO/scratch.txt"
probe 0 "$TMP/out-tap-pass"
check "a pass recorded dirty is not reused once the tree is clean" "$(runs)" "7"
check "the clean run is recorded clean" "$(field 2)" "clean"

printf 'tracked change\n' >> "$REPO/a.txt"
probe 0 "$TMP/out-tap-pass"
check "a modified tracked file counts as dirty" "$(field 2)" "dirty"
git -C "$REPO" checkout -q -- a.txt

# --- a command that dirties the tree is recorded dirty -------------------------
commit four
run -- bash -c 'echo made > made.txt'
check "a run that leaves a file behind records dirty" "$(field 2)" "dirty"
rm "$REPO/made.txt"

# --- failures ----------------------------------------------------------------
commit five
probe 1 "$TMP/out-tap-fail"
check "a failing run exits with the command's code" "$rc" "1"
has "a failure prints its verdict" "$out" "suite: FAIL (exit 1)"
has "a failure prints the counts" "$out" "counts: 1 pass, 2 fail"
has "a failure prints its failing lines" "$out" "not ok 2 - b broke"
has "a failure prints every failing line" "$out" "not ok 3 - c broke"
lacks "a matched failure does not print the log tail" "$out" "last 30 lines"
check "the failing exit is recorded" "$(field 4)" "1"
before=$(runs)
probe 1 "$TMP/out-tap-fail"
check "a failure is never reused" "$(runs)" "$((before + 1))"

probe 7 "$TMP/out-opaque"
check "an unmatched failure keeps its exit code" "$rc" "7"
has "an unmatched failure is still a FAIL" "$out" "suite: FAIL (exit 7)"
has "an unmatched failure prints the log tail" "$out" "last 30 lines of "
has "an unmatched failure prints the output" "$out" "boom: something broke"
has "an unmatched failure names the log" "$out" "log: "

probe 4 "$TMP/out-long"
has "the tail holds the last line" "$out" "line 40"
has "the tail holds the 30th line from the end" "$out" "line 11"
lacks "the tail stops at 30 lines" "$out" "line 10"$'\n'
lacks "the tail drops the early lines" "$out" "line 1"$'\n'

probe 5
check "a failure with no output exits non-zero" "$rc" "5"
has "a failure with no output is still reported" "$out" "suite: FAIL (exit 5)"
has "a failure with no output names the log tail" "$out" "last 30 lines of "

probe 1 "$TMP/out-bun"
has "a Bun failing line is matched" "$out" "(fail) b > breaks [1.2ms]"
has "Bun counts are read" "$out" "counts: 1 pass, 1 fail"
lacks "a Bun passing line is not a failing line" "$out" "(pass) a"

probe 1 "$TMP/out-fail-word"
has "a line starting FAIL is matched" "$out" "FAIL - two"
has "a shell suite's summary supplies the counts" "$out" "counts: 3 pass, 1 fail"

probe 1 "$TMP/out-many"
check "at most 20 failing lines are printed" "$(printf '%s\n' "$out" | grep -c '^not ok')" "20"
has "the 20th failing line is printed" "$out" "not ok 20 - case 20"
lacks "the 21st failing line is not" "$out" "not ok 21 - case 21"

run -- bash -c 'printf "not ok 1 - crlf\r\n"; exit 1'
has "a CR does not hide a failing line" "$out" "not ok 1 - crlf"

run -- no-such-command-here
check "a command that does not start fails" "$rc" "127"
has "a command that does not start is reported" "$out" "suite: FAIL (exit 127)"

# --- timeout and heartbeat ---------------------------------------------------------
run --timeout 1 -- sleep 5
check "a timeout exits 124" "$rc" "124"
has "a timeout is a FAIL" "$out" "suite: FAIL (exit 124)"
check "a timeout is recorded" "$(field 4)" "124"

out=$(cd "$REPO" && SUITE_RUN_KILL_AFTER=1 bash "$SUITE" --timeout 1 -- bash -c 'trap "" TERM; sleep 30' 2>&1); rc=$?
check "a command that ignores TERM is still a timeout" "$rc" "124"

out=$(cd "$REPO" && SUITE_RUN_HEARTBEAT=1 bash "$SUITE" -- sleep 3 2>&1); rc=$?
check "a heartbeat run passes" "$rc" "0"
has "a running command prints a heartbeat" "$out" "suite-run: running "

# --- usage ---------------------------------------------------------------------------
run
check "no command exits 2" "$rc" "2"
run --
check "an empty command exits 2" "$rc" "2"
run bash -c true
check "a command without -- exits 2" "$rc" "2"
run --timeout x -- true
check "a bad timeout exits 2" "$rc" "2"
run --timeout 0 -- true
check "a zero timeout exits 2" "$rc" "2"
mkdir "$TMP/plain"
out=$(cd "$TMP/plain" && bash "$SUITE" -- true 2>&1); rc=$?
check "outside a git checkout exits 2" "$rc" "2"
has "outside a git checkout says so" "$out" "not in a git checkout"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
