#!/usr/bin/env bash
# Acceptance tests for the speed-and-cost-followups spec
# (docs/dforge/specs/2026-10-28-speed-and-cost-followups-design.md), the
# plugin-side statements A1 to A4 and A6 to A16, A19 to A21 and the fast part
# of A23. A5 is the `A5:` describe block in cockpit.test.ts; A17 and A18 are in
# evals/tiers/tests/speed-and-cost-followups.acceptance.test.mjs. Each test is
# written from the statement's text and reaches the behaviour through the
# scripts the spec names (task-step, impl-stop-gate, draft-pack), the files the
# plugin ships, or, for a statement about text, the text itself.
# Usage:
#   bash speed-and-cost-followups.acceptance.test.sh            run every test
#   bash speed-and-cost-followups.acceptance.test.sh A3 A9      run the named tests only
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN/../.." && pwd)"
S="$PLUGIN/scripts"
STEP="$S/task-step"
SUITE="$S/suite-run"
GATE="$S/impl-stop-gate"
DP="$S/draft-pack"
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
matches() { # matches <name> <haystack> <ERE> — case-insensitive
  if grep -qiE -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       no match: [%s]\n' "$1" "$3"; fail=$((fail + 1)); fi
}
selected() { [ "$ONLY" = "  " ] || [[ "$ONLY" == *" $1 "* ]]; }

TMP="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude"
unset CLAUDE_CONFIG_DIR CODEX_HOME AR_SESSION DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_PROJECT_DIR XDG_STATE_HOME
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL TASK_STEP_BASE_TIMEOUT SUITE_RUN_KILL_AFTER
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1 MSYS_NO_PATHCONV=1
export DR_CODEX_SESSION_DIR="$TMP/codex-sessions" CLAUDE_CODE_SESSION_ID=followups-acceptance
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-gate usable=true reason= review=true lane=false resets_at=- source=cache"' > "$TMP/gate-stub"
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
  printf '# Fixture Plan\n\n**Goal:** Fixture.\n\n**Execution:** subagent — `claude --model sonnet --effort high` — fixture\n\n'
  [ -z "${2:-}" ] || printf '%s\n\n' "$2"
  printf '## Task index\n\n'
  local i
  for ((i = 1; i <= $1; i++)); do printf '%d. Task %d\n' "$i" "$i"; done
  for ((i = 1; i <= $1; i++)); do
    printf '\n### Task %d: Task %d\n\n**Files:**\n- Modify: `app.txt`\n\n**Implementer:** dforge:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n' "$i" "$i"
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
|**Execution:** subagent — `claude --model sonnet --effort high` — fixture
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
|**Implementer:** dforge:impl-sonnet-low
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

# ---------------------------------------------------------------- A9, A10
build_group() { # build_group <dir> — a repository with tasks 1 and 2 held and group-reviewed at one head, and the group's report written
  REPO="$1"; init_repo "$REPO"; mkdir -p "$REPO/docs"
  mkplan 3 > "$REPO/docs/plan.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$REPO/suite.sh"
  echo 0 > "$REPO/app.txt"
  commit_all base
  B0=$(g rev-parse HEAD | tr -d '\r')
  local n t
  for n in 1 2; do
    ts start docs/plan.md "$n" --suite 'bash suite.sh'
    echo "w$n" >> "$REPO/app.txt"; commit_all "work $n"
    ts hold docs/plan.md "$n"
  done
  WS=$(workspace docs/plan.md)
  sr 'bash suite.sh'
  ts review --group docs/plan.md 1 2
  check "setup: group review exits 0" "$rc" "0"
  {
    printf '## Verdict\n'
    for t in 1 2; do printf 'Task %s spec: pass\nTask %s quality: approved\nTask %s scores: spec 17 / scope 17 / verification 17 / quality 17\n' "$t" "$t" "$t"; done
  } > "$WS/group-1,2-review-report.md"
}

if selected A9; then
  build_group "$TMP/s9"
  printf -- '- app.txt: wrong value\n\nFixed.\n' > "$WS/task-2-fix-1.md"
  echo fix >> "$REPO/app.txt"; commit_all "fix 2"
  cp "$WS/task-2-step.json" "$TMP/step2.before"
  base_before=$(jq -r '.base' "$WS/task-2-step.json" | tr -d '\r')
  ts rereview docs/plan.md 2 --base "$B0"
  check "A9: rereview --base on a sequential group member exits 2" "$rc" "2"
  check "A9: the step file's base is unchanged" "$(jq -r '.base' "$WS/task-2-step.json" | tr -d '\r') $(cmp -s "$TMP/step2.before" "$WS/task-2-step.json" && echo same || echo changed)" "$base_before same"

  PREV=$B0
  ts start docs/plan.md 3 --wave 1
  echo w3 >> "$REPO/app.txt"; commit_all "work 3"; g branch t3ref
  ts review docs/plan.md 3 --head t3ref
  printf -- '- app.txt: wrong value\n\nFixed.\n' > "$WS/task-3-fix-1.md"
  echo fix3 >> "$REPO/app.txt"; commit_all "fix 3"; g branch -f t3ref HEAD
  ts rereview docs/plan.md 3 --base "$PREV"
  check "A9: on a wave task with a head ref --base is accepted and recorded" "$rc $(jq -r '.base' "$WS/task-3-step.json" | tr -d '\r')" "0 $PREV"

fi

if selected A10; then
  build_group "$TMP/s10"
  cp "$WS/task-2-step.json" "$TMP/step2.keep"
  rm -f "$WS/task-2-step.json"
  ts verdict docs/plan.md 1 2 --group
  check "A10: a missing last member's step file exits 6 naming the file" "$rc $(grep -cF "$WS/task-2-step.json" <<<"$err")" "6 1"
  check "A10: and prints no 'suite: none recorded'" "$(grep -c 'suite: none recorded' <<<"$out")" "0"
  printf '{not json\n' > "$WS/task-2-step.json"
  ts verdict docs/plan.md 1 2 --group
  check "A10: a last member's step file that is not valid JSON exits 6 naming the file" "$rc $(grep -cF "$WS/task-2-step.json" <<<"$err")" "6 1"
  check "A10: and prints no 'suite: none recorded' either" "$(grep -c 'suite: none recorded' <<<"$out")" "0"
  cp "$TMP/step2.keep" "$WS/task-2-step.json"
  ts verdict docs/plan.md 1 2 --group
  check "A10: with the file back the same verdict reads the recorded suite" "$rc $(grep -c '^suite: pass' <<<"$out")" "0 1"
fi

# ------------------------------------------------------------------ A12
if selected A12; then
  BT="$HERE/task-step-base.test.sh"; ST="$HERE/task-step-settle.test.sh"
  check "A12: task-step-base.test.sh has a verdict --cwd case" "$(grep -cE 'verdict .*--cwd' "$BT" | awk '{ print ($1 >= 1) ? "yes" : "no" }')" "yes"
  check "A12: and a base row that timed out (exit 124)" "$(grep -cE 'exit 124|sr_timeout|--timeout 1' "$BT" | awk '{ print ($1 >= 1) ? "yes" : "no" }')" "yes"
  check "A12: and a passing base row (no base run)" "$(grep -ciE 'passing (suites.tsv )?(base )?row|0 baseline' "$BT" | awk '{ print ($1 >= 1) ? "yes" : "no" }')" "yes"
  check "A12: task-step-settle.test.sh has a ./<name> exists item run from a subdirectory" \
    "$(grep -cE 'exists \./[A-Za-z_.]+ at head, expect present' "$ST" | awk '{ print ($1 >= 1) ? "yes" : "no" }') $(grep -cE '\(cd "\$REPO/[a-z]+" && .*task-step' "$ST" | awk '{ print ($1 >= 1) ? "yes" : "no" }')" "yes yes"
  out=$(cd "$HERE" && timeout 900 bash "$BT" 2>&1); rc=$?
  check "A12: task-step-base.test.sh passes" "$rc $(grep -c '^FAIL' <<<"$out")" "0 0"
  out=$(cd "$HERE" && timeout 600 bash "$ST" 2>&1); rc=$?
  check "A12: task-step-settle.test.sh passes" "$rc $(grep -c '^FAIL' <<<"$out")" "0 0"
fi

# ------------------------------------------------------------------ A6
if selected A6; then
  doc() { tr -d '\r' < "$1" | tr '\n' ' ' | tr -s ' '; }
  TRP=$(doc "$PLUGIN/skills/subagent-driven-development/references/task-reviewer-prompt.md")
  DT=$(doc "$PLUGIN/reference/delegated-task.md")
  matches "A6: task-reviewer-prompt.md says baseline runs only a command the plan names" "$TRP" 'baseline.{0,300}runs only.{0,60}plan names'
  matches "A6: delegated-task.md says a baseline command runs only when the plan names it" "$DT" 'baseline. command runs only when the plan names it'
  matches "A6: delegated-task.md says a plan-named command runs unsandboxed" "$DT" 'plan-named command.{0,80}unsandboxed'
  matches "A6: delegated-task.md says review seats write only their report files" "$DT" 'review seats can write only their report files'
  check "A6: delegated-suite.test.sh pins the baseline, unsandboxed and report-file sentences" \
    "$(grep -c 'runs only when the plan names it' "$HERE/delegated-suite.test.sh") $(grep -c 'unsandboxed' "$HERE/delegated-suite.test.sh") $(grep -c 'write only their report files' "$HERE/delegated-suite.test.sh")" "1 1 1"
  check "A6: task-step-text.test.sh pins the reviewer prompt's baseline sentence" \
    "$(grep -cE 'names_flat .*(TRP|task-reviewer-prompt).*plan names' "$HERE/task-step-text.test.sh" | awk '{ print ($1 >= 1) ? "yes" : "no" }')" "yes"
fi

# ---------------------------------------------------- A13, A14, A15 (gate)
gate_setup() {
  GREPO="$TMP/gate-repo"; init_repo "$GREPO"
  GSTATE=$(cd "$GREPO" && bash "$S/dforge-path" state | tr -d '\r')
  FALLBACK="$HOME/.local/state/dforge/impl-stop-gate.log"
  RPT="$TMP/gate-reports"; mkdir -p "$RPT"
  printf '# Report\n\n## Verified\n- `bash t.sh` — pass: 3 passed, 0 failed\n\n## Discovered issues (not fixed)\nNone.\n\n## Assumptions made\nNone.\n' > "$RPT/full.md"
  printf '# Report\n\n## Discovered issues (not fixed)\nNone.\n\n## Assumptions made\nNone.\n' > "$RPT/no-verified.md"
  printf '# Report\n\n**Status:** BLOCKED\n\nNeed a decision.\n' > "$RPT/blocked.md"
  printf '# Report\n\n## Verified\n- `bash t.sh` — pass: 3 passed, 0 failed\n\n## Verified\nnothing yet\n\n## Discovered issues (not fixed)\nNone.\n\n## Assumptions made\nNone.\n' > "$RPT/two-first-valid.md"
  printf '# Report\n\n## Verified\nnothing yet\n\n## Verified\n- `bash t.sh` — pass: 3 passed, 0 failed\n\n## Discovered issues (not fixed)\nNone.\n\n## Assumptions made\nNone.\n' > "$RPT/two-last-valid.md"
}
gate() { # gate <agent id> <message> [cwd] — sets GRC and GERR
  local json
  json=$(jq -nc --arg i "$1" --arg m "$2" --arg c "${3:-$GREPO}" '{session_id:"s",cwd:$c,hook_event_name:"SubagentStop",stop_hook_active:false,agent_id:$i,agent_type:"dforge:impl-sonnet-high",last_assistant_message:$m}')
  timeout 30 bash "$GATE" <<<"$json" >"$TMP/gout" 2>"$TMP/gerr"; GRC=$?
  GERR=$(tr -d '\r' < "$TMP/gerr")
}
done_msg() { printf '**Status:** DONE\nReport: %s' "$1"; }
plain_msg() { printf 'Here is my update.\nReport: %s' "$1"; }
fallback_size() { if [ -f "$FALLBACK" ]; then wc -c < "$FALLBACK" | tr -d ' '; else echo 0; fi; }

if selected A13 || selected A14 || selected A15; then gate_setup; fi

if selected A13; then
  gate a13-x "$(done_msg "$TMP/none.md")"
  check "A13: the first DONE with no report file is blocked" "$GRC" "2"
  gate a13-x "$(plain_msg "$RPT/no-verified.md")"
  check "A13: a status-less retry whose report still lacks ## Verified exits 2" "$GRC" "2"
  has "A13: and says what is missing" "$GERR" "## Verified"
  gate a13-y "$(done_msg "$TMP/none.md")"
  gate a13-y "$(plain_msg "$RPT/full.md")"
  check "A13: the same retry with a complete report exits 0" "$GRC" "0"
fi

if selected A14; then
  gate a14-a "$(done_msg "$TMP/none.md")"
  gate a14-a "$(printf 'Status: blocked - waiting on a decision\nReport: %s' "$RPT/no-verified.md")"
  check "A14: a retry whose text says 'Status: blocked' exits 0" "$GRC" "0"

  gate a14-b "$(done_msg "$TMP/none.md")"
  gate a14-b "$(plain_msg "$RPT/blocked.md")"
  check "A14: a status-less retry whose report's first status line is BLOCKED exits 0" "$GRC" "0"

  gate a14-c "$(done_msg "$TMP/none.md")"
  gate a14-c "$(done_msg "$RPT/full.md")"
  rc1=$GRC
  gate a14-c "$(plain_msg "$TMP/none.md")"
  check "A14: a status-less reply after a block followed by a complete DONE exits 0" "$rc1 $GRC" "0 0"

  gate a14-d "$(done_msg "$TMP/none.md")"
  gate a14-d "$(printf '**Status:** BLOCKED\nReport: %s' "$TMP/none.md")"
  rc1=$GRC
  gate a14-d "$(plain_msg "$TMP/none.md")"
  check "A14: a status-less reply after a block followed by a BLOCKED status exits 0" "$rc1 $GRC" "0 0"

  size0=$(fallback_size)
  gate a14-e "$(plain_msg "$TMP/none.md")"
  check "A14: a status-less reply from an agent never blocked exits 0" "$GRC" "0"
  gate a14-f "$(plain_msg "$TMP/none.md")" "$TMP/no/such/dir"
  check "A14: also from a directory that cannot be entered" "$GRC" "0"
  check "A14: neither adds a line to the fallback log" "$(fallback_size)" "$size0"
fi

if selected A15; then
  gate a15-a "$(done_msg "$RPT/two-first-valid.md")"
  check "A15: two ## Verified sections, the last holding no bullet, is blocked" "$GRC" "2"
  gate a15-b "$(done_msg "$RPT/two-last-valid.md")"
  check "A15: with the valid bullet in the last section it passes" "$GRC" "0"
fi

# ------------------------------------------------------------------ A16
if selected A16; then
  mkdir -p "$TMP/xdg-host"
  out=$(cd "$HERE" && XDG_STATE_HOME="$TMP/xdg-host" timeout 300 bash "$HERE/impl-stop-gate.test.sh" 2>&1); rc=$?
  check "A16: impl-stop-gate.test.sh passes with XDG_STATE_HOME set in the calling environment" "$rc $(grep -c '^FAIL' <<<"$out")" "0 0"
  check "A16: and writes nothing under it" "$(find "$TMP/xdg-host" -mindepth 1 | wc -l | tr -d ' ')" "0"
fi

# ------------------------------------------------------------------ A19
if selected A19; then
  REPO="$TMP/dp"; init_repo "$REPO"; mkdir -p "$REPO/docs"
  printf '# Demo Implementation Plan\n\n## Task index\n\n1. Step 1\n2. Step 2\n\n---\n' > "$REPO/docs/plan.md"
  DST=$(cd "$REPO" && bash "$S/dforge-path" state | tr -d '\r')
  mkdir -p "$DST/drafts/plan"
  printf '### Task 1: Step 1\n\nBody 1.\n' > "$DST/drafts/plan/tasks-1-1.md"
  printf '### Task 2: Step 2\n\nBody 2.\n' > "$DST/drafts/plan/tasks-2-2.md"
  out=$(cd "$REPO" && timeout 60 bash "$DP" --join docs/plan.md 2>&1); rc=$?
  check "A19: draft-pack joins the slices" "$rc $(grep -c '^### Task' "$REPO/docs/plan.md")" "0 2"
  check "A19: the plan's drafts directory is gone" "$([ -e "$DST/drafts/plan" ] && echo present || echo gone)" "gone"
  check "A19: and the emptied drafts directory too" "$([ -e "$DST/drafts" ] && echo present || echo gone)" "gone"

  printf '# Other Plan\n\n## Task index\n\n1. Step 1\n\n---\n' > "$REPO/docs/other.md"
  mkdir -p "$DST/drafts/other" "$DST/drafts/elsewhere"
  printf '### Task 1: Step 1\n\nBody.\n' > "$DST/drafts/other/tasks-1-1.md"
  printf 'keep\n' > "$DST/drafts/elsewhere/tasks-1-1.md"
  (cd "$REPO" && timeout 60 bash "$DP" --join docs/other.md >/dev/null 2>&1)
  check "A19: a drafts directory that still holds another plan's slices stays" "$([ -e "$DST/drafts/other" ] && echo present || echo gone) $([ -f "$DST/drafts/elsewhere/tasks-1-1.md" ] && echo kept || echo lost)" "gone kept"
fi

# ------------------------------------------------------------------ A20
if selected A20; then
  SK="$PLUGIN/skills"
  check "A20: process-graph.md has no ./references/ label" "$(grep -c '\./references/' "$SK/subagent-driven-development/references/process-graph.md")" "0"
  for f in "$SK/subagent-driven-development/SKILL.md" "$SK/executing-plans/SKILL.md" "$SK/subagent-driven-development/references/setup.md" "$SK/executing-plans/references/setup.md"; do
    check "A20: ${f#"$PLUGIN/"} points at ledger.md or recovery.md for the Recovery table" "$(grep -i 'recovery' "$f" | grep -cE '(ledger|recovery)\.md' | awk '{ print ($1 >= 1) ? "yes" : "no" }')" "yes"
  done
  check "A20: writing-plans/SKILL.md names design-phase.md" "$(grep -c 'design-phase\.md' "$SK/writing-plans/SKILL.md" | awk '{ print ($1 >= 1) ? "yes" : "no" }')" "yes"
  out=$(cd "$HERE" && timeout 120 bash "$HERE/skill-split-planning.test.sh" 2>&1); rc=$?
  check "A20: skill-split-planning.test.sh passes and reports no broken link" "$rc $(grep -c '^FAIL' <<<"$out") $(grep -i 'broken' <<<"$out" | grep -vc '^ok ')" "0 0 0"
  check "A20: no SD= line in the two review-depth acceptance tests" \
    "$(grep -cE '^[[:space:]]*SD=' "$HERE/review-depth.acceptance.test.sh") $(grep -cE '^[[:space:]]*SD=' "$HERE/review-depth-qa.acceptance.test.sh")" "0 0"

  COPY="$TMP/plugin-copy"; mkdir -p "$COPY/tests"
  cp -R "$PLUGIN/agents" "$COPY/agents"
  cp "$HERE/impl-clauses.test.sh" "$COPY/tests/impl-clauses.test.sh"
  out=$(cd "$COPY/tests" && timeout 60 bash impl-clauses.test.sh 2>&1); rc=$?
  check "A20: impl-clauses.test.sh passes on an untouched copy" "$rc $(grep -c '^FAIL' <<<"$out")" "0 0"
  target="$COPY/agents/impl-haiku.md"
  clause='Never edit or delete an existing test unless the brief names it.'
  sed "s/^Never edit or delete an existing test unless the brief names it\./$clause $clause/" "$target" > "$target.new" && mv "$target.new" "$target"
  out=$(cd "$COPY/tests" && timeout 60 bash impl-clauses.test.sh 2>&1); rc=$?
  check "A20: a clause duplicated in one impl-*.md makes impl-clauses.test.sh print a FAIL line" "$([ "$rc" -ne 0 ] && echo failed || echo passed) $(grep -c '^FAIL.*impl-haiku' <<<"$out" | awk '{ print ($1 >= 1) ? "fail-line" : "no-fail-line" }')" "failed fail-line"
fi

# ------------------------------------------------------------------ A21
if selected A21; then
  NOTE="$REPO_ROOT/docs/dforge/notes/2026-10-28-pipeline-smoke.md"
  cav=$(tr -d '\r' < "$NOTE" | awk '/^#+ Caveats[[:space:]]*$/ { on = 1; next } on && /^#+ / { exit } on { print }' | tr '\n' ' ')
  check "A21: the note has a Caveats section" "$(grep -cE '^#+ Caveats[[:space:]]*$' "$NOTE")" "1"
  matches "A21: it names the figures that come from the last result event" "$cav" 'last .?result.? event'
  matches "A21: it names the subagent messages in the timeline" "$cav" 'subagent'
  matches "A21: it names the p1_overlap change" "$cav" 'p1_overlap.{0,300}(changed|group)'
fi

# ------------------------------------------------------------------ A23
if selected A23; then
  out=$(cd "$REPO_ROOT" && timeout 120 node scripts/validate-repository.mjs 2>&1); rc=$?
  check "A23: node scripts/validate-repository.mjs passes" "$rc" "0"
  CLAUDE_BIN=${CLAUDE_BIN:-/root/.local/bin/claude}
  if [ -x "$CLAUDE_BIN" ]; then
    out=$(cd "$REPO_ROOT" && timeout 120 "$CLAUDE_BIN" plugin validate . 2>&1); rc=$?
    check "A23: claude plugin validate passes on the marketplace" "$rc" "0"
    for p in $(jq -r '.plugins[].source' "$REPO_ROOT/.claude-plugin/marketplace.json" | tr -d '\r'); do
      if [ -f "$REPO_ROOT/$p/.claude-plugin/plugin.json" ]; then
        out=$(cd "$REPO_ROOT" && timeout 120 "$CLAUDE_BIN" plugin validate "$p" 2>&1); rc=$?
        check "A23: claude plugin validate passes on $p" "$rc" "0"
      fi
    done
  else
    printf 'skip - A23: no claude CLI at %s\n' "$CLAUDE_BIN"
  fi
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
