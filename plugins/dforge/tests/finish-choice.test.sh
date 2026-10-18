#!/usr/bin/env bash
# finish-choice keeps the finish action chosen before execution; finishing
# carries it out at once and records that it did, so it is never re-run.
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
check "get: prints the choice" "$(fc get --plan docs/plans/p.md | jq -r '[.action, .base] | join(" ")')" "pr main"

# --- finishing acts on it ---
fc answer later --plan docs/plans/p.md >/dev/null 2>&1
check "answer: refuses an unknown action" "$?" "2"
check "answer: prints nothing" "$(FINISH_CHOICE_NOW=$((T0 + 60)) fc answer pr --plan docs/plans/p.md)" ""
check "answer: recorded" "$(jq -r '[.answer, .answeredAt] | join(" ")' "$file")" "pr $((T0 + 60))"
check "answer: get shows it" "$(fc get --plan docs/plans/p.md | jq -r .answer)" "pr"

# --- the timer is gone ---
for cmd in arm "job cron-7" due; do
  fc $cmd --plan docs/plans/p.md >/dev/null 2>&1
  check "$cmd: no longer a command" "$?" "2"
done

# --- a file an older version armed still reads ---
mkdir -p .dforge/sdd/old && printf '# Plan\n' > docs/plans/old.md
printf '{"action":"merge","base":"main","chosenAt":%d,"armedAt":%d,"dueAt":%d,"job":"cron-8","firedAt":%d}\n' \
  "$T0" "$T0" "$((T0 + 1800))" "$((T0 + 1800))" > .dforge/sdd/old/finish.json
out=$(fc get --plan docs/plans/old.md)
check "old file: get exits 0" "$?" "0"
check "old file: the action and base read" "$(jq -r '[.action, .base] | join(" ")' <<<"$out")" "merge main"

# --- wait, and work without a plan ---
fc set wait >/dev/null
check "no plan: under .dforge/sdd" "$(jq -r .action .dforge/sdd/finish.json)" "wait"
fc clear
fc get >/dev/null 2>&1
check "clear: nothing chosen" "$?" "3"

# --- the finishAction setting ---
mkdir -p "$HOME/.dforge" docs/plans
for name in s r w; do printf '# Plan\n' > "docs/plans/$name.md"; done
fc get --plan docs/plans/s.md >/dev/null 2>&1
check "setting ask: nothing chosen still exits 3" "$?" "3"
printf '{"finishAction":"merge"}\n' > "$HOME/.dforge/config.json"
out=$(FINISH_CHOICE_NOW=$T0 fc get --plan docs/plans/s.md)
check "setting: get exits 0" "$?" "0"
check "setting: get records the configured action" \
  "$(jq -r '[.action, (.base | tostring), .source, (.chosenAt | tostring)] | join(" ")' .dforge/sdd/s/finish.json)" "merge null setting $T0"
has "setting: get prints the choice" "$out" '"action": "merge"'
fc set keep --plan docs/plans/r.md >/dev/null
check "a recorded choice wins over the setting" "$(fc get --plan docs/plans/r.md | jq -r '[.action, (.source // "asked")] | join(" ")')" "keep asked"
printf '{"finishAction":"wait"}\n' > "$HOME/.dforge/config.json"
check "setting wait: recorded" "$(fc get --plan docs/plans/w.md | jq -r .action)" "wait"
rm -f "$HOME/.dforge/config.json"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
