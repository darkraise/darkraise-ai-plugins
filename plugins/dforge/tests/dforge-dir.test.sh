#!/usr/bin/env bash
# dforge_dir: always the 3.0 directory; dforge_legacy_layout names the pre-3.0 ones.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/lib/dforge-dir.sh"

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

check "neither: state" "$(dforge_dir state "$R")" "$R/.dforge"
check "neither: docs" "$(dforge_dir docs "$R")" "$R/docs/dforge"

check "neither: no legacy layout" "$(dforge_legacy_layout "$R")" ""

mkdir -p "$R/.superpowers" "$R/docs/superpowers"
check "only old: state is still .dforge" "$(dforge_dir state "$R")" "$R/.dforge"
check "only old: docs is still docs/dforge" "$(dforge_dir docs "$R")" "$R/docs/dforge"
check "only old: relative docs" "$(dforge_dir_rel docs "$R")" "docs/dforge"
check "only old: legacy layout named" "$(dforge_legacy_layout "$R" | tr '\n' '|')" "$R/.superpowers|$R/docs/superpowers|"

rm -rf "$R/.superpowers" "$R/docs/superpowers"
check "removed: no legacy layout" "$(dforge_legacy_layout "$R")" ""

check "default root" "$(cd "$R" && dforge_dir state)" "./.dforge"
check "default root, relative" "$(cd "$R" && dforge_dir_rel state)" ".dforge"

dforge_dir other "$R" > /dev/null 2>&1
check "unknown kind: exit 2" "$?" "2"

# --- dforge-path: the directory for the repository at hand ---
G="$TMP/git"
git init -q "$G"
TOP=$(cd "$G" && git rev-parse --show-toplevel)
check "dforge-path: new checkout" "$(cd "$G" && bash "$HERE/../scripts/dforge-path" docs specs)" "$TOP/docs/dforge/specs"
mkdir -p "$G/.superpowers"
check "dforge-path: a pre-3.0 directory is not used" "$(cd "$G" && bash "$HERE/../scripts/dforge-path" state)" "$TOP/.dforge"
rm -rf "$G/.superpowers"
(cd "$G" && bash "$HERE/../scripts/dforge-path" > /dev/null 2>&1)
check "dforge-path: usage exit 2" "$?" "2"

# --- dforge-path: the families' roots and names ---
. "$HERE/fixtures/darkmem-stores.sh"
H=$HOME
git -C "$G" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
FP="$HERE/../scripts/dforge-path"
check "dforge-path: ledger, local" "$(cd "$G" && HOME=$H bash "$FP" ledger p1)" "$TOP/.dforge/sdd/p1"
check "dforge-path: latest, local" "$(cd "$G" && HOME=$H bash "$FP" latest)" "$TOP/.dforge/handoff/latest.md"
check "dforge-path: store, local" "$(cd "$G" && HOME=$H bash "$FP" store | tr '\n' '|')" "documents local|progress local|"
M=$(stores_home "$H" "$G" proj darkmem darkmem)
check "dforge-path: docs, darkmem" "$(cd "$G" && HOME=$H bash "$FP" docs plans/p1.md)" "$M/dforge/plans/p1.md"
check "dforge-path: ledger, darkmem" "$(cd "$G" && HOME=$H bash "$FP" ledger p1)" "$M/work/sdd/p1"
check "dforge-path: latest, darkmem" "$(cd "$G" && HOME=$H bash "$FP" latest)" "$M/work/handoff/latest.md"
check "dforge-path: state stays local" "$(cd "$G" && HOME=$H bash "$FP" state)" "$TOP/.dforge"
check "dforge-path: store, darkmem" "$(cd "$G" && HOME=$H bash "$FP" store | tr '\n' '|')" "documents darkmem|progress darkmem|"
check "dforge-path: name" "$(cd "$G" && HOME=$H bash "$FP" name "$M/dforge/plans/p1.md")" "docs/dforge/plans/p1.md"
(cd "$G" && HOME=$H bash "$FP" ledger > /dev/null 2>&1)
check "dforge-path: ledger needs a slug" "$?" "2"

# --- dforge_legacy_layout: a linked worktree's git dir and the primary's state ---
W="$TMP/wt"
git -C "$G" worktree add -q --detach "$W"
WG=$(git -C "$W" rev-parse --absolute-git-dir)
mkdir -p "$WG/dr-superpowers" "$G/.superpowers"
check "worktree: its git dir and the primary's state" "$(dforge_legacy_layout "$W" | tr '\n' '|')" "$WG/dr-superpowers|$TOP/.superpowers|"
rm -rf "$WG/dr-superpowers" "$G/.superpowers"
check "worktree: nothing left" "$(dforge_legacy_layout "$W")" ""

# --- dforge_legacy_layout: an unmigrated home ---
SAVED_HOME=$HOME
export HOME="$TMP/home2"; mkdir -p "$HOME"
OLDH="$HOME/.dr-superpowers"
NEWH="$HOME/.dforge"
mkdir -p "$OLDH"
printf '{"darkmem":{"repos":{}}}\n' > "$OLDH/config.json"
check "home: old darkmem mapping, new home lacks it" "$(dforge_legacy_layout "$R")" "$OLDH"
mkdir -p "$NEWH"
printf '{"darkmemEnabled":true}\n' > "$NEWH/config.json"
check "home: a new config without the mapping still counts" "$(dforge_legacy_layout "$R")" "$OLDH"
printf '{"darkmem":{"repos":{}}}\n' > "$NEWH/config.json"
check "home: the new config holds the mapping" "$(dforge_legacy_layout "$R")" ""
printf '{"darkmemEnabled":true}\n' > "$OLDH/config.json"
check "home: an old config without a mapping" "$(dforge_legacy_layout "$R")" ""
mkdir -p "$OLDH/mirror"
check "home: an empty old mirror folder" "$(dforge_legacy_layout "$R")" ""
mkdir -p "$OLDH/mirror/proj"
check "home: a mirror left in the old home" "$(dforge_legacy_layout "$R")" "$OLDH"
printf '{"darkmem":{}}\n' > "$OLDH/config.json"
rm -rf "$NEWH" "$OLDH/mirror/proj"
check "home: reported once beside a repository path" "$(mkdir -p "$R/.superpowers"; dforge_legacy_layout "$R" | tr '\n' '|')" "$OLDH|$R/.superpowers|"
rm -rf "$R/.superpowers" "$OLDH"
export HOME=$SAVED_HOME

# --- dforge_legacy_layout: dr-forge's 3.x names ---
mkdir -p "$R/.forge" "$R/docs/forge"
check "dr-forge: state and docs" "$(dforge_legacy_layout "$R" | tr '\n' '|')" "$R/.forge|$R/docs/forge|"
rm -rf "$R/.forge" "$R/docs/forge"
mkdir -p "$WG/dr-forge" "$G/.forge"
check "dr-forge: a worktree's git dir and the primary's state" "$(dforge_legacy_layout "$W" | tr '\n' '|')" "$WG/dr-forge|$TOP/.forge|"
rm -rf "$WG/dr-forge" "$G/.forge"
SAVED_HOME=$HOME
export HOME="$TMP/home3"; mkdir -p "$HOME/.dr-forge"
check "dr-forge: an empty ~/.dr-forge is not named" "$(dforge_legacy_layout "$R")" ""
printf '{}\n' > "$HOME/.dr-forge/config.json"
check "dr-forge: a ~/.dr-forge holding anything is named" "$(dforge_legacy_layout "$R")" "$HOME/.dr-forge"
export HOME=$SAVED_HOME

# Codex runs no session-start hook, so its tool notes carry the check.
check "codex-tools: names the pre-3.0 check" "$(grep -c 'pre-3.0 layout' "$HERE/../skills/using-dforge/references/codex-tools.md")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
