# agy Hydrogen review measurement

Date: 2026-11-15 (plan of 2026-11-14)

agy version: 1.5.9

Gemini 4 Hydrogen (`high`, `xhigh`) against Gemini 4 Argon (`high`) as the
`agy-judge` fallback row, through the shipped `scripts/run-agy-review.sh` in a
scratch clone, with fixture one-row ladders and a gate stub reporting
`claude=off`. No Claude model and no `--dangerously-skip-permissions` was used.

## Branches

The three most recent first-parent merges into `main` with at least 200
changed lines under `plugins`:

| Branch | Merge | Head | Base | Lines under plugins |
|---|---|---|---|---|
| b1 | 712dbf36 (fix/cockpit-reported-issues) | bc097711 | b36eaf63 | 1419 |
| b2 | b36eaf63 (chore/audit-2026-11-14) | 3fbcfaef | 56ac7568 | 13169 |
| b3 | 2fd485ee (feat/retire-executor-lanes) | e48eeafa | 5bb5545f | 11773 |

The b2 diff the final round embeds is 9.1 MB; b1's is 164 KB and b3's 1.0 MB.

## Runs

Findings were judged blind by `dforge:judge-opus` (lists shuffled, no model
named); a confirmed finding is a real defect of that branch's diff.

| Model | Effort | Branch | Kind | Status | Seconds | Findings | Confirmed |
|---|---|---|---|---|---|---|---|
| gemini-4-argon | high | b1 | final | OK | 510 | 4 | 4 |
| gemini-4-argon | high | b2 | final | FAILED schema | 40 | - | - |
| gemini-4-argon | high | b3 | final | OK | 453 | 2 | 2 |
| gemini-4-hydrogen | high | b1 | final | FAILED schema | 24 | - | - |
| gemini-4-hydrogen | high | b2 | final | FAILED schema | 14 | - | - |
| gemini-4-hydrogen | high | b3 | final | FAILED schema | 104 | - | - |
| gemini-4-hydrogen | xhigh | b1 | final | FAILED schema | 30 | - | - |
| gemini-4-hydrogen | xhigh | b2 | final | FAILED schema | 15 | - | - |
| gemini-4-hydrogen | xhigh | b3 | final | FAILED schema | 160 | - | - |
| gemini-4-hydrogen | high | b1 | task | FAILED schema | 16 | - | - |

Every failed run ended the same way: agy reported `status: SUCCESS` with an
empty response and `denied_actions: [{"action":"command","display_name":"Bash"}]`,
and stderr said a tool needed the `command` permission that headless mode
cannot grant. The model reached for a shell, plan mode denied it, and agy
returned no review. The diff was in the prompt each time (the task run's
prompt embedded it as well). Argon did this only on b2's 9 MB diff; Hydrogen
did it on every run, at both efforts.

## Totals

- Argon high: 6 findings, 6 confirmed, unconfirmed share 0%; 2 of 3 final
  runs usable.
- Hydrogen high: 0 findings, 0 confirmed, unconfirmed share undefined (no
  findings); 0 of 3 final runs and 0 of 1 task run usable.
- Hydrogen xhigh: 0 findings, 0 confirmed; 0 of 3 final runs usable.

Hydrogen's effort by the rule: both efforts confirmed 0, a tie, so `high`.

## The rule at Hydrogen high

| Condition | Value | Result |
|---|---|---|
| All three final runs and the task run usable | 0 of 4 usable | fail |
| Confirmed total at least Argon's | 0 against 6 | fail |
| Unconfirmed share at most Argon's plus 10 points | undefined (no findings) against 10% | fail |
| Slowest run inside 2400 seconds | 104 s | pass |

Argon stays.

Verdict: gemini-4-argon high
