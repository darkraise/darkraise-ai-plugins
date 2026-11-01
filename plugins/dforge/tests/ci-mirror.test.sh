#!/usr/bin/env bash
# ci-mirror runs the local commands of a plan's **CI:** line through suite-run,
# prints one digest line per command and the uncovered platforms, and exits
# non-zero when a command fails or cannot launch. Every case works in a
# throwaway git repository; HOME points into the temporary directory.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIRROR="$HERE/../scripts/ci-mirror"

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

export PROBE_RUNS="$TMP/runs"
runs() { if [ -f "$PROBE_RUNS" ]; then wc -l < "$PROBE_RUNS" | tr -d ' '; else echo 0; fi; }
mirror() { # mirror <plan file> — stdout in $out, stderr in $err, exit code in $rc
  out=$(cd "$REPO" && timeout 120 bash "$MIRROR" "$@" 2>"$TMP/err" < /dev/null); rc=$?
  err=$(cat "$TMP/err")
}
rows() { wc -l < "$REPO/.dforge/suites.tsv" | tr -d ' '; }
key_of() { sed -n "${1}p" "$REPO/.dforge/suites.tsv" | tr -d '\r' | cut -f3; }

# --- a plan whose CI line is none --------------------------------------------
printf '# P\n\n**Spec:** `s.md`\n\n**CI:** none\n\n### Task 1: One\n\nbody\n' > "$TMP/none.md"
mirror "$TMP/none.md"
check "none exits 0" "$rc" "0"
check "none prints ci: none and nothing else" "$out" "ci: none"
check "none runs nothing through suite-run" "$([ -e "$REPO/.dforge/suites.tsv" ] && echo yes || echo no)" "no"

# --- local commands run through suite-run ----------------------------------------
cat > "$TMP/ci.md" <<'EOF'
# P

**Spec:** `s.md`

**CI:** `.github/workflows/validate.yml` — platforms: ubuntu-latest, windows-latest — local: `echo ran >> "$PROBE_RUNS"`; `true` — uncovered: Windows Git Bash, macOS

## Global Constraints

- c

### Task 1: One

body
EOF
HEAD1=$(git -C "$REPO" rev-parse HEAD)
mirror "$TMP/ci.md"
check "a passing mirror exits 0" "$rc" "0"
check "one digest line per command, then the uncovered platforms" "$out" "$(printf '%s\n' \
  'ci: echo ran >> "$PROBE_RUNS" — pass (exit 0)' \
  'ci: true — pass (exit 0)' \
  'uncovered: Windows Git Bash, macOS')"
check "each command is one suite-run row" "$(rows)" "2"
want=$(printf '%q ' bash -c 'echo ran >> "$PROBE_RUNS"'); want=${want% }
check "the first row is keyed as bash -c of the command" "$(key_of 1)" "$want"
check "the second row is keyed as bash -c of the command" "$(key_of 2)" "bash -c true"
check "the first command ran once" "$(runs)" "1"

mirror "$TMP/ci.md"
check "a repeat at the same HEAD exits 0" "$rc" "0"
check "a repeat reuses both passes" "$(printf '%s\n' "$out" | grep -c "reused pass at ${HEAD1:0:7} (")" "2"
check "a reuse runs nothing" "$(runs)" "1"
check "a reuse records no row" "$(rows)" "2"

commit two
mirror "$TMP/ci.md"
check "a new HEAD runs the commands again" "$(runs)" "2"

# --- commands run from the top level, whatever the caller's directory ----------------
commit three
mkdir -p "$REPO/sub"
out=$(cd "$REPO/sub" && timeout 120 bash "$MIRROR" "$TMP/ci.md" 2>/dev/null); rc=$?
check "a run from a subdirectory passes" "$rc" "0"
check "a run from a subdirectory still runs the command" "$(runs)" "3"
check "no row names the subdirectory" "$(cut -f3 "$REPO/.dforge/suites.tsv" | tr -d '\r' | grep -c '^(sub)')" "0"

# --- a failing command, and a command that cannot launch ---------------------------------
cat > "$TMP/fail.md" <<'EOF'
# P

**Spec:** `s.md`

**CI:** `ci.yml` — platforms: ubuntu-latest — local: `true`; `exit 3`; `echo after >> "$PROBE_RUNS"` — uncovered: none

### Task 1: One

body
EOF
before=$(runs)
mirror "$TMP/fail.md"
check "a failing command exits 1" "$rc" "1"
check "the digest names the failing command and its exit code" "$(printf '%s\n' "$out" | grep -cF 'ci: exit 3 — FAIL (exit 3)')" "1"
check "a failure does not skip the later commands" "$(runs)" "$((before + 1))"
check "the uncovered line is still printed" "$(printf '%s\n' "$out" | tail -n 1)" "uncovered: none"
check "stdout holds only digest lines" "$(printf '%s\n' "$out" | grep -Evc '^(ci: |uncovered: )')" "0"
has "the failed command's suite-run digest goes to stderr" "$err" "suite: FAIL (exit 3)"
has "stderr names the log" "$err" "log: "

cat > "$TMP/nolaunch.md" <<'EOF'
# P

**Spec:** `s.md`

**CI:** `ci.yml` — platforms: ubuntu-latest — local: `no-such-command-here` — uncovered: none

### Task 1: One

body
EOF
mirror "$TMP/nolaunch.md"
check "a command that cannot launch exits 1" "$rc" "1"
check "its digest line names it" "$(printf '%s\n' "$out" | head -n 1)" "ci: no-such-command-here — FAIL (exit 127)"

# --- a plan written with CRLF line endings -----------------------------------------------------
awk '{ printf "%s\r\n", $0 }' "$TMP/ci.md" > "$TMP/ci-crlf.md"
mirror "$TMP/ci-crlf.md"
check "a CRLF plan exits 0" "$rc" "0"
check "a CRLF plan prints no carriage return" "$(printf '%s' "$out" | tr -cd '\r' | wc -c | tr -d ' ')" "0"
check "a CRLF plan prints the same uncovered line" "$(printf '%s\n' "$out" | tail -n 1)" "uncovered: Windows Git Bash, macOS"

# --- usage and malformed lines exit 2 ------------------------------------------------------------
mirror
check "no argument exits 2" "$rc" "2"
mirror "$TMP/missing.md"
check "a missing plan exits 2" "$rc" "2"
printf '# P\n\n**Spec:** `s.md`\n\n### Task 1: One\n\nbody\n' > "$TMP/noline.md"
mirror "$TMP/noline.md"
check "a plan with no CI line exits 2" "$rc" "2"
has "a plan with no CI line says so" "$err" "no **CI:** line"
printf '# P\n\n````markdown\n**CI:** none\n````\n\n### Task 1: One\n\nbody\n' > "$TMP/fenced.md"
mirror "$TMP/fenced.md"
check "a CI line inside a code fence is not read" "$rc" "2"
while IFS= read -r line; do
  printf '# P\n\n**Spec:** `s.md`\n\n%s\n\n### Task 1: One\n\nbody\n' "$line" > "$TMP/bad.md"
  mirror "$TMP/bad.md"
  check "a malformed CI line exits 2: $line" "$rc" "2"
  check "a malformed CI line prints no digest: $line" "$out" ""
done <<'EOF'
**CI:** nope
**CI:** none — no workflows
**CI:** `ci.yml` — platforms: ubuntu-latest — uncovered: none
**CI:** `ci.yml` — platforms: ubuntu-latest — local: make test — uncovered: none
**CI:** `ci.yml` — platforms: ubuntu-latest — local: `make test`
**CI:** `ci.yml` — platforms: ubuntu-latest — local: `make test` — uncovered:
EOF

mkdir "$TMP/plain"
out=$(cd "$TMP/plain" && timeout 120 bash "$MIRROR" "$TMP/ci.md" 2>&1); rc=$?
check "commands outside a git checkout exit 2" "$rc" "2"
has "commands outside a git checkout say so" "$out" "not in a git checkout"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
