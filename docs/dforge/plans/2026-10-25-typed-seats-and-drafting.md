# Typed Seats and Plan Drafting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep every dforge dispatch on a typed seat: a seat rule, a cockpit spawn check that denies untyped and fork dispatches, and a plan-drafting seat whose drafter (fork or typed Sonnet) a measurement picks.

**Architecture:** Task 1 measures fork drafters against a typed Sonnet drafter in a throwaway clone and writes `**Decision:** typed|fork` to a note. The cockpit's `agent.spawn` hook calls a pure `seatDenial()` in `hooks/cockpit/lib.ts`. The seat rule lives in using-dforge and the review seat in requesting-code-review. writing-plans gains a drafting section, joined by `scripts/draft-pack --join`.

**Tech Stack:** bash (3.2+, mawk-safe awk), jq, tmux, TypeScript (the cockpit mod and its `claude-code/testing` suite), markdown.

**Spec:** `docs/dforge/specs/2026-10-25-typed-seats-and-drafting-design.md`

**Execution:** subagent — `claude --model sonnet --effort high` — the plan runs parallel waves

**Parallelism:** waves — 1 | 2-4 | 5

**Integration check:** `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 3600 node scripts/test-all.mjs`

**Worktree setup:** none

**Plan review:** 2026-10-25 — dforge:judge-opus — executability 12 / coherence 16 / coverage 16 / assumptions 12 (round 1)

## Global Constraints

- All code changes are under `plugins/dforge/` in this repository, plus the Task 1 note under `docs/dforge/notes/`; never edit the installed copy under `/root/.claude/plugins/cache/`.
- Commit as `Darkraise <quangtc94@gmail.com>` (`git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit …`). No `Co-Authored-By`, `Claude-Session`, "Generated with" or other AI attribution in any commit. Subjects follow `<type>(<scope>): <subject>`, type one of feat|fix|docs|style|refactor|test|chore|perf, at most 50 characters, imperative, no period.
- Every test suite, build, network call and long-running CLI command runs under `timeout` (quick local `git` and `tmux` calls are exempt). Shell suites run from the repository root as `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/<name>.test.sh`; the cockpit suite as `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge`. Leave no process running: kill every tmux session you start, by its name only.
- `claude` and `rg` are shell functions on this host: call `/root/.local/bin/claude`, and use `grep` in scripts and steps.
- Shell code must run under bash 3.2+ and Git Bash on Windows CI: no awk interval expressions (`{m,n}`; the host awk is mawk 1.3.4), no `grep -P`, no `mapfile`; expand a possibly empty array as `${a[@]+"${a[@]}"}`; split rows on `\037`, never on a tab.
- New scripts and tests are committed with mode 100644, like `scripts/task-brief` and `tests/fleet.test.sh`, and are run through `bash`.
- `node scripts/validate-repository.mjs` resolves every `dforge:<name>` written anywhere under `plugins/dforge/` (code and tests included) against `skills/` and `agents/`: never write a glob such as `dforge:judge-*`, and no file may name `dforge:drafter-sonnet` before Task 5 creates it.
- Files under `plugins/dforge/agents/` are ASCII only (`tests/fleet.test.sh`).
- `plugins/dforge/skills/using-dforge/SKILL.md` stays at most 5,100 bytes until Task 3 raises the cap in `tests/hook.test.sh` to 5,500, and at most 5,500 after it.
- Do not edit `docs/superpowers/`, historical plans or specs. The spec is read-only.
- Tests stay apart at run time: the cockpit suite runs in its own mock world, and every shell suite works only inside its own `mktemp -d` directory, with `HOME` pointed into it where a script reads dforge settings.

## Contracts

- **Measurement note** `docs/dforge/notes/2026-10-25-drafter-measurement.md` (Task 1) holds, each on its own line at column 0:
  - `**Decision:** typed` or `**Decision:** fork`
  - `**Untyped dispatch resolves to:** <agentType>` — the `agentType` an Agent call with no `subagent_type` recorded.

  Later tasks read the decision with `grep -m1 '^\*\*Decision:\*\*' docs/dforge/notes/2026-10-25-drafter-measurement.md`. Below, **typed branch** means the line reads `typed` and **fork branch** that it reads `fork`.
- **`hooks/cockpit/lib.ts`** (Task 2):
  - `export type SeatSpawn = { subagentType: string; description: string; fork: boolean; model?: string; parentAgentId?: string; workflow?: unknown; isTeammate?: true; resume?: unknown }`
  - `export const FORK_DRAFTING: boolean` — `true` on the fork branch, `false` on the typed branch.
  - `export function seatDenial(spawn: SeatSpawn, isPlanSession: boolean, forkDrafting: boolean): string | null`
  - Fork reason, exactly: `dforge: forks are kept out of dforge sessions. Use dforge:judge-sonnet-high for a read-only check and writing-plans' drafting seat for plan drafting; see using-dforge §Seats.`
  - Untyped reason, exactly: `dforge: name a seat for this dispatch: dforge:judge-sonnet-high or dforge:judge-opus for a review or read-only check, the task's **Implementer:** agent (such as dforge:impl-sonnet-medium) for implementation, or pass an explicit model (model: "sonnet") to general-purpose; see using-dforge §Seats.`
- **Fork description prefix** `Draft plan tasks` — a fork whose `description` starts with it passes the spawn check on the fork branch only.
- **Slice path** `<state>/drafts/<plan basename without .md>/tasks-<A>-<B>.md`, where `<state>` is `dforge_dir state <checkout root>` (`<root>/.dforge`); the session gets it with `bash <plugin-root>/scripts/dforge-path state`.
- **`scripts/draft-pack --join PLAN_FILE`** (Task 4): appends every slice of the plan, in task order, each after one blank line, then deletes them and their directory when empty. Prints `draft-pack: joined tasks <list> from <n> slices into <plan>` or `draft-pack: nothing to join`. Exit 0 joined or nothing to join; 2 bad usage or no such plan; 3 the slices do not cover exactly the Task index tasks the plan has no heading for (a gap, an overlap, a malformed slice name, a slice whose headings are not its range, or slices with nothing missing), the plan byte-identical and the slices kept.
- **Drafter prompt** `skills/writing-plans/references/drafter-prompt.md` (Task 5; its prototype in Task 1 has the same prompt body) with placeholders `[A]`, `[B]`, `[SPEC_PATH]`, `[PLAN_PATH]`, `[SLICE_PATH]`, `[PLUGIN_ROOT]`; the drafter's report is `Status: DONE | NEEDS_CONTEXT | BLOCKED` and one line.
- **Agent** `agents/drafter-sonnet.md` (Task 5, typed branch only): `model: sonnet`, `effort: high`, `tools: Read, Grep, Glob, Bash, Write, Edit`.

## Assumptions (evidence)

- A typed Sonnet drafter given the spec and plan paths drafts about as well as a fork drafter: unverified — Task 1 verifies it (the spec's riskiest assumption).
- An Agent call with no `subagent_type` reaches `agent.spawn` as `general-purpose` or `claude`: `AgentSpawnInput.subagentType` is "the resolved agent type" listing `general-purpose`, `Explore`, plugin agents and `fork` (`plugins/dforge/.claude-plugin/types/claude-code/index.d.ts:285-287`); `claude` is inference from this host's Agent roster, 2026-10-25. Task 1 records the resolved type, and Task 2 adds it to the catch-all list when it is neither.
- `agent.spawn` hooks may return `{ deny }` before calling `next` (`AgentSpawnResult`, `index.d.ts:413-454`), and `fork`, `parentAgentId`, `workflow`, `isTeammate`, `resume` and `model` are on the input (`index.d.ts:254-392`).
- `isPlanSession` turns true only after a dforge skill (Skill tool or typed command) or a dforge agent spawn (`hooks/cockpit/register.tsx:487-492,522-527,734-737`); session-start's injected entry point does not set it.
- Refusals render as `✗  <tool>: <line>` in the cockpit pane (`register.tsx:1957-1963`), and the attribution guard's test finds them with `/✗ Bash: …/` (`tests/cockpit.test.ts:647-659`).
- `scripts/validate-repository.mjs:163-171` resolves `dforge:<name>` against `plugins/dforge/skills/<name>` and `plugins/dforge/agents/<name>.md` in every file under `plugins/dforge/`, hence concrete seat names in deny reasons.
- `plugins/dforge/skills/using-dforge/SKILL.md` is 5,091 bytes (`wc -c`, 2026-10-25) against the 5,100 cap at `tests/hook.test.sh:212-215`; Opus ruled the cap rises to 5,500 in the task that adds the Seats section (ruling recorded in the auto run, 2026-10-25).
- Task 1 joins its slices with `cat` in task order rather than `draft-pack --join`, which Task 4 builds after it; for a header-only plan with exactly covering slices the result is the same file. Opus ruled this (2026-10-25); A9's refusal paths are tested by `tests/draft-pack.test.sh`, not by Task 1.
- Task 4 depends on Task 1 for order only: the spec's Parallel decomposition runs the measurement alone, before every other part.
- The measurement subject is the ui-ux plan at commit `6df85ec4` (the plan's own commit, before `7c820202` started implementing it), so the clone's drafters see the code the original planner saw (`git log --diff-filter=A`, 2026-10-25). That commit has no `.claude/settings.json`, so a nested session with `--setting-sources project,local` loads no plugin.
- Prices, USD per million tokens (platform.claude.com/docs/en/about-claude/pricing, fetched 2026-10-25), as input / 5-minute cache write / 1-hour cache write / cache read / output: Opus 5.5 4 / 5 / 8 / 0.20 / 20; Sonnet 5.5 2 / 2.50 / 4 / 0.10 / 10.
- Transcripts live in `$CLAUDE_CONFIG_DIR/projects/<cwd with every non-alphanumeric replaced by ->/<session>.jsonl`, subagents in `<session>/subagents/agent-*.jsonl` with a `.meta.json` carrying `agentType` and `description`; streamed messages repeat one `message.id`, so usage is deduplicated per id keeping each field's maximum (observed in this repository's transcripts, 2026-10-25). The CLI is 2.1.310 (`claude --version`, 2026-10-25), past the 2.1.302 fork default.
- `scripts/test-all.mjs:64` runs every `plugins/dforge/tests/*.test.sh`, so new suites need no registration.
- writing-plans' `## Task index` heading at `skills/writing-plans/SKILL.md:171` is inside the header template's fence, so the drafting section goes before `## Task Structure` (`SKILL.md:297`), right after the header and Parallel waves sections it builds on.
- Codex lane: `codex-gate` printed `usable=false reason=setting review=false lane=false` (2026-10-25), so the plan is Claude-only.
- An Agent call with `subagent_type: "fork"` spawns a fork: the Agent tool's own description in Claude Code 2.1.310 says "`\"fork\"` forks yourself" (this session's tool list, 2026-10-25). Task 1 Step 4 confirms it from the subagents' `.meta.json` `agentType` before using the run.
- `/root/.claude-alt2` holds a `.credentials.json` (dated 2026-10-23) and a `history.jsonl` last written 2026-10-23 (`ls -la`, `stat`, 2026-10-25); whether its login is still valid shows only at launch, so Task 1 reports BLOCKED rather than fall back to the live `/root/.claude-alt`.
- Planning rulings on spec §4, made here: the nested sessions load no plugin (no `--plugin-dir`), so dforge's own Stop hook and spawn check cannot act inside the measurement and both runs see the same harness; the plan-review metric runs as `claude -p --model opus --effort medium` limited to Read, Grep and Glob, the same model, effort and read-only toolset as `dforge:judge-opus`, because an implementer subagent may not dispatch subagents; the scratch root is a fixed `/tmp` path because an implementer's Bash calls share no variables and no known scratchpad.
- `scripts/draft-pack` relies on `plan_locate` and `_plan_ctx` (`scripts/lib/plan.sh:328-360`), `plan_tasks`, which prints `N<TAB>title` per heading outside fences (`scripts/lib/plan.sh:37-49`), and `dforge_dir state ROOT` → `ROOT/.dforge` (`scripts/lib/dforge-dir.sh:4-12`, sourced through `roots.sh`). Its code and test, extracted from this plan, passed 19 of 19 checks in a scratch copy (2026-10-25).
- Plan review round 1 scored executability 12 and assumptions 12 (borderline): every Important finding is fixed in place (Task 1's fixed paths, tool timeouts, status baseline, fork check and config directory; Task 2's concrete implementer seat; Task 5's single-line test phrase), and the Minor ones are fixed or ruled above, so no second round runs.
- Wave 2's tasks each run in their own worktree and are merged after the wave (`reference/delegated-task.md` §1, last bullet; `reference/parallel-waves.md`), so their commits do not share an index.

## Task index

1. Measure fork and typed Sonnet drafters
2. Deny untyped and fork spawns in the cockpit
3. Add the seat rule and type the code reviewer
4. Add draft-pack --join
5. Add the drafting seat to writing-plans

---

### Task 1: Measure fork and typed Sonnet drafters

**Files:**
- Create: `docs/dforge/notes/2026-10-25-drafter-measurement.md`
- Scratch (never committed, deleted at the end): `/tmp/dforge-measure-2026-10-25/` holding `measure.sh`, `cost.jq`, `cfg`, two clones and the run outputs

**Interfaces:**
- Consumes: nothing.
- Produces: the measurement note (Contracts: Measurement note).

**Items:** 1

**Depends on:** none

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4

Acceptance served: A11, A12, A13 (spec §4). Nothing in this task writes inside `/root/repositories/darkraise-ai-plugins` except the note in Step 9; clones, prompts, scripts and transcripts live under the scratch root and the config directory.

Shell variables do not survive from one Bash call to the next, so every command below spells the scratch root out as `/tmp/dforge-measure-2026-10-25`, called `M` in the prose, and `measure.sh` reads the config directory from `M/cfg`. Run Steps 2, 4, 5 and 6 with the Bash tool's `timeout` at 600000 ms: `setup`, `wait` and `review` run for up to ten minutes.

- [ ] **Step 1: Create the scratch root, record the baseline and write the scripts**

```bash
mkdir /tmp/dforge-measure-2026-10-25
git -C /root/repositories/darkraise-ai-plugins status --short > /tmp/dforge-measure-2026-10-25/status-before.txt
printf '%s\n' /root/.claude-alt2 > /tmp/dforge-measure-2026-10-25/cfg
```

If the `mkdir` fails because the directory exists, a previous attempt left it: kill any `measure-fork` or `measure-typed` tmux session, `rm -rf /tmp/dforge-measure-2026-10-25`, and start this step again.

Write `/tmp/dforge-measure-2026-10-25/cost.jq`:

```jq
def rates: {opus: [4, 5, 8, 0.20, 20], sonnet: [2, 2.5, 4, 0.10, 10]};
map(select(.type == "assistant" and (.message.id? != null) and (.message.usage? != null)))
| group_by(.message.id)
| map({
    model: .[0].message.model,
    in: (map(.message.usage.input_tokens // 0) | max),
    w: (map(.message.usage.cache_creation_input_tokens // 0) | max),
    w1: (map(.message.usage.cache_creation.ephemeral_1h_input_tokens // 0) | max),
    r: (map(.message.usage.cache_read_input_tokens // 0) | max),
    out: (map(.message.usage.output_tokens // 0) | max)
  })
| map(. + {w5: (.w - .w1), family: (if (.model | test("opus")) then "opus" elif (.model | test("sonnet")) then "sonnet" else "other" end)})
| {
    usd: (map(select(.family != "other") | . as $x | rates[$x.family] as $p
          | ($x.in * $p[0] + $x.w5 * $p[1] + $x.w1 * $p[2] + $x.r * $p[3] + $x.out * $p[4]) / 1000000) | add // 0),
    messages: length,
    by_family: (group_by(.family) | map({family: .[0].family, messages: length, output: (map(.out) | add)})),
    unpriced: (map(select(.family == "other")) | map({model, in, out}))
  }
```

Write `/tmp/dforge-measure-2026-10-25/measure.sh`. The two heredocs at `setup` are the prototype drafter prompt and agent; their bodies are the same text Task 5 commits.

````bash
#!/usr/bin/env bash
# The drafter measurement's mechanics. M is the directory this script is in.
set -euo pipefail
M=$(cd "$(dirname "$0")" && pwd)
REPO=/root/repositories/darkraise-ai-plugins
BASE=6df85ec4
PLAN=docs/dforge/plans/2026-10-24-ui-ux-skill.md
SPEC=docs/dforge/specs/2026-10-24-ui-ux-skill-design.md
DRAFTS=.dforge/drafts/2026-10-24-ui-ux-skill
SLICES="1-2 3-4 5-6"
NODEBIN=$(dirname "$(command -v node)")
CFG=$(cat "$M/cfg" 2>/dev/null || true)
slug() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
nested() { # nested CFG CMD... - run CMD in a clean environment
  local cfg=$1; shift
  env -i HOME=/root PATH="/root/.local/bin:$NODEBIN:/usr/local/bin:/usr/bin:/bin" TERM=xterm-256color LANG=C.UTF-8 \
    CLAUDE_CONFIG_DIR="$cfg" IS_SANDBOX=1 "$@"
}

case ${1:-} in
  setup)
    for run in fork typed; do
      c=$M/$run
      timeout 300 git clone -q "$REPO" "$c"
      git -C "$c" checkout -q --detach "$BASE"
      awk '
        { h = $0; sub(/[ \t]+$/, "", h) }
        !on { print; if (h == "## Task index") { on = 1; print "" }; next }
        /^[1-6]\. / { print; next }
        /^### / { exit }
      ' "$c/$PLAN" > "$c/$PLAN.tmp"
      printf '\n---\n' >> "$c/$PLAN.tmp"
      mv "$c/$PLAN.tmp" "$c/$PLAN"
      mkdir -p "$c/$DRAFTS" "$c/.claude/agents"
      printf '{}\n' > "$c/.measure-settings.json"
      cat > "$c/plugins/dforge/skills/writing-plans/references/drafter-prompt.md" <<'PROMPT'
# Drafter Prompt Template

```
Subagent ([SEAT]):
  description: "Draft plan tasks [A]-[B]"
  prompt: |
    You are drafting tasks [A] to [B] of an implementation plan. Other
    drafters are writing the plan's other tasks at the same time.

    **Spec:** [SPEC_PATH]
    **Plan:** [PLAN_PATH] - it holds the header and the Task index only.
    **Your slice:** tasks [A]-[B], titled as the Task index names them.
    **Write to:** [SLICE_PATH]
    **Skill:** [PLUGIN_ROOT]/skills/writing-plans/SKILL.md

    Read the spec, then the plan's header in full: its Global Constraints,
    Contracts, Assumptions and Task index are fixed, and every name one task
    produces and another consumes is in Contracts. Then read the skill's Task
    Structure, Task Right-Sizing and No Placeholders sections; your tasks
    follow them exactly.

    Write your tasks to [SLICE_PATH] as `### Task N: <title>` sections, in
    order, with the titles the Task index gives, and nothing else: no
    header, no index and no assignment lines (`**Implementer:**`,
    `**Evaluation:**`); the session scores the tasks after joining. Each task
    names its exact files, gives the complete code of every step, and ends
    with a check that proves it.

    Read the code your tasks change. You may prototype and run tests, but
    only in a scratch worktree of your own
    (`git worktree add --detach <scratch dir> HEAD`, removed before you
    finish). Write nothing in this checkout except [SLICE_PATH].

    You do not dispatch subagents.

    When a task needs a name, file or format that Contracts does not give
    and another slice could also produce, do not invent it: report
    NEEDS_CONTEXT with the exact contract you need.

    Your final message is your report, and only this:
    - Status: DONE | NEEDS_CONTEXT | BLOCKED
    - One line: the slice path, or what you need.
```
PROMPT
      if [ "$run" = typed ]; then
        cat > "$c/.claude/agents/drafter-sonnet.md" <<'AGENT'
---
name: drafter-sonnet
description: "Plan drafter running Sonnet 5.5 at high effort. Dispatched by dforge's writing-plans to draft one slice of 2-3 consecutive tasks of a plan whose header is written."
model: sonnet
effort: high
tools: Read, Grep, Glob, Bash, Write, Edit
color: cyan
---

You are a plan drafter. Your dispatch prompt names a plan, a slice of its
tasks and the file to write them to. It is your complete instruction set;
follow it exactly.

You run on Sonnet 5.5 at high effort.

You cannot dispatch subagents. You write tasks, never the implementation
itself: any code you run to check a task runs in a scratch worktree of your
own, and the only file you write in the checkout is your slice.

Your final message ends your turn and is read as your report.
AGENT
      fi
      seat=fork; [ "$run" = typed ] && seat=drafter-sonnet
      cat > "$M/prompt-$run.txt" <<EOF
Read $SPEC and $PLAN in full, then plugins/dforge/skills/writing-plans/references/drafter-prompt.md, and nothing else. Then, in a single message, make three Agent tool calls with subagent_type "$seat", described "Draft plan tasks 1-2", "Draft plan tasks 3-4" and "Draft plan tasks 5-6". Each call's prompt is that template's prompt body, from "You are drafting" to its last line, with [A] and [B] set to the slice's first and last task, [SPEC_PATH] to $c/$SPEC, [PLAN_PATH] to $c/$PLAN, [SLICE_PATH] to $c/$DRAFTS/tasks-[A]-[B].md and [PLUGIN_ROOT] to $c/plugins/dforge. Wait for all three reports. Then reply with the single word FINISHED.
EOF
      printf '%s: %s index rows\n' "$run" "$(grep -cE '^[1-6]\. ' "$c/$PLAN")"
    done
    ;;
  launch) # launch RUN
    c=$M/$2
    printf '#!/usr/bin/env bash\ncd %q\n' "$c" > "$M/start-$2.sh"
    printf 'exec env -i HOME=/root PATH=%q TERM=xterm-256color LANG=C.UTF-8 CLAUDE_CONFIG_DIR=%q IS_SANDBOX=1 /root/.local/bin/claude --model opus --effort high --setting-sources project,local --settings %q --dangerously-skip-permissions\n' \
      "/root/.local/bin:$NODEBIN:/usr/local/bin:/usr/bin:/bin" "$CFG" "$c/.measure-settings.json" >> "$M/start-$2.sh"
    timeout 30 tmux new-session -d -s "measure-$2" -x 200 -y 50 "bash $M/start-$2.sh"
    ;;
  screen) tmux capture-pane -p -t "measure-$2" | tail -n 30 ;;
  keys) shift; t=$1; shift; tmux send-keys -t "measure-$t" "$@" ;;
  send) tmux send-keys -t "measure-$2" -l "$(cat "$M/prompt-$2.txt")"; sleep 2; tmux send-keys -t "measure-$2" Enter ;;
  wait) # wait RUN - up to 540 s; exit 0 once three slices exist and FINISHED shows
    d=$M/$2/$DRAFTS; end=$((SECONDS + 540))
    while [ $SECONDS -lt $end ]; do
      n=$(ls "$d"/tasks-*.md 2>/dev/null | wc -l | tr -d ' ')
      if [ "$n" -ge 3 ] && tmux capture-pane -p -t "measure-$2" | grep -q FINISHED; then echo "done: $n slices"; exit 0; fi
      sleep 10
    done
    echo "waiting: $(ls "$d"/tasks-*.md 2>/dev/null | wc -l | tr -d ' ') slices"; exit 1
    ;;
  cost) # cost RUN - the run's newest session and its subagents
    proj=$CFG/projects/$(slug "$M/$2")
    main=$(ls -t "$proj"/*.jsonl | head -n 1); sid=$(basename "$main" .jsonl)
    cat "$main" "$proj/$sid"/subagents/agent-*.jsonl 2>/dev/null | jq -s -f "$M/cost.jq"
    ;;
  agents) # agents RUN - each subagent's agentType and description
    proj=$CFG/projects/$(slug "$M/$2")
    main=$(ls -t "$proj"/*.jsonl | head -n 1); sid=$(basename "$main" .jsonl)
    for m in "$proj/$sid"/subagents/*.meta.json; do
      [ -e "$m" ] && jq -r '[.agentType, .description] | join(" | ")' "$m"
    done
    ;;
  lint) # lint RUN - join the slices in task order, then plan-lint
    c=$M/$2
    for s in $SLICES; do printf '\n' >> "$c/$PLAN"; cat "$c/$DRAFTS/tasks-$s.md" >> "$c/$PLAN"; done
    (cd "$c" && timeout 300 bash "$REPO/plugins/dforge/scripts/plan-lint" "$c/$PLAN") > "$M/lint-$2.txt" 2>&1 || true
    printf 'errors (excluding missing assignment lines): %s\nwarnings: %s\n' \
      "$(grep -vE 'missing \*\*(Implementer|Evaluation):\*\* line' "$M/lint-$2.txt" | grep -c '^ERROR ' || true)" \
      "$(grep -c '^WARN ' "$M/lint-$2.txt" || true)"
    ;;
  review) # review RUN - one Opus plan-review round over the joined plan
    c=$M/$2
    cp "$M/lint-$2.txt" "$c/.dforge/plan-lint.txt"
    awk '/^  prompt: \|/ { on = 1; next } on && /^```/ { exit } on { sub(/^    /, ""); print }' \
      "$c/plugins/dforge/skills/writing-plans/references/plan-reviewer-prompt.md" \
      | sed -e "s|\[PLAN_FILE\]|$c/$PLAN|g" -e "s|\[SPEC_FILE\]|$c/$SPEC|g" \
            -e "s|\[LINT_FILE\]|$c/.dforge/plan-lint.txt|g" -e "s|\[PLUGIN_ROOT\]|$c/plugins/dforge|g" > "$M/review-prompt-$2.txt"
    (cd "$c" && nested "$CFG" timeout 590 /root/.local/bin/claude -p --model opus --effort medium \
      --setting-sources project,local --allowedTools Read Grep Glob -- "$(cat "$M/review-prompt-$2.txt")") > "$M/review-$2.md" 2>&1 || true
    wc -l "$M/review-$2.md"
    ;;
  probe) # probe - which type an Agent call with no subagent_type gets
    c=$M/typed
    (cd "$c" && nested "$CFG" timeout 300 /root/.local/bin/claude -p --model sonnet --setting-sources project,local --dangerously-skip-permissions \
      -- 'Make exactly one Agent tool call with no subagent_type argument, description "Type probe", prompt "Reply OK.". Then reply DONE.') > "$M/probe.txt" 2>&1 || true
    for m in "$CFG/projects/$(slug "$c")"/*/subagents/*.meta.json; do
      [ -e "$m" ] && jq -r 'select(.description == "Type probe") | .agentType' "$m"
    done
    ;;
  *) echo "usage: measure.sh setup|launch RUN|screen RUN|keys RUN KEY...|send RUN|wait RUN|cost RUN|agents RUN|lint RUN|review RUN|probe" >&2; exit 2 ;;
esac
````

- [ ] **Step 2: Build the clones**

Run: `timeout 600 bash /tmp/dforge-measure-2026-10-25/measure.sh setup`
Expected: `fork: 6 index rows` and `typed: 6 index rows`.

- [ ] **Step 3: Note the model setting**

```bash
jq -r '.model // "unset"' /root/.claude-alt2/settings.json > /tmp/dforge-measure-2026-10-25/model-before.txt; cat /tmp/dforge-measure-2026-10-25/model-before.txt
```

The nested sessions run only under `/root/.claude-alt2`, never under the live `/root/.claude-alt`, and credentials are never copied between config directories. If Step 4's screen shows a login prompt or "Not logged in", kill the tmux session and report BLOCKED: `/root/.claude-alt2` needs a login by the owner.

- [ ] **Step 4: Run the fork drafters**

```bash
bash /tmp/dforge-measure-2026-10-25/measure.sh launch fork
bash /tmp/dforge-measure-2026-10-25/measure.sh screen fork
```

Read the screen. Answer a folder-trust question with `bash /tmp/dforge-measure-2026-10-25/measure.sh keys fork Enter`, and a bypass-permissions warning with `bash /tmp/dforge-measure-2026-10-25/measure.sh keys fork Down Enter`; read the screen again after each. Once the input prompt shows, run `bash /tmp/dforge-measure-2026-10-25/measure.sh send fork`, then repeat `bash /tmp/dforge-measure-2026-10-25/measure.sh wait fork` (Bash tool timeout 600000 ms) until it exits 0. If six calls (54 minutes) pass without it, report BLOCKED with the last `screen` output. Answer any question the nested session asks by restating the prompt's instruction; never approve an edit outside the scratch root.

Then confirm the drafters really were forks, record the cost and close the session:

```bash
bash /tmp/dforge-measure-2026-10-25/measure.sh agents fork
bash /tmp/dforge-measure-2026-10-25/measure.sh cost fork > /tmp/dforge-measure-2026-10-25/cost-fork.json; cat /tmp/dforge-measure-2026-10-25/cost-fork.json
timeout 30 tmux kill-session -t measure-fork
```

Expected: `agents` prints three lines whose type is `fork` and whose descriptions start `Draft plan tasks`; any other type means the fork run measured something else, so report BLOCKED with the output. `cost` prints a JSON object with `usd` above 0 and `by_family` naming `opus`.

- [ ] **Step 5: Run the typed drafters**

The same as Step 4 with `typed` in place of `fork`, writing `/tmp/dforge-measure-2026-10-25/cost-typed.json`. Expected: `agents` prints three `drafter-sonnet` lines, and `by_family` names both `opus` (the parent) and `sonnet` (the drafters).

- [ ] **Step 6: Lint and review both joined plans**

```bash
bash /tmp/dforge-measure-2026-10-25/measure.sh lint fork; bash /tmp/dforge-measure-2026-10-25/measure.sh lint typed
```

Then, each as its own Bash call with timeout 600000 ms: `bash /tmp/dforge-measure-2026-10-25/measure.sh review fork` and `bash /tmp/dforge-measure-2026-10-25/measure.sh review typed`.

Count the Critical and Important findings in `/tmp/dforge-measure-2026-10-25/review-fork.md` and `/tmp/dforge-measure-2026-10-25/review-typed.md`, and note each Critical finding's subject.

- [ ] **Step 7: Probe the untyped dispatch**

Run: `bash /tmp/dforge-measure-2026-10-25/measure.sh probe`
Expected: one line, the `agentType` (for example `general-purpose`). If it prints nothing, read `/tmp/dforge-measure-2026-10-25/probe.txt` and the newest `*.meta.json` under `/root/.claude-alt2/projects/<slug of the typed clone path>/` and record what you find.

- [ ] **Step 8: Apply the decision rule**

USD per task is each run's `usd` divided by 6. The typed drafter wins unless its USD per task is higher than the fork's, or its review has a Critical finding whose subject the fork's review does not also raise, or its review has more than one Important finding beyond the fork's count. A tie goes to the typed drafter.

- [ ] **Step 9: Write the note**

Create `docs/dforge/notes/2026-10-25-drafter-measurement.md` with this layout, every bracket filled from Steps 4-8:

```markdown
# Drafter measurement — 2026-10-25

**Decision:** [typed|fork]

**Untyped dispatch resolves to:** [agentType from Step 7]

Subject: tasks 1-6 of `docs/dforge/plans/2026-10-24-ui-ux-skill.md` at `6df85ec4`, trimmed to its header and Task index rows 1-6, drafted as slices 1-2, 3-4 and 5-6. Each parent ran `claude --model opus --effort high`, read the spec, the trimmed plan and the drafter prompt, then dispatched the three drafters in one message. Prices in USD per million tokens (platform.claude.com pricing, 2026-10-25), input / 5-minute write / 1-hour write / cache read / output: Opus 5.5 4 / 5 / 8 / 0.20 / 20; Sonnet 5.5 2 / 2.50 / 4 / 0.10 / 10.

| Run | USD total | USD per task | Lint errors (excluding assignment lines) | Lint warnings | Review Critical | Review Important | Messages |
|---|---|---|---|---|---|---|---|
| fork | [usd] | [usd/6] | [n] | [n] | [n] | [n] | [messages] |
| typed | [usd] | [usd/6] | [n] | [n] | [n] | [n] | [messages] |

Decision rule (spec §4): the typed drafter wins unless it costs more per task than the fork, or its review finds a Critical the fork's does not, or more than one Important finding beyond the fork's; a tie goes to the typed drafter. [One sentence applying it to the numbers above.]

## Notes

- [Each run: NEEDS_CONTEXT or BLOCKED reports, re-dispatches, unpriced messages from `unpriced`, the config directory used.]
- [The Critical findings of each review, one line each.]
```

- [ ] **Step 10: Clean up and confirm nothing else changed**

```bash
timeout 30 tmux kill-session -t measure-fork 2>/dev/null; timeout 30 tmux kill-session -t measure-typed 2>/dev/null
jq -r '.model // "unset"' /root/.claude-alt2/settings.json | diff - /tmp/dforge-measure-2026-10-25/model-before.txt && echo "model unchanged"
git -C /root/repositories/darkraise-ai-plugins status --short | diff /tmp/dforge-measure-2026-10-25/status-before.txt -
```

Expected: `model unchanged` (if not, restore the value from `model-before.txt` and say so in the note), and the status diff shows exactly one added line, `> ?? docs/dforge/notes/2026-10-25-drafter-measurement.md` (A13). Any other difference is a finding for the note; never revert a file this task did not create. Then `rm -rf /tmp/dforge-measure-2026-10-25`.

- [ ] **Step 11: Commit**

```bash
cd /root/repositories/darkraise-ai-plugins
git add docs/dforge/notes/2026-10-25-drafter-measurement.md
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "docs(dforge): record the drafter measurement"
```

### Task 2: Deny untyped and fork spawns in the cockpit

**Files:**
- Modify: `plugins/dforge/hooks/cockpit/lib.ts` (append after `isDforge`, near line 179)
- Modify: `plugins/dforge/hooks/cockpit/register.tsx:487-508` (the `agent.spawn` hook) and its `./lib` import
- Test: `plugins/dforge/tests/cockpit.test.ts` (new `describe('seat check')` after `describe('attribution guard')`, which ends near line 697)

**Interfaces:**
- Consumes: Measurement note (`**Decision:**`, `**Untyped dispatch resolves to:**`).
- Produces: `SeatSpawn`, `FORK_DRAFTING`, `seatDenial`, the two reasons (Contracts).

**Items:** 7, 9

**Depends on:** Task 1

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

Acceptance served: A1, A2, A3, A4, A8.

- [ ] **Step 1: Read the decision**

Run: `grep -m1 '^\*\*Decision:\*\*' docs/dforge/notes/2026-10-25-drafter-measurement.md; grep -m1 '^\*\*Untyped dispatch resolves to:\*\*' docs/dforge/notes/2026-10-25-drafter-measurement.md`

Set `FORK_DRAFTING` below to `true` on the fork branch, `false` on the typed branch. If the resolved type is neither `general-purpose` nor `claude`, add it to `CATCH_ALL` and to the first test's catch-all loop.

- [ ] **Step 2: Write the failing tests**

Add `FORK_DRAFTING` and `seatDenial` to the import from the cockpit lib at the top of `tests/cockpit.test.ts`, then add after the `attribution guard` describe block:

```ts
describe('seat check', () => {
  const base = { subagentType: 'general-purpose', description: 'Look around', fork: false }

  test('denies an untyped dispatch and a fork in a dforge session, and passes typed ones', () => {
    const untyped = seatDenial(base, true, false)
    expect(untyped).toMatch(/dforge:judge-sonnet-high/)
    expect(untyped).toMatch(/\*\*Implementer:\*\*/)
    expect(untyped).toMatch(/dforge:impl-sonnet-medium/)
    expect(untyped).toMatch(/model: "sonnet"/)
    expect(untyped).toMatch(/using-dforge §Seats/)
    for (const subagentType of ['general-purpose', 'claude']) expect(seatDenial({ ...base, subagentType }, true, false)).toBe(untyped)
    expect(seatDenial({ ...base, subagentType: 'fork', fork: true }, true, false)).toMatch(/^dforge: forks are kept out of dforge sessions\./)
    expect(seatDenial({ ...base, model: 'sonnet' }, true, false)).toBeNull()
    expect(seatDenial({ ...base, subagentType: 'dforge:judge-opus' }, true, false)).toBeNull()
    expect(seatDenial({ ...base, subagentType: 'Explore' }, true, false)).toBeNull()
  })

  test('passes everything before a dforge skill runs, and spawns the main loop does not make', () => {
    expect(seatDenial(base, false, false)).toBeNull()
    expect(seatDenial({ ...base, subagentType: 'fork', fork: true }, false, false)).toBeNull()
    expect(seatDenial({ ...base, parentAgentId: 'agent-1' }, true, false)).toBeNull()
    expect(seatDenial({ ...base, workflow: { runId: 'wf_1', agentIndex: 1 } }, true, false)).toBeNull()
    expect(seatDenial({ ...base, isTeammate: true }, true, false)).toBeNull()
    expect(seatDenial({ ...base, resume: { agentId: 'agent-1' } }, true, false)).toBeNull()
  })

  test('admits a drafting fork only when forks draft', () => {
    const fork = { ...base, subagentType: 'fork', fork: true, description: 'Draft plan tasks 1-2' }
    expect(seatDenial(fork, true, true)).toBeNull()
    expect(seatDenial({ ...fork, description: 'Verify the register rows' }, true, true)).toMatch(/^dforge: forks are kept out/)
    expect(seatDenial(fork, true, false)).toMatch(/^dforge: forks are kept out/)
    expect(typeof FORK_DRAFTING).toBe('boolean')
  })

  test('refuses an untyped spawn once a dforge skill ran, and lists the refusal', async ($, on) => {
    world(on, { tokens: 10_000 })
    await $.session.start(START)
    const spawn = { tool_use_id: 'toolu_1', prompt: 'Check the rows', description: 'Check rows', subagentType: 'general-purpose', provider: { plugin: 'engine', tier: 'core' }, parentModel: 'claude-opus-5-5', background: false, fork: false } as never
    expect((await $.agent.spawn(spawn)).deny).toBeUndefined()
    await $.tool.call({ tool: 'Skill', skill: 'dforge:subagent-driven-development' })
    expect((await $.agent.spawn({ ...(spawn as object), tool_use_id: 'toolu_2' } as never)).deny).toMatch(/^dforge: name a seat/)
    expect((await $.agent.spawn({ ...(spawn as object), tool_use_id: 'toolu_3', model: 'sonnet' } as never)).deny).toBeUndefined()
    const ui = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await ui.find({ type: 'Text', text: /✗ Agent: dforge: name a seat/ })).toBeDefined()
  })
})
```

- [ ] **Step 3: Run the suite to verify the new tests fail**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge 2>&1 | tail -n 40`
Expected: FAIL — `seatDenial` and `FORK_DRAFTING` are not exported.

- [ ] **Step 4: Add the check to `hooks/cockpit/lib.ts`**

Append after `isDforge`:

```ts
/** The agent.spawn fields the seat check reads. */
export type SeatSpawn = {
  subagentType: string
  description: string
  fork: boolean
  model?: string
  parentAgentId?: string
  workflow?: unknown
  isTeammate?: true
  resume?: unknown
}

/**
 * Whether a fork described `Draft plan tasks …` may run in a dforge session:
 * docs/dforge/notes/2026-10-25-drafter-measurement.md picked the drafter.
 * Changing it takes a plugin release.
 */
export const FORK_DRAFTING = false

/** The engine's catch-all agent types: what a dispatch naming no type resolves to. */
const CATCH_ALL = ['general-purpose', 'claude']

/**
 * Why a dforge session's main loop may not start this agent, or null. A fork
 * inherits the session's context and model, and an untyped agent given no
 * model inherits the model: the costs typed seats exist to avoid. Workflow
 * agents, teammates, resumes and spawns inside a subagent are not the main
 * loop's dispatch, and nothing is checked before a dforge skill or agent ran.
 */
export function seatDenial(spawn: SeatSpawn, isPlanSession: boolean, forkDrafting: boolean): string | null {
  if (!isPlanSession || spawn.parentAgentId !== undefined || spawn.workflow !== undefined || spawn.isTeammate === true || spawn.resume !== undefined) return null
  if (spawn.fork) {
    if (forkDrafting && spawn.description.startsWith('Draft plan tasks')) return null
    return "dforge: forks are kept out of dforge sessions. Use dforge:judge-sonnet-high for a read-only check and writing-plans' drafting seat for plan drafting; see using-dforge §Seats."
  }
  if (CATCH_ALL.includes(spawn.subagentType) && spawn.model === undefined) {
    return 'dforge: name a seat for this dispatch: dforge:judge-sonnet-high or dforge:judge-opus for a review or read-only check, the task\'s **Implementer:** agent (such as dforge:impl-sonnet-medium) for implementation, or pass an explicit model (model: "sonnet") to general-purpose; see using-dforge §Seats.'
  }
  return null
}
```

Use the `FORK_DRAFTING` value Step 1 chose.

- [ ] **Step 5: Call it from the `agent.spawn` hook**

Add `FORK_DRAFTING` and `seatDenial` to `register.tsx`'s import from `./lib`. In the hook at `register.tsx:487`, replace

```ts
  on('agent.spawn', async ($, e, next) => {
    const started = await next(e)
```

with

```ts
  on('agent.spawn', async ($, e, next) => {
    const denial = seatDenial(e, await read($, isPlanSession), FORK_DRAFTING)
    if (denial !== null) {
      const refusal: CockpitRefusal = { at: await $.clock.now(), tool: 'Agent', line: denial }
      await update($, refusals, list => [...list, refusal].slice(-20))
      return { deny: denial }
    }
    const started = await next(e)
```

Leave the rest of the hook and its `.catch(($, e, next) => next(e))` as they are: a check that throws lets the spawn go ahead.

- [ ] **Step 6: Run the suites to verify they pass**

Run: `env -u CLAUDE_CONFIG_DIR timeout 300 /root/.local/bin/claude plugin test plugins/dforge 2>&1 | tail -n 20`
Expected: PASS, no failures. Then `timeout 300 tsc --noEmit -p plugins/dforge` when `tsc` is on PATH (expected: no output), and `timeout 60 node scripts/validate-repository.mjs` (expected: exit 0).

- [ ] **Step 7: Commit**

```bash
git add plugins/dforge/hooks/cockpit/lib.ts plugins/dforge/hooks/cockpit/register.tsx plugins/dforge/tests/cockpit.test.ts
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "feat(dforge): deny untyped and fork spawns"
```

### Task 3: Add the seat rule and type the code reviewer

**Files:**
- Modify: `plugins/dforge/skills/using-dforge/SKILL.md` (new section between `## Principles` and `## Process Depth`, near line 53)
- Modify: `plugins/dforge/skills/requesting-code-review/SKILL.md:35-44,66-72`
- Modify: `plugins/dforge/skills/requesting-code-review/references/code-reviewer.md:8,22-38,140-145`
- Modify: `plugins/dforge/reference/final-review.md:204-210`
- Modify: `plugins/dforge/tests/hook.test.sh:212-215`
- Create: `plugins/dforge/tests/seats.test.sh`

**Interfaces:**
- Consumes: Measurement note (`**Decision:**`).
- Produces: none.

**Items:** 7, 9

**Depends on:** Task 1

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

Acceptance served: A5, A6.

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/seats.test.sh`:

````bash
#!/usr/bin/env bash
# Every dforge seat is typed. A general-purpose prescription must name its
# model, or it inherits the session's, usually the most expensive. A
# prescription is a `Subagent (general-purpose):` template line, which needs a
# `model:` line before its block's closing fence, or a table row whose second
# cell (a Seats table's Agent column) is `general-purpose`, which needs a
# backticked model alias in the same row.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" 2>/dev/null && echo yes || echo no)" "yes"
}

# unmodelled FILE... - one "file:line" per general-purpose prescription with no model
unmodelled() {
  awk '
    FNR == 1 { if (open) print where; open = 0 }
    open && /^[ \t]+model:/ { open = 0 }
    open && /^```/ { print where; open = 0 }
    /Subagent \(general-purpose\):/ { open = 1; where = FILENAME ":" FNR; next }
    /^\|/ {
      n = split($0, cell, "|")
      agent = cell[3]; gsub(/^[ \t]+/, "", agent); gsub(/[ \t]+$/, "", agent)
      if (agent == "general-purpose" && $0 !~ /`(sonnet|opus|haiku|fable)`/) print FILENAME ":" FNR
    }
    END { if (open) print where }
  ' "$@"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

files=$(find "$P/skills" "$P/reference" -name '*.md' | LC_ALL=C sort)
# shellcheck disable=SC2086
check "no dforge prescription leaves a general-purpose seat unmodelled" "$(unmodelled $files)" ""

cat > "$TMP/bad-block.md" <<'EOF'
```
Subagent (general-purpose):
  description: "Review"
  prompt: |
    Review it.
```
EOF
check "a template block with no model is caught" "$(unmodelled "$TMP/bad-block.md")" "$TMP/bad-block.md:2"

cat > "$TMP/bad-row.md" <<'EOF'
| Seat | Agent | Model argument |
|---|---|---|
| Verifier | general-purpose | None |
EOF
check "a Seats row with no model is caught" "$(unmodelled "$TMP/bad-row.md")" "$TMP/bad-row.md:3"

cat > "$TMP/good.md" <<'EOF'
```
Subagent (general-purpose):
  description: "Re-review"
  model: [MODEL]
  prompt: |
    Re-review it.
```

| Seat | Agent | Model argument |
|---|---|---|
| Scoped re-review | general-purpose | `sonnet` |
EOF
check "a modelled block and row pass" "$(unmodelled "$TMP/good.md")" ""

RCR="$P/skills/requesting-code-review/SKILL.md"
CR="$P/skills/requesting-code-review/references/code-reviewer.md"
UD="$P/skills/using-dforge/SKILL.md"
names "requesting review: the judge seat" "$RCR" 'Dispatch `dforge:judge-opus` as `subagent_type`'
names "requesting review: the diff file comes first" "$RCR" 'git diff -U10 "$BASE_SHA..$HEAD_SHA"'
check "requesting review: no general-purpose seat" "$(grep -c 'general-purpose' "$RCR")" "0"
names "code reviewer: the judge seat" "$CR" 'Subagent (dforge:judge-opus):'
check "code reviewer: no git fallback" "$(grep -c 'derive it yourself' "$CR")" "0"
names "code reviewer: the diff file is required" "$CR" '`[DIFF_FILE]` — REQUIRED'
names "entry point: the Seats section" "$UD" '## Seats'
names "entry point: general-purpose takes a model" "$UD" '`general-purpose` takes an explicit `model`'
names "entry point: read-only checks on a judge" "$UD" 'Read-only checks (register rows, findings, a claim) go to `dforge:judge-sonnet-high`'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
````

- [ ] **Step 2: Run it to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/seats.test.sh`
Expected: FAIL — the first check names `skills/requesting-code-review/references/code-reviewer.md:8`, and the `names` checks fail.

- [ ] **Step 3: Add the Seats section to using-dforge**

Read the decision: `grep -m1 '^\*\*Decision:\*\*' docs/dforge/notes/2026-10-25-drafter-measurement.md`. Insert between the `## Principles` bullets and `## Process Depth` (one blank line on each side):

```markdown
## Seats

Every dispatch names a seat: a `dforge:` agent or a typed built-in (`Explore`); `general-purpose` takes an explicit `model`. No forks. Read-only checks (register rows, findings, a claim) go to `dforge:judge-sonnet-high`, or `dforge:judge-opus` across several files.
```

On the fork branch, write `No forks, except as writing-plans' drafter.` in place of `No forks.`

- [ ] **Step 4: Raise the entry-point cap**

In `plugins/dforge/tests/hook.test.sh`, replace

```bash
# The entry point rides in every session's baseline and shares the hook's
# 10,000-character cap with the compaction snapshot.
check "entry point is at most 5,100 bytes" \
  "$([ "$(wc -c < "$HERE/../skills/using-dforge/SKILL.md")" -le 5100 ] && echo yes || echo no)" "yes"
```

with

```bash
# The entry point rides in every session's baseline and shares the hook's
# 10,000-character cap with the compaction snapshot; 5,500 bytes leaves the
# snapshot about 4,500.
check "entry point is at most 5,500 bytes" \
  "$([ "$(wc -c < "$HERE/../skills/using-dforge/SKILL.md")" -le 5500 ] && echo yes || echo no)" "yes"
```

- [ ] **Step 5: Put requesting-code-review on the judge seat**

In `plugins/dforge/skills/requesting-code-review/SKILL.md`, replace

```markdown
**2. Dispatch code reviewer subagent:**

Dispatch a `general-purpose` subagent, filling the template at [code-reviewer.md](references/code-reviewer.md)
```

with

````markdown
**2. Write the diff file and dispatch the reviewer:**

`scripts/review-package` needs a plan, so outside one write the diff file yourself:

```bash
DIFF_FILE="$(bash <plugin-root>/scripts/dforge-path state)/review-$(git rev-parse --short "$HEAD_SHA").diff"
mkdir -p "$(dirname "$DIFF_FILE")"
{ git log --oneline "$BASE_SHA..$HEAD_SHA"; echo; git diff --stat "$BASE_SHA..$HEAD_SHA"; echo; git diff -U10 "$BASE_SHA..$HEAD_SHA"; } > "$DIFF_FILE"
```

Dispatch `dforge:judge-opus` as `subagent_type`, with no `model` or `effort` argument, filling the template at [code-reviewer.md](references/code-reviewer.md). The judge is read-only and has no shell: the diff file is its view of the change.
````

In the same file replace the placeholder line

```markdown
- `[DIFF_FILE]` - `none`, or a diff file you wrote for the reviewer
```

with

```markdown
- `[DIFF_FILE]` - REQUIRED: the diff file you wrote above
```

and in the Example block replace

```
[Dispatch code reviewer subagent]
  DESCRIPTION: Added verifyIndex() and repairIndex() with 4 issue types
```

with

```
[Write the diff file, then dispatch dforge:judge-opus]
  DESCRIPTION: Added verifyIndex() and repairIndex() with 4 issue types
  DIFF_FILE: .dforge/review-3df7661.diff
```

- [ ] **Step 6: Type the code-reviewer template**

In `plugins/dforge/skills/requesting-code-review/references/code-reviewer.md`, replace the line `Subagent (general-purpose):` with `Subagent (dforge:judge-opus):`. Replace

````
    Read this file first: [DIFF_FILE]
    It holds the commit list, a stat summary and the full diff with context
    for [BASE_SHA]..[HEAD_SHA], and it is your view of the change. Only if
    the line above says "none" derive it yourself:

    ```bash
    git diff --stat [BASE_SHA]..[HEAD_SHA]
    git diff [BASE_SHA]..[HEAD_SHA]
    ```

    ## Read-Only Review

    Your review is read-only on this checkout. Do not mutate the working tree, the index, HEAD, or branch state in any way. Use tools like `git show`, `git diff`, and `git log` to inspect history. If you need a working copy of a different revision, check it out into a separate temporary directory (e.g. `git worktree add /tmp/review-[SHA] [SHA]`) — never move HEAD on this checkout.
````

with

```
    Read this file first: [DIFF_FILE]
    It holds the commit list, a stat summary and the full diff with context
    for [BASE_SHA]..[HEAD_SHA], and it is your view of the change.

    ## Read-Only Review

    Your review is read-only and you have no shell: read the diff file and
    the repository files it touches, and change nothing.
```

and replace the placeholder

```markdown
- `[DIFF_FILE]` — the path `scripts/review-package` printed, or `none` for an
  ad-hoc review outside a plan
```

with

```markdown
- `[DIFF_FILE]` — REQUIRED: the path `scripts/review-package` printed under a
  plan, or the diff file the session wrote outside one
  (requesting-code-review step 2)
```

- [ ] **Step 7: Drop final-review's note about the old seat line**

In `plugins/dforge/reference/final-review.md`, replace

```markdown
   spec and plan paths, and the SHAs to `MERGE_BASE` and `HEAD`. Dispatch the
   `primary` as `subagent_type`; the template's own
   "Subagent (general-purpose)" line is not the seat here. The judge
   agents are read-only and carry no shell: the package file means the
   template's git fallback never applies, and neither do its Read-Only
   Review section's `git show`/`git diff`/`git worktree` instructions. A
   Codex-host plan takes its final-review seat from
```

with

```markdown
   spec and plan paths, and the SHAs to `MERGE_BASE` and `HEAD`. Dispatch the
   `primary` as `subagent_type`, in place of the template's seat line. A
   Codex-host plan takes its final-review seat from
```

- [ ] **Step 8: Run the suites to verify they pass**

Run each:
- `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/seats.test.sh` — expected `0 failed`
- `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/hook.test.sh` — expected `0 failed`
- `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/process-roles.test.sh` — expected `0 failed`
- `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/inline-mode.test.sh` — expected `0 failed`
- `wc -c < plugins/dforge/skills/using-dforge/SKILL.md` — expected at most 5500
- `timeout 60 node scripts/validate-repository.mjs` — expected exit 0

- [ ] **Step 9: Commit**

```bash
git add plugins/dforge/skills/using-dforge/SKILL.md plugins/dforge/skills/requesting-code-review plugins/dforge/reference/final-review.md plugins/dforge/tests/hook.test.sh plugins/dforge/tests/seats.test.sh
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "feat(dforge): type every review and dispatch seat"
```

### Task 4: Add draft-pack --join

**Files:**
- Create: `plugins/dforge/scripts/draft-pack`
- Test: `plugins/dforge/tests/draft-pack.test.sh`

**Interfaces:**
- Consumes: Slice path (Contracts).
- Produces: `scripts/draft-pack --join PLAN_FILE` (Contracts).

**Items:** 1

**Depends on:** Task 1

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 1 = 4

Acceptance served: A9.

- [ ] **Step 1: Write the failing test**

Create `plugins/dforge/tests/draft-pack.test.sh`:

```bash
#!/usr/bin/env bash
# draft-pack --join appends the drafters' slices to a header-only plan in task
# order, and refuses anything that does not cover the missing tasks exactly,
# leaving the plan as it was.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DP="$HERE/../scripts/draft-pack"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
REPO="$TMP/repo"
git init -q -b main "$REPO"
cd "$REPO"
mkdir -p docs
D="$REPO/.dforge/drafts/plan"

header() { # header N - a plan header whose index lists tasks 1..N
  printf '# Demo Implementation Plan\n\n## Task index\n\n'
  i=1; while [ "$i" -le "$1" ]; do printf '%d. Step %d\n' "$i" "$i"; i=$((i + 1)); done
  printf '\n---\n'
}
slice() { # slice A B - a slice file holding tasks A..B
  mkdir -p "$D"
  i=$1; while [ "$i" -le "$2" ]; do printf '### Task %d: Step %d\n\nBody %d.\n' "$i" "$i" "$i"; [ "$i" -lt "$2" ] && printf '\n'; i=$((i + 1)); done > "$D/tasks-$1-$2.md"
}
reset() { rm -rf "$REPO/.dforge"; header "$1" > docs/plan.md; cp docs/plan.md "$TMP/before.md"; }
unchanged() { cmp -s docs/plan.md "$TMP/before.md" && echo yes || echo no; }
run() { out=$(bash "$DP" "$@" 2>&1); code=$?; }

run; check "no arguments: usage" "$code" "2"
run --join; check "--join alone: usage" "$code" "2"
run --join docs/missing.md; check "no such plan: usage" "$code" "2"

reset 4; slice 3 4; slice 1 2
run --join docs/plan.md
check "join: exit 0" "$code" "0"
check "join: the message" "$out" "draft-pack: joined tasks 1 2 3 4 from 2 slices into docs/plan.md"
expected=$( { header 4; printf '\n### Task 1: Step 1\n\nBody 1.\n\n### Task 2: Step 2\n\nBody 2.\n\n### Task 3: Step 3\n\nBody 3.\n\n### Task 4: Step 4\n\nBody 4.\n'; } )
check "join: slices appended in task order" "$(cat docs/plan.md)" "$expected"
check "join: slices deleted" "$([ -e "$D" ] && echo present || echo gone)" "gone"

run --join docs/plan.md
check "nothing missing, no slices: exit 0" "$code" "0"
check "nothing missing, no slices: the message" "$out" "draft-pack: nothing to join"

reset 4; slice 1 2; slice 4 4
run --join docs/plan.md
check "gap: exit 3" "$code" "3"
check "gap: plan unchanged" "$(unchanged)" "yes"
check "gap: slices kept" "$(ls "$D" | tr '\n' ' ')" "tasks-1-2.md tasks-4-4.md "

reset 4; slice 1 2; slice 2 4
run --join docs/plan.md
check "overlap: exit 3" "$code" "3"
check "overlap: plan unchanged" "$(unchanged)" "yes"

reset 2; slice 1 1; mv "$D/tasks-1-1.md" "$D/tasks-1-2.md"
run --join docs/plan.md
check "headings not the range: exit 3" "$code" "3"
check "headings not the range: plan unchanged" "$(unchanged)" "yes"

reset 2; slice 1 2; printf 'x\n' > "$D/tasks-a-b.md"
run --join docs/plan.md
check "malformed slice name: exit 3" "$code" "3"

reset 2; slice 1 2; bash "$DP" --join docs/plan.md >/dev/null 2>&1; cp docs/plan.md "$TMP/before.md"; slice 1 2
run --join docs/plan.md
check "slices with nothing missing: exit 3" "$code" "3"
check "slices with nothing missing: plan unchanged" "$(unchanged)" "yes"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/draft-pack.test.sh`
Expected: FAIL — `scripts/draft-pack` does not exist.

- [ ] **Step 3: Write the script**

Create `plugins/dforge/scripts/draft-pack`:

```bash
#!/usr/bin/env bash
# Join the task slices drafters wrote into a plan that holds its header and
# Task index, so the session never reads them. Slices live at
# <state>/drafts/<plan basename>/tasks-A-B.md and must cover, in order and
# with no gap or overlap, every Task index task the plan has no heading for;
# anything else leaves the plan byte-identical and the slices in place.
#
# Usage: draft-pack --join PLAN_FILE
# Exit: 0 joined, or nothing to join; 2 usage or no such plan; 3 the slices do
# not cover the missing tasks.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/plan.sh"

if [ $# -ne 2 ] || [ "$1" != --join ]; then
  echo "usage: draft-pack --join PLAN_FILE" >&2
  exit 2
fi
plan=$(plan_locate "$2")
[ -f "$plan" ] || { echo "no such plan file: $plan" >&2; exit 2; }
ctx=$(_plan_ctx "$plan")
root=$(git -C "$ctx" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$ctx")
dir="$(dforge_dir state "$root")/drafts/$(basename "$plan" .md)"

refuse() { echo "draft-pack: $1" >&2; exit 3; }
span() { awk -v a="$1" -v b="$2" 'BEGIN { for (i = a; i <= b; i++) printf "%d ", i }'; }

index=$(tr -d '\r' < "$plan" | awk '
  { h = $0; sub(/[ \t]+$/, "", h) }
  h == "## Task index" { on = 1; next }
  on && (/^## / || /^### / || /^---/) { exit }
  on && /^[0-9]+\. / { sub(/\..*/, ""); print }
')
held=$(plan_tasks "$plan" | cut -f1)
missing=$(awk 'NR == FNR { if ($0 != "") held[$0] = 1; next } $0 != "" && !($0 in held) { printf "%d ", $0 }' \
  <(printf '%s\n' "$held") <(printf '%s\n' "$index"))

rows=""
count=0
if [ -d "$dir" ]; then
  for f in "$dir"/tasks-*.md; do
    [ -e "$f" ] || continue
    b=$(basename "$f")
    [[ $b =~ ^tasks-([0-9]+)-([0-9]+)\.md$ ]] || refuse "malformed slice name: $b"
    rows="$rows${BASH_REMATCH[1]}"$'\037'"${BASH_REMATCH[2]}"$'\037'"$f"$'\n'
    count=$((count + 1))
  done
fi

if [ -z "$missing" ] && [ "$count" -eq 0 ]; then echo "draft-pack: nothing to join"; exit 0; fi
[ "$count" -gt 0 ] || refuse "no slices in $dir for tasks ${missing% }"

rows=$(printf '%s' "$rows" | sort -t $'\037' -k1,1n)
covered=""
while IFS=$'\037' read -r a b f; do
  [ "$a" -le "$b" ] || refuse "$(basename "$f") runs backwards"
  got=$(plan_tasks "$f" | cut -f1 | awk '{ printf "%d ", $0 }')
  [ "$got" = "$(span "$a" "$b")" ] || refuse "$(basename "$f") holds tasks [${got% }], not $a-$b"
  covered="$covered$(span "$a" "$b")"
done <<<"$rows"
[ "$covered" = "$missing" ] || refuse "the slices cover [${covered% }], the plan is missing [${missing% }]"

tmp="$plan.join.$$"
trap 'rm -f "$tmp"' EXIT
cp "$plan" "$tmp"
[ -z "$(tail -c 1 "$tmp")" ] || printf '\n' >> "$tmp"
while IFS=$'\037' read -r a b f; do
  printf '\n' >> "$tmp"
  cat "$f" >> "$tmp"
  [ -z "$(tail -c 1 "$tmp")" ] || printf '\n' >> "$tmp"
done <<<"$rows"
mv "$tmp" "$plan"
while IFS=$'\037' read -r a b f; do rm -f "$f"; done <<<"$rows"
rmdir "$dir" 2>/dev/null || true
echo "draft-pack: joined tasks ${covered% } from $count slices into $2"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/draft-pack.test.sh`
Expected: `0 failed`. Also `timeout 60 node scripts/validate-repository.mjs` — expected exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/draft-pack plugins/dforge/tests/draft-pack.test.sh
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "feat(dforge): add draft-pack --join"
```

### Task 5: Add the drafting seat to writing-plans

**Files:**
- Modify: `plugins/dforge/skills/writing-plans/SKILL.md` (new section before `## Task Structure`, line 297)
- Create: `plugins/dforge/skills/writing-plans/references/drafter-prompt.md`
- Create (typed branch only): `plugins/dforge/agents/drafter-sonnet.md`
- Modify (typed branch only): `plugins/dforge/tests/fleet.test.sh`, `plugins/dforge/README.md:63-67`
- Test: `plugins/dforge/tests/process-roles.test.sh` (append before its summary lines)

**Interfaces:**
- Consumes: Measurement note (`**Decision:**`), `scripts/draft-pack --join`, Slice path, Fork description prefix (Contracts).
- Produces: Drafter prompt; Agent `dforge:drafter-sonnet` on the typed branch (Contracts).

**Items:** 1

**Depends on:** Task 1, Task 4

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

Acceptance served: A7, A10, A14.

- [ ] **Step 1: Read the decision**

Run: `grep -m1 '^\*\*Decision:\*\*' docs/dforge/notes/2026-10-25-drafter-measurement.md`
Every step below names what each branch writes.

- [ ] **Step 2: Write the failing tests**

Append to `plugins/dforge/tests/process-roles.test.sh`, before its final `printf` summary:

```bash
WP="$P/skills/writing-plans/SKILL.md"
DPR="$P/skills/writing-plans/references/drafter-prompt.md"
names "drafting: small plans stay in the session" "$WP" 'A plan of 1-3 tasks is drafted in the session.'
names "drafting: slices of 2-3, all at once" "$WP" 'split the index into slices of 2-3 consecutive tasks'
names "drafting: joined without reading" "$WP" 'scripts/draft-pack --join PLAN_FILE'
names "drafting: a changed Contract re-dispatches every slice" "$WP" 're-dispatches every slice: a slice drafted against the old Contract'
names "drafting: Codex drafts in the session" "$WP" 'On a Codex host, draft every task in the session'
names "drafter prompt: the slice path" "$DPR" '**Write to:** [SLICE_PATH]'
names "drafter prompt: the scratch worktree" "$DPR" 'Write nothing in this checkout except [SLICE_PATH].'
```

On the typed branch, also apply Step 6's `tests/fleet.test.sh` edits now (not the agent file), so the fleet test fails first; on the fork branch, leave `tests/fleet.test.sh` unchanged.

- [ ] **Step 3: Run it to verify it fails**

Run: `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/process-roles.test.sh`
Expected: FAIL on the seven new checks.

- [ ] **Step 4: Write the drafter prompt**

Create `plugins/dforge/skills/writing-plans/references/drafter-prompt.md`. On the typed branch `[SEAT LINE]` is `Subagent (dforge:drafter-sonnet):`; on the fork branch it is `Subagent (fork):`.

````markdown
# Drafter Prompt Template

Use this template for each slice writing-plans §Drafting the tasks
dispatches: one dispatch per slice of 2-3 consecutive tasks, every slice in
one message.

```
[SEAT LINE]
  description: "Draft plan tasks [A]-[B]"
  prompt: |
    You are drafting tasks [A] to [B] of an implementation plan. Other
    drafters are writing the plan's other tasks at the same time.

    **Spec:** [SPEC_PATH]
    **Plan:** [PLAN_PATH] - it holds the header and the Task index only.
    **Your slice:** tasks [A]-[B], titled as the Task index names them.
    **Write to:** [SLICE_PATH]
    **Skill:** [PLUGIN_ROOT]/skills/writing-plans/SKILL.md

    Read the spec, then the plan's header in full: its Global Constraints,
    Contracts, Assumptions and Task index are fixed, and every name one task
    produces and another consumes is in Contracts. Then read the skill's Task
    Structure, Task Right-Sizing and No Placeholders sections; your tasks
    follow them exactly.

    Write your tasks to [SLICE_PATH] as `### Task N: <title>` sections, in
    order, with the titles the Task index gives, and nothing else: no
    header, no index and no assignment lines (`**Implementer:**`,
    `**Evaluation:**`); the session scores the tasks after joining. Each task
    names its exact files, gives the complete code of every step, and ends
    with a check that proves it.

    Read the code your tasks change. You may prototype and run tests, but
    only in a scratch worktree of your own
    (`git worktree add --detach <scratch dir> HEAD`, removed before you
    finish). Write nothing in this checkout except [SLICE_PATH].

    You do not dispatch subagents.

    When a task needs a name, file or format that Contracts does not give
    and another slice could also produce, do not invent it: report
    NEEDS_CONTEXT with the exact contract you need.

    Your final message is your report, and only this:
    - Status: DONE | NEEDS_CONTEXT | BLOCKED
    - One line: the slice path, or what you need.
```

**Placeholders:**
- `[A]`, `[B]` — the slice's first and last task numbers.
- `[SPEC_PATH]`, `[PLAN_PATH]` — absolute paths of the spec and the plan.
- `[SLICE_PATH]` — `<state>/drafts/<plan basename without .md>/tasks-[A]-[B].md`,
  with `<state>` from `bash <plugin-root>/scripts/dforge-path state`.
- `[PLUGIN_ROOT]` — the resolved dforge plugin directory.
````

On the fork branch, add after the Placeholders list: `A fork already holds the spec and the header, so its dispatch adds nothing to this prompt: the placeholders filled, under the description above, which the cockpit's spawn check admits.`

- [ ] **Step 5: Add the drafting section to writing-plans**

Insert before `## Task Structure` in `plugins/dforge/skills/writing-plans/SKILL.md`. On the typed branch `[DRAFTER]` is ``one `dforge:drafter-sonnet` ``; on the fork branch it is ``one fork (`subagent_type` `fork`) ``.

```markdown
## Drafting the tasks

A plan of 1-3 tasks is drafted in the session. For 4 or more, write the
header yourself, through the Task index, and save it as the plan file. Then
split the index into slices of 2-3 consecutive tasks and dispatch [DRAFTER]
per slice, every slice in one message, with
[drafter-prompt.md](references/drafter-prompt.md). Each dispatch names the
spec path, the plan path, the slice range and the slice path,
`<state>/drafts/<plan basename>/tasks-A-B.md`, as the template's placeholders; paste nothing else.

- **Contracts settle what slices share.** A drafter that reports
  `NEEDS_CONTEXT` needs a contract: add it to the header and re-dispatch that
  slice. An amendment that changes an existing Contract, rather than adding
  one, re-dispatches every slice: a slice drafted against the old Contract is
  stale, and nothing downstream can tell.
- **Join without reading.** Once every slice reports `DONE`, run
  `scripts/draft-pack --join PLAN_FILE`. It appends the slices in task order
  and deletes them; on exit 3 it names the gap or overlap and leaves the plan
  unchanged. Then continue at Assign an implementer.
- **On a Codex host, draft every task in the session.**
```

- [ ] **Step 6: Add the drafter agent (typed branch only)**

Create `plugins/dforge/agents/drafter-sonnet.md`:

```markdown
---
name: drafter-sonnet
description: "Plan drafter running Sonnet 5.5 at high effort. Dispatched by dforge's writing-plans to draft one slice of 2-3 consecutive tasks of a plan whose header is written."
model: sonnet
effort: high
tools: Read, Grep, Glob, Bash, Write, Edit
color: cyan
---

You are a plan drafter. Your dispatch prompt names a plan, a slice of its
tasks and the file to write them to. It is your complete instruction set;
follow it exactly.

You run on Sonnet 5.5 at high effort.

You cannot dispatch subagents. You write tasks, never the implementation
itself: any code you run to check a task runs in a scratch worktree of your
own, and the only file you write in the checkout is your slice.

Your final message ends your turn and is read as your report.
```

In `plugins/dforge/tests/fleet.test.sh`:
- In the opening comment, replace `The fleet is twenty agents in three classes.` with `The fleet is twenty-one agents in four classes.`, and after the sentence ending `are enforced rather than requested.` add the comment line `# One drafter writes plan slices and may prototype, so it carries Bash, Write`, then `# and Edit, but never Agent: drafters do not spawn subagents.`
- Prepend `drafter-sonnet ` to the `EXPECTED=` list (it sorts first under `LC_ALL=C`).
- Below `ROLE_TOOLS=…` add `DRAFTER_TOOLS="Read, Grep, Glob, Bash, Write, Edit"`.
- Replace `check "fleet contains exactly the 20 expected agents"` with `check "fleet contains exactly the 21 expected agents"`.
- Add this branch before the `*)` branch of the `case "$base" in` block:

```bash
    drafter-*)
      check "$base: carries the drafter toolset" "$(fm "$f" tools)" "$DRAFTER_TOOLS"
      check "$base: runs on sonnet" "$model" "sonnet"
      check "$base: effort is high" "$effort" "high"
      check "$base: preloads no skills" "$(grep -c '^skills:' "$f")" "0"
      ;;
```

- In the `*)` branch, replace `"impl|judge|scout"` with `"impl|judge|scout|drafter"`.

In `plugins/dforge/README.md`, after the sentence that ends `a fact about the registry rather than a request in a prompt.` (line 67), add:

```markdown
One drafter, `drafter-sonnet`, writes a slice of 2-3 tasks of a plan whose
header is written (writing-plans' Drafting the tasks); it may run code in a
scratch worktree of its own, so it carries `Bash`, `Write` and `Edit`, but
never `Agent`.
```

- [ ] **Step 7: Run the suites to verify they pass**

Run each:
- `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/process-roles.test.sh` — expected `0 failed`
- `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/fleet.test.sh` — expected `0 failed` (typed branch: `fleet contains exactly the 21 expected agents`)
- `env -u AR_SESSION -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CONFIG_DIR timeout 600 bash plugins/dforge/tests/seats.test.sh` — expected `0 failed`
- `timeout 60 node scripts/validate-repository.mjs` — expected exit 0
- `timeout 300 /root/.local/bin/claude plugin validate plugins/dforge` — expected to pass

- [ ] **Step 8: Commit**

```bash
git add plugins/dforge/skills/writing-plans plugins/dforge/tests/process-roles.test.sh
git add plugins/dforge/agents/drafter-sonnet.md plugins/dforge/tests/fleet.test.sh plugins/dforge/README.md 2>/dev/null || true
git -c user.name=Darkraise -c user.email=quangtc94@gmail.com commit -m "feat(dforge): draft plan tasks in slices"
```
