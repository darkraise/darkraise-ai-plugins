#!/usr/bin/env bash
# Exercise executable documentation examples and pin their routing contracts.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
pass=0 fail=0
check() {
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s: got [%s], want [%s]\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi
}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

W="$P/skills/using-git-worktrees/SKILL.md"
git init -q "$TMP/repo"
mkdir "$TMP/repo/.worktrees" "$TMP/repo/worktrees"
printf 'worktrees/\n' > "$TMP/repo/.gitignore"
ignore_command=$(grep '^git check-ignore' "$W")
(cd "$TMP/repo" && LOCATION=.worktrees bash -c "$ignore_command")
check 'ignore example refuses the selected unignored directory' "$?" 1
(cd "$TMP/repo" && LOCATION=worktrees bash -c "$ignore_command")
check 'ignore example accepts the selected ignored directory' "$?" 0

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
