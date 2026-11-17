#!/usr/bin/env bash
# Acceptance tests for the speed-and-cost-followups spec
# (docs/dforge/specs/2026-10-28-speed-and-cost-followups-design.md), the
# plugin-side statements A1 to A4, A7, A8, A11 and A13 to A15 (A19 went with
# draft-pack). A5 is the `A5:` describe block in
# cockpit.test.ts. Each test is
# written from the statement's text and reaches the behaviour through the
# scripts the spec names (task-step, impl-stop-gate), the files the
# plugin ships, or, for a statement about text, the text itself.
# Usage:
#   bash speed-and-cost-followups.acceptance.test.sh            run every test
#   bash speed-and-cost-followups.acceptance.test.sh A3 A9      run the named tests only
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../plugins/dforge" && pwd)"
REPO_ROOT="$(cd "$PLUGIN/../.." && pwd)"
S="$PLUGIN/scripts"
STEP="$S/task-step"
SUITE="$S/suite-run"
GATE="$S/impl-stop-gate"
ONLY=" $* "

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n' "$1" "$3"; fail=$((fail + 1)); fi
}
selected() { [ "$ONLY" = "  " ] || [[ "$ONLY" == *" $1 "* ]]; }

TMP="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
export WORKFLOW_GUARD_CLAUDE_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_MANAGED_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_PROJECT_DIR="$TMP/workflow-guard"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude"
unset CLAUDE_CONFIG_DIR CODEX_HOME AR_SESSION DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_PROJECT_DIR XDG_STATE_HOME
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL TASK_STEP_BASE_TIMEOUT SUITE_RUN_KILL_AFTER
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1 MSYS_NO_PATHCONV=1
export DR_CODEX_SESSION_DIR="$TMP/codex-sessions" CLAUDE_CODE_SESSION_ID=followups-acceptance
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-gate usable=true reason= review=true resets_at=- source=cache"' > "$TMP/gate-stub"
export TASK_STEP_CODEX_GATE="$TMP/gate-stub"

winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
init_repo() { git init -q "$1"; git -C "$1" config user.name t; git -C "$1" config user.email t@example.invalid; }
g() { git -C "$REPO" "$@"; }
commit_all() { g add -A && g commit -qm "$1"; }
TIMEOUT_BIN=$(command -v timeout)
ts() { # ts <args...> — task-step in $REPO; sets out, err, rc
  out=$(cd "$REPO" && "$TIMEOUT_BIN" "${TS_LIMIT:-300}" bash "$STEP" "$@" 2>"$TMP/err"); rc=$?
  out=${out//$'\r'/}
  err=$(tr -d '\r' < "$TMP/err")
}
workspace() { winpath "$(cd "$REPO" && bash "$S/sdd-workspace" "$1")"; }
sr() { (cd "$REPO" && bash "$SUITE" -- bash -c "$1" >/dev/null 2>&1); } # the controller's own suite run, recorded for the head
worktrees() { g worktree list | wc -l | tr -d ' '; }

mkplan() { # mkplan <ntasks> [header line] [task 1 extra text]
  printf '# Fixture Plan\n\n**Goal:** Fixture.\n\n**Execution:** inline — `claude --model sonnet --effort high` — fixture\n\n'
  [ -z "${2:-}" ] || printf '%s\n\n' "$2"
  printf '## Task index\n\n'
  local i
  for ((i = 1; i <= $1; i++)); do printf '%d. Task %d\n' "$i" "$i"; done
  for ((i = 1; i <= $1; i++)); do
    printf '\n### Task %d: Task %d\n\n**Files:**\n- Modify: `app.txt`\n\n**Implementer:** dforge:impl-sonnet-high\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n' "$i" "$i"
    if [ "$i" -eq 1 ] && [ -n "${3:-}" ]; then printf '\n%s\n' "$3"; fi
  done
}
cv_report() { # cv_report <file> <item>... — a single-task review report whose Cannot verify section holds the items
  local f=$1; shift
  {
    printf '## Verdict\nspec: cannot-verify\nquality: approved\nscores: spec 15 / scope 17 / verification 12 / quality 16\n\n## Strengths\nFine.\n\n## Findings\n\n## Cannot verify\n'
    printf '%s\n' "$@"
    printf '\n## Assessment\nFine.\n'
  } > "$f"
}
clean_report() { # clean_report <file>
  printf '## Verdict\nspec: pass\nquality: approved\nscores: spec 17 / scope 17 / verification 16 / quality 16\n\n## Strengths\nFine.\n\n## Findings\n\n## Cannot verify\n\n## Assessment\nFine.\n' > "$1"
}
digest_cv() { grep '^cannot-verify: ' <<<"$out"; }
ledger_settled() { grep -c 'settled by task-step check baseline' "$1" 2>/dev/null || true; }

# ------------------------------------------------------- fixture for A1 to A4
if selected A1 || selected A2 || selected A3 || selected A4; then
  REPO="$TMP/s1"; init_repo "$REPO"; mkdir -p "$REPO/docs" "$REPO/lib"
  MARK="$TMP/s1-marks"; mkdir -p "$MARK" "$TMP/s1-sr"; export MARK_DIR="$MARK"
  sed 's/^|//' > "$REPO/docs/plan.md" <<'PLAN'
|# Named Commands Plan
|
|**Goal:** Fixture.
|
|**Execution:** inline — `claude --model sonnet --effort high` — fixture
|
|**Integration check:** `bash mark.sh a2integ 0`
|
|## Task index
|
|1. One
|
|### Task 1: One
|
|**Files:**
|- Modify: `lib/new.sh`
|
|**Implementer:** dforge:impl-sonnet-high
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|Run: `bash mark.sh a1first 0` and then `bash mark.sh a3second 0`
|Run: `test -f base-only.txt`
|**Check:** `bash mark.sh a2check 0` prints nothing.
|Run: `bash mark.sh a4timeout 124`
|
|```bash
|bash mark.sh a3fenced 0
|```
PLAN
  printf '#!/usr/bin/env bash\n: > "$MARK_DIR/$1"\nexit "${2:-0}"\n' > "$REPO/mark.sh"
  echo old > "$REPO/lib/new.sh"; echo present > "$REPO/base-only.txt"
  commit_all base
  ts start docs/plan.md 1 --suite 'bash mark.sh a2suite 0'
  WS=$(workspace docs/plan.md); LEDGER="$WS/progress.md"
  g rm -q base-only.txt; echo work > "$REPO/lib/new.sh"; commit_all work
  (cd "$REPO" && MARK_DIR="$TMP/s1-sr" bash "$SUITE" -- bash -c 'bash mark.sh a2suite 0' >/dev/null 2>&1)
  ts review docs/plan.md 1
  check "setup: review exits 0" "$rc" "0"

  cv_report "$WS/task-1-review-report.md" \
    "- cannot-verify: baseline bash mark.sh a1first 0, expect pass — first span of a Run line" \
    "- cannot-verify: baseline test -f base-only.txt, expect pass — the file exists only at the base" \
    "- cannot-verify: baseline   bash mark.sh a2check 0  , expect pass — the first span of a Check line, padded with spaces" \
    "- cannot-verify: baseline "$'\t'"bash mark.sh a2integ 0"$'\t'", expect pass — the Integration check, padded with tabs" \
    "- cannot-verify: baseline bash mark.sh a2suite 0, expect pass — the recorded suite command" \
    "- cannot-verify: baseline bash mark.sh a4timeout 124, expect pass — a plan-named command that exits 124"
  ts verdict docs/plan.md 1
  check "A1: verdict exits 0" "$rc" "0"
  check "A1: the first span of a Run line is run" "$([ -e "$MARK/a1first" ] && echo ran || echo not-run)" "ran"
  check "A1: it is run at the base commit (a file only the base holds)" "$(grep -cxF "Task 1: Ruling: cannot-verify — settled by task-step check baseline — exit 0, log $WS/task-1-baseline-2.log" "$LEDGER")" "1"
  check "A1: the first span is settled in the ledger" "$(grep -cxF "Task 1: Ruling: cannot-verify — settled by task-step check baseline — exit 0, log $WS/task-1-baseline-1.log" "$LEDGER")" "1"
  check "A2: the Check line's span is run" "$([ -e "$MARK/a2check" ] && echo ran || echo not-run)" "ran"
  check "A2: the Integration check is run" "$([ -e "$MARK/a2integ" ] && echo ran || echo not-run)" "ran"
  check "A2: the recorded suite command is run" "$([ -e "$MARK/a2suite" ] && echo ran || echo not-run)" "ran"
  check "A2: each of the three is settled in the ledger" "$(grep -cxE "Task 1: Ruling: cannot-verify — settled by task-step check baseline — exit 0, log $WS/task-1-baseline-[345].log" "$LEDGER")" "3"
  check "A2: five items in all are settled" "$(ledger_settled "$LEDGER")" "5"
  check "A4: a plan-named command that times out stays for the seat, without the label" "$(digest_cv)" \
    "cannot-verify: baseline bash mark.sh a4timeout 124, expect pass — a plan-named command that exits 124"
  check "A4: it is run, and settles nothing and adds no finding" "$([ -e "$MARK/a4timeout" ] && echo ran || echo not-run) $(grep '^findings: ' <<<"$out")" "ran findings: 0 Critical, 0 Important, 0 Minor"

  before=$(wc -l < "$LEDGER" | tr -d ' ')
  cv_report "$WS/task-1-review-report.md" \
    "- cannot-verify: baseline bash mark.sh a3nowhere 0, expect pass — a command found nowhere in the plan" \
    "- cannot-verify: baseline bash mark.sh a1first 0; bash mark.sh a3append 0, expect pass — a named command with more after it" \
    "- cannot-verify: baseline bash mark.sh a3fenced 0, expect pass — a trimmed line of a fenced block" \
    "- cannot-verify: baseline bash mark.sh a3second 0, expect pass — the second code span of a Run line"
  rm -f "$MARK"/*
  ts verdict docs/plan.md 1
  check "A3: verdict exits 0" "$rc" "0"
  check "A3: none of the four commands is run (no marker file, not even the named one it contains)" "$(ls "$MARK" | tr '\n' ' ')" ""
  check "A3: each stays a cannot-verify line ending with the label" \
    "$(digest_cv | grep -c ' (command not named in the plan)$') $(digest_cv | wc -l | tr -d ' ')" "4 4"
  check "A3: no ledger line is added" "$(wc -l < "$LEDGER" | tr -d ' ')" "$before"
  check "A3: and no finding" "$(grep '^findings: ' <<<"$out")" "findings: 0 Critical, 0 Important, 0 Minor"
  check "A3: no temporary worktree is left" "$(worktrees)" "1"
fi

# ------------------------------------------------------------------ A7
if selected A7; then
  REPO="$TMP/s7"; init_repo "$REPO"; mkdir -p "$REPO/docs"
  export SETUP_MARK="$TMP/s7-setup-runs" SUITE_MARK="$TMP/s7-suite-runs"
  mkplan 2 '**Worktree setup:** `echo ran >> "$SETUP_MARK"; exec sleep 60`' 'Run: `bash check.sh`' > "$REPO/docs/plan.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$REPO/check.sh"
  printf '#!/usr/bin/env bash\nif [ -f broken.txt ]; then echo "not ok 1 - tc01"; exit 1; fi\nexit 0\n' > "$REPO/suite.sh"
  echo 0 > "$REPO/app.txt"
  commit_all base
  mkdir -p "$TMP/s7-shim"
  real_timeout=$(command -v timeout)
  # Shrinks a bound of 100 s or more to 1 s, so the 600 s bound of a baseline item can be reached.
  cat > "$TMP/s7-shim/timeout" <<SHIM
#!/usr/bin/env bash
args=("\$@"); i=0
while [[ "\${args[\$i]}" == -* ]]; do case "\${args[\$i]}" in -k|-s) i=\$((i + 2)) ;; *) i=\$((i + 1)) ;; esac; done
if [[ "\${args[\$i]}" =~ ^[0-9]+\$ ]] && [ "\${args[\$i]}" -ge 100 ]; then args[\$i]=1; fi
exec "$real_timeout" "\${args[@]}"
SHIM
  chmod +x "$TMP/s7-shim/timeout"
  # PATH takes the POSIX form: TMP's C:/… splits at its drive letter's colon.
  SHIM_PATH=$TMP/s7-shim
  if command -v cygpath >/dev/null 2>&1; then SHIM_PATH=$(cygpath -u "$SHIM_PATH"); fi

  # a baseline item whose setup runs past the bound
  ts start docs/plan.md 1
  WS=$(workspace docs/plan.md)
  echo 1 >> "$REPO/app.txt"; commit_all work1
  ts review docs/plan.md 1
  cv_report "$WS/task-1-review-report.md" "- cannot-verify: baseline bash check.sh, expect pass — does the check pass at the base"
  start=$(date +%s)
  PATH="$SHIM_PATH:$PATH" SUITE_RUN_KILL_AFTER=1 TS_LIMIT=100 ts verdict docs/plan.md 1
  took=$(( $(date +%s) - start ))
  check "A7: a setup that sleeps past the bound does not hang a baseline item's verdict" "$rc $([ "$took" -lt 60 ] && echo prompt || echo slow)" "0 prompt"
  check "A7: the item goes to the seat, without the not-named label" "$(digest_cv)" "cannot-verify: baseline bash check.sh, expect pass — does the check pass at the base"
  check "A7: the setup log of the baseline run exists" "$([ -e "$WS/task-1-baseline-1.log.setup.log" ] && echo yes || echo no)" "yes"
  check "A7: no temporary worktree is left (baseline item)" "$(worktrees)" "1"
  check "A7: the setup ran once" "$(grep -c . "$SETUP_MARK")" "1"

  # the suite's base run
  ts start docs/plan.md 2 --suite 'bash suite.sh'
  : > "$REPO/broken.txt"; echo 2 >> "$REPO/app.txt"; commit_all work2
  sr 'bash suite.sh'
  ts review docs/plan.md 2
  clean_report "$WS/task-2-review-report.md"
  runs0=$(grep -c . "$SETUP_MARK")
  start=$(date +%s)
  TASK_STEP_BASE_TIMEOUT=1 SUITE_RUN_KILL_AFTER=1 TS_LIMIT=100 ts verdict docs/plan.md 2
  took=$(( $(date +%s) - start ))
  check "A7: a setup that sleeps past the bound does not hang the suite's verdict" "$rc $([ "$took" -lt 60 ] && echo prompt || echo slow)" "0 prompt"
  check "A7: the setup ran once, and the suite's new failure is not excused" "$(( $(grep -c . "$SETUP_MARK") - runs0 )) $(grep '^suite: ' <<<"$out")" "1 suite: red (1 failing, 0 baseline)"
  check "A7: a setup log exists beside the base log" "$(ls "$WS" | grep -c '^task-2-base.*setup\.log$')" "1"
  check "A7: the timeout is recorded for the task" "$([ -e "$WS/task-2-base-timeout" ] && echo marker || echo none)" "marker"
  TASK_STEP_BASE_TIMEOUT=1 SUITE_RUN_KILL_AFTER=1 TS_LIMIT=100 ts verdict docs/plan.md 2
  check "A7: a second verdict does not run the setup again" "$(( $(grep -c . "$SETUP_MARK") - runs0 )) $rc" "1 0"
  check "A7: no temporary worktree is left (suite)" "$(worktrees)" "1"
fi

# ---------------------------------------------------------------- A8, A11
if selected A8 || selected A11; then
  REPO="$TMP/s8"; init_repo "$REPO"; mkdir -p "$REPO/docs"
  mkplan 2 > "$REPO/docs/plan.md"
  printf '#!/usr/bin/env bash\nif [ -f broken.txt ]; then for i in $(seq -w 1 25); do echo "not ok $i - tc$i"; done; exit 1; fi\nexit 0\n' > "$REPO/suite.sh"
  echo 0 > "$REPO/app.txt"
  commit_all base
  ts start docs/plan.md 1 --suite 'bash suite.sh'
  WS=$(workspace docs/plan.md); LEDGER="$WS/progress.md"
  : > "$REPO/broken.txt"; commit_all "break 25 tests"
  sr 'bash suite.sh'
  ts review docs/plan.md 1
  clean_report "$WS/task-1-review-report.md"
  ts verdict docs/plan.md 1
  FIX="$WS/task-1-fix-1.md"
  names=0; for i in $(seq -w 1 25); do grep -qF "tc$i" "$FIX" 2>/dev/null && names=$((names + 1)); done
  check "A8: the digest counts 25 Important and no baseline" "$(grep '^suite: red' <<<"$out") | $(grep '^findings: ' <<<"$out")" \
    "suite: red (25 failing, 0 baseline) | findings: 0 Critical, 25 Important, 0 Minor"
  check "A8: the fix file names all 25 failing tests" "$names" "25"
  check "A8: the digest shows 20 of the findings" "$(grep -c '^Important ' <<<"$out")" "20"
  check "A8: and the line for the other five" "$(grep '^suite: .*more' <<<"$out")" "suite: 5 more failing lines in $FIX"
  check "A8: the digest names the fix file" "$(grep '^fix: ' <<<"$out" | cut -d' ' -f1-2)" "fix: $FIX"

  # A11: a symbol only a binary file holds
  ts start docs/plan.md 2
  printf 'only_in_blob\0\0' > "$REPO/blob.bin"; echo 'text_symbol_zz lives here' > "$REPO/notes.txt"
  commit_all "a binary file and a text file"
  ts review docs/plan.md 2
  cv_report "$WS/task-2-review-report.md" \
    "- cannot-verify: exists only_in_blob at head, expect present — named in the brief" \
    "- cannot-verify: exists text_symbol_zz at head, expect present — named in the brief"
  ts verdict docs/plan.md 2
  check "A11: a symbol only a binary file holds settles as a mismatch (absent)" "$(grep '^Important ' <<<"$out")" \
    "Important 2 cannot-verify:0 — exists only_in_blob at head, expect present — got absent"
  check "A11: it is not logged as settled, and a text hit still settles" \
    "$(grep -c 'blob.bin' "$LEDGER") $(grep -cxE 'Task 2: Ruling: cannot-verify — settled by task-step check exists — notes.txt:1' "$LEDGER")" "0 1"
fi

# ---------------------------------------------------- A13, A14, A15 (gate)
gate_setup() {
  GREPO="$TMP/gate-repo"; init_repo "$GREPO"
  GSTATE=$(cd "$GREPO" && bash "$S/dforge-path" state | tr -d '\r')
  FALLBACK="$HOME/.local/state/dforge/impl-stop-gate.log"
  RPT="$TMP/gate-reports"; mkdir -p "$RPT"
  printf '## Verdict\npass: 3\n' > "$RPT/full.md"
  printf '# Report\n\n## Verdict\npass: 3\n' > "$RPT/no-verdict.md"
  printf '\n\n## Verdict\npass: 3\n' > "$RPT/blank-first.md"
  printf 'pass: 3\n\n## Verdict\n' > "$RPT/verdict-late.md"
}
gate() { # gate <agent id> <message> [cwd] — sets GRC and GERR
  local json
  json=$(jq -nc --arg i "$1" --arg m "$2" --arg c "${3:-$GREPO}" '{session_id:"s",cwd:$c,hook_event_name:"SubagentStop",stop_hook_active:false,agent_id:$i,agent_type:"dforge:impl-sonnet-high",last_assistant_message:$m}')
  timeout 30 bash "$GATE" <<<"$json" >"$TMP/gout" 2>"$TMP/gerr"; GRC=$?
  GERR=$(tr -d '\r' < "$TMP/gerr")
}
plain_msg() { printf 'Here is my update.\nReport: %s' "$1"; }
fallback_size() { if [ -f "$FALLBACK" ]; then wc -c < "$FALLBACK" | tr -d ' '; else echo 0; fi; }

if selected A13 || selected A14 || selected A15; then gate_setup; fi

if selected A13; then
  gate a13-x "$(plain_msg "$TMP/none.md")"
  check "A13: the first reply whose report file is missing is blocked" "$GRC" "2"
  gate a13-x "$(plain_msg "$RPT/no-verdict.md")"
  check "A13: a retry whose report does not open with ## Verdict exits 2" "$GRC" "2"
  has "A13: and says what is missing" "$GERR" "## Verdict"
  gate a13-y "$(plain_msg "$TMP/none.md")"
  gate a13-y "$(plain_msg "$RPT/full.md")"
  check "A13: the same retry with a report that opens with ## Verdict exits 0" "$GRC" "0"
fi

if selected A14; then
  gate a14-a "$(plain_msg "$TMP/none.md")"
  gate a14-a 'Status: blocked - waiting on a decision'
  check "A14: a retry with no Report: line after a block exits 0" "$GRC" "0"

  gate a14-c "$(plain_msg "$TMP/none.md")"
  gate a14-c "$(plain_msg "$RPT/full.md")"
  rc1=$GRC
  gate a14-c 'Here is my update.'
  check "A14: a reply with no Report: line after a block and a passing report exits 0" "$rc1 $GRC" "0 0"

  size0=$(fallback_size)
  gate a14-e 'Here is my update.'
  check "A14: a reply with no Report: line from an agent never blocked exits 0" "$GRC" "0"
  gate a14-f 'Here is my update.' "$TMP/no/such/dir"
  check "A14: also from a directory that cannot be entered" "$GRC" "0"
  check "A14: neither adds a line to the fallback log" "$(fallback_size)" "$size0"
fi

if selected A15; then
  gate a15-a "$(plain_msg "$RPT/verdict-late.md")"
  check "A15: a report whose ## Verdict follows another first line is blocked" "$GRC" "2"
  gate a15-b "$(plain_msg "$RPT/blank-first.md")"
  check "A15: blank lines before ## Verdict pass" "$GRC" "0"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
