#!/usr/bin/env bash
# Inline mode is a document, and the claims that make it work are structural:
# which scripts it calls, which references it links, which ledger lines it
# shares with subagent mode, and which ruling-seat kinds it claims. A model is
# not needed to check any of them, so they are checked here instead of in a
# review.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
INLINE="$P/skills/executing-plans/SKILL.md"
SDD="$P/skills/subagent-driven-development/SKILL.md"
FINAL="$P/reference/final-review.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
absent() { # absent <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}

for f in "$INLINE" "$SDD" "$FINAL"; do
  check "exists: $(basename "$(dirname "$f")")/$(basename "$f")" \
    "$([ -f "$f" ] && echo yes || echo no)" "yes"
done

# The scripts inline mode must call. Reading the plan directly would skip
# amendments; skipping next-step would end a session without a next action.
for s in 'task-brief --header' 'task-brief PLAN_FILE N' 'sdd-workspace' 'context-size' 'next-step' 'plan-amend'; do
  present "calls $s" "$INLINE" "$s"
done

# The two skills a finished or interrupted run hands control to. Dropping
# either would strand a session with nowhere to go.
present "names handoff" "$INLINE" "dr-superpowers:handoff"
present "names finishing" "$INLINE" "dr-superpowers:finishing-a-development-branch"

# Only the first 5,000 tokens of a skill body come back after compaction, so
# the recovery instructions have to be at the top.
check "opens with After compaction" \
  "$(grep -m 1 '^## ' "$INLINE")" "## After compaction"

# Links, and the files they point at.
present "links the shared final review" "$INLINE" "../../reference/final-review.md"
present "links the ruling prompt" "$INLINE" "../subagent-driven-development/references/ruling-prompt.md"
check "the shared final review exists" \
  "$([ -f "$P/reference/final-review.md" ] && echo yes || echo no)" "yes"
check "the ruling prompt exists" \
  "$([ -f "$P/skills/subagent-driven-development/references/ruling-prompt.md" ] && echo yes || echo no)" "yes"

# final-review.md's own links are outside validate-repository.mjs's coverage
# (it walks skills/, not reference/), so this suite is the only thing pinning
# them.
present "final review links the code reviewer" "$FINAL" "../skills/requesting-code-review/references/code-reviewer.md"
check "the code reviewer reference exists" \
  "$([ -f "$P/skills/requesting-code-review/references/code-reviewer.md" ] && echo yes || echo no)" "yes"
present "final review links the external executor" "$FINAL" "external-executor.md"
check "the external executor reference exists" \
  "$([ -f "$P/reference/external-executor.md" ] && echo yes || echo no)" "yes"
present "final review links the re-review prompt" "$FINAL" "../skills/subagent-driven-development/references/re-review-prompt.md"
check "the re-review prompt exists" \
  "$([ -f "$P/skills/subagent-driven-development/references/re-review-prompt.md" ] && echo yes || echo no)" "yes"

# The mode is chosen by the plan, not by whether subagents exist.
absent "drops the upstream subagent-availability note" "$INLINE" \
  "works much better with access to subagents"

# The three ruling-seat kinds this mode can reach, and the four it cannot.
for k in blocked-plan plan-conflict final-residual; do
  present "claims the $k kind" "$INLINE" "\`$k\`"
done
# The skill names all seven kinds - three it runs and four it explains away -
# so "states the three and no others" is not greppable. Assert the three plus
# the sentence that excludes the rest.
present "names the one kind it never runs" "$INLINE" 'Only `codex-empty-diff` belongs to a seat this mode never runs'
for k in preflight cannot-verify breaker; do
  present "claims the $k kind for delegated work" "$INLINE" "\`$k\`"
done
present "reads the Dispatch line" "$INLINE" '`**Dispatch:** delegated'
present "links the delegated loop" "$INLINE" "../../reference/delegated-task.md"
present "passes the plan to context-size" "$INLINE" 'context-size --plan PLAN_FILE'
present "subagent mode passes the plan to context-size" "$SDD" 'context-size --plan PLAN_FILE'
present "a delegated task hands off at the next ledger write" "$INLINE" 'In a delegated task, act at the next ledger write'
present "a delegating plan gets a preflight" "$INLINE" 'send one `preflight` item'
present "the preflight keys on a heavy task" "$INLINE" 'naming at least one `(heavy)` task'
absent "the kinds table no longer keys the preflight on any delegation" "$INLINE" 'when the plan delegates any task'
present "the preflight arises only for a heavy task" "$INLINE" '`preflight` arises only for a plan with a heavy task'
present "inline mode names both delegation reasons" "$INLINE" '`**Dispatch:** delegated — Task <a> (heavy), Task <b> (total 4)`'
present "writing-plans defines four-band tasks" "$P/skills/writing-plans/SKILL.md" 'A task is **four-band**'
present "writing-plans delegates total-4 tasks up to a third" "$P/skills/writing-plans/SKILL.md" 'are a third of the plan or fewer (`3 x four-band <= N`)'
present "using-superpowers names total-4 delegation" "$P/skills/using-superpowers/SKILL.md" 'total-4 tasks while they are a third of the plan or fewer'
present "README names both reasons for delegation" "$P/README.md" 'while they are a third of the plan or fewer, which then get an independent'
present "the delegated loop names both reasons" "$P/reference/delegated-task.md" 'or a total-4 task in a plan where those are a third of the tasks or'
present "inline routes the ruling seat" "$INLINE" '`scripts/review-route PLAN_FILE --ruling <kind> [<task> ...]`'
present "inline confirms a Header amendment" "$INLINE" 'A Header amendment from `judge-opus` is confirmed by `judge-fable`'
absent "inline drops the no-preflight sentence" "$INLINE" 'There is no pre-flight scan.'
absent "inline no longer names judge-fable as the ruling seat" "$INLINE" '`dr-superpowers:judge-fable` (`dr-superpowers:judge-opus` when Fable is'
present "inline translates a delegated task's agent" "$INLINE" "translate a delegated task's \`**Implementer:**\` agent before dispatching it"
absent "inline drops the all-inert legacy sentence" "$INLINE" 'no task is dispatched, so their names need no translation'
present "a return to inline starts at a task that is not delegated" "$INLINE" 'The return takes effect at the first remaining task that is not delegated'

# The fix cap, and the escalation clause both skills key on.
present "states the fix cap" "$INLINE" "fix round R/3"
present "inline writes the escalation line" "$INLINE" "Task <N>: escalated inline -> subagent — <trigger>"
present "subagent mode reads the escalation line" "$SDD" "escalated inline -> subagent"
present "inline fix rounds record their outcome" "$INLINE" "passing | still failing"
absent "inline no longer marks the switch on a fix-round line" "$INLINE" "escalated inline -> subagent)"

# One ledger grammar for both modes.
for line in 'minor (deferred)' 'parked' 'BLOCKED' 'Ruling:' 'Final review: clean'; do
  present "inline ledger has: $line" "$INLINE" "$line"
  present "subagent ledger has: $line" "$SDD" "$line"
done
present "inline marks an unreviewed completion" "$INLINE" "unreviewed"
present "inline assigns itself" "$INLINE" "implementer inline"

# The final review lives in one place now.
present "subagent mode links the shared final review" "$SDD" "final-review.md"
absent "subagent mode no longer spells out the package call" "$SDD" \
  "review-package PLAN_FILE MERGE_BASE HEAD"
absent "inline mode does not spell out the package call" "$INLINE" \
  "review-package PLAN_FILE MERGE_BASE HEAD"
present "the shared reference spells out the package call" "$FINAL" \
  "review-package PLAN_FILE MERGE_BASE HEAD"
present "the shared reference names both modes" "$FINAL" "Inline mode"
present "final review routes the Claude seat" "$FINAL" '`scripts/review-route PLAN_FILE --final` and dispatch'
absent "final review drops the most capable model" "$FINAL" 'most capable'
present "final review routes the fix subagent" "$FINAL" '`scripts/review-route PLAN_FILE --final-fix <file> [<file> ...]`'
present "final review ledgers the fix subagent" "$FINAL" '`Final fix: implementer <agent> (assigned; base <sha7>)`'
absent "subagent mode drops the most capable final seat" "$SDD" 'most capable available'
absent "subagent mode drops the most capable final reviewer" "$SDD" 'final reviewer on the most capable model'
present "subagent ledger has the Final fix line" "$SDD" 'Final fix: implementer <agent> (assigned; base <sha7>)'
present "subagent mode recovers a lost fix wave" "$SDD" 'A `Final fix:` line and no `Final review:` line'
present "inline mode names the final seat" "$INLINE" '`scripts/review-route PLAN_FILE --final` prints'
present "judge-fable takes an intricate final review" "$P/agents/judge-fable.md" 'the final whole-branch review of an intricate plan'
present "judge-opus takes a plain final review" "$P/agents/judge-opus.md" 'the final whole-branch review of a plain plan'
present "README names the final seats" "$P/README.md" 'The final whole-branch review runs on `judge-fable` for an intricate plan'

# A standing project constraint outranks a spec, so both execution skills read
# it at Setup. Without this, a plan can be executed against a constraint and
# nothing notices until a handoff.
for f in "$INLINE" "$SDD"; do
  present "setup loads distilled constraints: $(basename "$(dirname "$f")")" \
    "$f" 'distilled/constraints.md'
done

# Gates run before the reviewers are dispatched: reviewing a branch that does
# not build wastes both reviewer seats.
present "final review runs gates first" "$FINAL" 'dr-superpowers:running-gates'
present "a red gate stops the review" "$FINAL" 'A red gate stops'

# The dedupe seat runs only over two lists; one list goes to the fixer's triage
# and the re-review rules on every rejection.
RRP="$P/skills/subagent-driven-development/references/re-review-prompt.md"
present "final review dedupes only two lists" "$FINAL" '**Dedupe and verify, only with two lists.**'
present "final review names the one-list case" "$FINAL" '**With one list**'
present "the fixer records rejections" "$FINAL" 'under `REJECTED: <finding>`'
present "disputed rejections go to the ruling seat" "$FINAL" '`REJECTION DISPUTED` in the'
present "the re-review rules on rejections" "$RRP" 'REJECTION UPHELD |'
present "an upheld rejection closes" "$RRP" 'An upheld rejection is closed; a disputed one is open.'
present "the Codex round rationale covers one list" "$P/reference/external-executor.md" 'with one list the'
absent "README drops the always-third-seat claim" "$P/README.md" 'which is why every finding goes through a third seat'

# --- the delegated loop: one copy, shared by both execution skills ---
DT="$P/reference/delegated-task.md"
check "exists: reference/delegated-task.md" "$([ -f "$DT" ] && echo yes || echo no)" "yes"
for h in '## Contract' '## Seats' '## 1. Dispatch the implementer' '## 2. Handle the report' \
         '## 3. Review the task' '## 4. The fix loop' '## 5. Complete the task' '## Recovery'; do
  check "delegated loop heading: $h" "$(grep -cxF -- "$h" "$DT")" "1"
done
for h in '### 1. Dispatch the implementer' '### 2. Handle the report' '### 3. Review the task' \
         '### 4. The fix loop' '### 5. Complete the task'; do
  check "subagent mode no longer holds: $h" "$(grep -cxF -- "$h" "$SDD")" "0"
done
present "subagent mode links the delegated loop" "$SDD" "../../reference/delegated-task.md"
present "subagent mode defers per-task recovery" "$SDD" 'Apply [delegated-task.md](../../reference/delegated-task.md) §Recovery'
# validate-repository.mjs checks links only under skills/, so this suite pins
# the reference file's links.
for link in $(grep -oE '\]\([^)#]+\.md' "$DT" | sed 's/^](//' | sort -u); do
  check "delegated loop link resolves: $link" "$([ -f "$P/reference/$link" ] && echo yes || echo no)" "yes"
done

# --- the Dispatch line: mixed mode's delegation, computed by task-brief ---
DTMP=$(mktemp -d)
sed 's/^|//' > "$DTMP/plan.md" <<'EOF'
|# Mixed
|
|**Execution:** inline — `claude --model opus --effort high` — x
|
|### Task 1: light
|
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 2: heavy
|
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5
|
|### Task 3: split
|
|#### Part A: small
|
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|#### Part B: risky
|
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 3 = 4
EOF
brief() { bash "$P/scripts/task-brief" "$@" >/dev/null 2>&1; }
brief "$DTMP/plan.md" 1 "$DTMP/b1.md"
check "a light task has no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/b1.md")" "0"
brief "$DTMP/plan.md" 2 "$DTMP/b2.md"
check "a heavy task's second line is the Dispatch line" "$(sed -n 2p "$DTMP/b2.md")" "**Dispatch:** delegated — total 5, risk 2"
brief "$DTMP/plan.md" 3 "$DTMP/b3.md"
check "a split task carries its highest total and risk" "$(sed -n 2p "$DTMP/b3.md")" "**Dispatch:** delegated — total 4, risk 3"
brief --header "$DTMP/plan.md" "$DTMP/h.md"
check "the header lists the delegated tasks with reasons" "$(tail -n 1 "$DTMP/h.md")" "**Dispatch:** delegated — Task 2 (heavy), Task 3 (heavy)"
sed 's/^\*\*Evaluation:\*\* files 1 - spec 1 - coupling 1 - risk 2 = 5$/**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4/; s/risk 3 = 4$/risk 0 = 1/' "$DTMP/plan.md" > "$DTMP/light.md"
brief --header "$DTMP/light.md" "$DTMP/hl.md"
check "a lone total-4 task in three is delegated" "$(tail -n 1 "$DTMP/hl.md")" "**Dispatch:** delegated — Task 2 (total 4)"
sed 's/inline — `claude --model opus --effort high`/subagent — `claude --model sonnet --effort high`/' "$DTMP/plan.md" > "$DTMP/sub.md"
brief "$DTMP/sub.md" 2 "$DTMP/s2.md"
check "a subagent plan has no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/s2.md")" "0"
grep -v '^\*\*Execution:\*\*' "$DTMP/plan.md" > "$DTMP/old.md"
brief "$DTMP/old.md" 2 "$DTMP/o2.md"
check "a plan with no Execution line has no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/o2.md")" "0"
{ printf 'Host: codex\n\n'; cat "$DTMP/plan.md"; } > "$DTMP/cdx.md"
brief "$DTMP/cdx.md" 2 "$DTMP/c2.md"
check "a Codex-host plan has no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/c2.md")" "0"
four_plan() { # four_plan <file> <total ...> — an inline plan, one task per total (1 or 4)
  local f=$1 i=0 t ev; shift
  printf '# Four\n\n**Execution:** inline — `claude --model sonnet --effort high` — x\n' > "$f"
  for t in "$@"; do
    i=$((i + 1))
    if [ "$t" -eq 4 ]; then ev='files 0 - spec 1 - coupling 1 - risk 2 = 4'; else ev='files 0 - spec 0 - coupling 1 - risk 0 = 1'; fi
    printf '\n### Task %s: t\n\n**Evaluation:** %s\n' "$i" "$ev" >> "$f"
  done
}
four_plan "$DTMP/one4.md" 1 4 1 1 1 1
brief "$DTMP/one4.md" 2 "$DTMP/f2.md"
check "a delegated total-4 task's second line is the Dispatch line" "$(sed -n 2p "$DTMP/f2.md")" "**Dispatch:** delegated — total 4, risk 2"
brief "$DTMP/one4.md" 1 "$DTMP/f1.md"
check "a light task beside a delegated total-4 task has no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/f1.md")" "0"
brief --header "$DTMP/one4.md" "$DTMP/fh.md"
check "the header names the total-4 reason" "$(tail -n 1 "$DTMP/fh.md")" "**Dispatch:** delegated — Task 2 (total 4)"
four_plan "$DTMP/three4.md" 4 4 4 1 1 1
brief "$DTMP/three4.md" 1 "$DTMP/t1.md"
check "total-4 tasks past a third get no Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/t1.md")" "0"
brief --header "$DTMP/three4.md" "$DTMP/th.md"
check "total-4 tasks past a third leave no header Dispatch line" "$(grep -c '^\*\*Dispatch:\*\*' "$DTMP/th.md")" "0"
rm -rf "$DTMP"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
