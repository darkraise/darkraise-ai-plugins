#!/usr/bin/env bash
# A skill-enforced setting is only as good as the skill text that names it:
# each key must be named where its decision is made, and no skill may still
# state the finish menu's wait as a fixed number.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
command -v node > /dev/null 2>&1 || { echo "settings-skills tests: node is required but not on PATH" >&2; exit 2; }

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" && echo yes || echo no)" "yes"
}

B="$P/skills/brainstorming/SKILL.md"
W="$P/skills/writing-plans/SKILL.md"
G="$P/skills/using-git-worktrees/SKILL.md"
F="$P/reference/finish-preference.md"

# Each check is a whole instruction, not a keyword: where the settings come
# from, what outranks them, and what each value changes at its decision point.
names "brainstorming has a Settings section" "$B" '## Settings'
names "brainstorming loads the settings when no line is in context" "$B" '`scripts/dforge-config workflow` once before your first question'
names "brainstorming: instructions outrank a setting, and the gate stays" "$B" 'setting, and no setting removes the approval gate.'
names "brainstorming: processBias" "$B" 'plainly holds; doubt resolves to bounded.'
names "brainstorming: questionStyle" "$B" '`questionStyle=batched`: ask all the clarifying questions in one message'
names "brainstorming: designApproval" "$B" '`designApproval=whole`: present every design section in one message and ask'
names "brainstorming: executionStrategy" "$B" 'the execution-strategy question; record the value as the answer.'
names "brainstorming: an inline plan is sequential" "$B" 'and when `executionMode=inline`, which makes the plan sequential.'
names "brainstorming: specReview" "$B" '`specReview=false`: after the spec self-review block, skip the User Review'
names "brainstorming: the path rule points at processBias" "$B" '(`processBias` moves where doubt lands; see Settings). The'
names "brainstorming: the question rule points at questionStyle" "$B" '(`questionStyle=batched` asks them all in one message; see Settings)'
names "brainstorming: the strategy question is skipped by the setting" "$P/skills/brainstorming/references/design-phase.md" 'When `executionStrategy` is `sequential` or `parallel` (see Settings), skip the'
names "brainstorming: the section rule points at designApproval" "$P/skills/brainstorming/references/design-phase.md" 'with `designApproval=whole`, present every section in one message and ask once (see Settings)'
names "brainstorming: the review gate is skipped by the setting" "$P/skills/brainstorming/references/user-review-gate.md" 'With `specReview=false` (see Settings), skip this gate and go to Implementation.'
names "writing-plans loads the settings when no line is in context" "$P/skills/writing-plans/references/execution-line.md" 'run `scripts/dforge-config workflow` before you choose the Execution line'
names "writing-plans: instructions outrank a setting" "$P/skills/writing-plans/references/execution-line.md" 'own instructions outrank a setting.'
names "writing-plans: executionMode fixes the line" "$P/skills/writing-plans/references/execution-line.md" 'line when it is `inline` or `subagent`, in place of the majority rule.'
names "writing-plans: an inline plan is sequential" "$P/skills/writing-plans/references/execution-line.md" '`**Parallelism:** sequential — executionMode is inline`'
names "writing-plans: executionStrategy answers the question" "$W" 'that value and do not ask. On a Codex host do not ask:'
names "using-git-worktrees checks only the chosen directory" "$G" 'git check-ignore -q "$LOCATION/"'
names "using-git-worktrees picks pnpm from its lockfile" "$G" 'if [ -f pnpm-lock.yaml ]; then pnpm install'
names "using-git-worktrees loads the settings when no line is in context" "$G" 'run `scripts/dforge-config workflow` when no such line is in context'
names "using-git-worktrees: what each value does" "$G" '`worktree=always` creates the worktree without asking, `worktree=never` works in place and skips to Step 2'
names "using-git-worktrees: the setting decides only when no preference was stated" "$G" 'If not, the `worktree` setting decides'
names "finish-preference: finishAction" "$F" 'finishAction'
names "finish-preference: the question offers Ask me then" "$F" '4. Ask me then: show the finish menu and wait for my answer'
FIN="$P/skills/finishing-a-development-branch/SKILL.md"
names "finishing: a recorded choice runs with no menu" "$FIN" '**A choice recorded before the run.**'
names "finishing: an answered record is never re-run" "$FIN" 'A record whose `answer` field is set has been used'
names "finishing: a null base is found without asking" "$FIN" 'upstream, as Step 3 does, without asking or confirming'
names "finishing: an upstream base must be another local branch" "$FIN" 'a local branch other than this one'
names "finishing: Step 3 qualifies an upstream base as Step 4 does" "$FIN" 'An upstream names the base only as Step 4 qualifies it'
names "finishing: a remote prefix is dropped only for a configured remote" "$FIN" 'when no local branch has the whole name and its first segment is a configured remote'
names "finishing: a fired legacy record is consumed" "$FIN" 'with no `answer` or `firedAt` field'
names "finish-preference: a fired legacy record is consumed" "$F" 'with no `answer` or `firedAt` field'
names "finishing: Step 3 asks nothing for a recorded choice" "$FIN" 'never ask here: Step 4 says where its base comes from'
names "finish-preference: a setting's choice has no base branch" "$F" '`base` is null'

# The auto run (reference/auto-run.md) where each skill would otherwise ask.
names "brainstorming: autoRun" "$B" '`autoRun=off`: never offer an auto run'
names "brainstorming offers the auto run" "$P/skills/brainstorming/references/auto-run-offer.md" 'Run the rest unattended?'
names "brainstorming: the review gate gives way to the Fable review" "$P/skills/brainstorming/references/user-review-gate.md" 'In an auto run (`scripts/auto-run status` exits 0), skip this gate'
names "writing-plans: an auto run asks nothing" "$P/skills/writing-plans/references/auto-run-plan.md" 'nothing in this skill waits on your human partner'
names "writing-plans: planning choices go to Opus first" "$P/skills/writing-plans/references/auto-run-plan.md" '`dforge:judge-opus` first, then the ladder'
names "writing-plans: the plan step switches in place" "$P/skills/writing-plans/references/auto-run-plan.md" '`scripts/auto-run switch` and end the turn with `Auto run: switching`'
names "using-git-worktrees: an auto run creates the worktree" "$G" 'In an auto run (`scripts/auto-run status` exits 0), create the worktree without asking'
names "handoff: the caller owns the clear" "$P/skills/handoff/SKILL.md" 'never runs `scripts/auto-run clear` itself'
names "resume-execution: an auto run stops before asking" "$P/skills/resume-execution/SKILL.md" 'scripts/auto-run stop --reason'
names "finishing: an auto run shows no menu" "$P/skills/finishing-a-development-branch/SKILL.md" '**Step 4 shows no menu.**'
names "finishing: the run's base" "$P/skills/finishing-a-development-branch/SKILL.md" 'the base `scripts/auto-run status` names'
names "finishing: a detached HEAD never merges in an auto run" "$P/skills/finishing-a-development-branch/SKILL.md" 'there is no merge, so `merge` keeps'
names "finishing: failing tests at Step 1 stop the run" "$P/skills/finishing-a-development-branch/SKILL.md" '(failing tests at Step 1, a merged'
H="$P/skills/handoff/SKILL.md"
names "handoff: a design phase writes the Draft line" "$H" '- Draft: `<spec path>`'
names "handoff: pushes once latest.md is written" "$H" 'run `scripts/darkmem-sync push` and promote'
# The README describes the shipped defaults: executionStrategy=parallel, and an
# auto run (autoRun=on) that dispatches judge-fable.
names "README: parallel waves are the default" "$P/README.md" 'The `executionStrategy` setting defaults to'
check "README: sequential is not called the default" "$(grep -cF 'sequentially (the default)' "$P/README.md")" "0"
names "README: an auto run dispatches judge-fable" "$P/README.md" 'An auto run is the exception: it dispatches `judge-fable`'
CT="$P/skills/using-dforge/references/codex-tools.md"
names "codex-tools: routed dispatch never relies on a full-history fork" "$CT" 'Never assume a full-history fork accepts `model` and'
check "codex-tools: no unconditional fork override claim" "$(grep -cF 'Full-history forks accept `model`' "$CT")" "0"
names "codex-tools: session start reconciles, then pulls" "$CT" 'bash <plugin-root>/scripts/darkmem-sync reconcile`, then'
names "codex-tools: nothing pushes at the end of a turn" "$CT" 'nothing pushes for you at the end of a turn'

# Every skill-enforced key in the schema is named by at least one skill, as
# `key` or key=value: a bare word such as "worktree" is not a naming.
keys=$(node -e 'const { pathToFileURL } = require("url"); import(pathToFileURL(process.argv[1]).href).then(m => console.log(Object.entries(m.default).filter(([, spec]) => spec.enforcedBy === "skill").map(([key]) => key).join(" ")))' "$P/config/schema.mjs")
check "the schema has skill-enforced keys" "$([ -n "$keys" ] && echo yes || echo no)" "yes"
for key in $keys; do
  check "a skill names $key" "$(grep -lE -- "\`$key\`|$key=" "$P"/skills/*/SKILL.md | head -n 1 | grep -c .)" "1"
done

# The finish menu has no timer: no skill, reference or README names its machinery.
# Each file is read as one line, so a phrase wrapped across lines still counts.
for file in "$P"/skills/*/SKILL.md "$P"/skills/*/references/*.md "$P"/reference/*.md "$P/README.md"; do
  check "${file#"$P"/} names no finish timer" "$(tr '\n' ' ' < "$file" | tr -s ' ' | grep -cE 'finish-choice (arm|due|job)|finishTimeout|configured wait|CronCreate|CronDelete|no wake')" "0"
done

# The README describes the contract-and-test plan shape, review groups, the
# two-round fix loop, the wave check cadence and the judge report files.
names "README: tasks carry tests, not implementation code" "$P/README.md" 'carries its interfaces and the complete code of its tests'
names "README: low-risk tasks are reviewed in groups" "$P/README.md" 'reviewed in groups'
names "README: two fix rounds" "$P/README.md" 'at most two fix rounds'
names "README: the full check runs every third wave" "$P/README.md" 'every third wave'
names "README: judges write their report to a file" "$P/README.md" 'writes its full report to a file'
check "README: no five-round loop" "$(grep -cE 'fix rounds 4|rounds 1 to 3|and 5, at the BLOCKED' "$P/README.md")" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
