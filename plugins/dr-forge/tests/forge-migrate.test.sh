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
echo old > "$B/.superpowers/clash.md"
echo new > "$B/.forge/clash.md"
printf '.superpowers/\n' > "$B/.gitignore"
out=$(bash "$FM" "$B" 2>&1); code=$?
check "both: exit 1" "$code" "1"
check "both: refusal names the differing file" "$(grep -c "refused: $B/.superpowers/clash.md differs from $B/.forge/clash.md" <<<"$out")" "1"
check "both: differing file kept in .superpowers" "$(cat "$B/.superpowers/clash.md")" "old"
check "both: .forge file untouched" "$(cat "$B/.forge/clash.md")" "new"
check "both: untracked docs still moved" "$(exists "$B/docs/forge")" "yes"
check "both: the new pattern is added beside the old" "$(cat "$B/.gitignore")" $'.superpowers/\n.forge/'
rm "$B/.superpowers/clash.md"
out=$(bash "$FM" "$B" 2>&1); code=$?
check "both resolved: exit 0" "$code" "0"
check "both resolved: .superpowers gone" "$(exists "$B/.superpowers")" "no"
check "both resolved: the old pattern is replaced, not duplicated" "$(cat "$B/.gitignore")" ".forge/"

# --- .superpowers and .forge both present: merged file by file ---
M="$TMP/merge"
repo "$M"
mkdir -p "$M/.superpowers/sub" "$M/.forge"
echo a > "$M/.superpowers/only-old.md"
echo b > "$M/.superpowers/sub/deep.md"
echo same > "$M/.superpowers/same.md"
echo same > "$M/.forge/same.md"
echo c > "$M/.forge/only-new.md"
out=$(bash "$FM" "$M" 2>&1); code=$?
check "merge: exit 0" "$code" "0"
check "merge: old-only file moved" "$(cat "$M/.forge/only-old.md" 2>/dev/null)" "a"
check "merge: nested old-only file moved" "$(cat "$M/.forge/sub/deep.md" 2>/dev/null)" "b"
check "merge: new-only file kept" "$(cat "$M/.forge/only-new.md" 2>/dev/null)" "c"
check "merge: identical file kept once" "$(cat "$M/.forge/same.md" 2>/dev/null)" "same"
check "merge: .superpowers gone" "$(exists "$M/.superpowers")" "no"

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

# --- a refused checkout never leaves a moved .forge/ un-ignored ---
G="$TMP/partial"
repo "$G"
mkdir -p "$G/.superpowers" "$G/docs/superpowers"
echo one > "$G/docs/superpowers/a.md"
printf '.superpowers/\n' > "$G/.gitignore"
git -C "$G" add docs .gitignore
git -C "$G" commit -q -m docs
echo two > "$G/docs/superpowers/a.md"
echo 'docs/superpowers/local/' >> "$G/.git/info/exclude"
out=$(bash "$FM" "$G" 2>&1); code=$?
check "partial: exit 1" "$code" "1"
check "partial: .superpowers moved" "$(exists "$G/.forge")" "yes"
check "partial: .gitignore ignores both names" "$(cat "$G/.gitignore")" $'.superpowers/\n.forge/'
check "partial: info/exclude names both" "$(tail -n 2 "$G/.git/info/exclude" | tr '\n' ' ')" "docs/superpowers/local/ docs/forge/local/ "
out=$(bash "$FM" "$G" 2>&1)
check "partial again: ignore files unchanged, nothing rewritten" "$(grep -c '^rewrote' <<<"$out")" "0"
check "partial again: .gitignore not duplicated" "$(cat "$G/.gitignore")" $'.superpowers/\n.forge/'
git -C "$G" checkout -q -- docs
out=$(bash "$FM" "$G" 2>&1); code=$?
check "partial resolved: exit 0" "$code" "0"
check "partial resolved: .gitignore holds only the new name" "$(cat "$G/.gitignore")" ".forge/"
check "partial resolved: info/exclude holds only the new name" "$(tail -n 1 "$G/.git/info/exclude")" "docs/forge/local/"
check "partial resolved: info/exclude has no old line" "$(grep -c 'docs/superpowers' "$G/.git/info/exclude")" "0"

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
check "darkmem-migrate moved the home: not reported as nothing to migrate" "$(grep -c 'nothing to migrate' <<<"$out")" "0"
printf 'process.exit(3);\n' > "$P/lib/darkmem-migrate.mjs"
out=$(bash "$P/forge-migrate" "$H" 2>&1); code=$?
check "darkmem-migrate fails: exit 1" "$code" "1"
check "darkmem-migrate fails: refused" "$(grep -c 'refused: scripts/lib/darkmem-migrate.mjs' <<<"$out")" "1"

# --- no Node: refused only when there is a home to migrate ---
NB="$TMP/nonode-bin"
mkdir -p "$NB"
for c in git timeout dirname tr sed head grep mv rm cat find cmp mkdir awk readlink sort mktemp cp bash; do
  src=$(type -P "$c") && ln -s "$src" "$NB/$c"
done
printf 'console.log("x");\n' > "$P/lib/darkmem-migrate.mjs"
NH="$TMP/no-home"
mkdir -p "$NH"
out=$(HOME="$NH" PATH="$NB" bash "$P/forge-migrate" "$H" 2>&1); code=$?
check "no node, no old home: exit 0" "$code" "0"
check "no node, no old home: nothing to migrate" "$out" "forge-migrate: nothing to migrate in $H"
mkdir -p "$NH/.dr-superpowers"
out=$(HOME="$NH" PATH="$NB" bash "$P/forge-migrate" "$H" 2>&1); code=$?
check "no node, old home present: exit 1" "$code" "1"
check "no node, old home present: refused" "$(grep -c 'refused: node is not on PATH' <<<"$out")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
