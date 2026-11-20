#!/usr/bin/env bash
# Acceptance tests for the per-worktree handoff spec, written from the spec's
# Acceptance section: the handoff path of each checkout, next-step's target
# checkout, launch line and prompt, --target, the notes-keeping rule, and the
# darkmem placement. Each test name starts with its statement id.
set -uo pipefail

PLUGIN=dforge STATE=.dforge DOCS=docs/dforge PATHCMD=dforge-path

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../../plugins/$PLUGIN/scripts"
NS="$SCRIPTS/next-step"
START="$SCRIPTS/turn-start.sh"
END="$SCRIPTS/turn-end.sh"
UIEND="$SCRIPTS/ui-turn-end.sh"
. "$HERE/fixtures/darkmem-stores.sh"
PATHP="$SCRIPTS/$PATHCMD"

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
unset CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR AR_SESSION DFORGE_BUDGET CLAUDE_PROJECT_DIR \
  DFORGE_DOCUMENT_STORE DFORGE_PROGRESS_SOURCE DAGENTS_DOCUMENT_STORE DAGENTS_PROGRESS_SOURCE
export DFORGE_NO_SETTINGS=1 GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
# Local mode needs no mirror; the stubs below stand in for the host's clients.

digest() { if command -v sha256sum >/dev/null 2>&1; then sha256sum < "$1"; else shasum -a 256 < "$1"; fi; }

# ---------------------------------------------------------------- fixtures
PA=2026-11-01-pa
PB=2026-11-02-pb
PQ=2026-11-03-pq
PC=2026-10-01-pc
n=0
plan() { # plan <slug> <spec file name> [extra header line]
  {
    printf '# %s\n\n**Spec:** %s/specs/%s\n' "$1" "$DOCS" "$2"
    printf '**Execution:** inline — `claude --model sonnet --effort high` — small\n'
    [ -z "${3:-}" ] || printf '%s\n' "$3"
    printf '\n### Task 1: One\n\nBody.\n\n### Task 2: Two\n\nBody.\n'
  } > "$D/plans/$1.md"
}
fixture() { # fixture — a fresh repository in $R (path $TOP) holding plans PA, PB and PQ, and PC completed
  n=$((n + 1))
  R="$TMP/r$n"
  git init -q -b main "$R"
  D="$R/$DOCS"
  mkdir -p "$D/plans" "$D/specs" "$D/registers"
  printf '%s/\n' "$STATE" > "$R/.gitignore"
  : > "$D/specs/S.md"; : > "$D/specs/X.md"; : > "$D/specs/Q.md"; : > "$D/specs/program.md"
  plan "$PA" S.md "**Program:** $DOCS/specs/program.md — sub-project 2 of 5 — next: Session budget"
  plan "$PB" S.md
  plan "$PQ" Q.md
  plan "$PC" S.md
  printf '# Completed plans\n\n- 2026-10-02 — `%s/plans/%s.md` — merged\n' "$DOCS" "$PC" > "$D/plans/completed.md"
  {
    printf '# r — item register\n\n**Source:** test\n**Covers:** %s/specs/S.md\n\n' "$DOCS"
    printf '| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n'
    printf '| 1 | Build Q | %s/specs/Q.md | - | doing | - |\n' "$DOCS"
  } > "$D/registers/r.md"
  mkdir -p "$R/src" "$D/ui-ux"
  printf 'export const App = () => <main>Hi</main>;\n' > "$R/src/App.tsx"
  printf '# UI profile\n\n**Platform:** web\n' > "$D/ui-ux/profile.md"
  git -C "$R" add -A >/dev/null && git -C "$R" commit -qm init >/dev/null
  TOP=$(git -C "$R" rev-parse --show-toplevel)
}
wt() { # wt <branch> — a linked worktree; prints its top-level path
  git -C "$R" worktree add -q -b "$1" "$TMP/w$n-$1" >/dev/null 2>&1
  git -C "$TMP/w$n-$1" rev-parse --show-toplevel
}
ledger() { # ledger <checkout> <slug> <lines...> — a ledger whose identity line names the plan
  local dir=$1/$STATE/sdd/$2 slug=$2; shift 2
  mkdir -p "$dir"
  { printf '# SDD ledger — plan: %s/plans/%s.md\n' "$DOCS" "$slug"; printf '%s\n' "$@"; } > "$dir/progress.md"
}
workspace() { # workspace <checkout> <slug> — the plan review's workspace: files, no ledger
  mkdir -p "$1/$STATE/sdd/$2"; printf 'lint\n' > "$1/$STATE/sdd/$2/lint.md"
}
handoff() { # handoff <checkout> — its newest handoff, else its latest.md path (C15)
  local d="$1/$STATE/handoff" f newest=""
  for f in "$d"/*.md; do
    [ -f "$f" ] || continue
    if [ -z "$newest" ] || [ "$f" -nt "$newest" ]; then newest=$f; fi
  done
  printf '%s' "${newest:-$d/latest.md}"
}
seed() { # seed <checkout> <text> — the latest.md another session left
  mkdir -p "$1/$STATE/handoff"; printf '%s\n' "$2" > "$1/$STATE/handoff/latest.md"
}
clear_handoffs() { local c; for c; do rm -f "$c/$STATE/handoff/"*.md; done; } # clear_handoffs <checkout...>
# The session an ns run is, unless SID names another: an --adhoc or --project
# write keys its handoff by it.
S_NS=a1b2c3d4-0000-0000-0000-000000000000
ns() { # ns <dir> <args...> — next-step run in <dir>; sets OUT, ERR, RC
  OUT=$(cd "$1" && CLAUDE_CODE_SESSION_ID=${SID:-$S_NS} timeout 90 bash "$NS" "${@:2}" 2>"$TMP/stderr"); RC=$?
  ERR=$(cat "$TMP/stderr")
}
prompt_of() { awk '/^Paste as the first prompt:/ { on = 1; next } on && /^```$/ { if (f) exit; f = 1; next } f' <<<"$1"; }
launch_of() { awk '/^Launch in / { on = 1; next } on && /^```$/ { if (f) exit; f = 1; next } f' <<<"$1"; }
opening() { # opening <T> <branch text> — the first sentences of every prompt
  printf 'Start in `%s` (%s); its handoff is `%s`. If your working directory is not `%s`, enter it first.' \
    "$1" "$2" "$(handoff "$1")" "$1"
}

# ---------------------------------------------------------------- A1
fixture
W1=$(wt w1)
check "A1: latest in a linked worktree is the worktree's" "$(cd "$W1" && bash "$PATHP" latest)" "$W1/$STATE/handoff/latest.md"
check "A1: latest in the primary is the primary's" "$(cd "$TOP" && bash "$PATHP" latest)" "$TOP/$STATE/handoff/latest.md"

# ---------------------------------------------------------------- A2
fixture
W1=$(wt w1); W2=$(wt w2)
workspace "$TOP" "$PA"; workspace "$TOP" "$PB"
ledger "$W1" "$PA" 'Task 1: complete (commits a..b, review clean)'
ledger "$W2" "$PB" 'Task 1: complete (commits a..b, review clean)'
seed "$TOP" $'# Handoff\n\n## Next session\n\nPrimary sentinel.'
before=$(digest "$(handoff "$TOP")")
ns "$W1" "$DOCS/plans/$PA.md"; rc1=$RC
ns "$W2" "$DOCS/plans/$PB.md"; rc2=$RC
check "A2: both runs exit 0" "$rc1 $rc2" "0 0"
h1=$(cat "$(handoff "$W1")" 2>/dev/null); h2=$(cat "$(handoff "$W2")" 2>/dev/null)
has "A2: the first worktree's handoff holds its block" "$h1" "$DOCS/plans/$PA.md"
has "A2: the first worktree's handoff is a Next session block" "$h1" "## Next session"
lacks "A2: the first worktree's handoff never names the other plan" "$h1" "$PB"
has "A2: the second worktree's handoff holds its block" "$h2" "$DOCS/plans/$PB.md"
lacks "A2: the second worktree's handoff never names the other plan" "$h2" "$PA"
check "A2: the primary's handoff is not modified" "$(digest "$(handoff "$TOP")")" "$before"

# ---------------------------------------------------------------- A3
fixture
W1=$(wt w1)
workspace "$TOP" "$PA"
ledger "$W1" "$PA" 'Task 1: complete (commits a..b, review clean)'
seed "$TOP" $'# Handoff\n\n## Next session\n\nPrimary sentinel.'
before=$(digest "$(handoff "$TOP")")
ns "$TOP" "$DOCS/plans/$PA.md"
check "A3: exits 0" "$RC" 0
has "A3: the block launches in the worktree" "$OUT" "Launch in \`$W1\`:"
check "A3: the worktree's handoff is written" "$([ -f "$(handoff "$W1")" ] && echo yes || echo no)" yes
has "A3: the worktree's handoff holds the block" "$(cat "$(handoff "$W1")" 2>/dev/null)" "$DOCS/plans/$PA.md"
check "A3: the primary's handoff is not modified" "$(digest "$(handoff "$TOP")")" "$before"

# ---------------------------------------------------------------- A4
fixture
WEIRD="$TMP/it's a dir"
mkdir -p "$WEIRD"
# MSYS passes an argument holding a quote to git.exe unconverted, so Git Bash
# needs the native form of this path.
WQN="$WEIRD/wt q"
if command -v cygpath >/dev/null 2>&1; then WQN=$(cygpath -m "$WQN"); fi
git -C "$R" worktree add -q -b wq "$WQN" >/dev/null 2>&1
WQ=$(git -C "$WQN" rev-parse --show-toplevel)
check "A4: fixture: the worktree under a space and a quote exists" "$([ -n "$WQ" ] && [ -d "$WQ" ] && echo yes || echo no)" yes
ESC=${WQ//\'/\'\\\'\'}
if command -v cygpath >/dev/null 2>&1; then
  # Where cygpath is on PATH next-step prints the bare command by design; the
  # checks below cover that form.
  for c in "claude launch command is cd then the command" "bash runs the claude command in T (space and quote)" \
    "codex launch command carries the same cd prefix" "bash runs the codex command in T (space and quote)"; do
    printf 'skip - A4: %s (cygpath on PATH)\n' "$c"
  done
else
  STUB="$TMP/stubbin"; mkdir -p "$STUB"
  for c in claude codex; do printf '#!/bin/sh\npwd\n' > "$STUB/$c"; chmod +x "$STUB/$c"; done
  ns "$WQ" --adhoc --phase build --next go
  cmd=$(launch_of "$OUT")
  check "A4: claude launch command is cd then the command" "$cmd" "cd '$ESC' && claude --model sonnet --effort high"
  check "A4: bash runs the claude command in T (space and quote)" "$(cd "$TMP" && PATH="$STUB:$PATH" timeout 20 bash -c "$cmd")" "$WQ"
  ns "$WQ" --host codex --adhoc --phase build --next go
  cmd=$(launch_of "$OUT")
  case $cmd in "cd '$ESC' && codex "*) pre=yes ;; *) pre=no ;; esac
  check "A4: codex launch command carries the same cd prefix" "$pre" yes
  check "A4: bash runs the codex command in T (space and quote)" "$(cd "$TMP" && PATH="$STUB:$PATH" timeout 20 bash -c "$cmd")" "$WQ"
fi
WIN="$TMP/winbin"; mkdir -p "$WIN"
printf '#!/bin/sh\nfor a; do last=$a; done\nprintf "%%s\\n" "$last"\n' > "$WIN/cygpath"; chmod +x "$WIN/cygpath"
OUT=$(cd "$WQ" && PATH="$WIN:$PATH" CLAUDE_CODE_SESSION_ID=$S_NS timeout 90 bash "$NS" --adhoc --phase build --next go 2>/dev/null)
cmd=$(launch_of "$OUT")
check "A4: with cygpath on PATH the command carries no cd prefix" "$cmd" "claude --model sonnet --effort high"
OUT=$(cd "$WQ" && PATH="$WIN:$PATH" CLAUDE_CODE_SESSION_ID=$S_NS timeout 90 bash "$NS" --host codex --adhoc --phase build --next go 2>/dev/null)
case $(launch_of "$OUT") in "codex "*) pre=no ;; *) pre=yes ;; esac
check "A4: with cygpath on PATH a codex command carries no cd prefix" "$pre" no

# ---------------------------------------------------------------- A5
fixture
W1=$(wt w1)
ledger "$W1" "$PA" 'Task 1: complete (commits a..b, review clean)'
DET="$TMP/det$n"
git -C "$R" worktree add -q --detach "$DET" >/dev/null 2>&1
DETT=$(git -C "$DET" rev-parse --show-toplevel)
SHA7=$(git -C "$DETT" rev-parse --short=7 HEAD)
every=""
a5() { # a5 <mode label> <T> <branch text> <dir> <args...>
  local label=$1 t=$2 b=$3 dir=$4; shift 4
  ns "$dir" "$@"
  check "A5: $label exits 0" "$RC" 0
  PROMPT=$(prompt_of "$OUT")
  every="$every$OUT"
  want=$(opening "$t" "$b")
  check "A5: $label prompt opens with the Start in sentences" "${PROMPT:0:${#want}}" "$want"
}
a5 "plan (resume, ledger in the worktree, run in the primary)" "$W1" "branch w1" "$TOP" "$DOCS/plans/$PA.md"
a5 "plan (start, no ledger yet, run in the worktree)" "$W1" "branch w1" "$W1" "$DOCS/plans/$PB.md"
a5 "draft" "$W1" "branch w1" "$W1" --draft "$DOCS/specs/S.md" --next write_plan
a5 "adhoc" "$W1" "branch w1" "$W1" --adhoc --phase build --next go
a5 "project" "$W1" "branch w1" "$W1" --project
a5 "complete" "$TOP" "branch main" "$W1" --complete "$DOCS/plans/$PA.md"
a5 "kept" "$W1" "branch w1" "$W1" --kept "$DOCS/plans/$PA.md"
a5 "adhoc in a detached checkout" "$DETT" "detached at \`$SHA7\`" "$DETT" --adhoc --phase build --next go
lacks "A5: no prompt contains the retired sentence" "$every" "First enter the existing worktree"

# ---------------------------------------------------------------- A6
fixture
W1=$(wt w1)
ledger "$W1" "$PA" 'Task 1: complete (commits a..b, review clean)' 'Task 2: complete (commits b..c, review clean)'
ns "$W1" --complete "$DOCS/plans/$PA.md"
check "A6: --complete in a worktree exits 0" "$RC" 0
has "A6: --complete launches in the primary" "$OUT" "Launch in \`$TOP\`:"
has "A6: --complete writes the primary's handoff" "$(cat "$(handoff "$TOP")" 2>/dev/null)" "Plan \`$DOCS/plans/$PA.md\` is complete."
check "A6: --complete leaves the worktree's handoff unwritten" "$([ -f "$(handoff "$W1")" ] && echo written || echo none)" none
rm -f "$(handoff "$TOP")"
ns "$W1" --kept "$DOCS/plans/$PA.md"
check "A6: --kept in a worktree exits 0" "$RC" 0
has "A6: --kept launches in the checkout it ran in" "$OUT" "Launch in \`$W1\`:"
has "A6: --kept writes that checkout's handoff" "$(cat "$(handoff "$W1")" 2>/dev/null)" "$DOCS/plans/$PA.md"
check "A6: --kept leaves the primary's handoff unwritten" "$([ -f "$(handoff "$TOP")" ] && echo written || echo none)" none

# ---------------------------------------------------------------- A12
fixture
W1=$(wt w1)
ns "$TOP" --adhoc --phase build --next go
old=$(cat "$(handoff "$TOP")")
printf '%s\n' "${old//Start in /First enter the existing worktree and start in }" > "$(handoff "$TOP")"
before=$(digest "$(handoff "$TOP")")
check "A12: dforge-path latest in the primary names its newest handoff" "$(cd "$TOP" && bash "$PATHP" latest)" "$TOP/$STATE/handoff/adhoc-${S_NS:0:8}.md"
ns "$TOP" --print --latest
check "A12: next-step --print --latest reads the primary's file" "$RC" 0
has "A12: the recomputed block carries the stored Next" "$OUT" "**Next:** go."
check "A12: reading it changed nothing" "$(digest "$(handoff "$TOP")")" "$before"
AUDIT=$(cd "$TOP" && timeout 60 bash "$SCRIPTS/repo-audit" 2>&1)
has "A12: repo-audit lists the primary's handoff" "$AUDIT" "\`$TOP/$STATE/handoff/adhoc-${S_NS:0:8}.md\`"
has "A12: repo-audit shows its Next line" "$AUDIT" "**Next:** go."

# ---------------------------------------------------------------- A13
fixture
W1=$(wt w1)
ledger "$W1" "$PA" 'Task 1: complete (commits a..b, review clean)'
tree() { (cd "$TOP" && find . -path ./.git -prune -o -type f -print | sort; cd "$W1" && find . -path ./.git -prune -o -type f -print | sort | sed 's#^#W1:#'); }
written() { local f; for f in "$TOP/$STATE/handoff/"*.md "$W1/$STATE/handoff/"*.md; do [ -f "$f" ] && printf '%s ' "$f"; done; }
for args in "$DOCS/plans/$PA.md" "--complete $DOCS/plans/$PA.md" "--kept $DOCS/plans/$PA.md" \
  "--draft $DOCS/specs/S.md --next x" "--adhoc --phase build --next x" "--project"; do
  clear_handoffs "$TOP" "$W1"
  files_before=$(tree)
  # shellcheck disable=SC2086
  ns "$W1" --target $args; trc=$RC; target=$OUT
  check "A13: --target exits 0 ($args)" "$trc" 0
  check "A13: --target writes nothing ($args)" "$(tree)" "$files_before"
  # shellcheck disable=SC2086
  ns "$W1" $args
  check "A13: --target names the file the call then writes ($args)" "$(written)" "$target "
done
clear_handoffs "$TOP" "$W1"
rm -rf "$TMP/stubplugin" && cp -R "$SCRIPTS/.." "$TMP/stubplugin"
printf '#!/usr/bin/env bash\nprintf -- "- shell b1 10:00 idle 1m sleep\\n"\nexit 1\n' > "$TMP/stubplugin/scripts/in-flight"
(cd "$W1" && timeout 60 bash "$TMP/stubplugin/scripts/next-step" "$DOCS/plans/$PA.md" >/dev/null 2>&1)
check "A13: with background work a plain run exits 5" "$?" 5
t=$(cd "$W1" && timeout 60 bash "$TMP/stubplugin/scripts/next-step" --target "$DOCS/plans/$PA.md" 2>/dev/null); rc=$?
check "A13: with background work --target exits 0 and names the path" "$rc:$t" "0:$W1/$STATE/handoff/$PA.md"
rm -rf "$TMP/stubplugin"
for args in "" "--adhoc --phase build" "$DOCS/plans/missing.md" "--complete $DOCS/plans/missing.md"; do
  # shellcheck disable=SC2086
  ns "$W1" $args; real=$RC
  # shellcheck disable=SC2086
  ns "$W1" --target $args; tgt=$RC
  check "A13: --target exits as the real call does (${args:-no arguments})" "$tgt" "$real"
  check "A13: that exit is 2 (${args:-no arguments})" "$real" 2
done
ns "$W1" --target --latest
check "A13: --target with --latest is a usage error" "$RC" 2

# ---------------------------------------------------------------- A15
# Each piece of work has its own handoff: --complete and --kept write their
# plan's and leave another live block, with its notes, in its own file.
fixture
W1=$(wt w1)
mkdir -p "$TOP/$STATE/sdd/$PB"
ledger "$TOP" "$PB" 'Task 1: complete (commits a..b, review clean)'
notes() { # notes <handoff file> — keep-me notes above the Next session section
  awk '/^## Next session/ && !d { print "## Notes\nKEEP-ME-NOTES\n"; d = 1 } { print }' "$1" > "$1.new" && mv "$1.new" "$1"
}
ns "$TOP" "$DOCS/plans/$PB.md"
notes "$TOP/$STATE/handoff/$PB.md"
before=$(digest "$TOP/$STATE/handoff/$PB.md")
ns "$TOP" --adhoc --phase build --next go
notes "$TOP/$STATE/handoff/adhoc-${S_NS:0:8}.md"
before_adhoc=$(digest "$TOP/$STATE/handoff/adhoc-${S_NS:0:8}.md")
ns "$W1" --complete "$DOCS/plans/$PA.md"
check "A15: --complete exits 0 beside other live blocks" "$RC" 0
has "A15: --complete writes its plan's own handoff" "$(cat "$TOP/$STATE/handoff/$PA.md")" "Plan \`$DOCS/plans/$PA.md\` is complete."
check "A15: --complete leaves another plan's handoff byte-identical" "$(digest "$TOP/$STATE/handoff/$PB.md")" "$before"
check "A15: --complete leaves an adhoc handoff byte-identical" "$(digest "$TOP/$STATE/handoff/adhoc-${S_NS:0:8}.md")" "$before_adhoc"
lacks "A15: --complete names no displaced block" "$ERR" "replaced the block"
mkdir -p "$W1/$STATE/sdd/$PB"
ledger "$W1" "$PB" 'Task 1: complete (commits a..b, review clean)'
ns "$W1" "$DOCS/plans/$PB.md"
notes "$W1/$STATE/handoff/$PB.md"
before=$(digest "$W1/$STATE/handoff/$PB.md")
ns "$W1" --kept "$DOCS/plans/$PA.md"
check "A15: --kept exits 0 beside another live block" "$RC" 0
has "A15: --kept writes its plan's own handoff" "$(cat "$W1/$STATE/handoff/$PA.md")" "$DOCS/plans/$PA.md"
check "A15: --kept leaves another plan's handoff byte-identical" "$(digest "$W1/$STATE/handoff/$PB.md")" "$before"
# Its own plan's handoff is replaced wholesale, notes and all.
notes "$W1/$STATE/handoff/$PA.md"
ns "$W1" --kept "$DOCS/plans/$PA.md"
check "A15: --kept replaces its own handoff wholesale (notes gone)" "$(grep -c 'KEEP-ME-NOTES' "$W1/$STATE/handoff/$PA.md")" 0
notes "$TOP/$STATE/handoff/$PA.md"
ns "$W1" --complete "$DOCS/plans/$PA.md"
check "A15: --complete replaces its own handoff wholesale (notes gone)" "$(grep -c 'KEEP-ME-NOTES' "$TOP/$STATE/handoff/$PA.md")" 0

# ---------------------------------------------------------------- A7, A16
sidn=0
prompt() { jq -n --arg sid "$1" --arg cwd "$2" '{hook_event_name:"UserPromptSubmit",session_id:$sid,cwd:$cwd,prompt:"go"}' | bash "$START"; }
stop() { # stop <hook script> <session> <cwd> <last message>
  jq -n --arg sid "$2" --arg cwd "$3" --arg msg "$4" \
    '{hook_event_name:"Stop",session_id:$sid,cwd:$cwd,transcript_path:"",stop_hook_active:false,last_assistant_message:$msg}' | bash "$1"
}
decision() { jq -r '.decision // "none"' <<<"${1:-{\}}" 2>/dev/null || echo none; }
begin_turn() { sleep 1; prompt "$1" "$TOP"; sleep 1; }
make_hold() { # make_hold <hook script> [done] — what the hook holds the turn for
  if [ "$1" = "$END" ]; then
    if [ -n "${MIRROR:-}" ]; then
      mkdir -p "$MIRROR/work/sdd/$PB"
      printf '# SDD ledger — plan: %s/plans/%s.md\nTask 1: complete (commits a..b, review clean)\n' "$DOCS" "$PB" > "$MIRROR/work/sdd/$PB/progress.md"
      workspace "$TOP" "$PB"
    elif [ "${2:-}" = done ]; then
      ledger "$TOP" "$PB" 'Task 1: complete (commits a..b, review clean)' 'Task 2: complete (commits b..c, review clean)' 'Final review: clean (commits a1b2c3d..f0e1d2c)'
    else
      ledger "$TOP" "$PB" 'Task 1: complete (commits a..b, review clean)'
    fi
  else
    printf '// change %s\n' "$RANDOM" >> "$TOP/src/App.tsx"
    git -C "$TOP" commit -qam "ui change $RANDOM"
  fi
}
HANDTYPED=$'Stopping here.\n\n## Next session\n\n**Status:** typed by hand.\n**Next:** typed by hand.'
hooks="$END $UIEND"
names=("turn-end.sh" "ui-turn-end.sh")

a7() { # a7 <label> <hook> <plan to run next-step for>
  local label=$1 hook=$2 plan=$3 sid
  sid="s$((sidn += 1))"
  begin_turn "$sid"; make_hold "$hook"
  check "A7: $label: a turn with no block is held" "$(decision "$(stop "$hook" "$sid" "$TOP" 'Done.')")" block
  ns "$TOP" "$DOCS/plans/$plan.md"
  check "A7: $label: next-step exits 0" "$RC" 0
  check "A7: $label: ending on the block next-step wrote is released" "$(stop "$hook" "$sid" "$TOP" "$OUT")" ""
  sid="s$((sidn += 1))"
  begin_turn "$sid"; make_hold "$hook"
  check "A7: $label: a hand-typed block with no handoff written this turn is held" "$(decision "$(stop "$hook" "$sid" "$TOP" "$HANDTYPED")")" block
}
for hook in "$END" "$UIEND"; do
  nm=$(basename "$hook")
  fixture
  W1=$(wt w1)
  ledger "$W1" "$PA" 'Task 1: complete (commits a..b, review clean)'
  a7 "$nm, next-step writes a worktree's handoff (local progress)" "$hook" "$PA"
  check "A7: $nm: it was the worktree's handoff that next-step wrote" "$([ -f "$(handoff "$W1")" ] && echo yes || echo no)" yes
  if [ "$PLUGIN" = dforge ]; then
    fixture
    HOME_SAVE=$HOME; export HOME="$TMP/hm$n"; mkdir -p "$HOME"
    W1=$(wt w1)
    MIRROR=$(stores_home "$HOME" "$R" proj local darkmem)
    mkdir -p "$MIRROR/work/sdd/$PA"
    printf '# SDD ledger — plan: %s/plans/%s.md\nTask 1: complete (commits a..b, review clean)\n' "$DOCS" "$PA" > "$MIRROR/work/sdd/$PA/progress.md"
    workspace "$TOP" "$PA"; workspace "$W1" "$PA"
    a7 "$nm, darkmem, next-step writes a worktree's handoff" "$hook" "$PA"
    check "A7: $nm: darkmem: the worktree's handoff stays local" "$([ -f "$(handoff "$W1")" ] && echo yes || echo no)" yes
    a7 "$nm, darkmem, the block is in the mirror's file" "$hook" "$PB"
    check "A7: $nm: darkmem: the primary's block is in the mirror" "$([ -f "$MIRROR/work/handoff/$PB.md" ] && echo yes || echo no)" yes
    export HOME=$HOME_SAVE; MIRROR=""
  fi
done

a16() { # a16 <hook>
  local hook=$1 nm sid own other othernext
  nm=$(basename "$hook")
  fixture
  W2=$(wt w2)
  # i: the session's own block, then another worktree writes a newer handoff
  sid="s$((sidn += 1))"
  begin_turn "$sid"; make_hold "$hook"
  ns "$TOP" "$DOCS/plans/$PB.md"; own=$OUT
  sleep 1
  ns "$W2" --adhoc --phase build --next 'other session work'; other=$OUT
  check "A16: $nm: another worktree's newer handoff exists" "$([ "$(handoff "$W2")" -nt "$(handoff "$TOP")" ] && echo newer || echo older)" newer
  check "A16: $nm: the session's own next-step block still releases" "$(stop "$hook" "$sid" "$TOP" "$own")" ""
  # ii: a completed plan with no next-step run
  sid="s$((sidn += 1))"
  begin_turn "$sid"; make_hold "$hook" done
  sleep 1
  ns "$W2" --adhoc --phase build --next 'other session work again'
  check "A16: $nm: a turn that ran no next-step is still held" "$(decision "$(stop "$hook" "$sid" "$TOP" 'All done, nothing left.')")" block
  # iii: a hand-typed block carrying only the other block's Next line
  sid="s$((sidn += 1))"
  begin_turn "$sid"; make_hold "$hook"
  sleep 1
  ns "$W2" --adhoc --phase build --next 'third session work'; other=$OUT
  othernext=$(grep '^\*\*Next:\*\*' <<<"$other")
  check "A16: $nm: a hand-typed block with only the other block's Next line is held" \
    "$(decision "$(stop "$hook" "$sid" "$TOP" "$(printf 'Stopping here.\n\n## Next session\n\n**Status:** typed by hand.\n%s\n' "$othernext")")")" block
}
a16 "$END"
a16 "$UIEND"

# ---------------------------------------------------------------- A8
AR="$SCRIPTS/auto-run"
beat() { # a live cockpit heartbeat for a session
  local f="$HOME/.claude/$PLUGIN/sessions/cockpit/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
  mkdir -p "$(dirname "$f")"; printf '%s\n' "$(date +%s)" > "$f"
}
ar() { # ar <dir> <args...>
  beat s-8
  (cd "$1" && timeout 60 bash "$AR" --session s-8 "${@:2}" 2>&1)
}
fixture
W1=$(wt w1)
ns "$TOP" "$DOCS/plans/$PA.md"
has "A8: the primary's handoff holds the plan's start block" "$(cat "$(handoff "$TOP")")" "No ledger exists yet"
ar "$TOP" start --spec "$DOCS/specs/S.md" >/dev/null
ar "$TOP" attach --plan "$DOCS/plans/$PA.md" >/dev/null
ledger "$W1" "$PA" 'Task 1: complete (commits a..b, review clean)'
ns "$W1" "$DOCS/plans/$PA.md"
has "A8: the worktree's handoff holds the resume block" "$(cat "$(handoff "$W1")")" "Resume at Task 2"
arstate="$TOP/$STATE/sdd/auto-run.json"
for where in "$W1" "$TOP" "$TOP/docs"; do
  case $where in "$W1") label="in the worktree" ;; "$TOP") label="in the primary" ;; *) label="from a subdirectory of the primary" ;; esac
  out=$(ar "$where" clear --phase); rc=$?
  check "A8: clear --phase $label exits 0" "$rc" 0
  stored=$(jq -r '.resumePrompt // ""' "$arstate")
  want=$(opening "$W1" "branch w1")
  check "A8: clear --phase $label stores the worktree's first prompt" "${stored:0:${#want}}" "$want"
  has "A8: clear --phase $label stores the resume text" "$stored" "Resume at Task 2"
  lacks "A8: clear --phase $label never reads the primary's start block" "$stored" "No ledger exists yet"
  ar "$where" rebind --to s-8 >/dev/null; ar "$where" resumed >/dev/null
done

# ---------------------------------------------------------------- A10
fixture
W1=$(wt w1); W2=$(wt w2); W3=$(wt w3); W4=$(wt w4); W5=$(wt w5)
SID=a1000001-0000-0000-0000-000000000000 ns "$W1" --adhoc --phase build --next own-work
SID=a1000002-0000-0000-0000-000000000000 ns "$W2" --adhoc --phase build --next other-work
SID=a1000003-0000-0000-0000-000000000000 ns "$W3" --adhoc --phase build --next stale-work
SID=a1000004-0000-0000-0000-000000000000 ns "$TOP" --adhoc --phase build --next primary-work
rm -rf "$W5"
touch -d '4 days ago' "$(handoff "$W3")"
sed -i "s/at=[0-9]*/at=$(( $(date +%s) - 3 * 86400 ))/" "$(handoff "$W2")"
touch -d '2 days ago' "$(handoff "$W2")"
# The session's own handoff is the one its marker names (spec 2026-11-20 §5).
AUDIT=$(cd "$W1" && CLAUDE_CODE_SESSION_ID=a1000001-0000-0000-0000-000000000000 timeout 60 bash "$SCRIPTS/repo-audit" 2>&1)
SEC=$(sed -n '/^## Handoff/,/^## /p' <<<"$AUDIT" | sed '$d')
for c in "$W1" "$TOP" "$W2" "$W3"; do
  has "A10: repo-audit lists $(basename "$c")'s handoff" "$SEC" "\`$(handoff "$c")\`"
done
lacks "A10: a checkout with no handoff gets no entry" "$SEC" "\`$(handoff "$W4")\`"
has "A10: a prunable worktree gets a skip line" "$SEC" "skipped \`$W5\`"
lacks "A10: a prunable worktree gets no entry" "$SEC" "\`$(handoff "$W5")\`"
check "A10: the prunable worktree is named once in the section" "$(grep -cF "$W5" <<<"$SEC")" 1
own_at=$(grep -nF "\`$(handoff "$W1")\`" <<<"$SEC" | head -1 | cut -d: -f1)
other_at=$(grep -nF "\`$(handoff "$W2")\`" <<<"$SEC" | head -1 | cut -d: -f1)
top_at=$(grep -nF "\`$(handoff "$TOP")\`" <<<"$SEC" | head -1 | cut -d: -f1)
check "A10: the session's own entry comes first" "$([ "$own_at" -lt "$other_at" ] && [ "$own_at" -lt "$top_at" ] && echo first || echo "$own_at,$other_at,$top_at")" first
check "A10: the own entry is recomputed" "$(grep -c '^- recomputed' <<<"$SEC")" 1
has "A10: the own entry carries its Next line" "$SEC" "**Next:** own-work."
has "A10: the own entry carries the commit count since it was written" "$SEC" "Commits on this checkout's HEAD since it was written: 0"
entry() { sed -n "/\`$(sed 's/[][\.*^$/]/\\&/g' <<<"$(handoff "$1")")\`/,/^- \*\*Next/p" <<<"$SEC"; }
e2=$(entry "$W2")
has "A10: another checkout's entry is marked stored" "$e2" "stored"
has "A10: another checkout's entry carries its Status line" "$e2" "**Status:** Unplanned work"
has "A10: another checkout's entry carries its Next line" "$e2" "**Next:** other-work."
check "A10: another checkout's entry shows its age (2 days)" "$(grep -cE ', 2d old, unclaimed$' <<<"$e2")" 1
check "A10: another checkout's entry is not recomputed" "$(grep -c '^- recomputed' <<<"$e2")" 0
start_ctx() { # start_ctx <source> <cwd> [session]
  jq -n --arg cwd "$2" --arg src "$1" --arg sid "${3:-s-10}" '{hook_event_name:"SessionStart",session_id:$sid,transcript_path:"",cwd:$cwd,source:$src}' \
    | bash "$SCRIPTS/session-start.sh" | jq -r '.hookSpecificOutput.additionalContext // .additional_context // empty'
}
CTX=$(start_ctx startup "$W1")
# Spec 2026-11-20 A10: every unclaimed handoff younger than three days (W1, W2, the primary; not W3).
has "A10: the startup context counts the open handoffs" "$CTX" "3 open handoffs (scripts/repo-audit lists them)."
# The snapshot shows the compacted session's own handoff: W1's, which its writer's marker names.
SNAP=$(start_ctx compact "$W1" a1000001-0000-0000-0000-000000000000)
has "A10: the compaction snapshot shows the session checkout's handoff" "$SNAP" "own-work"
lacks "A10: the compaction snapshot omits another worktree's handoff" "$SNAP" "other-work"
lacks "A10: the compaction snapshot omits the primary's handoff" "$SNAP" "primary-work"

# ---------------------------------------------------------------- A11, A14 (dforge only)
fixture
HOME_SAVE=$HOME; export HOME="$TMP/hm$n"; mkdir -p "$HOME"
W1=$(wt w1)
MIRROR=$(stores_home "$HOME" "$R" proj local darkmem)
check "A11: darkmem: a linked worktree's handoff is local" "$(cd "$W1" && bash "$PATHP" latest)" "$W1/$STATE/handoff/latest.md"
check "A11: darkmem: the primary's handoff is the mirror's file" "$(cd "$TOP" && bash "$PATHP" latest)" "$MIRROR/work/handoff/latest.md"

# A14: the plan's workspace is in a worktree, the primary holds one too
mkdir -p "$MIRROR/work/sdd/$PA"
printf '# SDD ledger — plan: %s/plans/%s.md\nTask 1: complete (commits a..b, review clean)\n' "$DOCS" "$PA" > "$MIRROR/work/sdd/$PA/progress.md"
workspace "$W1" "$PA"; workspace "$TOP" "$PA"
mkdir -p "$MIRROR/work/handoff"
printf '# Handoff\n\n## Next session\n\nPrimary mirror sentinel.\n' > "$MIRROR/work/handoff/latest.md"
before=$(digest "$MIRROR/work/handoff/latest.md")
ns "$TOP" "$DOCS/plans/$PA.md"
check "A14: next-step exits 0" "$RC" 0
check "A14: the worktree's handoff is written" "$([ -f "$(handoff "$W1")" ] && echo yes || echo no)" yes
has "A14: the worktree's handoff holds the block" "$(cat "$(handoff "$W1")" 2>/dev/null)" "$DOCS/plans/$PA.md"
check "A14: the primary's handoff (the mirror's file) is not modified" "$(digest "$MIRROR/work/handoff/latest.md")" "$before"
has "A14: the block launches in the worktree" "$OUT" "Launch in \`$W1\`:"
PROMPT=$(prompt_of "$OUT")
has "A14: the prompt names the worktree" "$PROMPT" "Start in \`$W1\`"
lacks "A14: the prompt does not name the primary" "$PROMPT" "Start in \`$TOP\`"
lacks "A14: the prompt names no handoff in the mirror" "$PROMPT" "$MIRROR/work/handoff"
export HOME=$HOME_SAVE

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
