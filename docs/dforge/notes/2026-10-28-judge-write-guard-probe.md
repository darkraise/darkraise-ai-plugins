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

## Residuals

1. A session where the cockpit mod does not load runs without the guard (the spec's accepted residual). This probe shows the mod loads in `claude -p --plugin-dir` and in an interactive session on this host, and says nothing about older Claude Code releases.
2. The review dispatch also names the implementer's report (`task-<N>-report.md`, which ends in `-report.md`), so a judge may rewrite that file as well as its own report.
3. On Windows, task-step names report paths in the `C:/…` long form (`dforge_workspace`, `scripts/lib/roots.sh:21-34`), the form the cockpit's roots take, and `canonPath` also maps a Git Bash `/c/…` spelling to `c:/…`. No Windows host ran this probe.
4. The guard fails closed on a spelling mismatch, a `..` segment and a symbolic link, never on a missing root.

## Verdict

HOLDS: in both modes the guard refused the write outside the named report and allowed the report.
