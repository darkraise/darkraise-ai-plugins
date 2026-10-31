# Test tiers

The three tiers split one project's test cost between three places. The Task
check tier runs in the controller's per-task loop. The Full suite tier is the
full run. The Sweep tier runs in CI.

## The three tiers

| Tier | Command source | Runs |
|---|---|---|
| Task check | the plan header's `**Task check:**` line | beside every task review, every fix round, and inline before every task commit |
| Full suite | the plan header's `**Integration check:**` line | each wave's merged check, tasks whose number is a multiple of 3 (and the last task) when the task check is `none`, the final review, the fix wave, finishing |
| Sweep | the project's CI | after the push |

## Impact selection

| Tool | Selects |
|---|---|
| pytest-testmon | tests whose recorded coverage touches changed code |
| `jest --changedSince=<base>` / `--onlyChanged` | tests importing changed files |
| `vitest --changed <base>` | the same, for Vitest |
| `nx affected -t test` | projects downstream of the change |
| bazel-diff, target-determinator | Bazel targets downstream of the change |
| `go test` on changed packages and their importers | `go list -deps` gives the graph |
| Gradle build cache with `--continue` | skips tasks whose inputs did not change |

Selection serves the Task check tier only. The Full suite and Sweep tiers
still run what they declare, which is what catches a dependency the selector
missed.
