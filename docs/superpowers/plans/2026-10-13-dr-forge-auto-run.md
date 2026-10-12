# dr-forge Auto Run Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An opt-in dr-forge auto run that, once the design is approved, writes the spec and plan, executes, reviews and finishes with no question to the human, compacting its own context at task boundaries.

**Architecture:** A bash state script (`scripts/auto-run`, `scripts/lib/auto-run.sh`) owns a session-bound JSON state file and the compaction rules; the budget line consults it; the Stop hook lets a run's turn end only on a sentinel line; the cockpit mod compacts, or clears and resumes, after such a turn, retrying the stage that failed; the skills and references carry the unattended behaviour.

**Tech Stack:** bash + jq (scripts and tests), TypeScript/TSX Claude Code mod (`claude-code` module, `claude-code/testing`), Markdown skills.

**Spec:** docs/superpowers/specs/2026-10-13-dr-forge-auto-run-design.md

**Execution:** subagent — `claude --model sonnet --effort high` — the plan runs parallel waves

**Plan review:** 2026-10-13 — dr-superpowers:judge-opus — executability 16 / coherence 17 / coverage 16 / assumptions 13 (round 2)

**Parallelism:** waves — 1 | 2 | 3 | 4-6 | 7 | 8 | 9-10 | 11

**Integration check:** `timeout 2700 node scripts/test-all.mjs` from the repository root

**Worktree setup:** none

> **External executors:** codex

## Global Constraints

- All paths below are relative to `plugins/dr-forge/` unless they start with `docs/`, or name the repository-root scripts `scripts/test-all.mjs` and `scripts/validate-repository.mjs`.
- English only. No AI attribution in commits. Commit messages: `<type>(dr-forge): <subject>`, subject at most 50 characters, imperative, no period.
- Inside `plugins/dr-forge/`, never write `dr-superpowers:` or `superpowers:` skill references; write `dr-forge:<name>` (`scripts/validate-repository.mjs` rejects the legacy names).
- Comments only where the why is non-obvious, matching the surrounding files.
- Bash executables use `set -uo pipefail`; libraries are sourced and define functions only. Every two-word option in an argument loop is guarded by `[ $# -ge 2 ] || usage` before `shift 2`.
- Shell tests use their own `mktemp -d` HOME and repository, unset `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_SESSION_ID` and `DR_FORGE_BUDGET` at the top, and never touch the real home directory; `tests/cockpit.test.ts` runs in its own process. No two tasks' tests share a path, port or global state.
- The mod (`hooks/cockpit/*.ts*`): `$` may only be passed to functions declared at the top level of `register.tsx`; an inline callback may call such a function with `$`. `lib.ts` functions are pure (no `$`).
- Bound every run: shell suites `timeout 600 bash plugins/dr-forge/tests/<name>.test.sh`; the mod suite `timeout 600 claude plugin test plugins/dr-forge`; both from the repository root.
- Versions: both `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json` become `2.2.0` (Task 11 only).

## Contracts

**C1. State file.** `<primary checkout>/<state>/sdd/auto-run.json`, `<state>` from `forge_dir state` (`.forge`, or `.superpowers` in a pre-2.0 checkout); the primary checkout is the top level of the directory holding `git rev-parse --path-format=absolute --git-common-dir`. `sdd/` holds a `.gitignore` containing `*`. JSON fields:

| Field | Type | Meaning |
|---|---|---|
| `active` | boolean | true from `start` until `stop` |
| `session` | string | the one session id the run is bound to |
| `rebind` | boolean | a clear awaits its new session |
| `stopped` | string \| null | why the run stopped; null while active or when finished |
| `startedAt` | string | UTC ISO time |
| `spec`, `register` | string | repository-relative paths |
| `plan` | string \| null | repository-relative, null until `attach` |
| `base` | string \| null | the branch checked out where `start` ran; null on a detached HEAD |
| `phase` | `spec` \| `plan` \| `execute` \| `final` \| `finish` | |
| `regime` | `normal` \| `high` | |
| `pending` | null \| `compact` \| `after-compact` \| `clear` \| `resume` | |
| `resumePrompt` | string \| null | first prompt after a clear |
| `launch` | `{model, effort}` \| null | model and effort after a clear |
| `failures` | number | consecutive failed cockpit actions |
| `compactions` | number | |
| `resumes` | number | self-resume clears in a row since a task completed |
| `decisions` | `{id, question, options, opusReason, task}`[] | pending list; `task` string or null |
| `rulings` | string[] | rulings made before the plan's ledger exists |

**C2. CLI `scripts/auto-run [--session ID] COMMAND`.** `--session` names the caller; default `$CLAUDE_CODE_SESSION_ID`. A caller whose id is not `session` of an active run sees no run. Exit: 0 done; 2 usage, no session id or no jq; 3 no run bound to this session; 4 refused; 5 the run stopped (for `verdict` and `after-compact`: `handoff`); 6 `compact` (`verdict` only).

| Command | Effect |
|---|---|
| `start --spec P [--register R] [--force]` | new run bound to the caller; `base` from `git symbolic-ref --short -q HEAD` where it runs; without `--register` creates `<docs>/registers/<YYYY-MM-DD>-<slug>-auto.md` under the top level of the checkout it runs in (slug: spec basename less a `YYYY-MM-DD-` prefix and `-design.md`) and prints its path; exit 4 while another active run's session has written its transcript within 60 minutes |
| `status` | `auto run: <phase> — regime <regime> — pending <pending\|none> — <n> compactions — <n> resumes — <n> pending decisions — spec <spec> — plan <plan\|none> — base <base\|none> — register <register>` |
| `pending` | prints `compact`, `after-compact`, `clear`, `resume` or `none` |
| `attach --plan P` | sets `plan` |
| `phase spec\|plan\|execute\|final\|finish` | sets `phase` |
| `task-complete` | `resumes = 0` |
| `clear [--phase]` | reads `<state>/handoff/latest.md` of the primary checkout: the fenced block after the line starting `Paste as the first prompt:` → `resumePrompt`; the first line of the fenced block after the line starting `Launch in `, matched by `claude --model M --effort E` → `launch`; sets `pending = clear`, `rebind = true`; without `--phase` adds 1 to `resumes`, and when that reaches 3 stops the run with reason `three self-resumes without a completed task` and exits 5 |
| `rebind --to ID` | only while `rebind` is true (else exit 4); `session = ID`, `rebind = false`, `pending = resume`, `failures = 0`, `regime = normal`; no caller check |
| `resumed` | `pending = null` when it is `resume` |
| `compacted` | `compactions += 1`, `failures = 0`, `pending = after-compact` |
| `failure [--reason TEXT]` | `failures += 1`; at 2 stops the run with TEXT (default `the cockpit could not compact or clear`) and exits 5 |
| `decision add --id ID --question Q [--options O] [--opus-reason R] [--task N]` | replaces any decision with that id |
| `decision list` | one compact JSON object per line |
| `decision clear [--id ID]` | one, or all |
| `ruling add TEXT` / `ruling list` | append to `rulings` / print one per line |
| `stop [--reason TEXT]` | `active = false`, `stopped = TEXT or null`, `pending = null` |
| `verdict --tokens T --budget B --window W [--wave N]` | (Task 3) prints `<ok\|compact\|handoff> <limit> <regime>`; exit 0, 6, 5 |
| `after-compact` | (Task 3) measures the `--session` session's context; prints `continue — <k>k after compaction; regime <r>` (exit 0), `continue — the size after compaction is unknown; …` (exit 0) or `handoff — …` (exit 5) |

**C3. Library `scripts/lib/auto-run.sh`** (sourced; `AR_SESSION` names the caller): `ar_primary_root`, `ar_path`, `ar_state`, `ar_bound`, `ar_update FILTER [jq options]`, `ar_get FIELD`, `ar_transcript SESSION`, `ar_is_stale`, `ar_start SPEC REGISTER FORCE`, `ar_status`, `ar_pending`, `ar_stop [REASON]`, `ar_fenced FILE PREFIX`, `ar_clear PHASE`, `ar_rebind ID`, `ar_resumed`, `ar_compacted`, `ar_failure [REASON]`, `ar_decision_add`, `ar_decision_list`, `ar_decision_clear [ID]`, `ar_ruling_add TEXT`, `ar_ruling_list`; Task 3 adds `ar_limit BUDGET WINDOW N REGIME`, `ar_after P BUDGET WINDOW` (prints `handoff`/`high`/`normal`), `ar_settle P BUDGET WINDOW` (prints `continue`/`handoff`), `ar_verdict TOKENS BUDGET WINDOW [N]`.

**C4. Rules.** limit = (regime `high` ? ⌊W·90/100⌋ : B) − (N−1)·140000, at least 1. `compact` when tokens ≥ limit, which sets `pending = compact`; `ok` clears a `pending = compact` left by a wider probe. After a compaction of size P: P·100 ≥ W·85 → `handoff`; else P·100 ≥ B·85 → `high`; else `normal`. A `verdict` with `pending = after-compact` settles first with T as P; with `pending = clear`, or a settle that says `handoff`, it prints `handoff`. B is `DR_FORGE_BUDGET`, else `handoffTokens`, else `ctx_budget MODEL` (604,000 at an 800,000 window).

**C5. Budget line in an auto run** (Task 6), for every `scripts/context-size` mode but `--plan`, when `ar_bound`: `budget (auto[, high][, wave of N]): <T>k of <limit>k (<pct>%) — <ok|compact|handoff> — source: <source>`; B as in C4; W is `ctx_window MODEL`; exit 0 ok, 6 compact, 5 handoff.

**C6. Sentinels.** A turn of a bound run ends, as the last non-blank line of the message, on `Auto run: compacting` (answers `pending = compact`) or `Auto run: clearing` (answers `pending = clear`).

**C7. Cockpit lib (`hooks/cockpit/lib.ts`).** `autoRunFor(text: string, sessionId: string): CockpitAutoRun | null` (null unless `session` equals `sessionId`; returns inactive runs too), `AUTO_SENTINELS`, `endsOnSentinel(answer: string, pending: string | null): boolean`; Task 7 adds `autoLimitFor(regime: string, configured: number, window: number, compactWindow?: number): number`. Type `CockpitAutoRun` in `types/index.d.ts`: `{ active: boolean; phase: string; regime: string; pending: string | null; plan: string | null; compactions: number; resumes: number; stopped: string | null; resumePrompt: string | null; launch: { model: string; effort: string } | null }`; atom key `autoRun: CockpitAutoRun | null`.

**C8. Cockpit top-level functions (`register.tsx`, Task 5)** that Task 7 calls: `readAutoRun($): Promise<CockpitAutoRun | null>`, `autoRunCall($, sessionId: string, args: string[]): Promise<number>` (the exit code; 1 when it could not run), `trackAutoRun($): Promise<void>` (refreshes the `autoRun` atom; sends the Discord `blocked` notice once on an active-to-stopped transition with a reason), `bookAutoCompaction($)`. The atom `autoRun` is declared in `register.tsx` by Task 5.

**C9. Cockpit test helpers (`tests/cockpit.test.ts`, Task 5)** that Task 7 uses: `AUTO` (the state file path `/home/me/code/shop/.forge/sdd/auto-run.json`), `autoFiles(fields?)` (a `World['files']` holding a bound active run with `pending: 'compact'`, overridable), `settle(clock)`, and the `World` fields `autoRuns`, `autoFile`, `autoRunExits`.

**C10. Deferred task ledger line.** A task the auto run cannot do, and every task that depends on it, ends with `Task <N>: complete (deferred by the auto run) — done: nothing; verified: not run; remaining: <the item>[; partial commits <a7>..<b7>, kept for the final review]; discovered: none; assumptions: none; Ruling: <why> — <cost if wrong>`. Commits a deferred task already made stay, named in `remaining:`. `scripts/lib/plan.sh` counts any `Task N: complete…` line as done, so recovery, `next-step` and the final review treat it as terminal; in a wave its branch is not merged. Each such task also gets a deferred register row.

**C11. Reference.** `reference/auto-run.md` (Task 2) is the contract skills cite as `[auto-run.md](../../reference/auto-run.md)`; sections: Starting, While a run is bound to this session, The spec, Rulings, The budget line, Ending a turn, After a compaction, Clears, Stopping, Finishing. **Setting** `autoRun` in `config/schema.mjs`: enum `ask` | `off`, default `ask`, group Workflow, `enforcedBy: 'skill'`.

## Assumptions (evidence)

- The Bash tool environment carries `CLAUDE_CODE_SESSION_ID` (`echo` in this session, 2026-10-13: `f6f90474-…`), and Claude Code resets it to the new session's id on `/clear`: the 2.1.296 CLI's clear path runs `if(a.CLAUDE_CODE_SESSION_ID)process.env.CLAUDE_CODE_SESSION_ID=K()` (`grep -a` of `~/.local/share/claude/versions/2.1.296`, 2026-10-13), so the single `session` binding follows a clear.
- `scripts/lib/plan.sh:51-54` `ledger_done` matches `^Task N: complete.*`, so C10's line is terminal without script changes; `ledger_blocked` (`plan.sh:79-91`) would instead stop the run for a human.
- `$.session.compact` runs only between turns and resolves `{ skip }` on a veto; `$.command.run` rejects inside a hook the turn waits on; `$.prompt.submit` runs once idle; `$.session.id()` changes after `/clear` (`plugins/dr-forge/.claude-plugin/types/claude-code/index.d.ts`: `session.compact` near line 2872, `command.run` near 3073, `SessionCompactSkipped` near 10841, `session.end` near 11060).
- `S.isTurnLive` is true while a main turn runs (`register.tsx:2019-2021`, set from the activity `turn.start` writes), so the actuator can tell a live turn from an idle session.
- An inline callback passing `$` to a top-level function is accepted by the mod loader (memory `mod-hooks-need-top-level-functions`; `register.tsx:2059` does it).
- `claude-code/testing` drives `$.turn.start`, `$.turn.complete`, `$.session.compact`, `$.agent.spawn`, a mock clock with `advance`, and `ui.press` (`tests/cockpit.test.ts:348,488,743,1604`).
- unverified — Task 10 writes the smoke checklist that settles these; running it needs a Claude Code session started on this branch's plugin build, so the owner runs it after the plan finishes, and register rows 5, 8 and 9 stay `verify` until it is recorded: `/clear`, `/model`, `/effort` through `$.command.run`; the prompt submitted after `/clear`; that the environment reset above reaches the Bash tool's shell (row 7); `SessionStart` hooks firing for mod-driven compaction and clear.
- Plan review round 2 scored assumptions 13 (borderline): its open item was the session id after `/clear`, settled by the CLI source above; the rest are the smoke checklist's rows, which only a session on this branch's build can observe.
- Plan-level decisions within the spec (recorded so a reviewer can object): only the explicit `rebind --to` command rebinds (the spec's "first call from another session" would let an unrelated session's budget line capture the run); a booked engine compaction uses the same `compacted` command as the cockpit's own; a failed cockpit stage is retried after 5 seconds, re-checking for a live turn and background work first, since nothing starts a next turn while the session is idle; after a compaction the run recovers through the execution skill's own After compaction steps, not resume-execution, because `latest.md` predates the execution worktree; the step that hands off owns `auto-run clear`, not the handoff skill; a planning choice Fable does not rule takes the option listed first and is recorded as unconfirmed; the auto line and **Stop auto** button sit in the pane's action row, which both surfaces draw whether or not a ledger exists; the Stop hook holds every non-sentinel ending of a bound run's turn once (the spec held only the ledger cases; otherwise a summary in the spec or plan phase would end the run silently); the version bump moves to the documentation task, as the 2.1.0 release did (`9548101`).

## Task index

1. Auto-run state core
2. autoRun setting, brainstorming offer and the reference
3. Compaction rules
4. Stop hook sentinel gate
5. Cockpit actuator
6. Auto budget line
7. Cockpit auto line and muted note
8. Planning, worktree, handoff, resume and finishing skills
9. Execution skills
10. Smoke-run checklist
11. Reference docs, README, release 2.2.0 and final verification

---

### Task 1: Auto-run state core

**Files:**
- Create: `scripts/lib/auto-run.sh`
- Create: `scripts/auto-run` (mode 755)
- Test: `tests/auto-run.test.sh` (mode 755)

**Interfaces:**
- Consumes: `scripts/lib/forge-dir.sh` (`forge_dir`, `forge_dir_rel`).
- Produces: C1, C2 (all commands but `verdict` and `after-compact`), C3 (all but Task 3's functions).

**Items:** 1, 9

**Depends on:** none

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

Create `tests/auto-run.test.sh` with exactly this content:

````bash
#!/usr/bin/env bash
# An auto run is one state file in the primary checkout's self-ignoring sdd/
# directory, bound to one session: another session sees no run, a stale run
# gives way, and each command changes only what it names.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AR="$HERE/../scripts/auto-run"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export MSYS_NO_PATHCONV=1 DR_FORGE_NO_SETTINGS=1 GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset DR_FORGE_BUDGET DR_FORGE_JQ DR_SUPERPOWERS_BUDGET DR_SUPERPOWERS_JQ CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID

REPO="$TMP/repo"
git init -q -b main "$REPO"
git -C "$REPO" commit -q --allow-empty -m init
STATE="$REPO/.forge/sdd/auto-run.json"
SPEC=docs/forge/specs/2026-10-13-widget-design.md
ar() { (cd "$REPO" && bash "$AR" "$@"); }
field() { jq -r --arg f "$1" '.[$f] | tostring' "$STATE"; }
# A session's by-id record and transcript, written now or at a touch -d time.
live() { # live <session> [touch -d argument]
  local rec="$HOME/.claude/dr-forge/sessions/by-id/$1.json" tp="$HOME/.claude/projects/p/$1.jsonl"
  mkdir -p "$(dirname "$rec")" "$(dirname "$tp")"
  printf '{}\n' > "$tp"
  [ -z "${2:-}" ] || touch -d "$2" "$tp"
  jq -n --arg tp "$tp" '{transcript_path: $tp}' > "$rec"
}

# --- start ---
out=$(ar start --spec "$SPEC" 2>&1); status=$?
check "start without a session: exit 2" "$status" "2"
check "start without a session: says why" "$(grep -c 'no session id' <<<"$out")" "1"
out=$(ar --session s-1 start --spec "$SPEC" 2>&1); status=$?
check "start: exit 0" "$status" "0"
reg="docs/forge/registers/$(date +%Y-%m-%d)-widget-auto.md"
check "start: prints the register it created" "$out" "$reg"
check "start: the register has the table header" "$(grep -c '^| # | Item | Assigned | Acceptance | State | Note |$' "$REPO/$reg")" "1"
check "start: the register covers the spec" "$(grep -c "^\*\*Covers:\*\* $SPEC$" "$REPO/$reg")" "1"
check "start: active, bound, based on main" "$(field active) $(field session) $(field base)" "true s-1 main"
check "start: phase spec, regime normal" "$(field phase) $(field regime)" "spec normal"
check "start: nothing pending" "$(field pending)" "null"
check "start: the state file is ignored by git" "$(git -C "$REPO" status --porcelain -- .forge | grep -c .)" "0"

# --- binding ---
ar --session s-2 status >/dev/null 2>&1; status=$?
check "another session: no run (exit 3)" "$status" "3"
ar --session s-2 stop >/dev/null 2>&1; status=$?
check "another session cannot stop it" "$status:$(field active)" "3:true"
out=$(ar --session s-1 status); status=$?
check "status: exit 0" "$status" "0"
check "status: one line" "$out" "auto run: spec — regime normal — pending none — 0 compactions — 0 resumes — 0 pending decisions — spec $SPEC — plan none — base main — register $reg"
check "pending: none" "$(ar --session s-1 pending)" "none"
check "the environment names the session" "$(cd "$REPO" && CLAUDE_CODE_SESSION_ID=s-1 bash "$AR" pending)" "none"

# --- a second start ---
live s-1
ar --session s-2 start --spec "$SPEC" --register docs/r.md >/dev/null 2>&1; status=$?
check "a second start while the first is live: exit 4" "$status:$(field session)" "4:s-1"
live s-1 '2 hours ago'
ar --session s-2 start --spec "$SPEC" --register docs/r.md >/dev/null 2>&1; status=$?
check "a stale run gives way" "$status:$(field session):$(field register)" "0:s-2:docs/r.md"
mkdir -p "$HOME/.claude/projects/q"
printf '{}\n' > "$HOME/.claude/projects/q/s-2.jsonl"
ar --session s-1 start --spec "$SPEC" --register docs/r.md >/dev/null 2>&1; status=$?
check "a live transcript without a record still counts" "$status:$(field session)" "4:s-2"
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null 2>&1; status=$?
check "--force replaces a live run" "$status:$(field session)" "0:s-1"

# --- a start from a linked worktree ---
git -C "$REPO" worktree add -q -b side "$TMP/side"
out=$(cd "$TMP/side" && bash "$AR" --session s-5 start --spec "$SPEC" --force 2>&1); status=$?
check "worktree: the register is created in that checkout" "$status:$([ -f "$TMP/side/$reg" ] && echo yes)" "0:yes"
check "worktree: the state stays in the primary checkout" "$(field session) $(field base)" "s-5 side"
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null

# --- progress ---
ar --session s-1 attach --plan docs/plan.md
ar --session s-1 phase execute
check "attach and phase" "$(field plan) $(field phase)" "docs/plan.md execute"
ar --session s-1 phase later >/dev/null 2>&1; status=$?
check "an unknown phase: exit 2" "$status:$(field phase)" "2:execute"

# --- decisions and rulings ---
ar --session s-1 decision add --id d1 --question "Which store?" --options "sqlite | files" --opus-reason "the spec is silent" --task 3
ar --session s-1 decision add --id d2 --question "Retry count?"
check "decision list" "$(ar --session s-1 decision list | jq -r '.id' | paste -sd, -)" "d1,d2"
check "a decision keeps its fields" "$(ar --session s-1 decision list | jq -r 'select(.id == "d1") | "\(.options)|\(.opusReason)|\(.task)"')" "sqlite | files|the spec is silent|3"
ar --session s-1 decision add --id d1 --question "Which store, again?"
check "adding an id again replaces it" "$(ar --session s-1 decision list | jq -r 'select(.id == "d1") | .question')" "Which store, again?"
ar --session s-1 decision clear --id d1
check "clear one" "$(ar --session s-1 decision list | jq -r '.id' | paste -sd, -)" "d2"
ar --session s-1 decision clear
check "clear all" "$(ar --session s-1 decision list | grep -c .)" "0"
ar --session s-1 ruling add "Fable: keep the sqlite store — cost if wrong: one migration"
ar --session s-1 ruling add "Opus: three retries"
check "ruling list" "$(ar --session s-1 ruling list | paste -sd'|' -)" "Fable: keep the sqlite store — cost if wrong: one migration|Opus: three retries"

# --- clears ---
mkdir -p "$REPO/.forge/handoff"
cat > "$REPO/.forge/handoff/latest.md" <<'EOF'
# Handoff

## Next session

**Status:** plan saved
**Next:** execute the plan

Launch in `/work/repo`:

```
claude --model sonnet --effort high
```

Paste as the first prompt:

```
Execute docs/plan.md with dr-forge:subagent-driven-development.
```
EOF
ar --session s-1 clear --phase; status=$?
check "clear --phase: exit 0" "$status" "0"
check "clear --phase: pending clear, awaiting a rebind" "$(field pending) $(field rebind)" "clear true"
check "clear --phase: the first prompt" "$(field resumePrompt)" "Execute docs/plan.md with dr-forge:subagent-driven-development."
check "clear --phase: the launch" "$(jq -r '.launch | "\(.model) \(.effort)"' "$STATE")" "sonnet high"
check "clear --phase: not a self-resume" "$(field resumes)" "0"

# --- rebind ---
ar --session s-1 rebind --to s-9; status=$?
check "rebind: exit 0" "$status" "0"
check "rebind: the cleared session is bound" "$(ar --session s-9 pending)" "resume"
ar --session s-1 status >/dev/null 2>&1; status=$?
check "rebind: the old session is not" "$status" "3"
check "rebind: nothing awaits a rebind" "$(field rebind)" "false"
ar --session s-9 resumed
check "resumed: nothing pending" "$(field pending)" "null"
ar --session s-7 rebind --to s-7 >/dev/null 2>&1; status=$?
check "rebind without a clear: exit 4" "$status:$(field session)" "4:s-9"

# --- self-resumes ---
ar --session s-9 clear; ar --session s-9 rebind --to s-10
check "a clear without --phase counts" "$(field resumes)" "1"
ar --session s-10 task-complete
check "task-complete resets the count" "$(field resumes)" "0"
ar --session s-10 clear; ar --session s-10 rebind --to s-11
ar --session s-11 clear; ar --session s-11 rebind --to s-12
ar --session s-12 clear >/dev/null 2>&1; status=$?
check "the third self-resume in a row stops the run" "$status:$(field active)" "5:false"
check "the stop says why" "$(field stopped)" "three self-resumes without a completed task"

# --- compactions and failures ---
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
ar --session s-1 compacted
check "compacted: counted, after-compact pending" "$(field compactions) $(field pending)" "1 after-compact"
ar --session s-1 failure --reason "vetoed"; status=$?
check "a first failure: exit 0, counted" "$status:$(field failures):$(field active)" "0:1:true"
ar --session s-1 compacted
check "a compaction resets the failures" "$(field failures)" "0"
ar --session s-1 failure; ar --session s-1 failure --reason "refused twice"; status=$?
check "a second failure in a row stops the run" "$status:$(field active):$(field stopped)" "5:false:refused twice"

# --- stop ---
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
ar --session s-1 stop --reason "owner asked"
check "stop: inactive with the reason" "$(field active):$(field stopped)" "false:owner asked"
ar --session s-1 status >/dev/null 2>&1; status=$?
check "stop: no run is bound any more" "$status" "3"
ar --session s-1 start --spec "$SPEC" --register docs/r.md >/dev/null 2>&1; status=$?
check "a stopped run never blocks a start" "$status" "0"
ar --session s-1 stop
check "stop without a reason: finished" "$(field stopped)" "null"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
````

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dr-forge/tests/auto-run.test.sh`
Expected: FAIL lines (no `scripts/auto-run` yet) and a non-zero exit.

- [ ] **Step 3: Write the implementation**

Create `scripts/lib/auto-run.sh`:

```bash
# Sourced. An auto run's state (reference/auto-run.md): one JSON file in the
# primary checkout's self-ignoring sdd/ directory, bound to one session.
# Defines functions only; scripts/auto-run is the command line.
#
# AR_SESSION names the caller. A caller whose session the run is not bound to
# sees no run, so another session in the same repository never acts on it.

. "$(dirname "${BASH_SOURCE[0]}")/forge-dir.sh"

AR_STALE_MINUTES=60
AR_RESUME_CAP=3
AR_FAILURE_CAP=2

ar_jq() { "${DR_FORGE_JQ:-jq}" "$@"; }

ar_primary_root() {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  git -C "$(dirname "$common")" rev-parse --show-toplevel 2>/dev/null || return 1
}

# ar_path — the state file's path, whether or not it exists.
ar_path() {
  local primary
  primary=$(ar_primary_root) || return 1
  printf '%s/sdd/auto-run.json\n' "$(forge_dir state "$primary")"
}

# ar_state — the state file's JSON; fails when there is none.
ar_state() {
  local path
  path=$(ar_path) || return 1
  [ -f "$path" ] || return 1
  ar_jq -e 'objects' < "$path" 2>/dev/null
}

# ar_bound — true when an active run is bound to AR_SESSION.
ar_bound() {
  [ -n "${AR_SESSION:-}" ] || return 1
  ar_state | ar_jq -e --arg s "$AR_SESSION" '.active == true and .session == $s' >/dev/null 2>&1
}

# ar_update FILTER [jq options…] — apply a jq filter to the state atomically.
ar_update() {
  local path tmp filter=$1
  shift
  path=$(ar_path) || return 1
  tmp=$(mktemp "$path.XXXXXX") || return 1
  if ar_jq "$@" "$filter" < "$path" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv -f "$tmp" "$path"
  else
    rm -f "$tmp"
    return 1
  fi
}

# ar_get FIELD — one field, raw; empty for null or false.
ar_get() {
  ar_state | ar_jq -r --arg f "$1" '.[$f] // empty | if type == "array" or type == "object" then tojson else tostring end'
}

# ar_transcript SESSION — the session's transcript: its by-id record's path,
# else the projects tree's <SESSION>.jsonl. Records hold native paths, so a
# Windows path is converted as scripts/lib/context.sh does.
ar_transcript() {
  local rec tp
  rec="$HOME/.claude/dr-forge/sessions/by-id/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-').json"
  if [ -f "$rec" ]; then
    tp=$(ar_jq -r '.transcript_path // empty' < "$rec" 2>/dev/null | tr -d '\r')
    if [ -n "$tp" ] && command -v cygpath >/dev/null 2>&1; then tp=$(cygpath -u "$tp"); fi
    if [ -n "$tp" ] && [ -f "$tp" ]; then printf '%s\n' "$tp"; return 0; fi
  fi
  tp=$(ls -t "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$1".jsonl 2>/dev/null | head -n 1)
  [ -n "$tp" ] || return 1
  printf '%s\n' "$tp"
}

# ar_is_stale — true when the run's session has not written its transcript
# within AR_STALE_MINUTES, or has none: whoever owned the run is gone.
ar_is_stale() {
  local sid tp
  sid=$(ar_get session)
  [ -n "$sid" ] || return 0
  tp=$(ar_transcript "$sid") || return 0
  [ -n "$(find "$tp" -mmin +"$AR_STALE_MINUTES" 2>/dev/null)" ]
}

# ar_start SPEC REGISTER FORCE — prints the register path. A register it
# creates goes in the checkout the run starts from, where its path resolves.
ar_start() {
  local spec=$1 register=$2 force=$3 path top slug base
  path=$(ar_path) || { echo "auto-run: not inside a git repository" >&2; return 2; }
  if [ "$force" != 1 ] && ar_state | ar_jq -e '.active == true' >/dev/null 2>&1 && ! ar_is_stale; then
    echo "auto-run: an auto run is already active ($(ar_state | ar_jq -r '.spec')); stop it with auto-run stop, or pass --force" >&2
    return 4
  fi
  top=$(git rev-parse --show-toplevel)
  if [ -z "$register" ]; then
    slug=$(basename "$spec" .md)
    slug=${slug%-design}
    slug=$(sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//' <<<"$slug")
    register="$(forge_dir_rel docs "$top")/registers/$(date +%Y-%m-%d)-$slug-auto.md"
    if [ ! -f "$top/$register" ]; then
      mkdir -p "$(dirname "$top/$register")" || return 1
      printf '# Auto run: %s\n\n**Source:** items the auto run for `%s` deferred\n**Covers:** %s\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n' \
        "$slug" "$spec" "$spec" > "$top/$register" || return 1
    fi
  fi
  base=$(git symbolic-ref --short -q HEAD 2>/dev/null || true)
  mkdir -p "$(dirname "$path")" || return 1
  [ -f "$(dirname "$path")/.gitignore" ] || printf '*\n' > "$(dirname "$path")/.gitignore"
  ar_jq -n --arg s "$AR_SESSION" --arg spec "$spec" --arg reg "$register" --arg base "$base" \
    --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
    active: true, session: $s, rebind: false, stopped: null, startedAt: $now,
    spec: $spec, plan: null, register: $reg, base: (if $base == "" then null else $base end),
    phase: "spec", regime: "normal", pending: null, resumePrompt: null, launch: null,
    failures: 0, compactions: 0, resumes: 0, decisions: [], rulings: []
  }' > "$path" || return 1
  printf '%s\n' "$register"
}

ar_status() {
  ar_state | ar_jq -r '"auto run: \(.phase) — regime \(.regime) — pending \(.pending // "none") — \(.compactions) compactions — \(.resumes) resumes — \(.decisions | length) pending decisions — spec \(.spec) — plan \(.plan // "none") — base \(.base // "none") — register \(.register)"'
}

ar_pending() { ar_state | ar_jq -r '.pending // "none"'; }

ar_stop() { # ar_stop [REASON]
  ar_update '.active = false | .stopped = (if $r == "" then null else $r end) | .pending = null' --arg r "${1:-}"
}

# ar_fenced FILE PREFIX — the first fenced block after the first line that
# starts with PREFIX.
ar_fenced() {
  awk -v h="$2" '
    !seen && index($0, h) == 1 { seen = 1; next }
    seen && !open && /^```/ { open = 1; next }
    open && /^```/ { exit }
    open { print }
  ' "$1"
}

# ar_clear PHASE — the cleared session's first prompt and launch, from the
# handoff scripts/next-step just wrote. PHASE 1 for a phase clear; otherwise
# the clear is a self-resume, and the AR_RESUME_CAP-th in a row stops the run
# (return 5).
ar_clear() {
  local is_phase=$1 primary latest prompt="" launch model="" effort="" resumes
  primary=$(ar_primary_root) || return 1
  latest="$(forge_dir state "$primary")/handoff/latest.md"
  [ -f "$latest" ] && prompt=$(ar_fenced "$latest" 'Paste as the first prompt:')
  [ -n "$prompt" ] || { echo "auto-run: no first prompt in $latest; run scripts/next-step first" >&2; return 1; }
  launch=$(ar_fenced "$latest" 'Launch in ' | head -n 1)
  if [[ $launch =~ claude\ --model\ ([^ ]+)\ --effort\ ([^ ]+) ]]; then
    model=${BASH_REMATCH[1]} effort=${BASH_REMATCH[2]}
  fi
  resumes=$(ar_get resumes)
  resumes=${resumes:-0}
  if [ "$is_phase" != 1 ]; then
    resumes=$((resumes + 1))
    if [ "$resumes" -ge "$AR_RESUME_CAP" ]; then
      ar_stop "three self-resumes without a completed task"
      echo "auto-run: stopped — $AR_RESUME_CAP self-resumes in a row without a completed task" >&2
      return 5
    fi
  fi
  ar_update '.pending = "clear" | .rebind = true | .resumes = ($r | tonumber) | .resumePrompt = $p
    | .launch = (if $m == "" then null else {model: $m, effort: $e} end)' \
    --arg r "$resumes" --arg p "$prompt" --arg m "$model" --arg e "$effort"
}

ar_rebind() { # ar_rebind ID
  ar_state | ar_jq -e '.active == true and .rebind == true' >/dev/null 2>&1 \
    || { echo "auto-run: no clear is waiting for its session" >&2; return 4; }
  ar_update '.session = $id | .rebind = false | .pending = "resume" | .failures = 0 | .regime = "normal"' --arg id "$1"
}

ar_resumed() { ar_update 'if .pending == "resume" then .pending = null else . end'; }

ar_compacted() { ar_update '.compactions += 1 | .failures = 0 | .pending = "after-compact"'; }

ar_failure() { # ar_failure [REASON] — return 5 when this failure stops the run
  local n
  n=$(ar_get failures)
  n=$(( ${n:-0} + 1 ))
  if [ "$n" -ge "$AR_FAILURE_CAP" ]; then
    ar_stop "${1:-the cockpit could not compact or clear}"
    return 5
  fi
  ar_update '.failures = ($n | tonumber)' --arg n "$n"
}

ar_decision_add() { # ar_decision_add ID QUESTION OPTIONS REASON TASK
  ar_update '.decisions = (((.decisions // []) | map(select(.id != $id))) + [{id: $id, question: $q, options: $o, opusReason: $r, task: (if $t == "" then null else $t end)}])' \
    --arg id "$1" --arg q "$2" --arg o "$3" --arg r "$4" --arg t "$5"
}

ar_decision_list() { ar_state | ar_jq -c '(.decisions // [])[]'; }

ar_decision_clear() { # ar_decision_clear [ID]
  if [ -n "${1:-}" ]; then
    ar_update '.decisions = ((.decisions // []) | map(select(.id != $id)))' --arg id "$1"
  else
    ar_update '.decisions = []'
  fi
}

ar_ruling_add() { ar_update '.rulings = ((.rulings // []) + [$t])' --arg t "$1"; }

ar_ruling_list() { ar_state | ar_jq -r '(.rulings // [])[]'; }
```

Create `scripts/auto-run` and `chmod 755` it:

```bash
#!/usr/bin/env bash
# An auto run's state (reference/auto-run.md).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/auto-run.sh"

usage() {
  cat >&2 <<'EOF'
usage: auto-run [--session ID] start --spec P [--register R] [--force]
       auto-run [--session ID] status | pending | task-complete | compacted | resumed
       auto-run [--session ID] attach --plan P
       auto-run [--session ID] phase spec|plan|execute|final|finish
       auto-run [--session ID] clear [--phase]
       auto-run [--session ID] rebind --to ID
       auto-run [--session ID] failure [--reason TEXT]
       auto-run [--session ID] decision add --id ID --question Q [--options O] [--opus-reason R] [--task N]
       auto-run [--session ID] decision list | decision clear [--id ID]
       auto-run [--session ID] ruling add TEXT | ruling list
       auto-run [--session ID] stop [--reason TEXT]
Exit: 0 done; 2 usage; 3 no run bound to this session; 4 refused; 5 the run stopped.
EOF
  exit 2
}

command -v "${DR_FORGE_JQ:-jq}" >/dev/null 2>&1 || { echo "auto-run: jq is required" >&2; exit 2; }

AR_SESSION=${CLAUDE_CODE_SESSION_ID:-}
if [ "${1:-}" = --session ]; then
  [ $# -ge 2 ] && [ -n "$2" ] || usage
  AR_SESSION=$2
  shift 2
fi
export AR_SESSION
[ $# -ge 1 ] || usage
cmd=$1
shift

bound() { ar_bound || { echo "auto-run: no auto run is bound to this session" >&2; exit 3; }; }
reason_arg() { # sets reason from [--reason TEXT]
  reason=""
  if [ "${1:-}" = --reason ]; then
    [ $# -eq 2 ] || usage
    reason=$2
  else
    [ $# -eq 0 ] || usage
  fi
}

case $cmd in
  start)
    spec="" register="" force=0
    while [ $# -gt 0 ]; do
      case $1 in
        --spec) [ $# -ge 2 ] || usage; spec=$2; shift 2 ;;
        --register) [ $# -ge 2 ] || usage; register=$2; shift 2 ;;
        --force) force=1; shift ;;
        *) usage ;;
      esac
    done
    [ -n "$spec" ] || usage
    [ -n "$AR_SESSION" ] || { echo "auto-run: no session id; CLAUDE_CODE_SESSION_ID is unset and no --session was given" >&2; exit 2; }
    ar_start "$spec" "$register" "$force"
    ;;
  status) [ $# -eq 0 ] || usage; bound; ar_status ;;
  pending) [ $# -eq 0 ] || usage; bound; ar_pending ;;
  attach)
    [ $# -eq 2 ] && [ "$1" = --plan ] && [ -n "$2" ] || usage
    bound; ar_update '.plan = $p' --arg p "$2"
    ;;
  phase)
    [ $# -eq 1 ] || usage
    case $1 in spec|plan|execute|final|finish) ;; *) usage ;; esac
    bound; ar_update '.phase = $p' --arg p "$1"
    ;;
  task-complete) [ $# -eq 0 ] || usage; bound; ar_update '.resumes = 0' ;;
  clear)
    case "$#:${1:-}" in
      0:) bound; ar_clear 0 ;;
      1:--phase) bound; ar_clear 1 ;;
      *) usage ;;
    esac
    ;;
  rebind)
    [ $# -eq 2 ] && [ "$1" = --to ] && [ -n "$2" ] || usage
    ar_rebind "$2"
    ;;
  resumed) [ $# -eq 0 ] || usage; bound; ar_resumed ;;
  compacted) [ $# -eq 0 ] || usage; bound; ar_compacted ;;
  failure) reason_arg "$@"; bound; ar_failure "$reason" ;;
  decision)
    [ $# -ge 1 ] || usage
    sub=$1
    shift
    case $sub in
      add)
        id="" question="" options="" opus="" task=""
        while [ $# -gt 0 ]; do
          [ $# -ge 2 ] || usage
          case $1 in
            --id) id=$2 ;;
            --question) question=$2 ;;
            --options) options=$2 ;;
            --opus-reason) opus=$2 ;;
            --task) task=$2 ;;
            *) usage ;;
          esac
          shift 2
        done
        [ -n "$id" ] && [ -n "$question" ] || usage
        bound; ar_decision_add "$id" "$question" "$options" "$opus" "$task"
        ;;
      list) [ $# -eq 0 ] || usage; bound; ar_decision_list ;;
      clear)
        case "$#:${1:-}" in
          0:) bound; ar_decision_clear ;;
          2:--id) bound; ar_decision_clear "$2" ;;
          *) usage ;;
        esac
        ;;
      *) usage ;;
    esac
    ;;
  ruling)
    case "$#:${1:-}" in
      2:add) [ -n "$2" ] || usage; bound; ar_ruling_add "$2" ;;
      1:list) bound; ar_ruling_list ;;
      *) usage ;;
    esac
    ;;
  stop) reason_arg "$@"; bound; ar_stop "$reason" ;;
  *) usage ;;
esac
```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dr-forge/tests/auto-run.test.sh`
Expected: every line `ok`, last line `N passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/auto-run.sh plugins/dr-forge/scripts/auto-run plugins/dr-forge/tests/auto-run.test.sh
git commit -m "feat(dr-forge): add the auto-run state script"
```

---

### Task 2: autoRun setting, brainstorming offer and the reference

**Files:**
- Modify: `config/schema.mjs` (after the `worktree` entry)
- Modify: `skills/brainstorming/SKILL.md` (Settings list, Architectural checklist, After the Design)
- Create: `reference/auto-run.md`
- Test: `tests/settings-skills.test.sh` (run only; Task 8 edits it)

**Interfaces:**
- Consumes: C2 command names, C6, C10 (prose only).
- Produces: C11.

**Items:** 1, 2, 4, 11

**Depends on:** none

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Add the setting (the failing state)**

In `config/schema.mjs`, insert after the closing `},` of the `worktree` entry:

```js
  autoRun: {
    type: 'enum', values: ['ask', 'off'], default: 'ask', enforcedBy: 'skill', group: 'Workflow', target: 'forge',
    label: 'Auto run', title: 'Offer an unattended run',
    description: 'ask offers, once the design is approved, to run the spec, plan, execution, review and finish unattended (Claude Code only). off never offers it.',
  },
```

- [ ] **Step 2: Run the settings test to verify it fails**

Run: `timeout 600 bash plugins/dr-forge/tests/settings-skills.test.sh`
Expected: `FAIL - a skill names autoRun`, non-zero exit.

- [ ] **Step 3: Write the skill text and the reference**

In `skills/brainstorming/SKILL.md`:

(a) Replace

```
- `specReview=false`: after the spec self-review block, skip the User Review
  Gate and go on to Implementation.
```

with

```
- `specReview=false`: after the spec self-review block, skip the User Review
  Gate and go on to Implementation.
- `autoRun=off`: never offer an auto run (see After the Design). `ask`, the
  default, offers it once on the architectural path.
```

(b) In the Architectural checklist, replace

```
6. **Present design** — in sections scaled to their complexity, get user approval after each section
7. **Write design doc** — save to `<docs>/specs/YYYY-MM-DD-<topic>-design.md` and commit
8. **Spec self-review** — one round for placeholders, contradictions, ambiguity, scope; post its block before the user review (see below)
9. **User reviews written spec** — ask user to review the spec file before proceeding
10. **Transition to implementation** — invoke writing-plans skill to create implementation plan
```

with

```
6. **Present design** — in sections scaled to their complexity, get user approval after each section
7. **Offer an auto run** — unless `autoRun=off` or on a Codex host: one question once the last section is approved (see After the Design)
8. **Write design doc** — save to `<docs>/specs/YYYY-MM-DD-<topic>-design.md` and commit
9. **Spec self-review** — one round for placeholders, contradictions, ambiguity, scope; post its block before the user review (see below)
10. **User reviews written spec** — ask user to review the spec file before proceeding (an auto run has Fable review it instead)
11. **Transition to implementation** — invoke writing-plans skill to create implementation plan
```

(c) Replace

````
## After the Design (architectural path)

**Documentation:**
````

with

````
## After the Design (architectural path)

**Offering an auto run:**

Unless `autoRun=off` (see Settings) or this is a Codex host, ask this once, as
its own message, right after your human partner approves the last design
section and before you write the spec. `<finish>` follows the `finishAction`
setting (`scripts/forge-config get finishAction`): `merge` reads "merge to
<the current branch>", `pr` reads "open a pull request", and `keep`, `ask` and
`wait` read "keep the branch".

```
Run the rest unattended? Spec → Fable spec review → plan → execution →
final review → finish (<finish>).
I won't ask anything else: undecided items go to Opus, then to Fable in
batches, and what neither settles goes on the deferred list.

1. Yes, run unattended
2. No, keep the normal stops

Which option?
```

On yes, run `scripts/auto-run start --spec <the spec's path>` (add
`--register <path>` when an item register is open) from this checkout, before
writing the spec, and follow [auto-run.md](../../reference/auto-run.md) from
here to the finished branch. On exit 2 or 4, say why in one line and continue
without an auto run. On no, continue as below.

**Documentation:**
````

(d) Replace

```
**User Review Gate:**
With `specReview=false` (see Settings), skip this gate and go to Implementation.
```

with

```
**User Review Gate:**
In an auto run (`scripts/auto-run status` exits 0), skip this gate: run the
Fable spec review in [auto-run.md](../../reference/auto-run.md) §The spec, then
go to Implementation.
With `specReview=false` (see Settings), skip this gate and go to Implementation.
```

(e) Replace

```
  with dr-forge:writing-plans." — the plan is written in a fresh session.
```

with

```
  with dr-forge:writing-plans." — the plan is written in a fresh session. In
  an auto run this step owns the clear: run `scripts/auto-run clear --phase`
  and end as [auto-run.md](../../reference/auto-run.md) §Clears says.
```

Create `reference/auto-run.md`:

````markdown
# Auto run

An opt-in mode: once the design is approved, dr-forge writes the spec and the
plan, executes, reviews and finishes without asking its human anything. The
design is `docs/superpowers/specs/2026-10-13-dr-forge-auto-run-design.md` in
the dr-forge repository; this file is the contract the skills cite. Every
`scripts/…` command runs as `bash <plugin-root>/scripts/<name>`.

Claude Code only: the cockpit mod compacts and clears the session. No run
starts on Codex.

## Starting

dr-forge:brainstorming offers it once, after the last design section is
approved and before the spec is written, unless `autoRun=off`. On yes, from
the checkout the design was made in:

    scripts/auto-run start --spec <spec path> [--register <register path>]

`--register` names the item register when one is open; without it the script
creates `<docs>/registers/<date>-<slug>-auto.md` in this checkout and prints
its path. The branch checked out here becomes the run's base, the branch the
finish merges into. Exit 4 means another live run is active, exit 2 that this
session cannot be bound: say so in one line and continue without an auto run.

## While a run is bound to this session

`scripts/auto-run status` exits 0 and names the phase, the regime, the pending
action, the plan, the base and the register. Then:

- **Ask nothing.** No clarifying question, approval or menu. What you would
  have asked goes to the ladder under Rulings.
- **Skipped questions:** the spec review stop, the worktree consent (create
  the worktree), the finish-preference question, and the execution stops
  under Rulings.
- **Phases:** `scripts/auto-run phase plan` when writing-plans starts,
  `scripts/auto-run attach --plan <plan>` once the plan is reviewed,
  `scripts/auto-run phase execute` when execution starts,
  `scripts/auto-run phase final` before the final review and
  `scripts/auto-run phase finish` when finishing starts.
- **Each completed task:** `scripts/auto-run task-complete` right after its
  `Task N: complete` ledger line.
- **A message from your human partner** does not stop the run: answer it and
  continue, unless it asks you to stop (see Stopping).

## The spec

After your own self-review round, dispatch `dr-forge:judge-fable` on the spec
against the approved design: the design sections as approved, verbatim, and
the spec's path. Apply what it rules, and record each ruling with
`scripts/auto-run ruling add "Fable, spec: <item> — <ruling>"`. Add each item
it leaves undecided or without a suggestion to the run's register:

    scripts/register add <register> "<item>" --state deferred --note "Fable: <its words>"

At most two Fable rounds run (review, revise, re-review); anything still open
after the second is deferred the same way. Then `scripts/context-size --plan`
as brainstorming says: under its limit write the plan here; over it, follow
Clears with `--phase`.

## Rulings

The ladder for anything you would have asked:

1. **Opus.** During execution, the ruling seat (`dr-forge:judge-opus`) as the
   execution skills dispatch it; CONFIRMED-GAP, PARK and AMEND are carried out
   as always. Before execution (a spec or planning choice), dispatch
   `dr-forge:judge-opus` yourself with the question, its options with your
   recommendation first, the spec's path and the plan's path when one exists,
   asking for `ruling: <choice> — <reason>` or `no ruling`.
2. **The pending list.** An Opus `BLOCKED` or `no ruling`, or an implementer
   that exhausted the ladder, is added:

       scripts/auto-run decision add --id <id> --question "<q>" --options "<recommended | other>" --opus-reason "<why Opus did not rule>" [--task <N>]

3. **Fable, in one batch.** Dispatch `dr-forge:judge-fable` once with every
   line of `scripts/auto-run decision list`, asking for each item
   `ruling: <choice> — <reason>` or `no ruling`. Carry out each ruling as a
   ruling-seat verdict. Record it as a `Ruling:` ledger line when the plan's
   ledger exists (`Task <N>: Ruling: …` for a task's item), and with
   `scripts/auto-run ruling add` before it does. Then
   `scripts/auto-run decision clear`.

**When Fable gives no ruling:**

- **A task's item:** the task is deferred. Write its terminal ledger line,
  and the same line for every task that depends on it:

      Task <N>: complete (deferred by the auto run) — done: nothing; verified: not run; remaining: <the item>[; partial commits <a7>..<b7>, kept for the final review]; discovered: none; assumptions: none; Ruling: <why> — <cost if wrong>

  Add one deferred register row per such task. Recovery, `scripts/next-step`
  and the final review count the line as complete, so the run moves on. In a
  wave, a deferred task's branch is not merged.
- **A spec or planning choice:** take the option listed first, record
  `scripts/auto-run ruling add "unconfirmed: <choice> — Fable gave no ruling"`,
  and add a deferred register row naming the choice.

A batch runs at once for a blocked task, and otherwise whenever the list is
not empty at a boundary: after the spec, after the plan is reviewed, after each
wave (each task in sequential mode) and before the final review. Tasks that do
not depend on a deferred task keep running.

**Never performed in an auto run,** whatever a ruling says: an irreversible or
destructive operation, a security-sensitive action, or a side effect outside
the worktree (a push, a publish, a merge before finishing). Defer the task, as
above, with a register row naming the operation. The finish action is the one
exception.

## The budget line

While a run is bound to this session, every budget line but
`scripts/context-size --plan` prints the run's own verdict:

    budget (auto): 312k of 465k (67%) — ok — source: record
    budget (auto): 471k of 465k (101%) — compact — source: record
    budget (auto, high): 724k of 720k (101%) — compact — source: record
    budget (auto, wave of 3): 190k of 185k (103%) — compact — source: record

- `ok`, or `unknown`: carry on; on `unknown`, record that with
  `scripts/auto-run ruling add`.
- `compact` (`scripts/context-size` exit 6): finish the task in flight through
  its `Task N: complete` line (a wave through its merge), run
  `scripts/auto-run task-complete`, then end the turn as Ending a turn says.
  In the wave loop, lower the width while `--wave` says `compact`, as on
  `handoff`; at width 1, compact.
- `handoff` (exit 5): the last compaction left too much behind. Finish the
  task in flight, then follow Clears.

The rules: compact at the task budget in the normal regime, or at 90% of the
compaction window in the high one, less 140k for each task of a wave beyond
the first. After a compaction of size P: P at 85% of the window or more hands
off; P at 85% of the task budget or more switches to the high regime;
anything smaller returns to the normal one. The tail rule, the final-phase
limit and relaxed mode do not apply. Finishing is never measured.

## Ending a turn

A run's turn ends only with one of two lines as the last line of the message:

- `Auto run: compacting` when `scripts/auto-run pending` says `compact`;
- `Auto run: clearing` after `scripts/auto-run clear` exits 0.

Nothing you started may still run in the background. The Stop hook holds any
other ending once. The cockpit then compacts, or clears the session and binds
the new one, and submits the next prompt itself.

## After a compaction

The cockpit's prompt asks you to run `scripts/auto-run after-compact` first.
It prints `continue` (exit 0) or `handoff` (exit 5).

- `continue`: carry on with the phase `scripts/auto-run status` names. In
  `execute` and `final`, follow the After compaction steps of the execution
  skill the plan's Execution line names, for the plan `status` names: its
  workspace, ledger and `git log` are the authority. `latest.md` predates the
  execution worktree, so do not resume from it. When the line says the size
  is unknown, record that with `scripts/auto-run ruling add`.
- `handoff`: follow Clears.

## Clears

The step that hands off owns the clear; dr-forge:handoff itself never runs it.
Run dr-forge:handoff first (`scripts/auto-run clear` reads the first prompt
and launch command `scripts/next-step` wrote to `latest.md`), then:

- **Plan saved**, and **spec to plan** over the `--plan` limit:
  `scripts/auto-run clear --phase`.
- **A compaction that left too much:** `scripts/auto-run clear`.

On exit 0, end the turn with `Auto run: clearing` as the last line, below the
next-step block. The cleared session runs on the launch command's model and
effort. On exit 5 the run has stopped (the third self-resume in a row without
a completed task): end with the next-step block alone, as Stopping says.

## Stopping

`scripts/auto-run stop --reason "<why>"` ends the run; without a reason it
ends as finished. Run it, then end as the attended flow would, when:

- your human partner asks you to stop;
- dr-forge:resume-execution would stop to ask (a worktree whose branch is
  gone);
- finishing hits one of its unattended stops (failing tests on the merged
  result, a rejected push, a refused worktree removal).

When `scripts/auto-run clear` exits 5, or the cockpit's prompt says the run
stopped, it has already stopped: end with the next-step block. The cockpit
sends one Discord `blocked` notice when a run stops with a reason.

## Finishing

Finishing carries out the `finishAction` setting at once, into the base
`scripts/auto-run status` names: `merge` and `pr` as named; `keep`, `ask` and
`wait` keep the branch, and so does `merge` when the base is `none`. No menu,
no wake. Its final message lists every `Ruling:` ledger line, every line of
`scripts/auto-run ruling list` and every deferred row the run added, and it
runs `scripts/auto-run stop` before the next-step block.
````

- [ ] **Step 4: Run the checks to verify they pass**

Run: `timeout 600 bash plugins/dr-forge/tests/settings-skills.test.sh` → Expected: `0 failed`, exit 0.
Run: `timeout 120 node scripts/validate-repository.mjs` → Expected: exit 0, no error lines.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/config/schema.mjs plugins/dr-forge/skills/brainstorming/SKILL.md plugins/dr-forge/reference/auto-run.md
git commit -m "feat(dr-forge): offer an auto run after the design"
```

---

### Task 3: Compaction rules

**Files:**
- Modify: `scripts/lib/auto-run.sh` (append)
- Modify: `scripts/auto-run` (source line, usage, two commands)
- Test: `tests/auto-run.test.sh` (insert before the summary)

**Interfaces:**
- Consumes: C1-C3 from Task 1; `scripts/lib/context.sh` (`ctx_have_jq`, `ctx_find_transcript`, `ctx_measure`, `ctx_model`, `ctx_pinned_budget`, `ctx_budget`, `ctx_window`).
- Produces: C2 `verdict` and `after-compact`, C3 rule functions, C4.

**Items:** 5, 6, 7, 9

**Depends on:** Task 1

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

In `tests/auto-run.test.sh`, insert immediately before the line `printf '\n%d passed, %d failed\n' "$pass" "$fail"`:

```bash
# --- the rules (reference/auto-run.md §The budget line) ---
ar --session s-1 start --spec "$SPEC" --register docs/r.md --force >/dev/null
verdict() { ar --session s-1 verdict --budget 465000 --window 800000 "$@"; }
out=$(verdict --tokens 464999); status=$?
check "normal: under the budget" "$status:$out" "0:ok 465000 normal"
check "normal: ok leaves nothing pending" "$(field pending)" "null"
out=$(verdict --tokens 465000); status=$?
check "normal: at the budget, compact" "$status:$out" "6:compact 465000 normal"
check "compact is pending" "$(field pending)" "compact"
out=$(verdict --tokens 185000 --wave 3); status=$?
check "a wave of three reserves two tasks" "$status:$out" "6:compact 185000 normal"
out=$(verdict --tokens 184999 --wave 3)
check "a narrower probe that fits cancels the compaction" "$out:$(field pending)" "ok 185000 normal:null"
ar --session s-1 compacted
out=$(verdict --tokens 395249)
check "after a compaction under 85% of the budget: normal" "$out:$(field pending)" "ok 465000 normal:null"
ar --session s-1 compacted
out=$(verdict --tokens 395250)
check "after a compaction at 85% of the budget: high" "$out" "ok 720000 high"
out=$(verdict --tokens 719999)
check "high: under 90% of the window" "$out" "ok 720000 high"
out=$(verdict --tokens 720000); status=$?
check "high: at 90% of the window, compact" "$status:$out" "6:compact 720000 high"
ar --session s-1 compacted
out=$(verdict --tokens 679999)
check "after a compaction under 85% of the window: high stays" "$out" "ok 720000 high"
ar --session s-1 compacted
out=$(verdict --tokens 100000)
check "after a small compaction: back to normal" "$out" "ok 465000 normal"
ar --session s-1 compacted
out=$(verdict --tokens 680000); status=$?
check "after a compaction at 85% of the window: handoff" "$status:${out%% *}" "5:handoff"
ar --session s-1 clear --phase
out=$(verdict --tokens 10000); status=$?
check "a pending clear answers handoff" "$status:${out%% *}" "5:handoff"
ar --session s-1 rebind --to s-1
ar --session s-1 compacted
out=$(ar --session s-1 verdict --tokens 260000 --budget 300000 --window 400000)
check "another budget and window" "$out" "ok 360000 high"
ar --session s-x verdict --tokens 1 --budget 1 --window 1 >/dev/null 2>&1; status=$?
check "verdict for another session: exit 3" "$status" "3"
ar --session s-1 verdict --tokens 1 --budget 1 >/dev/null 2>&1; status=$?
check "verdict without a window: exit 2" "$status" "2"

# --- after-compact measures the session it names ---
mkdir -p "$HOME/.claude"
printf '{"autoCompactWindow": 800000}\n' > "$HOME/.claude/settings.json"
live s-1
T="$HOME/.claude/projects/p/s-1.jsonl"
asst() { printf '{"type":"assistant","isSidechain":false,"message":{"model":"claude-opus-5-5","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":%s}}}\n' "$1"; }
after() { (cd "$REPO" && CLAUDE_CODE_SESSION_ID=s-other DR_FORGE_BUDGET=465000 bash "$AR" --session s-1 after-compact); }
ar --session s-1 compacted
asst 30000 > "$T"
out=$(after); status=$?
check "after-compact: a small context continues" "$status:$out" "0:continue — 30k after compaction; regime normal"
check "after-compact: nothing pending" "$(field pending)" "null"
ar --session s-1 compacted
asst 700000 > "$T"
out=$(after); status=$?
check "after-compact: 85% of the window hands off" "$status:${out%% *}" "5:handoff"
ar --session s-1 compacted
printf '{}\n' > "$T"
out=$(after); status=$?
check "after-compact: an unknown size continues and says to record it" "$status:${out%%;*}" "0:continue — the size after compaction is unknown"
check "after-compact: unknown leaves nothing pending" "$(field pending)" "null"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dr-forge/tests/auto-run.test.sh`
Expected: the new checks FAIL (`verdict` and `after-compact` print usage), non-zero exit.

- [ ] **Step 3: Write the implementation**

Append to `scripts/lib/auto-run.sh`:

```bash
AR_TASK_MARGIN=140000
AR_HIGH_PCT=90
AR_AFTER_HANDOFF_PCT=85
AR_AFTER_HIGH_PCT=85

# ar_limit BUDGET WINDOW N REGIME — where a checkpoint covering N tasks
# compacts: the task budget, or AR_HIGH_PCT of the window in the high regime,
# less one task's worst growth for each task beside the first.
ar_limit() {
  local limit
  if [ "$4" = high ]; then limit=$(( $2 * AR_HIGH_PCT / 100 )); else limit=$1; fi
  limit=$(( limit - ($3 - 1) * AR_TASK_MARGIN ))
  [ "$limit" -gt 0 ] || limit=1
  echo "$limit"
}

# ar_after P BUDGET WINDOW — the after-compaction rule: handoff, high or normal.
ar_after() {
  if [ $(( $1 * 100 )) -ge $(( $3 * AR_AFTER_HANDOFF_PCT )) ]; then echo handoff
  elif [ $(( $1 * 100 )) -ge $(( $2 * AR_AFTER_HIGH_PCT )) ]; then echo high
  else echo normal
  fi
}

# ar_settle P BUDGET WINDOW — apply the after-compaction rule to the run: set
# the regime, clear pending, print continue or handoff.
ar_settle() {
  local result regime
  result=$(ar_after "$1" "$2" "$3")
  if [ "$result" = handoff ]; then regime=$(ar_get regime); else regime=$result; fi
  ar_update '.regime = $r | .pending = null' --arg r "${regime:-normal}" || return 1
  if [ "$result" = handoff ]; then echo handoff; else echo continue; fi
}

# ar_verdict TOKENS BUDGET WINDOW [N] — prints "<ok|compact|handoff> <limit>
# <regime>". A compaction not yet measured is settled first with TOKENS as its
# size; a pending clear is a handoff in progress. An ok clears a compaction a
# wider wave probe requested.
ar_verdict() {
  local tokens=$1 budget=$2 window=$3 n=${4:-1} pending regime limit
  pending=$(ar_get pending)
  if [ "$pending" = after-compact ] && [ "$(ar_settle "$tokens" "$budget" "$window")" = handoff ]; then
    pending=handoff
  fi
  regime=$(ar_get regime)
  regime=${regime:-normal}
  limit=$(ar_limit "$budget" "$window" "$n" "$regime")
  if [ "$pending" = handoff ] || [ "$pending" = clear ]; then
    echo "handoff $limit $regime"
  elif [ "$tokens" -ge "$limit" ]; then
    ar_update '.pending = "compact"' || return 1
    echo "compact $limit $regime"
  else
    if [ "$pending" = compact ]; then ar_update '.pending = null' || return 1; fi
    echo "ok $limit $regime"
  fi
}
```

In `scripts/auto-run`:

(a) Replace the line `. "$HERE/lib/auto-run.sh"` with:

```bash
. "$HERE/lib/context.sh"
. "$HERE/lib/auto-run.sh"
```

(b) In `usage`, replace the line `       auto-run [--session ID] stop [--reason TEXT]` with:

```
       auto-run [--session ID] stop [--reason TEXT]
       auto-run [--session ID] verdict --tokens T --budget B --window W [--wave N]
       auto-run [--session ID] after-compact
```

and replace its `Exit:` line with:

```
Exit: 0 done; 2 usage; 3 no run bound to this session; 4 refused; 5 the run stopped, or handoff; 6 compact.
```

(c) Insert before the line `  stop) reason_arg "$@"; bound; ar_stop "$reason" ;;`:

```bash
  verdict)
    tokens="" budget="" window="" n=1
    while [ $# -gt 0 ]; do
      [ $# -ge 2 ] || usage
      case $1 in
        --tokens) tokens=$2 ;;
        --budget) budget=$2 ;;
        --window) window=$2 ;;
        --wave) n=$2 ;;
        *) usage ;;
      esac
      shift 2
    done
    for v in "$tokens" "$budget" "$window" "$n"; do [[ $v =~ ^[0-9]+$ ]] || usage; done
    [ "$n" -ge 1 ] || usage
    bound
    out=$(ar_verdict "$tokens" "$budget" "$window" "$n") || exit 1
    echo "$out"
    case ${out%% *} in compact) exit 6 ;; handoff) exit 5 ;; esac
    ;;
  after-compact)
    [ $# -eq 0 ] || usage
    bound
    # Measure the session the run is bound to, whatever the environment says.
    export CLAUDE_CODE_SESSION_ID=$AR_SESSION
    model="" tokens=""
    if ctx_have_jq && ctx_find_transcript; then
      model=$(ctx_model "$CTX_TRANSCRIPT")
      tokens=$(ctx_measure "$CTX_TRANSCRIPT") || tokens=""
    fi
    budget=$(ctx_pinned_budget)
    [ -n "$budget" ] || budget=$(ctx_budget "$model")
    window=$(ctx_window "$model")
    if [ -z "$tokens" ]; then
      ar_update '.pending = null'
      echo "continue — the size after compaction is unknown; record that with auto-run ruling add, and Claude Code's own compaction stays the backstop"
      exit 0
    fi
    result=$(ar_settle "$tokens" "$budget" "$window") || exit 1
    echo "$result — $(( (tokens + 500) / 1000 ))k after compaction; regime $(ar_get regime)"
    [ "$result" = continue ] || exit 5
    ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dr-forge/tests/auto-run.test.sh`
Expected: `N passed, 0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/auto-run.sh plugins/dr-forge/scripts/auto-run plugins/dr-forge/tests/auto-run.test.sh
git commit -m "feat(dr-forge): add the auto-run compaction rules"
```

---

### Task 4: Stop hook sentinel gate

**Files:**
- Modify: `scripts/turn-end.sh` (two replacements and one inserted block, located by their text)
- Test: `tests/turn-end.test.sh` (insert before the summary)

**Interfaces:**
- Consumes: C2 `pending`, `start`, `stop`; C6.
- Produces: none.

**Items:** 8

**Depends on:** Task 1

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing test**

In `tests/turn-end.test.sh`, insert immediately before the line `printf '\n%d passed, %d failed\n' "$pass" "$fail"`:

```bash
# --- an auto run bound to the session ends its turns only on the sentinel ---
AR="$HERE/../scripts/auto-run"
unset CLAUDE_CODE_SESSION_ID
git -C "$REPO" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m init
(cd "$REPO" && bash "$AR" --session s-1 start --spec docs/s.md --register docs/r.md >/dev/null)
STATE="$REPO/.superpowers/sdd/auto-run.json"
pend() { jq --arg p "$1" '.pending = $p' "$STATE" > "$STATE.tmp" && mv "$STATE.tmp" "$STATE"; }
stop_in() { # stop_in <cwd> <session> <last message>
  jq -n --arg cwd "$1" --arg sid "$2" --arg msg "$3" \
    '{hook_event_name:"Stop",session_id:$sid,cwd:$cwd,transcript_path:"",stop_hook_active:false,last_assistant_message:$msg}' | bash "$END"
}
sleep 1; prompt s-1
out=$(stop s-1 'Task 2 is done. Everything looks good.')
check "auto run: a summary is held" "$(decision "$out")" "block"
check "auto run: the reason names the sentinel" "$(jq -r .reason <<<"$out" | grep -c 'Auto run: compacting')" "1"
check "auto run: the retry passes" "$(stop s-1 'Task 2 is done.' true)" ""
pend compact
check "auto run: the compacting line passes" "$(stop s-1 $'Task 2 is done.\n\nAuto run: compacting\n')" ""
check "auto run: the clearing line does not answer compact" "$(decision "$(stop s-1 $'Done.\n\nAuto run: clearing')")" "block"
check "auto run: the sentinel must be the last line" "$(decision "$(stop s-1 $'Auto run: compacting\n\nMore words.')")" "block"
pend clear
check "auto run: the clearing line passes a clear" "$(stop s-1 $'Handed off.\n\nAuto run: clearing')" ""
sleep 1; prompt s-2
check "auto run: another session is not held" "$(stop s-2 'Here is the answer.')" ""
git -C "$REPO" worktree add -q -b wt "$TMP/wt"
pend compact
check "auto run: found from a worktree" "$(stop_in "$TMP/wt" s-1 $'Done.\n\nAuto run: compacting')" ""
check "auto run: held from a worktree" "$(decision "$(stop_in "$TMP/wt" s-1 'Done.')")" "block"
(cd "$REPO" && bash "$AR" --session s-1 stop)
check "a stopped run: back to the plain rules" "$(stop s-1 'Here is the answer.')" ""
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dr-forge/tests/turn-end.test.sh`
Expected: `FAIL - auto run: a summary is held` (and others), non-zero exit.

- [ ] **Step 3: Write the implementation**

In `scripts/turn-end.sh`:

(a) Replace

```bash
sdd="$(forge_dir state "$root")/sdd"
[ -d "$sdd" ] || exit 0
```

with

```bash
sdd="$(forge_dir state "$root")/sdd"
# An auto run bound to this session (reference/auto-run.md) lives in the
# primary checkout, whichever worktree the turn ran in: its pending action.
auto_pending=$(cd "${cwd:-$PWD}" 2>/dev/null && bash "${SCRIPT_DIR}/auto-run" --session "$session_id" pending 2>/dev/null) || auto_pending=""
[ -d "$sdd" ] || [ -n "$auto_pending" ] || exit 0
root_shown=$PLUGIN_ROOT
if command -v cygpath >/dev/null 2>&1; then root_shown=$(cygpath -m "$PLUGIN_ROOT" 2>/dev/null || printf '%s' "$PLUGIN_ROOT"); fi
```

(b) Delete the two lines that follow `[ -n "$plan" ] || plan="PLAN_FILE"` (they moved up):

```bash
root_shown=$PLUGIN_ROOT
if command -v cygpath >/dev/null 2>&1; then root_shown=$(cygpath -m "$PLUGIN_ROOT" 2>/dev/null || printf '%s' "$PLUGIN_ROOT"); fi
```

(c) Insert immediately before the comment line `# Every ledger written this turn must have its ending, since two plans can be`:

```bash
# A turn of an auto run ends only on the sentinel line that answers its pending
# action; the cockpit compacts or clears on that line. Any other ending is held
# once.
if [ -n "$auto_pending" ]; then
  final_line=$(printf '%s\n' "$last" | sed -e 's/[[:space:]]*$//' -e '/^$/d' | tail -n 1)
  case "$auto_pending:$final_line" in
    'compact:Auto run: compacting' | 'clear:Auto run: clearing') exit 0 ;;
  esac
  reason="An auto run is bound to this session (pending: ${auto_pending}; see reference/auto-run.md), so its turns end only on a sentinel line. Do not stop: continue the run. When a budget line said compact, finish the task in flight, then end your message with the line \`Auto run: compacting\`. After \`auto-run clear\` exits 0, end with \`Auto run: clearing\`. If the run must stop (your human partner asked, or a stop the reference names), run \`bash ${root_shown}/scripts/auto-run stop --reason \"<why>\"\` first, then end as the attended flow would."
  jq -n --arg reason "$reason" '{decision: "block", reason: $reason}'
  exit 0
fi

```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dr-forge/tests/turn-end.test.sh`
Expected: `N passed, 0 failed`, exit 0 (the existing checks still pass).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/turn-end.sh plugins/dr-forge/tests/turn-end.test.sh
git commit -m "feat(dr-forge): end auto-run turns on the sentinel"
```

---

### Task 5: Cockpit actuator

**Files:**
- Modify: `types/index.d.ts` (new exported type; `PluginState`)
- Modify: `hooks/cockpit/lib.ts` (line 1 import; append)
- Modify: `hooks/cockpit/register.tsx` (imports, constants, atom, `S`, `session.start`, `session.compact`, `turn.complete`, new top-level functions)
- Test: `tests/cockpit.test.ts` (lib import list, `World`, `world()`, new helpers and describe at the end)

**Interfaces:**
- Consumes: C1 fields, C2 `compacted`, `failure`, `rebind`, `resumed`, C6.
- Produces: C7 (all but `autoLimitFor`), C8, C9.

**Items:** 5, 7, 8, 9

**Depends on:** Task 1

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 2 = 5

- [ ] **Step 1: Write the failing test**

In `tests/cockpit.test.ts`:

(a) Add `autoRunFor,` and `endsOnSentinel,` to the `import { … } from '../hooks/cockpit/lib'` list.

(b) In `type World = {`, add before its closing `}`:

```ts
  /** The session id `$.session.id()` answers; `sess-1` unless said. A /clear sets `sess-2`. */
  sessionId?: string
  /** Each compaction the engine runs, as `<trigger>:<instructions>`. */
  compacts?: string[]
  /** Every compaction is vetoed, as a PreCompact hook would. */
  isCompactVetoed?: boolean
  /** Each slash command the plugin runs, as typed. */
  commands?: string[]
  /** Slash commands that refuse to run, by name. */
  refusedCommands?: string[]
  /** How many prompt submissions fail before one goes through. */
  submitFailures?: number
  /** Each scripts/auto-run call, after the script's path. */
  autoRuns?: string[]
  /** The exit code of an auto-run command, by its command word; 0 unless said. */
  autoRunExits?: Record<string, number>
  /** The auto-run state file the fake script updates, as the real one would. */
  autoFile?: { text: string }
```

(c) In `function world(on: On, w: World)`, replace

```ts
  on('prompt.submit', (_$, e) => {
    w.prompts?.push(e.text)
    return { text: e.text }
  })
```

with

```ts
  on('prompt.submit', (_$, e) => {
    if ((w.submitFailures ?? 0) > 0) {
      w.submitFailures = (w.submitFailures ?? 1) - 1
      throw new Error('busy')
    }
    w.prompts?.push(e.text)
    return { text: e.text }
  })
```

replace

```ts
  on('session.compact', (_$, e) => ({ messages: e.messages }))
```

with

```ts
  on('session.compact', (_$, e) => {
    w.compacts?.push(`${e.trigger}:${(e as { instructions?: string }).instructions ?? ''}`)
    return w.isCompactVetoed ? ({ skip: 'vetoed' } as never) : { messages: e.messages }
  })
  on('command.run', (_$, e) => {
    if (w.refusedCommands?.includes(e.command)) throw new Error(`/${e.command} refused`)
    w.commands?.push(e.args === '' ? `/${e.command}` : `/${e.command} ${e.args}`)
    if (e.command === 'clear') w.sessionId = 'sess-2'
    return { text: '' } as never
  })
```

replace

```ts
  on('session.id', () => ({ value: 'sess-1' }))
```

with

```ts
  on('session.id', () => ({ value: w.sessionId ?? 'sess-1' }))
```

and in the `on('process.run', …)` handler, insert as its first statements after `const argv = e.argv.join(' ')`:

```ts
    const script = '/scripts/auto-run '
    if (argv.includes(script)) {
      const call = argv.slice(argv.indexOf(script) + script.length)
      w.autoRuns?.push(call)
      const words = call.split(' ')
      const word = words[2] ?? ''
      const exitCode = w.autoRunExits?.[word] ?? 0
      if (w.autoFile !== undefined) {
        const state = JSON.parse(w.autoFile.text) as Record<string, unknown>
        if (exitCode === 0 && word === 'compacted') state.pending = 'after-compact'
        if (exitCode === 0 && word === 'rebind') Object.assign(state, { session: words[4], pending: 'resume' })
        if (exitCode === 0 && word === 'resumed') state.pending = null
        if (exitCode === 0 && word === 'stop') Object.assign(state, { active: false, stopped: call.split(' --reason ')[1] ?? null, pending: null })
        if (exitCode === 5 && word === 'failure') Object.assign(state, { active: false, stopped: 'the cockpit could not compact twice', pending: null })
        w.autoFile.text = JSON.stringify(state)
      }
      return { value: { exitCode, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    }
```

(d) Append at the end of the file:

```ts
// An auto run's state file in the primary checkout the world names.
const AUTO = '/home/me/code/shop/.forge/sdd/auto-run.json'
const SENTINEL = 'Task 3: complete.\n\nAuto run: compacting'
function autoFiles(fields: Record<string, unknown> = {}): NonNullable<World['files']> {
  return {
    [AUTO]: {
      text: JSON.stringify({
        active: true,
        session: 'sess-1',
        phase: 'execute',
        regime: 'normal',
        pending: 'compact',
        plan: 'docs/plan.md',
        compactions: 0,
        resumes: 0,
        stopped: null,
        resumePrompt: null,
        launch: null,
        ...fields,
      }),
    },
  }
}
/** Lets timers at the current instant fire and their work finish. */
async function settle(clock: ReturnType<typeof world>) {
  for (let i = 0; i < 10; i++) await clock.advance(1)
}
const pendingOf = (files: NonNullable<World['files']>) => (JSON.parse(files[AUTO]!.text) as { pending: unknown }).pending

describe('auto run', () => {
  test('compacts on the sentinel, books it and submits the continue prompt', async ($, on) => {
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.compacts?.[0]).toMatch(/Ruling: line/)
    expect(w.autoRuns).toContain('--session sess-1 compacted')
    expect(w.prompts).toHaveLength(1)
    expect(w.prompts?.[0]).toMatch(/scripts\/auto-run after-compact/)
    expect(w.prompts?.[0]).toMatch(/docs\/plan\.md/)
    expect(pendingOf(files)).toBe('after-compact')
  })

  test('stays still without the sentinel, on an interrupted turn, or for another session', async ($, on) => {
    const w: World = { ...SIGNED_IN, compacts: [], prompts: [] }
    const clock = world(on, w)
    const files = autoFiles()
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Task 3: complete.', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: true, turnId: 't2', reason: 'aborted' })
    files[AUTO] = autoFiles({ session: 'another' })[AUTO]!
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't3', reason: 'answer' })
    await settle(clock)
    expect(w.compacts).toEqual([])
    expect(w.prompts).toEqual([])
  })

  test('waits while a subagent runs', async ($, on) => {
    const w: World = { ...SIGNED_IN, compacts: [] }
    const clock = world(on, w)
    signedIn(on, autoFiles())
    await $.session.start(START)
    await $.agent.spawn({
      tool_use_id: 'toolu_1',
      prompt: 'Implement task 4',
      description: 'Task 4',
      subagentType: 'dr-forge:impl-sonnet-low',
      provider: { plugin: 'dr-forge', tier: 'user' },
      parentModel: 'claude-opus-5-5',
      background: true,
      fork: false,
    })
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    await clock.advance(5_000)
    await settle(clock)
    expect(w.compacts).toEqual([])
  })

  test('waits for a turn that started first, then compacts', async ($, on) => {
    const w: World = { ...SIGNED_IN, compacts: [] }
    const clock = world(on, w)
    signedIn(on, autoFiles())
    await $.session.start(START)
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await $.turn.start({ text: 'How is it going?', turnId: 't2' })
    await settle(clock)
    expect(w.compacts).toEqual([])
    await $.turn.complete({ answer: 'Going well.', durationMs: 1, isAborted: false, turnId: 't2', reason: 'answer' })
    await clock.advance(5_000)
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
  })

  test('clears, binds the cleared session, sets its model and submits its first prompt', async ($, on) => {
    const files = autoFiles({ pending: 'clear', resumePrompt: 'Execute docs/plan.md.', launch: { model: 'sonnet', effort: 'high' } })
    const w: World = { ...SIGNED_IN, commands: [], autoRuns: [], prompts: [], autoFile: files[AUTO] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.commands).toEqual(['/clear', '/model sonnet', '/effort high'])
    expect(w.autoRuns).toContain('--session sess-2 rebind --to sess-2')
    expect(w.autoRuns).toContain('--session sess-2 resumed')
    expect(w.prompts).toEqual(['Execute docs/plan.md.'])
    expect(pendingOf(files)).toBeNull()
  })

  test('tells the cleared session when its model was refused', async ($, on) => {
    const files = autoFiles({ pending: 'clear', resumePrompt: 'Execute docs/plan.md.', launch: { model: 'sonnet', effort: 'high' } })
    const w: World = { ...SIGNED_IN, commands: [], prompts: [], autoFile: files[AUTO], refusedCommands: ['model'] }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.prompts).toHaveLength(1)
    expect(w.prompts?.[0]).toMatch(/could not run \/model sonnet/)
    expect(w.prompts?.[0]).toMatch(/auto-run ruling add/)
  })

  test('stops the run when the cleared session cannot be bound', async ($, on) => {
    const files = autoFiles({ pending: 'clear', resumePrompt: 'Execute docs/plan.md.' })
    const w: World = { ...SIGNED_IN, commands: [], autoRuns: [], prompts: [], autoFile: files[AUTO], autoRunExits: { rebind: 1 } }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: 'Handed off.\n\nAuto run: clearing', durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.autoRuns).toContain('--session sess-1 stop --reason the cleared session could not be bound')
    expect(w.prompts).toHaveLength(1)
    expect(w.prompts?.[0]).toMatch(/could not be bound/)
  })

  test('retries the stage that failed', async ($, on) => {
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], autoFile: files[AUTO], submitFailures: 1 }
    const clock = world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.prompts).toEqual([])
    expect(w.autoRuns?.filter(call => call.includes(' failure '))).toHaveLength(1)
    await clock.advance(5_000)
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.prompts).toHaveLength(1)
    expect(w.prompts?.[0]).toMatch(/after-compact/)
  })

  test('books a refused compaction and retries it once', async ($, on) => {
    const w: World = { ...SIGNED_IN, compacts: [], autoRuns: [], prompts: [], isCompactVetoed: true }
    const clock = world(on, w)
    signedIn(on, autoFiles())
    await $.session.start(START)
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.autoRuns?.filter(call => call.includes(' failure '))).toHaveLength(1)
    await clock.advance(5_000)
    await settle(clock)
    expect(w.compacts).toHaveLength(2)
    expect(w.prompts).toEqual([])
  })

  test('at the second failure, says so once and asks for the ending', async ($, on) => {
    const fetches: World['fetches'] = []
    const files = autoFiles()
    const w: World = { ...SIGNED_IN, fetches, compacts: [], prompts: [], isCompactVetoed: true, autoRunExits: { failure: 5 }, autoFile: files[AUTO] }
    const clock = world(on, w)
    mock.store(on, { notifyUrl: WEBHOOK })
    signedIn(on, files)
    await $.session.start(START)
    await $.turn.complete({ answer: SENTINEL, durationMs: 1, isAborted: false, turnId: 't1', reason: 'answer' })
    await settle(clock)
    await clock.advance(5_000)
    await settle(clock)
    expect(w.compacts).toHaveLength(1)
    expect(w.prompts).toHaveLength(1)
    expect(w.prompts?.[0]).toMatch(/auto run stopped/i)
    const titles = fetches.map(one => (one.body.embeds as Record<string, unknown>[] | undefined)?.[0]?.title)
    expect(titles.filter(title => title === '⛔ Auto run stopped')).toHaveLength(1)
  })

  test('books a compaction the engine made', async ($, on) => {
    const w: World = { ...SIGNED_IN, autoRuns: [] }
    world(on, w)
    signedIn(on, autoFiles({ pending: null }))
    await $.session.start(START)
    await $.session.compact({ trigger: 'auto', messages: [SUMMARY] })
    expect(w.autoRuns).toContain('--session sess-1 compacted')
  })

  test('books nothing without a run', async ($, on) => {
    const w: World = { ...SIGNED_IN, autoRuns: [] }
    world(on, w)
    signedIn(on, {})
    await $.session.start(START)
    await $.session.compact({ trigger: 'auto', messages: [SUMMARY] })
    expect(w.autoRuns).toEqual([])
  })

  test('reads a run only for its session, and its sentinel only as the last line', () => {
    const text = autoFiles({ session: 'b', launch: { model: 'sonnet', effort: 'high' } })[AUTO]!.text
    expect(autoRunFor(text, 'b')?.launch).toEqual({ model: 'sonnet', effort: 'high' })
    expect(autoRunFor(text, 'b')?.plan).toBe('docs/plan.md')
    expect(autoRunFor(text, 'a')).toBeNull()
    expect(autoRunFor('not json', 'b')).toBeNull()
    expect(endsOnSentinel('x\n\nAuto run: compacting  \n\n', 'compact')).toBe(true)
    expect(endsOnSentinel('Auto run: compacting\nmore', 'compact')).toBe(false)
    expect(endsOnSentinel('Auto run: clearing', 'compact')).toBe(false)
    expect(endsOnSentinel('Auto run: clearing', 'clear')).toBe(true)
    expect(endsOnSentinel('Auto run: compacting', null)).toBe(false)
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 claude plugin test plugins/dr-forge` (repository root)
Expected: FAIL — `autoRunFor` is not exported, and the `auto run` tests fail.

- [ ] **Step 3: Write the implementation**

In `types/index.d.ts`, add after the `CockpitFinish` type:

```ts
/** An auto run as its state file says (reference/auto-run.md), for the session it is bound to. */
export type CockpitAutoRun = {
  active: boolean
  phase: string
  regime: string
  /** `compact`, `after-compact`, `clear`, `resume`, or null. */
  pending: string | null
  /** The plan's repository-relative path, once attached. */
  plan: string | null
  compactions: number
  resumes: number
  /** Why the run stopped; null while it runs or once it finished. */
  stopped: string | null
  /** The first prompt of the session a clear starts. */
  resumePrompt: string | null
  /** The model and effort that session runs on. */
  launch: { model: string; effort: string } | null
}
```

and inside `'dr-forge': {` of `PluginState`, after `isPlanSession: boolean`:

```ts
      /** The auto run bound to this session, as last read; null without one. */
      autoRun: CockpitAutoRun | null
```

In `hooks/cockpit/lib.ts`, change line 1 to `import type { CockpitAutoRun, CockpitFinish } from '../../types'` and append:

```ts
/** The run in an auto-run state file when it is bound to `sessionId`, active or not; else null. */
export function autoRunFor(text: string, sessionId: string): CockpitAutoRun | null {
  let parsed: unknown
  try {
    parsed = JSON.parse(text)
  } catch {
    return null
  }
  if (typeof parsed !== 'object' || parsed === null) return null
  const s = parsed as Record<string, unknown>
  if (s.session !== sessionId) return null
  const word = (value: unknown) => (typeof value === 'string' ? value : null)
  const count = (value: unknown) => (typeof value === 'number' && Number.isFinite(value) ? value : 0)
  const launch = (typeof s.launch === 'object' && s.launch !== null ? s.launch : {}) as Record<string, unknown>
  return {
    active: s.active === true,
    phase: word(s.phase) ?? 'spec',
    regime: word(s.regime) ?? 'normal',
    pending: word(s.pending),
    plan: word(s.plan),
    compactions: count(s.compactions),
    resumes: count(s.resumes),
    stopped: word(s.stopped),
    resumePrompt: word(s.resumePrompt),
    launch: typeof launch.model === 'string' && typeof launch.effort === 'string' ? { model: launch.model, effort: launch.effort } : null,
  }
}

/** The line an auto run's turn ends on, by the pending action it answers. */
export const AUTO_SENTINELS: Readonly<Record<string, string>> = { compact: 'Auto run: compacting', clear: 'Auto run: clearing' }

/** Whether `answer`'s last non-blank line is the sentinel for `pending`. */
export function endsOnSentinel(answer: string, pending: string | null): boolean {
  const sentinel = pending === null ? undefined : AUTO_SENTINELS[pending]
  if (sentinel === undefined) return false
  const lines = answer.split('\n').map(line => line.trimEnd()).filter(line => line !== '')
  return lines[lines.length - 1] === sentinel
}
```

In `hooks/cockpit/register.tsx`:

(a) Add `autoRunFor,` and `endsOnSentinel,` to the `import { … } from './lib'` list, and `CockpitAutoRun,` to the `import type { … } from '../../types'` list.

(b) After the line `const RESUME_WITHIN = 3 * 86_400_000`, insert:

```ts
// What an auto run's compaction keeps (reference/auto-run.md).
const AUTO_COMPACT_INSTRUCTIONS =
  'Preserve verbatim: the worktree path; the plan, ledger, handoff and auto-run state file paths; the current HEAD; every Ruling: line; and the auto run pending decisions. Name the task in progress and its fix round.'
// A failed stage is tried again after this long; a live turn or background work defers it as long.
const AUTO_RETRY_MS = 5_000
type AutoStage = 'compact' | 'continue' | 'clear' | 'resume'
// The pending action the state file holds while each stage is due.
const AUTO_STAGE_PENDING: Record<AutoStage, string> = { compact: 'compact', continue: 'after-compact', clear: 'clear', resume: 'resume' }
function autoContinuePrompt(root: string, plan: string | null): string {
  const where = plan === null ? '' : ` for plan ${plan}, through the After compaction steps of the execution skill its Execution line names`
  return `Continue the auto run: run \`bash ${root}/scripts/auto-run after-compact\` first, then continue the phase \`bash ${root}/scripts/auto-run status\` names${where}, as reference/auto-run.md §After a compaction says.`
}
```

(c) After the line `const isPlanSession = atom({ plugin: 'dr-forge', key: 'isPlanSession' } as const, false)`, add:

```ts
const autoRun = atom({ plugin: 'dr-forge', key: 'autoRun' } as const, null)
```

(d) In `const S = {`, add before its closing `}`:

```ts
  // The auto run's scheduled stage, at most one.
  autoTimer: null as Timer | null,
```

(e) In the `on('session.start', …)` hook, replace

```ts
    await readRun($)
    await readVersion($)
```

with

```ts
    await readRun($)
    await trackAutoRun($)
    await readVersion($)
```

(f) In the `on('session.compact', …)` hook, replace

```ts
    if (e.agentId === undefined && e.trigger !== 'precompute' && 'messages' in done && done.messages !== undefined) {
      await update($, budget, () => null)
      await update($, isNudged, () => false)
    }
```

with

```ts
    if (e.agentId === undefined && e.trigger !== 'precompute' && 'messages' in done && done.messages !== undefined) {
      await update($, budget, () => null)
      await update($, isNudged, () => false)
      // The engine's or the person's compaction: the run's rule still applies after it.
      if (e.trigger === 'auto' || e.trigger === 'manual') await bookAutoCompaction($)
    }
```

(g) In the `on('turn.complete', …)` hook, replace

```ts
    if (e.agentId === undefined) {
      compactWindow = await readCompactWindow($)
```

with

```ts
    if (e.agentId === undefined) {
      await trackAutoRun($)
      compactWindow = await readCompactWindow($)
```

and replace

```ts
      return done
    }
    const agentId = e.agentId
```

with

```ts
      if (e.reason === 'answer') await armAutoRun($, e.answer)
      return done
    }
    const agentId = e.agentId
```

(h) Insert after the top-level function `stateDirOf` (after its closing `}`):

```ts
// The auto run state file in the primary checkout, as the run bound to this
// session; null when there is none or another session owns it.
async function readAutoRun($: EngineInterface): Promise<CockpitAutoRun | null> {
  const root = S.where.primary ?? (await read($, place))?.root ?? null
  if (root === null) return null
  const state = await stateDirOf($, root)
  const text = await $.fs.read(`${state}/sdd/auto-run.json`).catch(() => null)
  if (typeof text !== 'string') return null
  return autoRunFor(text, await $.session.id())
}

// Runs scripts/auto-run as `sessionId`; resolves its exit code, 1 when it could not run.
async function autoRunCall($: EngineInterface, sessionId: string, args: string[]): Promise<number> {
  const ran = await $.process.run(['bash', `${$.plugin.root}/scripts/auto-run`, '--session', sessionId, ...args], { timeoutMs: 15_000 }).catch(() => null)
  return ran?.exitCode ?? 1
}

// Keeps the pane's copy of the bound run, and says once on Discord when the
// run stopped with a reason.
async function trackAutoRun($: EngineInterface) {
  const now = await readAutoRun($)
  const before = await read($, autoRun)
  if (JSON.stringify(now) === JSON.stringify(before)) return
  await update($, autoRun, () => now)
  if (before?.active === true && now !== null && !now.active && now.stopped !== null) {
    await notify($, { kind: 'blocked', title: '⛔ Auto run stopped', detail: now.stopped, isPlain: true })
  }
}

// A main turn of the bound run ended on the sentinel its pending action asks
// for: schedule the stage from a timer, so it never runs inside this hook
// (compact and /clear refuse there).
async function armAutoRun($: EngineInterface, answer: string) {
  const auto = await readAutoRun($)
  if (auto === null || !auto.active || !endsOnSentinel(answer, auto.pending)) return
  scheduleAutoAct($, auto.pending === 'clear' ? 'clear' : 'compact', 0)
}

function scheduleAutoAct($: EngineInterface, stage: AutoStage, ms: number) {
  S.autoTimer?.cancel()
  S.autoTimer = $.clock.after(ms, () => void autoAct($, stage))
}

// Carries the bound run through its pending stages: compact, then the
// continue prompt; or clear, rebind, model and effort, then the first prompt.
// Each attempt first re-checks that the stage is still due and the session
// idle. A failure is booked and the failed stage tried again; the script stops
// the run at the second (exit 5).
async function autoAct($: EngineInterface, stage: AutoStage) {
  S.autoTimer = null
  const auto = await readAutoRun($)
  if (auto === null || !auto.active || auto.pending !== AUTO_STAGE_PENDING[stage]) return
  if (S.isTurnLive || (await read($, spawns)).some(one => !one.isDone) || (await read($, shells)).length > 0) {
    scheduleAutoAct($, stage, AUTO_RETRY_MS)
    return
  }
  let bound = await $.session.id()
  let at: AutoStage = stage
  try {
    if (at === 'compact') {
      const done = await $.session.compact({ instructions: AUTO_COMPACT_INSTRUCTIONS })
      if ('skip' in done && typeof done.skip === 'string') throw new Error(done.skip)
      await update($, budget, () => null)
      await update($, isNudged, () => false)
      // The compaction happened: never repeat it, even if booking it failed.
      await autoRunCall($, bound, ['compacted'])
      at = 'continue'
    }
    if (at === 'continue') {
      await $.prompt.submit({ text: autoContinuePrompt($.plugin.root, auto.plan), asUser: true })
      return
    }
    if (at === 'clear') {
      await $.command.run({ command: 'clear' })
      const cleared = await $.session.id()
      if ((await autoRunCall($, cleared, ['rebind', '--to', cleared])) !== 0) {
        // The run is still bound to the session /clear ended: stop it from there.
        await endUnboundRun($, bound)
        return
      }
      bound = cleared
      at = 'resume'
    }
    const refused: string[] = []
    if (auto.launch !== null) {
      for (const [command, args] of [['model', auto.launch.model], ['effort', auto.launch.effort]] as const) {
        await $.command.run({ command, args }).catch(() => refused.push(`/${command} ${args}`))
      }
    }
    const note =
      refused.length === 0
        ? ''
        : `\n\nThe cockpit could not run ${refused.join(' or ')}; this session runs on ${await $.session.model()}. Record that with scripts/auto-run ruling add.`
    await $.prompt.submit({ text: `${auto.resumePrompt ?? resumePrompt()}${note}`, asUser: true })
    await autoRunCall($, bound, ['resumed'])
  } catch (error) {
    const why = error instanceof Error ? error.message : String(error)
    const action = at === 'compact' || at === 'continue' ? 'compact' : 'clear'
    const code = await autoRunCall($, bound, ['failure', '--reason', `the cockpit could not ${action}: ${why}`])
    if (code === 0) scheduleAutoAct($, at, AUTO_RETRY_MS)
    else if (code === 5) await endStoppedRun($)
  }
}

// The run stopped while the session was idle: record it, and give the model a
// turn to end the run as the attended flow would.
async function endStoppedRun($: EngineInterface) {
  await trackAutoRun($)
  const reason = (await read($, autoRun))?.stopped ?? 'the cockpit could not act'
  await $.prompt.submit({ text: `The auto run stopped: ${reason}. End as reference/auto-run.md §Stopping says.`, asUser: true }).catch(() => undefined)
}

// /clear went through but the cleared session could not be bound, so the
// state file no longer reads as this session's: stop the run as the session
// that owned it, and say so here.
async function endUnboundRun($: EngineInterface, owner: string) {
  const reason = 'the cleared session could not be bound'
  await autoRunCall($, owner, ['stop', '--reason', reason])
  await update($, autoRun, () => null)
  await notify($, { kind: 'blocked', title: '⛔ Auto run stopped', detail: reason, isPlain: true })
  await $.prompt.submit({ text: `The auto run stopped: ${reason}. End as reference/auto-run.md §Stopping says.`, asUser: true }).catch(() => undefined)
}

// A compaction the cockpit did not make, booked so the run's rule applies after it.
async function bookAutoCompaction($: EngineInterface) {
  const auto = await readAutoRun($)
  if (auto === null || !auto.active) return
  await autoRunCall($, await $.session.id(), ['compacted'])
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 claude plugin test plugins/dr-forge`
Expected: every test passes, including the `auto run` describe; the module loads (no "hooks module did not load").

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/types/index.d.ts plugins/dr-forge/hooks/cockpit/lib.ts plugins/dr-forge/hooks/cockpit/register.tsx plugins/dr-forge/tests/cockpit.test.ts
git commit -m "feat(dr-forge): compact and clear for an auto run"
```

---

### Task 6: Auto budget line

**Files:**
- Modify: `scripts/lib/context.sh` (source line after line 27, new function before `ctx_line`, `ctx_line`)
- Modify: `scripts/context-size:6` (exit line)
- Test: `tests/budget-line.test.sh`, `tests/context-size.test.sh`

**Interfaces:**
- Consumes: C3 `ar_bound`, `ar_verdict` (Tasks 1, 3); C4.
- Produces: C5.

**Items:** 5, 7

**Depends on:** Task 3

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing tests**

In `tests/budget-line.test.sh`, insert immediately before the line `# --- a missing task still fails the way it did ---`:

```bash
# --- an auto run bound to this session: its own rule replaces the budget ---
bash "$P/scripts/auto-run" --session s-1 start --spec docs/spec.md --register docs/reg.md >/dev/null
out=$(CLAUDE_CODE_SESSION_ID=s-1 bash "$P/scripts/task-brief" docs/plan.md 1 2>/dev/null); status=$?
check "task-brief: an auto run says compact" "$(tail -n 1 <<<"$out")" \
  "budget (auto): 500k of 465k (107%) — compact — source: record"
check "task-brief: exit unchanged under an auto run" "$status" "0"
out=$(CLAUDE_CODE_SESSION_ID=s-1 bash "$P/scripts/review-package" docs/plan.md "$BASE" HEAD 2>/dev/null)
check "review-package: an auto run says compact" "$(tail -n 1 <<<"$out")" \
  "budget (auto): 500k of 465k (107%) — compact — source: record"
printf '# SDD ledger — plan: docs/plan.md\nTask 1: complete (commit abc1234)\nTask 2: complete (commit abc1235)\n' > "$L"
out=$(CLAUDE_CODE_SESSION_ID=s-1 bash "$P/scripts/task-brief" docs/plan.md 3 2>/dev/null)
check "task-brief: an auto run replaces the tail limit" "$(tail -n 1 <<<"$out")" \
  "budget (auto): 500k of 465k (107%) — compact — source: record"
rm -f "$L"
out=$(CLAUDE_CODE_SESSION_ID=s-2 bash "$P/scripts/task-brief" docs/plan.md 1 2>/dev/null)
check "task-brief: another session keeps the task budget" "$(tail -n 1 <<<"$out")" \
  "budget: 500k of 465k (107%) — handoff — source: record?"
bash "$P/scripts/auto-run" --session s-1 stop >/dev/null
```

In `tests/context-size.test.sh`, insert immediately before the line `printf '\n%d passed, %d failed\n' "$pass" "$fail"`:

```bash
# --- an auto run bound to this session ---
AUTO_T="$PROJ/auto-1.jsonl"
settings 800000
asst 300000 > "$AUTO_T"; record auto-1 "$AUTO_T"
(cd "$REPO" && bash "$HERE/../scripts/auto-run" --session auto-1 start --spec docs/s.md --register docs/r.md >/dev/null)
export CLAUDE_CODE_SESSION_ID=auto-1
unset DR_FORGE_BUDGET
run
check "auto, unpinned: the derived budget at an 800k window" "$status:$out" "0:budget (auto): 300k of 604k (49%) — ok — source: record"
export DR_FORGE_BUDGET=465000
run
check "auto: ok, exit 0" "$status:$out" "0:budget (auto): 300k of 465k (64%) — ok — source: record"
run --plan
check "auto: --plan keeps its own limit" "$out" "budget (plan): 300k of 680k (44%) — ok — source: record"
run --wave 2
check "auto: a wave reserves a task" "$out" "budget (auto, wave of 2): 300k of 325k (92%) — ok — source: record"
asst 470000 > "$AUTO_T"
run
check "auto: compact, exit 6" "$status:$out" "6:budget (auto): 470k of 465k (101%) — compact — source: record"
run --final
check "auto: --final follows the run's rule" "$out" "budget (auto): 470k of 465k (101%) — compact — source: record"
(cd "$REPO" && bash "$HERE/../scripts/auto-run" --session auto-1 compacted)
asst 400000 > "$AUTO_T"
run
check "auto: the first reading after a compaction settles the regime" "$out" "budget (auto, high): 400k of 720k (55%) — ok — source: record"
asst 725000 > "$AUTO_T"
run
check "auto, high: compact at 90% of the window" "$status:$out" "6:budget (auto, high): 725k of 720k (100%) — compact — source: record"
(cd "$REPO" && bash "$HERE/../scripts/auto-run" --session auto-1 compacted)
asst 690000 > "$AUTO_T"
run
check "auto: a compaction that left 85% of the window hands off" "$status:$out" "5:budget (auto, high): 690k of 720k (95%) — handoff — source: record"
CLAUDE_CODE_SESSION_ID=auto-2 run
check "auto: another session keeps the task budget" "$status:$out" "5:budget: 690k of 465k (148%) — handoff — source: record?"
(cd "$REPO" && bash "$HERE/../scripts/auto-run" --session auto-1 stop)
unset DR_FORGE_BUDGET CLAUDE_CODE_SESSION_ID
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `timeout 600 bash plugins/dr-forge/tests/budget-line.test.sh` and `timeout 600 bash plugins/dr-forge/tests/context-size.test.sh`
Expected: the new `auto` checks FAIL (plain `budget:` lines), non-zero exits.

- [ ] **Step 3: Write the implementation**

In `scripts/lib/context.sh`:

(a) After the line `. "$(dirname "${BASH_SOURCE[0]}")/forge-env.sh"`, add:

```bash
. "$(dirname "${BASH_SOURCE[0]}")/auto-run.sh"
```

(b) Insert immediately before the comment line `# ctx_line [final | tail R | plan | wave W] — print the budget line; return 0 ok, 5`:

```bash
# ctx_auto_line TOKENS MODEL WIDTH — the budget line while an auto run is bound
# to this session (reference/auto-run.md): the run's rule replaces the task
# budget, the tail, the final-phase limit and relaxed mode. Returns 0 ok,
# 6 compact, 5 handoff, 3 when the run cannot be read.
ctx_auto_line() {
  local tokens=$1 task window out verdict limit regime label
  task=$(ctx_pinned_budget)
  [ -n "$task" ] || task=$(ctx_budget "$2")
  window=$(ctx_window "$2")
  out=$(ar_verdict "$tokens" "$task" "$window" "$3") || return 3
  read -r verdict limit regime <<<"$out"
  label="budget (auto"
  [ "$regime" = high ] && label="$label, high"
  [ "$3" -gt 1 ] && label="$label, wave of $3"
  label="$label)"
  echo "$label: $(( (tokens + 500) / 1000 ))k of $(( (limit + 500) / 1000 ))k ($(( tokens * 100 / limit ))%) — $verdict — source: $CTX_SOURCE"
  case $verdict in
    compact) return 6 ;;
    handoff) return 5 ;;
  esac
  return 0
}

```

(c) In `ctx_line`, replace

```bash
  local label=budget extra=0
  local limit=task
```

with

```bash
  local label=budget extra=0
  local limit=task auto=0 width=1
```

(d) In `ctx_line`, replace

```bash
  if [ "$limit" = task ] && [ "$(forge_setting handoffMode strict)" = relaxed ]; then
```

with

```bash
  [ "${1:-}" = wave ] && width=${2:-1}
  # An auto run bound to this session replaces every limit but the plan's.
  if [ "${1:-}" != plan ]; then
    AR_SESSION=${AR_SESSION:-${CLAUDE_CODE_SESSION_ID:-}}
    ar_bound && auto=1
  fi
  if [ "$limit" = task ] && [ "$(forge_setting handoffMode strict)" = relaxed ]; then
```

(e) In `ctx_line`, replace

```bash
  if ! tokens=$(ctx_measure "$CTX_TRANSCRIPT"); then
    echo "$label: unknown of ${bk}k — unknown — no usage entry in $CTX_TRANSCRIPT"; return 3
  fi
```

with

```bash
  if ! tokens=$(ctx_measure "$CTX_TRANSCRIPT"); then
    echo "$label: unknown of ${bk}k — unknown — no usage entry in $CTX_TRANSCRIPT"; return 3
  fi
  if [ "$auto" = 1 ]; then
    ctx_auto_line "$tokens" "$model" "$width"
    return
  fi
```

In `scripts/context-size`, replace the line `# Exit: 0 ok; 5 handoff due; 3 unknown; 2 usage.` with:

```bash
# Exit: 0 ok; 5 handoff due; 6 compact (an auto run, reference/auto-run.md);
# 3 unknown; 2 usage.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `timeout 600 bash plugins/dr-forge/tests/budget-line.test.sh`, `timeout 600 bash plugins/dr-forge/tests/context-size.test.sh`, `timeout 600 bash plugins/dr-forge/tests/auto-run.test.sh`
Expected: each ends `0 failed`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/scripts/lib/context.sh plugins/dr-forge/scripts/context-size plugins/dr-forge/tests/budget-line.test.sh plugins/dr-forge/tests/context-size.test.sh
git commit -m "feat(dr-forge): print the auto verdict on budget lines"
```

---

### Task 7: Cockpit auto line and muted note

**Files:**
- Modify: `hooks/cockpit/lib.ts` (append)
- Modify: `hooks/cockpit/register.tsx` (lib import, `tool.call` hook, `refresh`, `onBudget`, pane actions, one new top-level function)
- Test: `tests/cockpit.test.ts` (lib import list; append)

**Interfaces:**
- Consumes: C7 `CockpitAutoRun`, atom `autoRun`; C8 `autoRunCall`, `trackAutoRun`, `bookAutoCompaction` (position anchor); C9 helpers.
- Produces: C7 `autoLimitFor`.

**Items:** 5, 7

**Depends on:** Task 5

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

Add `autoLimitFor,` to the test file's `import { … } from '../hooks/cockpit/lib'` list, and append at the end of `tests/cockpit.test.ts`:

```ts
describe('auto run in the pane', () => {
  test('the limit follows the regime', () => {
    expect(autoLimitFor('normal', 465_000, 1_000_000, 800_000)).toBe(465_000)
    expect(autoLimitFor('normal', 0, 1_000_000, 800_000)).toBe(604_000)
    expect(autoLimitFor('high', 465_000, 1_000_000, 800_000)).toBe(720_000)
    expect(autoLimitFor('high', 0, 650_000)).toBe(585_000)
  })

  test('shows the run and stops it from the pane', async ($, on) => {
    const files = autoFiles({ pending: null, compactions: 2 })
    const w: World = { ...SIGNED_IN, autoRuns: [], autoFile: files[AUTO] }
    world(on, w)
    signedIn(on, files)
    await $.session.start(START)
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /Auto run · execute · normal · 2 compactions · 0 resumes/ })).toBeDefined()
    await ui.press({ key: 'pane-stop-auto' })
    expect(w.autoRuns).toContain('--session sess-1 stop --reason owner pressed Stop auto')
  })

  test('picks up a run started during the turn, and mutes the handoff note', async ($, on) => {
    const notes: string[] = []
    world(on, { ...SIGNED_IN, tokens: 470_000, notes })
    const files: NonNullable<World['files']> = {}
    signedIn(on, files)
    await $.session.start(START)
    files[AUTO] = autoFiles({ pending: null })[AUTO]!
    await $.tool.call({ tool: 'Skill', skill: 'dr-forge:subagent-driven-development' })
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    expect(notes).toEqual([])
  })

  test('measures against the high regime', async ($, on) => {
    world(on, { ...SIGNED_IN, tokens: 470_000 })
    signedIn(on, autoFiles({ pending: null, regime: 'high' }))
    await $.session.start(START)
    await $.tool.call({ tool: 'Bash', command: 'ls' })
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /80% of handoff/ })).toBeDefined()
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 claude plugin test plugins/dr-forge`
Expected: FAIL — `autoLimitFor` is not exported; the pane tests fail.

- [ ] **Step 3: Write the implementation**

In `hooks/cockpit/lib.ts`, append:

```ts
/**
 * An auto run's compaction point (reference/auto-run.md): the task budget, or
 * 90% of min(autoCompactWindow, window) in the high regime.
 */
export function autoLimitFor(regime: string, configured: number, window: number, compactWindow?: number): number {
  if (regime !== 'high') return budgetFor(configured, undefined, window, compactWindow)
  const room = compactWindow !== undefined && compactWindow > 0 ? Math.min(window, compactWindow) : window
  return Math.floor(room * 0.9)
}
```

In `hooks/cockpit/register.tsx`:

(a) Add `autoLimitFor,` to the `./lib` import list.

(b) In the `on('tool.call', …)` hook, replace

```ts
      if (ran.deny === undefined && !ran.isError) await trackPlan($, tool, e, ran.result)
      await onBudget($, await refresh($, (await live($)).tuning, compactWindow))
```

with

```ts
      if (ran.deny === undefined && !ran.isError) await trackPlan($, tool, e, ran.result)
      // A run starts, stops and changes regime through the model's own calls.
      await trackAutoRun($)
      await onBudget($, await refresh($, (await live($)).tuning, compactWindow))
```

(c) In `refresh`, replace

```ts
  const limit = tuning.isRelaxed ? finalLimitFor(window, compactWindow) : budgetFor(handoffTokens, undefined, window, compactWindow)
```

with

```ts
  const auto = await read($, autoRun)
  const isAuto = auto !== null && auto.active
  const limit = isAuto
    ? autoLimitFor(auto.regime, handoffTokens, window, compactWindow)
    : tuning.isRelaxed
      ? finalLimitFor(window, compactWindow)
      : budgetFor(handoffTokens, undefined, window, compactWindow)
```

and replace

```ts
  if (!nudgeModel || (await read($, isNudged)) || !(await read($, isPlanSession))) return reading
```

with

```ts
  // An auto run compacts at its limit rather than handing off: no note.
  if (!nudgeModel || isAuto || (await read($, isNudged)) || !(await read($, isPlanSession))) return reading
```

(d) In `onBudget`, replace

```ts
  if (reading === undefined) return
  const { now, isPast } = reading
```

with

```ts
  if (reading === undefined) return
  if ((await read($, autoRun))?.active) return
  const { now, isPast } = reading
```

(e) In the pane render hook, replace

```ts
    const isNearHandoff = head !== null && levelOf(head.tokens, head.limit, o.tuning.warnAt) !== 'quiet'
```

with

```ts
    const isNearHandoff = head !== null && levelOf(head.tokens, head.limit, o.tuning.warnAt) !== 'quiet'
    const autoNow = await read($, autoRun)
```

and replace

```tsx
        {canHandOff && button('pane-handoff', 'Hand off', () => $.prompt.submit({ text: HANDOFF_PROMPT, asUser: true }), { hotkey: 'h', isMain: isNearHandoff })}
```

with

```tsx
        {autoNow?.active && (
          <Text key="auto-line" color="magenta">
            {`Auto run · ${autoNow.phase} · ${autoNow.regime} · ${autoNow.compactions} compactions · ${autoNow.resumes} resumes`}
          </Text>
        )}
        {autoNow?.active && button('pane-stop-auto', 'Stop auto', () => void stopAutoRun($), { hotkey: 'x' })}
        {canHandOff && button('pane-handoff', 'Hand off', () => $.prompt.submit({ text: HANDOFF_PROMPT, asUser: true }), { hotkey: 'h', isMain: isNearHandoff })}
```

(f) After the top-level function `bookAutoCompaction`, add:

```ts
async function stopAutoRun($: EngineInterface) {
  await autoRunCall($, await $.session.id(), ['stop', '--reason', 'owner pressed Stop auto'])
  await trackAutoRun($)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 claude plugin test plugins/dr-forge`
Expected: every test passes, the `auto run` describe included.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/hooks/cockpit/lib.ts plugins/dr-forge/hooks/cockpit/register.tsx plugins/dr-forge/tests/cockpit.test.ts
git commit -m "feat(dr-forge): show the auto run in the cockpit"
```

---

### Task 8: Planning, worktree, handoff, resume and finishing skills

**Files:**
- Modify: `skills/writing-plans/SKILL.md` (new section before `## Scope Check`; Execution Handoff first line)
- Modify: `skills/using-git-worktrees/SKILL.md` (before the line starting `Has the user already indicated`)
- Modify: `skills/handoff/SKILL.md` (When list)
- Modify: `skills/resume-execution/SKILL.md` (before `## Red Flags`)
- Modify: `skills/finishing-a-development-branch/SKILL.md` (before `## Step 1: Verify Tests`)
- Test: `tests/settings-skills.test.sh`

**Interfaces:**
- Consumes: C2, C6, C10, C11.
- Produces: none.

**Items:** 3, 9, 10, 11

**Depends on:** Task 1, Task 2

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

- [ ] **Step 1: Write the failing test**

In `tests/settings-skills.test.sh`, insert immediately before the line `# Every skill-enforced key in the schema is named by at least one skill.`:

```bash
# The auto run (reference/auto-run.md) where each skill would otherwise ask.
names "brainstorming: autoRun" "$B" '`autoRun=off`: never offer an auto run'
names "brainstorming offers the auto run" "$B" 'Run the rest unattended?'
names "brainstorming: the review gate gives way to the Fable review" "$B" 'In an auto run (`scripts/auto-run status` exits 0), skip this gate'
names "writing-plans: an auto run asks nothing" "$W" 'nothing in this skill waits on your human partner'
names "writing-plans: planning choices go to Opus first" "$W" '`dr-forge:judge-opus` first, then the ladder'
names "writing-plans: the plan step owns the clear" "$W" '`scripts/auto-run clear --phase`'
names "using-git-worktrees: an auto run creates the worktree" "$G" 'In an auto run (`scripts/auto-run status` exits 0), create the worktree without asking'
names "handoff: the caller owns the clear" "$P/skills/handoff/SKILL.md" 'never runs `scripts/auto-run clear` itself'
names "resume-execution: an auto run stops before asking" "$P/skills/resume-execution/SKILL.md" 'scripts/auto-run stop --reason'
names "finishing: an auto run shows no menu" "$P/skills/finishing-a-development-branch/SKILL.md" '**Step 4 shows no menu.**'
names "finishing: the run's base" "$P/skills/finishing-a-development-branch/SKILL.md" 'the base `scripts/auto-run status` names'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dr-forge/tests/settings-skills.test.sh`
Expected: FAIL on the writing-plans, using-git-worktrees, handoff, resume-execution and finishing checks; non-zero exit.

- [ ] **Step 3: Write the skill text**

`skills/writing-plans/SKILL.md` — insert immediately before the line `## Scope Check`:

```markdown
## Auto run

When `scripts/auto-run status` exits 0, this plan is written unattended
([auto-run.md](../../reference/auto-run.md)). Run `scripts/auto-run phase plan`
first. Then nothing in this skill waits on your human partner:

- **The execution strategy:** take the spec's `**Execution strategy:**` line;
  with none, write `sequential`.
- **An approach or planning choice** you would ask about goes to
  `dr-forge:judge-opus` first, then the ladder in auto-run.md §Rulings.
  dr-forge:selecting-approaches runs as usual otherwise.
- **The executor offer:** tick only what a constraint ticks without asking;
  start no timed question.
- **At the review cap,** a Critical finding or a score of 8 or below goes on
  the pending list, and the Fable batch rules on it with the rest.
- **Once the plan is reviewed:** `scripts/auto-run attach --plan PLAN_FILE`,
  the Fable batch when `scripts/auto-run decision list` prints anything, then
  Execution Handoff. This step owns the clear: after dr-forge:handoff, run
  `scripts/auto-run clear --phase` and end as auto-run.md §Clears says.

```

and replace the line `A saved, reviewed plan is a hard stop: execution starts in a fresh session.` with:

```markdown
A saved, reviewed plan is a hard stop: execution starts in a fresh session (in
an auto run the cockpit starts it; see Auto run).
```

`skills/using-git-worktrees/SKILL.md` — insert, as its own paragraph immediately before the line that starts `Has the user already indicated their worktree preference`:

```markdown
In an auto run (`scripts/auto-run status` exits 0), create the worktree without asking, as `worktree=always` does ([auto-run.md](../../reference/auto-run.md)).

```

`skills/handoff/SKILL.md` — insert immediately before the line `- Your human partner says they are stepping away for more than an hour, or`:

```markdown
- An auto run ([auto-run.md](../../reference/auto-run.md)) hands off for a
  compaction that left too much, for a saved plan, and for the spec-to-plan
  limit. The steps below run as always, but the turn does not end on the
  next-step block: return to the step that invoked this skill, which runs
  `scripts/auto-run clear` and ends the turn (auto-run.md §Clears). This skill
  never runs `scripts/auto-run clear` itself.
```

`skills/resume-execution/SKILL.md` — insert immediately before the line `## Red Flags`:

```markdown
## Auto run

When `scripts/auto-run status` exits 0
([auto-run.md](../../reference/auto-run.md)), the cockpit started this session
after a clear, and nobody is watching. Run every step as above. Where step 2
would stop and ask (the worktree and its branch are gone), run
`scripts/auto-run stop --reason "the worktree and its branch are gone"`
first, then ask. After a compaction an auto run does not come here: it
follows the execution skill's After compaction steps.

```

`skills/finishing-a-development-branch/SKILL.md` — insert immediately before the line `## Step 1: Verify Tests`:

```markdown
## Auto run

When `scripts/auto-run status` exits 0
([auto-run.md](../../reference/auto-run.md)), run
`scripts/auto-run phase finish`, then follow this skill with these changes:

- **Step 3** asks nothing: the base branch is the base `scripts/auto-run status` names.
- **Step 4 shows no menu.** Read `scripts/forge-config get finishAction`:
  `merge` carries out Option 1 into that base and `pr` Option 2, as if your
  human partner had chosen it; `keep`, `ask` and `wait`, and `merge` when the
  base is `none`, carry out Option 3. Never discard. Arm no wake.
- **Where an unattended finish stops** (a merged result failing its tests, a
  rejected push, a refused worktree removal), run
  `scripts/auto-run stop --reason "<what stopped it>"` first, then stop as
  [finish-preference.md](../../reference/finish-preference.md) says.
- **The rulings** printed at Step 3 also include every line of
  `scripts/auto-run ruling list`, and Step 7's final message lists every
  deferred row the run added to its register (`scripts/auto-run status` names
  it). Run `scripts/auto-run stop` before printing the next-step block.

```

- [ ] **Step 4: Run test to verify it passes**

Run: `timeout 600 bash plugins/dr-forge/tests/settings-skills.test.sh` → Expected: `0 failed`, exit 0.
Run: `timeout 120 node scripts/validate-repository.mjs` → Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/skills/writing-plans/SKILL.md plugins/dr-forge/skills/using-git-worktrees/SKILL.md plugins/dr-forge/skills/handoff/SKILL.md plugins/dr-forge/skills/resume-execution/SKILL.md plugins/dr-forge/skills/finishing-a-development-branch/SKILL.md plugins/dr-forge/tests/settings-skills.test.sh
git commit -m "feat(dr-forge): run planning and finishing unattended"
```

---

### Task 9: Execution skills

**Files:**
- Modify: `skills/subagent-driven-development/SKILL.md` (new section before `## Select the host first`; the four-stops paragraph)
- Modify: `skills/executing-plans/SKILL.md` (same two places)
- Test: `tests/auto-run-skills.test.sh` (create, mode 755)

**Interfaces:**
- Consumes: C2, C5, C6, C10, C11.
- Produces: none.

**Items:** 4, 5, 8, 11

**Depends on:** Task 2, Task 6

**Implementer:** dr-superpowers:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Write the failing test**

Create `tests/auto-run-skills.test.sh`:

```bash
#!/usr/bin/env bash
# Both execution skills carry the auto run where a plan run would otherwise
# stop for its human: each check is a whole instruction, not a keyword.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" && echo yes || echo no)" "yes"
}

for skill in subagent-driven-development executing-plans; do
  F="$P/skills/$skill/SKILL.md"
  names "$skill: the section" "$F" '## Auto run'
  names "$skill: after a compaction" "$F" '`scripts/auto-run after-compact` before step 1 above'
  names "$skill: setup asks nothing" "$F" 'skip the finish-preference question; run `scripts/auto-run phase execute`'
  names "$skill: blocked goes to Fable" "$F" '`BLOCKED` goes on the pending list and one Fable batch runs at once'
  names "$skill: the deferred line" "$F" 'Task <N>: complete (deferred by the auto run)'
  names "$skill: dependents are deferred too" "$F" 'and every task that depends on it'
  names "$skill: never performed" "$F" 'is never performed'
  names "$skill: each task resets the count" "$F" '`scripts/auto-run task-complete`. After each wave'
  names "$skill: compact ends the turn" "$F" '`Auto run: compacting` as its last line'
  names "$skill: the step owns the clear" "$F" 'then run `scripts/auto-run clear` and end as auto-run.md §Clears says'
  names "$skill: final review" "$F" 'run `scripts/auto-run phase final`'
  names "$skill: the four stops give way" "$F" 'except in an auto run'
done
names "subagent-driven-development: a deferred task is not merged" "$P/skills/subagent-driven-development/SKILL.md" "a deferred task's branch is"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `timeout 600 bash plugins/dr-forge/tests/auto-run-skills.test.sh`
Expected: FAIL lines, non-zero exit.

- [ ] **Step 3: Write the skill text**

In `skills/subagent-driven-development/SKILL.md`, insert immediately before the line `## Select the host first`:

```markdown
## Auto run

When `scripts/auto-run status` exits 0, this run is unattended
([auto-run.md](../../reference/auto-run.md)); read that file once per session.
What changes here:

- **After a compaction**, the cockpit's prompt has you run
  `scripts/auto-run after-compact` before step 1 above. On `handoff` (exit 5),
  invoke dr-forge:handoff, then run `scripts/auto-run clear` and end as auto-run.md §Clears says.
- **Setup:** skip the finish-preference question; run `scripts/auto-run phase execute`.
- **Nothing stops for your human partner.** A ruling-seat or exhausted
  `BLOCKED` goes on the pending list and one Fable batch runs at once. An
  irreversible, security-sensitive or outside-the-worktree action is never performed.
  A task Fable gives no ruling for, or whose action is never performed, is
  deferred, and every task that depends on it: write
  `Task <N>: complete (deferred by the auto run) — done: nothing; verified: not run; remaining: <the item>[; partial commits <a7>..<b7>, kept for the final review]; discovered: none; assumptions: none; Ruling: <why> — <cost if wrong>`
  and a deferred register row for each. In a wave, a deferred task's branch is
  not merged. Other tasks keep running.
- **Each task:** right after its `Task N: complete` line, run
  `scripts/auto-run task-complete`. After each wave, or each task in
  sequential mode, run the Fable batch when `scripts/auto-run decision list`
  prints anything.
- **The budget line** reads `budget (auto…)`. On `compact` (exit 6), finish
  the task in flight (a wave through its merge), then end the turn with
  `Auto run: compacting` as its last line. On `handoff`, invoke
  dr-forge:handoff, then run `scripts/auto-run clear` and end as auto-run.md §Clears says.
  The tail rule and the final-phase limit do not apply;
  `scripts/context-size --final` prints the auto line too.
- **Final review:** run `scripts/auto-run phase final` and, when the pending
  list is not empty, the Fable batch first; the review's findings take the
  same ladder.
- **A turn ends** only on one of the two auto-run lines, or after
  `scripts/auto-run stop --reason "<why>"` when the run must stop.

```

In `skills/executing-plans/SKILL.md`, insert immediately before the line `## Select the host first` (inline mode runs no waves, so it has no wave clauses):

```markdown
## Auto run

When `scripts/auto-run status` exits 0, this run is unattended
([auto-run.md](../../reference/auto-run.md)); read that file once per session.
What changes here:

- **After a compaction**, the cockpit's prompt has you run
  `scripts/auto-run after-compact` before step 1 above. On `handoff` (exit 5),
  invoke dr-forge:handoff, then run `scripts/auto-run clear` and end as auto-run.md §Clears says.
- **Setup:** skip the finish-preference question; run `scripts/auto-run phase execute`.
- **Nothing stops for your human partner.** A ruling-seat or exhausted
  `BLOCKED` goes on the pending list and one Fable batch runs at once. An
  irreversible, security-sensitive or outside-the-worktree action is never performed.
  A task Fable gives no ruling for, or whose action is never performed, is
  deferred, and every task that depends on it: write
  `Task <N>: complete (deferred by the auto run) — done: nothing; verified: not run; remaining: <the item>[; partial commits <a7>..<b7>, kept for the final review]; discovered: none; assumptions: none; Ruling: <why> — <cost if wrong>`
  and a deferred register row for each. Other tasks keep running.
- **Each task:** right after its `Task N: complete` line, run
  `scripts/auto-run task-complete`. After each wave, or each task in
  sequential mode, run the Fable batch when `scripts/auto-run decision list`
  prints anything.
- **The budget line** reads `budget (auto…)`. On `compact` (exit 6), finish
  the task in flight, then end the turn with
  `Auto run: compacting` as its last line. On `handoff`, invoke
  dr-forge:handoff, then run `scripts/auto-run clear` and end as auto-run.md §Clears says.
  The tail rule and the final-phase limit do not apply;
  `scripts/context-size --final` prints the auto line too.
- **Final review:** run `scripts/auto-run phase final` and, when the pending
  list is not empty, the Fable batch first; the review's findings take the
  same ladder.
- **A turn ends** only on one of the two auto-run lines, or after
  `scripts/auto-run stop --reason "<why>"` when the run must stop.

```

In `skills/subagent-driven-development/SKILL.md`, replace the line

```
path forward is a guess. For those, stop and ask.
```

with

```
path forward is a guess. For those, stop and ask — except in an auto run,
which asks nothing (see Auto run).
```

In `skills/executing-plans/SKILL.md`, replace the line

```
ruling-seat `BLOCKED` verdict. For those, stop and ask.
```

with

```
ruling-seat `BLOCKED` verdict. For those, stop and ask — except in an auto run,
which asks nothing (see Auto run).
```

- [ ] **Step 4: Run the checks to verify they pass**

Run: `timeout 600 bash plugins/dr-forge/tests/auto-run-skills.test.sh` → Expected: `0 failed`, exit 0.
Run: `timeout 120 node scripts/validate-repository.mjs` → Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/skills/subagent-driven-development/SKILL.md plugins/dr-forge/skills/executing-plans/SKILL.md plugins/dr-forge/tests/auto-run-skills.test.sh
git commit -m "feat(dr-forge): execute plans unattended in an auto run"
```

---

### Task 10: Smoke-run checklist

**Files:**
- Create: `docs/superpowers/notes/2026-10-13-auto-run-smoke.md`

**Interfaces:**
- Consumes: C2, C5, C6, C11 (prose only).
- Produces: none.

**Items:** 5, 8, 9

**Depends on:** Task 2

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0

- [ ] **Step 1: Write the failing check**

Run: `test -f docs/superpowers/notes/2026-10-13-auto-run-smoke.md; echo $?`

- [ ] **Step 2: Run it to verify it fails**

Expected: `1`.

- [ ] **Step 3: Write the checklist**

Create `docs/superpowers/notes/2026-10-13-auto-run-smoke.md`:

```markdown
# Auto run smoke check

Settles the platform facts the auto-run design inferred
(`docs/superpowers/specs/2026-10-13-dr-forge-auto-run-design.md`, Platform
facts) and closes register rows 5, 8 and 9 of
`docs/superpowers/registers/2026-10-12-auto-execution.md`. It needs a person:
the session under test must run this branch's dr-forge build.

## Setup

1. A scratch repository with a committed toy spec and a three-task plan whose
   tasks each add one small file with a test, and whose Execution line names
   `subagent`.
2. Start Claude Code in it on this branch's dr-forge build, with
   `DR_FORGE_BUDGET=60000` in the environment and `autoCompactWindow` at
   800,000, so the first task brief already says `compact`.
3. In the session: `bash <plugin-root>/scripts/auto-run start --spec <spec>`,
   then `attach --plan <plan>` and `phase execute`, then ask it to execute the
   plan with dr-forge:subagent-driven-development.

## Observe

| # | What to observe | Expected | Observed (date, result) |
|---|---|---|---|
| 1 | The task brief's last line | `budget (auto): …k of 60k … — compact` | |
| 2 | The turn's last line after the task completes | `Auto run: compacting`, and the Stop hook lets it end | |
| 3 | The cockpit compacts on its own | a compaction, then a prompt naming `auto-run after-compact` | |
| 4 | The compaction snapshot | the SessionStart `compact` snapshot is in context after the cockpit's compaction | |
| 5 | `auto-run after-compact` | `continue — …k after compaction; regime …` | |
| 6 | A self-resume by hand: run `scripts/next-step <plan>`, then `scripts/auto-run clear`, and end a turn with `Auto run: clearing` | the cockpit runs `/clear`, then `/model` and `/effort` from the launch line, then submits the first prompt | |
| 7 | In the cleared session, `echo $CLAUDE_CODE_SESSION_ID` | the cleared session's own id, equal to the run's `session` after `rebind` | |
| 8 | In the cleared session, the SessionStart `clear` hook | a fresh record under `~/.claude/dr-forge/sessions/by-id/` for the new id | |
| 9 | The plan finishes | final review, then finishing by `finishAction`, no question asked | |
| 10 | Over the whole run | at least two cockpit compactions (`auto-run status` counts them) | |
| 11 | Right after a cockpit compaction, the pane's Context card | `no reading yet`, then a fresh figure: shows whether the cockpit's own `session.compact` hook ran for its own call | |
| 12 | A self-resume driven by the run itself: set `autoCompactWindow` to 100,000 for one session so a compaction leaves 85% of it | `after-compact` prints `handoff`, the model hands off, runs `auto-run clear` and the cockpit resumes as in row 6 | |

## Afterwards

Fill the Observed column. When every row matches, set rows 5, 8 and 9 of the
register to `done`. A row that does not match is a bug against the design:
file it as a new register row before anything is changed.
```

- [ ] **Step 4: Run the check to verify it passes**

Run: `test -f docs/superpowers/notes/2026-10-13-auto-run-smoke.md; echo $?` → Expected: `0`.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/notes/2026-10-13-auto-run-smoke.md
git commit -m "docs(dr-forge): add the auto-run smoke checklist"
```

---

### Task 11: Reference docs, README, release 2.2.0 and final verification

**Files:**
- Modify: `reference/session-budget.md` (before `## Idle`)
- Modify: `reference/finish-preference.md` (before `## The settings`)
- Modify: `reference/parallel-waves.md` (§1 serialize list, step 3, end of file)
- Modify: `agents/judge-fable.md:3`
- Modify: `tests/review-route.test.sh:387`
- Modify: `README.md` (settings table, Session budget section)
- Modify: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` (`version`)

**Interfaces:**
- Consumes: C5, C11.
- Produces: none.

**Items:** 10

**Depends on:** Task 2, Task 6

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6.1-sol / medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing check**

In `tests/review-route.test.sh`, replace line 387

```bash
present "no route names judge-fable" "$P/agents/judge-fable.md" 'No dr-forge route names it'
```

with

```bash
present "no route names judge-fable" "$P/agents/judge-fable.md" 'No dr-forge route names it'
present "an auto run dispatches judge-fable" "$P/agents/judge-fable.md" 'an auto run (reference/auto-run.md) dispatches it for the spec review and the batched rulings'
```

and run, from the repository root:

```bash
grep -c '^## Auto run$' plugins/dr-forge/reference/session-budget.md plugins/dr-forge/reference/finish-preference.md plugins/dr-forge/reference/parallel-waves.md
grep -c '`autoRun`' plugins/dr-forge/README.md
grep -h '"version"' plugins/dr-forge/.claude-plugin/plugin.json plugins/dr-forge/.codex-plugin/plugin.json
```

- [ ] **Step 2: Run them to verify they fail**

Run: `timeout 600 bash plugins/dr-forge/tests/review-route.test.sh` → Expected: `FAIL - an auto run dispatches judge-fable`.
The greps → Expected: every count `0`; both versions `2.1.0`.

- [ ] **Step 3: Write the docs**

`reference/session-budget.md` — insert immediately before the line `## Idle`:

```markdown
## Auto run

While an auto run is bound to the session ([auto-run.md](auto-run.md)), every
budget line but `context-size --plan` prints the run's own verdict,
`budget (auto…)`, and `context-size` exits 6 on `compact`. The run compacts at
the task budget, or at 90% of the compaction window once a compaction has left
85% of the task budget or more, less 140k per extra task of a wave; a
compaction that leaves 85% of the window or more hands off, and the cockpit
clears and resumes the session. The tail rule, the final-phase limit and
relaxed mode do not apply to it.

```

`reference/finish-preference.md` — insert immediately before the line `## The settings`:

```markdown
## Auto run

An auto run ([auto-run.md](auto-run.md)) never asks the question below:
finishing carries out `finishAction` at once into the run's recorded base
(`merge` or `pr`), and keeps the branch under `keep`, `ask` or `wait`, or when
there is no base, with no menu and no wake.

```

`reference/parallel-waves.md`:

- replace the line ``- `scripts/context-size --wave 2` says `handoff` (§1);`` with ``- `scripts/context-size --wave 2` says `handoff`, or `compact` in an auto run (§1);``
- replace the line ``   `scripts/context-size --wave <c>` and lower `c` while it exits 5; it`` with ``   `scripts/context-size --wave <c>` and lower `c` while it exits 5 (or 6, an auto run's `compact`); it``
- append at the end of the file:

```markdown

## Auto run

In an auto run ([auto-run.md](auto-run.md)) `--wave` prints the run's verdict.
Lower the width while it says `compact`, as on `handoff`; a narrower width that
fits cancels the compaction. At width 1 a `compact` verdict means finishing
the task in flight and ending the turn with `Auto run: compacting`. A task the
run defers is not merged.
```

`agents/judge-fable.md` — replace line 3 with:

```yaml
description: "Read-only verifier and ruling seat running Fable 5.1 at high effort. No dr-forge route names it: an auto run (reference/auto-run.md) dispatches it for the spec review and the batched rulings, and otherwise it runs only when your human partner asks for Fable on a judge seat, in place of the judge-opus seat the route printed."
```

`README.md`:

- in the settings table, insert after the row that starts ``| Workflow | `worktree` |``:

```markdown
| Workflow | `autoRun` | `ask` | `ask` offers, once the design is approved, to run the spec, plan, execution, review and finish unattended (Claude Code only); `off` never offers it. See [Auto run](#auto-run). |
```

- insert immediately before the line `## Cockpit` (the one that follows the Session budget section):

```markdown
### Auto run

After you approve a design, brainstorming can offer to run the rest
unattended. Fable reviews the spec, the plan is written and reviewed, the plan
executes in its recorded strategy, and the branch is finished by
`finishAction` into the branch the run started from (kept under `ask` or
`wait`), with no question to you. What Opus cannot rule goes to Fable in one
batch; what Fable cannot rule is deferred on the run's register. Instead of
handing off, the session compacts at the handoff budget, and the cockpit
clears and resumes it when a compaction leaves too much. The pane shows the
run and a **Stop auto** button. See [auto-run.md](reference/auto-run.md).

```

- `.claude-plugin/plugin.json` and `.codex-plugin/plugin.json`: change `"version": "2.1.0"` to `"version": "2.2.0"`.

- [ ] **Step 4: Run the final verification**

From the repository root, each must pass:

- `timeout 600 bash plugins/dr-forge/tests/review-route.test.sh` → `0 failed`.
- The Step 1 greps → each count `1`; both versions `2.2.0`.
- `timeout 120 node scripts/validate-repository.mjs` → exit 0.
- `timeout 2700 node scripts/test-all.mjs` → exit 0 (every maintained suite, `claude plugin test plugins/dr-forge` included).
- `timeout 120 claude plugin validate .`, then `timeout 120 claude plugin validate plugins/<name>` for each of `dr-forge`, `dr-status`, `dcc-darkraise-ui`, `dcc-darkraise-win32ui` → no errors.

Confirm afterwards that no process these commands started is still running (`pgrep -f test-all.mjs` prints nothing).

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-forge/reference/session-budget.md plugins/dr-forge/reference/finish-preference.md plugins/dr-forge/reference/parallel-waves.md plugins/dr-forge/agents/judge-fable.md plugins/dr-forge/tests/review-route.test.sh plugins/dr-forge/README.md plugins/dr-forge/.claude-plugin/plugin.json plugins/dr-forge/.codex-plugin/plugin.json
git commit -m "docs(dr-forge): document the auto run, release 2.2.0"
```
