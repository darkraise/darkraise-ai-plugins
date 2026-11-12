import { parseArgs } from 'node:util';
import { formatTokens } from '../context.mjs';
import { phaseBounds, readUsage, summarise } from '../cost.mjs';
import { listPlans } from '../repo.mjs';
import { readEvents } from '../state.mjs';
import { activePlan, loadPlan } from '../status.mjs';
import { fail } from '../util.mjs';

function row(name, totals) {
  const cells = [totals.requests, formatTokens(totals.input), formatTokens(totals.write), formatTokens(totals.read), formatTokens(totals.output), formatTokens(Math.round(totals.equivalent))];
  return `${name.padEnd(28)}${cells.map(cell => String(cell).padStart(9)).join('')}`;
}

export async function run(ctx, argv, { out }) {
  const { values } = parseArgs({ args: argv, options: { plan: { type: 'string' }, json: { type: 'boolean' } } });
  const entry = values.plan
    ? listPlans(ctx.paths).map(file => loadPlan(ctx, file)).find(candidate => candidate.slug === values.plan || candidate.slug.endsWith(`-${values.plan}`))
    : activePlan(ctx);
  if (!entry) fail(values.plan ? `no plan named ${values.plan}` : 'no plan is active on this branch; name one with --plan <slug>');
  const events = readEvents(ctx.paths).filter(event => event.plan === entry.slug);
  if (!events.length) fail(`no recorded events for ${entry.slug} in this checkout; cost is measured where the plan was built`);
  const bounds = phaseBounds(events);
  const until = bounds.shipped ?? (Date.parse(ctx.env.DFLOW_NOW || '') || Date.now());
  const records = readUsage(ctx, { from: bounds.first, to: until, branch: entry.plan.fields.branch });
  const summary = summarise(records, bounds);
  if (values.json) {
    out(JSON.stringify(summary, null, 2));
    return 0;
  }
  if (!records.length) {
    out(`No transcript usage found for ${entry.slug}. Transcripts are kept for about 30 days.`);
    return 0;
  }
  out(`dflow cost · ${entry.slug} · ${new Date(bounds.first).toISOString().slice(0, 16)} to ${bounds.shipped ? new Date(bounds.shipped).toISOString().slice(0, 16) : 'now'}`);
  out(`${''.padEnd(28)}${['requests', 'input', 'write', 'read', 'output', 'equiv'].map(cell => cell.padStart(9)).join('')}`);
  for (const [name, totals] of Object.entries(summary.phases)) out(row(name, totals));
  out(row('total', summary.total));
  out('By model:');
  for (const [name, totals] of Object.entries(summary.models)) out(row(`  ${name}`, totals));
  const agents = Object.entries(summary.agents);
  if (agents.length) {
    out('Subagents:');
    for (const [name, totals] of agents) out(row(`  ${name}`, totals));
    const share = agents.reduce((sum, [, totals]) => sum + totals.equivalent, 0) / summary.total.equivalent;
    out(`Subagents are ${(share * 100).toFixed(0)}% of the total.`);
  }
  out(`Average context per main-session request: ${formatTokens(summary.averageContext)}.`);
  out('equiv = input-token equivalents: cache read ×0.1, cache write ×1.25 (5 min) or ×2 (1 h), output ×5. It compares runs on one model; it is not a price.');
  return 0;
}
