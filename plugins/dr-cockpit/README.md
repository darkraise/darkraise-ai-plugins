# dr-cockpit

A Claude Code mod for long sessions, and for `dr-superpowers` plans in
particular. It is a hooks module, not a set of skills, so it costs the model no
context: it draws in the interface and acts on the engine's events.

Claude Code only. Built and tested against Claude Code 2.1.292 to 2.1.295; the
mod API is early access and may change between releases.

## What it does

**Cockpit pane.** A pane with the session at a glance. It opens by itself when
a session starts, once the terminal is 144 columns wide; `/cockpit` opens it at
any width, and says why if Claude Code holds it back. In fullscreen at 110
columns or more it docks beside the transcript; otherwise it sits above the
prompt. In the full layout each section is a framed card in its own color, its
headline on the title line, under one **Now** row that says what the
session is doing:

```
● running 2m14s · step 18 · Bash in impl-sonnet-low
╭ Account ──────────────────────────── subscription ╮
│ ● you@example.com                                 │
│   You · Acme (admin)                              │
│   Opus 5.5 · xhigh effort                         │
│   Remote ● connected · phone                      │
│   config ~/.claude                                │
╰───────────────────────────────────────────────────╯
╭ Context ─────────────────── 68% of handoff · ≈7 turns ╮
│ ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▱▱▱▱▱▱▱┃▱▱▱▱▱┊▱▱▱▱▱▱▱▱▱▱▱▱▱▱ │
│ 412k of 1.0M ┃ handoff 604k ┊ compacts 744k      │
│ trend ▁▂▃▃▄▄▅▆▆▇▇█ +23k                           │
│ ██████████████████████████████████████▓▓▓▓▒▒▒░░  │
│   ■ Messages              318k  78%               │
│   ■ System tools           41k  10%               │
│ ╭──────────╮ ╭─────────╮ ╭──────────╮             │
│ │ Hand off │ │ Compact │ │ Settings │             │
│ ╰──────────╯ ╰─────────╯ ╰──────────╯             │
╰───────────────────────────────────────────────────╯
╭ Usage ──────────────────────────── $4.85 · $2.35/h ╮
│ 5h  ▰▰▰▰▰┊▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱  23%     │
│     resets in 3h40m · on pace                     │
╰───────────────────────────────────────────────────╯
╭ Agents & shells ─────────────── $ 1 ● 1 running ✓ 2 ╮
│ $ npm run dev 12m                                 │
│ ● impl-sonnet-low Task 4 4m                       │
│ ✓ reviewer-opus Review task 3                     │
│ Seats by input                                    │
│   impl-sonnet-low ×1                              │
│   ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰ 120k in · 80% cached · 7k out  │
╰───────────────────────────────────────────────────╯
╭ Run ──────────────────────────────── round 2 · 3/6 ╮
│ ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱ │
│ docs/plans/cockpit.md                             │
│ ✓ Task 3: Draw the context section · clean        │
│ ▸ Task 4: Draw usage and agents                   │
│   round 2 · impl-sonnet-low                       │
│ ○ Task 5: Track the plan and repo                 │
╰───────────────────────────────────────────────────╯
╭ Repo ─────────────────────────────────── ● dirty ╮
│ ⎇ feat/cockpit-pane-overhaul ↑3                   │
│ ~2 changed ?1 untracked                           │
╰───────────────────────────────────────────────────╯
```

The context track runs over the whole window: the fill is the reading, `┃` the
handoff budget and `┊` where auto-compaction runs. The trend line is the
session's recent readings. The colored bar splits the context by `/context`
category, each color matching its row. On a usage-limit meter `┊` marks how far
through its window the limit is, so a fill past it is spending faster than the
window refills.

- **Now** is the turn in flight: running with its time, step, tool and the
  subagent calling it; waiting for your approval; Claude asking you something;
  idle with the last turn's length; the last turn failed; or Esc
  interrupted it, with the background shells and agents still running after
  it (Esc stops the turn, not them). It adds
  `Discord ✓` once a notification went out for what it shows.
- **Account** is who the session runs as: the email, name, organization and
  role from the account's `.claude.json` (under `CLAUDE_CONFIG_DIR` when set),
  the billing type, the model and effort the last request used, Remote Control,
  and the config directory. Remote reads `connected` with the devices attached
  (a phone, the desktop app), `on · no device yet` when "Enable Remote Control
  for all sessions" is on in `/config`, and `not connected` otherwise; a session
  started with `/remote-control` reads `not connected` until a device joins. Its frame takes the color `dr-status` assigns the account in
  `~/.claude/dcc-statusline.json` (`DCC_STATUSLINE_CONFIG` when set).
- **Context** is the main session against its handoff budget, the window and
  where auto-compaction runs, and the largest `/context` categories, estimated
  locally with no API calls. The title adds about how many turns are left to
  the budget at the pace of the last few. **Hand off** appears in
  `dr-superpowers` sessions; **Resume** (`r`) appears outside them when
  `.superpowers/handoff/latest.md` is under three days old, and queues the
  prompt that resumes it.
- **Usage** is the account's 5-hour and 7-day limits with their resets, and the
  session's cost and cost per hour. Once a window is ten minutes old each meter
  says whether the limit lasts to its reset at the pace so far (`on pace`), or
  when it runs out first, in amber.
- **Agents & shells** lists the background shells still running (a Bash call
  sent to the background, by Claude or with Ctrl+B) with how long each has run,
  until its notification or a stop ends it; then the subagents running and
  recently finished, then each
  subagent type (seat) with its runs, input tokens, the share served from the
  prompt cache and output tokens. Use it to see where a plan's tokens go.
- **Plan** follows the main session's todo list or task list, centred on the
  item in progress. In a `dr-superpowers` run it becomes **Run**, read from the
  run's ledger (`.superpowers/sdd/<run>/progress.md`) and its plan: the review
  round in flight, the tasks done, which were reviewed clean, and a blocked
  task in red with its reason.
- **Repo** is the working tree's branch, ahead and behind counts and changes.
- **Guard** lists commits and pull requests the attribution guard refused.

When the pane sits above the prompt (`layout` `auto`, the default), it draws
what `dr-status` draws, with the cockpit's buttons under it: the frame in the
account's color with its email on the top rule, the path, branch, model and
effort, then the context, cache, cost and limit meters. A running turn rides on
the top rule's right end, a `dr-superpowers` run adds `run 3/6 r2` to the first
line, past `warnAt` a `handoff 86%` reading follows `ctx`, and the bottom rule
counts the background shells running and names the Remote Control devices
attached:

```
╭─ you@example.com ──────────────────────────────────────────────────────────────── ● 2m14s · Bash ─╮
│ darkraise-ai-plugins/…/dr-cockpit · feat/cockpit-pane-overhaul* · Opus · xhigh · run 3/6 r2      │
│ ctx ▰▰▱▱ 41% · cache ▰▰▰▱ 93% · $4.85 · 5h ▰▱▱ 23% · 7d ▰▰▱ 61%                                  │
╰─ $ 2 shells · ● phone ───────────────────────────────────────────────────────────────────────────╯
╭──────────╮ ╭─────────╮ ╭──────────╮
│ Hand off │ │ Compact │ │ Settings │
╰──────────╯ ╰─────────╯ ╰──────────╯
```

Each line shrinks the way `dr-status`' do, a step at a time until it fits: the
path drops what leads to the repository, then its middle, then all but the
leaf; the branch drops its counters, then shortens; the model drops its
version; the meters narrow, drop the token count and reset times, and at last
show the percentage alone. Below 48 columns the frame goes and the email takes
a line of its own above them. The pane draws no Nerd Font icons. The context
meter is the share of the model's window, as `dr-status` shows it.

Each button sits in a rounded box, the letter of its hotkey underlined in the
label as a desktop app marks one; the hotkey presses it while the pane has the
keyboard: `h` **Hand off**, `r` **Resume**, `c` **Compact**, `s` **Settings**,
and `b` **Back** in the settings view. Before Claude Code 2.1.295, which first
draws a styled label, the hotkey leads the label instead (`c: Compact`). The box is gray at rest and takes the accent color on the one
that matters: **Hand off** once the context passes `warnAt`, **Resume**
whenever it shows. In the settings view a switch reads `● On` or `○ Off`, the
chosen option of a row takes the accent, and what is off is drawn dim.

**Settings view.** **Settings** (or `/cockpit settings`) turns the pane into the
mod's settings: whether it shows at session start, the layout, which sections
show, the handoff budget, where the strip's handoff reading and the limit alert
appear, how many context rows to list, the note and guard switches, and the
Discord notifications. Each press saves
the setting the way `/config` does, and the pane redraws with it. **Back** (`b`)
returns to the cockpit.


The breakdown and the repo are read after each turn while the pane is open, and
when it opens; nothing in the pane costs the model context.

**Limit alerts.** When the 5-hour or 7-day limit crosses 90%, a toast says so
once, with when it resets; it can say so again after the window resets.

**Handoff reading.** The handoff reading shows only in the cockpit: the
Context card, and the strip's `handoff N%` once the context reaches `warnAt`
(yellow, red past the budget). The main session re-reads its whole context on every request, so a session that
runs past its budget pays for it on each turn after. In a session running
`dr-superpowers` (one that has loaded one of its skills or started one of its
agents), **Hand off** queues a prompt asking the controller to finish the task
in flight and hand off with the `handoff` skill. Past the budget the mod also
adds one note to the conversation saying the same, so a controller deep in a
long turn sees it before its next task. A compaction clears the reading until
the next response, and re-arms the note.

**Discord notifications.** The mod can post to a Discord channel when the
session needs you, which works the same over ssh and tmux. Create a webhook
(channel settings → Integrations → Webhooks → copy URL) and paste it in the
settings view's **Notifications** group, or run `/cockpit notify url <url>`.
It is kept in the plugin's own store, not in `settings.json`, and only ever
shows masked; `DR_COCKPIT_NOTIFY_URL` in the environment wins over it. **Send
test** (or `/cockpit notify test`) posts a sample. Set your Discord user id
(**Mention**, or `/cockpit notify mention <id>`) to be pinged for the events
that need you; everything else posts silently.

| Event | When | Default | Pings |
| --- | --- | --- | --- |
| `ask` | A tool call waits for your approval past `notifyAskAfter`; the message is edited once you approve or deny it | on | yes |
| `question` | Claude asks you something or has a plan ready, likewise | on | yes |
| `done` | A turn ends after running at least `notifyAfter` seconds | on | no |
| `error` | A turn fails | on | yes |
| `blocked` | A `dr-superpowers` task is blocked | on | yes |
| `budget` | The context crosses the handoff budget | on | no |
| `limit` | A usage limit crosses `limitAlertAt` | on | no |
| `task` | A run's task completes, or its final review is clean | off | no |
| `session` | The session ends, with its resume command | off | no |
| `agent` | A subagent finishes | off | no |

Each message names the host, repository, branch, account and tmux session it
came from. Command and answer excerpts are cut short and pass through a
redactor that masks common tokens and `key=`/`token=`/`password=` values;
`notifyDetail` `brief` leaves them out. A turn you interrupt sends nothing, and
approvals are not watched when the session runs in `auto`, `bypassPermissions`
or `dontAsk` mode.

**State file for dr-status.** The mod writes the turn's state and the run's
progress to `<config dir>/dr-cockpit/state/<session id>.json`, and `dr-status`
draws them as its `turn` and `run` segments.

**Attribution guard.** Claude Code asks the model to add a `Co-Authored-By`
trailer to commits and a "Generated with Claude Code" footer to pull requests.
The mod blanks both where the engine composes them, and refuses a `git commit`,
`gh pr create`/`edit` or GitHub pull-request tool call that still carries AI
attribution (an AI `Co-Authored-By`, `Claude-Session`, "Generated with Claude
Code" or a Claude session link). Human co-authors pass.

## Settings

Set these in the pane's settings view, in `/config` under the plugin's rows, or
in your user settings
(`~/.claude/settings.json`; project settings are not read) under
`pluginConfigs["dr-cockpit@darkraise"].options`, then start a new session:

```json
{
  "pluginConfigs": {
    "dr-cockpit@darkraise": {
      "options": { "layout": "compact", "sections": "context,usage,plan", "warnAt": 70 }
    }
  }
}
```

| Option | Default | Effect |
| --- | --- | --- |
| `handoffTokens` | `0` | The handoff budget in tokens. `0` follows `DR_SUPERPOWERS_BUDGET`, else `dr-superpowers`' own rule: 93% of the smaller of `autoCompactWindow` and the model's window, minus 140,000 (465k at 650k, 604k on a 1M model with `autoCompactWindow` at 800k). Windows too small for that rule get a fifth of the window. |
| `nudgeModel` | `true` | Add the one note to the conversation at the budget, in `dr-superpowers` sessions. |
| `guardAttribution` | `true` | Blank the engine's attribution text and refuse git writes that carry it. |
| `warnAt` | `80` | Where the strip's handoff reading appears, as a percentage of the handoff budget (1-99). |
| `layout` | `auto` | `auto`: the full layout docked beside the transcript, the compact strip (the `dr-status` lines and the buttons) above the prompt. `full` or `compact`: always that one. |
| `sections` | empty | The pane's sections and their order, comma-separated: `account`, `context`, `usage`, `agents`, `plan`, `repo`, `guard`. Empty shows all seven. The compact strip always draws the `dr-status` lines. |
| `breakdownRows` | `6` | How many `/context` categories the Context section lists, largest first, up to 12. `0` hides them. |
| `openAtStart` | `true` | Open the pane when a session starts. Claude Code shows it once the terminal is 144 columns wide (110 once you have opened it before); `/cockpit` opens it at any width. |
| `limitAlertAt` | `90` | The usage-limit alert's line, in percent. `0` turns the alert off. |
| `notifyOn` | empty | The Discord events to send, comma-separated (see above). Empty sends the default set; `none` sends nothing. |
| `notifyAfter` | `60` | Seconds a turn must run before `done` sends. `0` sends every turn. |
| `notifyAskAfter` | `20` | Seconds an approval or question waits before it sends. `0` sends at once. |
| `notifyDetail` | `full` | `full` includes command and answer excerpts; `brief` sends titles and fields only. |

## Install

```text
/plugin marketplace add darkraise/darkraise-ai-plugins
/plugin install dr-cockpit@darkraise
```

An installed copy stays at the version it was installed at. To take a new
release, run `claude plugin update dr-cockpit@darkraise` and start a new session
(or run `/reload-plugins`).

## Development

```text
claude plugin validate plugins/dr-cockpit
claude plugin test plugins/dr-cockpit
claude --plugin-dir plugins/dr-cockpit
```

The last loads the working copy into a session and reloads it on save. The
engine lays its type declarations under `.claude-plugin/types/` when it loads
the folder; they are not committed.
