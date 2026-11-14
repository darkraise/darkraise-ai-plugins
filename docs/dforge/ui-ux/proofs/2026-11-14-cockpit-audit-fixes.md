# UI proof: cockpit audit fixes

**Contract:** touch
**Fingerprint:** 7c9be6b73a91cf27
**Platform:** terminal
**Viewports:** 200x60, 120x40
**Themes:** default
**Evidence:** local
**Judge:** ship 7c9be6b73a91cf27 — docs/dforge/ui-ux/proofs/2026-11-14-cockpit-audit-fixes.judge.md

## Delta

**UI/UX depth:** touch — the audit branch changes the cockpit's session-end, notification, usage and offer code in `plugins/dforge/hooks/cockpit/`

- **UX-1** — The Resume offer (pane card and band row) is drawn again after /clear.
- **UX-2** — `/cockpit notify url <url>` is no longer a verb: the command's answer says where to set the webhook and does not echo the typed URL.
- **UX-3** — A context window the host does not know draws no share of it (no Infinity%).
- **UX-4** — A burst of usage measurements does not run git once each.
- **UX-5** — A hung Discord send does not hold the turn-complete hook, and the next send still goes out.
- **OP-1** — Proven at 200x60 and 120x40, in the default theme (Claude Code emits colour under NO_COLOR=1, so there is no second theme to walk).

## Results

| ID | Verdict | Evidence | Note |
|---|---|---|---|
| UX-1 | pass | .dforge/ui-ux/cockpit-audit-fixes/c3-before-clear-v200x60.txt, .dforge/ui-ux/cockpit-audit-fixes/c3-after-clear-v200x60.txt, .dforge/ui-ux/cockpit-audit-fixes/c3-before-clear-v120x40.txt, .dforge/ui-ux/cockpit-audit-fixes/c3-after-clear-v120x40.txt; test "resume offer > offers the handoff again in the session a clear carries the process into" | each capture shows the band row `↻ Resumable work · handed off just now — Next: Continue the Remaining list with task 3.` with `[ Resume ] Dismiss`; the after captures show the `❯ /clear` line above it, and the offer is still drawn |
| UX-2 | pass | .dforge/ui-ux/cockpit-audit-fixes/c5-urlverb-v200x60.txt, .dforge/ui-ux/cockpit-audit-fixes/c5-urlverb-v120x40.txt; test "/cockpit notify takes no webhook on the command line, which the transcript keeps" | the command is answered `dforge: No Discord webhook is set. Set one in /cockpit settings (Notifications) in a terminal, or with DFORGE_NOTIFY_URL.` (wrapped at 120 columns); the typed line stays on screen, and the test asserts nothing was saved |
| UX-3 | pass | test "a window the host does not know draws no share of it" | the test asserts the drawn pane holds no `Infinity`; not reachable live, since the host reports a window on every model turn and the placeholder API key starts none |
| UX-4 | pass | test "a burst of measurements does not run git once each", .dforge/ui-ux/cockpit-audit-fixes/c3-after-clear-v200x60.txt, .dforge/ui-ux/cockpit-audit-fixes/c3-after-clear-20s-v200x60.txt, .dforge/ui-ux/cockpit-audit-fixes/main-c3-after-clear-10s-v200x60.txt, .dforge/ui-ux/cockpit-audit-fixes/main-c3-after-clear-20s-v200x60.txt | the test asserts at most one git status run across five measurements. The git-backed Repo card is drawn before /clear, absent 10 s after it and drawn again by 20 s, on this branch and on main alike (the main captures were taken at the audit branch's base), so the pacing change does not move it; the 10 s gap is the existing detail poll, which this change leaves at its 10 s pace |
| UX-5 | pass | test "a hung Discord send does not hold the turn hook, and the next send still goes out" | the test drives turn-complete; it needs a hanging webhook, which this host cannot stage without a model turn |
| OP-1 | pass | .dforge/ui-ux/cockpit-audit-fixes/c5-settings-v200x60.txt, .dforge/ui-ux/cockpit-audit-fixes/c5-settings-v120x40.txt | the captures are 200x60 and 120x40 by measurement (rows and widest line); the settings view opens at both |

## Automated checks

- Walked on Claude Code 2.1.325 in tmux (`NO_COLOR=1`, a throwaway HOME and config directory, a placeholder API key) with `--plugin-dir plugins/dforge` at the audit branch, the window pinned to the stated size, the main build run from the primary checkout; the captures were taken before the final type-only edit to register.tsx (timer types), which changes nothing drawn.
- `claude plugin test plugins/dforge`: 509 pass, 0 fail; `claude plugin test plugins/dflow`: 39 pass, 0 fail
- `claude plugin validate` passes on the marketplace and on all five plugins (one plugin directory warning each, the missing icon)
- `node scripts/test-all.mjs`: exit 0

## Not proven

- The settings view's Discord row hint changed for a surface with no text input (the mobile app): it now names the settings view and `DFORGE_NOTIFY_URL` instead of the removed `/cockpit notify url`. The mobile surface cannot be driven on this host and the test harness gives that surface a text input, so neither a capture nor a test shows the row. A terminal draws the Set button instead.
- The session-end hook's bound on a hung send has no test of its own; the turn-complete test above exercises the same send queue.
