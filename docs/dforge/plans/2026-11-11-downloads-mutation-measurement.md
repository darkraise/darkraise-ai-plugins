# Downloads Mutation Measurement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One StrykerJS run with bail disabled on darkcloud `web/src/features/downloads`, in a throwaway clone, yields a committed report counting covering tests, tests that kill nothing, tests with no unique kill, the greedy minimum killing set and redundant A<n> tests, without touching darkcloud or deleting any test.

**Architecture:** Task 1 builds the clone and proves the riskiest assumption with a dry run, then records the bail fact in test-simplifier's `runners.md`. Task 2 runs the mutation under an 8-hour budget and saves `mutation.json` where test-simplifier Phase 4 expects a "before" report. Task 3 analyses that file with a small Node script, checked against a hand-made fixture first, writes the report and updates the register.

**Tech Stack:** StrykerJS 10.1.1 with `@stryker-mutator/vitest-runner`, Vitest 2 (darkcloud's two-project workspace), Node 24, Markdown.

**Spec:** docs/dforge/specs/2026-11-11-downloads-mutation-measurement-design.md

**Execution:** inline — `claude --model sonnet --effort medium` — the hardest task totals 4

**Parallelism:** sequential — inline execution

**Task check:** `timeout 1500 node scripts/test-all.mjs && timeout 240 /root/.local/bin/claude plugin test plugins/dforge && timeout 60 node scripts/validate-repository.mjs && timeout 60 /root/.local/bin/claude plugin validate . && timeout 60 /root/.local/bin/claude plugin validate plugins/dforge` — the full suite last passed in 270 s

**Integration check:** `timeout 1500 node scripts/test-all.mjs && timeout 240 /root/.local/bin/claude plugin test plugins/dforge && timeout 60 node scripts/validate-repository.mjs && timeout 60 /root/.local/bin/claude plugin validate . && timeout 60 /root/.local/bin/claude plugin validate plugins/dforge`

**CI:** `.github/workflows/validate.yml` — platforms: uutils (ubuntu-latest), Windows Git Bash — local: `node scripts/test-all.mjs`; `node scripts/validate-repository.mjs`; `claude plugin validate plugins/dforge`; `claude plugin test plugins/dforge` — uncovered: uutils (ubuntu-latest), Windows Git Bash

**Plan review:** 2026-11-11 — dforge:judge-opus — executability 10 / coherence 16 / coverage 16 / assumptions 12 (round 1)

## Global Constraints

- English only in code, comments, docs, commits and tests.
- Commits are `<type>(<scope>): <subject>`, subject at most 50 characters, authored as `Darkraise <quangtc94@gmail.com>`, with no AI attribution of any kind.
- Nothing is pushed before finishing.
- Measurement only: no darkcloud test is deleted or edited, in the clone or in `/root/repositories/darkcloud` (spec A8). Nothing is installed, written or run inside `/root/repositories/darkcloud`; every darkcloud command runs in the clone.
- The clone is never a worktree of darkcloud and has no `origin` remote (spec A7).
- Every long command runs with an explicit `timeout`; the mutation run runs under `setsid` as a tracked background task, and every process it started is gone before Task 2 ends (spec A12).
- No test checks the wording of a skill or reference (register row 12): the `runners.md` note and the report are carried by `demo` statements.
- Windows Git Bash: A native program (`git.exe`, `jq.exe`) given a path built from `$PWD`, `$(pwd)` or `$TMPDIR` gets a POSIX form it cannot open, or has its argument rewritten when path conversion is on (`MSYS_NO_PATHCONV` unset). Convert the path with `cygpath -m` before the call (dforge's `dr_native_path`, `plugins/dforge/scripts/lib/native-path.sh`), and feed `jq` a file on stdin in a script that exports `MSYS_NO_PATHCONV`.
- Windows Git Bash: The same directory is `/c/Users/x` in the shell and `C:/Users/x` from a native tool, so a string comparison never matches. Normalise both sides with `cygpath -m`, or compare with `-ef`.
- Windows Git Bash: Files a Windows tool wrote, and native program output, end lines with `\r`, which `read`, `awk` and `[ = ]` keep. Pipe through `tr -d '\r'` before comparing or parsing.
- Windows Git Bash: `awk -v name=value` processes backslash escapes in the value, so a regex or a Windows path changes. Pass the value in the environment and read `ENVIRON["NAME"]`.
- Windows Git Bash: Node's `import()` of an absolute `D:/x/y.mjs` reads `d:` as a URL scheme and fails. Import with `import(pathToFileURL(path).href)`.
- uutils (ubuntu-latest): A lock built on `mkdir` failing when the directory exists does not exclude a second process. Create the lock file with `set -C` (noclobber), or use `flock`.
- uutils (ubuntu-latest): `timeout` signals only the command it started, so the command's children keep running. Run the command in its own process group (`setsid`) and signal the group.

## Contracts

- **Clone:** `/root/mutation-runs/darkcloud-downloads`, a `git clone --no-hardlinks` of `/root/repositories/darkcloud`; the web app is its `web/` directory. Task 1 creates it; Tasks 2 and 3 use it; register row 8 reuses it later, so nothing deletes it.
- **Run directory:** `.dforge/test-simplifier/downloads-mutation/` in this repository (git-ignored, the `<state>` of `scripts/dforge-path state`).
- **Run notes:** `<run directory>/run-notes.md`, plain `key: value` lines, appended by Tasks 1 and 2 and read by Task 3. Keys: `darkcloud-sha`, `darkcloud-status-sha256` (the `sha256sum` of `git -C /root/repositories/darkcloud status --porcelain`), `clone`, `node`, `stryker`, `vitest`, `dry-run-tests`, `dry-run-mutants`, `concurrency`, `command` (one line per command run, repeated key), `probe` (the probe check's output line), `run-start` (the first run's start, written once, so the wall time includes an aborted run), `run-end` (ISO 8601 UTC), `pgid` (the current run's process group, read from `<run directory>/pgid`; a restart appends a new line and the last one is current), `estimate-at-30m` (elapsed plus remaining as printed), `narrowed` (`no`, or the narrowed `mutate` globs), `final-status` (Stryker's last summary line).
- **Stryker configuration:** `<clone>/web/stryker.config.json`, exactly as Task 1 Step 3 gives it.
- **Mutation report:** `<run directory>/before/mutation.json`, a copy of `<clone>/web/reports/mutation/mutation.json` (mutation-testing-report-schema: `files.<path>.mutants[]` with `id`, `status`, `coveredBy`, `killedBy`; `testFiles.<path>.tests[]` with `id`, `name`).
- **Analysis module:** `<run directory>/analyse.mjs`, exporting `analyse(report)` and, run as `node analyse.mjs <mutation.json>`, printing `JSON.stringify(analyse(report), null, 2)`. The return shape is the `expected` object of Task 3's test, with these definitions: a test is in the *downloads* population when its test file's basename starts with `downloads-`, else *other*; *covering* means it appears in some mutant's `coveredBy`; *killsNothing* counts covering tests in no `killedBy`; *noUniqueKill* counts tests that kill at least one mutant where every mutant they kill lists another test in `killedBy`; the greedy set covers the Killed mutants, each step taking the test that kills the most still-uncovered mutants, ties to the lowest test id by string comparison; *outsideGreedy* counts tests run that are not in the greedy set; an *A<n> test* is a test in a file whose basename contains `.acceptance.` and whose name matches `/\bA(\d+)\b/`, the first match being its id; *aTests.total* counts A<n> tests run; *aTests.killsNothing* counts covering A<n> tests in no Killed mutant's `killedBy`; *allKilledByNonA* counts A<n> tests that kill at least one mutant where every mutant they kill is also killed by a test that is not an A<n> test; *allKilledBySameId* counts A<n> tests that kill at least one mutant where every mutant they kill is also killed by another test in the same file with the same id; `mutants.other` counts every status other than Killed, Timeout, Survived, NoCoverage and Ignored; *multiKiller* counts Killed mutants with two or more `killedBy` entries; Timeout mutants are attributed to no test; `perFile` lists downloads-population files only, sorted by path.
- **Report:** `docs/dforge/test-simplifier/<run-end date>-darkcloud-downloads.md`.

## Assumptions (evidence)

- The Vitest runner honours `disableBail` and iterates every workspace project: `npm pack @stryker-mutator/vitest-runner@10.1.1` on 2026-11-11, `dist/src/vitest-test-runner.js:138` (`bail: this.options.disableBail ? 0 : 1`) and lines 145 and 278-294 (`this.ctx.projects`). Its peer range is `vitest >=2.0.0`, and darkcloud's `web/package.json` declares `vitest ^2.1.9`.
- That the dry run passes on darkcloud's `vitest.workspace.ts`: unverified — Task 1 Step 4 verifies it.
- That `mutation.json` names one `testFiles` key per test file, that every `killedBy` id resolves to a `testFiles` test id, and that bail is really off (some mutant has two killers): unverified — Task 1 Step 5's probe on one small file verifies all three before the long run, since `--dryRunOnly` writes no `mutation.json`.
- The A<n> rule departs from the spec's "a test whose name begins with `A` followed by digits": Stryker's test names carry the `describe` prefix, so "begins with" would miss nested tests, and in darkcloud `web/tests` all 130 `it("A<n>` tests are in `.acceptance.` files, named like `A5: a single-f…` (`rg`, 2026-11-11). The Contracts rule (acceptance file plus `/\bA(\d+)\b/`) keeps the spec's intent.
- That the whole module fits 8 hours: unverified — Task 2 Step 2 reads the estimate at 30 minutes and narrows as the spec says.
- The reporter is `progress-append-only`, the line-per-update form of the spec's `progress` reporter, because the run's output goes to a log file, not a terminal, and the 30-minute estimate is read from it.
- Host: 12 cores and 16 GB with about 7 GB available (`nproc`, `free -g`, 2026-11-11); hence `concurrency` 4, lowered to 2 when the dry run leaves under 1 GB available.
- darkcloud's working tree has uncommitted changes outside `web/` (`git status --short`, 2026-11-11) and is in active use, so its status may change during the run for reasons unrelated to it; Task 3 Step 6 tells the two apart.
- Round 1's borderline executability 10 and assumptions 12 stand without a second round (cap 1 at depth light): every Critical and Important finding was fixed in place — the background launch without an inner `&`, a whole-object second test, the exact A<n> regex with its evidence, the Task 1 probe of the report's shape and bail, and the A5 check against the embedded copy.
- The clone at `/root/mutation-runs/darkcloud-downloads` and the installs inside it lie outside this checkout, but they are the design the owner approved at the spec review ("Approve and run unattended", 2026-11-11), not a side effect an auto run must defer; nothing is pushed, published or merged by Tasks 1-3.
- Tasks 1 and 2 change no file the repository's tests read, and Task 3 adds a report and edits the register; the Task check runs anyway, because it is the Full suite command and costs 270 s.

## Task index

1. Clone, configure and dry-run Stryker
2. Run the mutation within the budget
3. Analyse, report and update the register

---

### Task 1: Clone, configure and dry-run Stryker

**Files:**
- Create: `/root/mutation-runs/darkcloud-downloads/` (outside this repository)
- Create: `/root/mutation-runs/darkcloud-downloads/web/stryker.config.json`
- Create: `.dforge/test-simplifier/downloads-mutation/run-notes.md`
- Create: `.dforge/test-simplifier/downloads-mutation/probe/mutation.json`
- Modify: `plugins/dforge/skills/test-simplifier/references/runners.md` (section `## Mutation tools`)

**Interfaces:**
- Consumes: nothing.
- Produces: the Clone, the Stryker configuration and the first Run notes keys (Contracts).

**Items:** 1

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 1 - coupling 2 - risk 0 = 4

- [ ] **Step 1: Record darkcloud's state, then clone**

```bash
[ ! -e /root/mutation-runs/darkcloud-downloads ] || { echo "clone exists"; exit 1; }
mkdir -p .dforge/test-simplifier/downloads-mutation /root/mutation-runs
N=.dforge/test-simplifier/downloads-mutation/run-notes.md
echo "darkcloud-sha: $(git -C /root/repositories/darkcloud rev-parse HEAD)" >> $N
echo "darkcloud-status-sha256: $(git --no-optional-locks -C /root/repositories/darkcloud status --porcelain | sha256sum | cut -d' ' -f1)" >> $N
timeout 600 git clone --no-hardlinks /root/repositories/darkcloud /root/mutation-runs/darkcloud-downloads
git -C /root/mutation-runs/darkcloud-downloads remote remove origin
echo "clone: /root/mutation-runs/darkcloud-downloads" >> $N
```

Expected: the clone's `git rev-parse HEAD` equals `darkcloud-sha`, and `git -C /root/mutation-runs/darkcloud-downloads remote` prints nothing. If `/root/mutation-runs/darkcloud-downloads` already exists, stop: a leftover is not reused without a ruling.

- [ ] **Step 2: Install and prove the baseline green**

In `/root/mutation-runs/darkcloud-downloads/web`:

```bash
timeout 900 npm ci
timeout 600 npm install --no-save @stryker-mutator/core@10.1.1 @stryker-mutator/vitest-runner@10.1.1
timeout 300 npm run gen:routes
timeout 300 npm run gen:file-icons
timeout 1800 npx vitest run
```

Expected: `vitest run` exits 0 with both the `dom` and `node` projects reporting tests. A red baseline stops the plan: append the failing test names to the run notes as `baseline-failure:` lines, fix nothing, and take it to the ruling seat. Append `node: $(node --version)`, `stryker: <npx stryker --version>` and `vitest: <npx vitest --version>`, and one `command:` line per command above.

- [ ] **Step 3: Write the Stryker configuration**

`/root/mutation-runs/darkcloud-downloads/web/stryker.config.json`:

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

- [ ] **Step 4: Dry run — the riskiest assumption**

```bash
set -o pipefail; cd /root/mutation-runs/darkcloud-downloads/web && timeout 3600 npx stryker run --dryRunOnly 2>&1 | tee /root/repositories/darkraise-ai-plugins/.dforge/test-simplifier/downloads-mutation/dry-run.log
```

Expected: exit 0, an "Initial test run succeeded" line whose test count is within 1% of Step 2's `vitest run` total, and an instrumented mutant count above zero. Watch `free -m` while it runs; under 1 GB available means `concurrency` becomes 2 in the configuration. Append `dry-run-tests`, `dry-run-mutants`, `concurrency` and the `command:` line. A failure gets dforge:systematic-debugging inside the clone; a fix that needs anything beyond `stryker.config.json` and the clone's installs goes to the ruling seat, because it changes what is measured.

- [ ] **Step 5: Probe the report's shape on one small file**

```bash
set -o pipefail; cd /root/mutation-runs/darkcloud-downloads/web && timeout 3600 npx stryker run --mutate src/features/downloads/lib/when.ts 2>&1 | tee /root/repositories/darkraise-ai-plugins/.dforge/test-simplifier/downloads-mutation/probe.log
cd /root/repositories/darkraise-ai-plugins && mkdir -p .dforge/test-simplifier/downloads-mutation/probe
cp /root/mutation-runs/darkcloud-downloads/web/reports/mutation/mutation.json .dforge/test-simplifier/downloads-mutation/probe/mutation.json
node -e '
const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))
const files = Object.keys(r.testFiles ?? {})
const ids = new Set(files.flatMap(f => r.testFiles[f].tests.map(t => t.id)))
const mutants = Object.values(r.files).flatMap(f => f.mutants)
const killers = mutants.flatMap(m => m.killedBy ?? [])
const multi = mutants.filter(m => m.status === "Killed" && (m.killedBy ?? []).length >= 2).length
console.log(`test-files: ${files.length} downloads-files: ${files.filter(f => /(^|\/)downloads-[^/]*$/.test(f)).length} unresolved-killers: ${killers.filter(k => !ids.has(k)).length} multi-killer: ${multi}`)
' .dforge/test-simplifier/downloads-mutation/probe/mutation.json
```

Expected: Stryker exits 0, and the printed line shows `test-files` above 1, `downloads-files` above 0, `unresolved-killers: 0` and `multi-killer` above 0. Append the line as `probe:` and the `command:` lines. When only `multi-killer` is 0, repeat with `--mutate src/features/downloads/lib/segments.ts` once; still 0, or any other expectation failing, goes to the ruling seat, because the long run would then measure nothing Task 3 can use.

- [ ] **Step 6: Record the bail fact in `runners.md`**

Below the `Count \`Killed\` and \`Timeout\` as caught …` paragraph of `## Mutation tools`, add this paragraph verbatim:

```markdown
Most runners stop a mutant at its first killing test, so the report names one
killer per mutant. Finding tests that no mutant needs takes every killer: for
StrykerJS set `disableBail: true` with `coverageAnalysis: "perTest"` and read
each mutant's `killedBy` in the JSON reporter's `mutation.json`. Its Vitest
runner applies both across every project of a Vitest workspace.
```

- [ ] **Step 7: Verify and commit**

Run the Task check. Expected: exit 0.

```bash
git add plugins/dforge/skills/test-simplifier/references/runners.md
git commit -m "docs(dforge): note disableBail for kill matrices"
```

### Task 2: Run the mutation within the budget

**Files:**
- Create: `.dforge/test-simplifier/downloads-mutation/run.log`
- Create: `.dforge/test-simplifier/downloads-mutation/pgid`
- Create: `.dforge/test-simplifier/downloads-mutation/before/mutation.json`
- Modify: `.dforge/test-simplifier/downloads-mutation/run-notes.md`

**Interfaces:**
- Consumes: the Clone, the Stryker configuration and Run notes (Contracts).
- Produces: the Mutation report and the remaining Run notes keys (Contracts).

**Items:** 1

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Start the run**

As a tracked background task (Bash `run_in_background`), from `/root/mutation-runs/darkcloud-downloads/web`:

```bash
D=/root/repositories/darkraise-ai-plugins/.dforge/test-simplifier/downloads-mutation
setsid --wait bash -c "echo \$\$ > $D/pgid; exec timeout 8h npx stryker run" > $D/run.log 2>&1
```

The command has no inner `&`: the tracked task lives exactly as long as Stryker, and its exit code is Stryker's (124 when the cap is hit). Append `run-start` (`date -u +%FT%TZ`, first run only), `pgid: $(cat $D/pgid)` and the `command:` line to the run notes.

- [ ] **Step 2: Read the estimate at 30 minutes**

Start a second background task, `sleep 1800`, and on its notification take the last `progress-append-only` line of `run.log` and append its elapsed and remaining times as `estimate-at-30m`. When elapsed plus remaining exceeds 8 hours: `kill -TERM -<pgid>`, confirm with `ps -o pid= -g <pgid>` that nothing remains, set `mutate` in the configuration to `["src/features/downloads/{transfers,lib}/**/*.ts", "src/features/downloads/{transfers,lib}/**/*.tsx"]`, append `narrowed:` with those globs, and repeat Step 1 (a fresh run, not incremental). The narrowed run takes no second estimate. Otherwise append `narrowed: no`.

- [ ] **Step 3: Finish, save and clean up**

When the run's tracked task ends (not before): append `run-end`, its exit code as `exit`, and Stryker's final summary line as `final-status`. Exit 124 means the 8-hour cap was hit after the estimate said otherwise: record it, and take it to the ruling seat, since no complete `mutation.json` exists. Then:

```bash
mkdir -p .dforge/test-simplifier/downloads-mutation/before
cp /root/mutation-runs/darkcloud-downloads/web/reports/mutation/mutation.json .dforge/test-simplifier/downloads-mutation/before/mutation.json
ps -o pid=,cmd= -g "$(cat .dforge/test-simplifier/downloads-mutation/pgid)"; pgrep -af 'stryker|vitest'
```

Expected: `ps -g` prints nothing, and no `stryker` or `vitest` process whose working directory is in the clone survives (`readlink /proc/<pid>/cwd`); kill any that does, by PID. Stop the `sleep` task if it is still running. No repository file changes in this task, so there is no commit; the run notes are the task's record.

### Task 3: Analyse, report and update the register

**Files:**
- Create: `.dforge/test-simplifier/downloads-mutation/analyse.mjs`
- Test: `.dforge/test-simplifier/downloads-mutation/analyse.test.mjs` (scratch, not committed)
- Create: `docs/dforge/test-simplifier/<run-end date>-darkcloud-downloads.md`
- Modify: `docs/dforge/registers/2026-11-10-tdd-and-lifecycle-review.md` (rows 1, 8, 10, 15)

**Interfaces:**
- Consumes: the Mutation report, Run notes and the Analysis module's definitions (Contracts).
- Produces: the Report (Contracts).

**Items:** 1

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 0 = 4

- [ ] **Step 1: Write the failing test**

`.dforge/test-simplifier/downloads-mutation/analyse.test.mjs`:

```js
import { test } from "node:test"
import assert from "node:assert/strict"
import { analyse } from "./analyse.mjs"

const loc = { start: { line: 1, column: 1 }, end: { line: 1, column: 2 } }
const m = (id, status, coveredBy = [], killedBy = []) => ({ id, mutatorName: "X", location: loc, status, coveredBy, killedBy })

const report = {
  schemaVersion: "2",
  thresholds: { high: 80, low: 60 },
  files: {
    "src/features/downloads/a.ts": {
      language: "typescript",
      source: "",
      mutants: [
        m("m1", "Killed", ["d1", "a1", "d3"], ["d1", "a1"]),
        m("m2", "Killed", ["d1", "d2"], ["d1"]),
        m("m3", "Killed", ["a1", "a2"], ["a1", "a2"]),
        m("m4", "Killed", ["a3", "o1"], ["a3", "o1"]),
        m("m5", "Killed", ["d2"], ["d2"]),
        m("m6", "Timeout", ["d2"], []),
        m("m7", "Survived", ["d3"], []),
        m("m8", "NoCoverage"),
        m("m9", "Ignored"),
      ],
    },
  },
  testFiles: {
    "tests/downloads-a.test.ts": { tests: [{ id: "d1", name: "adds" }, { id: "d2", name: "removes" }, { id: "d3", name: "renders" }] },
    "tests/downloads-b.test.ts": { tests: [{ id: "d4", name: "idle" }] },
    "tests/downloads-v.acceptance.test.tsx": {
      tests: [{ id: "a1", name: "A1 shows the tray" }, { id: "a2", name: "A1 hides the tray" }, { id: "a3", name: "A2 lists folders" }],
    },
    "tests/other.test.ts": { tests: [{ id: "o1", name: "other" }] },
  },
}

const expected = {
  mutants: { total: 9, Killed: 5, Timeout: 1, Survived: 1, NoCoverage: 1, Ignored: 1, other: 0 },
  multiKiller: 3,
  greedySize: 4,
  populations: {
    downloads: { run: 7, covering: 6, killsNothing: 1, noUniqueKill: 3, outsideGreedy: 3 },
    other: { run: 1, covering: 1, killsNothing: 0, noUniqueKill: 1, outsideGreedy: 1 },
  },
  aTests: { total: 3, killsNothing: 0, allKilledByNonA: 1, allKilledBySameId: 1 },
  perFile: [
    { file: "tests/downloads-a.test.ts", run: 3, killsNothing: 1, noUniqueKill: 0, outsideGreedy: 1 },
    { file: "tests/downloads-b.test.ts", run: 1, killsNothing: 0, noUniqueKill: 0, outsideGreedy: 1 },
    { file: "tests/downloads-v.acceptance.test.tsx", run: 3, killsNothing: 0, noUniqueKill: 3, outsideGreedy: 1 },
  ],
}

test("analyse counts the fixture's kill matrix", () => {
  assert.deepEqual(analyse(report), expected)
})

test("a Timeout mutant credits no test", () => {
  const timeoutOnly = structuredClone(report)
  timeoutOnly.files["src/features/downloads/a.ts"].mutants = [m("t1", "Timeout", ["d1"], ["d1"])]
  assert.deepEqual(analyse(timeoutOnly), {
    mutants: { total: 1, Killed: 0, Timeout: 1, Survived: 0, NoCoverage: 0, Ignored: 0, other: 0 },
    multiKiller: 0,
    greedySize: 0,
    populations: {
      downloads: { run: 7, covering: 1, killsNothing: 1, noUniqueKill: 0, outsideGreedy: 7 },
      other: { run: 1, covering: 0, killsNothing: 0, noUniqueKill: 0, outsideGreedy: 1 },
    },
    aTests: { total: 3, killsNothing: 0, allKilledByNonA: 0, allKilledBySameId: 0 },
    perFile: [
      { file: "tests/downloads-a.test.ts", run: 3, killsNothing: 1, noUniqueKill: 0, outsideGreedy: 3 },
      { file: "tests/downloads-b.test.ts", run: 1, killsNothing: 0, noUniqueKill: 0, outsideGreedy: 1 },
      { file: "tests/downloads-v.acceptance.test.tsx", run: 3, killsNothing: 0, noUniqueKill: 0, outsideGreedy: 3 },
    ],
  })
})
```

Why these values: the greedy set is a1 (m1, m3; ties with d1 broken by id), then a3 (m4), d1 (m2), d2 (m5). a2's only kill, m3, is shared with a1 under the same id A1; a3's only kill, m4, is shared with the non-A test o1. d4 covers nothing, so it is neither covering nor "kills nothing". The second test pins that a Timeout's `killedBy` is ignored even if a report filled it.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 60 node --test .dforge/test-simplifier/downloads-mutation/analyse.test.mjs`
Expected: FAIL, cannot find module `./analyse.mjs`.

- [ ] **Step 3: Implement `analyse.mjs`**

1. `export function analyse(report)` computes the object the Analysis module contract defines, from `report.files[*].mutants` and `report.testFiles[*].tests`; it reads nothing else and runs no tests.
2. Kill attribution uses only mutants whose `status` is `Killed`; `coveredBy` counts for every status.
3. When run directly (`import.meta.url === pathToFileURL(process.argv[1]).href`), it reads the file named by `process.argv[2]` and prints `JSON.stringify(analyse(report), null, 2)`; a missing argument prints `usage: node analyse.mjs <mutation.json>` to stderr and exits 2.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 60 node --test .dforge/test-simplifier/downloads-mutation/analyse.test.mjs`
Expected: PASS, 2 tests.

- [ ] **Step 5: Analyse the real report**

Run: `timeout 300 node .dforge/test-simplifier/downloads-mutation/analyse.mjs .dforge/test-simplifier/downloads-mutation/before/mutation.json > .dforge/test-simplifier/downloads-mutation/analysis.json`
Expected: exit 0 and `multiKiller` above zero (spec A2). A zero means bail was not disabled and the run proves nothing about redundancy: stop and take it to the ruling seat.

- [ ] **Step 6: Check darkcloud is untouched**

Compare `git -C /root/repositories/darkcloud rev-parse HEAD` and the `sha256sum` of its `git --no-optional-locks status --porcelain` with the run notes. If either differs, list the changed paths with `git --no-optional-locks -C /root/repositories/darkcloud status --porcelain` and `git -C /root/repositories/darkcloud log --oneline <darkcloud-sha>..HEAD`; nothing this plan ran writes there, so a difference outside `web/` is the owner's own work and is reported as such, and a difference inside `web/` goes to the ruling seat before the report is written. Confirm `git -C /root/mutation-runs/darkcloud-downloads remote` prints nothing.

- [ ] **Step 7: Write the report**

`docs/dforge/test-simplifier/<run-end date>-darkcloud-downloads.md`, sections in this order:

1. **Environment (A1):** darkcloud commit, clone path, Node, Stryker and Vitest versions, the configuration from the clone's `stryker.config.json` in a code block (with any narrowing), every `command:` line, run start and end, wall time, `estimate-at-30m` and `narrowed` (A9).
2. **Mutants:** the `mutants` counts, caught = Killed + Timeout, and `multiKiller` (A2); Timeout and Ignored stated as attributed to no test (A6). Break `Ignored` down by `statusReason` (`jq '[.files[].mutants[] | select(.status=="Ignored") | .statusReason] | group_by(.) | map({(.[0]): length}) | add' < before/mutation.json`), so the static count stands apart from any comment-disabled mutants.
3. **Tests:** a table with one row per population (`downloads`, `other`) and columns run, covering, kills nothing, no unique kill, in greedy set (run minus outside greedy), outside greedy set, plus the greedy set's total size (A3).
4. **A<n> tests:** total, kills nothing, every kill also made by a non-A<n> test (row 10), every kill also made by a same-id test in the same file (row 15) (A4).
5. **Per file:** the `perFile` rows as a table, sorted by "no unique kill" descending — row 8's candidate list. No row recommends a deletion (A8).
6. **Reading:** at most 10 sentences on what the counts say about row 1's claim: the share of downloads tests outside the greedy set and with no unique kill, and the limits (one module, one project, mutants are a proxy for faults, greedy cover is an approximation).
7. **Reproduce (A5):** the command of Step 5 and the full source of `analyse.mjs` in a code block.
8. **darkcloud check (A7):** Step 6's result.

Check A5 against the embedded copy, not the file on disk: extract the report's `analyse.mjs` code block to `.dforge/test-simplifier/downloads-mutation/embedded.mjs`, then run `diff <(timeout 300 node .dforge/test-simplifier/downloads-mutation/embedded.mjs .dforge/test-simplifier/downloads-mutation/before/mutation.json) .dforge/test-simplifier/downloads-mutation/analysis.json`. Expected: no output. Then confirm every number in sections 2-5 matches `analysis.json`.

- [ ] **Step 8: Update the register (A11)**

With `bash /root/.claude-alt/plugins/cache/darkraise/dforge/4.15.2/scripts/register set docs/dforge/registers/2026-11-10-tdd-and-lifecycle-review.md <id> <state> --note "<note>"`, where each note is the row's current Note with one sentence appended:

- Row 1, state `verify`: "Result <run-end date>: <report path>: <downloads run> downloads tests, <kills nothing> kill nothing, <no unique kill> have no unique kill, <outside greedy> lie outside a greedy killing set of <greedy size>."
- Row 8, state `deferred`: "Row 1 reported <run-end date> (<report path>); offer the owner one Phase 4 wave on the clone /root/mutation-runs/darkcloud-downloads with these counts."
- Row 10, state `deferred`: "Row 1 count <run-end date>: <allKilledByNonA> of <A total> A<n> tests have every kill also made by a non-A<n> test (<report path>)."
- Row 15, state `deferred`: "Row 1 count <run-end date>: <allKilledBySameId> of <A total> A<n> tests have every kill also made by a same-id test in the same file (<report path>)."

Then run `bash /root/.claude-alt/plugins/cache/darkraise/dforge/4.15.2/scripts/register check docs/dforge/registers/2026-11-10-tdd-and-lifecycle-review.md`. Expected: `register: 0 errors`. The register's earlier change (row 1 assigned to this plan) is committed with the plan before execution, so this commit carries only Step 8's edits.

- [ ] **Step 9: Verify and commit**

Run the Task check. Expected: exit 0.

```bash
git add docs/dforge/test-simplifier/*-darkcloud-downloads.md docs/dforge/registers/2026-11-10-tdd-and-lifecycle-review.md
git commit -m "docs(dforge): report downloads mutation run"
```
