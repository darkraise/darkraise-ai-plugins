#!/usr/bin/env bash
# Acceptance checks for docs/dforge/specs/2026-11-09-clean-session-phases-design.md
# (the script, document and review-package statements; the cockpit statements
# are in clean-session-phases.acceptance.test.ts): the switch and finishing
# take the cleared-session path, and review-package leaves a branch's own
# design documents out of what a judge reads.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$(cd "$HERE/.." && pwd)"
S="$P/scripts"
AR="$S/auto-run"
TMP="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export LC_ALL=C MSYS_NO_PATHCONV=1 DFORGE_NO_SETTINGS=1 GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset DFORGE_BUDGET DFORGE_JQ DFORGE_FLOCK CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR

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
matches() { # matches <name> <haystack> <extended regex>
  if grep -qiE -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       no match: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

# --- the script statements: A3, A4, A5 ---
REPO="$TMP/repo"
STATE="$REPO/.dforge/sdd/auto-run.json"
HANDOFF="$REPO/.dforge/handoff/latest.md"
SPEC=docs/dforge/specs/2026-11-09-widget-design.md
PLAN_REL=docs/dforge/plans/2026-11-09-widget.md
LEDGER="$REPO/.dforge/sdd/2026-11-09-widget/progress.md"
beat() { # beat <session>: the heartbeat a live cockpit writes
  local f
  f="$HOME/.claude/dforge/sessions/cockpit/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$(date +%s)" > "$f"
}
arun() { # arun <session> <args...>
  local s=$1
  shift
  beat "$s"
  (cd "$REPO" && bash "$AR" --session "$s" "$@")
}
field() { jq -r --arg f "$1" '.[$f] | tostring' < "$STATE" | tr -d '\r'; }
resumes() { arun "$1" status | sed -n 's/.* \([0-9][0-9]*\) resumes.*/\1/p'; }

git init -q -b main "$REPO"
mkdir -p "$REPO/docs/dforge/plans" "$REPO/docs/dforge/specs"
printf '# Spec\n' > "$REPO/$SPEC"
{
  printf '# Widget Implementation Plan\n\n**Spec:** `%s`\n\n' "$SPEC"
  printf '**Execution:** subagent — `claude --model sonnet --effort high` — Task 1 scores 4\n\n'
  printf '## Task index\n\n1. Only\n\n### Task 1: Only\n\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\nBody.\n'
} > "$REPO/$PLAN_REL"
git -C "$REPO" add -A
git -C "$REPO" commit -qm init

# A run that has already self-resumed once, so an unchanged count is not zero by default.
arun s-1 start --spec "$SPEC" --register docs/r.md >/dev/null
arun s-1 attach --plan "$PLAN_REL" >/dev/null
arun s-1 phase plan >/dev/null
(cd "$REPO" && bash "$S/next-step" "$PLAN_REL" >/dev/null)
arun s-1 clear >/dev/null
arun s-1 rebind --to s-2 >/dev/null
arun s-2 resumed >/dev/null
before=$(resumes s-2)
check "A3: the fixture run has self-resumed once" "$before" "1"

arun s-2 switch >/dev/null; status=$?
check "A3: switch exits 0" "$status" "0"
arun s-2 clear --phase >/dev/null; status=$?
check "A3: the switch's clear exits 0" "$status" "0"
status_line=$(arun s-2 status)
has "A3: status reports phase execute" "$status_line" "auto run: execute"
matches "A3: status says setup is due" "$status_line" "setup due"
check "A3: the resume count is unchanged" "$(resumes s-2)" "$before"
check "A3: the first prompt is the one next-step wrote" "$(field resumePrompt | grep -c 'dforge:subagent-driven-development')" "1"

# A4
arun s-2 stop >/dev/null
arun s-3 start --spec "$SPEC" --register docs/r.md --force >/dev/null
arun s-3 attach --plan "$PLAN_REL" >/dev/null
arun s-3 phase plan >/dev/null
(cd "$REPO" && bash "$S/next-step" "$PLAN_REL" >/dev/null)
arun s-3 switch >/dev/null
check "A4: the fixture has switch pending" "$(arun s-3 pending)" "switch"
arun s-3 compacted --switch >/dev/null 2>&1; status=$?
check "A4: compacted --switch exits as a usage error" "$status" "2"
check "A4: compacted --switch books nothing" "$(field compactions):$(arun s-3 pending)" "0:switch"
usage_text=$(bash "$AR" 2>&1)
has "A4: the usage text is printed" "$usage_text" "usage: auto-run"
lacks "A4: the usage text does not name switch-resume" "$usage_text" "switch-resume"
lacks "A4: the usage text has no compacted --switch" "$usage_text" "compacted --switch"

# A5
arun s-3 stop >/dev/null
arun s-4 start --spec "$SPEC" --register docs/r.md --force >/dev/null
arun s-4 attach --plan "$PLAN_REL" >/dev/null
mkdir -p "$(dirname "$LEDGER")"
{
  printf '# SDD ledger — plan: %s\n' "$PLAN_REL"
  printf 'Task 1: complete (x)\n'
  printf 'Final review: clean (commits a1b2c3d..d4e5f6a)\n'
} > "$LEDGER"
arun s-4 phase final >/dev/null
resumes_before=$(resumes s-4)
block=$(cd "$REPO" && bash "$S/next-step" "$PLAN_REL")
first_prompt=$(awk '/^Paste as the first prompt:/ { want = 1; next } want && /^```/ { if (seen) exit; seen = 1; next } want && seen { print }' <<<"$block")
has "A5: next-step's block names finishing" "$block" "Run dforge:finishing-a-development-branch."
arun s-4 phase finish >/dev/null; status=$?
check "A5: phase finish exits 0" "$status" "0"
arun s-4 clear --phase >/dev/null; status=$?
check "A5: clear --phase exits 0" "$status" "0"
has "A5: status reports phase finish" "$(arun s-4 status)" "auto run: finish"
check "A5: the phase is finish" "$(field phase)" "finish"
check "A5: clear is pending" "$(arun s-4 pending)" "clear"
check "A5: the first prompt is next-step's finishing prompt" "$(field resumePrompt)" "$first_prompt"
has "A5: the first prompt reaches finishing through resume-execution" "$(field resumePrompt)" "with dforge:resume-execution. Run dforge:finishing-a-development-branch."
check "A5: the resume count is unchanged" "$(resumes s-4)" "$resumes_before"

# --- the document statements: A11 ---
over=""
count=0
for f in "$P"/skills/*/SKILL.md; do
  bytes=$(wc -c < "$f" | tr -d ' \r')
  count=$((count + 1))
  [ "$bytes" -le 20000 ] || over="$over $(basename "$(dirname "$f")"):$bytes"
done
check "A11: every SKILL.md is at most 20000 bytes" "${over:- }" " "
check "A11: skills were found" "$([ "$count" -gt 0 ] && echo yes || echo no)" "yes"
timeout 120 bash "$HERE/skill-size.test.sh" >/dev/null 2>&1; status=$?
check "A11: the skill-size test passes" "$status" "0"

# --- review-package: A8, A9, A10, A14 ---
RP="$S/review-package"
RR="$TMP/rp"
git init -q -b main "$RR"
mkdir -p "$RR/docs/dforge/plans" "$RR/docs/dforge/specs" "$RR/docs/dforge/registers" "$RR/src/deep" "$RR/lib"
printf '# Plan\n\n### Task 1: One\n\nBody.\n' > "$RR/docs/dforge/plans/2026-11-09-demo.md"
printf 'seed\n' > "$RR/src/seed.txt"
printf 'seed\n' > "$RR/lib/seed.txt"
printf 'seed\n' > "$RR/docs/dforge/notes.md"
printf 'seed\n' > "$RR/docs/guide.md"
git -C "$RR" add -A
git -C "$RR" commit -qm base
BASE=$(git -C "$RR" rev-parse HEAD)
PLAN="$RR/docs/dforge/plans/2026-11-09-demo.md"

printf 'code one\n' > "$RR/src/deep/code.js"
printf 'code two\n' > "$RR/lib/code.js"
printf 'spec text\n' > "$RR/docs/dforge/specs/2026-11-09-demo-design.md"
printf '\nplan edit\n' >> "$PLAN"
printf 'row\n' > "$RR/docs/dforge/registers/2026-11-09-demo.md"
git -C "$RR" add -A
git -C "$RR" commit -qm "code and own documents"
C1=$(git -C "$RR" rev-parse HEAD)
rp() { # rp <dir> <out> <base> <head>
  # A real session has no MSYS_NO_PATHCONV; only the script's own prefix may protect the pathspecs.
  (cd "$1" && env -u MSYS_NO_PATHCONV bash "$RP" "$PLAN" "$3" "$4" "$2" >/dev/null 2>"$TMP/rp-stderr")
}
files_section() { awk '/^## Files changed$/ { on = 1; next } /^## Diff$/ { on = 0 } on' "$1"; }
diff_section() { awk '/^## Diff$/ { on = 1; next } on' "$1"; }

rp "$RR" "$TMP/a8.diff" "$BASE" "$C1"; status=$?
check "A8: review-package exits 0" "$status" "0"
files=$(files_section "$TMP/a8.diff")
body=$(diff_section "$TMP/a8.diff")
has "A8: the stat lists src/deep/code.js" "$files" "src/deep/code.js"
has "A8: the stat lists lib/code.js" "$files" "lib/code.js"
has "A8: the diff carries src/deep/code.js" "$body" "diff --git a/src/deep/code.js b/src/deep/code.js"
has "A8: the diff carries lib/code.js" "$body" "diff --git a/lib/code.js b/lib/code.js"
for left in docs/dforge/specs/2026-11-09-demo-design.md docs/dforge/plans/2026-11-09-demo.md docs/dforge/registers/2026-11-09-demo.md; do
  lacks "A8: the diff does not carry $left" "$body" "$left"
  check "A8: the stat does not list $left" "$(grep -F "$left" <<<"$files" | grep -c ' | ')" "0"
  check "A8: one line under Files changed names $left as left out" "$(grep -cF "$left" <<<"$files")" "1"
done

printf 'notes edit\n' >> "$RR/docs/dforge/notes.md"
printf 'guide edit\n' >> "$RR/docs/guide.md"
git -C "$RR" add -A
git -C "$RR" commit -qm "documents outside the three"
printf 'late spec edit\n' >> "$RR/docs/dforge/specs/2026-11-09-demo-design.md"
git -C "$RR" add -A
git -C "$RR" commit -qm "spec only commit"
C3=$(git -C "$RR" rev-parse HEAD)

rp "$RR" "$TMP/a9.diff" "$BASE" "$C3"; status=$?
check "A9: review-package exits 0" "$status" "0"
files=$(files_section "$TMP/a9.diff")
body=$(diff_section "$TMP/a9.diff")
commits=$(awk '/^## Commits$/ { on = 1; next } /^## Files changed$/ { on = 0 } on' "$TMP/a9.diff")
has "A9: the diff keeps docs/dforge/notes.md" "$body" "diff --git a/docs/dforge/notes.md b/docs/dforge/notes.md"
has "A9: the diff keeps docs/guide.md" "$body" "diff --git a/docs/guide.md b/docs/guide.md"
has "A9: the stat lists docs/dforge/notes.md" "$files" "docs/dforge/notes.md"
has "A9: the stat lists docs/guide.md" "$files" "docs/guide.md"
lacks "A9: the diff still leaves out the spec" "$body" "docs/dforge/specs/2026-11-09-demo-design.md"
for subject in "code and own documents" "documents outside the three" "spec only commit"; do
  has "A9: the commit list names '$subject'" "$commits" "$subject"
done
check "A9: the commit list has one line per commit" "$(grep -c . <<<"$commits")" "$(git -C "$RR" rev-list --count "$BASE..$C3")"

printf 'only spec again\n' >> "$RR/docs/dforge/specs/2026-11-09-demo-design.md"
printf 'only register again\n' >> "$RR/docs/dforge/registers/2026-11-09-demo.md"
printf 'only plan again\n' >> "$PLAN"
git -C "$RR" add -A
git -C "$RR" commit -qm "documents only"
D_BASE=$(git -C "$RR" rev-parse HEAD~1)
D_HEAD=$(git -C "$RR" rev-parse HEAD)
rp "$RR" "$TMP/a10.diff" "$D_BASE" "$D_HEAD"; status=$?
check "A10: review-package exits 0" "$status" "0"
files=$(files_section "$TMP/a10.diff")
body=$(diff_section "$TMP/a10.diff")
for doc in docs/dforge/specs/2026-11-09-demo-design.md docs/dforge/registers/2026-11-09-demo.md docs/dforge/plans/2026-11-09-demo.md; do
  has "A10: the diff shows $doc" "$body" "diff --git a/$doc b/$doc"
  check "A10: the stat lists $doc" "$(grep -F "$doc" <<<"$files" | grep -c ' | ')" "1"
done
has "A10: the added text is in the diff" "$body" "+only spec again"

rp "$RR" "$TMP/top.diff" "$BASE" "$C3"
rp "$RR/src/deep" "$TMP/sub.diff" "$BASE" "$C3"; status=$?
check "A14: review-package from a subdirectory exits 0" "$status" "0"
check "A14: the package from a subdirectory equals the one from the top" "$(cmp -s "$TMP/top.diff" "$TMP/sub.diff" && echo same || echo different)" "same"
check "A14: the stat equals" "$(files_section "$TMP/sub.diff")" "$(files_section "$TMP/top.diff")"
check "A14: the diff equals" "$(diff_section "$TMP/sub.diff")" "$(diff_section "$TMP/top.diff")"
has "A14: the subdirectory run still diffs a file outside it" "$(diff_section "$TMP/sub.diff")" "diff --git a/lib/code.js b/lib/code.js"
has "A14: the subdirectory run still diffs a document outside the three" "$(diff_section "$TMP/sub.diff")" "diff --git a/docs/guide.md b/docs/guide.md"
lacks "A14: the subdirectory run still leaves the spec out" "$(diff_section "$TMP/sub.diff")" "docs/dforge/specs/2026-11-09-demo-design.md"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
