#!/usr/bin/env bash
# scripts/ask and the marker it leaves for the Stop hooks: a question asked this
# turn, after the last recorded work, releases the hold that turn and no other.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/../../plugins/dagents"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
export WORKFLOW_GUARD_CLAUDE_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_MANAGED_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_PROJECT_DIR="$TMP/workflow-guard"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION DAGENTS_BUDGET CLAUDE_PROJECT_DIR
TURNS="$HOME/.claude/dagents/sessions/turns"; mkdir -p "$TURNS"

# --- the marker rule (lib/ask-marker.sh) ---
. "$P/scripts/lib/ask-marker.sh"
check "the marker sits beside the stamp" "$(ask_marker_path 'ab:c 1')" "$TURNS/ab-c-1.asked"
LR="$TMP/sdd"; DOCS="$TMP/docs"; mkdir -p "$LR/p" "$DOCS/plans"
STAMP="$TURNS/s-lib"; touch "$STAMP"
rel() { ask_marker_released "$STAMP" "$LR" "$DOCS" && echo released || echo held; }
check "no marker: held" "$(rel)" "held"
sleep 1; printf 'q\n' > "$STAMP.asked"
check "a marker newer than the stamp: released" "$(rel)" "released"
sleep 1; printf 'Task 1: complete\n' > "$LR/p/progress.md"
check "a ledger written after the marker: held" "$(rel)" "held"
sleep 1; touch "$STAMP.asked"
check "asked again after that work: released" "$(rel)" "released"
sleep 1; touch "$DOCS/plans/completed.md"
check "completed.md written after the marker: held" "$(rel)" "held"
sleep 1; touch "$STAMP.asked"; sleep 1; touch "$DOCS/roadmap.md"
check "roadmap.md written after the marker: held" "$(rel)" "held"
sleep 1; touch "$STAMP.asked"
check "empty roots are skipped" "$(ask_marker_released "$STAMP" "" "" && echo released || echo held)" "released"
sleep 1; touch "$STAMP"
check "a marker older than the stamp: held" "$(rel)" "held"

# --- scripts/ask ---
ASK="$P/scripts/ask"; START="$P/scripts/turn-start.sh"
REPO="$TMP/repo"; git init -q "$REPO"
git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m base
PLAN=docs/dagents/plans/2026-11-19-x.md
WS="$REPO/.dagents/sdd/2026-11-19-x"; mkdir -p "$WS"; LEDGER="$WS/progress.md"
printf '# SDD ledger — plan: %s\nTask 2: implementer inline (assigned; base abc1234)' "$PLAN" > "$LEDGER"
ask() { (cd "$REPO" && CLAUDE_CODE_SESSION_ID="${SID-s-ask}" bash "$ASK" "$@"); }
out=$(ask "$PLAN" 2 $'Which width:\nnarrow or wide?'); st=$?
check "ask with a plan: exit 0" "$st" "0"
check "ask prints the question on one line" "$out" "Which width: narrow or wide?"
check "ask: the waiting line ends the ledger" "$(tail -n 1 "$LEDGER")" "Task 2: waiting — Which width: narrow or wide?"
check "ask: a missing final newline is added first" "$(tail -n 2 "$LEDGER" | head -n 1)" "Task 2: implementer inline (assigned; base abc1234)"
check "ask: the marker holds the question" "$(cat "$TURNS/s-ask.asked")" "Which width: narrow or wide?"
check "ask: the marker is not older than the ledger" "$([ "$LEDGER" -nt "$TURNS/s-ask.asked" ] && echo older || echo ok)" "ok"
rm -f "$TURNS/s-ask.asked"
out=$(ask 'Merge now?'); st=$?
check "ask without a plan: exit 0 and the marker" "$st:$(cat "$TURNS/s-ask.asked")" "0:Merge now?"
rm -f "$TURNS/s-ask.asked"; before=$(cat "$LEDGER")
ask "$PLAN" two 'q?' >/dev/null 2>&1; check "a non-numeric N: exit 2" "$?" "2"
ask "$PLAN" 2 '' >/dev/null 2>&1; check "an empty question: exit 2" "$?" "2"
ask docs/dagents/plans/absent.md 2 'q?' >/dev/null 2>&1; check "a plan with no ledger: exit 2" "$?" "2"
SID='' ask 'q?' >/dev/null 2>&1; check "no plan and no session id: exit 2" "$?" "2"
check "the refusals wrote no ledger line" "$(cat "$LEDGER")" "$before"
check "the refusals wrote no marker" "$([ -e "$TURNS/s-ask.asked" ] && echo yes || echo no)" "no"
out=$(SID='' ask "$PLAN" 3 'Codex host?' 2>"$TMP/err"); st=$?
check "no session id with a plan: exit 0" "$st" "0"
check "no session id with a plan: the ledger line" "$(tail -n 1 "$LEDGER")" "Task 3: waiting — Codex host?"
check "no session id with a plan: says no marker was written" "$(grep -c 'no marker' "$TMP/err")" "1"
if [ "$(id -u)" != 0 ] && ! command -v cygpath >/dev/null 2>&1; then
  chmod 555 "$TURNS"
  ask "$PLAN" 4 'Unwritable?' >/dev/null 2>&1; st=$?
  chmod 755 "$TURNS"
  check "an unwritable marker after the ledger line: exit 1" "$st" "1"
fi
printf 'q\n' > "$TURNS/s-ask.asked"
jq -n --arg cwd "$REPO" '{hook_event_name:"UserPromptSubmit",session_id:"s-ask",cwd:$cwd,prompt:"go"}' | bash "$START"
check "turn-start deletes the session's marker" "$([ -e "$TURNS/s-ask.asked" ] && echo yes || echo no)" "no"

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
