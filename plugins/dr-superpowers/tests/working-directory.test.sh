#!/usr/bin/env bash
# Scripts find the repository from the working directory. A plan in another
# repository or worktree is refused before anything is written, so one plan's
# ledger, briefs and amendments never split across two checkouts.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/../scripts"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

mkrepo() { # mkrepo <dir> — a repository with a committed one-task plan at docs/plan.md
  git init -q "$1"
  mkdir -p "$1/docs"
  printf '# Plan\n\n**Execution:** inline — `claude --model sonnet --effort low` — x\n\n## Task index\n\n1. Only\n\n### Task 1: Only\n\nBody.\n' > "$1/docs/plan.md"
  git -C "$1" add -A && git -C "$1" commit -qm plan
}
run() { # run <dir> <script> <args...>; sets out, err and status
  out=$(cd "$1" && bash "$S/$2" "${@:3}" 2>"$TMP/err"); status=$?
  err=$(cat "$TMP/err")
}
state() { # state <dir> — yes when a .superpowers directory exists there
  if [ -d "$1/.superpowers" ]; then echo yes; else echo no; fi
}

X="$TMP/x" Y="$TMP/y"
mkrepo "$X"
mkrepo "$Y"
XTOP=$(git -C "$X" rev-parse --show-toplevel)
YTOP=$(git -C "$Y" rev-parse --show-toplevel)
WANT="is in $XTOP, but the working directory is in $YTOP; run from inside the plan's worktree"

# --- a plan in another repository ---
run "$Y" sdd-workspace "$X/docs/plan.md"
check "sdd-workspace: another repository exits 2" "$status" "2"
check "sdd-workspace: names both top levels" "$err" "sdd-workspace: $X/docs/plan.md $WANT"
run "$Y" review-package "$X/docs/plan.md" HEAD HEAD
check "review-package: another repository exits 2" "$status" "2"
check "review-package: names both top levels" "$err" "review-package: $X/docs/plan.md $WANT"
run "$Y" task-brief "$X/docs/plan.md" 1
check "task-brief: inherits the refusal from sdd-workspace" "$status" "2"
run "$Y" next-step "$X/docs/plan.md"
check "next-step: another repository exits 2" "$status" "2"
has "next-step: names both top levels on stdout" "$out" "next-step: $X/docs/plan.md $WANT"
check "no state in the plan's repository" "$(state "$X")" "no"
check "no state in the working directory's repository" "$(state "$Y")" "no"

# --- a plan outside any repository, and a working directory outside one ---
printf '# Loose\n' > "$TMP/loose.md"
run "$X" sdd-workspace "$TMP/loose.md"
check "a plan outside any repository exits 2" "$status" "2"
check "a plan outside any repository is named" "$err" \
  "sdd-workspace: $TMP/loose.md is in no git repository, but the working directory is in $XTOP; run from inside the plan's worktree"
run "$TMP" sdd-workspace "$X/docs/plan.md"
check "a working directory outside any repository exits 2" "$status" "2"
check "a working directory outside any repository is named" "$err" "sdd-workspace: not inside a git repository"

# --- a linked worktree given its primary checkout's plan path ---
WT="$TMP/wt"
git -C "$X" worktree add -q -b wt "$WT"
WTTOP=$(git -C "$WT" rev-parse --show-toplevel)
run "$WT" sdd-workspace "$X/docs/plan.md"
check "worktree: the primary checkout's plan exits 2" "$status" "2"
check "worktree: names both top levels" "$err" \
  "sdd-workspace: $X/docs/plan.md is in $XTOP, but the working directory is in $WTTOP; run from inside the plan's worktree"
check "worktree: no state in the worktree" "$(state "$WT")" "no"
check "worktree: no state in the primary checkout" "$(state "$X")" "no"
run "$WT" sdd-workspace docs/plan.md
check "worktree: its own plan passes" "$status" "0"
has "worktree: the workspace is in the worktree" "$out" "/wt/.superpowers/sdd/plan"
git -C "$X" worktree remove --force "$WT" >/dev/null 2>&1

# --- the same repository keeps working ---
run "$X" sdd-workspace docs/plan.md
check "same repository: sdd-workspace exits 0" "$status" "0"
run "$X/docs" sdd-workspace plan.md
check "a relative plan resolves against the working directory" "$status" "0"
run "$X" sdd-workspace "$X/docs/plan.md"
check "same repository: an absolute plan path passes" "$status" "0"
run "$X" review-package docs/plan.md HEAD HEAD
check "same repository: review-package exits 0" "$status" "0"
run "$X" next-step docs/plan.md
check "same repository: next-step exits 0" "$status" "0"

# --- the prose names one contract ---
P="$HERE/.."
check "no skill, reference or script says 'from the plugin root'" \
  "$(grep -rlF 'from the plugin root' "$P/skills" "$P/reference" "$P/scripts" 2>/dev/null)" ""
check "no skill or reference re-explains where the plugin root is" \
  "$(grep -rlF "the path the session's entry point names" "$P/skills" "$P/reference" 2>/dev/null)" ""
check "the compaction snapshot names the contract" \
  "$(grep -cF 'plugin-root path, with the working directory inside the project;' "$P/scripts/lib/snapshot.sh")" "1"
check "nine skill and reference files cite the contract" \
  "$(grep -rlF '(see using-superpowers §Session Budget)' "$P/skills" "$P/reference" | wc -l | tr -d ' ')" "9"

# A script that execs a sibling depends on the executable bit, which a Windows
# checkout cannot carry: core.filemode is false there, so a new script lands as
# mode 100644 and only Linux rejects it, with exit 126.
check "no script execs a sibling instead of running it with bash" \
  "$(grep -rnE '(^|\$\(|&& |\|\| |; )"\$(HERE/|\(cd )' "$P/scripts" 2>/dev/null)" ""

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
