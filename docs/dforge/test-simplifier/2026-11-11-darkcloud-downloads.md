# Mutation measurement: darkcloud downloads, 2026-11-11

One StrykerJS run with bail disabled on darkcloud `web/src/features/downloads`, in a throwaway clone. Measurement only: no test was deleted or edited, and nothing here recommends a deletion.

## 1. Environment

- darkcloud commit measured: `dde303e0efc946598155ea3af24875cadb07f370` (the clone's HEAD; see section 8 for what darkcloud itself did during the run).
- Clone: `/root/mutation-runs/darkcloud-downloads`, made with `git clone --no-hardlinks`, no `origin` remote.
- Node v24.18.0, StrykerJS 10.1.1, Vitest 2.1.9, with `@stryker-mutator/vitest-runner@10.1.1`.
- Run start 2026-11-11T10:04:33Z, run end 2026-11-11T10:43:02Z, wall time about 38 minutes 29 seconds (Stryker reports "Done in 38 minutes and 23 seconds"). `estimate-at-30m`: elapsed ~28m, remaining ~6m (81%, 3709/5364 tested). `narrowed`: no.
- Stryker's own dry run ran 1539 tests against 5747 mutants, not the baseline's 5132 tests: its Vitest runner runs only the test files related to the mutated sources (`vitest.related`, default true). The population below is therefore the tests that import the downloads module directly or transitively, and a test outside it cannot kill these mutants.

Configuration (`web/stryker.config.json`, no narrowing):

```json
{
  "$schema": "./node_modules/@stryker-mutator/core/schema/stryker-schema.json",
  "testRunner": "vitest",
  "coverageAnalysis": "perTest",
  "disableBail": true,
  "ignoreStatic": true,
  "mutate": ["src/features/downloads/**/*.ts", "src/features/downloads/**/*.tsx"],
  "reporters": ["json", "html", "progress-append-only", "clear-text"],
  "concurrency": 4,
  "tempDirName": ".stryker-tmp"
}
```

Commands run:

- `timeout 900 npm ci`
- `timeout 600 npm install --no-save @stryker-mutator/core@10.1.1 @stryker-mutator/vitest-runner@10.1.1`
- `timeout 300 npm run gen:routes`
- `timeout 300 npm run gen:file-icons`
- `timeout 1800 npx vitest run`
- `timeout 1800 npx vitest run`
- `timeout 1800 npx vitest run --poolOptions.threads.maxThreads=4 --poolOptions.threads.minThreads=1 --poolOptions.forks.maxForks=4 --poolOptions.forks.minForks=1`
- `timeout 3600 npx stryker run --dryRunOnly`
- `timeout 3600 npx stryker run --mutate src/features/downloads/lib/when.ts`
- `setsid --wait bash -c 'echo $$ > pgid; exec timeout 8h npx stryker run' (cwd clone web/)`

Baseline. The default `vitest run` was not green in this environment: it failed twice under full parallel load, on different tests each time, and the failing files pass when run alone. The baseline used is the third run, capped at four workers, which was green. Recorded lines:

- `baseline-failure: tests/cover-chooser.test.tsx > cover chooser grid > uploading a file posts it through uploadCover`
- `baseline-failure: tests/library-filter-bar.test.tsx > the read-state control > shows icons only on a phone, each named and tooltipped by its state`
- `baseline-failure: tests/book-intel-timeline-tab.test.tsx > TimelineTab > says when a chapter number is not in the book`
- `baseline-failure: tests/library-filter-bar.test.tsx > the read-state control > shows icons only on a phone, each named and tooltipped by its state`
- `baseline-failure: tests/library-settings-scanning.test.tsx > the Scanning tab's rows > marks only the watch row modified once it is changed`
- `baseline-rerun: exit 1, 3 failed of 5132`
- `baseline-variant: exit 0, 0 failed of 5132 (5131 passed, 1 skipped); four workers (--maxWorkers=4 alone is rejected by vitest 2.1.9 with a minThreads/maxThreads conflict)`

Killed mutants whose `killedBy` contains each named failing test, from `before/mutation.json`:

| Failing test | Killed mutants credited |
|---|---|
| cover-chooser: uploading a file posts it through uploadCover | 0 (its file is not in the related set, so it is absent from the report) |
| library-filter-bar: shows icons only on a phone, each named and tooltipped by its state | 0 (absent from the report) |
| book-intel-timeline-tab: says when a chapter number is not in the book | 0 (in the report, kills nothing) |
| library-settings-scanning: marks only the watch row modified once it is changed | 0 (absent from the report) |

No load flake is credited as a killer, so none of them inflates the redundancy counts below.

## 2. Mutants

| Total | Killed | Timeout | Survived | NoCoverage | Ignored | Other |
|---|---|---|---|---|---|---|
| 5747 | 3623 | 1 | 1117 | 617 | 383 | 6 |

- Caught (Killed + Timeout): 3624.
- Mutants killed by two or more tests (`multiKiller`): 2187, so bail was off and every killer is recorded.
- Timeout and Ignored mutants are attributed to no test.
- Ignored, by `statusReason`: 383 of 383 are `Static mutant (and "ignoreStatic" was enabled)`; none were disabled by comment.
- Other: 6, all `RuntimeError`.

## 3. Tests

| Population | Run | Covering | Kills nothing | No unique kill | In greedy set | Outside greedy set |
|---|---|---|---|---|---|---|
| downloads (`downloads-*` files) | 543 | 533 | 0 | 275 | 290 | 253 |
| other | 992 | 77 | 0 | 45 | 36 | 956 |

Greedy minimum killing set, total size: 326 tests (each step takes the test killing the most still-uncovered Killed mutants, ties to the lowest id). "No unique kill" counts tests that kill at least one mutant where every mutant they kill is also killed by another test.

## 4. A<n> tests

| A<n> tests run | Kill nothing | Every kill also made by a non-A<n> test (row 10) | Every kill also made by a same-id test in the same file (row 15) |
|---|---|---|---|
| 159 | 0 | 29 | 8 |

An A<n> test is a test in a `.acceptance.` file whose name contains `A<number>`.

## 5. Per file

Downloads-population files, sorted by "no unique kill" descending. This is row 8's candidate list, not a deletion list.

| File | Run | Kills nothing | No unique kill | Outside greedy set |
|---|---|---|---|---|
| tests/downloads-submit.test.ts | 50 | 0 | 42 | 33 |
| tests/downloads-queue.test.ts | 36 | 0 | 30 | 31 |
| tests/downloads-transfers.test.ts | 48 | 0 | 30 | 28 |
| tests/downloads-errors.test.ts | 24 | 0 | 23 | 23 |
| tests/downloads-visual-revamp-folders.acceptance.test.tsx | 14 | 0 | 12 | 10 |
| tests/downloads-file-kind.test.tsx | 14 | 0 | 11 | 11 |
| tests/downloads-visual-revamp-overview.acceptance.test.tsx | 14 | 0 | 11 | 9 |
| tests/downloads-add-modal.test.tsx | 17 | 0 | 10 | 8 |
| tests/downloads-priority.test.ts | 10 | 0 | 8 | 8 |
| tests/downloads-package-card.test.tsx | 28 | 0 | 7 | 7 |
| tests/downloads-detect.test.ts | 7 | 0 | 5 | 5 |
| tests/downloads-finished-chart.test.ts | 7 | 0 | 5 | 4 |
| tests/downloads-folder-browser.test.tsx | 20 | 0 | 5 | 3 |
| tests/downloads-watch-box.test.tsx | 16 | 0 | 5 | 5 |
| tests/downloads-when.test.ts | 5 | 0 | 5 | 5 |
| tests/downloads-needs-tab.test.tsx | 11 | 0 | 4 | 3 |
| tests/downloads-settings-accounts.test.ts | 11 | 0 | 4 | 4 |
| tests/downloads-browsable-tree-pane.test.tsx | 7 | 0 | 3 | 2 |
| tests/downloads-confirmed-actions.test.tsx | 3 | 0 | 3 | 2 |
| tests/downloads-layout.test.tsx | 11 | 0 | 3 | 3 |
| tests/downloads-overview.test.tsx | 12 | 0 | 3 | 3 |
| tests/downloads-pick-tray.test.tsx | 5 | 0 | 3 | 3 |
| tests/downloads-remote-folders.test.tsx | 11 | 0 | 3 | 2 |
| tests/downloads-reorder.test.ts | 5 | 0 | 3 | 3 |
| tests/downloads-settings-gating.test.ts | 4 | 0 | 3 | 3 |
| tests/downloads-visual-revamp-actions.acceptance.test.tsx | 5 | 0 | 3 | 1 |
| tests/downloads-active-tab.test.tsx | 18 | 0 | 2 | 2 |
| tests/downloads-category-select.test.tsx | 2 | 0 | 2 | 2 |
| tests/downloads-counted.test.ts | 2 | 0 | 2 | 2 |
| tests/downloads-folder-list.test.tsx | 9 | 0 | 2 | 2 |
| tests/downloads-history.test.ts | 5 | 0 | 2 | 2 |
| tests/downloads-idle-overview.test.tsx | 9 | 0 | 2 | 1 |
| tests/downloads-settings-accounts-panel.test.tsx | 4 | 0 | 2 | 1 |
| tests/downloads-settings-caps.test.ts | 3 | 0 | 2 | 2 |
| tests/downloads-settings-categories-panel.test.tsx | 2 | 0 | 2 | 1 |
| tests/downloads-settings-config.test.ts | 2 | 0 | 2 | 2 |
| tests/downloads-visual-revamp-add.acceptance.test.tsx | 2 | 0 | 2 | 2 |
| tests/downloads-bulk.test.tsx | 4 | 0 | 1 | 2 |
| tests/downloads-enqueue-selection-hook.test.tsx | 2 | 0 | 1 | 0 |
| tests/downloads-folder-grid.test.tsx | 5 | 0 | 1 | 1 |
| tests/downloads-history-tab.test.tsx | 14 | 0 | 1 | 1 |
| tests/downloads-narrow.test.tsx | 2 | 0 | 1 | 1 |
| tests/downloads-ready-tab.test.tsx | 15 | 0 | 1 | 1 |
| tests/downloads-segments.test.ts | 7 | 0 | 1 | 1 |
| tests/downloads-settings-categories.test.ts | 6 | 0 | 1 | 1 |
| tests/downloads-submit-hook.test.tsx | 3 | 0 | 1 | 1 |
| tests/downloads-attention-banner.test.tsx | 4 | 0 | 0 | 0 |
| tests/downloads-edit-package-hook.test.tsx | 1 | 0 | 0 | 0 |
| tests/downloads-edit-package.test.tsx | 5 | 0 | 0 | 0 |
| tests/downloads-finished-history.test.tsx | 2 | 0 | 0 | 0 |
| tests/downloads-history-api.test.ts | 2 | 0 | 0 | 0 |
| tests/downloads-hub.test.ts | 6 | 0 | 0 | 6 |
| tests/downloads-reorder-conflict.test.tsx | 1 | 0 | 0 | 0 |
| tests/downloads-retry-api.test.ts | 1 | 0 | 0 | 0 |
| tests/downloads-retry-hook.test.tsx | 1 | 0 | 0 | 0 |
| tests/downloads-settings-caps-panel.test.tsx | 6 | 0 | 0 | 0 |
| tests/downloads-settings-profiles-panel.test.tsx | 3 | 0 | 0 | 0 |

## 6. Reading

Of 543 downloads tests, 275 (50.6%) have no unique kill and 253 (46.6%) lie outside a greedy killing set, so about half of them add no kill that another test does not already make. No covering test kills nothing, so the "too many tests" claim shows up as overlap, not as dead tests. undefined of 3623 killed mutants have two or more killers, which is why the overlap is so large. 10 downloads tests cover no mutant at all, a separate group worth a look. Among 159 A<n> tests, 29 have every kill also made by a non-A<n> test and 8 have every kill also made by a same-id test in the same file. The limits: one module of one project, mutants are a proxy for faults, 1117 Survived mutants and 617 with no coverage mean some faults no test catches, and the greedy set is an approximation, not the true minimum. Outside greedy does not mean deletable: a test can guard a fault no mutator models. These counts are evidence for row 1's claim, not for removing any test.

## 7. Reproduce

```
node .dforge/test-simplifier/downloads-mutation/analyse.mjs .dforge/test-simplifier/downloads-mutation/before/mutation.json
```

`analyse.mjs`:

```js
import { readFileSync } from "node:fs"
import { pathToFileURL } from "node:url"

const STATUSES = ["Killed", "Timeout", "Survived", "NoCoverage", "Ignored"]

export function analyse(report) {
  const mutants = Object.values(report.files).flatMap((f) => f.mutants)

  const tests = []
  for (const [file, entry] of Object.entries(report.testFiles ?? {})) {
    const base = file.split("/").pop()
    for (const t of entry.tests) {
      const a = base.includes(".acceptance.") ? /\bA(\d+)\b/.exec(t.name) : null
      tests.push({ id: t.id, file, downloads: base.startsWith("downloads-"), aId: a ? a[1] : null })
    }
  }
  const byId = new Map(tests.map((t) => [t.id, t]))

  const counts = { total: mutants.length }
  for (const s of STATUSES) counts[s] = 0
  counts.other = 0
  for (const m of mutants) {
    if (STATUSES.includes(m.status)) counts[m.status]++
    else counts.other++
  }

  const killed = mutants.filter((m) => m.status === "Killed")
  const killers = killed.map((m) => (m.killedBy ?? []).filter((id) => byId.has(id)))
  const multiKiller = killed.filter((m) => (m.killedBy ?? []).length >= 2).length

  const covering = new Set()
  for (const m of mutants) for (const id of m.coveredBy ?? []) if (byId.has(id)) covering.add(id)

  const kills = new Map()
  killers.forEach((ids, i) => {
    for (const id of ids) {
      if (!kills.has(id)) kills.set(id, [])
      kills.get(id).push(i)
    }
  })

  const noUniqueKill = new Set()
  for (const [id, list] of kills) {
    if (list.every((i) => killers[i].some((other) => other !== id))) noUniqueKill.add(id)
  }

  const greedy = new Set()
  const uncovered = new Set(killers.map((_, i) => i).filter((i) => killers[i].length > 0))
  while (uncovered.size > 0) {
    let best = null
    let bestCount = 0
    for (const [id, list] of kills) {
      const n = list.filter((i) => uncovered.has(i)).length
      if (n > bestCount || (n === bestCount && n > 0 && id < best)) {
        best = id
        bestCount = n
      }
    }
    greedy.add(best)
    for (const i of kills.get(best)) uncovered.delete(i)
  }

  const killsNothing = (t) => covering.has(t.id) && !kills.has(t.id)
  const population = (list) => ({
    run: list.length,
    covering: list.filter((t) => covering.has(t.id)).length,
    killsNothing: list.filter(killsNothing).length,
    noUniqueKill: list.filter((t) => noUniqueKill.has(t.id)).length,
    outsideGreedy: list.filter((t) => !greedy.has(t.id)).length,
  })

  const aTests = tests.filter((t) => t.aId !== null)
  const killedMutantsOf = (t) => (kills.get(t.id) ?? []).map((i) => killed[i])
  const everyKillAlso = (t, other) => {
    const list = killedMutantsOf(t)
    return list.length > 0 && list.every((m) => (m.killedBy ?? []).some((id) => id !== t.id && other(byId.get(id), t)))
  }

  const files = [...new Set(tests.filter((t) => t.downloads).map((t) => t.file))].sort()

  return {
    mutants: counts,
    multiKiller,
    greedySize: greedy.size,
    populations: {
      downloads: population(tests.filter((t) => t.downloads)),
      other: population(tests.filter((t) => !t.downloads)),
    },
    aTests: {
      total: aTests.length,
      killsNothing: aTests.filter(killsNothing).length,
      allKilledByNonA: aTests.filter((t) => everyKillAlso(t, (o) => o && o.aId === null)).length,
      allKilledBySameId: aTests.filter((t) => everyKillAlso(t, (o, self) => o && o.file === self.file && o.aId === self.aId)).length,
    },
    perFile: files.map((file) => {
      const p = population(tests.filter((t) => t.file === file))
      return { file, run: p.run, killsNothing: p.killsNothing, noUniqueKill: p.noUniqueKill, outsideGreedy: p.outsideGreedy }
    }),
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (!process.argv[2]) {
    console.error("usage: node analyse.mjs <mutation.json>")
    process.exit(2)
  }
  console.log(JSON.stringify(analyse(JSON.parse(readFileSync(process.argv[2], "utf8"))), null, 2))
}
```

## 8. darkcloud check

The plan's check (A7) expects darkcloud's HEAD and `git status --porcelain` hash to match the run notes after the run. They do not match.

- HEAD before the run: `dde303e0efc946598155ea3af24875cadb07f370`. HEAD after: `c476656dd7a5f8167711f0a3b4676f7340b00822`.
- Commits in between (`git log --oneline dde303e0..HEAD`): `132a689d` feat(book-intel): choose a style from the run's list (10:28 UTC); `c476656d` feat(book-intel): drop the global portrait style (10:38 UTC). Neither touches `web/`.
- Status hash before: `5118adad6be939544448f9cc3f2e425d35a7c1f9c6a37706e01eb3bf15e50d59`. After: `fac0cff6d0fe1f74ca23e85e1f66e88eeba336faad158c0a60605a7d0c09f312`.
- Current `git --no-optional-locks status --porcelain`:
  - ` M tests/Darkcloud.Api.IntegrationTests/Snapshots/openapi.v1.json`
  - ` M web/src/features/book-intel/components/settings/StagesSection.tsx` (modified 10:40:52 UTC)
  - ` M web/src/features/book-intel/hooks.ts` (10:40:52 UTC)
  - ` M web/src/lib/api/types.ts` (10:41:01 UTC)
  - ` M web/tests/book-intel-settings-stages.test.tsx` (10:40:52 UTC)
  - `?? .superpowers/handoff/2026-10-21-reader-hardening.md`
- Reason (inference): the owner kept working in darkcloud during the run window, 10:04:33 to 10:43:02 UTC. Evidence: the commits are book-intel work and the four `web/` files are in the same area, with modification times just after the second commit; every command of this plan ran in the clone; darkcloud has no `.stryker-tmp` or `reports/` directory.
- No changed path is under `src/features/downloads` or `tests/downloads-*`. The clone's HEAD is still `dde303e0`, and `git -C /root/mutation-runs/darkcloud-downloads remote` prints nothing.
- On A8: the modified `web/tests/book-intel-settings-stages.test.tsx` is part of the owner's book-intel change. This plan neither edited nor deleted it, and no downloads test changed in the clone or in the project.
