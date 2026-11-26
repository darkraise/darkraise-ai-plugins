#!/usr/bin/env bash
# An auto run measures every phase against its limit, with `hard` capping the
# high regime outside execute, and stops a phase that compacts again and again
# without progress.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AR="$HERE/../../plugins/dforge/scripts/auto-run"
LIB="$HERE/../../plugins/dforge/scripts/lib"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <text> <needle>
  case $2 in *"$3"*) check "$1" yes yes ;; *) check "$1" "$2" "contains: $3" ;; esac
}

TMP="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export MSYS_NO_PATHCONV=1 DFORGE_NO_SETTINGS=1 GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
. "$HERE/fixtures/cockpit-ack.sh"
cockpit_ack_start "$HOME"
unset DFORGE_BIND_WAIT DFORGE_BUDGET DFORGE_JQ DFORGE_FLOCK DR_SUPERPOWERS_BUDGET DR_SUPERPOWERS_JQ CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR

REPO="$TMP/repo"
git init -q -b main "$REPO"
git -C "$REPO" commit -q --allow-empty -m init
STATE="$REPO/.dforge/sdd/auto-run.json"
SPEC=docs/dforge/specs/2026-11-25-widget-design.md
beat() { # beat <session>: the heartbeat a live cockpit writes
  local f
  f="$HOME/.claude/dforge/sessions/cockpit/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$(date +%s)" > "$f"
}
ar() {
  [ "${1:-}" != --session ] || beat "$2"
  (cd "$REPO" && bash "$AR" "$@")
}
field() { jq -r --arg f "$1" '.[$f] | tostring' "$STATE"; }
setf() { jq "$1" "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"; }
compactions() { # compactions N: N compacted calls; prints their exits
  local i out=""
  for ((i = 0; i < $1; i++)); do ar --session s-p compacted >/dev/null 2>&1; out="$out$?"; done
  printf '%s' "$out"
}

# --- hard ---
hard() { (. "$LIB/context.sh" && . "$LIB/auto-run.sh" && ar_hard "$@"); }
check "hard: the formula (A9)" "$(hard 300000 800000)|$(hard 465000 500000)|$(hard 100000 800000)" "375000|465000|125000"

# --- progress ---
ar --session s-p start --spec "$SPEC" >/dev/null 2>&1
ar --session s-p phase plan >/dev/null 2>&1
check "progress: three compactions in plan stop the run (A9)" "$(compactions 3)|$(field stopped)" "005|3 compactions in plan without progress"

ar --session s-p start --spec "$SPEC" --force >/dev/null 2>&1
ar --session s-p phase final >/dev/null 2>&1
a=$(compactions 2)
git -C "$REPO" commit -q --allow-empty -m progress
b=$(compactions 2)
check "progress: a commit restarts the count (A9)" "$a$b|$(field compactionsSinceProgress)|$(field active)" "0000|2|true"

mkdir -p "$REPO/docs/dforge/plans" "$REPO/.dforge/sdd/2026-11-26-widget"
printf '# Widget Plan\n\n**Spec:** `%s`\n\n### Task 1: One\n\nBody.\n' "$SPEC" > "$REPO/docs/dforge/plans/2026-11-26-widget.md"
LEDGER="$REPO/.dforge/sdd/2026-11-26-widget/progress.md"
printf '# SDD ledger — plan: docs/dforge/plans/2026-11-26-widget.md\n' > "$LEDGER"
ar --session s-p start --spec "$SPEC" --force >/dev/null 2>&1
ar --session s-p attach --plan docs/dforge/plans/2026-11-26-widget.md
ar --session s-p phase final >/dev/null 2>&1
a=$(compactions 2)
printf 'Task 1: implementer inline (assigned; base abc1234)\n' >> "$LEDGER"
b=$(compactions 2)
check "progress: a ledger line restarts the count (A9)" "$a$b|$(field compactionsSinceProgress)|$(field active)" "0000|2|true"

ar --session s-p start --spec "$SPEC" --force >/dev/null 2>&1
ar --session s-p phase plan >/dev/null 2>&1
a=$(compactions 2)
touch -d "@$(( $(date +%s) + 100 ))" "$REPO/docs/dforge/plans/2026-11-26-widget.md"
b=$(compactions 1)
check "progress: a saved draft restarts the count (A9)" "$a$b|$(field compactionsSinceProgress)|$(field active)" "000|1|true"

ar --session s-p start --spec "$SPEC" --force >/dev/null 2>&1
setf '.phase = "execute"'
check "progress: execute keeps its own count" "$(compactions 3)|$(field stopped)" "005|3 compactions without a completed task"
ar --session s-p start --spec "$SPEC" --force >/dev/null 2>&1
git -C "$REPO" checkout -q -b auto/widget
setf '.phase = "execute" | .isolation = "in-place" | .branch = "auto/widget" | .branchBase = "main"'
a=$(compactions 2)
ar --session s-p task-complete >/dev/null 2>&1
b=$(compactions 2)
check "progress: task-complete resets execute's count" "$a$b|$(field compactionsSinceTask)|$(field active)" "0000|2|true"
git -C "$REPO" checkout -q main

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
