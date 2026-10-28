**Exploring approaches:**

- Propose 2-3 different approaches with trade-offs
- Make one of them the do-less option: the smallest change that could meet the
  goal (delete or simplify something, change a configuration, or change
  nothing), so the others have to beat it. Recommend it when they do not.
- Present options conversationally with your recommendation and reasoning
- Lead with your recommended option and explain why
- YAGNI ruthlessly - remove unnecessary features from every approach and design

**Choosing the execution strategy:**

When `executionStrategy` is `sequential` or `parallel` (see Settings), skip the
question and record that value. Otherwise, once the approach is settled and
before you present the design, ask your human partner one multiple-choice
question, on its own:

> How should the plan execute?
> 1. **Sequential** (default) — one task at a time; the safest choice, and the
>    right one when the work is one chain of dependent changes.
> 2. **Parallel subagents** — independent tasks run at the same time, each in
>    its own worktree, merged and checked together after each wave; faster
>    when the work splits into parts that share no files.

Recommend one: parallel only when you can already name two or more parts that
share no file and do not consume each other's output; sequential otherwise.
Parallel runs only in subagent mode on Claude Code. On a Codex host do not
ask: the plan is sequential, and you say so in one line.

Record the answer near the top of the spec, below its title, as
`**Execution strategy:** parallel — <reason>` or
`**Execution strategy:** sequential — <reason>`. The plan inherits it.

When the answer is parallel, the design leans toward independence, because a
part that shares nothing is a part that cannot break its sibling:

- **Settle shared things first.** Types, interfaces, schemas, configuration
  keys and file layout that several parts use belong to one foundation part
  that runs before the others.
- **Give every file one owner.** Registries, barrels and index files, route
  tables, dependency manifests and lockfiles, migrations and version files are
  where parallel work collides; assign each to exactly one part, or to the
  foundation part.
- **Keep risk alone.** Security, data-loss, migration and concurrency work
  runs on its own, never beside a sibling.
- **Isolate the tests.** Say how parts' tests avoid each other at run time —
  ports, databases, fixed paths, global state — or that they share nothing.
- Add a `## Parallel decomposition` section to the spec: the parts, the files
  each owns, what each consumes from the foundation, and which parts may run
  together. writing-plans turns it into waves.

Never bend a design out of shape to make it parallel: a part that genuinely
needs another's output waits for it.

**Presenting the design:**

- Once you believe you understand what you're building, present the design
- Scale each section to its complexity: a few sentences if straightforward, up to 200-300 words if nuanced
- Ask after each section whether it looks right so far; with `designApproval=whole`, present every section in one message and ask once (see Settings); under `autoRun=on` present no design (see Auto by default), on Claude Code only
- Cover: architecture, components, data flow, error handling, testing, how the
  work will be accepted, and the riskiest assumption
- On Claude Code, when an option is genuinely clearer shown than described, present it visually with the Artifact tool
- Be ready to go back and clarify if something doesn't make sense

**Design for isolation and clarity:**

- Break the system into smaller units that each have one clear purpose, communicate through well-defined interfaces, and can be understood and tested independently
- For each unit, you should be able to answer: what does it do, how do you use it, and what does it depend on?
- Can someone understand what a unit does without reading its internals? Can you change the internals without breaking consumers? If not, the boundaries need work.
- Smaller, well-bounded units are also easier for you to work with - you reason better about code you can hold in context at once, and your edits are more reliable when files are focused. When a file grows large, that's often a signal that it's doing too much.

**Working in existing codebases:**

- Explore the current structure before proposing changes. Follow existing patterns.
- Where existing code has problems that affect the work (e.g., a file that's grown too large, unclear boundaries, tangled responsibilities), include targeted improvements as part of the design - the way a good developer improves code they're working in.
- Don't propose unrelated refactoring. Stay focused on what serves the current goal.
