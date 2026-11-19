#!/usr/bin/env bash
# scripts/ask and the marker it leaves for the Stop hooks: a question asked this
# turn, after the last recorded work, releases the hold that turn and no other.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/../../plugins/dforge"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
export WORKFLOW_GUARD_CLAUDE_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_MANAGED_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_PROJECT_DIR="$TMP/workflow-guard"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION DFORGE_BUDGET CLAUDE_PROJECT_DIR
TURNS="$HOME/.claude/dforge/sessions/turns"; mkdir -p "$TURNS"

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
PLAN=docs/dforge/plans/2026-11-19-x.md
WS="$REPO/.dforge/sdd/2026-11-19-x"; mkdir -p "$WS"; LEDGER="$WS/progress.md"
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
ask docs/dforge/plans/absent.md 2 'q?' >/dev/null 2>&1; check "a plan with no ledger: exit 2" "$?" "2"
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

# --- the Stop hooks ---
END="$P/scripts/turn-end.sh"; UIEND="$P/scripts/ui-turn-end.sh"; AR="$P/scripts/auto-run"
SHOWN="$(cd "$P" && pwd)"; if command -v cygpath >/dev/null 2>&1; then SHOWN=$(cygpath -m "$SHOWN"); fi
prompt() { jq -n --arg sid "$1" --arg cwd "${2:-$REPO}" '{hook_event_name:"UserPromptSubmit",session_id:$sid,cwd:$cwd,prompt:"go"}' | bash "$START"; }
stop_with() { # stop_with <hook> <session> <message> [transcript]
  jq -n --arg sid "$2" --arg cwd "$REPO" --arg msg "$3" --arg tp "${4:-}" \
    '{hook_event_name:"Stop",session_id:$sid,cwd:$cwd,transcript_path:$tp,stop_hook_active:false,last_assistant_message:$msg}' | bash "$1"
}
stop() { stop_with "$END" "$@"; }
decision() { jq -r '.decision // "none"' <<<"${1:-{\}}" 2>/dev/null || echo none; }
ledger() { sleep 1; printf '# SDD ledger — plan: %s\n%s\n' "$PLAN" "$1" > "$LEDGER"; }
asked() { sleep 1; SID="$1" ask "${@:2}" >/dev/null; }

sleep 1; prompt s-h; ledger 'Task 1: complete (commits a..b, review clean)'
out=$(stop s-h 'Task 1 is done.')
check "mid-plan summary: held" "$(decision "$out")" "block"
check "the mid-plan reason names ask with the plan" "$(jq -r .reason <<<"$out" | grep -cF "\`bash \"$SHOWN/scripts/ask\" $PLAN N")" "1"
check "the mid-plan reason offers next-step only for an ending session" "$(jq -r .reason <<<"$out" | grep -c 'If the session is ending, run')" "1"
asked s-h 'Which width?'
check "mid-plan, asked this turn: passes" "$(stop s-h 'Which width?')" ""
sleep 1; prompt s-h; ledger 'Task 2: complete (commits c..d, review clean)'
check "a question asked in an earlier turn releases nothing" "$(decision "$(stop s-h 'Task 2 is done.')")" "block"
asked s-h 'Which width?'; ledger 'Task 3: complete (commits e..f, review clean)'
check "work recorded after the question: held" "$(decision "$(stop s-h 'Task 3 is done.')")" "block"

h=$(git -C "$REPO" rev-parse --short HEAD)
sleep 1; prompt s-c; ledger "Task 1: complete (commits a..b, review clean)"$'\n'"Final review: clean (commits $h..$h)"
out=$(stop s-c 'All done.')
check "clean final review summary: held" "$(decision "$out")" "block"
check "the clean final review takes the clean branch" "$(jq -r .reason <<<"$out" | grep -c 'passed its final review')" "1"
check "the clean-review reason names ask without a plan" "$(jq -r .reason <<<"$out" | grep -cF "\`bash \"$SHOWN/scripts/ask\" \"<question>\"\`")" "1"
asked s-c 'Merge, or open a pull request?'
check "clean final review, asked: passes" "$(stop s-c 'Merge, or open a pull request?')" ""

mkdir -p "$REPO/docs/dforge/plans"; printf '# Completed plans\n' > "$REPO/docs/dforge/plans/completed.md"
git -C "$REPO" add docs && git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -qm 'docs: completed'
sleep 1; prompt s-t; sleep 1
printf -- '- 2026-11-19 `docs/dforge/plans/2026-11-19-y.md` — merged into `main`\n' >> "$REPO/docs/dforge/plans/completed.md"
out=$(stop s-t 'Merged.')
check "a transition summary: held" "$(decision "$out")" "block"
check "the transition reason names ask" "$(jq -r .reason <<<"$out" | grep -c 'scripts/ask')" "1"
asked s-t 'Start the next milestone now?'
check "a transition, asked: passes" "$(stop s-t 'Start the next milestone now?')" ""

for dash in '—' '–' '-'; do
  sleep 1; prompt s-d; ledger "Task 4: waiting $dash which colour?"
  check "a typed waiting line with '$dash': passes" "$(stop s-d 'Which colour?')" ""
done

BG="$TMP/bg.jsonl"
jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_bg",name:"Bash",input:{description:"Long suite",command:"sleep 600",run_in_background:true}}]}}' > "$BG"
jq -nc '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_bg",content:"Command running in background with ID: b1. Output is being written to: /tmp/b1.output."}]}}' >> "$BG"
sleep 1; prompt s-b; ledger 'Task 5: complete (commits a..b, review clean)'; asked s-b 'Which width?'
check "a question does not release a session-ending block over running work" \
  "$(decision "$(stop s-b $'## Next session\n\n**Status:** x\n**Next:** x' "$BG")")" "block"

mkdir -p "$HOME/.claude/dforge/sessions/cockpit"; date +%s > "$HOME/.claude/dforge/sessions/cockpit/s-ar"
(cd "$REPO" && bash "$AR" --session s-ar start --spec docs/s.md --register docs/r.md >/dev/null)
sleep 1; prompt s-ar; asked s-ar 'Which width?'
check "a question does not release the auto-run hold" "$(decision "$(stop s-ar 'Which width?')")" "block"
(cd "$REPO" && bash "$AR" --session s-ar stop --reason test >/dev/null 2>&1)

# ui-turn-end: a UI change without proof is held unless a question was asked.
mkdir -p "$REPO/src" "$REPO/docs/dforge/ui-ux"
printf '# UI profile\n\n**Platform:** web\n' > "$REPO/docs/dforge/ui-ux/profile.md"
printf 'export const A = () => <main/>;\n' > "$REPO/src/App.tsx"
git -C "$REPO" add -A && git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -qm base-ui
sleep 1; prompt s-u
printf '// change\n' >> "$REPO/src/App.tsx"; git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -qam 'ui change'
rm -rf "$REPO/.dforge/sdd"
check "ui: a UI change without proof is held" "$(decision "$(stop_with "$UIEND" s-u 'Done.')")" "block"
asked s-u 'Which colour?'
check "ui: asked this turn: passes" "$(decision "$(stop_with "$UIEND" s-u 'Which colour?')")" "none"
mkdir -p "$WS"
for dash in '—' '–' '-'; do
  sleep 1; prompt s-u2; printf '// %s\n' "$dash" >> "$REPO/src/App.tsx"; git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -qam "ui $dash"
  ledger "Task 4: waiting $dash which colour?"
  check "ui: a typed waiting line with '$dash': passes" "$(decision "$(stop_with "$UIEND" s-u2 'Which colour?')")" "none"
done

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
