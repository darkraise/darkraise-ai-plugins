#!/usr/bin/env bash
# The ui-ux skill and the instructions that route to it and gate on it: each
# check is a whole instruction, not a keyword, so a rewording that drops the
# rule fails here.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
S="$P/skills/ui-ux/SKILL.md"
R="$P/skills/ui-ux/references"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" && echo yes || echo no)" "yes"
}

# --- the skill ---
check "the skill exists" "$([ -f "$S" ] && echo yes || echo no)" "yes"
check "its name is ui-ux" "$(sed -n '2p' "$S")" "name: ui-ux"
names "the description triggers on anything a user sees or does" "$S" 'description: Use when work touches anything a user sees or does'
names "the description triggers on UI bug fixes" "$S" 'fixing a bug whose fix changes the UI'
names "the depth line" "$S" '`**UI/UX depth:** <touch|feature|product> — <why>`'
names "state boards are asked at every depth" "$S" 'Ask at every depth; recommend yes at'
names "demo when no UI test runner" "$S" 'is tagged `demo` when the profile names no UI test runner'
names "the gate command" "$S" 'scripts/ui-proof check --base <ref> [--spec <spec>]'
names "the pending line" "$S" '`UI proof: pending — <why>`'
names "Accepted by needs the user's words" "$S" 'Never write `**Accepted by:**` unless the user said'
names "Codex runs the scripts by hand" "$S" 'runs no hooks: run `bash <plugin-root>/scripts/ui-lint'
for f in contract-template.md state-catalogue.md interaction-rules.md walkthrough.md \
         platforms/web.md platforms/windows.md platforms/linux-desktop.md platforms/android.md platforms/terminal.md; do
  check "reference $f exists" "$([ -f "$R/$f" ] && echo yes || echo no)" "yes"
done
for f in windows linux-desktop android; do
  names "$f guide ships marked unverified" "$R/platforms/$f.md" '**Status:** unverified'
done
check "no macOS or iOS guide" "$(ls "$R/platforms" | grep -ciE 'mac|ios')" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
