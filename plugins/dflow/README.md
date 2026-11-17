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

## One workflow plugin at a time

dflow, dforge and dagents each own a whole workflow: their hooks, skills and
state collide in one session. `scripts/workflow-guard.mjs`, shipped
byte-identical in each of the three, decides which of them are active and
stands dflow down when more than one is.

- **At session start** the hook runs the guard first. The guard reads the
  managed settings (`managed-settings.json` and the `managed-settings.d/`
  drop-ins), the project's `.claude/settings.local.json` and
  `.claude/settings.json`, your user `settings.json`, and the install record
  `plugins/installed_plugins.json`. With two or more of the three enabled, the
  hook prints a block naming each one with its disable commands,
  `claude plugin disable <name>@darkraise --scope local` first, then the
  enabling scope's command for one enabled at user or project scope. It tells
  the model to show the block and use none of the plugins. For the rest of the
  session the PreCompact and Stop hooks exit at once, and the HUD draws one
  line naming the active plugins and the check to run, and nothing else. Run
  the check yourself with
  `node <plugin-root>/scripts/workflow-guard.mjs --host claude`: one line per
  active plugin with the scope that enables it, exit 3 on a conflict.
- **Skills stay invocable.** Claude Code gives a plugin no way to hide its
  skills, so a stood-down dflow's skills and CLI still run when asked for by
  name; the hook's instruction to the model is the only check.
- **Older siblings do not stand down.** A dforge release older than the one
  that ships the guard has none: dflow still stands down beside it, but that
  dforge keeps running its own hooks. Every dagents release carries the guard.
- **Blind spots.** The guard reads files only, so it misses a plugin enabled
  through `--settings` or `--plugin-dir`, settings a server delivers, and MDM,
  registry or plist policy. A file it cannot read or parse prints one
  `workflow-guard: <reason>` line and counts as no conflict.

## The loop

| Step | Command | What happens |
| --- | --- | --- |
| Plan | `/dflow:plan <what>` | Chooses the depth, writes the plan, links a board row, asks for one approval |
| Build | `/dflow:build` | For each task: tests first, implement, `dflow done <N>` |
| Review | `/dflow:review` | Tier 0, 1 or 2 by diff size and risk; findings with evidence; then it stops for you |
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

`dflow init` also marks `decisions.md` and `gotchas.md` `merge=union` in
`.gitattributes`: they only grow, so entries promoted on two branches merge
without a conflict. Promoted decisions are numbered within their plan, as
`D-<plan>/<n>`.

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

A **task** is done when `dflow done` saw its verify command pass on a working
tree that matches what it commits, files outside the task's `Files` are
explained, no existing test was weakened without a reason, and an amended
verify line carries a reason. A task without a verify command cannot be done.

A **plan** is done when `dflow ship` finds every task done through `dflow done`
(a box ticked by hand does not count), the gates and every
acceptance command passing on the current commit, a fresh proof for every `UI`
line, a review at the required tier that covers the current code with no
blocking finding open, the named docs changed, and `dflow doctor` clean. A task
the owner drops is removed from the plan with a logged amendment.

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
| `dflow review pack\|add\|list\|verify\|check\|resolve\|judge\|record` | The review |
| `dflow proof <A-id> --shot <file> --text "<seen>"` | Record UI evidence |
| `dflow ship [--check]` | Check the definition of done and close the plan |
| `dflow doctor` | Docs, board and plan checks |
| `dflow wave`, `dflow worktree add\|merge\|drop <N>` | Worker tasks side by side |
| `dflow plans [--conflicts]`, `dflow session <row>` | Plans across worktrees |
| `dflow sync push\|pull\|status\|enable\|disable` | The darkmem projection, and your consent to it |
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
that exits non-zero while the defect exists or an exact quote. A reviewer
wrote the commands, so dflow never runs them: `dflow review verify` checks the
quotes and lists the commands, the session runs each one with its own shell
tool, where your permission settings apply, and records the result with
`dflow review check <id> --exit <status>`. A failing command proves the
finding, the same command passing later closes it, and exit 126 or 127 (the
command could not run) proves nothing.

Once the review is recorded the session reports it and stops: shipping closes
the plan and promotes its decisions, so it waits for your `/dflow:ship`. Set
`"autoShip": true` in `docs/dflow/config.json` to let the session go straight
on to ship; it still asks before pushing.

## Context

Every tool call re-reads the whole context, so dflow keeps it small: CLI output
is capped, the session works from a task brief, and when the context passes
`context.resetAt` (150,000 tokens by default) `dflow done` prints a `RESET:`
line at the task boundary. The HUD mod then compacts and resumes the build.
The mod keeps the size and the reset request per session, so another session
open in the same checkout is never compacted by it.
Without the mod, the PreCompact and SessionStart hooks shape and follow the
harness's own compaction.

## HUD

The dflow mod draws the build's state from `.dflow/hud.json`, which the CLI
rewrites on every state change. It draws only in a checkout whose git root
holds `.dflow`.

- `/dflow:hud` cycles band, pane and off, and reopens a pane closed by hand;
  `/dflow:hud band|pane|off` sets one. The choice is kept across sessions.
- `/dflow:hud sections` opens the pane on the Sections view;
  `/dflow:hud sections plan,context,repo` sets which cards show, in order.

The pane shows a Now row, then one framed card per section, then the Next row:

- **Account** (the account's color): email, name and organization, model and
  effort, Remote Control, and the config directory.
- **Plan** (yellow): progress, the plan's title and file, a meter, up to eight
  tasks around the current one, and any `⚠` checks.
- **Context** (cyan): the reading against the reset point (`┃`) and
  auto-compaction (`┊`), a trend, and the six largest `/context` categories.
- **Usage** (blue): the 5-hour and 7-day limits with pace and reset, other
  limits, and the session's cost.
- **Checks** (red): gates and the review.
- **Board** (white): the board row or counts, and darkmem's sync state.
- **Workers** (magenta): each running worker's task and branch.
- **Repo** (green): the repository, the folder, the branch with ahead and
  behind, and changed and untracked files.

Pressing a card's title collapses it. The buttons take hotkeys while the pane
has the keyboard: `c` Compact, `d` Dense or Detailed (one line per card), `s`
Sections (hide, show or reorder the cards), `m` Minimize (to the band), `r`
Resume and `b` Back from the Sections view.

The band is a frame in the account's color above the prompt: the email,
billing and Remote Control on its top rule beside **Expand**; a line with the
folder, branch, model, effort, plan progress and workers; a line with the
context, the 5-hour and 7-day limits and the cost; and a red line when a task
is blocked, gates failed or darkmem has a conflict or refusal. Each line
shrinks to fit, and below 48 columns the frame goes.

A session that starts on an approved plan with work left offers to resume it:
a card above the Now row, or a row above the band, with **Resume** (runs
`/dflow:build`) and **Dismiss**.

The HUD costs no model tokens. git status runs every ten seconds and the
`/context` breakdown is estimated locally, each only while it is shown.

## Parallel work

Tasks marked `Run: worker` run side by side as `dflow:worker` subagents
(Sonnet 5.5) in worktrees the CLI creates from the current head, when two or
more are ready with disjoint files. Separate plans run as separate background
sessions (`dflow session <row>` prints the command); `dflow plans --conflicts`
refuses overlap.

## darkmem

Off unless all four hold: the project in `docs/dflow/config.json`
(`dflow init --darkmem <project>`), the server in `~/.dflow/config.json`
(`{"darkmem": {"url": "…"}}`), the key in `DARKMEM_API_KEY`, and your consent
to that project for this repository. A repository can name any project, so a
clone never sends anything with your key until you agree: `dflow init
--darkmem` records the consent, and `dflow sync enable` records it for the
project the repository names now (`dflow sync disable` withdraws it). It is
kept per repository in `~/.dflow/config.json` under `darkmem.repositories`,
and covers every worktree of the repository.

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

darkmem's board row edit route has to accept the API key; where it does not,
the row is reported as refused and the rest of the projection goes on.

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
  "autoShip": false,
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
