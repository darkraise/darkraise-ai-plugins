# Desktop nested sessions and dforge — 2026-10-17

Research spike. Question: how does the Claude Code desktop app structure
sessions that start, watch or coordinate other sessions, and what should
dforge adopt from it? Host checked: Claude Code 2.1.302 on Linux (no desktop
app on this machine, so every desktop statement below comes from the docs).

## Answer in brief

The desktop app has no general parent/child session model. Its sidebar is a
flat list of independent sessions (local, cloud, SSH, WSL), each optionally in
its own worktree. Parent-child structure exists in only three places, and
none of them is open to a plugin:

- **Projects** (public beta, Pro/Max): one coordinator conversation starts
  "threads", which are whole sessions, mostly in the cloud. It shows them in an
  Overview pane grouped by state. Not available from the CLI, and the
  coordinator is Anthropic's, not scriptable.
- **Task chips**: Claude offers out-of-scope work as a chip. The person clicks
  it, and the work starts in a new session with its own worktree.
- **Dispatch** (Cowork tab) can start Code sessions, which get a badge.

Underneath these, the CLI offers background sessions (`claude --bg`, agent
view) and cross-session messaging (`SendMessage`, `ListAgents`,
`notify_when_idle`). Both are local and both work today. A session or a mod can
reach them, but sessions they create are not visible as desktop sidebar
children (see Unknowns).

Recommendation: keep parallel waves on subagents. Adopt the desktop's
state-grouped view in the cockpit (cheap, all APIs exist). Do not move waves
or the auto run's `/clear` onto separate sessions until the experiment below
settles three unknowns.

## The platform, with evidence

### Desktop app

Source: https://code.claude.com/docs/en/desktop (read 2026-10-17).

- "each conversation is a **session**: it has its own chat history and
  project folder, independent of any other session. The sidebar lists your
  sessions and lets you run several in parallel." The sidebar can filter by
  status, project or environment, and group sessions by project. Cmd/Ctrl-click
  opens a second pane.
- Worktree per session is an option next to the branch name. Worktrees go
  under `<project-root>/.claude/worktrees/`, and archiving the session removes
  its worktree. Sessions can auto-archive when their PR merges or closes.
- **Background tasks pane**: "subagents, background shell commands, and
  dynamic workflows" running inside the current session. Clicking one shows
  its output in a subagent pane or stops it. Subagents are therefore already
  visible in the desktop, but inside their session, not as sidebar rows.
- **Work across sessions**: Claude can list, read, message, rename and archive
  "only the sessions the desktop app runs itself: local, SSH, and WSL
  sessions". It "doesn't see cloud sessions, or sessions you started from the
  terminal CLI or the VS Code extension". It sees the 20 most recently active
  sessions. The tool names for this surface are not documented.
- **Task chips**: the person clicks the chip "to start that work in a new
  session with its own worktree". No API or version is documented for it.
- Redesign announcement, 2026-04-14:
  https://claude.com/blog/claude-code-desktop-redesign. It covers the sidebar,
  drag-and-drop panes and side chats. It describes no orchestration API.

### Projects (the desktop's nested model)

Source: https://code.claude.com/docs/en/claude-projects.

- "one coordinating conversation with Claude plus the threads it starts". The
  coordinator "sees what threads report back, not every step they take".
  Threads are "separate session[s] with [their] own context window". A cloud
  thread works on its own branch and opens a PR.
- The Overview pane groups threads as Ready for review, Waiting on you,
  Working, Landing, Idle and Resolved. Desktop notifications fire on errors
  and when input is needed.
- A thread can run on the person's computer through Remote Control (needs
  Claude Code v2.1.280+). Otherwise threads are cloud sessions.
- Limits: "not in the terminal CLI, the VS Code extension, or the JetBrains
  plugin". "You can't add a session you started yourself on your machine to a
  project." Cloud threads do not get locally installed plugins.

### CLI: background sessions and agent view

Sources: https://code.claude.com/docs/en/agent-view, and `claude --help` /
`claude agents --help` on 2.1.302.

- `claude --bg [--name] [--agent <agent>] [--model] [--effort] "<prompt>"`
  starts a full session under a supervisor process. `--bg --resume <id>`
  continues a session in place (v2.1.257+). `claude attach`, `logs`, `stop`,
  `rm` and `respawn` manage it. Verified present in `--help`.
- A dispatched session "moves the session into an isolated git worktree under
  `.claude/worktrees/`" before editing. This can be turned off with
  `worktree.bgIsolation: "none"`.
- `claude agents --json` lists active sessions. Verified: on this host it
  returned the four interactive sessions with `pid`, `cwd`, `kind`,
  `sessionId`, `name` and `status` (`idle`/`busy`). Docs give background
  states as `working`, `blocked`, `done`, `failed` and `stopped`.
- Subagents and teammates "aren't listed as separate rows". There is no
  documented tool for Claude to start a background session. A session can
  still run `claude --bg` from Bash (inferred, not tried).
- An unattached session that is finished or waiting is stopped after about an
  hour unless it is pinned. Usage scales with the number of sessions.

### Cross-session messaging

Source: https://code.claude.com/docs/en/cross-session-messaging (v2.1.224+).

- `ListAgents` and `SendMessage` reach subagents, teammates, other local
  sessions (including background ones), and cloud or Remote Control sessions
  while this session is on Remote Control. Same-machine delivery goes over a
  per-session socket. Verified: `CLAUDE_CODE_MESSAGING_SOCKET` is set in this
  session.
- A message arrives between tool calls, or starts a turn when the receiver is
  idle. It is plain text, never consent, and never runs a command.
- `notify_when_idle` sends one notice when a same-machine session goes idle or
  exits. Only the main conversation can subscribe, and the subscription
  expires after 12 hours.
- **Inbound default:** a session that bypasses permissions holds every
  message from a session that does not. Held messages wait for approval and
  expire after `dialogExpiry` (5 minutes by default). Messages from the
  session's own child processes are delivered. `crossSessionInbound` set to
  `accept`/`hold`/`refuse` overrides the default.

### Agent teams

Source: https://code.claude.com/docs/en/agent-teams.

- Experimental and off by default (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`).
  Teammates run in-process or in tmux/iTerm2 panes.
- "Agent teams don't isolate teammates in worktrees". There is no resume of
  in-process teammates, no nesting, and one team per session. Teammate
  permission prompts appear in the lead.
- When teams are on, an Agent call that has a `name` and no `isolation`
  launches a teammate, "and Claude names ordinary subagents on its own".

### Mod API (host typings, Claude Code 2.1.302)

The source is the `claude-code.d.ts` that the plugin-authoring skill writes.
`plugins/dforge/types/index.d.ts` declares only dforge's own `PluginState`.

| Capability | API | Cross-session? |
|---|---|---|
| Spawn a subagent | `$.agent.spawn({ prompt, description, subagentType, model, name, cwd })` | No. In-session, background. No `isolation` argument; an `$.agent.register` spec can set `isolation: 'worktree' \| 'remote'` |
| List agents | `$.agent.list()` → id, type, description, status (`pending`/`running`/`waiting`/`idle`/`completed`/`failed`/`killed`) | No. This session's subagents and teammates only |
| Message | `$.session.send({ to: { sessionId } \| { agentId }, text })` | **Yes**: any of the person's running sessions, including `session_…` cloud ids. Resolves `isDelivered` or a reason |
| Receive | `session.receive` event (origin `peer`, `coordinator`, plugin name) | Yes |
| Surfaces | `$.session.surfaces()`, `session.attach`/`detach` events | Clients of this session only |
| Start, list or archive another session | none | Only by `$.process.run(['claude', '--bg', …])` or `['claude', 'agents', '--json']` (inferred, untried) |

The cockpit uses none of `session.send`, `session.receive` or `agent.list`
today. It tracks subagents through its own `agent.spawn` hook (`spawns`).

## Mapping onto dforge

What dforge does now:

- Parallel waves dispatch up to 3 Agent calls with `isolation: "worktree"`.
  The controller reviews and merges each one. `context-size --wave` reserves
  140k tokens of controller context per extra task, so the controller's own
  context limits the wave width.
- Fix rounds resume an implementer by its agent id. After compaction "the
  agent id is gone", so the next round is a fresh dispatch.
- In the auto run, the cockpit compacts, or it runs `/clear`, rebinds,
  rewrites `/model` and `/effort`, and submits the resume prompt. It waits
  until no spawn or shell is still running.

### Adoption candidates, ranked

**1. State-grouped wave view in the cockpit, modelled on the Projects Overview.**
- *Gain:* the cockpit shows which wave tasks are Working, Waiting on you (a
  held permission prompt in a subagent), Ready for review or Failed. The
  controller transcript does not show this today.
- *Needs:* `$.agent.list()` status joined to `run.tasks` by agent id.
- *Exists:* yes. The API is verified in the types, but its runtime status
  values have not been observed.
- *Cost/risk:* small and UI only. Risk: `agent.list` drops finished entries
  "seconds after", so done/failed must come from the ledger.

**2. Fleet row in the cockpit, modelled on the desktop sidebar.**
- *Gain:* the cockpit shows the person's other sessions and background
  sessions with their status, including other dforge runs (the auto run
  already refuses a second live run with exit 4).
- *Needs:* `claude agents --json` through `$.process.run` on a slow timer.
- *Exists:* the command is verified on this host. Calling it from a mod is
  untried.
- *Cost/risk:* small. Each poll spawns a process, and the path is
  `/root/.local/bin/claude` here because `claude` is a shell function. It
  shows nothing from desktop-only or cloud sessions.

**3. Keep resumable ids across compaction (adjacent, not desktop-specific).**
- *Gain:* fix rounds after compaction could resume the warm implementer
  instead of a fresh dispatch. The types say a finished subagent "is resumed
  from its transcript with the message".
- *Needs:* the agent id written in the ledger's assigned line, plus a resume
  by `SendMessage`/`$.session.send({ to: { agentId } })` after compaction.
- *Exists:* unknown. It is unverified whether the engine still holds the id
  after compaction. It cannot hold across `/clear`.
- *Cost/risk:* a one-hour probe. If it fails, the fresh dispatch stays.

**4. Opt-in "start in background" for deferred items, modelled on task chips.**
- *Gain:* a deferred register row, or a `discovered:` item, can start as its
  own background session in its own worktree, by the person's press.
- *Needs:* a cockpit button running `claude --bg --name … --agent … "<brief>"`.
- *Exists:* `--bg` is verified. Launching it from a mod is untried.
- *Cost/risk:* moderate. It multiplies quota and leaves sessions and worktrees
  to clean up with `claude rm`. It must never fire in an auto run, which
  forbids side effects outside the worktree.

**5. Wave tasks as background sessions instead of subagents.** Not now.
- *Gain:* only real if each child runs the whole task loop (implement,
  review, fix) and reports a verdict. Then controller growth per task drops
  from about 140k to a report, and children outlive controller compaction and
  `/clear` (the cockpit would no longer wait on them). A person can
  `claude attach` to one.
- *Needs:* `claude --bg --agent <seat>` per task; a report file plus
  `SendMessage` or `notify_when_idle` back to the controller; ledger rules for
  session ids; recovery and cleanup with `claude stop`/`rm`.
- *Exists:* the primitives do. Delivery is not reliable as dforge needs it.
  A controller in bypass mode holds messages from a non-bypass child, and they
  expire after 5 minutes. Whether a `--bg` child counts as an "own child" is
  unknown. Children are not desktop sidebar rows (unknown, probably not).
- *Cost/risk:* high. It means a second execution lane, a nested controller
  with its own budget, a new recovery table, a supervisor process to manage,
  and idle stops after about an hour. It also gives up today's design, where
  the controller judges every task itself.

**6. Replace the auto run's `/clear` with a fresh background session.** No.
- *Gain:* model and effort would come from launch flags, removing the
  `/model`/`/effort` rewrite-and-restore of user settings, a known source of
  trouble.
- *Cost/risk:* the person loses the run from the window they watch. It
  continues headless in agent view, invisible in the desktop. The current
  `/clear` path is verified working.
- *Better fix:* none found in the mod API; `$.command.run` is the only way to
  set the model and effort.

**Not adoptable:**
- *Projects:* cloud-first, closed beta, not in the CLI, and cloud threads do
  not get local plugins, so dforge would not load.
- *Agent teams:* experimental, no worktree isolation, no resume, and
  permission prompts bubble up to the lead. This conflicts with waves.
- *Desktop "work across sessions":* desktop-only, does not see CLI sessions,
  and its tools are undocumented.

## Recommendation

Adopt candidates 1 and 2 as one small cockpit change. Run the probe for
candidate 3. Shelve candidates 5 and 6. The desktop's nesting is a product
surface (Projects, chips) and not an API a plugin can drive. The primitives a
plugin can drive (`--bg`, messaging) make the person lose sight of the work
in the desktop. Today's subagent waves already show in the desktop's
Background tasks pane.

Adjacent hazard: a person who turns on `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`
would turn any dforge Agent call that Claude chooses to `name` (and that has
no `isolation`) into an in-process teammate. Such a teammate runs in the
foreground, cannot be resumed after `/resume`, and puts its prompts in the
lead. dforge never names its calls, but the docs say Claude may. Wave
dispatches are immune because they pass `isolation`.

## Open unknowns and what would settle them

| Unknown | Settle by |
|---|---|
| Do `claude --bg` sessions show in the desktop sidebar? | Start one on a machine with the desktop app and look |
| Is a `--bg` session launched from a session's Bash an "own child" for messaging, so it is delivered under bypass mode? | Start one from a bypass-mode session; have it `SendMessage` the parent; check for a hold notice |
| Does `$.agent.list()` report `waiting` for a subagent held on a permission prompt? | A test mod logging `agent.list()` while a subagent waits on a prompt |
| Can an agent id be resumed by message after compaction? | Dispatch a subagent, `/compact`, then `SendMessage` to its id |
| Is `$.process.run(['claude', …])` allowed and fast enough in a mod timer? | `claude plugin test` with a stub, then one live run |
| Tool names and plugin access for the desktop's work-across-sessions surface | Inspect the tool list in a desktop Code session |
| Does `$.agent.spawn` honor `isolation: 'worktree'` from an `$.agent.register` spec? | A test mod registering an isolated seat and checking the child's `cwd` |
