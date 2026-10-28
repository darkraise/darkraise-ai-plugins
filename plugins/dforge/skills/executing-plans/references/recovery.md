# Recovery and plan state

**Recovery.** For task N, take the last line in file order among its
`Task <N>:` lines, stepping over `minor (deferred)`, `parked`,
`Task <N>: Ruling:` and bare `Ruling:` lines. Then:

| Last line | Action |
|---|---|
| `complete` | Done; never redo |
| `BLOCKED` | Terminal. It is a stop of the fourth class for any task that depends on it; name it in your final message |
| `escalated inline -> subagent` | This plan has left inline mode: use dforge:subagent-driven-development |
| `fix round R/3 (…; passing)` | Re-run the task's verifications; if they pass, commit anything uncommitted and write the complete line, else treat as `still failing` |
| `fix round R/3 (…; still failing)`, R < 3 | Resume the loop at round R+1 |
| `fix round 3/3 (…; still failing)` | Go to Switching to subagent mode |
| `implementer inline (assigned; base <sha7>)` | If `git log <base>..HEAD` is non-empty, re-run the task's verifications and finish it from where those commits leave it; otherwise start the task |
| An agent-named `implementer <agent> (assigned …)` line, or `fix round R/2` (a Codex plan's `fix round R/5`) | A delegated task: apply [delegated-task.md](../../../reference/delegated-task.md) §Recovery |
| none | Not started |

**Plan state.** First, whatever the per-task lines say: if the ledger holds a
`Task <N>: escalated inline -> subagent` line with no later
`implementer inline (assigned` line after it, this plan has left inline mode -
use dforge:subagent-driven-development, exactly as `scripts/next-step`
reads the same ledger. Otherwise: every task complete and no `Final review:`
line: go to Final Review. A `Final review: clean` line: go to
dforge:finishing-a-development-branch.
