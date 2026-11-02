// Approximate Windows seconds from Actions run 40514782333. That run cut off
// faster-plans and task-step, whose weights are extrapolated from the share of
// their checks that ran, and ui-proof, which keeps its weight from 39725084214.
// Run 40753974623 (2026-10-29) supplied the suites the speed-and-cost plans
// added and those that had grown; task-step-base, cut off there, is
// extrapolated from task-step-settle's Windows-to-Linux ratio.
// Run 41307035161 (2026-11-01) supplied speed-and-cost-followups, whose A12
// part no longer re-runs two suites under test-all (371 s, 0.4 s and 98 s),
// and typed-seats-and-drafting.acceptance.sh.
// These are scheduling weights, not timeouts. The jobs that are not shell
// suites (validate-repository.mjs, the --test jobs, claude plugin test, tsc)
// take the default weight of 10. Every shell suite needs an entry here, with a
// weight of at most 80% of the suite's limit; tests/test-shards.test.mjs
// enforces both. A suite test-all runs in parts splits its weight evenly among
// them.
export const windowsSeconds = {
  'run-all.sh': 157,
  'agy-gate.test.sh': 20,
  'antigravity-executor-lane.acceptance.test.sh': 250,
  'auto-default.test.sh': 10,
  'auto-run-skills.test.sh': 10,
  'auto-run.test.sh': 507,
  'budget-line.test.sh': 123,
  'ci-mirror.test.sh': 60,
  'codex-client.test.sh': 10,
  'codex-gate.test.sh': 122,
  'codex-review.test.sh': 141,
  'context-size.test.sh': 222,
  'criteria.test.sh': 10,
  'darkmem-sync.test.sh': 155,
  'delegated-suite.test.sh': 10,
  'depth-route.test.sh': 88,
  'detect.test.sh': 137,
  'dforge-config.test.sh': 34,
  'dforge-dir.test.sh': 10,
  'dforge-migrate.test.sh': 64,
  'dforge-state.test.sh': 10,
  'distilling-docs.test.sh': 10,
  'draft-pack.test.sh': 40,
  'executor-recovery.test.sh': 295,
  'executor-session.test.sh': 10,
  'executors.test.sh': 10,
  'faster-plans.acceptance.test.sh': 1200,
  'final-phase.test.sh': 10,
  'finish-choice.test.sh': 78,
  'fleet.test.sh': 10,
  'gates-manifest.test.sh': 10,
  'hook.test.sh': 75,
  'impl-clauses.test.sh': 10,
  'impl-stop-gate.test.sh': 64,
  'in-flight.test.sh': 36,
  'inline-mode.test.sh': 65,
  'ladder.test.sh': 10,
  'lane-breaker.test.sh': 10,
  'lanes.test.sh': 10,
  'lens-route.test.sh': 185,
  'lock.test.sh': 10,
  'migrate-skill.test.sh': 10,
  'native-routing.test.sh': 10,
  'next-step.test.sh': 500,
  'parallel-grouping.test.sh': 10,
  'plan-amend.test.sh': 333,
  'plan-lib.test.sh': 43,
  'plan-lint.test.sh': 814,
  'plan-revise.test.sh': 355,
  'polluter.test.sh': 10,
  'process-roles.test.sh': 10,
  'project-status.test.sh': 10,
  'readme-unattended.test.sh': 10,
  'register.test.sh': 68,
  'repo-audit.test.sh': 53,
  'review-depth-qa.acceptance.test.sh': 288,
  'review-depth.acceptance.test.sh': 160,
  'review-route.test.sh': 458,
  'roadmap.test.sh': 125,
  'roots.test.sh': 84,
  'run-agy-task.test.sh': 100,
  'run-codex-task.test.sh': 10,
  'sdd-references.test.sh': 10,
  'seats.test.sh': 10,
  'settings-skills.test.sh': 10,
  'skill-size.test.sh': 10,
  'skill-split-planning.test.sh': 10,
  'snapshot.test.sh': 10,
  'speed-and-cost-followups.acceptance.test.sh': 470,
  'speed-and-cost.acceptance.test.sh': 230,
  'suite-run.test.sh': 54,
  'task-loop-steps.acceptance.test.sh': 720,
  'task-state.test.sh': 47,
  'task-step-base.test.sh': 550,
  'task-step-settle.test.sh': 180,
  'task-step-suite.test.sh': 150,
  'task-step-text.test.sh': 10,
  'task-step.test.sh': 1340,
  'test-simplifier.test.sh': 10,
  'turn-end.test.sh': 251,
  'typed-seats-and-drafting.acceptance.sh': 75,
  'ui-hooks.test.sh': 65,
  'ui-lint.test.sh': 10,
  'ui-proof.test.sh': 195,
  'ui-ux-skill.acceptance.test.sh': 362,
  'ui-ux-skill.test.sh': 10,
  'waiting-text.test.sh': 10,
  'wave.test.sh': 75,
  'working-directory.test.sh': 82,
  'worktree-instructions.test.sh': 10,
};

export function selectShard(jobs, shard) {
  if (shard === undefined) return jobs;
  if (!/^[1-9]\d*\/[1-9]\d*$/.test(shard)) throw new Error('Shard must be INDEX/TOTAL (for example 1/4)');
  const [index, total] = shard.split('/').map(Number);
  if (!Number.isSafeInteger(index) || !Number.isSafeInteger(total) || index > total || total > jobs.length) {
    throw new Error('Shard requires 1 <= INDEX <= TOTAL <= number of suites');
  }
  const buckets = Array.from({ length: total }, () => ({ seconds: 0, positions: [] }));
  const name = job => job[1][0].split('/').at(-1);
  const parts = new Map();
  for (const job of jobs) parts.set(name(job), (parts.get(name(job)) ?? 0) + 1);
  const weighted = jobs.map((job, position) => ({
    position,
    seconds: (windowsSeconds[name(job)] ?? 10) / parts.get(name(job)),
  })).sort((a, b) => b.seconds - a.seconds || a.position - b.position);
  for (const { position, seconds } of weighted) {
    const bucket = buckets.reduce((best, current) => current.seconds < best.seconds ? current : best);
    bucket.positions.push(position);
    bucket.seconds += seconds;
  }
  const selected = new Set(buckets[index - 1].positions);
  return jobs.filter((_, position) => selected.has(position));
}

export function checkShellWeights(jobs, weights = windowsSeconds) {
  const suites = new Map();
  for (const [, args, limit] of jobs) {
    if (args[0] !== 'plugins/dr-status/tests/run-all.sh' && !/^plugins\/dforge\/tests\/[^/]+\.(test|acceptance)\.sh$/.test(args[0])) continue;
    const name = args[0].split('/').at(-1);
    const suite = suites.get(name) ?? { parts: 0, limit };
    suite.parts += 1;
    suites.set(name, suite);
  }
  const problems = [];
  for (const [name, { parts, limit }] of suites) {
    if (!Object.hasOwn(weights, name)) {
      problems.push(`${name}: no weight in scripts/test-shards.mjs; add it to windowsSeconds`);
      continue;
    }
    const each = weights[name] / parts;
    if (each > 0.8 * limit) problems.push(`${name}: weight ${each} s is above 80% of its ${limit} s limit: raise its suiteSeconds or split it`);
  }
  return problems;
}

export function driftWarning(args, seconds, limit) {
  if (!(seconds > 0.75 * limit)) return undefined;
  return `::warning::${args.join(' ').slice(0, 120)} took ${Math.round(seconds)}s of its ${limit}s limit`;
}
