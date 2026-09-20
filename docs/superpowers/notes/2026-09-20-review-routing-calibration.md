# Review routing — calibration run, 2026-09-20

Spec: `docs/superpowers/specs/2026-09-15-dr-superpowers-review-routing-design.md` §11, §15.6.
Procedure: Task 10 of `docs/superpowers/plans/2026-09-15-dr-superpowers-review-routing.md`.
Run: 2026-09-20, Codex codex-cli 0.154.0; advanced runtime available.
Gate at Step 0: `codex-gate usable=true reason=ok review=false lane=false resets_at=- source=probe`.

This is the first session in which the gate reported Codex usable: the quota
that blocked 2026-09-15 reset at 17:03 +07 today, and `codex@openai-codex` is
now enabled in the `.claude-alt` profile, which is what
`2026-09-16-codex-through-plugin-calibration.md` said a later session had to
wait for. It supersedes the PENDING rows in that file and in
`2026-09-15-review-routing-calibration.md`.

## Two defects found before the calibration could run

Both were found by attempting the gate, and both are fixed.

**The roster's auth probe never worked on Windows** (`1bc0602`).
`scripts/detect-executors.sh` passed Git Bash's `$PWD`, a POSIX path, to
`scripts/lib/codex-client.mjs`. The codex plugin uses that value as a
`spawnSync` working directory; Windows cannot resolve it, the spawn fails with
`ENOENT`, and `binaryAvailable` maps `ENOENT` to
`{available:false, detail:"not found"}` — the shape a missing binary produces.
The roster recorded `auth_status: probe_failed` and turned the lane off naming
the wrong cause, while `scripts/codex-gate`, which reaches Codex through
`app-server.mjs` and spawns nothing, correctly answered `usable=true`. The two
probes disagreed for that reason alone. Measured, everything else held equal:

| `cwd` handed to the probe | Result |
|---|---|
| `/d/Repositories/Personal/darkraise-ai-plugins` | `{"available":false,"detail":"not found"}` |
| `D:/Repositories/Personal/darkraise-ai-plugins` | `{"available":true,"detail":"codex-cli 0.154.0"}` |

Fixed with `scripts/lib/native-path.sh` (`cygpath -m`) at the two sites that
hand a working directory to a node client. The roster now reports
`authed: true, usable: true`.

**The Codex plan seat could not read its inputs** (`de4342f`). The
plan-reviewer template carries `You cannot run commands, modify files, or
dispatch subagents.` A Claude judge reads with a Read tool, so the line costs
it nothing; Codex has no such tool, a command is its only file access, and
`run-codex-review.sh` already confines it with `sandbox: "read-only"`. Sent
unchanged, the seat's own approval layer refused the read and it returned a
well-formed review of nothing — every criterion scored 10, the schema's
"genuinely uncertain" — with a finding saying so:

> Review blocked; this is not a plan defect. Automatic approval review rejected
> the read-only Node file access because your instructions prohibit running
> commands. No command-free local file reader is available, so the four files
> remain unread. Scores of 10 indicate uncertainty, not assessed quality.

It is intermittent, not absolute: of three seats that ran before the fix, two
were blocked this way and one (`small-model`) read its inputs and produced 32
findings. §Round 1 on Codex gained a fourth adaptation replacing that line.

## Calibration

All rows below are from the post-fix run. `project-state` is the only plan
whose recorded scores come from the exact commit being replayed; the other
three replay the committed plan, which already carries its last round's fixes.

| Plan | Version | Status line | Astra e / c / v / a | Recorded | Max delta | Result |
|---|---|---|---|---|---|---|
| project-state | d6c288c | `gpt-6-astra/high status=TIMEOUT exit=124` (twice) | - | 17 / 16 / 17 / 16 | - | NO-RUN |
| judge-seats | 01f5a2a | `gpt-6-astra/high status=OK exit=0` | 13 / 14 / 10 / 12 | 17 / 18 / 16 / 16 | 6 | MISS |
| inline-mode | 69c6b48 | `gpt-6-astra/high status=OK exit=0` | 14 / 13 / 16 / 17 | 17 / 18 / 14 / 16 | 5 | MISS |
| small-model | 5e96f14 | `gpt-6-astra/high status=OK exit=0` | 8 / 13 / 15 / 9 | 17 / 17 / 16 / 17 | 9 | MISS |

Every seat that ran chose the preferred rung: no row is `SUBSTITUTED`.

`project-state` exceeded the `codex-judge` block's 1800-second bound on both
attempts, which is the retry the procedure allows. No third run was made: the
gate had already failed on three `MISS` rows, so another paid run could not
change the outcome. This leaves 1800 seconds unproven as a bound for the
largest plan in the set.

**The scores are reproducible.** `small-model` returned 8 / 13 / 15 / 12 with 32
findings before the prompt fix and 8 / 13 / 15 / 9 with 29 findings after it.
The gap from the recorded scores is therefore systematic, not variance.

**The findings are substantive, not padding.** Astra returned 17, 15 and 29
findings on the three plans it read, naming specific tasks and mechanisms. One
example, `judge-seats`:

> Contracts weakens risk-3 validation from schema compliance to the presence of
> three keys. Task 4 consequently accepts its own invalid fixture, which lacks
> all four scores and uses invalid verdict values. Callers would count an
> unusable result as a vote.

## Known defects (Step 5)

Not performed. Step 5 reads `project-state-review.json`, and that row is
`NO-RUN`, so neither the cross-task helper defect nor the vacuous needles can
be recorded as found or not found.

- Cross-task helper (Task 3 / Task 11): not checked — no review
- Vacuous needles: not checked — no review

## Gate

**FAIL** — three `MISS` rows, one `NO-RUN` row, and both known-defect checks
unperformed. `trust.calibration` in
`plugins/dr-superpowers/reference/codex-plugin.json` stays `pending`, so the
Codex review surface stays off.

The failure is not that the seat is broken. After the two fixes, astra ran the
preferred rung, read its inputs, and returned reproducible, specific reviews.
It simply scores a plan far lower than the Claude judges who set these
baselines did — consistently, and in one direction.

## What the owner must decide

The gate's ±2 tolerance encodes an assumption that a Codex seat and a Claude
seat should agree within noise. This run is evidence against that assumption
rather than against the seat. Three options, none of which a session should
take on its own:

1. **Re-baseline.** Treat astra's scores as the reference for a Codex seat and
   change what the gate compares against. The recorded scores came from Claude
   judges reviewing their own plugin's plans; they are not ground truth.
2. **Widen the tolerance,** if the four criteria are meant to be comparable
   across model families at all. A delta of 9 on one axis argues they are not.
3. **Keep the surface off** and let Claude judges review plans, accepting that
   the Codex plan seat stays unused.

A fourth question is separate from the gate: whether 1800 seconds is the right
bound for `codex-judge`, given the largest plan in the set could not finish
inside it twice.

## Smoke test

Run: 2026-09-21, Codex codex-cli 0.154.0; advanced runtime available, `gpt-5.5 / medium`, disposable linked worktree.

Recorded here rather than in `2026-09-15-review-routing-calibration.md`, which
Task 15 of the review-routing plan names: this file already supersedes that
one's PENDING rows, so the live record belongs in one place.

- Status line: `codex gpt-5.5/medium status=DONE exit=0 commits=7221a67..468f31b thread=01a0c046-cf0a-7883-9a4b-375d4b0f2e90`
- Wrapper exit: 0
- Commit: `468f31b test(superpowers): add codex smoke file`
- File content correct: yes — `codex lane smoke test`, 22 bytes including the newline
- Write set honoured: yes — `1 file changed, 1 insertion(+)`, `smoke.txt` only
- Worktree clean afterwards: yes

Gate: PASS — `trust.smoke` becomes `pass` and the executor lane opens.

### One defect found and fixed before the gate could run

The first attempt died before Codex was contacted:

```
scripts/lib/task-state.sh: line 29: jq: Argument list too long
run-codex-task: cannot snapshot worktree
wrapper-exit=2
```

`dr_snapshot` passed the base64 index and the whole file manifest to `jq` as
command-line arguments. Measured on this repository: the index argument alone
is 45,912 bytes and the manifest about 47,000, against a `CreateProcess` limit
of 32,767 on Windows. Probed directly, `jq` here accepts a 32,000-byte
argument and fails at 40,000.

`run-codex-task.sh:166` calls `dr_snapshot` on every delegated task, so **the
lane could not work on any repository above roughly a hundred files**, and the
smoke gate was unpassable rather than merely unrun. A FAIL recorded before
this fix would have been evidence about our own snapshot code, not about
Codex.

Fixed by passing both values to `jq` as files, with `--rawfile` and
`--slurpfile` — the form already used by `dr_task_assert_snapshot` ten lines
below, so the emitted JSON is unchanged. `tests/task-state.test.sh` gained a
700-file fixture that reproduces the exact error; the suite went from 14 to 17
assertions passing.

Every other case in that suite uses a one-file fixture repository, which is
why a size ceiling survived a full 17-task sub-project unnoticed.

## Calibration re-run — `project-state` at xhigh, 2026-09-21

Owner direction: score divergence between two reviewers is signal to aggregate
and discuss, not grounds to reject one of them; and raise astra's thinking
effort before re-running.

`reference/ladder.md`'s `codex-judge` block moved from `gpt-6-astra high 1800`
to `gpt-6-astra xhigh 3600`. The effort and the bound had to move together:
`project-state` had already exceeded 1800 seconds twice at `high`, and more
thinking takes more wall clock, so raising effort alone would only have bought
another `TIMEOUT`. The fallback row is `gpt-5.6-sol xhigh 2400`, not 3600,
because that pair also appears in `codex-timeout` where it bounds task
execution, and `tests/lanes.test.sh` requires the two blocks to agree on any
shared pair.

Scope: `project-state` alone. It is the only plan carrying this calibration's
planted defects and the only one never reviewed, so it is where the evidence
is.

| Plan | Version | Status line | Astra e / c / v / a | Recorded | Max delta |
|---|---|---|---|---|---|
| project-state | d6c288c | `gpt-6-astra/xhigh status=OK exit=0` | 13 / 14 / 16 / 17 | 17 / 16 / 17 / 16 | 4 |

Per-axis: executability −4, coherence −2, coverage −1, assumptions **+1**.
Findings: 2 Critical, 19 Important.

**The bound was the blocker, and that is now settled.** The run that failed
twice at 1800 seconds completed inside 3600 at a *higher* effort, which is
slower. 1800 was simply too small for the largest plan in the set.

### Known defects (Step 5) — performed for the first time

This check has never run before: it reads `project-state-review.json`, and
that row was `NO-RUN` on 2026-09-20.

- **Vacuous needles — FOUND.** "Several structural tests accept keyword stubs
  instead of checking their stated guarantees … Task 5's 'squash' assertion
  accepts an instruction to squash and omits the three judge/tree conditions.
  … add negative controls." It names the mechanism and an instance, and
  prescribes the right remedy. A second, independent finding on Task 4 reports
  the same class: "The validator accepts a no-gates stub containing the three
  asserted phrases because it never requires `seen_gate`."
- **Cross-task helper — FOUND on substance, not on instance.** "Contracts
  omits … the shared test-helper interfaces consumed by later tasks. Isolated
  implementers cannot verify these claimed contracts." That is the defect's
  mechanism and its consequence, but it does not name `absent`, Task 3, Task 11
  or `tests/gates-manifest.test.sh`. A separate finding reports the same
  consumer-precedes-producer hazard for documents, so the class was actively
  hunted. Graded honestly: substance yes, instance no.

### One Critical verified against shipped code

> Task 2 — The skill instructs running `repo-audit` from the plugin root. The
> script derives the audited repository from its working directory, so an
> installed plugin can audit the plugin checkout or fail outside a repository.

Confirmed. `scripts/repo-audit:15` is `root=$(git rev-parse --show-toplevel)`,
which reads the *working directory*, while `project-status/SKILL.md:17` and
`resume-execution/SKILL.md:16` both say "Run `scripts/repo-audit`" as a bare
relative command. The hazard is mitigated today only by a cross-cutting rule in
a different skill — `using-superpowers` §Session Budget, "call every
`scripts/…` command as `bash <plugin-root>/scripts/<name>`, with the working
directory inside the project's worktree" — which is exactly the remedy astra
prescribes. An implementer reading only that task would not know.

Whether that deserves *Critical* is arguable. That it is a real structural
hazard, in a plan Claude judges scored 17 on executability, is not.

### What this does and does not show

Under the ±2 rule this row is still a `MISS` at a max delta of 4, though it is
the tightest row recorded — the 2026-09-20 rows were 6, 5 and 9.

**That comparison is not controlled and must not be read as one.**
`project-state` was never scored at `high`, so nothing here isolates the effect
of effort from the effect of reviewing a different document. The prediction
going in was that higher effort would push scores *down* by finding more
defects; this row neither confirms nor refutes it.

What the row does establish, on its own terms: the seat finishes the largest
plan, finds the planted defects, and returns specific findings, at least one of
which is verifiable against shipped code.

Gate: **not applied.** `trust.calibration` stays `pending`. Re-baselining means
deciding what the reference is, and that is the owner's decision, not a
session's — the three options above stand, now with this row as evidence.
