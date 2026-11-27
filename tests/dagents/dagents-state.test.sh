#!/usr/bin/env bash
# The state directory the scripts write: .dagents/, even in a checkout that still
# has the pre-3.0 .superpowers/.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../../plugins/dagents/scripts"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then pass=$((pass + 1))
  else printf 'FAIL - %s\n       got:  [%s]\n       want: [%s]\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
# Long, as git prints it: the runner's TEMP is an 8.3 short name.
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m -l "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"

checkout() { # checkout DIR — a repository with one committed plan, docs/p.md
  git init -q "$1"
  mkdir -p "$1/docs"
  printf '# Plan\n' > "$1/docs/p.md"
  git -C "$1" add docs/p.md
  git -C "$1" -c user.name=t -c user.email=t@example.com commit -q -m plan
}

checkout "$TMP/new"
top=$(git -C "$TMP/new" rev-parse --show-toplevel)
dir=$(cd "$TMP/new" && bash "$SCRIPTS/sdd-workspace" docs/p.md)
check "new checkout: workspace" "${dir#"$top"}" "/.dagents/sdd/p"
(cd "$TMP/new" && bash "$SCRIPTS/finish-choice" set pr --base main > /dev/null)
check "new checkout: finish choice" "$([ -f "$TMP/new/.dagents/sdd/finish.json" ] && echo yes)" "yes"
printf '!keep\n' > "$TMP/new/.dagents/sdd/.gitignore"
(cd "$TMP/new" && bash "$SCRIPTS/sdd-workspace" docs/p.md > /dev/null)
check "new checkout: an existing sdd ignore is kept" "$(cat "$TMP/new/.dagents/sdd/.gitignore")" '!keep'

# A cloned repository controls .dagents/sdd/, so its ignore is never written
# through a symbolic link.
checkout "$TMP/linked"
mkdir -p "$TMP/linked/.dagents/sdd" "$TMP/outside"
ln -s "$TMP/outside/planted" "$TMP/linked/.dagents/sdd/.gitignore"
top=$(git -C "$TMP/linked" rev-parse --show-toplevel)
dir=$(cd "$TMP/linked" && bash "$SCRIPTS/sdd-workspace" docs/p.md)
check "linked ignore: workspace" "${dir#"$top"}" "/.dagents/sdd/p"
check "linked ignore: never written through" "$([ -e "$TMP/outside/planted" ] && echo yes || echo no)" "no"

checkout "$TMP/old"
mkdir -p "$TMP/old/.superpowers"
top=$(git -C "$TMP/old" rev-parse --show-toplevel)
dir=$(cd "$TMP/old" && bash "$SCRIPTS/sdd-workspace" docs/p.md)
check "pre-3.0 checkout: workspace under .dagents" "${dir#"$top"}" "/.dagents/sdd/p"
(cd "$TMP/old" && bash "$SCRIPTS/finish-choice" set pr --base main > /dev/null)
check "pre-3.0 checkout: finish choice under .dagents" "$([ -f "$TMP/old/.dagents/sdd/finish.json" ] && echo yes)" "yes"
check "pre-3.0 checkout: .superpowers left to dagents-migrate" "$(ls -A "$TMP/old/.superpowers")" ""

# A worktree resolves under its own root, as sdd-workspace always did.
git -C "$TMP/old" worktree add -q -b wt "$TMP/wt"
top=$(git -C "$TMP/wt" rev-parse --show-toplevel)
dir=$(cd "$TMP/wt" && bash "$SCRIPTS/sdd-workspace" docs/p.md)
check "worktree: workspace under the worktree" "${dir#"$top"}" "/.dagents/sdd/p"

# Two plans with one basename share a workspace name: the one the ledger does
# not name is refused.
checkout "$TMP/same"
mkdir -p "$TMP/same/other" "$TMP/same/.dagents/sdd/p"
printf '# Other plan\n' > "$TMP/same/other/p.md"
git -C "$TMP/same" add other/p.md
git -C "$TMP/same" -c user.name=t -c user.email=t@example.com commit -q -m other
printf '# SDD ledger \342\200\224 plan: docs/p.md\n' > "$TMP/same/.dagents/sdd/p/progress.md"
(cd "$TMP/same" && bash "$SCRIPTS/sdd-workspace" other/p.md >/dev/null 2>&1); rc_other=$?
(cd "$TMP/same" && bash "$SCRIPTS/sdd-workspace" docs/p.md >/dev/null 2>&1); rc_own=$?
check "same-basename plan: the workspace is refused" "$rc_other|$rc_own" "2|0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
