---
name: brainstorming
description: "You MUST use this before any creative work - creating features, building components, adding functionality, or modifying behavior. Explores user intent, requirements and design before implementation."
---

# Brainstorming Ideas Into Designs

Help turn ideas into fully formed designs and specs through natural collaborative dialogue.

Start by classifying how much process the request needs, then work
through your path: understand the context, refine the idea, present a
design, and get your human partner's approval.

<HARD-GATE>
Do NOT invoke any implementation skill, write any code, scaffold any
project, or take any implementation action until you have told your
human partner what you intend and they have approved it. This applies
to EVERY task on EVERY path below — the ceremony scales with the task;
the approval gate never does.
</HARD-GATE>

## Three Paths

Before your first question, classify the request and say it in one
line — `Process: <spike|bounded|architectural>, <inline|subagent> —
<trigger | no trigger>` — so your human partner can override it. The mode
slot is your expectation only; the plan's Execution line decides. The
triggers are the seven in dforge:using-dforge's Process Depth:
a new project or subsystem; an interface that something outside its own
files depends on changes; the files touched cannot be enumerated after
exploring; a load-bearing approach question is open; irreducible risk
(security, data loss, migration, concurrency); behaviour too intricate for
a chat design; or your human partner asked for a spec.

On the architectural path the line also names the depth,
`Process: architectural, <inline|subagent>, depth <d> — <triggers>`. Name each
trigger that holds by its id (`new-subsystem`, `interface`, `unenumerable`,
`approach`, `risk`, `intricate`, `asked`, in the order of the list above), and
take `<d>` from `scripts/depth-route --spec-triggers <ids>`: `full` for `risk`
or `new-subsystem`, `standard` for `interface`, `light` otherwise. The depth
sizes the reviews that follow the spec; it never removes the approval. Your
human partner may set it by hand at the spec review.

- **Spike** — a feasibility question ("can we...", "is it possible...",
  "quick and dirty is fine") whose output is an answer, not code you
  keep. Present the question and what you'll try in 2-3 sentences, get
  a nod, then find out as cheaply as correctness allows. No design
  doc, no spec file. Report findings as a recommendation; anything you
  built stays labeled throwaway.
- **Bounded** — no trigger holds: a new flag, a small endpoint, a
  one-file fix, or a small feature that adds a new flow. Ask the clarifying
  questions that matter, present a short design IN CHAT (a few
  sentences to a few short paragraphs), self-review it once, and
  STOP. Implementation starts only after your human partner says yes
  to that design — a bounded task's approval is as hard a gate as an
  architectural one. No spec file, no implementation plan document.
- **Architectural** — at least one trigger holds; name it and the depth. Follow the
  full process: questions, approaches, sectioned
  design, written spec, then the writing-plans skill.

Doubt means check the trigger list, not jump to the heavier path
(`processBias` moves where doubt lands; see Settings). The
ratchet is one-way: a trigger discovered mid-task upgrades the path —
stop, say so, and step up. A trigger found after the Process line was said
reruns `scripts/depth-route --spec-triggers` with the whole list, and the depth
can only rise; a `**Depth:** <d> — owner` line is left as it is. Nothing
downgrades mid-task.

## Settings

The workflow settings in force arrive as one line at session start, `dforge
settings in force (…): key=value; …`. With no such line in context, run
`scripts/dforge-config workflow` once before your first question; it prints the
same line, or nothing when every setting is at its default. A key the line does
not name is at its default. Your human partner's own instructions outrank a
setting, and no setting removes the approval gate.

- `processBias=lighter`: take the architectural path only when a trigger
  plainly holds; doubt resolves to bounded. `processBias=heavier`: doubt
  resolves to architectural. A request for a spec and the irreducible-risk
  trigger hold under either.
- `questionStyle=batched`: ask all the clarifying questions in one message
  instead of one per message.
- `designApproval=whole`: present every design section in one message and ask
  for approval once, instead of after each section. It has no effect on Claude
  Code under `autoRun=on`, which presents no design.
- `executionStrategy=sequential` or `executionStrategy=parallel`: do not ask
  the execution-strategy question; record the value as the answer. `parallel`
  still becomes sequential when you cannot name two parts that share no file,
  on a Codex host,
  and when `executionMode=inline`, which makes the plan sequential.
- `specReview=false`: after the spec self-review block, skip the User Review
  Gate and go on to Implementation. It has no effect under `autoRun=on`:
  on Claude Code the spec review always happens.
- `autoRun=on`, the default: the architectural path runs as Auto by default
  says, and its one stop is the spec review. `autoRun=ask` offers an auto run
  once on the architectural path (see After the Design).
  `autoRun=off`: never offer an auto run. On a Codex host `on` behaves as
  `off`; say so in one line.

## Anti-Pattern: "Too Simple To Need Approval"

Every path ends with your human partner approving your intent before
implementation. A todo list, a single-function utility, a config
change — the design may be two sentences in chat, but you MUST present
it and get approval. "Simple" tasks are where unexamined assumptions
cause the most wasted work. What scales with simplicity is the
artifact, never the approval.

## Red Flags

| Thought | Reality |
|---------|---------|
| "This is too simple to need a design" | Simple means a short design, not no design. Two sentences in chat, then approval. |
| "I'll call it bounded and skip the spec" | Name, for each of the seven triggers, why it fails — or take the architectural path. |
| "It's bounded and the design is obvious — I'll start while they read it" | The gate is the approval, not the design's length. Present, then stop until you hear yes. |
| "I understand this kind of app, so it's bounded" | Bounded is decided by the trigger list, not by familiarity. A new project is a trigger. |
| "The spike works, so I'll keep the code" | A spike's output is an answer. Keeping the code is a new request — classify it. |
| "It grew, but I'm almost done — no need to re-classify" | Hidden complexity upgrades the path mid-task. Stop and say so. |
| "They approved the spike, so the follow-up change is approved too" | Each task gets its own classification and its own approval. |
| "The design reads fine, so I'll skip the self-review" | The round is required on every design and spec. No `Self-review (round 1 of 1):` block before the approval question means it did not happen. |
| "A reviewer subagent can do the self-review" | The round is yours. Any other review comes after it and does not replace it. |

## Checklist

Classify first, announce the path, then create a task for each item on
your path and complete them in order.

**Spike:**
1. **Explore project context** — enough to frame the probe
2. **Present question + probe plan** — 2-3 sentences
3. **Get approval** — a nod is enough
4. **Investigate** — as cheaply as correctness allows
5. **Report findings** — a recommendation; label anything built as throwaway

**Bounded:**
1. **Explore project context** — check files, docs, recent commits
2. **Ask clarifying questions** — one at a time, the ones that matter
3. **Present short design in chat** — approach, files touched, testing
4. **Self-review the design** — one round, its block in the same message as the design (see Self-reviewing a bounded design)
5. **Get approval** — STOP and wait for an explicit yes; presenting the design and starting in the same breath is skipping the gate
6. **Implement** — proceed with the normal development workflow (TDD applies); no plan document

**Architectural:** (under `autoRun=on`, the default on Claude Code, steps 6-8
and 12-13 run as Auto by default says)
1. **Open the item register** — when the request or a review carries two or
   more distinct items, before the spec
2. **Explore project context** — check files, docs, recent commits
3. **Ask clarifying questions** — one at a time, understand purpose/constraints/success criteria
4. **Propose 2-3 approaches** — with trade-offs and your recommendation
5. **Ask the execution strategy** — parallel subagent waves or sequential execution, one question (see Choosing the execution strategy)
6. **Present design** — in sections scaled to their complexity, get user approval after each section
7. **Draft acceptance** — numbered, tagged, rated statements; ask your human partner about every one rated below `high` (see Drafting acceptance)
8. **Offer an auto run** — unless `autoRun=off` or on a Codex host: one question once the acceptance statements are settled (see After the Design)
9. **Write design doc** — save to `<docs>/specs/YYYY-MM-DD-<topic>-design.md` with its `**Depth:**` line, and commit
10. **Spec self-review** — one round for placeholders, contradictions, ambiguity, scope, acceptance and the riskiest assumption; post its block before the user review (see below)
11. **Architecture critic** — one `dforge:judge-opus` round on the written spec; fix or answer every Blocker and High finding (see Architecture critic: depth light skips it, and depth standard folds it into Fable's first round when Fable reviews)
12. **User reviews written spec** — ask user to review the spec file before proceeding; under `autoRun=on` this is Auto by default's spec review message, after Fable's review at depth standard or full (an auto run started from the offer has Fable review it instead, at those depths)
13. **Transition to implementation** — invoke writing-plans skill to create implementation plan

## Process Flow

Read [process-flow.md](references/process-flow.md) before you change the order of the spec phase or the path a request takes through it.

**Terminal states are path-bound.** Architectural: the ONLY skill you
invoke after brainstorming is writing-plans — never frontend-design,
mcp-builder, or any other implementation skill. Bounded: after
approval, implementation proceeds directly through the normal
development workflow; no plan document. Spike: the terminal state is a
reported recommendation.

## The Process

The subsections below serve the bounded and architectural paths (a
spike stops at "present the probe, get a nod"). Sections from
**Exploring approaches** onward are architectural-path depth — for
bounded work, context plus a few questions plus a short in-chat design
and its self-review is the whole process.

**Understanding the idea:**

- Check out the current project state first (files, docs, recent commits)
- Read `<docs>/distilled/constraints.md` and
  `<docs>/distilled/rejected.md` when the project has them: a
  constraint outranks the spec you are about to write, and a rejected approach
  is the one a fresh design most reliably re-proposes. Neither is an error when
  absent.
- When the design has a user-facing part — anything a user sees or does —
  invoke dforge:ui-ux before drafting acceptance: its Shape phase writes the
  spec's `## UI/UX contract`, the source of every UI acceptance statement.
  Under `autoRun=on`, ask its profile and state-board questions among your
  clarifying questions.
- Run `scripts/register open --spec <any spec this work touches>`, then list
  `<docs>/registers/` and run `scripts/register open <file>` on every
  register whose `**Covers:**` is `-`: a list captured before anything was
  designed is named by no spec, so no `--spec` query reaches it. A row deferred
  months ago is a decision this design inherits; a findings file nobody reopens
  is how it was lost before.
- Before asking detailed questions, assess scope: if the request describes multiple independent subsystems (e.g., "build a platform with chat, file storage, billing, and analytics"), flag this immediately. Don't spend questions refining details of a project that needs to be decomposed first.
- Under `autoRun=ask` or `autoRun=off` only (under `on`, one spec covers the whole request) on Claude Code, and under any setting on a Codex host: if the project is too large for a single spec and the next bullet does not send it to dforge:planning-a-product, help the user decompose into sub-projects: what are the independent pieces, how do they relate, what order should they be built? Then brainstorm the first sub-project through the normal design flow. Each sub-project gets its own spec → plan → implementation cycle.
- A new product built from scratch, or a request naming several subsystems in a repository with no `<docs>/roadmap.md`, goes to dforge:planning-a-product instead: its epics and milestones become register rows before any feature is designed, rather than prose in a program spec.
- When `<docs>/roadmap.md` exists, this spec is an epic. Find its row with `scripts/roadmap status`, set the row's Assigned cell to this spec's path once the spec is written (`scripts/register set <milestone register> <id> doing --assigned <spec path>`), and open the spec's requirement register below even when the request was one sentence: the roadmap is the list the requirements came from.
- For appropriately-scoped projects, ask questions one at a time to refine the idea
- Prefer multiple choice questions when possible, but open-ended is fine too
- Only one question per message - if a topic needs more exploration, break it into multiple questions (`questionStyle=batched` asks them all in one message; see Settings)
- Focus on understanding: purpose, constraints, success criteria

**Opening an item register:**

When a request, a review or a batch arrives carrying two or more distinct items,
write them down before designing anything. Create
`<docs>/registers/YYYY-MM-DD-<slug>.md` with a `**Source:**` line
naming where the items came from, a `**Covers:**` line holding `-` until a spec
exists, and the table header
`| # | Item | Assigned | Acceptance | State | Note |` with its `|---|---|---|---|---|---|`
separator row. Add each item with
`scripts/register add <file> "<the requester's words>"` — their words, not your
paraphrase — and confirm the file with `scripts/register check <file>`.

Once the spec is written, set the register's `**Covers:**` line to that spec's
repository-relative path, comma-separated when several apply. Nothing else
fills it in, and until it is filled no plan-side surface can see the register.

The register is the authority on whether the work is finished. A list that
lives only in the conversation is a list that gets shorter every session.

**Self-reviewing a bounded design:**

Before asking for approval, check the design once yourself, never through a
subagent, and fix what you find inline:

1. **Files:** every file the change touches is named.
2. **Testing:** the design says how the change will be verified.
3. **Assumptions:** every assumption you made is stated, so your human partner can correct it.
4. **Ambiguity:** nothing in it can be read two ways.

Below the design, in the same message, post `Self-review (round 1 of 1):` with
one line per item: clean, or what you fixed. Do not re-review after fixing.
A revision your human partner asks for gets one new round.

**Exploring approaches, choosing the execution strategy, presenting the design:**

Read [design-phase.md](references/design-phase.md) before you propose approaches, ask the execution strategy or present the design.

## Auto by default (`autoRun=on`)

Read [auto-by-default.md](references/auto-by-default.md) before you write the spec under `autoRun=on`.

## After the Design (architectural path)

**Drafting acceptance:**

Read [drafting-acceptance.md](references/drafting-acceptance.md) before you draft the spec's acceptance statements.

**Offering an auto run:**

Read [auto-run-offer.md](references/auto-run-offer.md) before you offer an auto run.

**Documentation:**

Read [spec-document.md](references/spec-document.md) before you write the spec document.

**Spec Self-Review:**

Read [spec-self-review.md](references/spec-self-review.md) before you self-review the written spec.

**Architecture critic:**

Read [architecture-critic.md](references/architecture-critic.md) before you run the architecture critic or Fable's spec review.

**User Review Gate:**

Read [user-review-gate.md](references/user-review-gate.md) before you ask your human partner to review the written spec.

**Implementation:**

- In an auto run skip this check: the plan is always written in this session.
  Otherwise run `scripts/context-size --plan`
  (see using-dforge §Session Budget).
  It measures against 150% of the task budget, capped at the
  final-phase limit: writing the plan here costs less than a fresh session's
  baseline and reload. On exit 5 (handoff), invoke dforge:handoff with the spec
  as the draft and the next action "Write the implementation plan with
  dforge:writing-plans." — the plan is written in a fresh session.
- Otherwise invoke the writing-plans skill to create a detailed implementation plan.
- Do NOT invoke any other skill. writing-plans is the next step — in this
  session or, after a handoff, the next one.
