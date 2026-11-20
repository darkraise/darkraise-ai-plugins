#!/usr/bin/env bash
# Acceptance tests for the parallel-session handoff spec: one handoff file per
# piece of work, keyed by the plan, the draft or the session, each with its own
# notes, so sessions running side by side never overwrite each other's. Each
# test name starts with its case name.
set -uo pipefail

PLUGIN=dagents STATE=.dagents DOCS=docs/dagents

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../../plugins/$PLUGIN/scripts"
NS="$SCRIPTS/next-step"

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

TMP="$(mktemp -d)"
export WORKFLOW_GUARD_CLAUDE_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_MANAGED_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_PROJECT_DIR="$TMP/workflow-guard"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
unset CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR AR_SESSION DFORGE_BUDGET DAGENTS_BUDGET CLAUDE_PROJECT_DIR \
  DFORGE_DOCUMENT_STORE DFORGE_PROGRESS_SOURCE DAGENTS_DOCUMENT_STORE DAGENTS_PROGRESS_SOURCE
export DFORGE_NO_SETTINGS=1 DAGENTS_NO_SETTINGS=1 GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

digest() { if command -v sha256sum >/dev/null 2>&1; then sha256sum < "$1"; else shasum -a 256 < "$1"; fi; }

S1=a1111111-0000-0000-0000-000000000001
S2=b2222222-0000-0000-0000-000000000002
S3=c3333333-0000-0000-0000-000000000003
P=2026-11-01-p
n=0
fixture() { # fixture — a fresh repository in $R (path $TOP) holding plan P and draft D
  n=$((n + 1))
  R="$TMP/r$n"
  git init -q -b main "$R"
  D="$R/$DOCS"
  mkdir -p "$D/plans" "$D/specs"
  printf '%s/\n' "$STATE" > "$R/.gitignore"
  printf '# D design\n' > "$D/specs/D.md"
  {
    printf '# P\n\n**Spec:** %s/specs/S.md\n' "$DOCS"
    printf '**Execution:** inline — `claude --model sonnet --effort high` — small\n'
    printf '\n### Task 1: One\n\nBody.\n\n### Task 2: Two\n\nBody.\n'
  } > "$D/plans/$P.md"
  git -C "$R" add -A >/dev/null && git -C "$R" commit -qm init >/dev/null
  TOP=$(git -C "$R" rev-parse --show-toplevel)
  HD="$TOP/$STATE/handoff"
}
notes() { # notes <key> <text> — the notes file the handoff skill writes (C14)
  mkdir -p "$HD/notes"; printf '## Notes\n\n%s\n' "$2" > "$HD/notes/$1.md"
}
ns() { # ns <session> <dir> <args...> — next-step run as <session> in <dir>; sets OUT and RC
  OUT=$(cd "$2" && CLAUDE_CODE_SESSION_ID=$1 timeout 90 bash "$NS" "${@:3}" 2>"$TMP/stderr"); RC=$?
}
files() { local f; for f in "$1"/*; do [ -f "$f" ] && printf '%s ' "${f##*/}"; done; } # files <dir> — its plain files' names
notes_of() { awk '/^## Next session/ { exit } { print }' "$1"; } # notes_of <handoff> — everything above the block
marker_of() { grep -E '^<!-- next-step: ' "$1" | tail -n 1; }

# ---------------------------------------------------------------- base_repo_only
fixture
notes "adhoc-${S1:0:8}" "S1 punch list"
ns "$S1" "$TOP" --adhoc --phase build --next "Finish item C" --notes "$HD/notes/adhoc-${S1:0:8}.md"; rc1=$RC
A="$HD/adhoc-${S1:0:8}.md"
a1=$(digest "$A" 2>/dev/null)
notes D "S2 design notes"
ns "$S2" "$TOP" --draft "$DOCS/specs/D.md" --next "Write the plan with dagents:writing-plans" --notes "$HD/notes/D.md"; rc2=$RC
d1=$(digest "$HD/D.md" 2>/dev/null)
notes "$P" "S3 plan notes"
ns "$S3" "$TOP" "$DOCS/plans/$P.md" --notes "$HD/notes/$P.md"; rc3=$RC
check "base_repo_only: the three runs exit 0" "$rc1 $rc2 $rc3" "0 0 0"
check "base_repo_only: one file per piece of work" "$(files "$HD")" "$P.md D.md adhoc-${S1:0:8}.md "
check "base_repo_only: no latest.md" "$([ -e "$HD/latest.md" ] && echo yes || echo no)" "no"
has "base_repo_only: the adhoc handoff holds S1's notes" "$(cat "$A")" "S1 punch list"
has "base_repo_only: the draft handoff holds S2's notes" "$(cat "$HD/D.md")" "S2 design notes"
has "base_repo_only: the plan handoff holds S3's notes" "$(cat "$HD/$P.md")" "S3 plan notes"
lacks "base_repo_only: the plan handoff holds no one else's notes" "$(cat "$HD/$P.md")" "S2 design notes"
has "base_repo_only: the adhoc marker names its key and session" "$(marker_of "$A")" "kind=adhoc key=adhoc-${S1:0:8} session=$S1 "
has "base_repo_only: the draft marker names its key and session" "$(marker_of "$HD/D.md")" "kind=draft key=D session=$S2 "
has "base_repo_only: the plan marker names its key and session" "$(marker_of "$HD/$P.md")" "kind=plan key=$P session=$S3 "
check "base_repo_only: the adhoc handoff is unchanged by the others" "$(digest "$A")" "$a1"
check "base_repo_only: the draft handoff is unchanged by the plan's" "$(digest "$HD/D.md")" "$d1"
check "base_repo_only: the notes files are gone" "$(ls -A "$HD/notes" | wc -l | tr -d ' ')" "0"
has "base_repo_only: the adhoc block names its own handoff" "$OUT$(cat "$A")" "the notes in \`$A\` are the authority"

# ---------------------------------------------------------------- base_repo_and_worktree
fixture
ns "$S1" "$TOP" --adhoc --phase build --next "Finish item C"
A="$HD/adhoc-${S1:0:8}.md"
a1=$(digest "$A")
git -C "$R" worktree add -q -b p "$TMP/w$n" >/dev/null 2>&1
W=$(git -C "$TMP/w$n" rev-parse --show-toplevel)
mkdir -p "$W/$STATE/sdd/$P"
printf '# SDD ledger — plan: %s/plans/%s.md\nTask 1: complete (commits a..b, review clean)\nTask 2: complete (commits b..c, review clean)\n' "$DOCS" "$P" > "$W/$STATE/sdd/$P/progress.md"
ns "$S3" "$W" --complete "$DOCS/plans/$P.md"
check "base_repo_and_worktree: --complete exits 0" "$RC" "0"
check "base_repo_and_worktree: --complete writes the primary's keyed handoff" "$(grep -c '^## Next session' "$HD/$P.md" 2>/dev/null)" "1"
check "base_repo_and_worktree: the adhoc handoff is byte-identical" "$(digest "$A")" "$a1"
check "base_repo_and_worktree: nothing is written in the worktree" "$(ls "$W/$STATE/handoff" 2>/dev/null | wc -l | tr -d ' ')" "0"

# ---------------------------------------------------------------- interleaved_notes
fixture
K1="adhoc-${S1:0:8}" K2="adhoc-${S2:0:8}"
notes "$K1" "S1 note one"
notes "$K2" "S2 note two"
ns "$S2" "$TOP" --adhoc --phase build --next "Carry on with two" --notes "$HD/notes/$K2.md"; rc2=$RC
ns "$S1" "$TOP" --adhoc --phase design --next "Carry on with one" --notes "$HD/notes/$K1.md"; rc1=$RC
check "interleaved_notes: both runs exit 0" "$rc1 $rc2" "0 0"
has "interleaved_notes: k1 holds S1's notes" "$(notes_of "$HD/$K1.md")" "S1 note one"
lacks "interleaved_notes: k1 holds not S2's" "$(cat "$HD/$K1.md")" "S2 note two"
has "interleaved_notes: k1 holds its own block" "$(cat "$HD/$K1.md")" "**Next:** Carry on with one."
has "interleaved_notes: k2 holds S2's notes" "$(notes_of "$HD/$K2.md")" "S2 note two"
lacks "interleaved_notes: k2 holds not S1's" "$(cat "$HD/$K2.md")" "S1 note one"
has "interleaved_notes: k2 holds its own block" "$(cat "$HD/$K2.md")" "**Next:** Carry on with two."
check "interleaved_notes: both notes files are gone" "$(ls -A "$HD/notes" | wc -l | tr -d ' ')" "0"
notes_of "$HD/$K1.md" > "$TMP/k1-notes"
ns "$S1" "$TOP" --adhoc --phase design --next "Then the last step"
check "interleaved_notes: a run without --notes exits 0" "$RC" "0"
notes_of "$HD/$K1.md" > "$TMP/k1-notes-after"
check "interleaved_notes: and keeps k1's notes byte-identical" "$(digest "$TMP/k1-notes-after")" "$(digest "$TMP/k1-notes")"
has "interleaved_notes: with the new block" "$(cat "$HD/$K1.md")" "**Next:** Then the last step."
check "interleaved_notes: one block" "$(grep -c '^## Next session' "$HD/$K1.md")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
