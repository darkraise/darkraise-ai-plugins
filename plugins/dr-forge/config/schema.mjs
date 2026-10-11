// Every dr-forge setting: its type, default, the settings-view group and text,
// and where it is stored. An ES module rather than JSON because a Claude Code
// mod imports only code files; the cockpit, scripts/lib/forge-config.mjs and
// scripts/validate-repository.mjs all import it. Values live in
// ~/.dr-forge/config.json, whose `darkmem` key is reserved for the darkmem mapping.
export default {
  openAtStart: {
    type: 'boolean', default: true, group: 'Cockpit', target: 'forge',
    title: 'Open the pane at session start',
    description: 'Open the cockpit when a session starts. Claude Code shows it once the terminal is 144 columns wide, 110 once you have opened it before; /cockpit opens it at any width.',
  },
  layout: {
    type: 'enum', values: ['auto', 'full', 'compact'], default: 'auto', group: 'Cockpit', target: 'forge',
    title: 'Pane layout',
    description: 'auto: the full layout docked beside the transcript, the band when the pane sits above the prompt. full: always the full layout. compact: minimized, the band above the prompt; Minimize sets it and Expand sets auto.',
  },
  sections: {
    type: 'string', default: '', group: 'Cockpit', target: 'forge',
    title: 'Pane sections',
    description: 'Which sections the full pane shows, in order, comma-separated: account, context, usage, shells, agents, plan, repo, guard. Empty shows all eight.',
  },
  breakdownRows: {
    type: 'number', default: 6, min: 0, max: 12, step: 1, group: 'Cockpit', target: 'forge',
    title: 'Context breakdown rows',
    description: 'How many /context categories the Context section lists, largest first, up to 12. 0 hides the breakdown.',
  },
  guardAttribution: {
    type: 'boolean', default: true, group: 'Cockpit', target: 'forge',
    title: 'Keep AI attribution out of git',
    description: 'Drop the commit trailer and pull request footer Claude Code asks for, and refuse commits and pull requests that still carry AI attribution.',
  },
  handoffTokens: {
    type: 'number', default: 0, min: 0, max: 2_000_000, step: 50_000, env: 'DR_FORGE_BUDGET', group: 'Context', target: 'forge',
    title: 'Handoff budget (tokens)',
    description: "Context size at which the cockpit says hand off. 0 follows dr-forge's rule: 93% of the smaller of autoCompactWindow and the model's window, minus 140,000. DR_FORGE_BUDGET overrides it.",
  },
  warnAt: {
    type: 'number', default: 80, min: 1, max: 99, step: 5, group: 'Context', target: 'forge',
    title: 'Warn at (% of the handoff budget)',
    description: 'Where Hand off takes the accent color, as a share of the handoff budget, 1 to 99.',
  },
  nudgeModel: {
    type: 'boolean', default: true, group: 'Context', target: 'forge',
    title: 'Tell the model at the budget',
    description: 'In a session running dr-forge, add one note to the conversation when the main session crosses its handoff budget.',
  },
  limitAlertAt: {
    type: 'number', default: 90, min: 0, max: 100, step: 5, group: 'Notifications', target: 'forge',
    title: 'Discord usage limit alert (%)',
    description: 'Send the Discord limit message once when the 5-hour or 7-day limit crosses this share, again after it resets. 0 turns it off.',
  },
  notifyOn: {
    type: 'string', default: '', group: 'Notifications', target: 'forge',
    title: 'Discord: events to send',
    description: 'Comma-separated: ask, question, done, error, blocked, budget, limit, task, session, agent. Empty sends ask, question, done, error, blocked, budget and limit; none sends nothing.',
  },
  notifyAfter: {
    type: 'number', default: 60, min: 0, max: 3600, step: 15, group: 'Notifications', target: 'forge',
    title: 'Discord: done after (seconds)',
    description: 'A finished turn is sent only when it ran at least this long. 0 sends every turn.',
  },
  notifyAskAfter: {
    type: 'number', default: 20, min: 0, max: 600, step: 10, group: 'Notifications', target: 'forge',
    title: 'Discord: approval after (seconds)',
    description: 'An approval or question is sent only when it is still unanswered after this long. 0 sends at once.',
  },
  notifyDetail: {
    type: 'enum', values: ['full', 'brief'], default: 'full', group: 'Notifications', target: 'forge',
    title: 'Discord: detail',
    description: 'full sends command, question and answer excerpts (secrets masked); brief sends titles and figures only.',
  },
};
