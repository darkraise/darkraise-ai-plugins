// Approximate Windows seconds from recent Actions runs; this file's git history
// names them. A weight for a suite with no Windows run yet is an
// estimate from its Linux time.
// These are scheduling weights, not timeouts. validate-repository.mjs, claude
// plugin test and tsc take the default weight of 10. Every shell suite, and
// every node --test job under its first test file, needs an entry here, with a
// weight of at most 80% of the job's limit; tests/test-shards.test.mjs
// enforces both. A suite test-all runs in parts splits its weight evenly among
// them, unless its entry maps each part to its own weight, as task-step's and
// plan-lint's do: task-step's start and verdict parts together overran one
// shard at an even split, and plan-lint's paths part is a small fraction of it.
export const windowsSeconds = {
  'tests/dagents-rename.test.mjs': 60,
  'tests/guard-isolation.test.mjs': 375,
  'tests/dflow/board.test.mjs': 150,
  'tests/dr-status/run-all.sh': 157,
  'tests/dforge/agy-gate.test.sh': 70,
  'tests/dforge/agy-review.test.sh': 150,
  'tests/dforge/api-decisions-keep-warm-hydrogen.acceptance.test.sh': { 'A1 A2 A3 A4 A5 A6 A7': 340, 'A8 A9 A10 A11 A12 A13 A14 A15 A16 A17 A18 A25 A27 A28 A31': 380 },
  'tests/dforge/api-judge.test.sh': 260,
  'tests/dforge/api-spend.test.sh': 50,
  'tests/dforge/auto-default.test.sh': 10,
  'tests/dforge/auto-run-skills.test.sh': 10,
  'tests/dforge/auto-run-worktree-setting-qa.acceptance.test.sh': 420,
  'tests/dforge/auto-run-worktree-setting.acceptance.test.sh': 240,
  'tests/dforge/auto-run.test.sh': 800,
  'tests/dforge/budget-line.test.sh': 180,
  'tests/dforge/ci-mirror.test.sh': 60,
  'tests/dforge/clean-session-phases.acceptance.test.sh': 125,
  'tests/dforge/codex-client.test.sh': 10,
  'tests/dforge/codex-gate.test.sh': 122,
  'tests/dforge/codex-review.test.sh': 141,
  'tests/dforge/context-size.test.sh': 275,
  'tests/dforge/criteria.test.sh': 10,
  'tests/dforge/darkmem-sync.test.sh': 155,
  'tests/dforge/decide.test.sh': 165,
  'tests/dforge/depth-route.test.sh': 88,
  'tests/dforge/dforge-config.test.sh': 34,
  'tests/dforge/dforge-dir.test.sh': 10,
  'tests/dforge/dforge-migrate.test.sh': 64,
  'tests/dforge/dforge-state.test.sh': 10,
  'tests/dforge/executor-session.test.sh': 100,
  'tests/dforge/executors.test.sh': 10,
  'tests/dforge/faster-plans.acceptance.test.sh': 900,
  'tests/dforge/finish-choice.test.sh': 50,
  'tests/dforge/fleet.test.sh': 10,
  'tests/dforge/gates-manifest.test.sh': 10,
  'tests/dforge/hook.test.sh': 50,
  'tests/dforge/impl-stop-gate.test.sh': 40,
  'tests/dforge/in-flight.test.sh': 85,
  'tests/dforge/inline-mode.test.sh': 10,
  'tests/dforge/inline-only.acceptance.test.sh': 80,
  'tests/dforge/inline-only-execution.acceptance.test.sh': 120,
  'tests/dforge/ladder.test.sh': 10,
  'tests/dforge/lanes.test.sh': 10,
  'tests/dforge/lens-route.test.sh': 185,
  'tests/dforge/lock.test.sh': 10,
  'tests/dforge/measured-proposals.acceptance.test.sh': 535,
  'tests/dforge/native-routing.test.sh': 10,
  'tests/dforge/next-session-routing.acceptance.test.sh': 495,
  'tests/dforge/next-step.test.sh': 765,
  'tests/dforge/next-step-print.test.sh': 210,
  'tests/dforge/per-worktree-handoff.acceptance.test.sh': 700,
  'tests/dforge/plan-amend.test.sh': 390,
  'tests/dforge/plan-lib.test.sh': 35,
  'tests/dforge/plan-lint.test.sh': { one: 620, two: 620, paths: 40 },
  'tests/dforge/plugin-review-fixes.acceptance.test.sh': 415,
  'tests/dforge/polluter.test.sh': 10,
  'tests/dforge/process-roles.test.sh': 10,
  'tests/dforge/qa-files.test.sh': 20,
  'tests/dforge/register.test.sh': 45,
  'tests/dforge/repo-audit.test.sh': 80,
  'tests/dforge/retained-review-data.acceptance.test.sh': 50,
  'tests/dforge/review-depth-qa.acceptance.test.sh': 288,
  'tests/dforge/review-depth.acceptance.test.sh': 115,
  'tests/dforge/review-panel.test.sh': 70,
  'tests/dforge/review-record.test.sh': 20,
  'tests/dforge/review-route.test.sh': 355,
  'tests/dforge/reviewer-only-externals.acceptance.test.sh': 200,
  'tests/dforge/roadmap.test.sh': 170,
  'tests/dforge/roots.test.sh': 84,
  'tests/dforge/route.test.sh': 120,
  'tests/dforge/sdd-references.test.sh': 10,
  'tests/dforge/seats.test.sh': 10,
  'tests/dforge/session-state.test.sh': 20,
  'tests/dforge/settings-skills.test.sh': 10,
  'tests/dforge/skill-size.test.sh': 10,
  'tests/dforge/skill-split-planning.test.sh': 10,
  'tests/dforge/snapshot.test.sh': 10,
  'tests/dforge/speed-and-cost-followups.acceptance.test.sh': 470,
  'tests/dforge/speed-and-cost.acceptance.test.sh': 280,
  'tests/dforge/suite-run.test.sh': 54,
  'tests/dforge/task-loop-steps.acceptance.test.sh': 490,
  'tests/dforge/task-open-close.test.sh': 155,
  'tests/dforge/task-step-base.test.sh': 650,
  'tests/dforge/task-step-settle.test.sh': 220,
  'tests/dforge/task-step-suite.test.sh': 260,
  'tests/dforge/task-step-text.test.sh': 10,
  'tests/dforge/task-step.test.sh': { start: 700, verdict: 450, rereview: 420 },
  'tests/dforge/test-simplifier.test.sh': 10,
  'tests/dforge/test-volume-rules.acceptance.test.sh': 65,
  'tests/dforge/turn-end.test.sh': 485,
  'tests/dforge/typed-seats-and-drafting.acceptance.sh': 15,
  'tests/dforge/ui-hooks.test.sh': 180,
  'tests/dforge/ui-lint.test.sh': 10,
  'tests/dforge/ui-proof.test.sh': 135,
  'tests/dforge/ui-ux-skill.acceptance.test.sh': 330,
  'tests/dforge/ui-ux-skill.test.sh': 10,
  'tests/dforge/with-timeout.test.sh': 20,
  'tests/dforge/working-directory.test.sh': 82,
  'tests/dforge/worktree-instructions.test.sh': 10,
  'tests/dforge/wording-pin-deletion.acceptance.test.sh': 20,
  'tests/dforge/worktree-snapshot.test.sh': 20,
  'tests/dagents/agy-gate.test.sh': 65,
  'tests/dagents/agy-gemini-first.acceptance.test.sh': 145,
  'tests/dagents/antigravity-executor-lane.acceptance.test.sh': 255,
  'tests/dagents/auto-default.test.sh': 10,
  'tests/dagents/auto-run-skills.test.sh': 10,
  'tests/dagents/auto-run-worktree-setting-qa.acceptance.test.sh': 435,
  'tests/dagents/auto-run-worktree-setting.acceptance.test.sh': 245,
  'tests/dagents/auto-run.test.sh': 800,
  'tests/dagents/budget-line.test.sh': 230,
  'tests/dagents/ci-mirror.test.sh': 60,
  'tests/dagents/clean-session-phases.acceptance.test.sh': 140,
  'tests/dagents/codex-client.test.sh': 10,
  'tests/dagents/codex-gate.test.sh': 122,
  'tests/dagents/codex-review.test.sh': 141,
  'tests/dagents/context-size.test.sh': 222,
  'tests/dagents/criteria.test.sh': 10,
  'tests/dagents/darkmem-sync.test.sh': 155,
  'tests/dagents/depth-route.test.sh': 88,
  'tests/dagents/detect.test.sh': 160,
  'tests/dagents/dagents-config.test.sh': 34,
  'tests/dagents/dagents-dir.test.sh': 10,
  'tests/dagents/dagents-migrate.test.sh': 135,
  'tests/dagents/dagents-split.acceptance.test.sh': 90,
  'tests/dagents/dagents-state.test.sh': 10,
  'tests/dagents/executor-recovery.test.sh': 250,
  'tests/dagents/executor-session.test.sh': 85,
  'tests/dagents/executors.test.sh': 10,
  'tests/dagents/faster-plans.acceptance.test.sh': { 'a2 a3 a4 a5 a6 a7': 300, 'a8 a9 a10 a11 a12 a13': 340, 'a17 a18 a19 a20 a21 a22 a23': 470 },
  'tests/dagents/finish-choice.test.sh': 78,
  'tests/dagents/fleet.test.sh': 10,
  'tests/dagents/gates-manifest.test.sh': 10,
  'tests/dagents/hook.test.sh': 100,
  'tests/dagents/impl-stop-gate.test.sh': 90,
  'tests/dagents/in-flight.test.sh': 60,
  'tests/dagents/inline-mode.test.sh': 65,
  'tests/dagents/inline-only-execution.acceptance.test.sh': 200,
  'tests/dagents/inline-only.acceptance.test.sh': 110,
  'tests/dagents/isolation.acceptance.test.sh': 40,
  'tests/dagents/ladder.test.sh': 10,
  'tests/dagents/lane-breaker.test.sh': 40,
  'tests/dagents/lanes.test.sh': 10,
  'tests/dagents/lens-route.test.sh': 185,
  'tests/dagents/lock.test.sh': 10,
  'tests/dagents/native-routing.test.sh': 10,
  'tests/dagents/next-session-routing.acceptance.test.sh': 400,
  'tests/dagents/next-step.test.sh': 765,
  'tests/dagents/next-step-print.test.sh': 230,
  'tests/dagents/per-worktree-handoff.acceptance.test.sh': 700,
  'tests/dagents/plan-amend.test.sh': 390,
  'tests/dagents/plan-lib.test.sh': 43,
  'tests/dagents/plan-lint.test.sh': { one: 850, two: 660 },
  'tests/dagents/plan-revise.test.sh': 540,
  'tests/dagents/polluter.test.sh': 10,
  'tests/dagents/process-roles.test.sh': 10,
  'tests/dagents/qa-files.test.sh': 20,
  'tests/dagents/register.test.sh': 45,
  'tests/dagents/repo-audit.test.sh': 115,
  'tests/dagents/retained-review-data.acceptance.test.sh': 40,
  'tests/dagents/review-depth-qa.acceptance.test.sh': 288,
  'tests/dagents/review-depth.acceptance.test.sh': 160,
  'tests/dagents/review-record.test.sh': 20,
  'tests/dagents/review-route.test.sh': 458,
  'tests/dagents/roadmap.test.sh': 170,
  'tests/dagents/roots.test.sh': 84,
  'tests/dagents/route.test.sh': 175,
  'tests/dagents/run-agy-task.test.sh': 465,
  'tests/dagents/run-codex-task.test.sh': 10,
  'tests/dagents/sdd-references.test.sh': 10,
  'tests/dagents/seats.test.sh': 10,
  'tests/dagents/settings-skills.test.sh': 10,
  'tests/dagents/skill-size.test.sh': 10,
  'tests/dagents/skill-split-planning.test.sh': 10,
  'tests/dagents/snapshot.test.sh': 35,
  'tests/dagents/speed-and-cost-followups.acceptance.test.sh': 470,
  'tests/dagents/speed-and-cost.acceptance.test.sh': 280,
  'tests/dagents/stand-down.test.sh': 20,
  'tests/dforge/stand-down.test.sh': 20,
  'tests/dagents/suite-run.test.sh': 54,
  'tests/dagents/task-loop-steps.acceptance.test.sh': 1050,
  'tests/dagents/task-state.test.sh': 40,
  'tests/dagents/task-step-base.test.sh': 980,
  'tests/dagents/task-step-settle.test.sh': 220,
  'tests/dagents/task-step-suite.test.sh': 250,
  'tests/dagents/task-step-text.test.sh': 10,
  'tests/dagents/task-step.test.sh': { start: 750, rereview: 420, group: 348, verdict: 450 },
  'tests/dagents/test-simplifier.test.sh': 10,
  'tests/dagents/test-volume-rules.acceptance.test.sh': 90,
  'tests/dagents/turn-end.test.sh': 585,
  'tests/dagents/typed-seats-and-drafting.acceptance.sh': 20,
  'tests/dagents/ui-hooks.test.sh': 160,
  'tests/dagents/ui-lint.test.sh': 10,
  'tests/dagents/ui-proof.test.sh': 195,
  'tests/dagents/ui-ux-skill.acceptance.test.sh': 362,
  'tests/dagents/ui-ux-skill.test.sh': 10,
  'tests/dagents/wave.test.sh': 110,
  'tests/dagents/with-timeout.test.sh': 20,
  'tests/dagents/wording-pin-deletion.acceptance.test.sh': 20,
  'tests/dagents/working-directory.test.sh': 82,
  'tests/dagents/worktree-instructions.test.sh': 10,
};

// plan-lint runs about 320 checks of a few processes each, which take over
// twenty minutes on a Windows runner and under a minute on Linux. next-step and
// auto-run take about 760-800 s on a Windows runner; 1000 s keeps that within
// 80% of their limit. task-step's limit applies to each of its parts.
export const suiteSeconds = {
  'tests/dforge/plan-lint.test.sh': 1200,
  'tests/dforge/speed-and-cost-followups.acceptance.test.sh': 1200,
  'tests/dforge/task-loop-steps.acceptance.test.sh': 1200,
  'tests/dforge/task-step-base.test.sh': 1200,
  'tests/dforge/task-step.test.sh': 900,
  'tests/dforge/next-step.test.sh': 1000,
  'tests/dforge/auto-run.test.sh': 1000,
  'tests/dforge/measured-proposals.acceptance.test.sh': 900,
  'tests/dforge/next-session-routing.acceptance.test.sh': 650,
  'tests/dforge/turn-end.test.sh': 650,
  'tests/dagents/turn-end.test.sh': 750,
  'tests/dforge/per-worktree-handoff.acceptance.test.sh': 1000,
  'tests/dagents/per-worktree-handoff.acceptance.test.sh': 1000,
  'tests/dagents/auto-run.test.sh': 1000,
  'tests/dagents/faster-plans.acceptance.test.sh': 1125,
  'tests/dagents/next-step.test.sh': 1000,
  'tests/dagents/plan-lint.test.sh': 1200,
  'tests/dagents/plan-revise.test.sh': 900,
  'tests/dagents/task-loop-steps.acceptance.test.sh': 1350,
  'tests/dagents/task-step-base.test.sh': 1225,
  'tests/dagents/task-step.test.sh': 1000,
};
// faster-plans takes about 20 minutes on a Windows runner, more than a shard
// can hold beside anything else, so it runs as three parts of its tests.
// task-step and plan-lint each run as three parts, one per section of the
// suite, whose limit applies to each.
export const suiteParts = {
  'tests/dforge/faster-plans.acceptance.test.sh': [['a2', 'a3', 'a5'], ['a11', 'a12'], ['a17', 'a19', 'a20', 'a21', 'a22', 'a23']],
  'tests/dforge/task-step.test.sh': [['start'], ['rereview'], ['verdict']],
  'tests/dforge/plan-lint.test.sh': [['one'], ['two'], ['paths']],
  'tests/dforge/speed-and-cost-followups.acceptance.test.sh': [['A1', 'A2', 'A3', 'A4', 'A7', 'A8', 'A11'], ['A13', 'A14', 'A15']],
  'tests/dforge/api-decisions-keep-warm-hydrogen.acceptance.test.sh': [['A1', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7'], ['A8', 'A9', 'A10', 'A11', 'A12', 'A13', 'A14', 'A15', 'A16', 'A17', 'A18', 'A25', 'A27', 'A28', 'A31']],
  'tests/dagents/faster-plans.acceptance.test.sh': [['a2', 'a3', 'a4', 'a5', 'a6', 'a7'], ['a8', 'a9', 'a10', 'a11', 'a12', 'a13'], ['a17', 'a18', 'a19', 'a20', 'a21', 'a22', 'a23']],
  'tests/dagents/plan-lint.test.sh': [['one'], ['two']],
  'tests/dagents/task-step.test.sh': [['start'], ['rereview'], ['group'], ['verdict']],
};

// A node --test job's first argument is the --test flag every such job shares,
// so the job is named by its first test file instead.
const nodeTest = args => args[0] === '--test';
const suiteName = args => nodeTest(args) ? args[1] : args[0];
const suitePart = args => nodeTest(args) ? '' : args.slice(1).join(' ');

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
  const name = job => suiteName(job[1]);
  const parts = new Map();
  for (const job of jobs) parts.set(name(job), (parts.get(name(job)) ?? 0) + 1);
  const weighted = jobs.map((job, position) => ({
    position,
    seconds: partWeight(weights[name(job)], suitePart(job[1]), parts.get(name(job))),
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
    if (!nodeTest(args) && args[0] !== 'tests/dr-status/run-all.sh' && !/^tests\/[a-z0-9-]+\/[^/]+\.(test|acceptance)\.sh$/.test(args[0])) continue;
    const name = suiteName(args);
    const suite = suites.get(name) ?? { parts: [], limit };
    suite.parts.push(suitePart(args));
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

// The workflow guard reads the host's own Claude settings by default, so a
// job runs it against an empty directory unless its environment names one.
export function guardIsolation(env, dir) {
  const isolated = { ...env };
  for (const name of ['WORKFLOW_GUARD_CLAUDE_DIR', 'WORKFLOW_GUARD_MANAGED_DIR', 'WORKFLOW_GUARD_PROJECT_DIR']) {
    if (isolated[name] === undefined) isolated[name] = dir;
  }
  return isolated;
}

export function driftWarning(args, seconds, limit) {
  if (!(seconds > 0.75 * limit)) return undefined;
  return `::warning::${args.join(' ').slice(0, 120)} took ${Math.round(seconds)}s of its ${limit}s limit`;
}
