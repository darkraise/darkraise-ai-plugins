# Codex through the plugin — calibration and smoke results

Spec: `docs/superpowers/specs/2026-09-16-dr-superpowers-codex-through-plugin-design.md` §11.
Run: 2026-09-16, not run to completion — codex-gate usable=false reason=plugin-not-enabled review=false lane=false resets_at=- source=cache.

Both gates replay through the migrated path: the review runner and the task
runner now reach Codex only through `scripts/lib/codex-client.mjs`. Neither can
run while the gate reports Codex unusable.

## Calibration

| Plan | Version | Status line | Recorded | Max delta | Result |
|---|---|---|---|---|---|
| project-state | d6c288c | - | 17 / 16 / 17 / 16 | - | PENDING — codex unusable |
| judge-seats | 01f5a2a | - | 17 / 18 / 16 / 16 | - | PENDING — codex unusable |
| inline-mode | 69c6b48 | - | 17 / 18 / 14 / 16 | - | PENDING — codex unusable |
| small-model | 5e96f14 | - | 17 / 17 / 16 / 17 | - | PENDING — codex unusable |

Gate: PENDING. The review surface stays off: `trust.calibration` in
`plugins/dr-superpowers/reference/codex-plugin.json` stays `pending`.

## Smoke test

Run: 2026-09-16, not run to completion — same gate line.

Gate: PENDING. The lane surface stays off: `trust.smoke` stays `pending`.

## What a later session must do

Codex quota resets 2026-09-20 17:03 (+07), and `codex@openai-codex` must be
enabled in the profile the session runs under — it is enabled in `~/.claude` but
not in `~/.claude-alt`, which is where this repository is developed. With both
true, re-run each gate, replace the PENDING rows with the measured results, and
flip the matching `trust` field in a plugin release.
