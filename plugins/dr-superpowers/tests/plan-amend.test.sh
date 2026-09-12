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

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1

Print `hello NAME`.

### Task 2: Second thing

**Files:**
- Modify: `a.sh`

**Implementer:** dr-superpowers:impl-opus-low
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4

Print `hello NAME` twice.
EOF
WS="$REPO/.superpowers/sdd/plan"
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

entry b7.md '## Task 2' '**Implementer:** dr-superpowers:impl-opus-low' '**Implementer:** dr-superpowers:impl-opus-high'
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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
