// Every dforge setting: its type, default, the settings-view group and text,
// and where it is stored. An ES module rather than JSON because a Claude Code
// mod imports only code files; the cockpit, scripts/lib/dforge-config.mjs and
// scripts/validate-repository.mjs all import it. Values live in
// ~/.dforge/config.json, whose `darkmem` key is reserved for the darkmem mapping.
//
// The groups are the settings view's tabs, in the order they first appear here.
// label is the row's label there (at most 16 characters); unit and zero say how
// a number reads (`k` is thousands of tokens, zero the word shown at 0).
// enforcedBy names what obeys a workflow key: `script`, the script that already
// makes the decision, or `skill`, through the `dforge-config workflow` line.
// keepDefault writes the key even at its default, for a key whose absence
// means something of its own.
// A value as ~/.dforge/config.json must hold it: exactly the setting's type.
// scripts/lib/dforge-config.mjs and the cockpit's config.ts both call this, so
// the two readers cannot disagree about what the file may contain.
export function isValidValue(spec, value) {
  switch (spec.type) {
    case "boolean": return typeof value === "boolean";
    case "number":
      if (typeof value !== "number" || !Number.isInteger(value)) return false;
      // A floor leaves 0 as the one value below it: "unset".
      if (spec.floor !== undefined) return value === 0 || (value >= spec.floor && (spec.max === undefined || value <= spec.max));
      return (spec.min === undefined || value >= spec.min) && (spec.max === undefined || value <= spec.max);
    case "enum": return typeof value === "string" && (spec.values ?? []).includes(value);
    case "string": return typeof value === "string";
    default: return false;
  }
}

export default {
  openAtStart: {
    type: 'boolean', default: true, group: 'Cockpit', target: 'dforge',
    label: 'Show at start', title: 'Open the pane at session start',
    description: 'Open the cockpit when a session starts. Claude Code shows it once the terminal is 144 columns wide, 110 once you have opened it before; /cockpit opens it at any width.',
  },
  layout: {
    type: 'enum', values: ['auto', 'full', 'compact'], default: 'auto', group: 'Cockpit', target: 'dforge',
    label: 'Layout', title: 'Pane layout',
    description: 'auto: the full layout docked beside the transcript, the band when the pane sits above the prompt. full: always the full layout. compact: minimized, the band above the prompt; Minimize sets it and Expand sets auto, or full where the pane does not dock.',
  },
  sections: {
    type: 'string', default: '', group: 'Cockpit', target: 'dforge',
    label: 'Sections', title: 'Pane sections',
    description: 'Which sections the full pane shows, in order, comma-separated: account, context, usage, shells, agents, plan, repo, guard. Empty shows all eight.',
  },
  collapsed: {
    type: 'string', default: '', group: 'Cockpit', target: 'dforge',
    label: 'Collapsed', title: 'Collapsed sections',
    description: 'Sections drawn as their title row only, comma-separated: account, context, usage, shells, agents, plan, repo, guard. Empty expands all eight.',
  },
  breakdownRows: {
    type: 'number', default: 6, min: 0, max: 12, step: 1, zero: 'hidden', group: 'Cockpit', target: 'dforge',
    label: 'Context rows', title: 'Context breakdown rows',
    description: 'How many /context categories the Context section lists, largest first, up to 12. 0 hides the breakdown.',
  },
  guardAttribution: {
    type: 'boolean', default: true, group: 'Cockpit', target: 'dforge',
    label: 'AI attribution', title: 'Keep AI attribution out of git',
    description: 'Drop the commit trailer and pull request footer Claude Code asks for, and refuse commits and pull requests that still carry AI attribution.',
  },
  handoffTokens: {
    type: 'number', default: 0, min: 0, max: 2_000_000, step: 50_000, unit: 'k', zero: 'auto', env: 'DFORGE_BUDGET', group: 'Context', target: 'dforge',
    label: 'Handoff budget', title: 'Handoff budget (tokens)',
    description: "Context size at which the cockpit and the budget scripts say hand off. 0 follows dforge's rule: 93% of the smaller of autoCompactWindow and the model's window, minus 140,000, and never below a fifth of that window. DFORGE_BUDGET overrides it; relaxed handoff mode ignores it.",
  },
  handoffMode: {
    type: 'enum', values: ['strict', 'relaxed'], default: 'strict', enforcedBy: 'script', group: 'Context', target: 'dforge',
    label: 'Handoff mode', title: 'Handoff mode',
    description: 'strict hands off at the handoff budget. relaxed measures every task against the final-phase limit, 85% of the window, and the handoff budget then has no effect.',
  },
  warnAt: {
    type: 'number', default: 80, min: 1, max: 99, step: 5, unit: '%', group: 'Context', target: 'dforge',
    label: 'Warn at', title: 'Warn at (% of the handoff budget)',
    description: 'Where Hand off takes the accent color, as a share of the handoff budget, 1 to 99.',
  },
  nudgeModel: {
    type: 'boolean', default: true, group: 'Context', target: 'dforge',
    label: 'Handoff note', title: 'Tell the model at the budget',
    description: 'In a session running dforge, add one note to the conversation when the main session crosses its handoff budget.',
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
    type: 'boolean', default: true, enforcedBy: 'script', group: 'Workflow', target: 'dforge',
    label: 'Codex tasks', title: 'Give tasks to Codex',
    description: 'Give plan tasks to Codex when its gate passes. Off keeps every task on Claude.',
  },
  codexReview: {
    type: 'boolean', default: false, enforcedBy: 'script', group: 'Workflow', target: 'dforge',
    label: 'Codex reviews', title: 'Let Codex review',
    description: 'On lets Codex take review seats when its gate passes. Off, the default, keeps every review on Claude; /codex:review or /codex:adversarial-review runs a Codex review on demand.',
  },
  lensCap: {
    type: 'number', default: 4, min: 0, max: 9, step: 1, zero: 'off', env: 'DFORGE_LENS_CAP', enforcedBy: 'script', group: 'Workflow', target: 'dforge',
    label: 'Review lenses', title: 'Final-review lens cap',
    description: 'How many specialist review lenses the final review runs at most, highest priority first. 0 turns them off. DFORGE_LENS_CAP overrides it.',
  },
  executionStrategy: {
    type: 'enum', values: ['ask', 'sequential', 'parallel'], default: 'parallel', enforcedBy: 'skill', group: 'Workflow', target: 'dforge',
    label: 'Strategy', title: 'Execution strategy',
    description: 'How a plan executes. parallel, the default, runs independent tasks in waves and falls back to sequential when no two tasks can share a wave, and on Codex; ask keeps the question.',
  },
  executionMode: {
    type: 'enum', values: ['auto', 'inline', 'subagent'], default: 'auto', enforcedBy: 'skill', group: 'Workflow', target: 'dforge',
    label: 'Execution mode', title: 'Execution mode',
    description: "Who implements plan tasks. auto follows the planner's rule; inline and subagent fix the plan's Execution line, and inline also makes the plan sequential.",
  },
  worktree: {
    type: 'enum', values: ['ask', 'always', 'never'], default: 'ask', enforcedBy: 'skill', group: 'Workflow', target: 'dforge',
    label: 'Worktree', title: 'Worktree',
    description: 'Whether work is isolated in a git worktree before it starts. ask keeps the consent question.',
  },
  autoRun: {
    type: 'enum', values: ['on', 'ask', 'off'], default: 'on', enforcedBy: 'skill', group: 'Workflow', target: 'dforge',
    label: 'Auto run', title: 'Unattended runs',
    description: 'on runs the plan, execution, review and finish unattended once you approve the written spec (Claude Code only; off on Codex). ask offers that once the design is approved. off never runs one.',
  },
  processBias: {
    type: 'enum', values: ['standard', 'lighter', 'heavier'], default: 'standard', enforcedBy: 'skill', group: 'Process', target: 'dforge',
    label: 'Path bias', title: 'Path bias',
    description: 'How readily a request gets a written spec and plan. lighter resolves doubt to a short in-chat design; heavier resolves it to a spec.',
  },
  designApproval: {
    type: 'enum', values: ['sections', 'whole'], default: 'sections', enforcedBy: 'skill', group: 'Process', target: 'dforge',
    label: 'Design approval', title: 'Design approval',
    description: 'sections approves each design section in turn; whole presents the design once with one approval.',
  },
  specReview: {
    type: 'boolean', default: true, enforcedBy: 'skill', group: 'Process', target: 'dforge',
    label: 'Spec review stop', title: 'Stop for spec review',
    description: 'Stop for you to review the written spec before the plan is written. Off goes straight to the plan after the self-review.',
  },
  questionStyle: {
    type: 'enum', values: ['single', 'batched'], default: 'single', enforcedBy: 'skill', group: 'Process', target: 'dforge',
    label: 'Questions', title: 'Clarifying questions',
    description: 'single asks one clarifying question per message; batched asks them all in one message.',
  },
  finishAction: {
    type: 'enum', values: ['ask', 'merge', 'pr', 'keep', 'wait'], default: 'ask', enforcedBy: 'script', group: 'Finish', target: 'dforge',
    label: 'When done', title: 'When the work is done',
    description: 'ask asks before the first task. merge, pr or keep skips the question and runs that action as soon as the final review is clean; wait skips it and shows the finish menu then.',
  },
  limitAlertAt: {
    type: 'number', default: 90, min: 0, max: 100, step: 5, unit: '%', zero: 'off', group: 'Notifications', target: 'dforge',
    label: 'Limit alert at', title: 'Discord usage limit alert (%)',
    description: 'Send the Discord limit message once when the 5-hour or 7-day limit crosses this share, again after it resets. 0 turns it off.',
  },
  notifyOn: {
    type: 'string', default: '', group: 'Notifications', target: 'dforge',
    label: 'Send on', title: 'Discord: events to send',
    description: 'Comma-separated: ask, question, done, error, blocked, budget, limit, task, session, agent. Empty sends ask, question, done, error, blocked, budget and limit; none sends nothing.',
  },
  notifyAfter: {
    type: 'number', default: 60, min: 0, max: 3600, step: 15, unit: 's', zero: 'any', group: 'Notifications', target: 'dforge',
    label: 'Done after', title: 'Discord: done after (seconds)',
    description: 'A finished turn is sent only when it ran at least this long. 0 sends every turn.',
  },
  notifyAskAfter: {
    type: 'number', default: 20, min: 0, max: 600, step: 10, unit: 's', group: 'Notifications', target: 'dforge',
    label: 'Ask after', title: 'Discord: approval after (seconds)',
    description: 'An approval or question is sent only when it is still unanswered after this long. 0 sends at once.',
  },
  notifyDetail: {
    type: 'enum', values: ['full', 'brief'], default: 'full', group: 'Notifications', target: 'dforge',
    label: 'Detail', title: 'Discord: detail',
    description: 'full sends command, question and answer excerpts (secrets masked); brief sends titles and figures only.',
  },
  darkmemEnabled: {
    type: 'boolean', default: false, keepDefault: true, group: 'darkmem', target: 'dforge',
    label: 'Use darkmem', title: 'Use darkmem',
    description: 'Keep a mapped repository\'s documents and progress in darkmem through the mirror. Off keeps both in the repository: a family already in the mirror moves back at the next session start with no plan in progress, from the mirror alone. Left unset after an upgrade, a family a 2.x release put in the mirror stays there unsynced until you choose. A repository is mapped under darkmem.repos in ~/.dforge/config.json.',
  },
  documentStore: {
    type: 'enum', values: ['local', 'darkmem'], default: 'darkmem', group: 'darkmem', target: 'dforge',
    label: 'Documents', title: 'Document store',
    description: 'While Use darkmem is on, where a mapped repository keeps its specs, plans, registers and notes: local in the repository, or darkmem through the mirror. A change moves them at the next session start with no plan in progress.',
  },
  progressSource: {
    type: 'enum', values: ['local', 'darkmem'], default: 'darkmem', group: 'darkmem', target: 'dforge',
    label: 'Progress', title: 'Progress tracking source',
    description: 'While Use darkmem is on, where a mapped repository keeps its plan ledgers and handoffs: local in the repository, or darkmem through the mirror. A change moves them at the next session start with no plan in progress.',
  },
};
