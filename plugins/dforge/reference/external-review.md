# External review

Codex and the Antigravity CLI (agy) take review seats only: no plan task is
implemented by either. When a family's review surface is open, its reviewers
run beside the Claude judges as a parallel panel chosen by risk, and every
finding they return is weighed by a Claude judge or read as a judge's report
would be. With both surfaces off, the default, every review stays on Claude.

## Reviewers

Each family has a judge block in [ladder.md](ladder.md), first row preferred,
last row the fallback, each row `model effort seconds`: `codex-judge`
(`gpt-6-astra xhigh 5400`, then `gpt-6.1-sol xhigh 2400`) and `agy-judge`
(`claude-opus-5-5 high 5400`, then `gemini-4-argon high 2400`).

Every panel run starts each family on its first row and falls back once to
its last row on a refusal: Codex `gpt-6-astra`, then `gpt-6.1-sol`; agy
`claude-opus-5-5`, then `gemini-4-argon`. The panel runs for a risk-3 task's
review (only a risk-3 task gets a per-task review), plan review round 1 and
the final review's external round.

## The panel

`scripts/run-review-panel` runs every open family at once:

```bash
bash "<plugin-root>/scripts/run-review-panel" --kind task|plan|final \
  [--tier heavy] --cwd <worktree-root> --out-dir <dir> \
  (--prompt <file> | --base <sha>)
```

- It reads each family's gate once, in `scripts/executors ranked` order (agy,
  then codex). A family whose gate does not print `review=true` is skipped
  with `<id>-judge none/none status=SKIPPED exit=0 out=- evidence=none
  reason=<r>`: `<r>` is the gate's reason, `untrusted` when the gate printed
  `usable=true review=false`, or `no-session-id` when
  `CLAUDE_CODE_SESSION_ID` is unset, since a gate stores its answer per
  session. Each gate's stderr is kept in `<out-dir>/<id>.gate.log`, so a
  gate that died (`reason=gate`) still names its cause.
- Each open family's runner (`run-codex-review.sh`, `run-agy-review.sh`)
  starts in the background, in its own process group where `setsid` exists,
  with its stderr in `<out-dir>/<id>.stderr` and its list in
  `<out-dir>/<id>.json` (`<id>.md` for `--kind final`).
- It prints each runner's own status line,
  `<id>-judge <model>/<effort> status=OK|FALLBACK|SKIPPED|TIMEOUT|FAILED exit=<n> out=<path> evidence=<e>`,
  with ` reason=<token>` on every line that is not `OK`, and
  ` until=<epoch>` after `reason=quota` when the runner knows the quota's reset,
  then
  `panel tier=heavy lists=<n>`, where `<n>` counts the `OK` and `FALLBACK`
  lines.
- Its bound is the slowest family's first row plus that family's grace
  (60 s for codex, 70 s for agy), plus 120 s: 5590 s. A watchdog ends every
  runner still going 15 s before it. Run the panel as a background Bash call
  with `timeout` 5590000 ms; a foreground call caps at ten minutes.
- It exits 0 whenever it answered, `lists=0` included, and 2 on a usage
  error.

Read the status lines and nothing else. `OK` and `FALLBACK` are a reviewer
that returned a list; `FALLBACK` means the preferred row refused the run
(`reason=refused`) and the fallback row answered: say the substitution aloud
with that reason. `SKIPPED`, `TIMEOUT` and `FAILED` are a reviewer
that returned none. Never run a reviewer again: each runner has already
applied its own one-shot fallback. `lists=0` means the Claude seat reviews
alone: say so aloud, with each reviewer's reason.

The reason tokens a run prints are `gate`, `git`, `refused`, `quota`,
`quota-stderr`, `timeout`, `wrote`, `schema`, `unread` and `error`. A
`SKIPPED` line, for a family the panel did not start, carries `quota-skip`,
`untrusted`, `no-session-id`, `gate`, or the gate's own `reason=` value (for
example `setting`, `no-timeout` or `logged-out`). An `unread` review is
schema-valid but scores every criterion 1 with no finding: the reviewer read
nothing, so it is no list. A `wrote` run changed the worktree, the index,
`HEAD`, the stash list, the git config or a hook: it never counts as a list,
and what changed is named in `<out>.wrote`. An ignored file counts only when
its time is newer than the run's start, so a deletion or rename of one, a copy
that keeps its old time, an empty directory and any write inside `.dforge/`
are outside that proof. Before any commit the session
undoes a changed path or `HEAD` in the panel's `--cwd`; a final round's
`--cwd` is a throwaway worktree, so it is removed instead, and nothing
Acceptance QA committed or wrote in the checkout is ever restored. A `hook`
path, a `git config <key> <origin>` or a `stash` line lives in the shared git
directory or a config file, outside `--cwd`, and removing the worktree does
not undo it; `.wrote` keeps no old value to restore from. On any of those,
whatever the round, run no further git command in that repository and put
the `.wrote` lines to the user.

## Task review seats

`scripts/review-route PLAN_FILE --task <N>` routes a risk-3 task, and exits
2 for any other:

- either family's session file says `review=true`:
  `primary=panel:heavy+judge-opus fallback=dforge:judge-opus reason=risk`;
- neither surface open: `primary=dforge:judge-opus` with
  `reason=reviewers-off`.

`scripts/task-step review` writes the judge prompt, whose Second Pass names
one review file per ranked family, and the reviewers' prompt
`task-<N>-review-panel-prompt.md`: the task-reviewer prompt without its
Second Pass and lens sections, with the criteria and an output section that
asks for one JSON object matching `criteria/codex-review-schema.json`. It
prints the seat, `panel: <command>` and `timeout: <ms>`;
[delegated-task.md](delegated-task.md) §3 says how to run them. The lists are
consumed this way:

- **No list:** the Claude seat the route names as `fallback`, with the judge
  prompt and the line "No external review file exists: skip the Second Pass
  section".
- **One or two lists:** `judge-opus` rules on every finding of every list.
- **Whose verdict counts:** the judge's verdict and scores go on the ledger.

The judge's report carries its reading of the lists as `## External findings`,
its last section, which `task-step verdict` reads.

The ledger's seat clause names each reviewer that returned a list and the
judge, joined with `+`: `seat codex gpt-6.1-sol/xhigh+agy
gemini-4-argon/high+judge-opus`. A reviewer that ran and returned no
list adds ` (<id> <STATUS> — <reason>)`; no open surface adds
` (reviewers off — <answers>)`.

## Plan review round 1

Round 1 runs `run-review-panel --kind plan --prompt <plan review prompt>` on
the heavy rows, in place of the Claude round, as a background Bash call with
`timeout` 5590000 ms; `review-route` prints `primary=panel:plan
fallback=dforge:judge-opus reason=round cap=<n>`, and `dforge:judge-opus`
reviews only when the panel returns `lists=0`. The plan writer reads every
list. With two or more score sets, the lowest score per criterion decides the
"any score of 8 or below" gate, and the `**Plan review:**` header line names
every seat that returned a list.

## Final-review external round

At depth full only, the final review runs the panel once:

```bash
git worktree remove -f -f "<workspace>/final-review-panel-tree" 2>/dev/null; rm -rf "<workspace>/final-review-panel-tree"; git worktree prune
git worktree add --detach "<workspace>/final-review-panel-tree" <sha>
bash "<plugin-root>/scripts/run-review-panel" --kind final --tier heavy \
  --cwd "<workspace>/final-review-panel-tree" \
  --out-dir "<workspace>/final-review-panel" --base <base-branch>
```

Keep the quotes: the workspace sits under the repository root, whose path may
hold a space.

`<sha>` is the review's HEAD ([final-review.md](final-review.md) says which
SHA that is), and `<base-branch>` is the branch this one forked from.
Acceptance QA commits in the checkout while the round runs, so the panel reads
a detached worktree of its own: there `HEAD` is `<sha>`, QA's commits stay out
of the diff, and they never trip the agy write check. Remove the worktree with
`git worktree remove --force` once the final review's step 3 has read the
lists. The block's first line clears a tree a crashed run left behind, which
would otherwise make `git worktree add` fail; the doubled `-f` also removes a
tree that an interrupted `add` left locked. Each runner composes its
own prompt, `criteria/codex-final-review.md` followed by
`git diff <base>...HEAD`, and returns a markdown findings list:
`<out-dir>/codex.md`, and `<out-dir>/agy.md` from the `review` field of
`criteria/agy-final-review-schema.json`. Each list joins the Claude review's,
and [final-review.md](final-review.md) step 3 runs its dedupe judge whenever
two or more lists carry findings, tagging each finding's origins as a
`+`-joined set of `claude`, `codex` and `agy`, for example `[claude+agy]`.
At depth light or standard the round is skipped and said aloud, and so is a depth-full round whose route line says `external=off`.

## Quota and the Opus row

A quota error during a run turns that family off until the reset the error
names, or for the session when it names none, so the next panel skips it with
`reason=quota`. Only the reviewer's own answer counts: a clean JSON answer is
never scanned for quota words, a quota word found only in stderr gives
`reason=quota-stderr` and marks nothing, and `429` counts only as a whole
number.

Antigravity counts Claude and Gemini against separate limits, and its Claude
quota is small (about 500k tokens). A Claude quota during an Opus run ends that
run `FAILED` and marks only the Opus row off: the gate prints `claude=off
claude_resets_at=<iso>`, and the following heavy panels run Argon directly,
their status line saying `evidence=claude-off`. After one or two heavy reviews
that is the expected steady state, so record it as
`agy claude-opus-5-5 off (quota until <time>)`: a quota day, not a fault.

## Gates and switches

Each family's gate decides once per session and caches its answer in the
family's session directory:

```
codex-gate usable=<b> reason=<r> review=<b> resets_at=<iso|-> source=<probe|cache|setting>
agy-gate usable=<b> reason=<r> review=<b> resets_at=<iso|-> claude=<on|off> claude_resets_at=<iso|-> source=<probe|cache|setting>
```

`review=true` needs the family's setting on and its policy's trust entry
passed: `codexReview` and `reference/codex-plugin.json` `trust.calibration:
pass` for Codex, `agyReview` and `reference/agy-policy.json` `trust.review:
pass` for agy. Both settings are off by default; with one off, its gate
answers `usable=false reason=setting source=setting` without probing. A runner
reads only `usable`, so a verification run can go through a runner directly
while the surface is still untrusted. Run a gate with `--refresh` after a
login; an off answer is otherwise kept for the session. Say a gate's line
aloud when it ends `source=probe`.

## The registry

One JSON entry per reviewer family lives in `reference/executors/<id>.json`,
and `scripts/executors` is its only reader. An entry is valid when it parses as
JSON, carries every required field, and its `id` matches `^[a-z][a-z0-9-]*$`
and equals its filename stem; `executors ranked` skips an invalid entry with one
diagnostic line on stderr.

| Field | Required | What it names |
|---|---|---|
| `id` | yes | The family id: the panel's `<id>-judge` prefix and its out file's stem |
| `gate` | yes | The family's gate script |
| `runner` | yes | The review runner the panel starts |
| `session_dir` | yes | The per-session state directory under `$HOME/.claude/dforge/` |
| `surfaces` | yes | `["review"]` |
| `reference` | no | This file |
| `session_dir_env` | no | An environment variable that replaces `session_dir` |
| `priority` | no | A non-negative integer; lower ranks first in `executors ranked` (agy 10, codex 20) |
| `blocks.judge` | no | The family's judge block in [ladder.md](ladder.md) |

`${DR_EXECUTORS_DIR}` replaces the registry directory when set.

## Per-family: codex

- Codex is reached only through the official `codex@openai-codex` plugin.
  `scripts/codex-plugin` locates it, and `scripts/codex-gate` reads login,
  plan and quota through the plugin's own client. A free ChatGPT plan is off
  (`reason=free-plan`): it logs in but refuses the judge models.
- Codex reports a reset time, which the gate caches, so a quota answer is
  probed again once that time has passed.
- Efforts are `low`, `medium`, `high` and `xhigh`.
- Codex runs one review at a time per machine: two runs that overlap fail.

## Per-family: agy

- `run-agy-review.sh` runs `agy -p --mode plan --output-format json` with
  `--json-schema` (the review schemas in `criteria/`), `--model`, `--effort`,
  `--print-timeout` and `--add-dir` for the prompt directory, and never with
  `--dangerously-skip-permissions`. The answer is read from the result's
  `structured_output`.
- The prompt reaches agy as a file named by a one-sentence pointer, so a long
  prompt never meets an argument-length limit.
- Headless `--mode plan` denies every shell command, so a reviewer prompt
  names the files to read and never a command to run.
- Before the run the runner records the tracked and untracked files, `HEAD`,
  the stash list, the effective git config (every scope and include) and the
  hooks of `--cwd`, and a run that
  changed any of them ends
  `status=FAILED evidence=wrote reason=wrote`. Never edit the worktree while
  an agy review runs: the check cannot tell your edit from agy's.
- A print timeout that exits 0 is `TIMEOUT`. The reset is parsed from the
  error's `Resets in <n>d<n>h<n>m<n>s`.
