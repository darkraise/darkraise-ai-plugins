#!/usr/bin/env bash
# Acceptance tests for the parallel-session handoff spec: one handoff file per
# piece of work, keyed by the plan, the draft or the session, each with its own
# notes, so sessions running side by side never overwrite each other's. Each
# test name starts with its case name.
set -uo pipefail

PLUGIN=dforge STATE=.dforge DOCS=docs/dforge

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
files() { local f; for f in "$1"/*; do [ -f "$f" ] && printf '%s\n' "${f##*/}"; done | LC_ALL=C sort | tr '\n' ' '; } # files <dir> — its plain files' names, in C order
notes_of() { awk '/^## Next session/ { exit } { print }' "$1"; } # notes_of <handoff> — everything above the block
marker_of() { grep -E '^<!-- next-step: ' "$1" | tail -n 1; }

# ---------------------------------------------------------------- base_repo_only
fixture
notes "adhoc-${S1:0:8}" "S1 punch list"
ns "$S1" "$TOP" --adhoc --phase build --next "Finish item C" --notes "$HD/notes/adhoc-${S1:0:8}.md"; rc1=$RC
A="$HD/adhoc-${S1:0:8}.md"
a1=$(digest "$A" 2>/dev/null)
notes D "S2 design notes"
ns "$S2" "$TOP" --draft "$DOCS/specs/D.md" --next "Write the plan with dforge:writing-plans" --notes "$HD/notes/D.md"; rc2=$RC
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
# A next sub-project keeps the --complete block from being terminal (printed, not written).
SPEC_DIR=$DOCS awk '{ print } /^\*\*Spec:\*\*/ { print "**Program:** `" ENVIRON["SPEC_DIR"] "/specs/S.md` — sub-project 1 of 2 — next: Two" }' \
  "$W/$DOCS/plans/$P.md" > "$TMP/plan" && mv "$TMP/plan" "$W/$DOCS/plans/$P.md"
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

H="$SCRIPTS/handoff"
beat() { # beat <session> — the heartbeat a live cockpit writes
  local f
  f="$HOME/.claude/$PLUGIN/sessions/cockpit/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
  mkdir -p "${f%/*}"; date +%s > "$f"
}
claim() { # claim <session> <dir> <file> — handoff claim as <session> in <dir>; sets OUT and RC
  OUT=$(cd "$2" && CLAUDE_CODE_SESSION_ID=$1 timeout 30 bash "$H" claim "$3" 2>&1); RC=$?
}
exists() { if [ -e "$1" ]; then echo yes; else echo no; fi; }
worktree() { # worktree — a linked worktree in $W on branch p whose ledger has Task 1 complete
  git -C "$R" worktree add -q -b p "$TMP/w$n" >/dev/null 2>&1
  W=$(git -C "$TMP/w$n" rev-parse --show-toplevel)
  mkdir -p "$W/$STATE/sdd/$P"
  printf '# SDD ledger — plan: %s/plans/%s.md\nTask 1: complete (commits a..b, review clean)\n' "$DOCS" "$P" > "$W/$STATE/sdd/$P/progress.md"
}

# ---------------------------------------------------------------- held_claim_refuses_write
fixture
ns "$S2" "$TOP" --draft "$DOCS/specs/D.md" --next "Write the plan"
beat "$S2"
claim "$S2" "$TOP" "$HD/D.md"
check "held_claim_refuses_write: S2 claims D" "$RC $OUT" "0 claimed D"
d1=$(digest "$HD/D.md")
notes D "S3 design notes"
n1=$(digest "$HD/notes/D.md")
ns "$S3" "$TOP" --draft "$DOCS/specs/D.md" --next "Write the plan" --notes "$HD/notes/D.md"
check "held_claim_refuses_write: the write exits 7" "$RC" "7"
has "held_claim_refuses_write: it names the holder and the claim's age" "$OUT" "next-step: handoff D is held by ${S2:0:8} (live, claimed "
has "held_claim_refuses_write: on stderr too" "$(cat "$TMP/stderr")" "next-step: handoff D is held by ${S2:0:8} (live, claimed "
lacks "held_claim_refuses_write: it prints no block" "$OUT" "## Next session"
check "held_claim_refuses_write: the handoff is byte-identical" "$(digest "$HD/D.md")" "$d1"
check "held_claim_refuses_write: the notes file is byte-identical" "$(digest "$HD/notes/D.md")" "$n1"
ns "$S3" "$TOP" --target --draft "$DOCS/specs/D.md" --next "Write the plan"
check "held_claim_refuses_write: --target exits 7" "$RC" "7"
has "held_claim_refuses_write: --target names the holder" "$OUT" "next-step: handoff D is held by ${S2:0:8} (live, claimed "
beat "$S3"
(cd "$TOP" && timeout 30 bash "$SCRIPTS/auto-run" --session "$S3" start --spec "$DOCS/specs/D.md" --isolation in-place > /dev/null 2>&1)
check "held_claim_refuses_write: S3's auto run is active" "$(cd "$TOP" && timeout 30 bash "$SCRIPTS/auto-run" --session "$S3" status > /dev/null 2>&1; echo $?)" "0"
ns "$S3" "$TOP" --draft "$DOCS/specs/D.md" --next "Write the plan"
check "held_claim_refuses_write: in an auto run the write still exits 7" "$RC" "7"
check "held_claim_refuses_write: and stops S3's run first" "$(jq -r '.active' "$TOP/$STATE/sdd/auto-run.json")" "false"
check "held_claim_refuses_write: naming the key and the holder" "$(jq -r '.stopped // empty' "$TOP/$STATE/sdd/auto-run.json")" "handoff D is held by ${S2:0:8}"
check "held_claim_refuses_write: the claim is still S2's" "$(sed -n 1p "$HD/claims/D")" "session=$S2"
# A stop that cannot take the run's lock is said, not swallowed.
(cd "$TOP" && timeout 30 bash "$SCRIPTS/auto-run" --session "$S3" start --spec "$DOCS/specs/D.md" --isolation in-place --force > /dev/null 2>&1)
sleep 30 & holder=$!
LOCKD="$TOP/$STATE/sdd/auto-run.json.lockd"
mkdir "$LOCKD" && printf '%s\n' "$holder" > "$LOCKD/pid" && uname -n > "$LOCKD/host"
DFORGE_FLOCK=no-such-flock DR_LOCK_TENTHS=5 ns "$S3" "$TOP" --draft "$DOCS/specs/D.md" --next "Write the plan"
kill "$holder"; wait "$holder" 2>/dev/null; rm -f "$LOCKD/pid" "$LOCKD/host"; rmdir "$LOCKD"
check "held_claim_refuses_write: with the run's lock held, the write still exits 7" "$RC" "7"
check "held_claim_refuses_write: and says the stop failed" "$(grep -c '^next-step: auto-run stop failed (status [0-9]*); the run is still active$' "$TMP/stderr")" "1"
check "held_claim_refuses_write: the run is still active" "$(jq -r '.active' "$TOP/$STATE/sdd/auto-run.json")" "true"
ns "$S2" "$TOP" --draft "$DOCS/specs/D.md" --next "Write the plan"
check "held_claim_refuses_write: the holder itself writes" "$RC" "0"
check "held_claim_refuses_write: and so releases its claim" "$(exists "$HD/claims/D")" "no"

# ---------------------------------------------------------------- consume_and_supersede
fixture
A="$HD/adhoc-${S1:0:8}.md"
ns "$S1" "$TOP" --adhoc --phase build --next "Finish item C"
claim "$S2" "$TOP" "$A"
notes D "S2 design notes"
ns "$S2" "$TOP" --draft "$DOCS/specs/D.md" --next "Write the plan" --notes "$HD/notes/D.md"
check "consume_and_supersede: the draft write exits 0" "$RC" "0"
has "consume_and_supersede: the draft handoff is written" "$(cat "$HD/D.md" 2>/dev/null)" "S2 design notes"
check "consume_and_supersede: the claimed adhoc handoff is consumed" "$(exists "$A")" "no"
check "consume_and_supersede: with its claim" "$(exists "$HD/claims/adhoc-${S1:0:8}")" "no"
has "consume_and_supersede: stderr names the consumed path" "$(cat "$TMP/stderr")" "next-step: consumed $A (claimed by this session)"
ns "$S1" "$TOP" --adhoc --phase build --next "Finish item C"
claim "$S2" "$TOP" "$A"
ns "$S2" "$TOP" --draft "$DOCS/specs/D.md" --next "Write the plan"
check "consume_and_supersede: without --notes the run exits 0" "$RC" "0"
check "consume_and_supersede: and keeps the adhoc handoff" "$(exists "$A")" "yes"
check "consume_and_supersede: and releases its claim" "$(exists "$HD/claims/adhoc-${S1:0:8}")" "no"
has "consume_and_supersede: stderr names the kept path" "$(cat "$TMP/stderr")" "next-step: kept $A (released)"
printf '# D1 design\n' > "$D/specs/D1-design.md"
ns "$S3" "$TOP" "$DOCS/plans/$P.md"
ns "$S3" "$TOP" --draft "$DOCS/specs/D1-design.md" --next "Write the plan"
claim "$S2" "$TOP" "$HD/$P.md"
claim "$S2" "$TOP" "$HD/D1-design.md"
notes "adhoc-${S2:0:8}" "S2 punch list"
ns "$S2" "$TOP" --adhoc --phase build --next "Go on" --notes "$HD/notes/adhoc-${S2:0:8}.md"
check "consume_and_supersede: the adhoc write with --notes exits 0" "$RC" "0"
check "consume_and_supersede: an unfinished plan's handoff is kept" "$(exists "$HD/$P.md")" "yes"
check "consume_and_supersede: a live draft's handoff is kept" "$(exists "$HD/D1-design.md")" "yes"
check "consume_and_supersede: both claims are released" "$(exists "$HD/claims/$P") $(exists "$HD/claims/D1-design")" "no no"
has "consume_and_supersede: stderr names the kept plan handoff" "$(cat "$TMP/stderr")" "next-step: kept $HD/$P.md (released)"
has "consume_and_supersede: stderr names the kept draft handoff" "$(cat "$TMP/stderr")" "next-step: kept $HD/D1-design.md (released)"
worktree
ns "$S3" "$W" "$DOCS/plans/$P.md"
check "consume_and_supersede: the executor's handoff from W exits 0" "$RC" "0"
check "consume_and_supersede: W's handoff is written" "$(exists "$W/$STATE/handoff/$P.md")" "yes"
check "consume_and_supersede: the primary's copy is superseded" "$(exists "$HD/$P.md")" "no"
has "consume_and_supersede: stderr names the superseded path" "$(cat "$TMP/stderr")" "next-step: superseded $HD/$P.md"
beat "$S3"
claim "$S3" "$W" "$W/$STATE/handoff/$P.md"
claim "$S1" "$TOP" "$W/$STATE/handoff/$P.md"
check "consume_and_supersede: a primary session's claim on W's live-claimed P exits 3" "$RC" "3"

# ---------------------------------------------------------------- terminal_blocks
fixture
ns "$S3" "$TOP" "$DOCS/plans/$P.md"
worktree
mkdir -p "$W/$STATE/handoff"
cp "$HD/$P.md" "$W/$STATE/handoff/$P.md"
claim "$S3" "$TOP" "$HD/$P.md"
notes "$P" "Last words"
ns "$S3" "$W" --complete "$DOCS/plans/$P.md" --notes "$HD/notes/$P.md"
check "terminal_blocks: the terminal --complete run exits 0" "$RC" "0"
has "terminal_blocks: it prints the terminal block" "$OUT" "**Next:** Nothing — the plan records no follow-on work."
check "terminal_blocks: no copy of P remains" "$(exists "$HD/$P.md") $(exists "$W/$STATE/handoff/$P.md")" "no no"
check "terminal_blocks: the claim is released" "$(exists "$HD/claims/$P")" "no"
check "terminal_blocks: the notes file is deleted" "$(exists "$HD/notes/$P.md")" "no"
has "terminal_blocks: stderr says so" "$(cat "$TMP/stderr")" "next-step: deleted notes $HD/notes/$P.md (terminal block)"
A="$HD/adhoc-${S1:0:8}.md"
ns "$S1" "$TOP" --adhoc --phase build --next "Finish item C"
a1=$(digest "$A")
ns "$S1" "$TOP" --project
check "terminal_blocks: the terminal --project run exits 0" "$RC" "0"
has "terminal_blocks: it prints the terminal block" "$OUT" "**Next:** Nothing — no register holds an unresolved row."
check "terminal_blocks: the session's adhoc handoff is byte-identical" "$(digest "$A")" "$a1"
mkdir -p "$TOP/$STATE/sdd/$P"
printf '# SDD ledger — plan: %s/plans/%s.md\nTask 1: BLOCKED — ruling seat — choose the storage format\n' "$DOCS" "$P" > "$TOP/$STATE/sdd/$P/progress.md"
ns "$S3" "$TOP" "$DOCS/plans/$P.md"
check "terminal_blocks: a BLOCKED plan's run exits 0" "$RC" "0"
has "terminal_blocks: its block is written" "$(cat "$HD/$P.md" 2>/dev/null)" "Task 1 is BLOCKED"

# ---------------------------------------------------------------- first_prompt_claims
fixture
claims_its_handoff() { # claims_its_handoff NAME FILE — OUT's first prompt names FILE as its handoff and claims that file
  has "$1 names its handoff" "$OUT" "its handoff is \`$2\`."
  has "$1 claims it" "$OUT" "Before anything else, claim it with dforge's \`scripts/handoff claim\` on that file."
}
ns "$S1" "$TOP" --target "$DOCS/plans/$P.md"; T=$OUT
ns "$S1" "$TOP" --print "$DOCS/plans/$P.md"
claims_its_handoff "first_prompt_claims: a plan's prompt" "$T"
ns "$S1" "$TOP" --print --kept "$DOCS/plans/$P.md"
claims_its_handoff "first_prompt_claims: a kept plan's prompt" "$T"
ns "$S1" "$TOP" --target --draft "$DOCS/specs/D.md" --next "Write the plan"; T=$OUT
ns "$S1" "$TOP" --print --draft "$DOCS/specs/D.md" --next "Write the plan"
claims_its_handoff "first_prompt_claims: a draft's prompt" "$T"
ns "$S1" "$TOP" --target --adhoc --phase build --next "Finish item C"; T=$OUT
ns "$S1" "$TOP" --adhoc --phase build --next "Finish item C"
claims_its_handoff "first_prompt_claims: an adhoc prompt" "$T"
ns "$S1" "$TOP" --print --handoff "$T"
claims_its_handoff "first_prompt_claims: a recomputed prompt" "$T"
ns "" "$TOP" --host codex --print --draft "$DOCS/specs/D.md" --next "Write the plan"
lacks "first_prompt_claims: a Codex draft prompt has no claim clause" "$OUT" "scripts/handoff claim"
ns "" "$TOP" --host codex --print --adhoc --phase build --next "Finish item C"
lacks "first_prompt_claims: nor a Codex adhoc prompt" "$OUT" "scripts/handoff claim"
k=$(grep -o 'adhoc-[0-9a-f]\{8\}\.md' <<<"$OUT" | head -n 1)
check "first_prompt_claims: a Codex adhoc prompt names an adhoc handoff" "$([ -n "$k" ] && echo named)" "named"
has "first_prompt_claims: and the key to pass" "$OUT" "When you hand off, pass \`--key ${k%.md}\` to next-step."

# ---------------------------------------------------------------- turn_record_written
fixture
TR="$HOME/.claude/$PLUGIN/sessions/turns"
rec() { printf '%s/%s.next' "$TR" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"; }
ns "$S1" "$TOP" --adhoc --phase build --next "Finish item C"
check "turn_record_written: after a write, the block's Status and Next" "$(cat "$(rec "$S1")" 2>/dev/null)" \
  "status=$(sed -n 's/^\*\*Status:\*\* //p' <<<"$OUT")
next=Finish item C."
ns "$S1" "$TOP" --project
check "turn_record_written: after a terminal run, its Next" "$(sed -n 2p "$(rec "$S1")" 2>/dev/null)" "next=Nothing — no register holds an unresolved row."
rm -rf "$TR"
ns "" "$TOP" --adhoc --phase build --next "Finish item C" --key adhoc-0123abcd
check "turn_record_written: a write without a session id exits 0" "$RC" "0"
ns "$S2" "$TOP" --print --adhoc --phase build --next "Finish item C"
ns "$S2" "$TOP" --target --adhoc --phase build --next "Finish item C"
check "turn_record_written: no record without a session id, nor for --print or --target" "$(ls -A "$TR" 2>/dev/null | wc -l | tr -d ' ')" "0"

# ---------------------------------------------------------------- adhoc_never_superseded
fixture
worktree
A="$HD/adhoc-${S1:0:8}.md"
notes "adhoc-${S1:0:8}" "S1 primary notes"
ns "$S1" "$TOP" --adhoc --phase build --next "Finish item C" --notes "$HD/notes/adhoc-${S1:0:8}.md"
a1=$(digest "$A")
ns "$S1" "$W" --adhoc --phase build --next "Go on in the worktree"
check "adhoc_never_superseded: the worktree write exits 0" "$RC" "0"
check "adhoc_never_superseded: it writes the worktree's adhoc handoff" "$(exists "$W/$STATE/handoff/adhoc-${S1:0:8}.md")" "yes"
check "adhoc_never_superseded: the primary's, with its notes, is byte-identical" "$(digest "$A")" "$a1"
lacks "adhoc_never_superseded: nothing is superseded" "$(cat "$TMP/stderr")" "superseded"

# ---------------------------------------------------------------- claims_lock_not_had
if command -v flock > /dev/null 2>&1; then
  fixture
  mkdir -p "$HD/claims"
  exec 8>> "$HD/claims/.lock"
  flock 8
  OUT=$(cd "$TOP" && CLAUDE_CODE_SESSION_ID=$S1 DR_LOCK_TENTHS=1 timeout 90 bash "$NS" --adhoc --phase build --next "Finish item C" 2>"$TMP/stderr"); RC=$?
  exec 8>&-
  check "claims_lock_not_had: exits 4" "$RC" "4"
  check "claims_lock_not_had: the block is printed once" "$(grep -c '^## Next session' <<<"$OUT")" "1"
  has "claims_lock_not_had: it names the lock as the cause" "$OUT" "(the claims lock in $HD/claims was not had)"
  check "claims_lock_not_had: nothing is written" "$(exists "$HD/adhoc-${S1:0:8}.md")" "no"
  check "claims_lock_not_had: the turn record is written" "$(sed -n 2p "$HOME/.claude/$PLUGIN/sessions/turns/$(printf '%s' "$S1" | tr -c 'A-Za-z0-9' '-').next")" "next=Finish item C."
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
