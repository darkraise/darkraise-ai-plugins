# Auto Execution Default Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make dforge's auto run the default on Claude Code: one spec review is the owner's only stop, the plan is written and executed in the same session through an in-place switch, plans prefer parallel waves, and nothing hands off once the last task is complete.

**Architecture:** `scripts/auto-run` gains a `switch` command, a `compacted --switch` booking and phases that never hand off; the Stop hook and the cockpit carry the new `Auto run: switching` stage (compact, then `/model` and `/effort` and the first prompt, with no `/clear`); `context-size --final` never hands off; the settings default to `autoRun=on` and `executionStrategy=parallel`; and the skills and references describe the new flow.

**Tech Stack:** Bash scripts with shell test suites, a Node.js ESM settings schema, the TypeScript cockpit mod (tested by `claude plugin test`), Markdown skills and docs.

**Spec:** `docs/superpowers/specs/2026-10-18-auto-execution-default-design.md`

**Execution:** subagent — `claude --model sonnet --effort high` — the plan runs parallel waves (Tasks 1-2)

**Plan review:** 2026-10-19 — dr-superpowers:judge-opus — executability 16 / coherence 16 / coverage 17 / assumptions 15 (round 2)

**Parallelism:** waves — 1-2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10

**Integration check:** `env -u CLAUDE_CONFIG_DIR timeout --kill-after=10s 690s node scripts/test-all.mjs`, then `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`, both from the worktree root

**Worktree setup:** none

> **External executors:** codex

## Global Constraints

- Work in a worktree branched from local `main` (local `main` runs 390 commits ahead of `origin/main`): `git worktree add .claude/worktrees/auto-execution-default -b auto-execution-default main`. This plan, its spec and its register must be on local `main` first: before Task 1, `ls docs/superpowers/plans/2026-10-19-auto-execution-default.md` in the worktree must list the file, or stop. Do not push.
- Never edit anything under `docs/superpowers/`: it is history (register rows are set by the execution skill's own scripts, not by hand).
- Run each command on its own line; do not chain commands that mention git with `&&`, `;` or a pipe (the worktree guard refuses them).
- Run suites from the worktree root under a bound, with the host's `CLAUDE_CONFIG_DIR` removed: `env -u CLAUDE_CONFIG_DIR timeout 300 <command>`. In this host's Bash `claude` is a shell function that exits 127: call `/root/.local/bin/claude`.
- Commits: `<type>(<scope>): <subject>`, subject at most 50 characters, imperative, no period; author and committer `Darkraise <quangtc94@gmail.com>` (the repository's `user.name`/`user.email`); no `Co-Authored-By:`, `Claude-Session:` or "Generated with" line, nor any other AI attribution.
- No version bump in any manifest: a release is a separate commit the owner asks for.
- An edit's old text that is not found exactly once is a stop: report BLOCKED with the file and the text. Never paraphrase an edit; copy the new text exactly, including its line breaks.
- `plugins/dforge/skills/using-dforge/SKILL.md` stays at or below 5,100 bytes (`tests/hook.test.sh` checks it).
- Every wave must leave the whole suite green. A phrase that a test file this task does not own pins (`grep -F` in `plugins/dforge/tests/`) stays byte-identical. Before committing, run every shell test file that names a file this task changed: `grep -l <basename> plugins/dforge/tests/*.sh`.
- Prose wraps at 80 columns like the surrounding text, except where a new text block below wraps differently: copy those as written.
- Stop every process a check starts. Task 6's probe is the one step that starts a long-lived process (a nested Claude Code session in tmux); it kills its own tmux session and nothing else.

## Contracts

- **C1 `scripts/auto-run` (Task 1).** New commands: `switch` (exit 0 sets `pending` to `switch` and `phase` to `execute`, stores `resumePrompt` and `launch` read from `latest.md` as `clear` reads them, and leaves `resumes` and `rebind` unchanged; exit 4 when no plan is attached or when the first prompt in `latest.md` does not contain the attached plan's basename; exit 1 when `latest.md` has no first prompt) and `compacted --switch` (counts the compaction, resets `failures`, sets `pending` to `switch-resume`). `resumed` turns a pending `switch-resume` into `after-compact`. `pending` can print `switch` and `switch-resume`. The state gains `finalCompacted` (boolean): `compacted` with or without `--switch` sets it when `phase` is `final` or `finish`, and once it is true `verdict` never answers `compact`. In the `plan`, `final` and `finish` phases a compaction never hands off: `after-compact` prints `continue` (exit 0), and a booked compaction that would have handed off takes the `high` regime.
- **C2 The switching sentinel (Tasks 2, 6).** The line `Auto run: switching`, as the last non-blank line of a turn, answers pending `switch`. The Stop hook lets it through only then; the cockpit's `AUTO_SENTINELS.switch` is that text.
- **C3 The cockpit's switch (Task 6).** Stage `switch` (pending `switch`): compact with instructions containing `Drop the design conversation`, then `auto-run compacted --switch`. Stage `switch-resume` (pending `switch-resume`): `/model` and `/effort` from `launch`, the user-default restore, then submit `Run \`bash <plugin-root>/scripts/auto-run after-compact\` first. ` followed by `resumePrompt`, then `auto-run resumed`; a nonzero `resumed` after a switch stops the run with `the cockpit switched but could not book it`, since the first prompt is already submitted. A failure in either stage is booked as `failure --reason "the cockpit could not switch: <why>"` and retried in that stage. No engine compaction is booked while `switch` or `switch-resume` is pending.
- **C4 Settings (Task 3).** `autoRun`: values `on | ask | off`, default `on`. `executionStrategy`: values `ask | sequential | parallel`, default `parallel`.
- **C5 `scripts/context-size --final` (Task 4).** Outside an auto run it never exits 5; over its limit its line reads `… — ok — source: …`. `--tail` and every other mode are unchanged. While a run is bound, `--final` prints the run's own line as today (C1's rules: no handoff in `final` or `finish`; a `handoff` already pending from an execute-phase compaction that left 85% of the window still clears, since that session is full).
- **C6 Names the skills share (Tasks 5, 7, 8, 9, 10).** `reference/auto-run.md` gains `## The switch`; `skills/brainstorming/SKILL.md` gains `## Auto by default (\`autoRun=on\`)`. A spec written under `autoRun=on` carries `## Decisions` (with an optional `Finish: <merge|pr|keep>` line) and `## Review rulings` sections. writing-plans records a `Finish:` line with `scripts/finish-choice set <action> --plan PLAN_FILE`; finishing in an auto run reads `scripts/finish-choice get --plan PLAN_FILE` before `finishAction`.
- **C7 Test ownership.** `tests/settings-skills.test.sh` belongs to Task 8, which replaces its writing-plans `clear --phase` pin with `` `scripts/auto-run switch` and end the turn with `Auto run: switching` ``. `tests/auto-run-skills.test.sh` belongs to Task 10. Tasks 7 and 9 create `tests/auto-default.test.sh` and `tests/final-phase.test.sh`; Task 8 creates `tests/parallel-grouping.test.sh`.

## Assumptions (evidence)

- **New shell suites are picked up without registration.** `scripts/test-all.mjs:53` runs every `plugins/dforge/tests/*.test.sh` (read 2026-10-19).
- **The cockpit's own compaction does not book itself twice.** The `session.compact` handler books only `trigger` `auto` or `manual` (`plugins/dforge/hooks/cockpit/register.tsx:403`); the stage's own call books through `autoRunCall` (`register.tsx:2340`).
- **The first prompt names the plan.** `scripts/next-step` builds it as ``Continue `$rel` with dforge:$skill.`` or ``Resume `$rel` …`` (`plugins/dforge/scripts/next-step:454-456`), so a basename check suffices for `switch`.
- **Nothing reads `context-size --final`'s exit 5 except the skills.** `grep -rn -- "--final" plugins/dforge/scripts plugins/dforge/hooks` found only `review-route`, `lens-route` and `context-size` itself on 2026-10-19.
- **`finish-choice` takes `--plan` anywhere in its arguments** (`plugins/dforge/scripts/finish-choice:32-38`).
- **The Codex lane is on.** `codex-gate` printed `usable=true reason=ok review=true lane=true resets_at=- source=probe` on 2026-10-19; the constraint in `docs/superpowers/distilled/constraints.md` ticks `codex` without asking. Every task with total 2-4 and risk at most 1 carries an `**Executor:**` line and so runs alone in its wave, which is why waves 3-10 hold one task each.
- **The executor tasks' tests run in the Codex sandbox.** The lane refuses tasks whose tests spawn piped Node child processes; "Bash pipes, and child processes with stdio `inherit` or `ignore`, are unaffected" (`plugins/dforge/reference/executor-lane.md:109-115`). The executor tasks' tests are shell suites whose Node use is a Bash pipe into `node -e`, `node scripts/validate-repository.mjs`, and (Task 7's `hook.test.sh`, through `session-start.sh` and `roots.sh`) `darkmem-config.mjs`, whose piped `spawnSync` (`plugins/dforge/scripts/lib/darkmem-config.mjs:35`) runs inside a `$(…)` subshell whose failure falls back to the checkout's paths; if Task 7's `hook.test.sh` fails only in the sandbox, that is a handback, not a code fault; `grep -n "spawnSync\|execSync\|execFileSync"` over `scripts/validate-repository.mjs`, `plugins/dforge/scripts/lib/dforge-config.mjs` and `plugins/dforge/config/schema.mjs` printed nothing on 2026-10-19.
- **A bound run's `--final` keeps the run's verdict (C5).** Converting a pending handoff into `ok` would leave a session at 85% of its window running the final review; the spec's A14 is amended to "outside an auto run", and A15 covers the auto run.
- **No cockpit test pins the changed defaults.** `grep -n "Strategy\|executionStrategy\|autoRun:" plugins/dforge/tests/cockpit.test.ts plugins/dforge/hooks/cockpit/*` printed nothing on 2026-10-19.
- **The in-place switch works on a real engine:** unverified — Task 6 verifies it (its last step), once Tasks 1 and 2 have landed.
- **A13 and A12 are checked where they can be.** A13's planner behaviour is a skill instruction, pinned by Task 8; A12 is the demo Task 6's probe performs, and the final review's acceptance QA lists it.

## Task index

1. Auto-run switch and held phases
2. Stop hook switching line
3. Auto-run and strategy defaults
4. Final phase never hands off
5. Auto-run references
6. Cockpit in-place switch
7. Brainstorming auto by default
8. Writing-plans grouping and switch
9. Execution skills keep going
10. README and auto-run pins

---

### Task 1: Auto-run switch and held phases

**Files:**
- Modify: `plugins/dforge/scripts/lib/auto-run.sh`
- Modify: `plugins/dforge/scripts/auto-run`
- Test: `plugins/dforge/tests/auto-run.test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: C1.

**Items:** 1, 3

**Depends on:** none

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/auto-run.test.sh`, replace:

```text
check "resumed resets the failures" "$(field failures):$(field pending)" "0:null"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
```

with:

```text
check "resumed resets the failures" "$(field failures):$(field pending)" "0:null"

# --- the switch (reference/auto-run.md §The switch) ---
ar --session s-1 stop
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
ar --session s-1 switch >/dev/null 2>&1; status=$?
check "switch without a plan: exit 4, nothing pending" "$status:$(field pending)" "4:null"
ar --session s-1 attach --plan docs/other.md
ar --session s-1 switch >/dev/null 2>&1; status=$?
check "switch: a first prompt naming another plan: exit 4" "$status:$(field pending)" "4:null"
ar --session s-1 attach --plan docs/plan.md
ar --session s-1 phase plan
ar --session s-1 switch; status=$?
check "switch: exit 0, switch pending" "$status:$(field pending)" "0:switch"
check "switch: the phase moves to execute" "$(field phase)" "execute"
check "switch: the first prompt" "$(field resumePrompt)" "Execute docs/plan.md with dforge:subagent-driven-development."
check "switch: the launch" "$(jq -r '.launch | "\(.model) \(.effort)"' "$STATE")" "sonnet high"
check "switch: not a self-resume, no rebind" "$(field resumes):$(field rebind)" "0:false"
check "pending prints switch" "$(ar --session s-1 pending)" "switch"
ar --session s-1 compacted --switch
check "compacted --switch: counted, switch-resume pending" "$(field compactions):$(field pending)" "1:switch-resume"
check "the switch's compaction is not a final-phase one" "$(field finalCompacted)" "false"
ar --session s-1 resumed
check "resumed after a switch: after-compact is due" "$(field pending)" "after-compact"
asst 700000 > "$T"
out=$(after); status=$?
check "after a switch, an oversized context still hands off" "$status:${out%% *}" "5:handoff"
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
ar --session s-1 attach --plan docs/plan.md
ar --session s-1 phase plan
ar --session s-1 switch
ar --session s-1 compacted --switch
ar --session s-1 resumed
asst 30000 > "$T"
out=$(after); status=$?
check "after a switch, a small context continues" "$status:${out%% *}:$(field pending)" "0:continue:null"
ar --session s-1 compacted --what >/dev/null 2>&1; status=$?
check "compacted with another flag: exit 2" "$status" "2"

# --- the plan, final and finish phases never hand off ---
for phase in plan final finish; do
  ar --session s-1 phase "$phase"
  ar --session s-1 compacted
  asst 700000 > "$T"
  out=$(after); status=$?
  check "after-compact in $phase: 85% of the window continues" "$status:${out%% *}:$(field pending)" "0:continue:null"
done
ar --session s-1 phase execute
ar --session s-1 compacted
out=$(after); status=$?
check "after-compact in execute: 85% of the window still hands off" "$status:${out%% *}" "5:handoff"

# --- once a final-phase compaction ran, every budget line is ok ---
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
ar --session s-1 phase final
out=$(verdict --tokens 465000); status=$?
check "final, before a compaction: at the budget, compact" "$status:${out%% *}" "6:compact"
ar --session s-1 compacted
check "a final-phase compaction is recorded" "$(field finalCompacted)" "true"
out=$(verdict --tokens 750000); status=$?
check "final, after a compaction: ok above the high limit" "$status:${out%% *}:$(field pending)" "0:ok:null"
ar --session s-1 phase finish
out=$(verdict --tokens 900000); status=$?
check "finish, after a final-phase compaction: ok" "$status:${out%% *}" "0:ok"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run.test.sh`
Expected: FAIL lines for the switch checks (`switch` is an unknown command, exit 2), for `compacted --switch` and for the held-phase checks.

- [ ] **Step 3: Implement**

In `plugins/dforge/scripts/lib/auto-run.sh`, replace:

```text
# ar_clear PHASE — the cleared session's first prompt and launch, from the
# handoff scripts/next-step just wrote. PHASE 1 for a phase clear; otherwise
# the clear is a self-resume, and the AR_RESUME_CAP-th in a row stops the run
# (return 5).
ar_clear() {
  local is_phase=$1 primary latest prompt="" launch model="" effort="" resumes
  primary=$(ar_primary_root) || return 1
  dforge_stores_init "$primary"
  latest=$(dforge_latest_file "$primary")
  [ -f "$latest" ] && prompt=$(ar_fenced "$latest" 'Paste as the first prompt:')
  [ -n "$prompt" ] || { echo "auto-run: no first prompt in $latest; run scripts/next-step first" >&2; return 1; }
  launch=$(ar_fenced "$latest" 'Launch in ' | head -n 1)
  if [[ $launch =~ claude\ --model\ ([^ ]+)\ --effort\ ([^ ]+) ]]; then
    model=${BASH_REMATCH[1]} effort=${BASH_REMATCH[2]}
  fi
  if [ "$is_phase" != 1 ]; then
```

with:

```text
# ar_handoff — the first prompt and launch from the handoff scripts/next-step
# just wrote, into AR_PROMPT, AR_MODEL and AR_EFFORT.
ar_handoff() {
  local primary latest launch
  AR_PROMPT="" AR_MODEL="" AR_EFFORT=""
  primary=$(ar_primary_root) || return 1
  dforge_stores_init "$primary"
  latest=$(dforge_latest_file "$primary")
  [ -f "$latest" ] && AR_PROMPT=$(ar_fenced "$latest" 'Paste as the first prompt:')
  [ -n "$AR_PROMPT" ] || { echo "auto-run: no first prompt in $latest; run scripts/next-step first" >&2; return 1; }
  launch=$(ar_fenced "$latest" 'Launch in ' | head -n 1)
  if [[ $launch =~ claude\ --model\ ([^ ]+)\ --effort\ ([^ ]+) ]]; then
    AR_MODEL=${BASH_REMATCH[1]} AR_EFFORT=${BASH_REMATCH[2]}
  fi
}

# ar_switch — at plan saved, the in-place move to execution: the first prompt
# and launch as ar_clear reads them. Refuses (return 4) without an attached
# plan, or when the first prompt names another plan. Never a self-resume. The
# phase moves to execute, so the switch's compaction is measured under
# execution's rules and an oversized one still hands off.
ar_switch() {
  local plan
  plan=$(ar_get plan)
  [ -n "$plan" ] || { echo "auto-run: no plan is attached; run auto-run attach --plan first" >&2; return 4; }
  ar_handoff || return 1
  [[ $AR_PROMPT == *"$(basename "$plan")"* ]] \
    || { echo "auto-run: the handoff's first prompt names another plan than $plan; run scripts/next-step $plan again" >&2; return 4; }
  ar_update '.pending = "switch" | .phase = "execute" | .resumePrompt = $p
    | .launch = (if $m == "" then null else {model: $m, effort: $e} end)' \
    --arg p "$AR_PROMPT" --arg m "$AR_MODEL" --arg e "$AR_EFFORT"
}

# ar_clear PHASE — the cleared session's first prompt and launch, from the
# handoff scripts/next-step just wrote. PHASE 1 for a phase clear; otherwise
# the clear is a self-resume, and the AR_RESUME_CAP-th in a row stops the run
# (return 5).
ar_clear() {
  local is_phase=$1 resumes
  ar_handoff || return 1
  if [ "$is_phase" != 1 ]; then
```

Then replace:

```text
  ar_update '.pending = "clear" | .rebind = true | .resumePrompt = $p
    | .launch = (if $m == "" then null else {model: $m, effort: $e} end)' \
    --arg p "$prompt" --arg m "$model" --arg e "$effort"
}
```

with:

```text
  ar_update '.pending = "clear" | .rebind = true | .resumePrompt = $p
    | .launch = (if $m == "" then null else {model: $m, effort: $e} end)' \
    --arg p "$AR_PROMPT" --arg m "$AR_MODEL" --arg e "$AR_EFFORT"
}
```

Then replace:

```text
ar_resumed() { ar_update '.failures = 0 | if .pending == "resume" then .pending = null else . end'; }

ar_compacted() { ar_update '.compactions += 1 | .failures = 0 | .pending = "after-compact"'; }
```

with:

```text
# ar_resumed — the cockpit submitted its stage's prompt. After a switch the
# compaction is still to be measured, so after-compact becomes due.
ar_resumed() {
  ar_update '.failures = 0
    | if .pending == "resume" then .pending = null
      elif .pending == "switch-resume" then .pending = "after-compact"
      else . end'
}

# ar_compacted [--switch] — book a compaction; the switch's own leaves its
# resume stage due. One in the final or finish phase sets finalCompacted, after
# which every budget line of the run says ok.
ar_compacted() {
  local next=after-compact
  [ "${1:-}" = --switch ] && next=switch-resume
  ar_update '.compactions += 1 | .failures = 0 | .pending = $n
    | .finalCompacted = ((.finalCompacted // false) or .phase == "final" or .phase == "finish")' --arg n "$next"
}
```

Then replace:

```text
# ar_settle P BUDGET WINDOW — apply the after-compaction rule to the run: set
# the regime, clear pending, print continue; a handoff keeps the regime and
# stays pending until clear.
ar_settle() {
  local result
  result=$(ar_after "$1" "$2" "$3")
  if [ "$result" = handoff ]; then
```

with:

```text
# ar_holds_session — true in the phases no compaction hands off from: the plan
# is written, and the final review and finishing run, in this session.
ar_holds_session() {
  ar_state | ar_jq -e '.phase == "plan" or .phase == "final" or .phase == "finish"' >/dev/null 2>&1
}

# ar_settle P BUDGET WINDOW — apply the after-compaction rule to the run: set
# the regime, clear pending, print continue; a handoff keeps the regime and
# stays pending until clear. A phase that holds the session takes the high
# regime instead of a handoff.
ar_settle() {
  local result
  result=$(ar_after "$1" "$2" "$3")
  if [ "$result" = handoff ] && ar_holds_session; then result=high; fi
  if [ "$result" = handoff ]; then
```

Then replace:

```text
# size; a pending clear is a handoff in progress. An ok clears a compaction a
# wider wave probe requested.
```

with:

```text
# size; a pending clear is a handoff in progress. An ok clears a compaction a
# wider wave probe requested. Once a compaction ran in the final phases
# (finalCompacted) it never asks for another: Claude Code's own is the backstop.
```

Then replace:

```text
  elif [ "$tokens" -ge "$limit" ]; then
    ar_update '.pending = "compact"' || return 1
```

with:

```text
  elif [ "$tokens" -ge "$limit" ] && ! ar_state | ar_jq -e '.finalCompacted == true' >/dev/null 2>&1; then
    ar_update '.pending = "compact"' || return 1
```

In `plugins/dforge/scripts/auto-run`, replace:

```text
       auto-run [--session ID] status | pending | task-complete | compacted | resumed
```

with:

```text
       auto-run [--session ID] status | pending | task-complete | resumed | switch
       auto-run [--session ID] compacted [--switch]
```

Then replace:

```text
pending prints compact, after-compact, handoff, clear, resume or none.
```

with:

```text
pending prints compact, after-compact, handoff, clear, resume, switch, switch-resume or none.
```

Then replace:

```text
  compacted) [ $# -eq 0 ] || usage; bound; ar_compacted ;;
```

with:

```text
  compacted)
    case "$#:${1:-}" in
      0:) bound; ar_compacted ;;
      1:--switch) bound; ar_compacted --switch ;;
      *) usage ;;
    esac
    ;;
  switch) [ $# -eq 0 ] || usage; bound; ar_switch ;;
```

Then replace:

```text
      regime=$(ar_after "$tokens" "$budget" "$window")
      if [ "$regime" = handoff ]; then result=handoff regime=$(ar_get regime); else result=continue; fi
```

with:

```text
      regime=$(ar_after "$tokens" "$budget" "$window")
      if [ "$regime" = handoff ] && ! ar_holds_session; then result=handoff regime=$(ar_get regime)
      else
        result=continue
        [ "$regime" != handoff ] || regime=$(ar_get regime)
      fi
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run.test.sh`
Expected: `0 failed`.
Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/context-size.test.sh`, then `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/budget-line.test.sh`, then `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/turn-end.test.sh`
Expected: each `0 failed` (they source or call `auto-run`).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/auto-run.sh plugins/dforge/scripts/auto-run plugins/dforge/tests/auto-run.test.sh
git commit -m "feat(dforge): add the auto-run in-place switch"
```

### Task 2: Stop hook switching line

**Files:**
- Modify: `plugins/dforge/scripts/turn-end.sh`
- Test: `plugins/dforge/tests/turn-end.test.sh`

**Interfaces:**
- Consumes: nothing another task produces: the pending names are fixed by C1 and read through the existing `auto-run pending`.
- Produces: C2 (the hook half).

**Items:** 1

**Depends on:** none

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/turn-end.test.sh`, replace:

```text
check "auto run: the hold tells the user" "$(jq -r .systemMessage <<<"$out" | grep -c 'auto run, hold 1 of 3')" "1"
```

with:

```text
check "auto run: the hold tells the user" "$(jq -r .systemMessage <<<"$out" | grep -c 'auto run, hold 1 of 3')" "1"
check "auto run: the reason names the switching line" "$(jq -r .reason <<<"$out" | grep -c 'end with `Auto run: switching`')" "1"
```

Then replace:

```text
check "auto run: the clearing line passes a clear" "$(stop s-1 $'Handed off.\n\nAuto run: clearing')" ""
```

with:

```text
check "auto run: the clearing line passes a clear" "$(stop s-1 $'Handed off.\n\nAuto run: clearing')" ""
pend switch
check "auto run: the switching line passes a switch" "$(stop s-1 $'Plan saved.\n\nAuto run: switching')" ""
out=$(stop s-1 $'Plan saved.\n\nAuto run: compacting')
check "auto run: the compacting line does not answer a switch" "$(decision "$out")" "block"
check "auto run: the switch hold names the switching line" "$(jq -r .reason <<<"$out" | grep -c 'end your message with the line `Auto run: switching`')" "1"
pend compact
check "auto run: the switching line does not answer compact" "$(decision "$(stop s-1 $'Done.\n\nAuto run: switching')")" "block"
pend switch-resume
check "auto run: a pending switch-resume is held" "$(decision "$(stop s-1 $'Done.\n\nAuto run: switching')")" "block"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/turn-end.test.sh`
Expected: FAIL on "the reason names the switching line", "the switching line passes a switch" and "the switch hold names the switching line".

- [ ] **Step 3: Implement**

In `plugins/dforge/scripts/turn-end.sh`, replace:

```text
# action; the cockpit compacts or clears on that line. Any other ending is held
```

with:

```text
# action; the cockpit compacts, clears or switches on that line. Any other ending is held
```

Then replace:

```text
    'compact:Auto run: compacting' | 'clear:Auto run: clearing') rm -f "$stamp.holds"; exit 0 ;;
```

with:

```text
    'compact:Auto run: compacting' | 'clear:Auto run: clearing' | 'switch:Auto run: switching') rm -f "$stamp.holds"; exit 0 ;;
```

Then replace:

```text
After \`auto-run clear\` exits 0, end with \`Auto run: clearing\`. If the run must stop
```

with:

```text
After \`auto-run clear\` exits 0, end with \`Auto run: clearing\`. After \`auto-run switch\` exits 0, end with \`Auto run: switching\`. If the run must stop
```

Then replace:

```text
  if [ "$auto_pending" = after-compact ]; then
```

with:

```text
  if [ "$auto_pending" = switch ]; then
    reason="An auto run is bound to this session and the plan is saved (pending: switch; see reference/auto-run.md §The switch), so this turn ends only on the switching line. Do not stop: end your message with the line \`Auto run: switching\`; the cockpit then compacts and moves this session to the plan's launch model. If the run must stop, run \`bash ${root_shown}/scripts/auto-run stop --reason \"<why>\"\` first, then end as the attended flow would."
  fi
  if [ "$auto_pending" = after-compact ]; then
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/turn-end.test.sh`
Expected: `0 failed`.
Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/hook.test.sh`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/turn-end.sh plugins/dforge/tests/turn-end.test.sh
git commit -m "feat(dforge): let the Stop hook end on switching"
```

### Task 3: Auto-run and strategy defaults

**Files:**
- Modify: `plugins/dforge/config/schema.mjs`
- Test: `plugins/dforge/tests/dforge-config.test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: C4.

**Items:** 2, 7

**Depends on:** none

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/dforge-config.test.sh`, replace:

```text
  "strict true true ask auto ask standard sections true single ask"
```

with:

```text
  "strict true true parallel auto ask standard sections true single ask"
```

Then replace:

```text
executionStrategy ask parallel fast
```

with:

```text
executionStrategy parallel sequential fast
autoRun on ask maybe
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: FAIL on "workflow keys: defaults", "executionStrategy: default" and "autoRun: default".

- [ ] **Step 3: Implement**

In `plugins/dforge/config/schema.mjs`, replace:

```text
    type: 'enum', values: ['ask', 'sequential', 'parallel'], default: 'ask', enforcedBy: 'skill', group: 'Workflow', target: 'dforge',
    label: 'Strategy', title: 'Execution strategy',
    description: 'How a plan executes. ask keeps the question; parallel falls back to sequential when the parts share files, and on Codex.',
```

with:

```text
    type: 'enum', values: ['ask', 'sequential', 'parallel'], default: 'parallel', enforcedBy: 'skill', group: 'Workflow', target: 'dforge',
    label: 'Strategy', title: 'Execution strategy',
    description: 'How a plan executes. parallel, the default, runs independent tasks in waves and falls back to sequential when no two tasks can share a wave, and on Codex; ask keeps the question.',
```

Then replace:

```text
    type: 'enum', values: ['ask', 'off'], default: 'ask', enforcedBy: 'skill', group: 'Workflow', target: 'dforge',
    label: 'Auto run', title: 'Offer an unattended run',
    description: 'ask offers, once the design is approved, to run the spec, plan, execution, review and finish unattended (Claude Code only). off never offers it.',
```

with:

```text
    type: 'enum', values: ['on', 'ask', 'off'], default: 'on', enforcedBy: 'skill', group: 'Workflow', target: 'dforge',
    label: 'Auto run', title: 'Unattended runs',
    description: 'on runs the plan, execution, review and finish unattended once you approve the written spec (Claude Code only; off on Codex). ask offers that once the design is approved. off never runs one.',
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: `0 failed`.
Run: `timeout 60 node scripts/validate-repository.mjs`
Expected: exit 0.
Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/settings-skills.test.sh`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/config/schema.mjs plugins/dforge/tests/dforge-config.test.sh
git commit -m "feat(dforge): default to auto runs and parallel"
```

### Task 4: Final phase never hands off

**Files:**
- Modify: `plugins/dforge/scripts/lib/context.sh`
- Modify: `plugins/dforge/scripts/context-size`
- Test: `plugins/dforge/tests/context-size.test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: C5.

**Items:** 3

**Depends on:** none

**Implementer:** dr-superpowers:impl-sonnet-low
**Executor:** codex gpt-6.1-sol / low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Write the failing test**

In `plugins/dforge/tests/context-size.test.sh`, replace:

```text
check "final: over: exit 5" "$status" "5"
check "final: over: line" "$out" "budget (final): 560k of 553k (101%) — handoff — source: record"
```

with:

```text
check "final: over: exit 0, the final phase never hands off" "$status" "0"
check "final: over: line" "$out" "budget (final): 560k of 553k (101%) — ok — source: record"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/context-size.test.sh`
Expected: FAIL on the two "final: over" checks.

- [ ] **Step 3: Implement**

In `plugins/dforge/scripts/lib/context.sh`, replace:

```text
  tk=$(( (tokens + 500) / 1000 ))
  pct=$(( tokens * 100 / budget ))
  if [ "$tokens" -ge "$budget" ]; then
```

with:

```text
  tk=$(( (tokens + 500) / 1000 ))
  pct=$(( tokens * 100 / budget ))
  # The final phase never hands off (reference/session-budget.md §Stops): an
  # over-limit --final line still says ok.
  if [ "$tokens" -ge "$budget" ] && [ "${1:-}" != final ]; then
```

In `plugins/dforge/scripts/context-size`, replace:

```text
#   --final         measure against the final-phase limit, the check after the
#                   last task's complete line. Finishing itself is never checked.
```

with:

```text
#   --final         measure against the final-phase limit, the check after the
#                   last task's complete line; it never exits 5, since the final
#                   phase never hands off. Finishing itself is never checked.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/context-size.test.sh`
Expected: `0 failed`.
Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/budget-line.test.sh`
Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/context.sh plugins/dforge/scripts/context-size plugins/dforge/tests/context-size.test.sh
git commit -m "feat(dforge): never hand off from the final phase"
```

### Task 5: Auto-run references

**Files:**
- Modify: `plugins/dforge/reference/auto-run.md`
- Modify: `plugins/dforge/reference/session-budget.md`
- Modify: `plugins/dforge/reference/finish-preference.md`

**Interfaces:**
- Consumes: nothing another task produces: it documents C1, C2, C3 and C5 by the names Contracts fixes.
- Produces: C6 (`## The switch`).

**Items:** 1, 3, 4

**Depends on:** none

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Confirm the pins that must survive**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh`
Expected: `0 failed`. Every phrase it pins in `reference/auto-run.md` must still be there after Step 2.

- [ ] **Step 2: Edit `plugins/dforge/reference/auto-run.md`**

Replace:

```text
An opt-in mode: once the design is approved, dforge writes the spec and the
plan, executes, reviews and finishes without asking its human anything. The
design is `docs/superpowers/specs/2026-10-13-dr-forge-auto-run-design.md` in
the dforge repository; this file is the contract the skills cite. Every
`scripts/…` command runs as `bash <plugin-root>/scripts/<name>`.

Claude Code only: the cockpit mod compacts and clears the session. No run
starts on Codex.
```

with:

```text
The default on Claude Code (`autoRun=on`): once your human partner approves the
written spec at the spec review, dforge writes the plan, executes, reviews and
finishes without asking anything. Under `autoRun=ask` it is offered once the
design is approved and starts before the spec is written; `autoRun=off` never
starts one. The designs are
`docs/superpowers/specs/2026-10-13-dr-forge-auto-run-design.md` and
`docs/superpowers/specs/2026-10-18-auto-execution-default-design.md` in the
dforge repository; this file is the contract the skills cite. Every
`scripts/…` command runs as `bash <plugin-root>/scripts/<name>`.

Claude Code only: the cockpit mod compacts, switches and clears the session.
No run starts on Codex, where `autoRun=on` behaves as `off`.
```

Replace:

```text
dforge:brainstorming offers it once, after the last design section is
approved and before the spec is written, unless `autoRun=off`. On yes, from
the checkout the design was made in:
```

with:

```text
Under `autoRun=on`, dforge:brainstorming starts it once your human partner
approves the spec at the spec review (dforge:brainstorming §Auto by default).
Under `autoRun=ask` it offers it once, after the last design section is
approved and before the spec is written, and starts it on yes. Either way,
from the checkout the design was made in:
```

Replace:

```text
- **Phases:** `scripts/auto-run phase plan` when writing-plans starts,
  `scripts/auto-run attach --plan <plan>` once the plan is reviewed,
```

with:

```text
- **Phases:** `scripts/auto-run phase plan` when writing-plans starts,
  `scripts/auto-run attach --plan <plan>` once the plan is reviewed, then
  `scripts/auto-run switch` (see The switch),
```

Replace:

```text
## The spec

After your own self-review round and the architecture critic
```

with:

```text
## The spec

Under `autoRun=on` the critic and the Fable review run before the run starts,
as dforge:brainstorming §Auto by default says: what Fable leaves undecided is
asked at the spec review instead of deferred, and its rulings are imported
after `start` with `scripts/auto-run ruling add`. The rest of this section is
the spec phase of a run started under `autoRun=ask`.

After your own self-review round and the architecture critic
```

Replace:

```text
after the second is deferred the same way. Then `scripts/context-size --plan`
as brainstorming says: under its limit write the plan here; over it, follow
Clears with `--phase`.
```

with:

```text
after the second is deferred the same way. Then write the plan in this
session: `scripts/context-size --plan` does not run in an auto run.
```

Replace:

```text
anything smaller returns to the normal one.
```

with:

```text
anything smaller returns to the normal one. In the `plan`, `final` and
`finish` phases P never hands off, and once a compaction has run in `final` or
`finish` every budget line says `ok`.
```

Replace:

```text
A run's turn ends only with one of two lines as the last line of the message:

- `Auto run: compacting` when `scripts/auto-run pending` says `compact`;
- `Auto run: clearing` after `scripts/auto-run clear` exits 0.

`scripts/auto-run pending` prints `compact`, `after-compact`, `handoff`,
`clear`, `resume` or `none`. `handoff` is a compaction that left too much
```

with:

```text
A run's turn ends only with one of three lines as the last line of the message:

- `Auto run: compacting` when `scripts/auto-run pending` says `compact`;
- `Auto run: clearing` after `scripts/auto-run clear` exits 0;
- `Auto run: switching` after `scripts/auto-run switch` exits 0.

`scripts/auto-run pending` prints `compact`, `after-compact`, `handoff`,
`clear`, `resume`, `switch`, `switch-resume` or `none`. `handoff` is a
compaction that left too much
```

Replace:

```text
It prints `continue` (exit 0) or `handoff` (exit 5).
```

with:

```text
It prints `continue` (exit 0) or `handoff` (exit 5); in the `plan`, `final`
and `finish` phases it always prints `continue`, since the plan, the final
review and finishing stay in this session.
```

Replace:

```text
- `continue`: carry on with the phase `scripts/auto-run status` names. In
```

with:

```text
- `continue`: carry on with the phase `scripts/auto-run status` names. In
  `plan`, resume dforge:writing-plans from the spec and the plan file on disk
  (before `attach`, the newest file in the plans directory whose `**Spec:**`
  line names the spec). In
```

Replace:

```text
## Clears
```

with:

```text
## The switch

Once the plan is reviewed and attached, the session moves to execution in
place; dforge:handoff does not end it. In order:

1. When the spec's `## Decisions` holds a `Finish: <action>` line,
   `scripts/finish-choice set <action> --plan PLAN_FILE`.
2. dforge:handoff steps 0-3: reconcile background agents and shells, commit
   the plan and the spec, and update the handoff notes. Do not end the session.
3. `scripts/next-step PLAN_FILE`. Any nonzero exit means `latest.md` was not
   written: run `scripts/auto-run stop --reason "the handoff file could not be
   written"` and end as Stopping says.
4. `scripts/auto-run switch`, which also sets the phase to `execute`. It exits
   4 without an attached plan, or when the first prompt in `latest.md` names
   another plan; stop the run the same way. On exit 0, end the turn with
   `Auto run: switching` as its last line.

The cockpit then compacts the session, keeping the spec, plan, register and
base paths and dropping the design conversation (`compacted --switch` leaves
`switch-resume` pending), runs `/model` and `/effort` from the plan's launch
command, puts back the user's default model and effort, and submits the plan's
first prompt behind "Run `scripts/auto-run after-compact` first." Run it, then
follow the first prompt in this same session. A switch is a phase transition:
it never counts as a self-resume. Its compaction is measured in the `execute`
phase, so one that leaves 85% of the window or more hands off as Clears says.
A failure in either stage is retried once in that stage; the second stops the
run.

## Clears
```

Replace:

```text
- **Plan saved**, and **spec to plan** over the `--plan` limit:
  `scripts/auto-run clear --phase`.
- **A compaction that left too much:** `scripts/auto-run clear`.
```

with:

```text
- **A compaction that left too much:** `scripts/auto-run clear`.

Plan saved is no clear: the session switches in place (§The switch). A run
started under `autoRun=ask` writes its plan in the same session too.
```

Replace:

```text
Finishing carries out the `finishAction` setting at once, into the base
`scripts/auto-run status` names: `merge` and `pr` as named;
```

with:

```text
Finishing carries out at once, into the base `scripts/auto-run status` names,
the choice `scripts/finish-choice get --plan PLAN_FILE` prints, which the spec
review recorded, or else the `finishAction` setting: `merge` and `pr` as named;
```

Replace:

```text
red test at finishing's first step, and one the fix wave fixed does not keep the branch. On a
```

with:

```text
red test at finishing's first step, and one the fix wave fixed does not keep the branch. A row
deferred at the spec review, before the run started, counts as one the run
added. On a
```

- [ ] **Step 3: Edit `plugins/dforge/reference/session-budget.md`**

Replace:

```text
- **brainstorming:** `context-size --plan` once, after the spec is committed.
  Below its limit the plan is written in the same session.
```

with:

```text
- **brainstorming:** `context-size --plan` once, after the spec is committed.
  Below its limit the plan is written in the same session. In an auto run it
  does not run: the plan is always written in the same session.
```

Replace:

```text
- **Hard:** the plan is saved; a plan switches from inline to subagent mode.
  Both launch the execution model the Execution line names. writing-plans runs
  dforge:handoff once the plan is reviewed.
- **Soft:** the last task is complete, in either mode. The final review and
  finishing follow in the same session unless `context-size --final` says
  `handoff` there; a clean final review never stops before finishing. The
  final phase - the final review, its one fix wave, the scoped re-review and
  finishing - grows far less than a task's fix loop, so it is measured against
  the final-phase limit, and a task budget line saying `handoff` inside it
  does not stop it.
```

with:

```text
- **Hard:** the plan is saved; a plan switches from inline to subagent mode.
  Both launch the execution model the Execution line names. writing-plans runs
  dforge:handoff once the plan is reviewed. In an auto run the plan saved is
  no stop: the cockpit switches the session in place
  ([auto-run.md](auto-run.md) §The switch).
- **Never a stop:** the last task completing, in either mode. The final review
  and finishing follow in the same session whatever `context-size --final`
  prints: it never says `handoff`, and a task budget line saying `handoff`
  inside the final phase does not stop it. When the context fills there,
  Claude Code's own compaction is the backstop, and the execution skill's
  After compaction steps resume the final phase from the ledger.
```

Replace:

```text
85% of the task budget or more, less 140k per extra task of a wave; a
compaction that leaves 85% of the window or more hands off, and the cockpit
clears and resumes the session.
```

with:

```text
85% of the task budget or more, less 140k per extra task of a wave; a
compaction that leaves 85% of the window or more hands off, and the cockpit
clears and resumes the session, except in the `plan`, `final` and `finish`
phases, which never hand off; after one compaction in `final` or `finish`
every budget line of the run says `ok`.
```

- [ ] **Step 4: Edit `plugins/dforge/reference/finish-preference.md`**

Replace:

```text
An auto run ([auto-run.md](auto-run.md)) never asks the question below:
finishing carries out `finishAction` at once into the run's recorded base
(`merge` or `pr`), and keeps the branch under `keep`, `ask` or `wait`, or when
there is no base, with no menu.
```

with:

```text
An auto run ([auto-run.md](auto-run.md)) never asks the question below. Under
`autoRun=on` the spec review asks it when `finishAction` is `ask`, and the
answer is recorded with `scripts/finish-choice set <action> --plan PLAN_FILE`
once the plan is attached. Finishing carries out that choice, or else
`finishAction`, at once into the run's recorded base (`merge` or `pr`), and
keeps the branch under `keep`, `ask` or `wait`, or when there is no base, with
no menu.
```

- [ ] **Step 5: Run the tests that read these files**

Run each: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh`, `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/settings-skills.test.sh`, `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/inline-mode.test.sh`
Expected: each `0 failed`.
Run: `grep -c 'clear --phase' plugins/dforge/reference/auto-run.md`
Expected: `0`.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/reference/auto-run.md plugins/dforge/reference/session-budget.md plugins/dforge/reference/finish-preference.md
git commit -m "docs(dforge): describe the switch and final phase"
```

### Task 6: Cockpit in-place switch

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/lib.ts`
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: C1 (`compacted --switch`, `resumed`, the pending names), C2 (the Stop hook lets `Auto run: switching` end a turn).
- Produces: C3, C2 (the cockpit half).

**Items:** 1

**Depends on:** Task 1, Task 2

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/cockpit.test.ts`, replace:

```text
        if (exitCode === 0 && word === 'compacted') Object.assign(state, { pending: 'after-compact', compactions: Number(state.compactions) + 1 })
```

with:

```text
        if (exitCode === 0 && word === 'compacted') Object.assign(state, { pending: words[3] === '--switch' ? 'switch-resume' : 'after-compact', compactions: Number(state.compactions) + 1 })
```

Then replace:

```text
        if (exitCode === 0 && word === 'resumed' && state.pending === 'resume') state.pending = null
```

with:

```text
        if (exitCode === 0 && word === 'resumed' && state.pending === 'resume') state.pending = null
        else if (exitCode === 0 && word === 'resumed' && state.pending === 'switch-resume') state.pending = 'after-compact'
```

Then replace:

```text
  test('books nothing without a run', async ($, on) => {
```

with:

```text
  test('switches in place: compacts, books it, sets the model and submits the first prompt', async ($, on) => {
    const files = autoFiles({ phase: 'execute', pending: 'switch', resumePrompt: 'Continue `docs/plan.md` with dforge:subagent-driven-development.', launch: { model: 'sonnet', effort: 'high' } })
    const w: World = { ...SIGNED_IN, compacts: [], commands: [], autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Plan saved.\n\nAuto run: switching', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.compacts?.[0]).toMatch(/Drop the design conversation/)
    expect(w.commands).toEqual(['/model sonnet', '/effort high'])
    expect(w.autoRuns).toContain('--session sess-1 compacted --switch')
    expect(w.autoRuns).toContain('--session sess-1 resumed')
    expect(w.prompts).toHaveLength(1)
    expect(w.prompts?.[0]).toMatch(/^Run `bash .*\/scripts\/auto-run after-compact` first\. Continue `docs\/plan\.md`/)
    expect(pendingOf(files)).toBe('after-compact')
  })

  test('retries the first prompt after the switch compaction without compacting again', async ($, on) => {
    const files = autoFiles({ phase: 'execute', pending: 'switch', resumePrompt: 'Continue `docs/plan.md`.', launch: null })
    const w: World = { ...SIGNED_IN, compacts: [], commands: [], autoRuns: [], prompts: [], autoFile: files[AUTO], submitFailures: 1 }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Plan saved.\n\nAuto run: switching', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.prompts).toEqual([])
    expect(w.autoRuns?.filter(call => call.includes(' failure --reason the cockpit could not switch: '))).toHaveLength(1)
    expect(pendingOf(files)).toBe('switch-resume')
    await clock.advance(5_000)
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.commands).toEqual([])
    expect(w.prompts).toHaveLength(1)
    expect(w.autoRuns?.at(-1)).toBe('--session sess-1 resumed')
    expect(pendingOf(files)).toBe('after-compact')
  })

  test('stops the run when the switch cannot book its resume', async ($, on) => {
    const files = autoFiles({ phase: 'execute', pending: 'switch', resumePrompt: 'Continue `docs/plan.md`.', launch: null })
    const w: World = { ...SIGNED_IN, compacts: [], commands: [], autoRuns: [], prompts: [], autoFile: files[AUTO], autoRunExits: { resumed: 1 } }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Plan saved.\n\nAuto run: switching', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.prompts?.filter(text => text.includes('Continue `docs/plan.md`.'))).toHaveLength(1)
    expect(w.autoRuns).toContain('--session sess-1 stop --reason the cockpit switched but could not book it')
  })

  test('books no engine compaction over a pending switch', async ($, on) => {
    const w: World = { ...SIGNED_IN, autoRuns: [] }
    world(on, w)
    signedIn(on, autoFiles({ pending: 'switch' }))
    await $.session.start(START)
    await $.session.compact({ trigger: 'auto', messages: [SUMMARY] })
    expect(w.autoRuns).toEqual([])
  })

  test('books no engine compaction over a pending switch-resume', async ($, on) => {
    const w: World = { ...SIGNED_IN, autoRuns: [] }
    world(on, w)
    signedIn(on, autoFiles({ pending: 'switch-resume' }))
    await $.session.start(START)
    await $.session.compact({ trigger: 'auto', messages: [SUMMARY] })
    expect(w.autoRuns).toEqual([])
  })

  test('books nothing without a run', async ($, on) => {
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: FAIL in the five new tests (no compaction on the switching line; the engine compaction is booked).

- [ ] **Step 3: Implement**

In `plugins/dforge/hooks/cockpit/lib.ts`, replace:

```text
export const AUTO_SENTINELS: Readonly<Record<string, string>> = { compact: 'Auto run: compacting', clear: 'Auto run: clearing' }
```

with:

```text
export const AUTO_SENTINELS: Readonly<Record<string, string>> = { compact: 'Auto run: compacting', clear: 'Auto run: clearing', switch: 'Auto run: switching' }
```

In `plugins/dforge/hooks/cockpit/register.tsx`, replace:

```text
const AUTO_COMPACT_INSTRUCTIONS =
  'Preserve verbatim: the worktree path; the plan, ledger, handoff and auto-run state file paths; the current HEAD; every Ruling: line; and the auto run pending decisions. Name the task in progress and its fix round.'
```

with:

```text
const AUTO_COMPACT_INSTRUCTIONS =
  'Preserve verbatim: the worktree path; the plan, ledger, handoff and auto-run state file paths; the current HEAD; every Ruling: line; and the auto run pending decisions. Name the task in progress and its fix round.'
// What the switch's compaction keeps: once the plan is saved, the spec and the
// plan hold what the design conversation decided.
const AUTO_SWITCH_INSTRUCTIONS =
  'Preserve verbatim: the spec, plan, register and auto-run state file paths; the base branch; the current HEAD. Drop the design conversation: the spec and the plan hold what it decided.'
```

Then replace:

```text
type AutoStage = 'compact' | 'continue' | 'clear' | 'resume'
// The pending action the state file holds while each stage is due.
const AUTO_STAGE_PENDING: Record<AutoStage, string> = { compact: 'compact', continue: 'after-compact', clear: 'clear', resume: 'resume' }
```

with:

```text
type AutoStage = 'compact' | 'continue' | 'clear' | 'resume' | 'switch' | 'switch-resume'
// The pending action the state file holds while each stage is due.
const AUTO_STAGE_PENDING: Record<AutoStage, string> = {
  compact: 'compact',
  continue: 'after-compact',
  clear: 'clear',
  resume: 'resume',
  switch: 'switch',
  'switch-resume': 'switch-resume',
}
```

Then replace:

```text
  scheduleAutoAct($, auto.pending === 'clear' ? 'clear' : 'compact', 0)
```

with:

```text
  scheduleAutoAct($, auto.pending === 'clear' ? 'clear' : auto.pending === 'switch' ? 'switch' : 'compact', 0)
```

Then replace:

```text
// Carries the bound run through its pending stages: compact, then the
// continue prompt; or clear, rebind, model and effort, then the first prompt.
```

with:

```text
// Carries the bound run through its pending stages: compact, then the
// continue prompt; or clear, rebind, model and effort, then the first prompt;
// or switch: compact, then model and effort and the first prompt in the same
// session.
```

Then replace:

```text
    if (at === 'clear') {
      await $.command.run({ command: 'clear' })
```

with:

```text
    if (at === 'switch') {
      const done = await $.session.compact({ instructions: AUTO_SWITCH_INSTRUCTIONS })
      if ('skip' in done && typeof done.skip === 'string') throw new Error(done.skip)
      await update($, budget, () => null)
      await update($, isNudged, () => false)
      // As for compact: the compaction happened, so it is never repeated.
      if ((await autoRunCall($, bound, ['compacted', '--switch'])) !== 0) {
        await endUnboundRun($, bound, 'the cockpit compacted for the switch but could not book it')
        return
      }
      await trackAutoRun($)
      at = 'switch-resume'
    }
    if (at === 'clear') {
      await $.command.run({ command: 'clear' })
```

Then replace:

```text
    await $.prompt.submit({ text: `${auto.resumePrompt ?? resumePrompt()}${note}`, asUser: true })
```

with:

```text
    const lead = at === 'switch-resume' ? `Run \`bash ${$.plugin.root}/scripts/auto-run after-compact\` first. ` : ''
    await $.prompt.submit({ text: `${lead}${auto.resumePrompt ?? resumePrompt()}${note}`, asUser: true })
```

Then replace:

```text
    await autoRunCall($, bound, ['resumed'])
    await trackAutoRun($)
  } catch (error) {
```

with:

```text
    // After a switch an unbooked resume leaves switch-resume pending, which no
    // stage retries; the prompt is already submitted, so stop rather than resend it.
    if ((await autoRunCall($, bound, ['resumed'])) !== 0 && at === 'switch-resume') {
      await endUnboundRun($, bound, 'the cockpit switched but could not book it')
      return
    }
    await trackAutoRun($)
  } catch (error) {
```

Then replace:

```text
    const action = at === 'compact' || at === 'continue' ? 'compact' : 'clear'
```

with:

```text
    const action = at === 'compact' || at === 'continue' ? 'compact' : at === 'switch' || at === 'switch-resume' ? 'switch' : 'clear'
```

Then replace:

```text
  // A pending clear supersedes the compaction: booking it would drop the clear.
  if (auto === null || !auto.active || auto.pending === 'clear') return
```

with:

```text
  // A pending clear or switch supersedes the compaction: booking it would drop
  // that stage.
  if (auto === null || !auto.active || ['clear', 'switch', 'switch-resume'].includes(auto.pending ?? '')) return
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`
Expected: every test passes.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(cockpit): switch an auto run in place"
```

- [ ] **Step 6: Probe the switch on a real engine (spec A12, riskiest assumption)**

This verifies that a compaction followed by `/model` and `/effort` in the same session, with no `/clear`, leaves the session on the launch model, runs the plan's first prompt there, and leaves the owner's saved defaults as they were. It needs real model turns. Everything lives under the fixed directory `/tmp/dforge-switch-probe` and the tmux session `dforge-switch-probe`, so every script finds them. `<worktree>` below is this task's worktree root, absolute.

Each script below sits in a list item: write it without the list's three-space indent (column 1), or the heredoc terminators `ARM` and `LAUNCH` never match.

1. Write `/tmp/dforge-switch-probe-setup.sh` with exactly this content, then run `bash /tmp/dforge-switch-probe-setup.sh <worktree>`:

   ```bash
   set -eu
   WT=$1
   PROBE=/tmp/dforge-switch-probe
   rm -rf "$PROBE"
   mkdir -p "$PROBE/repo/.dforge/handoff"
   jq -S '{model, modelSettings}' /root/.claude-alt/settings.json > "$PROBE/defaults-before.json"
   cd "$PROBE/repo"
   git init -q -b main
   printf '# Probe spec\n' > spec.md
   printf '# Probe plan\n' > plan.md
   git add spec.md plan.md
   git -c user.name=probe -c user.email=probe@example.invalid commit -q -m probe
   {
     printf '# Handoff\n\n## Next session\n\n**Status:** plan saved\n**Next:** execute the plan\n\n'
     printf 'Launch in `%s`:\n\n```\nclaude --model sonnet --effort low\n```\n\n' "$PROBE/repo"
     printf 'Paste as the first prompt:\n\n```\nCreate the file started.txt in this repository containing the word READY, then run: bash %s/plugins/dforge/scripts/auto-run stop --reason "probe done" and reply DONE. This is the first prompt of plan.md.\n```\n' "$WT"
   } > .dforge/handoff/latest.md
   cat > "$PROBE/arm.sh" <<ARM
   set -u
   cd "$PROBE/repo"
   for step in "start --spec spec.md --register r.md" "attach --plan plan.md" "phase plan" "switch"; do
     bash "$WT/plugins/dforge/scripts/auto-run" \$step || { echo "auto-run \$step: exit \$?"; exit 1; }
   done
   echo armed
   ARM
   printf '{}\n' > "$PROBE/settings.json"
   cat > "$PROBE/launch.sh" <<LAUNCH
   cd "$PROBE/repo"
   exec env -i HOME=/root PATH=/root/.local/bin:/usr/local/bin:/usr/bin:/bin CLAUDE_CONFIG_DIR=/root/.claude-alt IS_SANDBOX=1 DFORGE_NO_SETTINGS=1 TERM=xterm-256color /root/.local/bin/claude --dangerously-skip-permissions --setting-sources project,local --settings "$PROBE/settings.json" --plugin-dir "$WT/plugins/dforge"
   LAUNCH
   tmux new-session -d -s dforge-switch-probe -x 200 -y 50 "bash $PROBE/launch.sh"
   echo started
   ```

2. Drive the session with single commands: `tmux capture-pane -p -t dforge-switch-probe` to read the screen, and `tmux send-keys -t dforge-switch-probe <keys>` to answer it. Answer a folder-trust dialog with Enter on its "Yes" option and the bypass-permissions prompt with Down, then Enter. Never copy `.credentials.json` anywhere. When the prompt box is ready, send `tmux send-keys -t dforge-switch-probe -l 'Run bash /tmp/dforge-switch-probe/arm.sh. If it does not print armed, say so and stop. Otherwise end your reply with this line exactly: Auto run: switching'`, then `tmux send-keys -t dforge-switch-probe Enter`.
3. Write `/tmp/dforge-switch-probe-observe.sh` with exactly this content, and run it every 30 seconds (a Monitor until-loop, or one `bash` call at a time) until `started.txt` exists, or for at most five minutes:

   ```bash
   PROBE=/tmp/dforge-switch-probe
   S="$PROBE/repo/.dforge/sdd/auto-run.json"
   jq -c '{pending, phase, compactions, resumes, session}' "$S"
   if [ -f "$PROBE/repo/started.txt" ]; then echo "started.txt: $(cat "$PROBE/repo/started.txt")"; else echo "started.txt: missing"; fi
   sid=$(jq -r .session "$S")
   T=$(ls /root/.claude-alt/projects/*/"$sid".jsonl 2>/dev/null | head -n 1)
   echo "transcript: ${T:-none}"
   [ -n "$T" ] || exit 0
   echo "compact boundaries: $(grep -c '"compact_boundary"\|"isCompactSummary":true' "$T")"
   echo "assistant models: $(jq -r 'select(.type == "assistant") | .message.model // empty' "$T" | uniq | paste -sd' ' -)"
   echo "newer transcripts in that project: $(find "$(dirname "$T")" -name '*.jsonl' -newer "$T" | grep -c .)"
   if diff -q <(jq -S '{model, modelSettings}' /root/.claude-alt/settings.json) "$PROBE/defaults-before.json" >/dev/null; then echo "defaults: unchanged"; else echo "defaults: CHANGED"; fi
   ```

4. Expected, in the last observation: `phase` `execute`, `compactions` 1, `resumes` 0; `started.txt: READY`; `compact boundaries` at least 1; the assistant models end with a Sonnet model (the launch model) after the Opus or other model the session started on; `newer transcripts` 0 (no `/clear` started another session); `defaults: unchanged`. Effort is not recorded in the transcript: read the effort level from the pane (`tmux capture-pane -p -t dforge-switch-probe`, the status line or the `/effort low` output) and report it; if the pane shows none, say effort is unverified. Record every observation, with the date, in your report.
5. Write `/tmp/dforge-switch-probe-cleanup.sh` with exactly this content, and run it whether the probe passed or not:

   ```bash
   PROBE=/tmp/dforge-switch-probe
   tmux kill-session -t dforge-switch-probe 2>/dev/null
   if [ -f "$PROBE/defaults-before.json" ] && ! diff -q <(jq -S '{model, modelSettings}' /root/.claude-alt/settings.json) "$PROBE/defaults-before.json" >/dev/null; then
     tmp=$(mktemp)
     jq --slurpfile d "$PROBE/defaults-before.json" '(if $d[0].model == null then del(.model) else .model = $d[0].model end) | (if $d[0].modelSettings == null then del(.modelSettings) else .modelSettings = $d[0].modelSettings end)' /root/.claude-alt/settings.json > "$tmp" && mv "$tmp" /root/.claude-alt/settings.json && echo "restored the owner's model defaults"
   fi
   rm -rf "$PROBE" /tmp/dforge-switch-probe-setup.sh /tmp/dforge-switch-probe-observe.sh
   echo cleaned
   ```

   Then delete the cleanup script itself with `rm -f /tmp/dforge-switch-probe-cleanup.sh`. If it printed `restored the owner's model defaults`, say so in your report.

If any expectation in item 4 fails, report BLOCKED with the observations: the switch's design must be ruled on before Task 7. Commit nothing from this step.

### Task 7: Brainstorming auto by default

**Files:**
- Modify: `plugins/dforge/skills/brainstorming/SKILL.md`
- Modify: `plugins/dforge/skills/brainstorming/references/architecture-critic-prompt.md`
- Modify: `plugins/dforge/skills/using-dforge/SKILL.md`
- Create: `plugins/dforge/tests/auto-default.test.sh`

**Interfaces:**
- Consumes: C4 (the `autoRun` values), C6 (`## The switch` in auto-run.md).
- Produces: C6 (`## Auto by default (\`autoRun=on\`)`, `## Decisions`, `## Review rulings`, the `Finish:` line).

**Items:** 4, 5, 6, 7

**Depends on:** Task 3, Task 5

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/auto-default.test.sh`:

```bash
#!/usr/bin/env bash
# Under autoRun=on, brainstorming's one stop is the spec review: each check is
# a whole instruction, not a keyword.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" && echo yes || echo no)" "yes"
}

B="$P/skills/brainstorming/SKILL.md"
names "the section" "$B" '## Auto by default (`autoRun=on`)'
names "the setting" "$B" '- `autoRun=on`, the default: the architectural path runs as Auto by default'
names "designApproval has no effect" "$B" '`autoRun=on`, which presents no design.'
names "specReview has no effect" "$B" 'Gate and go on to Implementation. It has no effect under `autoRun=on`:'
names "the checklist points at the section" "$B" '**Architectural:** (under `autoRun=on`, the default on Claude Code, steps 6-8'
names "no sub-project split" "$B" 'Under `autoRun=ask` or `autoRun=off` only (under `on`, one spec covers the whole request)'
names "one spec" "$B" 'One spec covers the whole request: no'
names "acceptance waits for the review" "$B" 'Under `autoRun=on` skip this step and the offer below: the statements are'
names "no design presented" "$B" '; under `autoRun=on` present no design (see Auto by default)'
names "self-review accepts an open statement" "$B" 'Under `autoRun=on`, a statement rated `medium` or `low` passes when it carries its `Q:`'
names "the critic gets the decisions" "$B" 'spec path, the approved design sections verbatim (under `autoRun=on`, the'
names "the gate is the spec review" "$B" 'Under `autoRun=on`, this gate is the spec review message in Auto by default.'
names "no plan budget check in a run" "$B" 'an auto run skip this check: the plan is always written in this session.'
names "the review rulings section" "$B" '`## Review rulings`'
names "the three approvals" "$B" '- **Approve and run unattended**, **Approve, keep the normal stops**, or'
names "the finish line" "$B" '`Finish: <merge|pr|keep>` line in `## Decisions`;'
names "specReview never skips it" "$B" '`specReview=false` does not skip this stop.'
names "rulings are imported" "$B" '`scripts/auto-run ruling add "Fable, spec: <line>"`'
names "the old pin survives" "$B" '`autoRun=off`: never offer an auto run'
names "critic prompt: the decisions" "$P/skills/brainstorming/references/architecture-critic-prompt.md" 'or under `autoRun=on` the spec'"'"'s'
names "using-dforge: the approval is the spec review" "$P/skills/using-dforge/SKILL.md" 'still get approval (under `autoRun=on`, the spec review).'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-default.test.sh`
Expected: FAIL on every check but "the old pin survives".

- [ ] **Step 3: Edit `plugins/dforge/skills/brainstorming/SKILL.md`**

Replace:

```text
- `designApproval=whole`: present every design section in one message and ask
  for approval once, instead of after each section.
```

with:

```text
- `designApproval=whole`: present every design section in one message and ask
  for approval once, instead of after each section. It has no effect under
  `autoRun=on`, which presents no design.
```

Replace:

```text
- `specReview=false`: after the spec self-review block, skip the User Review
  Gate and go on to Implementation.
```

with:

```text
- `specReview=false`: after the spec self-review block, skip the User Review
  Gate and go on to Implementation. It has no effect under `autoRun=on`:
  the spec review always happens.
```

Replace:

```text
- `autoRun=off`: never offer an auto run (see After the Design). `ask`, the
  default, offers it once on the architectural path.
```

with:

```text
- `autoRun=on`, the default: the architectural path runs as Auto by default
  says, and its one stop is the spec review. `autoRun=ask` offers an auto run
  once on the architectural path (see After the Design).
  `autoRun=off`: never offer an auto run. On a Codex host `on` behaves as
  `off`; say so in one line.
```

Replace:

```text
**Architectural:**
1. **Open the item register**
```

with:

```text
**Architectural:** (under `autoRun=on`, the default on Claude Code, steps 6-8
and 12-13 run as Auto by default says)
1. **Open the item register**
```

Replace:

```text
- If the project is too large for a single spec, help the user decompose into sub-projects:
```

with:

```text
- Under `autoRun=ask` or `autoRun=off` only (under `on`, one spec covers the whole request): if the project is too large for a single spec, help the user decompose into sub-projects:
```

Replace:

```text
- Ask after each section whether it looks right so far; with `designApproval=whole`, present every section in one message and ask once (see Settings)
```

with:

```text
- Ask after each section whether it looks right so far; with `designApproval=whole`, present every section in one message and ask once (see Settings); under `autoRun=on` present no design (see Auto by default)
```

Replace:

```text
## After the Design (architectural path)
```

with:

```text
## Auto by default (`autoRun=on`)

The default on Claude Code. Only the architectural path changes: a spike or a
bounded task runs as above, and on a Codex host `on` behaves as `off`. Steps 1-5
of the checklist run as written; the execution-strategy question is asked only
when the setting is `ask`. Then:

1. **Write the spec directly.** Present no design section and ask no
   acceptance question first. One spec covers the whole request: no
   sub-project decomposition, no program spec, no `**Program:**` line. A new
   product still goes to dforge:planning-a-product.
2. **Record the decisions.** Below its `**Execution strategy:**` line the spec
   carries a `## Decisions` section: every clarifying question and approach
   choice, with your human partner's answer quoted. The critic and Fable check
   the spec against it in place of approved design sections.
3. **Acceptance in the spec.** Draft and rate the statements as Drafting
   acceptance says, but ask nothing yet: a statement rated below `high` keeps
   its `Q:` until the spec review.
4. **Reviews before the stop.** Run the spec self-review round, then the
   architecture critic, then `dforge:judge-fable` on the spec against its
   `## Decisions`, at most two rounds (review, revise, re-review). Apply what
   Fable rules and list each ruling as one line in a `## Review rulings`
   section of the spec.
5. **The spec review**, the one stop: one message, its questions asked with the
   multiple-choice prompt, at most four per call:
   - the spec path, the `Critic: …` counts and the number of Fable rulings;
   - every statement rated below `high`, asked as Drafting acceptance asks it;
     a deferral writes the same `A<n>:` register row;
   - every item Fable left undecided, and every critic Blocker it did not
     settle, with the recommended option first;
   - when `finishAction` is `ask`: merge into `<current branch>`, open a pull
     request, or keep the branch, recorded as a
     `Finish: <merge|pr|keep>` line in `## Decisions`;
   - **Approve and run unattended**, **Approve, keep the normal stops**, or
     **Changes needed**.

   Apply the answers to the spec. **Changes needed** gets the revision and one
   new self-review round; the critic and Fable do not run again.
   `specReview=false` does not skip this stop.
6. **Start the run.** On **Approve and run unattended**, commit the spec and
   the register, run `scripts/auto-run start --spec <spec>` (add
   `--register <path>` when a register is open), then import each
   `## Review rulings` line with
   `scripts/auto-run ruling add "Fable, spec: <line>"`. Invoke
   dforge:writing-plans in this session: `scripts/context-size --plan` does not
   run. On exit 2 or 4 from `start`, say why in one line and continue as
   **Approve, keep the normal stops**.
7. **Approve, keep the normal stops** commits the spec and the register and
   continues at Implementation below, with no run.

From step 6 on, [auto-run.md](../../reference/auto-run.md) applies.

## After the Design (architectural path)
```

Replace:

```text
**Drafting acceptance:**

Once your human partner approves the last design section
```

with:

```text
**Drafting acceptance:**

Under `autoRun=on` skip this step and the offer below: the statements are
drafted in the spec and settled at the spec review (see Auto by default).

Once your human partner approves the last design section
```

Replace:

```text
6. **Acceptance:** The `## Acceptance` section is present, every statement matches `A<n>. [<test|demo>[, neg], <high|confirmed>] <statement>` and is checkable by a test or a demo, at least one carries `neg`, and no rating other than `high` or `confirmed` appears.
```

with:

```text
6. **Acceptance:** The `## Acceptance` section is present, every statement matches `A<n>. [<test|demo>[, neg], <high|confirmed>] <statement>` and is checkable by a test or a demo, at least one carries `neg`, and no rating other than `high` or `confirmed` appears. Under `autoRun=on`, a statement rated `medium` or `low` passes when it carries its `Q:`; the spec review settles it.
```

Replace:

```text
spec path, the approved design sections verbatim and the repository root.
```

with:

```text
spec path, the approved design sections verbatim (under `autoRun=on`, the
spec's `## Decisions` section) and the repository root.
```

Replace:

```text
**User Review Gate:**
In an auto run (`scripts/auto-run status` exits 0), skip this gate:
```

with:

```text
**User Review Gate:**
Under `autoRun=on`, this gate is the spec review message in Auto by default.
In an auto run (`scripts/auto-run status` exits 0), skip this gate:
```

Replace:

```text
  with dforge:writing-plans." — the plan is written in a fresh session. In
  an auto run this step owns the clear: run `scripts/auto-run clear --phase`
  and end as [auto-run.md](../../reference/auto-run.md) §Clears says.
```

with:

```text
  with dforge:writing-plans." — the plan is written in a fresh session. In
  an auto run skip this check: the plan is always written in this session.
```

- [ ] **Step 4: Edit the critic prompt and using-dforge**

In `plugins/dforge/skills/brainstorming/references/architecture-critic-prompt.md`, replace:

```text
is the approved design sections, verbatim; `[PLUGIN_ROOT]` is the resolved
```

with:

```text
is the approved design sections, verbatim, or under `autoRun=on` the spec's
`## Decisions` section, verbatim; `[PLUGIN_ROOT]` is the resolved
```

In `plugins/dforge/skills/using-dforge/SKILL.md`, replace:

```text
(the plan's Execution line decides the mode), and still get approval.
```

with:

```text
(the plan's Execution line decides the mode), and still get approval (under `autoRun=on`, the spec review).
```

- [ ] **Step 5: Run the tests to verify they pass**

Run each: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-default.test.sh`, `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/settings-skills.test.sh`, `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/process-roles.test.sh`, `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/hook.test.sh`
Expected: each `0 failed`.
Run: `timeout 60 node scripts/validate-repository.mjs`
Expected: exit 0 (it checks the skills' links).

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/skills/brainstorming/SKILL.md plugins/dforge/skills/brainstorming/references/architecture-critic-prompt.md plugins/dforge/skills/using-dforge/SKILL.md plugins/dforge/tests/auto-default.test.sh
git commit -m "feat(dforge): make brainstorming auto by default"
```

### Task 8: Writing-plans grouping and switch

**Files:**
- Modify: `plugins/dforge/skills/writing-plans/SKILL.md`
- Modify: `plugins/dforge/tests/settings-skills.test.sh`
- Create: `plugins/dforge/tests/parallel-grouping.test.sh`

**Interfaces:**
- Consumes: C6 (`## The switch`, the `Finish:` line), C7.
- Produces: the writing-plans instructions Task 10 does not pin.

**Items:** 1, 2, 6

**Depends on:** Task 5

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing tests**

Create `plugins/dforge/tests/parallel-grouping.test.sh`:

```bash
#!/usr/bin/env bash
# writing-plans sorts tasks into alone and parallel groups, orders waves by
# dependency depth, and an auto run's plan switches in place.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
W="$HERE/../skills/writing-plans/SKILL.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <text>
  check "$1" "$(grep -qF -- "$2" "$W" && echo yes || echo no)" "yes"
}

names "two groups" '1. **Draft the tasks as usual, then sort them into two groups.**'
names "the alone group" '**alone** — a task that cannot share a wave'
names "the parallel group" '**parallel** — every other task.'
names "depth decides the order" 'Dependencies decide only the order. A task'"'"'s depth is one more than the'
names "the worked example" 'Task 6 on Tasks 3-5 give `waves — 1-2 | 3-5 | 6`. Every dependency sits in'
names "one plan in an auto run" '**One plan.** An auto run writes one plan for the whole spec and amends it'
names "the finish line is recorded" 'holds a `Finish: <action>` line, `scripts/finish-choice set <action> --plan'
names "the switch ends the turn" '`scripts/auto-run switch` and end the turn with `Auto run: switching`'
names "the handoff note" 'an auto run the session switches in place instead; see Auto run'
names "parallel is the default" 'default is `parallel`), take that value and do not ask.'
names "no split under autoRun=on" 'Under `autoRun=on` the spec covers the whole request by design: write one plan for it, never suggest a split'
check "no clear --phase is left" "$(grep -c 'clear --phase' "$W")" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

In `plugins/dforge/tests/settings-skills.test.sh`, replace:

```text
names "writing-plans: the plan step owns the clear" "$W" '`scripts/auto-run clear --phase`'
```

with:

```text
names "writing-plans: the plan step switches in place" "$W" '`scripts/auto-run switch` and end the turn with `Auto run: switching`'
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/parallel-grouping.test.sh`
Expected: FAIL on every check.

- [ ] **Step 3: Edit `plugins/dforge/skills/writing-plans/SKILL.md`**

Replace:

```text
- **Once the plan is reviewed:** `scripts/auto-run attach --plan PLAN_FILE`,
  the Fable batch when `scripts/auto-run decision list` prints anything, then
  Execution Handoff. This step owns the clear: after dforge:handoff, run
  `scripts/auto-run clear --phase` and end as auto-run.md §Clears says.
```

with:

```text
- **Once the plan is reviewed:** `scripts/auto-run attach --plan PLAN_FILE`,
  the Fable batch when `scripts/auto-run decision list` prints anything, then
  the switch instead of Execution Handoff: when the spec's `## Decisions`
  holds a `Finish: <action>` line, `scripts/finish-choice set <action> --plan
  PLAN_FILE`; dforge:handoff steps 0-3 only; `scripts/next-step PLAN_FILE`;
  then `scripts/auto-run switch` and end the turn with `Auto run: switching`
  as its last line, as auto-run.md §The switch says.
- **One plan.** An auto run writes one plan for the whole spec and amends it
  in place through the ruling seat's AMEND path (`scripts/plan-amend`); it
  never writes a follow-up plan or a second plan version.
```

Replace:

```text
If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking this into separate plans — one per subsystem. Each plan should produce working, testable software on its own.
```

with:

```text
If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking this into separate plans — one per subsystem. Each plan should produce working, testable software on its own. Under `autoRun=on` the spec covers the whole request by design: write one plan for it, never suggest a split, and take a later change of scope through the ruling seat's AMEND path.
```

Replace:

```text
setting is `sequential` or `parallel` (dforge:brainstorming §Settings), take
that value and do not ask.
```

with:

```text
setting is `sequential` or `parallel` (dforge:brainstorming §Settings; the
default is `parallel`), take that value and do not ask.
```

Replace:

```text
1. **Draft the tasks as usual, then group them into waves.** A wave is a run
   of consecutive task numbers whose tasks can run at the same time. Order the
   tasks so that tasks which can run together are adjacent, and give every
   task a `**Depends on:**` line below its `**Interfaces:**` block (and its
   `**Items:**` line, when there is one): `none`, or the tasks whose output it
   consumes, as `Task 1, Task 3`. Every dependency sits in an earlier wave.
```

with:

```text
1. **Draft the tasks as usual, then sort them into two groups.** Give every
   task a `**Depends on:**` line below its `**Interfaces:**` block (and its
   `**Items:**` line, when there is one): `none`, or the tasks whose output it
   consumes, as `Task 1, Task 3`. Then:
   - **alone** — a task that cannot share a wave (rule 4 below, or a file it
     cannot give up to another task);
   - **parallel** — every other task.

   Dependencies decide only the order. A task's depth is one more than the
   deepest task it depends on; a task that depends on nothing has depth 1.
   Parallel tasks of one depth that share no file form one wave (rule 5 caps
   its width); an alone task is a wave of its own at its depth. Number the
   tasks so that the waves run in depth order, each a run of consecutive task
   numbers. Tasks 1-2 depending on nothing, Tasks 3-5 on Task 1 or 2, and
   Task 6 on Tasks 3-5 give `waves — 1-2 | 3-5 | 6`. Every dependency sits in
   an earlier wave.
```

Replace:

```text
A saved, reviewed plan is a hard stop: execution starts in a fresh session (in
an auto run the cockpit starts it; see Auto run).
```

with:

```text
A saved, reviewed plan is a hard stop: execution starts in a fresh session (in
an auto run the session switches in place instead; see Auto run).
```

- [ ] **Step 4: Run the tests to verify they pass**

Run each: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/parallel-grouping.test.sh`, `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/settings-skills.test.sh`, `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/plan-lint.test.sh`, `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/wave.test.sh`
Expected: each `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/writing-plans/SKILL.md plugins/dforge/tests/settings-skills.test.sh plugins/dforge/tests/parallel-grouping.test.sh
git commit -m "feat(dforge): group plan tasks and switch in place"
```

### Task 9: Execution skills keep going

**Files:**
- Modify: `plugins/dforge/skills/subagent-driven-development/SKILL.md`
- Modify: `plugins/dforge/skills/executing-plans/SKILL.md`
- Modify: `plugins/dforge/skills/finishing-a-development-branch/SKILL.md`
- Modify: `plugins/dforge/skills/handoff/SKILL.md`
- Modify: `plugins/dforge/reference/final-review.md`
- Create: `plugins/dforge/tests/final-phase.test.sh`

**Interfaces:**
- Consumes: C5, C6 (`finish-choice get --plan` before `finishAction`).
- Produces: nothing other tasks consume.

**Items:** 3

**Depends on:** Task 4, Task 5

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/final-phase.test.sh`:

```bash
#!/usr/bin/env bash
# Once the last task is complete nothing hands off: the final review and
# finishing run in the same session, and an auto run finishes on the recorded
# choice first.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" && echo yes || echo no)" "yes"
}

SDD="$P/skills/subagent-driven-development/SKILL.md"
EP="$P/skills/executing-plans/SKILL.md"
FIN="$P/skills/finishing-a-development-branch/SKILL.md"
H="$P/skills/handoff/SKILL.md"
FR="$P/reference/final-review.md"

names "subagent mode: --final is for the record" "$SDD" '`scripts/context-size --final` for the record, then'
names "subagent mode: the final phase never hands off" "$SDD" 'prints: the final phase never hands off, and a `review-package` budget line'
names "subagent mode: Final Review stays here" "$SDD" 'This runs in the session that completed the last task. Only a stop the'
names "inline mode: never a stop" "$EP" 'The last task completing is never a stop: the final review, its fix wave and'
names "inline mode: --final never hands off" "$EP" 'task'"'"'s `Task <N>: complete` line for the record: it never says `handoff`.'
names "inline mode: the final review stays here" "$EP" 'pass. In this mode it runs in this session: the final phase never hands off.'
names "handoff: plan saved outside an auto run" "$H" 'plan saved outside an auto run'
names "handoff: never a stop" "$H" 'The last task completing is never a stop in either execution'
names "final review: the same session" "$FR" 'the session that completed the last task: the'
names "finishing: the recorded choice first" "$FIN" 'Read `scripts/finish-choice get --plan PLAN_FILE`'
names "finishing: a spec-review deferral keeps a merge" "$FIN" 'A row deferred at the spec review, before the run started, counts as one'
names "subagent mode: recovery resumes the final phase" "$SDD" '3. When every task has its `complete` line, run `scripts/context-size --final`'
names "inline mode: recovery resumes the final phase" "$EP" '3. When every task has its `complete` line, run `scripts/context-size --final`'
names "handoff: a saved plan switches in place" "$H" 'a compaction that left too much. A saved plan switches in place instead'
check "handoff: no spec-to-plan trigger is left" "$(grep -c 'spec-to-plan' "$H")" "0"
for f in "$SDD" "$EP" "$H" "$FR"; do
  check "${f#"$P"/} no longer hands off after --final" "$(tr '\n' ' ' < "$f" | tr -s ' ' | grep -cE -- '--final` (said|says) `handoff`')" "0"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/final-phase.test.sh`
Expected: FAIL on every check.

- [ ] **Step 3: Edit the two execution skills**

In `plugins/dforge/skills/subagent-driven-development/SKILL.md`, replace:

```text
3. Run `scripts/context-size`. On exit 5, finish the task in flight, then
   invoke dforge:handoff.
4. Re-read this skill in full before the next dispatch, and
```

with:

```text
3. When every task has its `complete` line, run `scripts/context-size --final`
   and go on to Final Review or finishing whatever it prints: the final phase
   never hands off (in an auto run, the Auto run section's `handoff` rule still
   applies). Otherwise run `scripts/context-size`; on exit 5, finish the task
   in flight, then invoke dforge:handoff.
4. Re-read this skill in full before the next dispatch, and
```

Then replace:

```text
- After the last task's `Task N: complete` line, run
  `scripts/context-size --final`, which measures against the final-phase limit
  (85% of the compaction window) instead of the task budget. On `ok` or
  `unknown`, continue to Final Review in this session and on to finishing: a
  `review-package` budget line saying `handoff` does not stop the final phase.
  On exit 5,
  invoke dforge:handoff, and dforge:resume-execution brings
  the next session to Final Review.
```

with:

```text
- After the last task's `Task N: complete` line, run
  `scripts/context-size --final` for the record, then
  continue to Final Review in this session and on to finishing, whatever it
  prints: the final phase never hands off, and a `review-package` budget line
  saying `handoff` does not stop it. If the context fills, Claude Code's own
  compaction is the backstop, and After compaction resumes the final phase
  from the ledger.
```

Then replace:

```text
This runs in the session that completed the last task, unless
`scripts/context-size --final` said `handoff` there; then
dforge:resume-execution brought the next session here.
```

with:

```text
This runs in the session that completed the last task. Only a stop the
final phase cannot avoid (your human partner asked, or the session ended)
brings it to a later session, through dforge:resume-execution.
```

In `plugins/dforge/skills/executing-plans/SKILL.md`, replace:

```text
3. Run `scripts/context-size`. On exit 5, finish the task in flight, then
   invoke dforge:handoff.
4. Re-read this skill in full before the next task. If a task's last ledger
```

with:

```text
3. When every task has its `complete` line, run `scripts/context-size --final`
   and go on to the final review or finishing whatever it prints: the final
   phase never hands off (in an auto run, the Auto run section's `handoff`
   rule still applies). Otherwise run `scripts/context-size`; on exit 5,
   finish the task in flight, then invoke dforge:handoff.
4. Re-read this skill in full before the next task. If a task's last ledger
```

Then replace:

```text
line's verdict decides. Run `scripts/context-size --final` after the last
task's `Task <N>: complete` line and act on its exit 5 the same way; after
every earlier task, the next brief's budget line is the check. Finishing is
never budget-checked.

The last task completing is a soft stop: the final review, its fix wave and
finishing run in this session unless `context-size --final` says `handoff`. The
final phase is measured against its own limit, 85% of the compaction window,
so a `review-package` budget line saying `handoff` does not stop it. A switch
to subagent mode is always a handoff.
```

with:

```text
line's verdict decides. Run `scripts/context-size --final` after the last
task's `Task <N>: complete` line for the record: it never says `handoff`.
After every earlier task, the next brief's budget line is the check.
Finishing is never budget-checked.

The last task completing is never a stop: the final review, its fix wave and
finishing run in this session whatever `context-size --final` prints, and a
`review-package` budget line saying `handoff` does not stop them. If the
context fills, Claude Code's own compaction is the backstop. A switch to
subagent mode is always a handoff.
```

Then replace:

```text
pass. In this mode it runs in this session, unless
`scripts/context-size --final` said `handoff` - then invoke
dforge:handoff, and dforge:resume-execution brings the next
session here. List any
```

with:

```text
pass. In this mode it runs in this session: the final phase never hands off.
List any
```

- [ ] **Step 4: Edit the handoff skill, the final review and finishing**

In `plugins/dforge/skills/handoff/SKILL.md`, replace:

```text
- An auto run ([auto-run.md](../../reference/auto-run.md)) hands off for a
  compaction that left too much, for a saved plan, and for the spec-to-plan
  limit. The steps below run as always, but the turn does not end on the
  next-step block: return to the step that invoked this skill, which runs
```

with:

```text
- An auto run ([auto-run.md](../../reference/auto-run.md)) hands off only for
  a compaction that left too much. A saved plan switches in place instead
  (auto-run.md §The switch): only steps 0-3 below run, and the session does
  not end. On a handoff the steps below run as always, but the turn does not
  end on the next-step block: return to the step that invoked this skill, which runs
```

Then replace:

```text
at a hard phase stop (plan saved, or a switch from inline to subagent mode),
```

with:

```text
at a hard phase stop (plan saved outside an auto run, or a switch from inline to subagent mode),
```

Then replace:

```text
  subagent mode. The last task completing is a soft stop in both execution
  modes: the final review and finishing run in the same session unless
  `scripts/context-size --final` says `handoff` after the last task. A task
```

with:

```text
  subagent mode. The last task completing is never a stop in either execution
  mode: the final review and finishing run in the same session whatever
  `scripts/context-size --final` prints. A task
```

In `plugins/dforge/reference/final-review.md`, replace:

```text
- **Either execution mode:** the session that completed the last task, unless
  `scripts/context-size --final` said `handoff` after it; then
  dforge:resume-execution brought the next session here. The final
```

with:

```text
- **Either execution mode:** the session that completed the last task: the
  final phase never hands off. The final
```

In `plugins/dforge/skills/finishing-a-development-branch/SKILL.md`, replace:

```text
- **Step 4 shows no menu.** Read `scripts/dforge-config get finishAction` and
  carry out the matching option
```

with:

```text
- **Step 4 shows no menu.** Read `scripts/finish-choice get --plan PLAN_FILE`
  (the spec review's answer, else the `finishAction` setting; exit 3 means
  `ask`) and carry out the matching option
```

Then replace:

```text
  row whose Item begins `A<n>:` or whose Note is `critic Blocker unresolved`.
```

with:

```text
  row whose Item begins `A<n>:` or whose Note is `critic Blocker unresolved`.
  A row deferred at the spec review, before the run started, counts as one
  the run added.
```

- [ ] **Step 5: Run the tests to verify they pass**

Run each: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/final-phase.test.sh`, `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/inline-mode.test.sh`, `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/settings-skills.test.sh`, `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh`, `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/process-roles.test.sh`
Expected: each `0 failed`.
Run: `timeout 60 node scripts/validate-repository.mjs`
Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/skills/subagent-driven-development/SKILL.md plugins/dforge/skills/executing-plans/SKILL.md plugins/dforge/skills/finishing-a-development-branch/SKILL.md plugins/dforge/skills/handoff/SKILL.md plugins/dforge/reference/final-review.md plugins/dforge/tests/final-phase.test.sh
git commit -m "feat(dforge): keep going after the last task"
```

### Task 10: README and auto-run pins

**Files:**
- Modify: `plugins/dforge/README.md`
- Modify: `plugins/dforge/tests/auto-run-skills.test.sh`

**Interfaces:**
- Consumes: C4, C6 and the texts Tasks 5 and 9 wrote.
- Produces: nothing.

**Items:** 4, 7

**Depends on:** Task 5, Task 7, Task 8, Task 9

**Implementer:** dr-superpowers:impl-sonnet-low
**Executor:** codex gpt-6.1-sol / low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Write the failing pins**

In `plugins/dforge/tests/auto-run-skills.test.sh`, replace:

```text
names "finishing: the final message lists demos and lenses" "$FIN" 'every `demo` statement of the spec, every lens'
printf '\n%d passed, %d failed\n' "$pass" "$fail"
```

with:

```text
names "finishing: the final message lists demos and lenses" "$FIN" 'every `demo` statement of the spec, every lens'

# The default flow (docs/superpowers/specs/2026-10-18-auto-execution-default-design.md).
names "auto-run.md: the default" "$R" 'The default on Claude Code (`autoRun=on`): once your human partner approves the'
names "auto-run.md: the switch section" "$R" '## The switch'
names "auto-run.md: the switching line" "$R" '- `Auto run: switching` after `scripts/auto-run switch` exits 0.'
names "auto-run.md: plan saved is no clear" "$R" 'Plan saved is no clear: the session switches in place (§The switch).'
names "auto-run.md: finishing reads the recorded choice" "$R" 'the choice `scripts/finish-choice get --plan PLAN_FILE` prints, which the spec'
names "auto-run.md: a spec-review deferral keeps a merge" "$R" 'deferred at the spec review, before the run started, counts as one the run'
check "auto-run.md: no phase clear is left" "$(grep -c 'clear --phase' "$R")" "0"
names "session-budget.md: the last task is never a stop" "$P/reference/session-budget.md" '- **Never a stop:** the last task completing, in either mode. The final review'
names "finish-preference.md: the spec review's answer" "$P/reference/finish-preference.md" 'once the plan is attached. Finishing carries out that choice, or else'
names "README: the default" "$P/README.md" 'The default on Claude Code (`autoRun=on`). Brainstorming asks its clarifying'
names "README: the opt-outs" "$P/README.md" '`autoRun=ask` offers the run once the design is approved instead, and'
names "README: the autoRun row" "$P/README.md" '| Workflow | `autoRun` | `on` |'
names "README: the strategy row" "$P/README.md" '| Workflow | `executionStrategy` | `parallel` |'
printf '\n%d passed, %d failed\n' "$pass" "$fail"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh`
Expected: FAIL only on the four README checks.

- [ ] **Step 3: Edit `plugins/dforge/README.md`**

Replace:

```text
After you approve a design, brainstorming can offer to run the rest
unattended. Fable reviews the spec, the plan is written and reviewed, the plan
executes in its recorded strategy, and the branch is finished by
`finishAction` into the branch the run started from (kept under `ask` or
`wait`), with no question to you. What Opus cannot rule goes to Fable in one
batch; what Fable cannot rule is deferred on the run's register. Instead of
handing off, the session compacts at the handoff budget, and the cockpit
clears and resumes it when a compaction leaves too much.
```

with:

```text
The default on Claude Code (`autoRun=on`). Brainstorming asks its clarifying
questions and approaches, writes the whole spec with no design-section
approvals, and has the architecture critic and Fable review it. You then get
one spec review message: the open questions, the finish choice when
`finishAction` is `ask`, and the approval. Approve it and the plan is written
in the same session; the cockpit compacts and switches the session to the
plan's launch model in place, and the plan executes, is reviewed and finished
into the branch the run started from, with no question to you and no handoff
once the last task is done. What Opus cannot rule goes to Fable in one batch;
what Fable cannot rule is deferred on the run's register. Instead of handing
off, the session compacts at the handoff budget, and the cockpit clears and
resumes it when a compaction leaves too much.
`autoRun=ask` offers the run once the design is approved instead, and
`autoRun=off` never runs one.
```

Then replace the row that begins `| Workflow | \`executionStrategy\` | \`ask\` |` (the whole line) with:

```text
| Workflow | `executionStrategy` | `parallel` | `parallel` runs independent tasks in waves and falls back to sequential when no two tasks can share a wave, and on Codex; `sequential` runs one task at a time; `ask` asks "how should the plan execute". |
```

Then replace the row that begins `| Workflow | \`autoRun\` | \`ask\` |` (the whole line) with:

```text
| Workflow | `autoRun` | `on` | `on` runs the plan, execution, review and finish unattended once you approve the written spec (Claude Code only; `off` on Codex); `ask` offers that once the design is approved; `off` never runs one. See [Auto run](#auto-run). |
```

- [ ] **Step 4: Run the tests to verify they pass**

Run each: `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh`, `env -u CLAUDE_CONFIG_DIR timeout 300 bash plugins/dforge/tests/settings-skills.test.sh`
Expected: each `0 failed`.
Run: `timeout 60 node scripts/validate-repository.mjs`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/README.md plugins/dforge/tests/auto-run-skills.test.sh
git commit -m "docs(dforge): describe auto runs as the default"
```
