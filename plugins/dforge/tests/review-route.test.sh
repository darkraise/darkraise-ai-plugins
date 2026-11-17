#!/usr/bin/env bash
# review-route is the review routing table as code. Each fixture task below
# pins one row, so a controller of any size reaches the same seat.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
ROUTE="$P/scripts/review-route"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <file> <needle>
  if grep -qF -- "$3" "$2" 2>/dev/null; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s] in %s\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
absent() { # absent <name> <file> <needle>
  if grep -qF -- "$3" "$2" 2>/dev/null; then printf 'FAIL - %s\n       unexpected: [%s] in %s\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Routing reads this session's Codex and agy gate files. A fixed session id and
# temporary directories keep the machine's real session state out of every case.
export DR_CODEX_SESSION_DIR="$TMP/sessions" DR_AGY_SESSION_DIR="$TMP/agy-sessions" CLAUDE_CODE_SESSION_ID=review-route-test
review_surface() { # review_surface <codex true|false|absent> [agy true|false|absent]
  local dir b
  rm -rf "$DR_CODEX_SESSION_DIR" "$DR_AGY_SESSION_DIR"
  for pair in "$DR_CODEX_SESSION_DIR:$1" "$DR_AGY_SESSION_DIR:${2:-absent}"; do
    dir=${pair%:*} b=${pair##*:}
    [ "$b" != absent ] || continue
    mkdir -p "$dir"
    printf '{"session_id":"review-route-test","usable":true,"review":%s}\n' "$b" > "$dir/review-route-test.json"
  done
}
review_surface true

# Fixture lines carry a leading | so a plan that quotes this suite still lints:
# plan-lint's part and Evaluation scans do not skip fenced blocks.
sed 's/^|//' > "$TMP/plan.md" <<'EOF'
|# Routing Fixture Plan
|
|**Goal:** Fixture.
|
|## Task index
|
|1. light low
|2. light mid
|3. heavy
|4. risky
|5. executor
|6. executor risky
|7. split
|8. risk three
|9. broken
|10. band five
|11. executor risk three
|12. band six
|
|### Task 1: light low
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 2: light mid
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 1 — spec 0 — coupling 1 — risk 1 = 3
|
|### Task 3: heavy
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4
|
|### Task 4: risky
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4
|
|### Task 5: executor
|
|**Implementer:** dforge:impl-sonnet-high
|**Executor:** codex gpt-6.1-sol / high
|**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3
|
|### Task 6: executor risky
|
|**Implementer:** dforge:impl-sonnet-high
|**Executor:** codex gpt-6.1-sol / high
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 2 = 3
|
|### Task 7: split
|
|#### Part A: small half
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|#### Part B: risky half
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5
|
|### Task 8: risk three
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 3 = 6
|
|### Task 9: broken
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** one plus one
|
|### Task 10: band five
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 2 - spec 2 - coupling 1 - risk 0 = 5
|
|### Task 11: executor risk three
|
|**Implementer:** dforge:impl-sonnet-high
|**Executor:** codex gpt-6.1-sol / high
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 3 = 4
|
|### Task 12: band six
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 2 - spec 2 - coupling 2 - risk 0 = 6
EOF

route() { # route <args...>; sets out and rc
  out=$(bash "$ROUTE" "$TMP/plan.md" "$@" 2>"$TMP/err"); rc=$?
}
rround() { # rround <plan> <round>; sets out and rc
  out=$(bash "$ROUTE" "$1" --plan-round "$2" 2>"$TMP/err"); rc=$?
}
shape_plan() { # shape_plan <file> <evaluation line>... - one task per line
  local f=$1 i=0 ev; shift
  { printf '# Shape\n\n'
    for ev in "$@"; do i=$((i + 1)); printf '### Task %s: t\n\n%s\n\n' "$i" "$ev"; done
  } > "$f"
}
# Plan rounds parse every task, so they run on the fixture without Task 9.
awk '/^### Task 9:/ { skip = 1 } /^### Task 10:/ { skip = 0 } !skip' "$TMP/plan.md" | grep -v '^9\. broken$' > "$TMP/round.md"
shape_plan "$TMP/light.md" '**Evaluation:** files 0 - spec 0 - coupling 1 - risk 2 = 3' '**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1'
shape_plan "$TMP/mid.md" '**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5' '**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1'

check "script exists" "$([ -f "$ROUTE" ] && echo yes || echo no)" "yes"

route --task 8
check "risk 3 goes to the heavy panel then Opus" "$out" "review-seat task=8 primary=panel:heavy+judge-opus fallback=dforge:judge-opus reason=risk"
check "a routed task exits 0" "$rc" "0"
for t in 1 4 12; do
  route --task "$t"
  check "Task $t below risk 3 exits 2" "$rc|$out" "2|"
done
present "a task below risk 3 is named" "$TMP/err" "only a risk-3 task gets a per-task review"
route --task 8 12
check "a batch exits 2" "$rc" "2"
route --task 7B
check "a part letter exits 2" "$rc" "2"

# --- the plan-round cap follows the depth ----------------------------------------
# A Claude plan's cap is 1 at light and standard, 2 at full (lib/depth.sh): the
# higher of its spec's Depth line and its riskiest task. The specs live in a
# throwaway repository so the plans' **Spec:** paths resolve.
git init -q "$TMP/drepo"
mkdir -p "$TMP/drepo/specs"
for d in light standard full; do
  printf '# Spec\n\n**Depth:** %s — fixture\n' "$d" > "$TMP/drepo/specs/$d.md"
done
depth_fixture() { # depth_fixture <file> <spec name> <evaluation line>... - one task per argument
  local f=$1 spec=$2 i=0 ev; shift 2
  { printf '# Depth Fixture\n\n**Spec:** `specs/%s.md`\n\n' "$spec"
    for ev in "$@"; do i=$((i + 1)); printf '### Task %s: t\n\n%s\n\n' "$i" "$ev"; done
  } > "$f"
}
EV0='**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1'
EV1='**Evaluation:** files 0 - spec 0 - coupling 1 - risk 1 = 2'
EV2='**Evaluation:** files 0 - spec 0 - coupling 1 - risk 2 = 3'
EV3='**Evaluation:** files 0 - spec 0 - coupling 1 - risk 3 = 4'
depth_fixture "$TMP/drepo/light.md" light "$EV0" "$EV1"
depth_fixture "$TMP/drepo/light-r2.md" light "$EV0" "$EV2"
depth_fixture "$TMP/drepo/light-r3.md" light "$EV0" "$EV3"
depth_fixture "$TMP/drepo/light-bad.md" light "$EV0" '**Evaluation:** one plus one'
depth_fixture "$TMP/drepo/standard.md" standard "$EV0"
depth_fixture "$TMP/drepo/full.md" full "$EV0"
depth_fixture "$TMP/drepo/missing.md" missing "$EV0"
rround "$TMP/drepo/light.md" 1
check "light: round 1 reviews at cap 1" "$rc:$out" "0:review-seat plan-round=1 primary=panel:plan fallback=dforge:judge-opus reason=round cap=1"
rround "$TMP/drepo/light.md" 2
check "light: round 2 exits 2" "$rc" "2"
present "light: round 2 names the cap" "$TMP/err" "past the cap (1)"
rround "$TMP/drepo/light-r2.md" 1
check "a light spec with a risk-2 task is standard: cap 1" "$rc:$out" "0:review-seat plan-round=1 primary=panel:plan fallback=dforge:judge-opus reason=round cap=1"
rround "$TMP/drepo/light-r2.md" 2
check "standard: round 2 exits 2" "$rc" "2"
present "standard: round 2 names the cap" "$TMP/err" "past the cap (1)"
rround "$TMP/drepo/standard.md" 1
check "a standard spec with a risk-0 task: cap 1" "$rc:$out" "0:review-seat plan-round=1 primary=panel:plan fallback=dforge:judge-opus reason=round cap=1"
rround "$TMP/drepo/light-r3.md" 2
check "a light spec with a risk-3 task is full: round 2 within cap 2" "$rc:$out" "0:review-seat plan-round=2 primary=dforge:judge-opus fallback=- reason=round cap=2"
rround "$TMP/drepo/light-r3.md" 3
check "full: a Claude plan has no round 3" "$rc" "2"
rround "$TMP/drepo/full.md" 1
check "a full spec with a risk-0 task stays at cap 2" "$rc:$out" "0:review-seat plan-round=1 primary=panel:plan fallback=dforge:judge-opus reason=round cap=2"
rround "$TMP/drepo/light-bad.md" 1
check "a light spec with an unparsable task routes at full: cap 2" "$rc:$out" "0:review-seat plan-round=1 primary=panel:plan fallback=dforge:judge-opus reason=round cap=2"
rround "$TMP/drepo/missing.md" 1
check "a Spec path that does not exist routes at full: cap 2" "$rc:$out" "0:review-seat plan-round=1 primary=panel:plan fallback=dforge:judge-opus reason=round cap=2"
review_surface false
rround "$TMP/drepo/light.md" 1
check "light with reviewers off: round 1 goes to Opus alone, cap 1" "$rc:$out" "0:review-seat plan-round=1 primary=dforge:judge-opus fallback=- reason=reviewers-off cap=1"
rround "$TMP/drepo/standard.md" 1
check "standard with reviewers off: round 1 goes to Opus alone, cap 1" "$rc:$out" "0:review-seat plan-round=1 primary=dforge:judge-opus fallback=- reason=reviewers-off cap=1"
review_surface true

# --- the ruling seat -------------------------------------------------------------
# Rulings go to Opus, except a list made only of cannot-verify items on no
# risk-3 task, which goes to Sonnet. The reason
# marks where a wrong verdict is expensive: the merge gate, a risk-3 task, and
# an intricate plan's preflight.
rule() { out=$(bash "$ROUTE" "$@" 2>"$TMP/err"); rc=$?; }
rule "$TMP/light.md" --ruling final-residual
check "final-residual is the merge gate on Opus" "$out" "review-seat ruling=final-residual tasks=plan primary=dforge:judge-opus fallback=- reason=merge-gate"
rule "$TMP/round.md" --ruling plan-conflict 8
check "an item on a risk-3 task goes to Opus" "$out" "review-seat ruling=plan-conflict tasks=8 primary=dforge:judge-opus fallback=- reason=risk"
rule "$TMP/round.md" --ruling breaker 3 8
check "a batch routes on its heaviest item" "$out" "review-seat ruling=breaker tasks=3,8 primary=dforge:judge-opus fallback=- reason=risk"
rule "$TMP/round.md" --ruling cannot-verify 4
check "a cannot-verify item goes to Sonnet" "$out" "review-seat ruling=cannot-verify tasks=4 primary=dforge:judge-sonnet-high fallback=- reason=simple-kind"
rule "$TMP/round.md" --ruling cannot-verify
check "a plan-wide cannot-verify goes to Sonnet" "$out" "review-seat ruling=cannot-verify tasks=plan primary=dforge:judge-sonnet-high fallback=- reason=simple-kind"
rule "$TMP/round.md" --ruling cannot-verify 8
check "a cannot-verify item on a risk-3 task goes to Opus" "$out" "review-seat ruling=cannot-verify tasks=8 primary=dforge:judge-opus fallback=- reason=risk"
rule "$TMP/round.md" --ruling cannot-verify 1 4
check "a cannot-verify batch goes to Sonnet" "$out" "review-seat ruling=cannot-verify tasks=1,4 primary=dforge:judge-sonnet-high fallback=- reason=simple-kind"
rule "$TMP/round.md" --ruling cannot-verify,breaker 1
check "a mixed list goes to Opus" "$out" "review-seat ruling=cannot-verify,breaker tasks=1 primary=dforge:judge-opus fallback=- reason=routine"
rule "$TMP/round.md" --ruling cannot-verify 1 8
check "a cannot-verify batch with one risk-3 task goes to Opus" "$out" "review-seat ruling=cannot-verify tasks=1,8 primary=dforge:judge-opus fallback=- reason=risk"
rule "$TMP/light.md" --ruling cannot-verify,final-residual
check "a list naming final-residual is the merge gate" "$out" "review-seat ruling=cannot-verify,final-residual tasks=plan primary=dforge:judge-opus fallback=- reason=merge-gate"
rule "$TMP/round.md" --ruling cannot-verify,preflight
check "a list with preflight on an intricate plan is intricate" "$out" "review-seat ruling=cannot-verify,preflight tasks=plan primary=dforge:judge-opus fallback=- reason=intricate"
for bad in cannot-verify, ,cannot-verify cannot-verify,,breaker cannot-verify,guess ""; do
  rule "$TMP/round.md" --ruling "$bad" 1
  check "a malformed kind list [$bad] exits 2" "$rc" "2"
done
rule "$TMP/round.md" --ruling preflight
check "preflight on an intricate plan goes to Opus" "$out" "review-seat ruling=preflight tasks=plan primary=dforge:judge-opus fallback=- reason=intricate"
rule "$TMP/light.md" --ruling preflight
check "preflight on a plain plan goes to Opus" "$out" "review-seat ruling=preflight tasks=plan primary=dforge:judge-opus fallback=- reason=routine"
rule "$TMP/round.md" --ruling blocked-plan 7B
check "a part id routes on its task" "$out" "review-seat ruling=blocked-plan tasks=7B primary=dforge:judge-opus fallback=- reason=routine"
rule "$TMP/round.md" --ruling guess 1
check "an unknown kind exits 2" "$rc" "2"
rule "$TMP/round.md" --ruling breaker 99
check "an unknown task exits 2" "$rc" "2"
rule "$TMP/round.md" --ruling breaker x
check "a malformed ruling id exits 2" "$rc" "2"
{ printf 'Host: codex\n'; cat "$TMP/light.md"; } > "$TMP/cdx-light.md"
rule "$TMP/cdx-light.md" --ruling breaker 1
check "a Codex-host plan exits 2 for a ruling" "$rc" "2"

# --- the review surface off ------------------------------------------------------
# While the session's gate has not opened the review surface, no route names a
# Codex seat, and the Claude seat it names has nothing to fall back to.
review_surface false
route --task 8
check "reviewers off: risk 3 goes to Opus alone" "$out" "review-seat task=8 primary=dforge:judge-opus fallback=- reason=reviewers-off"
check "reviewers off: a routed task still exits 0" "$rc" "0"
rround "$TMP/round.md" 1
check "reviewers off: an intricate plan's round 1 goes to Opus alone" "$out" "review-seat plan-round=1 primary=dforge:judge-opus fallback=- reason=reviewers-off cap=2"
rround "$TMP/light.md" 1
check "reviewers off: a plain plan's round 1 goes to Opus alone" "$out" "review-seat plan-round=1 primary=dforge:judge-opus fallback=- reason=reviewers-off cap=2"
rround "$TMP/round.md" 2
check "reviewers off: plan round 2 is unchanged" "$out" "review-seat plan-round=2 primary=dforge:judge-opus fallback=- reason=round cap=2"
review_surface absent
route --task 8
check "no session file is off" "$out" "review-seat task=8 primary=dforge:judge-opus fallback=- reason=reviewers-off"
rround "$TMP/round.md" 1
check "no session file keeps plan round 1 off the panel" "$out" "review-seat plan-round=1 primary=dforge:judge-opus fallback=- reason=reviewers-off cap=2"
review_surface true
printf 'not json' > "$DR_CODEX_SESSION_DIR/review-route-test.json"
route --task 8
check "a torn session file is off" "$out" "review-seat task=8 primary=dforge:judge-opus fallback=- reason=reviewers-off"
review_surface true
CLAUDE_CODE_SESSION_ID="" route --task 8
check "no session id is off, whatever is on disk" "$out" "review-seat task=8 primary=dforge:judge-opus fallback=- reason=reviewers-off"
route --task 8
check "an open review surface routes to the panel again" "$out" "review-seat task=8 primary=panel:heavy+judge-opus fallback=dforge:judge-opus reason=risk"
review_surface false true
route --task 8
check "agy alone opens the heavy panel at risk 3" "$(grep -o 'primary=[^ ]*' <<<"$out")" "primary=panel:heavy+judge-opus"
rround "$TMP/round.md" 1
check "agy alone opens the plan panel" "$(grep -o 'primary=[^ ]*' <<<"$out")" "primary=panel:plan"
review_surface false false
route --task 8
check "no surface routes to Claude as reviewers-off" "$(grep -o 'reason=[^ ]*' <<<"$out")" "reason=reviewers-off"
review_surface true

route --task 9
check "an unparseable Evaluation exits 2" "$rc" "2"
check "an unparseable Evaluation prints nothing on stdout" "$out" ""
route --task 99
check "an unknown task exits 2" "$rc" "2"
route --task x
check "a malformed id exits 2" "$rc" "2"
route --task
check "--task with no id exits 2" "$rc" "2"
route --plan-round 0
check "plan round 0 exits 2" "$rc" "2"
route --bogus 1
check "an unknown flag exits 2" "$rc" "2"
out=$(bash "$ROUTE" "$TMP/nope.md" --task 1 2>/dev/null); rc=$?
check "a missing plan exits 2" "$rc" "2"

{ printf 'Host: codex\n'; cat "$TMP/plan.md"; } > "$TMP/codex.md"
out=$(bash "$ROUTE" "$TMP/codex.md" --task 1 2>"$TMP/err"); rc=$?
check "a Codex-host plan exits 2" "$rc" "2"
present "a Codex-host plan names native-codex.md" "$TMP/err" "native-codex.md"
{ printf '# Fenced Host\n\n```markdown\n**Host:** codex\n```\n'; sed 1d "$TMP/plan.md"; } > "$TMP/fenced-host.md"
out=$(bash "$ROUTE" "$TMP/fenced-host.md" --task 8 2>/dev/null); rc=$?
check "a fenced Host: codex example leaves a Claude plan routable" "$rc|$out" "0|$(bash "$ROUTE" "$TMP/plan.md" --task 8 2>/dev/null)"

sed 's/$/\r/' "$TMP/plan.md" > "$TMP/crlf.md"
out=$(bash "$ROUTE" "$TMP/crlf.md" --task 8 2>/dev/null)
check "a CRLF plan routes" "$out" "review-seat task=8 primary=panel:heavy+judge-opus fallback=dforge:judge-opus reason=risk"

# --- ruling seat prose -----------------------------------------------------------
absent "review-route never prints judge-fable" "$ROUTE" 'judge-fable'

# --- the final whole-branch review ---
shape_plan "$TMP/final-plain.md" '**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1' \
  '**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5'
rule "$TMP/final-plain.md" --final
check "final: a plain plan takes judge-opus" "$out" "review-seat final primary=dforge:judge-opus fallback=- reason=plain external=on"
shape_plan "$TMP/final-risk.md" '**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1' \
  '**Evaluation:** files 0 - spec 0 - coupling 1 - risk 3 = 4'
rule "$TMP/final-risk.md" --final
check "final: risk 3 is intricate" "$out" \
  "review-seat final primary=dforge:judge-opus fallback=- reason=intricate external=on"
shape_plan "$TMP/final-six.md" '**Evaluation:** files 1 - spec 1 - coupling 2 - risk 2 = 6'
rule "$TMP/final-six.md" --final
check "final: total 6 is intricate" "$out" \
  "review-seat final primary=dforge:judge-opus fallback=- reason=intricate external=on"
review_surface false
rule "$TMP/final-plain.md" --final
check "final: the seat ignores the gate, and no open surface says external=off" "$out" "review-seat final primary=dforge:judge-opus fallback=- reason=plain external=off"
review_surface false true
rule "$TMP/final-plain.md" --final
check "final: an open agy surface alone says external=on" "$out" "review-seat final primary=dforge:judge-opus fallback=- reason=plain external=on"
rule "$TMP/final-plain.md" --final extra
check "final: an extra argument exits 2" "$rc" "2"
rule "$TMP/final-plain.md" --task
check "final: --task with no id still exits 2" "$rc" "2"

# --- a Codex-host plan: the plan-round cap ---
FF="$TMP/ff"
git init -q "$FF"
mkdir -p "$FF/docs" "$FF/.dforge/sdd/plan"
# The cap reads the raw total (Task 2: raw 5, weighted 7), so it is 2, not 3.
mkdir -p "$FF/.dforge/sdd/native"
sed 's/^|//' > "$FF/docs/native.md" <<'EOF'
|# Native Fixture
|
|**Host:** codex
|**Routing policy:** codex-v4
|**Execution:** inline — codex gpt-6.1-sol / xhigh — x
|
|### Task 1: low
|
|**Files:**
|- Modify: `a.txt`
|
|**Implementer:** codex gpt-6-luna / high
|**Evaluation:** files=0, spec=1, coupling=0, risk=0; weighted routing score=1
|**Assignment source:** rubric
|
|### Task 2: weighted above raw
|
|**Files:**
|- Modify: `b.txt`
|
|**Implementer:** codex gpt-6-astra / medium
|**Evaluation:** files=1, spec=1, coupling=1, risk=2; weighted routing score=7
|**Assignment source:** rubric
|
|### Task 3: escalated
|
|**Files:**
|- Modify: `c.txt`
|
|**Implementer:** codex gpt-6.1-sol / high
|**Evaluation:** files=1, spec=1, coupling=1, risk=1; weighted routing score=5
|**Assignment source:** rubric
|
|### Task 4: reserve
|
|**Files:**
|- Modify: `d.txt`
|
|**Implementer:** codex gpt-6-astra / max
|**Evaluation:** files=1, spec=1, coupling=1, risk=1; weighted routing score=5
|**Assignment source:** human
|
|### Task 5: inline
|
|**Files:**
|- Modify: `e.txt`
|
|**Implementer:** codex gpt-6-luna / low
|**Evaluation:** files=0, spec=0, coupling=0, risk=0; weighted routing score=0
|**Assignment source:** rubric
EOF
sed 's/^|//' > "$FF/.dforge/sdd/native/progress.md" <<'EOF'
|# SDD ledger — plan: docs/native.md
|Task 3: implementer codex gpt-6.1-sol / high (assigned; base aaaaaaa)
|Task 3: fix round 4/5 (1 addressed, 1 open — x; commits aaaaaaa..bbbbbbb; escalated gpt-6.1-sol / high -> gpt-6-astra / high)
|Task 3: complete (commits aaaaaaa..ccccccc, review clean; scores spec 17 / scope 18 / verification 15 / quality 16, seat codex gpt-6-astra/xhigh) — done: x
|Task 5: implementer inline (assigned; base ddddddd)
EOF
native() { out=$(bash "$ROUTE" "$FF/docs/native.md" "$@" 2>"$TMP/err"); rc=$?; }
native --plan-round 1
check "native plan round: the raw total sets the cap, at the judge floor" "$out" \
  "review-seat plan-round=1 primary=native:gpt-6-astra/high fallback=- reason=round cap=2"
native --plan-round 3
check "native plan round: one cap-critical round" "$out" \
  "review-seat plan-round=3 primary=native:gpt-6-astra/high fallback=- reason=cap-critical cap=2"
native --plan-round 4
check "native plan round: past the cap exits 2" "$rc" "2"
awk '{ print } /^\*\*Routing policy:\*\*/ { print "**Spec:** `specs/light.md`" }' "$FF/docs/native.md" > "$TMP/drepo/native-light.md"
rround "$TMP/drepo/native-light.md" 1
check "native plan round: a light spec leaves the native cap alone" "$rc:$out" \
  "0:review-seat plan-round=1 primary=native:gpt-6-astra/high fallback=- reason=round cap=2"
rround "$TMP/drepo/native-light.md" 3
check "native plan round: a light spec keeps the cap-critical round" "$out" \
  "review-seat plan-round=3 primary=native:gpt-6-astra/high fallback=- reason=cap-critical cap=2"
native --task 1
check "native: a task seat still exits 2" "$rc" "2"
# A score with a leading zero is read as decimal, as plan_scores reads it.
sed 's/^\*\*Evaluation:\*\* files=0,/**Evaluation:** files=08,/' "$FF/docs/native.md" > "$FF/docs/native-zero.md"
out=$(bash "$ROUTE" "$FF/docs/native-zero.md" --plan-round 1 2>"$TMP/err"); rc=$?
check "native plan round: a score written 08 is read as 8" "$rc:$out" \
  "0:review-seat plan-round=1 primary=native:gpt-6-astra/high fallback=- reason=round cap=3"

# --- README, version and program amendment -------------------------------------
# The version is read from the Claude manifest, so a release bump needs no edit here.
version=$(sed -nE 's/^[[:space:]]*"version": "([^"]+)".*/\1/p' "$P/.claude-plugin/plugin.json" | head -n 1)
check "the Claude manifest names a release version" "$([[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo yes || echo no)" "yes"
present "the Codex manifest carries the Claude manifest's version" "$P/.codex-plugin/plugin.json" "\"version\": \"$version\""

# --- ruling kinds ------------------------------------------------------------
bash "$ROUTE" "$TMP/round.md" --ruling nonsense-kind 1 >/dev/null 2>&1
check "an unknown ruling kind is still rejected" "$?" "2"

# --- the external review reference -----------------------------------------
check "the external review reference exists" "$([ -f "$P/reference/external-review.md" ] && echo yes || echo no)" "yes"

# --- the shared Evaluation reader ---
# Two shipped defects: a fenced example line escalated the seat to the risk-3
# rung, and a stale line above `#### Part A` routed a split task on the score
# that forced the split.
# The suite leaves the review surface closed, and a closed surface routes every
# seat to Claude with reason=reviewers-off, which is not what these cases are about.
review_surface true

seat() { # seat <file> <id>; sets out and rc
  out=$(bash "$ROUTE" "$1" --task "$2" 2>"$TMP/err"); rc=$?
}
HEAVY="primary=panel:heavy+judge-opus fallback=dforge:judge-opus reason=risk"

printf '# P\n\n### Task 1: Fenced\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 3 = 6\n```\n' > "$TMP/ev-fenced.md"
seat "$TMP/ev-fenced.md" 1
check "a fenced example does not escalate the task to risk 3" "$rc|$out" "2|"

printf '# P\n\n### Task 1: Split\n\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 1 = 6\n\n#### Part A: a\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n#### Part B: b\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 3 = 5\n' > "$TMP/ev-split.md"
seat "$TMP/ev-split.md" 1
check "a whole-task id routes on its riskiest part" "$out" "review-seat task=1 $HEAVY"

# A part filter that does not skip fences reads an example inside the part.
printf '# P\n\n### Task 1: Split with an example\n\n#### Part A: a\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 3 = 6\n```\n\n#### Part B: b\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n' > "$TMP/ev-partfence.md"
seat "$TMP/ev-partfence.md" 1
check "a fenced example inside a part does not escalate the whole task" "$rc|$out" "2|"

out=$(bash "$ROUTE" "$TMP/round.md" --ruling acceptance-ambiguous 2>&1); status=$?
check "acceptance-ambiguous: exit 0" "$status" "0"
check "acceptance-ambiguous goes to the ruling seat" "$out" \
  "review-seat ruling=acceptance-ambiguous tasks=plan primary=dforge:judge-opus fallback=- reason=routine"

printf '# P\n\n### Task 1: Unscored\n\n**Implementer:** dforge:impl-sonnet-high\n\nBody.\n' > "$TMP/unscored.md"
seat "$TMP/unscored.md" 1
check "an unscored task exits 2" "$rc|$out" "2|"
present "an unscored task names the missing Evaluation line" "$TMP/err" "Task 1 has no **Evaluation:** line"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
