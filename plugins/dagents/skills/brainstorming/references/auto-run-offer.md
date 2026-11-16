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

When the `worktree` setting is `ask` (read as Settings says), the block's
options are instead:

```
1. Yes, in an isolated worktree
2. Yes, in place on a new branch (leave this checkout alone until the run finishes)
3. No, keep the normal stops
```

On yes, run `scripts/auto-run start --spec <the spec's path> --isolation <worktree|in-place>` (add
`--register <path>` when an item register is open) from this checkout, before
writing the spec, and follow [auto-run.md](../../../reference/auto-run.md) from
here to the finished branch. The isolation is `worktree` for option 1, and for
yes under `worktree=always`; option 2 passes
`--isolation in-place`, as yes under `worktree=never` does. A preference your
human partner's instructions name outranks the setting. On exit 2 or 4, say
why in one line and continue without an auto run. On no, continue as below.
