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
