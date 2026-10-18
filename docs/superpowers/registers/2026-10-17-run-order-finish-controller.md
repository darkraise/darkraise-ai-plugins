# Run order, finish, controller and desktop

**Source:** owner request in the 2026-10-17 brainstorming session
**Covers:** docs/superpowers/specs/2026-10-17-finish-without-wait-design.md, docs/superpowers/specs/2026-10-17-cockpit-native-desktop-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Run section: auto move done item to the bottom of list, push running and not started items to the top of list | commit 8cff656 | runList orders in flight, blocked, not started, done (plan order within each) on the terminal card and desktop panel; cockpit tests 'lists running, blocked and pending tasks before done ones' and 'replaces the plan card' | done | - |
| 2 | If user select the approach for finishing development when writting plan, auto use that to finish the devemopment, no need to ask and wait after done all tasks. | docs/superpowers/plans/2026-10-17-finish-without-wait.md | spec A1-A12: a recorded merge/pr/keep runs at once with no menu; the timer, finishTimeout and the countdown are gone | done | - |
| 3 | Evaluate to use opus low/medium as controller instead of sonnet high, since I see that in claude code cloud, it always use opus low/medium as controller. | docs/superpowers/notes/2026-10-17-controller-model-eval.md | evaluation note recommends keep, switch or pilot; owner decides | doing | recommends keeping Sonnet high pending a pilot: Opus 5.5 is 2x Sonnet 5.5 per token, est. +$4/plan at low; pilot awaits owner |
| 4 | Analyze the nested sessions architecture of claude code desktop, to see if we can adapt anything | docs/superpowers/notes/2026-10-17-desktop-nested-sessions.md | note maps the desktop session model onto dforge and ranks adoption candidates | done | no plugin-drivable nesting API; ranks 1-2 (wave tasks grouped by state, other sessions list) feed item 5 |
| 5 | Improve UI with collapsible section and enhance the UI, comtibility with claude code desktop app | docs/superpowers/plans/2026-10-17-cockpit-native-desktop.md | spec A1-A13: sections collapse from their titles on both surfaces; desktop panels, band and settings use native text, theme colors and controls; Agents groups subagents by state; A10-A11 demos in the desktop app | verify | merged at 0c3ab53; owner still runs the A10 and A11 demos in the desktop app: Context legend colors, a failed subagent in the Agents headline, and whether the desktop settings text field draws its label twice (drop label from the Input if so) |
| 6 | cockpit native desktop: collapsing the plan section also collapses the Run card (shared 'plan' key) and the README does not say so | - | - | open | - |
| 7 | cockpit native desktop: no test mounts a collapsed section without canUnderline | - | - | open | - |
| 8 | cockpit native desktop: title absence checks look only for the expanded label, so a wrongly collapsed section would still pass them | - | - | open | - |
| 9 | cockpit native desktop: unnamed 7.5 cell-width constant in hooks/cockpit/native.tsx | - | - | open | - |
| 10 | cockpit native desktop: no tests for a text line without right, undefined indent, dim, or a badge without Svg | - | - | open | - |
| 11 | cockpit native desktop: JSX props and RenderChildren accepting false are unchecked by any typecheck (nothing type-checks the mod) | - | - | open | - |
| 12 | cockpit native desktop: no test checks the desktop band's chips row or warning row after they moved to nativeLine | - | - | open | - |
| 13 | cockpit native desktop: drawNativeRow duplicates drawRow's custom-or-label branch and help lines | - | - | open | - |
| 14 | cockpit native desktop: register.tsx decides isDesktop by Svg alone while the settings view also requires Select, so a host with Svg and no Select gets desktop spacing around terminal controls | - | - | open | - |
| 15 | cockpit native desktop: the desktop settings test covers a number row only, not free-text, locked or custom rows | - | - | open | - |
| 16 | cockpit native desktop: no agentGroups case with more running spawns than shown, which would exercise the Math.max clamp | - | - | open | - |
| 17 | cockpit native desktop: agentGroups assumes spawns arrive oldest-first; the caller must keep satisfying it | - | - | open | - |
| 18 | cockpit native desktop: an approved subagent call stays under Waiting on you until its call returns | - | - | deferred | the plan's documented out-of-scope limit |
| 19 | cockpit native desktop: Task 2 recorded no RED run and the plan said main reads 220 tests when it read 219 | - | - | deferred | historical count note, no work owed |
| 20 | finish without wait: no test runs scripts/finish-choice directly, so a missing executable bit would go unnoticed | - | - | open | - |
| 21 | finish without wait: spec A6's no once-a-second redraw half has no test; the test harness cannot observe the ticker | - | - | deferred | final-residual ruling PARK: syncTicker reads only activity, shells and spawns, and the structural grep is clean; add a direct test if claude-code/testing exposes pending timers |
| 22 | finish without wait: finishing Step 3 still lists the branch's upstream as a base source without the local-branch qualifier Step 4 adds, and a remote prefix is ambiguous for local branch names containing a slash | - | - | open | - |
