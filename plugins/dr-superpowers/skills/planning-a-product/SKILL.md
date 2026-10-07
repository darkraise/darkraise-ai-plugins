---
name: planning-a-product
description: Use when starting a new product or project from scratch, or when a request names several subsystems - runs discovery, then writes the product spec, the milestone roadmap and one register per milestone so no epic can be lost
---

# Planning a Product

**Announce at start:** "I'm using the planning-a-product skill to set up the roadmap before any feature work."

A greenfield project spans many specs and many sessions. What goes missing is
not code but whole epics: they were decided in a conversation, written as prose
in one spec, and forgotten when a later session declared the phase done. This
skill puts every milestone and every epic into files that scripts check, before
the first feature is designed. See [project-state.md](../../reference/project-state.md)
and the roadmap format in [roadmap.md](references/roadmap.md).

<HARD-GATE>
Write no feature spec, plan or code until your human partner has approved the
product spec and `scripts/roadmap check` reports `0 errors`.
</HARD-GATE>

## When this applies

- The repository is empty or a skeleton, and the request is a product, an app,
  a service or a tool rather than a change to one.
- Or the request names several independent subsystems ("chat, file storage,
  billing and analytics"). dr-superpowers:brainstorming's scope check sends
  these here instead of decomposing them in prose.

A project that already has `docs/superpowers/roadmap.md` does not come here:
the roadmap exists, and new work is an epic row (see Changing the roadmap).

## Steps

1. **Orient.** Run `scripts/repo-audit`. Read
   `docs/superpowers/distilled/constraints.md` and `rejected.md` when present.
2. **Discovery interview (M0).** One question per message, multiple choice when
   possible, as in brainstorming. Cover, in order: the problem and who has it;
   the users and their top tasks; what success looks like, measurably; the
   non-goals; hard constraints (platform, stack, budget, compliance, data);
   and the release target. Stop asking when each of those has an answer your
   human partner has confirmed.
3. **Requirements.** Write the requirement list as numbered statements a test
   or a demo can check. Every requirement belongs to exactly one epic.
4. **Epics and milestones.** Group requirements into epics (an epic is one
   spec, one or more plans, independently demonstrable). Order epics into
   milestones, starting from the default template in
   [roadmap.md](references/roadmap.md): M0 Discovery, M1 Foundations,
   feature milestones, Hardening, Release. Propose it; your human partner edits
   it.
5. **Write the product spec** to
   `docs/superpowers/specs/YYYY-MM-DD-<product>-design.md`: problem, users,
   success measures, non-goals, constraints, the requirement list, the epics
   (each naming its requirements by number), the milestones with their exit
   criteria, and the architecture direction known so far.
6. **Write one register per milestone** at
   `docs/superpowers/registers/YYYY-MM-DD-m<n>-<slug>.md`, with
   `**Source:** roadmap` and `**Covers:**` the product spec. Add each epic as a
   row with `scripts/register add <file> "<epic title>" --assigned "<epic title>"
   --acceptance "<the requirement numbers it carries>"`. The label in Assigned
   is replaced by the epic's spec path once that spec exists. M0's rows are the
   discovery deliverables (brief, requirements, non-goals approved) and M1's
   include the walking skeleton, CI and `gates.md`.
7. **Write `docs/superpowers/roadmap.md`** from the template, one table row per
   milestone, every one `open`. Run `scripts/roadmap check` until it reports
   `0 errors`, and `scripts/roadmap status`.
8. **Review.** Self-review once, inline: every requirement is in exactly one
   epic; every epic is a row in exactly one milestone register; every milestone
   has exit criteria a reviewer could check; nothing from the interview is
   missing. Post `Self-review (round 1 of 1):` with one line per item.
9. **Approval.** Present the spec path and `roadmap status`. On approval, commit
   the spec, the registers and the roadmap together. Set each M0 row your human
   partner approved to `done` with `scripts/register set`, close M0 through
   dr-superpowers:closing-a-milestone, and end with
   `scripts/next-step --draft <product spec> --next "Brainstorm the first M1 epic with dr-superpowers:brainstorming"`.

## After this skill

Each epic runs the normal cycle: dr-superpowers:brainstorming writes its spec
and opens its requirement register (required for every epic on the roadmap,
even when the request was one sentence), dr-superpowers:writing-plans plans it,
the plan's execution skill builds it, and
dr-superpowers:finishing-a-development-branch runs `scripts/roadmap settle`,
which moves the epic row to `verify` once its requirements are resolved. A
milestone closes only through dr-superpowers:closing-a-milestone.

## Changing the roadmap

Scope changes are rows, never silent edits:

- **A new epic:** `scripts/register add <milestone register> "<title>" --assigned "<title>"`.
- **A dropped or postponed epic:** `scripts/register set <file> <id> deferred --note "<owner's ruling>"`,
  and add it to a later milestone's register when it is postponed rather than dropped.
- **A new milestone:** `scripts/roadmap add "<name>" --exit "<criteria>" --register <path>`.
- **A milestone closed wrongly:** `scripts/roadmap reopen M<n> --note "<why>"`.

Only `scripts/register` and `scripts/roadmap` write these files.

## Red Flags

| Thought | Reality |
|---------|---------|
| "The user just wants the app; skip discovery" | M0 is short. Skipping it is how requirements end up invented mid-build. |
| "I'll list the epics in the spec, that's enough" | Prose in a spec is the failure this skill exists for. Every epic is a register row. |
| "Foundations can come later" | M1 is where CI, gates and the walking skeleton make every later "done" checkable. |
| "This epic is small, I'll fold it into another" | Fold it explicitly: one row deferred with a note naming where it went. |
| "I'll edit the roadmap table by hand" | Only the scripts write it; `roadmap check` rejects a hand-closed milestone. |
