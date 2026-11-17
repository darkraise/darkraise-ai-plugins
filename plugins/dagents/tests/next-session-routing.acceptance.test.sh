#!/usr/bin/env bash
# Acceptance tests for the next-session routing spec, written from the spec's
# Acceptance section: the register router, next-step's modes and marker, the
# repo-audit Handoff section, the Stop hook's transition rules and the roadmap
# close path. Each test name starts with its statement id.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../scripts"
NS="$SCRIPTS/next-step"
RM="$SCRIPTS/roadmap"
REG="$SCRIPTS/register"
AR="$SCRIPTS/auto-run"
AUDIT="$SCRIPTS/repo-audit"
START="$SCRIPTS/turn-start.sh"
END="$SCRIPTS/turn-end.sh"

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
unset CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR AR_SESSION DAGENTS_BUDGET CLAUDE_PROJECT_DIR
export DAGENTS_NO_SETTINGS=1 GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }
digest() { if command -v sha256sum >/dev/null 2>&1; then sha256sum < "$1"; else shasum -a 256 < "$1"; fi; }
commit_all() { git -C "$1" add -A >/dev/null && git -C "$1" commit -qm "${2:-fixture}" >/dev/null; }

# ---------------------------------------------------------------- fixtures
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
plan() { # plan <name> <spec> [extra header line] [tasks]
  local i
  {
    printf '# %s\n\n**Spec:** %s\n' "$1" "$2"
    printf '**Execution:** inline — `claude --model sonnet --effort high` — small\n'
    [ -z "${3:-}" ] || printf '%s\n' "$3"
    printf '\n'
    for i in $(seq 1 "${4:-1}"); do printf '### Task %s: Step %s\n\nBody.\n\n' "$i" "$i"; done
  } > "$D/plans/$1.md"
}
completed() { # completed <plan name>... — entries dated 2026-09-01
  { printf '# Completed plans\n\n'
    local p
    for p in "$@"; do printf -- '- 2026-09-01 — `docs/dagents/plans/%s.md` — merged\n' "$p"; done
  } > "$D/plans/completed.md"
}
register() { # register <name> <covers> <row>... — rows as "id|item|assigned|state"
  local name=$1 covers=$2 row id item assigned state; shift 2
  { printf '# %s — item register\n\n**Source:** test\n**Covers:** %s\n\n' "$name" "$covers"
    printf '| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n'
    for row in "$@"; do
      IFS='|' read -r id item assigned state <<<"$row"
      printf '| %s | %s | %s | - | %s | - |\n' "$id" "$item" "$assigned" "$state"
    done
  } > "$D/registers/$name.md"
}
roadmap() { # roadmap <register name>... — M1 (MVP) open on the first register; the rest closed first
  { printf '# Shop — roadmap\n\n**Product:** a shop\n**Spec:** docs/dagents/specs/shop.md\n\n'
    printf '| M | Name | Exit criteria | Register | State | Note |\n|---|---|---|---|---|---|\n'
    printf '| M1 | MVP | every epic resolved | docs/dagents/registers/%s.md | open | - |\n' "$1"
  } > "$D/roadmap.md"
  : > "$D/specs/shop.md"
}
ns() { # ns <args...> — run next-step in $R; sets OUT, NEXT, STATUS, PROMPT, RC
  commit_all "$R" >/dev/null 2>&1 || true
  OUT=$(cd "$R" && timeout 90 bash "$NS" "$@" 2>&1); RC=$?
  NEXT=$(grep '^\*\*Next:\*\*' <<<"$OUT")
  STATUS=$(grep '^\*\*Status:\*\*' <<<"$OUT")
  PROMPT=$(awk '/^Paste as the first prompt:/ { on = 1; next } on && /^```$/ { if (f) exit; f = 1; next } f' <<<"$OUT")
}

# ---------------------------------------------------------------- A1
# A plan naming S that is not indexed takes the row, in both modes.
fixture
plan 2026-09-01-p1 "$X"
plan 2026-10-05-p2 "$S"
completed 2026-09-01-p1
register r "$X" "1|Build S|$S|doing"
ns --complete docs/dagents/plans/2026-09-01-p1.md
check "A1: --complete exits 0" "$RC" 0
has "A1: --complete routes to the live plan" "$NEXT" "docs/dagents/plans/2026-10-05-p2.md"
lacks "A1: --complete never says write its plan" "$OUT" "write its plan"
ns --project
check "A1: --project exits 0" "$RC" 0
has "A1: --project routes to the live plan" "$NEXT" "docs/dagents/plans/2026-10-05-p2.md"
lacks "A1: --project never says write its plan" "$OUT" "write its plan"
lacks "A1: --project does not send the spec to writing-plans" "$NEXT" "dagents:writing-plans"

# ---------------------------------------------------------------- A2
fixture
plan 2026-09-01-p1 "$X"
completed 2026-09-01-p1
register r "$X" "1|Build S|$S|doing"
ns --complete docs/dagents/plans/2026-09-01-p1.md
has "A2: a spec with no plan routes to writing-plans" "$NEXT" "dagents:writing-plans"
has "A2: the spec is named" "$NEXT" "$S"
ns --project
has "A2: --project routes the spec to writing-plans too" "$NEXT" "dagents:writing-plans"

# ---------------------------------------------------------------- A3
fixture
plan 2026-09-01-p1 "$S"
completed 2026-09-01-p1
register e docs/dagents/specs/shop.md "1|Epic S|$S|doing"
roadmap e
ns --complete docs/dagents/plans/2026-09-01-p1.md
has "A3: --complete routes to closing the milestone" "$NEXT" "dagents:closing-a-milestone"
has "A3: the milestone is named" "$NEXT" "M1"
lacks "A3: not to writing-plans" "$NEXT" "dagents:writing-plans"
ns --project
has "A3: --project routes to closing the milestone" "$NEXT" "dagents:closing-a-milestone"
lacks "A3: --project not to writing-plans" "$NEXT" "dagents:writing-plans"

# ---------------------------------------------------------------- A4
fixture
plan 2026-09-01-p1 "$S"
completed 2026-09-01-p1
register q "$S" "2|First requirement|$S|open" "5|Second requirement|$S|open"
ns --complete docs/dagents/plans/2026-09-01-p1.md
has "A4: a follow-up plan is asked for the open rows' ids" "$NEXT" "\`$S\`: write a follow-up plan for rows #2, #5 with dagents:writing-plans."
ns --project
has "A4: --project asks for the same follow-up plan" "$NEXT" "write a follow-up plan for rows #2, #5 with dagents:writing-plans."

# ---------------------------------------------------------------- A5
fixture
plan 2026-09-01-p1 "$X"
plan 2026-10-05-p2 "$X" "**Program:** $S — sub-project 2 of 3 — next: x"
completed 2026-09-01-p1
register r "$X" "1|Build S|$S|doing"
ns --complete docs/dagents/plans/2026-09-01-p1.md
has "A5: a plan naming S on its Program line is routed to" "$NEXT" "docs/dagents/plans/2026-10-05-p2.md"
lacks "A5: S is not planned afresh while its Program plan is live" "$NEXT" "write its plan"
fixture
plan 2026-09-01-p1 "$X" "**Program:** $S — sub-project 1 of 1 — last"
completed 2026-09-01-p1
register q "$S" "3|Requirement|$S|open"
ns --complete docs/dagents/plans/2026-09-01-p1.md
has "A5: a finished Program plan counts as a plan of S" "$NEXT" "\`$S\`: write a follow-up plan for rows #3 with dagents:writing-plans."
lacks "A5: a finished Program plan is not no plan" "$NEXT" "write its plan"

# ---------------------------------------------------------------- A23
fixture
plan 2026-09-01-p1 "$X"
plan 2026-10-03-third "$S" "**Program:** \`$S\` — sub-project 3 of 3 — last"
plan 2026-10-09-second "$S" "**Program:** \`$S\` — sub-project 2 of 3 — next: third"
completed 2026-09-01-p1
register r "$X" "1|Build S|$S|doing"
ns --complete docs/dagents/plans/2026-09-01-p1.md
has "A23: the lower sub-project is picked, though it is the newer file" "$NEXT" "docs/dagents/plans/2026-10-09-second.md"
lacks "A23: the higher sub-project is not picked" "$NEXT" "2026-10-03-third"
fixture
plan 2026-09-01-p1 "$X"
plan 2026-10-09-later "$S"
plan 2026-10-03-earlier "$S"
completed 2026-09-01-p1
register r "$X" "1|Build S|$S|doing"
ns --complete docs/dagents/plans/2026-09-01-p1.md
has "A23: with no Program lines the older filename date is picked" "$NEXT" "docs/dagents/plans/2026-10-03-earlier.md"
lacks "A23: the later date is not picked" "$NEXT" "2026-10-09-later"

# ---------------------------------------------------------------- A24
fixture
plan 2026-09-01-p1 "$X"
plan 2026-10-05-p2 "$S"
register r "$X" "1|Build S|$S|doing"
ns --complete docs/dagents/plans/2026-09-01-p1.md
has "A24: without completed.md the row is listed outcome unrecorded" "$NEXT" "plans exist, outcome unrecorded"
lacks "A24: without completed.md nothing is executed" "$NEXT" "executing-plans"
lacks "A24: without completed.md nothing is sent to writing-plans" "$NEXT" "writing-plans"
lacks "A24: without completed.md the plan is not named as the next step" "$NEXT" "2026-10-05-p2.md"
fixture
plan 2026-09-01-p1 "$X"
plan 2026-08-15-p2 "$S"
completed 2026-09-01-p1
register r "$X" "1|Build S|$S|doing"
ns --complete docs/dagents/plans/2026-09-01-p1.md
has "A24: a plan dated before the first entry is outcome unrecorded" "$NEXT" "plans exist, outcome unrecorded"
lacks "A24: a plan older than the index is not executed" "$NEXT" "executing-plans"
lacks "A24: a plan older than the index sends nothing to writing-plans" "$NEXT" "writing-plans"

# ---------------------------------------------------------------- A7
fixture
plan 2026-09-01-p1 "$S"
completed 2026-09-01-p1
register e docs/dagents/specs/shop.md "1|Epic S|$S|doing" "2|Other|-|verify"
roadmap e
ns --print --project
check "A7: the audit block exits 0" "$RC" 0
has "A7: the status names the current milestone" "$STATUS" "Project: milestone M1 (MVP) is current."
has "A7: the Next line is the milestone audit" "$NEXT" "dagents:closing-a-milestone"
has "A7: the verify row is named" "$NEXT" "#2"
has "A7: the built row is named" "$NEXT" "#1"
fixture
register e docs/dagents/specs/shop.md "1|Only verify|-|verify"
roadmap e
ns --print --project
has "A7: verify rows alone go to the audit" "$NEXT" "dagents:closing-a-milestone"
fixture
register r "$X" "1|Done|-|done"
ns --print --project
check "A7: nothing open exits 0" "$RC" 0
has "A7: no roadmap is the status" "$STATUS" "**Status:** Project: no roadmap."
has "A7: prints Nothing" "$NEXT" "**Next:** Nothing — no register holds an unresolved row."
lacks "A7: no launch prompt" "$OUT" "Paste as the first prompt:"
lacks "A7: no launch command" "$OUT" "Launch in "

# ---------------------------------------------------------------- A8
fixture
plan 2026-09-01-p1 "$S" "" 3
completed 2026-09-01-p1
register q "$S" "2|Requirement|$S|open"
ns --print --complete docs/dagents/plans/2026-09-01-p1.md
want=$NEXT
ns --print docs/dagents/plans/2026-09-01-p1.md
check "A8: a plain run for an indexed plan prints the --complete Next line" "$NEXT" "$want"
lacks "A8: and does not restart at Task 1" "$OUT" "Start at Task 1"
has "A8: the --complete line is the follow-up" "$want" "write a follow-up plan for rows #2"

# ---------------------------------------------------------------- A9
fixture
plan 2026-11-02-three "$X" "" 3
register r "$X" "1|Item|-|done"
commit_all "$R"
git -C "$R" worktree add -q "$TMP/wt$n" -b feat
WT=$(git -C "$TMP/wt$n" rev-parse --show-toplevel)
WL="$TMP/wt$n/.dagents/sdd/2026-11-02-three/progress.md"
mkdir -p "$(dirname "$WL")"
printf '# SDD ledger — plan: docs/dagents/plans/2026-11-02-three.md\nTask 1: complete (commits a..b, unreviewed)\n' > "$WL"
ns --print docs/dagents/plans/2026-11-02-three.md
has "A9: the worktree ledger's progress is reported" "$OUT" "1 of 3 tasks complete"
has "A9: the next task resumes after the ledger's" "$NEXT" "Task 2"
has "A9: the worktree is named" "$OUT" "$WT"
printf 'x\n' > "$TMP/wt$n/x.txt"
git -C "$TMP/wt$n" add x.txt && git -C "$TMP/wt$n" commit -qm work
whead=$(git -C "$TMP/wt$n" rev-parse --short HEAD)
printf 'Task 2: complete (commits a..b, unreviewed)\nTask 3: complete (commits a..b, unreviewed)\nFinal review: clean (commits abc1234..%s)\n' "$whead" >> "$WL"
ns --print docs/dagents/plans/2026-11-02-three.md
has "A9: the clean final review is read against the worktree" "$OUT" "final review is clean"
has "A9: the finishing worktree is named" "$OUT" "$WT"
lacks "A9: the review head is not taken as rewritten" "$OUT" "no longer in the branch history"
rm -rf "$TMP/wt$n/.dagents"
ns --print docs/dagents/plans/2026-11-02-three.md
has "A9: without that ledger the plan starts at Task 1" "$NEXT" "Task 1"

# ---------------------------------------------------------------- A6
fixture
plan 2026-11-01-demo "$X" "" 2
: > "$D/specs/draft.md"
completed 2026-09-01-old
register m1 "$X" "1|Epic|-|done"
{ printf '# Shop — roadmap\n\n**Product:** a shop\n**Spec:** docs/dagents/specs/shop.md\n\n'
  printf '| M | Name | Exit criteria | Register | State | Note |\n|---|---|---|---|---|---|\n'
  printf '| M1 | One | done | docs/dagents/registers/m1.md | closed | audit |\n'
  printf '| M2 | Two | done | docs/dagents/registers/m2.md | open | - |\n'
} > "$D/roadmap.md"
register m2 "$X" "1|Epic|-|open"
: > "$D/specs/shop.md"
commit_all "$R"
P6=docs/dagents/plans/2026-11-01-demo.md
LATEST="$R/.dagents/handoff/latest.md"
FINISH="$R/.dagents/sdd/finish.json"
snap() { # snap — the tree outside .git and the home directory, with digests and mtimes
  (cd "$R" && find . -path ./.git -prune -o -print | LC_ALL=C sort)
  (cd "$HOME" && find . -print | LC_ALL=C sort)
  local f
  for f in "$R/.dagents" "$HOME"; do
    find "$f" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r g; do printf '%s %s %s\n' "$g" "$(digest "$g")" "$(mtime "$g")"; done
  done
}
# A stub in-flight reporting running work: a plain run refuses with exit 5, --print must not look.
rm -rf "$TMP/stubscripts" && cp -R "$SCRIPTS" "$TMP/stubscripts"
# dagents' scripts read their settings through ../config/schema.mjs.
rm -rf "$TMP/config" && cp -R "$SCRIPTS/../config" "$TMP/config"
printf '#!/usr/bin/env bash\nprintf -- "- shell b1 10:00 idle 1m sleep\\n"\nexit 1\n' > "$TMP/stubscripts/in-flight"
modes=(
  "plan|$P6"
  "complete|--complete $P6"
  "kept|--kept $P6"
  "project|--project"
  "draft|--draft docs/dagents/specs/draft.md --next x"
  "adhoc-build|--adhoc --phase build --next x"
  "adhoc-design|--adhoc --phase design --next x"
  "codex|--host codex --project"
  "latest-project|--latest"
  "latest-complete|--latest"
  "latest-kept|--latest"
  "latest-draft|--latest"
  "latest-adhoc|--latest"
  "latest-plan|--latest"
)
for entry in "${modes[@]}"; do
  name=${entry%%|*}; args=${entry#*|}
  mkdir -p "$R/.dagents/handoff" "$R/.dagents/sdd"
  case $name in
    latest-project) mk="kind=project done=1 closed=1 subject=- at=1" ;;
    latest-complete) mk="kind=complete done=1 closed=1 subject=$P6 at=1" ;;
    latest-kept) mk="kind=kept branch=main done=1 closed=1 subject=$P6 at=1" ;;
    latest-draft) mk="kind=draft done=1 closed=1 subject=docs/dagents/specs/draft.md at=1" ;;
    latest-adhoc) mk="kind=adhoc done=1 closed=1 subject=- at=1" ;;
    latest-plan) mk="kind=plan done=1 closed=1 subject=$P6 at=1" ;;
    *) mk="" ;;
  esac
  printf '# Handoff\n\n## Notes\n\nkeep me\n\n## Next session\n\n**Status:** stored\n**Next:** stored\n' > "$LATEST"
  [ -z "$mk" ] || printf '<!-- next-step: %s -->\n' "$mk" >> "$LATEST"
  printf '{"action":"merge"}\n' > "$FINISH"
  touch -t 200101010000 "$LATEST" "$FINISH"
  before=$(snap)
  digest_before=$(digest "$LATEST"); mtime_before=$(mtime "$LATEST")
  # shellcheck disable=SC2086
  (cd "$R" && timeout 90 bash "$TMP/stubscripts/next-step" --print $args >"$TMP/o6" 2>"$TMP/e6"); rc=$?
  case $rc in 0|6) ok=ok ;; *) ok="exit $rc" ;; esac
  check "A6: --print $name exits 0 (or 6 for --latest), never 5" "$ok" ok
  check "A6: --print $name leaves every file and mtime alone" "$(snap)" "$before"
  check "A6: --print $name keeps latest.md byte-identical" "$(digest "$LATEST")" "$digest_before"
  check "A6: --print $name keeps latest.md's mtime" "$(mtime "$LATEST")" "$mtime_before"
  check "A6: --print $name keeps finish.json" "$(cat "$FINISH")" '{"action":"merge"}'
  check "A6: --print $name keeps finish.json's mtime" "$(mtime "$FINISH")" "$mtime_before"
done
rm -rf "$R/.dagents"
before=$(snap)
for entry in "plan|$P6" "complete|--complete $P6" "project|--project" "adhoc|--adhoc --phase build --next x" "latest|--latest"; do
  name=${entry%%|*}; args=${entry#*|}
  # shellcheck disable=SC2086
  (cd "$R" && timeout 90 bash "$TMP/stubscripts/next-step" --print $args >/dev/null 2>&1); rc=$?
  check "A6: --print $name with no .dagents creates nothing" "$([ -e "$R/.dagents" ] && echo created || echo none)" none
  case $rc in 5) echo "FAIL - A6: --print $name exited 5"; fail=$((fail + 1)) ;; *) pass=$((pass + 1)); echo "ok   - A6: --print $name with no .dagents does not exit 5" ;; esac
done
check "A6: --print with no .dagents changes no file" "$(snap)" "$before"
# Control: the same stub refuses a plain run, so the stub can fail the check.
(cd "$R" && timeout 90 bash "$TMP/stubscripts/next-step" "$P6" >/dev/null 2>&1); check "A6: the in-flight stub makes a plain run exit 5" "$?" 5
rm -rf "$R/.dagents"

# ---------------------------------------------------------------- A11
fixture
plan 2026-11-01-p "$X" "" 3
: > "$D/specs/D.md"
completed 2026-09-01-a 2026-09-02-b
register m1 "$X" "1|Epic|-|done"
{ printf '# Shop — roadmap\n\n**Product:** a shop\n**Spec:** docs/dagents/specs/shop.md\n\n'
  printf '| M | Name | Exit criteria | Register | State | Note |\n|---|---|---|---|---|---|\n'
  printf '| M1 | One | done | docs/dagents/registers/m1.md | closed | audit |\n'
  printf '| M2 | Two | done | docs/dagents/registers/m2.md | open | - |\n'
} > "$D/roadmap.md"
register m2 "$X" "1|Epic|-|open"
: > "$D/specs/shop.md"
commit_all "$R"
P11=docs/dagents/plans/2026-11-01-p.md
LATEST="$R/.dagents/handoff/latest.md"
section_last() { awk '/^## Next session[ \t\r]*$/ { on = 1; next } on && /^## / { exit } on && NF { last = $0 } END { print last }' "$LATEST"; }
for entry in "plan|$P11|$P11" "complete|--complete $P11|$P11" "kept|--kept $P11|$P11" "project|--project|-" "draft|--draft docs/dagents/specs/D.md --next x|docs/dagents/specs/D.md" "adhoc|--adhoc --phase build --next x|-"; do
  IFS='|' read -r kind args subject <<<"$entry"
  [ "$kind" != plan ] || args=$P11
  rm -f "$LATEST"
  before=$EPOCHSECONDS
  # shellcheck disable=SC2086
  ns $args
  after=$(date +%s)
  check "A11: $kind exits 0" "$RC" 0
  lacks "A11: $kind: the printed block has no marker" "$OUT" "<!-- next-step:"
  last=$(section_last)
  has "A11: $kind: the section ends with a next-step marker" "$last" "<!-- next-step: kind=$kind "
  has "A11: $kind: done counts the two completed.md entries" "$last" " done=2 "
  has "A11: $kind: closed counts the one closed milestone" "$last" " closed=1 "
  has "A11: $kind: the subject is recorded" "$last" " subject=$subject at="
  at=$(sed -n 's/.* at=\([0-9]*\) -->$/\1/p' <<<"$last")
  check "A11: $kind: at is an epoch second from this run" "$([ -n "$at" ] && [ "$at" -ge "$((before - 1))" ] && [ "$at" -le "$((after + 1))" ] && echo ok || echo "at=$at")" ok
  check "A11: $kind: exactly one marker in the file" "$(grep -c '^<!-- next-step:' "$LATEST")" 1
  [ "$kind" != kept ] || has "A11: kept: names the branch" "$last" " branch=main "
done
# The auto-run switch and clear read the first prompt and launch from the stored file.
rm -f "$LATEST"
mkdir -p "$HOME/.claude/dagents/sessions/cockpit"
date +%s > "$HOME/.claude/dagents/sessions/cockpit/s-1"
(cd "$R" && bash "$AR" --session s-1 start --spec "$S" --register docs/dagents/registers/m2.md --force >/dev/null 2>&1)
(cd "$R" && bash "$AR" --session s-1 attach --plan "$P11" >/dev/null 2>&1)
(cd "$R" && bash "$AR" --session s-1 phase plan >/dev/null 2>&1)
ns "$P11"
(cd "$R" && bash "$AR" --session s-1 switch >/dev/null 2>&1); rc=$?
check "A11: the auto-run switch accepts the block that carries a marker" "$rc" 0
STATE="$R/.dagents/sdd/auto-run.json"
check "A11: the switch stored the block's first prompt" "$(jq -r .resumePrompt "$STATE")" "$PROMPT"
check "A11: the switch stored the block's launch model" "$(jq -r '.launch.model' "$STATE")" "sonnet"
(cd "$R" && bash "$AR" --session s-1 clear --phase >/dev/null 2>&1); rc=$?
check "A11: the clear accepts it" "$rc" 0
check "A11: the clear leaves a clear pending" "$(jq -r .pending "$STATE")" "clear"
check "A11: the clear's first prompt is the block's" "$(jq -r .resumePrompt "$STATE")" "$PROMPT"
(cd "$R" && bash "$AR" --session s-1 stop >/dev/null 2>&1)

# ---------------------------------------------------------------- A10 A25 A26 A27 A28
L="$TMP/latest"
lfixture() { # lfixture — $L with plan P (3 tasks) and completed.md of one entry
  rm -rf "$L"; git init -q -b main "$L"
  LD="$L/docs/dagents"; mkdir -p "$LD/plans" "$LD/specs" "$LD/registers" "$L/.dagents/handoff"
  printf '.dagents/\n' > "$L/.gitignore"
  : > "$LD/specs/demo.md"
  {
    printf '# P\n\n**Spec:** docs/dagents/specs/demo.md\n'
    printf '**Execution:** inline — `claude --model sonnet --effort high` — small\n\n'
    printf '### Task 1: One\n\nBody.\n\n### Task 2: Two\n\nBody.\n\n### Task 3: Three\n\nBody.\n'
  } > "$LD/plans/2026-11-01-p.md"
  printf '# Completed plans\n\n- 2026-10-01 — `docs/dagents/plans/2026-10-01-a.md` — merged\n' > "$LD/plans/completed.md"
  git -C "$L" add -A && git -C "$L" commit -qm init
  LL="$L/.dagents/handoff/latest.md"
}
LP=docs/dagents/plans/2026-11-01-p.md
stored() { # stored <marker or empty> [status] [next]
  { printf '# Handoff\n\n## Notes\n\nmine\n\n## Next session\n\n**Status:** %s\n**Next:** %s\n' "${2:-Stored status.}" "${3:-Stored next.}"
    [ -z "$1" ] || printf '%s\n' "$1"; } > "$LL"
}
latest() { # latest — run --print --latest in $L; sets out, err, status
  out=$(cd "$L" && timeout 120 bash "$NS" --print --latest 2>"$TMP/lerr"); status=$?
  err=$(cat "$TMP/lerr")
}
close_m1() { # a roadmap whose M1 is closed
  printf '# M1\n\n**Source:** roadmap\n**Covers:** -\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | E | - | - | done | - |\n' > "$LD/registers/m1.md"
  printf '# R\n\n**Product:** p\n**Spec:** docs/dagents/specs/demo.md\n\n| M | Name | Exit criteria | Register | State | Note |\n|---|---|---|---|---|---|\n| M1 | One | x | docs/dagents/registers/m1.md | closed | audit |\n' > "$LD/roadmap.md"
}

# A10
for kind in adhoc draft; do
  lfixture
  : > "$LD/specs/D.md"
  subj=-; [ "$kind" != draft ] || subj=docs/dagents/specs/D.md
  stored "<!-- next-step: kind=$kind done=1 closed=0 subject=$subj at=1 -->"
  latest
  check "A10: $kind with matching counts exits 0" "$status" 0
  printf -- '- 2026-10-02 — `docs/dagents/plans/2026-10-02-b.md` — merged\n' >> "$LD/plans/completed.md"
  latest
  check "A10: $kind followed by one more completed.md entry exits 6" "$status" 6
  check "A10: $kind superseded prints nothing on stdout" "$out" ""
  lfixture
  : > "$LD/specs/D.md"
  close_m1
  stored "<!-- next-step: kind=$kind done=1 closed=0 subject=$subj at=1 -->"
  latest
  check "A10: $kind followed by one more closed milestone exits 6" "$status" 6
done
lfixture
close_m1
stored "<!-- next-step: kind=adhoc done=1 closed=1 subject=- at=1 -->"
latest
check "A10: an adhoc block whose counts match the repository still exits 0" "$status" 0

# A25
lfixture
stored ""
latest
check "A25: no marker exits 0" "$status" 0
has "A25: the stored Next line is printed" "$out" "**Next:** Stored next."
has "A25: the stored Status line is printed" "$out" "**Status:** Stored status."
has "A25: the output ends with kind=none" "$(tail -n 1 <<<"$out")" "kind=none"

# A26
lfixture
printf '# D\n' > "$LD/specs/D.md"
stored "<!-- next-step: kind=draft done=1 closed=0 subject=docs/dagents/specs/D.md at=1 -->"
latest
check "A26: a draft nobody planned stands" "$status" 0
sed 's#docs/dagents/specs/demo.md#docs/dagents/specs/D.md#' "$LD/plans/2026-11-01-p.md" > "$LD/plans/2026-11-02-d.md"
latest
check "A26: a plan naming the draft as its Spec supersedes it" "$status" 6
check "A26: nothing on stdout" "$out" ""

# A27
lfixture
git -C "$L" checkout -q -b feat && printf 'x\n' > "$L/x.txt" && git -C "$L" add x.txt && git -C "$L" commit -qm feat && git -C "$L" checkout -q main
KEPT="<!-- next-step: kind=kept branch=feat done=1 closed=0 subject=$LP at=1 -->"
stored "$KEPT"
latest
check "A27: an unmerged branch exits 0" "$status" 0
has "A27: an unmerged branch keeps the stored block" "$out" "**Next:** Stored next."
printf -- '- 2026-11-10 — `%s` — merged\n' "$LP" >> "$LD/plans/completed.md"
want=$(cd "$L" && bash "$NS" --print --complete "$LP" 2>/dev/null | grep '^\*\*Next:\*\*')
latest
check "A27: once indexed the block is the --complete block" "$(grep '^\*\*Next:\*\*' <<<"$out")" "$want"
lacks "A27: and no longer the stored one" "$out" "Stored next."
sed -i.bak '$d' "$LD/plans/completed.md" && rm -f "$LD/plans/completed.md.bak"
git -C "$L" branch -q -D feat
latest
check "A27: a deleted branch exits 6" "$status" 6
lfixture
git -C "$L" checkout -q -b feat && printf 'x\n' > "$L/x.txt" && git -C "$L" add x.txt && git -C "$L" commit -qm feat && git -C "$L" checkout -q main
git -C "$L" merge -q --no-ff -m merge feat
stored "$KEPT"
latest
check "A27: a branch merged into the primary HEAD exits 6" "$status" 6

# A28: the ledger that made the Status count tasks is deleted, the plan never indexed.
lfixture
mkdir -p "$L/.dagents/sdd/2026-11-01-p"
printf '# SDD ledger — plan: %s\nTask 1: complete (x)\nTask 2: complete (x)\n' "$LP" > "$L/.dagents/sdd/2026-11-01-p/progress.md"
(cd "$L" && timeout 60 bash "$NS" "$LP" >/dev/null 2>&1)
has "A28: next-step stored a Status that counts completed tasks" "$(cat "$LL")" "2 of 3 tasks complete"
latest
check "A28: with the ledger present the block recomputes" "$status" 0
has "A28: and resumes at Task 3" "$out" "Task 3"
rm -rf "$L/.dagents/sdd"
latest
check "A28: no ledger anywhere and no completed.md entry exits 6" "$status" 6
check "A28: nothing is printed to stdout" "$out" ""
lacks "A28: never Start at Task 1" "$out$err" "Start at Task 1"

# ---------------------------------------------------------------- A14
H="$TMP/handoff"
git init -q -b main "$H"
mkdir -p "$H/docs/dagents/plans" "$H/.dagents/sdd/2026-11-01-p" "$H/.dagents/handoff"
printf '.dagents/\n' > "$H/.gitignore"
printf '# P\n\n**Spec:** docs/dagents/specs/p.md\n**Execution:** inline — `claude --model sonnet --effort high` — x\n\n### Task 1: One\n\n### Task 2: Two\n\n### Task 3: Three\n' \
  > "$H/docs/dagents/plans/2026-11-01-p.md"
git -C "$H" add -A && git -C "$H" commit -qm init
printf '# SDD ledger — plan: docs/dagents/plans/2026-11-01-p.md\nTask 1: complete (x)\nTask 2: complete (x)\n' > "$H/.dagents/sdd/2026-11-01-p/progress.md"
hstored() { printf '# Handoff\n\n## Next session\n\n**Status:** Plan stored status.\n**Next:** Resume at Task 1 (One).\n%s\n' "$1" > "$H/.dagents/handoff/latest.md"; }
section() { (cd "$H" && timeout 100 bash "${1:-$AUDIT}" 2>/dev/null) | sed -n '/^## Handoff/,/^$/p'; }
hstored "<!-- next-step: kind=plan done=0 closed=0 subject=docs/dagents/plans/2026-11-01-p.md at=1 -->"
SEC=$(section)
has "A14: the lines are labelled recomputed" "$SEC" "recomputed from the repository"
has "A14: the recomputed Status line is printed" "$SEC" "- **Status:** Plan \`docs/dagents/plans/2026-11-01-p.md\`: 2 of 3 tasks complete"
has "A14: the recomputed Next line is printed, not the stored one" "$SEC" "Resume at Task 3"
lacks "A14: the stale stored Next line is not printed" "$SEC" "Resume at Task 1 (One)."
printf '# Completed plans\n\n- 2026-10-01 — `docs/dagents/plans/2026-10-01-a.md` — merged\n' > "$H/docs/dagents/plans/completed.md"
hstored "<!-- next-step: kind=adhoc done=0 closed=0 subject=- at=1 -->"
SEC=$(section)
has "A14: exit 6 says nothing is to resume" "$SEC" "nothing to resume"
lacks "A14: exit 6 prints no Next line" "$SEC" "**Next:**"
hstored "<!-- next-step: kind=plan done=1 closed=0 subject=docs/dagents/plans/missing.md at=1 -->"
SEC=$(section)
has "A14: another failure is labelled stored, not recomputed" "$SEC" "not recomputed"
has "A14: another failure prints the stored Status" "$SEC" "- **Status:** Plan stored status."
has "A14: another failure prints the stored Next" "$SEC" "- **Next:** Resume at Task 1 (One)."
lacks "A14: another failure is not labelled recomputed" "$SEC" "recomputed from the repository"
# A recompute that never returns: next-step is replaced by a stub that sleeps past the bound.
rm -rf "$TMP/auditscripts" && cp -R "$SCRIPTS" "$TMP/auditscripts"
# dagents' scripts read their settings through ../config/schema.mjs.
rm -rf "$TMP/config" && cp -R "$SCRIPTS/../config" "$TMP/config"
printf '#!/usr/bin/env bash\nsleep 40\n' > "$TMP/auditscripts/next-step"
hstored "<!-- next-step: kind=plan done=0 closed=0 subject=docs/dagents/plans/2026-11-01-p.md at=1 -->"
SEC=$(section "$TMP/auditscripts/repo-audit")
has "A14: a timeout is labelled not recomputed" "$SEC" "not recomputed"
has "A14: a timeout prints the stored Next" "$SEC" "- **Next:** Resume at Task 1 (One)."

# ---------------------------------------------------------------- A30 A31
fixture
plan 2026-09-01-p1 "$S"
plan 2026-09-02-p2 "$S"
completed 2026-09-01-p1 2026-09-02-p2
register m5 docs/dagents/specs/shop.md "1|Epic one|$S|doing" "2|Epic two|$S|open" "3|Operator check|-|verify"
roadmap m5
commit_all "$R"
ns --print --project
has "A30: the router sends the milestone to its audit" "$NEXT" "dagents:closing-a-milestone"
(cd "$R" && timeout 60 bash "$RM" close M1 --note audit >/dev/null 2>&1); rc=$?
check "A30: close is still refused while the rows are open" "$rc" 1
for id in 1 2 3; do bash "$REG" set "$D/registers/m5.md" "$id" done >/dev/null 2>&1; done
(cd "$R" && timeout 60 bash "$RM" close M1 --note audit >"$TMP/o30" 2>&1); rc=$?
check "A30: close M1 succeeds after the built and verify rows are done" "$rc" 0
check "A30: the milestone is closed" "$(grep -c '| M1 | MVP | .* | closed |' "$D/roadmap.md")" 1

fixture
printf '# S design\n' > "$R/$S"
register spec "$S" "1|Req|$S|done"
register m "docs/dagents/specs/shop.md" "1|Epic S|$S|doing"
roadmap m
bash "$REG" set "$D/registers/m.md" 1 doing --note "owner ruling: keep" >/dev/null
(cd "$R" && timeout 60 bash "$RM" settle --spec "$S" >/dev/null 2>&1)
note=$(awk -F'|' '$2 ~ /^ *1 *$/ { gsub(/^ +| +$/, "", $7); print $7 }' "$D/registers/m.md")
state=$(awk -F'|' '$2 ~ /^ *1 *$/ { gsub(/^ +| +$/, "", $6); print $6 }' "$D/registers/m.md")
check "A31: settle moves the epic to verify" "$state" verify
has "A31: settle keeps the existing note" "$note" "owner ruling: keep"
check "A31: settle prefixes its own note" "${note%%owner ruling: keep*}" "built; owner confirms at the milestone audit; "
(cd "$R" && timeout 60 bash "$RM" settle --spec "$S" >/dev/null 2>&1)
bash "$REG" set "$D/registers/m.md" 1 doing >/dev/null
(cd "$R" && timeout 60 bash "$RM" settle --spec "$S" >/dev/null 2>&1)
note2=$(awk -F'|' '$2 ~ /^ *1 *$/ { gsub(/^ +| +$/, "", $7); print $7 }' "$D/registers/m.md")
check "A31: a settle with no note of its own repeated keeps the note as it was" "$note2" "$note"

# ---------------------------------------------------------------- Stop hook
prompt() { # prompt <session> [cwd]
  jq -n --arg sid "$1" --arg cwd "${2:-$TRP}" '{hook_event_name:"UserPromptSubmit",session_id:$sid,cwd:$cwd,prompt:"go"}' | bash "$START"
}
stop_at() { # stop_at <session> <cwd> <message> [stop_hook_active]
  jq -n --arg sid "$1" --arg cwd "$2" --arg msg "$3" --argjson active "${4:-false}" \
    '{hook_event_name:"Stop",session_id:$sid,cwd:$cwd,transcript_path:"",stop_hook_active:$active,last_assistant_message:$msg}' | bash "$END"
}
decision() { jq -r '.decision // "none"' <<<"${1:-{\}}" 2>/dev/null || echo none; }
reason() { jq -r '.reason // ""' <<<"${1:-{\}}" 2>/dev/null; }
tcommit() { git -C "$1" add -A && git -C "$1" commit -qm "$2"; }
milestone() { printf '| %s | %s | it works | `docs/dagents/registers/%s.md` | %s | - |\n' "$1" "$2" "$1" "$3"; }
BLOCK=$'Wrapping up.\n\n## Next session\n\n**Status:** x\n**Next:** x'

TRP="$TMP/transitions"
git init -q -b main "$TRP"
mkdir -p "$TRP/docs/dagents/plans" "$TRP/.dagents/handoff"
printf '.dagents/\n' > "$TRP/.gitignore"
printf '# Completed plans\n\n- 2026-11-01 `docs/dagents/plans/2026-11-01-old.md` — merged into `main`\n' > "$TRP/docs/dagents/plans/completed.md"
{ printf '# Roadmap\n\n| M | Name | Exit | Register | State | Note |\n|---|---|---|---|---|---|\n'; milestone M1 One open; milestone M2 Two open; } > "$TRP/docs/dagents/roadmap.md"
tcommit "$TRP" 'docs: roadmap'

# A15
git -C "$TRP" worktree add -q "$TMP/wt-p" -b feature
sleep 1; prompt s-a15 "$TMP/wt-p"
sleep 1
printf -- '- 2026-11-16 `docs/dagents/plans/2026-11-16-p.md` — merged into `main`\n' >> "$TRP/docs/dagents/plans/completed.md"
tcommit "$TRP" 'docs: record p'
git -C "$TRP" worktree remove --force "$TMP/wt-p"
out=$(stop_at s-a15 "$TMP/wt-p" 'Merged. All done.')
check "A15: a removed-worktree finishing turn that ends on a summary is held" "$(decision "$out")" block
has "A15: the reason names next-step --complete with the plan" "$(reason "$out")" "next-step\" --complete docs/dagents/plans/2026-11-16-p.md"
check "A15: held once, the retry passes" "$(stop_at s-a15 "$TMP/wt-p" 'Merged. All done.' true)" ""

# A16: the turn's own commit closes a milestone
sleep 1; prompt s-a16 "$TRP"
sleep 1
sed 's/| M1 | One | \(.*\) | open |/| M1 | One | \1 | closed |/' "$TRP/docs/dagents/roadmap.md" > "$TMP/roadmap.md" && mv "$TMP/roadmap.md" "$TRP/docs/dagents/roadmap.md"
tcommit "$TRP" 'docs: close M1'
out=$(stop_at s-a16 "$TRP" 'M1 closed.')
check "A16: a turn whose commit closes a milestone is held" "$(decision "$out")" block
has "A16: the reason names next-step --project" "$(reason "$out")" "next-step\" --project"
check "A16: the retry passes" "$(stop_at s-a16 "$TRP" 'M1 closed.' true)" ""
# Moved only through a pull.
SECOND="$TMP/transitions-2"
git clone -q "$TRP" "$SECOND"
sed 's/| M2 | Two | \(.*\) | open |/| M2 | Two | \1 | closed |/' "$SECOND/docs/dagents/roadmap.md" > "$TMP/roadmap.md" && mv "$TMP/roadmap.md" "$SECOND/docs/dagents/roadmap.md"
printf -- '- 2026-11-16 `docs/dagents/plans/2026-11-16-q.md` — merged into `main`\n' >> "$SECOND/docs/dagents/plans/completed.md"
tcommit "$SECOND" 'docs: close M2, record q'
sleep 1; prompt s-a16b "$TRP"
sleep 1
git -C "$TRP" pull -q --ff-only "$SECOND" HEAD
check "A16: roadmap.md and completed.md moved only through a pull: not held" "$(stop_at s-a16b "$TRP" 'Pulled.')" ""

# A17: a hand-typed block does not release a transition turn while latest.md is writable and stale
mkdir -p "$TRP/.dagents/handoff"
printf '# Handoff\n\n## Next session\n\n**Status:** old\n**Next:** old\n' > "$TRP/.dagents/handoff/latest.md"
sleep 1; prompt s-a17 "$TRP"
sleep 1
printf -- '- 2026-11-17 `docs/dagents/plans/2026-11-17-r.md` — merged into `main`\n' >> "$TRP/docs/dagents/plans/completed.md"
tcommit "$TRP" 'docs: record r'
check "A17: a transition turn whose first stop carries a hand-typed block is held" "$(decision "$(stop_at s-a17 "$TRP" "$BLOCK")")" block
# A ledger turn.
WS="$TRP/.dagents/sdd/2026-10-08-example"
mkdir -p "$WS"
sleep 1; prompt s-a17b "$TRP"
sleep 1
printf '# SDD ledger — plan: docs/dagents/plans/2026-10-08-example.md\nTask 1: complete (commits a..b, review clean)\n' > "$WS/progress.md"
check "A17: a ledger turn whose first stop carries a hand-typed block is held" "$(decision "$(stop_at s-a17b "$TRP" "$BLOCK")")" block
# Control: the block next-step wrote this turn releases it.
sleep 1
printf '# Handoff\n\n## Next session\n\n**Status:** x\n**Next:** x\n' > "$TRP/.dagents/handoff/latest.md"
check "A17: control — a block next-step wrote this turn releases it" "$(stop_at s-a17b "$TRP" "$BLOCK")" ""
rm -rf "$WS"

# A18: nothing the hooks watch changed
mkdir -p "$WS"
printf '# SDD ledger — plan: docs/dagents/plans/2026-10-08-example.md\nTask 1: complete (commits a..b, review clean)\n' > "$WS/progress.md"
sleep 1; prompt s-a18 "$TRP"
sleep 1
printf 'notes\n' > "$TRP/docs/notes.md"
printf '# a plan\n' > "$TRP/docs/dagents/plans/2026-11-20-new.md"
tcommit "$TRP" 'docs: notes and a plan'
check "A18: a turn that changed no ledger, completed.md or roadmap.md passes" "$(stop_at s-a18 "$TRP" 'Added notes. Done.')" ""
check "A18: and passes when it asks a question" "$(stop_at s-a18 "$TRP" 'Which way?')" ""
rm -rf "$WS"

# A19: another worktree's ledger written during the turn (progress in darkmem).
. "$HERE/fixtures/darkmem-stores.sh"
DM="$TMP/dm"
git init -q -b main "$DM"
git -C "$DM" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
M=$(stores_home "$HOME" "$DM" proj local darkmem)
mkdir -p "$M/work/sdd/2026-10-11-other"
sleep 1; prompt s-a19 "$DM"
sleep 1
printf '# SDD ledger — plan: docs/dagents/plans/2026-10-11-other.md\nTask 1: complete (commits a..b, review clean)\n' > "$M/work/sdd/2026-10-11-other/progress.md"
check "A19: another worktree's ledger written during the turn never holds it" "$(stop_at s-a19 "$DM" 'Task 1 is done.')" ""
rm -f "$HOME/.dagents/config.json" "$HOME/.dagents/stores.json"

# A29: latest.md cannot be written, so the heading alone releases a held turn.
UNSH=0
if command -v unshare >/dev/null 2>&1 && unshare -m true >/dev/null 2>&1; then UNSH=1; fi
if [ "$UNSH" = 1 ]; then
  W29="$TMP/w29"
  git init -q -b main "$W29"
  mkdir -p "$W29/.dagents/handoff" "$W29/.dagents/sdd/2026-10-08-example" "$W29/docs/dagents/plans"
  printf '.dagents/\n' > "$W29/.gitignore"
  printf '# Completed plans\n' > "$W29/docs/dagents/plans/completed.md"
  tcommit "$W29" init
  printf '# Handoff\n\n## Next session\n\n**Status:** old\n**Next:** old\n' > "$W29/.dagents/handoff/latest.md"
  touch -t 200101010000 "$W29/.dagents/handoff/latest.md"
  sleep 1; prompt s-a29 "$W29"
  sleep 1
  printf '# SDD ledger — plan: docs/dagents/plans/2026-10-08-example.md\nTask 1: complete (commits a..b, review clean)\n' > "$W29/.dagents/sdd/2026-10-08-example/progress.md"
  check "A29: control — a writable latest.md does not accept the heading" "$(decision "$(stop_at s-a29 "$W29" "$BLOCK")")" block
  # Read-only bind mount of the handoff directory, in a private mount namespace.
  cat > "$TMP/stop-json.sh" <<'STOPJSON'
#!/usr/bin/env bash
# stop-json.sh END SESSION CWD MESSAGE
jq -n --arg sid "$2" --arg cwd "$3" --arg msg "$4" \
  '{hook_event_name:"Stop",session_id:$sid,cwd:$cwd,transcript_path:"",stop_hook_active:false,last_assistant_message:$msg}' | bash "$1"
STOPJSON
  ro_stop() { # ro_stop <session> <cwd> <message>
    unshare -m bash -c '
      mount --bind "$1/.dagents/handoff" "$1/.dagents/handoff" && mount -o remount,ro,bind "$1/.dagents/handoff" || exit 99
      shift
      exec bash "$@"
    ' _ "$W29" "$TMP/stop-json.sh" "$END" "$1" "$2" "$3"
  }
  out=$(ro_stop s-a29 "$W29" "$BLOCK"); rc=$?
  check "A29: an unwritable latest.md: the heading releases the held turn" "$out" ""
  # Absent latest.md in an unwritable directory.
  rm -f "$W29/.dagents/handoff/latest.md"
  sleep 1; prompt s-a29b "$W29"
  sleep 1
  printf 'Task 2: complete (commits a..b, review clean)\n' >> "$W29/.dagents/sdd/2026-10-08-example/progress.md"
  check "A29: control — an absent latest.md in a writable directory holds" "$(decision "$(stop_at s-a29b "$W29" "$BLOCK")")" block
  out=$(ro_stop s-a29b "$W29" "$BLOCK")
  check "A29: an absent latest.md in an unwritable directory: the heading releases" "$out" ""
else
  echo "skip - A29: no private mount namespace (unshare -m) on this host"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
