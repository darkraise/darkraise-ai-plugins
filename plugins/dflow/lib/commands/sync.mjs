import { closeStream, loadSync, pull as pullBoard, push, settings, writeCheckpoint } from '../darkmem.mjs';
import { primaryRoot, setDarkmemConsent } from '../repo.mjs';
import { readEvents } from '../state.mjs';
import { refreshHud } from '../status.mjs';
import { fail } from '../util.mjs';

// The quiet callers (done, ship, the hooks) get a short timeout so a slow or
// absent server never holds up the build; whatever is not sent stays queued.
export async function flush(ctx, { quiet = false } = {}) {
  return push(ctx, { timeoutMs: quiet ? 3000 : 10000 });
}

export async function pull(ctx, { quiet = false } = {}) {
  return pullBoard(ctx, { timeoutMs: quiet ? 3000 : 10000 });
}

export async function checkpoint(ctx) {
  return writeCheckpoint(ctx, { timeoutMs: 3000 });
}

export async function closeWorkstream(ctx, slug) {
  return closeStream(ctx, slug, { timeoutMs: 3000 });
}

function say(out, verb, report) {
  if (report.error) out(`darkmem ${verb} stopped: ${report.error}. What was not sent stays queued.`);
  if (report.conflict) out(`darkmem conflict: ${report.conflict}`);
  for (const refusal of report.refused) out(`darkmem refused ${refusal}`);
  const parts = [];
  if (report.documents.length) parts.push(`${report.documents.length} document(s): ${report.documents.join(', ')}`);
  if (report.rows.length) parts.push(`board row ${report.rows.join(', ')}`);
  if (report.entries) parts.push(`${report.entries} work-log entr${report.entries === 1 ? 'y' : 'ies'}`);
  if (!report.error) out(parts.length ? `darkmem ${verb}: ${parts.join('; ')}` : `darkmem ${verb}: nothing to do`);
}

// Consent is the owner's, so it lives in the user's config, never in the
// repository: `enable` agrees to the project the repository names now.
function consent(ctx, action, out) {
  const root = primaryRoot(ctx.root);
  if (action === 'disable') {
    setDarkmemConsent(ctx.env, root, null);
    out(`darkmem disabled for ${root}`);
    return 0;
  }
  const project = ctx.config.darkmem?.project;
  if (!project) fail('the repository names no darkmem project; map one with `dflow init --darkmem <project>`');
  setDarkmemConsent(ctx.env, root, project);
  out(`darkmem enabled for ${root}: its docs go to project "${project}"`);
  const cfg = settings(ctx);
  if (cfg.off) out(`darkmem is still off: ${cfg.off}`);
  return 0;
}

export async function run(ctx, argv, { out }) {
  const action = argv[0] ?? 'status';
  if (action === 'enable' || action === 'disable') return consent(ctx, action, out);
  const cfg = settings(ctx);
  if (cfg.off) {
    out(`darkmem is off: ${cfg.off}`);
    return 0;
  }
  if (action === 'status') {
    const sync = loadSync(ctx);
    out(`darkmem project ${cfg.project} at ${cfg.url}: ${Object.keys(sync.documents).length} document(s) tracked, ${readEvents(ctx.paths).length - sync.cursor} work-log entr(ies) queued`);
    return 0;
  }
  if (action !== 'push' && action !== 'pull') fail('usage: dflow sync push|pull|status|enable|disable');
  const report = action === 'push' ? await flush(ctx) : await pull(ctx);
  if (!report) out(action === 'pull' ? 'darkmem pull: the board is pulled only on the default branch, and one projection runs at a time' : 'darkmem push: another push is running in this checkout');
  else say(out, action, report);
  refreshHud(ctx);
  return report?.error || report?.conflict || report?.refused.length ? 1 : 0;
}
