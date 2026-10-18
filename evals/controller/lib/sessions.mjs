import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { measureTranscript, sumMetrics } from './transcript.mjs';

export const PROJECTS = process.env.CONTROLLER_EVAL_PROJECTS ?? join(homedir(), '.claude/projects');
export const PLUGIN = fileURLToPath(new URL('../../../plugins/dforge', import.meta.url));
// A pilot repository given by a relative path is a sibling of this one.
export const REPOS = process.env.CONTROLLER_EVAL_REPOS ?? fileURLToPath(new URL('../../../..', import.meta.url));

// Every per-task script takes the plan as its first argument, often as a
// variable the same command assigned (PLAN=docs/…/x.md … task-brief "$PLAN").
// The scripts/ prefix keeps a search for the script name (rg task-brief …) from
// counting as running it, and the optional quote admits a quoted script path.
const PER_TASK = /scripts\/(?:task-brief|review-route|review-package)['"]?[ \t]+(['"]?[^\s;&|]+)/g;
const ASSIGN = /\b([A-Za-z_]\w*)=(['"]?)([^\s'";&|]+)\2/g;

function planArgs(cmd) {
  const vars = Object.fromEntries([...cmd.matchAll(ASSIGN)].map(m => [m[1], m[3]]));
  return [...cmd.matchAll(PER_TASK)].flatMap(m => {
    const arg = m[1].replace(/^['"]|['"]$/g, '').replace(/^\$\{?(\w+)\}?$/, (_, name) => vars[name] ?? '');
    return arg.endsWith('.md') ? [basename(arg, '.md')] : [];
  });
}
// A handoff writes .dforge/handoff/latest.md and runs scripts/next-step.
const BOUNDARY = use => (use.name === 'Bash' && /scripts\/next-step\b/.test(String(use.input?.command ?? '')))
  || (['Write', 'Edit'].includes(use.name) && /handoff\/latest\.md$/.test(String(use.input?.file_path ?? '')));

// projectFolder REPO — the folder Claude Code keeps REPO's transcripts in: the
// absolute path with every character other than a letter or digit as '-'.
export const projectFolder = repo => resolve(repo).replace(/[^A-Za-z0-9]/g, '-');

// transcripts REPO [DIR] — every main-session transcript of REPO and of the
// worktrees inside it. Subagent transcripts sit one level deeper and are not
// listed. Hidden worktree directories (.worktrees, .claude/worktrees) map to
// `<REPO>--…`, a plain worktrees/ directory to `<REPO>-worktrees-…`; any other
// sibling repository whose name starts with REPO's is not REPO.
export function transcripts(repo, dir = PROJECTS) {
  if (!existsSync(dir)) return [];
  const own = projectFolder(repo);
  return readdirSync(dir).flatMap(project => {
    const folder = join(dir, project);
    if ((project !== own && !project.startsWith(`${own}--`) && !project.startsWith(`${own}-worktrees-`)) || !statSync(folder).isDirectory()) return [];
    return readdirSync(folder).filter(name => name.endsWith('.jsonl')).map(name => join(folder, name));
  });
}

function toolUses(file) {
  return readFileSync(file, 'utf8').split('\n').flatMap(line => {
    let r;
    try { r = JSON.parse(line); } catch { return []; }
    return r?.type === 'assistant' && Array.isArray(r.message?.content) ? r.message.content.filter(c => c?.type === 'tool_use') : [];
  });
}

// planSlugs FILE — the plans FILE's session executed: those it ran a per-task
// script on, when it invoked subagent-driven-development. A later plan's
// sessions often name an earlier plan without executing it.
export function planSlugs(file) {
  const uses = toolUses(file);
  if (!uses.some(u => u.name === 'Skill' && /subagent-driven-development$/.test(String(u.input?.skill ?? '')))) return [];
  const slugs = uses.flatMap(u => (u.name === 'Bash' ? planArgs(String(u.input?.command ?? '')) : []));
  return [...new Set(slugs)].sort();
}

// planSessions SLUG REPO [DIR] — the controller sessions of the plan whose
// file is SLUG.md in REPO, oldest first.
export function planSessions(slug, repo, dir = PROJECTS) {
  return transcripts(repo, dir).filter(file => planSlugs(file).includes(slug)).sort((a, b) => statSync(a).mtimeMs - statSync(b).mtimeMs);
}

// inFlight FILE — the background launches still running at a handoff or at
// the end of FILE's session, as scripts/in-flight counts them. Work running
// at a handoff is a slip however it is reported, and a notification after it
// does not undo that.
export function inFlight(file) {
  // inflight_scan hides jq's absence and prints nothing, which would read as no launch running.
  if (spawnSync('jq', ['--version'], { encoding: 'utf8', timeout: 10000 }).status !== 0) throw new Error('inFlight needs jq on PATH');
  const lines = readFileSync(file, 'utf8').split('\n');
  const cuts = [];
  lines.forEach((line, i) => {
    let r;
    try { r = JSON.parse(line); } catch { return; }
    if (r?.type === 'assistant' && Array.isArray(r.message?.content) && r.message.content.some(c => c?.type === 'tool_use' && BOUNDARY(c))) cuts.push(i + 1);
  });
  cuts.push(lines.length);
  const tmp = mkdtempSync(join(tmpdir(), 'controller-inflight-'));
  const running = new Set();
  try {
    for (const cut of cuts) {
      const part = join(tmp, 'part.jsonl');
      writeFileSync(part, lines.slice(0, cut).join('\n') + '\n');
      const r = spawnSync('bash', ['-c', '. "$1/scripts/lib/in-flight.sh"; inflight_scan "$2"', 'in-flight', PLUGIN, part], { encoding: 'utf8', timeout: 120000 });
      if (r.status !== 0) throw new Error(`inflight_scan ${file}: ${String(r.stderr ?? r.error?.message ?? '').trim()}`);
      for (const launch of r.stdout.split('\n').filter(Boolean)) running.add(launch.split(' ')[1]);
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
  return running.size;
}

// measureSessions FILES — the controller metrics of FILES summed, their
// subagents' summed, and the launches each session left running.
export function measureSessions(files) {
  const subagents = files.flatMap(file => {
    const folder = join(dirname(file), basename(file, '.jsonl'), 'subagents');
    if (!existsSync(folder)) return [];
    return readdirSync(folder).filter(name => name.endsWith('.jsonl')).map(name => measureTranscript(readFileSync(join(folder, name), 'utf8')));
  });
  return {
    sessions: files.length,
    controller: sumMetrics(files.map(file => measureTranscript(readFileSync(file, 'utf8')))),
    subagents: sumMetrics(subagents),
    inFlight: files.reduce((sum, file) => sum + inFlight(file), 0),
  };
}

const cents = n => Math.round(n * 100) / 100;

// flatten MEASURED — one row of the numbers the reports compare.
export function flatten(m) {
  const c = m.controller;
  return {
    sessions: m.sessions,
    models: c.models.join('+'),
    efforts: c.efforts.join('+'),
    calls: c.calls,
    dispatches: c.dispatches,
    controllerCost: cents(c.cost),
    subagentCost: cents(m.subagents.cost),
    costPerDispatch: c.dispatches === 0 ? 0 : Math.round((c.cost / c.dispatches) * 1000) / 1000,
    sleeps: c.sleeps,
    listAgents: c.listAgents,
    monitors: c.monitors,
    nudges: c.nudges,
    seatMisses: c.seatMisses,
    inFlight: m.inFlight,
    unpriced: [...new Set([...c.unpriced, ...m.subagents.unpriced])].sort().join('+'),
  };
}
