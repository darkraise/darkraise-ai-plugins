# Per-worktree Handoff Files Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every checkout its own `latest.md`, make `next-step` write the handoff of the checkout the next session must work in, and make the launch line and first prompt name that checkout and its handoff, in dforge and dagents.

**Architecture:** The handoff path moves from the primary to the session's own checkout (`roots.sh`, `darkmem-config.mjs`). `next-step` computes a target checkout T (one helper, also printed by `next-step --target`) and writes T's handoff. Every reader (stop hooks, auto-run, cockpit, repo-audit, session start, darkmem push, skills) follows T or the session's own checkout as the spec says.

**Tech Stack:** bash scripts and libraries, Node `.mjs` darkmem modules, the TypeScript cockpit mod, bash and `node --test` suites, the mod test runner (`claude plugin test`).

**Spec:** `docs/dforge/specs/2026-11-18-per-worktree-handoff-design.md`

**Execution:** inline — `claude --model opus --effort high` — the hardest self-implemented tasks total 7

**Parallelism:** sequential — inline execution

**Task check:** none — full suite every 3 tasks

**Integration check:** `node scripts/test-all.mjs && node scripts/test-all.mjs --plugin dagents`

**CI:** `.github/workflows/validate.yml` — platforms: Linux (self-hosted homelab or ubuntu-latest), Windows Git Bash (14 shards) — local: `node scripts/validate-repository.mjs`; `node scripts/test-all.mjs`; `node scripts/test-all.mjs --plugin dagents`; `claude plugin test plugins/dforge`; `claude plugin test plugins/dagents` — uncovered: Windows Git Bash, uutils (ubuntu-latest)

**Plan review:** 2026-11-18 — dforge:judge-opus — executability 13 / coherence 15 / coverage 15 / assumptions 15 (round 2)

## Global Constraints

- Every change lands in dforge and dagents alike (`plugins/dforge`, `plugins/dagents`; dagents uses `.dagents/` and `dagents_*` names where dforge uses `.dforge/` and `dforge_*`), one commit per concern covering both plugins. Exceptions: the darkmem behaviour of A11 and A14 and Task 10 are dforge only; dagents' `darkmem-config.mjs` changes only its local branch.
- Preserve existing `DCC_*` variables and statusline user storage paths.
- The primary checkout's handoff path does not change; no migration code.
- Do not touch the `chore/audit-2026-11-17` branch or worktree.
- Do not push (owner, 2026-11-18: "merge locally, do not push").
- Commits: `<type>(<scope>): <subject>`, subject at most 50 characters after the prefix, author `Darkraise <quangtc94@gmail.com>`, no AI attribution of any kind.
- Bound every test and CLI run with a timeout and stop every process the run starts.
- Windows Git Bash: a native program (`git.exe`, `jq.exe`) given a path built from `$PWD`, `$(pwd)` or `$TMPDIR` gets a POSIX form it cannot open, or has its argument rewritten when path conversion is on (`MSYS_NO_PATHCONV` unset). Convert the path with `cygpath -m` before the call (`dr_native_path`, `plugins/dforge/scripts/lib/native-path.sh`), and feed `jq` a file on stdin in a script that exports `MSYS_NO_PATHCONV`.
- Windows Git Bash: the same directory is `/c/Users/x` in the shell and `C:/Users/x` from a native tool, so a string comparison never matches. Normalise both sides with `cygpath -m`, or compare with `-ef`.
- Windows Git Bash: files a Windows tool wrote, and native program output, end lines with `\r`, which `read`, `awk` and `[ = ]` keep. Pipe through `tr -d '\r'` before comparing or parsing.
- Windows Git Bash: `awk -v name=value` processes backslash escapes in the value, so a regex or a Windows path changes. Pass the value in the environment and read `ENVIRON["NAME"]`.
- Windows Git Bash: Node's `import()` of an absolute `D:/x/y.mjs` reads `d:` as a URL scheme and fails. Import with `import(pathToFileURL(path).href)`.
- uutils (ubuntu-latest): a lock built on `mkdir` failing when the directory exists does not exclude a second process. Create the lock file with `set -C` (noclobber), or use `flock`.
- uutils (ubuntu-latest): `timeout` signals only the command it started, so the command's children keep running. Run the command in its own process group (`setsid`) and signal the group.

## Contracts

- **C1 handoff path.** A checkout's handoff is `<checkout>/.dforge/handoff/latest.md` (dagents `.dagents/`). While dforge progress is in darkmem, the primary's is `<mirror>/work/handoff/latest.md` and a linked worktree's stays `<worktree>/.dforge/handoff/latest.md`. `dforge_latest_file [DIR]` and `darkmem-config.mjs`'s `progress.latestFile` return it for the checkout DIR (default: the working directory) is in.
- **C2 `dforge_latest_files [DIR]`** (dagents `dagents_latest_files`), in `scripts/lib/roots.sh`: prints one absolute path per line, each checkout's C1 handoff once, for every checkout `git worktree list --porcelain` names whose directory exists, in that order; under darkmem the mirror's file stands in for the primary's local path (dagents under darkmem: the mirror's file alone). It starts no node process per worktree.
- **C3 `next-step --target <arguments>`**: prints T's absolute handoff path and a newline, exit 0, writing nothing; never exits 5 over background work; exits 2 on the same usage errors and missing plan as `next-step <arguments>`; `--target` with `--latest` is a usage error (exit 2).
- **C4 T.** Plan in flight: progress local — the checkout `plan_ledger_any` prints in its second field; progress darkmem with a ledger in the mirror — among linked worktrees holding `<state>/sdd/<slug>/`, the checkout next-step runs in when it is one of them, else the first `git worktree list` names; when none holds it, the primary if the primary does; otherwise the checkout next-step runs in. `--complete` or a plan `plan_finished` records: the primary. `--kept`, `--draft`, `--adhoc`, `--project`: the checkout next-step runs in.
- **C5 launch prefix.** When no `cygpath` is on PATH, a non-empty launch command is printed as `cd '<T>' && <command>`, each `'` in T written `'\''`. With `cygpath` on PATH, no prefix. With no launch command: ``Launch from `<T>`: see the **Execution:** line in `<plan>`.`` The line above the fence stays ``Launch in `<T>`:``.
- **C6 prompt prefix.** Every first prompt opens with ``Start in `<T>` (branch <b>); its handoff is `<T's handoff>`. If your working directory is not `<T>`, enter it first.`` A detached T reads ``(detached at `<sha7>`)`` in place of `(branch <b>)`. No prompt contains "First enter the existing worktree".
- **C7 stderr line.** `next-step: replaced the block for <subject>` — the marker's subject, or its kind when the subject is `-`.
- **C8 push line.** `worktree handoff stays local: <path>` on stdout when `darkmem-sync push` runs in a linked worktree.
- **C9 SessionStart count line.** `<n> other checkouts hold a handoff (scripts/repo-audit lists them).`
- **C10 repo-audit entries.** Under `## Handoff`: the session's own handoff first, as today (path, recomputed or stored lines, commits since). Each other checkout's: ``- `<path>` [<branch>]``, then `- stored, not recomputed: another checkout's handoff, written <h>h ago` (age from the marker's `at=`, else the file's mtime), then its stored `**Status:**` and `**Next:**` lines. A prunable or missing worktree: ``- skipped `<path>`: prunable or missing``. No handoff anywhere: `- none`.

## Assumptions (evidence)

- A session's checkout follows `cd '<worktree>' && claude`, `EnterWorktree` and a cockpit `/clear`: unverified — Task 1 verifies it.
- The cockpit re-reads its checkout after `EnterWorktree` (`plugins/dforge/hooks/cockpit/register.tsx:959-963`, `:4653-4666`); `cockpit.test.ts:5981` pins it with a mocked checkout.
- The primary holds `<state>/sdd/<slug>/` after a plan review (`plugins/dforge/scripts/sdd-workspace:38-41`), so T never takes the first listed checkout blindly (spec §2).
- `ending_released` (`plugins/dforge/scripts/lib/next-ending.sh`) checks one file; Task 6 applies it per checkout.
- `plan_ledger_any` checks the caller's own checkout before the other worktrees (`plugins/dforge/scripts/lib/plan.sh:283-284`), so C4's local rule gives the caller's checkout whenever it holds the plan's ledger; a test fixture must not leave a ledger for the plan in the checkout it runs from.
- `next-step --complete` prints a launch block and a prompt only when something follows (a Program line naming a next sub-project, an open register row, or a roadmap milestone), and `--project` only when a register row is open or a milestone is current (`plugins/dforge/scripts/next-step:412-413`; `tests/dforge/next-step.test.sh:146-150`); Tasks 4 and 5 give their fixtures both.
- The cockpit runs `scripts/auto-run` through `autoRunCall` with no directory (`plugins/dforge/hooks/cockpit/register.tsx:3094-3097`), and the compact, continue, switch and clear stages and the stop buttons call it; a session-start with `pending: null` may not.
- Existing tests that pin today's shared file and the task that updates each: `tests/dforge/next-session-routing.acceptance.test.sh:251-260` (Task 5), `plugins/dforge/tests/cockpit.test.ts:5342` and `:5695-5702` (Task 8), `tests/dforge/repo-audit.test.sh:63-78` (Task 9), `tests/dforge/next-step.test.sh:168,530` (Task 5).
- The full suite last passed in 402-418 s (`.dforge/suites.tsv`), above the 300 s Task check threshold.

## Task index

1. Verify the session checkout on a live host
2. Resolve the handoff per checkout in darkmem-config
3. Resolve the handoff per checkout in roots.sh
4. Write the handoff of the target checkout
5. Name the target checkout in the block
6. Release stop hooks on any checkout's handoff
7. Read the attached plan's handoff in auto-run
8. Read the session checkout's handoff in the cockpit
9. List every checkout's handoff
10. Say a worktree handoff stays local on push
11. Update the skills and docs

---

### Task 1: Verify the session checkout on a live host

**Files:**
- Create: `docs/dforge/notes/2026-11-18-worktree-cwd-probe.md`

**Interfaces:**
- Consumes: None
- Produces: the probe's findings, which Task 8 reads: the line `process.run follows EnterWorktree: yes` or `… : no`. On `no`, Task 8 passes `$.session.cwd()` explicitly to `readPlace`'s git calls.

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 0 - spec 2 - coupling 0 - risk 0 = 2

- [ ] **Step 1: No new test, because this task probes host behaviour no repository test can reach; its result is a note**

- [ ] **Step 2: Build the scratch setup**

`claude` is a shell function in this environment: call `/root/.local/bin/claude`. The owner's tmux server is already running, so a new tmux session gets the server's environment: start Claude through a script with `env -i`. Never copy `.credentials.json`, and kill only your own tmux session.

```bash
S=$(mktemp -d)
git init -q -b main "$S/repo" && git -C "$S/repo" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
git -C "$S/repo" worktree add -q -b w "$S/w"
mkdir -p "$S/home"; printf '{}\n' > "$S/settings.json"
# A copy of the plugin whose auto-run logs the directory the cockpit runs it in.
cp -R /root/repositories/darkraise-ai-plugins/plugins/dforge "$S/dforge"
mv "$S/dforge/scripts/auto-run" "$S/dforge/scripts/auto-run.real"
printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "$(pwd -P)" "$*" >> "%s/auto-run.log"\nexit 0\n' "$S" > "$S/dforge/scripts/auto-run"
chmod +x "$S/dforge/scripts/auto-run"
cat > "$S/launch.sh" <<EOF
#!/bin/sh
cd "\$1" && exec env -i HOME="$S/home" PATH="$PATH" TERM=xterm-256color CLAUDE_CONFIG_DIR=/root/.claude-alt2 IS_SANDBOX=1 \\
  /root/.local/bin/claude --setting-sources project,local --settings "$S/settings.json" --plugin-dir "$S/dforge" --session-id "\$2"
EOF
chmod +x "$S/launch.sh"
cp /root/.claude-alt2/settings.json "$S/owner-settings.json"
```

Do not pass `--dangerously-skip-permissions`: approve each tool prompt with Enter, so the owner's settings stay byte-identical. The trust prompt lists "No, exit" first: answer it with Down, Enter. Drive the pane with `tmux send-keys -t probe …` and read it with `tmux capture-pane -p -t probe`, waiting for each reply before the next step.

- [ ] **Step 3: Run the probe**

1. Launch in the worktree: `tmux new-session -d -s probe -x 160 -y 45 "$S/launch.sh $S/w $(cat /proc/sys/kernel/random/uuid)"`. First confirm the setup: the pane shows the trust prompt (answer it), then the cockpit's pane or band. If either is missing, or `claude --help` does not list `--plugin-dir`, `--session-id` and `--setting-sources`, stop and record the gap in the note. Then ask it to run `pwd` with Bash. Record the directory, and the cockpit's directory strip. Exit with `/exit`.
2. Bind an auto run to the next session, so the cockpit calls `auto-run` on its own: `SID=$(cat /proc/sys/kernel/random/uuid)`, `mkdir -p "$S/repo/.dforge/sdd"`, then write `$S/repo/.dforge/sdd/auto-run.json` as `{"active":true,"session":"<SID>","phase":"execute","regime":"normal","pending":"compact","plan":"docs/plan.md","compactions":0,"resumes":0,"stopped":null,"resumePrompt":null,"launch":null}`.
3. Launch in the primary: `tmux new-session -d -s probe -x 160 -y 45 "$S/launch.sh $S/repo $SID"`. Ask it to call `EnterWorktree` on `w`, then run `pwd` and `git rev-parse --show-toplevel` with Bash. Record both and the cockpit's directory strip (`readPlace` fills it from `$.process.run`).
4. Plant a handoff only in the worktree: `mkdir -p "$S/w/.dforge/handoff"`, and write `$S/w/.dforge/handoff/latest.md` with a `## Next session` block holding `Paste as the first prompt:` and a fenced prompt line. Ask for any one-line reply. Record whether the cockpit pane shows a Resume offer. Before Tasks 2-3 the handoff path resolves to the primary's for every checkout, so `no` is the expected baseline; record it as such.
5. Ask it to reply with exactly `Task 1: complete.` and, on its own last line, `Auto run: compacting`. The cockpit then runs `auto-run … compacted` through `autoRunCall`. Read `$S/auto-run.log`: the directory on the `compacted` line is where `$.process.run` runs.
6. After the compaction, type `/clear`, then ask for `pwd` with Bash. Record it, the directory strip, and any new `$S/auto-run.log` lines (the cockpit calls `rebind` and `resumed` on a clear during a run).
7. Clean up: `tmux kill-session -t probe`; check with `ps -eo pid,args | grep "$S"` that nothing it started is left, and stop what is; restore `/root/.claude-alt2/settings.json` from `$S/owner-settings.json` if it changed (`cmp`); `rm -rf "$S"`.

- [ ] **Step 4: Record**

Write the note: date, Claude Code version (`/root/.local/bin/claude --version`), each step's observed directories and log lines, and one verdict line per case: `cd launch: worktree|primary`, `EnterWorktree (Bash): worktree|primary`, `/clear: worktree|primary`, `resume offer read the worktree's handoff: yes|no`, and `process.run follows EnterWorktree: yes|no` (from step 5's log line; step 3's strip confirms it). If any case stays in the primary, write the fallback the spec names for it (riskiest assumption section).

- [ ] **Step 5: Commit**

```bash
git add docs/dforge/notes/2026-11-18-worktree-cwd-probe.md
git commit -m "docs(dforge): record the worktree cwd probe"
```

### Task 2: Resolve the handoff per checkout in darkmem-config

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-config.mjs` (the `latestFile` entry of `result`), `plugins/dagents/scripts/lib/darkmem-config.mjs` (the same entry, local branch only)
- Test: `tests/dforge/darkmem-sync/config.test.mjs`, `tests/dagents/darkmem-sync/config.test.mjs`

**Interfaces:**
- Consumes: None
- Produces: C1 for `progress.latestFile`.

**Items:** 1

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Extend the test `tests/dforge/darkmem-sync/config.test.mjs::a linked worktree keeps local families in itself and latest.md in the primary checkout`**

Rename it and change its last assertion, then add a darkmem case after it:

```js
test("a linked worktree keeps local families and latest.md in itself", () => {
  const repo = makeRepo();
  const { env } = makeHome({ repo, stores: { documents: "local", progress: "local" } });
  const worktree = path.join(scratch("dms-wt-"), "wt");
  git(repo, "worktree", "add", "-q", "-b", "wt", worktree);
  const stores = resolveStores({ cwd: worktree, env });
  assert.equal(stores.sync.project, "proj");
  assert.equal(stores.documents.root, path.join(worktree, "docs", "dforge"));
  assert.equal(stores.progress.ledgerRoot, path.join(worktree, ".dforge", "sdd"));
  assert.equal(stores.progress.latestFile, path.join(worktree, ".dforge", "handoff", "latest.md"));
  assert.equal(resolveStores({ cwd: repo, env }).progress.latestFile, path.join(repo, ".dforge", "handoff", "latest.md"));
});

test("under darkmem progress only the primary's latest.md is in the mirror", () => {
  const repo = makeRepo();
  const { env, mirror } = makeHome({ repo, stores: { documents: "local", progress: "darkmem" } });
  const worktree = path.join(scratch("dms-wt-"), "wt");
  git(repo, "worktree", "add", "-q", "-b", "wt", worktree);
  assert.equal(resolveStores({ cwd: repo, env }).progress.latestFile, path.join(mirror, "work", "handoff", "latest.md"));
  assert.equal(resolveStores({ cwd: worktree, env }).progress.latestFile, path.join(worktree, ".dforge", "handoff", "latest.md"));
});
```

In `tests/dagents/darkmem-sync/config.test.mjs`, the test at its line 191 gets the first test's change with `.dagents` for `.dforge`; no darkmem case.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 120 node --test tests/dforge/darkmem-sync/config.test.mjs tests/dagents/darkmem-sync/config.test.mjs`
Expected: FAIL — `latestFile` is the primary's path from the worktree, and the mirror's under darkmem.

- [ ] **Step 3: Implement**

1. In the `result` builder's `progress.latestFile`, the local branch uses `worktreeRoot` (not `repoRoot ?? worktreeRoot`).
2. dforge only: the darkmem branch returns the mirror's `work/handoff/latest.md` only when `worktreeRoot` is the primary (compare with `samePath(worktreeRoot, repoRoot)`); for a linked worktree it returns `path.join(dforgeDir("state", worktreeRoot), "handoff", "latest.md")`.
3. `ledgerRoot` and `documents.root` are unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 120 node --test tests/dforge/darkmem-sync/config.test.mjs tests/dagents/darkmem-sync/config.test.mjs tests/dforge/darkmem-sync/reconcile-progress.test.mjs tests/dagents/darkmem-sync/reconcile-progress.test.mjs`
Expected: PASS (update `reconcile-progress.test.mjs:30-33` in both plugins if it pins the primary's path for a worktree, to the worktree's).

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-config.mjs plugins/dagents/scripts/lib/darkmem-config.mjs tests/dforge/darkmem-sync tests/dagents/darkmem-sync
git commit -m "feat(dforge): resolve latest.md per checkout in config"
```

### Task 3: Resolve the handoff per checkout in roots.sh

**Files:**
- Modify: `plugins/dforge/scripts/lib/roots.sh` (`_dforge_local`; new `dforge_latest_files`), `plugins/dagents/scripts/lib/roots.sh` (`_dagents_local`; new `dagents_latest_files`)
- Test: `tests/dforge/roots.test.sh`, `tests/dagents/roots.test.sh`

**Interfaces:**
- Consumes: C1 from Task 2.
- Produces: C1 for `dforge_latest_file`; C2.

**Items:** 1

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Extend the test `tests/dforge/roots.test.sh`**

Change the assertions that pin the primary's file for a worktree:

```bash
check "no config: latest.md from a worktree" "$(cd "$WT" && dforge_latest_file)" "$WT/.dforge/handoff/latest.md"
check "no config: latest.md from the primary" "$(cd "$REPO" && dforge_latest_file)" "$TOP/.dforge/handoff/latest.md"
```

```bash
check "settings only: latest.md from a worktree" "$(cd "$WT" && PATH="$TMP/marknode:$PATH" dforge_latest_file)" "$WT/.dforge/handoff/latest.md"
```

In the four-combinations loop, the combined if/else at `tests/dforge/roots.test.sh:63-67` sets `want_ledger` and `want_latest` together. Edit only its `want_latest=` assignments, leaving every `want_ledger=` assignment as it is, so that `want_latest` ends up as:

```bash
      if [ "$progress" = darkmem ] && [ "$where" = "$TOP" ]; then want_latest="$MIRROR/work/handoff/latest.md"
      else want_latest="$where/.dforge/handoff/latest.md"; fi
```

At the end of the loop body add:

```bash
      check "$label: every checkout's handoff" "$(cd "$where" && dforge_latest_files | tr '\n' ' ')" \
        "$( [ "$progress" = darkmem ] && printf '%s ' "$MIRROR/work/handoff/latest.md" || printf '%s ' "$TOP/.dforge/handoff/latest.md")$WT/.dforge/handoff/latest.md "
```

Before the summary lines at the end, add:

```bash
# --- dforge_latest_files skips a worktree whose directory is gone ---
git -C "$REPO" worktree add -q -b gone "$TMP/gone"
rm -rf "$TMP/gone"
check "latest files: a missing worktree is skipped" "$(cd "$REPO" && dforge_latest_files | grep -c gone)" "0"
git -C "$REPO" worktree prune
```

In `tests/dagents/roots.test.sh` make the same changes at its lines 35, 47, 49 and its loop, with `.dagents`, `dagents_latest_file`, `dagents_latest_files`; under darkmem the expected `dagents_latest_files` output is the mirror's file alone (`"$MIRROR/work/handoff/latest.md "`).

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 120 bash tests/dforge/roots.test.sh; timeout 120 bash tests/dagents/roots.test.sh`
Expected: FAIL — the worktree resolves to the primary's file; `dforge_latest_files: command not found`.

- [ ] **Step 3: Implement**

1. `_dforge_local DIR TOP`: `_DFORGE_LATEST` from `$base`, as `_DFORGE_LEDGER_ROOT` already is. The `primary` computation stays only if something else in the function uses it; otherwise remove it. Same in `_dagents_local`.
2. `dforge_latest_files [DIR]`: list `worktree <path>` lines of `git -C DIR worktree list --porcelain` (strip `\r`, convert with `_dforge_path`), skip a path whose directory does not exist, and print each one's handoff: the primary (first entry) prints `dforge_latest_file <primary>`; each linked worktree prints `$(dforge_dir state <worktree>)/handoff/latest.md` without calling node (C1 makes it local in both stores). dagents: under darkmem, print the mirror file once and nothing else.
3. Keep the per-checkout cache in `dforge_stores_init` untouched.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 120 bash tests/dforge/roots.test.sh; timeout 120 bash tests/dagents/roots.test.sh`
Expected: PASS, `0 failed` in both.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/roots.sh plugins/dagents/scripts/lib/roots.sh tests/dforge/roots.test.sh tests/dagents/roots.test.sh
git commit -m "feat(dforge): keep latest.md in each checkout"
```

### Task 4: Write the handoff of the target checkout

**Files:**
- Modify: `plugins/dforge/scripts/next-step` (mode parsing, the `dir=` assignments, `handoff=` and `write_handoff`), `plugins/dforge/scripts/lib/plan.sh` (`_plan_ledger_tree`), and the same in dagents
- Test: `tests/dforge/next-step.test.sh`, `tests/dagents/next-step.test.sh`

**Interfaces:**
- Consumes: C1, C2 (Tasks 2-3).
- Produces: C3, C4.

**Items:** 1

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Extend the test `tests/dforge/next-step.test.sh`**

In the `# --- worktree: ledger in the worktree, handoff in the primary checkout ---` block, change the heading to `# --- worktree: ledger in the worktree, handoff in the worktree ---` and replace its four assertions after `run "$WT" "$PLAN_REL"` (the "First enter", "launch dir is still the primary checkout", "handoff written in the primary checkout" and "no handoff inside the worktree" checks) with:

```bash
has "worktree: launch dir is the worktree" "$out" "Launch in \`$WT_ROOT\`:"
check "worktree: handoff written in the worktree" "$([ -f "$WT_ROOT/.dforge/handoff/latest.md" ] && echo yes || echo no)" "yes"
check "worktree: no handoff in the primary" "$([ -f "$HANDOFF" ] && echo yes || echo no)" "no"
rm -f "$WT_ROOT/.dforge/handoff/latest.md"
```

Step 3.3 makes the handoff path the block names absolute, so change the draft and adhoc assertions at `:227`, `:240` and `:243` (dagents: the same three checks in its draft and adhoc blocks) that name the relative path:

```bash
has "draft: prompt" "$out" "Continue from \`docs/specs/draft.md\` (the authority): Write the implementation plan with dforge:writing-plans. Read \`$ROOT/.dforge/handoff/latest.md\` first."
has "adhoc: status names the authority" "$out" "**Status:** Unplanned work: the notes in \`$ROOT/.dforge/handoff/latest.md\` are the authority."
has "adhoc: prompt" "$out" "Continue the unplanned work recorded in \`$ROOT/.dforge/handoff/latest.md\`: Scope item C with dforge:brainstorming."
```

Before the summary lines at the end of the file, add:

```bash
# --- per-worktree handoffs (spec A2, A3, A6, A13, A14) ---
# The Keep as-is block left a ledger for this plan in the primary; plan_ledger_any
# checks the caller's checkout first, so it would make the primary T.
rm -rf "$LEDGER_DIR"
rm -rf "$HOME/.dforge" "$REPO/.dforge/handoff"
# A Program line and an open register row, so --complete and --project print a block.
write_plan "$PLAN" "$EXEC_SUB" "$PROG_NEXT"
OTHER_REL="docs/plans/2026-01-02-other.md"
write_plan "$REPO/$OTHER_REL" "$EXEC_SUB" ""
mkdir -p "$REPO/docs/dforge/registers"
printf '# Demo — item register\n\n**Source:** test\n**Covers:** -\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | Open item | - | - | open | - |\n' \
  > "$REPO/docs/dforge/registers/demo.md"
git -C "$REPO" add "$PLAN_REL" "$OTHER_REL" docs/dforge/registers/demo.md && git -C "$REPO" commit -qm "two plans"
WA="$TMP/wa"; WB="$TMP/wb"
git -C "$REPO" worktree add -q -b wa "$WA"; git -C "$REPO" worktree add -q -b wb "$WB"
WA_ROOT=$(git -C "$WA" rev-parse --show-toplevel); WB_ROOT=$(git -C "$WB" rev-parse --show-toplevel)
WA_H="$WA_ROOT/.dforge/handoff/latest.md"; WB_H="$WB_ROOT/.dforge/handoff/latest.md"
# The primary holds both plans' workspaces, as a plan review leaves them.
mkdir -p "$REPO/.dforge/sdd/2026-01-01-demo" "$REPO/.dforge/sdd/2026-01-02-other" \
  "$WA/.dforge/sdd/2026-01-01-demo" "$WB/.dforge/sdd/2026-01-02-other"
printf 'lint\n' > "$REPO/.dforge/sdd/2026-01-01-demo/plan-lint.txt"
printf 'lint\n' > "$REPO/.dforge/sdd/2026-01-02-other/plan-lint.txt"
printf '# SDD ledger — plan: %s\nTask 1: complete (x)\n' "$PLAN_REL" > "$WA/.dforge/sdd/2026-01-01-demo/progress.md"
printf '# SDD ledger — plan: %s\nTask 1: complete (x)\n' "$OTHER_REL" > "$WB/.dforge/sdd/2026-01-02-other/progress.md"
run "$WA" "$PLAN_REL"; run "$WB" "$OTHER_REL"
has "A2: the first worktree holds its plan's block" "$(cat "$WA_H")" "$PLAN_REL"
lacks "A2: the first worktree does not name the other plan" "$(cat "$WA_H")" "2026-01-02-other"
has "A2: the second worktree holds its plan's block" "$(cat "$WB_H")" "$OTHER_REL"
lacks "A2: the second worktree does not name the first plan" "$(cat "$WB_H")" "2026-01-01-demo"
check "A2: the primary's handoff is not written" "$([ -f "$HANDOFF" ] && echo yes || echo no)" "no"
rm -f "$WA_H"
run "$REPO" "$PLAN_REL"
has "A3: from the primary, the block launches in the ledger's worktree" "$out" "Launch in \`$WA_ROOT\`:"
check "A3: from the primary, the worktree's handoff is written" "$([ -f "$WA_H" ] && echo yes || echo no)" "yes"
check "A3: from the primary, the primary's handoff is not written" "$([ -f "$HANDOFF" ] && echo yes || echo no)" "no"
check "A13: --target from the primary names the worktree's handoff" "$(cd "$REPO" && bash "$SCRIPT" --target "$PLAN_REL")" "$WA_H"
rm -f "$WA_H"
check "A13: --target writes nothing" "$(cd "$WA" && bash "$SCRIPT" --target "$PLAN_REL" >/dev/null; [ -f "$WA_H" ] && echo yes || echo no)" "no"
check "A13: --target for adhoc work names this checkout's" "$(cd "$WB" && bash "$SCRIPT" --target --adhoc --phase build --next x)" "$WB_H"
(cd "$REPO" && bash "$SCRIPT" --target --latest >/dev/null 2>&1); check "A13: --target with --latest is a usage error" "$?" "2"
(cd "$REPO" && bash "$SCRIPT" --target docs/plans/missing.md >/dev/null 2>&1); check "A13: --target of a missing plan exits 2" "$?" "2"
# A13, every mode: --target names exactly the file the same call then writes.
# Paths as git spells them (C:/… on Windows Git Bash), as --target prints them.
written() { local f; for f in "$ROOT/.dforge/handoff/latest.md" "$WA_H" "$WB_H"; do [ -f "$f" ] && printf '%s ' "$f"; done; }
for args in "$PLAN_REL" "--complete $PLAN_REL" "--kept $PLAN_REL" "--draft $OTHER_REL --next x" "--adhoc --phase build --next x" "--project"; do
  rm -f "$HANDOFF" "$WA_H" "$WB_H"
  # shellcheck disable=SC2086
  t=$(cd "$WA" && bash "$SCRIPT" --target $args 2>/dev/null)
  # shellcheck disable=SC2086
  run "$WA" $args
  check "A13: --target names the file written ($args)" "$(written)" "$t "
done
rm -f "$HANDOFF" "$WA_H" "$WB_H"
# A13: background work running never stops --target (the stub in-flight reports a live launch).
rm -rf "$TMP/stubscripts" && cp -R "$(dirname "$SCRIPT")" "$TMP/stubscripts"
printf '#!/usr/bin/env bash\nprintf -- "- shell b1 10:00 idle 1m sleep\\n"\nexit 1\n' > "$TMP/stubscripts/in-flight"
(cd "$WA" && bash "$TMP/stubscripts/next-step" "$PLAN_REL" >/dev/null 2>&1); check "A13: the in-flight stub makes a plain run exit 5" "$?" "5"
t=$(cd "$WA" && bash "$TMP/stubscripts/next-step" --target "$PLAN_REL" 2>/dev/null); status=$?
check "A13: --target with background work running exits 0 and names the path" "$status:$t" "0:$WA_H"
rm -rf "$TMP/stubscripts"
rm -f "$HANDOFF" "$WA_H"
run "$WA" --complete "$PLAN_REL"
has "A6: --complete launches in the primary" "$out" "Launch in \`$ROOT\`:"
check "A6: --complete writes the primary's handoff" "$([ -f "$HANDOFF" ] && echo yes || echo no)" "yes"
rm -f "$HANDOFF" "$WA_H"
run "$WA" --kept "$PLAN_REL"
check "A6: --kept writes the handoff of the checkout it runs in" "$([ -f "$WA_H" ] && echo yes || echo no):$([ -f "$HANDOFF" ] && echo yes || echo no)" "yes:no"
rm -f "$WA_H"
# A14: darkmem progress, ledger in the mirror; the primary also holds the workspace.
. "$HERE/fixtures/darkmem-stores.sh"
MIRROR=$(stores_home "$HOME" "$REPO" demo local darkmem)
mkdir -p "$MIRROR/work/sdd/2026-01-01-demo"
printf '# SDD ledger — plan: %s\nTask 1: complete (x)\n' "$PLAN_REL" > "$MIRROR/work/sdd/2026-01-01-demo/progress.md"
rm -f "$WA/.dforge/sdd/2026-01-01-demo/progress.md"
run "$REPO" "$PLAN_REL"
has "A14: darkmem: launches in the worktree holding the workspace" "$out" "Launch in \`$WA_ROOT\`:"
check "A14: darkmem: the worktree's handoff is written" "$([ -f "$WA_H" ] && echo yes || echo no)" "yes"
check "A14: darkmem: the mirror's handoff is not written" "$([ -f "$MIRROR/work/handoff/latest.md" ] && echo yes || echo no)" "no"
rm -rf "$HOME/.dforge"
```

In `tests/dagents/next-step.test.sh` make the same changes (its worktree block at lines 277-280; the new block before its summary) with `.dagents` for `.dforge` and `$HERE/fixtures/darkmem-stores.sh` replaced by nothing: drop the A14 lines (dforge only).

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash tests/dforge/next-step.test.sh; timeout 300 bash tests/dagents/next-step.test.sh`
Expected: FAIL — the handoff is written in the primary and `--target` is an unknown option.

- [ ] **Step 3: Implement**

1. Option parsing: `--target` sets `target_only=1`; with `--latest` it is a usage error (exit 2, the script's `usage`).
2. After the mode branches have computed `rel`, `has_ledger`, `ledger_root`, `complete` and the finished check, compute T per C4 in one function `handoff_target` (dagents the same name). The darkmem rule lists `git worktree list --porcelain` entries other than the primary that hold `$(dforge_dir state <w>)/sdd/<slug>/`.
3. `dir` (the `Launch in` directory) becomes T for every mode. Resolve T's handoff in a subshell, `handoff=$(dforge_stores_init "$T"; dforge_latest_file "$T")`, so the cached roots stay the session's. `latest_shown` becomes that absolute path. `plan_final_review_state` is given T, not `ledger_root`.
4. With `target_only=1`, after T is known and before the background-work check (`in-flight`), print `$handoff` and exit 0.
5. `_plan_ledger_tree` in `plan.sh`: try the caller's checkout first when it is a linked worktree, then the other linked worktrees in `git worktree list` order, the primary last.
6. Keep the marker counts (`handoff_counts "$primary"`) and the `finish.json` clearing as they are.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash tests/dforge/next-step.test.sh; timeout 300 bash tests/dagents/next-step.test.sh`
Expected: PASS, `0 failed` in both.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/next-step plugins/dforge/scripts/lib/plan.sh plugins/dagents/scripts/next-step plugins/dagents/scripts/lib/plan.sh tests/dforge/next-step.test.sh tests/dagents/next-step.test.sh
git commit -m "feat(dforge): write the target checkout's handoff"
```

### Task 5: Name the target checkout in the block

**Files:**
- Modify: `plugins/dforge/scripts/next-step` (the `block=$(` printer, the two "First enter the existing worktree" sentences, `write_handoff`), and the same in dagents
- Test: `tests/dforge/next-step.test.sh`, `tests/dagents/next-step.test.sh`, `tests/dforge/next-step-print.test.sh`, `tests/dagents/next-step-print.test.sh`, `tests/dforge/next-session-routing.acceptance.test.sh`, `tests/dagents/next-session-routing.acceptance.test.sh`

**Interfaces:**
- Consumes: C3, C4 (Task 4).
- Produces: C5, C6, C7.

**Items:** 2, 3

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 2 - risk 2 = 7

- [ ] **Step 1: Extend the test `tests/dforge/next-step.test.sh`**

Change the no-launch-command needle at `tests/dforge/next-step.test.sh:168` (dagents `:258`) to C5's form, and the `lacks` at `:530` (dagents `:631`) to the words both forms share:

```bash
has "an Execution line naming no pair: points at the Execution line" "$out" "Launch from \`$ROOT\`: see the **Execution:** line in \`$PLAN_REL\`."
```

```bash
lacks "codex plan: no fallback to reading the Execution line" "$out" "see the **Execution:** line"
```

Before the A14 lines of Task 4's block (after `rm -f "$WA_H"` that follows the `--kept` check), add:

```bash
# --- launch line and prompt (spec A4, A5, A15) ---
launch_of() { awk '/^Launch in /{f=1; next} f && /^```$/{ if (g) exit; g=1; next } f && g { print; exit }' <<<"$1"; }
mkdir -p "$TMP/stub"
printf '#!/bin/sh\npwd -P > "%s"\n' "$TMP/started" > "$TMP/stub/claude"; chmod +x "$TMP/stub/claude"
run "$WA" "$PLAN_REL"
launch=$(launch_of "$out")
check "A4: cd prefix" "$launch" "cd '$WA_ROOT' && claude --model sonnet --effort high"
rm -f "$TMP/started"; (cd / && PATH="$TMP/stub:$PATH" bash -c "$launch")
check "A4: the launch starts in the worktree" "$(cat "$TMP/started" 2>/dev/null)" "$(cd "$WA" && pwd -P)"
ODD="$TMP/it's here"; git -C "$REPO" worktree add -q -b odd "$ODD"
ODD_ROOT=$(git -C "$ODD" rev-parse --show-toplevel)
run "$ODD" --adhoc --phase build --next x
rm -f "$TMP/started"; (cd / && PATH="$TMP/stub:$PATH" bash -c "$(launch_of "$out")")
check "A4: a path with a space and a quote survives" "$(cat "$TMP/started" 2>/dev/null)" "$(cd "$ODD" && pwd -P)"
printf '#!/bin/sh\nfor a; do last=$a; done\nprintf "%%s\\n" "$last"\n' > "$TMP/stub/cygpath"; chmod +x "$TMP/stub/cygpath"
out=$(cd "$WA" && PATH="$TMP/stub:$PATH" bash "$SCRIPT" "$PLAN_REL" 2>/dev/null)
check "A4: with cygpath on PATH no cd prefix" "$(launch_of "$out")" "claude --model sonnet --effort high"
rm -f "$TMP/stub/cygpath"
# A Codex Execution line gets the same prefix (spec §3); WA reads its own copy of the plan.
write_plan "$WA/$PLAN_REL" '**Execution:** inline — codex gpt-6.1-sol / high — Codex host' "$PROG_NEXT"
run "$WA" "$PLAN_REL"
check "A4: a Codex launch gets the cd prefix" "$(launch_of "$out")" "cd '$WA_ROOT' && codex -m gpt-6.1-sol -c model_reasoning_effort=high"
git -C "$WA" checkout -q -- "$PLAN_REL"
start="Start in \`$WA_ROOT\` (branch wa); its handoff is \`$WA_H\`. If your working directory is not \`$WA_ROOT\`, enter it first."
for args in "$PLAN_REL" "--draft $OTHER_REL --next x" "--adhoc --phase build --next x" "--project" "--kept $PLAN_REL"; do
  run "$WA" $args
  has "A5: prompt opens with Start in ($args)" "$out" "$start"
  lacks "A5: no First enter ($args)" "$out" "First enter the existing worktree"
done
run "$WA" --complete "$PLAN_REL"
has "A5: complete's prompt starts in the primary" "$out" "Start in \`$ROOT\`"
git -C "$WA" checkout -q --detach
run "$WA" --adhoc --phase build --next x
has "A5: a detached checkout" "$out" "Start in \`$WA_ROOT\` (detached at \`$(git -C "$WA" rev-parse --short HEAD)\`)"
git -C "$WA" checkout -q wa
printf '# Handoff\n\n## State\nKeep these notes.\n\n## Next session\n\n**Next:** other\n<!-- next-step: kind=adhoc done=0 closed=0 subject=- at=1 -->\n' > "$HANDOFF"
run "$WA" --complete "$PLAN_REL"
has "A15: complete over another live block keeps the notes" "$(cat "$HANDOFF")" "Keep these notes."
lacks "A15: and replaces its block" "$(cat "$HANDOFF")" "**Next:** other"
has "A15: stderr names the kind" "$(cat "$TMP/stderr")" "next-step: replaced the block for adhoc"
printf '# Handoff\n\n## State\nOld notes.\n\n## Next session\n\n**Next:** x\n<!-- next-step: kind=plan done=0 closed=0 subject=%s at=1 -->\n' "$PLAN_REL" > "$HANDOFF"
run "$WA" --complete "$PLAN_REL"
lacks "A15: its own plan's block is replaced wholesale" "$(cat "$HANDOFF")" "Old notes."
printf '# Handoff\n\n## State\nOld notes.\n\n## Next session\n\n**Next:** x\n<!-- next-step: kind=complete done=0 closed=0 subject=%s at=1 -->\n' "$OTHER_REL" > "$HANDOFF"
run "$WA" --complete "$PLAN_REL"
lacks "A15: a complete marker is replaced wholesale" "$(cat "$HANDOFF")" "Old notes."
mkdir -p "${WA_H%/*}"
printf '# Handoff\n\n## State\nWA notes.\n\n## Next session\n\n**Next:** y\n<!-- next-step: kind=plan done=0 closed=0 subject=%s at=1 -->\n' "$OTHER_REL" > "$WA_H"
run "$WA" --kept "$PLAN_REL"
has "A15: kept over another plan's block keeps the notes" "$(cat "$WA_H")" "WA notes."
has "A15: stderr names the subject" "$(cat "$TMP/stderr")" "next-step: replaced the block for $OTHER_REL"
rm -f "$HANDOFF" "$WA_H"
```

In Task 4's A14 lines, after the check `A14: darkmem: launches in the worktree holding the workspace`, add:

```bash
has "A14: darkmem: the prompt starts in the worktree" "$out" "Start in \`$WA_ROOT\`"
```

In `tests/dforge/next-step-print.test.sh` (lines 149, 162-165) and `tests/dagents/next-step-print.test.sh` (lines 150, 163-165), change each expected `.dforge/handoff/latest.md` (dagents `.dagents/…`) to the absolute `$ROOT/…` path and each expected launch line to its `cd '<root>' && ` form. Port the block above to `tests/dagents/next-step.test.sh` with `.dagents` for `.dforge`.

The A5 loop's `--project` case prints its prompt from the register Task 4's block commits (`docs/dforge/registers/demo.md`, one open unassigned row: "Rule on the open rows with dforge:brainstorming."), and `--complete` from the plan's Program line (sub-project 3, Session budget). Both exist in WA because they are committed before WA is created.

In `tests/dforge/next-session-routing.acceptance.test.sh`, the A9 block (`:251-260`) keeps its checks: "A9: the worktree is named" now passes through the `Launch in` line and the `Start in` sentence instead of "First enter the existing worktree". After its `has "A9: the worktree is named" "$OUT" "$WT"` line add, in both plugins' copies:

```bash
has "A9: the launch line names the worktree" "$OUT" "Launch in \`$WT\`:"
lacks "A9: no First enter sentence" "$OUT" "First enter the existing worktree"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash tests/dforge/next-step.test.sh; timeout 300 bash tests/dagents/next-step.test.sh; timeout 120 bash tests/dforge/next-step-print.test.sh; timeout 120 bash tests/dagents/next-step-print.test.sh; timeout 600 bash tests/dforge/next-session-routing.acceptance.test.sh; timeout 600 bash tests/dagents/next-session-routing.acceptance.test.sh`
Expected: FAIL — no `cd` prefix, no "Start in" sentence, the notes are dropped, the old "Launch:" line.

- [ ] **Step 3: Implement**

1. In the `block=$(` printer: prefix a non-empty `launch_cmd` per C5 (detect Windows with `command -v cygpath`); with no launch command print C5's "Launch from" line. The `Launch in` line prints `$dir` (T).
2. Build C6's sentence once (`git -C "$T" branch --show-current`; empty means detached: `git -C "$T" rev-parse --short HEAD`) and prepend it to `prompt` for every mode. Delete both `First enter the existing worktree` sentences.
3. `write_handoff`: `--complete`/`--kept` replace wholesale when the file is absent, has no `<!-- next-step:` marker, its subject equals `$rel`, its kind is `complete`, or `plan_finished` records its subject; otherwise run the existing Next-section awk merge and print C7 on stderr.
4. Update the script header (`:1-53`): the handoff is T's, and `--target` in the usage.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash tests/dforge/next-step.test.sh; timeout 300 bash tests/dagents/next-step.test.sh; timeout 120 bash tests/dforge/next-step-print.test.sh; timeout 120 bash tests/dagents/next-step-print.test.sh; timeout 600 bash tests/dforge/next-session-routing.acceptance.test.sh; timeout 600 bash tests/dagents/next-session-routing.acceptance.test.sh`
Expected: PASS, `0 failed` in each.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/next-step plugins/dagents/scripts/next-step tests/dforge/next-step.test.sh tests/dagents/next-step.test.sh tests/dforge/next-step-print.test.sh tests/dagents/next-step-print.test.sh tests/dforge/next-session-routing.acceptance.test.sh tests/dagents/next-session-routing.acceptance.test.sh
git commit -m "feat(dforge): name the target checkout in the block"
```

### Task 6: Release stop hooks on any checkout's handoff

**Files:**
- Modify: `plugins/dforge/scripts/lib/next-ending.sh` (new `ending_released_any`), `plugins/dforge/scripts/turn-end.sh` (`wrote_block`, `changed_here`), `plugins/dforge/scripts/ui-turn-end.sh` (the `ending_released` call), and the same in dagents
- Test: `tests/dforge/turn-end.test.sh`, `tests/dagents/turn-end.test.sh`, `tests/dforge/plugin-review-fixes.acceptance.test.sh`, `tests/dagents/ui-hooks.test.sh`

**Interfaces:**
- Consumes: C2 (Task 3), C4 (Task 4).
- Produces: `ending_released_any MESSAGE STAMP OWN_LATEST` — status 0 when `ending_released MESSAGE STAMP OWN_LATEST` holds, or when a C2 path other than OWN_LATEST is newer than STAMP and both its `**Status:**` and `**Next:**` lines appear in MESSAGE.

**Items:** 1

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 2 = 7

- [ ] **Step 1: Extend the test `tests/dforge/turn-end.test.sh`**

Before the summary lines at the end, add:

```bash
# --- per-worktree handoffs (spec A7, A16) ---
git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m base
WTD="$TMP/wt-hand"; git -C "$REPO" worktree add -q -b wt-hand "$WTD"
WT_LATEST="$WTD/.dforge/handoff/latest.md"; mkdir -p "${WT_LATEST%/*}"
wt_block() { sleep 1; printf '# Handoff\n\n## Next session\n\n**Status:** %s\n**Next:** %s\n' "$1" "$2" > "$WT_LATEST"; }
prompt s-wa; write_ledger 'Task 1: complete (commits a..b, review clean)'
check "A7: a held primary turn: held on a summary" "$(decision "$(stop s-wa 'Task 1 is done.')")" "block"
prompt s-wb; write_ledger 'Task 1: complete (commits a..b, review clean)'
wt_block 'wt status' 'Resume at Task 2 (Wt).'
check "A7: the worktree's block written this turn releases" "$(stop s-wb $'Stopping.\n\n## Next session\n\n**Status:** wt status\n**Next:** Resume at Task 2 (Wt).')" ""
prompt s-wc; write_ledger 'Task 1: complete (commits a..b, review clean)'
check "A7: a hand-typed block with no handoff written: held" "$(decision "$(stop s-wc $'## Next session\n\n**Status:** typed\n**Next:** typed.')")" "block"
prompt s-wd; write_ledger 'Task 1: complete (commits a..b, review clean)'
wrote_next 'Own next.'
wt_block 'other' 'Other next.'
check "A16: own block released after another worktree's later write" "$(stop s-wd $'## Next session\n\n**Status:** x\n**Next:** Own next.')" ""
prompt s-we; write_ledger 'Task 1: complete (commits a..b, review clean)'
wt_block 'other' 'Run dforge:finishing-a-development-branch.'
check "A16: another checkout's Next line alone does not release" "$(decision "$(stop s-we $'## Next session\n\n**Next:** Run dforge:finishing-a-development-branch.')")" "block"
prompt s-wf
mkdir -p "$REPO/docs/dforge/plans"; sleep 1
printf -- '- 2026-11-18 `docs/dforge/plans/2026-11-18-x.md` — merged into `main`\n' >> "$REPO/docs/dforge/plans/completed.md"
wt_block 'other' 'Other next.'
check "A16: a completed plan stays held after another worktree writes" "$(decision "$(stop s-wf 'All done.')")" "block"
```

Add the darkmem case of A7 right after it. Under darkmem progress the stop hook reads ledgers from the mirror's `work/sdd` (`turn-end.sh:69`, `:151`) and counts one only when the session checkout holds its workspace directory (`:136`), so the ledger goes in the mirror and the workspace stays local; the hold is asserted first. The release comes from a linked worktree's local handoff, which C1 keeps out of the mirror: the path this change adds.

```bash
. "$HERE/fixtures/darkmem-stores.sh"
MIRROR=$(stores_home "$HOME" "$REPO" demo local darkmem)
mkdir -p "$MIRROR/work/sdd/2026-10-12-dm" "$REPO/.dforge/sdd/2026-10-12-dm"
dm_ledger() { sleep 1; printf '# SDD ledger — plan: docs/dforge/plans/2026-10-12-dm.md\nTask 1: complete (commits a..b, review clean)\n' > "$MIRROR/work/sdd/2026-10-12-dm/progress.md"; }
prompt s-wg; dm_ledger
check "A7: darkmem: a mirror ledger holds the primary turn" "$(decision "$(stop s-wg 'Task 1 is done.')")" "block"
prompt s-wh; dm_ledger
wt_block 'dm wt' 'Resume at Task 2 (Dm).'
check "A7: darkmem: a linked worktree's local block releases" "$(stop s-wh $'## Next session\n\n**Status:** dm wt\n**Next:** Resume at Task 2 (Dm).')" ""
prompt s-wi; dm_ledger
sleep 1; printf '# Handoff\n\n## Next session\n\n**Status:** m\n**Next:** Mirror next.\n' > "$MIRROR/work/handoff/latest.md"
check "A7: darkmem: the primary's own block in the mirror's file releases" "$(stop s-wi $'## Next session\n\n**Next:** Mirror next.')" ""
rm -rf "$REPO/.dforge/sdd/2026-10-12-dm"
rm -f "$HOME/.dforge/config.json" "$HOME/.dforge/stores.json"
```

In `tests/dforge/plugin-review-fixes.acceptance.test.sh`, after the last A23 check (`A23: a pending line with no reason is still held`), add:

```bash
# Per-worktree handoff (spec A7): a block next-step wrote into a linked worktree releases the UI proof hold.
UWT="$TMP/u-wt"; git -C "$R17" worktree add -q -b u-wt "$UWT"; mkdir -p "$UWT/.dforge/handoff"
sleep 1; u_prompt u-wt1
printf '// change wt1\n' >> "$R17/src/App.tsx"; git -C "$R17" commit -qam 'ui change wt1'
check "ui-turn-end A7: held on a UI change" "$(decision "$(u_stop u-wt1 'Done.')")" "block"
sleep 1; u_prompt u-wt2
printf '// change wt2\n' >> "$R17/src/App.tsx"; git -C "$R17" commit -qam 'ui change wt2'
sleep 1; printf '# Handoff\n\n## Next session\n\n**Status:** ui wt\n**Next:** Prove the UI in the worktree.\n' > "$UWT/.dforge/handoff/latest.md"
check "ui-turn-end A7: the worktree's block releases" "$(decision "$(u_stop u-wt2 $'## Next session\n\n**Status:** ui wt\n**Next:** Prove the UI in the worktree.')")" "none"
git -C "$R17" worktree remove --force "$UWT"
```

Port the turn-end block to `tests/dagents/turn-end.test.sh` before its summary lines, with `.dagents` for `.dforge`; drop the darkmem case in dagents.

`tests/dagents/ui-hooks.test.sh` is a different harness (its own `prompt`, `stop` and `decision` helpers, the working directory `cd`'d into `$REPO`, git identity in the repository's config). Before its summary lines add:

```bash
# --- per-worktree handoff (spec A7): a block next-step wrote into a linked worktree releases the hold ---
git -C "$REPO" commit -q --allow-empty -am 'before the worktree cases'
UWT="$TMP/u-wt"; git -C "$REPO" worktree add -q -b u-wt "$UWT"; mkdir -p "$UWT/.dagents/handoff"
sleep 1; prompt u-wt1
printf '// change wt1\n' >> "$REPO/src/App.tsx"; git -C "$REPO" commit -qam 'ui change wt1'
check "A7: held on a UI change" "$(decision "$(stop u-wt1 'Done.')")" "block"
sleep 1; prompt u-wt2
printf '// change wt2\n' >> "$REPO/src/App.tsx"; git -C "$REPO" commit -qam 'ui change wt2'
sleep 1; printf '# Handoff\n\n## Next session\n\n**Status:** ui wt\n**Next:** Prove the UI in the worktree.\n' > "$UWT/.dagents/handoff/latest.md"
check "A7: the worktree's block releases" "$(decision "$(stop u-wt2 $'## Next session\n\n**Status:** ui wt\n**Next:** Prove the UI in the worktree.')")" "none"
git -C "$REPO" worktree remove --force "$UWT"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash tests/dforge/turn-end.test.sh; timeout 300 bash tests/dagents/turn-end.test.sh; timeout 300 bash tests/dforge/plugin-review-fixes.acceptance.test.sh; timeout 300 bash tests/dagents/ui-hooks.test.sh`
Expected: FAIL — the worktree's block does not release the primary turn.

- [ ] **Step 3: Implement**

1. `next-ending.sh`: add `ending_released_any` per its Produces line. Its cannot-write branch is `ending_released`'s own, applied to OWN_LATEST only. The other files come from `dforge_latest_files "$root"` (dagents `dagents_latest_files`), read in this function, with OWN_LATEST skipped; their Status and Next lines are read with the same awk as `ending_released` and matched with `grep -qF`.
2. `turn-end.sh` `wrote_block` and `ui-turn-end.sh`'s release call use `ending_released_any` with the session checkout's own handoff.
3. `changed_here` compares against the primary's handoff for the `completed.md` transition (`dforge_latest_file "$primary"`, where `$primary` is the root of `git rev-parse --git-common-dir`'s parent) and the session checkout's for the roadmap transition.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash tests/dforge/turn-end.test.sh; timeout 300 bash tests/dagents/turn-end.test.sh; timeout 300 bash tests/dforge/plugin-review-fixes.acceptance.test.sh; timeout 300 bash tests/dagents/ui-hooks.test.sh`
Expected: PASS, `0 failed` in each.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/next-ending.sh plugins/dforge/scripts/turn-end.sh plugins/dforge/scripts/ui-turn-end.sh plugins/dagents/scripts/lib/next-ending.sh plugins/dagents/scripts/turn-end.sh plugins/dagents/scripts/ui-turn-end.sh tests/dforge/turn-end.test.sh tests/dagents/turn-end.test.sh tests/dforge/plugin-review-fixes.acceptance.test.sh tests/dagents/ui-hooks.test.sh
git commit -m "fix(dforge): release on any checkout's handoff"
```

### Task 7: Read the attached plan's handoff in auto-run

**Files:**
- Modify: `plugins/dforge/scripts/lib/auto-run.sh` (`ar_handoff`, the comment in `ar_clear`), `plugins/dagents/scripts/lib/auto-run.sh` (same)
- Test: `tests/dforge/auto-run.test.sh`, `tests/dagents/auto-run.test.sh`

**Interfaces:**
- Consumes: C3 (Task 4).
- Produces: None

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6

- [ ] **Step 1: Extend the test `tests/dforge/auto-run.test.sh`**

After the `# --- clear checks whose prompt it stores (row 32) ---` block's last check, add:

```bash
# --- clear reads the attached plan's handoff (spec A8) ---
printf '# P\n\n**Execution:** inline — `claude --model sonnet --effort high` — x\n\n## Task index\n\n1. One\n\n### Task 1: One\n\nBody.\n' > "$REPO/docs/wplan.md"
git -C "$REPO" add docs/wplan.md && git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -qm wplan
ARW="$TMP/ar-wt"; git -C "$REPO" worktree add -q -b ar-wt "$ARW"
mkdir -p "$ARW/.dforge/sdd/wplan" "$ARW/.dforge/handoff" "$REPO/.dforge/sdd/wplan"
printf '# SDD ledger — plan: docs/wplan.md\nTask 1: in progress\n' > "$ARW/.dforge/sdd/wplan/progress.md"
printf '# Handoff\n\n## Next session\n\nPaste as the first prompt:\n\n```\nResume `docs/wplan.md` with dforge:resume-execution. From W.\n```\n' > "$ARW/.dforge/handoff/latest.md"
printf '# Handoff\n\n## Next session\n\nPaste as the first prompt:\n\n```\nContinue `docs/wplan.md` with dforge:executing-plans. From the primary.\n```\n' > "$REPO/.dforge/handoff/latest.md"
ar --session s-1 attach --plan docs/wplan.md
ar --session s-1 clear --phase >/dev/null 2>&1; status=$?
check "A8: clear in the primary reads the worktree's handoff" "$status:$(field resumePrompt)" "0:Resume \`docs/wplan.md\` with dforge:resume-execution. From W."
(cd "$ARW" && bash "$AR" --session s-1 clear --phase >/dev/null 2>&1); status=$?
check "A8: clear in the worktree reads its own handoff" "$status:$(field resumePrompt)" "0:Resume \`docs/wplan.md\` with dforge:resume-execution. From W."
ar --session s-1 attach --plan docs/plan.md
```

Port it to `tests/dagents/auto-run.test.sh` with `.dagents` for `.dforge` at the same anchor.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash tests/dforge/auto-run.test.sh; timeout 300 bash tests/dagents/auto-run.test.sh`
Expected: FAIL — `resumePrompt` is the primary's "From the primary." prompt.

- [ ] **Step 3: Implement**

1. At the top of `auto-run.sh`, beside the three `. "$(dirname "${BASH_SOURCE[0]}")/…"` lines, set `AR_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)` (no such variable exists today). next-step is `"$AR_LIB_DIR/../next-step"`.
2. `ar_handoff`: with a plan attached (`ar_get plan` non-empty), `latest=$(cd "$(ar_primary_root)" && bash "$AR_LIB_DIR/../next-step" --target "$plan" 2>/dev/null)`; when that fails or prints nothing, or no plan is attached, `latest=$(dforge_latest_file "$(git rev-parse --show-toplevel)")`.
3. `ar_clear`'s comment above the plan-name guard reads that the guard catches a block another session left in the plan's checkout.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash tests/dforge/auto-run.test.sh; timeout 300 bash tests/dagents/auto-run.test.sh`
Expected: PASS, `0 failed` in both.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/auto-run.sh plugins/dagents/scripts/lib/auto-run.sh tests/dforge/auto-run.test.sh tests/dagents/auto-run.test.sh
git commit -m "fix(dforge): read the attached plan's handoff"
```

### Task 8: Read the session checkout's handoff in the cockpit

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/register.tsx` (`readRun`, `resumePrompt`, `autoRunCall`), `plugins/dagents/hooks/cockpit/register.tsx` (same)
- Test: `plugins/dforge/tests/cockpit.test.ts`, `plugins/dagents/tests/cockpit.test.ts`

**Interfaces:**
- Consumes: C1 (Tasks 2-3); Task 1's probe result.
- Produces: None

**Implementer:** dforge:impl-opus-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6

- [ ] **Step 1: Extend the test `plugins/dforge/tests/cockpit.test.ts`**

In `describe('resume offer', …)`, replace the test `runs from the primary checkout when the session's directory is gone` with:

```ts
  test("runs from the primary checkout when the session's directory is gone", async ($, on) => {
    const WORKTREE = '/home/me/code/shop-wt'
    const WT_LATEST = `${WORKTREE}/.dforge/handoff/latest.md`
    const w = await begin($, on, RESUMABLE, { w: { checkout: WORKTREE }, more: { [WORKTREE]: { text: '', kind: 'dir' }, [WT_LATEST]: { text: RESUMABLE, mtimeMs: 900_000 } } })
    expect(w.nextStepRuns).toEqual([WORKTREE])
    delete w.files[WORKTREE]
    delete w.files[WT_LATEST]
    w.files[LATEST] = { ...w.files[LATEST]!, mtimeMs: 950_000 }
    await w.turn()
    expect(w.nextStepRuns).toEqual([WORKTREE, '/home/me/code/shop'])
  })

  test("reads the session worktree's handoff, not the primary's (spec A9)", async ($, on) => {
    const WORKTREE = '/home/me/code/shop-wt'
    const w = await begin($, on, RESUMABLE, { w: { checkout: WORKTREE }, more: { [WORKTREE]: { text: '', kind: 'dir' } } })
    expect(w.nextStepRuns).toEqual([])
  })

  test('names the absolute handoff path in the fallback resume prompt (spec A9)', async ($, on) => {
    const WORKTREE = '/home/me/code/shop-wt'
    const WT_LATEST = `${WORKTREE}/.dforge/handoff/latest.md`
    const w = await begin($, on, '# Handoff\n', {
      w: { checkout: WORKTREE, nextStepOuts: [{ exitCode: 0, stdout: UNFENCED }] },
      more: { [WORKTREE]: { text: '', kind: 'dir' }, [WT_LATEST]: { text: UNFENCED, mtimeMs: 900_000 } },
    })
    const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
    await pane.press({ key: 'pane-resume' })
    expect(w.prompts).toEqual([`Resume the work in ${WT_LATEST} with the dforge resume-execution skill.`])
  })

```

In `describe('auto run', …)`, after the test `compacts on the sentinel, books it and submits the continue prompt`, add a test that drives the compact stage, which is known to call `autoRunCall`:

```ts
  test('passes the session checkout to every auto-run call (spec A8)', async ($, on) => {
    const WORKTREE = '/home/me/code/shop-wt'
    const files = { ...autoFiles(), [WORKTREE]: { text: '', kind: 'dir' as const } }
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], processRuns: [], autoFile: files[AUTO], checkout: WORKTREE }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.autoRuns).toContain('--session sess-1 compacted')
    const calls = (w.processRuns ?? []).filter(argv => argv.includes('/scripts/auto-run '))
    expect(calls.length).toBeGreaterThan(0)
    for (const argv of calls) expect(argv.startsWith(`bash -c cd -- "$1" && shift && exec bash "$@" auto-run ${WORKTREE} `)).toBe(true)
  })
```

`describe('resume offer', …)`'s `LATEST` constant (`cockpit.test.ts:5342`, the primary's handoff) stays as it is: every test there but the replaced one runs with the default checkout, the primary, whose handoff it is. The replaced test (`:5695-5702`) is the one that pinned the primary's file for a worktree session.

Change `cockpit.test.ts:181` and the routing acceptance test `plugins/dforge/tests/next-session-routing.acceptance.test.ts:499,513` where they expect the primary's handoff for a worktree session, to the worktree's. Port the four tests to `plugins/dagents/tests/cockpit.test.ts` (its lines 5213, 5566 for the pinned cases) with `.dagents` for `.dforge` and `dagents` in the fallback prompt's skill name as that file's `resumePrompt` words it.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 /root/.local/bin/claude plugin test plugins/dforge; timeout 600 /root/.local/bin/claude plugin test plugins/dagents`
Expected: FAIL — the primary's handoff raises the offer in a worktree session; the auto-run argv has no `cd --` wrapper.

- [ ] **Step 3: Implement**

1. `readRun`: `const state = \`${session ?? root}/.dforge\``; when `session` is set but its directory no longer exists (`$.fs.stat`), use `root` (the primary). `latest` stays `roots?.progress.latestFile ?? \`${state}/handoff/latest.md\``.
2. `S.latestName = latest` always; `resumePrompt()` keeps its fallback text for a null name.
3. `autoRunCall`: argv `['bash', '-c', 'cd -- "$1" && shift && exec bash "$@"', 'auto-run', checkout, \`${$.plugin.root}/scripts/auto-run\`, '--session', sessionId, ...args]`, `checkout` being `S.where.checkout ?? S.where.primary ?? '.'`.
4. If Task 1's note says `$.process.run` does not follow `EnterWorktree`, `readPlace` runs its `git rev-parse --show-toplevel` as `['git', '-C', cwd, …]` with `cwd` from `$.session.cwd()`. The test world answers only the exact argv `git rev-parse --show-toplevel` (`cockpit.test.ts:582-583`, dagents the matching lines): extend that match in the same step to accept `git -C <dir> rev-parse --show-toplevel`.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 /root/.local/bin/claude plugin test plugins/dforge; timeout 600 /root/.local/bin/claude plugin test plugins/dagents`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/hooks/cockpit/register.tsx plugins/dagents/hooks/cockpit/register.tsx plugins/dforge/tests plugins/dagents/tests
git commit -m "fix(dforge): read the session checkout's handoff"
```

### Task 9: List every checkout's handoff

**Files:**
- Modify: `plugins/dforge/scripts/repo-audit` (the `## Handoff` section), `plugins/dforge/scripts/session-start.sh` (beside the roadmap line), and the same in dagents
- Test: `tests/dforge/repo-audit.test.sh`, `tests/dforge/hook.test.sh`, `tests/dagents/repo-audit.test.sh`, `tests/dagents/hook.test.sh`

**Interfaces:**
- Consumes: C2 (Task 3).
- Produces: C9, C10.

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 2 - spec 2 - coupling 1 - risk 0 = 5

- [ ] **Step 1: Extend the test `tests/dforge/repo-audit.test.sh`**

Change the staleness check at `:66`, since the own entry now counts the session checkout's HEAD:

```bash
has "primary: handoff staleness" "$out" "- Commits on this checkout's HEAD since it was written: 2"
```

Before the summary lines at the end, add. `$WT` was removed at `:88`, so the block makes its own worktrees:

```bash
# --- every checkout's handoff (spec A10) ---
A10="$TMP/a10"; git -C "$REPO" worktree add -q -b a10 "$A10"
A10_ROOT=$(git -C "$A10" rev-parse --show-toplevel)
mkdir -p "$A10/.dforge/handoff"
printf '# Handoff\n\n## Next session\n\n**Status:** a10 status\n**Next:** a10 next\n<!-- next-step: kind=adhoc done=0 closed=0 subject=- at=%s -->\n' "$(( $(date +%s) - 7200 ))" > "$A10/.dforge/handoff/latest.md"
NOH="$TMP/noh"; git -C "$REPO" worktree add -q -b noh "$NOH"
NOH_ROOT=$(git -C "$NOH" rev-parse --show-toplevel)
git -C "$REPO" worktree add -q -b gone "$TMP/gone"
GONE_ROOT=$(git -C "$TMP/gone" rev-parse --show-toplevel); rm -rf "$TMP/gone"
run "$REPO"
HSEC=$(sed -n '/^## Handoff/,/^## /p' <<<"$out")
has "A10: the own handoff first" "$(sed -n 2p <<<"$HSEC")" "- \`$ROOT/.dforge/handoff/latest.md\`"
has "A10: the worktree's handoff listed with its branch" "$HSEC" "- \`$A10_ROOT/.dforge/handoff/latest.md\` [a10]"
has "A10: marked stored with its age" "$HSEC" "- stored, not recomputed: another checkout's handoff, written 2h ago"
has "A10: its stored status" "$HSEC" "- **Status:** a10 status"
check "A10: a checkout with no handoff gets no entry" "$(grep -cF -- "$NOH_ROOT" <<<"$HSEC")" "0"
has "A10: a missing worktree is skipped" "$HSEC" "- skipped \`$GONE_ROOT\`: prunable or missing"
git -C "$REPO" worktree remove --force "$A10"; git -C "$REPO" worktree remove --force "$NOH"; git -C "$REPO" worktree prune
```

In `tests/dforge/hook.test.sh`, after the check `no roadmap: nothing injected` (the end of the `# --- a roadmap project …` checks), add. `$REPO` there has a commit and its own handoff ("Resume at Task 4 (Four)"), and `startup_payload` and `compact_payload` start sessions in it under `$HOME_D`:

```bash
# --- other checkouts' handoffs are counted on every source (spec A10) ---
git -C "$REPO" worktree add -q -b hc "$TMP/hc"; mkdir -p "$TMP/hc/.dforge/handoff"
printf '# Handoff\n\n## Next session\n\n**Next:** hc next\n' > "$TMP/hc/.dforge/handoff/latest.md"
hc_start=$(startup_payload | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
check "count line on startup" "$(grep -c '^1 other checkouts hold a handoff (scripts/repo-audit lists them)\.$' <<<"$hc_start")" "1"
hc_compact=$(compact_payload | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
check "the compaction snapshot shows only the session's handoff" "$(grep -c 'hc next' <<<"$hc_compact"):$(grep -c 'Resume at Task 4 (Four)' <<<"$hc_compact")" "0:1"
touch -d '4 days ago' "$TMP/hc/.dforge/handoff/latest.md"
check "no count line for a handoff older than three days" "$(grep -c 'other checkouts hold a handoff' <<<"$(startup_payload | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')")" "0"
git -C "$REPO" worktree remove --force "$TMP/hc"
```

Port the three changes to `tests/dagents/repo-audit.test.sh` (its staleness check and its end) and the hook block to `tests/dagents/hook.test.sh` (after its matching roadmap checks), with `.dagents` for `.dforge`.

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 300 bash tests/dforge/repo-audit.test.sh; timeout 300 bash tests/dforge/hook.test.sh; timeout 300 bash tests/dagents/repo-audit.test.sh; timeout 300 bash tests/dagents/hook.test.sh`
Expected: FAIL — only one handoff is listed, the old staleness label, no count line.

- [ ] **Step 3: Implement**

1. `repo-audit` `## Handoff`: the own entry as today, but recomputed in the session checkout (`cd "$root"`, not `"$primary"`, around `with-timeout 20 … next-step --print --latest`), and its commits-since line counts `git -C "$root"`'s HEAD and reads `- Commits on this checkout's HEAD since it was written: <n>`. Then for each other path from `dforge_latest_files` that exists, C10's lines; for each `git worktree list --porcelain` entry marked `prunable` or whose directory is missing, C10's skip line.
2. `session-start.sh`, after the roadmap line: count the paths from `dforge_latest_files` other than the session's own that exist and are younger than 3 days (`find <path> -mmin -4320`); when the count is at least 1, append C9 to `context`. The compaction snapshot (`snapshot.sh`) is unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 300 bash tests/dforge/repo-audit.test.sh; timeout 300 bash tests/dforge/hook.test.sh; timeout 300 bash tests/dagents/repo-audit.test.sh; timeout 300 bash tests/dagents/hook.test.sh`
Expected: PASS, `0 failed` in each.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/repo-audit plugins/dforge/scripts/session-start.sh plugins/dagents/scripts/repo-audit plugins/dagents/scripts/session-start.sh tests/dforge tests/dagents
git commit -m "feat(dforge): list every checkout's handoff"
```

### Task 10: Say a worktree handoff stays local on push

**Files:**
- Modify: `plugins/dforge/scripts/lib/darkmem-push.mjs` (the latest.md checkpoint step)
- Test: `tests/dforge/darkmem-sync/push.test.mjs`

**Interfaces:**
- Consumes: C1 (Task 2).
- Produces: C8.

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 0 = 4

- [ ] **Step 1: Extend the test `tests/dforge/darkmem-sync/push.test.mjs`**

Add after the test `latest.md goes up as a checkpoint on the plan its State names, or on --workstream` (import `git` and `scratch` from `./helpers.mjs` if the file does not yet):

```js
test("a push from a linked worktree says its handoff stays local (spec A11)", async t => {
  const s = await setup(t);
  write(path.join(s.workRoot, "handoff", "latest.md"), "# Handoff\n\n## State\n- Plan: `docs/superpowers/plans/p1.md`\n");
  const worktree = path.join(scratch("dms-push-wt-"), "wt");
  git(s.repo, "worktree", "add", "-q", "-b", "wt", worktree);
  write(path.join(worktree, ".dforge", "handoff", "latest.md"), "# Handoff\n\n## State\n- Plan: `docs/superpowers/plans/p2.md`\n");
  const result = await run(["push"], { cwd: worktree, env: s.env });
  assert.equal(result.code, 0, result.stdout + result.stderr);
  assert.match(result.stdout, new RegExp(`^worktree handoff stays local: ${path.join(worktree, ".dforge", "handoff", "latest.md").replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}$`, "m"));
  assert.equal(s.stub.db.workstreams.find(w => w.key === "p2"), undefined);
  const primary = await s.push();
  assert.doesNotMatch(primary.stdout, /worktree handoff stays local/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 120 node --test tests/dforge/darkmem-sync/push.test.mjs`
Expected: FAIL — no "worktree handoff stays local" line.

- [ ] **Step 3: Implement**

In the push step that reads `<mirror>/work/handoff/latest.md` (`darkmem-push.mjs:392`), keep sending only the mirror's file; when the working directory's checkout is a linked worktree (its `git rev-parse --show-toplevel` is not the primary from `--git-common-dir`), print C8 with the worktree's C1 path on stdout.

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 120 node --test tests/dforge/darkmem-sync/push.test.mjs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lib/darkmem-push.mjs tests/dforge/darkmem-sync/push.test.mjs
git commit -m "feat(dforge): say a worktree handoff stays local"
```

### Task 11: Update the skills and docs

**Files:**
- Modify (dforge): `skills/handoff/SKILL.md:89-132`, `skills/resume-execution/SKILL.md:17-18`, `skills/finishing-a-development-branch/SKILL.md:362-379`, `skills/finishing-a-development-branch/references/cleanup.md`, `skills/project-status/SKILL.md:32-35`, `skills/distilling-docs/SKILL.md:74,168`, `skills/executing-plans/SKILL.md:144-146`, `reference/project-state.md:97,106-111,131`, `reference/auto-run.md:288`, `README.md:337,719`
- Modify (dagents): the matching lines of the same skills, `README.md:440,812`, `reference/auto-run.md:259`

**Interfaces:**
- Consumes: C3, C4, C6, C8, C10.
- Produces: None

**Items:** 2

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 3 - spec 2 - coupling 0 - risk 0 = 5

- [ ] **Step 1: No new test, because the edits are prose no script reads; the suites' wording checks run in Step 3**

- [ ] **Step 2: Edit**

1. handoff step 3: write the notes to the path `scripts/next-step --target <the arguments step 4 will pass>` prints; the push note says a worktree's handoff stays local (C8).
2. resume-execution step 1: read the handoff the first prompt names by absolute path; the session checkout's only when it names none.
3. finishing: under Option 1, before Step 6, when the session worked in a linked worktree, read the worktree's handoff; an open item in its notes counts as something that follows, beside register rows and findings; write the notes sections with every open item to the path `next-step --target --adhoc …` prints in the primary, then run `--adhoc`. The same carry in `references/cleanup.md` where a host-owned worktree is left in place. Remove "One latest.md" wording.
4. project-status: list every checkout's handoff as repo-audit prints it, and recommend the session's own.
5. distilling-docs, executing-plans, project-state, auto-run.md, README: the handoff is per checkout (C1), next-step writes T's (C4), the prompt opens with C6.

- [ ] **Step 3: Verify**

Run: `timeout 120 node scripts/validate-repository.mjs; timeout 900 node scripts/test-all.mjs; timeout 900 node scripts/test-all.mjs --plugin dagents; for p in plugins/dforge plugins/dagents plugins/dflow; do timeout 300 /root/.local/bin/claude plugin validate "$p"; done; timeout 300 /root/.local/bin/claude plugin validate .`
Expected: every command exits 0. A wording test that pins old text fails here: update its expectation to the new wording only when the new wording is what the spec asks for.

- [ ] **Step 4: Commit**

```bash
git add plugins/dforge plugins/dagents tests
git commit -m "docs(dforge): describe per-checkout handoffs"
```
