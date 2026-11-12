# dflow

A Claude Code workflow plugin: plan, build, review and ship, with a task gate
that only a passing command can open. Claude Code only.

- **One document per unit of work.** The design is the head of the plan; plans
  hold decisions, signatures and test assertions, not code.
- **Scripts keep the books.** Ticking a task, moving a board row, pushing to
  darkmem and writing a checkpoint cost no model tokens.
- **A task is done when its command passes.** `dflow done` runs the task's
  verify command and only then ticks, commits and moves on.
- **One review per branch, sized to the diff.** Every finding carries evidence
  that can be re-run.
- **Docs that cannot rot quietly.** Four living files with line budgets, a
  dead-path check, and a plan that names the docs it invalidates.

## Install

```text
/plugin marketplace add darkraise/darkraise-ai-plugins
/plugin install dflow@darkraise
```

Requires Node 20 or later on `PATH`, and Git. Then, in a repository:

```text
/dflow:init
```

## The loop

| Step | Command | What happens |
| --- | --- | --- |
| Plan | `/dflow:plan <what>` | Chooses the depth, writes the plan, links a board row, asks for one approval |
| Build | `/dflow:build` | For each task: tests first, implement, `dflow done <N>` |
| Review | `/dflow:review` | Tier 0, 1 or 2 by diff size and risk; findings with evidence |
| Ship | `/dflow:ship` | Gates, acceptance, UI proof, docs, then closes the plan and the board row |
| Any time | `/dflow:status`, `/dflow:hud` | Where the work stands and the one next step |

A change of a couple of files with no open decision gets no plan at all.

## Documents

```
docs/dflow/
  project.md     what the system is, module map, how to run and verify it (150 lines at most)
  decisions.md   append-only decisions with their reasons
  gotchas.md     tooling and environment traps (100 lines at most)
  board.md       the backlog table
  config.json    gates, run command, darkmem project, thresholds
  plans/         one file per unit of work
.dflow/          run state, gitignored
```

`dflow doctor` checks the budgets, that every repository path named in
`project.md` and `gotchas.md` exists, the board, and every open plan.

### A plan

```markdown
# Rate-limit meter

**Board:** 12 · **Branch:** feat/rate-meter
**Goal:** one sentence.
**Acceptance:**
- A1: `npm test -- meter` passes
- A2 UI: the meter turns red below 10% remaining
**Docs:** project.md, decisions.md
**Risk:** none

## Design

- D1: a parser function, not a class — one call site
- Interfaces: `parseLimit(headers): Limit | null`

## Tasks

### Task 1: Parse the limit header
**Files:** src/limit.ts, tests/limit.test.ts · **After:** — · **Run:** inline · **Size:** S
- [ ] Test: `x-ratelimit-remaining: 5` parses to `{ remaining: 5 }`
- [ ] Implement `parseLimit`
- [ ] Verify: `npm test -- limit.test.ts`

## Log
```

Header fields sit before the first `##`. `Risk` is `none`, `security`,
`data-loss`, `migration` or `concurrency`. A task's `Run` is `inline` or
`worker`, its `Size` S, M or L, and it may carry its own `Risk`. Log lines read
`- <date> T<N> <K>: <text>`, where K is D (decision), G (gotcha), A (plan
amended), V (verify amended), X (extra files), W (test weakened), B (blocked),
U (unblocked) or N (note).

### The board

`| # | Item | Assigned | Acceptance | State | Note |` with the states `open`,
`planned`, `doing`, `verify`, `done`, `deferred` and `n/a`. The CLI moves a
plan's row: `planned` at approval, `doing` at the first finished task, `verify`
when every task is done, `done` at ship.

## Definition of done

A **task** is done when `dflow done` saw its verify command pass, the change is
committed, files outside the task's `Files` are explained, no existing test was
weakened without a reason, and an amended verify line carries a reason.

A **plan** is done when `dflow ship` finds every task done, the gates and every
acceptance command passing on the current commit, a fresh proof for every `UI`
line, a review at the required tier with no blocking finding open, the named
docs changed, and `dflow doctor` clean.

## Commands

| Command | Purpose |
| --- | --- |
| `dflow init [--gate "name=cmd"] [--darkmem <project>]` | Scaffold `docs/dflow`, add gates, map darkmem |
| `dflow plan new\|check\|approve\|use` | Create, lint, approve or select a plan |
| `dflow status [--json\|--brief]` | State and the one next step |
| `dflow next` | Start the next ready task and print its brief |
| `dflow done <N> -m "<msg>" [--extra] [--weaken] [--allow-empty]` | Verify, tick, commit |
| `dflow block\|unblock <N> "<text>"` | Record or clear a hard blocker |
| `dflow log <N\|-> <D\|G\|A\|N> "<text>"` | Append a plan log line |
| `dflow amend <N> --verify "<cmd>" --reason "<why>"` | Change a verify command, logged |
| `dflow gate [name…]` | Run the project gates |
| `dflow review pack\|add\|list\|verify\|resolve\|judge\|record` | The review |
| `dflow proof <A-id> --shot <file> --text "<seen>"` | Record UI evidence |
| `dflow ship [--check]` | Check the definition of done and close the plan |
| `dflow doctor` | Docs, board and plan checks |
| `dflow wave`, `dflow worktree add\|merge\|drop <N>` | Worker tasks side by side |
| `dflow plans [--conflicts]`, `dflow session <row>` | Plans across worktrees |
| `dflow sync push\|pull\|status` | The darkmem projection |
| `dflow cost [--plan <slug>]` | Token use by phase and model |
| `dflow context` | Context size and the reset threshold |

## Review

`dflow review pack` computes the tier and the mechanical facts: files outside
the plan, amended verify lines, weakened tests, the ratio of test lines to
source lines, suite time against the default branch, added TODO lines.

| Tier | When | Who |
| --- | --- | --- |
| 0 | 40 changed lines or fewer, no risk | the session |
| 1 | default | one `dflow:reviewer` (Opus 5.5) |
| 2 | a risk is set, over 800 lines or over 25 files | the `deep-review` workflow: two reviewers, one verifier |

A finding has a file, a line, a claim, what it breaks, and either a command
that exits non-zero while the defect exists or an exact quote. `dflow review
verify` re-runs the commands: a failing one proves the finding, and the same
command passing later closes it.

## Context

Every tool call re-reads the whole context, so dflow keeps it small: CLI output
is capped, the session works from a task brief, and when the context passes
`context.resetAt` (150,000 tokens by default) `dflow done` prints a `RESET:`
line at the task boundary. The HUD mod then compacts and resumes the build.
Without the mod, the PreCompact and SessionStart hooks shape and follow the
harness's own compaction.

## HUD

`/dflow:hud` cycles a one-line band above the prompt, a pane and off;
`/dflow:hud band|pane|off` sets one. It reads `.dflow/hud.json`, which the CLI
rewrites on every state change, and costs no model tokens.

## Parallel work

Tasks marked `Run: worker` run side by side as `dflow:worker` subagents
(Sonnet 5.5) in worktrees the CLI creates from the current head, when two or
more are ready with disjoint files. Separate plans run as separate background
sessions (`dflow session <row>` prints the command); `dflow plans --conflicts`
refuses overlap.

## darkmem

Off unless all three are set: the project in `docs/dflow/config.json`
(`dflow init --darkmem <project>`), the server in `~/.dflow/config.json`
(`{"darkmem": {"url": "…"}}`), and the key in `DARKMEM_API_KEY`.

The repository is the source of truth; darkmem is a projection.

| Thing | Form |
| --- | --- |
| Document URI | the path below `docs/`: `dflow/board.md`, `dflow/plans/<file>.md` |
| Board sources | register `dflow/board.md`; plans `dflow/plans/*.md` |
| Row to plan | the Assigned cell holds `docs/dflow/plans/<file>.md` |
| Workstream | one per plan, keyed by the plan's file name without `.md`, property `plan_uri` |
| Task state | a `ledger` entry with properties `task`, `state` (`todo`, `wip`, `review`, `blocked`, `done`) and `commit`; a blocked entry's body is the reason |
| Checkpoint | a `checkpoint` entry at each stop: progress, next task, branch, commit |
| Client | header `X-Darkmem-Client: dflow` |

On the default branch every document under `docs/dflow` is pushed by content
hash. On a plan branch only that plan and its own board row are, so branches
never overwrite each other. The one inbound change is a board row edited in
darkmem's UI, pulled on the default branch at session start; a row changed on
both sides is reported and nothing is overwritten.

## Configuration

`docs/dflow/config.json`, all keys optional:

```json
{
  "gates": [{ "name": "test", "cmd": "npm test", "timeout": 900 }],
  "run": { "cmd": "npm run dev", "url": "http://localhost:3000" },
  "ui": { "paths": ["src/ui/"] },
  "verifyTimeout": 600,
  "budgets": { "project.md": 150, "gotchas.md": 100 },
  "context": { "resetAt": 150000 },
  "review": { "tier0Lines": 40, "tier2Lines": 800, "tier2Files": 25 },
  "tests": { "maxRatio": 2, "maxSuiteGrowth": 0.2 },
  "darkmem": { "project": "" },
  "defaultBranch": "main"
}
```

## Development

```text
node --test "plugins/dflow/tests/*.test.mjs"
claude plugin validate plugins/dflow
claude plugin test plugins/dflow
```

The design record is `docs/dflow/design.md`. The eval suite is described in
`evals/README.md`.
