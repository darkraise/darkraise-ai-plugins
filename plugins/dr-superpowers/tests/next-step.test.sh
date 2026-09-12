#!/usr/bin/env bash
# next-step must name exactly one next action for every plan state — start,
# resume, final review, next sub-project, program done, no follow-on — and
# keep the primary checkout's handoff file pointing at it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/next-step"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
lacks() { # lacks <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n' "$1" "$3"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

REPO="$TMP/repo"
git init -q "$REPO"
ROOT="$(git -C "$REPO" rev-parse --show-toplevel)"
PLAN_REL="docs/plans/2026-01-01-demo.md"
PLAN="$REPO/$PLAN_REL"
LEDGER_DIR="$REPO/.superpowers/sdd/2026-01-01-demo"
LEDGER_SHOWN="$ROOT/.superpowers/sdd/2026-01-01-demo/progress.md"
HANDOFF="$REPO/.superpowers/handoff/latest.md"
mkdir -p "$REPO/docs/plans"

write_plan() { # write_plan <file> <execution line> <program line or empty>
  {
    printf '# Demo Implementation Plan\n\n**Spec:** `docs/specs/demo.md`\n\n'
    printf '%s\n\n' "$2"
    [ -n "$3" ] && printf '%s\n\n' "$3"
    printf '## Task index\n\n1. First\n2. Second\n3. Third\n\n'
    printf '### Task 1: First thing\n\nBody.\n\n```bash\n### Task 9: fenced, not a task\n```\n\n'
    printf '### Task 2: Second thing\n\nBody.\n\n### Task 3: Third thing\n\nBody.\n'
  } > "$1"
}
EXEC_SUB='**Execution:** subagent — `claude --model sonnet --effort high` — Task 2 scores 4'
PROG_NEXT='**Program:** `docs/specs/program.md` — sub-project 2 of 5 — next: Session budget'
write_plan "$PLAN" "$EXEC_SUB" "$PROG_NEXT"
git -C "$REPO" add -A && git -C "$REPO" commit -qm init

ledger() { # ledger <lines...> — first line is the identity line
  mkdir -p "$LEDGER_DIR"
  { printf '# SDD ledger — plan: %s\n' "$PLAN_REL"; printf '%s\n' "$@"; } > "$LEDGER_DIR/progress.md"
}
run() { # run <dir> <args...>; sets out and status
  out=$(cd "$1" && bash "$SCRIPT" "${@:2}" 2>"$TMP/stderr")
  status=$?
}

# --- not started: no ledger ---
rm -f "$HANDOFF"
run "$REPO" "$PLAN_REL"
check "not started: exits 0" "$status" "0"
has "not started: block heading" "$out" "## Next session"
has "not started: status counts tasks outside fences only" "$out" "**Status:** Plan \`$PLAN_REL\`: 0 of 3 tasks complete (no ledger at \`$LEDGER_SHOWN\`)."
has "not started: next is Task 1" "$out" "**Next:** Start at Task 1 (First thing)."
has "not started: launch dir is the primary checkout" "$out" "Launch in \`$ROOT\`:"
has "not started: launch command from Execution line" "$out" "claude --model sonnet --effort high"
has "not started: prompt names the sdd skill" "$out" "Continue \`$PLAN_REL\` with dr-superpowers:subagent-driven-development. Start at Task 1 (First thing)."
check "not started: writes the handoff file" "$([ -f "$HANDOFF" ] && echo yes || echo no)" "yes"
check "not started: handoff carries the block" "$(grep -c '^\*\*Next:\*\* Start at Task 1' "$HANDOFF")" "1"

# --- mid-plan: tasks 1-2 complete, task 3 mid fix-round ---
ledger 'Task 1: complete (commits a..b, review clean)' \
       'Task 2: complete (commits b..c, review clean)' \
       'Task 3: fix round 2/5 (1 addressed, 1 open — x; commits c..d)'
printf '# Handoff\n\n## Goal\nKeep me.\n\n## Next session\nOld stale block.\n\n## Do not\nKeep me too.\n' > "$HANDOFF"
run "$REPO" "$PLAN_REL"
check "mid-plan: exits 0" "$status" "0"
has "mid-plan: status counts completions" "$out" "2 of 3 tasks complete (ledger \`$LEDGER_SHOWN\`)."
has "mid-plan: resumes the fix-round task" "$out" "**Next:** Resume at Task 3 (Third thing)."
has "mid-plan: prompt points at the ledger" "$out" "Progress ledger: \`$LEDGER_SHOWN\` — trust its \`Task N: complete\` lines."
has "mid-plan: prompt routes through resume-execution" "$out" "Resume \`$PLAN_REL\` with dr-superpowers:resume-execution. Resume at Task 3 (Third thing)."
hand=$(cat "$HANDOFF")
has "mid-plan: handoff keeps earlier sections" "$hand" "Keep me."
has "mid-plan: handoff keeps later sections" "$hand" "## Do not"
lacks "mid-plan: handoff drops the stale block" "$hand" "Old stale block."
check "mid-plan: handoff has one Next session section" "$(grep -c '^## Next session' "$HANDOFF")" "1"
has "mid-plan: handoff carries the new next step" "$hand" "Resume at Task 3 (Third thing)."

# --- ledger for another plan is ignored ---
mkdir -p "$LEDGER_DIR"
printf '# SDD ledger — plan: docs/plans/other.md\nTask 1: complete (x)\n' > "$LEDGER_DIR/progress.md"
run "$REPO" "$PLAN_REL"
has "foreign ledger: treated as not started" "$out" "**Next:** Start at Task 1 (First thing)."
has "foreign ledger: says why" "$out" "belongs to another plan"

# --- all tasks complete, final review not yet run ---
ledger 'Task 1: complete (x)' 'Task 2: complete (x)' 'Group 2-3: review round 1/3' 'Task 3: complete (x)'
run "$REPO" "$PLAN_REL"
has "tasks done: status" "$out" "**Status:** Plan \`$PLAN_REL\`: all 3 tasks complete."
has "tasks done: next is final review then finishing" "$out" "**Next:** Run the final whole-branch review, then dr-superpowers:finishing-a-development-branch."

# --- --complete with a next sub-project ---
printf '# Handoff\n\n## Goal\nOld goal.\n\n## Next session\nOld.\n' > "$HANDOFF"
rm -rf "$LEDGER_DIR"
run "$REPO" --complete "$PLAN_REL"
check "complete/next: exits 0" "$status" "0"
has "complete/next: status" "$out" "**Status:** Plan \`$PLAN_REL\` is complete; sub-project 2 of 5 is done."
has "complete/next: next sub-project" "$out" "**Next:** Sub-project 3 (Session budget): write its spec in a fresh session."
has "complete/next: planning launch command" "$out" "claude --model opus --effort high"
has "complete/next: brainstorming prompt" "$out" "Start sub-project 3 (Session budget) of the program in \`docs/specs/program.md\`: use dr-superpowers:brainstorming to write its spec."
hand=$(cat "$HANDOFF")
lacks "complete/next: handoff replaced wholesale" "$hand" "Old goal."
has "complete/next: handoff carries next sub-project" "$hand" "Sub-project 3 (Session budget)"

# --- --complete on the last sub-project ---
write_plan "$PLAN" "$EXEC_SUB" '**Program:** `docs/specs/program.md` — sub-project 5 of 5 — last'
run "$REPO" --complete "$PLAN_REL"
has "complete/last: program done" "$out" "**Next:** Nothing — every sub-project of \`docs/specs/program.md\` is done."
lacks "complete/last: no launch block" "$out" "Launch in"

# --- --complete with no Program line ---
write_plan "$PLAN" "$EXEC_SUB" ""
run "$REPO" --complete "$PLAN_REL"
has "complete/none: no follow-on" "$out" "**Next:** Nothing — the plan records no follow-on work."
lacks "complete/none: no launch block" "$out" "Launch in"

# --- --complete with a Program line naming no next step ---
write_plan "$PLAN" "$EXEC_SUB" '**Program:** `docs/specs/program.md` — sub-project 2 of 5'
run "$REPO" --complete "$PLAN_REL"
has "complete/unreadable: points at the program spec" "$out" "**Next:** Read \`docs/specs/program.md\` for the sub-project after 2 — the plan's Program line names no next step."

# --- Execution line variants ---
write_plan "$PLAN" '**Execution:** inline -- claude --model sonnet --effort medium -- all tasks score <= 3' ""
run "$REPO" "$PLAN_REL"
has "inline: prompt names executing-plans" "$out" "with dr-superpowers:executing-plans."
has "inline: command without backticks" "$out" "claude --model sonnet --effort medium"
write_plan "$PLAN" '**Execution:** subagent — codex gpt-5.6-sol / high — Codex host' ""
run "$REPO" "$PLAN_REL"
has "codex: no claude command, points at the Execution line" "$out" "Launch: see the **Execution:** line in \`$PLAN_REL\`."

# --- CRLF plan ---
write_plan "$PLAN" "$EXEC_SUB" "$PROG_NEXT"
sed 's/$/\r/' "$PLAN" > "$PLAN.tmp" && mv "$PLAN.tmp" "$PLAN"
run "$REPO" "$PLAN_REL"
has "crlf: tasks still counted" "$out" "0 of 3 tasks complete"
lacks "crlf: no carriage return in output" "$out" $'\r'

# --- worktree: ledger in the worktree, handoff in the primary checkout ---
write_plan "$PLAN" "$EXEC_SUB" "$PROG_NEXT"
WT="$TMP/wt"
git -C "$REPO" worktree add -q -b feat "$WT"
WT_ROOT="$(git -C "$WT" rev-parse --show-toplevel)"
mkdir -p "$WT/.superpowers/sdd/2026-01-01-demo"
printf '# SDD ledger — plan: %s\nTask 1: complete (x)\n' "$PLAN_REL" > "$WT/.superpowers/sdd/2026-01-01-demo/progress.md"
rm -f "$HANDOFF"
run "$WT" "$PLAN_REL"
has "worktree: reads the worktree ledger" "$out" "1 of 3 tasks complete"
has "worktree: prompt names the worktree" "$out" "First enter the existing worktree \`$WT_ROOT\`."
has "worktree: launch dir is still the primary checkout" "$out" "Launch in \`$ROOT\`:"
check "worktree: handoff written in the primary checkout" "$([ -f "$HANDOFF" ] && echo yes || echo no)" "yes"
check "worktree: no handoff inside the worktree" "$([ -f "$WT/.superpowers/handoff/latest.md" ] && echo yes || echo no)" "no"

# --- handoff write failure still prints the block ---
rm -rf "$REPO/.superpowers/handoff"
printf 'not a dir' > "$REPO/.superpowers/handoff"
run "$REPO" "$PLAN_REL"
check "unwritable handoff: exits 4" "$status" "4"
has "unwritable handoff: block still printed" "$out" "**Next:** Start at Task 1 (First thing)."
has "unwritable handoff: says so on stderr" "$(cat "$TMP/stderr")" "could not write"
has "unwritable handoff: says so on stdout" "$out" "next-step: could not write"
rm -f "$REPO/.superpowers/handoff"

# --- final review clean: finishing is next ---
ledger 'Task 1: complete (x)' 'Task 2: complete (x)' 'Task 3: complete (x)' 'Final review: clean (commits a1b2c3d..d4e5f6a)'
run "$REPO" "$PLAN_REL"
has "final review clean: status" "$out" "**Status:** Plan \`$PLAN_REL\`: all 3 tasks complete; the final review is clean."
has "final review clean: next is finishing" "$out" "**Next:** Run dr-superpowers:finishing-a-development-branch."
has "final review clean: prompt routes through resume-execution" "$out" "Resume \`$PLAN_REL\` with dr-superpowers:resume-execution. Run dr-superpowers:finishing-a-development-branch."
rm -rf "$LEDGER_DIR"

# --- draft mode: a design phase hands off ---
mkdir -p "$REPO/docs/specs" "$REPO/.superpowers/handoff"
printf '# Draft\n' > "$REPO/docs/specs/draft.md"
printf '# Handoff\n\n## State\nKeep me.\n\n## Next session\nOld block.\n' > "$HANDOFF"
run "$REPO" --draft docs/specs/draft.md --next "Write the implementation plan with dr-superpowers:writing-plans"
check "draft: exits 0" "$status" "0"
has "draft: status names the authority" "$out" "**Status:** Design in progress: \`docs/specs/draft.md\` is the authority."
has "draft: next action gains a full stop" "$out" "**Next:** Write the implementation plan with dr-superpowers:writing-plans."
has "draft: planning launch command" "$out" "claude --model opus --effort high"
has "draft: prompt" "$out" "Continue from \`docs/specs/draft.md\` (the authority): Write the implementation plan with dr-superpowers:writing-plans. Read \`.superpowers/handoff/latest.md\` first."
hand=$(cat "$HANDOFF")
has "draft: handoff keeps the notes" "$hand" "Keep me."
lacks "draft: handoff drops the stale block" "$hand" "Old block."
run "$REPO" --draft docs/specs/draft.md
check "draft without --next: exits 2" "$status" "2"
run "$REPO" --draft docs/specs/missing.md --next "x"
check "draft of a missing file: exits 2" "$status" "2"

# --- usage errors ---
run "$REPO"
check "no args: exits 2" "$status" "2"
run "$REPO" docs/plans/missing.md
check "missing plan: exits 2" "$status" "2"
printf '# Empty plan\n\nNo tasks here.\n' > "$REPO/docs/plans/empty.md"
run "$REPO" docs/plans/empty.md
check "no tasks: exits 3" "$status" "3"

git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1

# --- failures are visible on stdout ---
# Every non-zero exit prints on stdout too: a session that surfaces only
# stdout would otherwise see nothing at all from the script whose job is
# saying what happens next. Always go through run(): it cds into the fixture
# repo, so the script cannot resolve the real checkout and overwrite its
# handoff file.
run "$REPO" docs/plans/no-such-plan.md
check "missing plan: exits 2" "$status" "2"
has "missing plan: says so on stdout" "$out" "next-step: no such file"

printf '# Empty plan\n\n**Goal:** nothing\n' > "$REPO/docs/plans/2026-01-01-empty.md"
run "$REPO" docs/plans/2026-01-01-empty.md
check "no tasks: exits 3 (stdout form)" "$status" "3"
has "no tasks: says so on stdout" "$out" "next-step: no tasks in"

run "$REPO"
check "no arguments: exits 2" "$status" "2"
has "no arguments: prints usage on stdout" "$out" "next-step: usage:"

# --- a plan that escalated out of inline mode ---
# The ledger, not the Execution line, says which mode a run is in after a
# switch. The launch command has to follow it, or the resumed session starts at
# inline mode's model and effort.
INL="$REPO/docs/plans/2026-01-01-inline.md"
cat > "$INL" <<'PLAN'
# Inline plan

**Goal:** demo

**Spec:** docs/spec.md

**Execution:** inline — `claude --model sonnet --effort low` — every task scores 2

## Task index

1. First
2. Second

### Task 1: First

### Task 2: Second
PLAN
INL_LEDGER="$REPO/.superpowers/sdd/2026-01-01-inline"
mkdir -p "$INL_LEDGER"
{
  echo "# SDD ledger — plan: docs/plans/2026-01-01-inline.md"
  echo "Task 1: implementer inline (assigned; base aaaaaaa)"
  echo "Task 1: complete (commits aaaaaaa..bbbbbbb, unreviewed) — done: x; verified: y → ok; remaining: none; discovered: none; assumptions: none"
  echo "Task 2: implementer inline (assigned; base bbbbbbb)"
  echo "Task 2: fix round 3/3 (0 addressed, 1 open — still red; commits bbbbbbb..ccccccc; escalated inline -> subagent)"
} > "$INL_LEDGER/progress.md"

run "$REPO" docs/plans/2026-01-01-inline.md
has "escalated: launches the subagent pair" "$out" "claude --model sonnet --effort high"
lacks "escalated: drops the inline pair" "$out" "--effort low"
has "escalated: says the plan escalated" "$out" "This plan escalated to subagent mode at Task 2."

# A later inline assignment means the plan came back; the Execution line rules
# again.
echo "Task 2: implementer inline (assigned; base ccccccc)" >> "$INL_LEDGER/progress.md"
run "$REPO" docs/plans/2026-01-01-inline.md
has "returned to inline: launches the inline pair" "$out" "claude --model sonnet --effort low"
lacks "returned to inline: drops the escalation sentence" "$out" "This plan escalated to subagent mode"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
