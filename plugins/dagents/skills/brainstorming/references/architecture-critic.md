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
[architecture-critic-prompt.md](architecture-critic-prompt.md): the
spec path, the approved design sections verbatim (under `autoRun=on`, the
spec's `## Decisions` section) and the repository root. Set `[REPORT_FILE]` to
`<state>/critic-<spec name>-report.md`; read its `## Verdict` section and its
Blocker and High findings. It
runs in an auto run too, before the Fable review. A revision of the spec does
not earn a second critic round.

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
([auto-run.md](../../../reference/auto-run.md) §The spec). Two seats find more
than one on a risky or new design, so a spec at depth `full`, which a risk or
new-subsystem trigger gives it, keeps the separate critic round.

- Fix each Blocker and High finding in the spec, or keep the design with the
  finding answered in a `## Critic findings` section at the end of the spec:
  one bullet per finding, with the reason the design stands.
- List every Medium and Nit finding in that section too; they need no answer.
- Commit the spec, then state the counts in the review request below:
  `Critic: <b> Blocker, <h> High (<f> fixed, <a> answered), <m> Medium`,
  followed by ` (in Fable's review)` when the critic was folded into it.
  At depth light the review request says `Critic: skipped (depth light)`
  instead, since no critic ran.

**The spec review's report.** Every Fable spec review round names a report
file, `<state>/spec-review-<spec name>-<r>-report.md`, and tells the seat to
write its full report there, write nothing else, and reply in at most 10 lines.
The report opens with a
`## Verdict` section of `rulings: <k>`, `undecided: <k>` and
`open: <b> Blocker, <h> High` (the Blocker and High findings still unanswered
after this round, its own and a folded critic's), then `## Rulings` (one
`- <item> — <ruling>` line each), `## Undecided` (one
`- <item> — <options, recommended first>` line each) and, when the critic is
folded in, `## Critic findings` in the critic's grammar. Read the Verdict
section, then the Rulings and Undecided lines; the `open:` line decides whether
a second round runs at depth `full`; at `standard` none runs.
