# dr-forge

A standalone fork of [superpowers](https://github.com/obra/superpowers) 6.3.0
(MIT — see `LICENSES/`) for Claude Code and Codex, built around one idea: a
strong model writes the plan, a Sonnet-class session or small tiered
implementers execute it literally, and every judgment call goes to one strong
ruling seat. Install `dr-forge@darkraise` from the repository-root
marketplace, then disable the upstream `superpowers` plugin,
`dcc-superpower-companions` and `andrej-karpathy-skills`: same-named skills in
two enabled plugins can double-trigger.

## Why

Four findings from real transcripts drove the fork; the numbers are in
`docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`.

- **Cost.** The main session was 92% of token spend, most of it re-reading a
  400–700k context. The plugin hands off at a budget printed by its own
  scripts (the compaction point minus one task's growth, 465k at a 650000
  window), keeps the execution
  controller on Sonnet, and reads the plan one task at a time instead of whole.
- **Small models executing literally.** Upstream advises picking a model per
  task but has no field for the choice, and the Agent tool could not pass
  reasoning effort before Claude Code 2.1.292 (it now can, but a fleet
  dispatch still passes neither model nor effort, so the pinned pair is what
  runs). Here every task records an implementer from a model ×
  effort grid, the plan's `**Execution:**` line decides inline or subagent
  mode, and `plan-lint` checks the header, the scores and the mode before a
  plan is saved.
- **Judgment in one seat.** Executors and controllers rule only on mechanical
  conflicts and log every ruling. Plan defects, contested findings and
  cannot-verify items go to an Opus judge whose verdicts —
  CONFIRMED-GAP, PARK, AMEND, BLOCKED — are carried out verbatim; AMEND edits
  the plan through `scripts/plan-amend` so the plan on disk stays immutable.
- **Karpathy guidelines baked in.** Think before coding, simplicity first,
  surgical changes, goal-driven verification: in the entry point, the plan
  template, the implementer template and TDD.

**Codex host.** Read [native-codex.md](reference/native-codex.md). Its
`codex-v4` policy routes scores 0–9 through Luna, Sol and Astra with
the same four raw axes; scouts start at Sol medium, judges at Astra high; the
Claude hooks are disabled in the native manifest. Native reviewers have
independent contexts; enforce read-only restrictions where the host allows and
disclose instruction-only restrictions where it does not.

**External CLI lane.** On Claude, a task scoring 2–4 at risk ≤ 1 may run on the
Codex CLI instead of a Claude implementer. The lane needs an exclusively
assigned linked worktree, stable task IDs, approved file paths and durable
recovery; read [external-task-recovery.md](reference/external-task-recovery.md)
before offloading.

## What you get

**Twenty agents in three classes.** Seven execution implementers - Sonnet 5.5
and Opus 5.5 at `low`, `medium`, and `high`, plus one Haiku 4.5 agent - are
everything the assignment table and the escalation ladder can reach; no score
assigns `impl-opus-low` or `impl-opus-medium`; both are reached only by
escalation. Since 1.27.0 no score assigns `impl-haiku` either: total 0 runs on
`impl-sonnet-low`, which cost less per pass in the tier evaluation, and Haiku
is reached only by a human `**Implementer:**` override. Nine reserve implementers - the `xhigh` and `max` efforts, and
every Fable 5.1 tier - are reachable only by a human override, or by a task
that has already been split once and still exhausted `impl-opus-high`. Four
read-only role agents - the judges `judge-opus`, `judge-sonnet-high` and
`judge-fable` (a human override only), and `scout-sonnet` - whose `tools:`
frontmatter omits `Edit`, `Write`, and `Agent`, so a reviewer that cannot
modify the tree or spawn subagents is a fact about the registry rather than a
request in a prompt.

The reserve exists so that a human ruling, and a task that genuinely cannot be
split any further, both have somewhere to go. It is not a way around the gate:
above `impl-opus-high` the first answer to a hard task is still to split it, and
the reserve is only entered when that split has already been spent.

**A four-axis rubric that gates the plan.** Files, spec completeness, coupling,
and risk, each scored 0 to 3. Three of those four measure how the task was
drawn, not how hard the change is, so Rule S sends a task scoring 4 or more
across them back to be split rather than to a larger model. That cap is what
makes the assignment table stop at 6.

**An escalation ladder.** Every execution implementer has exactly one successor,
changing model before effort except at the two Opus effort rows, where Opus is
already the top model and there is nowhere else to go. Walks terminate at a
SPLIT action rather than an agent, and only a task that survives that split
enters the reserve chain, which terminates at BLOCKED. Used at fix rounds 4
and 5, at the BLOCKED handler, and at round 3 when the re-review reports
stalled progress.

**Criteria-scored reviews.** `criteria/` holds narrow scored criteria adapted
from LLM-as-a-Verifier (arXiv:2607.05391): a ground-truth note the judge sees on
every evaluation, and 2 to 4 criteria that each say where to look, what scores
high, what scores low, and what to ignore. Task reviews score four criteria -
spec, scope, verification, quality - 1 to 20 each, alongside the spec and
quality verdicts and never replacing them, because the fix loop keys on those
verdicts. Tasks at risk 3 are reviewed by Codex `gpt-6-astra` and then by
`judge-opus`, which rules CONFIRMED or REJECTED on every Codex finding in the
same pass.

**Best-of-3 approach selection.** `selecting-approaches` gates an open approach
decision to inline, one advisory pass, or three scouts ranked by a judge in a
ring pass that cancels positional bias. Five numbered skip conditions send most
decisions to inline, including bug fixes with a located root cause - where
ranking candidates generated before the root cause is known would launder
guesses into a confident pick.

**Two execution modes, chosen by the plan.** The `**Execution:**` line decides
whether a plan runs under subagent-driven-development, a dispatch and a scored
review per task, or under executing-plans, where one session implements every
task itself. Inline mode is the default unless more than half the tasks are
heavy (total 5 or more, or risk 3). An inline plan delegates its heavy
tasks, which are too large or risky to implement in the session,
and every task carrying an `**Executor:**` line, which runs on that executor
rather than in the session. Each delegated task runs through an implementer
subagent — or, for an Executor line, that executor's wrapper — with the full
per-task review loop, shared with subagent mode in
`reference/delegated-task.md`; the session implements the rest itself, trading
their per-task review for one whole-branch review at the end, which both modes
share. `plan-lint` requires the session's effort to cover the highest score it
implements, and `--effort high` once it delegates. A task that will not
converge after three fix rounds escalates to subagent mode at the next task
boundary, recorded in the ledger both modes write.

**Opt-in parallel waves.** Brainstorming asks, once the approach is settled,
whether the plan should run sequentially (the default) or with parallel
subagents, and records the answer in the spec as `**Execution strategy:**`;
writing-plans asks the same question when a spec carries no answer. A parallel
plan groups its tasks into waves, written `**Parallelism:** waves — 1 | 2-4 | 5`:
contiguous task ranges whose tasks share no file and consume nothing from each
other, with a `**Depends on:**` line on every task. Subagent mode runs a wave's
tasks at once, each in its own git worktree, reviews each exactly as it would a
sequential task, merges each reviewed task with `scripts/wave merge` (which
refuses a task whose files overlap what the wave already merged), and runs the
plan's `**Integration check:**` before the next wave starts. `plan-lint` keeps
risk-3 tasks, executor tasks and dependency-manifest changes alone in their
wave, the pre-flight ruling seat checks every same-wave pair for coupling the
file lists cannot show, and `context-size --wave W` keeps room in the session
for every task running at once. Running a wave one task after another is always
correct, so every doubt serializes it; `reference/parallel-waves.md` holds the
procedure. A plan without a `**Parallelism:**` line runs exactly as before.

**An external executor lane.** A task scoring 2 to 4 with `risk <= 1` can run on
the Codex CLI instead of a Claude implementer, for quota offload onto a separate
ChatGPT subscription and for a second model family in the loop. The lane is a
gate in front of the assignment table, never a rung on the escalation ladder:
offload selects downward at the cheap end while the ladder only moves upward, and
one total order cannot express both. The Claude ladder stays the sole backstop,
so its termination proof is untouched.

The gate floors at score 2 on purpose. Rule S caps `reducible` at 3, so under
`risk <= 1` the eligible totals are exactly 2, 3, and 4; without the floor the
gate would reduce to `risk <= 1` and capture nearly every task by count, and it
would offload score-0 work where the displaced agent is `impl-sonnet-low` and
the wrapper costs more to orchestrate than it saves.

`**Implementer:**` still names the Claude agent for the score. `**Executor:**` is
an override on a second line, which is what makes a machine without Codex, a cold
session, and an executor whose auth has lapsed all degrade by reading a line that
is already there rather than re-deriving the assignment at dispatch. Under
`dr-forge:executing-plans` both lines are read only for the tasks an
inline plan delegates; for the tasks the session implements itself they are
inert, so nothing falls back.

`revising-plans` brings a plan written before the external executor lane up to the current format, scoring what is unscored and writing the `**Executor:**` and `**Execution:**` lines from `scripts/plan-revise`.

The following observations were made against the external CLI lane on Windows
with ChatGPT-subscription auth on 2026-08-31. They are historical CLI policy
evidence, not native Codex capability declarations:

- Only `gpt-5.5` and `gpt-5.6-sol` were available. `luna` and `terra` were
  rejected with HTTP 400 and Codex held no metadata for either.
- Valid reasoning efforts are `low`, `medium`, `high`, `xhigh`, `ultra`.
  `minimal` is rejected. The CLI validates neither model nor effort locally - it
  echoes any string and fails at the API - so `scripts/run-codex-task.sh`
  validates both before spawning anything.
- Codex **cannot commit**. Its Windows restricted-token sandbox denies writes to
  `.git` under `-s workspace-write`, which `codex sandbox -- git add -A`
  reproduces with no model call. The wrapper owns the commit, so the ledger's
  commit range is measured rather than reported. It also inlines the repository's
  `CLAUDE.md` into every prompt, because Codex natively reads only `AGENTS.md`,
  and passes the model's own conventional-commit subject to `git commit`
  unmodified.
- Resume is a request field, not a subcommand. `scripts/lib/codex-client.mjs`
  passes `resumeThreadId`, and the runner re-sends the model and the effort on
  every resumed turn, because a resumed thread that fell back to the user's
  config defaults would run a fix round at a tier the ledger does not record.

Every Codex interaction — the session gate, both runners and the executor
roster — goes through the official `codex@openai-codex` plugin.
`scripts/codex-plugin` locates it for the active profile and enforces a version
allowlist; `scripts/lib/codex-client.mjs` runs one turn through the plugin's own
client and reaps the broker it causes to exist. This plugin never names the
`codex` executable and never reads Codex-owned state.

That probe is a dated observation, not a standing fact: the same two models were
listed in the local catalog on 2026-09-14, and `gpt-6-astra` ran there on that
date. This plugin reads no model catalog at all: the judge seats attempt the preferred
rung and fall back once on a refusal, which is the only evidence of entitlement
that has ever been reliable.

On 2026-09-23 the lane and the judge fallback moved to `gpt-6-sol`: `gpt-5.5`
retires from Codex with ChatGPT sign-in on 2026-10-14, and Codex 0.155.1's
catalog lists `gpt-6-sol` as the upgrade for `gpt-5.6-sol`, with every lane
effort advertised for a ChatGPT Pro sign-in.

On 2026-10-07 they moved again, to `gpt-6.1-sol`, Codex's default since
0.159.1, and the review seat for totals 4 to 6 moved from Astra to it. The move
rests on OpenAI's description of 6.1 Sol as near-Astra on software work, at
about a fifth of Astra's price; no calibration replay was run, because no Codex
client was available to run one. Native Codex plans moved to `codex-v4`, which
puts `gpt-6.1-sol` at ranks 3 to 6.

A different machine, account, or Codex version must verify the tables against
its own account before relying on them. Do not make paid capability probes.

**Cross-family review.** Codex is the default task reviewer: `gpt-6.1-sol` for
tasks totalling 0 to 6, and `gpt-6-astra` followed by `judge-opus` at risk 3. A task the executor lane implemented is always
reviewed by a Claude judge, so Codex never reviews its own work there; when a
Codex seat produces nothing, `judge-sonnet-high` takes totals 0 to 3 and
`judge-opus` 4 to 6 and at risk 3. Plan review takes Astra for round 1
(`judge-opus` when Codex is off) and `judge-opus` for delta rounds,
capped by the plan's highest task total.
The final whole-branch review runs on `judge-opus`, its one fix subagent on
the highest tier among the tasks the findings touch, and gains a Codex round. When both reviewers return findings,
a fresh `judge-opus` dedupes and verifies them. No route names `judge-fable`:
on 2026-09-23 Opus 5.5 at high effort matched or beat Fable 5.1 on two replayed reviews with
known defects, at about 40% of the cost, so Fable is dispatched on a judge seat
only when you ask for it. With one list there is no third seat:
the fixer triages each finding against the code and the scoped re-review rules
on every rejection. The Codex round is not self-review-free, because the branch
contains whatever the executor lane produced, which is why no finding is acted
on unchecked.
`scripts/review-route` prints the review seat for a task or plan round, and
every Codex seat runs through `scripts/run-codex-review.sh`, which checks
availability on each run and falls back once to `gpt-6.1-sol` when Astra
refuses the run. Selection, the run bound and the four
outcomes live in those scripts rather than in prose, so a refused model is a
recorded substitution instead of a silently missing seat.

**The Codex session gate.** Before any Codex use, `scripts/codex-gate` checks the official codex plugin
once per session - enabled, installed at an allowed version, logged in, not on
a free ChatGPT plan, and within quota - through the plugin's own client, and
caches the answer per session. When Codex is unusable, every Codex seat, the final-review Codex round,
the executor lane and `plan-lint`'s lane probe are skipped for the session and
Claude seats take over; a quota error mid-run turns Codex off the same way. A
usable Codex is still used only on a surface whose shipping gate passed,
recorded per surface in `reference/codex-plugin.json`: the calibration replay
opens the review seats, and the executor-lane smoke test opens the lane.

**Project state.** `docs/forge/` holds what a project knows about
  itself, not just its specs and plans: `gates.md` declares the verification
  gates in order, `plans/completed.md` indexes merged plans, and `distilled/`
  holds four durable files — constraints, gotchas, reference, rejected —
  collapsed from session notes. Three skills use it. `project-status` reports
  where the work stands and exactly one next step, and writes nothing.
  `running-gates` runs the declared gates in order and stops at the first red,
  judging each by its `Evidence` type so a gate whose proof is a picture is
  never passed off a metric. `distilling-docs` distils notes into the four files
  and deletes the tracked sources it absorbed, once an independent judge has
  confirmed every enumerated fact was carried. Every one of these files is
  optional; a project without them behaves exactly as before.

**Test simplification.** `test-simplifier` shrinks a suite that TDD has grown
  slow, in the order that risks the least. `scripts/test-profile` reads the
  JUnit XML reports a runner already emits and prints a short table of where
  the time goes. Then the skill speeds tests up without deleting any, tiers the
  run into an inner loop, a branch gate and a full sweep, and only then merges
  or removes tests, one module per wave. A wave changes test files only, and
  stands only when every mutant the old tests killed is still killed (or, with
  no mutation tool, every fault a judge named still turns the suite red) and
  `judge-opus` returns `KEPT`. Coverage alone never proves a test redundant.
  `test-driven-development` and `writing-plans` now place each test at the
  lowest layer that can fail for its change, so the suite stops regrowing.

**darkmem mirror (optional, off by default).** `scripts/darkmem-sync` keeps
  a repository's planning documents and progress in a darkmem instance over
  its keyed REST routes. It does nothing until you opt in: turn on **Use
  darkmem** (`darkmemEnabled`) in the cockpit's darkmem settings or with
  `bash <plugin-root>/scripts/forge-config set darkmemEnabled true`, and map
  the repository's primary checkout in `~/.dr-forge/config.json` —
  `{"darkmem": {"url": "http://<host>:8000", "api_key_env": "DARKMEM_API_KEY", "repos": {"<primary checkout path>": {"project": "<name>"}}}}`
  — and export a `dmk_` key in that variable. The repository then syncs a
  mirror at `~/.dr-forge/mirror/<project>/`, whose documents live under the
  darkmem uri prefix `forge/`. The key needs the `read` and `capture` scopes,
  and `import --replace` also `admin`. Two settings choose each family's
  store while darkmem is on: `documentStore` (specs, plans, registers, notes)
  and `progressSource` (ledgers and handoffs), `local` or `darkmem`, both
  `darkmem` by default; a mapping entry may override either, for example
  `{"project": "plugins", "documentStore": "local"}`. `~/.dr-forge/stores.json`
  records where each family actually lives, with its project and mirror, and
  the scripts and skills read and write there through `scripts/lib/roots.sh`
  and `scripts/forge-path`.
  `pull` fetches what changed; `push` sends documents under their last synced
  hash and each new ledger line as its own entry, with `task`, `state` and
  `commit` properties a progress board can read; `status` lists each family's
  store and local changes;
  `import` files an existing `docs/forge/` and its ledgers once, verified byte
  for byte. A store that changes moves its family at the next session start
  with no plan in progress and no auto run active:
  `reconcile` copies the files across, verifies every hash, records the new
  store in `stores.json`, and leaves documents leaving the repository as a
  staged `git rm` for you to commit. Every move refuses, naming the reason,
  while a plan is in progress (a ledger whose plan `completed.md` does not
  record) or an auto run is active. A move into darkmem also refuses while
  darkmem is unreachable or the key is unset, while a linked worktree holds
  documents the primary checkout does not, or when a file cannot be carried
  (a dotfile, a symbolic link, an empty or non-UTF-8 file, a name some
  platform cannot hold, a case twin, an ignored file); it never overwrites a different darkmem copy, and moved
  progress files are kept under a dated `moved-<stamp>` backup.
  **Falling back to the file system.** While darkmem is on, the mirror is plain
  local files: without the key or the server, work goes on from it and `pull`
  and `push` say why they skipped. Turn darkmem off (`darkmemEnabled` false) or
  remove the mapping, and the next session start with no plan in progress
  moves every family back into the repository from the mirror alone, without
  asking darkmem, naming each file darkmem does not hold as the mirror does and keeping the mirror
  as a dated `forge-moved-<stamp>` / `work-moved-<stamp>` backup; until then
  the scripts keep reading the mirror, and `push` and `pull` do nothing. A
  store set back to `local` while darkmem is on and reachable is pulled from
  darkmem first. A repository a 2.x release moved into darkmem stays there,
  unsynced, while `darkmemEnabled` is unset: each session start says so until
  you set it either way. A repository with no mapping but a record that still
  places a family in the mirror is read and reconciled the same way: the
  scripts read the mirror until a session start with no plan in progress
  moves the family back. Without the darkmem MCP tools, or with darkmem off,
  the durable facts the skills would file with `memory_add` go to
  `<docs>/notes/<date>-facts.md` instead. Session start runs `reconcile` and
  `pull`; the skills' stop points run `push`, and a
  background Stop hook pushes as a safety net, the whole run bounded at 100
  seconds (SIGTERM, then SIGKILL after 5 seconds). `push` waits up to 100
  seconds for another run's mirror lock before refusing;
  `DARKMEM_SYNC_LOCK_WAIT_MS` sets that wait in milliseconds, and a value that
  is not a positive number means the 100 seconds. The Stop hook's push never
  waits: it refuses at once while another run holds the lock and the next stop
  sends what it missed. A
  move stopped part-way through filing a ledger resumes it at the next session
  start. A document deleted from the mirror is archived on darkmem under
  `forge/archive/<stamp>/` and `restore <name>` brings it back;
  `revision <name>` prints the `<name>@r<id>` a distilled `Source:` line
  cites. `docs/superpowers/<rest>` and `docs/forge/<rest>` name the same
  document everywhere names are compared, so historical plans keep resolving.
  A conflict is reported, never merged. Without a mapping every command but
  `import` prints one line and does nothing.

## Requirements

**The upstream workflow ships in-plugin.** The fork carries the full skill
set — brainstorming through finishing-a-development-branch — frozen at upstream
6.3.0, so no other plugin is required: every agent definition preloads
`dr-forge:verification-before-completion` through its `skills:`
frontmatter, and writing-plans and subagent-driven-development use the plugin's own
`scripts/sdd-workspace`, `task-brief`, `review-package`, `next-step`,
`context-size`, `repo-audit`, `plan-lint`, and `plan-amend` — `next-step` ends every session with its next
action and keeps `.forge/handoff/latest.md` pointing at it. Disable the
upstream `superpowers` plugin: same-named skills in two enabled plugins can
double-trigger.

**Bash, jq, Git, and GNU timeout/coreutils.** These are requirements of the external executor lane:
`scripts/detect-executors.sh` builds every field with `jq`, and
`scripts/run-codex-task.sh` parses Codex's verdict with it. Each exits 2 with a
message naming the dependency rather than degrading, because a missing `jq`
would otherwise read as "no executor usable" or as a task Codex blocked on. The
SessionStart hook is the lenient case: without `jq` it still injects the entry
point and only skips persisting the session record, and `bash` is required for
it to run at all. On Windows that means Git for
Windows. The hook declares `"shell": "bash"` so it takes the Git Bash
route explicitly: without that key Claude Code falls back to PowerShell on a
machine with no Git Bash, where the command is meaningless, and with it the
user gets Claude Code's actionable "requires bash but Git Bash was not found"
message instead.

## How it fires

A `SessionStart` hook (matcher `startup|resume|clear|compact`) injects the
`dr-forge:using-forge` entry point as `additionalContext`, so every
session starts with the skill-routing rules — including the pointers to
`selecting-approaches`, implementer assignment in `writing-plans`, and tiered
dispatch in `subagent-driven-development` that a PreToolUse nudge used to add. The same
script persists the session's `transcript_path`, `session_id`, `cwd`, and
`source` to `~/.claude/dr-forge/sessions/by-id/<sanitized-session-id>.json`
and to `~/.claude/dr-forge/sessions/<sanitized-cwd>.json` (last writer
wins per directory). `scripts/context-size` reads the session's own record by
`CLAUDE_CODE_SESSION_ID`, so two sessions in one checkout each measure their
own transcript, and falls back to the directory's record. A record no
session start has rewritten for 30 days is deleted. On the
`compact` source it also appends a compaction snapshot (see Session budget).
Malformed stdin skips persistence but never blocks the injection, and the
hook always exits 0.

A run must end on its next step: the finishing menu once the final review is
clean, otherwise the `## Next session` block from `next-step`. Controllers,
Sonnet especially, tend to summarize the run and stop instead. A
`UserPromptSubmit` hook stamps the start of each turn under
`~/.claude/dr-forge/sessions/turns/`, and a `Stop` hook checks whether
that turn wrote a plan ledger (`.forge/sdd/*/progress.md`). If it did and
the last message carries neither ending, the hook blocks the stop once and
tells Claude which one is missing. The retry always passes, and without `jq`,
a stamp or a ledger written this turn, the hook does nothing. While an agent or
command the session started in the background has not reported back, a plain
stop passes (the controller is waiting on it), and a message that ends the
session over it, with the next-step block or the finishing menu, is held once
in any turn: a handoff there would invite ending a session whose work is still
in flight. Work stopped with `TaskStop`, and work launched before the session
last started or resumed, sends no notification and does not count as running.
An agent that sent its report but left a shell or agent of its own alive still
counts: Claude Code keeps listing it, and its notification says so.
`scripts/in-flight` prints the same list on demand; handoff step 0 and the
finishing menu run it, and `scripts/next-step` prints no block (exit 5) while
anything is on it.
When the turn wrote more than one ledger, each one must have its
ending. Each hold also shows you a one-line note saying why the session went
on.

Unplanned work gets the same hold. The prompt hook also records which commits
the repository's local branches point at. A turn that wrote no ledger but
changed that set (a commit, a merge, or deleting a branch's only pointer to a
commit) in a project with forge docs must end on the `## Next session` block
from `next-step --adhoc`, the finishing menu, or finishing's "No plan file"
line. Otherwise the hook holds the stop once and tells Claude to continue
remaining work, finish a branch that is ready to integrate, or print the block. Creating
a branch on an existing commit, or a stop in another repository than the
prompt's, does not count.

A run also asks one question before its first task: what finishing should do
if its menu goes unanswered for the configured wait, 30 minutes by default
(merge locally, push and open a pull request, keep the branch, or wait).
`scripts/finish-choice` keeps the answer beside the ledger
(`.forge/sdd/<plan>/finish.json`, or `.forge/sdd/finish.json` for work done
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

See [reference/finish-preference.md](reference/finish-preference.md).

Codex has no Stop hook: the Codex manifest declares no hooks, so nothing
catches a summarize-and-stop there. On Codex you must run `next-step` yourself
on every early stop.

## Session budget

Long sessions cost more than they look: every request re-reads the whole
context, and compaction drops the reports, findings and rulings a controller
needs. dr-forge hands off instead.

- **The budget line.** `scripts/task-brief` and `scripts/review-package` end
  with `budget: 312k of 465k (67%) — ok — source: record`, so the controller
  checks before every task and every review at no extra request;
  `scripts/context-size` prints it on demand. At `handoff`, the `handoff`
  skill writes `latest.md` and the plan's `handoff.md` and ends with the
  resume guide from `scripts/next-step`.
- **Stops.** A saved plan and a switch from inline to subagent mode are hard
  stops; a finished task list is a soft stop in both modes, so the final
  whole-branch review and finishing run in the same session unless
  `scripts/context-size --final` says otherwise after the last task: the final
  phase has its own limit, 85% of the compaction window, which the plan's
  last two tasks share, and finishing itself is never budget-checked. A
  `handoff` verdict waits for the task in flight to complete. The
  budget is the compaction point minus one task's worst growth, derived from
  `autoCompactWindow` and the model's window; see
  [session-budget.md](reference/session-budget.md) for the numbers and the
  full Stops table.
- **Resuming.** `resume-execution` runs `scripts/repo-audit` — one read-only
  snapshot of branch, worktrees, dirty files, plans in flight and handoff
  staleness — verifies the worktree, and hands control back to the plan's
  execution skill.
- **Compaction.** The SessionStart hook appends a snapshot of what summaries
  drop. Compaction fires at about 93-96% of `autoCompactWindow`, so set the
  window to suit you — the budget follows it, 465k at 650000 — and paste the
  Compact Instructions block from
  [session-budget.md](reference/session-budget.md) into your project's
  CLAUDE.md.

### Auto run

After you approve a design, brainstorming can offer to run the rest
unattended. Fable reviews the spec, the plan is written and reviewed, the plan
executes in its recorded strategy, and the branch is finished by
`finishAction` into the branch the run started from (kept under `ask` or
`wait`), with no question to you. What Opus cannot rule goes to Fable in one
batch; what Fable cannot rule is deferred on the run's register. Instead of
handing off, the session compacts at the handoff budget, and the cockpit
clears and resumes it when a compaction leaves too much. The pane shows the
run and a **Stop auto** button. A run's turn that ends without its sentinel
line is held up to three times in a row, retries included; then the run stops
with a reason, which the cockpit sends to Discord. See
[auto-run.md](reference/auto-run.md).

## Cockpit

Claude Code only. Built and tested against Claude Code 2.1.295 to 2.1.296; the
mod API is early access and may change between releases.

### What it does

**Cockpit pane.** A pane with the session at a glance. It opens by itself when
a session starts, once the terminal is 144 columns wide; `/cockpit` opens it at
any width, and says why if Claude Code holds it back. In fullscreen at 110
columns or more it docks beside the transcript; otherwise it sits above the
prompt. In the full layout each section is a framed card in its own color, its
headline on the title line, under one **Now** row that says what the
session is doing:

```
● running 2m14s · step 18 · Bash in impl-sonnet-low
╭ Account ──────────────────────────── subscription ╮
│ ● you@example.com                                 │
│   You · Acme (admin)                              │
│   Opus 5.5 · xhigh effort                         │
│   Remote ● connected · phone                      │
│   config ~/.claude                                │
╰───────────────────────────────────────────────────╯
╭ Context ─────────────────── 68% of handoff · ≈7 turns ╮
│ ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▱▱▱▱▱▱▱┃▱▱▱▱▱┊▱▱▱▱▱▱▱▱▱▱▱▱▱▱ │
│ 412k of 1.0M ┃ handoff 604k ┊ compacts 744k      │
│ trend ▁▂▃▃▄▄▅▆▆▇▇█ +23k                           │
│ ██████████████████████████████████████▓▓▓▓▒▒▒░░  │
│   ■ Messages              318k  78%               │
│   ■ System tools           41k  10%               │
│ ╭──────────╮ ╭─────────╮ ╭──────────╮             │
│ │ Hand off │ │ Compact │ │ Settings │             │
│ ╰──────────╯ ╰─────────╯ ╰──────────╯             │
╰───────────────────────────────────────────────────╯
╭ Usage ──────────────────────────── $4.85 · $2.35/h ╮
│ 5h  ▰▰▰▰▰┊▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱  23%     │
│     resets in 3h40m · on pace                     │
╰───────────────────────────────────────────────────╯
╭ Shells ─────────────────────────────── $ 1 running ╮
│ $ npm run dev 12m04s                              │
╰───────────────────────────────────────────────────╯
╭ Agents ───────────────────────── ● 1 running ✓ 2 ╮
│ ● impl-sonnet-low Task 4 4m17s                    │
│ ✓ reviewer-opus Review task 3                     │
│ Seats by input                                    │
│   impl-sonnet-low ×1                              │
│   ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰ 120k in · 80% cached · 7k out  │
╰───────────────────────────────────────────────────╯
╭ Run ────────────────────────────── round 2/5 · 3/6 ╮
│ ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱ │
│ plan docs/plans/cockpit.md                        │
│ ✓ Task 3: Draw the context section · clean        │
│ ▸ Task 4: Draw usage and agents                   │
│   round 2/5 · impl-sonnet-low                     │
│ ○ Task 5: Track the plan and repo                 │
╰───────────────────────────────────────────────────╯
╭ Repo ─────────────────────────────────── ● dirty ╮
│ repo darkraise/darkraise-ai-plugins               │
│ dir  ~/code/darkraise-ai-plugins/plugins          │
│ ⎇ feat/cockpit-pane-overhaul ↑3                   │
│ ~2 changed ?1 untracked                           │
╰───────────────────────────────────────────────────╯
```

The context track runs over the whole window: the fill is the reading, `┃` the
handoff budget and `┊` where auto-compaction runs. The trend line is the
session's recent readings. The colored bar splits the context by `/context`
category, each color matching its row. On a usage-limit meter `┊` marks how far
through its window the limit is, so a fill past it is spending faster than the
window refills.

In the Claude desktop app (its Code tab) the pane is laid out as a flight
deck. The account comes first, then what Claude is doing, then three gauges:
the context against its handoff budget with the turns left, and the 5-hour and
7-day limits, each with a tick where its window has run to, its reset and its
forecast. The gauges sit in framed tiles that span the same width as the
panels; a narrow pane moves the context to its own row, then stacks every
tile. Every other section follows as a softly filled panel with a colored
lamp; the usage panel says how far each window has run. The desktop's own text
has one size and spaces rows a whole line apart, so each panel's rows, chips
and charts are drawn as one picture at their own sizes and gaps, its text in
your system's light or dark tones (its words are in the picture's alt text).
The buttons are the desktop's own. With **Show at start** on it opens once the
desktop window joins the session, unless you closed it.

- **Now** is the turn in flight: running with its time, step, tool and the
  subagent calling it; waiting for your approval; Claude asking you something;
  idle with the last turn's length; the last turn failed; or Esc
  interrupted it, with the background shells and agents still running after
  it (Esc stops the turn, not them). It adds
  `Discord ✓` once a notification went out for what it shows.
- **Account** is who the session runs as: the email, name, organization and
  role from the account's `.claude.json` (under `CLAUDE_CONFIG_DIR` when set),
  the billing type, the model and effort the last request used, Remote Control,
  and the config directory. Remote reads `connected` with the devices attached
  (a phone, the desktop app), `on · no device yet` when "Enable Remote Control
  for all sessions" is on in `/config`, and `not connected` otherwise; a session
  started with `/remote-control` reads `not connected` until a device joins. Its frame takes one of eight colors picked from the config
  directory, so each account keeps its own.
- **Context** is the main session against its handoff budget, the window and
  where auto-compaction runs, and the largest `/context` categories, estimated
  locally with no API calls. The title adds about how many turns are left to
  the budget at the pace of the last few. **Hand off** appears in
  `dr-forge` sessions.
- **Resumable work** is a card at the top of the pane, framed in the accent
  color, when `.forge/handoff/latest.md` is under three days old and its
  `## Next session` block has a first prompt to paste (a finished plan, or a
  task blocked on your ruling, has none). It names the note's age and its
  **Next:** line, and **Resume** (`r`) queues the prompt that resumes it. The
  same offer rides in a band above the prompt, over the minimized band when
  there is one, with **Resume** and **Dismiss**. Pressing either in one place
  removes both for this session; so does an auto run, or the session starting
  on a plan.
- **Usage** is the account's 5-hour and 7-day limits with their resets, and the
  session's cost and cost per hour. Once a window is ten minutes old each meter
  says whether the limit lasts to its reset at the pace so far (`on pace`), or
  when it runs out first, in amber.
- **Shells** lists the background shells still running (a Bash call sent to
  the background, by Claude or with Ctrl+B) with how long each has run, to the
  second, until its notification or a stop ends it. The card shows only while
  one runs.
- **Agents** lists the subagents running, each timed to the second, and those
  recently finished, then each subagent type (seat) with its runs, input
  tokens, the share served from the prompt cache and output tokens. Use it to see where a plan's tokens go.
- **Plan** follows the main session's todo list or task list, centred on the
  item in progress. In a `dr-forge` run it becomes **Run**, read from the
  run's ledger (`.forge/sdd/<run>/progress.md`) and its plan: the review
  round in flight, the tasks done, which were reviewed clean, and a blocked
  task in red with its reason. A run whose tasks were all done before the
  session started is left out, so a new session starts without it. Its
  **Finish** row shows what dr-forge will do if the finishing menu goes
  unanswered (the option chosen before the run), then counts down the menu's
  wait (`⏱ Finish push and open a PR · in 23m`) and says once it was
  carried out. It disappears when you answer the menu yourself. Work done
  without a plan shows the row on the Plan card.
- **Repo** names the repository (`owner/name` from its remote, else its folder)
  and the working folder, then the branch, ahead and behind counts and changes.
- **Guard** lists commits and pull requests the attribution guard refused.

**Minimize** (`m`) closes the pane and draws the cockpit as a band directly
above the prompt, across the transcript's width. **Expand** on the band's top
rule opens the pane again, and so does `/cockpit`. Each saves the `layout`
setting, so the next session opens the same way: a minimized cockpit starts
with the band and no pane. `/cockpit settings` still opens the settings, and
**Back** closes them again. Minimize is offered in the terminal and the desktop
app, the two that draw above the prompt; elsewhere a minimized cockpit shows
nothing until `/cockpit` opens it. The band is also what a pane that is not
docked draws (`layout` `auto`, the default). Its frame takes the account's
color, with the email, billing and Remote Control on the top rule. The first
line has the
context against the handoff budget with the turns left, and the 5-hour and
7-day limits with their pace (`on pace`, or when the window runs out before
it resets). The second has the subagents running, the background shells with
how long the longest has run, and the folder with the branch, ahead and behind
counts and changes. A blocked run task or a refused command adds a red line.

```
╭─ you@example.com · subscription · Remote ● connected ───────────────────────────────── Expand ─╮
│ ctx ▰▰▰▰▱▱▱┃▱▱ 61% · ≈9 turns  ·  5h ▰▰▱▱┊▱▱▱ 23% on pace · 3h40m  ·  7d ▰▰▰┊▰▱▱▱ 61% out in 2d4h │
│ ● 1 agent  ·  $ 2 shells · longest 12m  ·  ~/code/shop/web ⎇ feat/pane* ↑2 ↓1 ~1 ?1              │
╰─────────────────────────────────────────────────────────────────────────────────────────────────╯
```

Each line shrinks a step at a time until it fits: the meters narrow and then
show the percentage alone, the labels shorten, and the path keeps the
repository's name. Below 48 columns the frame goes and the email sits beside
**Expand**. The pane draws no Nerd Font icons. In the desktop app the band is
one card with slim meters whose ticks mark how far each window has run.

Each button sits in a rounded box, the letter of its hotkey underlined in the
label as a desktop app marks one; the hotkey presses it while the pane has the
keyboard: `h` **Hand off**, `r` **Resume**, `c` **Compact**, `s` **Settings**, `m` **Minimize**,
and `b` **Back** in the settings view. Before Claude Code 2.1.295, which first
draws a styled label, the hotkey leads the label instead (`c: Compact`). The box is gray at rest and takes the accent color on the one
that matters: **Hand off** once the context passes `warnAt`, **Resume**
whenever it shows. In the settings view a switch reads `● On` or `○ Off`, the
chosen option of a row takes the accent, and what is off is drawn dim.

**Settings view.** **Settings** (or `/cockpit settings`) turns the pane into the
mod's settings: whether it shows at session start, the layout, which sections
show, the handoff budget, where Hand off takes the accent and the Discord limit
message goes out, how many context rows to list, the note and guard switches, and the
Discord notifications. Each press saves
the setting to `~/.dr-forge/config.json`, and the pane redraws with it. **Back** (`b`)
returns to the cockpit.

The breakdown and the repo are read after each turn while the pane is open, and
when it opens; nothing in the pane costs the model context.

The cockpit never pops up a banner. Usage limits show in the gauges and the
band, and a Discord message that fails to send shows in the settings view.

**Handoff reading.** The handoff reading shows only in the cockpit: the
Context card and the band. The main session re-reads its whole context on every request, so a session that
runs past its budget pays for it on each turn after. In a session running
`dr-forge` (one that has loaded one of its skills or started one of its
agents), **Hand off** queues a prompt asking the controller to finish the task
in flight and hand off with the `handoff` skill. Past the budget the mod also
adds one note to the conversation saying the same, so a controller deep in a
long turn sees it before its next task. A compaction clears the reading until
the next response, and re-arms the note.

**Discord notifications.** The mod can post to a Discord channel when the
session needs you, which works the same over ssh and tmux. Create a webhook
(channel settings → Integrations → Webhooks → copy URL) and paste it in the
settings view's **Notifications** group, or run `/cockpit notify url <url>`.
It is kept in the plugin's own store, not in `settings.json`, and only ever
shows masked; `DR_FORGE_NOTIFY_URL` in the environment wins over it (`DR_COCKPIT_NOTIFY_URL` still read). **Send
test** (or `/cockpit notify test`) posts a sample. Set your Discord user id
(**Mention**, or `/cockpit notify mention <id>`) to be pinged for the events
that need you; everything else posts silently.

| Event | When | Default | Pings |
| --- | --- | --- | --- |
| `ask` | A tool call waits for your approval past `notifyAskAfter`; the message is edited once you approve or deny it | on | yes |
| `question` | Claude asks you something or has a plan ready, likewise | on | yes |
| `done` | A turn ends after running at least `notifyAfter` seconds | on | no |
| `error` | A turn fails | on | yes |
| `blocked` | A `dr-forge` task is blocked | on | yes |
| `budget` | The context crosses the handoff budget | on | no |
| `limit` | A usage limit crosses `limitAlertAt` | on | no |
| `task` | A run's task completes, or its final review is clean | off | no |
| `session` | The session ends, with its resume command | off | no |
| `agent` | A subagent finishes | off | no |

Each message names the host, repository, branch, account and tmux session it
came from. Command and answer excerpts are cut short and pass through a
redactor that masks common tokens and `key=`/`token=`/`password=` values;
`notifyDetail` `brief` leaves them out. A turn you interrupt sends nothing, and
approvals are not watched when the session runs in `auto`, `bypassPermissions`
or `dontAsk` mode.

**Attribution guard.** Claude Code asks the model to add a `Co-Authored-By`
trailer to commits and a "Generated with Claude Code" footer to pull requests.
The mod blanks both where the engine composes them, and refuses a `git commit`,
`gh pr create`/`edit` or GitHub pull-request tool call that still carries AI
attribution (an AI `Co-Authored-By`, `Claude-Session`, "Generated with Claude
Code" or a Claude session link). Human co-authors pass.

### Settings

Open the settings with **Settings** in the pane or `/cockpit settings`. They are
one tab per group: press `1` to `6` to switch, `i` to hide or show each
setting's description, and `b` to go back. A row whose value differs from its
default is marked `*` and shows the default with a **Reset**; `r` resets the
whole tab after a second press. Numbers step with `−` and `+` or take a typed
value with **Edit**. A value forced from outside (an environment variable, or
a project or managed Claude settings file) shows what forces it and no
controls.

The same settings can be set with
`bash <plugin-root>/scripts/forge-config set <key> <value>` or by editing
`~/.dr-forge/config.json`:

```json
{ "layout": "compact", "handoffMode": "relaxed", "finishAction": "pr" }
```

`forge-config get --json` prints every value in force, and
`forge-config workflow` prints the line the skills read.

| Tab | Option | Default | Effect |
| --- | --- | --- | --- |
| Cockpit | `openAtStart` | `true` | Open the pane when a session starts. Claude Code shows it once the terminal is 144 columns wide (110 once you have opened it before); `/cockpit` opens it at any width. |
| Cockpit | `layout` | `auto` | `auto`: the full layout docked beside the transcript, the band in a pane above the prompt. `full`: always the full layout. `compact`: minimized, no pane and the band above the prompt. **Minimize** sets `compact`, **Expand** sets `auto` (`full` where the pane does not dock). |
| Cockpit | `sections` | empty | The pane's sections and their order, comma-separated: `account`, `context`, `usage`, `shells`, `agents`, `plan`, `repo`, `guard`. Empty shows all eight. The band always draws its own lines. |
| Cockpit | `breakdownRows` | `6` | How many `/context` categories the Context section lists, largest first, up to 12. `0` hides them. |
| Cockpit | `guardAttribution` | `true` | Blank the engine's attribution text and refuse git writes that carry it. |
| Context | `handoffTokens` | `0` | The handoff budget in tokens, for the pane and the budget scripts alike. `0` follows dr-forge's own rule: 93% of the smaller of `autoCompactWindow` and the model's window, minus 140,000. `DR_FORGE_BUDGET` overrides it. |
| Context | `handoffMode` | `strict` | `strict` hands off at the handoff budget. `relaxed` measures every task against the final-phase limit, 85% of the window, so a session carries a plan further; a worst-case fix loop late in such a session may compact, and the compaction snapshot carries it on. |
| Context | `warnAt` | `80` | Where **Hand off** takes the accent color, as a percentage of the handoff budget (1-99). |
| Context | `nudgeModel` | `true` | Add the one note to the conversation at the budget, in `dr-forge` sessions. |
| Context | `autoCompactWindow` | `0` | Claude's own `autoCompactWindow`, written to Claude's user settings file: `0` leaves it unset, else 100,000 to 1,000,000. Applies from the next session. |
| Context | `autoCompactEnabled` | `true` | Claude's own `autoCompactEnabled`, written to the same file. Applies from the next session. |
| Workflow | `codexLane` | `true` | Give plan tasks to Codex when its gate passes. `false` makes `scripts/codex-gate` report `lane=false`. |
| Workflow | `codexReview` | `true` | Let Codex take review seats when its gate passes. `false` makes the gate report `review=false`; with both off it does not probe Codex at all. |
| Workflow | `executionStrategy` | `ask` | `sequential` or `parallel` answers the "how should the plan execute" question. `parallel` still falls back to sequential when the parts share files, and on Codex. |
| Workflow | `executionMode` | `auto` | `auto` follows the planner's rule; `inline` and `subagent` fix the plan's Execution line, and `inline` also makes the plan sequential. |
| Workflow | `worktree` | `ask` | `always` isolates work in a git worktree without asking, `never` works in place, `ask` keeps the consent question. |
| Workflow | `autoRun` | `ask` | `ask` offers, once the design is approved, to run the spec, plan, execution, review and finish unattended (Claude Code only); `off` never offers it. See [Auto run](#auto-run). |
| Process | `processBias` | `standard` | How readily a request gets a written spec and plan: `lighter` resolves doubt to a short in-chat design, `heavier` to a spec. |
| Process | `designApproval` | `sections` | `sections` approves each design section in turn; `whole` presents the design once with one approval. |
| Process | `specReview` | `true` | Stop for you to review the written spec before the plan is written. |
| Process | `questionStyle` | `single` | `single` asks one clarifying question per message; `batched` asks them all in one. |
| Finish | `finishAction` | `ask` | What happens when the finish menu goes unanswered. `ask` keeps the question before the first task; `merge`, `pr` or `keep` skips it and runs after the wait; `wait` skips it and never acts. |
| Finish | `finishTimeout` | `30` | Minutes the finish menu waits before that action runs (5-240). |
| Notifications | `limitAlertAt` | `90` | The share at which a usage limit sends the Discord `limit` message, in percent. `0` turns it off. |
| Notifications | `notifyOn` | empty | The Discord events to send, comma-separated (see above). Empty sends the default set; `none` sends nothing. |
| Notifications | `notifyAfter` | `60` | Seconds a turn must run before `done` sends. `0` sends every turn. |
| Notifications | `notifyAskAfter` | `20` | Seconds an approval or question waits before it sends. `0` sends at once. |
| Notifications | `notifyDetail` | `full` | `full` includes command and answer excerpts; `brief` sends titles and fields only. |
| darkmem | `darkmemEnabled` | `false` | Use darkmem for mapped repositories. Off keeps everything in the repository, and a family already in the mirror moves back at the next session start with no plan in progress, from the mirror alone. |
| darkmem | `documentStore` | `darkmem` | While darkmem is on, where a mapped repository keeps its specs, plans, registers and notes: `local` in the repository, `darkmem` through the mirror. A mapping entry's own `documentStore` outranks it; an unmapped repository is local, though a family its record still places in the mirror is read there until a session start with no plan in progress moves it back. |
| darkmem | `progressSource` | `darkmem` | The same choice for plan ledgers and handoffs. A mapping entry's own `progressSource` outranks it. |

The cockpit settings (Cockpit, Context, Notifications) apply at once, except
the two Claude keys, which Claude reads at its next session start. A
Workflow or Process setting reaches the skills through one line injected at
session start; when you change one mid-session, the cockpit adds a note to the
conversation as the settings close. The Codex switches, the handoff mode and
the finish settings are read by the scripts each time they run. Your own
instructions always outrank a setting, and no setting removes the approval
before implementation.

### Install

```text
/plugin marketplace add darkraise/darkraise-ai-plugins
/plugin install dr-forge@darkraise
```

An installed copy stays at the version it was installed at. To take a new
release, run `claude plugin update dr-forge@darkraise` and start a new session
(or run `/reload-plugins`).

### Development

```text
claude plugin validate plugins/dr-forge
claude plugin test plugins/dr-forge
claude --plugin-dir plugins/dr-forge
```

The last loads the working copy into a session and reloads it on save. The
engine lays its type declarations under `.claude-plugin/types/` when it loads
the folder; they are not committed.

## Migrating from 0.x

1.0.0 is standalone and breaking. On a machine with the old setup:

1. **Re-point the marketplace.** The `darkraise` marketplace registration in
   `~/.claude/settings.json` may still name `darkraise/claude-code-plugins`;
   the canonical repository is `darkraise/darkraise-ai-plugins`. Remove and
   re-add the marketplace (or edit the registration) to point there.
2. **Statusline.** `dcc-statusline` is `dr-status` in this catalog; enable
   `dr-status@darkraise` and disable the old name.
3. **Telegram notifications.** `dcc-telegram-notify` is not in this catalog;
   keep it installed from its previous source or drop it.
4. **Disable the superseded plugins:** `superpowers` (its skills now ship
   here), `dcc-superpower-companions` (folded into this plugin), and
   `andrej-karpathy-skills` (its guidelines are folded into the skills where
   they fire).

## Migrating from dr-superpowers and dr-cockpit

dr-forge 2.0.0 replaces both plugins. Install dr-forge and start one session
before you uninstall the old plugins, because the first session reads their
saved settings:

    /plugin install dr-forge@darkraise
    /plugin uninstall dr-superpowers@darkraise
    /plugin uninstall dr-cockpit@darkraise

The first session imports the cockpit's options into
`~/.dr-forge/config.json`, and the cockpit's Discord webhook and mention into
dr-forge's own plugin store, once; the old files stay. Since 3.0.0 the
dr-superpowers names are no longer read: see Migrating to 3.0.

## Migrating to 3.0

dr-forge 3.0.0 reads and writes only its own names: `.forge/`, `docs/forge/`,
the git directory's `dr-forge/`, `~/.dr-forge/`, the `DR_FORGE_*` variables
and the `dr-forge:` prefix. The pre-2.0 `.superpowers/`, `docs/superpowers/`,
`dr-superpowers/` and `DR_SUPERPOWERS_*` names and the `dr-superpowers`
prefix are no longer read. Session start and `repo-audit` print one line naming
any pre-3.0 directory a repository still has; run, once per repository:

    bash <plugin-root>/scripts/forge-migrate [DIR]

In the primary checkout and every linked worktree it moves `.superpowers/` to
`.forge/`, `docs/superpowers/` to `docs/forge/` (with `git mv` when the
directory is tracked) and `<git dir>/dr-superpowers/` to `<git dir>/dr-forge/`,
then rewrites the lines of `.gitignore`, `.gitattributes` and
`.git/info/exclude` that name the old directories. It prints each move and what
you must commit. A checkout that has both the old and the new directory, or a
`docs/superpowers/` with uncommitted changes, is refused and left as it is;
merge or commit, then run the command again, which does only what is left. It
exits 0 when done or when there was nothing to do, and 1 when something was
refused.

No other file is edited: plans, specs and ledgers that cite
`docs/superpowers/<rest>` keep that spelling, and dr-forge still reads it as
`docs/forge/<rest>`. A plan whose `**Implementer:**` lines name agents under an
older plugin prefix fails `scripts/plan-lint` until they name `dr-forge:`.
Rename any `DR_SUPERPOWERS_*` variable you set to its `DR_FORGE_*` name.
`DR_FORGE_DOCUMENT_STORE` and `DR_FORGE_PROGRESS_SOURCE`, which 2.x read, are
no longer read at all: set `documentStore` and `progressSource` instead.

`forge-migrate` also moves the home: the darkmem mapping in
`~/.dr-superpowers/config.json` into `~/.dr-forge/config.json` when that file
has none, and each `~/.dr-superpowers/mirror/<project>/` that
`~/.dr-forge/mirror/` lacks. darkmem itself is off in 3.0 until you set
`darkmemEnabled`. A mirror's `superpowers/` folder becomes `forge/` at the next
`darkmem-sync` run, and the first online run moves darkmem's `superpowers/`
documents to `forge/`; upgrade every machine that shares a darkmem project,
since a 2.x client no longer sees the moved documents.

## What a plan looks like

A plan opens with a header block: Goal, Spec, the `**Execution:**` line that
decides inline or subagent execution, Global Constraints, Contracts (every name
one task produces and another consumes), Assumptions with evidence, and a Task
index. `scripts/plan-lint` checks it, and a judge reviews it against
`criteria/plan-review.md` before it is saved. That Execution line is binding: a
session does not change mode because subagents happen to be available, and only
your explicit instruction overrides it. Each task then reads:

```markdown
### Task 4: Wire the export pipeline

**Files:**
- Create: `src/export/pipeline.ts`

**Interfaces:**
- Consumes: `formatRow(row: Row): string` from Task 2
- Produces: `runExport(cfg: Config): Promise<Report>`

**Implementer:** dr-forge:impl-sonnet-high
**Evaluation:** files 0 - spec 1 - coupling 2 - risk 2 = 5
**Approach:** inline - skip 2: follows the existing exporter pattern
```

Edit the `**Implementer:**` line to override. `subagent-driven-development`
obeys the line and never recomputes when it is present. Add
`**Override:** <reason>` below the Evaluation line so that `plan-lint` reports
the deviation as a warning instead of an error.

The heading keeps upstream's `### Task N: <name>` form on purpose.
`scripts/task-brief` finds a task by matching a heading that starts with
`Task <N>`, so a heading like `### Wire the export pipeline (Task 4)` yields an
empty brief and a non-zero exit — and, because the extractor keeps copying
until the next heading it recognizes, quietly appends that task's body to the
previous task's brief.

## Differences from upstream 6.3.0

The upstream loop is kept - the brief and report protocol, the review
package, the five-round cap, the breaker (whose adjudication now goes to the ruling seat), and the
handoff to dr-forge:finishing-a-development-branch - with these
differences:

1. **Named seats.** The implementer is the fleet agent the plan's
   `**Implementer:**` line names, dispatched with no `model` argument: passing
   one would override the agent file's model while `effort` kept its
   frontmatter value. The task reviewer is a judge agent scoring the criteria
   file. General-purpose seats still name their model explicitly.
2. **Scores and progress.** Task reviews add four 1-to-20 scores alongside the
   verdicts, and the scoped re-review adds a progress reading that can pull
   escalation from round 4 to round 3.
3. **Escalation ladder.** Rounds 4 and 5 and the BLOCKED handler climb
   [ladder.md](reference/ladder.md)'s table, ending in one split and then the
   reserve chain. An external task hands back to its Claude implementer instead.
4. **Cache-aware resumes.** Fix rounds 1 to 3 resume the implementer only while
   its cache is warm - returned under five minutes ago, or under about 100k
   tokens of context - and otherwise dispatch a fresh copy on the same tier.
5. **One ledger grammar.** Every task gets an assigned line and a complete line
   carrying its scores and a checkpoint (done, verified, remaining, discovered
   issues, assumptions), which crash recovery and the final review read.
6. **Cross-family final review.** The final whole-branch review adds a Codex
   round, and a judge verifies the union of both reviewers' findings.
7. **Rulings, not stops.** Dispatch problems - an unknown agent name, an
   unavailable model, an Executor line the wrapper refuses - are logged
   rulings, never silent fallbacks and never stops.
8. **Session budget.** A budget line, a compaction snapshot, and the
   dr-forge:handoff / dr-forge:resume-execution pair replace
   upstream's unmeasured sessions - see [Session budget](#session-budget).
9. **Small-model planning.** A strong model plans once; small models execute.
   Every task brief carries the header's Global Constraints and Contracts, the
   controller reads only the header and one brief at a time, and judgment
   calls go to a read-only ruling seat (`judge-opus`, with the reason
   `review-route --ruling` prints). Its plan corrections
   land in an append-only `amendments.md` through `scripts/plan-amend`; the
   plan file is never edited during execution.
10. **Two modes, chosen by the plan.** Upstream picks `executing-plans` when
    subagents are unavailable and recommends subagent execution otherwise. Here
    the `**Execution:**` line decides and is binding: `executing-plans` is a
    full inline mode that writes the same ledger, sends its judgment to the
    same ruling seat, and ends at the same shared
    [final-review.md](reference/final-review.md), with no per-task review. A
    task it cannot land in three fix rounds escalates to subagent mode at the
    next task boundary.

## Licenses

MIT. `LICENSES/` carries the licenses of the forked and folded projects:
[superpowers](https://github.com/obra/superpowers) by Jesse Vincent (MIT),
frozen at 6.3.0 with no upstream sync, and
[andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills)
(MIT).

## Tests

```bash
for t in plugins/dr-forge/tests/*.test.sh; do bash "$t"; done
```

Requires `jq` and `git`. No model calls: the executor suites run against a stub
`codex` on `PATH` and a synthetic roster, never the real CLI. `project-status.test.sh`,
`gates-manifest.test.sh` and `distilling-docs.test.sh` check the project-state
skills the same way — structurally, against the documents themselves.
`test-simplifier.test.sh` does the same for that skill and runs
`scripts/test-profile` against fixture reports. `roadmap.test.sh` runs every
`scripts/roadmap` verb against a temporary repository. `turn-end.test.sh`
drives the turn-stamp and Stop hooks against a temporary repository, its
ledgers and its branch heads;
`darkmem-sync/hooks.test.mjs` drives darkmem's session-start sync and the
background Stop push (`scripts/darkmem-stop-push.sh`) against the stub.
`codex-review.test.sh` covers the judge seats' selection and outcome policy
against a stub `codex`, so every branch — refusal, fallback, timeout, empty
report — is exercised without a model call.
`darkmem-sync.test.sh` runs the `node:test` suites under
`tests/darkmem-sync/` against an in-memory stub of darkmem's routes, so no
darkmem instance is needed.

## Reference

`reference/ladder.md` holds the raw rubric, Rule S, and Claude assignment,
escalation, reserve, and external CLI tables. Native Codex reads
`reference/codex-routing.json`; `reference/native-codex.md` explains its weighted
score, request format, and plan conversion. `scripts/select-native-tier.sh`
validates raw scores and history before returning a native routing decision.

`reference/executors/` holds one JSON entry per external executor and
`scripts/executors` is the only reader of it: `executors list` prints every
valid id, `executors get <id> <dotted.key>` one field, and
`executors path <id> <dotted.key>` that field resolved against the plugin root.
An entry names the executor's locator, probe, wrapper, gate, session directory,
surfaces and ladder blocks, so adding an executor is an entry, a wrapper and a
ladder block rather than an edit to every script. `reference/executor-lane.md`
states the entry schema and holds the Claude-hosted external executor lanes,
`reference/session-budget.md` holds the budget numbers, checkpoints,
stops and the Compact Instructions block, and `reference/final-review.md` holds
the whole-branch review both execution skills end at.
`scripts/run-codex-review.sh` runs every Codex review seat: it
selects the judge rung from `codex-judge`, bounds the run, and classifies the
outcome as `OK`, `FALLBACK`, `TIMEOUT` or `FAILED`.

`reference/parallel-waves.md` runs a waves plan: opening a wave, the parallel
implementer dispatch, the merge and the integration check, and recovery.
`scripts/wave` holds its mechanics: `list` the waves, the `ref` a parallel
task commits to, `status` of a wave's tasks, `merge` one reviewed task, and
`clean` a merged wave's worktrees and refs without ever forcing.

`reference/project-state.md` describes the committed project-declared state —
`gates.md`, `plans/completed.md` and `distilled/` — and the precedence order that
settles a disagreement between them.

`criteria/` holds the verifier criteria, including `plan-review.md` for plan
review, `codex-review-schema.json` for the Codex task seats, and
`codex-plan-review-schema.json` for the Codex plan-review round;
`criteria/TEMPLATE.md` documents the format.
`tests/criteria.test.sh` validates every file in that directory.

`scripts/` holds the external executor lane:

- `detect-executors.sh` emits the JSON roster read at plan time and again as a
  dispatch guard. `usable` means dispatchable, so a batch-capable CLI this
  plugin ships no wrapper for reports `usable: false` with the reason.
- `run-codex-task.sh` runs one plan task on Codex, owns the commit, and prints
  one status line. Exit 0 is `DONE`, 1 is a run that did not reach it, and 2 is
  no status line - either a refusal before launch or a git failure after the run,
  which the dispatching skill tells the controller apart and recovers from
  differently. The status line also carries Codex's own `exit=` code and a
  `note=timed-out` marker, and the report lifts Codex's error text out of the
  `--json` stream into a `## Codex error` section. All three exist because
  `status` is forced to `BLOCKED` on any non-zero exit, so on its own it cannot
  separate a parse failure, a timeout, and a model that gave up - and the error
  text is on stdout, where a controller reading `<report>.stderr` never finds it.
- `codex-report-schema.json` is the `--output-schema` the wrapper passes, and
  the shape of the verdict it parses back.
- `codex-task-contract.md` is appended to every prompt the wrapper sends,
  resume rounds included.

### Item registers

A register is the list of source items a body of work must answer, and the
authority on whether that work is finished. One file per incoming list —
an owner's list, a review's findings, a batch — at
`docs/forge/registers/YYYY-MM-DD-<slug>.md`, committed, and required whenever a request carries two or more
distinct items.

Each row carries an identifier, the requester's words, an assignment, an
acceptance, a state and a note. The states are
open, planned, doing, verify, done, deferred, n/a
— the first four unresolved, with `verify` meaning built and the owner's
confirmation still owed. A note is mandatory for verify, deferred and n/a,
because those three record a decision rather than progress.

`scripts/register` reads and writes them: `check` validates a file, `open`
reports the unresolved rows for a file or a spec and exits 1 while any remain,
and `set` and `add` are the only writers. Readers resolve a register from a
plan's `**Spec:**` and `**Program:**` spec paths rather than from a pointer in
the plan, so the link cannot go stale.

No surface may claim a body of work complete while a row is unresolved:
`next-step` reports the open rows instead of "every sub-project is done",
`plan-lint` rejects a `last` Program line that a register contradicts,
`repo-audit` counts the open rows, and `project-status` lists them. When no register covers a spec, every
surface behaves exactly as it did before.

### Greenfield roadmap

A project built from scratch spans many specs and many sessions, and what goes
missing there is whole epics: decided once in prose, then forgotten when a later
session calls the phase done. `planning-a-product` runs discovery first and
writes `docs/forge/roadmap.md`, the milestones in order (by default M0
Discovery, M1 Foundations, the feature milestones, Hardening, Release), each
with exit criteria and one item register whose rows are its epics. Each epic's
spec then gets its own register of requirements, which `plan-lint` already ties
to plan tasks through `**Items:**`.

`scripts/roadmap` computes a milestone's progress from those registers rather
than storing it: `status` reports it, `open` lists every unresolved row below a
milestone, including the requirements under an epic someone marked done too
early, and `settle` moves an integrated epic to `verify`, never to `done`.
`close` is the only writer of `closed`; it refuses while anything below the
milestone is unresolved or an earlier milestone is open, and
`closing-a-milestone` runs it only after a fresh `judge-opus` has ruled every
row `MET` on evidence and your human partner has signed off.

`next-step` takes the next epic from the current milestone instead of a copied
Program line, `repo-audit` and `project-status` show the milestones, and the
SessionStart hook injects one line, such as
`Roadmap: M2 Beta, 3 of 5 epics resolved, open: #4 Billing, #5 Search`, so a
fresh or compacted session starts knowing where the project stands. Without a
roadmap every surface behaves exactly as before.
