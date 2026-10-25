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

reset 11; printf '\n### Task 1: Step 1\n\nBody 1.\n' >> docs/plan.md; cp docs/plan.md "$TMP/before.md"
slice 10 11; slice 4 5; slice 6 9; slice 2 3
run --join docs/plan.md
check "numeric order: exit 0" "$code" "0"
check "numeric order: tasks 1-11 in order" "$(grep -o '^### Task [0-9]*' docs/plan.md | tr -d '\n')" "### Task 1### Task 2### Task 3### Task 4### Task 5### Task 6### Task 7### Task 8### Task 9### Task 10### Task 11"

reset 3
run --join docs/plan.md
check "tasks missing and no slices: exit 3" "$code" "3"
check "tasks missing and no slices: plan unchanged" "$(unchanged)" "yes"

reset 4; slice 1 2; printf '### Task 4: Step 4\n\nBody 4.\n\n### Task 3: Step 3\n\nBody 3.\n' > "$D/tasks-4-3.md"
run --join docs/plan.md
check "backwards slice name: exit 3" "$code" "3"
check "backwards slice name: the message" "$(grep -c 'tasks-4-3.md runs backwards' <<<"$out")" "1"
check "backwards slice name: plan unchanged" "$(unchanged)" "yes"

reset 2; printf '# Demo Implementation Plan\n\n## Task index\n\n- Step 1\n- Step 2\n\n---\n' > docs/plan.md; cp docs/plan.md "$TMP/before.md"; slice 1 2
run --join docs/plan.md
check "no numbered Task index: exit 3" "$code" "3"
check "no numbered Task index: plan unchanged" "$(unchanged)" "yes"
check "no numbered Task index: slices kept" "$(ls "$D")" "tasks-1-2.md"

rm -rf "$REPO/.dforge"; printf '# Demo Implementation Plan\n\n---\n' > docs/plan.md; cp docs/plan.md "$TMP/before.md"
run --join docs/plan.md
check "no Task index heading: exit 3" "$code" "3"
check "no Task index heading: plan unchanged" "$(unchanged)" "yes"

for line in '**Implementer:** dforge:impl-opus-high' '**Executor:** codex' '**Evaluation:** spec 0' '**Override:** because' '**Approach:** inline' '**Lenses:** security'; do
  reset 2; slice 1 2; printf '\n%s\n' "$line" >> "$D/tasks-1-2.md"
  run --join docs/plan.md
  check "assignment line ${line%%:*}: exit 3" "$code" "3"
  check "assignment line ${line%%:*}: plan unchanged" "$(unchanged)" "yes"
  check "assignment line ${line%%:*}: slices kept" "$(ls "$D")" "tasks-1-2.md"
done
check "assignment line: the message names it" "$(grep -c 'tasks-1-2.md carries a \*\*Lenses:\*\* line' <<<"$out")" "1"

reset 2; slice 1 2; printf '\n```\n**Implementer:** dforge:impl-opus-high\n```\n' >> "$D/tasks-1-2.md"
run --join docs/plan.md
check "assignment line inside a code fence: exit 0" "$code" "0"

reset 2; slice 1 2
run --join docs/plan.md
check "the state directory ignores itself" "$(cat "$REPO/.dforge/.gitignore" 2>/dev/null)" "*"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
