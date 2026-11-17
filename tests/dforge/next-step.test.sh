#!/usr/bin/env bash
# next-step must name exactly one next action for every plan state — start,
# resume, final review, next sub-project, program done, no follow-on — and
# keep the primary checkout's handoff file pointing at it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../plugins/dforge/scripts/next-step"

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
LEDGER_DIR="$REPO/.dforge/sdd/2026-01-01-demo"
LEDGER_SHOWN="$ROOT/.dforge/sdd/2026-01-01-demo/progress.md"
HANDOFF="$REPO/.dforge/handoff/latest.md"
mkdir -p "$REPO/docs/plans"

write_plan() { # write_plan <file> <execution line> <program line or empty>
  {
    printf '# Demo Implementation Plan\n\n**Spec:** `docs/specs/demo.md`\n\n'
    printf '%s\n\n' "$2"
    [ -n "$3" ] && printf '%s\n\n' "$3"
    printf '## Task index\n\n1. First\n2. Second\n3. Third\n\n'
    printf '### Task 1: First thing\n\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\nBody.\n\n```bash\n### Task 9: fenced, not a task\n```\n\n'
    printf '### Task 2: Second thing\n\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\nBody.\n\n'
    printf '### Task 3: Third thing\n\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\nBody.\n'
  } > "$1"
}
EXEC_SUB='**Execution:** inline — `claude --model sonnet --effort high` — Task 2 scores 4'
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
has "not started: prompt names the execution skill and Setup" "$out" "Continue \`$PLAN_REL\` with dforge:executing-plans. No ledger exists yet: begin at the skill's Setup, workspace first; the first task is Task 1 (First thing)."
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
has "mid-plan: prompt routes through resume-execution" "$out" "Resume \`$PLAN_REL\` with dforge:resume-execution. Resume at Task 3 (Third thing)."
hand=$(cat "$HANDOFF")
has "mid-plan: handoff keeps earlier sections" "$hand" "Keep me."
has "mid-plan: handoff keeps later sections" "$hand" "## Do not"
lacks "mid-plan: handoff drops the stale block" "$hand" "Old stale block."
check "mid-plan: handoff has one Next session section" "$(grep -c '^## Next session' "$HANDOFF")" "1"
has "mid-plan: handoff carries the new next step" "$hand" "Resume at Task 3 (Third thing)."
lacks "mid-plan: no assigned-line warning" "$(cat "$TMP/stderr")" "warning"

# --- a ledger ending on an assigned line warns, and still prints the block ---
ledger 'Task 1: complete (commits a..b, review clean)' \
       'Task 2: implementer impl-sonnet-low (assigned; base bbbbbbb; executor codex gpt-6.1-sol/low, thread pending)'
run "$REPO" "$PLAN_REL"
check "thread pending: exits 0" "$status" "0"
has "thread pending: still prints the block" "$out" "**Next:** Resume at Task 2 (Second thing)."
lacks "thread pending: no warning names the pending thread" "$(cat "$TMP/stderr")" "thread pending"
ledger 'Task 1: complete (commits a..b, review clean)' \
       'Task 2: implementer dforge:impl-sonnet-high (assigned; base bbbbbbb)'
run "$REPO" "$PLAN_REL"
has "agent assigned: warns on stderr" "$(cat "$TMP/stderr")" "the ledger ends on an assigned line for Task 2"
ledger 'Task 1: complete (commits a..b, review clean)' \
       'Task 2: implementer inline (assigned; base bbbbbbb)'
run "$REPO" "$PLAN_REL"
lacks "inline assigned: no warning, the controller is the implementer" "$(cat "$TMP/stderr")" "warning"

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
has "tasks done: next is final review then finishing" "$out" "**Next:** Run the final whole-branch review, then dforge:finishing-a-development-branch."

# --- --complete with a next sub-project ---
printf '# Handoff\n\n## Goal\nOld goal.\n\n## Next session\nOld.\n' > "$HANDOFF"
rm -rf "$LEDGER_DIR"
run "$REPO" --complete "$PLAN_REL"
check "complete/next: exits 0" "$status" "0"
has "complete/next: status" "$out" "**Status:** Plan \`$PLAN_REL\` is complete; sub-project 2 of 5 is done."
has "complete/next: next sub-project" "$out" "**Next:** Sub-project 3 (Session budget): write its spec in a fresh session."
has "complete/next: planning launch command" "$out" "claude --model opus --effort high"
has "complete/next: brainstorming prompt" "$out" "Start sub-project 3 (Session budget) of the program in \`docs/specs/program.md\`: use dforge:brainstorming to write its spec."
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
has "inline: prompt names executing-plans" "$out" "with dforge:executing-plans."
has "inline: command without backticks" "$out" "claude --model sonnet --effort medium"
write_plan "$PLAN" '**Execution:** inline — codex gpt-6.1-sol / high — Codex host' ""
run "$REPO" "$PLAN_REL"
has "codex pair: the launch command names the Codex client" "$out" "codex -m gpt-6.1-sol -c model_reasoning_effort=high"
lacks "codex pair: no claude command" "$out" "claude --model"
write_plan "$PLAN" '**Execution:** inline — whatever the owner pinned' ""
run "$REPO" "$PLAN_REL"
has "an Execution line naming no pair: points at the Execution line" "$out" "Launch from \`$ROOT\`: see the **Execution:** line in \`$PLAN_REL\`."

# --- CRLF plan ---
write_plan "$PLAN" "$EXEC_SUB" "$PROG_NEXT"
sed 's/$/\r/' "$PLAN" > "$PLAN.tmp" && mv "$PLAN.tmp" "$PLAN"
run "$REPO" "$PLAN_REL"
has "crlf: tasks still counted" "$out" "0 of 3 tasks complete"
lacks "crlf: no carriage return in output" "$out" $'\r'

# --- worktree: ledger in the worktree, handoff in the worktree ---
write_plan "$PLAN" "$EXEC_SUB" "$PROG_NEXT"
WT="$TMP/wt"
git -C "$REPO" worktree add -q -b feat "$WT"
WT_ROOT="$(git -C "$WT" rev-parse --show-toplevel)"
mkdir -p "$WT/.dforge/sdd/2026-01-01-demo"
printf '# SDD ledger — plan: %s\nTask 1: complete (x)\n' "$PLAN_REL" > "$WT/.dforge/sdd/2026-01-01-demo/progress.md"
rm -f "$HANDOFF"
run "$WT" "$PLAN_REL"
has "worktree: reads the worktree ledger" "$out" "1 of 3 tasks complete"
has "worktree: launch dir is the worktree" "$out" "Launch in \`$WT_ROOT\`:"
check "worktree: handoff written in the worktree" "$([ -f "$WT_ROOT/.dforge/handoff/latest.md" ] && echo yes || echo no)" "yes"
check "worktree: no handoff in the primary" "$([ -f "$HANDOFF" ] && echo yes || echo no)" "no"
rm -f "$WT_ROOT/.dforge/handoff/latest.md"
mkdir -p "$WT/.dforge/sdd" "$REPO/.dforge/sdd"
printf '{"action":"pr"}\n' > "$WT/.dforge/sdd/finish.json"
printf '{"action":"pr"}\n' > "$REPO/.dforge/sdd/finish.json"
run "$WT" --adhoc --phase build --next "Ship the fix"
check "worktree: adhoc clears the no-plan record finish-choice wrote there" "$([ -e "$WT/.dforge/sdd/finish.json" ] && echo kept || echo gone)" "gone"
check "worktree: adhoc clears the primary's no-plan record too" "$([ -e "$REPO/.dforge/sdd/finish.json" ] && echo kept || echo gone)" "gone"
# The primary finds a worktree's ledger, so the cases below start from none.
rm -rf "$WT/.dforge/sdd/2026-01-01-demo"

# --- handoff write failure still prints the block ---
rm -rf "$REPO/.dforge/handoff"
printf 'not a dir' > "$REPO/.dforge/handoff"
run "$REPO" "$PLAN_REL"
check "unwritable handoff: exits 4" "$status" "4"
has "unwritable handoff: block still printed" "$out" "**Next:** Start at Task 1 (First thing)."
has "unwritable handoff: says so on stderr" "$(cat "$TMP/stderr")" "could not write"
has "unwritable handoff: says so on stdout" "$out" "next-step: could not write"
rm -f "$REPO/.dforge/handoff"

# --- final review clean: finishing is next ---
ledger 'Task 1: complete (x)' 'Task 2: complete (x)' 'Task 3: complete (x)' "Final review: clean (commits a1b2c3d..$(git -C "$REPO" rev-parse --short HEAD))"
run "$REPO" "$PLAN_REL"
has "final review clean: status" "$out" "**Status:** Plan \`$PLAN_REL\`: all 3 tasks complete; the final review is clean."
has "final review clean: next is finishing" "$out" "**Next:** Run dforge:finishing-a-development-branch."
has "final review clean: prompt routes through resume-execution" "$out" "Resume \`$PLAN_REL\` with dforge:resume-execution. Run dforge:finishing-a-development-branch."
rm -rf "$LEDGER_DIR"

# --- draft mode: a design phase hands off ---
mkdir -p "$REPO/docs/specs" "$REPO/.dforge/handoff"
printf '# Draft\n' > "$REPO/docs/specs/draft.md"
printf '# Handoff\n\n## State\nKeep me.\n\n## Next session\nOld block.\n' > "$HANDOFF"
run "$REPO" --draft docs/specs/draft.md --next "Write the implementation plan with dforge:writing-plans"
check "draft: exits 0" "$status" "0"
has "draft: status names the authority" "$out" "**Status:** Design in progress: \`docs/specs/draft.md\` is the authority."
has "draft: next action gains a full stop" "$out" "**Next:** Write the implementation plan with dforge:writing-plans."
has "draft: planning launch command" "$out" "claude --model opus --effort high"
has "draft: prompt" "$out" "Continue from \`docs/specs/draft.md\` (the authority): Write the implementation plan with dforge:writing-plans. Read \`$ROOT/.dforge/handoff/latest.md\` first."
hand=$(cat "$HANDOFF")
has "draft: handoff keeps the notes" "$hand" "Keep me."
lacks "draft: handoff drops the stale block" "$hand" "Old block."
run "$REPO" --draft docs/specs/draft.md
check "draft without --next: exits 2" "$status" "2"
run "$REPO" --draft docs/specs/missing.md --next "x"
check "draft of a missing file: exits 2" "$status" "2"

# --- adhoc mode: unplanned work hands off, latest.md is the authority ---
printf '# Handoff\n\n## State\nItem C unscoped.\n\n## Next session\nOld block.\n' > "$HANDOFF"
run "$REPO" --adhoc --phase design --next "Scope item C with dforge:brainstorming"
check "adhoc design: exits 0" "$status" "0"
has "adhoc: status names the authority" "$out" "**Status:** Unplanned work: the notes in \`$ROOT/.dforge/handoff/latest.md\` are the authority."
has "adhoc: next action gains a full stop" "$out" "**Next:** Scope item C with dforge:brainstorming."
has "adhoc design: opus launch command" "$out" "claude --model opus --effort high"
has "adhoc: prompt" "$out" "Continue the unplanned work recorded in \`$ROOT/.dforge/handoff/latest.md\`: Scope item C with dforge:brainstorming."
hand=$(cat "$HANDOFF")
has "adhoc: handoff keeps the notes" "$hand" "Item C unscoped."
lacks "adhoc: handoff drops the stale block" "$hand" "Old block."
check "adhoc: the state directory ignores itself" "$(git -C "$REPO" status --porcelain --untracked-files=all -- .dforge)" ""
run "$REPO" --adhoc --phase build --next "Commit items A and B"
check "adhoc build: exits 0" "$status" "0"
has "adhoc build: sonnet launch command" "$out" "claude --model sonnet --effort high"
lacks "adhoc build: no opus launch command" "$out" "claude --model opus"
run "$REPO" --adhoc --next "x"
check "adhoc without --phase: exits 2" "$status" "2"
run "$REPO" --adhoc --phase plan --next "x"
check "adhoc with an unknown phase: exits 2" "$status" "2"
run "$REPO" --adhoc --phase design
check "adhoc without --next: exits 2" "$status" "2"
run "$REPO" --adhoc --phase design --next "x" docs/plans/2026-01-01-demo.md
check "adhoc with a plan argument: exits 2" "$status" "2"

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

# --- an older ledger's escalation line ---
# Subagent mode was retired, so the line switches nothing: the Execution line
# still decides the launch command.
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
INL_LEDGER="$REPO/.dforge/sdd/2026-01-01-inline"
mkdir -p "$INL_LEDGER"
{
  echo "# SDD ledger — plan: docs/plans/2026-01-01-inline.md"
  echo "Task 1: implementer inline (assigned; base aaaaaaa)"
  echo "Task 1: complete (commits aaaaaaa..bbbbbbb, unreviewed) — done: x; verified: y → ok; remaining: none; discovered: none; assumptions: none"
  echo "Task 2: implementer inline (assigned; base bbbbbbb)"
  echo "Task 2: fix round 3/3 (build still red; commits bbbbbbb..ccccccc; still failing)"
  echo "Task 2: escalated inline -> subagent — still failing after fix round 3/3  "
} > "$INL_LEDGER/progress.md"

run "$REPO" docs/plans/2026-01-01-inline.md
has "escalation line: keeps the inline pair" "$out" "claude --model sonnet --effort low"
lacks "escalation line: no subagent pair" "$out" "--effort high"

# --- a mixed ledger: a delegated task mid-loop in an inline plan ---
# Mixed mode writes subagent grammar for a delegated task. An agent-named
# assignment is not a switch, and the plan stays in inline mode.
{
  echo "# SDD ledger — plan: docs/plans/2026-01-01-inline.md"
  echo "Task 1: implementer inline (assigned; base aaaaaaa)"
  echo "Task 1: complete (commits aaaaaaa..bbbbbbb, unreviewed) — done: x; verified: y → ok; remaining: none; discovered: none; assumptions: none"
  echo "Task 2: implementer dforge:impl-sonnet-high (assigned; base bbbbbbb)"
  echo "Task 2: fix round 2/5 (1 addressed, 1 open — x; commits bbbbbbb..ccccccc; progress 9 -> 12; resumed)"
} > "$INL_LEDGER/progress.md"
run "$REPO" docs/plans/2026-01-01-inline.md
has "mixed ledger: keeps the inline pair" "$out" "claude --model sonnet --effort low"
has "mixed ledger: resumes the delegated task" "$out" "Resume at Task 2 (Second)."

# --- a ledger that quotes the escalation marker ---
# The marker is its own ledger line, not a substring match anywhere in the
# ledger; a deferred-minor sentence describing the grammar is not an
# escalation.
QUOTE="$REPO/docs/plans/2026-01-01-quote.md"
cat > "$QUOTE" <<'PLAN'
# Quote plan

**Goal:** demo

**Spec:** docs/spec.md

**Execution:** inline — `claude --model sonnet --effort low` — every task scores 2

## Task index

1. First

### Task 1: First
PLAN
QUOTE_LEDGER="$REPO/.dforge/sdd/2026-01-01-quote"
mkdir -p "$QUOTE_LEDGER"
{
  echo "# SDD ledger — plan: docs/plans/2026-01-01-quote.md"
  echo "Task 1: implementer inline (assigned; base aaaaaaa)"
  echo "Task 1: minor (deferred): the Recovery row calls this a line \`Task N: escalated inline -> subagent\`, harmless"
} > "$QUOTE_LEDGER/progress.md"

run "$REPO" docs/plans/2026-01-01-quote.md
lacks "quoted clause: does not launch the subagent pair" "$out" "--effort high"

# --- the ledger identity may carry an absolute or Windows-form path ---
ABS_LEDGER="$REPO/.dforge/sdd/2026-01-01-quote"
abs_plan="$(cd "$REPO" && pwd)/docs/plans/2026-01-01-quote.md"
{
  echo "# SDD ledger — plan: $abs_plan"
  echo "Task 1: implementer inline (assigned; base aaaaaaa)"
  echo "Task 1: complete (commits aaaaaaa..bbbbbbb, unreviewed) — done: x; verified: y → ok; remaining: none; discovered: none; assumptions: none"
} > "$ABS_LEDGER/progress.md"
run "$REPO" docs/plans/2026-01-01-quote.md
has "absolute identity path: ledger recognised" "$out" "all 1 tasks complete"
lacks "absolute identity path: not treated as another plan's" "$out" "belongs to another plan"

# --- a Program next-title ending in "last" is not the final sub-project ---
LASTP="$REPO/docs/plans/2026-01-01-lastword.md"
cat > "$LASTP" <<'PLAN'
# Last-word plan

**Goal:** demo

**Spec:** docs/spec.md

**Execution:** inline — `claude --model sonnet --effort high` — x

**Program:** `docs/spec.md` — sub-project 1 of 3 — next: Cleanup at last

## Task index

1. First

### Task 1: First
PLAN
run "$REPO" --complete docs/plans/2026-01-01-lastword.md
has "next title ending in last: names the next sub-project" "$out" "Sub-project 2 (Cleanup at last)"
lacks "next title ending in last: not read as the final one" "$out" "every sub-project of"

# --- outside a repository the documented exit is 2 ---
out=$(cd "$TMP" && bash "$SCRIPT" "$(cd "$REPO" && pwd)/docs/plans/2026-01-01-quote.md" 2>/dev/null); status=$?
check "outside a repository: exits 2" "$status" "2"

# --- a BLOCKED task is terminal: no launch, a human decides ---
# The skills say never re-dispatch a BLOCKED task; a resume guide that said
# "Start at Task 2" would do exactly that.
BLK="$REPO/docs/plans/2026-01-01-blocked.md"
cat > "$BLK" <<'PLAN'
# Blocked plan

**Goal:** demo

**Spec:** docs/spec.md

**Execution:** inline — `claude --model sonnet --effort high` — Task 2 scores 4

## Task index

1. First
2. Second
3. Third

### Task 1: First

### Task 2: Second

### Task 3: Third
PLAN
BLK_LEDGER="$REPO/.dforge/sdd/2026-01-01-blocked"
mkdir -p "$BLK_LEDGER"
{
  echo "# SDD ledger — plan: docs/plans/2026-01-01-blocked.md"
  echo "Task 1: implementer impl-sonnet-low (assigned; base aaaaaaa)"
  echo "Task 1: complete (commits aaaaaaa..bbbbbbb, review clean) — done: x; verified: y → ok; remaining: none; discovered: none; assumptions: none"
  echo "Task 2: implementer impl-sonnet-high (assigned; base bbbbbbb)"
  echo "Task 2: BLOCKED — ruling seat — whether the export keeps the legacy field"
} > "$BLK_LEDGER/progress.md"

run "$REPO" docs/plans/2026-01-01-blocked.md
check "blocked: exits 0" "$status" "0"
has "blocked: status names the task" "$out" "1 of 3 tasks complete; Task 2 is BLOCKED"
has "blocked: next carries the decision" "$out" "Your human partner decides: whether the export keeps the legacy field."
lacks "blocked: no start or resume instruction" "$out" "Resume at Task"
lacks "blocked: no launch command" "$out" "Launch in"
has "blocked: latest.md carries the block" "$(cat "$REPO/.dforge/handoff/latest.md")" "Task 2 is BLOCKED"
printf '%s\n' "Task 2: BLOCKED — ruling seat — pick the store - sqlite or files" >> "$BLK_LEDGER/progress.md"
run "$REPO" docs/plans/2026-01-01-blocked.md
has "blocked: a decision with a dash of its own is carried whole" "$out" "Your human partner decides: pick the store - sqlite or files."

# Writers share no temporary path: one another writer left behind, or holds,
# does not stop this one, and two at once leave one well-formed block.
mkdir -p "$REPO/.dforge/handoff/latest.md.tmp"
run "$REPO" docs/plans/2026-01-01-blocked.md
check "handoff: another writer's temporary path does not block the write" "$status" "0"
rmdir "$REPO/.dforge/handoff/latest.md.tmp"
(cd "$REPO" && bash "$SCRIPT" docs/plans/2026-01-01-blocked.md >/dev/null 2>&1) &
(cd "$REPO" && bash "$SCRIPT" docs/plans/2026-01-01-blocked.md >/dev/null 2>&1) &
wait
check "handoff: concurrent writers leave one Next session block" "$(grep -c '^## Next session' "$REPO/.dforge/handoff/latest.md")" "1"
check "handoff: no temporary file is left beside it" "$(ls -A "$REPO/.dforge/handoff" | grep -cv '^latest.md$')" "0"
# A note another writer adds to the handoff while next-step holds its copy must
# survive: the slowed awk delivers the merged copy two seconds after it read
# the file, and the other writer appends under the same lock meanwhile.
REAL_AWK=$(command -v awk)
SLOW_BIN="$TMP/slow-awk"; mkdir -p "$SLOW_BIN"
cat > "$SLOW_BIN/awk" <<SLOW
#!/usr/bin/env bash
case "\$*" in
  *'## Next session'*) "$REAL_AWK" "\$@" > "$TMP/awk-out"; touch "$TMP/awk-read"; sleep 2; cat "$TMP/awk-out" ;;
  *) exec "$REAL_AWK" "\$@" ;;
esac
SLOW
chmod +x "$SLOW_BIN/awk"
rm -f "$TMP/awk-read"
(cd "$REPO" && PATH="$SLOW_BIN:$PATH" bash "$SCRIPT" docs/plans/2026-01-01-blocked.md >/dev/null 2>&1) &
for _ in $(seq 100); do [ -e "$TMP/awk-read" ] && break; sleep 0.1; done
( . "$HERE/../../plugins/dforge/scripts/lib/lock.sh"
  dr_locked "$(dr_lock_base "$REPO/.dforge/handoff/latest.md")" bash -c 'printf "\n## Notes\nkept by the other writer\n" >> "$1"' _ "$REPO/.dforge/handoff/latest.md" )
wait
check "handoff: a note added during the write is kept" "$(grep -c 'kept by the other writer' "$REPO/.dforge/handoff/latest.md")" "1"
check "handoff: and one Next session block remains" "$(grep -c '^## Next session' "$REPO/.dforge/handoff/latest.md")" "1"

# --- Codex host: the launch command names the Codex client, not Claude ---
# The session knows its host (native-codex.md identifies it from callable tool
# schemas, never from an executable), so the adhoc and draft paths take it as a
# flag. A plan carries `Host: codex` in its header instead.
CODEX_DESIGN='codex -m gpt-6.1-sol -c model_reasoning_effort=high'
CODEX_BUILD='codex -m gpt-6.1-sol -c model_reasoning_effort=high'

run "$REPO" --adhoc --phase design --host codex --next "Scope item C with dforge:brainstorming"
check "adhoc design on codex: exits 0" "$status" "0"
has "adhoc design on codex: sol launch command" "$out" "$CODEX_DESIGN"
lacks "adhoc design on codex: no astra launch command" "$out" "gpt-6-astra"
lacks "adhoc design on codex: no claude launch command" "$out" "claude --model"
run "$REPO" --adhoc --phase build --host codex --next "Commit items A and B"
check "adhoc build on codex: exits 0" "$status" "0"
has "adhoc build on codex: sol launch command" "$out" "$CODEX_BUILD"
run "$REPO" --draft docs/specs/draft.md --host codex --next "Write the implementation plan with dforge:writing-plans"
check "draft on codex: exits 0" "$status" "0"
has "draft on codex: sol launch command" "$out" "$CODEX_DESIGN"
run "$REPO" --adhoc --phase build --host claude --next "Commit items A and B"
has "an explicit --host claude: keeps the claude launch command" "$out" "claude --model sonnet --effort high"
run "$REPO" --adhoc --phase build --host gemini --next "x"
check "an unknown --host: exits 2" "$status" "2"
run "$REPO" --adhoc --phase build --host --next "x"
check "--host without a value: exits 2" "$status" "2"

# A Codex plan's launch command comes from its own Execution line, exactly as a
# Claude plan's does. The header, not the flag, tells the plan path its host.
CODEX_PLAN_REL="docs/plans/2026-01-01-codex.md"
CODEX_PLAN="$REPO/$CODEX_PLAN_REL"
CODEX_LEDGER_DIR="$REPO/.dforge/sdd/2026-01-01-codex"
EXEC_CODEX='**Host:** codex

**Routing policy:** codex-v4

**Execution:** inline — `codex gpt-6.1-sol / medium` — every task totals 4 or less'
write_plan "$CODEX_PLAN" "$EXEC_CODEX" "$PROG_NEXT"
run "$REPO" "$CODEX_PLAN_REL"
check "codex plan: exits 0" "$status" "0"
has "codex plan: launch command from the Execution line" "$out" "codex -m gpt-6.1-sol -c model_reasoning_effort=medium"
lacks "codex plan: no fallback to reading the Execution line" "$out" "see the **Execution:** line"

run "$REPO" --complete "$CODEX_PLAN_REL"
check "codex plan complete: exits 0" "$status" "0"
has "codex plan complete: the next sub-project launches the design tier" "$out" "$CODEX_DESIGN"
lacks "codex plan complete: no claude launch command" "$out" "claude --model"

mkdir -p "$CODEX_LEDGER_DIR"
{ printf '# SDD ledger — plan: %s
' "$CODEX_PLAN_REL"
  printf 'Task 1: complete (commits a..b, review clean)
'
  printf 'Task 2: escalated inline -> subagent — fix round 3/3
'; } > "$CODEX_LEDGER_DIR/progress.md"
run "$REPO" "$CODEX_PLAN_REL"
check "codex plan, old escalation line: exits 0" "$status" "0"
has "codex plan, old escalation line: keeps the Execution pair" "$out" "model_reasoning_effort=medium"
lacks "codex plan, old escalation line: no claude launch command" "$out" "claude --model"


# --- the same directory under a second POSIX spelling ---
# Under Git Bash /tmp and /c/Users/…/Temp can name one directory, so stripping
# pwd output off the plan path degrades the status line to an absolute path
# wherever the two spellings differ. Git resolves the relative path instead.
ALIAS_PLAN_REL="docs/plans/2026-01-01-alias.md"
case $ROOT in
  [A-Za-z]:/*)
    ALT="/$(printf '%s' "${ROOT%%:*}" | tr '[:upper:]' '[:lower:]')${ROOT#?:}"
    if [ -d "$ALT" ] && [ "$ALT" != "$(cd "$REPO" && pwd)" ]; then
      write_plan "$REPO/$ALIAS_PLAN_REL" "$EXEC_SUB" ""
      run "$ALT" "$ALIAS_PLAN_REL"
      check "mount alias: exits 0" "$status" "0"
      has "mount alias: the plan path stays relative" "$out" "Plan \`$ALIAS_PLAN_REL\`"
    fi
    ;;
esac

# --- item registers outrank the Program line ---
# The frozen `next:` is copied when the plan is written, so a sub-project split
# decided later never reaches it. A register with an open row must stop the
# "every sub-project is done" answer.
RREPO="$TMP/registers"
git init -q -b main "$RREPO"
mkdir -p "$RREPO/docs/dforge/plans" "$RREPO/docs/dforge/specs" "$RREPO/docs/dforge/registers"
printf '.dforge/\n' > "$RREPO/.gitignore"
: > "$RREPO/docs/dforge/specs/prog-design.md"
cat > "$RREPO/docs/dforge/plans/c1.md" <<'PLAN'
# C1

**Goal:** One
**Spec:** docs/superpowers/specs/prog-design.md
**Execution:** inline — `claude --model sonnet --effort high` — small
**Program:** `docs/superpowers/specs/prog-design.md` — sub-project 3 of 4 — last

### Task 1: One
PLAN
git -C "$RREPO" add -A && git -C "$RREPO" commit -qm init

cat > "$RREPO/docs/dforge/registers/prog.md" <<'REG'
# Programme — item register

**Source:** owner list 2026-09-18
**Covers:** docs/superpowers/specs/prog-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Status bar | - | - | done | - |
| 4 | Settings tabs | C2 Settings | Radius follows the axis | planned | - |
| 6 | Editor preview | C2 Settings | - | planned | - |
| 16 | Stale note | C2 Settings | - | planned | - |
| 17 | Unused UI font | C2 Settings | - | planned | - |
REG

OUT=$(cd "$RREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/c1.md 2>&1)
has "next-step: a register with open rows refuses 'Nothing'" "$OUT" "Register rows still open (4) in \`docs/dforge/registers/prog.md\`"
has "next-step: names the first rows" "$OUT" "#4 Settings tabs"
has "next-step: caps the list at three" "$OUT" "+1 more"
has "next-step: routes to the assignment" "$OUT" "\`C2 Settings\`: write its spec in a fresh session."
lacks "next-step: must not claim the program is done" "$OUT" "Nothing — every sub-project"

# An unassigned row routes to brainstorming instead.
bash "$HERE/../../plugins/dforge/scripts/register" set "$RREPO/docs/dforge/registers/prog.md" 4 open --assigned -
bash "$HERE/../../plugins/dforge/scripts/register" set "$RREPO/docs/dforge/registers/prog.md" 6 done
bash "$HERE/../../plugins/dforge/scripts/register" set "$RREPO/docs/dforge/registers/prog.md" 16 done
bash "$HERE/../../plugins/dforge/scripts/register" set "$RREPO/docs/dforge/registers/prog.md" 17 done
OUT=$(cd "$RREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/c1.md 2>&1)
has "next-step: an unassigned row routes to brainstorming" "$OUT" "Rule on the open rows with dforge:brainstorming."
has "next-step: one row still reports" "$OUT" "Register rows still open (1) in"

# Every row resolved: the Program line answers again, exactly as before.
bash "$HERE/../../plugins/dforge/scripts/register" set "$RREPO/docs/dforge/registers/prog.md" 4 done
OUT=$(cd "$RREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/c1.md 2>&1)
has "next-step: a fully resolved register restores the old answer" "$OUT" "Nothing — every sub-project"

# No register at all: unchanged behaviour, which is what keeps every existing
# plan in this repository working.
rm "$RREPO/docs/dforge/registers/prog.md"
OUT=$(cd "$RREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/c1.md 2>&1)
has "next-step: no register means no change" "$OUT" "Nothing — every sub-project"

# --- register routing: the Assigned cell decides the next step ---
# A row still assigned to the plan that just finished, or to one completed.md
# records, must not route back to it; an assigned plan is executed, not
# re-specified; verify rows and other repositories' rows are not work here.
GREPO="$TMP/routing"
git init -q -b main "$GREPO"
mkdir -p "$GREPO/docs/dforge/plans" "$GREPO/docs/dforge/specs" "$GREPO/docs/dforge/registers"
printf '.dforge/\n' > "$GREPO/.gitignore"
: > "$GREPO/docs/dforge/specs/lane-design.md"
: > "$GREPO/docs/dforge/specs/rev-design.md"
for p in inc1 inc2 inc3; do
  effort=high
  [ "$p" = inc3 ] && effort=medium
  cat > "$GREPO/docs/dforge/plans/$p.md" <<PLAN
# $p

**Goal:** $p
**Spec:** docs/superpowers/specs/lane-design.md
**Execution:** inline — \`claude --model sonnet --effort $effort\` — small

### Task 1: One
PLAN
done
printf '# Completed plans\n\n- 2026-01-01 `docs/superpowers/plans/inc1.md` — merged into `main` at abc1234\n' \
  > "$GREPO/docs/dforge/plans/completed.md"
cat > "$GREPO/docs/dforge/registers/lane.md" <<'REG'
# Lane — item register

**Source:** owner list 2026-01-01
**Covers:** docs/superpowers/specs/lane-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Search and UI | docs/superpowers/plans/inc2.md | - | doing | - |
| 2 | Verbatim bodies | docs/superpowers/plans/inc1.md | - | verify | awaiting deploy |
| 3 | Sync client | other-repo: docs/superpowers/plans/sync.md | - | planned | - |
| 4 | Loose end | - | - | open | - |
| 5 | Revisions | docs/superpowers/plans/inc3.md | - | planned | - |
| 6 | Leftover | docs/superpowers/plans/inc1.md | - | open | - |
REG
git -C "$GREPO" add -A && git -C "$GREPO" commit -qm init
GREG="$GREPO/docs/dforge/registers/lane.md"

OUT=$(cd "$GREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/inc2.md 2>&1)
has "routing: still reports every unresolved row" "$OUT" "Register rows still open (6)"
has "routing: an assigned plan is executed" "$OUT" "Continue \`docs/superpowers/plans/inc3.md\` with dforge:executing-plans."
has "routing: launches the assigned plan's Execution pair" "$OUT" "claude --model sonnet --effort medium"
lacks "routing: never asks for a spec of a plan" "$OUT" "write its spec"
has "routing: names rows left on finished plans" "$OUT" "Still assigned to a finished plan: #1, #6"

# Either docs prefix names the same plan (spec §7.1): a completed.md entry and
# an Assigned cell spelled docs/dforge/ match the docs/superpowers/ plan.
printf '# Completed plans\n\n- 2026-01-01 `docs/dforge/plans/inc1.md` — merged into `main` at abc1234\n' \
  > "$GREPO/docs/dforge/plans/completed.md"
bash "$HERE/../../plugins/dforge/scripts/register" set "$GREG" 1 doing --assigned docs/dforge/plans/inc2.md >/dev/null
OUT=$(cd "$GREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/inc2.md 2>&1)
has "routing: either prefix names a finished plan" "$OUT" "Still assigned to a finished plan: #1, #6"
printf '# Completed plans\n\n- 2026-01-01 `docs/superpowers/plans/inc1.md` — merged into `main` at abc1234\n' \
  > "$GREPO/docs/dforge/plans/completed.md"
bash "$HERE/../../plugins/dforge/scripts/register" set "$GREG" 1 doing --assigned docs/superpowers/plans/inc2.md >/dev/null

# The reverse direction: Assigned cells spelled docs/forge/ match the plan
# being completed and a completed.md entry spelled docs/superpowers/.
bash "$HERE/../../plugins/dforge/scripts/register" set "$GREG" 1 doing --assigned docs/forge/plans/inc2.md >/dev/null
bash "$HERE/../../plugins/dforge/scripts/register" set "$GREG" 6 open --assigned docs/forge/plans/inc1.md >/dev/null
OUT=$(cd "$GREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/inc2.md 2>&1)
has "routing: docs/forge cells name docs/superpowers plans" "$OUT" "Still assigned to a finished plan: #1, #6"
bash "$HERE/../../plugins/dforge/scripts/register" set "$GREG" 1 doing --assigned docs/superpowers/plans/inc2.md >/dev/null
bash "$HERE/../../plugins/dforge/scripts/register" set "$GREG" 6 open --assigned docs/superpowers/plans/inc1.md >/dev/null

# An absolute Assigned cell is named from the roots: one naming the plan being
# completed and one naming a finished plan are both stale.
bash "$HERE/../../plugins/dforge/scripts/register" set "$GREG" 1 doing --assigned "$GREPO/docs/dforge/plans/inc2.md" >/dev/null
bash "$HERE/../../plugins/dforge/scripts/register" set "$GREG" 6 open --assigned "$GREPO/docs/dforge/plans/inc1.md" >/dev/null
OUT=$(cd "$GREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/inc2.md 2>&1)
has "routing: absolute Assigned cells name finished plans" "$OUT" "Still assigned to a finished plan: #1, #6"
bash "$HERE/../../plugins/dforge/scripts/register" set "$GREG" 1 doing --assigned docs/superpowers/plans/inc2.md >/dev/null
bash "$HERE/../../plugins/dforge/scripts/register" set "$GREG" 6 open --assigned docs/superpowers/plans/inc1.md >/dev/null

# From a linked worktree, an Assigned cell naming the primary checkout's copy
# of a finished plan is stale too. The worktree holds the committed register
# and completed.md (row 1 on inc2, row 6 on inc1, inc1 recorded).
GWT="$TMP/routing-wt"
git -C "$GREPO" worktree add -q -b routing-side "$GWT"
bash "$HERE/../../plugins/dforge/scripts/register" set "$GWT/docs/dforge/registers/lane.md" 6 open --assigned "$GREPO/docs/dforge/plans/inc1.md" >/dev/null
OUT=$(cd "$GWT" && bash "$SCRIPT" --complete docs/superpowers/plans/inc2.md 2>&1)
has "routing: a worktree names the primary checkout's absolute plan path" "$OUT" "Still assigned to a finished plan: #1, #6"
git -C "$GREPO" worktree remove --force "$GWT"
git -C "$GREPO" branch -q -D routing-side

# The deepest root wins, as in the JavaScript mapping: a cell naming a copy in a
# worktree nested inside the primary checkout is that worktree's plan, not a
# file of the primary named .nested-wt/docs/….
NWT="$GREPO/.nested-wt"
git -C "$GREPO" worktree add -q -b routing-nested "$NWT"
bash "$HERE/../../plugins/dforge/scripts/register" set "$GREG" 6 open --assigned "$NWT/docs/dforge/plans/inc1.md" >/dev/null
OUT=$(cd "$GREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/inc2.md 2>&1)
has "routing: a name in a nested worktree is named from that worktree" "$OUT" "Still assigned to a finished plan: #1, #6"
git -C "$GREPO" worktree remove --force "$NWT"
git -C "$GREPO" branch -q -D routing-nested
bash "$HERE/../../plugins/dforge/scripts/register" set "$GREG" 6 open --assigned docs/superpowers/plans/inc1.md >/dev/null

mkdir -p "$GREPO/.dforge/sdd/inc3"
printf '# SDD ledger — plan: docs/superpowers/plans/inc3.md\n' > "$GREPO/.dforge/sdd/inc3/progress.md"
OUT=$(cd "$GREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/inc2.md 2>&1)
has "routing: an assigned plan with a ledger resumes" "$OUT" "Resume \`docs/superpowers/plans/inc3.md\` with dforge:resume-execution."
printf '# SDD ledger — plan: docs/dforge/plans/inc3.md\nTask 1: complete (x)\n' > "$GREPO/.dforge/sdd/inc3/progress.md"
OUT=$(cd "$GREPO" && bash "$SCRIPT" docs/superpowers/plans/inc3.md 2>&1)
has "ledger check: an identity line under the other prefix is this plan's" "$OUT" "all 1 tasks complete."
rm -rf "$GREPO/.dforge/sdd/inc3"

bash "$HERE/../../plugins/dforge/scripts/register" set "$GREG" 5 planned --assigned docs/superpowers/specs/rev-design.md
OUT=$(cd "$GREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/inc2.md 2>&1)
has "routing: an assigned spec gets its plan" "$OUT" "\`docs/superpowers/specs/rev-design.md\`: write its plan with dforge:writing-plans."
has "routing: planning launches the design pair" "$OUT" "claude --model opus --effort high"

printf '# P\n\n### Task A1: One\n' > "$GREPO/docs/dforge/plans/lettered.md"
bash "$HERE/../../plugins/dforge/scripts/register" set "$GREG" 5 planned --assigned docs/superpowers/plans/lettered.md
OUT=$(cd "$GREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/inc2.md 2>&1)
has "routing: a plan with lettered headings is a plan, not a spec" "$OUT" "Continue \`docs/superpowers/plans/lettered.md\` with dforge:"
rm -f "$GREPO/docs/dforge/plans/lettered.md"

bash "$HERE/../../plugins/dforge/scripts/register" set "$GREG" 5 done
OUT=$(cd "$GREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/inc2.md 2>&1)
has "routing: an unassigned row outranks rows on finished plans" "$OUT" "Rule on the open rows with dforge:brainstorming."

bash "$HERE/../../plugins/dforge/scripts/register" set "$GREG" 4 done
OUT=$(cd "$GREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/inc2.md 2>&1)
has "routing: nothing routable names the stale rows" "$OUT" "Still assigned to a finished plan: #1, #6"
has "routing: nothing routable names the verify rows" "$OUT" "Awaiting your check (verify): #2."
has "routing: nothing routable names other repositories' rows" "$OUT" "Assigned outside this repository: #3."
lacks "routing: nothing routable launches nothing" "$OUT" "Launch in"

# --- a roadmap outranks the Program line ---
# On a greenfield project the next epic comes from the current milestone's
# register, never from a copied `next:`; with nothing open the milestone goes
# to its audit, and only when every milestone is closed is there nothing to do.
MREPO="$TMP/roadmap"
git init -q -b main "$MREPO"
MD="$MREPO/docs/dforge"
mkdir -p "$MD/plans" "$MD/specs" "$MD/registers"
printf '.dforge/\n' > "$MREPO/.gitignore"
: > "$MD/specs/shop-design.md"
: > "$MD/specs/billing-design.md"
cat > "$MD/plans/billing.md" <<'PLAN'
# Billing

**Goal:** Billing
**Spec:** docs/superpowers/specs/billing-design.md
**Execution:** inline — `claude --model sonnet --effort high` — small
**Program:** `docs/superpowers/specs/shop-design.md` — sub-project 1 of 2 — last

### Task 1: One
PLAN
cat > "$MD/registers/m1.md" <<'REG'
# M1 — item register

**Source:** roadmap
**Covers:** docs/superpowers/specs/shop-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Billing | docs/superpowers/specs/billing-design.md | - | verify | built; owner confirms at the milestone audit |
| 2 | Search | Search | - | open | - |
REG
cat > "$MD/roadmap.md" <<'RM'
# Shop — roadmap

**Product:** a shop
**Spec:** docs/superpowers/specs/shop-design.md

| M | Name | Exit criteria | Register | State | Note |
|---|---|---|---|---|---|
| M1 | MVP | every epic resolved | docs/superpowers/registers/m1.md | open | - |
RM
git -C "$MREPO" add -A && git -C "$MREPO" commit -qm init

OUT=$(cd "$MREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/billing.md 2>&1)
has "roadmap: the forgotten epic is the next step" "$OUT" "\`Search\`: write its spec in a fresh session."
has "roadmap: the built epic waits on the owner" "$OUT" "#1 Billing"
lacks "roadmap: the Program line's 'last' is not believed" "$OUT" "Nothing — every sub-project"

bash "$HERE/../../plugins/dforge/scripts/register" set "$MD/registers/m1.md" 2 n/a --note "owner dropped search" >/dev/null
# A verify row waits on the milestone audit, so it must lead there rather than
# stop at "awaiting your check".
OUT=$(cd "$MREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/billing.md 2>&1)
has "roadmap: only verify rows go to the audit" "$OUT" "Milestone M1 (MVP) has nothing else open: audit and close it with dforge:closing-a-milestone."
has "roadmap: the verify rows are named" "$OUT" "Awaiting your check (verify): #1."
has "roadmap: a verify-only audit gets a launch prompt" "$OUT" "Close milestone M1 (MVP)"

# A requirements register covering the milestone's spec joins the audit the
# same way: its verify rows go there, and an open row keeps the work first.
cat > "$MD/registers/billing-requirements.md" <<'REG'
# Billing requirements

**Source:** spec
**Covers:** docs/superpowers/specs/billing-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Pay invoice | - | owner check | verify | built |
REG
OUT=$(cd "$MREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/billing.md 2>&1)
has "roadmap: verify requirements join the audit" "$OUT" 'Close milestone M1 (MVP)'
bash "$HERE/../../plugins/dforge/scripts/register" set "$MD/registers/billing-requirements.md" 1 open >/dev/null
OUT=$(cd "$MREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/billing.md 2>&1)
lacks "roadmap: open requirements prevent audit routing" "$OUT" 'Close milestone M1 (MVP)'
bash "$HERE/../../plugins/dforge/scripts/register" set "$MD/registers/billing-requirements.md" 1 verify >/dev/null
bash "$HERE/../../plugins/dforge/scripts/roadmap" close --root "$MREPO" M1 --note audit >/dev/null 2>&1
check "roadmap: verify rows still require sign-off" "$?" 1
bash "$HERE/../../plugins/dforge/scripts/register" set "$MD/registers/billing-requirements.md" 1 done --note 'audit: MET' >/dev/null
bash "$HERE/../../plugins/dforge/scripts/register" set "$MD/registers/m1.md" 1 done >/dev/null
OUT=$(cd "$MREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/billing.md 2>&1)
has "roadmap: nothing open goes to the audit" "$OUT" "Milestone M1 (MVP) has nothing open: audit and close it with dforge:closing-a-milestone."
has "roadmap: the audit gets a launch prompt" "$OUT" "Close milestone M1 (MVP)"

# A register covering the plan's spec but sitting outside the milestone is not
# below it, so the audit cannot resolve its verify rows.
: > "$MD/specs/other-design.md"
cat > "$MD/plans/other.md" <<'PLAN'
# Other

**Goal:** Other
**Spec:** docs/superpowers/specs/other-design.md
**Execution:** inline — `claude --model sonnet --effort high` — small
**Program:** `docs/superpowers/specs/other-design.md` — sub-project 1 of 1 — last

### Task 1: One
PLAN
cat > "$MD/registers/other.md" <<'REG'
# Other — item register

**Source:** spec
**Covers:** docs/superpowers/specs/other-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Outside the milestone | - | owner check | verify | built |
REG
OUT=$(cd "$MREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/other.md 2>&1)
has "roadmap: a verify row outside the milestone waits on the owner" "$OUT" "Awaiting your check (verify): #1."
lacks "roadmap: a verify row outside the milestone is not an audit" "$OUT" "Close milestone M1 (MVP)"
lacks "roadmap: a verify row outside the milestone is not audited" "$OUT" "audit and close it"
rm "$MD/plans/other.md" "$MD/registers/other.md"

bash "$HERE/../../plugins/dforge/scripts/roadmap" close --root "$MREPO" M1 --note "audit: 1 MET" >/dev/null
OUT=$(cd "$MREPO" && bash "$SCRIPT" --complete docs/superpowers/plans/billing.md 2>&1)
has "roadmap: every milestone closed" "$OUT" "Nothing — every milestone in \`docs/dforge/roadmap.md\` is closed."
lacks "roadmap: closed launches nothing" "$OUT" "Launch in"

# --- documents and progress kept in darkmem ---
# --- a service-only list does not stop the block ---
SID=s-next; export CLAUDE_CODE_SESSION_ID=$SID
NT="$TMP/$SID.jsonl"
mkdir -p "$HOME/.claude/dforge/sessions/by-id"
jq -n --arg tp "$NT" '{session_id:"s-next",transcript_path:$tp}' > "$HOME/.claude/dforge/sessions/by-id/$SID.json"
jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_dev",name:"Bash",input:{description:"Dev server",command:"npm run dev",run_in_background:true}}]}}' > "$NT"
jq -nc '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_dev",content:"Command running in background with ID: d1. Output is being written to: /tmp/d1.output."}]}}' >> "$NT"
run "$REPO" "$PLAN_REL"
check "service only: exits 0" "$status" "0"
has "service only: the block is printed" "$out" "## Next session"
has "service only: the services are named" "$out" "Still running services: shell d1 (Dev server)"
rm -f "$HOME/.claude/dforge/sessions/by-id/$SID.json"; unset CLAUDE_CODE_SESSION_ID

# --- a clean final review is current only for the head it names (C5) ---
done3() { ledger 'Task 1: complete (commits a..b, review clean)' 'Task 2: complete (commits b..c, review clean)' 'Task 3: complete (commits c..d, review clean)' "$@"; }
git -C "$REPO" checkout -q -b feat-c5
head7=$(git -C "$REPO" rev-parse --short HEAD)
done3 "Final review: clean (commits 0000000..$head7)"
run "$REPO" "$PLAN_REL"
has "C5: current clean line routes to finishing" "$out" "**Next:** Run dforge:finishing-a-development-branch."
mkdir -p "$REPO/docs/dforge/plans" && printf 'note\n' > "$REPO/docs/dforge/plans/completed.md"
git -C "$REPO" add docs/dforge/plans/completed.md && git -C "$REPO" commit -qm "docs: index"
run "$REPO" "$PLAN_REL"
has "C5: docs-only commits after the head keep it current" "$out" "**Next:** Run dforge:finishing-a-development-branch."
# A git call that fails is no evidence the head still covers HEAD.
REAL_GIT=$(command -v git)
for verb in 'rev-list --first-parent' 'log --format= --name-only'; do
  mkdir -p "$TMP/git-fails"
  printf '#!/usr/bin/env bash\ncase " $* " in *" %s "*) exit 128 ;; esac\nexec "%s" "$@"\n' "$verb" "$REAL_GIT" > "$TMP/git-fails/git"
  chmod +x "$TMP/git-fails/git"
  out=$(cd "$REPO" && PATH="$TMP/git-fails:$PATH" bash "$SCRIPT" "$PLAN_REL" 2>/dev/null)
  has "C5: a failed git ${verb%% *} routes to a scoped re-review, not finishing" "$out" "Re-review $head7..HEAD"
done
rm -rf "$TMP/git-fails"
printf 'x\n' > "$REPO/code.txt" && git -C "$REPO" add code.txt && git -C "$REPO" commit -qm "fix: later"
run "$REPO" "$PLAN_REL"
has "C5: a later code commit routes to a scoped re-review" "$out" "Re-review $head7..HEAD"
git -C "$REPO" reset -q --hard "$head7" && git -C "$REPO" commit -q --amend -m "rewritten"
run "$REPO" "$PLAN_REL"
has "C5: a rewritten head routes to a full final review" "$out" "Run the final whole-branch review, then dforge:finishing-a-development-branch."
head7=$(git -C "$REPO" rev-parse --short HEAD)
done3 "Final review: clean (commits 0000000..$head7)"
git -C "$REPO" checkout -q -
git -C "$REPO" merge -q --no-ff --allow-unrelated-histories -m "merge feat-c5" feat-c5
merge7=$(git -C "$REPO" rev-parse --short HEAD)
run "$REPO" "$PLAN_REL"
has "C5: a base branch that merged the head routes to finishing" "$out" "**Next:** Run dforge:finishing-a-development-branch."
printf 'note\n' > "$REPO/docs/dforge/plans/after-merge.md"
git -C "$REPO" add docs/dforge/plans/after-merge.md && git -C "$REPO" commit -qm "docs: after merge"
run "$REPO" "$PLAN_REL"
has "C5: docs-only commits after the merge keep it current" "$out" "**Next:** Run dforge:finishing-a-development-branch."
printf 'y\n' > "$REPO/base.txt" && git -C "$REPO" add base.txt && git -C "$REPO" commit -qm "fix: on base"
run "$REPO" "$PLAN_REL"
has "C5: a code commit after the merge routes to a re-review from the merge" "$out" "Re-review $merge7..HEAD"
git -C "$REPO" reset -q --hard HEAD~3 && git -C "$REPO" branch -qD feat-c5

# --- Keep as-is keeps the branch pending (C9) ---
ledger 'Task 1: complete (commits a..b, review clean)' 'Task 2: complete (commits b..c, review clean)' 'Task 3: complete (commits c..d, review clean)' 'Final review: clean (commits a..d)'
mkdir -p "$REPO/.dforge/sdd" && printf '{"action":"pr"}\n' > "$REPO/.dforge/sdd/finish.json"
run "$REPO" --kept "$PLAN_REL"
check "kept: exits 0" "$status" "0"
has "kept: names the branch" "$out" "$(git -C "$REPO" branch --show-current)"
lacks "kept: never says complete" "$out" "is complete"
has "kept: the finish choices stay open" "$out" "merge, pr or discard"
check "kept: the no-plan finish record is cleared" "$([ -e "$REPO/.dforge/sdd/finish.json" ] && echo kept || echo gone)" "gone"

. "$HERE/fixtures/darkmem-stores.sh"
SH="$TMP/stores-home"; mkdir -p "$SH"
SR="$TMP/stores-repo"
git init -q "$SR"
git -C "$SR" commit -q --allow-empty -m init
M=$(stores_home "$SH" "$SR" proj darkmem darkmem)
mkdir -p "$M/dforge/plans" "$M/work/sdd/2026-02-02-mirror"
write_plan "$M/dforge/plans/2026-02-02-mirror.md" '**Execution:** inline — `claude --model sonnet --effort high` — demo' ""
printf '# SDD ledger — plan: docs/dforge/plans/2026-02-02-mirror.md\nTask 1: complete (commits a..b, review clean)\n' \
  > "$M/work/sdd/2026-02-02-mirror/progress.md"
out=$(cd "$SR" && HOME=$SH bash "$SCRIPT" docs/dforge/plans/2026-02-02-mirror.md)
check "darkmem: exit 0" "$?" "0"
has "darkmem: the plan is named" "$out" "docs/dforge/plans/2026-02-02-mirror.md"
has "darkmem: the mirror ledger is read" "$out" "ledger \`$M/work/sdd/2026-02-02-mirror/progress.md\`"
check "darkmem: latest.md is written to the mirror" \
  "$(grep -c '^## Next session' "$M/work/handoff/latest.md")" "1"
check "darkmem: only latest.md and dotfiles sit beside it" "$(ls -A "$M/work/handoff" | grep -v '^\.' | tr '\n' ' ')" "latest.md "
check "darkmem: nothing is written in the checkout" "$([ -e "$SR/.dforge/handoff/latest.md" ] && echo yes || echo no)" "no"

# --- per-worktree handoffs (spec A2, A3, A6, A13, A14) ---
# The Keep as-is block left a ledger for this plan in the primary; plan_ledger_any
# checks the caller's checkout first, so it would make the primary T.
rm -rf "$LEDGER_DIR"
rm -rf "$HOME/.dforge" "$REPO/.dforge/handoff"
# A Program line and an open register row, so --complete and --project print a block.
write_plan "$PLAN" "$EXEC_SUB" "$PROG_NEXT"
OTHER_REL="docs/plans/2026-01-02-other.md"
write_plan "$REPO/$OTHER_REL" "$EXEC_SUB" ""
mkdir -p "$REPO/docs/dforge/registers"
printf '# Demo — item register\n\n**Source:** test\n**Covers:** -\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | Open item | - | - | open | - |\n' \
  > "$REPO/docs/dforge/registers/demo.md"
git -C "$REPO" add "$PLAN_REL" "$OTHER_REL" docs/dforge/registers/demo.md && git -C "$REPO" commit -qm "two plans"
WA="$TMP/wa"; WB="$TMP/wb"
git -C "$REPO" worktree add -q -b wa "$WA"; git -C "$REPO" worktree add -q -b wb "$WB"
WA_ROOT=$(git -C "$WA" rev-parse --show-toplevel); WB_ROOT=$(git -C "$WB" rev-parse --show-toplevel)
WA_H="$WA_ROOT/.dforge/handoff/latest.md"; WB_H="$WB_ROOT/.dforge/handoff/latest.md"
# The primary holds both plans' workspaces, as a plan review leaves them.
mkdir -p "$REPO/.dforge/sdd/2026-01-01-demo" "$REPO/.dforge/sdd/2026-01-02-other" \
  "$WA/.dforge/sdd/2026-01-01-demo" "$WB/.dforge/sdd/2026-01-02-other"
printf 'lint\n' > "$REPO/.dforge/sdd/2026-01-01-demo/plan-lint.txt"
printf 'lint\n' > "$REPO/.dforge/sdd/2026-01-02-other/plan-lint.txt"
printf '# SDD ledger — plan: %s\nTask 1: complete (x)\n' "$PLAN_REL" > "$WA/.dforge/sdd/2026-01-01-demo/progress.md"
printf '# SDD ledger — plan: %s\nTask 1: complete (x)\n' "$OTHER_REL" > "$WB/.dforge/sdd/2026-01-02-other/progress.md"
run "$WA" "$PLAN_REL"; run "$WB" "$OTHER_REL"
has "A2: the first worktree holds its plan's block" "$(cat "$WA_H")" "$PLAN_REL"
lacks "A2: the first worktree does not name the other plan" "$(cat "$WA_H")" "2026-01-02-other"
has "A2: the second worktree holds its plan's block" "$(cat "$WB_H")" "$OTHER_REL"
lacks "A2: the second worktree does not name the first plan" "$(cat "$WB_H")" "2026-01-01-demo"
check "A2: the primary's handoff is not written" "$([ -f "$HANDOFF" ] && echo yes || echo no)" "no"
rm -f "$WA_H"
run "$REPO" "$PLAN_REL"
has "A3: from the primary, the block launches in the ledger's worktree" "$out" "Launch in \`$WA_ROOT\`:"
check "A3: from the primary, the worktree's handoff is written" "$([ -f "$WA_H" ] && echo yes || echo no)" "yes"
check "A3: from the primary, the primary's handoff is not written" "$([ -f "$HANDOFF" ] && echo yes || echo no)" "no"
check "A13: --target from the primary names the worktree's handoff" "$(cd "$REPO" && bash "$SCRIPT" --target "$PLAN_REL")" "$WA_H"
rm -f "$WA_H"
check "A13: --target writes nothing" "$(cd "$WA" && bash "$SCRIPT" --target "$PLAN_REL" >/dev/null; [ -f "$WA_H" ] && echo yes || echo no)" "no"
check "A13: --target for adhoc work names this checkout's" "$(cd "$WB" && bash "$SCRIPT" --target --adhoc --phase build --next x)" "$WB_H"
(cd "$REPO" && bash "$SCRIPT" --target --latest >/dev/null 2>&1); check "A13: --target with --latest is a usage error" "$?" "2"
(cd "$REPO" && bash "$SCRIPT" --target docs/plans/missing.md >/dev/null 2>&1); check "A13: --target of a missing plan exits 2" "$?" "2"
# A13, every mode: --target names exactly the file the same call then writes.
# Paths as git spells them (C:/… on Windows Git Bash), as --target prints them.
written() { local f; for f in "$ROOT/.dforge/handoff/latest.md" "$WA_H" "$WB_H"; do [ -f "$f" ] && printf '%s ' "$f"; done; }
for args in "$PLAN_REL" "--complete $PLAN_REL" "--kept $PLAN_REL" "--draft $OTHER_REL --next x" "--adhoc --phase build --next x" "--project"; do
  rm -f "$HANDOFF" "$WA_H" "$WB_H"
  # shellcheck disable=SC2086
  t=$(cd "$WA" && bash "$SCRIPT" --target $args 2>/dev/null)
  # shellcheck disable=SC2086
  run "$WA" $args
  check "A13: --target names the file written ($args)" "$(written)" "$t "
done
rm -f "$HANDOFF" "$WA_H" "$WB_H"
# A13: background work running never stops --target (the stub in-flight reports a live launch).
rm -rf "$TMP/stubscripts" && cp -R "$(dirname "$SCRIPT")" "$TMP/stubscripts"
printf '#!/usr/bin/env bash\nprintf -- "- shell b1 10:00 idle 1m sleep\\n"\nexit 1\n' > "$TMP/stubscripts/in-flight"
(cd "$WA" && bash "$TMP/stubscripts/next-step" "$PLAN_REL" >/dev/null 2>&1); check "A13: the in-flight stub makes a plain run exit 5" "$?" "5"
t=$(cd "$WA" && bash "$TMP/stubscripts/next-step" --target "$PLAN_REL" 2>/dev/null); status=$?
check "A13: --target with background work running exits 0 and names the path" "$status:$t" "0:$WA_H"
rm -rf "$TMP/stubscripts"
rm -f "$HANDOFF" "$WA_H"
run "$WA" --complete "$PLAN_REL"
has "A6: --complete launches in the primary" "$out" "Launch in \`$ROOT\`:"
check "A6: --complete writes the primary's handoff" "$([ -f "$HANDOFF" ] && echo yes || echo no)" "yes"
rm -f "$HANDOFF" "$WA_H"
run "$WA" --kept "$PLAN_REL"
check "A6: --kept writes the handoff of the checkout it runs in" "$([ -f "$WA_H" ] && echo yes || echo no):$([ -f "$HANDOFF" ] && echo yes || echo no)" "yes:no"
rm -f "$WA_H"
# --- launch line and prompt (spec A4, A5, A15) ---
launch_of() { awk '/^Launch in /{f=1; next} f && /^```$/{ if (g) exit; g=1; next } f && g { print; exit }' <<<"$1"; }
mkdir -p "$TMP/stub"
printf '#!/bin/sh\npwd -P > "%s"\n' "$TMP/started" > "$TMP/stub/claude"; chmod +x "$TMP/stub/claude"
# A Windows Git Bash host has cygpath on PATH and gets no prefix (spec §3).
if command -v cygpath >/dev/null 2>&1; then a4_pre=""; else a4_pre="cd '$WA_ROOT' && "; fi
run "$WA" "$PLAN_REL"
launch=$(launch_of "$out")
check "A4: cd prefix on a POSIX host only" "$launch" "${a4_pre}claude --model sonnet --effort high"
if [ -n "$a4_pre" ]; then
  rm -f "$TMP/started"; (cd / && PATH="$TMP/stub:$PATH" bash -c "$launch")
  check "A4: the launch starts in the worktree" "$(cat "$TMP/started" 2>/dev/null)" "$(cd "$WA" && pwd -P)"
  ODD="$TMP/it's here"; git -C "$REPO" worktree add -q -b odd "$ODD"
  run "$ODD" --adhoc --phase build --next x
  rm -f "$TMP/started"; (cd / && PATH="$TMP/stub:$PATH" bash -c "$(launch_of "$out")")
  check "A4: a path with a space and a quote survives" "$(cat "$TMP/started" 2>/dev/null)" "$(cd "$ODD" && pwd -P)"
  printf '#!/bin/sh\nfor a; do last=$a; done\nprintf "%%s\\n" "$last"\n' > "$TMP/stub/cygpath"; chmod +x "$TMP/stub/cygpath"
  out=$(cd "$WA" && PATH="$TMP/stub:$PATH" bash "$SCRIPT" "$PLAN_REL" 2>/dev/null)
  check "A4: with cygpath on PATH no cd prefix" "$(launch_of "$out")" "claude --model sonnet --effort high"
  rm -f "$TMP/stub/cygpath"
fi
# A Codex Execution line gets the same prefix (spec §3); WA reads its own copy of the plan.
write_plan "$WA/$PLAN_REL" '**Execution:** inline — codex gpt-6.1-sol / high — Codex host' "$PROG_NEXT"
run "$WA" "$PLAN_REL"
check "A4: a Codex launch gets the same prefix" "$(launch_of "$out")" "${a4_pre}codex -m gpt-6.1-sol -c model_reasoning_effort=high"
git -C "$WA" checkout -q -- "$PLAN_REL"
start="Start in \`$WA_ROOT\` (branch wa); its handoff is \`$WA_H\`. If your working directory is not \`$WA_ROOT\`, enter it first."
for args in "$PLAN_REL" "--draft $OTHER_REL --next x" "--adhoc --phase build --next x" "--project" "--kept $PLAN_REL"; do
  run "$WA" $args
  has "A5: prompt opens with Start in ($args)" "$out" "$start"
  lacks "A5: no First enter ($args)" "$out" "First enter the existing worktree"
done
run "$WA" --complete "$PLAN_REL"
has "A5: complete's prompt starts in the primary" "$out" "Start in \`$ROOT\`"
git -C "$WA" checkout -q --detach
run "$WA" --adhoc --phase build --next x
has "A5: a detached checkout" "$out" "Start in \`$WA_ROOT\` (detached at \`$(git -C "$WA" rev-parse --short HEAD)\`)"
git -C "$WA" checkout -q wa
printf '# Handoff\n\n## State\nKeep these notes.\n\n## Next session\n\n**Next:** other\n<!-- next-step: kind=adhoc done=0 closed=0 subject=- at=1 -->\n' > "$HANDOFF"
run "$WA" --complete "$PLAN_REL"
has "A15: complete over another live block keeps the notes" "$(cat "$HANDOFF")" "Keep these notes."
lacks "A15: and replaces its block" "$(cat "$HANDOFF")" "**Next:** other"
has "A15: stderr names the kind" "$(cat "$TMP/stderr")" "next-step: replaced the block for adhoc"
printf '# Handoff\n\n## State\nOld notes.\n\n## Next session\n\n**Next:** x\n<!-- next-step: kind=plan done=0 closed=0 subject=%s at=1 -->\n' "$PLAN_REL" > "$HANDOFF"
run "$WA" --complete "$PLAN_REL"
lacks "A15: its own plan's block is replaced wholesale" "$(cat "$HANDOFF")" "Old notes."
printf '# Handoff\n\n## State\nOld notes.\n\n## Next session\n\n**Next:** x\n<!-- next-step: kind=complete done=0 closed=0 subject=%s at=1 -->\n' "$OTHER_REL" > "$HANDOFF"
run "$WA" --complete "$PLAN_REL"
lacks "A15: a complete marker is replaced wholesale" "$(cat "$HANDOFF")" "Old notes."
mkdir -p "${WA_H%/*}"
printf '# Handoff\n\n## State\nWA notes.\n\n## Next session\n\n**Next:** y\n<!-- next-step: kind=plan done=0 closed=0 subject=%s at=1 -->\n' "$OTHER_REL" > "$WA_H"
run "$WA" --kept "$PLAN_REL"
has "A15: kept over another plan's block keeps the notes" "$(cat "$WA_H")" "WA notes."
has "A15: stderr names the subject" "$(cat "$TMP/stderr")" "next-step: replaced the block for $OTHER_REL"
CM="$WA/$(dirname "$OTHER_REL")/completed.md"; rm -f "$TMP/cm.bak"; [ ! -f "$CM" ] || cp "$CM" "$TMP/cm.bak"
printf -- '- 2026-01-02 `%s` — merged into `main`\n' "$OTHER_REL" >> "$CM"
printf '# Handoff\n\n## State\nFinished notes.\n\n## Next session\n\n**Next:** y\n<!-- next-step: kind=plan done=0 closed=0 subject=%s at=1 -->\n' "$OTHER_REL" > "$WA_H"
run "$WA" --kept "$PLAN_REL"
lacks "A15: a finished plan's block is replaced wholesale" "$(cat "$WA_H")" "Finished notes."
lacks "A15: and stderr names no replaced block" "$(cat "$TMP/stderr")" "replaced the block"
if [ -f "$TMP/cm.bak" ]; then mv "$TMP/cm.bak" "$CM"; else rm -f "$CM"; fi
rm -f "$HANDOFF" "$WA_H"
# A14: darkmem progress, ledger in the mirror; the primary also holds the workspace.
. "$HERE/fixtures/darkmem-stores.sh"
MIRROR=$(stores_home "$HOME" "$REPO" demo local darkmem)
mkdir -p "$MIRROR/work/sdd/2026-01-01-demo"
printf '# SDD ledger — plan: %s\nTask 1: complete (x)\n' "$PLAN_REL" > "$MIRROR/work/sdd/2026-01-01-demo/progress.md"
rm -f "$WA/.dforge/sdd/2026-01-01-demo/progress.md"
run "$REPO" "$PLAN_REL"
has "A14: darkmem: launches in the worktree holding the workspace" "$out" "Launch in \`$WA_ROOT\`:"
has "A14: darkmem: the prompt starts in the worktree" "$out" "Start in \`$WA_ROOT\`"
check "A14: darkmem: the worktree's handoff is written" "$([ -f "$WA_H" ] && echo yes || echo no)" "yes"
check "A14: darkmem: the mirror's handoff is not written" "$([ -f "$MIRROR/work/handoff/latest.md" ] && echo yes || echo no)" "no"
# Both worktrees hold the workspace: the calling one is T, not the first listed.
mkdir -p "$WB/.dforge/sdd/2026-01-01-demo"; rm -f "$WA_H" "$WB_H"
run "$WB" "$PLAN_REL"
has "A14: darkmem: the calling worktree holding the workspace launches" "$out" "Launch in \`$WB_ROOT\`:"
check "A14: darkmem: the first worktree's handoff is not written" "$([ -f "$WA_H" ] && echo yes || echo no)" "no"
# Only the primary holds it: a linked worktree's call makes the primary T.
rm -rf "$WA/.dforge/sdd/2026-01-01-demo" "$WB/.dforge/sdd/2026-01-01-demo"; rm -f "$WA_H" "$WB_H"
run "$WB" "$PLAN_REL"
has "A14: darkmem: only the primary holding the workspace launches there" "$out" "Launch in \`$ROOT\`:"
check "A14: darkmem: the calling worktree's handoff is not written" "$([ -f "$WB_H" ] && echo yes || echo no)" "no"
rm -rf "$HOME/.dforge"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
