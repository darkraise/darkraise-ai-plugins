---
name: distilling-docs
description: Use when session notes, findings and gate reports have accumulated, or after a programme completes - distils them into four durable files and deletes the tracked sources it has absorbed, gated on an independent verification
---

# Distilling Docs

**Announce at start:** "I'm using the distilling-docs skill to distil <area> into the durable files."

Session notes accumulate until nothing reads them. This skill collapses them into
four durable files and deletes the sources it has absorbed — but only tracked,
clean, unreferenced Markdown, and only after an independent judge confirms every
fact survived. See [project-state.md](../../reference/project-state.md).

## The four files

Under `docs/superpowers/distilled/`, each an H1, a one-line statement of what
belongs in it, then `## <area>` sections holding `### <entry>` blocks.

**`distilled/constraints.md`** — rulings and policy that bind future work.
Fields: `Set by`, `Scope`, `Source`.

**`distilled/gotchas.md`** — the symptom leads, because that is how a session
recognises it is inside one. Fields: `Cause`, `Workaround`, `Verified`, `Source`.

**`distilled/reference.md`** — measured facts. Fields: `Measured`, `Authority`,
`Verified`, `Source`.

**`distilled/rejected.md`** — approaches a future session would re-propose.
Fields: `Tried`, `Why it looked right`, `Why it failed`, `Would change if`,
`Source`.

An example entry, from `gotchas.md`:

```markdown
### `bash: rg: command not found` in a test that greps
Cause: ripgrep is not on PATH in Git Bash on this machine; the suite assumes it
Workaround: use the Grep tool, or `fd`; this one discovery failure is environmental
Verified: 2026-09-11
Source: docs/superpowers/notes/2026-09-11-test-env.md@e4f5a6b
```

Every entry carries a `Source:` line: the file it came from and the short SHA of
the last commit that touched it, from `git log -1 --format=%h -- <path>`, captured
before deletion. Because only tracked, clean files are eligible, that SHA always
resolves and the original is one `git show` away, permanently.

**Size discipline.** A distilled file over 400 lines has become the wall it
replaced. The next wave begins by merging duplicate and obsolete entries; if it
is still over, split by area into `distilled/<area>-<kind>.md` with an index in
the original. Splitting happens during a wave's extraction, never after that
wave's judge has ruled.

## What may be deleted

Eligible by path and extension: Markdown files (`*.md`) under
`docs/superpowers/notes/` and `docs/superpowers/findings/`. Every non-Markdown
file under those paths is **never eligible** — captures and fixtures live there
too, and a judge whose tools are `Read, Grep, Glob, WebFetch` cannot enumerate
the facts in a binary, so `CARRIED` is unreachable for one by construction.

Three conditions, checked per file, all required:

1. **Tracked** — `git ls-files --error-unmatch <path>` succeeds. An untracked
   file has no SHA, cannot be `git rm`'d, and cannot be recovered by `git show`,
   so the recovery story below does not hold for it. This excludes gitignored
   conventions such as a `.reviews/` directory or archived handoffs; they are out
   of the eligible set entirely and this skill never proposes deleting them.
2. **Clean** — `git status --porcelain -- <path>` is empty. A file with
   uncommitted edits would get a `Source:` SHA pointing at older content while
   the content you actually distilled went unrecoverable. Commit it first, or
   leave it out of the wave.
3. **Unreferenced** — `git grep` over tracked files outside those two
   directories, plus the primary checkout's `.superpowers/handoff/latest.md`,
   finds neither the file's path, nor its basename, nor any **ancestor**
   directory path beneath those roots. The ancestor check matters: a plan naming
   a capture directory references every file in it without naming one.

**Never deleted**, whatever a judge says: specs, plans, `completed.md`, `README`,
`CLAUDE.md`, `AGENTS.md`, licence files, hand-written research anywhere else in
the repository (a `docs/reverse-engineering/` tree is research, not session
detritus), and anything failing one of the three conditions. Specs and plans
are read as sources and are never targets.

## Waves

Work on a branch (dr-superpowers:using-git-worktrees), in waves of **five to
fifteen** source files covering one area, never the whole tree. A wave fits one
session with room for the judge round, and is the unit at which work can stop:
git is the ledger, so a fresh session sees what remains from the distilled files
and the log.

Per wave: inventory the sources, apply the three conditions, classify each
survivor (durable-fact carrier, superseded by code or tests, or historical record
with nothing durable in it), extract into the four files, then verify.

## The verification gate

**Commit the extraction before the judge runs.** The first commit below lands
first, and the judge is given its SHA. A judge that reads uncommitted files can
be invalidated by any later edit — a merge, a split, or a fix made for another
file's verdict — and would then be attesting to text that no longer exists.

**The judge reads the working tree, not the commit.** `agents/judge-opus.md`
grants `Read, Grep, Glob, WebFetch` and **no Bash**, so it cannot run
`git show <sha>:<path>`. Committing first therefore binds the verdict only under
three conditions you must hold: the working tree is clean at that SHA when you
dispatch, nothing is edited until the verdict returns, and the verdict names the
SHA it was given. A verdict returned against an edited tree is void; re-judge.

Dispatch dr-superpowers:judge-opus with
[distil-judge.md](references/distil-judge.md). It must work in one order:
enumerate every fact in each source as a numbered list first, then map each
numbered fact to the entry that carries it, and only then return a verdict. A
judge that reads holistically grades the summary it was handed.

| Verdict | Meaning | Consequence |
|---|---|---|
| `CARRIED` | Every enumerated fact maps to a named distilled entry | Eligible for deletion |
| `MISSING` | An enumerated fact maps to nothing | Fix, re-commit, re-judge |
| `DISTORTED` | A fact was carried but its meaning changed | Fix, re-commit, re-judge |

Any edit after a verdict re-judges **every** file whose entries changed, not only
the one that prompted it.

## Deletion, in two kinds of commit

```
docs(<scope>): distil <area> notes            # adds the distilled entries - no deletions
docs(<scope>): remove absorbed <area> notes   # git rm only - no content changes
```

One or more distil commits — each `MISSING` or `DISTORTED` verdict produces
another — then **exactly one removal commit**, carrying only the files the judge
returned `CARRIED` against the committed content. Never combined, and
never squashed on integration: a squash collapses the two commits the recovery
story depends on, so merge with `--no-ff` or fast-forward. Reverting a bad
deletion is then one `git revert` that keeps the distillation.

## Re-runs

Entries merge rather than accumulate. A new fact that duplicates an existing entry
updates it and adds its `Source:` line. A new fact that **contradicts** one wins
only when it is both newer and carries evidence; otherwise report both to your
human partner and drop neither. A corpus holding two opposed facts is worse than
one holding neither. Every merge happens during extraction, before that wave's
commit and judge round.

A wave that edits entries carried by an **earlier** wave is editing facts whose
sources may already be deleted, and its own judge sees only its own sources. When
that happens, include the touched entry's diff and a `git show` extract of every
source named in its `Source:` lines in the dispatch, so the judge rules on the
rewrite too. Without that, a fact can be rewritten out of the corpus with no seat
having checked it.

## An external memory store

These files are repo-scoped, committed, and readable with no MCP server present:
they survive a fresh clone, reach a Codex session, and travel with the branch. An
external store holds cross-repo facts for one human's agents. They are not
substitutes, and a fact can belong in both — when one is available, offer to push
newly distilled constraints and gotchas there as well, and never do it silently.

## Red Flags

| Thought | Reality |
|---------|---------|
| "I read the whole notes directory, I can summarise it all" | Waves of five to fifteen. A summary written from a full context loses the specifics that made the note worth keeping. |
| "The judge will probably say CARRIED" | Dispatch it, against a commit. Deletion is gated on the verdict, not the expectation. |
| "This note is obviously superseded, I'll just delete it" | Three conditions, two kinds of commit, one judge. Nothing else deletes. |
| "It's only in a gitignored directory, deleting it is free" | It is untracked. Deleting it destroys it. It is not in the eligible set. |
| "One commit is tidier" | Two are what make the deletion revertible on its own. |
| "The spec says it, so I'll distil and delete the spec" | Specs and plans are sources, never targets. |
