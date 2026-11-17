**Exploring approaches:**

- Propose 2-3 different approaches with trade-offs
- Make one of them the do-less option: the smallest change that could meet the
  goal (delete or simplify something, change a configuration, or change
  nothing), so the others have to beat it. Recommend it when they do not.
- Present options conversationally with your recommendation and reasoning
- Lead with your recommended option and explain why
- YAGNI ruthlessly - remove unnecessary features from every approach and design

**Choosing the execution strategy:**

Ask nothing here. Record the `executionStrategy` setting near the top of the
spec, below its title: `**Execution strategy:** sequential — <why>` under
`sequential`, the default, or `**Execution strategy:** parallel — <why>` under
`parallel`. Under `ask`, record no line: dagents:writing-plans §Parallel waves
asks the question. The plan inherits the line. Waves run only for a plan whose
Execution line names `subagent`, the default mode, on Claude Code; an inline
plan (`executionMode=inline`, or your human partner asks) or a Codex plan is
sequential whatever the line says. dagents:writing-plans §Parallel waves
groups a parallel plan's waves.

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
