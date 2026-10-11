#!/usr/bin/env bash
# forge_dir: the new directory unless only the pre-2.0 one exists.
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
R="$TMP/repo"
mkdir -p "$R"

check "neither: state" "$(forge_dir state "$R")" "$R/.forge"
check "neither: docs" "$(forge_dir docs "$R")" "$R/docs/forge"

mkdir -p "$R/.superpowers" "$R/docs/superpowers"
check "only old: state" "$(forge_dir state "$R")" "$R/.superpowers"
check "only old: docs" "$(forge_dir docs "$R")" "$R/docs/superpowers"
check "only old: relative state" "$(forge_dir_rel state "$R")" ".superpowers"
check "only old: relative docs" "$(forge_dir_rel docs "$R")" "docs/superpowers"

mkdir -p "$R/.forge" "$R/docs/forge"
check "both: state" "$(forge_dir state "$R")" "$R/.forge"
check "both: docs" "$(forge_dir docs "$R")" "$R/docs/forge"

rm -rf "$R/.superpowers" "$R/docs/superpowers"
check "only new: state" "$(forge_dir state "$R")" "$R/.forge"
check "only new: relative docs" "$(forge_dir_rel docs "$R")" "docs/forge"

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
check "forge-path: pre-2.0 state" "$(cd "$G" && bash "$HERE/../scripts/forge-path" state)" "$TOP/.superpowers"
(cd "$G" && bash "$HERE/../scripts/forge-path" > /dev/null 2>&1)
check "forge-path: usage exit 2" "$?" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
