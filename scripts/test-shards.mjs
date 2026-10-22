// Approximate Windows seconds from Actions run 39725084214 (plan-revise,
// roots and turn-end from 39716794435, which ran them whole). These are
// scheduling weights, not timeouts; newly discovered suites receive the
// default weight.
const windowsSeconds = {
  'run-all.sh': 155,
  'auto-run.test.sh': 500,
  'budget-line.test.sh': 110,
  'codex-gate.test.sh': 115,
  'codex-review.test.sh': 145,
  'context-size.test.sh': 220,
  'darkmem-sync.test.sh': 140,
  'detect.test.sh': 130,
  'dforge-config.test.sh': 35,
  'dforge-migrate.test.sh': 75,
  'executor-recovery.test.sh': 295,
  'finish-choice.test.sh': 80,
  'hook.test.sh': 80,
  'inline-mode.test.sh': 65,
  'next-step.test.sh': 335,
  'plan-amend.test.sh': 215,
  'plan-lib.test.sh': 40,
  'plan-lint.test.sh': 750,
  'plan-revise.test.sh': 225,
  'register.test.sh': 60,
  'repo-audit.test.sh': 55,
  'review-route.test.sh': 330,
  'roadmap.test.sh': 110,
  'roots.test.sh': 50,
  'task-state.test.sh': 55,
  'turn-end.test.sh': 55,
  'wave.test.sh': 35,
  'working-directory.test.sh': 80,
};

export function selectShard(jobs, shard) {
  if (shard === undefined) return jobs;
  if (!/^[1-9]\d*\/[1-9]\d*$/.test(shard)) throw new Error('Shard must be INDEX/TOTAL (for example 1/4)');
  const [index, total] = shard.split('/').map(Number);
  if (!Number.isSafeInteger(index) || !Number.isSafeInteger(total) || index > total || total > jobs.length) {
    throw new Error('Shard requires 1 <= INDEX <= TOTAL <= number of suites');
  }
  const buckets = Array.from({ length: total }, () => ({ seconds: 0, positions: [] }));
  const weighted = jobs.map((job, position) => ({
    position,
    seconds: windowsSeconds[job[1][0].split('/').at(-1)] ?? 10,
  })).sort((a, b) => b.seconds - a.seconds || a.position - b.position);
  for (const { position, seconds } of weighted) {
    const bucket = buckets.reduce((best, current) => current.seconds < best.seconds ? current : best);
    bucket.positions.push(position);
    bucket.seconds += seconds;
  }
  const selected = new Set(buckets[index - 1].positions);
  return jobs.filter((_, position) => selected.has(position));
}
