---
name: plan
description: Use when a change needs a plan before code - a new feature or subsystem, a change across several files, an open design decision, or a risk (security, data loss, migration, concurrency). Writes one lean plan with its design at the head, links it to the board and gets a single approval.
argument-hint: "[what to build | board row <N>]"
---

# Plan

## 1. Choose the depth, in one line

`Depth: none | plan | plan+critique — <reason>`

- **none**: a couple of files, no open decision, no risk. Do not write a plan: write the test first, implement, run the tests that cover it, commit. Stop reading here.
- **plan**: everything else.
- **plan+critique**: a risk is present, an interface something else depends on changes, or an approach question is open.

## 2. Ground it

- Read `docs/dflow/project.md` whole. If `docs/dflow/` is missing, run `/dflow:init` first.
- Search past decisions and plans by section, never by loading files: darkmem `document_search` and `memory_search` when those tools are connected, otherwise `rg` over `docs/dflow/decisions.md` and `docs/dflow/plans/`.
- Explore code narrowly: darkmem `code_search` when the repository is indexed, direct reads for a known place, one `Explore` agent for a broad sweep.

## 3. Ask only what is the owner's

Scope, behaviour trade-offs and irreversible choices are the owner's. Ask them in one batch, recommendation first. Decide everything else yourself and record it as a design decision.

## 4. Write the plan

On the default branch, branch first (`git switch -c <type>/<slug>`). Then:

```
dflow plan new <slug> --title "<title>" [--board <row>]
```

Fill in the file it creates:

- **Goal**: one sentence.
- **Acceptance**: observable outcomes. Each line holds a command in backticks, or is marked `UI` (proven in the running app) or `UI visual` (its appearance matters).
- **Docs**: the living docs this change makes wrong (`project.md`, `decisions.md`, `gotchas.md`), or `none — <reason>`.
- **Risk**: `none`, `security`, `data-loss`, `migration` or `concurrency`.
- **Design**: decisions with their reasons (`D1: … — …`), exact signatures and data shapes, what is out of scope. No code.
- **Tasks**: one commit each. `Files` it may change; `After` the tasks it needs; `Run: inline` unless the task is independent, fully specified and at least one other such task can run beside it (`worker`); `Size` S, M or L; `Risk` on a task whose defect would be costly to find late.
- **Steps**: the test assertions first, then what to implement (name the signature), then `Verify:` with the narrowest command that proves the task.

A plan states decisions, signatures and assertions. Code belongs in the build.

### Tests the plan may ask for

- One test per behaviour: an acceptance line, a decision with a visible effect, or a bug being fixed.
- None for wording, constants, configuration, private helpers reached through a public path, or framework behaviour. No assertion on prose unless a program parses it.
- The lowest level that fails for the right reason; one end-to-end check per acceptance line at most; a new case in an existing table before a new file.
- A task that changes no behaviour lists no test and verifies with existing ones.

### UI

If any acceptance line is `UI`, read `ui.md` beside this file and add the `## UI` section it describes.

## 5. Check, critique, approve

1. `dflow plan check` until it reports no problems.
2. For plan+critique: dispatch one `dflow:reviewer` (model opus, effort high) with the plan's path and the instruction to critique the plan document. Amend the plan for findings that hold, and close each with `dflow review resolve <id> fixed` or `declined "<reason>"`.
3. Give the owner the plan's path and at most six lines: goal, acceptance, task count, risk, what you decided for them. Ask for approval of the whole document, once.
4. On approval: `dflow plan approve`.

## 6. Hand over

- Three tasks or fewer: continue with the dflow:build skill.
- More: tell the owner in one line to run `/clear` and then `/dflow:build`, and stop. The build then starts with a small context, and may run on a cheaper model.
