# dr-cockpit

A Claude Code mod for long sessions, and for `dr-superpowers` plans in
particular. It is a hooks module, not a set of skills, so it costs the model no
context: it draws in the interface and acts on the engine's events.

Claude Code only. Built and tested against Claude Code 2.1.292 and 2.1.294; the
mod API is early access and may change between releases.

## What it does

**Cockpit pane.** A pane with the session at a glance. It opens by itself when
a session starts, once the terminal is 144 columns wide; `/cockpit` opens it at
any width, and says why if Claude Code holds it back. In fullscreen at 110
columns or more it docks beside the transcript; otherwise it sits above the
prompt. In the full layout each section is a framed card in its own color, its
headline on the title line:

```
╭ Context ─────────────────────────── 68% of handoff ╮
│ ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▱▱▱▱▱▱▱┃▱▱▱▱▱┊▱▱▱▱▱▱▱▱▱▱▱▱▱▱ │
│ 412k of 1.0M ┃ handoff 604k ┊ compacts 744k      │
│ trend ▁▂▃▃▄▄▅▆▆▇▇█ +23k                           │
│ ██████████████████████████████████████▓▓▓▓▒▒▒░░  │
│   ■ Messages              318k  78%               │
│   ■ System tools           41k  10%               │
│ [ Hand off ] [ Compact ] [ Settings ]             │
╰───────────────────────────────────────────────────╯
╭ Usage ──────────────────────────── $4.85 · $2.35/h ╮
│ 5h  ▰▰▰▰▰┊▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱  23%     │
│     resets in 3h40m · 27% of the window gone      │
╰───────────────────────────────────────────────────╯
╭ Agents ───────────────────────── ● 1 running ✓ 2 ╮
│ ● impl-sonnet-low Task 4 4m                       │
│ ✓ reviewer-opus Review task 3                     │
│ Seats by input                                    │
│   impl-sonnet-low ×1                              │
│   ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰ 120k in · 80% cached · 7k out  │
╰───────────────────────────────────────────────────╯
╭ Plan ─────────────────────────────────────── 3/6 ╮
│ ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱ │
│ ✓ Task 3: Draw the context section                │
│ ▸ Task 4: Draw usage and agents                   │
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

- **Context** is the main session against its handoff budget, the window and
  where auto-compaction runs, and the largest `/context` categories, estimated
  locally with no API calls. **Hand off** appears in `dr-superpowers` sessions.
- **Usage** is the account's 5-hour and 7-day limits with their resets, and the
  session's cost and cost per hour.
- **Agents** lists the subagents running and recently finished, then each
  subagent type (seat) with its runs, input tokens, the share served from the
  prompt cache and output tokens. Use it to see where a plan's tokens go.
- **Plan** follows the main session's todo list or task list, centred on the
  item in progress.
- **Repo** is the working tree's branch, ahead and behind counts and changes.
- **Guard** lists commits and pull requests the attribution guard refused.

When the pane sits above the prompt (`layout` `auto`, the default), it switches to
a compact strip of about seven rows, one per section:

```
ctx ▰▰▰▰▰▱▱▱ 68% · 412k/604k · 5h ▰▱▱▱ 23% · 7d ▰▰▱▱ 61% · $4.85
▸ impl-sonnet-low: Task 4 · 4m  +2 done
Plan 3/6 ▸ Task 4: Draw usage and agents
feat/cockpit-pane-overhaul ↑3 · 2 changed · 1 untracked
guard refused 1 git write
[ Hand off ] [ Compact ]
```

Under 90 columns the usage meters take a line of their own. While the pane has
the keyboard, `h` presses **Hand off**, `c` presses **Compact** and `s` opens the
settings.

**Settings view.** **Settings** (or `/cockpit settings`) turns the pane into the
mod's settings: whether it shows at session start, the layout, which sections
show, the handoff budget, where the band and the limit alert appear, how many
context rows to list, and the hint, note and guard switches. Each press saves
the setting the way `/config` does, and the pane redraws with it. **Back** (`b`)
returns to the cockpit.


The breakdown and the repo are read after each turn while the pane is open, and
when it opens; nothing in the pane costs the model context.

**Limit alerts.** When the 5-hour or 7-day limit crosses 90%, a toast says so
once, with when it resets; it can say so again after the window resets.

**Handoff reading.** The hint line under the prompt ends with the main
session's context against its budget, `284k/465k handoff`, in the terminal.

**Handoff band.** A row above the prompt appears once the main session's
context reaches 80% of its handoff budget (`warnAt`), yellow while it nears it
and red past it. **Hide** quiets the warning until the context falls back under
that line; past the budget the band always shows.

```
Nearing handoff: 400k of 465k (86%)  [ Hide ]
Hand off: 470k of 465k (101%)  [ Hand off ]
```

The main session re-reads its whole context on every request, so a session that
runs past its budget pays for it on each turn after. In a session running
`dr-superpowers` (one that has loaded one of its skills or started one of its
agents), **Hand off** queues a prompt asking the controller to finish the task
in flight and hand off with the `handoff` skill. Past the budget the mod also
adds one note to the conversation saying the same, so a controller deep in a
long turn sees it before its next task. A compaction clears the reading until
the next response, and re-arms the note and **Hide**.

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
| `showHint` | `true` | Add the handoff reading to the hint line under the prompt. |
| `warnAt` | `80` | Where the yellow band appears, as a percentage of the handoff budget (1-99). |
| `layout` | `auto` | `auto`: the full layout docked beside the transcript, the compact strip above the prompt. `full` or `compact`: always that one. |
| `sections` | empty | The pane's sections and their order, comma-separated: `context`, `usage`, `agents`, `plan`, `repo`, `guard`. Empty shows all six. |
| `breakdownRows` | `6` | How many `/context` categories the Context section lists, largest first, up to 12. `0` hides them. |
| `openAtStart` | `true` | Open the pane when a session starts. Claude Code shows it once the terminal is 144 columns wide (110 once you have opened it before); `/cockpit` opens it at any width. |
| `limitAlertAt` | `90` | The usage-limit alert's line, in percent. `0` turns the alert off. |

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
