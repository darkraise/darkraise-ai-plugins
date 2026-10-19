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

# --- the spec's Finish line, which the spec review writes ---
mkdir -p docs/specs
spec_plan() { # spec_plan <name> <spec text> [Spec line value]: a plan citing its spec
  printf '%s' "$2" > "docs/specs/$1.md"
  printf '# Plan\n\n**Spec:** %s\n\n### Task 1: One\n' "${3:-\`docs/specs/$1.md\`}" > "docs/plans/$1.md"
}
spec_plan bare $'# S\n\n## Decisions\n\n1. Finish: "Ask at spec review" — the owner\'s words\n\nFinish: keep\n\n## Problem\n'
printf '{"finishAction":"merge"}\n' > "$HOME/.dforge/config.json"
out=$(FINISH_CHOICE_NOW=$T0 fc get --plan docs/plans/bare.md); status=$?
check "spec line: get exits 0" "$status" "0"
check "spec line: outranks the setting, recorded with its source" \
  "$(jq -r '[.action, (.base | tostring), .source, (.chosenAt | tostring)] | join(" ")' .dforge/sdd/bare/finish.json)" "keep null spec $T0"
has "spec line: get prints the choice" "$out" '"action": "keep"'
rm -f "$HOME/.dforge/config.json"
for pair in 'dash:-' 'star:*' 'number:6.'; do
  name="marker-${pair%%:*}" marker=${pair#*:}
  spec_plan "$name" "# S"$'\n\n'"## Decisions"$'\n\n'"$marker Finish: pr"$'\n'
  check "spec line after a '$marker' marker: a fresh record" "$([ -e ".dforge/sdd/$name/finish.json" ] && echo exists || echo none)" "none"
  check "spec line after a '$marker' marker" "$(fc get --plan "docs/plans/$name.md" | jq -r '[.action, .source] | join(" ")')" "pr spec"
  check "spec line after a '$marker' marker: recorded in its own workspace" "$(jq -r .source ".dforge/sdd/$name/finish.json")" "spec"
done
{ printf '# S\n\n## Decisions\n\nFinish: keep\n\n## Problem\n\n'; seq 1 200000 | sed 's/^/filler line /'; } > docs/specs/large.md
printf '# Plan\n\n**Spec:** `docs/specs/large.md`\n\n### Task 1: One\n' > docs/plans/large.md
out=$(fc get --plan docs/plans/large.md); status=$?
check "a long spec: the line is read and recorded" "$status:$(jq -r '[.action, .source] | join(" ")' <<<"$out")" "0:keep spec"
spec_plan crlf $'# S\r\n\r\n## Decisions\r\n\r\nFinish: merge\r\n'
check "spec line: CRLF line endings" "$(fc get --plan docs/plans/crlf.md | jq -r .action)" "merge"
spec_plan plain 'plain text'
fc set merge --plan docs/plans/plain.md >/dev/null
printf '# S\n\n## Decisions\n\nFinish: keep\n' > docs/specs/plain.md
check "a recorded choice outranks the spec line" "$(fc get --plan docs/plans/plain.md | jq -r '[.action, (.source // "asked")] | join(" ")')" "merge asked"
spec_plan none $'# S\n\n## Decisions\n\n1. Keep it small.\n'
fc get --plan docs/plans/none.md >/dev/null 2>&1
check "no spec line, setting ask: exit 3" "$?" "3"
printf '{"finishAction":"pr"}\n' > "$HOME/.dforge/config.json"
check "no spec line: the setting stands in" "$(fc get --plan docs/plans/none.md | jq -r '[.action, .source] | join(" ")')" "pr setting"
rm -f "$HOME/.dforge/config.json"
mkdir -p docs/dforge/specs
printf '# S\n\n## Decisions\n\nFinish: keep\n' > docs/dforge/specs/legacy.md
printf '# Plan\n\n**Spec:** docs/superpowers/specs/legacy.md\n\n### Task 1: One\n' > docs/plans/legacy.md
check "a spec cited under the pre-4.0 prefix is found" "$(fc get --plan docs/plans/legacy.md | jq -r '[.action, .source] | join(" ")')" "keep spec"
for case in outside fenced worded quoted; do
  case $case in
    outside) text=$'# S\n\n## Decisions\n\n1. Small.\n\n## Problem\n\nFinish: keep\n' ;;
    fenced) text=$'# S\n\n## Decisions\n\n```\nFinish: keep\n```\n' ;;
    worded) text=$'# S\n\n## Decisions\n\nFinish: keep it for review\n' ;;
    quoted) text=$'# S\n\n## Decisions\n\n3. Finish: "Ask at spec review"\n' ;;
  esac
  spec_plan "not-$case" "$text"
  fc get --plan "docs/plans/not-$case.md" >/dev/null 2>&1
  check "a Finish line $case is not read" "$?" "3"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
