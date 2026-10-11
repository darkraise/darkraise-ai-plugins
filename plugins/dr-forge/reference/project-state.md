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

## Where `<state>` and `<docs>` are

`<state>` and `<docs>` are repository-relative names: `<state>` is `.forge/` and
`<docs>` is `docs/forge/`, except in a repository that
has `.superpowers/` or `docs/superpowers/` and not the new directory: there the
old one stays in use, for writing as well as reading, so a pre-2.0 checkout never
splits across both. Every script resolves its paths through
`scripts/lib/forge-dir.sh`; a skill resolves them with
`bash <plugin-root>/scripts/forge-path state|docs [RELATIVE]` before it reads or
writes, never by spelling either path.

`forge-path` prints the absolute path in the checkout it runs in. For a path
written under another root, such as `<primary checkout>/<state>/…` or
`<worktree>/<state>/…`, run it from that root:
`(cd "<root>" && bash <plugin-root>/scripts/forge-path state handoff/latest.md)`.
Where the path is written into a file or onto a command line (a roadmap `Spec`
or `Register` cell, `.gitattributes`, a script argument), write the
repository-relative form: the resolved path minus the checkout's root.
