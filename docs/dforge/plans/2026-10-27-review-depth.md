# Review Depth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names — dforge:subagent-driven-development for `subagent`, dforge:executing-plans for `inline`. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `scripts/depth-route`, which sizes every architectural plan as light, standard or full from its risk triggers and task risk scores, and make the spec, plan and final-review stages run only what that depth calls for.

**Architecture:** One rule in a new `scripts/lib/depth.sh`, sourced by a new `scripts/depth-route` CLI and by `review-route` (plan-review cap) and `lens-route` (final-review lenses). Skill and reference text then reads the depth at each stage: brainstorming and auto-run.md for the spec phase, writing-plans and handoff for the plan phase, final-review.md, the two execution skills and finishing for the end. Plans and specs without a Depth line route at full, so nothing in flight changes.

**Tech Stack:** Bash 5 (`set -uo pipefail`), awk/sed/grep, the plugin's bash test suites (`plugins/dforge/tests/*.test.sh`), Markdown skill files.

**Spec:** docs/dforge/specs/2026-10-27-review-depth-design.md

**Execution:** subagent — `claude --model sonnet --effort high` — a waves plan runs in subagent mode

**Parallelism:** waves — 1-2 | 3-5 | 6-8 | 9 | 10-11

**Integration check:** `cd /root/repositories/darkraise-ai-plugins && timeout --kill-after=10s 1050s node scripts/test-all.mjs`

**Worktree setup:** none

**Plan review:** 2026-10-27 — dforge:judge-opus — executability 14 / coherence 15 / coverage 18 / assumptions 16 (round 2)

## Global Constraints

- The code under change is the repository copy, `plugins/dforge/` in this checkout. Never edit the installed plugin under `~/.claude-alt/plugins/cache/`.
- Every new or changed script is Bash with `set -uo pipefail`, sources `lib/plan.sh` the way `scripts/review-route` does, and uses only bash, awk, sed, grep, git and jq; `rg` is a shell function here, not a binary, so scripts and steps use `grep`.
- Error messages go to stderr as `<script-name>: <message>`; usage errors and unknown inputs exit 2, as `review-route` and `lens-route` do.
- Test suites follow `plugins/dforge/tests/review-route.test.sh`: a `check`/`present`/`absent` helper set, `TMP=$(mktemp -d)` with an EXIT trap, fixture plans written by heredoc with each line prefixed `|` and stripped by `sed 's/^|//'`, and a final `printf '\n%d passed, %d failed\n'` with exit status from the failure count. Each suite works only inside its own `$TMP`: no fixed paths, ports or global state.
- Run each changed suite under a timeout: `timeout 300 bash plugins/dforge/tests/<suite>.test.sh`.
- Text pins: `tests/process-roles.test.sh`, `tests/faster-plans.acceptance.test.sh` and `tests/auto-default.test.sh` quote skill text. A task may change a pinned phrase only when its Files block names that suite; every other task keeps each pinned phrase byte-for-byte and adds text around it. Before editing a skill file, grep these three suites for the file's name to see what is pinned.
- Skill text: wrap at about 80 columns like the surrounding text, no new headings unless the task says so, and never reference this plan, its spec or a task number in shipped text.
- Old plans keep today's behaviour: a plan with no `**Spec:**` line, a spec with no `**Depth:**` line, and every existing test fixture route at `full`, and every existing assertion in a suite a task touches stays as it is unless the task names it.
- Commits: `<type>(dforge): <subject>`, subject at most 50 characters, imperative, no period, no AI attribution; author `Darkraise <quangtc94@gmail.com>`.

## Contracts

**C1 — `scripts/lib/depth.sh`** (Task 2). Sourced after `lib/plan.sh`; defines only functions and the readonly array below, no top-level side effects.

- `DEPTH_TRIGGERS=(new-subsystem interface unenumerable approach risk intricate asked)` — the seven trigger ids.
- `depth_rank DEPTH` — prints `0`, `1` or `2` for `light`, `standard`, `full`; status 1 and no output for anything else.
- `depth_name RANK` — prints `light`, `standard` or `full` for `0`, `1`, `2`.
- `depth_from_triggers LIST` — LIST is comma-separated trigger ids. Prints one line `<depth>\t<reason>`: `full` when LIST holds `risk` or `new-subsystem` (reason: those of the two present, in the order `risk,new-subsystem`); else `standard` when it holds `interface` (reason `interface`); else `light` (reason: every id given, in the order given). Status 2 with a stderr message `no trigger given` for an empty LIST, or `unknown trigger: <id>` for an id outside `DEPTH_TRIGGERS`; no stdout then.
- `depth_spec_file SPEC_FILE` — prints the first word after `**Depth:**` on the first line of SPEC_FILE that begins with `**Depth:**`, when that word is `light`, `standard` or `full`; prints `none` when the file is missing, has no such line, or the word is anything else.
- `depth_plan SRC ROOT` — SRC is a plan file with its amendments already applied; ROOT is the checkout root used to resolve the plan's `**Spec:**` path with `dforge_resolve "<path>" "$ROOT"` (the path parsed with the same sed expression `scripts/plan-lint` uses on the Spec line). Prints one line:
  `depth=<d> spec=<light|standard|full|none> tasks=<light|standard|full> reason=<items>`
  - `tasks=` from `plan_scores SRC`: `full` when any task's row is `-` (no Evaluation line) or `?` (unparsable) or its risk is 3; else `standard` when the highest risk is 2; else `light`. Totals and the task count are never read.
  - `depth=`: `full` when the header has a `Host: codex` line (matched as `review-route` matches it) or `spec=none`; otherwise the higher of `spec` and `tasks`.
  - `reason=` items, comma-joined, in this order: `codex-host` (alone, when it applies, and then no other item); `no-spec-depth` when `spec=none`; `spec` when `spec` equals `depth`; `unscored:<N>` for the first task (in plan order) whose row is `-` or `?`, when `tasks=full` comes from it; `task-risk:<N>` for the first task at the highest risk, when `tasks` equals `depth` and no `unscored` item was printed. A plan with no tasks has `tasks=light` and no task item.
- `depth_plan_depth SRC ROOT` — prints only the `<d>` of `depth_plan`.
- **ROOT, for every caller** (`depth-route`, `review-route`, `lens-route`): `git -C "$(dirname "$plan")" rev-parse --show-toplevel 2>/dev/null || pwd`, where `$plan` is the located plan file, so all three read the same depth wherever they run.

**C2 — `scripts/depth-route`** (Task 2).

```
depth-route --spec-triggers LIST   ->  depth=<d> reason=<ids>         exit 0
depth-route PLAN_FILE              ->  the depth_plan line             exit 0
```

PLAN_FILE is located with `plan_locate`, read with `plan_apply_amendments "$plan" "$(plan_amendments_file "$plan")"` into a temp file as `review-route` does, and ROOT is `git -C "$(dirname "$plan")" rev-parse --show-toplevel`, falling back to `pwd`. Exit 2 with `depth-route: <message>` on stderr for: no arguments, an unknown option, an empty or unknown trigger list, a missing plan file, or an amendment that does not apply. Its comment block opens like `lens-route`'s: a one-line purpose, why the rule lives in a script, `# Usage:`, `# Output:`, `# Exit:`.

**C3 — `review-route PLAN_FILE --plan-round R` on a Claude plan** (Task 3). `cap=` comes from `depth_plan_depth`: light `0`, standard `1`, full `2`. At light, round 1 prints exactly
`review-seat plan-round=1 primary=none fallback=- reason=depth-light cap=0` and exits 0. Any round above the cap exits 2 with the existing `plan round <R> is past the cap (<cap>)` message. A `Host: codex` plan keeps its native cap rule unchanged. All other routes are unchanged.

**C4 — `lens-route PLAN_FILE --final BASE HEAD`** (Task 4). After the `lenses off` check, read the depth with `depth_plan_depth "$src" <ROOT>`, ROOT as C1 states it.
- light: print a `lens` line only for `security`, and only when its Applies clause matches; every other lens whose Applies clause matches prints `lens-skipped <id> reason=depth`.
- standard: the cap is the smaller of the `lensCap` value and 2; lenses past it print `lens-skipped <id> reason=cap` as today.
- full: unchanged.
- `lenses off` and `lens-floor important …` keep today's rules (`n` counts the `lens` lines printed). `--task` is unchanged.

**C5 — line grammar** used across skill text and tests.
- Spec line, below `**Execution strategy:**`: `**Depth:** <light|standard|full> — <reason ids>`; set by the owner: `**Depth:** <d> — owner`.
- Process line, architectural path: `Process: architectural, <inline|subagent>, depth <d> — <triggers>`.
- Plan header at light: `**Plan review:** <YYYY-MM-DD> — skipped (depth light)`.
- Spec review count at light: `Critic: skipped (depth light)`; every spec review message also carries `Depth: <d> — <reasons>`.
- Ledger: `Review depth: <depth> (<reason>)` before final-review step 0; `Acceptance QA: skipped (depth light)`, which recovery treats as `Acceptance QA: complete`; final-review step 4 writes `final review lens-skipped <id> reason=<reason>` for every `lens-skipped` line, whatever its reason (today's `reason=cap` line, generalised).
- Spoken lines: `codex round skipped (depth <d>)`; at light finishing lists the spec's `test` statements under `not verified (depth light)`.

## Assumptions (evidence)

- `plan_scores` prints `<task>\t<total>\t<risk>` per task, `-` for both when a task has no Evaluation line and `?` when one does not parse, and takes the highest risk across a split task's parts — `plugins/dforge/scripts/lib/plan.sh:185-205`, read 2026-10-27.
- `dforge_resolve` maps `docs/dforge/…` paths into the darkmem mirror when `documentStore` keeps documents there — `plugins/dforge/scripts/lib/roots.sh:166-177`, read 2026-10-27.
- A Claude plan has no cap-critical plan-review round: `review-route` exits 2 past the cap — `plugins/dforge/scripts/review-route:268-272`, read 2026-10-27.
- Existing `review-route` and `lens-route` fixture plans carry no resolvable spec with a Depth line, so they route at full and their assertions stand — `plugins/dforge/tests/review-route.test.sh:42-100`, read 2026-10-27.
- CI discovers every `plugins/dforge/tests/*.test.sh` without a list to edit — `scripts/test-shards.mjs:4-5` ("newly discovered suites receive the default weight"), read 2026-10-27.
- The Codex executor lane is off this session (`codex-gate … lane=false reason=setting`, run 2026-10-27), so no task carries an Executor line.
- Round 2's one Critical finding (Task 9's pin tail `so this` against Step 4's `so the`) was fixed and checked mechanically (the pin's needle occurs on one line of Step 4's text, `grep -cF`, 2026-10-27) instead of in a cap-critical round.
- The spec's riskiest assumption — that light plans lose little by skipping plan review and acceptance QA — is unverified; Task 1 verifies it.

## Task index

1. Measure what plan review and QA caught on light-scoring plans
2. Add lib/depth.sh and the depth-route command
3. Take review-route's plan-round cap from the depth
4. Route final-review lenses by depth in lens-route
5. Size the plan phase by depth in writing-plans and handoff
6. Size the spec phase by depth in using-dforge, brainstorming and auto-run
7. Size the final review by depth in final-review.md
8. Add the depth ledger lines to both execution skills
9. List depth-skipped checks when finishing a branch
10. Describe review depth in the dforge README
11. Add the review-depth acceptance suite

---

### Task 1: Measure what plan review and QA caught on light-scoring plans

**Files:**
- Create: `docs/dforge/notes/2026-10-27-review-depth-measurement.md`
- Create: `docs/dforge/registers/2026-10-27-review-depth.md` (only when the verdict is `inconclusive`)

**Interfaces:**
- Consumes: `plan_scores`, `plan_header_line` (`plugins/dforge/scripts/lib/plan.sh`), `scripts/dforge-path` and `scripts/register`, all as they stand.
- Produces: the note, whose `**Verdict:**` line is `inconclusive`, `keep` or `stop`. `keep` and `inconclusive` let the later tasks proceed; `stop` ends this task as BLOCKED, so the controller takes the plan to a ruling before the next wave. No later task reads the note's text.

**Depends on:** none

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 1 - spec 1 - coupling 0 - risk 0 = 2

This task checks the spec's riskiest assumption: that on plans whose spec scores light and whose tasks are all at risk 1 or below, plan review and acceptance QA rarely find a defect that the task reviews and the whole-branch review would miss. It reads existing evidence and writes one note. It changes no script, skill or test.

The agent scratch files live in `.dforge/review-depth-measure/`, which git ignores, and Step 7 removes them.

- [ ] **Step 1: Write the survey script**

Run from the checkout root:

```bash
mkdir -p .dforge/review-depth-measure
cat > .dforge/review-depth-measure/survey.sh <<'EOF'
#!/usr/bin/env bash
# Usage: survey.sh — run from inside the checkout. Lists every completed plan
# whose tasks are all scored at risk 1 or below, with its spec and the review
# evidence the workspaces and the ledger store still hold.
set -uo pipefail
ROOT=$(git rev-parse --show-toplevel)
. "$ROOT/plugins/dforge/scripts/lib/plan.sh"

wts=$(git worktree list --porcelain | tr -d '\r' | sed -n 's/^worktree //p')
printf 'stores: %s\n' "$(bash "$ROOT/plugins/dforge/scripts/dforge-path" store | tr '\n' ' ')"
printf 'worktrees searched:\n%s\n\n' "$wts"

for list in docs/dforge/plans/completed.md docs/superpowers/plans/completed.md; do
  [ -f "$ROOT/$list" ] || continue
  grep -o '`docs/[^`]*\.md`' "$ROOT/$list" | tr -d '`'
done | sort -u | while IFS= read -r plan; do
  [ -f "$ROOT/$plan" ] || { printf 'SKIP %s (file gone)\n' "$plan"; continue; }
  scores=$(plan_scores "$ROOT/$plan")
  n=$(grep -c . <<<"$scores")
  [ "$n" -gt 0 ] || { printf 'SKIP %s (no tasks)\n' "$plan"; continue; }
  if awk -F'\t' '$3 == "-" || $3 == "?" || $3 + 0 > 1 { bad = 1 } END { exit !bad }' <<<"$scores"; then
    continue
  fi
  slug=$(basename "$plan" .md)
  spec=$(plan_header_line "$ROOT/$plan" Spec | sed -E 's/^\*\*Spec:\*\*[ \t]*(`([^`]+)`|([^ \t]+)).*/\2\3/')
  printf 'PLAN %s tasks=%s spec=%s\n' "$plan" "$n" "${spec:--}"
  rv=$(plan_header_line "$ROOT/$plan" 'Plan review' | cut -c1-140)
  printf '  plan-review header: %s\n' "${rv:-none}"
  found=0
  while IFS= read -r wt; do
    for f in "$wt/.dforge/sdd/$slug"/plan-review-round-*; do
      [ -e "$f" ] && { printf '  review-report %s\n' "$f"; found=1; }
    done
    f="$wt/.dforge/sdd/$slug/progress.md"
    [ -f "$f" ] && { printf '  ledger %s\n' "$f"; found=1; }
  done <<<"$wts"
  led="$(bash "$ROOT/plugins/dforge/scripts/dforge-path" ledger "$slug")/progress.md"
  [ -f "$led" ] && { printf '  ledger %s\n' "$led"; found=1; }
  [ "$found" -eq 1 ] || printf '  no evidence held\n'
done
EOF
```

The script lists the completed plans (the paths in both `completed.md` files) whose every task is scored at risk 1 or below, with the review evidence still held. A workspace is `<worktree>/.dforge/sdd/<plan basename>/`; it is searched in every worktree of this repository, because the plan-review reports of earlier plans live in the primary checkout, not in this task's worktree. The ledger is also searched where `scripts/dforge-path ledger` points, which is the darkmem mirror when progress is kept there.

- [ ] **Step 2: Run the survey**

Run: `bash .dforge/review-depth-measure/survey.sh | tee .dforge/review-depth-measure/survey.txt`

Expected: a `stores:` line (`documents local progress local` on a host with no darkmem mapping; when it reads `darkmem`, the ledger path already points into the mirror), the worktree list, then one `PLAN` block per qualifying plan. Each block shows the plan's `**Plan review:**` header line and then either `review-report` and `ledger` lines or `no evidence held`. On 2026-10-27 the list held seven plans (2026-08-21 companions-reserve-tier, the two 2026-08-28 darkraise-ui plans, 2026-08-31 external-executors, 2026-09-11 standalone-base, 2026-10-01 tier-eval, 2026-10-18 controller-model-eval) and every block ended `no evidence held`. Record what this run prints; the date changes it.

- [ ] **Step 3: Read the evidence and record one row per plan that holds some**

Skip every block that ends `no evidence held`: a `**Plan review:**` header line holds scores and a round number but no findings, so it is not evidence. For each block with a `review-report` or `ledger` line:

1. Read the spec named on the `PLAN` line (a note, when that is what the plan cites). The spec reads light when none of these holds: it builds a new project or subsystem; it changes an interface that something outside its own files depends on (a script's command line or output, a setting, a skill or agent name, a file format other tools read); it carries irreducible risk (security, data loss, migration, concurrency). A spec that is only hard to enumerate, has an open approach question, or is intricate stays light.
2. For each `review-report` file run `sed -n 1,60p FILE`. The plan review hit when the report lists at least one Critical finding (a count of `1 Critical` or more, or an item marked Critical); `0 Critical` and `No Critical` are not a hit.
3. For each `ledger` file run `grep -h 'Acceptance QA:' FILE`. QA hit when the `Acceptance QA: complete` line reports at least one fail; a ledger with no `complete` line holds no QA evidence.
4. Record one row per plan: the plan path; `yes` or `no` for spec light; the evidence held (`report`, `ledger`, `report+ledger`, or `none` when the files held nothing readable); `yes` or `no` for a hit; a short reason. Define the helper and call it once per plan in the same shell call, for example `row docs/superpowers/plans/X.md yes report no "0 Critical in round 1"` with the real path and reasons:

```bash
row() { printf '%s\t%s\t%s\t%s\t%s\n' "$@" >> .dforge/review-depth-measure/rows.tsv; }
```

When no block holds evidence, create the empty file instead:

```bash
: > .dforge/review-depth-measure/rows.tsv
```

- [ ] **Step 4: Write the note builder and build the note**

```bash
cat > .dforge/review-depth-measure/note.sh <<'EOF'
#!/usr/bin/env bash
# Usage: note.sh WORK_DIR NOTE_FILE — WORK_DIR holds survey.txt and rows.tsv.
set -uo pipefail
work=$1 note=$2
n=0 k=0
if [ -s "$work/rows.tsv" ]; then
  n=$(awk -F'\t' '$2 == "yes" && $3 != "none"' "$work/rows.tsv" | grep -c .)
  k=$(awk -F'\t' '$2 == "yes" && $3 != "none" && $4 == "yes"' "$work/rows.tsv" | grep -c .)
fi
if [ "$n" -lt 4 ]; then
  verdict=inconclusive
  why="the sample holds $n plans, fewer than the four the measurement needs; the design proceeds and a deferred register row re-checks once five light plans have shipped"
elif [ $((k * 4)) -gt "$n" ]; then
  verdict=stop
  why="$k of $n plans is more than one in four; the plan stops for a ruling on keeping one plan-review round or acceptance QA at light before any later task builds on the plan-phase or final-review changes"
else
  verdict=keep
  why="$k of $n plans is not more than one in four; the design stands"
fi
{
  printf '# Review-depth measurement — %s\n\n' "$(date +%F)"
  printf '**Sample size:** %s\n' "$n"
  printf '**Plans with a Critical plan-review finding or a QA fail:** %s\n' "$k"
  printf '**Verdict:** %s\n\n' "$verdict"
  printf 'The verdict is `%s`: %s.\n\n' "$verdict" "$why"
  printf 'The question: on plans whose spec scores light and whose tasks are all at risk 1 or below, do plan review and acceptance QA rarely find a defect that the task reviews and the whole-branch review would miss? A plan is in the sample when its spec reads light under the seven Process Depth triggers (no `risk`, `new-subsystem` or `interface` trigger) and a plan-review report or an `Acceptance QA: complete` ledger line is still held. A plan counts as a hit when a held report lists a Critical finding or the QA line reports at least one fail.\n\n'
  printf '## Candidates\n\n'
  printf 'Completed plans whose tasks are all scored at risk 1 or below, with the evidence the workspaces and the ledger store still hold (plan names with the retired dcc- prefix print without it, because the repository validator rejects that prefix in docs outside docs/superpowers):\n\n```\n'
  cat "$work/survey.txt"
  printf '```\n\n## Sample\n\n'
  if [ -s "$work/rows.tsv" ]; then
    printf '| Plan | Spec light | Evidence | Found | Why |\n|---|---|---|---|---|\n'
    awk -F'\t' '{ printf "| `%s` | %s | %s | %s | %s |\n", $1, $2, $3, $4, $5 }' "$work/rows.tsv"
  else
    printf 'No candidate holds a plan-review report or an `Acceptance QA` ledger line, so no plan was read.\n'
  fi
} | sed 's/dc[c]-darkraise-/darkraise-/g' > "$note"
EOF
bash .dforge/review-depth-measure/note.sh .dforge/review-depth-measure docs/dforge/notes/2026-10-27-review-depth-measurement.md
```

The builder counts a plan into the sample when its row says spec light `yes` and the evidence is not `none`. It sets the verdict: `inconclusive` below four plans in the sample; `stop` when the plans with a hit are more than one in four; `keep` otherwise.

- [ ] **Step 5: Check the note**

Run: `grep -nE '^\*\*(Sample size|Plans with a Critical plan-review finding or a QA fail|Verdict):\*\*' docs/dforge/notes/2026-10-27-review-depth-measurement.md`

Expected: three lines, the last one `**Verdict:** inconclusive`, `**Verdict:** keep` or `**Verdict:** stop`. Then run `grep -c 'dc[c]-darkraise' docs/dforge/notes/2026-10-27-review-depth-measurement.md`. Expected: `0`, because the repository validator rejects that prefix in docs outside `docs/superpowers`.

- [ ] **Step 6: Act on the verdict**

`keep`: nothing more to write.

`stop`: nothing more to write; Step 7 commits the note, and then you end the task with `Status: BLOCKED` and the note's `**Verdict:**` line as the reason. Start no later task.

`inconclusive`: create the register that re-checks the assumption later, then add its deferred row.

```bash
cat > docs/dforge/registers/2026-10-27-review-depth.md <<'EOF'
# dforge: review depth

**Source:** the riskiest assumption of docs/dforge/specs/2026-10-27-review-depth-design.md
**Covers:** docs/dforge/specs/2026-10-27-review-depth-design.md

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
EOF
N=$(sed -n 's/^\*\*Sample size:\*\* //p' docs/dforge/notes/2026-10-27-review-depth-measurement.md)
bash plugins/dforge/scripts/register add docs/dforge/registers/2026-10-27-review-depth.md "Re-check that plans at depth light lose little by skipping plan review and acceptance QA, by comparing the final-review Critical counts of five shipped light plans with standard plans'" --state deferred --note "inconclusive: the sample held $N plans, fewer than the four the measurement needs (docs/dforge/notes/2026-10-27-review-depth-measurement.md); re-check once five light plans have shipped"
bash plugins/dforge/scripts/register check docs/dforge/registers/2026-10-27-review-depth.md
```

Expected from the last command: `register: 0 errors`.

- [ ] **Step 7: Clean up and commit**

```bash
rm -rf .dforge/review-depth-measure
git status --short
```

Expected: only the note, plus the register when the verdict was `inconclusive`.

```bash
git add docs/dforge/notes/2026-10-27-review-depth-measurement.md
[ ! -f docs/dforge/registers/2026-10-27-review-depth.md ] || git add docs/dforge/registers/2026-10-27-review-depth.md
git commit -m "docs(dforge): record the review-depth measurement"
```

- [ ] **Step 8: Prove the task**

Run: `grep -cE '^\*\*Verdict:\*\* (inconclusive|keep|stop)$' docs/dforge/notes/2026-10-27-review-depth-measurement.md`
Expected: `1`.

When the verdict is `inconclusive`, also run `bash plugins/dforge/scripts/register check docs/dforge/registers/2026-10-27-review-depth.md` (expected `register: 0 errors`) and `bash plugins/dforge/scripts/register open --spec docs/dforge/specs/2026-10-27-review-depth-design.md; echo $?` (expected `0`, because a deferred row is not open).

### Task 2: Add lib/depth.sh and the depth-route command

**Files:**
- Create: `plugins/dforge/scripts/lib/depth.sh`
- Create: `plugins/dforge/scripts/depth-route` (executable)
- Create: `plugins/dforge/tests/depth-route.test.sh`
- Create: `plugins/dforge/tests/fixtures/depth-route/spec-light.md`, `spec-standard.md`, `spec-full.md`, `spec-owner-light.md`, `spec-no-depth.md`, `spec-bad-word.md`

**Interfaces:**
- Consumes: `plan_header`, `plan_scores`, `plan_locate`, `plan_apply_amendments`, `plan_amendments_file`, `_plan_ctx` and `$_PLAN_AWK` (`plugins/dforge/scripts/lib/plan.sh`), and `dforge_stores_init` and `dforge_resolve` (`lib/roots.sh`), all as they stand.
- Produces: Contracts C1 (`lib/depth.sh`: `DEPTH_TRIGGERS`, `depth_rank`, `depth_name`, `depth_from_triggers`, `depth_spec_file`, `depth_plan`, `depth_plan_depth`) and C2 (`scripts/depth-route`), exactly as stated there.

**Depends on:** none

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Write the six fixture specs**

Run from the checkout root. Each spec carries the `**Depth:**` line the plan checkpoint reads; `spec-owner-light.md` shows a spec whose body names risk topics and whose line the owner set to light.

```bash
mkdir -p plugins/dforge/tests/fixtures/depth-route
cd plugins/dforge/tests/fixtures/depth-route
cat > spec-light.md <<'EOF'
# Light spec

**Execution strategy:** sequential

**Depth:** light — unenumerable

## Decisions

- Fixture.
EOF
cat > spec-standard.md <<'EOF'
# Standard spec

**Execution strategy:** sequential

**Depth:** standard — interface (set by hand)

## Decisions

- Fixture.
EOF
cat > spec-full.md <<'EOF'
# Full spec

**Execution strategy:** sequential

**Depth:** full — risk

## Decisions

- Fixture.
EOF
cat > spec-owner-light.md <<'EOF'
# Owner spec

**Execution strategy:** sequential

**Depth:** light — owner

## Decisions

- The change touches a migration and a security boundary; the owner still set light.
EOF
cat > spec-no-depth.md <<'EOF'
# Spec without a Depth line

**Execution strategy:** sequential

## Decisions

- Fixture.
EOF
cat > spec-bad-word.md <<'EOF'
# Spec with an unknown depth word

**Execution strategy:** sequential

**Depth:** medium — owner

## Decisions

- Fixture.
EOF
cd ../../../../..
```

- [ ] **Step 2: Write the failing test**

Create `plugins/dforge/tests/depth-route.test.sh` with exactly this content. It builds a throwaway repository under its own `mktemp -d`, copies the fixture specs into it, and writes each fixture plan with the `mkplan` helper.

```bash
#!/usr/bin/env bash
# depth-route is the review-depth rule as code: seven trigger ids give the spec
# checkpoint, and a plan's spec depth and task risk scores give the plan
# checkpoint. Each case below pins one row of that rule.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
ROUTE="$P/scripts/depth-route"
FIX="$HERE/fixtures/depth-route"
. "$P/scripts/lib/plan.sh"
. "$P/scripts/lib/depth.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
absent() { # absent <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected: [%s] in [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# The darkmem cases below set their own home; every other case reads this one,
# never the developer's ~/.dforge.
export HOME="$TMP/home"
mkdir -p "$HOME"

REPO="$TMP/repo"
git init -q "$REPO"
mkdir -p "$REPO/docs/dforge/specs" "$REPO/docs/dforge/plans"
cp "$FIX"/spec-*.md "$REPO/docs/dforge/specs/"

route() { (cd "$REPO" && bash "$ROUTE" "$@" 2>&1); }

# mkplan NAME SPEC EXTRA RISK... — docs/dforge/plans/NAME.md with one task per
# RISK. SPEC is a spec fixture's basename ("" for no Spec line), EXTRA a header
# line ("" for none). A RISK of "-" writes a task with no Evaluation line, "?" an
# Evaluation line that does not parse, and "3t8" risk 3 with a total of 8.
mkplan() {
  local name=$1 spec=$2 extra=$3 n=0 r total
  shift 3
  {
    sed 's/^|//' <<'HEAD'
|# Depth Fixture Plan
|
|**Goal:** Fixture.
|
HEAD
    [ -z "$spec" ] || printf '**Spec:** docs/dforge/specs/%s.md\n\n' "$spec"
    [ -z "$extra" ] || printf '%s\n\n' "$extra"
    printf '## Task index\n\n'
    for r in "$@"; do
      n=$((n + 1))
      printf '### Task %d: fixture task\n\n' "$n"
      case $r in
        -) ;;
        '?') printf '**Evaluation:** files one, spec none\n\n' ;;
        *t*) total=${r#*t}; printf '**Evaluation:** files 1 - spec 1 - coupling 1 - risk %s = %s\n\n' "${r%%t*}" "$total" ;;
        *) printf '**Evaluation:** files 0 - spec 0 - coupling 0 - risk %s = %s\n\n' "$r" "$r" ;;
      esac
    done
  } > "$REPO/docs/dforge/plans/$name.md"
}
plan_line() { route "docs/dforge/plans/$1.md"; }

# --- the library functions ---
check "depth_rank light" "$(depth_rank light)" "0"
check "depth_rank standard" "$(depth_rank standard)" "1"
check "depth_rank full" "$(depth_rank full)" "2"
out=$(depth_rank medium); st=$?
check "depth_rank of another word prints nothing" "$out" ""
check "depth_rank of another word exits 1" "$st" "1"
check "depth_name 0" "$(depth_name 0)" "light"
check "depth_name 1" "$(depth_name 1)" "standard"
check "depth_name 2" "$(depth_name 2)" "full"
out=$(depth_name 3); st=$?
check "depth_name 3 prints nothing, exits 1" "$out:$st" ":1"
check "the seven trigger ids" "${DEPTH_TRIGGERS[*]}" "new-subsystem interface unenumerable approach risk intricate asked"
. "$P/scripts/lib/depth.sh"
check "sourcing the lib twice is harmless" "$?" "0"
check "depth_spec_file reads the first word" "$(depth_spec_file "$FIX/spec-standard.md")" "standard"
check "depth_spec_file of a missing file" "$(depth_spec_file "$TMP/none.md")" "none"
check "depth_spec_file of an unknown word" "$(depth_spec_file "$FIX/spec-bad-word.md")" "none"
check "depth_spec_file with no Depth line" "$(depth_spec_file "$FIX/spec-no-depth.md")" "none"
sed 's/$/\r/' "$FIX/spec-full.md" > "$TMP/crlf-spec.md"
check "depth_spec_file tolerates CRLF" "$(depth_spec_file "$TMP/crlf-spec.md")" "full"

# --- A1: the spec checkpoint ---
check "risk alone is full" "$(route --spec-triggers risk)" "depth=full reason=risk"
check "new-subsystem alone is full" "$(route --spec-triggers new-subsystem)" "depth=full reason=new-subsystem"
check "risk outranks interface" "$(route --spec-triggers interface,risk)" "depth=full reason=risk"
check "both full triggers are named in a fixed order" "$(route --spec-triggers new-subsystem,asked,risk)" "depth=full reason=risk,new-subsystem"
check "interface alone is standard" "$(route --spec-triggers interface)" "depth=standard reason=interface"
check "interface with light triggers is standard" "$(route --spec-triggers unenumerable,interface,approach)" "depth=standard reason=interface"
check "light triggers are all named in the order given" "$(route --spec-triggers intricate,approach)" "depth=light reason=intricate,approach"
for id in unenumerable approach intricate asked; do
  check "$id alone is light" "$(route --spec-triggers $id)" "depth=light reason=$id"
done

# --- A2: the spec checkpoint refuses what it cannot route ---
for bad in "" "," "bogus" "risk,bogus" "Risk"; do
  out=$(route --spec-triggers "$bad"); st=$?
  check "list [$bad] exits 2" "$st" "2"
  absent "list [$bad] prints no depth line" "$out" "depth="
done
check "an empty list says why" "$(route --spec-triggers "")" "depth-route: no trigger given"
check "an unknown id is named" "$(route --spec-triggers interface,bogus)" "depth-route: unknown trigger: bogus"
out=$(route); st=$?
check "no argument exits 2" "$st" "2"
out=$(route --bogus); st=$?
check "an unknown option exits 2" "$st:$out" "2:depth-route: unknown option: --bogus"
out=$(route --spec-triggers); st=$?
check "--spec-triggers without a list exits 2" "$st" "2"
out=$(route docs/dforge/plans/missing.md); st=$?
check "a missing plan exits 2" "$st" "2"
check "a missing plan is named" "${out%%:*}:$(grep -c 'no such plan file' <<<"$out")" "depth-route:1"

# --- A3, A4, A6: the plan checkpoint ---
mkplan l-low spec-light "" 0 1
check "light spec, risks 0 and 1: light" "$(plan_line l-low)" "depth=light spec=light tasks=light reason=spec,task-risk:2"
mkplan l-two spec-light "" 0 2 1
check "light spec, highest risk 2: standard" "$(plan_line l-two)" "depth=standard spec=light tasks=standard reason=task-risk:2"
mkplan l-three spec-light "" 1 3
check "light spec, a risk 3 task: full" "$(plan_line l-three)" "depth=full spec=light tasks=full reason=task-risk:2"
mkplan s-low spec-standard "" 0 1
check "standard spec, low risks: standard" "$(plan_line s-low)" "depth=standard spec=standard tasks=light reason=spec"
mkplan s-two spec-standard "" 2
check "standard spec, risk 2: both inputs named" "$(plan_line s-two)" "depth=standard spec=standard tasks=standard reason=spec,task-risk:1"
mkplan s-three spec-standard "" 3
check "standard spec, risk 3: full" "$(plan_line s-three)" "depth=full spec=standard tasks=full reason=task-risk:1"
mkplan f-zero spec-full "" 0 0
check "full spec, risk 0 tasks: the plan never lowers it" "$(plan_line f-zero)" "depth=full spec=full tasks=light reason=spec"
mkplan f-three spec-full "" 3
check "full spec, risk 3: both inputs named" "$(plan_line f-three)" "depth=full spec=full tasks=full reason=spec,task-risk:1"
mkplan empty spec-light ""
check "a plan with no tasks is light on tasks" "$(plan_line empty)" "depth=light spec=light tasks=light reason=spec"

# --- A4: task count and totals never raise the depth ---
risks=()
for ((i = 1; i <= 40; i++)); do
  if [ $((i % 3)) -eq 0 ]; then risks+=("1t8"); else risks+=("$((i % 2))"); fi
done
mkplan forty spec-light "" "${risks[@]}"
check "40 tasks at risk 1 or below with totals of 8: light" "$(plan_line forty)" "depth=light spec=light tasks=light reason=spec,task-risk:1"

# --- A5: what routes at full ---
mkplan no-spec-line "" "" 0
check "no Spec line: full" "$(plan_line no-spec-line)" "depth=full spec=none tasks=light reason=no-spec-depth"
mkplan no-depth-line spec-no-depth "" 0
check "a spec with no Depth line: full" "$(plan_line no-depth-line)" "depth=full spec=none tasks=light reason=no-spec-depth"
mkplan bad-word spec-bad-word "" 0
check "a spec whose Depth word is unknown: full" "$(plan_line bad-word)" "depth=full spec=none tasks=light reason=no-spec-depth"
mkplan gone-spec spec-gone "" 0
check "a Spec path that does not exist: full" "$(plan_line gone-spec)" "depth=full spec=none tasks=light reason=no-spec-depth"
mkplan no-spec-risk3 "" "" 3
check "no spec depth and a risk 3 task name both" "$(plan_line no-spec-risk3)" "depth=full spec=none tasks=full reason=no-spec-depth,task-risk:1"
mkplan unscored spec-light "" 1 -
check "a task with no Evaluation line: full" "$(plan_line unscored)" "depth=full spec=light tasks=full reason=unscored:2"
mkplan unparsable spec-light "" '?' 0
check "an unparsable Evaluation line: full" "$(plan_line unparsable)" "depth=full spec=light tasks=full reason=unscored:1"
mkplan unscored-risk3 spec-light "" - 3
check "an unscored task is named before a risk 3 task" "$(plan_line unscored-risk3)" "depth=full spec=light tasks=full reason=unscored:1"
mkplan codex spec-light "Host: codex" 0
check "Host: codex: full" "$(plan_line codex)" "depth=full spec=light tasks=light reason=codex-host"
mkplan codex-bold spec-full "**Host:** codex" 3
check "a bold Host: codex line is read, and names only codex-host" "$(plan_line codex-bold)" "depth=full spec=full tasks=full reason=codex-host"

# --- A13: an owner line is the spec's depth ---
mkplan owner-low spec-owner-light "" 1
check "an owner light line is spec=light" "$(plan_line owner-low)" "depth=light spec=light tasks=light reason=spec,task-risk:1"
mkplan owner-two spec-owner-light "" 2
check "a risk 2 task still raises an owner light spec" "$(plan_line owner-two)" "depth=standard spec=light tasks=standard reason=task-risk:1"
mkplan owner-three spec-owner-light "" 3
check "a risk 3 task still raises an owner light spec to full" "$(plan_line owner-three)" "depth=full spec=light tasks=full reason=task-risk:1"

# --- A3: the plan is read with its amendments applied ---
mkplan amend spec-light "" 1 1
check "before the amendment: light" "$(plan_line amend)" "depth=light spec=light tasks=light reason=spec,task-risk:1"
mkdir -p "$REPO/.dforge/sdd/amend"
sed 's/^|//' > "$REPO/.dforge/sdd/amend/amendments.md" <<'AMEND'
|## A1 — Task 2
|
|### Old
|
|````
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 1 = 1
|````
|
|### New
|
|````
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 3 = 3
|````
AMEND
check "after the amendment: full" "$(plan_line amend)" "depth=full spec=light tasks=full reason=task-risk:2"
sed 's/risk 1 = 1/risk 2 = 2/' "$REPO/.dforge/sdd/amend/amendments.md" > "$TMP/broken-amend.md"
cp "$TMP/broken-amend.md" "$REPO/.dforge/sdd/amend/amendments.md"
out=$(plan_line amend); st=$?
check "an amendment that does not apply exits 2" "$st:$out" "2:depth-route: an amendment does not apply; run plan-lint"
rm -rf "$REPO/.dforge/sdd/amend"

# --- A16: the Depth line is read by its first word, in the darkmem mirror too ---
mkplan first-word spec-standard "" 0
check "a Depth line with trailing text gives spec=standard" "$(plan_line first-word | grep -o 'spec=[a-z]*')" "spec=standard"
sed 's/$/\r/' "$REPO/docs/dforge/specs/spec-light.md" > "$REPO/docs/dforge/specs/spec-crlf.md"
mkplan crlf spec-crlf "" 0
check "a CRLF spec is read" "$(plan_line crlf | grep -o 'spec=[a-z]*')" "spec=light"

. "$HERE/fixtures/darkmem-stores.sh"
SH="$TMP/stores-home"; mkdir -p "$SH"
SR="$TMP/stores-repo"; git init -q "$SR"
M=$(stores_home "$SH" "$SR" proj darkmem darkmem)
mkdir -p "$M/dforge/specs" "$M/dforge/plans"
cp "$FIX/spec-standard.md" "$M/dforge/specs/s.md"
printf '# P\n\n**Goal:** Fixture.\n\n**Spec:** docs/dforge/specs/s.md\n\n## Task index\n\n### Task 1: One\n\n**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0\n' > "$M/dforge/plans/p.md"
out=$(cd "$SR" && HOME=$SH bash "$ROUTE" docs/dforge/plans/p.md 2>&1)
check "a spec in the darkmem mirror resolves as plan-lint resolves it" "$out" "depth=standard spec=standard tasks=light reason=spec"
out=$(cd "$SR" && HOME=$SH bash "$ROUTE" "$M/dforge/plans/p.md" 2>&1)
check "the mirror plan is also found by its absolute path" "$out" "depth=standard spec=standard tasks=light reason=spec"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/depth-route.test.sh; echo "status=$?"`
Expected: the suite fails or aborts early (the lib and the script do not exist yet, so an unbound name may stop it under `set -u`), with a non-zero `status=`.

- [ ] **Step 4: Write the library**

Create `plugins/dforge/scripts/lib/depth.sh`:

```bash
# Review depth: the one rule that sizes the spec, plan and final-review stages
# of an architectural plan as light, standard or full. Sourced after
# lib/plan.sh by depth-route, review-route and lens-route, so the three agree
# and none shells out to another. Defines functions only.

[ -n "${DEPTH_TRIGGERS+x}" ] || readonly -a DEPTH_TRIGGERS=(new-subsystem interface unenumerable approach risk intricate asked)

# depth_rank DEPTH — 0, 1 or 2 for light, standard, full; status 1 otherwise.
depth_rank() {
  case ${1:-} in
    light) echo 0 ;;
    standard) echo 1 ;;
    full) echo 2 ;;
    *) return 1 ;;
  esac
}

# depth_name RANK — the depth a rank names; status 1 for any other value.
depth_name() {
  case ${1:-} in
    0) echo light ;;
    1) echo standard ;;
    2) echo full ;;
    *) return 1 ;;
  esac
}

# depth_from_triggers LIST — "<depth><TAB><reason>" for a comma-separated list
# of trigger ids. Status 2 and a stderr message, with no stdout, for an empty
# list or an id outside DEPTH_TRIGGERS.
depth_from_triggers() {
  local ids=() id known t risk=0 sub=0 iface=0 reason
  IFS=, read -ra ids <<<"${1:-}"
  local given=()
  for id in "${ids[@]}"; do
    [ -z "$id" ] || given+=("$id")
  done
  if [ "${#given[@]}" -eq 0 ]; then
    echo "no trigger given" >&2
    return 2
  fi
  for id in "${given[@]}"; do
    known=0
    for t in "${DEPTH_TRIGGERS[@]}"; do
      [ "$t" != "$id" ] || known=1
    done
    if [ "$known" -eq 0 ]; then
      echo "unknown trigger: $id" >&2
      return 2
    fi
    case $id in
      risk) risk=1 ;;
      new-subsystem) sub=1 ;;
      interface) iface=1 ;;
    esac
  done
  if [ "$risk" -eq 1 ] || [ "$sub" -eq 1 ]; then
    reason=""
    [ "$risk" -eq 0 ] || reason=risk
    [ "$sub" -eq 0 ] || reason="${reason:+$reason,}new-subsystem"
    printf 'full\t%s\n' "$reason"
  elif [ "$iface" -eq 1 ]; then
    printf 'standard\tinterface\n'
  else
    reason=$(IFS=,; printf '%s' "${given[*]}")
    printf 'light\t%s\n' "$reason"
  fi
}

# depth_spec_file SPEC_FILE — the first word after **Depth:** on the first line
# that begins with it, when that word is a depth; "none" for a missing file, no
# such line, or any other word. awk reads to the end rather than exiting early:
# an early exit can leave tr on a closed pipe, which pipefail reports.
depth_spec_file() {
  local word=""
  if [ -f "${1:-}" ]; then
    word=$(tr -d '\r' < "$1" | awk '
      !done && /^\*\*Depth:\*\*/ { sub(/^\*\*Depth:\*\*[ \t]*/, ""); print $1; done = 1 }')
  fi
  case $word in
    light|standard|full) printf '%s\n' "$word" ;;
    *) echo none ;;
  esac
}

# depth_plan SRC ROOT — the plan checkpoint for SRC, a plan file with its
# amendments applied, whose **Spec:** path resolves against the checkout ROOT:
#   depth=<d> spec=<d|none> tasks=<d> reason=<items>
# The plan never lowers the spec's depth; a missing spec depth or a Host: codex
# header raises it to full.
depth_plan() {
  local src=$1 root=$2 header spec_line spec_path spec_file spec tasks depth
  local codex=0 n t r hi=-1 hi_task="" unscored="" reasons=()
  header=$(plan_header "$src")
  grep -qE '^(\*\*)?Host:(\*\*)?[ \t]+codex[ \t]*$' <<<"$header" && codex=1

  spec_line=$(awk "$_PLAN_AWK"'
    in_fence($0) { next }
    !done && index($0, "**Spec:**") == 1 { print; done = 1 }' <<<"$header")
  spec=none
  if [ -n "$spec_line" ]; then
    spec_path=$(sed -E 's/^\*\*Spec:\*\*[ \t]*(`([^`]+)`|([^ \t]+)).*/\2\3/' <<<"$spec_line")
    if [ -n "$spec_path" ] && [ "$spec_path" != "$spec_line" ]; then
      dforge_stores_init "$root"
      spec_file=$(dforge_resolve "$spec_path" "$root")
      spec=$(depth_spec_file "$spec_file")
    fi
  fi

  while IFS=$'\t' read -r n t r; do
    [ -n "$n" ] || continue
    if [ "$r" = "-" ] || [ "$r" = "?" ]; then
      [ -n "$unscored" ] || unscored=$n
    elif [ "$r" -gt "$hi" ]; then
      hi=$r hi_task=$n
    fi
  done < <(plan_scores "$src")
  if [ -n "$unscored" ] || [ "$hi" -ge 3 ]; then tasks=full
  elif [ "$hi" -eq 2 ]; then tasks=standard
  else tasks=light
  fi

  if [ "$codex" -eq 1 ] || [ "$spec" = none ]; then depth=full
  elif [ "$(depth_rank "$spec")" -ge "$(depth_rank "$tasks")" ]; then depth=$spec
  else depth=$tasks
  fi

  if [ "$codex" -eq 1 ]; then
    reasons=(codex-host)
  else
    [ "$spec" != none ] || reasons+=(no-spec-depth)
    [ "$spec" != "$depth" ] || reasons+=(spec)
    if [ -n "$unscored" ]; then
      reasons+=("unscored:$unscored")
    elif [ "$tasks" = "$depth" ] && [ -n "$hi_task" ]; then
      reasons+=("task-risk:$hi_task")
    fi
  fi
  printf 'depth=%s spec=%s tasks=%s reason=%s\n' "$depth" "$spec" "$tasks" "$(IFS=,; printf '%s' "${reasons[*]}")"
}

# depth_plan_depth SRC ROOT — only the depth of depth_plan.
depth_plan_depth() {
  local line
  line=$(depth_plan "$1" "$2") || return $?
  line=${line#depth=}
  printf '%s\n' "${line%% *}"
}
```

- [ ] **Step 5: Write the command**

Create `plugins/dforge/scripts/depth-route` and make it executable (`chmod +x plugins/dforge/scripts/depth-route`):

```bash
#!/usr/bin/env bash
# Print the review depth that sizes an architectural plan's spec phase, plan
# phase and final review.
#
# The rule lives in lib/depth.sh, called from a script rather than written in
# skill prose, for the reason review-route gives: a rule a session must follow
# is only reachable when a test can reach it. review-route and lens-route read
# the same rule when they route.
#
# Usage: depth-route --spec-triggers LIST
#        depth-route PLAN_FILE
# LIST is comma-separated Process Depth trigger ids: new-subsystem, interface,
# unenumerable, approach, risk, intricate, asked.
# Output: depth=<light|standard|full> reason=<id>[,<id>...]
#         (PLAN_FILE adds, before reason=: spec=<light|standard|full|none>
#         tasks=<light|standard|full>; the plan is read with its amendments.md
#         applied)
# Exit: 0 routed; 2 usage error, an empty or unknown trigger list, a missing
# plan file, or an amendment that does not apply.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/plan.sh"
. "$HERE/lib/depth.sh"

die() { printf 'depth-route: %s\n' "$1" >&2; exit 2; }
usage() { die "usage: depth-route --spec-triggers LIST | PLAN_FILE"; }

[ $# -ge 1 ] || usage
case $1 in
  --spec-triggers)
    [ $# -eq 2 ] || usage
    out=$(depth_from_triggers "$2" 2>&1) || die "$out"
    IFS=$'\t' read -r depth reason <<<"$out"
    printf 'depth=%s reason=%s\n' "$depth" "$reason"
    exit 0 ;;
  -*) die "unknown option: $1" ;;
esac
[ $# -eq 1 ] || usage

plan=$(plan_locate "$1")
[ -f "$plan" ] || die "no such plan file: $plan"
dforge_stores_init "$(_plan_ctx "$plan")"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
src="$TMP/plan.md"
plan_apply_amendments "$plan" "$(plan_amendments_file "$plan")" > "$src" 2>/dev/null \
  || die "an amendment does not apply; run plan-lint"
root=$(git -C "$(dirname "$plan")" rev-parse --show-toplevel 2>/dev/null || pwd)

depth_plan "$src" "$root"
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `timeout 300 bash plugins/dforge/tests/depth-route.test.sh | tail -3`
Expected: the last line reads `74 passed, 0 failed`.

- [ ] **Step 7: Check the repository still validates and the script parses**

Run: `bash -n plugins/dforge/scripts/depth-route && bash -n plugins/dforge/scripts/lib/depth.sh && timeout 300 node scripts/validate-repository.mjs | tail -2`
Expected: no output from `bash -n`, then `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`

- [ ] **Step 8: Commit**

```bash
git add plugins/dforge/scripts/lib/depth.sh plugins/dforge/scripts/depth-route plugins/dforge/tests/depth-route.test.sh plugins/dforge/tests/fixtures/depth-route
git commit -m "feat(dforge): add depth-route and lib/depth.sh"
```

Check that proves the task: `timeout 300 bash plugins/dforge/tests/depth-route.test.sh | tail -1` prints `74 passed, 0 failed`, and `git ls-files -s plugins/dforge/scripts/depth-route` shows mode `100755`.

### Task 3: Take review-route's plan-round cap from the depth

**Files:**
- Modify: `plugins/dforge/scripts/review-route`
- Modify: `plugins/dforge/tests/review-route.test.sh`

**Interfaces:**
- Consumes: Contracts C1 (`depth_plan_depth SRC ROOT` from `plugins/dforge/scripts/lib/depth.sh`, built by Task 2) and the behavior C3 specifies.
- Produces: Contracts C3 (`review-route PLAN_FILE --plan-round R` on a Claude plan takes `cap=` from the depth: light 0, standard 1, full 2; at light, round 1 prints `primary=none ... reason=depth-light cap=0`). Task 5 writes this output into `skills/writing-plans/SKILL.md`, and Task 11 pins it.

**Depends on:** Task 2

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

Today a Claude plan's plan-review cap is a flat 2. This task makes it follow the plan's depth, so a light plan runs no plan-review round and a standard plan runs one. A `Host: codex` plan keeps its native cap rule, and every other `review-route` mode is untouched. A Claude plan has no cap-critical round, so a round past the cap exits 2 at every depth; that is already how the script treats a round 3 and stays so.

- [ ] **Step 1: Write the failing tests**

All edits are in `plugins/dforge/tests/review-route.test.sh`. The first edit renames the label of one existing assertion, whose expected value does not change: its fixture has an unparsable Evaluation line, which now routes the plan at full. The block that follows builds the specs and plans it needs in a throwaway git repository under the suite's own `$TMP`, so the plans' `**Spec:**` paths resolve.

Edit 1. Replace this single line:

```bash
check "a Claude plan round reads no Evaluation line" "$rc:$out" "0:review-seat plan-round=1 primary=codex:plan fallback=dforge:judge-opus reason=round cap=2"
```

with the following block (its first line is the same assertion under its new label, and the rest is new):

```bash
check "a Claude plan round with an unparsable Evaluation line routes at full: cap 2" "$rc:$out" "0:review-seat plan-round=1 primary=codex:plan fallback=dforge:judge-opus reason=round cap=2"

# --- the plan-round cap follows the depth ----------------------------------------
# A Claude plan's cap is 0 at light, 1 at standard, 2 at full (lib/depth.sh): the
# higher of its spec's Depth line and its riskiest task. The specs live in a
# throwaway repository so the plans' **Spec:** paths resolve.
git init -q "$TMP/drepo"
mkdir -p "$TMP/drepo/specs"
for d in light standard full; do
  printf '# Spec\n\n**Depth:** %s — fixture\n' "$d" > "$TMP/drepo/specs/$d.md"
done
depth_fixture() { # depth_fixture <file> <spec name> <evaluation line>... - one task per line
  local f=$1 spec=$2 i=0 ev; shift 2
  { printf '# Depth Fixture\n\n**Spec:** `specs/%s.md`\n\n' "$spec"
    for ev in "$@"; do i=$((i + 1)); printf '### Task %s: t\n\n%s\n\n' "$i" "$ev"; done
  } > "$f"
}
EV0='**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1'
EV1='**Evaluation:** files 0 - spec 0 - coupling 1 - risk 1 = 2'
EV2='**Evaluation:** files 0 - spec 0 - coupling 1 - risk 2 = 3'
EV3='**Evaluation:** files 0 - spec 0 - coupling 1 - risk 3 = 4'
depth_fixture "$TMP/drepo/light.md" light "$EV0" "$EV1"
depth_fixture "$TMP/drepo/light-r2.md" light "$EV0" "$EV2"
depth_fixture "$TMP/drepo/light-r3.md" light "$EV0" "$EV3"
depth_fixture "$TMP/drepo/light-bad.md" light "$EV0" '**Evaluation:** one plus one'
depth_fixture "$TMP/drepo/standard.md" standard "$EV0"
depth_fixture "$TMP/drepo/full.md" full "$EV0"
depth_fixture "$TMP/drepo/missing.md" missing "$EV0"
rround "$TMP/drepo/light.md" 1
check "light: round 1 runs no review" "$rc:$out" "0:review-seat plan-round=1 primary=none fallback=- reason=depth-light cap=0"
rround "$TMP/drepo/light.md" 2
check "light: round 2 exits 2" "$rc" "2"
present "light: round 2 names the cap" "$TMP/err" "past the cap (0)"
rround "$TMP/drepo/light-r2.md" 1
check "a light spec with a risk-2 task is standard: cap 1" "$out" "review-seat plan-round=1 primary=codex:plan fallback=dforge:judge-opus reason=round cap=1"
rround "$TMP/drepo/light-r2.md" 2
check "standard: round 2 exits 2" "$rc" "2"
present "standard: round 2 names the cap" "$TMP/err" "past the cap (1)"
rround "$TMP/drepo/standard.md" 1
check "a standard spec with a risk-0 task: cap 1" "$out" "review-seat plan-round=1 primary=codex:plan fallback=dforge:judge-opus reason=round cap=1"
rround "$TMP/drepo/light-r3.md" 2
check "a light spec with a risk-3 task is full: round 2 within cap 2" "$out" "review-seat plan-round=2 primary=dforge:judge-opus fallback=- reason=round cap=2"
rround "$TMP/drepo/light-r3.md" 3
check "full: a Claude plan has no round 3" "$rc" "2"
rround "$TMP/drepo/full.md" 1
check "a full spec with a risk-0 task stays at cap 2" "$out" "review-seat plan-round=1 primary=codex:plan fallback=dforge:judge-opus reason=round cap=2"
rround "$TMP/drepo/light-bad.md" 1
check "a light spec with an unparsable task routes at full: cap 2" "$out" "review-seat plan-round=1 primary=codex:plan fallback=dforge:judge-opus reason=round cap=2"
rround "$TMP/drepo/missing.md" 1
check "a Spec path that does not exist routes at full: cap 2" "$out" "review-seat plan-round=1 primary=codex:plan fallback=dforge:judge-opus reason=round cap=2"
review_surface false
rround "$TMP/drepo/light.md" 1
check "light with Codex off: still no review round" "$rc:$out" "0:review-seat plan-round=1 primary=none fallback=- reason=depth-light cap=0"
rround "$TMP/drepo/standard.md" 1
check "standard with Codex off: round 1 goes to Opus alone, cap 1" "$out" "review-seat plan-round=1 primary=dforge:judge-opus fallback=- reason=codex-off cap=1"
review_surface true
```

Edit 2. Directly above the line `native --task 1`, which is followed by the line `check "native: a task seat still exits 2" "$rc" "2"`, insert:

```bash
sed '/^\*\*Routing policy:\*\*/a **Spec:** `specs/light.md`' "$FF/docs/native.md" > "$TMP/drepo/native-light.md"
rround "$TMP/drepo/native-light.md" 1
check "native plan round: a light spec leaves the native cap alone" "$rc:$out" \
  "0:review-seat plan-round=1 primary=native:gpt-6-astra/high fallback=- reason=round cap=2"
rround "$TMP/drepo/native-light.md" 3
check "native plan round: a light spec keeps the cap-critical round" "$out" \
  "review-seat plan-round=3 primary=native:gpt-6-astra/high fallback=- reason=cap-critical cap=2"
```

- [ ] **Step 2: Run the suite to verify the new cases fail**

Run: `timeout 300 bash plugins/dforge/tests/review-route.test.sh 2>&1 | grep -E '^FAIL|passed'`
Expected: FAIL lines, among them `light: round 1 runs no review`, `light: round 2 names the cap`, `a light spec with a risk-2 task is standard: cap 1`, and a final line with a non-zero failed count. The assertions that already existed still print `ok`.

- [ ] **Step 3: Implement the depth cap in review-route**

Apply these five edits to `plugins/dforge/scripts/review-route`. They source `lib/depth.sh`, add `claude_cap`, and route round 1 at cap 0 to the `depth-light` line before the past-the-cap check can refuse it. `claude_cap` locates the checkout root the way `depth-route` does (the plan's git top level, else the working directory) and treats a depth that does not print as full.

Edit 1 in `plugins/dforge/scripts/review-route`. Replace this exact text:

```text
# Output: review-seat <scope> primary=<seat> fallback=<seat|-> reason=<why>
#         (a plan round appends cap=<n>; a single --task ID puts
#         review=<task|group> before reason=)
```

with:

```text
# Output: review-seat <scope> primary=<seat> fallback=<seat|-> reason=<why>
#         (a plan round appends cap=<n>; a single --task ID puts
#         review=<task|group> before reason=)
# A Claude plan's round cap comes from scripts/depth-route's depth: light 0,
# standard 1, full 2. At cap 0 round 1 prints primary=none reason=depth-light,
# meaning no review round runs; any round past the cap exits 2.
```

Edit 2 in `plugins/dforge/scripts/review-route`. Replace this exact text:

```text
. "$HERE/lib/plan.sh"
. "$HERE/lib/executor-session.sh"
```

with:

```text
. "$HERE/lib/plan.sh"
. "$HERE/lib/depth.sh"
. "$HERE/lib/executor-session.sh"
```

Edit 3 in `plugins/dforge/scripts/review-route`. Replace this exact text:

```text
# plan_shape — sets intricate (1 when a task is at risk 3 or totals 6) for
# --ruling. It no longer sets cap: a Claude plan's review cap is a flat 2.
```

with:

```text
# plan_shape — sets intricate (1 when a task is at risk 3 or totals 6) for
# --ruling. It sets no cap: a Claude plan's review cap comes from claude_cap.
```

Edit 4 in `plugins/dforge/scripts/review-route`. Replace this exact text:

```text
# cap_for MAX — a Codex-host plan's review cap from its highest raw task total;
```

with:

```text
# claude_cap — a Claude plan's review cap from its depth (lib/depth.sh): light
# 0, standard 1, full 2. A depth that does not print takes the full cap.
claude_cap() {
  local root depth
  root=$(git -C "$(dirname "$plan")" rev-parse --show-toplevel 2>/dev/null) || root=$PWD
  depth=$(depth_plan_depth "$src" "$root")
  case $depth in light) cap=0 ;; standard) cap=1 ;; *) cap=2 ;; esac
}

# cap_for MAX — a Codex-host plan's review cap from its highest raw task total;
```

Edit 5 in `plugins/dforge/scripts/review-route`. Replace this exact text:

```text
    # A Claude plan's cap is 2 whatever its totals, with no cap-critical round,
    # so it reads no Evaluation line.
    if [ "$native" -eq 1 ]; then native_shape; else cap=2; fi
    if [ "$native" -eq 0 ] && [ "$r" -gt "$cap" ]; then
```

with:

```text
    # A Claude plan's cap follows its depth, never its totals, and it has no
    # cap-critical round: a round past the cap exits 2.
    if [ "$native" -eq 1 ]; then native_shape; else claude_cap; fi
    if [ "$native" -eq 0 ] && [ "$cap" -eq 0 ] && [ "$r" -eq 1 ]; then
      printf 'review-seat plan-round=1 primary=none fallback=- reason=depth-light cap=0\n'
    elif [ "$native" -eq 0 ] && [ "$r" -gt "$cap" ]; then
```

- [ ] **Step 4: Run the suite and the suites that call review-route**

Run: `timeout 300 bash plugins/dforge/tests/review-route.test.sh 2>&1 | tail -3`
Expected: `0 failed`.

Then run each of these under its own `timeout 600`, one at a time:

```bash
for t in faster-plans.acceptance inline-mode next-step process-roles task-step codex-gate executor-session working-directory; do
  printf '%s: ' "$t"; timeout 600 bash "plugins/dforge/tests/$t.test.sh" 2>&1 | tail -1
done
```

Expected: every line ends `0 failed`. The existing `cap=2` assertions in `faster-plans.acceptance` (its A17) pass unchanged, because those fixture plans hold a risk-3 task (and carry no spec with a Depth line), so they route at full.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/review-route plugins/dforge/tests/review-route.test.sh
git commit -m "feat(dforge): cap plan review by depth"
```

### Task 4: Route final-review lenses by depth in lens-route

**Files:**
- Modify: `plugins/dforge/scripts/lens-route`
- Modify: `plugins/dforge/tests/lens-route.test.sh`

**Interfaces:**
- Consumes: Contracts C1 (`depth_plan_depth SRC ROOT` from `plugins/dforge/scripts/lib/depth.sh`, built by Task 2) and the behavior C4 specifies.
- Produces: Contracts C4 (`lens-route PLAN_FILE --final BASE HEAD` at light prints a `lens` line only for `security`, when its Applies clause matches, and `lens-skipped <id> reason=depth` for every other lens that applied; at standard the cap is the smaller of `lensCap` and 2). Task 7 writes this into `reference/final-review.md`, and Task 11 pins it.

**Depends on:** Task 2

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 2 = 4

`lens-route --final` today prints up to `lensCap` lenses whatever the plan. After this task it reads the plan's depth: light keeps security only, standard keeps at most two lenses, full is unchanged. `lenses off` (a `lensCap` of 0), the `lens-floor` line and `--task` keep their rules; the floor still counts the `lens` lines printed.

- [ ] **Step 1: Write the failing tests**

Edit `plugins/dforge/tests/lens-route.test.sh`. Directly above the line `# --- the ui-ux lens (dforge:ui-ux) ---`, insert the block below. It runs in the suite's first throwaway repository (the working directory at that point), where `$BASE`, `$HEAD1` and `$HEAD2` are already set. Fixture plan lines carry a leading `|` that `sed` strips, as the suite's other fixtures do. The last cases copy the script tree into `$TMP` and narrow security's Applies clause in the copy, to prove that light prints no `lens` line for security when the clause does not match.

```bash
# --- the depth of the plan sizes the final lenses ---
# A plan's depth is the higher of its spec's Depth line and its riskiest task
# (lib/depth.sh). Light keeps security only, standard at most two lenses, full
# up to lensCap. The change set is HEAD2's: shell, a TypeScript test and a README.
mkdir -p specs
for d in light standard full; do
  printf '# Spec\n\n**Depth:** %s — fixture\n' "$d" > "specs/$d.md"
done
write_depth_plan() { # write_depth_plan <file> <spec name> <risk> - a one-task plan
  sed 's/^|//' > "$1" <<EOF2
|# Depth Fixture Plan
|
|**Spec:** \`specs/$2.md\`
|
|## Task index
|
|1. only
|
|### Task 1: only
|
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk $3 = $3
EOF2
}
write_depth_plan light-plan.md light 0
write_depth_plan standard-plan.md standard 0
write_depth_plan full-plan.md full 0
write_depth_plan light-risk2.md light 2
write_depth_plan light-risk3.md light 3
sed '/^\*\*Spec:\*\*/d' light-plan.md > nospec-plan.md
out=$(bash "$ROUTE" light-plan.md --final "$BASE" "$HEAD2")
check "light: security only, every other applicable lens skipped for its depth" "$(short <<<"$out")" \
  "lens security;lens-skipped silent-failures reason=depth;lens-skipped test-quality reason=depth;lens-skipped lang-bash reason=depth;lens-skipped lang-typescript reason=depth;lens-skipped docs-comments reason=depth;"
out=$(DFORGE_LENS_CAP=1 bash "$ROUTE" light-plan.md --final "$BASE" "$HEAD2")
check "light: lensCap 1 still keeps security" "$(grep -c '^lens security ' <<<"$out")" "1"
out=$(DFORGE_LENS_CAP=0 bash "$ROUTE" light-plan.md --final "$BASE" "$HEAD2")
check "light: lensCap 0 is still lenses off" "$out" "lenses off"
out=$(DFORGE_LENS_MINOR_FROM=4 bash "$ROUTE" light-plan.md --final "$BASE" "$HEAD1")
check "light: the floor counts the one lens printed" "$(short <<<"$out")" \
  "lens security;lens-skipped lang-bash reason=depth;lens-floor important tasks=1 from=4;"
out=$(bash "$ROUTE" standard-plan.md --final "$BASE" "$HEAD2")
check "standard: two lenses, the rest past the cap" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens-skipped test-quality reason=cap;lens-skipped lang-bash reason=cap;lens-skipped lang-typescript reason=cap;lens-skipped docs-comments reason=cap;"
out=$(DFORGE_LENS_CAP=1 bash "$ROUTE" standard-plan.md --final "$BASE" "$HEAD2")
check "standard: a lower lensCap wins" "$(grep -c '^lens ' <<<"$out")" "1"
out=$(DFORGE_LENS_CAP=3 bash "$ROUTE" standard-plan.md --final "$BASE" "$HEAD2")
check "standard: a lensCap of 3 is cut to 2" "$(grep -c '^lens ' <<<"$out")" "2"
out=$(bash "$ROUTE" full-plan.md --final "$BASE" "$HEAD2")
check "full: the default cap of 4, as before" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens test-quality;lens lang-bash;lens-skipped lang-typescript reason=cap;lens-skipped docs-comments reason=cap;"
out=$(bash "$ROUTE" light-risk2.md --final "$BASE" "$HEAD2")
check "a light spec with a risk-2 task is standard: two lenses" "$(grep -c '^lens ' <<<"$out")" "2"
out=$(bash "$ROUTE" light-risk3.md --final "$BASE" "$HEAD2")
check "a light spec with a risk-3 task is full: four lenses" "$(grep -c '^lens ' <<<"$out")" "4"
out=$(bash "$ROUTE" nospec-plan.md --final "$BASE" "$HEAD2")
check "a risk-0 plan with no Spec line routes at full" "$(grep -c '^lens ' <<<"$out")" "4"
# Security applies by its Applies clause; a copy of the script tree with a
# narrower clause shows light printing no lens line when it does not match.
mkdir -p "$TMP/plug/criteria"
cp -R "$HERE/../scripts" "$HERE/../config" "$TMP/plug/"
cp -R "$HERE/../criteria/lenses" "$TMP/plug/criteria/lenses"
sed 's/^Applies: always$/Applies: paths nothing\/*/' "$HERE/../criteria/lenses/security.md" > "$TMP/plug/criteria/lenses/security.md"
out=$(bash "$TMP/plug/scripts/lens-route" light-plan.md --final "$BASE" "$HEAD2")
check "light: security prints nothing when its Applies clause does not match" "$(short <<<"$out")" \
  "lens-skipped silent-failures reason=depth;lens-skipped test-quality reason=depth;lens-skipped lang-bash reason=depth;lens-skipped lang-typescript reason=depth;lens-skipped docs-comments reason=depth;"
{ cat light-plan.md; printf '**Lenses:** lang-bash\n'; } > light-lenses.md
out=$(bash "$ROUTE" light-lenses.md --task 1); status=$?
check "light: --task names its lenses as before" "$status:$(sed -E 's/ criteria=[^ ]*//' <<<"$out")" "0:lens lang-bash"
```

- [ ] **Step 2: Run the suite to verify the new cases fail**

Run: `timeout 300 bash plugins/dforge/tests/lens-route.test.sh 2>&1 | grep -E '^FAIL|passed'`
Expected: FAIL lines, among them `light: security only, every other applicable lens skipped for its depth` and `standard: two lenses, the rest past the cap`, and a final line with a non-zero failed count.

- [ ] **Step 3: Implement the depth routing in lens-route**

Apply these five edits to `plugins/dforge/scripts/lens-route`. The depth is read once, after the `lenses off` check, so a `lensCap` of 0 never pays for it. At light every lens other than security that applied prints `lens-skipped <id> reason=depth`; security is first in the lens order, so a `lensCap` of 1 or more always keeps it. At standard the cap is cut to 2 before the loop, so lenses past it print `reason=cap` as before.

Edit 1 in `plugins/dforge/scripts/lens-route`. Replace this exact text:

```text
# Output: lens <id> criteria=<path> seat=<seat> reason=<always|paths:<glob>|added|ui-paths>
#         lens-skipped <id> reason=cap      (--final, past the lensCap setting)
```

with:

```text
# Output: lens <id> criteria=<path> seat=<seat> reason=<always|paths:<glob>|added|ui-paths>
#         lens-skipped <id> reason=cap      (--final, past the lensCap setting, or
#                                           at standard depth past 2 lenses)
#         lens-skipped <id> reason=depth    (--final, a lens other than security
#                                           that applied, at light depth)
```

Edit 2 in `plugins/dforge/scripts/lens-route`. Replace this exact text:

```text
# Exit: 0 routed, also when no lens applies; 2 usage error, a missing plan or
# task, an unknown lens id, or a Host: codex plan.
```

with:

```text
# The depth (scripts/depth-route) sizes --final: light keeps only security,
# standard keeps at most 2 lenses, full keeps up to lensCap.
# Exit: 0 routed, also when no lens applies; 2 usage error, a missing plan or
# task, an unknown lens id, or a Host: codex plan.
```

Edit 3 in `plugins/dforge/scripts/lens-route`. Replace this exact text:

```text
. "$HERE/lib/plan.sh"
. "$HERE/lib/dforge-env.sh"
```

with:

```text
. "$HERE/lib/plan.sh"
. "$HERE/lib/depth.sh"
. "$HERE/lib/dforge-env.sh"
```

Edit 4 in `plugins/dforge/scripts/lens-route`. Replace this exact text:

```text
    if [ "$cap" -eq 0 ]; then echo "lenses off"; exit 0; fi
```

with:

```text
    if [ "$cap" -eq 0 ]; then echo "lenses off"; exit 0; fi
    depth=$(depth_plan_depth "$src" "$(git -C "$(dirname "$plan")" rev-parse --show-toplevel 2>/dev/null || pwd)")
    if [ "$depth" = standard ] && [ "$cap" -gt 2 ]; then cap=2; fi
```

Edit 5 in `plugins/dforge/scripts/lens-route`. Replace this exact text:

```text
      reason=$(lens_match "$id") || continue
      if [ "$n" -lt "$cap" ]; then
```

with:

```text
      reason=$(lens_match "$id") || continue
      if [ "$depth" = light ] && [ "$id" != security ]; then
        printf 'lens-skipped %s reason=depth\n' "$id"
      elif [ "$n" -lt "$cap" ]; then
```

- [ ] **Step 4: Run the suite and the suites that call lens-route**

Run: `timeout 300 bash plugins/dforge/tests/lens-route.test.sh 2>&1 | tail -3`
Expected: `0 failed`.

Then run each of these under its own `timeout 600`, one at a time:

```bash
for t in process-roles task-step-text ui-ux-skill.acceptance task-loop-steps.acceptance task-step; do
  printf '%s: ' "$t"; timeout 600 bash "plugins/dforge/tests/$t.test.sh" 2>&1 | tail -1
done
```

Expected: every line ends `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/scripts/lens-route plugins/dforge/tests/lens-route.test.sh
git commit -m "feat(dforge): route final lenses by depth"
```

### Task 5: Size the plan phase by depth in writing-plans and handoff

**Files:**
- Modify: `plugins/dforge/skills/writing-plans/SKILL.md`
- Modify: `plugins/dforge/skills/handoff/SKILL.md`

**Interfaces:**
- Consumes: Contracts C2 (the `depth-route PLAN_FILE` output line, built by Task 2), C3 (the `primary=none ... reason=depth-light cap=0` line `review-route` prints at light) and the C5 grammar `**Plan review:** <YYYY-MM-DD> — skipped (depth light)`. This task writes them as text and runs none of them.
- Produces: the plan phase by depth in `skills/writing-plans/SKILL.md` (Lint and Review, Execution Handoff, Auto run) and `skills/handoff/SKILL.md` (description, hard-stop rule, step 5). Task 11 pins the phrases `**Plan review:** <YYYY-MM-DD> — skipped (depth light)`, `handoff steps 0-4`, `context-size` and `hard stop` in writing-plans, and `depth` in handoff.

**Depends on:** Task 2

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

Writing-plans learns four things. After lint the session runs `scripts/depth-route` and says its line. At light, `review-route` returns no seat and the session records `skipped (depth light)` in place of a review. The cap sentence stops giving every plan a cap-critical round, which `review-route` never gave a Claude plan. And a light plan of 1-3 tasks is no hard stop: it runs the handoff skill's steps 0-4, checks plain `scripts/context-size`, and on `ok` continues into the execution skill in the same session. Handoff learns that exception.

Several suites quote these two files. Every edit below keeps their pinned phrases byte for byte and adds text around them: `On a Claude plan the cap is 2 whatever the task totals: round 2 is the delta round, and there is no third` (`review-route.test.sh`, `faster-plans.acceptance.test.sh`), the first line of the Execution Handoff paragraph (`parallel-grouping.test.sh`), and `plan saved outside an auto run` in handoff's description (`final-phase.test.sh`). Do not edit any test file in this task.

- [ ] **Step 1: Write the failing check**

Run this from the repository root. Every `need` line names one line of the new text, so each prints `MISSING` until the edits below are made:

```bash
W=plugins/dforge/skills/writing-plans/SKILL.md
H=plugins/dforge/skills/handoff/SKILL.md
miss=0
need() { grep -qF -- "$2" "$1" || { echo "MISSING in $1: $2"; miss=1; }; }
need "$W" '- **Once the plan is reviewed** (at depth light, once it is linted):'
need "$W" 'Then run `scripts/depth-route PLAN_FILE` and say its line aloud'
need "$W" '- **`primary=none`** (`reason=depth-light`, round 1 of a light plan). No'
need "$W" 'delta round, and there is no third. Only the plan'"'"'s depth lowers it: 1 at'
need "$W" 'fix, which earns no other; a Claude plan has no such round. A delta round'
need "$W" '`**Plan review:** <YYYY-MM-DD> — skipped (depth light)` in the same place,'
need "$W" 'The exception is a plan at depth light, which is no hard stop outside an auto'
need "$W" 'dforge:handoff steps 0-4 only (reconcile background work, commit the plan and'
need "$W" '`latest.md` names this plan, then plain `scripts/context-size`: the task'
need "$W" 'line that the Execution line'"'"'s model and effort are not applied in this'
need "$H" 'except a light plan of 1-3 tasks with room to continue'
need "$H" 'plan of 1-3 tasks runs steps 0-4 and continues in this session.'
need "$H" 'tasks with room does, stops after step 4.'
[ "$miss" -eq 0 ] && echo "all present"
exit "$miss"
```

- [ ] **Step 2: Run the check to verify it fails**

Run the block above. Expected: thirteen `MISSING in ...` lines and exit status 1.

- [ ] **Step 3: Edit the writing-plans skill**

Apply these six edits to `plugins/dforge/skills/writing-plans/SKILL.md`. Each old text appears exactly once. Keep the surrounding lines as they are.

Edit 1 in `plugins/dforge/skills/writing-plans/SKILL.md`. Replace this exact text:

```text
- **Once the plan is reviewed:** `scripts/auto-run attach --plan PLAN_FILE`,
```

with:

```text
- **Once the plan is reviewed** (at depth light, once it is linted):
  `scripts/auto-run attach --plan PLAN_FILE`,
```

Edit 2 in `plugins/dforge/skills/writing-plans/SKILL.md`. Replace this exact text:

```text
   header sections, the task headings and index, the Execution line,
   placeholders, and every task's assignment lines.
2. **Review.**
```

with:

```text
   header sections, the task headings and index, the Execution line,
   placeholders, and every task's assignment lines.
   Then run `scripts/depth-route PLAN_FILE` and say its line aloud
   (`depth=<d> spec=<d> tasks=<d> reason=<items>`). The depth sizes the review
   below and the handoff after it; `review-route` reads the same depth, so
   never pick it by hand.
2. **Review.**
```

Edit 3 in `plugins/dforge/skills/writing-plans/SKILL.md`. Replace this exact text:

```text
   - **`primary=native:<model>/<effort>`** (every round of a Codex-host plan).
```

with:

```text
   - **`primary=none`** (`reason=depth-light`, round 1 of a light plan). No
     review round runs: dispatch no seat, skip step 3, and record the skip in
     step 4.
   - **`primary=native:<model>/<effort>`** (every round of a Codex-host plan).
```

Edit 4 in `plugins/dforge/skills/writing-plans/SKILL.md`. Replace this exact text:

```text
   below the `cap=` that `review-route` printed.
   On a Claude plan the cap is 2 whatever the task totals: round 2 is the
   delta round, and there is no third. On a Codex-host plan the cap follows the
   highest raw task total, not the weighted routing score: 1 when it is 3 or
   less, 2 for 4 or 5, 3 for 6. At the cap a Critical finding
   earns exactly one more delta round (`reason=cap-critical`), scoped to its
   fix, which earns no other. A delta round replaces a fresh full review. Any
   Critical finding still open after the last round, and any score of 8 or
   below at the cap, go to your human partner. A borderline score (9-13) gets
   a one-line decision in the plan's Assumptions.
```

with:

```text
   below the `cap=` that `review-route` printed.
   On a Claude plan the cap is 2 whatever the task totals: round 2 is the
   delta round, and there is no third. Only the plan's depth lowers it: 1 at
   standard, so round 1 is the only round, and 0 at light, so none runs. On a
   Codex-host plan the cap follows the highest raw task total, not the weighted
   routing score, at every depth: 1 when it is 3 or less, 2 for 4 or 5, 3 for
   6. At the cap a Codex-host plan's Critical finding
   earns exactly one more delta round (`reason=cap-critical`), scoped to its
   fix, which earns no other; a Claude plan has no such round. A delta round
   replaces a fresh full review. Any Critical finding still open after the
   last round, and any score of 8 or below at the cap, go to your human partner
   (in an auto run, onto the pending list). A borderline score (9-13) gets
   a one-line decision in the plan's Assumptions.
```

Edit 5 in `plugins/dforge/skills/writing-plans/SKILL.md`. Replace this exact text:

```text
   agent. The header template deliberately omits it, so `plan-lint` warns
   until the review has run.
```

with:

```text
   agent. The header template deliberately omits it, so `plan-lint` warns
   until the review has run. At depth light no review ran: write
   `**Plan review:** <YYYY-MM-DD> — skipped (depth light)` in the same place,
   and `plan-lint` accepts it.
```

Edit 6 in `plugins/dforge/skills/writing-plans/SKILL.md`. Replace this exact text:

```text
line and the first prompt for the skill that line names. Offer no execution
choice: the Execution line already made it.
```

with:

```text
line and the first prompt for the skill that line names. Offer no execution
choice: the Execution line already made it.

The exception is a plan at depth light, which is no hard stop outside an auto
run (an auto run switches at every depth). A light plan of 4 or more tasks
still ends with dforge:handoff as above. A light plan of 1-3 tasks runs
dforge:handoff steps 0-4 only (reconcile background work, commit the plan and
the spec, write the handoff notes, `scripts/next-step PLAN_FILE`), so that
`latest.md` names this plan, then plain `scripts/context-size`: the task
budget, not `--plan`, which measures room to write a plan. On `ok`, say in one
line that the Execution line's model and effort are not applied in this
session, and invoke the skill that line names; print no resume guide. On any
other result, run handoff step 5 and end the session as above. The task count
decides only this, never the depth.
```

- [ ] **Step 4: Edit the handoff skill**

Apply these three edits to `plugins/dforge/skills/handoff/SKILL.md`. The description keeps the phrase `plan saved outside an auto run`, and the hard-stop bullet keeps the line that follows it, `The last task completing is never a stop in either execution mode`.

Edit 1 in `plugins/dforge/skills/handoff/SKILL.md`. Replace this exact text:

```text
description: Use when a budget line says handoff, at a hard phase stop (plan saved outside an auto run, or a switch from inline to subagent mode), on Codex
```

with:

```text
description: Use when a budget line says handoff, at a hard phase stop (plan saved outside an auto run, except a light plan of 1-3 tasks with room to continue, or a switch from inline to subagent mode), on Codex
```

Edit 2 in `plugins/dforge/skills/handoff/SKILL.md`. Replace this exact text:

```text
- A hard stop: the plan is saved outside an auto run, or a plan has just
  switched from inline to subagent mode.
```

with:

```text
- A hard stop: the plan is saved outside an auto run, or a plan has just
  switched from inline to subagent mode. A saved plan at depth light is a stop
  only when it has 4 or more tasks, or when `scripts/context-size` does not
  say `ok` after steps 0-4 (dforge:writing-plans §Execution Handoff): a light
  plan of 1-3 tasks runs steps 0-4 and continues in this session.
```

Edit 3 in `plugins/dforge/skills/handoff/SKILL.md`. Replace this exact text:

```text
   the launch command, the directory to launch it in, and the first prompt.
```

with:

```text
   the launch command, the directory to launch it in, and the first prompt.
   A caller that continues in this session instead, as a light plan of 1-3
   tasks with room does, stops after step 4.
```

- [ ] **Step 5: Run the check and the suites that quote these files**

Run the Step 1 block again. Expected: `all present`, exit status 0.

Then run each suite below under its own `timeout 600`, one at a time (`faster-plans.acceptance` takes a few minutes):

```bash
for t in review-route parallel-grouping final-phase settings-skills auto-default auto-run-skills process-roles faster-plans.acceptance project-status inline-mode plan-lint task-step-text seats ui-ux-skill lanes test-simplifier; do
  printf '%s: ' "$t"; timeout 600 bash "plugins/dforge/tests/$t.test.sh" 2>&1 | tail -1
done
```

Expected: every line ends `0 failed`.

Last, confirm the skip line passes the plan linter's header check, which only tests that a `**Plan review:**` line exists. Run: `grep -n "Plan review" plugins/dforge/scripts/plan-lint`. Expected: one match, `no **Plan review:** line yet`, raised only when the line is absent.

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/skills/writing-plans/SKILL.md plugins/dforge/skills/handoff/SKILL.md
git commit -m "feat(dforge): size the plan phase by depth"
```

### Task 6: Size the spec phase by depth in using-dforge, brainstorming and auto-run

**Files:**
- Modify: `plugins/dforge/skills/using-dforge/SKILL.md` (Process Depth)
- Modify: `plugins/dforge/skills/brainstorming/SKILL.md` (Three Paths, Checklist, Process Flow, Auto by default, After the Design)
- Modify: `plugins/dforge/reference/auto-run.md` (§The spec, §Finishing)
- Modify: `plugins/dforge/tests/process-roles.test.sh` (the three pins that quote the trigger-keyed critic fold)
- Test: `plugins/dforge/tests/auto-default.test.sh`

**Interfaces:**
- Consumes: C2 (`scripts/depth-route --spec-triggers LIST` prints `depth=<d> reason=<ids>`) and C5 (the Process line, the `**Depth:**` line, `Critic: skipped (depth light)`, `Depth: <d> — <reasons>`, `not verified (depth light)` and the existing `final review lens-skipped <id> reason=…` ledger line, which Task 7 writes for every reason).
- Produces: skill and reference text that says what the spec phase runs at each depth; the strings pinned in Step 1 are the ones the closing acceptance suite may quote.

**Depends on:** Task 2

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 2 - spec 0 - coupling 1 - risk 1 = 4

Every edit below is one `Edit` call: the quoted old text occurs exactly once in its file, and the new text is final, wrapped as shown. Change nothing else. `skills/using-dforge/SKILL.md` has a 5,500-byte cap (`hook.test.sh`); its edits are sized to fit.

- [ ] **Step 1: Write the failing pins**

Add the new assertions to `plugins/dforge/tests/auto-default.test.sh`, below its last existing `names` line. They define `flat`, `says` and `lacks` (line breaks folded, so a pin may wrap) and pin the text Steps 4 to 6 write:

Edit 1. In `plugins/dforge/tests/auto-default.test.sh`, replace this text, which occurs once:

````text
names "using-dforge: the approval is the spec review" "$P/skills/using-dforge/SKILL.md" 'still get approval (under `autoRun=on`, the spec review).'
````

with:

````text
names "using-dforge: the approval is the spec review" "$P/skills/using-dforge/SKILL.md" 'still get approval (under `autoRun=on`, the spec review).'

# Review depth: the spec phase by depth. Matched with line breaks folded.
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
says() { # says <label> <file> <text>
  check "$1" "$(flat "$2" | grep -qF -- "$3" && echo yes || echo no)" "yes"
}
lacks() { # lacks <label> <file> <text>
  check "$1" "$(flat "$2" | grep -qF -- "$3" && echo yes || echo no)" "no"
}
AR="$P/reference/auto-run.md"
PROC='`Process: architectural, <inline|subagent>, depth <d> — <triggers>`'
says "using-dforge: the Process line names the depth" "$P/skills/using-dforge/SKILL.md" "$PROC"
says "using-dforge: the depth comes from depth-route" "$P/skills/using-dforge/SKILL.md" '`<d>` from `scripts/depth-route --spec-triggers`'
says "brainstorming: the Process line names the depth" "$B" "$PROC"
says "brainstorming: the depth comes from depth-route" "$B" 'take `<d>` from `scripts/depth-route --spec-triggers <ids>`'
says "brainstorming: a later trigger reruns depth-route and the depth only rises" "$B" 'reruns `scripts/depth-route --spec-triggers` with the whole list, and the depth can only rise'
says "brainstorming: an owner line survives the ratchet" "$B" 'a `**Depth:** <d> — owner` line is left as it is'
says "brainstorming: the depth decides the fold, not the triggers" "$B" 'The depth decides, not the trigger list'
says "brainstorming: an owner full line gets the separate critic" "$B" 'a spec whose line reads `**Depth:** full — owner` and holds no risk trigger gets the separate critic'
says "brainstorming: light runs the self-review round only" "$B" 'At `light`, run the spec self-review round and nothing else: no critic, no Fable review'
says "brainstorming: standard folds the critic and runs no second round" "$B" 'with the critic folded into it (Architecture critic), and no second round'
says "brainstorming: a Codex host runs the spec phase as full" "$B" 'On a Codex host the spec phase runs as `full` at every depth'
says "brainstorming: light reports the critic as skipped" "$B" '`Critic: skipped (depth light)`'
says "brainstorming: the spec review names the depth" "$B" '`Depth: <d> — <reasons>`'
says "brainstorming: the light approve option says the plan is not a stop" "$B" '(depth light: the plan is not a stop; execution follows in this session)'
says "brainstorming: the owner sets the depth under Changes needed" "$B" 'sets the depth by hand under **Changes needed**: write `**Depth:** <d> — owner` in the spec'
says "brainstorming: no rulings to import at light" "$B" '(none at depth light)'
says "brainstorming: self-review checks the Depth line" "$B" 'its first word is `light`, `standard` or `full`'
says "brainstorming: every architectural spec carries the Depth line" "$B" 'carries a `**Depth:**` line directly below its `**Execution strategy:**` line'
lacks "brainstorming: the fold no longer keys on the Process line's triggers" "$B" 'your Process line names neither irreducible risk nor a new'
says "auto-run.md: the spec depth sizes the phase" "$AR" 'The spec'"'"'s `**Depth:**` line sizes this phase'
says "auto-run.md: light dispatches no critic and no Fable review" "$AR" 'dispatch no critic and no Fable review, record no spec ruling'
says "auto-run.md: light under ask reaches execution with no reader" "$AR" 'reaches execution with no reader of the written spec'
says "auto-run.md: the critic folds at depth standard" "$AR" 'folds the critic into Fable'"'"'s first round at depth standard'
says "auto-run.md: no second Fable round at standard" "$AR" 'at depth `standard` no second round runs'
says "auto-run.md: finishing lists every lens-skipped line" "$AR" '`final review lens-skipped <id> reason=<reason>` line in the ledger, whatever its reason'
says "auto-run.md: light finishing lists the unverified test statements" "$AR" 'every `test` statement of the spec under `not verified (depth light)`'
````

- [ ] **Step 2: Move the three trigger-keyed pins**

`plugins/dforge/tests/process-roles.test.sh` pins the critic fold by the Process line's triggers, and the folded second round. Step 5 rewrites exactly that text, so replace these three assertions (no other assertion in the file changes):

Edit 1. In `plugins/dforge/tests/process-roles.test.sh`, replace this text, which occurs once:

````text
names "critic: folded into Fable without a risk trigger" "$BS" 'and your Process line names neither irreducible risk nor a new'
names "critic: a risk trigger keeps the separate round" "$BS" 'a risk or new-subsystem trigger keeps the separate'
````

with:

````text
names "critic: folded into Fable at depth standard" "$BS" 'and the spec'"'"'s depth is `standard`, dispatch no critic.'
names "critic: depth full keeps the separate round" "$BS" 'new-subsystem trigger gives it, keeps the separate critic round.'
````

Edit 2. In `plugins/dforge/tests/process-roles.test.sh`, replace this text, which occurs once:

````text
says "spec review: the folded second round needs an open finding" "$BS" 'which runs only when a Blocker or High finding is still open'
````

with:

````text
says "spec review: the folded critic gets no second Fable round" "$BS" 'No second Fable round runs at standard'
````

- [ ] **Step 3: Run both suites to verify they fail**

Run: `timeout 300 bash plugins/dforge/tests/auto-default.test.sh`
Expected: 26 `FAIL` lines, one per pin added in Step 1, and no other failure

Run: `timeout 300 bash plugins/dforge/tests/process-roles.test.sh`
Expected: 3 `FAIL` lines: `critic: folded into Fable at depth standard`, `critic: depth full keeps the separate round`, `spec review: the folded critic gets no second Fable round`

- [ ] **Step 4: Name the depth in the entry point**

Edit 1. In `plugins/dforge/skills/using-dforge/SKILL.md`, replace this text, which occurs once:

````text
(the plan's Execution line decides the mode), and still get approval
````

with:

````text
(the plan decides the mode), and still get approval
````

Edit 2. In `plugins/dforge/skills/using-dforge/SKILL.md`, replace this text, which occurs once:

````text
Codex runs `on` as `off`. Execute inline by default
````

with:

````text
Codex runs `on` as `off`. Architectural: `Process: architectural, <inline|subagent>, depth <d> — <triggers>`, `<d>` from `scripts/depth-route --spec-triggers`. Execute inline by default
````

Run: `wc -c < plugins/dforge/skills/using-dforge/SKILL.md`
Expected: a number of 5500 or less (5487 when the file was 5368 bytes before).

- [ ] **Step 5: Size the spec phase in brainstorming**

Three Paths: the Process line names the depth, the ratchet reruns the script.

Edit 1. In `plugins/dforge/skills/brainstorming/SKILL.md`, replace this text, which occurs once:

````text
a chat design; or your human partner asked for a spec.

- **Spike**
````

with:

````text
a chat design; or your human partner asked for a spec.

On the architectural path the line also names the depth,
`Process: architectural, <inline|subagent>, depth <d> — <triggers>`. Name each
trigger that holds by its id (`new-subsystem`, `interface`, `unenumerable`,
`approach`, `risk`, `intricate`, `asked`, in the order of the list above), and
take `<d>` from `scripts/depth-route --spec-triggers <ids>`: `full` for `risk`
or `new-subsystem`, `standard` for `interface`, `light` otherwise. The depth
sizes the reviews that follow the spec; it never removes the approval. Your
human partner may set it by hand at the spec review.

- **Spike**
````

Edit 2. In `plugins/dforge/skills/brainstorming/SKILL.md`, replace this text, which occurs once:

````text
- **Architectural** — at least one trigger holds; name it. Follow the
````

with:

````text
- **Architectural** — at least one trigger holds; name it and the depth. Follow the
````

Edit 3. In `plugins/dforge/skills/brainstorming/SKILL.md`, replace this text, which occurs once:

````text
stop, say so, and step up. Nothing downgrades mid-task.
````

with:

````text
stop, say so, and step up. A trigger found after the Process line was said
reruns `scripts/depth-route --spec-triggers` with the whole list, and the depth
can only rise; a `**Depth:** <d> — owner` line is left as it is. Nothing
downgrades mid-task.
````

Checklist and Process Flow: step 12, step 9, step 11 and the graph edges.

Edit 1. In `plugins/dforge/skills/brainstorming/SKILL.md`, replace this text, which occurs once:

````text
under `autoRun=on` Fable reviews it first and this is Auto by default's spec review message (an auto run started from the offer has Fable review it instead)
````

with:

````text
under `autoRun=on` this is Auto by default's spec review message, after Fable's review at depth standard or full (an auto run started from the offer has Fable review it instead, at those depths)
````

Edit 2. In `plugins/dforge/skills/brainstorming/SKILL.md`, replace this text, which occurs once:

````text
9. **Write design doc** — save to `<docs>/specs/YYYY-MM-DD-<topic>-design.md` and commit
````

with:

````text
9. **Write design doc** — save to `<docs>/specs/YYYY-MM-DD-<topic>-design.md` with its `**Depth:**` line, and commit
````

Edit 3. In `plugins/dforge/skills/brainstorming/SKILL.md`, replace this text, which occurs once:

````text
(see Architecture critic, which folds it into Fable's first round when Fable reviews a spec with no risk or new-subsystem trigger)
````

with:

````text
(see Architecture critic: depth light skips it, and depth standard folds it into Fable's first round when Fable reviews)
````

Edit 4. In `plugins/dforge/skills/brainstorming/SKILL.md`, replace this text, which occurs once:

````text
    "Spec self-review\n(one round, shown)" -> "Fable spec review\n(at most two rounds)" [label="Fable reviews; no risk or\nnew-subsystem trigger"];
````

with:

````text
    "Spec self-review\n(one round, shown)" -> "Fable spec review\n(at most two rounds)" [label="Fable reviews;\ndepth standard"];
    "Spec self-review\n(one round, shown)" -> "Spec review\n(the one stop)" [label="depth light\n(autoRun=on)"];
    "Spec self-review\n(one round, shown)" -> "User reviews spec?" [label="depth light\n(attended)"];
````

Auto by default: the Depth line, the reviews by depth, the spec review message, the owner override and the ruling import.

Edit 1. In `plugins/dforge/skills/brainstorming/SKILL.md`, replace this text, which occurs once:

````text
2. **Record the decisions.** Below its `**Execution strategy:**` line the spec
   carries a `## Decisions` section: every clarifying question and approach
````

with:

````text
2. **Record the decisions.** Below its `**Execution strategy:**` and
   `**Depth:**` lines the spec carries a `## Decisions` section: every
   clarifying question and approach
````

Edit 2. In `plugins/dforge/skills/brainstorming/SKILL.md`, replace this text, which occurs once:

````text
4. **Reviews before the stop.** Run the spec self-review round, then the
   architecture critic, then `dforge:judge-fable` on the spec against its
   `## Decisions`: one round, and a second only when round 1 leaves a Blocker
   or High finding open, its own or a folded critic's, checking only those
   answers; without a risk or new-subsystem trigger, Fable's first round
   takes the critic's place (Architecture critic). Apply what
   Fable rules and list each ruling as one line in a `## Review rulings`
   section of the spec.
````

with:

````text
4. **Reviews before the stop,** by the spec's depth. At `light`, run the spec
   self-review round and nothing else: no critic, no Fable review, no
   `## Review rulings` section. At `standard`, run it, then one
   `dforge:judge-fable` round on the spec against its `## Decisions` with the
   critic folded into it (Architecture critic), and no second round. At
   `full`, run it, then the architecture critic, then `dforge:judge-fable` on
   the spec against its `## Decisions`: one round, and a second only when
   round 1 leaves a Blocker or High finding open, checking only those
   answers. Apply what Fable rules and list each ruling as one line in a
   `## Review rulings` section of the spec.
````

Edit 3. In `plugins/dforge/skills/brainstorming/SKILL.md`, replace this text, which occurs once:

````text
   - the spec path, the `Critic: …` counts and the number of Fable rulings;
````

with:

````text
   - the spec path, `Depth: <d> — <reasons>` (the `depth=` and `reason=` of
     `scripts/depth-route --spec-triggers`, or `owner`), the `Critic: …` counts
     (at `light`, `Critic: skipped (depth light)`) and the number of Fable
     rulings;
````

Edit 4. In `plugins/dforge/skills/brainstorming/SKILL.md`, replace this text, which occurs once:

````text
   Apply the answers to the spec. **Changes needed** gets the revision and one
````

with:

````text
   At `light`, the **Approve, keep the normal stops** option adds "(depth
   light: the plan is not a stop; execution follows in this session)". Your
   human partner sets the depth by hand under **Changes needed**: write
   `**Depth:** <d> — owner` in the spec. The plan checkpoint can still raise
   it, and the ratchet never replaces an owner line.

   Apply the answers to the spec. **Changes needed** gets the revision and one
````

Edit 5. In `plugins/dforge/skills/brainstorming/SKILL.md`, replace this text, which occurs once:

````text
   `scripts/auto-run ruling add "Fable, spec: <line>"`. Invoke
   dforge:writing-plans in this session: `scripts/context-size --plan` does not
   run. On exit 2 or 4 from `start`, say why in one line and continue as
   **Approve, keep the normal stops**.
````

with:

````text
   `scripts/auto-run ruling add "Fable, spec: <line>"` (none at depth light).
   Invoke dforge:writing-plans in this session: `scripts/context-size --plan`
   does not run. On exit 2 or 4 from `start`, say why in one line and continue
   as **Approve, keep the normal stops**.
````

After the Design: the Documentation bullet, the self-review item, the critic by depth, the fold, the counts and the User Review Gate.

Edit 1. In `plugins/dforge/skills/brainstorming/SKILL.md`, replace this text, which occurs once:

````text
- Every spec has an `## Acceptance` section holding the statements settled in
````

with:

````text
- Every architectural spec carries a `**Depth:**` line directly below its
  `**Execution strategy:**` line: `**Depth:** <light|standard|full> — <reason ids>`,
  the `depth=` and `reason=` that `scripts/depth-route --spec-triggers`
  printed for the Process line's triggers, or `**Depth:** <d> — owner` when
  your human partner set it. `## Decisions` sits below it. A spec without the
  line routes at `full`.
- Every spec has an `## Acceptance` section holding the statements settled in
````

Edit 2. In `plugins/dforge/skills/brainstorming/SKILL.md`, replace this text, which occurs once:

````text
and no part that may run beside another consumes its output.
````

with:

````text
and no part that may run beside another consumes its output. The `**Depth:**` line is present below it, and its first word is `light`, `standard` or `full`.
````

Edit 3. In `plugins/dforge/skills/brainstorming/SKILL.md`, replace this text, which occurs once:

````text
**Architecture critic:**

After the self-review block, dispatch the critic once with
````

with:

````text
**Architecture critic:**

The spec's `**Depth:**` line decides which reviews run. At `light`, neither the
critic nor a Fable spec review runs: the self-review round is the whole spec
phase. At `standard`, when Fable reviews the spec (under `autoRun=on`, or in an
auto run) no separate critic runs and Fable's first round takes its job
(Folded into Fable, below); when Fable does not review it (attended), the
critic round below runs as written. At `full`, the separate critic round runs,
then Fable for one or two rounds. The depth decides, not the trigger list: a
spec whose line reads `**Depth:** full — owner` and holds no risk trigger gets
the separate critic. On a Codex host the spec phase runs as `full` at every
depth.

After the self-review block, dispatch the critic once with
````

Edit 4. In `plugins/dforge/skills/brainstorming/SKILL.md`, replace this text, which occurs once:

````text
**Folded into Fable.** When Fable will review this spec (under `autoRun=on`, or
in an auto run) and your Process line names neither irreducible risk nor a new
project or subsystem as a trigger, dispatch no critic. Give Fable's first round
the critic's job as well: the criteria path
`[PLUGIN_ROOT]/criteria/architecture-critique.md`, read as lenses and not
scored, and the critic prompt's Output section, so its report carries the
critic's ranked findings under their own heading, ## Critic findings, beside its rulings. Handle
those findings exactly as the critic's below, before Fable's second round,
which runs only when a Blocker or High finding is still open and checks only
those answers. Two seats find more than one on a
risky or new design, so a risk or new-subsystem trigger keeps the separate
critic round.
````

with:

````text
**Folded into Fable.** When Fable will review this spec (under `autoRun=on`, or
in an auto run) and the spec's depth is `standard`, dispatch no critic. Give
Fable's first round the critic's job as well: the criteria path
`[PLUGIN_ROOT]/criteria/architecture-critique.md`, read as lenses and not
scored, and the critic prompt's Output section, so its report carries the
critic's ranked findings under their own heading, ## Critic findings, beside its rulings. Handle
those findings exactly as the critic's below. No second Fable round runs at
standard: a critic Blocker that round 1 leaves open is asked at the spec
review as one Fable did not settle, or, in an auto run started from the
offer, deferred to the register
([auto-run.md](../../reference/auto-run.md) §The spec). Two seats find more
than one on a risky or new design, so a spec at depth `full`, which a risk or
new-subsystem trigger gives it, keeps the separate critic round.
````

Edit 5. In `plugins/dforge/skills/brainstorming/SKILL.md`, replace this text, which occurs once:

````text
  followed by ` (in Fable's review)` when the critic was folded into it.
````

with:

````text
  followed by ` (in Fable's review)` when the critic was folded into it.
  At depth light the review request says `Critic: skipped (depth light)`
  instead, since no critic ran.
````

Edit 6. In `plugins/dforge/skills/brainstorming/SKILL.md`, replace this text, which occurs once:

````text
> "Spec written and committed to `<path>`. Critic: <b> Blocker, <h> High (<f> fixed, <a> answered), <m> Medium. Please review it and let me know if you want to make any changes before we start writing out the implementation plan."

Wait for the user's response.
````

with:

````text
> "Spec written and committed to `<path>`. Depth: <d> — <reasons>. Critic: <b> Blocker, <h> High (<f> fixed, <a> answered), <m> Medium. Please review it and let me know if you want to make any changes before we start writing out the implementation plan."

At depth light, `Critic: skipped (depth light)` replaces the counts. Your human
partner may set the depth in the reply; write `**Depth:** <d> — owner` in the
spec.

Wait for the user's response.
````

- [ ] **Step 6: Size the spec phase in auto-run.md**

Edit 1. In `plugins/dforge/reference/auto-run.md`, replace this text, which occurs once:

````text
Under `autoRun=on` the critic and the Fable review run before the run starts,
as dforge:brainstorming §Auto by default says: what Fable leaves undecided is
````

with:

````text
Under `autoRun=on` the critic and the Fable review run before the run starts,
at the spec's depth (below), as dforge:brainstorming §Auto by default says:
what Fable leaves undecided is
````

Edit 2. In `plugins/dforge/reference/auto-run.md`, replace this text, which occurs once:

````text
After your own self-review round and the architecture critic
(dforge:brainstorming §Architecture critic, which folds the critic into
Fable's first round when no risk or new-subsystem trigger holds), dispatch
`dforge:judge-fable` on
````

with:

````text
The spec's `**Depth:**` line sizes this phase. At `light` the self-review
round is the whole of it: dispatch no critic and no Fable review, record no
spec ruling, and go on to the plan. Under `autoRun=ask`, a light run started
from the offer therefore reaches execution with no reader of the written spec:
every design section and acceptance statement was approved by hand before the
run started, and that is the review light keeps. At `standard` the critic is
folded into one Fable round with no second round; at `full` the separate
critic runs first and Fable for one or two rounds. The depth decides, not the
trigger list. What follows is the phase at `standard` and `full`.

After your own self-review round and the architecture critic
(dforge:brainstorming §Architecture critic, which folds the critic into
Fable's first round at depth standard), dispatch
`dforge:judge-fable` on
````

Edit 3. In `plugins/dforge/reference/auto-run.md`, replace this text, which occurs once:

````text
Fable runs one round. A second runs only when round 1 leaves a Blocker or High
finding open, its own or a folded critic's, and checks only those answers;
anything still open after the last round is deferred the same way. Then write
````

with:

````text
Fable runs one round. A second runs only when round 1 leaves a Blocker or High
finding open at depth `full`, and checks only those answers; at depth
`standard` no second round runs, and anything still open after the last round
is deferred the same way. Then write
````

Edit 4. In `plugins/dforge/reference/auto-run.md`, replace this text, which occurs once:

````text
every `demo` statement of the spec, every lens
named by a `final review lens-skipped <id> reason=cap` line in the ledger
(final-review.md step 4 writes them; do not run `scripts/lens-route --final`
here, since after a merge its base..HEAD range is empty), and it runs
`scripts/auto-run stop` with no `--reason` before the next-step block: a
````

with:

````text
every `demo` statement of the spec, every lens
named by a `final review lens-skipped <id> reason=<reason>` line in the ledger,
whatever its reason (final-review.md step 4 writes them; do not run
`scripts/lens-route --final` here, since after a merge its base..HEAD range is
empty), and, when the ledger's `Review depth:` line says `light`, every `test`
statement of the spec under `not verified (depth light)`. It runs
`scripts/auto-run stop` with no `--reason` before the next-step block: a
````

- [ ] **Step 7: Run the suites to verify they pass**

Run: `timeout 300 bash plugins/dforge/tests/auto-default.test.sh`
Expected: `0 failed`

Run: `timeout 300 bash plugins/dforge/tests/process-roles.test.sh`
Expected: `0 failed`

Run: `timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh`
Expected: `0 failed` (it pins `auto-run.md` lines that this task keeps as they are, among them the self-review line that opens The spec's second paragraph and the final message's `demo` and lens list)

Run: `timeout 300 bash plugins/dforge/tests/hook.test.sh`
Expected: `0 failed` (the entry point is at most 5,500 bytes)

Run: `timeout 300 bash plugins/dforge/tests/ui-ux-skill.test.sh`
Expected: `0 failed`

Run: `timeout 300 bash plugins/dforge/tests/seats.test.sh`
Expected: `0 failed`

Run: `timeout 600 bash plugins/dforge/tests/faster-plans.acceptance.test.sh`
Expected: `0 failed` (it pins the one-round Fable wording in `brainstorming` and `auto-run.md`)

- [ ] **Step 8: Commit**

```bash
git add plugins/dforge/skills/using-dforge/SKILL.md plugins/dforge/skills/brainstorming/SKILL.md plugins/dforge/reference/auto-run.md plugins/dforge/tests/process-roles.test.sh plugins/dforge/tests/auto-default.test.sh
git commit -m "feat(dforge): size the spec phase by depth"
```

### Task 7: Size the final review by depth in final-review.md

**Files:**
- Modify: `plugins/dforge/reference/final-review.md` (The review intro, steps 0.5, 1, 2, 3 and 4)
- Test: `plugins/dforge/tests/final-phase.test.sh`

**Interfaces:**
- Consumes: C2 (`scripts/depth-route PLAN_FILE` prints `depth=<d> … reason=<items>`), C4 (`scripts/lens-route --final` prints `lens-skipped <id> reason=depth` at light and `reason=cap` as before) and C5.
- Produces: the ledger lines `Review depth: <depth> (<reason>)` and `Acceptance QA: skipped (depth light)`, the ledger line `final review lens-skipped <id> reason=<reason>` for every reason, and the spoken line `codex round skipped (depth <d>)`. Tasks 8, 9 and 11 consume them.

**Depends on:** Task 2, Task 4

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

Every edit below is one `Edit` call: the quoted old text occurs exactly once in its file, and the new text is final, wrapped as shown. Change nothing else. `tests/process-roles.test.sh`, `tests/inline-mode.test.sh`, `tests/seats.test.sh`, `tests/ui-ux-skill.test.sh` and `tests/auto-run-skills.test.sh` pin lines of this file; every line they pin stays as it is.

- [ ] **Step 1: Write the failing pins**

Add these assertions to `plugins/dforge/tests/final-phase.test.sh`, above its final `printf` line. They define `flat` and `says` (line breaks folded) and pin the depth table, the ledger lines and the skips:

Edit 1. In `plugins/dforge/tests/final-phase.test.sh`, replace this text, which occurs once:

````text
printf '\n%d passed, %d failed\n' "$pass" "$fail"
````

with:

````text
# Review depth: the final review by depth. Matched with line breaks folded.
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
says() { # says <label> <file> <text>
  check "$1" "$(flat "$2" | grep -qF -- "$3" && echo yes || echo no)" "yes"
}
says "final review: depth-route runs before step 0" "$FR" 'Before step 0 run `scripts/depth-route PLAN_FILE`'
says "final review: the depth is ledgered" "$FR" 'append `Review depth: <depth> (<reason>)` to the ledger'
says "final review: a recovered review reads the ledgered depth" "$FR" 'read that line and run no new route'
names "final review: gates run at every depth" "$FR" '| 0 Gates | runs | runs | runs |'
names "final review: UI proof runs at every depth" "$FR" '| 0.2 UI proof | runs | runs | runs |'
names "final review: QA is skipped at light only" "$FR" '| 0.5 Acceptance QA | skipped | runs | runs |'
names "final review: the Claude review runs at every depth" "$FR" '| 1 Claude review | runs | runs | runs |'
names "final review: the lens column by depth" "$FR" '| 1 Lenses | `security` only, when it applies | at most 2 | up to `lensCap` |'
names "final review: the Codex round is skipped below full" "$FR" '| 2 Codex round | skipped | skipped | as today |'
names "final review: the dedupe judge needs two lists" "$FR" '| 3 Dedupe judge | never (one list) | never (one list) | with two lists |'
says "final review: the fix wave runs at every depth" "$FR" 'The fix wave and its scoped re-review run at every depth.'
says "final review: light writes the skipped QA line" "$FR" 'append `Acceptance QA: skipped (depth light)` to the ledger, once'
says "final review: recovery reads skipped as complete" "$FR" 'Recovery reads that line as `Acceptance QA: complete`'
says "final review: the Codex round skip is said" "$FR" '`codex round skipped (depth <d>)`'
says "final review: the skipped round leaves nothing to wait for" "$FR" 'or depth light or standard), there is nothing to wait for'
says "final review: lens-route reads the depth itself" "$FR" '`lens-route` reads the depth itself'
says "final review: every lens-skipped line reaches the ledger" "$FR" 'as `final review lens-skipped <id> reason=<reason>`, whatever its reason'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
````

- [ ] **Step 2: Run the suite to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/final-phase.test.sh`
Expected: 17 `FAIL` lines, one per pin added in Step 1, and no other failure

- [ ] **Step 3: Write the depth rules into final-review.md**

Edit 1. In `plugins/dforge/reference/final-review.md`, replace this text, which occurs once:

````text
## The review

MERGE_BASE is the commit the branch started from, for example
````

with:

````text
## The review

**Depth.** Before step 0 run `scripts/depth-route PLAN_FILE` and append
`Review depth: <depth> (<reason>)` to the ledger, `<depth>` and `<reason>`
being the values of its `depth=` and `reason=` fields. When the ledger already
holds a `Review depth:` line, as it does after a compaction, read that line
and run no new route, so every step of one review reads the same depth. The
prefix keeps the line apart from `Final review:`, which recovery keys on. The
depth sizes the steps below:

| Step | light | standard | full |
|---|---|---|---|
| 0 Gates | runs | runs | runs |
| 0.2 UI proof | runs | runs | runs |
| 0.5 Acceptance QA | skipped | runs | runs |
| 1 Claude review | runs | runs | runs |
| 1 Lenses | `security` only, when it applies | at most 2 | up to `lensCap` |
| 2 Codex round | skipped | skipped | as today |
| 3 Dedupe judge | never (one list) | never (one list) | with two lists |

The fix wave and its scoped re-review run at every depth.

MERGE_BASE is the commit the branch started from, for example
````

Edit 2. In `plugins/dforge/reference/final-review.md`, replace this text, which occurs once:

````text
- 0.5 **Acceptance QA.** Skip this step, saying so in one line, when the
  plan's spec has no `A<n>` statement tagged `test`, or when
  the ledger already holds `Acceptance QA: complete`. When the ledger holds
````

with:

````text
- 0.5 **Acceptance QA.** At depth light, skip this step: append
  `Acceptance QA: skipped (depth light)` to the ledger, once, and go on to
  step 1. Recovery reads that line as `Acceptance QA: complete`, so the step
  never reopens. At any other depth, skip this step, saying so in one line,
  when the plan's spec has no `A<n>` statement tagged `test`, or when
  the ledger already holds `Acceptance QA: complete`. When the ledger holds
````

Edit 3. In `plugins/dforge/reference/final-review.md`, replace this text, which occurs once:

````text
   costs the fixer more triage than it yields fixes.
````

with:

````text
   costs the fixer more triage than it yields fixes. `lens-route` reads the
   depth itself: at light it prints a `lens` line only for `security`, and
   only when its Applies clause matches; at standard it prints at most two,
   fewer when `lensCap` is lower. A lens it drops prints
   `lens-skipped <id> reason=depth` (light) or `reason=cap`.
````

Edit 4. In `plugins/dforge/reference/final-review.md`, replace this text, which occurs once:

````text
2. **Codex round.** Run the round in
   [executor-lane.md](executor-lane.md) §Final-review Codex round. Its
````

with:

````text
2. **Codex round.** At depth light or standard, skip it: say
   `codex round skipped (depth <d>)` in one line and go to step 3 with the
   Claude review alone. At depth full, run the round in
   [executor-lane.md](executor-lane.md) §Final-review Codex round. Its
````

Edit 5. In `plugins/dforge/reference/final-review.md`, replace this text, which occurs once:

````text
   (`codexReview` off, or the gate did not print `review=true`), there is
   nothing to wait for: go straight to the one-list case.
````

with:

````text
   (`codexReview` off, the gate did not print `review=true`,
   or depth light or standard), there is
   nothing to wait for: go straight to the one-list case.
````

Edit 6. In `plugins/dforge/reference/final-review.md`, replace this text, which occurs once:

````text
   Important, and the `Acceptance QA: complete` counts. Append each
   `lens-skipped <id> reason=cap` line step 1 printed to the ledger as
   `final review lens-skipped <id> reason=cap`, one line per lens, unless the
   ledger already holds it: finishing lists them from there, because after a
````

with:

````text
   Important, and the `Acceptance QA:` line (its counts, or `skipped (depth
   light)`). Append each
   `lens-skipped <id> reason=<reason>` line step 1 printed to the ledger as
   `final review lens-skipped <id> reason=<reason>`, whatever its reason
   (`cap` or `depth`), one line per lens, unless the
   ledger already holds it: finishing lists them from there, because after a
````

- [ ] **Step 4: Run the suites to verify they pass**

Run: `timeout 300 bash plugins/dforge/tests/final-phase.test.sh`
Expected: `0 failed`

Run: `timeout 300 bash plugins/dforge/tests/process-roles.test.sh`
Expected: `0 failed` (it pins the order of steps 0, 0.5, the review package and the lenses, and the QA recovery lines)

Run: `timeout 300 bash plugins/dforge/tests/inline-mode.test.sh`
Expected: `0 failed`

Run: `timeout 300 bash plugins/dforge/tests/seats.test.sh`
Expected: `0 failed`

Run: `timeout 300 bash plugins/dforge/tests/ui-ux-skill.test.sh`
Expected: `0 failed`

Run: `timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh`
Expected: `0 failed`

- [ ] **Step 5: Commit**

```bash
git add plugins/dforge/reference/final-review.md plugins/dforge/tests/final-phase.test.sh
git commit -m "feat(dforge): size the final review by depth"
```

### Task 8: Add the depth ledger lines to both execution skills

**Files:**
- Modify: `plugins/dforge/skills/executing-plans/SKILL.md` (The Ledger)
- Modify: `plugins/dforge/skills/subagent-driven-development/SKILL.md` (The Ledger)
- Test: `plugins/dforge/tests/inline-mode.test.sh`

**Interfaces:**
- Consumes: C5 (`Review depth: <depth> (<reason>)` and `Acceptance QA: skipped (depth light)`, which `reference/final-review.md` writes).
- Produces: the two lines in both skills' ledger grammar blocks, and the recovery note that reads a skipped QA line as `complete`.

**Depends on:** Task 2

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

Every edit below is one `Edit` call: the quoted old text occurs exactly once in its file, and the new text is final, wrapped as shown. Change nothing else. `tests/process-roles.test.sh` pins the `Acceptance QA:` lines and recovery bullet of both skills; the edits only add lines around them.

- [ ] **Step 1: Write the failing pins**

In `plugins/dforge/tests/inline-mode.test.sh`, the `One ledger grammar for both modes` loop checks each shared line in both skills. Add the two new lines to its list and add the recovery pins after it:

Edit 1. In `plugins/dforge/tests/inline-mode.test.sh`, replace this text, which occurs once:

````text
for line in 'minor (deferred)' 'parked' 'BLOCKED' 'Ruling:' 'Final review: clean'; do
  present "inline ledger has: $line" "$INLINE" "$line"
  present "subagent ledger has: $line" "$SDD" "$line"
done
````

with:

````text
for line in 'minor (deferred)' 'parked' 'BLOCKED' 'Ruling:' 'Final review: clean' 'Review depth: <light|standard|full> (<reason>)' 'Acceptance QA: skipped (depth light)'; do
  present "inline ledger has: $line" "$INLINE" "$line"
  present "subagent ledger has: $line" "$SDD" "$line"
done
for f in "$INLINE" "$SDD"; do
  s=$(basename "$(dirname "$f")")
  present "$s: a skipped QA line counts as complete on recovery" "$f" 'Acceptance QA: skipped (depth light)` counts as `complete` on recovery.'
  present "$s: the Review depth line is never recomputed" "$f" 'and is read on recovery, never recomputed; it is'
done
````

- [ ] **Step 2: Run the suite to verify it fails**

Run: `timeout 300 bash plugins/dforge/tests/inline-mode.test.sh`
Expected: 8 `FAIL` lines: the two new grammar lines in each skill and the two recovery pins in each skill, and no other failure

- [ ] **Step 3: Add the lines to executing-plans**

Edit 1. In `plugins/dforge/skills/executing-plans/SKILL.md`, replace this text, which occurs once:

````text
Acceptance QA: dispatched (base <sha7>)
Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo
````

with:

````text
Review depth: <light|standard|full> (<reason>)
Acceptance QA: dispatched (base <sha7>)
Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo
Acceptance QA: skipped (depth light)
````

Edit 2. In `plugins/dforge/skills/executing-plans/SKILL.md`, replace this text, which occurs once:

````text
  `rerun`. Step 0.5 holds the rest of the procedure.
````

with:

````text
  `rerun`. Step 0.5 holds the rest of the procedure.
- `Acceptance QA: skipped (depth light)` counts as `complete` on recovery.
  `Review depth: <light|standard|full> (<reason>)` is written once, before
  step 0 of the final review, and is read on recovery, never recomputed; it is
  not a `Final review:` line, which recovery keys on.
````

- [ ] **Step 4: Add the lines to subagent-driven-development**

Edit 1. In `plugins/dforge/skills/subagent-driven-development/SKILL.md`, replace this text, which occurs once:

````text
Acceptance QA: dispatched (base <sha7>)
Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo
````

with:

````text
Review depth: <light|standard|full> (<reason>)
Acceptance QA: dispatched (base <sha7>)
Acceptance QA: complete — <p> pass, <f> fail, <k> flaky, <c> cannot-test, <d> demo
Acceptance QA: skipped (depth light)
````

Edit 2. In `plugins/dforge/skills/subagent-driven-development/SKILL.md`, replace this text, which occurs once:

````text
  `rerun`. Step 0.5 holds the rest of the procedure.
````

with:

````text
  `rerun`. Step 0.5 holds the rest of the procedure.
- `Acceptance QA: skipped (depth light)` counts as `complete` on recovery.
  `Review depth: <light|standard|full> (<reason>)` is written once, before
  step 0 of the final review, and is read on recovery, never recomputed; it is
  not a `Final review:` line, which recovery keys on.
````

- [ ] **Step 5: Run the suites to verify they pass**

Run: `timeout 300 bash plugins/dforge/tests/inline-mode.test.sh`
Expected: `0 failed`

Run: `timeout 300 bash plugins/dforge/tests/process-roles.test.sh`
Expected: `0 failed`

Run: `timeout 300 bash plugins/dforge/tests/final-phase.test.sh`
Expected: `0 failed`

Run: `timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh`
Expected: `0 failed`

Run: `timeout 600 bash plugins/dforge/tests/faster-plans.acceptance.test.sh`
Expected: `0 failed`

- [ ] **Step 6: Commit**

```bash
git add plugins/dforge/skills/executing-plans/SKILL.md plugins/dforge/skills/subagent-driven-development/SKILL.md plugins/dforge/tests/inline-mode.test.sh
git commit -m "feat(dforge): add depth ledger lines"
```

### Task 9: List depth-skipped checks when finishing a branch

**Files:**
- Modify: `plugins/dforge/skills/finishing-a-development-branch/SKILL.md` (the Auto run section's "The rulings" bullet and the `merge` guard paragraph; Step 3, after "Rulings first")
- Test: `plugins/dforge/tests/auto-run-skills.test.sh` (after the line pinning `every \`demo\` statement of the spec, every lens`)

**Interfaces:**
- Consumes: Contracts C5, ledger lines `Review depth: <depth> (<reason>)` and `Acceptance QA: skipped (depth light)`, which final-review.md writes (Task 7); and the existing ledger line `final review lens-skipped <id> reason=<reason>`, which final-review.md step 4 now writes for every reason, not only `cap` (Task 7).
- Produces: C5's spoken line `not verified (depth light)` in finishing; Task 6 writes the same line into auto-run.md §Finishing, so this task does not edit that file. Task 11's acceptance suite pins both. Every phrase that `tests/auto-run-skills.test.sh`, `tests/auto-default.test.sh`, `tests/final-phase.test.sh` and the other suites already pin in these two files stays byte-for-byte; the edits add lines around them.

**Depends on:** Task 7

**Implementer:** dforge:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Write the failing pins**

In `plugins/dforge/tests/auto-run-skills.test.sh`, find this line (it appears once, in the `FIN=` block):

```text
names "finishing: the final message lists demos and lenses" "$FIN" 'every `demo` statement of the spec, every lens'
```

and add these five lines directly below it, leaving it unchanged:

```bash
names "finishing: every lens-skipped line is read, whatever its reason" "$FIN" 'a `final review lens-skipped <id> reason=<reason>` ledger line names,'
check "finishing: no lens-skipped line is read for reason=cap alone" "$(grep -c 'lens-skipped <id> reason=cap' "$FIN")" "0"
names "finishing: light lists the unverified test statements" "$FIN" 'every `A<n>` statement tagged `test` under `not verified (depth light)`'
names "finishing: Step 3 lists them before the menu" "$FIN" '**Unverified at light depth.** When the ledger holds a `Review depth: light`'
names "finishing: a skipped QA line carries no counts" "$FIN" 'An `Acceptance QA: skipped (depth light)` line carries no counts, so the'
```

- [ ] **Step 2: Run the suite to see the pins fail**

Run: `timeout 300 bash plugins/dforge/tests/auto-run-skills.test.sh 2>&1 | grep -c '^FAIL'`
Expected: `5`, and the last line of the full output reads `107 passed, 5 failed`.

- [ ] **Step 3: List unverified statements and every skipped lens in the Auto run bullet**

In `plugins/dforge/skills/finishing-a-development-branch/SKILL.md`, replace this exact text (the end of the "**The rulings**" bullet):

```text
  every `demo` statement of the spec, every lens
  a `final review lens-skipped <id> reason=cap` ledger line names (the final
  review wrote them; never run `scripts/lens-route` here, since after a merge
  base..HEAD is empty). Run
```

with:

```text
  every `A<n>` statement tagged `test` under `not verified (depth light)`
  when the ledger's `Review depth:` line names light (no acceptance QA ran),
  every `demo` statement of the spec, every lens
  a `final review lens-skipped <id> reason=<reason>` ledger line names,
  whatever its reason (the final
  review wrote them; never run `scripts/lens-route` here, since after a merge
  base..HEAD is empty). Run
```

- [ ] **Step 4: Say the `merge` guard has nothing to read at light**

In the same file, replace this exact text:

```text
  Note is `final review residual`.
```

with:

```text
  Note is `final review residual`.
  An `Acceptance QA: skipped (depth light)` line carries no counts, so the
  `cannot-test` case does not apply to it; Step 7's final message lists what
  went unchecked.
```

- [ ] **Step 5: Print the unverified statements at Step 3**

In the same file, replace this exact text (the end of the "**Rulings first.**" paragraph):

```text
exhaustive here. Your human partner chooses how to integrate with those
decisions in view.
```

with:

```text
exhaustive here. Your human partner chooses how to integrate with those
decisions in view.

**Unverified at light depth.** When the ledger holds a `Review depth: light`
line, no acceptance QA checked the spec. Print every `A<n>` statement tagged
`test` under `not verified (depth light)` with the rulings, so your human
partner chooses how to integrate with them in view. Without that line (a plan
that ran at standard or full depth, or one older than depth routing), print
nothing here.
```

- [ ] **Step 6: Run every suite that pins this file**

Run (from the repository root):

```bash
timeout 1500 bash -c 'for t in auto-run-skills auto-default final-phase project-status settings-skills task-step-text ui-ux-skill gates-manifest process-roles; do printf "%s: " "$t"; timeout 300 bash plugins/dforge/tests/$t.test.sh 2>&1 | tail -1; done'
```

Expected: nine lines, each ending `, 0 failed`; `auto-run-skills` reads `112 passed, 0 failed`.

Run: `node scripts/validate-repository.mjs`
Expected: `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`

- [ ] **Step 7: Commit**

```bash
git add plugins/dforge/skills/finishing-a-development-branch/SKILL.md plugins/dforge/tests/auto-run-skills.test.sh
git commit -m "docs(dforge): list unverified checks at finishing"
```

### Task 10: Describe review depth in the dforge README

**Files:**
- Modify: `plugins/dforge/README.md` (§What you get, a new paragraph directly after "**Review groups and wave checks.**")

**Interfaces:**
- Consumes: the behaviour of `scripts/depth-route` (Task 2), the plan-round cap (Task 3), the lens limits (Task 4), the plan-phase and spec-phase rules (Tasks 5 and 6), the final-review stages (Task 7) and the finishing list (Task 9); the paragraph states them, and the table is spec §6 verbatim.
- Produces: nothing a later task reads. No suite pins the new paragraph, and every phrase the suites pin in the README stays as it is.

**Depends on:** Task 2, Task 3, Task 4, Task 5, Task 6, Task 7, Task 9

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1

- [ ] **Step 1: Add the paragraph**

In `plugins/dforge/README.md`, replace this exact text (it appears once, at the end of the "**Review groups and wave checks.**" paragraph):

```text
whose failures do not grow counts as a pass. A `Host: codex` plan keeps
`review_cap: 5` and per-task review.
```

with:

````text
whose failures do not grow counts as a pass. A `Host: codex` plan keeps
`review_cap: 5` and per-task review.

**Review depth.** An architectural plan runs at one of three depths, sized by
risk rather than length. `scripts/depth-route` prints the depth: `full` for a
risk trigger (security, data loss, migration, concurrency), a new subsystem, or
any task at risk 3; `standard` when an interface that something outside its own
files depends on changes, or any task is at risk 2; `light` for everything else,
however many tasks the plan has. The spec records it on a `**Depth:**` line,
your human partner may set it there by hand (`**Depth:** light — owner`), and
the check after the plan is written can only raise it, from the tasks' real
scores. A spec with no `**Depth:**` line, a plan whose spec has none, and a
`Host: codex` plan run at `full`, so every plan written before depth routing
keeps today's process. The spec phase and the plan phase follow the depth:
light runs the self-review round alone and no plan review, and a light plan of
1-3 tasks goes on to execution in the same session when the budget allows,
standard folds the architecture critic into one Fable round and runs one plan
review round, and full runs the separate critic, one or two Fable rounds and
one or two plan review rounds. Execution is unchanged at every depth. The
final review scales as follows:

| Stage | light | standard | full |
|---|---|---|---|
| 0 Gates | runs | runs | runs |
| 0.2 UI proof | runs | runs | runs |
| 0.5 Acceptance QA | skipped | runs | runs |
| 1 Claude review (`dforge:judge-opus`) | runs | runs | runs |
| 1 Lenses | security only, when it applies | at most 2 | up to `lensCap` |
| 2 Codex round | skipped | skipped | as today |
| 3 Dedupe judge | never (one list) | never (one list) | with two lists |

At light, finishing lists the spec's `test` statements under
`not verified (depth light)`, since no acceptance QA checked them.
````

- [ ] **Step 2: Check the paragraph is in place and the README suites still pass**

Run: `grep -c '^\*\*Review depth\.\*\*' plugins/dforge/README.md`
Expected: `1`

Run: `grep -c '^| 0.5 Acceptance QA | skipped | runs | runs |' plugins/dforge/README.md`
Expected: `1`

Run: `grep -c 'not verified (depth light)' plugins/dforge/README.md`
Expected: `1`

Run (from the repository root):

```bash
timeout 1500 bash -c 'for t in auto-run-skills settings-skills inline-mode seats project-status lanes dforge-config executors; do printf "%s: " "$t"; timeout 300 bash plugins/dforge/tests/$t.test.sh 2>&1 | tail -1; done'
```

Expected: eight lines, each ending `, 0 failed`.

Run: `node scripts/validate-repository.mjs`
Expected: `Repository catalogs, manifests, versions, bundled links and the settings schema are valid.`

- [ ] **Step 3: Commit**

```bash
git add plugins/dforge/README.md
git commit -m "docs(dforge): describe review depth in the README"
```

### Task 11: Add the review-depth acceptance suite

**Files:**
- Create: `plugins/dforge/tests/review-depth.acceptance.test.sh`

**Interfaces:**
- Consumes: `scripts/depth-route` and `scripts/lib/depth.sh` (Contracts C1 and C2, Task 2); `review-route --plan-round` (C3, Task 3); `lens-route --final` (C4, Task 4); and the line grammar of C5, which Tasks 5 to 9 write into `skills/writing-plans/SKILL.md`, `skills/handoff/SKILL.md`, `skills/brainstorming/SKILL.md`, `skills/using-dforge/SKILL.md`, `reference/auto-run.md`, `reference/final-review.md`, `skills/executing-plans/SKILL.md`, `skills/subagent-driven-development/SKILL.md` and `skills/finishing-a-development-branch/SKILL.md`.
- Produces: nothing a later task reads. CI finds the suite by its name (`scripts/test-all.mjs` runs every `plugins/dforge/tests/*.test.sh`).

**Depends on:** Task 2, Task 3, Task 4, Task 5, Task 6, Task 7, Task 8, Task 9

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 2 - risk 0 = 2

The suite has one function per spec statement, `a1` to `a16`. It builds its own repository, specs and plans in `mktemp -d`, uses no fixed path or port, and reads the shipped scripts and documents only. The behavioural statements (A1 to A8, A13, A16) run the real scripts; A9 to A12, A14 and A15 are about what skills tell a session to do, so they pin the line grammar of Contracts C5 in the files that must carry it, the same way `tests/faster-plans.acceptance.test.sh` pins its skill text.

- [ ] **Step 1: Write the suite**

Create `plugins/dforge/tests/review-depth.acceptance.test.sh` with exactly this content:

```bash
#!/usr/bin/env bash
# Acceptance tests for the review-depth spec
# (docs/dforge/specs/2026-10-27-review-depth-design.md), statements A1-A16.
# Each test is written from the statement's text and reaches the behaviour
# through the scripts the spec names (depth-route, review-route, lens-route,
# plan-lint) or, where the statement is about what a skill tells a session to
# do, through the line grammar the shipped skills and references must carry.
# Usage:
#   bash review-depth.acceptance.test.sh            run every test
#   bash review-depth.acceptance.test.sh A5 A9      run the named tests only
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN/../.." && pwd)"
S="$PLUGIN/scripts"
DEPTH="$S/depth-route"
ROUTE="$S/review-route"
LENS="$S/lens-route"
LINT="$S/plan-lint"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n' "$1" "$3"; fail=$((fail + 1)); fi
}
lacks() { # lacks <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n' "$1" "$3"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}
matches() { # matches <name> <haystack> <ERE>
  if grep -qE -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       no match: [%s]\n' "$1" "$3"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
# MSYS_NO_PATHCONV below hands git.exe this path untranslated, so it must be a
# Windows path or git initialises a repository somewhere else.
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude"
unset CLAUDE_CONFIG_DIR CODEX_HOME AR_SESSION DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_PROJECT_DIR DFORGE_LENS_CAP
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1 MSYS_NO_PATHCONV=1
export DFORGE_LENS_MINOR_FROM=0
# No session gate file exists, so every plan round routes with reason=codex-off.
export DR_CODEX_SESSION_DIR="$TMP/codex-sessions" CLAUDE_CODE_SESSION_ID=review-depth-acceptance
printf '%s\n' '#!/usr/bin/env bash' "echo '[{\"id\":\"codex\",\"usable\":true,\"reason\":null}]'" > "$TMP/roster-stub"
export PLAN_LINT_ROSTER="$TMP/roster-stub"

doc() { tr -d '\r' < "$1" | tr '\n' ' ' | tr -s ' '; } # a file as one line, whitespace collapsed
between() { # between <text> <start> <end> — the text after the first <start> up to the next <end>
  local t=${1#*"$2"}
  [ "$t" != "$1" ] || { printf ''; return 0; }
  printf '%s' "${t%%"$3"*}"
}

# --- fixtures: a repository holding specs and plans ------------------------

R="$TMP/repo"
git init -q "$R"
git -C "$R" config user.email t@example.com
git -C "$R" config user.name t
git -C "$R" commit -q --allow-empty -m base
mkdir -p "$R/docs/dforge/specs" "$R/docs/dforge/plans"

mkspec() { # mkspec <file> [<Depth line>]
  { printf '# Fixture spec\n\n**Execution strategy:** parallel\n\n'
    [ -z "${2:-}" ] || printf '%s\n\n' "$2"
    printf '## Decisions\n\nFinish: merge\n\n## Problem\n\nSecurity, data loss and migration risk are named here on purpose.\n'
  } > "$R/docs/dforge/specs/$1"
}
mkspec spec-light.md '**Depth:** light — unenumerable'
mkspec spec-standard.md '**Depth:** standard — interface (set by hand)'
mkspec spec-full.md '**Depth:** full — risk'
mkspec spec-owner.md '**Depth:** light — owner'
mkspec spec-none.md
mkspec spec-weird.md '**Depth:** medium — nothing'

# mkplan <file> <spec file|-> <host|-> <task>... — a task is a risk digit, big
# (risk 1 with a total of 8), none (no Evaluation line) or bad (one that does
# not parse).
mkplan() {
  local f=$1 spec=$2 host=$3 i=0 t
  shift 3
  {
    printf '# Fixture Plan\n\n'
    [ "$host" = - ] || printf 'Host: codex\n\n'
    printf '**Goal:** Fixture.\n\n'
    [ "$spec" = - ] || printf '**Spec:** docs/dforge/specs/%s\n\n' "$spec"
    printf '**Execution:** subagent — `claude --model sonnet --effort high` — fixture\n\n'
    printf '**Parallelism:** sequential — fixture\n\n'
    [ -z "${PLAN_REVIEW:-}" ] || printf '%s\n\n' "$PLAN_REVIEW"
    printf '## Task index\n\n'
    for t in "$@"; do i=$((i + 1)); printf '%d. task %d\n' "$i" "$i"; done
    printf '\n'
    i=0
    for t in "$@"; do
      i=$((i + 1))
      printf '### Task %d: task %d\n\n' "$i" "$i"
      case $t in
        none) ;;
        bad) printf '**Evaluation:** not a score\n\n' ;;
        big) printf '**Evaluation:** files 3 - spec 3 - coupling 1 - risk 1 = 8\n\n' ;;
        *) printf '**Evaluation:** files 0 - spec 0 - coupling 0 - risk %d = %d\n\n' "$t" "$t" ;;
      esac
    done
  } > "$R/docs/dforge/plans/$f"
}

dt() { out=$(cd "$R" && timeout 60 bash "$DEPTH" "$@" 2>"$TMP/err"); rc=$?; err=$(cat "$TMP/err"); }
depth_of() { # depth_of <plan file> — the depth-route line for a plan in the fixture repository
  dt "docs/dforge/plans/$1"
}
rr() { out=$(cd "$R" && timeout 60 bash "$ROUTE" "$@" 2>"$TMP/err"); rc=$?; err=$(cat "$TMP/err"); }
lr() { out=$(cd "$R" && timeout 60 bash "${LENS_SCRIPT:-$LENS}" "$@" 2>"$TMP/err"); rc=$?; err=$(cat "$TMP/err"); }
short() { sed -E 's/ criteria=[^ ]*//; s/ seat=[^ ]*//; s/ reason=(always|added|ui-paths|paths:[^ ]*)$//' | tr '\n' ';'; }

# --- A1-A6, A13, A16: depth-route ------------------------------------------

a1() {
  local row list depth reason
  for row in \
    "risk|full|risk" "new-subsystem|full|new-subsystem" \
    "risk,new-subsystem|full|risk,new-subsystem" "new-subsystem,risk|full|risk,new-subsystem" \
    "asked,interface,risk|full|risk" "interface,new-subsystem|full|new-subsystem" \
    "interface|standard|interface" "asked,interface|standard|interface" \
    "unenumerable|light|unenumerable" "asked|light|asked" \
    "approach,intricate,asked|light|approach,intricate,asked"; do
    IFS='|' read -r list depth reason <<<"$row"
    dt --spec-triggers "$list"
    check "A1: [$list] routes depth=$depth reason=$reason" "$rc:$out" "0:depth=$depth reason=$reason"
  done
}

a2() {
  local list
  dt --spec-triggers ""
  check "A2: an empty list exits 2" "$rc" "2"
  check "A2: an empty list prints nothing on stdout" "$out" ""
  has "A2: an empty list is refused in depth-route's voice" "$err" "depth-route:"
  dt --spec-triggers
  check "A2: a missing list exits 2" "$rc" "2"
  check "A2: a missing list prints no depth= line" "$(grep -c '^depth=' <<<"$out")" "0"
  for list in bogus risk,bogus bogus,risk Risk; do
    dt --spec-triggers "$list"
    check "A2: [$list] exits 2" "$rc" "2"
    check "A2: [$list] prints no depth= line" "$(grep -c 'depth=' <<<"$out")" "0"
    has "A2: [$list] names the unknown id" "$err" "unknown trigger:"
  done
}

a3() {
  mkplan p3a.md spec-light.md - 0 3 1
  depth_of p3a.md
  check "A3: a task at risk 3 gives full" "$rc:$out" "0:depth=full spec=light tasks=full reason=task-risk:2"
  mkplan p3b.md spec-light.md - 1 2 0 2
  depth_of p3b.md
  check "A3: a highest risk of 2 gives standard" "$rc:$out" "0:depth=standard spec=light tasks=standard reason=task-risk:2"
  mkplan p3c.md spec-light.md - 0 1 1
  depth_of p3c.md
  check "A3: a highest risk of 1 gives light" "$rc:$out" "0:depth=light spec=light tasks=light reason=spec,task-risk:2"
  mkplan p3d.md spec-standard.md - 0 1
  depth_of p3d.md
  check "A3: the spec's standard outranks light tasks" "$rc:$out" "0:depth=standard spec=standard tasks=light reason=spec"
  mkplan p3e.md spec-standard.md - 1 3
  depth_of p3e.md
  check "A3: a risk-3 task outranks the spec's standard" "$rc:$out" "0:depth=full spec=standard tasks=full reason=task-risk:2"
  mkplan p3f.md spec-full.md - 2
  depth_of p3f.md
  check "A3: the spec's full outranks standard tasks" "$rc:$out" "0:depth=full spec=full tasks=standard reason=spec"
  mkplan p3g.md spec-standard.md - 2 0
  depth_of p3g.md
  check "A3: equal inputs name both" "$rc:$out" "0:depth=standard spec=standard tasks=standard reason=spec,task-risk:1"

  # An amendment that raises a task is read: the plan with its amendments applied.
  mkplan p3h.md spec-light.md - 1 1
  depth_of p3h.md
  check "A3: before the amendment the plan is light" "$rc:$out" "0:depth=light spec=light tasks=light reason=spec,task-risk:1"
  mkdir -p "$R/.dforge/sdd/p3h"
  {
    printf '## A1 — Task 2\n\n### Old\n\n````\n'
    printf '**Evaluation:** files 0 - spec 0 - coupling 0 - risk 1 = 1\n'
    printf '````\n\n### New\n\n````\n'
    printf '**Evaluation:** files 0 - spec 0 - coupling 0 - risk 3 = 3\n'
    printf '````\n'
  } > "$R/.dforge/sdd/p3h/amendments.md"
  depth_of p3h.md
  check "A3: an amendment that raises Task 2 to risk 3 gives full" "$rc:$out" "0:depth=full spec=light tasks=full reason=task-risk:2"
  rm -rf "$R/.dforge/sdd/p3h"
}

a4() {
  local i args=()
  for i in $(seq 1 40); do
    if [ $((i % 5)) -eq 0 ]; then args+=(big); else args+=($((i % 2))); fi
  done
  mkplan p4.md spec-light.md - "${args[@]}"
  check "A4: the fixture holds 40 tasks" "$(grep -c '^### Task ' "$R/docs/dforge/plans/p4.md")" "40"
  check "A4: and tasks with a total of 8" "$(grep -c '= 8$' "$R/docs/dforge/plans/p4.md")" "8"
  depth_of p4.md
  check "A4: 40 tasks at risk 1 or below stay light" "$rc:$out" "0:depth=light spec=light tasks=light reason=spec,task-risk:1"
}

a5() {
  mkplan p5a.md spec-none.md - 0
  depth_of p5a.md
  check "A5: a spec with no Depth line is full" "$rc:$out" "0:depth=full spec=none tasks=light reason=no-spec-depth"
  mkplan p5b.md - - 0
  depth_of p5b.md
  check "A5: a plan with no Spec line is full" "$rc:$out" "0:depth=full spec=none tasks=light reason=no-spec-depth"
  mkplan p5c.md missing.md - 0
  depth_of p5c.md
  check "A5: a Spec path that cannot be read is full" "$rc:$out" "0:depth=full spec=none tasks=light reason=no-spec-depth"
  mkplan p5d.md spec-weird.md - 0
  depth_of p5d.md
  check "A5: a Depth word outside the three is full" "$rc:$out" "0:depth=full spec=none tasks=light reason=no-spec-depth"
  mkplan p5e.md spec-light.md - 0 none 1
  depth_of p5e.md
  check "A5: a task with no Evaluation line is full" "$rc:$out" "0:depth=full spec=light tasks=full reason=unscored:2"
  mkplan p5f.md spec-light.md - 0 1 bad
  depth_of p5f.md
  check "A5: a task whose Evaluation does not parse is full" "$rc:$out" "0:depth=full spec=light tasks=full reason=unscored:3"
  mkplan p5g.md spec-light.md codex 0
  depth_of p5g.md
  check "A5: a Host: codex plan is full" "$rc:$out" "0:depth=full spec=light tasks=light reason=codex-host"
}

a6() {
  mkplan p6a.md spec-full.md - 0 0
  depth_of p6a.md
  check "A6: a full spec with every task at risk 0 stays full" "$rc:$out" "0:depth=full spec=full tasks=light reason=spec"
  mkplan p6b.md spec-full.md - 0 1 1
  depth_of p6b.md
  check "A6: and with tasks at risk 1" "$rc:$out" "0:depth=full spec=full tasks=light reason=spec"
}

a13() {
  mkplan p13a.md spec-owner.md - 0 1
  depth_of p13a.md
  check "A13: an owner line reads as spec=light whatever the spec says of its risks" "$rc:$out" "0:depth=light spec=light tasks=light reason=spec,task-risk:2"
  mkplan p13b.md spec-owner.md - 0 2
  depth_of p13b.md
  check "A13: a task at risk 2 still raises it to standard" "$rc:$out" "0:depth=standard spec=light tasks=standard reason=task-risk:2"
  mkplan p13c.md spec-owner.md - 3 0
  depth_of p13c.md
  check "A13: a task at risk 3 still raises it to full" "$rc:$out" "0:depth=full spec=light tasks=full reason=task-risk:1"
}

a16() {
  mkplan p16a.md spec-standard.md - 0
  depth_of p16a.md
  check "A16: a Depth line is read by its first word" "$rc:$out" "0:depth=standard spec=standard tasks=light reason=spec"

  . "$HERE/fixtures/darkmem-stores.sh"
  local SH="$TMP/stores-home" SR="$TMP/stores-repo" M
  mkdir -p "$SH"
  git init -q "$SR"
  M=$(stores_home "$SH" "$SR" proj darkmem darkmem)
  mkdir -p "$M/dforge/specs" "$M/dforge/plans" "$SR/docs/dforge/specs"
  printf '# Spec\n\n**Depth:** light — unenumerable\n' > "$M/dforge/specs/s.md"
  printf '# Stale local copy\n\n**Depth:** full — risk\n' > "$SR/docs/dforge/specs/s.md"
  {
    printf '# P\n\n**Goal:** Fixture.\n\n**Spec:** docs/dforge/specs/s.md\n\n## Task index\n\n1. one\n\n'
    printf '### Task 1: one\n\n**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0\n'
  } > "$M/dforge/plans/p.md"
  out=$(cd "$SR" && HOME="$SH" timeout 60 bash "$DEPTH" docs/dforge/plans/p.md 2>"$TMP/err"); rc=$?
  check "A16: a Spec path in the darkmem mirror resolves as plan-lint resolves it" "$rc:$out" \
    "0:depth=light spec=light tasks=light reason=spec,task-risk:1"
  out=$(cd "$SR" && HOME="$SH" timeout 60 bash "$LINT" docs/dforge/plans/p.md --no-probe 2>&1)
  check "A16: plan-lint resolves the same path" "$(grep -c 'Spec path does not exist' <<<"$out")" "0"
}

# --- A7: review-route's plan-round cap -------------------------------------

a7() {
  mkplan p7l.md spec-light.md - 0 1
  mkplan p7s.md spec-standard.md - 1
  mkplan p7f.md spec-full.md - 0
  rr docs/dforge/plans/p7l.md --plan-round 1
  check "A7: light round 1 routes to no seat, cap 0" "$rc:$out" "0:review-seat plan-round=1 primary=none fallback=- reason=depth-light cap=0"
  rr docs/dforge/plans/p7l.md --plan-round 2
  check "A7: light round 2 exits 2" "$rc" "2"
  has "A7: and says the round is past the cap" "$err" "plan round 2 is past the cap (0)"
  rr docs/dforge/plans/p7s.md --plan-round 1
  check "A7: standard round 1 has cap 1" "$rc:$out" "0:review-seat plan-round=1 primary=dforge:judge-opus fallback=- reason=codex-off cap=1"
  rr docs/dforge/plans/p7s.md --plan-round 2
  check "A7: standard round 2 exits 2" "$rc" "2"
  rr docs/dforge/plans/p7f.md --plan-round 1
  check "A7: full round 1 has cap 2" "$rc:$out" "0:review-seat plan-round=1 primary=dforge:judge-opus fallback=- reason=codex-off cap=2"
  rr docs/dforge/plans/p7f.md --plan-round 2
  check "A7: full round 2 is a round within cap 2" "$rc:$out" "0:review-seat plan-round=2 primary=dforge:judge-opus fallback=- reason=round cap=2"
  rr docs/dforge/plans/p7f.md --plan-round 3
  check "A7: full round 3 exits 2" "$rc" "2"

  # A Host: codex plan keeps its own cap rule, from its highest raw total.
  local spec
  for spec in spec-light.md -; do
    {
      printf '# Native Fixture\n\n**Host:** codex\n**Routing policy:** codex-v4\n'
      [ "$spec" = - ] || printf '**Spec:** docs/dforge/specs/%s\n' "$spec"
      printf '**Execution:** inline — codex gpt-6.1-sol / high — x\n\n### Task 1: low\n\n'
      printf '**Implementer:** codex gpt-6-luna / high\n'
      printf '**Evaluation:** files=0, spec=0, coupling=0, risk=0; weighted routing score=0\n'
      printf '**Assignment source:** rubric\n'
    } > "$R/docs/dforge/plans/p7n${spec%%.*}.md"
  done
  rr docs/dforge/plans/p7nspec-light.md --plan-round 1
  local with=$out
  rr docs/dforge/plans/p7n-.md --plan-round 1
  check "A7: a Codex plan's round 1 does not read the spec's depth" "$with" "$out"
  matches "A7: and keeps the cap its raw total sets (1)" "$with" 'plan-round=1 primary=native:[^ ]+ fallback=- reason=round cap=1$'
  rr docs/dforge/plans/p7nspec-light.md --plan-round 2
  matches "A7: a Codex plan keeps its cap-critical round" "$rc:$out" '^0:review-seat plan-round=2 .* reason=cap-critical cap=1$'
}

# --- A8: lens-route at each depth ------------------------------------------

a8() {
  local base head out_full out_std
  base=$(git -C "$R" rev-parse HEAD)
  mkdir -p "$R/scripts" "$R/tests"
  printf 'echo hi 2>/dev/null\n' > "$R/scripts/foo.sh"
  printf 'print(1)\n' > "$R/scripts/foo.py"
  printf 'try { run() } catch (e) {}\n' > "$R/tests/a.test.ts"
  printf 'Docs.\n' > "$R/NOTES.md"
  git -C "$R" add scripts tests NOTES.md
  git -C "$R" commit -q -m lens-fixture
  head=$(git -C "$R" rev-parse HEAD)
  mkplan p8l.md spec-light.md - 0 1
  mkplan p8s.md spec-standard.md - 1
  mkplan p8f.md spec-full.md - 0

  lr docs/dforge/plans/p8f.md --final "$base" "$head"
  out_full=$out
  check "A8: full prints every lens up to the cap of 4, the rest skipped for the cap" "$(short <<<"$out_full")" \
    "lens security;lens silent-failures;lens test-quality;lens lang-bash;lens-skipped lang-python reason=cap;lens-skipped lang-typescript reason=cap;lens-skipped docs-comments reason=cap;"

  lr docs/dforge/plans/p8l.md --final "$base" "$head"
  check "A8: light prints a lens line for security alone" "$(grep -c '^lens ' <<<"$out")" "1"
  check "A8: light keeps security" "$(grep -c '^lens security ' <<<"$out")" "1"
  check "A8: light skips every other applicable lens for the depth" "$(short <<<"$out")" \
    "lens security;lens-skipped silent-failures reason=depth;lens-skipped test-quality reason=depth;lens-skipped lang-bash reason=depth;lens-skipped lang-python reason=depth;lens-skipped lang-typescript reason=depth;lens-skipped docs-comments reason=depth;"
  check "A8: light skips no lens for the cap" "$(grep -c 'reason=cap' <<<"$out")" "0"

  lr docs/dforge/plans/p8s.md --final "$base" "$head"
  out_std=$out
  check "A8: standard prints at most 2 lens lines" "$(grep -c '^lens ' <<<"$out_std")" "2"
  check "A8: standard skips the rest for the cap" "$(short <<<"$out_std")" \
    "lens security;lens silent-failures;lens-skipped test-quality reason=cap;lens-skipped lang-bash reason=cap;lens-skipped lang-python reason=cap;lens-skipped lang-typescript reason=cap;lens-skipped docs-comments reason=cap;"
  out=$(cd "$R" && DFORGE_LENS_CAP=1 timeout 60 bash "$LENS" docs/dforge/plans/p8s.md --final "$base" "$head" 2>&1)
  check "A8: standard with lensCap 1 prints 1 lens line" "$(grep -c '^lens ' <<<"$out")" "1"

  out=$(cd "$R" && DFORGE_LENS_CAP=0 timeout 60 bash "$LENS" docs/dforge/plans/p8l.md --final "$base" "$head" 2>&1)
  check "A8: lenses off is unchanged at light" "$out" "lenses off"

  # Security prints only when its Applies clause matches: a copy of the lenses
  # whose security lens applies to nothing in this change.
  local copy="$TMP/plugin-copy"
  mkdir -p "$copy"
  cp -R "$S" "$copy/scripts"
  cp -R "$PLUGIN/criteria" "$PLUGIN/config" "$copy/"
  sed -i.bak 's#^Applies: .*#Applies: paths docs/never/*#' "$copy/criteria/lenses/security.md"
  LENS_SCRIPT="$copy/scripts/lens-route" lr docs/dforge/plans/p8l.md --final "$base" "$head"
  check "A8: light prints no security line when its clause does not match" "$(grep -c 'security' <<<"$out")" "0"
  check "A8: and still skips the other lenses for the depth" "$(grep -c '^lens-skipped .* reason=depth$' <<<"$out")" "6"
  LENS_SCRIPT="$copy/scripts/lens-route" lr docs/dforge/plans/p8f.md --final "$base" "$head"
  check "A8: full is unchanged without a matching security lens" "$(grep -c '^lens ' <<<"$out")" "4"
}

# --- text statements: the line grammar the shipped skills carry ------------

BS="$PLUGIN/skills/brainstorming/SKILL.md"
UD="$PLUGIN/skills/using-dforge/SKILL.md"
AR="$PLUGIN/reference/auto-run.md"
WP="$PLUGIN/skills/writing-plans/SKILL.md"
HO="$PLUGIN/skills/handoff/SKILL.md"
FR="$PLUGIN/reference/final-review.md"
EP="$PLUGIN/skills/executing-plans/SKILL.md"
SD="$PLUGIN/skills/subagent-driven-development/SKILL.md"
FIN="$PLUGIN/skills/finishing-a-development-branch/SKILL.md"

a9() {
  local bs
  bs=$(doc "$BS")
  has "A9: brainstorming reports the skipped critic at light" "$bs" 'Critic: skipped (depth light)'
  lacks "A9: the fold no longer keys on the Process line's triggers" "$bs" 'names neither irreducible risk nor a new'
  matches "A9: the spec review message carries the depth" "$bs" 'Depth: <[a-z]+> — <reason'
}

a10() {
  local wp ho out_with out_without
  wp=$(doc "$WP"); ho=$(doc "$HO")
  has "A10: writing-plans records the skipped plan review at light" "$wp" '**Plan review:** <YYYY-MM-DD> — skipped (depth light)'
  has "A10: writing-plans runs the handoff steps first" "$wp" 'handoff steps 0-4'
  has "A10: and measures the budget with plain context-size" "$wp" 'context-size'
  has "A10: standard and full keep the hard stop" "$wp" 'hard stop'
  matches "A10: handoff names the depth in its hard-stop rule" "$ho" 'depth'
  lacks "A10: handoff no longer calls every saved plan a hard stop" "$ho" '(plan saved outside an auto run, or a switch'

  mkplan p10.md spec-light.md - 0
  out_without=$(cd "$R" && timeout 60 bash "$LINT" docs/dforge/plans/p10.md --no-probe 2>&1)
  has "A10: plan-lint warns while the header has no Plan review line" "$out_without" 'no **Plan review:** line yet'
  PLAN_REVIEW='**Plan review:** 2026-10-27 — skipped (depth light)' mkplan p10b.md spec-light.md - 0
  out_with=$(cd "$R" && timeout 60 bash "$LINT" docs/dforge/plans/p10b.md --no-probe 2>&1)
  lacks "A10: plan-lint accepts the skipped line with no Plan review warning" "$out_with" 'no **Plan review:** line yet'
  check "A10: and no header warning mentions it" "$(grep -ci 'WARN header.*plan review' <<<"$out_with")" "0"
}

a11() {
  local fr ep sd head0 step05 step2
  fr=$(doc "$FR"); ep=$(doc "$EP"); sd=$(doc "$SD")
  has "A11: final-review.md skips acceptance QA at light with the ledger line" "$fr" 'Acceptance QA: skipped (depth light)'
  matches "A11: recovery treats the skipped line as complete" "$fr" 'skipped \(depth light\).{0,300}complete|complete.{0,300}skipped \(depth light\)'
  has "A11: the Codex round skipped is said in one line" "$fr" 'codex round skipped (depth'
  has "A11: the review logs its depth" "$fr" 'Review depth: <'
  head0=${fr%%'0. **Gates.**'*}
  has "A11: the depth is logged before step 0" "$head0" 'Review depth: <'
  step05=$(between "$fr" '- 0.5 **Acceptance QA.**' '1. **Claude review.**')
  has "A11: step 0.5 carries the light skip" "$step05" 'skipped (depth light)'
  step2=$(between "$fr" '2. **Codex round.**' '3. **Wait for QA.**')
  has "A11: step 2 carries the Codex skip" "$step2" 'codex round skipped (depth'
  has "A11: executing-plans lists the Review depth ledger line" "$ep" 'Review depth: <'
  has "A11: executing-plans lists the skipped QA ledger line" "$ep" 'Acceptance QA: skipped (depth light)'
  has "A11: subagent-driven-development lists the Review depth ledger line" "$sd" 'Review depth: <'
  has "A11: and the skipped QA ledger line" "$sd" 'Acceptance QA: skipped (depth light)'
}

a12() {
  local fr gates ui claude fixwave p
  mkplan p12l.md spec-light.md - 0 1
  mkplan p12s.md spec-standard.md - 1
  mkplan p12f.md spec-full.md - 0 1
  for p in p12l p12s p12f; do
    rr "docs/dforge/plans/$p.md" --final
    check "A12: review-route --final still routes the whole-branch Claude review ($p)" "$rc:$out" \
      "0:review-seat final primary=dforge:judge-opus fallback=- reason=plain"
  done
  fr=$(doc "$FR")
  gates=$(between "$fr" '0. **Gates.**' '- 0.2 **UI proof.**')
  ui=$(between "$fr" '- 0.2 **UI proof.**' '- 0.5 **Acceptance QA.**')
  claude=$(between "$fr" '1. **Claude review.**' '**Lenses.**')
  fixwave=${fr#*'## Fixing what it finds'}
  check "A12: the Gates step is found" "$([ -n "$gates" ] && echo yes || echo no)" "yes"
  check "A12: the UI proof step is found" "$([ -n "$ui" ] && echo yes || echo no)" "yes"
  check "A12: the Claude review step is found" "$([ -n "$claude" ] && echo yes || echo no)" "yes"
  lacks "A12: gates are not cut by a depth" "$gates" 'depth'
  lacks "A12: the UI proof is not cut by a depth" "$ui" 'depth'
  lacks "A12: the Claude review is not cut by a depth" "$claude" 'depth'
  lacks "A12: the fix wave is not cut by a depth" "$fixwave" 'depth light'
  has "A12: the light approve option says the plan is not a stop" "$(doc "$BS")" 'depth light: the plan is not a stop'
}

a14() {
  local ud bs spec_text
  ud=$(doc "$UD"); bs=$(doc "$BS")
  has "A14: using-dforge states the architectural Process line" "$ud" 'Process: architectural, <inline|subagent>, depth <d> — <triggers>'
  has "A14: brainstorming states it too" "$bs" 'Process: architectural, <inline|subagent>, depth <d> — <triggers>'
  matches "A14: brainstorming writes the Depth line" "$bs" '\*\*Depth:\*\* <[^>]+> — <reason'
  matches "A14: and the owner's Depth line" "$bs" '\*\*Depth:\*\* <[^>]+> — owner'
  spec_text="$REPO_ROOT/docs/dforge/specs/2026-10-27-review-depth-design.md"
  check "A14: this spec carries Depth below Execution strategy" \
    "$(awk '/^\*\*Execution strategy:\*\*/ { e = NR } /^\*\*Depth:\*\*/ { d = NR } END { print (e > 0 && d > e) ? "yes" : "no" }' "$spec_text")" "yes"
}

a15() {
  local fr step4 fin ar
  fr=$(doc "$FR"); fin=$(doc "$FIN"); ar=$(doc "$AR")
  step4=$(between "$fr" '4. **Report.**' '## Fixing what it finds')
  check "A15: final-review.md step 4 is found" "$([ -n "$step4" ] && echo yes || echo no)" "yes"
  has "A15: step 4 writes lens-skipped lines to the ledger" "$step4" 'final review lens-skipped'
  lacks "A15: step 4 no longer writes only reason=cap" "$step4" 'lens-skipped <id> reason=cap'
  has "A15: finishing reads the ledger's lens-skipped lines" "$fin" 'final review lens-skipped'
  lacks "A15: finishing no longer reads only reason=cap" "$fin" 'lens-skipped <id> reason=cap'
  lacks "A15: auto-run.md's Finishing no longer reads only reason=cap" "$ar" 'lens-skipped <id> reason=cap'
  has "A15: finishing lists the unverified test statements at light" "$fin" 'not verified (depth light)'
  has "A15: from the statements tagged test" "$fin" 'tagged `test`'
  has "A15: auto-run.md's Finishing lists them too" "$ar" 'not verified (depth light)'
}

ALL="a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16"
if [ $# -gt 0 ]; then
  sel=""
  for n in "$@"; do sel="$sel $(tr 'A-Z' 'a-z' <<<"$n")"; done
else
  sel=$ALL
fi
for t in $sel; do "$t"; done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the suite**

Run: `bash -n plugins/dforge/tests/review-depth.acceptance.test.sh`
Expected: no output.

Run: `timeout 300 bash plugins/dforge/tests/review-depth.acceptance.test.sh 2>&1 | tail -3`
Expected: the last line reads `<N> passed, 0 failed` (about 130 checks) and the exit status is 0.

A `FAIL` line in a text check means the task that owns the phrase left out a line that Contracts C5 fixes. Do not weaken the pin and do not edit that file here: stop with BLOCKED and name the failing check and its owner. The owners are: A9 and A14, Task 6 (brainstorming, using-dforge); A10, Task 5 (writing-plans, handoff); A11 on `reference/final-review.md` and A12, Task 7; A11 on the two execution skills, Task 8; A15 on step 4, Task 7, and on finishing, Task 9, and on `not verified (depth light)` in auto-run.md, Task 6. A failure in A1 to A8, A13 or A16 belongs to Task 2 (A1 to A6, A13, A16), Task 3 (A7) or Task 4 (A8).

- [ ] **Step 3: Run the neighbouring suites the new text must not break**

Run (from the repository root):

```bash
timeout 2400 bash -c 'for t in depth-route review-route lens-route process-roles faster-plans.acceptance auto-default auto-run-skills; do printf "%s: " "$t"; timeout 600 bash plugins/dforge/tests/$t.test.sh 2>&1 | tail -1; done'
```

Expected: seven lines, each ending `, 0 failed`.

- [ ] **Step 4: Commit**

```bash
git add plugins/dforge/tests/review-depth.acceptance.test.sh
git commit -m "test(dforge): add review-depth acceptance suite"
```
