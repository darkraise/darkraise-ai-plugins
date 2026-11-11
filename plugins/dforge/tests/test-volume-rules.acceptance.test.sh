#!/usr/bin/env bash
# Acceptance tests for the test-volume-rules spec (A1-A10), driven through the
# public surface only: plan-lint and lens-route run on fixture plans and
# fixture git repositories.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$HERE/../scripts/plan-lint"
ROUTE="$HERE/../scripts/lens-route"
export DFORGE_NO_SETTINGS=1
unset DFORGE_LENS_CAP CLAUDE_CONFIG_DIR
export DFORGE_LENS_MINOR_FROM=0

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
nonzero() { # nonzero <name> <status>
  if [ "$2" -ne 0 ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want a non-zero exit, got 0\n' "$1"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1
export HOME="$TMP/home"
mkdir -p "$HOME" docs
printf '# Spec\n' > docs/spec.md
export DR_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=test-volume-rules-acceptance

# ---------------------------------------------------------------- plan-lint

# plan3 <Task 1 Step 1 heading> <Task 2 ...> <Task 3 ...>: a clean three-task
# sequential plan on stdout; an empty heading leaves that task without a
# Step 1 line. Headings reach awk through the environment.
plan3() {
  S1=$1 S2=$2 S3=$3 awk '
    /^### Task [0-9]+:/ { n++ }
    /^\*\*Evaluation:\*\*/ { print; h = ENVIRON["S" n]; if (h != "") { print ""; print "- [ ] **Step 1: " h "**" } next }
    { print }
  ' <<'EOF'
# Demo Implementation Plan

**Goal:** Demo.

**Spec:** `docs/spec.md`

**Execution:** subagent — `claude --model sonnet --effort high` — three tasks

**Parallelism:** sequential — one chain

**Integration check:** `bash test.sh`

**Worktree setup:** none

**Task check:** `bash quick.sh` — gate 1 has Tier: task

**CI:** none

**Plan review:** 2026-10-10 — dforge:judge-opus — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)

## Global Constraints

- Bash only.

## Contracts

None

## Assumptions (evidence)

- None.

## Task index

1. One
2. Two
3. Three

### Task 1: One

**Files:**
- Create: `a.txt`

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1

### Task 2: Two

**Files:**
- Create: `b.txt`

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1

### Task 3: Three

**Files:**
- Create: `c.txt`

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
EOF
}
lint() { # lint <file>; sets out and status, CR stripped
  out=$(bash "$LINT" "$1" --no-probe 2>&1 | tr -d '\r'); status=${PIPESTATUS[0]}
}
step1_lines() { grep -E '^(ERROR|WARN) Task [0-9]+: Step 1' <<<"$out"; }

# Baseline: the fixture itself is clean, so every later finding comes from the
# heading under test.
plan3 'Write the failing test' 'Write the failing test' 'Write the failing test' > base.md
lint base.md
check "setup: the fixture plan lints with exit 0" "$status" "0"
check "setup: the fixture plan has no ERROR" "$(grep -c '^ERROR' <<<"$out")" "0"
check "setup: the fixture plan has no Step 1 finding" "$(step1_lines | wc -l | tr -d ' ')" "0"

# A1
plan3 'No new test, because the change is prose no script reads' 'Write the failing test' 'Write the failing test' > a1.md
lint a1.md
check "A1: a No new test heading with a reason: exit 0" "$status" "0"
check "A1: a No new test heading with a reason: no ERROR line" "$(grep -c '^ERROR' <<<"$out")" "0"
check "A1: a No new test heading with a reason: no finding names its Step 1" "$(step1_lines | wc -l | tr -d ' ')" "0"
has "A1: the lint ran to its summary" "$out" "plan-lint: 0 errors"

# A2
i=0
for h in 'No new test' 'No new test, because' 'No new test, because .' 'No new test because x'; do
  i=$((i + 1))
  plan3 'Write the failing test' "$h" 'Write the failing test' > "a2-$i.md"
  lint "a2-$i.md"
  has "A2: '$h' is an ERROR naming the form" "$out" 'ERROR Task 2: Step 1 must read "No new test, because <reason>"'
  nonzero "A2: '$h' exits non-zero" "$status"
done

# A3
plan3 'Write the failing test' 'Do it' 'Write the failing test' > a3.md
lint a3.md
has "A3: an unrecognized heading draws the WARN" "$out" 'WARN Task 2: Step 1 "Do it" is none of the forms in test-step-forms.md'
check "A3: the WARN alone leaves exit status 0" "$status" "0"
check "A3: no ERROR accompanies the WARN" "$(grep -c '^ERROR' <<<"$out")" "0"

# A4: three recognized headings in each plan, and a task with no Step 1 line.
plan3 'Write the failing tests' 'Extend the test `t/a.test.sh::first`' "Covered by Task 1's test \`first\`" > a4-1.md
lint a4-1.md
check "A4: tests / Extend / Covered by: no Step 1 finding" "$(step1_lines | wc -l | tr -d ' ')" "0"
has "A4: tests / Extend / Covered by: the lint ran to its summary" "$out" "plan-lint: "
plan3 'Write the failing test' '' 'Write the failing test' > a4-2.md
lint a4-2.md
check "A4: a task with no Step 1 line: no Step 1 finding" "$(step1_lines | wc -l | tr -d ' ')" "0"
has "A4: a task with no Step 1 line: the lint ran to its summary" "$out" "plan-lint: "
plan3 'Write the failing test' 'Write the failing tests' "Covered by Task 2's test \`second\`" > a4-3.md
lint a4-3.md
check "A4: a valid Covered by after a tests heading: no Step 1 finding" "$(step1_lines | wc -l | tr -d ' ')" "0"
check "A4: a valid Covered by: no ERROR" "$(grep -c '^ERROR' <<<"$out")" "0"

# A5
plan3 'Write the failing test' 'No new test, because prose only' "Covered by Task 2's test \`b\`" > a5.md
lint a5.md
has "A5: Covered by a No new test task is an ERROR" "$out" 'ERROR Task 3: Covered by Task 2 — Task 2 has no test step'
nonzero "A5: that ERROR exits non-zero" "$status"

# ---------------------------------------------------------------- lens-route

# new_repo <dir>: a git repository with a base commit, three spec files of the
# three depths and one one-task plan per depth, all untracked.
new_repo() {
  git init -q "$1" && cd "$1" || exit 1
  git config user.email t@example.com && git config user.name t
  git commit -q --allow-empty -m base
  BASE=$(git rev-parse HEAD)
  mkdir -p specs
  for d in light standard full; do
    printf '# Spec\n\n**Depth:** %s — fixture\n' "$d" > "specs/$d.md"
    {
      printf '# Depth Fixture Plan\n\n**Spec:** `specs/%s.md`\n\n## Task index\n\n1. only\n\n' "$d"
      printf '### Task 1: only\n\n**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0\n'
    } > "$d-plan.md"
  done
}
add_file() { # add_file <path> <content>
  mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; git add "$1"; git commit -q -m "add $1"
}
# lines <route output>: only the lens and lens-skipped lines, without the
# criteria, seat and reason=<why applied> fields, as one ;-joined string.
lines() {
  tr -d '\r' <<<"$1" | grep -E '^lens(-skipped)? ' \
    | sed -E 's/ criteria=[^ ]*//; s/ seat=[^ ]*//; s/ reason=(always|added|ui-paths|paths:[^ ]*)$//' | tr '\n' ';'
}
printed() { tr -d '\r' <<<"$1" | grep -c '^lens '; }
route() { bash "$ROUTE" "$@" 2>&1; }

# The change set of A6: a shell file with 2>/dev/null, a test file, a README.
new_repo "$TMP/a6" ; cd "$TMP/a6" || exit 1
add_file scripts/run.sh 'cmd 2>/dev/null'
add_file tests/a.test.sh 'echo hi'
add_file README.md 'Docs.'
H6=$(git rev-parse HEAD)

out=$(route standard-plan.md --final "$BASE" "$H6")
check "A6: standard depth, default cap: three lenses, the rest skipped for the cap" "$(lines "$out")" \
  "lens security;lens silent-failures;lens test-quality;lens-skipped lang-bash reason=cap;lens-skipped docs-comments reason=cap;"

# A10 on the same change set.
out=$(route light-plan.md --final "$BASE" "$H6")
check "A10: light depth: security only, every other applicable lens skipped for depth" "$(lines "$out")" \
  "lens security;lens-skipped silent-failures reason=depth;lens-skipped test-quality reason=depth;lens-skipped lang-bash reason=depth;lens-skipped docs-comments reason=depth;"
out=$(route full-plan.md --final "$BASE" "$H6")
check "A10: full depth, cap 4: four lenses, the rest skipped for the cap" "$(lines "$out")" \
  "lens security;lens silent-failures;lens test-quality;lens lang-bash;lens-skipped docs-comments reason=cap;"

# A7: no path matches test-quality's clause; five other lenses apply.
new_repo "$TMP/a7" ; cd "$TMP/a7" || exit 1
add_file src/run.sh 'cmd 2>/dev/null'
add_file src/b.ts 'run() ?? fallback()'
add_file NOTES.md 'Notes.'
H7=$(git rev-parse HEAD)
out=$(route standard-plan.md --final "$BASE" "$H7")
[ "$(printed "$out")" -le 2 ] && r=yes || r=no
check "A7: at most two lens lines when no test path changed" "$r" "yes"
has "A7: the route ran and printed its lens lines" "$(lines "$out")" "lens security;"
lacks "A7: test-quality is not routed" "$(lines "$out")" "lens test-quality"

# A8: lensCap 2, a changed test file, security and silent-failures apply.
new_repo "$TMP/a8" ; cd "$TMP/a8" || exit 1
add_file tests/a.test.ts 'try { run() } catch (e) {}'
H8=$(git rev-parse HEAD)
out=$(DFORGE_LENS_CAP=2 route standard-plan.md --final "$BASE" "$H8")
check "A8: lensCap 2: exactly two lens lines" "$(printed "$out")" "2"
has "A8: lensCap 2: security is printed" "$(lines "$out")" "lens security;"
has "A8: lensCap 2: silent-failures is printed" "$(lines "$out")" "lens silent-failures;"
has "A8: lensCap 2: test-quality is skipped for the cap" "$out" "lens-skipped test-quality reason=cap"

# A9: a copy of the plugin whose security lens applies to no path.
mkdir -p "$TMP/plug/criteria"
cp -R "$HERE/../scripts" "$HERE/../config" "$TMP/plug/"
cp -R "$HERE/../criteria/lenses" "$TMP/plug/criteria/lenses"
sed 's/^Applies: .*$/Applies: paths nothing\/*/' "$HERE/../criteria/lenses/security.md" > "$TMP/plug/criteria/lenses/security.md"
new_repo "$TMP/a9" ; cd "$TMP/a9" || exit 1
add_file src/run.sh 'cmd 2>/dev/null'
add_file tests/a.test.sh 'echo hi'
H9=$(git rev-parse HEAD)
out=$(bash "$TMP/plug/scripts/lens-route" standard-plan.md --final "$BASE" "$H9" 2>&1)
has "A9: without security, silent-failures prints" "$(lines "$out")" "lens silent-failures;"
has "A9: without security, test-quality prints" "$(lines "$out")" "lens test-quality;"
has "A9: without security, lang-bash prints" "$(lines "$out")" "lens lang-bash;"
lacks "A9: the narrowed security lens does not print" "$(lines "$out")" "lens security;"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
