#!/usr/bin/env bash
# The delegated task loop, the waves, the final review and finishing call the
# step and suite scripts instead of describing their mechanics. Each call is a
# whole instruction a session follows, so each is pinned by the text that
# carries it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
DT="$P/reference/delegated-task.md"
PW="$P/reference/parallel-waves.md"
FR="$P/reference/final-review.md"
FIN="$P/skills/finishing-a-development-branch/SKILL.md"
IP="$P/skills/subagent-driven-development/references/implementer-prompt.md"
SDD="$P/skills/subagent-driven-development/SKILL.md"
INLINE="$P/skills/executing-plans/SKILL.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" 2>/dev/null && echo yes || echo no)" "yes"
}
lacks() { # lacks <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" 2>/dev/null && echo yes || echo no)" "no"
}

# loop_steps - the delegated loop's text before its by-hand section
loop_steps() { sed '/^## The steps by hand/,$d' "$DT"; }

check "delegated-task.md has the by-hand section" "$(grep -c '^## The steps by hand' "$DT")" "1"

for call in 'task-step start PLAN_FILE N' 'task-step review PLAN_FILE N' 'task-step rereview PLAN_FILE N'; do
  check "the loop steps name $call" "$([ "$(loop_steps | grep -cF -- "$call")" -ge 1 ] && echo yes || echo no)" "yes"
done
for gone in 'scripts/review-package' 'scripts/task-brief PLAN_FILE N' 'Record BASE' 'run `scripts/lens-route'; do
  check "the loop steps no longer carry: $gone" "$(loop_steps | grep -cF -- "$gone")" "0"
done
check "only the cache rule runs date +%s in the loop steps" "$(loop_steps | grep -cF 'date +%s')" "1"
names "the fix message is a file of finding bullets" "$DT" '`<workspace>/task-<N>-fix-<R>.md`'
names "the fix message bullet format" "$DT" 'per open finding, `- <file>: <finding one-liner>`, then a blank line, then'
names "the skip rule needs --covered" "$DT" '`bash <plugin-root>/scripts/task-step rereview PLAN_FILE N` (with `--covered`'
names "a skipped re-review is recorded on the fix-round line" "$DT" 're-review skipped (<n> lines)'
names "the review step names the checks" "$DT" 'lines, each `clean` or the short SHA and what it found'
names "a repeated start keeps the recorded base" "$DT" 'keeps the recorded BASE'
names "the Codex seat line carries the fallback judge" "$DT" 'the judge after `fallback:` as the seat when it'
names "a failed route is read off the seat line" "$DT" '`(review-route exited <N>: …)`'
names "the gate line position is stated" "$DT" 'A `gate:` line right'

names "waves open a task with --wave" "$PW" '`bash <plugin-root>/scripts/task-step start PLAN_FILE N --wave <k>`'
names "waves review against the task ref" "$PW" '`--head <TASK_REF>` to'
names "waves pass the worktree to a Codex review" "$PW" '`--cwd <worktree>`, so that a Codex seat'
names "an overlap rebase passes --base" "$PW" '`task-step rereview PLAN_FILE N --head <TASK_REF> --base <that HEAD>`'
names "waves batch the in-hand cannot-verify items" "$PW" 'of every task whose review is in hand when one task reaches its cannot-verify'
names "the wave base check runs through suite-run" "$PW" '`bash <plugin-root>/scripts/suite-run -- bash -c '"'"'<the check>'"'"'`, in the'
check "the wave integration check runs through suite-run" "$(grep -cF 'scripts/suite-run -- bash -c' "$PW")" "2"
lacks "the wave check output file is gone" "$PW" 'wave-<k>-check.txt'

names "the final review runs suites through suite-run" "$FR" '`bash <plugin-root>/scripts/suite-run -- <command>`'
names "finishing runs the suite through suite-run" "$FIN" '`bash <plugin-root>/scripts/suite-run -- <test command>`, in the background'
names "finishing verifies the merged result through suite-run" "$FIN" 'bash <plugin-root>/scripts/suite-run -- <test command>'
names "implementers run the full suite through suite-run" "$IP" '`bash [PLUGIN_ROOT]/scripts/suite-run -- <the suite command>` and report'
lacks "implementers no longer run the full suite before committing" "$IP" 'full suite once before committing, not after every edit.'

names "the example workflow starts a task with task-step" "$SDD" '[task-step start PLAN_FILE 1:'
names "the example workflow reviews with task-step" "$SDD" '[task-step review PLAN_FILE 1:'
names "the example workflow re-reviews with task-step" "$SDD" '[task-step rereview PLAN_FILE 2:'
lacks "the example workflow no longer hand-runs review-package" "$SDD" 'review-package PLAN_FILE a1b2c3d HEAD'
names "the budget line is on every task-step digest" "$SDD" 'every `scripts/task-step`'
names "the rationalization row names the skip rule" "$SDD" 'Only `task-step rereview --covered` skips one'
lacks "the rationalization row no longer says every round is re-reviewed" "$SDD" 'Every round ends with a scoped re-review.'
names "inline mode hands delegated tasks to delegated-task.md" "$INLINE" '[delegated-task.md](../../reference/delegated-task.md) for this task instead'
check "inline mode restates no hand-run review mechanic" "$(grep -cE 'date \+%s|codex-gate|lens-route' "$INLINE")" "0"

# --- the group reviewer template ---
GRP="$P/skills/subagent-driven-development/references/group-reviewer-prompt.md"
check "the group reviewer template exists" "$([ -f "$GRP" ] && echo yes || echo no)" "yes"
for ph in '[GROUP_LIST]' '[PACKAGE_FILE]' '[REPORT_FILE]' '[PLUGIN_ROOT]'; do
  names "the group template carries $ph" "$GRP" "$ph"
done
names "the group template is a fenced prompt task-step can fill" "$GRP" '  prompt: |'
names "the group package holds one section per task" "$GRP" 'one section per task, headed `## Task <N>`'
names "the group reviewer scores each task on its own" "$GRP" 'Score each task on its own'
names "the group report holds one block per task" "$GRP" 'one block per task, headed `### Task <N>`'
names "a group finding names its task" "$GRP" 'prefix its file with `(Task <N>) `'
names "a finding in one task never fails another" "$GRP" 'A finding in one task never fails another task'
names "the group reviewer reads a section's lens files" "$GRP" 'a `**Lenses:**` line'
lacks "the group template takes no single diff placeholder" "$GRP" '[DIFF_FILE]'
check "the group prompt holds no placeholder task-step does not fill" \
  "$(awk '/^  prompt: \|/ { on = 1; next } on && /^```/ { exit } on' "$GRP" 2>/dev/null | grep -oE '\[[A-Z][A-Z_]*\]' | sort -u | grep -cvxE '\[(GROUP_LIST|PACKAGE_FILE|REPORT_FILE|PLUGIN_ROOT)\]')" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
