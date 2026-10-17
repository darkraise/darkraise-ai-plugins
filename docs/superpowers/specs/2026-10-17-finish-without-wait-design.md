# Carry out the recorded finish choice without a wait

**Execution strategy:** sequential — one chain: the script and file format
first, then the skills and references that describe them, then the cockpit
that reads them.
**Register:** docs/superpowers/registers/2026-10-17-run-order-finish-controller.md, row 2

## Problem

A plan run asks one question before its first task: what finishing should do
when the work is done. Today that answer is only a fallback. When the final
review is clean, dforge:finishing-a-development-branch still shows its
integration menu, arms a timer (`finishTimeout`, 30 minutes by default),
schedules a wake with CronCreate, and carries out the recorded choice only if
nobody answers before the wake fires. The owner's request: when the choice
was made, use it to finish; do not ask again and do not wait.

An auto run already behaves this way (finishing §Auto run: "Step 4 shows no
menu"). This design extends that behaviour to every run with a recorded
choice and removes the timer, which no longer has a job.

## Behaviour

### When the choice is asked

Unchanged in timing: at plan-run Setup before the ledger is written
(dforge:subagent-driven-development, dforge:executing-plans), or before the
first change for work without a plan (dforge:using-git-worktrees). Skipped,
as today, when `finish-choice get` already prints a choice (including one the
`finishAction` setting supplies) or when the ledger already exists. An auto
run never asks.

The question, determined base branch first, is the last thing in the message:

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
branch and create a Pull Request", "Keep as-is" and "Ask me then". Answers
record with `finish-choice set <merge|pr|keep|wait> --base <base>`; option 4
records `wait`.

### At finishing

Finishing Step 4 runs `scripts/finish-choice get [--plan PLAN_FILE]`:

- **`merge`, `pr` or `keep`** (attended or not): show no menu. Carry the
  option out from Step 5 by name, with the recorded base branch, exactly as
  if your human partner had chosen it, and record it with
  `finish-choice answer <action>` first so the cockpit stops showing it as
  pending. The overrides finishing §Auto run already applies hold here too:
  on a detached HEAD `merge` keeps and `pr` pushes a new branch
  (`git push origin HEAD:refs/heads/<new-branch>`); when the base is null or
  `none`, determine it as Step 3 does, and if none can be determined `merge`
  keeps and `pr` opens its request against the repository's default branch.
  Never discard.
- **`wait`, or exit 3 (nothing recorded)**: show the menu as today and wait
  for the answer. No timer, no wake.

The auto-run-only overrides stay in finishing §Auto run and apply only
there: the `finishAction` mapping (`ask` and `wait` keep), and `merge`
keeping the branch for a deferred task line, a nonzero `cannot-test` count,
or a deferred `A<n>:` or critic-Blocker register row.

An immediate finish stops where an attended one would ask: failing tests at
Step 1, a merged result failing its tests, a rejected push, a refused
worktree removal. It leaves everything in place, reports what stopped it, and
ends with the menu (no choice is armed, since nothing is). Otherwise the
final message opens with `Finished with <option>, as chosen before the run.`
and ends, as today, with Step 7's next-step block.

An answer to the menu (shown under `wait`, or after a stop) still records
with `finish-choice answer <merge|pr|keep|discard>`.

## Components

### `scripts/finish-choice`

Keeps `set`, `get`, `answer` and `clear`; `get` keeps its `finishAction`
fallback. Removes `arm`, `job` and `due`; an unknown command exits 2 with
the usage, as today. `FINISH_CHOICE_NOW` stays, since `set`, `get`'s
fallback and `answer` still write `chosenAt` and `answeredAt`. `answer`
prints nothing (there is no job id). The header comment describes the new
meaning. `finish.json` holds `action`, `base`, `chosenAt`, optional `source`,
and after an answer `answer` and `answeredAt`; files written by older versions
with `armedAt`, `dueAt`, `job` or `firedAt` are read without error and those
fields are ignored.

### Settings (`config/schema.mjs`)

- `finishTimeout` is removed. A value already stored in `~/.dforge/config.json`
  stays in the file and is ignored; `dforge-config get finishTimeout` reports
  an unknown setting like any other retired key.
- `finishAction` keeps its values (`ask`, `merge`, `pr`, `keep`, `wait`) and
  default `ask`. Title: "When the work is done". Description: "ask asks
  before the first task. merge, pr or keep skips the question and runs that
  action as soon as the final review is clean; wait skips it and shows the
  finish menu then."
- The cockpit Finish settings tab loses the "Menu waits" control (it renders
  from the schema, so removing the key removes the control).

### Stop hook (`scripts/turn-end.sh`)

The marker that recognises the question as a valid ending,
`If it gets none within `, becomes `what should I do?` in both places that
list it. The header comment drops "unanswered".

### Cockpit (`hooks/cockpit/`)

- `types/index.d.ts` `CockpitFinish`: drop `dueAt` and `firedAt`.
- `lib.ts`: `parseFinish` drops those fields; `isFinishArmed` is deleted;
  `finishLine` shows `Finish <label> when done` before an answer and nothing
  after, with `Finish ask me when done` for `wait`. No countdown.
- `register.tsx`: the once-a-second ticker no longer considers the finish
  choice; the Run card, Plan card and desktop chips keep calling `finishLine`.

### Skills and references

- `reference/finish-preference.md`: rewritten for the new meaning: the
  settings, when to ask, the question, what finishing does with each answer,
  where an immediate finish stops. The §At the finishing menu, §When your
  human partner answers (beyond recording) and §When the wake fires sections
  go.
- `skills/finishing-a-development-branch/SKILL.md`: Step 4 gains the
  recorded-choice rule above and loses "Arm the finish preference"; Step 5's
  "Whose choice it is" drops the wake; §Auto run's Step 4 bullet points to the
  shared rule and keeps only its auto-run overrides; the Common
  Rationalizations row about the wake goes.
- `skills/subagent-driven-development/SKILL.md`, `skills/executing-plans/SKILL.md`,
  `skills/using-git-worktrees/SKILL.md`,
  `skills/using-dforge/references/codex-tools.md`: the sentence describing
  the question ("if its menu goes unanswered for the configured wait") states
  the new meaning; codex-tools drops the no-scheduler fallback.
- `reference/auto-run.md`: unchanged (it names only the question, which an
  auto run still skips).
- `README.md`: the finish-preference paragraphs and the settings table.

Historical plans, specs and registers are not edited.

## Error handling

- `finish-choice get` failing for a reason other than exit 3 (no jq, outside
  a repository): finishing shows the menu, as for nothing recorded.
- A recorded base branch that no longer exists: Step 5's merge fails at
  checkout; that is a stop, handled as above.

## Testing

- `tests/finish-choice.test.sh`: drop the `arm`, `job` and `due` cases; keep
  `set`, `get` (including the `finishAction` fallback), `answer`, `clear`; add
  that an old file carrying `dueAt`/`firedAt` still reads, and that `arm`
  now exits 2 as an unknown command.
- `tests/turn-end.test.sh`: a run ending on the new question passes; the old
  marker no longer does.
- `tests/cockpit.test.ts`: replace the countdown and "no answer, so done"
  cases with the new chip text; nothing ticks for a recorded choice.
- `tests/dforge-config.test.sh` and `tests/settings-skills.test.sh`: drop
  `finishTimeout`; pin the new `finishAction` description and the
  recorded-choice rule in finishing.
- `tests/auto-run-skills.test.sh`, `tests/dforge-state.test.sh`: updated only
  where they pin removed text.
- Then the full validation: `node scripts/validate-repository.mjs`, the shell
  suites, `claude plugin validate` on the marketplace and every Claude plugin,
  and `claude plugin test plugins/dforge`.

## Out of scope

- Moving the question into plan writing: a plan can execute in a later
  session, and `finish.json` lives beside the run's ledger.
- A release version bump: a separate release commit when the owner asks.
