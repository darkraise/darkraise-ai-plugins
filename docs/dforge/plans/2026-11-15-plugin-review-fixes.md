# Plugin Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix every confirmed finding of the 2026-11-15 dforge plugin review (register rows 1-63): the QA cleanup data-loss path, the readers that drifted from the core scripts, and the session facts scripts infer that the cockpit already knows.

**Architecture:** The cockpit writes a per-session state file (window, model, launches) that a new `scripts/lib/session-state.sh` reads with a fallback to today's transcript scan; one service list in `config/services.json` serves both the cockpit and `lib/in-flight.sh`. The other fixes are local changes to the scripts, references, agents and cockpit modules each row names, each pinned by a test in the suite that already covers the file.

**Tech Stack:** Bash scripts and bash test suites, jq, Node (`.mjs`) config and darkmem sync with node:test suites, the TypeScript cockpit mod (`hooks/cockpit/*.ts(x)`) with `tests/cockpit.test.ts`, Markdown skills and references.

**Spec:** `docs/dforge/specs/2026-11-15-plugin-review-fixes-design.md`

**Execution:** inline — `claude --model opus --effort high` — Tasks 14 and 16 total 8 at risk 3

**Parallelism:** sequential — inline execution

**Task check:** `timeout 1500 node scripts/test-all.mjs --jobs 6 && timeout 240 /root/.local/bin/claude plugin test plugins/dforge && timeout 60 node scripts/validate-repository.mjs && timeout 60 /root/.local/bin/claude plugin validate . && timeout 60 /root/.local/bin/claude plugin validate plugins/dforge` — the full suite last passed in 296 s

**Integration check:** `timeout 1500 node scripts/test-all.mjs --jobs 6 && timeout 240 /root/.local/bin/claude plugin test plugins/dforge && timeout 60 node scripts/validate-repository.mjs && timeout 60 /root/.local/bin/claude plugin validate . && timeout 60 /root/.local/bin/claude plugin validate plugins/dforge`

**CI:** `.github/workflows/validate.yml` — platforms: uutils (ubuntu-latest), Windows Git Bash — local: `node scripts/test-all.mjs`; `node scripts/validate-repository.mjs`; `claude plugin validate plugins/dforge`; `claude plugin test plugins/dforge` — uncovered: uutils (ubuntu-latest), Windows Git Bash

**Plan review:** 2026-11-15 — dforge:judge-opus — executability 14 / coherence 17 / coverage 17 / assumptions 15 (round 2)

## Global Constraints

- Paths are repository-relative; `plugins/dforge/` is the plugin root. The work edits the unreleased source under `plugins/dforge`; the session itself runs the installed 4.17.1 from the plugin cache.
- No version bump and no release. Do not touch `docs/dforge/registers/2026-11-15-residual-fixes.md`, and do not edit historical plans or specs.
- English only. Commits are `<type>(<scope>): <subject>`, subject at most 50 characters, imperative, no period, author and committer `Darkraise <quangtc94@gmail.com>`, with no AI attribution of any kind (no `Co-Authored-By:`, `Claude-Session:` or "Generated with" text).
- Never push: the branch merges into `main` locally at the end (spec `Finish: merge`).
- Every command that runs a test, a build or a CLI carries an explicit `timeout`; every process a task starts is stopped before the task closes.
- A new `plugins/dforge/tests/*.test.sh` suite needs a weight in `windowsSeconds` in `scripts/test-shards.mjs` (at most 80% of its limit, 600 s by default); `scripts/test-all.mjs` finds it by name.
- A rewritten assertion is allowed only where it pins behaviour a register row changes, and the task for that row names it (spec ruling R8, which replaces A55's list).
- Windows Git Bash: a native program (`git.exe`, `jq.exe`) given a path built from `$PWD`, `$(pwd)` or `$TMPDIR` gets a POSIX form it cannot open, or has its argument rewritten when path conversion is on (`MSYS_NO_PATHCONV` unset). Convert the path with `cygpath -m` before the call (dforge's `dr_native_path`, `plugins/dforge/scripts/lib/native-path.sh`), and feed `jq` a file on stdin in a script that exports `MSYS_NO_PATHCONV`.
- Windows Git Bash: the same directory is `/c/Users/x` in the shell and `C:/Users/x` from a native tool, so a string comparison never matches. Normalise both sides with `cygpath -m`, or compare with `-ef`.
- Windows Git Bash: files a Windows tool wrote, and native program output, end lines with `\r`, which `read`, `awk` and `[ = ]` keep. Pipe through `tr -d '\r'` before comparing or parsing.
- Windows Git Bash: `awk -v name=value` processes backslash escapes in the value, so a regex or a Windows path changes. Pass the value in the environment and read `ENVIRON["NAME"]`.
- Windows Git Bash: Node's `import()` of an absolute `D:/x/y.mjs` reads `d:` as a URL scheme and fails. Import with `import(pathToFileURL(path).href)`.
- uutils (ubuntu-latest): a lock built on `mkdir` failing when the directory exists does not exclude a second process. Create the lock file with `set -C` (noclobber), or use `flock`.
- uutils (ubuntu-latest): `timeout` signals only the command it started, so the command's children keep running. Run the command in its own process group (`setsid`) and signal the group.
- CI awk is gawk and local awk is mawk: write portable awk, and never build a dynamic regex inside a per-line loop.

## Contracts

- **C1 session state file** (Task 1 writes; Tasks 2, 3, 8 read). `~/.claude/dforge/sessions/state/<sid>.json`, where `~` is the cockpit's home as for `sessions/cockpit/<id>` and `<sid>` is the session id with every character outside `A-Za-z0-9` replaced by `-` (the turn stamp's name, `scripts/turn-start.sh`). Written with one `$.fs.write` of the final path (a mod has no rename; a reader that meets a half-written file sees `unparseable` and falls back, C2) at session start, at every `prompt.submit` (after the turn stamp exists), at every main-loop `turn.complete`, whenever a launch starts or ends, and when the model changes:
  `{"session": "<id>", "updated": <epoch ms>, "window": <tokens or null>, "model": "<id or null>", "partial": <bool>, "launches": [{"id": "<task id>", "kind": "shell|agent|monitor", "what": "<description or command, 80 chars>", "command": "<first line of the command, or empty>", "startedAt": <epoch ms>, "outputFile": "<path or empty>", "service": <bool>, "timer": <bool>}]}`.
  `partial` is true when the session started a launch form the cockpit does not track (a Monitor, a resumed agent, an agent that reported with work of its own still running); `launches` lists only launches still running.
- **C2 `scripts/lib/session-state.sh`** (Task 2). Sourced; functions only; needs jq.
  `ss_file SID` prints the C1 path. `ss_window SID` prints the window and exits 0 when the file parses, `.session` equals SID and `.window` is a positive integer; `ss_model SID` likewise for `.model`. `ss_launches SID` prints C3 lines for `.launches` and exits 0 only when, in addition, `.partial` is false and `.updated` is not older than the turn stamp's modification time (no turn stamp: stale). Each returns 1 otherwise, after appending one line `<turn stamp epoch>\t<sid>\t<reader>\t<reason>` to `<state>/session-state.log` (`<state>` = `scripts/dforge-path state` in the working directory's checkout), where `<reader>` is `window`, `model` or `launches` and `<reason>` is `missing`, `unparseable`, `session mismatch`, `stale` or `partial`; a line already in the log is not appended again. `ss_prune` deletes state files older than 30 days.
- **C3 in-flight line** (Task 3; read by Tasks 5, 7, 12). `inflight_scan` and `inflight_list` print six tab-separated fields: `<agent|shell|monitor> <task id> <started HH:MM> <idle Nm|idle -> <what> <work|service|timer>`. `inflight_list TRANSCRIPT SINCE SID` prints `ss_launches SID` when it succeeds, else `inflight_scan TRANSCRIPT SINCE` (same exit contract); `inflight_source SID` prints `session file` or `transcript`, the choice `inflight_list` makes, without logging. `inflight_text` keeps printing the first five fields and appends ` (service)` or ` (timer)` for those roles.
- **C4 `plugins/dforge/config/services.json`** (Task 3; read by Task 4). `{"services": ["<pattern>", ...], "timer": "<pattern>"}`. Each pattern is valid in both JavaScript `RegExp` and jq (Oniguruma); the shell side evaluates them with jq, never `grep -E`. A command is a service when some part of its first line matches a services pattern, the parts being the line split on `&&`, `||` and `;`, each trimmed, with leading `NAME=value ` assignments removed (today's `isServiceCommand`). A command is a timer when its trimmed first line matches `timer`: `^sleep\s+[0-9]+(\.[0-9]+)?[smhd]?$`. `plugins/dforge/tests/fixtures/service-commands.json` is `[{"command": "<text>", "role": "service|timer|work"}, ...]`, asserted through both implementations. A mod and its tests load only code files, so `plugins/dforge/config/services.mjs` and `plugins/dforge/tests/fixtures/service-commands.mjs` default-export the same values as their JSON files (Task 4). Each is generated from its JSON file by the command `tests/repository-layout.test.mjs` prints, and that test asserts the two are equal. Edit the JSON, never the mirror.
- **C5 `plan_final_review_state LEDGER [DIR]`** (Task 6, `scripts/lib/plan.sh`; read by Task 7). Runs git in DIR (default the working directory) and reads the ledger's last `Final review: clean (commits <base>..<head>)` line and prints one of: `none` (no such line), `current` (HEAD equals `<head>`; or every commit in `<head>..HEAD` touches only paths under the docs root; or `<head>` is an ancestor of HEAD but not on HEAD's first-parent chain, `git rev-list --first-parent HEAD`, which is a base branch that merged the plan's branch), `stale <head>` (`<head>` is on HEAD's first-parent chain and a commit after it touches a path outside the docs root), `rewritten <head>` (`<head>` is not an ancestor of HEAD, or is not a commit). A path is under the docs root when `<toplevel>/<path>` lies inside `dforge_docs_root DIR`; when `dforge_docs_store DIR` is not `local` (darkmem documents), no committed path is. A clean line without a `(commits …)` clause prints `current`. The ledger records no branch, so the first-parent test is the only base-branch rule.
- **C6 fast-mode grammar** (Task 9; read by Tasks 10, 11). `Process: fast — <why>` is request-scoped: on only while it sits after the current turn stamp. `Process: fast (session) — <why>` is session-scoped: on until a later `Process:` line names another path. `fast_mode_on TRANSCRIPT [LAST_MESSAGE]` (status 0 = on) reads the last message first, then the main transcript backwards in chunks; it skips an expired plain `fast` line and stops at the first `fast (session)` line (on) or non-fast `Process:` line (off). With no turn stamp, plain `fast` counts as on. The session id is the transcript's basename without `.jsonl`; the verdict for the part before the stamp is cached in `<turn stamp>.fast` (`on` or `off`), so the backwards scan runs at most once per turn. `plugins/dforge/tests/fixtures/fast-mode/cases.json` is `[{"name": "<case>", "before": [<assistant texts>], "after": [<assistant texts>] or null, "on": <bool>}]`, `before` and `after` sitting on either side of the turn stamp (a person's prompt in the cockpit) and `after: null` meaning no stamp,, asserted through `fast_mode_on` and the cockpit's parser.
- **C7 amendments location** (Task 14; read by Tasks 15-17). `plan_amendments_file PLAN` prints `<dforge_ledger_dir <slug>>/amendments.md` only when that file is non-empty, and nothing otherwise: readers take no output as no amendments, and it never creates the file or its directory. A writer (`plan-amend`) computes the same path itself from `dforge_ledger_dir <slug>`. `plan_amendments_ready PLAN`, run in the caller's own shell (never inside `$(…)`), first moves a `<dforge_workspace <slug>>/amendments.md` to the ledger directory when the ledger-directory file is missing, appending `Ruling: amendments moved beside the ledger — none` to the ledger when the ledger exists; then exits 2 with `<script>: the ledger cites amendment A<k>, which <amendments path> lacks` when a ledger line contains `Ruling: amendment A<k>` and the file has no `## A<k> ` heading.
- **C8 `scripts/qa-files`** (Task 13). `qa-files begin WORKSPACE` writes `WORKSPACE/qa-status-before.txt` from `git status --porcelain=v1 -z --untracked-files=all` and truncates `WORKSPACE/qa-touched.txt`. `qa-files clean WORKSPACE` restores (tracked, `git restore --staged --worktree --`) or deletes (untracked file; a directory only once empty) each path that is listed in `qa-touched.txt` and new relative to the snapshot, never a path `scripts/auto-run carried` prints, and prints `qa-files: removed <path>` per file it restored or deleted (a directory removed once empty prints no line) and `qa-files: left <path>` per other new dirty path, a carried one included. Exit 0; 2 usage or a missing snapshot. No manifest: nothing is cleaned and every new path is printed as left.
- **C9 `next-step --kept PLAN_FILE`** (Task 19). Prints a `## Next session` block whose Status names the plan and says its branch is kept unintegrated, and whose Next names the branch, the worktree and the finish choices still open, ending `run dforge:finishing-a-development-branch when you choose merge, pr or discard.`; prints no "is complete", launches nothing, reads no register or roadmap. `--complete`, `--kept` and `--adhoc` delete `.dforge/sdd/finish.json` (the no-plan finish record) after writing the block.
- **C10 `scripts/with-timeout SECONDS CMD...`** (Task 23). Runs CMD under `dforge_timeout`'s command with `-k 10`, exiting with its status (124 on the bound); exits 125 with `with-timeout: no timeout command (timeout or gtimeout) on PATH` when there is none; 2 on usage.
- **C11 QA reply contract** (Task 26). Acceptance QA's reply ends with `Report: <absolute path>`; `impl-stop-gate` blocks a stop whose reply has that line when the file is missing or its first non-empty line is not `## Verdict`; a reply with no `Report:` line passes.
- **C12 `dforge-config workflow [--host claude|codex]`** (Task 27). With `--host codex` the `autoRun=on` exclusion of `inertWhen` is not applied.
- **C13 cockpit ledger states** (Task 29; read by Task 30). `parseLedger` task states gain `waiting` (with `question: string`, the text after `waiting — `) and `deferred` (a `complete (deferred by the auto run)` line). `isClean` is read only inside the parenthesised clause before ` — `.
- **C14 saved defaults** (Task 32; liveness from C16). `~/.claude/dforge/sessions/saved-defaults/<sid>.json`, with `~` and `<sid>` as for the heartbeat `sessions/cockpit/<sid>`: `{"session": "<id>", "launchModel": "<model the switch sets>", "saved": {"model": ..., "modelSettings": ..., "effortLevel": ...}}`, a missing key stored as `null`, in that key order. Written with `$.fs.write` before `/model`, never over an existing file. Deleted only by `node scripts/lib/dforge-config.mjs drop-snapshot <sid>` (exit 0, a missing file included; 2 on usage), since a mod cannot delete a file.
- **C15 settings problem line** (Task 34). `dforge: <config path> is not a JSON object; every setting reads its default and notifyOn reads none until it parses` — printed by `dforge-config workflow` in place of the settings line, and shown by the cockpit.
- **C16 cockpit liveness** (Task 30; read by Task 32). `isSessionAlive($, sid)` in `register.tsx` is true when `<home>/.claude/dforge/sessions/cockpit/<sid with every character outside A-Za-z0-9 replaced by ->` holds epoch seconds no more than 180 before `$.clock.now()` (`AR_BEAT_SECONDS`, `scripts/lib/auto-run.sh:17`). This is the heartbeat `beat` writes each watchdog minute, and `<home>` is `HOME`, else `USERPROFILE`. A beat up to 180 s ahead reads as now. A missing, unreadable or non-numeric file, or a beat further ahead, is not alive. It starts no process.

## Assumptions (evidence)

- The cockpit already writes `~/.claude/dforge/sessions/cockpit/<id>` (`plugins/dforge/hooks/cockpit/register.tsx:3003`) under the `sessions/` directory the turn stamps use (`plugins/dforge/scripts/turn-start.sh:16-19`), and holds the engine's window as `figures.context.window` (`register.tsx:3544`). Whether its write lands before a Stop hook reads the file in the same turn is unverified — Task 1 verifies it; C2's staleness rule falls back to the transcript scan when it does not.
- `isServiceCommand` splits a command's first line on `&&`, `||` and `;` and strips leading assignments before matching `SERVICES` (`plugins/dforge/hooks/cockpit/lib.ts:1218-1236`); three of its patterns use lookahead, which jq's Oniguruma supports and `grep -E` does not.
- No script parses the budget line's `source:` field (rg over `plugins/dforge/scripts` and `hooks`, 2026-11-15), so Task 8 may extend it.
- New `*.test.sh` suites are found by `scripts/test-all.mjs` (`readdirSync` of `plugins/dforge/tests`) and need a `windowsSeconds` weight in `scripts/test-shards.mjs`, which `tests/test-shards.test.mjs` enforces.
- The model table keeps session-budget.md's entries (`plugins/dforge/reference/session-budget.md:20`): 1,000,000 for Fable 5.1, Opus 5.5 and Sonnet 5.5, 200,000 for Haiku 4.5. Any other model id, Fable 5.2 included, takes its window from the session state file or reads `unknown`.
- R5 choice: the cockpit tracks shells and agents it starts and marks the file `partial` for any other launch form, so the transcript scan stays the authority there; this avoids teaching the cockpit three transcript-only forms.
- `scripts/auto-run` takes its session from `CLAUDE_CODE_SESSION_ID`, or `--session ID`, and overwrites any inherited `AR_SESSION` (`plugins/dforge/scripts/auto-run:38-44`), so Task 13's carried case names the session through `CLAUDE_CODE_SESSION_ID`.
- Today's `fast_mode_on` reads the whole transcript in one forward `jq -rR` pass (`plugins/dforge/scripts/lib/fast-mode.sh:13-15`); Task 9's R9 case therefore measures the bytes `jq` reads, not the time taken.
- Node sits in a PATH directory of its own on both CI platforms (`actions/setup-node@v5`, `.github/workflows/validate.yml:57-59` and `:129-131`) and locally (`/root/.nvm/versions/node/v24.18.0/bin/node`, `command -v node`, 2026-11-15), so Task 21's no-node cases drop that directory from PATH instead of linking tools into a bare one; where node shares a directory with git or jq they print `skip`. A temporary `PATH=…` prefix reaches `command -v` inside a bash function (checked 2026-11-15).
- Task 23's fake PATH holds scripts that exec each tool by absolute path, never links: Git Bash's `ln -s` copies by default, and a copied `.exe` loses its DLL directory; uutils' multicall binary picks its tool from the name it runs under. `agy-locate` reaches its `--version` call once an `agy` is on PATH (`plugins/dforge/scripts/agy-locate:26-30`).
- On CI's uutils `timeout`, `_darkmem_bounded` uses the watchdog, which returns 143 or 137 on an overrun rather than 124 (`plugins/dforge/scripts/lib/darkmem-hook.sh:23-50`); Task 21 accepts all three.
- `run-review-panel` takes its bound from `PANEL_BOUND_SECONDS` and its runners from `PANEL_<ID>_RUNNER` (`plugins/dforge/scripts/run-review-panel:19-21`, `:68-77`); Git Bash has no `pgrep`, so Task 24's tree case skips there (`plugins/dforge/tests/review-panel.test.sh:13-14`).
- The ledger records no branch (`plugins/dforge/scripts/task-step:581`), so C5 tells a base branch from the plan's branch by `git rev-list --first-parent HEAD` alone.
- `stores.json` maps each primary checkout to `{documents, progress, project, mirror}` (`plugins/dforge/scripts/lib/darkmem-config.mjs:77-121`), which Task 21 reads with jq.
- A Claude Code mod, and every file it or its tests import, loads only code files (`.ts`, `.tsx`, `.jsx`, `.js`, `.mjs`, `.cjs`, `.mts`, `.cts`) and imports only relative files and `claude-code`: there is no Node (`plugins/dforge/.claude-plugin/types/claude-code/index.d.ts:22-28`, engine-written for 2.1.325 and git-ignored; `plugins/dforge/config/schema.mjs:2-3`). A `claude plugin test` probe on 2026-11-15 confirmed it: a `.json` import fails ("is not named like code and was not loaded"), `node:fs` fails ("imports its own files by relative path and "claude-code", nothing else"), and a test's `./fixtures/x.mjs` import loads. So Tasks 4 and 10 read JSON through generated `.mjs` mirrors, which `tests/repository-layout.test.mjs` checks.
- A mod has no process id and no signal API (`rg -n '\bpid\b'` over that `index.d.ts` finds nothing, 2026-11-15). Its `$.fs` offers only `read`, `write`, `list`, `exists`, `stat` and `ancestors` (`index.d.ts:7644-7678`), so it cannot rename or delete. Liveness therefore comes from the cockpit heartbeat (C16), the rule `ar_is_stale` applies (`plugins/dforge/scripts/lib/auto-run.sh:17`, `:128-157`), and deletion goes through `dforge-config.mjs drop-snapshot`.
- The function-hook `tool.check` event carries no permission mode (`ToolCheckInput`, `index.d.ts:14794-14847`). Classic hook inputs do (`BaseHookInput.permission_mode`, `:881`): a 2026-11-15 probe showed `$.classic.UserPromptSubmit({ prompt, permission_mode: 'auto' })` delivers `'auto'` to `on('classic.UserPromptSubmit')`, so Task 31 reads the session's mode from classic events.
- `cockpit.test.ts` harness rules, from 2026-11-15 probes:
  - A test registers each event once: a second `on('fs.list')` beside `world`'s fails to load with "registered twice". A matcher-qualified registration (`{ path }`, or `{ argv: /re/ }`, since `process.run`'s argv is matched as a string) loads beside it and nests outside it ("first outermost", `index.d.ts:7296-7297`).
  - A test hook that throws is skipped and the hooks beneath answer, so a seam that must fail a read answers `{ deny }`.
  - A test's own `on('classic.<Event>')` is the bottom of that classic chain (`index.d.ts:17297-17299`).

## Task index

1. Cockpit writes the session state file
2. Session state reader
3. Shared service list and launch roles in in-flight.sh
4. Cockpit reads the shared service list
5. in-flight and next-step over services
6. Final review state helper and next-step routing
7. turn-end.sh holds over services and stale clean lines
8. Context window from the session state file
9. Request- and session-scoped fast mode in the hooks
10. Cockpit fast mode, budget nudge and relaxed final phase
11. Compaction snapshot trust and truncation
12. ui-turn-end.sh stand-downs and transcript fallback
13. QA file manifest
14. Amendments beside the ledger
15. Amendment consumers refuse missing entries
16. Amendments in the darkmem sync
17. Review record and ci-mirror amendments
18. Plan identity and Codex task opening
19. Finishing records and the Keep as-is route
20. Auto-run hygiene
21. Session start: missing Node and sync bound
22. Suite baselines, suite-run HEAD and task-step cwd
23. with-timeout and bounded agy version
24. Review panel process trees
25. UI-proof screenshot evidence
26. Judge tools, QA persona and stop gate
27. Codex workflow line and native-codex.md
28. Stale procedure text and fast-mode prose
29. Cockpit ledger states and question notifications
30. Cockpit Run binding, resume offer and stale run
31. Cockpit guards
32. Cockpit session lifecycle and model snapshot
33. Cockpit glyphs, problem count and saved-state honesty
34. Broken settings file
35. One settings resolver and locked Claude writes
36. Inert rows, consent press and desktop steppers

---

### Task 1: Cockpit writes the session state file

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Modify: `plugins/dforge/hooks/cockpit/lib.ts`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: none.
- Produces: C1.

**Items:** 40, 28, 12
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Append to `plugins/dforge/tests/cockpit.test.ts`:

```ts
describe('session state file', () => {
  const STATE_FILE = '/home/me/.claude/dforge/sessions/state/sess-1.json'
  const stateOf = (written: Record<string, string>) => JSON.parse(written[STATE_FILE] ?? 'null')
  const bg = (id: string) => ({ Bash: () => ({ result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: id }, text: 'Running in the background' }) })

  test('is written at session start, prompt submit and turn end with the window', async ($, on) => {
    const written: Record<string, string> = {}
    const clock = world(on, { ...SIGNED_IN, written, window: 650_000 })
    signedIn(on, {})
    await $.session.start(START)
    const first = stateOf(written)
    expect(first).toMatchObject({ session: 'sess-1', window: 650_000, partial: false, launches: [] })
    expect(typeof first.model).toBe('string')
    await clock.advance(5_000)
    await $.prompt.submit({ text: 'go on', wait: false } as never)
    const submitted = stateOf(written).updated
    expect(submitted).toBeGreaterThan(first.updated)
    await clock.advance(5_000)
    await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    expect(stateOf(written).updated).toBeGreaterThan(submitted)
  })

  test('lists running launches with their roles and drops an ended one', async ($, on) => {
    const written: Record<string, string> = {}
    const w: World = { ...SIGNED_IN, written, tools: bg('b7k2') }
    world(on, w)
    signedIn(on, {})
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'npm run dev', description: 'Dev server', run_in_background: true } as never)
    w.tools = bg('t1')
    await $.tool.call({ tool: 'Bash', command: 'sleep 1200', run_in_background: true } as never)
    const launches = stateOf(written).launches
    expect(launches.map((l: Record<string, unknown>) => [l.id, l.kind, l.command, l.service, l.timer])).toEqual([
      ['b7k2', 'shell', 'npm run dev', true, false],
      ['t1', 'shell', 'sleep 1200', false, true],
    ])
    expect(launches[0].what).toBe('Dev server')
    await $.session.append({ message: { type: 'user', role: 'user', content: [{ type: 'text', text: '<task-notification>\n<task-id>b7k2</task-id>\n<status>completed</status>\n</task-notification>' }] }, door: 'queue', origin: { kind: 'task-notification' }, uuid: 'n1' } as never)
    expect(stateOf(written).launches.map((l: Record<string, unknown>) => l.id)).toEqual(['t1'])
  })

  test('marks the launches partial once a Monitor starts', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { ...SIGNED_IN, written })
    signedIn(on, {})
    await $.session.start(START)
    await $.tool.call({ tool: 'Monitor', command: 'tail -f x.log' } as never)
    expect(stateOf(written).partial).toBe(true)
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge`
Expected: FAIL in `session state file` (no state file is written).

- [ ] **Step 3: Implement**

1. In `register.tsx`, add `writeSessionState($)`, beside `beat($)` (`$.fs.write` of `sessions/cockpit/<id>`, about `:2997-3003`): it builds C1 from the session id (sanitised as `beat` does), `Date`/clock milliseconds, the window `figures.context.window` from the last `$.session.usage()` reading (null when unknown), the engine or session model, the main-loop `shells` atom entries and the undone background `spawns`, and writes it with one `$.fs.write` of the final path (`$.fs` offers no rename). A write failure is swallowed.
2. Call it at the end of the `session.start` handler, in `prompt.submit` (`:606`), in the main-loop branch of `turn.complete` (`:674`), after `trackShells` changes the `shells` atom (`:4126`), after `endShells` (`:4116`), after a spawn is added (`:522`) or marked done (`:733-756`), and when `turn.step` (`:663`) changes the engine model.
3. A shell entry is `{id, kind: 'shell', what: description || command first line (80 chars), command: first line, startedAt, outputFile: '', service: isServiceCommand(command), timer: isTimerCommand(command)}`; an agent entry has `kind: 'agent'`, `what` its description, `command: ''`, `service: false`, `timer: false`.
4. In `lib.ts`, export `isTimerCommand(command)`: true when the trimmed first line matches `^sleep\s+[0-9]+(\.[0-9]+)?[smhd]?$` (C4's timer pattern).
5. Keep a module flag set by a `Monitor` or `SendMessage` `tool.call`, or a task-notification row containing `background work of its own still running`; it makes `partial` true for the rest of the session and resets on a session-id change.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge`
Expected: PASS.

- [ ] **Step 5: Verify the riskiest assumption**

In tmux, with a scratch `HOME` and `CLAUDE_CONFIG_DIR` under the scratchpad (the session memory note on nested smoke runs), start `/root/.local/bin/claude --plugin-dir plugins/dforge` with a temporary Stop hook in the scratch settings that runs `printf '%s %s\n' "$(jq -r .updated "$HOME/.claude/dforge/sessions/state/<sid>.json")" "$(stat -c %Y "$HOME/.claude/dforge/sessions/turns/<sid>")" >> <scratchpad>/probe.log`. Submit one prompt that starts `sleep 30` in the background and ends the turn. Expected: one log line whose first number is at least the second times 1000, and the state file lists the sleep with `timer: true`. Append `Ruling: the session state file reached the Stop hook in the same turn — <yes|no, with the two numbers> — none` to the ledger; a `no` changes no later task, since C2 falls back to the transcript scan. Kill the tmux session and confirm no `claude` process from it remains.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(dforge): write a per-session state file"
```

### Task 2: Session state reader

**Files:**
- Create: `plugins/dforge/scripts/lib/session-state.sh`
- Modify: `plugins/dforge/scripts/session-start.sh`
- Modify: `scripts/test-shards.mjs`
- Test: `plugins/dforge/tests/session-state.test.sh`

**Interfaces:**
- Consumes: C1.
- Produces: C2.

**Items:** 40, 28
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/session-state.test.sh`:

```bash
#!/usr/bin/env bash
# lib/session-state.sh: the cockpit's per-session state file, read with its
# validity rules, each rejection logged once per turn.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
export HOME="$TMP/home" MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR
git init -q "$TMP/repo" && cd "$TMP/repo" || exit 1
. "$HERE/../scripts/lib/in-flight.sh"
. "$HERE/../scripts/lib/session-state.sh"
SD="$HOME/.claude/dforge/sessions/state" TD="$HOME/.claude/dforge/sessions/turns"
mkdir -p "$SD" "$TD"
LOG="$TMP/repo/.dforge/session-state.log"
ms() { echo $(( ($(date +%s) - ${1:-0}) * 1000 )); } # ms [SECONDS_AGO]
state() { # state SID UPDATED_MS [PARTIAL] [SESSION]
  jq -nc --arg s "${4:-$1}" --argjson u "$2" --argjson p "${3:-false}" --argjson at "$(ms)" \
    '{session:$s, updated:$u, window:200000, model:"claude-x", partial:$p,
      launches:[{id:"b1", kind:"shell", what:"Dev server", command:"npm run dev", startedAt:$at, outputFile:"", service:true, timer:false}]}' > "$SD/$1.json"
}
touch -d '-60 seconds' "$TD/s-1"

check "the file name is the sanitised id" "$(ss_file 'a:b')" "$SD/a-b.json"
state s-1 "$(ms)"
check "window" "$(ss_window s-1)" "200000"
check "model" "$(ss_model s-1)" "claude-x"
check "launches: six fields with the service role" "$(ss_launches s-1 | cut -f1,2,4,5,6)" $'shell\tb1\tidle -\tDev server\tservice'

state s-1 "$(ms 120)"
ss_launches s-1 >/dev/null; rc=$?
check "launches older than the turn stamp are stale" "$rc" "1"
check "the window stays valid for the same session" "$(ss_window s-1)" "200000"
ss_launches s-1 >/dev/null
check "a rejection is logged once per turn" "$(grep -c $'\ts-1\tlaunches\tstale$' "$LOG")" "1"

state s-1 "$(ms)" true
ss_launches s-1 >/dev/null; rc=$?
check "partial launches are rejected" "$rc:$(grep -c $'\tlaunches\tpartial$' "$LOG")" "1:1"

state s-1 "$(ms)" false s-other
ss_window s-1 >/dev/null; rc=$?
check "another session's file is rejected" "$rc:$(grep -c $'\twindow\tsession mismatch$' "$LOG")" "1:1"

printf 'not json\n' > "$SD/s-1.json"
ss_window s-1 >/dev/null; rc=$?
check "an unparseable file is rejected" "$rc:$(grep -c $'\twindow\tunparseable$' "$LOG")" "1:1"

ss_window s-9 >/dev/null; rc=$?
check "a missing file is rejected" "$rc:$(grep -c $'\ts-9\twindow\tmissing$' "$LOG")" "1:1"

state s-2 "$(ms)"
ss_launches s-2 >/dev/null; rc=$?
check "no turn stamp: launches are stale" "$rc" "1"

state s-old "$(ms)"; touch -d '-31 days' "$SD/s-old.json"
ss_prune
check "prune: a file older than 30 days goes, a newer one stays" \
  "$([ -e "$SD/s-old.json" ] && echo kept || echo gone) $([ -e "$SD/s-2.json" ] && echo kept || echo gone)" "gone kept"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

Add `'session-state.test.sh': 20,` to `windowsSeconds` in `scripts/test-shards.mjs`, in name order.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 120 bash plugins/dforge/tests/session-state.test.sh`
Expected: FAIL (`session-state.sh` does not exist).

- [ ] **Step 3: Implement**

1. Create `scripts/lib/session-state.sh` with the C2 functions. It sources nothing; `ss_launches` formats `startedAt` as local `HH:MM` and the idle field with `inflight_idle` when that function is defined (callers source `lib/in-flight.sh` first), else `idle -`; the role is `service`, `timer` or `work` from the two booleans; `what` is cut at 80 characters with tabs and newlines turned to spaces.
2. The log goes to `<state>/session-state.log` where `<state>` is `dforge_dir state` of `git rev-parse --show-toplevel` (`lib/dforge-dir.sh`); outside a git checkout nothing is logged. The turn-stamp epoch in each line is the stamp's modification time, or `0` without a stamp. Read jq input on stdin.
3. In `session-start.sh`, source the lib and call `ss_prune` once, in the block that already prunes session records; it must never fail the hook.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 120 bash plugins/dforge/tests/session-state.test.sh && timeout 300 bash plugins/dforge/tests/hook.test.sh && timeout 120 node --test tests/test-shards.test.mjs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/session-state.sh plugins/dforge/scripts/session-start.sh scripts/test-shards.mjs plugins/dforge/tests/session-state.test.sh
git commit -m "feat(dforge): read the cockpit session state file"
```

### Task 3: Shared service list and launch roles in in-flight.sh

**Files:**
- Create: `plugins/dforge/config/services.json`
- Create: `plugins/dforge/tests/fixtures/service-commands.json`
- Modify: `plugins/dforge/scripts/lib/in-flight.sh`
- Test: `plugins/dforge/tests/in-flight.test.sh`

**Interfaces:**
- Consumes: C2.
- Produces: C3, C4.

**Items:** 12, 37, 40
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/fixtures/service-commands.json` with every command of `cockpit.test.ts::tells a service from a job that ends` (the 14 service commands with `"role": "service"`, the 9 others with `"role": "work"`), plus `{"command": "sleep 1200", "role": "timer"}`, `{"command": "sleep 30m", "role": "timer"}`, `{"command": "sleep 5 && npm test", "role": "work"}`.

Append to `plugins/dforge/tests/in-flight.test.sh`, before its summary lines:

```bash
# --- launch roles from config/services.json (C3, C4) ---
. "$HERE/../scripts/lib/in-flight.sh"
FIX="$HERE/fixtures/service-commands.json"
while IFS=$'\t' read -r cmd role; do
  check "role of $(printf '%q' "$cmd")" "$(inflight_role "$cmd")" "$role"
done < <(jq -r '.[] | [.command, .role] | @tsv' < "$FIX" | tr -d '\r')

bash_use() { # bash_use <tool_use_id> <description> <command>
  fjq -nc --arg id "$1" --arg d "$2" --arg c "$3" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:$id,name:"Bash",input:{description:$d,command:$c,run_in_background:true}}]}}' >> "$TP"
}
: > "$TP"
bash_use toolu_dev 'Dev server' 'npm run dev'
result toolu_dev 'Command running in background with ID: d1. Output is being written to: /tmp/d1.output.'
bash_use toolu_t 'QA timer' 'sleep 1200'
result toolu_t 'Command running in background with ID: t1. Output is being written to: /tmp/t1.output.'
bash_use toolu_w 'Run the suite' 'npm test'
result toolu_w 'Command running in background with ID: w1. Output is being written to: /tmp/w1.output.'
check "scan: the sixth field is the role" "$(inflight_scan "$TP" | cut -f2,6 | tr '\n' ' ')" "d1	service t1	timer w1	work "

SD="$HOME/.claude/dforge/sessions/state"; mkdir -p "$SD" "$HOME/.claude/dforge/sessions/turns"
touch -d '-60 seconds' "$HOME/.claude/dforge/sessions/turns/$SID"
jq -nc --arg s "$SID" --argjson u "$(( $(date +%s) * 1000 ))" \
  '{session:$s, updated:$u, window:null, model:null, partial:false, launches:[{id:"z9", kind:"agent", what:"Review", command:"", startedAt:$u, outputFile:"", service:false, timer:false}]}' > "$SD/$SID.json"
check "list: a fresh session file is the source" "$(inflight_source "$SID") $(inflight_list "$TP" "" "$SID" | cut -f2)" "session file z9"
jq -c '.partial = true' < "$SD/$SID.json" > "$SD/x" && mv "$SD/x" "$SD/$SID.json"
check "list: a partial file falls back to the transcript" "$(inflight_source "$SID") $(inflight_list "$TP" "" "$SID" | cut -f2 | tr '\n' ' ')" "transcript d1 t1 w1 "
rm -f "$SD/$SID.json"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/in-flight.test.sh`
Expected: FAIL (`inflight_role: command not found`).

- [ ] **Step 3: Implement**

1. Create `config/services.json` from `SERVICES` in `hooks/cockpit/lib.ts:1218-1228`, each pattern JSON-escaped, and the C4 `timer` pattern; check each compiles under `jq -n 'test(...)'`.
2. In `lib/in-flight.sh`, add `inflight_role COMMAND` (C4, evaluated by one jq call that reads `services.json` on stdin and the command with `--arg`), and make `inflight_scan`'s first jq pass carry `.input.command` (first line) for each tool_use; the final loop prints the role as field 6 (an agent or monitor is `work`). Compute roles in one jq call for all launches, not one per line.
3. Add `inflight_list` and `inflight_source` (C3); `inflight_text` prints fields 1-5 and appends ` (service)` or ` (timer)`. Source `lib/session-state.sh` at the end of the file.
4. `scripts/in-flight`'s `wc`-style count and `next-step`/`turn-end.sh` stay unchanged here; Tasks 5 and 7 change them.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/in-flight.test.sh && timeout 600 bash plugins/dforge/tests/turn-end.test.sh`
Expected: PASS (turn-end still passes: its line count of running work is unchanged).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/config/services.json plugins/dforge/tests/fixtures/service-commands.json plugins/dforge/scripts/lib/in-flight.sh plugins/dforge/tests/in-flight.test.sh
git commit -m "feat(dforge): tell services and timers from work"
```

### Task 4: Cockpit reads the shared service list

**Files:**
- Create: `plugins/dforge/config/services.mjs`
- Create: `plugins/dforge/config/services.d.mts`
- Create: `plugins/dforge/tests/fixtures/service-commands.mjs`
- Create: `plugins/dforge/tests/fixtures/service-commands.d.mts`
- Modify: `plugins/dforge/hooks/cockpit/lib.ts`
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Modify: `plugins/dforge/scripts/in-flight`
- Test: `plugins/dforge/tests/cockpit.test.ts`
- Test: `plugins/dforge/tests/in-flight.test.sh`
- Test: `tests/repository-layout.test.mjs`

**Interfaces:**
- Consumes: C4.
- Produces: C4's module mirrors (`config/services.mjs`, `tests/fixtures/service-commands.mjs`).

**Items:** 12, 37
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

A Claude Code mod, and every file it or its tests import, loads only code files: `import ... from '../config/x.json'` fails with "is not named like code and was not loaded", and `import ... from 'node:fs'` fails with "a hooks module imports its own files by relative path and "claude-code", nothing else". So the cockpit reads C4 through generated `.mjs` mirrors of the two JSON files, the way it already imports `config/schema.mjs`, and a node test keeps each mirror equal to its JSON file. The JSON files stay the ones to edit; the shell side keeps reading them with jq.

- [ ] **Step 1: Write the failing tests**

1. From the repository root, generate the fixture's mirror (the same command, naming `config/services.json`, generates the service list's mirror in Step 3):

```bash
node -e "const fs = require('node:fs'); for (const file of process.argv.slice(1)) fs.writeFileSync(file.slice(0, -5) + '.mjs', '// Generated from ' + file.split('/').pop() + ': edit that file, then run the command in tests/repository-layout.test.mjs.\nexport default ' + JSON.stringify(JSON.parse(fs.readFileSync(file, 'utf8')), null, 2) + '\n')" plugins/dforge/tests/fixtures/service-commands.json
```

2. Create `plugins/dforge/tests/fixtures/service-commands.d.mts`:

```ts
// Types for service-commands.mjs, so cockpit.test.ts's import type-checks.
declare const cases: readonly { command: string; role: 'service' | 'timer' | 'work' }[]
export default cases
```

3. In `plugins/dforge/tests/cockpit.test.ts`, add `isTimerCommand,` after `isServiceCommand,` in the `../hooks/cockpit/lib` import, and add this line after the `../hooks/cockpit/svg` import:

```ts
import SERVICE_COMMANDS from './fixtures/service-commands.mjs'
```

4. Rewritten assertion (row 12 moves the list into the shared fixture): replace the body of `tells a service from a job that ends` (in `describe('now row')`), whose two literal loops become one over the fixture:

```ts
  test('tells a service from a job that ends', () => {
    expect(SERVICE_COMMANDS.length).toBeGreaterThan(25)
    for (const { command, role } of SERVICE_COMMANDS) {
      expect([command, isServiceCommand(command)]).toEqual([command, role === 'service'])
      expect([command, isTimerCommand(command)]).toEqual([command, role === 'timer'])
    }
  })
```

5. Rewritten assertion (row 37 adds a sentence to the reconcile prompt): in `describe('auto run')`, replace `RECONCILE_PROMPT` with:

```ts
  const RECONCILE_PROMPT =
    /^Background work has run 20 minutes since the last turn with no notification\. Run `bash "[^"]*\/scripts\/in-flight"`\. Stop with TaskStop each launch idle 30 minutes or more, and record a `Ruling:` line naming the task it served and that its result is void; leave the others running\. Never stop a bare `sleep` timer: it bounds a dispatch\. Then continue the run, and end the turn again if only waiting remains\.$/
```

6. In `describe('auto run')`, beside `submits one reconcile prompt when a background ${holder} alone holds a bound run for 20 minutes`:

```ts
  test('a bare sleep timer alone never draws a reconcile prompt', async ($, on) => {
    const files = autoFiles({ pending: null })
    const bash = { Bash: () => ({ result: { stdout: '', stderr: '', interrupted: false, backgroundTaskId: 'qa1' }, text: 'Running in the background' }) }
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO], tools: bash }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'sleep 3600', run_in_background: true } as never)
    await $.turn.complete({ answer: 'Waiting for QA.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await clock.advance(2_600_000)
    expect(w.prompts?.filter(text => /^Background work has run/.test(text))).toEqual([])
  })
```

7. Append to `plugins/dforge/tests/in-flight.test.sh`, after Task 3's part and before its summary lines. The idle report is `scripts/in-flight`'s listing, which the reconcile prompt sends the session to and whose closing text says to stop each launch with TaskStop:

```bash
# --- the idle report leaves a bare sleep timer running (row 37) ---
# The "no transcript" part above removed the session record; in-flight needs it.
jq -n --arg tp "$TP" '{session_id:"s-flight",transcript_path:$tp}' > "$HOME/.claude/dforge/sessions/by-id/$SID.json"
TIMER_LINE='A launch marked (timer) is a bare sleep that bounds a dispatch: leave it running.'
: > "$TP"
bash_use toolu_t 'QA timer' 'sleep 1200'
result toolu_t 'Command running in background with ID: t1. Output is being written to: /tmp/t1.output.'
out=$(bash "$INFLIGHT")
check "a timer is listed as a timer" "$(grep -c '^- shell t1 .* QA timer (timer)$' <<<"$out")" "1"
check "the report says to leave a timer running" "$(grep -cxF "$TIMER_LINE" <<<"$out")" "1"
: > "$TP"
bash_use toolu_w 'Run the suite' 'npm test'
result toolu_w 'Command running in background with ID: w1. Output is being written to: /tmp/w1.output.'
out=$(bash "$INFLIGHT")
check "no timer, no timer line" "$(grep -cxF "$TIMER_LINE" <<<"$out")" "0"
```

8. In `tests/repository-layout.test.mjs`, change the `node:url` import to `import { fileURLToPath, pathToFileURL } from 'node:url';` and add:

```js
test('the cockpit\'s module mirrors of dforge JSON files match them', async () => {
  const sources = ['plugins/dforge/config/services.json', 'plugins/dforge/tests/fixtures/service-commands.json'];
  const regenerate = `node -e "const fs = require('node:fs'); for (const file of process.argv.slice(1)) fs.writeFileSync(file.slice(0, -5) + '.mjs', '// Generated from ' + file.split('/').pop() + ': edit that file, then run the command in tests/repository-layout.test.mjs.\\nexport default ' + JSON.stringify(JSON.parse(fs.readFileSync(file, 'utf8')), null, 2) + '\\n')" ${sources.join(' ')}`;
  for (const rel of sources) {
    const mirror = rel.slice(0, -'.json'.length) + '.mjs';
    assert.ok(existsSync(resolve(root, mirror)), `${mirror} is missing; from the repository root run: ${regenerate}`);
    const { default: value } = await import(pathToFileURL(resolve(root, mirror)).href);
    assert.deepEqual(value, json(rel), `${mirror} differs from ${rel}; from the repository root run: ${regenerate}`);
  }
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge; timeout 300 bash plugins/dforge/tests/in-flight.test.sh; timeout 120 node --test tests/repository-layout.test.mjs`
Expected: FAIL. The cockpit suite fails `a bare sleep timer alone never draws a reconcile prompt` (a reconcile prompt is sent at 21 minutes) and every test that matches `RECONCILE_PROMPT` (the sentence is missing); in-flight fails `the report says to leave a timer running`; the layout test fails with `plugins/dforge/config/services.mjs is missing`.

- [ ] **Step 3: Implement**

1. From the repository root, run the Step 1 command with `plugins/dforge/config/services.json` in place of the fixture path, which writes `config/services.mjs`. Add `config/services.d.mts` declaring its default export as `{ services: readonly string[]; timer: string }`, the way `config/schema.d.mts` types `schema.mjs`.
2. In `lib.ts`, import the default export of `../../config/services.mjs` (as `config.ts:1` imports `../../config/schema.mjs`). Replace the `SERVICES` literal (`:1218-1227`) with that list's `services`, each compiled once with `new RegExp(pattern)` at module load, and build `isTimerCommand` from its `timer` pattern, tested against the trimmed first line. Read no file at run time: no JSON import, no `node:fs`, no `$.fs.read`.
3. In `register.tsx`, `backgroundKey` (`:3074`) and `reconcileBackground` (`:3085`) leave out main-loop shells whose command is a timer or a service, so a timer or a service alone never starts the 20-minute reconcile; `isMainBackground` (`:2660`) keeps holding a timer as background work.
4. `reconcilePrompt` (`:203`) gains the sentence `Never stop a bare \`sleep\` timer: it bounds a dispatch.` after `leave the others running.`
5. `scripts/in-flight`: after its closing text, when a listed launch ends ` (timer)`, print the line `A launch marked (timer) is a bare sleep that bounds a dispatch: leave it running.`

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge && timeout 300 bash plugins/dforge/tests/in-flight.test.sh && timeout 120 node --test tests/repository-layout.test.mjs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/config/services.mjs plugins/dforge/config/services.d.mts plugins/dforge/tests/fixtures/service-commands.mjs plugins/dforge/tests/fixtures/service-commands.d.mts plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/scripts/in-flight plugins/dforge/tests/cockpit.test.ts plugins/dforge/tests/in-flight.test.sh tests/repository-layout.test.mjs
git commit -m "feat(dforge): share the service list with the cockpit"
```

### Task 5: in-flight and next-step over services

**Files:**
- Modify: `plugins/dforge/scripts/in-flight`
- Modify: `plugins/dforge/scripts/next-step`
- Test: `plugins/dforge/tests/in-flight.test.sh`
- Test: `plugins/dforge/tests/next-step.test.sh`

**Interfaces:**
- Consumes: C3.
- Produces: none.

**Items:** 12, 40
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

Append to `plugins/dforge/tests/in-flight.test.sh` at its end, after Task 4's part and before its summary lines (an earlier part deletes the by-id record, which Task 4's part re-creates):

```bash
# --- in-flight lists services but exits 1 only for finite work ---
: > "$TP"
bash_use toolu_dev 'Dev server' 'npm run dev'
result toolu_dev 'Command running in background with ID: d1. Output is being written to: /tmp/d1.output.'
out=$(bash "$INFLIGHT"); code=$?
check "a service alone: exit 0" "$code" "0"
check "a service alone: listed as a service" "$(grep -c '^- shell d1 .* Dev server (service)$' <<<"$out")" "1"
check "the source is named" "$(grep -c '^in-flight: source transcript$' <<<"$out")" "1"
bash_use toolu_w 'Run the suite' 'npm test'
result toolu_w 'Command running in background with ID: w1. Output is being written to: /tmp/w1.output.'
out=$(bash "$INFLIGHT"); code=$?
check "finite work beside a service: exit 1" "$code" "1"
```

Append to `plugins/dforge/tests/next-step.test.sh`, before its darkmem part (`. "$HERE/fixtures/darkmem-stores.sh"`):

```bash
# --- a service-only list does not stop the block ---
SID=s-next; export CLAUDE_CODE_SESSION_ID=$SID
NT="$TMP/$SID.jsonl"
mkdir -p "$HOME/.claude/dforge/sessions/by-id"
jq -n --arg tp "$NT" '{session_id:"s-next",transcript_path:$tp}' > "$HOME/.claude/dforge/sessions/by-id/$SID.json"
jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_dev",name:"Bash",input:{description:"Dev server",command:"npm run dev",run_in_background:true}}]}}' > "$NT"
jq -nc '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_dev",content:"Command running in background with ID: d1. Output is being written to: /tmp/d1.output."}]}}' >> "$NT"
run "$REPO" "$PLAN_REL"
check "service only: exits 0" "$status" "0"
has "service only: the block is printed" "$out" "## Next session"
has "service only: the services are named" "$out" "Still running services: shell d1 (Dev server)"
rm -f "$HOME/.claude/dforge/sessions/by-id/$SID.json"; unset CLAUDE_CODE_SESSION_ID
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/in-flight.test.sh; timeout 700 bash plugins/dforge/tests/next-step.test.sh`
Expected: FAIL on `a service alone: exit 0` and `service only: exits 0`.

- [ ] **Step 3: Implement**

1. `scripts/in-flight`: use `inflight_list` with the session id, print `in-flight: source <inflight_source>` as the second line, list every launch with `inflight_text`, and exit 1 only when a `work` or `timer` launch runs; a service-only list exits 0 with `in-flight: only services are running:` and the list. Update its header's Exit line.
2. `scripts/next-step` (`:465-469`): on exit 0, collect the `(service)` lines; when there are any, add one line under the block's Next line: `Still running services: <kind> <id> (<what>)[, …] — stop them with TaskStop before you end the session.`

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/in-flight.test.sh && timeout 700 bash plugins/dforge/tests/next-step.test.sh`
Expected: PASS. The existing in-flight assertion `the shell is named` (`'^- shell b9 - idle - Run the suite$'`) still matches: a `work` launch gets no suffix.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/in-flight plugins/dforge/scripts/next-step plugins/dforge/tests/in-flight.test.sh plugins/dforge/tests/next-step.test.sh
git commit -m "fix(dforge): let services pass the in-flight check"
```

### Task 6: Final review state helper and next-step routing

**Files:**
- Modify: `plugins/dforge/scripts/lib/plan.sh`
- Modify: `plugins/dforge/scripts/next-step`
- Test: `plugins/dforge/tests/next-step.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: C5.

**Items:** 3
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Append to `plugins/dforge/tests/next-step.test.sh`, before its darkmem part:

```bash
# --- a clean final review is current only for the head it names (C5) ---
done3() { ledger 'Task 1: complete (commits a..b, review clean)' 'Task 2: complete (commits b..c, review clean)' 'Task 3: complete (commits c..d, review clean)' "$@"; }
git -C "$REPO" checkout -q -b feat-c5
head7=$(git -C "$REPO" rev-parse --short HEAD)
done3 "Final review: clean (commits 0000000..$head7)"
run "$REPO" "$PLAN_REL"
has "C5: current clean line routes to finishing" "$out" "**Next:** Run dforge:finishing-a-development-branch."
mkdir -p "$REPO/docs/dforge/plans" && printf 'note\n' > "$REPO/docs/dforge/plans/completed.md"
git -C "$REPO" add docs/dforge/plans/completed.md && git -C "$REPO" commit -qm "docs: index"
run "$REPO" "$PLAN_REL"
has "C5: docs-only commits after the head keep it current" "$out" "**Next:** Run dforge:finishing-a-development-branch."
printf 'x\n' > "$REPO/code.txt" && git -C "$REPO" add code.txt && git -C "$REPO" commit -qm "fix: later"
run "$REPO" "$PLAN_REL"
has "C5: a later code commit routes to a scoped re-review" "$out" "Re-review $head7..HEAD"
git -C "$REPO" reset -q --hard "$head7" && git -C "$REPO" commit -q --amend -m "rewritten"
run "$REPO" "$PLAN_REL"
has "C5: a rewritten head routes to a full final review" "$out" "Run the final whole-branch review, then dforge:finishing-a-development-branch."
head7=$(git -C "$REPO" rev-parse --short HEAD)
done3 "Final review: clean (commits 0000000..$head7)"
git -C "$REPO" checkout -q -
git -C "$REPO" merge -q --no-ff -m "merge feat-c5" feat-c5
printf 'y\n' > "$REPO/base.txt" && git -C "$REPO" add base.txt && git -C "$REPO" commit -qm "fix: on base"
run "$REPO" "$PLAN_REL"
has "C5: a base branch that merged the head routes to finishing" "$out" "**Next:** Run dforge:finishing-a-development-branch."
git -C "$REPO" reset -q --hard HEAD~2 && git -C "$REPO" branch -qD feat-c5
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 700 bash plugins/dforge/tests/next-step.test.sh`
Expected: FAIL on `C5: a later code commit routes to a scoped re-review`.

- [ ] **Step 3: Implement**

1. In `lib/plan.sh`, add `plan_final_review_state LEDGER [DIR]` (C5), running every git call as `git -C "$(dr_native_path "${2:-$PWD}")"`. Decide in this order: no clean line, `none`; no `(commits …)` clause or HEAD equal to `<head>`, `current`; `git merge-base --is-ancestor <head> HEAD` false or `<head>` not a commit, `rewritten <head>`; `<head>` absent from `git rev-list --first-parent HEAD`, `current`; every path of `git log --format= --name-only <head>..HEAD` under the docs root as C5 defines it, `current`; otherwise `stale <head>`. Compare paths after `tr -d '\r'`, and compare the docs root and `<toplevel>/<path>` as `cygpath -m` forms where `cygpath` exists (Global Constraints).
2. In `next-step` (`:428`), replace the `grep -q '^Final review: clean'` test: `current` keeps today's finishing route; `stale <h>` prints Status `all N tasks complete; commits after the clean review (<h>) are unreviewed` and Next `Re-review <h>..HEAD with the fix-wave re-review in reference/final-review.md, then append a new clean line; then dforge:finishing-a-development-branch.`; `rewritten <h>` takes the no-clean route (`Run the final whole-branch review, …`) and its Status adds `the reviewed head <h> is no longer in the branch history`; `none` is unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 700 bash plugins/dforge/tests/next-step.test.sh && timeout 300 bash plugins/dforge/tests/plan-lib.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/plan.sh plugins/dforge/scripts/next-step plugins/dforge/tests/next-step.test.sh
git commit -m "fix(dforge): route a stale clean review to re-review"
```

### Task 7: turn-end.sh holds over services and stale clean lines

**Files:**
- Modify: `plugins/dforge/scripts/turn-end.sh`
- Test: `plugins/dforge/tests/turn-end.test.sh`

**Interfaces:**
- Consumes: C3, C5.
- Produces: none.

**Items:** 12, 3
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Append to `plugins/dforge/tests/turn-end.test.sh`, before its darkmem part (`. "$HERE/fixtures/darkmem-stores.sh"`):

```bash
# --- a running service does not pass a plain stop (row 12) ---
SVC="$TMP/service.jsonl"
jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_dev",name:"Bash",input:{description:"Dev server",command:"npm run dev",run_in_background:true}}]}}' > "$SVC"
jq -nc '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_dev",content:"Command running in background with ID: d1. Output is being written to: /tmp/d1.output."}]}}' >> "$SVC"
sleep 1; prompt s-svc
write_ledger 'Task 1: complete (commits a..b, review clean)'
check "a service alone: a mid-plan summary stop is held" "$(decision "$(stop s-svc 'Task 1 is done.' false "$SVC")")" "block"
check "a service alone: the next-step block passes" "$(stop s-svc $'## Next session\n\n**Status:** x' false "$SVC")" ""

# --- a clean line older than the code is not current (row 3) ---
h7=$(git -C "$REPO" rev-parse --short HEAD)
printf 'x\n' > "$REPO/code.txt"
git -C "$REPO" add code.txt && git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -qm "fix: later"
sleep 1; prompt s-stale
write_ledger "Final review: clean (commits 0000000..$h7)"
out=$(stop s-stale 'All done.')
check "a stale clean line: held" "$(decision "$out")" "block"
check "a stale clean line: not sent to the finishing menu" "$(jq -r .reason <<<"$out" | grep -c 'passed its final review')" "0"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/turn-end.test.sh`
Expected: FAIL on `a service alone: a mid-plan summary stop is held`.

- [ ] **Step 3: Implement**

1. Read the running list with `inflight_list "$transcript_path" "$since" "$session_id"` and count only `work` and `timer` lines in `pending` (`:117-121`); the session-ending hold over running work (`:130-141`) names only those lines too. A service-only list therefore reaches the auto-run and ledger checks.
2. Replace `grep -q '^Final review: clean' "$candidate"` (`:91`) with `plan_final_review_state "$candidate" "$root"` (source `lib/plan.sh`): only `current` takes the finishing branch; `stale` and `rewritten` take the other branch, so the hold says "advanced without a next step".
3. Update the header comment (lines 10-16) to say a running service does not count as waiting.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/turn-end.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/turn-end.sh plugins/dforge/tests/turn-end.test.sh
git commit -m "fix(dforge): hold stops over services and stale reviews"
```

### Task 8: Context window from the session state file

**Files:**
- Modify: `plugins/dforge/scripts/lib/context.sh`
- Modify: `plugins/dforge/scripts/lib/auto-run.sh`
- Modify: `plugins/dforge/reference/session-budget.md`
- Test: `plugins/dforge/tests/context-size.test.sh`
- Test: `plugins/dforge/tests/auto-run.test.sh`

**Interfaces:**
- Consumes: C2.
- Produces: none.

**Items:** 28
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Append to `plugins/dforge/tests/context-size.test.sh`, before its Codex part (the line that sources `scripts/lib/context.sh`):

```bash
# --- the window: the session state file, else the model table, else unknown (row 28) ---
TW="$PROJ/s-win.jsonl"
asst 300000 false claude-mystery-9 > "$TW"
record s-win "$TW"
run
check "unlisted model, no state file: unknown, exit 3" "$status:$(grep -c ' — unknown — ' <<<"$out")" "3:1"
check "unlisted model: no arithmetic error" "$(grep -c 'syntax error\|integer expression' "$TMP/stderr")" "0"
mkdir -p "$HOME/.claude/dforge/sessions/state"
jq -nc --argjson u "$(( $(date +%s) * 1000 ))" '{session:"s-win",updated:$u,window:400000,model:"claude-mystery-9",partial:false,launches:[]}' > "$HOME/.claude/dforge/sessions/state/s-win.json"
run
check "the state file's window gives a verdict" "$status" "5"
has "the line names the window's source" "$out" "— source: record, window session file"
rm -f "$HOME/.claude/dforge/sessions/state/s-win.json"
```

Append to `plugins/dforge/tests/auto-run.test.sh`, after the `verdict()` cases (`:445-494`):

```bash
# --- an unknown window never asks for a size-based compaction (R17) ---
jq '.pending = "after-compact"' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"
out=$(verdict --tokens 900000 --window 0); status=$?
check "unknown window: unknown, exit 3, nothing pending" "$status:${out%% *}:$(field pending)" "3:unknown:null"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/context-size.test.sh; timeout 700 bash plugins/dforge/tests/auto-run.test.sh`
Expected: FAIL on `unlisted model, no state file: unknown, exit 3` and `unknown window: unknown, exit 3, nothing pending`.

- [ ] **Step 3: Implement**

1. `ctx_model_window MODEL [SID]`: `ss_window SID` first (SID defaults to `CLAUDE_CODE_SESSION_ID`, else the basename of `CTX_TRANSCRIPT` without `.jsonl`), setting `CTX_WINDOW_SOURCE=session file`; else the table — `*haiku*` 200000; `claude-fable-5-1*`, `claude-opus-5-5*`, `claude-sonnet-5-5*` 1000000 — with `CTX_WINDOW_SOURCE=table`; else print nothing and return 1. `ctx_window`, `ctx_budget`, `ctx_final_budget` and `ctx_plan_budget` return 1 with nothing printed when the window is unknown.
2. `ctx_line` and `ctx_auto_line`: on an unknown window print `<label>: <t>k measured — unknown — the model's window is unknown` and return 3, before any arithmetic; a known window ends the line `— source: <CTX_SOURCE>, window <CTX_WINDOW_SOURCE>` when the source is `session file` (the table source keeps today's line, so the existing exact-line assertions stand).
3. `ar_verdict TOKENS BUDGET WINDOW` with WINDOW `0`: print `unknown 0 <regime>`, clear a pending `after-compact`, set nothing else, return 3; `auto-run verdict` accepts `--window 0` and exits 3 on it; `ar_limit` is not called.
4. `session-budget.md`: say an unlisted model takes the cockpit's window or reads unknown, never 1,000,000, and that the script's budget agrees with the cockpit's only when the state file is present.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/context-size.test.sh && timeout 700 bash plugins/dforge/tests/auto-run.test.sh && timeout 300 bash plugins/dforge/tests/budget-line.test.sh`
Expected: PASS. Rewritten assertion: none; a test pinning the 1,000,000 fallback for an unlisted model, if one turns up, is rewritten to `unknown` and named in the commit body.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/context.sh plugins/dforge/scripts/lib/auto-run.sh plugins/dforge/reference/session-budget.md plugins/dforge/tests/context-size.test.sh plugins/dforge/tests/auto-run.test.sh
git commit -m "fix(dforge): read the window, never assume a million"
```

### Task 9: Request- and session-scoped fast mode in the hooks

**Files:**
- Modify: `plugins/dforge/scripts/lib/fast-mode.sh`
- Create: `plugins/dforge/tests/fixtures/fast-mode/cases.json`
- Test: `plugins/dforge/tests/ui-hooks.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: C6.

**Items:** 14, 39, 59
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/fixtures/fast-mode/cases.json` (C6; `before` and `after` are main-loop assistant texts on either side of the turn stamp, `after: null` means no stamp):

```json
[
  {"name": "plain fast in this request", "before": [], "after": ["Process: fast — a one-line fix"], "on": true},
  {"name": "plain fast in an earlier request", "before": ["Process: fast — a one-line fix"], "after": ["Done."], "on": false},
  {"name": "session fast in an earlier request", "before": ["Process: fast (session) — spikes all day"], "after": ["ok"], "on": true},
  {"name": "an expired plain line keeps the session scope", "before": ["Process: fast (session) — spikes", "Process: fast — again"], "after": ["ok"], "on": true},
  {"name": "a full-flow line ends the session scope", "before": ["Process: fast (session) — spikes", "Process: bounded — no trigger"], "after": ["ok"], "on": false},
  {"name": "no turn stamp: plain fast is on", "before": ["Process: fast — a one-line fix"], "after": null, "on": true},
  {"name": "a full-flow line in this request", "before": ["Process: fast (session) — spikes"], "after": ["Process: architectural, depth full — risk"], "on": false}
]
```

Append to `plugins/dforge/tests/ui-hooks.test.sh`, before its summary lines:

```bash
# --- fast_mode_on: request and session scope (C6) ---
. "$HERE/../scripts/lib/fast-mode.sh"
TURNS="$HOME/.claude/dforge/sessions/turns"; mkdir -p "$TURNS"
said() { jq -nc --arg t "$1" --arg ts "$2" '{type:"assistant",timestamp:$ts,message:{role:"assistant",content:[{type:"text",text:$t}]}}'; }
n=0
while IFS= read -r c; do
  n=$((n + 1)); sid="fm-$n"; tp="$TMP/$sid.jsonl"; : > "$tp"; rm -f "$TURNS/$sid" "$TURNS/$sid.fast"
  while IFS= read -r t; do said "$t" "2020-01-01T00:00:00.000Z" >> "$tp"; done < <(jq -r '.before[]' <<<"$c")
  if [ "$(jq -r '.after == null' <<<"$c")" = false ]; then
    touch -d '2020-01-01T00:01:00Z' "$TURNS/$sid"
    while IFS= read -r t; do said "$t" "2020-01-01T00:02:00.000Z" >> "$tp"; done < <(jq -r '.after[]' <<<"$c")
  fi
  if fast_mode_on "$tp"; then got=true; else got=false; fi
  check "fast mode: $(jq -r .name <<<"$c")" "$got" "$(jq -r .on <<<"$c")"
done < <(jq -c '.[]' < "$HERE/fixtures/fast-mode/cases.json")

# The verdict for the part before the stamp is read once per turn.
sid=fm-cache; tp="$TMP/$sid.jsonl"
said 'Process: fast (session) — spikes' 2020-01-01T00:00:00.000Z > "$tp"
touch -d '2020-01-01T00:01:00Z' "$TURNS/$sid"
fast_mode_on "$tp"
said 'Process: bounded — no trigger' 2020-01-01T00:00:00.000Z > "$tp.new" && mv "$tp.new" "$tp"
fast_mode_on "$tp"; rc=$?
check "fast mode: the pre-stamp verdict is cached for the turn" "$rc:$(cat "$TURNS/$sid.fast")" "0:on"

# The scan reads from the end and stops at the deciding line (ruling R9): jq,
# wrapped to log the bytes each call reads, never sees the 64 MiB head that a
# forward pass must read.
sid=fm-big; tp="$TMP/$sid.jsonl"; rm -f "$TURNS/$sid" "$TURNS/$sid.fast"
JQW="$TMP/jq-wrap"; mkdir -p "$JQW"
export JQ_BYTES="$TMP/jq-bytes" REAL_JQ; REAL_JQ=$(command -v jq); : > "$JQ_BYTES"
cat > "$JQW/jq" <<'W'
#!/usr/bin/env bash
n=0
for a in "$@"; do [ -f "$a" ] && n=$((n + $(wc -c < "$a"))); done
t=$(mktemp); cat > "$t"; n=$((n + $(wc -c < "$t")))
printf '%s\n' "$n" >> "$JQ_BYTES"
"$REAL_JQ" "$@" < "$t"; rc=$?; rm -f "$t"; exit $rc
W
chmod +x "$JQW/jq"
if command -v truncate >/dev/null 2>&1 && truncate -s 64M "$tp" 2>/dev/null; then
  printf '\n' >> "$tp"
  said 'Process: fast (session) — spikes' 2020-01-01T00:00:00.000Z >> "$tp"
  touch -d '2020-01-01T00:01:00Z' "$TURNS/$sid"
  said 'ok' 2020-01-01T00:02:00.000Z >> "$tp"
  PATH="$JQW:$PATH" timeout 120 bash -c '. "$1"; fast_mode_on "$2"' fm "$HERE/../scripts/lib/fast-mode.sh" "$tp" < /dev/null; rc=$?
  read_bytes=$(awk '{ s += $1 } END { print s + 0 }' "$JQ_BYTES")
  check "fast mode: a huge head is never read" "$rc:$(( read_bytes < 8388608 ))" "0:1"
else
  printf 'skip - fast mode huge head: truncate cannot make a 64 MiB file here\n'
fi
rm -f "$tp"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/ui-hooks.test.sh`
Expected: FAIL on `fast mode: plain fast in an earlier request`, `fast mode: the pre-stamp verdict is cached for the turn` and `fast mode: a huge head is never read`.

- [ ] **Step 3: Implement**

1. Rewrite `fast_mode_on TRANSCRIPT [LAST_MESSAGE]` to C6. The stamp is `$HOME/.claude/dforge/sessions/turns/<sanitised basename of TRANSCRIPT>`; an entry is after the stamp when its `timestamp` is at or after the stamp's modification time (compare as epoch seconds; an entry without a timestamp counts as after).
2. Read backwards: `tail -c` chunks of 1 MiB from the end, growing until the deciding line or the start of the file is found, each chunk through `jq -R 'fromjson?'` for main-loop assistant text; never run a full forward `jq` pass.
3. Write `<stamp>.fast` with `on` or `off` for the pre-stamp verdict the first time it is computed in a turn; read it back on later calls while the stamp is unchanged (the cache file is newer than the stamp). `scripts/turn-start.sh` needs no change: a new stamp is newer than the old cache.
4. Keep `fast_mode_process_lines` as is; the callers (`ui-edit-hook.sh:31`, `ui-turn-end.sh:241`) are unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/ui-hooks.test.sh`
Expected: PASS. Rewritten assertion: any existing ui-hooks case that relies on a plain `Process: fast` line from an earlier request staying on now expects it off (row 14), named in the commit body.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/fast-mode.sh plugins/dforge/tests/fixtures/fast-mode/cases.json plugins/dforge/tests/ui-hooks.test.sh
git commit -m "fix(dforge): scope fast mode to its request or session"
```

### Task 10: Cockpit fast mode, budget nudge and relaxed final phase

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/lib.ts`
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Modify: `plugins/dforge/config/schema.mjs`
- Create: `plugins/dforge/tests/fixtures/fast-mode/cases.mjs`
- Create: `plugins/dforge/tests/fixtures/fast-mode/cases.d.mts`
- Test: `plugins/dforge/tests/cockpit.test.ts`
- Test: `tests/repository-layout.test.mjs`

**Interfaces:**
- Consumes: C6.
- Produces: none.

**Items:** 14, 59, 13
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

A mod test cannot read a JSON file (no `node:fs`, no `.json` import; Task 4), so the cases reach it through a generated mirror, as Task 4's do.

1. From the repository root, generate `plugins/dforge/tests/fixtures/fast-mode/cases.mjs` with Task 4's command naming `plugins/dforge/tests/fixtures/fast-mode/cases.json`:

```bash
node -e "const fs = require('node:fs'); for (const file of process.argv.slice(1)) fs.writeFileSync(file.slice(0, -5) + '.mjs', '// Generated from ' + file.split('/').pop() + ': edit that file, then run the command in tests/repository-layout.test.mjs.\nexport default ' + JSON.stringify(JSON.parse(fs.readFileSync(file, 'utf8')), null, 2) + '\n')" plugins/dforge/tests/fixtures/fast-mode/cases.json
```

2. Create `plugins/dforge/tests/fixtures/fast-mode/cases.d.mts`:

```ts
// Types for cases.mjs, so cockpit.test.ts's import type-checks.
declare const cases: readonly { name: string; before: readonly string[]; after: readonly string[] | null; on: boolean }[]
export default cases
```

3. In `tests/repository-layout.test.mjs`, add `'plugins/dforge/tests/fixtures/fast-mode/cases.json'` to the `sources` list of `the cockpit's module mirrors of dforge JSON files match them` (Task 4).

4. In `plugins/dforge/tests/cockpit.test.ts`, add `import fastModeCases from './fixtures/fast-mode/cases.mjs'` after the fixture import Task 4 added, then append:

```ts
describe('fast mode scope', () => {
  const cases = fastModeCases
  const said = ($: Parameters<TestBody>[0], text: string, n: number) =>
    $.session.append({ message: { type: 'assistant', role: 'assistant', content: [{ type: 'text', text }] }, door: 'response', origin: { kind: 'model' }, uuid: `fm-${n}` } as never)
  const spawn = (id: string) => ({ tool_use_id: id, prompt: 'Look', description: 'Look around', subagentType: 'general-purpose', provider: { plugin: 'engine', tier: 'core' }, parentModel: 'claude-opus-5-5', background: false, fork: false }) as never
  for (const c of cases)
    test(`the seat check follows fast mode: ${c.name}`, async ($, on) => {
      world(on, { tokens: 10_000 })
      await $.session.start(START)
      await $.tool.call({ tool: 'Skill', skill: 'dforge:brainstorming' })
      let n = 0
      for (const text of c.before) await said($, text, n++)
      if (c.after !== null) {
        await $.prompt.submit({ text: 'the next request', wait: false } as never)
        for (const text of c.after) await said($, text, n++)
      }
      const denial = (await $.agent.spawn(spawn('toolu_fm'))).deny
      if (c.on) expect(denial).toBeUndefined()
      else expect(denial).toMatch(/^dforge: name a seat/)
    })

  test('no handoff note while fast mode is on', async ($, on) => {
    const notes: string[] = []
    const w: World = { tokens: 440_000, notes }
    world(on, w)
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:brainstorming' })
    await said($, 'Process: fast — a one-line fix', 1)
    w.tokens = 470_000
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    expect(notes.filter(text => /— handoff\./.test(text))).toEqual([])
  })

  test('relaxed mode keeps the final-phase exemption once every task is complete', async ($, on) => {
    const notes: string[] = []
    const files: World['files'] = {
      ...configured({ handoffMode: 'relaxed' }),
      '/home/me/code/shop/.dforge/sdd/p/progress.md': { text: '# SDD ledger — plan: docs/plans/p.md\nTask 1: complete (commits a..b, review clean) — done: x', mtimeMs: 2_000_000 },
      '/home/me/code/shop/docs/plans/p.md': { text: '# Plan\n\n### Task 1: Only\n' },
    }
    world(on, { ...SIGNED_IN, tokens: 600_000, notes, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:executing-plans' })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    expect(notes.filter(text => /— handoff\./.test(text))).toEqual([])
  })
})
```

In `a rows whose setting has no effect under the values in force is locked` (`:1778`), add after the handoffTokens assertion: `expect((await ui.find({ key: 'set-handoffTokens-controls' }))?.text).toMatch(/an auto run still uses it/)`.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge`
Expected: FAIL on `plain fast in an earlier request`, `no handoff note while fast mode is on`, `relaxed mode keeps the final-phase exemption once every task is complete` and the lock text.

- [ ] **Step 3: Implement**

1. `lib.ts` `fastModeLine(text)`: return `'session'` for `Process: fast (session)`, `'request'` for any other `Process: fast`, `false` for another `Process:` line, `null` for none (C6's grammar; update the three call sites).
2. `register.tsx`: keep a session-scope flag beside `isFastMode`. The `session.append` handler (`:590`) sets both from `fastModeLine`; a `prompt.submit` (`:606`) whose origin is absent or a person's (not in `NEW_CHAIN_ORIGINS`, not the keep-warm prompt) sets `isFastMode` false unless the session-scope flag is set; a `'request'` line after a session line leaves the session flag set, and a `false` line clears both.
3. `refresh` (`:3535-3594`): add `(await read($, isFastMode))` to the nudge guard; set `isFinishing = !isAuto && isTail && (!tuning.isRelaxed || summary?.isFinished === true)`.
4. `schema.mjs` `handoffTokens.inertWhen.words`: `ignored in relaxed handoff mode; an auto run still uses it`; and the description's last sentence likewise.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge && timeout 300 bash plugins/dforge/tests/dforge-config.test.sh && timeout 120 node --test tests/repository-layout.test.mjs`
Expected: PASS. Rewritten assertion: none — `stands down while the main loop is in fast mode, and a full-flow Process line turns it back on` (`:882`) keeps passing unchanged, since it submits no prompt between its lines.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/config/schema.mjs plugins/dforge/tests/cockpit.test.ts plugins/dforge/tests/fixtures/fast-mode/cases.mjs plugins/dforge/tests/fixtures/fast-mode/cases.d.mts tests/repository-layout.test.mjs
git commit -m "fix(dforge): scope cockpit fast mode and its nudge"
```

### Task 11: Compaction snapshot trust and truncation

**Files:**
- Modify: `plugins/dforge/scripts/lib/snapshot.sh`
- Test: `plugins/dforge/tests/snapshot.test.sh`

**Interfaces:**
- Consumes: C6.
- Produces: none.

**Items:** 5
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 1 = 5

- [ ] **Step 1: Write the failing test**

Append to `plugins/dforge/tests/snapshot.test.sh`, before its darkmem part (`. "$HERE/fixtures/darkmem-stores.sh"`):

```bash
# --- latest.md is trusted only when this session wrote it or its ledger (row 5) ---
TS="$TMP/ts.jsonl"
jq -nc --arg t "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" '{type:"user",timestamp:$t,message:{role:"user",content:"go"}}' > "$TS"
jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Process: fast (session) — spikes"}]}}' >> "$TS"
touch -d '-2 hours' "$REPO/.dforge/handoff/latest.md" "$WT/.dforge/sdd/plan/progress.md"
out=$(snapshot_build "$TS" "$REPO")
lacks "an old latest.md for an untouched ledger is left out" "$out" "**Next:** Resume at Task 2 (Two)."
has "a session-scoped fast line is carried" "$out" "Process: fast (session) — spikes"
touch "$REPO/.dforge/handoff/latest.md"
out=$(snapshot_build "$TS" "$REPO")
has "a latest.md newer than the session start is kept" "$out" "**Next:** Resume at Task 2 (Two)."
has "its age is stated" "$out" "(0m old)"
out=$(snapshot_build "$TS" "$REPO" 900)
check "a small cap still fits" "$([ "${#out}" -le 900 ] && echo yes || echo no)" "yes"
has "a small cap keeps the ledger's newest line" "$out" "$(tr -d '\r' < "$WT/.dforge/sdd/plan/progress.md" | grep -v '^[[:space:]]*$' | tail -n 1)"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/snapshot.test.sh`
Expected: FAIL on `an old latest.md for an untouched ledger is left out`.

- [ ] **Step 3: Implement**

1. `snapshot_build` takes the session start as the first `timestamp` in TRANSCRIPT (R11) and passes it to `snapshot_latest CWD START`, which prints the block only when `latest.md` is at or after START, or names (in its Next session block) a plan whose ledger in `dforge_ledger_files` was modified at or after START; its heading becomes ``### From `<latest>` (<age> old)`` with the age in `m`, `h` or `d`. No start found: today's behaviour.
2. Section 1 gains the newest `Process: fast (session) — …` line from the transcript when `fast_mode_on` says fast mode is on (source `lib/fast-mode.sh`).
3. Over the cap, section 3 is cut to each ledger's heading and newest lines (dropping rulings first, then older lines), never dropped whole; sections 6, 5, 4 still go first.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/snapshot.test.sh && timeout 300 bash plugins/dforge/tests/hook.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/snapshot.sh plugins/dforge/tests/snapshot.test.sh
git commit -m "fix(dforge): trust only this session's handoff in snapshots"
```

### Task 12: ui-turn-end.sh stand-downs and transcript fallback

**Files:**
- Create: `plugins/dforge/scripts/lib/last-message.sh`
- Modify: `plugins/dforge/scripts/turn-end.sh`
- Modify: `plugins/dforge/scripts/ui-turn-end.sh`
- Test: `plugins/dforge/tests/ui-hooks.test.sh`

**Interfaces:**
- Consumes: C3.
- Produces: none.

**Items:** 29
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Append to `plugins/dforge/tests/ui-hooks.test.sh`, after the part that creates `docs/dforge/ui-ux/profile.md` and before Task 9's fast-mode part:

```bash
# --- ui-turn-end.sh stands down for handoffs, questions and finite work (row 29) ---
sleep 1; prompt u-9
printf '// changed\n' >> src/App.tsx
check "a UI change with no proof: held" "$(decision "$(stop u-9 'Task 2 is done.')")" "block"
check "a Next session block stands down" "$(decision "$(stop u-9 $'Done.\n\n## Next session\n\n**Status:** x')")" "none"
mkdir -p .dforge/sdd/ui-plan
printf '# SDD ledger — plan: docs/ui-plan.md\nTask 2: waiting — which colour?\n' > .dforge/sdd/ui-plan/progress.md
check "a ledger ending on a waiting line stands down" "$(decision "$(stop u-9 'Which colour should the button be?')")" "none"
rm -rf .dforge/sdd/ui-plan
BGT="$TMP/ui-bg.jsonl"
jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"toolu_w",name:"Bash",input:{description:"Suite",command:"npm test",run_in_background:true}}]}}' > "$BGT"
jq -nc '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_w",content:"Command running in background with ID: w1. Output is being written to: /tmp/w1.output."}]}}' >> "$BGT"
check "finite background work stands down" "$(decision "$(stop u-9 'Waiting for the suite.' false "$BGT")")" "none"
LT="$TMP/ui-last.jsonl"
jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Stopping here.\n\nUI proof: pending — needs the device"}]}}' > "$LT"
out=$(jq -nc --arg tp "$LT" --arg cwd "$REPO" '{session_id:"u-9",cwd:$cwd,transcript_path:$tp,stop_hook_active:false}' | bash "$END")
check "no last_assistant_message: the transcript's pending line releases" "$(decision "$out")" "none"
git checkout -q -- src/App.tsx
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/ui-hooks.test.sh`
Expected: FAIL on `a Next session block stands down`.

- [ ] **Step 3: Implement**

1. Move `last_text` and the fallback (`turn-end.sh:58-70`) into `scripts/lib/last-message.sh` as `last_message STDIN_JSON TRANSCRIPT` (prints the text; functions only); `turn-end.sh` calls it with no change in behaviour.
2. `ui-turn-end.sh`: take `last` from `last_message`; before running `ui-proof check`, exit 0 when the message contains `## Next session`, when a ledger under `dforge_ledger_root` modified after the turn stamp ends (last non-empty line) on `Task <N>: waiting — `, or when `inflight_list` lists a `work` or `timer` launch. Keep the closing-line `UI proof: pending` release, now read from that text.
3. Update the header comment to list the new stand-downs.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/ui-hooks.test.sh && timeout 600 bash plugins/dforge/tests/turn-end.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/last-message.sh plugins/dforge/scripts/turn-end.sh plugins/dforge/scripts/ui-turn-end.sh plugins/dforge/tests/ui-hooks.test.sh
git commit -m "fix(dforge): let the UI proof hold stand down"
```

### Task 13: QA file manifest

**Files:**
- Create: `plugins/dforge/scripts/qa-files`
- Modify: `plugins/dforge/reference/final-review.md`
- Modify: `plugins/dforge/reference/acceptance-qa.md`
- Modify: `scripts/test-shards.mjs`
- Test: `plugins/dforge/tests/qa-files.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: C8.

**Items:** 1
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 0 - risk 3 = 7
**Lenses:** silent-failures

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/qa-files.test.sh`:

```bash
#!/usr/bin/env bash
# scripts/qa-files: QA's timeout cleanup touches only the paths QA listed.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QA="$HERE/../scripts/qa-files"
pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
TMP="$(mktemp -d)"
# git.exe under MSYS_NO_PATHCONV cannot open the shell's /tmp form.
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR
git init -q "$TMP/repo" && cd "$TMP/repo" || exit 1
printf '.dforge/\n' > .gitignore
printf 'one\n' > kept.txt; printf 'one\n' > qa-edit.txt; printf 'one\n' > human.txt
git add -A && git commit -qm base
WS="$TMP/repo/.dforge/sdd/p"; mkdir -p "$WS"
printf 'pre-existing\n' > dirty-before.txt

bash "$QA" begin "$WS"; rc=$?
check "begin: exit 0, manifest empty" "$rc:$(wc -c < "$WS/qa-touched.txt" | tr -d ' ')" "0:0"
# QA's work, listed; the human's work, not listed.
printf 'tests/a.acceptance.sh\nqa-edit.txt\ntests/dir/b.sh\n' >> "$WS/qa-touched.txt"
mkdir -p tests/dir && printf 'x\n' > tests/a.acceptance.sh && printf 'x\n' > tests/dir/b.sh
printf 'two\n' >> qa-edit.txt
printf 'two\n' >> human.txt
printf 'mine\n' > 'human new.txt'
out=$(bash "$QA" clean "$WS"); rc=$?
check "clean: exit 0" "$rc" "0"
check "clean: a listed new file is deleted" "$([ -e tests/a.acceptance.sh ] && echo kept || echo gone)" "gone"
check "clean: an emptied directory goes too" "$([ -e tests/dir ] && echo kept || echo gone)" "gone"
check "clean: a listed tracked edit is restored" "$(cat qa-edit.txt)" "one"
check "clean: an unlisted human edit keeps its content" "$(cat human.txt)" $'one\ntwo'
check "clean: an unlisted new file stays" "$(cat 'human new.txt')" "mine"
check "clean: a path dirty before QA stays" "$(cat dirty-before.txt)" "pre-existing"
check "clean: names what it left" "$(grep -c '^qa-files: left human.txt$' <<<"$out") $(grep -c '^qa-files: left human new.txt$' <<<"$out")" "1 1"
check "clean: names what it removed" "$(grep -c '^qa-files: removed ' <<<"$out")" "3"

# A path the auto run carried in is never cleaned, even when QA listed it.
bash "$QA" begin "$WS"
printf '{"active":true,"session":"s-qa","carried":["carried.txt"]}\n' > "$TMP/repo/.dforge/sdd/auto-run.json"
printf 'carried.txt\n' >> "$WS/qa-touched.txt"; printf 'mine\n' > carried.txt
out=$(CLAUDE_CODE_SESSION_ID=s-qa bash "$QA" clean "$WS")
check "clean: a carried path stays though QA listed it" "$(cat carried.txt):$(grep -c '^qa-files: left carried.txt$' <<<"$out")" "mine:1"
rm -f "$TMP/repo/.dforge/sdd/auto-run.json"

bash "$QA" begin "$WS"
check "a re-dispatch starts with an empty manifest" "$(wc -c < "$WS/qa-touched.txt" | tr -d ' ')" "0"
rm -f "$WS/qa-touched.txt"; printf 'z\n' > z.txt
out=$(bash "$QA" clean "$WS")
check "no manifest: nothing is cleaned" "$(cat z.txt):$(grep -c '^qa-files: left z.txt$' <<<"$out")" "z:1"
rm -f "$WS/qa-status-before.txt"
bash "$QA" clean "$WS" >/dev/null 2>&1; rc=$?
check "no snapshot: exit 2" "$rc" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

Add `'qa-files.test.sh': 20,` to `windowsSeconds` in `scripts/test-shards.mjs`.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 120 bash plugins/dforge/tests/qa-files.test.sh`
Expected: FAIL (no such script).

- [ ] **Step 3: Implement**

1. Create `scripts/qa-files` (C8): parse `git status --porcelain=v1 -z --untracked-files=all` records (a rename record carries a second path; take both), compare against the snapshot by path, read `scripts/auto-run carried` (ignore its failure), restore or delete, then remove each emptied parent directory up to the repository root. Paths with spaces and newlines must survive (`-z` throughout; the manifest is one path per line).
2. `final-review.md` step 0.5: (b) replaces "save the output of `git status --porcelain`" with `bash <plugin-root>/scripts/qa-files begin <workspace>` before every dispatch, the `rerun` re-dispatch included, and after the cut-off cleanup; the timer-first cleanup (`:163-168`) and the cut-off recovery (`:121-125`) become `qa-files clean <workspace>`, whose `left` lines the session names in its final-review message and in the `Ruling:` line (`Ruling: QA timed out — its listed files were removed; left: <paths> — none`).
3. `acceptance-qa.md`: before it writes, creates or deletes a path, QA appends that repository-relative path to `[WORKSPACE]/qa-touched.txt`; add that one append to "What you may read" and to `## Never`'s write rule.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 120 bash plugins/dforge/tests/qa-files.test.sh && timeout 120 node --test tests/test-shards.test.mjs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/qa-files plugins/dforge/reference/final-review.md plugins/dforge/reference/acceptance-qa.md scripts/test-shards.mjs plugins/dforge/tests/qa-files.test.sh
git commit -m "fix(dforge): clean up only the files QA listed"
```

### Task 14: Amendments beside the ledger

**Files:**
- Modify: `plugins/dforge/scripts/lib/plan.sh`
- Test: `plugins/dforge/tests/plan-lib.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: C7.

**Items:** 25
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 3 = 8
**Lenses:** silent-failures

- [ ] **Step 1: Write the failing test**

Append to `plugins/dforge/tests/plan-lib.test.sh`, inside its darkmem part (after `M=$(stores_home "$SH" "$SR" proj darkmem darkmem)`):

```bash
# --- amendments live beside the ledger (C7) ---
mkdir -p "$SR/docs" && printf '# P\n\n### Task 1: One\n' > "$SR/docs/am.md"
LD="$M/work/sdd/am"; WSD="$SR/.dforge/sdd/am"
mkdir -p "$LD" "$WSD"
printf '# SDD ledger — plan: docs/am.md\nTask 1: Ruling: amendment A1 — x — y\n' > "$LD/progress.md"
printf '## A1 — Task 1\n' > "$WSD/amendments.md"
(cd "$SR" && HOME=$SH plan_amendments_ready docs/am.md); rc=$?
check "ready: migrates the workspace file" "$rc:$([ -s "$LD/amendments.md" ] && echo moved):$([ -e "$WSD/amendments.md" ] && echo left || echo gone)" "0:moved:gone"
check "ready: logs the move once" "$(grep -c '^Ruling: amendments moved beside the ledger — none$' "$LD/progress.md")" "1"
check "file: the ledger directory's copy" "$(cd "$SR" && HOME=$SH plan_amendments_file docs/am.md)" "$LD/amendments.md"
printf 'Task 1: Ruling: amendment A2 — x — y\n' >> "$LD/progress.md"
err=$(cd "$SR" && HOME=$SH plan_amendments_ready docs/am.md 2>&1); rc=$?
check "ready: a cited amendment missing from the file exits 2" "$rc" "2"
check "ready: the message names it" "$(grep -c 'cites amendment A2, which .*amendments.md lacks' <<<"$err")" "1"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/plan-lib.test.sh`
Expected: FAIL (`plan_amendments_ready: command not found`).

- [ ] **Step 3: Implement**

1. `plan_amendments_file PLAN` (`plan.sh:356`): the C7 path through `dforge_ledger_dir`, keeping its "computed, not created" rule and its git-checkout guard.
2. Add `plan_amendments_ready PLAN` (C7). It calls `dforge_stores_init` in the caller's shell first; the move is a copy to a temporary name in the ledger directory, a rename, then removal of the workspace file; the ledger line is appended only when the ledger exists and does not already hold it. `<script>` is `basename "$0"`.
3. Update the header comments of both functions.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/plan-lib.test.sh && timeout 300 bash plugins/dforge/tests/plan-amend.test.sh`
Expected: PASS (with local progress the ledger directory is the workspace, so plan-amend's tests are unchanged).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/plan.sh plugins/dforge/tests/plan-lib.test.sh
git commit -m "fix(dforge): keep amendments beside the ledger"
```

### Task 15: Amendment consumers refuse missing entries

**Files:**
- Modify: `plugins/dforge/scripts/plan-amend`
- Modify: `plugins/dforge/scripts/task-brief`
- Modify: `plugins/dforge/scripts/task-step`
- Modify: `plugins/dforge/scripts/task-close`
- Modify: `plugins/dforge/scripts/plan-lint`
- Modify: `plugins/dforge/scripts/review-route`
- Modify: `plugins/dforge/scripts/lens-route`
- Modify: `plugins/dforge/scripts/depth-route`
- Modify: `plugins/dforge/reference/prompts/ruling-prompt.md`
- Test: `plugins/dforge/tests/task-open-close.test.sh`
- Test: `plugins/dforge/tests/plan-amend.test.sh`

**Interfaces:**
- Consumes: C7.
- Produces: none.

**Items:** 25
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6

Files 1: the eight scripts carry one decision, one `plan_amendments_ready "$plan"` call before their `plan_amendments_file` read, plus plan-amend's write path.

- [ ] **Step 1: Write the failing test**

Append to `plugins/dforge/tests/task-open-close.test.sh`, before its summary lines:

```bash
# --- every amendment consumer refuses a ledger citing a missing amendment (A4) ---
printf 'Task 1: Ruling: amendment A7 — x — y\n' >> "$LEDGER"
for argv in "task-brief|docs/plan.md|1" \
    "task-step|start|docs/plan.md|1" \
    "task-close|docs/plan.md|1|done: x; verified: y; remaining: none; discovered: none; assumptions: none" \
    "plan-lint|docs/plan.md" \
    "review-route|docs/plan.md|--task|1" \
    "lens-route|docs/plan.md|--task|1" \
    "depth-route|docs/plan.md"; do
  IFS='|' read -r -a a <<<"$argv"
  run bash "$P/scripts/${a[0]}" "${a[@]:1}"
  check "${a[0]}: a cited amendment missing exits 2" "$rc" "2"
  has "${a[0]}: the message names the script and the amendment" "$err" "${a[0]}: the ledger cites amendment A7"
done
sed -i '/amendment A7/d' "$LEDGER"
```

Append to `plugins/dforge/tests/plan-amend.test.sh`, before its summary lines:

```bash
# --- under darkmem progress the amendment lands beside the mirror ledger (C7) ---
. "$HERE/fixtures/darkmem-stores.sh"
DH="$TMP/dm-home"; mkdir -p "$DH"
DM=$(stores_home "$DH" "$REPO" proj local darkmem)
mkdir -p "$DM/work/sdd/plan"
printf '# SDD ledger — plan: docs/plan.md\n' > "$DM/work/sdd/plan/progress.md"
had=$(grep -c '^## A[0-9]* ' "$amendments")
entry b-dm.md '## A? — Task 1' 'Print `hello NAME`.' 'Print `hello NAME` once.'
out=$(HOME="$DH" bash "$AMEND" docs/plan.md b-dm.md 2>&1); status=$?
check "darkmem: append exits 0" "$status" "0"
check "darkmem: the workspace file was moved, not shadowed" "$([ -e "$amendments" ] && echo left || echo moved)" "moved"
check "darkmem: the ledger directory holds every entry" "$(grep -c '^## A[0-9]* ' "$DM/work/sdd/plan/amendments.md")" "$((had + 1))"
check "darkmem: the move is logged in the mirror ledger" "$(grep -c '^Ruling: amendments moved beside the ledger — none$' "$DM/work/sdd/plan/progress.md")" "1"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/task-open-close.test.sh; timeout 300 bash plugins/dforge/tests/plan-amend.test.sh`
Expected: FAIL on each `<script>: a cited amendment missing exits 2` check (Task 14 adds `plan_amendments_ready` but no consumer calls it yet) and on `darkmem: the workspace file was moved, not shadowed`.

- [ ] **Step 3: Implement**

1. In each of `task-brief`, `task-step` (both call sites, `:345` and `:480`), `task-close`, `plan-lint` (unless `--amendments` was given), `review-route`, `lens-route`, `depth-route`, call `plan_amendments_ready "$plan"` in the main shell, after `plan_locate` and before `plan_apply_amendments`.
2. `plan-amend`: write `amendments.md` in `dforge_ledger_dir <slug>` (creating the directory), calling `plan_amendments_ready` first so a workspace file is moved, not shadowed; update its header comment and `reference/prompts/ruling-prompt.md:130`'s `[AMENDMENTS_FILE]` to `<ledger dir>/amendments.md`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/task-open-close.test.sh && timeout 300 bash plugins/dforge/tests/plan-amend.test.sh && timeout 1200 bash plugins/dforge/tests/plan-lint.test.sh && timeout 300 bash plugins/dforge/tests/review-route.test.sh && timeout 300 bash plugins/dforge/tests/lens-route.test.sh && timeout 300 bash plugins/dforge/tests/depth-route.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts plugins/dforge/reference/prompts/ruling-prompt.md plugins/dforge/tests/task-open-close.test.sh plugins/dforge/tests/plan-amend.test.sh
git commit -m "fix(dforge): refuse a plan whose amendments went missing"
```

### Task 16: Amendments in the darkmem sync

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-mirror.mjs`
- Modify: `plugins/dforge/scripts/lib/darkmem-pull.mjs`
- Modify: `plugins/dforge/scripts/lib/darkmem-progress-move.mjs`
- Modify: `plugins/dforge/scripts/lib/darkmem-reconcile.mjs`
- Modify: `plugins/dforge/reference/project-state.md`
- Test: `plugins/dforge/tests/darkmem-sync/push.test.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`
- Test: `plugins/dforge/tests/darkmem-sync/pull.test.mjs`

**Interfaces:**
- Consumes: C7.
- Produces: none.

**Items:** 25
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 3 = 8
**Lenses:** silent-failures

Files 2: the four sync modules make one decision (a second per-plan file beside `handoff.md`), the reference and two tests.

- [ ] **Step 1: Write the failing test**

In `plugins/dforge/tests/darkmem-sync/push.test.mjs`, after `handoff notes go up as documents and are linked from their workstream`:

```js
test("a plan's amendments go up beside its handoff note (A3)", async t => {
  const s = await setup(t);
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "one\n" }] });
  write(path.join(s.workRoot, "sdd", "p1", "amendments.md"), "## A1 — Task 1\n");
  const result = await s.push();
  assert.equal(result.code, 0, result.stdout);
  assert.equal(s.stub.db.documents.get("proj\u0000dforge/amendments/p1.md").content, "## A1 — Task 1\n");
});
```

In `plugins/dforge/tests/darkmem-sync/reconcile-progress.test.mjs`, after `progress moves into darkmem from every checkout, and a second run does nothing`:

```js
test("a plan's amendments move into darkmem with its ledger (A3)", async t => {
  const s = await setup(t, "darkmem");
  write(path.join(s.repo, ".dforge", "sdd", "p1", "progress.md"), LEDGER("p1"));
  write(path.join(s.repo, ".dforge", "sdd", "p1", "amendments.md"), "## A1 — Task 1\n");
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to darkmem$/m);
  assert.equal(s.stub.db.documents.get("proj\u0000dforge/amendments/p1.md").content, "## A1 — Task 1\n");
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "amendments.md")), "## A1 — Task 1\n");
  assert.equal(s.state().documents["dforge/amendments/p1.md"], sha("## A1 — Task 1\n"));
  const [aside] = movedAside(s.repo);
  assert.equal(read(path.join(s.repo, ".dforge", aside, "sdd", "p1", "amendments.md")), "## A1 — Task 1\n");
  assert.equal(fs.existsSync(path.join(s.repo, ".dforge", "sdd", "p1", "amendments.md")), false);
});
```

After `progress moves back into the primary checkout from closed and open workstreams, and darkmem keeps its copy`:

```js
test("a plan's amendments move back into the checkout with its ledger (A3)", async t => {
  const s = await setup(t, "local");
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: LEDGER("p1") }] });
  await s.seed.putDocument({ project: "proj", uri: "dforge/amendments/p1.md", content: "## A1 — Task 1\n" });
  const result = await s.reconcile();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /^darkmem-sync reconcile: progress moved to local$/m);
  assert.equal(read(path.join(s.repo, ".dforge", "sdd", "p1", "amendments.md")), "## A1 — Task 1\n");
  assert.equal("dforge/amendments/p1.md" in s.state().documents, false);
  assert.equal(s.stub.db.documents.has("proj\u0000dforge/amendments/p1.md"), true, "darkmem keeps its copy");
});
```

In `plugins/dforge/tests/darkmem-sync/pull.test.mjs`, after `pull writes documents and handoff notes under the prefix, and records their hashes`:

```js
test("pull restores a plan's amendments beside its ledger (A3)", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/amendments/p1.md", content: "## A1 — Task 1\n" });
  const result = await s.pull();
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.equal(read(path.join(s.workRoot, "sdd", "p1", "amendments.md")), "## A1 — Task 1\n");
  assert.equal(fs.existsSync(path.join(s.docsRoot, "amendments")), false, "not filed as a document under the docs root");
  assert.equal(s.state().documents["dforge/amendments/p1.md"], sha("## A1 — Task 1\n"));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`
Expected: FAIL on the four `(A3)` tests.

- [ ] **Step 3: Implement**

1. `darkmem-mirror.mjs`: reserve `dforge/amendments/<slug>.md` in `uriToLocal` (`:40-50`) for `workRoot/sdd/<slug>/amendments.md` and its inverse; list it in `listDocumentFiles` (`:111-135`) and the per-plan directory filter (`:107`), and treat it like `handoff.md` at `:739`.
2. `darkmem-pull.mjs`: pull it to the same place. `darkmem-progress-move.mjs`: add an `amendments` kind beside `handoff` at `:155` and `:635`, moved in both directions. `darkmem-reconcile.mjs`: carry it wherever it carries `handoff.md`.
3. `project-state.md:99-100`: `amendments.md` now lives beside the ledger and follows progress into darkmem; review packages stay in the checkout.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib plugins/dforge/reference/project-state.md plugins/dforge/tests/darkmem-sync
git commit -m "fix(dforge): sync amendments with the ledger"
```

### Task 17: Review record and ci-mirror amendments

**Files:**
- Modify: `plugins/dforge/scripts/review-record`
- Modify: `plugins/dforge/scripts/ci-mirror`
- Test: `plugins/dforge/tests/review-record.test.sh`
- Test: `plugins/dforge/tests/ci-mirror.test.sh`

**Interfaces:**
- Consumes: C7.
- Produces: none.

**Items:** 25
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 0 = 5

- [ ] **Step 1: Write the failing test**

Append to `plugins/dforge/tests/ci-mirror.test.sh`, before its summary lines:

```bash
# --- an amended CI line is read (A5) ---
mkdir -p "$REPO/docs" && cp "$TMP/none.md" "$REPO/docs/amended.md"
mkdir -p "$REPO/.dforge/sdd/amended"
printf '## A1 — Header\n\nReason: x\nCost if wrong: y\n\n### Old\n\n````\n**CI:** none\n````\n\n### New\n\n````\n**CI:** none-amended\n````\n' > "$REPO/.dforge/sdd/amended/amendments.md"
mirror docs/amended.md
has "an amended CI line is the one read" "$out$err" "none-amended"
rm -rf "$REPO/.dforge/sdd/amended" "$REPO/docs/amended.md"

# --- a plan stored only in the darkmem docs mirror is found (A5) ---
. "$HERE/fixtures/darkmem-stores.sh"
DM=$(stores_home "$HOME" "$REPO" proj darkmem local)
mkdir -p "$DM/dforge/plans" && cp "$TMP/none.md" "$DM/dforge/plans/mp.md"
mirror docs/dforge/plans/mp.md
check "a mirror-only plan: exit 0" "$rc" "0"
check "a mirror-only plan: its CI line is read" "$out" "ci: none"
rm -f "$HOME/.dforge/stores.json" "$HOME/.dforge/config.json"
```

Append to `plugins/dforge/tests/review-record.test.sh`, after the `A9: a rerun leaves one record` check:

```bash
# --- amendments are kept in the record, after the review lines (A5) ---
printf '## A1 — Task 1\nReason: x\nCost if wrong: y\n' > "$WT/.dforge/sdd/2026-01-01-p/amendments.md"
out=$(cd "$TOP" && bash "$P/scripts/review-record" retain "$PLAN" --from "$WT"); rc=$?
check "amendments: retain exits 0" "$rc:$out" "0:$REVIEW"
check "amendments are kept in the record" "$(cat "$REVIEW" 2>/dev/null)" \
  "$want"$'\n\n## Amendments\n\n## A1 — Task 1\nReason: x\nCost if wrong: y'
rm -f "$WT/.dforge/sdd/2026-01-01-p/amendments.md"
(cd "$TOP" && bash "$P/scripts/review-record" retain "$PLAN" --from "$WT" >/dev/null)
check "amendments: none, no section" "$(cat "$REVIEW" 2>/dev/null)" "$want"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/ci-mirror.test.sh; timeout 300 bash plugins/dforge/tests/review-record.test.sh`
Expected: FAIL on `an amended CI line is the one read`, `a mirror-only plan: exit 0` and `amendments are kept in the record`.

- [ ] **Step 3: Implement**

1. `ci-mirror` (`:24-27`): `plan=$(plan_locate "$1")` (so a name resolves into the darkmem docs mirror, while a path outside the checkout, as the suite's `$TMP/*.md` cases pass, stays readable as today), `plan_amendments_ready "$plan"`, then read `**CI:**` from `plan_apply_amendments "$plan" "$(plan_amendments_file "$plan")"`; an amended value that is not `none` and not a CI line form is reported as today's malformed line.
2. `review-record`: when the plan's `amendments.md` (C7 path, in the `--from` checkout when given) is non-empty, append to the record a blank line, `## Amendments`, a blank line, then the file verbatim; with none, the record is unchanged. `REVIEW_LINES` (`:26`) keeps everything else as is.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/ci-mirror.test.sh && timeout 300 bash plugins/dforge/tests/review-record.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/review-record plugins/dforge/scripts/ci-mirror plugins/dforge/tests/review-record.test.sh plugins/dforge/tests/ci-mirror.test.sh
git commit -m "fix(dforge): read and keep plan amendments"
```

### Task 18: Plan identity and Codex task opening

**Files:**
- Modify: `plugins/dforge/scripts/task-brief`
- Modify: `plugins/dforge/scripts/task-close`
- Modify: `plugins/dforge/reference/native-codex.md`
- Test: `plugins/dforge/tests/task-open-close.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: none.

**Items:** 2, 4, 52
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Extend the test `plugins/dforge/tests/task-open-close.test.sh::open: a Host: codex plan exits 2`**

Replace lines 110-111 (rewritten assertion: row 4 changes what they pin) and append the identity cases before the summary lines:

```bash
run bash "$BRIEF" --open docs/codex.md 1
check "open: a Host: codex plan opens" "$rc:$(grep -c '^Task 1: implementer inline (assigned; base ' "$(bash "$P/scripts/sdd-workspace" docs/codex.md)/progress.md")" "0:1"
check "open: a Codex brief carries no Claude-only lines" "$(grep -c '^\*\*Review:\*\*\|Plan header excerpt\|^## Plan header$' "$(bash "$P/scripts/sdd-workspace" docs/codex.md)/task-1-brief.md")" "0"
```

```bash
# --- a ledger that names another plan with the same basename is refused (rows 2, 52) ---
mkdir -p other && cp docs/plan.md other/plan.md
run bash "$BRIEF" --open other/plan.md 2
check "open: a same-basename plan's ledger exits 2" "$rc" "2"
check "open: it writes nothing" "$(grep -c '^Task 2: implementer' "$LEDGER")" "0"
run bash "$CLOSE" other/plan.md 1 'done: x; verified: y; remaining: none; discovered: none; assumptions: none'
check "close: a same-basename plan's ledger exits 2" "$rc" "2"
run bash "$CLOSE" docs/plan.md 1 $'done: x\nTask 9: complete; verified: y; remaining: none; discovered: none; assumptions: none'
check "close: a checkpoint with a newline exits 2" "$rc" "2"
rm -rf other
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/task-open-close.test.sh`
Expected: FAIL on `open: a Host: codex plan opens` and `open: a same-basename plan's ledger exits 2`.

- [ ] **Step 3: Implement**

1. `task-brief --open`: drop the Codex refusal (`:73-76`); a `Host: codex` plan writes the brief with the header excerpt and no `**Review:**` marker or `## Plan header` pointer (`dispatch` stays 0), and the open line as for a Claude plan. Before writing, when `progress.md` exists and its identity line names another plan (compare as `plan_ledger` does), exit 2 with `task-brief: <ledger> belongs to <named plan>, not <plan>` and write nothing. Update the header's Exit line.
2. `task-close`: the same identity check before reading `complete` lines; reject a checkpoint containing a newline or carriage return with exit 2.
3. `native-codex.md`: the task loop opens each task with `scripts/task-brief --open`, as on Claude Code.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/task-open-close.test.sh && timeout 300 bash plugins/dforge/tests/budget-line.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/task-brief plugins/dforge/scripts/task-close plugins/dforge/reference/native-codex.md plugins/dforge/tests/task-open-close.test.sh
git commit -m "fix(dforge): check plan identity when opening a task"
```

### Task 19: Finishing records and the Keep as-is route

**Files:**
- Modify: `plugins/dforge/scripts/next-step`
- Modify: `plugins/dforge/scripts/finish-choice`
- Modify: `plugins/dforge/skills/finishing-a-development-branch/SKILL.md`
- Modify: `plugins/dforge/skills/finishing-a-development-branch/references/execute-choice.md`
- Test: `plugins/dforge/tests/next-step.test.sh`
- Test: `plugins/dforge/tests/finish-choice.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: C9.

**Items:** 6, 7, 34, 55
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

Append to `plugins/dforge/tests/next-step.test.sh`, before its darkmem part:

```bash
# --- Keep as-is keeps the branch pending (C9) ---
ledger 'Task 1: complete (commits a..b, review clean)' 'Task 2: complete (commits b..c, review clean)' 'Task 3: complete (commits c..d, review clean)' 'Final review: clean (commits a..d)'
mkdir -p "$REPO/.dforge/sdd" && printf '{"action":"pr"}\n' > "$REPO/.dforge/sdd/finish.json"
run "$REPO" --kept "$PLAN_REL"
check "kept: exits 0" "$status" "0"
has "kept: names the branch" "$out" "$(git -C "$REPO" branch --show-current)"
lacks "kept: never says complete" "$out" "is complete"
has "kept: the finish choices stay open" "$out" "merge, pr or discard"
check "kept: the no-plan finish record is cleared" "$([ -e "$REPO/.dforge/sdd/finish.json" ] && echo kept || echo gone)" "gone"
```

Append to `plugins/dforge/tests/finish-choice.test.sh`, before its summary lines:

```bash
# --- answer with nothing recorded creates the record (row 55) ---
rm -f .dforge/sdd/finish.json
FINISH_CHOICE_NOW=$T0 fc answer keep >/dev/null 2>&1; rc=$?
check "answer: no record still succeeds" "$rc:$(jq -r .answer .dforge/sdd/finish.json)" "0:keep"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 700 bash plugins/dforge/tests/next-step.test.sh; timeout 300 bash plugins/dforge/tests/finish-choice.test.sh`
Expected: FAIL on `kept: exits 0` and `answer: no record still succeeds`.

- [ ] **Step 3: Implement**

1. `next-step`: add `--kept PLAN_FILE` (C9) to the usage and argument parsing; it writes `latest.md` as `--complete` does (wholesale) with the C9 block, its launch command the plan's Execution launch and its prompt `Finish \`<plan>\` with dforge:finishing-a-development-branch: the branch <branch> in <worktree> is kept unintegrated.`; `--complete`, `--kept` and `--adhoc` remove the primary checkout's `.dforge/sdd/finish.json` after writing the block.
2. `finish-choice answer`: with no record, create `{action: ACTION, base: null, chosenAt: now, source: "answer", answer: ACTION, answeredAt: now}`.
3. Finishing `SKILL.md` Step 7: after Option 3 run `next-step --kept PLAN_FILE`; Step 5b's table and `execute-choice.md` Option 2: while documents live in darkmem, write and sync Step 5b's records (index line, register rows, roadmap settle, review record) only after `git push` and the PR creation both succeed; with local documents the commit stays before the push (R10).

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 700 bash plugins/dforge/tests/next-step.test.sh && timeout 300 bash plugins/dforge/tests/finish-choice.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/next-step plugins/dforge/scripts/finish-choice plugins/dforge/skills/finishing-a-development-branch plugins/dforge/tests/next-step.test.sh plugins/dforge/tests/finish-choice.test.sh
git commit -m "fix(dforge): route Keep as-is and late PR records"
```

### Task 20: Auto-run hygiene

**Files:**
- Modify: `plugins/dforge/scripts/lib/auto-run.sh`
- Modify: `plugins/dforge/scripts/auto-run`
- Modify: `plugins/dforge/skills/resume-execution/SKILL.md`
- Test: `plugins/dforge/tests/auto-run.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: `auto-run stop --stale`, read by Task 30.

**Items:** 32, 33, 54
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Append to `plugins/dforge/tests/auto-run.test.sh`, before its final block (the one that checks every suite sets both session variables):

```bash
# --- start --register fills an empty Covers (row 54) ---
mkdir -p "$REPO/docs"
printf '# Register\n\n**Source:** a review\n**Covers:** -\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n' > "$REPO/docs/r-covers.md"
ar --session s-1 start --spec "$SPEC" --register docs/r-covers.md --force >/dev/null
check "start --register fills an empty Covers" "$(grep -c "^\*\*Covers:\*\* $SPEC$" "$REPO/docs/r-covers.md")" "1"
# --- clear checks whose prompt it stores (row 32) ---
ar --session s-1 attach --plan docs/plan.md
mkdir -p "$REPO/.dforge/handoff"
printf '# Handoff\n\n## Next session\n\nPaste as the first prompt:\n\n```\nResume `docs/other.md` with dforge:resume-execution.\n```\n' > "$REPO/.dforge/handoff/latest.md"
pending_before=$(field pending) resumes_before=$(field resumes)
ar --session s-1 clear >/dev/null 2>&1; status=$?
check "clear: another plan's prompt is refused, nothing booked" "$status:$(field pending):$(field resumes)" "4:$pending_before:$resumes_before"
# --- stop --stale (row 33) ---
ar --session s-2 stop --stale >/dev/null 2>&1; status=$?
check "stop --stale: refused while the owner lives" "$status:$(field active)" "3:true"
beat s-1 100000
ar --session s-2 stop --stale >/dev/null 2>&1; status=$?
check "stop --stale: a dead owner's run stops" "$status:$(field active)" "0:false"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 700 bash plugins/dforge/tests/auto-run.test.sh`
Expected: FAIL on `start --register fills an empty Covers`, `clear: another plan's prompt is refused, nothing booked` and `stop --stale: a dead owner's run stops`.

- [ ] **Step 3: Implement**

1. `ar_clear`: after `ar_handoff` and before the resume count changes, apply `ar_switch`'s check (`[[ $AR_PROMPT == *"$(basename "$plan")"* ]]`, exit 4 with its message) when a plan is attached.
2. `auto-run stop --stale`: skip the binding check when `ar_is_stale` holds, stop the run with reason `owner session <id> is gone`, print its pending decisions and rulings; exit 3 while the owner is live.
3. `auto-run start --register FILE`: set `**Covers:**` to the spec when it is `-` (`register.sh` already edits that line for auto-run's own register, `auto-run.sh:200`).
4. resume-execution `SKILL.md`: when `auto-run status` names a run whose owner is stale, run `auto-run stop --stale` and read what it lists before resuming.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 700 bash plugins/dforge/tests/auto-run.test.sh && timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/auto-run.sh plugins/dforge/scripts/auto-run plugins/dforge/skills/resume-execution/SKILL.md plugins/dforge/tests/auto-run.test.sh
git commit -m "fix(dforge): guard auto-run clear and stop stale runs"
```

### Task 21: Session start: missing Node and sync bound

**Files:**
- Modify: `plugins/dforge/scripts/lib/roots.sh`
- Modify: `plugins/dforge/scripts/session-start.sh`
- Modify: `plugins/dforge/scripts/lib/darkmem-hook.sh`
- Test: `plugins/dforge/tests/roots.test.sh`
- Test: `plugins/dforge/tests/hook.test.sh`
- Test: `plugins/dforge/tests/darkmem-sync/hooks.test.mjs`

**Interfaces:**
- Consumes: none.
- Produces: none.

**Items:** 15, 41
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 0 - risk 2 = 6

- [ ] **Step 1: Write the failing test**

The no-node cases take node away by dropping every PATH directory that holds `node` (or `node.exe`), never by linking tools into a bare directory: a copied `git.exe` or `bash.exe` on Git Bash loses its DLLs, and a uutils multicall binary picks its tool from its name. Where node shares a directory with git or jq the cases print a `skip` line; locally (nvm) and on both CI platforms (`actions/setup-node`) node has a directory of its own.

Append to `plugins/dforge/tests/roots.test.sh`, before its summary lines:

```bash
# --- no node while darkmem is applied: exit 2, never local (row 15) ---
nonode_path() { # PATH without the directories that hold node
  local d out='' IFS=:
  for d in $PATH; do [ -x "$d/node" ] || [ -x "$d/node.exe" ] || out=${out:+$out:}$d; done
  printf '%s\n' "$out"
}
NONODE_PATH=$(nonode_path)
if PATH="$NONODE_PATH" command -v node >/dev/null 2>&1 || ! PATH="$NONODE_PATH" command -v git >/dev/null 2>&1 \
   || ! PATH="$NONODE_PATH" command -v jq >/dev/null 2>&1; then
  printf 'skip - no node: node shares a PATH directory with git or jq here\n'
else
  stores_home "$HOME" "$REPO" superpowers local darkmem > /dev/null
  out=$(cd "$REPO" && _DFORGE_KEY= PATH="$NONODE_PATH" dforge_ledger_dir p1 2>&1); rc=$?
  check "no node, progress applied darkmem: exit 2" "$rc" "2"
  check "the message names node" "$(grep -c 'roots.sh: node is required while darkmem stores are applied' <<<"$out")" "1"
  rm -f "$HOME/.dforge/stores.json"
  check "no node, nothing applied: still local" "$(cd "$REPO" && _DFORGE_KEY= PATH="$NONODE_PATH" dforge_ledger_dir p1)" "$TOP/.dforge/sdd/p1"
fi
```

Append to `plugins/dforge/tests/hook.test.sh`, before its summary lines:

```bash
# --- no node while darkmem is applied: one warning per session (row 15, A13) ---
. "$HERE/fixtures/darkmem-stores.sh"
nonode_path() { # PATH without the directories that hold node
  local d out='' IFS=:
  for d in $PATH; do [ -x "$d/node" ] || [ -x "$d/node.exe" ] || out=${out:+$out:}$d; done
  printf '%s\n' "$out"
}
NN_PATH=$(nonode_path)
NN_REPO="$TMP/nn-repo"; git init -q "$NN_REPO"
HOME_N="$TMP/nn-home"; mkdir -p "$HOME_N"
stores_home "$HOME_N" "$NN_REPO" proj local darkmem > /dev/null
nn_ctx() { # nn_ctx <source> — the additionalContext of one start of session s-nn
  MSYS_NO_PATHCONV=1 jq -n --arg cwd "$NN_REPO" --arg src "$1" \
    '{hook_event_name:"SessionStart",session_id:"s-nn",transcript_path:"",cwd:$cwd,source:$src}' \
    | HOME="$HOME_N" PATH="$NN_PATH" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""'
}
if PATH="$NN_PATH" command -v node >/dev/null 2>&1 || ! PATH="$NN_PATH" command -v git >/dev/null 2>&1 \
   || ! PATH="$NN_PATH" command -v jq >/dev/null 2>&1; then
  printf 'skip - no node at session start: node shares a PATH directory with git or jq here\n'
else
  check "no node: the first start warns once" "$(nn_ctx startup | grep -c 'node is required while darkmem stores are applied')" "1"
  check "no node: a later start of the same session does not repeat it" "$(nn_ctx resume | grep -c 'node is required while darkmem stores are applied')" "0"
fi
```

Add to `plugins/dforge/tests/darkmem-sync/hooks.test.mjs`, after the test `session lines skip the sync, and say so, when too little of the hook's time is left`:

```js
test("a session-start sync that overruns its step bound is one line naming the command", async t => {
  const s = await setup(t);
  const shim = scratch("dmh-slow-");
  const realNode = process.execPath.replace(/\\/g, "/");
  fs.writeFileSync(path.join(shim, "node"),
    `#!/usr/bin/env bash\ncase " $* " in *"darkmem-sync.mjs reconcile "*) exec sleep 60 ;; esac\nexec "${realNode}" "$@"\n`,
    { mode: 0o755 });
  const key = Object.keys(s.env).find(k => k.toUpperCase() === "PATH") ?? "PATH";
  const env = { ...s.env, [key]: shim + path.delimiter + (s.env[key] ?? ""), DARKMEM_SESSION_STEP_SECONDS: "2", DARKMEM_KILL_GRACE: "1" };
  const started = Date.now();
  const result = await sessionLines(s.repo, "sid-hook", env);
  assert.equal(result.code, 0, result.stderr);
  assert.match(result.stdout, /^darkmem-sync did not finish at session start; run darkmem-sync reconcile by its plugin-root path$/m);
  assert.ok(Date.now() - started < 30000, "the overrun ended at the step bound, not the reconcile's own end");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/roots.test.sh; timeout 300 bash plugins/dforge/tests/hook.test.sh; timeout 600 node --test plugins/dforge/tests/darkmem-sync/hooks.test.mjs`
Expected: FAIL on `no node, progress applied darkmem: exit 2`, `no node: the first start warns once` and the overrun test (or `skip` lines for the two bash cases where node shares a directory).

- [ ] **Step 3: Implement**

1. `dforge_stores_init` (`roots.sh:74`): split the node test out; when node is missing and `stores.json` records `documents` or `progress` as `darkmem` for this checkout's primary root (read with jq; without jq, any entry), print `roots.sh: node is required while darkmem stores are applied` to stderr and exit 2. Update the comment at `:48-50`.
2. Hooks that already wrap the roots call in `$(…) ||` pass silently. `session-start.sh` adds the line `dforge: node is required while darkmem stores are applied; install Node or set the stores local` to its context once per session: it writes a marker `<turn stamp>.nonode` (the stamp path `scripts/turn-start.sh` builds, `~/.claude/dforge/sessions/turns/<sanitised sid>`) and adds the line only while the marker is absent.
3. `darkmem_session_lines`: bound reconcile and pull at `${DARKMEM_SESSION_STEP_SECONDS:-20}` seconds each (each still capped by the time the hook has left, as today), with `DARKMEM_SYNC_LOCK_WAIT_MS=10000`, below the step bound (spec ruling R18). An overrun is `_darkmem_run` exiting 124 (GNU timeout), 143 or 137 (the watchdog's TERM or KILL); on one, print `darkmem-sync did not finish at session start; run darkmem-sync <reconcile|pull> by its plugin-root path`, naming the step that overran. Update the comment at `:91-96`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/roots.test.sh && timeout 300 bash plugins/dforge/tests/hook.test.sh && timeout 600 node --test plugins/dforge/tests/darkmem-sync/hooks.test.mjs && timeout 600 bash plugins/dforge/tests/darkmem-sync.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/roots.sh plugins/dforge/scripts/session-start.sh plugins/dforge/scripts/lib/darkmem-hook.sh plugins/dforge/tests/roots.test.sh plugins/dforge/tests/hook.test.sh plugins/dforge/tests/darkmem-sync/hooks.test.mjs
git commit -m "fix(dforge): refuse local stores without node"
```

### Task 22: Suite baselines, suite-run HEAD and task-step cwd

**Files:**
- Modify: `plugins/dforge/scripts/task-step`
- Modify: `plugins/dforge/scripts/suite-run`
- Test: `plugins/dforge/tests/task-step-base.test.sh`
- Test: `plugins/dforge/tests/suite-run.test.sh`
- Test: `plugins/dforge/tests/task-step.test.sh`
- Test: `plugins/dforge/tests/task-step-settle.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: none.

**Items:** 8, 9, 10, 56, 57
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 0 - risk 2 = 6

- [ ] **Step 1: Write the failing test**

In `plugins/dforge/tests/task-step-base.test.sh`, rewrite three checks (rewritten assertions: row 8 changes what they pin):

```bash
check "task 10: an unnamed failure at base and head counts as new" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: red (1 failing, 0 baseline)"
```

in place of line 297 (`task 10: a red base row without test lines excuses the head`),

```bash
check "task 11: an unnamed failure at base and head counts as new" "$rc $(grep '^suite: ' <<<"$out")" "0 suite: red (1 failing, 0 baseline)"
check "task 11: the base failures hold the exit code, marked unnamed" "$(grep -cE '^command exit 1 \(unnamed [0-9]+-[0-9]+\)$' "$WS/task-11-base-failures.txt")" "1"
```

in place of lines 309-310. In the same file, change the fixture line 268 so the Worktree setup carries a trailing note (row 57; the later base runs, Tasks 9 to 12, fail without the setup):

```bash
sed 's/^\(\*\*Worktree setup:\*\* \).*$/\1`touch setup.done` — the marker the suite reads/' "$REPO/docs/plan.md" > "$REPO/docs/plan.tmp" && mv "$REPO/docs/plan.tmp" "$REPO/docs/plan.md"
```

In `plugins/dforge/tests/task-step-settle.test.sh`, change the fixture header line 238 to `` |**Integration check:** `bash mark.sh integ 0` — the full suite `` (row 57): the existing check that settles `baseline bash mark.sh integ 0` as a named command then pins the first-code-span rule.

Append to `plugins/dforge/tests/suite-run.test.sh`, before its summary lines:

```bash
# --- a HEAD that moved during the run records no reusable row (row 9) ---
printf '#!/usr/bin/env bash\ngit -C "%s" commit -q --allow-empty -m moved\n' "$REPO" > "$TMP/mover.sh"
run -- bash "$TMP/mover.sh"
check "a moved HEAD is recorded dirty" "$(field 2)" "dirty"
# --- a failed git status counts as dirty (row 10) ---
mv "$REPO/.git/index" "$REPO/.git/index.bak"; printf 'garbage' > "$REPO/.git/index"
probe 0 "$TMP/out-tap-pass"
check "a failed git status is not clean" "$(field 2)" "dirty"
mv "$REPO/.git/index.bak" "$REPO/.git/index"
```

In `plugins/dforge/tests/task-step.test.sh`, after the `review: --cwd names the panel's working directory` case and its `git worktree remove` line:

```bash
# --- --cwd's checkout answers every git question (row 56) ---
state_keep=$(cat "$WS/task-1-step.json")
git worktree add -q --detach "$TMP/wt-cwd" HEAD
git -C "$TMP/wt-cwd" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m "only in the worktree"
step review docs/plan.md 1 --cwd "$TMP/wt-cwd"
check "review: the review head is --cwd's HEAD" "$rc:$(jq -r '.reviewHead' "$WS/task-1-step.json" | tr -d '\r')" "0:$(git -C "$TMP/wt-cwd" rev-parse HEAD)"
git worktree remove --force "$TMP/wt-cwd"
printf '%s\n' "$state_keep" > "$WS/task-1-step.json"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 1200 bash plugins/dforge/tests/task-step-base.test.sh; timeout 300 bash plugins/dforge/tests/suite-run.test.sh; timeout 900 bash plugins/dforge/tests/task-step.test.sh; timeout 600 bash plugins/dforge/tests/task-step-settle.test.sh`
Expected: FAIL on the rewritten Task 10 and 11 checks, the Task 9 base checks (the setup no longer runs), both suite-run checks, `review: the review head is --cwd's HEAD`, and the settle check for `baseline bash mark.sh integ 0`.

- [ ] **Step 3: Implement**

1. `task-step` `suite_fail_set` (`:107-111`): an unnamed failure prints `command exit <CODE> (unnamed <epoch>-<pid>)`, which never equals a base line; update its comment. `plan_named_commands` (`:908`) and `run_at_base`'s setup (`:156`) take the first code span the way `task-brief`'s `check_command` does. Every git call after `top` is set (`:642-653` and later) runs `git -C "$top"`.
2. `suite-run`: `is_clean` captures git's status and returns 1 when `git status` fails; after the run, read HEAD again and record the row as `dirty` when it differs from `head`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 1200 bash plugins/dforge/tests/task-step-base.test.sh && timeout 300 bash plugins/dforge/tests/suite-run.test.sh && timeout 900 bash plugins/dforge/tests/task-step.test.sh && timeout 600 bash plugins/dforge/tests/task-step-settle.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/task-step plugins/dforge/scripts/suite-run plugins/dforge/tests/task-step-base.test.sh plugins/dforge/tests/suite-run.test.sh plugins/dforge/tests/task-step.test.sh plugins/dforge/tests/task-step-settle.test.sh
git commit -m "fix(dforge): never excuse or reuse unproven suite runs"
```

### Task 23: with-timeout and bounded agy version

**Files:**
- Create: `plugins/dforge/scripts/with-timeout`
- Modify: `plugins/dforge/scripts/agy-locate`
- Modify: `plugins/dforge/reference/final-review.md`
- Modify: `plugins/dforge/skills/finishing-a-development-branch/references/ui-proof.md`
- Modify: `plugins/dforge/reference/acceptance-qa.md`
- Modify: `scripts/test-shards.mjs`
- Test: `plugins/dforge/tests/with-timeout.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: C10.

**Items:** 11, 35
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 2 - coupling 0 - risk 1 = 5

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/with-timeout.test.sh`:

```bash
#!/usr/bin/env bash
# scripts/with-timeout and agy-locate on a host with only gtimeout.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="$HERE/../scripts"
pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
# A script that execs the tool by its absolute path, never a link or a copy:
# Git Bash's ln -s copies, and a copied .exe loses its DLLs; a uutils
# multicall binary picks its tool from the name it is run under.
wrap() { # wrap <name> <target>
  printf '#!%s\nexec "%s" "$@"\n' "$BASH" "$2" > "$BIN/$1"; chmod +x "$BIN/$1"
}
for t in env sleep true cat head tr dirname basename jq sed grep; do wrap "$t" "$(command -v "$t")"; done
wrap gtimeout "$(command -v timeout)"
PATH="$BIN" "$BASH" "$S/with-timeout" 5 true; rc=$?
check "only gtimeout: a quick command exits 0" "$rc" "0"
PATH="$BIN" "$BASH" "$S/with-timeout" 1 sleep 5; rc=$?
check "only gtimeout: the bound exits 124" "$rc" "124"
rm -f "$BIN/gtimeout"
out=$(PATH="$BIN" "$BASH" "$S/with-timeout" 5 true 2>&1); rc=$?
check "no timeout command: exit 125" "$rc:$out" "125:with-timeout: no timeout command (timeout or gtimeout) on PATH"
printf '#!%s\nsleep 60\n' "$BASH" > "$BIN/agy"; chmod +x "$BIN/agy"
out=$(timeout 30 env PATH="$BIN" "$BASH" "$S/agy-locate"); rc=$?
check "agy-locate: no timeout command reports the CLI unusable" "$rc:$out" "1:agy-locate off reason=no-timeout-command"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

Add `'with-timeout.test.sh': 20,` to `windowsSeconds` in `scripts/test-shards.mjs`.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 120 bash plugins/dforge/tests/with-timeout.test.sh`
Expected: FAIL (no such script).

- [ ] **Step 3: Implement**

1. Create `scripts/with-timeout` (C10) on `lib/timeout.sh`'s `dforge_timeout`.
2. `agy-locate` (`:29-33`): source `lib/timeout.sh`; run `"$DFORGE_TIMEOUT" 20 "$agy" --version`; with no timeout command, `off no-timeout-command`.
3. `final-review.md` step 0.2 (`:100-105`), finishing `references/ui-proof.md` (`:3-4`) and `acceptance-qa.md` step 3 name `bash <plugin-root>/scripts/with-timeout <seconds> <command>` instead of a literal `timeout`, and say exit 125 means no timeout command is installed.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 120 bash plugins/dforge/tests/with-timeout.test.sh && timeout 300 bash plugins/dforge/tests/agy-gate.test.sh && timeout 120 node --test tests/test-shards.test.mjs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/with-timeout plugins/dforge/scripts/agy-locate plugins/dforge/reference plugins/dforge/skills/finishing-a-development-branch/references/ui-proof.md scripts/test-shards.mjs plugins/dforge/tests/with-timeout.test.sh
git commit -m "fix(dforge): bound commands where only gtimeout exists"
```

### Task 24: Review panel process trees

**Files:**
- Modify: `plugins/dforge/scripts/run-review-panel`
- Test: `plugins/dforge/tests/review-panel.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: none.

**Items:** 58
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 2 - coupling 0 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

Append to `plugins/dforge/tests/review-panel.test.sh`, before its summary lines:

```bash
# --- without setsid, a timed-out runner leaves no descendant (row 58) ---
# The grandchild is the case today's walk misses: it signals a child before
# listing that child's children, which are reparented once it dies.
cat > "$TMP/tree-runner" <<EOF
#!/usr/bin/env bash
( sleep 300 & printf '%s\n' \$! >> "$TMP/tree-pids"; printf '%s\n' \$! >> "$TMP/children"; wait ) &
printf '%s\n' \$! >> "$TMP/tree-pids"; printf '%s\n' \$! >> "$TMP/children"
wait
EOF
chmod +x "$TMP/tree-runner"
if command -v pgrep >/dev/null 2>&1; then
  : > "$TMP/tree-pids"
  PANEL_NO_SETSID=1 PANEL_BOUND_SECONDS=3 PANEL_AGY_RUNNER="$TMP/tree-runner" panel --kind task --tier light --prompt "$TMP/prompt.md"
  check "no setsid: the timed-out runner is reported as TIMEOUT" "$(head -1 <<<"$out" | grep -c 'status=TIMEOUT')" "1"
  alive=0; while read -r p; do kill -0 "$p" 2>/dev/null && alive=$((alive + 1)); done < "$TMP/tree-pids"
  check "no setsid: no child or grandchild survives the timeout" "$alive:$(wc -l < "$TMP/tree-pids" | tr -d ' ')" "0:2"
else
  printf 'skip - no setsid tree walk: pgrep is not on PATH (Git Bash)\n'
fi
```

Add `PANEL_NO_SETSID` to the `# Env seams:` comment in `run-review-panel` (`:19-21`) beside `PANEL_BOUND_SECONDS`.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/review-panel.test.sh`
Expected: FAIL on `no setsid: no child or grandchild survives the timeout`.

- [ ] **Step 3: Implement**

1. `stop_runner` (`:142-156`): without setsid, walk the whole tree with `pgrep -P` first, collecting every pid, then send the signal to all of them, deepest first; after the KILL pass (`:196`), check every collected pid with `kill -0` and KILL survivors once more. `PANEL_NO_SETSID=1` sets `have_setsid=false` (`:135`), so both the launch (`:174`) and `stop_runner` take the no-setsid path.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/review-panel.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/run-review-panel plugins/dforge/tests/review-panel.test.sh
git commit -m "fix(dforge): reap the whole runner tree without setsid"
```

### Task 25: UI-proof screenshot evidence

**Files:**
- Modify: `plugins/dforge/scripts/ui-proof`
- Modify: `plugins/dforge/skills/ui-ux/references/walkthrough.md`
- Test: `plugins/dforge/tests/ui-proof.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: none.

**Items:** 27
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 2 - coupling 0 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

Append to `plugins/dforge/tests/ui-proof.test.sh`, before its summary lines, a darkmem case: source `fixtures/darkmem-stores.sh`, `M=$(stores_home "$HOME" "$REPO" proj darkmem local)`, put a screenshot at `$M/dforge/ui-ux/proofs/a.png`, and check that `try '| UX-1 | pass | docs/dforge/ui-ux/proofs/a.png | ok |'` prints `0` (a docs name resolves through `dforge_resolve`), then remove the config and `stores.json`.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/ui-proof.test.sh`
Expected: FAIL on the darkmem case.

- [ ] **Step 3: Implement**

1. `ui-proof` (`:151`): accept an image path when `$root/$item`, `$item` or `dforge_resolve "$item"` exists.
2. `walkthrough.md` (`:108`): while documents live in darkmem, screenshots are `**Evidence:** local` under the checkout's `.dforge/ui-proofs/` and cited from there; a profile's `**Screenshots:** commit` is not honoured then, said in one line.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/ui-proof.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/ui-proof plugins/dforge/skills/ui-ux/references/walkthrough.md plugins/dforge/tests/ui-proof.test.sh
git commit -m "fix(dforge): resolve proof screenshots through the store"
```

### Task 26: Judge tools, QA persona and stop gate

**Files:**
- Modify: `plugins/dforge/agents/judge-opus.md`
- Modify: `plugins/dforge/agents/judge-sonnet-high.md`
- Modify: `plugins/dforge/agents/judge-fable.md`
- Modify: `plugins/dforge/agents/impl-sonnet-high.md`
- Modify: `plugins/dforge/scripts/impl-stop-gate`
- Modify: `plugins/dforge/reference/acceptance-qa.md`
- Test: `plugins/dforge/tests/fleet.test.sh`
- Test: `plugins/dforge/tests/impl-stop-gate.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: C11.

**Items:** 36, 53
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 0 - risk 2 = 6

Files 2: the three judge files are one shape.

- [ ] **Step 1: Write the failing test**

`plugins/dforge/tests/fleet.test.sh:29` (rewritten assertion: row 36): `JUDGE_TOOLS="Read, Grep, Glob, Write"`.

In `plugins/dforge/tests/impl-stop-gate.test.sh`, replace the cases built on `DONE` and the `**Status:**` contract (rewritten assertions: row 53) with:

```bash
printf '## Verdict\npass: 1\n' > "$R"
gate "$(input dforge:impl-sonnet-high q-1 "QA done: 1 pass.
Report: $R")"
check "a QA report that opens with ## Verdict passes" "$CODE|$OUT|$ERR" "0||"
gate "$(input dforge:impl-sonnet-high q-2 "QA done.
Report: $TMP/missing.md")"
check "a missing QA report blocks" "$CODE:$(has "$ERR" 'does not exist')" "2:1"
printf '# Notes\n## Verdict\n' > "$R"
gate "$(input dforge:impl-sonnet-high q-3 "QA done.
Report: $R")"
check "a report that does not open with ## Verdict blocks" "$CODE:$(has "$ERR" '## Verdict')" "2:1"
gate "$(input dforge:impl-sonnet-high w-1 'Walkthrough done; screenshots saved.')"
check "a reply with no Report line passes" "$CODE|$OUT|$ERR" "0||"
```

Keep the counter cases (two blocks per agent, five fires, the fallback log), rebuilt on the missing-report reply.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 120 bash plugins/dforge/tests/fleet.test.sh; timeout 300 bash plugins/dforge/tests/impl-stop-gate.test.sh`
Expected: FAIL on the judge tools check and `a missing QA report blocks`.

- [ ] **Step 3: Implement**

1. Drop `WebFetch` from the three judge agents' `tools:` lines.
2. `impl-sonnet-high.md`: describe Acceptance QA and walkthrough dispatches only (follow the dispatch prompt, end QA replies with `Report: <absolute path>`), with no task brief, escalation ladder or BLOCKED status; keep the general-solution, no-test-gaming and report-honesty paragraphs.
3. `impl-stop-gate`: C11; remove the `**Status:**` and `## Verified`/`## Assumptions made` checks; the block message (`:141`) says `Fix it, then end your reply again with its Report: line.`; keep the counter, pass-through and fallback-log logic; rewrite the header comment.
4. `acceptance-qa.md`'s reply paragraph ends with the `Report: <absolute path>` line.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 120 bash plugins/dforge/tests/fleet.test.sh && timeout 300 bash plugins/dforge/tests/impl-stop-gate.test.sh && timeout 300 bash plugins/dforge/tests/seats.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/agents plugins/dforge/scripts/impl-stop-gate plugins/dforge/reference/acceptance-qa.md plugins/dforge/tests/fleet.test.sh plugins/dforge/tests/impl-stop-gate.test.sh
git commit -m "fix(dforge): retarget the stop gate to the QA report"
```

### Task 27: Codex workflow line and native-codex.md

**Files:**
- Modify: `plugins/dforge/scripts/lib/dforge-config.mjs`
- Modify: `plugins/dforge/reference/native-codex.md`
- Modify: `plugins/dforge/skills/brainstorming/SKILL.md`
- Test: `plugins/dforge/tests/dforge-config.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: C12.

**Items:** 23, 26
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 2 - coupling 0 - risk 1 = 5

- [ ] **Step 1: Write the failing test**

Append to `plugins/dforge/tests/dforge-config.test.sh`, after the workflow cases (`:96-106`):

```bash
fresh codexwf
fc set designApproval whole >/dev/null; fc set specReview false >/dev/null
check "workflow --host codex keeps overrides under autoRun=on" "$(fc workflow --host codex)" \
  "dforge settings in force (each replaces the matching question or default in the skills): designApproval=whole; specReview=false"
check "workflow on Claude still leaves them out" "$(fc workflow)" ""
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: FAIL on `workflow --host codex keeps overrides under autoRun=on`.

- [ ] **Step 3: Implement**

1. `workflowLine(env, host = 'claude')` (C12) and `main`'s `workflow [--host claude|codex]` (USAGE too); the `inertWhen` filter skips a key whose `inertWhen.key` is `autoRun` when host is `codex`.
2. brainstorming `SKILL.md:89-93`: a Codex session runs `scripts/dforge-config workflow --host codex`.
3. `native-codex.md`: rewrite for inline execution — one judge per risk-3 review (drop "three independent evaluations", `:292-293`); delete the implementer selector, escalation, reserve tiers and one-time split (`:183-250`) and "Resume the recorded implementer for fix rounds" (`:282-285`); the manual lens routing (`:303-321`) applies lens-route's depth gating (`light` runs security only, `standard` at most 2 others) and the `lensMinorFrom` floor; name `workflow --host codex`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/dforge-config.test.sh && timeout 300 bash plugins/dforge/tests/native-routing.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/dforge-config.mjs plugins/dforge/reference/native-codex.md plugins/dforge/skills/brainstorming/SKILL.md plugins/dforge/tests/dforge-config.test.sh
git commit -m "fix(dforge): keep Codex workflow overrides"
```

### Task 28: Stale procedure text and fast-mode prose

**Files:**
- Modify: `plugins/dforge/skills/executing-plans/SKILL.md`
- Modify: `plugins/dforge/reference/final-review.md`
- Modify: `plugins/dforge/README.md`
- Modify: `plugins/dforge/reference/fast-mode.md`
- Modify: `plugins/dforge/skills/brainstorming/SKILL.md`
- Modify: `plugins/dforge/skills/systematic-debugging/SKILL.md`
- Modify: `plugins/dforge/skills/executing-plans/references/recovery.md`

**Interfaces:**
- Consumes: C5, C6.
- Produces: none.

**Items:** 30, 31, 38, 59, 14, 3
**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 3 - spec 1 - coupling 0 - risk 0 = 4

- [ ] **Step 1: No new test, because these are procedure texts no script reads; `plugins/dforge/tests/skill-size.test.sh::*` and `plugins/dforge/tests/settings-skills.test.sh::*` still bound and check them**

- [ ] **Step 2: Edit the texts**

1. `executing-plans/SKILL.md:201`: "a delegated task keeps 2 (5 on a `Host: codex` plan)".
2. `final-review.md:479`: "(**the fix pass** above)"; `:489-490`: "Run the plan's `**Integration check:**` command yourself the same way"; the fix-wave re-review, when clean, appends a new `Final review: clean (commits <base>..<new head>)` line (C5).
3. `README.md:400-410`: replace the unplanned-commit hold paragraph with one sentence: the prompt hook's branch-head record serves the UI proof hold only.
4. `fast-mode.md`: fast mode covers one request (`Process: fast — <why>`) or the session (`Process: fast (session) — <why>`) until a later `Process:` line names another path; a later turn of the same request restates the line before its first edit; the compaction snapshot carries a session-scoped line.
5. brainstorming `SKILL.md:25-36` and systematic-debugging `SKILL.md:16-20`: the question offers fast mode, fast for this session, or the full flow; the session answer writes `Process: fast (session) — <why>`.
6. `recovery.md`: route by C5 — `current` to finishing, `stale` to the scoped re-review, `rewritten` to a full final review with a `Ruling:` line naming the rewritten history.

- [ ] **Step 3: Run the checks**

Run: `timeout 300 bash plugins/dforge/tests/skill-size.test.sh && timeout 120 bash plugins/dforge/tests/settings-skills.test.sh && timeout 60 node scripts/validate-repository.mjs`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add plugins/dforge/skills plugins/dforge/reference plugins/dforge/README.md
git commit -m "docs(dforge): drop retired rules, add session fast mode"
```

### Task 29: Cockpit ledger states and question notifications

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/lib.ts`
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: none.
- Produces: C13.

**Items:** 19, 20, 21, 52
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

In `cockpit.test.ts`'s `describe('run card')`, beside `reads the ledger and the plan`:

```ts
  test('reads waiting, deferred and review clean only in its clause', () => {
    const ledger = parseLedger([
      LEDGER,
      'Task 2: waiting — which meter width?',
      'Task 3: implementer inline (assigned; base 1234567)',
      'Task 3: complete (deferred by the auto run) — done: nothing; verified: lint and self review clean; remaining: all; discovered: none; assumptions: none',
    ].join('\n'))
    expect(ledger.tasks.map(task => [task.n, task.state])).toEqual([[1, 'complete'], [2, 'waiting'], [3, 'deferred']])
    expect(ledger.tasks[1]?.question).toBe('which meter width?')
    expect(ledger.tasks[2]?.isClean).toBe(false)
  })

  test('a waiting line sends one question and a deferred task no completion', async ($, on) => {
    const files = runFiles(LEDGER)
    const fetches: World['fetches'] = []
    world(on, { ...SIGNED_IN, files, fetches })
    signedIn(on, files)
    mock.store(on, { notifyUrl: WEBHOOK, notifyOn: 'task,question' })
    await $.tool.call({ tool: 'Skill', skill: 'dforge:executing-plans' })
    await $.session.start(START)
    const ledger = files?.['/home/me/code/shop/.dforge/sdd/p/progress.md']
    if (ledger !== undefined) ledger.text += '\nTask 2: waiting — which meter width?\nTask 3: complete (deferred by the auto run) — done: nothing'
    await $.tool.call({ tool: 'Bash', command: 'cat .dforge/sdd/p/progress.md' })
    await $.turn.complete({ answer: 'Which meter width should the card use?', durationMs: 120_000, isAborted: false, turnId: 't1', reason: 'answer' })
    const titles = fetches.map(f => String((f.body.embeds as Record<string, unknown>[])[0]?.title))
    expect(titles.filter(t => /Task 2/.test(t))).toHaveLength(1)
    expect(titles.filter(t => /✅ Task 3 complete/.test(t))).toEqual([])
  })

  test('a main turn ending on Which option? sends a question', async ($, on) => {
    const fetches: World['fetches'] = []
    world(on, { ...SIGNED_IN, fetches })
    signedIn(on, {})
    mock.store(on, { notifyUrl: WEBHOOK })
    await $.session.start(START)
    await $.turn.complete({ answer: '1. Merge\n2. PR\n\nWhich option?', durationMs: 120_000, isAborted: false, turnId: 't1', reason: 'answer' })
    expect(fetches).toHaveLength(1)
    expect(String((fetches[0]?.body.embeds as Record<string, unknown>[])[0]?.title)).not.toMatch(/^✅ Done/)
  })
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge`
Expected: FAIL on the three tests.

- [ ] **Step 3: Implement**

1. `lib.ts` `parseLedger` (`:917`): C13. A deferred task still counts toward done for `isPlanTail`.
2. `register.tsx`: the Run card draws `waiting` (its question, permission colour) and `deferred` (muted, "deferred") distinctly; `sendLedgerEvents` (`:3373`) sends kind `question` once per `waiting:<n>:<question>` key, and kind `task` "⏭ Task N deferred" for a deferred task, never "✅ … complete".
3. Main-loop `turn.complete`: an answer ending on `Which option?`, `Type 'discard' to confirm` or `Ask me then: show the finish menu`, or a newest ledger line `Task <N>: waiting — ` not yet sent, sends kind `question` instead of `sendDone`; a waiting line `sendLedgerEvents` already sent is not sent again (R15).

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "fix(dforge): show waiting and deferred tasks in the cockpit"
```

### Task 30: Cockpit Run binding, resume offer and stale run

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Modify: `plugins/dforge/hooks/cockpit/lib.ts`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: C13, `auto-run stop --stale` (Task 20).
- Produces: C16.

**Items:** 18, 39, 16, 33
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6

- [ ] **Step 1: Write the failing test**

Two harness rules these tests follow: a test registers each event once (a second `on('fs.list', ...)` beside `world`'s fails to load with `registered twice`), so a counting hook takes a matcher and `world`'s hook answers beneath it; and a test's own hooks nest in registration order, first outermost.

In `describe('run card')`, before `reads the ledger again at a new session start, unchanged as it is`:

```ts
  test('follows the plan this session named, not a newer ledger', async ($, on) => {
    const files: World['files'] = {
      ...runFiles(LEDGER),
      '/home/me/code/shop/.dforge/sdd/q/progress.md': { text: '# SDD ledger — plan: docs/plans/q.md\nTask 1: complete (commits a..b, review clean) — done: x', mtimeMs: 3_000_000 },
      '/home/me/code/shop/docs/plans/q.md': { text: '# Plan\n\n### Task 1: Other\n' },
    }
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:executing-plans' })
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'bash /p/scripts/task-brief --open docs/plans/p.md 2' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Task 2: Draw the card/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /Task 1: Other/ })).toBeUndefined()
  })

  test('lists an unchanged ledger directory once, and again once it changes', async ($, on) => {
    const BASE = '/home/me/code/shop/.dforge/sdd'
    const lists: string[] = []
    // A test registers each event once: world's fs.list hook answers beneath this matched one.
    on('fs.list', { path: BASE } as never, ((_$: unknown, e: { path: string }, next: (e: unknown) => unknown) => {
      lists.push(e.path)
      return next(e)
    }) as never)
    const files: NonNullable<World['files']> = { ...runFiles(LEDGER), [BASE]: { text: '', kind: 'dir', mtimeMs: 5 } }
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:executing-plans' })
    await $.session.start(START)
    const listed = () => lists.filter(path => path === BASE).length
    const before = listed()
    expect(before).toBeGreaterThan(0)
    for (const turnId of ['t1', 't2', 't3']) await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId, reason: 'answer' })
    expect(listed()).toBe(before)
    files[`${BASE}/q/progress.md`] = { text: '# SDD ledger — plan: docs/plans/q.md\nTask 1: implementer dforge:impl-sonnet-low (assigned; base abc1234)', mtimeMs: 3_000_000 }
    files[BASE] = { text: '', kind: 'dir', mtimeMs: 6 }
    await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 't4', reason: 'answer' })
    expect(listed()).toBe(before + 1)
  })
```

In `describe('resume offer')`, beside `withdraws a ruling handoff at the next turn once its last row closes` (before `keeps a ruling handoff whose register cannot be read`). The register lives only in the darkmem docs mirror, so today's checkout path reads nothing and the offer is kept:

```ts
  test('withdraws a ruling handoff once every row of its register in the darkmem docs store is resolved', async ($, on) => {
    const MIRROR = '/home/me/.dforge/mirror/shop'
    const MODE = [
      `documents\tdarkmem\t${MIRROR}/dforge`,
      'progress\tlocal\t/home/me/code/shop/.dforge/sdd\t/home/me/code/shop/.dforge/handoff/latest.md',
      'project\tshop',
      '',
    ].join('\n')
    const STORED = `${MIRROR}/dforge/registers/r.md`
    const files: NonNullable<World['files']> = {
      '/home/me/.dforge/stores.json': { text: '{}', mtimeMs: 1 },
      [LATEST]: { text: rulingHandoff(), mtimeMs: 900_000 },
      [STORED]: { text: register(['done', 'open']), mtimeMs: 1 },
    }
    world(on, { ...SIGNED_IN, files, modeOut: { exitCode: 0, stdout: MODE, stderr: '' } })
    signedIn(on, files)
    await $.session.start(START)
    const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
    expect(await band.find({ key: 'band-resume' })).toBeDefined()
    files[STORED] = { text: register(['done', 'done']), mtimeMs: 2 }
    await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 'turn-1', reason: 'answer' })
    expect(await band.find({ key: 'band-resume' })).toBeUndefined()
  })
```

In `describe('auto run in the pane')`, before `measures against the high regime`. The world's clock starts at 1000 s, so a beat at 700 is 300 s old (past C16's 180 s) and one at 950 is alive:

```ts
  for (const [beat, isNamed] of [[undefined, true], ['700\n', true], ['950\n', false]] as const)
    test(`${isNamed ? 'names' : 'does not name'} auto-run stop --stale for a run whose owner ${beat === undefined ? 'left no heartbeat' : `last beat at ${beat.trim()} s, the clock at 1000 s`}`, async ($, on) => {
      const files: NonNullable<World['files']> = {
        ...autoFiles({ session: 'sess-old', pending: null }),
        ...(beat === undefined ? {} : { '/home/me/.claude/dforge/sessions/cockpit/sess-old': { text: beat } }),
      }
      world(on, { ...SIGNED_IN, files })
      signedIn(on, files)
      await $.session.start(START)
      const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
      const line = await ui.find({ type: 'Text', text: /auto run left by a closed session — run scripts\/auto-run stop --stale/ })
      if (isNamed) expect(line).toBeDefined()
      else expect(line).toBeUndefined()
    })
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge`
Expected: FAIL on `follows the plan this session named, not a newer ledger` (the newer ledger `q` is shown), `lists an unchanged ledger directory once, and again once it changes` (the directory is listed at every turn), `withdraws a ruling handoff once every row of its register in the darkmem docs store is resolved` (the offer stays), and the two `names auto-run stop --stale …` cases. `does not name auto-run stop --stale for a run whose owner last beat at 950 s, the clock at 1000 s` already passes.

- [ ] **Step 3: Implement**

1. `tool.call` (Bash): record the plan path of the last `task-brief`, `task-step`, `task-close` or `next-step` call in a session atom; `readRun` (`:3266`) reads that plan's ledger after turn-end's local-workspace test (`scripts/turn-end.sh:87-90`); newest-by-mtime only when no plan is bound. Cache the ledger-directory listing (`:3282`): keep the entries `$.fs.list(base)` returned with `$.fs.stat(base).mtimeMs`, and list again only when that time changes or the stat fails. Still stat each `<slug>/progress.md` on every read: appending to a ledger changes no directory's modification time.
2. `readResumeOffer` (`:3223`): resolve each register name through `planCandidates`' docs-root mapping (`lib.ts:813-821`), given the roots `readRun` already read and its checkouts, in place of `${root}/${path}`.
3. Add C16's `isSessionAlive($, sid)` to `register.tsx`, reading the heartbeat `beat` writes (`:2997-3007`) with `$.fs.read` and comparing it with `$.clock.now()`. The engine gives a mod no process id or signal API, so liveness is the heartbeat's age, the rule `ar_is_stale` applies (`scripts/lib/auto-run.sh:17`, `:128-157`).
4. The pane: when `.dforge/sdd/auto-run.json` holds an active run whose `session` is not this session's id and `isSessionAlive` is false for it, the auto run card shows `auto run left by a closed session — run scripts/auto-run stop --stale`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/tests/cockpit.test.ts
git commit -m "fix(dforge): bind the Run card to the session's plan"
```

### Task 31: Cockpit guards

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Modify: `plugins/dforge/hooks/cockpit/lib.ts`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: none.
- Produces: none.

**Items:** 17, 62, 42, 43, 44
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 0 - risk 3 = 6
**Lenses:** security

- [ ] **Step 1: Write the failing test**

Harness rules these tests follow: a test registers each event once, so a hook beside one `world` registers takes a matcher (`{ argv: /worktree/ }` matches `process.run`'s argv as a string), and the matched hook, registered first, answers above `world`'s; a test hook that throws is skipped and the kit answers beneath it, so a hook that must make a read fail answers `{ deny }`; and the test's own `on('classic.<Event>')` is the bottom of that classic chain, so a test that raises one registers it.

In `describe('A5: the judge write guard …')`, before `A5: a dforge:impl-* subagent and the main loop are not affected`:

```ts
  test('a direct re-review prompt allows only its report line, not the prior round', async ($, on) => {
    const PRIOR = `${WS}/plan-review-round-1-report.md`
    const NEXT = `${WS}/plan-review-round-2-report.md`
    world(on, { tokens: 10_000, agentIds: ['judge-1'] })
    on('agent.list', () => ({ value: [] }) as never)
    await $.session.start(START)
    await $.agent.spawn(spawn(`Prior findings: ${PRIOR}\nWrite your full report to ${NEXT}, then reply in 10 lines.`, 'dforge:judge-opus', 9))
    expect((await write($, 'judge-1', PRIOR)).deny).toMatch(REFUSED)
    expect((await write($, 'judge-1', NEXT)).deny).toBeUndefined()
  })

  test('accepts the named report under the session directory when no checkout is known and git worktree list fails', async ($, on) => {
    // Matched on its argv, this answers `git worktree list` above world's process.run hook.
    on('process.run', { argv: /worktree/ } as never, (() => ({
      value: { exitCode: 128, stdout: '', stderr: 'fatal: not a git repository\n', isStdoutTruncated: false, isStderrTruncated: false },
    })) as never)
    world(on, { tokens: 10_000, agentIds: ['judge-1'], checkout: '', commonDir: '/home/me/code/shop/.git/modules/sub' })
    signedIn(on, {}, undefined, '/home/me/code/shop', () => '/home/me/code/shop')
    on('agent.list', () => ({ value: [] }) as never)
    await $.session.start(START)
    await $.agent.spawn(spawn(`Review task 1. Write your full report to ${NAMED}, then reply in 10 lines.`, 'dforge:judge-sonnet-high', 1))
    expect((await write($, 'judge-1', NAMED)).deny).toBeUndefined()
    expect((await write($, 'judge-1', `${WS}/amendments.md`)).deny).toMatch(REFUSED)
  })
```

In `describe('attribution guard')`, before `is off when configured off` (the trailer word is built at run time so the test file's own commit passes the guard):

```ts
  test('passes a human co-author and a mere mention, refuses an AI trailer', async ($, on) => {
    const TRAILER = ['Co', 'authored-by:'].join('-')
    world(on, { ...SIGNED_IN })
    signedIn(on, {})
    const human = await $.tool.call({ tool: 'Bash', command: `git commit -m 'fix: x' -m '${TRAILER} Claude Dupont <claude.dupont@example.com>'` })
    expect(human.deny).toBeUndefined()
    const mention = await $.tool.call({ tool: 'Bash', command: `git commit -m 'test: refuse ${TRAILER} trailers naming Claude'` })
    expect(mention.deny).toBeUndefined()
    const ai = await $.tool.call({ tool: 'Bash', command: `git commit -m 'fix: x' -m '${TRAILER} Claude <noreply@anthropic.com>'` })
    expect(ai.deny).toMatch(/keeps AI attribution out of git/)
  })

  test('a guard hook that throws refuses only a call the guard judges, naming guardAttribution', async ($, on) => {
    // The next read of the settings is refused once: the hook's own, before
    // anything else it does; its .catch then reads them as usual. A hook that
    // throws would be skipped and the store beneath would answer, so it denies.
    let failures = 0
    on('state.get', { plugin: 'dforge', key: 'settings' } as never, ((_$: unknown, e: unknown, next: (e: unknown) => unknown) => {
      if (failures > 0) {
        failures -= 1
        return { deny: 'the store is down' }
      }
      return next(e)
    }) as never)
    const files: World['files'] = { '/home/me/code/shop/web/msg.txt': { text: 'fix: tidy\n' } }
    world(on, { ...SIGNED_IN, files })
    signedIn(on, files)
    await $.session.start(START)
    failures = 1
    const read = await $.tool.call({ tool: 'Read', file_path: '/home/me/code/shop/a.ts' } as never)
    expect(read.deny).toBeUndefined()
    expect(read.text).toBe('ok')
    failures = 1
    const commit = await $.tool.call({ tool: 'Bash', command: 'git commit -F msg.txt' })
    expect(commit.deny).toBe('dforge: its attribution guard failed; set guardAttribution off to lift it.')
  })
```

In `describe('discord')`, before `says when a turn fails`:

```ts
  for (const [mode, defaultMode, isAsked] of [['auto', 'default', false], ['default', 'bypassPermissions', true]] as const)
    test(`an approval under the ${mode} mode the session reports ${isAsked ? 'pings' : 'does not ping'}, the settings default being ${defaultMode}`, async ($, on) => {
      const fetches: NonNullable<World['fetches']> = []
      on('tool.check', (_$, e, next) => (e.agentId === undefined ? next(e) : { decision: 'ask' }))
      // The test's own hook is the bottom of a classic event's chain.
      on('classic.UserPromptSubmit', () => ({}) as never)
      const clock = world(on, { tokens: 50_000, fetches, settings: { permissions: { defaultMode } }, config: { notifyAskAfter: 20 } })
      mock.store(on, { notifyUrl: WEBHOOK })
      await $.session.start(START)
      await $.classic.UserPromptSubmit({ prompt: 'go', permission_mode: mode })
      await $.tool.check({ tool: 'Bash', input: { command: 'ls' }, tool_use_id: 'toolu_9', agentId: 'agent-1' })
      await clock.advance(30_000)
      expect(fetches.map(one => (one.body.embeds as Record<string, unknown>[] | undefined)?.[0]?.title)).toEqual(isAsked ? ['⏳ Waiting for approval'] : [])
    })
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge`
Expected: FAIL on the six new tests: the prior round's report is allowed; the report under the session directory is refused with `(none)`; the human co-author is refused; the Read is refused with `dforge: its attribution guard failed.`; the `auto` case pings and the `default` case does not.

- [ ] **Step 3: Implement**

1. `judgeReports` (`:4300`): a direct prompt with a `REPORT_LINE` line (the phrase may wrap) allows only that line's paths; without one, today's behaviour. `reviewDirs` (`:4248`) adds the session cwd (`$.session.cwd()`, a failed read ignored) after the checkout, the primary and the listed worktrees, so a report under `<cwd>/.dforge` is found when `S.where` is unset and `git worktree list` fails.
2. The attribution pattern (`lib.ts:135`): match only a trailer line at a real line start, stopping at a real or escaped newline, whose name or address is an AI identity (the whole name `Claude`, `Codex`, `Copilot`, `ChatGPT`, or an address at `anthropic.com` or `openai.com`); for Bash, scan only `-m` texts and message files, not the whole command.
3. `tool.call`'s `.catch` (`:848-852`): fail closed only for calls the guards judge: a Bash command `writesGitText` matches, a tool `isGitWriteTool` names, and the judge writes the first branch already refuses. For such a call, read `guardAttribution`: off passes the call to `next(e)`; on, or a read that fails, answers `dforge: its attribution guard failed; set guardAttribution off to lift it.` Every other call goes to `next(e)`.
4. Unattended mode from the session: the function-hook `tool.check` event carries no permission mode (`ToolCheckInput`, `.claude-plugin/types/claude-code/index.d.ts:14794-14847`); the classic hook inputs do (`BaseHookInput.permission_mode`, `:881`). Register `classic.UserPromptSubmit` and `classic.PermissionRequest` hooks that store a non-empty `e.permission_mode` in `S.permissionMode` and return `next(e)`; `session.start` clears it. `tool.check` (`:641`) treats a call as unattended by `UNATTENDED_MODES.includes(S.permissionMode)` while `S.permissionMode` is set, and by `S.isUnattended` (the settings default) only before any event has carried a mode.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/tests/cockpit.test.ts
git commit -m "fix(dforge): narrow the write and attribution guards"
```

### Task 32: Cockpit session lifecycle and model snapshot

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Modify: `plugins/dforge/scripts/lib/dforge-config.mjs`
- Test: `plugins/dforge/tests/cockpit.test.ts`
- Test: `plugins/dforge/tests/dforge-config.test.sh`

**Interfaces:**
- Consumes: C16 (Task 30).
- Produces: C14.

**Items:** 60, 61, 45
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

A mod has no process id and no file delete: the engine's `fs` offers `read`, `write`, `list`, `exists`, `stat` and `ancestors` only, and nothing names a process id. So a snapshot's writer is alive by its cockpit heartbeat (C16), and the cockpit deletes a snapshot through `dforge-config.mjs drop-snapshot`, which the test world already records in `w.runs` as it records `claude-restore`.

- [ ] **Step 1: Write the failing test**

Rewritten assertions (row 60 adds `effortLevel` to what is saved and restored): in `describe('auto run')`, `puts back the default model and effort that /model and /effort save` expects

```ts
    expect(w.runs?.filter(run => run.includes(' claude-restore '))).toEqual([
      expect.stringContaining(`claude-restore ${JSON.stringify({ model: 'opus[1m]', modelSettings: { 'claude-opus-5-5': { effortLevel: 'max' } }, effortLevel: null })}`),
    ])
```

and `removes the defaults /model and /effort added where none were set` expects

```ts
    expect(w.runs?.filter(run => run.includes(' claude-restore '))).toEqual([expect.stringContaining('claude-restore {"model":null,"modelSettings":null,"effortLevel":null}')])
```

In `describe('auto run')`, before `removes the defaults /model and /effort added where none were set`:

```ts
  for (const isRefusing of [false, true])
    test(`saves the defaults before /model and ${isRefusing ? 'keeps them when the restore fails' : 'drops them once the restore reads back'}`, async ($, on) => {
      const SNAP = '/home/me/.claude/dforge/sessions/saved-defaults/sess-2.json'
      const files = autoFiles({ pending: 'clear', resumePrompt: 'Execute docs/plan.md.', launch: { model: 'sonnet', effort: 'high' } })
      const written: Record<string, string> = {}
      let atModel: string | undefined
      const w: World = {
        ...SIGNED_IN,
        written,
        commands: [],
        autoRuns: [],
        prompts: [],
        runs: [],
        userSettings: { model: 'opus[1m]', effortLevel: 'max' },
        isDforgeConfigRefusing: isRefusing,
        autoFile: files[AUTO],
        onCommand: command => {
          if (command === 'model') atModel = written[SNAP]
        },
      }
      const clock = world(on, w)
      signedIn(on, files)
      await $.session.start(START)
      await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
      await settle(clock)
      expect(JSON.parse(atModel ?? 'null')).toEqual({ session: 'sess-2', launchModel: 'sonnet', saved: { model: 'opus[1m]', modelSettings: null, effortLevel: 'max' } })
      expect(w.runs?.filter(run => run.includes(' drop-snapshot '))).toEqual(isRefusing ? [] : [expect.stringContaining('drop-snapshot sess-2')])
    })

  describe('a model switch snapshot another session left', () => {
    const SNAP = '/home/me/.claude/dforge/sessions/saved-defaults/sess-0.json'
    const BEAT = '/home/me/.claude/dforge/sessions/cockpit/sess-0'
    const SNAPSHOT = { text: JSON.stringify({ session: 'sess-0', launchModel: 'sonnet', saved: { model: 'opus[1m]', modelSettings: null, effortLevel: 'max' } }) }
    // The clock starts at 1000 s: a beat at 700 is 300 s old, past the 180 s limit; one at 990 is alive.
    const startWith = async ($: Parameters<TestBody>[0], on: On, model: string, beat?: string) => {
      const files: NonNullable<World['files']> = { [SNAP]: SNAPSHOT, ...(beat === undefined ? {} : { [BEAT]: { text: beat } }) }
      const w: World = { ...SIGNED_IN, runs: [], toasts: [], files, userSettings: { model } }
      const clock = world(on, w)
      signedIn(on, files)
      await $.session.start(START)
      await settle(clock)
      return w
    }
    const restores = (w: World) => w.runs?.filter(run => run.includes(' claude-restore ')) ?? []
    const drops = (w: World) => w.runs?.filter(run => run.includes(' drop-snapshot ')) ?? []
    const told = (w: World) => w.toasts?.filter(text => /snapshot/.test(text)) ?? []

    for (const beat of ['700\n', undefined])
      test(`restores the defaults of a session ${beat === undefined ? 'that left no heartbeat' : 'whose heartbeat is stale'} while its launch model is the default, then drops the snapshot`, async ($, on) => {
        const w = await startWith($, on, 'sonnet', beat)
        expect(restores(w)).toEqual([expect.stringContaining('claude-restore {"model":"opus[1m]","modelSettings":null,"effortLevel":"max"}')])
        expect(w.userSettings).toEqual({ model: 'opus[1m]', effortLevel: 'max' })
        expect(drops(w)).toEqual([expect.stringContaining('drop-snapshot sess-0')])
        expect(told(w)).toEqual([])
      })

    test('drops, saying so once, the snapshot of a dead session whose launch model is no longer the default', async ($, on) => {
      const w = await startWith($, on, 'haiku', '700\n')
      expect(restores(w)).toEqual([])
      expect(drops(w)).toEqual([expect.stringContaining('drop-snapshot sess-0')])
      expect(told(w)).toEqual(['dforge: dropped the model switch snapshot of session sess-0: your default model is no longer sonnet.'])
    })

    test('leaves the snapshot of a session that is still alive', async ($, on) => {
      const w = await startWith($, on, 'sonnet', '990\n')
      expect(restores(w)).toEqual([])
      expect(drops(w)).toEqual([])
      expect(told(w)).toEqual([])
    })
  })

  test('arms the watchdog when a read at the start fails', async ($, on) => {
    const written: Record<string, string> = {}
    const clock = world(on, { ...SIGNED_IN, written, isUsageFailing: true })
    signedIn(on, {})
    await $.session.start(START)
    await clock.advance(60_000)
    expect(written['/home/me/.claude/dforge/sessions/cockpit/sess-1']).toBe('1060\n')
  })

  test("a main compaction clears the turn readings, a subagent's does not", async ($, on) => {
    const sets: unknown[] = []
    on('state.set', { plugin: 'dforge', key: 'turnTokens' } as never, ((_$: unknown, e: { value: unknown }, next: (e: unknown) => unknown) => {
      sets.push(e.value)
      return next(e)
    }) as never)
    world(on, { ...SIGNED_IN })
    signedIn(on, {})
    await $.session.start(START)
    await $.tool.call({ tool: 'Skill', skill: 'dforge:executing-plans' })
    await $.turn.complete({ answer: 'ok', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    const before = sets.length
    expect(before).toBeGreaterThan(0)
    await $.session.compact({ trigger: 'auto', messages: [SUMMARY], agentId: 'agent-1' } as never)
    expect(sets).toHaveLength(before)
    await $.session.compact({ trigger: 'manual', messages: [SUMMARY] })
    expect(sets.slice(before)).toEqual([[]])
  })
```

In `describe('auto run')`, before `submits no reconcile prompt outside an auto run`. With `pending: 'compact'` and no sentinel turn the stage is never armed, so only `RECONCILE_CAP` can fail it: today the count carries over the session change and the second prompt after it books the failure:

```ts
  test('counts the reconcile prompts afresh in the session a resume carries the process into', { timeoutMs: 30_000 }, async ($, on) => {
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    on('session.end', (_$, e) => e as never)
    signedIn(on, files)
    await $.session.start(START)
    await spawnTask4($)
    // No sentinel: the pending compact is never armed, so only the reconcile cap can fail it.
    await $.turn.complete({ answer: 'Waiting for the implementer.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    const reconciles = () => w.prompts?.filter(text => RECONCILE_PROMPT.test(text)).length
    await clock.advance(2_600_000)
    expect(reconciles()).toBe(2)
    await $.session.end({ reason: 'resume', sessionId: 'sess-1', resume: { id: 'sess-1' } })
    w.sessionId = 'sess-2'
    files[AUTO]!.text = files[AUTO]!.text.replace('"session":"sess-1"', '"session":"sess-2"')
    await clock.advance(2_600_000)
    expect(reconciles()).toBe(4)
    expect(w.autoRuns?.filter(call => call.includes(' failure '))).toEqual([])
  })
```

In `describe('keep-warm')`, before `submits nothing while the composer holds a draft`. Any person turn already resets the count (`register.tsx:621`), so the session changes with no turn in between:

```ts
    test('lets six more go in the session a resume carries the process into', async ($, on) => {
      const w = quiet({ keepWarm: 4 })
      const clock = world(on, w)
      on('session.end', (_$, e) => e as never)
      await begin($)
      for (let i = 1; i <= 8; i++) {
        await clock.advance(5 * MIN)
        if (sentOf(w).length === i) await keepWarmTurn($, clock, `k${i}`)
      }
      expect(sentOf(w)).toHaveLength(6)
      // The shell still runs and no turn starts: only the session id changes.
      await $.session.end({ reason: 'resume', sessionId: 'sess-1', resume: { id: 'sess-1' } })
      w.sessionId = 'sess-2'
      await clock.advance(2_000)
      await clock.advance(5 * MIN)
      expect(sentOf(w)).toHaveLength(7)
    })
```

Append to `plugins/dforge/tests/dforge-config.test.sh`, before its closing `printf '\n%d passed, %d failed\n'` line:

```bash
# --- claude-restore takes effortLevel; drop-snapshot removes one session's snapshot (row 60) ---
fresh snapshot
mkdir -p "$HOME/.claude"
printf '%s\n' '{"model":"sonnet"}' > "$HOME/.claude/settings.json"
fc claude-restore '{"model":"opus[1m]","modelSettings":null,"effortLevel":"high"}'; check "claude-restore takes effortLevel: exit 0" "$?" "0"
check "claude-restore takes effortLevel: written" "$(at "$HOME/.claude/settings.json" effortLevel)" '"high"'
printf '%s\n' '{"model":"sonnet","effortLevel":"low"}' > "$HOME/.claude/settings.json"
fc claude-restore '{"effortLevel":null}'; check "claude-restore: a null effortLevel removes it" "$?:$(keys "$HOME/.claude/settings.json")" "0:model"
SNAPS="$HOME/.claude/dforge/sessions/saved-defaults"
mkdir -p "$SNAPS"
printf '{}\n' > "$SNAPS/sess-0.json"
printf '{}\n' > "$SNAPS/sess-9.json"
fc drop-snapshot 'sess/0'; check "drop-snapshot: exit 0" "$?" "0"
check "drop-snapshot: only that session's snapshot is gone, its id sanitised" "$(ls "$SNAPS" | tr '\n' ' ')" "sess-9.json "
fc drop-snapshot sess-0; check "drop-snapshot: a missing snapshot: exit 0" "$?" "0"
fc drop-snapshot; check "drop-snapshot: no session: exit 2" "$?" "2"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge; timeout 300 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: FAIL. In the cockpit suite: the two rewritten assertions (no `effortLevel` in the restore), both `saves the defaults before /model …` cases (no snapshot is written), the two `restores the defaults of a session …` cases and `drops, saying so once, …` (nothing is read at start), `arms the watchdog when a read at the start fails` (no heartbeat: the failing usage read ends `session.start` before the timers are armed), `a main compaction clears the turn readings, …`, `counts the reconcile prompts afresh …` (3 prompts and a booked failure) and `lets six more go …` (6, not 7). `leaves the snapshot of a session that is still alive` already passes. In dforge-config: the three `claude-restore` effortLevel checks and the first three `drop-snapshot` checks; `drop-snapshot: no session: exit 2` already passes.

- [ ] **Step 3: Implement**

1. `autoStage` (`:2851`): before `/model`, write C14 for the current session id with `$.fs.write`, unless `$.fs.stat` finds the file; `saved` is `userDefaults`' answer. After `restoreUserDefaults` returns true, run `node <plugin root>/scripts/lib/dforge-config.mjs drop-snapshot <session id>` (timeout 15 s, a failure ignored); a restore that did not read back leaves the snapshot.
2. `session.start`: list `<home>/.claude/dforge/sessions/saved-defaults` (a listing that fails means none) and read each name ending `.json`, whatever kind the listing reports. Skip this session's own. For another session's snapshot: leave it when `isSessionAlive` (C16) holds for its `session`; otherwise, when the user's current `model` (from `userDefaults`) equals its `launchModel`, put its `saved` back with `restoreUserDefaults` and drop it once that read back; otherwise drop it and toast `dforge: dropped the model switch snapshot of session <session>: your default model is no longer <launchModel>.` A snapshot that does not parse is dropped (by its file name less `.json`) with `dforge: dropped an unreadable model switch snapshot, <file name>.` Compare `saved` in C14's key order (`model`, `modelSettings`, `effortLevel`), since the read-back compares JSON text.
3. `RESTORABLE` (`dforge-config.mjs:169`) gains `effortLevel`; `userDefaults` (`register.tsx:2955`) returns `{ model, modelSettings, effortLevel }`, each missing key `null`. `dforge-config.mjs` gains `drop-snapshot SESSION`: delete `<home>/.claude/dforge/sessions/saved-defaults/<SESSION with every character outside A-Za-z0-9 replaced by ->.json` (`<home>` as `homeOf` reads it), a missing file included, and exit 0; any other argument count prints the usage line, which names the command, and exits 2.
4. A `resetSessionGuards()` resets `keepWarmCount`, `reconcileSeen` and `autoDeferredSince`; `session.start` calls it in place of its own resets (`:396-397`), and `pollTick` (`:3828-3831`) calls it before `readSession($, false)` when the session id changed. A main `session.compact` (`:508`) clears `turnTokens` to `[]`.
5. `session.start` (`:392`) arms the watchdog and the poll first, then runs `readSession` with each read in its own `try`, so a read that throws (`refresh`'s `$.session.usage()`, `:3542`) skips only its own section.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge && timeout 300 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/scripts/lib/dforge-config.mjs plugins/dforge/tests/cockpit.test.ts plugins/dforge/tests/dforge-config.test.sh
git commit -m "fix(dforge): survive a crash between switch and restore"
```

### Task 33: Cockpit glyphs, problem count and saved-state honesty

**Files:**
- Modify: `plugins/dforge/config/schema.mjs`
- Modify: `plugins/dforge/hooks/cockpit/lib.ts`
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: none.
- Produces: none.

**Items:** 46, 22, 47
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 2 - coupling 0 - risk 1 = 5

- [ ] **Step 1: Write the failing test**

```ts
describe('display and saved-state honesty', () => {
  test('paneGlyphs=ascii draws only ASCII, and the head counts setting problems', async ($, on) => {
    world(on, { tokens: 284_000, config: { paneGlyphs: 'ascii', layout: 'tiles' } })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(JSON.stringify(await ui.drawn())).not.toMatch(/[▰▱●▸]/)
    expect(await ui.find({ type: 'Text', text: /1 setting problem/ })).toBeDefined()
  })

  test('a Claude-key save the engine drops is cleared and toasted', async ($, on) => {
    const toasts: string[] = []
    const clock = world(on, { tokens: 284_000, config: {}, toasts, runs: [], settings: { autoCompactWindow: 650_000 } })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    await ui.press({ key: 'set-autoCompactWindow-more' })
    await clock.advance(10_000)
    expect(await ui.find({ type: 'Text', text: /^650k/ })).toBeDefined()
    expect(toasts.filter(t => /autoCompactWindow .*did not stick/.test(t))).toHaveLength(1)
  })

  test('a skill-enforced key changed in the file mid-session adds the settings note', async ($, on) => {
    const notes: string[] = []
    const files: NonNullable<World['files']> = { [CONFIG]: { text: JSON.stringify({}), mtimeMs: 1 } }
    const clock = world(on, { ...SIGNED_IN, files, notes })
    signedIn(on, files)
    await $.session.start(START)
    files[CONFIG] = { text: JSON.stringify({ worktree: 'never' }), mtimeMs: 2 }
    await clock.advance(10_000)
    await $.turn.start({ text: 'next', turnId: 't2' })
    expect(notes.some(n => /worktree/.test(n))).toBe(true)
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge`
Expected: FAIL on the three tests.

- [ ] **Step 3: Implement**

1. `schema.mjs`: `paneGlyphs` (`enum` `unicode` | `ascii`, default `unicode`, group `Cockpit`, label `Glyphs`); `lib.ts` `bar` and `nowLine` take a glyph set (`#`/`-`, `*`, `>` for ASCII); the pane head shows `<n> setting problem(s)` when `S.settingProblems` is non-empty.
2. `setOption` (`:3679`) for a Claude key: poll the engine's user settings as `restoreUserDefaults` does (500 ms, up to 3 s); when the value did not stick, delete `S.claudeSaved[key]` and toast `dforge: <key> did not stick: the engine kept <value>`.
3. `rereadSettings` (`:3856`): add the skill-enforced keys whose value changed to `S.changed`, so `flushSettingNote` sends them.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge && timeout 300 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/config/schema.mjs plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "feat(dforge): add ASCII glyphs and honest saved settings"
```

### Task 34: Broken settings file

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Modify: `plugins/dforge/scripts/lib/dforge-config.mjs`
- Test: `plugins/dforge/tests/cockpit.test.ts`
- Test: `plugins/dforge/tests/dforge-config.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: C15.

**Items:** 24
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 2 - coupling 0 - risk 1 = 5

- [ ] **Step 1: Write the failing test**

```ts
  test('a settings file that does not parse is a problem and silences Discord', async ($, on) => {
    const fetches: World['fetches'] = []
    const files: NonNullable<World['files']> = { [CONFIG]: { text: '{"layout": "full",}', mtimeMs: 1 } }
    world(on, { ...SIGNED_IN, files, fetches, env: { HOME: '/home/me', DFORGE_NOTIFY_URL: WEBHOOK } })
    signedIn(on, files)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /1 setting problem/ })).toBeDefined()
    await $.turn.complete({ answer: 'done', durationMs: 120_000, isAborted: false, turnId: 't1', reason: 'answer' })
    expect(fetches).toHaveLength(0)
  })
```

```bash
fresh broken
mkdir -p "$(dirname "$FILE")" && printf '{"layout": "full",}' > "$FILE"
check "workflow: a broken file prints the problem line" "$(fc workflow)" "dforge: $FILE is not a JSON object; every setting reads its default and notifyOn reads none until it parses"
```

The first goes in `cockpit.test.ts` beside `the settings view says which saved values it ignored`, the second at the end of `dforge-config.test.sh` before its summary.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge; timeout 300 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: FAIL on both.

- [ ] **Step 3: Implement**

1. `loadSettings` (`:3670`): a file that exists and is not a JSON object adds C15 to `S.settingProblems` and resolves `notifyOn` as `none` until it parses; `rereadSettings` keeps that state until then.
2. `workflowLine`: C15 instead of the settings line when the file exists and does not parse to an object; `session-start.sh` already injects the first line.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge && timeout 300 bash plugins/dforge/tests/dforge-config.test.sh && timeout 300 bash plugins/dforge/tests/hook.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/scripts/lib/dforge-config.mjs plugins/dforge/tests/cockpit.test.ts plugins/dforge/tests/dforge-config.test.sh
git commit -m "fix(dforge): report a settings file that does not parse"
```

### Task 35: One settings resolver and locked Claude writes

**Files:**
- Modify: `plugins/dforge/config/schema.mjs`
- Modify: `plugins/dforge/hooks/cockpit/config.ts`
- Modify: `plugins/dforge/scripts/lib/dforge-config.mjs`
- Test: `plugins/dforge/tests/dforge-config.test.sh`

**Interfaces:**
- Consumes: none.
- Produces: none.

**Items:** 48, 49
**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

Append to `plugins/dforge/tests/dforge-config.test.sh`, before its summary:

```bash
fresh resolver
mkdir -p "$(dirname "$FILE")" && printf '{"notifyOn": "off", "sections": "plan,unknown"}' > "$FILE"
check "an invalid notifyOn reads none" "$(fc get notifyOn)" "none"
check "a mixed list keeps its known names" "$(fc get sections)" "plan"
fresh claudelock
mkdir -p "$HOME/.claude" && printf '{}' > "$HOME/.claude/settings.json"
# The delay holds each writer between its read and its write, so two unlocked
# writers always both read {} and the second rename drops the first key.
DFORGE_CLAUDE_WRITE_DELAY_MS=1500 fc set autoCompactWindow 700000 & DFORGE_CLAUDE_WRITE_DELAY_MS=1500 fc set autoCompactEnabled false & wait
check "two concurrent Claude-key writes both persist" "$(jq -c '{autoCompactWindow, autoCompactEnabled}' "$HOME/.claude/settings.json")" '{"autoCompactWindow":700000,"autoCompactEnabled":false}'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: FAIL on `an invalid notifyOn reads none` and `two concurrent Claude-key writes both persist`.

- [ ] **Step 3: Implement**

1. `schema.mjs`: export `resolveStored(key, spec, file)` beside `isValidValue` with the list salvage and the `notifyOn`-as-`none` fallback now in `config.ts:87-111`; `config.ts` `storedSetting` and `dforge-config.mjs` `resolve` both call it, each keeping its own warning. `SettingSpec['unit']` gains `'min'`.
2. `writeClaudeKeys`: hold a lock keyed to `realTarget(...)` across read, change and rename (the `withHomeLock` mechanism with a per-file lock name, waiting at least 10 s for it); `setValue`'s Claude branch and `restoreClaude` go through it. Between the read and the write, when `DFORGE_CLAUDE_WRITE_DELAY_MS` is a positive integer, block that many milliseconds (`Atomics.wait` on a fresh `Int32Array(new SharedArrayBuffer(4))`): a test seam, named in the function's comment, that leaves the default path unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/dforge-config.test.sh && timeout 240 /root/.local/bin/claude plugin test plugins/dforge`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/config/schema.mjs plugins/dforge/hooks/cockpit/config.ts plugins/dforge/scripts/lib/dforge-config.mjs plugins/dforge/tests/dforge-config.test.sh
git commit -m "fix(dforge): resolve settings once and lock Claude writes"
```

### Task 36: Inert rows, consent press and desktop steppers

**Files:**
- Modify: `plugins/dforge/config/schema.mjs`
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`
- Modify: `plugins/dforge/hooks/cockpit/settings-view.tsx`
- Test: `plugins/dforge/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: none.
- Produces: none.

**Items:** 50, 51, 63
**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 2 - coupling 0 - risk 1 = 5

- [ ] **Step 1: Write the failing test**

```ts
describe('inert rows, consent and desktop steppers', () => {
  test('the darkmem store rows are locked while darkmem is off', async ($, on) => {
    world(on, { tokens: 284_000, config: { darkmemEnabled: false } })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-darkmem' })
    expect((await ui.find({ key: 'set-documentStore-controls' }))?.text).toMatch(/no effect while darkmem is off/)
  })

  test('raising the AgentRouter cap from 0 needs a second press', async ($, on) => {
    const written: Record<string, string> = {}
    world(on, { tokens: 284_000, config: {}, written })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: `settings-tab-${SCHEMA.apiBudgetAgentRouter!.group}` })
    await ui.press({ key: 'set-apiBudgetAgentRouter-more' })
    expect(written[CONFIG]).toBeUndefined()
    await ui.press({ key: 'set-apiBudgetAgentRouter-confirm' })
    expect(JSON.parse(written[CONFIG] ?? '{}').apiBudgetAgentRouter).toBe(5)
  })

  test('a desktop stepper shows its zero word', async ($, on) => {
    world(on, { tokens: 284_000, config: {} })
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
    await ui.press({ key: 'pane-settings' })
    await ui.press({ key: 'settings-tab-Context' })
    expect((await boxTexts(ui)).join(' ')).toMatch(/\bauto\b/)
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge`
Expected: FAIL on the three tests.

- [ ] **Step 3: Implement**

1. `schema.mjs`: `documentStore` and `progressSource` get `inertWhen: { key: 'darkmemEnabled', value: false, words: 'no effect while darkmem is off' }`.
2. `register.tsx` `step` (`:1147-1152`): `+` on `apiBudgetAgentRouter` at 0 shows `set-apiBudgetAgentRouter-confirm` and `-cancel` (the Reset-group confirm pattern, `settings-view.tsx:259-261`) and saves only on the confirm.
3. `settings-view.tsx` `nativeControl` (`:175-178`): show `row.shown` beside the desktop field; `webhookRows` (`register.tsx:987-996`) use the native stacked layout on desktop.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 240 /root/.local/bin/claude plugin test plugins/dforge && timeout 300 bash plugins/dforge/tests/dforge-config.test.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/config/schema.mjs plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/hooks/cockpit/settings-view.tsx plugins/dforge/tests/cockpit.test.ts
git commit -m "fix(dforge): lock inert rows and confirm API consent"
```
