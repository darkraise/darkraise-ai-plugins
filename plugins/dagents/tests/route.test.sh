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
has "built epic: the built rows are named" "$NEXT" "Built, awaiting the audit: #1."
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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
