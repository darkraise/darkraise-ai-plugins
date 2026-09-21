#!/usr/bin/env bash
# lib/plan.sh is the one plan parser every script shares, so all of them agree
# on what a task, the header and an amendment are: fences by the CommonMark
# rule, CRLF tolerated.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/lib/plan.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- plan_tasks and ledger_done ---
printf '# Plan\n\n### Task 1: First thing\n\n```bash\n### Task 9: fenced\n```\n\n## Task 2 - Second\n\n### Task 10: Tenth\n' > "$TMP/plan.md"
check "plan_tasks: numbers outside fences" "$(plan_tasks "$TMP/plan.md" | cut -f1 | tr '\n' ' ')" "1 2 10 "
check "plan_tasks: titles" "$(plan_tasks "$TMP/plan.md" | cut -f2 | tr '\n' '|')" "First thing|Second|Tenth|"
sed 's/$/\r/' "$TMP/plan.md" > "$TMP/crlf.md"
check "plan_tasks: CRLF" "$(plan_tasks "$TMP/crlf.md" | cut -f2 | tr '\n' '|')" "First thing|Second|Tenth|"
printf '# Empty\n' > "$TMP/none.md"
check "plan_tasks: no tasks prints nothing" "$(plan_tasks "$TMP/none.md")" ""
printf '# P\n\n### Task 1: One\n\n````markdown\n```bash\necho hi\n```\n### Task 9: inside\n````\n\n~~~\n### Task 8: tilde\n~~~\n\n### Task 2: Two\n' > "$TMP/nested.md"
check "plan_tasks: a 4-backtick fence holds 3-backtick fences" "$(plan_tasks "$TMP/nested.md" | cut -f1 | tr '\n' ' ')" "1 2 "

printf '# SDD ledger — plan: x\nTask 2: complete (a)\nTask 1: fix round 1/5 (x)\nTask 1: complete (b)\nTask 2: complete (again)\nGroup 1-2: review round 1/5\n' > "$TMP/ledger.md"
check "ledger_done: unique and sorted" "$(ledger_done "$TMP/ledger.md" | tr '\n' ' ')" "1 2 "
sed 's/$/\r/' "$TMP/ledger.md" > "$TMP/ledger-crlf.md"
check "ledger_done: CRLF" "$(ledger_done "$TMP/ledger-crlf.md" | tr '\n' ' ')" "1 2 "
printf '# SDD ledger — plan: x\nTask 3: fix round 1/5 (x)\n' > "$TMP/open.md"
check "ledger_done: nothing complete" "$(ledger_done "$TMP/open.md")" ""

# --- ledger_blocked: the Recovery rule, not a flat grep ---
# Both execution skills read the LAST "Task N:" line in file order, stepping
# over minor (deferred), parked and Ruling lines. A BLOCKED a later line
# superseded is not blocked any more, or a resolved task stays blocked forever.
printf '# SDD ledger — plan: x\nTask 2: BLOCKED — ruling seat — what to do\n' > "$TMP/bl-plain.md"
check "ledger_blocked: a terminal BLOCKED" "$(ledger_blocked "$TMP/bl-plain.md" | tr '\n' ' ')" "2 "
printf '# SDD ledger — plan: x\nTask 6: BLOCKED — ruling seat — quota\nTask 6: implementer inline (assigned; base abc1234)\nTask 6: complete (def5678, unreviewed) — done: x\n' > "$TMP/bl-resolved.md"
check "ledger_blocked: a BLOCKED a later complete superseded" "$(ledger_blocked "$TMP/bl-resolved.md")" ""
printf '# SDD ledger — plan: x\nTask 4: BLOCKED — ruling seat — what\nTask 4: implementer inline (assigned; base abc1234)\n' > "$TMP/bl-restarted.md"
check "ledger_blocked: a BLOCKED a later assignment superseded" "$(ledger_blocked "$TMP/bl-restarted.md")" ""
printf '# SDD ledger — plan: x\nTask 3: BLOCKED — ruling seat — what\nTask 3: minor (deferred): a wart\nTask 3: parked — f — Ruling: why\nTask 3: Ruling: a call — why — cost\nRuling: a bare ruling — why — cost\n' > "$TMP/bl-skipped.md"
check "ledger_blocked: non-terminal lines do not clear it" "$(ledger_blocked "$TMP/bl-skipped.md" | tr '\n' ' ')" "3 "
printf '# SDD ledger — plan: x\nTask 10: BLOCKED — a\nTask 2: BLOCKED — b\nTask 10: BLOCKED — c\n' > "$TMP/bl-many.md"
check "ledger_blocked: unique and numerically sorted" "$(ledger_blocked "$TMP/bl-many.md" | tr '\n' ' ')" "2 10 "
sed 's/$/\r/' "$TMP/bl-resolved.md" > "$TMP/bl-crlf.md"
check "ledger_blocked: CRLF" "$(ledger_blocked "$TMP/bl-crlf.md")" ""
check "ledger_blocked: nothing blocked" "$(ledger_blocked "$TMP/open.md")" ""

# --- header, header lines and task text ---
printf '# P\n\n**Spec:** `a.md`\n\n```\n**Execution:** fenced\n```\n**Execution:** subagent — x\n\n## Global Constraints\n\n- c\n\n### Task 1: One\n\nbody 1\n\n### Task 2: Two\n\nbody 2\n' > "$TMP/h.md"
check "plan_header_line: first unfenced match" "$(plan_header_line "$TMP/h.md" Execution)" "**Execution:** subagent — x"
check "plan_header_line: no match prints nothing" "$(plan_header_line "$TMP/h.md" Program)" ""
check "plan_header: stops before the first task" "$(plan_header "$TMP/h.md" | tail -n 2 | head -n 1)" "- c"
check "plan_task_text: heading to the next task" "$(plan_task_text "$TMP/h.md" 1 | tr '\n' '|')" "### Task 1: One||body 1||"
check "plan_task_text: last task runs to the end" "$(plan_task_text "$TMP/h.md" 2 | tr '\n' '|')" "### Task 2: Two||body 2|"
plan_task_text "$TMP/h.md" 7 > /dev/null
check "plan_task_text: absent task exits 3" "$?" "3"
sed 's/$/\r/' "$TMP/h.md" > "$TMP/hc.md"
check "plan_task_text: CRLF" "$(plan_task_text "$TMP/hc.md" 2 | tr '\n' '|')" "### Task 2: Two||body 2|"

# --- plan_apply_amendments ---
cat > "$TMP/am.md" <<'EOF'
## A1 — Task 2
Reason: r
Cost if wrong: c
### Old
````text
body 2
````
### New
````text
body 2 amended
```bash
echo fenced
```
````

## A2 - Header
Reason: r
Cost if wrong: c
### Old
````text
- c
````
### New
````text
````
EOF
out=$(plan_apply_amendments "$TMP/h.md" "$TMP/am.md"); status=$?
check "apply: exit 0" "$status" "0"
check "apply: task target, fenced New kept" "$(printf '%s\n' "$out" | tail -n 4 | tr '\n' '|')" 'body 2 amended|```bash|echo fenced|```|'
check "apply: header target, empty New deletes" "$(printf '%s\n' "$out" | grep -c '^- c$')" "0"
printf '## A1 — Task 1\nReason: r\nCost if wrong: c\n### Old\n````text\nbody 2\n````\n### New\n````text\nx\n````\n' > "$TMP/bad.md"
plan_apply_amendments "$TMP/h.md" "$TMP/bad.md" > /dev/null 2> "$TMP/err"
check "apply: old text outside its target exits 1" "$?" "1"
check "apply: names the entry" "$(cat "$TMP/err")" "amendment A1 does not apply"
printf '# P\n\n### Task 1: One\n\nx\nx\n' > "$TMP/dup.md"
printf '## A1 — Task 1\nReason: r\nCost if wrong: c\n### Old\n````text\nx\n````\n### New\n````text\ny\n````\n' > "$TMP/dup-am.md"
plan_apply_amendments "$TMP/dup.md" "$TMP/dup-am.md" > /dev/null 2>&1
check "apply: old text twice exits 1" "$?" "1"
printf '# P\n\n### Task 1: One\n\n```bash\nold line\nsecond\n```\n' > "$TMP/multi.md"
printf '## A1 — Task 1\nReason: r\nCost if wrong: c\n### Old\n````text\nold line\nsecond\n````\n### New\n````text\nnew line\n````\n' > "$TMP/multi-am.md"
check "apply: multi-line old text inside a fence" "$(plan_apply_amendments "$TMP/multi.md" "$TMP/multi-am.md" | tail -n 2 | tr '\n' '|')" 'new line|```|'
check "apply: missing amendments file prints the plan" \
  "$(plan_apply_amendments "$TMP/h.md" "$TMP/no-such.md" | wc -l | tr -d ' ')" "$(wc -l < "$TMP/h.md" | tr -d ' ')"

# --- plan_amendments_file ---
export GIT_CONFIG_NOSYSTEM=1
REPO="$TMP/repo"
git init -q "$REPO"
cp "$TMP/h.md" "$REPO/plan.md"
check "amendments_file: none yet" "$(plan_amendments_file "$REPO/plan.md")" ""
mkdir -p "$REPO/.superpowers/sdd/plan"
cp "$TMP/am.md" "$REPO/.superpowers/sdd/plan/amendments.md"
got=$(plan_amendments_file "$REPO/plan.md")
check "amendments_file: the plan's workspace file" "${got##*/.superpowers/}" "sdd/plan/amendments.md"
check "amendments_file: outside a repository" "$(plan_amendments_file "$TMP/h.md")" ""

# --- plan_scores and plan_heavy ---
sed 's/^|//' > "$TMP/scores.md" <<'EOF'
|# Scores
|
|### Task 1: light
|
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|```text
|**Evaluation:** files 3 - spec 3 - coupling 3 - risk 3 = 12
|```
|
|### Task 2: total five
|
|**Evaluation:** files 1 — spec 1 — coupling 1 — risk 2 = 5
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
|
|### Task 4: no score
|
|Body.
|
|### Task 5: broken
|
|**Evaluation:** one plus one
EOF
check "plan_scores: highest total and risk per task, fences skipped" \
  "$(plan_scores "$TMP/scores.md" | tr '\t\n' ' |')" "1 1 0|2 5 2|3 4 3|4 - -|5 ? ?|"
check "plan_heavy: total 5 or risk 3 on any part" "$(plan_heavy "$TMP/scores.md" | tr '\n' ' ')" "2 3 "
sed 's/$/\r/' "$TMP/scores.md" > "$TMP/scores-crlf.md"
check "plan_scores: CRLF" "$(plan_scores "$TMP/scores-crlf.md" | tr '\t\n' ' |')" "1 1 0|2 5 2|3 4 3|4 - -|5 ? ?|"

# --- plan_delegated: heavy tasks, and total-4 tasks while a third or fewer ---
deleg_plan() { # deleg_plan <file> <total/risk ...> — one task per argument
  local f=$1 i=0 tr; shift
  printf '# Delegation\n' > "$f"
  for tr in "$@"; do
    i=$((i + 1))
    printf '\n### Task %s: t\n\n**Evaluation:** files 0 - spec 0 - coupling %s - risk %s = %s\n' \
      "$i" "$((${tr%/*} - ${tr#*/}))" "${tr#*/}" "${tr%/*}" >> "$f"
  done
}
deleg() { plan_delegated "$1" | tr '\t\n' ' |'; }
deleg_plan "$TMP/d1.md" 1/0 4/2 1/0 1/0 1/0 1/0
check "plan_delegated: one total-4 task in six" "$(deleg "$TMP/d1.md")" "2 total 4|"
deleg_plan "$TMP/d2.md" 4/2 1/0 4/2 1/0 1/0 1/0
check "plan_delegated: two total-4 tasks in six" "$(deleg "$TMP/d2.md")" "1 total 4|3 total 4|"
deleg_plan "$TMP/d3.md" 4/2 4/2 4/2 1/0 1/0 1/0
check "plan_delegated: three total-4 tasks in six are none" "$(deleg "$TMP/d3.md")" ""
deleg_plan "$TMP/d4.md" 5/2 4/2 1/0 4/3 1/0 1/0
check "plan_delegated: heavy and total-4 tasks together" "$(deleg "$TMP/d4.md")" "1 heavy|2 total 4|4 heavy|"
deleg_plan "$TMP/d5.md" 5/2 4/2 4/2 1/0
check "plan_delegated: heavy tasks stay when total-4 tasks pass a third" "$(deleg "$TMP/d5.md")" "1 heavy|"
sed 's/^|//' > "$TMP/d6.md" <<'EOF'
|# Split
|
|### Task 1: light
|
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 2: split
|
|#### Part A: small
|
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|#### Part B: larger
|
|**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4
|
|### Task 3: unscored
EOF
check "plan_delegated: a split task with a total-4 part" "$(deleg "$TMP/d6.md")" "2 total 4|"
check "plan_delegated: the scores fixture" "$(deleg "$TMP/scores.md")" "2 heavy|3 heavy|"

# --- plan_ledger and ledger_left_inline ---
REPO="$TMP/repo"
git init -q "$REPO"
mkdir -p "$REPO/docs" "$REPO/.superpowers/sdd/demo"
printf '# Demo\n' > "$REPO/docs/demo.md"
L="$REPO/.superpowers/sdd/demo/progress.md"
check "plan_ledger: no ledger prints nothing" "$(plan_ledger "$REPO/docs/demo.md")" ""
printf '# SDD ledger — plan: docs/demo.md\n' > "$L"
check "plan_ledger: a relative identity line names the plan" "$(plan_ledger "$REPO/docs/demo.md")" \
  "$(git -C "$REPO" rev-parse --show-toplevel)/.superpowers/sdd/demo/progress.md"
printf '# SDD ledger — plan: %s/docs/demo.md\n' "$(git -C "$REPO" rev-parse --show-toplevel)" > "$L"
check "plan_ledger: an absolute identity line names the plan" "$(plan_ledger "$REPO/docs/demo.md")" \
  "$(git -C "$REPO" rev-parse --show-toplevel)/.superpowers/sdd/demo/progress.md"
printf '# SDD ledger — plan: docs/other.md\n' > "$L"
check "plan_ledger: another plan's ledger is ignored" "$(plan_ledger "$REPO/docs/demo.md")" ""
printf '# SDD ledger — plan: docs/demo.md\nTask 1: implementer inline (assigned; base a)\nTask 2: escalated inline -> subagent — still failing\n' > "$L"
check "ledger_left_inline: the escalated task" "$(ledger_left_inline "$L")" "2"
printf 'Task 3: implementer inline (assigned; base b)\n' >> "$L"
check "ledger_left_inline: a later inline assignment returns" "$(ledger_left_inline "$L")" ""
printf 'Task 3: minor (deferred): the grammar says Task 4: escalated inline -> subagent — x\n' >> "$L"
check "ledger_left_inline: a quoted marker is not a switch" "$(ledger_left_inline "$L")" ""
printf 'Task 5: escalated inline -> subagent\n' | sed 's/$/\r/' >> "$L"
check "ledger_left_inline: a bare CRLF marker counts" "$(ledger_left_inline "$L")" "5"

# --- plan_executors ---------------------------------------------------------
sed 's/^|//' > "$TMP/exec.md" <<'EOF'
|# Executors Fixture
|
|### Task 1: plain
|
|**Implementer:** dr-superpowers:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|### Task 2: offloaded
|
|**Implementer:** dr-superpowers:impl-sonnet-medium
|**Executor:** codex gpt-5.5 / medium
|**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2
|
|### Task 3: fenced only
|
|**Implementer:** dr-superpowers:impl-sonnet-low
|**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
|
|```markdown
|**Executor:** codex gpt-5.5 / medium
|```
|
|### Task 4: split, executor on part A, heavy part B
|
|#### Part A: cheap
|
|**Implementer:** dr-superpowers:impl-sonnet-medium
|**Executor:** codex gpt-5.5 / medium
|**Evaluation:** files 0 - spec 1 - coupling 1 - risk 0 = 2
|
|#### Part B: risky
|
|**Implementer:** dr-superpowers:impl-opus-high
|**Evaluation:** files 1 - spec 1 - coupling 1 - risk 3 = 6
EOF

check "plan_executors names an offloaded task" \
  "$(plan_executors "$TMP/exec.md" | awk -F'\t' '$1 == 2 { print $2 }')" "codex"
check "plan_executors ignores a fenced Executor line" \
  "$(plan_executors "$TMP/exec.md" | awk -F'\t' '$1 == 3 { print $2 }')" ""
check "plan_executors matches a line in any part" \
  "$(plan_executors "$TMP/exec.md" | awk -F'\t' '$1 == 4 { print $2 }')" "codex"
check "plan_executors emits one row per task" \
  "$(plan_executors "$TMP/exec.md" | wc -l | tr -d ' ')" "2"

# --- plan_delegated gains the executor kind --------------------------------
check "an offloaded task is delegated as executor" \
  "$(plan_delegated "$TMP/exec.md" | awk -F'\t' '$1 == 2 { print $2 }')" "executor"
check "a plain task is not delegated" \
  "$(plan_delegated "$TMP/exec.md" | awk -F'\t' '$1 == 1 { print $2 }')" ""
check "heavy wins over executor on a split task" \
  "$(plan_delegated "$TMP/exec.md" | awk -F'\t' '$1 == 4 { print $2 }')" "heavy"

# --- the four-band threshold counts the original population ----------------
# Six tasks, three at total 4, one of them offloaded. 3 x 3 > 6, so no
# four-band task delegates. If the offloaded one left the numerator, 3 x 2 <= 6
# would newly delegate the other two - tasks nobody marked for offload.
{ printf '# Threshold Fixture\n\n'
  for i in 1 2 3; do
    printf '### Task %s: four band\n\n**Implementer:** dr-superpowers:impl-opus-low\n' "$i"
    [ "$i" = 1 ] && printf '**Executor:** codex gpt-5.6-sol / high\n'
    printf '**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4\n\n'
  done
  for i in 4 5 6; do
    printf '### Task %s: small\n\n**Implementer:** dr-superpowers:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\n' "$i"
  done
} > "$TMP/threshold.md"

check "the offloaded four-band task delegates as executor" \
  "$(plan_delegated "$TMP/threshold.md" | awk -F'\t' '$1 == 1 { print $2 }')" "executor"
check "the other four-band tasks stay in session" \
  "$(plan_delegated "$TMP/threshold.md" | awk -F'\t' '$1 == 2 || $1 == 3 { print $2 }' | tr '\n' ',')" ""
check "the delegated set is the offloaded task alone" \
  "$(plan_delegated "$TMP/threshold.md" | wc -l | tr -d ' ')" "1"

# --- absence is not failure -------------------------------------------------
# threshold.md's last task carries no Executor line, which is the case that
# leaks a non-zero status out of the loop. The second assertion is the one that
# matters: it calls plan_delegated directly under errexit, the caller shape that
# would silently emit no rows.
check "plan_executors exits 0 when the final task has no Executor line" \
  "$(plan_executors "$TMP/threshold.md" >/dev/null; echo $?)" "0"
check "plan_delegated emits its rows under set -euo pipefail" \
  "$(bash -c 'set -euo pipefail; . "$1"; plan_delegated "$2" | wc -l | tr -d " "' _ "$HERE/../scripts/lib/plan.sh" "$TMP/threshold.md")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
