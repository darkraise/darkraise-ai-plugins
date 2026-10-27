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
run status docs/plan.md 9 HEAD
check "status: a wave the plan lacks exits 2" "$status" "2"
run clean docs/plan.md 9 HEAD
check "clean: a wave the plan lacks exits 2" "$status" "2"
run status "$TMP/bad.md" 1 HEAD
check "status: waves that do not parse exit 4" "$status" "4"
run enter docs/plan.md 2 HEAD
check "enter: refuses the primary checkout" "$status" "2"
# A mark that cannot be written leaves the worktree where it was, not detached
# and unmarked, which `wave clean` would skip without a word.
git worktree add -q -b markfail "$TMP/wt-markfail" main
touch "$(git -C "$TMP/wt-markfail" rev-parse --absolute-git-dir)/dforge"
out=$(cd "$TMP/wt-markfail" && bash "$WAVE" enter "$REPO/docs/plan.md" 2 "$BASE" 2>&1); status=$?
check "enter: a mark that cannot be written exits 2" "$status" "2"
check "enter: and the worktree is not left detached" "$(git -C "$TMP/wt-markfail" branch --show-current)" "markfail"
git worktree remove --force "$TMP/wt-markfail" && git branch -q -D markfail
# A fresh worktree can start on a commit that predates the plan; the plan
# arrives with the detach at START, so enter reads it from there.
OLD=$(git commit-tree "$(git hash-object -t tree /dev/null)" -m old)
git worktree add -q --detach "$TMP/wt-fresh" "$OLD"
out=$(cd "$TMP/wt-fresh" && bash "$WAVE" enter docs/nope.md 2 "$BASE" 2>&1); status=$?
check "enter: a plan in neither the worktree nor START exits 2" "$status" "2"
out=$(cd "$TMP/wt-fresh" && bash "$WAVE" enter docs/plan.md 2 "$OLD" 2>&1); status=$?
check "enter: a START without the plan exits 2" "$status" "2"
check "enter: and the worktree stays where it was" "$(git -C "$TMP/wt-fresh" rev-parse HEAD)" "$OLD"
out=$(cd "$TMP/wt-fresh" && bash "$WAVE" enter docs/plan.md 2 "$BASE" 2>&1); status=$?
check "enter: a worktree that predates the plan enters at START" "$status:$(git -C "$TMP/wt-fresh" rev-parse HEAD)" "0:$BASE"
check "enter: and the plan is there afterwards" "$([ -f "$TMP/wt-fresh/docs/plan.md" ] && echo yes)" "yes"
git worktree remove --force "$TMP/wt-fresh"

# --- a task worktree, as an implementer would leave it ---
task() { # task <N> <file> — commit <file> in a detached worktree and move the ref
  local wt="$TMP/wt-$1"
  git worktree add -q --detach "$wt" main
  (cd "$wt" && bash "$WAVE" enter "$REPO/docs/plan.md" "$1" "$BASE" >/dev/null)
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
# A user's detached worktree on a task's commit was never entered for the task.
git worktree add -q --detach "$TMP/inspect" sdd/plan/task-2
printf 'x\n' > "$TMP/wt-3/scratch"
run clean docs/plan.md 2 "$BASE"
has "clean: removes a merged task's worktree" "$out" "removed $GTMP/wt-2"
has "clean: keeps a worktree with uncommitted changes" "$out" "kept $GTMP/wt-3: uncommitted changes"
has "clean: deletes the merged ref" "$out" "deleted sdd/plan/task-2"
check "clean: a worktree is reported once" "$(grep -c "wt-3: uncommitted" <<<"$out")" "1"
check "clean: a user's own worktree stays" "$(git worktree list | grep -c "$GTMP/own ")" "1"
check "clean: the removed worktree is gone" "$([ -d "$TMP/wt-2" ] && echo yes || echo no)" "no"
check "clean: an unmarked detached worktree in range stays" "$([ -d "$TMP/inspect" ] && echo yes || echo no)" "yes"

# --- check-due: which check closes wave K ---
# Fixture lines carry a leading | so a plan that quotes this suite still lints.
sed 's/^|//' > docs/cadence.md <<'PLAN'
|# Cadence Plan
|
|**Execution:** subagent — `claude --model sonnet --effort high` — waves
|
|**Parallelism:** waves — 1 | 2-3 | 4 | 5 | 6-7 | 8 | 9
|
|**Integration check:** `bash full.sh`
|
|**Worktree setup:** none
|
|**Wave check:** `bash quick.sh`
|
|### Task 1: One
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|### Task 2: Two
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 1 = 1
|### Task 3: Three
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 2 = 2
|### Task 4: Four
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|### Task 5: Five
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 3 = 4
|### Task 6: Six
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|### Task 7: Seven
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|### Task 8: Eight
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|### Task 9: Nine
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
PLAN
grep -v '^\*\*Wave check:\*\*' docs/cadence.md > docs/cadence-nocheck.md
git add docs/cadence.md docs/cadence-nocheck.md && git commit -qm "docs: cadence fixtures"
due() { out=$(HOME="$TMP/home" bash "$WAVE" check-due "$@" 2>&1); status=$?; }
got="" got_status=""
for k in 1 2 3 4 5 6 7; do due docs/cadence.md "$k"; got="$got$out "; got_status="$got_status$status"; done
check "check-due: every third wave, a risk-3 wave and the last run the full check" "$got" "wave-check wave-check full full wave-check full full "
check "check-due: exits 0 for every wave" "$got_status" "0000000"
got=""
for k in 1 2 3 4 5 6 7; do due docs/cadence-nocheck.md "$k"; got="$got$out "; done
check "check-due: without a Wave check line the other waves run none" "$got" "none none full full none full full "
due docs/cadence.md 8
check "check-due: a wave past the last exits 2" "$status" "2"
due docs/cadence.md 0
check "check-due: wave 0 exits 2" "$status" "2"
due docs/cadence.md two
check "check-due: a wave that is not a number exits 2" "$status" "2"
due docs/cadence.md
check "check-due: no wave exits 2" "$status" "2"
due docs/plan.md 1
check "check-due: a one-task first wave of two runs the wave check or none" "$out" "none"
due docs/plan.md 2
check "check-due: the last wave runs the full check" "$out" "full"
due "$TMP/seq.md" 1
check "check-due: a sequential plan exits 2" "$status" "2"
due "$TMP/bad.md" 1
check "check-due: waves that do not parse exit 4" "$status" "4"
# A Header amendment adds a Wave check line without editing the plan file.
WS_C=$(HOME="$TMP/home" bash "$HERE/../scripts/sdd-workspace" docs/cadence-nocheck.md | tr -d '\r')
printf '%s\n' '## A1 — Header' 'Reason: a faster check between full checks' 'Cost if wrong: one wave check' \
  '### Old' '````text' '**Worktree setup:** none' '````' \
  '### New' '````text' '**Worktree setup:** none' '' '**Wave check:** `bash quick.sh`' '````' > "$WS_C/amendments.md"
due docs/cadence-nocheck.md 1
check "check-due: reads a Wave check line an amendment adds" "$out" "wave-check"
check "check-due: the plan file itself is unchanged" "$(grep -c '^\*\*Wave check:\*\*' docs/cadence-nocheck.md)" "0"


printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
