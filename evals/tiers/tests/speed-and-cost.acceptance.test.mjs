// Acceptance tests for the speed-and-cost spec
// (docs/dforge/specs/2026-10-27-speed-and-cost-design.md): A2's "no rule is
// lost by the split", and A12 and A13 for the eval pipeline. Each test is
// written from the statement's text and reaches the behaviour through the
// public surface: `run-grid.mjs --stage pipeline`, the files it writes, the
// commands it launches, and the skill files the split produced. The `claude`
// CLI is a recording wrapper around the harness's stub, so nothing is spent.
// A14 is a decision rule with no code behind it; it is recorded as
// cannot-test: no-surface in the acceptance report.
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { after, test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { PLAN, fixture, modes } from './fixture.mjs';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));
const GRID = fileURLToPath(new URL('../run-grid.mjs', import.meta.url));
const BASE = process.env.SPEED_AND_COST_BASE ?? 'e6f88a653e365585ad446e3bbe505e4dc4155819';

const git = (cwd, ...args) => execFileSync('git', ['-c', 'user.name=acceptance', '-c', 'user.email=acceptance@example.invalid', ...args], { cwd, encoding: 'utf8' });
const baseKnown = () => spawnSync('git', ['cat-file', '-e', `${BASE}^{commit}`], { cwd: REPO }).status === 0;

// ---------------------------------------------------------------- A2
// Every sentence of a split skill's SKILL.md before the split is still in the
// skill or its references after it (link targets aside: a moved sentence's
// relative links change with its directory). Some sentences were reworded on
// purpose: the first to point at the reference that now holds the table it
// names, the rest when the follow-ups pointed the Recovery and
// execution-strategy pointers at the files that hold them and dropped
// ./references/ from the process graph's labels, and the last four when the
// plan-review report file was renamed to end -report.md, the only name the
// judge write guard lets a judge write.
const norm = s => s.replace(/\]\([^)]*\)/g, ']').replace(/\r/g, '').replace(/\s+/g, ' ').trim();
const REWORDED = [
  'escalated inline -> subagent` ledger line, and the Recovery table below says what to do with it.',
  "For each task the last ledger line decides; see the Recovery table under The Ledger.",
  "If its first line names your plan file, recover each task's state with the Recovery table under The Ledger.",
  "`complete` is done; `fix round 1/2` resumes at round 2 with a fresh dispatch, and `fix round 2/2` goes to the breaker (an older run's `R/5` maps as §The Ledger's Recovery says); an assigned line with commits after its base goes to review; `awaiting group review` is reviewed by the next group dispatch, never re-dispatched.",
  "subgraph cluster_per_task { label=\"Per Task\"; \"Dispatch the assigned implementer or executor (./references/implementer-prompt.md)\" [shape=box]; \"Implementer reports NEEDS_CONTEXT?\" [shape=diamond]; \"Mechanical:",
  "review=group?\" [shape=diamond]; \"task-step hold; review the group at 4 held, before a review=task dispatch, and after the last task (./references/group-reviewer-prompt.md)\" [shape=box]; \"Generate review package, dispatch judge (./references/task-reviewer-prompt.md)\" [shape=box]; \"Verdicts clean and no score 1-8?\" [shape=diamond]; \"Finding conflicts with plan text?\" [shape=diamond]; \"Ruling seat rules on the conflict (./references/ruling-prompt.md)\" [shape=box]; \"Fix round R of 2:",
  "R=1 resume or fresh by cache state; R=2 successor rung, fresh\" [shape=box]; \"Dispatch scoped re-review (./references/re-review-prompt.md)\" [shape=box]; \"All findings addressed?\" [shape=diamond]; \"R = 2?\" [shape=diamond]; \"Ruling seat adjudicates each open finding\" [shape=box]; \"Any CONFIRMED-GAP or AMEND?\" [shape=diamond]; \"Carry the fix or amendment forward; BLOCKED stops\" [shape=box]; \"Park findings in ledger with rulings\" [shape=box]; \"Append completion to ledger, mark todo complete\" [shape=box]; }",
  "worktree, finish preference, ledger check, plan header, pre-flight ruling\" -> \"Dispatch the assigned implementer or executor (./references/implementer-prompt.md)\"; \"Dispatch the assigned implementer or executor (./references/implementer-prompt.md)\" -> \"Implementer reports NEEDS_CONTEXT?\"; \"Implementer reports NEEDS_CONTEXT?\" -> \"Mechanical:",
  "review=group?\" -> \"Generate review package, dispatch judge (./references/task-reviewer-prompt.md)\" [label=\"no\"]; \"review-route:",
  "review=group?\" -> \"task-step hold; review the group at 4 held, before a review=task dispatch, and after the last task (./references/group-reviewer-prompt.md)\" [label=\"yes\"]; \"task-step hold; review the group at 4 held, before a review=task dispatch, and after the last task (./references/group-reviewer-prompt.md)\" -> \"Verdicts clean and no score 1-8?\"; \"Generate review package, dispatch judge (./references/task-reviewer-prompt.md)\" -> \"Verdicts clean and no score 1-8?\"; \"Verdicts clean and no score 1-8?\" -> \"Append completion to ledger, mark todo complete\" [label=\"yes\"]; \"Verdicts clean and no score 1-8?\" -> \"Finding conflicts with plan text?\" [label=\"no\"]; \"Finding conflicts with plan text?\" -> \"Ruling seat rules on the conflict (./references/ruling-prompt.md)\" [label=\"yes\"]; \"Ruling seat rules on the conflict (./references/ruling-prompt.md)\" -> \"Fix round R of 2:",
  "R=1 resume or fresh by cache state; R=2 successor rung, fresh\" -> \"Dispatch scoped re-review (./references/re-review-prompt.md)\"; \"Dispatch scoped re-review (./references/re-review-prompt.md)\" -> \"All findings addressed?\"; \"All findings addressed?\" -> \"Append completion to ledger, mark todo complete\" [label=\"yes\"]; \"All findings addressed?\" -> \"R = 2?\" [label=\"no\"]; \"R = 2?\" -> \"Fix round R of 2:",
  "R=1 resume or fresh by cache state; R=2 successor rung, fresh\" [label=\"no - next round\"]; \"R = 2?\" -> \"Ruling seat adjudicates each open finding\" [label=\"yes - breaker trips\"]; \"Ruling seat adjudicates each open finding\" -> \"Any CONFIRMED-GAP or AMEND?\"; \"Any CONFIRMED-GAP or AMEND?\" -> \"Carry the fix or amendment forward; BLOCKED stops\" [label=\"yes\"]; \"Carry the fix or amendment forward; BLOCKED stops\" -> \"Append completion to ledger, mark todo complete\" [label=\"gap carried\"]; \"Any CONFIRMED-GAP or AMEND?\" -> \"Park findings in ledger with rulings\" [label=\"no\"]; \"Park findings in ledger with rulings\" -> \"Append completion to ledger, mark todo complete\"; \"Append completion to ledger, mark todo complete\" -> \"More tasks remain?\"; \"More tasks remain?\" -> \"Dispatch the assigned implementer or executor (./references/implementer-prompt.md)\" [label=\"yes\"]; \"More tasks remain?\" -> \"Final review:",
  "When the spec has none — it predates the question, or there is no spec — ask your human partner the question in dforge:brainstorming §Choosing the execution strategy before you draft any task, and wait for the answer; when the `executionStrategy` setting is `sequential` or `parallel` (dforge:brainstorming §Settings; the default is `parallel`), take that value and do not ask.",
  "the full-plan template in round 1, the Later rounds template after it, each with `[REPORT_FILE]` set to `<workspace>/plan-review-round-<r>.md`.",
  "dispatch the printed `fallback` (`dforge:judge-opus`) with the full-plan template and `[REPORT_FILE]` set to `<workspace>/plan-review-round-1.md`, and say why.",
  "Dispatch it with the full-plan template and `[REPORT_FILE]` set to `<workspace>/plan-review-round-1.md`, and say `codex off — <reason>`, quoting the gate line's `reason` (`untrusted` when it printed `usable=true`).",
  "Write `diff -u <workspace>/plan-round-<r-1>.md PLAN_FILE > <workspace>/plan-delta-<r>.diff`, dispatch the seat with the Later rounds template, passing that file and the previous round's findings file, with `[REPORT_FILE]` set to `<workspace>/plan-review-round-<r>.md`.",
];
// Sentences later changes on the main branch removed or reworded after BASE:
// "review light plans once" in writing-plans, the strict-mode tail in the
// execution skills, the drafting threshold in writing-plans, the plan
// header's waves-only Integration check placeholder, which the test tiers
// change widened to every plan, the inline full-suite-before-commit rule,
// which it replaced with the task check, the merged-result verification's
// gates-or-suite choice, which it replaced with gates then the full suite as
// `bash -c`, the spec review's bullet run, which the CI parity change
// split with the early-CI question, and the auto run's one-exception
// sentence, the ledger grammar block's end and the two Plan state openings,
// which early CI extended, and the assignment procedure's one-executor gate
// and precedence sentences, which the executor routing rule (Task 8)
// replaced, and the plan drafter's slice bullets, which inline-only execution
// removed when every plan came to be drafted in the session, and the
// execution skill's heavy-task delegation and switch to subagent mode, which
// inline-only execution replaced with the session review loop and the
// breaker, and writing-plans' majority rule and subagent Execution line,
// which it replaced with an inline line on every plan, and brainstorming's
// mode slot and execution-strategy question and subagent mode's description,
// which it removed when it deprecated subagent mode. The split cannot have
// lost them.
const REMOVED = [
  '- **Contracts settle what slices share.** A drafter that reports `NEEDS_CONTEXT` needs a contract:',
  'add it to the header and re-dispatch that slice.',
  'An amendment that changes an existing Contract, rather than adding one, re-dispatches every slice:',
  'a slice drafted against the old Contract is stale, and nothing downstream can tell.',
  '- **Join without reading.** Once every slice reports `DONE`, run `scripts/draft-pack --join PLAN_FILE`.',
  'It appends the slices in task order and deletes them; on exit 3 it names the gap or overlap and leaves the plan unchanged.',
  'Then continue at Assign an implementer.',
  '- **On a Codex host, draft every task in the session.**',
  '`inline`, `advisor`, or `best-of-3`, a dash, and a one-line reason; an `inline` reason cites a skip condition by number - `**Lenses:**` — only on a task scored risk 3, and optional there:',
  '- **Once the plan is reviewed** (at depth light, once it is linted):',
  'Before each round `<r>`, copy the plan to `<workspace>/plan-round-<r>.md`.',
  "At depth light (step 1's line) skip `scripts/codex-gate`:",
  'no seat runs, so run only `scripts/review-route PLAN_FILE --plan-round 1`.',
  'Otherwise run `scripts/codex-gate` (say its line aloud when it ends `source=probe`), then `scripts/review-route PLAN_FILE --plan-round <r>`, and review with the seat it prints, using [plan-reviewer-prompt.md].',
  '- **`primary=none`** (`reason=depth-light`, round 1 of a light plan).',
  'dispatch no seat, skip step 3, and record the skip in step 4.',
  '1 at standard, so round 1 is the only round, and 0 at light, so none runs.',
  'At depth light no review ran:',
  'write `**Plan review:** <YYYY-MM-DD> — skipped (depth light)` in the same place, and `plan-lint` accepts it.',
  "The plan's last two tasks are measured against the final-phase limit:",
  "- The plan's last two tasks are measured against the final-phase limit:",
  "their brief prints `budget (last 2 tasks)` or `budget (last task)`, and only that line's verdict decides.",
  'A plan of 1-3 tasks is drafted in the session.',
  'For 4 or more, write the header yourself, through the Task index, and save it as the plan file.',
  'Then split the index into slices of 2-3 consecutive tasks and dispatch one `dforge:drafter-sonnet` per slice, every slice in one message, with [drafter-prompt.md].',
  "Each dispatch names the spec path, the plan path, the slice range, the slice path (`<state>/drafts/<plan basename without .md>/tasks-A-B.md`) and the plugin root, as the template's placeholders; paste nothing else.",
  '**Integration check:** [waves only:',
  'the command that proves a merged wave works, normally the full suite]',
  'Run the focused test while you work and the full suite once before committing.',
  'gates when the project declares a manifest # (dforge:running-gates, with the sha printed above as its base), otherwise # the full test suite through suite-run.',
  'Gates that passed on the branch say # nothing about the merged tree, and the merged HEAD is new, so suite-run runs.',
  'bash <plugin-root>/scripts/suite-run -- <test command> ```',
  '<question>"`; with no register open, first open `<docs>/registers/<date>-<spec-slug>.md` as Opening an item register says; - every item Fable left undecided, and every critic Blocker it did not settle, with the recommended option first; - when `finishAction` is `ask`:',
  'An irreversible, security-sensitive or outside-the-worktree action is never performed (the finish action is the one exception).',
  'clean (commits <merge-base7>..<head7>[, K parked]) ```',
  '**Plan state.** First, whatever the per-task lines say:',
  '**Plan state.** Every task complete and no `Final review:` line:',
  '`**Integration check:**` names the command that proves a merged wave works together — normally the whole suite.',
  'Every id `scripts/executors list` prints has its own gate; run each, resolved with `bash "$(bash scripts/executors path <id> gate)"`, before the roster, and make the offer once per plan for every executor whose gate prints `lane=true`.',
  "**A task carries at most one `**Executor:**` line, and you choose it.** When two ticked executors' gates both admit a task, nothing mechanical picks between them:",
  'write one line, and `plan-lint` validates only what is written.',
  'No precedence rule is introduced here — with one registered executor there is no choice to make, and a rule invented now would be untested against a real second executor.',
  "Everything else here is host-neutral - inline mode dispatches nothing but the ruling seat, delegated tasks and the final review.",
  "**Why this mode.** The plan's `**Execution:**` line chose it because at most half the tasks are heavy (total 5 or more, or risk 3).",
  "The rest are small changes whose text carries the code, and a subagent per task would cost more in context rebuild than the task itself.",
  "The line's model is Sonnet, and its effort follows the highest score among the tasks you implement, at least high when the plan delegates.",
  "**Delegated tasks.** A delegated task is not yours to implement:",
  "every heavy task, and every task carrying an `**Executor:**` line.",
  "An offloaded task is delegated for the same reason the others are — the session does not implement it — and it runs on its executor's wrapper rather than an implementer subagent.",
  "Its brief's second line is `**Dispatch:** delegated — total <t>, risk <r>`, and `plan-header.md` ends with `**Dispatch:** delegated — Task <a> (heavy), Task <b> (executor)`.",
  "an implementer subagent, the review seat `scripts/review-route` prints, fix rounds up to 2 and a reviewed complete line.",
  "**Why no per-task review of your own tasks.** The eligibility bar is the gate, applied when the plan was written.",
  "A task too large or too risky to implement here is delegated and reviewed; what catches the rest is the plan's own verification steps, your self-review of each diff, and one broad review of the whole branch at the end.",
  "**Every session ends with the next step.** Whenever this session ends before the plan is finished - one of those four stops, a context-budget handoff, a switch to subagent mode, or your human partner asking you to stop - first reconcile live children exactly as dforge:handoff step 0 says:",
  "inline by invocation — plan predates the Execution line — if wrong, the run escalates at the first task that will not converge` and continue.",
  "A task whose brief's second line marks it delegated is dispatched, never implemented here, and its `**Executor:**` line is read by [delegated-task.md] §1, which runs that executor's wrapper in place of an implementer subagent.",
  "`**Implementer:**` lines are inert for the tasks you implement.",
  "**Preflight.** When `plan-header.md` ends with a `**Dispatch:** delegated` line naming at least one `(heavy)` task, send one `preflight` item to the ruling seat before Task 1 and carry out its verdicts.",
  "You are fixing your own work, so a fourth round is not a better round - it is the trigger in Switching to subagent mode.",
  "- The escalated line is the switch itself.",
  "Every trigger in Switching to subagent mode writes it, whether or not a fix round preceded it, and it is the only line `scripts/next-step` and subagent mode's recovery read as a switch.",
  "use dforge:subagent-driven-development | | `fix round R/3 (…; passing)` | Re-run the task's verifications; if they pass, commit anything uncommitted and write the complete line, else treat as `still failing` | | `fix round R/3 (…; still failing)`, R < 3 | Resume the loop at round R+1 | | `fix round 3/3 (…; still failing)` | Go to Switching to subagent mode | | `implementer inline (assigned; base <sha7>)` | If `git log <base>..HEAD` is non-empty, re-run the task's verifications and finish it from where those commits leave it; otherwise start the task | | An agent-named `implementer <agent> (assigned …)` line, or `fix round R/2` (a Codex plan's `fix round R/5`) | A delegated task:",
  "A switch to subagent mode is always a handoff.",
  "A task still failing after `3/3` goes to Switching to subagent mode - not to a fourth round, and not to a complete line.",
  "It and delegated tasks are all this mode dispatches before the final review.",
  "| Kind | Decision point | |---|---| | `preflight` | Once, before Task 1, when the plan has a heavy task (Setup) | | `blocked-plan` | The plan is wrong and no path forward is a mechanical choice | | `plan-conflict` | A final-review finding, or a delegated task's review finding, that conflicts with what the plan's text requires, or is labelled plan-mandated | | `cannot-verify` | A delegated task's `cannot-verify:` digest line | | `breaker` | A delegated task's findings still open after round 2/2 | | `executor-empty-diff` | An external executor's fix round that returned DONE with an empty diff and an argument | | `final-residual` | Findings still open after the final review's one fix wave |",
  "A CONFIRMED-GAP whose fix you attempt and fail is a trigger in Switching to subagent mode.",
  "## Switching to subagent mode",
  "Inline mode has one exit, and it runs in one direction.",
  "- your human partner says to; - a task is still failing its own verifications after `fix round 3/3`; - a ruling-seat CONFIRMED-GAP names a fix you have attempted and failed.",
  "The trigger is mechanical, so the switch is your ruling, not a seat verdict:",
  "the seat's four verdicts say nothing about execution mode.",
  "It happens only at a task boundary where every earlier task is complete.",
  "escalated inline -> subagent — <trigger>`, where `<N>` is the task that will run first under subagent mode - the failing task, or, on your human partner's instruction, the next task not yet started.",
  "every trigger writes it, with or without a preceding fix-round line.",
  "Log, and say aloud, `Ruling:",
  "switch to subagent mode at Task <N> — <trigger> — if wrong, the remaining tasks each cost one dispatch that inline would not have spent`.",
  "`**Execution:**` is one of the lines `scripts/plan-amend` refuses to touch, and the ledger is where the switch is recorded.",
  "The switch is always a handoff:",
  "subagent mode's value is a fresh controller that reads the header and one brief at a time, and this session's context is full of implementation detail it does not need.",
  "In an auto run, run dforge:handoff steps 0-4, then `scripts/auto-run clear --phase`, and end the turn with `Auto run:",
  "clearing` as its last line; a `next-step` exit 4 or 5 there is handled as auto-run.md §Clears says; a phase clear never counts as a self-resume.",
  "Your human partner may also move a plan the other way, from subagent mode to this one.",
  "Only their explicit instruction does that, and only at the same kind of boundary.",
  "The return takes effect at the first remaining task that is not delegated:",
  "only its `implementer inline (assigned` line records the return, so delegated tasks before it still run under subagent mode.",
  "| | \"This task is harder than it scored - I'll just take more rounds\" | Three rounds, then the switch.",
  "| | \"The owner said switch, but there is no fix round to mark\" | The escalated line is its own ledger line.",
  'escalated inline -> subagent — <trigger> Task <N>:',
  "Write it; nothing else records the switch.",
  "- **The execution strategy:** take the spec's `**Execution strategy:**` line; with none, take the `executionStrategy` setting (`parallel` by default) as Parallel waves says, and write `sequential` when it is `ask`.",
  "**Execution:** [inline|subagent] — `claude --model <model> --effort <effort>` — [why]",
  "`**Execution:** <inline|subagent> — codex <model> / <effort> — <why>`.",
  "That pair runs the main session for the whole plan.",
  "A subagent plan names `codex gpt-6.1-sol / high`; an inline plan names the execution tier at its highest weighted routing score.",
  "**Choosing the Execution line.** The plan decides its execution mode:",
  "An inline plan delegates its heavy tasks and every task carrying an `**Executor:**` line:",
  "each runs through [delegated-task.md] with an implementer subagent — or, for an Executor line, that executor's wrapper — and the full per-task review.",
  "The tasks not delegated are the **self-implemented** tasks.",
  "- `subagent` when more than half the tasks are heavy, and always when the plan runs parallel waves (see Parallel waves):",
  "The controller owns no judgment calls — the ruling seat does — so it needs no stronger model.",
  "- Otherwise `inline`, the default, on `sonnet`:",
  "every self-implemented task (total 4 or less, risk below 3) is assigned to Sonnet, and heavy tasks are delegated.",
  "`<e>` is the assignment-table effort of the highest self-implemented total (`impl-haiku` counts as `low`), raised to `high` when any task is delegated:",
  "`claude --model sonnet --effort <e>`.",
  "When every task is heavy and your human partner overrides the line to inline, use `claude --model opus --effort high`.",
  "- Your human partner may override the line; `plan-lint` checks its grammar, warns when it disputes the majority rule, and lists the delegated tasks with their reasons.",
  "- The `executionMode` setting fixes the line when it is `inline` or `subagent`, in place of the majority rule.",
  "`inline` also makes the plan sequential, whatever the spec's `**Execution strategy:**` line or the `executionStrategy` setting says, because an inline session implements its own tasks one after another:",
  "write `**Parallelism:** sequential — executionMode is inline` and group no waves.",
  "An inline plan still delegates its heavy tasks and every task carrying an `**Executor:**` line.",
  "**Ask first.** Read the spec's `**Execution strategy:**` line.",
  "**The Execution line names `subagent`**, `claude --model sonnet --effort high`, whatever the heavy-task count:",
  "inline mode implements the tasks it does not delegate in the session itself, one after another, so it has nothing to run in parallel.",
  "`plan-lint` skips the majority-rule warning for a waves plan.",
  "Under dforge:executing-plans the lines are read for the delegated tasks, which include every task carrying an `**Executor:**` line.",
  "<spike|bounded|architectural>, <inline|subagent> — <trigger | no trigger>` — so your human partner can override it.",
  "The mode slot is your expectation only; the plan's Execution line decides.",
  "architectural, <inline|subagent>, depth <d> — <triggers>`.",
  "- `executionStrategy=sequential` or `executionStrategy=parallel`:",
  "do not ask the execution-strategy question; record the value as the answer.",
  "`parallel` still becomes sequential when you cannot name two parts that share no file, on a Codex host, and when `executionMode=inline`, which makes the plan sequential.",
  "**Architectural:** (under `autoRun=on`, the default on Claude Code, steps 6-8 and 12-13 run as Auto by default says) 1.",
  "**Ask the execution strategy** — parallel subagent waves or sequential execution, one question (see Choosing the execution strategy) 6.",
  "**Present design** — in sections scaled to their complexity, get user approval after each section 7.",
  "**Draft acceptance** — numbered, tagged, rated statements; ask your human partner about every one rated below `high` (see Drafting acceptance) 8.",
  "one question once the acceptance statements are settled (see After the Design) 9.",
  "**Write design doc** — save to `<docs>/specs/YYYY-MM-DD-<topic>-design.md` with its `**Depth:**` line, and commit 10.",
  "**Spec self-review** — one round for placeholders, contradictions, ambiguity, scope, acceptance and the riskiest assumption; post its block before the user review (see below) 11.",
  "depth light skips it, and depth standard folds it into Fable's first round when Fable reviews) 12.",
  "**User reviews written spec** — ask user to review the spec file before proceeding; under `autoRun=on` this is Auto by default's spec review message, after Fable's review at depth standard or full (an auto run started from the offer has Fable review it instead, at those depths) 13.",
  "spike / bounded / architectural\" [shape=diamond]; \"Present question + probe (2-3 sentences)\" [shape=box]; \"Ask clarifying questions (bounded)\" [shape=box]; \"Present short design in chat\\n+ self-review block\" [shape=box]; \"Human approves?\" [shape=diamond]; \"Investigate; report recommendation\" [shape=doublecircle]; \"Implement via normal workflow (no plan doc)\" [shape=doublecircle]; \"Explore project context\" [shape=box]; \"Ask clarifying questions\" [shape=box]; \"Propose 2-3 approaches\" [shape=box]; \"Ask execution strategy\\n(parallel or sequential)\" [shape=box]; \"Present design sections\" [shape=box]; \"User approves design?\" [shape=diamond]; \"Draft acceptance\\n(rate; ask below high)\" [shape=box]; \"Offer an auto run\\n(once, unless autoRun=off)\" [shape=box]; \"Write design doc\" [shape=box]; \"Spec self-review\\n(one round, shown)\" [shape=box]; \"Architecture critic\\n(one judge-opus round)\" [shape=box]; \"User reviews spec?\" [shape=diamond]; \"Invoke writing-plans skill\" [shape=doublecircle]; \"Hidden complexity?",
  "spike / bounded / architectural\"; \"Explore project context\" -> \"Ask clarifying questions\"; \"Ask clarifying questions\" -> \"Propose 2-3 approaches\"; \"Propose 2-3 approaches\" -> \"Ask execution strategy\\n(parallel or sequential)\"; \"Ask execution strategy\\n(parallel or sequential)\" -> \"Present design sections\"; \"Present design sections\" -> \"User approves design?\"; \"User approves design?\" -> \"Present design sections\" [label=\"no, revise\"]; \"User approves design?\" -> \"Draft acceptance\\n(rate; ask below high)\" [label=\"yes\"]; \"Draft acceptance\\n(rate; ask below high)\" -> \"Offer an auto run\\n(once, unless autoRun=off)\"; \"Offer an auto run\\n(once, unless autoRun=off)\" -> \"Write design doc\"; \"Write design doc\" -> \"Spec self-review\\n(one round, shown)\"; \"Spec self-review\\n(one round, shown)\" -> \"Architecture critic\\n(one judge-opus round)\"; \"Architecture critic\\n(one judge-opus round)\" -> \"User reviews spec?\"; \"User reviews spec?\" -> \"Write design doc\" [label=\"changes requested\"]; \"User reviews spec?\" -> \"Invoke writing-plans skill\" [label=\"approved\"]; \"Ask execution strategy\\n(parallel or sequential)\" -> \"Write spec directly\\n(autoRun=on, with ## Decisions)\" [label=\"autoRun=on\"]; \"Write spec directly\\n(autoRun=on, with ## Decisions)\" -> \"Draft acceptance in the spec\\n(ask nothing yet)\"; \"Draft acceptance in the spec\\n(ask nothing yet)\" -> \"Spec self-review\\n(one round, shown)\"; \"Architecture critic\\n(one judge-opus round)\" -> \"Fable spec review\\n(at most two rounds)\" [label=\"autoRun=on\"]; \"Spec self-review\\n(one round, shown)\" -> \"Fable spec review\\n(at most two rounds)\" [label=\"Fable reviews;\\ndepth standard\"]; \"Spec self-review\\n(one round, shown)\" -> \"Spec review\\n(the one stop)\" [label=\"depth light\\n(autoRun=on)\"]; \"Spec self-review\\n(one round, shown)\" -> \"User reviews spec?\" [label=\"depth light\\n(attended)\"]; \"Fable spec review\\n(at most two rounds)\" -> \"Spec review\\n(the one stop)\"; \"Spec review\\n(the one stop)\" -> \"Revise spec\\n+ one new self-review round\" [label=\"changes needed\"]; \"Revise spec\\n+ one new self-review round\" -> \"Spec review\\n(the one stop)\"; \"Spec review\\n(the one stop)\" -> \"Invoke writing-plans skill\" [label=\"either approval\"]; } ```",
  "When `executionStrategy` is `sequential` or `parallel` (see Settings), skip the question and record that value.",
  "Otherwise, once the approach is settled and before you present the design, ask your human partner one multiple-choice question, on its own:",
  "> How should the plan execute?",
  "**Sequential** (default) — one task at a time; the safest choice, and the > right one when the work is one chain of dependent changes.",
  "**Parallel subagents** — independent tasks run at the same time, each in > its own worktree, merged and checked together after each wave; faster > when the work splits into parts that share no files.",
  "parallel only when you can already name two or more parts that share no file and do not consume each other's output; sequential otherwise.",
  "Parallel runs only in subagent mode on Claude Code.",
  "On a Codex host do not ask:",
  "the plan is sequential, and you say so in one line.",
  "Record the answer near the top of the spec, below its title, as `**Execution strategy:** parallel — <reason>` or `**Execution strategy:** sequential — <reason>`.",
  "When the answer is parallel, the design leans toward independence, because a part that shares nothing is a part that cannot break its sibling:",
  "- **Settle shared things first.** Types, interfaces, schemas, configuration keys and file layout that several parts use belong to one foundation part that runs before the others.",
  "- **Give every file one owner.** Registries, barrels and index files, route tables, dependency manifests and lockfiles, migrations and version files are where parallel work collides; assign each to exactly one part, or to the foundation part.",
  "- **Keep risk alone.** Security, data-loss, migration and concurrency work runs on its own, never beside a sibling.",
  "- **Isolate the tests.** Say how parts' tests avoid each other at run time — ports, databases, fixed paths, global state — or that they share nothing.",
  "- Add a `## Parallel decomposition` section to the spec:",
  "the parts, the files each owns, what each consumes from the foundation, and which parts may run together.",
  "writing-plans turns it into waves.",
  "Never bend a design out of shape to make it parallel:",
  "a part that genuinely needs another's output waits for it.",
  "Steps 1-5 of the checklist run as written; the execution-strategy question is asked only when the setting is `ask`.",
  "Use when executing implementation plans with independent tasks in the current session ---",
  // Reworded when auto runs began following the worktree setting: the
  // execution workspace, the run's own branch and its carried paths.
  "- **After any compaction**, whether or not a prompt asks for it (the cockpit's prompt does; a compaction Claude Code starts on its own comes with none), run `scripts/auto-run after-compact` before step 0 above.",
  "- **Setup:** skip the finish-preference question; run `scripts/auto-run phase execute` from the execution worktree, once dforge:using-git-worktrees has created it.",
  "Exit 4 means the worktree step was skipped:",
  "create the worktree, then run the command again from it.",
  "complete (deferred by the auto run) — done:",
  "<the item>[; partial commits <a7>..<b7>, kept for the final review]; discovered:",
  "<why> — <cost if wrong>` and a deferred register row for each.",
  "When that line leaves every task with its `complete` line (in subagent mode, after the last wave's merge), run `scripts/auto-run phase final` next, before any budget check and before the turn ends, so a compaction from there on never hands off.",
  "A `task-complete` exit 5 means the run stopped (a task was completed in the primary checkout):",
  "- **Final review:** run `scripts/auto-run phase final` and, when the pending list is not empty, the Fable batch first; the review's findings take the same ladder.",
  "an irreversible or destructive operation; a security-sensitive action; a side effect outside this worktree that norms say you ask about first (a merge, a push to a shared branch, a publish); and a ruling-seat `BLOCKED` verdict.",
  "an irreversible or destructive operation; a security-sensitive action; a side effect outside this worktree that norms say you ask about first (a merge, a push to a shared branch, a publish); and a ruling-seat `BLOCKED` verdict — a plan so broken that every path forward is a guess.",
  "When `scripts/auto-run status` exits 0 ([auto-run.md]), run `scripts/auto-run phase finish`, then follow this skill with these changes:",
  "- **Where an unattended finish stops** (failing tests at Step 1, a merged result failing its tests, a rejected push, a refused worktree removal), run `scripts/auto-run stop --reason \"<what stopped it>\"` first, then stop as Step 1 or Step 5's \"Whose choice it is\" says.",
  "<merge|pr|keep>` line in `## Decisions`; - **Approve and run unattended**, **Approve, keep the normal stops**, or **Changes needed**.",
  "**Start the run.** On **Approve and run unattended**, commit the spec and the register, run `scripts/auto-run start --spec <spec>` (add `--register <path>` when a register is open, and always the register step 5's deferrals went to), then import each `## Review rulings` line with `scripts/auto-run ruling add \"Fable, spec:",
  "On yes, run `scripts/auto-run start --spec <the spec's path>` (add `--register <path>` when an item register is open) from this checkout, before writing the spec, and follow [auto-run.md] from here to the finished branch.",
  // Finishing's own entry grew past the 20,000-byte limit; auto-run.md
  // §Finishing keeps this statement, pinned by its own check.
  "The line's `fail` and `flaky` counts are not read:",
  "they are taken before the fix wave, a failure that survives it is a deferred `A<n>:` row or a red test at Step 1, and one the fix wave fixed does not keep the branch.",
  // Reworded when the switch began clearing the session instead of compacting it.
  "execution starts in a fresh session (in an auto run the session switches in place instead; see Auto run).",
];
const SPLIT = ['brainstorming', 'executing-plans', 'finishing-a-development-branch', 'subagent-driven-development', 'writing-plans', 'writing-skills'];

for (const skill of SPLIT) {
  test(`A2: no sentence of ${skill}/SKILL.md is lost by the split`, { skip: baseKnown() ? false : `base ${BASE} is not in this repository` }, () => {
    const dir = join(REPO, 'plugins/dforge/skills', skill);
    const old = git(REPO, 'show', `${BASE}:plugins/dforge/skills/${skill}/SKILL.md`);
    let now = readFileSync(join(dir, 'SKILL.md'), 'utf8');
    if (existsSync(join(dir, 'references'))) {
      for (const f of readdirSync(join(dir, 'references'), { recursive: true }).filter(f => f.endsWith('.md'))) now += '\n' + readFileSync(join(dir, 'references', f), 'utf8');
    }
    const hay = norm(now);
    const sentences = norm(old.replace(/\n\n/g, ' ¶ ')).split(/(?<=[.!?:]) |¶/).map(s => s.trim()).filter(s => s.length > 25);
    assert.ok(sentences.length > 100, `only ${sentences.length} sentences were read from the base skill`);
    const lost = sentences.filter(s => !hay.includes(s) && !REWORDED.includes(s) && !REMOVED.includes(s));
    assert.deepEqual(lost, []);
  });
}

// ---------------------------------------------------------------- A12, A13
const fx = fixture();
after(() => rmSync(fx.top, { recursive: true, force: true }));

const hostHome = join(fx.top, 'host-home');
const hostConfig = join(fx.top, 'host-config');
const hostProject = join(fx.top, 'host-project');
for (const dir of [hostHome, hostConfig, hostProject, join(hostHome, '.claude')]) mkdirSync(dir, { recursive: true });
writeFileSync(join(hostConfig, '.credentials.json'), '{"login":true}');
writeFileSync(join(hostConfig, 'settings.json'), '{"model":"owner-choice"}');
writeFileSync(join(hostHome, '.claude', 'settings.json'), '{"owner":"settings"}');

const realStub = process.env.TIER_EVAL_CLAUDE;
const rec = join(fx.top, 'recorded');
mkdirSync(rec);
const wrapper = join(fx.top, 'claude-recorder');
writeFileSync(wrapper, `#!/bin/sh\nd="${rec}/$$"\nmkdir -p "$d"\npwd > "$d/cwd"\nprintf '%s\\n' "$@" > "$d/args"\nenv > "$d/env"\nexec "${realStub}" "$@"\n`);
chmodSync(wrapper, 0o755);

const arms = JSON.parse(readFileSync(join(fx.data, 'arms.json'), 'utf8'));
writeFileSync(join(fx.data, 'arms.json'), JSON.stringify({ ...arms, pipeline: { baseline: fx.planned, candidate: fx.greet } }));
writeFileSync(join(fx.data, 'cases/pipeline.tsv'), `case\tplan\ttask\tbase\tfixRounds\np-acceptance-t1\t${PLAN}\t1\t${fx.planned}\t1\n`);

const tree = dir => existsSync(dir) ? readdirSync(dir, { recursive: true }).sort() : [];
const grid = rep => spawnSync(process.execPath, [GRID, '--stage', 'pipeline', '--rep', String(rep)], {
  cwd: fx.repo,
  encoding: 'utf8',
  env: {
    ...process.env,
    TIER_EVAL_JOBS: '1',
    TIER_EVAL_CLAUDE: wrapper,
    HOME: hostHome,
    CLAUDE_CONFIG_DIR: hostConfig,
    CLAUDE_PROJECT_DIR: hostProject,
    DFORGE_BUDGET: '12345',
    DCC_SENTINEL: 'host-dcc',
    CLAUDE_CODE_SESSION_ID: 'host-session',
  },
});
const tsv = file => {
  const [header, ...lines] = readFileSync(file, 'utf8').split('\n').filter(Boolean);
  const keys = header.split('\t');
  return { header, rows: lines.map(line => Object.fromEntries(line.split('\t').map((v, i) => [keys[i], v]))) };
};
const calls = () => readdirSync(rec).sort().map(id => ({
  id,
  cwd: readFileSync(join(rec, id, 'cwd'), 'utf8').trim(),
  args: readFileSync(join(rec, id, 'args'), 'utf8').split('\n').filter(Boolean),
  env: Object.fromEntries(readFileSync(join(rec, id, 'env'), 'utf8').split('\n').filter(l => l.includes('=')).map(l => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)])),
}));
const flag = (call, name) => call.args[call.args.indexOf(name) + 1];

const reposBefore = { status: git(fx.repo, 'status', '--porcelain', '--untracked-files=all'), worktrees: git(fx.repo, 'worktree', 'list'), refs: git(fx.repo, 'for-each-ref') };
const homeBefore = tree(hostHome);
const configBefore = tree(hostConfig);
const projectBefore = tree(hostProject);

modes(fx.stub, 'loop');
const run1 = grid(1);
const first = calls();

test('A12: the pipeline stage replays one case end to end and exits 0', () => {
  assert.equal(run1.status, 0, run1.stderr);
  assert.match(run1.stdout, /run-grid stage=pipeline rep=1 ran=4 remaining=0/);
});

test('A12: results/pipeline.tsv has the pipeline columns and one row per arm and run', () => {
  const file = join(fx.data, 'results/pipeline.tsv');
  assert.ok(existsSync(file));
  const { header, rows } = tsv(file);
  assert.equal(header, 'rep\tcase\tarm\trun\toutcome\tcostUsd\tseconds\tdispatches\tfixRounds\tdetail');
  assert.deepEqual(rows.map(r => [r.case, r.arm.split('@')[0], r.run]), [
    ['p-acceptance-t1', 'baseline', '1'], ['p-acceptance-t1', 'baseline', '2'],
    ['p-acceptance-t1', 'candidate', '1'], ['p-acceptance-t1', 'candidate', '2'],
  ]);
  assert.deepEqual(rows.map(r => r.arm.split('@')[1]), [fx.planned, fx.planned, fx.greet, fx.greet].map(sha => sha.slice(0, 7)));
});

test('A12: each run records pass, costUsd, wall time, dispatch count and fix rounds', () => {
  const { rows } = tsv(join(fx.data, 'results/pipeline.tsv'));
  for (const r of rows) {
    assert.equal(r.outcome, 'PASS');
    assert.equal(r.costUsd, '0.5');
    assert.match(r.seconds, /^\d+$/);
    assert.equal(r.dispatches, '2');
    assert.equal(r.fixRounds, '1');
  }
});

test('A12: a session that never finishes the task is recorded as a failure, not a pass', () => {
  modes(fx.stub, 'loopstop');
  const run2 = grid(2);
  assert.equal(run2.status, 0, run2.stderr);
  const { rows } = tsv(join(fx.data, 'results/pipeline.tsv'));
  const second = rows.filter(r => r.rep === '2');
  assert.equal(second.length, 4);
  for (const r of second) {
    assert.equal(r.outcome, 'FAIL');
    assert.equal(r.fixRounds, '0');
    assert.equal(r.dispatches, '2');
  }
  assert.equal(rows.filter(r => r.rep === '1' && r.outcome === 'PASS').length, 4);
});

test('A12: each arm runs under its own plugin directory, one session per run', () => {
  assert.equal(first.length, 4);
  const dirs = first.map(c => flag(c, '--plugin-dir'));
  const refs = [fx.planned, fx.planned, fx.greet, fx.greet].map(sha => sha.slice(0, 7));
  dirs.forEach((dir, i) => {
    assert.ok(dir.endsWith(`${sep}arms${sep}${refs[i]}${sep}plugins${sep}dforge`) || dir.endsWith(`/arms/${refs[i]}/plugins/dforge`), dir);
    assert.ok(existsSync(join(dir, 'marker.txt')), `${dir} holds the plugin of its ref`);
  });
  assert.notEqual(dirs[0], dirs[2]);
  assert.match(readFileSync(join(rec, first[0].id, 'args'), 'utf8'), /^-p$/m);
});

test('A12: the existing results file is not written by the pipeline stage', () => {
  assert.equal(existsSync(join(fx.data, 'results/results.tsv')), false);
});

// A13: nothing outside the eval's own temporary root.
const root = join(fx.work, 'pipeline');
const inside = path => { const rel = relative(root, path); return rel !== '' && !rel.startsWith('..') && !rel.split(sep).includes('..'); };

test('A13: every run works in a directory under the eval root', () => {
  assert.equal(first.length, 4);
  for (const c of first) assert.ok(inside(c.cwd), `cwd ${c.cwd} is outside ${root}`);
  assert.ok(first.every(c => c.cwd !== fx.repo && c.cwd !== hostProject));
});

test('A13: every run loads its plugin from a directory under the eval root', () => {
  for (const c of first) assert.ok(inside(flag(c, '--plugin-dir')), `plugin ${flag(c, '--plugin-dir')} is outside ${root}`);
});

test('A13: every run has its own HOME, XDG, config and temp directories under the eval root', () => {
  for (const c of first) {
    for (const key of ['HOME', 'XDG_CONFIG_HOME', 'XDG_CACHE_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'CLAUDE_CONFIG_DIR', 'TMPDIR']) {
      assert.ok(c.env[key], `${key} is unset`);
      assert.ok(inside(c.env[key]), `${key}=${c.env[key]} is outside ${root}`);
    }
    assert.notEqual(c.env.HOME, hostHome);
  }
  assert.equal(new Set(first.map(c => c.env.HOME)).size, 4, 'two runs share a HOME');
});

test('A13: nothing of the host session leaks into a run', () => {
  for (const c of first) {
    assert.equal(c.env.CLAUDE_PROJECT_DIR, undefined);
    assert.equal(c.env.DFORGE_BUDGET, undefined);
    assert.equal(c.env.DCC_SENTINEL, undefined);
    assert.notEqual(c.env.CLAUDE_CODE_SESSION_ID, 'host-session');
    for (const [key, value] of Object.entries(c.env)) {
      if (key === 'PATH') continue;
      assert.ok(!value.includes(hostHome) && !value.includes(hostConfig) && !value.includes(hostProject), `${key}=${value} names a host directory`);
    }
  }
});

test('A13: the owner credentials are copied in and the owner settings are not', () => {
  const dirs = new Set(first.map(c => c.env.CLAUDE_CONFIG_DIR));
  assert.equal(dirs.size, 4);
  for (const dir of dirs) {
    assert.ok(existsSync(join(dir, '.credentials.json')));
    assert.equal(existsSync(join(dir, 'settings.json')), false);
  }
});

test('A13: the run leaves the host home, config, project and source repository untouched', () => {
  assert.deepEqual(tree(hostHome), homeBefore);
  assert.deepEqual(tree(hostConfig), configBefore);
  assert.deepEqual(tree(hostProject), projectBefore);
  assert.equal(git(fx.repo, 'status', '--porcelain', '--untracked-files=all'), reposBefore.status);
  assert.equal(git(fx.repo, 'worktree', 'list'), reposBefore.worktrees);
  assert.equal(git(fx.repo, 'for-each-ref'), reposBefore.refs);
});
