#!/usr/bin/env bash
# Usage markers: task-brief --open writes one open row into the primary
# checkout's usage-markers.tsv, a mark is written once, and a mark that cannot
# be written changes nothing its caller prints or returns.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$(cd "$HERE/../../plugins/dforge" && pwd)"
BRIEF="$P/scripts/task-brief"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP=$(mktemp -d)
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.claude"
export MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1
export GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
unset DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR \
  USAGE_MARK USAGE_MARK_PLAN USAGE_MARK_TASKS USAGE_MARK_CALLER USAGE_MARK_RANGE USAGE_MARK_DEFERRED

VERSION=$(jq -r .version < "$P/.claude-plugin/plugin.json")

# fixture DIR — a repository with a one-task plan, committed at a fixed date.
fixture() {
  git init -q "$1"
  git -C "$1" config user.name Darkraise
  git -C "$1" config user.email dark@example.invalid
  mkdir -p "$1/docs/plans"
  printf '# Fixture\n\n**Goal:** Fixture.\n\n## Global Constraints\n\n- None.\n\n### Task 1: one\n\nBody.\n' \
    > "$1/docs/plans/p.md"
  git -C "$1" add docs
  git -C "$1" commit -q -m init
}

# transcript SID TOKENS — the session's transcript, found by its id.
transcript() {
  mkdir -p "$HOME/.claude/projects/fx"
  printf '{"type":"assistant","isSidechain":false,"message":{"model":"claude-opus-5-5","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":%s}}}\n' \
    "$2" > "$HOME/.claude/projects/fx/$1.jsonl"
  printf '%s' "$HOME/.claude/projects/fx/$1.jsonl"
}

# --- open_row_from_worktree ---
REPO="$TMP/repo"
fixture "$REPO"
git -C "$REPO" worktree add -q "$TMP/w" -b w
T=$(transcript s1 120000)
(cd "$TMP/w" && CLAUDE_CODE_SESSION_ID=s1 bash "$BRIEF" --open docs/plans/p.md 1 >/dev/null 2>&1)
M="$REPO/.dforge/sdd/usage-markers.tsv"
check "open_row_from_worktree: one row in the primary checkout" "$(wc -l < "$M" 2>/dev/null | tr -d ' ')" "1"
check "open_row_from_worktree: 14 columns" "$(awk -F'\t' '{print NF}' "$M" 2>/dev/null)" "14"
check "open_row_from_worktree: the time is UTC" \
  "$(awk -F'\t' '$1 ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/ {print "utc"}' "$M" 2>/dev/null)" "utc"
check "open_row_from_worktree: columns 2-14" "$(cut -f2- "$M" 2>/dev/null)" \
  "$(printf 'open\tdforge\t%s\t%s\tdocs/plans/p.md\t1\ts1\t%s\t%s\t120000\ttask-brief:1\t\t' \
    "$VERSION" "$P" "$T" "$(wc -c < "$T" | tr -d ' ')")"
check "open_row_from_worktree: nothing in the worktree's state" "$([ -e "$TMP/w/.dforge/sdd/usage-markers.tsv" ] && echo yes || echo no)" "no"
check "open_row_from_worktree: the primary checkout stays clean" "$(git -C "$REPO" status --porcelain=v1 --untracked-files=all)" ""

# --- open_dedup ---
mark() { # mark SID ARGS… — um_mark in REPO as session SID
  (cd "$REPO" && CLAUDE_CODE_SESSION_ID=$1 bash -c '. "$1/scripts/lib/context.sh"; . "$1/scripts/lib/usage-marker.sh"; shift; um_mark "$@"' _ "$P" "${@:2}")
}
rm -f "$M"
mark s1 open docs/plans/p.md 1 "" task-brief:1
mark s1 open docs/plans/p.md 1 "" task-brief:1
check "open_dedup: a second open in one session writes nothing" "$(wc -l < "$M" | tr -d ' ')" "1"
mark s2 open docs/plans/p.md 1 "" task-brief:1
check "open_dedup: an open in another session writes a row" "$(wc -l < "$M" | tr -d ' ')" "2"
mark s2 close docs/plans/p.md 1 "" task-close:1 a..b
check "open_dedup: a close writes a row" "$(awk -F'\t' '$2 == "close" {print $13 "|" $14}' "$M")" "a..b|"
mark s2 close docs/plans/p.md 1 "" task-close:1 a..b
check "open_dedup: a second close writes nothing" "$(wc -l < "$M" | tr -d ' ')" "3"
mark s3 open docs/plans/p.md 1 "" task-brief:1
check "open_dedup: an open after the close writes nothing" "$(wc -l < "$M" | tr -d ' ')" "3"
mark s3 open docs/plans/p.md 2 "" task-brief:2
check "open_dedup: another task is its own" "$(wc -l < "$M" | tr -d ' ')" "4"
check "open_dedup: a mark prints nothing" "$(mark s4 open docs/plans/p.md 5 "" task-brief:5)" ""

# --- marker_failure_silent ---
# Each pair runs at one path, so the brief's paths in stdout are the same.
run_pair() { # run_pair LABEL SID — normal run, then the same checkout with the marker path a directory
  local d="$TMP/pair" out1 out2 st1 st2
  rm -rf "$d"; fixture "$d"
  out1=$(cd "$d" && CLAUDE_CODE_SESSION_ID=$2 bash "$BRIEF" --open docs/plans/p.md 1 2>/dev/null); st1=$?
  check "marker_failure_silent ($1): the normal run wrote its row" "$(wc -l < "$d/.dforge/sdd/usage-markers.tsv" 2>/dev/null | tr -d ' ')" "1"
  rm -rf "$d"; fixture "$d"
  mkdir -p "$d/.dforge/sdd/usage-markers.tsv"
  out2=$(cd "$d" && CLAUDE_CODE_SESSION_ID=$2 bash "$BRIEF" --open docs/plans/p.md 1 2>/dev/null); st2=$?
  check "marker_failure_silent ($1): same exit code" "$st2" "$st1"
  check "marker_failure_silent ($1): byte-identical stdout" "$out2" "$out1"
  check "marker_failure_silent ($1): the failing run wrote none" "$(find "$d/.dforge/sdd/usage-markers.tsv" -type f | wc -l | tr -d ' ')" "0"
}
transcript s1 120000 >/dev/null
run_pair transcript s1
run_pair "no transcript" s-none

# --- close_row_before_task_complete / task_complete_sweeps ---
# An auto run bound to s1, with an auto-run wrapper that copies the marker
# file at task-complete: the close row must already be there.
AR="$TMP/ar"
fixture "$AR"
printf '# Four\n\n### Task 1: one\n\nB.\n\n### Task 2: two\n\nB.\n\n### Task 3: three\n\nB.\n\n### Task 4: four\n\nB.\n' > "$AR/docs/plans/p4.md"
git -C "$AR" add docs && git -C "$AR" commit -q -m p4
KIT="$TMP/kit"; mkdir -p "$KIT"; cp -R "$P/scripts" "$P/.claude-plugin" "$KIT/"
mv "$KIT/scripts/auto-run" "$KIT/scripts/auto-run.real"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = task-complete ] && cp "$UM_FILE" "$UM_COPY" 2>/dev/null; done\nexec bash "$(dirname "$0")/auto-run.real" "$@"\n' > "$KIT/scripts/auto-run"
export UM_FILE="$AR/.dforge/sdd/usage-markers.tsv" UM_COPY="$TMP/at-task-complete.tsv"
mkdir -p "$HOME/.claude/dforge/sessions/cockpit"
date +%s > "$HOME/.claude/dforge/sessions/cockpit/s1"
transcript s1 120000 >/dev/null
ark() { (cd "$AR" && CLAUDE_CODE_SESSION_ID=s1 bash "$KIT/scripts/$@"); }
ark auto-run --session s1 start --spec docs/s.md --register docs/r.md >/dev/null 2>&1
ark auto-run --session s1 attach --plan docs/plans/p4.md >/dev/null 2>&1
ark task-brief --open docs/plans/p4.md 1 >/dev/null 2>&1
printf 'x\n' > "$AR/x.txt"; git -C "$AR" add x.txt; git -C "$AR" commit -q -m x
CP='done: x; verified: y; remaining: none; discovered: none; assumptions: none'
ark task-close docs/plans/p4.md 1 "$CP" >/dev/null 2>&1
LEDGER="$AR/.dforge/sdd/p4/progress.md"
RANGE=$(sed -n 's/^Task 1: complete (commits \([^,]*\),.*/\1/p' "$LEDGER")
close1() { awk -F'\t' '$2 == "close" && $7 == "1"' "$1" 2>/dev/null; }
check "close_row_before_task_complete: one close row" "$(close1 "$UM_FILE" | wc -l | tr -d ' ')" "1"
check "close_row_before_task_complete: range, deferred and caller" "$(close1 "$UM_FILE" | cut -f12-14)" \
  "$(printf 'task-close:1\t%s\t' "$RANGE")"
check "close_row_before_task_complete: the range is the complete line's" "$([[ $RANGE =~ ^[0-9a-f]+\.\.[0-9a-f]+$ ]] && echo yes)" "yes"
check "close_row_before_task_complete: context is measured" "$(close1 "$UM_FILE" | cut -f11)" "120000"
check "close_row_before_task_complete: written before task-complete" "$(close1 "$UM_COPY" | wc -l | tr -d ' ')" "1"
ark task-close docs/plans/p4.md 1 "$CP" >/dev/null 2>&1
check "close_row_before_task_complete: a second close writes nothing" "$(wc -l < "$UM_FILE" | tr -d ' ')" "2"

printf 'Task 2: complete (commits aaa1111..bbb2222, unreviewed) — x\nTask 3: complete (commits bbb2222..ccc3333, 1 parked) — x\nTask 4: complete (deferred by the auto run) — reason\n' >> "$LEDGER"
ark auto-run --session s1 task-complete >/dev/null 2>&1
closes() { awk -F'\t' -v t="$1" '$2 == "close" && $7 == t { print $12 "|" $13 "|" $14 }' "$UM_FILE"; }
check "task_complete_sweeps: task 2" "$(closes 2)" "auto-run:task-complete|aaa1111..bbb2222|"
check "task_complete_sweeps: task 3" "$(closes 3)" "auto-run:task-complete|bbb2222..ccc3333|"
check "task_complete_sweeps: a deferred task" "$(closes 4)" "auto-run:task-complete||1"
check "task_complete_sweeps: task 1 keeps its own row" "$(closes 1 | cut -d'|' -f1)" "task-close:1"
ark auto-run --session s1 task-complete >/dev/null 2>&1
check "task_complete_sweeps: a second sweep writes nothing" "$(awk -F'\t' '$2 == "close"' "$UM_FILE" | wc -l | tr -d ' ')" "4"
ark auto-run --session s1 stop >/dev/null 2>&1

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
