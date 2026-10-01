// The decision rules of spec §4, as pure functions over scored results.

export const MIN_STRIPPED = 4;

// decideRow ARMS CASES CELL [THIN] — ARMS lists the current agent first, CASES
// are the row's manifest cases from both pools, and CELL(id, arm) returns
// { outcome, cost } or undefined while the cell is unscored. A regression is
// a case the current agent passes and a candidate does not. THIN is false for
// row 1, which cannot hold a stripped case: a stripped task totals at least 2.
export function decideRow(arms, cases, cell, thin = true) {
  const [current, ...candidates] = arms;
  if (cases.length === 0) return { verdict: 'NOT MEASURED', notes: ['no case on this row'], stats: [] };
  const missing = arms.flatMap(arm => cases.filter(c => !cell(c.id, arm)).map(c => `${c.id}/${arm}`));
  if (missing.length > 0) return { verdict: 'INCOMPLETE', notes: [`${missing.length} cells are not scored`], stats: [] };
  const stat = arm => {
    const runs = cases.map(c => cell(c.id, arm));
    const pass = runs.filter(r => r.outcome === 'PASS').length;
    const cost = runs.reduce((sum, r) => sum + r.cost, 0);
    const regressions = arm === current ? [] : cases.filter(c => cell(c.id, current).outcome === 'PASS' && cell(c.id, arm).outcome !== 'PASS').map(c => c.id);
    return { arm, pass, of: runs.length, perPass: pass > 0 ? cost / pass : Infinity, regressions };
  };
  const stats = arms.map(stat);
  const [cur, ...cands] = stats;
  const eligible = cands.filter(s => s.regressions.length === 0 && s.perPass < cur.perPass).sort((a, b) => a.perPass - b.perPass);
  const stripped = cases.filter(c => c.pool === 'stripped').length;
  const notes = [`${cases.length} paired trials (${stripped} stripped); zero regressions is consistent with a true regression rate up to ${Math.round(Math.min(1, 3 / cases.length) * 100)}%`];
  for (const s of cands.filter(s => s.regressions.length > 0)) notes.push(`${s.arm} regresses on ${s.regressions.join(', ')}`);
  let verdict = 'UNCHANGED';
  if (eligible.length > 0) {
    verdict = `MOVE to ${eligible[0].arm}`;
    if (thin && stripped < MIN_STRIPPED) verdict += ` - owner ruling, only ${stripped} stripped cases`;
  } else if (cands.some(s => s.regressions.length === 1)) {
    verdict = 'INCONCLUSIVE';
  }
  if (cur.of - cur.pass >= 2) notes.push(`${current} does not pass ${cur.of - cur.pass} cases: second repetition with the next agent up`);
  return { verdict, notes, stats };
}

// decideReview ARMS GRADES — ARMS lists the current judge first; GRADES are
// the pass-1 rows of review-grades.tsv. A cheaper judge is supported when its
// pooled recall is at least the current judge's and it misses no defect the
// current judge found and graded Critical. Every rubric defect was fixed by a
// later commit, so one found but graded below Important is under-graded.
export function decideReview(arms, grades) {
  const [current, ...candidates] = arms;
  const key = g => `${g.case}\t${g.defect}`;
  const of = arm => new Map(grades.filter(g => g.arm === arm).map(g => [key(g), g]));
  const cur = of(current);
  const recall = map => {
    const found = [...map.values()].filter(g => g.found === '1');
    return { found: found.length, of: map.size, underGraded: found.filter(g => g.severity !== 'Critical' && g.severity !== 'Important').length };
  };
  return [{ arm: current, ...recall(cur), verdict: 'current', missedCritical: [] }, ...candidates.map(arm => {
    const mine = of(arm);
    const r = recall(mine);
    if (cur.size === 0 || mine.size !== cur.size) return { arm, ...r, verdict: 'INCOMPLETE', missedCritical: [] };
    const missedCritical = [...cur.values()].filter(g => g.found === '1' && g.severity === 'Critical' && mine.get(key(g))?.found !== '1').map(g => `${g.case}/${g.defect}`);
    const supported = r.found >= recall(cur).found && missedCritical.length === 0;
    return { arm, ...r, verdict: supported ? 'SUPPORTED' : 'NOT SUPPORTED', missedCritical };
  })];
}

// graderDisagreements GRADES PASS — how many defects the repeat grading, pass
// PASS + 1, judged differently from pass PASS. More than one means the grader
// is not usable.
export function graderDisagreements(grades, pass = 1) {
  const first = new Map(grades.filter(g => g.pass === String(pass)).map(g => [`${g.case}\t${g.arm}\t${g.defect}`, g.found]));
  const second = grades.filter(g => g.pass === String(pass + 1));
  return { repeated: second.length, disagreements: second.filter(g => first.get(`${g.case}\t${g.arm}\t${g.defect}`) !== g.found).length };
}
