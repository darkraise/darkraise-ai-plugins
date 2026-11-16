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

# --- footer ---
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
