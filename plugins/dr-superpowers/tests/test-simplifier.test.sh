#!/usr/bin/env bash
# test-simplifier removes tests. The checks below pin what makes a removal
# safe — fault evidence over coverage, test-only waves, the never-removed list
# and the judge gate — and run scripts/test-profile against fixture reports.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
SKILL="$P/skills/test-simplifier/SKILL.md"
JUDGE="$P/skills/test-simplifier/references/simplify-judge.md"
RUNNERS="$P/skills/test-simplifier/references/runners.md"
PROFILE="$P/scripts/test-profile"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

for f in "$SKILL" "$JUDGE" "$RUNNERS"; do
  check "exists: ${f#"$P"/}" "$([ -f "$f" ] && echo yes || echo no)" "yes"
done

# Coverage is never the proof. This is the finding the skill is built on.
present "coverage never proves redundancy" "$SKILL" 'Coverage never proves a test redundant'
present "every killed mutant stays killed" "$SKILL" 'Every mutant killed before is killed after'
present "no-tool fallback: faults must be caught" "$SKILL" 'Every named fault must turn the kept tests'
present "fault patches are reverted" "$SKILL" 'revert the patch'

# Phase order: nothing is deleted before measuring, speeding up and tiering.
for h in '## Phase 1. Measure' '## Phase 2. Recover time without deleting' \
         '## Phase 3. Tier the run' '## Phase 4. Remove or merge, mutation-gated'; do
  present "phase: $h" "$SKILL" "$h"
done
present "flaky tests are quarantined, not deleted" "$SKILL" 'quarantined, never deleted'
present "tier changes need approval" "$SKILL" 'apply them only'
present "full sweep must keep running somewhere" "$SKILL" 'deletion in disguise'

# A wave changes test files only, so before and after mutant sets match.
present "waves change test files only" "$SKILL" 'test files only'
present "waves are bounded" "$SKILL" 'never the whole suite'
present "never removed: regression tests" "$SKILL" 'a regression test naming a fixed bug'
present "never removed: gate dependencies" "$SKILL" '`gates.md` entry'

# The judge gate.
present "dispatches judge-opus" "$SKILL" 'dispatch dr-superpowers:judge-opus with the *ruling* prompt'
present "commit before judging" "$SKILL" 'Commit the wave, including its ledger section'
for v in KEPT LOST VIOLATED; do
  present "verdict $v" "$SKILL" "\`$v\`"
  present "judge contract verdict $v" "$JUDGE" "- $v -"
done
present "judge maps assertions before ruling" "$JUDGE" 'Map assertions before ruling'
present "judge checks production files" "$JUDGE" 'Any production file'
present "judge is read-only" "$JUDGE" 'read-only'
present "fault prompt names concrete edits" "$JUDGE" 'the exact edit'
present "judge names the SHA" "$JUDGE" '[COMMIT] in your report'

# Routing and regrowth.
present "entry point routes to the skill" "$P/skills/using-superpowers/SKILL.md" 'dr-superpowers:test-simplifier'
present "TDD folds variants into a table" "$P/skills/test-driven-development/SKILL.md" "into the sibling's table as a row"
present "TDD asks for the lowest layer" "$P/skills/test-driven-development/SKILL.md" '**Lowest layer**'
present "plans keep e2e for user journeys" "$P/skills/writing-plans/SKILL.md" 'only for a new user journey'

# scripts/test-profile against fixture reports.
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/reports/nested"
cat > "$T/reports/py.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<testsuites>
  <testsuite name="pytest" time="20.0" tests="4">
    <testcase classname="tests.unit.test_math" name="test_add" time="0.010"/>
    <testcase classname="tests.unit.test_math" name="test_div[a|b]" time="0.020">
      <failure message="x &lt; y">trace</failure>
    </testcase>
    <testcase classname="tests.integration.test_db" name="test_save" time="5.5"><skipped/></testcase>
    <testcase classname="tests.e2e.test_login" name="test_login" time="12.0">
      <rerunFailure message="timeout"/>
    </testcase>
  </testsuite>
</testsuites>
EOF
cat > "$T/reports/nested/js.xml" <<'EOF'
<testsuites><testsuite name="jest" time="3"><testcase classname="Login" name="works" file="src/e2e/login.spec.ts" time="2.5"></testcase><testcase classname="Login" name="works" file="src/e2e/login.spec.ts" time="0.1"/></testsuite></testsuites>
EOF

out=$(bash "$PROFILE" --brief "$T/reports")
check "brief totals over a directory, recursively" "$out" \
  "tests=6 time=20.1s overhead=2.9s slowest10pct=60% fail=1 skip=1 flaky=1 reran=1"

out=$(bash "$PROFILE" "$T/reports")
present_out() { # present_out <name> <needle>
  if printf '%s\n' "$out" | grep -qF -- "$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n' "$1" "$2"; fail=$((fail + 1)); fi
}
present_out "default layers: e2e" "| e2e | 3 | 14.6s | 73% |"
present_out "default layers: integration" "| integration | 1 | 5.5s | 27% |"
present_out "dotted classnames become paths" "| tests/e2e/test_login | 1 | 12.0s | 60% |"
present_out "file attribute wins over classname" "| src/e2e/login.spec.ts | 2 | 2.6s | 13% |"
present_out "pipes in names are escaped" 'test_div[a\|b]'
present_out "slowest test is first" "| tests.e2e.test_login::test_login | e2e | 12.0s |"

out=$(bash "$PROFILE" --layer slow='e2e|integration' --top 1 "$T/reports/py.xml")
present_out "custom layer" "| slow | 2 | 17.5s | 100% |"
present_out "unmatched custom layer is other" "| other | 2 |"
check "top limits the tests table" "$(printf '%s\n' "$out" | grep -c '::')" "1"

bash "$PROFILE" >/dev/null 2>&1; check "no input exits 2" "$?" "2"
bash "$PROFILE" --top 0 "$T/reports" >/dev/null 2>&1; check "bad --top exits 2" "$?" "2"
bash "$PROFILE" "$T/missing" >/dev/null 2>&1; check "missing path exits 2" "$?" "2"
printf '<x/>\n' > "$T/empty.xml"
bash "$PROFILE" "$T/empty.xml" >/dev/null 2>&1; check "no test case exits 2" "$?" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
