#!/usr/bin/env bash
# plan-amend is how a controller records a plan correction without composing
# it: the entry must be well formed, apply exactly once, and add no lint
# errors, or amendments.md is left exactly as it was.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AMEND="$HERE/../scripts/plan-amend"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
REPO="$TMP/repo"
git init -q "$REPO"
cd "$REPO"
mkdir -p docs
printf '# Spec\n' > docs/spec.md
cat > docs/plan.md <<'EOF'
# Demo Implementation Plan

**Goal:** Demo.

**Spec:** `docs/spec.md`

**Execution:** subagent — `claude --model sonnet --effort high` — Task 2 scores 4

## Global Constraints

- Bash only.

## Contracts

- `greet NAME` prints `hello NAME`.

## Assumptions (evidence)

- None.

## Task index

1. First thing
2. Second thing

### Task 1: First thing

**Files:**
- Create: `a.sh`

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1

Print `hello NAME`.

### Task 2: Second thing

**Files:**
- Modify: `a.sh`

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4

Print `hello NAME` twice.
EOF
WS="$REPO/.dforge/sdd/plan"
LEDGER="$WS/amendments.md"

entry() { # entry <file> <heading> <old> <new>
  printf '%s\nReason: the plan says the wrong thing\nCost if wrong: one fix round\n### Old\n````text\n%s\n````\n### New\n````text\n%s\n````\n' \
    "$2" "$3" "$4" > "$1"
}
run() { out=$(bash "$AMEND" "$@" 2>&1); status=$?; }

entry b1.md '## A? — Task 2' 'Print `hello NAME` twice.' 'Print `hello NAME` three times.'
run docs/plan.md b1.md
check "append: exit 0" "$status" "0"
check "append: output" "$out" "amended: A1 Task 2"
check "append: heading numbered" "$(grep -c '^## A1 — Task 2$' "$LEDGER")" "1"

entry b2.md '## Header' '- Bash only.' '- Bash 4 or later.'
run docs/plan.md b2.md
check "header target: output" "$out" "amended: A2 Header"
check "header target: blank line between entries" "$(grep -c '^$' "$LEDGER")" "1"

cp "$LEDGER" "$TMP/snapshot"
entry b3.md '## A? - Task 1' 'no such line' 'x'
run docs/plan.md b3.md
check "absent old text: exit 1" "$status" "1"
has "absent old text: reason" "$out" "rejected: Old text does not match exactly once in Task 1"
check "absent old text: file unchanged" "$(cmp -s "$LEDGER" "$TMP/snapshot" && echo same)" "same"

entry b4.md '## Task 1' '' 'x'
run docs/plan.md b4.md
has "empty old text" "$out" "rejected: Old text is empty"

entry b5.md '## Task 7' 'x' 'y'
run docs/plan.md b5.md
has "missing task" "$out" "rejected: no Task 7 in the plan"

entry b6.md '## Header' '**Execution:** subagent — `claude --model sonnet --effort high` — Task 2 scores 4' '**Execution:** inline'
run docs/plan.md b6.md
has "protected line" "$out" "rejected: Old text touches a line that cannot be amended"

entry b7.md '## Task 2' '**Implementer:** dforge:impl-sonnet-medium' '**Implementer:** dforge:impl-opus-high'
run docs/plan.md b7.md
check "new lint error: exit 1" "$status" "1"
has "new lint error: reason" "$out" "rejected: the amendment introduces lint errors:"
has "new lint error: named" "$out" "ERROR Task 2: Implementer impl-opus-high does not match"
check "new lint error: rolled back byte for byte" "$(cmp -s "$LEDGER" "$TMP/snapshot" && echo same)" "same"

printf '## Task 1\nReason: r\nCost if wrong: c\n### Old\n```text\nPrint `hello NAME`.\n```\n' > b8.md
run docs/plan.md b8.md
has "three-backtick fence rejected" "$out" "rejected: '### Old' and '### New' must each be followed by a closed fence"

printf 'Reason: r\n' > b9.md
run docs/plan.md b9.md
has "missing heading" "$out" "rejected: heading must be"

# A plan that already fails lint (no Contracts section) still accepts an
# amendment that adds no new error.
sed '/^## Contracts$/,/^## Assumptions/{/^## Assumptions/!d}' docs/plan.md > docs/old.md
entry b10.md '## Task 1' 'Print `hello NAME`.' 'Print `hello, NAME`.'
run docs/old.md b10.md
check "pre-existing errors: accepted" "$out" "amended: A1 Task 1"

entry b11.md '## Task 2' 'Print `hello NAME` three times.' 'Print `hello NAME` four times.'
sed 's/$/\r/' b11.md > b11-crlf.md
run docs/plan.md b11-crlf.md
check "CRLF block, builds on A1: output" "$out" "amended: A3 Task 2"

# --- a split into parts, as the ruling seat's AMEND writes it ---
cp docs/plan.md docs/split.md
SPLIT_LEDGER="$REPO/.dforge/sdd/split/amendments.md"
part() { # part <letter> [evaluation line]
  printf '#### Part %s: half %s\n\n**Files:**\n- Modify: `a.sh`\n\n**Implementer:** dforge:impl-sonnet-low\n%s' "$1" "$1" "${2-}"
}
split_old=$(printf '**Implementer:** dforge:impl-sonnet-medium\n**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4')
ev='**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1'
entry s1.md '## A? — Task 2' "$split_old" "$(printf '%s\n\n%s' "$(part A "$ev")" "$(part B)")"
run docs/split.md s1.md
check "split, a part without its Evaluation line: rejected" "$status" "1"
has "split, a part without its Evaluation line: named" "$out" "ERROR Task 2 part B: missing **Evaluation:** line"
entry s2.md '## A? — Task 2' "$split_old" "$(printf '%s\n\n%s' "$(part A "$ev")" "$(part B "$ev")")"
run docs/split.md s2.md
check "split: applied" "$out" "amended: A1 Task 2"
check "split: the amended plan holds both parts" \
  "$(. "$HERE/../scripts/lib/plan.sh"; plan_apply_amendments docs/split.md "$SPLIT_LEDGER" | grep -c '^#### Part [AB]: ')" "2"
out=$(bash "$HERE/../scripts/plan-lint" docs/split.md --no-probe 2>&1)
check "split: plan-lint accepts the amended plan" "$(grep -c '^ERROR' <<<"$out")" "0"

run docs/plan.md
check "usage: exit 2" "$status" "2"

# --- New text may not introduce a protected line either ---
cat > "$TMP/inject.md" <<'EOF'
## A? — Header
Reason: inject
Cost if wrong: none
### Old
````text
**Goal:** demo
````
### New
````text
**Execution:** subagent — `claude --model opus --effort max` — injected
**Goal:** demo
````
EOF
printf '# Inject plan

**Goal:** demo

**Execution:** subagent — `claude --model sonnet --effort high` — x

### Task 1: Only

line
' > docs/inject-plan.md
run docs/inject-plan.md "$TMP/inject.md"
check "injected Execution line: rejected" "$status" "1"
has "injected Execution line: names the rule" "$out" "New text adds a line that cannot be amended"

# Two amendments at once each get a number of their own, and neither is lost.
cp docs/plan.md docs/race.md
entry r1.md '## Task 1' 'Print `hello NAME`.' 'Print `hello, NAME`.'
entry r2.md '## Task 2' 'Print `hello NAME` twice.' 'Print `hello NAME` thrice.'
bash "$AMEND" docs/race.md r1.md > "$TMP/race1" 2>&1 &
bash "$AMEND" docs/race.md r2.md > "$TMP/race2" 2>&1 &
wait
check "concurrent amendments: both numbered apart" \
  "$(cat "$TMP/race1" "$TMP/race2" | sed 's/ Task [12]$//' | sort | tr '\n' ' ')" "amended: A1 amended: A2 "
check "concurrent amendments: both kept" "$(grep -c '^## A[12] — Task' "$REPO/.dforge/sdd/race/amendments.md")" "2"

# The same, without flock: the lock directory serializes them.
cp docs/plan.md docs/race-mkdir.md
DFORGE_FLOCK=no-such-flock bash "$AMEND" docs/race-mkdir.md r1.md > "$TMP/race1" 2>&1 &
DFORGE_FLOCK=no-such-flock bash "$AMEND" docs/race-mkdir.md r2.md > "$TMP/race2" 2>&1 &
wait
check "no flock: concurrent amendments both numbered apart" \
  "$(cat "$TMP/race1" "$TMP/race2" | sed 's/ Task [12]$//' | sort | tr '\n' ' ')" "amended: A1 amended: A2 "
check "no flock: concurrent amendments both kept" "$(grep -c '^## A[12] — Task' "$REPO/.dforge/sdd/race-mkdir/amendments.md")" "2"
check "no flock: the lock directory is gone" "$(find "$REPO" -name '*.lockd' | grep -c .)" "0"
# A mkdir that answers 0 for a directory that exists, as uutils' mkdir does to
# more than one of several shells racing for one: the claim still admits one.
LYING="$TMP/lying-mkdir"
mkdir -p "$LYING"
printf '#!%s\n"%s" "$@" 2>/dev/null\nexit 0\n' "$BASH" "$(type -P mkdir)" > "$LYING/mkdir"
chmod +x "$LYING/mkdir"
cp docs/plan.md docs/race-lying.md
PATH="$LYING:$PATH" DFORGE_FLOCK=no-such-flock bash "$AMEND" docs/race-lying.md r1.md > "$TMP/race1" 2>&1 &
PATH="$LYING:$PATH" DFORGE_FLOCK=no-such-flock bash "$AMEND" docs/race-lying.md r2.md > "$TMP/race2" 2>&1 &
wait
check "a mkdir that is not exclusive: concurrent amendments numbered apart" \
  "$(cat "$TMP/race1" "$TMP/race2" | sed 's/ Task [12]$//' | sort | tr '\n' ' ')" "amended: A1 amended: A2 "
check "a mkdir that is not exclusive: both kept" "$(grep -c '^## A[12] — Task' "$REPO/.dforge/sdd/race-lying/amendments.md")" "2"

# A write that fails is reported, never "amended".
mkdir -p "$TMP/failcp"
printf '#!/usr/bin/env bash
case "$*" in *amendments.md.*) exit 1 ;; esac
exec %s "$@"
' "$(command -v cp)" > "$TMP/failcp/cp"
chmod +x "$TMP/failcp/cp"
cp "$REPO/.dforge/sdd/race/amendments.md" "$TMP/race-snapshot"
entry r3.md '## Task 1' 'Print `hello, NAME`.' 'Print `hi NAME`.'
out=$(PATH="$TMP/failcp:$PATH" bash "$AMEND" docs/race.md r3.md 2>&1); status=$?
check "a failed write: exit 2" "$status" "2"
check "a failed write: never says amended" "$(grep -c '^amended' <<<"$out")" "0"
check "a failed write: amendments unchanged" \
  "$(cmp -s "$REPO/.dforge/sdd/race/amendments.md" "$TMP/race-snapshot" && echo same)" "same"

# --- --report: an AMEND entry taken from a ruling report, never hand-copied ---
# A ruling report numbers its entries A1, A2 … in the report; --id names one.
# Applied from the report, the entry lands exactly as the hand-copied block does.
entry "$TMP/rep-e1" '## A1 — Task 2' 'Print `hello NAME` twice.' 'Print `hello NAME` three times.'
entry "$TMP/rep-e2" '## A2 — Header' '- Bash only.' '- Bash 4 or later.'
{
  printf '## Verdict\n\n### Item 1\nVerdict: AMEND\nRuling: the count is wrong — say three times — one fix round\nAmendment: A1\n\n'
  printf '### Item 2\nVerdict: AMEND\nRuling: pin the shell — Bash 4 — one fix round\nAmendment: A2\n\n'
  cat "$TMP/rep-e1"; echo; cat "$TMP/rep-e2"
  printf '\n## Notes\n\nTrailing text that belongs to no entry.\n'
} > "$TMP/ruling-report.md"
for n in a b c d; do cp docs/plan.md "docs/rep-$n.md"; done
REP_A="$REPO/.dforge/sdd/rep-a/amendments.md" REP_B="$REPO/.dforge/sdd/rep-b/amendments.md"
run docs/rep-a.md b1.md
check "report: the hand-copied block applies" "$out" "amended: A1 Task 2"
run docs/rep-b.md --report "$TMP/ruling-report.md" --id A1
check "report: exit 0" "$status" "0"
check "report: the entry applies" "$out" "amended: A1 Task 2"
check "report: amendments.md matches the hand-copied block's byte for byte" "$(cmp -s "$REP_A" "$REP_B" && echo same || echo differs)" "same"
run docs/rep-b.md --report "$TMP/ruling-report.md" --id A2
check "report: a later entry applies" "$out" "amended: A2 Header"
check "report: nothing after the New fence is taken" "$(grep -c 'Trailing text\|^## Notes\|^Verdict:\|^Amendment:' "$REP_B")" "0"
run docs/rep-c.md --id A1 --report "$TMP/ruling-report.md"
check "report: the flags in either order" "$out" "amended: A1 Task 2"
sed 's/$/\r/' "$TMP/ruling-report.md" > "$TMP/ruling-report-crlf.md"
run docs/rep-d.md --report "$TMP/ruling-report-crlf.md" --id A1
check "report: a CRLF report" "$out" "amended: A1 Task 2"

cp "$REP_B" "$TMP/rep-snapshot"
run docs/rep-b.md --report "$TMP/ruling-report.md" --id A9
check "report: an id the report lacks: exit 1" "$status" "1"
has "report: an id the report lacks: named" "$out" "rejected: no entry A9 in $TMP/ruling-report.md"
check "report: an id the report lacks: amendments unchanged" "$(cmp -s "$REP_B" "$TMP/rep-snapshot" && echo same)" "same"
{ printf '## Verdict\n\n'; printf '## A1 — Task 1\nReason: r\nCost if wrong: c\n### Old\n````text\nPrint `hello NAME`.\n````\n### New\n````text\nPrint `hi NAME`.\n'; } > "$TMP/open-fence.md"
run docs/rep-b.md --report "$TMP/open-fence.md" --id A1
check "report: an entry whose New fence never closes: exit 1" "$status" "1"
has "report: an entry whose New fence never closes: named" "$out" "rejected: entry A1 in $TMP/open-fence.md has no closed New fence"
run docs/rep-b.md --report "$TMP/no-such-report.md" --id A1
check "report: a missing report file: exit 2" "$status" "2"
run docs/rep-b.md --report "$TMP/ruling-report.md" --id 1
check "report: an id that is not A<k>: exit 2" "$status" "2"
run docs/rep-b.md --report "$TMP/ruling-report.md"
check "report: --report without --id: exit 2" "$status" "2"
run docs/rep-b.md --id A1
check "report: --id without --report: exit 2" "$status" "2"
check "report: the refusals left amendments unchanged" "$(cmp -s "$REP_B" "$TMP/rep-snapshot" && echo same)" "same"
# A linked worktree session must not amend the primary checkout's plan: the
# worktree's task-brief would never see the amendment.
git add -A && git commit -qm 'test: seed' && git worktree add -q "$TMP/wt"
amendments="$REPO/.dforge/sdd/plan/amendments.md"
before_amend=$(cat "$amendments" 2>/dev/null)
(cd "$TMP/wt" && bash "$AMEND" "$REPO/docs/plan.md" "$REPO/b1.md") >/dev/null 2>&1
check "primary plan from a linked worktree: refused" "$?" "2"
check "primary plan from a linked worktree: amendments untouched" "$(cat "$amendments" 2>/dev/null)" "$before_amend"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
