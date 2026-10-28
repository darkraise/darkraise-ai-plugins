# Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "Tests passed earlier this session" | Run the suite on the tree you are about to integrate. A green run only proves the tree it ran on. |
| "They obviously want it merged" | Integration is your human partner's decision. Present the menu and wait; only the choice they made before the run acts for them, and it acts at once. |
| "I'll ask for the merge in prose" | A request buried in a long report goes unseen. The three-option menu, verbatim, is the last thing in the message. |
| "The open findings are in my report" | The report scrolls away and Step 6 deletes the ledger. Commit them in the followups note. |
| "They seem done with this feature — I'll offer to discard it" | The menu is complete as written. Discard happens only when your human partner asks for it in so many words. |
| "'Yeah, get rid of it' counts as confirmation" | Only the typed word `discard` authorizes deletion. |
| "The PR is up, so the worktree is clutter now" | PR feedback gets fixed in that worktree. It stays until the work lands. |
| "This other worktree looks stale — I'll clean it too" | Clean up only worktrees under `.worktrees/` or `worktrees/`. Everything else belongs to the host. |
| "Removal refused — `--force` is just finishing the cleanup" | The refusal means files exist only in that worktree. `--force` destroys them permanently. Show your human partner and ask. |
| "The merged-result failure is probably flaky" | A failing merged result stops everything. Branch and worktree stay put while you investigate. |
| "The base branch is obviously main" | Confirm the fork point or ask, unless Step 4 carries out a choice recorded before the run, which takes its base from the record, the plan, the conversation or the upstream. Merging into the wrong base is expensive to undo. |
| "The push was rejected — force-push will fix it" | A rejected push means the remote moved. Investigate; force-push only on your human partner's explicit request. |
| "I printed the rulings and the review — that wraps up the run" | Without the menu or a recorded choice nothing integrates. With no recorded choice the options close the message, every time; a run that carried out its choice ends on the next-step block. |
| "I summarized the outcome — the next step is obvious" | Not to a fresh session or a partner who stepped away. End with the `next-step` block, verbatim. |
