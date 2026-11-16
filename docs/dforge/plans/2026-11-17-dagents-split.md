# dagents Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship dagents 1.0.0 (dforge 4.17.1 renamed, isolated and carrying every version-5 fix for a defect it shares) beside dforge 5 and dflow, with a guard that stands all of them down when more than one is active.

**Architecture:** `plugins/dagents` is created from tag `dforge-v4.17.1` by `git read-tree`, renamed once by a repository script (`scripts/dagents-rename.mjs`) that also translates every backported patch, and enrolled in both catalogs and CI with its own test jobs. A backport register lists every dforge commit since the tag; port tasks walk it in source order. A shared `workflow-guard.mjs`, byte-identical in the three plugins, reads the host's plugin settings and drives each plugin's stand-down.

**Tech Stack:** Bash hook and CLI scripts, Node.js 22 ESM (`node:test`), Claude Code mods (TypeScript), GitHub Actions.

**Spec:** docs/dforge/specs/2026-11-16-dagents-split-design.md

**Execution:** inline — `claude --model opus --effort high` — the hardest self-implemented task totals 8 and two tasks carry risk 3

**Parallelism:** sequential — inline execution

**Task check:** none — full suite every 3 tasks

**Integration check:** `node scripts/test-all.mjs && node scripts/test-all.mjs --plugin dagents`

**CI:** `.github/workflows/validate.yml` — platforms: homelab self-hosted Linux, uutils (ubuntu-latest), Windows Git Bash — local: `node scripts/validate-repository.mjs`; `node scripts/test-all.mjs`; `claude plugin validate .`; `claude plugin validate plugins/dforge`; `claude plugin test plugins/dforge`; `claude plugin validate plugins/dflow`; `claude plugin test plugins/dflow` — uncovered: uutils (ubuntu-latest), Windows Git Bash

## Global Constraints

- Commit as `Darkraise <quangtc94@gmail.com>`; no `Co-Authored-By:`, `Claude-Session:` or "Generated with" text in any commit. Commit subjects follow `<type>(<scope>): <subject>`, at most 50 characters, imperative, no period.
- Work in place on a new branch `feat/dagents-split` created from `main` at the start of Task 1; never push and never merge before the finish step (an auto run performs the merge at finishing).
- English only in code, comments, docs and commit messages. No comment explains what code does; one is written only for a hidden constraint.
- `plugins/dagents/.claude-plugin/plugin.json` and `plugins/dagents/.codex-plugin/plugin.json` carry `"version": "1.0.0"` and no commit changes either version; no commit edits dforge's or dflow's version.
- dagents never reads or writes `.dforge/`, `docs/dforge/`, `~/.dforge/`, `~/.claude/dforge/`, `<git dir>/dforge/`, a `DFORGE_*` variable or the darkmem `dforge/` prefix, except in the files the Contracts allowlist names (migrate, the older-spelling readers, the guard's sibling list, the README origin note, the legacy dr-forge and dr-superpowers translations).
- Shared on purpose, never renamed: `CLAUDE_*`, `CODEX_*`, `DARKMEM_API_KEY`, `DARKMEM_URL`, `DR_TEST_BASH`, `DR_TEST_ALL`, `DR_FORGE_*`, `DR_SUPERPOWERS_*`, and the `WORKFLOW_GUARD_*` overrides.
- Every test, build and CLI command runs under an explicit `timeout`; every process a task starts is stopped before the task ends.
- Windows Git Bash: a native program (`git.exe`, `jq.exe`) given a path built from `$PWD`, `$(pwd)` or `$TMPDIR` gets a POSIX form it cannot open, or has its argument rewritten when path conversion is on (`MSYS_NO_PATHCONV` unset). Convert the path with `cygpath -m` before the call (dforge's `dr_native_path`, `plugins/dforge/scripts/lib/native-path.sh`), and feed `jq` a file on stdin in a script that exports `MSYS_NO_PATHCONV`.
- Windows Git Bash: the same directory is `/c/Users/x` in the shell and `C:/Users/x` from a native tool, so a string comparison never matches. Normalise both sides with `cygpath -m`, or compare with `-ef`.
- Windows Git Bash: files a Windows tool wrote, and native program output, end lines with `\r`, which `read`, `awk` and `[ = ]` keep. Pipe through `tr -d '\r'` before comparing or parsing.
- Windows Git Bash: `awk -v name=value` processes backslash escapes in the value, so a regex or a Windows path changes. Pass the value in the environment and read `ENVIRON["NAME"]`.
- Windows Git Bash: Node's `import()` of an absolute `D:/x/y.mjs` reads `d:` as a URL scheme and fails. Import with `import(pathToFileURL(path).href)`.
- uutils (ubuntu-latest): a lock built on `mkdir` failing when the directory exists does not exclude a second process. Create the lock file with `set -C` (noclobber), or use `flock`.
- uutils (ubuntu-latest): `timeout` signals only the command it started, so the command's children keep running. Run the command in its own process group (`setsid`) and signal the group.

## Contracts

- **C1 — the copy.** `plugins/dagents/` is created by `git read-tree --prefix=plugins/dagents/ -u dforge-v4.17.1:plugins/dforge`, and its tree hash at the copy commit equals `git rev-parse dforge-v4.17.1:plugins/dforge`.
- **C2 — test scheduling.** `scripts/test-shards.mjs` exports `windowsSeconds`, `suiteSeconds` and `suiteParts`, each keyed by a suite's repository path (`plugins/dforge/tests/plan-lint.test.sh`, `plugins/dr-status/tests/run-all.sh`), plus `selectShard(jobs, shard, weights)` and `checkShellWeights(jobs, weights)`, which look weights up by `job[1][0]` (the full path) and check every `plugins/<name>/tests/*.test.sh`, `*.acceptance.sh` and `plugins/dr-status/tests/run-all.sh`. `scripts/test-all.mjs` takes `--plugin <name>`: without it, it runs every job except dagents' jobs; with `--plugin dagents`, only dagents' jobs (its shell suites, `claude plugin test plugins/dagents` when `claude` is on PATH, `tsc --noEmit -p plugins/dagents` when its generated types exist). `--plugin` composes with `--shard`, `--list` and `--limits`. Any other `--plugin` value exits 2.
- **C3 — the rename.** `scripts/dagents-rename.mjs` exports `renameText(text)` and `renamePath(relPath)`, and runs as `node scripts/dagents-rename.mjs tree <dir>` (rewrites every text file's content and renames every path component under `<dir>`, in place; exit 0, or exit 1 naming both sources when two distinct source names map to one target) and `node scripts/dagents-rename.mjs patch` (a unified diff on stdin, the translated diff on stdout). The map, applied in this order: (1) `\bDFORGE_` → `DAGENTS_`; (2) `\bDR_[A-Z0-9_]+` → `DAGENTS_` + the rest, except `DR_TEST_BASH`, `DR_TEST_ALL`, `DR_FORGE_*` and `DR_SUPERPOWERS_*`; (3) `DARKMEM_KILL_GRACE`, `DARKMEM_SYNC_LOCK_WAIT_MS`, `DARKMEM_SYNC_TIMEOUT_MS` → `DAGENTS_` + the name; (4) `dforge` followed by ` <digit>`, ` v<digit>` or `-v<digit>` is left unchanged; (5) every other `dforge` → `dagents`, `Dforge` → `Dagents`, `DFORGE` → `DAGENTS`. Files holding a NUL byte are left unchanged.
- **C4 — the validator.** `validateRepository(root, { names } = {})` takes an optional plugin list (default the maintained list). `NAMESPACED = ['dforge', 'dagents']`: for each such plugin, every `<plugin>:<name>` reference in its own tree must resolve to `plugins/<plugin>/skills/<name>`, `agents/<name>.md` or `commands/<name>.md`, else the error `<rel>:<line>: unresolved <plugin> reference <name>`. `validateSchema(root, plugin = 'dforge')` reads `plugins/<plugin>/config/schema.mjs` and requires `target` to be `<plugin>` or `claude` (error `schema <key>: target must be <plugin> or claude`); the CLI validates the schema of every listed plugin that has one. `.dagents` is unswept. `DAGENTS_DFORGE_ALLOWED` is the set of `plugins/dagents/` files allowed to spell `dforge` (beyond the C3 rule-4 version text); any other match is the error `<rel>:<line>: dforge name in dagents`, and `dagents <digit>` other than `dagents 1` is the error `<rel>:<line>: dagents version other than 1.x`.
- **C5 — the backport register and tool.** `docs/dforge/registers/2026-11-16-dagents-backport.md` (`**Covers:** -`) holds one row per commit, Item `<sha7> <subject>`, in `git rev-list --no-merges --reverse dforge-v4.17.1..<to> -- plugins/dforge` order. A finished row is `done` with Note `port <dagents-sha7>; fail@parent pass@port` or `port <dagents-sha7>; text-only <path>`, or `n/a` with Note `5-only`, `5-only: <reason>`, `feature: <reason>`, `test-only: <reason>`, `docs-only: <reason>` or `superseded by <sha7>: <reason>`. `node scripts/dagents-backport.mjs rows <from> <to>` prints `<sha7> <subject>` per commit; `five-only <sha>` exits 0 when every non-test path (not under a `/tests/` directory) the commit touches under `plugins/dforge/` is absent at `dforge-v4.17.1`, else 1; `audit <register> <to> [--through <id>]` exits 0 when every row (through row `<id>`, when given) is finished as above, a bare `5-only` passes `five-only`, a `port` sha resolves to a commit that touches `plugins/dagents/`, and (without `--through`) every commit `rows` lists is a row; else it prints one line per problem and exits 1.
- **C6 — older spellings.** In dagents, `docs/dforge` and `.dforge` are a third older spelling beside `docs/forge`/`docs/superpowers` and `.forge`/`.superpowers`: `dagents_name_key docs/dforge/<rest>` prints `docs/dagents/<rest>`; `dagents_name_spellings docs/dagents/<rest>` prints the key `docs/dagents/<rest>`, then `docs/dforge/<rest>`, `docs/forge/<rest>`, `docs/superpowers/<rest>`, in that order; `dagents_resolve docs/dforge/<rest>` prints `<docs root>/<rest>`. The dforge spelling translates local names and citations only: it never forms a darkmem request uri or workstream key.
- **C7 — darkmem namespace.** dagents' darkmem client name is `dagents`, its document uris start `dagents/`, and every workstream key it writes or reads starts `dagents/` (`dagents/<plan slug>`, `dagents/project`).
- **C8 — the guard.** `scripts/workflow-guard.mjs` in `plugins/dforge`, `plugins/dagents` and `plugins/dflow`, byte-identical. CLI: `node workflow-guard.mjs --host claude|codex [--self <name>] [--hook session-start]`. Inputs: `WORKFLOW_GUARD_CLAUDE_DIR` (default `${CLAUDE_CONFIG_DIR:-~/.claude}`), `WORKFLOW_GUARD_MANAGED_DIR` (default per OS: `/etc/claude-code` on Linux, `/Library/Application Support/ClaudeCode` on macOS, `C:\Program Files\ClaudeCode` on Windows; `managed-settings.json` plus `managed-settings.d/*.json`), `WORKFLOW_GUARD_PROJECT_DIR` (default `CLAUDE_PROJECT_DIR`, else the working directory's git root), and for Codex `CODEX_HOME` (default `~/.codex`). Siblings are `dforge@darkraise`, `dagents@darkraise`, `dflow@darkraise`. Standalone output: one line `<name>@darkraise <scope>` per active plugin (`<scope>` is `managed`, `local`, `project`, `user` or `default`), exit 0 for zero or one, 3 for two or more, 2 for bad usage. `--self <name>` counts that plugin active (scope `self`). `--hook session-start` reads the hook event JSON on stdin; on a conflict it prints one JSON object `{"systemMessage": <block>, "hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": <block + relay instruction>}}`, writes the marker and exits 3; with no conflict it prints nothing, deletes this session's marker and exits 0. The block names every active plugin and, per active plugin, `claude plugin disable <name>@darkraise --scope local` first, then `claude plugin disable <name>@darkraise --scope <scope>` when `<scope>` is `user` or `project`. Marker: `${CLAUDE_PLUGIN_DATA}/workflow-guard/<session id with every character outside A-Za-z0-9 replaced by ->`; none is written or read when `CLAUDE_PLUGIN_DATA` is unset; markers older than seven days are deleted on each `--hook session-start`. A malformed file or a thrown error prints one line `workflow-guard: <reason>` on stderr and counts as no conflict. The guard never writes a settings file or `installed_plugins.json`.
- **C9 — stand-down check in bash hooks.** `scripts/lib/stand-down.sh` (dforge and dagents) defines `stand_down_active SESSION_ID`, status 0 when the C8 marker for that session exists, 1 otherwise or when `CLAUDE_PLUGIN_DATA` or the id is empty.
- **C10 — 4.x migration.** `dagents-migrate [--dry-run] [DIR]` keeps its 4.17.1 interface and exit codes and adds `.dforge/` → `.dagents/`, `docs/dforge/` → `docs/dagents/`, `<git dir>/dforge/` → `<git dir>/dagents/` as further older sources. Ignore and attributes lines naming `.dforge` or `docs/dforge` gain a dagents twin and are kept. `dforge:` prefixes in active plans and the handoff note become `dagents:`, and migrate stages every rewrite it makes in a tracked file (`git add`), so a moved and rewritten plan shows as a plain rename. A project with an active plan whose `### Task` headings carry no `**Implementer:**` line is refused with `dagents-migrate: refused: dforge 5 layout: not migratable (<plan>)` and nothing moves. A live run refuses that checkout: a lock directory under `<git common dir>/dforge/locks/` whose `host` file names this host and whose `pid` file names a running process, or an auto-run binding whose session is live. Refusals keep 4.17.1's form `dagents-migrate: refused: <reason>`; two tracked docs trees keep its `refused: <a> and <b> all exist` text.
- **C11 — the mods' guard line.** `guardLine(result, root)` — exported from `hooks/cockpit/lib.ts` in dforge and dagents and from `hooks/hud/band.mjs` in dflow — takes the standalone check's `{ exitCode, stdout }` (or `null` when it failed to start) and the plugin root; it returns `<plugin ids from stdout, joined by ", "> are enabled together; run node <root>/scripts/workflow-guard.mjs --host claude` when `exitCode` is 3, else `null`. A mod awaits the check through `$.process.run` before registering anything with a side effect, and when `guardLine` returns a line it renders only that line.
- **C12 — harness isolation.** `scripts/test-shards.mjs` exports `guardIsolation(env, dir)`: a copy of `env` with `WORKFLOW_GUARD_CLAUDE_DIR`, `WORKFLOW_GUARD_MANAGED_DIR` and `WORKFLOW_GUARD_PROJECT_DIR` set to `dir` where unset. `scripts/test-all.mjs` passes every job's environment through it with one empty temporary directory.

## Assumptions (evidence)

- Claude Code has no install or enable hook and no conflict field; SessionStart and the mod are the earliest points — code.claude.com/docs/en/plugins/manifest-reference.md and …/hooks.md, read 2026-11-16.
- SessionStart's `systemMessage` reaches the user — code.claude.com/docs/en/hooks.md (2026-11-17, by inference); unverified — Task 21 verifies it by hand in a nested session.
- Version 5's writing-plans writes no `**Implementer:**` line and 4.17.1's always does — `diff` of the bold labels in `skills/writing-plans/SKILL.md` between `dforge-v4.17.1` and `main`, run 2026-11-17.
- 283 commits touch `plugins/dforge/` since the tag; 127 are `fix`, 27 of them touch only non-test paths absent at the tag — `git rev-list` and `git diff-tree` run 2026-11-17 at `d85f6776`.
- The `DARKMEM_*` names 4.17.1 defines are `DARKMEM_API_KEY`, `DARKMEM_KILL_GRACE`, `DARKMEM_SYNC_LOCK_WAIT_MS`, `DARKMEM_SYNC_TIMEOUT_MS`; its `DR_*` names include the legacy `DR_FORGE_*` and `DR_SUPERPOWERS_*` translations — `git grep` at the tag, 2026-11-17.
- The renamed 4.17.1 tree passes its own suites once its baseline failures are dispositioned — unverified — Task 5 verifies it (the spec's riskiest assumption).
- The release workflow bumps dforge to 5.0.0 and tags dagents and dflow at 1.0.0 — `scripts/release.mjs:29-61`, read 2026-11-16.
- `installed_plugins.json` is `{"version": 2, "plugins": {"<name>@<marketplace>": [{"scope": "user"|"project"|"local", "projectPath"?, "installPath", "version", …}]}}` — this host's `~/.claude-alt/plugins/installed_plugins.json`, read 2026-11-17.
- Settings precedence is managed, then local, project, user; a plugin with no `enabledPlugins` entry is enabled by default; SessionStart hooks may return `systemMessage` and `hookSpecificOutput.additionalContext` — code.claude.com/docs/en/settings.md, …/plugins/manifest-reference.md and …/hooks.md, per the spec review of 2026-11-17.
- The per-OS managed-settings paths and the `managed-settings.d` drop-in in C8 — unverified — Task 20 verifies them against code.claude.com/docs/en/settings.md before writing the defaults.
- No identifier collides under the C3 map at the tag (no `DFORGE_X` beside a renamed `DR_X` or `DARKMEM_X`) — `comm` of the two name sets from `git grep` at `dforge-v4.17.1`, run 2026-11-17.
- 4.17.1 test helpers the plan's tests reuse: `dforge-migrate.test.sh` defines `check`, `exists`, `migrate`, `repo`, `$FM` and `$TMP`, and refuses two docs trees with `refused: <a> and <b> all exist` (lines 1-60, 496-498); `roots.test.sh` defines `$REPO`, `$TOP`, `$WT`, and `dforge_name_spellings` prints the key first (lines 24-29, 106-111; `lib/roots.sh:153-163`); `darkmem-sync/push.test.mjs` `setup` returns `stub`, `repo`, `seed`, `push`, `docsRoot`, `workRoot`, `env` (lines 10-23); `darkmem-sync/migrate.test.mjs` imports `createClient`, `startStub`, `STUB_KEY`, `sha` and `makeHome`, `makeRepo`, `read`, `run`, `scratch`, `write` (lines 1-9); `cockpit.test.ts` imports from `'../hooks/cockpit/lib'` (line 74); `next-step` prints ``Plan `<rel>` is complete.`` and `<done> of <total> tasks complete` (lines 384, 494); 4.17.1 locks live in `<git common dir>/dforge/locks/<name>.<key>/` with `host` and `pid` files (`lib/lock.sh:17-30, 147-148`) — `git show dforge-v4.17.1:<path>`, run 2026-11-17. After Task 5 every `dforge` in these names reads `dagents`.

## Task index

1. Copy dforge 4.17.1 into dagents and name it
2. Key test scheduling by suite path and add a plugin selector
3. Write the dagents rename script
4. Generalise the repository validator per plugin
5. Rename the copy and enroll dagents
6. Run dagents in CI behind a path filter
7. Build the backport register and its audit tool
8. Triage and port backport rows 1-36
9. Triage and port backport rows 37-72
10. Triage and port backport rows 73-108
11. Triage and port backport rows 109-144
12. Triage and port backport rows 145-180
13. Triage and port backport rows 181-216
14. Triage and port backport rows 217-252
15. Triage and port backport rows 253 to the end
16. Read dforge spellings as older ones in dagents
17. Isolate dagents' darkmem namespace
18. Migrate a dforge 4.x project's files
19. Migrate the home settings and darkmem data
20. Write the workflow guard
21. Stand dagents' hooks down under a conflict
22. Stand dagents' cockpit and Codex entry down
23. Stand dforge 5's hooks down under a conflict
24. Stand dforge 5's cockpit and Codex entry down and signpost dagents
25. Stand dflow down and check the guard copies
26. Prove dagents' isolation and feature set
27. Document the split and close the backport

---

### Task 1: Copy dforge 4.17.1 into dagents and name it

**Files:**
- Create: `plugins/dagents/**` (from the tag)
- Modify: `plugins/dagents/.claude-plugin/plugin.json`, `plugins/dagents/.codex-plugin/plugin.json`
- Create: `docs/dforge/notes/2026-11-17-dagents-baseline.md`

**Interfaces:**
- Consumes: none
- Produces: C1

**Items:** 2, 5

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 1 - coupling 0 - risk 1 = 3

- [ ] **Step 1: No new test, because the copy's correctness is the equality of two git trees, checked by command in Step 4, and no later commit can change the copy commit.**

- [ ] **Step 2: Create the branch and the copy**

Run: `git switch -c feat/dagents-split && git read-tree --prefix=plugins/dagents/ -u dforge-v4.17.1:plugins/dforge && git commit -q -m "chore(dagents): copy dforge 4.17.1"`

- [ ] **Step 3: Name the plugin**

In both manifests change only these fields: `name` to `dagents`; `version` to `1.0.0`; `description` (and the Codex manifest's `interface.shortDescription`) to `Brainstorm, plan and execute with scored tasks, implementer agents on a model ladder, subagent or inline execution, external Antigravity and Codex executors, criteria-based review and UI/UX work proven in the running UI; on Claude Code a cockpit pane shows the session, the run, context against its handoff budget and usage limits. Continues the dforge 4.x workflow.`; `homepage` to `https://github.com/darkraise/darkraise-ai-plugins/tree/main/plugins/dagents`; the Codex manifest's `interface.displayName` to `dagents`. Commit `feat(dagents): name the plugin dagents 1.0.0`.

Then record the copy's baseline: run every copied suite and write each exit code and suite path, one per line, into `docs/dforge/notes/2026-11-17-dagents-baseline.md` under a `## Before the rename` heading:

```bash
ls plugins/dagents/tests/*.test.sh plugins/dagents/tests/*.acceptance.sh | xargs -P 8 -I{} sh -c 'timeout 900 bash {} >/dev/null 2>&1; echo "$? {}"' | sort -k2
```

Commit the note with `docs(dagents): record the copy's suite baseline`.

- [ ] **Step 4: Verify**

Run: `test "$(git rev-parse HEAD~2:plugins/dagents)" = "$(git rev-parse dforge-v4.17.1:plugins/dforge)" && echo A1-ok && jq -r '.name+" "+.version' plugins/dagents/.claude-plugin/plugin.json plugins/dagents/.codex-plugin/plugin.json`
Expected: `A1-ok`, then `dagents 1.0.0` twice.

- [ ] **Step 5: Commit** — done in Steps 2 and 3.

### Task 2: Key test scheduling by suite path and add a plugin selector

**Files:**
- Modify: `scripts/test-shards.mjs`, `scripts/test-all.mjs`
- Test: `tests/test-shards.test.mjs`

**Interfaces:**
- Consumes: C1
- Produces: C2

**Items:** 2

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing tests** (append to `tests/test-shards.test.mjs`; change its `jobsWithLimits()` helper to `function jobsWithLimits(...args) { return list('--limits', ...args).map(line => { const [seconds, text] = line.split('\t'); return ['', text.split(' '), Number(seconds)]; }); }`)

```js
test('weights, limits and parts are keyed by repository path', () => {
  for (const table of [sched.windowsSeconds, sched.suiteSeconds, sched.suiteParts]) {
    for (const key of Object.keys(table)) assert.match(key, /^plugins\/[a-z0-9-]+\/tests\/[^/]+$/, key);
  }
});

test('two plugins may hold suites with one basename', () => {
  const jobs = [
    ['bash', ['plugins/dforge/tests/plan-lint.test.sh', 'one'], 1200],
    ['bash', ['plugins/dagents/tests/plan-lint.test.sh'], 600],
  ];
  const weights = { 'plugins/dforge/tests/plan-lint.test.sh': { one: 300 }, 'plugins/dagents/tests/plan-lint.test.sh': 100 };
  assert.deepEqual(sched.checkShellWeights(jobs, weights), []);
  assert.deepEqual(sched.checkShellWeights(jobs, { 'plugins/dforge/tests/plan-lint.test.sh': { one: 300 } }),
    ['plugins/dagents/tests/plan-lint.test.sh: no weight in scripts/test-shards.mjs; add it to windowsSeconds']);
});

test('the default run leaves dagents to its own run, and --plugin dagents runs only dagents', () => {
  assert.ok(list().every(line => !/plugins\/dagents(\/|$| )/.test(line)));
  const dagents = list('--plugin', 'dagents');
  assert.ok(dagents.length > 0);
  assert.ok(dagents.every(line => /plugins\/dagents(\/|$| )/.test(line)), dagents.join('\n'));
  const bad = spawnSync(process.execPath, [runner, '--list', '--plugin', 'nope'], { encoding: 'utf8', timeout: 10000 });
  assert.equal(bad.status, 2);
});

test('a dagents suite sharing a dforge basename keeps its own limit and parts', () => {
  const path = 'plugins/dagents/tests/plan-lint.test.sh';
  const lines = list('--limits', '--plugin', 'dagents').map(line => line.split('\t')).filter(([, text]) => text.startsWith(path));
  const expected = (sched.suiteParts[path] ?? [[]]).map(part => [path, ...part].join(' '));
  assert.deepEqual(lines.map(([, text]) => text), expected);
  for (const [seconds] of lines) assert.equal(Number(seconds), sched.suiteSeconds[path] ?? 600);
});

test('every dagents shell suite has a weight within 80% of its limit', () => {
  assert.deepEqual(sched.checkShellWeights(jobsWithLimits('--plugin', 'dagents')), []);
});
```

Re-key the file's existing weight tables to the new keys, since weights are now looked up by a job's full path: in `a suite with per-part weights schedules each part by its own weight` the weights become `{ 'plugins/dforge/tests/a.test.sh': { start: 700, verdict: 450, x: 100, y: 100 } }`; in `a shell suite needs a weight of at most 80% of its limit` every weights key `'a.test.sh'` becomes `'plugins/dforge/tests/a.test.sh'` (the `shell` helper already builds that path; the expected patterns stay, since the messages now carry the full path, which contains the old name).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 120 node --test tests/test-shards.test.mjs; timeout 60 node scripts/test-all.mjs --list | wc -l`
Expected: FAIL — `sched.suiteSeconds` is undefined and `--plugin` is an unknown option. Note the line count: the default run's job count, which Step 4 must reproduce.

- [ ] **Step 3: Implement**

1. Move `suiteSeconds` and `suiteParts` from `scripts/test-all.mjs` into `scripts/test-shards.mjs` as exports, and re-key them and `windowsSeconds` by repository path (`'plan-lint.test.sh'` → `'plugins/dforge/tests/plan-lint.test.sh'`, `'run-all.sh'` → `'plugins/dr-status/tests/run-all.sh'`). Keep every existing value.
2. In `selectShard` and `checkShellWeights`, name a job by `job[1][0]` instead of its basename; `checkShellWeights` accepts `^plugins\/[a-z0-9-]+\/tests\/[^/]+\.(test|acceptance)\.sh$` and the dr-status `run-all.sh`, and its messages use the path.
3. `scripts/test-all.mjs` gains `--plugin` (only `dagents` is accepted; any other value prints `test-all: --plugin takes dagents` and exits 2). The dforge job builder becomes a function of the plugin directory; without `--plugin` the job list is today's; with `--plugin dagents` it is dagents' shell suites (`plugins/dagents/tests/*.test.sh` and `*.acceptance.sh`, parts and limits from the path-keyed tables), `claude plugin test plugins/dagents` under the same `hasClaude` rule, and `tsc --noEmit -p plugins/dagents` when `plugins/dagents/tsconfig.json` and `plugins/dagents/.claude-plugin/types/tsconfig.json` exist and tsc runs.
4. Give every dagents shell suite a `windowsSeconds` entry. When the dagents suite declares an `ALL="..."` line naming exactly the parts of its dforge namesake's `suiteParts` entry, give it the same `suiteParts`, `suiteSeconds` and per-part weights under its own path. Otherwise give it one weight: the namesake's weight (the sum of its parts' weights when the namesake's entry is per-part), or 10 when it has no namesake; and when that weight exceeds 80% of 600, a `suiteSeconds` entry of `Math.ceil(weight / 0.8)`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 120 node --test tests/test-shards.test.mjs && timeout 60 node scripts/test-all.mjs --list | wc -l`
Expected: PASS; the line count equals the one Step 2 noted.

- [ ] **Step 5: Commit**

```bash
git add scripts/test-shards.mjs scripts/test-all.mjs tests/test-shards.test.mjs
git commit -m "feat(ci): key suites by path and select a plugin"
```

### Task 3: Write the dagents rename script

**Files:**
- Create: `scripts/dagents-rename.mjs`
- Test: `tests/dagents-rename.test.mjs`

**Interfaces:**
- Consumes: none
- Produces: C3

**Items:** 2

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

```js
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { renamePath, renameText } from '../scripts/dagents-rename.mjs';

const script = fileURLToPath(new URL('../scripts/dagents-rename.mjs', import.meta.url));
const run = (args, input) => spawnSync(process.execPath, [script, ...args], { encoding: 'utf8', input, timeout: 30000 });

test('identifiers take their dagents form', () => {
  for (const [from, to] of [
    ['use dforge:brainstorming', 'use dagents:brainstorming'],
    ['docs/dforge/plans and .dforge/sdd', 'docs/dagents/plans and .dagents/sdd'],
    ['~/.dforge/config.json and ~/.claude/dforge/sessions', '~/.dagents/config.json and ~/.claude/dagents/sessions'],
    ['${DFORGE_BUDGET:-}', '${DAGENTS_BUDGET:-}'],
    ['DR_CODEX_SESSION_DIR=x', 'DAGENTS_CODEX_SESSION_DIR=x'],
    ['DR_TEST_BASH DR_TEST_ALL', 'DR_TEST_BASH DR_TEST_ALL'],
    ['DR_FORGE_DOCUMENT_STORE DR_SUPERPOWERS_JQ', 'DR_FORGE_DOCUMENT_STORE DR_SUPERPOWERS_JQ'],
    ['ADDR_X', 'ADDR_X'],
    ['DARKMEM_API_KEY DARKMEM_URL', 'DARKMEM_API_KEY DARKMEM_URL'],
    ['DARKMEM_SYNC_LOCK_WAIT_MS', 'DAGENTS_DARKMEM_SYNC_LOCK_WAIT_MS'],
    ['Dforge and DFORGE', 'Dagents and DAGENTS'],
    ['off by default since dforge 3.0', 'off by default since dforge 3.0'],
    ['tag dforge-v4.17.1, dforge v4', 'tag dforge-v4.17.1, dforge v4'],
    ['plugins/dforge/scripts', 'plugins/dagents/scripts'],
  ]) assert.equal(renameText(from), to, from);
});

test('path components take their dagents form', () => {
  assert.equal(renamePath('skills/using-dforge/SKILL.md'), 'skills/using-dagents/SKILL.md');
  assert.equal(renamePath('scripts/lib/dforge-dir.sh'), 'scripts/lib/dagents-dir.sh');
  assert.equal(renamePath('tests/plan-lint.test.sh'), 'tests/plan-lint.test.sh');
});

test('tree renames contents and paths in place and refuses a collision', t => {
  const dir = mkdtempSync(join(tmpdir(), 'rename-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(join(dir, 'skills/using-dforge'), { recursive: true });
  mkdirSync(join(dir, 'scripts/lib'), { recursive: true });
  writeFileSync(join(dir, 'skills/using-dforge/SKILL.md'), 'name: using-dforge\n');
  writeFileSync(join(dir, 'scripts/dforge-path'), '. "$HERE/lib/dforge-dir.sh"\n');
  writeFileSync(join(dir, 'scripts/lib/dforge-dir.sh'), 'echo "${DFORGE_DOCS_ROOT:-docs/dforge}"\n');
  writeFileSync(join(dir, 'blob.bin'), Buffer.from([0x64, 0x66, 0x00, 0x6f]));
  const ok = run(['tree', dir]);
  assert.equal(ok.status, 0, ok.stderr);
  assert.equal(readFileSync(join(dir, 'skills/using-dagents/SKILL.md'), 'utf8'), 'name: using-dagents\n');
  assert.equal(readFileSync(join(dir, 'scripts/dagents-path'), 'utf8'), '. "$HERE/lib/dagents-dir.sh"\n');
  assert.equal(readFileSync(join(dir, 'scripts/lib/dagents-dir.sh'), 'utf8'), 'echo "${DAGENTS_DOCS_ROOT:-docs/dagents}"\n');
  assert.equal(existsSync(join(dir, 'skills/using-dforge')), false);
  assert.deepEqual([...readFileSync(join(dir, 'blob.bin'))], [0x64, 0x66, 0x00, 0x6f]);

  writeFileSync(join(dir, 'clash.sh'), 'echo "$DFORGE_LOCK_TENTHS $DR_LOCK_TENTHS"\n');
  const clash = run(['tree', dir]);
  assert.equal(clash.status, 1);
  assert.match(clash.stderr, /DFORGE_LOCK_TENTHS/);
  assert.match(clash.stderr, /DR_LOCK_TENTHS/);
});

test('patch translates paths and lines of a diff', () => {
  const diff = [
    'diff --git a/plugins/dforge/scripts/lib/roots.sh b/plugins/dforge/scripts/lib/roots.sh',
    '--- a/plugins/dforge/scripts/lib/roots.sh',
    '+++ b/plugins/dforge/scripts/lib/roots.sh',
    '@@ -1,2 +1,2 @@',
    ' . "$HERE/dforge-dir.sh"',
    '-echo "$DFORGE_DOCS_ROOT"',
    '+echo "${DFORGE_DOCS_ROOT:-docs/dforge}"',
    '',
  ].join('\n');
  const out = run(['patch'], diff);
  assert.equal(out.status, 0, out.stderr);
  assert.equal(out.stdout, [
    'diff --git a/plugins/dagents/scripts/lib/roots.sh b/plugins/dagents/scripts/lib/roots.sh',
    '--- a/plugins/dagents/scripts/lib/roots.sh',
    '+++ b/plugins/dagents/scripts/lib/roots.sh',
    '@@ -1,2 +1,2 @@',
    ' . "$HERE/dagents-dir.sh"',
    '-echo "$DAGENTS_DOCS_ROOT"',
    '+echo "${DAGENTS_DOCS_ROOT:-docs/dagents}"',
    '',
  ].join('\n'));
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 60 node --test tests/dagents-rename.test.mjs`
Expected: FAIL — cannot find module `../scripts/dagents-rename.mjs`.

- [ ] **Step 3: Implement**

1. `renameText(text)` applies the C3 map in its stated order; rule 4 is a guard, so a version-qualified `dforge` survives rule 5.
2. `renamePath(relPath)` applies `renameText` to each `/`-separated component.
3. `tree <dir>`: walk every file (skip `.git`); first compute every source-to-target name mapping across all text files (a "name" is a whole match of rules 1-3); exit 1 with `dagents-rename: <a> and <b> both become <target>` on stderr when two distinct sources map to one target, changing nothing; else rewrite each text file (no NUL byte) and rename paths deepest first.
4. `patch`: read stdin, apply `renameText` to every line (header, hunk and body lines alike), write stdout.
5. Any other argument prints a usage line and exits 2.

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 60 node --test tests/dagents-rename.test.mjs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add scripts/dagents-rename.mjs tests/dagents-rename.test.mjs
git commit -m "feat(dagents): add the rename script"
```

### Task 4: Generalise the repository validator per plugin

**Files:**
- Modify: `scripts/validate-repository.mjs`
- Test: `tests/repository-layout.test.mjs`

**Interfaces:**
- Consumes: C1
- Produces: C4

**Items:** 2

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6

- [ ] **Step 1: Write the failing tests** (append to `tests/repository-layout.test.mjs`; add `join` to its `node:path` import)

```js
test('a namespaced plugin resolves references within its own tree', async t => {
  const { validateRepository } = await import('../scripts/validate-repository.mjs');
  const dir = mkdtempSync(resolve(tmpdir(), 'ns-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  cpSync(root, dir, { recursive: true, filter: src => !/[\\/](\.git|node_modules|\.dforge|\.worktrees)([\\/]|$)/.test(src) });
  writeFileSync(resolve(dir, 'plugins/dagents/reference/stray.md'), 'see dagents:no-such-skill and dagents:brainstorming\n');
  const names = ['darkraise-ui', 'darkraise-win32ui', 'dflow', 'dforge', 'dr-status', 'dagents'];
  const errors = validateRepository(dir, { names });
  assert.ok(errors.includes('plugins/dagents/reference/stray.md:1: unresolved dagents reference no-such-skill'), errors.join('\n'));
  assert.ok(!errors.some(e => e.includes('dagents reference brainstorming')), errors.join('\n'));
});

test('the .dagents scratch directory is not swept', async t => {
  const { validateRepository } = await import('../scripts/validate-repository.mjs');
  const dir = mkdtempSync(resolve(tmpdir(), 'sweep-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  cpSync(root, dir, { recursive: true, filter: src => !/[\\/](\.git|node_modules|\.dforge|\.worktrees)([\\/]|$)/.test(src) });
  mkdirSync(resolve(dir, '.dagents'), { recursive: true });
  writeFileSync(resolve(dir, '.dagents/x.md'), 'dcc-darkraise\n');
  assert.ok(!validateRepository(dir).some(e => e.startsWith('.dagents/')));
});

test('each plugin schema names its own plugin as a target', async t => {
  const { validateSchema } = await import('../scripts/validate-repository.mjs');
  const dir = mkdtempSync(resolve(tmpdir(), 'schema-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(resolve(dir, 'plugins/probe/config'), { recursive: true });
  const entry = target => `export default { flag: { type: 'boolean', group: 'Workflow', title: 'Flag', description: 'A flag.', target: '${target}', label: 'Flag', default: false } };\n`;
  writeFileSync(resolve(dir, 'plugins/probe/config/schema.mjs'), entry('probe'));
  assert.deepEqual(await validateSchema(dir, 'probe'), []);
  writeFileSync(resolve(dir, 'plugins/probe/config/schema.mjs'), entry('dforge'));
  assert.deepEqual(await validateSchema(dir, 'probe'), ['schema flag: target must be probe or claude']);
  assert.deepEqual(await validateSchema(root), []);
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test tests/repository-layout.test.mjs`
Expected: FAIL — `validateRepository` ignores `names`, `.dagents` is swept, and `validateSchema` has no plugin argument (the second schema case reports `target must be dforge or claude`).

- [ ] **Step 3: Implement**

1. `validateRepository(root, { names } = {})`: the module-level `names` list becomes the default; every loop that reads it uses the argument. Catalog membership checks keep using the catalogs as they are.
2. The reference check runs for each plugin in `NAMESPACED = ['dforge', 'dagents']` present in `names`, matching `<plugin>:([a-z0-9-]+)` in that plugin's own tree and resolving under `plugins/<plugin>/`; the error text is C4's. A reference followed by `<` stays a placeholder.
3. Add `.dagents` to the unswept set.
4. `validateSchema(root, plugin = 'dforge')` reads `plugins/<plugin>/config/schema.mjs` and checks `target` against `[plugin, 'claude']`; the CLI block runs it for each listed plugin whose schema file exists.
5. Add `DAGENTS_DFORGE_ALLOWED` (initially `['plugins/dagents/README.md']`) and the two C4 dagents checks, applied only when `dagents` is in `names`; they are exercised from Task 5 on.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test tests/repository-layout.test.mjs && timeout 60 node scripts/validate-repository.mjs`
Expected: PASS, and the validator prints its success line.

- [ ] **Step 5: Commit**

```bash
git add scripts/validate-repository.mjs tests/repository-layout.test.mjs
git commit -m "feat(ci): validate references and schema per plugin"
```

### Task 5: Rename the copy and enroll dagents

**Files:**
- Modify: `plugins/dagents/**` (by `scripts/dagents-rename.mjs tree`, then baseline fixes)
- Modify: `.claude-plugin/marketplace.json`, `.agents/plugins/marketplace.json`
- Modify: `scripts/validate-repository.mjs`, `scripts/test-shards.mjs`
- Modify: `tests/repository-layout.test.mjs`
- Modify: `.gitignore`, `docs/dforge/notes/2026-11-17-dagents-baseline.md`

**Interfaces:**
- Consumes: C1, C2, C3, C4
- Produces: the enrolled dagents plugin every later task changes

**Items:** 2

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 1 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Extend the test `tests/repository-layout.test.mjs::Claude offers five maintained plugins`**

Replace the first three tests with:

```js
test('Claude offers six maintained plugins', () => {
  assert.deepEqual(json('.claude-plugin/marketplace.json').plugins.map(p => p.name).sort(),
    ['dagents', 'darkraise-ui', 'darkraise-win32ui', 'dflow', 'dforge', 'dr-status']);
});
test('Codex root discovery offers only supported plugins', () => {
  assert.ok(existsSync(resolve(root, '.agents/plugins/marketplace.json')), 'dedicated Codex catalog is required');
  assert.deepEqual(json('.agents/plugins/marketplace.json').plugins.map(p => p.name).sort(),
    ['dagents', 'darkraise-ui', 'darkraise-win32ui', 'dforge']);
});
test('Codex explicitly suppresses inherited Claude hooks', () => {
  for (const path of ['plugins/dforge/.codex-plugin/plugin.json', 'plugins/dagents/.codex-plugin/plugin.json']) {
    assert.ok(existsSync(resolve(root, path)), `${path} is required`);
    assert.deepEqual(json(path).hooks, {});
  }
});
```

and append:

```js
test('dagents spells dforge only where it must, and names only its 1.x version', async t => {
  const { validateRepository } = await import('../scripts/validate-repository.mjs');
  const dir = mkdtempSync(resolve(tmpdir(), 'dagents-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  cpSync(root, dir, { recursive: true, filter: src => !/[\\/](\.git|node_modules|\.dforge|\.worktrees)([\\/]|$)/.test(src) });
  assert.deepEqual(validateRepository(dir), []);
  writeFileSync(resolve(dir, 'plugins/dagents/reference/stray.md'), 'see docs/dforge/plans\nsince dagents 3.0\nsince dforge 3.0\n');
  const errors = validateRepository(dir);
  assert.ok(errors.includes('plugins/dagents/reference/stray.md:1: dforge name in dagents'), errors.join('\n'));
  assert.ok(errors.includes('plugins/dagents/reference/stray.md:2: dagents version other than 1.x'), errors.join('\n'));
  assert.ok(!errors.some(e => e.startsWith('plugins/dagents/reference/stray.md:3')), errors.join('\n'));
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test tests/repository-layout.test.mjs`
Expected: FAIL — the catalogs list five plugins and no dagents Codex manifest is checked.

- [ ] **Step 3: Implement**

1. Run `timeout 300 node scripts/dagents-rename.mjs tree plugins/dagents`; it must exit 0. Then add `dagents` to `names` in `scripts/validate-repository.mjs`, give it the Codex rules dforge has (explicit empty Codex hooks, no dependencies), and give dagents the retired-name allowlists dforge has, with each path passed through `renamePath`.
2. Add to `.claude-plugin/marketplace.json` `plugins`, after dforge:

```json
{
  "name": "dagents",
  "source": "./plugins/dagents",
  "description": "Brainstorm, plan and execute with scored tasks, implementer agents on a model ladder, subagent or inline execution, external Antigravity and Codex executors, criteria-based review and UI/UX work proven in the running UI; on Claude Code a cockpit pane shows the session, the run, context against its handoff budget and usage limits. Continues the dforge 4.x workflow.",
  "category": "workflow",
  "keywords": ["spec-driven", "planning", "subagents", "model-selection", "verification", "code-review", "codex", "external-executors", "mod", "context-window", "handoff"]
}
```

and to `.agents/plugins/marketplace.json` `plugins`, after dforge:

```json
{
  "policy": { "installation": "AVAILABLE", "authentication": "ON_USE" },
  "name": "dagents",
  "category": "Development",
  "source": { "source": "local", "path": "./plugins/dagents" }
}
```

3. Add `.dagents/` to `.gitignore` on the line after `.dforge/`.
4. Re-key `windowsSeconds` entries for dagents suites the rename renamed (`dforge-config.test.sh` → `dagents-config.test.sh`, `dforge-dir.test.sh`, `dforge-migrate.test.sh`, `dforge-state.test.sh`).
5. Write a short origin note at the top of `plugins/dagents/README.md` saying dagents continues dforge 4.17.1 (the one allowlisted file).
6. Run `timeout 1800 node scripts/test-all.mjs --plugin dagents` and record each failing suite under `## After the rename` in the baseline note. Disposition each: fix it in this task (a renamed string a test compares against Claude Code's own output, a pinned name), or drop the test case with a one-line reason in the note. Repeat until the run passes.
7. `timeout 120 claude plugin validate plugins/dagents` and `timeout 300 claude plugin test plugins/dagents` pass.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test tests/repository-layout.test.mjs && timeout 60 node scripts/validate-repository.mjs && timeout 1800 node scripts/test-all.mjs --plugin dagents`
Expected: PASS on all three.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/dagents .claude-plugin/marketplace.json .agents/plugins/marketplace.json scripts/validate-repository.mjs scripts/test-shards.mjs tests/repository-layout.test.mjs .gitignore docs/dforge/notes/2026-11-17-dagents-baseline.md
git commit -m "feat(dagents): rename the copy and enroll it"
```

### Task 6: Run dagents in CI behind a path filter

**Files:**
- Modify: `.github/workflows/validate.yml`
- Test: `tests/test-shards.test.mjs`

**Interfaces:**
- Consumes: C2
- Produces: the jobs `dagents-changes`, `validate-dagents` and `windows-dagents`

**Items:** 1

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6

- [ ] **Step 1: Write the failing tests** (append to `tests/test-shards.test.mjs`)

```js
test('dagents Windows shards cover every dagents suite exactly once', () => {
  const workflow = readFileSync(new URL('../.github/workflows/validate.yml', import.meta.url), 'utf8');
  const count = Number(/--plugin dagents --shard \$\{\{ matrix\.shard \}\}\/(\d+)/.exec(workflow)?.[1]);
  assert.ok(count > 0, 'validate.yml names the dagents shard count');
  const all = list('--plugin', 'dagents');
  const shards = Array.from({ length: count }, (_, i) => list('--plugin', 'dagents', '--shard', `${i + 1}/${count}`));
  assert.ok(shards.every(shard => shard.length > 0));
  assert.deepEqual(shards.flat().sort(), all.sort());
});

test('dagents jobs run only when dagents, scripts, tests or the workflow change', () => {
  const workflow = readFileSync(new URL('../.github/workflows/validate.yml', import.meta.url), 'utf8');
  assert.match(workflow, /^ {2}dagents-changes:$/m);
  assert.ok(workflow.includes('^(plugins/dagents/|scripts/|tests/|\\.github/workflows/validate\\.yml)'), 'the path filter');
  for (const job of ['validate-dagents', 'windows-dagents']) {
    const block = workflow.slice(workflow.indexOf(`  ${job}:`));
    assert.match(block.slice(0, 600), /needs\.dagents-changes\.outputs\.dagents == 'true'/, job);
  }
  assert.match(workflow, /\.name == "validate-dagents"/, 'the homelab wait job watches validate-dagents');
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 120 node --test tests/test-shards.test.mjs`
Expected: FAIL — validate.yml names no dagents shard count.

- [ ] **Step 3: Implement**

1. Measure: `time timeout 1800 node scripts/test-all.mjs --plugin dagents` on this host; set the dagents Linux bound to 1.5× that (seconds, at most 1050) and the Windows dagents shard count so that `selectShard` puts at most 1100 weighted seconds in any shard.
2. Add job `dagents-changes` on `ubuntu-latest` (checkout with `fetch-depth: 0`): for `workflow_dispatch` output `dagents=true`; for `push` diff `${{ github.event.before }}..${{ github.sha }}`, for `pull_request` diff the base sha to the head sha; output `dagents=true` when any changed path matches `^(plugins/dagents/|scripts/|tests/|\.github/workflows/validate\.yml)`, else `false`; an unreadable `before` (a new branch) outputs `true`.
3. Add job `validate-dagents` with the `validate` job's `runs-on` expression and `timeout-minutes`, `needs: dagents-changes`, `if: needs.dagents-changes.outputs.dagents == 'true'`; steps: checkout, setup-node 22, the prerequisites step, the Install Claude Code step (copied), `timeout 60s "$CLAUDE" plugin validate plugins/dagents`, `timeout 240s "$CLAUDE" plugin test plugins/dagents`, then `timeout --kill-after=10s <bound>s node scripts/test-all.mjs --plugin dagents`.
4. Add job `windows-dagents`, placed after the `windows` job, mirroring `windows` with `needs`/`if` as above and `node scripts/test-all.mjs --plugin dagents --shard ${{ matrix.shard }}/<count>`.
5. The `homelab` wait job selects `.name == "validate" or .name == "validate-dagents"` and succeeds once every selected job has left `queued`, `waiting` and `pending`, or has been skipped.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 120 node --test tests/test-shards.test.mjs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/validate.yml tests/test-shards.test.mjs
git commit -m "chore(ci): run dagents suites behind a path filter"
```

### Task 7: Build the backport register and its audit tool

**Files:**
- Create: `scripts/dagents-backport.mjs`
- Test: `tests/dagents-backport.test.mjs`
- Create: `docs/dforge/registers/2026-11-16-dagents-backport.md`

**Interfaces:**
- Consumes: none
- Produces: C5

**Items:** 4

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 1 = 6

- [ ] **Step 1: Write the failing test**

```js
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const script = fileURLToPath(new URL('../scripts/dagents-backport.mjs', import.meta.url));
const env = { ...process.env, GIT_AUTHOR_NAME: 't', GIT_AUTHOR_EMAIL: 't@e', GIT_COMMITTER_NAME: 't', GIT_COMMITTER_EMAIL: 't@e' };

function fixture(t) {
  const dir = mkdtempSync(join(tmpdir(), 'backport-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const git = (...args) => spawnSync('git', args, { cwd: dir, encoding: 'utf8', env, timeout: 30000 }).stdout.trim();
  const put = (path, text) => { mkdirSync(join(dir, path, '..'), { recursive: true }); writeFileSync(join(dir, path), text); };
  const commit = (message, files) => { for (const [p, text] of Object.entries(files)) put(p, text); git('add', '-A'); git('commit', '-q', '-m', message); return git('rev-parse', '--short=7', 'HEAD'); };
  git('init', '-q', '-b', 'main');
  commit('init', { 'plugins/dforge/a.sh': 'a\n' });
  git('tag', 'dforge-v4.17.1');
  const c1 = commit('fix(dforge): fix a', { 'plugins/dforge/a.sh': 'a2\n' });
  const c2 = commit('feat(dforge): add b', { 'plugins/dforge/b.sh': 'b\n' });
  const c3 = commit('fix(dforge): fix b', { 'plugins/dforge/b.sh': 'b2\n', 'plugins/dforge/tests/b.test.sh': 't\n' });
  commit('docs: readme', { 'README.md': 'r\n' });
  const port = commit('fix(dagents): fix a', { 'plugins/dagents/a.sh': 'a2\n' });
  return { dir, c1, c2, c3, port };
}
const run = (dir, ...args) => spawnSync(process.execPath, [script, ...args], { cwd: dir, encoding: 'utf8', env, timeout: 30000 });
const register = (rows) => ['# r', '', '**Source:** t', '**Covers:** -', '', '| # | Item | Assigned | Acceptance | State | Note |', '|---|---|---|---|---|---|',
  ...rows.map(([id, item, state, note]) => `| ${id} | ${item} | - | - | ${state} | ${note} |`), ''].join('\n');

test('rows lists the commits touching plugins/dforge in source order', t => {
  const f = fixture(t);
  const out = run(f.dir, 'rows', 'dforge-v4.17.1', 'HEAD');
  assert.equal(out.status, 0, out.stderr);
  assert.deepEqual(out.stdout.trim().split('\n'), [`${f.c1} fix(dforge): fix a`, `${f.c2} feat(dforge): add b`, `${f.c3} fix(dforge): fix b`]);
});

test('five-only checks every non-test path against the tag', t => {
  const f = fixture(t);
  assert.equal(run(f.dir, 'five-only', f.c1).status, 1);
  assert.equal(run(f.dir, 'five-only', f.c2).status, 0);
  assert.equal(run(f.dir, 'five-only', f.c3).status, 0);
});

test('audit accepts a finished register and names each problem', t => {
  const f = fixture(t);
  const file = join(f.dir, 'reg.md');
  const good = [
    [1, `${f.c1} fix(dforge): fix a`, 'done', `port ${f.port}; fail@parent pass@port`],
    [2, `${f.c2} feat(dforge): add b`, 'n/a', 'feature: adds b.sh'],
    [3, `${f.c3} fix(dforge): fix b`, 'n/a', '5-only'],
  ];
  writeFileSync(file, register(good));
  assert.equal(run(f.dir, 'audit', file, 'HEAD').status, 0);

  writeFileSync(file, register(good.slice(0, 2)));
  const missing = run(f.dir, 'audit', file, 'HEAD');
  assert.equal(missing.status, 1);
  assert.match(missing.stdout, new RegExp(`${f.c3}.*not a row`));
  assert.equal(run(f.dir, 'audit', file, 'HEAD', '--through', '2').status, 0);

  writeFileSync(file, register([[1, `${f.c1} fix(dforge): fix a`, 'n/a', '5-only'], ...good.slice(1)]));
  assert.match(run(f.dir, 'audit', file, 'HEAD').stdout, /row 1: 5-only fails the path check/);

  writeFileSync(file, register([[1, `${f.c1} fix(dforge): fix a`, 'done', 'port 0000000; fail@parent pass@port'], ...good.slice(1)]));
  assert.match(run(f.dir, 'audit', file, 'HEAD').stdout, /row 1: port 0000000 is not a dagents commit/);

  writeFileSync(file, register([[1, `${f.c1} fix(dforge): fix a`, 'open', '-'], ...good.slice(1)]));
  assert.match(run(f.dir, 'audit', file, 'HEAD').stdout, /row 1: not finished/);

  writeFileSync(file, register([good[0], [2, `${f.c2} feat(dforge): add b`, 'n/a', 'feature'], good[2]]));
  assert.match(run(f.dir, 'audit', file, 'HEAD').stdout, /row 2: feature needs a reason/);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 120 node --test tests/dagents-backport.test.mjs`
Expected: FAIL — the script does not exist.

- [ ] **Step 3: Implement**

1. `scripts/dagents-backport.mjs` implements C5's three subcommands, reading git through `execFileSync` with a 60-second timeout and the register table by its `| # | Item | … |` rows. Problem lines are `row <id>: <problem>` or `<sha7> <subject>: not a row`.
2. Create the register: write its header (`# dagents backport`, `**Source:** every dforge commit since dforge-v4.17.1, for docs/dforge/specs/2026-11-16-dagents-split-design.md §2`, `**Covers:** -`, the table header), then add a row per line of `node scripts/dagents-backport.mjs rows dforge-v4.17.1 main` with `bash plugins/dforge/scripts/register add docs/dforge/registers/2026-11-16-dagents-backport.md "<line>"`, and confirm with `bash plugins/dforge/scripts/register check docs/dforge/registers/2026-11-16-dagents-backport.md`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 120 node --test tests/dagents-backport.test.mjs && bash plugins/dforge/scripts/register check docs/dforge/registers/2026-11-16-dagents-backport.md`
Expected: PASS, and `register: 0 errors`; the register holds as many rows as `rows` prints.

- [ ] **Step 5: Commit**

```bash
git add scripts/dagents-backport.mjs tests/dagents-backport.test.mjs docs/dforge/registers/2026-11-16-dagents-backport.md
git commit -m "feat(dagents): add the backport register and audit"
```

### Task 8: Triage and port backport rows 1-36

**Files:**
- Modify: `plugins/dagents/**` (the files each ported fix touches; not enumerable before triage)
- Modify: `docs/dforge/registers/2026-11-16-dagents-backport.md`

**Interfaces:**
- Consumes: C3, C5
- Produces: finished rows 1-36

**Items:** 4

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 3 - spec 1 - coupling 1 - risk 2 = 7

- [ ] **Step 1: No new test, because each ported row brings the regression test its source commit carries (or a new one reproducing the defect when it shipped without one), run red at the port's parent and green at the port under A4, and a prose-only port earns none.**

- [ ] **Step 2: Triage each row, in order**

For row `<id>` with source `<sha>`: read `git show <sha>`. If `timeout 60 node scripts/dagents-backport.mjs five-only <sha>` exits 0, run `bash plugins/dforge/scripts/register set docs/dforge/registers/2026-11-16-dagents-backport.md <id> n/a --note "5-only"`; set every other `n/a` row with the same command and its own note. Otherwise decide, from the diff and the 4.17.1 code it touches in `plugins/dagents`, whether its defect exists in 4.17.1: a `port`, or `n/a` with `feature: …`, `test-only: …`, `docs-only: …`, `superseded by <sha7>: …` or `5-only: …`, each reason naming the code in one clause.

- [ ] **Step 3: Port each `port` row**

1. `PD=$(mktemp -d) && git show <sha> -- plugins/dforge | node scripts/dagents-rename.mjs patch > "$PD/port.diff"` (remove `$PD` once the row is finished).
2. Apply only the test hunks (`git apply --3way --include='plugins/dagents/tests/*' "$PD/port.diff"`, or write the reproducing test), run that suite under `timeout`, and confirm it fails. A port that adds a dagents shell suite also adds its `windowsSeconds` entry to `scripts/test-shards.mjs` (its Linux seconds, at most 80% of its limit).
3. Apply the rest (`git apply --3way "$PD/port.diff"`); where it does not apply because version 5 restructured the code, reimplement the same behaviour in the 4.17.1 structure. Run the suite: it passes.
4. Commit `fix(dagents): <source subject's description>` with body `Backport of <sha>.`; source commits fixing one defect may share one port commit. Run `bash plugins/dforge/scripts/register set docs/dforge/registers/2026-11-16-dagents-backport.md <id> done --note "port <sha7>; fail@parent pass@port"`, or with `--note "port <sha7>; text-only <path>"` for a prose-only port.

- [ ] **Step 4: Verify the range**

Run: `timeout 120 node scripts/dagents-backport.mjs audit docs/dforge/registers/2026-11-16-dagents-backport.md main --through 36 && timeout 120 node --test tests/test-shards.test.mjs && timeout 1800 node scripts/test-all.mjs --plugin dagents`
Expected: exit 0, then both test runs pass. A failure is bisected to its port commit and fixed there (`git commit --fixup` plus `git rebase --autosquash` on the unpushed branch) before Task 9.

- [ ] **Step 5: Commit** — the register: `git commit -m "docs(dagents): triage backport rows 1-36" docs/dforge/registers/2026-11-16-dagents-backport.md`.

### Task 9: Triage and port backport rows 37-72

**Files:**
- Modify: `plugins/dagents/**` (the files each ported fix touches; not enumerable before triage)
- Modify: `docs/dforge/registers/2026-11-16-dagents-backport.md`

**Interfaces:**
- Consumes: C3, C5
- Produces: finished rows 37-72

**Items:** 4

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 3 - spec 1 - coupling 1 - risk 2 = 7

- [ ] **Step 1: No new test, because each ported row brings the regression test its source commit carries (or a new one reproducing the defect when it shipped without one), run red at the port's parent and green at the port under A4, and a prose-only port earns none.**

- [ ] **Step 2: Triage each row, in order**

For row `<id>` with source `<sha>`: read `git show <sha>`. If `timeout 60 node scripts/dagents-backport.mjs five-only <sha>` exits 0, run `bash plugins/dforge/scripts/register set docs/dforge/registers/2026-11-16-dagents-backport.md <id> n/a --note "5-only"`; set every other `n/a` row with the same command and its own note. Otherwise decide, from the diff and the 4.17.1 code it touches in `plugins/dagents`, whether its defect exists in 4.17.1: a `port`, or `n/a` with `feature: …`, `test-only: …`, `docs-only: …`, `superseded by <sha7>: …` or `5-only: …`, each reason naming the code in one clause.

- [ ] **Step 3: Port each `port` row**

1. `PD=$(mktemp -d) && git show <sha> -- plugins/dforge | node scripts/dagents-rename.mjs patch > "$PD/port.diff"` (remove `$PD` once the row is finished).
2. Apply only the test hunks (`git apply --3way --include='plugins/dagents/tests/*' "$PD/port.diff"`, or write the reproducing test), run that suite under `timeout`, and confirm it fails. A port that adds a dagents shell suite also adds its `windowsSeconds` entry to `scripts/test-shards.mjs` (its Linux seconds, at most 80% of its limit).
3. Apply the rest (`git apply --3way "$PD/port.diff"`); where it does not apply because version 5 restructured the code, reimplement the same behaviour in the 4.17.1 structure. Run the suite: it passes.
4. Commit `fix(dagents): <source subject's description>` with body `Backport of <sha>.`; source commits fixing one defect may share one port commit. Run `bash plugins/dforge/scripts/register set docs/dforge/registers/2026-11-16-dagents-backport.md <id> done --note "port <sha7>; fail@parent pass@port"`, or with `--note "port <sha7>; text-only <path>"` for a prose-only port.

- [ ] **Step 4: Verify the range**

Run: `timeout 120 node scripts/dagents-backport.mjs audit docs/dforge/registers/2026-11-16-dagents-backport.md main --through 72 && timeout 120 node --test tests/test-shards.test.mjs && timeout 1800 node scripts/test-all.mjs --plugin dagents`
Expected: exit 0, then both test runs pass. A failure is bisected to its port commit and fixed there before Task 10.

- [ ] **Step 5: Commit** — the register: `git commit -m "docs(dagents): triage backport rows 37-72" docs/dforge/registers/2026-11-16-dagents-backport.md`.

### Task 10: Triage and port backport rows 73-108

**Files:**
- Modify: `plugins/dagents/**` (the files each ported fix touches; not enumerable before triage)
- Modify: `docs/dforge/registers/2026-11-16-dagents-backport.md`

**Interfaces:**
- Consumes: C3, C5
- Produces: finished rows 73-108

**Items:** 4

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 3 - spec 1 - coupling 1 - risk 2 = 7

- [ ] **Step 1: No new test, because each ported row brings the regression test its source commit carries (or a new one reproducing the defect when it shipped without one), run red at the port's parent and green at the port under A4, and a prose-only port earns none.**

- [ ] **Step 2: Triage each row, in order**

For row `<id>` with source `<sha>`: read `git show <sha>`. If `timeout 60 node scripts/dagents-backport.mjs five-only <sha>` exits 0, run `bash plugins/dforge/scripts/register set docs/dforge/registers/2026-11-16-dagents-backport.md <id> n/a --note "5-only"`; set every other `n/a` row with the same command and its own note. Otherwise decide, from the diff and the 4.17.1 code it touches in `plugins/dagents`, whether its defect exists in 4.17.1: a `port`, or `n/a` with `feature: …`, `test-only: …`, `docs-only: …`, `superseded by <sha7>: …` or `5-only: …`, each reason naming the code in one clause.

- [ ] **Step 3: Port each `port` row**

1. `PD=$(mktemp -d) && git show <sha> -- plugins/dforge | node scripts/dagents-rename.mjs patch > "$PD/port.diff"` (remove `$PD` once the row is finished).
2. Apply only the test hunks (`git apply --3way --include='plugins/dagents/tests/*' "$PD/port.diff"`, or write the reproducing test), run that suite under `timeout`, and confirm it fails. A port that adds a dagents shell suite also adds its `windowsSeconds` entry to `scripts/test-shards.mjs` (its Linux seconds, at most 80% of its limit).
3. Apply the rest (`git apply --3way "$PD/port.diff"`); where it does not apply because version 5 restructured the code, reimplement the same behaviour in the 4.17.1 structure. Run the suite: it passes.
4. Commit `fix(dagents): <source subject's description>` with body `Backport of <sha>.`; source commits fixing one defect may share one port commit. Run `bash plugins/dforge/scripts/register set docs/dforge/registers/2026-11-16-dagents-backport.md <id> done --note "port <sha7>; fail@parent pass@port"`, or with `--note "port <sha7>; text-only <path>"` for a prose-only port.

- [ ] **Step 4: Verify the range**

Run: `timeout 120 node scripts/dagents-backport.mjs audit docs/dforge/registers/2026-11-16-dagents-backport.md main --through 108 && timeout 120 node --test tests/test-shards.test.mjs && timeout 1800 node scripts/test-all.mjs --plugin dagents`
Expected: exit 0, then both test runs pass. A failure is bisected to its port commit and fixed there before Task 11.

- [ ] **Step 5: Commit** — the register: `git commit -m "docs(dagents): triage backport rows 73-108" docs/dforge/registers/2026-11-16-dagents-backport.md`.

### Task 11: Triage and port backport rows 109-144

**Files:**
- Modify: `plugins/dagents/**` (the files each ported fix touches; not enumerable before triage)
- Modify: `docs/dforge/registers/2026-11-16-dagents-backport.md`

**Interfaces:**
- Consumes: C3, C5
- Produces: finished rows 109-144

**Items:** 4

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 3 - spec 1 - coupling 1 - risk 2 = 7

- [ ] **Step 1: No new test, because each ported row brings the regression test its source commit carries (or a new one reproducing the defect when it shipped without one), run red at the port's parent and green at the port under A4, and a prose-only port earns none.**

- [ ] **Step 2: Triage each row, in order**

For row `<id>` with source `<sha>`: read `git show <sha>`. If `timeout 60 node scripts/dagents-backport.mjs five-only <sha>` exits 0, run `bash plugins/dforge/scripts/register set docs/dforge/registers/2026-11-16-dagents-backport.md <id> n/a --note "5-only"`; set every other `n/a` row with the same command and its own note. Otherwise decide, from the diff and the 4.17.1 code it touches in `plugins/dagents`, whether its defect exists in 4.17.1: a `port`, or `n/a` with `feature: …`, `test-only: …`, `docs-only: …`, `superseded by <sha7>: …` or `5-only: …`, each reason naming the code in one clause.

- [ ] **Step 3: Port each `port` row**

1. `PD=$(mktemp -d) && git show <sha> -- plugins/dforge | node scripts/dagents-rename.mjs patch > "$PD/port.diff"` (remove `$PD` once the row is finished).
2. Apply only the test hunks (`git apply --3way --include='plugins/dagents/tests/*' "$PD/port.diff"`, or write the reproducing test), run that suite under `timeout`, and confirm it fails. A port that adds a dagents shell suite also adds its `windowsSeconds` entry to `scripts/test-shards.mjs` (its Linux seconds, at most 80% of its limit).
3. Apply the rest (`git apply --3way "$PD/port.diff"`); where it does not apply because version 5 restructured the code, reimplement the same behaviour in the 4.17.1 structure. Run the suite: it passes.
4. Commit `fix(dagents): <source subject's description>` with body `Backport of <sha>.`; source commits fixing one defect may share one port commit. Run `bash plugins/dforge/scripts/register set docs/dforge/registers/2026-11-16-dagents-backport.md <id> done --note "port <sha7>; fail@parent pass@port"`, or with `--note "port <sha7>; text-only <path>"` for a prose-only port.

- [ ] **Step 4: Verify the range**

Run: `timeout 120 node scripts/dagents-backport.mjs audit docs/dforge/registers/2026-11-16-dagents-backport.md main --through 144 && timeout 120 node --test tests/test-shards.test.mjs && timeout 1800 node scripts/test-all.mjs --plugin dagents`
Expected: exit 0, then both test runs pass. A failure is bisected to its port commit and fixed there before Task 12.

- [ ] **Step 5: Commit** — the register: `git commit -m "docs(dagents): triage backport rows 109-144" docs/dforge/registers/2026-11-16-dagents-backport.md`.

### Task 12: Triage and port backport rows 145-180

**Files:**
- Modify: `plugins/dagents/**` (the files each ported fix touches; not enumerable before triage)
- Modify: `docs/dforge/registers/2026-11-16-dagents-backport.md`

**Interfaces:**
- Consumes: C3, C5
- Produces: finished rows 145-180

**Items:** 4

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 3 - spec 1 - coupling 1 - risk 2 = 7

- [ ] **Step 1: No new test, because each ported row brings the regression test its source commit carries (or a new one reproducing the defect when it shipped without one), run red at the port's parent and green at the port under A4, and a prose-only port earns none.**

- [ ] **Step 2: Triage each row, in order**

For row `<id>` with source `<sha>`: read `git show <sha>`. If `timeout 60 node scripts/dagents-backport.mjs five-only <sha>` exits 0, run `bash plugins/dforge/scripts/register set docs/dforge/registers/2026-11-16-dagents-backport.md <id> n/a --note "5-only"`; set every other `n/a` row with the same command and its own note. Otherwise decide, from the diff and the 4.17.1 code it touches in `plugins/dagents`, whether its defect exists in 4.17.1: a `port`, or `n/a` with `feature: …`, `test-only: …`, `docs-only: …`, `superseded by <sha7>: …` or `5-only: …`, each reason naming the code in one clause.

- [ ] **Step 3: Port each `port` row**

1. `PD=$(mktemp -d) && git show <sha> -- plugins/dforge | node scripts/dagents-rename.mjs patch > "$PD/port.diff"` (remove `$PD` once the row is finished).
2. Apply only the test hunks (`git apply --3way --include='plugins/dagents/tests/*' "$PD/port.diff"`, or write the reproducing test), run that suite under `timeout`, and confirm it fails. A port that adds a dagents shell suite also adds its `windowsSeconds` entry to `scripts/test-shards.mjs` (its Linux seconds, at most 80% of its limit).
3. Apply the rest (`git apply --3way "$PD/port.diff"`); where it does not apply because version 5 restructured the code, reimplement the same behaviour in the 4.17.1 structure. Run the suite: it passes.
4. Commit `fix(dagents): <source subject's description>` with body `Backport of <sha>.`; source commits fixing one defect may share one port commit. Run `bash plugins/dforge/scripts/register set docs/dforge/registers/2026-11-16-dagents-backport.md <id> done --note "port <sha7>; fail@parent pass@port"`, or with `--note "port <sha7>; text-only <path>"` for a prose-only port.

- [ ] **Step 4: Verify the range**

Run: `timeout 120 node scripts/dagents-backport.mjs audit docs/dforge/registers/2026-11-16-dagents-backport.md main --through 180 && timeout 120 node --test tests/test-shards.test.mjs && timeout 1800 node scripts/test-all.mjs --plugin dagents`
Expected: exit 0, then both test runs pass. A failure is bisected to its port commit and fixed there before Task 13.

- [ ] **Step 5: Commit** — the register: `git commit -m "docs(dagents): triage backport rows 145-180" docs/dforge/registers/2026-11-16-dagents-backport.md`.

### Task 13: Triage and port backport rows 181-216

**Files:**
- Modify: `plugins/dagents/**` (the files each ported fix touches; not enumerable before triage)
- Modify: `docs/dforge/registers/2026-11-16-dagents-backport.md`

**Interfaces:**
- Consumes: C3, C5
- Produces: finished rows 181-216

**Items:** 4

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 3 - spec 1 - coupling 1 - risk 2 = 7

- [ ] **Step 1: No new test, because each ported row brings the regression test its source commit carries (or a new one reproducing the defect when it shipped without one), run red at the port's parent and green at the port under A4, and a prose-only port earns none.**

- [ ] **Step 2: Triage each row, in order**

For row `<id>` with source `<sha>`: read `git show <sha>`. If `timeout 60 node scripts/dagents-backport.mjs five-only <sha>` exits 0, run `bash plugins/dforge/scripts/register set docs/dforge/registers/2026-11-16-dagents-backport.md <id> n/a --note "5-only"`; set every other `n/a` row with the same command and its own note. Otherwise decide, from the diff and the 4.17.1 code it touches in `plugins/dagents`, whether its defect exists in 4.17.1: a `port`, or `n/a` with `feature: …`, `test-only: …`, `docs-only: …`, `superseded by <sha7>: …` or `5-only: …`, each reason naming the code in one clause.

- [ ] **Step 3: Port each `port` row**

1. `PD=$(mktemp -d) && git show <sha> -- plugins/dforge | node scripts/dagents-rename.mjs patch > "$PD/port.diff"` (remove `$PD` once the row is finished).
2. Apply only the test hunks (`git apply --3way --include='plugins/dagents/tests/*' "$PD/port.diff"`, or write the reproducing test), run that suite under `timeout`, and confirm it fails. A port that adds a dagents shell suite also adds its `windowsSeconds` entry to `scripts/test-shards.mjs` (its Linux seconds, at most 80% of its limit).
3. Apply the rest (`git apply --3way "$PD/port.diff"`); where it does not apply because version 5 restructured the code, reimplement the same behaviour in the 4.17.1 structure. Run the suite: it passes.
4. Commit `fix(dagents): <source subject's description>` with body `Backport of <sha>.`; source commits fixing one defect may share one port commit. Run `bash plugins/dforge/scripts/register set docs/dforge/registers/2026-11-16-dagents-backport.md <id> done --note "port <sha7>; fail@parent pass@port"`, or with `--note "port <sha7>; text-only <path>"` for a prose-only port.

- [ ] **Step 4: Verify the range**

Run: `timeout 120 node scripts/dagents-backport.mjs audit docs/dforge/registers/2026-11-16-dagents-backport.md main --through 216 && timeout 120 node --test tests/test-shards.test.mjs && timeout 1800 node scripts/test-all.mjs --plugin dagents`
Expected: exit 0, then both test runs pass. A failure is bisected to its port commit and fixed there before Task 14.

- [ ] **Step 5: Commit** — the register: `git commit -m "docs(dagents): triage backport rows 181-216" docs/dforge/registers/2026-11-16-dagents-backport.md`.

### Task 14: Triage and port backport rows 217-252

**Files:**
- Modify: `plugins/dagents/**` (the files each ported fix touches; not enumerable before triage)
- Modify: `docs/dforge/registers/2026-11-16-dagents-backport.md`

**Interfaces:**
- Consumes: C3, C5
- Produces: finished rows 217-252

**Items:** 4

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 3 - spec 1 - coupling 1 - risk 2 = 7

- [ ] **Step 1: No new test, because each ported row brings the regression test its source commit carries (or a new one reproducing the defect when it shipped without one), run red at the port's parent and green at the port under A4, and a prose-only port earns none.**

- [ ] **Step 2: Triage each row, in order**

For row `<id>` with source `<sha>`: read `git show <sha>`. If `timeout 60 node scripts/dagents-backport.mjs five-only <sha>` exits 0, run `bash plugins/dforge/scripts/register set docs/dforge/registers/2026-11-16-dagents-backport.md <id> n/a --note "5-only"`; set every other `n/a` row with the same command and its own note. Otherwise decide, from the diff and the 4.17.1 code it touches in `plugins/dagents`, whether its defect exists in 4.17.1: a `port`, or `n/a` with `feature: …`, `test-only: …`, `docs-only: …`, `superseded by <sha7>: …` or `5-only: …`, each reason naming the code in one clause.

- [ ] **Step 3: Port each `port` row**

1. `PD=$(mktemp -d) && git show <sha> -- plugins/dforge | node scripts/dagents-rename.mjs patch > "$PD/port.diff"` (remove `$PD` once the row is finished).
2. Apply only the test hunks (`git apply --3way --include='plugins/dagents/tests/*' "$PD/port.diff"`, or write the reproducing test), run that suite under `timeout`, and confirm it fails. A port that adds a dagents shell suite also adds its `windowsSeconds` entry to `scripts/test-shards.mjs` (its Linux seconds, at most 80% of its limit).
3. Apply the rest (`git apply --3way "$PD/port.diff"`); where it does not apply because version 5 restructured the code, reimplement the same behaviour in the 4.17.1 structure. Run the suite: it passes.
4. Commit `fix(dagents): <source subject's description>` with body `Backport of <sha>.`; source commits fixing one defect may share one port commit. Run `bash plugins/dforge/scripts/register set docs/dforge/registers/2026-11-16-dagents-backport.md <id> done --note "port <sha7>; fail@parent pass@port"`, or with `--note "port <sha7>; text-only <path>"` for a prose-only port.

- [ ] **Step 4: Verify the range**

Run: `timeout 120 node scripts/dagents-backport.mjs audit docs/dforge/registers/2026-11-16-dagents-backport.md main --through 252 && timeout 120 node --test tests/test-shards.test.mjs && timeout 1800 node scripts/test-all.mjs --plugin dagents`
Expected: exit 0, then both test runs pass. A failure is bisected to its port commit and fixed there before Task 15.

- [ ] **Step 5: Commit** — the register: `git commit -m "docs(dagents): triage backport rows 217-252" docs/dforge/registers/2026-11-16-dagents-backport.md`.

### Task 15: Triage and port backport rows 253 to the end

**Files:**
- Modify: `plugins/dagents/**` (the files each ported fix touches; not enumerable before triage)
- Modify: `docs/dforge/registers/2026-11-16-dagents-backport.md`

**Interfaces:**
- Consumes: C3, C5
- Produces: every backport row finished

**Items:** 4

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 3 - spec 1 - coupling 1 - risk 2 = 7

- [ ] **Step 1: No new test, because each ported row brings the regression test its source commit carries (or a new one reproducing the defect when it shipped without one), run red at the port's parent and green at the port under A4, and a prose-only port earns none.**

- [ ] **Step 2: Refresh, then triage each row, in order**

First add a row for every line `node scripts/dagents-backport.mjs rows dforge-v4.17.1 main` prints that the register lacks (commits that landed on `main` since Task 7). Then, for each row from 253 on with source `<sha>`: read `git show <sha>`. If `timeout 60 node scripts/dagents-backport.mjs five-only <sha>` exits 0, run `bash plugins/dforge/scripts/register set docs/dforge/registers/2026-11-16-dagents-backport.md <id> n/a --note "5-only"`; set every other `n/a` row with the same command and its own note. Otherwise decide, from the diff and the 4.17.1 code it touches in `plugins/dagents`, whether its defect exists in 4.17.1: a `port`, or `n/a` with `feature: …`, `test-only: …`, `docs-only: …`, `superseded by <sha7>: …` or `5-only: …`, each reason naming the code in one clause.

- [ ] **Step 3: Port each `port` row**

1. `PD=$(mktemp -d) && git show <sha> -- plugins/dforge | node scripts/dagents-rename.mjs patch > "$PD/port.diff"` (remove `$PD` once the row is finished).
2. Apply only the test hunks (`git apply --3way --include='plugins/dagents/tests/*' "$PD/port.diff"`, or write the reproducing test), run that suite under `timeout`, and confirm it fails. A port that adds a dagents shell suite also adds its `windowsSeconds` entry to `scripts/test-shards.mjs` (its Linux seconds, at most 80% of its limit).
3. Apply the rest (`git apply --3way "$PD/port.diff"`); where it does not apply because version 5 restructured the code, reimplement the same behaviour in the 4.17.1 structure. Run the suite: it passes.
4. Commit `fix(dagents): <source subject's description>` with body `Backport of <sha>.`; source commits fixing one defect may share one port commit. Run `bash plugins/dforge/scripts/register set docs/dforge/registers/2026-11-16-dagents-backport.md <id> done --note "port <sha7>; fail@parent pass@port"`, or with `--note "port <sha7>; text-only <path>"` for a prose-only port.

- [ ] **Step 4: Verify every row**

Run: `timeout 120 node scripts/dagents-backport.mjs audit docs/dforge/registers/2026-11-16-dagents-backport.md main && timeout 120 node --test tests/test-shards.test.mjs && timeout 1800 node scripts/test-all.mjs --plugin dagents`
Expected: exit 0, then both test runs pass.

- [ ] **Step 5: Commit** — the register: `git commit -m "docs(dagents): finish the backport triage" docs/dforge/registers/2026-11-16-dagents-backport.md`.

### Task 16: Read dforge spellings as older ones in dagents

**Files:**
- Modify: `plugins/dagents/scripts/lib/roots.sh`, `plugins/dagents/scripts/lib/darkmem-mirror.mjs`, `plugins/dagents/scripts/lib/darkmem-sync.mjs`, `plugins/dagents/scripts/lib/darkmem-reconcile.mjs` (and every other list of older spellings `rg -n 'superpowers' plugins/dagents/scripts` finds)
- Modify: `scripts/validate-repository.mjs` (`DAGENTS_DFORGE_ALLOWED`)
- Test: `plugins/dagents/tests/roots.test.sh`

**Interfaces:**
- Consumes: C4
- Produces: C6

**Items:** 2

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Extend the test `plugins/dagents/tests/roots.test.sh`** (before its summary lines, using its `check <name> <got> <want>` helper and its repository `$TOP`)

```bash
# --- dforge 4.x citations read as an older spelling ---
check "dforge key" "$(dagents_name_key docs/dforge/plans/x.md)" "docs/dagents/plans/x.md"
check "dforge root key" "$(dagents_name_key docs/dforge)" "docs/dagents"
check "spellings: key, then dforge first" "$(dagents_name_spellings docs/dagents/plans/x.md | tr '\n' '|')" "docs/dagents/plans/x.md|docs/dforge/plans/x.md|docs/forge/plans/x.md|docs/superpowers/plans/x.md|"
check "dforge citation resolves" "$(cd "$TOP" && dagents_resolve docs/dforge/plans/x.md)" "$(cd "$TOP" && dagents_docs_root)/plans/x.md"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 600 bash plugins/dagents/tests/roots.test.sh`
Expected: FAIL — `dforge key` gets `docs/dforge/plans/x.md`.

- [ ] **Step 3: Implement**

1. In each list of older local spellings (`docs/forge`, `docs/superpowers`, `.forge`, `.superpowers` in `lib/roots.sh`, the mirror's local base list of worktree docs directories, sync's and reconcile's citation translations), add `docs/dforge` or `.dforge` as the first older spelling, with C6's output order (the key stays first). Never add `dforge` to a list from which a darkmem request uri, document prefix or workstream key is formed (`DOC_PREFIX`, `LEGACY_PREFIX` and their uses stay as they are).
2. Add every file this task changed to `DAGENTS_DFORGE_ALLOWED`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dagents/tests/roots.test.sh && timeout 600 bash plugins/dagents/tests/darkmem-sync.test.sh && timeout 60 node scripts/validate-repository.mjs`
Expected: PASS on all three; the existing roots cases, whose expected spellings gain the `docs/dforge` line, are updated to the C6 order.

- [ ] **Step 5: Commit**

```bash
git add plugins/dagents/scripts plugins/dagents/tests/roots.test.sh scripts/validate-repository.mjs
git commit -m "feat(dagents): read dforge spellings as older ones"
```

### Task 17: Isolate dagents' darkmem namespace

**Files:**
- Modify: `plugins/dagents/scripts/lib/darkmem-push.mjs`, `plugins/dagents/scripts/lib/darkmem-pull.mjs`, `plugins/dagents/scripts/lib/darkmem-sync.mjs` (wherever a workstream key is formed or matched)
- Test: `plugins/dagents/tests/darkmem-sync/push.test.mjs`

**Interfaces:**
- Consumes: none
- Produces: C7

**Items:** 2

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6

- [ ] **Step 1: Write the failing test** (append to `plugins/dagents/tests/darkmem-sync/push.test.mjs`, which already defines `setup`)

```js
test("dagents keeps to its own darkmem client, documents and workstreams on push and pull", async t => {
  const s = await setup(t);
  await s.seed.putDocument({ project: "proj", uri: "dforge/specs/old.md", content: "dforge's\n" });
  await s.seed.append({ project: "proj", workstream: "p1", entries: [{ kind: "ledger", body: "dforge's\n" }] });
  write(path.join(s.docsRoot, "specs", "a.md"), "# A\n");
  write(path.join(s.workRoot, "sdd", "p1", "progress.md"), "# SDD ledger — plan: docs/dagents/plans/p1.md\nTask 1: complete (abc)\n");
  const before = s.stub.db.requests.length;
  const pushed = await s.push();
  assert.equal(pushed.code, 0, pushed.stdout + pushed.stderr);
  const pulled = await run(["pull"], { cwd: s.repo, env: s.env });
  assert.equal(pulled.code, 0, pulled.stdout + pulled.stderr);
  for (const r of s.stub.db.requests.slice(before)) {
    if (r.body?.uri) assert.match(r.body.uri, /^dagents\//, JSON.stringify(r));
    if (r.body?.workstream) assert.match(r.body.workstream, /^dagents\//, JSON.stringify(r));
    if (r.query?.workstream) assert.match(r.query.workstream, /^dagents\//, JSON.stringify(r));
    if (r.body?.client) assert.equal(r.body.client, "dagents");
    assert.notEqual(r.method, "DELETE", JSON.stringify(r));
  }
  assert.ok(s.stub.db.workstreams.some(w => w.key === "dagents/p1"));
  assert.deepEqual(s.stub.db.workstreams.find(w => w.key === "p1").entries.map(e => e.body), ["dforge's\n"]);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 600 bash plugins/dagents/tests/darkmem-sync.test.sh`
Expected: FAIL — the ledger goes to workstream `p1`.

- [ ] **Step 3: Implement**

1. Form every workstream key dagents writes as `dagents/<slug>` and read only keys with that prefix (pull, resume and reconcile strip it back to the local slug). The `project` workstream becomes `dagents/project`.
2. Leave the client name and document prefix as the rename made them (`dagents`); confirm no request path or body names `dforge`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dagents/tests/darkmem-sync.test.sh`
Expected: PASS, the existing push, pull and reconcile tests included (their expected keys updated to the prefixed form where they name a workstream).

- [ ] **Step 5: Commit**

```bash
git add plugins/dagents/scripts/lib plugins/dagents/tests/darkmem-sync
git commit -m "feat(dagents): prefix its darkmem workstreams"
```

### Task 18: Migrate a dforge 4.x project's files

**Files:**
- Modify: `plugins/dagents/scripts/dagents-migrate`, `plugins/dagents/skills/migrate/SKILL.md`, `plugins/dagents/scripts/session-start.sh`, `plugins/dagents/scripts/repo-audit`
- Modify: `scripts/validate-repository.mjs` (`DAGENTS_DFORGE_ALLOWED`)
- Test: `plugins/dagents/tests/dagents-migrate.test.sh`

**Interfaces:**
- Consumes: C6
- Produces: C10

**Items:** 2

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 3 = 7
**Lenses:** silent-failures, lang-bash

- [ ] **Step 1: Write the failing test** (append to `plugins/dagents/tests/dagents-migrate.test.sh` before its summary lines; it uses the suite's `repo`, `migrate`, `check` and `exists` helpers and `$FM`)

```bash
# --- dforge 4.x: a primary checkout and a worktree move to the dagents names ---
D="$TMP/d4"
repo "$D"
mkdir -p "$D/.dforge/sdd/p1" "$D/docs/dforge/plans"
printf '# SDD ledger — plan: docs/dforge/plans/p1.md\nTask 1: complete (abc)\n' > "$D/.dforge/sdd/p1/progress.md"
printf '# P1\n\n### Task 1: one\n\n**Implementer:** dforge:impl-sonnet-low\n\n### Task 2: two\n\n**Implementer:** dforge:impl-sonnet-low\nuse dforge:executing-plans\n' > "$D/docs/dforge/plans/p1.md"
printf '# P0\n\n### Task 1: one\n\n**Implementer:** dforge:impl-sonnet-low\n' > "$D/docs/dforge/plans/p0.md"
printf -- '- docs/dforge/plans/p0.md\n' > "$D/docs/dforge/plans/completed.md"
printf '.dforge/\n' > "$D/.gitignore"
printf 'docs/dforge/** linguist-documentation\n' > "$D/.gitattributes"
printf 'see dforge:brainstorming\n' > "$D/CLAUDE.md"
git -C "$D" add .gitignore .gitattributes docs CLAUDE.md
git -C "$D" commit -q -m docs
DG=$(git -C "$D" rev-parse --absolute-git-dir)
mkdir -p "$DG/dforge/locks"
DW="$TMP/d4wt"
git -C "$D" worktree add -q -b feature "$DW"
mkdir -p "$DW/.dforge/handoff"
printf 'next: dforge:executing-plans\n' > "$DW/.dforge/handoff/latest.md"
DWG=$(git -C "$DW" rev-parse --absolute-git-dir)
mkdir -p "$DWG/dforge/tasks"
tree_of() { (cd "$1" && find . -path ./.git -prune -o -print | sort; cat .gitignore .gitattributes 2>/dev/null) | cksum; }
before=$(tree_of "$D")

dry=$(migrate "$FM" --dry-run "$D" 2>&1)
check "dforge dry run: nothing moved" "$(exists "$D/.dagents")$(exists "$D/docs/dagents")$(exists "$DW/.dagents")" "nonono"
check "dforge dry run: nothing rewritten" "$(tree_of "$D")" "$before"
out=$(migrate "$FM" "$D" 2>&1); code=$?
check "dforge: exit 0" "$code" "0"
check "dforge: ledger moved" "$(head -n 1 "$D/.dagents/sdd/p1/progress.md" 2>/dev/null)" "# SDD ledger — plan: docs/dforge/plans/p1.md"
check "dforge: docs moved and staged" "$(git -C "$D" status --porcelain -- docs | cut -c1-2 | sort -u | tr -d ' ')" "R"
check "dforge: git-dir state moved" "$(exists "$DG/dagents/locks")$(exists "$DG/dforge")" "yesno"
check "dforge worktree: state moved" "$(exists "$DW/.dagents/handoff/latest.md")$(exists "$DW/.dforge")" "yesno"
check "dforge worktree: handoff prefix rewritten" "$(cat "$DW/.dagents/handoff/latest.md")" "next: dagents:executing-plans"
check "dforge worktree: git-dir state moved" "$(exists "$DWG/dagents/tasks")$(exists "$DWG/dforge")" "yesno"
check "dforge: active plan prefixes rewritten" "$(grep -c 'dagents:' "$D/docs/dagents/plans/p1.md")" "3"
check "dforge: ignore twin added, original kept" "$(tr '\n' '|' < "$D/.gitignore")" ".dforge/|.dagents/|"
check "dforge: attributes twin added" "$(grep -c 'docs/dagents/\*\* linguist-documentation' "$D/.gitattributes")" "1"
check "dforge: CLAUDE.md reported, not rewritten" "$(cat "$D/CLAUDE.md")|$(printf '%s' "$out" | grep -c 'CLAUDE.md')" "see dforge:brainstorming|1"
again=$(migrate "$FM" "$D" 2>&1); check "dforge: a second run finds nothing" "$?" "0"

# --- A21: after the move, dforge citations still resolve ---
NS="$HERE/../scripts/next-step"
p0=$(cd "$D" && bash "$NS" docs/dagents/plans/p0.md 2>&1)
check "A21: the finished plan is finished" "$(printf '%s' "$p0" | grep -c 'Plan `docs/dagents/plans/p0.md` is complete.')" "1"
p1=$(cd "$D" && bash "$NS" docs/dagents/plans/p1.md 2>&1)
check "A21: the unfinished plan resumes at Task 2" "$(printf '%s' "$p1" | grep -c '1 of 2 tasks complete')" "1"

# --- a dforge 5 project is refused, a 4.x project opened under dforge 5 is not ---
F="$TMP/d5"
repo "$F"
mkdir -p "$F/docs/dforge/plans"
printf '# P\n\n### Task 1: one\n\nno implementer line\n' > "$F/docs/dforge/plans/p.md"
git -C "$F" add docs; git -C "$F" commit -q -m docs
out=$(migrate "$FM" "$F" 2>&1); code=$?
check "dforge 5: refused" "$code" "1"
check "dforge 5: says why" "$(printf '%s' "$out" | grep -c 'dforge 5 layout: not migratable (docs/dforge/plans/p.md)')" "1"
check "dforge 5: nothing moved" "$(exists "$F/docs/dagents")" "no"
G="$TMP/d4s"
repo "$G"
mkdir -p "$G/docs/dforge/plans" "$G/.dforge"
printf '# P\n\n### Task 1: one\n\n**Implementer:** dforge:impl-sonnet-low\n' > "$G/docs/dforge/plans/p.md"
echo state > "$G/.dforge/session-state.log"
git -C "$G" add docs; git -C "$G" commit -q -m docs
migrate "$FM" "$G" > /dev/null 2>&1; check "4.x opened under dforge 5: migrates" "$?$(exists "$G/docs/dagents/plans/p.md")" "0yes"

# --- per-item refusals, one fixture each ---
plan4='# P\n\n### Task 1: one\n\n**Implementer:** dforge:impl-sonnet-low\n'
fixture() { repo "$1"; mkdir -p "$1/docs/dforge/plans"; printf "$plan4" > "$1/docs/dforge/plans/p.md"; git -C "$1" add docs; git -C "$1" commit -q -m docs; }
H1="$TMP/r-differ"; fixture "$H1"
mkdir -p "$H1/.dforge/sdd/p" "$H1/.dagents/sdd/p"; echo old > "$H1/.dforge/sdd/p/progress.md"; echo new > "$H1/.dagents/sdd/p/progress.md"
out=$(migrate "$FM" "$H1" 2>&1); code=$?
check "differing same-path file: refused" "$code" "1"
check "differing file left in place" "$(cat "$H1/.dforge/sdd/p/progress.md")" "old"
check "the docs still moved" "$(exists "$H1/docs/dagents/plans/p.md")" "yes"
H2="$TMP/r-dirty"; fixture "$H2"
echo dirty >> "$H2/docs/dforge/plans/p.md"
migrate "$FM" "$H2" > /dev/null 2>&1; code=$?
check "dirty docs: refused" "$code" "1"
check "dirty docs: left in place" "$(exists "$H2/docs/dforge/plans/p.md")$(exists "$H2/docs/dagents")" "yesno"
H3="$TMP/r-two"; fixture "$H3"
mkdir -p "$H3/docs/dagents"; echo x > "$H3/docs/dagents/x.md"; git -C "$H3" add docs; git -C "$H3" commit -q -m two
out=$(migrate "$FM" "$H3" 2>&1); code=$?
check "two docs trees: refused" "$code" "1"
check "two docs trees: says why" "$(printf '%s' "$out" | grep -c "refused: .*docs/dforge.* all exist")" "1"
H4="$TMP/r-live"; fixture "$H4"
H4G=$(git -C "$H4" rev-parse --git-common-dir); case $H4G in /*) ;; *) H4G="$H4/$H4G" ;; esac
mkdir -p "$H4G/dforge/locks/run.abc"; uname -n > "$H4G/dforge/locks/run.abc/host"; echo "$$" > "$H4G/dforge/locks/run.abc/pid"
out=$(migrate "$FM" "$H4" 2>&1); code=$?
check "live run: refused" "$code" "1"
check "live run: nothing moved" "$(exists "$H4/docs/dagents")" "no"
echo 999999 > "$H4G/dforge/locks/run.abc/pid"
migrate "$FM" "$H4" > /dev/null 2>&1; check "dead pid: migrates" "$?$(exists "$H4/docs/dagents/plans/p.md")" "0yes"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 900 bash plugins/dagents/tests/dagents-migrate.test.sh`
Expected: FAIL — `.dforge` is not a migrate source.

- [ ] **Step 3: Implement**

1. In `dagents-migrate`, add `.dforge`, `docs/dforge` and `<git dir>/dforge` to the older sources of each move, using the existing per-item move, merge and refusal paths (the dirty check covers only paths migrate moves or rewrites).
2. For `.dforge` and `docs/dforge` ignore and attributes lines, append the dagents twin and keep the original (the older dr-forge and dr-superpowers lines keep today's replace behaviour). Stage every rewrite migrate makes in a tracked file.
3. Add `dforge:` to the prefixes rewritten in active plans and the handoff note; list other tracked files that mention `docs/dforge`, `.dforge` or `dforge:` on a `report:` line each, without changing them.
4. Before any move, refuse the checkout per C10 when an active plan (not in `completed.md`) has a `### Task` heading with no `**Implementer:**` line, and when dforge's locks or an auto-run binding are held by a live session; `.dforge/session-state.log` and other hook-written files are never markers.
5. The migrate skill, `session-start.sh` and `repo-audit` name `dforge 4.x layout found` when a project has `docs/dforge` or `.dforge` and no C10 marker; `session-start.sh` prints it only on its normal path, after the guard (a stood-down session prints nothing of it). Add the changed files to `DAGENTS_DFORGE_ALLOWED`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 900 bash plugins/dagents/tests/dagents-migrate.test.sh && timeout 60 node scripts/validate-repository.mjs`
Expected: PASS on both.

- [ ] **Step 5: Commit**

```bash
git add plugins/dagents scripts/validate-repository.mjs
git commit -m "feat(dagents): migrate a dforge 4.x project"
```

### Task 19: Migrate the home settings and darkmem data

**Files:**
- Modify: `plugins/dagents/scripts/lib/dagents-home-migrate.mjs`, `plugins/dagents/scripts/dagents-migrate`
- Modify: `scripts/validate-repository.mjs` (`DAGENTS_DFORGE_ALLOWED`)
- Test: `plugins/dagents/tests/darkmem-sync/migrate.test.mjs`

**Interfaces:**
- Consumes: C7, C10
- Produces: the per-repository home and darkmem step of C10

**Items:** 2

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 3 = 8
**Lenses:** silent-failures, security

- [ ] **Step 1: Write the failing test** (append to `plugins/dagents/tests/darkmem-sync/migrate.test.mjs`, which already imports `fs`, `path`, `createClient`, `startStub`, `STUB_KEY`, `makeRepo`, `read`, `run`, `scratch` and `write`; add `import { spawnSync } from "node:child_process";` and `import { fileURLToPath } from "node:url";` to its imports and this helper above the new tests)

```js
const MIGRATE = fileURLToPath(new URL("../../scripts/dagents-migrate", import.meta.url));
const runMigrate = (repo, env, ...args) => spawnSync(process.env.DR_TEST_BASH ?? "bash", [MIGRATE, ...args, repo], { cwd: repo, env, encoding: "utf8", timeout: 120000 });
```

The tests:

```js
test("a dforge 4.x project's home record and darkmem data move to dagents, and dforge keeps the rest", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const seed = createClient({ url: stub.url, apiKey: STUB_KEY, runKey: "seed" });
  const home = scratch("home-");
  const a = makeRepo(); const b = makeRepo();
  const dforgeHome = path.join(home, ".dforge");
  const mirrorA = path.join(dforgeHome, "mirror", "projA");
  write(path.join(dforgeHome, "config.json"), JSON.stringify({ autoRun: "off", darkmem: { url: stub.url, projects: { [a]: "projA", [b]: "projB" } } }));
  write(path.join(dforgeHome, "stores.json"), JSON.stringify({
    [a]: { documents: "darkmem", progress: "darkmem", project: "projA", mirror: mirrorA },
    [b]: { documents: "darkmem", progress: "darkmem", project: "projB", mirror: path.join(dforgeHome, "mirror", "projB") },
  }));
  write(path.join(mirrorA, "dforge", "plans", "p1.md"), "# P1\n");
  await seed.putDocument({ project: "projA", uri: "dforge/plans/p1.md", content: "# P1\n" });
  await seed.append({ project: "projA", workstream: "p1", entries: [{ kind: "ledger", body: "Task 1: complete (abc)\n" }] });
  const env = { ...process.env, HOME: home, DARKMEM_API_KEY: STUB_KEY, CLAUDE_CONFIG_DIR: "" };

  const out = runMigrate(a, env);
  assert.equal(out.status, 0, out.stdout + out.stderr);
  const dagentsConfig = JSON.parse(read(path.join(home, ".dagents", "config.json")));
  assert.equal(dagentsConfig.autoRun, "off");
  assert.equal(dagentsConfig.darkmem.projects[a], "projA");
  assert.equal(dagentsConfig.darkmem.projects[b], undefined);
  const dforgeStores = JSON.parse(read(path.join(dforgeHome, "stores.json")));
  assert.equal(dforgeStores[a], undefined);
  assert.equal(dforgeStores[b].project, "projB");
  assert.equal(JSON.parse(read(path.join(dforgeHome, "config.json"))).darkmem.projects[b], "projB");
  const dagentsStores = JSON.parse(read(path.join(home, ".dagents", "stores.json")));
  assert.match(dagentsStores[a].mirror, /\.dagents[\\/]mirror[\\/]projA$/);
  assert.equal(read(path.join(dagentsStores[a].mirror, "dagents", "plans", "p1.md")), "# P1\n");
  assert.ok(stub.db.workstreams.some(w => w.key === "dagents/p1"));
  assert.ok(stub.db.workstreams.some(w => w.key === "p1"), "the dforge workstream is kept");
  assert.ok(!stub.db.requests.some(r => r.method === "DELETE"));
  assert.match(out.stdout, /dforge\/ documents and workstreams were copied, not deleted; to delete them once no dforge checkout maps projA, run: /);

  const before = stub.db.requests.length;
  const sync = await run(["push"], { cwd: a, env: { ...env } });
  assert.equal(sync.code, 0, sync.stdout + sync.stderr);
  const after = stub.db.requests.slice(before);
  assert.ok(!after.some(r => r.method === "DELETE"));
  assert.ok(!after.some(r => r.method === "POST" && r.path === "/api/v1/documents"), "nothing is re-uploaded");
});

test("the migrate dry run lists the home steps and the variables to rename, and writes nothing", async t => {
  const stub = await startStub();
  t.after(() => stub.close());
  const home = scratch("home-");
  const a = makeRepo();
  write(path.join(home, ".dforge", "config.json"), JSON.stringify({ autoRun: "off", darkmem: { url: stub.url, projects: { [a]: "projA" } } }));
  write(path.join(home, ".dforge", "stores.json"), JSON.stringify({ [a]: { documents: "darkmem", progress: "darkmem", project: "projA", mirror: path.join(home, ".dforge", "mirror", "projA") } }));
  const env = { ...process.env, HOME: home, DARKMEM_API_KEY: STUB_KEY, CLAUDE_CONFIG_DIR: "", DFORGE_BUDGET: "200k" };
  const before = stub.db.requests.filter(r => r.method !== "GET").length;
  const out = runMigrate(a, env, "--dry-run");
  assert.equal(out.status, 0, out.stdout + out.stderr);
  assert.match(out.stdout, /DFORGE_BUDGET .*DAGENTS_BUDGET/);
  assert.equal(fs.existsSync(path.join(home, ".dagents")), false);
  assert.equal(JSON.parse(read(path.join(home, ".dforge", "stores.json")))[a].project, "projA");
  assert.equal(stub.db.requests.filter(r => r.method !== "GET").length, before);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 600 bash plugins/dagents/tests/darkmem-sync.test.sh`
Expected: FAIL — no `~/.dagents/config.json` is written.

- [ ] **Step 3: Implement**

1. In `dagents-home-migrate.mjs`, add a per-repository step for a repository `dagents-migrate` moved from dforge 4.x: copy into `~/.dagents/config.json` every key dagents' schema defines and this repository's darkmem mapping, never overwriting an existing dagents value; move this repository's `~/.dforge/stores.json` record into `~/.dagents/stores.json` and remove it from `~/.dforge/stores.json` under dforge's home lock; move its mirror to `~/.dagents/mirror/<project>` (copy instead while another `~/.dforge/stores.json` record names the same mirror), rewriting the mirror state's prefix and uris to `dagents`.
2. Copy the project's darkmem `dforge/…` documents to `dagents/…` and each workstream `<k>` to `dagents/<k>`, read every copy back and compare; on any mismatch stop and report, deleting nothing. Print the deletion-command line the test matches.
3. The dry run lists each of these steps and any set `DFORGE_*` or `DR_*` variable (process environment and Claude settings `env`) with its `DAGENTS_*` name, writing nothing. `~/.claude/dforge/` is not touched.
4. Add the changed files to `DAGENTS_DFORGE_ALLOWED`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 600 bash plugins/dagents/tests/darkmem-sync.test.sh && timeout 900 bash plugins/dagents/tests/dagents-migrate.test.sh && timeout 60 node scripts/validate-repository.mjs`
Expected: PASS on all three.

- [ ] **Step 5: Commit**

```bash
git add plugins/dagents scripts/validate-repository.mjs
git commit -m "feat(dagents): migrate home settings and darkmem"
```

### Task 20: Write the workflow guard

**Files:**
- Create: `plugins/dagents/scripts/workflow-guard.mjs`
- Test: `tests/workflow-guard.test.mjs`

**Interfaces:**
- Consumes: none
- Produces: C8

**Items:** 3

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Write the failing test**

```js
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, utimesSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const guard = fileURLToPath(new URL('../plugins/dagents/scripts/workflow-guard.mjs', import.meta.url));

function world(t) {
  const dir = mkdtempSync(join(tmpdir(), 'guard-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const claude = join(dir, 'claude'); const managed = join(dir, 'managed'); const project = join(dir, 'project'); const codex = join(dir, 'codex'); const data = join(dir, 'data');
  for (const d of [claude, managed, join(project, '.claude'), join(project, '.codex'), codex, data, join(claude, 'plugins')]) mkdirSync(d, { recursive: true });
  const json = (file, value) => writeFileSync(file, JSON.stringify(value));
  const installs = (entries) => json(join(claude, 'plugins/installed_plugins.json'), { version: 2, plugins: entries });
  const userInstall = name => ({ [`${name}@darkraise`]: [{ scope: 'user', installPath: '/x', version: '1' }] });
  const env = { ...process.env, WORKFLOW_GUARD_CLAUDE_DIR: claude, WORKFLOW_GUARD_MANAGED_DIR: managed, WORKFLOW_GUARD_PROJECT_DIR: project, CODEX_HOME: codex, CLAUDE_PLUGIN_DATA: data };
  const run = (args, input) => spawnSync(process.execPath, [guard, ...args], { encoding: 'utf8', env, input, timeout: 30000 });
  return { dir, claude, managed, project, codex, data, json, installs, userInstall, run };
}

test('one or no workflow plugin is no conflict; two are', t => {
  const w = world(t);
  w.installs({ ...w.userInstall('dforge'), ...w.userInstall('dagents') });
  w.json(join(w.claude, 'settings.json'), { enabledPlugins: { 'dforge@darkraise': true, 'dagents@darkraise': false } });
  const one = w.run(['--host', 'claude']);
  assert.equal(one.status, 0, one.stderr);
  assert.equal(one.stdout, 'dforge@darkraise user\n');
  w.json(join(w.claude, 'settings.json'), { enabledPlugins: { 'dforge@darkraise': true, 'dagents@darkraise': true } });
  const two = w.run(['--host', 'claude']);
  assert.equal(two.status, 3);
  assert.equal(two.stdout, 'dagents@darkraise user\ndforge@darkraise user\n');
});

test('scope precedence, defaults and installs decide what is active', t => {
  const w = world(t);
  w.installs({ ...w.userInstall('dforge'), ...w.userInstall('dagents'), 'dflow@darkraise': [{ scope: 'project', projectPath: '/elsewhere', installPath: '/x', version: '1' }] });
  w.json(join(w.claude, 'settings.json'), { enabledPlugins: { 'dforge@darkraise': true, 'dagents@darkraise': true, 'dflow@darkraise': true } });
  w.json(join(w.project, '.claude/settings.json'), { enabledPlugins: { 'dagents@darkraise': false } });
  assert.equal(w.run(['--host', 'claude']).stdout, 'dforge@darkraise user\n', 'project false wins; dflow is installed for another project');
  w.json(join(w.claude, 'settings.json'), {});
  assert.equal(w.run(['--host', 'claude']).stdout, 'dforge@darkraise default\n', 'installed with no entry anywhere is enabled');
  w.json(join(w.managed, 'managed-settings.json'), { enabledPlugins: { 'dforge@darkraise': false } });
  w.json(join(w.project, '.claude/settings.local.json'), { enabledPlugins: { 'dforge@darkraise': true } });
  assert.equal(w.run(['--host', 'claude']).stdout, '', 'managed false overrides every scope');
});

test('a malformed file gives one diagnostic and no conflict', t => {
  const w = world(t);
  w.installs({ ...w.userInstall('dforge'), ...w.userInstall('dagents') });
  writeFileSync(join(w.claude, 'settings.json'), '{ not json');
  const out = w.run(['--host', 'claude']);
  assert.equal(out.status, 0);
  assert.equal(out.stderr.trim().split('\n').length, 1);
  assert.match(out.stderr, /^workflow-guard: /);
});

test('the session-start hook returns the block for the user and the model, and keeps its marker in step', t => {
  const w = world(t);
  w.installs({ ...w.userInstall('dforge'), ...w.userInstall('dflow') });
  w.json(join(w.claude, 'settings.json'), { enabledPlugins: { 'dforge@darkraise': true } });
  w.json(join(w.project, '.claude/settings.json'), { enabledPlugins: { 'dflow@darkraise': true } });
  const event = JSON.stringify({ session_id: 'ab/c 1', hook_event_name: 'SessionStart', source: 'startup' });
  const marker = join(w.data, 'workflow-guard', 'ab-c-1');
  const hit = w.run(['--host', 'claude', '--self', 'dagents', '--hook', 'session-start'], event);
  assert.equal(hit.status, 3);
  const out = JSON.parse(hit.stdout);
  for (const text of [out.systemMessage, out.hookSpecificOutput.additionalContext]) {
    for (const name of ['dagents', 'dforge', 'dflow']) assert.match(text, new RegExp(`${name}@darkraise`));
    assert.ok(text.indexOf('claude plugin disable dforge@darkraise --scope local') < text.indexOf('claude plugin disable dforge@darkraise --scope user'));
    assert.match(text, /claude plugin disable dflow@darkraise --scope project/);
  }
  assert.equal(out.hookSpecificOutput.hookEventName, 'SessionStart');
  assert.ok(existsSync(marker));
  const old = join(w.data, 'workflow-guard', 'stale');
  writeFileSync(old, '');
  const past = (Date.now() - 8 * 86400 * 1000) / 1000;
  utimesSync(old, past, past);
  w.json(join(w.project, '.claude/settings.json'), { enabledPlugins: { 'dflow@darkraise': false } });
  w.json(join(w.claude, 'settings.json'), { enabledPlugins: { 'dforge@darkraise': false } });
  const clear = w.run(['--host', 'claude', '--self', 'dagents', '--hook', 'session-start'], event);
  assert.deepEqual([clear.status, clear.stdout], [0, '']);
  assert.equal(existsSync(marker), false, 'no conflict deletes the marker');
  assert.equal(existsSync(old), false, 'markers older than seven days are pruned');
});

test('the guard writes no settings file and no install record', t => {
  const w = world(t);
  w.installs({ ...w.userInstall('dforge'), ...w.userInstall('dagents') });
  w.json(join(w.claude, 'settings.json'), { enabledPlugins: { 'dforge@darkraise': true, 'dagents@darkraise': true } });
  const snapshot = () => [join(w.claude, 'settings.json'), join(w.claude, 'plugins/installed_plugins.json'), join(w.project, '.claude/settings.json')]
    .map(f => existsSync(f) ? `${statSync(f).mtimeMs}:${readFileSync(f, 'utf8')}` : 'absent');
  const before = snapshot();
  w.run(['--host', 'claude', '--self', 'dagents', '--hook', 'session-start'], JSON.stringify({ session_id: 's' }));
  w.run(['--host', 'claude']);
  assert.deepEqual(snapshot(), before);
});

test('Codex reads config.toml and never combines hosts', t => {
  const w = world(t);
  writeFileSync(join(w.codex, 'config.toml'), '[plugins."dforge@darkraise"]\nenabled = true\n\n[plugins."dagents@darkraise"]\nenabled = true\n');
  assert.equal(w.run(['--host', 'codex']).status, 3);
  writeFileSync(join(w.project, '.codex/config.toml'), '[plugins."dagents@darkraise"]\nenabled = false\n');
  assert.equal(w.run(['--host', 'codex']).status, 0, 'the project file wins');
  writeFileSync(join(w.codex, 'config.toml'), '[plugins."dagents@darkraise"]\nenabled = true\n');
  rmSync(join(w.project, '.codex/config.toml'));
  w.installs(w.userInstall('dforge'));
  w.json(join(w.claude, 'settings.json'), { enabledPlugins: { 'dforge@darkraise': true } });
  assert.equal(w.run(['--host', 'claude']).status, 0);
  assert.equal(w.run(['--host', 'codex']).status, 0);
  assert.equal(w.run([]).status, 2);
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 120 node --test tests/workflow-guard.test.mjs`
Expected: FAIL — the guard does not exist.

- [ ] **Step 3: Implement**

`plugins/dagents/scripts/workflow-guard.mjs`, one file with no imports beyond `node:` modules, implementing C8: the Claude scope walk (managed file plus `managed-settings.d/*.json` merged, then local, project, user, else `default`), the `installed_plugins.json` scope match (`user`, or `project`/`local` whose `projectPath` equals the project directory), the TOML subset reader for `[plugins."<id>"]` tables with an `enabled` boolean, the hook mode with its marker and pruning, and fail-open handling (`workflow-guard: <reason>` on stderr). Output lines are sorted by plugin name. The relay text added to `additionalContext` tells the model to show the block to the user and to use no skill of the listed plugins until one is disabled.

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 120 node --test tests/workflow-guard.test.mjs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dagents/scripts/workflow-guard.mjs tests/workflow-guard.test.mjs
git commit -m "feat(dagents): add the workflow guard"
```

### Task 21: Stand dagents' hooks down under a conflict

**Files:**
- Modify: `plugins/dagents/hooks/hooks.json`, `plugins/dagents/scripts/session-start.sh`, the other hook scripts `plugins/dagents/hooks/hooks.json` names
- Create: `plugins/dagents/scripts/lib/stand-down.sh`
- Modify: `scripts/test-all.mjs`, `scripts/test-shards.mjs`
- Test: `plugins/dagents/tests/stand-down.test.sh`, `tests/test-shards.test.mjs`

**Interfaces:**
- Consumes: C8
- Produces: C9, C12

**Items:** 3

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Write the failing test** (`plugins/dagents/tests/stand-down.test.sh`)

```bash
#!/usr/bin/env bash
# The guard's stand-down: a conflicted session start prints the block as JSON
# and every other hook stays silent; a fork runs the guard; a clean start
# leaves no marker.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HERE/.."
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); else printf 'FAIL - %s\n       got:  [%s]\n       want: [%s]\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" CLAUDE_PLUGIN_DATA="$TMP/data" CLAUDE_PLUGIN_ROOT="$ROOT"
export WORKFLOW_GUARD_CLAUDE_DIR="$TMP/claude" WORKFLOW_GUARD_MANAGED_DIR="$TMP/managed" WORKFLOW_GUARD_PROJECT_DIR="$TMP/project"
mkdir -p "$HOME" "$TMP/claude/plugins" "$TMP/managed" "$TMP/project/.claude"
git init -q "$TMP/project"
printf '{"version":2,"plugins":{"dforge@darkraise":[{"scope":"user","installPath":"/x","version":"5"}]}}' > "$TMP/claude/plugins/installed_plugins.json"
printf '{"enabledPlugins":{"dforge@darkraise":true}}' > "$TMP/claude/settings.json"
event() { printf '{"session_id":"s1","cwd":"%s","source":"%s","hook_event_name":"%s","transcript_path":"%s/t.jsonl","stop_hook_active":false}' "$TMP/project" "$1" "$2" "$TMP"; }

out=$(event startup SessionStart | (cd "$TMP/project" && bash "$ROOT/scripts/session-start.sh"))
check "conflict: JSON with a systemMessage" "$(printf '%s' "$out" | jq -r '.systemMessage | contains("dforge@darkraise")')" "true"
check "conflict: the model is told too" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext | contains("claude plugin disable dforge@darkraise --scope local")')" "true"
check "conflict: no dagents injection" "$(printf '%s' "$out" | grep -c 'using-dagents')" "0"
check "conflict: marker written" "$( [ -e "$TMP/data/workflow-guard/s1" ] && echo yes)" "yes"
for hook in $(jq -r '.hooks | to_entries[] | select(.key != "SessionStart") | .value[].hooks[].command' "$ROOT/hooks/hooks.json" | sed -E 's#^bash "\$\{CLAUDE_PLUGIN_ROOT\}/##; s#"$##'); do
  silent=$(event startup Stop | (cd "$TMP/project" && bash "$ROOT/$hook" 2>&1)); code=$?
  check "conflict: $hook is silent" "$code:$silent" "0:"
done
check "conflict: no transcript record" "$(ls "$HOME/.claude/dagents/sessions/by-id" 2>/dev/null | wc -l | tr -d ' ')" "0"

printf '{"enabledPlugins":{"dforge@darkraise":false}}' > "$TMP/claude/settings.json"
event startup SessionStart | (cd "$TMP/project" && bash "$ROOT/scripts/session-start.sh") > /dev/null
check "clean start: marker removed" "$( [ -e "$TMP/data/workflow-guard/s1" ] && echo yes || echo no)" "no"
check "the guard's matcher includes fork" "$(jq -r '.hooks.SessionStart[0].matcher' "$ROOT/hooks/hooks.json")" "startup|resume|clear|compact|fork"

printf '{"enabledPlugins":{"dforge@darkraise":true}}' > "$TMP/claude/settings.json"
out=$(printf '{"session_id":"s2","cwd":"%s","source":"fork","hook_event_name":"SessionStart"}' "$TMP/project" | (cd "$TMP/project" && bash "$ROOT/scripts/session-start.sh"))
check "fork: guard runs" "$( [ -e "$TMP/data/workflow-guard/s2" ] && echo yes)" "yes"

printf '{"enabledPlugins":{"dforge@darkraise":false}}' > "$TMP/claude/settings.json"
mkdir -p "$TMP/nonode"
for tool in bash sh cat jq git sed awk tr mkdir rm date grep head tail sort uname mktemp dirname basename printf wc cut env ls find cp mv touch stat od; do
  where=$(command -v "$tool" 2>/dev/null) && [ "$where" != "$(command -v node 2>/dev/null)" ] && ln -sf "$where" "$TMP/nonode/$tool"
done
with_node=$(event resume SessionStart | (cd "$TMP/project" && bash "$ROOT/scripts/session-start.sh" 2>/dev/null))
no_node_err=$( (event resume SessionStart | (cd "$TMP/project" && PATH="$TMP/nonode" bash "$ROOT/scripts/session-start.sh" >/dev/null)) 2>&1 )
check "node missing: no guard output on stderr" "$(printf '%s' "$no_node_err" | grep -c 'workflow-guard\|node: command not found')" "0"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

and append to `tests/test-shards.test.mjs`:

```js
test('jobs run with the guard isolated from the host', () => {
  const env = sched.guardIsolation({ CLAUDE_CONFIG_DIR: '/host', KEEP: 'x' }, '/empty');
  assert.deepEqual([env.WORKFLOW_GUARD_CLAUDE_DIR, env.WORKFLOW_GUARD_MANAGED_DIR, env.WORKFLOW_GUARD_PROJECT_DIR, env.KEEP], ['/empty', '/empty', '/empty', 'x']);
  assert.equal(sched.guardIsolation({ WORKFLOW_GUARD_CLAUDE_DIR: '/set' }, '/empty').WORKFLOW_GUARD_CLAUDE_DIR, '/set');
});
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 bash plugins/dagents/tests/stand-down.test.sh`
Expected: FAIL — session start prints the normal injection.

- [ ] **Step 3: Implement**

1. `scripts/lib/stand-down.sh` per C9.
2. `session-start.sh`: first, when node is on PATH, run `node "$CLAUDE_PLUGIN_ROOT/scripts/workflow-guard.mjs" --host claude --self dagents --hook session-start` with the hook's stdin; on exit 3 print its stdout and exit 0 before any other work (injection, darkmem reconcile and pull, the transcript record).
3. Every other hook script `hooks.json` names reads the session id the way it already does (or from stdin with `jq`) and exits 0 silently when `stand_down_active` succeeds, before any other work.
4. `hooks.json`: the SessionStart matcher becomes `startup|resume|clear|compact|fork`.
5. Add `guardIsolation` (C12) to `scripts/test-shards.mjs`; `scripts/test-all.mjs` creates one empty temporary directory, passes every job's environment through `guardIsolation`, and removes the directory when the run ends. So that a suite run alone is isolated too, every dagents suite that runs a hook script (`rg -l 'session-start.sh|turn-start.sh|turn-end.sh|ui-edit-hook.sh|ui-turn-end.sh|darkmem-stop-push.sh|impl-stop-gate' plugins/dagents/tests`) exports `WORKFLOW_GUARD_CLAUDE_DIR`, `WORKFLOW_GUARD_MANAGED_DIR` and `WORKFLOW_GUARD_PROJECT_DIR` to a fresh directory under its own temporary directory, on the line after it creates it, unless the suite sets them itself (as `stand-down.test.sh` does). The cockpit's tests need nothing: their `$.process.run` is a fake that never runs the guard.
6. Give `plugins/dagents/tests/stand-down.test.sh` a `windowsSeconds` entry of 20.
7. By hand, once: start a nested Claude Code session with both dagents and dforge enabled (see memory "Driving nested Claude smoke runs") and confirm the `systemMessage` shows; record the result in the baseline note under `## Guard message`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 bash plugins/dagents/tests/stand-down.test.sh && timeout 120 node --test tests/test-shards.test.mjs && timeout 1800 node scripts/test-all.mjs --plugin dagents`
Expected: PASS on all three.

- [ ] **Step 5: Commit**

```bash
git add plugins/dagents scripts/test-all.mjs scripts/test-shards.mjs tests/test-shards.test.mjs docs/dforge/notes/2026-11-17-dagents-baseline.md
git commit -m "feat(dagents): stand hooks down under a conflict"
```

### Task 22: Stand dagents' cockpit and Codex entry down

**Files:**
- Modify: `plugins/dagents/hooks/cockpit/register.tsx`, `plugins/dagents/hooks/cockpit/lib.ts`, `plugins/dagents/skills/using-dagents/references/codex-tools.md`, `plugins/dagents/README.md`
- Test: `plugins/dagents/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: C8
- Produces: C11 (dagents)

**Items:** 3

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6

- [ ] **Step 1: Write the failing test** (in `plugins/dagents/tests/cockpit.test.ts`, add `guardLine` to the import list from `'../hooks/cockpit/lib'` and append)

```ts
test('the guard line names the active plugins and the check, only on a conflict', () => {
  expect(guardLine({ exitCode: 3, stdout: 'dagents@darkraise self\ndforge@darkraise user\n' }, '/p'))
    .toBe('dagents@darkraise, dforge@darkraise are enabled together; run node /p/scripts/workflow-guard.mjs --host claude')
  expect(guardLine({ exitCode: 0, stdout: 'dagents@darkraise self\n' }, '/p')).toBe(null)
  expect(guardLine(null, '/p')).toBe(null)
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 claude plugin test plugins/dagents`
Expected: FAIL — `guardLine` is not exported.

- [ ] **Step 3: Implement**

1. Export `guardLine` (C11) from `hooks/cockpit/lib.ts`. At the top of the cockpit's registration, before any `on(…)`, timer, model-default save or auto-run binding, await `$.process.run(['node', `${$.plugin.root}/scripts/workflow-guard.mjs`, '--host', 'claude', '--self', 'dagents'], { timeoutMs: 5_000 })` (a run that fails to start passes `null`); when `guardLine` returns a line, register only a band that renders it, and return.
2. `codex-tools.md`: a first step telling the Codex session to run `node <plugin-root>/scripts/workflow-guard.mjs --host codex` before anything else and, on exit 3, to show its output and stop.
3. README: a "One workflow plugin at a time" section with the guard's behaviour, its blind spots (`--settings`, `--plugin-dir`, server-delivered settings, MDM/registry/plist policy, an untrusted Codex project file), that skills stay invocable when stood down, that a sibling older than its guard release does not stand down, and that on Codex the check runs only when the entry skill loads.

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 300 claude plugin test plugins/dagents`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dagents
git commit -m "feat(dagents): stand the cockpit down on a conflict"
```

### Task 23: Stand dforge 5's hooks down under a conflict

**Files:**
- Create: `plugins/dforge/scripts/workflow-guard.mjs` (copy of `plugins/dagents/scripts/workflow-guard.mjs`), `plugins/dforge/scripts/lib/stand-down.sh`
- Modify: `plugins/dforge/hooks/hooks.json`, `plugins/dforge/scripts/session-start.sh`, the other hook scripts it names, `scripts/test-shards.mjs`
- Test: `plugins/dforge/tests/stand-down.test.sh`

**Interfaces:**
- Consumes: C8, C9
- Produces: dforge's stand-down

**Items:** 3

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 1 - coupling 1 - risk 2 = 6

- [ ] **Step 1: Write the failing test** — `plugins/dforge/tests/stand-down.test.sh`, the Task 21 test with these differences: `ROOT` is dforge's, the enabled sibling is `dagents@darkraise` (install record and `enabledPlugins` name dagents), the injection check counts `using-dforge`, and the transcript check reads `$HOME/.claude/dforge/sessions/by-id`:

```bash
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HERE/.."
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); else printf 'FAIL - %s\n       got:  [%s]\n       want: [%s]\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" CLAUDE_PLUGIN_DATA="$TMP/data" CLAUDE_PLUGIN_ROOT="$ROOT"
export WORKFLOW_GUARD_CLAUDE_DIR="$TMP/claude" WORKFLOW_GUARD_MANAGED_DIR="$TMP/managed" WORKFLOW_GUARD_PROJECT_DIR="$TMP/project"
mkdir -p "$HOME" "$TMP/claude/plugins" "$TMP/managed" "$TMP/project/.claude"
git init -q "$TMP/project"
printf '{"version":2,"plugins":{"dagents@darkraise":[{"scope":"user","installPath":"/x","version":"1"}]}}' > "$TMP/claude/plugins/installed_plugins.json"
printf '{"enabledPlugins":{"dagents@darkraise":true}}' > "$TMP/claude/settings.json"
event() { printf '{"session_id":"s1","cwd":"%s","source":"%s","hook_event_name":"%s","transcript_path":"%s/t.jsonl","stop_hook_active":false}' "$TMP/project" "$1" "$2" "$TMP"; }

out=$(event startup SessionStart | (cd "$TMP/project" && bash "$ROOT/scripts/session-start.sh"))
check "conflict: JSON with a systemMessage" "$(printf '%s' "$out" | jq -r '.systemMessage | contains("dagents@darkraise")')" "true"
check "conflict: the model is told too" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext | contains("claude plugin disable dagents@darkraise --scope local")')" "true"
check "conflict: no dforge injection" "$(printf '%s' "$out" | grep -c 'using-dforge')" "0"
check "conflict: marker written" "$( [ -e "$TMP/data/workflow-guard/s1" ] && echo yes)" "yes"
for hook in $(jq -r '.hooks | to_entries[] | select(.key != "SessionStart") | .value[].hooks[].command' "$ROOT/hooks/hooks.json" | sed -E 's#^bash "\$\{CLAUDE_PLUGIN_ROOT\}/##; s#"$##'); do
  silent=$(event startup Stop | (cd "$TMP/project" && bash "$ROOT/$hook" 2>&1)); code=$?
  check "conflict: $hook is silent" "$code:$silent" "0:"
done
check "conflict: no transcript record" "$(ls "$HOME/.claude/dforge/sessions/by-id" 2>/dev/null | wc -l | tr -d ' ')" "0"
printf '{"enabledPlugins":{"dagents@darkraise":false}}' > "$TMP/claude/settings.json"
event startup SessionStart | (cd "$TMP/project" && bash "$ROOT/scripts/session-start.sh") > /dev/null
check "clean start: marker removed" "$( [ -e "$TMP/data/workflow-guard/s1" ] && echo yes || echo no)" "no"
check "the guard's matcher includes fork" "$(jq -r '.hooks.SessionStart[0].matcher' "$ROOT/hooks/hooks.json")" "startup|resume|clear|compact|fork"
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/stand-down.test.sh`
Expected: FAIL — dforge's session start prints its injection.

- [ ] **Step 3: Implement**

1. Copy `plugins/dagents/scripts/workflow-guard.mjs` byte for byte to `plugins/dforge/scripts/workflow-guard.mjs`, and add `plugins/dforge/scripts/lib/stand-down.sh` per C9.
2. `session-start.sh`: first, when node is on PATH, run `node "$CLAUDE_PLUGIN_ROOT/scripts/workflow-guard.mjs" --host claude --self dforge --hook session-start` with the hook's stdin; on exit 3 print its stdout and exit 0 before any other work (the injection, darkmem reconcile and pull, the transcript record).
3. Every other hook script `hooks.json` names reads the session id the way it already does (or from stdin with `jq`) and exits 0 silently when `stand_down_active` succeeds, before any other work.
4. `hooks.json`: the SessionStart matcher becomes `startup|resume|clear|compact|fork`.
5. Every dforge suite that runs a hook script (`rg -l 'session-start.sh|turn-start.sh|turn-end.sh|ui-edit-hook.sh|ui-turn-end.sh|darkmem-stop-push.sh|impl-stop-gate' plugins/dforge/tests`) exports the three `WORKFLOW_GUARD_*` variables to a fresh directory under its own temporary directory, on the line after it creates it, unless it sets them itself.
6. Give `plugins/dforge/tests/stand-down.test.sh` a `windowsSeconds` entry of 20.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 bash plugins/dforge/tests/stand-down.test.sh && timeout 1800 node scripts/test-all.mjs`
Expected: PASS on both; every existing dforge suite passes unchanged apart from the guard isolation (A17).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge scripts/test-shards.mjs
git commit -m "feat(dforge): stand hooks down under a conflict"
```

### Task 24: Stand dforge 5's cockpit and Codex entry down and signpost dagents

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx`, `plugins/dforge/hooks/cockpit/lib.ts`, `plugins/dforge/skills/using-dforge/references/codex-tools.md`, `plugins/dforge/README.md`, `plugins/dforge/scripts/plan-lint`
- Test: `plugins/dforge/tests/cockpit.test.ts`, `plugins/dforge/tests/plan-lint.test.sh`

**Interfaces:**
- Consumes: C8
- Produces: C11 (dforge) and the plan-lint signpost

**Items:** 1, 3

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Write the failing tests**

In `plugins/dforge/tests/cockpit.test.ts`, add `guardLine` to the import list from `'../hooks/cockpit/lib'` and append:

```ts
test('the guard line names the active plugins and the check, only on a conflict', () => {
  expect(guardLine({ exitCode: 3, stdout: 'dagents@darkraise user\ndforge@darkraise self\n' }, '/p'))
    .toBe('dagents@darkraise, dforge@darkraise are enabled together; run node /p/scripts/workflow-guard.mjs --host claude')
  expect(guardLine({ exitCode: 0, stdout: '' }, '/p')).toBe(null)
  expect(guardLine(null, '/p')).toBe(null)
})
```

In `plugins/dforge/tests/plan-lint.test.sh`, inside the `if want one; then` block, immediately before the `fi` that closes it (the line before `if want two; then`); the suite defines `LINT`, `TMP` and `check` above that block:

```bash
# --- the 4.x signposts name dagents ---
printf '# P\n\n**Goal:** g\n\n**Execution:** subagent — `claude --model sonnet --effort high` — legacy\n\n## Task index\n\n1. One\n\n---\n\n### Task 1: One\n\n**Files:**\n- Modify: `a.sh`\n' > "$TMP/signpost-sub.md"
sub=$(bash "$LINT" "$TMP/signpost-sub.md" 2>&1)
check "subagent error names dagents" "$(printf '%s' "$sub" | grep -q 'dagents.*/dagents:migrate' && echo yes || echo no)" "yes"
printf '# P\n\n**Goal:** g\n\n**Execution:** inline — `claude --model sonnet --effort low` — x\n\n## Task index\n\n1. One\n\n---\n\n### Task 1: One\n\n**Files:**\n- Modify: `a.sh`\n\n**Executor:** codex gpt-6.1-sol / low\n' > "$TMP/signpost-exe.md"
exe=$(bash "$LINT" "$TMP/signpost-exe.md" 2>&1)
check "Executor warning names dagents" "$(printf '%s' "$exe" | grep -q 'dagents.*/dagents:migrate' && echo yes || echo no)" "yes"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 claude plugin test plugins/dforge; timeout 1300 bash plugins/dforge/tests/plan-lint.test.sh one`
Expected: FAIL on both new cases.

- [ ] **Step 3: Implement**

1. Export `guardLine` (C11) from `hooks/cockpit/lib.ts`; at the top of the cockpit's registration, before any `on(…)`, timer, model-default save or auto-run binding, await `$.process.run(['node', `${$.plugin.root}/scripts/workflow-guard.mjs`, '--host', 'claude', '--self', 'dforge'], { timeoutMs: 5_000 })` (a run that fails to start passes `null`); when `guardLine` returns a line, register only a band that renders it, and return.
2. `codex-tools.md`: a first step telling the Codex session to run `node <plugin-root>/scripts/workflow-guard.mjs --host codex` before anything else and, on exit 3, to show its output and stop.
3. README: a "One workflow plugin at a time" section with the guard's behaviour, its blind spots (`--settings`, `--plugin-dir`, server-delivered settings, MDM/registry/plist policy, an untrusted Codex project file), that skills stay invocable when stood down, that a sibling older than its guard release does not stand down, and that on Codex the check runs only when the entry skill loads; plus one line: "The dforge 4.x agent workflow (implementer agents, subagent mode, external executors) continues as the dagents plugin."
4. `plan-lint`: append to the subagent-mode error and the Executor-line warning the clause ` — the 4.x agent workflow continues in the dagents plugin; run /dagents:migrate there`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 claude plugin test plugins/dforge && timeout 1300 bash plugins/dforge/tests/plan-lint.test.sh one`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge
git commit -m "feat(dforge): guard the cockpit and point to dagents"
```

### Task 25: Stand dflow down and check the guard copies

**Files:**
- Create: `plugins/dflow/scripts/workflow-guard.mjs` (copy)
- Modify: `plugins/dflow/hooks/hooks.json`, `plugins/dflow/lib/commands/hook.mjs`, `plugins/dflow/hooks/hud/register.tsx`, `plugins/dflow/hooks/hud/band.mjs`, `plugins/dflow/README.md`, `plugins/dflow/tests/helpers.mjs`
- Modify: `scripts/validate-repository.mjs`, `scripts/test-all.mjs`
- Test: `plugins/dflow/tests/hooks.test.mjs`, `plugins/dflow/tests/hud.test.mjs`, `tests/repository-layout.test.mjs`, `tests/guard-isolation.test.mjs`

**Interfaces:**
- Consumes: C8, C12
- Produces: C11 (dflow), dflow's stand-down and the C8 identity check

**Items:** 3

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Write the failing tests**

Append to `plugins/dflow/tests/hooks.test.mjs`:

```js
test('a conflicted session start returns the guard block and the other hooks stay silent', t => {
  const root = makeProject(t);
  const claude = fs.mkdtempSync(path.join(os.tmpdir(), 'guard-'));
  const data = fs.mkdtempSync(path.join(os.tmpdir(), 'data-'));
  t.after(() => { fs.rmSync(claude, { recursive: true, force: true }); fs.rmSync(data, { recursive: true, force: true }); });
  fs.mkdirSync(path.join(claude, 'plugins'));
  fs.writeFileSync(path.join(claude, 'plugins/installed_plugins.json'), JSON.stringify({ version: 2, plugins: { 'dforge@darkraise': [{ scope: 'user', installPath: '/x', version: '5' }] } }));
  fs.writeFileSync(path.join(claude, 'settings.json'), JSON.stringify({ enabledPlugins: { 'dforge@darkraise': true } }));
  const env = { WORKFLOW_GUARD_CLAUDE_DIR: claude, WORKFLOW_GUARD_MANAGED_DIR: claude, WORKFLOW_GUARD_PROJECT_DIR: root, CLAUDE_PLUGIN_DATA: data };
  const started = dflow(root, ['hook', 'session-start'], { input: event({ source: 'startup' }), env });
  assert.equal(started.status, 0);
  const out = JSON.parse(started.stdout);
  assert.match(out.systemMessage, /dforge@darkraise/);
  assert.match(out.hookSpecificOutput.additionalContext, /claude plugin disable dforge@darkraise --scope local/);
  const stopped = dflow(root, ['hook', 'stop'], { input: event({}), env });
  assert.deepEqual([stopped.status, stopped.stdout, stopped.stderr], [0, '', '']);
  const compact = dflow(root, ['hook', 'pre-compact'], { input: event({}), env });
  assert.deepEqual([compact.status, compact.stdout], [0, '']);
  assert.equal(JSON.parse(fs.readFileSync(path.join(PLUGIN, 'hooks/hooks.json'), 'utf8')).hooks.SessionStart[0].matcher, 'startup|resume|clear|compact|fork');
});
```

Append to `plugins/dflow/tests/hud.test.mjs` (importing `guardLine` from `'../hooks/hud/band.mjs'`):

```js
test('the HUD guard line names the active plugins and the check, only on a conflict', () => {
  assert.equal(guardLine({ exitCode: 3, stdout: 'dflow@darkraise self\ndforge@darkraise user\n' }, '/p'),
    'dflow@darkraise, dforge@darkraise are enabled together; run node /p/scripts/workflow-guard.mjs --host claude');
  assert.equal(guardLine({ exitCode: 0, stdout: '' }, '/p'), null);
  assert.equal(guardLine(null, '/p'), null);
});
```

Create `tests/guard-isolation.test.mjs` (A25), run by `scripts/test-all.mjs` as its own job with a 1200-second limit and left out of the root `tests/*.test.mjs` job:

```js
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const repoRoot = fileURLToPath(new URL('../', import.meta.url));

test('the hook suites pass, each run alone, under a host config that enables every sibling', t => {
  const dir = mkdtempSync(join(tmpdir(), 'host-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  mkdirSync(join(dir, 'plugins'), { recursive: true });
  const install = name => ({ [`${name}@darkraise`]: [{ scope: 'user', installPath: '/x', version: '1' }] });
  writeFileSync(join(dir, 'plugins/installed_plugins.json'), JSON.stringify({ version: 2, plugins: { ...install('dforge'), ...install('dagents'), ...install('dflow') } }));
  writeFileSync(join(dir, 'settings.json'), JSON.stringify({ enabledPlugins: { 'dforge@darkraise': true, 'dagents@darkraise': true, 'dflow@darkraise': true } }));
  const host = { ...process.env, CLAUDE_CONFIG_DIR: dir };
  for (const key of ['WORKFLOW_GUARD_CLAUDE_DIR', 'WORKFLOW_GUARD_MANAGED_DIR', 'WORKFLOW_GUARD_PROJECT_DIR']) delete host[key];
  for (const suite of ['plugins/dagents/tests/hook.test.sh', 'plugins/dforge/tests/hook.test.sh']) {
    const r = spawnSync(process.env.DR_TEST_BASH ?? 'bash', [suite], { cwd: repoRoot, env: host, encoding: 'utf8', timeout: 600000 });
    assert.equal(r.status, 0, `${suite}\n${(r.stdout ?? '').slice(-2000)}`);
  }
  const d = spawnSync(process.execPath, ['--test', 'plugins/dflow/tests/hooks.test.mjs'], { cwd: repoRoot, env: host, encoding: 'utf8', timeout: 300000 });
  assert.equal(d.status, 0, (d.stdout ?? '').slice(-2000));
});
```

Append to `tests/repository-layout.test.mjs`:

```js
test('the three workflow-guard copies are byte-identical', async t => {
  const { validateRepository } = await import('../scripts/validate-repository.mjs');
  const copies = ['dforge', 'dagents', 'dflow'].map(p => readFileSync(resolve(root, `plugins/${p}/scripts/workflow-guard.mjs`), 'utf8'));
  assert.ok(copies.every(c => c === copies[0]));
  const dir = mkdtempSync(resolve(tmpdir(), 'guard-copy-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  cpSync(root, dir, { recursive: true, filter: src => !/[\\/](\.git|node_modules|\.dforge|\.worktrees)([\\/]|$)/.test(src) });
  writeFileSync(resolve(dir, 'plugins/dflow/scripts/workflow-guard.mjs'), copies[0] + '\n// drift\n');
  assert.ok(validateRepository(dir).includes('plugins/dflow/scripts/workflow-guard.mjs: differs from plugins/dforge/scripts/workflow-guard.mjs'));
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 node --test plugins/dflow/tests/hooks.test.mjs plugins/dflow/tests/hud.test.mjs; timeout 300 node --test tests/repository-layout.test.mjs; timeout 1200 node --test tests/guard-isolation.test.mjs`
Expected: FAIL on the new dflow, copy-identity and A25 tests.

- [ ] **Step 3: Implement**

1. Copy `workflow-guard.mjs` byte for byte into `plugins/dflow/scripts/`.
2. `lib/commands/hook.mjs`: `session-start` first runs the guard (`--host claude --self dflow --hook session-start`, the event on stdin) as a child process with a 5-second timeout; on exit 3 it writes the guard's stdout and returns 0 before any other work. `pre-compact` and `stop` return 0 silently when the C8 marker for the event's session exists.
3. `hooks.json`: the SessionStart matcher becomes `startup|resume|clear|compact|fork`.
4. Export `guardLine` (C11) from `hooks/hud/band.mjs`; the HUD mod awaits `$.process.run(['node', `${$.plugin.root}/scripts/workflow-guard.mjs`, '--host', 'claude', '--self', 'dflow'], { timeoutMs: 5_000 })` before registering anything with a side effect, and when `guardLine` returns a line renders only that line.
5. `tests/helpers.mjs`: `dflow()` and `dflowAsync()` set the three `WORKFLOW_GUARD_*` variables to an empty temporary directory unless the caller's `env` sets them.
6. `validate-repository.mjs`: compare the three copies and report `plugins/<p>/scripts/workflow-guard.mjs: differs from plugins/dforge/scripts/workflow-guard.mjs`.
7. README: a "One workflow plugin at a time" section with the guard's behaviour, its blind spots (`--settings`, `--plugin-dir`, server-delivered settings, MDM/registry/plist policy), that skills stay invocable when stood down, and that a sibling older than its guard release does not stand down.
8. `scripts/test-all.mjs`: leave `tests/guard-isolation.test.mjs` out of the root `tests/*.test.mjs` job and run it as its own job, `[process.execPath, ['--test', 'tests/guard-isolation.test.mjs'], 1200]`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 node --test plugins/dflow/tests/*.test.mjs && timeout 300 node --test tests/repository-layout.test.mjs && timeout 1200 node --test tests/guard-isolation.test.mjs && timeout 120 node --test tests/test-shards.test.mjs && timeout 180 claude plugin test plugins/dflow`
Expected: PASS on all four.

- [ ] **Step 5: Commit**

```bash
git add plugins/dflow scripts/validate-repository.mjs scripts/test-all.mjs tests/repository-layout.test.mjs tests/guard-isolation.test.mjs
git commit -m "feat(dflow): stand down when another workflow runs"
```

### Task 26: Prove dagents' isolation and feature set

**Files:**
- Test: `plugins/dagents/tests/isolation.acceptance.test.sh`
- Modify: `scripts/test-shards.mjs` (its weight)

**Interfaces:**
- Consumes: C3, C6, C7, C9
- Produces: none

**Items:** 2

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 1 = 5

- [ ] **Step 1: Write the failing test** (`plugins/dagents/tests/isolation.acceptance.test.sh`)

```bash
#!/usr/bin/env bash
# A5 and A7: dagents keeps 4.17.1's feature set without version 5's, and a
# full cycle neither touches nor reads dforge's names.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); else printf 'FAIL - %s\n       got:  [%s]\n       want: [%s]\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi; }

# --- A5: the feature set ---
want=$(git -C "$REPO" ls-tree --name-only dforge-v4.17.1:plugins/dforge/agents | sed 's/dforge/dagents/g' | sort | tr '\n' ' ')
check "agent set equals the tag's" "$(ls "$ROOT/agents" | sort | tr '\n' ' ')" "$want"
for skill in subagent-driven-development revising-plans; do
  check "skill $skill present" "$( [ -f "$ROOT/skills/$skill/SKILL.md" ] && echo yes)" "yes"
done
check "Executor-line routing present" "$(grep -l '\*\*Executor:\*\*' "$ROOT/scripts/plan-lint" "$ROOT/scripts/task-step" 2>/dev/null | wc -l | tr -d ' ')" "2"
for absent in scripts/run-review-panel scripts/task-close scripts/api-judge scripts/lib/session-state.sh; do
  check "no version-5 $absent" "$( [ -e "$ROOT/$absent" ] && echo present || echo absent)" "absent"
done

# --- A7: a full cycle in a temporary project and home ---
cycle() { # cycle LABEL — run the cycle; print a listing of dforge-named paths and the output
  local T; T="$(mktemp -d)"
  export HOME="$T/home"; mkdir -p "$HOME"
  export WORKFLOW_GUARD_CLAUDE_DIR="$T/c" WORKFLOW_GUARD_MANAGED_DIR="$T/c" WORKFLOW_GUARD_PROJECT_DIR="$T/p"
  git init -q -b main "$T/p"; git -C "$T/p" commit -q --allow-empty -m init
  if [ "$1" = seeded ]; then
    mkdir -p "$HOME/.dforge" "$T/p/.dforge/sdd/p"
    printf '{"autoRun":"off","handoffBudget":1,"darkmem":{"url":"http://127.0.0.1:9","projects":{"%s":"projP"}}}' "$T/p" > "$HOME/.dforge/config.json"
    echo 'Task 1: complete (abc)' > "$T/p/.dforge/sdd/p/progress.md"
    export DFORGE_BUDGET=1 DR_CODEX_SESSION_DIR="$T/elsewhere"
  fi
  sleep 1
  mkdir -p "$T/p/docs/dagents/plans"
  printf '# P\n\n**Execution:** inline — `claude --model sonnet --effort low` — x\n\n### Task 1: one\n\n**Implementer:** dagents:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0\n' > "$T/p/docs/dagents/plans/p.md"
  local ev='{"session_id":"s","source":"startup","hook_event_name":"SessionStart","cwd":"'"$T/p"'"}'
  local out
  out=$( cd "$T/p" && printf '%s' "$ev" | bash "$ROOT/scripts/session-start.sh" 2>&1 | grep -v 'dforge 4.x layout found'
         bash "$ROOT/scripts/task-brief" docs/dagents/plans/p.md 1 2>&1 | grep -v '^budget'
         bash "$ROOT/scripts/next-step" docs/dagents/plans/p.md 2>&1
         printf '%s' "$ev" | bash "$ROOT/scripts/turn-end.sh" 2>&1 )
  unset DFORGE_BUDGET DR_CODEX_SESSION_DIR
  printf '%s\n' "$out" | sed "s#$T#T#g"
  find "$T" -name '*dforge*' -newer "$T/p/docs/dagents/plans/p.md" | sed "s#$T#T#g"
  rm -rf "$T"
}
plain=$(cycle plain)
check "no dforge-named path is created" "$(printf '%s' "$plain" | grep -c '^T/.*dforge')" "0"
seeded=$(cycle seeded)
check "seeded dforge state and variables change nothing" "$seeded" "$plain"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test**

Run: `timeout 900 bash plugins/dagents/tests/isolation.acceptance.test.sh; timeout 120 node --test tests/test-shards.test.mjs`
Expected: the suite passes unless a leak remains (each failing `check` names one); the shard test FAILS — the new suite has no `windowsSeconds` entry.

- [ ] **Step 3: Implement** — fix every leak the test names in the dagents file that causes it (a remaining dforge path or variable read); give the suite a `windowsSeconds` entry from its measured Linux time.

- [ ] **Step 4: Run the test to verify it passes**

Run: `timeout 900 bash plugins/dagents/tests/isolation.acceptance.test.sh && timeout 120 node --test tests/test-shards.test.mjs`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add plugins/dagents scripts/test-shards.mjs
git commit -m "test(dagents): prove isolation and the 4.x set"
```

### Task 27: Document the split and close the backport

**Files:**
- Modify: `README.md`, `docs/migration.md`, `CLAUDE.md`
- Modify: `docs/dforge/registers/2026-11-16-dagents-split.md`, `docs/dforge/registers/2026-11-16-dagents-backport.md`

**Interfaces:**
- Consumes: C5
- Produces: none

**Items:** 1, 4

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 1 - coupling 1 - risk 1 = 5

- [ ] **Step 1: No new test, because this task changes prose no script reads and the backport audit, release dry run and validator it runs are existing checks (`tests/dagents-backport.test.mjs`, `tests/release.test.mjs`).**

- [ ] **Step 2: Write the documents**

1. Root `README.md`: a dagents row in the plugin table beside dforge and dflow, and a note that dforge, dagents and dflow are alternatives of which only one may be enabled per project, with the guard's command.
2. `docs/migration.md`: a "dforge 4.x to dagents" entry: 4.17.1 updates to dforge 5.0.0; to keep the agent workflow, install dagents, run `claude plugin disable dforge@darkraise --scope local` in the project, and run `/dagents:migrate`; darkmem `dforge/` data is copied, and the printed command deletes it later.
3. `CLAUDE.md` Validation: name `plugins/dagents` beside dforge and dflow for `claude plugin validate`/`test`, `node scripts/test-all.mjs --plugin dagents`, and add: "A dagents job skipped by its path filter counts as green."
4. Add the deferred row to the split register: `bash plugins/dforge/scripts/register add docs/dforge/registers/2026-11-16-dagents-split.md "dagents does not follow dforge fixes that land after the split; a later backport reruns scripts/dagents-backport.mjs" --state deferred --note "spec out of scope: later dforge fixes"`.

- [ ] **Step 3: Close the backport**

Add a row for every line `timeout 60 node scripts/dagents-backport.mjs rows dforge-v4.17.1 main` prints that the register lacks, with `bash plugins/dforge/scripts/register add docs/dforge/registers/2026-11-16-dagents-backport.md "<line>"`. For each new row: read `git show <sha>`; when `timeout 60 node scripts/dagents-backport.mjs five-only <sha>` exits 0 set it `n/a` with note `5-only` (`bash plugins/dforge/scripts/register set docs/dforge/registers/2026-11-16-dagents-backport.md <id> n/a --note "5-only"`); otherwise decide whether its defect exists in 4.17.1 and set `n/a` with a classed reason, or port it: `PD=$(mktemp -d) && git show <sha> -- plugins/dforge | node scripts/dagents-rename.mjs patch > "$PD/port.diff"`, apply the test hunks first (`git apply --3way --include='plugins/dagents/tests/*' "$PD/port.diff"`) and see the suite fail, apply the rest (`git apply --3way "$PD/port.diff"`, or reimplement it in the 4.17.1 structure) and see it pass, commit `fix(dagents): <description>` with body `Backport of <sha>.`, and set the row `done` with note `port <sha7>; fail@parent pass@port`. A24 is a demo for your human partner; it is not run here, and finishing records register row 3 as `verify`.

- [ ] **Step 4: Verify**

Run: `timeout 120 node scripts/dagents-backport.mjs audit docs/dforge/registers/2026-11-16-dagents-backport.md main && bash plugins/dforge/scripts/register open docs/dforge/registers/2026-11-16-dagents-backport.md; timeout 120 node scripts/release.mjs --dry-run && timeout 60 node scripts/validate-repository.mjs`
Expected: the audit exits 0; `register open` exits 0 (no open row); the dry run lists `release dforge 4.17.1 -> 5.0.0`, `tag dagents-v1.0.0` and `tag dflow-v1.0.0`; the validator passes.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/migration.md CLAUDE.md docs/dforge/registers
git commit -m "docs: describe the dagents split"
```
