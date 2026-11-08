#!/usr/bin/env bash
# Acceptance QA for "Auto runs follow the worktree setting": each statement
# A1-A21 of docs/dforge/specs/2026-11-08-auto-run-worktree-setting-design.md
# is checked through the CLI (scripts/auto-run) in throwaway repositories, or,
# for the skill and reference statements, through the texts themselves.
# ONLY="A3 A4" runs just those statements.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$HERE/.."
AR="$PLUGIN/scripts/auto-run"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
want() { [ -z "${ONLY:-}" ] && return 0; case " $ONLY " in *" $1 "*) return 0 ;; esac; return 1; }

TMP="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export MSYS_NO_PATHCONV=1 DFORGE_NO_SETTINGS=1 GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset DFORGE_BUDGET DFORGE_JQ DFORGE_FLOCK DR_SUPERPOWERS_BUDGET DR_SUPERPOWERS_JQ CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR

SPEC=docs/dforge/specs/2026-10-13-widget-design.md
REPO="" CWD="" STATE=""

beat() { # the heartbeat a live cockpit writes
  local f="$HOME/.claude/dforge/sessions/cockpit/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$(date +%s)" > "$f"
}
ar() { beat s-1; (cd "$CWD" && bash "$AR" --session s-1 "$@"); }
gi() { git -C "$CWD" "$@"; }
fld() { jq -r --arg f "$1" '.[$f] | tostring' "$STATE"; }
snap() { jq -c '[.branch, .branchBase, .carried, .isolation, .phase, .base]' "$STATE"; }

newrepo() { # newrepo <name>: a repository on main with tracked files
  REPO="$TMP/$1" CWD="$TMP/$1" STATE="$TMP/$1/.dforge/sdd/auto-run.json"
  git init -q -b main "$REPO"
  mkdir -p "$REPO/tracked" "$REPO/docs"
  local f
  for f in tracked/a.txt tracked/b.txt tracked/c.txt docs/notes.md rename-me.txt; do
    printf 'base %s\n' "$f" > "$REPO/$f"
  done
  git -C "$REPO" add .
  git -C "$REPO" commit -q -m base
}
startrun() { # startrun [start flags]: start a run in CWD, commit its register, attach a plan
  ar start --spec "$SPEC" --register docs/r.md "$@" >/dev/null
  git -C "$CWD" add -A -- docs
  git -C "$CWD" diff --cached --quiet || git -C "$CWD" commit -q -m register
  ar attach --plan docs/plan.md
}
inplace_branch() { # what Setup does: the run's branch, then setup-branch
  gi switch -q -c auto/widget
  ar setup-branch auto/widget
}
dirty() { # dirty [plain]: a modified file, untracked files, an unstaged rename (intent-to-add unless plain: git cannot merge past one)
  printf 'changed\n' >> "$CWD/tracked/a.txt"
  printf 'new\n' > "$CWD/loose.txt"
  mkdir -p "$CWD/newdir/deep"
  printf 'x\n' > "$CWD/newdir/x.txt"
  printf 'y\n' > "$CWD/newdir/deep/y.txt"
  mv "$CWD/rename-me.txt" "$CWD/renamed.txt"
  [ "${1:-}" = plain ] || gi add -N renamed.txt
}
DIRTY_WANT=$(printf '%s\n' loose.txt newdir/deep/y.txt newdir/x.txt rename-me.txt renamed.txt tracked/a.txt | LC_ALL=C sort)
fingerprint() { # the content of every dirty path and the full status
  local p
  while IFS= read -r p; do
    if [ -e "$CWD/$p" ]; then printf '%s %s\n' "$(cksum < "$CWD/$p")" "$p"; else printf 'absent %s\n' "$p"; fi
  done <<<"$DIRTY_WANT"
  git -C "$CWD" status --porcelain=v1 -z --untracked-files=all | tr '\0' '|'
}

t_A1() {
  newrepo a1; startrun --isolation in-place
  check "A1: start --isolation in-place records isolation \"in-place\"" "$(jq -c '.isolation' "$STATE")" '"in-place"'
  check "A1: status prints isolation in-place" "$(ar status | grep -c 'isolation in-place')" "1"
  newrepo a1w; startrun --isolation worktree
  check "A1: start --isolation worktree records isolation \"worktree\"" "$(jq -c '.isolation' "$STATE")" '"worktree"'
}

t_A2() {
  newrepo a2; startrun
  check "A2: a start without --isolation reads as isolation worktree" "$(ar status | grep -c 'isolation worktree')" "1"
  jq 'del(.isolation)' "$STATE" > "$STATE.new" && mv "$STATE.new" "$STATE"
  check "A2: the old state file has no isolation field" "$(jq 'has("isolation")' "$STATE")" "false"
  check "A2: a state file without isolation reads as isolation worktree" "$(ar status | grep -c 'isolation worktree')" "1"
  gi switch -q -c feature
  ar phase execute >/dev/null 2>&1; local status=$?
  check "A2: an old run behaves as a worktree run: the primary checkout on another branch is refused" "$status:$(fld phase)" "4:spec"
  gi switch -q main
  gi worktree add -q -b side "$TMP/a2-side"
  CWD="$TMP/a2-side" ar phase execute >/dev/null 2>&1; status=$?
  check "A2: an old run behaves as a worktree run: a linked worktree passes" "$status:$(fld phase)" "0:execute"
  CWD=$REPO
}

t_A3() {
  newrepo a3
  local v out status
  for v in elsewhere In-Place inplace worktrees ''; do
    out=$(ar start --spec "$SPEC" --register docs/r.md --isolation "$v" 2>&1); status=$?
    check "A3: --isolation '$v' exits 2" "$status" "2"
    check "A3: --isolation '$v' writes no state file" "$([ -e "$STATE" ] && echo exists || echo none)" "none"
  done
  newrepo a3b; startrun --isolation in-place
  local before; before=$(cksum < "$STATE")
  ar start --spec "$SPEC" --register docs/r.md --isolation elsewhere --force >/dev/null 2>&1; status=$?
  check "A3: a bad value over a live run exits 2" "$status" "2"
  check "A3: a bad value over a live run leaves its state alone" "$(cksum < "$STATE")" "$before"
}

t_A4() {
  local iso status p0
  for iso in in-place worktree; do
    newrepo "a4-$iso"; startrun --isolation "$iso"
    p0=$(fld phase)
    ar phase execute >/dev/null 2>&1; status=$?
    check "A4: $iso run, primary checkout on its base: exit 4, phase unchanged" "$status:$(fld phase)" "4:$p0"

    newrepo "a4s-$iso"
    gi worktree add -q -b side "$TMP/a4s-$iso-side"
    CWD="$TMP/a4s-$iso-side"; startrun --isolation "$iso"
    p0=$(fld phase)
    check "A4: $iso run started in a linked worktree has that branch as its base" "$(fld base)" "side"
    ar phase execute >/dev/null 2>&1; status=$?
    check "A4: $iso run, linked worktree on its base: exit 4, phase unchanged" "$status:$(fld phase)" "4:$p0"
  done
}

t_A5() {
  newrepo a5; startrun --isolation in-place
  inplace_branch >/dev/null 2>&1; local status=$?
  check "A5: setup-branch on the new branch exits 0" "$status" "0"
  ar phase execute >/dev/null 2>&1; status=$?
  check "A5: in-place run, primary checkout, recorded branch: phase execute exits 0" "$status:$(fld phase)" "0:execute"
}

t_A6() {
  local where status p0
  for where in main other; do
    newrepo "a6p-$where"; startrun --isolation in-place
    gi branch other
    inplace_branch >/dev/null 2>&1
    gi switch -q "$where"
    p0=$(fld phase)
    ar phase execute >/dev/null 2>&1; status=$?
    check "A6: in-place run, HEAD on $where: phase execute exits 4, phase unchanged" "$status:$(fld phase)" "4:$p0"

    newrepo "a6t-$where"; startrun --isolation in-place
    gi branch other
    inplace_branch >/dev/null 2>&1
    ar phase execute >/dev/null 2>&1
    check "A6: precondition: execute phase on the recorded branch" "$(fld phase)" "execute"
    gi switch -q "$where"
    ar task-complete >/dev/null 2>&1; status=$?
    check "A6: in-place run, HEAD on $where: task-complete exits 5, run stopped" "$status:$(fld active)" "5:false"
  done
}

t_A7() {
  local status p0 flag
  for flag in "--isolation worktree" ""; do
    newrepo a7; startrun $flag
    gi switch -q -c feature
    p0=$(fld phase)
    ar phase execute >/dev/null 2>&1; status=$?
    check "A7: worktree run (${flag:-no flag}), primary checkout on a non-base branch: exit 4, phase unchanged" "$status:$(fld phase)" "4:$p0"
    rm -rf "$REPO"
  done
}

t_A8() {
  local iso status p0
  for iso in in-place worktree; do
    newrepo "a8-$iso"
    gi checkout -q --detach
    startrun --isolation "$iso"
    check "A8: $iso run started on a detached HEAD has no base" "$(fld base)" "null"
    p0=$(fld phase)
    ar phase execute >/dev/null 2>&1; status=$?
    check "A8: $iso run, detached HEAD in the primary checkout: exit 4, phase unchanged" "$status:$(fld phase)" "4:$p0"
  done
  newrepo a8b
  gi checkout -q --detach
  startrun --isolation in-place
  gi switch -q -c auto/widget
  ar setup-branch auto/widget >/dev/null 2>&1; status=$?
  check "A8: setup-branch on the new branch exits 0 with no base" "$status" "0"
  ar phase execute >/dev/null 2>&1; status=$?
  check "A8: no base, on the recorded branch: phase execute exits 0" "$status:$(fld phase)" "0:execute"
}

t_A9() {
  local status head0
  newrepo a9; startrun --isolation in-place; dirty
  head0=$(gi rev-parse HEAD)
  gi switch -q -c auto/widget
  ar setup-branch auto/widget >/dev/null 2>&1; status=$?
  check "A9: setup-branch exits 0 on a dirty checkout" "$status" "0"
  check "A9: records the branch" "$(fld branch)" "auto/widget"
  check "A9: records branchBase, the commit the branch was created at" "$(fld branchBase)" "$head0"
  check "A9: carried holds every modified and untracked path, both sides of the rename, each file of an untracked directory" \
    "$(jq -r '.carried[]' "$STATE" | LC_ALL=C sort)" "$DIRTY_WANT"
  check "A9: carried lists them one per line" "$(ar carried | LC_ALL=C sort)" "$DIRTY_WANT"
  check "A9: status names the branch" "$(ar status | grep -c 'branch auto/widget')" "1"

  newrepo a9r; startrun --isolation in-place; dirty
  gi switch -q -c auto/widget
  local before; before=$(snap)
  ar setup-branch auto/other >/dev/null 2>&1; status=$?
  check "A9: HEAD not on <name>: exit 4" "$status" "4"
  check "A9: HEAD not on <name>: nothing recorded" "$(snap)" "$before"
  check "A9: HEAD not on <name>: no branch, branchBase or carried" "$(fld branch):$(fld branchBase):$(fld carried)" "null:null:null"
  gi switch -q main
  before=$(snap)
  ar setup-branch main >/dev/null 2>&1; status=$?
  check "A9: <name> is the run's base: exit 4" "$status" "4"
  check "A9: <name> is the run's base: nothing recorded" "$(snap)" "$before"
  check "A9: <name> is the run's base: no branch, branchBase or carried" "$(fld branch):$(fld branchBase):$(fld carried)" "null:null:null"
}

# A run with a carried a.txt and u.txt, on its recorded branch, in the execute phase.
carried_run() {
  newrepo "$1"; startrun --isolation in-place
  printf 'changed\n' >> "$CWD/tracked/a.txt"
  printf 'untracked\n' > "$CWD/u.txt"
  inplace_branch >/dev/null 2>&1
  ar phase execute >/dev/null 2>&1
}

t_A10() {
  local status
  carried_run a10ok
  printf 'task\n' >> "$CWD/tracked/b.txt"
  gi add tracked/b.txt; gi commit -q -m task
  ar task-complete >/dev/null 2>&1; status=$?
  check "A10: a commit touching only other paths: task-complete exits 0, run goes on" "$status:$(fld active)" "0:true"

  carried_run a10mod
  printf 'task\n' >> "$CWD/tracked/b.txt"
  gi add tracked/a.txt tracked/b.txt; gi commit -q -m task
  ar task-complete >/dev/null 2>&1; status=$?
  check "A10: a commit including a carried modified file: task-complete exits 5" "$status:$(fld active)" "5:false"
  check "A10: the stop reason names the path" "$(fld stopped | grep -c 'tracked/a.txt')" "1"

  carried_run a10new
  gi add u.txt; gi commit -q -m task
  ar task-complete >/dev/null 2>&1; status=$?
  check "A10: a commit including a carried untracked file: task-complete exits 5" "$status:$(fld active)" "5:false"
  check "A10: the stop reason names the path" "$(fld stopped | grep -c 'u.txt')" "1"

  carried_run a10two
  printf 'task\n' >> "$CWD/tracked/b.txt"
  gi add tracked/b.txt; gi commit -q -m first
  gi add tracked/a.txt; gi commit -q -m second
  ar task-complete >/dev/null 2>&1; status=$?
  check "A10: a carried path in a later commit since branchBase: exit 5" "$status:$(fld active)" "5:false"
}

t_A11() {
  local status before after p head0 bad=0
  newrepo a11; startrun --isolation in-place; dirty plain
  before=$(fingerprint)
  head0=$(gi rev-parse HEAD)
  inplace_branch >/dev/null 2>&1; status=$?
  check "A11: setup-branch exits 0" "$status" "0"
  ar phase execute >/dev/null 2>&1; status=$?
  check "A11: phase execute exits 0" "$status" "0"
  printf 'task\n' >> "$CWD/tracked/b.txt"
  gi add tracked/b.txt; gi commit -q -m task
  ar task-complete >/dev/null 2>&1; status=$?
  check "A11: task-complete after a non-carried commit exits 0" "$status:$(fld active)" "0:true"
  gi switch -q main
  gi merge -q --no-ff -m merge auto/widget >/dev/null 2>&1; status=$?
  check "A11: the merge into the base succeeds" "$status" "0"
  gi branch -d auto/widget >/dev/null 2>&1; status=$?
  check "A11: git branch -d succeeds" "$status" "0"
  after=$(fingerprint)
  check "A11: every carried path and the status are byte for byte as before setup" "$after" "$before"
  while IFS= read -r p; do
    [ "$(gi log "$head0..main" --name-only --format= -- "$p" | wc -l | tr -d ' ')" = 0 ] || bad=1
  done <<<"$DIRTY_WANT"
  check "A11: no carried path is in any commit the run added to the base" "$bad" "0"
  check "A11: the task's file did land on the base" "$(gi show main:tracked/b.txt | tail -1)" "task"
}

t_A12() {
  local iso status
  for iso in worktree in-place; do
    newrepo "a12-$iso"
    gi worktree add -q -b side "$TMP/a12-$iso-side"
    CWD="$TMP/a12-$iso-side"; startrun --isolation "$iso"
    ar phase execute >/dev/null 2>&1; status=$?
    check "A12: $iso run, linked worktree on its base: phase execute is refused first" "$status" "4"
    gi switch -q -c auto/widget
    ar setup-branch auto/widget >/dev/null 2>&1; status=$?
    check "A12: $iso run: setup-branch exits 0 in the linked worktree" "$status" "0"
    ar phase execute >/dev/null 2>&1; status=$?
    check "A12: $iso run: after Setup, phase execute exits 0" "$status:$(fld phase)" "0:execute"
  done
}

# Text helpers: the file at HEAD, an extract between two line patterns, a flat extract.
txt() { cat "$PLUGIN/$1"; }
between() { # between <file> <start regexp> <end regexp>: from the first start line up to the next end line
  awk -v s="$2" -v e="$3" '
    !on && $0 ~ s { on = 1; print; next }
    on && $0 ~ e { exit }
    on { print }' "$PLUGIN/$1"
}
flat() { tr '\n' ' ' | tr -s ' '; }
has() { # has <text> <literal>
  case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac
}
before_in() { # before_in <text> <first> <second>: <first> occurs ahead of <second>
  local pre=${1%%"$3"*}
  has "$pre" "$2"
}

t_A13() {
  local file=skills/using-git-worktrees/SKILL.md body
  body=$(between "$file" '^\*\*In an auto run\*\*' '^Outside an auto run:' | flat)
  check "A13: the auto-run paragraph exists" "$([ -n "$body" ] && echo yes || echo no)" "yes"
  check "A13: reads the run's state with scripts/auto-run status" "$(has "$body" 'scripts/auto-run status')" "yes"
  check "A13: not the worktree setting" "$(has "$body" 'not the `worktree` setting')" "yes"
  check "A13: done before the linked-worktree check, in any checkout" "$(has "$body" 'before the linked-worktree check')$(has "$body" 'in any checkout')" "yesyes"
  check "A13: switches to a recorded branch when HEAD is elsewhere" "$(has "$body" 'branch <name>')$(has "$body" 'git switch <name>')" "yesyes"
  check "A13: creates auto/<plan slug> with git switch -c" "$(has "$body" 'git switch -c auto/<plan slug>')" "yes"
  check "A13: with a collision suffix" "$(has "$body" '-2')" "yes"
  check "A13: HEAD is the base or detached" "$(has "$body" 'the run'"'"'s base')$(has "$body" 'detached')" "yesyes"
  check "A13: under in-place, or in a linked worktree" "$(has "$body" 'isolation in-place')$(has "$body" 'linked worktree')" "yesyes"
  check "A13: calls setup-branch" "$(has "$body" 'scripts/auto-run setup-branch <name>')" "yes"
  check "A13: stops the run on staged changes" "$(has "$body" 'staged changes in this checkout: <paths>')$(has "$body" 'scripts/auto-run stop --reason')" "yesyes"
  check "A13: creates the worktree without asking under worktree in the primary checkout" \
    "$(has "$body" 'Under `isolation worktree` in the primary checkout, create the worktree without asking')" "yes"
}

t_A14() {
  local file=skills/brainstorming/references/auto-by-default.md s5 s6 off
  s5=$(between "$file" '^5\. \*\*The spec review' '^6\. \*\*Start the run' | flat)
  s6=$(between "$file" '^6\. \*\*Start the run' '^7\. \*\*Approve, keep' | flat)
  check "A14: step 5 asks the worktree question only when the worktree setting is ask" "$(has "$s5" 'when the `worktree` setting is `ask`')" "yes"
  check "A14: the question offers the isolated worktree and the in-place branch" \
    "$(has "$s5" '**Isolated worktree (Recommended)**')$(has "$s5" '**Work in place on a new branch')" "yesyes"
  check "A14: asked in the last call, beside the approval question" "$(has "$s5" 'in the last call')$(has "$s5" 'beside the approval question')" "yesyes"
  check "A14: the question comes before the approval options in the list" "$(before_in "$s5" 'Worktree: <worktree|in-place>' '**Approve and run unattended**')" "yes"
  check "A14: the answer is a Worktree: <worktree|in-place> line in ## Decisions" "$(has "$s5" '`Worktree: <worktree|in-place>` line in `## Decisions`')" "yes"
  check "A14: step 6 passes --isolation" "$(has "$s6" '--isolation <worktree|in-place>')" "yes"
  check "A14: step 6 takes the value from the line under ask, and from the setting under always and never" \
    "$(has "$s6" 'under `ask`')$(has "$s6" '`worktree` under `always`')$(has "$s6" '`in-place` under `never`')" "yesyesyes"

  off=$(txt skills/brainstorming/references/auto-run-offer.md | flat)
  check "A14: the offer keeps its two options by default" "$(has "$off" '1. Yes, run unattended')$(has "$off" '2. No, keep the normal stops')" "yesyes"
  check "A14: under worktree=ask the offer has three options" \
    "$(has "$off" 'When the `worktree` setting is `ask`')$(has "$off" '1. Yes, in an isolated worktree')$(has "$off" '2. Yes, in place on a new branch (leave this checkout alone until the run finishes)')$(has "$off" '3. No, keep the normal stops')" "yesyesyesyes"
  check "A14: the offer passes --isolation, in-place for option 2" "$(has "$off" 'scripts/auto-run start --spec')$(has "$off" '--isolation <worktree|in-place>')$(has "$off" '--isolation in-place')" "yesyesyes"
}

t_A15() {
  local hits
  # A clause is the text between a period, comma, semicolon, colon or parenthesis.
  hits=$(cd "$PLUGIN" && { find skills reference -name '*.md'; echo README.md; echo config/schema.mjs; } | while IFS= read -r f; do
    tr '.,;:()' '\n\n\n\n\n\n' < "$f" | grep -iE -e '`(worktree=)?never`.*(creat|isolat|mak(e|es|ing) (a|the|it))' -e '(creat|isolat)[a-z]* .*`(worktree=)?never`' \
      -e '(creates?|making|makes) (it|the (execution )?worktree|a worktree).*every auto.?run' -e 'worktree. setting is not read' | sed "s|^|$f: |"
  done)
  check "A15: no skill or reference text says an auto run creates the worktree when worktree=never is set" "$hits" ""
  check "A15: the corrected paragraph says what never does" "$(txt skills/using-git-worktrees/SKILL.md | grep -c 'worktree=never` works in place')" "1"
  check "A15: the README says an in-place auto run for never" "$(txt README.md | grep -c '`never` works in this checkout')" "1"
}

t_A16() {
  local lane plan
  lane=$(between reference/executor-lane.md '^\*\*Reserve an exclusive linked worktree' '^Stop other' | flat)
  check "A16: executor-lane.md refuses the primary checkout for the lane" "$(has "$lane" 'Refuse the primary checkout')" "yes"
  check "A16: runs task-step start first" "$(has "$lane" 'run `task-step start`')" "yes"
  check "A16: then neither the gate nor the wrapper, and the session review loop" "$(has "$lane" 'neither the gate nor the wrapper')$(has "$lane" 'session review loop')" "yesyes"
  check "A16: task-step start comes before the neither-gate-nor-wrapper step" "$(before_in "$lane" 'task-step start' 'neither the gate nor the wrapper')" "yes"
  check "A16: records the executor unavailable line" "$(has "$lane" 'Task <N>: implementer inline (assigned; base <sha7>; executor <id> unavailable - no linked worktree)')" "yes"
  check "A16: continuing in the primary checkout is limited to worktree runs" "$(txt reference/executor-lane.md | grep -c 'In a worktree run the user can continue in the primary checkout')" "1"
  check "A16: no other line lets the user continue in the primary checkout unqualified" \
    "$(txt reference/executor-lane.md | grep -i 'user can continue in the primary checkout' | grep -vc 'worktree run')" "0"
  plan=$(txt skills/writing-plans/references/auto-run-plan.md | flat)
  check "A16: auto-run-plan.md ticks no executor when isolation is in-place" "$(has "$plan" 'tick nothing when `scripts/auto-run status` prints `isolation in-place`')" "yes"
}

t_A17() {
  local rec qa nclean nnever setup viol
  rec=$(txt skills/executing-plans/references/recovery.md | grep 'commit anything uncommitted')
  check "A17: recovery.md's commit-anything-uncommitted excludes the carried paths" "$(has "$rec" 'except the carried paths')" "yes"
  check "A17: recovery.md says it once per row that has it" "$(printf '%s\n' "$rec" | grep -c .):$(printf '%s\n' "$rec" | grep -c 'carried')" "1:1"
  nclean=$(txt reference/final-review.md | grep -c "its uncommitted files were removed")
  nnever=$(txt reference/final-review.md | grep -c 'Never restore or delete a carried path')
  check "A17: final-review.md has QA timeout cleanup sites" "$([ "$nclean" -ge 1 ] && echo yes || echo no)" "yes"
  check "A17: every QA timeout cleanup site excludes carried paths" "$nnever" "$nclean"
  setup=$(txt skills/executing-plans/references/setup.md | flat)
  check "A17: executing-plans Setup states by-name staging" "$(has "$setup" 'stage the paths it changed by name')$(has "$setup" 'never `git add -A` or `git add .`')" "yesyes"
  viol=$(cd "$PLUGIN" && grep -rnE --include='*.md' 'git add (-A|--all|-u|\.)([^A-Za-z0-9_/.-]|$)' skills reference | grep -viE 'never|not |do not|don.t' || true)
  check "A17: no Setup or task-loop text stages with git add -A or git add ." "$viol" ""
}

t_A18() {
  local stops inplace
  stops=$(between skills/finishing-a-development-branch/SKILL.md '^- \*\*Where an unattended finish stops' '^- \*\*' | flat)
  check "A18: the unattended-finish stop list names a refused checkout, pull or merge of the base" "$(has "$stops" 'a refused checkout, pull or merge of the base')" "yes"
  check "A18: and stops the run with scripts/auto-run stop" "$(has "$stops" 'scripts/auto-run stop --reason')" "yes"
  inplace=$(between skills/finishing-a-development-branch/SKILL.md '^- \*\*In place,\*\*' '^- \*\*' | flat)
  check "A18: in place, pr and keep end with the branch line" \
    "$(has "$inplace" '`pr` and `keep`')$(has "$inplace" 'This checkout is on `auto/<slug>`; your uncommitted changes are here')" "yesyes"
}

t_A19() {
  local step2
  step2=$(between skills/resume-execution/SKILL.md '^2\. \*\*Verify the worktree' '^3\. \*\*Enter' | flat)
  check "A19: step 2 covers an auto run whose status names a recorded branch" "$(has "$step2" 'In an auto run whose `scripts/auto-run status` names `branch <name>`')" "yes"
  check "A19: a vanished branch stops the run with the reason and asks" \
    "$(has "$step2" '`git branch --list <name>` prints nothing')$(has "$step2" 'scripts/auto-run stop --reason "the run'"'"'s branch <name> is gone"')$(has "$step2" 'ask')" "yesyesyes"
  check "A19: a HEAD that is elsewhere is switched back with git switch <name>" "$(has "$step2" 'When HEAD is not on it, run `git switch <name>`')" "yes"
  check "A19: a refused switch stops the run the same way" "$(has "$step2" 'a refused switch stops the run the same way')" "yes"
}

# A final or finish phase after commits since branchBase.
t_A20() {
  local status out
  carried_run a20f
  printf 'task\n' >> "$CWD/tracked/b.txt"
  gi add tracked/a.txt tracked/b.txt; gi commit -q -m task
  out=$(ar phase final 2>&1); status=$?
  check "A20: phase final after a carried path was committed: exit 4, phase unchanged" "$status:$(fld phase)" "4:execute"
  check "A20: phase final names the path" "$(has "$out" 'tracked/a.txt')" "yes"

  carried_run a20u
  gi add u.txt; gi commit -q -m task
  out=$(ar phase final 2>&1); status=$?
  check "A20: phase final after a carried untracked file was committed: exit 4, phase unchanged" "$status:$(fld phase)" "4:execute"
  check "A20: phase final names the path" "$(has "$out" 'u.txt')" "yes"

  carried_run a20z
  printf 'task\n' >> "$CWD/tracked/b.txt"
  gi add tracked/b.txt; gi commit -q -m task
  ar phase final >/dev/null 2>&1
  gi add tracked/a.txt; gi commit -q -m late
  out=$(ar phase finish 2>&1); status=$?
  check "A20: phase finish after a carried path was committed: exit 4, phase unchanged" "$status:$(fld phase)" "4:final"
  check "A20: phase finish names the path" "$(has "$out" 'tracked/a.txt')" "yes"

  carried_run a20ok
  printf 'task\n' >> "$CWD/tracked/b.txt"
  gi add tracked/b.txt; gi commit -q -m task
  ar phase final >/dev/null 2>&1; status=$?
  check "A20: phase final after commits touching only other paths: exit 0" "$status:$(fld phase)" "0:final"
  ar phase finish >/dev/null 2>&1; status=$?
  check "A20: phase finish after commits touching only other paths: exit 0" "$status:$(fld phase)" "0:finish"
}

t_A21() {
  local status out before
  newrepo a21; startrun --isolation in-place; dirty
  printf 'staged\n' >> "$CWD/tracked/b.txt"
  gi add tracked/b.txt
  printf 'fresh\n' > "$CWD/fresh.txt"
  gi add fresh.txt
  gi switch -q -c auto/widget
  before=$(snap)
  out=$(ar setup-branch auto/widget 2>&1); status=$?
  check "A21: setup-branch with staged changes exits 4" "$status" "4"
  check "A21: records nothing" "$(snap)" "$before"
  check "A21: no branch, branchBase or carried" "$(fld branch):$(fld branchBase):$(fld carried)" "null:null:null"
  check "A21: prints the staged paths" "$(has "$out" 'tracked/b.txt')$(has "$out" 'fresh.txt')" "yesyes"

  newrepo a21m; startrun --isolation in-place
  printf 'staged\n' >> "$CWD/tracked/c.txt"
  gi add tracked/c.txt
  printf 'more\n' >> "$CWD/tracked/c.txt"
  gi switch -q -c auto/widget
  out=$(ar setup-branch auto/widget 2>&1); status=$?
  check "A21: a path both staged and modified again: exit 4" "$status" "4"
  check "A21: a path both staged and modified again: nothing recorded, path printed" "$(fld branch):$(has "$out" 'tracked/c.txt')" "null:yes"

  newrepo a21d; startrun --isolation in-place
  gi rm -q tracked/c.txt
  gi switch -q -c auto/widget
  out=$(ar setup-branch auto/widget 2>&1); status=$?
  check "A21: a staged deletion: exit 4, nothing recorded, path printed" "$status:$(fld branch):$(has "$out" 'tracked/c.txt')" "4:null:yes"
}

for a in A1 A2 A3 A4 A5 A6 A7 A8 A9 A10 A11 A12 A13 A14 A15 A16 A17 A18 A19 A20 A21; do
  want "$a" && "t_$a"
done

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
