#!/usr/bin/env bash
# A5 and A7: dagents keeps 4.17.1's feature set without version 5's, and a
# full cycle neither touches nor reads dforge's names.
set -uo pipefail
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION DAGENTS_BUDGET CLAUDE_PROJECT_DIR
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../plugins/dagents" && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); else printf 'FAIL - %s\n       got:  [%s]\n       want: [%s]\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi; }

# --- A5: the feature set ---
# CI's shallow checkout carries no tags; the comparison needs a full clone.
if git -C "$REPO" rev-parse -q --verify 'dforge-v4.17.1^{tree}' >/dev/null 2>&1; then
  want=$(git -C "$REPO" ls-tree --name-only dforge-v4.17.1:plugins/dforge/agents | sed 's/dforge/dagents/g' | sort | tr '\n' ' ')
  check "agent set equals the tag's" "$(ls "$ROOT/agents" | sort | tr '\n' ' ')" "$want"
else
  printf 'skip - agent set equals the tag'"'"'s: tag dforge-v4.17.1 is not in this clone\n'
fi
for skill in subagent-driven-development revising-plans; do
  check "skill $skill present" "$( [ -f "$ROOT/skills/$skill/SKILL.md" ] && echo yes)" "yes"
done
# task-step reads the Executor line through lib/plan.sh's plan_executors, as at
# the tag, whose awk spells it as the regex \*\*Executor:\*\*.
check "Executor-line routing present" "$(grep -lE '\\?\*\\?\*Executor:\\?\*\\?\*' "$ROOT/scripts/plan-lint" "$ROOT/scripts/lib/plan.sh" 2>/dev/null | wc -l | tr -d ' ')" "2"
for absent in scripts/run-review-panel scripts/task-close scripts/run-api-judge scripts/lib/session-state.sh; do
  check "no version-5 $absent" "$( [ -e "$ROOT/$absent" ] && echo present || echo absent)" "absent"
done

# --- A7: a full cycle in a temporary project and home ---
cycle() { # cycle LABEL — run the cycle; print a listing of dforge-named paths and the output
  local T; T="$(mktemp -d)"
  export HOME="$T/home"; mkdir -p "$HOME"
  export WORKFLOW_GUARD_CLAUDE_DIR="$T/c" WORKFLOW_GUARD_MANAGED_DIR="$T/c" WORKFLOW_GUARD_PROJECT_DIR="$T/p"
  git init -q -b main "$T/p"; git -C "$T/p" commit -q --allow-empty -m init
  if [ "$1" = seeded ]; then
    mkdir -p "$HOME/.dforge" "$T/p/.dforge/sdd/p"
    printf '{"autoRun":"off","handoffBudget":1,"darkmem":{"url":"http://127.0.0.1:9","projects":{"%s":"projP"}}}' "$T/p" > "$HOME/.dforge/config.json"
    echo 'Task 1: complete (abc)' > "$T/p/.dforge/sdd/p/progress.md"
    export DFORGE_BUDGET=1 DR_CODEX_SESSION_DIR="$T/elsewhere"
  fi
  sleep 1
  mkdir -p "$T/p/docs/dagents/plans"
  printf '# P\n\n**Execution:** inline — `claude --model sonnet --effort low` — x\n\n### Task 1: one\n\n**Implementer:** dagents:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0\n' > "$T/p/docs/dagents/plans/p.md"
  local ev='{"session_id":"s","source":"startup","hook_event_name":"SessionStart","cwd":"'"$T/p"'"}'
  local out
  out=$( cd "$T/p" && printf '%s' "$ev" | bash "$ROOT/scripts/session-start.sh" 2>&1 | sed 's/\\n\\ndagents: dforge 4\.x layout found[^"\\]*//'
         bash "$ROOT/scripts/task-brief" docs/dagents/plans/p.md 1 2>&1
         bash "$ROOT/scripts/next-step" docs/dagents/plans/p.md 2>&1
         printf '%s' "$ev" | bash "$ROOT/scripts/turn-end.sh" 2>&1
         # The readers of the two seeded variables' dagents names.
         bash "$ROOT/scripts/context-size" 2>&1 | tail -n 1
         bash -c '. "$1/scripts/lib/executor-session.sh" && executor_session_dir codex' _ "$ROOT" 2>&1; echo )
  unset DFORGE_BUDGET DR_CODEX_SESSION_DIR
  # Git Bash prints T both as /tmp/... and in its C:/... form.
  local TN=$T
  if command -v cygpath >/dev/null 2>&1; then TN=$(cygpath -m "$T"); fi
  printf '%s\n' "$out" | sed "s#$TN#T#g; s#$T#T#g"
  find "$T" -name '*dforge*' -newer "$T/p/docs/dagents/plans/p.md" | sed "s#$TN#T#g; s#$T#T#g"
  rm -rf "$T"
}
plain=$(cycle plain)
check "no dforge-named path is created" "$(printf '%s' "$plain" | grep -c '^T/.*dforge')" "0"
seeded=$(cycle seeded)
check "seeded dforge state and variables change nothing" "$seeded" "$plain"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
