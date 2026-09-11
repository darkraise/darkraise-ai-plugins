#!/usr/bin/env bash
# repo-audit replaces a resuming session's orientation calls with one read-only
# snapshot: branch, worktrees, dirty files, plans in flight, handoff staleness,
# the CLAUDE.md compaction section, the budget line and recent commits.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/repo-audit"

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
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset DR_SUPERPOWERS_BUDGET DR_SUPERPOWERS_JQ

REPO="$TMP/repo"
git init -q -b main "$REPO"
mkdir -p "$REPO/docs"
printf '# Plan\n\n### Task 1: One\n\n### Task 2: Two\n\n### Task 3: Three\n' > "$REPO/docs/plan.md"
printf '# Project\n\nNo compaction notes.\n' > "$REPO/CLAUDE.md"
printf '.superpowers/\n' > "$REPO/.gitignore"
git -C "$REPO" add -A && git -C "$REPO" commit -qm init
ROOT="$(git -C "$REPO" rev-parse --show-toplevel)"

WT="$TMP/wt"
git -C "$REPO" worktree add -q -b feat "$WT"
WT_ROOT="$(git -C "$WT" rev-parse --show-toplevel)"
WS="$WT/.superpowers/sdd/plan"
mkdir -p "$WS"
printf '# SDD ledger — plan: docs/plan.md\nTask 1: complete (commits a..b, review clean)\nTask 2: fix round 1/5 (1 addressed, 1 open — x)\n' > "$WS/progress.md"
printf '# Handoff notes\n' > "$WS/handoff.md"

mkdir -p "$REPO/.superpowers/handoff"
printf '# Handoff\n\n## Next session\n\n**Status:** Plan `docs/plan.md`: 1 of 3 tasks complete.\n**Next:** Resume at Task 2 (Two).\n' \
  > "$REPO/.superpowers/handoff/latest.md"
touch -d '1 hour ago' "$REPO/.superpowers/handoff/latest.md"
printf 'later\n' > "$REPO/later.txt"
git -C "$REPO" add -A && git -C "$REPO" commit -qm second

run() { out=$(cd "$1" && bash "$SCRIPT" "${@:2}" 2>"$TMP/stderr"); status=$?; }

# --- primary checkout ---
run "$REPO"
check "primary: exit 0" "$status" "0"
has "primary: heading" "$out" "# Repo audit"
has "primary: root" "$out" "- Root: \`$ROOT\`"
has "primary: branch" "$out" "- Branch: \`main\` at "
has "primary: budget line" "$out" "- budget: unknown of 475k — unknown — no transcript found"
has "primary: worktree listed with branch" "$out" "[feat]"
has "primary: clean tree" "$out" "## Dirty files (0)"
has "primary: plan in flight" "$out" "- \`docs/plan.md\` in \`$WT_ROOT\`: 1 of 3 tasks complete; handoff.md: yes"
has "primary: last ledger line" "$out" "  - last ledger line: Task 2: fix round 1/5 (1 addressed, 1 open — x)"
has "primary: handoff status" "$out" "- **Status:** Plan \`docs/plan.md\`: 1 of 3 tasks complete."
has "primary: handoff staleness" "$out" "- Commits on the primary checkout's HEAD since it was written: 2"
has "primary: no compact section" "$out" "- CLAUDE.md has no Compact Instructions section"
has "primary: recent commits" "$out" " second"

# --- dirty tree and a Compact Instructions section ---
printf '# Project\n\n# Compact instructions\n\nKeep paths.\n' > "$REPO/CLAUDE.md"
run "$REPO"
has "dirty: counted" "$out" "## Dirty files (1)"
has "compact section: found" "$out" "- CLAUDE.md has a Compact Instructions section"

# --- from the worktree ---
run "$WT"
has "worktree: primary named" "$out" "- Primary checkout: \`$ROOT\`"
has "worktree: branch" "$out" "- Branch: \`feat\` at "

# --- errors ---
mkdir -p "$TMP/notrepo"
run "$TMP/notrepo"
check "outside a repository: exit 2" "$status" "2"
run "$REPO" extra
check "usage: exit 2" "$status" "2"

git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
