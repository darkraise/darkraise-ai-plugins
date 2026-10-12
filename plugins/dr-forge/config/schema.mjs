// Every dr-forge setting: its type, default, the settings-view group and text,
// and where it is stored. An ES module rather than JSON because a Claude Code
// mod imports only code files; the cockpit, scripts/lib/forge-config.mjs and
// scripts/validate-repository.mjs all import it. Values live in
// ~/.dr-forge/config.json, whose `darkmem` key is reserved for the darkmem mapping.
//
// The groups are the settings view's tabs, in the order they first appear here.
// label is the row's label there (at most 16 characters); unit and zero say how
// a number reads (`k` is thousands of tokens, zero the word shown at 0).
// enforcedBy names what obeys a workflow key: `script`, the script that already
// makes the decision, or `skill`, through the `forge-config workflow` line.
export default {
  openAtStart: {
    type: 'boolean', default: true, group: 'Cockpit', target: 'forge',
    label: 'Show at start', title: 'Open the pane at session start',
    description: 'Open the cockpit when a session starts. Claude Code shows it once the terminal is 144 columns wide, 110 once you have opened it before; /cockpit opens it at any width.',
  },
  layout: {
    type: 'enum', values: ['auto', 'full', 'compact'], default: 'auto', group: 'Cockpit', target: 'forge',
    label: 'Layout', title: 'Pane layout',
    description: 'auto: the full layout docked beside the transcript, the band when the pane sits above the prompt. full: always the full layout. compact: minimized, the band above the prompt; Minimize sets it and Expand sets auto.',
  },
  sections: {
    type: 'string', default: '', group: 'Cockpit', target: 'forge',
    label: 'Sections', title: 'Pane sections',
    description: 'Which sections the full pane shows, in order, comma-separated: account, context, usage, shells, agents, plan, repo, guard. Empty shows all eight.',
  },
  breakdownRows: {
    type: 'number', default: 6, min: 0, max: 12, step: 1, zero: 'hidden', group: 'Cockpit', target: 'forge',
    label: 'Context rows', title: 'Context breakdown rows',
    description: 'How many /context categories the Context section lists, largest first, up to 12. 0 hides the breakdown.',
  },
  guardAttribution: {
    type: 'boolean', default: true, group: 'Cockpit', target: 'forge',
    label: 'AI attribution', title: 'Keep AI attribution out of git',
    description: 'Drop the commit trailer and pull request footer Claude Code asks for, and refuse commits and pull requests that still carry AI attribution.',
  },
  handoffTokens: {
    type: 'number', default: 0, min: 0, max: 2_000_000, step: 50_000, unit: 'k', zero: 'auto', env: 'DR_FORGE_BUDGET', group: 'Context', target: 'forge',
    label: 'Handoff budget', title: 'Handoff budget (tokens)',
    description: "Context size at which the cockpit and the budget scripts say hand off. 0 follows dr-forge's rule: 93% of the smaller of autoCompactWindow and the model's window, minus 140,000. DR_FORGE_BUDGET overrides it; relaxed handoff mode ignores it.",
  },
  handoffMode: {
    type: 'enum', values: ['strict', 'relaxed'], default: 'strict', enforcedBy: 'script', group: 'Context', target: 'forge',
    label: 'Handoff mode', title: 'Handoff mode',
    description: 'strict hands off at the handoff budget. relaxed measures every task against the final-phase limit, 85% of the window, and the handoff budget then has no effect.',
  },
  warnAt: {
    type: 'number', default: 80, min: 1, max: 99, step: 5, unit: '%', group: 'Context', target: 'forge',
    label: 'Warn at', title: 'Warn at (% of the handoff budget)',
    description: 'Where Hand off takes the accent color, as a share of the handoff budget, 1 to 99.',
  },
  nudgeModel: {
    type: 'boolean', default: true, group: 'Context', target: 'forge',
    label: 'Handoff note', title: 'Tell the model at the budget',
    description: 'In a session running dr-forge, add one note to the conversation when the main session crosses its handoff budget.',
  },
  autoCompactWindow: {
    type: 'number', default: 0, min: 0, floor: 100_000, max: 1_000_000, step: 50_000, unit: 'k', zero: 'unset', group: 'Context', target: 'claude',
    label: 'Auto-compact at', title: "Claude's auto-compaction window (tokens)",
    description: "Claude's autoCompactWindow: 0 leaves it unset, else 100,000 to 1,000,000. Stored in Claude's settings file; applies from the next session.",
  },
  autoCompactEnabled: {
    type: 'boolean', default: true, group: 'Context', target: 'claude',
    label: 'Auto-compact', title: "Claude's auto-compaction",
    description: "Claude's autoCompactEnabled. Stored in Claude's settings file; applies from the next session.",
  },
  codexLane: {
    type: 'boolean', default: true, enforcedBy: 'script', group: 'Workflow', target: 'forge',
    label: 'Codex tasks', title: 'Give tasks to Codex',
    description: 'Give plan tasks to Codex when its gate passes. Off keeps every task on Claude.',
  },
  codexReview: {
    type: 'boolean', default: true, enforcedBy: 'script', group: 'Workflow', target: 'forge',
    label: 'Codex reviews', title: 'Let Codex review',
    description: 'Let Codex take review seats when its gate passes. Off keeps every review on Claude.',
  },
  executionStrategy: {
    type: 'enum', values: ['ask', 'sequential', 'parallel'], default: 'ask', enforcedBy: 'skill', group: 'Workflow', target: 'forge',
    label: 'Strategy', title: 'Execution strategy',
    description: 'How a plan executes. ask keeps the question; parallel falls back to sequential when the parts share files, and on Codex.',
  },
  executionMode: {
    type: 'enum', values: ['auto', 'inline', 'subagent'], default: 'auto', enforcedBy: 'skill', group: 'Workflow', target: 'forge',
    label: 'Execution mode', title: 'Execution mode',
    description: "Who implements plan tasks. auto follows the planner's rule; inline and subagent fix the plan's Execution line, and inline also makes the plan sequential.",
  },
  worktree: {
    type: 'enum', values: ['ask', 'always', 'never'], default: 'ask', enforcedBy: 'skill', group: 'Workflow', target: 'forge',
    label: 'Worktree', title: 'Worktree',
    description: 'Whether work is isolated in a git worktree before it starts. ask keeps the consent question.',
  },
  autoRun: {
    type: 'enum', values: ['ask', 'off'], default: 'ask', enforcedBy: 'skill', group: 'Workflow', target: 'forge',
    label: 'Auto run', title: 'Offer an unattended run',
    description: 'ask offers, once the design is approved, to run the spec, plan, execution, review and finish unattended (Claude Code only). off never offers it.',
  },
  processBias: {
    type: 'enum', values: ['standard', 'lighter', 'heavier'], default: 'standard', enforcedBy: 'skill', group: 'Process', target: 'forge',
    label: 'Path bias', title: 'Path bias',
    description: 'How readily a request gets a written spec and plan. lighter resolves doubt to a short in-chat design; heavier resolves it to a spec.',
  },
  designApproval: {
    type: 'enum', values: ['sections', 'whole'], default: 'sections', enforcedBy: 'skill', group: 'Process', target: 'forge',
    label: 'Design approval', title: 'Design approval',
    description: 'sections approves each design section in turn; whole presents the design once with one approval.',
  },
  specReview: {
    type: 'boolean', default: true, enforcedBy: 'skill', group: 'Process', target: 'forge',
    label: 'Spec review stop', title: 'Stop for spec review',
    description: 'Stop for you to review the written spec before the plan is written. Off goes straight to the plan after the self-review.',
  },
  questionStyle: {
    type: 'enum', values: ['single', 'batched'], default: 'single', enforcedBy: 'skill', group: 'Process', target: 'forge',
    label: 'Questions', title: 'Clarifying questions',
    description: 'single asks one clarifying question per message; batched asks them all in one message.',
  },
  finishAction: {
    type: 'enum', values: ['ask', 'merge', 'pr', 'keep', 'wait'], default: 'ask', enforcedBy: 'script', group: 'Finish', target: 'forge',
    label: 'When done', title: 'When the finish menu goes unanswered',
    description: 'ask keeps the question before the first task. Any other value skips it: merge, pr or keep runs after the wait below; wait never acts.',
  },
  finishTimeout: {
    type: 'number', default: 30, min: 5, max: 240, step: 5, unit: 'min', enforcedBy: 'script', group: 'Finish', target: 'forge',
    label: 'Menu waits', title: 'Finish menu wait (minutes)',
    description: 'How long the finish menu waits before the action above runs.',
  },
  limitAlertAt: {
    type: 'number', default: 90, min: 0, max: 100, step: 5, unit: '%', zero: 'off', group: 'Notifications', target: 'forge',
    label: 'Limit alert at', title: 'Discord usage limit alert (%)',
    description: 'Send the Discord limit message once when the 5-hour or 7-day limit crosses this share, again after it resets. 0 turns it off.',
  },
  notifyOn: {
    type: 'string', default: '', group: 'Notifications', target: 'forge',
    label: 'Send on', title: 'Discord: events to send',
    description: 'Comma-separated: ask, question, done, error, blocked, budget, limit, task, session, agent. Empty sends ask, question, done, error, blocked, budget and limit; none sends nothing.',
  },
  notifyAfter: {
    type: 'number', default: 60, min: 0, max: 3600, step: 15, unit: 's', zero: 'any', group: 'Notifications', target: 'forge',
    label: 'Done after', title: 'Discord: done after (seconds)',
    description: 'A finished turn is sent only when it ran at least this long. 0 sends every turn.',
  },
  notifyAskAfter: {
    type: 'number', default: 20, min: 0, max: 600, step: 10, unit: 's', group: 'Notifications', target: 'forge',
    label: 'Ask after', title: 'Discord: approval after (seconds)',
    description: 'An approval or question is sent only when it is still unanswered after this long. 0 sends at once.',
  },
  notifyDetail: {
    type: 'enum', values: ['full', 'brief'], default: 'full', group: 'Notifications', target: 'forge',
    label: 'Detail', title: 'Discord: detail',
    description: 'full sends command, question and answer excerpts (secrets masked); brief sends titles and figures only.',
  },
};
