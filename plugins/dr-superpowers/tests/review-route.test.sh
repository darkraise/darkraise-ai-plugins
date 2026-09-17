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
|**Implementer:** dr-superpowers:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 2: light mid
|
|**Implementer:** dr-superpowers:impl-sonnet-high
|**Evaluation:** files 1 — spec 0 — coupling 1 — risk 1 = 3
|
|### Task 3: heavy
|
|**Implementer:** dr-superpowers:impl-opus-low
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4
|
|### Task 4: risky
|
|**Implementer:** dr-superpowers:impl-opus-low
|**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4
|
|### Task 5: executor
|
|**Implementer:** dr-superpowers:impl-sonnet-high
|**Executor:** codex gpt-5.5 / high
|**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3
|
|### Task 6: executor risky
|
|**Implementer:** dr-superpowers:impl-sonnet-high
|**Executor:** codex gpt-5.5 / high
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 2 = 3
|
|### Task 7: split
|
|#### Part A: small half
|
|**Implementer:** dr-superpowers:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|#### Part B: risky half
|
|**Implementer:** dr-superpowers:impl-opus-medium
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5
|
|### Task 8: risk three
|
|**Implementer:** dr-superpowers:impl-opus-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 3 = 6
|
|### Task 9: broken
|
|**Implementer:** dr-superpowers:impl-sonnet-low
|**Evaluation:** one plus one
|
|### Task 10: band five
|
|**Implementer:** dr-superpowers:impl-opus-medium
|**Evaluation:** files 2 - spec 2 - coupling 1 - risk 0 = 5
|
|### Task 11: executor risk three
|
|**Implementer:** dr-superpowers:impl-opus-low
|**Executor:** codex gpt-5.5 / high
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 3 = 4
EOF

route() { # route <args...>; sets out and rc
  out=$(bash "$ROUTE" "$TMP/plan.md" "$@" 2>"$TMP/err"); rc=$?
}

check "script exists" "$([ -f "$ROUTE" ] && echo yes || echo no)" "yes"

route --task 1
check "total 1: light Codex, Sonnet fallback" "$out" "review-seat task=1 primary=codex:light fallback=dr-superpowers:judge-sonnet-high reason=band"
check "a routed task exits 0" "$rc" "0"
route --task 2
check "total 3 with em dashes: light Codex, Sonnet fallback" "$out" "review-seat task=2 primary=codex:light fallback=dr-superpowers:judge-sonnet-high reason=band"
route --task 3
check "total 4 at risk 1: heavy Codex, Opus fallback" "$out" "review-seat task=3 primary=codex:heavy fallback=dr-superpowers:judge-opus reason=band"
route --task 4
check "risk 2 takes its band: heavy Codex, Opus fallback" "$out" "review-seat task=4 primary=codex:heavy fallback=dr-superpowers:judge-opus reason=band"
route --task 5
check "an Executor task is reviewed by its band judge, never Codex" "$out" "review-seat task=5 primary=dr-superpowers:judge-sonnet-high fallback=- reason=executor"
route --task 6
check "an Executor task at risk 2 takes its band" "$out" "review-seat task=6 primary=dr-superpowers:judge-sonnet-high fallback=- reason=executor"
route --task 11
check "an Executor task at risk 3 goes to Fable alone" "$out" "review-seat task=11 primary=dr-superpowers:judge-fable fallback=- reason=executor"
route --task 7A
check "a part routes on its own Evaluation" "$out" "review-seat task=7A primary=codex:light fallback=dr-superpowers:judge-sonnet-high reason=band"
route --task 7B
check "the risk-2 part takes heavy Codex" "$out" "review-seat task=7B primary=codex:heavy fallback=dr-superpowers:judge-opus reason=band"
route --task 7
check "a split task without a part routes on its heaviest part" "$out" "review-seat task=7 primary=codex:heavy fallback=dr-superpowers:judge-opus reason=band"
route --task 8
check "risk 3 goes to Astra then Fable" "$out" "review-seat task=8 primary=codex:heavy+judge-fable fallback=dr-superpowers:judge-fable reason=risk"
route --task 10
check "total 5 at risk 0: heavy Codex, Opus fallback" "$out" "review-seat task=10 primary=codex:heavy fallback=dr-superpowers:judge-opus reason=band"

route --task 1 2
check "a batch takes its highest total" "$out" "review-seat task=1,2 primary=codex:light fallback=dr-superpowers:judge-sonnet-high reason=band"
route --task 1 3
check "a batch crossing into the heavy band" "$out" "review-seat task=1,3 primary=codex:heavy fallback=dr-superpowers:judge-opus reason=band"
route --task 1 5
check "one Executor task makes the whole batch Claude-reviewed" "$out" "review-seat task=1,5 primary=dr-superpowers:judge-sonnet-high fallback=- reason=executor"

route --plan-round 1
check "plan round 1 is Codex with a Fable fallback" "$out" "review-seat plan-round=1 primary=codex:plan fallback=dr-superpowers:judge-fable reason=round"
route --plan-round 2
check "plan round 2 is Opus" "$out" "review-seat plan-round=2 primary=dr-superpowers:judge-opus fallback=- reason=round"
route --plan-round 3
check "plan round 3 is Opus" "$out" "review-seat plan-round=3 primary=dr-superpowers:judge-opus fallback=- reason=round"

# --- the review surface off ------------------------------------------------------
# While the session's gate has not opened the review surface, no route names a
# Codex seat, and the Claude seat it names has nothing to fall back to.
review_surface false
route --task 1
check "codex off: total 1 goes to Sonnet alone" "$out" "review-seat task=1 primary=dr-superpowers:judge-sonnet-high fallback=- reason=codex-off"
check "codex off: a routed task still exits 0" "$rc" "0"
route --task 2
check "codex off: total 3 goes to Sonnet alone" "$out" "review-seat task=2 primary=dr-superpowers:judge-sonnet-high fallback=- reason=codex-off"
route --task 3
check "codex off: total 4 goes to Opus alone" "$out" "review-seat task=3 primary=dr-superpowers:judge-opus fallback=- reason=codex-off"
route --task 10
check "codex off: total 5 goes to Opus alone" "$out" "review-seat task=10 primary=dr-superpowers:judge-opus fallback=- reason=codex-off"
route --task 4
check "codex off: risk 2 at total 4 takes its band" "$out" "review-seat task=4 primary=dr-superpowers:judge-opus fallback=- reason=codex-off"
route --task 8
check "codex off: risk 3 goes to Fable alone" "$out" "review-seat task=8 primary=dr-superpowers:judge-fable fallback=- reason=codex-off"
route --task 7
check "codex off: a split task routes on its heaviest part" "$out" "review-seat task=7 primary=dr-superpowers:judge-opus fallback=- reason=codex-off"
route --task 1 2
check "codex off: a batch takes its highest total" "$out" "review-seat task=1,2 primary=dr-superpowers:judge-sonnet-high fallback=- reason=codex-off"
route --task 5
check "codex off: an Executor task is unchanged" "$out" "review-seat task=5 primary=dr-superpowers:judge-sonnet-high fallback=- reason=executor"
route --task 6
check "codex off: an Executor task at risk 2 is unchanged" "$out" "review-seat task=6 primary=dr-superpowers:judge-sonnet-high fallback=- reason=executor"
route --plan-round 1
check "codex off: plan round 1 goes to Fable alone" "$out" "review-seat plan-round=1 primary=dr-superpowers:judge-fable fallback=- reason=codex-off"
route --plan-round 2
check "codex off: plan round 2 is unchanged" "$out" "review-seat plan-round=2 primary=dr-superpowers:judge-opus fallback=- reason=round"
review_surface absent
route --task 3
check "no session file is off" "$out" "review-seat task=3 primary=dr-superpowers:judge-opus fallback=- reason=codex-off"
route --plan-round 1
check "no session file keeps plan round 1 off Codex" "$out" "review-seat plan-round=1 primary=dr-superpowers:judge-fable fallback=- reason=codex-off"
review_surface true
printf 'not json' > "$DR_CODEX_SESSION_DIR/review-route-test.json"
route --task 1
check "a torn session file is off" "$out" "review-seat task=1 primary=dr-superpowers:judge-sonnet-high fallback=- reason=codex-off"
review_surface true
CLAUDE_CODE_SESSION_ID="" route --task 1
check "no session id is off, whatever is on disk" "$out" "review-seat task=1 primary=dr-superpowers:judge-sonnet-high fallback=- reason=codex-off"
route --task 1
check "an open review surface routes to Codex again" "$out" "review-seat task=1 primary=codex:light fallback=dr-superpowers:judge-sonnet-high reason=band"

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
check "a CRLF plan routes" "$out" "review-seat task=4 primary=codex:heavy fallback=dr-superpowers:judge-opus reason=band"

# --- plan review prose ---------------------------------------------------------
WP="$P/skills/writing-plans/SKILL.md"
PRP="$P/skills/writing-plans/references/plan-reviewer-prompt.md"
present "writing-plans routes each round" "$WP" 'scripts/review-route PLAN_FILE --plan-round <r>'
present "writing-plans snapshots the plan before each round" "$WP" '<workspace>/plan-round-<r>.md'
present "writing-plans runs the Codex plan kind" "$WP" '--kind plan'
present "writing-plans writes the delta" "$WP" '<workspace>/plan-delta-<r>.diff'
present "writing-plans keeps the round cap" "$WP" 'replaces a fresh full review; rounds are not cut.'
absent "writing-plans no longer dispatches a fresh full review each round" "$WP" 'dispatch a fresh full review'
present "the prompt file has a Codex round-1 section" "$PRP" '## Round 1 on Codex'
present "the Codex round-1 prompt names its schema" "$PRP" 'codex-plan-review-schema.json'
present "the prompt file has a delta template" "$PRP" '## Rounds 2 and 3'
present "the delta template takes the delta file" "$PRP" '[DELTA_FILE]'
present "the delta template verdicts prior findings" "$PRP" '[ADDRESSED|NOT ADDRESSED]'
present "the delta template may read beyond the delta" "$PRP" 'The delta is where to look first, not the limit of'

# --- the session gate in writing-plans -------------------------------------------
present "writing-plans runs the gate before each round" "$WP" 'run `scripts/codex-gate` (say its line aloud when it ends `source=probe`),'
present "writing-plans sends a codex-off round 1 to Fable" "$WP" '**`primary=dr-superpowers:judge-fable` with `reason=codex-off`**'
present "writing-plans offers the lane only on lane=true" "$WP" 'offers Codex only when'

# --- task review prose -----------------------------------------------------------
SDD="$P/skills/subagent-driven-development/SKILL.md"
TRP="$P/skills/subagent-driven-development/references/task-reviewer-prompt.md"
present "the Seats table routes the task reviewer" "$SDD" '| Task reviewer | The seat `scripts/review-route PLAN_FILE --task <N>` prints'
present "SDD runs the light tier for codex:light" "$SDD" '`codex:light` is `--tier light`'
present "SDD has the risk 2 section" "$SDD" '**Risk 2 and above.**'
absent "SDD no longer averages three seats" "$SDD" 'average each criterion'
absent "SDD no longer writes K=3" "$SDD" 'K=3'
present "SDD writes the seat clause" "$SDD" ', seat <seat>'
present "SDD keeps the runner name" "$SDD" 'run-codex-review.sh'
present "SDD keeps the FAILED deferral" "$SDD" 'TIMEOUT or FAILED'
present "SDD keeps the no-redispatch rule" "$SDD" 'never re-dispatch the Codex seat'
present "SDD runs the gate before routing" "$SDD" '- **The seat:** run `scripts/codex-gate` (say its line aloud when it ends'
present "SDD names a codex-off route" "$SDD" 'On `reason=codex-off` the review surface is off for'
present "SDD records a codex-off seat" "$SDD" '` (codex off — <reason>)` when `review-route` printed `reason=codex-off`'
present "the reviewer prompt has the second pass" "$TRP" '## Second Pass: The Codex Review'
present "the second pass names the Codex file by path" "$TRP" '[CODEX_REVIEW_FILE]'
present "the second pass comes after Fable's own review" "$TRP" 'Do this only after your Spec Compliance'
present "a Codex finding never raises a score" "$TRP" 'review raises a score, and nothing else you wrote before reading it changes.'

# --- risk3-spread is retired -----------------------------------------------------
for f in "$P/skills/subagent-driven-development/SKILL.md" \
         "$P/skills/subagent-driven-development/references/ruling-prompt.md" \
         "$P/skills/executing-plans/SKILL.md"; do
  absent "no risk3-spread in ${f#"$P/"}" "$f" 'risk3-spread'
done
present "inline mode lists four kinds it does not run" "$P/skills/executing-plans/SKILL.md" 'The other four kinds belong to seats this mode does not run'

# --- external-executor and ladder prose ------------------------------------------
EXEC="$P/reference/external-executor.md"
LAD="$P/reference/ladder.md"
present "the lane reference has the task seats section" "$EXEC" '## Codex task review seats'
absent "the lane reference drops the risk-3 seat section" "$EXEC" '## Risk-3 Codex seat'
present "planning reads the distilled constraints" "$EXEC" 'Read `docs/superpowers/distilled/constraints.md` first'
present "a declared lane is ticked without asking" "$EXEC" 'tick it without asking'
present "an executor task routes to a Claude judge" "$EXEC" 'always routes to a Claude judge'
absent "the final round no longer cites the risk-3 seat" "$EXEC" 'Unlike the risk-3 seat'
present "the ladder names the light tier" "$LAD" '`--tier light` runs the last row directly'
present "planning runs the gate before the roster" "$EXEC" 'Unless it prints `lane=true`, stop here:'
present "dispatch runs the gate before guarding the roster" "$EXEC" '1. **Gate, then guard the roster.**'
present "a failed run refreshes the gate" "$EXEC" 'bash "<plugin-root>/scripts/codex-gate" --refresh'
present "the final Codex round needs the review surface" "$EXEC" 'Unless it prints `review=true`, skip the round'
present "the task seats name the runner's gate" "$EXEC" 'codex is off for this session (<reason>)'

# --- README, version and program amendment -------------------------------------
RD="$P/README.md"
present "README counts twenty agents" "$RD" '**Twenty agents in three classes.**'
absent "README drops the three-seat risk-3 mean" "$RD" 'spread above 6 points'
present "README names review-route" "$RD" '`scripts/review-route` prints the review seat'
present "README names the plan-review schema" "$RD" '`codex-plan-review-schema.json`'
present "the Claude manifest is 1.10.0" "$P/.claude-plugin/plugin.json" '"version": "1.10.0"'
present "the Codex manifest is 1.10.0" "$P/.codex-plugin/plugin.json" '"version": "1.10.0"'
present "the program design records sub-project 8" "$P/../../docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md" '**Amendment 2026-09-15 (sub-project 8 spec).**'
present "README names the session gate" "$RD" '`scripts/codex-gate` checks the official codex plugin'
present "README records trust per surface" "$RD" 'recorded per surface in `reference/codex-plugin.json`'
present "the program design records the session gate" "$P/../../docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md" 'A session gate (`scripts/codex-gate`) reads'
present "the program design names sub-project 9" "$P/../../docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md" '**Amendment 2026-09-16 (sub-project 9 spec).**'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
