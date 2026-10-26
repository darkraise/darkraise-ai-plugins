# The walkthrough

The Prove phase. Run it in the session or in an implementer seat: judge seats
have no browser or device tools. Every step writes evidence the proof report
cites. A step you cannot run becomes an `unverifiable` row with its reason,
never a silent skip.

## Before you start

- Read the contract (the spec's `## UI/UX contract`, or at touch depth the
  `## Delta` you are about to write) and the profile
  (`<docs>/ui-ux/profile.md`).
- Open the guide for the profile's `**Platform:**` under `platforms/`:
  [web](platforms/web.md), [windows](platforms/windows.md),
  [linux-desktop](platforms/linux-desktop.md),
  [android](platforms/android.md), [terminal](platforms/terminal.md).
  macOS and iOS have no guide: their items are `unverifiable`.
- Pick the slug: the spec's file name without its date and `-design.md`, or at
  touch depth the bug in a few words. Evidence goes to
  `<checkout>/.dforge/ui-ux/<slug>/`. Create it; `.dforge/` is ignored by git
  through its own `.gitignore` holding `*` (write that file when it is
  missing).

## Steps

1. **Launch** the UI through the guide's launch step. Start every server,
   emulator or session as a tracked background task, note its PID, and give
   every command a timeout.
2. **Seed the worst-case data** through the boundary the real data uses
   (`state-catalogue.md` §Worst-case data).
3. **Walk every flow** in scope, first by pointer, then by keyboard alone, at
   every viewport and theme the profile and the Output promise name.
4. **Force every state** in the matrix: the guide says how (on the web, route
   the network to slow, failing, empty and huge responses).
5. **Run the automated checks** the guide lists: accessibility scan, console
   or log errors, overflow, contrast. Record each result for the report's
   `## Automated checks`.
6. **Screenshot each item and state**, named
   `<id>-<viewport>-<theme>[-<state>].png`, beside the state board it answers.
   Pass the tool the absolute path
   `<checkout>/.dforge/ui-ux/<slug>/<name>.png`. When the tool refuses that
   path, save with the bare file name and move the file from where the tool
   reports it into `.dforge/ui-ux/<slug>/`.
7. **Write the report** (format below) at
   `<docs>/ui-ux/proofs/<YYYY-MM-DD>-<slug>.md`.
8. **Stamp it:** `bash <plugin-root>/scripts/ui-proof stamp <report>`.
9. **Have it judged** (below), save the reply, and add the Judge line.
10. **Check:** `bash <plugin-root>/scripts/ui-proof check --base <ref>`, adding
    `--spec <spec>` when the work has a contract. `<ref>` is the commit the
    work started from. Fix the UI or the proof until it exits 0.
11. **Clean up:** close the browser or app, stop every process you started
    (`pkill -P <pid>` then `kill <pid>`, repeated for grandchildren), and
    remove the `.playwright-mcp/` files you created. Confirm with `ps` that
    nothing you started is left.
12. **Commit** the report and its `.judge.md`, and on a first run
    `<docs>/ui-ux/profile.md`: they are not UI files, so committing them
    leaves the stamp current, and the report is the record that survives the
    worktree.

Any UI edit after step 8 makes the stamp stale: stamp again, and since the
stamp drops a judge line for another fingerprint, judge again.

## The report

````markdown
# UI proof: Settings screen

**Contract:** docs/dforge/specs/2026-10-24-settings-design.md
**Platform:** web
**Viewports:** 375x812, 768x1024, 1440x900
**Themes:** light, dark
**Evidence:** local
**Fingerprint:** 3f9a0c1e5b7d2a46
**Judge:** ship 3f9a0c1e5b7d2a46 — docs/dforge/ui-ux/proofs/2026-10-24-settings.judge.md

## Results

| ID | Verdict | Evidence | Note |
|---|---|---|---|
| UI-1 | pass | .dforge/ui-ux/settings/ui-1-1440x900-light.png, .dforge/ui-ux/settings/ui-1-375x812-dark.png | |
| UX-2 | deviation | .dforge/ui-ux/settings/ux-2-1440x900-light-error.png | cites: user answer 2026-10-24, no Retry on the error card |
| UX-3 | pass | A14: saving shows the pending state | |
| OP-2 | unverifiable | - | no tablet emulator on this host |

**Accepted by:** "fine without the tablet run for now"

## Automated checks

- axe: 0 serious, 0 critical
- console errors: 0
- horizontal overflow at 375: none
````

- `**Contract:**` is the spec's path, or `touch` with a `## Delta` section
  above `## Results` (`contract-template.md` §The touch delta).
- One row per contract ID (per Delta ID at touch depth), `OP-` IDs included.
- `pass` and `deviation` rows cite at least one screenshot or test name.
- A `deviation` note starts `cites:` and names the user's answer, the profile
  decision or the accessibility need that forced it. An uncited difference is
  a `fail`.
- `unverifiable` passes the gate only with an `**Accepted by:**` line quoting
  the user; with several unverifiable rows, one line per ID, as
  `**Accepted by:** OP-2: "<their words>"`. Never write that line unless the user said, in this
  conversation, that they accept the item unproven.
- `**Evidence:** local` while screenshots live under `.dforge/`; they go when
  the worktree is removed, and the verdict rows are what remains. With the
  profile's `**Screenshots:** commit`, put them beside the report and write
  `committed`.

## The judge

Dispatch `dforge:judge-opus` at feature and product depth and
`dforge:judge-sonnet-high` at touch depth (on a Codex host, the native judge
`reference/native-codex.md` names for that rank):

```
Subagent (judge seat):
  description: "Judge the UI proof"
  prompt: |
    You judge whether a built UI keeps its UI/UX contract. Assume every item
    is unproven until a screenshot you opened or a test you read shows it.

    **Criteria:** [PLUGIN_ROOT]/criteria/ui-ux-proof.md
    **Contract:** [SPEC_PATH and its "## UI/UX contract", or the report's "## Delta"]
    **Report:** [REPORT_PATH]
    **Evidence:** every file the report cites, under [EVIDENCE_DIR], and the state boards the contract names
    **Fingerprint:** [FINGERPRINT]
    **Report file:** [REPORT_FILE]

    Read the criteria, the contract and the report. Open every cited
    screenshot and board.
    Write your full report to [REPORT_FILE] and write nothing else: it is
    the only file you may create or change. Then reply in at most 10 lines:
    the verdict, the scores, the count of disputed items, and the report
    path. The report opens with a Verdict section, written without the indent:

        ## Verdict
        verdict: ship | fix [FINGERPRINT]
        scores: <criterion> <1-20> / …

    then answers as the criteria's Output section says, and ends with
    exactly one line: "Verdict: ship [FINGERPRINT]" or "Verdict: fix [FINGERPRINT]".
```

Its `[REPORT_FILE]` is `<report name>.judge.md` beside the report. When it
returns, set the report header's `**Judge:** <ship|fix> <fingerprint> — <that file's repository path>`
line, replacing any earlier one. On `fix`, correct what the judge disputes, then rerun
from step 8. A judge file that does not end with the verdict line is
re-dispatched once with that instruction repeated.
