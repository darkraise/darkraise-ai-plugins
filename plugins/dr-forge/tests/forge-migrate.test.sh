#!/usr/bin/env bash
# forge-migrate: a pre-3.0 repository's checkouts move to the 3.0 names.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM="$HERE/../scripts/forge-migrate"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then pass=$((pass + 1))
  else printf 'FAIL - %s\n       got:  [%s]\n       want: [%s]\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi
}
exists() { [ -e "$1" ] && echo yes || echo no; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

repo() { # repo DIR — a repository with one commit
  git init -q -b main "$1"
  git -C "$1" commit -q --allow-empty -m init
}

# --- a primary checkout and a linked worktree, both pre-3.0 ---
R="$TMP/repo"
repo "$R"
mkdir -p "$R/.superpowers/sdd/p1" "$R/docs/superpowers/plans"
echo ledger > "$R/.superpowers/sdd/p1/progress.md"
echo 'see docs/superpowers/specs/s.md' > "$R/docs/superpowers/plans/p.md"
printf '.superpowers/\n*.tmp\n' > "$R/.gitignore"
printf '* text=auto\ndocs/superpowers/** linguist-documentation\n' > "$R/.gitattributes"
git -C "$R" add .gitignore .gitattributes docs
git -C "$R" commit -q -m docs
echo scratch > "$R/docs/superpowers/scratch.tmp"
echo 'docs/superpowers/local/' >> "$R/.git/info/exclude"
W="$TMP/wt"
git -C "$R" worktree add -q -b feature "$W"
mkdir -p "$W/.superpowers/handoff"
echo handoff > "$W/.superpowers/handoff/latest.md"
WG=$(git -C "$W" rev-parse --absolute-git-dir)
mkdir -p "$WG/dr-superpowers/tasks"

out=$(bash "$FM" "$W" 2>&1); code=$?
check "migrate: exit 0" "$code" "0"
check "primary: .forge holds the ledger" "$(cat "$R/.forge/sdd/p1/progress.md" 2>/dev/null)" "ledger"
check "primary: .superpowers gone" "$(exists "$R/.superpowers")" "no"
check "primary: docs moved" "$(cat "$R/docs/forge/plans/p.md" 2>/dev/null)" "see docs/superpowers/specs/s.md"
check "primary: docs/superpowers gone" "$(exists "$R/docs/superpowers")" "no"
check "primary: the ignored file moved with the docs" "$(exists "$R/docs/forge/scratch.tmp")" "yes"
check "primary: the rename is staged" "$(git -C "$R" status --porcelain -- docs | cut -c1-2 | sort -u | tr -d ' ')" "R"
check "primary: .gitignore rewritten" "$(head -n 1 "$R/.gitignore")" ".forge/"
check "primary: .gitattributes rewritten" "$(sed -n 2p "$R/.gitattributes")" "docs/forge/** linguist-documentation"
check "primary: info/exclude rewritten" "$(tail -n 1 "$R/.git/info/exclude")" "docs/forge/local/"
check "worktree: .forge holds the handoff" "$(cat "$W/.forge/handoff/latest.md" 2>/dev/null)" "handoff"
check "worktree: docs moved from its own branch" "$(exists "$W/docs/forge/plans/p.md")" "yes"
check "worktree: git dir state moved" "$(exists "$WG/dr-forge/tasks")" "yes"
check "worktree: dr-superpowers gone" "$(exists "$WG/dr-superpowers")" "no"
check "prints the commit the user must make" "$(grep -c "^commit: $R: the staged rename" <<<"$out")" "1"
check "names the tracked ignore file" "$(grep -c "^commit: $R: .gitignore" <<<"$out")" "1"

out=$(bash "$FM" "$R" 2>&1); code=$?
check "second run: exit 0" "$code" "0"
check "second run: nothing to migrate" "$out" "forge-migrate: nothing to migrate in $R"

# --- refusals leave the checkout as it is ---
B="$TMP/both"
repo "$B"
mkdir -p "$B/.superpowers" "$B/.forge" "$B/docs/superpowers"
printf '.superpowers/\n' > "$B/.gitignore"
out=$(bash "$FM" "$B" 2>&1); code=$?
check "both: exit 1" "$code" "1"
check "both: refusal names the pair" "$(grep -c "refused: $B/.superpowers and $B/.forge both exist" <<<"$out")" "1"
check "both: .superpowers kept" "$(exists "$B/.superpowers")" "yes"
check "both: untracked docs still moved" "$(exists "$B/docs/forge")" "yes"
check "both: no ignore rewrite after a refusal" "$(cat "$B/.gitignore")" ".superpowers/"

D="$TMP/dirty"
repo "$D"
mkdir -p "$D/docs/superpowers"
echo one > "$D/docs/superpowers/a.md"
git -C "$D" add docs
git -C "$D" commit -q -m docs
echo two > "$D/docs/superpowers/a.md"
out=$(bash "$FM" "$D" 2>&1); code=$?
check "dirty docs: exit 1" "$code" "1"
check "dirty docs: refused" "$(grep -c 'has uncommitted changes' <<<"$out")" "1"
check "dirty docs: left in place" "$(cat "$D/docs/superpowers/a.md")" "two"

E="$TMP/both-docs"
repo "$E"
mkdir -p "$E/docs/superpowers" "$E/docs/forge"
bash "$FM" "$E" > /dev/null 2>&1
check "both docs: exit 1" "$?" "1"

bash "$FM" "$TMP/home" > /dev/null 2>&1
check "outside git: exit 2" "$?" "2"

# --- the home step runs when darkmem-migrate.mjs is installed ---
P="$TMP/plugin/scripts"
mkdir -p "$P/lib"
cp "$FM" "$P/forge-migrate"
cp "$HERE/../scripts/lib/native-path.sh" "$P/lib/"
H="$TMP/home-step"
repo "$H"
check "no darkmem-migrate: nothing to do" "$(bash "$P/forge-migrate" "$H" 2>&1)" "forge-migrate: nothing to migrate in $H"
printf 'console.log("home migrated");\n' > "$P/lib/darkmem-migrate.mjs"
out=$(bash "$P/forge-migrate" "$H" 2>&1); code=$?
check "darkmem-migrate: exit 0" "$code" "0"
check "darkmem-migrate: its output shown" "$(grep -c 'home migrated' <<<"$out")" "1"
printf 'process.exit(3);\n' > "$P/lib/darkmem-migrate.mjs"
out=$(bash "$P/forge-migrate" "$H" 2>&1); code=$?
check "darkmem-migrate fails: exit 1" "$code" "1"
check "darkmem-migrate fails: refused" "$(grep -c 'refused: scripts/lib/darkmem-migrate.mjs' <<<"$out")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
