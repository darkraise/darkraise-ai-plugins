# UI proof: cockpit sections after /clear and /resume

**Contract:** touch
**Fingerprint:** 20791747c68d03ae
**Platform:** terminal
**Viewports:** 200x60, 120x40
**Themes:** default
**Evidence:** local
**Judge:** ship 20791747c68d03ae — docs/dforge/ui-ux/proofs/2026-10-29-cockpit-after-clear.judge.md

## Delta

**UI/UX depth:** touch — the cockpit's account card and context breakdown disappeared after /clear or an in-process /resume

- **UX-1** — After /clear, the Account card is drawn again within one poll (2 s).
- **UX-2** — After an in-process /resume, the Account card is drawn again.
- **UI-1** — After /clear and /resume, the Context breakdown is drawn again.
- **UX-3** — A pane the person closed stays closed after /clear or /resume.
- **UX-4** — A minimized cockpit's pane is neither opened nor shut by /clear or /resume.
- **UX-5** — /cockpit still answers after /clear and after /resume.
- **UX-6** — A session end that ends the process reads nothing again.
- **OP-1** — Proven at 200x60 and 120x40, in the default theme (Claude Code emits colour under NO_COLOR=1, so it offers no second theme to walk).

## Results

| ID | Verdict | Evidence | Note |
|---|---|---|---|
| UX-1 | pass | .dforge/ui-ux/cockpit-after-clear/after-clear-200x60.ansi, .dforge/ui-ux/cockpit-after-clear/after-clear-120x40.ansi; test "account > shows the card and the context again in the session a clear carries the process into, the pane left shut" | captured 6 s after /clear; the main build at the same point draws no card: .dforge/ui-ux/cockpit-after-clear/main-after-clear-200x60.ansi |
| UX-2 | pass | .dforge/ui-ux/cockpit-after-clear/resume-picker-200x60.ansi, .dforge/ui-ux/cockpit-after-clear/after-resume-200x60.ansi, .dforge/ui-ux/cockpit-after-clear/resume-picker-120x40.ansi, .dforge/ui-ux/cockpit-after-clear/after-resume-120x40.ansi; test "account > shows the card and the context again in the session a resume carries the process into, the pane left shut" | the picker capture shows the /resume; the main build draws no card after it: .dforge/ui-ux/cockpit-after-clear/main-after-resume-200x60.ansi |
| UI-1 | pass | .dforge/ui-ux/cockpit-after-clear/after-clear-200x60.ansi, .dforge/ui-ux/cockpit-after-clear/after-clear-120x40.ansi, .dforge/ui-ux/cockpit-after-clear/after-resume-200x60.ansi, .dforge/ui-ux/cockpit-after-clear/after-resume-120x40.ansi; the two tests above assert "System tools" | the main build's after-clear capture has no breakdown |
| UX-3 | pass | test "account > shows the card and the context again in the session a clear carries the process into, the pane left shut" and its resume twin | the pane is shut before the re-read; both tests fail when the re-read runs the start's pane step |
| UX-4 | pass | test "account > leaves the pane up for a minimized cockpit in the session a clear carries the process into" and its resume twin | both tests fail when the re-read runs the start's pane step |
| UX-5 | pass | .dforge/ui-ux/cockpit-after-clear/cockpit-after-clear-200x60.ansi, .dforge/ui-ux/cockpit-after-clear/cockpit-after-clear-120x40.ansi, .dforge/ui-ux/cockpit-after-clear/cockpit-after-resume-200x60.ansi, .dforge/ui-ux/cockpit-after-clear/cockpit-after-resume-120x40.ansi | the left pane shows "dforge: Cockpit pane opened." in answer to /cockpit |
| UX-6 | pass | test "account > reads nothing again after a session end that ends the process" | |
| OP-1 | pass | every capture above exists at 200x60 (60 rows) and 120x40 (40 rows) | one theme: Claude Code emits colour escapes under NO_COLOR=1; every row is carried by text, not colour |

## Automated checks

- claude plugin test plugins/dforge: 487 pass, 0 fail
- tsc --noEmit -p plugins/dforge: 0 errors
- ui-lint on register.tsx: 2 raw-color findings, both in lines this change does not touch
- Walked on Claude Code 2.1.312 in tmux with an isolated config directory and a placeholder account (probe@example.com)
