# r-code-judge-seats

Source: the final-review fix commits `fb05b23` and `6d54b1e`, reviewed at head `f88429b`.

## D1: the refusal search matches any line of the whole transcript

- Where: `plugins/dr-superpowers/scripts/run-codex-review.sh`, `is_refusal`
- Defect: `is_refusal` greps both whole log files, unanchored and case-insensitively, for words such as "unsupported ... model" and for `http 400` or `status 400`. Codex writes its session transcript, including every file the model read, to those logs, so a run that merely quotes a refusal message is declared a refusal and buys a second full round on the fallback rung.
- Evidence: `fb05b23` restricts the search to column-0 `ERROR:` lines and JSON error events (`error_lines`) and drops the bare `400` patterns.
- Minimum severity: Important

## D2: the refusal reason is the CLI banner, not the refusing line

- Where: `plugins/dr-superpowers/scripts/run-codex-review.sh`, `refusal_line`
- Defect: `refusal_line` returns the first non-empty line of stderr followed by stdout, which is the CLI banner, so every substitution is reported as refused for the banner text instead of the line that matched.
- Evidence: `fb05b23` makes `refusal_line` read the first of the same error-shaped lines `is_refusal` matched.
- Minimum severity: Important

## D3: a fail-closed selection of the fallback rung is not reported as a substitution

- Where: `plugins/dr-superpowers/reference/external-executor.md`, the review-seat and final-review round sections
- Defect: the reference tells the controller to announce a substitution only on `FALLBACK`. When the catalog does not advertise the preferred rung, selection falls closed to the block's last row before the run and the status line says `status=OK`, so the substitution passes unannounced.
- Evidence: `fb05b23` adds a paragraph to both sections: a status line naming the block's last row with `status=OK` is a substitution too, said aloud with its `evidence=` value.
- Minimum severity: Important

## D4: no test proves which model reaches the command

- Where: `plugins/dr-superpowers/tests/codex-review.test.sh`, the dry-run selection cases
- Defect: both judge rows run at the same effort, and the tests assert only the effort and the printed `codex-judge` line, so a runner that printed one model and passed another to `-m` would pass.
- Evidence: `fb05b23` adds a token check that the selected model reaches `-m` in each of the four selection cases.
- Minimum severity: Important

## D5: the test stub's refusal is not the form Codex emits, and prose mentioning a refusal is untested

- Where: `plugins/dr-superpowers/tests/codex-review.test.sh`, the stub's `refuse-then-ok` and `refuse-always` modes
- Defect: the stub refuses with `stream error: unsupported model …`, a line real Codex never writes, so the tests pass against a matcher that would misread real output; and no case covers a failed run whose output only mentions a refusal.
- Evidence: `fb05b23` changes the stub to the observed column-0 `ERROR: {"type":"error",…}` line and adds the `prose-fail` case; `6d54b1e` corrects that line's quoting.
- Minimum severity: Important
