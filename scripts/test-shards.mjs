// Approximate Windows seconds from recent Actions runs; this file's git history
// names them. A weight for a suite with no Windows run yet is an
// estimate from its Linux time.
// These are scheduling weights, not timeouts. The jobs that are not shell
// suites (validate-repository.mjs, the --test jobs, claude plugin test, tsc)
// take the default weight of 10. Every shell suite needs an entry here, with a
// weight of at most 80% of the suite's limit; tests/test-shards.test.mjs
// enforces both. A suite test-all runs in parts splits its weight evenly among
// them, unless its entry maps each part to its own weight, as task-step's and
// plan-lint's do: task-step's start and verdict parts together overran one
// shard at an even split, and plan-lint's paths part is a small fraction of it.
export const windowsSeconds = {
  'plugins/dr-status/tests/run-all.sh': 157,
  'plugins/dforge/tests/agy-gate.test.sh': 20,
  'plugins/dforge/tests/agy-review.test.sh': 60,
  'plugins/dforge/tests/api-decisions-keep-warm-hydrogen.acceptance.test.sh': 360,
  'plugins/dforge/tests/api-judge.test.sh': 120,
  'plugins/dforge/tests/api-spend.test.sh': 20,
  'plugins/dforge/tests/auto-default.test.sh': 10,
  'plugins/dforge/tests/auto-run-skills.test.sh': 10,
  'plugins/dforge/tests/auto-run-worktree-setting-qa.acceptance.test.sh': 330,
  'plugins/dforge/tests/auto-run-worktree-setting.acceptance.test.sh': 190,
  'plugins/dforge/tests/auto-run.test.sh': 507,
  'plugins/dforge/tests/budget-line.test.sh': 123,
  'plugins/dforge/tests/ci-mirror.test.sh': 60,
  'plugins/dforge/tests/clean-session-phases.acceptance.test.sh': 70,
  'plugins/dforge/tests/codex-client.test.sh': 10,
  'plugins/dforge/tests/codex-gate.test.sh': 122,
  'plugins/dforge/tests/codex-review.test.sh': 141,
  'plugins/dforge/tests/context-size.test.sh': 222,
  'plugins/dforge/tests/criteria.test.sh': 10,
  'plugins/dforge/tests/darkmem-sync.test.sh': 155,
  'plugins/dforge/tests/decide.test.sh': 40,
  'plugins/dforge/tests/depth-route.test.sh': 88,
  'plugins/dforge/tests/dforge-config.test.sh': 34,
  'plugins/dforge/tests/dforge-dir.test.sh': 10,
  'plugins/dforge/tests/dforge-migrate.test.sh': 64,
  'plugins/dforge/tests/dforge-state.test.sh': 10,
  'plugins/dforge/tests/executor-session.test.sh': 10,
  'plugins/dforge/tests/executors.test.sh': 10,
  'plugins/dforge/tests/faster-plans.acceptance.test.sh': 900,
  'plugins/dforge/tests/finish-choice.test.sh': 78,
  'plugins/dforge/tests/fleet.test.sh': 10,
  'plugins/dforge/tests/gates-manifest.test.sh': 10,
  'plugins/dforge/tests/hook.test.sh': 75,
  'plugins/dforge/tests/impl-stop-gate.test.sh': 64,
  'plugins/dforge/tests/in-flight.test.sh': 36,
  'plugins/dforge/tests/inline-mode.test.sh': 65,
  'plugins/dforge/tests/inline-only.acceptance.test.sh': 110,
  'plugins/dforge/tests/inline-only-execution.acceptance.test.sh': 200,
  'plugins/dforge/tests/ladder.test.sh': 10,
  'plugins/dforge/tests/lanes.test.sh': 10,
  'plugins/dforge/tests/lens-route.test.sh': 185,
  'plugins/dforge/tests/lock.test.sh': 10,
  'plugins/dforge/tests/measured-proposals.acceptance.test.sh': 60,
  'plugins/dforge/tests/native-routing.test.sh': 10,
  'plugins/dforge/tests/next-session-routing.acceptance.test.sh': 400,
  'plugins/dforge/tests/next-step.test.sh': 500,
  'plugins/dforge/tests/next-step-print.test.sh': 150,
  'plugins/dforge/tests/plan-amend.test.sh': 390,
  'plugins/dforge/tests/plan-lib.test.sh': 43,
  'plugins/dforge/tests/plan-lint.test.sh': { one: 620, two: 620, paths: 40 },
  'plugins/dforge/tests/plugin-review-fixes.acceptance.test.sh': 200,
  'plugins/dforge/tests/polluter.test.sh': 10,
  'plugins/dforge/tests/process-roles.test.sh': 10,
  'plugins/dforge/tests/qa-files.test.sh': 20,
  'plugins/dforge/tests/register.test.sh': 68,
  'plugins/dforge/tests/repo-audit.test.sh': 53,
  'plugins/dforge/tests/retained-review-data.acceptance.test.sh': 30,
  'plugins/dforge/tests/review-depth-qa.acceptance.test.sh': 288,
  'plugins/dforge/tests/review-depth.acceptance.test.sh': 160,
  'plugins/dforge/tests/review-panel.test.sh': 30,
  'plugins/dforge/tests/review-record.test.sh': 20,
  'plugins/dforge/tests/review-route.test.sh': 458,
  'plugins/dforge/tests/reviewer-only-externals.acceptance.test.sh': 200,
  'plugins/dforge/tests/roadmap.test.sh': 170,
  'plugins/dforge/tests/roots.test.sh': 84,
  'plugins/dforge/tests/route.test.sh': 120,
  'plugins/dforge/tests/sdd-references.test.sh': 10,
  'plugins/dforge/tests/seats.test.sh': 10,
  'plugins/dforge/tests/session-state.test.sh': 20,
  'plugins/dforge/tests/settings-skills.test.sh': 10,
  'plugins/dforge/tests/skill-size.test.sh': 10,
  'plugins/dforge/tests/skill-split-planning.test.sh': 10,
  'plugins/dforge/tests/snapshot.test.sh': 10,
  'plugins/dforge/tests/speed-and-cost-followups.acceptance.test.sh': 470,
  'plugins/dforge/tests/speed-and-cost.acceptance.test.sh': 280,
  'plugins/dforge/tests/suite-run.test.sh': 54,
  'plugins/dforge/tests/task-loop-steps.acceptance.test.sh': 920,
  'plugins/dforge/tests/task-open-close.test.sh': 30,
  'plugins/dforge/tests/task-step-base.test.sh': 900,
  'plugins/dforge/tests/task-step-settle.test.sh': 220,
  'plugins/dforge/tests/task-step-suite.test.sh': 250,
  'plugins/dforge/tests/task-step-text.test.sh': 10,
  'plugins/dforge/tests/task-step.test.sh': { start: 700, verdict: 450, rereview: 420 },
  'plugins/dforge/tests/test-simplifier.test.sh': 10,
  'plugins/dforge/tests/test-volume-rules.acceptance.test.sh': 40,
  'plugins/dforge/tests/turn-end.test.sh': 290,
  'plugins/dforge/tests/typed-seats-and-drafting.acceptance.sh': 75,
  'plugins/dforge/tests/ui-hooks.test.sh': 65,
  'plugins/dforge/tests/ui-lint.test.sh': 10,
  'plugins/dforge/tests/ui-proof.test.sh': 195,
  'plugins/dforge/tests/ui-ux-skill.acceptance.test.sh': 362,
  'plugins/dforge/tests/ui-ux-skill.test.sh': 10,
  'plugins/dforge/tests/with-timeout.test.sh': 20,
  'plugins/dforge/tests/working-directory.test.sh': 82,
  'plugins/dforge/tests/worktree-instructions.test.sh': 10,
  'plugins/dforge/tests/wording-pin-deletion.acceptance.test.sh': 20,
  'plugins/dforge/tests/worktree-snapshot.test.sh': 47,
  'plugins/dagents/tests/agy-gate.test.sh': 20,
  'plugins/dagents/tests/agy-gemini-first.acceptance.test.sh': 10,
  'plugins/dagents/tests/antigravity-executor-lane.acceptance.test.sh': 10,
  'plugins/dagents/tests/auto-default.test.sh': 10,
  'plugins/dagents/tests/auto-run-skills.test.sh': 10,
  'plugins/dagents/tests/auto-run-worktree-setting-qa.acceptance.test.sh': 330,
  'plugins/dagents/tests/auto-run-worktree-setting.acceptance.test.sh': 190,
  'plugins/dagents/tests/auto-run.test.sh': 507,
  'plugins/dagents/tests/budget-line.test.sh': 123,
  'plugins/dagents/tests/ci-mirror.test.sh': 60,
  'plugins/dagents/tests/clean-session-phases.acceptance.test.sh': 70,
  'plugins/dagents/tests/codex-client.test.sh': 10,
  'plugins/dagents/tests/codex-gate.test.sh': 122,
  'plugins/dagents/tests/codex-review.test.sh': 141,
  'plugins/dagents/tests/context-size.test.sh': 222,
  'plugins/dagents/tests/criteria.test.sh': 10,
  'plugins/dagents/tests/darkmem-sync.test.sh': 155,
  'plugins/dagents/tests/depth-route.test.sh': 88,
  'plugins/dagents/tests/detect.test.sh': 10,
  'plugins/dagents/tests/dagents-config.test.sh': 34,
  'plugins/dagents/tests/dagents-dir.test.sh': 10,
  'plugins/dagents/tests/dagents-migrate.test.sh': 64,
  'plugins/dagents/tests/dagents-state.test.sh': 10,
  'plugins/dagents/tests/executor-recovery.test.sh': 10,
  'plugins/dagents/tests/executor-session.test.sh': 10,
  'plugins/dagents/tests/executors.test.sh': 10,
  'plugins/dagents/tests/faster-plans.acceptance.test.sh': 900,
  'plugins/dagents/tests/finish-choice.test.sh': 78,
  'plugins/dagents/tests/fleet.test.sh': 10,
  'plugins/dagents/tests/gates-manifest.test.sh': 10,
  'plugins/dagents/tests/hook.test.sh': 75,
  'plugins/dagents/tests/impl-stop-gate.test.sh': 64,
  'plugins/dagents/tests/in-flight.test.sh': 36,
  'plugins/dagents/tests/inline-mode.test.sh': 65,
  'plugins/dagents/tests/inline-only-execution.acceptance.test.sh': 200,
  'plugins/dagents/tests/inline-only.acceptance.test.sh': 110,
  'plugins/dagents/tests/ladder.test.sh': 10,
  'plugins/dagents/tests/lane-breaker.test.sh': 10,
  'plugins/dagents/tests/lanes.test.sh': 10,
  'plugins/dagents/tests/lens-route.test.sh': 185,
  'plugins/dagents/tests/lock.test.sh': 10,
  'plugins/dagents/tests/native-routing.test.sh': 10,
  'plugins/dagents/tests/next-step.test.sh': 500,
  'plugins/dagents/tests/plan-amend.test.sh': 390,
  'plugins/dagents/tests/plan-lib.test.sh': 43,
  'plugins/dagents/tests/plan-lint.test.sh': { one: 620, two: 660 },
  'plugins/dagents/tests/plan-revise.test.sh': 10,
  'plugins/dagents/tests/polluter.test.sh': 10,
  'plugins/dagents/tests/process-roles.test.sh': 10,
  'plugins/dagents/tests/register.test.sh': 68,
  'plugins/dagents/tests/repo-audit.test.sh': 53,
  'plugins/dagents/tests/retained-review-data.acceptance.test.sh': 30,
  'plugins/dagents/tests/review-depth-qa.acceptance.test.sh': 288,
  'plugins/dagents/tests/review-depth.acceptance.test.sh': 160,
  'plugins/dagents/tests/review-record.test.sh': 20,
  'plugins/dagents/tests/review-route.test.sh': 458,
  'plugins/dagents/tests/roadmap.test.sh': 170,
  'plugins/dagents/tests/roots.test.sh': 84,
  'plugins/dagents/tests/run-agy-task.test.sh': 10,
  'plugins/dagents/tests/run-codex-task.test.sh': 10,
  'plugins/dagents/tests/sdd-references.test.sh': 10,
  'plugins/dagents/tests/seats.test.sh': 10,
  'plugins/dagents/tests/settings-skills.test.sh': 10,
  'plugins/dagents/tests/skill-size.test.sh': 10,
  'plugins/dagents/tests/skill-split-planning.test.sh': 10,
  'plugins/dagents/tests/snapshot.test.sh': 10,
  'plugins/dagents/tests/speed-and-cost-followups.acceptance.test.sh': 470,
  'plugins/dagents/tests/speed-and-cost.acceptance.test.sh': 280,
  'plugins/dagents/tests/suite-run.test.sh': 54,
  'plugins/dagents/tests/task-loop-steps.acceptance.test.sh': 920,
  'plugins/dagents/tests/task-state.test.sh': 10,
  'plugins/dagents/tests/task-step-base.test.sh': 900,
  'plugins/dagents/tests/task-step-settle.test.sh': 220,
  'plugins/dagents/tests/task-step-suite.test.sh': 250,
  'plugins/dagents/tests/task-step-text.test.sh': 10,
  'plugins/dagents/tests/task-step.test.sh': { start: 700, rereview: 420, group: 348, verdict: 450 },
  'plugins/dagents/tests/test-simplifier.test.sh': 10,
  'plugins/dagents/tests/test-volume-rules.acceptance.test.sh': 40,
  'plugins/dagents/tests/turn-end.test.sh': 290,
  'plugins/dagents/tests/typed-seats-and-drafting.acceptance.sh': 75,
  'plugins/dagents/tests/ui-hooks.test.sh': 65,
  'plugins/dagents/tests/ui-lint.test.sh': 10,
  'plugins/dagents/tests/ui-proof.test.sh': 195,
  'plugins/dagents/tests/ui-ux-skill.acceptance.test.sh': 362,
  'plugins/dagents/tests/ui-ux-skill.test.sh': 10,
  'plugins/dagents/tests/wave.test.sh': 10,
  'plugins/dagents/tests/wording-pin-deletion.acceptance.test.sh': 20,
  'plugins/dagents/tests/working-directory.test.sh': 82,
  'plugins/dagents/tests/worktree-instructions.test.sh': 10,
};

// plan-lint runs about 320 checks of a few processes each, which take over
// twenty minutes on a Windows runner and under a minute on Linux. next-step and
// auto-run take about 500 s on a Windows runner; 700 s keeps that under 80% of
// their limit. task-step's limit applies to each of its parts.
export const suiteSeconds = {
  'plugins/dforge/tests/plan-lint.test.sh': 1200,
  'plugins/dforge/tests/speed-and-cost-followups.acceptance.test.sh': 1200,
  'plugins/dforge/tests/task-loop-steps.acceptance.test.sh': 1200,
  'plugins/dforge/tests/task-step-base.test.sh': 1200,
  'plugins/dforge/tests/task-step.test.sh': 900,
  'plugins/dforge/tests/next-step.test.sh': 700,
  'plugins/dforge/tests/auto-run.test.sh': 700,
  'plugins/dagents/tests/auto-run.test.sh': 634,
  'plugins/dagents/tests/faster-plans.acceptance.test.sh': 1125,
  'plugins/dagents/tests/next-step.test.sh': 625,
  'plugins/dagents/tests/plan-lint.test.sh': 1200,
  'plugins/dagents/tests/task-loop-steps.acceptance.test.sh': 1150,
  'plugins/dagents/tests/task-step-base.test.sh': 1125,
  'plugins/dagents/tests/task-step.test.sh': 900,
};
// faster-plans takes about 20 minutes on a Windows runner, more than a shard
// can hold beside anything else, so it runs as three parts of its tests.
// task-step and plan-lint each run as three parts, one per section of the
// suite, whose limit applies to each.
export const suiteParts = {
  'plugins/dforge/tests/faster-plans.acceptance.test.sh': [['a2', 'a3', 'a5'], ['a11', 'a12'], ['a17', 'a19', 'a20', 'a21', 'a22', 'a23']],
  'plugins/dforge/tests/task-step.test.sh': [['start'], ['rereview'], ['verdict']],
  'plugins/dforge/tests/plan-lint.test.sh': [['one'], ['two'], ['paths']],
  'plugins/dforge/tests/speed-and-cost-followups.acceptance.test.sh': [['A1', 'A2', 'A3', 'A4', 'A7', 'A8', 'A11'], ['A13', 'A14', 'A15']],
  'plugins/dagents/tests/plan-lint.test.sh': [['one'], ['two']],
  'plugins/dagents/tests/task-step.test.sh': [['start'], ['rereview'], ['group'], ['verdict']],
};

function partWeight(entry, part, parts) {
  if (entry === undefined) return 10 / parts;
  if (typeof entry !== 'object') return entry / parts;
  if (!part) return Object.values(entry).reduce((sum, w) => sum + w, 0);
  return entry[part] ?? 10;
}

export function selectShard(jobs, shard, weights = windowsSeconds) {
  if (shard === undefined) return jobs;
  if (!/^[1-9]\d*\/[1-9]\d*$/.test(shard)) throw new Error('Shard must be INDEX/TOTAL (for example 1/4)');
  const [index, total] = shard.split('/').map(Number);
  if (!Number.isSafeInteger(index) || !Number.isSafeInteger(total) || index > total || total > jobs.length) {
    throw new Error('Shard requires 1 <= INDEX <= TOTAL <= number of suites');
  }
  const buckets = Array.from({ length: total }, () => ({ seconds: 0, positions: [] }));
  const name = job => job[1][0];
  const parts = new Map();
  for (const job of jobs) parts.set(name(job), (parts.get(name(job)) ?? 0) + 1);
  const weighted = jobs.map((job, position) => ({
    position,
    seconds: partWeight(weights[name(job)], job[1].slice(1).join(' '), parts.get(name(job))),
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
    if (args[0] !== 'plugins/dr-status/tests/run-all.sh' && !/^plugins\/[a-z0-9-]+\/tests\/[^/]+\.(test|acceptance)\.sh$/.test(args[0])) continue;
    const name = args[0];
    const suite = suites.get(name) ?? { parts: [], limit };
    suite.parts.push(args.slice(1).join(' '));
    suites.set(name, suite);
  }
  const problems = [];
  for (const [name, { parts, limit }] of suites) {
    if (!Object.hasOwn(weights, name)) {
      problems.push(`${name}: no weight in scripts/test-shards.mjs; add it to windowsSeconds`);
      continue;
    }
    for (const part of typeof weights[name] === 'object' ? parts : parts.slice(0, 1)) {
      const label = typeof weights[name] === 'object' ? `${name} ${part}` : name;
      if (typeof weights[name] === 'object' && !Object.hasOwn(weights[name], part)) {
        problems.push(`${label}: no weight for this part in scripts/test-shards.mjs; add it to windowsSeconds`);
        continue;
      }
      const each = partWeight(weights[name], part, parts.length);
      if (each > 0.8 * limit) problems.push(`${label}: weight ${each} s is above 80% of its ${limit} s limit: raise its suiteSeconds or split it`);
    }
  }
  return problems;
}

export function driftWarning(args, seconds, limit) {
  if (!(seconds > 0.75 * limit)) return undefined;
  return `::warning::${args.join(' ').slice(0, 120)} took ${Math.round(seconds)}s of its ${limit}s limit`;
}
