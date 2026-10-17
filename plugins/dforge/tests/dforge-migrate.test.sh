#!/usr/bin/env bash
# dforge-migrate: a pre-3.0 repository's checkouts move to the 3.0 names.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM="$HERE/../scripts/dforge-migrate"

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
check "primary: .dforge holds the ledger" "$(cat "$R/.dforge/sdd/p1/progress.md" 2>/dev/null)" "ledger"
check "primary: .superpowers gone" "$(exists "$R/.superpowers")" "no"
check "primary: docs moved" "$(cat "$R/docs/dforge/plans/p.md" 2>/dev/null)" "see docs/superpowers/specs/s.md"
check "primary: docs/superpowers gone" "$(exists "$R/docs/superpowers")" "no"
check "primary: the ignored file moved with the docs" "$(exists "$R/docs/dforge/scratch.tmp")" "yes"
check "primary: the rename is staged" "$(git -C "$R" status --porcelain -- docs | cut -c1-2 | sort -u | tr -d ' ')" "R"
check "primary: .gitignore rewritten" "$(head -n 1 "$R/.gitignore")" ".dforge/"
check "primary: .gitattributes rewritten" "$(sed -n 2p "$R/.gitattributes")" "docs/dforge/** linguist-documentation"
check "primary: info/exclude rewritten" "$(tail -n 1 "$R/.git/info/exclude")" "docs/dforge/local/"
check "worktree: .dforge holds the handoff" "$(cat "$W/.dforge/handoff/latest.md" 2>/dev/null)" "handoff"
check "worktree: docs moved from its own branch" "$(exists "$W/docs/dforge/plans/p.md")" "yes"
check "worktree: git dir state moved" "$(exists "$WG/dforge/tasks")" "yes"
check "worktree: dr-superpowers gone" "$(exists "$WG/dr-superpowers")" "no"
check "prints the commit the user must make" "$(grep -c "^commit: $R: the staged rename" <<<"$out")" "1"
check "names the tracked ignore file" "$(grep -c "^commit: $R: .gitignore" <<<"$out")" "1"

out=$(bash "$FM" "$R" 2>&1); code=$?
check "second run: exit 0" "$code" "0"
check "second run: nothing to migrate" "$out" "dforge-migrate: nothing to migrate in $R"

# --- refusals leave the checkout as it is ---
B="$TMP/both"
repo "$B"
mkdir -p "$B/.superpowers" "$B/.dforge" "$B/docs/superpowers"
echo old > "$B/.superpowers/clash.md"
echo new > "$B/.dforge/clash.md"
printf '.superpowers/\n' > "$B/.gitignore"
out=$(bash "$FM" "$B" 2>&1); code=$?
check "both: exit 1" "$code" "1"
check "both: refusal names the differing file" "$(grep -c "refused: $B/.superpowers/clash.md differs from $B/.dforge/clash.md" <<<"$out")" "1"
check "both: differing file kept in .superpowers" "$(cat "$B/.superpowers/clash.md")" "old"
check "both: .dforge file untouched" "$(cat "$B/.dforge/clash.md")" "new"
check "both: untracked docs still moved" "$(exists "$B/docs/dforge")" "yes"
check "both: the new pattern is added beside the old" "$(cat "$B/.gitignore")" $'.superpowers/\n.dforge/'
rm "$B/.superpowers/clash.md"
out=$(bash "$FM" "$B" 2>&1); code=$?
check "both resolved: exit 0" "$code" "0"
check "both resolved: .superpowers gone" "$(exists "$B/.superpowers")" "no"
check "both resolved: the old pattern is replaced, not duplicated" "$(cat "$B/.gitignore")" ".dforge/"

# --- .superpowers and .dforge both present: merged file by file ---
M="$TMP/merge"
repo "$M"
mkdir -p "$M/.superpowers/sub" "$M/.dforge"
echo a > "$M/.superpowers/only-old.md"
echo b > "$M/.superpowers/sub/deep.md"
echo same > "$M/.superpowers/same.md"
echo same > "$M/.dforge/same.md"
echo c > "$M/.dforge/only-new.md"
out=$(bash "$FM" "$M" 2>&1); code=$?
check "merge: exit 0" "$code" "0"
check "merge: old-only file moved" "$(cat "$M/.dforge/only-old.md" 2>/dev/null)" "a"
check "merge: nested old-only file moved" "$(cat "$M/.dforge/sub/deep.md" 2>/dev/null)" "b"
check "merge: new-only file kept" "$(cat "$M/.dforge/only-new.md" 2>/dev/null)" "c"
check "merge: identical file kept once" "$(cat "$M/.dforge/same.md" 2>/dev/null)" "same"
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

# --- a refused checkout never leaves a moved .dforge/ un-ignored ---
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
check "partial: .superpowers moved" "$(exists "$G/.dforge")" "yes"
check "partial: .gitignore ignores both names" "$(cat "$G/.gitignore")" $'.superpowers/\n.dforge/'
check "partial: info/exclude names both" "$(tail -n 2 "$G/.git/info/exclude" | tr '\n' ' ')" "docs/superpowers/local/ docs/dforge/local/ "
out=$(bash "$FM" "$G" 2>&1)
check "partial again: ignore files unchanged, nothing rewritten" "$(grep -c '^rewrote' <<<"$out")" "0"
check "partial again: .gitignore not duplicated" "$(cat "$G/.gitignore")" $'.superpowers/\n.dforge/'
git -C "$G" checkout -q -- docs
out=$(bash "$FM" "$G" 2>&1); code=$?
check "partial resolved: exit 0" "$code" "0"
check "partial resolved: .gitignore holds only the new name" "$(cat "$G/.gitignore")" ".dforge/"
check "partial resolved: info/exclude holds only the new name" "$(tail -n 1 "$G/.git/info/exclude")" "docs/dforge/local/"
check "partial resolved: info/exclude has no old line" "$(grep -c 'docs/superpowers' "$G/.git/info/exclude")" "0"

E="$TMP/both-docs"
repo "$E"
mkdir -p "$E/docs/superpowers" "$E/docs/dforge"
bash "$FM" "$E" > /dev/null 2>&1
check "both docs: exit 1" "$?" "1"

bash "$FM" "$TMP/home" > /dev/null 2>&1
check "outside git: exit 2" "$?" "2"

# --- a dr-forge repository: .forge/, docs/forge/, <git dir>/dr-forge/ ---
F="$TMP/forge"
repo "$F"
mkdir -p "$F/.forge/sdd/p1" "$F/.forge/handoff" "$F/docs/forge/plans" "$F/docs/forge/specs" "$F/.git/dr-forge/tasks"
echo ledger > "$F/.forge/sdd/p1/progress.md"
printf 'Resume with dr-forge:resume-execution\n' > "$F/.forge/handoff/latest.md"
printf '> REQUIRED SUB-SKILL: dr-forge:subagent-driven-development\n**Implementer:** `dr-forge:impl-sonnet-low`\nsee dr-superpowers:executing-plans\n' > "$F/docs/forge/plans/active.md"
printf '**Implementer:** dr-forge:impl-sonnet-low\n' > "$F/docs/forge/plans/done.md"
printf -- '- 2026-10-01 `docs/forge/plans/done.md` — merged into `main` at abc1234\n' > "$F/docs/forge/plans/completed.md"
printf 'use dr-forge:brainstorming\n' > "$F/docs/forge/specs/s.md"
printf '.forge/\n' > "$F/.gitignore"
printf 'docs/forge/** linguist-documentation\n' > "$F/.gitattributes"
git -C "$F" add .gitignore .gitattributes docs
git -C "$F" commit -q -m docs
out=$(bash "$FM" "$F" 2>&1); code=$?
check "dr-forge: exit 0" "$code" "0"
check "dr-forge: .dforge holds the ledger" "$(cat "$F/.dforge/sdd/p1/progress.md" 2>/dev/null)" "ledger"
check "dr-forge: .forge gone" "$(exists "$F/.forge")" "no"
check "dr-forge: docs moved" "$(exists "$F/docs/dforge/specs/s.md")" "yes"
check "dr-forge: docs/forge gone" "$(exists "$F/docs/forge")" "no"
check "dr-forge: the rename is staged" "$(git -C "$F" status --porcelain -- docs/dforge/specs docs/forge/specs | cut -c1-2 | sort -u | tr -d ' ')" "R"
check "dr-forge: git dir state moved" "$(exists "$F/.git/dforge/tasks")" "yes"
check "dr-forge: .gitignore rewritten" "$(cat "$F/.gitignore")" ".dforge/"
check "dr-forge: .gitattributes rewritten" "$(cat "$F/.gitattributes")" "docs/dforge/** linguist-documentation"
check "dr-forge: the active plan's prefixes rewritten" "$(cat "$F/docs/dforge/plans/active.md")" \
  $'> REQUIRED SUB-SKILL: dforge:subagent-driven-development\n**Implementer:** `dforge:impl-sonnet-low`\nsee dforge:executing-plans'
check "dr-forge: a finished plan keeps its text" "$(cat "$F/docs/dforge/plans/done.md")" "**Implementer:** dr-forge:impl-sonnet-low"
check "dr-forge: a spec keeps its text" "$(cat "$F/docs/dforge/specs/s.md")" "use dr-forge:brainstorming"
check "dr-forge: the handoff note's prefixes rewritten" "$(cat "$F/.dforge/handoff/latest.md")" "Resume with dforge:resume-execution"
check "dr-forge: names the staged rename" "$(grep -c "^commit: $F: the staged rename docs/forge/ -> docs/dforge/" <<<"$out")" "1"
check "dr-forge: names the rewritten plan" "$(grep -c "^commit: $F: docs/dforge/plans/active.md$" <<<"$out")" "1"
out=$(bash "$FM" "$F" 2>&1); code=$?
check "dr-forge again: exit 0" "$code" "0"
check "dr-forge again: nothing to migrate" "$out" "dforge-migrate: nothing to migrate in $F"

# --- .superpowers/ and .forge/ both present: both merged into .dforge/ ---
T="$TMP/two-states"
repo "$T"
mkdir -p "$T/.superpowers" "$T/.forge"
echo a > "$T/.superpowers/a.md"
echo b > "$T/.forge/b.md"
out=$(bash "$FM" "$T" 2>&1); code=$?
check "two states: exit 0" "$code" "0"
check "two states: both merged" "$(cat "$T/.dforge/a.md" "$T/.dforge/b.md" 2>/dev/null | tr '\n' ' ')" "a b "
check "two states: both gone" "$(exists "$T/.superpowers")$(exists "$T/.forge")" "nono"

# --- docs/forge/ beside docs/dforge/: refused, and no plan is rewritten ---
K="$TMP/forge-both-docs"
repo "$K"
mkdir -p "$K/docs/forge/plans" "$K/docs/dforge"
printf 'dr-forge:impl-sonnet-low\n' > "$K/docs/forge/plans/p.md"
out=$(bash "$FM" "$K" 2>&1); code=$?
check "forge and dforge docs: exit 1" "$code" "1"
check "forge and dforge docs: refusal names both" "$(grep -c "refused: $K/docs/forge and $K/docs/dforge all exist" <<<"$out")" "1"
check "forge and dforge docs: the plan is untouched" "$(cat "$K/docs/forge/plans/p.md")" "dr-forge:impl-sonnet-low"

# --- a cloned repository controls these names: nothing is written through a link ---
L="$TMP/links"
repo "$L"
mkdir -p "$TMP/outside/state/handoff" "$L/docs/dforge/plans"
printf 'dr-forge:resume-execution\n' > "$TMP/outside/note.md"
printf 'dr-forge:resume-execution\n' > "$TMP/outside/state/handoff/latest.md"
printf '.forge/\n' > "$TMP/outside/ignore"
mkdir -p "$L/.dforge/handoff"
ln -s "$TMP/outside/note.md" "$L/.dforge/handoff/latest.md"
ln -s "$TMP/outside/note.md" "$L/docs/dforge/plans/linked.md"
ln -s "$TMP/outside/ignore" "$L/.gitignore"
LL="$TMP/linked-state"
repo "$LL"
ln -s "$TMP/outside/state" "$LL/.forge"
bash "$FM" "$L" > /dev/null 2>&1
bash "$FM" "$LL" > /dev/null 2>&1
check "links: a linked handoff note is not rewritten" "$(cat "$TMP/outside/note.md")" "dr-forge:resume-execution"
check "links: a linked .gitignore is not rewritten" "$(cat "$TMP/outside/ignore")" ".forge/"
check "links: a state directory linked outside is not rewritten" "$(cat "$TMP/outside/state/handoff/latest.md")" "dr-forge:resume-execution"

# --- the home step runs when dforge-home-migrate.mjs is installed ---
P="$TMP/plugin/scripts"
mkdir -p "$P/lib"
cp "$FM" "$P/dforge-migrate"
cp "$HERE/../scripts/lib/native-path.sh" "$P/lib/"
H="$TMP/home-step"
repo "$H"
check "no dforge-home-migrate: nothing to do" "$(bash "$P/dforge-migrate" "$H" 2>&1)" "dforge-migrate: nothing to migrate in $H"
printf 'console.log("home migrated");\n' > "$P/lib/dforge-home-migrate.mjs"
out=$(bash "$P/dforge-migrate" "$H" 2>&1); code=$?
check "dforge-home-migrate: exit 0" "$code" "0"
check "dforge-home-migrate: its output shown" "$(grep -c 'home migrated' <<<"$out")" "1"
check "dforge-home-migrate moved the home: not reported as nothing to migrate" "$(grep -c 'nothing to migrate' <<<"$out")" "0"
printf 'process.exit(3);\n' > "$P/lib/dforge-home-migrate.mjs"
out=$(bash "$P/dforge-migrate" "$H" 2>&1); code=$?
check "dforge-home-migrate fails: exit 1" "$code" "1"
check "dforge-home-migrate fails: refused" "$(grep -c 'refused: scripts/lib/dforge-home-migrate.mjs' <<<"$out")" "1"

# --- no Node: refused only when there is a home to migrate ---
NB="$TMP/nonode-bin"
mkdir -p "$NB"
for c in git timeout dirname tr sed head grep mv rm cat find cmp mkdir awk readlink sort mktemp cp bash; do
  src=$(type -P "$c") && ln -s "$src" "$NB/$c"
done
printf 'console.log("x");\n' > "$P/lib/dforge-home-migrate.mjs"
NH="$TMP/no-home"
mkdir -p "$NH"
out=$(HOME="$NH" PATH="$NB" bash "$P/dforge-migrate" "$H" 2>&1); code=$?
check "no node, no old home: exit 0" "$code" "0"
check "no node, no old home: nothing to migrate" "$out" "dforge-migrate: nothing to migrate in $H"
mkdir -p "$NH/.dr-superpowers"
out=$(HOME="$NH" PATH="$NB" bash "$P/dforge-migrate" "$H" 2>&1); code=$?
check "no node, old home present: exit 1" "$code" "1"
check "no node, old home present: refused" "$(grep -c 'refused: node is not on PATH' <<<"$out")" "1"
rm -rf "$NH/.dr-superpowers"
mkdir -p "$NH/.dr-forge"
out=$(HOME="$NH" PATH="$NB" bash "$P/dforge-migrate" "$H" 2>&1); code=$?
check "no node, dr-forge home present: exit 1" "$code" "1"
check "no node, dr-forge home present: refused" "$(grep -c 'refused: node is not on PATH' <<<"$out")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
