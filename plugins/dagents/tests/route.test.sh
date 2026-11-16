#!/usr/bin/env bash
# next-step's register router must route a row assigned to a spec by the
# spec's plans: a live plan is executed, a spec with none is planned, a spec
# whose plans are all finished gets a follow-up plan or, for an epic row, the
# milestone audit, and plans of unknown outcome route nowhere.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/next-step"

pass=0 fail=0
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
lacks() { # lacks <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
unset CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

S=docs/dagents/specs/S.md
X=docs/dagents/specs/X.md
n=0
fixture() { # fixture — a fresh repository in $R with $D as its docs root
  n=$((n + 1))
  R="$TMP/r$n"
  git init -q -b main "$R"
  D="$R/docs/dagents"
  mkdir -p "$D/plans" "$D/specs" "$D/registers"
  printf '.dagents/\n' > "$R/.gitignore"
  : > "$R/$S"; : > "$R/$X"
}
plan() { # plan <name> <spec> [program line]
  {
    printf '# %s\n\n**Spec:** %s\n' "$1" "$2"
    printf '**Execution:** inline — `claude --model sonnet --effort high` — small\n'
    [ -z "${3:-}" ] || printf '%s\n' "$3"
    printf '\n### Task 1: One\n\nBody.\n'
  } > "$D/plans/$1.md"
}
completed() { # completed <plan name>... — entries dated 2026-10-01
  { printf '# Completed plans\n\n'
    for p in "$@"; do printf -- '- 2026-10-01 — `docs/dagents/plans/%s.md` — merged\n' "$p"; done
  } > "$D/plans/completed.md"
}
register() { # register <name> <covers> <row>... — rows as "id|item|assigned|state"
  local name=$1 covers=$2 row; shift 2
  { printf '# %s — item register\n\n**Source:** test\n**Covers:** %s\n\n' "$name" "$covers"
    printf '| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n'
    for row in "$@"; do
      IFS='|' read -r id item assigned state <<<"$row"
      printf '| %s | %s | %s | - | %s | - |\n' "$id" "$item" "$assigned" "$state"
    done
  } > "$D/registers/$name.md"
}
roadmap() { # roadmap <register name> — milestone M1 (MVP), open
  { printf '# Shop — roadmap\n\n**Product:** a shop\n**Spec:** docs/dagents/specs/shop.md\n\n'
    printf '| M | Name | Exit criteria | Register | State | Note |\n|---|---|---|---|---|---|\n'
    printf '| M1 | MVP | every epic resolved | docs/dagents/registers/%s.md | open | - |\n' "$1"
  } > "$D/roadmap.md"
  : > "$D/specs/shop.md"
}
complete() { # complete <plan name> — sets OUT, NEXT and PROMPT
  git -C "$R" add -A >/dev/null && git -C "$R" commit -qm fixture >/dev/null
  OUT=$(cd "$R" && timeout 60 bash "$SCRIPT" --complete "docs/dagents/plans/$1.md" 2>&1)
  NEXT=$(grep '^\*\*Next:\*\*' <<<"$OUT")
  PROMPT=$(awk '/^Paste as the first prompt:/ { on = 1; next } on && /^```$/ { if (in_f) exit; in_f = 1; next } in_f' <<<"$OUT")
}

# --- a live plan of the spec takes the row (A1) ---
live_fixture() { # live_fixture <P2 name> [P2 spec] [P2 program line]
  fixture
  plan 2026-09-01-p1 "$X"
  plan "$1" "${2:-$S}" "${3:-}"
  completed 2026-09-01-p1
  register r "$X" "1|Build S|$S|doing"
}
live_fixture 2026-10-05-p2
complete 2026-09-01-p1
has "live plan: the Next line names the live plan" "$NEXT" "Continue \`docs/dagents/plans/2026-10-05-p2.md\` with dagents:executing-plans."
has "live plan: an abandoned plan is named as such" "$NEXT" "If it was abandoned, record it in completed.md or delete it."
lacks "live plan: not sent to writing-plans" "$NEXT" "write its plan"

# --- a spec with no plan still goes to writing-plans (A2) ---
fixture
plan 2026-09-01-p1 "$X"
completed 2026-09-01-p1
register r "$X" "1|Build S|$S|doing"
complete 2026-09-01-p1
has "no plan: the spec is planned" "$NEXT" "\`$S\`: write its plan with dagents:writing-plans."

# --- a built epic row sends the milestone to its audit (A3, C7) ---
built_fixture() {
  fixture
  plan 2026-09-01-p1 "$S"
  completed 2026-09-01-p1
  register e docs/dagents/specs/shop.md "1|Epic S|$S|doing"
  roadmap e
}
built_fixture
complete 2026-09-01-p1
has "built epic: the milestone goes to its audit" "$NEXT" "Built, awaiting the audit: #1. Milestone M1 (MVP) has nothing else open: audit and close it with dagents:closing-a-milestone."
lacks "built epic: not sent to writing-plans" "$NEXT" "write its plan"

# --- a built-only milestone prompt names the built rows (A1 amendment) ---
has "built prompt: the audit prompt names the built rows" "$PROMPT" "with dagents:closing-a-milestone. Built, awaiting the audit: #1."
lacks "built prompt: no empty verify list" "$PROMPT" "(verify): ."

# --- an open requirement row after the last plan asks for a follow-up plan (A4) ---
fixture
plan 2026-09-01-p1 "$S"
completed 2026-09-01-p1
register q "$S" "2|Requirement|$S|open"
complete 2026-09-01-p1
has "follow-up: a finished spec with open rows gets a follow-up plan" "$NEXT" "\`$S\`: write a follow-up plan for rows #2 with dagents:writing-plans."

# --- a Program line counts as naming the spec (A5) ---
live_fixture 2026-10-05-p2 docs/dagents/specs/own.md "**Program:** $S — sub-project 2 of 3 — next: x"
complete 2026-09-01-p1
has "program line: the plan naming S on its Program line is routed" "$NEXT" "Continue \`docs/dagents/plans/2026-10-05-p2.md\` with dagents:executing-plans."

# --- the lower sub-project wins among live plans (A23) ---
fixture
plan 2026-09-01-p1 "$X"
plan 2026-10-03-third "$S" "**Program:** \`$S\` — sub-project 3 of 3 — last"
plan 2026-10-09-second "$S" "**Program:** \`$S\` — sub-project 2 of 3 — next: third"
completed 2026-09-01-p1
register r "$X" "1|Build S|$S|doing"
complete 2026-09-01-p1
has "sub-project: the lower sub-project wins" "$NEXT" "Continue \`docs/dagents/plans/2026-10-09-second.md\`"
fixture
plan 2026-09-01-p1 "$X"
plan 2026-10-09-later "$S"
plan 2026-10-03-earlier "$S"
completed 2026-09-01-p1
register r "$X" "1|Build S|$S|doing"
complete 2026-09-01-p1
has "sub-project: without Program lines the older date wins" "$NEXT" "Continue \`docs/dagents/plans/2026-10-03-earlier.md\`"

# --- unindexed plans are listed as outcome unrecorded (A24) ---
live_fixture 2026-10-05-p2
rm "$D/plans/completed.md"
complete 2026-09-01-p1
has "unrecorded: no completed.md leaves the outcome unrecorded" "$NEXT" "plans exist, outcome unrecorded: #1"
lacks "unrecorded: no completed.md executes nothing" "$NEXT" "executing-plans"
lacks "unrecorded: no completed.md plans nothing" "$NEXT" "write its plan"
live_fixture 2026-10-01-p2
complete 2026-09-01-p1
has "unrecorded: a plan dated the index's first entry is not older" "$NEXT" "Continue \`docs/dagents/plans/2026-10-01-p2.md\` with dagents:executing-plans."
live_fixture 2026-09-15-p2
complete 2026-09-01-p1
has "unrecorded: a plan older than completed.md is unrecorded" "$NEXT" "plans exist, outcome unrecorded: #1"
lacks "unrecorded: an older plan executes nothing" "$NEXT" "executing-plans"
lacks "unrecorded: an older plan plans nothing" "$NEXT" "write its plan"

# --- the plan being completed counts as finished ---
fixture
plan 2026-10-05-p1 "$S"
completed 2026-09-01-other
register q "$S" "2|Requirement|$S|open"
complete 2026-10-05-p1
has "completing: the completing plan's spec gets a follow-up plan" "$NEXT" "\`$S\`: write a follow-up plan for rows #2 with dagents:writing-plans."
lacks "completing: the completing plan is not routed" "$NEXT" "2026-10-05-p1"
lacks "completing: the spec is not planned afresh" "$NEXT" "write its plan"
fixture
plan 2026-10-05-p1 "$S"
completed 2026-09-01-other
register e docs/dagents/specs/shop.md "1|Epic S|$S|doing"
roadmap e
complete 2026-10-05-p1
has "completing: the completing plan's epic is built" "$NEXT" "Built, awaiting the audit: #1."
lacks "completing: the completing plan is not routed to" "$NEXT" "2026-10-05-p1"
lacks "completing: the epic's spec is not planned afresh" "$NEXT" "write its plan"

# --- built rows without a roadmap fall through to the plan's own next step (spec §1 rule 4) ---
fixture
plan 2026-09-01-p0 "$S"
plan 2026-10-05-p1 "$X"
completed 2026-09-01-p0
register r "$X" "1|Epic S|$S|doing"
complete 2026-10-05-p1
has "no roadmap: built rows fall through to the Program-line branches" "$NEXT" "**Next:** Nothing — the plan records no follow-on work."
lacks "no roadmap: built rows are not listed as open" "$NEXT" "Register rows still open"
lacks "no roadmap: built rows are not planned afresh" "$NEXT" "write its plan"

# --- built rows under a roadmap whose milestones are all closed: no audit awaits them ---
fixture
plan 2026-09-01-p0 "$S"
plan 2026-10-05-p1 "$X"
completed 2026-09-01-p0
register r "$X" "1|Epic S|$S|doing"
roadmap r
sed -i.bak 's/| open | - |$/| closed | - |/' "$D/roadmap.md" && rm -f "$D/roadmap.md.bak"
complete 2026-10-05-p1
has "closed roadmap: built rows read as nothing open" "$NEXT" "**Next:** Nothing — every milestone in \`docs/dagents/roadmap.md\` is closed."
lacks "closed roadmap: built rows are not listed without an action" "$NEXT" "Register rows still open"

# --- a plan row resumes a worktree ledger ---
fixture
plan 2026-09-01-p1 "$X"
plan 2026-10-05-live "$X"
completed 2026-09-01-p1
register r "$X" "1|Do it|docs/dagents/plans/2026-10-05-live.md|doing"
git -C "$R" add -A >/dev/null && git -C "$R" commit -qm fixture >/dev/null
git -C "$R" worktree add -q "$TMP/wt$n" -b feat
mkdir -p "$TMP/wt$n/.dagents/sdd/2026-10-05-live"
printf '# SDD ledger — plan: docs/dagents/plans/2026-10-05-live.md\nTask 1: implementer inline (assigned; base abc1234)\n' \
  > "$TMP/wt$n/.dagents/sdd/2026-10-05-live/progress.md"
complete 2026-09-01-p1
has "worktree ledger: the plan row resumes" "$NEXT" "Resume \`docs/dagents/plans/2026-10-05-live.md\` with dagents:resume-execution."

project() { # project [args...] — run next-step --project in $R; sets OUT, NEXT, STATUS
  git -C "$R" add -A >/dev/null && git -C "$R" commit -qm fixture >/dev/null
  OUT=$(cd "$R" && timeout 60 bash "$SCRIPT" "$@" 2>&1)
  NEXT=$(grep '^\*\*Next:\*\*' <<<"$OUT")
  STATUS=$(grep '^\*\*Status:\*\*' <<<"$OUT")
}

# --- --project with only built rows and no milestone has nothing open ---
fixture
plan 2026-09-01-p1 "$S"
completed 2026-09-01-p1
register r "$X" "1|Build S|$S|doing"
project --print --project
has "project built only: no roadmap means nothing open" "$NEXT" "**Next:** Nothing — no register holds an unresolved row."
lacks "project built only: no row list without an action" "$NEXT" "Register rows still open"

# --- --project audits a milestone of verify or built rows ---
built_fixture
register e docs/dagents/specs/shop.md "1|Epic S|$S|doing" "2|Other|-|verify"
project --print --project
has "project milestone: the current milestone is named" "$STATUS" "**Status:** Project: milestone M1 (MVP) is current."
has "project milestone: the C7 audit line" "$NEXT" "Awaiting your check (verify): #2. Built, awaiting the audit: #1. Milestone M1 (MVP) has nothing else open: audit and close it with dagents:closing-a-milestone."
has "project milestone: the audit launches" "$OUT" "Paste as the first prompt:"

# --- --project with nothing open and no roadmap prints Nothing ---
fixture
register r "$X" "1|Done|-|done"
project --print --project
has "project nothing: no roadmap" "$STATUS" "**Status:** Project: no roadmap."
has "project nothing: the Nothing line" "$NEXT" "**Next:** Nothing — no register holds an unresolved row."
lacks "project nothing: launches nothing" "$OUT" "Paste as the first prompt:"

# --- --project with every milestone closed scans every register ---
built_fixture
register e docs/dagents/specs/shop.md "1|Epic S|$S|done"
sed -i.bak 's/| open | - |$/| closed | audit |/' "$D/roadmap.md" && rm -f "$D/roadmap.md.bak"
register other "$X" "1|Search|Search|open"
project --print --project
has "project closed: every milestone is closed" "$STATUS" "**Status:** Project: every milestone is closed."
has "project closed: a register outside the milestones routes" "$NEXT" "\`Search\`: write its spec in a fresh session."

# --- --project replaces latest.md unless told to keep notes ---
fixture
register r "$X" "1|Search|Search|open"
LATEST="$R/.dagents/handoff/latest.md"
mkdir -p "$(dirname "$LATEST")"
printf '# Handoff\n\n## State\n\nold notes\n\n## Next session\n\nOld block.\n' > "$LATEST"
project --project
lacks "project write: the notes are replaced" "$(cat "$LATEST")" "## State"
has "project write: the marker names the project" "$(grep '^<!-- next-step:' "$LATEST")" "kind=project done=0 closed=0 subject=- at="
awk '/^## Next session/ { print "## State"; print ""; print "kept notes"; print "" } { print }' "$LATEST" > "$LATEST.new" && mv "$LATEST.new" "$LATEST"
project --project --keep-notes
kept=$(cat "$LATEST")
has "project keep-notes: the notes survive" "$kept" "kept notes"
check_above=$(awk '/^kept notes$/ { n = NR } /^## Next session/ { b = NR } END { print (n && b && n < b) ? "above" : "not above" }' "$LATEST")
has "project keep-notes: the notes sit above the block" "$check_above" "above"
has "project keep-notes: the marker names the project" "$(grep '^<!-- next-step:' "$LATEST")" "kind=project done=0 closed=0 subject=- at="

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
