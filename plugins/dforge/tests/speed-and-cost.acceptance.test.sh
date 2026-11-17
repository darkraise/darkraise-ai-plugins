#!/usr/bin/env bash
# Acceptance tests for the speed-and-cost spec
# (docs/dforge/specs/2026-10-27-speed-and-cost-design.md), the plugin-side
# statements A1, A3, A4, A5, A6, A7, A9, A10 and A11.
# Each test is written from the statement's text and reaches the behaviour
# through the scripts the spec names (task-step, suite-run, impl-stop-gate), the
# files the plugin ships, or, where a statement is about what a skill tells a
# session to do, the text of the shipped skill and references.
# Usage:
#   bash speed-and-cost.acceptance.test.sh            run every test
#   bash speed-and-cost.acceptance.test.sh A5 A9      run the named tests only
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
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
lacks() { # lacks <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n' "$1" "$3"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}
matches() { # matches <name> <haystack> <ERE>
  if grep -qE -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       no match: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
selected() { [ "$ONLY" = "  " ] || [[ "$ONLY" == *" $1 "* ]]; }

TMP="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
export WORKFLOW_GUARD_CLAUDE_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_MANAGED_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_PROJECT_DIR="$TMP/workflow-guard"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude"
unset CLAUDE_CONFIG_DIR CODEX_HOME AR_SESSION DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_PROJECT_DIR CLAUDE_CODE_SESSION_ID
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1 MSYS_NO_PATHCONV=1
export DR_CODEX_SESSION_DIR="$TMP/codex-sessions" CLAUDE_CODE_SESSION_ID=speed-and-cost-acceptance
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-gate usable=true reason= review=true resets_at=- source=cache"' > "$TMP/gate-stub"
export TASK_STEP_CODEX_GATE="$TMP/gate-stub"

doc() { tr -d '\r' < "$1" | tr '\n' ' ' | tr -s ' '; } # a file as one line, whitespace collapsed
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }

# ------------------------------------------------- fixture for A3, A5, A6, A7
need_fixture() { selected A3 || selected A4 || selected A5 || selected A6 || selected A7; }
if need_fixture; then
  FIX="$TMP/repo"
  git init -q "$FIX"
  g() { git -C "$FIX" "$@"; }
  g config user.name t
  g config user.email t@example.invalid
  mkdir -p "$FIX/docs" "$FIX/lib"
  {
    printf '# Acceptance Fixture Plan\n\n**Goal:** Fixture.\n\n**Execution:** inline — `claude --model sonnet --effort high` — fixture\n\n## Task index\n\n'
    for n in 1 2 3 4 5; do printf '%s. Task %s\n' "$n" "$n"; done
    for n in 1 2 3 4 5; do
      printf '\n### Task %s: Task %s\n\n**Files:**\n- Modify: `lib/new.sh`\n\n**Implementer:** dforge:impl-sonnet-high\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\nRun: `bash check.sh`\n' "$n" "$n"
    done
  } > "$FIX/docs/plan.md"
  printf '#!/usr/bin/env bash\nif grep -qx ok state.txt; then echo "ok 1 - alpha"; else echo "not ok 1 - alpha"; exit 1; fi\n' > "$FIX/suite.sh"
  printf 'ok\n' > "$FIX/state.txt"
  printf '#!/usr/bin/env bash\necho old\n' > "$FIX/lib/old.sh"
  printf '#!/usr/bin/env bash\necho "not ok 1 - beta"\nexit 1\n' > "$FIX/check.sh"
  g add -A && g commit -qm base
  CMD='bash suite.sh'
  ts() { out=$(cd "$FIX" && bash "$STEP" "$@" 2>"$TMP/err"); rc=$?; err=$(cat "$TMP/err"); }
  commit_file() { # commit_file <path> <content> — one commit
    printf '%s\n' "$2" > "$FIX/$1"; g add -A && g commit -qm "change $1"
    HEAD_SHA=$(g rev-parse HEAD | tr -d '\r')
  }
  WS=$(winpath "$(cd "$FIX" && bash "$S/sdd-workspace" docs/plan.md)")
  LEDGER="$WS/progress.md"
  good_report() { # good_report <task> [extra Cannot verify bullets...]
    local t=$1; shift
    { printf '## Verdict\nspec: pass\nquality: approved\nscores: spec 17 / scope 18 / verification 16 / quality 16\n\n## Strengths\nFine.\n\n## Findings\n\n## Cannot verify\n'
      for b in "$@"; do printf '%s\n' "$b"; done
      printf '\n## Assessment\nFine.\n'; } > "$WS/task-$t-review-report.md"
  }
fi

# ---------------------------------------------------------------- A3
if selected A3; then
  has "A3: the session report shape names the Verified section" "$(doc "$PLUGIN/reference/delegated-task.md")" '## Verified'
fi

# ---------------------------------------------------------------- A4
if selected A4; then
  # suite-run itself records a row at the head the controller runs it at.
  (cd "$FIX" && timeout 60 bash "$SUITE" -- bash -c "$CMD" >/dev/null 2>&1)
  row=$(awk -F'\t' -v h="$(g rev-parse HEAD | tr -d '\r')" '$1 == h { print $4 }' "$FIX/.dforge/suites.tsv" 2>/dev/null | tail -n 1)
  check "A4: suite-run records a row at the head it ran at" "$row" "0"
fi

# ---------------------------------------------------------------- A5
if selected A5; then
  ts start docs/plan.md 1 --suite "$CMD"
  commit_file state.txt bad
  H1=$HEAD_SHA; H1_7=${H1:0:7}
  ts review docs/plan.md 1
  check "A5: review exits 0" "$rc" "0"
  good_report 1
  ts verdict docs/plan.md 1
  check "A5: no row for the head: exit 7" "$rc" "7"
  check "A5: no row: prints suite: not run (<command>)" "$(grep '^suite: ' <<<"$out")" "suite: not run ($CMD)"
  check "A5: no row: writes no fix file" "$(ls "$WS"/task-1-fix-*.md 2>/dev/null | wc -l | tr -d ' ')" "0"

  (cd "$FIX" && timeout 60 bash "$SUITE" -- bash -c 'true' >/dev/null 2>&1)
  ts verdict docs/plan.md 1
  check "A5: a row for another command at the head does not count: exit 7" "$rc" "7"

  (cd "$FIX" && timeout 60 bash "$SUITE" -- bash -c "$CMD" >/dev/null 2>&1)
  ts verdict docs/plan.md 1
  check "A5: a non-baseline failure: exit 0" "$rc" "0"
  matches "A5: the digest carries the Important finding for the failing test" "$out" "^Important 1 suite:0 — suite: .*alpha.* fails at $H1_7\$"
  fix_line=$(grep '^fix: ' <<<"$out")
  matches "A5: the digest prints fix: naming the fix file" "$fix_line" '^fix: .*task-1-fix-1\.md'
  fixfile=$(sed -E 's/^fix: (.*task-1-fix-1\.md).*/\1/' <<<"$fix_line")
  check "A5: the fix file exists" "$([ -f "$fixfile" ] && echo yes || echo no)" "yes"
  matches "A5: the fix file holds suite: <test> fails at <head7>" "$(cat "$fixfile" 2>/dev/null)" "suite: .*alpha.* fails at $H1_7"

  # A failure the base commit also has is not a finding.
  ts start docs/plan.md 2 --suite "$CMD"
  commit_file lib/new.sh 'echo new'
  H2=$HEAD_SHA
  ts review docs/plan.md 2
  good_report 2
  (cd "$FIX" && timeout 60 bash "$SUITE" -- bash -c "$CMD" >/dev/null 2>&1)
  ts verdict docs/plan.md 2
  check "A5: a failure the base also has: exit 0" "$rc" "0"
  lacks "A5: a baseline-only failure is no finding" "$(grep -E '^(Critical|Important) ' <<<"$out")" "alpha"
  check "A5: a baseline-only failure writes no fix file" "$(ls "$WS"/task-2-fix-*.md 2>/dev/null | wc -l | tr -d ' ')" "0"
fi

# ---------------------------------------------------------------- A6, A7
if selected A6 || selected A7; then
  ts start docs/plan.md 3
  commit_file lib/new.sh $'#!/usr/bin/env bash\ncompute_total() {\n  echo 1\n}'
  ts review docs/plan.md 3
  good_report 3 \
    '- cannot-verify: exists lib/new.sh at head — the brief names this file' \
    '- cannot-verify: exists lib/old.sh at base — the brief says it predates the task' \
    '- cannot-verify: exists compute_total at head — callers need the function' \
    '- cannot-verify: baseline bash check.sh — does the check fail before the task'
  ts verdict docs/plan.md 3
  rc3=$rc; out3=$out
  ledger3=$(tr -d '\r' < "$LEDGER" | grep '^Task 3: Ruling: cannot-verify' || true)

  ts start docs/plan.md 4
  commit_file lib/other.sh $'#!/usr/bin/env bash\ncompute_other() {\n  echo 2\n}'
  ts review docs/plan.md 4
  good_report 4 \
    '- cannot-verify: exists lib/other.sh at head, expect present — the brief names this file' \
    '- cannot-verify: exists lib/old.sh at base, expect present — the brief says it predates the task' \
    '- cannot-verify: exists compute_other at head, expect present — callers need the function' \
    '- cannot-verify: baseline bash check.sh, expect fail — does the check fail before the task'
  ts verdict docs/plan.md 4
  rc4=$rc; out4=$out
  ledger4=$(tr -d '\r' < "$LEDGER" | grep '^Task 4: Ruling: cannot-verify' || true)

  ts start docs/plan.md 5
  commit_file lib/third.sh 'echo third'
  ts review docs/plan.md 5
  good_report 5 \
    '- the caller passes the flag to the new function' \
    '- cannot-verify: the retry path is covered by an integration test I could not find'
  ts verdict docs/plan.md 5
  rc5=$rc; out5=$out
  ledger5=$(tr -d '\r' < "$LEDGER" | grep '^Task 5: Ruling: cannot-verify' || true)
fi

if selected A6; then
  check "A6 (no expect): verdict exits 0" "$rc3" "0"
  check "A6 (no expect): no item is settled" "$(grep -c 'settled by task-step check' <<<"$ledger3")" "0"
  check "A6 (no expect): all four items are left for the seat" "$(grep -c '^cannot-verify: ' <<<"$out3")" "4"

  check "A6 (expect form): verdict exits 0" "$rc4" "0"
  check "A6 (expect form): three exists items and one baseline item are settled" \
    "$(grep -c 'settled by task-step check' <<<"$ledger4")" "4"
  check "A6 (expect form): no item is left for a seat" "$(grep -c '^cannot-verify: ' <<<"$out4")" "0"
fi

# ---------------------------------------------------------------- A7
if selected A7; then
  check "A7: verdict exits 0 with only free-text items" "$rc5" "0"
  has "A7: a plain free-text item reaches the digest for the ruling seat" "$out5" "cannot-verify: the caller passes the flag to the new function"
  has "A7: a free-text item written with the cannot-verify prefix reaches it too" "$out5" "cannot-verify: the retry path is covered by an integration test I could not find"
  check "A7: no free-text item is logged as settled by task-step" "$ledger5" ""
fi

# ---------------------------------------------------------------- gate fixtures
need_gate() { selected A9 || selected A10 || selected A11; }
if need_gate; then
  GREPO="$TMP/grepo"
  git init -q "$GREPO"
  git -C "$GREPO" config user.name t; git -C "$GREPO" config user.email t@example.invalid
  printf 'x\n' > "$GREPO/f"; git -C "$GREPO" add -A && git -C "$GREPO" commit -qm init
  GSTATE=$(cd "$GREPO" && bash "$S/dforge-path" state | tr -d '\r')
  mkdir -p "$TMP/reports"
  gate() { # gate <agent_type> <agent_id> <message> — sets grc and gerr
    jq -n --arg t "$1" --arg i "$2" --arg m "$3" --arg c "$GREPO" \
      '{session_id: "s", cwd: $c, hook_event_name: "SubagentStop", stop_hook_active: false, agent_id: $i, agent_type: $t, last_assistant_message: $m}' \
      | CLAUDE_PLUGIN_ROOT="$PLUGIN" timeout 30 bash "$GATE" 2>"$TMP/gerr"
    grc=$?; gerr=$(cat "$TMP/gerr")
  }
  qa() { printf '%s\nReport: %s' "${2:-QA done.}" "$1"; } # qa <report path> [first line]
  miss() { qa "$TMP/reports/none.md" "$1"; } # miss <first line>: a reply whose report file is missing
  newid() { printf 'agent-%s' "$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"; }
fi

# ---------------------------------------------------------------- A9
if selected A9; then
  hooks=$(jq -r '.hooks.SubagentStop[0] | [.matcher, .hooks[0].command] | @tsv' < "$PLUGIN/hooks/hooks.json" | tr -d '\r')
  has "A9: hooks.json registers the gate on SubagentStop for the QA seat" "$hooks" '^(dforge:)?impl-sonnet-high$'
  has "A9: and runs scripts/impl-stop-gate" "$hooks" 'scripts/impl-stop-gate'

  printf '## Verdict\npass: 1\n' > "$TMP/reports/ok.md"
  gate dforge:impl-sonnet-high "$(newid)" "$(qa "$TMP/reports/ok.md")"
  check "A9: a report that opens with ## Verdict passes" "$grc" "0"
  gate dforge:impl-sonnet-high "$(newid)" $'**Status:** DONE\n- Commits: abc1234 feat: x'
  check "A9: a reply with no Report: line passes" "$grc" "0"
  gate impl-sonnet-high "$(newid)" "$(qa "$TMP/reports/nothing-here.md")"
  check "A9: an agent type without the plugin prefix is gated too" "$grc" "2"
  gate dforge:impl-sonnet-high "$(newid)" "$(qa "$TMP/reports/nothing-here.md")"
  check "A9: a missing report file exits 2" "$grc" "2"
  has "A9: and the reason names the missing file" "$gerr" "nothing-here.md"
  has "A9: and the block names the Report: line" "$gerr" "Report: line"
  printf '# Task report\n\n## Verdict\npass: 1\n' > "$TMP/reports/no-verdict.md"
  gate dforge:impl-sonnet-high "$(newid)" "$(qa "$TMP/reports/no-verdict.md")"
  check "A9: a report that does not open with ## Verdict exits 2" "$grc" "2"
  has "A9: and the reason names ## Verdict" "$gerr" "## Verdict"
fi

# ---------------------------------------------------------------- A10
if selected A10; then
  for kind in dforge:judge-opus general-purpose Explore dforge:judge-sonnet-high; do
    gate "$kind" "$(newid)" "$(miss 'QA done.')"
    check "A10: $kind with a missing report exits 0" "$grc" "0"
  done
  gate dforge:impl-sonnet-high "$(newid)" $'**Status:** BLOCKED - the brief is unclear'
  check "A10: a BLOCKED impl stop exits 0" "$grc" "0"
  gate dforge:impl-sonnet-high "$(newid)" $'**Status:** NEEDS_CONTEXT\nWhich file?'
  check "A10: a NEEDS_CONTEXT impl stop exits 0" "$grc" "0"
  gate dforge:impl-sonnet-high "$(newid)" 'I finished the work and have nothing more to say.'
  check "A10: an impl stop with no status line exits 0" "$grc" "0"

  id=$(newid)
  gate dforge:impl-sonnet-high "$id" "$(miss 'first try')"
  r1=$grc
  gate dforge:impl-sonnet-high "$id" "$(miss 'second try, different words')"
  r2=$grc
  check "A10: the first two distinct stops are blocked" "$r1 $r2" "2 2"
  gate dforge:impl-sonnet-high "$id" "$(miss 'third try, different again')"
  check "A10: the third distinct stop after two blocks exits 0" "$grc" "0"
  log="$GSTATE/impl-stop-gate.log"
  check "A10: it appends exactly one line to <state>/impl-stop-gate.log" "$(wc -l < "$log" 2>/dev/null | tr -d ' ')" "1"
  matches "A10: the log line is '<epoch> <agent_id> <agent_type> pass-through after 2 blocks — <reason>'" "$(cat "$log" 2>/dev/null)" "^[0-9]+ $id dforge:impl-sonnet-high pass-through after 2 blocks — .+"

  # An identical stop fired twice does not raise the count.
  id=$(newid)
  gate dforge:impl-sonnet-high "$id" "$(miss 'repeated stop')"
  a=$grc
  gate dforge:impl-sonnet-high "$id" "$(miss 'repeated stop')"
  b=$grc
  gate dforge:impl-sonnet-high "$id" "$(miss 'repeated stop')"
  c=$grc
  check "A10: the same stop three times is blocked each time" "$a $b $c" "2 2 2"
  gate dforge:impl-sonnet-high "$id" "$(miss 'a second, distinct stop')"
  d=$grc
  check "A10: after repeats the next distinct stop is still only the second block" "$d" "2"
  gate dforge:impl-sonnet-high "$id" "$(miss 'a third, distinct stop')"
  check "A10: and the stop after that passes" "$grc" "0"
  check "A10: the repeats added no second log line for the first agent" "$(grep -c " $id " "$log")" "1"
fi

# ---------------------------------------------------------------- A11
if selected A11; then
  STUBS="$TMP/stubs"; mkdir -p "$STUBS"
  STUBLOG="$TMP/stub-calls.log"; : > "$STUBLOG"
  for tool in npm npx yarn pnpm bun deno pytest py.test python python3 tox nose2 go cargo make mvn gradle dotnet jest vitest mocha bats ruby rspec rake php phpunit \
              curl wget nc ncat telnet ssh scp sftp ftp socat dig nslookup ping http; do
    printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 0\n' "$tool" "$STUBLOG" > "$STUBS/$tool"
    chmod +x "$STUBS/$tool"
  done
  # PATH takes the POSIX form: TMP's C:/… splits at its drive letter's colon.
  STUBS_PATH=$STUBS
  if command -v cygpath >/dev/null 2>&1; then STUBS_PATH=$(cygpath -u "$STUBS"); fi
  PATH="$STUBS_PATH:$PATH" npm test >/dev/null 2>&1
  check "A11: the recording stubs work (control: npm is recorded)" "$(grep -c '^npm test' "$STUBLOG")" "1"
  : > "$STUBLOG"

  { printf '## Verdict\npass: 1\n\n## Notes\n'; for i in $(seq 1 1000); do printf 'line %s: tested things and ran things\n' "$i"; done; } > "$TMP/reports/big.md"
  { printf '# Task report\n\n## Notes\n'; for i in $(seq 1 1000); do printf 'line %s: tested things\n' "$i"; done; printf '\n## Verdict\npass: 1\n'; } > "$TMP/reports/big-bad.md"
  check "A11: the report is a 1,000-line file" "$([ "$(wc -l < "$TMP/reports/big.md")" -ge 1000 ] && echo yes || echo no)" "yes"

  OLDPATH=$PATH
  export PATH="$STUBS_PATH:$OLDPATH"
  gate dforge:impl-sonnet-high "$(newid)" "$(qa "$TMP/reports/big.md")"
  check "A11: a 1,000-line report that opens with ## Verdict passes" "$grc" "0"
  gate dforge:impl-sonnet-high "$(newid)" "$(qa "$TMP/reports/big-bad.md")"
  check "A11: a 1,000-line report that does not open with ## Verdict is blocked" "$grc" "2"
  gate dforge:impl-sonnet-high "$(newid)" $'**Status:** DONE\nno report line'
  check "A11: a reply with no Report: line passes" "$grc" "0"
  id=$(newid)
  gate dforge:impl-sonnet-high "$id" "$(miss one)"
  gate dforge:impl-sonnet-high "$id" "$(miss two)"
  gate dforge:impl-sonnet-high "$id" "$(miss three)"
  check "A11: the pass-through path passes" "$grc" "0"
  export PATH=$OLDPATH
  check "A11: no test runner or network tool stub was invoked by any gate run" "$(cat "$STUBLOG")" ""
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
