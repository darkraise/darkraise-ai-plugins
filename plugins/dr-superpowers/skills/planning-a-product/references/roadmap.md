# The roadmap format

`docs/superpowers/roadmap.md` lists a greenfield project's milestones in order.
`scripts/roadmap` reads and writes it; `scripts/register` writes the registers it
points at.

## Template

````markdown
# <Product> — roadmap

**Product:** <one sentence: who it is for and what it does>
**Spec:** docs/superpowers/specs/YYYY-MM-DD-<product>-design.md
**Non-goals:** <comma-separated, or ->

| M | Name | Exit criteria | Register | State | Note |
|---|---|---|---|---|---|
| M0 | Discovery | brief, users, non-goals and requirement list approved | docs/superpowers/registers/YYYY-MM-DD-m0-discovery.md | open | - |
| M1 | Foundations | architecture decided, walking skeleton deployed end to end, CI and gates.md green | docs/superpowers/registers/YYYY-MM-DD-m1-foundations.md | open | - |
| M2 | MVP | every MVP epic resolved, gates green | docs/superpowers/registers/YYYY-MM-DD-m2-mvp.md | open | - |
| M3 | Hardening | security review, performance budget, accessibility, documentation | docs/superpowers/registers/YYYY-MM-DD-m3-hardening.md | open | - |
| M4 | Release | deployed, runbook, versioning, handover | docs/superpowers/registers/YYYY-MM-DD-m4-release.md | open | - |
````

## Rules

- `M` is `M` and a number, unique and ascending. Six cells per row; write a
  literal pipe as `\|`. Rows inside a fenced block are ignored.
- `Register` is a repository-relative path to an item register whose
  `**Covers:**` is the product spec. Each row of it is one epic; its Assigned
  cell holds the epic's title until the epic's spec exists, then that spec's
  path.
- `State` is `open` or `closed`. Only `scripts/roadmap close` writes `closed`,
  and only with a note: the audit summary.
- A milestone's progress is never stored. `scripts/roadmap status` computes it
  from the milestone register and from every register covering an epic's spec.

## What each default milestone holds

| Milestone | Typical epic rows |
|---|---|
| M0 Discovery | product brief approved; requirement list approved; non-goals approved |
| M1 Foundations | architecture decisions recorded; repository and tooling; walking skeleton deployed end to end; CI running; `docs/superpowers/gates.md` declared |
| Feature milestones | one row per epic |
| Hardening | security review; performance budget met; accessibility; error handling and observability; user and developer documentation |
| Release | deployment and rollback; runbook; versioning and changelog; handover |

## Commands

```
scripts/roadmap check                      validate the roadmap and its registers
scripts/roadmap status [--line]            progress per milestone, and the current one
scripts/roadmap open [M<n>]                every unresolved row below a milestone; exit 1 while any
scripts/roadmap add NAME --exit TEXT --register PATH
scripts/roadmap close M<n> --note TEXT     refuses while rows are open or an earlier milestone is open
scripts/roadmap reopen M<n> --note TEXT
scripts/roadmap settle --spec SPEC         epic rows assigned to SPEC go to verify once its registers are resolved
```
