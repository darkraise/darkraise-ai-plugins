# ui-ux demos

Run 2026-10-24 in the execution worktree.

## A20 — web walkthrough from an implementer subagent

- Page: `plugins/dforge/tests/fixtures/ui-ux/walkthrough.html` (served over `http://127.0.0.1:8765/walkthrough.html`: the browser refused `file://`; the server was killed afterwards)
- Keyboard walk at 375x812: pass (Tab lands on "Rename", Enter opens the dialog with focus on the name field, Escape closes it and focus returns to "Rename", each confirmed by the `[active]` marker); at 1440x900: pass, same steps
- Error state: pass at both viewports (an empty name and "Save name" shows "Enter a name of 1 to 64 characters." and focus stays on the field)
- Screenshots (git-ignored, under `.dforge/ui-ux/demo/`): `ux-1-375x812-light.png`, `ux-1-1440x900-light.png`, `ux-2-375x812-light-error.png`, `ux-2-1440x900-light-error.png`
- The subagent reported one browser console error on the first page load at 375x812 and did not read its text; the page has no favicon, which is the likely cause (unverified)

## A17 — terminal guide

- tmux 3.5a: new-session at 80x24, send-keys (a `select` menu, then `2`), wait for `picked beta`, capture at 80 columns, resize to 120x40, capture at 120 columns, kill-session — every command succeeded and `picked beta` appeared once in `terminal-80.ansi`. The guide's Status line now reads verified.

## Left for the owner

- A2 (a fresh session loads dforge:ui-ux when brainstorming a settings screen) and A3 (a UI bug fix states the touch depth line and writes a judged proof): need a fresh interactive session.
- A17, Windows half: run `plugins/dforge/skills/ui-ux/references/platforms/windows.md` on a Windows host and update its Status line.

## Validation

Run 2026-10-24 from the execution worktree.

- `node scripts/validate-repository.mjs`: exit 0.
- `node scripts/test-all.mjs`: exit 1. Every bash suite passed; the only failures are two cockpit tests in `plugins/dforge/tests/cockpit.test.ts`, "a Done held for background work > a subagent's approval after the turn does not stall the release" and "the shell ending under a subagent approval still releases once it is answered". They fail the same way on the plan's base commit (6df85ec4, checked in a throwaway worktree, since removed) and on three runs here, so this plan did not cause them and did not touch cockpit code. Not worked around.
- `claude plugin validate .` (marketplace) and `claude plugin validate plugins/<p>` for dforge, dr-status, darkraise-ui and darkraise-win32ui: all pass.
- `claude plugin test plugins/dforge`: 406 pass, 2 fail (the same two cockpit tests, on the branch and on the base commit).

## Pressure run

Two `general-purpose` Sonnet subagents, told to edit nothing and answer in under 400 words, were given the walkthrough fixture as an approved mockup to build as a production React component.

- Without the skill: the answer was careful. It built the dialog, the 1 to 64 validation, the focus return and the focus ring, asked for the real save call, and planned component tests and a browser check. It dropped: any contract or item IDs, a depth line, the states the mockup does not draw (pending save, failed save, success, collision), keyboard and focus-trap rules beyond the mockup, the viewports and themes to prove, copy, a worst-case dataset, and a done condition; its verification was "run lint and tests, compare with the mockup".
- With the skill, first run: it planned a contract, state boards, the walkthrough, the judge seat and `ui-proof check` as the done condition, and named the extra states. It missed two pass points as worded: it wrote "Depth: feature" and not the literal `**UI/UX depth:**` line, and it described items in prose with no `UI-`/`UX-`/`OP-` IDs.
- Finding against `skills/ui-ux/SKILL.md`: the text said to state the depth line "before anything else" but did not say that a planning answer lists the items by ID. A short paragraph under Depth now says to write the line literally in every answer that plans UI work, to list the items by ID one line each, and to name `ui-proof check` as the done condition.
- With the skill, rerun: opens with `**UI/UX depth:** feature — …`; lists UI-1, UI-2, UX-1 to UX-7 and OP-1 to OP-3, covering Escape and Cancel returning focus to the trigger (UX-1), the validation error with focus on the field (UX-2), keyboard operation (UX-4) and the state matrix (UX-3); and names `ui-proof check` exits 0 as the done condition, ending on `UI proof: pending — <why>` if it cannot run. All pass points met. Still not covered: the answer merges two states into one item (UX-3), and it cannot name the real profile, design system or runner because no app was open.
