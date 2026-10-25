#!/usr/bin/env bash
# draft-pack --join appends the drafters' slices to a header-only plan in task
# order, and refuses anything that does not cover the missing tasks exactly,
# leaving the plan as it was.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DP="$HERE/../scripts/draft-pack"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
REPO="$TMP/repo"
git init -q -b main "$REPO"
cd "$REPO"
mkdir -p docs
D="$REPO/.dforge/drafts/plan"

header() { # header N - a plan header whose index lists tasks 1..N
  printf '# Demo Implementation Plan\n\n## Task index\n\n'
  i=1; while [ "$i" -le "$1" ]; do printf '%d. Step %d\n' "$i" "$i"; i=$((i + 1)); done
  printf '\n---\n'
}
slice() { # slice A B - a slice file holding tasks A..B
  mkdir -p "$D"
  i=$1; while [ "$i" -le "$2" ]; do printf '### Task %d: Step %d\n\nBody %d.\n' "$i" "$i" "$i"; [ "$i" -lt "$2" ] && printf '\n'; i=$((i + 1)); done > "$D/tasks-$1-$2.md"
}
reset() { rm -rf "$REPO/.dforge"; header "$1" > docs/plan.md; cp docs/plan.md "$TMP/before.md"; }
unchanged() { cmp -s docs/plan.md "$TMP/before.md" && echo yes || echo no; }
run() { out=$(bash "$DP" "$@" 2>&1); code=$?; }

run; check "no arguments: usage" "$code" "2"
run --join; check "--join alone: usage" "$code" "2"
run --join docs/missing.md; check "no such plan: usage" "$code" "2"

reset 4; slice 3 4; slice 1 2
run --join docs/plan.md
check "join: exit 0" "$code" "0"
check "join: the message" "$out" "draft-pack: joined tasks 1 2 3 4 from 2 slices into docs/plan.md"
expected=$( { header 4; printf '\n### Task 1: Step 1\n\nBody 1.\n\n### Task 2: Step 2\n\nBody 2.\n\n### Task 3: Step 3\n\nBody 3.\n\n### Task 4: Step 4\n\nBody 4.\n'; } )
check "join: slices appended in task order" "$(cat docs/plan.md)" "$expected"
check "join: slices deleted" "$([ -e "$D" ] && echo present || echo gone)" "gone"

run --join docs/plan.md
check "nothing missing, no slices: exit 0" "$code" "0"
check "nothing missing, no slices: the message" "$out" "draft-pack: nothing to join"

reset 4; slice 1 2; slice 4 4
run --join docs/plan.md
check "gap: exit 3" "$code" "3"
check "gap: plan unchanged" "$(unchanged)" "yes"
check "gap: slices kept" "$(ls "$D" | tr '\n' ' ')" "tasks-1-2.md tasks-4-4.md "

reset 4; slice 1 2; slice 2 4
run --join docs/plan.md
check "overlap: exit 3" "$code" "3"
check "overlap: plan unchanged" "$(unchanged)" "yes"

reset 2; slice 1 1; mv "$D/tasks-1-1.md" "$D/tasks-1-2.md"
run --join docs/plan.md
check "headings not the range: exit 3" "$code" "3"
check "headings not the range: plan unchanged" "$(unchanged)" "yes"

reset 2; slice 1 2; printf 'x\n' > "$D/tasks-a-b.md"
run --join docs/plan.md
check "malformed slice name: exit 3" "$code" "3"

reset 2; slice 1 2; bash "$DP" --join docs/plan.md >/dev/null 2>&1; cp docs/plan.md "$TMP/before.md"; slice 1 2
run --join docs/plan.md
check "slices with nothing missing: exit 3" "$code" "3"
check "slices with nothing missing: plan unchanged" "$(unchanged)" "yes"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
