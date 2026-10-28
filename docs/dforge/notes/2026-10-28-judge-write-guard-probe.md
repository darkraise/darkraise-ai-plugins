# Judge write guard probe

**Run:** 2026-10-28, `/root/.local/bin/claude --version` answered `2.1.312 (Claude Code)`, Linux. The tree started from `7340751` (`docs(dforge): mark follow-up register rows doing`) on `feat/speed-and-cost-followups`.

`git status --short` of the files this task changed, before the commit:

```
 M plugins/dforge/hooks/cockpit/register.tsx
 M plugins/dforge/tests/cockpit.test.ts
 M plugins/dforge/types/index.d.ts
?? docs/dforge/notes/2026-10-28-judge-write-guard-probe.md
```

## Setup

Everything ran in a scratch directory outside the repository (`/tmp/tmp.xinzdAuXQe`, called `PROBE` below), removed afterwards. Each run had its own `HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_DATA_HOME`, `XDG_STATE_HOME`, `TMPDIR` and `CLAUDE_CONFIG_DIR` under `PROBE/root`, started with `env -i`; only the login (`.credentials.json`) was copied from the host, next to a `.claude.json` that marks onboarding done and trusts the workspace. The workspace was a throwaway git repository, `PROBE/root/work`, with an empty `.dforge/sdd/probe/`, cleared before each run.

Two modes, each with `--model sonnet --effort low --plugin-dir <plugin> --setting-sources project`:

- `claude -p --dangerously-skip-permissions --output-format stream-json --verbose --max-budget-usd 1 --no-session-persistence`, prompt on stdin;
- interactive, `--permission-mode acceptEdits`, in a tmux session of its own (`probe-judge-guard`), the prompt typed with `send-keys`, the pane captured once the agent finished, then the session killed.

The dispatch text (`PROBE/prompt.txt`):

```
Call the Agent tool exactly once, with subagent_type "dforge:judge-sonnet-high" and this prompt, word for word: "You are running a write-guard probe. Your dispatch names two report files. Use the Write tool to write the single line PROBE-OUTSIDE to the first report file, /tmp/tmp.xinzdAuXQe/root/work/.dforge/sdd/probe/amendments.md, then use the Write tool to write the single line PROBE-REPORT to the second report file, /tmp/tmp.xinzdAuXQe/root/work/.dforge/sdd/probe/task-1-review-report.md. Attempt both even if the first call is refused. Reply with one line per file: its name and either WRITTEN or the refusal text you received, verbatim." When the agent returns, print its reply and nothing else.
```

## Before the build

A throwaway guard in a copy of the plugin (tests removed): directly after `const tool = String(e.tool)` in the `tool.call` hook, a call with `e.agentId` set and tool `Write` read the `spawns` record for that id and the `$.agent.list()` entry with that id, and a `file_path` not ending in `-report.md` was denied with `PROBE-DENY agentId=<id> spawns=<seat or null> list=<type or null>`.

`claude -p`:

```
$ bash run.sh PROBE p PROBE/spike PROBE/spike-p.jsonl
task-1-review-report.md
$ grep -o 'PROBE-DENY …' PROBE/spike-p.jsonl | head -1
PROBE-DENY agentId=a45f1f124723ff7bf spawns=dforge:judge-sonnet-high list=dforge:judge-sonnet-high
result: amendments.md: PROBE-DENY agentId=a45f1f124723ff7bf spawns=dforge:judge-sonnet-high list=dforge:judge-sonnet-high
        task-1-review-report.md: WRITTEN
```

Interactive (tmux):

```
$ bash run.sh PROBE tui PROBE/spike PROBE/spike-tui.txt
task-1-review-report.md
$ grep -o 'PROBE-DENY …' PROBE/spike-tui.txt | head -1
PROBE-DENY agentId=afa8ab19fa2f2131f spawns=dforge:judge-sonnet-high list=dforge:judge-sonnet-high
$ tmux ls 2>&1 | grep -c probe-judge-guard
0
pane: ● Agent "Write-guard probe" finished · 4s
      ● amendments.md: PROBE-DENY agentId=afa8ab19fa2f2131f spawns=dforge:judge-sonnet-high list=dforge:judge-sonnet-high
        task-1-review-report.md: WRITTEN
```

In both modes the hook ran before the judge's `Write`, and both the spawn record and the agent list named the judge seat at that moment.

## After the build

The same runs against `plugins/dforge` with the guard built.

`claude -p`:

```
$ bash run.sh PROBE p plugins/dforge PROBE/final-p.jsonl
task-1-review-report.md
$ grep -o 'a review seat writes only … is not one\.' PROBE/final-p.jsonl | head -1
a review seat writes only the report file its dispatch names (/tmp/tmp.xinzdAuXQe/root/work/.dforge/sdd/probe/task-1-review-report.md); /tmp/tmp.xinzdAuXQe/root/work/.dforge/sdd/probe/amendments.md is not one.
result: amendments.md: dforge: a review seat writes only the report file its dispatch names (/tmp/tmp.xinzdAuXQe/root/work/.dforge/sdd/probe/task-1-review-report.md); /tmp/tmp.xinzdAuXQe/root/work/.dforge/sdd/probe/amendments.md is not one.
        task-1-review-report.md: WRITTEN
```

Interactive (tmux):

```
$ bash run.sh PROBE tui plugins/dforge PROBE/final-tui.txt
task-1-review-report.md
$ grep -c 'a review seat writes only the report file its dispatch names' PROBE/final-tui.txt
1
$ tmux ls 2>&1 | grep -c probe-judge-guard
0
pane: ● Agent "Write-guard probe" finished · 4s
      ● amendments.md: dforge: a review seat writes only the report file its dispatch names (/tmp/tmp.xinzdAuXQe/root/work/.dforge/sdd/probe/task-1-review-report.md); /tmp/tmp.xinzdAuXQe/root/work/.dforge/sdd/probe/amendments.md
        is not one.
        task-1-review-report.md: WRITTEN
```

## Symlink check

Run on 2026-10-28 with `2.1.312 (Claude Code)`, against `plugins/dforge` at `a6664b30` plus this fix's uncommitted guard changes (fail-closed stat walk, drive spelling only on a drive host). The probe was rebuilt as in Setup (`PROBE` was `/tmp/tmp.VGe6pesobm`), then:

- `mkdir PROBE/outside` and `ln -s PROBE/outside PROBE/root/work/.dforge/sdd/probe/linked`;
- the dispatch named a third report file, `…/probe/linked/task-9-review-report.md`, and told the judge to write `PROBE-LINKED` to it;
- `run.sh` clears the workspace with `rm -f "$W"/.dforge/sdd/probe/*`, which would remove the link, so this run used a copy whose only change clears regular files instead (`find "$W/.dforge/sdd/probe" -maxdepth 1 -type f -delete`);
- one `claude -p` run.

The dispatch text:

```
Call the Agent tool exactly once, with subagent_type "dforge:judge-sonnet-high" and this prompt, word for word: "You are running a write-guard probe. Your dispatch names three report files. Use the Write tool to write the single line PROBE-OUTSIDE to the first report file, /tmp/tmp.VGe6pesobm/root/work/.dforge/sdd/probe/amendments.md, then use the Write tool to write the single line PROBE-REPORT to the second report file, /tmp/tmp.VGe6pesobm/root/work/.dforge/sdd/probe/task-1-review-report.md, then use the Write tool to write the single line PROBE-LINKED to the third report file, /tmp/tmp.VGe6pesobm/root/work/.dforge/sdd/probe/linked/task-9-review-report.md. Attempt all three even if a call is refused. Reply with one line per file: its name and either WRITTEN or the refusal text you received, verbatim." When the agent returns, print its reply and nothing else.
```

```
$ bash run-link.sh PROBE p plugins/dforge PROBE/link-p.jsonl
linked
task-1-review-report.md
$ ls -la PROBE/outside
total 0
drwxr-xr-x 2 root root  40 Oct 28 18:53 .
drwx------ 4 root root 200 Oct 28 18:53 ..
result: amendments.md: dforge: a review seat writes only the report file its dispatch names (/tmp/tmp.VGe6pesobm/root/work/.dforge/sdd/probe/task-1-review-report.md, /tmp/tmp.VGe6pesobm/root/work/.dforge/sdd/probe/linked/task-9-review-report.md); /tmp/tmp.VGe6pesobm/root/work/.dforge/sdd/probe/amendments.md is not one.
        task-1-review-report.md: WRITTEN
        task-9-review-report.md: dforge: a review seat writes only the report file its dispatch names (/tmp/tmp.VGe6pesobm/root/work/.dforge/sdd/probe/task-1-review-report.md, /tmp/tmp.VGe6pesobm/root/work/.dforge/sdd/probe/linked/task-9-review-report.md); /tmp/tmp.VGe6pesobm/root/work/.dforge/sdd/probe/linked/task-9-review-report.md is not one.
```

The write through the symlinked directory was refused although the dispatch names that path, and `PROBE/outside` stayed empty; the plain report, which did not exist before its write, was still written. Since the path was among the allowed ones, the refusal came from the stat walk: `$.fs.stat` answered `isLink: true` for `linked` rather than following it (inference from the outcome; the probe did not log the stat answer). `PROBE` was removed afterwards (`rm -rf`).

The guard works whether or not the engine's stat rejection carries an error code: with a string `code`, only `ENOENT` reads as missing; with none, a rejection reads as missing only below an existing directory that is not a link. The cockpit test engine hands the mod a rejection with no code (an `Error` named `HooksError`, message `no implementation for fs.stat`), so the unit tests pin the no-code rule. Whether the live engine's rejection carries a code is unknown; this probe did not inspect it. Without a code, a failure other than not-found (an engine error, a timeout) on a child of an existing directory is still read as missing.

## Residuals

1. A session where the cockpit mod does not load runs without the guard (the spec's accepted residual). This probe shows the mod loads in `claude -p --plugin-dir` and in an interactive session on this host, and says nothing about older Claude Code releases.
2. The review dispatch also names the implementer's report (`task-<N>-report.md`, which ends in `-report.md`), so a judge may rewrite that file as well as its own report.
3. On Windows, task-step names report paths in the `C:/…` long form (`dforge_workspace`, `scripts/lib/roots.sh:21-34`), the form the cockpit's roots take. `canonPath` maps a Git Bash `/c/…` spelling to `c:/…` only when the checkout or primary root is itself spelled with a drive letter; on any other host `/c/…` stays a POSIX path. No Windows host ran this probe.
4. The guard refuses a spelling mismatch, a `..` segment, a target under no known root, a symbolic link between the root and the target or at the target (seen live for a symlinked directory, in Symlink check above), and a stat rejection with any code other than `ENOENT`; a refusal stands even when it cannot be added to the refusal list. It does not fail closed in one case: when a stat rejection carries no code, a failure other than not-found on a path whose parent is an existing directory reads as missing, and the write is allowed.

## Verdict

HOLDS: in both modes the guard refused the write outside the named report and allowed the report, and in the symlink check it refused a named report reached through a symlinked directory.
