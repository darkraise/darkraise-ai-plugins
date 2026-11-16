# Next-Session Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every `## Next session` block, and every reader of one, match the repository: the router stops sending specs with plans to writing-plans, next-step gains read-only and plan-less modes, the readers recompute instead of trusting latest.md, and the Stop hook holds the turns that end a plan or a milestone without a real block.

**Architecture:** The register router moves out of `scripts/next-step` into `scripts/lib/route.sh`, where a one-pass header scan (`spec_plans`) decides how a spec's rows route. `next-step` gains `--print` (no side effects), `--project` (no plan), `--print --latest` (recompute the stored block from a marker line) and a cross-worktree ledger lookup. The cockpit band, repo-audit, the snapshot, resume-execution and project-status consume `--print`; the Stop hook gains a removed-checkout fallback, a transition trigger and a release rule that reads latest.md.

**Tech Stack:** Bash scripts and bash test suites, jq, awk; the TypeScript cockpit mod (`hooks/cockpit/*.ts(x)`) with `tests/cockpit.test.ts`; Node darkmem sync with node:test suites; Markdown skills.

**Spec:** `docs/dforge/specs/2026-11-16-next-session-routing-design.md`

**Execution:** inline — `claude --model opus --effort high` — tasks total up to 7 (Tasks 1, 3, 4, 9, 14)

**Parallelism:** sequential — inline execution

**Task check:** none — full suite every 3 tasks

**Integration check:** `timeout 1500 node scripts/test-all.mjs --jobs 6 && timeout 240 /root/.local/bin/claude plugin test plugins/dforge && timeout 60 node scripts/validate-repository.mjs && timeout 60 /root/.local/bin/claude plugin validate . && timeout 60 /root/.local/bin/claude plugin validate plugins/dforge`

**CI:** `.github/workflows/validate.yml` — platforms: uutils (ubuntu-latest), Windows Git Bash — local: `node scripts/test-all.mjs`; `node scripts/validate-repository.mjs`; `claude plugin validate plugins/dforge`; `claude plugin test plugins/dforge` — uncovered: uutils (ubuntu-latest), Windows Git Bash

**Plan review:** 2026-11-16 — dforge:judge-opus — executability 11 / coherence 13 / coverage 14 / assumptions 14 (round 1)

## Global Constraints

- Paths are repository-relative; `plugins/dforge/` is the plugin root. The work edits the unreleased source under `plugins/dforge`; the session itself runs the installed 4.17.1 from the plugin cache, so a test runs the repository's scripts, never the cache's.
- No version bump and no release. Do not edit historical plans or specs, nor any register other than `docs/dforge/registers/2026-11-16-next-session-routing.md`.
- English only. Commits are `<type>(<scope>): <subject>`, subject at most 50 characters, imperative, no period, author and committer `Darkraise <quangtc94@gmail.com>`, with no AI attribution of any kind (no `Co-Authored-By:`, `Claude-Session:` or "Generated with" text).
- Never push during the tasks: the branch merges into `main` at the end (spec `Finish: merge`).
- Every command that runs a test, a build or a CLI carries an explicit `timeout`; every process a task starts is stopped before the task closes.
- Tests never touch a real project: darkpanel is read only through a throwaway clone (`git clone --no-hardlinks`) under the session's scratch directory, deleted at the end of the step.
- A new `plugins/dforge/tests/*.test.sh` suite needs a weight in `windowsSeconds` in `scripts/test-shards.mjs` (at most 80% of its limit, 600 s by default); `scripts/test-all.mjs` finds it by name. `tests/next-step.test.sh` already weighs 500 s, so new next-step cases go in `tests/route.test.sh` or `tests/next-step-print.test.sh`, not there.
- An existing assertion may be rewritten only where the spec changes the behaviour it pins, and the task names it.
- `next-step`'s printed block keeps its current text for every mode the spec does not change; the marker line goes only into latest.md (C4).
- Windows Git Bash: a native program (`git.exe`, `jq.exe`) given a path built from `$PWD`, `$(pwd)` or `$TMPDIR` gets a POSIX form it cannot open, or has its argument rewritten when path conversion is on (`MSYS_NO_PATHCONV` unset). Convert the path with `cygpath -m` before the call (dforge's `dr_native_path`, `plugins/dforge/scripts/lib/native-path.sh`), and feed `jq` a file on stdin in a script that exports `MSYS_NO_PATHCONV`.
- Windows Git Bash: the same directory is `/c/Users/x` in the shell and `C:/Users/x` from a native tool, so a string comparison never matches. Normalise both sides with `cygpath -m`, or compare with `-ef`.
- Windows Git Bash: files a Windows tool wrote, and native program output, end lines with `\r`, which `read`, `awk` and `[ = ]` keep. Pipe through `tr -d '\r'` before comparing or parsing.
- Windows Git Bash: `awk -v name=value` processes backslash escapes in the value, so a regex or a Windows path changes. Pass the value in the environment and read `ENVIRON["NAME"]`.
- Windows Git Bash: Node's `import()` of an absolute `D:/x/y.mjs` reads `d:` as a URL scheme and fails. Import with `import(pathToFileURL(path).href)`.
- uutils (ubuntu-latest): a lock built on `mkdir` failing when the directory exists does not exclude a second process. Create the lock file with `set -C` (noclobber), or use `flock`.
- uutils (ubuntu-latest): `timeout` signals only the command it started, so the command's children keep running. Run the command in its own process group (`setsid`) and signal the group.
- CI awk is gawk and local awk is mawk: write portable awk, and never build a dynamic regex inside a per-line loop. File times are read with the two-form stat helper of `scripts/lib/snapshot.sh` (`stat -c %Y` else `stat -f %m`) or compared with `[ -nt ]`.

## Contracts

- **C1 `route_rows`** (`plugins/dforge/scripts/lib/route.sh`; Task 1 creates, Task 2 extends, Tasks 4-5 call). Sourced; called in the caller's own shell, never inside `$(…)`. Reads open rows on stdin, one per line: `<register>\t<id>\t<item>\t<assigned>\t<acceptance>\t<state>\t<note>`, where `<register>` is the register file's path. Reads the globals `ROUTE_ROOT` (the checkout), `ROUTE_FINISHED` (the repository-relative name of the plan `--complete` is completing, empty otherwise) and `ROUTE_MS` (the `roadmap_current` line, empty without one) and `ROUTE_OUTSIDE_MS` (`1` when a register outside the milestone holds an open row). Sets: `ROUTE_KIND` (`plan`, `spec`, `followup`, `label`, `rule`, `milestone` or empty), `ROUTE_TARGET`, `ROUTE_ACTION` (the sentence appended to the Next line), `ROUTE_LAUNCH_CMD`, `ROUTE_LAUNCH_PLAN`, and the comma lists `ROUTE_WAITING` (`verify` rows), `ROUTE_BUILT` (rule 4 rows), `ROUTE_STALE`, `ROUTE_ELSEWHERE`, `ROUTE_UNRECORDED` (rows of `#<id>`). Task 1 reproduces today's routing exactly; Task 2 adds the spec rules.
- **C2 `spec_plans ROOT SPEC`** (`route.sh`; Task 2). Prints, one per line and once per name key, the repository-relative name of every plan file under the plan directory of each place `_plan_roots ROOT` lists whose header `**Spec:**` or `**Program:**` line names SPEC (compared by `dforge_name_key`). A plan is a file with a `Task N` heading outside a fence; `completed.md` is never one. One awk pass over all candidate files, stripping `\r` and resetting fence state per file.
- **C3 `plan_ledger_any ROOT PLAN`** (`plugins/dforge/scripts/lib/plan.sh`; Task 4 creates it and makes `route_rows` use it; read by Task 6). Prints `<ledger path>\t<checkout>` for the first `progress.md` whose identity line names PLAN by name key: this checkout's ledger directory first, then each line of `dforge_ledger_files ROOT` (for a `mirror` line, `<checkout>` is the worktree holding `<state>/sdd/<slug>`, else ROOT). Status 1 with nothing printed when none.
- **C4 marker line** (Task 3 writes; Tasks 6, 7, 8, 14 read). The last line of latest.md's `## Next session` section on every next-step write, never in the printed block:
  `<!-- next-step: kind=<plan|complete|kept|project|draft|adhoc> [branch=<name>] done=<n> closed=<n> subject=<name or -> at=<epoch seconds> -->`.
  `branch=` only for `kept`. `done` counts the backticked plan entries of `completed.md` (0 when absent); `closed` counts the milestones `scripts/roadmap status` reads `closed` (0 without a roadmap). `subject=` runs to the last ` at=`; `-` for `project` and `adhoc`.
- **C5 next-step command line** (Tasks 3-6). `next-step [--host claude|codex] [--print] (PLAN_FILE | --complete PLAN_FILE | --kept PLAN_FILE | --project [--keep-notes] | --latest | --draft DRAFT --next ACTION | --adhoc --phase design|build --next ACTION)`. `--print` writes nothing, creates no file or directory, deletes no finish.json and skips the in-flight check. `--latest` requires `--print` (else exit 2). Exits: 0 ok; 2 usage or missing file; 3 plan has no tasks; 4 block printed but latest.md not written; 5 background work running (never under `--print`); 6 `--print --latest` has nothing to resume.
- **C6 `--print --latest` output** (Task 6; read by Tasks 7, 8). The recomputed block exactly as the matching `--print` mode prints it, then one line: the C4 marker used (for a file with no marker, `<!-- next-step: kind=none subject=- at=<latest.md mtime> -->`). Exit 6 prints at most one reason line on stderr and nothing on stdout.
- **C7 milestone audit wording** (Task 2 prints; Task 12's skill text reads it). The milestone route's Next line keeps today's sentence `Milestone <id> (<name>) has nothing else open: audit and close it with dforge:closing-a-milestone.` and, when `ROUTE_BUILT` is not empty, is preceded by `Built, awaiting the audit: <#ids>.`, the ids joined by `, ` (`#1, #2`)
- **C8 `ending_released MESSAGE STAMP LATEST`** (`plugins/dforge/scripts/lib/next-ending.sh`; Task 9; read by Task 10). Status 0 when LATEST is newer than STAMP and MESSAGE contains LATEST's `**Next:**` line (the text after `**Next:** `, verbatim); or when MESSAGE has a line reading exactly `## Next session` and LATEST cannot be written (it exists and is not writable, or it is absent and its nearest existing parent directory is not writable). Status 1 otherwise. No process beyond `grep`/`awk` per call.

## Assumptions (evidence)

- The register router lives at `plugins/dforge/scripts/next-step:294-401`, and its `kind=spec` branch has no plan check: read 2026-11-16; reproduced on a darkpanel clone the same day (`next-step --complete docs/dforge/plans/2026-11-15-v1-w12g-security-followup.md` printed "`docs/dforge/specs/2026-10-21-v1-completion-design.md`: write its plan").
- `roadmap close` refuses a milestone while any of its rows is unresolved (`plugins/dforge/scripts/roadmap:307-311`), and darkpanel M5's epic rows are `doing`/`open` (`/root/repositories/darkpanel/docs/dforge/registers/2026-10-17-m5-tailscale.md:8-11`): unverified that setting them `done` is enough for `roadmap close M5` — Task 1 verifies it.
- The cockpit can run plugin scripts with `$.process.run([...], { timeoutMs })` (`plugins/dforge/hooks/cockpit/register.tsx:3017`), and `readResumeOffer` is awaited from `readRun` (`register.tsx:3698`), itself awaited after every Bash tool call (`register.tsx:911`): read 2026-11-16.
- `turn-start` records the common git directory as line 1 of `$stamp.refs` (`plugins/dforge/scripts/lib/turn-refs.sh:4-10`) and deletes the file when the cwd is not a repository (`plugins/dforge/scripts/turn-start.sh:24-28`): read 2026-11-16.
- The darkmem push refuses a latest.md whose `## State` names no plan or draft (`plugins/dforge/scripts/lib/darkmem-push.mjs:402-406`, `plugins/dforge/scripts/lib/darkmem-mirror.mjs:759-766`): by reading; Task 14 reproduces it.
- `ar_fenced` reads the first fence after "Paste as the first prompt:" (`plugins/dforge/scripts/lib/auto-run.sh:453-460`) and `resumeOfferOf` likewise (`plugins/dforge/hooks/cockpit/lib.ts:1577-1591`), so a marker line after the block changes neither: Fable spec review round 1, 2026-11-16.
- Recompute cost on Linux, darkpanel clone, 2026-11-16: `next-step --complete` 1,953 ms, plain `next-step PLAN` 563 ms. Windows Git Bash unmeasured: the `next-step-print` suite records one figure in its log (Task 6) against a 10-second budget.
- Borderline plan-review scores (executability 11, coherence 13, round 1 of a cap of 1): every Critical and Important finding of that round was fixed in place (the completing plan counts as finished in Task 2; the full fixture list in Task 9 and the ui-hooks check; `ROUTE_OUTSIDE_MS` for `--project`; A6 for `--project` and `--latest`; C3's readers; the darkpanel `--project` probe in Task 5; the cockpit's primary checkout from `S.where.primary`), so execution proceeds without a second round.

## Task index

1. Verify the built-row close and extract the router
2. Route spec rows by the spec's plans
3. Add --print and the latest.md marker
4. Answer plain next-step from completed.md and any worktree's ledger
5. Add the plan-less --project mode
6. Recompute the stored block with --print --latest
7. Recompute in repo-audit and the snapshot
8. Recompute the cockpit resume offer
9. Release a held turn only on a real block
10. Hold transition turns and survive a removed checkout
11. Keep notes in roadmap settle and pin the built-row close
12. End milestone and finishing flows on a computed block
13. Point readers and Codex at the computed block
14. File project checkpoints in darkmem

---

### Task 1: Verify the built-row close and extract the router

**Files:**
- Create: `plugins/dforge/scripts/lib/route.sh`
- Modify: `plugins/dforge/scripts/next-step` (the `if [ -n "$open_rows" ]` branch of the `--complete` path)

**Interfaces:**
- Produces: C1 `route_rows` with today's behaviour.

**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7
**Implementer:** dforge:impl-opus-high

- [ ] **Step 1: No new test, because the extraction keeps behaviour and `tests/next-step.test.sh` pins every router branch (plan, spec, label, rule, verify, stale, elsewhere, milestone)**

Before the extraction, verify the spec's riskiest assumption on a throwaway clone:

```bash
S=$(mktemp -d) && git clone -q --no-hardlinks /root/repositories/darkpanel "$S/dp" && cd "$S/dp" \
  && R=docs/dforge/registers/2026-10-17-m5-tailscale.md \
  && for id in 1 2 3 4; do timeout 30 bash /root/repositories/darkraise-ai-plugins/plugins/dforge/scripts/register set "$R" "$id" done; done \
  && timeout 60 bash /root/repositories/darkraise-ai-plugins/plugins/dforge/scripts/roadmap open M5; echo "open exit=$?"; \
  timeout 60 bash /root/repositories/darkraise-ai-plugins/plugins/dforge/scripts/roadmap close M5 --note "probe"; echo "close exit=$?"; cd / && rm -rf "$S"
```

Expected: `open exit=0` and `close exit=0`. Record the two exits in the ledger as `Task 1: Ruling: built-row close probe — open <e>, close <e> — none`. If `close` refuses for a reason other than these rows, the spec's §4 is not enough: stop and take it up the ruling ladder before Task 2. The router half of the riskiest assumption (does darkpanel's M5 route to its audit) needs `--project` and is probed in Task 5 Step 5.

- [ ] **Step 2: Run the covering suite before the change**

Run: `timeout 900 bash plugins/dforge/tests/next-step.test.sh`
Expected: PASS (the baseline).

- [ ] **Step 3: Implement**

1. Create `route.sh`, sourced by `next-step` next to `lib/roadmap.sh`. Move the loop that reads `open_rows` and classifies each row (the block beginning `stale="" waiting="" elsewhere="" best=9 target="" kind=""` through the `case $kind in … esac` that sets `action`) into `route_rows` as C1 states. `open_rows` gains the register path as its first field, so the row list and the reg_list keep using the item and id fields at their new positions.
2. In `next-step`, build the C1 input lines while iterating the registers (prefix each `register_open` line with the register's path), set the `ROUTE_*` globals from the current values (`$rel`, `$current_ms`, `$outside_ms`), call `route_rows`, and read `kind`, `target`, `action`, `waiting`, `stale`, `elsewhere`, `launch_cmd` and `launch_plan` back from the `ROUTE_*` outputs. The printed text of every branch stays byte-identical.

- [ ] **Step 4: Run the covering suite**

Run: `timeout 900 bash plugins/dforge/tests/next-step.test.sh`
Expected: PASS, the same check count as Step 2.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/route.sh plugins/dforge/scripts/next-step
git commit -m "refactor(dforge): move next-step's router to route.sh"
```

### Task 2: Route spec rows by the spec's plans

**Files:**
- Modify: `plugins/dforge/scripts/lib/route.sh`
- Create: `plugins/dforge/tests/route.test.sh`
- Modify: `scripts/test-shards.mjs` (`windowsSeconds`: `'route.test.sh': 120`)

**Interfaces:**
- Consumes: C1.
- Produces: C2 `spec_plans`; C1's `followup`, `ROUTE_BUILT` and `ROUTE_UNRECORDED`; C7.

**Items:** 1, 3

**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6
**Implementer:** dforge:impl-opus-high

- [ ] **Step 1: Write the failing test**

`tests/route.test.sh` builds each fixture in a fresh `git init` repository under `$TMP` with `docs/dforge/{plans,specs,registers}`, a `docs/dforge/plans/completed.md` index (first line `# Completed plans`, entries ``- 2026-10-01 — `docs/dforge/plans/<name>.md` — merged``), and runs `plugins/dforge/scripts/next-step --complete <finished plan>` inside the fixture, reading stdout (the fixture's own latest.md absorbs the write). Model the fixture helpers on `tests/next-step.test.sh`'s register and roadmap fixtures.

- `tests/route.test.sh::a live plan of the spec takes the row` (integration): given register R covering nothing with row 1 `doing` assigned to `docs/dforge/specs/S.md`, plan P2 (`**Spec:** docs/dforge/specs/S.md`, dated after completed.md's first entry, not indexed), and the finished plan P1 indexed, asserts the Next line names P2 with `dforge:executing-plans` and contains no `write its plan`; fails today because the `kind=spec` branch routes S to writing-plans (A1).
- `tests/route.test.sh::a spec with no plan still goes to writing-plans` (integration): given the same row and no plan naming S, asserts `` `docs/dforge/specs/S.md`: write its plan with dforge:writing-plans.``; passes today and must keep passing (A2).
- `tests/route.test.sh::a built epic row sends the milestone to its audit` (integration): given a roadmap whose current milestone M1 has register E (not covering S) with row 1 `doing` assigned to S, every plan naming S indexed, and nothing else open, asserts the Next line contains `Built, awaiting the audit: #1.` and `Milestone M1 (` … `audit and close it with dforge:closing-a-milestone.`; fails today because S routes to writing-plans (A3, C7).
- `tests/route.test.sh::an open requirement row after the last plan asks for a follow-up plan` (integration): given register Q covering S with row 2 `open` assigned to S and every plan naming S indexed, asserts `write a follow-up plan for rows #2 with dforge:writing-plans.`; fails today (A4).
- `tests/route.test.sh::a Program line counts as naming the spec` (integration): the first case with P2's header carrying `**Program:** docs/dforge/specs/S.md — sub-project 2 of 3 — next: x` and a different `**Spec:**`, asserts P2 is routed; fails today (A5).
- `tests/route.test.sh::the lower sub-project wins among live plans` (integration): two live plans of S, `sub-project 3` dated earlier and `sub-project 2` dated later, asserts sub-project 2's plan is named; a second variant without Program lines asserts the older filename date wins; fails today (A23).
- `tests/route.test.sh::unindexed plans are listed as outcome unrecorded` (integration): the first case without completed.md (P1 finished via `--complete` anyway), and again with P2 dated before completed.md's first entry, asserts the Next line contains `plans exist, outcome unrecorded: #1` and neither `executing-plans` nor `write its plan`; fails today (A24).
- `tests/route.test.sh::the plan being completed counts as finished` (integration): P1 (the plan `--complete` names) is the only plan of S and not yet indexed; with row 2 `open` assigned to S in a register covering S, asserts `write a follow-up plan for rows #2 with dforge:writing-plans.`; with epic row 1 `doing` assigned to S in a milestone register not covering S and nothing else open, asserts `Built, awaiting the audit: #1.`; neither output names P1 or contains `write its plan`; fails today because the `kind=spec` branch routes to writing-plans.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/route.test.sh`
Expected: FAIL on every case except "a spec with no plan still goes to writing-plans".

- [ ] **Step 3: Implement**

1. `spec_plans ROOT SPEC` as C2: collect the `*.md` files of each `_plan_roots ROOT` plan directory (`<docs>/plans`), skip `completed.md`, and read them in one awk program that prints `FILENAME\t<Spec value>\t<Program spec>` for files holding a `Task N` heading outside a fence; then keep the names whose value matches SPEC by `dforge_name_key`, deduplicated by key.
2. In `route_rows`, for a row whose Assigned names an existing file with no tasks (today's `r=2 k=spec`): take `spec_plans "$ROUTE_ROOT" "$a"` and split it into finished and live: a plan is finished when `plan_finished` says so or when it is `ROUTE_FINISHED` (the plan being completed counts as finished, never as live, and never as "no plans"). Live plans count only when completed.md exists beside them and the plan's filename date (`YYYY-MM-DD` prefix) is not older than completed.md's first entry date; a live plan failing that guard adds the row to `ROUTE_UNRECORDED`.
   - no plans at all: today's spec route;
   - a counted live plan: route as `kind=plan` to the pick (lowest `sub-project <k>` on its Program line, else the oldest filename date), ranked with today's plan rows (r=1); the action adds ` If it was abandoned, record it in completed.md or delete it.`;
   - all finished and the row's register covers S (`register_covers <register>` names S by key): `kind=followup` (rank 2): ``"`S`: write a follow-up plan for rows #<ids> with dforge:writing-plans."`` collecting every such row of S;
   - all finished and the register does not cover S: add `#<id>` to `ROUTE_BUILT` and treat it as a `verify` row for the milestone branch;
   - `ROUTE_UNRECORDED` rows route nowhere; the Next line names them as `plans exist, outcome unrecorded: <#ids>.`
3. The milestone branch fires when `ROUTE_WAITING` or `ROUTE_BUILT` is non-empty and nothing else is set; it prints C7. With no roadmap and only built rows, `next-step` falls through to its Program-line branches as if no row were open.
4. Add the weight to `scripts/test-shards.mjs`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/route.test.sh && timeout 900 bash plugins/dforge/tests/next-step.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/route.sh plugins/dforge/tests/route.test.sh scripts/test-shards.mjs
git commit -m "fix(dforge): route spec rows by the spec's plans"
```

### Task 3: Add --print and the latest.md marker

**Files:**
- Modify: `plugins/dforge/scripts/next-step` (argument parsing, the in-flight check, the finish.json removal, `write_handoff`)
- Create: `plugins/dforge/tests/next-step-print.test.sh`
- Modify: `scripts/test-shards.mjs` (`windowsSeconds`: `'next-step-print.test.sh': 150`)

**Interfaces:**
- Produces: C4 marker; C5 `--print` and the exit table.

**Items:** 1

**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7
**Implementer:** dforge:impl-opus-high

- [ ] **Step 1: Write the failing test**

- `tests/next-step-print.test.sh::--print changes nothing` (integration): for each of `PLAN`, `--complete PLAN`, `--kept PLAN` in a fixture repository with an existing latest.md and `.dforge/sdd/finish.json`, records `sha256sum` and `stat` mtimes of both and the list of files under `.dforge`, runs `next-step --print …`, asserts the same hashes, mtimes and file list, and exit status 0; a second variant with no `.dforge/handoff` directory asserts none is created; fails today because `--print` is a usage error (A6).
- `tests/next-step-print.test.sh::--print ignores running background work` (integration): with a stub `in-flight` on a copied plugin tree that exits 1, asserts `next-step --print PLAN` exits 0 and prints the block, while plain `next-step PLAN` still exits 5; fails today (A6).
- `tests/next-step-print.test.sh::latest.md carries the marker and the block does not` (integration): runs `next-step PLAN`, `--complete PLAN`, `--kept PLAN`, `--draft D --next "x"` and `--adhoc --phase build --next "x"`; asserts stdout has no `<!-- next-step:` line, and latest.md's `## Next session` section ends with a line matching `^<!-- next-step: kind=(plan|complete|kept|draft|adhoc)( branch=[^ ]+)? done=[0-9]+ closed=[0-9]+ subject=.+ at=[0-9]+ -->$` with the expected kind, `branch=` only for `kept`, `subject=` the plan or draft name (`-` for adhoc), and `done=` the fixture's completed.md entry count; fails today (A11).
- `tests/next-step-print.test.sh::the auto run still reads the first prompt` (integration): after `next-step PLAN` writes latest.md, sources `scripts/lib/auto-run.sh` and asserts `ar_fenced <latest.md> 'Paste as the first prompt:'` prints the prompt line and `ar_fenced <latest.md> 'Launch in '` the launch command, unchanged from before the marker; fails today only if the marker breaks parsing, so it pins A11's negative half.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/next-step-print.test.sh`
Expected: FAIL on the `--print` and marker cases.

- [ ] **Step 3: Implement**

1. Parse `--print` wherever it sits, as `--host` is pulled out today, into `print_only=1`.
2. Under `print_only`: skip the in-flight block, the finish.json `rm -f`, the `mkdir -p` and lock, and `write_handoff`; print the block and exit 0.
3. Otherwise `write_handoff` appends the C4 marker as the last line of the block it writes (both the wholesale and the section-replace branches). `done` counts lines of `<docs>/plans/completed.md` holding a backticked `.md` name; `closed` counts `scripts/roadmap status` lines whose state field is `closed` (0 without a roadmap); `branch=` is the branch `--kept` names; `subject=` is `$rel` for plan, complete and kept, the draft's name for draft, `-` for adhoc.
4. Add the weight.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/next-step-print.test.sh && timeout 900 bash plugins/dforge/tests/next-step.test.sh && timeout 600 bash plugins/dforge/tests/auto-run.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/next-step plugins/dforge/tests/next-step-print.test.sh scripts/test-shards.mjs
git commit -m "feat(dforge): add next-step --print and a marker"
```

### Task 4: Answer plain next-step from completed.md and any worktree's ledger

**Files:**
- Modify: `plugins/dforge/scripts/lib/plan.sh` (new `plan_ledger_any`)
- Modify: `plugins/dforge/scripts/next-step` (the plain-plan path's ledger lookup and a completed.md check before it)
- Modify: `plugins/dforge/scripts/lib/route.sh` (plan rows find their ledger with `plan_ledger_any`)
- Test: `plugins/dforge/tests/next-step-print.test.sh`, `plugins/dforge/tests/route.test.sh`

**Interfaces:**
- Consumes: C1, C5.
- Produces: C3 `plan_ledger_any`.

**Items:** 5

**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7
**Implementer:** dforge:impl-opus-high

- [ ] **Step 1: Extend the test `tests/next-step-print.test.sh`**

- `tests/next-step-print.test.sh::an indexed plan is answered as complete` (integration): a plan listed in completed.md, with no ledger; asserts `next-step --print PLAN`'s `**Next:**` line equals `next-step --print --complete PLAN`'s, and contains no `Start at Task 1`; fails today because the plain path ignores completed.md (A8).
- `tests/next-step-print.test.sh::a ledger in a linked worktree is found from the primary` (integration): primary checkout plus `git worktree add $TMP/wt -b feat`; the ledger `.dforge/sdd/<slug>/progress.md` exists only in `$TMP/wt`, records Task 1 complete of 3 and has no `Final review:` line; from the primary, asserts the Status line reads `1 of 3 tasks complete`, the Next line `Resume at Task 2`, and the prompt contains ``First enter the existing worktree `$TMP/wt` ``; a second variant with all tasks complete and a clean line at the worktree's HEAD asserts `the final review is clean` (read against the worktree, not `rewritten`); fails today (A9).
- `tests/route.test.sh::a plan row resumes a worktree ledger` (integration): a register row assigned to a live plan whose ledger is only in a linked worktree; asserts the action is `Resume … with dforge:resume-execution.`; fails today because `plan_ledger` reads only this checkout.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/next-step-print.test.sh; timeout 600 bash plugins/dforge/tests/route.test.sh`
Expected: FAIL on the three new cases.

- [ ] **Step 3: Implement**

1. `plan_ledger_any ROOT PLAN` per C3, using `ledger_plan` and `dforge_name_key` as the plain path does today.
2. In the plain path, before the ledger read: when `plan_finished "$root" "$rel"`, set `complete=1` and continue through the `--complete` branch (its write-mode side effects apply; under `--print` none do).
3. When this checkout's ledger is missing or names another plan, use `plan_ledger_any`; pass the found checkout to `plan_final_review_state` and use it in place of `$root` for the "First enter the existing worktree" sentence.
4. In `route_rows`, the plan route's `plan_ledger` test becomes `plan_ledger_any`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/next-step-print.test.sh && timeout 600 bash plugins/dforge/tests/route.test.sh && timeout 900 bash plugins/dforge/tests/next-step.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/plan.sh plugins/dforge/scripts/next-step plugins/dforge/scripts/lib/route.sh plugins/dforge/tests/next-step-print.test.sh plugins/dforge/tests/route.test.sh
git commit -m "fix(dforge): read completed.md and worktree ledgers"
```

### Task 5: Add the plan-less --project mode

**Files:**
- Modify: `plugins/dforge/scripts/next-step` (a `--project` branch beside `--adhoc`)
- Test: `plugins/dforge/tests/route.test.sh`, `plugins/dforge/tests/next-step-print.test.sh`

**Interfaces:**
- Consumes: C1, C5.
- Produces: C5 `--project [--keep-notes]`, `kind=project` markers.

**Items:** 6

**Evaluation:** files 1 - spec 2 - coupling 1 - risk 1 = 5
**Implementer:** dforge:impl-sonnet-high

- [ ] **Step 1: Extend the test `tests/route.test.sh`**

- `tests/route.test.sh::--project audits a milestone of verify or built rows` (integration): roadmap with current milestone M1 whose register holds one `verify` row and one built epic row (Task 2's fixture); asserts `next-step --print --project` prints `**Status:** Project: milestone M1 (` … `) is current.` and the C7 milestone Next line with a launch; fails today because `--project` is a usage error (A7).
- `tests/route.test.sh::--project with nothing open and no roadmap prints Nothing` (integration): no roadmap, every register row resolved; asserts `**Status:** Project: no roadmap.`, `**Next:** Nothing — no register holds an unresolved row.` and no `Paste as the first prompt:`; fails today (A7).
- `tests/route.test.sh::--project with every milestone closed scans every register` (integration): every milestone closed, one open row in a register outside them assigned to a label; asserts `Project: every milestone is closed.` and the label route; fails today.
- `tests/next-step-print.test.sh::--print --project changes nothing` (integration): Task 3's side-effect check (hashes, mtimes, file list of latest.md, finish.json and `.dforge`) run for `next-step --print --project`; fails today because `--project` is a usage error (A6).
- `tests/route.test.sh::--project replaces latest.md unless told to keep notes` (integration): latest.md with a `## State` section; after `next-step --project` the file holds no `## State`; after a second write with `--keep-notes` the notes written before it survive above the block; both end with a `kind=project subject=-` marker; fails today.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/route.test.sh; timeout 600 bash plugins/dforge/tests/next-step-print.test.sh`
Expected: FAIL on the five new cases.

- [ ] **Step 3: Implement**

1. Parse `--project` and `--keep-notes` (C5). With `--project`: `root`/`primary` as `--adhoc` computes them; registers are `roadmap_unresolved` of the current milestone when one exists, else every `<docs>/registers/*.md` with `register_open` output; call `route_rows` with `ROUTE_FINISHED=""` and `ROUTE_OUTSIDE_MS=""` (with a current milestone only its registers are read, so no row is outside it).
2. Status per spec §2; nothing open: the milestone audit when a milestone is current (today's "has nothing open" branch text), else the Nothing line with `launch=0`.
3. Writes latest.md wholesale like `--complete` unless `--keep-notes`, then section-replace; the marker is `kind=project subject=-`. `--host` applies to its launch command.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/route.test.sh && timeout 600 bash plugins/dforge/tests/next-step-print.test.sh && timeout 900 bash plugins/dforge/tests/next-step.test.sh`
Expected: PASS.

- [ ] **Step 5: Darkpanel probe**

On a throwaway clone of `/root/repositories/darkpanel` (as Task 1's probe), run `timeout 120 bash /root/repositories/darkraise-ai-plugins/plugins/dforge/scripts/next-step --print --project` and record its `**Next:**` line in the ledger as `Task 5: Ruling: darkpanel --project probe — <Next line> — none`; delete the clone. If it does not name milestone M5's audit, stop and take it up the ruling ladder: the spec's riskiest assumption failed on real data.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/scripts/next-step plugins/dforge/tests/route.test.sh plugins/dforge/tests/next-step-print.test.sh
git commit -m "feat(dforge): add the plan-less next-step --project"
```

### Task 6: Recompute the stored block with --print --latest

**Files:**
- Modify: `plugins/dforge/scripts/next-step` (a `--latest` branch)
- Test: `plugins/dforge/tests/next-step-print.test.sh`

**Interfaces:**
- Consumes: C3, C4, C5.
- Produces: C6.

**Items:** 1, 4

**Evaluation:** files 1 - spec 2 - coupling 2 - risk 1 = 6
**Implementer:** dforge:impl-opus-high

- [ ] **Step 1: Extend the test `tests/next-step-print.test.sh`**

Each case writes latest.md by hand with a chosen marker, then runs `next-step --print --latest` and checks stdout, stderr and the exit.

- `…::a superseded unplanned block is hidden` (integration): `kind=adhoc done=1 closed=0`, completed.md now holding 2 entries; asserts exit 6 and empty stdout; the same with `closed=0` and a roadmap with one closed milestone; and the same block with matching counts asserts exit 0 and the stored block (A10).
- `…::a draft named by a plan is superseded` (integration): `kind=draft subject=docs/dforge/specs/D.md`, a plan whose `**Spec:**` is D; asserts exit 6 (A26).
- `…::a file with no marker prints the stored block` (integration): asserts exit 0, the stored block, and the last line matching `^<!-- next-step: kind=none subject=- at=[0-9]+ -->$` with `at` equal to latest.md's mtime (A25).
- `…::a kept block follows its branch` (integration): `kind=kept branch=feat subject=P`; with `feat` unmerged asserts the stored block; after indexing P in completed.md asserts the `--complete` Next line; after `git branch -D feat` (P unindexed) asserts exit 6; after merging `feat` into the primary's HEAD asserts exit 6 (A27).
- `…::a plan block never moves back to Task 1` (integration): `kind=plan subject=P`, a stored Status line `Plan … 2 of 3 tasks complete …`, no ledger anywhere, P not indexed; asserts exit 6 with `the ledger is gone and the plan is unrecorded` on stderr (A28).
- `…::a plan block is recomputed from its ledger` (integration): `kind=plan`, a stored Next `Resume at Task 2`, the ledger now recording Task 2 complete; asserts the Next line `Resume at Task 3` and the stored marker as the last line.
- `…::--print --latest changes nothing` (integration): Task 3's side-effect check run for `next-step --print --latest` with a `kind=plan` marker and with a `kind=project` marker (the recompute runs the script again as a subprocess); fails today (A6).
- `…::edges` (integration): no latest.md → exit 6; latest.md without `## Next session` → exit 6; `next-step --latest` without `--print` → exit 2; `kind=plan subject=` a missing plan → exit 2 passed through.
- `…::Windows timing` (integration): on a generated fixture of 1,000 register rows across 10 registers and 25 plans naming one spec, runs `--print --latest` with a `kind=project` marker and prints `next-step-print: --print --latest took <ms> ms` to the log; asserts under 10,000 ms only when `uname -s` is `Linux`, and always prints the figure (the Windows shard's log carries it).

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/next-step-print.test.sh`
Expected: FAIL on the `--latest` cases.

- [ ] **Step 3: Implement**

1. `--latest` (requires `print_only`, else usage): read latest.md (`dforge_latest_file`); exit 6 when missing or without the section. Parse the marker: `kind`, optional `branch`, `done`, `closed`, `subject` (to the last ` at=`), `at`.
2. Dispatch per spec §2: `plan` → recompute as `--print PLAN` (Task 4's path) unless the stored Status counts completed tasks (`[1-9][0-9]* of [0-9]+ tasks complete`) while `plan_ledger_any` finds nothing and the plan is not indexed → stderr line and exit 6; `complete` → `--print --complete`; `kept` → stored block, `--complete` once indexed, exit 6 when `git rev-parse --verify --quiet refs/heads/<branch>` fails or `git merge-base --is-ancestor <branch> <primary HEAD>` succeeds; `project` → `--print --project`; `draft`/`adhoc` → stored block unless the current counts exceed the marker's or (draft) `spec_plans` names the subject → exit 6; no marker → stored block with the `kind=none` line.
3. Recomputing re-runs the script itself with the sub-mode (`bash "$0" --host "$host" --print …`, so a Codex launch line survives), passing exits 2 and 3 through, then prints the marker used as the last line (C6).

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/next-step-print.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/next-step plugins/dforge/tests/next-step-print.test.sh
git commit -m "feat(dforge): recompute latest.md with --print --latest"
```

### Task 7: Recompute in repo-audit and the snapshot

**Files:**
- Modify: `plugins/dforge/scripts/repo-audit` (the `## Handoff` section)
- Modify: `plugins/dforge/scripts/lib/snapshot.sh` (`snapshot_latest`)
- Test: `plugins/dforge/tests/repo-audit.test.sh`, `plugins/dforge/tests/snapshot.test.sh`

**Interfaces:**
- Consumes: C4, C6.

**Items:** 9

**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6
**Implementer:** dforge:impl-opus-high

- [ ] **Step 1: Write the failing test**

- `tests/repo-audit.test.sh::the handoff lines are recomputed` (integration): latest.md with a `kind=plan` marker and a stored Next `Resume at Task 2` while the ledger records Task 2 complete; asserts the Handoff section prints `recomputed from the repository` and `- **Next:** Resume at Task 3`; fails today because the stored lines are printed (A14).
- `tests/repo-audit.test.sh::a superseded handoff says nothing to resume` (integration): a `kind=adhoc done=0` marker and one completed.md entry; asserts `- nothing to resume (the stored block is superseded)`; fails today (A14).
- `tests/repo-audit.test.sh::a failed recompute prints the stored lines` (integration): a `kind=plan` marker whose subject is a missing file; asserts the stored Status and Next lines under `stored, not recomputed: next-step: no such file` (first error line); fails today (A14).
- `tests/snapshot.test.sh::the snapshot drops the marker and ages from at` (unit): latest.md whose marker has `at` 7,200 s before now and whose mtime is now; asserts `snapshot_latest` output contains no `<!-- next-step:` and its age reads ` (2h old)`; fails today.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/repo-audit.test.sh; timeout 120 bash plugins/dforge/tests/snapshot.test.sh`
Expected: FAIL on the four new cases.

- [ ] **Step 3: Implement**

1. repo-audit: run `bash "$here/with-timeout" 20 bash "$here/next-step" --print --latest` from `$primary` (`here` is repo-audit's script directory); exit 0 → `- recomputed from the repository` then its Status and Next lines prefixed `- `; exit 6 → the nothing line; else the stored lines under `- stored, not recomputed: <first stderr or stdout line>`. Keep the commit-count line.
2. `snapshot_latest`: drop the marker line from `block`, and take the age from the marker's `at` when present, else the mtime as today.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/repo-audit.test.sh && timeout 120 bash plugins/dforge/tests/snapshot.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/repo-audit plugins/dforge/scripts/lib/snapshot.sh plugins/dforge/tests/repo-audit.test.sh plugins/dforge/tests/snapshot.test.sh
git commit -m "fix(dforge): recompute handoff lines in repo-audit"
```

### Task 8: Recompute the cockpit resume offer

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx` (`readResumeOffer`, `offerNow`, `drawResumeBand`)
- Modify: `plugins/dforge/hooks/cockpit/lib.ts` (a marker parser beside `resumeOfferOf`; `promptRegisters` stays only if the fallback uses it)
- Test: `plugins/dforge/tests/cockpit.test.ts` (`describe('resume offer')` and the resume tests near "offers Resume for a handoff under .dforge")

**Interfaces:**
- Consumes: C4, C6.

**Items:** 1, 4

**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6
**Implementer:** dforge:impl-opus-high

- [ ] **Step 1: Extend the test `tests/cockpit.test.ts::resume offer`**

The tests stub `$.process.run` for the `next-step --print --latest` command, recording each call.

- `cockpit.test.ts::resume offer › shows the recomputed block` (integration): latest.md stores Next `Write the plan`, the stub prints a block with Next `Resume at Task 3` and a marker `at`; asserts the band text contains `Next: Resume at Task 3` and Resume submits the stub's prompt; fails today because the stored text is shown (A12).
- `…› hides the offer when nothing is to resume` (integration): stub exit 6; asserts no band and no card; fails today (A12).
- `…› falls back on a failed run and marks it` (integration): stub exit 1, then a timeout; asserts the stored block's Next with a `not rechecked` mark, and that a stored `Continue the work recorded in` prompt whose registers are all resolved still shows no offer (`hasUnresolvedRows` kept); fails today because no mark exists (A12).
- `…› ages from the marker` (integration): marker `at` four days ago, latest.md mtime now; asserts no offer; then dismiss an offer, touch latest.md's notes without changing `at`, asserts it stays dismissed; fails today because the age is the mtime (A12).
- `…› never runs while hidden or unchanged` (integration): in a plan session, with an active auto run, and after a dismissal, asserts zero stub calls; outside them, two reads with unchanged mtimes of latest.md, completed.md, roadmap.md, the register files, the plans directory and the subject plan give one call, and touching a register file gives a second; a stub that never resolves, followed by a Bash tool event, asserts the tool hook completes and at most one call is in flight; fails today (A13).
- `…› runs from the primary checkout when the session's directory is gone` (integration): the session cwd deleted; asserts the stub's cwd is the primary checkout.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge`
Expected: FAIL on the new resume-offer cases.

- [ ] **Step 3: Implement**

1. `lib.ts`: `markerOf(text): { kind: string; at: number } | null` parsing C4/C6's last marker line.
2. `readResumeOffer`: compute the cache key from the stats listed in the spec §3; when it changes and the offer can show, start (without awaiting it in `readRun`) one `$.process.run(['bash', `${$.plugin.root}/scripts/next-step`, '--print', '--latest'], { cwd, timeoutMs: 20_000 })`, where `cwd` is the session's checkout (`S.where.checkout`) if it still exists, else the primary checkout `readRun` already holds (`S.where.primary`, cached from `place` while the checkout existed). On resolve: exit 0 → `resumeOfferOf(stdout)` with `at` from `markerOf(stdout)` (seconds × 1000); exit 6 → offer null; anything else → today's read of latest.md including the register check, with `isRechecked: false`.
3. The offer's `at` comes from the marker; `offerNow`'s three-day test and `resumeDismissed` use it. `drawResumeBand` appends ` · not rechecked` when `isRechecked` is false.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/tests/cockpit.test.ts
git commit -m "fix(dforge): recompute the cockpit resume offer"
```

### Task 9: Release a held turn only on a real block

**Files:**
- Create: `plugins/dforge/scripts/lib/next-ending.sh`
- Modify: `plugins/dforge/scripts/turn-end.sh` (the `ends_with '## Next session'` tests in the ledger loop)
- Modify: `plugins/dforge/scripts/ui-turn-end.sh` (its `## Next session` substring test)
- Test: `plugins/dforge/tests/turn-end.test.sh`, `plugins/dforge/tests/ui-hooks.test.sh`

**Interfaces:**
- Produces: C8 `ending_released`.

**Items:** 2, 8

**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7
**Implementer:** dforge:impl-opus-high

- [ ] **Step 1: Extend the test `tests/turn-end.test.sh`**

- `tests/turn-end.test.sh::a hand-typed block does not release a ledger turn` (integration): a ledger written this turn, latest.md writable and older than the stamp, last message `Done.\n\n## Next session\n\n**Next:** Resume at Task 2.`; asserts a first stop is held; fails today because the substring passes (A17).
- `tests/turn-end.test.sh::a written block releases a ledger turn` (integration): the same, but latest.md rewritten after the stamp with `**Next:** Resume at Task 2.` and that line in the message; asserts no hold.
- `tests/turn-end.test.sh::an unwritable latest.md accepts the heading` (integration): latest.md `chmod 444` (skipped with a note when running as root, where the hook's own writability test is exercised through a parent directory `chmod 555` instead), message with a line exactly `## Next session`; asserts no hold (A29).
- Rewrite the checks that release a ledger turn with a bare block so that their fixture also writes latest.md after the stamp with the message's `**Next:**` line (named here as the assertions this behaviour change touches): `tests/turn-end.test.sh:78` ("next-step block: passes"), `:82-84` ("no message field, the block far back in the transcript: passes"), `:118`, `:215` ("every launch stopped: next-step block passes"), `:219` ("a stopped agent passes"), `:228` ("its final notification: passes"), `:400`, and any other check whose message is `$NEXT` or a literal `## Next session` block and whose expected result is a pass; list each one rewritten in the commit body.
- `tests/ui-hooks.test.sh::a Next session block stands down` (`tests/ui-hooks.test.sh:170`): rewrite its fixture to write latest.md after the stamp with `**Next:** x` and the message's Next line `**Next:** x`, still expecting `none`; add `tests/ui-hooks.test.sh::a hand-typed Next session block does not stand down`: the same message with latest.md not rewritten, expecting `block`; fails today because the substring test stands down.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 450 bash plugins/dforge/tests/turn-end.test.sh`
Expected: FAIL on "a hand-typed block does not release a ledger turn" and, in `timeout 300 bash plugins/dforge/tests/ui-hooks.test.sh`, on "a hand-typed Next session block does not stand down".

- [ ] **Step 3: Implement**

1. `next-ending.sh` with `ending_released MESSAGE STAMP LATEST` per C8: `[ "$LATEST" -nt "$STAMP" ]` and the `**Next:**` text found with `grep -F`; the writability test walks up from LATEST's directory to the nearest existing parent.
2. In `turn-end.sh`'s ledger loop, both `ends_with '## Next session' …` calls drop `'## Next session'` from the list and add `ending_released "$last" "$stamp" "$(dforge_latest_file "$root")"` as an alternative. The background-work hold keeps its substring test.
3. `ui-turn-end.sh`: replace `grep -qF '## Next session' <<<"$message" && exit 0` with an `ending_released` test; source `lib/roots.sh` and `lib/next-ending.sh` before it (today `roots.sh` is first sourced inside the `if [ -f "$stamp" ]` branch) and take LATEST from `dforge_latest_file "$root"`; without a stamp, skip the test (no turn to compare against) and keep today's stand-down on the substring.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 450 bash plugins/dforge/tests/turn-end.test.sh && timeout 300 bash plugins/dforge/tests/ui-hooks.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/next-ending.sh plugins/dforge/scripts/turn-end.sh plugins/dforge/scripts/ui-turn-end.sh plugins/dforge/tests/turn-end.test.sh plugins/dforge/tests/ui-hooks.test.sh
git commit -m "fix(dforge): release a stop only on a written block"
```

### Task 10: Hold transition turns and survive a removed checkout

**Files:**
- Modify: `plugins/dforge/scripts/turn-end.sh` (root resolution, a transition check before the `[ -d "$sdd" ]` exit)
- Modify: `plugins/dforge/scripts/turn-start.sh` (keep line 1 of `$stamp.refs` when `turn_refs` fails)
- Test: `plugins/dforge/tests/turn-end.test.sh`

**Interfaces:**
- Consumes: C8.

**Items:** 2, 7

**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6
**Implementer:** dforge:impl-opus-high

- [ ] **Step 1: Extend the test `tests/turn-end.test.sh`**

- `…::a finishing turn in a removed worktree is held` (integration): a prompt stamped with cwd `$TMP/wt` (a linked worktree), then the turn commits a completed.md line for plan P on the primary and removes the worktree; the stop's cwd is the removed `$TMP/wt`, message `Merged.`; asserts a hold whose reason contains `next-step" --complete` and P's name; fails today because `git -C <cwd>` fails and the hook exits (A15).
- `…::a turn that closes a milestone is held once` (integration): the turn commits roadmap.md with M1 changed to `closed`; message `M1 closed.`; asserts a hold naming `next-step" --project`, and the retry (`stop_hook_active`) passes (A16).
- `…::a pull that moves the roadmap is not held` (integration): roadmap.md and completed.md changed by `git pull` from a second clone (the commit's time before the stamp, file clean); asserts no hold (A16).
- `…::a design turn that edits the roadmap is not held` (integration): the turn commits roadmap.md adding a milestone row, no milestone newly closed; asserts no hold (A16).
- `…::nothing changed, nothing held` (integration): a turn that changes no ledger, completed.md or roadmap.md and ends `Done.`; asserts no hold (A18); the existing "a dforge turn that committed without a plan: passes" case keeps passing.
- `…::a later turn still finds the primary` (integration): after a turn whose cwd was removed, a second prompt with the same removed cwd keeps line 1 of `$stamp.refs`; asserts it equals the common git directory.
- The existing case "darkmem progress: another worktree's ledger does not block" keeps passing (A19).

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 450 bash plugins/dforge/tests/turn-end.test.sh`
Expected: FAIL on the removed-worktree, milestone and later-turn cases.

- [ ] **Step 3: Implement**

1. turn-start: when `turn_refs` fails and `$stamp.refs` exists, keep its first line (write it alone) instead of deleting the file.
2. turn-end: when `git -C "$cwd" rev-parse --show-toplevel` fails, read line 1 of `$stamp.refs`; the root is the line's parent when it ends in `/.git`, else the first `worktree` of `git --git-dir=<line> worktree list --porcelain`; the hook exits as today only when neither yields an existing directory. Use that root for the `auto-run` lookup as well.
3. Transition check, run before the `[ -d "$sdd" ]` exit and joining the early-exit test: for `C=<docs root>/plans/completed.md` and `M=<docs root>/roadmap.md`, a file counts when `[ "$f" -nt "$stamp" ]`, `! [ "$latest" -nt "$f" ]`, and (documents local) `git status --porcelain -- "$f"` is non-empty or `git log -1 --format=%ct -- "$f"` is at or after the stamp's mtime; for M also more `closed` milestones now than in `git show <turn-start head>:<M>` (the head from `$stamp.refs` for the root's branch; no head → count from zero). With documents in darkmem, the mtime test alone.
4. When it counts and no ledger hold applies, hold once with a reason naming `bash "<plugin root>/scripts/next-step" --complete <plan>` (the backticked name on the completed.md line added since the turn-start head, else its last entry) or `… --project`, and `end with its block verbatim`. It stands down where the ledger hold does: background work, a queued notification, a bound auto run, and the finishing endings; `ending_released` releases it.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 450 bash plugins/dforge/tests/turn-end.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/turn-end.sh plugins/dforge/scripts/turn-start.sh plugins/dforge/tests/turn-end.test.sh
git commit -m "fix(dforge): hold turns that merge or close work"
```

### Task 11: Keep notes in roadmap settle and pin the built-row close

**Files:**
- Modify: `plugins/dforge/scripts/roadmap` (`cmd_settle`'s `register set … --note`)
- Test: `plugins/dforge/tests/roadmap.test.sh`

**Interfaces:**
- Consumes: C7.

**Items:** 10

**Evaluation:** files 1 - spec 2 - coupling 0 - risk 1 = 4
**Implementer:** dforge:impl-sonnet-medium

- [ ] **Step 1: Extend the test `tests/roadmap.test.sh`**

- `tests/roadmap.test.sh::settle keeps an existing note` (integration): an epic row with note `owner ruling: keep`, its spec's registers resolved; after `roadmap settle --spec S` asserts the row is `verify` and its note starts with settle's own text and still contains `owner ruling: keep`; fails today because `register set --note` replaces the cell (A31).
- `tests/roadmap.test.sh::a milestone of built rows closes after sign-off` (integration): a darkpanel-shaped fixture (milestone M5 register with rows 1-3 `doing` and row 4 `open`, all assigned to spec S, S's plans all indexed, S's requirement registers resolved); asserts `next-step --print --project` names M5's audit with `Built, awaiting the audit: #1, #2, #3, #4.`; then sets rows 1-4 `done` as closing-a-milestone step 7 will, and asserts `roadmap close M5 --note x` exits 0 and `roadmap status` reads M5 `closed` (A30).

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/roadmap.test.sh`
Expected: FAIL on "settle keeps an existing note".

- [ ] **Step 3: Implement**

`cmd_settle`: read the row's current note (`register_rows` field 6); when it is neither empty nor `-`, pass `--note "<settle's text>; <existing note>"`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/roadmap.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/roadmap plugins/dforge/tests/roadmap.test.sh
git commit -m "fix(dforge): keep row notes in roadmap settle"
```

### Task 12: End milestone and finishing flows on a computed block

**Files:**
- Modify: `plugins/dforge/skills/closing-a-milestone/SKILL.md` (steps 2, 6, 7, 9)
- Modify: `plugins/dforge/skills/finishing-a-development-branch/SKILL.md` (the `roadmap settle --spec` paragraph of Step 5b)
- Modify: `plugins/dforge/skills/handoff/SKILL.md` (step 4)

**Interfaces:**
- Consumes: C5 `--project`, C7.

**Items:** 2, 6, 10

**Evaluation:** files 1 - spec 2 - coupling 1 - risk 1 = 5
**Implementer:** dforge:impl-sonnet-high

- [ ] **Step 1: No new test, because these are skill sentences no script reads; `tests/skill-size.test.sh` and the wording pins under `tests/*skill*.test.sh` keep passing**

- [ ] **Step 2: Find any assertion pinning the sentences changed**

Run: `rg -n "nothing else open|name the next milestone|settle --spec|next-step --adhoc" plugins/dforge/tests`
Expected: the list of tests to keep passing; an assertion pinning a sentence this task changes is rewritten to the new sentence and named in the commit body.

- [ ] **Step 3: Implement**

1. closing-a-milestone step 2: run `scripts/next-step --print --project`; when its Next line names this milestone's audit (`Milestone M<n> (` … `audit and close it`), continue with the `verify` and the `Built, awaiting the audit:` rows; otherwise report the rows, run `scripts/next-step --project`, and end the message with its block verbatim.
2. Step 6, any GAP: after writing the rows back, run `scripts/next-step --project` and end on its block. UNVERIFIABLE stays a question.
3. Step 7: set the built rows to `done` together with the `verify` rows.
4. Step 9: run `scripts/next-step --project` and end the message with its block verbatim.
5. finishing Step 5b: run `scripts/roadmap settle --spec` for the plan's Spec and, when its header has one, its Program spec.
6. handoff step 4: add the between-plans form `scripts/next-step --project --keep-notes`, preferred over `--adhoc` on a roadmap or register project.

- [ ] **Step 4: Run the checks**

Run: `timeout 300 bash plugins/dforge/tests/skill-size.test.sh && timeout 60 node scripts/validate-repository.mjs && timeout 60 /root/.local/bin/claude plugin validate plugins/dforge`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/closing-a-milestone/SKILL.md plugins/dforge/skills/finishing-a-development-branch/SKILL.md plugins/dforge/skills/handoff/SKILL.md
git commit -m "docs(dforge): end milestone flows on next-step"
```

### Task 13: Point readers and Codex at the computed block

**Files:**
- Modify: `plugins/dforge/skills/resume-execution/SKILL.md` (step 5)
- Modify: `plugins/dforge/skills/project-status/SKILL.md` (the "never calls `scripts/next-step`" sentence and rules 6-7)
- Modify: `plugins/dforge/skills/using-dforge/SKILL.md` (the Codex line) and `plugins/dforge/skills/using-dforge/references/codex-tools.md`

**Interfaces:**
- Consumes: C5 `--print`, `--project`.

**Items:** 9, 12

**Evaluation:** files 1 - spec 2 - coupling 1 - risk 1 = 5
**Implementer:** dforge:impl-sonnet-high

- [ ] **Step 1: No new test, because these are skill sentences no script reads; the wording pins under `tests/` keep passing**

- [ ] **Step 2: Find any assertion pinning the sentences changed**

Run: `rg -n "never calls|Next:\*\* line says|every early stop|Route by the .Assigned" plugins/dforge/tests`
Expected: the list of tests to keep passing; a pinned sentence this task changes is rewritten and named in the commit body.

- [ ] **Step 3: Implement**

1. resume-execution step 5: continue with the Next line of `scripts/next-step --print PLAN_FILE`, not latest.md's.
2. project-status: it calls `scripts/next-step` only with `--print` (still writing nothing); rules 6 and 7 become one rule: run `scripts/next-step --print --project` (with `--host codex` on Codex) and recommend what its Next line names. Open items still list every register.
3. using-dforge's Codex line and codex-tools.md: run `scripts/next-step` at every step a skill says to end on its block, not only on early stops.

- [ ] **Step 4: Run the checks**

Run: `timeout 300 bash plugins/dforge/tests/skill-size.test.sh && timeout 60 node scripts/validate-repository.mjs && timeout 60 /root/.local/bin/claude plugin validate plugins/dforge`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/skills/resume-execution/SKILL.md plugins/dforge/skills/project-status/SKILL.md plugins/dforge/skills/using-dforge/SKILL.md plugins/dforge/skills/using-dforge/references/codex-tools.md
git commit -m "docs(dforge): read the next step from next-step"
```

### Task 14: File project checkpoints in darkmem

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-mirror.mjs` (`checkpointTarget`)
- Modify: `plugins/dforge/scripts/lib/darkmem-push.mjs` (the checkpoint send's workstream)
- Test: `plugins/dforge/tests/darkmem-sync/push.test.mjs`, `plugins/dforge/tests/darkmem-sync/pull.test.mjs`

**Interfaces:**
- Consumes: C4.

**Items:** 11

**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7
**Implementer:** dforge:impl-opus-high

- [ ] **Step 1: Write the failing test**

- `tests/darkmem-sync/push.test.mjs::a complete latest.md is pushed under the project workstream` (integration): with the stub server, a mirror whose latest.md is what `next-step --complete` writes (no `## State`, marker `kind=complete subject=docs/dforge/plans/P.md`); asserts the push reports no `names no plan or draft` failure and the stub received one checkpoint under workstream `project`; fails today (A22).
- `…::a project latest.md with stale notes is filed by its marker` (integration): latest.md with a `## State` naming plan Q and a `kind=project` marker; asserts the checkpoint goes to `project`, not `Q`; fails today.
- `tests/darkmem-sync/pull.test.mjs::a second mirror receives the project checkpoint` (integration): after the first push, a second mirror's pull writes latest.md holding the same `## Next session` block; fails today (A22).
- The existing `darkmem-progress-move` cases keep passing unchanged.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/push.test.mjs plugins/dforge/tests/darkmem-sync/pull.test.mjs`
Expected: FAIL on the three new cases. If the first passes unchanged, record `Task 14: Ruling: row 11 not reproduced — none` and close row 11 as not reproduced instead of Step 3.

- [ ] **Step 3: Implement**

1. `checkpointTarget(text, { marker = false } = {})`: with `marker`, a C4 marker of `kind=complete` or `kind=project` returns `{ slug: 'project', path: null }` ahead of any `## State`; other kinds and no marker keep today's `## State` rule. `darkmem-progress-move.mjs` keeps calling it without the option.
2. The push's checkpoint send passes `{ marker: true }`. The `project` workstream is created the way any new workstream is today: `client.resume(cfg.project, 'project')` finding none makes the push open it (as it does for a plan's first checkpoint; check `darkmem-push.mjs` around `const existing = await client.resume`), and `closeFinished` never closes it, since it names no plan. `darkmem-pull.mjs` stays unchanged: it already pulls every open workstream's checkpoint; if the pull test shows otherwise, the fix belongs in this task and the file joins its commit.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 node --test plugins/dforge/tests/darkmem-sync/*.test.mjs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-mirror.mjs plugins/dforge/scripts/lib/darkmem-push.mjs plugins/dforge/tests/darkmem-sync/push.test.mjs plugins/dforge/tests/darkmem-sync/pull.test.mjs
git commit -m "fix(dforge): file project checkpoints in darkmem"
```
