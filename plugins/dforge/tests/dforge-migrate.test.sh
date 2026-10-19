#!/usr/bin/env bash
# dforge-migrate: a dr-superpowers or dr-forge repository's checkouts move to
# the dforge 4.0 names.
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
check "dr-forge: the state move printed" "$(grep -cxF "moved $F/.forge -> $F/.dforge" <<<"$out")" "1"
check "dr-forge: the docs move printed" "$(grep -cxF "moved $F/docs/forge -> $F/docs/dforge" <<<"$out")" "1"
check "dr-forge: the git dir move printed" "$(grep -cxF "moved $F/.git/dr-forge -> $F/.git/dforge" <<<"$out")" "1"
check "dr-forge: the plan rewrite printed" "$(grep -cxF "rewrote the plugin prefixes in $F/docs/dforge/plans/active.md" <<<"$out")" "1"
check "dr-forge: the handoff rewrite printed" "$(grep -cxF "rewrote the plugin prefixes in $F/.dforge/handoff/latest.md" <<<"$out")" "1"
out=$(bash "$FM" "$F" 2>&1); code=$?
check "dr-forge again: exit 0" "$code" "0"
check "dr-forge again: nothing to migrate" "$out" "dforge-migrate: nothing to migrate in $F"

# --- an active plan's fenced code blocks keep their prefixes ---
FC="$TMP/fenced"
repo "$FC"
mkdir -p "$FC/docs/dforge/plans"
printf '**Implementer:** dr-forge:impl-sonnet-low\n```bash\necho dr-forge:brainstorming\n```\nthen dr-forge:executing-plans\n' > "$FC/docs/dforge/plans/mixed.md"
printf '```\ndr-forge:impl-sonnet-low\n```\n' > "$FC/docs/dforge/plans/fenced-only.md"
out=$(bash "$FM" --dry-run "$FC" 2>&1); code=$?
check "fenced, dry: exit 0" "$code" "0"
check "fenced, dry: the mixed plan listed" "$(grep -cxF "would rewrite the plugin prefixes in $FC/docs/dforge/plans/mixed.md" <<<"$out")" "1"
check "fenced, dry: a plan with prefixes only in a fence not listed" "$(grep -c "fenced-only.md" <<<"$out")" "0"
out=$(bash "$FM" "$FC" 2>&1); code=$?
check "fenced: exit 0" "$code" "0"
check "fenced: prefixes outside the fence rewritten, inside kept" "$(cat "$FC/docs/dforge/plans/mixed.md")" \
  $'**Implementer:** dforge:impl-sonnet-low\n```bash\necho dr-forge:brainstorming\n```\nthen dforge:executing-plans'
check "fenced: a plan with prefixes only in a fence keeps its text" "$(cat "$FC/docs/dforge/plans/fenced-only.md")" $'```\ndr-forge:impl-sonnet-low\n```'
check "fenced: no rewrite reported for it" "$(grep -c "fenced-only.md" <<<"$out")" "0"

# --- a fence closes only on its own character and length ---
printf '````md\n```\ndr-forge:inner\n```\n````\nafter dr-forge:outer\n' > "$FC/docs/dforge/plans/long-fence.md"
printf '~~~\ndr-forge:tilde\n~~~\nthen dr-forge:plain\n' > "$FC/docs/dforge/plans/tilde.md"
out=$(bash "$FM" "$FC" 2>&1); code=$?
check "fence kinds: exit 0" "$code" "0"
check "fence kinds: an inner three-backtick line does not close a four-backtick fence" "$(cat "$FC/docs/dforge/plans/long-fence.md")" \
  $'````md\n```\ndr-forge:inner\n```\n````\nafter dforge:outer'
check "fence kinds: a tilde fence keeps its prefixes" "$(cat "$FC/docs/dforge/plans/tilde.md")" $'~~~\ndr-forge:tilde\n~~~\nthen dforge:plain'

# --- a CRLF fence closes ---
printf '```\r\ndr-forge:inner\r\n```\r\nthen dr-forge:outer\r\n' > "$FC/docs/dforge/plans/crlf.md"
out=$(bash "$FM" --dry-run "$FC" 2>&1)
check "crlf fence, dry: listed" "$(grep -cxF "would rewrite the plugin prefixes in $FC/docs/dforge/plans/crlf.md" <<<"$out")" "1"
out=$(bash "$FM" "$FC" 2>&1); code=$?
check "crlf fence: exit 0" "$code" "0"
check "crlf fence: closes, the line after it rewritten" "$(cat "$FC/docs/dforge/plans/crlf.md")" $'```\r\ndr-forge:inner\r\n```\r\nthen dforge:outer\r'

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

# --- a tracked state directory: named for the commit only once it has moved ---
TS="$TMP/tracked-state"
repo "$TS"
mkdir -p "$TS/.forge" "$TS/.dforge"
echo old > "$TS/.forge/clash.md"
git -C "$TS" add .forge
git -C "$TS" commit -q -m state
echo new > "$TS/.dforge/clash.md"
out=$(bash "$FM" "$TS" 2>&1); code=$?
check "tracked state refused: exit 1" "$code" "1"
check "tracked state refused: no commit line for it" "$(grep -c "^commit: $TS: the rename .forge/" <<<"$out")" "0"
rm "$TS/.forge/clash.md"
out=$(bash "$FM" "$TS" 2>&1); code=$?
check "tracked state resolved: exit 0" "$code" "0"
check "tracked state resolved: .forge gone" "$(exists "$TS/.forge")" "no"
check "tracked state resolved: the commit line names it" "$(grep -c "^commit: $TS: the rename .forge/ -> .dforge/ (git add -A .forge .dforge)$" <<<"$out")" "1"

# --- a merge keeps an empty directory only the old tree holds ---
ED="$TMP/empty-dirs"
repo "$ED"
mkdir -p "$ED/.forge/a/b" "$ED/.dforge" "$ED/.git/dr-forge/run.lock" "$ED/.git/dforge/tasks"
echo x > "$ED/.forge/a/x.md"
out=$(bash "$FM" --dry-run "$ED" 2>&1); code=$?
check "empty dirs, dry: exit 0" "$code" "0"
check "empty dirs, dry: the empty directory listed" "$(grep -cxF "would move $ED/.git/dr-forge/run.lock -> $ED/.git/dforge/run.lock" <<<"$out")" "1"
out=$(bash "$FM" "$ED" 2>&1); code=$?
check "empty dirs: exit 0" "$code" "0"
check "empty dirs: the nested empty directory kept" "$([ -d "$ED/.dforge/a/b" ] && echo yes || echo no)" "yes"
check "empty dirs: the file beside it moved" "$(cat "$ED/.dforge/a/x.md" 2>/dev/null)" "x"
check "empty dirs: the git dir lock kept" "$([ -d "$ED/.git/dforge/run.lock" ] && echo yes || echo no)" "yes"
check "empty dirs: the old trees gone" "$(exists "$ED/.forge")$(exists "$ED/.git/dr-forge")" "nono"
EF="$TMP/empty-dir-clash"
repo "$EF"
mkdir -p "$EF/.forge/d" "$EF/.dforge"
echo file > "$EF/.dforge/d"
out=$(bash "$FM" --dry-run "$EF" 2>&1); code=$?
check "empty dir over a file, dry: exit 1" "$code" "1"
check "empty dir over a file, dry: the refusal foretold" "$(grep -c "refused: $EF/.forge/d is a directory and $EF/.dforge/d is not" <<<"$out")" "1"
out=$(bash "$FM" "$EF" 2>&1); code=$?
check "empty dir over a file: exit 1" "$code" "1"
check "empty dir over a file: refused once" "$(grep -c "refused: " <<<"$out")" "1"
check "empty dir over a file: both kept" "$([ -d "$EF/.forge/d" ] && cat "$EF/.dforge/d")" "file"

# --- an empty old state directory, or one holding only directories .dforge/ has ---
EM="$TMP/empty-old"
repo "$EM"
mkdir -p "$EM/.superpowers/sub" "$EM/.forge" "$EM/.dforge/sub"
echo kept > "$EM/.dforge/kept.md"
out=$(bash "$FM" --dry-run "$EM" 2>&1); code=$?
check "empty old dirs, dry: exit 0" "$code" "0"
check "empty old dirs, dry: the empty one listed" "$(grep -cxF "would move $EM/.forge -> $EM/.dforge" <<<"$out")" "1"
check "empty old dirs, dry: the one holding a shared directory listed" "$(grep -cxF "would move $EM/.superpowers -> $EM/.dforge" <<<"$out")" "1"
check "empty old dirs, dry: not nothing to migrate" "$(grep -c 'nothing to migrate' <<<"$out")" "0"
out=$(bash "$FM" "$EM" 2>&1); code=$?
check "empty old dirs: exit 0" "$code" "0"
check "empty old dirs: the real run moves the empty one" "$(grep -cxF "moved $EM/.forge -> $EM/.dforge" <<<"$out")" "1"
check "empty old dirs: both gone" "$(exists "$EM/.superpowers")$(exists "$EM/.forge")" "nono"

# --- a handoff note left under an old state directory keeps its text ---
HN="$TMP/handoff-refused"
repo "$HN"
mkdir -p "$HN/.forge/handoff" "$HN/.dforge/handoff"
printf 'old dr-forge:resume-execution\n' > "$HN/.forge/handoff/latest.md"
printf 'new dr-forge:resume-execution\n' > "$HN/.dforge/handoff/latest.md"
out=$(bash "$FM" --dry-run "$HN" 2>&1); code=$?
check "refused note, dry: exit 1" "$code" "1"
check "refused note, dry: the note left behind not listed" "$(grep -c "would rewrite the plugin prefixes in $HN/.forge/" <<<"$out")" "0"
check "refused note, dry: the .dforge note listed" "$(grep -cxF "would rewrite the plugin prefixes in $HN/.dforge/handoff/latest.md" <<<"$out")" "1"
out=$(bash "$FM" "$HN" 2>&1); code=$?
check "refused note: exit 1" "$code" "1"
check "refused note: the note left behind keeps its text" "$(cat "$HN/.forge/handoff/latest.md")" "old dr-forge:resume-execution"
check "refused note: the .dforge note rewritten" "$(cat "$HN/.dforge/handoff/latest.md")" "new dforge:resume-execution"
HM="$TMP/handoff-moves"
repo "$HM"
mkdir -p "$HM/.forge/handoff" "$HM/.dforge"
printf 'dr-forge:resume-execution\n' > "$HM/.forge/handoff/latest.md"
out=$(bash "$FM" --dry-run "$HM" 2>&1)
check "moving note, dry: listed" "$(grep -cxF "would rewrite the plugin prefixes in $HM/.forge/handoff/latest.md" <<<"$out")" "1"
bash "$FM" "$HM" > /dev/null 2>&1
check "moving note: rewritten once moved" "$(cat "$HM/.dforge/handoff/latest.md")" "dforge:resume-execution"

# --- docs/forge/ beside docs/dforge/: refused, and no plan is rewritten ---
K="$TMP/forge-both-docs"
repo "$K"
mkdir -p "$K/docs/forge/plans" "$K/docs/dforge"
printf 'dr-forge:impl-sonnet-low\n' > "$K/docs/forge/plans/p.md"
out=$(bash "$FM" "$K" 2>&1); code=$?
check "forge and dforge docs: exit 1" "$code" "1"
check "forge and dforge docs: refusal names both" "$(grep -c "refused: $K/docs/forge and $K/docs/dforge all exist" <<<"$out")" "1"
check "forge and dforge docs: the plan is untouched" "$(cat "$K/docs/forge/plans/p.md")" "dr-forge:impl-sonnet-low"

# --- a link in a merge or a docs move: refused, nothing lands outside ---
LM="$TMP/linked-merge"
repo "$LM"
mkdir -p "$TMP/outside-merge" "$LM/.forge"
echo planted > "$LM/.forge/planted.md"
ln -s "$TMP/outside-merge" "$LM/.dforge"
out=$(bash "$FM" "$LM" 2>&1); code=$?
check "linked .dforge: exit 1" "$code" "1"
check "linked .dforge: nothing lands outside" "$(exists "$TMP/outside-merge/planted.md")" "no"
check "linked .dforge: .forge kept" "$(cat "$LM/.forge/planted.md")" "planted"
LS="$TMP/linked-source"
repo "$LS"
mkdir -p "$TMP/outside-source" "$LS/.dforge"
echo kept > "$TMP/outside-source/kept.md"
ln -s "$TMP/outside-source" "$LS/.forge"
out=$(bash "$FM" "$LS" 2>&1); code=$?
check "linked .forge beside .dforge: exit 1" "$code" "1"
check "linked .forge beside .dforge: the outside file stays" "$(cat "$TMP/outside-source/kept.md")" "kept"
LI="$TMP/linked-inner"
repo "$LI"
mkdir -p "$TMP/outside-inner" "$LI/.forge/sub" "$LI/.dforge"
echo planted > "$LI/.forge/sub/planted.md"
ln -s "$TMP/outside-inner" "$LI/.dforge/sub"
out=$(bash "$FM" "$LI" 2>&1); code=$?
check "a link inside .dforge: exit 1" "$code" "1"
check "a link inside .dforge: nothing lands outside" "$(exists "$TMP/outside-inner/planted.md")" "no"
LG="$TMP/linked-dangling"
repo "$LG"
mkdir -p "$LG/.forge/x" "$LG/.forge/sub" "$LG/.dforge"
echo a > "$LG/.forge/x/a.md"
echo planted > "$LG/.forge/sub/planted.md"
ln -s x/../../.. "$LG/.dforge/sub"
out=$(bash "$FM" "$LG" 2>&1); code=$?
check "a dangling link inside .dforge: refused by the link guard" "$(grep -c "holds a symbolic link; merge them by hand" <<<"$out")" "1"
check "a dangling link inside .dforge: nothing lands outside" "$(exists "$TMP/planted.md")" "no"
LD="$TMP/linked-docs"
repo "$LD"
mkdir -p "$TMP/outside-docs/forge"
ln -s "$TMP/outside-docs" "$LD/docs"
out=$(bash "$FM" "$LD" 2>&1); code=$?
check "linked docs: exit 1" "$code" "1"
check "linked docs: the outside tree is not renamed" "$(exists "$TMP/outside-docs/forge")$(exists "$TMP/outside-docs/dforge")" "yesno"

LR="$TMP/linked-docs-inside"
repo "$LR"
mkdir -p "$LR/real-docs/forge/plans"
printf 'dr-forge:impl-sonnet-low\n' > "$LR/real-docs/forge/plans/p.md"
ln -s real-docs "$LR/docs"
out=$(bash "$FM" --dry-run "$LR" 2>&1); code=$?
check "docs linked inside, dry: exit 1" "$code" "1"
check "docs linked inside, dry: the refusal foretold" "$(grep -c "refused: $LR/docs/forge or $LR/docs/dforge lies in a linked directory" <<<"$out")" "1"
check "docs linked inside, dry: no plan rewrite listed" "$(grep -c 'would rewrite the plugin prefixes' <<<"$out")" "0"
out=$(bash "$FM" "$LR" 2>&1); code=$?
check "docs linked inside: exit 1" "$code" "1"
check "docs linked inside: the plan keeps its text" "$(cat "$LR/real-docs/forge/plans/p.md")" "dr-forge:impl-sonnet-low"

# --- a search of .dforge/ that fails counts as holding a link ---
# The suite may run as root, where permissions cannot make find fail.
FF="$TMP/find-fails"
mkdir -p "$FF"
cat > "$FF/find" <<FIND
#!/bin/sh
case "\$*" in *"-type l -print -quit"*) echo "find: '\$1/locked': Permission denied" >&2; exit 1 ;; esac
exec $(type -P find) "\$@"
FIND
chmod +x "$FF/find"
UF="$TMP/unsearchable"
repo "$UF"
mkdir -p "$UF/.forge" "$UF/.dforge"
echo a > "$UF/.forge/a.md"
out=$(PATH="$FF:$PATH" bash "$FM" "$UF" 2>&1); code=$?
check "unsearchable .dforge: exit 1" "$code" "1"
check "unsearchable .dforge: refused by the link guard" "$(grep -c "holds a symbolic link; merge them by hand" <<<"$out")" "1"
check "unsearchable .dforge: find's error not shown" "$(grep -c 'Permission denied' <<<"$out")" "0"
check "unsearchable .dforge: .forge kept" "$(cat "$UF/.forge/a.md")" "a"
check "unsearchable .dforge: nothing merged" "$(exists "$UF/.dforge/a.md")" "no"

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

# --- --dry-run: every action listed, nothing written in the checkout or the home ---
snapshot() { # snapshot DIR... — every path and file checksum under DIR, the git index aside
  find "$@" -not -path '*/.git/index' -not -path '*/.git/objects/*' -print | sort
  find "$@" -type f -not -path '*/.git/index' -not -path '*/.git/objects/*' -exec cksum {} + | sort
}
DR="$TMP/dry"
repo "$DR"
mkdir -p "$DR/.forge/sdd/p1" "$DR/docs/forge/plans" "$DR/.git/dr-forge"
echo ledger > "$DR/.forge/sdd/p1/progress.md"
printf '**Implementer:** dr-forge:impl-sonnet-low\n' > "$DR/docs/forge/plans/active.md"
printf '.forge/\n' > "$DR/.gitignore"
git -C "$DR" add .gitignore docs
git -C "$DR" commit -q -m docs
DH="$TMP/dry-home"
mkdir -p "$DH/.dr-forge"
printf '{"handoffTokens":325000}\n' > "$DH/.dr-forge/config.json"
NM="$TMP/no-mktemp"
mkdir -p "$NM"
printf '#!/bin/sh\necho "$*" >> "%s/mktemp-calls"\nexit 1\n' "$TMP" > "$NM/mktemp"
chmod +x "$NM/mktemp"
before=$(snapshot "$DR" "$DH")
out=$(HOME="$DH" PATH="$NM:$PATH" bash "$FM" --dry-run "$DR" 2>&1); code=$?
check "dry: exit 0" "$code" "0"
check "dry: nothing written" "$(snapshot "$DR" "$DH")" "$before"
check "dry: the state move listed" "$(grep -cxF "would move $DR/.forge -> $DR/.dforge" <<<"$out")" "1"
check "dry: the docs move listed" "$(grep -cxF "would move $DR/docs/forge -> $DR/docs/dforge" <<<"$out")" "1"
check "dry: the git dir move listed" "$(grep -cxF "would move $DR/.git/dr-forge -> $DR/.git/dforge" <<<"$out")" "1"
check "dry: the ignore rewrite listed" "$(grep -cxF "would rewrite the older names in $DR/.gitignore" <<<"$out")" "1"
check "dry: the plan rewrite listed" "$(grep -cxF "would rewrite the plugin prefixes in $DR/docs/forge/plans/active.md" <<<"$out")" "1"
check "dry: the home move listed" "$(grep -cxF "dforge-home-migrate: would move $DH/.dr-forge to $DH/.dforge" <<<"$out")" "1"
check "dry: no commit lines" "$(grep -c '^commit:' <<<"$out")" "0"
check "dry: no temporary file made" "$(cat "$TMP/mktemp-calls" 2>/dev/null)" ""
out=$(HOME="$DH" bash "$FM" "$DR" 2>&1); code=$?
check "after the dry run, the real run: exit 0" "$code" "0"
check "after the dry run, the real run: the plan rewritten" "$(cat "$DR/docs/dforge/plans/active.md")" "**Implementer:** dforge:impl-sonnet-low"

DB="$TMP/dry-both-docs"
repo "$DB"
mkdir -p "$DB/docs/forge" "$DB/docs/dforge"
before=$(snapshot "$DB")
out=$(bash "$FM" --dry-run "$DB" 2>&1); code=$?
check "dry, two docs trees: exit 1" "$code" "1"
check "dry, two docs trees: the refusal foretold" "$(grep -c "refused: $DB/docs/forge and $DB/docs/dforge all exist" <<<"$out")" "1"
check "dry, two docs trees: nothing written" "$(snapshot "$DB")" "$before"

bash "$FM" --dry-run "$DB" extra > /dev/null 2>&1
check "dry: a second directory is a usage error" "$?" "2"

# --- a rewrite that fails is not listed: the real run would skip it ---
AW="$TMP/failing-awk"
mkdir -p "$AW"
printf '#!/bin/sh\nexit 2\n' > "$AW/awk"
chmod +x "$AW/awk"
RN="$TMP/rewrite-fails"
repo "$RN"
printf '.forge/\n' > "$RN/.gitignore"
out=$(PATH="$AW:$PATH" bash "$FM" --dry-run "$RN" 2>&1); code=$?
check "a failing rewrite, dry: exit 0" "$code" "0"
check "a failing rewrite, dry: not listed" "$(grep -c 'would rewrite the older names' <<<"$out")" "0"
out=$(PATH="$AW:$PATH" bash "$FM" "$RN" 2>&1)
check "a failing rewrite: not reported" "$(grep -c 'rewrote the older names' <<<"$out")" "0"
check "a failing rewrite: the file kept" "$(cat "$RN/.gitignore")" ".forge/"

# --- a home note that is no action still leaves nothing to migrate ---
SH="$TMP/settled-home"
mkdir -p "$SH/.dr-superpowers" "$SH/.dforge"
printf '{"darkmem":{"repos":{}}}\n' > "$SH/.dr-superpowers/config.json"
printf '{"darkmem":{"repos":{}}}\n' > "$SH/.dforge/config.json"
SR="$TMP/settled-repo"
repo "$SR"
for mode in --dry-run ""; do
  out=$(HOME="$SH" bash "$FM" $mode "$SR" 2>&1); code=$?
  check "settled home ${mode:-real}: exit 0" "$code" "0"
  check "settled home ${mode:-real}: the darkmem note shown" "$(grep -c "already has a darkmem section" <<<"$out")" "1"
  check "settled home ${mode:-real}: nothing to migrate" "$(grep -cxF "dforge-migrate: nothing to migrate in $SR" <<<"$out")" "1"
done

# --- a dry run's foretold home refusal is named as one ---
RH="$TMP/refusing-home"
mkdir -p "$RH/.dr-forge" "$RH/.dforge"
printf '{"handoffTokens":1}\n' > "$RH/.dr-forge/config.json"
printf '{"handoffTokens":2}\n' > "$RH/.dforge/config.json"
out=$(HOME="$RH" bash "$FM" --dry-run "$SR" 2>&1); code=$?
check "refusing home, dry: exit 1" "$code" "1"
check "refusing home, dry: the home's refusal shown" "$(grep -c '^dforge-home-migrate: refused: ' <<<"$out")" "1"
check "refusing home, dry: summed up as foretold" "$(grep -cxF 'dforge-migrate: refused: foretold refusals in the home; see above' <<<"$out")" "1"
check "refusing home, dry: not called unfinished" "$(grep -c 'did not finish' <<<"$out")" "0"

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
out=$(bash "$P/dforge-migrate" --dry-run "$H" 2>&1); code=$?
check "dforge-home-migrate fails, dry: exit 1" "$code" "1"
check "dforge-home-migrate fails, dry: still did not finish" "$(grep -c 'refused: scripts/lib/dforge-home-migrate.mjs did not finish' <<<"$out")" "1"

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
