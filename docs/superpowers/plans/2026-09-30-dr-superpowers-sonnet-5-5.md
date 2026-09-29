# dr-superpowers on Sonnet 5.5 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Name Sonnet 5.5 in the Sonnet agents with Anthropic's prompt guidance, route score 4 to `impl-sonnet-high`, and remove the four-band inline rule that existed only because total 4 meant Opus.

**Architecture:** Agent prompt edits (Task 1), one assignment-table row plus its test fixtures (Task 2), then the four-band rule removed in three layers — the `plan-lint`/`plan-revise` Opus check (Task 3), `plan_delegated` (Task 4), the prose (Task 5) — and a release (Task 6). Every task leaves all suites green.

**Tech Stack:** Bash scripts and their `*.test.sh` suites, Markdown skills and references, Node repository checks.

**Spec:** `docs/superpowers/specs/2026-09-29-dr-superpowers-sonnet-5-5-design.md`

**Execution:** inline — `claude --model sonnet --effort high` — Tasks 2 and 4 are heavy (2 of 6) and delegated; the highest self-implemented total is 3

**Plan review:** 2026-09-30 — dr-superpowers:judge-opus — executability 17 / coherence 18 / coverage 16 / assumptions 15 (round 1)

## Global Constraints

- Run every command from the repository root `/root/repositories/darkraise-ai-plugins`; paths below are relative to it.
- No agent's `model:` or `effort:` value changes (`tests/fleet.test.sh` ties `effort:` to the name suffix).
- Do not edit completed plans under `docs/superpowers/plans/` or specs under `docs/superpowers/specs/`, and do not touch the untracked `docs/superpowers/notes/2026-09-23-opus-5-5-effort-eval-design.md`.
- Keep the Claude and Codex manifest versions equal (`plugins/dr-superpowers/.claude-plugin/plugin.json`, `plugins/dr-superpowers/.codex-plugin/plugin.json`).
- Commits: `<type>(<scope>): <subject>`, subject ≤ 50 characters, imperative, no period. The commit commands end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; when the model writing the commit is a different one, use the co-author line your harness gives for it instead.
- Bound every test and CLI run with `timeout`; leave no process running.
- English only.

## Contracts

- **Assignment row.** After Task 2, the `assignment` block in `plugins/dr-superpowers/reference/ladder.md` reads `4 impl-sonnet-high`. Tasks 3–5 write their test expectations against it.
- **plan-lint base fixture.** After Task 2, Task 2 of `claude_plan()` in `plugins/dr-superpowers/tests/plan-lint.test.sh` reads `**Implementer:** dr-superpowers:impl-sonnet-high` at total 4, and every `sed` variant that matched `impl-opus-low$` matches `impl-sonnet-high$`. Tasks 3 and 4 edit lines of that file as they read after Task 2.
- **plan-revise check name.** Task 3 names the check `a self-implemented total 4 stays on sonnet`; Task 4 leaves that line alone.
- **`plan_delegated` rows.** After Task 4, `plan_delegated` in `plugins/dr-superpowers/scripts/lib/plan.sh` prints only `N<TAB>heavy` and `N<TAB>executor` rows, never `N<TAB>total 4`.
- **Dispatch header example.** After Task 5, the executing-plans skill shows `` `**Dispatch:** delegated — Task <a> (heavy), Task <b> (executor)` `` and `tests/inline-mode.test.sh` checks that exact string.

## Assumptions (evidence)

- The `sonnet` alias already resolves to Sonnet 5.5: `claude -p --model sonnet ...` on Claude Code 2.1.284, 2026-09-29, reported `modelUsage` `claude-sonnet-5-5` with `contextWindow` 1000000.
- Baseline: all 32 `plugins/dr-superpowers/tests/*.test.sh` suites passed on `5d0d3a0` (2026-09-29 run).
- Every task was rehearsed literally on 2026-09-30: a script extracted this plan's `bash` blocks and ran them in order in a detached worktree of `5d0d3a0`. After each test-edit block the named suite failed (plan-lint 147/13 after Task 2 Step 1, 159/2 after Task 3 Step 1, plan-lib 70/4 after Task 4 Step 1, inline-mode 165/6 after Task 5 Step 1, review-route 229/2 after Task 6 Step 1). After each task all 32 suites passed. At the end, `node scripts/validate-repository.mjs`, the node suites (22/0) and five `claude plugin validate` runs passed. The pass counts in the steps come from that run.
- `rg` on this machine is a shell function that runs `/root/.local/bin/claude` under the name `rg` (`type rg`, 2026-09-29), not a binary, so `node --test tests/*.test.mjs` fails one test on `main` with `rg: command not found`; with a two-line `rg` wrapper on `PATH` (Task 6 Step 5) all 22 pass (run 2026-09-29).
- Codex executor lane is off: `scripts/codex-gate` printed `usable=false reason=plugin-api review=false lane=false` on 2026-09-29, so no task carries an `**Executor:**` line.
- Scores use the installed 1.22.1 ladder, which still maps total 4 to `impl-opus-low`; no task scores 4, so the four-band rule does not affect this plan's execution.
- Departure from spec §3: its three commits become six, one per task, because the ladder shift is split into Tasks 2–5 and each of those commits leaves the suites green on its own. Each commit is one concern.
- Departure from spec §2 wording: the ladder's §What the range actually reaches keeps "cluster in the 0 to 3 band" (where compliant tasks still cluster) and adds that Haiku and Sonnet take totals 0 to 4 and Opus starts at 5, which is the spec's content.
- Shape counting: the test-suite edits inside one task apply one decision (the expectation the task's code change alters) to several suites, so they count as one file shape, per `reference/ladder.md` §Scoring rubric ("Count file shapes, not file instances").

## Task index

1. Tune the Sonnet agents for Sonnet 5.5
2. Route score 4 to impl-sonnet-high
3. Drop the Opus requirement for total 4
4. Stop delegating total-4 tasks
5. Remove the four-band rule from the docs
6. Release 1.23.0

---

### Task 1: Tune the Sonnet agents for Sonnet 5.5

**Files:**
- Modify: `plugins/dr-superpowers/agents/impl-sonnet-low.md`, `impl-sonnet-medium.md`, `impl-sonnet-high.md`, `impl-sonnet-xhigh.md`, `impl-sonnet-max.md`, `judge-sonnet-high.md`, `scout-sonnet.md` (all in `plugins/dr-superpowers/agents/`)
- Modify: `plugins/dr-superpowers/README.md:53`
- Modify: `plugins/dr-superpowers/reference/session-budget.md:16`
- Test: `plugins/dr-superpowers/tests/fleet.test.sh` (unchanged; must stay green)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing later tasks read.

**Items:** 1

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 0 - risk 1 = 3

- [ ] **Step 1: Confirm the starting state**

Run: `rg -c 'Sonnet 5 at' plugins/dr-superpowers/agents`
Expected: seven files, each with count 2.

- [ ] **Step 2: Apply the agent edits**

```bash
python3 - <<'EOF'
P = 'plugins/dr-superpowers/'
STOP = '''
Your final message ends your turn, and the controller reads it as your
report. Do not end a turn with a summary that announces the next step, an
offer to continue, or a list of decisions none of which blocks the rest of
the task: take the step instead, and put any progress note in the same
message as your next tool call. End the turn only when the report contract
is met, or when you are BLOCKED or NEEDS_CONTEXT. This does not relax any
limit the brief sets on risky or destructive actions.

Change only what the brief asks for. Do not add features, tests, files,
docs or refactors the brief does not call for; if you think one would
help, say so in your report instead.
'''
VERIFY = '''
When you change code that can be run, built, or type-checked, run a real
check that exercises the change before reporting DONE: the project's tests,
type-checker, or build, or the changed command itself. A syntax-only check,
or a check command that failed to start, does not count. If no real check can
run here, report DONE_WITH_CONCERNS and name the check you did not run and
why.
'''
REVIEW = '''
When the task is done and its checks pass, write the report and stop. Do not
start extra rounds of review or hardening on your own, and do not launch
reviewer subagents: the controller reviews your work after you report. If
you think a deeper review is worth doing, say so in your report.
'''
for e in ['low', 'medium', 'high', 'xhigh', 'max']:
    p = P + f'agents/impl-sonnet-{e}.md'
    s = open(p).read()
    assert s.count('Sonnet 5 at') == 2, p
    s = s.replace('Sonnet 5 at', 'Sonnet 5.5 at')
    s = s.rstrip('\n') + '\n' + STOP + (VERIFY if e == 'low' else '') + (REVIEW if e in ('xhigh', 'max') else '')
    open(p, 'w').write(s)
for name in ['judge-sonnet-high', 'scout-sonnet']:
    p = P + f'agents/{name}.md'
    s = open(p).read()
    assert s.count('Sonnet 5 at') == 2, p
    open(p, 'w').write(s.replace('Sonnet 5 at', 'Sonnet 5.5 at'))
def rep(p, old, new):
    s = open(P + p).read()
    assert s.count(old) == 1, (p, old[:70])
    open(P + p, 'w').write(s.replace(old, new))
rep('README.md', 'Seven execution implementers - Sonnet 5\nand', 'Seven execution implementers - Sonnet 5.5\nand')
rep('reference/session-budget.md',
    '| Model window | 1,000,000 for Fable 5.1, Opus 5.5 and Sonnet 5; 200,000 for Haiku 4.5 | Claude API model table, cached 2026-06-24; Opus 5.5 from its launch notes |',
    '| Model window | 1,000,000 for Fable 5.1, Opus 5.5 and Sonnet 5.5; 200,000 for Haiku 4.5 | Claude API model table, cached 2026-06-24; Opus 5.5 from its launch notes; Sonnet 5.5 from the model table and a CLI probe, 2026-09-29 |')
EOF
```

- [ ] **Step 3: Verify the edits**

Run: `rg -c 'Sonnet 5 at' plugins/dr-superpowers/agents; rg -l 'Change only what the brief asks for' plugins/dr-superpowers/agents | sort; rg -l 'run a real' plugins/dr-superpowers/agents; rg -l 'do not launch' plugins/dr-superpowers/agents | sort`
Expected: the first command prints nothing; the second lists the five `impl-sonnet-*.md` files; the third lists only `impl-sonnet-low.md`; the fourth lists `impl-sonnet-max.md` and `impl-sonnet-xhigh.md`.

Run: `timeout 300 bash plugins/dr-superpowers/tests/fleet.test.sh | tail -1; timeout 300 bash plugins/dr-superpowers/tests/context-size.test.sh | tail -1`
Expected: `199 passed, 0 failed` and `75 passed, 0 failed`.

- [ ] **Step 4: Commit**

```bash
git add plugins/dr-superpowers/agents plugins/dr-superpowers/README.md plugins/dr-superpowers/reference/session-budget.md
git commit -m "feat(superpowers): tune Sonnet agents for Sonnet 5.5" -m "Claude Code 2.1.284 resolves the \`sonnet\` alias to claude-sonnet-5-5,
so every Sonnet agent already runs Sonnet 5.5; name it.

The Sonnet implementers now carry Anthropic's recommended instructions
for Sonnet 5.5: no early check-ins, no unrequested additions, a real
check at low effort, and no self-started review rounds at xhigh and max.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: Route score 4 to impl-sonnet-high

**Files:**
- Modify: `plugins/dr-superpowers/reference/ladder.md` (assignment block row 4, §The one legacy floor, §Reserve table, §What the range actually reaches)
- Modify: `plugins/dr-superpowers/agents/impl-opus-low.md:3`, `plugins/dr-superpowers/agents/impl-sonnet-high.md:3`
- Test: `plugins/dr-superpowers/tests/plan-lint.test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: the Assignment row and the plan-lint base fixture (see Contracts).

**Items:** 2

**Implementer:** dr-superpowers:impl-opus-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Point the plan-lint fixtures at the new row**

```bash
sed -i 's/impl-opus-low/impl-sonnet-high/g' plugins/dr-superpowers/tests/plan-lint.test.sh
python3 - <<'EOF'
p = 'plugins/dr-superpowers/tests/plan-lint.test.sh'
s = open(p).read()
old1 = "variant v9b.md 's/^\\*\\*Execution:\\*\\* .*/**Execution:** inline — `claude --model opus --effort low` — Task 2 scores 4/'"
new1 = "variant v9b.md 's/^\\*\\*Execution:\\*\\* .*/**Execution:** inline — `claude --model opus --effort high` — Task 2 scores 4/'"
old2 = 'tplan r4.md inline opus low 4 4 4 1 1 1\nlint r4.md\ncheck "three total-4 tasks in six on opus low: exit 0"'
new2 = 'tplan r4.md inline opus high 4 4 4 1 1 1\nlint r4.md\ncheck "three total-4 tasks in six on opus high: exit 0"'
for old, new in ((old1, new1), (old2, new2)):
    assert s.count(old) == 1, old[:70]
    s = s.replace(old, new)
open(p, 'w').write(s)
EOF
```

- [ ] **Step 2: Run the suite to verify it fails**

Run: `timeout 300 bash plugins/dr-superpowers/tests/plan-lint.test.sh | grep '^FAIL'`
Expected: 13 failures, among them `FAIL - clean Claude plan: exit 0` and `FAIL - wrong agent` (the fixture now names `impl-sonnet-high` while the table still says `impl-opus-low`).

- [ ] **Step 3: Change the row and the prose that states it**

```bash
python3 - <<'EOF'
P = 'plugins/dr-superpowers/'
def rep(p, old, new):
    s = open(P + p).read()
    assert s.count(old) == 1, (p, old[:70])
    open(P + p, 'w').write(s.replace(old, new))
L = 'reference/ladder.md'
rep(L, '4 impl-opus-low\n', '4 impl-sonnet-high\n')
rep(L, '''as written. It raises; it never lowers.
''', '''as written. It raises; it never lowers.

### Plans written before 1.23.0

Until 1.23.0 the assignment table sent total 4 to `impl-opus-low`. A plan
written then names that agent for a total-4 task, and `plan-lint` reports the
line as a table mismatch. Change it to `impl-sonnet-high`, or keep Opus with a
human `**Override:**` line below the Evaluation line, which turns the finding
into a warning.
''')
rep(L, 'Nine implementers exist that no score can reach: the `xhigh` and `max` efforts,',
    'Nine implementers exist that neither the assignment table nor the escalation\ntable reaches: the `xhigh` and `max` efforts,')
rep(L, '''cluster in the 0 to 3 band - Haiku and Sonnet. Scores of 4 to 6 are reached
almost entirely through the Risk axis, which is the one axis splitting cannot
reduce.
''', '''cluster in the 0 to 3 band. Scores of 4 to 6 are reached almost entirely
through the Risk axis, which is the one axis splitting cannot reduce. Haiku and
Sonnet take totals 0 to 4; Opus is assigned from 5 up, and otherwise reached by
escalation. Total 4 went to Opus until Sonnet 5.5, whose agentic-coding results
sit close to Opus 5.5's at half the price.
''')
rep('agents/impl-opus-low.md',
    'Dispatched by dr-superpowers for score 4: work whose reducible axes are exhausted and whose risk is real."',
    'Escalation rung for impl-sonnet-low in dr-superpowers: no score assigns it."')
rep('agents/impl-sonnet-high.md',
    'Dispatched by dr-superpowers for score 3: ordinary multi-file work with exact signatures supplied."',
    'Dispatched by dr-superpowers for scores 3 and 4: ordinary multi-file work with exact signatures supplied, and work whose reducible axes are exhausted and whose risk is real."')
EOF
```

- [ ] **Step 4: Run the suites to verify they pass**

Run: `for t in plan-lint ladder fleet review-route; do timeout 300 bash plugins/dr-superpowers/tests/$t.test.sh | tail -1; done`
Expected: `160 passed, 0 failed`, `25 passed, 0 failed`, `199 passed, 0 failed`, `231 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/reference/ladder.md plugins/dr-superpowers/agents/impl-opus-low.md plugins/dr-superpowers/agents/impl-sonnet-high.md plugins/dr-superpowers/tests/plan-lint.test.sh
git commit -m "feat(superpowers): route score 4 to Sonnet 5.5" -m "Sonnet 5.5 scores 70.6% on Terminal-Bench 4.0 against Opus 5.5's
66.4% and 55.5% on CursorBench against 57.8%, at half the price, so a
total-4 task now goes to impl-sonnet-high. impl-opus-low stays on the
escalation ladder above impl-sonnet-low.

A plan written before this change names impl-opus-low for total 4 and
fails plan-lint: change the line to impl-sonnet-high, or add an
Override line to keep Opus.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: Drop the Opus requirement for total 4

**Files:**
- Modify: `plugins/dr-superpowers/scripts/plan-lint` (the R5 inline model check)
- Modify: `plugins/dr-superpowers/scripts/plan-revise` (the recommendation block)
- Test: `plugins/dr-superpowers/tests/plan-lint.test.sh`, `plugins/dr-superpowers/tests/plan-revise.test.sh`

**Interfaces:**
- Consumes: the plan-lint base fixture (see Contracts).
- Produces: the plan-revise check name (see Contracts).

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing tests**

```bash
python3 - <<'EOF'
P = 'plugins/dr-superpowers/'
def rep(p, old, new):
    s = open(P + p).read()
    assert s.count(old) == 1, (p, old[:70])
    open(P + p, 'w').write(s.replace(old, new))
T = 'tests/plan-lint.test.sh'
rep(T, '''has "inline at total 4 needs opus" "$out" "ERROR header: inline execution with a self-implemented task at total 4 needs --model opus"
''', '''lacks "inline at total 4 needs no opus" "$out" "needs --model opus"
has "inline at total 4 needs effort high" "$out" "ERROR header: inline execution needs --effort high or above (effort medium)"
''')
rep(T, '''has "a self-implemented total 4 needs Opus" "$out" "ERROR header: inline execution with a self-implemented task at total 4 needs --model opus"
''', '''check "three self-implemented total-4 tasks on sonnet high: exit 0" "$status" "0"
''')
rep('tests/plan-revise.test.sh',
    'check "a self-implemented four-band needs opus" "$(field model "$out")" "opus"',
    'check "a self-implemented total 4 stays on sonnet" "$(field model "$out")" "sonnet"')
EOF
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `timeout 300 bash plugins/dr-superpowers/tests/plan-lint.test.sh | grep '^FAIL'; timeout 300 bash plugins/dr-superpowers/tests/plan-revise.test.sh | grep '^FAIL'`
Expected: `FAIL - inline at total 4 needs no opus`, `FAIL - three self-implemented total-4 tasks on sonnet high: exit 0`, `FAIL - a self-implemented total 4 stays on sonnet`.

- [ ] **Step 3: Remove the Opus rule**

```bash
python3 - <<'EOF'
P = 'plugins/dr-superpowers/'
def rep(p, old, new):
    s = open(P + p).read()
    assert s.count(old) == 1, (p, old[:70])
    open(P + p, 'w').write(s.replace(old, new))
rep('scripts/plan-lint', '''      say ERROR header "inline execution needs --model sonnet or opus (model $exec_model)"
    elif [ "$self_max" -eq 4 ] && [ "$family" != opus ]; then
      say ERROR header "inline execution with a self-implemented task at total 4 needs --model opus"
    fi''', '''      say ERROR header "inline execution needs --model sonnet or opus (model $exec_model)"
    fi''')
rep('scripts/plan-revise', '''any_four_self=0 max_self=-1
while IFS=$'\\t' read -r tn total trisk; do
  [ -n "$tn" ] || continue
  case "$total" in '-'|'?') continue ;; esac
  case " $deleg_ids " in *" $tn "*) continue ;; esac
  [ "$total" -eq 4 ] && any_four_self=1
  [ "$total" -gt "$max_self" ] && max_self=$total''', '''max_self=-1
while IFS=$'\\t' read -r tn total trisk; do
  [ -n "$tn" ] || continue
  case "$total" in '-'|'?') continue ;; esac
  case " $deleg_ids " in *" $tn "*) continue ;; esac
  [ "$total" -gt "$max_self" ] && max_self=$total''')
rep('scripts/plan-revise', '''  rec_mode=inline
  if [ "$any_four_self" -eq 1 ]; then rec_model=opus; else rec_model=sonnet; fi
''', '''  rec_mode=inline rec_model=sonnet
''')
EOF
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `for t in plan-lint plan-revise inline-mode plan-lib next-step; do timeout 300 bash plugins/dr-superpowers/tests/$t.test.sh | tail -1; done`
Expected: `161 passed, 0 failed`, `85 passed, 0 failed`, `175 passed, 0 failed`, `77 passed, 0 failed`, `149 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/plan-lint plugins/dr-superpowers/scripts/plan-revise plugins/dr-superpowers/tests/plan-lint.test.sh plugins/dr-superpowers/tests/plan-revise.test.sh
git commit -m "feat(superpowers): drop the Opus rule for total 4" -m "Total 4 now runs on impl-sonnet-high, so a self-implemented total-4
task no longer needs an Opus session: plan-lint drops the error and
plan-revise always recommends sonnet for an inline plan. The effort
check still requires high for it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: Stop delegating total-4 tasks

**Files:**
- Modify: `plugins/dr-superpowers/scripts/lib/plan.sh` (`plan_delegated`)
- Modify: `plugins/dr-superpowers/scripts/task-brief` (Mixed mode comment), `plugins/dr-superpowers/scripts/plan-revise` (recommendation comment)
- Test: `plugins/dr-superpowers/tests/plan-lib.test.sh`, `plugins/dr-superpowers/tests/plan-lint.test.sh`, `plugins/dr-superpowers/tests/plan-revise.test.sh`, `plugins/dr-superpowers/tests/inline-mode.test.sh`

**Interfaces:**
- Consumes: the plan-lint base fixture and the plan-revise check name (see Contracts).
- Produces: the `plan_delegated` rows (see Contracts).

**Items:** 2

**Implementer:** dr-superpowers:impl-opus-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

- [ ] **Step 1: Write the failing tests**

```bash
python3 - <<'EOF'
P = 'plugins/dr-superpowers/'
def rep(p, old, new):
    s = open(P + p).read()
    assert s.count(old) == 1, (p, old[:70])
    open(P + p, 'w').write(s.replace(old, new))
T = 'tests/plan-lib.test.sh'
rep(T, '# --- plan_delegated: heavy tasks, and total-4 tasks while a third or fewer ---',
       '# --- plan_delegated: heavy tasks and Executor tasks, never a total-4 task ---')
rep(T, '''deleg_plan "$TMP/d1.md" 1/0 4/2 1/0 1/0 1/0 1/0
check "plan_delegated: one total-4 task in six" "$(deleg "$TMP/d1.md")" "2 total 4|"
deleg_plan "$TMP/d2.md" 4/2 1/0 4/2 1/0 1/0 1/0
check "plan_delegated: two total-4 tasks in six" "$(deleg "$TMP/d2.md")" "1 total 4|3 total 4|"
deleg_plan "$TMP/d3.md" 4/2 4/2 4/2 1/0 1/0 1/0
check "plan_delegated: three total-4 tasks in six are none" "$(deleg "$TMP/d3.md")" ""
deleg_plan "$TMP/d4.md" 5/2 4/2 1/0 4/3 1/0 1/0
check "plan_delegated: heavy and total-4 tasks together" "$(deleg "$TMP/d4.md")" "1 heavy|2 total 4|4 heavy|"
deleg_plan "$TMP/d5.md" 5/2 4/2 4/2 1/0
check "plan_delegated: heavy tasks stay when total-4 tasks pass a third" "$(deleg "$TMP/d5.md")" "1 heavy|"
''', '''deleg_plan "$TMP/d1.md" 1/0 4/2 1/0 1/0 1/0 1/0
check "plan_delegated: a lone total-4 task stays in session" "$(deleg "$TMP/d1.md")" ""
deleg_plan "$TMP/d4.md" 5/2 4/2 1/0 4/3 1/0 1/0
check "plan_delegated: heavy tasks beside a total-4 task" "$(deleg "$TMP/d4.md")" "1 heavy|4 heavy|"
''')
rep(T, 'check "plan_delegated: a split task with a total-4 part" "$(deleg "$TMP/d6.md")" "2 total 4|"',
       'check "plan_delegated: a split task with a total-4 part stays in session" "$(deleg "$TMP/d6.md")" ""')
rep(T, '''# --- the four-band threshold counts the original population ----------------
# Six tasks, three at total 4, one of them offloaded. 3 x 3 > 6, so no
# four-band task delegates. If the offloaded one left the numerator, 3 x 2 <= 6
# would newly delegate the other two - tasks nobody marked for offload.
{ printf '# Threshold Fixture\\n\\n'
  for i in 1 2 3; do
    printf '### Task %s: four band\\n\\n**Implementer:** dr-superpowers:impl-opus-low\\n' "$i"''',
'''# --- only an Executor line delegates a total-4 task ------------------------
# Six tasks, three at total 4, one of them offloaded.
{ printf '# Threshold Fixture\\n\\n'
  for i in 1 2 3; do
    printf '### Task %s: four band\\n\\n**Implementer:** dr-superpowers:impl-sonnet-high\\n' "$i"''')
rep(T, 'check "the offloaded four-band task delegates as executor"', 'check "the offloaded total-4 task delegates as executor"')
rep(T, 'check "the other four-band tasks stay in session"', 'check "the other total-4 tasks stay in session"')
rep(T, '''# The four-band threshold moves in both directions, so both are pinned. With the
# stale line the plan delegates two of three tasks; without it, two of three are
# four-band, 3 x 2 > 3, and nothing is delegated.''', '''# A split task routes on its parts. With the stale parent line Task 1 would be
# heavy and delegated; its parts top out at 4, so nothing is delegated.''')
rep(T, 'check "plan_delegated: the corrected score drops the plan below the four-band third"',
       'check "plan_delegated: the corrected score leaves the split task in session"')
rep(T, '''check "plan_delegated: an unsplit plan is unchanged by the fix" \\
  "$(plan_delegated "$TMP/unsplit.md" | tr '\\t\\n' ' |')" "1 heavy|2 total 4|"''',
'''check "plan_delegated: an unsplit plan is unchanged by the fix" \\
  "$(plan_delegated "$TMP/unsplit.md" | tr '\\t\\n' ' |')" "1 heavy|"''')
L = 'tests/plan-lint.test.sh'
rep(L, '# --- R5 delegation: heavy tasks, and total-4 tasks while a third or fewer ---',
       '# --- R5 delegation: heavy tasks; a total-4 task stays in session ----------')
rep(L, '''has "one total-4 task in six is delegated" "$out" "NOTE header: delegated: Task 2 (total 4)"
lacks "a delegated total-4 task needs no Opus session" "$out" "needs --model opus"
tplan r2.md inline sonnet high 4 1 4 1 1 1
lint r2.md
check "two total-4 tasks in six on sonnet high: exit 0" "$status" "0"
has "two total-4 tasks in six are delegated" "$out" "NOTE header: delegated: Task 1 (total 4), Task 3 (total 4)"
''', '''lacks "one total-4 task in six is not delegated" "$out" "NOTE header"
lacks "a self-implemented total-4 task needs no Opus session" "$out" "needs --model opus"
''')
rep(L, 'lacks "three total-4 tasks in six are not delegated" "$out" "NOTE header"',
       'lacks "three total-4 tasks in six are not delegated either" "$out" "NOTE header"')
rep(L, 'has "heavy and total-4 reasons together" "$out" "NOTE header: delegated: Task 1 (heavy), Task 2 (total 4)"',
       'has "only the heavy task is delegated" "$out" "NOTE header: delegated: Task 1 (heavy)"\nlacks "total 4 is no delegation reason" "$out" "(total 4)"')
rep(L, 'has "delegating a total-4 task raises the effort to high"', 'has "a self-implemented total 4 needs effort high"')
rep(L, '''# Two consequences, both intended: an offloaded task leaves self_max, so a
# total-4 offload no longer forces opus; and any delegation raises the
# required effort to high.''', '''# An offloaded task leaves self_max, and any delegation raises the required
# effort to high.''')
R = 'tests/plan-revise.test.sh'
rep(R, 'check "a four-band within the third is delegated" "$(field delegated "$out")" "2/3"',
       'check "a total-4 task beside a heavy one is not delegated" "$(field delegated "$out")" "1/3"')
rep(R, 'check "four-band past the third is self-implemented" "$(field delegated "$out")" "0/3"',
       'check "total-4 tasks are self-implemented" "$(field delegated "$out")" "0/3"')
I = 'tests/inline-mode.test.sh'
rep(I, '''check "a lone total-4 task in three is delegated" "$(tail -n 1 "$DTMP/hl.md")" "**Dispatch:** delegated — Task 2 (total 4)"''',
       '''check "a lone total-4 task in three is not delegated" "$(grep -c '^\\*\\*Dispatch:\\*\\*' "$DTMP/hl.md")" "0"''')
rep(I, '''check "a delegated total-4 task's second line is the Dispatch line" "$(sed -n 2p "$DTMP/f2.md")" "**Dispatch:** delegated — total 4, risk 2"
brief "$DTMP/one4.md" 1 "$DTMP/f1.md"
check "a light task beside a delegated total-4 task has no Dispatch line" "$(grep -c '^\\*\\*Dispatch:\\*\\*' "$DTMP/f1.md")" "0"
brief --header "$DTMP/one4.md" "$DTMP/fh.md"
check "the header names the total-4 reason" "$(tail -n 1 "$DTMP/fh.md")" "**Dispatch:** delegated — Task 2 (total 4)"
four_plan "$DTMP/three4.md" 4 4 4 1 1 1
brief "$DTMP/three4.md" 1 "$DTMP/t1.md"
check "total-4 tasks past a third get no Dispatch line" "$(grep -c '^\\*\\*Dispatch:\\*\\*' "$DTMP/t1.md")" "0"
brief --header "$DTMP/three4.md" "$DTMP/th.md"
check "total-4 tasks past a third leave no header Dispatch line" "$(grep -c '^\\*\\*Dispatch:\\*\\*' "$DTMP/th.md")" "0"''',
'''check "a total-4 task has no Dispatch line" "$(grep -c '^\\*\\*Dispatch:\\*\\*' "$DTMP/f2.md")" "0"
brief --header "$DTMP/one4.md" "$DTMP/fh.md"
check "a total-4 task leaves no header Dispatch line" "$(grep -c '^\\*\\*Dispatch:\\*\\*' "$DTMP/fh.md")" "0"''')
EOF
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `for t in plan-lib plan-lint plan-revise inline-mode; do timeout 300 bash plugins/dr-superpowers/tests/$t.test.sh | grep '^FAIL'; done`
Expected: failures in each of the four suites, among them `FAIL - plan_delegated: a lone total-4 task stays in session`, `FAIL - one total-4 task in six is not delegated`, `FAIL - a total-4 task beside a heavy one is not delegated` and `FAIL - a total-4 task has no Dispatch line`.

- [ ] **Step 3: Drop the total-4 rows from plan_delegated**

```bash
python3 - <<'EOF'
P = 'plugins/dr-superpowers/'
def rep(p, old, new):
    s = open(P + p).read()
    assert s.count(old) == 1, (p, old[:70])
    open(P + p, 'w').write(s.replace(old, new))
rep('scripts/lib/plan.sh', '''# plan_delegated FILE — the tasks an inline plan delegates, one "N<TAB>heavy",
# "N<TAB>executor" or "N<TAB>total 4" line each, ascending. Heavy tasks always,
# then the tasks an Executor line marks for an external executor. Tasks whose
# highest total is exactly 4 only while they are a third of the plan or fewer:
# past that, one Opus session costs less than a seat for each of them.
plan_delegated() {
  local tasks execs
  tasks=$(plan_tasks "$1" | grep -c . || true)
  execs=$(plan_executors "$1" | cut -f1 | tr '\\n' ' ')
  plan_scores "$1" | awk -F'\\t' -v n="$tasks" -v execs=" $execs" '
    $2 == "-" || $2 == "?" { next }
    # Heavy first: a heavy task is delegated whatever else it is, and the
    # (heavy) label is what the preflight ruling keys on.
    $2 + 0 >= 5 || $3 + 0 == 3 { row[++k] = $1 "\\theavy"; next }
    # A total-4 task counts toward the four-band population whether or not it
    # is offloaded. Removing it from the numerator could flip the threshold
    # and newly delegate other four-band tasks nobody marked.
    $2 + 0 == 4 { four++ }
    index(execs, " " $1 " ") > 0 { row[++k] = $1 "\\texecutor"; next }
    $2 + 0 == 4 { row[++k] = $1 "\\ttotal 4" }
    END {
      for (i = 1; i <= k; i++)
        if (row[i] !~ /\\ttotal 4$/ || 3 * four <= n + 0) print row[i]
    }
  '
}''', '''# plan_delegated FILE — the tasks an inline plan delegates, one "N<TAB>heavy"
# or "N<TAB>executor" line each, ascending: heavy tasks always, then the tasks
# an Executor line marks for an external executor.
plan_delegated() {
  local execs
  execs=$(plan_executors "$1" | cut -f1 | tr '\\n' ' ')
  plan_scores "$1" | awk -F'\\t' -v execs=" $execs" '
    $2 == "-" || $2 == "?" { next }
    # Heavy first: a heavy task is delegated whatever else it is, and the
    # (heavy) label is what the preflight ruling keys on.
    $2 + 0 >= 5 || $3 + 0 == 3 { print $1 "\\theavy"; next }
    index(execs, " " $1 " ") > 0 { print $1 "\\texecutor" }
  '
}''')
rep('scripts/task-brief', '''# Mixed mode: an inline plan delegates the tasks plan_delegated names - heavy
# tasks, four-band tasks under the threshold, and tasks carrying an Executor
# line.''', '''# Mixed mode: an inline plan delegates the tasks plan_delegated names - heavy
# tasks and tasks carrying an Executor line.''')
rep('scripts/plan-revise', '''# It counts tasks, not units. plan_delegated already reduces a split task to its
# highest band and applies the four-band third threshold, so reading it here is
# what keeps this report and the execution skills agreeing.''', '''# It counts tasks, not units. plan_delegated already reduces a split task to its
# highest band, so reading it here is what keeps this report and the execution
# skills agreeing.''')
EOF
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `for t in plan-lib plan-lint plan-revise inline-mode next-step task-state project-status executor-recovery lanes; do timeout 300 bash plugins/dr-superpowers/tests/$t.test.sh | tail -1; done`
Expected: every line reads `<n> passed, 0 failed`; the first four are `74`, `160`, `85` and `172` passed.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/lib/plan.sh plugins/dr-superpowers/scripts/task-brief plugins/dr-superpowers/scripts/plan-revise plugins/dr-superpowers/tests/plan-lib.test.sh plugins/dr-superpowers/tests/plan-lint.test.sh plugins/dr-superpowers/tests/plan-revise.test.sh plugins/dr-superpowers/tests/inline-mode.test.sh
git commit -m "feat(superpowers): stop delegating total-4 tasks" -m "The four-band rule delegated total-4 tasks from an inline plan so they
would not put the session on Opus. Total 4 now runs on
impl-sonnet-high, which the default sonnet high session covers, so
plan_delegated names only heavy tasks and Executor tasks.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: Remove the four-band rule from the docs

**Files:**
- Modify: `plugins/dr-superpowers/skills/writing-plans/SKILL.md` (§Choosing the Execution line)
- Modify: `plugins/dr-superpowers/skills/executing-plans/SKILL.md` (§Why this mode, §Delegated tasks, §Preflight)
- Modify: `plugins/dr-superpowers/skills/using-superpowers/SKILL.md` (§Process Depth)
- Modify: `plugins/dr-superpowers/reference/delegated-task.md` (opening paragraph)
- Modify: `plugins/dr-superpowers/README.md` (§What you get, §Two execution modes)
- Test: `plugins/dr-superpowers/tests/inline-mode.test.sh`

**Interfaces:**
- Consumes: the `plan_delegated` rows (see Contracts).
- Produces: the Dispatch header example (see Contracts).

**Items:** 2

**Implementer:** dr-superpowers:impl-sonnet-high
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 0 = 3

- [ ] **Step 1: Write the failing tests**

```bash
python3 - <<'EOF'
P = 'plugins/dr-superpowers/'
def rep(p, old, new):
    s = open(P + p).read()
    assert s.count(old) == 1, (p, old[:70])
    open(P + p, 'w').write(s.replace(old, new))
I = 'tests/inline-mode.test.sh'
rep(I, '''present "inline mode names all three delegation reasons" "$INLINE" '`**Dispatch:** delegated — Task <a> (heavy), Task <b> (total 4), Task <c> (executor)`'
present "writing-plans defines four-band tasks" "$P/skills/writing-plans/SKILL.md" 'A task is **four-band**'
present "writing-plans delegates total-4 tasks up to a third" "$P/skills/writing-plans/SKILL.md" 'are a third of the plan or fewer (`3 x four-band <= N`)'
present "using-superpowers names total-4 delegation" "$P/skills/using-superpowers/SKILL.md" 'total-4 tasks while they are a third of the plan or fewer'
present "README names both reasons for delegation" "$P/README.md" 'while they are a third of the plan or fewer, which then get an independent'
present "the delegated loop names both reasons" "$P/reference/delegated-task.md" 'or a total-4 task in a plan where those are a third of the tasks or'
''', '''present "inline mode names both delegation reasons" "$INLINE" '`**Dispatch:** delegated — Task <a> (heavy), Task <b> (executor)`'
absent "writing-plans no longer defines four-band tasks" "$P/skills/writing-plans/SKILL.md" 'four-band'
absent "inline mode no longer delegates total-4 tasks" "$INLINE" 'total-4'
absent "using-superpowers no longer delegates total-4 tasks" "$P/skills/using-superpowers/SKILL.md" 'total-4'
absent "README no longer delegates total-4 tasks" "$P/README.md" 'total-4'
absent "the delegated loop no longer delegates total-4 tasks" "$P/reference/delegated-task.md" 'total-4'
''')
rep(I, '''present "the four-band population still counts an offloaded task" "$P/skills/writing-plans/SKILL.md" 'A total-4 task counts toward that third whether or not it is offloaded'
''', '')
EOF
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh | grep '^FAIL'`
Expected: six failures, from `FAIL - inline mode names both delegation reasons` through `FAIL - the delegated loop no longer delegates total-4 tasks`.

- [ ] **Step 3: Rewrite the prose**

```bash
python3 - <<'EOF'
P = 'plugins/dr-superpowers/'
def rep(p, old, new):
    s = open(P + p).read()
    assert s.count(old) == 1, (p, old[:70])
    open(P + p, 'w').write(s.replace(old, new))
rep('skills/writing-plans/SKILL.md', '''A task is **four-band** when it is not heavy and its highest total is exactly 4.
An inline plan delegates its heavy tasks, its four-band tasks while they
are a third of the plan or fewer (`3 x four-band <= N`),
and every task carrying an `**Executor:**` line: each runs through
[delegated-task.md](../../reference/delegated-task.md) with an implementer
subagent — or, for an Executor line, that executor's wrapper — and the full
per-task review. Past that third, one Opus session costs less than a seat per
task, and no four-band task is delegated.
A total-4 task counts toward that third whether or not it is offloaded:
dropping it from the count could flip the threshold and newly delegate
four-band tasks nobody marked. The tasks not delegated are the
**self-implemented** tasks.

- `subagent` when more than half the tasks are heavy:
  `claude --model sonnet --effort high`. The controller owns no judgment calls
  — the ruling seat does — so it needs no stronger model. Four-band tasks never
  count toward this majority.
- Otherwise `inline`, the default. The model is `opus` when a self-implemented
  task totals 4 — so only when four-band tasks exceed a third of the plan and
  at least one of them carries no `**Executor:**` line — and `sonnet`
  otherwise. `<e>` is the assignment-table effort of the highest
  self-implemented total (`impl-haiku` counts as `low`),
  raised to `high` when any task is delegated:
  `claude --model <sonnet|opus> --effort <e>`. When every task is heavy''',
'''An inline plan delegates its heavy tasks
and every task carrying an `**Executor:**` line: each runs through
[delegated-task.md](../../reference/delegated-task.md) with an implementer
subagent — or, for an Executor line, that executor's wrapper — and the full
per-task review. The tasks not delegated are the **self-implemented** tasks.

- `subagent` when more than half the tasks are heavy:
  `claude --model sonnet --effort high`. The controller owns no judgment calls
  — the ruling seat does — so it needs no stronger model.
- Otherwise `inline`, the default, on `sonnet`: the assignment table sends
  every total below 5 to Haiku or Sonnet, and heavy tasks are delegated. `<e>`
  is the assignment-table effort of the highest self-implemented total
  (`impl-haiku` counts as `low`), raised to `high` when any task is delegated:
  `claude --model sonnet --effort <e>`. When every task is heavy''')
E = 'skills/executing-plans/SKILL.md'
rep(E, '''context rebuild than the task itself. The line's model follows the highest
score among the tasks you implement: Sonnet when every one is 3 or less, Opus
when one scores 4; its effort is at least high when the plan delegates.''',
'''context rebuild than the task itself. The line's model is Sonnet, and its
effort follows the highest score among the tasks you implement, at least high
when the plan delegates.''')
rep(E, '''**Delegated tasks.** A delegated task is not yours to implement: every heavy
task, each total-4 task while those are a third of the plan or fewer,
and every task carrying an `**Executor:**` line, so it gets an independent
review without putting the whole session on Opus. An offloaded task is''',
'''**Delegated tasks.** A delegated task is not yours to implement: every heavy
task, and every task carrying an `**Executor:**` line. An offloaded task is''')
rep(E, '`**Dispatch:** delegated — Task <a> (heavy), Task <b> (total 4), Task <c> (executor)`. Run',
       '`**Dispatch:** delegated — Task <a> (heavy), Task <b> (executor)`. Run')
rep(E, 'has no pre-flight scan, even when it delegates total-4 tasks: it is one',
       'has no pre-flight scan, even when it offloads tasks: it is one')
rep('skills/using-superpowers/SKILL.md',
    'an inline plan delegates those, total-4 tasks while they are a third of the plan or fewer, and every task carrying an `**Executor:**` line)',
    'an inline plan delegates those and every task carrying an `**Executor:**` line)')
rep('reference/delegated-task.md', '''`**Dispatch:** delegated`: a heavy task, too large or risky to implement in the
session, or a total-4 task in a plan where those are a third of the tasks or
fewer, delegated so it gets an independent review without putting the whole
session on Opus,
and every task''', '''`**Dispatch:** delegated`: a heavy task, too large or risky to implement in the
session, and every task''')
R = 'README.md'
rep(R, '''and Opus 5.5 at `low`, `medium`, and `high`, plus one Haiku 4.5 agent - are
everything a score can reach.''', '''and Opus 5.5 at `low`, `medium`, and `high`, plus one Haiku 4.5 agent - are
everything the assignment table and the escalation ladder can reach; no score
assigns `impl-opus-low`, which is reached only by escalation.''')
rep(R, '''makes the assignment table stop at 6, which is exactly the seven execution
implementers.''', 'makes the assignment table stop at 6.')
rep(R, '''which are too large or risky to implement in the session, its total-4 tasks
while they are a third of the plan or fewer, which then get an independent
review without putting the whole session on Opus,
and every task''', '''which are too large or risky to implement in the session,
and every task''')
rep(R, '''which both modes share. `plan-lint` requires `--model opus` once a task it
implements scores 4, and `--effort high` once it delegates.''',
'''which both modes share. `plan-lint` requires the session's effort to cover
the highest score it implements, and `--effort high` once it delegates.''')
EOF
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh | tail -1; rg -n 'four-band|total-4 task' plugins/dr-superpowers/skills plugins/dr-superpowers/README.md plugins/dr-superpowers/reference/delegated-task.md`
Expected: `171 passed, 0 failed`; the search prints nothing.

Run: `for t in plugins/dr-superpowers/tests/*.test.sh; do timeout 300 bash "$t" >/dev/null 2>&1 || echo "FAIL $t"; done; echo suites-done`
Expected: only `suites-done`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/skills/writing-plans/SKILL.md plugins/dr-superpowers/skills/executing-plans/SKILL.md plugins/dr-superpowers/skills/using-superpowers/SKILL.md plugins/dr-superpowers/reference/delegated-task.md plugins/dr-superpowers/README.md plugins/dr-superpowers/tests/inline-mode.test.sh
git commit -m "docs(superpowers): drop the four-band rule" -m "An inline plan now delegates only heavy tasks and Executor tasks, and
its session runs on sonnet. The README also states that no score
assigns impl-opus-low any more.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: Release 1.23.0

**Files:**
- Modify: `plugins/dr-superpowers/.claude-plugin/plugin.json`, `plugins/dr-superpowers/.codex-plugin/plugin.json` (`"version"`)
- Test: `plugins/dr-superpowers/tests/review-route.test.sh:583-584`

**Interfaces:**
- Consumes: Tasks 1–5 committed.
- Produces: nothing.

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Pin the new version in the test**

```bash
python3 - <<'EOF'
p = 'plugins/dr-superpowers/tests/review-route.test.sh'
s = open(p).read()
for client in ('Claude', 'Codex'):
    old = f'present "the {client} manifest is 1.22.1"'
    assert s.count(old) == 1, old
    line = next(l for l in s.split('\n') if l.startswith(old))
    s = s.replace(line, line.replace('1.22.1', '1.23.0'))
open(p, 'w').write(s)
EOF
sed -n 583,584p plugins/dr-superpowers/tests/review-route.test.sh
```

Expected output:

```
present "the Claude manifest is 1.23.0" "$P/.claude-plugin/plugin.json" '"version": "1.23.0"'
present "the Codex manifest is 1.23.0" "$P/.codex-plugin/plugin.json" '"version": "1.23.0"'
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh | grep '^FAIL'`
Expected: `FAIL - the Claude manifest is 1.23.0` and `FAIL - the Codex manifest is 1.23.0`.

- [ ] **Step 3: Bump both manifests**

```bash
sed -i 's/"version": "1.22.1"/"version": "1.23.0"/' plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json
grep -n '"version"' plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json
```

Expected: both files show `"version": "1.23.0"`.

- [ ] **Step 4: Run the plugin suites**

Run: `for t in plugins/dr-superpowers/tests/*.test.sh; do timeout 300 bash "$t" >/dev/null 2>&1 || echo "FAIL $t"; done; echo suites-done`
Expected: only `suites-done`.

- [ ] **Step 5: Run the repository checks**

```bash
RGBIN=$(mktemp -d)
printf '#!/usr/bin/env bash\nexec -a rg /root/.local/bin/claude "$@"\n' > "$RGBIN/rg" && chmod +x "$RGBIN/rg"
timeout 120 node scripts/validate-repository.mjs
PATH="$RGBIN:$PATH" timeout 300 node --test tests/*.test.mjs 2>&1 | grep -E '^ℹ (pass|fail)'
for p in . plugins/dr-status plugins/dr-superpowers plugins/dcc-darkraise-ui plugins/dcc-darkraise-win32ui; do timeout 120 claude plugin validate "$p" 2>&1 | tail -1; done
rm -rf "$RGBIN"
```

Expected: `Repository catalogs, manifests, versions, and bundled links are valid.`, `ℹ pass 22`, `ℹ fail 0`, and five `✔ Validation passed` lines. The `rg` wrapper exists because `rg` is a shell function on this machine (see Assumptions).

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "chore(superpowers): release 1.23.0" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
