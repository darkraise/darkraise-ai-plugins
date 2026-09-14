---
name: running-gates
description: Use before the final whole-branch review or before merging, when the project declares gates in docs/superpowers/gates.md - runs the applicable gates in order and stops at the first red
---

# Running Gates

**Announce at start:** "I'm using the running-gates skill to run this project's declared gates."

A project declares what proves a change works, in order, in
`docs/superpowers/gates.md`. This skill reads that manifest and runs it. Gates
are **branch level**: they are reached from dr-superpowers:finishing-a-development-branch
and from [final-review.md](../../reference/final-review.md), never from inside a
per-task loop, where a five-gate manifest would cost more than the plan. See
[project-state.md](../../reference/project-state.md).

## The manifest format

`gates.md` is a document a human maintains, read by a model. No shipped script
parses it, so it is a convention with required fields — tight enough that two
sessions read it the same way.

- An H1, optionally followed by prose.
- Each gate is `## <n>. <title>`, `<n>` the run order, contiguous from 1.
- Under the heading, one `Field: value` line per field, in any order.
- Required: **`Command`** and **`Green`** (what output or observation proves it).
- Optional, seven of them: **`Applies`** (default `always`), **`Evidence`**
  (default `output`), **`Repo`**, **`Setup`**, **`Teardown`**,
  **`Known-flaky`** — the specific failure that is known noise — and **`Why`**,
  the reason the gate exists, which is what stops a later session deleting it.
- **Value form:** when a value both begins and ends with a backtick, those two
  delimiters are stripped and the rest is the value. Otherwise the value is the
  remainder of the line verbatim, backticks included.
- **Continuation:** a value may continue on following lines indented two spaces,
  or — when it contains its own newlines — be given as an empty `Field:` line
  followed immediately by a fenced code block. Those two forms are the only ones.
- **`Repo`:** a path relative to the manifest's repository root. The gate's
  `Command`, `Setup` and `Teardown` run with that repository as the working
  directory. Each repository has its own base and its own change set. Omitted
  means the manifest's own repository. This is what lets a manifest order a
  framework's gates before its consumer's.

A complete example, and a blank skeleton, are in
[gates-template.md](references/gates-template.md).

## Evidence

The `Evidence` field is the load-bearing part of the format. It exists because of
a recorded failure: a payload mask carried the wrong bit layout, every value in
the corpus decoded to the same wrong answer, and the suites stayed green
throughout, because nothing had looked at the output.

| Evidence | What proves it | What is not enough |
|---|---|---|
| `output` (default) | The declared `Green` text appears in this run's output | A previous run, a partial match |
| `exit` | Exit code 0 | Output that looks fine |
| `image` | Opening the artifact and writing one sentence describing what it shows | Any metric, including one reporting zero defects |
| `judgment` | A stated verdict against `Green`, with the observation it rests on | "Looks right" |

The default is `output`, not `exit`: a gate that declares `Green` and omits
`Evidence` must be judged against that text, or every `Green` line in a minimal
manifest is decorative. Every gate additionally requires its command to exit 0,
`image` and `judgment` included — a crashed run that left a readable artifact is
red. An `image` gate is never passed off numbers; the numbers say where to look.

## Steps

1. **Locate the manifest** at `<repo root>/docs/superpowers/gates.md`. Absent:
   say so, offer the bootstrap below, and fall back to the project's full test
   suite for this run. A missing manifest is not an error.
2. **Compute the base and the change set.** Determine the base yourself — the
   plan's base when a plan is in force, else `git merge-base <default branch> HEAD`,
   else ask — and state it in the report. Never expect a caller to supply one:
   dr-superpowers:finishing-a-development-branch establishes its base in Step 3,
   after the Step 1 that invokes this skill. The change set is
   `git diff --name-only <base>...HEAD` plus `git status --short`, computed per
   `Repo`, each against its own repository's default branch.
3. **Select the gates.** `Applies: always` runs. A conditional gate runs when its
   own repository's change set touches what it names. Report every skipped
   conditional gate with the reason it did not apply: a silent skip is
   indistinguishable from a forgotten one.
4. **Run in order, stop at the first red.** Later gates usually depend on earlier
   ones — a manifest whose `Repo` fields put a framework before its consumer
   encodes a build dependency — so results after a red are not unknown, they are
   meaningless.
5. **Judge by `Evidence`.** For an `image` gate, open the artifact and write the
   sentence before recording a result.
6. **`Known-flaky` never auto-passes.** Re-run once **only** when the observed
   failure matches the `Known-flaky` text. Any other failure is red on the first
   occurrence. A retry that passes is recorded as passed-on-retry, naming the
   flake.
7. **Report** one row per gate: number, title, result, and the summary line the
   command printed — plus, for `image` gates, the sentence written after looking.
   Name the base from step 2.

A gate whose command cannot launch at all — missing script, bad path — is a
**manifest defect**, not a red gate. Report it as one and say the manifest needs
updating. A manifest that has rotted silently is worse than no manifest, because
it turns a real check into a green line.

## Bootstrap

When no manifest exists and your human partner wants one, propose it from
evidence rather than asking them to dictate it: read the build, test and lint
entry points under `scripts/` or the package manifest, any CI workflow, and the
verification commands `CLAUDE.md` already names. Present the draft — ordered,
with a `Green` for each — and write it only after approval. The first version
does not need every gate; it needs the ones that are run today.

## Red Flags

| Thought | Reality |
|---------|---------|
| "The metrics say zero overlaps, so the picture is fine" | Open the picture. That is what `Evidence: image` means. |
| "It failed, but it's just this machine" | Only a failure matching `Known-flaky` gets a retry. Everything else is red. |
| "The later gates will probably pass" | Stop at the first red. Results after a failed dependency mean nothing. |
| "This gate seems obsolete, I'll skip it" | Read its `Why`. If it is dead, propose deleting it from the manifest. |
| "I'll run the gates for each task" | Gates are branch level. Per-task verification is the task's own tests. |
