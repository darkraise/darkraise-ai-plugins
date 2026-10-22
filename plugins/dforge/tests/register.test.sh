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
mkdir -p "$ROOT/docs/dforge/registers" "$ROOT/docs/dforge/specs"
: > "$ROOT/docs/dforge/specs/a-design.md"
: > "$ROOT/docs/dforge/specs/b-design.md"
reg "$ROOT/docs/dforge/registers/one.md" '| 1 | A | - | - | open | - |'
printf '# Two — item register\n\n**Source:** s\n**Covers:** docs/superpowers/specs/z-design.md\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | B | - | - | open | - |\n' \
  > "$ROOT/docs/dforge/registers/two.md"
check "register_files: both" "$(register_files "$ROOT" | wc -l | tr -d ' ')" "2"
check "register_for_spec: matches one" \
  "$(register_for_spec "$ROOT" docs/superpowers/specs/a-design.md | xargs -n1 basename | tr '\n' ' ')" "one.md "
check "register_for_spec: no spec argument prints nothing" "$(register_for_spec "$ROOT")" ""
check "register_for_spec: the other docs prefix matches" \
  "$(register_for_spec "$ROOT" docs/dforge/specs/a-design.md | xargs -n1 basename | tr '\n' ' ')" "one.md "
check "register_for_spec: a leading ./ and the other prefix match" \
  "$(register_for_spec "$ROOT" ./docs/dforge/specs/b-design.md | xargs -n1 basename | tr '\n' ' ')" "one.md "
check "register_for_spec: docs/superpowersx is another name" \
  "$(register_for_spec "$ROOT" docs/superpowersx/specs/a-design.md)" ""
check "register_files: no directory prints nothing" "$(register_files "$TMP/absent")" ""
mkdir -p "$TMP/dforge/docs/dforge/registers"
reg "$TMP/dforge/docs/dforge/registers/one.md" '| 1 | A | - | - | open | - |'
check "register_files: a docs/dforge checkout" "$(register_files "$TMP/dforge" | xargs -n1 basename)" "one.md"

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

# An empty cell must not shift the cells after it into place.
reg "$ROOT/gap.md" '| 1 | A |  | acceptance | garbage | done |'
run bash "$REG" check "$ROOT/gap.md"
check "check: an empty cell does not hide an unknown state" "$(grep -c 'unknown state: garbage' <<<"$OUT")" "1"

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

run bash "$REG" set "$ROOT/w.md" 1 'done deferred' --note x
check "set: two states in one value are refused" "$RC" "2"
run bash "$REG" set "$ROOT/w.md" 2 verify --note $'line one\nline two'
check "set: a multiline note is refused" "$RC" "2"
check "set: the refused row still parses" "$(register_rows "$ROOT/w.md" | awk -F'\t' '$1 == 2 { print $5 }')" "planned"
run bash "$REG" add "$ROOT/w.md" $'Item\twith a tab'
check "add: a control character is refused" "$RC" "2"

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

# --- concurrent writers: every row update lands, the file keeps its mode ---
reg "$ROOT/many.md" '| 1 | A | - | - | open | - |' '| 2 | B | - | - | open | - |' '| 3 | C | - | - | open | - |' \
  '| 4 | D | - | - | open | - |' '| 5 | E | - | - | open | - |' '| 6 | F | - | - | open | - |'
chmod 664 "$ROOT/many.md"
mode_before=$(ls -l "$ROOT/many.md" | cut -c1-10)
for i in 1 2 3 4 5 6; do bash "$REG" set "$ROOT/many.md" "$i" done >/dev/null 2>&1 & done
for i in 1 2 3; do bash "$REG" add "$ROOT/many.md" "Added $i" >/dev/null 2>&1 & done
wait
check "concurrent sets: every row is done" "$(register_rows "$ROOT/many.md" | awk -F'\t' '$1 <= 6 && $5 == "done"' | grep -c .)" "6"
check "concurrent adds: three distinct new rows" "$(register_rows "$ROOT/many.md" | awk -F'\t' '$1 > 6 { print $1 }' | sort -u | grep -c .)" "3"
check "a rewrite keeps the file's mode" "$(ls -l "$ROOT/many.md" | cut -c1-10)" "$mode_before"

# The same, without flock: the lock directory serializes the writers.
reg "$ROOT/many-mkdir.md" '| 1 | A | - | - | open | - |' '| 2 | B | - | - | open | - |' '| 3 | C | - | - | open | - |' \
  '| 4 | D | - | - | open | - |' '| 5 | E | - | - | open | - |' '| 6 | F | - | - | open | - |'
# Nine writers queue for one lock, which on a Windows runner can outlast the
# default ten-second wait: a writer that gives up says so in its .err file.
for i in 1 2 3 4 5 6; do DR_LOCK_TENTHS=600 DFORGE_FLOCK=no-such-flock bash "$REG" set "$ROOT/many-mkdir.md" "$i" done >/dev/null 2>"$TMP/set-$i.err" & done
for i in 1 2 3; do DR_LOCK_TENTHS=600 DFORGE_FLOCK=no-such-flock bash "$REG" add "$ROOT/many-mkdir.md" "Added $i" >/dev/null 2>"$TMP/add-$i.err" & done
wait
check "no flock: concurrent sets: every row is done" "$(register_rows "$ROOT/many-mkdir.md" | awk -F'\t' '$1 <= 6 && $5 == "done"' | grep -c .)" "6"
check "no flock: no writer gave up" "$(cat "$TMP"/set-*.err "$TMP"/add-*.err)" ""
check "no flock: concurrent adds: three distinct new rows" "$(register_rows "$ROOT/many-mkdir.md" | awk -F'\t' '$1 > 6 { print $1 }' | sort -u | grep -c .)" "3"
check "no flock: the lock directory is gone" "$(find "$TMP" -name '*.lockd' | grep -c .)" "0"
check "a rewrite leaves no temporary file" "$(ls -A "$ROOT" | grep -c '^\.many')" "0"

# A register whose lock cannot be placed is not written, and no lock is left
# in the caller's working directory instead.
LR="$TMP/lockless-repo"; git init -q "$LR"
reg "$LR/r.md" '| 1 | A | - | - | open | - |'
touch "$(git -C "$LR" rev-parse --absolute-git-dir)/dforge"
mkdir "$TMP/elsewhere"
(cd "$TMP/elsewhere" && bash "$REG" set "$LR/r.md" 1 done >/dev/null 2>&1); set_rc=$?
(cd "$TMP/elsewhere" && bash "$REG" add "$LR/r.md" "Unlocked" >/dev/null 2>&1); add_rc=$?
check "an unlockable register: set and add exit 2" "$set_rc:$add_rc" "2:2"
check "an unlockable register is left unchanged" "$(register_rows "$LR/r.md" | cut -f1,5 | tr '\t\n' ': ')" "1:open "
check "an unlockable register leaves no lock in the working directory" "$(ls -A "$TMP/elsewhere")" ""

# A lock that is held by another writer is reported as that; a flock that fails
# for another reason is not.
BR="$TMP/busy-repo"; git init -q "$BR"
reg "$BR/r.md" '| 1 | A | - | - | open | - |'
BASE=$(. "$HERE/../scripts/lib/lock.sh"; dr_lock_base "$BR/r.md")
if command -v flock >/dev/null 2>&1; then
  flock "$BASE.lock" sleep 3 &
  sleep 0.5
  out=$(DR_LOCK_TENTHS=10 bash "$REG" set "$BR/r.md" 1 done 2>&1); rc=$?
  wait
  check "a busy lock: exit 1" "$rc" "1"
  check "a busy lock: says another process holds it" "$(grep -c 'is locked by another process' <<<"$out")" "1"
fi
printf '#!/bin/sh\nexit 64\n' > "$TMP/broken-flock"; chmod +x "$TMP/broken-flock"
out=$(DFORGE_FLOCK="$TMP/broken-flock" bash "$REG" set "$BR/r.md" 1 done 2>&1); rc=$?
check "a flock that fails: exit 1" "$rc" "1"
check "a flock that fails: is not called a busy lock" "$(grep -c 'locked by another process' <<<"$out")" "0"
check "a flock that fails: names the failure" "$(grep -c 'cannot lock .*flock exited 64' <<<"$out")" "1"
check "a flock that fails: leaves the register unchanged" "$(register_rows "$BR/r.md" | cut -f5)" "open"

# A register reached through a symbolic link is written through it: the link
# stays a link and its target changes.
mkdir "$TMP/linked"
reg "$TMP/linked/real.md" '| 1 | A | - | - | open | - |'
ln -s linked/real.md "$TMP/link.md"
run bash "$REG" set "$TMP/link.md" 1 done
check "a symlinked register: set exits 0" "$RC" "0"
check "a symlinked register: the link survives" "$([ -L "$TMP/link.md" ] && echo link || echo file)" "link"
check "a symlinked register: the target changes" "$(register_rows "$TMP/linked/real.md" | cut -f5)" "done"
check "a symlinked register shares its target's lock" \
  "$(. "$HERE/../scripts/lib/lock.sh"; [ "$(dr_lock_base "$TMP/link.md")" = "$(dr_lock_base "$TMP/linked/real.md")" ] && echo same || echo different)" "same"
# A link's ../ under a linked directory climbs from the directory it points to.
mkdir -p "$TMP/up/a" "$TMP/up/b"
ln -s "$TMP/up/b" "$TMP/up/a/d"
reg "$TMP/up/real.md" '| 1 | A | - | - | open | - |'
ln -s ../real.md "$TMP/up/b/x.md"
check "a link climbing out of a linked directory shares its target's lock" \
  "$(. "$HERE/../scripts/lib/lock.sh"; [ "$(dr_lock_base "$TMP/up/a/d/x.md")" = "$(dr_lock_base "$TMP/up/real.md")" ] && echo same || echo different)" "same"

# --- the repository's own registers ---
# They are load-bearing for three scripts and two skills, so one that stopped
# parsing would otherwise go unnoticed.
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
while IFS= read -r own; do
  [ -n "$own" ] || continue
  run bash "$REG" check "$own"
  check "own register parses: $(basename "$own")" "$RC" "0"
done < <(register_files "$REPO_ROOT")

# --- documents kept in darkmem: registers are listed and checked in the mirror ---
. "$HERE/fixtures/darkmem-stores.sh"
SH="$TMP/stores-home"; mkdir -p "$SH"
SR="$TMP/stores-repo"; git init -q "$SR"
M=$(stores_home "$SH" "$SR" proj darkmem local)
mkdir -p "$M/dforge/registers" "$M/dforge/specs"
printf '# A\n' > "$M/dforge/specs/a-design.md"
printf '# B\n' > "$M/dforge/specs/b-design.md"
reg "$M/dforge/registers/r.md" '| 1 | One | - | - | planned | - |'
check "register_files: the mirror's registers" "$(HOME=$SH register_files "$SR")" "$M/dforge/registers/r.md"
out=$(cd "$SR" && HOME=$SH bash "$HERE/../scripts/register" check "$M/dforge/registers/r.md" 2>&1)
check "register check: Covers names resolve in the mirror" "$(tail -n 1 <<<"$out")" "register: 0 errors"
out=$(cd "$SR" && HOME=$SH bash "$HERE/../scripts/register" open --spec docs/superpowers/specs/a-design.md 2>&1)
check "register open: the register is named, not pathed" "$out" "docs/dforge/registers/r.md: #1 One — planned, assigned -"

# --- a ConfigError stops register instead of reporting nothing open ---
BH="$TMP/bad-home"; mkdir -p "$BH/.dforge"
BR="$TMP/bad-repo"; git init -q "$BR"
printf '{"darkmem":{"url":"http://127.0.0.1:9","repos":{"%s":{"project":"p","documentStore":"bogus"}}}}\n' \
  "$(git -C "$BR" rev-parse --show-toplevel)" > "$BH/.dforge/config.json"
(cd "$BR" && HOME=$BH bash "$HERE/../scripts/register" open --spec docs/x.md >/dev/null 2>&1)
check "register open: a ConfigError exits 2" "$?" "2"
reg "$BR/r.md" '| 1 | One | - | - | planned | - |'
(cd "$BR" && HOME=$BH bash "$HERE/../scripts/register" check "$BR/r.md" >/dev/null 2>&1)
check "register check: a ConfigError exits 2" "$?" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
