#!/usr/bin/env bash
# Usage markers in dagents: task-step start and task-brief write one open row
# per task into the primary checkout's usage-markers.tsv, auto-run
# task-complete closes every complete task, and a mark that cannot be written
# changes nothing its caller prints or returns.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$(cd "$HERE/../../plugins/dagents" && pwd)"

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
export MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1 DAGENTS_NO_SETTINGS=1
export GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
unset DAGENTS_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR \
  USAGE_MARK USAGE_MARK_PLAN USAGE_MARK_TASKS USAGE_MARK_CALLER USAGE_MARK_RANGE USAGE_MARK_DEFERRED
# review-route reads a gate; the stub keeps every case away from a real Codex.
export DAGENTS_CODEX_SESSION_DIR="$TMP/sessions"
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-gate usable=false reason=off review=false lane=false resets_at=- source=cache"' > "$TMP/gate-stub"
export TASK_STEP_CODEX_GATE="$TMP/gate-stub"

# fixture DIR — a repository with a four-task plan, committed at a fixed date.
fixture() {
  git init -q "$1"
  git -C "$1" config user.name Darkraise
  git -C "$1" config user.email dark@example.invalid
  mkdir -p "$1/docs/plans"
  {
    printf '# Fixture\n\n**Goal:** Fixture.\n\n**Execution:** subagent — `claude --model sonnet --effort high` — x\n\n'
    printf '## Global Constraints\n\n- None.\n\n## Contracts\n\n- None.\n'
    for t in 1 2 3 4; do
      printf '\n### Task %s: t%s\n\n**Implementer:** dagents:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0\n\nBody.\n' "$t" "$t"
    done
  } > "$1/docs/plans/p.md"
  git -C "$1" add docs
  git -C "$1" commit -q -m init
}

transcript() { # transcript SID TOKENS
  mkdir -p "$HOME/.claude/projects/fx"
  printf '{"type":"assistant","isSidechain":false,"message":{"model":"claude-opus-5-5","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":%s}}}\n' \
    "$2" > "$HOME/.claude/projects/fx/$1.jsonl"
}
opens() { awk -F'\t' '$2 == "open" { print $3 "|" $7 "|" $8 "|" $12 }' "$1" 2>/dev/null | sort; }

# --- task_step_start_opens_each ---
REPO="$TMP/repo"
fixture "$REPO"
transcript s1 120000; transcript s2 90000
M="$REPO/.dagents/sdd/usage-markers.tsv"
in_repo() { (cd "$REPO" && CLAUDE_CODE_SESSION_ID=$1 bash "$P/scripts/${@:2}") >/dev/null 2>&1; }
in_repo s1 task-step start docs/plans/p.md 2 3 --wave 1
check "task_step_start_opens_each: one open row per task" "$(opens "$M")" \
  "$(printf 'dagents|2|s1|task-step:2\ndagents|3|s1|task-step:3')"
in_repo s1 task-step start docs/plans/p.md 2 3 --wave 1
in_repo s1 task-brief docs/plans/p.md 2
check "task_step_start_opens_each: a repeat start and a brief write nothing" "$(wc -l < "$M" | tr -d ' ')" "2"
in_repo s2 task-brief docs/plans/p.md 4
check "task_step_start_opens_each: a brief alone opens its task" "$(opens "$M" | grep '|4|')" "dagents|4|s2|task-brief:4"
check "task_step_start_opens_each: the context is measured" "$(awk -F'\t' '$7 == "4" { print $11 }' "$M")" "90000"

# --- task_complete_closes_all ---
mkdir -p "$HOME/.claude/dagents/sessions/cockpit"
date +%s > "$HOME/.claude/dagents/sessions/cockpit/s1"
in_repo s1 auto-run --session s1 start --spec docs/s.md --register docs/r.md
in_repo s1 auto-run --session s1 attach --plan docs/plans/p.md
printf 'Task 2: complete (commits aaa1111..bbb2222, review clean) — x\nTask 3: complete (commits bbb2222..ccc3333, 1 parked) — x\n' \
  >> "$REPO/.dagents/sdd/p/progress.md"
in_repo s1 auto-run --session s1 task-complete
closes() { awk -F'\t' '$2 == "close" { print $7 "|" $12 "|" $13 "|" $14 }' "$M" | sort; }
check "task_complete_closes_all: a close row per complete task" "$(closes)" \
  "$(printf '2|auto-run:task-complete|aaa1111..bbb2222|\n3|auto-run:task-complete|bbb2222..ccc3333|')"
in_repo s1 auto-run --session s1 task-complete
check "task_complete_closes_all: a second call writes nothing" "$(closes | wc -l | tr -d ' ')" "2"
in_repo s1 auto-run --session s1 stop

# --- marker_failure_silent: task-step start ---
run_pair() { # run_pair LABEL SID
  local d="$TMP/pair" out1 out2 st1 st2
  rm -rf "$d"; fixture "$d"
  out1=$(cd "$d" && CLAUDE_CODE_SESSION_ID=$2 bash "$P/scripts/task-step" start docs/plans/p.md 1 2>/dev/null); st1=$?
  check "marker_failure_silent ($1): the normal run wrote its row" "$(wc -l < "$d/.dagents/sdd/usage-markers.tsv" 2>/dev/null | tr -d ' ')" "1"
  rm -rf "$d"; fixture "$d"
  mkdir -p "$d/.dagents/sdd/usage-markers.tsv"
  out2=$(cd "$d" && CLAUDE_CODE_SESSION_ID=$2 bash "$P/scripts/task-step" start docs/plans/p.md 1 2>/dev/null); st2=$?
  check "marker_failure_silent ($1): same exit code" "$st2" "$st1"
  check "marker_failure_silent ($1): byte-identical stdout" "$out2" "$out1"
  check "marker_failure_silent ($1): the failing run wrote none" "$(find "$d/.dagents/sdd/usage-markers.tsv" -type f | wc -l | tr -d ' ')" "0"
}
run_pair transcript s1
run_pair "no transcript" s-none

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
