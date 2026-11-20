#!/usr/bin/env bash
# Acceptance tests for the parallel-session handoff spec, written from the
# spec's Acceptance section alone: the keyed handoff path, next-step's writes,
# claims, readers, cleanup, migration and the stop hooks. Each test name starts
# with its statement id. The plugin under test is the directory this file sits
# in (tests/dforge or tests/dagents).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN=$(basename "$HERE")
STATE=".$PLUGIN" DOCS="docs/$PLUGIN" PATHCMD="$PLUGIN-path" MIGRATE="$PLUGIN-migrate"
SCRIPTS="$HERE/../../plugins/$PLUGIN/scripts"
PLUGIN_ROOT="$HERE/../../plugins/$PLUGIN"
NS="$SCRIPTS/next-step"
PATHP="$SCRIPTS/$PATHCMD"
HANDOFF="$SCRIPTS/handoff"
AUDIT="$SCRIPTS/repo-audit"
START="$SCRIPTS/turn-start.sh"
END="$SCRIPTS/turn-end.sh"
SESSION_START="$SCRIPTS/session-start.sh"
AR="$SCRIPTS/auto-run"
[ "$PLUGIN" != dforge ] || . "$HERE/fixtures/darkmem-stores.sh"

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
exists() { [ -e "$1" ] && echo yes || echo no; }
handoffs_in() { find "$1" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' '; } # handoffs_in <dir>: the handoff files directly in it

# Sessions: the first eight characters of an id key its adhoc handoff.
S1=a1b1c1d1-0000-0000-0000-000000000001
S2=a2b2c2d2-0000-0000-0000-000000000002
S3=a3b3c3d3-0000-0000-0000-000000000003
id8() { printf '%s' "${1:0:8}"; }
beat() { # beat <session> [age in seconds]: the heartbeat a live cockpit writes
  local f
  f="$HOME/.claude/$PLUGIN/sessions/cockpit/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$(( $(date +%s) - ${2:-0} ))" > "$f"
}

# ---------------------------------------------------------------- fixtures
PA=2026-11-01-pa
PB=2026-11-02-pb
PG=2026-11-03-pg   # a program plan: its --complete block names the next sub-project
n=0
plan() { # plan <slug> [extra header line]
  {
    printf '# %s\n\n**Spec:** %s/specs/S.md\n' "$1" "$DOCS"
    printf '**Execution:** inline — `claude --model sonnet --effort high` — small\n'
    [ -z "${2:-}" ] || printf '%s\n' "$2"
    printf '\n### Task 1: One\n\nBody.\n\n### Task 2: Two\n\nBody.\n'
  } > "$D/plans/$1.md"
}
fixture() { # fixture — a fresh repository in $R (path $TOP) holding plans PA, PB and PG and drafts D, D1-design, E
  n=$((n + 1))
  R="$TMP/r$n"
  git init -q -b main "$R"
  D="$R/$DOCS"
  mkdir -p "$D/plans" "$D/specs"
  printf '%s/\n' "$STATE" > "$R/.gitignore"
  : > "$D/specs/S.md"; : > "$D/specs/program.md"
  : > "$D/specs/D.md"; : > "$D/specs/D1-design.md"; : > "$D/specs/E.md"
  plan "$PA"; plan "$PB"
  plan "$PG" "**Program:** $DOCS/specs/program.md — sub-project 2 of 5 — next: Session budget"
  printf '# Completed plans\n' > "$D/plans/completed.md"
  git -C "$R" add -A >/dev/null && git -C "$R" commit -qm init >/dev/null
  TOP=$(git -C "$R" rev-parse --show-toplevel)
  HD="$TOP/$STATE/handoff"
}
wt() { # wt <branch> — a linked worktree; prints its top-level path
  git -C "$R" worktree add -q -b "$1" "$TMP/w$n-$1" >/dev/null 2>&1
  git -C "$TMP/w$n-$1" rev-parse --show-toplevel
}
ledger() { # ledger <checkout> <slug> <lines...>
  local dir=$1/$STATE/sdd/$2 slug=$2; shift 2
  mkdir -p "$dir"
  { printf '# SDD ledger — plan: %s/plans/%s.md\n' "$DOCS" "$slug"; printf '%s\n' "$@"; } > "$dir/progress.md"
}
completed() { printf -- '- 2026-11-04 — `%s/plans/%s.md` — merged\n' "$DOCS" "$1" >> "$D/plans/completed.md"; }
# ns <session|-> <dir> <args...> — next-step in <dir> as that session; sets OUT, ERR, RC.
ns() {
  local sid=$1 dir=$2; shift 2
  if [ "$sid" = - ]; then
    OUT=$(cd "$dir" && env -u CLAUDE_CODE_SESSION_ID timeout 90 bash "$NS" "$@" 2>"$TMP/stderr"); RC=$?
  else
    OUT=$(cd "$dir" && CLAUDE_CODE_SESSION_ID=$sid timeout 90 bash "$NS" "$@" 2>"$TMP/stderr"); RC=$?
  fi
  ERR=$(cat "$TMP/stderr")
}
# hc <session|-> <dir> <args...> — scripts/handoff in <dir>; sets OUT, ERR, RC.
hc() {
  local sid=$1 dir=$2; shift 2
  if [ "$sid" = - ]; then
    OUT=$(cd "$dir" && env -u CLAUDE_CODE_SESSION_ID timeout 90 bash "$HANDOFF" "$@" 2>"$TMP/stderr"); RC=$?
  else
    OUT=$(cd "$dir" && CLAUDE_CODE_SESSION_ID=$sid timeout 90 bash "$HANDOFF" "$@" 2>"$TMP/stderr"); RC=$?
  fi
  ERR=$(cat "$TMP/stderr")
}
hpath() { # hpath <session> <dir> <next-step mode args...> — dforge-path handoff
  (cd "$2" && CLAUDE_CODE_SESSION_ID=$1 bash "$PATHP" handoff "${@:3}" 2>/dev/null)
}
notes() { # notes <checkout> <key> <text> — the session's notes file; prints its path
  mkdir -p "$1/$STATE/handoff/notes"
  printf '## Notes\n\n%s\n' "$3" > "$1/$STATE/handoff/notes/$2.md"
  printf '%s' "$1/$STATE/handoff/notes/$2.md"
}
prompt_of() { awk '/^Paste as the first prompt:/ { on = 1; next } on && /^```$/ { if (f) exit; f = 1; next } f' <<<"$1"; }
body_of() { awk '/^## Next session/ { exit } { print }' "$1"; } # the handoff's notes: everything above the block

# ---------------------------------------------------------------- A1
fixture
W1=$(wt w1)
ledger "$W1" "$PA" 'Task 1: complete (commits a..b, review clean)'
tgt() { # tgt <session> <dir> <args...> — what next-step --target prints
  ns "$1" "$2" --target "${@:3}"; printf '%s' "$OUT"
}
check "A1: a plan's handoff is <T>/$STATE/handoff/<plan-slug>.md, T its ledger's worktree" "$(hpath $S1 "$TOP" "$DOCS/plans/$PA.md")" "$W1/$STATE/handoff/$PA.md"
check "A1: a plan's handoff path is the one next-step --target names" "$(tgt $S1 "$TOP" "$DOCS/plans/$PA.md")" "$W1/$STATE/handoff/$PA.md"
check "A1: a plan without a ledger is keyed in the checkout it runs in" "$(hpath $S1 "$TOP" "$DOCS/plans/$PB.md")" "$TOP/$STATE/handoff/$PB.md"
check "A1: --complete targets the primary" "$(hpath $S1 "$W1" --complete "$DOCS/plans/$PA.md")" "$TOP/$STATE/handoff/$PA.md"
check "A1: --complete: next-step --target names the same path" "$(tgt $S1 "$W1" --complete "$DOCS/plans/$PA.md")" "$TOP/$STATE/handoff/$PA.md"
check "A1: --kept targets the primary" "$(hpath $S1 "$W1" --kept "$DOCS/plans/$PA.md")" "$(tgt $S1 "$W1" --kept "$DOCS/plans/$PA.md")"
check "A1: --draft is <draft-basename>.md" "$(hpath $S1 "$TOP" --draft "$DOCS/specs/D1-design.md" --next x)" "$TOP/$STATE/handoff/D1-design.md"
check "A1: --draft: next-step --target names the same path" "$(tgt $S1 "$TOP" --draft "$DOCS/specs/D1-design.md" --next x)" "$TOP/$STATE/handoff/D1-design.md"
check "A1: --adhoc is adhoc-<first 8 of the session id>.md" "$(hpath $S1 "$TOP" --adhoc --phase build --next x)" "$TOP/$STATE/handoff/adhoc-a1b1c1d1.md"
check "A1: --adhoc: next-step --target names the same path" "$(tgt $S1 "$TOP" --adhoc --phase build --next x)" "$TOP/$STATE/handoff/adhoc-a1b1c1d1.md"
check "A1: --project is adhoc-<first 8 of the session id>.md" "$(hpath $S2 "$TOP" --project)" "$TOP/$STATE/handoff/adhoc-a2b2c2d2.md"
check "A1: --project: next-step --target names the same path" "$(tgt $S2 "$TOP" --project)" "$TOP/$STATE/handoff/adhoc-a2b2c2d2.md"
check "A1: --adhoc in a linked worktree is the worktree's" "$(hpath $S1 "$W1" --adhoc --phase build --next x)" "$W1/$STATE/handoff/adhoc-a1b1c1d1.md"

cp "$D/plans/$PB.md" "$D/plans/adhoc-foo.md"; cp "$D/plans/$PB.md" "$D/plans/latest.md"; cp "$D/plans/$PB.md" "$D/plans/b@d.md"
: > "$D/specs/adhoc-bar.md"; : > "$D/specs/latest.md"; : > "$D/specs/a:b.md"
for k in "plans/adhoc-foo" "plans/latest" "plans/b@d"; do
  (cd "$TOP" && CLAUDE_CODE_SESSION_ID=$S1 bash "$PATHP" handoff "$DOCS/$k.md" >/dev/null 2>&1); rc=$?
  check "A1: a plan key $(basename "$k") exits 2" "$rc" "2"
done
for k in adhoc-bar latest a:b; do
  (cd "$TOP" && CLAUDE_CODE_SESSION_ID=$S1 bash "$PATHP" handoff --draft "$DOCS/specs/$k.md" --next x >/dev/null 2>&1); rc=$?
  check "A1: a draft key $k exits 2" "$rc" "2"
done
ns $S1 "$TOP" --target --draft "$DOCS/specs/latest.md" --next x
check "A1: next-step --target on a draft keyed latest exits 2" "$RC" "2"

if [ "$PLUGIN" = dforge ]; then
  fixture
  HOME_SAVE=$HOME; export HOME="$TMP/hm$n"; mkdir -p "$HOME"
  MIRROR=$(stores_home "$HOME" "$R" proj local darkmem)
  W2=$(wt w2)
  check "A1: darkmem: the primary's plan handoff is <mirror>/work/handoff/<key>.md" "$(hpath $S1 "$TOP" "$DOCS/plans/$PB.md")" "$MIRROR/work/handoff/$PB.md"
  check "A1: darkmem: the primary's draft handoff is in the mirror" "$(hpath $S1 "$TOP" --draft "$DOCS/specs/D.md" --next x)" "$MIRROR/work/handoff/D.md"
  check "A1: darkmem: the primary's adhoc handoff is in the mirror" "$(hpath $S1 "$TOP" --adhoc --phase build --next x)" "$MIRROR/work/handoff/adhoc-a1b1c1d1.md"
  check "A1: darkmem: a linked worktree's handoff stays local" "$(hpath $S1 "$W2" --adhoc --phase build --next x)" "$W2/$STATE/handoff/adhoc-a1b1c1d1.md"
  export HOME=$HOME_SAVE
fi

# ---------------------------------------------------------------- A2
fixture
K1=adhoc-$(id8 $S1) K2=D K3=$PA
N1=$(notes "$TOP" "$K1" "S1 sentinel notes"); N2=$(notes "$TOP" "$K2" "S2 sentinel notes"); N3=$(notes "$TOP" "$K3" "S3 sentinel notes")
ns $S1 "$TOP" --adhoc --phase build --next "S1 next" --notes "$N1"; rc1=$RC
f1=$(digest "$HD/$K1.md")
ns $S2 "$TOP" --draft "$DOCS/specs/D.md" --next "S2 next" --notes "$N2"; rc2=$RC
f2=$(digest "$HD/$K2.md")
check "A2: S1's file is unchanged by S2's call" "$(digest "$HD/$K1.md")" "$f1"
ns $S3 "$TOP" "$DOCS/plans/$PA.md" --notes "$N3"; rc3=$RC
check "A2: the three calls exit 0" "$rc1 $rc2 $rc3" "0 0 0"
check "A2: S1's file is unchanged by S3's call" "$(digest "$HD/$K1.md")" "$f1"
check "A2: S2's file is unchanged by S3's call" "$(digest "$HD/$K2.md")" "$f2"
check "A2: three handoff files exist" "$(cd "$HD" && LC_ALL=C ls -1 *.md | paste -sd, -)" "$K3.md,$K2.md,$K1.md"
check "A2: no latest.md is created" "$(exists "$HD/latest.md")" "no"
for pair in "$K1:S1:$S1" "$K2:S2:$S2" "$K3:S3:$S3"; do
  k=${pair%%:*}; rest=${pair#*:}; tag=${rest%%:*}; sid=${rest#*:}
  c=$(cat "$HD/$k.md")
  has "A2: $k holds its own notes" "$c" "$tag sentinel notes"
  has "A2: $k holds a Next session block" "$c" "## Next session"
  has "A2: $k's marker names its session" "$c" "session=$sid"
  for other in S1 S2 S3; do
    [ "$other" = "$tag" ] || lacks "A2: $k holds none of $other's notes" "$c" "$other sentinel notes"
  done
done
has "A2: S1's block is its own" "$(cat "$HD/$K1.md")" "S1 next"
has "A2: S2's block is its own" "$(cat "$HD/$K2.md")" "S2 next"

# ---------------------------------------------------------------- A3
fixture
WG=$(wt wg)
ledger "$WG" "$PG" 'Task 1: complete (commits a..b, review clean)' 'Task 2: complete (commits c..d, review clean)'
completed "$PG"
ns $S1 "$TOP" --adhoc --phase build --next "S1 unplanned work"
before=$(digest "$HD/adhoc-$(id8 $S1).md")
ns $S2 "$WG" --complete "$DOCS/plans/$PG.md"
check "A3: --complete run in the plan's worktree exits 0" "$RC" "0"
check "A3: --complete writes <primary>/$STATE/handoff/<plan>.md" "$(exists "$TOP/$STATE/handoff/$PG.md")" "yes"
check "A3: the primary's block is not written into the worktree" "$(exists "$WG/$STATE/handoff/$PG.md")" "no"
check "A3: S1's adhoc handoff is byte-identical" "$(digest "$HD/adhoc-$(id8 $S1).md")" "$before"

# ---------------------------------------------------------------- A4
fixture
K1=adhoc-$(id8 $S1) K2=adhoc-$(id8 $S2)
N1=$(notes "$TOP" "$K1" "S1 interleaved notes")
N2=$(notes "$TOP" "$K2" "S2 interleaved notes")
ns $S2 "$TOP" --adhoc --phase build --next "S2 next" --notes "$N2"
check "A4: S2's run exits 0" "$RC" "0"
ns $S1 "$TOP" --adhoc --phase build --next "S1 next" --notes "$N1"
check "A4: S1's run exits 0" "$RC" "0"
c1=$(cat "$HD/$K1.md"); c2=$(cat "$HD/$K2.md")
has "A4: S1's file holds S1's notes" "$c1" "S1 interleaved notes"
lacks "A4: S1's file holds none of S2's notes" "$c1" "S2 interleaved notes"
has "A4: S1's file holds S1's block" "$c1" "S1 next"
has "A4: S1's file carries S1's marker" "$c1" "session=$S1"
has "A4: S2's file holds S2's notes" "$c2" "S2 interleaved notes"
lacks "A4: S2's file holds none of S1's notes" "$c2" "S1 interleaved notes"
has "A4: S2's file holds S2's block" "$c2" "S2 next"
has "A4: S2's file carries S2's marker" "$c2" "session=$S2"
check "A4: S1's notes file is gone" "$(exists "$N1")" "no"
check "A4: S2's notes file is gone" "$(exists "$N2")" "no"
notes_before=$(body_of "$HD/$K1.md" | digest /dev/stdin)
ns $S1 "$TOP" --adhoc --phase build --next "S1 later next"
check "A4: a second run without --notes exits 0" "$RC" "0"
has "A4: the second run replaced the block" "$(cat "$HD/$K1.md")" "S1 later next"
check "A4: the second run leaves k1's notes byte-identical" "$(body_of "$HD/$K1.md" | digest /dev/stdin)" "$notes_before"
has "A4: the notes are still there" "$(cat "$HD/$K1.md")" "S1 interleaved notes"

# ---------------------------------------------------------------- A5
fixture
CLAIM_WORDS='scripts/handoff claim'
check_prompt() { # check_prompt <label> <prompt> <handoff path>
  has "A5: $1: the prompt names the keyed handoff by absolute path" "$2" "$3"
  has "A5: $1: the prompt says to claim it with scripts/handoff claim" "$2" "$CLAIM_WORDS"
  has "A5: $1: the prompt says to do it before anything else" "$2" "efore anything else"
}
ns $S1 "$TOP" --adhoc --phase build --next "x";            check_prompt "adhoc" "$(prompt_of "$OUT")" "$HD/adhoc-$(id8 $S1).md"
ns $S1 "$TOP" "$DOCS/plans/$PA.md";                        check_prompt "plan" "$(prompt_of "$OUT")" "$HD/$PA.md"
ns $S1 "$TOP" --draft "$DOCS/specs/D.md" --next "x";       check_prompt "draft" "$(prompt_of "$OUT")" "$HD/D.md"
WG=$(wt wg); ledger "$WG" "$PG" 'Task 1: complete (commits a..b, review clean)'; completed "$PG"
ns $S1 "$WG" --complete "$DOCS/plans/$PG.md";              check_prompt "complete" "$(prompt_of "$OUT")" "$TOP/$STATE/handoff/$PG.md"
ns $S1 "$TOP" --print --handoff "$HD/adhoc-$(id8 $S1).md"; check_prompt "recomputed (--print --handoff)" "$(prompt_of "$OUT")" "$HD/adhoc-$(id8 $S1).md"

ns - "$TOP" --host codex --target --adhoc --phase build --next "x"
CK=$(basename "$OUT" .md)
ns - "$TOP" --host codex --adhoc --key "$CK" --phase build --next "codex work"
cp_=$(prompt_of "$OUT")
lacks "A5: a Codex adhoc prompt carries no claim clause" "$(tr 'A-Z' 'a-z' <<<"$cp_")" "claim"
has "A5: a Codex adhoc prompt names the key to pass with --key" "$cp_" "--key $CK"
has "A5: a Codex adhoc prompt names its handoff" "$cp_" "$HD/$CK.md"
ns - "$TOP" --host codex --draft "$DOCS/specs/E.md" --next "x"
lacks "A5: a Codex draft prompt carries no claim clause" "$(tr 'A-Z' 'a-z' <<<"$(prompt_of "$OUT")")" "claim"

# ---------------------------------------------------------------- A6
fixture
ns $S1 "$TOP" --draft "$DOCS/specs/D.md" --next "x"
F="$HD/D.md"; CL="$HD/claims/D"
check "A6: the draft handoff exists" "$(exists "$F")" "yes"
hc $S2 "$TOP" claim "$F"
check "A6: S2 claims an unclaimed handoff: exit 0" "$RC" "0"
has "A6: the claim names S2" "$(cat "$CL" 2>/dev/null)" "session=$S2"
hc $S2 "$TOP" claim "$F"
check "A6: S2 claims again: exit 0" "$RC" "0"
beat $S2 0
cl_before=$(digest "$CL")
hc $S3 "$TOP" claim "$F"
check "A6: S3 while S2's heartbeat is fresh: exit 3" "$RC" "3"
has "A6: the refusal names S2's id8" "$OUT" "$(id8 $S2)"
check "A6: the refusal states the claim's age" "$(grep -cE 'claimed [0-9]+[smhd] ago' <<<"$OUT")" "1"
check "A6: the refusal leaves the claim unchanged" "$(digest "$CL")" "$cl_before"
beat $S2 1000
hc $S3 "$TOP" claim "$F"
check "A6: S3 after S2's heartbeat is stale: exit 0" "$RC" "0"
has "A6: the takeover line names the gone session" "$OUT" "took over the claim of $(id8 $S2) (gone:"
has "A6: the claim now names S3" "$(cat "$CL")" "session=$S3"
check "A6: the claim records S2 as previous" "$(grep -c "^previous=$(id8 $S2)" "$CL")" "1"
hc $S3 "$TOP" claim "$HD/never-written.md"
check "A6: a missing file: exit 0" "$RC" "0"
has "A6: a missing file: says no handoff file" "$OUT" "no handoff file"
check "A6: a missing file: claims nothing" "$(exists "$HD/claims/never-written")" "no"
printf 'x\n' > "$HD/bad@key.md"
hc $S3 "$TOP" claim "$HD/bad@key.md"
check "A6: a malformed key: exit 2" "$RC" "2"
hc - "$TOP" claim "$F"
check "A6: without a session id: exit 0" "$RC" "0"
check "A6: without a session id: says claims are Claude Code only" "$OUT" "claims are Claude Code only; not claimed"

# ---------------------------------------------------------------- A7
fixture
ns $S1 "$TOP" --draft "$DOCS/specs/D.md" --next "first"
ns $S1 "$TOP" "$DOCS/plans/$PA.md"
hc $S2 "$TOP" claim "$HD/D.md"; hc $S2 "$TOP" claim "$HD/$PA.md"
beat $S2 0
d_before=$(digest "$HD/D.md"); p_before=$(digest "$HD/$PA.md")
cl_d=$(digest "$HD/claims/D")
NF=$(notes "$TOP" D "S3 must not land")
ns $S3 "$TOP" --draft "$DOCS/specs/D.md" --next "second" --notes "$NF"
check "A7: next-step on a key another live session holds: exit 7" "$RC" "7"
check "A7: the handoff is unchanged" "$(digest "$HD/D.md")" "$d_before"
check "A7: the notes file is not consumed" "$(exists "$NF")" "yes"
check "A7: the claim is unchanged" "$(digest "$HD/claims/D")" "$cl_d"
ns $S3 "$TOP" --target --draft "$DOCS/specs/D.md" --next "second"
check "A7: next-step --target on a held key: exit 7" "$RC" "7"
ns $S3 "$TOP" "$DOCS/plans/$PA.md"
check "A7: a plan key held by a live session: exit 7" "$RC" "7"
check "A7: the plan handoff is unchanged" "$(digest "$HD/$PA.md")" "$p_before"
ns $S3 "$TOP" --target "$DOCS/plans/$PA.md"
check "A7: --target on a held plan key: exit 7" "$RC" "7"
ns $S2 "$TOP" --draft "$DOCS/specs/D.md" --next "holder writes"
check "A7: the holder itself is not refused" "$RC" "0"

# ---------------------------------------------------------------- A8
# Consume: S2 claims S1's adhoc handoff and hands off a draft with --notes.
fixture
K1=adhoc-$(id8 $S1)
ns $S1 "$TOP" --adhoc --phase build --next "S1 open item"
hc $S2 "$TOP" claim "$HD/$K1.md"
check "A8: S2 claims the adhoc handoff" "$RC" "0"
NF=$(notes "$TOP" D "S2 carried S1's open item")
ns $S2 "$TOP" --draft "$DOCS/specs/D.md" --next "design on" --notes "$NF"
check "A8: consume: exit 0" "$RC" "0"
check "A8: consume: D.md is written" "$(exists "$HD/D.md")" "yes"
check "A8: consume: the adhoc handoff is gone" "$(exists "$HD/$K1.md")" "no"
check "A8: consume: its claim is gone" "$(exists "$HD/claims/$K1")" "no"
has "A8: consume: stderr names the consumed path" "$ERR" "$HD/$K1.md"
has "A8: consume: stderr says consumed" "$ERR" "consumed"
# The same run without --notes keeps it.
fixture
ns $S1 "$TOP" --adhoc --phase build --next "S1 open item"
hc $S2 "$TOP" claim "$HD/$K1.md"
ns $S2 "$TOP" --draft "$DOCS/specs/D.md" --next "design on"
check "A8: without --notes: exit 0" "$RC" "0"
check "A8: without --notes: the adhoc handoff is kept" "$(exists "$HD/$K1.md")" "yes"
check "A8: without --notes: its claim is released" "$(exists "$HD/claims/$K1")" "no"
has "A8: without --notes: stderr says kept ... (released)" "$ERR" "kept $HD/$K1.md (released)"
# An unfinished plan's handoff and a live draft's handoff survive even with --notes.
fixture
ns $S1 "$TOP" "$DOCS/plans/$PA.md"
ns $S1 "$TOP" --draft "$DOCS/specs/D1-design.md" --next "x"
hc $S2 "$TOP" claim "$HD/$PA.md"; hc $S2 "$TOP" claim "$HD/D1-design.md"
NF=$(notes "$TOP" E "S2 notes")
ns $S2 "$TOP" --draft "$DOCS/specs/E.md" --next "e" --notes "$NF"
check "A8: a draft handoff with --notes: exit 0" "$RC" "0"
check "A8: an unfinished plan's handoff is kept with --notes" "$(exists "$HD/$PA.md")" "yes"
check "A8: its claim is released" "$(exists "$HD/claims/$PA")" "no"
has "A8: stderr says the plan's handoff is kept (released)" "$ERR" "kept $HD/$PA.md (released)"
check "A8: a live draft's handoff is kept with --notes" "$(exists "$HD/D1-design.md")" "yes"
check "A8: its claim is released" "$(exists "$HD/claims/D1-design")" "no"
has "A8: stderr says the draft's handoff is kept (released)" "$ERR" "kept $HD/D1-design.md (released)"
# Supersede: a plan handed off from the primary, then by its executor in worktree W.
fixture
ns $S1 "$TOP" "$DOCS/plans/$PA.md"
check "A8: the primary holds the plan's handoff first" "$(exists "$HD/$PA.md")" "yes"
W=$(wt w)
ledger "$W" "$PA" 'Task 1: complete (commits a..b, review clean)'
ns $S2 "$W" "$DOCS/plans/$PA.md"
check "A8: the executor's call exits 0" "$RC" "0"
check "A8: the worktree holds the plan's handoff" "$(exists "$W/$STATE/handoff/$PA.md")" "yes"
check "A8: the primary's copy is gone" "$(exists "$HD/$PA.md")" "no"
has "A8: stderr says superseded" "$ERR" "superseded $HD/$PA.md"
hc $S2 "$W" claim "$W/$STATE/handoff/$PA.md"
check "A8: the executor claims the worktree's handoff" "$RC" "0"
beat $S2 0
hc $S3 "$TOP" claim "$W/$STATE/handoff/$PA.md"
check "A8: a primary session's claim on the plan exits 3 while W's session holds it" "$RC" "3"
has "A8: the refusal names the executor" "$OUT" "$(id8 $S2)"

# ---------------------------------------------------------------- A10
audit() { # audit <session> <dir> — repo-audit as that session; sets OUT
  OUT=$(cd "$2" && CLAUDE_CODE_SESSION_ID=$1 timeout 120 bash "$AUDIT" 2>"$TMP/stderr"); RC=$?
  ERR=$(cat "$TMP/stderr")
}
section() { awk -v h="$2" '$0 == "## " h { on = 1; next } /^## / { on = 0 } on' <<<"$1"; } # section <audit text> <heading>
age_files() { # age_files <days> <files...>: make handoffs old in mtime and in their marker's at=
  local days=$1 f t; shift
  t=$(( $(date +%s) - days * 86400 ))
  for f; do
    sed -i "s/ at=[0-9]* -->/ at=$t -->/" "$f"
    touch -d "@$t" "$f"
  done
}
fixture
W=$(wt w)
ns $S1 "$TOP" "$DOCS/plans/$PA.md"                                   # S1's own handoff (a plan with no ledger yet)
age_files 0 "$HD/$PA.md"; touch -d '@'"$(( $(date +%s) - 7200 ))" "$HD/$PA.md"
ns $S2 "$TOP" --draft "$DOCS/specs/D.md" --next "S2 design"
ns $S2 "$W" --adhoc --phase build --next "S2 in the worktree"
hc $S3 "$TOP" claim "$HD/D.md"; beat $S3 0
ledger "$TOP" "$PA" 'Task 1: complete (commits a..b, review clean)'
ns $S1 "$TOP" --print --handoff "$HD/$PA.md"
recomputed_next=$(grep -m1 '^\*\*Next:\*\*' <<<"$OUT")
audit $S1 "$TOP"
hs=$(section "$OUT" "Handoff")
check "A10: repo-audit exits 0" "$RC" "0"
for pair in "$HD/$PA.md:$PA:plan" "$HD/D.md:D:draft" "$W/$STATE/handoff/adhoc-$(id8 $S2).md:adhoc-$(id8 $S2):adhoc"; do
  p=${pair%%:*}; rest=${pair#*:}; k=${rest%%:*}; kind=${rest#*:}
  line=$(grep -F -- "$p" <<<"$hs" | head -n 1)
  has "A10: the audit lists $p" "$hs" "$p"
  has "A10: $k's line names its key" "$line" "$k"
  has "A10: $k's line names its kind" "$line" "$kind"
  check "A10: $k's line states an age" "$(grep -cE '[0-9]+[smhd]( |,|$)' <<<"$line")" "1"
done
check "A10: an unclaimed handoff is listed unclaimed" "$(grep -F -- "adhoc-$(id8 $S2).md" <<<"$hs" | head -n 1 | grep -c 'unclaimed')" "1"
has "A10: a handoff another live session claims shows the claimant live" "$(grep -F -- "$HD/D.md" <<<"$hs" | head -n 1)" "$(id8 $S3) live"
check "A10: the session's own handoff is listed first" "$(grep -m1 -F -e "$HD/" -e "$W/" <<<"$hs" | grep -cF -- "$HD/$PA.md")" "1"
has "A10: the session's own handoff is recomputed (its Next line is the recomputed one)" "$hs" "$recomputed_next"
check "A10: the recomputed Next differs from the stored block's" "$([ "$recomputed_next" != "$(grep -m1 '^\*\*Next:\*\*' "$HD/$PA.md")" ] && echo yes || echo no)" "yes"

# Session start: unclaimed or gone-claimed handoffs younger than three days.
fixture
ns $S1 "$TOP" --adhoc --phase build --next "open one"                 # unclaimed, fresh: counted
ns $S2 "$TOP" --draft "$DOCS/specs/D.md" --next "gone claimant"
hc $S3 "$TOP" claim "$HD/D.md"                                       # S3 has no beat: gone; counted
ns $S2 "$TOP" --draft "$DOCS/specs/E.md" --next "live claimant"
hc $S2 "$TOP" claim "$HD/E.md"; beat $S2 0                            # a live other session: not counted
ns $S3 "$TOP" "$DOCS/plans/$PB.md"
age_files 4 "$HD/$PB.md"                                              # older than three days: not counted
before=$(cd "$HD" && LC_ALL=C ls -R | digest /dev/stdin)
OUT=$(cd "$TOP" && jq -n --arg sid "$S1" --arg cwd "$TOP" '{hook_event_name:"SessionStart",session_id:$sid,cwd:$cwd,source:"startup"}' \
  | CLAUDE_CODE_SESSION_ID=$S1 timeout 120 bash "$SESSION_START" 2>/dev/null); RC=$?
check "A10: session start exits 0" "$RC" "0"
has "A10: session start counts the two open handoffs" "$OUT" "2 open handoffs (scripts/repo-audit lists them)."
check "A10: session start deletes nothing" "$(cd "$HD" && LC_ALL=C ls -R | digest /dev/stdin)" "$before"

if [ "$PLUGIN" = dforge ]; then
  fixture
  HOME_SAVE=$HOME; export HOME="$TMP/hm$n"; mkdir -p "$HOME"
  MIRROR=$(stores_home "$HOME" "$R" proj local darkmem)
  ns $S1 "$TOP" --draft "$DOCS/specs/D.md" --next "mirror draft"
  audit $S1 "$TOP"
  hs=$(section "$OUT" "Handoff")
  has "A10: darkmem: the audit lists the mirror's handoff" "$hs" "$MIRROR/work/handoff/D.md"
  has "A10: darkmem: its line names key and kind" "$(grep -F -- "$MIRROR/work/handoff/D.md" <<<"$hs" | head -n 1)" "draft"
  export HOME=$HOME_SAVE
fi

# ---------------------------------------------------------------- A11
prompt() { # prompt <session> <cwd> — the UserPromptSubmit hook's turn stamp
  jq -n --arg sid "$1" --arg cwd "$2" '{hook_event_name:"UserPromptSubmit",session_id:$sid,cwd:$cwd,prompt:"go"}' | bash "$START"
}
stop() { # stop <session> <cwd> <last message> — the Stop hook's answer
  jq -n --arg sid "$1" --arg cwd "$2" --arg msg "$3" \
    '{hook_event_name:"Stop",session_id:$sid,cwd:$cwd,transcript_path:"",stop_hook_active:false,last_assistant_message:$msg}' | bash "$END"
}
decision() { jq -r '.decision // "none"' <<<"${1:-{\}}" 2>/dev/null || echo none; }
nap() { sleep 1; } # modification times compare in whole seconds on some filesystems

# S1's own block, after S2 wrote a newer handoff in the same checkout.
fixture
prompt $S1 "$TOP" >/dev/null; nap
ledger "$TOP" "$PA" 'Task 1: complete (commits a..b, review clean)'
ns $S1 "$TOP" "$DOCS/plans/$PA.md"; BLOCK_A=$OUT; nap
ns $S2 "$TOP" --adhoc --phase build --next "S2 newer handoff"; nap
check "A11: control: a summary without the block is held" "$(decision "$(stop $S1 "$TOP" 'Task 1 is done. All good.')")" "block"
check "A11: S1's turn ending on its own block is released after S2 wrote a newer handoff" "$(decision "$(stop $S1 "$TOP" "$BLOCK_A")")" "none"

# A terminal --complete block: printed, not written; the turn is released.
fixture
prompt $S1 "$TOP" >/dev/null; nap
completed "$PB"
check "A11: control: a merged plan with no block is held by the transition test" "$(decision "$(stop $S1 "$TOP" 'Merged. Done.')")" "block"
nap
ns $S1 "$TOP" --complete "$DOCS/plans/$PB.md"
check "A11: a terminal --complete block exits 0" "$RC" "0"
has "A11: the block is terminal" "$OUT" "Nothing —"
check "A11: a terminal block is not written" "$(exists "$HD/$PB.md")" "no"
check "A11: a turn that ran --complete after recording the plan in completed.md is released" "$(decision "$(stop $S1 "$TOP" "$OUT")")" "none"

# A non-terminal --complete block after completed.md changed: not held by the transition test.
fixture
prompt $S1 "$TOP" >/dev/null; nap
completed "$PG"
nap
ns $S1 "$TOP" --complete "$DOCS/plans/$PG.md"
check "A11: a non-terminal --complete block is written" "$(exists "$HD/$PG.md")" "yes"
check "A11: a turn that ran --complete after recording the plan is not held by the transition test" "$(decision "$(stop $S1 "$TOP" "$OUT")")" "none"

# A BLOCKED plan: the block is written and the turn released.
fixture
prompt $S1 "$TOP" >/dev/null; nap
ledger "$TOP" "$PA" 'Task 1: BLOCKED — owner — pick the storage engine'
ns $S1 "$TOP" "$DOCS/plans/$PA.md"
has "A11: the BLOCKED plan's block names the blocker" "$OUT" "BLOCKED"
check "A11: the BLOCKED plan's block is written" "$(exists "$HD/$PA.md")" "yes"
check "A11: a BLOCKED plan's turn is released on its block" "$(decision "$(stop $S1 "$TOP" "$OUT")")" "none"

# A hand-typed block carrying only another session's Next line is held.
fixture
prompt $S1 "$TOP" >/dev/null; nap
ledger "$TOP" "$PA" 'Task 1: complete (commits a..b, review clean)'
ns $S2 "$TOP" --draft "$DOCS/specs/E.md" --next "S2 sentinel next action"; S2_BLOCK=$OUT
S2_NEXT=$(grep -m1 '^\*\*Next:\*\*' <<<"$S2_BLOCK"); S2_STATUS=$(grep -m1 '^\*\*Status:\*\*' <<<"$S2_BLOCK")
check "A11: S1 typing only S2's Next line is held" "$(decision "$(stop $S1 "$TOP" "## Next session

$S2_NEXT")")" "block"
check "A11: S1 typing S2's Status and Next lines is released (the rule for another session's handoff)" "$(decision "$(stop $S1 "$TOP" "## Next session

$S2_STATUS
$S2_NEXT")")" "none"

# ---------------------------------------------------------------- A12
set_mtime() { touch -d "@$(( $(date +%s) - $1 ))" "$2"; } # set_mtime <seconds ago> <file>
fixture
ns $S1 "$TOP" --adhoc --phase build --next "OWNWRITTEN sentinel"
ns $S2 "$TOP" --draft "$DOCS/specs/D.md" --next "CLAIMED sentinel"
ns $S3 "$TOP" --draft "$DOCS/specs/E.md" --next "FOREIGN sentinel"
hc $S1 "$TOP" claim "$HD/D.md"
set_mtime 300 "$HD/adhoc-$(id8 $S1).md"; set_mtime 200 "$HD/D.md"; set_mtime 100 "$HD/E.md"
snap() { # snap <session> — the compaction snapshot the SessionStart hook appends after a compaction
  OUT=$(cd "$TOP" && jq -n --arg sid "$1" --arg cwd "$TOP" '{hook_event_name:"SessionStart",session_id:$sid,cwd:$cwd,source:"compact",transcript_path:""}' \
    | CLAUDE_CODE_SESSION_ID=$1 timeout 120 bash "$SESSION_START" 2>/dev/null); RC=$?
  OUT=$(jq -r '.hookSpecificOutput.additionalContext' <<<"$OUT" 2>/dev/null)
}
snap $S1
check "A12: the snapshot hook exits 0" "$RC" "0"
has "A12: the snapshot shows the handoff this session claimed (newer than its own write)" "$OUT" "CLAIMED sentinel"
lacks "A12: the snapshot omits the older handoff whose marker names this session" "$OUT" "OWNWRITTEN sentinel"
lacks "A12: the snapshot omits another session's newest handoff" "$OUT" "FOREIGN sentinel"
snap $S3
has "A12: another session's snapshot shows the handoff its marker names" "$OUT" "FOREIGN sentinel"
lacks "A12: ... and none of S1's" "$OUT" "CLAIMED sentinel"
snap a9b9c9d9-0000-0000-0000-000000000009
lacks "A12: a session with no handoff of its own sees none" "$OUT" "FOREIGN sentinel"
lacks "A12: ... of any session" "$OUT" "CLAIMED sentinel"

# ---------------------------------------------------------------- A13
ar() { # ar <session> <args...> — auto-run in the primary as that session
  (cd "$TOP" && CLAUDE_CODE_SESSION_ID=$1 timeout 120 bash "$AR" --session "$1" "${@:2}" 2>&1)
}
arfield() { jq -r --arg f "$1" '.[$f] | tostring' "$TOP/$STATE/sdd/auto-run.json"; }
fixture
beat $S1 0
ar $S1 start --spec "$DOCS/specs/D.md" >/dev/null
ns $S1 "$TOP" --adhoc --phase build --next "OWNER design handoff"
ns $S2 "$TOP" --draft "$DOCS/specs/E.md" --next "FOREIGN newer handoff"
set_mtime 300 "$HD/adhoc-$(id8 $S1).md"; set_mtime 10 "$HD/E.md"
ar $S1 clear --phase >/dev/null
check "A13: with no plan attached the clear stores the owner's handoff's first prompt" \
  "$(arfield resumePrompt)" "$(prompt_of "$(cat "$HD/adhoc-$(id8 $S1).md")")"
has "A13: ... which names the owner's keyed file" "$(arfield resumePrompt)" "$HD/adhoc-$(id8 $S1).md"
lacks "A13: ... and not the newer handoff of another session" "$(arfield resumePrompt)" "FOREIGN"
check "A13: a clear is pending" "$(arfield pending)" "clear"

fixture
beat $S1 0
ar $S1 start --spec "$DOCS/specs/D.md" >/dev/null
ar $S1 attach --plan "$DOCS/plans/$PA.md" >/dev/null
ns $S2 "$TOP" "$DOCS/plans/$PA.md"                                   # the plan's keyed handoff, written by another session
ns $S1 "$TOP" --adhoc --phase build --next "OWNER newer unrelated handoff"
set_mtime 300 "$HD/$PA.md"; set_mtime 10 "$HD/adhoc-$(id8 $S1).md"
ar $S1 clear --phase >/dev/null
check "A13: with a plan attached the clear stores the first prompt of the file next-step --target prints" \
  "$(arfield resumePrompt)" "$(prompt_of "$(cat "$(hpath $S1 "$TOP" "$DOCS/plans/$PA.md")")")"
has "A13: ... the plan's keyed file" "$(arfield resumePrompt)" "$HD/$PA.md"
lacks "A13: ... not the owner's newer unrelated handoff" "$(arfield resumePrompt)" "adhoc-$(id8 $S1)"

# ---------------------------------------------------------------- A17
fixture
ns - "$TOP" --target --adhoc --phase build --next "x"
check "A17: --target --adhoc without a session id: exit 0" "$RC" "0"
check "A17: ... prints adhoc-<8 hex>.md in the handoff directory" "$(grep -cE "^$HD/adhoc-[0-9a-f]{8}\.md\$" <<<"$OUT")" "1"
KEY=$(basename "$OUT" .md); minted=$OUT
check "A17: --target writes nothing" "$(handoffs_in "$HD")" "0"
NF=$(notes "$TOP" "$KEY" "key notes")
ns - "$TOP" --adhoc --key "$KEY" --phase build --next "x" --notes "$NF"
check "A17: --adhoc --key <that key> writes it: exit 0" "$RC" "0"
check "A17: ... the file is the printed path" "$(exists "$minted")" "yes"
has "A17: ... holding the notes" "$(cat "$minted")" "key notes"
ns - "$TOP" --adhoc --key "adhoc-legacy-1700000000" --phase build --next "x"
check "A17: an adhoc-legacy-* key is accepted" "$RC" "0"
check "A17: ... and written" "$(exists "$HD/adhoc-legacy-1700000000.md")" "yes"
fixture
NF=$(notes "$TOP" "x" "must survive")
ns - "$TOP" --adhoc --phase build --next "x" --notes "$NF"
check "A17: --adhoc with neither a session id nor --key: exit 2" "$RC" "2"
check "A17: ... writes nothing" "$(handoffs_in "$HD")" "0"
check "A17: ... keeps the notes file" "$(exists "$NF")" "yes"
for bad in foo adhoc-xyz adhoc-1234567 adhoc-1234567g adhoc-123456789 latest D "adhoc-legacy"; do
  ns - "$TOP" --adhoc --key "$bad" --phase build --next "x"
  check "A17: --key $bad does not match adhoc-<8 hex> or adhoc-legacy-*: exit 2" "$RC" "2"
done
ns $S1 "$TOP" --adhoc --key "adhoc-12345678" --phase build --next "x"
check "A17: --key with a session id set: exit 2" "$RC" "2"
check "A17: ... writes nothing" "$(handoffs_in "$HD")" "0"
ns - "$TOP" --key "adhoc-12345678" "$DOCS/plans/$PA.md"
check "A17: --key with a plan: exit 2" "$RC" "2"
ns - "$TOP" --key "adhoc-12345678" --draft "$DOCS/specs/D.md" --next x
check "A17: --key with a draft: exit 2" "$RC" "2"
check "A17: ... and writes nothing" "$(handoffs_in "$HD")" "0"

# ---------------------------------------------------------------- A21
fixture
beat $S1 0; beat $S2 0
ns $S2 "$TOP" --draft "$DOCS/specs/D.md" --next "S2 design"
hc $S2 "$TOP" claim "$HD/D.md"
ar $S1 start --spec "$DOCS/specs/E.md" >/dev/null
check "A21: the auto run is active" "$(arfield active)" "true"
hc $S1 "$TOP" claim "$HD/D.md"
check "A21: handoff claim refused: exit 3" "$RC" "3"
check "A21: the auto run is stopped after the refusal" "$(arfield active)" "false"
has "A21: the stop reason names the key" "$(arfield stopped)" "D"
has "A21: the stop reason names the holder" "$(arfield stopped)" "$(id8 $S2)"
fixture
beat $S1 0; beat $S2 0
ns $S2 "$TOP" --draft "$DOCS/specs/D.md" --next "S2 design"
hc $S2 "$TOP" claim "$HD/D.md"
ar $S1 start --spec "$DOCS/specs/E.md" >/dev/null
ns $S1 "$TOP" --draft "$DOCS/specs/D.md" --next "S1 design"
check "A21: next-step refused: exit 7" "$RC" "7"
check "A21: the auto run is stopped after the refusal" "$(arfield active)" "false"
has "A21: the stop reason names the key" "$(arfield stopped)" "D"
has "A21: the stop reason names the holder" "$(arfield stopped)" "$(id8 $S2)"

# ---------------------------------------------------------------- end
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
