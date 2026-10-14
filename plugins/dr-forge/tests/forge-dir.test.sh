#!/usr/bin/env bash
# forge_dir: always the 3.0 directory; forge_legacy_layout names the pre-3.0 ones.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/lib/forge-dir.sh"

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

check "neither: state" "$(forge_dir state "$R")" "$R/.forge"
check "neither: docs" "$(forge_dir docs "$R")" "$R/docs/forge"

check "neither: no legacy layout" "$(forge_legacy_layout "$R")" ""

mkdir -p "$R/.superpowers" "$R/docs/superpowers"
check "only old: state is still .forge" "$(forge_dir state "$R")" "$R/.forge"
check "only old: docs is still docs/forge" "$(forge_dir docs "$R")" "$R/docs/forge"
check "only old: relative docs" "$(forge_dir_rel docs "$R")" "docs/forge"
check "only old: legacy layout named" "$(forge_legacy_layout "$R" | tr '\n' '|')" "$R/.superpowers|$R/docs/superpowers|"

rm -rf "$R/.superpowers" "$R/docs/superpowers"
check "removed: no legacy layout" "$(forge_legacy_layout "$R")" ""

check "default root" "$(cd "$R" && forge_dir state)" "./.forge"
check "default root, relative" "$(cd "$R" && forge_dir_rel state)" ".forge"

forge_dir other "$R" > /dev/null 2>&1
check "unknown kind: exit 2" "$?" "2"

# --- forge-path: the directory for the repository at hand ---
G="$TMP/git"
git init -q "$G"
TOP=$(cd "$G" && git rev-parse --show-toplevel)
check "forge-path: new checkout" "$(cd "$G" && bash "$HERE/../scripts/forge-path" docs specs)" "$TOP/docs/forge/specs"
mkdir -p "$G/.superpowers"
check "forge-path: a pre-3.0 directory is not used" "$(cd "$G" && bash "$HERE/../scripts/forge-path" state)" "$TOP/.forge"
rm -rf "$G/.superpowers"
(cd "$G" && bash "$HERE/../scripts/forge-path" > /dev/null 2>&1)
check "forge-path: usage exit 2" "$?" "2"

# --- forge-path: the families' roots and names ---
. "$HERE/fixtures/darkmem-stores.sh"
H=$HOME
git -C "$G" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
FP="$HERE/../scripts/forge-path"
check "forge-path: ledger, local" "$(cd "$G" && HOME=$H bash "$FP" ledger p1)" "$TOP/.forge/sdd/p1"
check "forge-path: latest, local" "$(cd "$G" && HOME=$H bash "$FP" latest)" "$TOP/.forge/handoff/latest.md"
check "forge-path: store, local" "$(cd "$G" && HOME=$H bash "$FP" store | tr '\n' '|')" "documents local|progress local|"
M=$(stores_home "$H" "$G" proj darkmem darkmem)
check "forge-path: docs, darkmem" "$(cd "$G" && HOME=$H bash "$FP" docs plans/p1.md)" "$M/superpowers/plans/p1.md"
check "forge-path: ledger, darkmem" "$(cd "$G" && HOME=$H bash "$FP" ledger p1)" "$M/work/sdd/p1"
check "forge-path: latest, darkmem" "$(cd "$G" && HOME=$H bash "$FP" latest)" "$M/work/handoff/latest.md"
check "forge-path: state stays local" "$(cd "$G" && HOME=$H bash "$FP" state)" "$TOP/.forge"
check "forge-path: store, darkmem" "$(cd "$G" && HOME=$H bash "$FP" store | tr '\n' '|')" "documents darkmem|progress darkmem|"
check "forge-path: name" "$(cd "$G" && HOME=$H bash "$FP" name "$M/superpowers/plans/p1.md")" "docs/forge/plans/p1.md"
(cd "$G" && HOME=$H bash "$FP" ledger > /dev/null 2>&1)
check "forge-path: ledger needs a slug" "$?" "2"

# --- forge_legacy_layout: a linked worktree's git dir and the primary's state ---
W="$TMP/wt"
git -C "$G" worktree add -q --detach "$W"
WG=$(git -C "$W" rev-parse --absolute-git-dir)
mkdir -p "$WG/dr-superpowers" "$G/.superpowers"
check "worktree: its git dir and the primary's state" "$(forge_legacy_layout "$W" | tr '\n' '|')" "$WG/dr-superpowers|$TOP/.superpowers|"
rm -rf "$WG/dr-superpowers" "$G/.superpowers"
check "worktree: nothing left" "$(forge_legacy_layout "$W")" ""

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
