---
name: ui-ux
description: Use when work touches anything a user sees or does - designing, building or changing screens, components, flows, forms, copy, styling, layout, interaction, accessibility or responsive behaviour, turning a mockup or design into code, or fixing a bug whose fix changes the UI - writes a UI/UX contract, carries it into every UI task, and proves it in the running UI before the work counts as done.
---

# UI/UX

## Overview

A mockup shows one state of one path. What is not drawn is not built: the
states, the flows, the feedback, the copy, the responsive changes, the
accessibility and the budgets fall away, and the build copies the layout.
This skill turns the design into a numbered contract, carries every item to
the task that builds it, and proves each one in the running UI.

**Core principle:** UI work is done when `ui-proof check` passes, not when it
looks right in one screenshot.

This skill owns the process. Aesthetic direction comes from the
frontend-design skill when it is installed, components and tokens from the
project's design system (for example darkraise-ui); call on them, and do not
restate them here.

## The Iron Law

```
NO UI WORK IS DONE WITHOUT A PASSING ui-proof check
```

The final review, finishing and every "done" claim run it. On Claude Code a
Stop hook holds a turn that leaves UI changes unproven.

## Depth

State one line before anything else:

`**UI/UX depth:** <touch|feature|product> — <why>`

| Depth | When | What it takes |
|---|---|---|
| touch | a bug fix, a copy or styling change, one surface | a `## Delta` of 5 to 15 items in the proof report, a proof of that surface, the judge-sonnet-high seat |
| feature | a new or changed flow or screen | a `## UI/UX contract` section in the spec, a walkthrough of every flow it touches, the judge-opus seat |
| product | a new product or surface family | the feature depth plus the profile's design decisions, written or extended |

## The project UI profile

Read `<docs>/ui-ux/profile.md` before any UI task
(`bash <plugin-root>/scripts/dforge-path docs ui-ux/profile.md` prints its
path). When it does not exist, create it from
[contract-template.md](references/contract-template.md) §Profile, asking the
user for what the repository cannot tell you: who uses the product, the
platform and how to launch it, the viewports and themes. Its existence turns
the gate on for the project.

## Shape

Run before acceptance statements are drafted (from dforge:brainstorming) and
before the fix (from dforge:systematic-debugging, at touch depth).

1. Read the profile, or create it.
2. Write the contract (feature, product) or the delta (touch) from
   [contract-template.md](references/contract-template.md), walking
   [state-catalogue.md](references/state-catalogue.md) for every surface and
   [interaction-rules.md](references/interaction-rules.md) for every control.
3. Ask the user whether to build state boards: every state of each screen
   side by side, annotated with contract IDs, built from the project's real
   components where the platform allows. Ask at every depth; recommend yes at
   feature and product depth and no at touch depth.
4. Define the worst-case dataset the proof will use
   ([state-catalogue.md](references/state-catalogue.md) §Worst-case data).

Under `autoRun=on`, brainstorming asks nothing after its clarifying
questions: ask the profile and state-board questions among them, and quote
the answers in the spec's `## Decisions`.

Every contract item becomes one or more acceptance statements whose text
starts with its ID, for example `A12. [test, high] UX-4: Escape closes the
dialog and returns focus to its trigger.` A behaviour statement is tagged
`test` when the profile names a UI test runner the project can run, and
is tagged `demo` when the profile names no UI test runner. Either way, its
proof-report row proves it.

## Carry

- **The plan.** Every task whose files match `ui-proof paths` carries a
  `**UI/UX:**` line naming the contract IDs it delivers, and every `UI-` and
  `UX-` ID reaches some task. `scripts/plan-lint` enforces both.
- **The brief.** `scripts/task-brief` appends the cited items verbatim under
  `## UI/UX contract items`.
- **The implementer** renders its work through the profile's harness before
  reporting, and maps each cited ID to a screenshot path or a test name.

## Prove

Follow [walkthrough.md](references/walkthrough.md): launch through the
platform guide, seed the worst-case data, walk every flow by pointer and by
keyboard at every viewport and theme, force every state, run the automated
checks, screenshot each item, write the proof report, stamp it with
`ui-proof stamp`, and have the judge seat review it. Run the walkthrough in
the session or an implementer seat: judge seats have no browser.

## The gate

```bash
bash <plugin-root>/scripts/ui-proof check --base <ref> [--spec <spec>]
```

That is `scripts/ui-proof check --base <ref> [--spec <spec>]`, where `<ref>`
is the commit the work started from: the final review and finishing pass
`MERGE_BASE` and the plan's spec, a "done" claim passes the branch's base.
Exit 1 names each failed step; fix the UI or the proof, never the check.

An `unverifiable` row (no harness for the platform on this host; macOS and
iOS are not supported) passes only with an `**Accepted by:**` line quoting the
user. Never write `**Accepted by:**` unless the user said, in this
conversation, that they accept the item unproven, and quote their words.

When the proof cannot happen in this turn, end the message with the line
`UI proof: pending — <why>`. It releases the Stop hook's hold and tells the
user the UI is unproven; it never satisfies the gate.

## Hooks and Codex

On Claude Code, after each edit to a UI file a hook returns `scripts/ui-lint`
findings and, once per session, names this skill; at each stop a hook holds a
turn whose UI changes have no passing proof, once (its retry passes). Codex
runs no hooks: run `bash <plugin-root>/scripts/ui-lint <files>` after UI
edits and `ui-proof check` before claiming done. Whether a Codex native
implementer can drive a browser is unverified.

## Red Flags

| Thought | Reality |
|---|---|
| "It matches the mockup" | The mockup is one state. Prove every state in the matrix. |
| "The states are obvious; I'll add them while building" | What is not in the contract is not built. Write the item first. |
| "One full-page screenshot shows it works" | A thumbnail hides the failures that matter. Screenshot each item and state. |
| "The demo data looks fine" | Demo data is chosen to look good. Prove with the worst-case data. |
| "Keyboard users are an edge case" | Walk every flow by keyboard alone. |
| "The judge will catch it" | The judge reads your evidence. Missing evidence is a fail. |
| "I'll mark it unverifiable" | Only the user can accept an unverifiable item. |
| "It's only a styling fix" | Touch depth still has a delta and a proof. |

## Quick Reference

| Command | Does |
|---|---|
| `ui-proof paths` | the globs that count as UI files |
| `ui-proof fingerprint` | the current UI fingerprint |
| `ui-proof contract <spec> [ID...]` | the contract's IDs, or the items verbatim |
| `ui-proof stamp <report>` | write the fingerprint; drop a stale judge line |
| `ui-proof check --base <ref> [--spec <spec>]` | the gate |
| `ui-lint <file>...` | high-precision UI defect patterns |
