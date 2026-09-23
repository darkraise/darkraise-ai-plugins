# Native Codex Routing Policy codex-v3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dr-superpowers:subagent-driven-development for `subagent`, dr-superpowers:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the native Codex routing policy `codex-v2` with `codex-v3`, which ranks scores 0–9 on GPT-6 Luna, Sol and Astra, rejects older policies with a conversion path, and ships as dr-superpowers 1.20.0.

**Architecture:** `reference/codex-routing.json` carries the new table, and `scripts/select-native-tier.sh` keeps its logic and names the file's version in its rejection. `scripts/plan-lint` gains one Routing-policy check, and `scripts/plan-revise` refuses Codex-host plans. `reference/native-codex.md` documents the table and the v2 → v3 conversion. A one-time `gpt-6-luna/low` smoke run gates the policy commit.

**Tech Stack:** bash 5, jq, awk, git, Codex CLI 0.155.1 (Task 1 only).

**Spec:** `docs/superpowers/specs/2026-09-23-dr-superpowers-codex-v3-design.md`

**Execution:** inline — `claude --model sonnet --effort high` — 1 of 7 tasks is heavy (Task 2, delegated), none is four-band, and Tasks 3–6 carry an `**Executor:**` line; the session implements Tasks 1 and 7 itself, and effort is high because tasks are delegated.

**Plan review:** 2026-09-23 — codex gpt-6-astra / xhigh — executability 14 / coherence 17 / coverage 18 / assumptions 16 (round 1)

> **External executors:** codex

## Global Constraints

- Native Codex host only. Do not modify any fenced block in `plugins/dr-superpowers/reference/ladder.md`, Claude's unweighted rubric, or `plugins/dr-superpowers/scripts/run-codex-task.sh`.
- Do not edit historical plans or specs under `docs/superpowers/plans/` or `docs/superpowers/specs/`.
- The policy version string is exactly `codex-v3`. The selector and `plan-lint` accept only that version (spec §3 decision 5, hard cut).
- The scoring formula stays `files + spec + coupling + 2 × risk`, with ten ranks 0–9, Rule S unchanged, and review cap 5.
- No test calls a model. Run every test suite, `node scripts/*.mjs` command, `claude plugin validate` and `codex exec` under `timeout`; plain `git`, `jq`, `grep` and `cat` reads need none.
- Both dr-superpowers manifests carry the same version; the target is `1.20.0`.
- Commit messages follow `<type>(superpowers): <subject>`, with a subject of 50 characters or fewer, and end with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- English only in code, comments, docs and tests.

## Contracts

- **Smoke gate** (Task 1 produces; Task 2 consumes): a section headed `## Smoke test — \`gpt-6-luna\`, <YYYY-MM-DD>` appended to `docs/superpowers/notes/2026-09-20-review-routing-calibration.md`, containing a line that begins `Result: PASS`.
- **Policy file** (Task 2 produces; Tasks 3 and 5 consume): `plugins/dr-superpowers/reference/codex-routing.json` has `"version": "codex-v3"`; execution ranks 0 `gpt-6-luna/low`, 1 `gpt-6-luna/medium`, 2 `gpt-6-luna/high`, 3 `gpt-6-sol/low`, 4 `gpt-6-sol/medium`, 5 `gpt-6-sol/high`, 6 `gpt-6-sol/xhigh`, 7 `gpt-6-astra/medium`, 8 `gpt-6-astra/high`, 9 `gpt-6-astra/xhigh`; reserve `gpt-6-astra/max` then `gpt-6-astra/ultra`; `role_floors` implementer 0, scout 4, judge 8; `review_cap` 5.
- **Conversion section name** (Task 3 writes; Tasks 5 and 6 cite in messages): the heading `## Existing plans` in `plugins/dr-superpowers/reference/native-codex.md`, cited as `reference/native-codex.md §Existing plans`.
- **plan-lint Codex fixture** (Task 2 produces; Task 5 consumes): the `codex_plan()` heredoc in `plugins/dr-superpowers/tests/plan-lint.test.sh` carries `Routing policy: codex-v3`, `**Execution:** subagent — codex gpt-6-sol / high — native pair`, and Task 1 `**Implementer:** codex gpt-6-sol / low` with `weighted routing score=3`.
- **Selector rejection text** (Task 3): `unsupported routing policy; conversion required before using codex-v3`.
- **plan-lint policy finding** (Task 5): `ERROR header: Routing policy is <found|missing>, not codex-v3; convert the plan per reference/native-codex.md §Existing plans`.
- **plan-revise refusal** (Task 6): stderr `plan-revise: <PLAN_FILE> is a Codex-host plan; convert it per reference/native-codex.md §Existing plans`, exit 2. Survey row: `plan  <basename>  host=codex  skipped`.

## Assumptions (evidence)

- `~/.codex/models_cache.json` (Codex 0.155.1, fetched 2026-09-23T02:07:21Z) lists `gpt-6-luna` with efforts `low,medium,high,xhigh,max` — `jq -r '.models[] | select(.slug=="gpt-6-luna") | [.supported_reasoning_levels[].effort] | join(",")' ~/.codex/models_cache.json`, run 2026-09-23. Task 1 Step 1 re-checks it.
- GPT-6 Luna has never run here; whether this account can use it is `unverified — Task 1 verifies it`.
- The lane's commits land from a linked worktree under the `workspace-write` sandbox: the 2026-09-23 `gpt-6-sol/low` smoke produced commit `c0fd959` (`docs/superpowers/notes/2026-09-20-review-routing-calibration.md` §Smoke test — `gpt-6-sol`).
- `codex exec` accepts `-m`, `-c key=value`, `-s workspace-write`, `-C DIR` and a prompt on stdin via `-` — `codex exec --help`, Codex 0.155.1, run 2026-09-23.
- The smoke brief and checks are those of `docs/superpowers/plans/2026-09-15-dr-superpowers-review-routing.md:3553-3558` and `:3603`.
- `.superpowers/` is gitignored — `git check-ignore -v .superpowers/x` printed `.gitignore:15:.superpowers/`, 2026-09-23.
- `scripts/plan-amend:49` refuses `Host:` and `Routing policy:` lines, and `plan-lint` is not run during execution (the only callers are writing-plans and revising-plans; `rg plan-lint skills reference`, 2026-09-23).
- `plan-revise` misreads a Codex-host plan: it prints `score=?` and `recommend  execution=inline  model=sonnet  effort=high` (run against the plan-lint Codex fixture, 2026-09-23).
- Every change in Tasks 2–7 was prototyped in a scratch copy of `f883b42` on 2026-09-23. Results: `native-routing` 97/0; `plan-lint` 153/0, where 9 new checks fail against the unchanged script; `plan-revise` 85/0; `node scripts/validate-repository.mjs` valid; `claude plugin validate` passed on the marketplace and all four plugins. `node scripts/test-all.mjs` failed only `tests/ui-discovery.test.mjs` "documented Win32 discovery finds centrally managed versions", a known environmental failure: the child shell's PATH has no `rg`. `test-all` runs the root JavaScript tests as one combined job, reported as `Finished --test tests/repository-layout.test.mjs tests/test-shards.test.mjs tests/ui-discovery.test.mjs in <t>s (exit 1)`, and names each failing test on a line beginning `✖ `.

## Task index

1. Luna smoke gate
2. The codex-v3 policy
3. Selector rejection and plan conversion
4. Version names across skills and references
5. plan-lint Routing-policy check
6. plan-revise refuses Codex-host plans
7. Release 1.20.0

---

### Task 1: Luna smoke gate

**Files:**
- Modify: `docs/superpowers/notes/2026-09-20-review-routing-calibration.md` (append one section)

**Interfaces:**
- Consumes: nothing.
- Produces: a PASS record that Task 2 requires before it starts.

**Items:** 7

**Implementer:** dr-superpowers:impl-haiku
**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0

The session runs this task itself. It spends Codex quota once, so it needs your human partner's explicit yes. It is a one-time acceptance run, not a routing-time probe (spec §7). Run every command from the repository root.

- [ ] **Step 1: Confirm the catalog lists Luna low (no model call)**

```bash
jq -r '.models[] | select(.slug=="gpt-6-luna") | [.supported_reasoning_levels[].effort] | join(",")' ~/.codex/models_cache.json
codex --version
```

Expected: a line containing `low` (on 2026-09-23 it was `low,medium,high,xhigh,max`), then `codex-cli 0.155.1` or later. If `gpt-6-luna` is missing or lacks `low`, stop: write the ledger line `Task 1: BLOCKED — gpt-6-luna/low not advertised — the owner decides` and report it.

- [ ] **Step 2: Ask for approval**

Ask your human partner, in one message: "Task 1 runs one Codex smoke at `gpt-6-luna/low` (the same one-file brief as the 2026-09-23 `gpt-6-sol` smoke) in a disposable worktree. It spends Codex quota once. Run it?" Wait for the answer. On anything but yes, write `Task 1: BLOCKED — smoke run not approved — the owner decides` and stop. On yes, write `Ruling: gpt-6-luna smoke approved — spec §7 gate — none`.

- [ ] **Step 3: Prepare the disposable worktree and brief**

```bash
root=$(git rev-parse --show-toplevel)
smoke="$root/.superpowers/smoke-luna/attempt-1"
mkdir -p "$smoke"
git worktree add --detach "$smoke/wt" HEAD
git -C "$smoke/wt" rev-parse HEAD > "$smoke/base"
cat > "$smoke/brief.md" <<'EOF'
Create the file `smoke.txt` at the repository root containing exactly this one
line, followed by a newline:

codex lane smoke test

Change no other file. Use the commit subject `test(superpowers): add codex smoke file`.
EOF
git -C "$smoke/wt" status --porcelain
```

Expected: `git worktree add` prints `HEAD is now at …`, and the final `status --porcelain` prints nothing. If `.superpowers/smoke-luna` already exists from an earlier session, run Step 8's removal first; never delete a registered worktree with `rm`.

- [ ] **Step 4: Run the smoke**

Run it as a **background** Bash call, then wait for its completion notification:

```bash
root=$(git rev-parse --show-toplevel)
smoke="$root/.superpowers/smoke-luna/attempt-1"
timeout 900 codex exec -m gpt-6-luna -c model_reasoning_effort=low -s workspace-write -C "$smoke/wt" - < "$smoke/brief.md" > "$smoke/out.txt" 2>&1
echo "codex-exit=$?" | tee "$smoke/exit.txt"
```

Expected: `codex-exit=0`. The 900-second bound is the lane's `gpt-6-sol/low` bound (`reference/ladder.md` `codex-timeout` block).

- [ ] **Step 5: Verify the five checks**

```bash
root=$(git rev-parse --show-toplevel)
smoke="$root/.superpowers/smoke-luna/attempt-1"
base=$(cat "$smoke/base")
cat "$smoke/exit.txt"
git -C "$smoke/wt" rev-list --count "$base..HEAD"
git -C "$smoke/wt" log --oneline -1
git -C "$smoke/wt" diff --name-only "$base..HEAD"
cat "$smoke/wt/smoke.txt"; wc -c < "$smoke/wt/smoke.txt"
git -C "$smoke/wt" status --porcelain
```

Expected, in order: `codex-exit=0`; `1`; a line ending `test(superpowers): add codex smoke file`; only `smoke.txt`; `codex lane smoke test` then `22`; nothing.

If any check fails and `$smoke/out.txt` shows the sandbox refusing a write under `.git` (a denied commit also leaves zero commits and a dirty worktree, so several checks fail together), the failure comes from this invocation, not from Luna. Report that to your human partner, quoting the refusal. Only on their explicit yes, run one second attempt that keeps the first attempt's evidence: repeat Steps 3–5 with every `attempt-1` replaced by `attempt-2`, and in Step 4 add `--add-dir "$(git rev-parse --git-common-dir)"` after `-s workspace-write`. Step 6 then records both attempts, each with its own five checks, and the Result is the second attempt's.

- [ ] **Step 6: Record the result**

Append to `docs/superpowers/notes/2026-09-20-review-routing-calibration.md`, filling in the actual values:

```markdown

## Smoke test — `gpt-6-luna`, <YYYY-MM-DD>

Run: <YYYY-MM-DD>, <`codex --version` output>, `gpt-6-luna / low` through
`codex exec` (`run-codex-task.sh` admits only the lane's `gpt-6-sol`),
ChatGPT Pro sign-in, Linux, disposable linked worktree. Same brief and checks
as the `gpt-6-sol` run above.

- codex exec exit: <n>
- Commit: `<the log line>`, <count> commit(s)
- File content correct: <yes|no> — `<content>`, <bytes> bytes including the newline
- Write set honoured: <yes|no> — `<the diff --name-only output>`
- Worktree clean afterwards: <yes|no>

Result: <PASS|FAIL> — <one line>. This gates the codex-v3 policy commit
(spec `docs/superpowers/specs/2026-09-23-dr-superpowers-codex-v3-design.md` §7).
It shows Luna is reachable and follows a write set; it says nothing about
output quality at ranks 0–2.
```

- [ ] **Step 7: Commit, or stop on FAIL**

```bash
git add docs/superpowers/notes/2026-09-20-review-routing-calibration.md
git commit -m "docs(superpowers): record the gpt-6-luna smoke test" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

On FAIL, commit the record anyway, keep the worktree for inspection, write `Task 1: BLOCKED — gpt-6-luna smoke failed — <the failing check>; the owner decides`, report it, and do not start Task 2.

- [ ] **Step 8: Remove the disposable worktree (PASS only)**

```bash
root=$(git rev-parse --show-toplevel)
for wt in "$root"/.superpowers/smoke-luna/attempt-*/wt; do [ -d "$wt" ] && git worktree remove --force "$wt"; done
rm -rf "$root/.superpowers/smoke-luna"
git worktree list
```

Expected: `git worktree list` no longer shows `smoke-luna`.

### Task 2: The codex-v3 policy

**Files:**
- Modify: `plugins/dr-superpowers/reference/codex-routing.json` (whole file)
- Modify: `plugins/dr-superpowers/reference/native-codex.md:22`, `:28`, `:37-44`, `:120`, `:124`, `:129`, `:157-161`, `:196`
- Test: `plugins/dr-superpowers/tests/native-routing.test.sh:10-15`, `:34-41`, `:56`, `:63-65`, `:67`, `:69`, `:105`
- Test: `plugins/dr-superpowers/tests/plan-lint.test.sh:117`, `:123`, `:148`, `:407`, `:410`

**Interfaces:**
- Consumes: Smoke gate (Contracts).
- Produces: the Policy file and the plan-lint Codex fixture (Contracts).

**Items:** 1, 2, 3

**Implementer:** dr-superpowers:impl-opus-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 2 = 5

Before starting, confirm the Smoke gate (Contracts) holds:

```bash
awk '/^## Smoke test — `gpt-6-luna`/ { on = 1 } on && /^Result: PASS/ { print "gate: pass"; exit }' docs/superpowers/notes/2026-09-20-review-routing-calibration.md
```

Expected: `gate: pass`. Anything else: stop with `BLOCKED — Task 1 smoke gate has not passed`.

- [ ] **Step 1: Update the selector tests to v3**

In `plugins/dr-superpowers/tests/native-routing.test.sh`, replace the request fixture's lines 10–15 (from `{"policy":"codex-v2",…` through `{"model":"gpt-6-astra","effort":"high"},{"model":"gpt-6-astra","effort":"xhigh"},`) with:

```text
{"policy":"codex-v3","operation":"assign","role":"implementer","assignment_source":"rubric",
 "axes":{"files":0,"spec":0,"coupling":0,"risk":0},
 "available_pairs":[{"model":"gpt-6-luna","effort":"low"},{"model":"gpt-6-luna","effort":"medium"},{"model":"gpt-6-luna","effort":"high"},
 {"model":"gpt-6-sol","effort":"low"},{"model":"gpt-6-sol","effort":"medium"},{"model":"gpt-6-sol","effort":"high"},{"model":"gpt-6-sol","effort":"xhigh"},
 {"model":"gpt-6-astra","effort":"medium"},{"model":"gpt-6-astra","effort":"high"},{"model":"gpt-6-astra","effort":"xhigh"},
```

The next line (`{"model":"gpt-6-astra","effort":"max"},{"model":"gpt-6-astra","effort":"ultra"}],`) stays.

Replace the score table between `done <<'CASES'` and `CASES` with:

```text
0 0 0 0 0 gpt-6-luna low
1 1 0 0 0 gpt-6-luna medium
2 1 1 0 0 gpt-6-luna high
3 1 1 1 0 gpt-6-sol low
4 1 1 0 1 gpt-6-sol medium
5 1 1 1 1 gpt-6-sol high
6 1 1 0 2 gpt-6-sol xhigh
7 1 1 1 2 gpt-6-astra medium
8 1 1 0 3 gpt-6-astra high
9 1 1 1 3 gpt-6-astra xhigh
```

Directly below `expect_error 'old policy' '.policy="codex-v1"' 'conversion required'`, add:

```bash
expect_error 'previous policy' '.policy="codex-v2"' 'conversion required'
```

Replace the three lines beginning `decision 'missing Terra effort promotes within Terra'`, `decision 'missing Terra promotes to Sol low'` and `decision 'initial assignment neither demotes nor enters reserve'` with:

```bash
decision 'missing Luna effort promotes within Luna' '.axes={files:1,spec:0,coupling:0,risk:0} | .available_pairs=[{model:"gpt-6-luna",effort:"high"}]' '[.score,.rank,.model,.effort]' '[1,2,"gpt-6-luna","high"]'
decision 'missing Luna promotes to Sol low' '.axes={files:1,spec:1,coupling:0,risk:0} | .available_pairs |= map(select(.model != "gpt-6-luna"))' '[.score,.rank,.model,.effort]' '[2,3,"gpt-6-sol","low"]'
decision 'initial assignment neither demotes nor enters reserve' '.axes={files:1,spec:1,coupling:1,risk:3} | .available_pairs=[{model:"gpt-6-sol",effort:"xhigh"},{model:"gpt-6-astra",effort:"max"}]' '.action' '"blocked"'
```

Replace the line beginning `decision 'scout retains Sol medium floor'` with:

```bash
decision 'scout retains Sol medium floor' '.role="scout"' '[.rank,.model,.effort]' '[4,"gpt-6-sol","medium"]'
```

Replace the line beginning `decision 'judge never drops below its floor'` with:

```bash
decision 'judge never drops below its floor' '.role="judge" | .available_pairs=[{model:"gpt-6-sol",effort:"xhigh"}]' '.action' '"blocked"'
```

In the last `check 'documented request executes with the stated assignment'` line, change the expected value `'["dispatch",7,7,"gpt-5.6-sol","high"]'` to `'["dispatch",7,7,"gpt-6-astra","medium"]'`.

- [ ] **Step 2: Update the plan-lint Codex fixture to v3 pairs**

In `plugins/dr-superpowers/tests/plan-lint.test.sh`, inside `codex_plan()`:
- `Routing policy: codex-v2` becomes `Routing policy: codex-v3`
- `**Execution:** subagent — codex gpt-5.6-sol / high — native pair` becomes `**Execution:** subagent — codex gpt-6-sol / high — native pair`
- `**Implementer:** codex gpt-5.6-terra / medium` becomes `**Implementer:** codex gpt-6-sol / low`

In the `# --- per task, Codex ---` block:
- `codex_plan | sed 's#gpt-5.6-terra / medium#gpt-5.6-terra / low#' > c2.md` becomes `codex_plan | sed 's#gpt-6-sol / low#gpt-6-luna / high#' > c2.md`
- `codex_plan | sed 's#gpt-5.6-terra / medium#gpt-5.6-terra / high#' > c3.md` becomes `codex_plan | sed 's#gpt-6-sol / low#gpt-6-sol / medium#' > c3.md`

The expected messages (`Implementer rank 2 is below routing score 3`, `Implementer rank 4 is above routing score 3 (promotion)`) stay as they are.

- [ ] **Step 3: Run the tests to verify they fail**

```bash
timeout 120 bash plugins/dr-superpowers/tests/native-routing.test.sh | tail -1
timeout 300 bash plugins/dr-superpowers/tests/plan-lint.test.sh | tail -1
```

Expected: both summaries report failures (non-zero `failed`), because the policy file still names v2 pairs.

- [ ] **Step 4: Write the policy file**

Replace the whole of `plugins/dr-superpowers/reference/codex-routing.json` with:

```json
{
  "version": "codex-v3",
  "execution": [
    {"rank":0,"model":"gpt-6-luna","effort":"low"},
    {"rank":1,"model":"gpt-6-luna","effort":"medium"},
    {"rank":2,"model":"gpt-6-luna","effort":"high"},
    {"rank":3,"model":"gpt-6-sol","effort":"low"},
    {"rank":4,"model":"gpt-6-sol","effort":"medium"},
    {"rank":5,"model":"gpt-6-sol","effort":"high"},
    {"rank":6,"model":"gpt-6-sol","effort":"xhigh"},
    {"rank":7,"model":"gpt-6-astra","effort":"medium"},
    {"rank":8,"model":"gpt-6-astra","effort":"high"},
    {"rank":9,"model":"gpt-6-astra","effort":"xhigh"}
  ],
  "reserve": [
    {"model":"gpt-6-astra","effort":"max"},
    {"model":"gpt-6-astra","effort":"ultra"}
  ],
  "role_floors": {"implementer":0,"scout":4,"judge":8},
  "review_cap": 5
}
```

- [ ] **Step 5: Update native-codex.md's policy description**

In `plugins/dr-superpowers/reference/native-codex.md`, make these exact replacements, each of which matches exactly once:

1. `New plans contain \`Host: codex\` and \`Routing policy: codex-v2\`.` → `New plans contain \`Host: codex\` and \`Routing policy: codex-v3\`.`
2. `**Implementer:** codex gpt-5.6-sol / high` → `**Implementer:** codex gpt-6-astra / medium`
3. The eight table rows from `| 0 | gpt-5.6-luna | low |` through `| 7 | gpt-5.6-sol | high |` → 

```text
| 0 | gpt-6-luna | low |
| 1 | gpt-6-luna | medium |
| 2 | gpt-6-luna | high |
| 3 | gpt-6-sol | low |
| 4 | gpt-6-sol | medium |
| 5 | gpt-6-sol | high |
| 6 | gpt-6-sol | xhigh |
| 7 | gpt-6-astra | medium |
```

   (rows 8 and 9, `gpt-6-astra` high and xhigh, stay).
4. `This complete example dispatches Sol high when that is the allowed advertised pair:` → `This complete example dispatches Astra medium when that is the allowed advertised pair:`
5. In the JSON example: `"policy": "codex-v2",` → `"policy": "codex-v3",` and `"available_pairs": [{"model": "gpt-5.6-sol", "effort": "high"}],` → `"available_pairs": [{"model": "gpt-6-astra", "effort": "medium"}],`
6. After the paragraph ending `Transport retries reuse their exact recorded pair and do not reset rank history,\nsplit budget, or the five-round cap.`, insert a blank line and this paragraph:

```text
An ultra implementer may run subagents in parallel inside its own task: OpenAI
documents ultra as using subagents for separate parts of a complex task. The
task's approved write set, the before/after snapshot and the review still apply
to the task as a whole. Only implementers reach the reserve, so the
no-delegation instruction for scouts and judges is unaffected.
```

7. `Scouts start at rank 6 (Sol medium) or above, judges at rank 8 (Astra high) or above.` → `Scouts start at rank 4 (Sol medium) or above, judges at rank 8 (Astra high) or above.`

- [ ] **Step 6: Run the tests to verify they pass**

```bash
timeout 120 bash plugins/dr-superpowers/tests/native-routing.test.sh | tail -1
timeout 300 bash plugins/dr-superpowers/tests/plan-lint.test.sh | tail -1
timeout 300 bash plugins/dr-superpowers/tests/next-step.test.sh | tail -1
grep -c 'gpt-5\.6-terra' plugins/dr-superpowers/reference/native-codex.md plugins/dr-superpowers/reference/codex-routing.json
```

Expected: `88 passed, 0 failed`; `142 passed, 0 failed`; a `0 failed` summary; both grep counts end in `:0`.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/reference/codex-routing.json plugins/dr-superpowers/reference/native-codex.md plugins/dr-superpowers/tests/native-routing.test.sh plugins/dr-superpowers/tests/plan-lint.test.sh
git commit -m "feat(superpowers): rank native Codex on GPT-6" -m "codex-v3 ranks scores 0-9 on gpt-6-luna, gpt-6-sol and gpt-6-astra
and drops Terra. The reserve stays Astra max then ultra; scouts keep Sol
medium, now rank 4; judges keep Astra high at rank 8." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: Selector rejection and plan conversion

**Files:**
- Modify: `plugins/dr-superpowers/scripts/select-native-tier.sh:19`
- Modify: `plugins/dr-superpowers/reference/native-codex.md` (the `## Existing plans` section, whole)
- Test: `plugins/dr-superpowers/tests/native-routing.test.sh` (one line after `expect_error 'previous policy'`; a needle block before the `awk '/^```json$/` line)

**Interfaces:**
- Consumes: Policy file (Contracts).
- Produces: Selector rejection text; Conversion section name (Contracts).

**Items:** 4, 5

**Implementer:** dr-superpowers:impl-sonnet-high
**Executor:** codex gpt-6-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing test**

In `plugins/dr-superpowers/tests/native-routing.test.sh`, directly below the line `expect_error 'previous policy' '.policy="codex-v2"' 'conversion required'`, add:

```bash
expect_error 'rejection names the current policy' '.policy="codex-v2"' 'conversion required before using codex-v3'
```

Then, directly above the line that begins `awk '/^```json$/`, add this block. It pins each conversion rule, so deleting one from §Existing plans fails the suite. The extraction skips fenced lines, because the section's own examples contain a `## ` line:

```bash
existing="$(awk '/^## Existing plans$/ { on = 1; next } /^```/ { fence = !fence } on && !fence && /^## / { exit } on' "$HERE/../reference/native-codex.md")"
while IFS= read -r needle; do
  check "Existing plans keeps: $needle" "$(grep -qF -- "$needle" <<< "$existing" && echo yes || echo no)" yes
done <<'NEEDLES'
Obtain approval
human pin stays verbatim
4     gpt-5.6-terra / high
## Policy conversion
Ruling: policy conversion codex-v2 -> codex-v3
consumed split/review budgets
caught mid-escalation
NEEDLES
```

The third needle has five spaces between `4` and `gpt-5.6-terra`, matching the v2 table in Step 4.

- [ ] **Step 2: Run it to verify it fails**

```bash
timeout 120 bash plugins/dr-superpowers/tests/native-routing.test.sh | grep -E '^FAIL|passed'
```

Expected: six `FAIL` lines — `rejection names the current policy explains the failure`, and `Existing plans keeps:` for `human pin stays verbatim`, `4     gpt-5.6-terra / high`, `## Policy conversion`, `Ruling: policy conversion codex-v2 -> codex-v3` and `caught mid-escalation` — then `91 passed, 6 failed`.

- [ ] **Step 3: Name the policy file's version in the rejection**

In `plugins/dr-superpowers/scripts/select-native-tier.sh`, replace

```text
  require(.policy == $p.version; "unsupported routing policy; conversion required before using codex-v2") |
```

with

```text
  require(.policy == $p.version; "unsupported routing policy; conversion required before using \($p.version)") |
```

- [ ] **Step 4: Rewrite §Existing plans**

In `plugins/dr-superpowers/reference/native-codex.md`, replace everything from the line `## Existing plans` up to (not including) the line `## Execution modes and session ends` with the content of the four-backtick block below. The block's own fence lines are not part of the text; the three-backtick fences inside it are, so copy them exactly:

````markdown
## Existing plans

Treat an existing assignment without a source as human-pinned. Keep original
assignments fixed; actual attempts, promotions, and substitutions go in the
ledger. The selector and `scripts/plan-lint` accept only `codex-v3`: they reject
codex-v1, codex-v2 and unknown policy versions with a conversion-required
error. Never reinterpret an older plan's scores or ranks as v3.

For an old Codex or Claude plan, preview the preserved raw axes, original policy,
old total, new weighted score, and old/proposed assignments. Obtain approval
before recording the converted plan. Recalculate the total from existing axes;
do not change the underlying assessments to fit a preferred tier. If axes are
missing, obtain an explicit evaluation instead of inferring them from the total.
Keep original evaluations and assignments in the conversion record, preserve
human pins, and never automatically translate reserve overrides.

A codex-v2 plan keeps its scores: v2 and v3 share the weighted formula, so the
preview states each score as unchanged. A rubric task's proposed pair is the v3
execution tier at its score. The Execution line's pair maps by rank: a v2
execution pair becomes the v3 pair at the same rank (v2 `gpt-5.6-sol / high`,
rank 7, becomes `gpt-6-astra / medium`), and a reserve pair stays itself. A
human pin stays verbatim even when it names a GPT-5.6 pair, which the selector
still dispatches while it is advertised; the preview flags each such pin so
your human partner keeps or re-pins it explicitly.

The codex-v2 ranks, kept here because the policy file no longer carries them:

```text
rank  codex-v2 pair
0     gpt-5.6-luna / low
1     gpt-5.6-luna / medium
2     gpt-5.6-terra / low
3     gpt-5.6-terra / medium
4     gpt-5.6-terra / high
5     gpt-5.6-sol / low
6     gpt-5.6-sol / medium
7     gpt-5.6-sol / high
8     gpt-6-astra / high
9     gpt-6-astra / xhigh
reserve  gpt-6-astra / max, then gpt-6-astra / ultra
```

An unstarted plan, one with no ledger, is converted in place and committed:
its `Routing policy:` line becomes `codex-v3` in its existing bold or plain
form, the Execution line and every `Assignment source: rubric` Implementer line
take their v3 pairs, Evaluation lines stay untouched, and a conversion record
goes in the header immediately before `## Task index`, so no task's text
absorbs it:

```text
## Policy conversion

codex-v2 → codex-v3, approved <date>. Scores unchanged.

| Task | Axes (f/s/c/r) | Score | codex-v2 | codex-v3 | Source |
|---|---|---|---|---|---|
| 1 | 1/1/1/0 | 3 | gpt-5.6-terra / medium | gpt-6-sol / low | rubric |
| 2 | 0/1/0/1 | 3 | gpt-5.6-sol / high | gpt-5.6-sol / high | human (kept) |
```

`scripts/plan-lint` must pass on the converted plan.

A plan with a ledger does not change: it is immutable during execution, and
`scripts/plan-amend` refuses `Routing policy:` lines. Convert active work only
at a reconciled task boundary, recording the approved preview as one ledger
line:

```text
Ruling: policy conversion codex-v2 -> codex-v3 — approved preview; Task 4 gpt-6-sol / low, Task 5 gpt-6-astra / medium — attempts above this line stay codex-v2
```

Later selector requests carry `"policy": "codex-v3"`. Preserve policy-tagged
attempt history and consumed split/review budgets; never relabel old attempts,
fabricate v3 ranks, or reset budgets to make a request pass. If v3 cannot
represent the active history, as for a task caught mid-escalation, stop for an
explicit handoff decision. A fresh unstarted v3 task can have empty local
history while retaining the prior task record.
A Claude `Executor: codex` line never starts recursive CLI offload in a Codex host.
````

Keep one blank line between the last line of that text and `## Execution modes and session ends`.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
timeout 120 bash plugins/dr-superpowers/tests/native-routing.test.sh | tail -1
grep -c '^## Existing plans$' plugins/dr-superpowers/reference/native-codex.md
```

Expected: `97 passed, 0 failed` (the documented-example check still reads the first ```` ```json ```` block, which is the selector example); `1`.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/scripts/select-native-tier.sh plugins/dr-superpowers/reference/native-codex.md plugins/dr-superpowers/tests/native-routing.test.sh
git commit -m "feat(superpowers): convert codex-v2 plans to v3" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: Version names across skills and references

**Files:**
- Modify: `plugins/dr-superpowers/README.md:38`
- Modify: `plugins/dr-superpowers/skills/writing-plans/SKILL.md:114`, `:219`
- Modify: `plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md:31`
- Modify: `plugins/dr-superpowers/reference/ladder.md:5`
- Modify: `plugins/dr-superpowers/reference/delegated-task.md:317`
- Test: `plugins/dr-superpowers/tests/inline-mode.test.sh:204`
- Test: `plugins/dr-superpowers/tests/next-step.test.sh:144`, `:146`, `:470`, `:472`, `:476`

**Interfaces:**
- Consumes: the version string `codex-v3` (Global Constraints).
- Produces: nothing later tasks read.

**Items:** 6

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6-sol / low
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Write the failing assertion**

In `plugins/dr-superpowers/tests/inline-mode.test.sh`, in the line beginning `present "the delegated loop names the Codex escalation source"`, change `'come from the \`codex-v2\` selector'` to `'come from the \`codex-v3\` selector'`.

- [ ] **Step 2: Run it to verify it fails**

```bash
timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh | grep -E '^FAIL|passed'
```

Expected: a `FAIL` line for `the delegated loop names the Codex escalation source`, and a summary with `1 failed`.

- [ ] **Step 3: Replace the version names**

Make these exact whole-line replacements. In the block below, each file name is followed by its old line (`-`) and new line (`+`); the `- ` and `+ ` prefixes are not part of the lines:

```text
plugins/dr-superpowers/README.md
- `codex-v2` policy routes scores 0–9 through Luna, Terra, Sol and Astra with
+ `codex-v3` policy routes scores 0–9 through Luna, Sol and Astra with

plugins/dr-superpowers/skills/writing-plans/SKILL.md
- Codex plans also carry `Host: codex` and `Routing policy: codex-v2` lines
+ Codex plans also carry `Host: codex` and `Routing policy: codex-v3` lines
- `codex-v2` selector, plan headers, assignment-source fields, and conversion
+ `codex-v3` selector, plan headers, assignment-source fields, and conversion

plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md
- its `codex-v2` protocol replaces every Claude agent and external-CLI
+ its `codex-v3` protocol replaces every Claude agent and external-CLI

plugins/dr-superpowers/reference/ladder.md
- uses [native-codex.md](native-codex.md) and its weighted `codex-v2` score.
+ uses [native-codex.md](native-codex.md) and its weighted `codex-v3` score.

plugins/dr-superpowers/reference/delegated-task.md
- reserve chain all come from the `codex-v2` selector
+ reserve chain all come from the `codex-v3` selector
```

- [ ] **Step 4: Update the next-step Codex fixtures**

In `plugins/dr-superpowers/tests/next-step.test.sh`:
- `codex gpt-5.6-sol / high — Codex host` → `codex gpt-6-sol / high — Codex host`
- `"codex -m gpt-5.6-sol -c model_reasoning_effort=high"` → `"codex -m gpt-6-sol -c model_reasoning_effort=high"`
- the line `**Routing policy:** codex-v2` → `**Routing policy:** codex-v3`
- `` `codex gpt-5.6-terra / high` `` → `` `codex gpt-6-sol / medium` `` (rank 4 in both policies)
- `"codex -m gpt-5.6-terra -c model_reasoning_effort=high"` → `"codex -m gpt-6-sol -c model_reasoning_effort=medium"`

- [ ] **Step 5: Run the tests and the leftover checks**

```bash
timeout 300 bash plugins/dr-superpowers/tests/inline-mode.test.sh | tail -1
timeout 300 bash plugins/dr-superpowers/tests/next-step.test.sh | tail -1
cd plugins/dr-superpowers && grep -rn 'codex-v2' . ; grep -rn 'gpt-5\.6' reference/codex-routing.json skills tests/next-step.test.sh; cd - >/dev/null
```

Expected: both summaries report `0 failed`. The `codex-v2` grep hits only `reference/native-codex.md` (the §Existing plans conversion text) and `tests/native-routing.test.sh` (the rejection cases, and the §Existing plans needles once Task 3 has run), plus `tests/plan-lint.test.sh` once Task 5 has run. The `gpt-5.6` grep prints nothing.

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/README.md plugins/dr-superpowers/skills/writing-plans/SKILL.md plugins/dr-superpowers/skills/subagent-driven-development/SKILL.md plugins/dr-superpowers/reference/ladder.md plugins/dr-superpowers/reference/delegated-task.md plugins/dr-superpowers/tests/inline-mode.test.sh plugins/dr-superpowers/tests/next-step.test.sh
git commit -m "docs(superpowers): name codex-v3 across the plugin" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: plan-lint Routing-policy check

**Files:**
- Modify: `plugins/dr-superpowers/scripts/plan-lint:65-66` (insert after), `:177-178`, `:288`
- Test: `plugins/dr-superpowers/tests/plan-lint.test.sh` (after the `has "promotion warns"` line)

**Interfaces:**
- Consumes: Policy file; plan-lint Codex fixture (Contracts).
- Produces: plan-lint policy finding (Contracts).

**Items:** 5

**Implementer:** dr-superpowers:impl-sonnet-high
**Executor:** codex gpt-6-sol / medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/plan-lint.test.sh`, directly below the line `has "promotion warns" "$out" "WARN Task 1: Implementer rank 4 is above routing score 3 (promotion)"`, add:

```bash
codex_plan | sed 's#^Routing policy: codex-v3$#Routing policy: codex-v2#; s#codex gpt-6-sol / high#codex gpt-5.6-sol / high#; s#codex gpt-6-sol / low#codex gpt-5.6-terra / medium#' > cv2.md
lint cv2.md
check "codex-v2 plan: exit 1" "$status" "1"
has "codex-v2 plan: conversion error" "$out" "ERROR header: Routing policy is codex-v2, not codex-v3; convert the plan per reference/native-codex.md §Existing plans"
lacks "codex-v2 plan: no Execution pair error" "$out" "is not in codex-routing.json"
lacks "codex-v2 plan: no Implementer tier error" "$out" "is not an execution tier"
has "codex-v2 plan: the conversion error is the only finding" "$out" "plan-lint: 1 errors, 0 warnings"
codex_plan | sed '/^Routing policy:/d; s#codex gpt-6-sol / high#codex gpt-5.6-sol / high#; s#codex gpt-6-sol / low#codex gpt-5.6-terra / medium#' > cnone.md
lint cnone.md
check "no Routing policy line: exit 1" "$status" "1"
has "no Routing policy line: conversion error names it missing" "$out" "ERROR header: Routing policy is missing, not codex-v3; convert the plan per reference/native-codex.md §Existing plans"
lacks "no Routing policy line: no Execution pair error" "$out" "is not in codex-routing.json"
lacks "no Routing policy line: no Implementer tier error" "$out" "is not an execution tier"
has "no Routing policy line: the conversion error is the only finding" "$out" "plan-lint: 1 errors, 0 warnings"
codex_plan | sed '/^Routing policy:/d; s#^\*\*Goal:\*\* Demo\.$#**Goal:** Demo.\n\n```text\nRouting policy: codex-v3\n```#' > cfenced.md
lint cfenced.md
has "a fenced Routing policy line does not count" "$out" "ERROR header: Routing policy is missing, not codex-v3; convert the plan per reference/native-codex.md §Existing plans"
```

- [ ] **Step 2: Run them to verify they fail**

```bash
timeout 300 bash plugins/dr-superpowers/tests/plan-lint.test.sh | grep -E '^FAIL|passed'
```

Expected: nine `FAIL` lines — for both `codex-v2 plan:` and `no Routing policy line:`, the conversion error, `no Execution pair error`, `no Implementer tier error` and `the conversion error is the only finding`, plus `a fenced Routing policy line does not count` — and `144 passed, 9 failed`. The two `exit 1` checks already pass, because the stale pairs make the unchanged script fail.

- [ ] **Step 3: Add the check**

In `plugins/dr-superpowers/scripts/plan-lint`, directly after these two lines:

```bash
codex=0
grep -qE '^(\*\*)?Host:(\*\*)?[ \t]+codex[ \t]*$' <<<"$header" && codex=1
```

insert:

```bash

# A plan written under another routing policy names pairs this policy does not
# rank, so one conversion finding replaces a pair or rank finding per task.
policy_ok=1
if [ "$codex" -eq 1 ]; then
  want_policy=$(jq -r '.version' "$ROUTING" 2>/dev/null | tr -d '\r')
  got_policy=$(awk "$_PLAN_AWK"'in_fence($0) { next } { print }' <<<"$header" \
    | sed -nE 's/^(\*\*)?Routing policy:(\*\*)?[ \t]+([^ \t]+)[ \t]*$/\3/p' | head -n 1)
  if [ "$got_policy" != "$want_policy" ]; then
    policy_ok=0
    say ERROR header "Routing policy is ${got_policy:-missing}, not $want_policy; convert the plan per reference/native-codex.md §Existing plans"
  fi
fi
```

In the Execution-line block, replace

```bash
      jq -e --arg m "$m" --arg e "$e" '[.execution[], .reserve[]] | any(.model == $m and .effort == $e)' "$ROUTING" >/dev/null 2>&1 \
        || say ERROR header "Execution pair codex $m / $e is not in codex-routing.json"
```

with

```bash
      [ "$policy_ok" -eq 0 ] \
        || jq -e --arg m "$m" --arg e "$e" '[.execution[], .reserve[]] | any(.model == $m and .effort == $e)' "$ROUTING" >/dev/null 2>&1 \
        || say ERROR header "Execution pair codex $m / $e is not in codex-routing.json"
```

In the per-task Codex block, replace

```bash
    if [[ "$source" == *rubric* ]]; then
```

with

```bash
    if [[ "$source" == *rubric* ]] && [ "$policy_ok" -eq 1 ]; then
```

That `if` line occurs exactly once in the file.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
timeout 300 bash plugins/dr-superpowers/tests/plan-lint.test.sh | tail -1
```

Expected: `153 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dr-superpowers/scripts/plan-lint plugins/dr-superpowers/tests/plan-lint.test.sh
git commit -m "feat(superpowers): lint the Codex routing policy" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: plan-revise refuses Codex-host plans

**Files:**
- Modify: `plugins/dr-superpowers/scripts/plan-revise:21-22` (insert after), `:202-203` (insert after), `:261` (insert after)
- Modify: `plugins/dr-superpowers/skills/revising-plans/SKILL.md:14-16` (insert after)
- Test: `plugins/dr-superpowers/tests/plan-revise.test.sh`

**Interfaces:**
- Consumes: Conversion section name (Contracts).
- Produces: plan-revise refusal and survey row (Contracts).

**Items:** 6

**Implementer:** dr-superpowers:impl-sonnet-medium
**Executor:** codex gpt-6-sol / low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2

- [ ] **Step 1: Write the failing tests**

In `plugins/dr-superpowers/tests/plan-revise.test.sh`, directly below the line `(cd "$REPO" && bash "$SCRIPT" >/dev/null 2>&1); check "no argument exits 2" "$?" "2"`, add:

```bash

# --- a Codex-host plan is not this script's ---
codex_plan() { # codex_plan <path>
  printf '# Codex Plan\n\nHost: codex\nRouting policy: codex-v3\n\n**Execution:** subagent — codex gpt-6-sol / high — native\n\n### Task 1: One\n\n**Files:**\n- Create: `x`\n\n**Implementer:** codex gpt-6-sol / low\n**Evaluation:** files=1, spec=1, coupling=1, risk=0; weighted routing score=3\n**Assignment source:** rubric\n' > "$1"
}
codex_plan "$REPO/docs/codex.md"
out=$( (cd "$REPO" && bash "$SCRIPT" docs/codex.md) 2>&1 ); rc=$?
check "a Codex-host plan exits 2" "$rc" "2"
check "a Codex-host plan is refused by name" "$out" "plan-revise: docs/codex.md is a Codex-host plan; convert it per reference/native-codex.md §Existing plans"
bare "$(printf '```text\nHost: codex\n```\n\n%s' "$(mktask 1 0 1 0 2)")"
check "a fenced Host: codex line does not refuse a Claude plan" "$( (cd "$REPO" && bash "$SCRIPT" docs/p.md) >/dev/null 2>&1; echo $?)" "0"
```

`bare` and `mktask` are the file's existing helpers; the `%s` form keeps the newline after the closing fence, which a `$(…)` would strip.

Directly below the line `check "the survey counts eligibility without a ticked executor" "$(field eligible "$(row scored)")" "1"`, add:

```bash
codex_plan "$SUR/docs/codex.md"
check "the survey skips a Codex-host plan" "$(row codex)" "plan  codex.md  host=codex  skipped"
check "the survey still counts it as surveyed" "$(survey | tail -n 1)" "surveyed  plans=4"
rm -f "$SUR/docs/codex.md"
```

Directly below the line `check "the skill exists" "$([ -f "$SK" ] && echo yes || echo no)" "yes"`, add:

```bash
present "the skill revises Claude plans only" "$SK" "revises Claude plans only"
```

- [ ] **Step 2: Run them to verify they fail**

```bash
timeout 300 bash plugins/dr-superpowers/tests/plan-revise.test.sh | grep -E '^FAIL|passed'
```

Expected: four `FAIL` lines — `a Codex-host plan exits 2`, `a Codex-host plan is refused by name`, `the survey skips a Codex-host plan` and `the skill revises Claude plans only` — then `81 passed, 4 failed`. `the survey still counts it as surveyed` and `a fenced Host: codex line does not refuse a Claude plan` already pass: they guard behaviour the change must keep.

- [ ] **Step 3: Refuse and skip Codex-host plans**

In `plugins/dr-superpowers/scripts/plan-revise`, directly after

```bash
die() { printf 'plan-revise: %s\n' "$1" >&2; exit 2; }
usage() { die "usage: plan-revise PLAN_FILE | plan-revise --survey DIR"; }
```

insert:

```bash

# A Codex-host plan carries the weighted native Evaluation form, which this
# script reads as unscored and then answers with a Claude Execution line. Fenced
# lines are skipped so a plan quoting a Codex header is not mistaken for one.
is_codex_plan() {
  plan_header "$1" | awk "$_PLAN_AWK"'in_fence($0) { next } { print }' \
    | grep -qE '^(\*\*)?Host:(\*\*)?[ \t]+codex[ \t]*$'
}
```

In `survey()`, directly after

```bash
    [ "$tasks" -gt 0 ] || continue
    rows=$((rows + 1))
```

insert:

```bash
    if is_codex_plan "$f"; then
      printf 'plan  %s  host=codex  skipped\n' "$(basename "$f")"
      continue
    fi
```

Directly after the line `[ -f "$plan" ] || die "no such plan file: $plan"`, insert:

```bash
is_codex_plan "$plan" && die "$plan is a Codex-host plan; convert it per reference/native-codex.md §Existing plans"
```

- [ ] **Step 4: State the scope in the skill**

In `plugins/dr-superpowers/skills/revising-plans/SKILL.md`, after the paragraph that begins `` `scripts/plan-revise` computes; this skill decides and edits.`` and ends `inside the plan's repository.`, insert a blank line and:

```text
This skill revises Claude plans only. `plan-revise` refuses a plan whose header
carries `Host: codex` with exit 2, and the survey lists one as
`host=codex  skipped`: convert a Codex plan per
[native-codex.md](../../reference/native-codex.md) §Existing plans instead.
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
timeout 300 bash plugins/dr-superpowers/tests/plan-revise.test.sh | tail -1
timeout 60 node scripts/validate-repository.mjs
```

Expected: `85 passed, 0 failed`; `Repository catalogs, manifests, versions, and bundled links are valid.`

- [ ] **Step 6: Commit**

```bash
git add plugins/dr-superpowers/scripts/plan-revise plugins/dr-superpowers/tests/plan-revise.test.sh plugins/dr-superpowers/skills/revising-plans/SKILL.md
git commit -m "fix(superpowers): refuse Codex plans in plan-revise" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: Release 1.20.0

**Files:**
- Modify: `plugins/dr-superpowers/.claude-plugin/plugin.json:5`
- Modify: `plugins/dr-superpowers/.codex-plugin/plugin.json:3`
- Test: `plugins/dr-superpowers/tests/review-route.test.sh:568-569`

**Interfaces:**
- Consumes: Tasks 2–6 committed.
- Produces: nothing.

**Items:** 6

**Implementer:** dr-superpowers:impl-sonnet-low
**Evaluation:** files 1 - spec 0 - coupling 0 - risk 0 = 1

- [ ] **Step 1: Write the failing assertion**

In `plugins/dr-superpowers/tests/review-route.test.sh`, replace

```bash
present "the Claude manifest is 1.19.0" "$P/.claude-plugin/plugin.json" '"version": "1.19.0"'
present "the Codex manifest is 1.19.0" "$P/.codex-plugin/plugin.json" '"version": "1.19.0"'
```

with

```bash
present "the Claude manifest is 1.20.0" "$P/.claude-plugin/plugin.json" '"version": "1.20.0"'
present "the Codex manifest is 1.20.0" "$P/.codex-plugin/plugin.json" '"version": "1.20.0"'
```

- [ ] **Step 2: Run it to verify it fails**

```bash
timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh | grep -E '^FAIL|passed'
```

Expected: two `FAIL` lines naming the manifests, and `2 failed`.

- [ ] **Step 3: Bump both manifests**

In both `plugins/dr-superpowers/.claude-plugin/plugin.json` and `plugins/dr-superpowers/.codex-plugin/plugin.json`, change `"version": "1.19.0"` to `"version": "1.20.0"`. Nothing else in either file changes.

- [ ] **Step 4: Run the full validation**

```bash
timeout 300 bash plugins/dr-superpowers/tests/review-route.test.sh | tail -1
timeout 60 node scripts/validate-repository.mjs
timeout 590 node scripts/test-all.mjs > .superpowers/codex-v3-test-all.log 2>&1; echo "test-all=$?"
grep -E '^Finished .*\(exit [^0]' .superpowers/codex-v3-test-all.log
grep -E '^✖ ' .superpowers/codex-v3-test-all.log | sort -u
for p in . plugins/dr-status plugins/dr-superpowers plugins/dcc-darkraise-ui plugins/dcc-darkraise-win32ui; do timeout 60 claude plugin validate "$p" | tail -1; done
```

Expected: `0 failed`; `Repository catalogs, manifests, versions, and bundled links are valid.`; five lines of `✔ Validation passed`.

`test-all` either passes completely (`test-all=0`, and both greps print nothing) or fails only on the known environmental case. That case prints `test-all=1`, exactly one `Finished` line (the combined root job `Finished --test tests/repository-layout.test.mjs tests/test-shards.test.mjs tests/ui-discovery.test.mjs in <t>s (exit 1)`), and `✖` lines naming only `documented Win32 discovery finds centrally managed versions` (the child shell's PATH has no `rg`). Any other `Finished … (exit N)` line or `✖` test name is a regression from this plan: keep the log, stop, and fix it before committing. Once the failures are classified, remove the log:

```bash
rm -f .superpowers/codex-v3-test-all.log
```

- [ ] **Step 5: Check the final inventory (spec §9)**

```bash
cd plugins/dr-superpowers
grep -rl 'codex-v2' . | sort
grep -rl 'gpt-5\.6' reference/codex-routing.json reference/native-codex.md skills tests/native-routing.test.sh tests/next-step.test.sh | sort
cd - >/dev/null
```

Expected, exactly:

```text
reference/native-codex.md
tests/native-routing.test.sh
tests/plan-lint.test.sh
reference/native-codex.md
tests/native-routing.test.sh
```

The first three come from the conversion text in §Existing plans, the selector's v2 rejection cases and plan-lint's v2 fixtures. The last two come from §Existing plans' v2 table and examples, and the `4     gpt-5.6-terra / high` needle. Any other file is a stale active-policy reference: fix it in the task that owns the file.

- [ ] **Step 6: Confirm nothing started by the validation is running**

```bash
ps -eo pid,args | grep -E '[t]est-all\.mjs|[n]ode --test|[c]odex exec|[p]lan-lint|[p]lan-revise' || echo none
```

Expected: `none`. The bracketed first letters keep the pattern from matching the shell running this command. A listed process whose command line names this repository was started by this run: stop it with `kill <pid>` (use `pkill -P <pid>` first for its children) and re-run the check.

- [ ] **Step 7: Commit**

```bash
git add plugins/dr-superpowers/.claude-plugin/plugin.json plugins/dr-superpowers/.codex-plugin/plugin.json plugins/dr-superpowers/tests/review-route.test.sh
git commit -m "chore(superpowers): bump to 1.20.0" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
