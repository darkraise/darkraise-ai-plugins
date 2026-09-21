#!/usr/bin/env bash
# plan-revise reports; it never writes. Every mechanical rule the revising-plans
# skill applies lives here, so a rule the skill must follow is one a test reaches.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/plan-revise"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO/docs"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t
git -C "$REPO" config user.name t

# Fields are separated by two spaces, so a value may contain single spaces; a
# naive [^ ]* capture truncates "Global Constraints,..." to "Global".
field() { # field <name> <row>
  printf '%s' "$2" | awk -v k="$1" '{
    n = split($0, a, "  ")
    for (i = 1; i <= n; i++) if (index(a[i], k "=") == 1) { print substr(a[i], length(k) + 2); exit }
  }'
}

hdr() { # hdr <executors line or empty> <body>
  cat > "$REPO/docs/p.md" <<HDR
# Demo Implementation Plan

**Goal:** demo

**Spec:** docs/spec.md

**Execution:** inline — \`claude --model sonnet --effort high\` — demo
$1
## Global Constraints

- none

## Contracts

None

## Assumptions (evidence)

- none

## Task index

1. One

---

$2
HDR
}
plan() { hdr '
> **External executors:** codex
' "$1"; }
bare() { hdr '' "$1"; }
run() { (cd "$REPO" && bash "$SCRIPT" docs/p.md); }
unit1() { run | grep -m 1 '^unit'; }

check "script exists" "$([ -f "$SCRIPT" ] && echo yes || echo no)" "yes"

mktask() { # mktask <files> <spec> <coupling> <risk> <total>
  printf '### Task 1: One\n\n**Files:**\n- Create: `x`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files %s - spec %s - coupling %s - risk %s = %s\n' "$@"
}

# --- the gate boundaries, read from the shipped ladder ---
plan "$(mktask 0 0 1 0 1)"
check "total 1 fails the floor" "$(field gate "$(unit1)")" "fail:total"
plan "$(mktask 1 0 1 0 2)"
out=$(unit1)
check "total 2 passes" "$(field gate "$out")" "pass"
check "total 2 takes the medium rung" "$(field rungs "$out")" "codex:gpt-5.5/medium"
plan "$(mktask 1 1 1 0 3)"
check "total 3 takes the high rung" "$(field rungs "$(unit1)")" "codex:gpt-5.5/high"
plan "$(mktask 1 0 1 2 4)"
check "risk 2 fails the ceiling" "$(field gate "$(unit1)")" "fail:risk"
# spec 3 alone, with reducible 3, so the case cannot pass by the reducible rule.
plan "$(mktask 0 3 0 0 3)"
check "spec 3 fails Rule S on its own" "$(field gate "$(unit1)")" "fail:rule_s"
plan "$(mktask 1 1 2 0 4)"
check "reducible 4 fails Rule S below total 5" "$(field gate "$(unit1)")" "fail:rule_s"
# An Override keeps a Rule S violation in the plan; it must still not be offloaded.
OVERRIDE='**Override:** kept by the owner'
plan "$(mktask 0 3 0 0 3)
$OVERRIDE"
check "an overridden Rule S violation is still not eligible" "$(field gate "$(unit1)")" "fail:rule_s"
# plan-lint makes ANY Executor line on an overridden task a hard error
# (scripts/plan-lint:301), independent of Rule S, so a clean score with an
# Override must not be offered either.
plan "$(mktask 1 0 1 0 2)
$OVERRIDE"
check "an override blocks a unit whose score passes" "$(field gate "$(unit1)")" "fail:override"

# --- require_external_enabled: scores are not enough ---
bare "$(mktask 1 0 1 0 2)"
out=$(unit1)
check "a passing score with no executor ticked does not pass" "$(field gate "$out")" "fail:not_enabled"
check "a unit that cannot be offloaded lists no rung" "$(field rungs "$out")" ""
check "the header reports a missing executors line" "$(field executors "$(run | grep '^header')")" "missing"

# --- a second registered executor ---
FIXREG="$HERE/fixtures/executors"
# The stub ladder holds only the stub's blocks, so codex's gate would vanish and
# the run would list stub alone. plan-lint.test.sh:584 concatenates for this
# reason; do the same.
STUBLADDER="$TMP/both-ladder.md"
cat "$HERE/../reference/ladder.md" "$HERE/fixtures/stub-ladder.md" > "$STUBLADDER"
hdr '
> **External executors:** codex stub
' "$(mktask 1 0 1 0 2)"
out=$( (cd "$REPO" && DR_EXECUTORS_DIR="$FIXREG" DR_PLAN_REVISE_LADDER="$STUBLADDER" bash "$SCRIPT" docs/p.md) | grep -m 1 '^unit')
check "every ticked executor that admits the unit is listed" \
  "$(field rungs "$out" | tr ',' '\n' | cut -d: -f1 | sort | tr '\n' ' ')" "codex stub "

# --- units, parts and the states a score can be in ---
plan "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x`\n\n#### Part A: a\n\n**Files:**\n- Create: `a`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n#### Part B: b\n\n**Files:**\n- Create: `b`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n')"
check "a split task yields one unit per part" "$(run | grep -c '^unit')" "2"
check "a part unit is named with its letter" "$(run | sed -n 's/^unit \([0-9A-Z]*\).*/\1/p' | tr '\n' ' ')" "1A 1B "

plan '### Task 1: One

**Files:**
- Create: `x`

**Implementer:** dr-superpowers:impl-sonnet-medium
'
out=$(unit1)
check "no score reports a dash" "$(field score "$out")" "-"
check "no score gates unknown" "$(field gate "$out")" "unknown"

plan '### Task 1: One

**Files:**
- Create: `x`

**Evaluation:** spec completeness 1 (exact signatures given), coupling 0
'
out=$(unit1)
check "an unparseable score reports a question mark" "$(field score "$out")" "?"
check "an unparseable score gates unknown" "$(field gate "$out")" "unknown"

# axes must aggregate exactly as plan_scores does: the highest total and the
# highest risk independently, not the risk that happens to sit on the top line.
plan "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files 1 - spec 1 - coupling 1 - risk 0 = 3\n**Evaluation:** files 0 - spec 0 - coupling 0 - risk 2 = 2\n')"
out=$(unit1)
check "the highest total wins" "$(field score "$out")" "3"
check "the highest risk wins independently" "$(field risk "$out")" "2"
check "a disqualifying risk on a lower-total line still fails" "$(field gate "$out")" "fail:risk"

EXECLINE='**Executor:** codex gpt-5.5 / medium'
plan "$(mktask 1 0 1 0 2)
$EXECLINE"
check "an existing Executor line is reported" "$(field executor "$(unit1)")" "codex"
plan "$(mktask 1 0 1 0 2)"
check "no Executor line reports none" "$(field executor "$(unit1)")" "none"

# --- the header row ---
check "the header reports the execution mode" "$(field execution "$(run | grep '^header')")" "inline"
check "a complete header reports sections ok" "$(field sections "$(run | grep '^header')")" "ok"
check "a ticked executor is reported" "$(field executors "$(run | grep '^header')")" "codex"

# The selection is a header line. A fenced example in a task body is not it.
plan "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x`\n\n**Implementer:** dr-superpowers:impl-sonnet-medium\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n> **External executors:** stub\n```\n')"
check "a fenced executors line is not the selection" "$(field executors "$(run | grep '^header')")" "codex"

printf '# Bare Plan\n\n### Task 1: One\n\n**Files:**\n- Create: `x`\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n' > "$REPO/docs/p.md"
out=$(run | grep '^header')
check "a legacy header reports its missing sections" \
  "$(field sections "$out")" "Global Constraints,Contracts,Assumptions (evidence),Task index"
check "a legacy header reports a missing execution line" "$(field execution "$out")" "missing"

# --- the recommendation, which is writing-plans' rule as arithmetic ---
plan "$(mktask 1 0 1 0 2)"
out=$(run | grep '^recommend')
check "one light task recommends inline" "$(field execution "$out")" "inline"
check "one light task recommends sonnet" "$(field model "$out")" "sonnet"
check "one light task delegates nothing" "$(field delegated "$out")" "0/1"
check "one light task takes the table's effort" "$(field effort "$out")" "medium"

three() { # three <eval 1> <eval 2> <eval 3>
  plan "$(printf '### Task 1: One\n\n**Files:**\n- Create: `x`\n\n%s\n\n### Task 2: Two\n\n**Files:**\n- Create: `y`\n\n%s\n\n### Task 3: Three\n\n**Files:**\n- Create: `z`\n\n%s\n' "$1" "$2" "$3")"
}
E5='**Evaluation:** files 2 - spec 1 - coupling 2 - risk 0 = 5'
E4='**Evaluation:** files 1 - spec 1 - coupling 2 - risk 0 = 4'
E2='**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2'

three "$E5" "$E4" "$E2"
out=$(run | grep '^recommend')
check "one heavy of three stays inline" "$(field execution "$out")" "inline"
check "a four-band within the third is delegated" "$(field delegated "$out")" "2/3"

three "$E5" "$E5" "$E2"
check "a heavy majority recommends subagent" "$(field execution "$(run | grep '^recommend')")" "subagent"

three "$E4" "$E4" "$E2"
out=$(run | grep '^recommend')
check "four-band past the third is self-implemented" "$(field delegated "$out")" "0/3"
check "a self-implemented four-band needs opus" "$(field model "$out")" "opus"

# --- exits ---
plan "$(mktask 1 0 1 0 2)"
(cd "$REPO" && bash "$SCRIPT" docs/p.md >/dev/null 2>&1); check "a readable plan exits 0" "$?" "0"
printf '# No tasks\n' > "$REPO/docs/empty.md"
(cd "$REPO" && bash "$SCRIPT" docs/empty.md >/dev/null 2>&1); check "a plan with no tasks exits 1" "$?" "1"
(cd "$REPO" && bash "$SCRIPT" docs/missing.md >/dev/null 2>&1); check "a missing plan exits 2" "$?" "2"
(cd "$REPO" && bash "$SCRIPT" >/dev/null 2>&1); check "no argument exits 2" "$?" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
