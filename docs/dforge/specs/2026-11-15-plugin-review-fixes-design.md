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

## Problem

The review found one data-loss path, 28 Important and 34 Minor defects. Their
common cause: a rule changed in the core scripts and not in every reader of
the same state (the cockpit's TypeScript, `ui-turn-end.sh`, `native-codex.md`,
the darkmem path handling), and several scripts infer session facts the
cockpit already knows.

## Design

Grouped by subsystem. Each bullet names its register row(s).

### 1. Data safety

- **QA manifest (row 1).** Acceptance QA appends each path it creates,
  modifies or deletes to `<workspace>/qa-touched.txt`, one repository-relative
  path per line, before it writes the path. On a QA timeout (both the main
  path at final-review.md:163-168 and the recovery path at :121-125) the
  session restores or deletes only paths that are both listed in the manifest
  and new relative to `qa-status-before.txt`. Every other new dirty path is
  left untouched and named in the final-review message and the ledger ruling.
  A missing manifest means nothing is cleaned. Carried paths stay exempt.
- **Amendments are durable (row 25).** `amendments.md` lives in the ledger
  directory (`dforge_dir ledger <plan>`), so it follows progress into the
  darkmem mirror and is synced and retained with the ledger. `review-record`
  keeps it. Recovery (`resume-execution`, `task-brief`) refuses with exit 2
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
  scoped re-review of `<head>..HEAD`, not to finishing.
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
  stores are applied". Hooks treat that exit as "pass silently and add one
  warning line"; scripts the session calls fail with the message.

### 3. Cockpit session file

- **Contract (rows 12, 28, 39, 40).** The cockpit writes
  `~/.claude/dforge/sessions/state/<session-id>.json` at session start, at
  every turn end and whenever a launch starts or ends:
  `{session, updated, window, model, fastMode: {on, scope, since},
  launches: [{id, kind, what, service}]}`. Scripts read it through one helper
  in `scripts/lib/session-state.sh`, and only when `updated` is not older
  than the session's turn stamp; otherwise they fall back to today's
  transcript scan.
- **One service list (row 12).** The service patterns the cockpit uses
  (`SERVICES`, `isServiceCommand`) move to `config/services.json`, read by
  both the cockpit and `lib/in-flight.sh`. In `turn-end.sh` a running service
  no longer passes a plain stop: only finite background work does.
- **Context window (row 28).** `ctx_model_window` takes the session file's
  `window`; without it, a model id the table does not list yields
  `unknown`, never a guessed 1,000,000.
- **Hot paths (row 39).** `fast_mode_on` reads the session file, else only
  the transcript tail since the turn stamp. The newest-ledger scan caches by
  directory modification time.
- **Fast-mode scope (rows 14, 59).** `Process: fast — <why>` covers the one
  request: it ends at the next human prompt unless that turn writes another
  `Process: fast` line. The fast-mode question gains a third answer, fast for
  this session, written `Process: fast (session) — <why>`, which stays in
  force until the session ends or a later `Process:` line names another path.
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
  walkthrough dispatches only. `impl-stop-gate` checks that the report path
  named in the dispatch exists and opens with its required heading
  (`## Verdict` for QA), and passes any other stop.

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
- **Model switch (row 60).** The saved defaults are written to
  `~/.claude/dforge/sessions/saved-defaults.json` before `/model` runs and
  restored from it at the next session start when still present.
  `effortLevel` joins the snapshot if the plan's first cockpit task finds
  that `/effort` writes it.
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
A2. [test, neg, high] The QA timeout cleanup never restores or deletes a path absent from `qa-touched.txt`, and with no manifest it touches nothing.
A3. [test, high] With progress in darkmem, `amendments.md` is synced with the ledger, and a fresh checkout restored from the mirror applies the approved amendments.
A4. [test, high] Resume and `task-brief` exit 2 naming the missing amendment when the ledger cites `A<k>` and `amendments.md` lacks it.
A5. [test, high] `ci-mirror` reads an amended `**CI:**` line and finds a plan stored in the darkmem docs mirror.
A6. [test, neg, high] `task-brief --open` and `task-close` exit 2 when the ledger's plan line names a different plan with the same basename, and write nothing.
A7. [test, high] A ledger with `Final review: clean (commits a..h)` and a later non-docs commit routes to a re-review of `h..HEAD`; docs-only commits after `h` still route to finishing.
A8. [test, high] Under Option 2 with darkmem documents, no completion record is written or synced when the push fails.
A9. [test, high] After Keep as-is, `next-step --kept` prints a pending-integration block naming the branch and does not print "is complete" or advance the programme.
A10. [test, high] `finish-choice answer` succeeds with no saved preference, and the no-plan record is gone after Step 7.
A11. [test, high] The compaction snapshot omits a `latest.md` that names another plan and predates the session, and keeps the newest ledger lines when over the cap.
A12. [test, high] `auto-run clear` refuses a `latest.md` prompt for another plan; `auto-run stop --stale` stops a run whose owner session is dead; `auto-run start --register` fills `**Covers:** -`.
A13. [test, neg, high] With darkmem stores applied and no Node on PATH, no script reads or writes a local ledger; scripts exit 2 with the node message and hooks pass with one warning line.
A14. [test, high] The cockpit writes the session state file at session start and turn end, and `lib/session-state.sh` ignores a file older than the turn stamp.
A15. [test, high] With a dev server as the only running launch, a mid-plan summary stop is held, as it is with nothing running.
A16. [test, high] `ctx_model_window` returns the session file's window when present and `unknown` for an unlisted model without one.
A17. [test, high] Request-scoped fast mode ends at the next human prompt: the UI edit hook and UI proof hold run again in a later request that writes no `Process: fast` line.
A18. [test, high] `Process: fast (session)` keeps fast mode on across later requests until another `Process:` line names a different path.
A19. [test, neg, high] The cockpit's budget nudge never fires while fast mode is on.
A20. [test, high] A bare `sleep` launch is never named as idle work to stop by the reconcile prompt.
A21. [test, medium] Session start returns within 45 seconds when darkmem reconcile or pull hangs, and injects one line naming the sync command. Q: is a 20-second bound per darkmem step right for your network?
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
A33. [test, high] `impl-stop-gate` blocks a QA dispatch's stop when its named report is missing or lacks `## Verdict`, and passes otherwise.
A34. [test, high] `task-brief --open` on a `Host: codex` plan writes the open line and brief and exits 0.
A35. [test, high] `dforge-config workflow --host codex` emits `designApproval` and `specReview` overrides under `autoRun=on`.
A36. [demo, high] native-codex.md describes one judge per risk-3 review and no implementer escalation, reserve tier or split, and its lens routing names depth gating and `lensMinorFrom`.
A37. [test, high] `parseLedger` reads `waiting —` as waiting with its question and `complete (deferred by the auto run)` as deferred; a deferred task sends no "✅ complete" event.
A38. [test, high] A main turn ending on `Which option?` or on a ledger `waiting —` line sends a `question` notification.
A39. [test, high] The Run card shows the plan this session last named in a task-brief/task-step/task-close/next-step call, even when another worktree's ledger changed later.
A40. [test, high] Under `documentStore=darkmem` the resume offer clears once every row of its register is resolved.
A41. [test, high] A cockpit crash after `/model` and before restore leaves `saved-defaults.json`, and the next session start restores the user's model.
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
A55. [test, neg, high] Every existing suite still passes, except the baseline assertion A25 replaces, and no existing `Task <N>:` ledger line changes meaning for `ledger_blocked` or recovery.

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
