// Approximate Windows seconds from Actions run 35680401352. These are scheduling
// weights, not timeouts; newly discovered suites receive the default weight.
const windowsSeconds = {
  'run-all.sh': 150,
  'codex-gate.test.sh': 55,
  'codex-review.test.sh': 70,
  'context-size.test.sh': 55,
  'detect.test.sh': 125,
  'executor-recovery.test.sh': 160,
  'inline-mode.test.sh': 35,
  'next-step.test.sh': 55,
  'plan-amend.test.sh': 45,
  'plan-lib.test.sh': 25,
  'plan-lint.test.sh': 430,
  'plan-revise.test.sh': 165,
  'review-route.test.sh': 110,
  'task-state.test.sh': 200,
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
