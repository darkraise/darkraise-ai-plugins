# Project-declared state

A project tells a session three kinds of thing through its repository. Specs and
plans under `docs/superpowers/` are authored and permanent — the record of what
was intended. `.superpowers/` is generated, gitignored and disposable — the state
of a run in flight. This document describes the third kind: small committed
documents that state facts about the project a session cannot derive from the
code.

```
docs/superpowers/
  specs/                 authored, permanent, never deleted by a skill
  plans/                 authored, permanent, never deleted by a skill
    completed.md         append-only index of merged plans
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

- `docs/superpowers/gates.md`
- `docs/superpowers/plans/completed.md`
- `docs/superpowers/distilled/constraints.md`
- `docs/superpowers/distilled/gotchas.md`
- `docs/superpowers/distilled/reference.md`
- `docs/superpowers/distilled/rejected.md`

## Who writes what

| File | Written by | Read by |
|---|---|---|
| `gates.md` | a human, or dr-superpowers:running-gates' bootstrap on approval | dr-superpowers:running-gates |
| `plans/completed.md` | dr-superpowers:finishing-a-development-branch | dr-superpowers:project-status |
| `distilled/*.md` | dr-superpowers:distilling-docs | dr-superpowers:project-status, dr-superpowers:brainstorming, dr-superpowers:resume-execution, both execution skills |

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

`distilled/*.md` are written only by dr-superpowers:distilling-docs, which
deletes sources under its own rules and never touches a spec, a plan,
`completed.md`, or anything outside `docs/superpowers/notes/` and
`docs/superpowers/findings/`. `gates.md` is edited by a human or by an approved
bootstrap, never silently. `completed.md` is append-only.
