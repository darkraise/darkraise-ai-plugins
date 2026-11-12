# dforge

A plugin for Claude Code and Codex. Planning and execution are the harness's
own (plan mode, its task list, its review); dforge adds UI/UX work proven in
the running UI, root-cause debugging, an optional darkmem mirror for a
project's documents, and on Claude Code a cockpit pane with Discord
notifications and an attribution guard. It began as a fork of
[superpowers](https://github.com/obra/superpowers) 6.3.0 (MIT — see
`LICENSES/`). Install `dforge@darkraise` from the repository-root marketplace,
then disable the upstream `superpowers` plugin, `dcc-superpower-companions`
and `andrej-karpathy-skills`: same-named skills in two enabled plugins can
double-trigger.

## What you get

**UI/UX work proven in the running UI.** `dforge:ui-ux` turns a design into a
numbered UI/UX contract (UI, UX and an Output promise), and a walkthrough
proves each item on the running UI — web, Windows, Linux desktop, Android or
terminal — with screenshots and test names as evidence. `scripts/ui-proof check`
holds every "done" claim until the proof covers the current UI files.

**Root-cause debugging.** `dforge:systematic-debugging` finds the cause before
any fix and reproduces the bug with a failing test first.

**Migration from the older names.** `dforge:migrate` moves a repository or
home that dr-superpowers or dr-forge set up (see the migration sections
below).

**darkmem mirror (optional, off by default).** `scripts/darkmem-sync` keeps
  a repository's planning documents and progress in a darkmem instance over
  its keyed REST routes. It does nothing until you opt in: turn on **Use
  darkmem** (`darkmemEnabled`) in the cockpit's darkmem settings or with
  `bash <plugin-root>/scripts/dforge-config set darkmemEnabled true`, and map
  the repository's primary checkout in `~/.dforge/config.json` —
  `{"darkmem": {"url": "http://<host>:8000", "api_key_env": "DARKMEM_API_KEY", "repos": {"<primary checkout path>": {"project": "<name>"}}}}`
  — and export a `dmk_` key in that variable. The repository then syncs a
  mirror at `~/.dforge/mirror/<project>/`, whose documents live under the
  darkmem uri prefix `dforge/`. The key needs the `read` and `capture` scopes,
  and `import --replace` also `admin`. Two settings choose each family's
  store while darkmem is on: `documentStore` (specs, plans, registers, notes)
  and `progressSource` (ledgers and handoffs), `local` or `darkmem`, both
  `darkmem` by default; a mapping entry may override either, for example
  `{"project": "plugins", "documentStore": "local"}`. `~/.dforge/stores.json`
  records where each family actually lives, with its project and mirror, and
  the scripts and skills read and write there through `scripts/lib/roots.sh`
  and `scripts/dforge-path`.
  `pull` fetches what changed; `push` sends documents under their last synced
  hash and each new ledger line as its own entry, with `task`, `state` and
  `commit` properties a progress board can read; `status` lists each family's
  store and local changes;
  `import` files an existing `docs/dforge/` and its ledgers once, verified byte
  for byte. A store that changes moves its family at the next session start
  with no plan in progress and no auto run active:
  `reconcile` copies the files across, verifies every hash, records the new
  store in `stores.json`, and leaves documents leaving the repository as a
  staged `git rm` for you to commit. Every move refuses, naming the reason,
  while a plan is in progress (a ledger whose plan `completed.md` does not
  record) or an auto run is active. A move into darkmem also refuses while
  darkmem is unreachable or the key is unset, while a linked worktree holds
  documents the primary checkout does not, or when a file cannot be carried
  (a dotfile, a symbolic link, an empty or non-UTF-8 file, a name some
  platform cannot hold, a case twin, an ignored file); it never overwrites a different darkmem copy, and moved
  progress files are kept under a dated `moved-<stamp>` backup.
  **Falling back to the file system.** While darkmem is on, the mirror is plain
  local files: without the key or the server, work goes on from it and `pull`
  and `push` say why they skipped. Turn darkmem off (`darkmemEnabled` false) or
  remove the mapping, and the next session start with no plan in progress
  moves every family back into the repository from the mirror alone, without
  asking darkmem, naming each file darkmem does not hold as the mirror does and keeping the mirror
  as a dated `dforge-moved-<stamp>` / `work-moved-<stamp>` backup; until then
  the scripts keep reading the mirror, and `push` and `pull` do nothing. A
  store set back to `local` while darkmem is on and reachable is pulled from
  darkmem first. A repository a 2.x release moved into darkmem stays there,
  unsynced, while `darkmemEnabled` is unset: each session start says so until
  you set it either way. A repository with no mapping but a record that still
  places a family in the mirror is read and reconciled the same way: the
  scripts read the mirror until a session start with no plan in progress
  moves the family back. Session start runs `reconcile` and
  `pull`, and a
  background Stop hook pushes as a safety net in at most 140 seconds: its
  config lookup is bounded at 30 seconds and its push at 100, each sent
  SIGTERM at its bound and SIGKILL 5 seconds later. `push` waits up to 100
  seconds for another run's mirror lock before refusing;
  `DARKMEM_SYNC_LOCK_WAIT_MS` sets that wait in milliseconds, and a value that
  is not a positive number means the 100 seconds. The Stop hook's push never
  waits: it refuses at once while another run holds the lock and the next stop
  sends what it missed. A
  move stopped part-way through filing a ledger resumes it at the next session
  start. A document deleted from the mirror is archived on darkmem under
  `dforge/archive/<stamp>/` and `restore <name>` brings it back;
  `revision <name>` prints the `<name>@r<id>` a distilled `Source:` line
  cites. `docs/superpowers/<rest>` and `docs/dforge/<rest>` name the same
  document everywhere names are compared, so historical plans keep resolving.
  A conflict is reported, never merged. Without a mapping every command but
  `import` prints one line and does nothing.

## Requirements

**Bash, jq and Git.** The scripts need Git 2.31 or later: they ask
`git rev-parse` for `--path-format=absolute`. The hooks read their input with
`jq`; without it the SessionStart hook still injects the entry point and only
skips the session record, and the UI hooks do nothing. `bash` is required for
any hook to run at all. On Windows that means Git for Windows. Each hook
declares `"shell": "bash"` so it takes the Git Bash route explicitly: without
that key Claude Code falls back to PowerShell on a machine with no Git Bash,
where the command is meaningless, and with it the user gets Claude Code's
actionable "requires bash but Git Bash was not found" message instead.

## How it fires

A `SessionStart` hook (matcher `startup|resume|clear|compact`) injects the
`dforge:using-dforge` entry point as `additionalContext`, so every session
starts with the routing to dforge's skills. It adds one line when the
repository still uses an older layout, and darkmem's reconcile and pull
lines for a repository mapped to darkmem. The same script records the
session's `transcript_path`, `session_id`, `cwd` and `source` in
`~/.claude/dforge/sessions/<sanitized-cwd>.json` (last writer wins per
directory), which darkmem's push reads; a record no session start has
rewritten for 30 days is deleted. Malformed stdin skips the record but never
blocks the injection, and the hook always exits 0.

A `UserPromptSubmit` hook records the commits the repository's local branches
point at when a turn starts, under `~/.claude/dforge/sessions/turns/`.

A `PostToolUse` hook on `Edit`, `Write` and `MultiEdit` runs
`scripts/ui-edit-hook.sh`: for a UI file (`scripts/ui-proof paths`) it
returns `scripts/ui-lint` findings as additional context and, once per
session, names `dforge:ui-ux`; it never blocks. A `Stop` hook,
`scripts/ui-turn-end.sh`, holds a turn once when it leaves UI changes without
a passing `ui-proof check` in a project with a UI profile (or a session that
ran the skill); the line `UI proof: pending — <why>` releases it. A second
`Stop` hook pushes to darkmem in the background.

Codex runs no hooks: the Codex manifest declares none. There,
`skills/using-dforge/references/codex-tools.md` names the commands to run by
hand.

## Cockpit

Claude Code only. Built and tested against Claude Code 2.1.299 to 2.1.306; the
mod API is early access and may change between releases.

### What it does

**Cockpit pane.** A pane with the session at a glance. It opens by itself when
a session starts, once the terminal is 144 columns wide; `/cockpit` opens it at
any width, and says why if Claude Code holds it back. In fullscreen at 110
columns or more it docks beside the transcript; otherwise it sits above the
prompt. In the full layout each section is a framed card in its own color, its
headline on the title line, under one **Now** row that says what the
session is doing:

```
● running 2m14s · step 18 · Bash in Explore
╭ Account ──────────────────────────── subscription ╮
│ ● you@example.com                                 │
│   You · Acme (admin)                              │
│   Opus 5.5 · xhigh effort                         │
│   Remote ● connected · phone                      │
│   config ~/.claude                                │
╰───────────────────────────────────────────────────╯
╭ Context ──────────── 68% of compaction · ≈7 turns ╮
│ ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▱▱▱▱▱▱▱▱▱┃▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱ │
│ 412k of 1.0M ┃ compacts 604k                      │
│ trend ▁▂▃▃▄▄▅▆▆▇▇█ +23k                           │
│ ██████████████████████████████████████▓▓▓▓▒▒▒░░   │
│   ■ Messages              318k  78%               │
│   ■ System tools           41k  10%               │
│ ╭───────────╮                                     │
│ │ ⇣ Compact │                                     │
│ ╰───────────╯                                     │
╰───────────────────────────────────────────────────╯
╭ Usage ─────────────────────────── $4.85 · $2.35/h ╮
│ 5h  ▰▰▰▰▰┊▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱  23%     │
│     resets in 3h40m · on pace                     │
╰───────────────────────────────────────────────────╯
╭ Shells ────────────────────────────── $ 1 running ╮
│ $ npm run dev 12m04s                              │
╰───────────────────────────────────────────────────╯
╭ Agents ────────────────────────── ● 1 running ✓ 2 ╮
│ Working · 1                                       │
│ ● Explore Map the settings code 4m17s             │
│ Done · 2                                          │
│ ✓ general-purpose Check the band widths           │
│ ✓ Explore Find the poll timer                     │
│ Seats by input                                    │
│   Explore ×2                                      │
│   ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰ 120k in · 80% cached · 7k out  │
╰───────────────────────────────────────────────────╯
╭ Plan ──────────────────────────────────────── 2/4 ╮
│ ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱  │
│ ✓ Draw the context section                        │
│ ✓ Draw usage and agents                           │
│ ▸ Track the plan and repo                         │
│ ○ Update the README                               │
╰───────────────────────────────────────────────────╯
╭ Repo ──────────────────────────────────── ● dirty ╮
│ repo darkraise/darkraise-ai-plugins               │
│ dir  ~/code/darkraise-ai-plugins/plugins          │
│ ⎇ feat/cockpit-pane-overhaul ↑3                   │
│ ~2 changed ?1 untracked                           │
╰───────────────────────────────────────────────────╯
```

The context track runs over the whole window: the fill is the reading and `┃`
the point where auto-compaction runs. The trend line is the session's recent
readings. The colored bar splits the context by `/context` category, each color
matching its row. On a usage-limit meter `┊` marks how far through its window
the limit is, so a fill past it is spending faster than the window refills.

In the Claude desktop app (its Code tab) the pane is laid out as a flight
deck. The account comes first, then what Claude is doing, then three gauges:
the context against its compaction point with the turns left, and the 5-hour and
7-day limits, each with a tick where its window has run to, its reset and its
forecast. The gauges sit in framed tiles that span the same width as the
panels; a narrow pane moves the context to its own row, then stacks every
tile. Every other section follows as a softly filled panel, a space apart,
its title in the section's color; the usage panel says how far each window has
run. Titles, rows and chips are the desktop's own text in your theme's colors,
so most of them follow the app between light and dark; the gauges, bars,
meters and a few fixed accent colors are drawings. A panel's title collapses
it, as in the terminal.
The buttons are the desktop's own. With **Show at start** on it opens once the
desktop window joins the session, unless you closed it.

- **Now** is the turn in flight: running with its time, step, tool and the
  subagent calling it; waiting for your approval; Claude asking you something;
  idle with the last turn's length; the last turn failed; or Esc
  interrupted it, with the background shells and agents still running after
  it (Esc stops the turn, not them). When a turn ends with its own background
  shells or subagents still running (a review, a test run), it reads
  `◐ background` with the shells, the newest command and the subagents, and the
  Done notification waits: one Done goes out after the turn their notification
  wakes ends, timed from the first turn. A prompt you send starts the count
  again; a subagent's own shells and a service that runs until stopped (a dev
  server, a `--watch` run, `tail -f`) hold nothing; and after 30 minutes the
  Done goes out anyway. It adds `Discord ✓` once a notification went out for
  what it shows.
- **Account** is who the session runs as: the email, name, organization and
  role from the account's `.claude.json` (under `CLAUDE_CONFIG_DIR` when set),
  the billing type, the model and effort the last request used, Remote Control,
  and the config directory. Remote reads `connected` with the devices attached
  (a phone, the desktop app), `on · no device yet` when "Enable Remote Control
  for all sessions" is on in `/config`, and `not connected` otherwise; a session
  started with `/remote-control` reads `not connected` until a device joins. Its frame takes one of eight colors picked from the config
  directory, so each account keeps its own. Below it a row holds the pane's own
  buttons: **≡ Dense** (`d`), **⚙ Settings** (`s`) and **▁ Minimize** (`m`);
  with Account hidden the row leads the pane.
- **Context** is the main session against the point where auto-compaction runs
  (the engine's own threshold once the `/context` breakdown names it, else the
  smaller of `autoCompactWindow` and the window), the window, and the largest
  `/context` categories, estimated locally with no API calls. The title adds
  about how many turns are left to that point at the pace of the last few.
  With auto-compaction off the session is measured against the whole window:
  the title reads `of window`, the legend `auto-compact off`, and no point is
  marked. Until a response measures the window (a new session, or just after a
  compaction) it shows the estimate instead, `≈37k estimated`, with the
  categories. A tool call's reading shows as the tool starts. **⇣ Compact**
  stays on the card.
- **Usage** is the account's 5-hour and 7-day limits with their resets, and the
  session's cost and cost per hour. Once a window is ten minutes old each meter
  says whether the limit lasts to its reset at the pace so far (`on pace`), or
  when it runs out first, in amber.
- **Shells** lists the background shells still running (a Bash call sent to
  the background, by Claude or with Ctrl+B) with how long each has run, to the
  second, until its notification or a stop ends it. The card shows only while
  one runs.
- **Agents** lists the subagents in four groups, each with its count and left
  out while empty: **Waiting on you** (a subagent with an approval open),
  **Working**, **Failed** (it ended aborted, refused or with an error) and
  **Done** (recently finished). Running ones are timed to the second. Then
  each subagent type (seat) with its runs, input tokens, the share served from
  the prompt cache and output tokens.
- **Plan** follows the main session's todo list (TodoWrite) or task list
  (TaskCreate and TaskUpdate), centred on the item in progress. The card shows
  only while the list has items.
- **Repo** names the repository (`owner/name` from its remote, else its folder)
  and the working folder, then the branch, ahead and behind counts and changes.
- **Guard** says whether the attribution guard is on (`on · none refused`, or
  `off`) and lists the commits and pull requests it refused.

**Collapsing.** Each section's title is a button: `▾ Usage` collapses the
section to its title row and headline, and `▸ Usage` expands it again. Each
press saves the `collapsed` setting, so the next session opens the same way. A
collapsed Context section keeps its **Compact** button.

**Dense** (`d`) turns the pane into one line per section, in the `sections`
order: the Now row, then `ctx` with a bar, the share of the compaction point and
the turns left, `lim` with the 5-hour and 7-day limits, the background shells
with the newest command, the running subagents, the plan's progress and its
item in progress, the branch and changes, and refusals. A section with
nothing to show is left out; the buttons shrink to one line, and
**Detailed** (`d`) brings the cards back. Each press saves the `density`
setting. In the desktop app the dense rows are text, without the gauges.

**Live readings.** While the pane is up or the cockpit minimized, it checks
`~/.dforge/config.json` and the dforge keys in Claude's settings every two
seconds and puts a change in force, so an edit from `dforge-config`, by hand or
in another session shows without a restart; a file that stops being a JSON
object keeps the settings in force and says so in the settings view. The git
state and the `/context` breakdown are read every ten seconds. Nothing is read
while the cockpit is hidden. The account, Remote Control's `/config` row and
the usage limits keep their own timing.

**Minimize** (`m`) closes the pane. The cockpit then draws as a band directly
above the prompt, across the transcript's width, in the terminal and the
desktop app alike.
**Expand** on the top rule opens the pane again, and so does `/cockpit`. Each
saves the `layout` setting, so the next session opens the same way: a
minimized cockpit starts with the box or band and no pane. `/cockpit settings`
still opens the settings, and **Back** closes them again. Minimize is offered
in the terminal and the desktop app; elsewhere a minimized cockpit shows
nothing until `/cockpit` opens it. The band is also what a pane that is not
docked draws (`layout` `auto`, the default). Its frame takes the account's
color, with the email, billing and Remote Control (`connected`, `on` or
`not connected`, as on the Account card) on the top rule. Its two lines show
the segments the **Minimized** settings tab picks, as dr-status did. By
default the first line has the folder with the branch, ahead and behind counts
and changes, the model and effort, the output style when it is not the
default, the turn (`▸ 2m14s · Bash` while it runs, `approve?` or `asking`
while it waits on you, `turn failed`), the subagents running, and the
background shells with how long the longest has run. The second has the
context against the compaction point with the turns left (no mark while
auto-compaction is off), the prompt-cache hit rate of the last turn, the
session's cost, and the 5-hour and 7-day limits with their pace (`on pace`, or
when the window runs out before it resets). The line holding the agents,
shells or turn leads with `◐` while the background state shows. A refused
command adds a red line.

```
╭─ you@example.com · subscription · Remote ● connected ──────────────────────────────────────────────── Expand ─╮
│ ~/code/shop/web ⎇ feat/pane* ↑2 ↓1 ~1 ?1  ·  Opus 5.5  ·  xhigh  ·  ▸ 2m14s · Bash  ·  ● 1 agent              │
│ ctx ▰▰▰▰▱▱▱┃▱▱ 61% · ≈9 turns  ·  cache ▰▰▰▰▰▰▰▱ 93%  ·  $1.20  ·  5h ▰▰▱▱┊▱▱▱ 23% on pace · 3h40m  ·  7d 61% │
╰───────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

Each line shrinks a step at a time until it fits: the meters narrow and then
show the percentage alone, the labels shorten, and the path keeps the
repository's name. Below 48 columns the frame goes and the email sits beside
**Expand**. The pane draws no Nerd Font icons. In the desktop app the band is
one card with slim meters whose ticks mark how far each window has run.

Each button sits in a rounded box, the letter of its hotkey underlined in the
label as a desktop app marks one; the hotkey presses it while the pane has the
keyboard: `c` **Compact**, `d` **Dense** or **Detailed**, `s` **Settings**, `m` **Minimize**,
and `b` **Back** in the settings view. Before Claude Code 2.1.295, which first
draws a styled label, the hotkey leads the label instead (`c: Compact`). The
box is gray at rest. In the terminal's settings view a switch reads `● On` or
`○ Off`, the open tab and the chosen option of a row take the accent color,
and what is off is drawn dim.

**Settings view.** **Settings** (or `/cockpit settings`) turns the pane into the
mod's settings: whether it shows at session start, the layout and density,
which sections show and which are collapsed, how many context rows to list, the
attribution guard, the minimized band's lines, Claude's auto-compaction
settings, the Discord notifications and the darkmem stores. Each press saves
the setting to `~/.dforge/config.json`, and the pane redraws with it. **Back** (`b`)
returns to the cockpit. In the desktop app each switch and choice is a
dropdown, and each number and text setting an open field that saves when you
submit it (a number keeps its `−` and `+` steps); an entry out of range shows
why below its field.

The breakdown and the repo are read after each turn while the pane is open, and
when it opens; nothing in the pane costs the model context.

The cockpit pops up nothing in the normal course: usage limits show in the
gauges and the band, and a Discord message that fails to send shows in the
settings view. A toast appears only when a setting could not be saved.
`/cockpit` with an argument it does not know answers with its usage.

**Discord notifications.** The mod can post to a Discord channel when the
session needs you, which works the same over ssh and tmux. Create a webhook
(channel settings → Integrations → Webhooks → copy URL) and paste it in the
settings view's **Notifications** group, or run `/cockpit notify url <url>`.
It is kept in the plugin's own store, not in `settings.json`, and only ever
shows masked; `DFORGE_NOTIFY_URL` in the environment wins over it (`DR_COCKPIT_NOTIFY_URL` still read). **Send
test** (or `/cockpit notify test`) posts a sample. Set your Discord user id
(**Mention**, or `/cockpit notify mention <id>`) to be pinged for the events
that need you; everything else posts silently.

| Event | When | Default | Pings |
| --- | --- | --- | --- |
| `ask` | A tool call waits for your approval past `notifyAskAfter`; the message is edited once you approve or deny it | on | yes |
| `question` | Claude asks you something or has a plan ready, likewise | on | yes |
| `done` | A turn ends after running at least `notifyAfter` seconds | on | no |
| `error` | A turn fails | on | yes |
| `limit` | A usage limit crosses `limitAlertAt` | on | no |
| `session` | The session ends, with its resume command | off | no |
| `agent` | A subagent finishes | off | no |

Each message names the host, repository, branch, account and tmux session it
came from. Command and answer excerpts are cut short and pass through a
redactor that masks common tokens and `key=`/`token=`/`password=` values;
`notifyDetail` `brief` leaves them out. A turn you interrupt sends nothing, and
approvals are not watched when the session runs in `auto`, `bypassPermissions`
or `dontAsk` mode.

**Attribution guard.** Claude Code asks the model to add a `Co-Authored-By`
trailer to commits and a "Generated with Claude Code" footer to pull requests.
The mod blanks both where the engine composes them, and refuses a `git commit`,
`gh pr create`/`edit` or GitHub pull-request tool call that still carries AI
attribution (an AI `Co-Authored-By`, `Claude-Session`, "Generated with Claude
Code" or a Claude session link). Human co-authors pass. A call the guard cannot
check is refused.

### Settings

Open the settings with **Settings** in the pane or `/cockpit settings`. They are
one tab per group: press `1` to `5` to switch, `i` to hide or show each
setting's description, and `b` to go back. A row whose value differs from its
default is marked `*` and shows the default with a **Reset**; `r` resets the
whole tab after a second press. Numbers step with `−` and `+` or take a typed
value with **Edit**. A value forced from outside (a project or managed Claude
settings file) shows what forces it and no controls.

The same settings can be set with
`bash <plugin-root>/scripts/dforge-config set <key> <value>` or by editing
`~/.dforge/config.json`:

```json
{ "layout": "compact", "density": "dense", "notifyDetail": "brief" }
```

`dforge-config get --json` prints every value in force. A key the file holds
that no setting names any more is ignored.

| Tab | Option | Default | Effect |
| --- | --- | --- | --- |
| Cockpit | `openAtStart` | `true` | Open the pane when a session starts. Claude Code shows it once the terminal is 144 columns wide (110 once you have opened it before); `/cockpit` opens it at any width. |
| Cockpit | `layout` | `auto` | `auto`: the full layout docked beside the transcript, the band in a pane above the prompt. `full`: always the full layout. `compact`: minimized, no pane, and the band above the prompt. **Minimize** sets `compact`, **Expand** sets `auto` (`full` where the pane does not dock). |
| Cockpit | `density` | `detailed` | `detailed`: cards, charts and lists. `dense`: one line per section. **Dense** and **Detailed** in the pane set it. |
| Cockpit | `sections` | empty | The pane's sections and their order, comma-separated: `account`, `context`, `usage`, `shells`, `agents`, `plan`, `repo`, `guard`. Empty shows all eight. The band draws the lines the Minimized tab picks instead. |
| Cockpit | `collapsed` | empty | Sections drawn as their title row and headline only, comma-separated, from the same eight names. Pressing a section's title collapses or expands it and saves this setting. Empty expands all eight. |
| Cockpit | `breakdownRows` | `6` | How many `/context` categories the Context section lists, largest first, up to 12. `0` hides them. |
| Cockpit | `guardAttribution` | `true` | Blank the engine's attribution text and refuse git writes that carry it. |
| Minimized | `bandLine1` | empty | The minimized band's first line, in order, comma-separated: `dir`, `git`, `model`, `effort`, `style`, `turn`, `agents`, `shells`, `ctx`, `cache`, `cost`, `5h`, `7d`, `time`. Empty shows `dir`, `git`, `model`, `effort`, `style`, `turn`, `agents`, `shells`; `none` hides the line. The tab's chips add a segment last on a line and take it off the other. |
| Minimized | `bandLine2` | empty | The second line, from the same names. Empty shows `ctx`, `cache`, `cost`, `5h`, `7d`; `none` hides it. A name on both lines shows on the first. In the desktop app the picked `ctx`, `cache`, `5h` and `7d` are its meters and the rest its text rows. |
| Context | `autoCompactWindow` | `0` | Claude's own `autoCompactWindow`, written to Claude's user settings file: `0` leaves it unset, else 100,000 to 1,000,000. Applies from the next session. |
| Context | `autoCompactEnabled` | `true` | Claude's own `autoCompactEnabled`, written to the same file. Applies from the next session. |
| Notifications | `limitAlertAt` | `90` | The share at which a usage limit sends the Discord `limit` message, in percent. `0` turns it off. |
| Notifications | `notifyOn` | empty | The Discord events to send, comma-separated (see above). Empty sends the default set; `none` sends nothing. `dforge-config` rejects a value naming an unknown event; one written by hand into the settings file sends nothing. |
| Notifications | `notifyAfter` | `60` | Seconds a turn must run before `done` sends. `0` sends every turn. |
| Notifications | `notifyAskAfter` | `20` | Seconds an approval or question waits before it sends. `0` sends at once. |
| Notifications | `notifyDetail` | `full` | `full` includes command and answer excerpts; `brief` sends titles and fields only. |
| darkmem | `darkmemEnabled` | `false` | Use darkmem for mapped repositories. Off keeps everything in the repository, and a family already in the mirror moves back at the next session start with no plan in progress, from the mirror alone. |
| darkmem | `documentStore` | `darkmem` | While darkmem is on, where a mapped repository keeps its specs, plans, registers and notes: `local` in the repository, `darkmem` through the mirror. A mapping entry's own `documentStore` outranks it; an unmapped repository is local, though a family its record still places in the mirror is read there until a session start with no plan in progress moves it back. |
| darkmem | `progressSource` | `darkmem` | The same choice for plan ledgers and handoffs. A mapping entry's own `progressSource` outranks it. |

The Cockpit, Minimized and Notifications settings apply at once, whether you
change them in the pane, with `dforge-config` or in the file. The two Context
keys are Claude's own, which Claude reads at its next session start.

### Install

```text
/plugin marketplace add darkraise/darkraise-ai-plugins
/plugin install dforge@darkraise
```

An installed copy stays at the version it was installed at. To take a new
release, run `claude plugin update dforge@darkraise` and start a new session
(or run `/reload-plugins`).

### Development

```text
claude plugin validate plugins/dforge
claude plugin test plugins/dforge
claude --plugin-dir plugins/dforge
```

The last loads the working copy into a session and reloads it on save. The
engine lays its type declarations under `.claude-plugin/types/` when it loads
the folder; they are not committed.

## Migrating to 4.0

dforge 4.0 is dr-forge renamed, internals included, and it reads none of the
3.x names:

| 3.x | 4.0 |
|---|---|
| plugin `dr-forge@darkraise`, skills and agents `dr-forge:<name>` | `dforge@darkraise`, `dforge:<name>` |
| `.forge/`, `docs/forge/`, `<git dir>/dr-forge/` | `.dforge/`, `docs/dforge/`, `<git dir>/dforge/` |
| `~/.dr-forge/` | `~/.dforge/` |
| `DR_FORGE_*` environment variables | `DFORGE_*` |
| `scripts/forge-config`, `scripts/forge-path`, `scripts/forge-migrate` | `scripts/dforge-config`, `scripts/dforge-path`, `scripts/dforge-migrate` |
| darkmem documents under `forge/` | `dforge/` |

1. Install dforge, then uninstall dr-forge, so their hooks do not run twice.
   The cockpit's Discord webhook and mention stay in dr-forge's plugin store,
   `~/.claude/plugins/store/dr-forge_darkraise-*.json` (under
   `$CLAUDE_CONFIG_DIR` when set), as `notifyUrl` and `notifyMention`. Copy
   them before you uninstall, then set them in a dforge session with
   `/cockpit notify url <url>` and `/cockpit notify mention <id>`.

       /plugin install dforge@darkraise
       /plugin uninstall dr-forge@darkraise

   On Codex: `codex plugin add dforge@darkraise`, then
   `codex plugin remove dr-forge@darkraise`.

   From dr-superpowers or dr-cockpit, skip dr-forge and install dforge
   directly. Start one dforge session before you uninstall the old plugins:
   it imports dr-cockpit's options and its Discord webhook and mention, once.
   Migrating from dr-superpowers and dr-cockpit below names
   `dr-forge@darkraise`, the plugin of its day; install `dforge@darkraise`
   in its place.
2. In each repository, run `/dforge:migrate` (on Codex, ask for the
   `dforge:migrate` skill). It shows what `scripts/dforge-migrate --dry-run`
   would move, asks once, then moves every checkout and the home, rewrites the
   old plugin prefixes (`dr-forge`, `dr-superpowers`) in plans still in
   progress, and offers to commit what moved. It takes a dr-superpowers
   repository straight to 4.0 as well. Session start names any older path
   still present.
3. Rename any `DR_FORGE_*` variable a shell profile sets to `DFORGE_*`.

darkmem's documents move from `forge/` to `dforge/` at the first sync after
the mirror moved. A name darkmem already holds under `dforge/` is refused,
never overwritten.

The sections below record the earlier migrations under the names of their
day; their steps now run through `/dforge:migrate`.

## Migrating from 0.x

1.0.0 is standalone and breaking. On a machine with the old setup:

1. **Re-point the marketplace.** The `darkraise` marketplace registration in
   `~/.claude/settings.json` may still name `darkraise/claude-code-plugins`;
   the canonical repository is `darkraise/darkraise-ai-plugins`. Remove and
   re-add the marketplace (or edit the registration) to point there.
2. **Statusline.** `dcc-statusline` is `dr-status` in this catalog; enable
   `dr-status@darkraise` and disable the old name.
3. **Telegram notifications.** `dcc-telegram-notify` is not in this catalog;
   keep it installed from its previous source or drop it.
4. **Disable the superseded plugins:** `superpowers` (its skills now ship
   here), `dcc-superpower-companions` (folded into this plugin), and
   `andrej-karpathy-skills` (its guidelines are folded into the skills where
   they fire).

## Migrating from dr-superpowers and dr-cockpit

dr-forge 2.0.0 replaces both plugins. Install dr-forge and start one session
before you uninstall the old plugins, because the first session reads their
saved settings:

    /plugin install dr-forge@darkraise
    /plugin uninstall dr-superpowers@darkraise
    /plugin uninstall dr-cockpit@darkraise

The first session imports the cockpit's options into
`~/.dr-forge/config.json`, and the cockpit's Discord webhook and mention into
dr-forge's own plugin store, once; the old files stay. Since 3.0.0 the
dr-superpowers names are no longer read: see Migrating to 3.0.

## Migrating to 3.0

dr-forge 3.0.0 reads and writes only its own names: `.forge/`, `docs/forge/`,
the git directory's `dr-forge/`, `~/.dr-forge/`, the `DR_FORGE_*` variables
and the `dr-forge:` prefix. The pre-2.0 `.superpowers/`, `docs/superpowers/`,
`dr-superpowers/` and `DR_SUPERPOWERS_*` names and the `dr-superpowers`
prefix are no longer read. Session start prints one line naming
any pre-3.0 directory a repository still has; run, once per repository:

    bash <plugin-root>/scripts/forge-migrate [DIR]

In the primary checkout and every linked worktree it moves `.superpowers/` to
`.forge/`, `docs/superpowers/` to `docs/forge/` (with `git mv` when the
directory is tracked) and `<git dir>/dr-superpowers/` to `<git dir>/dr-forge/`,
then rewrites the lines of `.gitignore`, `.gitattributes` and
`.git/info/exclude` that name the old directories. It prints each move and what
you must commit. A checkout that has both the old and the new directory, or a
`docs/superpowers/` with uncommitted changes, is refused and left as it is;
merge or commit, then run the command again, which does only what is left. It
exits 0 when done or when there was nothing to do, and 1 when something was
refused.

No other file is edited: plans, specs and ledgers that cite
`docs/superpowers/<rest>` keep that spelling, and dr-forge still reads it as
`docs/forge/<rest>`.
Rename any `DR_SUPERPOWERS_*` variable you set to its `DR_FORGE_*` name.
`DR_FORGE_DOCUMENT_STORE` and `DR_FORGE_PROGRESS_SOURCE`, which 2.x read, are
no longer read at all: set `documentStore` and `progressSource` instead.

`forge-migrate` also moves the home: the darkmem mapping in
`~/.dr-superpowers/config.json` into `~/.dr-forge/config.json` when that file
has none, and each `~/.dr-superpowers/mirror/<project>/` that
`~/.dr-forge/mirror/` lacks. darkmem itself is off in 3.0 until you set
`darkmemEnabled`. A mirror's `superpowers/` folder becomes `forge/` at the next
`darkmem-sync` run, and the first online run moves darkmem's `superpowers/`
documents to `forge/`; upgrade every machine that shares a darkmem project,
since a 2.x client no longer sees the moved documents.


## Licenses

MIT. `LICENSES/` carries the licenses of the forked and folded projects:
[superpowers](https://github.com/obra/superpowers) by Jesse Vincent (MIT),
frozen at 6.3.0 with no upstream sync, and
[andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills)
(MIT).

## Tests

```bash
for t in plugins/dforge/tests/*.test.sh; do bash "$t"; done
```

Requires `jq` and `git`. No model calls. `hook.test.sh` drives the
SessionStart hook against temporary homes and repositories.
`darkmem-sync.test.sh` runs the `node:test` suites under `tests/darkmem-sync/`
against an in-memory stub of darkmem's routes, so no darkmem instance is
needed; `darkmem-sync/hooks.test.mjs` drives darkmem's session-start sync and
the background Stop push (`scripts/darkmem-stop-push.sh`) against the stub.
The ui-ux suites — `ui-proof.test.sh`, `ui-lint.test.sh` (one failing and one
passing fixture per rule), `ui-hooks.test.sh` and `ui-ux-skill.test.sh` — run
against temporary repositories and the skill text. `cockpit.test.ts` runs
under `claude plugin test plugins/dforge`.

## Reference

`reference/project-state.md` says where a project's dforge files live, in the
checkout or in the darkmem mirror, and when darkmem syncs them.
