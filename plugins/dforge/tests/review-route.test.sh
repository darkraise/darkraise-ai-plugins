#!/usr/bin/env bash
# review-route is the review routing table as code. Each fixture task below
# pins one row, so a controller of any size reaches the same seat. The prose
# checks appended later pin the skill text that tells a controller to call it.
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

# Routing reads this session's Codex gate file. A fixed session id and a
# temporary directory keep the machine's real session state out of every case.
export DR_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=review-route-test
review_surface() { # review_surface <true|false|absent>
  rm -rf "$DR_CODEX_SESSION_DIR"
  [ "$1" != absent ] || return 0
  mkdir -p "$DR_CODEX_SESSION_DIR"
  printf '{"session_id":"review-route-test","usable":true,"review":%s,"lane":false}\n' "$1" \
    > "$DR_CODEX_SESSION_DIR/review-route-test.json"
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
|
|### Task 1: light low
|
|**Implementer:** dforge:impl-sonnet-low
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
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|#### Part B: risky half
|
|**Implementer:** dforge:impl-opus-medium
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5
|
|### Task 8: risk three
|
|**Implementer:** dforge:impl-opus-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 3 = 6
|
|### Task 9: broken
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** one plus one
|
|### Task 10: band five
|
|**Implementer:** dforge:impl-opus-medium
|**Evaluation:** files 2 - spec 2 - coupling 1 - risk 0 = 5
|
|### Task 11: executor risk three
|
|**Implementer:** dforge:impl-sonnet-high
|**Executor:** codex gpt-6.1-sol / high
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 3 = 4
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

route --task 1
check "total 1: light Codex, Sonnet fallback" "$out" "review-seat task=1 primary=codex:light fallback=dforge:judge-sonnet-high review=group reason=band"
check "a routed task exits 0" "$rc" "0"
route --task 2
check "total 3 with em dashes: light Codex, Sonnet fallback" "$out" "review-seat task=2 primary=codex:light fallback=dforge:judge-sonnet-high review=group reason=band"
route --task 3
check "total 4 at risk 1: light Codex, Opus fallback" "$out" "review-seat task=3 primary=codex:light fallback=dforge:judge-opus review=group reason=band"
route --task 4
check "risk 2 takes its band: light Codex, Opus fallback" "$out" "review-seat task=4 primary=codex:light fallback=dforge:judge-opus review=task reason=band"
route --task 5
check "an Executor task is reviewed by its band judge, never Codex" "$out" "review-seat task=5 primary=dforge:judge-sonnet-high fallback=- review=group reason=executor"
route --task 6
check "an Executor task at risk 2 takes its band" "$out" "review-seat task=6 primary=dforge:judge-sonnet-high fallback=- review=task reason=executor"
route --task 11
check "an Executor task at risk 3 goes to Opus alone" "$out" "review-seat task=11 primary=dforge:judge-opus fallback=- review=task reason=executor"
route --task 7A
check "a part routes on its own Evaluation" "$out" "review-seat task=7A primary=codex:light fallback=dforge:judge-sonnet-high review=group reason=band"
route --task 7B
check "the risk-2 part takes light Codex, Opus fallback" "$out" "review-seat task=7B primary=codex:light fallback=dforge:judge-opus review=task reason=band"
route --task 7
check "a split task without a part routes on its heaviest part" "$out" "review-seat task=7 primary=codex:light fallback=dforge:judge-opus review=task reason=band"
route --task 8
check "risk 3 goes to Astra then Opus" "$out" "review-seat task=8 primary=codex:heavy+judge-opus fallback=dforge:judge-opus review=task reason=risk"
route --task 10
check "total 5 at risk 0: light Codex, Opus fallback" "$out" "review-seat task=10 primary=codex:light fallback=dforge:judge-opus review=task reason=band"

route --task 1 2
check "a batch takes its highest total" "$out" "review-seat task=1,2 primary=codex:light fallback=dforge:judge-sonnet-high reason=band"
route --task 1 3
check "a batch crossing into the Opus fallback band" "$out" "review-seat task=1,3 primary=codex:light fallback=dforge:judge-opus reason=band"
route --task 1 5
check "one Executor task makes the whole batch Claude-reviewed" "$out" "review-seat task=1,5 primary=dforge:judge-sonnet-high fallback=- reason=executor"

rround "$TMP/round.md" 1
check "a Claude plan's round 1 is Codex with an Opus fallback, cap 2 whatever its totals" "$out" "review-seat plan-round=1 primary=codex:plan fallback=dforge:judge-opus reason=round cap=2"
rround "$TMP/light.md" 1
check "a light plan's round 1 is cap 2 too" "$out" "review-seat plan-round=1 primary=codex:plan fallback=dforge:judge-opus reason=round cap=2"
rround "$TMP/light.md" 2
check "a light plan's round 2 is a round within cap 2" "$out" "review-seat plan-round=2 primary=dforge:judge-opus fallback=- reason=round cap=2"
rround "$TMP/light.md" 3
check "a Claude plan has no round 3" "$rc" "2"
rround "$TMP/mid.md" 2
check "highest total 5: round 2 is within cap 2" "$out" "review-seat plan-round=2 primary=dforge:judge-opus fallback=- reason=round cap=2"
rround "$TMP/round.md" 3
check "an intricate Claude plan has no cap-critical round 3" "$rc" "2"
shape_plan "$TMP/slice.md" '**Evaluation:** files 2 - spec 2 - coupling 1 - risk 3 = 8'
rround "$TMP/slice.md" 2
check "a total-8 plan's round 2 is a round within cap 2" "$out" "review-seat plan-round=2 primary=dforge:judge-opus fallback=- reason=round cap=2"
rround "$TMP/slice.md" 3
check "a total-8 plan has no round 3" "$rc" "2"
rround "$TMP/plan.md" 1
check "a Claude plan round with an unparsable Evaluation line routes at full: cap 2" "$rc:$out" "0:review-seat plan-round=1 primary=codex:plan fallback=dforge:judge-opus reason=round cap=2"

# --- the plan-round cap follows the depth ----------------------------------------
# A Claude plan's cap is 0 at light, 1 at standard, 2 at full (lib/depth.sh): the
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
check "light: round 1 runs no review" "$rc:$out" "0:review-seat plan-round=1 primary=none fallback=- reason=depth-light cap=0"
rround "$TMP/drepo/light.md" 2
check "light: round 2 exits 2" "$rc" "2"
present "light: round 2 names the cap" "$TMP/err" "past the cap (0)"
rround "$TMP/drepo/light-r2.md" 1
check "a light spec with a risk-2 task is standard: cap 1" "$rc:$out" "0:review-seat plan-round=1 primary=codex:plan fallback=dforge:judge-opus reason=round cap=1"
rround "$TMP/drepo/light-r2.md" 2
check "standard: round 2 exits 2" "$rc" "2"
present "standard: round 2 names the cap" "$TMP/err" "past the cap (1)"
rround "$TMP/drepo/standard.md" 1
check "a standard spec with a risk-0 task: cap 1" "$rc:$out" "0:review-seat plan-round=1 primary=codex:plan fallback=dforge:judge-opus reason=round cap=1"
rround "$TMP/drepo/light-r3.md" 2
check "a light spec with a risk-3 task is full: round 2 within cap 2" "$rc:$out" "0:review-seat plan-round=2 primary=dforge:judge-opus fallback=- reason=round cap=2"
rround "$TMP/drepo/light-r3.md" 3
check "full: a Claude plan has no round 3" "$rc" "2"
rround "$TMP/drepo/full.md" 1
check "a full spec with a risk-0 task stays at cap 2" "$rc:$out" "0:review-seat plan-round=1 primary=codex:plan fallback=dforge:judge-opus reason=round cap=2"
rround "$TMP/drepo/light-bad.md" 1
check "a light spec with an unparsable task routes at full: cap 2" "$rc:$out" "0:review-seat plan-round=1 primary=codex:plan fallback=dforge:judge-opus reason=round cap=2"
rround "$TMP/drepo/missing.md" 1
check "a Spec path that does not exist routes at full: cap 2" "$rc:$out" "0:review-seat plan-round=1 primary=codex:plan fallback=dforge:judge-opus reason=round cap=2"
review_surface false
rround "$TMP/drepo/light.md" 1
check "light with Codex off: still no review round" "$rc:$out" "0:review-seat plan-round=1 primary=none fallback=- reason=depth-light cap=0"
rround "$TMP/drepo/standard.md" 1
check "standard with Codex off: round 1 goes to Opus alone, cap 1" "$rc:$out" "0:review-seat plan-round=1 primary=dforge:judge-opus fallback=- reason=codex-off cap=1"
review_surface true

# --- the ruling seat -------------------------------------------------------------
# Rulings go to Opus, except a list made only of cannot-verify and
# executor-empty-diff kinds on no risk-3 task, which goes to Sonnet. The reason
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
rule "$TMP/round.md" --ruling cannot-verify,executor-empty-diff 1 4
check "a list of Sonnet kinds goes to Sonnet" "$out" "review-seat ruling=cannot-verify,executor-empty-diff tasks=1,4 primary=dforge:judge-sonnet-high fallback=- reason=simple-kind"
rule "$TMP/round.md" --ruling cannot-verify,codex-empty-diff 1
check "the legacy kind joins a Sonnet list as given" "$out" "review-seat ruling=cannot-verify,codex-empty-diff tasks=1 primary=dforge:judge-sonnet-high fallback=- reason=simple-kind"
rule "$TMP/round.md" --ruling cannot-verify,breaker 1
check "a mixed list goes to Opus" "$out" "review-seat ruling=cannot-verify,breaker tasks=1 primary=dforge:judge-opus fallback=- reason=routine"
rule "$TMP/round.md" --ruling cannot-verify,executor-empty-diff 1 8
check "a Sonnet list with one risk-3 task goes to Opus" "$out" "review-seat ruling=cannot-verify,executor-empty-diff tasks=1,8 primary=dforge:judge-opus fallback=- reason=risk"
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
route --task 1
check "codex off: total 1 goes to Sonnet alone" "$out" "review-seat task=1 primary=dforge:judge-sonnet-high fallback=- review=group reason=codex-off"
check "codex off: a routed task still exits 0" "$rc" "0"
route --task 2
check "codex off: total 3 goes to Sonnet alone" "$out" "review-seat task=2 primary=dforge:judge-sonnet-high fallback=- review=group reason=codex-off"
route --task 3
check "codex off: total 4 goes to Opus alone" "$out" "review-seat task=3 primary=dforge:judge-opus fallback=- review=group reason=codex-off"
route --task 10
check "codex off: total 5 goes to Opus alone" "$out" "review-seat task=10 primary=dforge:judge-opus fallback=- review=task reason=codex-off"
route --task 4
check "codex off: risk 2 at total 4 takes its band" "$out" "review-seat task=4 primary=dforge:judge-opus fallback=- review=task reason=codex-off"
route --task 8
check "codex off: risk 3 goes to Opus alone" "$out" "review-seat task=8 primary=dforge:judge-opus fallback=- review=task reason=codex-off"
route --task 7
check "codex off: a split task routes on its heaviest part" "$out" "review-seat task=7 primary=dforge:judge-opus fallback=- review=task reason=codex-off"
route --task 1 2
check "codex off: a batch takes its highest total" "$out" "review-seat task=1,2 primary=dforge:judge-sonnet-high fallback=- reason=codex-off"
route --task 5
check "codex off: an Executor task is unchanged" "$out" "review-seat task=5 primary=dforge:judge-sonnet-high fallback=- review=group reason=executor"
route --task 6
check "codex off: an Executor task at risk 2 is unchanged" "$out" "review-seat task=6 primary=dforge:judge-sonnet-high fallback=- review=task reason=executor"
rround "$TMP/round.md" 1
check "codex off: an intricate plan's round 1 goes to Opus alone" "$out" "review-seat plan-round=1 primary=dforge:judge-opus fallback=- reason=codex-off cap=2"
rround "$TMP/light.md" 1
check "codex off: a plain plan's round 1 goes to Opus alone" "$out" "review-seat plan-round=1 primary=dforge:judge-opus fallback=- reason=codex-off cap=2"
rround "$TMP/round.md" 2
check "codex off: plan round 2 is unchanged" "$out" "review-seat plan-round=2 primary=dforge:judge-opus fallback=- reason=round cap=2"
review_surface absent
route --task 3
check "no session file is off" "$out" "review-seat task=3 primary=dforge:judge-opus fallback=- review=group reason=codex-off"
rround "$TMP/round.md" 1
check "no session file keeps plan round 1 off Codex" "$out" "review-seat plan-round=1 primary=dforge:judge-opus fallback=- reason=codex-off cap=2"
review_surface true
printf 'not json' > "$DR_CODEX_SESSION_DIR/review-route-test.json"
route --task 1
check "a torn session file is off" "$out" "review-seat task=1 primary=dforge:judge-sonnet-high fallback=- review=group reason=codex-off"
review_surface true
CLAUDE_CODE_SESSION_ID="" route --task 1
check "no session id is off, whatever is on disk" "$out" "review-seat task=1 primary=dforge:judge-sonnet-high fallback=- review=group reason=codex-off"
route --task 1
check "an open review surface routes to Codex again" "$out" "review-seat task=1 primary=codex:light fallback=dforge:judge-sonnet-high review=group reason=band"

route --task 9
check "an unparseable Evaluation exits 2" "$rc" "2"
check "an unparseable Evaluation prints nothing on stdout" "$out" ""
route --task 99
check "an unknown task exits 2" "$rc" "2"
route --task 7C
check "an unknown part exits 2" "$rc" "2"
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

sed 's/$/\r/' "$TMP/plan.md" > "$TMP/crlf.md"
out=$(bash "$ROUTE" "$TMP/crlf.md" --task 4 2>/dev/null)
check "a CRLF plan routes" "$out" "review-seat task=4 primary=codex:light fallback=dforge:judge-opus review=task reason=band"

# --- plan review prose ---------------------------------------------------------
WP="$P/skills/writing-plans/SKILL.md"
PRP="$P/skills/writing-plans/references/plan-reviewer-prompt.md"
present "writing-plans routes each round" "$P/skills/writing-plans/references/lint-and-review.md" 'scripts/review-route PLAN_FILE --plan-round <r>'
present "writing-plans snapshots the plan before each round" "$P/skills/writing-plans/references/lint-and-review.md" '<workspace>/plan-round-<r>.md'
present "writing-plans runs the Codex plan kind" "$P/skills/writing-plans/references/lint-and-review.md" '--kind plan'
present "writing-plans writes the delta" "$P/skills/writing-plans/references/lint-and-review.md" '<workspace>/plan-delta-<r>.diff'
present "writing-plans caps rounds by score" "$P/skills/writing-plans/references/lint-and-review.md" 'below the `cap=` that `review-route` printed'
present "writing-plans re-rounds only on Critical or a low score" "$P/skills/writing-plans/references/lint-and-review.md" 'Run the next round only when a round returned'
present "writing-plans gives a Codex plan's Critical at the cap one more round" "$P/skills/writing-plans/references/lint-and-review.md" 'earns exactly one more'
present "writing-plans caps a Claude plan at two rounds" "$P/skills/writing-plans/references/lint-and-review.md" 'On a Claude plan the cap is 2 whatever the task totals'
absent "writing-plans no longer derives a Claude cap from the totals" <(cat "$P/skills/writing-plans/SKILL.md" "$P/skills/writing-plans/references/"*.md) 'printed: 1 when the plan'"'"'s highest'
present "writing-plans states the heavy-majority rule" "$P/skills/writing-plans/references/execution-line.md" '`subagent` when more than half the tasks are heavy'
present "writing-plans raises a delegating inline effort" "$P/skills/writing-plans/references/execution-line.md" 'raised to `high` when any task is'
present "writing-plans falls back to Opus on exit 2" "$P/skills/writing-plans/references/lint-and-review.md" 'exit 2, review with `dforge:judge-opus` (on a Codex-host plan, a native'
present "writing-plans dispatches the native plan-review seat" "$P/skills/writing-plans/references/lint-and-review.md" '**`primary=native:<model>/<effort>`** (every round of a Codex-host plan)'
present "final review records the native fix seat" "$P/reference/final-review.md" 'On a Codex-host plan it prints `primary=native:<model>/<effort>`'
present "the plan reviewer prompt names both round-1 Claude seats" "$PRP" 'round produced nothing (`dforge:judge-opus`)'
present "using-dforge states the mixed-mode rule" "$P/skills/using-dforge/SKILL.md" 'an inline plan delegates those'
present "README states mixed mode" "$P/README.md" '`--effort high` once it delegates'
present "README caps plan review at two rounds" "$P/README.md" 'at most two rounds on a Claude plan'
absent "README no longer caps plan review by task total" "$P/README.md" 'capped by the plan'"'"'s highest task total'
absent "writing-plans no longer dispatches a fresh full review each round" <(cat "$P/skills/writing-plans/SKILL.md" "$P/skills/writing-plans/references/"*.md) 'dispatch a fresh full review'
present "the prompt file has a Codex round-1 section" "$PRP" '## Round 1 on Codex'
present "the Codex round-1 prompt names its schema" "$PRP" 'codex-plan-review-schema.json'
# A Claude judge reads files with a Read tool; Codex has none, and its only
# file access is a command. Sent the template's no-commands line unchanged, the
# seat's own approval layer refuses the read and it returns a well-formed
# review of nothing - scoring every criterion 10, the schema's "uncertain".
present "the Codex round-1 prompt permits read-only commands" "$PRP" 'You are running read-only'
present "the Codex round-1 prompt still forbids edits and subagents" "$PRP" 'Do not modify any file, and do not dispatch subagents'
present "a native Codex judge gets the read-only line in every round" "$PRP" 'In this template and the Later rounds one, make change 3 of'
present "the prompt file has a delta template" "$PRP" '## Later rounds'
present "the delta template takes the delta file" "$PRP" '[DELTA_FILE]'
present "the delta template verdicts prior findings" "$PRP" '[ADDRESSED|NOT ADDRESSED]'
present "the delta template may read beyond the delta" "$PRP" 'The delta is where to look first, not the limit of'

# --- the session gate in writing-plans -------------------------------------------
present "writing-plans runs the gate before each round" "$P/skills/writing-plans/references/lint-and-review.md" 'run `scripts/codex-gate` (say its line aloud when it ends `source=probe`),'
present "writing-plans routes a codex-off round 1 by intricacy" "$P/skills/writing-plans/references/lint-and-review.md" '**`reason=codex-off`** (round 1 while the gate has not opened the review'
present "writing-plans offers the lane only on lane=true" "$P/skills/writing-plans/references/assignment-procedure.md" 'for every executor whose gate prints `lane=true`'

# --- planning self-review ------------------------------------------------------
BS="$P/skills/brainstorming/SKILL.md"
present "brainstorming names the self-review block" "$BS" '`Self-review (round 1 of 1):`'
present "writing-plans names the self-review block" "$WP" '`Self-review (round 1 of 1):`'
present "brainstorming self-reviews a bounded design" "$BS" '4. **Self-review the design**'
present "brainstorming keeps the round with the main agent" "$P/skills/brainstorming/references/spec-self-review.md" 'never through a subagent'
present "writing-plans keeps the round with the main agent" "$WP" 'never through a subagent'
present "brainstorming gives a revision one new round" "$BS" 'A revision your human partner asks for gets one new round'
present "writing-plans gives a revision one new round" "$WP" 'A revision your human partner asks for gets one new round'
present "writing-plans posts the block before plan review" "$WP" 'before the first plan-review round'
present "brainstorming flags a skipped round" "$BS" 'I'"'"'ll skip the self-review'
absent "brainstorming no longer re-runs a review loop" <(cat "$P/skills/brainstorming/SKILL.md" "$P/skills/brainstorming/references/"*.md) 're-run the spec review loop'

# --- what a spec must carry -------------------------------------------------------
present "brainstorming proposes a do-less approach" "$P/skills/brainstorming/references/design-phase.md" 'Make one of them the do-less option'
present "a spec carries an Acceptance section" "$P/skills/brainstorming/references/spec-document.md" 'Every spec has an `## Acceptance` section'
present "acceptance names what must not happen" "$P/skills/brainstorming/references/spec-document.md" 'at least one thing that must not happen'
present "a spec carries its riskiest assumption" "$P/skills/brainstorming/references/spec-document.md" 'Every spec has a `## Riskiest assumption` section'
present "an unverified riskiest assumption goes first in the plan" "$P/skills/brainstorming/references/spec-document.md" '`unverified — the plan'"'"'s first task verifies it`'
present "the spec self-review checks acceptance" "$P/skills/brainstorming/references/spec-self-review.md" '6. **Acceptance:**'
present "the spec self-review checks the riskiest assumption" "$P/skills/brainstorming/references/spec-self-review.md" '7. **Riskiest assumption:**'
present "the plan's first task verifies the spec's riskiest assumption" "$WP" 'Task 1 is that verifying step'
present "the live spec self-review checks acceptance ratings" "$P/skills/brainstorming/references/spec-self-review.md" 'no rating other than `high` or `confirmed` appears'
present "the live spec self-review requires assumption evidence" "$P/skills/brainstorming/references/spec-self-review.md" 'section is present and names its evidence'

# --- task review prose -----------------------------------------------------------
SDD="$P/skills/subagent-driven-development/SKILL.md"
. "$HERE/fixtures/sdd-text.sh"
DT="$P/reference/delegated-task.md"
TRP="$P/skills/subagent-driven-development/references/task-reviewer-prompt.md"
present "the Seats table routes the task reviewer" "$DT" '| Task reviewer | The seat `scripts/review-route PLAN_FILE --task <N>` prints'
present "the delegated loop runs the light tier for codex:light" "$DT" '`codex:light` is `--tier light`'
present "the delegated loop has the risk 3 section" "$DT" '**Risk 3.** On `primary=codex:heavy+judge-opus`'
absent "the delegated loop drops the risk 2 section" "$DT" '**Risk 2 and above.**'
present "the delegated loop falls back to Opus on a failed route" "$DT" 'seat it names as printed, and say why, quoting that'
present "the task seats pair Codex with Opus at risk 3" "$P/reference/executor-lane.md" 'and `codex:heavy+judge-opus` at risk 3.'
present "the second pass points at the delegated loop" "$P/reference/executor-lane.md" 'per [delegated-task.md](delegated-task.md) §3 Review the task.'
absent "README drops risk 2 Fable reviews" "$P/README.md" 'at risk 2 or above'
present "the second pass runs at risk 3 only" "$P/skills/subagent-driven-development/references/task-reviewer-prompt.md" '[Include this section only on a risk 3 task whose Codex seat'
check "SDD no longer averages three seats" "$(sdd_text | grep -cF -- 'average each criterion')" "0"
absent "the delegated loop does not average three seats" "$DT" 'average each criterion'
check "SDD no longer writes K=3" "$(sdd_text | grep -cF -- 'K=3')" "0"
absent "the delegated loop does not write K=3" "$DT" 'K=3'
present "the delegated loop writes the seat clause" "$DT" ', seat <seat>'
present "the delegated loop keeps the runner name" "$DT" 'run-codex-review.sh'
present "the scoped re-review names its judge seats" "$DT" '| Scoped re-review | `dforge:judge-sonnet-high`; `dforge:judge-opus` for a subtle concurrency fix | None |'
# A breaker CONFIRMED-GAP is carried into the next dependent task; completion
# has to accept it, or the loop has no legal next step.
present "a carried breaker gap lets the task complete" "$DT" 'confirmed and carried into a later task, with a ruling at the cap'
present "the dependent task's dispatch takes the carried gap" "$DT" 'carried a CONFIRMED-GAP to this task, the dispatch names the gap'
present "the flow graph completes a task whose gap is carried" "$SDD_GRAPH" '"Carry the fix or amendment forward; BLOCKED stops" -> "Append completion to ledger, mark todo complete"'
present "inline mode never fixes a delegated task's gap itself" "$P/skills/executing-plans/SKILL.md" "A delegated task's gap is"
present "inline mode carries a delegated breaker gap forward" "$P/skills/executing-plans/SKILL.md" 'into the next dependent task'"'"'s dispatch (with none, the next task in plan'
present "a gap with no dependent task goes to the next task in plan order" "$DT" 'the next task in plan order; after the last task, to the final review'
present "a gap past the last task goes to the final review" "$DT" '`carried to final review`, where it is a confirmed finding'
present "the final review fixes a carried gap without triage" "$P/reference/final-review.md" 'it goes on the fix list without triage'
# ladder.test.sh holds every implementer to one escalation-table row, so an
# agent known to the escalation table is a real one a human may pin.
present "a pinned escalation-only implementer is not unknown" "$DT" "A name in none of [ladder.md](ladder.md)'s assignment, escalation or reserve tables"
present "the delegated loop keeps the FAILED deferral" "$DT" 'TIMEOUT or FAILED'
present "the delegated loop keeps the no-redispatch rule" "$DT" 'never re-dispatch the Codex seat'
present "the delegated loop refreshes the gate before the review" "$DT" 'Run `scripts/codex-gate --refresh` before `task-step review` when'
present "the delegated loop names a codex-off route" "$DT" 'was routed with `reason=codex-off`: the'
present "the delegated loop records a codex-off seat" "$DT" '` (codex off — <reason>)` when §3'"'"'s `gate:` and `seat:` lines say Codex is off'
present "the reviewer prompt has the second pass" "$TRP" '## Second Pass: The Codex Review'
present "the second pass names the Codex file by path" "$TRP" '[CODEX_REVIEW_FILE]'
present "the second pass comes after the judge's own review" "$TRP" 'Do this only after your Spec Compliance'
present "a Codex finding never raises a score" "$TRP" 'review raises a score, and nothing else you wrote before reading it changes.'

# --- ruling seat prose -----------------------------------------------------------
RULP="$P/skills/subagent-driven-development/references/ruling-prompt.md"
present "SDD routes the ruling seat" "$SDD" '`scripts/review-route PLAN_FILE --ruling <kind> [<task> ...]`'
check "SDD no longer pins the ruling seat to Fable" "$(sdd_text | grep -cF -- '`dforge:judge-fable` (`judge-opus` under the Fable-unavailable rule,')" "0"
present "SDD confirms a header amendment on a second seat" "$SDD_RULING_SEAT" 'a second, independent `dforge:judge-opus` dispatch'
check "SDD no longer keeps the confirmation off Opus" "$(sdd_text | grep -cF -- 'never hand it')" "0"
present "the ruling prompt has the confirmation note" "$RULP" '[CONFIRM_NOTE]'
present "the ruling prompt routes its judge" "$RULP" 'the `primary` that `scripts/review-route PLAN_FILE --ruling <kind>'
present "no route names judge-fable" "$P/agents/judge-fable.md" 'No dforge route names it'
present "an auto run dispatches judge-fable" "$P/agents/judge-fable.md" 'an auto run (reference/auto-run.md) dispatches it for the spec review and the batched rulings'
present "judge-opus grades by consequence" "$P/agents/judge-opus.md" 'not by how small the fix is'
absent "review-route never prints judge-fable" "$ROUTE" 'judge-fable'
present "judge-sonnet-high reviews totals 0 to 3" "$P/agents/judge-sonnet-high.md" 'totals 0 to 3'
present "judge-opus reviews totals 4 to 6" "$P/agents/judge-opus.md" 'totals 4 to 6'

# --- risk3-spread is retired -----------------------------------------------------
for f in "$P/skills/subagent-driven-development/SKILL.md" "$SDD_RULING_SEAT" "$SDD_LEDGER" "$SDD_GRAPH" "$SDD_BATCHING" "$SDD_BUDGET" "$SDD_EXAMPLE" "$SDD_FINISH_RULINGS" "$SDD_RATIONALE" "$SDD_RATIONALIZATIONS" "$SDD_SETUP" \
         "$P/skills/subagent-driven-development/references/ruling-prompt.md" \
         "$P/skills/executing-plans/SKILL.md"; do
  absent "no risk3-spread in ${f#"$P/"}" "$f" 'risk3-spread'
done
present "inline mode reaches the executor empty-diff kind" "$P/skills/executing-plans/SKILL.md" 'executor-empty-diff'

# --- executor-lane and ladder prose ------------------------------------------
EXEC="$P/reference/executor-lane.md"
LAD="$P/reference/ladder.md"
present "the lane reference has the task seats section" "$EXEC" '## Codex task review seats'
absent "the lane reference drops the risk-3 seat section" "$EXEC" '## Risk-3 Codex seat'
present "planning reads the distilled constraints" "$EXEC" 'Read `<docs>/distilled/constraints.md` first'
present "a declared lane is ticked without asking" "$EXEC" 'tick it without asking'
present "an executor task routes to a Claude judge" "$EXEC" 'always routes to a Claude judge'
absent "the final round no longer cites the risk-3 seat" "$EXEC" 'Unlike the risk-3 seat'
present "the ladder names the light tier" "$LAD" '`--tier light` runs the last row directly'
present "planning runs the gate before the roster" "$EXEC" 'Unless it prints `lane=true`, stop here:'
present "dispatch runs the gate before guarding the roster" "$EXEC" '1. **Gate, then guard the roster.**'
present "a failed run refreshes the gate" "$EXEC" 'bash "$(bash "<plugin-root>/scripts/executors" path <id> gate)" --refresh'
present "a refused model hands back at once" "$EXEC" '| Refusal - `refusal=true` in the report'"'"'s `## Codex error` section | `HANDBACK` now'
present "a refusal never takes the successor" "$LAD" 'A refused initial run never reads it'
present "the final Codex round needs the review surface" "$EXEC" 'Unless it prints `review=true`, skip the round'
present "the task seats name the runner's gate" "$EXEC" 'codex is off for this session (<reason>)'

# --- the final whole-branch review ---
shape_plan "$TMP/final-plain.md" '**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1' \
  '**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5'
rule "$TMP/final-plain.md" --final
check "final: a plain plan takes judge-opus" "$out" "review-seat final primary=dforge:judge-opus fallback=- reason=plain"
shape_plan "$TMP/final-risk.md" '**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1' \
  '**Evaluation:** files 0 - spec 0 - coupling 1 - risk 3 = 4'
rule "$TMP/final-risk.md" --final
check "final: risk 3 is intricate" "$out" \
  "review-seat final primary=dforge:judge-opus fallback=- reason=intricate"
shape_plan "$TMP/final-six.md" '**Evaluation:** files 1 - spec 1 - coupling 2 - risk 2 = 6'
rule "$TMP/final-six.md" --final
check "final: total 6 is intricate" "$out" \
  "review-seat final primary=dforge:judge-opus fallback=- reason=intricate"
review_surface false
rule "$TMP/final-plain.md" --final
check "final: the seat does not read the Codex gate" "$out" "review-seat final primary=dforge:judge-opus fallback=- reason=plain"
rule "$TMP/final-plain.md" --final extra
check "final: an extra argument exits 2" "$rc" "2"
rule "$TMP/final-plain.md" --task
check "final: --task with no id still exits 2" "$rc" "2"

# --- the final fix wave's implementer ---
FF="$TMP/ff"
git init -q "$FF"
mkdir -p "$FF/docs" "$FF/.dforge/sdd/plan"
sed 's/^|//' > "$FF/docs/plan.md" <<'EOF'
|# Fix Wave Fixture
|
|**Execution:** inline — `claude --model opus --effort low` — x
|
|### Task 1: below the floor
|
|**Files:**
|- Create: `a.txt`
|- Test: `tests/a.test.sh`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1
|
|### Task 2: line range
|
|**Files:**
|- Modify: `b.txt:10-20`
|
|**Implementer:** dforge:impl-opus-medium
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5
|
|### Task 3: escalated
|
|**Files:**
|- Modify: `c.txt`
|
|**Implementer:** dforge:impl-sonnet-medium
|**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2
|
|### Task 4: reserve
|
|**Files:**
|- Modify: `d.txt`
|
|**Implementer:** dforge:impl-fable-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 3 = 6
|**Override:** owner assigned Fable
|
|### Task 5: inline
|
|**Files:**
|- Modify: `e.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 6: split
|
|#### Part A: small half
|
|**Files:**
|- Modify: `f.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|#### Part B: larger half
|
|**Files:**
|- Modify: `g.txt`
|
|**Implementer:** dforge:impl-opus-low
|**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4
|
|### Task 7: line list
|
|**Files:**
|- Modify: `h.txt:3-4,9`
|- Modify: `dir with spaces/f.txt` (the export)
|- Delete: `old.txt`
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 0 = 3
EOF
sed 's/^|//' > "$FF/.dforge/sdd/plan/progress.md" <<'EOF'
|# SDD ledger — plan: docs/plan.md
|Task 1: implementer impl-sonnet-low (assigned; base aaaaaaa)
|Task 3: implementer dforge:impl-sonnet-medium (assigned; base bbbbbbb)
|Task 3: fix round 4/5 (1 addressed, 1 open — x; commits bbbbbbb..ccccccc; escalated impl-sonnet-medium -> impl-opus-medium)
|Task 5: implementer inline (assigned; base ddddddd)
|Task 5: escalated inline -> subagent — three fix rounds
EOF
fix() { out=$(bash "$ROUTE" "$FF/docs/plan.md" --final-fix "$@" 2>"$TMP/err"); rc=$?; }
FIXSEAT="review-seat final-fix primary=dforge"
fix zzz.txt
check "final-fix: no matched task is the floor" "$out" "$FIXSEAT:impl-sonnet-high fallback=- reason=floor"
fix a.txt
check "final-fix: a low tier is raised to the floor" "$out" "$FIXSEAT:impl-sonnet-high fallback=- reason=tasks:1"
fix tests/a.test.sh
check "final-fix: a Test entry matches" "$out" "$FIXSEAT:impl-sonnet-high fallback=- reason=tasks:1"
fix b.txt
check "final-fix: a :line-range suffix in the plan is ignored" "$out" "$FIXSEAT:impl-opus-medium fallback=- reason=tasks:2"
fix b.txt:12
check "final-fix: a finding's own line suffix is ignored" "$out" "$FIXSEAT:impl-opus-medium fallback=- reason=tasks:2"
fix h.txt
check "final-fix: a :line-list suffix in the plan is ignored" "$out" "$FIXSEAT:impl-sonnet-high fallback=- reason=tasks:7"
fix h.txt:3,9
check "final-fix: a finding's own line list is ignored" "$out" "$FIXSEAT:impl-sonnet-high fallback=- reason=tasks:7"
fix 'dir with spaces/f.txt'
check "final-fix: a path with spaces matches whole" "$out" "$FIXSEAT:impl-sonnet-high fallback=- reason=tasks:7"
fix old.txt
check "final-fix: a Delete entry matches" "$out" "$FIXSEAT:impl-sonnet-high fallback=- reason=tasks:7"
fix a.txt b.txt
check "final-fix: the highest of two matched tasks" "$out" "$FIXSEAT:impl-opus-medium fallback=- reason=tasks:1,2"
fix c.txt
check "final-fix: the ledger's escalated agent counts" "$out" "$FIXSEAT:impl-opus-medium fallback=- reason=tasks:3"
fix d.txt
check "final-fix: a reserve tier is capped at impl-opus-high" "$out" "$FIXSEAT:impl-opus-high fallback=- reason=tasks:4"
fix e.txt
check "final-fix: an inline implementer is the Execution line's rung" "$out" "$FIXSEAT:impl-opus-low fallback=- reason=tasks:5"
fix g.txt
check "final-fix: a split task's parts count as the task" "$out" "$FIXSEAT:impl-opus-low fallback=- reason=tasks:6"
fix zzz.txt c.txt
check "final-fix: an unmatched file beside a matched one" "$out" "$FIXSEAT:impl-opus-medium fallback=- reason=tasks:3"
sed 's/^|//' > "$FF/.dforge/sdd/plan/amendments.md" <<'EOF'
|## A1 — Task 1
|
|### Old
|
|````
|- Create: `a.txt`
|````
|
|### New
|
|````
|- Create: `a2.txt`
|````
EOF
fix a2.txt
check "final-fix: an amended Files block is read" "$out" "$FIXSEAT:impl-sonnet-high fallback=- reason=tasks:1"
fix a.txt
check "final-fix: a file amended away no longer matches" "$out" "$FIXSEAT:impl-sonnet-high fallback=- reason=floor"
rm -f "$FF/.dforge/sdd/plan/amendments.md"
fix
check "final-fix: no file exits 2" "$rc" "2"

# --- a Codex-host plan: the plan-review cap and the final fix wave ---
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
NATIVE="review-seat final-fix primary=native"
native --final-fix zzz.txt
check "native final-fix: no matched task is rank 5" "$out" "$NATIVE:gpt-6.1-sol/high fallback=- reason=floor"
native --final-fix a.txt
check "native final-fix: a low rank is raised to rank 5" "$out" "$NATIVE:gpt-6.1-sol/high fallback=- reason=tasks:1"
native --final-fix b.txt
check "native final-fix: the plan's pair without a ledger line" "$out" "$NATIVE:gpt-6-astra/medium fallback=- reason=tasks:2"
native --final-fix c.txt
check "native final-fix: the escalation counts, the review seat does not" "$out" "$NATIVE:gpt-6-astra/high fallback=- reason=tasks:3"
native --final-fix d.txt
check "native final-fix: a reserve pair is capped at rank 9" "$out" "$NATIVE:gpt-6-astra/xhigh fallback=- reason=tasks:4"
native --final-fix e.txt
check "native final-fix: an inline implementer is the Execution pair" "$out" "$NATIVE:gpt-6.1-sol/xhigh fallback=- reason=tasks:5"
native --final-fix a.txt b.txt c.txt
check "native final-fix: the highest of the matched tasks" "$out" "$NATIVE:gpt-6-astra/high fallback=- reason=tasks:1,2,3"

# --- README, version and program amendment -------------------------------------
RD="$P/README.md"
present "README counts twenty-one agents" "$RD" '**Twenty-one agents in four classes.**'
absent "README drops the three-seat risk-3 mean" "$RD" 'spread above 6 points'
present "README names review-route" "$RD" '`scripts/review-route` prints the review seat'
present "README names the plan-review schema" "$RD" '`codex-plan-review-schema.json`'
# The version is read from the Claude manifest, so a release bump needs no edit here.
version=$(sed -nE 's/^[[:space:]]*"version": "([^"]+)".*/\1/p' "$P/.claude-plugin/plugin.json" | head -n 1)
check "the Claude manifest names a release version" "$([[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo yes || echo no)" "yes"
present "the Codex manifest carries the Claude manifest's version" "$P/.codex-plugin/plugin.json" "\"version\": \"$version\""
present "the program design names sub-project 10" "$P/../../docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md" '**Amendment 2026-09-17 (sub-project 10 spec).**'
present "approach ranking runs on Opus" "$P/skills/selecting-approaches/SKILL.md" 'Dispatch one `dforge:judge-opus` to run the ring'
present "a load-bearing single candidate reaches the advisor" "$P/skills/selecting-approaches/SKILL.md" 'with one plausible approach goes to `advisor`'
present "the budget reference derives the budget" "$P/reference/session-budget.md" 'min(`autoCompactWindow`, model window) × 93% − 140,000'
present "the budget checkpoints finish the task in flight" "$P/reference/session-budget.md" 'finish the task in flight through its'
present "the program design records sub-project 8" "$P/../../docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md" '**Amendment 2026-09-15 (sub-project 8 spec).**'
present "README names the session gate" "$RD" '`scripts/codex-gate` checks the official codex plugin'
present "README records trust per surface" "$RD" 'recorded per surface in `reference/codex-plugin.json`'
present "the program design records the session gate" "$P/../../docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md" 'A session gate (`scripts/codex-gate`) reads'
present "the program design names sub-project 9" "$P/../../docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md" '**Amendment 2026-09-16 (sub-project 9 spec).**'

# --- ruling kinds are executor-neutral --------------------------------------
# --ruling calls plan_shape, which scans every task's score regardless of
# which id was requested (see "an unparseable Evaluation line fails a plan
# round" above), so it needs the fixture without Task 9's broken line, same
# as the plan-round checks.
out=$(bash "$ROUTE" "$TMP/round.md" --ruling executor-empty-diff 1 2>/dev/null); rc=$?
check "the neutral ruling kind is accepted" "$rc" "0"
check "the neutral kind prints itself and goes to Sonnet" \
  "$out" "review-seat ruling=executor-empty-diff tasks=1 primary=dforge:judge-sonnet-high fallback=- reason=simple-kind"

out=$(bash "$ROUTE" "$TMP/round.md" --ruling codex-empty-diff 1 2>/dev/null); rc=$?
check "the legacy ruling kind is still accepted" "$rc" "0"
check "the legacy kind prints its own spelling, not the new one" \
  "$out" "review-seat ruling=codex-empty-diff tasks=1 primary=dforge:judge-sonnet-high fallback=- reason=simple-kind"

out=$(bash "$ROUTE" "$TMP/round.md" --ruling executor-empty-diff 8 2>/dev/null)
check "a risk-3 task still routes the neutral kind to Opus" \
  "$out" "review-seat ruling=executor-empty-diff tasks=8 primary=dforge:judge-opus fallback=- reason=risk"

bash "$ROUTE" "$TMP/round.md" --ruling nonsense-kind 1 >/dev/null 2>&1
check "an unknown ruling kind is still rejected" "$?" "2"

# --- a task on a second executor still gets a Claude review seat ------------
# The spec's §12 asks for this row. Routing decides who *reviews* a task, and
# that has never depended on which executor produced the diff, so a stub
# Executor line must route exactly as the codex line it replaces does.
# Tasks 5 and 6 of the fixture plan both carry `**Executor:** codex gpt-6.1-sol /
# high` (lines 84 and 90), so this rewrites both; only Task 5 is asserted on.
# Swapping the executor and nothing else is the sharpest possible test.
sed 's|\*\*Executor:\*\* codex gpt-6.1-sol / high|**Executor:** stub stub-model / high|' \
  "$TMP/plan.md" > "$TMP/stub-plan.md"
codex_seat=$(bash "$ROUTE" "$TMP/plan.md" --task 5 2>/dev/null)
stub_seat=$(DR_EXECUTORS_DIR="$P/tests/fixtures/executors" \
  bash "$ROUTE" "$TMP/stub-plan.md" --task 5 2>/dev/null)
check "a stub Executor task routes exactly as a codex one does" "$stub_seat" "$codex_seat"
# The seat name is spelled in two pieces on purpose. validate-repository.mjs
# resolves every `dforge:<name>` it finds against skills/ and agents/,
# and this needle is a grep prefix matching three judges, not one agent name.
JUDGEREF='primary=dforge:''judge-'
check "the stub task's seat is a Claude judge" \
  "$(grep -c "$JUDGEREF" <<<"$stub_seat")" "1"

# --- the executor lane reference -------------------------------------------
LANE="$P/reference/executor-lane.md"
check "the neutral reference exists" "$([ -f "$LANE" ] && echo yes || echo no)" "yes"
# The old path is spelled in two pieces on purpose. The rename that produced
# executor-lane.md rewrote every literal spelling of the OLD path in this
# repository with sed; written whole, this assertion would have been rewritten
# to test the new file, which exists, and would then fail. The two pieces
# concatenate at runtime and match no sed pattern. Never join them.
OLDREF="external-""executor.md"
check "the Codex-only reference is gone" \
  "$([ -f "$P/reference/$OLDREF" ] && echo present || echo gone)" "gone"
present "the reference resolves the gate through the registry" "$LANE" 'executors path <id> gate'
present "the reference names the blocks through the registry" "$LANE" 'executors get <id> blocks.assignment'
present "the reference resolves the wrapper through the registry" "$LANE" 'executors path <id> wrapper'
present "the reference keeps a per-executor section" "$LANE" '## Per-executor: codex'
present "the reference names the neutral ruling kind" "$LANE" 'executor-empty-diff'
present "the reference keeps the background-call rule" "$LANE" 'background Bash call'
present "the reference keeps the two-failure budget" "$LANE" 'At most two executor runs may *fail* per task before Claude takes over'
present "the reference documents the wedged-client case" "$LANE" "Read the durable task record's \`phase\` and \`reaped\` as **evidence, not proof**"
present "the reference resumes an executor task, not a Codex one" "$LANE" '## Resuming an executor task'
absent "the reference no longer claims a wrapper poll loop" "$LANE" "wrapper's own poll loop"
absent "the reference no longer names the unreachable survivor note" "$LANE" 'codex-may-still-be-running'

RP="$P/skills/subagent-driven-development/references/ruling-prompt.md"
ESC="$P/skills/subagent-driven-development/references/escalation.md"
LOOP="$P/reference/delegated-task.md"
present "the ruling prompt explains the neutral kind" "$RP" 'executor-empty-diff'
absent "the ruling prompt no longer names the Codex-only kind" "$RP" 'codex-empty-diff'
present "the ledger grammar is executor-neutral" "$SDD_LEDGER" 'executor <id> <model>/<effort>, thread'
present "escalation resumes the executor's own session" "$ESC" "Its fix rounds resume that executor's own session"
absent "escalation no longer names a Codex session" "$ESC" 'rounds resume the same Codex session'
present "the loop resumes the executor's own session" "$LOOP" "A task on an external executor resumes that executor's own session instead"
absent "the loop no longer names a Codex session" "$LOOP" 'resumes its Codex'

# --- the shared Evaluation reader ---
# Two shipped defects: a fenced example line escalated the seat to the risk-3
# rung, and a stale line above `#### Part A` routed a split task on the score
# that forced the split.
# The suite leaves the review surface closed, and a closed surface routes every
# seat to Claude with reason=codex-off, which is not what these cases are about.
review_surface true

seat() { # seat <file> <id>; sets out and rc
  out=$(bash "$ROUTE" "$1" --task "$2" 2>"$TMP/err"); rc=$?
}
LIGHT="primary=codex:light fallback=dforge:judge-sonnet-high review=group reason=band"

printf '# P\n\n### Task 1: Fenced\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 3 = 6\n```\n' > "$TMP/ev-fenced.md"
seat "$TMP/ev-fenced.md" 1
check "a fenced example does not escalate the seat" "$out" "review-seat task=1 $LIGHT"
check "a fenced example exits 0" "$rc" "0"

printf '# P\n\n### Task 1: Split\n\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 1 = 6\n\n#### Part A: a\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n#### Part B: b\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n' > "$TMP/ev-split.md"
seat "$TMP/ev-split.md" 1
check "a whole-task id routes on its parts" "$out" "review-seat task=1 $LIGHT"
seat "$TMP/ev-split.md" 1A
check "a part id is unchanged" "$out" "review-seat task=1A $LIGHT"

# A part filter that does not skip fences reads an example inside the part.
printf '# P\n\n### Task 1: Split with an example\n\n#### Part A: a\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 3 = 6\n```\n\n#### Part B: b\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n' > "$TMP/ev-partfence.md"
seat "$TMP/ev-partfence.md" 1A
check "a fenced example inside a part does not escalate it" "$out" "review-seat task=1A $LIGHT"
seat "$TMP/ev-partfence.md" 1
check "a fenced example inside a part does not escalate the whole task" "$out" "review-seat task=1 $LIGHT"

printf '# P\n\n### Task 1: Fenced executor\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n**Executor:** codex gpt-6.1-sol / medium\n```\n' > "$TMP/ev-fexec.md"
seat "$TMP/ev-fexec.md" 1
check "a fenced Executor line does not claim the task is offloaded" "$out" "review-seat task=1 $LIGHT"

printf '# P\n\n### Task 1: Real executor\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n**Executor:** codex gpt-6.1-sol / medium\n' > "$TMP/ev-rexec.md"
seat "$TMP/ev-rexec.md" 1
check "a real Executor line still routes to a Claude judge" "$out" \
  "review-seat task=1 primary=dforge:judge-sonnet-high fallback=- review=group reason=executor"

out=$(bash "$ROUTE" "$TMP/round.md" --ruling acceptance-ambiguous 2>&1); status=$?
check "acceptance-ambiguous: exit 0" "$status" "0"
check "acceptance-ambiguous goes to the ruling seat" "$out" \
  "review-seat ruling=acceptance-ambiguous tasks=plan primary=dforge:judge-opus fallback=- reason=routine"
present "ruling prompt: the REWORD verdict" "$P/skills/subagent-driven-development/references/ruling-prompt.md" \
  'REWORD: the spec statement is what is wrong'
present "ruling prompt: the kind" "$P/skills/subagent-driven-development/references/ruling-prompt.md" \
  '- acceptance-ambiguous: the final review'"'"'s QA seat could not test a spec'

# --- the review tier ---
# A task is reviewed alone (review=task) at risk 2 or more or a total of 5 or
# more, and grouped (review=group) otherwise. A batch carries no tier, and a
# task with no Evaluation line is reviewed alone instead of failing the route.
review_surface true
tier_of() { sed -n 's/.* review=\([^ ]*\) reason=.*/\1/p' <<<"$out"; }
route --task 3
check "tier: total 4 at risk 1 is grouped" "$(tier_of)" "group"
route --task 4
check "tier: risk 2 at total 4 is reviewed alone" "$(tier_of)" "task"
route --task 10
check "tier: total 5 at risk 0 is reviewed alone" "$(tier_of)" "task"
route --task 7A
check "tier: a light part is grouped" "$(tier_of)" "group"
route --task 7
check "tier: a whole split task takes its heaviest part's tier" "$(tier_of)" "task"
route --task 1 3
check "tier: a batch carries no review field" "$(grep -c ' review=' <<<"$out")" "0"
review_surface false
route --task 2
check "tier: codex off keeps the tier" "$(tier_of)" "group"
review_surface true

printf '# P\n\n### Task 1: Unscored\n\n**Implementer:** dforge:impl-sonnet-low\n\nBody.\n\n### Task 2: Scored\n\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\n### Task 3: Split\n\n#### Part A: a\n\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\n#### Part B: b\n\nNo score.\n' > "$TMP/unscored.md"
seat "$TMP/unscored.md" 1
check "unscored: exits 0" "$rc" "0"
check "unscored: reviewed alone by Opus" "$out" "review-seat task=1 primary=dforge:judge-opus fallback=- review=task reason=unscored"
check "unscored: nothing on stderr" "$(cat "$TMP/err")" ""
seat "$TMP/unscored.md" 3B
check "unscored: a part with no Evaluation line is unscored too" "$out" "review-seat task=3B primary=dforge:judge-opus fallback=- review=task reason=unscored"
review_surface false
seat "$TMP/unscored.md" 1
check "unscored: codex off names the same seat" "$out" "review-seat task=1 primary=dforge:judge-opus fallback=- review=task reason=unscored"
review_surface true
out=$(bash "$ROUTE" "$TMP/unscored.md" --task 1 2 2>/dev/null); rc=$?
check "unscored: a batch holding an unscored task still exits 2" "$rc" "2"
seat "$TMP/unscored.md" 2
check "unscored: its scored neighbour routes as before" "$out" "review-seat task=2 primary=codex:light fallback=dforge:judge-sonnet-high review=group reason=band"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
