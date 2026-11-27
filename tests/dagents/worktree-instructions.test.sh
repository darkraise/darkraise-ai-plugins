#!/usr/bin/env bash
# Exercise executable documentation examples and pin their routing contracts.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/../../plugins/dagents"
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

# The Node block of Step 2, run against stub package managers.
node_block=$(awk '/^# Node\.js$/ { on = 1; next } on && /^$/ { exit } on' "$P/skills/using-git-worktrees/SKILL.md")
node_setup() { # node_setup <packageManager> <stub version> — the commands the block ran
  local d="$TMP/node-$RANDOM" name
  mkdir -p "$d/bin" "$d/work"
  for name in npm bun pnpm yarn corepack npx; do
    printf '#!/bin/sh\nif [ "$1" = --version ]; then echo %s; exit 0; fi\necho "%s $*" >> "%s/log"\n' "$2" "$name" "$d" > "$d/bin/$name"
    chmod +x "$d/bin/$name"
  done
  printf '{"packageManager": "%s"}\n' "$1" > "$d/work/package.json"
  (cd "$d/work" && PATH="$d/bin:$PATH" bash -c "$node_block") >/dev/null 2>&1
  cat "$d/log" 2>/dev/null
}
check 'node setup example runs the declared npm version' "$(node_setup 'npm@10.9.0+sha512.abc' 10.1.0)" 'npx --yes npm@10.9.0 install'
check 'node setup example runs the declared bun version' "$(node_setup 'bun@1.1.30' 1.0.0)" 'npx --yes bun@1.1.30 install'
check 'node setup example uses an installed npm at the declared version' "$(node_setup 'npm@10.9.0' 10.9.0)" 'npm install'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
