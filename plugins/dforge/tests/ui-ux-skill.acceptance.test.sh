#!/usr/bin/env bash
# Acceptance tests for the ui-ux skill spec (docs/dforge/specs/2026-10-24-ui-ux-skill-design.md).
# Each test is written from the spec's acceptance statement and reaches the
# behaviour through the scripts and documents the spec names. Usage:
#   bash ui-ux-skill.acceptance.test.sh            run every test
#   bash ui-ux-skill.acceptance.test.sh A7 A22     run the named tests only
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
S="$PLUGIN/scripts"
UIP="$S/ui-proof"
LINT="$S/ui-lint"
PLINT="$S/plan-lint"
TBRIEF="$S/task-brief"
LROUTE="$S/lens-route"
EDITHOOK="$S/ui-edit-hook.sh"
STOPHOOK="$S/ui-turn-end.sh"
TURNSTART="$S/turn-start.sh"
AUTORUN="$S/auto-run"

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
matches() { # matches <name> <haystack> <ERE>
  if grep -qE -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       no match: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

absent() { # absent <name> <haystack> <ERE>
  if grep -qE -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected match: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REAL_HOME="$HOME"
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION DFORGE_BUDGET CLAUDE_PROJECT_DIR
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export DR_CODEX_SESSION_DIR="$TMP/codex-sessions"
cat > "$TMP/unusable.sh" <<'EOF'
echo '[{"id":"codex","usable":false,"reason":"not authenticated"}]'
EOF
export PLAN_LINT_ROSTER="$TMP/unusable.sh"

g() { timeout 60 git "$@"; }
sedi() { # sedi <expression> <file> — portable in-place edit
  sed "$1" "$2" > "$2.sedi" && mv "$2.sedi" "$2"
}

SPEC_REL=docs/dforge/specs/2026-10-24-demo-design.md
OTHER_SPEC_REL=docs/dforge/specs/2026-10-24-other-design.md
PLAIN_SPEC_REL=docs/dforge/specs/2026-10-24-plain-design.md
PROFILE_REL=docs/dforge/ui-ux/profile.md
PROOFS=docs/dforge/ui-ux/proofs
REPORT_REL=$PROOFS/2026-10-24-demo.md
JUDGE_REL=$PROOFS/2026-10-24-demo.judge.md
EVID=.dforge/ui-ux/demo
FAKEFP=0000000000000000

# --- fixtures ---------------------------------------------------------------

write_spec() { # write_spec <file> contract|plain
  mkdir -p "$(dirname "$1")"
  if [ "$2" = contract ]; then
    cat > "$1" <<'EOF'
# Demo

## UI/UX contract

**UI/UX depth:** feature — a dialog

### UI

- **UI-1** — Dialog: `Card` with tokens `surface` and `muted-foreground`.
  Board: `docs/ux/boards/dialog.png` (default, saving).

### UX

- **UX-1** — Escape closes the dialog and returns focus to the trigger.
- **UX-2** — Saving shows a pending state after 200 ms.

### Output promise

| ID | Promise |
|---|---|
| OP-1 | Proven at 375x812, light theme. |

## Acceptance

A1. [test, high] ok
EOF
  else
    printf '# Plain\n\n## Acceptance\n\nA1. [test, high] ok\n' > "$1"
  fi
}

# new_repo <name> <profile: none|web|py>; sets REPO and BASE
new_repo() {
  REPO="$TMP/$1"
  g init -q "$REPO"
  mkdir -p "$REPO/src" "$REPO/docs/dforge/plans"
  printf 'hello\n' > "$REPO/README.md"
  write_spec "$REPO/$SPEC_REL" contract
  write_spec "$REPO/$OTHER_SPEC_REL" contract
  write_spec "$REPO/$PLAIN_SPEC_REL" plain
  case "$2" in
    web|py)
      mkdir -p "$REPO/$(dirname "$PROFILE_REL")"
      local globs='`src/*.tsx` `src/*.css`'
      [ "$2" = py ] && globs='`app/*.py`'
      printf '# UI profile\n\n**Platform:** web\n**Harness:** `npm run dev`\n**UI paths:** %s\n**Viewports:** 375x812\n**Themes:** light\n**Screenshots:** local\n' \
        "$globs" > "$REPO/$PROFILE_REL" ;;
  esac
  g -C "$REPO" add -A
  g -C "$REPO" commit -qm base
  BASE=$(g -C "$REPO" rev-parse HEAD)
}

ui_file() { # ui_file <repo> [path] [content] — write a UI file (uncommitted)
  mkdir -p "$(dirname "$1/${2:-src/App.tsx}")"
  printf '%s\n' "${3:-<button>ok</button>}" > "$1/${2:-src/App.tsx}"
}
commit_path() { # commit_path <repo> <path>
  g -C "$1" add "$2"
  g -C "$1" commit -qm "ui change $2"
}

good_rows() {
  cat <<'EOF'
| UI-1 | pass | .dforge/ui-ux/demo/a.png | |
| UX-1 | pass | A1: escape closes | |
| UX-2 | pass | A1: saving pending | |
| OP-1 | pass | .dforge/ui-ux/demo/a.png | |
EOF
}
touch_rows() {
  cat <<'EOF'
| UI-1 | pass | .dforge/ui-ux/demo/a.png | |
| UX-1 | pass | A1: escape closes | |
EOF
}
TOUCH_DELTA=$'## Delta\n\n**UI/UX depth:** touch — dialog closes on Escape\n\n- **UX-1** — Escape closes the dialog.\n- **UI-1** — Focus ring stays visible.'

# write_report <repo> <rows> [contract] [delta] [trailer]
write_report() {
  local repo=$1 rows=$2 contract=${3:-$SPEC_REL} delta=${4:-} trailer=${5:-}
  mkdir -p "$repo/$PROOFS" "$repo/$EVID"
  printf '*\n' > "$repo/.dforge/.gitignore"
  [ -f "$repo/$EVID/a.png" ] || printf 'png' > "$repo/$EVID/a.png"
  {
    printf '# UI proof: Demo\n\n'
    printf '**Contract:** %s\n' "$contract"
    printf '**Platform:** web\n**Viewports:** 375x812\n**Themes:** light\n**Evidence:** local\n\n'
    [ -z "$delta" ] || printf '%s\n\n' "$delta"
    printf '## Results\n\n| ID | Verdict | Evidence | Note |\n|---|---|---|---|\n%s\n' "$rows"
    [ -z "$trailer" ] || printf '\n%s\n' "$trailer"
  } > "$repo/$REPORT_REL"
}
fp() { (cd "$1" && timeout 60 bash "$UIP" fingerprint 2>&1); }
stamp() { (cd "$1" && timeout 60 bash "$UIP" stamp "$REPORT_REL" 2>&1); }
# add_judge <repo> <verdict> <fp on the Judge line> <fp ending the judge file | missing>
add_judge() {
  local repo=$1 verdict=$2 jfp=$3 ffp=$4
  if [ "$ffp" != missing ]; then
    printf 'Reviewed every row.\n\nVerdict: %s %s\n' "$verdict" "$ffp" > "$repo/$JUDGE_REL"
  fi
  local line="**Judge:** $verdict $jfp — $JUDGE_REL"
  awk -v l="$line" '{ print } /^\*\*Fingerprint:\*\*/ { print l }' "$repo/$REPORT_REL" > "$repo/$REPORT_REL.new"
  mv "$repo/$REPORT_REL.new" "$repo/$REPORT_REL"
}
# finish_report <repo> [verdict] — stamp, then record a judge verdict for the stamped fingerprint
finish_report() {
  stamp "$1" >/dev/null
  local f; f=$(fp "$1")
  add_judge "$1" "${2:-ship}" "$f" "$f"
}
# full_good <repo> — a stamped, judged report bound to the demo spec
full_good() { write_report "$1" "$(good_rows)"; finish_report "$1"; }

gate() { # gate <repo> args...; sets out and status
  local repo=$1; shift
  out=$(cd "$repo" && timeout 60 bash "$UIP" check "$@" 2>&1); status=$?
}

# --- plans ------------------------------------------------------------------

# plan <spec> <t1 files> <t1 ui line> <t2 files> <t2 ui line>
plan_text() {
  cat <<EOF
# Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names.

**Goal:** Demo.

**Spec:** \`$1\`

**Execution:** subagent — \`claude --model sonnet --effort high\` — Task 2 scores 4

**Program:** \`$1\` — sub-project 1 of 2 — next: Second part

**Plan review:** 2026-09-12 — dforge:judge-fable — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)

## Global Constraints

- Bash only.

## Contracts

None

## Assumptions (evidence)

- None.

## Task index

1. First thing
2. Second thing

### Task 1: First thing

**Files:**
- Create: \`$2\`

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1
$3

- [ ] **Step 1: Write it**

### Task 2: Second thing

**Files:**
- Modify: \`$4\`

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4
**Approach:** inline - skip 2: follows the pattern
$5

- [ ] **Step 1: Change it**
EOF
}
# write_plan <repo> <name> <spec> <t1 files> <t1 ui> <t2 files> <t2 ui>
write_plan() {
  plan_text "$3" "$4" "$5" "$6" "$7" > "$1/docs/dforge/plans/$2"
}
lint() { # lint <repo> <plan>; sets out and status
  out=$(cd "$1" && CLAUDE_CODE_SESSION_ID=acc-lint timeout 60 bash "$PLINT" "docs/dforge/plans/$2" 2>&1); status=$?
}

# --- hook helpers -----------------------------------------------------------

hook_edit() { # hook_edit <home> <session> <cwd> <file> [transcript]
  jq -n --arg sid "$2" --arg cwd "$3" --arg f "$4" --arg tp "${5:-}" \
    '{hook_event_name:"PostToolUse",session_id:$sid,cwd:$cwd,transcript_path:$tp,tool_name:"Edit",tool_input:{file_path:$f}}' \
    | (cd "$3" && HOME="$1" timeout 30 bash "$EDITHOOK" 2>/dev/null)
}
ctx() { jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$1" 2>/dev/null; }
turn_start() { # turn_start <home> <session> <cwd>
  jq -n --arg sid "$2" --arg cwd "$3" '{hook_event_name:"UserPromptSubmit",session_id:$sid,cwd:$cwd,prompt:"go"}' \
    | HOME="$1" timeout 30 bash "$TURNSTART" >/dev/null 2>&1
}
stop_hook() { # stop_hook <home> <session> <cwd> <message> <active> [transcript]
  jq -n --arg sid "$2" --arg cwd "$3" --arg msg "$4" --argjson active "$5" --arg tp "${6:-}" \
    '{hook_event_name:"Stop",session_id:$sid,cwd:$cwd,transcript_path:$tp,stop_hook_active:$active,last_assistant_message:$msg}' \
    | (cd "$3" && HOME="$1" timeout 60 bash "$STOPHOOK" 2>/dev/null)
}
decision() { jq -r '.decision // "none"' <<<"${1:-{\}}" 2>/dev/null || echo none; }
NOUI_TRANSCRIPT="$TMP/transcript-plain.jsonl"
jq -nc '{type:"user",message:{role:"user",content:"fix the dialog"}}' > "$NOUI_TRANSCRIPT"
UIRUN_TRANSCRIPT="$TMP/transcript-uiux.jsonl"
cp "$NOUI_TRANSCRIPT" "$UIRUN_TRANSCRIPT"
jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"t1",name:"Skill",input:{skill:"dforge:ui-ux"}}]}}' >> "$UIRUN_TRANSCRIPT"

# stop_scene <name> <profile none|web> — a repo whose turn committed a UI edit; sets REPO BASE HX SID
stop_scene() {
  new_repo "$1" "$2"
  HX="$TMP/home-$1"; mkdir -p "$HX"; SID="s-$1"
  turn_start "$HX" "$SID" "$REPO"
  ui_file "$REPO" src/App.tsx
  commit_path "$REPO" src/App.tsx
}

# --- tests ------------------------------------------------------------------

t_A1() {
  check "A1: SKILL.md exists at plugins/dforge/skills/ui-ux/SKILL.md" \
    "$([ -f "$PLUGIN/skills/ui-ux/SKILL.md" ] && echo yes || echo no)" "yes"
  check "A1: its frontmatter says name: ui-ux" \
    "$(awk 'NR==1 && $0=="---" {f=1; next} f && $0=="---" {exit} f && $0=="name: ui-ux" {print "yes"}' "$PLUGIN/skills/ui-ux/SKILL.md")" "yes"
  local vout vstatus
  local claude_bin=${CLAUDE:-$(type -P claude || true)}
  [ -n "$claude_bin" ] || claude_bin="$REAL_HOME/.local/bin/claude"
  if [ ! -f "$claude_bin" ] || [ ! -x "$claude_bin" ]; then
    echo "skip - A1: claude plugin validate: no claude CLI here (\$CLAUDE, PATH, ~/.local/bin)"
    return
  fi
  vout=$(cd "$PLUGIN" && timeout 180 "$claude_bin" plugin validate "$PLUGIN" 2>&1); vstatus=$?
  check "A1: claude plugin validate passes on dforge" "$vstatus" "0"
  has "A1: the validator reports success" "$vout" "Validation passed"
}

t_A4() {
  new_repo a4 none
  local spec=$SPEC_REL
  write_plan "$REPO" no-line.md "$spec" src/Dialog.tsx '' a.txt ''
  lint "$REPO" no-line.md
  check "A4: a UI task with no UI/UX line fails" "$status" "1"
  has "A4: the failure names Task 1" "$out" "Task 1"
  write_plan "$REPO" ux2.md "$spec" src/Dialog.tsx '**UI/UX:** UI-1, UX-1' a.txt ''
  lint "$REPO" ux2.md
  check "A4: a UX- ID named by no task fails" "$status" "1"
  has "A4: the failure names UX-2" "$out" "UX-2"
  write_plan "$REPO" ui1.md "$spec" src/Dialog.tsx '**UI/UX:** UX-1, UX-2' a.txt ''
  lint "$REPO" ui1.md
  check "A4: a UI- ID named by no task fails" "$status" "1"
  has "A4: the failure names UI-1" "$out" "UI-1"
  write_plan "$REPO" good.md "$spec" src/Dialog.tsx '**UI/UX:** UI-1, UX-1' a.txt '**UI/UX:** UX-2'
  lint "$REPO" good.md
  check "A4: with every UI-/UX- ID named and only OP-1 unnamed, the plan passes" "$status" "0"
  lacks "A4: the passing plan has no error finding" "$out" "ERROR"
  write_plan "$REPO" plain.md "$PLAIN_SPEC_REL" src/Dialog.tsx '' a.txt ''
  lint "$REPO" plain.md
  check "A4: a spec with no contract asks for no UI/UX line" "$status" "0"
}

t_A5() {
  new_repo a5 none
  write_plan "$REPO" p.md "$SPEC_REL" src/Dialog.tsx '**UI/UX:** UI-1, UX-1' a.txt ''
  local b1="$TMP/a5-brief1.md" b2="$TMP/a5-brief2.md"
  (cd "$REPO" && timeout 60 bash "$TBRIEF" docs/dforge/plans/p.md 1 "$b1" >/dev/null 2>&1); status=$?
  check "A5: task-brief exits 0 for the task with a UI/UX line" "$status" "0"
  local brief; brief=$(cat "$b1")
  has "A5: the brief carries UI-1's first line verbatim" "$brief" '- **UI-1** — Dialog: `Card` with tokens `surface` and `muted-foreground`.'
  has "A5: the brief carries UI-1's board line verbatim" "$brief" '  Board: `docs/ux/boards/dialog.png` (default, saving).'
  has "A5: the brief carries UX-1 verbatim" "$brief" '- **UX-1** — Escape closes the dialog and returns focus to the trigger.'
  lacks "A5: the brief leaves out the contract item the task does not cite" "$brief" 'Saving shows a pending state'
  lacks "A5: the brief leaves out the OP- item the task does not cite" "$brief" 'Proven at 375x812'
  (cd "$REPO" && timeout 60 bash "$TBRIEF" docs/dforge/plans/p.md 2 "$b2" >/dev/null 2>&1); status=$?
  check "A5: task-brief exits 0 for the task without a UI/UX line" "$status" "0"
  brief=$(cat "$b2")
  lacks "A5: a task without the line gets no UI-1 item" "$brief" 'Dialog: `Card`'
  lacks "A5: a task without the line gets no UX-1 item" "$brief" 'Escape closes the dialog'
  lacks "A5: a task without the line gets no UX-2 item" "$brief" 'Saving shows a pending state'
  lacks "A5: a task without the line gets no board path" "$brief" 'docs/ux/boards/dialog.png'
}

t_A6() {
  new_repo a6a none
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A6: no UI file differs from the base: exit 0" "$status" "0"
  printf 'changed\n' >> "$REPO/README.md"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A6: only a non-UI file differs: exit 0" "$status" "0"

  new_repo a6b none
  ui_file "$REPO"
  full_good "$REPO"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A6: a complete, fresh, judged report (uncommitted UI change): exit 0" "$status" "0"
  commit_path "$REPO" src/App.tsx
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A6: the same report after the UI change is committed: exit 0" "$status" "0"

  new_repo a6c none
  ui_file "$REPO"
  write_report "$REPO" "$(good_rows | sed 's#^| UX-2 | pass | A1: saving pending | |#| UX-2 | deviation | .dforge/ui-ux/demo/a.png | cites: user answer 2026-10-24, pending state dropped |#')"
  finish_report "$REPO"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A6: a cited deviation row passes" "$status" "0"
}

t_A7() {
  new_repo a7a none
  ui_file "$REPO"
  commit_path "$REPO" src/App.tsx
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A7: a committed UI change with no report: exit 1" "$status" "1"
  has "A7: the failure names the changed file" "$out" "src/App.tsx"

  new_repo a7b none
  ui_file "$REPO"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A7: an uncommitted UI change with no report: exit 1" "$status" "1"
  has "A7: the failure names the changed file (uncommitted)" "$out" "src/App.tsx"

  new_repo a7c web
  ui_file "$REPO"
  commit_path "$REPO" src/App.tsx
  gate "$REPO" --base "$BASE"
  check "A7: a profile project, committed UI change, no report, no --spec: exit 1" "$status" "1"
  write_report "$REPO" "$(touch_rows)" touch "$TOUCH_DELTA"
  finish_report "$REPO"
  gate "$REPO" --base "$BASE"
  check "A7: control: the stamped, judged touch report passes without --spec" "$status" "0"

  new_repo a7d none
  ui_file "$REPO"
  full_good "$REPO"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A7: control: before the edit the proof passes" "$status" "0"
  ui_file "$REPO" src/App.tsx '<button>changed after the stamp</button>'
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A7: a UI file edited after the report was stamped (uncommitted): exit 1" "$status" "1"
  commit_path "$REPO" src/App.tsx
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A7: the same stale edit once committed: exit 1" "$status" "1"
}

# build_a8 <name> <rows> [trailer] — a judged report with one defect in the rows
build_a8() {
  new_repo "$1" none
  ui_file "$REPO"
  write_report "$REPO" "$2" "$SPEC_REL" "" "${3:-}"
  finish_report "$REPO"
}
t_A8() {
  local rows
  build_a8 a8ctl "$(good_rows)"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A8: control: the unmodified report passes" "$status" "0"

  build_a8 a8fail "$(good_rows | sed 's#^| UX-1 | pass .*#| UX-1 | fail | A1: escape closes | does not return focus |#')"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A8: a fail row: exit 1" "$status" "1"

  build_a8 a8dev "$(good_rows | sed 's#^| UX-1 | pass .*#| UX-1 | deviation | A1: escape closes | no retry button on the error card |#')"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A8: an uncited deviation row: exit 1" "$status" "1"
  build_a8 a8devok "$(good_rows | sed 's#^| UX-1 | pass .*#| UX-1 | deviation | A1: escape closes | cites: user answer 2026-10-24, no retry button |#')"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A8: control: a cited deviation row passes" "$status" "0"

  build_a8 a8noev "$(good_rows | sed 's#^| UX-1 | pass .*#| UX-1 | pass | - | |#')"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A8: a pass row with no evidence: exit 1" "$status" "1"

  build_a8 a8missing "$(good_rows | sed 's#^| UI-1 | pass | [^|]*|#| UI-1 | pass | .dforge/ui-ux/demo/missing.png |#')"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A8: a cited screenshot that does not exist: exit 1" "$status" "1"

  build_a8 a8unv "$(good_rows | sed 's#^| OP-1 | pass .*#| OP-1 | unverifiable | - | no tablet on this host |#')"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A8: an unverifiable row without Accepted by: exit 1" "$status" "1"
  build_a8 a8unvok "$(good_rows | sed 's#^| OP-1 | pass .*#| OP-1 | unverifiable | - | no tablet on this host |#')" '**Accepted by:** "fine without the tablet run"'
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A8: control: an unverifiable row with Accepted by passes" "$status" "0"

  build_a8 a8noid "$(good_rows | grep -v '^| OP-1 ')"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A8: a contract ID with no row: exit 1" "$status" "1"
  has "A8: the failure names the missing ID" "$out" "OP-1"

  # judge line variants
  build_a8 a8jfix "$(good_rows)"
  local f; f=$(fp "$REPO")
  sedi "s#^\*\*Judge:\*\* ship#**Judge:** fix#" "$REPO/$REPORT_REL"
  printf 'Disputes UX-1.\n\nVerdict: fix %s\n' "$f" > "$REPO/$JUDGE_REL"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A8: a judge line that reads fix: exit 1" "$status" "1"

  build_a8 a8jother "$(good_rows)"
  sedi "s#^\*\*Judge:\*\* ship [0-9a-f]*#**Judge:** ship deadbeefdeadbeef#" "$REPO/$REPORT_REL"
  printf 'Looks fine.\n\nVerdict: ship deadbeefdeadbeef\n' > "$REPO/$JUDGE_REL"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A8: a judge line carrying another fingerprint: exit 1" "$status" "1"

  build_a8 a8nojudge "$(good_rows)"
  sedi '/^\*\*Judge:\*\*/d' "$REPO/$REPORT_REL"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A8: no judge line at all: exit 1" "$status" "1"
}

t_A9() {
  new_repo a9a none
  ui_file "$REPO"
  full_good "$REPO"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A9: control: the report bound to the spec passes" "$status" "0"

  new_repo a9b none
  ui_file "$REPO"
  write_report "$REPO" "$(touch_rows)" touch "$TOUCH_DELTA"
  finish_report "$REPO"
  gate "$REPO" --base "$BASE"
  check "A9: control: the touch report is complete and passes without --spec" "$status" "0"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A9: with --spec on a contract spec, a touch report with a current fingerprint: exit 1" "$status" "1"

  new_repo a9c none
  ui_file "$REPO"
  write_report "$REPO" "$(good_rows)" "$OTHER_SPEC_REL"
  finish_report "$REPO"
  gate "$REPO" --base "$BASE" --spec "$OTHER_SPEC_REL"
  check "A9: control: the report passes against the spec it is bound to" "$status" "0"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A9: with --spec on another spec, a report bound to the other spec: exit 1" "$status" "1"
}

t_A10() {
  new_repo a10 none
  ui_file "$REPO"
  write_report "$REPO" "$(good_rows)"
  stamp "$REPO" >/dev/null
  local f1; f1=$(fp "$REPO")
  check "A10: stamp writes the current fingerprint" \
    "$(grep -c "^\*\*Fingerprint:\*\* $f1\$" "$REPO/$REPORT_REL")" "1"
  add_judge "$REPO" ship "$FAKEFP" "$FAKEFP"
  check "A10: setup: the report holds a judge line for another fingerprint" \
    "$(grep -c '^\*\*Judge:\*\*' "$REPO/$REPORT_REL")" "1"
  stamp "$REPO" >/dev/null
  check "A10: stamp removes a judge line whose fingerprint differs" \
    "$(grep -c '^\*\*Judge:\*\*' "$REPO/$REPORT_REL")" "0"

  sedi '/^\*\*Judge:\*\*/d' "$REPO/$REPORT_REL"
  add_judge "$REPO" ship "$f1" "$f1"
  stamp "$REPO" >/dev/null
  check "A10: stamp keeps a judge line for the same fingerprint" \
    "$(grep -c "^\*\*Judge:\*\* ship $f1 " "$REPO/$REPORT_REL")" "1"

  ui_file "$REPO" src/App.tsx '<button>edited after the verdict</button>'
  stamp "$REPO" >/dev/null
  local f2; f2=$(fp "$REPO")
  check "A10: the edit changed the fingerprint" "$([ "$f1" != "$f2" ] && echo yes || echo no)" "yes"
  check "A10: after a UI edit the new stamp drops the old verdict" \
    "$(grep -c '^\*\*Judge:\*\*' "$REPO/$REPORT_REL")" "0"
  check "A10: the new stamp holds the new fingerprint" \
    "$(grep -c "^\*\*Fingerprint:\*\* $f2\$" "$REPO/$REPORT_REL")" "1"
}

union_globs() {
  cat <<'EOF'
*.tsx
*.jsx
*.vue
*.svelte
*.astro
*.html
*.css
*.scss
*.sass
*.less
*.xaml
*.axaml
*.rc
*.Designer.cs
*.razor
*.cshtml
res/layout/*.xml
res/values/*.xml
res/drawable/*.xml
*.ui
*.qml
*.glade
*.blp
EOF
}
t_A11() {
  new_repo a11np none
  local pout missing=""
  pout=$(cd "$REPO" && timeout 30 bash "$UIP" paths 2>&1)
  local glob
  while IFS= read -r glob; do
    # An Android glob may carry a leading * so it also matches below a module directory.
    if ! grep -qxF -e "$glob" -e "*$glob" <<<"$pout"; then missing="$missing $glob"; fi
  done < <(union_globs)
  check "A11: with no profile, paths prints every platform default" "${missing:-none}" "none"
  check "A11: the web and windows defaults exclude bare .ts and .cs" \
    "$(grep -cxE '\*\.(ts|cs|kt)' <<<"$pout")" "0"

  new_repo a11p py
  pout=$(cd "$REPO" && timeout 30 bash "$UIP" paths 2>&1)
  check "A11: with a profile, paths prints exactly the profile's globs" "$pout" "app/*.py"

  # consumers: the gate
  ui_file "$REPO" src/App.tsx
  commit_path "$REPO" src/App.tsx
  gate "$REPO" --base "$BASE"
  check "A11: the gate ignores a .tsx file the profile does not name" "$status" "0"
  ui_file "$REPO" app/x.py 'print(1)'
  commit_path "$REPO" app/x.py
  gate "$REPO" --base "$BASE"
  check "A11: the gate takes the profile's glob (app/*.py needs a proof)" "$status" "1"

  # consumers: the PostToolUse hook
  local hh="$TMP/home-a11" o
  mkdir -p "$hh"
  o=$(hook_edit "$hh" s-a11 "$REPO" "$REPO/src/App.tsx")
  check "A11: the hook stays silent for a .tsx file the profile does not name" "$o" ""
  o=$(hook_edit "$hh" s-a11 "$REPO" "$REPO/app/x.py")
  check "A11: the hook reacts to the profile's glob" "$([ -n "$o" ] && echo yes || echo no)" "yes"
  # git prints its top level resolved, as Windows prints it as C:/ against a /c/ path.
  ln -s "$REPO" "$TMP/a11p-link"
  o=$(hook_edit "$TMP/home-a11-link" s-a11 "$REPO" "$TMP/a11p-link/app/x.py")
  check "A11: the hook reacts to the profile's glob through another spelling of the path" \
    "$([ -n "$o" ] && echo yes || echo no)" "yes"

  # consumers: plan-lint
  write_plan "$REPO" prof.md "$SPEC_REL" app/x.py '**UI/UX:** UI-1, UX-1, UX-2' src/Dialog.tsx ''
  lint "$REPO" prof.md
  check "A11: plan-lint asks no UI/UX line of a task whose file the profile does not name" "$status" "0"
  write_plan "$REPO" prof2.md "$SPEC_REL" app/x.py '' src/Dialog.tsx '**UI/UX:** UI-1, UX-1, UX-2'
  lint "$REPO" prof2.md
  check "A11: plan-lint asks a UI/UX line of a task touching the profile's glob" "$status" "1"
  has "A11: that failure names Task 1" "$out" "Task 1"

  # consumers: lens-route
  local head1 head2
  head1=$(g -C "$REPO" rev-parse HEAD~1)
  head2=$(g -C "$REPO" rev-parse HEAD)
  write_plan "$REPO" lens.md "$PLAIN_SPEC_REL" app/x.py '' src/Dialog.tsx ''
  o=$(cd "$REPO" && timeout 60 bash "$LROUTE" docs/dforge/plans/lens.md --final "$BASE" "$head1" 2>&1)
  lacks "A11: lens-route does not route ui-ux for a .tsx file the profile does not name" "$o" "lens ui-ux "
  o=$(cd "$REPO" && timeout 60 bash "$LROUTE" docs/dforge/plans/lens.md --final "$head1" "$head2" 2>&1)
  has "A11: lens-route routes ui-ux for the profile's glob" "$o" "lens ui-ux "
}

t_A12() {
  new_repo a12 none
  local hh="$TMP/home-a12"; mkdir -p "$hh"
  printf 'export const A = () => (\n  <div>\n    <img src="x.png" />\n  </div>\n);\n' > "$REPO/src/App.tsx"
  printf 'export const n = 1;\n' > "$REPO/src/util.ts"
  local lintout; lintout=$(cd "$REPO" && timeout 20 bash "$LINT" src/App.tsx 2>&1)
  local rule; rule=$(sed -E 's/^[^:]*:3: ([A-Za-z0-9_-]+) .*/\1/' <<<"$lintout" | head -n1)
  check "A12: setup: ui-lint reports the img on line 3 with a rule name" "$([ -n "$rule" ] && [ "$rule" != "$lintout" ] && echo yes || echo no)" "yes"

  local o rc
  o=$(hook_edit "$hh" s-a12 "$REPO" "$REPO/src/App.tsx"); rc=$?
  check "A12: an edited UI file: the hook exits 0" "$rc" "0"
  check "A12: the output is JSON" "$(jq -e . >/dev/null 2>&1 <<<"$o" && echo yes || echo no)" "yes"
  check "A12: the event name is PostToolUse" "$(jq -r '.hookSpecificOutput.hookEventName // ""' <<<"$o")" "PostToolUse"
  has "A12: additionalContext names the rule" "$(ctx "$o")" "$rule"
  matches "A12: additionalContext names the line" "$(ctx "$o")" ':3[: ]|line 3|:3$'
  check "A12: the hook does not block the edit (no decision)" "$(jq -r '.decision // "none"' <<<"$o")" "none"
  check "A12: the hook does not deny the edit (no permission decision)" \
    "$(jq -r '.hookSpecificOutput.permissionDecision // "none"' <<<"$o")" "none"

  o=$(hook_edit "$hh" s-a12 "$REPO" "$REPO/src/util.ts"); rc=$?
  check "A12: a non-UI file: the hook exits 0" "$rc" "0"
  check "A12: a non-UI file: the hook returns nothing" "$o" ""
  o=$(hook_edit "$hh" s-a12 "$REPO" "$REPO/README.md")
  check "A12: a markdown file: the hook returns nothing" "$o" ""
}

t_A13() {
  new_repo a13 none
  local hh="$TMP/home-a13"; mkdir -p "$hh"
  printf 'export const A = () => (\n  <div>\n    <img src="x.png" />\n  </div>\n);\n' > "$REPO/src/App.tsx"
  local o
  o=$(hook_edit "$hh" s-a13 "$REPO" "$REPO/src/App.tsx" "$NOUI_TRANSCRIPT")
  has "A13: the first UI edit of a session with no ui-ux run names the skill" "$(ctx "$o")" "dforge:ui-ux"
  o=$(hook_edit "$hh" s-a13 "$REPO" "$REPO/src/App.tsx" "$NOUI_TRANSCRIPT")
  lacks "A13: the second UI edit does not repeat it" "$(ctx "$o")" "dforge:ui-ux"
  has "A13: the second UI edit still returns its lint findings" "$(ctx "$o")" "3"
  o=$(hook_edit "$hh" s-a13 "$REPO" "$REPO/src/App.tsx" "$NOUI_TRANSCRIPT")
  lacks "A13: the third UI edit does not repeat it" "$(ctx "$o")" "dforge:ui-ux"
  o=$(hook_edit "$hh" s-a13-other "$REPO" "$REPO/src/App.tsx" "$NOUI_TRANSCRIPT")
  has "A13: another session's first UI edit names the skill again" "$(ctx "$o")" "dforge:ui-ux"
  o=$(hook_edit "$hh" s-a13-ran "$REPO" "$REPO/src/App.tsx" "$UIRUN_TRANSCRIPT")
  lacks "A13: a session whose transcript shows a ui-ux run is not reminded" "$(ctx "$o")" "dforge:ui-ux"
}

t_A14() {
  # no proof at all
  stop_scene a14a web
  local o
  o=$(stop_hook "$HX" "$SID" "$REPO" 'The dialog is done.' false "$NOUI_TRANSCRIPT")
  check "A14: a committed UI edit with no proof, in a profile project: the stop is held" "$(decision "$o")" "block"
  has "A14: the reason names the stale file" "$(jq -r '.reason // ""' <<<"$o")" "src/App.tsx"
  has "A14: the systemMessage names the stale file" "$(jq -r '.systemMessage // ""' <<<"$o")" "src/App.tsx"
  o=$(stop_hook "$HX" "$SID" "$REPO" 'The dialog is done.' true "$NOUI_TRANSCRIPT")
  check "A14: the retry (stop_hook_active) passes" "$o" ""

  # a proof that misses an ID
  stop_scene a14b web
  write_report "$REPO" "$(good_rows | grep -v '^| OP-1 ')"
  finish_report "$REPO"
  o=$(stop_hook "$HX" "$SID" "$REPO" 'The dialog is done.' false "$NOUI_TRANSCRIPT")
  check "A14: a report with a contract ID missing: the stop is held" "$(decision "$o")" "block"
  has "A14: the reason names the missing ID" "$(jq -r '.reason // ""' <<<"$o")" "OP-1"
  has "A14: the systemMessage names the missing ID" "$(jq -r '.systemMessage // ""' <<<"$o")" "OP-1"
  o=$(stop_hook "$HX" "$SID" "$REPO" 'The dialog is done.' true "$NOUI_TRANSCRIPT")
  check "A14: the retry passes here too" "$o" ""

  # a passing proof
  stop_scene a14c web
  full_good "$REPO"
  o=$(stop_hook "$HX" "$SID" "$REPO" 'The dialog is done.' false "$NOUI_TRANSCRIPT")
  check "A14: control: with a passing proof the stop is not held" "$o" ""
}

t_A15() {
  # no profile, skill not run
  stop_scene a15a none
  local o
  o=$(stop_hook "$HX" "$SID" "$REPO" 'The dialog is done.' false "$NOUI_TRANSCRIPT")
  check "A15: no profile and no ui-ux run in the session: the stop is not held" "$o" ""
  o=$(stop_hook "$HX" "$SID" "$REPO" 'The dialog is done.' false "$UIRUN_TRANSCRIPT")
  check "A15: control: the same repo, once the transcript shows a ui-ux run, is held" "$(decision "$o")" "block"

  # an auto run bound to the session
  new_repo a15b web
  HX="$TMP/home-a15b"; SID=s-a15b
  mkdir -p "$HX/.claude/dforge/sessions/cockpit"
  date +%s > "$HX/.claude/dforge/sessions/cockpit/$SID"
  turn_start "$HX" "$SID" "$REPO"
  (cd "$REPO" && HOME="$HX" timeout 30 bash "$AUTORUN" --session "$SID" start --spec docs/s.md --register docs/r.md >/dev/null 2>&1)
  ui_file "$REPO" src/App.tsx
  commit_path "$REPO" src/App.tsx
  o=$(stop_hook "$HX" "$SID" "$REPO" 'The dialog is done.' false "$NOUI_TRANSCRIPT")
  check "A15: an auto run bound to the session: the stop is not held" "$o" ""
  (cd "$REPO" && HOME="$HX" timeout 30 bash "$AUTORUN" --session "$SID" stop --reason "acceptance control" >/dev/null 2>&1)
  rm -f "$REPO/.dforge/sdd/auto-run.json"
  o=$(stop_hook "$HX" "$SID" "$REPO" 'The dialog is done.' false "$NOUI_TRANSCRIPT")
  check "A15: control: with the auto run gone the same stop is held" "$(decision "$o")" "block"

  # the pending line
  stop_scene a15c web
  o=$(stop_hook "$HX" "$SID" "$REPO" $'The dialog is built.\n\nUI proof: pending — the browser harness is not installed on this host' false "$NOUI_TRANSCRIPT")
  check "A15: a last message carrying UI proof: pending — <why>: the stop is not held" "$o" ""
  o=$(stop_hook "$HX" "$SID" "$REPO" 'The dialog is built.' false "$NOUI_TRANSCRIPT")
  check "A15: control: the same repo without the pending line is held" "$(decision "$o")" "block"
}

# lint_pair <label> <relative path> <failing content> <failing line> <passing content>
lint_pair() {
  local label=$1 rel=$2 failc=$3 failn=$4 passc=$5
  local d f
  for d in fail pass; do
    mkdir -p "$TMP/fx/$label/$d/$(dirname "$rel")"
  done
  printf '%s' "$failc" > "$TMP/fx/$label/fail/$rel"
  printf '%s' "$passc" > "$TMP/fx/$label/pass/$rel"
  f="$TMP/fx/$label/fail/$rel"
  out=$(timeout 20 bash "$LINT" "$f" 2>&1); status=$?
  check "A16: $label: the failing fixture exits 1" "$status" "1"
  has "A16: $label: the failing fixture reports line $failn" "$out" "$f:$failn: "
  check "A16: $label: the failing fixture reports exactly one finding" "$(grep -c . <<<"$out")" "1"
  f="$TMP/fx/$label/pass/$rel"
  out=$(timeout 20 bash "$LINT" "$f" 2>&1); status=$?
  check "A16: $label: the passing fixture exits 0" "$status" "0"
  check "A16: $label: the passing fixture is silent" "$out" ""
}
tsx() { printf 'export const A = () => (\n%s\n);\n' "$1"; }
t_A16() {
  lint_pair raw-colour src/A.tsx "$(tsx "  <p style={{ color: '#ff0000' }}>x</p>")"$'\n' 2 "$(tsx "  <p style={{ color: 'var(--fg)' }}>x</p>")"$'\n'
  lint_pair outline-removed src/a.css $'.a { color: var(--fg); }\n.b { outline: none; }\n' 2 \
    $'.a { color: var(--fg); }\n.b { outline: none; }\n.b:focus-visible { outline: 2px solid var(--focus); }\n'
  lint_pair click-handler src/A.tsx "$(tsx '  <div onClick={go}>x</div>')"$'\n' 2 "$(tsx '  <button onClick={go}>x</button>')"$'\n'
  lint_pair image-alt src/A.tsx "$(tsx '  <img src="a.png" />')"$'\n' 2 "$(tsx '  <img src="a.png" alt="Logo" />')"$'\n'
  lint_pair transition-all src/a.css $'.a { color: var(--fg); }\n.b { transition: all 1s; }\n' 2 \
    $'.a { color: var(--fg); }\n.b { transition: opacity 1s; }\n'
  lint_pair zoom-disabled public/index.html $'<head>\n<meta name="viewport" content="width=device-width, user-scalable=no">\n</head>\n' 2 \
    $'<head>\n<meta name="viewport" content="width=device-width, initial-scale=1">\n</head>\n'
  lint_pair positive-tabindex src/A.tsx "$(tsx '  <button tabIndex={3}>x</button>')"$'\n' 2 "$(tsx '  <button tabIndex={0}>x</button>')"$'\n'
  lint_pair blocked-paste src/A.tsx "$(tsx '  <input onPaste={(e) => e.preventDefault()} />')"$'\n' 2 "$(tsx '  <input onChange={go} />')"$'\n'
  lint_pair xaml-brush views/Main.xaml $'<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">\n<Border Background="#FF0000" />\n</Grid>\n' 2 \
    $'<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation">\n<Border Background="{DynamicResource SurfaceBrush}" />\n</Grid>\n'
  lint_pair android-colour app/src/main/res/layout/a.xml $'<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android">\n<TextView android:textColor="#FF0000" android:text="@string/save" />\n</LinearLayout>\n' 2 \
    $'<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android">\n<TextView android:textColor="@color/ink" android:text="@string/save" />\n</LinearLayout>\n'
  lint_pair android-text app/src/main/res/layout/a.xml $'<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android">\n<TextView android:text="Save" />\n</LinearLayout>\n' 2 \
    $'<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android">\n<TextView android:text="@string/save" />\n</LinearLayout>\n'
  lint_pair android-image app/src/main/res/layout/a.xml $'<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android">\n<ImageView android:src="@drawable/logo" />\n</LinearLayout>\n' 2 \
    $'<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android">\n<ImageView android:src="@drawable/logo" android:contentDescription="@string/logo" />\n</LinearLayout>\n'
}

# A18 plan and diff: a UI file, a test file and a catch-all handler together
lens_branch() { # lens_branch <repo> <files...> — commit the files; the diff is BASE..HEAD
  local repo=$1; shift
  local f
  for f in "$@"; do
    mkdir -p "$repo/$(dirname "$f")"
    case "$f" in
      src/api.ts) printf 'export function go() {\n  try { run(); } catch (e) { return null; }\n}\n' > "$repo/$f" ;;
      src/App.test.tsx) printf 'test("a", () => { expect(1).toBe(1); });\n' > "$repo/$f" ;;
      src/App.tsx) printf 'export const A = () => <button>ok</button>;\n' > "$repo/$f" ;;
      *) printf 'content\n' > "$repo/$f" ;;
    esac
  done
  g -C "$repo" add -A
  g -C "$repo" commit -qm "branch work"
}
route() { # route <repo> <plan> <base>
  (cd "$1" && HOME="$TMP/home-lens" timeout 60 bash "$LROUTE" "docs/dforge/plans/$2" --final "$3" HEAD 2>&1)
}
t_A18() {
  mkdir -p "$TMP/home-lens"
  local o all='src/App.tsx src/App.test.tsx src/api.ts'

  # contract spec, no profile, all four other lenses match
  new_repo a18a none
  write_plan "$REPO" p.md "$SPEC_REL" src/Dialog.tsx '' a.txt ''
  g -C "$REPO" add -A; g -C "$REPO" commit -qm plan; BASE=$(g -C "$REPO" rev-parse HEAD)
  lens_branch "$REPO" $all
  o=$(route "$REPO" p.md "$BASE")
  has "A18: contract spec, UI file changed: ui-ux is routed" "$o" "lens ui-ux "
  lacks "A18: ui-ux is not cut by the cap" "$o" "lens-skipped ui-ux"
  local id
  for id in security lang-typescript test-quality silent-failures; do
    matches "A18: setup: $id matched the diff" "$o" "^lens(-skipped)? $id( |\$)"
  done

  # profile, spec with no contract
  new_repo a18b web
  write_plan "$REPO" p.md "$PLAIN_SPEC_REL" src/Dialog.tsx '' a.txt ''
  g -C "$REPO" add -A; g -C "$REPO" commit -qm plan; BASE=$(g -C "$REPO" rev-parse HEAD)
  lens_branch "$REPO" $all
  o=$(route "$REPO" p.md "$BASE")
  has "A18: profile project, UI file changed: ui-ux is routed" "$o" "lens ui-ux "
  lacks "A18: ui-ux is not cut by the cap (profile)" "$o" "lens-skipped ui-ux"
  for id in security lang-typescript test-quality silent-failures; do
    matches "A18: setup: $id matched the diff (profile)" "$o" "^lens(-skipped)? $id( |\$)"
  done

  # no UI file changed
  new_repo a18c web
  write_plan "$REPO" p.md "$SPEC_REL" src/Dialog.tsx '' a.txt ''
  g -C "$REPO" add -A; g -C "$REPO" commit -qm plan; BASE=$(g -C "$REPO" rev-parse HEAD)
  lens_branch "$REPO" src/api.ts src/App.test.tsx docs/notes.txt
  o=$(route "$REPO" p.md "$BASE")
  lacks "A18: profile and contract, but no UI file changed: ui-ux is not routed" "$o" "lens ui-ux "
  matches "A18: setup: the route still ran (security routed)" "$o" "^lens security "

  # no profile, spec without a contract, a .tsx file changed
  new_repo a18d none
  write_plan "$REPO" p.md "$PLAIN_SPEC_REL" src/Dialog.tsx '' a.txt ''
  g -C "$REPO" add -A; g -C "$REPO" commit -qm plan; BASE=$(g -C "$REPO" rev-parse HEAD)
  lens_branch "$REPO" $all
  o=$(route "$REPO" p.md "$BASE")
  lacks "A18: no profile, no contract, a .tsx file changed: ui-ux is not routed" "$o" "lens ui-ux "
  absent "A18: nor listed as skipped" "$o" '^lens(-skipped)? ui-ux( |$)'
  matches "A18: setup: the route still ran (lang-typescript matched)" "$o" "^lens(-skipped)? lang-typescript( |\$)"
}

flat() { tr '\n' ' ' < "$1" | sed -E 's/[[:space:]]+/ /g'; }
t_A19() {
  local fr fin
  fr=$(flat "$PLUGIN/reference/final-review.md")
  fin=$(flat "$PLUGIN/skills/finishing-a-development-branch/SKILL.md")
  has "A19: the final review names ui-proof check --base MERGE_BASE --spec" "$fr" "ui-proof check --base MERGE_BASE --spec"
  has "A19: the finishing skill names ui-proof check --base MERGE_BASE --spec" "$fin" "ui-proof check --base MERGE_BASE --spec"
  matches "A19: the final review says exit 1 stops it" "$fr" 'ui-proof check --base MERGE_BASE --spec.{0,600}[Ee]xit 1 stops'
  matches "A19: the finishing skill says exit 1 stops (blocks) integration" "$fin" 'ui-proof check --base MERGE_BASE --spec.{0,1500}[Ee]xit 1.{0,200}(stop|block)'
  matches "A19: the final review names the auto-run path: prove, check again, stop for unverifiable" "$fr" \
    '[Ii]n an auto run, run the dforge:ui-ux Prove phase, then check again.{0,300}unverifiable.{0,200}auto-run stop'
}

t_A21() {
  local qa skill
  qa=$(flat "$PLUGIN/reference/acceptance-qa.md")
  skill=$(flat "$PLUGIN/skills/ui-ux/SKILL.md")
  matches "A21: acceptance-qa.md says a statement starting with a contract ID is written for the profile's UI test runner" "$qa" \
    'starts with a contract ID.{0,120}is written for the UI test runner.{0,80}profile'
  has "A21: SKILL.md says a behaviour statement is tagged demo when the profile names no UI test runner" "$skill" \
    'tagged `demo` when the profile names no UI test runner'
  matches "A21: SKILL.md says a behaviour statement is tagged test when the profile names a runner" "$skill" \
    'tagged `test` when the profile names a UI test runner|`test` when the profile names a UI test runner'
}

t_A22() {
  new_repo a22ctl none
  ui_file "$REPO"
  full_good "$REPO"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A22: control: the judged report passes" "$status" "0"

  new_repo a22a none
  ui_file "$REPO"
  full_good "$REPO"
  rm -f "$REPO/$JUDGE_REL"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A22: a judge line citing a judge file that is missing: exit 1" "$status" "1"

  new_repo a22b none
  ui_file "$REPO"
  full_good "$REPO"
  local f; f=$(fp "$REPO")
  printf 'Disputes UX-1.\n\nVerdict: fix %s\n' "$f" > "$REPO/$JUDGE_REL"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A22: a judge file whose verdict line says fix while the report says ship: exit 1" "$status" "1"
  printf 'Fine.\n\nVerdict: ship %s\n' "$FAKEFP" > "$REPO/$JUDGE_REL"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A22: a judge file whose verdict line carries another fingerprint: exit 1" "$status" "1"
  printf 'Fine.\n\nVerdict: ship %s\n' "$f" > "$REPO/$JUDGE_REL"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A22: control: restoring the matching verdict line passes" "$status" "0"

  new_repo a22c none
  ui_file "$REPO" src/App.tsx
  ui_file "$REPO" src/Panel.tsx '<section>panel</section>'
  commit_path "$REPO" src
  full_good "$REPO"
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A22: control: the committed UI files with a judged report pass" "$status" "0"
  ui_file "$REPO" src/Panel.tsx '<section>fix wave edit</section>'
  commit_path "$REPO" src/Panel.tsx
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A22: a fix wave edits a UI file the fingerprint covered (committed): exit 1" "$status" "1"

  new_repo a22d none
  ui_file "$REPO" src/App.tsx
  full_good "$REPO"
  ui_file "$REPO" src/Extra.css '.a { color: var(--fg); }'
  gate "$REPO" --base "$BASE" --spec "$SPEC_REL"
  check "A22: a fix wave adds an untracked UI file after the verdict: exit 1" "$status" "1"
}

for id in A1 A4 A5 A6 A7 A8 A9 A10 A11 A12 A13 A14 A15 A16 A18 A19 A21 A22; do
  if [ $# -eq 0 ]; then run=1; else run=0; for a in "$@"; do [ "$a" = "$id" ] && run=1; done; fi
  [ "$run" -eq 1 ] && "t_$id"
done

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
