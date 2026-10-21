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
names() { check "$1" "$(grep -qF -- "$3" "$2" && echo yes || echo no)" yes; }
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
names 'setup honors the declared package manager' "$W" '`packageManager` in `package.json`'
names 'Python setup identifies tooling' "$W" 'A `pyproject.toml` with none of those files names no tool'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
