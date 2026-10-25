#!/usr/bin/env bash
# Acceptance tests for the task-loop steps spec
# (docs/dforge/specs/2026-10-26-task-loop-steps-design.md), statements
# A1-A11, A14 and A15. Each test is written from the statement's text and
# reaches the behaviour through the scripts and documents the spec names. The
# cockpit statements (A12, A13) are in task-loop-steps.acceptance.test.ts.
# Usage:
#   bash task-loop-steps.acceptance.test.sh           run every test
#   bash task-loop-steps.acceptance.test.sh A5 A9     run the named tests only
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
S="$PLUGIN/scripts"
STEP="$S/task-step"
SUITE="$S/suite-run"
INFLIGHT="$S/in-flight"
ROUTE="$S/review-route"
LROUTE="$S/lens-route"
TURNEND="$S/turn-end.sh"
TURNSTART="$S/turn-start.sh"

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
matches() { # matches <name> <haystack> <ERE>
  if grep -qE -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       no match: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
absent() { # absent <name> <haystack> <ERE>
  if grep -qE -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected match: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude"
unset CLAUDE_CONFIG_DIR CODEX_HOME AR_SESSION DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_PROJECT_DIR
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1 MSYS_NO_PATHCONV=1
export DR_CODEX_SESSION_DIR="$TMP/codex-sessions" CLAUDE_CODE_SESSION_ID=acceptance-session
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-gate usable=true reason= review=true lane=false resets_at=- source=cache"' > "$TMP/gate-stub"
export TASK_STEP_CODEX_GATE="$TMP/gate-stub"

review_surface() { # review_surface <true|false|absent> — what this session's Codex gate file says
  rm -rf "$DR_CODEX_SESSION_DIR"
  [ "$1" != absent ] || return 0
  mkdir -p "$DR_CODEX_SESSION_DIR"
  printf '{"session_id":"%s","usable":true,"review":%s,"lane":false}\n' "$CLAUDE_CODE_SESSION_ID" "$1" > "$DR_CODEX_SESSION_DIR/$CLAUDE_CODE_SESSION_ID.json"
}

CO="Co-Authored""-By"
CS="Claude""-Session"
GW="Generated"" with"

short() { git -C "$R" rev-parse --short=7 "$1"; }
full() { git -C "$R" rev-parse "$1"; }
ts() { out=$(cd "$R" && bash "$STEP" "$@" 2>"$TMP/err"); rc=$?; err=$(cat "$TMP/err"); }
count_lines() { printf '%s\n' "$1" | grep -c .; }
commit_file() { # commit_file <file> <content> <message>
  printf '%s\n' "$2" > "$R/$1"
  git -C "$R" add "$1" && git -C "$R" commit -qm "$3"
}
ws_files() { ls -A "$WS" 2>/dev/null | sort | tr '\n' ' '; }
prompt_path() { # prompt_path <file> — the first .diff path a prompt names
  grep -oE '[^ ]+\.diff' "$1" | head -n 1
}

PLAN_TEXT='|# Acceptance Fixture Plan
|
|**Goal:** Fixture.
|
|**Execution:** subagent — `claude --model sonnet --effort high` — fixture
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
|2. risky
|3. nolens
|
|### Task 1: plain
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|**Lenses:** lang-bash
|
|Body one.
|
|### Task 2: risky
|
|**Files:**
|- Modify: `app.txt`
|
|**Implementer:** dforge:impl-opus-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 3 = 6
|
|### Task 3: nolens
|
|**Files:**
|- Modify: `other.txt`
|
|**Implementer:** dforge:impl-sonnet-medium
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 1 = 2'

CODEX_PLAN_TEXT='|# Codex Fixture
|
|**Host:** codex
|
|### Task 1: only
|
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0'

new_repo() { # new_repo <name> — a throwaway repository with the fixture plans; sets R and WS
  R="$TMP/$1"
  git init -q "$R"
  git -C "$R" config user.name Darkraise
  git -C "$R" config user.email dark@example.invalid
  mkdir -p "$R/docs"
  sed 's/^|//' <<<"$PLAN_TEXT" > "$R/docs/plan.md"
  sed 's/^|//' <<<"$CODEX_PLAN_TEXT" > "$R/docs/codex-plan.md"
  seq 1 10 | sed 's/^/line /' > "$R/app.txt"
  cp "$R/app.txt" "$R/other.txt"
  cp "$R/app.txt" "$R/test.txt"
  git -C "$R" add -A && git -C "$R" commit -qm "docs: add fixtures"
  WS=$(cd "$R" && bash "$S/sdd-workspace" docs/plan.md)
  review_surface absent
}

# --- A1 ----------------------------------------------------------------------

a1() {
  new_repo a1
  local base7
  base7=$(short HEAD)
  ts start docs/plan.md 1
  check "A1: start exits 0" "$rc" "0"
  check "A1: the ledger's last line is the assigned line" "$(tail -n 1 "$WS/progress.md")" "Task 1: implementer impl-sonnet-low (assigned; base $base7)"
  local D="$WS/task-1-dispatch.md"
  check "A1: the dispatch file exists" "$([ -f "$D" ] && echo yes || echo no)" "yes"
  has "A1: the dispatch names the brief path" "$(cat "$D")" "$WS/task-1-brief.md"
  has "A1: the dispatch names the report path" "$(cat "$D")" "$WS/task-1-report.md"
  has "A1: the dispatch carries the expanded plugin root" "$(cat "$D")" "$PLUGIN/scripts/suite-run"
  absent "A1: the dispatch has no unexpanded placeholder" "$(cat "$D")" '\[[A-Z][A-Z_]+\]'
  check "A1: the digest is at most 15 lines" "$([ "$(count_lines "$out")" -le 15 ] && echo yes || echo no)" "yes"
  has "A1: the digest prints the subagent_type" "$out" "dforge:impl-sonnet-low"
  has "A1: the digest prints the dispatch path" "$out" "$D"
  matches "A1: the digest's last line is the budget line" "$(tail -n 1 <<<"$out")" '^budget'
  has "A1: the line before it records the state (base)" "$(tail -n 2 <<<"$out" | head -n 1)" "$base7"
}

# --- A2 ----------------------------------------------------------------------

a2() {
  new_repo a2
  ts start docs/plan.md 1
  commit_file a.txt a "feat: add a"
  review_surface absent
  ts review docs/plan.md 1
  local JP="$WS/task-1-review-prompt.md"
  check "A2: review exits 0" "$rc" "0"
  check "A2: the judge prompt exists" "$([ -f "$JP" ] && echo yes || echo no)" "yes"
  absent "A2: the judge prompt has no unexpanded placeholder" "$(cat "$JP")" '\[[A-Z][A-Z_]+\]'
  local lens_paths route primary
  lens_paths=$(cd "$R" && bash "$LROUTE" docs/plan.md --task 1 | sed -n 's/^lens [^ ]* criteria=\(.*\)$/\1/p')
  check "A2: the fixture task has a lens" "$([ -n "$lens_paths" ] && echo yes || echo no)" "yes"
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    has "A2: the judge prompt names the lens criteria path $(basename "$p")" "$(cat "$JP")" "$p"
  done <<<"$lens_paths"
  route=$(cd "$R" && bash "$ROUTE" docs/plan.md --task 1)
  primary=$(sed -n 's/.*primary=\([^ ]*\).*/\1/p' <<<"$route")
  check "A2: review-route prints a Claude judge seat with Codex off" "$primary" "dforge:judge-sonnet-high"
  has "A2: the digest names the seat review-route prints" "$out" "$primary"
  local nchecks
  nchecks=$(grep -cE '^check [A-Za-z_-]+: ' <<<"$out")
  check "A2: the digest prints at least two check lines" "$([ "$nchecks" -ge 2 ] && echo yes || echo no)" "yes"
  absent "A2: no Second Pass section below risk 3" "$(cat "$JP")" 'Second Pass'

  # A task whose lens-route prints none has no lens section.
  ts start docs/plan.md 3
  ts review docs/plan.md 3
  check "A2: lens-route prints no lens for task 3" "$(cd "$R" && bash "$LROUTE" docs/plan.md --task 3 | grep -c '^lens ')" "0"
  absent "A2: and the judge prompt has no lens section" "$(cat "$WS/task-3-review-prompt.md")" '[Ll]ens'
  absent "A2: and no unexpanded placeholder" "$(cat "$WS/task-3-review-prompt.md")" '\[[A-Z][A-Z_]+\]'

  # A Codex seat: the Codex prompt and the runner command.
  review_surface true
  ts review docs/plan.md 1
  route=$(cd "$R" && bash "$ROUTE" docs/plan.md --task 1)
  primary=$(sed -n 's/.*primary=\([^ ]*\).*/\1/p' <<<"$route")
  has "A2: the Codex route's primary is a Codex seat" "$primary" "codex"
  has "A2: the digest names the Codex seat" "$out" "$primary"
  local runner cprompt
  runner=$(grep 'run-codex-review.sh' <<<"$out" | head -n 1)
  check "A2: the digest prints the runner command" "$([ -n "$runner" ] && echo yes || echo no)" "yes"
  cprompt=$(sed -n 's/.*--prompt "\{0,1\}\([^" ]*\)"\{0,1\}.*/\1/p' <<<"$runner")
  check "A2: the runner command names an existing Codex prompt" "$([ -n "$cprompt" ] && [ -f "$cprompt" ] && echo yes || echo no)" "yes"
  absent "A2: the Codex prompt has no unexpanded placeholder" "$(cat "$cprompt" 2>/dev/null)" '\[[A-Z][A-Z_]+\]'
  check "A2: the judge prompt is still written beside a Codex seat" "$([ -f "$JP" ] && echo yes || echo no)" "yes"
  absent "A2: and has no Second Pass section below risk 3" "$(cat "$JP")" 'Second Pass'

  # Risk 3: the judge prompt carries the Second Pass section.
  ts start docs/plan.md 2
  commit_file b.txt b "feat: add b"
  ts review docs/plan.md 2
  has "A2: a risk-3 judge prompt carries the Second Pass section" "$(cat "$WS/task-2-review-prompt.md")" "Second Pass"
  absent "A2: the risk-3 judge prompt has no unexpanded placeholder" "$(cat "$WS/task-2-review-prompt.md")" '\[[A-Z][A-Z_]+\]'
  review_surface absent
}

# --- A3 ----------------------------------------------------------------------

a3() {
  new_repo a3
  local before
  before=$(ws_files)
  ts review docs/plan.md 1
  check "A3: review before start exits 6" "$rc" "6"
  check "A3: and writes nothing" "$(ws_files)" "$before"

  ts start docs/plan.md 1
  before=$(ws_files)
  ts rereview docs/plan.md 1
  check "A3: rereview before review exits 6" "$rc" "6"
  check "A3: and writes nothing" "$(ws_files)" "$before"

  local CWS sub
  CWS=$(cd "$R" && bash "$S/sdd-workspace" docs/codex-plan.md)
  rm -rf "$CWS"
  for sub in start review rereview; do
    ts "$sub" docs/codex-plan.md 1
    check "A3: $sub on a Host: codex plan exits 2" "$rc" "2"
    check "A3: $sub on a Host: codex plan writes nothing" "$([ -d "$CWS" ] && ls -A "$CWS" | grep -c . || echo 0)" "0"
  done
}

# --- A4 ----------------------------------------------------------------------

a4() {
  new_repo a4
  ts start docs/plan.md 1
  local base c1 c2
  base=$(full HEAD)
  commit_file a.txt a "feat: add a"
  c1=$(full HEAD)
  commit_file b.txt b "feat: add b"
  c2=$(full HEAD)
  git -C "$R" branch taskref "$c1"

  ts review docs/plan.md 1 --head taskref
  check "A4: review --head exits 0" "$rc" "0"
  local JP="$WS/task-1-review-prompt.md" diff
  diff=$(prompt_path "$JP")
  check "A4: the judge prompt names a diff file" "$([ -n "$diff" ] && [ -f "$diff" ] && echo yes || echo no)" "yes"
  has "A4: --head packages base..REF: the task ref's file is in" "$(cat "$diff")" "a.txt"
  lacks "A4: --head packages base..REF: a later commit's file is out" "$(cat "$diff")" "b.txt"
  has "A4: the digest's state shows the REF's commit as the review head" "$out" "${c1:0:7}"
  has "A4: the state file records REF" "$(cat "$WS/task-1-step.json")" "taskref"

  # --base on review: the package starts at SHA and not at the recorded base.
  ts review docs/plan.md 1 --head "$c2" --base "$c1"
  check "A4: review --base exits 0" "$rc" "0"
  diff=$(prompt_path "$JP")
  has "A4: --base on review: the package holds the commit after SHA" "$(cat "$diff")" "b.txt"
  lacks "A4: --base on review: the package leaves out the commit before SHA" "$(cat "$diff")" "a.txt"
  lacks "A4: the package does not start at the recorded base" "$(cat "$diff")" "${base:0:7}..none"

  # --base on rereview: the same, from the fix base.
  new_repo a4r
  ts start docs/plan.md 1
  commit_file a.txt a "feat: add a"
  ts review docs/plan.md 1
  local f1 f2
  commit_file other.txt fix1 "fix: first"
  f1=$(full HEAD)
  commit_file test.txt fix2 "fix: second"
  f2=$(full HEAD)
  printf '%s\n\nFixed.\n' '- app.txt: a finding' > "$WS/task-1-fix-1.md"
  local state_bak="$TMP/a4-state.json"
  cp "$WS/task-1-step.json" "$state_bak"
  local pre post newp
  pre=$(ls "$WS" | sort)
  ts rereview docs/plan.md 1 --base "$f1"
  check "A4: rereview --base exits 0" "$rc" "0"
  post=$(ls "$WS" | sort)
  newp=$(comm -13 <(printf '%s\n' "$pre") <(printf '%s\n' "$post") | grep -i 'prompt' | head -n 1)
  check "A4: rereview wrote a prompt" "$([ -n "$newp" ] && echo yes || echo no)" "yes"
  diff=$(prompt_path "$WS/$newp")
  check "A4: the re-review prompt names a diff file" "$([ -n "$diff" ] && [ -f "$diff" ] && echo yes || echo no)" "yes"
  has "A4: --base on rereview: the package holds the commit after SHA" "$(cat "$diff")" "test.txt"
  lacks "A4: --base on rereview: the package leaves out the commit up to SHA" "$(cat "$diff")" "other.txt"

  cp "$state_bak" "$WS/task-1-step.json"
  rm -f "$WS/$newp"
  ts rereview docs/plan.md 1
  newp=$(comm -13 <(printf '%s\n' "$pre") <(ls "$WS" | sort) | grep -i 'prompt' | head -n 1)
  diff=$(prompt_path "$WS/$newp")
  has "A4: without --base the package starts at the recorded review head" "$(cat "$diff")" "other.txt"

  # start --wave K ends the assigned line.
  new_repo a4w
  ts start docs/plan.md 2 --wave 3
  matches "A4: start --wave 3 ends the assigned line" "$(tail -n 1 "$WS/progress.md")" '^Task 2: implementer impl-opus-high \(assigned; base [0-9a-f]{7}; wave 3\)$'
}

# --- A5, A6 -----------------------------------------------------------------

# The repository for the skip rule: tasks 1 (risk 1) and 2 (risk 3) started and
# reviewed at one head, with their states saved.
rr_setup() { # rr_setup <repo name>
  new_repo "$1"
  ts start docs/plan.md 1; ts start docs/plan.md 2
  commit_file work.txt work "feat: work"
  ts review docs/plan.md 1
  ts review docs/plan.md 2
  RR0=$(full HEAD)
  cp "$WS/task-1-step.json" "$TMP/rr-state1.json"
  cp "$WS/task-2-step.json" "$TMP/rr-state2.json"
  RR_N=0
}
rr_edit() { # rr_edit <file> <add1|add2|add3|add4|mod> — change a fixture file
  local f="$R/$1"
  RR_N=$((RR_N + 1))
  case $2 in
    add1) printf 'x%s\n' "$RR_N" >> "$f" ;;
    add2) printf 'x%s\ny\n' "$RR_N" >> "$f" ;;
    add3) printf 'x%s\ny\nz\n' "$RR_N" >> "$f" ;;
    add4) printf 'x%s\ny\nz\nw\n' "$RR_N" >> "$f" ;;
    mod) awk -v n="$RR_N" 'NR == 2 { print "changed " n; next } { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f" ;;
  esac
}
# rr_case <name> <task> <flags> <bullets|separated> <edits file:kind ...> -- <want skip|prompt>
rr_case() {
  local name=$1 task=$2 flags=$3 bullets=$4 e want pre post newp skipline
  shift 4
  local edits=()
  while [ "$1" != "--" ]; do edits+=("$1"); shift; done
  shift
  want=$1
  git -C "$R" reset -q --hard "$RR0"
  rm -f "$WS"/task-*-fix-*.md
  find "$WS" -name 'task-*prompt*' ! -name '*review-prompt.md' -delete 2>/dev/null
  cp "$TMP/rr-state1.json" "$WS/task-1-step.json"
  cp "$TMP/rr-state2.json" "$WS/task-2-step.json"
  for e in "${edits[@]}"; do rr_edit "${e%%:*}" "${e#*:}"; done
  git -C "$R" add -A && git -C "$R" commit -qm "fix: round"
  { printf '%s\n' "$bullets" | tr '|' '\n'; printf '\nFixed.\n'; } > "$WS/task-$task-fix-1.md"
  pre=$(ls "$WS" | sort)
  # shellcheck disable=SC2086
  ts rereview docs/plan.md "$task" $flags
  post=$(ls "$WS" | sort)
  newp=$(comm -13 <(printf '%s\n' "$pre") <(printf '%s\n' "$post") | grep -i 'prompt' | head -n 1)
  skipline=$(grep '^re-review: skipped' <<<"$out")
  if [ "$want" = skip ]; then
    check "$name: exit 0" "$rc" "0"
    matches "$name: prints the skip line" "$skipline" '^re-review: skipped \([0-9]+ changed lines, 1 finding, app\.txt\)$'
    check "$name: writes no prompt" "${newp:-none}" "none"
  else
    check "$name: exit 0" "$rc" "0"
    check "$name: no skip line" "${skipline:-none}" "none"
    check "$name: writes a re-review prompt" "$([ -n "$newp" ] && echo yes || echo no)" "yes"
    has "$name: names dforge:judge-sonnet-high" "$out" "dforge:judge-sonnet-high"
  fi
}

a5() {
  rr_setup rr5
  rr_case "A5: one line in the finding's file, covered" 1 --covered '- app.txt: one' app.txt:add1 -- skip
  rr_case "A5: three changed lines is the limit" 1 --covered '- app.txt: one' app.txt:add3 -- skip
  rr_case "A5: three changed lines across the finding's file and a test file" 1 --covered '- app.txt: one' app.txt:add1 test.txt:add2 -- skip
  rr_case "A5: four changed lines are over the limit" 1 --covered '- app.txt: one' app.txt:add4 -- prompt
  rr_case "A5: test-file lines count toward the limit" 1 --covered '- app.txt: one' app.txt:add1 test.txt:add3 -- prompt
  rr_case "A5: a replaced line counts as two changed lines, four over three" 1 --covered '- app.txt: one' app.txt:mod app.txt:add2 -- prompt
  rr_case "A5: without --covered" 1 "" '- app.txt: one' app.txt:add1 -- prompt
  rr_case "A5: a risk-3 task" 2 --covered '- app.txt: one' app.txt:add1 -- prompt
}

a6() {
  rr_setup rr6
  rr_case "A6: a fix that edits only a test file other than the finding's" 1 --covered '- app.txt: one' test.txt:add1 -- prompt
  rr_case "A6: a fix that edits only another source file" 1 --covered '- app.txt: one' other.txt:add1 -- prompt
  rr_case "A6: two open findings, a tiny fix in one finding's file" 1 --covered '- app.txt: one|- other.txt: two' app.txt:add1 -- prompt
  rr_case "A6: two open findings, a fix touching both files" 1 --covered '- app.txt: one|- other.txt: two' app.txt:add1 other.txt:add1 -- prompt
}

# --- A7 ----------------------------------------------------------------------

a7() {
  new_repo a7
  local want got
  route_primary() { (cd "$R" && bash "$ROUTE" docs/plan.md --ruling "$@" 2>&1) | sed -n 's/.*primary=\([^ ]*\).*/\1/p'; }
  local SON=dforge:judge-sonnet-high OPU=dforge:judge-opus
  check "A7: cannot-verify, a risk-1 task" "$(route_primary cannot-verify 1)" "$SON"
  check "A7: executor-empty-diff, a risk-1 task" "$(route_primary executor-empty-diff 1)" "$SON"
  check "A7: both Sonnet kinds, a risk-1 task" "$(route_primary cannot-verify,executor-empty-diff 1)" "$SON"
  check "A7: cannot-verify over two risk-below-3 tasks" "$(route_primary cannot-verify 1 3)" "$SON"
  check "A7: cannot-verify, a risk-3 task" "$(route_primary cannot-verify 2)" "$OPU"
  check "A7: executor-empty-diff, a risk-3 task" "$(route_primary executor-empty-diff 2)" "$OPU"
  check "A7: cannot-verify over a risk-1 and a risk-3 task" "$(route_primary cannot-verify 1 2)" "$OPU"
  local kind
  for kind in preflight plan-conflict breaker blocked-plan final-residual acceptance-ambiguous; do
    check "A7: $kind" "$(route_primary "$kind" 1)" "$OPU"
  done
  check "A7: a mixed list, Sonnet kind first" "$(route_primary cannot-verify,breaker 1)" "$OPU"
  check "A7: a mixed list, Opus kind first" "$(route_primary breaker,cannot-verify 1)" "$OPU"
  check "A7: a mixed list of three" "$(route_primary cannot-verify,executor-empty-diff,preflight 1)" "$OPU"
}

# --- A8 ----------------------------------------------------------------------

# check_case <name> — start, run the offending commit by the caller, review, print check lines
a8_case() { # a8_case <name> <commit-fn> <expect clean|dirty>
  new_repo "a8-$1"
  ts start docs/plan.md 1
  "$2"
  local sha7
  sha7=$(short HEAD)
  ts review docs/plan.md 1
  local checks bad
  checks=$(grep '^check ' <<<"$out")
  bad=$(grep -v ': clean$' <<<"$checks")
  if [ "$3" = clean ]; then
    check "A8: $1: review exits 0" "$rc" "0"
    check "A8: $1: no check reports a finding" "${bad:-none}" "none"
    check "A8: $1: at least two check lines print clean" "$([ "$(grep -c ': clean$' <<<"$checks")" -ge 2 ] && echo yes || echo no)" "yes"
  else
    check "A8: $1: a check reports a finding" "$([ -n "$bad" ] && echo yes || echo no)" "yes"
    has "A8: $1: it names the offending commit" "$bad" "$sha7"
    check "A8: $1: another check line still prints clean" "$([ "$(grep -c ': clean$' <<<"$checks")" -ge 1 ] && echo yes || echo no)" "yes"
  fi
}
c_clean() { commit_file a.txt a "feat: add a"; }
c_author() { printf 'a\n' > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -q --author="Other <other@example.invalid>" -m "feat: add a"; }
c_committer() { printf 'a\n' > "$R/a.txt"; git -C "$R" add a.txt; GIT_COMMITTER_NAME=Other GIT_COMMITTER_EMAIL=other@example.invalid git -C "$R" commit -q -m "feat: add a"; }
c_email() { printf 'a\n' > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -q --author="Darkraise <elsewhere@example.invalid>" -m "feat: add a"; }
c_coauthor() { printf 'a\n' > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -q -m "feat: add a" -m "$CO: X <x@example.invalid>"; }
c_session() { printf 'a\n' > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -q -m "feat: add a" -m "$CS: abc123"; }
c_generated() { printf 'a\n' > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -q -m "feat: add a" -m "$GW a tool"; }

a8() {
  a8_case clean c_clean clean
  a8_case "a different author name" c_author dirty
  a8_case "a different committer" c_committer dirty
  a8_case "a different author email" c_email dirty
  a8_case "a co-author trailer" c_coauthor dirty
  a8_case "a session trailer" c_session dirty
  a8_case "a generated-with line" c_generated dirty
}

# --- A9, A10 ----------------------------------------------------------------

sr() { out=$(cd "$R" && bash "$SUITE" "$@" 2>&1); rc=$?; }
runs() { # runs <counter file> — how many times the command ran
  if [ -f "$1" ]; then grep -c . "$1"; else echo 0; fi
}

a9() {
  new_repo a9
  local N="$TMP/a9-counter" M="$TMP/a9-counter-other"
  : > "$N"; : > "$M"
  local cmd=(bash -c "echo run >> '$N'; exit 0")
  local other=(bash -c "echo run >> '$M'; exit 0")
  sr -- "${cmd[@]}"
  check "A9: a first run exits 0" "$rc" "0"
  check "A9: a first run runs the command" "$(runs "$N")" "1"
  local state row
  state=$(cd "$R" && bash "$S/dforge-path" state | tr -d '\r')
  row=$(tail -n 1 "$state/suites.tsv" 2>/dev/null)
  check "A9: the run is recorded with HEAD" "$(cut -f1 <<<"$row")" "$(full HEAD)"
  check "A9: the run is recorded clean" "$(cut -f2 <<<"$row")" "clean"
  check "A9: the run is recorded with exit 0" "$(cut -f4 <<<"$row")" "0"

  sr -- "${cmd[@]}"
  check "A9: the same HEAD, clean, the same command: exits 0" "$rc" "0"
  has "A9: and reports a reuse" "$out" "suite: reused pass at $(short HEAD)"
  check "A9: and does not run the command" "$(runs "$N")" "1"

  sr -- "${other[@]}"
  check "A9: a different command runs" "$(runs "$M")" "1"
  sr -- "${other[@]}"
  check "A9: and is reused on its own record" "$(runs "$M")" "1"

  commit_file a.txt a "feat: move head"
  sr -- "${cmd[@]}"
  check "A9: a new HEAD runs the command" "$(runs "$N")" "2"
  lacks "A9: and reports no reuse" "$out" "reused"
  sr -- "${cmd[@]}"
  check "A9: the new HEAD's pass is then reused" "$(runs "$N")" "2"

  # A dirty tree then: never reuses.
  commit_file b.txt b "feat: move head again"
  printf 'dirty\n' > "$R/untracked.txt"
  sr -- "${cmd[@]}"
  check "A9: a dirty tree runs" "$(runs "$N")" "3"
  sr -- "${cmd[@]}"
  check "A9: a dirty tree runs again, never reusing" "$(runs "$N")" "4"
  rm -f "$R/untracked.txt"
  sr -- "${cmd[@]}"
  check "A9: a clean tree after dirty runs only did not find a reusable row" "$(runs "$N")" "5"
  sr -- "${cmd[@]}"
  check "A9: and the clean run is then reused" "$(runs "$N")" "5"

  # A command that dirties the tree: its row is not reusable even when the tree is clean later.
  commit_file c.txt c "feat: move head a third time"
  local D="$TMP/a9-counter-dirtying"
  : > "$D"
  local dirtier=(bash -c "echo run >> '$D'; echo x > '$R/stray.txt'; exit 0")
  sr -- "${dirtier[@]}"
  check "A9: a command that dirties the tree runs" "$(runs "$D")" "1"
  rm -f "$R/stray.txt"
  sr -- "${dirtier[@]}"
  check "A9: its row, dirty when it ended, is not reused on a clean tree" "$(runs "$D")" "2"
  rm -f "$R/stray.txt"

  # A failing command is never reused.
  local F="$TMP/a9-counter-fail"
  : > "$F"
  local failing=(bash -c "echo run >> '$F'; echo not ok 1 - broken; exit 1")
  sr -- "${failing[@]}"
  check "A9: a failing command exits non-zero" "$([ "$rc" -ne 0 ] && echo yes || echo no)" "yes"
  sr -- "${failing[@]}"
  check "A9: a failing command runs again at the same HEAD" "$(runs "$F")" "2"
}

a10() {
  new_repo a10
  local noisy=(bash -c 'i=1; while [ $i -le 40 ]; do echo "noise line $i"; i=$((i + 1)); done; exit 3')
  sr -- "${noisy[@]}"
  check "A10: a failing command with no failing-line pattern exits non-zero" "$([ "$rc" -ne 0 ] && echo yes || echo no)" "yes"
  check "A10: and exits with the command's own code" "$rc" "3"
  has "A10: the output holds the log's last line" "$out" "noise line 40"
  has "A10: the output holds the 30th line from the end" "$out" "noise line 11"
  absent "A10: the output stops at 30 lines: line 10 is out" "$out" 'noise line 10$'
  absent "A10: the failure is not reported as a pass" "$out" 'suite: pass|reused'

  local silent=(bash -c 'exit 2')
  sr -- "${silent[@]}"
  check "A10: a failing command that prints nothing exits non-zero" "$rc" "2"
  check "A10: and the digest is not empty" "$([ -n "$out" ] && echo yes || echo no)" "yes"
  has "A10: and says it failed" "$out" "FAIL"

  local fewer=(bash -c 'echo only one line of noise; exit 4')
  sr -- "${fewer[@]}"
  check "A10: a log shorter than 30 lines is printed whole" "$(grep -c 'only one line of noise' <<<"$out")" "1"
  check "A10: and exits with the command's code" "$rc" "4"

  local tap=(bash -c 'echo "ok 1 - good"; echo "not ok 2 - bad thing"; echo "chatter after"; exit 1')
  sr -- "${tap[@]}"
  has "A10: a matching failing line is printed" "$out" "not ok 2 - bad thing"
  absent "A10: and the 30-line tail is not needed then" "$out" 'last 30 lines'

  sr --timeout 1 -- bash -c 'sleep 30'
  check "A10: a command past its timeout exits 124" "$rc" "124"
}

# --- A11 ---------------------------------------------------------------------

fjq() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' jq "$@"; }

a11() {
  local SID=s-flight TP="$TMP/s-flight.jsonl" ENV_SID
  ENV_SID=$CLAUDE_CODE_SESSION_ID
  export CLAUDE_CODE_SESSION_ID=$SID
  mkdir -p "$HOME/.claude/dforge/sessions/by-id" "$TMP/$SID/subagents"
  jq -n --arg tp "$TP" '{session_id:"s-flight",transcript_path:$tp}' > "$HOME/.claude/dforge/sessions/by-id/$SID.json"
  : > "$TP"
  use() { # use <tool_use_id> <description>
    fjq -nc --arg id "$1" --arg d "$2" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:$id,name:"Agent",input:{description:$d}}]}}' >> "$TP"
  }
  result_at() { # result_at <tool_use_id> <iso timestamp> <text>
    fjq -nc --arg id "$1" --arg ts "$2" --arg t "$3" '{type:"user",timestamp:$ts,message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:$t}]}}' >> "$TP"
  }
  ago() { touch -d "$1 minutes ago" "$2"; }

  # A shell: the file its result names.
  use toolu_sh 'Run the suite'
  result_at toolu_sh 2026-10-26T08:05:00.000Z "Command running in background with ID: b11. Output is being written to: $TMP/b11.output. You will be notified when it completes."
  : > "$TMP/b11.output"; ago 47 "$TMP/b11.output"
  # An agent whose result names an output_file.
  use toolu_a1 'Implement task 4'
  result_at toolu_a1 2026-10-26T09:30:00.000Z "$(printf 'Async agent launched successfully.\nagentId: a11 (internal ID)\noutput_file: %s/a11.output\nDo NOT Read or tail this file.' "$TMP")"
  : > "$TMP/a11.output"; ago 12 "$TMP/a11.output"
  # An agent with no output_file: its subagent transcript.
  use toolu_a2 'Review task 4'
  result_at toolu_a2 2026-10-26T10:15:00.000Z $'Async agent launched successfully.\nagentId: a12 (internal ID)'
  : > "$TMP/$SID/subagents/agent-a12.jsonl"; ago 9 "$TMP/$SID/subagents/agent-a12.jsonl"
  # An agent with neither.
  use toolu_a3 'Review task 5'
  result_at toolu_a3 2026-10-26T11:40:00.000Z $'Async agent launched successfully.\nagentId: a13 (internal ID)'

  local out code
  out=$(TZ=UTC0 bash "$INFLIGHT"); code=$?
  check "A11: running launches: exit 1" "$code" "1"
  matches "A11: a shell: start time and idle minutes from the file its result names" "$out" '^- shell b11 08:05 idle (46|47|48)m Run the suite$'
  matches "A11: an agent: start time and idle minutes from its output_file" "$out" '^- agent a11 09:30 idle (11|12|13)m Implement task 4$'
  matches "A11: an agent with no output_file: idle minutes from its subagent transcript" "$out" '^- agent a12 10:15 idle (8|9|10)m Review task 4$'
  matches "A11: an agent with neither: idle -" "$out" '^- agent a13 11:40 idle - Review task 5$'

  # turn-end.sh still counts and names the launches.
  local REPO="$TMP/a11-repo" WS2
  git init -q "$REPO"
  WS2="$REPO/.dforge/sdd/2026-10-08-example"
  mkdir -p "$WS2"
  jq -n --arg sid s-turn --arg cwd "$REPO" '{hook_event_name:"UserPromptSubmit",session_id:$sid,cwd:$cwd,prompt:"go"}' | bash "$TURNSTART"
  sleep 1
  printf '# SDD ledger — plan: docs/superpowers/plans/2026-10-08-example.md\nTask 1: dispatched\n' > "$WS2/progress.md"
  local msg=$'Stopping here.\n\n## Next session\n\n**Status:** x' hold reason
  hold=$(jq -n --arg sid s-turn --arg cwd "$REPO" --arg msg "$msg" --arg tp "$TP" \
    '{hook_event_name:"Stop",session_id:$sid,cwd:$cwd,transcript_path:$tp,stop_hook_active:false,last_assistant_message:$msg}' | bash "$TURNEND")
  reason=$(jq -r '.reason // ""' <<<"$hold")
  check "A11: turn-end.sh holds a next-step block over running launches" "$(jq -r '.decision // "none"' <<<"$hold")" "block"
  has "A11: turn-end.sh counts the launches" "$reason" "4 background launch"
  has "A11: turn-end.sh names the shell by id" "$reason" "b11"
  has "A11: turn-end.sh names the shell by description" "$reason" "Run the suite"
  has "A11: turn-end.sh names an agent by id" "$reason" "a11"
  has "A11: turn-end.sh names an agent by description" "$reason" "Implement task 4"
  export CLAUDE_CODE_SESSION_ID=$ENV_SID
}

# --- A14 ---------------------------------------------------------------------

a14() {
  local SKILL="$PLUGIN/skills/subagent-driven-development/SKILL.md"
  local CODEX="$PLUGIN/skills/using-dforge/references/codex-tools.md"
  local skill codex
  skill=$(cat "$SKILL")
  codex=$(cat "$CODEX")
  matches "A14: the skill tells a session to end the turn when only waiting remains" "$skill" '[Ee]nd the turn'
  matches "A14: and says it for the case where waiting is all that remains" "$skill" '[Oo]nly waiting remains|nothing left but waiting'
  absent "A14: the skill no longer carries the 290-second sleep wait" "$skill" 'sleep 29[0-9]'
  absent "A14: nor the stretch-over marker" "$skill" 'stretch-over'
  local lines
  lines=$(grep -nE 'Monitor|sleep' "$SKILL")
  check "A14: every mention of Monitor or sleep in the skill is a prohibition" \
    "$(grep -vE '[Nn]ever|[Nn]ot |[Nn]o longer|[Ii]nstead of|without' <<<"$lines" | grep -c .)" "0"
  absent "A14: the skill does not prescribe a Monitor call" "$skill" '(Run|Use|Call|Dispatch|Launch|Start|run|use|call|launch|start) (a |the )?`?Monitor'
  matches "A14: codex-tools.md keeps wait_agent" "$codex" 'wait_agent'
  matches "A14: codex-tools.md keeps bounded stretches" "$codex" 'bounded stretches'
}

# --- A15 ---------------------------------------------------------------------

a15() {
  local RRP="$PLUGIN/skills/subagent-driven-development/references/re-review-prompt.md" text
  text=$(cat "$RRP")
  has "A15: the re-review prompt names dforge:judge-sonnet-high" "$text" "dforge:judge-sonnet-high"
  has "A15: and dforge:judge-opus for a subtle concurrency fix" "$text" "dforge:judge-opus for a subtle concurrency fix"
  absent "A15: it names no general-purpose seat" "$text" 'general-purpose'
  absent "A15: it carries no model argument line" "$text" '^[ ]*model:'
  matches "A15: it requires the diff file" "$text" 'DIFF_FILE.*(REQUIRED|mandatory|required)'
  absent "A15: it carries no git diff fallback" "$text" 'git (diff|show|log)'
  absent "A15: it carries no fallback wording" "$text" '[Ff]all ?back|[Ii]f no diff file|[Ii]f the diff file is (missing|absent)'
  local DT="$PLUGIN/reference/delegated-task.md" row
  row=$(grep -E '^\| Scoped re-review' "$DT")
  absent "A15: delegated-task.md's Scoped re-review row names no general-purpose seat" "$row" 'general-purpose'
  has "A15: and names dforge:judge-sonnet-high" "$row" "dforge:judge-sonnet-high"
  local seats seats_rc
  seats=$(cd "$PLUGIN" && env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash tests/seats.test.sh 2>&1); seats_rc=$?
  check "A15: tests/seats.test.sh exits 0" "$seats_rc" "0"
  absent "A15: tests/seats.test.sh has no failing line" "$seats" '^FAIL'
  matches "A15: tests/seats.test.sh reports no failure count" "$seats" ' 0 failed$'
}

ALL="a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a14 a15"
if [ $# -gt 0 ]; then
  sel=""
  for n in "$@"; do sel="$sel $(tr 'A-Z' 'a-z' <<<"$n")"; done
else
  sel=$ALL
fi
for t in $sel; do "$t"; done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
