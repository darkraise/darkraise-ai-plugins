# dr-cockpit

A Claude Code mod for long sessions, and for `dr-superpowers` plans in
particular. It is a hooks module, not a set of skills, so it costs the model no
context: it draws in the interface and acts on the engine's events.

Claude Code only. Built and tested against Claude Code 2.1.292; the mod API is
early access and may change between releases.

## What it does

**Handoff band.** A row above the prompt appears once the main session's
context reaches 80% of its handoff budget, yellow while it nears it and red past
it. **Hide** quiets the warning; past the budget the band always shows.

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
long turn sees it before its next task; a compaction or `/clear` that brings the
context back under re-arms it.

**Cockpit pane.** `/cockpit` opens a pane listing each subagent type (seat)
the session used, with its runs, input tokens, the share served from the prompt
cache and output tokens, beside the main session's context and cost and the last
eight subagents started. Use it to see where a plan's tokens go.

**Attribution guard.** Claude Code asks the model to add a `Co-Authored-By`
trailer to commits and a "Generated with Claude Code" footer to pull requests.
The mod blanks both where the engine composes them, and refuses a `git commit`,
`gh pr create`/`edit` or GitHub pull-request tool call that still carries AI
attribution (an AI `Co-Authored-By`, `Claude-Session`, "Generated with Claude
Code" or a Claude session link). Human co-authors pass.

## Settings

Set these in `/config` under the plugin's rows, or in `settings.json` under
`pluginConfigs["dr-cockpit"].options`.

| Option | Default | Effect |
| --- | --- | --- |
| `handoffTokens` | `0` | The handoff budget in tokens. `0` follows `DR_SUPERPOWERS_BUDGET`, else `dr-superpowers`' own rule: 93% of the model's window minus 140,000 (465k at 650k). |
| `nudgeModel` | `true` | Add the one note to the conversation at the budget, in `dr-superpowers` sessions. |
| `guardAttribution` | `true` | Blank the engine's attribution text and refuse git writes that carry it. |

## Install

```text
/plugin marketplace add darkraise/darkraise-ai-plugins
/plugin install dr-cockpit@darkraise
```

## Development

```text
claude plugin validate plugins/dr-cockpit
claude plugin test plugins/dr-cockpit
claude --plugin-dir plugins/dr-cockpit
```

The last loads the working copy into a session and reloads it on save. The
engine lays its type declarations under `.claude-plugin/types/` when it loads
the folder; they are not committed.
