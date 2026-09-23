# Native Codex routing on GPT-6: `codex-v3`

A new native routing policy that moves every execution rank off GPT-5.6 onto
GPT-6 Luna, Sol and Astra, with a hard cut from `codex-v2` and a conversion path
for plans that pin it. Native Codex host only; the Claude-hosted external lane
already moved to `gpt-6-sol` in `a8a7e4f` and is not touched.

Item register: `docs/superpowers/registers/2026-09-23-codex-v3.md`.

## 1. Purpose

`codex-v2` (`plugins/dr-superpowers/reference/codex-routing.json`) ranks 0–7 on
`gpt-5.6-luna`, `gpt-5.6-terra` and `gpt-5.6-sol`, and 8–9 on `gpt-6-astra`.
OpenAI released GPT-6 Sol and GPT-6 Luna on 2026-09-22. This design ranks all
ten scores on GPT-6 models, drops Terra, and keeps everything else about native
routing — the weighted score, Rule S, the selector's escalation, split and
reserve logic, and the five-round review cap — as it is.

Editing `codex-v2` in place would silently change what an existing plan's ranks
mean, so this is a new version, as `codex-v1` → `codex-v2` was
(`docs/superpowers/specs/2026-09-08-codex-terra-scoring-design.md`).

## 2. Facts this design rests on

Checked on 2026-09-23 unless stated.

- `~/.codex/models_cache.json` (Codex 0.155.1, ChatGPT Pro sign-in, fetched
  2026-09-23T02:07:21Z) lists `gpt-6-astra` and `gpt-6-sol` with efforts
  low, medium, high, xhigh, max, ultra, and `gpt-6-luna` with low through max —
  no ultra. `gpt-5.6-luna`, `gpt-5.6-terra` and `gpt-5.6-sol` are still listed.
- **Upgrade markers are not current.** Commit `a8a7e4f` (2026-09-22T19:02Z)
  records that the catalog then listed `gpt-6-sol` as the upgrade for
  `gpt-5.6-sol`. The cache fetched seven hours later carries `upgrade: null` on
  all three GPT-5.6 entries. Nothing below depends on the markers; Terra's
  removal is a policy choice, not a catalog instruction.
- OpenAI's Codex models page (learn.chatgpt.com/docs/models), verbatim: "Start
  with **Medium** for Sol, **High** for Luna, or **Light** for Astra", where
  Light is **Low** in the CLI; "**Ultra** uses subagents to handle separate
  parts of a complex task in parallel"; "GPT-5.6 Sol, GPT-5.6 Terra, and GPT-5.6
  Luna remain available during the rollout". GPT-5.5 retires from Codex on
  2026-10-14; no GPT-5.6 retirement date is announced.
- A smoke run through `run-codex-task.sh` passed at `gpt-6-sol/low` on
  2026-09-23 (`docs/superpowers/notes/2026-09-20-review-routing-calibration.md`
  §Smoke test — `gpt-6-sol`). GPT-6 Luna has never run through any path here.
- No plan in this repository is a live `codex-v2` plan: the only
  `Routing policy: codex-v2` lines are test fixtures and a fixture quoted inside
  `docs/superpowers/plans/2026-09-12-dr-superpowers-small-model-planning.md`.
  Whether other repositories hold v2 plans is unknown.
- `scripts/plan-lint` runs when a plan is written or revised, never during
  execution; `scripts/plan-amend` refuses any `Host:` or `Routing policy:` line.

## 3. Decisions

| # | Question | Decision |
|---|---|---|
| 1 | Rank table, weights, rank count | Table in §4. Formula `files + spec + coupling + 2 × risk` and ten ranks unchanged |
| 2 | Reserve | Astra max, then Astra ultra. Sol max/ultra excluded |
| 3 | Role floors, review cap | implementer 0, scout 4 (Sol medium, was rank 6), judge 8 (Astra high, unchanged); cap 5 |
| 4 | Converting v2 plans | §6: preview, approval, in place for unstarted plans, ledger ruling for started ones |
| 5 | v2 lifetime | Hard cut: v2 is rejected from the release that ships v3 |
| 6 | Where v2 strings live | §9 inventory; adds a Codex-plan guard to `plan-revise` (§8) |
| 7 | Verifying Luna | One owner-approved smoke run at `gpt-6-luna/low` gates the release (§7) |

Keeping the formula means a task's score never changes on conversion; only the
pair each rank maps to changes. Rule S still bounds the reducible subtotal at 3,
and all ten scores stay reachable.

## 4. The policy

`reference/codex-routing.json` becomes:

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

Where the work lands: risk 0 spans scores 0–3 (Luna, or Sol low at a reducible
subtotal of 3); risk 3 spans 6–9, so a risk-3 task runs on Sol xhigh only when
its reducible axes are all 0, and on Astra otherwise.

Why this shape:

- Same structure as v2: the cheapest model takes the bottom, Sol the middle,
  Astra the top. Sol xhigh sits directly below Astra, which is where this
  plugin already places it — the external lane's successor chain climbs
  `gpt-6-sol` to xhigh before HANDBACK, and the `codex-judge` fallback row is
  `gpt-6-sol xhigh` (`reference/ladder.md`).
- The judge floor keeps its pair (Astra high, rank 8), so native judges still
  judge at the tier the Claude-hosted `codex-judge` block names. The scout floor
  keeps its pair (Sol medium), which moves from rank 6 to rank 4.
- The reserve is reached only after a task has exhausted Astra xhigh and its one
  split. Sol max or ultra there would step down in model, and the reserve must be
  monotone. Luna xhigh and max, and Astra low, are left unranked.
- These placements are policy choices. Cross-model effort comparisons remain
  unmeasured, as they were for v2. OpenAI's "start with" efforts are interactive
  defaults, not a ranking; ranks 0–1 and 3 sit below the model's recommended
  start on purpose, for transcription-sized work.

**Ultra fans out.** An ultra implementer may run subagents in parallel inside
its own task. The task's approved write set, the before/after snapshot and the
review still apply to the task as a whole. Only implementers reach the reserve,
so the no-delegation instruction for scouts and judges is unaffected.
`native-codex.md` states this next to the reserve rule.

## 5. The selector

`scripts/select-native-tier.sh` keeps its logic. It already accepts exactly the
policy file's `version`, so a request tagged `codex-v1`, `codex-v2` or any
unknown value exits 2 with the conversion-required error. One change: the error
text currently hardcodes "codex-v2"; it names `$p.version` instead
(`unsupported routing policy; conversion required before using codex-v3`).

## 6. The hard cut and conversion

From the release that ships v3, only `codex-v3` is accepted by the selector and
by `plan-lint`. The rules below specialise `native-codex.md` §Existing plans
(written for v1 → v2), which is rewritten to say them.

**Preview.** For each task: raw axes, old policy, score — stated as unchanged,
because the formula is the same — the v2 pair and the proposed v3 pair. The
proposed v3 pair for a rubric task is `execution[score]`. Tasks without all
four raw axes need an explicit evaluation; never infer axes from a total. Your
human partner approves the preview before anything is recorded.

**Human pins and reserve overrides are never translated.** A pin is preserved
verbatim, including one that names a GPT-5.6 pair: the selector dispatches any
advertised pinned pair, so it stays valid while GPT-5.6 is advertised. The
preview flags every such pin so it can be kept or re-pinned by an explicit
decision.

**Unstarted plan (no ledger).** Converted in place, then committed:

- `Routing policy: codex-v3`, keeping the line's existing bold or plain form.
- Every `Assignment source: rubric` task's `**Implementer:**` line takes
  `execution[score]`. The Execution line's pair maps by rank: a v2 execution
  pair becomes the v3 pair at the same rank (v2 `gpt-5.6-sol / high`, rank 7,
  becomes `gpt-6-astra / medium`), and a reserve pair stays itself. Both appear
  in the preview. Evaluation lines are untouched.
- A `## Policy conversion` section goes in the header, immediately before
  `## Task index`, so no task's text absorbs it:

  ```text
  ## Policy conversion

  codex-v2 → codex-v3, approved <date>. Scores unchanged.

  | Task | Axes (f/s/c/r) | Score | codex-v2 | codex-v3 | Source |
  |---|---|---|---|---|---|
  | 1 | 1/1/1/0 | 3 | gpt-5.6-terra / medium | gpt-6-sol / low | rubric |
  | 2 | 0/1/0/1 | 3 | gpt-5.6-sol / high | gpt-5.6-sol / high | human (kept) |
  ```

`plan-lint` must pass on the converted plan.

**Plan with a ledger.** The plan file does not change: plans are immutable
during execution, `plan-amend` refuses `Routing policy:` lines, and `plan-lint`
does not run during execution. At a reconciled task boundary, after approval,
the controller writes one ledger line in the existing grammar:

```text
Ruling: policy conversion codex-v2 -> codex-v3 — approved preview; Task 4 gpt-6-sol / low, Task 5 gpt-6-astra / medium — attempts above this line stay codex-v2
```

From then on the controller's selector requests carry `"policy": "codex-v3"`.
Recorded attempts keep their v2 tags and are never relabelled or re-ranked.
Consumed split and review budgets carry over unchanged. A not-yet-started task
starts with empty v3 rank history.

**A task mid-escalation** when the plugin updates has attempt history in v2
ranks, which v3 cannot represent. The controller stops for an explicit handoff
decision — the existing rule — rather than fabricating v3 ranks.

**Native-to-Claude conversion** is unchanged apart from the version name.

## 7. The Luna gate

The implementation plan's first task, before the policy commit lands:

1. Confirm from `~/.codex/models_cache.json` that `gpt-6-luna` is listed with
   `low` among its efforts. This reads a file and costs nothing.
2. With explicit owner approval, run one smoke at `gpt-6-luna/low`: the same
   one-file brief and checks as the 2026-09-23 `gpt-6-sol` smoke, in a
   disposable linked worktree, through `codex exec -m gpt-6-luna -c
   model_reasoning_effort=low`. `run-codex-task.sh` cannot be used: it admits
   only the lane's `gpt-6-sol`, and widening its admission for a test is out of
   scope. Checks: exit 0; exactly one commit; `smoke.txt` holds
   `codex lane smoke test` (22 bytes with the newline); the diff touches only
   `smoke.txt`; the worktree is clean afterwards.
3. Record the run under a new heading in
   `docs/superpowers/notes/2026-09-20-review-routing-calibration.md`, which
   already holds both lane smoke records.

A failure on any check stops implementation for the owner's decision. The run
shows Luna is reachable on this account and follows a write set; it says
nothing about output quality at ranks 0–2. This is a one-time acceptance run,
not a routing-time probe: the selector contract's "no paid capability probes"
still holds.

## 8. `plan-lint` and `plan-revise`

**plan-lint.** For a `Host: codex` plan, read the `Routing policy:` line (bold
or plain, like `Host:`). If it is missing or differs from `.version` in
`codex-routing.json`, emit one finding and skip the Execution-pair and
Implementer-rank checks, which would otherwise each fail on every GPT-5.6 pair:

```text
ERROR header: Routing policy is codex-v2, not codex-v3; convert the plan per reference/native-codex.md §Existing plans
```

(`missing` in place of the found value when the line is absent.)

**plan-revise.** Verified 2026-09-23: given a `Host: codex` plan, single-plan
mode reports every task `score=?` and recommends
`execution=inline model=sonnet effort=high`; the revising-plans skill would
then rewrite a Codex plan into Claude format. This predates v3 but sits on the
conversion path, so it is fixed here:

- Single-plan mode on a `Host: codex` plan exits 2 with
  `plan-revise: <file> is a Codex-host plan; convert it per reference/native-codex.md §Existing plans`.
- Survey mode prints `plan  <file>  host=codex  skipped` for such a plan instead
  of a scored row, and does not count it as a Claude plan.
- `skills/revising-plans/SKILL.md` states it revises Claude plans only and names
  the refusal.

## 9. Change inventory

Every location verified on 2026-09-23 against branch `feat/codex-gpt-6-sol`
(plugin 1.19.0). Acceptance checks, run from `plugins/dr-superpowers`:

- `grep -rn 'codex-v2' .` hits only `reference/native-codex.md`'s conversion
  text and the v2 rejection fixtures in `tests/native-routing.test.sh`,
  `tests/plan-lint.test.sh` and `tests/plan-revise.test.sh`.
- `grep -rn 'gpt-5\.6' reference/codex-routing.json reference/native-codex.md skills tests/native-routing.test.sh tests/next-step.test.sh`
  hits only conversion text and v2 input fixtures.

These GPT-5.6 mentions stay: `README.md:149` and `:182` and
`reference/ladder.md:222`, `:224` and `:316` are dated history of the Claude
lane, and `tests/codex-client.test.sh:30` and `:68` pass an arbitrary model
string through the Claude lane's client.

| File | Change |
|---|---|
| `reference/codex-routing.json` | §4 |
| `scripts/select-native-tier.sh` | §5 error text |
| `scripts/plan-lint` | §8 policy check |
| `scripts/plan-revise` | §8 Codex refusal and survey skip |
| `reference/native-codex.md` | Rank table; version in new-plan header text; Implementer example becomes `codex gpt-6-astra / medium` for score 7; selector example JSON uses `codex-v3` and advertises `gpt-6-astra / medium`, with its sentence updated; "Scouts start at rank 4 (Sol medium)"; ultra note (§4); §Existing plans rewritten per §6 |
| `README.md:38` | `codex-v3`; "through Luna, Sol and Astra" |
| `skills/writing-plans/SKILL.md:114`, `:219` | `codex-v3` |
| `skills/subagent-driven-development/SKILL.md:31` | `codex-v3` |
| `skills/revising-plans/SKILL.md` | §8 |
| `reference/ladder.md:5` | `codex-v3` |
| `reference/delegated-task.md:317` | `codex-v3` |
| `scripts/next-step` | None: `launch_for` already names GPT-6 pairs, and a plan's launch command comes from its own Execution line |
| `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json` | 1.19.0 → 1.20.0; neither carries a model string |

## 10. Testing

No test calls a model. All run under a bounded timeout.

- `tests/native-routing.test.sh`: the fixture advertises the ten v3 execution
  pairs plus Astra max and ultra. The score table becomes: 0 `0/0/0/0` Luna
  low; 1 `1/0/0/0` Luna medium; 2 `1/1/0/0` Luna high; 3 `1/1/1/0` Sol low;
  4 `1/1/0/1` Sol medium; 5 `1/1/1/1` Sol high; 6 `1/1/0/2` Sol xhigh;
  7 `1/1/1/2` Astra medium; 8 `1/1/0/3` Astra high; 9 `1/1/1/3` Astra xhigh.
  The Terra cases become: a missing Luna effort promotes within Luna (score 1,
  only Luna high advertised → rank 2); missing Luna promotes to Sol low
  (score 2 → rank 3). Scout floor → `[4,"gpt-6-sol","medium"]`; judge floor →
  `[8,"gpt-6-astra","high"]`; a judge offered only Sol xhigh is blocked; the
  no-demotion case offers only Sol xhigh and Astra max for score 9 and expects
  `blocked`. `codex-v2` joins `codex-v1` and `codex-v99` as rejected with
  "conversion required". The documented-example check expects
  `["dispatch",7,7,"gpt-6-astra","medium"]`. Every other case keeps its intent
  with v3 pairs substituted.
- `tests/plan-lint.test.sh`: the Codex fixture uses `codex-v3`,
  `codex gpt-6-sol / high` on the Execution line and `codex gpt-6-sol / low`
  for Task 1 (score 3). The below-score variant uses `gpt-6-luna / high`
  (rank 2) and the promotion variant `gpt-6-sol / medium` (rank 4). New cases: a
  `codex-v2` plan and a plan with no `Routing policy:` line each give exactly one
  policy ERROR and no pair or rank findings.
- `tests/plan-revise.test.sh`: a `Host: codex` plan gets exit 2 and the refusal
  text in single-plan mode, and the `host=codex  skipped` row in survey mode.
- `tests/next-step.test.sh`: fixtures at lines 144–146 and 470–476 move to v3
  pairs and `codex-v3`.
- `tests/inline-mode.test.sh:204`: expects `` come from the `codex-v3` selector ``.
- `tests/review-route.test.sh:568–569`: manifest version literals become 1.20.0.

## 11. Release and validation

Plugin 1.20.0 on both manifests. Before completion:
`node scripts/validate-repository.mjs`, `node scripts/test-all.mjs`, and
`claude plugin validate` on the marketplace and every Claude plugin, each with a
timeout, confirming afterwards that no process started by the run is left.
`test-all`'s known environmental failure (`ui-discovery`, no `rg` on the child
shell's PATH) is reported, not fixed.

## 12. Out of scope

- The Claude-hosted external lane, the `codex-judge` block and every other
  fenced block in `reference/ladder.md`; Claude's unweighted rubric.
- Any runtime trust flag or held-out state for Luna (§7 gates the release
  instead).
- Converting plans in other repositories; this design supplies the procedure.
- Historical plans and specs, including the fixture inside
  `2026-09-12-dr-superpowers-small-model-planning.md`.

## 13. Risks

- **Luna quality at ranks 0–2 is unmeasured.** The smoke proves reachability,
  not quality. Escalation still promotes a failing task to Sol, and the review
  cap bounds rounds, so the cost of a weak rank is extra attempts, not a wrong
  merge.
- **GPT-5.6 retirement.** When GPT-5.6 leaves the catalog, human pins naming it
  become unavailable; the selector already answers an unavailable pin with
  `approval`, so nothing silently substitutes.
- **Hard cut mid-execution.** A v2 task mid-escalation at update time stops for
  a handoff decision. Only plans outside this repository can hit this.
- **Astra usage.** Every risk-3 task with any reducible axis, and every judge,
  runs on Astra, as in v2. Rank 7 moves the score-7 tasks from Sol high to Astra
  medium, raising Astra's share of implementer work.
