#!/usr/bin/env bash
# dagents_dir: always the 3.0 directory; dagents_legacy_layout names the pre-3.0 ones.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/lib/dagents-dir.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then pass=$((pass + 1))
  else printf 'FAIL - %s\n       got:  [%s]\n       want: [%s]\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
R="$TMP/repo"
mkdir -p "$R"

check "neither: state" "$(dagents_dir state "$R")" "$R/.dagents"
check "neither: docs" "$(dagents_dir docs "$R")" "$R/docs/dagents"

check "neither: no legacy layout" "$(dagents_legacy_layout "$R")" ""

mkdir -p "$R/.superpowers" "$R/docs/superpowers"
check "only old: state is still .dagents" "$(dagents_dir state "$R")" "$R/.dagents"
check "only old: docs is still docs/dagents" "$(dagents_dir docs "$R")" "$R/docs/dagents"
check "only old: relative docs" "$(dagents_dir_rel docs "$R")" "docs/dagents"
check "only old: legacy layout named" "$(dagents_legacy_layout "$R" | tr '\n' '|')" "$R/.superpowers|$R/docs/superpowers|"

rm -rf "$R/.superpowers" "$R/docs/superpowers"
check "removed: no legacy layout" "$(dagents_legacy_layout "$R")" ""

check "default root" "$(cd "$R" && dagents_dir state)" "./.dagents"
check "default root, relative" "$(cd "$R" && dagents_dir_rel state)" ".dagents"

dagents_dir other "$R" > /dev/null 2>&1
check "unknown kind: exit 2" "$?" "2"

# --- dagents-path: the directory for the repository at hand ---
G="$TMP/git"
git init -q "$G"
TOP=$(cd "$G" && git rev-parse --show-toplevel)
check "dagents-path: new checkout" "$(cd "$G" && bash "$HERE/../scripts/dagents-path" docs specs)" "$TOP/docs/dagents/specs"
mkdir -p "$G/.superpowers"
check "dagents-path: a pre-3.0 directory is not used" "$(cd "$G" && bash "$HERE/../scripts/dagents-path" state)" "$TOP/.dagents"
rm -rf "$G/.superpowers"
(cd "$G" && bash "$HERE/../scripts/dagents-path" > /dev/null 2>&1)
check "dagents-path: usage exit 2" "$?" "2"

# --- dagents-path: the roots and names, all in the checkout ---
H=$HOME
git -C "$G" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
FP="$HERE/../scripts/dagents-path"
check "dagents-path: ledger, local" "$(cd "$G" && HOME=$H bash "$FP" ledger p1)" "$TOP/.dagents/sdd/p1"
check "dagents-path: ledger of a plan path" "$(cd "$G" && HOME=$H bash "$FP" ledger docs/dagents/plans/2026-10-19-greet.md)" "$TOP/.dagents/sdd/2026-10-19-greet"
check "dagents-path: ledger of a backslashed plan path" "$(cd "$G" && HOME=$H bash "$FP" ledger 'docs\dagents\plans\2026-10-19-greet.md')" "$TOP/.dagents/sdd/2026-10-19-greet"
check "dagents-path: ledger of a bare plan file name" "$(cd "$G" && HOME=$H bash "$FP" ledger 2026-10-19-greet.md)" "$TOP/.dagents/sdd/2026-10-19-greet"
check "dagents-path: latest, local" "$(cd "$G" && HOME=$H bash "$FP" latest)" "$TOP/.dagents/handoff/latest.md"
# A home holding darkmem settings and a stores.json from an older build reads
# as any other: every root stays in the checkout.
mkdir -p "$H/.dagents"
printf '{"darkmemEnabled":true,"documentStore":"darkmem","darkmem":{"url":"http://127.0.0.1:9","repos":{"%s":{"project":"proj"}}}}\n' "$TOP" > "$H/.dagents/config.json"
printf '{"%s":{"documents":"darkmem","progress":"darkmem"}}\n' "$TOP" > "$H/.dagents/stores.json"
check "dagents-path: docs, leftover darkmem settings" "$(cd "$G" && HOME=$H bash "$FP" docs plans/p1.md)" "$TOP/docs/dagents/plans/p1.md"
check "dagents-path: ledger, leftover darkmem settings" "$(cd "$G" && HOME=$H bash "$FP" ledger p1)" "$TOP/.dagents/sdd/p1"
check "dagents-path: latest, leftover darkmem settings" "$(cd "$G" && HOME=$H bash "$FP" latest)" "$TOP/.dagents/handoff/latest.md"
rm -f "$H/.dagents/config.json" "$H/.dagents/stores.json"
check "dagents-path: state" "$(cd "$G" && HOME=$H bash "$FP" state)" "$TOP/.dagents"
check "dagents-path: name" "$(cd "$G" && HOME=$H bash "$FP" name "$TOP/docs/dagents/plans/p1.md")" "docs/dagents/plans/p1.md"
(cd "$G" && HOME=$H bash "$FP" ledger > /dev/null 2>&1)
check "dagents-path: ledger needs a slug" "$?" "2"

# --- dagents_legacy_layout: a linked worktree's git dir and the primary's state ---
W="$TMP/wt"
git -C "$G" worktree add -q --detach "$W"
WG=$(git -C "$W" rev-parse --absolute-git-dir)
mkdir -p "$WG/dr-superpowers" "$G/.superpowers"
check "worktree: its git dir and the primary's state" "$(dagents_legacy_layout "$W" | tr '\n' '|')" "$WG/dr-superpowers|$TOP/.superpowers|"
rm -rf "$WG/dr-superpowers" "$G/.superpowers"
check "worktree: nothing left" "$(dagents_legacy_layout "$W")" ""

# --- dagents_legacy_layout: a dr-superpowers home holds nothing dagents moves ---
SAVED_HOME=$HOME
export HOME="$TMP/home2"; mkdir -p "$HOME/.dr-superpowers/mirror/proj"
printf '{"darkmem":{"repos":{}}}\n' > "$HOME/.dr-superpowers/config.json"
check "home: a dr-superpowers darkmem mapping and mirror" "$(dagents_legacy_layout "$R")" ""
export HOME=$SAVED_HOME

# --- dagents_legacy_layout: dr-forge's 3.x names ---
mkdir -p "$R/.forge" "$R/docs/forge"
check "dr-forge: state and docs" "$(dagents_legacy_layout "$R" | tr '\n' '|')" "$R/.forge|$R/docs/forge|"
rm -rf "$R/.forge" "$R/docs/forge"
mkdir -p "$WG/dr-forge" "$G/.forge"
check "dr-forge: a worktree's git dir and the primary's state" "$(dagents_legacy_layout "$W" | tr '\n' '|')" "$WG/dr-forge|$TOP/.forge|"
rm -rf "$WG/dr-forge" "$G/.forge"
SAVED_HOME=$HOME
export HOME="$TMP/home3"; mkdir -p "$HOME/.dr-forge"
check "dr-forge: an empty ~/.dr-forge is not named" "$(dagents_legacy_layout "$R")" ""
mkdir -p "$HOME/.dr-forge/mirror/proj"
printf '{}\n' > "$HOME/.dr-forge/stores.json"
check "dr-forge: the mirror and stores.json migrate leaves are not named" "$(dagents_legacy_layout "$R")" ""
printf '{}\n' > "$HOME/.dr-forge/config.json"
check "dr-forge: a ~/.dr-forge holding anything else is named" "$(dagents_legacy_layout "$R")" "$HOME/.dr-forge"
export HOME=$SAVED_HOME

# --- dagents_legacy_layout: both older names at once ---
mkdir -p "$R/.superpowers" "$R/.forge" "$R/docs/superpowers" "$R/docs/forge"
check "mixed: every older path in one checkout" "$(dagents_legacy_layout "$R" | tr '\n' '|')" "$R/.superpowers|$R/.forge|$R/docs/superpowers|$R/docs/forge|"
rm -rf "$R/.superpowers" "$R/.forge" "$R/docs/superpowers" "$R/docs/forge"
mkdir -p "$WG/dr-superpowers" "$WG/dr-forge" "$G/.superpowers" "$G/.forge"
check "mixed: a worktree's git dir and the primary's state, both names" "$(dagents_legacy_layout "$W" | tr '\n' '|')" "$WG/dr-superpowers|$WG/dr-forge|$TOP/.superpowers|$TOP/.forge|"
rm -rf "$WG/dr-superpowers" "$WG/dr-forge" "$G/.superpowers" "$G/.forge"
SAVED_HOME=$HOME
export HOME="$TMP/home4"; mkdir -p "$HOME/.dr-forge"
printf '{}\n' > "$HOME/.dr-forge/config.json"
check "mixed: the old home beside a checkout's older path" "$(mkdir -p "$R/.superpowers"; dagents_legacy_layout "$R" | tr '\n' '|')" "$HOME/.dr-forge|$R/.superpowers|"
rm -rf "$R/.superpowers"
export HOME=$SAVED_HOME

# --- dagents_legacy_layout: the primary checkout's own .forge ---
GD=$(git -C "$G" rev-parse --absolute-git-dir)
mkdir -p "$G/.forge" "$GD/dr-forge"
check "primary: its .forge and git dir, each named once" "$(dagents_legacy_layout "$G" | tr '\n' '|')" "$G/.forge|$GD/dr-forge|"
rm -rf "$G/.forge" "$GD/dr-forge"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
