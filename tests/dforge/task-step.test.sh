#!/usr/bin/env bash
# task-step runs one phase of the delegated task loop in a single call. Each
# case runs against a throwaway repository and plan; no case starts Codex.
set -uo pipefail
# Usage:
#   bash task-step.test.sh            run every part
#   bash task-step.test.sh verdict    run the named parts only
ALL="start rereview verdict"
sel=""
for n in "$@"; do
  n=$(tr 'A-Z' 'a-z' <<<"$n")
  case " $ALL " in
    *" $n "*) sel="$sel $n" ;;
    *) printf 'task-step.test.sh: unknown part %s (parts: %s)\n' "$n" "$ALL" >&2; exit 2 ;;
  esac
done
[ $# -gt 0 ] || sel=$ALL
want() { case " $sel " in *" $1 "*) return 0 ;; esac; return 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/../../plugins/dforge"
STEP="$P/scripts/task-step"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP=$(mktemp -d)
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
# sdd-workspace and task-step print the form git gives, which native jq.exe can
# open.
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.claude"
export MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1
unset DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR

# review-route reads this session's gate file; the gate itself is a stub, so no
# case can reach a real Codex.
export DR_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=task-step-test
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-gate usable=true reason=ok review=true resets_at=- source=cache"' > "$TMP/gate-stub"
printf '%s\n' '#!/usr/bin/env bash' 'echo "agy-gate usable=false reason=setting review=false resets_at=- claude=on claude_resets_at=- source=setting"' > "$TMP/agy-gate-stub"
export TASK_STEP_CODEX_GATE="$TMP/gate-stub" TASK_STEP_AGY_GATE="$TMP/agy-gate-stub"
review_surface() { # review_surface <true|false|absent>
  rm -rf "$DR_CODEX_SESSION_DIR"
  [ "$1" != absent ] || return 0
  mkdir -p "$DR_CODEX_SESSION_DIR"
  printf '{"session_id":"task-step-test","usable":true,"review":%s,"lane":false}\n' "$1" > "$DR_CODEX_SESSION_DIR/task-step-test.json"
}

REPO="$TMP/repo"
git init -q "$REPO"
cd "$REPO" || exit 1
git config user.name Darkraise
git config user.email dark@example.invalid
mkdir docs

# Fixture lines carry a leading | so a plan that quotes this suite still lints.
sed 's/^|//' > docs/plan.md <<'PLAN'
|# Step Fixture Plan
|
|**Goal:** Fixture.
|
|**Execution:** inline — `claude --model sonnet --effort high` — fixture
|
|## Global Constraints
|
|- Fixture constraint.
|
|## Contracts
|
|- Fixture contract.
|
|## Task index
|
|1. plain
|2. second
|3. executor
|4. unscored
|5. batch low
|6. batch high
|7. risky
|8. unparseable
|9. bad lens
|
|### Task 1: plain
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|**Lenses:** lang-bash
|
|Body one.
|
|### Task 2: second
|
|**Implementer:** `dforge:impl-sonnet-high`
|**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3
|
|### Task 3: executor
|
|**Implementer:** dforge:impl-sonnet-high
|**Executor:** codex gpt-6.1-sol / high
|**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3
|
|### Task 4: unscored
|
|**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3
|
|### Task 5: batch low
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|
|### Task 6: batch high
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|
|### Task 7: risky
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 3 = 6
|
|### Task 8: unparseable
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** one plus one
|
|### Task 9: bad lens
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|**Lenses:** no-such-lens
PLAN
sed 's/^|//' > docs/codex-plan.md <<'PLAN'
|# Codex Fixture
|
|**Host:** codex
|
|### Task 1: only
|
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
PLAN
git add -A && git commit -qm "docs: add fixture plans"
BASE=$(git rev-parse HEAD)

WS=$(bash "$P/scripts/sdd-workspace" docs/plan.md)
LEDGER="$WS/progress.md"
rm -f "$WS"/*
step() { out=$(bash "$STEP" "$@" 2>"$TMP/err"); rc=$?; }
count_lines() { printf '%s\n' "$1" | grep -c .; }

PR=$(cd "$P" && pwd)
TOP=$(git rev-parse --show-toplevel)
short() { git rev-parse --short "$1"; }
placeholders() { grep -cE '\[[A-Z][A-Z_]*\]' "$1"; }
ws_count() { ls -A "$WS" | wc -l | tr -d ' '; }
state_of() { jq -r "$2" "$WS/task-$1-step.json" | tr -d '\r'; }
open_task() { bash "$P/scripts/task-brief" --open docs/plan.md "$1" >/dev/null; }
base_at() { # base_at <task> <sha> — the review range starts at SHA
  jq --arg b "$2" '.base = $b' "$WS/task-$1-step.json" > "$TMP/s.json" && mv "$TMP/s.json" "$WS/task-$1-step.json"
}
RR_S="$HERE/../../plugins/dforge/scripts"

if want start; then
for t in 1 2 3 4 7 8 9; do open_task "$t"; done

# Negative: usage, a missing task, a Codex host, an amendment that does not apply.
step start docs/plan.md 1
check "start is no subcommand" "$rc" "2"
step review docs/plan.md 99
check "review: no such task exits 3" "$rc" "3"
step review docs/plan.md
check "review: no task number exits 2" "$rc" "2"
step review docs/plan.md x
check "review: a non-numeric task exits 2" "$rc" "2"
step review docs/plan.md 1 --nope
check "review: an unknown flag exits 2" "$rc" "2"
step review docs/plan.md 5 6
check "review: a second task exits 2" "$rc" "2"
check "review: a second task writes no state" "$([ -f "$WS/task-5-step.json" ] && echo yes || echo no)" "no"
step bogus docs/plan.md 1
check "an unknown subcommand exits 2" "$rc" "2"
step review docs/missing.md 1
check "review: a missing plan exits 2" "$rc" "2"
CWS=$(winpath "$(bash "$P/scripts/sdd-workspace" docs/codex-plan.md)")
rm -rf "$CWS"
mkdir -p "$WS"
sed 's/^|//' > "$WS/amendments.md" <<'AMEND'
|## A1 — Task 1
|
|### Old
|````
|a line the task does not hold
|````
|
|### New
|````
|replacement
|````
AMEND
step review docs/plan.md 1
check "review: an amendment that does not apply exits 4" "$rc" "4"
rm -f "$WS/amendments.md"

# review: the preconditions.
before=$(ws_count)
step review docs/plan.md 6
check "review: a task never opened exits 6" "$rc" "6"
check "review: a task never opened writes nothing" "$(ws_count)" "$before"
step review docs/codex-plan.md 1
check "review: a Host: codex plan exits 2" "$rc" "2"
check "review: a Host: codex plan writes nothing" "$([ -e "$CWS" ] && echo yes || echo no)" "no"
step review docs/plan.md 99
check "review: no such task exits 3" "$rc" "3"
for flag in --base --head --cwd --reset; do
  step review docs/plan.md 1 "$flag" x
  check "review: $flag is no flag" "$rc" "2"
done
BASE1=$(git rev-parse HEAD)

# review: a task below risk 3 gets no per-task route; the judge prompt is
# still written for judge-opus.
echo a > a.txt && git add a.txt && git commit -qm "feat: add a"
C1=$(git rev-parse HEAD)
review_surface absent
step review docs/plan.md 1
JP="$WS/task-1-review-prompt.md"
check "review: exit 0" "$rc" "0"
check "review: the digest is at most 15 lines" "$([ "$(count_lines "$out")" -le 15 ] && echo yes || echo no)" "yes"
check "review: below risk 3 the seat is judge-opus, saying why" "$(grep '^seat:' <<<"$out")" \
  "seat: dforge:judge-opus prompt: $JP (review-route exited 2: review-route: Task 1 is risk 0: only a risk-3 task gets a per-task review)"
check "review: no runner lines for a judge seat" "$(grep -cE '^(panel|codex|timeout):' <<<"$out")" "0"
check "review: no panel prompt for a judge seat" "$([ -e "$WS/task-1-review-panel-prompt.md" ] && echo yes || echo no)" "no"
check "review: the judge prompt has no unexpanded placeholder" "$(placeholders "$JP")" "0"
check "review: base, head and diff file" "$(grep -E '^\*\*(Base|Head|Diff file):\*\*' "$JP" | tr '\n' ' ' | sed 's/ $//')" \
  "**Base:** $BASE1 **Head:** $C1 **Diff file:** $WS/review-$(short "$BASE1")..$(short "$C1").diff"
check "review: the diff file exists" "$([ -f "$WS/review-$(short "$BASE1")..$(short "$C1").diff" ] && echo yes || echo no)" "yes"
# A bracketed capital token in a filled value, here the checkout's path, is
# not a placeholder the template left unexpanded.
cp -a "$REPO" "$TMP/fix-[WIP]"
wip_rc=$(cd "$TMP/fix-[WIP]" && bash "$STEP" review docs/plan.md 1 >/dev/null 2>&1; echo $?)
check "review: a checkout path holding [WIP] is no unexpanded placeholder" "$wip_rc" "0"
rm -rf "$TMP/fix-[WIP]"
check "review: brief and report paths" "$(grep -cE "^(Read the task brief: $WS/task-1-brief.md|Read the implementer's report: $WS/task-1-report.md)\$" "$JP")" "2"
check "review: the criteria path is expanded" "$(grep -c "Read the criteria file at $PR/criteria/task-review.md and score" "$JP")" "1"
check "review: the lens path is named" "$(grep -c "^Read each lens file in $PR/criteria/lenses/lang-bash.md\. Lens criteria" "$JP")" "1"
check "review: no Second Pass section below risk 3" "$(grep -c 'Second Pass' "$JP")" "0"
check "review: identity check" "$(grep '^check identity' <<<"$out")" "check identity: clean"
check "review: attribution check" "$(grep '^check attribution' <<<"$out")" "check attribution: clean"
check "review: the state records the review head" "$(state_of 1 .reviewHead)" "$C1"
check "review: the state records t0" "$(state_of 1 '.t0 | type')" "number"
check "review: the state keeps the round" "$(state_of 1 .round)" "0"
check "review: the state line precedes the budget line" "$(tail -n 2 <<<"$out" | head -n 1)" \
  "state: base $(short "$BASE1") review-head $(short "$C1") round 0 t0 $(state_of 1 .t0)"
check "review: the last line is the budget line" "$(tail -n 1 <<<"$out" | cut -c1-6)" "budget"

step review docs/plan.md 2
check "review: a task with no lens drops the section" "$(grep -c 'Lens Criteria' "$WS/task-2-review-prompt.md")" "0"
check "review: and leaves no placeholder" "$(placeholders "$WS/task-2-review-prompt.md")" "0"

# review: a heavy panel seat on risk 3, then the judge with the Second Pass section.
echo b > b.txt && git add b.txt && git commit -qm "feat: add b"
C2=$(git rev-parse HEAD)
review_surface true
step review docs/plan.md 7
JP7="$WS/task-7-review-prompt.md"
check "a heavy review prints the heavy panel seat" "$(grep -c '^seat: panel:heavy+judge-opus prompt: .* then: dforge:judge-opus' <<<"$out")" "1"
check "a heavy panel's timeout" "$(grep '^timeout:' <<<"$out")" "timeout: 5590000"
check "the Second Pass names each reviewer's file" "$(grep -c -e 'task-7-review-panel/codex.json' -e 'task-7-review-panel/agy.json' "$WS/task-7-review-prompt.md")" "2"
check "review: the heavy command names the tier" "$(grep -c -- '--kind task --tier heavy --cwd' <<<"$out")" "1"
check "review: the panel prompt leaves the Second Pass out" "$(grep -c 'Second Pass' "$WS/task-7-review-panel-prompt.md")" "0"
check "review: the risk-3 judge prompt has no placeholder" "$(placeholders "$JP7")" "0"
PP="$WS/task-7-review-panel-prompt.md"
check "review: the judge prompt keeps no template instruction text" "$(grep -cE '^\[Include |otherwise\.\]$' "$JP7")" "0"
check "review: the panel command in full" "$(grep '^panel:' <<<"$out")" \
  "panel: bash $(printf %q "$PR/scripts/run-review-panel") --kind task --tier heavy --cwd $(printf %q "$TOP") --out-dir $(printf %q "$WS/task-7-review-panel") --prompt $(printf %q "$PP")"
check "review: no gate line while a surface is open" "$(grep -c '^gate:' <<<"$out")" "0"
check "review: the panel prompt has no unexpanded placeholder" "$(placeholders "$PP")" "0"
check "review: the panel prompt asks for one JSON object" "$(grep -c 'one JSON object' "$PP")" "1"
check "review: the panel prompt carries the criteria" "$(grep -c '^#### Spec Compliance {#spec}$' "$PP")" "1"
check "review: the panel prompt drops the markdown report" "$(grep -cE 'Verification Scores|Output Format|Lens Criteria|Second Pass' "$PP")" "0"
check "review: the panel prompt names the diff file" "$(grep -c "^\*\*Diff file:\*\* $WS/review-" "$PP")" "1"
check "review: no Codex prompt is written" "$([ -e "$WS/task-7-review-codex-prompt.md" ] && echo yes || echo no)" "no"
# The printed panel line is run by the session: a checkout path is text there.
SUB_REPO="$TMP/fix-\$(touch pwned)"
cp -a "$REPO" "$SUB_REPO"
sub_line=$(cd "$SUB_REPO" && bash "$STEP" review docs/plan.md 7 2>/dev/null | grep '^panel:')
sub_top=$(cd "$SUB_REPO" && git rev-parse --show-toplevel)
mkdir -p "$TMP/empty"
sub_arg=$(cd "$TMP/empty" && eval "set -- ${sub_line#panel: }" && printf '%s' "${8:-}")
check "review: a checkout path holding \$(…) reaches the panel command as text" \
  "$([ "$sub_arg" = "$sub_top" ] && echo yes || echo no) $([ -e "$TMP/empty/pwned" ] && echo yes || echo no)" "yes no"
rm -rf "$SUB_REPO" "$TMP/empty"
printf '%s\n' '#!/usr/bin/env bash' 'echo "agy-gate usable=true reason=ok review=false resets_at=- claude=on claude_resets_at=- source=probe"' > "$TMP/agy-probe-stub"
TASK_STEP_AGY_GATE="$TMP/agy-probe-stub" step review docs/plan.md 7
check "review: a gate that probed prints the gate line, untrusted named" "$(grep '^gate:' <<<"$out")" "gate: agy=untrusted codex=open"
review_surface false
step review docs/plan.md 7
check "review: risk 3 with reviewers off is a judge-opus seat" "$(grep '^seat:' <<<"$out")" "seat: dforge:judge-opus prompt: $JP7"
check "review: reviewers off shows each family's gate reason" "$(grep '^gate:' <<<"$out")" "gate: agy=setting codex=open"
check "review: and carries no Second Pass section" "$(grep -c 'Second Pass' "$JP7")" "0"
review_surface absent

# review: a step file written before 5.0 may name a head ref; the package
# still stops there.
git branch taskref "$C1"
jq '.head = "taskref"' "$WS/task-1-step.json" > "$TMP/s.json" && mv "$TMP/s.json" "$WS/task-1-step.json"
step review docs/plan.md 1
check "review: a recorded head ref bounds the package" "$rc:$(state_of 1 .reviewHead)" "0:$C1"
jq 'del(.head)' "$WS/task-1-step.json" > "$TMP/s.json" && mv "$TMP/s.json" "$WS/task-1-step.json"

# review: the mechanical checks.
CO="Co-Authored""-By"
CS="Claude""-Session"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty --author="Other <other@example.invalid>" -m "feat: written by another author"
base_at 2 "$PREV"; step review docs/plan.md 2
check "check identity: a different author" "$(grep '^check identity' <<<"$out")" \
  "check identity: $(short HEAD) author Other <other@example.invalid> (expected Darkraise <dark@example.invalid>)"
check "check attribution: clean beside a bad identity" "$(grep '^check attribution' <<<"$out")" "check attribution: clean"
PREV=$(git rev-parse HEAD)
GIT_COMMITTER_NAME=Other GIT_COMMITTER_EMAIL=other@example.invalid git commit -q --allow-empty -m "feat: committed by another"
base_at 2 "$PREV"; step review docs/plan.md 2
check "check identity: a different committer" "$(grep '^check identity' <<<"$out")" \
  "check identity: $(short HEAD) committer Other <other@example.invalid> (expected Darkraise <dark@example.invalid>)"
PREV=$(git rev-parse HEAD)
git -c user.name=Other -c user.email=other@example.invalid commit -q --allow-empty -m "feat: both differ"
base_at 2 "$PREV"; step review docs/plan.md 2
check "check identity: author and committer" "$(grep '^check identity' <<<"$out")" \
  "check identity: $(short HEAD) author Other <other@example.invalid>, committer Other <other@example.invalid> (expected Darkraise <dark@example.invalid>)"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty -m "feat: with a co-author" -m "$CO: X <x@example.invalid>"
base_at 2 "$PREV"; step review docs/plan.md 2
check "check attribution: a co-author trailer" "$(grep '^check attribution' <<<"$out")" \
  "check attribution: $(short HEAD) $CO: X <x@example.invalid>"
check "check identity: clean beside a bad attribution" "$(grep '^check identity' <<<"$out")" "check identity: clean"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty -m "feat: with a session" -m "$CS: abc123"
base_at 2 "$PREV"; step review docs/plan.md 2
check "check attribution: a session trailer" "$(grep '^check attribution' <<<"$out")" "check attribution: $(short HEAD) $CS: abc123"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty -m "feat: tool line" -m "Generated with a tool"
base_at 2 "$PREV"; step review docs/plan.md 2
check "check attribution: a generated-with line" "$(grep '^check attribution' <<<"$out")" "check attribution: $(short HEAD) Generated with a tool"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty -m "feat: emoji line" -m "🤖 Generated with a tool"
base_at 2 "$PREV"; step review docs/plan.md 2
check "check attribution: a symbol before generated-with still counts" "$(grep '^check attribution' <<<"$out")" "check attribution: $(short HEAD) 🤖 Generated with a tool"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty -m "feat: lowercase trailer" -m "co-authored-by: X <x@example.invalid>"
base_at 2 "$PREV"; step review docs/plan.md 2
check "check attribution: the trailer name is case-insensitive" "$(grep '^check attribution' <<<"$out")" "check attribution: $(short HEAD) co-authored-by: X <x@example.invalid>"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty -m "feat: mentions the words" -m "The table is generated with a script, and a co-authored-by: note is prose here."
base_at 2 "$PREV"; step review docs/plan.md 2
check "check attribution: the words inside a sentence are not a trailer" "$(grep '^check attribution' <<<"$out")" "check attribution: clean"
PREV=$(git rev-parse HEAD)
git commit -q --allow-empty -m "feat: clean one"
base_at 2 "$PREV"; step review docs/plan.md 2
check "checks: a clean commit passes both" "$(grep '^check' <<<"$out" | tr '\n' ';')" "check identity: clean;check attribution: clean;"
base_at 2 "$(git rev-parse HEAD~9)"; step review docs/plan.md 2
check "checks: several offenders name the first and count the rest" "$(grep '^check attribution' <<<"$out" | grep -c '; 4 more commit(s)$')" "1"

# review: a route that fails.
step review docs/plan.md 8
check "review: a failed route falls back to judge-opus and says why" \
  "$(grep -c "^seat: dforge:judge-opus prompt: $WS/task-8-review-prompt.md (review-route exited 2: review-route: Task 8: the Evaluation line does not parse" <<<"$out")" "1"

# review: a lens-route failure stops the step before it writes anything.
step review docs/plan.md 9
check "review: a lens-route failure exits 2" "$rc" "2"
check "review: a lens-route failure says which lens" "$(grep -c 'unknown lens id: no-such-lens' "$TMP/err")" "1"
check "review: a lens-route failure writes no prompt file" "$([ -e "$WS/task-9-review-prompt.md" ] && echo yes || echo no)" "no"
check "review: a lens-route failure records no review head" "$(state_of 9 .reviewHead)" "null"

# review: the judge writes its report where the prompt says, and a fresh
# review discards the last one; the Codex seat gets no report-file rule.
review_surface absent
printf 'stale\n' > "$WS/task-2-review-report.md"
step review docs/plan.md 2
RP2="$WS/task-2-review-prompt.md"
check "review report: exit 0" "$rc" "0"
check "review report: the prompt names the report file" \
  "$(grep -cF "Write your full report to $WS/task-2-review-report.md and write nothing else" "$RP2")" "1"
check "review report: the implementer's report keeps its own line" "$(grep -cF "Read the implementer's report: $WS/task-2-report.md" "$RP2")" "1"
check "review report: no placeholder is left" "$(placeholders "$RP2")" "0"
check "review report: a fresh review discards the last report" "$([ -e "$WS/task-2-review-report.md" ] && echo yes || echo no)" "no"
review_surface true
step review docs/plan.md 7
check "review report: the panel prompt carries no report-file rule" \
  "$(grep -c 'review-report.md\|write nothing else' "$WS/task-7-review-panel-prompt.md")" "0"
check "review report: the panel prompt keeps the implementer's report" \
  "$(grep -cF "Read the implementer's report: $WS/task-7-report.md" "$WS/task-7-review-panel-prompt.md")" "1"
review_surface absent
fi

if want rereview || want verdict; then
# --- rereview: the package and the state ---
# The fixture plan's lines carry a leading | so a plan that quotes this suite still lints.
RR_TMP=$TMP/rr
mkdir -p "$RR_TMP"
RR_REPO=$RR_TMP/repo
rr_run() { # rr_run <args...> — task-step in the fixture repo; sets rr_out, rr_err, rr_rc
  rr_out=$(cd "$RR_REPO" && env HOME="$RR_TMP/home" DR_CODEX_SESSION_DIR="$RR_TMP/sessions" CLAUDE_CODE_SESSION_ID=rr-test \
    GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1 MSYS_NO_PATHCONV=1 bash "$RR_S/task-step" "$@" 2>"$RR_TMP/err"); rr_rc=$?
  rr_err=$(cat "$RR_TMP/err")
}
rr_git() { git -C "$RR_REPO" "$@"; }
rr_state() { # rr_state <task> <jq filter>
  jq -r "$2" "$RR_WS/task-$1-step.json" | tr -d '\r'
}
rr_edit() { # rr_edit <file> <mod|add1|add3|add4|bin> — change a fixture file
  local f=$RR_REPO/$1
  RR_N=$((RR_N + 1))
  case $2 in
    mod) awk -v n="$RR_N" 'NR == 2 { print "changed " n; next } { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f" ;;
    add1) printf 'a%s\n' "$RR_N" >> "$f" ;;
    add3) printf 'a%s\nb\nc\n' "$RR_N" >> "$f" ;;
    add4) printf 'a%s\nb\nc\nd\n' "$RR_N" >> "$f" ;;
    bin) printf 'x\000y%s' "$RR_N" >> "$f" ;;
  esac
}
rr_fix() { # rr_fix <task> <round> <bullets separated by |>
  { printf '%s\n' "$3" | tr '|' '\n'; printf '\nFixed.\n'; } > "$RR_WS/task-$1-fix-$2.md"
}
rr_reset() { # back to the reviewed head with the recorded states
  rr_git reset -q --hard "$RR_R0"
  rm -f "$RR_WS"/task-*-fix-*.md "$RR_WS"/task-*-rereview-*-prompt.md
  cp "$RR_TMP/state1.0" "$RR_WS/task-1-step.json"
  cp "$RR_TMP/state2.0" "$RR_WS/task-2-step.json"
}
rr_verdict() { # rr_verdict <task> <round> — the skip line, or "prompt", or "none"
  if grep -q '^re-review: ' <<<"$rr_out"; then grep '^re-review: ' <<<"$rr_out"
  elif [ -f "$RR_WS/task-$1-rereview-$2-prompt.md" ]; then echo prompt
  else echo none; fi
}
rr_case() { # rr_case <name> <task> <flags> <bullets> <edits> <want> — one fix, one rereview
  local e
  rr_reset
  for e in $5; do rr_edit "${e%%:*}" "${e#*:}"; done
  rr_git add -A && rr_git commit -qm fix
  rr_fix "$2" 1 "$4"
  # shellcheck disable=SC2086
  rr_run rereview docs/plan.md "$2" $3
  check "rereview $1" "$rr_rc $(rr_verdict "$2" 1)" "$6"
}

mkdir -p "$RR_TMP/home" "$RR_REPO/docs"
git init -q "$RR_REPO"
rr_git config user.name t
rr_git config user.email t@example.invalid
sed 's/^|//' > "$RR_REPO/docs/plan.md" <<'PLAN'
|# Rereview Fixture Plan
|
|**Goal:** Fixture.
|
|**Execution:** inline — `claude --model sonnet --effort high` — fixture
|
|## Task index
|
|1. Small
|2. Risky
|3. Unreviewed
|
|### Task 1: Small
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 2: Risky
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 3 = 6
|
|### Task 3: Unreviewed
|
|**Files:**
|- Modify: `other.txt`
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
PLAN
awk '{ print } /^\*\*Goal:\*\*/ { print ""; print "**Host:** codex" }' "$RR_REPO/docs/plan.md" > "$RR_REPO/docs/codex-plan.md"
seq 1 10 | sed 's/^/line /' > "$RR_REPO/app.txt"
cp "$RR_REPO/app.txt" "$RR_REPO/other.txt"
cp "$RR_REPO/app.txt" "$RR_REPO/test.txt"
printf 'a\000b' > "$RR_REPO/bin.dat"
rr_git add -A && rr_git commit -qm base
RR_N=0

for t in 1 2 3; do
  (cd "$RR_REPO" && env HOME="$RR_TMP/home" GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1 MSYS_NO_PATHCONV=1 bash "$RR_S/task-brief" --open docs/plan.md "$t" >/dev/null)
  check "rereview fixture: open $t" "$?" "0"
done
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm work
rr_run review docs/plan.md 1
check "rereview fixture: review 1" "$rr_rc" "0"
rr_run review docs/plan.md 2
check "rereview fixture: review 2" "$rr_rc" "0"
RR_WS=$(winpath "$(cd "$RR_REPO" && env HOME="$RR_TMP/home" bash "$RR_S/sdd-workspace" docs/plan.md)")
RR_R0=$(rr_git rev-parse HEAD)
cp "$RR_WS/task-1-step.json" "$RR_TMP/state1.0"
cp "$RR_WS/task-2-step.json" "$RR_TMP/state2.0"
fi

if want rereview; then
# Every fix round gets its re-review: there is no small-fix skip.
rr_case "prompts for a one-line fix" 1 "" "- app.txt: wrong value" "app.txt:mod" "0 prompt"
rr_case "prompts for a one-line fix on a risk 3 task" 2 "" "- app.txt: wrong value" "app.txt:mod" "0 prompt"
check "rereview: a risk 3 task keeps the judge-sonnet-high seat" "$(grep -c '^seat: dforge:judge-sonnet-high prompt: ' <<<"$rr_out")" "1"
rr_case "prompts for a fix that edits only another source file" 1 "" "- app.txt: wrong value" "other.txt:mod" "0 prompt"
rr_case "prompts for a fix that edits only a test file" 1 "" "- app.txt: wrong value" "test.txt:mod" "0 prompt"
rr_reset
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm fix
rr_fix 1 1 "- app.txt: wrong value"
rr_run rereview docs/plan.md 1 --covered
check "rereview: --covered is a usage error" "$rr_rc" "2"

# A prompt round packages the fix and advances the state.
rr_reset
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm fix
rr_fix 1 1 "- app.txt: wrong value"
jq '.t0 = 1' "$RR_WS/task-1-step.json" > "$RR_TMP/t0.tmp" && cp "$RR_TMP/t0.tmp" "$RR_WS/task-1-step.json"
rr_run rereview docs/plan.md 1
check "rereview round: records the head as the review head" "$(rr_state 1 .reviewHead)" "$(rr_git rev-parse HEAD)"
check "rereview round: increments the round" "$(rr_state 1 .round)" "1"
check "rereview round: replaces t0 with the time of the re-review" "$([ "$(rr_state 1 .t0)" -gt 1000000000 ] && echo yes || echo no)" "yes"
check "rereview round: the digest shows the recorded t0" "$(sed -n 's/^state: .* t0 //p' <<<"$rr_out")" "$(rr_state 1 .t0)"
check "rereview round: the digest names the state" "$(grep -c "^state: base .* review-head $(rr_git rev-parse --short HEAD) round 1 t0 " <<<"$rr_out")" "1"
check "rereview round: the digest ends with the budget line" "$(tail -n 1 <<<"$rr_out" | cut -c1-7)" "budget:"
# With the plan's other tasks complete the digest's budget line names the tail,
# which never hands off in strict mode.
cp "$RR_WS/progress.md" "$RR_TMP/ledger.keep"
printf 'Task 2: complete (commit abc1234)\nTask 3: complete (commit abc1235)\n' >> "$RR_WS/progress.md"
rr_reset
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm fix
rr_fix 1 1 "- app.txt: wrong value"
rr_run rereview docs/plan.md 1
check "rereview: in the plan's last task the budget line names the tail" "$(tail -n 1 <<<"$rr_out" | cut -c1-19)" "budget (last task):"
cp "$RR_TMP/ledger.keep" "$RR_WS/progress.md"

# A written prompt: the judge seat, no unexpanded placeholder, the open
# findings, the fix base and the diff file.
rr_reset
rr_edit app.txt add4
rr_git add -A && rr_git commit -qm fix
rr_fix 1 1 "- app.txt: wrong value|- other.txt: stale"
rr_run rereview docs/plan.md 1
RR_P=$RR_WS/task-1-rereview-1-prompt.md
check "rereview prompt: the digest names the seat and the file" "$(grep -c "^seat: dforge:judge-sonnet-high prompt: $RR_P\$" <<<"$rr_out")" "1"
check "rereview prompt: no placeholder is left" "$(grep -cE '\[(BRIEF_FILE|FINDINGS|REPORT_FILE|FIX_BASE_SHA|HEAD_SHA|DIFF_FILE|MODEL)\]' "$RR_P")" "0"
check "rereview prompt: the open findings are listed" "$(grep -c '^- app.txt: wrong value$\|^- other.txt: stale$' "$RR_P")" "2"
check "rereview prompt: the fix base is the recorded review head" "$(grep -c "Fix base:\*\* $RR_R0 " "$RR_P")" "1"
check "rereview prompt: the head is HEAD" "$(grep -c "Head:\*\* $(rr_git rev-parse HEAD)\$" "$RR_P")" "1"
RR_DIFF=$(sed -n 's/^\*\*Diff file:\*\* //p' "$RR_P")
check "rereview prompt: the diff file exists" "$([ -s "$RR_DIFF" ] && echo yes || echo no)" "yes"
check "rereview prompt: the report and brief paths" "$(grep -c "$RR_WS/task-1-report.md\|$RR_WS/task-1-brief.md" "$RR_P")" "2"
check "rereview prompt: the fence and indent are removed" "$(grep -c '^```\|^    You are re-reviewing' "$RR_P")" "0"

# Rounds chain: the next round's base is the last round's head.
RR_H1=$(rr_git rev-parse HEAD)
rr_edit app.txt add4
rr_git add -A && rr_git commit -qm fix2
rr_fix 1 2 "- app.txt: still wrong"
rr_run rereview docs/plan.md 1
check "rereview round 2: writes the round 2 prompt" "$([ -f "$RR_WS/task-1-rereview-2-prompt.md" ] && echo yes || echo no)" "yes"
check "rereview round 2: the fix base is round 1's head" "$(grep -c "Fix base:\*\* $RR_H1 " "$RR_WS/task-1-rereview-2-prompt.md")" "1"
check "rereview round 2: the state round is 2" "$(rr_state 1 .round)" "2"

# The loop holds two rounds: a third rereview writes nothing and names the breaker.
rr_edit app.txt add4
rr_git add -A && rr_git commit -qm fix3
rr_fix 1 3 "- app.txt: still wrong"
cp "$RR_WS/task-1-step.json" "$RR_TMP/state1.2"
rr_run rereview docs/plan.md 1
check "rereview round 3: exits 7" "$rr_rc" "7"
check "rereview round 3: names the cap and the breaker" "$(grep -c 'task-step: fix round 3 is past the cap of 2; send the open findings to the breaker' <<<"$rr_err")" "1"
check "rereview round 3: writes no prompt" "$([ -f "$RR_WS/task-1-rereview-3-prompt.md" ] && echo yes || echo no)" "no"
check "rereview round 3: leaves the state alone" "$(cmp -s "$RR_WS/task-1-step.json" "$RR_TMP/state1.2" && echo same || echo changed)" "same"
check "rereview round 3: prints no digest" "$rr_out" ""
# A step state an older run left at round 4 of 5 goes to the breaker too.
jq '.round = 4' "$RR_TMP/state1.2" > "$RR_WS/task-1-step.json"
rr_fix 1 5 "- app.txt: still wrong"
rr_run rereview docs/plan.md 1
check "rereview after an older run's round 4: exits 7" "$rr_rc" "7"
check "rereview after an older run's round 4: names round 5" "$(grep -c 'fix round 5 is past the cap of 2' <<<"$rr_err")" "1"

# A zero-padded task number names the same task.
rr_reset
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm fix
rr_fix 1 1 "- app.txt: wrong value"
rr_run rereview docs/plan.md 01
check "rereview names Task 1 as 01" "$rr_rc $(rr_verdict 1 1)" "0 prompt"

# The package's budget line is the digest's: context-size runs once.
RR_KIT=$RR_TMP/kit
mkdir -p "$RR_KIT" && cp -R "$RR_S" "$RR_S/../reference" "$RR_S/../criteria" "$RR_KIT/"
printf '#!/usr/bin/env bash\necho run >> "%s"\necho "budget: kit"\n' "$RR_TMP/context-size.count" > "$RR_KIT/scripts/context-size"
rr_reset
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm fix
rr_fix 1 1 "- app.txt: wrong value"
RR_S_KEEP=$RR_S RR_S=$RR_KIT/scripts
rr_run rereview docs/plan.md 1
RR_S=$RR_S_KEEP
check "rereview runs context-size once and prints its line" "$rr_rc:$(grep -c '' "$RR_TMP/context-size.count" 2>/dev/null):$(tail -n 1 <<<"$rr_out")" "0:1:budget: kit"

# A second rereview before the round's report reprints the round.
rr_reset
rr_edit app.txt mod
rr_git add -A && rr_git commit -qm fix
rr_fix 1 1 "- app.txt: wrong value"
rr_run rereview docs/plan.md 1
rr_run rereview docs/plan.md 1
check "rereview repeated before its report: reprints round 1 and keeps the round" \
  "$rr_rc $(jq -r '.round' "$RR_WS/task-1-step.json") $(head -n 1 <<<"$rr_out")" \
  "0 1 task 1: re-review round 1: prompt already written, no report yet"
rr_reset
rr_fix 1 1 "- app.txt: wrong value"
rr_run rereview docs/plan.md 1
check "rereview with no commit since the review exits 6" \
  "$rr_rc $(grep -c 'no commit since the reviewed head' <<<"$rr_err") $(cmp -s "$RR_WS/task-1-step.json" "$RR_TMP/state1.0" && echo same || echo changed)" "6 1 same"

# Refusals write nothing.
rr_reset
rr_run rereview docs/plan.md 3
check "rereview before review exits 6" "$rr_rc" "6"
rr_reset
rr_run rereview docs/plan.md 1
check "rereview with no fix message exits 6" "$rr_rc" "6"
check "rereview with no fix message leaves the state alone" "$(cmp -s "$RR_WS/task-1-step.json" "$RR_TMP/state1.0" && echo same || echo changed)" "same"
printf 'No bullets here.\n' > "$RR_WS/task-1-fix-1.md"
rr_run rereview docs/plan.md 1
check "rereview with a fix message that has no bullets exits 2" "$rr_rc" "2"
rr_reset
rr_run rereview docs/plan.md 99
check "rereview of a task not in the plan exits 3" "$rr_rc" "3"
rr_run rereview docs/codex-plan.md 1
check "rereview on a Host: codex plan exits 2" "$rr_rc" "2"
check "rereview on a Host: codex plan writes nothing" "$(ls -A "$(dirname "$RR_WS")/codex-plan" 2>/dev/null | wc -l | tr -d ' ')" "0"
rr_run rereview docs/plan.md 1 --bogus
check "rereview with an unknown flag exits 2" "$rr_rc" "2"
for flag in --base --head; do
  rr_run rereview docs/plan.md 1 "$flag" x
  check "rereview: $flag is no flag" "$rr_rc" "2"
done
fi

if want verdict; then
# The re-review judge writes its report where the prompt says; a fresh round
# discards a stale one at that path.
rr_reset
rr_edit app.txt add4
rr_git add -A && rr_git commit -qm fix
rr_fix 1 1 "- app.txt: wrong value|- other.txt: stale"
printf 'stale\n' > "$RR_WS/task-1-rereview-1-report.md"
rr_run rereview docs/plan.md 1
RR_P=$RR_WS/task-1-rereview-1-prompt.md
check "rereview report: exit 0" "$rr_rc" "0"
check "rereview report: the prompt names the round's report file" \
  "$(grep -cF "Write your full report to $RR_WS/task-1-rereview-1-report.md and write nothing else" "$RR_P")" "1"
check "rereview report: the implementer's report is filled" "$(grep -cF "$RR_WS/task-1-report.md" "$RR_P")" "1"
check "rereview report: no implementer-report placeholder is left" "$(grep -c '\[IMPLEMENTER_REPORT_FILE\]' "$RR_P")" "0"
check "rereview report: a fresh round discards the stale report" "$([ -e "$RR_WS/task-1-rereview-1-report.md" ] && echo yes || echo no)" "no"

# --- verdict: the report digest, the fix files and the tracked-file check ---
vd_report() { sed 's/^|//' > "$1"; } # vd_report <file> — the report on stdin, its leading | stripped
first_block() { awk '{ sub(/\r$/, "") } /^$/ { exit } { print }' "$1" | tr '\n' ';'; }

# A task review: the digest, the fix file, the deferred Minor lines.
rr_reset
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: fail
|quality: changes
|scores: spec 7 / scope 15 / verification 12 / quality 9
|
|## Strengths
|Small and focused.
|
|## Findings
|- [Critical] app.txt:2 — wrong value
|  The second line must read "line 2".
|- [Important] other.txt:4 — stale copy
|- [Minor] app.txt:5 — naming
|- [Minor] test.txt:0 — no edge case
|
|## Cannot verify
|- the caller passes the flag
|
|## Assessment
|Needs fixes.
REPORT
rr_run verdict docs/plan.md 1
VD=$rr_out
check "verdict: exit 0" "$rr_rc" "0"
check "verdict: the digest names the report" "$(head -n 1 <<<"$VD")" "task 1: verdict from $RR_WS/task-1-review-report.md"
check "verdict: the verdict lines" "$(grep -E '^(spec|quality|scores): ' <<<"$VD" | tr '\n' ';')" \
  "spec: fail;quality: changes;scores: spec 7 / scope 15 / verification 12 / quality 9;"
check "verdict: the counts by severity" "$(grep '^findings: ' <<<"$VD")" "findings: 1 Critical, 1 Important, 2 Minor"
check "verdict: one line per Critical or Important finding" "$(grep -E '^(Critical|Important) ' <<<"$VD" | tr '\n' ';')" \
  "Critical 1 app.txt:2 — wrong value;Important 1 other.txt:4 — stale copy;"
check "verdict: Minor findings are not listed" "$(grep -c '^Minor ' <<<"$VD")" "0"
check "verdict: the cannot-verify item" "$(grep '^cannot-verify: ' <<<"$VD")" "cannot-verify: the caller passes the flag"
check "verdict: the fix line" "$(grep '^fix: ' <<<"$VD")" "fix: $RR_WS/task-1-fix-1.md (2 findings)"
check "verdict: the minor line" "$(grep '^minor: ' <<<"$VD")" "minor: 2 logged as deferred"
check "verdict: the tracked check" "$(grep '^check tracked: ' <<<"$VD")" "check tracked: clean"
check "verdict: the last line is the budget line" "$(tail -n 1 <<<"$VD" | cut -c1-6)" "budget"
check "verdict: at most 20 lines besides the finding lines" "$([ "$(grep -cvE '^(Critical|Important) ' <<<"$VD")" -le 20 ] && echo yes || echo no)" "yes"
check "verdict: the fix file's bullets" "$(first_block "$RR_WS/task-1-fix-1.md")" "- app.txt:2: wrong value;- other.txt:4: stale copy;"
check "verdict: the fix file names the report" "$(grep -cF "$RR_WS/task-1-review-report.md" "$RR_WS/task-1-fix-1.md")" "1"
check "verdict: Minor findings go to the ledger as deferred" \
  "$(grep -cE '^Task 1: minor \(deferred\): (app\.txt:5 — naming|test\.txt:0 — no edge case)$' "$RR_WS/progress.md")" "2"
rr_run verdict docs/plan.md 1
check "verdict: a second run adds no ledger line" "$(grep -c '^Task 1: minor (deferred): app.txt:5 — naming$' "$RR_WS/progress.md")" "1"
# A ledger past the pipe buffer: the Minor line near its top is still found.
cp "$RR_WS/progress.md" "$RR_TMP/progress.keep"
awk 'BEGIN { for (i = 0; i < 4000; i++) printf "# filler line %04d of a long ledger, padded to sixty characters\n", i }' >> "$RR_WS/progress.md"
rr_run verdict docs/plan.md 1
check "verdict: a long ledger adds no second Minor line" "$(grep -c '^Task 1: minor (deferred): app.txt:5 — naming$' "$RR_WS/progress.md")" "1"
cp "$RR_TMP/progress.keep" "$RR_WS/progress.md"

# The fix file feeds the re-review, and the re-review's verdict writes the next round's.
rr_edit app.txt add4
rr_git add -A && rr_git commit -qm fix
rr_run rereview docs/plan.md 1
check "verdict then rereview: the fix file's findings reach the prompt" \
  "$(grep -cE '^- (app\.txt:2: wrong value|other\.txt:4: stale copy)$' "$RR_WS/task-1-rereview-1-prompt.md")" "2"
vd_report "$RR_WS/task-1-rereview-1-report.md" <<'REPORT'
|## Verdict
|fix round: open
|open: 1
|
|## Finding verdicts
|- app.txt:2: wrong value — ADDRESSED — app.txt:2 reads "line 2"
|- other.txt:4: stale copy — NOT ADDRESSED — other.txt:4 is unchanged
|
|## Findings
|- [Important] other.txt:4 — stale copy
|- [Minor] app.txt:9 — out of scope: trailing space
REPORT
rr_run verdict docs/plan.md 1 --rereview 1
check "verdict --rereview: passes against the state rereview recorded" "$rr_rc" "0"
check "verdict --rereview: reads the round's report" "$(head -n 1 <<<"$rr_out")" "task 1: verdict from $RR_WS/task-1-rereview-1-report.md"
check "verdict --rereview: the round lines" "$(grep -E '^(fix round|open): ' <<<"$rr_out" | tr '\n' ';')" "fix round: open;open: 1;"
check "verdict --rereview: writes the next round's fix file" "$(first_block "$RR_WS/task-1-fix-2.md")" "- other.txt:4: stale copy;"
# Round 2 is the cap: what is still open goes to the breaker, not a third fix file.
jq '.round = 2' "$RR_WS/task-1-step.json" > "$RR_WS/task-1-step.json.tmp" && mv "$RR_WS/task-1-step.json.tmp" "$RR_WS/task-1-step.json"
cp "$RR_WS/task-1-rereview-1-report.md" "$RR_WS/task-1-rereview-2-report.md"
rr_run verdict docs/plan.md 1 --rereview 2
check "verdict --rereview 2: exit 0" "$rr_rc" "0"
check "verdict --rereview 2: the fix line names the breaker" "$(grep '^fix: ' <<<"$rr_out")" "fix: breaker (round 2 of 2; 1 finding)"
check "verdict --rereview 2: no third fix file" "$([ -e "$RR_WS/task-1-fix-3.md" ] && echo yes || echo no)" "no"
rm -f "$RR_WS/task-1-rereview-2-report.md"
jq '.round = 1' "$RR_WS/task-1-step.json" > "$RR_WS/task-1-step.json.tmp" && mv "$RR_WS/task-1-step.json.tmp" "$RR_WS/task-1-step.json"

# A verdict reads the round the step file is at, never another round's report.
rr_run verdict docs/plan.md 1
check "verdict without --rereview after a rereview exits 6" "$rr_rc $(grep -c -- '--rereview 1' <<<"$rr_err")" "6 1"
rr_run verdict docs/plan.md 1 --rereview 2
check "verdict --rereview 2 at round 1 exits 6" "$rr_rc" "6"
vd_round() { # vd_round <round> — the step file at the round a verdict's flag names
  jq --argjson r "$1" '.round = $r' "$RR_WS/task-1-step.json" > "$RR_WS/task-1-step.json.tmp" && mv "$RR_WS/task-1-step.json.tmp" "$RR_WS/task-1-step.json"
}

# Failures: a missing or malformed report exits 5 and writes no fix file.
vd_round 2
rr_run verdict docs/plan.md 1 --rereview 2
check "verdict: a missing report exits 5" "$rr_rc" "5"
check "verdict: a missing report is named" "$(grep -cF "$RR_WS/task-1-rereview-2-report.md" <<<"$rr_err")" "1"
check "verdict: a missing report writes no fix file" "$([ -e "$RR_WS/task-1-fix-3.md" ] && echo yes || echo no)" "no"
printf 'spec: pass\n' > "$RR_WS/task-1-review-report.md"
vd_round 0
rr_run verdict docs/plan.md 1
check "verdict: a report that does not open with ## Verdict exits 5" "$rr_rc" "5"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|scores: spec 17 / scope 18 / verification 16 / quality 16
REPORT
vd_round 0
rr_run verdict docs/plan.md 1
check "verdict: a report missing a verdict key exits 5" "$rr_rc" "5"
check "verdict: the missing key is named" "$(grep -c 'quality' <<<"$rr_err")" "1"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: ✅
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
REPORT
vd_round 0
rr_run verdict docs/plan.md 1
check "verdict: a verdict value outside its set exits 5" "$rr_rc" "5"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: fail
|quality: changes
|scores: spec 7 / scope 15 / verification 12 / quality 9
|
|## Findings
|- [Severe] app.txt:2 — wrong value
REPORT
vd_round 0
rr_run verdict docs/plan.md 1
check "verdict: a finding line outside the grammar exits 5" "$rr_rc" "5"
check "verdict: the bad line is quoted" "$(grep -c 'Severe' <<<"$rr_err")" "1"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: fail
|quality: changes
|scores: spec 7 / scope 15 / verification 12 / quality 9
|
|## Findings
|- [Important] docs/user guide.md:3-4 — the heading is wrong - twice
REPORT
vd_round 0
rr_run verdict docs/plan.md 1
check "verdict: a finding on a path with a space is read whole" "$rr_rc $(grep -c '^Important 1 docs/user guide.md:3-4 — the heading is wrong - twice$' <<<"$rr_out")" "0 1"
rm -f "$RR_WS"/task-1-fix-*.md
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: fail
|quality: changes
|scores: spec 7 / scope 15 / verification 12 / quality 9
|
|## Findings
|- [Important] (Task 1) app.txt:2 — a task prefix
REPORT
vd_round 0
rr_run verdict docs/plan.md 1
check "verdict: a task finding with a (Task N) prefix exits 5" "$rr_rc $(grep -c 'a task prefix' <<<"$rr_err")" "5 1"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: fail
|quality: changes
|scores: spec 7 / scope 15 / verification 12 / quality 9
|
|## Issues
|- [Important] app.txt:2 — filed under the wrong heading
|
|## Findings
|- [Minor] app.txt:5 — naming
REPORT
vd_round 0
rr_run verdict docs/plan.md 1
check "verdict: spec fail with no Critical or Important finding exits 5" "$rr_rc $(grep -c 'no Critical or Important finding' <<<"$rr_err")" "5 1"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: fail
|quality: changes
|scores: spec 7 / scope 15 / verification 12 / quality 9
|
|## Findings
|### Critical
|- [Critical] app.txt:2 — wrong value
REPORT
vd_round 0
rr_run verdict docs/plan.md 1
check "verdict: a sub-heading under Findings exits 5" "$rr_rc $(grep -c '### Critical' <<<"$rr_err")" "5 1"
vd_report "$RR_WS/task-1-rereview-1-report.md" <<'REPORT'
|## Verdict
|fix round: maybe
|open: 1
|
|## Findings
|- [Important] other.txt:4 — stale copy
REPORT
vd_round 1
rr_run verdict docs/plan.md 1 --rereview 1
check "verdict --rereview: a fix round value outside its set exits 5" "$rr_rc $(grep -c 'fix round: maybe' <<<"$rr_err")" "5 1"
vd_report "$RR_WS/task-1-rereview-1-report.md" <<'REPORT'
|## Verdict
|fix round: open
|open: 1
|
|## Findings
REPORT
vd_round 1
rr_run verdict docs/plan.md 1 --rereview 1
check "verdict --rereview: an open round with no open finding exits 5" "$rr_rc $(grep -c 'fix round: open with no Critical or Important finding' <<<"$rr_err")" "5 1"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
|
|## External findings
|- [CONFIRMED] codex app.txt:2 wrong value - the diff shows it
|
|## Findings
REPORT
vd_round 0
rr_run verdict docs/plan.md 1
check "verdict: External findings that are not the last section exit 5" "$rr_rc" "5"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
|
|## Findings
|
|## Codex findings
|- [CONFIRMED] app.txt:2 wrong value - the diff shows it
REPORT
vd_round 0
rr_run verdict docs/plan.md 1
check "verdict: a report whose external section is still Codex findings exits 5" "$rr_rc $(grep -c 'External findings' <<<"$rr_err")" "5 1"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
|
|## Findings:
|- [Critical] app.txt:2 — wrong value
REPORT
vd_round 0
rr_run verdict docs/plan.md 1
check "verdict: a misspelled Findings heading exits 5" "$rr_rc $(grep -c '## Findings:' <<<"$rr_err")" "5 1"
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
|
|## Findings
REPORT
rm -f "$RR_WS"/task-1-fix-*.md
vd_round 0
rr_run verdict docs/plan.md 1
check "verdict: a clean report exits 0" "$rr_rc" "0"
check "verdict: a clean report writes no fix file" "$(grep '^fix: ' <<<"$rr_out")" "fix: none"
check "verdict: and leaves no fix file behind" "$(ls "$RR_WS"/task-1-fix-*.md 2>/dev/null | wc -l | tr -d ' ')" "0"

# Failures: a tracked file changed during the review exits 6 and names it.
printf 'judge edit\n' >> "$RR_REPO/app.txt"
rr_run verdict docs/plan.md 1
check "verdict: a tracked file changed during the review exits 6" "$rr_rc" "6"
check "verdict: the changed file is named on its own line" "$(grep -cx 'app.txt' <<<"$rr_err")" "1"
check "verdict: exit 6 restores only the review seat's change" \
  "$rr_rc $(grep -c "run a file's restore command only when the review seat made the change, and keep any other writer's edit" <<<"$rr_err") $(grep -c 'restore each to its recorded state' <<<"$rr_err")" "6 1 0"
check "verdict: a file clean at review time is restored from HEAD" \
  "$(grep -A1 -x 'app.txt' <<<"$rr_err" | sed -n 2p | grep -c '^  restore: git -C .* checkout -- app.txt$')" "1"
rr_git checkout -- app.txt
rr_run verdict docs/plan.md 1
check "verdict: restored files pass the check" "$rr_rc" "0"
printf 'new\n' > "$RR_REPO/untracked.txt"
rr_run verdict docs/plan.md 1
check "verdict: an untracked file is not a tracked change" "$rr_rc" "0"
rm -f "$RR_REPO/untracked.txt"
rr_git commit -q --allow-empty -m "moved"
rr_run verdict docs/plan.md 1
check "verdict: a HEAD that moved exits 6" "$rr_rc" "6"
check "verdict: a HEAD that moved is named" "$(grep -c 'HEAD moved' <<<"$rr_err")" "1"
rr_git reset -q --hard HEAD~1

# A file already changed when the review ran is compared by content.
rr_reset
printf 'dirty\n' >> "$RR_REPO/other.txt"
rr_run review docs/plan.md 1
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
REPORT
rr_run verdict docs/plan.md 1
check "verdict: a file already changed at review time passes" "$rr_rc" "0"
printf 'more\n' >> "$RR_REPO/other.txt"
rr_run verdict docs/plan.md 1
check "verdict: a further change to it exits 6" "$rr_rc" "6"
check "verdict: and names it" "$(grep -cx 'other.txt' <<<"$rr_err")" "1"
check "verdict: a file dirty at review time is never restored from HEAD" "$(grep -c 'checkout -- other.txt' <<<"$rr_err")" "0"
restore=$(grep -A1 -x 'other.txt' <<<"$rr_err" | sed -n 2p | sed 's/^  restore: //')
(cd "$RR_REPO" && bash -c "$restore")
check "verdict: its restore command keeps the edit made before the review" "$(tail -n 1 "$RR_REPO/other.txt")" "dirty"
rr_run verdict docs/plan.md 1
check "verdict: and the restored file passes the check" "$rr_rc" "0"
rm -f "$RR_REPO/other.txt"
rr_run verdict docs/plan.md 1
check "verdict: a file deleted by the reviewer gets a restore command" \
  "$(grep -A1 -x 'other.txt' <<<"$rr_err" | sed -n 2p | grep -c '^  restore: ')" "1"
restore=$(grep -A1 -x 'other.txt' <<<"$rr_err" | sed -n 2p | sed 's/^  restore: //')
(cd "$RR_REPO" && bash -c "$restore")
check "verdict: which brings back the recorded content" "$(tail -n 1 "$RR_REPO/other.txt")" "dirty"
# The snapshot is data in the task's state file: a hash that is no object id,
# or a path outside the work tree, gets no command to run.
jq '.reviewCheck.dirty += [{path: "../outside.txt", hash: "deleted"}, {path: "/tmp/abs.txt", hash: "deleted"}, {path: "tampered.txt", hash: "HEAD;touch pwned"}]' \
  "$RR_WS/task-1-step.json" > "$RR_TMP/tampered.json" && mv "$RR_TMP/tampered.json" "$RR_WS/task-1-step.json"
rr_run verdict docs/plan.md 1
check "verdict: a tampered snapshot still exits 6" "$rr_rc" "6"
check "verdict: a path outside the work tree gets no command" \
  "$(grep -A1 -x -e '../outside.txt' -e '/tmp/abs.txt' <<<"$rr_err" | grep -c '^  restore: none: ')" "2"
check "verdict: a hash that is no object id gets no command" \
  "$(grep -A1 -x 'tampered.txt' <<<"$rr_err" | sed -n 2p | grep -c '^  restore: none: ')" "1"
check "verdict: and its text is printed nowhere" "$(grep -c 'pwned' <<<"$rr_err")" "0"
rr_git checkout -- other.txt

# A name git quotes, and a mode-only change, still reach the check.
if ! command -v cygpath >/dev/null 2>&1; then
  rr_reset
  printf 'one\n' > "$RR_REPO/q\"uote.txt"
  rr_git add -A && rr_git commit -qm quoted
  printf 'two\n' >> "$RR_REPO/q\"uote.txt"
  rr_run review docs/plan.md 1
  vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
REPORT
  printf 'three\n' >> "$RR_REPO/q\"uote.txt"
  rr_run verdict docs/plan.md 1
  check "verdict: a change to a file whose name git quotes exits 6" "$rr_rc $(grep -cx 'q"uote.txt' <<<"$rr_err")" "6 1"
  rr_reset
  printf 'dirty\n' >> "$RR_REPO/other.txt"
  rr_run review docs/plan.md 1
  vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
REPORT
  chmod +x "$RR_REPO/other.txt"
  rr_run verdict docs/plan.md 1
  check "verdict: a mode-only change to a file dirty at review time exits 6" "$rr_rc $(grep -cx 'other.txt' <<<"$rr_err")" "6 1"
  chmod -x "$RR_REPO/other.txt"
  rr_git checkout -- other.txt
  # A restore line never writes through a link swapped in after the review.
  rr_reset
  printf 'dirty\n' >> "$RR_REPO/other.txt"
  rr_run review docs/plan.md 1
  vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
REPORT
  printf 'keep\n' > "$RR_TMP/outside.txt"
  rm -f "$RR_REPO/other.txt" && ln -s "$RR_TMP/outside.txt" "$RR_REPO/other.txt"
  rr_run verdict docs/plan.md 1
  link_rc=$rr_rc
  while IFS= read -r restore; do
    (cd "$RR_REPO" && bash -c "$restore" >/dev/null 2>&1)
  done < <(grep -A1 -x 'other.txt' <<<"$rr_err" | sed -n 's/^  restore: //p')
  check "verdict: a path swapped for a symbolic link is not written through" "$link_rc $(cat "$RR_TMP/outside.txt")" "6 keep"
  rm -f "$RR_REPO/other.txt"
  rr_git checkout -- other.txt
  # Nor through a link planted at the restore's temporary name.
  rr_reset
  printf 'dirty\n' >> "$RR_REPO/other.txt"
  rr_run review docs/plan.md 1
  vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
REPORT
  printf 'more\n' >> "$RR_REPO/other.txt"
  ln -s "$RR_TMP/outside.txt" "$RR_REPO/other.txt.dforge-restore"
  rr_run verdict docs/plan.md 1
  restore=$(grep -A1 -x 'other.txt' <<<"$rr_err" | sed -n 's/^  restore: //p')
  (cd "$RR_REPO" && bash -c "$restore" >/dev/null 2>&1)
  check "verdict: a link at the restore's temporary name is not written through" \
    "$(cat "$RR_TMP/outside.txt") $(tail -n 1 "$RR_REPO/other.txt")" "keep dirty"
  rm -f "$RR_REPO/other.txt.dforge-restore"
  rr_git checkout -- other.txt
fi

# A ledger that names another plan is never written by this plan's review.
rr_reset
cp "$RR_WS/progress.md" "$RR_TMP/progress.mine"
{ printf '# SDD ledger — plan: docs/other.md\n'; tail -n +2 "$RR_TMP/progress.mine"; } > "$RR_WS/progress.md"
cp "$RR_WS/progress.md" "$RR_TMP/progress.other"
rr_run review docs/plan.md 1
check "review: a ledger that names another plan exits 2" \
  "$rr_rc $(grep -c 'belongs to docs/other.md' <<<"$rr_err") $(cmp -s "$RR_WS/progress.md" "$RR_TMP/progress.other" && echo same || echo changed)" "2 1 same"
cp "$RR_TMP/progress.mine" "$RR_WS/progress.md"
rr_reset

# A state recorded before the check existed still reads its report; usage.
rr_reset
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|quality: approved
|scores: spec 17 / scope 18 / verification 16 / quality 16
REPORT
jq 'del(.reviewCheck)' "$RR_TMP/state1.0" > "$RR_WS/task-1-step.json"
rr_run verdict docs/plan.md 1
check "verdict: a state without a recorded check exits 0" "$rr_rc" "0"
check "verdict: and says the check was not recorded" "$(grep -c '^check tracked: not recorded' <<<"$rr_out")" "1"
rr_reset
rr_run verdict docs/plan.md 1 --cwd x
check "verdict: --cwd is no flag" "$rr_rc" "2"
jq '.reviewHead = null' "$RR_TMP/state2.0" > "$RR_WS/task-2-step.json"
rr_run verdict docs/plan.md 2
check "verdict: before review exits 6" "$rr_rc" "6"
cp "$RR_TMP/state2.0" "$RR_WS/task-2-step.json"
rr_run verdict docs/plan.md
check "verdict: no task number exits 2" "$rr_rc" "2"
rr_run verdict docs/plan.md 1 --rereview x
check "verdict: a non-numeric --rereview exits 2" "$rr_rc" "2"
rr_run verdict docs/plan.md 99
check "verdict: no such task exits 3" "$rr_rc" "3"
rr_run verdict docs/codex-plan.md 1
check "verdict: a Host: codex plan exits 2" "$rr_rc" "2"
# --- verdict_line_ref_parenthetical: a judge's slip after the line range (A15) ---
rr_reset
vd_report "$RR_WS/task-1-review-report.md" <<'REPORT'
|## Verdict
|spec: pass
|quality: changes
|scores: spec 15 / scope 15 / verification 12 / quality 9
|
|## Findings
|- [Important] plugins/x.sh:71-76(diff) — off by one
|- [Minor] plugins/y.sh:3(diff) — naming
|
|## Cannot verify
|- none
REPORT
rr_run verdict docs/plan.md 1
check "verdict_line_ref_parenthetical: exit 0" "$rr_rc" "0"
check "verdict_line_ref_parenthetical: the finding names lines 71-76" "$(grep -E '^Important ' <<<"$rr_out")" "Important 1 plugins/x.sh:71-76 — off by one"
check "verdict_line_ref_parenthetical: the fix file bullet" "$(first_block "$RR_WS/task-1-fix-1.md")" "- plugins/x.sh:71-76: off by one;"
fi

# A step-state write that fails stops the step instead of passing silently.
if want start; then
  cd "$REPO" || exit 1
  rm -f "$WS/task-5-step.json"
  open_task 5
  # The step file is replaced through a temporary file beside it: a mktemp
  # that refuses that name is a write that fails.
  mkdir -p "$TMP/shim"
  printf '%s\n' '#!/usr/bin/env bash' 'case "$*" in *.task-5-step.json.*) exit 1 ;; esac' "exec $(command -v mktemp) \"\$@\"" > "$TMP/shim/mktemp"
  chmod +x "$TMP/shim/mktemp"
  out=$(PATH="$TMP/shim:$PATH" bash "$STEP" review docs/plan.md 5 2>"$TMP/err"); rc=$?
  check "review: a step state that cannot be written fails" "$rc:$(grep -c 'cannot update' "$TMP/err")" "2:1"
  step review docs/plan.md 5
  echo w > w5.txt && git add w5.txt && git commit -qm "feat: add w5"
  out=$(PATH="$TMP/shim:$PATH" bash "$STEP" review docs/plan.md 5 2>"$TMP/err"); rc=$?
  check "review: a review head that cannot be recorded fails" "$rc:$(grep -c 'cannot update' "$TMP/err")" "2:1"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
