# dr-superpowers — Greenfield roadmap (design)

Date: 2026-10-07. Status: owner-approved design. Scope: greenfield projects
built from scratch over many sessions, where an epic or feature goes missing and
a session then claims a phase or milestone is done. Release: 1.30.0.

## 1. What this is for

dr-superpowers works for a feature or a bug fix: one spec, one plan, one branch.
On a greenfield project the work spans many specs, and the plugin loses track of
it. Seven mechanisms were verified against the code on `main` (80ba2d0):

1. **Epics never enter a register.** A register is required for "a request, a
   review or a batch carrying two or more distinct items"
   (`skills/brainstorming/SKILL.md`, Opening an item register). A greenfield ask
   is usually one sentence; the epics are invented during decomposition
   (Understanding the idea, the scope bullets), so nothing requires a register
   and they live only as prose in a program spec.
2. **The program is a frozen linked list.** Each plan copies
   `sub-project k of n — next: <title>` from that prose
   (`skills/writing-plans/SKILL.md`, the Program line). An epic added, split or
   postponed later never changes it. The item-registers design (2026-09-20,
   §1.1) diagnosed this; registers fixed it only where a register exists.
3. **There is no milestone or phase layer.** No file says what a milestone
   needs or whether it is finished, so "the phase is done" is always a claim
   from memory.
4. **Requirement coverage inside an epic is a skim.** `plan-lint` enforces that
   every register row assigned to a plan is cited by a task's `**Items:**`
   line, but without a register the only check is the self-review "skim each
   requirement" in writing-plans.
5. **The phases outside coding are missing.** Product brief, requirements,
   architecture, walking skeleton and CI, hardening and release have no home.
6. **The builder grades its own milestone.** Nothing independent checks
   requirements against evidence at a milestone boundary.
7. **New sessions start blind.** The SessionStart hook injects routing rules,
   not the project's position.

Prior art (BMAD Method's readiness gate and `sprint-status.yaml`, GSD's
`REQUIREMENTS.md`/`ROADMAP.md`/`STATE.md` and milestone audit, Spec Kit's
`/speckit.analyze`) converges on one pattern: requirements with stable
identifiers, a machine-readable roadmap mapping them to phases, a mechanical
coverage check, and an explicit audit to close a phase. dr-superpowers already
has the identifiers and the coverage check (registers and `**Items:**`). This
design adds the roadmap layer and the audit.

## 2. Decisions fixed here

- It ships inside dr-superpowers, not as a new plugin: every seam it fixes
  (brainstorming, writing-plans, `next-step`, `repo-audit`, project-status,
  finishing, the hook) belongs to this plugin.
- The roadmap reuses registers at every level below it. Only the top file and
  its script are new.
- A milestone's state is computed from its registers. The only stored state is
  `closed`, and only `scripts/roadmap close` writes it, after an audit.
- Milestones close in order. A later milestone cannot close while an earlier
  one is open.
- A project without `docs/superpowers/roadmap.md` behaves exactly as before.

## 3. The hierarchy

```
docs/superpowers/roadmap.md               milestones in order
  docs/superpowers/registers/<m-reg>.md   one register per milestone; rows are
                                          epics, Assigned = the epic's spec
    docs/superpowers/registers/<e-reg>.md one register per epic spec (Covers =
                                          that spec); rows are requirements,
                                          Assigned = the plan that builds them
      plan tasks                          cite requirement rows on **Items:**
```

An epic row is resolved only when its own state is resolved. A milestone is
**ready to close** when every row of its register is resolved and, for every
epic row assigned to an existing spec, every register covering that spec has no
unresolved row. A `done` epic whose spec register still has open rows is an
inconsistency that `roadmap check` reports and `close` refuses.

## 4. `docs/superpowers/roadmap.md`

```markdown
# <Product> — roadmap

**Product:** <one sentence>
**Spec:** docs/superpowers/specs/<date>-<product>-design.md
**Non-goals:** <comma-separated, or ->

| M | Name | Exit criteria | Register | State | Note |
|---|---|---|---|---|---|
| M0 | Discovery | brief, users, non-goals and requirements approved | docs/superpowers/registers/<date>-m0-discovery.md | closed | audit 2026-10-09: 4 MET |
| M1 | Foundations | architecture decided, walking skeleton deployed, CI and gates.md green | docs/superpowers/registers/<date>-m1-foundations.md | open | - |
```

- `M` is `M` followed by an integer; identifiers are unique and ascending.
- `Register` is a repository-relative path to a register that passes
  `register check`.
- `State` is `open` or `closed`. `closed` needs a note (the audit summary).
- The table uses the register cell grammar: six cells, `\|` for a literal pipe,
  fenced rows ignored.

### Default greenfield milestones

| M | Name | Exit criteria |
|---|---|---|
| M0 | Discovery | product brief, users, non-goals and the requirement list approved |
| M1 | Foundations | architecture decisions recorded, walking skeleton deployed end to end, CI and `gates.md` green |
| M2..k | Feature milestones (MVP, Beta, ...) | every epic resolved, gates green |
| Mh | Hardening | security review, performance budget, accessibility, documentation |
| Mr | Release | deployment, runbook, versioning, handover |

The owner edits the list at kickoff. M0 and M1 are the phases that were missing:
requirements and an architecture skeleton exist before features start.

## 5. `scripts/roadmap`

Sourced parsing lives in `scripts/lib/roadmap.sh` so every reader agrees.

```
roadmap check  [--root DIR]
roadmap status [--root DIR] [--line]
roadmap open   [--root DIR] [M<n>]
roadmap add    [--root DIR] NAME --exit TEXT --register PATH
roadmap close  [--root DIR] M<n> --note TEXT
roadmap reopen [--root DIR] M<n> --note TEXT
roadmap settle [--root DIR] --spec SPEC
```

- **check** validates the header (`Product`, `Spec`), the table, each register
  path (and runs `register check` on it), identifiers, states, notes, the
  close order, and that no closed milestone has unresolved rows below it. Exit
  0 clean, 1 errors, 2 usage or no roadmap.
- **status** prints one line per milestone, `M2 Beta — open — 3 of 5 epics
  resolved; open: #4 Billing (doing), #5 Search (open)`, then
  `Current: M2 Beta` (the first open milestone) or `Current: none — every
  milestone is closed`. `--line` prints only the one-line summary the hook
  injects. Exit 0.
- **open** lists every unresolved row below a milestone (the current one when
  none is named): the milestone register's rows, then each epic spec's register
  rows. Exit 1 while any remain, 0 when the milestone is ready to close.
- **add** appends a milestone with the next identifier.
- **close** refuses (exit 1) while `open` reports anything, while an earlier
  milestone is open, or without `--note`; otherwise writes `closed` and the
  note. It is the only writer of `closed`.
- **reopen** sets a closed milestone back to `open` with a note, for an audit
  that turns out wrong after the fact.
- **settle** is called after an epic's plan is integrated: for every milestone
  register row assigned to SPEC, when no register covering SPEC has an
  unresolved row, it sets the row to `verify` with the note `built; owner
  confirms at the milestone audit`. Rows already resolved are left alone. It
  never writes `done`.

## 6. Skills

### `planning-a-product` (new)

Triggered when the project is new or the request names several subsystems;
brainstorming's scope check routes there instead of decomposing in prose. It
runs the discovery interview one question at a time, writes the product spec
(vision, users, non-goals, requirements, epics, milestones), creates
`roadmap.md` and one register per milestone with every epic as a row, checks
them with `roadmap check`, and gets owner approval. The M0 register's rows are
the discovery deliverables, so M0 closes through the same audit as any other.
Each epic then runs the normal cycle: brainstorming, writing-plans, execution,
finishing.

### `closing-a-milestone` (new)

Triggered when `roadmap open` exits 0 for the current milestone, or when anyone
says a phase or milestone is done. It runs `roadmap open` (stop if anything is
listed), runs `running-gates` when `gates.md` exists, then dispatches a fresh
`judge-opus` with the milestone's exit criteria and every requirement row below
it. The judge returns, per row, `MET` with evidence (a file, a test, a gate
result) or `GAP`. Any GAP is written back with `register set … open --note`,
and the close stops. With no GAP, the skill presents the verdict; on the
owner's approval it sets the `verify` epic rows to `done` and runs
`roadmap close` with the audit summary as the note.

### Changes to existing skills

- **using-superpowers**: routing rows for "Starting a new product or a
  multi-subsystem project" and "A phase or milestone looks finished".
- **brainstorming**: a new product or several subsystems routes to
  planning-a-product. When the roadmap names this spec on an epic row, opening
  the spec's requirement register is required even when the request was one
  sentence.
- **writing-plans**: a plan whose spec is an epic on the roadmap omits the
  Program line; the roadmap supplies what comes next.
- **finishing-a-development-branch**: after integration, run
  `roadmap settle --spec <the plan's Spec>` when a roadmap exists, and name the
  milestone in the "After integration" line.
- **project-status**: reads `roadmap status`; a new Milestone section; a new
  rule after the register rule: the current milestone is ready to close, so the
  next step is closing-a-milestone.

## 7. Scripts that read the roadmap

- **next-step --complete**: when a roadmap exists, the current milestone's
  register joins the registers the plan's specs resolve, so an open epic row
  routes by its `Assigned` cell exactly as a register row does today. When no
  row is open and the current milestone is ready to close, the next step is
  closing-a-milestone; when every milestone is closed, it says so. The roadmap
  outranks the Program line, and an open register row outranks both.
- **repo-audit**: a `## Roadmap` section with `roadmap status`'s lines.
- **session-start.sh**: when the session's repository has a roadmap, append
  `roadmap status --line` to the injected context, so a fresh or compacted
  session knows the position. Failure to compute it injects nothing extra.

## 8. Out of scope

Time estimates, sprints and velocity: they add bookkeeping without preventing
the failure. Retrofitting a roadmap onto an existing project works with the same
commands but is not designed for here. `plan-lint` is unchanged: requirement
coverage is already enforced through registers and `**Items:**`.

## 9. Verification

- `tests/roadmap.test.sh`: every verb, against a temporary repository.
- `tests/next-step.test.sh`: a roadmap project routes to the next epic, to
  closing-a-milestone, and to "every milestone is closed".
- `tests/repo-audit.test.sh` and `tests/hook.test.sh`: the roadmap section and
  the injected line, and their absence without a roadmap.
- `tests/project-status.test.sh`: the new rule and section are present.
