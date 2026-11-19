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

printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
