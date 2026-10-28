# SubagentStop input observed live

**Run:** 2026-10-28, Claude Code 2.1.312. `claude -p --model haiku --plugin-dir plugins/dforge` dispatched `dforge:impl-haiku` once; a hook given by `--settings` logged each `SubagentStop` input and blocked the first two stops with exit 2 and one stderr line.

**agent_type:** `dforge:impl-haiku`, which carries the plugin prefix (`dforge:`). The matcher `(dforge:)?impl-.*` and the gate's own `(^|:)impl-` check both select it.

**Fields of the first stop:** `agent_id`, `agent_transcript_path`, `agent_type`, `background_tasks`, `cwd`, `effort`, `hook_event_name`, `last_assistant_message`, `permission_mode`, `prompt_id`, `session_crons`, `session_id`, `stop_hook_active`, `transcript_path`.

## Stops

| Stop | stop_hook_active | last_assistant_message (first 160 characters) |
|---|---|---|
| 1 | false | `**Status:** DONE / Report: /nonexistent/report.md` |
| 2 | true | `Report: /tmp/tmp.fN0U43J8Go/stops/second.md` |
| 3 | true | `Report: /tmp/tmp.fN0U43J8Go/stops/second.md` |

Exit 2 with a stderr line kept the subagent running: a block was followed by another stop of the same `agent_id`, and the line reached the agent as its next instruction. A retry's final message is whatever the agent says after the block, so the gate's block line asks for the full reply again, `**Status:**` line included.

With the plugin's own `hooks.json` loaded and no logging hook, the same dispatch left a gate counter of 1: the matcher selected the dispatch and the gate blocked it. The gate took 23 ms on a complete 1,000-line report.
