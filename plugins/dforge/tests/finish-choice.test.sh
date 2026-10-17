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
# finish-choice reads ~/.dforge/config.json; a temporary home keeps the real one out.
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 TZ=UTC
git init -q "$TMP/repo"
cd "$TMP/repo"
mkdir -p docs/plans && printf '# Plan\n' > docs/plans/p.md
fc() { bash "$SCRIPT" "$@"; }
T0=1760000000

# --- a plan run ---
FINISH_CHOICE_NOW=$T0 fc set pr --base main --plan docs/plans/p.md >/dev/null
file=".dforge/sdd/p/finish.json"
check "set: beside the plan's ledger" "$(jq -r '[.action, .base, .chosenAt] | join(" ")' "$file")" "pr main $T0"
check "set: git-ignored" "$(git status --porcelain --untracked-files=all | grep -c dforge)" "0"
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
check "no plan: under .dforge/sdd" "$(jq -r .action .dforge/sdd/finish.json)" "wait"
fc arm >/dev/null 2>&1
check "arm: wait arms nothing" "$?" "3"
fc clear
fc get >/dev/null 2>&1
check "clear: nothing chosen" "$?" "3"
fc due >/dev/null 2>&1
check "due: nothing chosen does nothing" "$?" "3"

# --- the finishAction and finishTimeout settings ---
mkdir -p "$HOME/.dforge" docs/plans
for name in s r a w; do printf '# Plan\n' > "docs/plans/$name.md"; done
fc get --plan docs/plans/s.md >/dev/null 2>&1
check "setting ask: nothing chosen still exits 3" "$?" "3"
printf '{"finishAction":"merge","finishTimeout":45}\n' > "$HOME/.dforge/config.json"
out=$(FINISH_CHOICE_NOW=$T0 fc get --plan docs/plans/s.md)
check "setting: get exits 0" "$?" "0"
check "setting: get records the configured action" \
  "$(jq -r '[.action, (.base | tostring), .source, (.chosenAt | tostring)] | join(" ")' .dforge/sdd/s/finish.json)" "merge null setting $T0"
has "setting: get prints the choice" "$out" '"action": "merge"'
FINISH_CHOICE_NOW=$T0 fc arm --plan docs/plans/s.md >/dev/null
check "setting: arm waits finishTimeout minutes" "$(jq -r '.dueAt - .armedAt' .dforge/sdd/s/finish.json)" "2700"
FINISH_CHOICE_NOW=$T0 fc arm --minutes 10 --plan docs/plans/s.md >/dev/null
check "setting: --minutes still overrides" "$(jq -r '.dueAt - .armedAt' .dforge/sdd/s/finish.json)" "600"
fc set keep --plan docs/plans/r.md >/dev/null
check "a recorded choice wins over the setting" "$(fc get --plan docs/plans/r.md | jq -r '[.action, (.source // "asked")] | join(" ")')" "keep asked"
FINISH_CHOICE_NOW=$T0 fc arm --plan docs/plans/a.md >/dev/null
check "arm with nothing chosen records the setting first" "$(jq -r '[.action, .source] | join(" ")' .dforge/sdd/a/finish.json)" "merge setting"
printf '{"finishAction":"wait"}\n' > "$HOME/.dforge/config.json"
check "setting wait: recorded" "$(fc get --plan docs/plans/w.md | jq -r .action)" "wait"
fc arm --plan docs/plans/w.md >/dev/null 2>&1
check "setting wait: nothing to arm" "$?" "3"
rm -f "$HOME/.dforge/config.json"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
