# External task ownership and recovery

This protocol is for Claude-hosted Codex CLI offload only. Native Codex uses
[native-codex.md](native-codex.md). Keep the CLI model table separate from native
model metadata. Prerequisites are Bash, Git, jq, GNU timeout/coreutils, a working
Codex CLI, and successful bounded `codex login status` detection.

Reserve a linked Superpowers worktree for one task. Initial execution requires
a clean index and no tracked/untracked changes. Stop only controller-owned
competing writers; require user editing to cease in this worktree. The owner
record and per-run lock prevent cooperating invocations from sharing it, but
cannot attribute arbitrary concurrent writes. Do not force-clear uncertain locks.

Pass `--task-id` on every initial run, retry, and resume. Pass `--write-set` with
a JSON array of explicit create/modify/delete paths, relative to the worktree.
Include both ends of renames. Paths are literal; traversal and symlink escapes
are rejected. Additional paths require an approved recorded scope amendment.

The authoritative version-1 record lives under the worktree's Git directory:
`dr-superpowers/tasks/<Git-hash-of-task-id>/state.json`. It contains identities,
initial/expected HEAD, scope, model/effort/thread, attempt and review history,
process identities, phase, snapshots, artifacts, and the intended commit.
Report filenames do not identify tasks. Human reports must be outside the
checkout or inside its actually ignored `.superpowers` workspace.
Pass `--review-round <N>` on review-fix resumes; clarification resumes omit it.
Retries of the same review round preserve its number. The number cannot move
backwards, and neither clarification nor transport retries reset review history.

## Phase-dependent actions

- `ready`: validated initial task; it has not launched yet.
- `running`: writer may exist. Confirm child termination before any recovery.
  A launch interrupted before process identity was saved is uncertain, even
  when a PID or timestamp appears old.
- `pending`: a stopped incomplete run with an exact recorded scoped diff.
  A fresh retry may use a new thread; a fix resume must match the stored thread,
  model, effort, HEAD, and snapshot. Neither resets counters or history.
- `committing`: intended tree, parent, and subject are durable. Recover the
  commit rather than rerunning the model.
- `complete`: successful commit or no-change DONE, with a recorded thread.
  Review fixes may resume it. Finish review before releasing ownership.
- `blocked`: preserve files and inspect the error, prior phase, process records,
  and snapshot. Do not start another writer or delete this worktree.
- `handed-back`: ownership was transferred to Claude; the external task ID can
  never resume. Subsequent Claude work follows its own verification protocol.

Control operations never launch Codex:

```bash
bash <plugin-root>/scripts/run-codex-task.sh --cwd <worktree> --task-id <id> --recover-commit
bash <plugin-root>/scripts/run-codex-task.sh --cwd <worktree> --task-id <id> --handback
bash <plugin-root>/scripts/run-codex-task.sh --cwd <worktree> --task-id <id> --release
```

Commit recovery revalidates the pending snapshot and candidate. A commit already
created before a crash is adopted only on exact tree, parent, and subject match
with a clean worktree. Hook or staging failures preserve actual state for review.
Handback validates a complete/pending snapshot and confirmed child termination.
Release requires completed review and a clean complete task.

For scope amendments use `--amend-write-set <paths.json> --approval <approval.json>`.
For a manually repaired baseline use `--accept-baseline <snapshot.json> --approval
<approval.json>`. Generate the snapshot with the bundled `dr_snapshot` helper,
review it, then obtain approval. The approval JSON contains `task_id`, `operation`
(`amend-write-set` or `accept-baseline`), `file_hash` from `git hash-object
--no-filters <file>`, and `approval_reference` identifying the user's approval.
This is an auditable workflow record, not user authentication. History is retained.

Old runs without state require explicit manual reconciliation; an old report is
not ownership evidence. Unknown live writers or uncertain locks require manual
process reconciliation before these operations can proceed. Never use age alone
or broad process-name termination. Exit codes are 0 for DONE/control success,
1 for executed non-DONE, and 2 for preflight, persistence, staging, or commit
failure; the durable phase distinguishes failures before and after execution.
