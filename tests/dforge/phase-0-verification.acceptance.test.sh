#!/usr/bin/env bash
# Acceptance tests A1-A8 of the phase-0-verification spec: scripts/ask, the
# marker it leaves, and the Stop hooks' question exits. Written from the spec's
# statements; the hooks run as Claude Code runs them, on JSON from stdin.
set -uo pipefail

PL=dforge
PFX=""
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/../../plugins/$PL"
ASK="$P/scripts/ask"; START="$P/scripts/turn-start.sh"; END="$P/scripts/turn-end.sh"; UIEND="$P/scripts/ui-turn-end.sh"
AR="$P/scripts/auto-run"; PLIB="$P/scripts/lib/plan.sh"
# The plugin root as the hooks show it in a hold reason.
SHOWN="$(cd "$P" && pwd)"
if command -v cygpath >/dev/null 2>&1; then SHOWN=$(cygpath -m "$SHOWN"); fi

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
export WORKFLOW_GUARD_CLAUDE_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_MANAGED_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_PROJECT_DIR="$TMP/workflow-guard"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION DFORGE_BUDGET DAGENTS_BUDGET CLAUDE_PROJECT_DIR
TURNS="$HOME/.claude/$PL/sessions/turns"
PLAN="docs/$PL/plans/2026-11-19-qa.md"
SLUG=2026-11-19-qa

CWD="" SID=""
git_c() { git -C "$1" -c user.name=t -c user.email=t@example.invalid "${@:2}"; }
commit_all() { git_c "$1" add -A && git_c "$1" commit -q -m "$2"; }
new_repo() { git init -q "$TMP/$1" && git_c "$TMP/$1" commit -q --allow-empty -m base && printf '%s' "$TMP/$1"; }
back() { touch -d "$2 seconds ago" "$1"; } # back <file> <seconds>: set the mtime into the past
prompt() { jq -n --arg sid "$1" --arg cwd "$CWD" '{hook_event_name:"UserPromptSubmit",session_id:$sid,cwd:$cwd,prompt:"go"}' | bash "$START"; }
# A turn starts; its stamp is set back so work written during it reads as newer
# without the test waiting out filesystem timestamp granularity.
turn() { prompt "$1"; back "$TURNS/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')" 6; }
stop_with() { # stop_with <script> <session> <last message> [stop_hook_active] [transcript]
  jq -n --arg sid "$2" --arg cwd "$CWD" --arg msg "$3" --argjson active "${4:-false}" --arg tp "${5:-}" \
    '{hook_event_name:"Stop",session_id:$sid,cwd:$cwd,transcript_path:$tp,stop_hook_active:$active,last_assistant_message:$msg}' | bash "$1"
}
stop() { stop_with "$END" "$@"; }
ui_stop() { stop_with "$UIEND" "$@"; }
decision() { jq -r '.decision // "none"' <<<"${1:-{\}}" 2>/dev/null || echo none; }
reason() { jq -r '.reason // empty' <<<"$1"; }
ask_cli() { (cd "$CWD" && CLAUDE_CODE_SESSION_ID="$SID" bash "$ASK" "$@"); }
marker_of() { printf '%s/%s.asked' "$TURNS" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"; }
markers() { find "$TURNS" -name '*.asked' 2>/dev/null | wc -l | tr -d ' '; }
set_ledger() { # set_ledger <lines after the header>; the file is older than the next ask
  mkdir -p "$(dirname "$LEDGER")"
  printf '# SDD ledger — plan: %s\n%s\n' "$PLAN" "$1" > "$LEDGER"
  back "$LEDGER" 3
}
use_repo() { CWD=$(new_repo "$1"); LEDGER="$CWD/.$PL/sdd/$SLUG/progress.md"; mkdir -p "${LEDGER%/*}"; }
trans_repo() { # trans_repo <name>: a checkout with a completed.md and a two-milestone roadmap
  CWD=$(new_repo "$1")
  mkdir -p "$CWD/docs/$PL/plans"
  printf '# Completed plans\n\n- 2026-11-01 `docs/%s/plans/2026-11-01-old.md` — merged into `main`\n' "$PL" > "$CWD/docs/$PL/plans/completed.md"
  { printf '# Roadmap\n\n| M | Name | Exit | Register | State | Note |\n|---|---|---|---|---|---|\n'
    printf '| M1 | One | it works | `docs/%s/registers/M1.md` | open | - |\n| M2 | Two | it works | `docs/%s/registers/M2.md` | open | - |\n' "$PL" "$PL"; } > "$CWD/docs/$PL/roadmap.md"
  commit_all "$CWD" 'docs: roadmap'
}
record_plan() { # record_plan <slug>: a plan recorded complete this turn
  printf -- '- 2026-11-16 `docs/%s/plans/%s.md` — merged into `main`\n' "$PL" "$1" >> "$CWD/docs/$PL/plans/completed.md"
  commit_all "$CWD" "docs: record $1"
  back "$CWD/docs/$PL/plans/completed.md" 3
}
close_m1() {
  sed 's/| M1 | One | \(.*\) | open |/| M1 | One | \1 | closed |/' "$CWD/docs/$PL/roadmap.md" > "$TMP/roadmap.tmp" && mv "$TMP/roadmap.tmp" "$CWD/docs/$PL/roadmap.md"
  commit_all "$CWD" 'docs: close M1'
  back "$CWD/docs/$PL/roadmap.md" 3
}
ui_repo() { # ui_repo <name>: a UI profile and a UI file
  CWD=$(new_repo "$1")
  mkdir -p "$CWD/src" "$CWD/docs/$PL/ui-ux"
  printf 'export const App = () => <main>Hi</main>;\n' > "$CWD/src/App.tsx"
  printf '# UI profile\n\n**Platform:** web\n' > "$CWD/docs/$PL/ui-ux/profile.md"
  LEDGER="$CWD/.$PL/sdd/$SLUG/progress.md"
  commit_all "$CWD" 'ui base'
}
ui_change() { printf '// change %s\n' "$1" >> "$CWD/src/App.tsx"; commit_all "$CWD" "ui change $1"; }

# --- A1: scripts/ask records the question ---
use_repo a1
printf '# SDD ledger — plan: %s\nTask 2: implementer inline (assigned; base abc1234)' "$PLAN" > "$LEDGER"
SID=a1-sess
out=$(ask_cli "$PLAN" 2 $'Which width:\nnarrow or wide?' 2>/dev/null); st=$?
check "${PFX}A1: ask PLAN N with a session id: exit 0" "$st" "0"
check "${PFX}A1: ask prints the question on one line" "$out" "Which width: narrow or wide?"
check "${PFX}A1: the waiting line is the ledger's last line" "$(tail -n 1 "$LEDGER")" "Task 2: waiting — Which width: narrow or wide?"
check "${PFX}A1: a missing final newline is added first" "$(tail -n 2 "$LEDGER" | head -n 1)" "Task 2: implementer inline (assigned; base abc1234)"
check "${PFX}A1: the ledger gained exactly one line" "$(wc -l < "$LEDGER" | tr -d ' ')" "3"
check "${PFX}A1: the marker holds the question" "$(cat "$(marker_of "$SID")" 2>/dev/null)" "Which width: narrow or wide?"
lines=$(wc -l < "$LEDGER" | tr -d ' ')
out=$(ask_cli "$PLAN" 2 'Second question?' 2>/dev/null); st=$?
check "${PFX}A1: a ledger that ends in a newline gets no blank line" "$(tail -n 2 "$LEDGER" | head -n 1):$(wc -l < "$LEDGER" | tr -d ' ')" "Task 2: waiting — Which width: narrow or wide?:$((lines + 1))"
rm -f "$(marker_of "$SID")"
before=$(cksum < "$LEDGER")
out=$(ask_cli 'Merge now?' 2>/dev/null); st=$?
check "${PFX}A1: ask \"<q>\": exit 0" "$st" "0"
check "${PFX}A1: ask \"<q>\" prints the question" "$out" "Merge now?"
check "${PFX}A1: ask \"<q>\" records the marker" "$(cat "$(marker_of "$SID")" 2>/dev/null)" "Merge now?"
check "${PFX}A1: ask \"<q>\" writes no ledger line" "$(cksum < "$LEDGER")" "$before"
rm -f "$(marker_of "$SID")"
SID='ab:c 1'
ask_cli 'Odd id?' >/dev/null 2>&1
check "${PFX}A1: the session id is sanitised in the marker's name" "$(cat "$TURNS/ab-c-1.asked" 2>/dev/null)" "Odd id?"
rm -f "$TURNS/ab-c-1.asked"

# --- A7: refusals write nothing ---
use_repo a7
printf '# SDD ledger — plan: %s\nTask 2: implementer inline (assigned; base abc1234)\n' "$PLAN" > "$LEDGER"
SID=a7-sess
before=$(cksum < "$LEDGER")
refused() { # refused <name> <args...>: exit 2, no marker, the ledger as it was
  local name=$1; shift
  ask_cli "$@" >/dev/null 2>&1; local st=$?
  check "${PFX}A7: $name: exit 2" "$st" "2"
  check "${PFX}A7: $name: no marker" "$(markers)" "0"
  check "${PFX}A7: $name: the ledger is unchanged" "$(cksum < "$LEDGER")" "$before"
}
refused "a non-numeric N" "$PLAN" two 'q?'
refused "N with a trailing letter" "$PLAN" 2x 'q?'
refused "a negative N" "$PLAN" -1 'q?'
refused "an empty N" "$PLAN" '' 'q?'
refused "an empty question with a plan" "$PLAN" 2 ''
refused "an empty question without a plan" ''
ask_cli "docs/$PL/plans/2026-11-19-missing.md" 2 'q?' >/dev/null 2>&1; st=$?
check "${PFX}A7: a PLAN_FILE with no ledger: exit 2" "$st" "2"
check "${PFX}A7: a PLAN_FILE with no ledger: no marker" "$(markers)" "0"
check "${PFX}A7: a PLAN_FILE with no ledger: nothing is created" "$(find "$CWD/.$PL" -type f | sort | tr '\n' ' ')" "$LEDGER "
SID=""
ask_cli 'q?' >/dev/null 2>&1; st=$?
check "${PFX}A7: no plan and no session id: exit 2" "$st" "2"
check "${PFX}A7: no plan and no session id: no marker" "$(markers)" "0"
check "${PFX}A7: no plan and no session id: the ledger is unchanged" "$(cksum < "$LEDGER")" "$before"
ask_cli "$PLAN" 2 'q?' >/dev/null 2>&1; st=$?
check "${PFX}A7: control, a plan and no session id: the ledger line is written" "$st:$(tail -n 1 "$LEDGER")" "0:Task 2: waiting — q?"

# --- A2, A4, A8: the three paths, a question this turn and one in an earlier turn ---
# A plan mid-task.
use_repo mid
SID=mid-sess
turn "$SID"; set_ledger 'Task 1: complete (commits a..b, review clean)'
mid_hold=$(stop "$SID" 'Task 1 is done. Everything looks good.')
check "${PFX}A2: a plan mid-task is held without a question" "$(decision "$mid_hold")" "block"
ask_cli 'Which database should it use?' >/dev/null 2>&1
check "${PFX}A2: a plan mid-task: passes after scripts/ask" "$(stop "$SID" 'Which database should it use?')" ""
turn "$SID"; set_ledger 'Task 1: complete (commits a..b, review clean)'
check "${PFX}A4: a plan mid-task: a question from an earlier turn releases nothing" "$(stop "$SID" 'Task 1 is done. Everything looks good.')" "$mid_hold"

# A plan whose final review is clean and current.
use_repo clean
SID=clean-sess
head=$(git -C "$CWD" rev-parse --short HEAD)
turn "$SID"; set_ledger "Final review: clean (commits 0000000..$head)"
clean_hold=$(stop "$SID" 'All tasks complete and the final review is clean.')
check "${PFX}A2: a clean current final review is held without a question" "$(decision "$clean_hold")" "block"
ask_cli 'Should I merge or open a pull request?' >/dev/null 2>&1
check "${PFX}A2: a clean current final review: passes after scripts/ask" "$(stop "$SID" 'Should I merge or open a pull request?')" ""
turn "$SID"; set_ledger "Final review: clean (commits 0000000..$head)"
check "${PFX}A4: a clean final review: a question from an earlier turn releases nothing" "$(stop "$SID" 'All tasks complete and the final review is clean.')" "$clean_hold"

# A completed.md transition.
trans_repo comp
SID=comp-sess
turn "$SID"; record_plan 2026-11-16-p
comp_hold=$(stop "$SID" 'Merged.')
check "${PFX}A2: a completed.md transition is held without a question" "$(decision "$comp_hold")" "block"
ask_cli 'Start the next plan now?' >/dev/null 2>&1
check "${PFX}A2: a completed.md transition: passes after scripts/ask" "$(stop "$SID" 'Start the next plan now?')" ""
turn "$SID"; record_plan 2026-11-17-q
out=$(stop "$SID" 'Merged.')
check "${PFX}A4: a completed.md transition: a question from an earlier turn releases nothing" "$(decision "$out"):$(reason "$out" | grep -c "2026-11-17-q.md")" "block:1"

# A roadmap transition.
trans_repo road
SID=road-sess
turn "$SID"; close_m1
road_hold=$(stop "$SID" 'M1 closed.')
check "${PFX}A2: a roadmap transition is held without a question" "$(decision "$road_hold")" "block"
ask_cli 'Which milestone next?' >/dev/null 2>&1
check "${PFX}A2: a roadmap transition: passes after scripts/ask" "$(stop "$SID" 'Which milestone next?')" ""
sed 's/| M2 | Two | \(.*\) | open |/| M2 | Two | \1 | closed |/' "$CWD/docs/$PL/roadmap.md" > "$TMP/roadmap.tmp" && mv "$TMP/roadmap.tmp" "$CWD/docs/$PL/roadmap.md"
commit_all "$CWD" 'docs: close M2'
turn "$SID"
sed 's/| M2 | Two | \(.*\) | closed |/| M2 | Two | \1 | open |/' "$CWD/docs/$PL/roadmap.md" > "$TMP/roadmap.tmp" && mv "$TMP/roadmap.tmp" "$CWD/docs/$PL/roadmap.md"
sed 's/| M1 | One | \(.*\) | closed |/| M1 | One | \1 | open |/' "$CWD/docs/$PL/roadmap.md" > "$TMP/roadmap.tmp" && mv "$TMP/roadmap.tmp" "$CWD/docs/$PL/roadmap.md"
commit_all "$CWD" 'docs: reopen M1'
sed 's/| M2 | Two | \(.*\) | open |/| M2 | Two | \1 | closed |/' "$CWD/docs/$PL/roadmap.md" > "$TMP/roadmap.tmp" && mv "$TMP/roadmap.tmp" "$CWD/docs/$PL/roadmap.md"
commit_all "$CWD" 'docs: close M2 again'
back "$CWD/docs/$PL/roadmap.md" 3
check "${PFX}A4: a roadmap transition: a question from an earlier turn releases nothing" "$(decision "$(stop "$SID" 'M2 closed.')")" "block"

# A UI turn without proof.
ui_repo ui
SID=ui-sess
turn "$SID"; ui_change 1
ui_hold=$(ui_stop "$SID" 'Done.')
check "${PFX}A3: a UI change without proof is held without a question" "$(decision "$ui_hold")" "block"
ask_cli 'Which colour should the button be?' >/dev/null 2>&1
check "${PFX}A3: a UI change without proof: passes after scripts/ask" "$(ui_stop "$SID" 'Which colour should the button be?')" ""
# The next turn's stamp, however it came to be newer than the marker, ends the question's release.
sleep 1; touch "$TURNS/$SID"
check "${PFX}A4: a UI change without proof: a marker older than the turn's stamp releases nothing" "$(decision "$(ui_stop "$SID" 'Done.')")" "block"
turn "$SID"; ui_change 2
check "${PFX}A4: a UI change without proof: a question from an earlier turn releases nothing" "$(decision "$(ui_stop "$SID" 'Done.')")" "block"

# --- A5: a question never releases the auto-run hold or the session-ending hold over running work ---
use_repo auto
SID=auto-sess
mkdir -p "$HOME/.claude/$PL/sessions/cockpit"
date +%s > "$HOME/.claude/$PL/sessions/cockpit/$SID"
(cd "$CWD" && bash "$AR" --session "$SID" start --spec docs/s.md --register docs/r.md >/dev/null 2>&1)
turn "$SID"; set_ledger 'Task 2: complete (commits a..b, review clean)'
auto_hold=$(stop "$SID" 'Task 2 is done. Everything looks good.')
check "${PFX}A5: an auto run holds a summary without a question" "$(decision "$auto_hold"):$(reason "$auto_hold" | grep -c 'Auto run: compacting')" "block:1"
ask_cli 'Should I carry on?' >/dev/null 2>&1
out=$(stop "$SID" 'Should I carry on?')
check "${PFX}A5: an auto run's hold stands after scripts/ask" "$(decision "$out"):$(jq -r .systemMessage <<<"$out" | grep -c 'auto run, hold 1 of 3')" "block:1"
out=$(stop "$SID" 'Should I carry on?' true)
check "${PFX}A5: an auto run's retry is held again after scripts/ask" "$(decision "$out"):$(jq -r .systemMessage <<<"$out" | grep -c 'hold 2 of 3')" "block:1"

use_repo bg
SID=bg-sess
BG="$TMP/background.jsonl"
jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Dispatched."}]}}' > "$BG"
jq -nc '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_bash",content:"Command running in background with ID: b1. Output is being written to: /tmp/b1.output."}]}}' >> "$BG"
ENDING=$'Stopping here.\n\n## Next session\n\n**Status:** x\n**Next:** x'
turn "$SID"
bg_hold=$(stop "$SID" "$ENDING" false "$BG")
check "${PFX}A5: a session-ending message over running work is held without a question" "$(decision "$bg_hold"):$(reason "$bg_hold" | grep -c '1 background launch')" "block:1"
ask_cli 'Should I wait for it?' >/dev/null 2>&1
out=$(stop "$SID" "$ENDING" false "$BG")
check "${PFX}A5: the session-ending hold over running work stands after scripts/ask" "$(decision "$out"):$(reason "$out" | grep -c '1 background launch')" "block:1"

# --- A6: one waiting-line grammar ---
use_repo six
. "$PLIB"
n=0
for dash in '—' '–' '-'; do
  n=$((n + 1)); SID="six-$n"
  turn "$SID"; set_ledger $'Task 4: implementer inline (assigned; base abc1234)\nTask 4: waiting '"$dash"$' which colour?'
  check "${PFX}A6: turn-end: a waiting line with '$dash' releases the mid-plan hold" "$(stop "$SID" 'Which colour?')" ""
  printf '# SDD ledger — plan: %s\nTask 2: BLOCKED — needs a ruling\nTask 2: waiting %s which colour?\n' "$PLAN" "$dash" > "$TMP/blocked.md"
  check "${PFX}A6: ledger_blocked steps over a waiting line with '$dash'" "$(ledger_blocked "$TMP/blocked.md")" "2"
done
printf '# SDD ledger — plan: %s\nTask 2: BLOCKED — needs a ruling\nTask 2: implementer inline (assigned; base abc1234)\n' "$PLAN" > "$TMP/unblocked.md"
check "${PFX}A6: ledger_blocked: a later task line that is not a waiting line clears the block" "$(ledger_blocked "$TMP/unblocked.md")" ""
SID=six-ctl; turn "$SID"; set_ledger $'Task 4: implementer inline (assigned; base abc1234)\nTask 4: waiting which colour?'
check "${PFX}A6: turn-end: a waiting line with no dash releases nothing" "$(decision "$(stop "$SID" 'Which colour?')")" "block"
ui_repo sixui
n=0
for dash in '—' '–' '-'; do
  n=$((n + 1)); SID="sixui-$n"
  turn "$SID"; ui_change "$n"
  set_ledger $'Task 4: implementer inline (assigned; base abc1234)\nTask 4: waiting '"$dash"$' which colour?'
  check "${PFX}A6: ui-turn-end: a waiting line with '$dash' releases the hold" "$(ui_stop "$SID" 'Which colour should the button be?')" ""
done
SID=sixui-ctl; turn "$SID"; ui_change 9
set_ledger $'Task 4: implementer inline (assigned; base abc1234)\nTask 4: waiting which colour?'
check "${PFX}A6: ui-turn-end: a waiting line with no dash releases nothing" "$(decision "$(ui_stop "$SID" 'Which colour should the button be?')")" "block"

# --- A8: what a hold names ---
mid_reason=$(reason "$mid_hold")
check "${PFX}A8: the not-clean hold names scripts/ask PLAN N, with the full path" \
  "$(grep -cE "bash \"$SHOWN/scripts/ask\" ($PLAN|PLAN) N" <<<"$mid_reason")" "1"
before_next=${mid_reason%%scripts/next-step*}
check "${PFX}A8: the not-clean hold names next-step only for a session that is ending" \
  "$([[ $mid_reason == *scripts/next-step* && $before_next == *'is ending'* ]] && echo yes || echo no)" "yes"
check "${PFX}A8: the not-clean hold does not offer the plan-less form" "$(grep -c "scripts/ask\" \"<question>\"" <<<"$mid_reason")" "0"
for held in clean_hold comp_hold road_hold; do
  r=$(reason "${!held}")
  check "${PFX}A8: the ${held%_hold} hold names scripts/ask \"<question>\", with the full path" \
    "$(grep -cF "bash \"$SHOWN/scripts/ask\" \"<question>\"" <<<"$r")" "1"
  check "${PFX}A8: the ${held%_hold} hold does not name a plan and task for the question" \
    "$(grep -cE "scripts/ask\" ($PLAN|PLAN|[^ \"]+\\.md) N" <<<"$r")" "0"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
