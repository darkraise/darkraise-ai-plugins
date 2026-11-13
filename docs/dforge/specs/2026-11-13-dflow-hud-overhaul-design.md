# dflow HUD overhaul in the cockpit's design

**Execution strategy:** sequential — inline execution
**Depth:** light — approach,intricate

## Decisions

- **Process:** architectural, depth light, triggers `approach` (what the HUD shows was open) and `intricate` (cards, a framed band, buttons, collapsing and a dense mode). Owner: "Full flow (Recommended)".
- **Scope:** owner chose "dflow state, cockpit style (Recommended)" with the note "Need account section and Repo section as well. If possible, Usage session show Fable usage." The HUD shows dflow's own cards plus Account, Usage and Repo cards ported from the cockpit; no Shells, Agents or Guard cards.
- **Fable usage:** owner: "retire fable usage". The Usage card carries the 5-hour and 7-day limits and the session's cost, as the cockpit's does. (The mod API reports no Fable-only quota: `SessionRateLimit.kind` is `five_hour`, `seven_day` or a gateway's `spend_limit`.)
- **Interactions:** owner picked all four: "Framed two-line band, Buttons with hotkeys, Collapsible cards, Dense mode".
- **Desktop app:** owner: "Terminal layout everywhere (Recommended)". The desktop draws the same Box/Text layout; no SVG flight deck.
- **State boards:** owner: "Yes, build boards (Recommended)". Board: `docs/dforge/ui-ux/boards/2026-11-13-dflow-hud.md`, also published as a private page for the review: https://claude.ai/artifact/AijNNmmuSmWkNA7N1zrUfo
- **Approach:** owner: "Port into dflow (Recommended)". The cockpit helpers dflow needs are copied and adapted into small pure modules under `plugins/dflow/hooks/hud/`; plugins in this repository never import each other. Rejected: a synced shared kit (adds a sync step and changes dforge's cockpit) and a restyle of today's rows (no meters, buttons, collapsing or dense mode).
- **UI profile:** `docs/dforge/ui-ux/profile.md`, drafted from the 2026-10-29 cockpit proof (terminal platform, nested Claude Code in tmux, 200x60 and 120x40, one theme). Owner: "Right".
- **Status button (A33):** owner: "Right" — dropped from the approved preview.
- **Gate on `.dflow` (A34):** owner: "Right".
- **Cockpit features (A35):** asked whether to leave out the `/context` breakdown, the settings view and `sections` setting, Discord notifications and the resumable-work card; owner: "Add context breakdown, section settings and resumable card". The Context card gains the breakdown; a Sections view and `/dflow:hud sections` set which cards show and in what order; a resumable-work card offers to resume an unfinished plan. Discord notifications and the rest of the cockpit's settings view stay out.
- **Spec review (2026-11-13):** owner chose "Approve and run unattended". The working tree held uncommitted dflow changes in 30 files, including the HUD's per-session context file and session-tagged reset flag that this design keeps; the owner chose to work in place on a new branch with them present.

- **Planning rulings (2026-11-13, auto run):** the last shown card cannot be hidden in the Sections view, so the stored list is never empty and "with every card hidden" (Sections) cannot occur; a context reading with no `resetAt` reads `<tokens> of <window>` with no reset mark on the card, the dense line and the band; the band shrinks in six tiers in the order the band section lists.

Early CI: none

Finish: merge

Worktree: in-place

## Problem

The dflow HUD (`plugins/dflow/hooks/hud/`, about 375 lines) draws a dim one-line band above the prompt, or a pane of labelled text rows from `.dflow/hud.json`. It has no frames, no meters, no buttons, and nothing about the account, the usage limits or the repository. The dforge cockpit (`plugins/dforge/hooks/cockpit/`) has an established look the owner wants dflow to follow: a Now row, one rounded card per section in its own color with a collapsible title and a headline on the top rule, `▰▱` meters with marks, rounded buttons with hotkeys, a dense one-line-per-section mode, and a framed two-line band when minimized.

## Design

### Surfaces and modes

The modes stay `band`, `pane` and `off`, saved in the mod store under `mode` as today; `band` is the default. `/dflow:hud` with no argument cycles them, with one change: in mode `pane` while the pane is not up (the person closed it), it reopens the pane instead of moving to `off`. `/dflow:hud band|pane|off` sets one; anything else answers `Usage: /dflow:hud [band|pane|off]`.

- **Pane** (`dflow-hud`, opened at 56 columns as the cockpit's is): the detailed layout (cards) or the dense layout, by the saved `density`.
- **Band** (mode `band`): the framed band above the prompt.
- **Off:** nothing drawn.

The HUD draws only in a checkout whose git root holds `.dflow`. Elsewhere the band draws nothing and the pane shows the no-state text (UI-15). The context governor (the per-session context file and the reset-and-resume after `dflow done`) keeps running in every mode, `off` included, exactly as today.

### The pane, detailed

Top to bottom: the Now row, the Account card, the controls row, then the Plan, Context, Usage, Checks, Board, Workers and Repo cards, then the Next row. A card with nothing to show is left out (state matrix in UX-6).

Each card is the cockpit's: a rounded frame in its color with one cell of padding; the title is a button reading `▾ Title` (expanded) or `▸ Title` (collapsed) in the card's color, bold; the headline is right-aligned on the same row; detail rows sit two cells in.

| Card | Color | Headline | Body |
|---|---|---|---|
| Account | the account color (one of the cockpit's eight, picked from the config directory) | billing label, `subscription` | `● email`; `name · organization (role)`; `model · effort effort`; `Remote ● connected · <devices>` / `Remote ○ on · no device yet` / `Remote ○ not connected`; `config ~/.claude` |
| Plan | yellow | `4/7`, then `· 1 blocked` in red when any; `✓ done` in green when every task is done | title (bold) and plan file (dim); a progress meter across the card; the task list (below); each `checks` entry as `⚠ <text>` in yellow |
| Context | cyan | `79% of reset` in the ramp color; before the first reading `≈37k estimated` dim from the breakdown's total, else `no reading yet` dim | a meter over the whole window, filled to the reading, `┃` at `resetAt` in the ramp color and `┊` gray where auto-compaction runs (when it is on); legend `118k of 1.0M ┃ resets at 150k ┊ compacts 967k`; `trend ▁▂▃▅▆ +23k` once two readings exist; the breakdown (below); the **⇣ Compact** button |
| Usage | blue | `$4.85 · $2.35/h` when the cost is known | per `five_hour` and `seven_day` window: `5h` or `7d`, a meter with `┊` where the window has run to, the percent in the ramp color; below it `resets in 3h40m` and, once the window is ten minutes old, `on pace` (green) or `out in 1h10m` (amber); any other window as one row `<kind> 42%` |
| Checks | red | the first that holds: `✗ failed` red (a gate failed), `● N blocking` red (open blocking findings), `stale` yellow (gates passed on an older head), `✓ passed` green, `not run` dim | `Gates  ✓ passed` / `✓ passed · stale, the head moved` / `✗ failed: lint, test` / `not run`; `Review  tier 1 recorded · 2 open, 1 blocking` / `not run` |
| Board | white | `#12 doing` when the plan has a board row, else the row count | the counts, `3 todo · 1 doing · 1 blocked`; `darkmem ● synced · 0 queued` / `◐ 3 queued` / `○ offline · 3 queued` (yellow) / `✗ refused: run dflow sync push · 3 queued` (red) / `✗ conflict: run dflow sync pull` (red) |
| Workers | magenta | `● 2 running` | `● Task 6: <title>` per worker, the worker's branch dim on the same row |
| Repo | green | `● dirty` yellow or `✓ clean` green | `repo owner/name` (from the remote, else the folder); `dir ~/code/x`; `⎇ branch ↑3 ↓1`; `~2 changed ?1 untracked` |

The ramp color is the cockpit's: under 50% green, under 75% yellow (`warning`), under 90% `#ff8700`, else red (`error`).

**The Plan card's task list** shows at most eight rows, a window centred on the current task. Each row is a glyph and `Task N: <title>`: `✓` green for done, `▸` cyan bold for the current task, `✗` red for blocked with its reason on an indented row, `○` dim for pending, and `· worker` appended for a `Run: worker` task. The current task's indented row reads `verify failed 2×` in yellow when it has failed attempts. Rows cut from the window are counted in one dim row above or below (`… 3 more done`, `… 12 more`).

**The Context card's breakdown** is the cockpit's: the `/context` categories estimated locally (`$.session.usage({ breakdown: 'summary' })`, no API call), the used ones only, largest first, the top six. A stacked bar across the card splits them in six colors (cyan, magenta, yellow, green, blue, red, in that order), and one row per category matches its color: `■ Messages              318k  78%`, the share being of the six rows' sum.

**The Now row** (above the Account card, no frame): `● Task 5 in progress` (cyan; `ready` and `wip` read `ready` and `in progress`), with `· verify failed 1×` in yellow; `✓ All 7 tasks done` green; `✗ Every remaining task is blocked` red; `○ No active plan on <branch>` dim.

**The controls row** sits under the Account card (it leads the pane when Account is hidden): **≡ Dense** (`d`) or **☰ Detailed** in the dense layout, **⚙ Sections** (`s`), and **▁ Minimize** (`m`). **⇣ Compact** (`c`) sits on the Context card. Buttons are the cockpit's: a rounded box, gray at rest, the hotkey's letter underlined in the label; **Compact** takes the accent (`permission`) once the reading reaches `resetAt`. Hotkeys work while the pane has the keyboard.

**The Next row** closes the pane: `Next  <hud.next>`, `Next` bold.

### Sections

The store keeps `sections`, the cards the pane shows in the order it shows them; the default is all eight in the order above, and an empty or unreadable value means the default. It orders and filters the detailed and the dense layouts alike; the band keeps its fixed segments. The Now row, the controls row and the Next row are not sections and always show.

- **⚙ Sections** (`s`) turns the pane into the Sections view: one row per card in its current order, each with a switch (`● On` in the accent, or `○ Off` dim), the card's name, and for a shown card **↑** and **↓** to move it (the first shown row has no **↑**, the last no **↓**); below them **Reset** (back to the default) and **Back** (`b`). Hidden cards are listed after the shown ones, in the default order, without move buttons; turning one on adds it after the last shown card. Each press saves at once and redraws the view.
- `/dflow:hud sections` opens the pane on the Sections view. `/dflow:hud sections plan,context,repo` sets the list directly and answers `dflow HUD sections: plan, context, repo`; a name that is not one of the eight answers `Sections: account, plan, context, usage, checks, board, workers, repo` and changes nothing. This command is the keyboard path to every setting the view holds.
- With every card hidden the pane shows the Now row, the controls row and the Next row.

### Resumable work

When a session starts or switches (`/clear`, `/resume`) in a checkout whose active plan is approved, not finished, and has a current task, the HUD offers to resume it:

- **In the pane**, a card at the top above the Now row, framed in the accent color, that never collapses and is not a section: `↻ Resumable work · <plan title>`, then `Next: Task 5: Wire the meter (in progress)` (`(ready)` for a task not started), then **Resume** (`r`, in the accent) and **Dismiss**.
- **In mode `band`**, a framed row above the band in the accent color: `↻ Resumable work · <plan title> — Next: Task 5: Wire the meter`, with **Resume** and **Dismiss** and no hotkeys (the prompt holds the keyboard).
- **Resume** submits `/dflow:build` as the person's prompt. **Dismiss** removes the offer. Pressing either in one place removes both for this session.
- The offer also goes, for this session, once `/dflow:build` runs in it, once `hud.json` shows the plan's done count or current task changed, or once the plan is finished. A compaction is not a session switch, so the governor's own reset-and-resume never shows it. Mode `off` shows nothing.

### The pane, dense

The Now row, the controls on one line as plain buttons without boxes, their hotkey letters still underlined (**☰ Detailed**, **⚙ Sections**, **▁ Minimize**, **⇣ Compact**), then one line per card in the same order, each with nothing to show left out, each truncated to the pane:

```
● Task 5 in progress · verify failed 1×
 ☰ Detailed   ▁ Minimize
acct  you@example.com · subscription · Remote ●
plan  ▰▰▰▰▰▱▱▱ 4/7 · Task 5 · 1 blocked
ctx   ▰▰▰▰▰▰┃▱ 79% of reset · 118k
lim   5h 23% on pace · 7d 61% · $4.85
chk   gates ✗ lint · review 1 blocking
board #12 doing · darkmem 3 queued
work  Task 6, Task 7
repo  ⎇ feat/rate-meter* ↑3 ~2 ?1
next  /dflow:build — Task 5: Wire the meter
```

### The band

The cockpit's minimized band, in the account color:

```
╭─ you@example.com · subscription · Remote ● connected ───────────────────── Expand ─╮
│ ~/code/shop ⎇ feat/rate-meter* ↑2 ~1 ?1 · Opus 5.5 · xhigh · dflow 4/7 · Task 5 · ● 2 workers │
│ ctx ▰▰▰▰▱▱▱┃▱▱ 79% · 5h ▰▰▱▱┊▱▱▱ 23% on pace · 3h40m · 7d 61% · $1.20              │
╰──────────────────────────────────────────────────────────────────────────────────╯
```

- Top rule: email, billing and Remote on the left; **Expand** on the right (no hotkey: the prompt holds the keyboard).
- Line 1: the folder with branch, ahead/behind and changes; model and effort; the plan's `done/total` and current task while a plan is active; the running workers.
- Line 2: the context against the reset point; the 5-hour and 7-day limits with pace and reset; the session's cost.
- A third line in red when a task is blocked, gates failed, or darkmem has a conflict or refusal: `✗ Task 6 blocked · ✗ gates failed · ✗ darkmem conflict`.
- Each line shrinks a step at a time until it fits: meters from 8 to 4 cells, then the percent alone; then the reset times and `on pace` go; then the path keeps the repository's name; then model and effort go; then the line is cut with `…`. Below 48 columns the frame goes and the email sits on the first row beside **Expand**.

### Collapsing and saved preferences

Pressing a card's title collapses it to its title row and headline, or expands it. The mod store keeps `collapsed` (a list of card keys: `account`, `plan`, `context`, `usage`, `checks`, `board`, `workers`, `repo`) and `density` (`detailed` or `dense`) beside `mode`, so the next session opens the same way. A stored value that is not one of these is ignored. A collapsed Context card keeps its **Compact** button.

### Data and timing

- `.dflow/hud.json`, as the CLI writes it today (`plugins/dflow/lib/status.mjs` `buildModel`): it already carries `plan.tasks`, `checks` and `workers`. The `Hud` type gains `tasks`, `checks` and the worker fields; the CLI does not change.
- One `$.session.usage()` call per poll, as today, gives the context reading, the rate-limit windows and the cost.
- The account from `.claude.json` (under `CLAUDE_CONFIG_DIR` when set, else the home one), read at session start and on a session switch; the model from the last main-loop turn's usage, falling back to `$.session.model()`; the effort from the settings' `effortLevel`; Remote Control from the client join and leave events and the `/config` setting, as the cockpit reads them.
- Git: `git --no-optional-locks -c core.fsmonitor=false status --porcelain=v2 --branch` with a 3-second timeout, every fifth poll (ten seconds) while the band or the pane is shown, plus `git remote get-url origin` once per session switch.
- The trend keeps the context reading at each main-loop turn end, the last 40.
- The breakdown: `$.session.usage({ breakdown: 'summary' })` when the pane opens and every fifth poll after, only while the pane is up in the detailed layout with the Context card shown and expanded.
- The resume offer is worked out from `hud.json` at session start and on a session switch, and dropped by the events in Resumable work; the `/dflow:build` run is seen by the mod's `command.run` hook.
- The poll stays at two seconds. The render hooks do no I/O: they read atoms.

### Units

| File | Holds |
|---|---|
| `plugins/dflow/hooks/hud/view.mjs` | modes, the reset flag and the context file name (kept); the Now row, card models, the task window, dense lines, the sections list and its parsing, the resume offer and when it ends |
| `plugins/dflow/hooks/hud/meter.mjs` (new) | token and duration text, the ramp color, the meter track with marks, the sparkline, the stacked breakdown bar, window elapsed and limit pace (ported from the cockpit's `lib.ts`) |
| `plugins/dflow/hooks/hud/band.mjs` (new) | band segments, the shrink tiers, fitting a line to a width |
| `plugins/dflow/hooks/hud/account.mjs` (new) | the account from a `.claude.json` object, its color, the billing label, the Remote text |
| `plugins/dflow/hooks/hud/repo.mjs` (new) | git porcelain parsing, the repository name, the shortened folder |
| `plugins/dflow/hooks/hud/register.tsx` | engine wiring, polling, preferences, drawing models as Box/Text/Button |
| `plugins/dflow/types/index.d.ts` | the `Hud` fields and the new atoms' types |

The pure modules are plain `.mjs`, so dflow's Node suite tests them directly, as it tests `view.mjs` today. A model is a list of runs (`{ text, color?, bold?, dim? }`); `register.tsx` only maps them to elements.

### Error handling

The HUD is a view: no read or draw failure reaches the engine. A `hud.json` that does not parse keeps the last good view and is read again on the next poll. A failed git call keeps the last Repo reading; with none, the Repo card shows `dir` alone. A missing `.claude.json` or field drops that row; with no email the Account card shows the config directory alone. A failed **Compact** retries once after two seconds, then toasts `dflow: could not compact; run /compact`.

### Testing

- `plugins/dflow/tests/hud.test.mjs` (Node): the pure modules. Card models and the Now row for each state in UX-6; the task window centred and counted with 40 tasks; dense lines; the sections list parsed, defaulted and applied; the stacked breakdown bar summing to its width; the resume offer's start and end conditions; band lines fit 200, 120, 80, 48 and 47 columns, with every tier in order; meter marks at the right cell; limit pace; porcelain parsing; a stable account color; unknown stored preferences ignored. Replaces the `bandText` and `paneRows` assertions there.
- `plugins/dflow/hooks/hud/register.test.tsx` (`claude plugin test plugins/dflow`): the pane in detailed and dense layouts, the band and its red line, title presses saving `collapsed`, **Dense** saving `density`, **Minimize** and **Expand** switching the mode and the pane, the hotkeys, **Compact** sending the reset instructions with a plan active, the context file written in mode `off`, nothing drawn outside `.dflow`, the cycle reopening a pane closed by hand, the Sections view's switches, moves, **Reset** and **Back**, `/dflow:hud sections`, the breakdown rows, and the resume card and band with **Resume** and **Dismiss**.
- The proof: the walkthrough in a nested session at 200x60 and 120x40 with the worst-case data (UX-10).

## UI/UX contract

**UI/UX depth:** feature — the HUD's pane and band are redesigned and its mode flow gains Minimize, Expand, collapsing and density

### UI

- **UI-1** — Pane layout: the resume card while the offer shows, the Now row, Account, the controls row, Plan, Context, Usage, Checks, Board, Workers, Repo, the Next row, in that order; each card a rounded frame in its color from the card table, title button and right-aligned headline on its first row, detail rows two cells in. Board: `docs/dforge/ui-ux/boards/2026-11-13-dflow-hud.md` (plan running, all done, blocked, no plan, worst case, collapsed, dense, narrow).
- **UI-2** — Now row: the four states and their glyphs and colors as the design states.
- **UI-3** — Account card: email, name and organization with role, model and effort, Remote, config directory; billing as the headline; the frame in the account color.
- **UI-4** — Plan card: title and file, progress meter, a task window of at most eight rows centred on the current task with the counted overflow rows, the glyphs `✓ ▸ ✗ ○`, the blocked reason and failed-verify rows, `· worker`, the `⚠` checks rows.
- **UI-5** — Context card: the meter over the window with `┃` at `resetAt` and `┊` at the compaction point, the legend, the trend line, the stacked breakdown bar and its rows in matching colors, the headline percent of the reset point in the ramp color (or the estimate before a reading), the **Compact** button.
- **UI-6** — Usage card: a meter per 5-hour and 7-day window with `┊` at the elapsed share, percent, reset and pace rows; other windows as rows; the cost headline.
- **UI-7** — Checks card: the Gates and Review rows and the headline precedence.
- **UI-8** — Board card: counts, the board row headline, the five darkmem readings with their glyphs and colors.
- **UI-9** — Workers card: one row per worker with the task title and branch.
- **UI-10** — Repo card: repository, folder, branch with ahead and behind, changes, and the dirty or clean headline.
- **UI-11** — Buttons: the controls row holds **Dense** (or **Detailed**), **Sections** and **Minimize**; rounded boxes, gray at rest, the hotkey letter underlined (on Claude Code before 2.1.295 the label leads with `c: `); **Compact** in the accent once the reading reaches `resetAt`; the Next row bold label.
- **UI-12** — Dense layout: the Now row, one controls line with **Detailed**, **Minimize** and **Compact**, one line per card with a short label (`acct plan ctx lim chk board work repo next`), each truncated to the pane.
- **UI-13** — Band: the frame in the account color, the top rule with email, billing, Remote and **Expand**, the two lines and their segments, the red third line.
- **UI-14** — Narrow widths: band lines shrink through the tiers in order and never wrap; below 48 columns the band drops its frame; the pane's rows truncate with `…` and never wrap at 40 columns. Widths are counted in terminal cells: a wide character such as an emoji or a CJK character counts two.
- **UI-15** — No state: outside a checkout with `.dflow`, or before `hud.json` exists, the pane reads `dflow has no state in this repository yet.` and `Run /dflow:init, then /dflow:plan.` dim; the band draws nothing.
- **UI-16** — Sections view: one row per card with its `● On` or `○ Off` switch and its name; shown cards first in their order with **↑** and **↓**, then hidden ones in the default order without them; **Reset** and **Back** below.
- **UI-17** — Resumable work: the pane card above the Now row in an accent frame with its title, its `Next:` line, **Resume** in the accent and **Dismiss**; in mode `band`, the one framed accent row above the band with the same text and buttons.

### UX

- **UX-1** — Mode flow: `/dflow:hud` cycles `band → pane → off → band`, except that in mode `pane` with the pane not up it reopens the pane; `/dflow:hud band|pane|off` sets one and answers `dflow HUD: <mode>`; anything else answers the usage line. **Minimize** sets `band` and closes the pane; **Expand** sets `pane` and opens it. The mode survives a new session and `/clear`. None of this spends a model turn.
- **UX-2** — Collapse flow: pressing a card title toggles it between `▾` with its body and `▸` with its title row and headline alone; the change shows on the next frame and survives a new session. A collapsed Context card keeps **Compact**.
- **UX-3** — Density flow: **Dense** (`d`) switches to the dense layout and becomes **Detailed**; pressing it again returns; the choice survives a new session.
- **UX-4** — Compact: with a plan active it compacts with the reset instructions the governor uses (`RESET_INSTRUCTIONS`); without one, with no instructions; a failure retries once after two seconds, then toasts `dflow: could not compact; run /compact`.
- **UX-5** — Keyboard: while the pane has the keyboard, `c` Compact, `d` Dense or Detailed, `s` Sections, `m` Minimize, `r` Resume while the offer shows, and `b` Back in the Sections view; the band's **Expand**, **Resume** and **Dismiss** have no hotkeys, so typing in the prompt never presses them.
- **UX-6** — State matrix:

  | Card | Left out when | Empty or partial |
  |---|---|---|
  | Account | never | no `.claude.json`: config directory alone; no model yet: `$.session.model()` |
  | Plan | never | no plan: `No active plan on <branch>.` dim; 0 tasks: title, `0/0`, no meter |
  | Context | no reading, no `resetAt` and no breakdown | no reading: headline `≈<total> estimated` from the breakdown, else `no reading yet`, and no meter; no breakdown yet: no bar or rows; auto-compaction off: no `┊` |
  | Usage | no windows and no cost | no windows (API billing): the cost headline alone |
  | Checks | no plan | gates and review `not run` |
  | Board | no board and darkmem off | no board: the darkmem row alone |
  | Workers | no workers | — |
  | Repo | never | no git reading yet: `dir` alone; no remote: the folder name |

  A card the `sections` setting hides is left out whatever its state.

- **UX-7** — Live updates: a `hud.json` change shows within one poll (2 s); a git change within ten seconds; limits and cost with each poll. No git or account read runs while the mode is `off`. The context file and the reset-and-resume work in every mode.
- **UX-8** — Failure: an unparsable `hud.json` keeps the last good view; a failing git call keeps the last reading; no exception from a read or a draw reaches the engine.
- **UX-9** — Session switch: after `/clear` or `/resume` the HUD reads everything again within one poll, and the saved mode, density and collapsed cards hold.
- **UX-10** — Worst-case data, written to `.dflow/hud.json` (the real boundary) by a fixture: a 40-task plan with 120-character titles, emoji and diacritics in a title, one unbroken 90-character identifier, a 200-character blocked reason, 12 workers, five failed gates, six board states, a darkmem conflict, an 80-character branch, a 60-character email, no rate-limit windows and no cost; and the empty cases: no plan, zero tasks, no board, darkmem off.
- **UX-11** — Sections flow: entry from **Sections** (`s`) or `/dflow:hud sections`; a switch hides or shows its card, **↑** and **↓** move it one place, **Reset** restores the default, each saving at once and surviving a new session; **Back** (`b`) returns to the cards, closing the pane when it was opened only for the view from mode `band`; `/dflow:hud sections <list>` sets the list or, with an unknown name, answers the valid names and changes nothing.
- **UX-12** — Resume flow: the offer appears on session start or switch under the conditions in Resumable work; **Resume** submits `/dflow:build` once as the person's prompt and removes the offer in both places; **Dismiss** removes it in both places; it also goes when `/dflow:build` runs, the plan's progress changes, or the plan finishes; it does not come back in that session.

### Output promise

| ID | Promise |
|---|---|
| OP-1 | The pane and the band match the board in structure, glyphs, colors and copy; spacing may differ by a cell. |
| OP-2 | Proven in the terminal at 200x60 and 120x40, default theme, with the pane docked; band widths 80, 48 and 47 proven by the Node suite. |
| OP-3 | Every row reads without color: a glyph or a word carries each state. |
| OP-4 | Declared deviations from the cockpit: no desktop flight deck (owner), no Fable usage (owner), no Shells, Agents or Guard cards (owner), no Discord notifications (owner), and of the settings view only the sections (owner); the breakdown's row count is fixed at six, and the band's segments are fixed. |
| OP-5 | The render hooks do no I/O; git and the breakdown each run at most once per ten seconds, git with a 3-second timeout, and neither runs in mode `off`. |

## Acceptance

A1. [test, high] UI-1: With a plan active, no resume offer and the default sections, the detailed pane draws the Now row, Account, the controls row, Plan, Context, Usage, Checks, Board, Repo and the Next row in that order, each card in a rounded frame in its color with its title and headline on the first row.
A2. [test, high] UI-2: The Now row reads `● Task 5 in progress · verify failed 1×`, `✓ All 7 tasks done`, `✗ Every remaining task is blocked` or `○ No active plan on <branch>` for the four states.
A3. [test, high] UI-3: The Account card shows the email, name and organization with role, model and effort, Remote and the config directory, with the billing label as its headline.
A4. [test, high] UI-4: With 40 tasks and Task 20 current, the Plan card lists at most eight task rows including Task 20, with counted overflow rows above and below.
A5. [test, high] UI-4: A blocked task shows `✗` and its reason on an indented row; a current task with two failed attempts shows `verify failed 2×`; a worker task shows `· worker`; each `checks` entry shows as a `⚠` row.
A6. [test, high] UI-5: At 118,000 tokens of a 1,000,000 window with `resetAt` 150,000 and auto-compaction off, the Context headline reads `79% of reset`, the meter's `┃` sits at the cell for 15% of its width, and the legend reads `118k of 1.0M ┃ resets at 150k`; with auto-compaction at 967,000 the meter adds `┊` at 97% and the legend ends `┊ compacts 967k`.
A7. [test, high] UI-6: A 5-hour window at 23% resetting in 3h40m draws a `5h` meter with `┊` at the elapsed share, `23%`, and `resets in 3h40m`, with `on pace` or `out in …` once the window is ten minutes old.
A8. [test, high] UI-6: With no rate-limit windows and a cost of $4.80 over two hours, the Usage card shows only its headline `$4.80 · $2.40/h`.
A9. [test, high] UI-7: The Checks card's Gates row reads `✗ failed: lint, test` for two failed gates, and its headline reads `✗ failed`.
A10. [test, high] UI-8: The darkmem row reads `● synced · 0 queued`, `◐ 3 queued`, `○ offline · 3 queued`, `✗ refused: run dflow sync push · 3 queued` and `✗ conflict: run dflow sync pull` for the five states.
A11. [test, high] UI-9: With workers on Tasks 6 and 7, the Workers card headline reads `● 2 running` and lists both with their titles; with none the card is left out.
A12. [test, high] UI-10: A porcelain reading on `feat/x` three ahead and one behind with two changed files and one untracked draws `⎇ feat/x ↑3 ↓1`, `~2 changed ?1 untracked` and the headline `● dirty`.
A13. [test, high] UI-11: The **Compact** button takes the accent once the reading reaches `resetAt`, and is gray below it.
A14. [test, high] UI-12, UX-3: Pressing **Dense** draws one line per card with labels `acct plan ctx lim chk board repo next` and saves `density` as `dense`; pressing **Detailed** restores the cards and saves `detailed`.
A15. [test, high] UI-13: Mode `band` with a plan active draws the framed band in the account color with the email, billing, Remote and **Expand** on the top rule and the two lines' segments in order.
A16. [test, high] UI-13: A blocked task, failed gates or a darkmem conflict adds a red third band line naming each.
A17. [test, high] UI-14: At 200, 120, 80 and 48 columns every band line fits its width without wrapping, shrinking through the tiers in order; at 47 the band has no frame and the email sits beside **Expand**.
A18. [test, high] UI-15: In a checkout without `.dflow` the band draws nothing and the pane shows the two no-state lines.
A19. [test, high] UX-1: `/dflow:hud` cycles band, pane, off; with mode `pane` and the pane closed by hand it reopens the pane; `/dflow:hud sideways` answers the usage line; none of these starts a model turn.
A20. [test, high] UX-1: **Minimize** sets mode `band` and closes the pane; **Expand** sets mode `pane` and opens it; the stored mode is read back by a new session.
A21. [test, high] UX-2: Pressing the Plan card's title draws it as `▸ Plan` with its headline and no body, saves `collapsed` as `["plan"]`, and a second press restores it; a collapsed Context card still shows **Compact**.
A22. [test, high] UX-4: Pressing **Compact** with a plan active calls the compaction with `RESET_INSTRUCTIONS`; without a plan, with no instructions.
A23. [test, high] UX-4: When the compaction fails twice, the HUD shows the toast `dflow: could not compact; run /compact` and nothing else.
A24. [test, high] UX-5: With the pane focused, `c`, `d`, `s` and `m` press **Compact**, **Dense**, **Sections** and **Minimize**; `r` presses **Resume** while the offer shows; `b` presses **Back** in the Sections view.
A25. [test, neg, high] UX-5: The band's **Expand**, **Resume** and **Dismiss** buttons carry no hotkey, so text typed in the prompt never presses them.
A26. [test, high] UX-6: Each card is left out, or shows its partial form, exactly as the state matrix says, for each row of the matrix.
A27. [test, neg, high] UX-7: In mode `off` no git status runs and no `.claude.json` read happens, while the per-session context file is still written and a fresh reset flag still compacts and submits `/dflow:build`.
A28. [test, high] UX-7: A rewritten `hud.json` shows in the pane on the next poll, within two seconds.
A29. [test, neg, high] UX-8: An unparsable `hud.json` or a failing git call leaves the last good view on screen and raises no error to the engine.
A30. [test, high] UX-9: After a session switch the HUD reads everything again within one poll, with the stored mode, density and collapsed cards in force.
A31. [demo, high] OP-1, OP-2, OP-3: In a nested session at 200x60 and 120x40 with the worst-case and empty data of UX-10, the pane and the band match the board, and every state is readable without color.
A32. [test, neg, high] OP-5: The render hooks make no file, process or network call.
A33. [demo, confirmed] The pane has no **Status** button.
A34. [test, confirmed] The band and the cards draw only in a checkout whose git root holds `.dflow`, so installing dflow does not add a band to every repository.
A35. [demo, high] OP-4: The HUD sends no Discord notification and has no settings beyond the sections.
A36. [test, high] UI-5: With a breakdown of Messages 318k, System tools 41k and five smaller categories, the Context card draws a stacked bar whose six colored runs sum to the card's width, and six rows, largest first, the first reading `■ Messages` with `318k` and its share of the six rows' sum.
A37. [test, high] UX-6: Before the first reading, with a breakdown total of 37,000, the Context headline reads `≈37k estimated` and no meter is drawn.
A38. [test, neg, high] OP-5: The breakdown is not requested in mode `band`, in the dense layout, or while the Context card is collapsed or hidden.
A39. [test, high] UI-16, UX-11: Pressing **Sections** shows one row per card; turning Usage off hides the Usage card in both layouts and saves `sections` without `usage`; **↓** on Plan moves it below Context; **Reset** restores all eight in the default order; **Back** returns to the cards.
A40. [test, high] UX-11: `/dflow:hud sections plan,context,repo` shows only those three cards in that order and answers `dflow HUD sections: plan, context, repo`; `/dflow:hud sections plan,shells` answers the valid names and leaves `sections` unchanged.
A41. [test, high] UI-17, UX-12: A session that starts on an approved plan with Task 5 in progress shows the resume card above the Now row in the pane and the resume row above the band in mode `band`, each reading `Next: Task 5: Wire the meter`.
A42. [test, high] UX-12: Pressing **Resume** submits `/dflow:build` once as the person's prompt and removes the offer from the pane and the band; pressing **Dismiss** removes both without submitting anything.
A43. [test, neg, high] UX-12: No offer shows for an unapproved plan, a finished plan, a plan with every remaining task blocked, after a compaction in the same session, or once `/dflow:build` has run or the plan's progress changed in this session.

## Riskiest assumption

That the dflow mod can read everything the ported cards need through the engine calls the cockpit already uses, on this host's Claude Code 2.1.323 (the cockpit was built against 2.1.299 to 2.1.306). Evidence: the account from `.claude.json` through `$.fs` (`plugins/dforge/hooks/cockpit/register.tsx:3813-3830`); rate limits and cost from `$.session.usage()` (`SessionUsage` in `plugins/dflow/.claude-plugin/types/claude-code/index.d.ts`, around line 12820, read 2026-11-13); git through `$.process.run` (`register.tsx:3777`, and dflow's own `register.tsx` already runs `git rev-parse`); pane state through `$.ui.panes()` (`register.tsx:3922`). Whether Button hotkeys and the underlined label still behave the same on 2.1.323 is unverified — the plan's first task verifies it with a rendered button and hotkey in `register.test.tsx` before the cards are built on it.

## Out of scope

The dforge cockpit itself, the CLI's `hud.json` writer, the `/dflow:hud` skill's fallback text (its description line is updated), and anything listed in OP-4.
