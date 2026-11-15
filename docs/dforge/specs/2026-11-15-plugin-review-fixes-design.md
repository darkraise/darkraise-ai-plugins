# dforge plugin review fixes — design

**Date:** 2026-11-15
**Source:** the verified four-seat review of `plugins/dforge` at b4f46903
(`.dforge/reviews/2026-11-15-plugin-review/consolidated.md`, verdicts in
`verify-1..5-report.md`); register
`docs/dforge/registers/2026-11-15-plugin-review-fixes.md`, rows 1-63.
**Execution strategy:** sequential — inline execution
**Depth:** full — risk

## Decisions

- Process: "Full dforge flow (Recommended)" — register, spec, Fable review,
  the owner's spec review, then the plan.
- Scope: every CONFIRMED issue and the confirmed part of every PARTIAL one
  (register rows 1-63). The rejected H5 and the rejected halves of partial
  groups (A1's review-package, A10, H12's setsid claim, H4's "loops
  indefinitely", A11's post-removal case, A7's "dispatches implementers")
  are out of scope.
- QA cleanup: "QA lists its own files (Recommended)" — QA appends every path it
  creates or changes to a manifest in the workspace; on a timeout the session
  reverts or deletes only manifest paths and reports any other new dirty path
  instead of touching it.
- Shared state: "Cockpit writes a session file (Recommended)" — the cockpit
  writes a per-session JSON the scripts read first, falling back to today's
  transcript scan when the file is missing or stale.
- Judge web access: "Remove WebFetch (Recommended)".
- Implementer gate: "Retarget to the QA report (Recommended)" — rewrite the
  persona for QA and walkthrough work, and change the SubagentStop gate to
  check that the named report exists and opens with its required heading.
- Fast-mode question: "Add 'fast for this session' (Recommended)".
- Release: no version bump or release in this work; the next release is a
  separate decision.
- Session-start bound (A21): "20 s per step (Recommended)" — reconcile and pull
  each bounded at 20 seconds, the mirror lock wait cut to 10 seconds.
- Approval: "Approve and run unattended".

Early CI: none

Finish: merge

Worktree: in-place

## Problem

The review found one data-loss path, 28 Important and 34 Minor defects. Their
common cause: a rule changed in the core scripts and not in every reader of
the same state (the cockpit's TypeScript, `ui-turn-end.sh`, `native-codex.md`,
the darkmem path handling), and several scripts infer session facts the
cockpit already knows.

## Design

Grouped by subsystem. Each bullet names its register row(s).

### 1. Data safety

- **QA manifest (row 1).** The session truncates
  `<workspace>/qa-touched.txt` whenever it saves `qa-status-before.txt`, so a
  re-dispatch or a second final-review round starts empty. Acceptance QA
  appends each path it creates, modifies or deletes to that file, one
  repository-relative path per line, before it writes the path;
  acceptance-qa.md's "What you may read" and "Never" sections allow that one
  append. On a QA timeout (both the main
  path at final-review.md:163-168 and the recovery path at :121-125) the
  session restores or deletes only paths that are both listed in the manifest
  and new relative to `qa-status-before.txt`. Every other new dirty path is
  left untouched and named in the final-review message and the ledger ruling.
  A missing manifest means nothing is cleaned. Carried paths stay exempt.
- **Amendments are durable (row 25).** `amendments.md` lives in the ledger
  directory (`dforge_dir ledger <plan>`), so it follows progress into the
  darkmem mirror and is synced and retained with the ledger. `review-record`
  keeps it. Migration: when the ledger-directory file is missing and
  `<workspace>/amendments.md` exists, the first reader moves it there and logs
  one `Ruling: amendments moved beside the ledger — none` line, so a plan
  amended before the upgrade resumes with its amendments. Recovery (`resume-execution`, `task-brief`) refuses with exit 2
  and a named message when the ledger has a `Ruling: amendment A<k>` line and
  `amendments.md` lacks `A<k>`. `ci-mirror` resolves the plan with
  `plan_locate` and reads it through `plan_apply_amendments`.
- **Plan identity (rows 2, 52).** `task-brief --open` and `task-close` check
  the ledger's `# SDD ledger — plan: <path>` line against the plan they were
  given (as `plan_ledger` does) and exit 2 on a mismatch. `task-close` rejects
  a checkpoint containing a newline, and the cockpit reads `review clean` only
  inside the parenthesised clause before ` — `.

### 2. Recovery, routing and finishing

- **Stale final review (row 3).** `next-step` and recovery parse the head of
  `Final review: clean (commits <base>..<head>)`. When HEAD has commits after
  `<head>` that touch anything but `<docs>/` files, the plan routes to a
  scoped re-review of `<head>..HEAD`, not to finishing. When `<head>` is not an
  ancestor of HEAD (a rebase, amend or squash), it routes to a full final
  review and logs a `Ruling:` line naming the rewritten history.
- **PR records after publication (row 6).** Option 2 writes and syncs the
  completion record only after `git push` and the PR creation both succeed.
- **Keep as-is (row 7).** Step 7 runs `next-step --kept` after Option 3: it
  prints a pending-integration block (branch, worktree, plan, the finish
  choices still open), leaves the programme where it is, and does not label
  this plan's rows as assigned to a finished plan.
- **finish-choice (rows 34, 55).** `finish-choice answer` creates the record
  when none exists. Step 7 clears the no-plan record after its outcome.
- **Compaction snapshot (row 5).** `snapshot_latest` includes `latest.md`
  only when it names a plan whose ledger this session wrote, or when it is
  newer than the session's start; the line states its age. Over the size cap,
  the ledger section is truncated to its newest lines instead of dropped.
- **Auto-run hygiene (rows 32, 33, 54).** `auto-run clear` applies the
  plan-name check `ar_switch` already uses. `auto-run stop --stale` stops a
  run whose owning session `ar_is_stale` reports dead; resume-execution and
  the pane name it. `auto-run start --register` sets the register's
  `**Covers:**` to the spec when it is `-`.
- **Missing Node (row 15).** When `dforge_darkmem_possible` is true and Node
  is not on PATH, `dforge_roots` exits 2 with "node is required while darkmem
  stores are applied". Hooks treat that exit as a silent pass, and session
  start injects the warning once (a marker beside the turn stamp); scripts the
  session calls fail with the message.

### 3. Cockpit session file

- **Contract (rows 12, 28, 39, 40).** The cockpit writes
  `~/.claude/dforge/sessions/state/<session-id>.json` at session start, when
  a prompt is submitted (after the turn stamp exists), at every turn end,
  whenever a launch starts or ends, and when the model changes:
  `{session, updated, window, model, launches: [{id, kind, what, service}]}`.
  Scripts read it through one helper in `scripts/lib/session-state.sh`.
  `window` and `model` are valid while `session` matches; `launches` is valid
  only when `updated` is not older than the turn stamp. Otherwise the helper
  falls back to today's transcript scan, and on a rejection it appends one
  line per turn (reader and reason: missing, stale, unparseable, session
  mismatch) to `<state>/session-state.log`; `scripts/in-flight` and the
  budget line name the source they used. Session start prunes state files
  older than 30 days. Fast mode stays out of the file: `fast_mode_on`
  remains its only parser.
- **One service list (row 12).** The service patterns the cockpit uses
  (`SERVICES`, `isServiceCommand`) move to `config/services.json`, read by
  both the cockpit and `lib/in-flight.sh`. In `turn-end.sh` a running service
  no longer passes a plain stop: only finite background work does.
- **Context window (row 28).** `ctx_model_window` takes the session file's
  `window`; without it, a model id the table does not list has no window.
  Every consumer handles that before any arithmetic: `ctx_line` and
  `ctx_auto_line` print the existing `unknown` verdict and exit 3
  (context.sh:386, which session-budget.md's count rule reads as "keep the
  session"), and `ar_verdict`/`ar_limit` treat it as no size-based handoff.
  A guessed 1,000,000 is never used.
- **Hot paths (row 39).** `fast_mode_on` reads the main transcript backwards
  in chunks and stops at the newest `Process:` line, instead of scanning the
  whole file forwards. The newest-ledger scan caches by directory
  modification time.
- **Fast-mode scope (rows 14, 59).** `Process: fast — <why>` covers the one
  request: it ends at the next human prompt unless that turn writes another
  `Process: fast` line. The fast-mode question gains a third answer, fast for
  this session, written `Process: fast (session) — <why>`, which stays in
  force until the session ends or a later `Process:` line names another path.
  So `fast_mode_on` takes the newest `Process:` line in the main transcript:
  `fast (session)` is on wherever it sits; plain `fast` is on only when it
  sits after the current turn stamp.
  The cockpit's budget nudge does not fire while fast mode is on.
- **QA timer (row 37).** A launch whose command is a bare `sleep <n>` is a
  timer: the reconcile prompt and the idle report never tell the session to
  stop it.
- **Session start (row 41).** `darkmem-sync reconcile` and `pull` each run
  under a 20-second bound at session start; on an overrun the hook injects
  one line saying sync did not finish and naming the command to run.

### 4. Stop hooks and budget

- **UI-proof hold (row 29).** `ui-turn-end.sh` reads the last message with
  the transcript fallback `turn-end.sh` uses (moved to a shared helper), and
  stands down when the message carries a `## Next session` block, when a
  ledger written this turn ends on a `Task <N>: waiting — ` line, or when
  finite background work is running.
- **Relaxed mode (row 13).** The cockpit keeps the final-phase exemption in
  relaxed handoff mode (only tail tasks lose it). The `handoffTokens` lock
  text says auto runs still use the value.
- **README (row 38).** The unplanned-commit hold paragraph is replaced by one
  sentence: the branch-head record serves the UI proof hold only.

### 5. Test results and review tooling

- **Baseline comparison (row 8).** An unnamed failure (`command exit CODE`)
  is never matched against the base: it counts as new.
  `tests/task-step-base.test.sh:286-297` pins the old behaviour and is
  changed to the new one.
- **suite-run (rows 9, 10).** It reads HEAD again after the run and records
  no reusable row when it changed; a failed `git status` counts as dirty.
- **Timeouts (rows 11, 35).** A new `scripts/with-timeout <seconds> <cmd…>`
  wraps `dforge_timeout`; final-review.md, finishing's ui-proof.md and
  acceptance-qa.md name it instead of a literal `timeout`. `agy-locate`
  bounds `agy --version` with `dforge_timeout` and reports the CLI unusable
  when no timeout command exists.
- **Process trees (row 58).** Without `setsid`, `run-review-panel` collects
  the runner's whole descendant tree before signalling and verifies after the
  kill that none is left.
- **task-step (rows 56, 57).** Every git call honours `--cwd` through
  `git -C "$top"`; Integration check and Worktree setup use task-brief's
  first-code-span extraction.
- **ui-proof evidence (row 27).** Screenshot paths resolve through
  `dforge_resolve`; while documents live in darkmem, screenshots are written
  under the checkout's `.dforge/ui-proofs/` and cited from there.
- **Judge guard (rows 17, 62).** For a direct prompt the guard allows only
  the path on its `Write your full report to` line (or `Write your complete
  review to`), as it already does for prompt files; the session cwd is a
  fallback root for report paths.
- **Judge seats (row 36).** `WebFetch` is removed from every judge agent's
  tools.
- **QA persona and gate (row 53).** `impl-sonnet-high.md` describes QA and
  walkthrough dispatches only. QA's reply contract (acceptance-qa.md) ends
  with a `Report: <absolute path>` line. `impl-stop-gate` identifies a QA stop
  by that line and blocks it when the file is missing or does not open with
  `## Verdict`; it no longer looks for a `**Status:**` line. A reply without
  a `Report:` line (a walkthrough, any other dispatch) passes unchecked. The
  existing pass-through limits (two blocks per agent, five fires) stay.

### 6. Codex host

- **Task opening (row 4).** `task-brief --open` accepts `Host: codex` plans:
  it writes the open line and the brief, omitting the Claude-only lines.
- **native-codex.md (row 26).** Rewritten for inline execution: one judge
  per risk-3 review, no implementer escalation, reserve tiers or splitting,
  and manual lens routing that applies lens-route's depth gating and
  `lensMinorFrom` floor.
- **Workflow line (row 23).** `dforge-config workflow --host codex` emits
  `designApproval` and `specReview` overrides even when `autoRun=on`; the
  Codex entry point passes the flag.
- **Stale text (rows 30, 31).** executing-plans says a delegated task keeps
  2 rounds (5 on a `Host: codex` plan); final-review.md says "the fix pass"
  and "run the plan's Integration check yourself".

### 7. Cockpit

- **Ledger states (rows 19, 21).** `parseLedger` gains `waiting` (carrying
  the question) and `deferred` (`complete (deferred by the auto run)`). The
  Run card draws each distinctly; `sendLedgerEvents` sends `question` for a
  new waiting line and `deferred`, not "✅ complete", for a deferred task.
- **Question notification (row 20).** A main turn that ends on a known
  plain-text ending — `Which option?`, a ledger ending on `waiting — `, a
  finishing stop — sends `question`, not `done`.
- **Run binding (row 18).** The Run card follows the plan this session last
  named in a `task-brief`, `task-step`, `task-close` or `next-step` call,
  after turn-end's local-workspace test; newest-by-mtime applies only to a
  session bound to no plan.
- **Resume offer (row 16).** Register names resolve through the docs-root
  mapping `planCandidates` uses.
- **Model switch (row 60).** Before `/model` runs, the cockpit writes the
  user's `model`, `modelSettings` and `effortLevel` to
  `~/.claude/dforge/sessions/saved-defaults/<session-id>.json`, never
  overwriting an existing snapshot, together with the launch model it is
  about to set. At session start a snapshot is restored only when the session
  that wrote it is dead and the user's current `model` still equals that
  launch model; any other snapshot is deleted with one line saying so.
- **Session changes (row 61).** One helper resets the per-session guards
  (keep-warm, reconcile, auto-deferred) on a session-id change, and a main
  compaction clears `turnTokens`.
- **Guards (rows 42, 43, 44).** The attribution guard matches trailer lines
  only and tests the name and address against AI identities, so a human
  co-author and a command that mentions a trailer pass. A failing `tool.call`
  hook fails closed only for calls the guards judge, and its message names
  `guardAttribution`. Unattended mode uses the permission mode the event
  carries when present.
- **Robustness and display (rows 45, 46).** `session.start` arms its timers
  first and guards each read. A `paneGlyphs` setting (`unicode` | `ascii`)
  switches the pane to ASCII, and the pane head shows a count of setting
  problems.
- **Saved-state honesty (rows 22, 47).** A Claude-key save polls for
  read-back as `restoreUserDefaults` does and toasts when the value did not
  stick. `rereadSettings` marks changed skill-enforced keys as changed.

### 8. Settings

- **One resolver (row 48).** List salvage and the `notifyOn`-as-`none`
  fallback move into `config/schema.mjs` beside `isValidValue`; both readers
  call it. `SettingSpec['unit']` includes `'min'`.
- **Broken file (row 24).** A settings file that is not a JSON object is a
  problem state: one problem line, shown on the pane head and injected once at
  session start, with `notifyOn` read as `none` until the file parses.
- **Writes (row 49).** `writeClaudeKeys` holds a lock on the resolved target
  path across read, change and rename.
- **Inert and consent rows (rows 50, 51).** The darkmem store rows are inert
  while darkmem is off. Raising `apiBudgetAgentRouter` from 0 needs a
  confirming second press, as Reset does.
- **Desktop view (row 63).** Steppers show `row.shown` (unit and zero word)
  beside the field; webhook and mention rows use the native stacked layout.

## Acceptance

A1. [test, high] When acceptance QA times out, a file the human edited during QA and not listed in `qa-touched.txt` keeps its content and is named in the final-review message.
A2. [test, neg, high] The QA timeout cleanup never restores or deletes a path absent from `qa-touched.txt`, with no manifest it touches nothing, and a re-dispatch never inherits an earlier run's entries.
A3. [test, high] With progress in darkmem, `amendments.md` is synced with the ledger, and a fresh checkout restored from the mirror applies the approved amendments.
A4. [test, high] Resume and `task-brief` exit 2 naming the missing amendment when the ledger cites `A<k>` and `amendments.md` lacks it.
A5. [test, high] `ci-mirror` reads an amended `**CI:**` line and finds a plan stored in the darkmem docs mirror.
A6. [test, neg, high] `task-brief --open` and `task-close` exit 2 when the ledger's plan line names a different plan with the same basename, and write nothing.
A7. [test, high] A ledger with `Final review: clean (commits a..h)` and a later non-docs commit routes to a re-review of `h..HEAD`; docs-only commits after `h` still route to finishing; when `h` is not an ancestor of HEAD it routes to a full final review.
A8. [test, high] Under Option 2 with darkmem documents, no completion record is written or synced when the push fails.
A9. [test, high] After Keep as-is, `next-step --kept` prints a pending-integration block naming the branch and does not print "is complete" or advance the programme.
A10. [test, high] `finish-choice answer` succeeds with no saved preference, and the no-plan record is gone after Step 7.
A11. [test, high] The compaction snapshot omits a `latest.md` that names another plan and predates the session, and keeps the newest ledger lines when over the cap.
A12. [test, high] `auto-run clear` refuses a `latest.md` prompt for another plan; `auto-run stop --stale` stops a run whose owner session is dead; `auto-run start --register` fills `**Covers:** -`.
A13. [test, neg, high] With darkmem stores applied and no Node on PATH, no script reads or writes a local ledger; scripts exit 2 with the node message and hooks pass with one warning line.
A14. [test, high] The cockpit writes the session state file at session start, prompt submit and turn end; a hook reading it mid-turn uses its `launches`, and `lib/session-state.sh` ignores `launches` older than the turn stamp while still using `window` for the same session, logging each rejection to `session-state.log`.
A15. [test, high] With a dev server as the only running launch, a mid-plan summary stop is held, as it is with nothing running.
A16. [test, high] `ctx_model_window` returns the session file's window when present; for an unlisted model without one, the budget line prints the `unknown` verdict and exits 3 and the auto-run verdict hands off on no size, with no arithmetic error.
A17. [test, high] Request-scoped fast mode ends at the next human prompt: the UI edit hook and UI proof hold run again in a later request that writes no `Process: fast` line.
A18. [test, high] `Process: fast (session)` keeps fast mode on across later requests until another `Process:` line names a different path, with no session state file present.
A19. [test, neg, high] The cockpit's budget nudge never fires while fast mode is on.
A20. [test, high] A bare `sleep` launch is never named as idle work to stop by the reconcile prompt.
A21. [test, confirmed] Session start returns within 45 seconds when darkmem reconcile or pull hangs (20 seconds per step, mirror lock wait cut to 10 seconds), and injects one line naming the sync command.
A22. [test, high] `ui-turn-end.sh` passes a stop whose message carries `## Next session`, a stop whose ledger ends on `waiting —`, and a stop with finite background work running, after a UI edit.
A23. [test, high] `ui-turn-end.sh` reads the transcript when `last_assistant_message` is absent and passes a message ending `UI proof: pending — …`.
A24. [test, high] In relaxed handoff mode the cockpit adds no handoff note during the final phase.
A25. [test, high] An unnamed base failure and an unnamed head failure with the same exit code count as a new failure.
A26. [test, high] `suite-run` records no reusable row when HEAD changed during the run, and treats a failed `git status` as dirty.
A27. [test, high] On a host with only `gtimeout`, `scripts/with-timeout 5 true` exits 0 and `agy-locate` bounds `agy --version`.
A28. [test, high] Without `setsid`, a timed-out panel runner leaves no descendant process alive.
A29. [test, high] `task-step` with `--cwd` resolves HEAD and diffs in that directory, and extracts the command from an Integration check line with a trailing note.
A30. [test, high] `ui-proof check` accepts a screenshot cited under the checkout's `.dforge/ui-proofs/` while documents live in darkmem.
A31. [test, neg, high] The judge guard refuses a write to a prior round's report named in a direct re-review prompt, and accepts the report on the prompt's report line.
A32. [test, neg, high] No judge agent file lists `WebFetch` among its tools.
A33. [test, high] `impl-stop-gate` blocks a stop whose reply ends `Report: <path>` when that file is missing or lacks `## Verdict`, and passes a reply with no `Report:` line.
A34. [test, high] `task-brief --open` on a `Host: codex` plan writes the open line and brief and exits 0.
A35. [test, high] `dforge-config workflow --host codex` emits `designApproval` and `specReview` overrides under `autoRun=on`.
A36. [demo, high] native-codex.md describes one judge per risk-3 review and no implementer escalation, reserve tier or split, and its lens routing names depth gating and `lensMinorFrom`.
A37. [test, high] `parseLedger` reads `waiting —` as waiting with its question and `complete (deferred by the auto run)` as deferred; a deferred task sends no "✅ complete" event.
A38. [test, high] A main turn ending on `Which option?` or on a ledger `waiting —` line sends a `question` notification.
A39. [test, high] The Run card shows the plan this session last named in a task-brief/task-step/task-close/next-step call, even when another worktree's ledger changed later.
A40. [test, high] Under `documentStore=darkmem` the resume offer clears once every row of its register is resolved.
A41. [test, high] A cockpit crash after `/model` and before restore leaves its per-session snapshot, and the next session start restores the user's model; a snapshot whose launch model no longer matches the current model, or whose session is alive, is not restored.
A42. [test, high] Keep-warm and reconcile counters reset on a session-id change, and `turnTokens` clears on a main compaction.
A43. [test, neg, high] The attribution guard passes a commit with a human `Co-Authored-By:` and a command that only mentions a trailer, and still refuses an AI co-author trailer.
A44. [test, high] A throwing `tool.call` hook refuses only guarded calls, with a message naming `guardAttribution`.
A45. [test, high] With `paneGlyphs=ascii` the pane renders only ASCII, and the pane head shows the setting-problem count.
A46. [test, high] A Claude-key save the engine does not keep is cleared from the view and toasted within 10 seconds.
A47. [test, high] Both settings readers resolve `"notifyOn": "off"` and `"sections": "plan,unknown"` to the same values.
A48. [test, high] A settings file with a trailing comma yields a problem line on the pane head and at session start, and `notifyOn` reads as `none`.
A49. [test, high] Two concurrent `writeClaudeKeys` calls on different keys both persist.
A50. [test, high] The darkmem store rows are inert while darkmem is off, and one press of `+` on `apiBudgetAgentRouter` at 0 does not change it.
A51. [demo, high] On desktop, steppers show unit and zero words, and webhook rows use the stacked layout.
A52. [test, high] The fast-mode question offers a fast-for-this-session answer in brainstorming and systematic-debugging.
A53. [demo, high] README, executing-plans, final-review.md and the QA persona carry no text describing the retired unplanned-commit hold, the fix subagent, a delegated cap of 5 on Claude plans, or per-task implementer dispatch.
A54. [test, high] An unattended-mode check uses the event's permission mode when the event carries one.
A55. [test, neg, high] Every existing suite still passes, except the assertions these rows rewrite: the baseline test (A25), impl-stop-gate's DONE contract (A33), the cockpit's service-shell tests (A15), the 1,000,000-token fallback (A16) and the fast-mode scope (A17, A18); no existing `Task <N>:` ledger line changes meaning for `ledger_blocked` or recovery.
A56. [test, high] A plan amended before the upgrade, with `amendments.md` still in its workspace, resumes and applies its amendments.

## Riskiest assumption

The cockpit can write a per-session file that the hook scripts find by
session id in time to use it. Evidence: the cockpit already writes
`~/.claude/dforge/sessions/cockpit/<id>` (`hooks/cockpit/register.tsx:3003`),
under the same `sessions/` directory the scripts' turn stamps use
(`scripts/turn-end.sh:42`), and it already holds the engine's window
(`figures.context.window`, register.tsx:3544). Whether the cockpit's write
lands before a Stop hook reads it in the same turn is unverified — the plan's
first task verifies it; the staleness rule falls back to the transcript scan
when it does not.

## Out of scope

The rejected findings and rejected halves listed in Decisions; register
`2026-11-15-residual-fixes.md` (unrelated agy behaviour); a version bump or
release.

## Critic findings

Architecture critic (judge-opus), 2026-11-15: 1 Blocker, 5 High, 5 Medium,
3 Nit — every one fixed in the sections above.

- [Blocker] Session-scoped fast mode lost by a tail-only fallback — fixed:
  `fast_mode_on` takes the newest `Process:` line in the whole transcript,
  read backwards (§3 Hot paths, Fast-mode scope; A18).
- [High] Session file stale for nearly every read — fixed: written at prompt
  submit too; `window`/`model` valid per session, `launches` per turn (A14).
- [High] QA gate had no source for the report path — fixed: QA replies end
  `Report: <path>`; the gate keys on it (A33).
- [High] Amendments move had no migration — fixed: first reader moves the
  workspace file and logs a ruling (A56).
- [High] One global saved-defaults file — fixed: per-session, never
  overwritten, restored only when the writer is dead and the launch model is
  still set (A41).
- [High] `unknown` window reached bash arithmetic — fixed: consumers take the
  existing unknown verdict, exit 3 (A16).
- [Medium] QA manifest lifecycle — fixed: truncated with `qa-status-before.txt`;
  acceptance-qa.md allows the append (A2).
- [Medium] A55 contradicted pinned suites — fixed: A55 names the rewritten
  assertions.
- [Medium] Rewritten history after the clean review — fixed: full final review
  with a ruling (A7).
- [Medium] `fastMode` duplicated the `Process:` grammar — fixed: dropped from
  the session file.
- [Medium] No trace of the source used — fixed: `session-state.log`, and the
  source named by `in-flight` and the budget line.
- [Nit] Node warning on every hook — fixed: once per session at start.
- [Nit] State file retention — fixed: pruned after 30 days.
- [Nit] `effortLevel` probe — fixed: always snapshotted.

## Review rulings

Fable spec review, round 1 (2026-11-15): 20 rulings, 0 Blocker and 0 High
left open. Each ruling below amends the design section and acceptance
statements it names and takes precedence over them; the plan follows the
ruling where the two differ.

- Fable, spec: R1 QA cleanup (row 1; A1, A2) — the cleanup becomes a script, not prose: `scripts/qa-files begin <workspace>` saves the status snapshot and truncates `qa-touched.txt`, and `scripts/qa-files clean <workspace>` restores or deletes the paths that are in the manifest and new, then prints every other new dirty path. Both read `git status --porcelain=v1 -z --untracked-files=all`, delete files only (a directory only once empty), and final-review.md calls them at :145-146, :163-168 and :121-125. Every dispatch runs `begin`, the `rerun` re-dispatch included, after the cut-off cleanup.
- Fable, spec: R2 Amendments (row 25; A3, A4, A56) — the spec must name the sync work: `amendments.md` joins the per-plan document set beside `handoff.md` in `darkmem-mirror.mjs` (the URI mapping at :38-48 and `listDocumentFiles`), `darkmem-pull.mjs`, `darkmem-progress-move.mjs` (both directions) and reconcile. Replace `dforge_dir ledger <plan>` with `dforge_ledger_dir <slug>`. The missing-amendment refusal and the workspace migration live in one `lib/plan.sh` function that every amendments consumer calls (`plan-amend`, `task-brief`, `task-step`, `task-close`, `plan-lint`, `review-route`, `lens-route`, `depth-route`, `ci-mirror`); "resume" in A4 means the `task-brief` call resume-execution makes, since that skill has no script.
- Fable, spec: R3 Stale final review (row 3; A7) — one helper in `lib/plan.sh` reads the last `Final review: clean (commits …)` line and answers `current`, `stale <head>`, `rewritten` or `none`; `next-step`, `turn-end.sh:91` and recovery.md use it, so the Stop hold never says "invoke finishing" on a stale line. The scoped re-review is final-review.md's existing fix-wave re-review (`re-review-prompt.md`, report `final-rereview-report.md`) over `<head>..HEAD`; when clean it appends a new clean line with the new head. The rule applies while HEAD is on the plan's branch; a base branch that already contains `<head>` routes to finishing. A7 gains: a stop after a stale clean line is not held for the finishing menu.
- Fable, spec: R4 Services (row 12; A15) — the spec must say what a service-only list does everywhere: `scripts/in-flight` lists services marked `service` and exits 1 only for finite work; `next-step` prints its block over a service-only list with one line naming the services; `turn-end.sh`'s session-ending hold (:130-141) counts finite work only. `config/services.json` holds patterns valid in both JavaScript `RegExp` and jq (Oniguruma), is evaluated with jq on the shell side (never `grep -E`: three patterns use lookahead), against the command's first line, which `inflight_scan` must carry in addition to the description. One fixture of commands is asserted through both implementations.
- Fable, spec: R5 Session file contract (rows 12, 28, 37, 40; A14) — `launches` is authoritative only for what the cockpit tracks. Either the cockpit learns every launch form `in-flight.sh:74-85` recognises (Monitor, a resumed agent, an agent that reported with work of its own still running) and one fixture proves both sources give the same list, or the file marks `launches` as partial and the helper falls back to the scan. Each launch carries `{id, kind, what, command, startedAt, outputFile, service, timer}` so the five-field in-flight line and the bare-`sleep` test can be produced from it. With no turn stamp, `launches` is stale. The file name uses the stamp's sanitised id.
- Fable, spec: R6 Fast mode (rows 14, 59; A17-A19) — delete "`fast_mode_on` remains its only parser": the cockpit has `fastModeLine` (lib.ts:202-209) feeding `isFastMode` (register.tsx:264, 523, 596-597). The spec must give the cockpit the same rule (reset at a person-origin `prompt.submit` unless session-scoped; recognise `fast (session)`), add `isFastMode` to the nudge guard from that state, and assert one transcript fixture through both parsers. A plain `fast` line that has expired does not end a session scope: `fast_mode_on` skips expired plain lines and stops at the first `fast (session)` or non-fast line, caching the pre-stamp verdict beside the turn stamp so the scan runs at most once per turn. fast-mode.md says a later turn of the same request restates the line before its first edit, and the compaction snapshot carries a session-scoped line. With no stamp, plain `fast` counts as on.
- Fable, spec: R7 Judge guard (rows 17, 62; A31) — narrow, do not replace: a direct prompt that has a `Write your full report to <path>` line allows only that line's paths; a direct prompt with no such line, or whose line names no path, keeps today's behaviour. Otherwise the lens seats (final-review.md:293-295, the phrase wraps across lines), the milestone judge (milestone-judge.md:16, :43), the dedupe judge (final-review.md:358-360) and the auto-run and advisor dispatches are refused. Drop "or `Write your complete review to`" unless a template uses it; none in the plugin does.
- Fable, spec: R8 A55 — replace the fixed list with "except assertions that pin behaviour a register row changes; the plan names each rewritten assertion in the task for its row". The list omits at least `tests/fleet.test.sh:29` (judge tools with WebFetch, row 36) and `tests/task-open-close.test.sh:110-111` (`--open` on a Codex plan exits 2, row 4), so A55 contradicts A32 and A34 as written.
- Fable, spec: R9 Acceptance coverage — add statements for the uncovered rows: row 39 (`fast_mode_on` returns the right verdict without reading past the deciding line, shown by a transcript whose head is unreadable; the newest-ledger scan does not re-stat unchanged directories), row 45 (the watchdog and poll are armed when a `session.start` read throws), row 47 (a skill-enforced key changed in the file mid-session produces the settings note), row 52 (a checkpoint with a newline exits 2; "verified: self review clean" in a checkpoint does not show as reviewed), row 62 (a report under the session cwd is accepted when `S.where` is unset and `git worktree list` fails). Extend A27 or A53 to the three procedures naming `with-timeout`, A24 to the `handoffTokens` lock text, A17 to the cockpit seat check, A12 to the pane and resume-execution naming a stale run.
- Fable, spec: R10 PR record and prose-only tests (row 6; A8, A10) — scope the reorder to darkmem documents and to all of Step 5b (index line, register rows, roadmap settle, review record); with local documents the commit stays before the push, as it travels with the PR and the verified finding found no harm there. A8 and the "gone after Step 7" half of A10 describe prose procedures: retag them `demo`, or word them as text assertions on execute-choice.md and SKILL.md, or move the clearing into `next-step --complete|--kept|--adhoc` so a script does it.
- Fable, spec: R11 Compaction snapshot (row 5; A11) — name the sources: the session start is the first timestamp in the transcript the hook is given (`by-id/<id>.json` is rewritten at every start event, the compact one included, and `.since` exists only after startup or resume); "a ledger this session wrote" is a ledger modified at or after that time.
- Fable, spec: R12 Missing Node (row 15; A13) — the function is `dforge_stores_init` (roots.sh:66), not `dforge_roots`. Trigger on a family recorded as applied (`stores.json`), which is what the message and A13 say; `dforge_darkmem_possible` is also true for a config that merely has a darkmem section, and exiting 2 there breaks Node-less shells for homes whose stores are local. If `--mode` can answer darkmem with no `stores.json`, the spec says so instead.
- Fable, spec: R13 Codex workflow line (row 23; A35) — no Codex entry point exists (`.codex-plugin/plugin.json` has `"hooks": {}`; the line is injected only by the Claude SessionStart hook). Name the files: brainstorming SKILL.md:89-93 and native-codex.md tell a Codex session to run `dforge-config workflow --host codex`.
- Fable, spec: R14 UI-proof evidence (row 27; A30) — state that under darkmem documents screenshots are `**Evidence:** local` under the self-ignored `<checkout>/.dforge/ui-proofs/`, and that a profile's `**Screenshots:** commit` is not honoured there, said in one line by the walkthrough. Reword A30: `ui-proof check` already accepts a checkout-relative path (ui-proof:151), so the statement passes on today's code; it must assert a screenshot cited by its docs name resolving through `dforge_resolve`.
- Fable, spec: R15 Question notifications (rows 19, 20; A37, A38) — one `question` per waiting line: `sendLedgerEvents` sends it, keyed on task and question, and the turn-end path does not send a second for the same line.
- Fable, spec: R16 Model switch snapshot (row 60; A41) — the writer deletes its snapshot after a restore that read back; a snapshot whose writer is alive is left alone, not deleted (spec:240 says "any other snapshot is deleted", which removes a concurrent session's protection and contradicts A41's intent).
- Fable, spec: R17 Unknown window in an auto run (row 28; A16) — reword A16's "hands off on no size": with an unknown window the auto line prints `unknown`, exits 3, sets no `pending`, and a pending `after-compact` settles to continue, so the Stop hold at turn-end.sh:172-174 cannot repeat forever.
- Fable, spec: R18 Session-start bound (row 41) — whatever bound the owner picks, `DARKMEM_SYNC_LOCK_WAIT_MS` (30 s today, darkmem-hook.sh:114, :120) must be below it, or a Stop push holding the mirror lock makes every start report an unfinished sync.
- Fable, spec: R19 QA gate (row 53; A33) — stands. Keying on the reply's `Report:` line follows the Decision; a QA reply that omits the line passes unchecked, which is the residual the two-block and five-fire limits already accept. The block message at impl-stop-gate:141 must stop naming the `**Status:**` line.
- Fable, spec: R20 Decisions — stands. Scope, QA manifest, session file with transcript fallback, WebFetch removal, gate retarget, the third fast-mode answer and no release are each carried by a design bullet with no contradiction; always snapshotting `effortLevel` is harmless where `/effort` does not write it.
