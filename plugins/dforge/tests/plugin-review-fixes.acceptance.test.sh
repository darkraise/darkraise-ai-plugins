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

# --- A12: auto-run clear, stop --stale and start --register ---
R12="$TMP/ar"
mkrepo "$R12"
AR="$S/auto-run"
STATE12="$R12/.dforge/sdd/auto-run.json"
beat() { # beat <session> [age seconds]: the heartbeat a live cockpit writes
  local f
  f="$HOME/.claude/dforge/sessions/cockpit/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$(( $(date +%s) - ${2:-0} ))" > "$f"
}
arun() { local s=$1; shift; beat "$s"; (cd "$R12" && bash "$AR" --session "$s" "$@"); }
printf '# Spec\n' > "$R12/docs/spec12.md"
mkdir -p "$R12/docs/dforge/registers"
printf '# Register\n\n**Source:** x\n**Covers:** -\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n' > "$R12/docs/r12.md"
git -C "$R12" add -A && git -C "$R12" commit -qm docs
arun s-12 start --spec docs/spec12.md --register docs/r12.md >/dev/null
check "A12: start --register fills **Covers:** - with the spec" "$(grep -c '^\*\*Covers:\*\* docs/spec12.md$' "$R12/docs/r12.md")" "1"
arun s-12 attach --plan docs/plan.md >/dev/null
arun s-12 phase plan >/dev/null
# latest.md written for another plan.
mkdir -p "$R12/docs/plans"
{ cat "$R12/docs/plan.md"; } > "$R12/docs/plans/other.md"
(cd "$R12" && bash "$S/next-step" docs/plans/other.md >/dev/null 2>&1)
arun s-12 clear >/dev/null 2>"$TMP/err"; rc=$?
check "A12: clear refuses a latest.md prompt for another plan (exit 4)" "$rc" "4"
has "A12: the refusal says the prompt names another plan" "$(cat "$TMP/err")" "another plan"
check "A12: and leaves no clear pending" "$(arun s-12 pending)" "none"
# A run whose owner is gone is stopped from another session.
beat s-12 100000
(cd "$R12" && bash "$AR" --session s-other stop --stale >"$TMP/o" 2>&1); rc=$?
check "A12: stop --stale stops a run whose owner session is dead (exit 0)" "$rc" "0"
check "A12: the run is no longer active" "$(jq -r '.active' "$STATE12" | tr -d '\r')" "false"
arun s-12b start --spec docs/spec12.md --force >/dev/null
(cd "$R12" && bash "$AR" --session s-other stop --stale >"$TMP/o" 2>&1); rc=$?
check "A12: stop --stale leaves a live owner alone (exit 3)" "$rc" "3"
check "A12: the live run stays active" "$(jq -r '.active' "$STATE12" | tr -d '\r')" "true"
check "A12: resume-execution names a stale run and the command that stops it" "$(grep -c 'stop --stale' "$P/skills/resume-execution/SKILL.md")" "1"

# --- A13: darkmem stores applied and no Node on PATH ---
R13="$TMP/nonode"
mkrepo "$R13"
NB="$TMP/nonode-bin"
mkdir -p "$NB"
IFS=: read -r -a pdirs <<<"$PATH"
for d in "${pdirs[@]}"; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    b=${f##*/}
    case $b in node | nodejs | npm | npx | corepack) continue ;; esac
    [ -e "$NB/$b" ] || ln -s "$f" "$NB/$b" 2>/dev/null
  done
done
. "$HERE/fixtures/darkmem-stores.sh"
M13=$(stores_home "$HOME" "$R13" nonode local darkmem)
mkdir -p "$R13/.dforge/sdd/plan"
printf '# SDD ledger — plan: docs/plan.md\nTask 1: complete (commits a..b, review clean)\nTask 2: complete (commits b..c, review clean)\n' > "$R13/.dforge/sdd/plan/progress.md"
cp "$R13/.dforge/sdd/plan/progress.md" "$TMP/ledger13.before"
check "A13: the sandbox PATH has no node" "$(PATH=$NB command -v node || echo none)" "none"
for argv in "task-brief|--open|docs/plan.md|1" "next-step|docs/plan.md" "task-close|docs/plan.md|1|$CP" "task-step|start|docs/plan.md|1"; do
  IFS='|' read -r -a a <<<"$argv"
  run bash -c "cd '$R13' && PATH='$NB' bash '$S/${a[0]}' \"\${@:1}\"" _ "${a[@]:1}"
  check "A13: ${a[0]} exits 2 without node" "$rc" "2"
  has "A13: ${a[0]} names the node requirement" "$out$err" "node is required while darkmem stores are applied"
done
check "A13: no script wrote the local ledger" "$(cmp -s "$R13/.dforge/sdd/plan/progress.md" "$TMP/ledger13.before" && echo same || echo changed)" "same"
check "A13: no script wrote a ledger line into the mirror" "$([ -e "$M13/work/sdd/plan/progress.md" ] && echo written || echo none)" "none"
hookin() { jq -cn --arg cwd "$R13" '{hook_event_name:"SessionStart",session_id:"s-nonode",transcript_path:"",cwd:$cwd,source:"startup"}'; }
out=$(hookin | PATH="$NB" bash "$S/session-start.sh" 2>/dev/null); rc=$?
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out")
check "A13: session start passes" "$rc" "0"
check "A13: session start injects the warning once" "$(grep -c 'node is required while darkmem stores are applied' <<<"$ctx")" "1"
out=$(hookin | PATH="$NB" bash "$S/session-start.sh" 2>/dev/null)
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out")
check "A13: a second start of the same session injects none" "$(grep -c 'node is required while darkmem stores are applied' <<<"$ctx")" "0"
out=$(jq -cn --arg cwd "$R13" '{hook_event_name:"Stop",session_id:"s-nonode",transcript_path:"",cwd:$cwd,stop_hook_active:false,last_assistant_message:"Done."}' | PATH="$NB" bash "$S/turn-end.sh" 2>/dev/null); rc=$?
check "A13: the Stop hook passes" "$rc:$(jq -r '.decision // "pass"' <<<"${out:-{\}}" 2>/dev/null)" "0:pass"
rm -f "$HOME/.dforge/config.json" "$HOME/.dforge/stores.json"

# --- A14 (the readers), A16: the cockpit's session state file ---
R14="$TMP/ss"
mkrepo "$R14"
SS="$HOME/.claude/dforge/sessions"
mkdir -p "$SS/by-id" "$SS/state" "$SS/turns"
TP14="$TMP/s-ss.jsonl"
: > "$TP14"
jq -n --arg tp "$TP14" '{session_id:"s-ss",transcript_path:$tp}' > "$SS/by-id/s-ss.json"
touch -d '-60 seconds' "$SS/turns/s-ss"
now_ms() { echo $(( ($(date +%s) - ${1:-0}) * 1000 )); }
put_state() { # put_state <updated ms> <session> <window> [model]
  jq -nc --arg s "$2" --argjson u "$1" --argjson w "$3" --arg m "${4:-claude-unlisted-9}" --argjson at "$(now_ms)" \
    '{session:$s, updated:$u, window:$w, model:$m, partial:false,
      launches:[{id:"bfresh", kind:"shell", what:"Fresh launch", command:"sleep 999", startedAt:$at, outputFile:"", service:false, timer:false}]}' > "$SS/state/s-ss.json"
}
inflight() { out=$(cd "$R14" && CLAUDE_CODE_SESSION_ID=s-ss bash "$S/in-flight" 2>&1); rc=$?; }
put_state "$(now_ms)" s-ss 650000
inflight
check "A14: a hook reading the file mid-turn lists its launches (exit 1)" "$rc" "1"
has "A14: the launch is listed" "$out" "bfresh"
has "A14: the source is named as the session file" "$out" "session"
put_state "$(now_ms 120)" s-ss 650000
inflight
check "A14: launches older than the turn stamp are ignored (transcript has none: exit 0)" "$rc" "0"
lacks "A14: the stale launch is not listed" "$out" "bfresh"
LOG14="$R14/.dforge/session-state.log"
check "A14: the rejection is logged to session-state.log" "$(grep -c 'launches.*stale' "$LOG14" 2>/dev/null)" "1"
inflight
check "A14: the same turn logs the rejection once" "$(grep -c 'launches.*stale' "$LOG14")" "1"
bl() { out=$(cd "$R14" && CLAUDE_CODE_SESSION_ID=s-ss bash "$S/context-size" 2>&1); rc=$?; }
printf '{"type":"assistant","isSidechain":false,"message":{"model":"claude-unlisted-9","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":300000}}}\n' > "$TP14"
bl
check "A14: the window of the same session is still used when launches are stale" "$rc" "0"
has "A14: the budget line names the session file as its window source" "$out" "window session file"
put_state "$(now_ms)" s-other 650000
inflight
check "A14: a file written for another session is ignored" "$(grep -c 'session mismatch' "$LOG14")" "1"
printf 'not json\n' > "$SS/state/s-ss.json"
inflight
check "A14: an unparseable file is logged" "$(grep -c 'unparseable' "$LOG14")" "1"
rm -f "$SS/state/s-ss.json"
inflight
check "A14: a missing file is logged" "$(grep -c 'missing' "$LOG14")" "1"

# A16: the window comes from the session file; an unlisted model without one is unknown.
bl
check "A16: an unlisted model with no session file exits 3" "$rc" "3"
has "A16: and prints the unknown verdict" "$out" "unknown"
lacks "A16: with no arithmetic error" "$out" "syntax error"
put_state "$(now_ms)" s-ss 650000
bl
b650=$out
check "A16: the session file's window is used (exit 0)" "$rc" "0"
put_state "$(now_ms)" s-ss 800000
bl
check "A16: a different window changes the budget" "$([ "$out" != "$b650" ] && echo differs || echo same)" "differs"
rm -f "$SS/state/s-ss.json"
# the auto run: unknown, exit 3, nothing pending, and a pending after-compact settles
printf '# Spec\n' > "$R14/docs/spec16.md"; printf '# P\n\n### Task 1: x\n\nb\n' > "$R14/docs/p16.md"
git -C "$R14" add -A && git -C "$R14" commit -qm docs
beat s-ss 2>/dev/null || { mkdir -p "$SS/cockpit"; date +%s > "$SS/cockpit/s-ss"; }
(cd "$R14" && bash "$S/auto-run" --session s-ss start --spec docs/spec16.md >/dev/null && bash "$S/auto-run" --session s-ss attach --plan docs/p16.md >/dev/null && bash "$S/auto-run" --session s-ss phase plan >/dev/null 2>&1)
bl
check "A16: the auto line exits 3 for an unlisted model" "$rc" "3"
has "A16: the auto line prints the unknown verdict" "$out" "unknown"
check "A16: it sets no pending" "$(cd "$R14" && bash "$S/auto-run" --session s-ss pending)" "none"
(cd "$R14" && bash "$S/auto-run" --session s-ss compacted >/dev/null 2>&1)
bl
check "A16: a pending after-compact settles (no pending left)" "$(cd "$R14" && bash "$S/auto-run" --session s-ss pending)" "none"
(cd "$R14" && bash "$S/auto-run" --session s-ss stop >/dev/null 2>&1)

# --- A15: a running service does not pass a mid-plan summary stop ---
R15="$TMP/stop"
mkrepo "$R15"
git -C "$R15" config user.name t; git -C "$R15" config user.email t@example.invalid
mkdir -p "$R15/.dforge/sdd/plan"
LEDGER15="$R15/.dforge/sdd/plan/progress.md"
TURNS="$HOME/.claude/dforge/sessions/turns"; mkdir -p "$TURNS"
t_prompt() { # t_prompt <session>
  jq -n --arg sid "$1" --arg cwd "$R15" '{hook_event_name:"UserPromptSubmit",session_id:$sid,cwd:$cwd,prompt:"go"}' | bash "$S/turn-start.sh"
}
t_stop() { # t_stop <script> <session> <message> [transcript]
  jq -n --arg sid "$2" --arg cwd "$R15" --arg msg "$3" --arg tp "${4:-}" \
    '{hook_event_name:"Stop",session_id:$sid,cwd:$cwd,transcript_path:$tp,stop_hook_active:false}
     + (if $msg == "" then {} else {last_assistant_message:$msg} end)' | bash "$S/$1"
}
decision() { jq -r '.decision // "none"' <<<"${1:-{\}}" 2>/dev/null || echo none; }
bg_transcript() { # bg_transcript <file> <description> <command>
  jq -nc --arg d "$2" --arg c "$3" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_bg",name:"Bash",input:{description:$d,command:$c,run_in_background:true}}]}}' > "$1"
  jq -nc '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_bg",content:"Command running in background with ID: bg1. Output is being written to: /tmp/bg1.output."}]}}' >> "$1"
}
SVC15="$TMP/svc15.jsonl"; bg_transcript "$SVC15" "Dev server" "npm run dev"
NOTHING15="$TMP/nothing15.jsonl"; : > "$NOTHING15"
sleep 1; t_prompt s-15
printf '# SDD ledger — plan: docs/plan.md\nTask 1: complete (commits a..b, review clean)\n' > "$LEDGER15"
check "A15: with nothing running a mid-plan summary stop is held" "$(decision "$(t_stop turn-end.sh s-15 'Task 1 is done.' "$NOTHING15")")" "block"
check "A15: with only a dev server running it is held as well" "$(decision "$(t_stop turn-end.sh s-15 'Task 1 is done.' "$SVC15")")" "block"
FIN15="$TMP/fin15.jsonl"; bg_transcript "$FIN15" "Suite" "npm test"
check "A15: finite background work still passes the plain stop" "$(decision "$(t_stop turn-end.sh s-15 'Task 1 is done.' "$FIN15")")" "none"

# --- A17, A18, A22, A23: the UI hooks and fast mode ---
R17="$TMP/ui"
mkrepo "$R17"
git -C "$R17" config user.name t; git -C "$R17" config user.email t@example.invalid
mkdir -p "$R17/src" "$R17/docs/dforge/ui-ux"
printf 'export const App = () => <main>Hi</main>;\n' > "$R17/src/App.tsx"
printf '<img src="a.png">\n' > "$R17/src/Bad.tsx"
printf '# UI profile\n\n**Platform:** web\n' > "$R17/docs/dforge/ui-ux/profile.md"
git -C "$R17" add -A && git -C "$R17" commit -qm ui
u_prompt() { jq -n --arg sid "$1" --arg cwd "$R17" '{hook_event_name:"UserPromptSubmit",session_id:$sid,cwd:$cwd,prompt:"go"}' | bash "$S/turn-start.sh"; }
u_edit() { # u_edit <session> <transcript>
  jq -n --arg sid "$1" --arg cwd "$R17" --arg f "$R17/src/Bad.tsx" --arg tp "$2" \
    '{hook_event_name:"PostToolUse",session_id:$sid,cwd:$cwd,transcript_path:$tp,tool_name:"Edit",tool_input:{file_path:$f}}' | bash "$S/ui-edit-hook.sh"
}
u_stop() { # u_stop <session> <message> [transcript]
  jq -n --arg sid "$1" --arg cwd "$R17" --arg msg "$2" --arg tp "${3:-}" \
    '{hook_event_name:"Stop",session_id:$sid,cwd:$cwd,transcript_path:$tp,stop_hook_active:false}
     + (if $msg == "" then {} else {last_assistant_message:$msg} end)' | bash "$S/ui-turn-end.sh"
}
said() { jq -nc --arg t "$1" --arg ts "$2" '{type:"assistant",timestamp:$ts,message:{role:"assistant",content:[{type:"text",text:$t}]}}'; }
findings() { jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$1" 2>/dev/null | grep -c 'img-alt'; }

# A17: request-scoped fast mode ends at the next human prompt. Claude Code names a
# session's transcript after the session, which is how the hooks find its turn stamp.
TR17="$TMP/u-17.jsonl"
u_prompt u-17
touch -d '-20 minutes' "$TURNS/u-17"
said 'Process: fast — a one-line tweak' "$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S.000Z)" > "$TR17"
check "A17: within the request that wrote the line the edit hook stays silent" "$(findings "$(u_edit u-17 "$TR17")")" "0"
sleep 1; u_prompt u-17
said 'Working on it.' "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" >> "$TR17"
check "A17: in a later request with no Process: fast line the edit hook runs again" "$(findings "$(u_edit u-17 "$TR17")")" "1"
printf '// change\n' >> "$R17/src/App.tsx"; git -C "$R17" commit -qam 'ui change'
check "A17: and the UI proof hold runs again" "$(decision "$(u_stop u-17 'Done.' "$TR17")")" "block"

# A18: a session-scoped line stays on across requests, with no state file.
TR18="$TMP/u-18.jsonl"
u_prompt u-18
touch -d '-20 minutes' "$TURNS/u-18"
said 'Process: fast (session) — spikes all day' "$(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S.000Z)" > "$TR18"
sleep 1; u_prompt u-18
said 'Another request.' "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" >> "$TR18"
check "A18: no state file exists" "$([ -e "$HOME/.claude/dforge/sessions/state/u-18.json" ] && echo yes || echo no)" "no"
check "A18: the edit hook stays silent in a later request" "$(findings "$(u_edit u-18 "$TR18")")" "0"
printf '// change 2\n' >> "$R17/src/App.tsx"; git -C "$R17" commit -qam 'ui change 2'
check "A18: the UI proof hold stays down" "$(decision "$(u_stop u-18 'Done.' "$TR18")")" "none"
said 'Process: bounded — no trigger' "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" >> "$TR18"
check "A18: a later Process: line naming another path turns the hooks back on" "$(findings "$(u_edit u-18 "$TR18")")" "1"

# A22: stand-downs after a UI edit.
sleep 1; u_prompt u-22
printf '// change 3\n' >> "$R17/src/App.tsx"; git -C "$R17" commit -qam 'ui change 3'
check "A22: a UI change with no proof is held" "$(decision "$(u_stop u-22 'Task 2 is done.')")" "block"
check "A22: a stop carrying ## Next session passes" "$(decision "$(u_stop u-22 $'Done.\n\n## Next session\n\n**Status:** x')")" "none"
mkdir -p "$R17/.dforge/sdd/ui-plan"
printf '# SDD ledger — plan: docs/ui-plan.md\nTask 2: waiting — which colour?\n' > "$R17/.dforge/sdd/ui-plan/progress.md"
check "A22: a ledger written this turn ending on waiting — passes" "$(decision "$(u_stop u-22 'Which colour should the button be?')")" "none"
rm -rf "$R17/.dforge/sdd/ui-plan"
BG22="$TMP/bg22.jsonl"; bg_transcript "$BG22" "Suite" "npm test"
check "A22: finite background work running passes" "$(decision "$(u_stop u-22 'Waiting for the suite.' "$BG22")")" "none"

# A23: the transcript supplies the message when last_assistant_message is absent.
LT23="$TMP/last23.jsonl"
jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Stopping here.\n\nUI proof: pending — needs the device"}]}}' > "$LT23"
check "A23: no last_assistant_message: the transcript's UI proof: pending line passes" "$(decision "$(u_stop u-22 '' "$LT23")")" "none"
check "A23: a message ending UI proof: pending — why passes" "$(decision "$(u_stop u-22 $'Done.\n\nUI proof: pending — no browser here')")" "none"
check "A23: a pending line with no reason is still held" "$(decision "$(u_stop u-22 $'Done.\n\nUI proof: pending')")" "block"

# --- A21: session start is bounded when darkmem never answers ---
R21="$TMP/hang"
mkrepo "$R21"
node -e 'const s=require("http").createServer(()=>{}); s.listen(0,"127.0.0.1",()=>{require("fs").writeFileSync(process.argv[1], String(s.address().port))})' "$TMP/hang.port" &
HANG_PID=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMP/hang.port" ] && break; sleep 0.5; done
M21=$(stores_home "$HOME" "$R21" hang darkmem darkmem)
sed -i "s#http://127.0.0.1:9#http://127.0.0.1:$(cat "$TMP/hang.port")#" "$HOME/.dforge/config.json"
start=$SECONDS
out=$(jq -cn --arg cwd "$R21" '{hook_event_name:"SessionStart",session_id:"s-hang",transcript_path:"",cwd:$cwd,source:"startup"}' \
  | DARKMEM_API_KEY=k DARKMEM_SYNC_TIMEOUT_MS=300000 timeout 120 bash "$S/session-start.sh" 2>/dev/null)
elapsed=$((SECONDS - start))
kill "$HANG_PID" 2>/dev/null; wait "$HANG_PID" 2>/dev/null
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out")
check "A21: session start returned within 45 seconds ($elapsed s)" "$([ "$elapsed" -lt 45 ] && echo yes || echo no)" "yes"
check "A21: it still injected the entry point" "$(grep -c 'dforge:using-dforge' <<<"$ctx")" "1"
check "A21: exactly one line says the sync did not finish" "$(grep -c 'did not finish' <<<"$ctx")" "1"
check "A21: and that line names the sync command" "$(grep 'did not finish' <<<"$ctx" | grep -c 'darkmem-sync')" "1"
rm -f "$HOME/.dforge/config.json" "$HOME/.dforge/stores.json"

# --- A25: unnamed failures at the base and at the head count as new ---
R25="$TMP/base"
git init -q "$R25"; git -C "$R25" config user.name t; git -C "$R25" config user.email t@example.invalid
mkdir -p "$R25/docs"
{
  printf '# Base Fixture Plan\n\n**Goal:** Fixture.\n\n**Execution:** inline — `claude --model sonnet --effort high` — fixture\n\n'
  printf '## Task index\n\n1. One\n\n### Task 1: One\n\n**Files:**\n- Modify: `app.txt`\n\n**Implementer:** dforge:impl-sonnet-high\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n'
} > "$R25/docs/plan.md"
printf '#!/usr/bin/env bash\nif [ -s failing.txt ]; then cat failing.txt; exit 1; fi\n' > "$R25/suite.sh"
printf 'one\n' > "$R25/app.txt"
printf 'boom\n' > "$R25/failing.txt"
printf '.dforge/\n' > "$R25/.gitignore"
git -C "$R25" add -A && git -C "$R25" commit -qm base
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-gate usable=true reason=ok review=true resets_at=- source=cache"' > "$TMP/gate-stub"
printf '%s\n' '#!/usr/bin/env bash' 'echo "agy-gate usable=false reason=setting review=false resets_at=- claude=on claude_resets_at=- source=setting"' > "$TMP/agy-gate-stub"
export TASK_STEP_CODEX_GATE="$TMP/gate-stub" TASK_STEP_AGY_GATE="$TMP/agy-gate-stub" DR_CODEX_SESSION_DIR="$TMP/sessions" CLAUDE_CODE_SESSION_ID=acc-base SUITE_MARK="$TMP/marks"
ts25() { out=$(cd "$R25" && bash "$S/task-step" "$@" 2>"$TMP/err"); rc=$?; err=$(cat "$TMP/err"); }
sr25() { (cd "$R25" && bash "$S/suite-run" -- bash -c 'bash suite.sh' >/dev/null 2>&1); }
ts25 start docs/plan.md 1 --suite 'bash suite.sh'
printf 'impl\n' >> "$R25/app.txt"
git -C "$R25" add -A && git -C "$R25" commit -qm "work 1"
sr25
ts25 review docs/plan.md 1
WS25=$(cd "$R25" && bash "$S/sdd-workspace" docs/plan.md)
printf '## Verdict\nspec: pass\nquality: approved\nscores: spec 17 / scope 17 / verification 16 / quality 16\n\n## Strengths\nFine.\n\n## Findings\n\n## Cannot verify\n\n## Assessment\nFine.\n' > "$WS25/task-1-review-report.md"
ts25 verdict docs/plan.md 1
has "A25: an unnamed base failure and an unnamed head failure with the same exit code are a new failure" "$out" "suite: red (1 failing, 0 baseline)"

# --- A26: suite-run records no reusable row after HEAD moved or a failed git status ---
R26="$TMP/suite"
mkrepo "$R26"
git -C "$R26" config user.name t; git -C "$R26" config user.email t@example.invalid
sr26() { out=$(cd "$R26" && bash "$S/suite-run" -- bash -c "$1" 2>&1); rc=$?; }
sr26 'if [ ! -f .dforge/once ]; then mkdir -p .dforge; touch .dforge/once; git commit -q --allow-empty -m moved; fi'
check "A26: the run that moves HEAD passes" "$rc" "0"
sr26 'if [ ! -f .dforge/once ]; then mkdir -p .dforge; touch .dforge/once; git commit -q --allow-empty -m moved; fi'
lacks "A26: no pass is reused at the new HEAD after HEAD moved during the run" "$out" "reused pass"
rm -f "$R26/.dforge/once"
sr26 'echo ok'
sr26 'echo ok'
has "A26: a plain run at a settled HEAD is reused (control)" "$out" "reused pass"
rm -f "$R26/.dforge/suites.tsv"
CORRUPT='if [ ! -f .dforge/once2 ]; then mkdir -p .dforge; touch .dforge/once2; printf garbage > "$(git rev-parse --git-dir)/index"; fi'
sr26 "$CORRUPT"
rm -f "$R26/.git/index" && git -C "$R26" reset -q
sr26 "$CORRUPT"
lacks "A26: a run whose git status failed afterwards is dirty, never reused" "$out" "reused pass"
check "A26: the row of the run whose git status failed is not marked clean" "$(sed -n 1p "$R26/.dforge/suites.tsv" | cut -f2)" "dirty"

# --- A27: a host with only gtimeout ---
BIN27="$TMP/bin27"; mkdir -p "$BIN27"
wrap27() { printf '#!%s\nexec "%s" "$@"\n' "$BASH" "$2" > "$BIN27/$1"; chmod +x "$BIN27/$1"; }
for t in env sleep true cat head tr dirname basename jq sed grep; do wrap27 "$t" "$(type -P "$t")"; done
wrap27 gtimeout "$(type -P timeout)"
PATH="$BIN27" "$BASH" "$S/with-timeout" 5 true; rc=$?
check "A27: with only gtimeout, with-timeout 5 true exits 0" "$rc" "0"
printf '#!%s\nsleep 120\n' "$BASH" > "$BIN27/agy"; chmod +x "$BIN27/agy"
start=$SECONDS
out=$(timeout 90 env PATH="$BIN27" "$BASH" "$S/agy-locate" 2>&1); rc=$?
check "A27: agy-locate bounds a hanging agy --version (returned in $((SECONDS - start)) s)" "$([ $((SECONDS - start)) -lt 60 ] && echo bounded || echo unbounded)" "bounded"
check "A27: and reports the CLI unusable" "$rc" "1"
rm -f "$BIN27/gtimeout"
out=$(timeout 30 env PATH="$BIN27" "$BASH" "$S/agy-locate" 2>&1); rc=$?
check "A27: with no timeout command at all agy-locate reports the CLI unusable" "$rc" "1"

# --- A28: without setsid a timed-out panel runner leaves no descendant alive ---
D28="$TMP/panel"; mkdir -p "$D28/work"
printf '# r\n' > "$D28/prompt.md"
for fam in codex agy; do
  printf 'echo "%s-gate usable=true reason=ok review=true resets_at=- source=cache"\n' "$fam" > "$D28/$fam-gate"
  printf 'echo "%s-judge none/none status=OK exit=0 out=- evidence=none"\n' "$fam" > "$D28/$fam-runner"
done
cat > "$D28/tree-runner" <<RUNNER
#!/usr/bin/env bash
( ( sleep 300 & echo \$! >> "$D28/pids"; wait ) & echo \$! >> "$D28/pids"; sleep 300 & echo \$! >> "$D28/pids"; wait ) &
echo \$! >> "$D28/pids"
sleep 300 &
echo \$! >> "$D28/pids"
wait
RUNNER
chmod +x "$D28/tree-runner" "$D28"/*-gate "$D28"/codex-runner "$D28"/agy-runner
: > "$D28/pids"
out=$(PANEL_NO_SETSID=1 PANEL_BOUND_SECONDS=3 PANEL_CODEX_GATE="$D28/codex-gate" PANEL_AGY_GATE="$D28/agy-gate" \
  PANEL_CODEX_RUNNER="$D28/codex-runner" PANEL_AGY_RUNNER="$D28/tree-runner" CLAUDE_CODE_SESSION_ID=s-28 \
  timeout 60 bash "$S/run-review-panel" --kind task --tier light --cwd "$D28/work" --out-dir "$D28/out" --prompt "$D28/prompt.md" 2>/dev/null)
sleep 1
alive=0
while read -r p; do
  [ -n "$p" ] || continue
  if kill -0 "$p" 2>/dev/null; then alive=$((alive + 1)); kill -9 "$p" 2>/dev/null; fi
done < "$D28/pids"
has "A28: the timed-out runner is reported as TIMEOUT" "$out" "status=TIMEOUT"
check "A28: every one of the runner's $(wc -l < "$D28/pids" | tr -d ' ') descendants is gone" "$alive" "0"

# --- A29: task-step --cwd, and a header command with a trailing note ---
R29="$TMP/cwd"
git init -q "$R29"; git -C "$R29" config user.name t; git -C "$R29" config user.email t@example.invalid
mkdir -p "$R29/docs"
{
  printf '# Cwd Fixture Plan\n\n**Goal:** Fixture.\n\n**Execution:** inline — `claude --model sonnet --effort high` — fixture\n\n'
  printf '**Integration check:** `bash mark.sh integ 0` — the full suite (slow; see CI)\n\n'
  printf '## Task index\n\n1. One\n\n### Task 1: One\n\n**Files:**\n- Modify: `app.txt`\n\n**Implementer:** dforge:impl-sonnet-high\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n'
} > "$R29/docs/plan.md"
printf '#!/usr/bin/env bash\n: > "$MARK_DIR/$1"\nexit "${2:-0}"\n' > "$R29/mark.sh"
printf 'one\n' > "$R29/app.txt"; printf '.dforge/\n' > "$R29/.gitignore"
git -C "$R29" add -A && git -C "$R29" commit -qm base
BASE29=$(git -C "$R29" rev-parse --short HEAD)
ts29() { out=$(cd "$R29" && bash "$S/task-step" "$@" 2>"$TMP/err"); rc=$?; err=$(cat "$TMP/err"); }
ts29 start docs/plan.md 1
git -C "$R29" worktree add -q -b wt "$TMP/wt29"
printf 'two\n' > "$TMP/wt29/wtonly.txt"
git -C "$TMP/wt29" add -A && git -C "$TMP/wt29" commit -qm "work in the worktree"
WTHEAD=$(git -C "$TMP/wt29" rev-parse --short HEAD)
ts29 review docs/plan.md 1 --cwd "$TMP/wt29"
check "A29: review --cwd exits 0" "$rc" "0"
has "A29: review --cwd resolves HEAD in that directory" "$out" "$BASE29..$WTHEAD"
check "A29: the review diff holds the worktree's change" "$(grep -q '^+++ b/wtonly.txt$' "$R29"/.dforge/sdd/plan/review-*.diff && echo yes || echo no)" "yes"
WS29=$(cd "$R29" && bash "$S/sdd-workspace" docs/plan.md)
printf '## Verdict\nspec: cannot-verify\nquality: approved\nscores: spec 15 / scope 17 / verification 12 / quality 16\n\n## Strengths\nFine.\n\n## Findings\n\n## Cannot verify\n- cannot-verify: baseline bash mark.sh integ 0, expect pass — the Integration check\n\n## Assessment\nFine.\n' > "$WS29/task-1-review-report.md"
mkdir -p "$TMP/marks29"
out=$(cd "$R29" && MARK_DIR="$TMP/marks29" bash "$S/task-step" verdict docs/plan.md 1 --cwd "$TMP/wt29" 2>"$TMP/err"); rc=$?
check "A29: verdict --cwd exits 0" "$rc" "0"
check "A29: the Integration check's command ran, taken from before its trailing note" "$(ls "$TMP/marks29" | tr '\n' ' ')" "integ "
check "A29: and the item is settled, not a finding" "$(grep -c 'settled by task-step check baseline' "$WS29/progress.md")" "1"
git -C "$R29" worktree remove --force "$TMP/wt29"

# --- A30: ui-proof check with documents in darkmem and screenshots in the checkout ---
R30="$TMP/proof"
mkrepo "$R30"
git -C "$R30" config user.name t; git -C "$R30" config user.email t@example.invalid
mkdir -p "$R30/src"
printf 'export const App = () => null;\n' > "$R30/src/App.tsx"
git -C "$R30" add -A && git -C "$R30" commit -qm app
BASE30=$(git -C "$R30" rev-parse HEAD)
M30=$(stores_home "$HOME" "$R30" proofs darkmem local)
PD30="$M30/dforge/ui-ux/proofs"
mkdir -p "$PD30" "$R30/.dforge/ui-proofs"
printf '# UI profile\n\n**Platform:** web\n' > "$M30/dforge/ui-ux/profile.md"
printf 'png' > "$R30/.dforge/ui-proofs/a.png"
printf '// change\n' >> "$R30/src/App.tsx"; git -C "$R30" commit -qam 'ui change'
up30() { (cd "$R30" && bash "$S/ui-proof" "$@"); }
proof30() { # proof30 <evidence cell>: a stamped, judged touch report citing the cell
  { printf '# UI proof: t\n\n**Contract:** touch\n**Platform:** web\n**Evidence:** local\n\n## Delta\n\n**UI/UX depth:** touch — a fix\n\n- **UX-1** — the fix\n'
    printf '\n## Results\n\n| ID | Verdict | Evidence | Note |\n|---|---|---|---|\n| UX-1 | pass | %s | |\n' "$1"
  } > "$PD30/2026-11-16-t.md"
  up30 stamp "$PD30/2026-11-16-t.md" >/dev/null
  fp=$(up30 fingerprint)
  printf 'The proof holds.\n\nVerdict: ship %s\n' "$fp" > "$PD30/2026-11-16-t.judge.md"
  printf '\n**Judge:** ship %s — %s/2026-11-16-t.judge.md\n' "$fp" "$PD30" >> "$PD30/2026-11-16-t.md"
}
proof30 '.dforge/ui-proofs/a.png'
up30 check --base "$BASE30" >/dev/null 2>&1; rc=$?
check "A30: a screenshot cited under the checkout's .dforge/ui-proofs/ is accepted while documents live in darkmem" "$rc" "0"
proof30 '.dforge/ui-proofs/missing.png'
up30 check --base "$BASE30" >/dev/null 2>&1; rc=$?
check "A30: a cited screenshot that is not there still fails" "$rc" "1"
rm -f "$HOME/.dforge/config.json" "$HOME/.dforge/stores.json"

# --- A32: no judge agent lists WebFetch ---
n32=0
for f in "$P"/agents/judge-*.md; do
  n32=$((n32 + 1))
  tools=$(awk '/^---[[:space:]]*$/ { c++; next } c == 1 && /^tools:/ { print; exit }' "$f")
  check "A32: $(basename "$f") has a tools line" "$([ -n "$tools" ] && echo yes || echo no)" "yes"
  lacks "A32: $(basename "$f") does not list WebFetch" "$tools" "WebFetch"
done
check "A32: there are judge agent files to check" "$([ "$n32" -ge 3 ] && echo yes || echo no)" "yes"

# --- A33: impl-stop-gate keys on the reply's Report: line ---
R33="$TMP/gate"
mkrepo "$R33"
gate() { # gate <agent id> <reply>: the SubagentStop input for a QA seat
  jq -n --arg id "$1" --arg cwd "$R33" --arg msg "$2" \
    '{session_id:"s-33",transcript_path:"",cwd:$cwd,permission_mode:"default",agent_id:$id,agent_type:"dforge:impl-sonnet-high",hook_event_name:"SubagentStop",stop_hook_active:false,agent_transcript_path:"",last_assistant_message:$msg}' \
    | bash "$S/impl-stop-gate" 2>"$TMP/gate.err"
}
gate a33-missing "QA done.
Report: $R33/missing-report.md"; rc=$?
check "A33: a reply ending Report: <path> blocks when the file is missing (exit 2)" "$rc" "2"
printf 'Findings only, no heading.\n' > "$R33/no-verdict.md"
gate a33-noverdict "QA done.
Report: $R33/no-verdict.md"; rc=$?
check "A33: it blocks when the file does not open with ## Verdict (exit 2)" "$rc" "2"
printf '## Verdict\npass: 2\n' > "$R33/good.md"
gate a33-good "QA done.
Report: $R33/good.md"; rc=$?
check "A33: it passes when the file opens with ## Verdict" "$rc" "0"
gate a33-none "Walkthrough done, no report line here."; rc=$?
check "A33: a reply with no Report: line passes unchecked" "$rc" "0"
gate a33-status $'**Status:** DONE'; rc=$?
check "A33: a **Status:** line alone is not looked at" "$rc" "0"

# --- A35: the workflow line on a Codex host under autoRun=on ---
export HOME="$TMP/home-wf"; mkdir -p "$HOME"
bash "$S/dforge-config" set designApproval whole >/dev/null 2>&1
bash "$S/dforge-config" set specReview false >/dev/null 2>&1
out=$(bash "$S/dforge-config" workflow --host codex 2>&1)
has "A35: --host codex emits the designApproval override under the default autoRun=on" "$out" "designApproval=whole"
has "A35: --host codex emits the specReview override" "$out" "specReview=false"
check "A35: the same settings on a Claude host emit nothing under autoRun=on" "$(bash "$S/dforge-config" workflow 2>&1)" ""
export HOME="$TMP/home"

# --- A52: the fast-mode question offers fast for this session ---
for skill in brainstorming systematic-debugging; do
  has "A52: $skill asks for a fast-for-this-session answer" "$(tr '\n' ' ' < "$P/skills/$skill/SKILL.md" | tr -s ' ')" "fast mode for this session"
done

# --- footer ---
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
