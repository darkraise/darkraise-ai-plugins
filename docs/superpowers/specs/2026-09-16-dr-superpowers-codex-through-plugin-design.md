# dr-superpowers — Codex through the plugin (sub-project 9 design)

Date: 2026-09-16. Status: owner-approved design. Sub-project 9 of 9 of
`docs/superpowers/specs/2026-09-11-dr-superpowers-fork-design.md`, the last.

Supersedes the sketch in
`docs/superpowers/specs/2026-09-15-dr-superpowers-review-routing-design.md` §15.8,
whose central premise — `runAppServerTurn` in direct mode — is not achievable
(§3 below).

## 1. What this sub-project is for

Sub-project 8 put every Codex *decision* behind a session gate that reaches the
official `codex@openai-codex` plugin and nothing else. It left every Codex *run*
where it was: `run-codex-review.sh`, `run-codex-task.sh` and
`detect-executors.sh` still invoke the `codex` executable directly, and
`detect-executors.sh` still reads Codex-owned state.

This sub-project closes that gap. After it, dr-superpowers reaches Codex through
exactly one seam, and the owner constraint — "codex in claude code must be used
via codex plugin ... do not rely on codex command, but rely only on codex
plugin" (2026-09-15) — holds for runs as well as for the gate.

## 2. Decisions fixed here

Each was decided by the owner during the 2026-09-16 design session.

1. **The locator stays strict and profile-scoped.** Only a plugin enabled in the
   *active* `CLAUDE_CONFIG_DIR` counts. A plugin installed and enabled in another
   profile is not used, and the gate keeps reporting `plugin-not-enabled`.
   Enabling it elsewhere is owner configuration, not something the locator works
   around. Fail-closed stays simple.
2. **One shared client module, thin bash callers** (approach B of three). The
   alternatives were a Node worker per runner, and rewriting both runners in
   Node; see §9.
3. **The model catalog read is dropped, not relocated.** Ruling 18 of the SP8
   spec left this open; it is settled here. The plugin exposes no catalog API
   whatsoever, so there is nothing to relocate to.
4. **The status line keeps its `evidence=` field, always `evidence=none`.**
   Dropping the field would be an interface change for every skill that reads
   the line.
5. **Broker mode, with a reaper we own.** This amends SP8 ruling 12, which said
   direct mode; that ruling now applies to the gate only. See §3.
6. **One sub-project, not two.** The whole migration lands together, keeping the
   program's "sub-project 9 of 9" count true.
7. **Code now, shipping gates when quota returns.** Implementation proceeds
   against stub fixtures; calibration and smoke record `PENDING` and a follow-up
   session after 2026-09-20 17:03 (+07) runs them on the new path and flips
   `trust` in a release. This repeats SP8's shape deliberately.

## 3. The premise that had to change

SP8 §15.8 specified `runAppServerTurn` "in direct mode (`disableBroker: true`)".
Read against `codex@openai-codex` 1.0.3, those two cannot hold together:

- `runAppServerTurn` delegates to `withAppServer`, which calls
  `CodexAppServerClient.connect(cwd)` with **no options**.
- `connect()` with no options calls `ensureBrokerSession(cwd)`, which **spawns a
  detached broker daemon** when none is running. `disableBroker` is reachable
  only by calling `connect` yourself.
- The helpers `runAppServerTurn` composes — `startThread`, `resumeThread`,
  `buildThreadParams`, and `captureTurn`, which aggregates the notification
  stream into `lastAgentMessage`, `reasoningSummary`, `fileChanges` and
  `commandExecutions` — are **not exported**.

So a caller can have the public convenience function, or direct mode, but not
both. Direct mode would mean reimplementing `captureTurn` against the app-server
JSON-RPC protocol: a *larger* coupling surface than the one the version
allowlist exists to bound, not a smaller one.

**Decision.** Use the public `runAppServerTurn`, accept the broker, and own its
shutdown (§6). Ruling 12's direct-mode requirement was reasoned about the gate,
where a sub-second rate-limit probe spawning a daemon is absurd; the gate keeps
direct mode unchanged. A twenty-minute review run is a different trade, and a
reaper is required regardless — SP8 §15.8 already called for one for "an
app-server that ignores stdin EOF".

A third option, forcing `withAppServer`'s ECONNREFUSED retry into direct mode by
pointing `CODEX_COMPANION_APP_SERVER_ENDPOINT` at a dead endpoint, is rejected:
it depends on an internal error path that a patch release could remove silently.

## 4. `scripts/lib/codex-client.mjs` — the one seam

**Amendment 2026-09-16 (written during planning).** The design first put a
`locate()` in this module. It does not belong here: `scripts/codex-plugin`
already resolves the plugin for the active profile, checks enablement, verifies
the install and enforces the version allowlist, and it already hands the root to
`codex-gate.mjs` as argv. `codex-client.mjs` takes `<plugin-root>` the same way.
The allowlist therefore stays enforced in exactly one place, which is the
property that matters, and `scripts/codex-gate` and `scripts/lib/codex-gate.mjs`
are left completely untouched rather than refactored. This strictly reduces the
change.

`codex-client.mjs` is the only *new* file that imports from the Codex plugin,
and the only one that runs a turn. Its surface, invoked as
`node codex-client.mjs <plugin-root>` with the request on stdin:

It is a command-line module, not a library: nothing imports it, so it exports
nothing. The two operations below are reached by the request's `op` field.

| Operation | Does |
|---|---|
| `op: "turn"` | One Codex turn, with deadline, interrupt and reap; prints a result object |
| `op: "auth"` | The plugin's login state, for the executor roster |

Reaping is not a separate operation: every turn reaps the broker it caused to
exist before it prints, and a broker that already existed is left alone, because
it belongs to the user's own Codex session rather than to this run.

`runTurn`'s request, marshalled as JSON on stdin:

```
{ kind, cwd, model, effort, prompt, schemaPath, sandbox,
  resumeThreadId, persistThread, threadName, deadlineMs }
```

Its result, JSON on stdout:

```
{ turnStatus, threadId, turnId, refusal, quota, timedOut,
  finalMessage, stderr, interrupted, reaped }
```

`turnStatus` is the plugin's own turn status (0 completed, 1 otherwise). The
module writes no output file and chooses no exit code: the caller writes the
report to its `--out` path and decides the process exit, because exit codes are
part of the argv contract bash owns (§5).

Every kind routes to `runAppServerTurn`, with `outputSchema` read from
`schemaPath` when one is given.

`runAppServerReview` is **not** used. It reads only `model`, `threadName`,
`target` and `delivery` (`codex.mjs:908-961`), starts its own read-only thread
and answers in Codex's report shape, so a seat's criteria prompt and output
schema would be silently discarded — the same reason SP8 moved every other kind
off `codex exec review`. `--kind final` therefore arrives with
`criteria/codex-final-review.md` and `git diff <base>...HEAD` already composed
into `prompt` by `run-codex-review.sh`, and with `schemaPath` null: the final
round has no schema of its own, and its report stays the markdown findings list
`reference/final-review.md` §3 deduplicates. There is no `base` request field;
`--base` is consumed by the runner when it builds the diff. (Owner ruling,
2026-09-16.)

**Version allowlist.** `scripts/codex-plugin` is the single place the allowlist
is enforced, which is what makes bounding the coupling meaningful: every caller
of `codex-client.mjs` passes a root that the locator has already vetted.
`reference/codex-plugin.json` keeps its current shape, and adding a version is
still an owner action.

## 5. What each caller keeps

`run-codex-review.sh` and `run-codex-task.sh` stay bash and keep every
externally-visible contract: argv, the `codex-judge …` status line, exit codes,
output paths, the `reference/ladder.md` rung lookup, refusal-to-fallback policy,
and the task record with its resume and attempts semantics. Bash keeps the
policy; Node owns the plugin coupling. The block that built a `codex exec` argv
and spawned it is what changes, and only that.

`scripts/codex-gate`, `scripts/lib/codex-gate.mjs` and `scripts/codex-plugin`
are **not modified by any task**. The locator keeps enforcing the version
allowlist for every caller, and the gate keeps its rate-limit probe, its cache
format, its status line and its 53 assertions exactly as SP8 shipped them.

`scripts/detect-executors.sh` stops reading
`${CODEX_HOME:-$HOME/.codex}/models_cache.json`. That read is the standing
violation of SP8 ruling 13 ("dr-superpowers never names the `codex` executable
and never reads Codex-owned state"), and with the catalog dropped nothing needs
it. Presence and auth come from `scripts/codex-plugin` and the plugin's
`getCodexAuthStatus`, reached through `codex-client.mjs`.

## 6. The deadline, the interrupt and the reaper

All three rest on exported plugin API, verified in 1.0.3.

**Deadline.** `runTurn` installs an `onProgress` recorder. The plugin's
`ProgressReporter` carries `threadId` and `turnId`; the turn id arrives with the
turn-started update. The recorder keeps the latest pair.

**Interrupt.** On expiry, `interruptAppServerTurn(cwd, {threadId, turnId})`. It
requires both ids and returns `attempted: false` without them; it connects with
`reuseExistingBroker: true`, so it never spawns a second daemon. The client is
then closed. The outcome stays `TIMEOUT` with exit 124, as today.

**Reaper.** `broker-lifecycle.mjs` exports `loadBrokerSession`,
`sendBrokerShutdown`, `teardownBrokerSession` and `clearBrokerSession`. Every
run ends by shutting down the broker it caused to exist: graceful shutdown
first, then teardown. The plugin's own SessionEnd hook cannot be relied on — it
does not fire in a profile where the plugin is not enabled, which is exactly the
profile this repository is developed in.

`teardownBrokerSession` takes a `killProcess` hook. That hook carries over
`run-codex-task.sh`'s existing Windows knowledge, which must move rather than
evaporate: the native `taskkill /F /T /PID` tree-walk, and the reason no wrapper
process may sit between the runner and node (a wrapper defeats the tree-walk,
which is why the current runner polls rather than using `timeout`).

## 7. Outcomes read from structure, not from a transcript

Today `is_refusal` and `is_quota` grep error-shaped lines out of the captured
transcript. `run-codex-review.sh` carries a comment recording why the search is
anchored: a 2026-09-14 `--kind final` run left 10,590 stderr lines holding 20
matches for an unanchored pattern, because this plugin's own tests and prose
quote refusal messages.

Through the client those become reads of structured result fields. The mapping:

| Outcome | Condition |
|---|---|
| `OK` | turn status 0 and output valid against the kind's schema |
| `FALLBACK` | refusal on the result's error; one retry on the fallback rung |
| `TIMEOUT` | deadline fired; exit 124 |
| `FAILED` | locate, version, auth or quota failure |

A quota failure still marks the session off through
`scripts/lib/codex-session.sh`. `evidence=none` on every status line.

## 8. Interface changes

Named here so the plan treats them as deliberate:

1. `--dry-run` prints the request JSON instead of a `codex exec …` argv.
2. The roster row loses its `advertised` field.
3. `reference/external-executor.md` loses the "the catalog did not advertise the
   preferred rung" substitution paragraph: that case ceases to exist. The
   preferred rung is attempted, and a refusal falls back as it already does.
4. `--kind risk3` and `--kind final` keep their argv and exit codes, but their
   status line's `evidence=` value becomes `none`. SP8's constraint freezing
   these kinds byte-for-byte is lifted by this sub-project, as SP8 §15.8 said.
5. `--kind final` composes its own prompt. The runner reads
   `criteria/codex-final-review.md` and appends `git diff <base>...HEAD` instead
   of handing the round to Codex's own review flow. Its argv and its `--out`
   contract are unchanged: no `--prompt`, and a markdown findings list on the way
   out.

## 9. Approaches considered

| Approach | Why not |
|---|---|
| A Node worker per runner, mirroring the gate | Lowest risk, but the plugin import lives in three files — the coupling the version allowlist is meant to bound in one place |
| Rewrite both runners in Node | Discards ~700 lines of working, heavily tested bash for a contract the suites pin but can still drift on in exit codes and quoting |
| **B: one shared client, thin bash shims** | **Chosen.** One seam, one place for deadline and reaper, gate left functionally alone |

## 10. Testing

A **stub-plugin fixture**: a fake plugin tree exporting scripted `codex.mjs`,
`app-server.mjs` and `broker-lifecycle.mjs`, reached through the locator by
pointing the config dir at the fixture. `tests/codex-gate.test.sh` already does
this at smaller scale and is the pattern to follow.

Every suite runs against the stub; no test starts a real Codex, and no test
reads the machine's Claude config or session file. Suites touched:
`codex-review`, `codex-gate`, `lanes`, and a new `codex-client` suite covering
`runTurn`'s fail-closed cases, the deadline and interrupt path, and the reaper.

Suites touching the runners keep exporting `DR_CODEX_SESSION_DIR` and
`CLAUDE_CODE_SESSION_ID`, per the standing constraint.

## 11. Gates before it ships

Unchanged in kind from SP8 §11, and run on the new path:

- **Calibration** — replay four recorded plan reviews through the migrated
  review runner; agreement within the tolerance SP8 §11 fixes opens the
  **review** surface by setting `trust.calibration`.
- **Smoke** — one real executor-lane run through the migrated task runner opens
  the **lane** surface by setting `trust.smoke`.

Both run only when `scripts/codex-gate` reports Codex usable. With quota
exhausted until 2026-09-20 17:03 (+07) and the plugin not enabled in this
profile, both are expected to record `PENDING`, and every Codex surface ships
off. A follow-up session flips `trust` in a release once they pass.

## 12. Verification

- `node scripts/test-all.mjs` green but for the documented pre-existing
  `rg: command not found` in `tests/ui-discovery.test.mjs`.
- `node scripts/validate-repository.mjs` valid.
- `claude plugin validate` on the marketplace and every Claude plugin.
- No file under a plugin contains `superpowers:` without the `dr-` prefix.
- No script other than `codex-client.mjs` imports from the Codex plugin, and no
  script reads Codex-owned state.

## 13. Program design amendment

Sub-project 9, "Codex through the plugin", is the last of nine. It introduces
`scripts/lib/codex-client.mjs` as the single seam to the official
`codex@openai-codex` plugin; moves `run-codex-review.sh`, `run-codex-task.sh`
and the executor roster onto it; drops the `models_cache.json` read, settling
ruling 18 by removing the catalog rather than relocating it; and amends ruling
12 so direct mode binds the gate only, because `runAppServerTurn` spawns a
broker and its thread helpers are unexported. Runs use broker mode with a reaper
this plugin owns. Shipping is gated on calibration and smoke replayed through
the new path; both record `PENDING` while Codex is unusable.
