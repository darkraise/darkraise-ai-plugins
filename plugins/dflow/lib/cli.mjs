import { context } from './repo.mjs';
import { CliError } from './util.mjs';

export const COMMANDS = {
  init: ['commands/init.mjs', 'scaffold docs/dflow in this repository'],
  plan: ['commands/plan.mjs', 'new | check | approve | use — create, lint, approve or select a plan'],
  status: ['commands/status.mjs', 'where the work stands and the one next step'],
  next: ['commands/next.mjs', 'start the next ready task and print its brief'],
  done: ['commands/done.mjs', 'verify a task, tick it and commit: done <N> -m "<message>"'],
  block: ['commands/block.mjs', 'record a hard blocker: block <N> "<reason>"'],
  unblock: ['commands/block.mjs', 'clear a blocker: unblock <N> "<what changed>"'],
  log: ['commands/log.mjs', 'append a plan log line: log <N|-> <D|G|N> "<text>"'],
  amend: ['commands/amend.mjs', 'change a task\'s verify command with a logged reason'],
  gate: ['commands/gate.mjs', 'run the project gates and record the result'],
  doctor: ['commands/doctor.mjs', 'check docs budgets, dead references, the board and open plans'],
  review: ['commands/review.mjs', 'pack | add | list | verify | resolve | judge | record'],
  proof: ['commands/proof.mjs', 'record UI evidence for an acceptance line'],
  ship: ['commands/ship.mjs', 'check the definition of done and close the plan'],
  sync: ['commands/sync.mjs', 'push | pull | status — the darkmem projection'],
  wave: ['commands/parallel.mjs', 'list worker tasks that can run at the same time'],
  worktree: ['commands/parallel.mjs', 'add | merge | drop a worker worktree'],
  plans: ['commands/parallel.mjs', 'list open plans across worktrees; --conflicts'],
  session: ['commands/parallel.mjs', 'print the command that starts a background session for a plan'],
  cost: ['commands/cost.mjs', 'token use of a plan by phase and model'],
  context: ['commands/context.mjs', 'the session\'s context size and the reset threshold'],
  hook: ['commands/hook.mjs', 'session-start | pre-compact | stop — hook entry points'],
};

function usage(out) {
  out('dflow <command> [arguments]');
  for (const [name, [, summary]] of Object.entries(COMMANDS)) out(`  ${name.padEnd(9)} ${summary}`);
}

export async function main(argv, { cwd = process.cwd(), env = process.env, out = line => console.log(line), err = line => console.error(line) } = {}) {
  const [name, ...rest] = argv;
  if (!name || name === 'help' || name === '--help' || name === '-h') {
    usage(out);
    return name ? 0 : 2;
  }
  const entry = COMMANDS[name];
  if (!entry) {
    err(`dflow: unknown command ${JSON.stringify(name)}; run \`dflow help\``);
    return 2;
  }
  let ctx;
  try {
    ctx = context(cwd, env);
  } catch (error) {
    // A hook that fires outside a repository has nothing to do and says nothing.
    if (name === 'hook') return 0;
    if (!(error instanceof CliError)) throw error;
    err(`dflow ${name}: ${error.message}`);
    return error.code;
  }
  try {
    const module = await import(new URL(entry[0], import.meta.url));
    const code = await module.run(ctx, rest, { out, err, name });
    return code ?? 0;
  } catch (error) {
    if (!(error instanceof CliError)) throw error;
    err(`dflow ${name}: ${error.message}`);
    return error.code;
  }
}
