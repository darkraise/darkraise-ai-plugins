#!/usr/bin/env bash
# finish-choice keeps the finish action chosen before execution, arms it when
# the finishing menu is shown, and fires it only when the menu went unanswered.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/finish-choice"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_NOSYSTEM=1 TZ=UTC
git init -q "$TMP/repo"
cd "$TMP/repo"
mkdir -p docs/plans && printf '# Plan\n' > docs/plans/p.md
fc() { bash "$SCRIPT" "$@"; }
T0=1760000000

# --- a plan run ---
FINISH_CHOICE_NOW=$T0 fc set pr --base main --plan docs/plans/p.md >/dev/null
file=".superpowers/sdd/p/finish.json"
check "set: beside the plan's ledger" "$(jq -r '[.action, .base, .chosenAt] | join(" ")' "$file")" "pr main $T0"
check "set: git-ignored" "$(git status --porcelain --untracked-files=all | grep -c superpowers)" "0"
fc set later --plan docs/plans/p.md >/dev/null 2>&1
check "set: refuses an unknown action" "$?" "2"

out=$(FINISH_CHOICE_NOW=$T0 fc arm --plan docs/plans/p.md)
# T0 + 30m = 09:23:20 UTC on 2025-10-09; cron rounds up to 09:24.
has "arm: one-shot cron line" "$out" "cron: 24 9 9 10 *"
has "arm: due time" "$out" "due: 09:24"
has "arm: the wake prompt names the plan" "$out" "finish-choice due --plan docs/plans/p.md"
check "arm: stamps the deadline" "$(jq -r '.dueAt - .armedAt' "$file")" "1800"
fc job cron-7 --plan docs/plans/p.md
check "job: recorded" "$(jq -r .job "$file")" "cron-7"

FINISH_CHOICE_NOW=$((T0 + 600)) fc due --plan docs/plans/p.md >/dev/null 2>&1
check "due: early wake waits" "$?" "4"
check "due: fires at the deadline" "$(FINISH_CHOICE_NOW=$((T0 + 1800)) fc due --plan docs/plans/p.md)" "pr"
FINISH_CHOICE_NOW=$((T0 + 1900)) fc due --plan docs/plans/p.md >/dev/null 2>&1
check "due: fires once" "$?" "3"

# --- the person answers in time ---
FINISH_CHOICE_NOW=$T0 fc arm --plan docs/plans/p.md >/dev/null
fc job cron-8 --plan docs/plans/p.md
check "answer: prints the job to cancel" "$(fc answer merge --plan docs/plans/p.md)" "cron-8"
FINISH_CHOICE_NOW=$((T0 + 1800)) fc due --plan docs/plans/p.md >/dev/null 2>&1
check "answer: the wake does nothing" "$?" "3"
check "answer: recorded" "$(jq -r .answer "$file")" "merge"
FINISH_CHOICE_NOW=$T0 fc arm --plan docs/plans/p.md >/dev/null 2>&1
check "arm: nothing to arm once answered" "$?" "3"

# --- wait, and work without a plan ---
fc set wait >/dev/null
check "no plan: under .superpowers/sdd" "$(jq -r .action .superpowers/sdd/finish.json)" "wait"
fc arm >/dev/null 2>&1
check "arm: wait arms nothing" "$?" "3"
fc clear
fc get >/dev/null 2>&1
check "clear: nothing chosen" "$?" "3"
fc due >/dev/null 2>&1
check "due: nothing chosen does nothing" "$?" "3"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
