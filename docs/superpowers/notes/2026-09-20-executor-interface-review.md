# Executor interface spec — review rounds 1 and 2

Spec reviewed: `docs/superpowers/specs/2026-09-20-dr-superpowers-executor-interface-design.md` @ `14f6bac`.
Run: 2026-09-20. Two seats, same prompt.

| Seat | executability | coherence | coverage | assumptions | Findings |
|---|---|---|---|---|---|
| `gpt-6-astra/high` | 6 | 5 | 8 | 6 | 27 |
| `dr-superpowers:judge-fable` | 7 | 8 | 9 | 8 | 25 |

Max delta 3. This is the second artifact on which astra and a Claude judge
landed within 3 of each other, against 5 to 9 between astra and the recorded
baselines in the same day's calibration. Two pairings is not a re-baseline, but
it is the only evidence that compares the seats on the same input.

## The root cause of round 1

One error produced most of the Criticals: the spec described the dispatch
machinery from `reference/external-executor.md` rather than from
`scripts/lib/plan.sh` and `scripts/task-brief`. Everything §9 said about where
delegation is decided was wrong, and the consequences reached `plan-lint`'s
model and effort rules, `executing-plans`' ruling table, and two files that
appeared in no change list.

`§13 What does not change` is what made this visible. Three of its entries were
false, and both seats found them by checking the list against the files — which
is what the section was added for. It is kept and corrected.

## Findings and disposition

Attribution: **A** astra, **F** fable, **A+F** both. Every Critical was verified
against the code before being accepted.

| # | Finding | Verified | Disposition |
|---|---|---|---|
| 1 | The delegated set is computed by `plan_delegated` (`lib/plan.sh:157-169`) and rendered by `task-brief:56-75` at execution time, not by `writing-plans`. No `**Dispatch:**` line exists in a plan file | Confirmed | §9.1 rewritten; both files added to §11 |
| 2 | `plan-lint:326-350` derives an inline plan's model and effort from `plan_delegated`, so executor rows change its verdicts | Confirmed | §9.2 added, naming both effects |
| 3 | §6's "ticked executor" predicate is not today's rule; `p1.md` has no header tick and still expects the warning | Confirmed at `tests/plan-lint.test.sh:416-420` | §6.2 rewritten around the real predicate |
| 4 | The registry cannot express the roster's auth probe | Confirmed | §4 gains `probe`; §4.1 writes down the contract and states why the gate is not a substitute |
| 5 | No override mechanism was specified for the fixture registry | Confirmed | `DR_EXECUTORS_DIR` in §4 |
| 6 | `tests/codex-gate.test.sh:236` sources `codex-session.sh` — a fifth caller, while §12 demanded the suite pass unchanged | Confirmed | §5 lists it; §12 carves out harness lines from the bar |
| 7 | §13's "every judge prompt unchanged" is false: `ruling-prompt.md:96` defines `codex-empty-diff` | Confirmed | §11 lists it; §13 narrowed |
| 8 | §13 vs §10: removing the survivor note changes executable statements, not just a comment | Confirmed | §13 carve-out; §10 names the lines |
| 9 | Removing the note leaves the genuinely dangerous state undocumented — the outer `timeout` firing when the client wedges, whose only observable is `reaped` | Confirmed | §10 documents it |
| 10 | Renaming `external-executor.md` breaks links in `final-review.md` and `escalation.md`, listed nowhere | Confirmed | §10 enumerates all eight referrers |
| 11 | `executing-plans:346-347` excludes `codex-empty-diff` because it "never runs an external executor"; §9 makes it reachable | Confirmed | §9.3 |
| 12 | The ledger claim that `resume-execution` and `repo-audit` parse the executor clause is false | Confirmed | §11 drops the claim; D6 keeps the field name `thread` |
| 13 | `plan-lint:300` skips the warning for inline plans, justified by the premise §9 removes, and the skip is pinned | Confirmed | §6.3: skip stays, comment rewritten, deferral recorded |
| 14 | §6's "any further keys that block defines" invites a generic evaluator nobody specified | — | Withdrawn; §6.1 reads exactly `min_score` and `max_risk` |
| 15 | §6 omitted the Override-on-Executor ERROR | Confirmed | §6.1 rule 2 |
| 16 | `mark_off` writes more fields than the draft specified, and the gate reads them back | Confirmed at `codex-gate:39-50` | §5 gives the full record; the unused argument dropped |
| 17 | The locator's output grammar is an interface and was unstated | Confirmed | §4.1 |
| 18 | The roster's id set is hardcoded and `batch_capable` is hand-maintained | Confirmed | §8 states enumeration and the `batch_capable` rule |
| 19 | `session_dir` had no base path; array output form undefined | — | §4 and §4.2 |
| 20 | Five registry fields are read by nothing in this sub-project | Confirmed | §4.3 lists them and forbids adding readers |
| 21 | `handoff/SKILL.md` records no executor state, so there was nothing to generalise | Confirmed | Row withdrawn from §11 |
| 22 | The `(total 4)` / `(executor)` overlap was undefined | — | §9.1 gives `executor` precedence and shows `heavy` cannot collide |
| 23 | `tests/plan-lib.test.sh` and `tests/run-codex-task.test.sh` were absent from §12 | Confirmed | Added |

## Rejected or deliberately deferred

- **Turning the lane-eligible warning on for inline plans.** Correct in
  principle under §9, but it changes a pinned fixture for an advisory warning.
  Deferred with a register row (§6.3, §15).
- **Renaming the ledger's `thread` to `session`.** Fable argued the rename is a
  self-inflicted compatibility cost and that `task-state.sh` and the wrapper
  both already say `thread`. Accepted; D6 keeps `thread`.

## Verified as claimed by fable

Worth recording, because these are the claims a later reader would otherwise
re-check: §2's grep result; §10's two defects; §9's roster-guard fallback;
§7's self-review rule keying on the Executor line rather than on `codex`; and
that the eligible band is exactly totals 2 to 4 at risk 0 or 1.

---

# Round 2

Spec reviewed: the revision at `372088a`.

| Seat | executability | coherence | coverage | assumptions | Criticals |
|---|---|---|---|---|---|
| `dr-superpowers:judge-fable` | 15 | 15 | 13 | 16 | 0 |
| `gpt-6-astra/high` | 10 | 9 | 12 | 11 | 5 |

**The seats diverged this round** — 5 to 6 apart, against 3 or less on the two
previous artifacts. The earlier note that astra and a Claude judge agree
closely on the same input rests on two data points, not three, and this round
is evidence against generalising it.

Both confirmed the root-cause test passed: every file-and-line citation in the
revision says what the spec claims. Fable found all 23 round-1 dispositions
resolved. The remaining findings were largely *disjoint* between the seats,
which is the strongest argument in this programme for running both.

## Round 2 findings and disposition

| Finding | Seat | Verified | Disposition |
|---|---|---|---|
| `review-route:205` echoes `ruling=%s`, so canonicalising `codex-empty-diff` changes an observable; the `risk3` precedent is from a script that does not echo | A | Confirmed | §7: both spellings share routing, each prints what it was invoked with. D3 reworded |
| `heavy` and `executor` **can** collide: `plan-lint:200-209` validates parts independently while `plan_scores:137-138` takes the highest across parts | A+F | Confirmed | §9.1: `heavy` wins, because `(heavy)` is what `executing-plans:169-171` keys the preflight on |
| Removing an offloaded total-4 task from the threshold numerator can newly delegate *other* total-4 tasks | A | Confirmed | §9.1: the threshold counts the original four-band population |
| Consecutive offloads fail preflight without `--release` (`executor-recovery.test.sh:111-117`) | A | Confirmed | §9.3: release after review, reconcile after HANDBACK; §12 covers two consecutive offloads |
| `reaped` is not a termination certificate: a pre-existing broker is deliberately not reaped, and a timed-out run reaches none of the BLOCKED path | A | Confirmed at `codex-client.mjs:183-192` | §10 rewritten: evidence, not proof; reconcile when inconclusive |
| §4.3's ban on new readers contradicts the neutral prose, which needs a *controller* to resolve gate, wrapper and successor | A | Confirmed | §4.3: script readers constrained, controller readers required through `scripts/executors` |
| `ladder_block` hardcodes the shipped `ladder.md`, so "registry entry plus wrapper" is overstated | A | Confirmed at `plan.sh:70-72` | §1 states the deliverable as registry entry + wrapper + ladder block; per-executor policy source is out of scope |
| `DR_EXECUTORS_DIR` replaces the directory, so a stub-only fixture dir would hide `codex` from the suites declared byte-identical | F | Confirmed by design | §12: the fixture directory holds a copy of `codex.json` |
| Registering `opencode` in B would produce two roster rows with one id | A | Confirmed | §8: a registered id suppresses its PATH row; §12 tests it with an `opencode` fixture |
| The prose *defining* the delegated set (`executing-plans:50-59`, `delegated-task.md:5-9`, README) is in no change list, and `inline-mode.test.sh:101,105-106` pin it | F | Confirmed | §9.3 and §11 |
| `external-task-recovery.md` is Codex-only and in neither list | A | Confirmed | §11: generalised, commands resolve through the selected executor's `wrapper` |
| Registry failure behaviour undefined for the tests §12 requires | A | — | §4.2: validity rules, skip-with-stderr, `list` still exits 0 |
| Overlapping eligibility between two admitting executors is undecided | A | — | §11: one Executor line per task, planner chooses; automatic precedence deferred to B |
| No *existing* plan-lint fixture moves under §9.2 — the Executor fixtures sit on a subagent base plan | F | Confirmed | §12 asks for new inline+Executor fixtures instead of a hunt |
| `plan_delegated` is one awk pass; reading task text inside it adds a per-task loop | F | — | §9.1: sibling helper `plan_executors`, shared with §6.1 |
| Four ERRORs in the Executor branch, not three | F | Confirmed | §6.1 |
| `executors path` takes a dotted key like `get` | F | — | §4.2 |
| `delegated-task.md:111` also links the renamed file | F | Confirmed | §10 |
| `run-codex-task.test.sh` asserts nothing on the survivor path, so its carve-out is moot | F | Confirmed | §12: carve-out withdrawn, the suite must pass untouched |

## Split out of this sub-project

Astra found three code/document mismatches in `external-executor.md` that are
**pre-existing defects, not consequences of this design**:

1. Lines 227-232 call the status line's `exit=` field Codex's own exit code;
   `run-codex-task.sh:270-274` synthesizes 0, 1 or 124 from `ok` and `timedOut`.
2. Lines 319 and 495 say exit 2 means nothing launched; the wrapper can exit 2
   after execution on thread-persistence, reap-persistence, scope-validation or
   report-copy failure.
3. Lines 200-206 tell a controller to stage manually when `commit_subject` is
   empty; `dr_task_stage` blocks that and `run-codex-task.sh:317` exits 2.

They are fixed as a **prerequisite** to this sub-project rather than inside it,
so the neutral rewrite inherits a correct document and this sub-project's
regression bar stays about the abstraction.
