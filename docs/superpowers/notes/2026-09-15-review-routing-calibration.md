# Review routing — calibration and smoke results

Spec: `docs/superpowers/specs/2026-09-15-dr-superpowers-review-routing-design.md` §11, §15.6.
Run: 2026-09-16, not run to completion — `codex-gate usable=false reason=plugin-not-enabled review=false lane=false resets_at=- source=cache`.

## Calibration

| Plan | Version | Status line | Astra e / c / v / a | Recorded | Max delta | Result |
|---|---|---|---|---|---|---|
| project-state | d6c288c | - | - | 17 / 16 / 17 / 16 | - | PENDING — codex unusable: plugin-not-enabled |
| judge-seats | 01f5a2a | - | - | 17 / 18 / 16 / 16 | - | PENDING — codex unusable: plugin-not-enabled |
| inline-mode | 69c6b48 | - | - | 17 / 18 / 14 / 16 | - | PENDING — codex unusable: plugin-not-enabled |
| small-model | 5e96f14 | - | - | 17 / 17 / 16 / 17 | - | PENDING — codex unusable: plugin-not-enabled |

Gate: PENDING — codex unusable: plugin-not-enabled. The review surface stays off: `trust.calibration` in `plugins/dr-superpowers/reference/codex-plugin.json` stays `pending`.
