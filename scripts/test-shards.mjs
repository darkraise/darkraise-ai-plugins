// Approximate Windows seconds from Actions run 40514782333. That run cut off
// faster-plans and task-step, whose weights are extrapolated from the share of
// their checks that ran, and ui-proof, which keeps its weight from 39725084214.
// These are scheduling weights, not timeouts; newly discovered suites receive
// the default weight. A suite test-all runs in parts splits its weight evenly
// among them.
const windowsSeconds = {
  'run-all.sh': 157,
  'auto-run.test.sh': 507,
  'budget-line.test.sh': 123,
  'codex-gate.test.sh': 97,
  'codex-review.test.sh': 141,
  'context-size.test.sh': 222,
  'darkmem-sync.test.sh': 155,
  'depth-route.test.sh': 88,
  'detect.test.sh': 137,
  'dforge-config.test.sh': 34,
  'dforge-migrate.test.sh': 64,
  'draft-pack.test.sh': 40,
  'executor-recovery.test.sh': 295,
  'faster-plans.acceptance.test.sh': 1200,
  'finish-choice.test.sh': 78,
  'hook.test.sh': 75,
  'in-flight.test.sh': 36,
  'inline-mode.test.sh': 65,
  'lens-route.test.sh': 135,
  'next-step.test.sh': 500,
  'plan-amend.test.sh': 235,
  'plan-lib.test.sh': 43,
  'plan-lint.test.sh': 814,
  'plan-revise.test.sh': 355,
  'register.test.sh': 68,
  'repo-audit.test.sh': 53,
  'review-depth-qa.acceptance.test.sh': 161,
  'review-depth.acceptance.test.sh': 160,
  'review-route.test.sh': 382,
  'roadmap.test.sh': 125,
  'roots.test.sh': 84,
  // Run 40748702288: the follow-ups suite was cut off at 600 s in A12.
  'speed-and-cost-followups.acceptance.test.sh': 1200,
  'speed-and-cost.acceptance.test.sh': 146,
  'suite-run.test.sh': 54,
  'task-loop-steps.acceptance.test.sh': 720,
  'task-state.test.sh': 47,
  'task-step.test.sh': 1340,
  'turn-end.test.sh': 251,
  'ui-hooks.test.sh': 65,
  'ui-proof.test.sh': 195,
  'ui-ux-skill.acceptance.test.sh': 362,
  'wave.test.sh': 75,
  'working-directory.test.sh': 64,
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
