import { backticked } from './util.mjs';

export const RISKS = ['none', 'security', 'data-loss', 'migration', 'concurrency'];

// Kept identical to darkmem's board parser so both read the same tasks.
const TASK = /^#+[ \t]+(Task[ \t]+([0-9]+)[A-Za-z]*[ \t]*[:.\-]?[ \t]*(.*))$/;
const STEP = /^[ \t]*[-*][ \t]+\[([ xX])\][ \t]+(.*)$/;
const FENCE_OPEN = /^ {0,3}(`{3,}|~{3,})/;
const FIELD = /^\*\*([A-Za-z][A-Za-z ]*):\*\*[ \t]*(.*)$/;
const ACCEPTANCE = /^[ \t]*[-*][ \t]+(A[0-9]+)(?:[ \t]+(UI)(?:[ \t]+(visual))?)?:[ \t]*(.*)$/;
const LOG = /^[ \t]*[-*][ \t]+(\d{4}-\d{2}-\d{2})[ \t]+(T[0-9]+|-)[ \t]+([A-Z]):[ \t]*(.*)$/;
const HEADING = /^(#{1,6})[ \t]+(.*?)[ \t]*$/;

export function splitLines(text) {
  return text.replace(/\r/g, '').split('\n');
}

export function fenceFlags(lines) {
  let marker = '';
  return lines.map(line => {
    if (marker) {
      const body = line.replace(/^ {0,3}/, '').trimEnd();
      if (/^(`+|~+)$/.test(body) && body[0] === marker[0] && body.length >= marker.length) marker = '';
      return true;
    }
    const open = FENCE_OPEN.exec(line);
    if (open) {
      marker = open[1];
      return true;
    }
    return false;
  });
}

function fieldsOf(line) {
  const found = [];
  for (const part of line.split(' · ')) {
    const match = FIELD.exec(part.trim());
    if (match) found.push([match[1].trim().toLowerCase(), match[2].trim()]);
  }
  return found;
}

function list(value) {
  return value.split(',').map(item => item.trim().replace(/^`|`$/g, '')).filter(Boolean);
}

function numbers(value) {
  return (value.match(/[0-9]+/g) ?? []).map(Number);
}

export function parsePlan(text) {
  const lines = splitLines(text);
  const fenced = fenceFlags(lines);
  const plan = {
    title: null, fields: {}, acceptance: [], tasks: [], log: [], sections: {}, lines,
  };
  let section = null;
  let task = null;
  let inAcceptance = false;

  const closeTask = index => {
    if (!task) return;
    task.endLine = index;
    task.done = task.steps.length > 0 && task.steps.every(step => step.checked);
    plan.tasks.push(task);
    task = null;
  };

  lines.forEach((line, index) => {
    if (fenced[index]) return;
    const number = index + 1;
    const heading = HEADING.exec(line);
    const taskMatch = TASK.exec(line);
    if (taskMatch) {
      closeTask(index);
      task = {
        number: Number(taskMatch[2]), label: taskMatch[1].trimEnd(), title: taskMatch[3].trim(),
        level: heading[1].length, line: number, endLine: lines.length, files: [], after: [], run: 'inline', size: 'M', risk: 'none',
        steps: [], verify: [],
      };
      return;
    }
    if (heading) {
      const level = heading[1].length;
      // A heading at the task's own level or above ends the task, so a
      // checklist under `### Rollout` is never read as the task's steps.
      if (task && level <= task.level) closeTask(index);
      if (level === 1 && plan.title === null) plan.title = heading[2];
      if (level <= 2) {
        closeTask(index);
        if (section) plan.sections[section].end = index;
        section = level === 2 ? heading[2].toLowerCase() : null;
        if (section) plan.sections[section] = { start: number, end: lines.length };
        inAcceptance = false;
      }
      return;
    }
    if (task) {
      for (const [key, value] of fieldsOf(line)) {
        if (key === 'files') task.files = list(value);
        else if (key === 'after') task.after = numbers(value);
        else if (key === 'run') task.run = value.toLowerCase();
        else if (key === 'size') task.size = value.toUpperCase();
        else if (key === 'risk') task.risk = value.toLowerCase();
      }
      const step = STEP.exec(line);
      if (step) {
        const entry = { line: number, checked: step[1] !== ' ', text: step[2].trimEnd() };
        task.steps.push(entry);
        if (/^verify:/i.test(entry.text)) task.verify.push(...backticked(entry.text));
      }
      return;
    }
    if (section === null) {
      const fields = fieldsOf(line);
      if (fields.length) {
        inAcceptance = false;
        for (const [key, value] of fields) {
          plan.fields[key] = value;
          if (key === 'acceptance') inAcceptance = true;
        }
        return;
      }
      const item = inAcceptance ? ACCEPTANCE.exec(line) : null;
      if (item) {
        plan.acceptance.push({
          id: item[1], ui: Boolean(item[2]), visual: Boolean(item[3]), text: item[4].trim(),
          commands: item[2] ? [] : backticked(item[4]), line: number,
        });
      }
      return;
    }
    if (section === 'log') {
      const entry = LOG.exec(line);
      if (entry) {
        plan.log.push({
          line: number, date: entry[1], task: entry[2] === '-' ? null : Number(entry[2].slice(1)),
          kind: entry[3], text: entry[4].trim(),
        });
      }
    }
  });
  closeTask(lines.length);
  if (section) plan.sections[section].end = lines.length;
  plan.docs = /^none\b/i.test(plan.fields.docs ?? '') ? [] : list(plan.fields.docs ?? '');
  plan.risk = (plan.fields.risk ?? 'none').toLowerCase();
  return plan;
}

export function blockedTasks(plan) {
  const blocked = new Map();
  for (const entry of plan.log) {
    if (entry.task === null) continue;
    if (entry.kind === 'B') blocked.set(entry.task, entry.text);
    if (entry.kind === 'U') blocked.delete(entry.task);
  }
  return blocked;
}

export function taskStates(plan, planState = {}) {
  const blocked = blockedTasks(plan);
  const done = new Set(plan.tasks.filter(task => task.done).map(task => task.number));
  return plan.tasks.map(task => {
    const record = planState.tasks?.[task.number] ?? {};
    let state = 'todo';
    if (task.done) state = record.reviewPending ? 'review' : 'done';
    else if (blocked.has(task.number)) state = 'blocked';
    else if (record.state === 'wip') state = 'wip';
    return {
      ...task, state, attempts: record.attempts ?? 0, commit: record.commit ?? null,
      blockedReason: blocked.get(task.number) ?? null,
      ready: !task.done && !blocked.has(task.number) && task.after.every(number => done.has(number)),
    };
  });
}

export function nextTask(tasks) {
  return tasks.find(task => task.state === 'wip' && task.ready) ?? tasks.find(task => task.ready) ?? null;
}

export function lintPlan(plan) {
  const errors = [];
  const warnings = [];
  const placeholder = value => !value || /^[….\s]*$/.test(value) || /^<.*>$/.test(value);
  if (!plan.title) errors.push('no title: the first line must be `# <title>`');
  if (placeholder(plan.fields.goal)) errors.push('Goal is empty');
  if (placeholder(plan.fields.branch)) errors.push('Branch is empty');
  if (plan.fields.docs === undefined || placeholder(plan.fields.docs)) errors.push('Docs is empty: name the living docs this change invalidates, or `none — <reason>`');
  else if (/^none\b/i.test(plan.fields.docs) && !/^none\s*[—-]\s*\S/i.test(plan.fields.docs)) errors.push('Docs is `none` without a reason: write `none — <reason>`');
  if (!RISKS.includes(plan.risk)) errors.push(`Risk is ${JSON.stringify(plan.fields.risk)}; use one of ${RISKS.join(', ')}`);
  if (!plan.acceptance.length) errors.push('no Acceptance lines: write `- A1: …` under **Acceptance:**');
  const ids = new Set();
  for (const line of plan.acceptance) {
    if (ids.has(line.id)) errors.push(`Acceptance ${line.id} appears twice`);
    ids.add(line.id);
    if (!line.ui && !line.commands.length) errors.push(`Acceptance ${line.id} names no command in backticks; mark it \`UI\` if it is proven in the running app`);
    if (placeholder(line.text)) errors.push(`Acceptance ${line.id} is empty`);
  }
  if (plan.acceptance.some(line => line.ui) && !plan.sections.ui) errors.push('a UI acceptance line needs a `## UI` section');
  if (!plan.tasks.length) errors.push('no tasks: write `### Task 1: <title>` under `## Tasks`');
  const known = new Set(plan.tasks.map(task => task.number));
  plan.tasks.forEach((task, index) => {
    const name = `Task ${task.number}`;
    if (task.number !== index + 1) errors.push(`${name} is out of order: tasks are numbered from 1 without gaps`);
    if (!task.title) errors.push(`${name} has no title`);
    if (!task.files.length) errors.push(`${name} has no Files`);
    if (!task.steps.length) errors.push(`${name} has no steps`);
    if (!task.verify.length) errors.push(`${name} has no \`Verify:\` step with a command in backticks`);
    if (!['inline', 'worker'].includes(task.run)) errors.push(`${name}: Run is ${JSON.stringify(task.run)}; use inline or worker`);
    if (!['S', 'M', 'L'].includes(task.size)) errors.push(`${name}: Size is ${JSON.stringify(task.size)}; use S, M or L`);
    if (!RISKS.includes(task.risk)) errors.push(`${name}: Risk is ${JSON.stringify(task.risk)}`);
    for (const dependency of task.after) {
      if (!known.has(dependency)) errors.push(`${name} comes after Task ${dependency}, which does not exist`);
      else if (dependency >= task.number) errors.push(`${name} comes after Task ${dependency}; a task depends only on earlier tasks`);
    }
  });
  const fenced = fenceFlags(plan.lines);
  const tasks = plan.sections.tasks;
  if (tasks) {
    let run = 0;
    for (let index = tasks.start; index < tasks.end; index += 1) {
      run = fenced[index] ? run + 1 : 0;
      if (run === 18) warnings.push(`line ${index + 1}: a long code block in Tasks; a plan states decisions, signatures and assertions, not code`);
    }
  }
  return { errors, warnings };
}

function replaceLines(text, edit) {
  const eol = text.includes('\r\n') ? '\r\n' : '\n';
  const lines = text.split(/\r?\n/);
  edit(lines);
  return lines.join(eol);
}

export function tickTask(text, number) {
  const task = parsePlan(text).tasks.find(candidate => candidate.number === number);
  return replaceLines(text, lines => {
    for (const step of task.steps) lines[step.line - 1] = lines[step.line - 1].replace(/\[ \]/, '[x]');
  });
}

export function setField(text, key, value) {
  const plan = parsePlan(text);
  const label = `**${key}:**`;
  return replaceLines(text, lines => {
    const limit = Math.min(...Object.values(plan.sections).map(section => section.start - 1), lines.length);
    const at = lines.findIndex((line, index) => index < limit && line.startsWith(label));
    if (at >= 0) {
      lines[at] = `${label} ${value}`;
      return;
    }
    let insert = limit;
    while (insert > 0 && lines[insert - 1].trim() === '') insert -= 1;
    lines.splice(insert, 0, `${label} ${value}`);
  });
}

export function appendLog(text, { date, task, kind, message }) {
  const entry = `- ${date} ${task ? `T${task}` : '-'} ${kind}: ${message.replace(/\s+/g, ' ').trim()}`;
  const plan = parsePlan(text);
  const eol = text.includes('\r\n') ? '\r\n' : '\n';
  if (!plan.sections.log) return `${text.replace(/\s*$/, '')}${eol}${eol}## Log${eol}${entry}${eol}`;
  return replaceLines(text, lines => {
    let insert = plan.sections.log.end;
    while (insert > plan.sections.log.start && lines[insert - 1].trim() === '') insert -= 1;
    lines.splice(insert, 0, entry);
    if (insert === lines.length - 1) lines.push('');
  });
}

export function setVerify(text, number, commands) {
  const task = parsePlan(text).tasks.find(candidate => candidate.number === number);
  const verifySteps = task.steps.filter(step => /^verify:/i.test(step.text));
  return replaceLines(text, lines => {
    // A task with no verify step gets one after its last step, or after its
    // last non-blank line when it has no steps at all.
    let first = verifySteps[0]?.line - 1;
    if (verifySteps.length === 0) {
      first = task.steps.length ? task.steps.at(-1).line : task.endLine;
      while (!task.steps.length && first > task.line && lines[first - 1].trim() === '') first -= 1;
    }
    const indent = verifySteps.length ? /^[ \t]*/.exec(lines[first])[0] : '';
    for (const step of [...verifySteps].reverse()) lines.splice(step.line - 1, 1);
    lines.splice(first, 0, ...commands.map(command => `${indent}- [ ] Verify: \`${command}\``));
  });
}

export function sectionText(plan, name, limit = Infinity) {
  const section = plan.sections[name];
  if (!section) return [];
  const body = plan.lines.slice(section.start, section.end);
  while (body.length && body[body.length - 1].trim() === '') body.pop();
  while (body.length && body[0].trim() === '') body.shift();
  return body.length <= limit ? body : [...body.slice(0, limit), `… ${body.length - limit} more lines in the plan's ${name} section`];
}

export function taskText(plan, task) {
  const body = plan.lines.slice(task.line - 1, task.endLine);
  while (body.length && body[body.length - 1].trim() === '') body.pop();
  return body;
}

export function template({ title, branch, board }) {
  return `# ${title}

**Board:** ${board} · **Branch:** ${branch}
**Goal:** …
**Acceptance:**
- A1: …
**Docs:** …
**Risk:** none

## Design

- D1: …
- Interfaces: …
- Out of scope: …

## Tasks

### Task 1: …
**Files:** … · **After:** — · **Run:** inline · **Size:** S
- [ ] Test: …
- [ ] Implement …
- [ ] Verify: \`…\`

## Log
`;
}
