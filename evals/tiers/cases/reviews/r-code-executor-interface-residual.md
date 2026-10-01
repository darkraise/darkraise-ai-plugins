# r-code-executor-interface-residual

Source: the final-residual fix commit `16752f6`, reviewed at head `58885f9`.

## D1: the session library swallows the registry helper's diagnostic

- Where: `plugins/dr-superpowers/scripts/lib/executor-session.sh`, `_executor_session_field`
- Defect: the helper call ends in `2>/dev/null`, so a malformed registry entry, which is an installation fault, turns the lane off with no message saying why.
- Evidence: `16752f6` removes the redirection and adds tests that a malformed entry still fails closed and says why on stderr.
- Minimum severity: Important

## D2: the generic failure rules name the `codex-successor` block

- Where: `plugins/dr-superpowers/reference/executor-lane.md`, "The successor column is never consulted" and the failure table's fix-round row
- Defect: both state the rule for every executor but name the Codex block `codex-successor`, although an executor's successor block is whatever its registry entry names in `blocks.successor`.
- Evidence: `16752f6` rewrites both as "that executor's successor block (`executors get <id> blocks.successor`)".
- Minimum severity: Important
