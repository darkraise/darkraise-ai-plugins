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
