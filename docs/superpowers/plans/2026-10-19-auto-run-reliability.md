# Auto Run Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make dforge's unattended auto run reliable: execution starts at Setup in a worktree after the switch, no question reaches the owner after the spec review, a stalled or looping run is woken or stopped with a reason, and the owner's model defaults are never left changed.

**Architecture:** `scripts/auto-run` gains a primary-checkout guard, `setupDue`, a `stalled` command, a compaction cap and a cockpit-heartbeat check; `next-step`, `finish-choice`, `dforge-path`, `context-size --final` and the Stop hook each get one targeted fix; the cockpit mod gains a watchdog, a heartbeat and guards around its compaction and `/model` stages; the execution skills, references, brainstorming, writing-plans and finishing say what an auto run does on each path the controller actually takes.

**Tech Stack:** Bash scripts with shell test suites, the TypeScript cockpit mod (tested by `claude plugin test`), Markdown skills and references.

**Spec:** `docs/superpowers/specs/2026-10-19-switch-setup-fixes-design.md`

**Execution:** inline — `claude --model sonnet --effort high` — 5 of 16 tasks are heavy (Tasks 1, 2, 3, 10, 11), under half; they are delegated

**Plan review:** 2026-10-19 — dr-superpowers:judge-opus — executability 15 / coherence 17 / coverage 18 / assumptions 11 (round 2)

**Parallelism:** sequential — most tasks edit the same few files (`scripts/lib/auto-run.sh`, `tests/auto-run.test.sh`, the two execution skills, `reference/auto-run.md`, the cockpit's `register.tsx` and `cockpit.test.ts`), as the spec's Execution strategy says


## Global Constraints

- Work in a worktree branched from local `main` (local `main` runs 411 commits ahead of `origin/main`): `git worktree add .claude/worktrees/auto-run-reliability -b auto-run-reliability main`. This plan, its spec and its register must be on local `main` first: before Task 1, `ls docs/superpowers/plans/2026-10-19-auto-run-reliability.md` in the worktree must list the file, or stop. Do not push.
- Never edit anything under `docs/superpowers/` by hand: it is history (register rows are set by the execution skill's own scripts).
- Run each command on its own line; do not chain commands that mention git with `&&`, `;` or a pipe (the worktree guard refuses them).
- Run suites from the worktree root under a bound, with the host's `CLAUDE_CONFIG_DIR` removed: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/<name>.test.sh`. The cockpit suite runs as `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge` (in this host's Bash `claude` is a shell function that exits 127).
- The whole suite is `env -u CLAUDE_CONFIG_DIR timeout --kill-after=10s 690s node scripts/test-all.mjs` from the worktree root. Every task leaves it green, and a phrase that a test file pins (`grep -F` in `plugins/dforge/tests/`) stays byte-identical unless this task's own steps change that pin. Before committing, run every shell test file that names a file this task changed: `grep -l <basename> plugins/dforge/tests/*.sh`.
- Commits: `<type>(<scope>): <subject>`, subject at most 50 characters, imperative, no period; author and committer `Darkraise <quangtc94@gmail.com>` (the repository's `user.name`/`user.email`); no `Co-Authored-By:`, `Claude-Session:` or "Generated with" line, nor any other AI attribution.
- Only Task 15 changes a manifest version.
- An `Expected:` pass count comes from the dry run; a different count that still ends `0 failed` is not a stop. A failing check is.
- An edit's old text that is not found exactly once is a stop: report BLOCKED with the file and the text. Never paraphrase an edit; copy the new text exactly, including its line breaks.
- `plugins/dforge/skills/using-dforge/SKILL.md` stays at or below 5,100 bytes (`tests/hook.test.sh` checks it).
- Prose wraps at 80 columns like the surrounding text, except where a new text block below wraps differently: copy those as written.
- Stop every process a check starts. Task 16's probe is the one step that starts long-lived processes (nested Claude Code sessions in tmux); it kills its own tmux sessions and nothing else.

## Contracts

- **C1 Run state fields (Tasks 1, 2, 3, 11).** `scripts/lib/auto-run.sh`'s state gains `setupDue` (boolean, absent = false), `stalls` (integer, absent = 0), `stalledAt` (epoch seconds or null) and `compactionsSinceTask` (integer, absent = 0). `ar_start` writes `setupDue: false, stalls: 0, stalledAt: null, compactionsSinceTask: 0`. Readers treat an absent field as its default, so a state written before this plan still works.
- **C2 The primary-checkout test (Tasks 1, 4).** `ar_in_primary` returns 0 when `git rev-parse --absolute-git-dir` equals `git rev-parse --path-format=absolute --git-common-dir` in the current directory, and 1 otherwise (including outside git).
- **C3 `scripts/auto-run` behaviour (Tasks 1, 2, 3, 9, 10, 11, 12, 13).**
  - `switch` also sets `setupDue` to true and `compactionsSinceTask` to 0.
  - `phase execute` in the primary checkout changes nothing, prints `auto-run: this is the primary checkout; create the execution worktree first (dforge:using-git-worktrees), then run auto-run phase execute from it` to stderr and exits 4; elsewhere it sets `phase` to `execute`, sets `setupDue` to false and exits 0. `phase final` also sets `setupDue` to false. Other phases are unchanged.
  - `task-complete` in the primary checkout stops the run with the reason `a task was completed in the primary checkout`, prints `auto-run: a task was completed in the primary checkout; the run has stopped. End as reference/auto-run.md §Stopping says.` to stderr and exits 5. Elsewhere it resets `resumes`, `stalls`, `stalledAt` and `compactionsSinceTask`, sets `setupDue` to false, and exits 0.
  - `status` appends ` — setup due` to its line while `setupDue` is true.
  - `after-compact`, on a `continue` result while `setupDue` is true, appends `; setup due: begin at the execution skill's Setup, worktree first` to its line.
  - `stalled` (new): sets `stalledAt` to now (epoch seconds) and adds 1 to `stalls`; at 3 it stops the run with the reason `three stalls without a completed task` and exits 5; otherwise exits 0 and prints nothing.
  - `compacted` (without `--switch`) in the `execute` phase adds 1 to `compactionsSinceTask`; when that reaches 3 it stops the run with the reason `three compactions without a completed task` and exits 5. `compacted --switch` and compactions in other phases never count.
  - `start` exits 2 with `auto-run: no live cockpit in this session` on stderr when the heartbeat (C4) for the session is missing or older than 180 seconds.
- **C4 The cockpit heartbeat (Tasks 2, 10).** The cockpit takes the home directory from `$.env.get('HOME')`, falling back to `USERPROFILE`, as `readPlace` does. File `$HOME/.claude/dforge/sessions/cockpit/<id>`, where `<id>` is the session id with every character outside `A-Za-z0-9` replaced by `-` (the by-id records' rule). Content: the epoch seconds of the last beat, one integer and a newline. Fresh means `now - content <= 180`. `ar_is_stale` uses the heartbeat when the bound session has a heartbeat file (stale when older than 180 seconds), and today's 60-minute transcript rule otherwise.
- **C5 `scripts/context-size --final` (Task 4).** In a bound run whose `phase` is `execute`, when the attached plan's ledger (`plan_ledger`) has a `Task N: complete` line for every task `plan_tasks` lists, it sets `phase` to `final` and `setupDue` to false before measuring. Otherwise the phase is unchanged.
- **C6 `scripts/next-step`'s no-ledger prompt (Task 6).** ``Continue `<plan>` with dforge:<skill>. No ledger exists yet: begin at the skill's Setup, worktree first; the first task is Task <N> (<title>).`` The `**Next:**` line stays `Start at Task <N> (<title>).`
- **C7 `scripts/finish-choice get --plan` (Task 7).** With no `finish.json`, the spec's `Finish:` line is recorded as `{action, base: null, chosenAt, source: "spec"}` ahead of the `finishAction` setting.
- **C8 `dforge-path ledger SLUG|PLAN_FILE` (Task 8).** A slug, or a plan path reduced to its basename without `.md` after `\` becomes `/`.
- **C9 Cockpit names (Tasks 9, 10, 11).** `S.autoBusy` (boolean) is true for the whole of `autoAct`; `S.autoActedAt` (epoch milliseconds, or null) is set when `autoAct` finishes, and `S.watchedSince` (epoch milliseconds) at `session.start`, so the watchdog measures `STALL_MS` from the latest of whichever exist of `S.watchedSince`, the turn's `endedAt`, `S.autoActedAt` and the run's `stalledAt`: a session with no turn yet, such as a cleared one, still ages, and a stage's own prompt, which looks idle until the engine starts its turn, is not taken for a stall. The cockpit's `CockpitAutoRun` type and `autoRunFor` (`lib.ts`) read `stalledAt`. The watchdog runs every `WATCHDOG_MS = 60_000`; a stall is `STALL_MS = 180_000`; the deferral cap is `DEFER_CAP_MS = 1_800_000`. The stall prompt is ``The auto run stalled: the last turn ended without its sentinel line. Run `bash <plugin-root>/scripts/auto-run status`, continue the phase it names, and end the turn as reference/auto-run.md §Ending a turn says.``
- **C10 Skill phrases (Tasks 12, 13, 14).** The pins those tasks add are the exact sentences in their steps; `tests/auto-run-skills.test.sh` belongs to Task 12 for the execution skills and to Task 13 for the references, and `tests/auto-default.test.sh` to Task 14.

- **C11 Test helpers in `plugins/dforge/tests/auto-run.test.sh` (Tasks 1, 2, 3).** Task 1 adds `side() { (cd "$TMP/side" && bash "$AR" "$@"); }`: it runs `scripts/auto-run` with the given arguments from the linked worktree `$TMP/side` (branch `side`), which the suite creates with `git -C "$REPO" worktree add -q -b side "$TMP/side"` in its "a start from a linked worktree" section, so `side` works only after that line; it writes no heartbeat. Task 2 adds `beat <session> [age in seconds]`, which writes the C4 heartbeat file `$HOME/.claude/dforge/sessions/cockpit/<session>` holding the current epoch seconds less the age (default 0), creating the directory, and turns `ar` into `ar() { [ "${1:-}" != --session ] || beat "$2"; (cd "$REPO" && bash "$AR" "$@"); }`: every call through `ar` that starts with `--session <id>` first writes a fresh heartbeat for that session (side effect: that session counts as live for `ar_is_stale`), then runs the script from the primary checkout `$REPO`. Calls that must see no heartbeat or an old one call `bash "$AR"` directly. `field <name>` (unchanged) prints a state field as a string, `null` when unset.

## Assumptions (evidence)

- **New shell suites and checks are picked up without registration.** `scripts/test-all.mjs` runs every `plugins/dforge/tests/*.test.sh` (read 2026-10-19).
- **The Codex lane is on.** `codex-gate` printed `usable=true reason=ok review=true lane=true resets_at=- source=probe` on 2026-10-19; `docs/superpowers/distilled/constraints.md` ticks `codex` without asking.
- **The cockpit suite does not run in the Codex sandbox** (register row 12), so the cockpit tasks carry no Executor line.
- **A switched session follows After compaction and skips Setup** — observed 2026-10-19 (register row 13's Note); Task 16 verifies the fix on a real engine.
- **Every task was dry-run before the plan was saved.** On 2026-10-19 each task's steps were applied in order to a scratch copy of `plugins/dforge`: each new check failed before its implementation and passed after; after the round-1 review fixes each part was dry-run again on 2026-10-19 — Tasks 1-8 in order (every shell suite green), Tasks 9-11 in order (`claude plugin test` 266 pass, 0 fail), Tasks 12-14 in order (the 16 suites they name green, `node scripts/test-all.mjs` exit 0). The parts touch disjoint files, and the cockpit suite fakes `scripts/auto-run`, so the parts do not change each other's results; the whole plan was not dry-run as one piece after those fixes.
- **Plan review ended at the cap with assumptions 11 (borderline).** Decision: proceed. The two assumption gaps it named (the executor scope and the dry-run counts) are closed by dropping every Executor line and by the pass-count constraint; nothing it raised is Critical.
- **`dforge-path`'s plan-path test lives in `tests/dforge-dir.test.sh`**, the suite that runs the `dforge-path` script and already holds `dforge-path: ledger, local`; the spec's Testing section names `tests/roots.test.sh`, which tests only the library.
- **`scripts/lib/auto-run.sh` sources `plan.sh` instead of `roots.sh` (Task 4)**, since `ar_enter_final` needs `plan_tasks`, `plan_ledger` and `plan_locate`; `plan.sh` sources `roots.sh` itself, and no function name collides (`grep` of both libraries' definitions, 2026-10-19).
- **Between Task 2 and Task 10 no real auto run can start**: `auto-run start` needs the cockpit heartbeat that Task 10 writes. One sequential branch merges both, so no release carries one without the other.
- **No task goes to Codex.** Every task's suites run scripts or `node`: Tasks 6-8 load `roots.sh`, whose failed `darkmem-config.mjs` call exits 2 (`plugins/dforge/scripts/lib/roots.sh:52-55`, read 2026-10-19), and Tasks 12-14 also run `next-step`, `inline-mode`, `settings-skills` and other script suites (round-2 plan review). The plan is Claude-only although the lane is on.
- **Three spec sentences were refined while drafting (spec amended 2026-10-19):** in wave mode the Fable batch stays after the wave (§F); Step 5b runs only for finish Options 1 and 2 (§K, A20); dforge:handoff names the inline-to-subagent switch beside the compaction (§G). Task 12 numbers the new After compaction step `0.` so the pinned steps 1-4 keep their numbers.

## Task index

1. Auto-run primary-checkout guard
2. Auto-run cockpit heartbeat
3. Auto-run stalls and compaction cap
4. context-size --final enters the final phase
5. Stop hook holds without a stamp
6. next-step names Setup on a cold start
7. finish-choice reads the spec's Finish line
8. dforge-path ledger takes a plan path
9. Cockpit switch, compaction and restore guards
10. Cockpit heartbeat and deferral cap
11. Cockpit watchdog wakes a stalled run
12. Execution skills after the switch
13. Auto-run, final-review and worktree references
14. Brainstorming, writing-plans and finishing text
15. Release dforge 4.1.0
16. Probe the fixed flow on a real engine

---

### Task 1: Auto-run primary-checkout guard

**Files:**
- Modify: `plugins/dforge/scripts/lib/auto-run.sh`
- Modify: `plugins/dforge/scripts/auto-run`
- Test: `plugins/dforge/tests/auto-run.test.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: C1 (`ar_start` writes `setupDue`, `stalls`, `stalledAt`, `compactionsSinceTask`), C2 (`ar_in_primary`), and C3's `switch`, `phase execute`, `phase final`, `task-complete`, `status` and `after-compact` behaviour. This task adds C11's `side` helper.

**Items:** 13

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

The suite's existing `phase execute` and `task-complete` calls move to the linked worktree `$TMP/side`, since both commands now refuse or stop in the primary checkout.

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/auto-run.test.sh`, replace:

````
ar() { (cd "$REPO" && bash "$AR" "$@"); }
````

with:

````
ar() { (cd "$REPO" && bash "$AR" "$@"); }
# The same, from the linked worktree $TMP/side (made below): where an auto
# run's execution happens.
side() { (cd "$TMP/side" && bash "$AR" "$@"); }
````

In `plugins/dforge/tests/auto-run.test.sh`, replace:

````
check "worktree: the state stays in the primary checkout" "$(field session) $(field base)" "s-5 side"
````

with:

````
check "worktree: the state stays in the primary checkout" "$(field session) $(field base)" "s-5 side"
side --session s-5 phase execute; status=$?
check "a run started in a linked worktree: phase execute there passes" "$status:$(field phase)" "0:execute"
````

In `plugins/dforge/tests/auto-run.test.sh`, replace:

````
ar --session s-1 attach --plan docs/plan.md
ar --session s-1 phase execute
check "attach and phase" "$(field plan) $(field phase)" "docs/plan.md execute"
````

with:

````
ar --session s-1 attach --plan docs/plan.md
ar --session s-1 phase execute 2>"$TMP/err"; status=$?
check "phase execute in the primary checkout: exit 4, phase unchanged" "$status:$(field phase)" "4:spec"
check "phase execute in the primary checkout: says to make the worktree" "$(grep -c 'create the execution worktree first (dforge:using-git-worktrees)' "$TMP/err")" "1"
side --session s-1 phase execute; status=$?
check "phase execute from a linked worktree: exit 0" "$status" "0"
check "attach and phase" "$(field plan) $(field phase)" "docs/plan.md execute"
````

In `plugins/dforge/tests/auto-run.test.sh`, replace:

````
ar --session s-10 task-complete
````

with:

````
side --session s-10 task-complete
````

In `plugins/dforge/tests/auto-run.test.sh`, replace:

````
DFORGE_FLOCK=no-such-flock ar --session s-1 task-complete; status=$?
````

with:

````
DFORGE_FLOCK=no-such-flock side --session s-1 task-complete; status=$?
````

In `plugins/dforge/tests/auto-run.test.sh`, replace:

````
ar --session s-1 phase execute
ar --session s-1 compacted
out=$(after); status=$?
check "after-compact in execute: 85% of the window still hands off" "$status:${out%% *}" "5:handoff"
````

with:

````
side --session s-1 phase execute
ar --session s-1 compacted
out=$(after); status=$?
check "after-compact in execute: 85% of the window still hands off" "$status:${out%% *}" "5:handoff"
````

In `plugins/dforge/tests/auto-run.test.sh`, replace:

````
printf '\n%d passed, %d failed\n' "$pass" "$fail"
````

with:

````
# --- Setup after the switch: setupDue and the primary-checkout guard ---
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
check "start: setup is not due" "$(field setupDue)" "false"
ar --session s-1 attach --plan docs/plan.md
ar --session s-1 phase plan
ar --session s-1 switch
check "switch: setup is due" "$(field setupDue)" "true"
check "status: says setup is due" "$(ar --session s-1 status | grep -c ' — setup due$')" "1"
ar --session s-1 compacted --switch
ar --session s-1 resumed
asst 30000 > "$T"
out=$(after); status=$?
check "after a switch, continue names Setup" "$status:$out" "0:continue — 30k after compaction; regime normal; setup due: begin at the execution skill's Setup, worktree first"
ar --session s-1 phase execute 2>/dev/null; status=$?
check "phase execute in the primary checkout keeps setup due" "$status:$(field setupDue)" "4:true"
side --session s-1 phase execute
check "phase execute from a worktree settles Setup" "$(field setupDue)" "false"
check "status: no setup note once settled" "$(ar --session s-1 status | grep -c 'setup due')" "0"
ar --session s-1 switch
side --session s-1 task-complete; status=$?
check "task-complete in a worktree: exit 0, Setup settled" "$status:$(field setupDue):$(field active)" "0:false:true"
ar --session s-1 switch
ar --session s-1 phase final
check "phase final settles Setup" "$(field setupDue)" "false"
ar --session s-1 task-complete 2>"$TMP/err"; status=$?
check "task-complete in the primary checkout stops the run" "$status:$(field active):$(field stopped)" "5:false:a task was completed in the primary checkout"
check "task-complete in the primary checkout: says to end as Stopping says" "$(grep -c 'the run has stopped. End as reference/auto-run.md §Stopping says.' "$TMP/err")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run.test.sh`
Expected: the last line reads `123 passed, 12 failed`, and exactly these checks print `FAIL`:

- `phase execute in the primary checkout: exit 4, phase unchanged`
- `phase execute in the primary checkout: says to make the worktree`
- `start: setup is not due`
- `switch: setup is due`
- `status: says setup is due`
- `after a switch, continue names Setup`
- `phase execute in the primary checkout keeps setup due`
- `phase execute from a worktree settles Setup`
- `task-complete in a worktree: exit 0, Setup settled`
- `phase final settles Setup`
- `task-complete in the primary checkout stops the run`
- `task-complete in the primary checkout: says to end as Stopping says`

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/scripts/lib/auto-run.sh`, replace:

````
ar_primary_root() {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  git -C "$(dirname "$common")" rev-parse --show-toplevel 2>/dev/null || return 1
}
````

with:

````
ar_primary_root() {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  git -C "$(dirname "$common")" rev-parse --show-toplevel 2>/dev/null || return 1
}

# ar_in_primary — true in the primary checkout. An auto run's tasks run in a
# linked worktree (dforge:using-git-worktrees), so a task step here would land
# on the run's base.
ar_in_primary() {
  local dir common
  dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 1
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  [ "$dir" = "$common" ]
}
````

In `plugins/dforge/scripts/lib/auto-run.sh`, replace:

````
    failures: 0, compactions: 0, resumes: 0, decisions: [], rulings: []
````

with:

````
    failures: 0, compactions: 0, resumes: 0, decisions: [], rulings: [],
    setupDue: false, stalls: 0, stalledAt: null, compactionsSinceTask: 0
````

In `plugins/dforge/scripts/lib/auto-run.sh`, replace:

````
register \(.register)"'
}
````

with:

````
register \(.register)\(if .setupDue == true then " — setup due" else "" end)"'
}
````

In `plugins/dforge/scripts/lib/auto-run.sh`, replace:

````
ar_stop() { # ar_stop [REASON]
  ar_update '.active = false | .stopped = (if $r == "" then null else $r end) | .pending = null' --arg r "${1:-}"
}
````

with:

````
ar_stop() { # ar_stop [REASON]
  ar_update '.active = false | .stopped = (if $r == "" then null else $r end) | .pending = null' --arg r "${1:-}"
}

# ar_set_phase PHASE — refuses execute in the primary checkout (return 4): the
# execution worktree Setup makes is missing. execute and final settle Setup.
ar_set_phase() {
  if [ "$1" = execute ] && ar_in_primary; then
    echo "auto-run: this is the primary checkout; create the execution worktree first (dforge:using-git-worktrees), then run auto-run phase execute from it" >&2
    return 4
  fi
  ar_update '.phase = $p | if $p == "execute" or $p == "final" then .setupDue = false else . end' --arg p "$1"
}

# ar_task_complete — a task's complete line is written, so the progress counts
# start again. In the primary checkout that task ran on the run's base: the run
# stops (return 5) rather than finish there.
ar_task_complete() {
  if ar_in_primary; then
    ar_stop "a task was completed in the primary checkout" || return 1
    echo "auto-run: a task was completed in the primary checkout; the run has stopped. End as reference/auto-run.md §Stopping says." >&2
    return 5
  fi
  ar_update '.resumes = 0 | .stalls = 0 | .stalledAt = null | .compactionsSinceTask = 0 | .setupDue = false'
}
````

In `plugins/dforge/scripts/lib/auto-run.sh`, replace:

````
# execution's rules and an oversized one still hands off.
ar_switch() {
````

with:

````
# execution's rules and an oversized one still hands off. Setup is due until
# a phase execute from the execution worktree, a task-complete or phase final.
ar_switch() {
````

In `plugins/dforge/scripts/lib/auto-run.sh`, replace:

````
  ar_update '.pending = "switch" | .phase = "execute" | .resumePrompt = $p
````

with:

````
  ar_update '.pending = "switch" | .phase = "execute" | .setupDue = true | .compactionsSinceTask = 0 | .resumePrompt = $p
````

In `plugins/dforge/scripts/auto-run`, replace:

````
    bound; ar_update '.phase = $p' --arg p "$1"
    ;;
  task-complete) [ $# -eq 0 ] || usage; bound; ar_update '.resumes = 0' ;;
````

with:

````
    bound; ar_set_phase "$1"
    ;;
  task-complete) [ $# -eq 0 ] || usage; bound; ar_task_complete ;;
````

In `plugins/dforge/scripts/auto-run`, replace:

````
    if [ -z "$tokens" ]; then
      [ "$pending" != after-compact ] || ar_update '.pending = null' || exit 1
      echo "continue — the size after compaction is unknown; record that with auto-run ruling add, and Claude Code's own compaction stays the backstop"
````

with:

````
    due=""
    [ "$(ar_get setupDue)" != true ] || due="; setup due: begin at the execution skill's Setup, worktree first"
    if [ -z "$tokens" ]; then
      [ "$pending" != after-compact ] || ar_update '.pending = null' || exit 1
      echo "continue — the size after compaction is unknown; record that with auto-run ruling add, and Claude Code's own compaction stays the backstop$due"
````

In `plugins/dforge/scripts/auto-run`, replace:

````
    echo "$result — $(( (tokens + 500) / 1000 ))k after compaction; regime $regime"
````

with:

````
    [ "$result" = continue ] || due=""
    echo "$result — $(( (tokens + 500) / 1000 ))k after compaction; regime $regime$due"
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run.test.sh`
Expected: `135 passed, 0 failed`

- [ ] **Step 5: Run the suites that name the changed files**

Run each of these on its own line, and expect each to end `0 failed`:

- `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/budget-line.test.sh`
- `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/turn-end.test.sh`
- `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/context-size.test.sh`
- `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/final-phase.test.sh`

Then run `grep -l <basename> plugins/dforge/tests/*.sh` for each changed file's basename and run any other suite it lists the same way.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/auto-run plugins/dforge/scripts/lib/auto-run.sh plugins/dforge/tests/auto-run.test.sh
git commit -m "feat(dforge): guard execution to a worktree"
```

### Task 2: Auto-run cockpit heartbeat

**Files:**
- Modify: `plugins/dforge/scripts/lib/auto-run.sh`
- Test: `plugins/dforge/tests/auto-run.test.sh`
- Test: `plugins/dforge/tests/budget-line.test.sh`
- Test: `plugins/dforge/tests/turn-end.test.sh`
- Test: `plugins/dforge/tests/context-size.test.sh`

**Interfaces:**
- Consumes: C1 (`ar_start` from Task 1); the test helper `side` (C11).
- Produces: C4 (the heartbeat file and its 180-second freshness) and C3's `start` exit 2 (`auto-run: no live cockpit in this session`). This task adds C11's `beat` helper and heartbeat-writing `ar` wrapper.

**Items:** 26, 30

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

Every suite that runs `auto-run start` now writes the session's heartbeat first, as a live cockpit would; the three one-line inserts in `budget-line`, `turn-end` and `context-size` keep those suites green once `start` checks it. Their checks do not fail before the implementation: they prepare for it.

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/auto-run.test.sh`, replace:

````
ar() { (cd "$REPO" && bash "$AR" "$@"); }
````

with:

````
beat() { # beat <session> [age in seconds]: the heartbeat a live cockpit writes
  local f="$HOME/.claude/dforge/sessions/cockpit/$1"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$(( $(date +%s) - ${2:-0} ))" > "$f"
}
# Every call through ar has a live cockpit in the session it names.
ar() {
  [ "${1:-}" != --session ] || beat "$2"
  (cd "$REPO" && bash "$AR" "$@")
}
````

In `plugins/dforge/tests/auto-run.test.sh`, replace:

````
live s-1 '2 hours ago'
````

with:

````
live s-1 '2 hours ago'
beat s-1 7200
````

In `plugins/dforge/tests/auto-run.test.sh`, replace:

````
printf '{}\n' > "$HOME/.claude/projects/q/s-2.jsonl"
````

with:

````
printf '{}\n' > "$HOME/.claude/projects/q/s-2.jsonl"
rm -f "$HOME/.claude/dforge/sessions/cockpit/s-2"
````

In `plugins/dforge/tests/auto-run.test.sh`, replace:

````
check "--force replaces a live run" "$status:$(field session)" "0:s-1"
````

with:

````
check "--force replaces a live run" "$status:$(field session)" "0:s-1"

# --- a start needs a live cockpit in its session ---
(cd "$REPO" && bash "$AR" --session s-3 start --spec "$SPEC" --register docs/r.md --force >/dev/null 2>"$TMP/err"); status=$?
check "start without a cockpit heartbeat: exit 2, the run unchanged" "$status:$(field session)" "2:s-1"
check "start without a cockpit heartbeat: says why" "$(grep -c 'no live cockpit in this session' "$TMP/err")" "1"
beat s-3 181
(cd "$REPO" && bash "$AR" --session s-3 start --spec "$SPEC" --register docs/r.md --force >/dev/null 2>&1); status=$?
check "a heartbeat older than 180 seconds: exit 2" "$status:$(field session)" "2:s-1"
beat s-1 181
ar --session s-3 start --spec "$SPEC" --register docs/r.md >/dev/null 2>&1; status=$?
check "a run whose cockpit heartbeat is older than 180 seconds is stale" "$status:$(field session)" "0:s-3"
````

In `plugins/dforge/tests/auto-run.test.sh`, replace:

````
git -C "$REPO" worktree add -q -b side "$TMP/side"
````

with:

````
git -C "$REPO" worktree add -q -b side "$TMP/side"
beat s-5
````

In `plugins/dforge/tests/auto-run.test.sh`, replace:

````
git -C "$REPO" worktree add -q --detach "$TMP/loose"
````

with:

````
git -C "$REPO" worktree add -q --detach "$TMP/loose"
beat s-6
````

In `plugins/dforge/tests/budget-line.test.sh`, replace:

````
bash "$P/scripts/auto-run" --session s-1 start --spec docs/spec.md --register docs/reg.md >/dev/null
````

with:

````
mkdir -p "$HOME/.claude/dforge/sessions/cockpit"
date +%s > "$HOME/.claude/dforge/sessions/cockpit/s-1"
bash "$P/scripts/auto-run" --session s-1 start --spec docs/spec.md --register docs/reg.md >/dev/null
````

In `plugins/dforge/tests/turn-end.test.sh`, replace:

````
(cd "$REPO" && bash "$AR" --session s-1 start --spec docs/s.md --register docs/r.md >/dev/null)
````

with:

````
mkdir -p "$HOME/.claude/dforge/sessions/cockpit"
date +%s > "$HOME/.claude/dforge/sessions/cockpit/s-1"
(cd "$REPO" && bash "$AR" --session s-1 start --spec docs/s.md --register docs/r.md >/dev/null)
````

In `plugins/dforge/tests/context-size.test.sh`, replace:

````
(cd "$REPO" && bash "$HERE/../scripts/auto-run" --session auto-1 start --spec docs/s.md --register docs/r.md >/dev/null)
````

with:

````
mkdir -p "$HOME/.claude/dforge/sessions/cockpit"
date +%s > "$HOME/.claude/dforge/sessions/cockpit/auto-1"
(cd "$REPO" && bash "$HERE/../scripts/auto-run" --session auto-1 start --spec docs/s.md --register docs/r.md >/dev/null)
````

In `plugins/dforge/tests/context-size.test.sh`, replace:

````
(cd "$REPO" && bash "$HERE/../scripts/auto-run" --session auto-1 start --spec docs/s.md --register docs/r.md --force >/dev/null)
````

with:

````
date +%s > "$HOME/.claude/dforge/sessions/cockpit/auto-1"
(cd "$REPO" && bash "$HERE/../scripts/auto-run" --session auto-1 start --spec docs/s.md --register docs/r.md --force >/dev/null)
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run.test.sh`
Expected: the last line reads `136 passed, 3 failed`, and exactly these checks print `FAIL`:

- `start without a cockpit heartbeat: exit 2, the run unchanged`
- `start without a cockpit heartbeat: says why`
- `a heartbeat older than 180 seconds: exit 2`

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/budget-line.test.sh`
Expected: `41 passed, 0 failed` (this suite only prepares for the change, so nothing fails yet).

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/turn-end.test.sh`
Expected: `105 passed, 0 failed` (this suite only prepares for the change, so nothing fails yet).

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/context-size.test.sh`
Expected: `143 passed, 0 failed` (this suite only prepares for the change, so nothing fails yet).

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/scripts/lib/auto-run.sh`, replace:

````
AR_FAILURE_CAP=2
````

with:

````
AR_FAILURE_CAP=2
AR_BEAT_SECONDS=180
````

In `plugins/dforge/scripts/lib/auto-run.sh`, replace:

````
# ar_is_stale — true when the run's session has not written its transcript
# within AR_STALE_MINUTES, or has none: whoever owned the run is gone.
ar_is_stale() {
  local sid tp
  sid=$(ar_get session)
  [ -n "$sid" ] || return 0
  tp=$(ar_transcript "$sid") || return 0
  [ -n "$(find "$tp" -mmin +"$AR_STALE_MINUTES" 2>/dev/null)" ]
}
````

with:

````
# ar_beat_file SESSION — where the session's cockpit writes its heartbeat: the
# epoch seconds of its last beat.
ar_beat_file() {
  printf '%s/.claude/dforge/sessions/cockpit/%s\n' "${HOME:-}" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
}

# ar_beat_age SESSION — seconds since the session's cockpit last beat; fails
# when the file is missing or holds no number.
ar_beat_age() {
  local file beat
  file=$(ar_beat_file "$1")
  [ -f "$file" ] || return 1
  beat=$(head -n 1 "$file" | tr -dc '0-9')
  [ -n "$beat" ] || return 1
  echo $(( $(date +%s) - beat ))
}

# ar_is_stale — true when whoever owned the run is gone: its session's cockpit
# heartbeat is older than AR_BEAT_SECONDS, or, for a session with no heartbeat
# file, its transcript was not written within AR_STALE_MINUTES or it has none.
ar_is_stale() {
  local sid tp age
  sid=$(ar_get session)
  [ -n "$sid" ] || return 0
  if [ -f "$(ar_beat_file "$sid")" ]; then
    age=$(ar_beat_age "$sid") || return 0
    [ "$age" -gt "$AR_BEAT_SECONDS" ]
    return
  fi
  tp=$(ar_transcript "$sid") || return 0
  [ -n "$(find "$tp" -mmin +"$AR_STALE_MINUTES" 2>/dev/null)" ]
}
````

In `plugins/dforge/scripts/lib/auto-run.sh`, replace:

````
  local spec=$1 register=$2 force=$3 path top slug base tmp regfile
  path=$(ar_path) || { echo "auto-run: not inside a git repository" >&2; return 2; }
````

with:

````
  local spec=$1 register=$2 force=$3 path top slug base tmp regfile age
  path=$(ar_path) || { echo "auto-run: not inside a git repository" >&2; return 2; }
  # Nothing would compact, switch or wake the run without the cockpit.
  age=$(ar_beat_age "$AR_SESSION") && [ "$age" -le "$AR_BEAT_SECONDS" ] \
    || { echo "auto-run: no live cockpit in this session" >&2; return 2; }
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run.test.sh`
Expected: `139 passed, 0 failed`

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/budget-line.test.sh`
Expected: `41 passed, 0 failed`

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/turn-end.test.sh`
Expected: `105 passed, 0 failed`

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/context-size.test.sh`
Expected: `143 passed, 0 failed`

- [ ] **Step 5: Run the suites that name the changed files**

Run each of these on its own line, and expect each to end `0 failed`:

- `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/final-phase.test.sh`

Then run `grep -l <basename> plugins/dforge/tests/*.sh` for each changed file's basename and run any other suite it lists the same way.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/lib/auto-run.sh plugins/dforge/tests/auto-run.test.sh plugins/dforge/tests/budget-line.test.sh plugins/dforge/tests/context-size.test.sh plugins/dforge/tests/turn-end.test.sh
git commit -m "feat(dforge): require a live cockpit heartbeat"
```

### Task 3: Auto-run stalls and compaction cap

**Files:**
- Modify: `plugins/dforge/scripts/lib/auto-run.sh`
- Modify: `plugins/dforge/scripts/auto-run`
- Test: `plugins/dforge/tests/auto-run.test.sh`

**Interfaces:**
- Consumes: C1 and C3's `task-complete` (Task 1); the test helpers `side`, `beat` and `ar` (C11).
- Produces: C3's `stalled` command and `compacted` exit 5 at the cap, which the cockpit tasks consume.

**Items:** 26, 27

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/auto-run.test.sh`, replace:

````
printf '\n%d passed, %d failed\n' "$pass" "$fail"
````

with:

````
# --- progress caps: compactions and stalls without a completed task ---
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
ar --session s-1 attach --plan docs/plan.md
ar --session s-1 phase plan
ar --session s-1 compacted
ar --session s-1 compacted
ar --session s-1 compacted; status=$?
check "plan-phase compactions are not counted" "$status:$(field active):$(field compactionsSinceTask)" "0:true:0"
ar --session s-1 switch
ar --session s-1 compacted --switch
check "the switch's compaction is not counted" "$(field compactionsSinceTask)" "0"
ar --session s-1 resumed
side --session s-1 phase execute
ar --session s-1 compacted
ar --session s-1 compacted
check "two execute compactions: counted, the run goes on" "$(field compactionsSinceTask):$(field active)" "2:true"
side --session s-1 task-complete
check "task-complete resets the compaction count" "$(field compactionsSinceTask)" "0"
ar --session s-1 compacted
ar --session s-1 compacted
ar --session s-1 compacted; status=$?
check "the third execute compaction without a completed task stops the run" "$status:$(field active):$(field stopped)" "5:false:three compactions without a completed task"
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
before=$(date +%s)
ar --session s-1 stalled; status=$?
after_s=$(date +%s)
first=$(field stalledAt)
check "stalled: exit 0, counted" "$status:$(field stalls)" "0:1"
check "stalled: stalledAt is the epoch seconds of the call" "$([ "$first" -ge "$before" ] && [ "$first" -le "$after_s" ] && echo within || echo "outside $before..$after_s")" "within"
sleep 1
ar --session s-1 stalled
check "a later stall refreshes stalledAt" "$([ "$(field stalledAt)" -gt "$first" ] && echo later || echo same)" "later"
side --session s-1 task-complete
check "task-complete resets the stalls" "$(field stalls):$(field stalledAt)" "0:null"
ar --session s-1 stalled
ar --session s-1 stalled
ar --session s-1 stalled; status=$?
check "the third stall without a completed task stops the run" "$status:$(field active):$(field stopped)" "5:false:three stalls without a completed task"
ar --session s-1 stalled >/dev/null 2>&1; status=$?
check "stalled with no run bound: exit 3" "$status" "3"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run.test.sh`
Expected: the last line reads `143 passed, 7 failed`, and exactly these checks print `FAIL`:

- `two execute compactions: counted, the run goes on`
- `the third execute compaction without a completed task stops the run`
- `stalled: exit 0, counted`
- `stalled: stalledAt is the epoch seconds of the call`
- `a later stall refreshes stalledAt`
- `the third stall without a completed task stops the run`
- `stalled with no run bound: exit 3`

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/scripts/lib/auto-run.sh`, replace:

````
AR_FAILURE_CAP=2
````

with:

````
AR_FAILURE_CAP=2
AR_STALL_CAP=3
AR_COMPACTION_CAP=3
````

In `plugins/dforge/scripts/lib/auto-run.sh`, replace:

````
# ar_compacted [--switch] — book a compaction; the switch's own leaves its
# resume stage due. One in the final or finish phase sets finalCompacted, after
# which every budget line of the run says ok.
ar_compacted() {
  local next=after-compact
  [ "${1:-}" = --switch ] && next=switch-resume
  ar_update '.compactions += 1 | .failures = 0 | .pending = $n
    | .finalCompacted = ((.finalCompacted // false) or .phase == "final" or .phase == "finish")' --arg n "$next"
}
````

with:

````
# ar_compacted [--switch] — book a compaction; the switch's own leaves its
# resume stage due. One in the final or finish phase sets finalCompacted, after
# which every budget line of the run says ok. An execute-phase compaction other
# than the switch's counts toward AR_COMPACTION_CAP, reached without a
# completed task, which stops the run (return 5): a task that cannot fit in a
# window would otherwise loop.
ar_compacted() {
  local next=after-compact n
  [ "${1:-}" = --switch ] && next=switch-resume
  ar_update '.compactions += 1 | .failures = 0 | .pending = $n
    | .finalCompacted = ((.finalCompacted // false) or .phase == "final" or .phase == "finish")
    | if $n == "after-compact" and .phase == "execute"
      then .compactionsSinceTask = ((.compactionsSinceTask // 0) + 1) else . end' --arg n "$next" || return 1
  [ "$next" = after-compact ] || return 0
  n=$(ar_get compactionsSinceTask)
  if [ "${n:-0}" -ge "$AR_COMPACTION_CAP" ]; then
    ar_stop "three compactions without a completed task" || return 1
    return 5
  fi
}
````

In `plugins/dforge/scripts/lib/auto-run.sh`, replace:

````
ar_decision_add() { # ar_decision_add ID QUESTION OPTIONS REASON TASK
````

with:

````
# ar_stalled — the cockpit found the run idle with no sentinel answered, and
# nudged it. The AR_STALL_CAP-th since the last completed task stops the run
# (return 5).
ar_stalled() {
  local n
  ar_update '.stalls = ((.stalls // 0) + 1) | .stalledAt = $now' --argjson now "$(date +%s)" || return 1
  n=$(ar_get stalls)
  if [ "${n:-0}" -ge "$AR_STALL_CAP" ]; then
    ar_stop "three stalls without a completed task" || return 1
    return 5
  fi
}

ar_decision_add() { # ar_decision_add ID QUESTION OPTIONS REASON TASK
````

In `plugins/dforge/scripts/auto-run`, replace:

````
       auto-run [--session ID] status | pending | task-complete | resumed | switch
````

with:

````
       auto-run [--session ID] status | pending | task-complete | resumed | switch | stalled
````

In `plugins/dforge/scripts/auto-run`, replace:

````
  task-complete) [ $# -eq 0 ] || usage; bound; ar_task_complete ;;
````

with:

````
  task-complete) [ $# -eq 0 ] || usage; bound; ar_task_complete ;;
  stalled) [ $# -eq 0 ] || usage; bound; ar_stalled ;;
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run.test.sh`
Expected: `150 passed, 0 failed`

- [ ] **Step 5: Run the suites that name the changed files**

Run each of these on its own line, and expect each to end `0 failed`:

- `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/budget-line.test.sh`
- `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/turn-end.test.sh`
- `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/context-size.test.sh`
- `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/final-phase.test.sh`

Then run `grep -l <basename> plugins/dforge/tests/*.sh` for each changed file's basename and run any other suite it lists the same way.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/auto-run plugins/dforge/scripts/lib/auto-run.sh plugins/dforge/tests/auto-run.test.sh
git commit -m "feat(dforge): cap stalls and compactions"
```

### Task 4: context-size --final enters the final phase

**Files:**
- Modify: `plugins/dforge/scripts/lib/auto-run.sh`
- Modify: `plugins/dforge/scripts/lib/context.sh`
- Test: `plugins/dforge/tests/context-size.test.sh`

**Interfaces:**
- Consumes: C1 (`setupDue`) and C3's phases (Task 1); the heartbeat (Task 2) for the suite's `start`.
- Produces: C5.

**Items:** 16

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

`scripts/lib/auto-run.sh` now sources `plan.sh` (which sources `roots.sh`, the line it replaces), so every script that loads `context.sh` also loads the plan readers; no function name collides (checked 2026-10-19), and every shell suite stayed green in a dry run.

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/context-size.test.sh`, replace:

````
(cd "$REPO" && bash "$HERE/../scripts/auto-run" --session auto-1 stop)
unset DFORGE_BUDGET CLAUDE_CODE_SESSION_ID
````

with:

````
# --- --final after the last task's complete line starts the final phase ---
date +%s > "$HOME/.claude/dforge/sessions/cockpit/auto-1"
(cd "$REPO" && bash "$HERE/../scripts/auto-run" --session auto-1 start --spec docs/s.md --register docs/r.md --force >/dev/null)
mkdir -p "$REPO/docs/plans" "$REPO/.dforge/sdd/fp"
printf '# FP\n\n### Task 1: One\n\n### Task 2: Two\n' > "$REPO/docs/plans/fp.md"
printf '# SDD ledger — plan: docs/plans/fp.md\nTask 1: complete (commits a..b, review clean)\n' > "$REPO/.dforge/sdd/fp/progress.md"
(cd "$REPO" && bash "$HERE/../scripts/auto-run" --session auto-1 attach --plan docs/plans/fp.md)
jq '.phase = "execute" | .setupDue = true' "$AUTO_STATE" > "$AUTO_STATE.tmp" && mv "$AUTO_STATE.tmp" "$AUTO_STATE"
asst 300000 > "$AUTO_T"
run --final
check "--final with a task still open: the phase stays execute" "$(jq -r .phase "$AUTO_STATE")" "execute"
printf 'Task 2: complete (commits b..c, review clean)\n' >> "$REPO/.dforge/sdd/fp/progress.md"
run
check "a task budget check never starts the final phase" "$(jq -r .phase "$AUTO_STATE")" "execute"
run --final
check "--final after the last task: the phase moves to final" "$status:$(jq -r '"\(.phase) \(.setupDue)"' "$AUTO_STATE")" "0:final false"
(cd "$REPO" && bash "$HERE/../scripts/auto-run" --session auto-1 stop)
unset DFORGE_BUDGET CLAUDE_CODE_SESSION_ID
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/context-size.test.sh`
Expected: the last line reads `145 passed, 1 failed`, and exactly these checks print `FAIL`:

- `--final after the last task: the phase moves to final`

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/scripts/lib/auto-run.sh`, replace:

````
. "$(dirname "${BASH_SOURCE[0]}")/roots.sh"
````

with:

````
# plan.sh brings roots.sh, and the plan and ledger readers ar_enter_final uses.
. "$(dirname "${BASH_SOURCE[0]}")/plan.sh"
````

In `plugins/dforge/scripts/lib/auto-run.sh`, replace:

````
# ar_task_complete — a task's complete line is written, so the progress counts
````

with:

````
# ar_enter_final — in the execute phase, once the attached plan's ledger has a
# complete line for every task, move the run to the final phase, so the check
# after the last task is measured where no compaction hands off.
ar_enter_final() {
  local plan ledger tasks
  [ "$(ar_get phase)" = execute ] || return 0
  plan=$(ar_get plan)
  [ -n "$plan" ] || return 0
  plan=$(plan_locate "$plan")
  [ -f "$plan" ] || return 0
  ledger=$(plan_ledger "$plan")
  [ -n "$ledger" ] || return 0
  tasks=$(plan_tasks "$plan" | cut -f1 | sort -u)
  [ -n "$tasks" ] || return 0
  [ -z "$(comm -23 <(printf '%s\n' "$tasks") <(ledger_done "$ledger" | sort -u))" ] || return 0
  ar_update '.phase = "final" | .setupDue = false'
}

# ar_task_complete — a task's complete line is written, so the progress counts
````

In `plugins/dforge/scripts/lib/context.sh`, replace:

````
    if ar_bound; then
      auto=1
      label=$(ctx_auto_label normal "$width")
    fi
````

with:

````
    if ar_bound; then
      auto=1
      # The check after the last task's complete line starts the final phase.
      [ "${1:-}" != final ] || ar_enter_final || true
      label=$(ctx_auto_label normal "$width")
    fi
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/context-size.test.sh`
Expected: `146 passed, 0 failed`

- [ ] **Step 5: Run the suites that name the changed files**

Run each of these on its own line, and expect each to end `0 failed`:

- `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run.test.sh`
- `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/budget-line.test.sh`
- `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/turn-end.test.sh`
- `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/final-phase.test.sh`
- `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/in-flight.test.sh`
- `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/hook.test.sh`

Then run `grep -l <basename> plugins/dforge/tests/*.sh` for each changed file's basename and run any other suite it lists the same way.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/lib/auto-run.sh plugins/dforge/scripts/lib/context.sh plugins/dforge/tests/context-size.test.sh
git commit -m "fix(dforge): enter the final phase at --final"
```

### Task 5: Stop hook holds without a stamp

**Files:**
- Modify: `plugins/dforge/scripts/turn-end.sh`
- Test: `plugins/dforge/tests/turn-end.test.sh`

**Interfaces:**
- Consumes: C4 (the suite writes the session's heartbeat before `start`, Task 2).
- Produces: nothing another task consumes: the Stop hook holds a bound run's turn whether or not a turn stamp exists.

**Items:** 26, 29

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

The existing pin `unstamped session: passes` stays: no run is bound to that session. The unwritable count is provoked by making the stamp directory's path a regular file, which fails for root too (the suites run as root here).

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/turn-end.test.sh`, replace:

````
check "a stopped run: back to the plain rules" "$(stop s-1 'Here is the answer.')" ""
````

with:

````
check "a stopped run: back to the plain rules" "$(stop s-1 'Here is the answer.')" ""

# --- an auto run holds a session that has no turn stamp ---
date +%s > "$HOME/.claude/dforge/sessions/cockpit/s-5"
(cd "$REPO" && bash "$AR" --session s-5 start --spec docs/s.md --register docs/r.md --force >/dev/null)
check "no stamp and no run bound: passes" "$(stop s-other 'Done.')" ""
out=$(stop s-5 'Done.')
check "auto run without a turn stamp: held" "$(decision "$out")" "block"
check "auto run without a turn stamp: the count is kept" "$(cat "$HOME/.claude/dforge/sessions/turns/s-5.holds")" "1"
H2="$TMP/home-turns-is-a-file"
mkdir -p "$H2/.claude/dforge/sessions"
printf 'not a directory\n' > "$H2/.claude/dforge/sessions/turns"
out=$(HOME="$H2" stop s-5 'Done.' true)
check "a hold count that cannot be written: the run stops" "$(jq -r .active "$STATE"):$(jq -r .stopped "$STATE" | grep -c 'without its sentinel')" "false:1"
check "a hold count that cannot be written: one hold asks for the attended ending" "$(jq -r .reason <<<"$out" | grep -c '§Stopping')" "1"
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/turn-end.test.sh`
Expected: the last line reads `106 passed, 4 failed`, and exactly these checks print `FAIL`:

- `auto run without a turn stamp: held`
- `auto run without a turn stamp: the count is kept`
- `a hold count that cannot be written: the run stops`
- `a hold count that cannot be written: one hold asks for the attended ending`

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/scripts/turn-end.sh`, replace:

````
stamp="${HOME:-}/.claude/dforge/sessions/turns/$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9' '-')"
[ -f "$stamp" ] || exit 0
root=$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || exit 0
. "${SCRIPT_DIR}/lib/roots.sh"
# In a subshell, so a malformed config costs only this check, never the hook.
sdd=$(dforge_ledger_root "$root") || sdd=""
# An auto run bound to this session (reference/auto-run.md) lives in the
# primary checkout, whichever worktree the turn ran in: its pending action.
auto_pending=$(cd "${cwd:-$PWD}" 2>/dev/null && bash "${SCRIPT_DIR}/auto-run" --session "$session_id" pending 2>/dev/null) || auto_pending=""
````

with:

````
stamp="${HOME:-}/.claude/dforge/sessions/turns/$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9' '-')"
# An auto run bound to this session (reference/auto-run.md) lives in the
# primary checkout, whichever worktree the turn ran in: its pending action. It
# is read before the stamp gate, so a session with no stamp (a cleared one,
# whose first prompt the cockpit submitted) is still held.
auto_pending=$(cd "${cwd:-$PWD}" 2>/dev/null && bash "${SCRIPT_DIR}/auto-run" --session "$session_id" pending 2>/dev/null) || auto_pending=""
[ -f "$stamp" ] || [ -n "$auto_pending" ] || exit 0
root=$(git -C "${cwd:-$PWD}" rev-parse --show-toplevel 2>/dev/null) || exit 0
. "${SCRIPT_DIR}/lib/roots.sh"
# In a subshell, so a malformed config costs only this check, never the hook.
sdd=$(dforge_ledger_root "$root") || sdd=""
````

In `plugins/dforge/scripts/turn-end.sh`, replace:

````
  holds=$((holds + 1))
  if [ "$holds" -gt "$AUTO_HOLD_CAP" ]; then
    rm -f "$stamp.holds"
````

with:

````
  holds=$((holds + 1))
  # A count that cannot be kept would hold forever: treat it as the cap.
  if ! { mkdir -p "$(dirname "$stamp")" && printf '%s\n' "$holds" > "$stamp.holds"; } 2>/dev/null; then
    holds=$((AUTO_HOLD_CAP + 1))
  fi
  if [ "$holds" -gt "$AUTO_HOLD_CAP" ]; then
    rm -f "$stamp.holds" 2>/dev/null
````

In `plugins/dforge/scripts/turn-end.sh`, delete this line:

````
  printf '%s\n' "$holds" > "$stamp.holds" 2>/dev/null || true
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/turn-end.test.sh`
Expected: `110 passed, 0 failed`

- [ ] **Step 5: Run the suites that name the changed files**

Run each of these on its own line, and expect each to end `0 failed`:

- `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/hook.test.sh`

Then run `grep -l <basename> plugins/dforge/tests/*.sh` for each changed file's basename and run any other suite it lists the same way.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/turn-end.sh plugins/dforge/tests/turn-end.test.sh
git commit -m "fix(dforge): hold auto runs without a stamp"
```

### Task 6: next-step names Setup on a cold start

**Files:**
- Modify: `plugins/dforge/scripts/next-step`
- Test: `plugins/dforge/tests/next-step.test.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: C6.

**Items:** 13

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

Only the first prompt changes: the `**Next:**` line and its pins stay `Start at Task <N> (<title>).`

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/next-step.test.sh`, replace:

````
has "not started: prompt names the sdd skill" "$out" "Continue \`$PLAN_REL\` with dforge:subagent-driven-development. Start at Task 1 (First thing)."
````

with:

````
has "not started: prompt names the sdd skill and Setup" "$out" "Continue \`$PLAN_REL\` with dforge:subagent-driven-development. No ledger exists yet: begin at the skill's Setup, worktree first; the first task is Task 1 (First thing)."
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/next-step.test.sh`
Expected: the last line reads `174 passed, 1 failed`, and exactly these checks print `FAIL`:

- `not started: prompt names the sdd skill and Setup`

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/scripts/next-step`, replace:

````
    # With a ledger there is state to verify before continuing, which is
    # resume-execution's job; without one the plan simply starts.
````

with:

````
    # With a ledger there is state to verify before continuing, which is
    # resume-execution's job; without one the plan starts at the skill's Setup,
    # which a session that arrives through a compaction would otherwise skip.
````

In `plugins/dforge/scripts/next-step`, replace:

````
      prompt="Continue \`$rel\` with dforge:$skill. $next_line"
````

with:

````
      prompt="Continue \`$rel\` with dforge:$skill. No ledger exists yet: begin at the skill's Setup, worktree first; the first task is Task $first_open ($open_title)."
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/next-step.test.sh`
Expected: `175 passed, 0 failed`

- [ ] **Step 5: Run the suites that name the changed files**

Run each of these on its own line, and expect each to end `0 failed`:

- `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run.test.sh`

Then run `grep -l <basename> plugins/dforge/tests/*.sh` for each changed file's basename and run any other suite it lists the same way.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/next-step plugins/dforge/tests/next-step.test.sh
git commit -m "fix(dforge): name Setup in the cold-start prompt"
```

### Task 7: finish-choice reads the spec's Finish line

**Files:**
- Modify: `plugins/dforge/scripts/finish-choice`
- Test: `plugins/dforge/tests/finish-choice.test.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks (`plan.sh` and `roots.sh` exist today).
- Produces: C7.

**Items:** 14

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/finish-choice.test.sh`, replace:

````
rm -f "$HOME/.dforge/config.json"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
````

with:

````
rm -f "$HOME/.dforge/config.json"

# --- the spec's Finish line, which the spec review writes ---
mkdir -p docs/specs
spec_plan() { # spec_plan <name> <spec text> [Spec line value]: a plan citing its spec
  printf '%s' "$2" > "docs/specs/$1.md"
  printf '# Plan\n\n**Spec:** %s\n\n### Task 1: One\n' "${3:-\`docs/specs/$1.md\`}" > "docs/plans/$1.md"
}
spec_plan bare $'# S\n\n## Decisions\n\n1. Finish: "Ask at spec review" — the owner\'s words\n\nFinish: keep\n\n## Problem\n'
printf '{"finishAction":"merge"}\n' > "$HOME/.dforge/config.json"
out=$(FINISH_CHOICE_NOW=$T0 fc get --plan docs/plans/bare.md); status=$?
check "spec line: get exits 0" "$status" "0"
check "spec line: outranks the setting, recorded with its source" \
  "$(jq -r '[.action, (.base | tostring), .source, (.chosenAt | tostring)] | join(" ")' .dforge/sdd/bare/finish.json)" "keep null spec $T0"
has "spec line: get prints the choice" "$out" '"action": "keep"'
rm -f "$HOME/.dforge/config.json"
for pair in 'dash:-' 'star:*' 'number:6.'; do
  name="marker-${pair%%:*}" marker=${pair#*:}
  spec_plan "$name" "# S"$'\n\n'"## Decisions"$'\n\n'"$marker Finish: pr"$'\n'
  check "spec line after a '$marker' marker: a fresh record" "$([ -e ".dforge/sdd/$name/finish.json" ] && echo exists || echo none)" "none"
  check "spec line after a '$marker' marker" "$(fc get --plan "docs/plans/$name.md" | jq -r '[.action, .source] | join(" ")')" "pr spec"
  check "spec line after a '$marker' marker: recorded in its own workspace" "$(jq -r .source ".dforge/sdd/$name/finish.json")" "spec"
done
{ printf '# S\n\n## Decisions\n\nFinish: keep\n\n## Problem\n\n'; seq 1 200000 | sed 's/^/filler line /'; } > docs/specs/large.md
printf '# Plan\n\n**Spec:** `docs/specs/large.md`\n\n### Task 1: One\n' > docs/plans/large.md
out=$(fc get --plan docs/plans/large.md); status=$?
check "a long spec: the line is read and recorded" "$status:$(jq -r '[.action, .source] | join(" ")' <<<"$out")" "0:keep spec"
spec_plan crlf $'# S\r\n\r\n## Decisions\r\n\r\nFinish: merge\r\n'
check "spec line: CRLF line endings" "$(fc get --plan docs/plans/crlf.md | jq -r .action)" "merge"
spec_plan plain 'plain text'
fc set merge --plan docs/plans/plain.md >/dev/null
printf '# S\n\n## Decisions\n\nFinish: keep\n' > docs/specs/plain.md
check "a recorded choice outranks the spec line" "$(fc get --plan docs/plans/plain.md | jq -r '[.action, (.source // "asked")] | join(" ")')" "merge asked"
spec_plan none $'# S\n\n## Decisions\n\n1. Keep it small.\n'
fc get --plan docs/plans/none.md >/dev/null 2>&1
check "no spec line, setting ask: exit 3" "$?" "3"
printf '{"finishAction":"pr"}\n' > "$HOME/.dforge/config.json"
check "no spec line: the setting stands in" "$(fc get --plan docs/plans/none.md | jq -r '[.action, .source] | join(" ")')" "pr setting"
rm -f "$HOME/.dforge/config.json"
mkdir -p docs/dforge/specs
printf '# S\n\n## Decisions\n\nFinish: keep\n' > docs/dforge/specs/legacy.md
printf '# Plan\n\n**Spec:** docs/superpowers/specs/legacy.md\n\n### Task 1: One\n' > docs/plans/legacy.md
check "a spec cited under the pre-4.0 prefix is found" "$(fc get --plan docs/plans/legacy.md | jq -r '[.action, .source] | join(" ")')" "keep spec"
for case in outside fenced worded quoted; do
  case $case in
    outside) text=$'# S\n\n## Decisions\n\n1. Small.\n\n## Problem\n\nFinish: keep\n' ;;
    fenced) text=$'# S\n\n## Decisions\n\n```\nFinish: keep\n```\n' ;;
    worded) text=$'# S\n\n## Decisions\n\nFinish: keep it for review\n' ;;
    quoted) text=$'# S\n\n## Decisions\n\n3. Finish: "Ask at spec review"\n' ;;
  esac
  spec_plan "not-$case" "$text"
  fc get --plan "docs/plans/not-$case.md" >/dev/null 2>&1
  check "a Finish line $case is not read" "$?" "3"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/finish-choice.test.sh`
Expected: the last line reads `32 passed, 11 failed`, and exactly these checks print `FAIL`:

- `spec line: outranks the setting, recorded with its source`
- `spec line: get prints the choice`
- `spec line after a '-' marker`
- `spec line after a '-' marker: recorded in its own workspace`
- `spec line after a '*' marker`
- `spec line after a '*' marker: recorded in its own workspace`
- `spec line after a '6.' marker`
- `spec line after a '6.' marker: recorded in its own workspace`
- `a long spec: the line is read and recorded`
- `spec line: CRLF line endings`
- `a spec cited under the pre-4.0 prefix is found`

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/scripts/finish-choice`, replace:

````
#   get                         print the file; exit 3 when nothing is chosen.
#                               With nothing chosen and the finishAction setting
#                               at anything but ask, record that action first.
````

with:

````
#   get                         print the file; exit 3 when nothing is chosen.
#                               With nothing chosen, record first the plan's
#                               spec's `Finish:` line in ## Decisions (with
#                               --plan), else the finishAction setting when it
#                               is anything but ask.
````

In `plugins/dforge/scripts/finish-choice`, replace:

````
. "$HERE/lib/dforge-dir.sh"
. "$HERE/lib/dforge-env.sh"
````

with:

````
. "$HERE/lib/dforge-dir.sh"
. "$HERE/lib/dforge-env.sh"
. "$HERE/lib/plan.sh"
````

In `plugins/dforge/scripts/finish-choice`, replace:

````
case $cmd in
  set)
````

with:

````
# The spec review records its answer as a `Finish: <merge|pr|keep>` line in the
# spec's ## Decisions; a list marker may precede it. Fenced lines, other
# sections and any other value are not read. With nothing chosen it stands in
# for the answer, ahead of the setting: the owner gave it for this plan. awk
# reads to the end after a match: an early exit would end tr with SIGPIPE,
# which pipefail turns into this script's exit.
spec_finish() { # spec_finish SPEC_FILE — the line's action, or nothing
  tr -d '\r' < "$1" | awk "$_PLAN_AWK"'
    in_fence($0) { next }
    /^## / { inside = ($0 ~ /^## Decisions[ \t]*$/); next }
    found { next }
    inside && $0 ~ /^([-*]|[0-9]+\.)?[ \t]*Finish:[ \t]*(merge|pr|keep)[ \t]*$/ {
      v = $0
      sub(/^([-*]|[0-9]+\.)?[ \t]*Finish:[ \t]*/, "", v)
      sub(/[ \t]+$/, "", v)
      print v
      found = 1
    }
  '
}
from_spec() {
  [ -n "$plan" ] && [ ! -s "$file" ] || return 0
  local located name spec action
  located=$(plan_locate "$plan")
  [ -f "$located" ] || return 0
  name=$(plan_header_line "$located" Spec | sed -E 's/^\*\*Spec:\*\*[ \t]*(`([^`]+)`|([^ \t]+)).*/\2\3/')
  [ -n "$name" ] || return 0
  spec=$(dforge_resolve "$name") || return 0
  [ -f "$spec" ] || return 0
  action=$(spec_finish "$spec")
  [ -n "$action" ] || return 0
  jq -n --arg action "$action" --argjson now "$now" \
    '{action: $action, base: null, chosenAt: $now, source: "spec"}' > "$file"
}

case $cmd in
  set)
````

In `plugins/dforge/scripts/finish-choice`, replace:

````
  get)
    from_setting
````

with:

````
  get)
    from_spec
    from_setting
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/finish-choice.test.sh`
Expected: `43 passed, 0 failed`

- [ ] **Step 5: Run the suites that name the changed files**

Run each of these on its own line, and expect each to end `0 failed`:

- `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/final-phase.test.sh`

Then run `grep -l <basename> plugins/dforge/tests/*.sh` for each changed file's basename and run any other suite it lists the same way.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/finish-choice plugins/dforge/tests/finish-choice.test.sh
git commit -m "fix(dforge): read the spec's Finish line"
```

### Task 8: dforge-path ledger takes a plan path

**Files:**
- Modify: `plugins/dforge/scripts/dforge-path`
- Test: `plugins/dforge/tests/dforge-dir.test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: C8.

**Items:** 15

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

The test goes in `tests/dforge-dir.test.sh`, beside the existing `dforge-path: ledger, local` check: that suite is the one that runs the `dforge-path` script (`tests/roots.test.sh` sources `roots.sh` directly).

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/dforge-dir.test.sh`, replace:

````
check "dforge-path: ledger, local" "$(cd "$G" && HOME=$H bash "$FP" ledger p1)" "$TOP/.dforge/sdd/p1"
````

with:

````
check "dforge-path: ledger, local" "$(cd "$G" && HOME=$H bash "$FP" ledger p1)" "$TOP/.dforge/sdd/p1"
check "dforge-path: ledger of a plan path" "$(cd "$G" && HOME=$H bash "$FP" ledger docs/dforge/plans/2026-10-19-greet.md)" "$TOP/.dforge/sdd/2026-10-19-greet"
check "dforge-path: ledger of a backslashed plan path" "$(cd "$G" && HOME=$H bash "$FP" ledger 'docs\dforge\plans\2026-10-19-greet.md')" "$TOP/.dforge/sdd/2026-10-19-greet"
check "dforge-path: ledger of a bare plan file name" "$(cd "$G" && HOME=$H bash "$FP" ledger 2026-10-19-greet.md)" "$TOP/.dforge/sdd/2026-10-19-greet"
````

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/dforge-dir.test.sh`
Expected: the last line reads `38 passed, 3 failed`, and exactly these checks print `FAIL`:

- `dforge-path: ledger of a plan path`
- `dforge-path: ledger of a backslashed plan path`
- `dforge-path: ledger of a bare plan file name`

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/scripts/dforge-path`, replace:

````
# dforge-path state [RELATIVE] | docs [RELATIVE] | ledger SLUG | latest | store | name PATH | project
````

with:

````
# dforge-path state [RELATIVE] | docs [RELATIVE] | ledger SLUG|PLAN_FILE | latest | store | name PATH | project
````

In `plugins/dforge/scripts/dforge-path`, replace:

````
usage() { echo "usage: dforge-path state|docs [RELATIVE] | ledger SLUG | latest | store | name PATH | project" >&2; exit 2; }
````

with:

````
usage() { echo "usage: dforge-path state|docs [RELATIVE] | ledger SLUG|PLAN_FILE | latest | store | name PATH | project" >&2; exit 2; }
````

In `plugins/dforge/scripts/dforge-path`, replace:

````
  ledger) [ $# -eq 2 ] || usage; dforge_ledger_dir "$2"; exit 0 ;;
````

with:

````
  ledger)
    [ $# -eq 2 ] || usage
    # A plan path names the same ledger as its basename (sdd-workspace's rule).
    slug=${2//\\//}
    case $slug in */* | *.md) slug=$(basename "$slug" .md) ;; esac
    dforge_ledger_dir "$slug"
    exit 0
    ;;
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/dforge-dir.test.sh`
Expected: `41 passed, 0 failed`

- [ ] **Step 5: Run the suites that name the changed files**

Run each of these on its own line, and expect each to end `0 failed`:

- `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/roots.test.sh`

Then run `grep -l <basename> plugins/dforge/tests/*.sh` for each changed file's basename and run any other suite it lists the same way.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/dforge-path plugins/dforge/tests/dforge-dir.test.sh
git commit -m "fix(dforge): accept a plan path for the ledger"
```

### Task 9: Cockpit switch, compaction and restore guards

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx` (`AUTO_SWITCH_INSTRUCTIONS` at about line 126; `autoAct`'s compact stage and the `/model`-`/effort` block at about lines 2345-2400; the comment above `restoreUserDefaults` at about line 2430; `bookAutoCompaction` at about line 2469)
- Test: `plugins/dforge/tests/cockpit.test.ts` (the `World` type at about line 250, `settings.read` at about line 275, the fake `auto-run` and `process.run` at about lines 325-390, and a new block of tests above `reads a run only for its session` at about line 3771)

**Interfaces:**
- Consumes: C3 — `auto-run compacted` exits 5 when it stops the run with the reason `three compactions without a completed task`.
- Produces: nothing another task consumes. The switch compaction's instructions gain the sentence spec §A.2 names; the cockpit runs `node --version` through `$.process.run` before `/model` and `/effort`.

**Items:** 13, 27, 28

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

Covers spec A2, the cockpit part of A26, and A27.

- [ ] **Step 1: Write the failing tests**

The fake world learns a missing node, unreadable user settings and the script's compaction-cap stop; eight tests follow.

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
  /** The agent ids the spawns get, in turn; `agent-1` once they run out. */
  agentIds?: string[]
}
```

with:

```ts
  /** The agent ids the spawns get, in turn; `agent-1` once they run out. */
  agentIds?: string[]
  /** `node --version` cannot start, as on a machine without node. */
  isNodeMissing?: boolean
  /** Reading the user settings rejects. */
  isUserSettingsUnreadable?: boolean
}
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
  on('settings.read', (_$, e) => ({ value: e?.source === 'user' && w.userSettings !== undefined ? w.userSettings : (w.settings ?? {}) }))
```

with:

```ts
  on('settings.read', (_$, e) => {
    if (e?.source === 'user' && w.isUserSettingsUnreadable) throw new Error('EACCES: the user settings cannot be read')
    return { value: e?.source === 'user' && w.userSettings !== undefined ? w.userSettings : (w.settings ?? {}) }
  })
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
        if (exitCode === 5 && word === 'failure') Object.assign(state, { active: false, stopped: 'the cockpit could not compact twice', pending: null })
```

with:

```ts
        if (exitCode === 5 && word === 'failure') Object.assign(state, { active: false, stopped: 'the cockpit could not compact twice', pending: null })
        if (exitCode === 5 && word === 'compacted') Object.assign(state, { active: false, stopped: 'three compactions without a completed task', pending: null })
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
    const stdout = argv === 'hostname' ? 'devbox\n' : argv.startsWith('git rev-parse')
```

with:

```ts
    if (argv === 'node --version') {
      if (w.isNodeMissing) return { deny: 'dforge: $.process.run(node) failed to start: ENOENT: Executable not found in $PATH: "node"' }
      return { value: { exitCode: 0, stdout: 'v24.18.0\n', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    }
    const stdout = argv === 'hostname' ? 'devbox\n' : argv.startsWith('git rev-parse')
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
  test('reads a run only for its session, and its sentinel only as the last line', () => {
```

with:

```ts
  test('says at the switch that execution begins at Setup', async ($, on) => {
    const files = autoFiles({ phase: 'execute', pending: 'switch', resumePrompt: 'Continue `docs/plan.md`.', launch: null })
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Plan saved.\n\nAuto run: switching', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.compacts?.[0]).toMatch(/No task has started and no execution worktree exists yet; execution begins at the execution skill's Setup\./)
  })

  test('ends the run when its compaction reaches the cap', async ($, on) => {
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO], autoRunExits: { compacted: 5 } }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.prompts).toEqual(['The auto run stopped: three compactions without a completed task. End as reference/auto-run.md §Stopping says.'])
    expect(w.autoRuns?.some(call => call.includes(' stop '))).toBe(false)
  })

  test('ends the run when an engine compaction reaches the cap', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO], autoRunExits: { compacted: 5 } }
    world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.session.compact({ trigger: 'auto', messages: [SUMMARY] })
    expect(w.autoRuns).toContain('--session sess-1 compacted')
    expect(w.prompts).toEqual(['The auto run stopped: three compactions without a completed task. End as reference/auto-run.md §Stopping says.'])
  })

  for (const pending of ['handoff', 'compact']) {
    test(`books no engine compaction over a pending ${pending}`, async ($, on) => {
      const w: World = { ...SIGNED_IN, autoRuns: [] }
      world(on, w)
      signedIn(on, autoFiles({ pending }))
      await $.session.start(START)
      await $.session.compact({ trigger: 'auto', messages: [SUMMARY] })
      expect(w.autoRuns).toEqual([])
    })
  }

  for (const [why, flag] of [['node cannot run the restore', { isNodeMissing: true }], ['the user settings cannot be read', { isUserSettingsUnreadable: true }]] as const) {
    test(`runs neither /model nor /effort when ${why}`, async ($, on) => {
      const files = autoFiles({ pending: 'clear', resumePrompt: 'Execute docs/plan.md.', launch: { model: 'sonnet', effort: 'high' } })
      const w: World = { ...SIGNED_IN, commands: [], autoRuns: [], prompts: [], runs: [], userSettings: { model: 'opus[1m]' }, ...flag, autoFile: files[AUTO] }
      const clock = world(on, w)
      signedIn(on, files)
      await $.session.start(START)
      await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
      await settle(clock)
      expect(w.commands).toEqual(['/clear'])
      expect(w.userSettings).toEqual({ model: 'opus[1m]' })
      expect(w.runs?.filter(run => run.includes(' claude-restore '))).toEqual([])
      expect(w.prompts).toHaveLength(1)
      expect(w.prompts?.[0]).toMatch(/^Execute docs\/plan\.md\./)
      expect(w.prompts?.[0]).toMatch(/kept this session on .+ because it could not put back your default model afterwards\. Record that with scripts\/auto-run ruling add\./)
    })
  }

  test('sends a blocked notice naming the settings file when the defaults cannot be put back', async ($, on) => {
    const fetches: World['fetches'] = []
    const files = autoFiles({ pending: 'clear', resumePrompt: 'Execute docs/plan.md.', launch: { model: 'sonnet', effort: 'high' } })
    const w: World = { ...SIGNED_IN, fetches, commands: [], autoRuns: [], prompts: [], runs: [], userSettings: { model: 'opus[1m]' }, isDforgeConfigRefusing: true, autoFile: files[AUTO] }
    const clock = world(on, w)
    mock.store(on, { notifyUrl: WEBHOOK })
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    const notice = fetches.map(one => (one.body.embeds as Record<string, unknown>[] | undefined)?.[0]).find(embed => embed?.title === '⛔ Default model not restored')
    expect(notice).toBeDefined()
    expect(JSON.stringify(notice)).toMatch(/\/home\/me\/\.claude\/settings\.json/)
  })

  test('reads a run only for its session, and its sentinel only as the last line', () => {
```

- [ ] **Step 2: Run the tests to verify they fail**

Run, from the worktree root: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: exit 1, `242 pass` and `8 fail`, the failures being exactly:

- `(fail) auto run > says at the switch that execution begins at Setup`
- `(fail) auto run > ends the run when its compaction reaches the cap`
- `(fail) auto run > ends the run when an engine compaction reaches the cap`
- `(fail) auto run > books no engine compaction over a pending handoff`
- `(fail) auto run > books no engine compaction over a pending compact`
- `(fail) auto run > runs neither /model nor /effort when node cannot run the restore`
- `(fail) auto run > runs neither /model nor /effort when the user settings cannot be read`
- `(fail) auto run > sends a blocked notice naming the settings file when the defaults cannot be put back`

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
const AUTO_SWITCH_INSTRUCTIONS =
  'Preserve verbatim: the spec, plan, register and auto-run state file paths; the base branch; the current HEAD. Drop the design conversation: the spec and the plan hold what it decided.'
```

with:

```ts
const AUTO_SWITCH_INSTRUCTIONS =
  "Preserve verbatim: the spec, plan, register and auto-run state file paths; the base branch; the current HEAD. Drop the design conversation: the spec and the plan hold what it decided. No task has started and no execution worktree exists yet; execution begins at the execution skill's Setup."
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
      // The compaction happened: never repeat it. Unbooked, pending stays
      // compact and no later stage would run, so stop the run instead.
      if ((await autoRunCall($, bound, ['compacted'])) !== 0) {
        await endUnboundRun($, bound, 'the cockpit compacted but could not book it')
        return
      }
```

with:

```ts
      // The compaction happened: never repeat it. Unbooked, pending stays
      // compact and no later stage would run, so stop the run instead. Exit 5
      // is the script's own stop: the compaction cap was reached.
      const booked = await autoRunCall($, bound, ['compacted'])
      if (booked === 5) {
        await endStoppedRun($)
        return
      }
      if (booked !== 0) {
        await endUnboundRun($, bound, 'the cockpit compacted but could not book it')
        return
      }
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
    const refused: string[] = []
    let isRestored = true
    if (auto.launch !== null) {
      const saved = await userDefaults($)
      for (const [command, args] of [['model', auto.launch.model], ['effort', auto.launch.effort]] as const) {
        await $.command.run({ command, args }).catch(() => refused.push(`/${command} ${args}`))
      }
      isRestored = saved !== null && (await restoreUserDefaults($, saved))
    }
    const notes: string[] = []
    if (refused.length > 0) notes.push(`The cockpit could not run ${refused.join(' or ')}; this session runs on ${await $.session.model()}.`)
    if (!isRestored) notes.push('The cockpit could not put back the default model and effort that /model and /effort saved in your user settings.')
```

with:

```ts
    const refused: string[] = []
    let isRestored = true
    let isKept = false
    if (auto.launch !== null) {
      // /model and /effort save the user's defaults: run them only when those
      // can be read now and put back after (the restore runs node).
      const saved = await userDefaults($)
      if (saved !== null && (await nodeRuns($))) {
        for (const [command, args] of [['model', auto.launch.model], ['effort', auto.launch.effort]] as const) {
          await $.command.run({ command, args }).catch(() => refused.push(`/${command} ${args}`))
        }
        isRestored = await restoreUserDefaults($, saved)
        if (!isRestored) {
          await notify($, { kind: 'blocked', title: '⛔ Default model not restored', detail: `/model and /effort left the auto run's launch model as the default in ${await userSettingsPath($)}.`, isPlain: true })
        }
      } else isKept = true
    }
    const notes: string[] = []
    if (isKept) notes.push(`The cockpit kept this session on ${await $.session.model()} because it could not put back your default model afterwards.`)
    if (refused.length > 0) notes.push(`The cockpit could not run ${refused.join(' or ')}; this session runs on ${await $.session.model()}.`)
    if (!isRestored) notes.push('The cockpit could not put back the default model and effort that /model and /effort saved in your user settings.')
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
// /model and /effort save their values as the user's defaults for every new
// session;
```

with:

```ts
// Whether node starts: the restore below runs dforge-config.mjs with it.
async function nodeRuns($: EngineInterface): Promise<boolean> {
  const ran = await $.process.run(['node', '--version'], { timeoutMs: 5_000 }).catch(() => null)
  return ran?.exitCode === 0
}

// The user settings file /model and /effort write, for the notice that names it.
async function userSettingsPath($: EngineInterface): Promise<string> {
  const home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))
  const configDir = (await $.env.get('CLAUDE_CONFIG_DIR')) || (home ? `${home.replace(/[\\/]+$/, '')}/.claude` : '~/.claude')
  return `${configDir}/settings.json`
}

// /model and /effort save their values as the user's defaults for every new
// session;
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
  // A pending clear or switch supersedes the compaction: booking it would drop
  // that stage.
  if (auto === null || !auto.active || ['clear', 'switch', 'switch-resume'].includes(auto.pending ?? '')) return
  await autoRunCall($, await $.session.id(), ['compacted'])
```

with:

```ts
  // A pending clear or switch supersedes the compaction: booking it would drop
  // that stage. A pending handoff still needs its clear, and a pending compact
  // is the cockpit's own stage, which books itself.
  if (auto === null || !auto.active || ['clear', 'switch', 'switch-resume', 'handoff', 'compact'].includes(auto.pending ?? '')) return
  // Exit 5: the compaction cap stopped the run.
  if ((await autoRunCall($, await $.session.id(), ['compacted'])) === 5) await endStoppedRun($)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run, from the worktree root: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: exit 0, `250 pass`, `0 fail`.

Then run `env -u CLAUDE_CONFIG_DIR timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`. Expected: `✔ Validation passed` (a `$` handed to anything but a top-level function of the same file fails here).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(cockpit): guard compaction cap and restore"
```

### Task 10: Cockpit heartbeat and deferral cap

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx` (new constants above `// The tools that wait on the person by their nature`; `S` below `autoTimer`; `session.start` after `trackAutoRun`; `armAutoRun`; the early return and the deferral at the top of `autoAct`; new `beat` and `watchdogTick` above `endStoppedRun`)
- Test: `plugins/dforge/tests/cockpit.test.ts` (three tests above `reads a run only for its session`)

**Interfaces:**
- Consumes: C9 — `WATCHDOG_MS = 60_000`, `DEFER_CAP_MS = 1_800_000`, and the failure reason `a background launch kept the <stage> waiting 30 minutes` (spec §L.3).
- Produces: C4 — the heartbeat file `$HOME/.claude/dforge/sessions/cockpit/<id>` holding the epoch seconds of the last beat, written at `session.start` and every `WATCHDOG_MS`; `auto-run start` and `ar_is_stale` read it (C3, C4). Task 11 fills in `watchdogTick`.

**Items:** 26, 30

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

Covers spec §L.1 (the heartbeat), §L.3 and A24.

The deferral's start (`S.autoDeferredSince`) is cleared on every path that leaves it: the stage proceeding, the stage's early return when the run stopped or its pending action changed, and `armAutoRun` arming a stage (which cancels whatever timer the old deferral had). A later run or stage therefore never inherits an old deferral.

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
  test('reads a run only for its session, and its sentinel only as the last line', () => {
```

with:

```ts
  test('writes the heartbeat at the start and on every watchdog tick', async ($, on) => {
    const written: Record<string, string> = {}
    const clock = world(on, { ...SIGNED_IN, written })
    signedIn(on, {})
    await $.session.start(START)
    expect(written['/home/me/.claude/dforge/sessions/cockpit/sess-1']).toBe('1000\n')
    await clock.advance(60_000)
    expect(written['/home/me/.claude/dforge/sessions/cockpit/sess-1']).toBe('1060\n')
  })

  test('books a failure once background work has deferred a stage for 30 minutes', async ($, on) => {
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.agent.spawn({
      tool_use_id: 'toolu_1',
      prompt: 'Implement task 4',
      description: 'Task 4',
      subagentType: 'dforge:impl-sonnet-low',
      provider: { plugin: 'dforge', tier: 'user' },
      parentModel: 'claude-opus-5-5',
      background: true,
      fork: false,
    })
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    await clock.advance(1_795_000)
    expect(w.autoRuns?.filter(call => call.includes(' failure '))).toEqual([])
    await clock.advance(10_000)
    expect(w.autoRuns?.filter(call => call.includes(' failure '))).toEqual(['--session sess-1 failure --reason a background launch kept the compact waiting 30 minutes'])
    expect(w.compacts).toEqual([])
  })

  test("starts a new run's deferral afresh after the last one stopped", async ($, on) => {
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.agent.spawn({
      tool_use_id: 'toolu_1',
      prompt: 'Implement task 4',
      description: 'Task 4',
      subagentType: 'dforge:impl-sonnet-low',
      provider: { plugin: 'dforge', tier: 'user' },
      parentModel: 'claude-opus-5-5',
      background: true,
      fork: false,
    })
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    await clock.advance(1_740_000)
    files[AUTO]!.text = autoFiles({ active: false, pending: null })[AUTO]!.text
    await clock.advance(10_000)
    files[AUTO]!.text = autoFiles()[AUTO]!.text
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't2', reason: 'answer' })
    await settle(clock)
    await clock.advance(120_000)
    expect(w.autoRuns?.filter(call => call.includes(' failure '))).toEqual([])
  })

  test('reads a run only for its session, and its sentinel only as the last line', () => {
```

- [ ] **Step 2: Run the tests to verify they fail**

Run, from the worktree root: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: exit 1, `251 pass` and `2 fail`, the failures being exactly:

- `(fail) auto run > writes the heartbeat at the start and on every watchdog tick`
- `(fail) auto run > books a failure once background work has deferred a stage for 30 minutes`

`starts a new run's deferral afresh after the last one stopped` passes already (nothing books a deferral failure yet); it fails if the deferral is not cleared when the run stops or a stage is armed.

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
// The tools that wait on the person by their nature: their dialog is the question.
```

with:

```ts
// The watchdog's period, and how long background work may defer a pending
// stage before that books a failure.
const WATCHDOG_MS = 60_000
const DEFER_CAP_MS = 1_800_000
// The tools that wait on the person by their nature: their dialog is the question.
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
  // The auto run's scheduled stage, at most one.
  autoTimer: null as Timer | null,
```

with:

```ts
  // The auto run's scheduled stage, at most one.
  autoTimer: null as Timer | null,
  // When background work began deferring the pending stage; null while nothing does.
  autoDeferredSince: null as number | null,
  // The watchdog's timer, every WATCHDOG_MS.
  watchdog: null as Timer | null,
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
    await readRun($)
    await trackAutoRun($)
    await readVersion($)
```

with:

```ts
    await readRun($)
    await trackAutoRun($)
    await beat($)
    S.watchdog?.cancel()
    S.watchdog = $.clock.every(WATCHDOG_MS, () => void watchdogTick($))
    await readVersion($)
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
  if (auto === null || !auto.active || auto.pending !== AUTO_STAGE_PENDING[stage]) return
  if (S.isTurnLive || (await read($, spawns)).some(one => !one.isDone) || (await read($, shells)).length > 0) {
    scheduleAutoAct($, stage, AUTO_RETRY_MS)
    return
  }
  let bound = await $.session.id()
```

with:

```ts
  if (auto === null || !auto.active || auto.pending !== AUTO_STAGE_PENDING[stage]) {
    // The run stopped or moved on: its deferral, if any, ends with it.
    S.autoDeferredSince = null
    return
  }
  const isBackground = (await read($, spawns)).some(one => !one.isDone) || (await read($, shells)).length > 0
  if (S.isTurnLive || isBackground) {
    const stamp = await $.clock.now()
    S.autoDeferredSince = isBackground ? (S.autoDeferredSince ?? stamp) : null
    if (S.autoDeferredSince === null || stamp - S.autoDeferredSince < DEFER_CAP_MS) {
      scheduleAutoAct($, stage, AUTO_RETRY_MS)
      return
    }
    // A launch that never reports would hold the stage forever: book it as a
    // failure, so the second one stops the run with a reason.
    S.autoDeferredSince = null
    const owner = await $.session.id()
    const why = `a background launch kept the ${stage} waiting 30 minutes`
    const code = await autoRunCall($, owner, ['failure', '--reason', why])
    if (code === 0) scheduleAutoAct($, stage, AUTO_RETRY_MS)
    else if (code === 5) await endStoppedRun($)
    else await endUnboundRun($, owner, `${why}, and the failure could not be booked (exit ${code})`)
    return
  }
  S.autoDeferredSince = null
  let bound = await $.session.id()
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
// The run stopped while the session was idle: record it, and give the model a
// turn to end the run as the attended flow would.
```

with:

```ts
// The heartbeat scripts/auto-run reads (reference/auto-run.md §Starting): the
// epoch seconds of the last beat, in a file named for this session's id with
// each character outside A-Za-z0-9 a dash.
async function beat($: EngineInterface) {
  const home = (await $.env.get('HOME')) || (await $.env.get('USERPROFILE'))
  if (!home) return
  const id = (await $.session.id()).replace(/[^A-Za-z0-9]/g, '-')
  const seconds = Math.floor((await $.clock.now()) / 1000)
  await $.fs.write(`${home.replace(/[\\/]+$/, '')}/.claude/dforge/sessions/cockpit/${id}`, `${seconds}\n`).catch(() => undefined)
}

// Each WATCHDOG_MS: the heartbeat.
async function watchdogTick($: EngineInterface) {
  await beat($)
}

// The run stopped while the session was idle: record it, and give the model a
// turn to end the run as the attended flow would.
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
  scheduleAutoAct($, auto.pending === 'clear' ? 'clear' : auto.pending === 'switch' ? 'switch' : 'compact', 0)
```

with:

```ts
  // A stage armed now starts its own deferral, whatever the timer it replaces had.
  S.autoDeferredSince = null
  scheduleAutoAct($, auto.pending === 'clear' ? 'clear' : auto.pending === 'switch' ? 'switch' : 'compact', 0)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run, from the worktree root: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: exit 0, `253 pass`, `0 fail`.

Then run `env -u CLAUDE_CONFIG_DIR timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`. Expected: `✔ Validation passed` (a `$` handed to anything but a top-level function of the same file fails here).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(cockpit): write a heartbeat, cap deferral"
```

### Task 11: Cockpit watchdog wakes a stalled run

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx` (the watchdog constants Task 10 added; `S` below `autoTimer`; `autoAct`, split into `autoAct` and `autoStage`; `session.start`'s heartbeat lines; the body of `watchdogTick`)
- Modify: `plugins/dforge/hooks/cockpit/lib.ts` (`autoRunFor`, at about line 945)
- Modify: `plugins/dforge/types/index.d.ts` (`CockpitAutoRun`, at about line 223)
- Test: `plugins/dforge/tests/cockpit.test.ts` (the `World` type, the fake `session.compact` and `auto-run`, thirteen tests above `reads a run only for its session`, and two lines in that test)

**Interfaces:**
- Consumes: C1 — the state's `stalledAt` (epoch seconds or null); C3 — `auto-run stalled` exits 0, or 5 when it stops the run with the reason `three stalls without a completed task`; C9 — `S.autoBusy`, `S.autoActedAt`, `STALL_MS = 180_000` and the stall prompt.
- Produces: `CockpitAutoRun.stalledAt` (`number | null`), read by `watchdogTick` only.

**Items:** 26

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

Covers spec §L.2 and A22 (and the cockpit side of A23).

A tick measures the session's last motion as the latest of whichever exist: this session's start (`S.watchedSince`), its last turn's end (`endedAt`), the last stage `autoAct` finished (`S.autoActedAt`) and the last nudge (`stalledAt`). It acts only once that is more than `STALL_MS` old, so a session that has had no turn yet (a cleared session, a `--resume`) still recovers, and a stage that has just submitted its prompt is not nudged before that prompt's turn can start. A pending `resume` with no stage timer resubmits the run's first prompt.

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
  /** Reading the user settings rejects. */
  isUserSettingsUnreadable?: boolean
}
```

with:

```ts
  /** Reading the user settings rejects. */
  isUserSettingsUnreadable?: boolean
  /** How long each compaction takes, in the clock's milliseconds; at once unless said. */
  compactMs?: number
}
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
  on('session.compact', (_$, e) => {
    w.compacts?.push(`${e.trigger}:${(e as { instructions?: string }).instructions ?? ''}`)
    return w.isCompactVetoed ? ({ skip: 'vetoed' } as never) : { messages: e.messages ?? [SUMMARY] }
  })
```

with:

```ts
  on('session.compact', (_$, e) => {
    w.compacts?.push(`${e.trigger}:${(e as { instructions?: string }).instructions ?? ''}`)
    const done = w.isCompactVetoed ? ({ skip: 'vetoed' } as never) : { messages: e.messages ?? [SUMMARY] }
    return w.compactMs === undefined ? done : clock.sleep(w.compactMs).then(() => done)
  })
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
        if (exitCode === 5 && word === 'compacted') Object.assign(state, { active: false, stopped: 'three compactions without a completed task', pending: null })
```

with:

```ts
        if (exitCode === 5 && word === 'compacted') Object.assign(state, { active: false, stopped: 'three compactions without a completed task', pending: null })
        if (exitCode === 0 && word === 'stalled') Object.assign(state, { stalls: Number(state.stalls ?? 0) + 1, stalledAt: Math.floor(clock.now() / 1000) })
        if (exitCode === 5 && word === 'stalled') Object.assign(state, { active: false, stopped: 'three stalls without a completed task', pending: null })
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
  test('reads a run only for its session, and its sentinel only as the last line', () => {
```

with:

```ts
  test('nudges a stalled run, and again only once its last nudge is as old', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(180_000)
    expect(w.prompts).toEqual([])
    await clock.advance(60_000)
    expect(w.autoRuns?.filter(call => call === '--session sess-1 stalled')).toHaveLength(1)
    expect(w.prompts).toEqual([
      expect.stringMatching(/^The auto run stalled: the last turn ended without its sentinel line\. Run `bash .*\/scripts\/auto-run status`, continue the phase it names, and end the turn as reference\/auto-run\.md §Ending a turn says\.$/),
    ])
    await clock.advance(180_000)
    expect(w.prompts).toHaveLength(1)
    await clock.advance(60_000)
    expect(w.prompts).toHaveLength(2)
  })

  test('nudges a run whose turn failed', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: '', durationMs: 1, isAborted: false, turnId: 't1', reason: 'error' })
    await clock.advance(240_000)
    expect(w.autoRuns).toContain('--session sess-1 stalled')
    expect(w.prompts).toHaveLength(1)
  })

  test('leaves the run to the owner after an Esc', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3', durationMs: 1, isAborted: true, turnId: 't1', reason: 'aborted' })
    await clock.advance(600_000)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
    expect(w.prompts).toEqual([])
  })

  test('leaves the run alone while a subagent runs', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.agent.spawn({
      tool_use_id: 'toolu_1',
      prompt: 'Implement task 4',
      description: 'Task 4',
      subagentType: 'dforge:impl-sonnet-low',
      provider: { plugin: 'dforge', tier: 'user' },
      parentModel: 'claude-opus-5-5',
      background: true,
      fork: false,
    })
    await $.turn.complete({ answer: 'Waiting for Task 4.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(600_000)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
    expect(w.prompts).toEqual([])
  })

  test('ends the run at the stall that stops it', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO], autoRunExits: { stalled: 5 } }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(240_000)
    expect(w.prompts).toEqual(['The auto run stopped: three stalls without a completed task. End as reference/auto-run.md §Stopping says.'])
  })

  test('arms a pending stage that no timer holds', async ($, on) => {
    const files = autoFiles({ pending: 'compact' })
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(240_000)
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
    expect(pendingOf(files)).toBe('after-compact')
  })

  test('resubmits the first prompt of a pending resume that no timer holds', async ($, on) => {
    const files = autoFiles({ pending: 'resume', resumePrompt: 'Execute docs/plan.md.', launch: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(240_000)
    await settle(clock)
    expect(w.prompts).toEqual(['Execute docs/plan.md.'])
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
    expect(w.autoRuns).toContain('--session sess-1 resumed')
    expect(pendingOf(files)).toBeNull()
  })

  test('nudges a bound run in a session that has had no turn yet', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await clock.advance(180_000)
    expect(w.prompts).toEqual([])
    await clock.advance(60_000)
    expect(w.autoRuns).toContain('--session sess-1 stalled')
    expect(w.prompts).toHaveLength(1)
  })

  test('recovers a cleared session whose first prompt started no turn', async ($, on) => {
    const files = autoFiles({ pending: 'clear', resumePrompt: 'Execute docs/plan.md.', launch: null })
    const w: World = { ...SIGNED_IN, commands: [], autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.prompts).toEqual(['Execute docs/plan.md.'])
    await clock.advance(240_000)
    expect(w.autoRuns).toContain('--session sess-2 stalled')
    expect(w.prompts).toHaveLength(2)
  })

  test('waits STALL_MS after a stage before it nudges', async ($, on) => {
    const files = autoFiles({ pending: 'compact' })
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(240_000)
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.prompts).toHaveLength(1)
    await clock.advance(60_000)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
    await clock.advance(120_000)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
    await clock.advance(60_000)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toHaveLength(1)
  })

  test('leaves the run alone while a background shell runs', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO], tools: { Bash: () => ({ result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'b9w1' }, text: 'Running in the background' }) } }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'npm run dev', run_in_background: true } as never)
    await $.turn.complete({ answer: 'Waiting for the server.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(600_000)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
    expect(w.prompts).toEqual([])
  })

  test('leaves the run alone while a turn runs', async ($, on) => {
    const files = autoFiles({ pending: null })
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await $.turn.start({ text: 'Continue.', turnId: 't2' })
    await clock.advance(600_000)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
    expect(w.prompts).toEqual([])
  })

  test('arms nothing while a stage runs, a long compaction included', async ($, on) => {
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO], compactMs: 240_000 }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    await clock.advance(250_000)
    expect(w.compacts).toHaveLength(1)
    expect(w.autoRuns?.filter(call => call.includes(' stalled'))).toEqual([])
  })

  test('reads a run only for its session, and its sentinel only as the last line', () => {
```

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```ts
    expect(autoRunFor(text, 'b')?.plan).toBe('docs/plan.md')
    expect(autoRunFor(text, 'a')).toBeNull()
```

with:

```ts
    expect(autoRunFor(text, 'b')?.plan).toBe('docs/plan.md')
    expect(autoRunFor(text, 'b')?.stalledAt).toBeNull()
    expect(autoRunFor(autoFiles({ session: 'b', stalledAt: 1240 })[AUTO]!.text, 'b')?.stalledAt).toBe(1240)
    expect(autoRunFor(text, 'a')).toBeNull()
```

- [ ] **Step 2: Run the tests to verify they fail**

Run, from the worktree root: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: exit 1, `257 pass` and `9 fail`, the failures being exactly:

- `(fail) auto run > nudges a stalled run, and again only once its last nudge is as old`
- `(fail) auto run > nudges a run whose turn failed`
- `(fail) auto run > ends the run at the stall that stops it`
- `(fail) auto run > arms a pending stage that no timer holds`
- `(fail) auto run > resubmits the first prompt of a pending resume that no timer holds`
- `(fail) auto run > nudges a bound run in a session that has had no turn yet`
- `(fail) auto run > recovers a cleared session whose first prompt started no turn`
- `(fail) auto run > waits STALL_MS after a stage before it nudges`
- `(fail) auto run > reads a run only for its session, and its sentinel only as the last line`

The tests that assert nothing happens (after an Esc, while a subagent runs, while a background shell runs, while a turn runs, while a stage runs) pass already; each except the live-turn case fails once the watchdog acts without its guard (the live turn is also excluded by the activity-kind check).

- [ ] **Step 3: Write the implementation**

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
// The watchdog's period, and how long background work may defer a pending
// stage before that books a failure.
const WATCHDOG_MS = 60_000
const DEFER_CAP_MS = 1_800_000
```

with:

```ts
// The watchdog's period, and how long background work may defer a pending
// stage before that books a failure. A bound run idle STALL_MS since its last
// turn ended, stage ran or nudge went is stalled.
const WATCHDOG_MS = 60_000
const DEFER_CAP_MS = 1_800_000
const STALL_MS = 180_000
// The pending actions whose stage the watchdog arms again when no timer holds
// it; a pending resume resubmits the run's first prompt.
const WATCHED_STAGES: Readonly<Record<string, AutoStage>> = { compact: 'compact', clear: 'clear', resume: 'resume', switch: 'switch', 'switch-resume': 'switch-resume' }
function stallPrompt(root: string): string {
  return `The auto run stalled: the last turn ended without its sentinel line. Run \`bash ${root}/scripts/auto-run status\`, continue the phase it names, and end the turn as reference/auto-run.md §Ending a turn says.`
}
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
  // The auto run's scheduled stage, at most one.
  autoTimer: null as Timer | null,
```

with:

```ts
  // The auto run's scheduled stage, at most one.
  autoTimer: null as Timer | null,
  // True while autoAct runs a stage, a long compaction included, and when it
  // last finished one: a prompt it just submitted has not started its turn yet.
  autoBusy: false,
  autoActedAt: null as number | null,
  // When this session started: one with no turn yet ages from it.
  watchedSince: null as number | null,
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
async function autoAct($: EngineInterface, stage: AutoStage) {
  S.autoTimer = null
  const auto = await readAutoRun($)
```

with:

```ts
async function autoAct($: EngineInterface, stage: AutoStage) {
  S.autoTimer = null
  // The watchdog arms nothing while a stage is in flight.
  S.autoBusy = true
  try {
    await autoStage($, stage)
  } finally {
    S.autoBusy = false
    S.autoActedAt = await $.clock.now()
  }
}

async function autoStage($: EngineInterface, stage: AutoStage) {
  const auto = await readAutoRun($)
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
// Each WATCHDOG_MS: the heartbeat.
async function watchdogTick($: EngineInterface) {
  await beat($)
}
```

with:

```ts
// Each WATCHDOG_MS: the heartbeat, then a wake-up for a bound run nothing
// else will carry on. A turn that ended on an error, or without its sentinel
// and unheld, arms no stage, and a pending stage can lose its timer. Never
// while a turn, background work, a stage or an Esc holds the session, and
// never within STALL_MS of the latest of this session's start, its last
// turn's end, the last stage and the last nudge.
async function watchdogTick($: EngineInterface) {
  await beat($)
  if (S.isTurnLive || S.autoBusy) return
  const auto = await readAutoRun($)
  if (auto === null || !auto.active) return
  if ((await read($, spawns)).some(one => !one.isDone) || (await read($, shells)).length > 0) return
  const now = await read($, activity)
  if (now.kind !== 'idle' && now.kind !== 'failed') return
  const last = Math.max(S.watchedSince ?? 0, now.endedAt ?? 0, S.autoActedAt ?? 0, (auto.stalledAt ?? 0) * 1000)
  if ((await $.clock.now()) - last <= STALL_MS) return
  const stage = WATCHED_STAGES[auto.pending ?? '']
  if (stage !== undefined) {
    if (S.autoTimer === null) {
      S.autoDeferredSince = null
      scheduleAutoAct($, stage, 0)
    }
    return
  }
  const code = await autoRunCall($, await $.session.id(), ['stalled'])
  if (code === 5) await endStoppedRun($)
  else if (code === 0) await $.prompt.submit({ text: stallPrompt($.plugin.root), asUser: true }).catch(() => undefined)
}
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```ts
    await beat($)
    S.watchdog?.cancel()
```

with:

```ts
    S.watchedSince = await $.clock.now()
    await beat($)
    S.watchdog?.cancel()
```

In `plugins/dforge/hooks/cockpit/lib.ts`, replace:

```ts
    resumePrompt: word(s.resumePrompt),
    launch: typeof launch.model
```

with:

```ts
    resumePrompt: word(s.resumePrompt),
    stalledAt: typeof s.stalledAt === 'number' && Number.isFinite(s.stalledAt) ? s.stalledAt : null,
    launch: typeof launch.model
```

In `plugins/dforge/types/index.d.ts`, replace:

```ts
  /** The first prompt of the session a clear starts. */
  resumePrompt: string | null
```

with:

```ts
  /** The first prompt of the session a clear starts. */
  resumePrompt: string | null
  /** When `auto-run stalled` last ran, in epoch seconds; null before. */
  stalledAt: number | null
```

- [ ] **Step 4: Run the tests to verify they pass**

Run, from the worktree root: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`

Expected: exit 0, `266 pass`, `0 fail`.

Then run `env -u CLAUDE_CONFIG_DIR timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`. Expected: `✔ Validation passed` (a `$` handed to anything but a top-level function of the same file fails here).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/types/index.d.ts plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(cockpit): wake a stalled auto run"
```

### Task 12: Execution skills after the switch

Spec §A.4, §E (skill text), §F, §G and §J: the two execution skills, the delegated-task and parallel-waves references and the handoff skill say what an auto run does on the path a switched or compacted controller actually takes. Covers A4, A6 (skill text), A13 (skill text), A14, A15 (executing-plans) and A19 (skills).

**Files:**
- Modify: `plugins/dforge/skills/executing-plans/SKILL.md`
- Modify: `plugins/dforge/skills/subagent-driven-development/SKILL.md`
- Modify: `plugins/dforge/reference/delegated-task.md`
- Modify: `plugins/dforge/reference/parallel-waves.md`
- Modify: `plugins/dforge/skills/handoff/SKILL.md`
- Test: `plugins/dforge/tests/auto-run-skills.test.sh`

**Interfaces:**
- Consumes: C3 and C10 (the script behaviour and exit codes the new text names; C10 for test ownership).
- Produces: the skill and reference sentences pinned in this task's test files.

**Items:** 13, 16, 18, 19, 23

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Add the failing pins**

Each new pin fails before the edits; the replaced Setup pin's old phrase stays in both skills, and every phrase another test pins (the After compaction step numbers 1-4, `and every task that depends on it`, `` `scripts/auto-run task-complete`. After each task, run the Fable batch when ``, `a compaction that left too much. A saved plan switches in place instead`) stays byte-identical.

In `plugins/dforge/tests/auto-run-skills.test.sh`, replace:

```bash
  names "$skill: after a compaction" "$F" '`scripts/auto-run after-compact` before step 1 above'
  names "$skill: setup asks nothing" "$F" 'skip the finish-preference question; run `scripts/auto-run phase execute`'
```

with:

```bash
  names "$skill: after a compaction" "$F" '`scripts/auto-run after-compact` before step 0 above'
  names "$skill: setup asks nothing, from the worktree" "$F" 'from the execution worktree, once dforge:using-git-worktrees has created it.'
  names "$skill: exit 4 is a skipped worktree" "$F" 'Exit 4 means the worktree step was skipped: create the worktree, then run'
  names "$skill: no ledger goes to Setup" "$F" 'no ledger names this plan, no task has started: skip the rest of this'
  names "$skill: setup due goes to Setup" "$F" '0. In an auto run, when `scripts/auto-run status` says setup is due, or when'
  names "$skill: a task-complete stop" "$F" 'A `task-complete` exit 5 means the run stopped (a task was completed in the'
  names "$skill: dependents come from the plan" "$F" 'names the task; in a plan without those lines, its `Consumes:` line cites'
  names "$skill: compact still ends the turn at the final check" "$F" 'a `compact` line still ends the turn on `Auto run: compacting`.'
  check "$skill: no handoff rule at the final check" "$(grep -c "Auto run section's \`handoff\`" "$F")" "0"
```

In `plugins/dforge/tests/auto-run-skills.test.sh`, replace:

```bash
names "subagent-driven-development: a deferred task is not merged" "$P/skills/subagent-driven-development/SKILL.md" "a deferred task's branch is"
```

with:

```bash
names "subagent-driven-development: a deferred task is not merged" "$P/skills/subagent-driven-development/SKILL.md" "a deferred task's branch is"
EPF="$P/skills/executing-plans/SKILL.md"
names "executing-plans: step 7 runs task-complete" "$EPF" 'auto run, run `scripts/auto-run task-complete`, then the Fable batch when'
names "executing-plans: step 8 moves to the final phase" "$EPF" '`scripts/context-size --final`; in an auto run it moves the run to the'
names "executing-plans: the budget section says so too" "$EPF" 'Finishing is never budget-checked. In an auto run `--final` also moves the'
names "subagent-driven-development: the budget section says so" "$P/skills/subagent-driven-development/SKILL.md" 'from the ledger. In an auto run `--final` also moves the run to the final'
names "executing-plans: the mode switch clears by phase" "$EPF" '`scripts/auto-run clear --phase`, and end the turn with'
names "executing-plans: the mode switch in an auto run" "$EPF" 'not need. In an auto run, run dforge:handoff steps 0-4, then'
names "delegated-task.md: task-complete after the complete line" "$P/reference/delegated-task.md" 'In an auto run, run `scripts/auto-run task-complete`, then the Fable batch when'
names "parallel-waves.md: task-complete after the merge" "$P/reference/parallel-waves.md" '`; merged <sha7>`. In an auto run, run `scripts/auto-run task-complete`'
names "parallel-waves.md: before any budget check" "$P/reference/parallel-waves.md" 'right after it, before any budget check or dispatch; the Fable batch runs'
names "handoff: the mode switch hands off too" "$P/skills/handoff/SKILL.md" 'mode hands off too, and the step that invoked this skill runs'
```

- [ ] **Step 2: Run the pins to verify they fail**

Run each, one command at a time:

```bash
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh
```

Expected: FAIL on the new pins only (the replaced pins' new text is not yet in the files); every other check passes.

- [ ] **Step 3: Edit the text**

Each old text occurs exactly once in its file; replace it with the new text exactly, including its line breaks.

10.1 In `plugins/dforge/skills/executing-plans/SKILL.md`, replace:

```markdown
back. Before anything else:

1. Run `scripts/sdd-workspace PLAN_FILE`
```

with:

```markdown
back. Before anything else:

0. In an auto run, when `scripts/auto-run status` says setup is due, or when
   no ledger names this plan, no task has started: skip the rest of this
   section and follow Setup from its first step.
1. Run `scripts/sdd-workspace PLAN_FILE`
```

10.2 In `plugins/dforge/skills/subagent-driven-development/SKILL.md`, replace:

```markdown
back. Before anything else:

1. Run `scripts/sdd-workspace PLAN_FILE`
```

with:

```markdown
back. Before anything else:

0. In an auto run, when `scripts/auto-run status` says setup is due, or when
   no ledger names this plan, no task has started: skip the rest of this
   section and follow Setup from its first step.
1. Run `scripts/sdd-workspace PLAN_FILE`
```

10.3 In `plugins/dforge/skills/executing-plans/SKILL.md`, replace:

```markdown
   and go on to the final review or finishing whatever it prints: the final
   phase never hands off (in an auto run, the Auto run section's `handoff`
   rule still applies). Otherwise run `scripts/context-size`; on exit 5,
   finish the task in flight, then invoke dforge:handoff.
```

with:

```markdown
   and go on to the final review or finishing whatever it prints: the final
   phase never hands off. In an auto run it also moves the run to the final
   phase, and a `compact` line still ends the turn on `Auto run: compacting`.
   Otherwise run `scripts/context-size`; on exit 5, finish the task in
   flight, then invoke dforge:handoff.
```

10.4 In `plugins/dforge/skills/subagent-driven-development/SKILL.md`, replace:

```markdown
   and go on to Final Review or finishing whatever it prints: the final phase
   never hands off (in an auto run, the Auto run section's `handoff` rule still
   applies). Otherwise run `scripts/context-size`; on exit 5, finish the task
   in flight, then invoke dforge:handoff.
```

with:

```markdown
   and go on to Final Review or finishing whatever it prints: the final phase
   never hands off. In an auto run it also moves the run to the final phase,
   and a `compact` line still ends the turn on `Auto run: compacting`.
   Otherwise run `scripts/context-size`; on exit 5, finish the task in flight,
   then invoke dforge:handoff.
```

10.5 In `plugins/dforge/skills/executing-plans/SKILL.md`, replace:

```markdown
`scripts/auto-run after-compact` before step 1 above.
```

with:

```markdown
`scripts/auto-run after-compact` before step 0 above.
```

10.6 In `plugins/dforge/skills/subagent-driven-development/SKILL.md`, replace:

```markdown
`scripts/auto-run after-compact` before step 1 above.
```

with:

```markdown
`scripts/auto-run after-compact` before step 0 above.
```

10.7 In `plugins/dforge/skills/executing-plans/SKILL.md`, replace:

```markdown
- **Setup:** skip the finish-preference question; run `scripts/auto-run phase execute`.
```

with:

```markdown
- **Setup:** skip the finish-preference question; run `scripts/auto-run phase execute`
  from the execution worktree, once dforge:using-git-worktrees has created it.
  Exit 4 means the worktree step was skipped: create the worktree, then run
  the command again from it.
```

10.8 In `plugins/dforge/skills/subagent-driven-development/SKILL.md`, replace:

```markdown
- **Setup:** skip the finish-preference question; run `scripts/auto-run phase execute`.
```

with:

```markdown
- **Setup:** skip the finish-preference question; run `scripts/auto-run phase execute`
  from the execution worktree, once dforge:using-git-worktrees has created it.
  Exit 4 means the worktree step was skipped: create the worktree, then run
  the command again from it.
```

10.9 In `plugins/dforge/skills/executing-plans/SKILL.md`, replace:

```markdown
so a compaction from there on never hands off.
- **The budget line** reads
```

with:

```markdown
so a compaction from there on never hands off.
  A `task-complete` exit 5 means the run stopped (a task was completed in the
  primary checkout): end as auto-run.md §Stopping says.
- **The budget line** reads
```

10.10 In `plugins/dforge/skills/subagent-driven-development/SKILL.md`, replace:

```markdown
so a compaction from there on never hands off.
- **The budget line** reads
```

with:

```markdown
so a compaction from there on never hands off.
  A `task-complete` exit 5 means the run stopped (a task was completed in the
  primary checkout): end as auto-run.md §Stopping says.
- **The budget line** reads
```

10.11 In `plugins/dforge/skills/executing-plans/SKILL.md`, replace:

```markdown
  deferred, and every task that depends on it: write
```

with:

```markdown
  deferred, and every task that depends on it (its `**Depends on:**` line
  names the task; in a plan without those lines, its `Consumes:` line cites
  a Contracts entry the deferred task's `Produces:` line cites): write
```

10.12 In `plugins/dforge/skills/subagent-driven-development/SKILL.md`, replace:

```markdown
  deferred, and every task that depends on it: write
```

with:

```markdown
  deferred, and every task that depends on it (its `**Depends on:**` line
  names the task; in a plan without those lines, its `Consumes:` line cites
  a Contracts entry the deferred task's `Produces:` line cites): write
```

10.13 In `plugins/dforge/skills/executing-plans/SKILL.md`, replace:

```markdown
7. **Close the task.** Append the complete line with its checkpoint, in the
   same message as your other bookkeeping, and mark the todo complete.
```

with:

```markdown
7. **Close the task.** Append the complete line with its checkpoint, in the
   same message as your other bookkeeping, and mark the todo complete. In an
   auto run, run `scripts/auto-run task-complete`, then the Fable batch when
   `scripts/auto-run decision list` prints anything.
```

10.14 In `plugins/dforge/skills/executing-plans/SKILL.md`, replace:

```markdown
8. **Check the budget after the last task.** Run
   `scripts/context-size --final`. After any other task, go to the
```

with:

```markdown
8. **Check the budget after the last task.** Run
   `scripts/context-size --final`; in an auto run it moves the run to the
   final phase, and a `compact` line still ends the turn on
   `Auto run: compacting`. After any other task, go to the
```

10.15 In `plugins/dforge/skills/executing-plans/SKILL.md`, replace:

```markdown
After every earlier task, the next brief's budget line is the check.
Finishing is never budget-checked.
```

with:

```markdown
After every earlier task, the next brief's budget line is the check.
Finishing is never budget-checked. In an auto run `--final` also moves the
run to the final phase, and a `compact` line still ends the turn on
`Auto run: compacting`.
```

10.16 In `plugins/dforge/skills/subagent-driven-development/SKILL.md`, replace:

```markdown
  compaction is the backstop, and After compaction resumes the final phase
  from the ledger.
```

with:

```markdown
  compaction is the backstop, and After compaction resumes the final phase
  from the ledger. In an auto run `--final` also moves the run to the final
  phase, and a `compact` line still ends the turn on `Auto run: compacting`.
```

10.17 In `plugins/dforge/skills/executing-plans/SKILL.md`, replace:

```markdown
   time, and this session's context is full of implementation detail it does
   not need.
```

with:

```markdown
   time, and this session's context is full of implementation detail it does
   not need. In an auto run, run dforge:handoff steps 0-4, then
   `scripts/auto-run clear --phase`, and end the turn with
   `Auto run: clearing` as its last line; a phase clear never counts as a
   self-resume.
```

10.18 In `plugins/dforge/reference/delegated-task.md`, replace:

```markdown
  ` (codex off — <reason>)` when `review-route` printed `reason=codex-off`

**Release the worktree when the task is complete.**
```

with:

```markdown
  ` (codex off — <reason>)` when `review-route` printed `reason=codex-off`

In an auto run, run `scripts/auto-run task-complete`, then the Fable batch when
`scripts/auto-run decision list` prints anything.

**Release the worktree when the task is complete.**
```

10.19 In `plugins/dforge/reference/parallel-waves.md`, replace:

```markdown
- **Exit 0, `merged Task <N>: <sha7>`.** Write the complete line with
  `; merged <sha7>`. A `note:` line names a file outside the task's
```

with:

```markdown
- **Exit 0, `merged Task <N>: <sha7>`.** Write the complete line with
  `; merged <sha7>`. In an auto run, run `scripts/auto-run task-complete`
  right after it, before any budget check or dispatch; the Fable batch runs
  after the wave. A `note:` line names a file outside the task's
```

10.20 In `plugins/dforge/skills/handoff/SKILL.md`, replace:

```markdown
- An auto run ([auto-run.md](../../reference/auto-run.md)) hands off only for
```

with:

```markdown
- An auto run ([auto-run.md](../../reference/auto-run.md)) hands off for
```

10.21 In `plugins/dforge/skills/handoff/SKILL.md`, replace:

```markdown
  never runs `scripts/auto-run clear` itself.
```

with:

```markdown
  never runs `scripts/auto-run clear` itself. A switch from inline to subagent
  mode hands off too, and the step that invoked this skill runs
  `scripts/auto-run clear --phase` (dforge:executing-plans §Switching to
  subagent mode).
```

- [ ] **Step 4: Run the suites that read these files**

Run these, one command at a time (every shell suite that names a changed file):

```bash
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/final-phase.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/inline-mode.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/process-roles.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/lanes.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/settings-skills.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/parallel-grouping.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/gates-manifest.test.sh
```

Expected: each ends `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/executing-plans/SKILL.md
git add plugins/dforge/skills/subagent-driven-development/SKILL.md
git add plugins/dforge/reference/delegated-task.md
git add plugins/dforge/reference/parallel-waves.md
git add plugins/dforge/skills/handoff/SKILL.md
git add plugins/dforge/tests/auto-run-skills.test.sh
git commit -m "docs(dforge): start execution at Setup after a switch"
```

- [ ] **Step 6: Run the whole suite**

The controller, not the executor, runs this once the task's commit is in its checkout. `scripts/test-all.mjs` runs every shell suite and then the cockpit suite (`claude plugin test plugins/dforge`):

```bash
env -u CLAUDE_CONFIG_DIR timeout --kill-after=10s 690s node scripts/test-all.mjs
```

Expected: exit 0, no `FAIL` line, and the cockpit suite's `0 fail`.

### Task 13: Auto-run, final-review and worktree references

Spec §A (auto-run.md), §B (finish-preference.md), §D, §G (auto-run.md §Clears), §H, §J (auto-run.md) and §O (auto-run.md): the references and dforge:using-git-worktrees name what an auto run does at the switch, at a phase clear, at a final-review stop and at worktree creation. Covers A10 (finish-preference.md), A12, A15 (§Clears), A16, A17 (§Rulings), A19 (auto-run.md) and A28 (auto-run.md).

**Files:**
- Modify: `plugins/dforge/reference/auto-run.md`
- Modify: `plugins/dforge/reference/final-review.md`
- Modify: `plugins/dforge/skills/using-git-worktrees/SKILL.md`
- Modify: `plugins/dforge/reference/finish-preference.md`
- Test: `plugins/dforge/tests/auto-run-skills.test.sh`

**Interfaces:**
- Consumes: C3 and C10 (the script behaviour and exit codes the new text names; C10 for test ownership).
- Produces: the skill and reference sentences pinned in this task's test files.

**Items:** 14, 17, 20, 21, 31

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Add the failing pins**

The replaced check (`no phase clear is left`) becomes `the one phase clear is the mode switch`: the plan-saved switch still writes no phase clear, and the only `clear --phase` in auto-run.md is the new §Clears case. Every other phrase a test pins in these four files stays byte-identical, including settings-skills' `worktree` pins and `once the plan is attached. Finishing carries out that choice, or else`.

In `plugins/dforge/tests/auto-run-skills.test.sh`, replace:

```bash
check "auto-run.md: no phase clear is left" "$(grep -c 'clear --phase' "$R")" "0"
```

with:

```bash
check "auto-run.md: the one phase clear is the mode switch" "$(grep -c 'clear --phase' "$R")" "1"
names "auto-run.md: the mode switch clears by phase" "$R" '- **A switch from inline to subagent mode** (dforge:executing-plans'
names "auto-run.md: the switch starts at Setup" "$R" 'execution skill starts at its Setup, worktree first: `scripts/auto-run status`'
names "auto-run.md: a listed launch is waited for" "$R" 'listed: run `scripts/in-flight`, wait for or stop each launch it lists, and'
names "auto-run.md: a second exit 5 stops the run" "$R" '`scripts/auto-run stop --reason "background work still running at the switch: <next-step'"'"'s message>"`'
names "auto-run.md: dependents come from the plan" "$R" '`**Depends on:**` line names it, or, in a plan without those lines, a later'
names "auto-run.md: a final residual is a deferred row" "$R" '`scripts/register add <run register> "<the finding>" --state deferred --note "final review residual"`.'
names "auto-run.md: a final residual keeps the branch" "$R" 'added. `merge` also keeps the branch when the run added a deferred row whose'
names "final-review.md: a red gate in an auto run" "$P/reference/final-review.md" 'run ([auto-run.md](auto-run.md)), a red gate does not stop the review: the'
names "final-review.md: a second red stops the run" "$P/reference/final-review.md" '`scripts/auto-run stop --reason "gate <name> red"` and ends as auto-run.md'
GWF="$P/skills/using-git-worktrees/SKILL.md"
names "using-git-worktrees: never is not read" "$GWF" 'The `worktree` setting is not read: `worktree=never` creates it too'
names "using-git-worktrees: the sandbox stops the run" "$GWF" 'In an auto run, do not work in place: run `scripts/auto-run stop --reason "the sandbox refused the execution worktree"`'
names "using-git-worktrees: a red baseline is a ruling" "$GWF" 'In an auto run, ask nothing: run `scripts/auto-run ruling add "Setup: baseline tests red — <failing summary>"` and continue'
names "finish-preference.md: get reads the spec line" "$P/reference/finish-preference.md" 'the plan'"'"'s spec carries a `Finish: <merge|pr|keep>` line in `## Decisions`,'
```

- [ ] **Step 2: Run the pins to verify they fail**

Run each, one command at a time:

```bash
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh
```

Expected: FAIL on the new pins only (the replaced pins' new text is not yet in the files); every other check passes.

- [ ] **Step 3: Edit the text**

Each old text occurs exactly once in its file; replace it with the new text exactly, including its line breaks.

11.1 In `plugins/dforge/reference/auto-run.md`, replace:

```markdown
3. `scripts/next-step PLAN_FILE`. Any nonzero exit means `latest.md` was not
   written: run `scripts/auto-run stop --reason "the handoff file could not be
   written"` and end as Stopping says.
```

with:

```markdown
3. `scripts/next-step PLAN_FILE`. Exit 5 means background work is still
   listed: run `scripts/in-flight`, wait for or stop each launch it lists, and
   run `scripts/next-step PLAN_FILE` again; a second exit 5 runs
   `scripts/auto-run stop --reason "background work still running at the switch: <next-step's message>"`
   and ends as Stopping says. Any other nonzero exit means `latest.md` was
   not written: run `scripts/auto-run stop --reason "the handoff file could
   not be written"` and end as Stopping says.
```

11.2 In `plugins/dforge/reference/auto-run.md`, replace:

```markdown
follow the first prompt in this same session. A switch is a phase transition:
```

with:

```markdown
follow the first prompt in this same session. No ledger exists yet, so the
execution skill starts at its Setup, worktree first: `scripts/auto-run status`
says setup is due until `phase execute` runs from the execution worktree. A
switch is a phase transition:
```

11.3 In `plugins/dforge/reference/auto-run.md`, replace:

```markdown
- **A compaction that left too much:** `scripts/auto-run clear`.
```

with:

```markdown
- **A compaction that left too much:** `scripts/auto-run clear`.
- **A switch from inline to subagent mode** (dforge:executing-plans
  §Switching to subagent mode): `scripts/auto-run clear --phase`. A phase
  clear never counts as a self-resume.
```

11.4 In `plugins/dforge/reference/auto-run.md`, replace:

```markdown
- **A task's item:** the task is deferred. Write its terminal ledger line,
  and the same line for every task that depends on it:
```

with:

```markdown
- **A task's item:** the task is deferred. Write its terminal ledger line,
  and the same line for every task that depends on it: a task whose
  `**Depends on:**` line names it, or, in a plan without those lines, a later
  task whose `Consumes:` line cites a Contracts entry the deferred task's
  `Produces:` line cites:
```

11.5 In `plugins/dforge/reference/auto-run.md`, replace:

```markdown
- **A QA `acceptance-ambiguous` item:** PARK it, as
  [final-review.md](final-review.md) step 0.5 says, and the final review
  continues.
```

with:

```markdown
- **A QA `acceptance-ambiguous` item:** PARK it, as
  [final-review.md](final-review.md) step 0.5 says, and the final review
  continues.
- **A `final-residual` item** (a final-review finding that belongs to no open
  task): park it and add it to the run's register with
  `scripts/register add <run register> "<the finding>" --state deferred --note "final review residual"`.
  Such a row keeps a `merge` finish (§Finishing).
```

11.6 In `plugins/dforge/reference/auto-run.md`, replace:

```markdown
deferred at the spec review, before the run started, counts as one the run
added. On a
```

with:

```markdown
deferred at the spec review, before the run started, counts as one the run
added. `merge` also keeps the branch when the run added a deferred row whose
Note is `final review residual`. On a
```

11.7 In `plugins/dforge/reference/final-review.md`, replace:

```markdown
   project has no manifest, say so in one line and go to step 0.5.
```

with:

```markdown
   project has no manifest, say so in one line and go to step 0.5. In an auto
   run ([auto-run.md](auto-run.md)), a red gate does not stop the review: the
   review runs, the red gate is the first finding on the one fix wave's
   list, and the gates run again after that wave; a gate still red then, or
   a manifest defect, runs
   `scripts/auto-run stop --reason "gate <name> red"` and ends as auto-run.md
   §Stopping says.
```

11.8 In `plugins/dforge/skills/using-git-worktrees/SKILL.md`, replace:

```markdown
create the worktree without asking, as `worktree=always` does ([auto-run.md](../../reference/auto-run.md)).
```

with:

```markdown
create the worktree without asking, as `worktree=always` does ([auto-run.md](../../reference/auto-run.md)). The `worktree` setting is not read: `worktree=never` creates it too, since an auto run never commits to its base branch.
```

11.9 In `plugins/dforge/skills/using-git-worktrees/SKILL.md`, replace:

```markdown
Then run setup and baseline tests in place.
```

with:

```markdown
Then run setup and baseline tests in place. In an auto run, do not work in place: run `scripts/auto-run stop --reason "the sandbox refused the execution worktree"` and end as [auto-run.md](../../reference/auto-run.md) §Stopping says.
```

11.10 In `plugins/dforge/skills/using-git-worktrees/SKILL.md`, replace:

```markdown
**If tests fail:** Report failures, ask whether to proceed or investigate.
```

with:

```markdown
**If tests fail:** Report failures, ask whether to proceed or investigate. In an auto run, ask nothing: run `scripts/auto-run ruling add "Setup: baseline tests red — <failing summary>"` and continue; the final review and finishing's first step run the suite again.
```

11.11 In `plugins/dforge/reference/finish-preference.md`, replace:

```markdown
  never stops to ask: finishing carries out the choice recorded at its
  start, or shows its menu when there is none.
```

with:

```markdown
  never stops to ask: finishing carries out the choice recorded at its
  start, or shows its menu when there is none. `get` prints a choice when
  the plan's spec carries a `Finish: <merge|pr|keep>` line in `## Decisions`,
  the spec review's answer: it reads and records that line itself, so the
  question asked there is never asked again.
```

- [ ] **Step 4: Run the suites that read these files**

Run these, one command at a time (every shell suite that names a changed file):

```bash
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/settings-skills.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/final-phase.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/inline-mode.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/process-roles.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/criteria.test.sh
```

Expected: each ends `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/reference/auto-run.md
git add plugins/dforge/reference/final-review.md
git add plugins/dforge/skills/using-git-worktrees/SKILL.md
git add plugins/dforge/reference/finish-preference.md
git add plugins/dforge/tests/auto-run-skills.test.sh
git commit -m "docs(dforge): give the references auto-run rules"
```

- [ ] **Step 6: Run the whole suite**

The controller, not the executor, runs this once the task's commit is in its checkout. `scripts/test-all.mjs` runs every shell suite and then the cockpit suite (`claude plugin test plugins/dforge`):

```bash
env -u CLAUDE_CONFIG_DIR timeout --kill-after=10s 690s node scripts/test-all.mjs
```

Expected: exit 0, no `FAIL` line, and the cockpit suite's `0 fail`.

### Task 14: Brainstorming, writing-plans and finishing text

Spec §B (brainstorming and finishing), §H (finishing), §I, §K and §O (writing-plans): the spec review writes its finish answer in the form `finish-choice get` reads and its deferrals into the run's register, writing-plans handles a listed launch at the switch, and finishing reads the choice through `get`, keeps a `merge` for a final-review residual and keeps a deferred task's rows deferred. Covers A10, A17 (keep rule), A18, A20 and A28 (writing-plans).

**Files:**
- Modify: `plugins/dforge/skills/brainstorming/SKILL.md`
- Modify: `plugins/dforge/skills/writing-plans/SKILL.md`
- Modify: `plugins/dforge/skills/finishing-a-development-branch/SKILL.md`
- Test: `plugins/dforge/tests/auto-default.test.sh`
- Test: `plugins/dforge/tests/final-phase.test.sh`

**Interfaces:**
- Consumes: C3 and C10 (the script behaviour and exit codes the new text names; C10 for test ownership).
- Produces: the skill and reference sentences pinned in this task's test files.

**Items:** 14, 21, 22, 24, 31

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Add the failing pins**

`tests/final-phase.test.sh`'s pin `finishing: only a setting-recorded choice is overwritten` is replaced, because spec §B removes that clause: `get` now records the spec's line itself, so nothing is overwritten. Every other phrase a test pins in these three files stays byte-identical, including `` `Finish: <merge|pr|keep>` line in `## Decisions`; ``, `` holds a `Finish: <action>` line, `scripts/finish-choice set <action> --plan `` (writing-plans) and `` Read `scripts/finish-choice get --plan PLAN_FILE` ``.

In `plugins/dforge/tests/auto-default.test.sh`, replace:

```bash
names "specReview never skips it" "$B" '`specReview=false` does not skip this stop.'
```

with:

```bash
names "specReview never skips it" "$B" '`specReview=false` does not skip this stop.'
names "the finish line is a bare paragraph" "$B" 'recorded as its own paragraph (no list'
names "a review deferral carries its command" "$B" '`scripts/register add <register> "A<n>: <statement>" --state deferred --note "Q: <question>"`;'
names "a review deferral opens a register" "$B" 'with no register open, first open `<docs>/registers/<date>-<spec-slug>.md`'
names "start takes the deferrals' register" "$B" '`--register <path>` when a register is open, and always the register'
W="$P/skills/writing-plans/SKILL.md"
names "writing-plans: a listed launch at the switch" "$W" '(on exit 5, wait for or stop what `scripts/in-flight` lists and run it'
FIN="$P/skills/finishing-a-development-branch/SKILL.md"
names "finishing: get reads the spec line" "$FIN" '`Finish:` line itself and records it with `"source": "spec"`, so the spec'
names "finishing: a final residual keeps a merge" "$FIN" 'the run added. `merge` also keeps when the run added a deferred row whose'
names "finishing: the final message lists residuals" "$FIN" 'it; the `final review residual` rows among them),'
names "finishing: a deferred task keeps its rows deferred" "$FIN" '`(deferred by the auto run)` is set with'
check "finishing: no read-the-spec-and-set clause" "$(grep -c 'first run `scripts/finish-choice set <action> --plan PLAN_FILE`:' "$FIN")" "0"
```

In `plugins/dforge/tests/final-phase.test.sh`, replace:

```bash
names "finishing: only a setting-recorded choice is overwritten" "$FIN" '`"source": "setting"` and no `answer` (a choice recorded any other way'
```

with:

```bash
names "finishing: get reads the spec's line" "$FIN" 'with nothing recorded in this checkout'"'"'s plan workspace it reads the spec'"'"'s'
```

- [ ] **Step 2: Run the pins to verify they fail**

Run each, one command at a time:

```bash
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-default.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/final-phase.test.sh
```

Expected: FAIL on the new pins only (the replaced pins' new text is not yet in the files); every other check passes.

- [ ] **Step 3: Edit the text**

Each old text occurs exactly once in its file; replace it with the new text exactly, including its line breaks.

12.1 In `plugins/dforge/skills/brainstorming/SKILL.md`, replace:

```markdown
     request, or keep the branch, recorded as a
     `Finish: <merge|pr|keep>` line in `## Decisions`;
```

with:

```markdown
     request, or keep the branch, recorded as its own paragraph (no list
     marker, nothing after the value) holding one
     `Finish: <merge|pr|keep>` line in `## Decisions`;
```

12.2 In `plugins/dforge/skills/brainstorming/SKILL.md`, replace:

```markdown
     a deferral writes the same `A<n>:` register row;
```

with:

```markdown
     a deferral runs
     `scripts/register add <register> "A<n>: <statement>" --state deferred --note "Q: <question>"`;
     with no register open, first open `<docs>/registers/<date>-<spec-slug>.md`
     as Opening an item register says;
```

12.3 In `plugins/dforge/skills/brainstorming/SKILL.md`, replace:

```markdown
   `--register <path>` when a register is open), then import each
```

with:

```markdown
   `--register <path>` when a register is open, and always the register
   step 5's deferrals went to), then import each
```

12.4 In `plugins/dforge/skills/writing-plans/SKILL.md`, replace:

```markdown
  PLAN_FILE`; dforge:handoff steps 0-3 only; `scripts/next-step PLAN_FILE`;
```

with:

```markdown
  PLAN_FILE`; dforge:handoff steps 0-3 only; `scripts/next-step PLAN_FILE`
  (on exit 5, wait for or stop what `scripts/in-flight` lists and run it
  again, as auto-run.md §The switch step 3 says);
```

12.5 In `plugins/dforge/skills/finishing-a-development-branch/SKILL.md`, replace:

```markdown
- **Step 4 shows no menu.** When the spec `scripts/auto-run status` names
  holds a `Finish: <action>` line in `## Decisions` and
  `scripts/finish-choice get --plan PLAN_FILE` exits 3 or prints a record with
  `"source": "setting"` and no `answer` (a choice recorded any other way
  stands), first run `scripts/finish-choice set <action> --plan PLAN_FILE`:
  writing-plans recorded it in the checkout the plan was written in, and an
  execution worktree keeps a plan workspace of its own.
  Read `scripts/finish-choice get --plan PLAN_FILE`
  (the spec review's answer, else the `finishAction` setting; exit 3 means
  `ask`) and carry out the matching option as if your human partner had chosen it, by
```

with:

```markdown
- **Step 4 shows no menu.** Read `scripts/finish-choice get --plan PLAN_FILE`:
  with nothing recorded in this checkout's plan workspace it reads the spec's
  `Finish:` line itself and records it with `"source": "spec"`, so the spec
  review's answer reaches an execution worktree too; else the `finishAction`
  setting; exit 3 means `ask`. Carry out the matching option as if your
  human partner had chosen it, by
```

12.6 In `plugins/dforge/skills/finishing-a-development-branch/SKILL.md`, replace:

```markdown
  A row deferred at the spec review, before the run started, counts as one
  the run added.
```

with:

```markdown
  A row deferred at the spec review, before the run started, counts as one
  the run added. `merge` also keeps when the run added a deferred row whose
  Note is `final review residual`.
```

12.7 In `plugins/dforge/skills/finishing-a-development-branch/SKILL.md`, replace:

```markdown
  deferred row the run added to its register (`scripts/auto-run status` names
  it), every `demo` statement of the spec, every lens
```

with:

```markdown
  deferred row the run added to its register (`scripts/auto-run status` names
  it; the `final review residual` rows among them),
  every `demo` statement of the spec, every lens
```

12.8 In `plugins/dforge/skills/finishing-a-development-branch/SKILL.md`, replace:

```markdown
  `scripts/register set <register> <id> done`, or `verify --note <what is owed>`
  when the row's acceptance names a check only your human partner can perform;
```

with:

```markdown
  `scripts/register set <register> <id> done`, or `verify --note <what is owed>`
  when the row's acceptance names a check only your human partner can perform;
  a row cited only by a task whose complete line reads
  `(deferred by the auto run)` is set with
  `scripts/register set <register> <id> deferred --note "deferred by the auto run: <the line's Ruling>"`
  instead, whichever finish action runs this step, never `done` or `verify`;
```

- [ ] **Step 4: Run the suites that read these files**

Run these, one command at a time (every shell suite that names a changed file):

```bash
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-default.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/final-phase.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/parallel-grouping.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/settings-skills.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/inline-mode.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/process-roles.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/lanes.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/gates-manifest.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/project-status.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/test-simplifier.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/turn-end.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/review-route.test.sh
env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/next-step.test.sh
```

Expected: each ends `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/brainstorming/SKILL.md
git add plugins/dforge/skills/writing-plans/SKILL.md
git add plugins/dforge/skills/finishing-a-development-branch/SKILL.md
git add plugins/dforge/tests/auto-default.test.sh
git add plugins/dforge/tests/final-phase.test.sh
git commit -m "docs(dforge): read the finish line and keep deferrals"
```

- [ ] **Step 6: Run the whole suite**

The controller, not the executor, runs this once the task's commit is in its checkout. `scripts/test-all.mjs` runs every shell suite and then the cockpit suite (`claude plugin test plugins/dforge`):

```bash
env -u CLAUDE_CONFIG_DIR timeout --kill-after=10s 690s node scripts/test-all.mjs
```

Expected: exit 0, no `FAIL` line, and the cockpit suite's `0 fail`.

### Task 15: Release dforge 4.1.0

**Files:**
- Modify: `plugins/dforge/.claude-plugin/plugin.json`
- Modify: `plugins/dforge/.codex-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Test: `plugins/dforge/tests/review-route.test.sh`

**Interfaces:**
- Consumes: none
- Produces: none

**Items:** 26

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

The 4.0.0 release (`git show ac5ee96`) changed exactly these four files; this
release follows it. `auto-run start` now needs a live cockpit, a behaviour
change, hence a minor version.

- [ ] **Step 1: Change the version pins**

In `plugins/dforge/tests/review-route.test.sh`, replace:

```bash
present "the Claude manifest is 4.0.0" "$P/.claude-plugin/plugin.json" '"version": "4.0.0"'
present "the Codex manifest is 4.0.0" "$P/.codex-plugin/plugin.json" '"version": "4.0.0"'
```

with:

```bash
present "the Claude manifest is 4.1.0" "$P/.claude-plugin/plugin.json" '"version": "4.1.0"'
present "the Codex manifest is 4.1.0" "$P/.codex-plugin/plugin.json" '"version": "4.1.0"'
```

- [ ] **Step 2: Run it to see it fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/review-route.test.sh`
Expected: FAIL on `the Claude manifest is 4.1.0` and `the Codex manifest is 4.1.0`.

- [ ] **Step 3: Bump the versions**

In `plugins/dforge/.claude-plugin/plugin.json` and in
`plugins/dforge/.codex-plugin/plugin.json`, replace `"version": "4.0.0",` with
`"version": "4.1.0",`. In `.claude-plugin/marketplace.json`, replace
`"version": "0.7.0",` with `"version": "0.8.0",`.

- [ ] **Step 4: Run the checks**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/review-route.test.sh`
Expected: PASS (`0 failed`).

Run: `timeout 120 node scripts/validate-repository.mjs`
Expected: `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`

Run: `env -u CLAUDE_CONFIG_DIR timeout 120 /root/.local/bin/claude plugin validate .`
Expected: validation passes.

Run: `env -u CLAUDE_CONFIG_DIR timeout 120 /root/.local/bin/claude plugin validate plugins/dforge`
Expected: validation passes.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/.claude-plugin/plugin.json plugins/dforge/.codex-plugin/plugin.json .claude-plugin/marketplace.json plugins/dforge/tests/review-route.test.sh
git commit -m "chore(dforge): release 4.1.0"
```

### Task 16: Probe the fixed flow on a real engine

**Files:**
- none in the repository: everything lives under `/tmp/dforge-reliability-probe`

**Interfaces:**
- Consumes: C3, C4, C6, C7 (the behaviour every earlier task built)
- Produces: none

**Items:** 13, 14

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 1 = 3

This is spec A29 and A30: a real auto run and a real attended run of a
one-task plan, in a fresh scratch repository, driven through tmux. It needs
real model turns and runs for 15 to 30 minutes. `<worktree>` below is this
plan's worktree root, absolute. It never touches this repository, never
copies `.credentials.json`, and uses its own `HOME` so the owner's
`~/.dforge` (settings, darkmem stores, run registry) is never read. Record
every observation with the date in your report; commit nothing.

- [ ] **Step 1: Write and run the setup script**

Write `/tmp/dforge-reliability-probe-setup.sh` with exactly this content,
then run `bash /tmp/dforge-reliability-probe-setup.sh <worktree>`:

```bash
set -eu
WT=$1
P=/tmp/dforge-reliability-probe
NODE_BIN=$(dirname "$(command -v node)")
rm -rf "$P"
mkdir -p "$P/home/.dforge" "$P/repo/docs/dforge/specs" "$P/repo/docs/dforge/registers"
printf '{}\n' > "$P/home/.dforge/config.json"
jq -S '{model, modelSettings}' /root/.claude-alt/settings.json > "$P/defaults-before.json"
cd "$P/repo"
git init -q -b main
git config user.name probe
git config user.email probe@example.invalid
printf '.dforge/\n.claude/\n' > .gitignore
cat > docs/dforge/specs/2026-10-19-greet-design.md <<'SPEC'
# Greet script

**Execution strategy:** sequential — one small change in one file and its test.

**Register:** docs/dforge/registers/2026-10-19-greet.md

## Decisions

The owner's answers at the spec review.

1. Finish: "Keep the branch" — keep the finished branch for a look.

Finish: keep

## Problem

The repository has no way to greet someone from the shell.

## Design

Add `bin/greet`, an executable bash script. With one argument it prints
`Hello, <name>!` and exits 0. With no argument it prints `Hello, world!` and
exits 0. With two or more arguments it prints `usage: greet [name]` to stderr
and exits 2. `tests/greet.test.sh` runs the three cases and exits nonzero on
the first mismatch.

## Acceptance

A1. [test, high] `bin/greet Ada` prints `Hello, Ada!` and exits 0.
A2. [test, high] `bin/greet` prints `Hello, world!` and exits 0.
A3. [test, neg, high] `bin/greet a b` prints `usage: greet [name]` to stderr, nothing to stdout, and exits 2.
SPEC
printf '# Greet script\n\n**Source:** probe\n**Covers:** docs/dforge/specs/2026-10-19-greet-design.md\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n' > docs/dforge/registers/2026-10-19-greet.md
HOME="$P/home" bash "$WT/plugins/dforge/scripts/register" add docs/dforge/registers/2026-10-19-greet.md "add a greet script" >/dev/null
git add -A
git commit -q -m "docs: greet spec"
cat > "$P/arm.sh" <<ARM
set -u
cd "$P/repo"
bash "$WT/plugins/dforge/scripts/auto-run" start --spec docs/dforge/specs/2026-10-19-greet-design.md --register docs/dforge/registers/2026-10-19-greet.md || { echo "auto-run start: exit \$?"; exit 1; }
echo armed
ARM
printf '{}\n' > "$P/settings.json"
for leg in 1 2; do
  model=opus
  [ "$leg" = 2 ] && model="sonnet --effort low"
  cat > "$P/launch$leg.sh" <<LAUNCH
cd "\$1"
exec env -i HOME=$P/home PATH=$NODE_BIN:/root/.local/bin:/usr/local/bin:/usr/bin:/bin CLAUDE_CONFIG_DIR=/root/.claude-alt IS_SANDBOX=1 TERM=xterm-256color /root/.local/bin/claude --model $model --dangerously-skip-permissions --setting-sources project,local --settings "$P/settings.json" --plugin-dir "$WT/plugins/dforge"
LAUNCH
done
tmux new-session -d -s dforge-probe-leg1 -x 200 -y 50 "bash $P/launch1.sh $P/repo"
echo started
```

- [ ] **Step 2: Start leg 1 (the auto run)**

Drive the session with single commands: `tmux capture-pane -p -t dforge-probe-leg1`
reads the screen; `tmux send-keys -t dforge-probe-leg1 <keys>` answers it. The
folder-trust dialog starts on "No, exit": send `Down`, then `Enter`. When the
prompt box shows `bypass permissions on`, send, as one `-l` literal, then `Enter`:

```
Run bash /tmp/dforge-reliability-probe/arm.sh. If it does not print armed, say so and stop. Otherwise: the spec docs/dforge/specs/2026-10-19-greet-design.md was approved at the spec review just now with Approve and run unattended, and the auto run is bound to this session. Continue as dforge:brainstorming step 6 (Start the run) says after the start command: invoke dforge:writing-plans in this session and follow the auto run through the switch.
```

If the reply says `auto-run start: exit 2`, the cockpit's heartbeat did not
reach the script: report BLOCKED with the pane text.

- [ ] **Step 3: Observe leg 1 until the run stops**

Write `/tmp/dforge-reliability-probe-observe.sh` with exactly this content:

```bash
P=/tmp/dforge-reliability-probe
R=${1:-$P/repo}
S="$R/.dforge/sdd/auto-run.json"
date -u +%FT%TZ
jq -c '{active, session, phase, pending, setupDue, compactions, stalls, stopped}' "$S" 2>/dev/null || echo "auto-run.json: none"
git -C "$R" worktree list
echo "main: $(git -C "$R" log --format=%s main | paste -sd'|' -)"
for w in $(git -C "$R" worktree list --porcelain | awk '/^worktree /{print $2}'); do
  for f in "$w"/.dforge/sdd/*/progress.md; do [ -f "$f" ] && echo "ledger: $f" && tail -n 3 "$f"; done
done
if diff -q <(jq -S '{model, modelSettings}' /root/.claude-alt/settings.json) "$P/defaults-before.json" >/dev/null; then echo "defaults: unchanged"; else echo "defaults: CHANGED"; fi
```

Run `bash /tmp/dforge-reliability-probe-observe.sh` about every 60 seconds
(a Monitor until-loop, or one call at a time) until `active` is `false`, or
for at most 30 minutes. Polling shows progress only; the ordering proof is
the transcript check below. The session must ask nothing; if the pane shows
a question, record it (a finding), answer nothing, and continue observing.

When `active` is `false`, write `/tmp/dforge-reliability-probe-order.sh`
with exactly this content and run it once:

```bash
P=/tmp/dforge-reliability-probe
S="$P/repo/.dforge/sdd/auto-run.json"
sid=$(jq -r .session "$S")
T=$(ls /root/.claude-alt/projects/*/"$sid".jsonl 2>/dev/null | head -n 1)
echo "session: $sid"
echo "transcript: ${T:-none}"
[ -n "$T" ] || exit 1
echo "compact boundaries: $(grep -c '"compact_boundary"' "$T")"
echo "newer transcripts in that project: $(find "$(dirname "$T")" -name '*.jsonl' -newer "$T" | grep -c .)"
echo "assistant models: $(jq -r 'select(.type == "assistant") | .message.model // empty' "$T" | uniq | paste -sd' ' -)"
plan=$(jq -r .plan "$S")
slug=$(basename "$plan" .md)
echo "primary ledger: $([ -e "$P/repo/.dforge/sdd/$slug/progress.md" ] && echo present || echo absent)"
echo "primary task files: $(cd "$P/repo" && ls bin/greet tests/greet.test.sh 2>/dev/null | grep -c .)"
for w in $(git -C "$P/repo" worktree list --porcelain | awk '/^worktree /{print $2}' | grep -v "^$P/repo\$" | grep -v qa-mutation); do
  f="$w/.dforge/sdd/$slug/progress.md"
  [ -f "$f" ] && echo "execution ledger: $w" && grep -m 1 '^Task 1: implementer' "$f"
done
```

Expected, by the end: the plan was written and attached; `pending` went
`switch`, `switch-resume`, `after-compact`; the order check prints exactly
one `session` throughout (the `session` field never changed in the polls),
`compact boundaries` at least 1, `newer transcripts in that project: 0` (no
`/clear`), `assistant models` ending with a Sonnet model, `primary ledger: absent`,
`primary task files: 0`, and one `execution ledger:` line naming a linked
worktree followed by its `Task 1: implementer … (assigned; …)` line (Task 1
was assigned inside the execution worktree, so the worktree came first); `main`'s subjects are only the spec commit and the plan commit
(no `feat`, `test` or `fix` subject); the ledger with `Task 1: complete` is in
the execution worktree at `.dforge/sdd/<plan basename>/progress.md`; `active`
ends `false` with `stopped` null; the worktree's branch still exists (finish
`keep`); `defaults: unchanged`.

- [ ] **Step 4: Run leg 2 (the attended run)**

Record the plan commit: `git -C /tmp/dforge-reliability-probe/repo log --format=%h -1 --grep=plan main`.
Kill leg 1: `tmux kill-session -t dforge-probe-leg1`. Then, one command each:

```bash
git clone -q --no-local /tmp/dforge-reliability-probe/repo /tmp/dforge-reliability-probe/repo2
git -C /tmp/dforge-reliability-probe/repo2 reset -q --hard <the plan commit>
git -C /tmp/dforge-reliability-probe/repo2 remote remove origin
git -C /tmp/dforge-reliability-probe/repo2 config user.name probe
git -C /tmp/dforge-reliability-probe/repo2 config user.email probe@example.invalid
tmux new-session -d -s dforge-probe-leg2 -x 200 -y 50 "bash /tmp/dforge-reliability-probe/launch2.sh /tmp/dforge-reliability-probe/repo2"
```

Accept the folder-trust dialog as in Step 2, then send the first prompt from
leg 1's handoff (`sed -n '/Paste as the first prompt:/,$p' /tmp/dforge-reliability-probe/repo/.dforge/handoff/latest.md`
shows it; it begins `Continue` and names Setup). Answer a worktree consent
question with `create a worktree`. Observe with
`bash /tmp/dforge-reliability-probe-observe.sh /tmp/dforge-reliability-probe/repo2`
and the pane until the session's last message says the branch was kept, or
for at most 30 minutes.

Expected: the session never asks what to do when the implementation is done
(no "Before I start: when the implementation is done" question, no finish
menu); the ledger is at `.dforge/sdd/<plan basename>/progress.md` inside the
execution worktree (not under a `docs/` subdirectory); `main` in `repo2`
gains no commit.

- [ ] **Step 5: Clean up, whether the probe passed or not**

Write `/tmp/dforge-reliability-probe-cleanup.sh` with exactly this content and
run it:

```bash
P=/tmp/dforge-reliability-probe
tmux kill-session -t dforge-probe-leg1 2>/dev/null
tmux kill-session -t dforge-probe-leg2 2>/dev/null
if [ -f "$P/defaults-before.json" ] && ! diff -q <(jq -S '{model, modelSettings}' /root/.claude-alt/settings.json) "$P/defaults-before.json" >/dev/null; then
  tmp=$(mktemp)
  jq --slurpfile d "$P/defaults-before.json" '(if $d[0].model == null then del(.model) else .model = $d[0].model end) | (if $d[0].modelSettings == null then del(.modelSettings) else .modelSettings = $d[0].modelSettings end)' /root/.claude-alt/settings.json > "$tmp" && mv "$tmp" /root/.claude-alt/settings.json && echo "restored the owner's model defaults"
fi
rm -rf "$P" /tmp/dforge-reliability-probe-setup.sh /tmp/dforge-reliability-probe-observe.sh /tmp/dforge-reliability-probe-order.sh
echo cleaned
```

Then delete the cleanup script itself with `rm -f /tmp/dforge-reliability-probe-cleanup.sh`.
If it printed `restored the owner's model defaults`, say so in your report:
that is a finding against Task 9.

If any expectation in Step 3 or Step 4 fails, report BLOCKED with the
observations; commit nothing from this task.
