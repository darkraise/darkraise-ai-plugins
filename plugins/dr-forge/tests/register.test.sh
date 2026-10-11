#!/usr/bin/env bash
# lib/register.sh is the one register parser every script shares, so all of
# them agree on what a row is: fences by the CommonMark rule, escaped pipes
# inside cells, CRLF tolerated.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/lib/register.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

reg() { # reg <file> <rows...>
  local f=$1; shift
  {
    printf '# Sample — item register\n\n'
    printf '**Source:** owner list 2026-09-20\n'
    printf '**Covers:** docs/superpowers/specs/a-design.md, docs/superpowers/specs/b-design.md\n\n'
    printf '| # | Item | Assigned | Acceptance | State | Note |\n'
    printf '|---|---|---|---|---|---|\n'
    printf '%s\n' "$@"
  } > "$f"
}

reg "$TMP/r.md" \
  '| 1 | Tabs in Settings | C2 Settings | Radius follows the axis | planned | - |' \
  '| 2 | Zoom indicator | - | - | done | - |' \
  '| 3 | Stale note | - | - | deferred | out of this batch |'

check "register_field: Source" "$(register_field "$TMP/r.md" Source)" "owner list 2026-09-20"
check "register_rows: identifiers" "$(register_rows "$TMP/r.md" | cut -f1 | tr '\n' ' ')" "1 2 3 "
check "register_rows: states" "$(register_rows "$TMP/r.md" | cut -f5 | tr '\n' '|')" "planned|done|deferred|"
check "register_open: unresolved only" "$(register_open "$TMP/r.md" | cut -f1 | tr '\n' ' ')" "1 "
check "register_covers: two paths" "$(register_covers "$TMP/r.md" | tr '\n' ' ')" \
  "docs/superpowers/specs/a-design.md docs/superpowers/specs/b-design.md "

# The header and separator rows are not items.
check "register_rows: header excluded" "$(register_rows "$TMP/r.md" | grep -c . )" "3"

# A cell may hold an escaped pipe; splitting must not see it.
reg "$TMP/pipe.md" '| 1 | Show a \| b | - | - | open | - |'
check "register_rows: escaped pipe stays in the cell" "$(register_rows "$TMP/pipe.md" | cut -f2)" 'Show a | b'

# Fenced table rows are documentation, not items.
{
  printf '# F — item register\n\n**Source:** s\n**Covers:** -\n\n'
  printf '| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n'
  printf '| 1 | Real | - | - | open | - |\n\n'
  printf '````\n| 9 | Example | - | - | open | - |\n````\n'
} > "$TMP/fenced.md"
check "register_rows: fenced rows ignored" "$(register_rows "$TMP/fenced.md" | cut -f1 | tr '\n' ' ')" "1 "
check "register_covers: a dash covers nothing" "$(register_covers "$TMP/fenced.md")" ""

sed 's/$/\r/' "$TMP/r.md" > "$TMP/crlf.md"
check "register_rows: CRLF" "$(register_rows "$TMP/crlf.md" | cut -f1 | tr '\n' ' ')" "1 2 3 "

# register_scan reports the line number and the field count, which is how
# check tells a short row from a well-formed one.
reg "$TMP/short.md" '| 1 | Missing cells | open |'
check "register_scan: field count of a short row" "$(register_scan "$TMP/short.md" | cut -f2)" "5"
check "register_rows: a short row is not a row" "$(register_rows "$TMP/short.md")" ""

# --- discovery ---
# A real git repository, because `register check` resolves the root with
# git rev-parse and would otherwise fall back to the working directory and
# look for these specs in the checkout running the suite.
ROOT="$TMP/repo"
git init -q -b main "$ROOT"
mkdir -p "$ROOT/docs/superpowers/registers" "$ROOT/docs/superpowers/specs"
: > "$ROOT/docs/superpowers/specs/a-design.md"
: > "$ROOT/docs/superpowers/specs/b-design.md"
reg "$ROOT/docs/superpowers/registers/one.md" '| 1 | A | - | - | open | - |'
printf '# Two — item register\n\n**Source:** s\n**Covers:** docs/superpowers/specs/z-design.md\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | B | - | - | open | - |\n' \
  > "$ROOT/docs/superpowers/registers/two.md"
check "register_files: both" "$(register_files "$ROOT" | wc -l | tr -d ' ')" "2"
check "register_for_spec: matches one" \
  "$(register_for_spec "$ROOT" docs/superpowers/specs/a-design.md | xargs -n1 basename | tr '\n' ' ')" "one.md "
check "register_for_spec: no spec argument prints nothing" "$(register_for_spec "$ROOT")" ""
check "register_files: no directory prints nothing" "$(register_files "$TMP/absent")" ""

# --- register check ---
REG="$HERE/../scripts/register"
run() { # run <args...> -> sets OUT and RC
  OUT=$("$@" 2>&1); RC=$?
}

reg "$ROOT/clean.md" \
  '| 1 | First | - | - | open | - |' \
  '| 2 | Second | - | - | deferred | not this batch |'
run bash "$REG" check "$ROOT/clean.md"
check "check: a clean register" "$RC" "0"
check "check: clean summary" "$(tail -n 1 <<<"$OUT")" "register: 0 errors"

reg "$ROOT/dup.md" '| 1 | A | - | - | open | - |' '| 1 | B | - | - | open | - |'
run bash "$REG" check "$ROOT/dup.md"
check "check: duplicate identifier fails" "$RC" "1"
check "check: names the duplicate" "$(grep -c 'duplicate identifier: 1' <<<"$OUT")" "1"

reg "$ROOT/state.md" '| 1 | A | - | - | finished | - |'
run bash "$REG" check "$ROOT/state.md"
check "check: unknown state fails" "$RC" "1"
check "check: names the state" "$(grep -c 'unknown state: finished' <<<"$OUT")" "1"

reg "$ROOT/note.md" '| 1 | A | - | - | deferred | - |'
run bash "$REG" check "$ROOT/note.md"
check "check: a ruling without its reason fails" "$RC" "1"
check "check: names the missing note" "$(grep -c 'state deferred needs a note' <<<"$OUT")" "1"

reg "$ROOT/short2.md" '| 1 | A | open |'
run bash "$REG" check "$ROOT/short2.md"
check "check: a short row fails" "$RC" "1"

printf '# No header — item register\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | A | - | - | open | - |\n' > "$ROOT/bare.md"
run bash "$REG" check "$ROOT/bare.md"
check "check: missing Source and Covers fails" "$RC" "1"
check "check: names Source" "$(grep -c 'missing \*\*Source:\*\* line' <<<"$OUT")" "1"

printf '# Ghost — item register\n\n**Source:** s\n**Covers:** docs/superpowers/specs/absent-design.md\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | A | - | - | open | - |\n' > "$ROOT/ghost.md"
run bash "$REG" check "$ROOT/ghost.md"
check "check: a Covers path that does not exist fails" "$RC" "1"

run bash "$REG" check "$ROOT/absent-file.md"
check "check: a missing file is usage" "$RC" "2"
run bash "$REG"
check "check: no verb is usage" "$RC" "2"

# --- register open ---
# The exit status is the gate: 1 means "something is still open", so a caller
# can branch on it without parsing the report.
run bash "$REG" open "$ROOT/clean.md"
check "open: rows open exits 1" "$RC" "1"
check "open: names the row" "$(grep -c '#1 First' <<<"$OUT")" "1"
check "open: a resolved row is not listed" "$(grep -c '#2' <<<"$OUT")" "0"

reg "$ROOT/settled.md" '| 1 | A | - | - | done | - |' '| 2 | B | - | - | n/a | answered inline |'
run bash "$REG" open "$ROOT/settled.md"
check "open: nothing open exits 0" "$RC" "0"

run bash "$REG" open --root "$ROOT" --spec docs/superpowers/specs/a-design.md
check "open: by spec finds the covering register" "$RC" "1"
check "open: by spec names the item" "$(grep -c ' A' <<<"$OUT")" "1"

# c-design.md is named by no register: the reg() helper's Covers line lists
# a-design.md and b-design.md, so either of those would match one.
run bash "$REG" open --root "$ROOT" --spec docs/superpowers/specs/c-design.md
check "open: a spec no register covers exits 0" "$RC" "0"

run bash "$REG" open --root "$ROOT" --spec docs/superpowers/specs/a-design.md "$ROOT/clean.md"
check "open: --spec with a file is usage" "$RC" "2"
run bash "$REG" open
check "open: neither --spec nor a file is usage" "$RC" "2"

# --- register set and add ---
reg "$ROOT/w.md" '| 1 | First | - | - | open | - |' '| 2 | Second | C2 | live check | planned | - |'

run bash "$REG" set "$ROOT/w.md" 1 done
check "set: writes the state" "$RC" "0"
check "set: the row is done" "$(register_rows "$ROOT/w.md" | awk -F'\t' '$1 == 1 { print $5 }')" "done"
check "set: the item survives" "$(register_rows "$ROOT/w.md" | awk -F'\t' '$1 == 1 { print $2 }')" "First"

run bash "$REG" set "$ROOT/w.md" 2 verify
check "set: verify without a note is refused" "$RC" "2"
run bash "$REG" set "$ROOT/w.md" 2 verify --note "owner live check owed"
check "set: verify with a note is written" "$RC" "0"
check "set: the note is stored" "$(register_rows "$ROOT/w.md" | awk -F'\t' '$1 == 2 { print $6 }')" "owner live check owed"
check "set: the assignment survives" "$(register_rows "$ROOT/w.md" | awk -F'\t' '$1 == 2 { print $3 }')" "C2"

run bash "$REG" set "$ROOT/w.md" 2 planned --assigned docs/superpowers/plans/p.md
check "set: reassigns" "$(register_rows "$ROOT/w.md" | awk -F'\t' '$1 == 2 { print $3 }')" "docs/superpowers/plans/p.md"
check "set: a kept note survives a state change" "$(register_rows "$ROOT/w.md" | awk -F'\t' '$1 == 2 { print $6 }')" "owner live check owed"

run bash "$REG" set "$ROOT/w.md" 9 done
check "set: an unknown identifier is refused" "$RC" "2"
run bash "$REG" set "$ROOT/w.md" 1 finished
check "set: an unknown state is refused" "$RC" "2"

run bash "$REG" add "$ROOT/w.md" "Discovered during execution"
check "add: appends" "$RC" "0"
check "add: takes the next identifier" "$(register_rows "$ROOT/w.md" | cut -f1 | tr '\n' ' ')" "1 2 3 "
check "add: defaults to open" "$(register_rows "$ROOT/w.md" | awk -F'\t' '$1 == 3 { print $5 }')" "open"
check "add: stores the item" "$(register_rows "$ROOT/w.md" | awk -F'\t' '$1 == 3 { print $2 }')" "Discovered during execution"

run bash "$REG" add "$ROOT/w.md" "Ruled out" --state deferred
check "add: deferred without a note is refused" "$RC" "2"
run bash "$REG" add "$ROOT/w.md" "Ruled out" --state deferred --note "disproportionate for this batch"
check "add: deferred with a note is written" "$RC" "0"
check "add: identifiers keep climbing" "$(register_rows "$ROOT/w.md" | cut -f1 | tr '\n' ' ')" "1 2 3 4 "

run bash "$REG" add "$ROOT/w.md" "Holds a | pipe"
check "add: a pipe is escaped on write" "$(register_rows "$ROOT/w.md" | awk -F'\t' '$1 == 5 { print $2 }')" "Holds a | pipe"
run bash "$REG" check "$ROOT/w.md"
check "add: the written register still checks clean" "$RC" "0"

# An empty table still accepts the first row.
printf '# E — item register\n\n**Source:** s\n**Covers:** -\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n\n## Notes\n\nTrailing prose.\n' > "$ROOT/empty.md"
run bash "$REG" add "$ROOT/empty.md" "The first item"
check "add: the first row of an empty table" "$(register_rows "$ROOT/empty.md" | cut -f1)" "1"
check "add: trailing prose survives" "$(tail -n 1 "$ROOT/empty.md")" "Trailing prose."

# --- the repository's own registers ---
# They are load-bearing for three scripts and two skills, so one that stopped
# parsing would otherwise go unnoticed.
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
while IFS= read -r own; do
  [ -n "$own" ] || continue
  run bash "$REG" check "$own"
  check "own register parses: $(basename "$own")" "$RC" "0"
done < <(register_files "$REPO_ROOT")

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
