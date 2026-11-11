#!/usr/bin/env bash
# Acceptance tests for the retained-review-data spec
# (docs/dforge/specs/2026-11-10-retained-review-data-design.md), the `test`
# statements A1-A9, A13 and A14. Each test is written from the statement's
# text and reaches the behaviour only through `scripts/review-record`'s
# command line: `ratio MERGE_BASE HEAD` and `retain PLAN_FILE [--from DIR]`.
# Usage:
#   bash retained-review-data.acceptance.test.sh           run every test
#   bash retained-review-data.acceptance.test.sh A5 A9     run the named tests only
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
RR="$PLUGIN/scripts/review-record"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
lacks() { # lacks <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}

TMP="$(mktemp -d)"
# Under MSYS_NO_PATHCONV, git.exe reads /tmp/... as a drive-root path; the
# long form matches the paths git prints, where TEMP is an 8.3 name.
if command -v cygpath >/dev/null 2>&1; then
  TMP=$(cygpath -m -l "$TMP" 2>/dev/null || cygpath -m "$TMP")
fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR DFORGE_DOCUMENT_STORE DFORGE_PROGRESS_STORE CLAUDE_PROJECT_DIR
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1 MSYS_NO_PATHCONV=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

lines() { # lines <n> [prefix] — n distinct text lines
  local i
  for ((i = 1; i <= $1; i++)); do printf '%sline %d\n' "${2:-}" "$i"; done
}
put() { # put <repo> <path> <n> — a text file of n lines
  mkdir -p "$(dirname "$1/$2")"
  lines "$3" "$2 " > "$1/$2"
}
newrepo() { # newrepo <dir> — a repository with one committed file
  git init -q -b main "$1"
  printf 'base\n' > "$1/base.txt"
  git -C "$1" add -A && git -C "$1" commit -q -m base
}
commit() { git -C "$1" add -A && git -C "$1" commit -q -m "$2"; }
ratio() { # ratio <repo> <base> <head> — runs in the repo; sets OUT, ERR, RC
  local errf="$TMP/ratio.err"
  OUT=$(cd "$1" && bash "$RR" ratio "$2" "$3" 2>"$errf"); RC=$?
  ERR=$(cat "$errf")
}
plugin_copy() { # plugin_copy <dir> — the plugin without its tests, to edit the lens in
  mkdir -p "$1"
  tar -C "$PLUGIN" --exclude=./tests -cf - . | tar -C "$1" -xf -
}
short() { git -C "$1" rev-parse --short=7 "$2"; }

# --- ratio -----------------------------------------------------------------

a1() {
  local R="$TMP/a1" base head
  newrepo "$R"; base=$(git -C "$R" rev-parse HEAD)
  put "$R" plugins/x/tests/a.test.sh 5
  put "$R" src/app.js 3
  put "$R" lib/util.py 4
  put "$R" web/button.spec.ts 2
  put "$R" pkg/test_thing.py 1
  put "$R" pkg/thing_test.go 6
  put "$R" pkg/__tests__/z.js 7
  put "$R" test/helper.rb 8
  commit "$R" head; head=$(git -C "$R" rev-parse HEAD)
  ratio "$R" "$base" "$head"
  check "A1: exit 0 on a diff of tests and code" "$RC" 0
  check "A1: the line counts test globs and other counted paths" "$OUT" \
    "Test ratio: 29 test / 7 code lines ($(short "$R" "$base")..$(short "$R" "$head"))"
  check "A1: prints exactly one line and nothing on stderr" "$(printf '%s' "$OUT" | wc -l | tr -d ' '):$ERR" "0:"

  R="$TMP/a1-zero"
  newrepo "$R"; base=$(git -C "$R" rev-parse HEAD)
  put "$R" tests/only.test.js 4
  commit "$R" head; head=$(git -C "$R" rev-parse HEAD)
  ratio "$R" "$base" "$head"
  check "A1: zero code lines exits 0" "$RC" 0
  check "A1: zero code lines prints the line" "$OUT" \
    "Test ratio: 4 test / 0 code lines ($(short "$R" "$base")..$(short "$R" "$head"))"

  R="$TMP/a1-writes-nothing"
  newrepo "$R"; base=$(git -C "$R" rev-parse HEAD)
  put "$R" src/a.js 2
  commit "$R" head; head=$(git -C "$R" rev-parse HEAD)
  ratio "$R" "$base" "$head"
  check "A1: ratio writes nothing into the repository" "$(git -C "$R" status --porcelain)" ""
}

a1_lens_globs() {
  local P="$TMP/a1-plug" R="$TMP/a1-lens" base head
  plugin_copy "$P"
  sed -i 's/^Applies: .*/Applies: paths *.check.js/' "$P/criteria/lenses/test-quality.md"
  newrepo "$R"; base=$(git -C "$R" rev-parse HEAD)
  put "$R" src/a.check.js 3
  put "$R" tests/b.test.js 5
  commit "$R" head; head=$(git -C "$R" rev-parse HEAD)
  OUT=$(cd "$R" && bash "$P/scripts/review-record" ratio "$base" "$head" 2>/dev/null); RC=$?
  check "A1: the test globs are the lens file's paths clause, read at run time" "$RC:$OUT" \
    "0:Test ratio: 3 test / 5 code lines ($(short "$R" "$base")..$(short "$R" "$head"))"
}

a2() {
  local R="$TMP/a2" base head
  newrepo "$R"; base=$(git -C "$R" rev-parse HEAD)
  put "$R" src/real.js 3
  put "$R" tests/real.test.js 2
  put "$R" fixtures/data.json 10
  put "$R" src/fixtures/sample.js 11
  put "$R" plugins/x/tests/fixtures/input.txt 12
  put "$R" snapshots/a.snap 13
  put "$R" tests/snapshots/b.snap 14
  put "$R" __snapshots__/c.snap 15
  put "$R" web/__snapshots__/d.test.js.snap 16
  put "$R" testdata/e.txt 17
  put "$R" pkg/testdata/f.go 18
  printf '%s\n' 'gen/*.js linguist-generated' 'out/** linguist-generated=true' > "$R/.gitattributes"
  put "$R" gen/bundle.js 19
  put "$R" out/deep/gen.ts 20
  put "$R" tests/gen.test.js 1
  printf 'tests/gen.test.js linguist-generated\n' >> "$R/.gitattributes"
  commit "$R" head; head=$(git -C "$R" rev-parse HEAD)
  ratio "$R" "$base" "$head"
  # .gitattributes itself is a counted code line: 2 lines + 1 appended = 3.
  check "A2: fixture, snapshot, testdata and generated paths appear in neither number" "$OUT" \
    "Test ratio: 2 test / 6 code lines ($(short "$R" "$base")..$(short "$R" "$head"))"
}

a3() {
  local R="$TMP/a3" base head f n=0
  newrepo "$R"; base=$(git -C "$R" rev-parse HEAD)
  put "$R" src/code.js 3
  put "$R" docs/guide.md 4
  put "$R" docs/dforge/specs/s.md 5
  put "$R" README.md 6
  put "$R" plugins/p/skills/s/SKILL.md 7
  for f in package-lock.json yarn.lock pnpm-lock.yaml bun.lock bun.lockb Cargo.lock poetry.lock \
           uv.lock Pipfile.lock Gemfile.lock composer.lock go.sum packages.lock.json flake.lock; do
    n=$((n + 1))
    put "$R" "$f" "$((n + 20))"
    put "$R" "sub/dir/$f" "$((n + 40))"
  done
  commit "$R" head; head=$(git -C "$R" rev-parse HEAD)
  ratio "$R" "$base" "$head"
  check "A3: docs/ and lock files are not code; Markdown outside docs/ is" "$OUT" \
    "Test ratio: 0 test / 16 code lines ($(short "$R" "$base")..$(short "$R" "$head"))"
}

a4() {
  local R="$TMP/a4" base head
  newrepo "$R"
  put "$R" src/old.js 20
  put "$R" src/pure.js 20
  put "$R" src/moved.js 20
  commit "$R" seed; base=$(git -C "$R" rev-parse HEAD)
  git -C "$R" mv src/old.js src/new.js
  sed -i '3s/.*/changed three/;4s/.*/changed four/' "$R/src/new.js"
  git -C "$R" mv src/pure.js src/pure-renamed.js
  mkdir -p "$R/tests"
  git -C "$R" mv src/moved.js tests/moved.test.js
  sed -i '5s/.*/one changed line/' "$R/tests/moved.test.js"
  head -c 64 /dev/zero > "$R/src/logo.png"
  head -c 64 /dev/zero > "$R/tests/blob.test.bin"
  commit "$R" head; head=$(git -C "$R" rev-parse HEAD)
  ratio "$R" "$base" "$head"
  check "A4: renames count their changed lines under the new path; binaries add nothing" "$OUT" \
    "Test ratio: 1 test / 2 code lines ($(short "$R" "$base")..$(short "$R" "$head"))"
}

# --- retain ----------------------------------------------------------------

ledger() { # ledger <checkout> <slug> <plan named> <line>...
  local dir="$1/.dforge/sdd/$2" named=$3
  shift 3
  mkdir -p "$dir"
  { printf '# SDD ledger — plan: %s\n' "$named"; printf '%s\n' "$@"; } > "$dir/progress.md"
}
repo_with_plan() { # repo_with_plan <dir> <slug> — a checkout holding the plan file
  git init -q -b main "$1"
  mkdir -p "$1/docs/dforge/plans"
  printf '# Plan %s\n' "$2" > "$1/docs/dforge/plans/$2.md"
  git -C "$1" add -A && git -C "$1" commit -q -m init
}
retain() { # retain <cwd> <args...> — sets OUT, ERR, RC
  local errf="$TMP/retain.err" cwd=$1
  shift
  OUT=$(cd "$cwd" && bash "$RR" retain "$@" 2>"$errf"); RC=$?
  ERR=$(cat "$errf")
}
exists() { if [ -e "$1" ]; then echo yes; else echo no; fi; }

DEPTH='Review depth: standard (interface)'
QA_DONE='Acceptance QA: complete — 5 pass, 0 fail, 0 flaky, 0 cannot-test, 1 demo'
QA_SKIP='Acceptance QA: skipped (depth light)'
LENS_SKIPPED='final review lens-skipped docs-comments reason=cap'
LENS_A='final review lens security — 0 Critical, 1 Important, 2 Minor; fixed 1, rejected 1'
LENS_B='final review lens test-quality — 0 Critical, 0 Important, 0 Minor; fixed 0, rejected 0'
RATIO_LINE='Test ratio: 40 test / 100 code lines (abc1234..def5678)'
FINAL='Final review: clean (commits abc1234..def5678, 1 parked)'

a5() {
  local R="$TMP/a5" S=2026-01-01-p target n want
  repo_with_plan "$R" "$S"
  ledger "$R" "$S" "docs/dforge/plans/$S.md" \
    "$DEPTH" \
    'Task 1: implementer impl-sonnet-high (assigned; base abc1234)' \
    "$QA_DONE" \
    "$LENS_SKIPPED" \
    "$LENS_A" \
    "$LENS_B" \
    "$RATIO_LINE" \
    "$FINAL"
  target="$R/docs/dforge/reviews/$S.md"
  retain "$R" "$R/docs/dforge/plans/$S.md"
  check "A5: exit 0 and the record's path on stdout" "$RC:$OUT" "0:$target"
  check "A5: the file is <docs>/reviews/<plan-basename>.md" "$(exists "$target")" yes
  has "A5: the file holds the plan's document name" "$(cat "$target" 2>/dev/null)" "docs/dforge/plans/$S.md"
  want=$(printf '%s\n' "$DEPTH" "$QA_DONE" "$LENS_SKIPPED" "$LENS_A" "$LENS_B" "$RATIO_LINE" "$FINAL")
  n=$(printf '%s\n' "$want" | wc -l | tr -d ' ')
  check "A5: every selected ledger line, verbatim and in ledger order, incl. lens-skipped and lens lines" \
    "$(tail -n "$n" "$target" 2>/dev/null)" "$want"
  has "A5: the lens-skipped line is retained" "$(cat "$target" 2>/dev/null)" "$LENS_SKIPPED"
  has "A5: a lens line is retained" "$(cat "$target" 2>/dev/null)" "$LENS_A"

  R="$TMP/a5-skipped"; S=2026-01-02-q
  repo_with_plan "$R" "$S"
  ledger "$R" "$S" "docs/dforge/plans/$S.md" \
    'Review depth: light (small change)' "$QA_SKIP" 'final review lenses off' "$RATIO_LINE" "$FINAL"
  target="$R/docs/dforge/reviews/$S.md"
  retain "$R" "$R/docs/dforge/plans/$S.md"
  want=$(printf '%s\n' 'Review depth: light (small change)' "$QA_SKIP" 'final review lenses off' "$RATIO_LINE" "$FINAL")
  check "A5: Acceptance QA: skipped and lenses-off lines are retained in order" \
    "$RC:$(tail -n 5 "$target" 2>/dev/null)" "0:$want"
}

a6() {
  local R="$TMP/a6" S=2026-01-03-r target body
  repo_with_plan "$R" "$S"
  ledger "$R" "$S" "docs/dforge/plans/$S.md" \
    "$DEPTH" \
    'Task 1: implementer impl-sonnet-high (assigned; base abc1234)' \
    'Task 1: fix round 1/2 (1 addressed, 0 open — a thing; commits abc1234..bcd2345)' \
    'Task 1: complete (commits abc1234..bcd2345, review clean) — done: x; verified: y → pass; remaining: none; discovered: none; assumptions: none' \
    'Task 2: parked — a finding — Ruling: the code stands' \
    'Task 2: Ruling: another finding — decided so — none' \
    'Ruling: amendment A1 — a reason — a cost' \
    'Acceptance QA: dispatched (base abc1234)' \
    "$QA_DONE" \
    'Final fix: implementer impl-sonnet-high (assigned; base abc1234)' \
    'Early CI: green run 7' \
    "$LENS_A" \
    "$FINAL"
  target="$R/docs/dforge/reviews/$S.md"
  retain "$R" "$R/docs/dforge/plans/$S.md"
  body=$(cat "$target" 2>/dev/null)
  check "A6: retain succeeds" "$RC" 0
  lacks "A6: Acceptance QA: dispatched is not retained" "$body" 'Acceptance QA: dispatched'
  lacks "A6: task lines are not retained" "$body" 'Task '
  lacks "A6: Ruling lines are not retained" "$body" 'Ruling:'
  lacks "A6: the ledger identity line is not retained" "$body" '# SDD ledger'
  lacks "A6: Final fix lines are not retained" "$body" 'Final fix:'
  lacks "A6: Early CI lines are not retained" "$body" 'Early CI:'
  has "A6: the selected lines around them are retained" "$body" "$QA_DONE"
  has "A6: the lens line is retained" "$body" "$LENS_A"
}

a7() {
  local T="$TMP/a7" W="$TMP/a7-wt" S=2026-01-04-s TOP WT target
  repo_with_plan "$T" "$S"
  git -C "$T" worktree add -q -b wt "$W"
  TOP=$(git -C "$T" rev-parse --show-toplevel); WT=$(git -C "$W" rev-parse --show-toplevel)
  ledger "$WT" "$S" "docs/dforge/plans/$S.md" "$DEPTH" "$QA_DONE" "$LENS_A" "$FINAL"
  target="$TOP/docs/dforge/reviews/$S.md"
  check "A7: the primary checkout has no ledger of its own" "$(exists "$TOP/.dforge/sdd/$S/progress.md")" no

  retain "$TOP" "$TOP/docs/dforge/plans/$S.md" --from "$WT"
  check "A7: --from <worktree>: exit 0 and the primary checkout's record path" "$RC:$OUT" "0:$target"
  check "A7: --from <worktree>: the record holds the worktree ledger's lines" \
    "$(tail -n 4 "$target" 2>/dev/null)" "$(printf '%s\n' "$DEPTH" "$QA_DONE" "$LENS_A" "$FINAL")"
  check "A7: --from <worktree>: nothing is written into the worktree's <docs>" \
    "$(exists "$WT/docs/dforge/reviews/$S.md")" no

  rm -f "$target"
  retain "$TOP" "$TOP/docs/dforge/plans/$S.md"
  check "A7: no --from: exit 0 and the primary checkout's record path" "$RC:$OUT" "0:$target"
  check "A7: no --from: the record holds the worktree ledger's lines" \
    "$(tail -n 4 "$target" 2>/dev/null)" "$(printf '%s\n' "$DEPTH" "$QA_DONE" "$LENS_A" "$FINAL")"
  check "A7: no --from: nothing is written into the worktree's <docs>" \
    "$(exists "$WT/docs/dforge/reviews/$S.md")" no
}

a8() {
  local T="$TMP/a8" W="$TMP/a8-wt" S=2026-01-05-t TOP WT
  repo_with_plan "$T" "$S"
  git -C "$T" worktree add -q -b wt "$W"
  TOP=$(git -C "$T" rev-parse --show-toplevel); WT=$(git -C "$W" rev-parse --show-toplevel)

  retain "$TOP" "$TOP/docs/dforge/plans/$S.md"
  check "A8: no ledger anywhere: exit 4" "$RC" 4
  has "A8: exit 4 names the primary checkout's ledger path" "$ERR" "$TOP/.dforge/sdd/$S/progress.md"
  has "A8: exit 4 names the linked worktree's ledger path" "$ERR" "$WT/.dforge/sdd/$S/progress.md"
  check "A8: exit 4 writes no file" "$(exists "$TOP/docs/dforge/reviews")" no

  retain "$TOP" "$TOP/docs/dforge/plans/$S.md" --from "$WT"
  check "A8: --from with no ledger there: exit 4" "$RC" 4
  has "A8: --from exit 4 names the path searched" "$ERR" "$WT/.dforge/sdd/$S/progress.md"
  check "A8: --from exit 4 writes no file" "$(exists "$TOP/docs/dforge/reviews")" no

  ledger "$WT" "$S" "docs/dforge/plans/$S.md" \
    'Task 1: implementer impl-sonnet-high (assigned; base abc1234)' \
    'Task 1: complete (commits abc1234..bcd2345, review clean) — done: x; verified: y → pass; remaining: none; discovered: none; assumptions: none' \
    'Acceptance QA: dispatched (base abc1234)' \
    'Ruling: a thing — a reason — a cost'
  retain "$TOP" "$TOP/docs/dforge/plans/$S.md" --from "$WT"
  check "A8: a ledger with no selected lines (--from): exit 3" "$RC" 3
  check "A8: exit 3 writes no file" "$(exists "$TOP/docs/dforge/reviews/$S.md")" no
  retain "$TOP" "$TOP/docs/dforge/plans/$S.md"
  check "A8: a ledger with no selected lines (no --from): exit 3" "$RC" 3
  check "A8: exit 3 writes no file (no --from)" "$(exists "$TOP/docs/dforge/reviews/$S.md")" no
  check "A8: exit 3 leaves no stray file under reviews/" \
    "$(ls -A "$TOP/docs/dforge/reviews" 2>/dev/null | wc -l | tr -d ' ')" 0
}

a9() {
  local R="$TMP/a9" S=2026-01-06-u target
  repo_with_plan "$R" "$S"
  target="$R/docs/dforge/reviews/$S.md"
  ledger "$R" "$S" "docs/dforge/plans/$S.md" "$DEPTH" "$FINAL"
  retain "$R" "$R/docs/dforge/plans/$S.md"
  check "A9: the first retain succeeds" "$RC" 0
  ledger "$R" "$S" "docs/dforge/plans/$S.md" "$DEPTH" "$QA_DONE" "$LENS_A" "$RATIO_LINE" "$FINAL"
  retain "$R" "$R/docs/dforge/plans/$S.md"
  check "A9: the second retain succeeds and prints the same path" "$RC:$OUT" "0:$target"
  check "A9: the second retain replaced the file" "$(tail -n 5 "$target" 2>/dev/null)" \
    "$(printf '%s\n' "$DEPTH" "$QA_DONE" "$LENS_A" "$RATIO_LINE" "$FINAL")"
  check "A9: the replaced file holds no line twice" \
    "$(grep -cF "$FINAL" "$target" 2>/dev/null)" 1
  check "A9: exactly one file is left for the plan" \
    "$(ls -A "$R/docs/dforge/reviews" | wc -l | tr -d ' '):$(ls -A "$R/docs/dforge/reviews")" "1:$S.md"
}

a13() {
  local T="$TMP/a13" W="$TMP/a13-wt" S=2026-01-07-v TOP WT target
  repo_with_plan "$T" "$S"
  mkdir -p "$T/docs/dforge/plans/old"
  printf '# Old plan\n' > "$T/docs/dforge/plans/old/$S.md"
  git -C "$T" add -A && git -C "$T" commit -q -m old
  git -C "$T" worktree add -q -b wt "$W"
  TOP=$(git -C "$T" rev-parse --show-toplevel); WT=$(git -C "$W" rev-parse --show-toplevel)
  target="$TOP/docs/dforge/reviews/$S.md"
  ledger "$TOP" "$S" "docs/dforge/plans/old/$S.md" 'Review depth: full (stale ledger line)' 'Final review: clean (commits 1111111..2222222)'

  retain "$TOP" "$TOP/docs/dforge/plans/$S.md"
  check "A13: only a stale ledger under the same basename: exit 4" "$RC" 4
  check "A13: the stale ledger is not retained" "$(exists "$target")" no
  retain "$TOP" "$TOP/docs/dforge/plans/$S.md" --from "$TOP"
  check "A13: --from a checkout holding only the stale ledger: exit 4" "$RC" 4
  check "A13: --from the stale ledger writes no file" "$(exists "$target")" no

  ledger "$WT" "$S" "docs/dforge/plans/$S.md" "$DEPTH" "$FINAL"
  retain "$TOP" "$TOP/docs/dforge/plans/$S.md"
  check "A13: the real ledger in a worktree is found past the stale one" "$RC:$OUT" "0:$target"
  check "A13: the record comes from the real ledger" "$(tail -n 2 "$target" 2>/dev/null)" "$(printf '%s\n' "$DEPTH" "$FINAL")"
  lacks "A13: no line of the stale ledger is retained" "$(cat "$target" 2>/dev/null)" 'stale ledger line'
}

a14() {
  local P="$TMP/a14-plug" R="$TMP/a14" base head lens
  plugin_copy "$P"
  lens="$P/criteria/lenses/test-quality.md"
  newrepo "$R"; base=$(git -C "$R" rev-parse HEAD)
  put "$R" tests/a.test.js 2
  put "$R" src/b.js 3
  commit "$R" head; head=$(git -C "$R" rev-parse HEAD)

  OUT=$(cd "$R" && bash "$P/scripts/review-record" ratio "$base" "$head" 2>/dev/null); RC=$?
  check "A14: the unmodified lens copy still prints (the copy is a valid test bed)" "$RC:$OUT" \
    "0:Test ratio: 2 test / 3 code lines ($(short "$R" "$base")..$(short "$R" "$head"))"

  sed -i 's/^Applies: .*/Applies: added ^[[:space:]]*assert/' "$lens"
  OUT=$(cd "$R" && bash "$P/scripts/review-record" ratio "$base" "$head" 2>/dev/null); RC=$?
  check "A14: an Applies line with no paths clause: exit 2" "$RC" 2
  check "A14: an Applies line with no paths clause: no line on stdout" "$OUT" ""

  sed -i 's/^Applies: .*/Applies: always/' "$lens"
  OUT=$(cd "$R" && bash "$P/scripts/review-record" ratio "$base" "$head" 2>/dev/null); RC=$?
  check "A14: Applies: always (no paths clause): exit 2 and no line" "$RC:$OUT" "2:"

  sed -i '/^Applies: /d' "$lens"
  OUT=$(cd "$R" && bash "$P/scripts/review-record" ratio "$base" "$head" 2>/dev/null); RC=$?
  check "A14: a lens file with no Applies line: exit 2 and no line" "$RC:$OUT" "2:"

  rm -f "$lens"
  OUT=$(cd "$R" && bash "$P/scripts/review-record" ratio "$base" "$head" 2>/dev/null); RC=$?
  check "A14: a missing lens file: exit 2 and no line" "$RC:$OUT" "2:"
}

ALL="a1 a1_lens_globs a2 a3 a4 a5 a6 a7 a8 a9 a13 a14"
if [ $# -gt 0 ]; then
  sel=""
  for t in "$@"; do
    t=$(printf '%s' "$t" | tr 'A-Z' 'a-z')
    sel="$sel $t"
    [ "$t" != a1 ] || sel="$sel a1_lens_globs"
  done
  ALL=$sel
fi
for t in $ALL; do "$t"; done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
