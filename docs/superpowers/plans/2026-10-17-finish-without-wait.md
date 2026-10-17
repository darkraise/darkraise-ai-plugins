# Finish Without Wait Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a finish choice was recorded before a dforge run, finishing carries it out as soon as the final review is clean, with no menu and no timer; the 30-minute timer machinery is removed.

**Architecture:** `scripts/finish-choice` loses `arm`, `job` and `due`; the `finishTimeout` setting goes; the Stop hook recognises the reworded start-of-run question; the cockpit's finish chip loses its countdown; and the finishing skill, the finish-preference reference and the docs that describe the wait state the new rule.

**Tech Stack:** Bash scripts with shell test suites, a Node.js ESM settings schema, the TypeScript cockpit mod (tested by `claude plugin test`), Markdown skills and docs.

**Spec:** `docs/superpowers/specs/2026-10-17-finish-without-wait-design.md`

**Execution:** inline — `claude --model sonnet --effort high` — 1 of 6 tasks is heavy (Task 1, total 5) and is delegated; the highest self-implemented total is 4 (`impl-sonnet-medium`, effort medium), raised to high because a task is delegated

**Plan review:** 2026-10-17 — dr-superpowers:judge-opus — executability 15 / coherence 17 / coverage 14 / assumptions 16 (round 1)

**Parallelism:** sequential — the spec's Execution strategy is sequential: the script and file format first, then the settings, the Stop hook and the cockpit that read them, then the skills and docs that describe them

## Global Constraints

- Work in a worktree branched from local `main` (local `main` runs ahead of `origin/main`): `git worktree add .claude/worktrees/finish-without-wait -b finish-without-wait main`. This plan, its spec and its register must be on local `main` first: before Task 1, `ls docs/superpowers/plans/2026-10-17-finish-without-wait.md` in the worktree must list the file, or stop. Do not push.
- Never edit anything under `docs/superpowers/`: it is history (the register row is set by the execution skill's own scripts, not by hand).
- Run each command on its own line; do not chain commands that mention git with `&&`, `;` or a pipe (the worktree guard refuses them).
- Run suites from the worktree root under a bound, with the host's `CLAUDE_CONFIG_DIR` removed: `env -u CLAUDE_CONFIG_DIR timeout 300 <command>`, except the whole suite, which takes CI's bound: `env -u CLAUDE_CONFIG_DIR timeout --kill-after=10s 690s node scripts/test-all.mjs`. In this host's Bash `claude` is a shell function that exits 127: call `/root/.local/bin/claude`.
- Commits: `<type>(<scope>): <subject>`, subject at most 50 characters, imperative, no period; author and committer `Darkraise <quangtc94@gmail.com>` (the repository's `user.name`/`user.email`); no `Co-Authored-By:`, `Claude-Session:` or "Generated with" line, nor any other AI attribution.
- No version bump in any manifest: a release is a separate commit the owner asks for.
- An Edit step's old text that is not found exactly is a stop: report BLOCKED with the file and the text. Never paraphrase an edit.
- Stop every process a check starts; nothing in this plan starts a long-lived one.

## Contracts

- **C1 `scripts/finish-choice`.** Commands: `set ACTION [--base BRANCH]` (ACTION `merge|pr|keep|wait`, exit 2 otherwise), `get` (prints `finish.json`; exit 3 when nothing is chosen; with nothing chosen and the `finishAction` setting not `ask`, records `{action, base: null, chosenAt, source: "setting"}` first), `answer ACTION` (writes `answer` and `answeredAt`, prints nothing), `clear`. Every other command, including `arm`, `job` and `due`, exits 2 with the usage. All take `--plan PLAN_FILE`. `finish.json` holds `action`, `base`, `chosenAt`, optional `source`, and after `answer` the fields `answer` and `answeredAt`; older files may also hold `armedAt`, `dueAt`, `job`, `firedAt`, which nothing reads. `FINISH_CHOICE_NOW` (epoch seconds) stands in for the clock.
- **C2 The start-of-run question.** Exactly this block, `<base-branch>` filled in:

  ```
  Before I start: when the implementation is done and its final review is
  clean, what should I do?

  1. Merge back to <base-branch> locally
  2. Push and create a Pull Request
  3. Keep the branch as-is
  4. Ask me then: show the finish menu and wait for my answer

  Which option?
  ```

  From a detached HEAD the options are `1. Push as new branch and create a Pull Request`, `2. Keep as-is`, `3. Ask me then: show the finish menu and wait for my answer`. The Stop hook's pass marker for it is the text `Ask me then: show the finish menu`.
- **C3 Cockpit finish.** `CockpitFinish = { action: 'merge' | 'pr' | 'keep' | 'wait'; base: string | null; answer: string | null }`. `finishLine(finish: CockpitFinish): Run[]` (no time parameter) renders, as joined text, `Finish <label> when done` while `answer` is null, where `<label>` is `merge into <base or "the base branch">`, `push and open a PR`, `keep the branch`, or `ask me` for `wait`; and `[]` once `answer` is set. `isFinishArmed` no longer exists.
- **C4 `finishAction` setting.** Values `ask | merge | pr | keep | wait`, default `ask`, label `When done`, title `When the work is done`, description `ask asks before the first task. merge, pr or keep skips the question and runs that action as soon as the final review is clean; wait skips it and shows the finish menu then.` The `finishTimeout` key no longer exists.

## Assumptions (evidence)

- **A retired key in the settings file is harmless.** On 2026-10-17, with `{"finishAction":"merge","notAKey":45}` as `~/.dforge/config.json` under a scratch HOME, `bash plugins/dforge/scripts/dforge-config get --json` exited 0 without `notAKey`, `get finishAction` printed `merge`, and `get notAKey` exited 2 with `dforge-config: unknown setting notAKey`. The cockpit validates only schema keys (`plugins/dforge/hooks/cockpit/config.ts:111`).
- **The cockpit settings tab renders from the schema.** `grep -n finishTimeout plugins/dforge/hooks/cockpit/settings-view.tsx plugins/dforge/hooks/cockpit/config.ts` printed nothing on 2026-10-17, so removing the key removes the "Menu waits" control.
- **An immediate finish ends a turn cleanly.** The Stop hook already accepts `## Next session` for a ledger whose final review is clean (`plugins/dforge/scripts/turn-end.sh:143`), and finishing Step 7 ends on that block.
- **The finish timer's references are all listed.** On 2026-10-17, `grep -rln "finish-choice\|finishTimeout\|If it gets none within\|finish-preference\|dueAt\|firedAt"` over `plugins/` named exactly the files this plan modifies plus `tests/dforge-state.test.sh` and `reference/auto-run.md`; the former uses only `finish-choice set`, which is unchanged.
- **A6's redraw half is checked structurally.** The cockpit test harness shows a redraw only through a row whose text changes with the clock (`tests/cockpit.test.ts:1769-1771`, a background shell's age), and a recorded finish choice with nothing live draws no such row, so no test can observe an idle ticker. Task 4 removes the only finish term from `syncTicker` and greps that `isFinishArmed`, `dueAt` and `firedAt` are gone; its tests assert that no `⏱` countdown is drawn on either surface.
- **A10 and A11 are demos.** They run in the execution skill's acceptance QA at the end of the run, not in a task.
- **`turn-end.sh:126-131` needs no change.** That comment names the finish-preference question and no wait (read 2026-10-17).
- **Codex is off for this plan.** `codex-gate` printed `usable=false reason=quota lane=false resets_at=2026-10-22T11:13:09Z source=probe` on 2026-10-17, so no task carries an `**Executor:**` line.

## Task index

1. Drop the timer from finish-choice
2. Retire the finishTimeout setting
3. Recognise the new question in the Stop hook
4. Drop the countdown from the cockpit
5. Rewrite finishing and its reference
6. Update the docs that describe the wait

---

### Task 1: Drop the timer from finish-choice

**Files:**
- Modify: `plugins/dforge/scripts/finish-choice` (whole file)
- Test: `plugins/dforge/tests/finish-choice.test.sh` (whole file)

**Interfaces:**
- Consumes: none
- Produces: C1

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Write the failing test**

Replace the whole of `plugins/dforge/tests/finish-choice.test.sh` with:

```bash
#!/usr/bin/env bash
# finish-choice keeps the finish action chosen before execution; finishing
# carries it out at once and records that it did, so it is never re-run.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/finish-choice"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# finish-choice reads ~/.dforge/config.json; a temporary home keeps the real one out.
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 TZ=UTC
git init -q "$TMP/repo"
cd "$TMP/repo"
mkdir -p docs/plans && printf '# Plan\n' > docs/plans/p.md
fc() { bash "$SCRIPT" "$@"; }
T0=1760000000

# --- a plan run ---
FINISH_CHOICE_NOW=$T0 fc set pr --base main --plan docs/plans/p.md >/dev/null
file=".dforge/sdd/p/finish.json"
check "set: beside the plan's ledger" "$(jq -r '[.action, .base, .chosenAt] | join(" ")' "$file")" "pr main $T0"
check "set: git-ignored" "$(git status --porcelain --untracked-files=all | grep -c dforge)" "0"
fc set later --plan docs/plans/p.md >/dev/null 2>&1
check "set: refuses an unknown action" "$?" "2"
check "get: prints the choice" "$(fc get --plan docs/plans/p.md | jq -r '[.action, .base] | join(" ")')" "pr main"

# --- finishing acts on it ---
check "answer: prints nothing" "$(FINISH_CHOICE_NOW=$((T0 + 60)) fc answer pr --plan docs/plans/p.md)" ""
check "answer: recorded" "$(jq -r '[.answer, .answeredAt] | join(" ")' "$file")" "pr $((T0 + 60))"
check "answer: get shows it" "$(fc get --plan docs/plans/p.md | jq -r .answer)" "pr"

# --- the timer is gone ---
for cmd in arm "job cron-7" due; do
  fc $cmd --plan docs/plans/p.md >/dev/null 2>&1
  check "$cmd: no longer a command" "$?" "2"
done

# --- a file an older version armed still reads ---
mkdir -p .dforge/sdd/old && printf '# Plan\n' > docs/plans/old.md
printf '{"action":"merge","base":"main","chosenAt":%d,"armedAt":%d,"dueAt":%d,"job":"cron-8","firedAt":%d}\n' \
  "$T0" "$T0" "$((T0 + 1800))" "$((T0 + 1800))" > .dforge/sdd/old/finish.json
out=$(fc get --plan docs/plans/old.md)
check "old file: get exits 0" "$?" "0"
check "old file: the action and base read" "$(jq -r '[.action, .base] | join(" ")' <<<"$out")" "merge main"

# --- wait, and work without a plan ---
fc set wait >/dev/null
check "no plan: under .dforge/sdd" "$(jq -r .action .dforge/sdd/finish.json)" "wait"
fc clear
fc get >/dev/null 2>&1
check "clear: nothing chosen" "$?" "3"

# --- the finishAction setting ---
mkdir -p "$HOME/.dforge" docs/plans
for name in s r w; do printf '# Plan\n' > "docs/plans/$name.md"; done
fc get --plan docs/plans/s.md >/dev/null 2>&1
check "setting ask: nothing chosen still exits 3" "$?" "3"
printf '{"finishAction":"merge"}\n' > "$HOME/.dforge/config.json"
out=$(FINISH_CHOICE_NOW=$T0 fc get --plan docs/plans/s.md)
check "setting: get exits 0" "$?" "0"
check "setting: get records the configured action" \
  "$(jq -r '[.action, (.base | tostring), .source, (.chosenAt | tostring)] | join(" ")' .dforge/sdd/s/finish.json)" "merge null setting $T0"
has "setting: get prints the choice" "$out" '"action": "merge"'
fc set keep --plan docs/plans/r.md >/dev/null
check "a recorded choice wins over the setting" "$(fc get --plan docs/plans/r.md | jq -r '[.action, (.source // "asked")] | join(" ")')" "keep asked"
printf '{"finishAction":"wait"}\n' > "$HOME/.dforge/config.json"
check "setting wait: recorded" "$(fc get --plan docs/plans/w.md | jq -r .action)" "wait"
rm -f "$HOME/.dforge/config.json"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/finish-choice.test.sh`
Expected: FAIL on exactly `arm: no longer a command` (got `3`: the choice is already answered), `job cron-7: no longer a command` (got `0`) and `due: no longer a command` (got `3`); the run ends `N passed, 3 failed`.

- [ ] **Step 3: Write the implementation**

Replace the whole of `plugins/dforge/scripts/finish-choice` with (keep the file executable):

```bash
#!/usr/bin/env bash
# The finish action your human partner chose before execution started: what
# dforge:finishing-a-development-branch carries out, with no menu, as soon as
# the final review is clean (`wait` asks for the menu instead). The choice is
# asked once, before the first task, so a finished run never stops to ask.
#
# One JSON file holds it: `<workspace>/finish.json` beside a plan's ledger, or
# `.dforge/sdd/finish.json` for work done without a plan. Both are
# git-ignored; the cockpit Run card reads the file to show the choice.
#
# Usage: finish-choice <command> [--plan PLAN_FILE] [args]
#   set ACTION [--base BRANCH]  record the choice: merge | pr | keep | wait
#   get                         print the file; exit 3 when nothing is chosen.
#                               With nothing chosen and the finishAction setting
#                               at anything but ask, record that action first.
#   answer ACTION               record that finishing acted on the choice, or
#                               that the menu was answered (merge | pr | keep |
#                               discard); an answered choice is never re-run
#   clear                       forget the choice
#
# FINISH_CHOICE_NOW (epoch seconds) stands in for the clock in tests.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/dforge-dir.sh"
. "$HERE/lib/dforge-env.sh"

usage() { sed -n '/^# Usage:/,/^# FINISH_CHOICE_NOW/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "finish-choice needs jq" >&2; exit 2; }
[ $# -ge 1 ] || usage
cmd=$1; shift

plan=""
args=()
while [ $# -gt 0 ]; do
  case $1 in
    --plan) [ $# -ge 2 ] || usage; plan=$2; shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
set -- "${args[@]+"${args[@]}"}"

if [ -n "$plan" ]; then
  dir=$(bash "$HERE/sdd-workspace" "$plan")
else
  root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not inside a git repository" >&2; exit 2; }
  dir="$(dforge_dir state "$root")/sdd"
  mkdir -p "$dir"
  printf '*\n' > "$dir/.gitignore"
fi
file="$dir/finish.json"
now=${FINISH_CHOICE_NOW:-$(date +%s)}

valid_action() {
  case $1 in merge|pr|keep|wait) return 0 ;; *) return 1 ;; esac
}
write() { # write <jq filter> [jq args...]: rewrite the file through the filter
  local filter=$1; shift
  local current='{}'
  [ -s "$file" ] && current=$(cat "$file")
  jq "$@" "$filter" <<<"$current" > "$file.tmp" && mv "$file.tmp" "$file"
}
need_file() { [ -s "$file" ] || { echo "no finish action chosen" >&2; exit 3; }; }
# With nothing chosen, the finishAction setting stands in for the answer
# (anything but ask). It is recorded like an answer, so the run keeps one
# choice even if the setting changes while it runs; the base branch is left
# for finishing to determine.
from_setting() {
  [ ! -s "$file" ] || return 0
  local action
  action=$(dforge_setting finishAction ask)
  valid_action "$action" || return 0
  jq -n --arg action "$action" --argjson now "$now" \
    '{action: $action, base: null, chosenAt: $now, source: "setting"}' > "$file"
}

case $cmd in
  set)
    [ $# -ge 1 ] && valid_action "$1" || { echo "set takes one of: merge pr keep wait" >&2; exit 2; }
    action=$1; shift
    base=""
    if [ $# -ge 2 ] && [ "$1" = "--base" ]; then base=$2; shift 2; fi
    [ $# -eq 0 ] || usage
    jq -n --arg action "$action" --arg base "$base" --argjson now "$now" \
      '{action: $action, base: (if $base == "" then null else $base end), chosenAt: $now}' > "$file"
    cat "$file"
    ;;
  get)
    from_setting
    need_file
    cat "$file"
    ;;
  answer)
    [ $# -eq 1 ] || usage
    need_file
    write '.answer = $answer | .answeredAt = $now' --arg answer "$1" --argjson now "$now"
    ;;
  clear)
    rm -f "$file"
    ;;
  *) usage ;;
esac
```

- [ ] **Step 4: Run test to verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/finish-choice.test.sh`
Expected: PASS, ending `N passed, 0 failed`.
Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/dforge-state.test.sh`
Expected: PASS, ending with 0 failed (it uses only `finish-choice set`).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/finish-choice plugins/dforge/tests/finish-choice.test.sh
git commit -m "feat(dforge): drop the finish-choice timer"
```

### Task 2: Retire the finishTimeout setting

**Files:**
- Modify: `plugins/dforge/config/schema.mjs:125-134`
- Test: `plugins/dforge/tests/dforge-config.test.sh`

**Interfaces:**
- Consumes: none
- Produces: C4

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

In `plugins/dforge/tests/dforge-config.test.sh`, make these exact replacements with the Edit tool.

Replace:

```
check "workflow keys: defaults" "$(fc get --json | node -e 'const v = JSON.parse(require("fs").readFileSync(0, "utf8")); console.log([v.handoffMode, v.codexLane, v.codexReview, v.executionStrategy, v.executionMode, v.worktree, v.processBias, v.designApproval, v.specReview, v.questionStyle, v.finishAction, v.finishTimeout].join(" "))')" \
  "strict true true ask auto ask standard sections true single ask 30"
```

with:

```
check "workflow keys: defaults" "$(fc get --json | node -e 'const v = JSON.parse(require("fs").readFileSync(0, "utf8")); console.log([v.handoffMode, v.codexLane, v.codexReview, v.executionStrategy, v.executionMode, v.worktree, v.processBias, v.designApproval, v.specReview, v.questionStyle, v.finishAction].join(" "))')" \
  "strict true true ask auto ask standard sections true single ask"
```

Replace:

```
finishAction ask merge discard
finishTimeout 30 45 3
```

with:

```
finishAction ask merge discard
```

Replace:

```
fc set finishTimeout 5.5; check "a fraction: exit 2" "$?" "2"
```

with:

```
fc set notifyAfter 5.5; check "a fraction: exit 2" "$?" "2"
# finishTimeout is retired: a value left in the file is ignored, and naming it is an error.
fresh retired
mkdir -p "$HOME/.dforge"
printf '{"finishAction":"merge","finishTimeout":45}\n' > "$FILE"
check "retired finishTimeout: get --json reads the rest" "$(fc get --json | node -e 'const v = JSON.parse(require("fs").readFileSync(0, "utf8")); console.log(v.finishAction + " " + ("finishTimeout" in v))')" "merge false"
fc get finishTimeout > /dev/null 2>&1; check "retired finishTimeout: get exits 2" "$?" "2"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: FAIL on `retired finishTimeout: get --json reads the rest` (got `merge true`) and `retired finishTimeout: get exits 2` (got `0`).

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/config/schema.mjs`, replace:

```js
  finishAction: {
    type: 'enum', values: ['ask', 'merge', 'pr', 'keep', 'wait'], default: 'ask', enforcedBy: 'script', group: 'Finish', target: 'dforge',
    label: 'When done', title: 'When the finish menu goes unanswered',
    description: 'ask keeps the question before the first task. Any other value skips it: merge, pr or keep runs after the wait below; wait never acts.',
  },
  finishTimeout: {
    type: 'number', default: 30, min: 5, max: 240, step: 5, unit: 'min', enforcedBy: 'script', group: 'Finish', target: 'dforge',
    label: 'Menu waits', title: 'Finish menu wait (minutes)',
    description: 'How long the finish menu waits before the action above runs.',
  },
```

with:

```js
  finishAction: {
    type: 'enum', values: ['ask', 'merge', 'pr', 'keep', 'wait'], default: 'ask', enforcedBy: 'script', group: 'Finish', target: 'dforge',
    label: 'When done', title: 'When the work is done',
    description: 'ask asks before the first task. merge, pr or keep skips the question and runs that action as soon as the final review is clean; wait skips it and shows the finish menu then.',
  },
```

- [ ] **Step 4: Run test to verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: PASS, ending with 0 failed.
Run: `env -u CLAUDE_CONFIG_DIR timeout 300 node scripts/validate-repository.mjs`
Expected: `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/config/schema.mjs plugins/dforge/tests/dforge-config.test.sh
git commit -m "feat(dforge): retire the finishTimeout setting"
```

### Task 3: Recognise the new question in the Stop hook

**Files:**
- Modify: `plugins/dforge/scripts/turn-end.sh:2-4,147,161,171`
- Test: `plugins/dforge/tests/turn-end.test.sh:63-64`

**Interfaces:**
- Consumes: C2
- Produces: none

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing test**

In `plugins/dforge/tests/turn-end.test.sh`, replace:

```
check "finish-preference question: passes" "$(stop s-1 $'Before I start: when the implementation is done, the finish menu waits for\nyour answer. If it gets none within 30 minutes, what should I do?\n\nWhich option?')" ""
check "finish-preference question at a configured wait: passes" "$(stop s-1 $'Before I start: when the implementation is done, the finish menu waits for\nyour answer. If it gets none within 45 minutes, what should I do?\n\nWhich option?')" ""
```

with:

```
check "finish-preference question: passes" "$(stop s-1 $'Before I start: when the implementation is done and its final review is\nclean, what should I do?\n\n1. Merge back to main locally\n2. Push and create a Pull Request\n3. Keep the branch as-is\n4. Ask me then: show the finish menu and wait for my answer\n\nWhich option?')" ""
check "finish-preference question on a detached HEAD: passes" "$(stop s-1 $'Before I start: when the implementation is done and its final review is\nclean, what should I do?\n\n1. Push as new branch and create a Pull Request\n2. Keep as-is\n3. Ask me then: show the finish menu and wait for my answer\n\nWhich option?')" ""
write_ledger 'Task 1: complete (commits a..b, review clean)'
out=$(stop s-1 $'Before I start: when the implementation is done, the finish menu waits for\nyour answer. If it gets none within 30 minutes, what should I do?\n\nWhich option?')
check "the retired finish-preference question: blocks" "$(decision "$out")" "block"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/turn-end.test.sh`
Expected: FAIL on `finish-preference question: passes`, `finish-preference question on a detached HEAD: passes` (each got a block decision) and `the retired finish-preference question: blocks` (got none).

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/scripts/turn-end.sh`, make these exact replacements with the Edit tool.

Replace:

```
# finishing menu once the final review is clean, otherwise the `## Next session`
# block from scripts/next-step. Controllers that summarize and stop (common on
```

with:

```
# finishing menu once the final review is clean, or the `## Next session` block
# once finishing carried out the choice recorded before the run; otherwise the
# `## Next session` block from scripts/next-step. Controllers that summarize and
# stop (common on
```

Replace:

```
    ends_with '## Next session' 'If it gets none within ' && continue
```

with:

```
    ends_with '## Next session' 'Ask me then: show the finish menu' && continue
```

Replace:

```
            'Worktree removal refused' 'If it gets none within ' 'No plan file — no follow-on work recorded.' && exit 0
```

with:

```
            'Worktree removal refused' 'Ask me then: show the finish menu' 'No plan file — no follow-on work recorded.' && exit 0
```

Replace:

```
but your message ends without the finishing menu. Invoke dforge:finishing-a-development-branch with the Skill tool now and follow it: tests, the rulings and amendments, then the integration menu as the last thing in your message."
```

with:

```
but your message ends without the finishing menu or the next step. Invoke dforge:finishing-a-development-branch with the Skill tool now and follow it: tests, the rulings and amendments, then the finishing menu, or the next-step block once a recorded choice is carried out, as the last thing in your message."
```

- [ ] **Step 4: Run test to verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/turn-end.test.sh`
Expected: PASS, ending with 0 failed.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/turn-end.sh plugins/dforge/tests/turn-end.test.sh
git commit -m "feat(dforge): pass the reworded finish question"
```

### Task 4: Drop the countdown from the cockpit

**Files:**
- Modify: `plugins/dforge/types/index.d.ts:181-194`
- Modify: `plugins/dforge/hooks/cockpit/lib.ts:795-864`
- Modify: `plugins/dforge/hooks/cockpit/register.tsx` (the import list, eleven `finishLine(finishNow, now)` calls, `syncTicker`)
- Test: `plugins/dforge/tests/cockpit.test.ts:2126-2166`

**Interfaces:**
- Consumes: C1 (the `finish.json` fields it reads)
- Produces: C3

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

In `plugins/dforge/tests/cockpit.test.ts`, replace the whole test that begins `  test('reads the finish choice and counts it down', () => {` and ends at its closing `  })` with:

```ts
  test('reads the finish choice', () => {
    const chosen = parseFinish('{"action":"pr","base":"main","chosenAt":900}')
    expect(chosen).toEqual({ action: 'pr', base: 'main', answer: null })
    expect(parseFinish('{"action":"merge","base":"main","chosenAt":900,"armedAt":1000,"dueAt":2800,"job":"cron-7","firedAt":2800}')).toEqual({ action: 'merge', base: 'main', answer: null })
    expect(parseFinish('{"action":"later"}')).toBeNull()
    expect(parseFinish('{broken')).toBeNull()
    if (chosen === null) return
    expect(runsText(finishLine(chosen))).toBe('Finish push and open a PR when done')
    expect(runsText(finishLine({ ...chosen, action: 'merge' }))).toBe('Finish merge into main when done')
    expect(runsText(finishLine({ ...chosen, action: 'merge', base: null }))).toBe('Finish merge into the base branch when done')
    expect(runsText(finishLine({ ...chosen, action: 'keep' }))).toBe('Finish keep the branch when done')
    expect(runsText(finishLine({ ...chosen, action: 'wait' }))).toBe('Finish ask me when done')
    expect(finishLine({ ...chosen, answer: 'keep' })).toEqual([])
  })
```

In the test `shows the finish choice on the Run card`, replace:

```ts
    // The world's clock reads 1,000,000 ms; the menu's 30 minutes end at 2,800 s.
    expect(await ui.find({ type: 'Text', text: /⏱ Finish push and open a PR · in 30m/ })).toBeDefined()
```

with:

```ts
    // A file an older version armed shows the choice, with no countdown.
    expect(await ui.find({ type: 'Text', text: /Finish push and open a PR when done/ })).toBeDefined()
    expect(JSON.stringify(await ui.drawn())).not.toContain('⏱')
```

In the test `shows the finish choice for work without a plan or a todo list`, replace:

```ts
    expect(await ui.find({ type: 'Text', text: /⏱ Finish push and open a PR · in 30m/ })).toBeDefined()
    await ui.unmount()
    const desk = await $.ui.mount({ ...PANE, surface: 'desktop' })
    expect(JSON.stringify(await desk.drawn())).toContain('⏱ Finish push and open a PR · in 30m')
```

with:

```ts
    expect(await ui.find({ type: 'Text', text: /Finish push and open a PR when done/ })).toBeDefined()
    await ui.unmount()
    const desk = await $.ui.mount({ ...PANE, surface: 'desktop' })
    const drawn = JSON.stringify(await desk.drawn())
    expect(drawn).toContain('Finish push and open a PR when done')
    expect(drawn).not.toContain('⏱')
```

- [ ] **Step 2: Run test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: FAIL, either as a load or type error on `finishLine`'s one-argument calls, or in `run card > reads the finish choice` (the parsed object still carries `dueAt` and `firedAt`, and the chip reads `… if the menu goes unanswered`) and the two `shows the finish choice` tests (the chip still counts down).

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/types/index.d.ts`, replace:

```ts
/**
 * What dforge finishing does if its menu goes unanswered, as its
 * `finish-choice` script keeps it (finish.json). Times in milliseconds.
 */
export type CockpitFinish = {
  action: 'merge' | 'pr' | 'keep' | 'wait'
  base: string | null
  /** When the menu's wait runs out, once finishing armed the choice. */
  dueAt: number | null
  /** Your own answer to the menu, which overrides the choice. */
  answer: string | null
  /** When the wake carried the choice out. */
  firedAt: number | null
}
```

with:

```ts
/**
 * What dforge finishing does once the final review is clean, as its
 * `finish-choice` script keeps it (finish.json).
 */
export type CockpitFinish = {
  action: 'merge' | 'pr' | 'keep' | 'wait'
  base: string | null
  /** Set once finishing carried the choice out or you answered the menu. */
  answer: string | null
}
```

In `plugins/dforge/hooks/cockpit/lib.ts`, replace:

```ts
    const ms = (value: unknown) => (typeof value === 'number' ? value * 1000 : null)
    return {
      action,
      base: typeof raw.base === 'string' ? raw.base : null,
      dueAt: ms(raw.dueAt),
      answer: typeof raw.answer === 'string' ? raw.answer : null,
      firedAt: ms(raw.firedAt),
    }
```

with:

```ts
    return {
      action,
      base: typeof raw.base === 'string' ? raw.base : null,
      answer: typeof raw.answer === 'string' ? raw.answer : null,
    }
```

In the same file, replace everything from the line `export function isFinishArmed(finish: CockpitFinish | null): boolean {` through the closing `}` of `finishLine` (the block that ends with `    { text: left === '' || left === '0m' ? 'due now' : \`in ${left}\`, color: AMBER, bold: true },` then `  ]` then `}`), including the doc comment between them, with:

```ts
/**
 * The Run card's finish row: the option chosen before the run, until
 * finishing carries it out or you answer the menu yourself.
 */
export function finishLine(finish: CockpitFinish): Run[] {
  if (finish.answer !== null) return []
  const label =
    finish.action === 'merge'
      ? `merge into ${finish.base ?? 'the base branch'}`
      : finish.action === 'pr'
        ? 'push and open a PR'
        : finish.action === 'keep'
          ? 'keep the branch'
          : 'ask me'
  return [{ text: 'Finish ', dim: true }, { text: label, bold: finish.action !== 'wait' }, { text: ' when done', dim: true }]
}
```

The doc comment directly above `export function isFinishArmed` (if any) goes too; check with `grep -n "isFinishArmed" plugins/dforge/hooks/cockpit/lib.ts`, which must print nothing afterwards.

In `plugins/dforge/hooks/cockpit/register.tsx`:

- Delete the import line `  isFinishArmed,`.
- Replace every `finishLine(finishNow, now)` with `finishLine(finishNow)` (eleven occurrences on nine lines; use the Edit tool with replace-all).
- Replace:

```ts
    S.isTurnLive || (await read($, shells)).length > 0 || (await read($, spawns)).some(one => !one.isDone) || isFinishArmed(await read($, finish))
```

with:

```ts
    S.isTurnLive || (await read($, shells)).length > 0 || (await read($, spawns)).some(one => !one.isDone)
```

Then run `grep -n "isFinishArmed\|finishLine(finishNow, now)" plugins/dforge/hooks/cockpit/register.tsx`; it must print nothing.

- [ ] **Step 4: Run test to verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: PASS, `0 fail`.
Run: `grep -rn "isFinishArmed\|dueAt\|firedAt" plugins/dforge/hooks plugins/dforge/types`
Expected: no output (the once-a-second redraw no longer considers the finish choice; see Assumptions on A6).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/types/index.d.ts plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(dforge): drop the finish countdown chip"
```

### Task 5: Rewrite finishing and its reference

**Files:**
- Modify: `plugins/dforge/reference/finish-preference.md` (whole file)
- Modify: `plugins/dforge/skills/finishing-a-development-branch/SKILL.md` (Core principle, §Auto run, Steps 3, 4 and 5, Common Rationalizations)
- Test: `plugins/dforge/tests/settings-skills.test.sh`

**Interfaces:**
- Consumes: C1, C2, C4
- Produces: none

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing test**

In `plugins/dforge/tests/settings-skills.test.sh`, replace:

```
names "finish-preference: finishTimeout" "$F" 'finishTimeout'
```

with:

```
names "finish-preference: the question offers Ask me then" "$F" '4. Ask me then: show the finish menu and wait for my answer'
FIN="$P/skills/finishing-a-development-branch/SKILL.md"
names "finishing: a recorded choice runs with no menu" "$FIN" '**A choice recorded before the run.**'
names "finishing: an answered record is never re-run" "$FIN" 'A record whose `answer` field is set has been used'
names "finishing: a null base is found without asking" "$FIN" 'upstream, as Step 3 does, without asking or confirming'
names "finishing: Step 3 asks nothing for a recorded choice" "$FIN" 'never ask here: Step 4 says where its base comes from'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/settings-skills.test.sh`
Expected: FAIL on the five new checks.

- [ ] **Step 3: Write the implementation**

Replace the whole of `plugins/dforge/reference/finish-preference.md` with:

````markdown
# Finish Preference

A run ends while its human is away more often than not, and a finishing menu
nobody answers leaves the finished branch unintegrated. So the finish action
is asked once, before the first task, and
dforge:finishing-a-development-branch carries it out as soon as the final
review is clean, with no menu and no wait. Choosing "Ask me then" keeps the
menu.

`scripts/finish-choice` keeps the choice (see using-dforge §Session
Budget). Pass `--plan PLAN_FILE` in a plan run; leave it out for work done
without a plan.

## Auto run

An auto run ([auto-run.md](auto-run.md)) never asks the question below:
finishing carries out `finishAction` at once into the run's recorded base
(`merge` or `pr`), and keeps the branch under `keep`, `ask` or `wait`, or when
there is no base, with no menu.

## The setting

`finishAction` (`scripts/dforge-config`, or the cockpit's Finish tab): `ask`,
the default, keeps the question below. With `merge`, `pr`, `keep` or `wait`,
`scripts/finish-choice get` records and prints that action whenever nothing is
chosen yet, so the question is never asked: the "skip the question when `get`
prints a choice" rule already covers it. A choice recorded this way has no base
branch (`base` is null): finishing finds it as its Step 4 says.

## When to ask

- **A plan run** (dforge:subagent-driven-development or
  dforge:executing-plans): at Setup, before the pre-flight and Task 1.
  Skip the question when `scripts/finish-choice get --plan PLAN_FILE` already
  prints a choice, or when the plan's ledger already exists: a resumed run
  never stops to ask, and its finishing menu simply waits.
- **Work without a plan** that you will finish with
  finishing-a-development-branch (implementation on its own branch or
  worktree, straight from the chat): before the first change, once
  dforge:using-git-worktrees has the workspace ready.
- Never in the middle of a run, and never again once answered.

## The question

Determine the base branch first, as finishing Step 3 would (the plan, the
conversation, the branch's upstream), so the merge option names it. Then ask
exactly this, as the last thing in the message:

```
Before I start: when the implementation is done and its final review is
clean, what should I do?

1. Merge back to <base-branch> locally
2. Push and create a Pull Request
3. Keep the branch as-is
4. Ask me then: show the finish menu and wait for my answer

Which option?
```

From a detached HEAD the merge option does not exist: offer "Push as new
branch and create a Pull Request", "Keep as-is" and "Ask me then: show the
finish menu and wait for my answer".

Ask before this run writes anything to its ledger: the stop hook holds a turn
that wrote a ledger and ends on anything but the next step. Record the answer,
with the base branch the merge option named, and start work in the same turn
("Ask me then" records `wait`):

```bash
bash <plugin-root>/scripts/finish-choice set <merge|pr|keep|wait> --base <base-branch> [--plan PLAN_FILE]
```

An answer that is not one of the options (a question, a change of plan) is
handled first; ask again only if it left the choice open. Asking is the only
pause this adds: a run never stops again for it.

## At finishing

finishing-a-development-branch Step 4 reads the choice after its in-flight
check. A `merge`, `pr` or `keep` with no `answer` field is carried out at once,
with no menu: the step records it with `scripts/finish-choice answer`, finds
the base without asking, and stops wherever an attended finish would ask.
`wait`, nothing recorded, or a record already answered shows the menu. Step 4
holds the full rule.

## When your human partner answers the menu

Run `scripts/finish-choice answer <merge|pr|keep|discard> [--plan PLAN_FILE]`
before acting on the answer, then carry it out.
````

In `plugins/dforge/skills/finishing-a-development-branch/SKILL.md`, make these exact replacements with the Edit tool.

1. Replace:

```
**Core principle:** Verify tests → Detect environment → Present options (armed with the choice made before the run) → Execute choice → Record the plan → Clean up → Report the next step.
```

with:

```
**Core principle:** Verify tests → Detect environment → Carry out the choice made before the run, or present options → Execute choice → Record the plan → Clean up → Report the next step.
```

2. Replace:

```
  Keep As-Is. Never discard. Arm no wake. Three cases override this: on a
```

with:

```
  Keep As-Is. Never discard. In an auto run this mapping replaces Step 4's
  recorded-choice block. Three cases override this: on a
```

2a. Replace:

```
  `scripts/auto-run stop --reason "<what stopped it>"` first, then stop as
  Step 1 or [finish-preference.md](../../reference/finish-preference.md) says.
```

with:

```
  `scripts/auto-run stop --reason "<what stopped it>"` first, then stop as
  Step 1 or Step 5's "Whose choice it is" says.
```

3. Replace:

```
the base your human partner confirmed then; use it. Otherwise, if it is not
already known, ask:
```

with:

```
the base your human partner confirmed then; use it. When Step 4 carries out
a recorded choice, never ask here: Step 4 says where its base comes from.
Otherwise, if it is not already known, ask:
```

4. Replace:

```
dforge:handoff step 0 says, and run it again. Present the menu only on
exit 0, or on exit 3 after checking by hand.
```

with:

```
dforge:handoff step 0 says, and run it again. Go on only on exit 0, or on
exit 3 after checking by hand.

**A choice recorded before the run.** Then run
`scripts/finish-choice get [--plan PLAN_FILE]`
([finish-preference.md](../../reference/finish-preference.md)):

- It prints `merge`, `pr` or `keep` with no `answer` field: show no menu.
  Run `scripts/finish-choice answer <action> [--plan PLAN_FILE]`, then carry
  the option out from Step 5 by name, exactly as if your human partner had
  chosen it; never discard. The base is the recorded `base`. When that is
  null or `none`, take it from the plan, the conversation or the branch's
  upstream, as Step 3 does, without asking or confirming; when none of those
  names one, `merge` keeps the branch and `pr` opens its request against the
  repository's default branch. On a detached HEAD, `merge` keeps the branch
  and `pr` pushes a new branch (`git push origin HEAD:refs/heads/<new-branch>`).
  Write no "After integration" line: Step 7's block says what follows. Open
  the final message with `Finished with <the option, as worded in the menu
  below>, as chosen before the run.`
- A record whose `answer` field is set has been used: an earlier immediate
  finish stopped, or the menu was answered. Show the menu and wait; never
  re-run the action unattended.
- It prints `wait`, exits 3 (nothing recorded), or fails any other way (no
  jq, outside a repository): show the menu below and wait.
```

5. Replace:

```
**Arm the finish preference.** When a choice was recorded before the run
([finish-preference.md](../../reference/finish-preference.md)), run
`scripts/finish-choice arm [--plan PLAN_FILE]` as you present the menu. Unless
it exits 3, schedule the wake it prints (CronCreate on Claude Code), and make
the menu's last line before `Which option?` say what happens without an answer:
`No answer by <due>: I'll <option> (chosen before the run).` Without a
scheduler, say `Chosen before the run: <option>. Reply to confirm or pick
another.` instead.

Present the menu exactly as written
```

with:

```
Present the menu exactly as written
```

6. Replace:

```
**Whose choice it is.** When your human partner answers the menu, run
`scripts/finish-choice answer <merge|pr|keep|discard> [--plan PLAN_FILE]`
first and cancel the wake it names with CronDelete: their answer overrides
the one chosen before the run. When the wake fires instead, the action
`scripts/finish-choice due` prints is the choice; follow
[finish-preference.md](../../reference/finish-preference.md) §When the wake
fires. An unattended finish never asks: where a step would ask (a refused
worktree removal, a failing merged result), it stops, leaves everything in
place and shows the menu again.
```

with:

```
**Whose choice it is.** When your human partner answers the menu, run
`scripts/finish-choice answer <merge|pr|keep|discard> [--plan PLAN_FILE]`
first, then carry out their answer. When Step 4 carries out a recorded
choice, it is theirs, made before the run. An immediate finish never asks:
where a step would ask (a refused worktree removal, a failing merged result,
a rejected push), it stops, leaves everything in place, reports what stopped
it and shows the menu; never pick a destructive answer for your human
partner.
```

7. Replace:

```
| "They obviously want it merged" | Integration is your human partner's decision. Present the menu and wait; only the choice they made before the run acts for them, and only after the configured wait goes unanswered. |
| "The wake fired, but they replied a minute ago — the timer still says merge" | Their reply wins. `scripts/finish-choice answer` disarms the timer; a wake after it finds nothing due. |
```

with:

```
| "They obviously want it merged" | Integration is your human partner's decision. Present the menu and wait; only the choice they made before the run acts for them, and it acts at once. |
```

7a. Replace:

```
| "The base branch is obviously main" | Confirm the fork point or ask. Merging into the wrong base is expensive to undo. |
```

with:

```
| "The base branch is obviously main" | Confirm the fork point or ask, unless Step 4 carries out a choice recorded before the run, which takes its base from the record, the plan, the conversation or the upstream. Merging into the wrong base is expensive to undo. |
```

8. Replace:

```
| "I printed the rulings and the review — that wraps up the run" | Without the menu nothing integrates. The three options close the message, every time. |
```

with:

```
| "I printed the rulings and the review — that wraps up the run" | Without the menu or a recorded choice nothing integrates. With no recorded choice the options close the message, every time; a run that carried out its choice ends on the next-step block. |
```

- [ ] **Step 4: Run test to verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/settings-skills.test.sh`
Expected: PASS, ending with 0 failed.
Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh`
Expected: PASS, ending with 0 failed (its pins on §Auto run are unchanged).
Run: `grep -n "finish-choice arm\|finish-choice due\|CronCreate\|CronDelete\|configured wait" plugins/dforge/skills/finishing-a-development-branch/SKILL.md plugins/dforge/reference/finish-preference.md`
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/reference/finish-preference.md plugins/dforge/skills/finishing-a-development-branch/SKILL.md plugins/dforge/tests/settings-skills.test.sh
git commit -m "feat(dforge): finish on the recorded choice at once"
```

### Task 6: Update the docs that describe the wait

**Files:**
- Modify: `plugins/dforge/skills/subagent-driven-development/SKILL.md:214-215`
- Modify: `plugins/dforge/skills/executing-plans/SKILL.md:146-147`
- Modify: `plugins/dforge/skills/using-git-worktrees/SKILL.md:147-149`
- Modify: `plugins/dforge/skills/using-dforge/references/codex-tools.md:117-122`
- Modify: `plugins/dforge/reference/auto-run.md:251`
- Modify: `plugins/dforge/README.md:421-436,624-628,783-784`
- Test: `plugins/dforge/tests/settings-skills.test.sh:81-85`

**Interfaces:**
- Consumes: C1, C4
- Produces: none

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing test**

In `plugins/dforge/tests/settings-skills.test.sh`, replace:

```
# The finish menu's wait is a setting now: 30 minutes may appear only as its default.
for file in "$P/skills/executing-plans/SKILL.md" "$P/skills/subagent-driven-development/SKILL.md" "$G" \
  "$P/skills/finishing-a-development-branch/SKILL.md" "$F"; do
  check "${file#"$P"/} states no fixed finish wait" "$(grep '30 minutes' "$file" | grep -vc 'by default')" "0"
done
```

with:

```
# The finish menu has no timer: no skill, reference or README names its machinery.
# Each file is read as one line, so a phrase wrapped across lines still counts.
for file in "$P"/skills/*/SKILL.md "$P"/skills/*/references/*.md "$P"/reference/*.md "$P/README.md"; do
  check "${file#"$P"/} names no finish timer" "$(tr '\n' ' ' < "$file" | tr -s ' ' | grep -cE 'finish-choice (arm|due|job)|finishTimeout|configured wait|CronCreate|CronDelete|no wake')" "0"
done
```

- [ ] **Step 2: Run test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/settings-skills.test.sh`
Expected: FAIL for `skills/subagent-driven-development/SKILL.md`, `skills/executing-plans/SKILL.md`, `skills/using-git-worktrees/SKILL.md`, `skills/using-dforge/references/codex-tools.md`, `reference/auto-run.md` and `README.md` (each names no finish timer: got a nonzero count).

- [ ] **Step 3: Write the implementation**

Make these exact replacements with the Edit tool.

In `plugins/dforge/skills/subagent-driven-development/SKILL.md` and, identically, in `plugins/dforge/skills/executing-plans/SKILL.md`, replace:

```
ask what finishing should do if its menu goes unanswered for the configured
wait, record the answer, and start work in the same turn. Skip it when
```

with:

```
ask what finishing should do once the final review is clean, record the
answer, and start work in the same turn. Skip it when
```

In `plugins/dforge/skills/using-git-worktrees/SKILL.md`, replace:

```
before the first change: what finishing should do if its menu goes unanswered
for the configured wait (the `finishTimeout` setting, 30 minutes by default). See
```

with:

```
before the first change: what finishing should do once the work is done. See
```

In `plugins/dforge/skills/using-dforge/references/codex-tools.md`, replace:

```
## No scheduled wake

Codex has no CronCreate, so nothing wakes a session whose finishing menu went
unanswered. Still ask the finish preference before a run and record it; at the
menu, say which option was chosen before the run and wait for a reply
([finish-preference.md](../../../reference/finish-preference.md)).
```

with:

```
## Finish preference

Ask the finish preference before a run and record it. Finishing carries out a
recorded choice at once, so it needs no scheduler
([finish-preference.md](../../../reference/finish-preference.md)).
```

In `plugins/dforge/reference/auto-run.md`, replace:

```
against the dforge's default branch. No menu, no wake. Its final message lists
```

with:

```
against the dforge's default branch. No menu. Its final message lists
```

In `plugins/dforge/README.md`, replace:

```
A run also asks one question before its first task: what finishing should do
if its menu goes unanswered for the configured wait, 30 minutes by default
(merge locally, push and open a pull request, keep the branch, or wait).
`scripts/finish-choice` keeps the answer beside the ledger
(`.dforge/sdd/<plan>/finish.json`, or `.dforge/sdd/finish.json` for work done
without a plan). When finishing
shows its menu, it arms that choice and schedules a one-shot wake with
CronCreate; the menu's last line says what happens and when. An answer to the
menu inside that wait disarms the wake and wins; otherwise the wake
carries out the chosen option as if it had been picked, and stops wherever an
attended finish would ask. The cockpit Run card shows the choice and the
deadline. Codex has no scheduler, so there the menu names the choice and waits.

With the `finishAction` setting at `merge`, `pr`, `keep` or `wait`, the run does
not ask that question: `scripts/finish-choice` records the configured action
the first time it is read, and `finishTimeout` sets the wait.
```

with:

```
A run also asks one question before its first task: what finishing should do
once the final review is clean (merge locally, push and open a pull request,
keep the branch, or ask then). `scripts/finish-choice` keeps the answer beside
the ledger (`.dforge/sdd/<plan>/finish.json`, or `.dforge/sdd/finish.json` for
work done without a plan). Finishing carries out that choice at once, with no
menu, and stops wherever an attended finish would ask (failing tests, a
rejected push, a refused worktree removal), ending on the menu. "Ask me then"
shows the menu and waits for your answer. The cockpit Run card shows the
choice.

With the `finishAction` setting at `merge`, `pr`, `keep` or `wait`, the run does
not ask that question: `scripts/finish-choice` records the configured action
the first time it is read.
```

In the same file, replace:

```
  **Finish** row shows what dforge will do if the finishing menu goes
  unanswered (the option chosen before the run), then counts down the menu's
  wait (`⏱ Finish push and open a PR · in 23m`) and says once it was
  carried out. It disappears when you answer the menu yourself. Work done
  without a plan shows the row on the Plan card.
```

with:

```
  **Finish** row shows what dforge will do once the final review is clean
  (the option chosen before the run: `Finish push and open a PR when done`).
  It disappears once finishing carries the choice out or you answer the menu
  yourself. Work done without a plan shows the row on the Plan card.
```

In the same file, replace:

```
| Finish | `finishAction` | `ask` | What happens when the finish menu goes unanswered. `ask` keeps the question before the first task; `merge`, `pr` or `keep` skips it and runs after the wait; `wait` skips it and never acts. |
| Finish | `finishTimeout` | `30` | Minutes the finish menu waits before that action runs (5-240). |
```

with:

```
| Finish | `finishAction` | `ask` | What finishing does once the final review is clean. `ask` keeps the question before the first task; `merge`, `pr` or `keep` skips it and runs that action at once; `wait` skips it and shows the finish menu then. |
```

- [ ] **Step 4: Run test to verify it passes**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/settings-skills.test.sh`
Expected: PASS, ending with 0 failed.
Run: `env -u CLAUDE_CONFIG_DIR timeout --kill-after=10s 690s node scripts/test-all.mjs`
Expected: every suite passes.
Run: `env -u CLAUDE_CONFIG_DIR timeout 300 node scripts/validate-repository.mjs`
Expected: `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`
Run each of these, one per line, and expect `✔ Validation passed` from each:
`timeout 120 /root/.local/bin/claude plugin validate .`
`timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`
`timeout 120 /root/.local/bin/claude plugin validate plugins/dr-status`
`timeout 120 /root/.local/bin/claude plugin validate plugins/darkraise-ui`
`timeout 120 /root/.local/bin/claude plugin validate plugins/darkraise-win32ui`

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/subagent-driven-development/SKILL.md plugins/dforge/skills/executing-plans/SKILL.md plugins/dforge/skills/using-git-worktrees/SKILL.md plugins/dforge/skills/using-dforge/references/codex-tools.md plugins/dforge/reference/auto-run.md plugins/dforge/README.md plugins/dforge/tests/settings-skills.test.sh
git commit -m "docs(dforge): describe the finish without a wait"
```
