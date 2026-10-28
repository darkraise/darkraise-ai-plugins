// summarize ROWS — one entry per arm, in order of first appearance, from the
// rows of results/pipeline.tsv. A cell is a case, an arm and a run; its last
// row settles it. pass2 counts the cases whose runs 1 and 2 both passed, cost
// sums every cell and median is the median wall time of the cells in seconds.
export function summarize(rows) {
  const cells = new Map();
  for (const r of rows) cells.set(`${r.arm}\t${r.case}\t${r.run}`, r);
  const arms = new Map();
  for (const r of cells.values()) {
    const arm = arms.get(r.arm) ?? { arm: r.arm, byCase: new Map(), cost: 0, times: [] };
    arm.byCase.set(r.case, { ...arm.byCase.get(r.case), [r.run]: r.outcome });
    arm.cost += Number(r.costUsd) || 0;
    arm.times.push(Number(r.seconds) || 0);
    arms.set(r.arm, arm);
  }
  return [...arms.values()].map(({ arm, byCase, cost, times }) => {
    const sorted = [...times].sort((a, b) => a - b);
    const mid = sorted.length >> 1;
    const median = sorted.length % 2 === 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
    return {
      arm,
      cases: byCase.size,
      pass2: [...byCase.values()].filter(runs => runs[1] === 'PASS' && runs[2] === 'PASS').length,
      cost,
      median: Math.round(median),
    };
  });
}
