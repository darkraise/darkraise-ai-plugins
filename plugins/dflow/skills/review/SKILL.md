---
name: review
description: Use when every task of a dflow plan is done and before it ships, or to review one risky task - sizes the review to the diff, gets an independent review whose findings carry reproducible evidence, and fixes only what reproduces.
argument-hint: "[--task <N>]"
---

# Review

## 1. Build the pack

```
dflow review pack
```

It prints the tier, the mechanical facts and the pack's path. Act on the facts first:

- `OVER the test budget`: trim tests that repeat each other or pin wording, or record why the volume is right (`dflow log - N "<reason>"`).
- `WITHOUT a logged reason`, a weakened test, files outside the plan: fix it, or log the reason.

## 2. Run the tier it names

- **Tier 0.** Read the diff yourself against every acceptance line and design decision. Record anything wrong with `dflow review add`.
- **Tier 1.** Dispatch one `dflow:reviewer` (model opus; effort medium, or high when the plan has a risk). Its whole prompt: `Review pack: <path>`.
- **Tier 2.** Run the workflow script `${CLAUDE_PLUGIN_ROOT}/workflows/deep-review.js` with the Workflow tool, `args: { "pack": "<path>" }`. Invoking this skill is the owner's request for it. Without the Workflow tool, dispatch two reviewers in one message (one told to look at correctness and plan conformance, one at the plan's risk), then a third to refute their findings with `dflow review judge`.

The reviewer writes findings to disk. Do not ask it to repeat them in its reply. If the workflow returns `complete: false`, a lens or the verifier did not run: run it again before recording the review.

## 3. Prove and fix

```
dflow review verify
```

- `reproduced`: the defect is shown. Fix it here, in this session, and commit with a normal `fix(<scope>): …` commit.
- `unproven`: the evidence did not show a defect. Do not fix blind; report it.
- A finding you disagree with: `dflow review resolve <id> declined "<technical reason>"`. The owner sees every declined finding at ship.

Run `dflow review verify` again after the fixes. A command finding closes itself once its command passes. A quote finding is closed by hand once you have checked the line: `dflow review resolve <id> fixed`.

A fix to a `blocking` finding gets one re-check: send the same reviewer the fix commit's range and ask only whether that finding is closed.

## 4. Record and report

```
dflow review record --tier <N>
```

Tell the owner every finding at every severity (`dflow review list --all`), graded by what it breaks, with what you fixed, declined or left unproven. Then continue with the dflow:ship skill.
