**Offering an auto run:**

Unless `autoRun=off` (see Settings) or this is a Codex host, ask this once, as
its own message, right after the Draft acceptance step and before you
write the spec. `<finish>` follows the `finishAction`
setting (`scripts/dforge-config get finishAction`): `merge` reads "merge to
<the current branch>", `pr` reads "open a pull request", and `keep`, `ask` and
`wait` read "keep the branch".

```
Run the rest unattended? Spec → Fable spec review → plan → execution →
final review → finish (<finish>).
I won't ask anything else: undecided items go to Opus, then to Fable in
batches, and what neither settles goes on the deferred list.

1. Yes, run unattended
2. No, keep the normal stops

Which option?
```

On yes, run `scripts/auto-run start --spec <the spec's path>` (add
`--register <path>` when an item register is open) from this checkout, before
writing the spec, and follow [auto-run.md](../../../reference/auto-run.md) from
here to the finished branch. On exit 2 or 4, say why in one line and continue
without an auto run. On no, continue as below.
