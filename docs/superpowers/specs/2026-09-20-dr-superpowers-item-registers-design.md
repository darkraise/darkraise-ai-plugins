# dr-superpowers — Item registers (design)

Date: 2026-09-20. Status: owner-approved design. Scope: items that go missing
across sessions, after which a session claims the work is complete. Evidence:
`docs/superpowers/notes/2026-09-20-missed-items-diagnosis.md` (the darkraise-modder
UX polish programme, tracked here because `.superpowers/` is ignored) plus the
broadened survey in Appendix A. Release: 1.15.0, which also
carries the unreleased Codex budget work.

## 1. What this is for

dr-superpowers has no first-class list of source items. Traceability from "what
was asked" to "what was built" exists only when a session hand-builds a table,
and the plugin neither creates, reads nor checks one.

Where a session built such a table, coverage held: the modder's
`2026-09-18-ux-polish-programme-ledger.md` still correctly shows six rows
unbuilt, and this repository's review-fixes spec carried a triage appendix
naming all nineteen review findings. Where no session built one, items were lost
silently and a completion claim followed.

Six mechanisms were verified against the code on 2026-09-20:

1. The Program line is a frozen singly linked list. `**Program:**` copies
   `next:` from the program's decomposition (`skills/writing-plans/SKILL.md:80-82`),
   so a split decided in a child spec never reaches the k-of-n or the successor
   pointer.
2. Completion is read from that one line. `scripts/next-step:182-184` prints
   "Nothing — every sub-project of `<spec>` is done" whenever the line ends
   `last` or k >= n, consulting no item-level source.
3. `plan-lint` checks the line's shape only — pattern, k <= n, path exists
   (`scripts/plan-lint:69-76`).
4. `project-status` treats `completed.md` as "the only completion signal"
   (`skills/project-status/SKILL.md:37-40`), and a program design as never
   unplanned (lines 44-50). No item source can veto "done".
5. The modder's own `status` skill lists five sources, none of them its ledger
   (`darkraise-modder/.claude/skills/status/SKILL.md:10-18`), while its report
   shape promises "Owner-only items" that nothing supplies.
6. Follow-ups cover only work that got a task: Step 5b harvests deferred, parked
   and discovered lines from the ledger
   (`skills/finishing-a-development-branch/SKILL.md:236-243`).

Four further mechanisms came out of the broadened survey (Appendix A). The
follow-ups note is write-only; design-time deferrals have no home at all;
item-to-task traceability breaks at the plan boundary even when the spec does it
well; and the frozen Program line fails in this repository too, in the opposite
direction, having announced "every sub-project is done" five times while the
programme continued.

## 2. Decisions fixed here

- A first-class item register is the authority on "is everything done?", rather
  than a discipline of reconciling documents by hand.
- It is required for any incoming list of two or more distinct items — an owner
  list, a review's findings, a batch — not only for programme designs.
- It absorbs items discovered later: deferred minors, design-time deferrals,
  findings raised for the owner.
- It blocks. No surface may claim completion while a row is unresolved, and the
  only exit is a ruling recorded in the row.

## 3. The register file

Path: `docs/superpowers/registers/YYYY-MM-DD-<slug>.md`, one per incoming list,
committed to the repository. It is deliberately not under `.superpowers/`: items
outlive worktrees, merges, and the ledger that Step 6 deletes.

````
# <Title> — item register

**Source:** <where the items came from, one phrase>
**Covers:** <comma-separated repository-relative spec paths, or ->

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Settings ignores the design language | C2 Settings | Tabs and Card radius | planned | - |
````

**Identifiers** are positive integers, assigned once, never renumbered or
reused; new items append. **Item** holds the requester's words, not a
paraphrase. **Assigned** names the sub-project, spec or plan that discharges the
row, or `-`; once a plan exists it is that plan's repository-relative path.
**Acceptance** is how anyone would know the row is finished, or `-` until the
item is specced. **Note** is free text.

Cells hold no newlines; a literal pipe is written `\|`. Table rows inside fenced
blocks are ignored, under the same CommonMark fence rule `scripts/lib/plan.sh`
applies, so documentation may show examples.

### 3.1 States

| State | Meaning | Resolved |
|---|---|---|
| `open` | recorded, not yet assigned | no |
| `planned` | assigned to a spec or plan | no |
| `doing` | a plan is executing it | no |
| `verify` | built, the owner's confirmation owed | no |
| `done` | built and verified | yes |
| `deferred` | ruled out of this work, with a reason | yes |
| `n/a` | answered without work, with the answer | yes |

The vocabulary is exact and lowercase. **Note** is mandatory — non-empty and not
`-` — for `deferred`, `n/a` and `verify`: those three states record a decision or
a debt, and a decision without its reason is what a findings file already fails
to preserve.

`verify` does not count as resolved. Rows 8, 12 and 13 of the modder's ledger are
in exactly that state today — implemented, the owner's live check owed — and the
plugin currently has no representation for it, so it evaporates at integration.

## 4. Discovery

Nothing carries a pointer to a register; resolution runs the other way. Given a
plan, a reader takes its `**Spec:**` path and, when present, the spec named in
its `**Program:**` line, then scans `docs/superpowers/registers/` for every
register whose `**Covers:**` names either. Several registers may cover one spec;
their unresolved rows are unioned. A plan therefore cannot carry a stale or
missing register pointer, which is the failure the frozen Program line already
demonstrates.

A register whose `**Covers:**` is `-` — the list arrived, nothing is designed yet
— is invisible to the plan-side readers and fully visible to `project-status`,
which scans the directory directly. A list with no spec is open work, not
nothing.

## 5. Command surface

### 5.1 `scripts/lib/register.sh`

Sourced; defines functions only; fence-aware, mirroring `lib/plan.sh`.

- `register_field FILE LABEL` — the first `**LABEL:**` line's value, or nothing.
- `register_rows FILE` — one
  `id<TAB>item<TAB>assigned<TAB>acceptance<TAB>state<TAB>note` line per row, in
  file order.
- `register_open FILE` — the same, filtered to the four unresolved states.
- `register_covers FILE` — one repository-relative spec path per line; nothing
  when `**Covers:**` is `-`.
- `register_files ROOT` — every `docs/superpowers/registers/*.md` under ROOT.
- `register_for_spec ROOT SPEC...` — the register paths covering any of the given
  specs.

### 5.2 `scripts/register`

```
register check FILE
register open [--root DIR] (--spec SPEC | FILE)
register set FILE ID STATE [--note TEXT] [--assigned TEXT] [--acceptance TEXT]
register add FILE "ITEM" [--assigned TEXT] [--acceptance TEXT] [--state STATE] [--note TEXT]
```

`check` validates header lines, table shape, duplicate or non-positive
identifiers, the state vocabulary, and the mandatory note. It prints one
`ERROR <line>: <message>` per problem. Exit 0 clean, 1 errors, 2 usage or missing
file.

`open` prints the unresolved rows for a register file, or for every register
covering `--spec`. **Exit 0 when nothing is open, 1 when rows are open**, 2 on
usage — so a caller gates on the exit status and reports on the output.

`set` rewrites one row, refusing an unknown identifier, an unknown state, or a
state that requires a note without one. `add` appends with the highest existing
identifier plus one, taking the maximum from the fence-aware parse rather than a
flat grep (the defect `plan-amend:64` carries).

The write verbs are not a convenience. Asking a model to hand-edit one cell of a
markdown table across a dozen sessions is how a row silently loses its state.

## 6. The completion rule

### 6.1 `scripts/next-step`

Before the Program-line branch that today prints completion, resolve the
registers covering the plan's spec and its programme spec, and collect their
unresolved rows.

When any row is unresolved, the answer is never "Nothing":

```
**Status:** Plan `<rel>` is complete.
**Next:** Register `<file>` has <n> open rows: #<id> <item>; #<id> <item> …
```

At most three rows are named, then `+<N> more`. The action that follows is the
assigned value of the first unresolved row when it has one — "Next:
`<assigned>`: write its spec in a fresh session", where `<assigned>` is the
sub-project name or plan path the row carries — and otherwise "Rule on the open
rows with dr-superpowers:brainstorming". Both launch the design tier.

The Program line survives as orientation, not as authority: `last` and k >= n no
longer end the programme on their own. When no register covers the spec,
`next-step` behaves exactly as it does today, so every plan already written in
this repository and in the modder keeps working unchanged.

This is the fix for the original incident. C1's plan said `sub-project 3 of 4 —
next: D. Workspace`; the split into C2 lived only in a spec header; the register
would have held rows 4, 6, 16 and 17 as `planned` against `C2 Settings`.

### 6.2 `skills/finishing-a-development-branch`

The line above the Step 5 menu may read "After integration: the program is
complete" only when every covering register is fully resolved. Otherwise it reads
"After integration: <n> register rows are still open — #<id> <item>".

Step 5b stops being a dead drop. A row the plan covered — one its tasks cite, or
one whose `Assigned` cell is this plan's path — is resolved through
`register set`: `done`, or `verify` when the row's acceptance names a check only
the owner can perform. Deferred minors, parked lines and unresolved discovered
items are written into the register through `register add` — `open` when they are
real work, `deferred` with the ruling in the note when they are not. The prose
follow-ups note is still written when no register covers the plan, so one-off
plans do not regress; where a register exists, it is the single place open work
lives.

### 6.3 `skills/project-status`

`completed.md` stops being the completion signal for a body of work and answers
the narrower question it can answer: did this plan's branch land. The register
answers whether the work is finished.

The report gains an **Open items** section, grouped by register, listing
unresolved rows; `verify` rows appear under a heading for work that needs the
owner rather than a session. The skill may not report a body of work as complete
while any covering register holds an unresolved row.

### 6.4 `scripts/repo-audit`

A new `## Item registers` section prints one line per register — its path, its
open count, its `verify` count and its total — or `- none`. A fresh session then
sees open items beside branch, worktrees and ledgers, without knowing registers
exist.

## 7. What `plan-lint` enforces

A task may carry an optional `**Items:** 4, 16` line citing register rows by
identifier. Three new checks, all ERROR:

1. **Uncovered assignment.** A row whose `Assigned` cell is this plan's
   repository-relative path, still unresolved, cited by no task.
2. **Dangling citation.** A task citing an identifier that no covering register
   holds.
3. **Premature `last`.** The Program line ends `last` while a covering register
   holds an unresolved row that is *not* assigned to this plan. This is the check
   that would have caught the Settings dialog.

Check 1 matches on the plan's repository-relative path only. A row still
assigned by sub-project name — `C2 Settings`, before that sub-project has a plan
— is not lintable against any plan, and is caught instead by check 3 and by
`next-step`. Turning that name into a plan path is `writing-plans`' job (§8).

A WARN covers the plan that has a covering register and no `**Items:**` line
anywhere: legal, since rows may be assigned to a later sub-project, but worth
saying.

## 8. Who writes rows

| Boundary | Write |
|---|---|
| brainstorming | creates the register before the spec, rows at `open`, verbatim |
| writing-plans | `planned` + assigned + `**Items:**` citations; a design-time deferral becomes a `deferred` row with its reason |
| executing-plans, subagent-driven-development | `doing` at the start of a run |
| finishing-a-development-branch | `done` or `verify`; appends discovered rows |

Brainstorming also *reads*: before designing, it opens any register covering the
area, so a row deferred months ago is seen by the next design that touches that
code instead of decomposing in a file nobody reopens.

## 9. Interface changes

- New: `docs/superpowers/registers/`, `scripts/register`,
  `scripts/lib/register.sh`.
- New optional plan header grammar: a task's `**Items:**` line.
- `next-step`'s completion output changes shape when a covering register has open
  rows; unchanged otherwise.
- `repo-audit` gains a section; downstream readers parse by heading.
- `plan-lint` gains three errors and one warning; exit codes unchanged.
- `project-status`'s completion rule and report shape change.
- README and `reference/project-state.md` document the register.

## 10. Approaches considered

**Fold items into the execution ledger** (`.superpowers/sdd/<plan>/progress.md`).
Nothing new to parse and a reader already exists. Rejected: that ledger is
per-plan, lives in the worktree and is deleted by Step 6, while items span
sub-projects and weeks. It puts the list somewhere destroyed, which is the shape
of the bug rather than a fix.

**Make the items a mandatory spec section.** No new file type, and the table sits
beside the design that answers it. Rejected: a programme's items would live in
the programme design while each sub-project writes its own spec, and specs exist
per piece of work — which fails the chosen trigger, where a review of nineteen
findings with no programme also needs a register.

**Conservative completion with no new artifact** — forbid "done" and report what
could not be verified. Rejected by the owner: it relies on a session reading the
right documents every time, which is the behaviour that already fails.

## 11. Testing

- New `tests/register.test.sh`: header parsing, table shape, escaped pipes,
  fenced rows ignored, duplicate and non-positive identifiers, the state
  vocabulary, the mandatory note, identifier stability across `add`, `set`
  refusals, and the exit codes of `open`.
- `tests/next-step.test.sh`: a complete plan whose covering register has open
  rows does not print "Nothing"; names at most three rows; routes to the first
  row's assignment; behaves exactly as before when no register covers the spec.
- `tests/plan-lint.test.sh`: uncovered assignment, dangling citation, premature
  `last`, and the no-citation warning.
- `tests/repo-audit.test.sh` and `tests/project-status.test.sh`: the new sections,
  including a register whose `**Covers:**` is `-`.
- Fixtures under `tests/fixtures/`.

## 12. Verification

- `node scripts/test-all.mjs`, bounded, accepting only the known
  `rg: command not found` failure in `tests/ui-discovery.test.mjs`.
- `node scripts/validate-repository.mjs`.
- `claude plugin validate` on the marketplace and every Claude plugin.
- `scripts/plan-lint` on this design's own plan.
- `scripts/register check` on the first register this work creates.

## 13. Out of scope

- Backfilling registers for historical programmes. Every existing plan has no
  covering register and behaves exactly as today; adoption is one list at a time.
- The darkraise-modder repository. Its ledger converts to a register almost
  mechanically, but that is the owner's to schedule.
- Removing the prose follow-ups note for plans with no covering register.
- Any darkmem integration; registers are repository files.
- Measuring the effect, and the version bump owed for the already-shipped 1.14.0
  manifests beyond naming 1.15.0 here.

## Appendix A. Broadened survey (checked 2026-09-20)

| Mechanism | Evidence | In scope |
|---|---|---|
| Follow-ups are write-only | `followups` appears in the plugin only as a write (`finishing-a-development-branch/SKILL.md:236`); no script or skill reads `docs/superpowers/notes/`. The modder's 2026-08-21 Studio batch recorded 31 deferred minors, three marked "SURFACE TO THE OWNER"; a month later no file in that repository references the document. One of them is the clipped Settings Weight combo — the area sub-project C2 was to cover. | §6.2 |
| Design-time deferrals have no home | This repository's review-fixes spec §12 deferred M3, a split re-lint test and special-path tests. Step 5b harvests only ledger lines, so a deferral decided while writing a spec never becomes a follow-up bullet, and nothing reads "Out of scope". | §8 |
| Traceability breaks at the plan boundary | The review-fixes spec names all nineteen review identifiers and carries a triage appendix; its plan mentions none of them. Neither direction of the coverage question is mechanically answerable once execution starts. | §7 |
| The frozen Program line fails here too | The fork design was amended ten times; successive plans read "5 of 5 — last", "6 of 6 — last", "7 of 7 — last", "8 of 9", "9 of 9 — last", "10 of 10 — last". Each `last` made `next-step` announce the programme finished while it continued; recovery was a manual amendment. | §6.1 |
| `completed.md` is unreliable in both repositories | Here it holds five lines for thirty plans (the index began 2026-09-16), so `project-status` rule 3 would call twenty-five merged plans "not started". In the modder it lacks B1, B2, B3 and C1, whose merge path skipped Step 5b. | §6.3 |
| No representation for owner-verification debt | Modder ledger rows 8, 12 and 13 sit at `verify`; the plugin has no such state, and the modder's `status` skill promises "Owner-only items" with no source. | §3.1 |
