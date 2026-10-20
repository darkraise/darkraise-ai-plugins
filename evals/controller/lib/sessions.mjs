import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { heredocEnd, heredocOpener } from './heredoc.mjs';
import { measureTranscript, sumMetrics } from './transcript.mjs';

export const PROJECTS = process.env.CONTROLLER_EVAL_PROJECTS ?? join(homedir(), '.claude/projects');
export const PLUGIN = fileURLToPath(new URL('../../../plugins/dforge', import.meta.url));
// A pilot repository given by a relative path is a sibling of this one.
export const REPOS = process.env.CONTROLLER_EVAL_REPOS ?? fileURLToPath(new URL('../../../..', import.meta.url));

// Every per-task script takes the plan as its first argument, often as a
// variable the same command assigned (PLAN=docs/…/x.md … task-brief "$PLAN").
// The script is run by a path (scripts/task-brief, $S/task-brief), so the
// required slash keeps a search for the bare name (rg task-brief …) from
// counting as running it. The path must also be a command's first word once
// the words that may precede a command are skipped (BEFORE_COMMAND, an
// assignment, an option, a timeout's duration), so a command that only reads
// the script (cat $S/task-brief …) or quotes a run (echo 'bash …/task-brief …')
// is not a run. A run inside a quoted string (bash -c '…/task-brief x.md') is
// one word too, so it is not counted either. A wrapper is known by its base
// name, so /bin/bash and /usr/bin/env are bash and env.
const SCRIPT = /\/(?:task-brief|review-route|review-package)$/;
const BEFORE_COMMAND = new Set(['!', '{', 'if', 'then', 'elif', 'else', 'while', 'until', 'do', 'bash', 'sh', 'command', 'env', 'exec', 'nohup', 'time', 'timeout']);
const SHELL_OPTION_VALUE = new Set(['-o', '-O', '+o', '+O', '--rcfile', '--init-file']);
const OPTION_VALUE = { env: new Set(['-u']), timeout: new Set(['-k', '-s']), bash: SHELL_OPTION_VALUE, sh: SHELL_OPTION_VALUE };
// A shell's clustered flags take a value when the last of them does (-eo pipefail).
const SHELL_CLUSTER_VALUE = /^[-+][A-Za-z]*[oO]$/;
const takesValue = (wrapper, w) => OPTION_VALUE[wrapper]?.has(w) || ((wrapper === 'bash' || wrapper === 'sh') && SHELL_CLUSTER_VALUE.test(w));
const NOT_A_RUN = { command: new Set(['-v', '-V']) };
// A shell given -n, alone or in a cluster (-nx, -en), or -o noexec (-eo
// noexec) reads the script without running it. A long option (--norc) is not
// a cluster.
const noExec = (wrapper, w, next) => (wrapper === 'bash' || wrapper === 'sh')
  && (/^-[A-Za-z]*n[A-Za-z]*$/.test(w) || (/^-[A-Za-z]*o$/.test(w) && next === 'noexec'));
const ASSIGN = /\b([A-Za-z_]\w*)=(['"]?)([^\s'";&|]+)\2/g;

// simpleCommands CMD — CMD cut at `;`, `&`, `|`, `(`, `)`, a backtick and a
// newline outside quotes, each piece as its words with the quotes removed, so
// a quoted string is one word and never a command. A heredoc's body is data,
// never a command, so it is left out.
function simpleCommands(cmd) {
  const commands = [[]];
  const pending = [];
  let word = null;
  let quote = '';
  const end = () => {
    if (word !== null) commands.at(-1).push(word);
    word = null;
  };
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i];
    const doc = quote ? null : heredocOpener(cmd, i);
    if (quote) {
      if (c === quote) quote = '';
      else word += c;
    } else if (c === "'" || c === '"') {
      quote = c;
      word ??= '';
    } else if (c === ' ' || c === '\t') end();
    else if (doc) {
      pending.push(doc);
      word = (word ?? '') + cmd.slice(i, i + doc.length);
      i += doc.length - 1;
    } else if (/[;&|()`\n]/.test(c)) {
      end();
      commands.push([]);
      if (c === '\n') for (const open of pending.splice(0)) i = heredocEnd(cmd, i, open);
    } else word = (word ?? '') + c;
  }
  end();
  return commands;
}

function planArgs(cmd) {
  const vars = Object.fromEntries([...cmd.matchAll(ASSIGN)].map(m => [m[1], m[3]]));
  return simpleCommands(cmd).flatMap(words => {
    let i = 0;
    let wrapper = '';
    const name = w => (w.includes('=') ? w : basename(w));
    while (i < words.length && !SCRIPT.test(words[i]) && (BEFORE_COMMAND.has(name(words[i])) || /^(?:[A-Za-z_]\w*=|[-+]|\d)/.test(words[i]))) {
      const w = words[i];
      if (NOT_A_RUN[wrapper]?.has(w) || noExec(wrapper, w, words[i + 1])) return [];
      if (BEFORE_COMMAND.has(name(w))) wrapper = name(w);
      i += takesValue(wrapper, w) ? 2 : 1;
    }
    if (!SCRIPT.test(words[i] ?? '')) return [];
    const arg = (words[i + 1] ?? '').replace(/^\$\{?(\w+)\}?$/, (_, name) => vars[name] ?? '');
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
