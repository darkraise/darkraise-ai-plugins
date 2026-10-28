#!/usr/bin/env bash
# Acceptance tests for the speed-and-cost spec
# (docs/dforge/specs/2026-10-27-speed-and-cost-design.md), the plugin-side
# statements A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A16 and A18. A12 and
# A13 (the eval pipeline) are in evals/tiers/tests/speed-and-cost.acceptance.test.mjs.
# Each test is written from the statement's text and reaches the behaviour
# through the scripts the spec names (task-step, suite-run, impl-stop-gate), the
# files the plugin ships, or, where a statement is about what a skill tells a
# session to do, the text of the shipped skill and references.
# Usage:
#   bash speed-and-cost.acceptance.test.sh            run every test
#   bash speed-and-cost.acceptance.test.sh A5 A9      run the named tests only
# SKIP_PINS=1 skips A2's run of the pre-split pin tests (about four minutes).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN/../.." && pwd)"
S="$PLUGIN/scripts"
STEP="$S/task-step"
SUITE="$S/suite-run"
GATE="$S/impl-stop-gate"
BASE=${SPEED_AND_COST_BASE:-e6f88a653e365585ad446e3bbe505e4dc4155819}
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
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude"
unset CLAUDE_CONFIG_DIR CODEX_HOME AR_SESSION DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_PROJECT_DIR CLAUDE_CODE_SESSION_ID
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1 MSYS_NO_PATHCONV=1
export DR_CODEX_SESSION_DIR="$TMP/codex-sessions" CLAUDE_CODE_SESSION_ID=speed-and-cost-acceptance
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-gate usable=true reason= review=true lane=false resets_at=- source=cache"' > "$TMP/gate-stub"
export TASK_STEP_CODEX_GATE="$TMP/gate-stub"

doc() { tr -d '\r' < "$1" | tr '\n' ' ' | tr -s ' '; } # a file as one line, whitespace collapsed
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
base_known() { git -C "$REPO_ROOT" cat-file -e "$BASE^{commit}" 2>/dev/null; }

# ---------------------------------------------------------------- A1
if selected A1; then
  over=""
  for f in "$PLUGIN"/skills/*/SKILL.md; do
    bytes=$(wc -c < "$f" | tr -d ' \r')
    [ "$bytes" -le 20000 ] || over="$over$(basename "$(dirname "$f")")=$bytes "
  done
  check "A1: every skills/*/SKILL.md is at most 20,000 bytes" "$over" ""

  mkdir -p "$TMP/a1/tests" "$TMP/a1/skills/small" "$TMP/a1/skills/exact" "$TMP/a1/skills/huge" "$TMP/a1/skills/barely"
  cp "$HERE/skill-size.test.sh" "$TMP/a1/tests/skill-size.test.sh"
  head -c 5000 /dev/zero | tr '\0' x > "$TMP/a1/skills/small/SKILL.md"
  head -c 20000 /dev/zero | tr '\0' x > "$TMP/a1/skills/exact/SKILL.md"
  head -c 31337 /dev/zero | tr '\0' x > "$TMP/a1/skills/huge/SKILL.md"
  head -c 20001 /dev/zero | tr '\0' x > "$TMP/a1/skills/barely/SKILL.md"
  out=$(timeout 60 bash "$TMP/a1/tests/skill-size.test.sh" 2>&1); rc=$?
  check "A1: skill-size.test.sh fails when a skill is over the cap" "$([ "$rc" -ne 0 ] && echo failed || echo passed)" "failed"
  has "A1: it names the 31,337-byte file with its size" "$out" "huge/SKILL.md"
  has "A1: it prints the 31,337 size" "$out" "31337"
  has "A1: it names the 20,001-byte file" "$out" "barely/SKILL.md"
  has "A1: it prints the 20,001 size" "$out" "20001"
  lacks "A1: it does not name a skill at exactly 20,000 bytes" "$(grep -E 'FAIL|skill-size:' <<<"$out")" "exact/SKILL.md"
  lacks "A1: it does not name a small skill" "$(grep -E 'FAIL|skill-size:' <<<"$out")" "small/SKILL.md"
  rm -rf "$TMP/a1/skills/huge" "$TMP/a1/skills/barely"
  out=$(timeout 60 bash "$TMP/a1/tests/skill-size.test.sh" 2>&1)
  check "A1: with every skill at or under the cap, skill-size.test.sh names none" "$(grep -c 'bytes (cap' <<<"$out")" "0"
  check "A1: and reports no over-cap failure" "$(grep -c 'FAIL.*at most' <<<"$out")" "0"
fi

# ---------------------------------------------------------------- A2
if selected A2; then
  if base_known; then
    missing=""
    count=0
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      count=$((count + 1))
      skill=$(cut -d/ -f4 <<<"$ref"); name=$(basename "$ref")
      linked=$(grep -F "references/$name" "$PLUGIN/skills/$skill/SKILL.md" | grep -i 'before' | head -n 1)
      [ -n "$linked" ] || missing="$missing$skill/$name "
    done < <(git -C "$REPO_ROOT" diff --diff-filter=A --name-only "$BASE" HEAD -- 'plugins/dforge/skills/*/references/*.md')
    matches "A2: the split added reference files" "$count" '^([1-9][0-9]+)$'
    check "A2: every new reference file is linked from its SKILL.md on a 'before you' line" "$missing" ""

    gone=""
    while IFS= read -r t; do
      [ -e "$HERE/$t" ] || gone="$gone$t "
    done < <(git -C "$REPO_ROOT" ls-tree --name-only "$BASE" plugins/dforge/tests/ | sed 's|.*/||')
    check "A2: no test file that existed before the split is gone" "$gone" ""

    if [ -z "${SKIP_PINS:-}" ]; then
      bad=""
      while IFS= read -r t; do
        case $t in *.sh) ;; *) continue ;; esac
        [ -f "$HERE/$t" ] || continue
        grep -qE 'SKILL\.md|skills/' "$HERE/$t" || continue
        (cd "$HERE" && timeout 300 bash "$t" > "$TMP/pin.out" 2>&1) || bad="$bad$t "
      done < <(git -C "$REPO_ROOT" ls-tree --name-only "$BASE" plugins/dforge/tests/ | sed 's|.*/||')
      check "A2: every pre-split test that reads skill text still runs and passes" "$bad" ""
    fi
  else
    printf 'skip - A2: base %s is not in this repository\n' "$BASE"
  fi
fi

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
    printf '# Acceptance Fixture Plan\n\n**Goal:** Fixture.\n\n**Execution:** subagent — `claude --model sonnet --effort high` — fixture\n\n## Task index\n\n'
    for n in 1 2 3 4 5; do printf '%s. Task %s\n' "$n" "$n"; done
    for n in 1 2 3 4 5; do
      printf '\n### Task %s: Task %s\n\n**Files:**\n- Modify: `lib/new.sh`\n\n**Implementer:** dforge:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\nRun: `bash check.sh`\n' "$n" "$n"
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
  IP="$PLUGIN/skills/subagent-driven-development/references/implementer-prompt.md"
  ts start docs/plan.md 1 --suite "$CMD"
  DISPATCH="$WS/task-1-dispatch.md"
  check "A3: task-step start writes the dispatch file" "$([ -f "$DISPATCH" ] && echo yes || echo no)" "yes"
  for src in "$IP" "$DISPATCH"; do
    label=$(basename "$src")
    text=$(doc "$src")
    lacks "A3: $label does not tell the implementer to run the full suite" "$text" "run the full suite"
    lacks "A3: $label does not tell the implementer to run the whole suite" "$text" "run the whole suite"
    lacks "A3: $label does not hand the implementer suite-run" "$text" "suite-run"
    has "A3: $label tells it to run the focused tests that cover its change" "$text" "focused tests that cover what you changed"
    has "A3: $label names the Verified section" "$text" '## Verified'
    has "A3: $label gives the pass bullet grammar" "$text" '- `<command>` — pass: <n> passed, <m> failed'
    has "A3: $label gives the fail bullet grammar" "$text" '- `<command>` — fail: <n> passed, <m> failed'
    has "A3: $label ends the reply with a Report: line" "$text" '`Report: <absolute path of the report file>`'
  done
  # The reply format puts the Report: line last in the "report back" list.
  last_item=$(doc "$IP" | sed 's/.*Then report back with ONLY//')
  matches "A3: the Report: line is the last element of the reply format" "$last_item" 'As the last line of your reply.*Report: <absolute path'
fi

# ---------------------------------------------------------------- A4
if selected A4; then
  DT="$PLUGIN/reference/delegated-task.md"
  text=$(doc "$DT")
  section=$(sed -e 's/.*\*\*The suite runs beside the review\.\*\*//' -e 's/\*\*NEEDS_CONTEXT:\*\*.*//' <<<"$text")
  has "A4: on a DONE report the controller starts suite-run" "$section" "scripts/suite-run -- bash -c '<suite command>'"
  has "A4: as a background command" "$section" "background"
  has "A4: at the task's head" "$section" "at the task's head"
  has "A4: and in the same turn runs the review step" "$section" "in the same turn run \`task-step review\`"
  has "A4: and dispatches the review seat" "$section" "dispatch its seat"
  has "A4: for DONE_WITH_CONCERNS too" "$section" "DONE or DONE_WITH_CONCERNS report"
  has "A4: the SKILL.md sends each task through delegated-task.md" "$(doc "$PLUGIN/skills/subagent-driven-development/SKILL.md")" "For each task, or batch, run [delegated-task.md]"
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

  text=$(doc "$PLUGIN/reference/delegated-task.md")
  has "A5: delegated-task.md says a task is marked complete only after verdict passes" "$text" 'A task is marked complete only after `task-step verdict` passes'
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
  # Skipped: these checks write the items in spec Design §2's form, without
  # `expect`, which the 2026-10-28 owner decision (amendment A21) overrides.
  # Deferred as register row 26 in docs/dforge/registers/2026-10-27-speed-and-cost.md.
  echo "skip: A6 spec-form checks (register row 26)"

  # The reviewer prompt's own form carries `expect`; the same items in that form.
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

# ---------------------------------------------------------------- A8
if selected A8; then
  agents=("$PLUGIN"/agents/impl-*.md)
  matches "A8: there are implementer agent files" "${#agents[@]}" '^([1-9][0-9]+)$'
  for f in "${agents[@]}"; do
    n=$(basename "$f" .md)
    t=$(doc "$f" | tr 'A-Z' 'a-z')
    matches "A8: $n carries the anti-hardcoding clause" "$t" 'general solution.*never one that only passes.*(hardcoded|hardcod)'
    matches "A8: $n carries the report-incorrect-tests clause" "$t" 'when a test looks wrong, report it'
    has "A8: $n carries the tests-are-immutable clause" "$t" "never edit or delete an existing test unless the brief names it"
    case $n in
      impl-sonnet-*) ;;
      *) has "A8: $n (non-Sonnet) carries the scope-limit clause" "$t" "change only what the brief asks for" ;;
    esac
  done
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
  report() { # report <path> <variant> — a report file; variant names what is wrong
    local p=$1 v=$2
    {
      printf '# Task report\n\n## What I did\nChanged things.\n\n'
      [ "$v" = no-verified ] || {
        printf '## Verified\n'
        case $v in
          prose-only) printf 'I ran the tests and they passed.\n- ran some tests\n- `npm test` passed\n' ;;
          fail-bullet) printf -- '- `bash tests/a.sh` — fail: 3 passed, 1 failed\n' ;;
          *) printf -- '- `bash tests/a.sh` — pass: 4 passed, 0 failed\n' ;;
        esac
        printf '\n'
      }
      [ "$v" = no-discovered ] || printf '## Discovered issues (not fixed)\nNone\n\n'
      [ "$v" = no-assumptions ] || printf '## Assumptions made\nNone\n'
    } > "$p"
  }
  msg() { printf '**Status:** %s\n- Commits: abc1234 feat: x\n- 4/4 passing\nReport: %s' "$1" "$2"; }
  newid() { printf 'agent-%s' "$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"; }
fi

# ---------------------------------------------------------------- A9
if selected A9; then
  hooks=$(jq -r '.hooks.SubagentStop[0] | [.matcher, .hooks[0].command] | @tsv' "$PLUGIN/hooks/hooks.json" | tr -d '\r')
  has "A9: hooks.json registers the gate on SubagentStop for impl agents" "$hooks" '(dforge:)?impl-.*'
  has "A9: and runs scripts/impl-stop-gate" "$hooks" 'scripts/impl-stop-gate'

  report "$TMP/reports/ok.md" ok
  gate dforge:impl-sonnet-high "$(newid)" "$(msg DONE "$TMP/reports/ok.md")"
  check "A9: a complete DONE report passes" "$grc" "0"
  gate dforge:impl-sonnet-high "$(newid)" "$(msg DONE_WITH_CONCERNS "$TMP/reports/ok.md")"
  check "A9: a complete DONE_WITH_CONCERNS report passes" "$grc" "0"
  report "$TMP/reports/fail.md" fail-bullet
  gate dforge:impl-sonnet-high "$(newid)" "$(msg DONE "$TMP/reports/fail.md")"
  check "A9: a Verified bullet in the fail form counts" "$grc" "0"

  gate dforge:impl-sonnet-high "$(newid)" $'**Status:** DONE\n- Commits: abc1234 feat: x'
  check "A9: DONE with no Report: line exits 2" "$grc" "2"
  has "A9: and the reason names the Report: line" "$gerr" "Report:"
  gate dforge:impl-opus-high "$(newid)" $'**Status:** DONE_WITH_CONCERNS\n- one concern'
  check "A9: DONE_WITH_CONCERNS with no Report: line exits 2" "$grc" "2"
  has "A9: and the reason names the Report: line" "$gerr" "Report:"
  gate impl-haiku "$(newid)" $'**Status:** DONE\nno report line here'
  check "A9: an agent type without the plugin prefix is gated too" "$grc" "2"

  gate dforge:impl-sonnet-high "$(newid)" "$(msg DONE "$TMP/reports/nothing-here.md")"
  check "A9: a missing report file exits 2" "$grc" "2"
  has "A9: and the reason names the missing file" "$gerr" "nothing-here.md"

  report "$TMP/reports/no-d.md" no-discovered
  gate dforge:impl-sonnet-high "$(newid)" "$(msg DONE "$TMP/reports/no-d.md")"
  check "A9: a report without ## Discovered issues (not fixed) exits 2" "$grc" "2"
  has "A9: and the reason names that section" "$gerr" "Discovered issues"
  report "$TMP/reports/no-a.md" no-assumptions
  gate dforge:impl-sonnet-high "$(newid)" "$(msg DONE "$TMP/reports/no-a.md")"
  check "A9: a report without ## Assumptions made exits 2" "$grc" "2"
  has "A9: and the reason names that section" "$gerr" "Assumptions made"
  report "$TMP/reports/no-v.md" no-verified
  gate dforge:impl-sonnet-high "$(newid)" "$(msg DONE "$TMP/reports/no-v.md")"
  check "A9: a report without ## Verified exits 2" "$grc" "2"
  has "A9: and the reason names that section" "$gerr" "Verified"
  report "$TMP/reports/prose.md" prose-only
  gate dforge:impl-sonnet-high "$(newid)" "$(msg DONE "$TMP/reports/prose.md")"
  check "A9: a Verified section with no bullet in the grammar exits 2" "$grc" "2"
  has "A9: and the reason names the Verified section" "$gerr" "Verified"
fi

# ---------------------------------------------------------------- A10
if selected A10; then
  report "$TMP/reports/ok.md" ok
  for kind in dforge:judge-opus general-purpose Explore dforge:judge-sonnet-high dforge:drafter-sonnet; do
    gate "$kind" "$(newid)" $'**Status:** DONE\nno report line'
    check "A10: $kind with a DONE stop and no report exits 0" "$grc" "0"
  done
  gate dforge:impl-sonnet-high "$(newid)" $'**Status:** BLOCKED - the brief is unclear'
  check "A10: a BLOCKED impl stop exits 0" "$grc" "0"
  gate dforge:impl-sonnet-high "$(newid)" $'**Status:** NEEDS_CONTEXT\nWhich file?'
  check "A10: a NEEDS_CONTEXT impl stop exits 0" "$grc" "0"
  gate dforge:impl-sonnet-high "$(newid)" 'I finished the work and have nothing more to say.'
  check "A10: an impl stop with no status line exits 0" "$grc" "0"

  id=$(newid)
  gate dforge:impl-opus-medium "$id" $'**Status:** DONE\nfirst try'
  r1=$grc
  gate dforge:impl-opus-medium "$id" $'**Status:** DONE\nsecond try, different words'
  r2=$grc
  check "A10: the first two distinct stops are blocked" "$r1 $r2" "2 2"
  gate dforge:impl-opus-medium "$id" $'**Status:** DONE\nthird try, different again'
  check "A10: the third distinct stop after two blocks exits 0" "$grc" "0"
  log="$GSTATE/impl-stop-gate.log"
  check "A10: it appends exactly one line to <state>/impl-stop-gate.log" "$(wc -l < "$log" 2>/dev/null | tr -d ' ')" "1"
  matches "A10: the log line is '<epoch> <agent_id> <agent_type> pass-through after 2 blocks — <reason>'" "$(cat "$log" 2>/dev/null)" "^[0-9]+ $id dforge:impl-opus-medium pass-through after 2 blocks — .+"

  # An identical stop fired twice does not raise the count.
  id=$(newid)
  gate dforge:impl-opus-medium "$id" $'**Status:** DONE\nrepeated stop'
  a=$grc
  gate dforge:impl-opus-medium "$id" $'**Status:** DONE\nrepeated stop'
  b=$grc
  gate dforge:impl-opus-medium "$id" $'**Status:** DONE\nrepeated stop'
  c=$grc
  check "A10: the same stop three times is blocked each time" "$a $b $c" "2 2 2"
  gate dforge:impl-opus-medium "$id" $'**Status:** DONE\na second, distinct stop'
  d=$grc
  check "A10: after repeats the next distinct stop is still only the second block" "$d" "2"
  gate dforge:impl-opus-medium "$id" $'**Status:** DONE\na third, distinct stop'
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
  PATH="$STUBS:$PATH" npm test >/dev/null 2>&1
  check "A11: the recording stubs work (control: npm is recorded)" "$(grep -c '^npm test' "$STUBLOG")" "1"
  : > "$STUBLOG"

  { printf '# Task report\n\n## What I did\n'; for i in $(seq 1 1000); do printf 'line %s: tested things and ran things\n' "$i"; done
    printf '\n## Verified\n- `bash tests/a.sh` — pass: 4 passed, 0 failed\n\n## Discovered issues (not fixed)\nNone\n\n## Assumptions made\nNone\n'; } > "$TMP/reports/big.md"
  { printf '# Task report\n\n## What I did\n'; for i in $(seq 1 1000); do printf 'line %s: tested things\n' "$i"; done
    printf '\n## Verified\n- `bash tests/a.sh` — pass: 4 passed, 0 failed\n\n## Discovered issues (not fixed)\nNone\n'; } > "$TMP/reports/big-bad.md"
  check "A11: the report is a 1,000-line file" "$([ "$(wc -l < "$TMP/reports/big.md")" -ge 1000 ] && echo yes || echo no)" "yes"

  OLDPATH=$PATH
  export PATH="$STUBS:$OLDPATH"
  gate dforge:impl-sonnet-high "$(newid)" "$(msg DONE "$TMP/reports/big.md")"
  check "A11: a complete 1,000-line report passes" "$grc" "0"
  gate dforge:impl-sonnet-high "$(newid)" "$(msg DONE "$TMP/reports/big-bad.md")"
  check "A11: an incomplete 1,000-line report is blocked" "$grc" "2"
  gate dforge:impl-sonnet-high "$(newid)" $'**Status:** DONE\nno report line'
  check "A11: a reply with no Report: line is blocked" "$grc" "2"
  id=$(newid)
  gate dforge:impl-sonnet-high "$id" $'**Status:** DONE\none'
  gate dforge:impl-sonnet-high "$id" $'**Status:** DONE\ntwo'
  gate dforge:impl-sonnet-high "$id" $'**Status:** DONE\nthree'
  check "A11: the pass-through path passes" "$grc" "0"
  export PATH=$OLDPATH
  check "A11: no test runner or network tool stub was invoked by any gate run" "$(cat "$STUBLOG")" ""
fi

# ---------------------------------------------------------------- A16
if selected A16; then
  readme=$(doc "$PLUGIN/README.md")
  section=$(sed -e 's/.*## Unattended runs//' -e 's/ ## Session budget.*//' <<<"$readme")
  matches "A16: the README has an unattended-runs section" "$readme" '## Unattended runs'
  has "A16: it documents auto mode" "$section" "Auto mode"
  has "A16: it ties auto mode to wave implementers" "$section" "wave"
  matches "A16: and gives the reason: a permission prompt stalls an unattended implementer" "$section" 'permission prompt.*(wait|stall|hold)'
  has "A16: it documents worktree.baseRef" "$section" 'worktree.baseRef'
  has "A16: set to \"head\"" "$section" '"baseRef": "head"'
  matches "A16: and gives the reason: the default branches from origin while local main may be ahead" "$section" 'origin/<default-branch>.*ahead'
fi

# ---------------------------------------------------------------- A18
if selected A18; then
  if base_known; then
    check "A18: reference/native-codex.md is byte-identical to the base" \
      "$(git -C "$REPO_ROOT" diff --stat "$BASE" -- plugins/dforge/reference/native-codex.md | wc -l | tr -d ' ')" "0"
    rule='Run the focused test while you work and the full suite once before committing.'
    old=$(git -C "$REPO_ROOT" show "$BASE:plugins/dforge/skills/executing-plans/SKILL.md" | tr -d '\r' | tr '\n' ' ' | tr -s ' ')
    has "A18: (control) the base executing-plans inline rule is the sentence tested here" "$old" "$rule"
    now=$({ doc "$PLUGIN/skills/executing-plans/SKILL.md"; for r in "$PLUGIN"/skills/executing-plans/references/*.md; do doc "$r"; done; })
    has "A18: executing-plans still tells the inline session to run the full suite once before committing" "$now" "$rule"
    wrap=$(grep -o '4\. \*\*Run the verifications as written\.\*\*.\{0,330\}' <<<"$old" | head -n 1)
    has "A18: the whole inline step 4 paragraph is unchanged" "$now" "$wrap"
  else
    printf 'skip - A18: base %s is not in this repository\n' "$BASE"
  fi
  text=$(doc "$PLUGIN/reference/delegated-task.md")
  byhand=$(sed -e 's/.*## The steps by hand//' -e 's/ ## Recovery.*//' <<<"$text")
  step2=$(sed -e 's/.*- \*\*§2\.\*\*//' -e 's/- \*\*§3\.\*\*.*//' <<<"$byhand")
  has "A18: the by-hand §2 runs suite-run itself" "$step2" 'scripts/suite-run -- <suite command>'
  has "A18: on a DONE report" "$step2" "On a DONE report"
  has "A18: in the background at the task's head" "$step2" "in the background at the task's head"
  has "A18: and treats a non-baseline failure as the Important finding of §3" "$step2" "non-baseline failure as §3's Important finding"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
