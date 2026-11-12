# Codex notes

## Older layout check

Codex runs no session-start hook, so nothing reports a repository or home that
still uses an older layout. Run
`bash <plugin-root>/scripts/dforge-migrate --dry-run` once at the start of a
session; if it names anything it would move, use the `dforge:migrate` skill
before any other work.

## darkmem at session start

Codex runs no hooks. In a repository that syncs with darkmem
(`bash <plugin-root>/scripts/dforge-path project` prints its project), or one
with a family still in the mirror (`bash <plugin-root>/scripts/dforge-path store`
names `darkmem`), start each session with
`bash <plugin-root>/scripts/darkmem-sync reconcile`, then `bash <plugin-root>/scripts/darkmem-sync pull`,
and read what they print: a `darkmem-sync reconcile:` line names a family
that moved or stayed and why. At the stop points
[project-state.md](../../../reference/project-state.md) §darkmem sync points
names, run `bash <plugin-root>/scripts/darkmem-sync push`;
nothing pushes for you at the end of a turn.
