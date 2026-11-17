#!/usr/bin/env bash
# Acceptance tests for the measured-proposals spec
# (docs/dforge/specs/2026-11-15-measured-proposals-design.md), the `test`
# statements A1-A12. Each test is written from the statement's text and
# reaches the behaviour only through the command lines of scripts/plan-lint,
# scripts/plan-amend, scripts/lens-route, scripts/dforge-config and
# scripts/task-step.
# Usage:
#   bash measured-proposals.acceptance.test.sh           run every test
#   bash measured-proposals.acceptance.test.sh A5 A9     run the named tests only
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../plugins/dforge" && pwd)"
LINT="$PLUGIN/scripts/plan-lint"
AMEND="$PLUGIN/scripts/plan-amend"
ROUTE="$PLUGIN/scripts/lens-route"
CONFIG="$PLUGIN/scripts/dforge-config"
STEP="$PLUGIN/scripts/task-step"

ALL="A1 A2 A3 A4 A5 A6 A7 A8 A9 A10 A11 A12"
sel=""
for n in "$@"; do
  n=$(tr 'a-z' 'A-Z' <<<"$n")
  case " $ALL " in
    *" $n "*) sel="$sel $n" ;;
    *) printf 'measured-proposals.acceptance.test.sh: unknown test %s (tests: %s)\n' "$n" "$ALL" >&2; exit 2 ;;
  esac
done
[ $# -gt 0 ] || sel=$ALL
want() { case " $sel " in *" $1 "*) return 0 ;; esac; return 1; }

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
if command -v cygpath >/dev/null 2>&1; then
  TMP=$(cygpath -m -l "$TMP" 2>/dev/null || cygpath -m "$TMP")
fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR DFORGE_DOCUMENT_STORE DFORGE_PROGRESS_STORE CLAUDE_PROJECT_DIR \
  DFORGE_LENS_CAP DFORGE_LENS_MINOR_FROM
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1 MSYS_NO_PATHCONV=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

# --- plan fixtures for plan-lint and plan-amend ----------------------------

plan_head() { # plan_head <task count> — the header block and the task index
  cat <<'EOF'
# Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names.

**Goal:** Demo.

**Spec:** `docs/spec.md`

**Execution:** inline — `claude --model sonnet --effort high` — every task scores 1

**Task check:** `bash quick.sh` — gate 1 has Tier: task

**Integration check:** `bash test.sh`

**CI:** none

**Plan review:** 2026-09-12 — dforge:judge-fable — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)

## Global Constraints

- Bash only.

## Contracts

None

## Assumptions (evidence)

- None.

## Task index

EOF
  local i
  for ((i = 1; i <= $1; i++)); do printf '%d. Thing %d\n' "$i" "$i"; done
  printf '\n'
}
mkplan() { # mkplan <task spec>... — spec: "<step 1 heading>;;<Files line>;;<Files line>..."
  plan_head "$#"
  local spec i=0
  for spec in "$@"; do
    i=$((i + 1))
    printf '%s\n' "$spec" | awk -F';;' -v n="$i" '{
      printf "### Task %d: Thing %d\n\n**Files:**\n", n, n
      for (k = 2; k <= NF; k++) printf "%s\n", $k
      printf "\n**Implementer:** dforge:impl-sonnet-high\n"
      printf "**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\n"
      printf "- [ ] **Step 1: %s**\n\nWork item %d prints hello.\n\n", $1, n
    }'
  done
}

WT='Write the failing test'
NT='No new test, because the change is prose'

LR="$TMP/lintrepo"
setup_lint_repo() {
  git init -q -b main "$LR"
  mkdir -p "$LR/docs" "$LR/t" "$LR/tests"
  printf '# Spec\n' > "$LR/docs/spec.md"
  printf 'l1\nl2\nl3\n' > "$LR/a.txt"
  printf 'l1\nl2\nl3' > "$LR/u.txt"
  : > "$LR/empty.txt"
  seq 1 80 | sed 's/^/row /' > "$LR/big.txt"
  seq 1 9 > "$LR/t/b.test.sh"
  git -C "$LR" add -A && git -C "$LR" commit -q -m base
}
lint() { # lint <task spec>... — sets out (ERROR prefix normalised) and status
  mkplan "$@" > "$LR/docs/plan.md"
  out=$(cd "$LR" && bash "$LINT" docs/plan.md 2>&1); status=$?
  out=$(sed -E 's/^ERROR:? /ERROR /' <<<"$out")
}
T1="$WT;;- Create: \`made.txt\`"

# --- A1 --------------------------------------------------------------------

a1() {
  setup_lint_repo
  lint "$T1" "$WT;;- Modify: \`a.txt\`"
  check "A1: baseline plan with existing Modify path lints clean" "$status" "0"

  lint "$T1" "$WT;;- Modify: \`missing.txt\`"
  check "A1: a missing Modify path exits 1" "$status" "1"
  has "A1: a missing Modify path is an ERROR naming the task and path" "$out" "ERROR Task 2: missing.txt does not exist"
  lint "$T1" "$NT;;- Test: \`tests/missing.test.sh\`"
  has "A1: a missing Test path of a task that writes no failing test is an ERROR" "$out" "ERROR Task 2: tests/missing.test.sh does not exist"
  check "A1: a missing Test path exits 1" "$status" "1"

  lint "$T1" "$WT;;- Modify: \`later.txt\`" "$WT;;- Create: \`later.txt\`"
  has "A1: a path a higher-numbered task creates is an ERROR" "$out" "ERROR Task 2: later.txt does not exist"
  lacks "A1: the creating task itself is not flagged" "$out" "Task 3: later.txt does not exist"

  lint "$T1" "$WT;;- Modify: \`tests/later.test.sh\`" "$WT;;- Test: \`tests/later.test.sh\`"
  has "A1: a Test path a higher-numbered Write-the-failing-test task creates is an ERROR" "$out" "ERROR Task 2: tests/later.test.sh does not exist"

  lint "$NT;;- Create: \`made.txt\`" "$NT;;- Test: \`tests/prose.test.sh\`" "$WT;;- Modify: \`tests/prose.test.sh\`"
  has "A1: a Test path of a task that writes no failing test does not count as created" "$out" "ERROR Task 3: tests/prose.test.sh does not exist"

  lint "$T1" "$WT;;- Modify: \`a.txt\`;;- Modify: \`gone1.txt\`;;- Modify: \`gone2.txt\`"
  has "A1: every missing Modify path is reported (first)" "$out" "ERROR Task 2: gone1.txt does not exist"
  has "A1: every missing Modify path is reported (second)" "$out" "ERROR Task 2: gone2.txt does not exist"
  lacks "A1: an existing Modify path is not reported" "$out" "a.txt does not exist"
}

# --- A2 --------------------------------------------------------------------

a2() {
  setup_lint_repo
  lint "$T1" "$WT;;- Create: \`new1.txt\`;;- Modify: \`a.txt\`"
  lacks "A2: a Create path is not checked" "$out" "new1.txt does not exist"
  check "A2: a Create path leaves the plan clean" "$status" "0"

  lint "$T1" "$WT;;- Delete: \`gone.txt\`;;- Modify: \`a.txt\`"
  lacks "A2: a Delete path is not checked" "$out" "gone.txt does not exist"
  check "A2: a Delete path leaves the plan clean" "$status" "0"

  lint "$T1" "$WT;;- Modify: \`made.txt\`"
  lacks "A2: a path an earlier task creates is not an error" "$out" "made.txt does not exist"
  check "A2: an earlier Create leaves the plan clean" "$status" "0"

  lint "$T1" "$WT;;- Modify: \`x/y.txt\`;;- Create: \`x/y.txt\`"
  lacks "A2: a path the same task creates is not an error" "$out" "x/y.txt does not exist"

  lint "$T1" "$WT;;- Test: \`tests/new.test.sh\`"
  lacks "A2: a Test path of a Write-the-failing-test task is not an error" "$out" "tests/new.test.sh does not exist"
  check "A2: a new Test path leaves the plan clean" "$status" "0"

  lint "$WT;;- Test: \`tests/earlier.test.sh\`" "$NT;;- Modify: \`tests/earlier.test.sh\`"
  lacks "A2: a Test path of an earlier Write-the-failing-test task counts as created" "$out" "tests/earlier.test.sh does not exist"

  lint "$T1" "$WT;;- Modify: \`src/*.sh\`"
  lacks "A2: a first span holding * is not checked" "$out" "does not exist"
  check "A2: a * span leaves the plan clean" "$status" "0"
  lint "$T1" "$NT;;- Test: \`tests/*.test.sh\`"
  lacks "A2: a * span on a Test line is not checked" "$out" "does not exist"
}

# --- A3 --------------------------------------------------------------------

range_bad() { # range_bad <file> <range> [Modify|Test]
  local kind=${3:-Modify} step=$WT
  [ "$kind" != Test ] || step=$NT
  lint "$T1" "$step;;- $kind: \`$1:$2\`"
  check "A3: $kind $1:$2 exits 1" "$status" "1"
  has "A3: $kind $1:$2 is an ERROR naming the task and range" "$out" "ERROR Task 2: $1:$2 "
}
range_ok() { # range_ok <file> <range> [Modify|Test]
  local kind=${3:-Modify} step=$WT
  [ "$kind" != Test ] || step=$NT
  lint "$T1" "$step;;- $kind: \`$1:$2\`"
  check "A3: $kind $1:$2 passes" "$status" "0"
  lacks "A3: $kind $1:$2 reports no range error" "$out" "ERROR Task 2"
}
a3() {
  setup_lint_repo
  range_bad a.txt 0
  range_bad a.txt 0-2
  range_bad a.txt 3-2
  range_bad a.txt 4
  range_bad a.txt 2-4
  range_bad a.txt 1-2,5
  range_bad a.txt 1-2,3-1
  range_bad a.txt 1-2,0
  range_bad a.txt 5,1-2
  range_bad u.txt 4
  range_bad u.txt 1-4
  range_bad empty.txt 1
  range_bad big.txt 35-44,66-92
  range_bad t/b.test.sh 1-99 Test
  range_bad t/b.test.sh 0 Test
  range_bad t/b.test.sh 5-4 Test

  range_ok a.txt 1
  range_ok a.txt 3
  range_ok a.txt 1-3
  range_ok a.txt 2-2
  range_ok a.txt 1-2,3
  range_ok a.txt 1,2,3
  range_ok a.txt 1-1,2-3
  range_ok u.txt 3
  range_ok u.txt 1-3
  range_ok big.txt 35-44,66-72
  range_ok big.txt 80
  range_ok t/b.test.sh 1-9 Test
  range_ok t/b.test.sh 9 Test

  lint "$T1" "$WT;;- Create: \`made.txt:40-50\`"
  check "A3: a range on a created path is not checked" "$status" "0"
}

# --- A4 --------------------------------------------------------------------

AR="$TMP/amendrepo"
amend_entry() { # amend_entry <file> <old> <new>
  printf '## A? — Task 2\nReason: the plan says the wrong thing\nCost if wrong: one fix round\n### Old\n````text\n%s\n````\n### New\n````text\n%s\n````\n' \
    "$2" "$3" > "$1"
}
a4() {
  git init -q -b main "$AR"
  mkdir -p "$AR/docs" "$AR/t"
  printf '# Spec\n' > "$AR/docs/spec.md"
  printf 'l1\nl2\nl3\n' > "$AR/a.txt"
  printf 'l1\nl2\nl3' > "$AR/u.txt"
  git -C "$AR" add -A && git -C "$AR" commit -q -m base

  mkplan "$T1" "$WT;;- Modify: \`missing.txt\`;;- Modify: \`a.txt:9-12\`;;- Modify: \`u.txt:1-3\`" > "$AR/docs/plan.md"
  local before
  before=$(cd "$AR" && bash "$LINT" docs/plan.md 2>&1 | sed -E 's/^ERROR:? /ERROR /'); status=$?
  has "A4: setup: the plan already has a path error" "$before" "ERROR Task 2: missing.txt does not exist"
  has "A4: setup: the plan already has a range error" "$before" "ERROR Task 2: a.txt:9-12 "

  amend_entry "$TMP/b1.md" 'Work item 2 prints hello.' 'Work item 2 prints hello twice.'
  out=$(cd "$AR" && bash "$AMEND" docs/plan.md "$TMP/b1.md" 2>&1); status=$?
  check "A4: an amendment to a plan with earlier path errors: exit 0" "$status" "0"
  check "A4: an amendment to a plan with earlier path errors: output" "$out" "amended: A1 Task 2"

  amend_entry "$TMP/b2.md" '- Modify: `missing.txt`' '- Modify: `missing.txt`
- Modify: `a.txt`'
  out=$(cd "$AR" && bash "$AMEND" docs/plan.md "$TMP/b2.md" 2>&1); status=$?
  check "A4: a second amendment that adds no error: exit 0" "$status" "0"

  amend_entry "$TMP/b3.md" '- Modify: `u.txt:1-3`' '- Modify: `u.txt:1-30`'
  out=$(cd "$AR" && bash "$AMEND" docs/plan.md "$TMP/b3.md" 2>&1); status=$?
  check "A4: an amendment that adds a range error is rejected (exit 1)" "$status" "1"
}

# --- lens-route fixtures ---------------------------------------------------

LRR="$TMP/lensrepo"
setup_lens_repo() { # setup_lens_repo [dir] — a repository with one empty base commit and the plans
  LRR=${1:-$TMP/lensrepo}
  git init -q -b main "$LRR"
  git -C "$LRR" config user.email t@example.invalid
  git -C "$LRR" config user.name t
  git -C "$LRR" commit -q --allow-empty -m base
  LBASE=$(git -C "$LRR" rev-parse HEAD)
  mkdir -p "$LRR/specs"
  local d r
  for d in light standard full; do
    printf '# Spec\n\n**Depth:** %s — fixture\n' "$d" > "$LRR/specs/$d.md"
    lens_plan "$d" 0 > "$LRR/$d-plan.md"
  done
  lens_plan light 3 "security, lang-bash, type-design, docs-comments, lang-python, lang-csharp, lang-typescript" > "$LRR/task-plan.md"
  { printf 'Host: codex\nRouting policy: codex-v4\n\n'; lens_plan light 3 "security, lang-bash"; } > "$LRR/codex-plan.md"
}
lens_plan() { # lens_plan <depth> <risk> [lenses] — a one-task plan on that depth's spec
  printf '# Lens Fixture Plan\n\n**Spec:** `specs/%s.md`\n\n## Task index\n\n1. only\n\n### Task 1: only\n\n' "$1"
  printf '**Evaluation:** files 0 - spec 0 - coupling 0 - risk %s = %s\n' "$2" "$2"
  [ -z "${3:-}" ] || printf '**Lenses:** %s\n' "$3"
}
change() { # change <path> <content> — start from nothing: commit one file on a fresh branch off base
  mkdir -p "$(dirname "$LRR/$1")"
  printf '%s\n' "$2" > "$LRR/$1"
}
newchange() { # newchange — a fresh branch off base with a clean tree
  git -C "$LRR" checkout -q -f -B work "$LBASE"
  git -C "$LRR" clean -fdq -e '*-plan.md' -e specs -e docs
}
commit_change() { git -C "$LRR" add -A . ':!*-plan.md' ':!specs' && git -C "$LRR" commit -q -m change; LHEAD=$(git -C "$LRR" rev-parse HEAD); }
route() { # route <plan> — sets out, status; the final route for LBASE..LHEAD
  out=$(cd "$LRR" && bash "$ROUTE" "$1" --final "$LBASE" "$LHEAD" 2>&1); status=$?
}
lens_lines() { grep -E '^lens ' <<<"$out" | sed -E 's/ criteria=[^ ]*//; s/ parts=[^ ]*//; s/ seat=[^ ]*//; s/ reason=.*$//' | tr '\n' ';'; }
part_ids() { sed -n 's/^lens code-quality parts=\([^ ]*\) .*/\1/p' <<<"$out" | tr ',' '\n' | sed -E 's#.*/##; s/\.md$//' | tr '\n' ' '; }

all_parts_change() {
  newchange
  change scripts/foo.sh 'echo hi'
  change src/x.py 'print(1)'
  change lib/a.cs 'class A {}'
  change src/b.ts 'const v = 1;'
  change src/types.txt 'export interface Foo { x: number }'
  change README.md 'Docs.'
  commit_change
}

# --- A5 --------------------------------------------------------------------

a5() {
  setup_lens_repo
  all_parts_change
  route standard-plan.md
  check "A5: exit 0" "$status" "0"
  check "A5: exactly one code-quality line" "$(grep -c 'code-quality' <<<"$out")" "1"
  check "A5: that line is a lens line with parts" "$(grep -c '^lens code-quality parts=' <<<"$out")" "1"
  check "A5: parts are every matching part, lang-* alphabetical, type-design, docs-comments" "$(part_ids)" \
    "lang-bash lang-csharp lang-python lang-typescript type-design docs-comments "
  check "A5: each parts path is the part's criteria file" "$(sed -n 's/^lens code-quality parts=\([^ ]*\) .*/\1/p' <<<"$out" | tr ',' '\n' | while read -r p; do [ -f "$p" ] && printf 'y' || printf 'n'; done)" "yyyyyy"
  check "A5: no lens or lens-skipped line for a part id" "$(grep -cE '^lens(-skipped)? (lang-|type-design|docs-comments)' <<<"$out")" "0"
  check "A5: the lens line carries the judge seat" "$(grep -c '^lens code-quality parts=[^ ]* seat=dforge:judge-sonnet-high reason=' <<<"$out")" "1"

  newchange
  change src/x.py 'print(1)'
  change README.md 'Docs.'
  commit_change
  route standard-plan.md
  check "A5: only the matching parts are listed" "$(part_ids)" "lang-python docs-comments "
  check "A5: still one code-quality line" "$(grep -c 'code-quality' <<<"$out")" "1"

  newchange
  change src/types.txt 'export interface Foo { x: number }'
  commit_change
  route standard-plan.md
  check "A5: a part that matches on added lines alone is listed" "$(part_ids)" "type-design "

  newchange
  change src/b.ts 'const v = 1;'
  change lib/a.cs 'int x = 1;'
  change src/x.py 'print(1)'
  commit_change
  route full-plan.md
  check "A5: at full depth the lang-* parts come in alphabetical order" "$(part_ids)" "lang-csharp lang-python lang-typescript "
  check "A5: at full depth one code-quality line" "$(grep -c '^lens code-quality parts=' <<<"$out")" "1"
}

# --- A6 --------------------------------------------------------------------

a6() {
  setup_lens_repo
  newchange
  change scripts/foo.sh 'cmd 2>/dev/null'
  change tests/a.test.sh 'echo test'
  commit_change
  route standard-plan.md
  check "A6: exit 0" "$status" "0"
  check "A6: lens lines for security, silent-failures, test-quality and code-quality" "$(lens_lines)" \
    "lens security;lens silent-failures;lens test-quality;lens code-quality;"
  check "A6: no reason=cap line" "$(grep -c 'reason=cap' <<<"$out")" "0"
}

# --- A7 --------------------------------------------------------------------

a7() {
  setup_lens_repo
  mkdir -p "$LRR/docs/dforge/ui-ux"
  printf '# UI profile\n\n**Platform:** web\n' > "$LRR/docs/dforge/ui-ux/profile.md"
  newchange
  change src/App.tsx 'const v = a ?? b;'
  change tests/app.test.ts 'test("x", () => {});'
  commit_change
  route full-plan.md
  check "A7: lensCap unset keeps five lenses at full depth" "$(lens_lines)" \
    "lens security;lens ui-ux;lens silent-failures;lens test-quality;lens code-quality;"
  check "A7: lensCap unset prints no reason=cap line" "$(grep -c 'reason=cap' <<<"$out")" "0"
  out=$(cd "$LRR" && DFORGE_LENS_CAP=4 bash "$ROUTE" full-plan.md --final "$LBASE" "$LHEAD" 2>&1)
  check "A7: lensCap 4 skips the fifth lens for the cap" "$(grep -c '^lens-skipped code-quality reason=cap$' <<<"$out")" "1"
  out=$(cd "$LRR" && DFORGE_LENS_CAP=5 bash "$ROUTE" full-plan.md --final "$LBASE" "$LHEAD" 2>&1)
  check "A7: an explicit lensCap of 5 prints the same five lenses" "$(lens_lines)" \
    "lens security;lens ui-ux;lens silent-failures;lens test-quality;lens code-quality;"

  out=$(bash "$CONFIG" get lensCap 2>&1)
  check "A7: dforge-config get lensCap prints 5" "$out" "5"
  out=$(bash "$CONFIG" get --json 2>&1)
  check "A7: dforge-config get --json reports lensCap 5" "$(grep -cE '"lensCap": *5([^0-9]|$)' <<<"$out")" "1"
}

# --- A8 --------------------------------------------------------------------

a8() {
  setup_lens_repo
  newchange
  change scripts/foo.sh 'echo hi'
  commit_change
  route light-plan.md
  check "A8: exit 0" "$status" "0"
  check "A8: light depth prints lens-skipped code-quality reason=depth" "$(grep -c '^lens-skipped code-quality reason=depth$' <<<"$out")" "1"
  check "A8: light depth prints no code-quality lens line" "$(grep -c '^lens code-quality' <<<"$out")" "0"
  check "A8: security still runs at light depth" "$(grep -c '^lens security ' <<<"$out")" "1"

  all_parts_change
  route light-plan.md
  check "A8: with every part applying, still one skipped line for the depth" "$(grep -c '^lens-skipped code-quality reason=depth$' <<<"$out")" "1"
  check "A8: with every part applying, no code-quality lens line" "$(grep -c '^lens code-quality' <<<"$out")" "0"
}

# --- A9 --------------------------------------------------------------------

a9() {
  setup_lens_repo
  newchange
  change data.json '{}'
  commit_change
  local p
  for p in light standard full; do
    route "$p-plan.md"
    check "A9: no part applies at $p depth: exit 0" "$status" "0"
    check "A9: no part applies at $p depth: no code-quality line of either kind" "$(grep -c 'code-quality' <<<"$out")" "0"
  done
  newchange
  change notes.txt 'plain words'
  commit_change
  route standard-plan.md
  check "A9: a text file no part matches: no code-quality line" "$(grep -c 'code-quality' <<<"$out")" "0"
}

# --- A10 -------------------------------------------------------------------

a10() {
  setup_lens_repo
  out=$(cd "$LRR" && bash "$ROUTE" task-plan.md --task 1 2>&1); status=$?
  check "A10: --task exits 0" "$status" "0"
  check "A10: one lens line per part id on the Lenses line, in order" "$(sed -E 's/ criteria=.*$//' <<<"$out" | tr '\n' ';')" \
    "lens security;lens lang-bash;lens type-design;lens docs-comments;lens lang-python;lens lang-csharp;lens lang-typescript;"
  check "A10: every line has the form lens <id> criteria=<path>" "$(grep -cE '^lens [a-z-]+ criteria=[^ ]+$' <<<"$out")" "7"
  check "A10: each criteria path is the id's lens file" "$(while read -r _ id crit; do p=${crit#criteria=}; [ -f "$p" ] && [ "${p##*/}" = "$id.md" ] && printf y || printf n; done <<<"$out")" "yyyyyyy"
  check "A10: no code-quality line under --task" "$(grep -c 'code-quality' <<<"$out")" "0"
}

# --- A11 -------------------------------------------------------------------

a11() {
  setup_lens_repo
  newchange
  change scripts/foo.sh 'echo hi'
  commit_change
  route light-plan.md
  check "A11: setup: the same plan without Host: codex routes (exit 0)" "$status" "0"
  route codex-plan.md
  check "A11: a Host: codex plan exits 2 on --final" "$status" "2"
  out=$(cd "$LRR" && bash "$ROUTE" codex-plan.md --final "$LBASE" "$LHEAD" 2>/dev/null)
  check "A11: a Host: codex plan prints no lens line on stdout" "$(grep -c '^lens' <<<"$out")" "0"
  out=$(cd "$LRR" && bash "$ROUTE" codex-plan.md --task 1 2>&1); status=$?
  check "A11: a Host: codex plan exits 2 on --task" "$status" "2"
}

# --- A12 -------------------------------------------------------------------

SR="$TMP/steprepo"
sr_run() { # sr_run <args...> — task-step in the fixture repo; sets sr_out, sr_err, sr_rc
  sr_out=$(cd "$SR" && env HOME="$TMP/srhome" DR_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=mp-acceptance \
    bash "$STEP" "$@" 2>"$TMP/sr.err"); sr_rc=$?
  sr_err=$(cat "$TMP/sr.err")
}
sr_git() { git -C "$SR" "$@"; }
sr_state() { jq -r "$2" "$SR_WS/task-$1-step.json" | tr -d '\r'; }
sr_fix_case() { # sr_fix_case <name> <task> <lines appended by the fix>
  local t=$2 i
  sr_run start docs/plan.md "$t"
  check "A12: $1: start" "$sr_rc" "0"
  printf 'work %s\n' "$t" >> "$SR/app.txt"
  sr_git add -A && sr_git commit -qm "work $t"
  sr_run review docs/plan.md "$t"
  check "A12: $1: review" "$sr_rc" "0"
  for ((i = 1; i <= $3; i++)); do printf 'fix %s %s\n' "$t" "$i" >> "$SR/app.txt"; done
  sr_git add -A && sr_git commit -qm "fix $t"
  printf -- '- app.txt: wrong value\n\nFixed.\n' > "$SR_WS/task-$t-fix-1.md"
  sr_run rereview docs/plan.md "$t"
  check "A12: $1: the re-review is packaged (exit 0)" "$sr_rc" "0"
  check "A12: $1: the re-review prompt is written" "$([ -s "$SR_WS/task-$t-rereview-1-prompt.md" ] && echo yes || echo no)" "yes"
  check "A12: $1: no skip line in the digest" "$(grep -ci 'skip' <<<"$sr_out")" "0"
  check "A12: $1: the fix round is recorded" "$(sr_state "$t" .round)" "1"
}
a12() {
  command -v jq >/dev/null 2>&1 || { printf 'FAIL - A12: jq is needed for this test\n'; fail=$((fail + 1)); return; }
  mkdir -p "$TMP/srhome" "$SR/docs"
  git init -q -b main "$SR"
  sr_git config user.name t
  sr_git config user.email t@example.invalid
  {
    printf '# Rereview Fixture Plan\n\n**Goal:** Fixture.\n\n'
    printf '**Execution:** inline — `claude --model sonnet --effort high` — fixture\n\n## Task index\n\n'
    printf '1. Small\n2. Risky\n3. Three lines\n4. Risky three lines\n\n'
    local n risk
    for n in 1 2 3 4; do
      risk=0; case $n in 2 | 4) risk=3 ;; esac
      printf '### Task %s: Thing\n\n**Files:**\n- Modify: `app.txt`\n\n**Implementer:** dforge:impl-sonnet-high\n' "$n"
      printf '**Evaluation:** files 0 - spec 0 - coupling 1 - risk %s = %s\n\n' "$risk" "$((risk + 1))"
    done
  } > "$SR/docs/plan.md"
  seq 1 10 | sed 's/^/line /' > "$SR/app.txt"
  sr_git add -A && sr_git commit -qm base
  SR_WS=$(cd "$SR" && env HOME="$TMP/srhome" bash "$PLUGIN/scripts/sdd-workspace" docs/plan.md)

  sr_run
  check "A12: task-step with no arguments is a usage error" "$sr_rc" "2"
  lacks "A12: the usage text names no --covered option" "$sr_err" "--covered"

  sr_fix_case "a one-line fix, risk 0" 1 1
  sr_fix_case "a one-line fix, risk 3" 2 1
  sr_fix_case "a three-line fix, risk 0" 3 3
  sr_fix_case "a three-line fix, risk 3" 4 3

  # --covered is gone from every subcommand.
  printf 'fix again\n' >> "$SR/app.txt"
  sr_git add -A && sr_git commit -qm "fix again"
  printf -- '- app.txt: wrong value\n\nFixed.\n' > "$SR_WS/task-1-fix-2.md"
  rm -f "$SR_WS/task-1-rereview-2-prompt.md"
  sr_run rereview docs/plan.md 1 --covered
  check "A12: rereview --covered is a usage error" "$sr_rc" "2"
  check "A12: rereview --covered writes no re-review prompt" "$([ -e "$SR_WS/task-1-rereview-2-prompt.md" ] && echo yes || echo no)" "no"
  lacks "A12: the --covered usage error does not offer the option" "$sr_err" "[--covered]"
  sr_run review docs/plan.md 1 --covered
  check "A12: review --covered is a usage error" "$sr_rc" "2"
  sr_run verdict docs/plan.md 1 --covered
  check "A12: verdict --covered is a usage error" "$sr_rc" "2"
  sr_run start docs/plan.md 1 --covered
  check "A12: start --covered is a usage error" "$sr_rc" "2"
}

for t in $sel; do
  case $t in
    A1) a1 ;; A2) a2 ;; A3) a3 ;; A4) a4 ;; A5) a5 ;; A6) a6 ;; A7) a7 ;;
    A8) a8 ;; A9) a9 ;; A10) a10 ;; A11) a11 ;; A12) a12 ;;
  esac
  # A test that sets up its own repository must not see the previous one.
  rm -rf "$LR" "$AR" "$LRR" "$SR" 2>/dev/null
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
