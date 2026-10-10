#!/usr/bin/env bash
# scripts/wave carries a parallel wave's mechanics: the waves a plan declares,
# the ref each task commits to, a merge that refuses overlapping files, and a
# clean-up that removes only the worktrees a wave's tasks committed in.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAVE="$HERE/../scripts/wave"

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
# git prints worktree paths as C:/… under Git Bash, where $TMP reads /tmp/….
GTMP=$(cd "$TMP" && { pwd -W 2>/dev/null || pwd; })
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
REPO="$TMP/repo"
git init -q -b main "$REPO"
cd "$REPO"
mkdir -p docs
cat > docs/plan.md <<'EOF'
# Demo Implementation Plan

**Execution:** subagent — `claude --model sonnet --effort high` — waves

**Parallelism:** waves — 1 | 2-4

## Task index

1. One
2. Two
3. Three
4. Four

### Task 1: One

**Files:**
- Create: `a.txt`

### Task 2: Two

**Files:**
- Create: `b.txt`

### Task 3: Three

**Files:**
- Create: `c.txt`

### Task 4: Four

**Files:**
- Create: `d.txt`
EOF
printf 'a\n' > a.txt
git add -A && git commit -qm base
BASE=$(git rev-parse HEAD)
run() { out=$(bash "$WAVE" "$@" 2>&1); status=$?; }

# --- list and ref ---
run list docs/plan.md
check "list: one line per wave" "$out" "$(printf 'wave 1: Tasks 1\nwave 2: Tasks 2-4')"
sed 's/^\*\*Parallelism:.*/**Parallelism:** sequential/' docs/plan.md > "$TMP/seq.md"
run list "$TMP/seq.md"
check "list: a sequential plan" "$out" "sequential"
sed 's/^\*\*Parallelism:.*/**Parallelism:** waves — 1 | two/' docs/plan.md > "$TMP/bad.md"
run list "$TMP/bad.md"
check "list: a range that does not parse exits 4" "$status" "4"
run ref docs/plan.md 3
check "ref: named after the plan" "$out" "sdd/plan/task-3"

# --- a task worktree, as an implementer would leave it ---
task() { # task <N> <file> — commit <file> in a detached worktree and move the ref
  local wt="$TMP/wt-$1"
  git worktree add -q --detach "$wt" "$BASE"
  printf '%s\n' "$1" > "$wt/$2"
  git -C "$wt" add -A && git -C "$wt" commit -qm "task $1"
  git -C "$wt" branch -f "sdd/plan/task-$1" HEAD
}
task 2 b.txt
task 3 c.txt
task 4 b.txt

run status docs/plan.md 2 "$BASE"
has "status: a committed task" "$out" "Task 2: ref sdd/plan/task-2"
has "status: names its worktree" "$out" "merged no; worktree $GTMP/wt-2"

# --- merge ---
printf 'dirty\n' >> a.txt
run merge docs/plan.md 2 "$BASE"
check "merge: a dirty checkout exits 3" "$status" "3"
git checkout -q -- a.txt
mkdir -p .claude/worktrees/x && printf 'u\n' > .claude/worktrees/x/u
run merge docs/plan.md 2 "$BASE"
check "merge: untracked files do not block" "$status" "0"
has "merge: says what merged" "$out" "merged Task 2:"
rm -rf .claude
run merge docs/plan.md 2 "$BASE"
has "merge: twice is a no-op" "$out" "already merged: Task 2"
run merge docs/plan.md 3 "$BASE"
check "merge: a disjoint sibling merges" "$status" "0"
check "merge: both files on the branch" "$(cat b.txt c.txt | tr '\n' ' ')" "2 3 "
head_before=$(git rev-parse HEAD)
run merge docs/plan.md 4 "$BASE"
check "merge: an overlapping sibling exits 1" "$status" "1"
has "merge: names the shared file" "$out" "  b.txt"
check "merge: an overlap leaves the branch alone" "$(git rev-parse HEAD)" "$head_before"
check "merge: an overlap leaves the checkout clean" "$(git status --porcelain --untracked-files=no)" ""
# The redo is a fresh fix round: a worktree detached at the merged head.
git -C "$TMP/wt-4" switch -q --detach "$(git rev-parse HEAD)"
printf '4\n' > "$TMP/wt-4/e.txt" && git -C "$TMP/wt-4" add -A && git -C "$TMP/wt-4" commit -qm "redo on the merged head" \
  && git -C "$TMP/wt-4" branch -f sdd/plan/task-4 HEAD
run merge docs/plan.md 4 "$BASE"
check "merge: a redo on the merged head merges" "$status" "0"
has "merge: notes a file outside the plan's list" "$out" "note: e.txt is not in Task 4's **Files:**"
check "merge: one merge commit per task" "$(git rev-list --merges --count "$BASE..HEAD")" "3"

# --- clean ---
git worktree add -q -b own "$TMP/own" "$BASE"
printf 'x\n' > "$TMP/wt-3/scratch"
run clean docs/plan.md 2 "$BASE"
has "clean: removes a merged task's worktree" "$out" "removed $GTMP/wt-2"
has "clean: keeps a worktree with uncommitted changes" "$out" "kept $GTMP/wt-3: uncommitted changes"
has "clean: deletes the merged ref" "$out" "deleted sdd/plan/task-2"
check "clean: a worktree is reported once" "$(grep -c "wt-3: uncommitted" <<<"$out")" "1"
check "clean: a user's own worktree stays" "$(git worktree list | grep -c "$GTMP/own ")" "1"
check "clean: the removed worktree is gone" "$([ -d "$TMP/wt-2" ] && echo yes || echo no)" "no"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
