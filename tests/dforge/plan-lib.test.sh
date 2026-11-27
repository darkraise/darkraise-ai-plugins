#!/usr/bin/env bash
# lib/plan.sh is the one plan parser every script shares, so all of them agree
# on what a task, the header and an amendment are: fences by the CommonMark
# rule, CRLF tolerated.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../plugins/dforge/scripts/lib/plan.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

printf '# Plan\n### Task 10x: Invalid\n### Task 11: Valid\n' > "$TMP/invalid-number.md"
check "plan_tasks: numeric prefix is not a task number" "$(plan_tasks "$TMP/invalid-number.md" | cut -f1)" "11"

# --- plan_tasks and ledger_done ---
printf '# Plan\n\n### Task 1: First thing\n\n```bash\n### Task 9: fenced\n```\n\n## Task 2 - Second\n\n### Task 10: Tenth\n' > "$TMP/plan.md"
check "plan_tasks: numbers outside fences" "$(plan_tasks "$TMP/plan.md" | cut -f1 | tr '\n' ' ')" "1 2 10 "
check "plan_tasks: titles" "$(plan_tasks "$TMP/plan.md" | cut -f2 | tr '\n' '|')" "First thing|Second|Tenth|"
sed 's/$/\r/' "$TMP/plan.md" > "$TMP/crlf.md"
check "plan_tasks: CRLF" "$(plan_tasks "$TMP/crlf.md" | cut -f2 | tr '\n' '|')" "First thing|Second|Tenth|"
printf '# P\n\n### Task 1: One\n\n### Task 10x: not a task\n\n### Task 2\n' > "$TMP/suffix.md"
check "plan_tasks: a number with a letter after it is no task" "$(plan_tasks "$TMP/suffix.md" | cut -f1 | tr '\n' ' ')" "1 2 "
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
# over minor (deferred), parked, Ruling and waiting lines. A BLOCKED a later line
# superseded is not blocked any more, or a resolved task stays blocked forever.
printf '# SDD ledger — plan: x\nTask 2: BLOCKED — ruling seat — what to do\n' > "$TMP/bl-plain.md"
check "ledger_blocked: a terminal BLOCKED" "$(ledger_blocked "$TMP/bl-plain.md" | tr '\n' ' ')" "2 "
printf '# SDD ledger — plan: x\nTask 6: BLOCKED — ruling seat — quota\nTask 6: implementer inline (assigned; base abc1234)\nTask 6: complete (def5678, unreviewed) — done: x\n' > "$TMP/bl-resolved.md"
check "ledger_blocked: a BLOCKED a later complete superseded" "$(ledger_blocked "$TMP/bl-resolved.md")" ""
printf '# SDD ledger — plan: x\nTask 4: BLOCKED — ruling seat — what\nTask 4: implementer inline (assigned; base abc1234)\n' > "$TMP/bl-restarted.md"
check "ledger_blocked: a BLOCKED a later assignment superseded" "$(ledger_blocked "$TMP/bl-restarted.md")" ""
printf '# SDD ledger — plan: x\nTask 3: BLOCKED — ruling seat — what\nTask 3: minor (deferred): a wart\nTask 3: parked — f — Ruling: why\nTask 3: Ruling: a call — why — cost\nRuling: a bare ruling — why — cost\nTask 3: waiting — which way?\n' > "$TMP/bl-skipped.md"
check "ledger_blocked: non-terminal lines do not clear it" "$(ledger_blocked "$TMP/bl-skipped.md" | tr '\n' ' ')" "3 "
for dash in '—' '–' '-'; do
  printf '# SDD ledger — plan: x\nTask 3: BLOCKED — ruling seat — what\nTask 3: waiting %s which way?\n' "$dash" > "$TMP/bl-dash.md"
  check "ledger_blocked: a waiting line with '$dash' does not clear it" "$(ledger_blocked "$TMP/bl-dash.md" | tr '\n' ' ')" "3 "
done
printf '# SDD ledger — plan: x\nTask 10: BLOCKED — a\nTask 2: BLOCKED — b\nTask 10: BLOCKED — c\n' > "$TMP/bl-many.md"
check "ledger_blocked: unique and numerically sorted" "$(ledger_blocked "$TMP/bl-many.md" | tr '\n' ' ')" "2 10 "
sed 's/$/\r/' "$TMP/bl-resolved.md" > "$TMP/bl-crlf.md"
check "ledger_blocked: CRLF" "$(ledger_blocked "$TMP/bl-crlf.md")" ""
check "ledger_blocked: nothing blocked" "$(ledger_blocked "$TMP/open.md")" ""

# --- header, header lines and task text ---
printf '# P\n\n**Spec:** `a.md`\n\n```\n**Execution:** fenced\n```\n**Execution:** inline — x\n\n## Global Constraints\n\n- c\n\n### Task 1: One\n\nbody 1\n\n### Task 2: Two\n\nbody 2\n' > "$TMP/h.md"
check "plan_header_line: first unfenced match" "$(plan_header_line "$TMP/h.md" Execution)" "**Execution:** inline — x"
check "plan_header_line: no match prints nothing" "$(plan_header_line "$TMP/h.md" Program)" ""
check "plan_header: stops before the first task" "$(plan_header "$TMP/h.md" | tail -n 2 | head -n 1)" "- c"
check "plan_is_codex: an unfenced Host line" "$(plan_is_codex $'# P\n\n**Host:** codex\n' && echo yes || echo no)" "yes"
check "plan_is_codex: a fenced Host line is an example" "$(plan_is_codex $'# P\n\n```markdown\n**Host:** codex\n```\n' && echo yes || echo no)" "no"
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
plan_apply_amendments "$TMP/no-such-plan.md" "" > /dev/null 2>&1; status=$?
check "apply: an unreadable plan with no amendments fails" "$([ "$status" -ne 0 ] && echo nonzero || echo zero)" "nonzero"
printf '## A1 — Task 2\nReason: r\nCost if wrong: c\n### Old\n````text\nbody 2\n````\n' > "$TMP/no-new.md"
out=$(plan_apply_amendments "$TMP/h.md" "$TMP/no-new.md" 2> "$TMP/err"); status=$?
check "apply: an entry with no New block fails" "$status:$out:$(cat "$TMP/err")" \
  "1::amendment A1 is not complete: it needs a closed Old and a closed New block"
printf '## A1 — Task 2\nReason: r\nCost if wrong: c\n### Old\n````text\nbody 2\n````\n### New\n````text\nbody 2 amended\n' > "$TMP/open-new.md"
out=$(plan_apply_amendments "$TMP/h.md" "$TMP/open-new.md" 2> "$TMP/err"); status=$?
check "apply: an unclosed New fence fails" "$status:$out:$(cat "$TMP/err")" \
  "1::amendment A1 is not complete: it needs a closed Old and a closed New block"

# --- plan_amendments_file ---
export GIT_CONFIG_NOSYSTEM=1
REPO="$TMP/repo"
git init -q "$REPO"
cp "$TMP/h.md" "$REPO/plan.md"
check "amendments_file: none yet" "$(plan_amendments_file "$REPO/plan.md")" ""
mkdir -p "$REPO/.dforge/sdd/plan"
cp "$TMP/am.md" "$REPO/.dforge/sdd/plan/amendments.md"
got=$(plan_amendments_file "$REPO/plan.md")
check "amendments_file: the plan's workspace file" "${got##*/.dforge/}" "sdd/plan/amendments.md"
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

# --- plan_ledger and ledger_left_inline ---
REPO="$TMP/repo"
git init -q "$REPO"
mkdir -p "$REPO/docs" "$REPO/.dforge/sdd/demo"
printf '# Demo\n' > "$REPO/docs/demo.md"
L="$REPO/.dforge/sdd/demo/progress.md"
check "plan_ledger: no ledger prints nothing" "$(plan_ledger "$REPO/docs/demo.md")" ""
printf '# SDD ledger — plan: docs/demo.md\n' > "$L"
check "plan_ledger: a relative identity line names the plan" "$(plan_ledger "$REPO/docs/demo.md")" \
  "$(git -C "$REPO" rev-parse --show-toplevel)/.dforge/sdd/demo/progress.md"
printf '# SDD ledger — plan: %s/docs/demo.md\n' "$(git -C "$REPO" rev-parse --show-toplevel)" > "$L"
check "plan_ledger: an absolute identity line names the plan" "$(plan_ledger "$REPO/docs/demo.md")" \
  "$(git -C "$REPO" rev-parse --show-toplevel)/.dforge/sdd/demo/progress.md"
printf '# SDD ledger — plan: docs/other.md\n' > "$L"
check "plan_ledger: another plan's ledger is ignored" "$(plan_ledger "$REPO/docs/demo.md")" ""

# --- the shared Evaluation reader ---
# Two shipped defects motivate these. A line left above `#### Part A` scores the
# task as it was before the split, which is the score that forced the split. And
# a plan that shows an example line inside a fence is documenting the format.
printf '# P\n\n### Task 1: Split\n\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 1 = 6\n\n#### Part A: a\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n#### Part B: b\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n' > "$TMP/split.md"
check "plan_eval_lines: a stale parent line does not score a split task" \
  "$(plan_task_text "$TMP/split.md" 1 | plan_eval_lines | grep -c .)" "2"
check "plan_scores: a split task scores from its parts" \
  "$(plan_scores "$TMP/split.md" | tr '\t\n' ' |')" "1 2 0|"
check "plan_heavy: a split task is not heavy on its stale parent score" \
  "$(plan_heavy "$TMP/split.md")" ""

printf '# P\n\n### Task 1: Fenced\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 3 = 6\n```\n' > "$TMP/fenced.md"
check "plan_eval_lines: a fenced example does not score" \
  "$(plan_task_text "$TMP/fenced.md" 1 | plan_eval_lines | grep -c .)" "1"
check "plan_scores: a fenced example does not score" \
  "$(plan_scores "$TMP/fenced.md" | tr '\t\n' ' |')" "1 2 0|"

printf '# P\n\n### Task 1: Fenced part\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n```markdown\n#### Part A: example\n\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 3 = 6\n```\n' > "$TMP/fencedpart.md"
check "plan_task_parts: a fenced part heading is not a part" \
  "$(plan_task_text "$TMP/fencedpart.md" 1 | plan_task_parts)" ""
check "plan_scores: a fenced part heading does not suppress the real line" \
  "$(plan_scores "$TMP/fencedpart.md" | tr '\t\n' ' |')" "1 2 0|"

check "plan_task_parts: real parts, in order" \
  "$(plan_task_text "$TMP/split.md" 1 | plan_task_parts | tr '\n' ' ')" "A B "
check "plan_part_text: one part's text only" \
  "$(plan_task_text "$TMP/split.md" 1 | plan_part_text B | grep -c '^\*\*Evaluation')" "1"
check "plan_part_text: an absent part is empty" \
  "$(plan_task_text "$TMP/split.md" 1 | plan_part_text Z)" ""

printf '# P\n\n### Task 1: Executor\n\n**Executor:** codex gpt-6.1-sol / medium\n\n```markdown\n**Executor:** codex gpt-6.1-sol / high\n```\n' > "$TMP/exec.md"
check "plan_lines: a fenced label line is not a line" \
  "$(plan_task_text "$TMP/exec.md" 1 | plan_lines Executor | grep -c .)" "1"

# A split task routes on its parts. With the stale parent line Task 1 would be
# heavy; its parts top out at 4, so it is not.
printf '# P\n\n### Task 1: One\n\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 0 = 5\n\n#### Part A: a\n\n**Evaluation:** files 1 - spec 1 - coupling 2 - risk 0 = 4\n\n#### Part B: b\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n\n### Task 2: Two\n\n**Evaluation:** files 1 - spec 1 - coupling 2 - risk 0 = 4\n\n### Task 3: Three\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n' > "$TMP/fourband.md"
check "plan_heavy: the corrected score leaves the split task light" \
  "$(plan_heavy "$TMP/fourband.md" | tr '\n' ' ')" ""

printf '# P\n\n### Task 1: One\n\n**Evaluation:** files 2 - spec 1 - coupling 2 - risk 0 = 5\n\n### Task 2: Two\n\n**Evaluation:** files 1 - spec 1 - coupling 2 - risk 0 = 4\n\n### Task 3: Three\n\n**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2\n' > "$TMP/unsplit.md"
check "plan_heavy: an unsplit plan is unchanged by the fix" \
  "$(plan_heavy "$TMP/unsplit.md" | tr '\n' ' ')" "1 "

# --- lettered task headings ---
# plan_tasks reads numbered headings only; plan_lettered names the ones it
# skips, so a caller can say why a plan has no tasks.
printf '# P\n\n### Task A1: One\n\n```markdown\n### Task B2: example\n```\n\n### Task 3: Three\n' > "$TMP/lettered.md"
check "plan_lettered: an unfenced lettered heading only" \
  "$(plan_lettered "$TMP/lettered.md")" "### Task A1: One"
check "plan_lettered: a numbered plan has none" "$(plan_lettered "$TMP/split.md")" ""

# --- the plan functions follow the roots ---
. "$HERE/fixtures/darkmem-stores.sh"
SH="$TMP/stores-home"; mkdir -p "$SH"
SR="$TMP/stores-repo"
git init -q "$SR"
git -C "$SR" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
STOP=$(git -C "$SR" rev-parse --show-toplevel)
M=$(stores_home "$SH" "$SR" proj darkmem darkmem)
# --- amendments live beside the ledger (C7) ---
mkdir -p "$SR/docs" && printf '# P\n\n### Task 1: One\n' > "$SR/docs/am.md"
LD="$M/work/sdd/am"; WSD="$SR/.dforge/sdd/am"
mkdir -p "$LD" "$WSD"
printf '# SDD ledger — plan: docs/am.md\nTask 1: Ruling: amendment A1 — x — y\n' > "$LD/progress.md"
printf '## A1 — Task 1\n' > "$WSD/amendments.md"
(cd "$SR" && HOME=$SH plan_amendments_ready docs/am.md); rc=$?
check "ready: migrates the workspace file" "$rc:$([ -s "$LD/amendments.md" ] && echo moved):$([ -e "$WSD/amendments.md" ] && echo left || echo gone)" "0:moved:gone"
check "ready: logs the move once" "$(grep -c '^Ruling: amendments moved beside the ledger — none$' "$LD/progress.md")" "1"
check "file: the ledger directory's copy" "$(cd "$SR" && HOME=$SH plan_amendments_file docs/am.md)" "$LD/amendments.md"
printf 'Task 1: Ruling: amendment A2 — x — y\n' >> "$LD/progress.md"
err=$(cd "$SR" && HOME=$SH plan_amendments_ready docs/am.md 2>&1); rc=$?
check "ready: a cited amendment missing from the file exits 2" "$rc" "2"
check "ready: the message names it" "$(grep -c 'cites amendment A2, which .*amendments.md lacks' <<<"$err")" "1"
{ printf '## A1 — Task 1\n\n## A2 — Task 1\n'; for ((i = 0; i < 4000; i++)); do printf 'filler %04d that takes the amendments past one pipe buffer\n' "$i"; done; } > "$LD/amendments.md"
(cd "$SR" && HOME=$SH plan_amendments_ready docs/am.md); rc=$?
check "ready: finds a cited amendment in a file past 64 KiB" "$rc" "0"
# Another reader moves the file and plan-amend publishes A2 while this one
# copies: the cp stand-in writes that state the moment its copy is made.
printf '# P\n\n### Task 1: One\n' > "$SR/docs/am2.md"
mkdir -p "$SR/.dforge/sdd/am2" "$TMP/cpshim"
printf '## A1 — Task 1\n' > "$SR/.dforge/sdd/am2/amendments.md"
export REAL_CP RACE_FILE="$M/work/sdd/am2/amendments.md"
REAL_CP=$(command -v cp)
printf '#!/usr/bin/env bash\n"$REAL_CP" "$@" || exit\nprintf '"'"'## A1 — Task 1\\n\\n## A2 — Task 1\\n'"'"' > "$RACE_FILE"\n' > "$TMP/cpshim/cp"
chmod +x "$TMP/cpshim/cp"
(cd "$SR" && HOME=$SH PATH="$TMP/cpshim:$PATH" plan_amendments_ready docs/am2.md); rc=$?
check "ready: a migration never replaces amendments published meanwhile" \
  "$rc:$(grep -c '^## A2 ' "$RACE_FILE" 2>/dev/null)" "0:1"
mkdir -p "$M/dforge/plans" "$M/work/sdd/mp"
printf '# MP\n' > "$M/dforge/plans/mp.md"
printf '# SDD ledger — plan: docs/dforge/plans/mp.md\n' > "$M/work/sdd/mp/progress.md"
check "plan_ledger: a mirror plan finds its mirror ledger by name" \
  "$(cd "$SR" && HOME=$SH plan_ledger "$M/dforge/plans/mp.md")" "$M/work/sdd/mp/progress.md"
printf '# SDD ledger — plan: %s\n' "$M/dforge/plans/mp.md" > "$M/work/sdd/mp/progress.md"
check "plan_ledger: an absolute mirror path names it too" \
  "$(cd "$SR" && HOME=$SH plan_ledger "$M/dforge/plans/mp.md")" "$M/work/sdd/mp/progress.md"
printf '# SDD ledger — plan: docs/superpowers/plans/mp.md\n' > "$M/work/sdd/mp/progress.md"
check "plan_ledger: the pre-2.0 prefix names a mirror plan" \
  "$(cd "$SR" && HOME=$SH plan_ledger "$M/dforge/plans/mp.md")" "$M/work/sdd/mp/progress.md"
check "plan_locate: a document name finds the mirror's copy" \
  "$(cd "$SR" && HOME=$SH plan_locate docs/dforge/plans/mp.md)" "$M/dforge/plans/mp.md"
mkdir -p "$SR/docs/dforge/plans"
printf '# Stale checkout copy\n' > "$SR/docs/dforge/plans/mp.md"
check "plan_locate: applied mirror wins over leftover checkout" \
  "$(cd "$SR" && HOME=$SH plan_locate docs/dforge/plans/mp.md)" "$M/dforge/plans/mp.md"
check "plan_locate: absolute checkout path follows applied mirror" \
  "$(cd "$SR" && HOME=$SH plan_locate "$SR/docs/dforge/plans/mp.md")" "$M/dforge/plans/mp.md"
check "plan_locate: an absolute plan outside cwd keeps its store context" \
  "$(cd "$TMP" && HOME=$SH plan_locate "$SR/docs/dforge/plans/mp.md")" "$M/dforge/plans/mp.md"
mv "$M/dforge/plans/mp.md" "$M/dforge/plans/mp.saved"
check "plan_locate: missing mirror does not revive stale checkout" \
  "$(cd "$SR" && HOME=$SH plan_locate docs/dforge/plans/mp.md)" "$M/dforge/plans/mp.md"
mv "$M/dforge/plans/mp.saved" "$M/dforge/plans/mp.md"
rm "$SR/docs/dforge/plans/mp.md"
check "plan_locate: an existing file stays" "$(cd "$REPO" && plan_locate docs/demo.md)" "docs/demo.md"
check "plan_locate: a missing name stays" "$(cd "$SR" && HOME=$SH plan_locate docs/dforge/plans/none.md)" "docs/dforge/plans/none.md"
mkdir -p "$M/work/sdd/mp"
printf '## A1 — Task 1\n' > "$M/work/sdd/mp/amendments.md"
check "amendments_file: a mirror plan's amendments sit beside its mirror ledger" \
  "$(cd "$SR" && HOME=$SH plan_amendments_file "$M/dforge/plans/mp.md")" "$M/work/sdd/mp/amendments.md"
(cd "$SR" && HOME=$SH plan_require_same_project "$M/dforge/plans/mp.md" 2>/dev/null)
check "same project: a mirror plan while documents are in darkmem" "$?" "0"
(cd "$SR" && HOME=$SH plan_require_same_project "$REPO/docs/demo.md" 2>/dev/null)
check "same project: another checkout's plan is refused" "$?" "2"
M=$(stores_home "$SH" "$SR" proj local darkmem)
mkdir -p "$STOP/docs/dforge/plans"
printf '# LP\n' > "$STOP/docs/dforge/plans/lp.md"
mkdir -p "$M/work/sdd/lp"
printf '# SDD ledger — plan: docs/dforge/plans/lp.md\n' > "$M/work/sdd/lp/progress.md"
check "plan_ledger: a checkout plan finds its mirror ledger" \
  "$(cd "$SR" && HOME=$SH plan_ledger "$STOP/docs/dforge/plans/lp.md")" "$M/work/sdd/lp/progress.md"
printf '# SDD ledger — plan: docs/superpowers/plans/lp.md\n' > "$M/work/sdd/lp/progress.md"
check "plan_ledger: the pre-2.0 prefix names a checkout plan" \
  "$(cd "$SR" && HOME=$SH plan_ledger "$STOP/docs/dforge/plans/lp.md")" "$M/work/sdd/lp/progress.md"
(cd "$SR" && HOME=$SH plan_require_same_project "$M/dforge/plans/mp.md" 2>/dev/null)
check "same project: a mirror plan while documents are local is refused" "$?" "2"

# --- a home that is a git repository: a mirror plan still belongs to the
# working directory's checkout, and a ConfigError stops plan_ledger ---
GH="$TMP/git-home"
git init -q "$GH"
GM=$(stores_home "$GH" "$SR" proj darkmem darkmem)
mkdir -p "$GM/dforge/plans" "$GM/work/sdd/gp"
printf '# GP\n' > "$GM/dforge/plans/gp.md"
printf '# SDD ledger — plan: docs/dforge/plans/gp.md\n' > "$GM/work/sdd/gp/progress.md"
check "plan_ledger: a mirror plan in a home under git finds its ledger" \
  "$(cd "$SR" && HOME=$GH plan_ledger "$GM/dforge/plans/gp.md")" "$GM/work/sdd/gp/progress.md"
printf '{not json\n' > "$GH/.dforge/config.json"
(cd "$SR" && HOME=$GH plan_ledger "$GM/dforge/plans/gp.md" > /dev/null 2> "$TMP/ledger-err")
check "plan_ledger: a ConfigError exits 2" "$?" "2"
check "plan_ledger: the ConfigError is named once" "$(grep -c 'not valid JSON' "$TMP/ledger-err")" "1"

# --- plan_primary_root ---
gq() { git -c user.name=t -c user.email=t@example.com -c init.defaultBranch=main "$@"; }
gq init -q "$TMP/std" && gq -C "$TMP/std" commit -q --allow-empty -m one
gq -C "$TMP/std" worktree add -q "$TMP/std-wt" 2>/dev/null
check "plan_primary_root: a linked worktree names its primary" \
  "$(plan_primary_root "$TMP/std-wt")" "$(git -C "$TMP/std" rev-parse --show-toplevel)"
mkdir -p "$TMP/meta" && gq init -q --separate-git-dir="$TMP/meta/r.git" "$TMP/sep"
out=$(plan_primary_root "$TMP/sep"); status=$?
check "plan_primary_root: a separate git directory is its own primary" \
  "$status:$out" "0:$(git -C "$TMP/sep" rev-parse --show-toplevel)"
gq init -q "$TMP/subsrc" && gq -C "$TMP/subsrc" commit -q --allow-empty -m one
gq init -q "$TMP/sup" && gq -C "$TMP/sup" commit -q --allow-empty -m one
gq -C "$TMP/sup" -c protocol.file.allow=always submodule add -q "$TMP/subsrc" sub >/dev/null 2>&1
out=$(plan_primary_root "$TMP/sup/sub"); status=$?
check "plan_primary_root: a submodule is its own primary" \
  "$status:$out" "0:$(git -C "$TMP/sup/sub" rev-parse --show-toplevel)"

# --- plan_task_paths ---
check "plan_task_paths: a comma line range is dropped" \
  "$(printf '%s\n' '- Modify: `src/view.tsx:10-20,30-40`' | plan_task_paths)" "src/view.tsx"

# --- plan_final_review_state: a merge's own conflict resolution ---
FR="$TMP/fr"
gq init -q "$FR" && printf 'old\n' > "$FR/a.sh" && printf 'b\n' > "$FR/b.sh"
gq -C "$FR" add a.sh b.sh && gq -C "$FR" commit -q -m base
frbase=$(git -C "$FR" rev-parse --short HEAD)
gq -C "$FR" checkout -q -b feat && printf 'feat\n' > "$FR/a.sh" && gq -C "$FR" commit -q -am feat
frhead=$(git -C "$FR" rev-parse --short HEAD)
gq -C "$FR" checkout -q main && printf 'main\n' > "$FR/a.sh" && gq -C "$FR" commit -q -am main
gq -C "$FR" merge -q feat >/dev/null 2>&1
printf 'new code\n' > "$FR/a.sh" && gq -C "$FR" commit -q -am "merge feat"
printf 'Final review: clean (commits %s..%s)\n' "$frbase" "$frhead" > "$TMP/fr-ledger.md"
check "final review: a merge's own conflict resolution reads stale" \
  "$(HOME="$TMP/fr-home" plan_final_review_state "$TMP/fr-ledger.md" "$FR")" "stale $(git -C "$FR" rev-parse --short HEAD^1)"
gq -C "$FR" checkout -q -b feat2 HEAD && printf 'b2\n' > "$FR/b.sh" && gq -C "$FR" commit -q -am feat2
fr2=$(git -C "$FR" rev-parse --short HEAD)
gq -C "$FR" checkout -q main && printf 'c\n' > "$FR/c.sh" && gq -C "$FR" add c.sh && gq -C "$FR" commit -q -m c
gq -C "$FR" merge -q --no-edit feat2 >/dev/null 2>&1
printf 'Final review: clean (commits %s..%s)\n' "$frbase" "$fr2" > "$TMP/fr-ledger.md"
check "final review: a clean merge of the reviewed head stays current" \
  "$(HOME="$TMP/fr-home" plan_final_review_state "$TMP/fr-ledger.md" "$FR")" "current"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
