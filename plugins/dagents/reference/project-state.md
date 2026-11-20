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
  reviews/               one review record per finished plan
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
- `<docs>/reviews/*.md`
- `<docs>/roadmap.md`
- `<docs>/distilled/constraints.md`
- `<docs>/distilled/gotchas.md`
- `<docs>/distilled/reference.md`
- `<docs>/distilled/rejected.md`

## Who writes what

| File | Written by | Read by |
|---|---|---|
| `gates.md` | a human, or dagents:running-gates' bootstrap on approval | dagents:running-gates |
| `plans/completed.md` | dagents:finishing-a-development-branch | dagents:project-status |
| `registers/*.md` | dagents:brainstorming, dagents:writing-plans, both execution skills, dagents:finishing-a-development-branch — all through `scripts/register` | `scripts/next-step`, `scripts/plan-lint`, `scripts/repo-audit`, dagents:project-status, dagents:brainstorming |
| `reviews/*.md` | dagents:finishing-a-development-branch, through `scripts/review-record` | dagents:closing-a-milestone, and a person weighing review depth |
| `roadmap.md` | dagents:planning-a-product and dagents:closing-a-milestone, through `scripts/roadmap` | `scripts/next-step`, `scripts/repo-audit`, the SessionStart hook, dagents:project-status, dagents:brainstorming, dagents:finishing-a-development-branch |
| `distilled/*.md` | dagents:distilling-docs, or a human recording an approved spec's owner decision | dagents:project-status, dagents:brainstorming, dagents:resume-execution, both execution skills; `constraints.md` also dagents:writing-plans |

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

`distilled/*.md` are written only by dagents:distilling-docs, with one
exception: a human may add an entry that an approved spec's owner decisions
name, citing that spec as its `Source`. distilling-docs deletes sources under
its own rules and never touches a spec, a plan, `completed.md`, or anything
outside `<docs>/notes/` and `<docs>/findings/`. `gates.md`
is edited by a human or by an approved bootstrap, never silently.
`completed.md` is append-only. `reviews/*.md` is written only by
`scripts/review-record`, one file per plan; nothing deletes it, and
dagents:distilling-docs never touches it.

## Where `<state>`, `<docs>`, `<ledger dir>` and `<handoff>` are

`<state>` is `.dagents/` and `<docs>` is `docs/dagents/`. A repository that still
has a pre-3.0 directory is moved with `bash <plugin-root>/scripts/dagents-migrate`
first; session start and `scripts/repo-audit` name what it still has.

All four are in the checkout:

| Token | Path |
|---|---|
| `<docs>` | `<worktree>/docs/dagents` |
| `<ledger dir>` | `<worktree>/<state>/sdd/<plan-basename>` |
| `<handoff>` | `<checkout>/<state>/handoff/<key>.md` |

Each piece of work has its own `<handoff>`, named by its key: the plan's or
the design draft's basename, or `adhoc-<the first 8 characters of the session
id>` for unplanned work and for a block written with no plan in hand
(`--project`). `scripts/next-step` writes it in the checkout the next session
works in: for a plan in flight, the worktree holding its ledger; once the plan
is complete, the primary's; otherwise the checkout it runs in. Writing a key
deletes that key's handoff in every other checkout, so one copy remains. Its
first prompt opens by naming that checkout and that file.
`scripts/repo-audit` lists every checkout's handoffs and removes the finished
ones; `bash <plugin-root>/scripts/handoff list` lists them with their claims.

A handoff's notes are written first to `<checkout>/<state>/handoff/notes/<key>.md`
in the session's own checkout, and `next-step --notes` moves them into the
handoff and deletes the notes file.

**Claims.** A session that resumes a handoff claims it before anything else:
`bash <plugin-root>/scripts/handoff claim <handoff>` writes
`<primary>/<state>/handoff/claims/<key>`, one claim for the repository
whichever checkout holds the file. Exit 3 means another live session holds
it: stop and ask. `scripts/next-step` refuses with exit 7 to write a key
another live session holds, and releases this session's claim once it writes.
In an auto run both scripts stop the run themselves before they exit. When
this session claimed one handoff and writes another key with `--notes`, the
claimed handoff is consumed (deleted), unless it is a plan or design draft
still in progress; an `adhoc-` handoff is deleted only that way.

Claims have limits:

- A claim belongs to the session id that took it (`CLAUDE_CODE_SESSION_ID`).
  `/clear` starts a new id, and `/resume` takes back the resumed
  conversation's own id, so a claim taken under one id reads as another
  session's until that session reads as gone.
- A session reads as gone when its cockpit heartbeat is older than
  `AR_BEAT_SECONDS`, or, with no heartbeat, when its transcript has gone
  unwritten for `AR_STALE_MINUTES`; a quiet session without the cockpit can
  lose its claim to the next `handoff claim`.
- Codex has no session id: it claims nothing, and its unplanned handoff keeps
  one file only through the `--key` its first prompt names.
- Claims are local to one machine.
- Two sessions deliberately working one plan share its ledger and branch; the
  claim refusal is the only guard.

A plan's workspace (`scripts/sdd-workspace`: briefs, reports, review
packages) is in the checkout too. A plan's ledger is
`<ledger dir>/progress.md`, its handoff note `<ledger dir>/handoff.md` and
its amendments `<ledger dir>/amendments.md`.

Every script resolves these through `scripts/lib/roots.sh`; a skill resolves
them with `bash <plugin-root>/scripts/dagents-path state|docs [RELATIVE] | ledger <plan-basename> | handoff <next-step mode arguments>`
before it reads or writes, never by spelling a path. `dagents-path` answers for
the checkout it runs in; for a path written under another root, such as
`<worktree>/<state>/…`, run it from that root:
`(cd "<root>" && bash <plugin-root>/scripts/dagents-path state sdd)`.

Where a path is written into a file or onto a command line (a ledger's
identity line, a roadmap `Spec` or `Register` cell, a `**Spec:**` line,
`.gitattributes`, a script argument), write its name:
`bash <plugin-root>/scripts/dagents-path name <path>`. A document's name is
`docs/dagents/<rest>` (a name written before 3.0.0 as
`docs/superpowers/<rest>` still means it); every script accepts a name where
it takes a path.

## Durable facts

At each `Task <N>: complete` line and at handoff, record the durable facts
the work established (decisions and their reasons, root causes and fixes,
constraints), one fact per entry: append each as one bullet to
`<docs>/notes/<YYYY-MM-DD>-facts.md` and commit it in a `docs(notes): …`
commit of its own: dagents:distilling-docs absorbs only tracked, clean notes.
Ledger lines, progress and commit hashes stay in the work log.
