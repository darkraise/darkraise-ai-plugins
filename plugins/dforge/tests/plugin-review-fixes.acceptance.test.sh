#!/usr/bin/env bash
# Acceptance checks for docs/dforge/specs/2026-11-15-plugin-review-fixes-design.md
# (the script, document and hook statements; the darkmem sync statement is in
# darkmem-sync/plugin-review-fixes.acceptance.test.mjs and the cockpit
# statements are in plugin-review-fixes.acceptance.test.ts). Each check name
# starts with the statement it answers.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$(cd "$HERE/.." && pwd)"
S="$P/scripts"
TMP="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.claude"
export LC_ALL=C MSYS_NO_PATHCONV=1 DFORGE_NO_SETTINGS=1 GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset DFORGE_BUDGET DFORGE_JQ DFORGE_FLOCK CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR DFORGE_SESSION_ID

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
  if grep -qF -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}
run() { out=$("$@" 2>"$TMP/err"); rc=$?; err=$(cat "$TMP/err"); }

# A plan fixture shared by the task-brief, task-close and amendment checks.
mkrepo() { # mkrepo <dir>: a git checkout with docs/plan.md (two tasks) committed
  git init -q "$1" && git -C "$1" config user.name t && git -C "$1" config user.email t@example.invalid
  mkdir -p "$1/docs"
  {
    printf '# Widget Implementation Plan\n\n**Goal:** Widget.\n\n'
    printf '**Execution:** inline — `claude --model opus --effort high` — fixture\n\n'
    printf '**Task check:** `bash t.sh` — fast\n**Integration check:** `bash all.sh`\n\n'
    printf '## Global Constraints\n\n- Bash only.\n\n## Contracts\n\n- None.\n\n'
    printf '### Task 1: first\n\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\nPrint hello.\n\n'
    printf '### Task 2: second\n\n**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0\n\nPrint bye.\n'
  } > "$1/docs/plan.md"
  printf '.dforge/\n' > "$1/.gitignore"
  git -C "$1" add -A && git -C "$1" commit -qm base
}
CP='done: x; verified: y; remaining: none; discovered: none; assumptions: none'

# --- A1, A2: the QA timeout cleanup (scripts/qa-files) ---
R1="$TMP/qa"
mkrepo "$R1"
printf 'one\n' > "$R1/human.txt"; printf 'one\n' > "$R1/qa-edit.txt"
git -C "$R1" add human.txt qa-edit.txt && git -C "$R1" commit -qm files
WS1="$R1/.dforge/sdd/plan"
mkdir -p "$WS1"
(cd "$R1" && bash "$S/qa-files" begin "$WS1")
printf 'tests/new.acceptance.sh\nqa-edit.txt\n' > "$WS1/qa-touched.txt"
mkdir -p "$R1/tests" && printf 'x\n' > "$R1/tests/new.acceptance.sh"
printf 'qa change\n' >> "$R1/qa-edit.txt"
printf 'human change\n' >> "$R1/human.txt"
run bash -c "cd '$R1' && bash '$S/qa-files' clean '$WS1'"
check "A1: clean exits 0" "$rc" "0"
check "A1: a file the human edited and QA did not list keeps its content" "$(cat "$R1/human.txt")" $'one\nhuman change'
has "A1: the human's file is named in the output" "$out" "human.txt"
check "A1: QA's listed new file is deleted" "$([ -e "$R1/tests/new.acceptance.sh" ] && echo kept || echo gone)" "gone"
check "A1: QA's listed edit is restored" "$(cat "$R1/qa-edit.txt")" "one"

# A2: no manifest, nothing touched; a begin after earlier entries starts empty.
rm -f "$WS1/qa-touched.txt"
printf 'x\n' > "$R1/orphan.txt"; printf 'edit\n' >> "$R1/qa-edit.txt"
(cd "$R1" && bash "$S/qa-files" clean "$WS1" >/dev/null 2>&1)
check "A2: without a manifest a new file stays" "$(cat "$R1/orphan.txt")" "x"
check "A2: without a manifest an edit stays" "$(cat "$R1/qa-edit.txt")" $'one\nedit'
(cd "$R1" && git checkout -q qa-edit.txt && rm -f orphan.txt)
(cd "$R1" && bash "$S/qa-files" begin "$WS1")
printf 'qa-edit.txt\n' > "$WS1/qa-touched.txt"
(cd "$R1" && bash "$S/qa-files" begin "$WS1")
check "A2: a re-dispatch's begin does not inherit earlier entries" "$(wc -c < "$WS1/qa-touched.txt" | tr -d ' ')" "0"
printf 'mine\n' >> "$R1/qa-edit.txt"
(cd "$R1" && bash "$S/qa-files" clean "$WS1" >/dev/null 2>&1)
check "A2: a path from an earlier run, not relisted, is not restored" "$(cat "$R1/qa-edit.txt")" $'one\nmine'
(cd "$R1" && git checkout -q qa-edit.txt)

# --- A4, A56, A34, A6: amendments, plan identity and Codex plans ---
R2="$TMP/am"
mkrepo "$R2"
cd "$R2" || exit 1
bash "$S/task-brief" --open docs/plan.md 1 >/dev/null 2>&1
LEDGER="$R2/.dforge/sdd/plan/progress.md"
printf 'Task 1: Ruling: amendment A3 — x — y\n' >> "$LEDGER"
run bash "$S/task-brief" docs/plan.md 1
check "A4: task-brief exits 2 when the ledger cites A3 and amendments.md lacks it" "$rc" "2"
has "A4: the message names A3" "$err" "A3"
sed -i '/amendment A3/d' "$LEDGER"

# A56: a plan amended before the upgrade keeps amendments.md in its workspace
# while progress now lives in the darkmem mirror, beside the ledger.
. "$HERE/fixtures/darkmem-stores.sh"
M=$(stores_home "$HOME" "$R2" proj local darkmem)
mkdir -p "$R2/.dforge/sdd/plan" "$M/work/sdd/plan"
printf '## A1 — Task 1\nReason: r\nCost if wrong: c\n### Old\n````text\nPrint hello.\n````\n### New\n````text\nPrint HELLO LOUDLY.\n````\n' > "$TMP/amend.md"
cp "$TMP/amend.md" "$R2/.dforge/sdd/plan/amendments.md"
printf '# SDD ledger — plan: docs/plan.md\nTask 1: Ruling: amendment A1 — Task 1 — loud\n' > "$M/work/sdd/plan/progress.md"
run bash "$S/task-brief" docs/plan.md 1
check "A56: a plan whose amendments.md is still in its workspace resumes" "$rc" "0"
check "A56: the brief carries the amended text" "$(grep -c 'Print HELLO LOUDLY.' "$R2/.dforge/sdd/plan/task-1-brief.md")" "1"
check "A56: amendments.md now sits beside the ledger" "$([ -s "$M/work/sdd/plan/amendments.md" ] && echo yes || echo no)" "yes"
check "A56: the workspace copy is gone" "$([ -e "$R2/.dforge/sdd/plan/amendments.md" ] && echo kept || echo gone)" "gone"
check "A56: one ruling line logs the move" "$(grep -c '^Ruling: amendments moved beside the ledger — none$' "$M/work/sdd/plan/progress.md")" "1"
run bash "$S/task-brief" docs/plan.md 1
check "A56: a second read logs no second ruling" "$(grep -c '^Ruling: amendments moved' "$M/work/sdd/plan/progress.md")" "1"
rm -f "$HOME/.dforge/config.json" "$HOME/.dforge/stores.json"

# A6: a ledger naming another plan with the same basename; nothing is written.
sed -i '/amendment A1/d' "$LEDGER"
mkdir -p other && cp docs/plan.md other/plan.md
BEFORE=$(cat "$LEDGER")
run bash "$S/task-brief" --open other/plan.md 2
check "A6: task-brief --open exits 2 on a same-basename plan" "$rc" "2"
check "A6: task-brief --open writes no ledger line" "$(cat "$LEDGER")" "$BEFORE"
run bash "$S/task-close" other/plan.md 1 "$CP"
check "A6: task-close exits 2 on a same-basename plan" "$rc" "2"
check "A6: task-close writes no ledger line" "$(cat "$LEDGER")" "$BEFORE"
rm -rf other

# A34: --open on a Host: codex plan.
sed 's/^# Widget Implementation Plan/&\n\n**Host:** codex/' docs/plan.md > docs/codex.md
run bash "$S/task-brief" --open docs/codex.md 1
check "A34: --open on a Host: codex plan exits 0" "$rc" "0"
check "A34: it writes the open line" "$(grep -c '^Task 1: implementer inline (assigned; base ' "$R2/.dforge/sdd/codex/progress.md")" "1"
check "A34: it writes the brief" "$([ -s "$R2/.dforge/sdd/codex/task-1-brief.md" ] && echo yes || echo no)" "yes"
cd "$TMP" || exit 1

# --- A5: ci-mirror reads the amended CI line of a plan the darkmem mirror holds ---
R5="$TMP/ci"
mkrepo "$R5"
. "$HERE/fixtures/darkmem-stores.sh"
M5=$(stores_home "$HOME" "$R5" proj darkmem local)
OLDCI='**CI:** `.github/workflows/v.yml` — platforms: ubuntu-latest — local: `echo original-ci` — uncovered: none'
mkdir -p "$M5/dforge/plans"
{
  printf '# Mirror Plan\n\n**Spec:** `s.md`\n\n%s\n\n## Global Constraints\n\n- c\n\n## Contracts\n\n- c\n\n### Task 1: One\n\nbody\n' "$OLDCI"
} > "$M5/dforge/plans/mp.md"
mkdir -p "$R5/.dforge/sdd/mp"
{
  printf '## A1 — Header\nReason: r\nCost if wrong: c\n### Old\n````text\n%s\n````\n### New\n````text\n' "$OLDCI"
  printf '**CI:** `.github/workflows/v.yml` — platforms: ubuntu-latest — local: `echo amended-ci` — uncovered: none\n````\n'
} > "$R5/.dforge/sdd/mp/amendments.md"
run bash -c "cd '$R5' && bash '$S/ci-mirror' docs/dforge/plans/mp.md"
check "A5: ci-mirror finds a plan stored in the darkmem docs mirror, by its docs name" "$rc" "0"
has "A5: it runs the amended CI command" "$out" "ci: echo amended-ci"
lacks "A5: it does not run the unamended command" "$out" "original-ci"
rm -f "$HOME/.dforge/config.json" "$HOME/.dforge/stores.json"

# --- A7, A9, A10: routing after a clean final review, Keep as-is, finish record ---
R7="$TMP/route"
mkrepo "$R7"
git -C "$R7" checkout -q -b feature
mkdir -p "$R7/.dforge/sdd/plan"
LEDGER7="$R7/.dforge/sdd/plan/progress.md"
write_ledger() { # write_ledger <final review line>
  printf '# SDD ledger — plan: docs/plan.md\nTask 1: complete (commits a..b, review clean)\nTask 2: complete (commits b..c, review clean)\n%s\n' "$1" > "$LEDGER7"
}
ns() { out=$(cd "$R7" && bash "$S/next-step" "$@" 2>"$TMP/err"); rc=$?; err=$(cat "$TMP/err"); }
H=$(git -C "$R7" rev-parse --short HEAD)
write_ledger "Final review: clean (commits 1234567..$H)"
ns docs/plan.md
has "A7: a clean review of the current head routes to finishing" "$out" "**Next:** Run dforge:finishing-a-development-branch."
mkdir -p "$R7/docs/dforge/plans" && printf 'note\n' > "$R7/docs/dforge/plans/completed.md"
git -C "$R7" add docs/dforge/plans/completed.md && git -C "$R7" commit -qm "docs: index"
ns docs/plan.md
has "A7: a docs-only commit after the head still routes to finishing" "$out" "**Next:** Run dforge:finishing-a-development-branch."
printf 'code\n' > "$R7/code.txt" && git -C "$R7" add code.txt && git -C "$R7" commit -qm "fix: later"
ns docs/plan.md
has "A7: a later non-docs commit routes to a re-review of h..HEAD" "$out" "$H..HEAD"
lacks "A7: and not straight to finishing" "$out" "**Next:** Run dforge:finishing-a-development-branch."
git -C "$R7" reset -q --hard "$H" && git -C "$R7" commit -q --amend -m "rewritten head"
ns docs/plan.md
has "A7: a head no longer in history routes to a full final review" "$out" "final whole-branch review"
lacks "A7: not to a scoped re-review" "$out" "..HEAD"
check "A7: recovery logs a Ruling line naming the rewritten history" "$(grep -c 'Ruling: final review rerun.*history rewritten' "$P/skills/executing-plans/references/recovery.md")" "1"

write_ledger "Final review: clean (commits 1234567..$(git -C "$R7" rev-parse --short HEAD))"
mkdir -p "$R7/.dforge/sdd" && printf '{"action":"pr"}\n' > "$R7/.dforge/sdd/finish.json"
ns --kept docs/plan.md
check "A9: --kept exits 0" "$rc" "0"
has "A9: the block names the branch" "$out" "feature"
lacks "A9: it never says the plan is complete" "$out" "is complete"
check "A9: the no-plan finish record is gone after Step 7" "$([ -e "$R7/.dforge/sdd/finish.json" ] && echo kept || echo gone)" "gone"

# A10: finish-choice answer needs no saved preference.
R10="$TMP/fc"
mkrepo "$R10"
run bash -c "cd '$R10' && bash '$S/finish-choice' answer merge"
check "A10: answer with no saved preference exits 0" "$rc" "0"
run bash -c "cd '$R10' && bash '$S/finish-choice' get"
has "A10: the answer is recorded" "$out" "merge"
printf '{"action":"pr"}\n' > "$R10/.dforge/sdd/finish.json"
run bash -c "cd '$R10' && bash '$S/next-step' --complete docs/plan.md"
check "A10: --complete clears the no-plan record" "$([ -e "$R10/.dforge/sdd/finish.json" ] && echo kept || echo gone)" "gone"

# A8: Option 2's procedure writes the records only after the push and the PR.
EC="$P/skills/finishing-a-development-branch/references/execute-choice.md"
l_opt=$(grep -n '^### Option 2' "$EC" | head -n 1 | cut -d: -f1)
l_push=$(awk -v s="$l_opt" 'NR > s && /git push -u origin/ { print NR; exit }' "$EC")
l_after=$(awk -v s="$l_opt" 'NR > s && /have both succeeded/ { print NR; exit }' "$EC")
l_none=$(awk -v s="$l_after" 'NR > s && /write none/ { print NR; exit }' "$EC")
check "A8: the prose orders the push before the darkmem records" "$([ -n "$l_push" ] && [ -n "$l_after" ] && [ "$l_push" -lt "$l_after" ] && echo ordered || echo not)" "ordered"
check "A8: the prose writes no record when the push or the PR failed" "$([ -n "$l_none" ] && echo yes || echo no)" "yes"
check "A8: the prose still syncs the records afterwards" "$(sed -n "${l_after},$((l_after+4))p" "$EC" | grep -c 'darkmem-sync push')" "1"

# --- A11: the compaction snapshot (session-start.sh, source compact) ---
R11="$TMP/snap"
mkrepo "$R11"
mkdir -p "$R11/.dforge/handoff" "$R11/.dforge/sdd/plan"
printf '# Handoff\n\n## Next session\n\n**Next:** Resume docs/other-plan.md at Task 9 (OTHERPLAN-MARK).\n' > "$R11/.dforge/handoff/latest.md"
touch -d '3 hours ago' "$R11/.dforge/handoff/latest.md"
snap_payload() { # snap_payload <transcript>
  jq -n --arg tp "$1" --arg cwd "$R11" '{hook_event_name:"SessionStart",session_id:"s-snap",transcript_path:$tp,cwd:$cwd,source:"compact"}'
}
TR11="$TMP/snap.jsonl"
jq -cn --arg ts "$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%S.000Z)" \
  '{type:"user",timestamp:$ts,isSidechain:false,origin:{kind:"human"},message:{role:"user",content:"hello"}}' > "$TR11"
out=$(snap_payload "$TR11" | bash "$S/session-start.sh" 2>/dev/null)
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out")
has "A11: the snapshot is built" "$ctx" "## Compaction snapshot"
lacks "A11: a latest.md naming another plan that predates the session is omitted" "$ctx" "OTHERPLAN-MARK"
printf '# Handoff\n\n## Next session\n\n**Next:** Resume docs/plan.md at Task 2 (OWNPLAN-MARK).\n' > "$R11/.dforge/handoff/latest.md"
touch -d '3 hours ago' "$R11/.dforge/handoff/latest.md"
printf '# SDD ledger — plan: docs/plan.md\nTask 1: complete (commits a..b, review clean)\n' > "$R11/.dforge/sdd/plan/progress.md"
out=$(snap_payload "$TR11" | bash "$S/session-start.sh" 2>/dev/null)
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out")
has "A11: a latest.md naming a plan whose ledger this session wrote is kept" "$ctx" "OWNPLAN-MARK"
# Over the cap: the ledger's newest lines survive.
pad=$(printf 'x%.0s' $(seq 1 600))
{
  printf '# SDD ledger — plan: docs/plan.md\n'
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do printf 'Task %s: OLDLINE-%s %s\n' "$i" "$i" "$pad"; done
  printf 'Task 13: NEWESTLINE-MARK %s\n' "$pad"
} > "$R11/.dforge/sdd/plan/progress.md"
out=$(snap_payload "$TR11" | bash "$S/session-start.sh" 2>/dev/null)
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out")
has "A11: over the cap, the newest ledger line is kept" "$ctx" "NEWESTLINE-MARK"
lacks "A11: over the cap, the oldest lines are the ones dropped" "$ctx" "OLDLINE-1 "
check "A11: the hook output stays under the 10,000-character cap" "$([ "${#ctx}" -lt 10000 ] && echo yes || echo no)" "yes"

# --- footer ---
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
