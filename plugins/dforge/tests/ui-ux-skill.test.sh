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

# --- the gate sites ---
FR="$P/reference/final-review.md"
FIN="$P/skills/finishing-a-development-branch/SKILL.md"
VBC="$P/skills/verification-before-completion/SKILL.md"
names "final review runs the gate" "$FR" 'scripts/ui-proof check --base MERGE_BASE --spec <the plan'"'"'s Spec>'
names "final review: exit 1 stops it like a red gate" "$FR" 'Exit 1 stops the review like a red gate'
names "final review: the auto-run path proves, then checks again" "$FR" 'phase, then check again, and go on when it passes'
names "final review: only an unverifiable row stops an auto run" "$FR" 'auto-run stop --reason "ui proof needs the user"'
names "final review: the check runs again after the fix wave" "$FR" 'step 0.2'"'"'s `ui-proof check` again'
names "finishing runs the gate" "$FIN" 'scripts/ui-proof check --base'
names "finishing: exit 1 keeps a recorded merge or pr" "$FIN" 'turns a recorded `merge` or `pr` into `keep`'
names "finishing: the two-option prompt ends on the menu line" "$FIN" '1. Prove it first'
names "finishing: Step 4 keeps a recorded merge after an unproven UI" "$FIN" 'When Step 1b'"'"'s `ui-proof check` exited 1, `merge` and `pr` become `keep`'
names "finishing: only an unused recorded choice skips the two-option prompt" "$FIN" 'with no `answer` or `firedAt` field, or an auto run is bound'
names "finishing: the auto-run mapping keeps too" "$FIN" '`merge` and `pr` also keep when Step 1b'"'"'s `ui-proof check` exited 1'
names "finishing: an auto run stops for unverifiable rows" "$FIN" 'auto-run stop --reason "ui proof needs the user"'
names "final review: step 0 goes on to step 0.2" "$FR" 'say so in one line and go to step 0.2'
names "verification: the UI claim row" "$VBC" '| The UI works |'

# --- routing ---
ENTRY="$P/skills/using-dforge/SKILL.md"
names "the entry point routes UI work" "$ENTRY" '| Anything a user sees or does | dforge:ui-ux |'
check "the entry point stays within 5100 bytes" "$([ "$(wc -c < "$ENTRY")" -le 5100 ] && echo yes || echo no)" "yes"
names "brainstorming runs Shape before acceptance" "$P/skills/brainstorming/SKILL.md" 'invoke dforge:ui-ux before drafting acceptance'
names "debugging runs touch depth for UI fixes" "$P/skills/systematic-debugging/SKILL.md" 'Run `dforge:ui-ux` at touch depth'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
