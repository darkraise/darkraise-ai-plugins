# dr-superpowers Codex budget — open follow-ups

Nothing here blocks the merge. The final review triaged each as LEAVE or deferred it to your human partner. Items the final fix wave closed are not listed.

- Final review: the Claude-host budget line now runs `ctx_find_rollout` on every call, up to 40 rollout files with one jq spawn each whenever `~/.codex/sessions` exists. Correct but slow on Windows; comparing the Claude transcript's mtime with the newest rollout before any jq work would skip the walk (own change, own test).
- Final review: log rows carry no plan identity, so two plans briefed in one session pair as if consecutive (spec §7 accepted it); a fifth column would fix it.
- Final review: an interactive Codex session in the same directory that wrote more recently than a live Claude transcript takes the Claude line's verdict (spec-sanctioned; document or leave).
- Final review: `plugins/dr-superpowers/README.md` does not mention the Codex measurement or `context-size --observations`.
- Final review: no version bump — both manifests still read 1.14.0, which 5aa3db0 already released.
- Task 3: a fractional `input_tokens` would fail the `tk` arithmetic under `set -u` on the rollout branch and the pre-existing Claude branch; latent, Codex writes integers.
- Task 4: `ctx_log_observation` has no guard for an empty `ctx_primary_root`; no assertion checks field 1's ISO-8601 format; the workspace path and self-ignore literal duplicate `scripts/sdd-workspace`.
- Task 4 (parked): `ctx_primary_root` repeats `ctx_candidates`' two-line git-common-dir walk; deduplicating would touch the Claude path.
- Task 2: the `ctx_find_rollout` comment says the walk stops early, but `sort -r` is a full barrier (only the per-day `ls -t` and jq spawns are bounded); the `grep -qxF` path match is case-sensitive, so a differently cased drive letter degrades to `unknown`; three `discovery:` negative assertions check only exit 1.
- Task 6: `session-budget.md` reads "or `guessed` … or, on a Codex host, `rollout`" with a doubled "or", and "followed by one `span` line per session" can read as all deltas first.
