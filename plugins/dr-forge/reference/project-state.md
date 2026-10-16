# Project-declared state

A project tells a session three kinds of thing through its repository. Specs and
plans under `<docs>/` are authored and permanent — the record of what
was intended. `<state>/` is generated, gitignored and disposable — the state
of a run in flight. This document describes the third kind: small committed
documents that state facts about the project a session cannot derive from the
code.

```
<docs>/
  specs/                 authored, permanent, never deleted by a skill
  plans/                 authored, permanent, never deleted by a skill
    completed.md         append-only index of merged plans
  registers/             one file per incoming list of source items
  roadmap.md             greenfield milestones in order, each with a register
  gates.md               what proves a change works here, in order
  distilled/
    constraints.md       owner rulings, do-nots, fixed policy
    gotchas.md           tooling and environment traps, symptom first
    reference.md         measured facts, formats, corpus numbers
    rejected.md          approaches tried and abandoned, and why
```

Every one of these is optional, and none of them is an error when absent. A
project with none of them loses nothing: each skill that reads one states what
it does without it.

## The files, by full path

- `<docs>/gates.md`
- `<docs>/plans/completed.md`
- `<docs>/registers/*.md`
- `<docs>/roadmap.md`
- `<docs>/distilled/constraints.md`
- `<docs>/distilled/gotchas.md`
- `<docs>/distilled/reference.md`
- `<docs>/distilled/rejected.md`

## Who writes what

| File | Written by | Read by |
|---|---|---|
| `gates.md` | a human, or dr-forge:running-gates' bootstrap on approval | dr-forge:running-gates |
| `plans/completed.md` | dr-forge:finishing-a-development-branch | dr-forge:project-status |
| `registers/*.md` | dr-forge:brainstorming, dr-forge:writing-plans, both execution skills, dr-forge:finishing-a-development-branch — all through `scripts/register` | `scripts/next-step`, `scripts/plan-lint`, `scripts/repo-audit`, dr-forge:project-status, dr-forge:brainstorming |
| `roadmap.md` | dr-forge:planning-a-product and dr-forge:closing-a-milestone, through `scripts/roadmap` | `scripts/next-step`, `scripts/repo-audit`, the SessionStart hook, dr-forge:project-status, dr-forge:brainstorming, dr-forge:finishing-a-development-branch |
| `distilled/*.md` | dr-forge:distilling-docs, or a human recording an approved spec's owner decision | dr-forge:project-status, dr-forge:brainstorming, dr-forge:resume-execution, both execution skills; `constraints.md` also dr-forge:writing-plans |

## Precedence

When two sources disagree, this order settles it:

1. `CLAUDE.md`, `AGENTS.md`, and anything your human partner says directly.
2. `handoff.md`'s owner constraints, for the run in flight.
3. `distilled/constraints.md` — which binds like those constraints and yields to
   them wherever both speak.
4. A spec.
5. A fact in `distilled/reference.md`.

A skill that acts on the losing side of that order has made an error, not a
judgment call.

## What never happens to these files

`distilled/*.md` are written only by dr-forge:distilling-docs, with one
exception: a human may add an entry that an approved spec's owner decisions
name, citing that spec as its `Source`. distilling-docs deletes sources under
its own rules and never touches a spec, a plan, `completed.md`, or anything
outside `<docs>/notes/` and `<docs>/findings/`. `gates.md`
is edited by a human or by an approved bootstrap, never silently.
`completed.md` is append-only.

## Where `<state>`, `<docs>`, `<ledger dir>` and `<latest.md>` are

`<state>` is `.forge/` and `<docs>` is `docs/forge/`. A repository that still
has a pre-3.0 directory is moved with `bash <plugin-root>/scripts/forge-migrate`
first; session start and `scripts/repo-audit` name what it still has.

darkmem is off unless the `darkmemEnabled` setting is on. A repository mapped
to darkmem while it is on may keep each family in the darkmem mirror instead
(`documentStore`, `progressSource`; `bash <plugin-root>/scripts/forge-path store`
prints which). Turned off or unmapped, both families belong in the checkout:
a family still in the mirror is read there until the reconcile of a session
start with no plan in progress copies it back from the mirror, without asking
darkmem.

| Token | Local | darkmem |
|---|---|---|
| `<docs>` | `<worktree>/docs/forge` | `~/.dr-forge/mirror/<project>/forge` |
| `<ledger dir>` | `<worktree>/<state>/sdd/<plan-basename>` | `~/.dr-forge/mirror/<project>/work/sdd/<plan-basename>` |
| `<latest.md>` | `<primary checkout>/<state>/handoff/latest.md` | `~/.dr-forge/mirror/<project>/work/handoff/latest.md` |

`<state>` and a plan's workspace (`scripts/sdd-workspace`: briefs, reports,
review packages, `amendments.md`) stay in the checkout either way. A plan's
ledger is `<ledger dir>/progress.md` and its handoff note
`<ledger dir>/handoff.md`.

Every script resolves these through `scripts/lib/roots.sh`; a skill resolves
them with `bash <plugin-root>/scripts/forge-path state|docs [RELATIVE] | ledger <plan-basename> | latest`
before it reads or writes, never by spelling a path. `forge-path` answers for
the checkout it runs in; for a path written under another root, such as
`<worktree>/<state>/…`, run it from that root:
`(cd "<root>" && bash <plugin-root>/scripts/forge-path state sdd)`.

Where a path is written into a file or onto a command line (a ledger's
identity line, a roadmap `Spec` or `Register` cell, a `**Spec:**` line,
`.gitattributes`, a script argument), write its name:
`bash <plugin-root>/scripts/forge-path name <path>`. A document's name is
`docs/forge/<rest>` in both stores (a name written before 3.0.0 as
`docs/superpowers/<rest>` still means it), so a ledger in darkmem can name a
plan in the checkout and the reverse; every script accepts a name where it
takes a path.

While `forge-path store` prints `documents darkmem`, a step that commits a
spec, plan, register, roadmap or `completed.md` line runs
`bash <plugin-root>/scripts/darkmem-sync push` instead. Code commits are
unchanged.

## darkmem sync points

Run `bash <plugin-root>/scripts/darkmem-sync push` at each stop point: after
every `Task <N>: complete` and fix-round ledger line, after a spec or plan is
saved, and at handoff once `scripts/next-step` has written `<latest.md>`. In a
repository that is not mapped to darkmem, or while darkmem is off, it prints
one line and exits 0, so no check comes first. On Claude Code the SessionStart hook runs `darkmem-sync reconcile`, then `pull`,
and the Stop hook pushes as a safety net. Codex has no hooks, so there these
steps and the session-start step in
`skills/using-forge/references/codex-tools.md` are the only triggers.

**Promotion to memory.** At each `Task <N>: complete` line and at handoff,
record the durable facts the work established (decisions and their reasons,
root causes and fixes, constraints), one fact per entry. When
`forge-path project` prints a project (darkmem is on and the repository
mapped) and the darkmem MCP tools are available, file each with `memory_add`,
tagged `project/<project>`. Otherwise append each as one bullet to
`<docs>/notes/<YYYY-MM-DD>-facts.md`, which dr-forge:distilling-docs later
absorbs. Ledger lines, progress and commit hashes stay in the work log either
way.
