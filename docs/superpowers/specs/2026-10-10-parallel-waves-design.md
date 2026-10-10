# Parallel waves — design

**Date:** 2026-10-10
**Plugin:** `plugins/dr-superpowers`
**Status:** approved for implementation

## Problem

dr-superpowers executes a plan one task at a time. Subagent mode dispatches one
implementer, reviews it, and only then starts the next task;
`reference/delegated-task.md` forbids parallel implementers outright, because
two agents editing one checkout clobber each other. Plans whose tasks are
genuinely independent still pay for every task in sequence.

The owner wants the planning phase to ask, for both the spec and the plan,
whether execution should use parallel subagents or stay sequential, and, when
parallel is chosen, to shape the spec and plan so that independent work runs at
the same time. Parallel execution must not break existing behaviour and must
not create new bugs.

## Decision

Add an opt-in **parallel waves** strategy.

- Brainstorming asks one question on the architectural path, after the
  approaches and before the design is presented: parallel waves or sequential
  (the default). The answer is recorded in the spec as
  `**Execution strategy:** parallel | sequential — <reason>`, and a parallel
  spec carries a **Parallel decomposition** section.
- writing-plans reads that line (and asks the same question when the spec has
  none) and, for a parallel plan, groups the tasks into **waves**: contiguous
  task ranges whose members share no file and do not depend on each other. The
  header records them as `**Parallelism:** waves — 1 | 2-4 | 5`.
- subagent-driven-development runs each wave's tasks concurrently, each in its
  own git worktree, reviews each task exactly as today, merges the reviewed
  tasks into the feature branch one at a time, and runs an integration check
  before the next wave starts.

Sequential stays the default. A plan without a `**Parallelism:**` line, or with
`**Parallelism:** sequential`, runs exactly as before: no script, skill path or
ledger line changes for it.

## Approaches considered

1. **Parallel implementers in one checkout.** Cheapest, and wrong: concurrent
   edits, interleaved commits, a shared index lock and test runs that observe a
   sibling's half-written files. Rejected.
2. **Waves in isolated worktrees, merged after review (chosen).** Each task
   gets its own worktree from the wave's base commit, so implementers cannot
   see or disturb each other. Reviews stay per task and unchanged. Merges are
   serial and checked. The integration check catches semantic conflicts that
   disjoint files cannot.
3. **Pipelining (start task N+1 while task N is in review).** Smaller win,
   same isolation cost, and it breaks the review-before-next-task invariant
   that later tasks rely on. Rejected.

## Safety model

The whole design rests on one invariant: **serializing a wave is always
correct.** Waves are contiguous ranges and every dependency points into an
earlier wave, so running a wave's tasks one after another in index order is the
existing sequential mode. Every doubt, failure or budget squeeze therefore
degrades to sequential execution; nothing degrades to a guess.

The layers, from plan time to merge time:

| Hazard | Guard | Where |
|---|---|---|
| Two tasks edit the same file | Same-wave tasks have disjoint `**Files:**` paths | plan-lint (error) |
| A task consumes another task's output | `**Depends on:**` on every task; every dependency sits in an earlier wave | plan-lint (error) |
| Hidden coupling (a registry, global state, shared test resource) | Pre-flight ruling seat scans every same-wave pair | subagent-driven-development Setup |
| Dependency manifests and lockfiles | A task touching one runs alone in its wave | plan-lint (error) |
| Risk-3 work (security, data loss, migration, concurrency) | Runs alone in its wave | plan-lint (error) |
| External executor tasks (their own worktree ownership) | Run alone in their wave | plan-lint (error) |
| Implementers clobbering each other | One worktree per task (`isolation: "worktree"`), detached at the wave base | parallel-waves.md |
| An implementer edits outside its plan files | The actual diff is checked against merged siblings before merge | `scripts/wave merge` |
| A semantic conflict between tasks | `**Integration check:**` runs after the wave is merged; failures enter a fix loop | parallel-waves.md |
| Session budget | `context-size --wave W` reserves one task's growth per concurrent task; the wave narrows to fit | parallel-waves.md |
| Compaction mid-wave | Ledger `Wave` lines plus a ref per task (`sdd/<plan>/task-<N>`) | parallel-waves.md §Recovery |
| Codex host, inline mode | Not supported: plan-lint errors on waves there | plan-lint (error) |

## Plan format

Header, below `**Execution:**`:

```markdown
**Parallelism:** waves — 1 | 2-4 | 5-6 | 7
**Integration check:** `npm test`
**Worktree setup:** `npm ci`
```

- `**Parallelism:**` is `sequential` (optionally with a reason) or
  `waves — <range> | <range> | …`. Ranges are `N` or `A-B`, ascending,
  contiguous and covering every task exactly once.
- `**Integration check:**` is the one command that proves the merged wave
  works together, normally the full test suite. Required with waves.
- `**Worktree setup:**` is what a fresh worktree needs before its tests can
  run (dependency install, code generation), or `none`. Required with waves.
- A waves plan's Execution line names `subagent`; inline mode implements in
  the session itself, so it has nothing to parallelize.

Every task of a waves plan carries `**Depends on:** none` or
`**Depends on:** Task 1, Task 3`, below its `**Interfaces:**` block.

## Execution

`reference/parallel-waves.md` holds the procedure; subagent-driven-development
points at it from The Task Loop. One wave of width more than one:

1. **Gate the start.** Every earlier wave is integrated, the checkout is clean,
   and `scripts/context-size --wave <c>` passes for the concurrency `c`
   (at most 3), narrowing until it passes; at 1 it is today's check.
2. **Open the wave.** Record the base, write `Wave <k>: started (…)`, create
   the briefs, and dispatch the implementers in one message, each with
   `isolation: "worktree"`. Each implementer first detaches its worktree at the
   wave base, and moves the task ref `sdd/<plan>/task-<N>` to every commit it
   makes.
3. **Run each task's loop independently** (delegated-task.md §2-§4): report,
   review against `<base>..<task ref>`, fix rounds. A fresh fix dispatch gets a
   new worktree detached at the task ref.
4. **Merge as each task passes review.** `scripts/wave merge` refuses a task
   whose changed files overlap what the wave has already merged; such a task
   gets a fresh fix round on top of the merged head. A merged task writes its
   `complete` line, so `complete` keeps meaning "on the branch".
5. **Integrate.** When every task is merged, remove the worktrees
   (`scripts/wave clean`), run `**Worktree setup:**` and
   `**Integration check:**` in the checkout, and write
   `Wave <k>: integrated (…)`. A failing check enters a wave fix loop (the
   same five rounds and breaker as a task), dispatched to the highest-ranked
   implementer of the wave.

A wave of width one is an ordinary task: no Wave lines, no worktree.

## Out of scope

- Parallel execution on a Codex host and in inline mode.
- Parallel reviews of tasks in different waves, or pipelining across waves.
- Choosing an executor for a parallel task: executor tasks run alone.
