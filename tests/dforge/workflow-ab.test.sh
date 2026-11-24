#!/usr/bin/env bash
# The replay harness (evals/workflow-ab): the fixture plan's shape, and prepare's
# clone hygiene, per-arm conversion, pins and --check, against a scratch source
# built from the fixture.
set -uo pipefail

case ${OSTYPE:-} in
  msys*|cygwin*) echo 'skip - workflow-ab: Linux only'; exit 0 ;;
esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAB="$HERE/../../evals/workflow-ab"
FIXTURE="$WAB/fixture"
PLAN=docs/dforge/plans/2026-01-01-fixture.md

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

# The harness refuses a root under /tmp, so the scratch lives on disk.
TMP="$(mktemp -d "${WAB_TEST_TMP:-/var/tmp}/workflow-ab-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" GIT_CONFIG_NOSYSTEM=1 TZ=UTC
mkdir -p "$HOME"
git config --global user.name Tester
git config --global user.email tester@localhost
git config --global init.defaultBranch main
unset DFORGE_BUDGET CLAUDE_CONFIG_DIR
printf '#!/bin/sh\necho "9.9.9 (Claude Code)"\n' > "$TMP/claude"
chmod +x "$TMP/claude"
mkdir -p "$TMP/claude-config"
printf '{"autoCompactWindow": 500000}\n' > "$TMP/claude-config/settings.json"
printf '{"handoffTokens": 250000}\n' > "$TMP/owner-dforge.json"
export WAB_ROOT="$TMP/root" WAB_CLAUDE="$TMP/claude" WAB_CLAUDE_CONFIG="$TMP/claude-config" \
  WAB_DFORGE_CONFIG="$TMP/owner-dforge.json" WAB_PLAN="$PLAN"

C14='- This is a replay in a clone with no remote: no push, tag or workflow dispatch; a gate that needs one is recorded as not run.'

# make_source DIR [SED] — a source repository built from the fixture: the base
# holds everything but the plan, which a later commit adds (edited by SED),
# one more commit follows, and an origin remote holds both.
make_source() {
  local src=$1
  mkdir -p "$src"
  cp -R "$FIXTURE/." "$src/"
  mkdir -p "$src/.claude"
  printf '{"enabledPlugins": {"other@market": true, "off@market": false}}\n' > "$src/.claude/settings.json"
  mv "$src/$PLAN" "$TMP/plan.md"
  git -C "$src" init -q
  git -C "$src" add -A
  git -C "$src" commit -q -m base
  mv "$TMP/plan.md" "$src/$PLAN"
  [ -z "${2:-}" ] || sed -i -E "$2" "$src/$PLAN"
  git -C "$src" add -A
  git -C "$src" commit -q -m "docs: add the plan"
  printf 'later\n' > "$src/later.txt"
  git -C "$src" add -A
  git -C "$src" commit -q -m "chore: a later commit"
  git init -q --bare "$src.origin.git"
  git -C "$src" remote add origin "$src.origin.git"
  git -C "$src" push -q origin main
}
prep() { # prep ARM RUN [ARGS...] — out and status
  out=$(bash "$WAB/prepare" "$@" 2>&1); status=$?
}

make_source "$TMP/src"
export WAB_SOURCE="$TMP/src"
WAB_BASE=$(git -C "$TMP/src" rev-list --max-parents=0 HEAD)
export WAB_BASE

# --- fixture_plan_shape ---
fx="$FIXTURE/$PLAN"
check "fixture_plan_shape: the plan sits under docs/dforge/plans" "$([ -f "$fx" ] && echo yes)" "yes"
check "fixture_plan_shape: subagent Execution line" "$(grep -c '^\*\*Execution:\*\* subagent' "$fx")" "1"
check "fixture_plan_shape: one two-task wave" "$(grep -c '^\*\*Parallelism:\*\* waves — 1-2$' "$fx")" "1"
check "fixture_plan_shape: two tasks" "$(grep -c '^### Task ' "$fx")" "2"
check "fixture_plan_shape: sonnet-high Implementer on each task" "$(grep -c '^\*\*Implementer:\*\* dforge:impl-sonnet-high$' "$fx")" "2"
check "fixture_plan_shape: one unqualified Items line" "$(grep -c '^\*\*Items:\*\*' "$fx") $(grep -c '^\*\*Items:\*\* 1$' "$fx")" "1 1"

# --- prepare_clone_hygiene ---
prep dforge 1
check "prepare_clone_hygiene: prepare exits 0" "$status" "0"
clone="$WAB_ROOT/dforge-1/clone"
g() { git -C "$clone" "$@"; }
check "prepare_clone_hygiene: no remote" "$(g remote)" ""
new=$(g rev-list --all | grep -vxF -f <(git -C "$TMP/src" rev-list "$WAB_BASE"))
check "prepare_clone_hygiene: one commit beyond the base's ancestry" "$(grep -c . <<<"$new")" "1"
check "prepare_clone_hygiene: that commit is the replay plan by the clone identity" \
  "$(g log -1 --format='%s|%an <%ae>' "$new")" "chore: replay plan|Replay <replay@localhost>"
check "prepare_clone_hygiene: the commit's parent is the base" "$(g rev-parse "$new^")" "$WAB_BASE"
"$clone/.git/hooks/pre-push" >/dev/null 2>&1
check "prepare_clone_hygiene: pre-push refuses" "$?" "1"
g config --get core.hooksPath >/dev/null
check "prepare_clone_hygiene: core.hooksPath is unset" "$?" "1"
check "prepare_clone_hygiene: no alternates" "$([ -e "$clone/.git/objects/info/alternates" ] && echo present || echo absent)" "absent"
git -C "$TMP/src" cat-file -e "$WAB_BASE:$PLAN" 2>/dev/null
check "prepare_clone_hygiene: the plan is absent at the base" "$?" "128"
check "prepare_clone_hygiene: the clone has the plan" "$([ -f "$clone/$PLAN" ] && echo yes)" "yes"
WAB_ROOT=/tmp/workflow-ab prep dforge 9
check "prepare_clone_hygiene: a root under /tmp is refused" "$status $out" "2 workflow-ab: WAB_ROOT must not be under /tmp"

# --- prepare_converts_per_arm ---
dplan="$clone/$PLAN"
check "prepare_converts_per_arm: dforge Execution line" "$(grep '^\*\*Execution:\*\*' "$dplan")" \
  '**Execution:** inline — `claude --model sonnet --effort high` — replay of a subagent plan'
check "prepare_converts_per_arm: dforge Items qualified" "$(grep '^\*\*Items:\*\*' "$dplan")" "**Items:** 2026-01-01-fixture#1"
check "prepare_converts_per_arm: dforge Implementer lines kept" "$(grep -c '^\*\*Implementer:\*\* dforge:impl-sonnet-high$' "$dplan")" "2"
has "prepare_converts_per_arm: dforge plan-lint passed" "$(cat "$WAB_ROOT/dforge-1/out/plan-lint.txt")" "plan-lint: 0 errors"
prep dagents 1
check "prepare_converts_per_arm: dagents prepare exits 0" "$status" "0"
aclone="$WAB_ROOT/dagents-1/clone"
aplan="$aclone/docs/dagents/plans/2026-01-01-fixture.md"
check "prepare_converts_per_arm: dagents Implementer lines renamed" "$(grep -c '^\*\*Implementer:\*\* dagents:impl-sonnet-high$' "$aplan") $(grep -c 'dforge:impl-' "$aplan")" "2 0"
check "prepare_converts_per_arm: dagents Execution line unchanged" "$(grep '^\*\*Execution:\*\*' "$aplan")" "$(grep '^\*\*Execution:\*\*' "$fx")"
check "prepare_converts_per_arm: dagents Items unchanged" "$(grep '^\*\*Items:\*\*' "$aplan")" "**Items:** 1"
has "prepare_converts_per_arm: dagents plan-lint passed" "$(cat "$WAB_ROOT/dagents-1/out/plan-lint.txt")" "plan-lint: 0 errors"
for f in "$dplan" "$aplan"; do
  check "prepare_converts_per_arm: the replay line once, ending Global Constraints (${f#"$WAB_ROOT/"})" \
    "$(grep -cxF -- "$C14" "$f") $(awk -v l="$C14" '$0 == "## Global Constraints" { on = 1; next } on && /^## / { exit } on && NF { last = $0 } END { print (last == l) }' "$f")" "1 1"
done
make_source "$TMP/src-opus" '/^### Task 2/,$ { s/impl-sonnet-high/impl-opus-medium/; s/^\*\*Evaluation:\*\* .*/**Evaluation:** files 1 - spec 1 - coupling 1 - risk 3 = 6/ }'
WAB_SOURCE="$TMP/src-opus" WAB_BASE=$(git -C "$TMP/src-opus" rev-list --max-parents=0 HEAD) prep dforge 4
check "prepare_converts_per_arm: an opus risk-3 variant exits 0" "$status" "0"
check "prepare_converts_per_arm: an opus risk-3 variant runs opus at high" \
  "$(grep '^\*\*Execution:\*\*' "$WAB_ROOT/dforge-4/clone/$PLAN")" \
  '**Execution:** inline — `claude --model opus --effort high` — replay of a subagent plan'

# --- prepare_pins ---
dcfg="$WAB_ROOT/dforge-1/home/.dforge/config.json"
check "prepare_pins: dforge pins" "$(jq -c '[.handoffTokens, .finishAction, .decisionApi, .codexReview, .agyReview]' "$dcfg")" '[250000,"keep","off",false,false]'
check "prepare_pins: every dforge apiBudget cap is 0" "$(jq -c '[to_entries[] | select(.key | startswith("apiBudget")) | .value]' "$dcfg")" '[0,0,0]'
acfg="$WAB_ROOT/dagents-1/home/.dagents/config.json"
check "prepare_pins: dagents pins" "$(jq -c '[.handoffTokens, .finishAction, .codexReview, .codexLane, .agyLane]' "$acfg")" '[250000,"keep",false,false,false]'
WAB_DFORGE_CONFIG="$TMP/absent.json" prep dforge 6
check "prepare_pins: no owner config, no DFORGE_BUDGET: 300000" "$(jq .handoffTokens "$WAB_ROOT/dforge-6/home/.dforge/config.json")" "300000"
WAB_DFORGE_CONFIG="$TMP/absent.json" DFORGE_BUDGET=275000 prep dforge 7
check "prepare_pins: no owner config: DFORGE_BUDGET" "$(jq .handoffTokens "$WAB_ROOT/dforge-7/home/.dforge/config.json")" "275000"
check "prepare_pins: enabled project plugins switched off" "$(jq -c .enabledPlugins "$clone/.claude/settings.local.json")" '{"other@market":false}'
check "prepare_pins: the local settings are not a change in the clone" "$(g status --porcelain)" ""
arm=$WAB_ROOT/dforge-1/arm.json
check "prepare_pins: arm.json records every field" \
  "$(jq -c '[has("pluginCommit"), has("pins"), has("model"), has("effort"), has("parallelism"), has("claudeVersion"), has("autoCompactWindow"), has("darkmem")] | all' "$arm")" "true"
check "prepare_pins: arm.json values" \
  "$(jq -c '[(.pluginCommit | test("^[0-9a-f]{40}$")), .pins.handoffTokens, .model, .effort, .parallelism, .claudeVersion, .autoCompactWindow, .darkmem]' "$arm")" \
  '[true,250000,"sonnet","high","sequential","9.9.9 (Claude Code)",500000,false]'
check "prepare_pins: dagents arm.json keeps the plan's waves" "$(jq -r '[.model, .effort, .parallelism, .plan] | join("|")' "$WAB_ROOT/dagents-1/arm.json")" \
  "sonnet|high|waves — 1-2|docs/dagents/plans/2026-01-01-fixture.md"

# --- prepare_check_blocks ---
make_source "$TMP/src-false" 's/^\*\*Integration check:\*\* .*/**Integration check:** `false`/'
WAB_SOURCE="$TMP/src-false" WAB_BASE=$(git -C "$TMP/src-false" rev-list --max-parents=0 HEAD) prep dforge 2 --check
check "prepare_check_blocks: a failing Integration check exits 1" "$status" "1"
check "prepare_check_blocks: and writes check-failed" "$(cat "$WAB_ROOT/dforge-2/state" 2>/dev/null)" "check-failed"
make_source "$TMP/src-true" 's/^\*\*Integration check:\*\* .*/**Integration check:** `true`/'
WAB_SOURCE="$TMP/src-true" WAB_BASE=$(git -C "$TMP/src-true" rev-list --max-parents=0 HEAD) prep dforge 3 --check
check "prepare_check_blocks: a passing Integration check exits 0" "$status" "0"
check "prepare_check_blocks: and writes no state" "$([ -e "$WAB_ROOT/dforge-3/state" ] && echo written || echo none)" "none"

# --- prepare_source_untouched ---
printf 'dirty\n' >> "$TMP/src/greet.sh"
git -C "$TMP/src" stash -q
printf 'untracked\n' > "$TMP/src/scratch.txt"
snapshot() {
  local s=$TMP/src
  git -C "$s" status --porcelain; git -C "$s" remote -v; git -C "$s" for-each-ref
  git -C "$s" worktree list --porcelain; git -C "$s" stash list; git -C "$s" rev-parse HEAD
}
before=$(snapshot)
prep dforge 5
check "prepare_source_untouched: prepare exits 0" "$status" "0"
check "prepare_source_untouched: status, remotes, refs, worktrees, stashes and HEAD unchanged" "$(snapshot)" "$before"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
