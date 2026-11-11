# Retained review data and the per-plan test ratio

**Register:** docs/dforge/registers/2026-11-10-tdd-and-lifecycle-review.md, rows 2 and 3; its other rows stay `planned` or `deferred` under their own labels.
**Execution strategy:** sequential — inline execution
**Depth:** standard — interface

## Decisions

- Process: the owner chose "Full dforge flow (Recommended)" over fast mode.
- Rulings: the owner said "let fable review to make the decision". Fable's amendments to rows 2 and 3 are recorded in the register and bind this spec: the line forms, the skipped path classes, `<docs>/reviews/<plan-slug>.md`, and no numeric threshold.
- Reading the ledger at finishing: Step 5b names the worktree with `--from`, and the script finds the ledger itself when `--from` is absent. Rejected, writing the retained file on the branch at `Final review: clean`, because the finish choice is not known then and option 3 or a discard must leave none.
- Where the summary lives: one file per plan. Rejected, extending `completed.md`, which several scripts parse and which is one line per plan; a per-plan file also needs no `merge=union`.
- Where the instructions live: in reference files. `skills/executing-plans/SKILL.md` is 19,999 bytes and `skills/finishing-a-development-branch/SKILL.md` 19,952, against a 20,000-byte limit that `skill-size.test.sh` enforces.
- Milestone listing under a darkmem document store, which has no commit range: the owner chose "Select by Retained date (Recommended)". The audit lists retained files whose `Retained:` date falls after the previous milestone close.

Early CI: none

Finish: pr

Worktree: in-place

## Problem

Finishing deletes a plan's ledger with its workspace (`skills/finishing-a-development-branch/references/cleanup.md`), so nothing records what review depth a plan got, what acceptance QA found, or which lenses earned their cost. No per-plan measure of test growth exists at all. Rows 1, 10 and 14 of the register cannot be decided without that data.

## Design

### New script: `plugins/dforge/scripts/review-record`

`review-record ratio MERGE_BASE HEAD` prints one line and writes nothing:

```
Test ratio: <t> test / <c> code lines (<base7>..<head7>)
```

It reads `git diff --numstat -z -M MERGE_BASE HEAD` and sums lines added. Each path falls in the first class that matches:

1. **Skipped, counted in neither number:** a path with a component named `fixtures`, `snapshots`, `__snapshots__` or `testdata`, or with the `linguist-generated` attribute set.
2. **Test:** a path matching a glob of the `paths` clause in the `Applies:` line of `criteria/lenses/test-quality.md`, read at run time so the lens and the ratio cannot disagree. Globs have bash `case` semantics, `*` crossing `/`, as in `scripts/lens-route`.
3. **Excluded:** a path under the repository's top-level `docs/`, under `<docs>` when it is inside the repository, or a lock file by basename (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `bun.lock`, `bun.lockb`, `Cargo.lock`, `poetry.lock`, `uv.lock`, `Pipfile.lock`, `Gemfile.lock`, `composer.lock`, `go.sum`, `packages.lock.json`, `flake.lock`).
4. **Code:** everything else, so a plugin's skill Markdown counts as code.

A binary file adds nothing. A rename counts only its changed lines, under the new path. Exit codes: 0 printed; 2 usage, an unknown revision, or a lens file with no `paths` clause, printing no line.

`review-record retain PLAN_FILE [--from CHECKOUT]` writes `<docs>/reviews/<plan-basename>.md` in the checkout it runs in and prints that path. It reads the ledger of `--from` when given. Otherwise it reads the current checkout's ledger, then searches every worktree's through `dforge_ledger_files`. A ledger counts only when its identity line names the plan, the check `plan_ledger` makes, so a stale ledger under the same basename is ignored.

```markdown
# Review record: <plan-basename>

Plan: <the plan's document name, from dforge_name>
Retained: <YYYY-MM-DD>

<the selected ledger lines, verbatim, in ledger order>
```

The selected lines begin with `Review depth:`, `Acceptance QA: complete`, `Acceptance QA: skipped`, `final review lens`, `Final review:` or `Test ratio:`. A rerun replaces the file. Exit codes: 0 written; 2 usage; 3 a ledger with none of those lines, nothing written; 4 no ledger found, nothing written, printing the paths searched.

### Ledger lines

All written from a new closing section of `reference/final-review.md`, which runs after the fix wave and its re-review, or directly when there was no fix wave, and before the execution skill appends `Final review: clean`:

- `final review lens <id> — <c> Critical, <i> Important, <m> Minor; fixed <f>, rejected <r>`, once per lens that ran, unless the ledger already holds it. The raised counts come from that lens report's Verdict; `fixed` and `rejected` come from the fix and re-review reports by the finding's `[lens:<id>]` tag, so the dedupe prompt in step 3 must keep that tag on each merged finding. A lens with no findings still gets a line. A finding neither fixed nor rejected, such as a parked one, appears in the raised counts only.
- `final review lenses off`, once, when `lensCap` is 0.
- `Test ratio:`, from `review-record ratio` over the same MERGE_BASE and HEAD, so QA and fix-wave tests count, unless the ledger already holds one. On exit 2 no ratio line is written and the review still ends clean.

The final report above the finishing menu names the `Test ratio:` line. `reference/native-codex.md` picks lenses by hand, so it names the same section and ledgers its hand-picked skips as `final review lens-skipped <id> reason=<reason>`.

Neither execution skill's `SKILL.md` changes. `skills/subagent-driven-development/references/ledger.md` lists the new line forms. No reader misreads them: every reader of the clean line anchors `^Final review: clean`, and no script reads a ledger's `lens` lines.

### Finishing and closing

- `skills/finishing-a-development-branch/references/execute-choice.md`, not `SKILL.md`: a new section read before Step 5b's commit. When the plan has a ledger, run `review-record retain PLAN_FILE`, adding the literal worktree path as `--from` on Option 1 when the work is in a linked worktree, and put the file in the same commit as the index line, or push it with the mirror as `completed.md` is. Same outcome binding: options 1 and 2, never option 3 or a discard. Exit 3 is reported in one line and finishing carries on. Exit 4 stops before Step 6 deletes the workspace: find the ledger, or tell your human partner that the record will be lost, and carry on only after that.
- `skills/closing-a-milestone/SKILL.md`, step 8: when the audit recommends the cleanup, it also lists the `Test ratio:` lines of the `<docs>/reviews/*.md` files that the milestone's commit range added, or, with documents in the darkmem mirror, whose `Retained:` date falls after the previous close. No threshold and no effect on the recommendation.

### Records

- `reference/project-state.md`: add `reviews/` to the layout, the file list and the who-writes table, and state that `distilling-docs` never touches it.
- `scripts/test-shards.mjs` at the repository root: add the new test file's Windows weight, which `checkShellWeights` requires.

Nothing branches on the ratio or on a retained file: no gate, route or finish decision reads them. `reviews/` is not a reserved directory in `scripts/lib/darkmem-mirror.mjs`, so the document mirror syncs it unchanged.

## Testing

`plugins/dforge/tests/review-record.test.sh` runs the script against throwaway git repositories, one test per behaviour, table-style where the cases are variants. It includes a worktree fixture for `--from` and the fallback search. No test checks skill wording: the skill edits are carried by the `demo` statements, in line with register row 12. Finishing this plan probably runs the installed 4.15.2 skills (inference), so A10 and A11 are not observable at its own finish, and Step 5b sets rows 2 and 3 to `verify`.

## Acceptance

A1. [test, high] `review-record ratio` prints `Test ratio: <t> test / <c> code lines (<base7>..<head7>)`, with `<t>` the lines added in paths matching the test-quality lens's `paths` globs and `<c>` the lines added in other counted paths, and exits 0 with zero code lines.
A2. [test, neg, high] Lines added under `fixtures/`, `snapshots/`, `__snapshots__/` or `testdata/`, or in a `linguist-generated` path, appear in neither number.
A3. [test, neg, high] Lines added under `docs/` or in a named lock file do not count as code, while a Markdown file outside `docs/` does.
A4. [test, high] A rename counts only its changed lines, and a binary file adds nothing.
A5. [test, high] `review-record retain` writes `<docs>/reviews/<plan-basename>.md` holding the plan's document name and every selected ledger line verbatim, in ledger order, including `final review lens-skipped` and `final review lens` lines.
A6. [test, neg, high] `Acceptance QA: dispatched`, task lines and `Ruling:` lines are not retained.
A7. [test, high] Run in a primary checkout, `retain` reads a linked worktree's ledger both with `--from <worktree>` and with no `--from`, and writes the file into the primary checkout's `<docs>`.
A8. [test, neg, high] A ledger with no selected lines makes `retain` exit 3, and no ledger found makes it exit 4 naming the paths searched; neither writes a file.
A9. [test, high] A second `retain` replaces the file and leaves exactly one file for the plan.
A10. [demo, high] A plan finished by option 1 or 2 leaves a retained file showing its depth, QA counts, per-lens findings, final review line and test ratio.
A11. [demo, neg, high] A plan finished by option 3 or discarded leaves no retained file.
A12. [demo, neg, high] No gate, route or finish decision changes with the ratio's value.
A13. [test, neg, high] A ledger whose identity line names a different plan under the same basename is ignored.
A14. [test, neg, high] A lens file with no `paths` clause makes `ratio` exit 2 and print no line.

## Riskiest assumption

That the worktree's ledger still exists when Step 5b runs on Option 1. Evidence: `skills/finishing-a-development-branch/references/execute-choice.md` records the plan (Step 5b) after the merge and before cleanup (Step 6), and `references/cleanup.md` removes the worktree only in Step 6; read 2026-11-10. Reading it from the main checkout is new and is verified by A7 in the plan's first task.

## Review rulings

- Covering register: plan-lint forces nothing for the other rows, but next-step routes unassigned rows to a ruling session, so each carries an `--assigned` label and rows 2 and 3 are assigned this spec.
- `--from` reaches every path to Step 5b, including a cleared finish session; pass the literal path.
- Both ledger and document roots are implementable under the darkmem stores.
- Ledger identity follows `plan_ledger`; the `Plan:` line is the document name.
- No script misreads the new lines; A5's fixture includes a `lens-skipped` line.
- Lens counts: raised from each lens report's Verdict, fixed and rejected by `[lens:<id>]` tag, written after the ruling seat and before `Test ratio:`.
- Globs have bash `case` semantics.
- File list adds `reference/native-codex.md`; the repository-root `scripts/test-shards.mjs` entry is required.
- Demo acceptance is right under row 12; A10 and A11 are not observable at this plan's own finish, so rows 2 and 3 close as `verify`.
- A1 adds exit 0 with zero code lines.

## Critic findings

- [High, fixed] A forgotten `--from` lost the data silently: `retain` now searches every worktree, and no ledger has its own exit code that stops before cleanup.
- [Medium, fixed] Per-lens fixed and rejected counts had no source: each is now read from a named report.
- [Medium, fixed] `SKILL.md` edits could cross the 20,000-byte limit: the instructions moved to reference files.
- [Medium, fixed] `ratio` had no failure outcome: exit 2, and the review still ends clean.
- [Nit, fixed] `lenses off` wrote no line: it now writes one.
